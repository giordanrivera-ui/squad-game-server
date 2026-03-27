const express = require('express');
const http = require('http');
const { Server } = require('socket.io');
const admin = require('firebase-admin');
const app = express();
const server = http.createServer(app);

const io = new Server(server, { 
  cors: { origin: "*" },
  pingTimeout: 10000,  // NEW: 10 sec timeout before disconnect
  pingInterval: 5000   // NEW: Ping every 5 sec to check alive
});

const { properties, handleBuyProperty, handleBuyUpgrade, handleClaimIncome } = require('./properties.js');
const { handleKillAttempt, markPlayerAsDead, getRankTitle } = require('./combat.js');
const { handleExecuteOperation } = require('./operations.js');
const { handleRequestBondMarket, handleRefreshBondMarket, handleBuyBond, startBondMaturityChecker } = require('./bonds.js');
const { vehicleTemplates, handleRequestVehicles, handlePurchaseVehicles } = require('./vehicles.js');

// Firebase Admin
const serviceAccount = JSON.parse(process.env.FIREBASE_SERVICE_ACCOUNT);
admin.initializeApp({
  credential: admin.credential.cert(serviceAccount)
});

const db = admin.firestore();

// ==================== CENTRALIZED EXP + ATTRIBUTE POINTS HELPER ====================
async function addExperienceAndGrantPoints(docRef, playerData, amount) {
  const oldExp = playerData.experience || 0;
  playerData.experience = oldExp + amount;

  const oldRank = getRankTitle(oldExp);
  const newRank = getRankTitle(playerData.experience);

  if (newRank !== oldRank && playerData.experience > oldExp) {
    if (playerData.unallocatedAttributePoints === undefined) playerData.unallocatedAttributePoints = 0;
    playerData.unallocatedAttributePoints += 3;
    console.log(`[SERVER] Rank-up: ${oldRank} → ${newRank} | +3 points (total: ${playerData.unallocatedAttributePoints})`);
  }

  return playerData;   // IMPORTANT: returns the updated object
}

// ==================== MARKSMANSHIP BONUS HELPER ====================
// +1% overall power per Marksmanship point (only when weapon equipped)
function recalculateOverallPower(p) {
  if (!p.weapon || !p.weapon.power) {
    p.overallPower = 0;
    return p;
  }
  const marksmanship = p.marksmanship || 0;
  const bonus = 1 + (marksmanship / 100);
  p.overallPower = Math.round(p.weapon.power * bonus);
  return p;
}

// ==================== ONLINE LIST HELPER (NEW) ====================
function removeFromOnlineList(displayName) {
  if (!displayName) return;
  onlinePlayers.delete(displayName);
  onlineSockets.delete(displayName);
  io.emit('online-players', Array.from(onlinePlayers));
  console.log(`[SERVER] ${displayName} removed from online list (death or cleanup)`);
}

// ==================== GLOBAL PRISON LIST ====================
const imprisonedPlayers = new Map(); // Key: displayName, Value: prisonEndTime

// ==================== IMPROVED TRANSACTION LOGGER (Server-side persistence) ====================
async function logTransaction(socket, amount, description, playerData, docRef) {
  if (!socket || typeof amount !== 'number' || !playerData || !docRef) {
    console.warn('[TX] Invalid logTransaction call - missing params');
    return;
  }

  const newBalance = (playerData.balance || 0) + amount;

  const txData = {
    amount: amount,
    description: description,
    balanceAfter: Math.round(newBalance),
    timestamp: admin.firestore.FieldValue.serverTimestamp()
  };

  // Live update to client (for immediate UI)
  socket.emit('new-transaction', {
    amount: amount,
    description: description,
    balanceAfter: Math.round(newBalance)
  });

  // Permanent storage on server (always succeeds, uses admin SDK)
  try {
    await docRef.collection('transactions').add(txData);
    console.log(`[TX SAVED] ${description} | $${amount} → Balance: $${newBalance}`);
  } catch (err) {
    console.error('[TX ERROR] Failed to save transaction:', err);
  }
}

// ==================== AUTO-CLEANUP EXPIRED PRISONERS ====================
// Runs every second and removes anyone whose time is up.
// This keeps the global list clean and enables future rescue mechanics.
setInterval(() => {
  const now = Date.now();
  let changed = false;

  for (const [displayName, prisonEndTime] of imprisonedPlayers.entries()) {
    if (prisonEndTime <= now) {
      imprisonedPlayers.delete(displayName);
      changed = true;
      console.log(`[SERVER] ${displayName} has been released from prison (auto-cleanup)`);
    }
  }

  if (changed) {
    const prisonList = Array.from(imprisonedPlayers, ([displayName, prisonEndTime]) => ({
      displayName,
      prisonEndTime
    }));
    io.emit('prison-list-update', {
      list: prisonList,
      serverTime: Date.now()
    });
  }
}, 1000);

// ==================== AUTO-CLEANUP EXPIRED HITS ====================
setInterval(async () => {
  try {
    const now = Date.now();
    const expiredHits = await db.collection('hitlist')
      .where('endTime', '<', now)
      .where('active', '==', true)
      .get();

    const batch = db.batch();
    for (const doc of expiredHits.docs) {
      // Inside the for (const doc of expiredHits.docs) loop, replace the refund block with this:
      const hitData = doc.data();
      batch.update(doc.ref, { active: false });

      // Refund if unclaimed
      const posterDocRef = db.collection('players').doc(hitData.posterEmail);  // Use ref for updates
      const posterDoc = await posterDocRef.get();  // Initial fetch (optional, but keep for exists check)
      if (posterDoc.exists) {
        await posterDocRef.update({ balance: admin.firestore.FieldValue.increment(hitData.reward) });  // Update using ref
        console.log(`[SERVER] Refunded $${hitData.reward} to ${hitData.posterEmail} for expired hit on ${hitData.target}`);

        // NEW: Re-fetch fresh data after update
        const updatedPosterDoc = await posterDocRef.get();
        const updatedPosterData = updatedPosterDoc.data();

        // Notify poster if online
        const posterSocket = onlineSockets.get(updatedPosterData.displayName);  // Use fresh name if needed
        if (posterSocket) {
          posterSocket.emit('hit-expired', { 
            target: hitData.target, 
            reward: hitData.reward 
          });
          posterSocket.emit('update-stats', updatedPosterData);  // Emit FRESH data
        }
      }
    }
    await batch.commit();

    if (!expiredHits.empty) {
      io.emit('hitlist-update'); // Refresh everyone's hitlist
    }
  } catch (error) {
    console.error('Error in hit cleanup: ', error);
  }
}, 2000); // Check every 2 seconds

const normalLocations = [ // ==================== LOCATIONS ====================
  "Riverstone", "Thornbury", "Vostokgrad", "Eichenwald", "Montclair",
  "Valleora", "Lónghǎi", "Sakuragawa", "Cawayan Heights"
];

const travelCosts = { // ==================== TRAVEL COSTS ====================
  "Riverstone": 40, "Thornbury": 45, "Vostokgrad": 110, "Eichenwald": 60,
  "Montclair": 85, "Valleora": 70, "Lónghǎi": 140, "Sakuragawa": 95,
  "Cawayan Heights": 55
};

// ==================== ONLINE PLAYERS TRACKING ====================
const onlinePlayers = new Set();
const onlineSockets = new Map();

// ==================== AUTO BOND MATURITY (8 MINUTES) - Runs every 30 seconds ====================
startBondMaturityChecker(db, { onlineSockets });

const timeFormatter = new Intl.DateTimeFormat('en-GB', { 
  timeZone: 'Europe/London', 
  hour: '2-digit', 
  minute: '2-digit', 
  hour12: false 
});

setInterval(() => {
  io.emit('time', timeFormatter.format(new Date()));
}, 30000);

io.on('connection', (socket) => {
  socket.on('register', async (data) => {
    const email = data.email;
    const displayName = data.displayName || 'Anonymous';

    if (!email) return;

    const docRef = db.collection('players').doc(email);
    const doc = await docRef.get();

    let playerData;

    if (doc.exists) {
      playerData = doc.data();
      if (playerData.experience === undefined) playerData.experience = 0;
      if (playerData.intelligence === undefined) playerData.intelligence = 0;
      if (playerData.skill === undefined) playerData.skill = 0;
      if (playerData.marksmanship === undefined) playerData.marksmanship = 0;
      if (playerData.stealth === undefined) playerData.stealth = 0;
      if (playerData.defense === undefined) playerData.defense = 0;
      if (playerData.bullets === undefined) playerData.bullets = 0;
      if (playerData.photoURL === undefined) playerData.photoURL = '';
      if (playerData.inventory === undefined) playerData.inventory = [];
      if (playerData.headwear === undefined) playerData.headwear = null;
      if (playerData.armor === undefined) playerData.armor = null;
      if (playerData.footwear === undefined) playerData.footwear = null;
      if (playerData.overallPower === undefined) playerData.overallPower = 0;
      if (playerData.weapon === undefined) playerData.weapon = null;
      if (playerData.lastLowLevelOp === undefined) playerData.lastLowLevelOp = 0;
      if (playerData.prisonEndTime === undefined) playerData.prisonEndTime = 0;
      if (playerData.lastMidLevelOp === undefined) playerData.lastMidLevelOp = 0;
      if (playerData.lastHighLevelOp === undefined) playerData.lastHighLevelOp = 0;
      if (playerData.sellBanEndTime === undefined) playerData.sellBanEndTime = 0;
      if (playerData.ownedBonds === undefined) playerData.ownedBonds = [];
      if (playerData.ownedProperties === undefined) playerData.ownedProperties = [];
      if (playerData.ownedUpgrades === undefined) playerData.ownedUpgrades = {};
      if (playerData.lastIncomeClaim === undefined) playerData.lastIncomeClaim = Date.now();
      if (playerData.propertyClaims === undefined) playerData.propertyClaims = [];
      if (playerData.showArmor === undefined) playerData.showArmor = true;
      if (playerData.showWeapon === undefined) playerData.showWeapon = true;
      if (playerData.hasBrokenBone === undefined) playerData.hasBrokenBone = false;
      if (playerData.bonePenaltyEndTimeLow === undefined) playerData.bonePenaltyEndTimeLow = 0;
      if (playerData.bonePenaltyEndTimeMid === undefined) playerData.bonePenaltyEndTimeMid = 0;
      if (playerData.bonePenaltyEndTimeHigh === undefined) playerData.bonePenaltyEndTimeHigh = 0;
      if (playerData.dead === undefined) playerData.dead = false;
      if (playerData.unallocatedAttributePoints === undefined) playerData.unallocatedAttributePoints = 0;
      if (playerData.taxiFleet === undefined) playerData.taxiFleet = [];

      if (playerData.weapon) {
        playerData = recalculateOverallPower(playerData);
      }

      if (playerData.displayName) {
        playerData.displayNameLower = playerData.displayName.toLowerCase();
      }

      // IMPORTANT: Never restore name for dead players
      if (!playerData.displayName && playerData.dead !== true && displayName !== 'Anonymous') {
        playerData.displayName = displayName;
        playerData.displayNameLower = displayName.toLowerCase();
      }

      await docRef.set(playerData);
    } else {
      const randomLocation = normalLocations[Math.floor(Math.random() * normalLocations.length)];

      playerData = {
        balance: 0,
        health: 100,
        bullets: 0,
        lastRob: 0,
        displayName: displayName,
        displayNameLower: displayName.toLowerCase(),
        location: randomLocation,
        messages: [],
        fcmTokens: [],
        experience: 0,
        intelligence: 0,
        skill: 0,
        marksmanship: 0,
        stealth: 0,
        defense: 0,
        kills: 0,
        photoURL: '',
        inventory: [],
        headwear: null,
        armor: null,
        footwear: null,
        overallPower: 0,
        weapon: null,
        lastLowLevelOp: 0,
        lastMidLevelOp: 0,
        lastHighLevelOp: 0,
        sellBanEndTime: 0,
        prisonEndTime: 0,
        ownedBonds: [],
        ownedProperties: [],
        lastIncomeClaim: Date.now(),
        propertyClaims: [],
        showArmor: true,
        showWeapon: true,
        hasBrokenBone: false,
        bonePenaltyEndTimeLow: 0,
        bonePenaltyEndTimeMid: 0,
        bonePenaltyEndTimeHigh: 0,
        dead: false,
        ownedUpgrades: {},
        unallocatedAttributePoints: 0,
        taxiFleet: [],
      };
    }

    if (playerData.displayName) {
      const name = playerData.displayName;
      // Check usedNames
      const usedNameDoc = await db.collection('usedNames').doc(name.toLowerCase()).get();
      if (usedNameDoc.exists) {
        // Reject or handle - for now, log and don't save name
        console.log(`[SERVER] Attempt to reuse taken name ${name} by ${email}`);
        socket.emit('error', { message: 'Name already taken forever.' });
        return;  // Don't proceed
      }
      // Also check players for active (though client did, server double-check)
      const playersQuery = await db.collection('players').where('displayName', '==', name).get();
      if (!playersQuery.empty && playersQuery.docs[0].id !== email) {  // Allow same email if respawn, but per task, block even same
        socket.emit('error', { message: 'Name already in use.' });
        return;
      }
    }

    await docRef.set(playerData);

    // ==================== Handle dead players FIRST ====================
    socket.data.email = email;
    socket.data.displayName = playerData.displayName || displayName;

    if (playerData.dead === true || (playerData.health ?? 100) <= 0) {
      // Force death screen and REMOVE from online list
      socket.emit('player-died');
      removeFromOnlineList(playerData.displayName || displayName);
      console.log(`[SERVER] ${playerData.displayName || email} reconnected while dead — forcing death screen`);
      return;  // IMPORTANT: Do NOT add them back to online list
    }
    onlinePlayers.add(socket.data.displayName);
    onlineSockets.set(socket.data.displayName, socket);

    io.emit('online-players', Array.from(onlinePlayers));

    console.log(`[SERVER] ${socket.data.displayName} joined - online now: ${onlinePlayers.size}`);


    socket.emit('init', {
      player: playerData,
      locations: normalLocations,
      travelCosts: travelCosts,
      properties: properties,
      vehicles: vehicleTemplates,
    });
    socket.emit('time', timeFormatter.format(new Date()));
  });

// ==================== RESPAWN HANDLER ====================
socket.on('respawn', async () => {
  const email = socket.data.email;
  if (!email) return;

  const docRef = db.collection('players').doc(email);
  const doc = await docRef.get();
  if (!doc.exists) return;

  let p = doc.data();

  if (p.dead) {
    const oldName = p.displayName;
    if (oldName) {
      // Save dead profile snapshot BEFORE reset
      const deadProfile = {
        displayName: oldName,
        displayNameLower: oldName.toLowerCase(),
        experience: p.experience || 0,
        balance: p.balance || 0,
        headwear: p.headwear || null,
        armor: p.armor || null,
        footwear: p.footwear || null,
        weapon: p.weapon || null,
        overallPower: p.overallPower || 0,
        deathTime: admin.firestore.FieldValue.serverTimestamp(),
        originalEmail: email
      };
      await db.collection('deadProfiles').doc(oldName.toLowerCase()).set(deadProfile);
      console.log(`[SERVER] Saved dead profile for ${oldName}`);

      // Add old name to usedNames
      await db.collection('usedNames').doc(oldName.toLowerCase()).set({
        name: oldName,
        taken: true,
        originalEmail: email,
        takenAt: admin.firestore.FieldValue.serverTimestamp()
      });
    }

    // === NEW: COMPLETELY WIPE TRANSACTION HISTORY ===
    const txSnapshot = await docRef.collection('transactions').get();
    if (!txSnapshot.empty) {
      const batch = db.batch();
      txSnapshot.docs.forEach((txDoc) => {
        batch.delete(txDoc.ref);
      });
      await batch.commit();
      console.log(`[SERVER] Respawned ${email} - wiped ${txSnapshot.size} old transactions (new life = clean slate)`);
    }

    // Reset stats to defaults
    const randomLocation = normalLocations[Math.floor(Math.random() * normalLocations.length)];
    p = {
      ...p,
      balance: 0,
      health: 100,
      bullets: 0,
      lastRob: 0,
      displayName: null,
      displayNameLower: null,
      location: randomLocation,
      experience: 0,
      intelligence: 0,
      skill: 0,
      marksmanship: 0,
      stealth: 0,
      defense: 0,
      kills: 0,
      photoURL: '',
      inventory: [],
      headwear: null,
      armor: null,
      footwear: null,
      overallPower: 0,
      weapon: null,
      lastLowLevelOp: 0,
      lastMidLevelOp: 0,
      lastHighLevelOp: 0,
      sellBanEndTime: 0,
      prisonEndTime: 0,
      ownedBonds: [],
      ownedProperties: [],
      lastIncomeClaim: Date.now(),
      propertyClaims: [],
      showArmor: true,
      showWeapon: true,
      hasBrokenBone: false,
      bonePenaltyEndTimeLow: 0,
      bonePenaltyEndTimeMid: 0,
      bonePenaltyEndTimeHigh: 0,
      dead: false,
      ownedUpgrades: {},
      unallocatedAttributePoints: 0,
      taxiFleet: [],
    };

    await docRef.set(p);
    socket.emit('update-stats', p);
    console.log(`[SERVER] Respawned ${email} - old name ${oldName} marked used`);
  }
});

  // ==================== TEST BUTTONS ====================
  socket.on('add-test-exp', async (amount) => {
    const email = socket.data.email;
    if (!email || typeof amount !== 'number') return;

    const docRef = db.collection('players').doc(email);
    const doc = await docRef.get();
    if (!doc.exists) return;

    let p = doc.data();
    p = await addExperienceAndGrantPoints(docRef, p, amount);

    await docRef.set(p);
    socket.emit('update-stats', p);
  });

  socket.on('add-test-money', async (amount) => {
    const email = socket.data.email;
    if (!email || typeof amount !== 'number') return;

    const docRef = db.collection('players').doc(email);
    const doc = await docRef.get();
    if (!doc.exists) return;

    let p = doc.data();

    await logTransaction(socket, amount, 'Test Money Added', p, docRef);   // p = playerData, docRef = the Firestore reference

    p.balance = (p.balance || 0) + amount;

    await docRef.set(p);
    socket.emit('update-stats', p);
  });

  socket.on('add-test-bullets', async (amount) => {
    const email = socket.data.email;
    if (!email || typeof amount !== 'number') {
      console.log(`[SERVER ERROR] Invalid add-test-bullets: email=${email}, amount=${amount}`);
      return;
    }

    console.log(`[SERVER] Processing add-test-bullets for ${email}, adding ${amount}`);

    const docRef = db.collection('players').doc(email);
    const doc = await docRef.get();
    if (!doc.exists) {
      console.log(`[SERVER ERROR] No player doc for ${email}`);
      return;
    }
  
    let p = doc.data();
    const oldBullets = p.bullets || 0;
    p.bullets = oldBullets + amount;
    console.log(`[SERVER] Updated bullets for ${email}: ${oldBullets} -> ${p.bullets}`);

    try {
      await docRef.set(p);
      socket.emit('update-stats', p);
      console.log(`[SERVER] Sent update-stats to ${email}`);
    } catch (error) {
      console.log(`[SERVER ERROR] Failed to save/update for ${email}: ${error}`);
    }
  });

  // ==================== ASSIGN TO TAXI FLEET ====================
  socket.on('assign-to-fleet', async (vehicle) => {
    const email = socket.data.email;
    if (!email || !vehicle || !vehicle.name) {
      socket.emit('fleet-result', { success: false, message: 'Invalid vehicle' });
      return;
    }

    const docRef = db.collection('players').doc(email);
    const doc = await docRef.get();
    if (!doc.exists) return;

    let p = doc.data();

    // Find and remove from inventory
    const index = p.inventory.findIndex(v => 
      v.name === vehicle.name && 
      v.power === vehicle.power && 
      v.health === (vehicle.health || 100)
    );

    if (index === -1) {
      socket.emit('fleet-result', { success: false, message: 'Vehicle not found in inventory' });
      return;
    }

    const assignedVehicle = p.inventory.splice(index, 1)[0];

    // Ensure taxiFleet exists
    if (!p.taxiFleet) p.taxiFleet = [];

    // Add to fleet
    p.taxiFleet.push(assignedVehicle);

    await docRef.set(p);

    // Live update
    socket.emit('update-stats', p);
    socket.emit('fleet-result', { 
      success: true, 
      message: `${assignedVehicle.name} assigned to your taxi fleet!` 
    });
  });

  // ==================== REMOVE FROM TAXI FLEET (FINAL SAFE MULTI-SELECT) ====================
socket.on('remove-from-fleet', async (payload) => {
  const email = socket.data.email;
  if (!email) {
    socket.emit('fleet-result', { success: false, message: 'Not logged in' });
    return;
  }

  // Support both old direct-array calls (if any) and the new wrapped format
  let vehiclesToRemove = payload?.vehicles || payload;

  // Normalize input
  let items = Array.isArray(vehiclesToRemove) ? vehiclesToRemove : [vehiclesToRemove];
  if (items.length === 0) {
    socket.emit('fleet-result', { success: false, message: 'No vehicles selected' });
    return;
  }

  const docRef = db.collection('players').doc(email);
  const doc = await docRef.get();
  if (!doc.exists) {
    socket.emit('fleet-result', { success: false, message: 'Player not found' });
    return;
  }

  let p = doc.data();
  if (!p.taxiFleet) p.taxiFleet = [];
  if (!p.inventory) p.inventory = [];

  const removedVehicles = [];

  // ← Fast lookup using composite key (unchanged)
  const toRemoveKeys = new Set();
  items.forEach(item => {
    const key = `${item.name}|${item.power}|${item.health ?? 100}`;
    toRemoveKeys.add(key);
  });

  p.taxiFleet = p.taxiFleet.filter(v => {
    const vHealth = v.health ?? 100;
    const key = `${v.name}|${v.power}|${vHealth}`;

    if (toRemoveKeys.has(key)) {
      removedVehicles.push(v);
      return false;
    }
    return true;
  });

  if (removedVehicles.length > 0) {
    p.inventory = [...p.inventory, ...removedVehicles];

    await docRef.set(p);

    socket.emit('update-stats', p);
    socket.emit('fleet-result', { 
      success: true, 
      message: `${removedVehicles.length} vehicle(s) moved back to inventory` 
    });
  } else {
    socket.emit('fleet-result', { success: false, message: 'No matching vehicles found to remove' });
  }
});

  // ====================== KILL ATTEMPT ======================
  socket.on('attempt-kill', async (data) => {
    await handleKillAttempt(db, socket, data, { 
      onlineSockets, 
      onlinePlayers, 
      io,
      removeFromOnlineList
    });
  });

  // ==================== PLACE HIT (BOUNTY) ====================
  socket.on('place-hit', async (data) => {
    const posterEmail = socket.data.email;
    if (!posterEmail || typeof data.target !== 'string' || typeof data.reward !== 'number' || data.reward < 1000) {
      socket.emit('hit-result', { success: false, message: 'Invalid hit details.' });
      return;
    }

    const posterDoc = await db.collection('players').doc(posterEmail).get();
    if (!posterDoc.exists || posterDoc.data().balance < data.reward) {
      socket.emit('hit-result', { success: false, message: 'Not enough money for the bounty.' });
      return;
    }

    const durationMinutes = data.durationDays || 5;  // NEW: Now called durationMinutes (accepts minutes from client)
    const durationMs = Math.max(durationMinutes * 60 * 1000, 5 * 60 * 1000);  // NEW: Minutes × 60 seconds

    const endTime = Date.now() + durationMs;

    const hitId = `${posterEmail}-${Date.now()}`;

    await db.collection('hitlist').doc(hitId).set({
      target: data.target,
      posterEmail,
      reward: data.reward,
      endTime,
      active: true
    });

    // Deduct from poster
    await posterDoc.ref.update({ balance: admin.firestore.FieldValue.increment(-data.reward) });
    await logTransaction(socket, -data.reward, `Bounty Placed on ${data.target}`, p, docRef);   // p = playerData, docRef = the Firestore reference

    const updatedPoster = await posterDoc.ref.get();
    socket.emit('update-stats', updatedPoster.data());

    socket.emit('hit-result', { 
      success: true, 
      message: `Bounty of $${data.reward} placed on ${data.target} for ${durationMinutes} minutes!` 
    });

    io.emit('hitlist-update');
  });

  // ==================== EXECUTE OPERATION ====================
  socket.on('execute-operation', async (data) => {
    await handleExecuteOperation(db, socket, data, { 
      io, 
      imprisonedPlayers, 
      addExperienceAndGrantPoints,
      onlinePlayers, 
      onlineSockets,
      removeFromOnlineList
    });
  });

  // ==================== REQUEST PRISON LIST (This was missing) ====================
  socket.on('request-prison-list', () => {
    const prisonList = Array.from(imprisonedPlayers, ([displayName, prisonEndTime]) => ({
      displayName,
      prisonEndTime
    }));
    io.emit('prison-list-update', {
      list: prisonList,
      serverTime: Date.now()
    });
  });

  // ==================== RESCUE / SAVE PLAYER ====================
  socket.on('attempt-rescue', async (targetDisplayName) => {
    const saverName = socket.data.displayName;
    const saverEmail = socket.data.email;
    if (!saverName || !saverEmail || saverName === targetDisplayName) return;

    // Get saver data
    const saverDocRef = db.collection('players').doc(saverEmail);
    const saverDoc = await saverDocRef.get();
    if (!saverDoc.exists) return;
    let saver = saverDoc.data();

    // Cannot rescue while in prison
    if (Date.now() < (saver.prisonEndTime || 0)) {
      socket.emit('rescue-result', { success: false, message: 'You are in prison and cannot rescue others.' });
      return;
    }

    // Target must actually be imprisoned
    if (!imprisonedPlayers.has(targetDisplayName)) {
      socket.emit('rescue-result', { success: false, message: 'That player is not in prison.' });
      return;
    }

    const isSuccess = Math.random() < 0.75;   // 50% chance (change later if needed)

    if (isSuccess) {
      // SUCCESS: Free the target
      imprisonedPlayers.delete(targetDisplayName);

      // Reset target's prisonEndTime in Firestore
      const targetQuery = await db.collection('players')
        .where('displayName', '==', targetDisplayName)
        .limit(1)
        .get();

      if (!targetQuery.empty) {
        await targetQuery.docs[0].ref.update({
          prisonEndTime: 0,
          lastLowLevelOp: 0
        });
      }

      // Give saver +15 EXP
      saver.experience = (saver.experience || 0) + 15;
      await saverDocRef.set(saver);

      // Broadcast clean prison list to everyone
      const prisonList = Array.from(imprisonedPlayers, ([dn, et]) => ({
        displayName: dn,
        prisonEndTime: et
      }));
      io.emit('prison-list-update', {
        list: prisonList,
        serverTime: Date.now()
      });

      // Notify saver
      socket.emit('rescue-result', {
        success: true,
        message: `You successfully rescued ${targetDisplayName}! +15 EXP`
      });

      socket.emit('update-stats', saver);

      // Notify rescued player if online
      const rescuedSocket = onlineSockets.get(targetDisplayName);
      if (rescuedSocket) {
        rescuedSocket.emit('update-stats', { prisonEndTime: 0 });

        // NEW: Trigger beautiful full-screen celebration
        rescuedSocket.emit('player-rescued', {
          rescuer: saverName,
          message: `You were rescued by ${saverName}!`
        });

        rescuedSocket.emit('rescue-result', {   // optional nice message
          success: true,
          message: 'You have been rescued from prison!'
        });
      }
    } else {
      // FAILURE: Imprison the saver
      const prisonEnd = Date.now() + 60000;
      saver.prisonEndTime = prisonEnd;
      imprisonedPlayers.set(saverName, prisonEnd);

      await saverDocRef.set(saver);

      const prisonList = Array.from(imprisonedPlayers, ([dn, et]) => ({
        displayName: dn,
        prisonEndTime: et
      }));
      io.emit('prison-list-update', {
        list: prisonList,
        serverTime: Date.now()
      });

      socket.emit('update-stats', saver);

      socket.emit('rescue-result', {
        success: false,
        message: `Rescue failed! You have been sent to prison for 60 seconds.`
      });
    }
  });

  // ==================== OTHER HANDLERS ====================
  socket.on('message', (msg) => {
    const name = socket.data.displayName || 'Anonymous';
    io.emit('message', `${name}: ${msg}`);
  });

  socket.on('travel', async (destination) => {
    const email = socket.data.email;
    if (!email || typeof destination !== 'string') return;

    const docRef = db.collection('players').doc(email);
    const doc = await docRef.get();
    if (!doc.exists) return;

    let p = doc.data();

    if (p.location === destination || travelCosts[destination] === undefined) return;

    const cost = travelCosts[destination];
    if (p.balance < cost) return;

    await logTransaction(socket, -cost, `Travel to ${destination}`, p, docRef);
    p.balance -= cost;

    p.location = destination;

    await docRef.set(p);
    socket.emit('update-stats', p);
  });

  socket.on('heal', async () => {
    const email = socket.data.email;
    if (!email) return;

    const docRef = db.collection('players').doc(email);
    const doc = await docRef.get();
    if (!doc.exists) return;

    let p = doc.data();
    if (p.health >= 100) return;

    const cost = 50;
    if (p.balance < cost) return;

    await logTransaction(socket, -cost, 'Healing ($50)', p, docRef);
    p.balance -= cost;

    p.health = 100;

    await docRef.set(p);
    socket.emit('update-stats', p);
  });

  socket.on('heal-broken-bone', async () => {
    const email = socket.data.email;
    if (!email) return;

    const docRef = db.collection('players').doc(email);
    const doc = await docRef.get();
    if (!doc.exists) return;

    let p = doc.data();

    // Strict location check
    if (p.location !== "Lónghǎi") {
      socket.emit('heal-broken-bone-result', { 
        success: false, 
        message: 'Orthopedic Surgeon is only available in Lónghǎi.' 
      });
      return;
    }

    if (!p.hasBrokenBone) {
      socket.emit('heal-broken-bone-result', { 
        success: false, 
        message: 'You do not have a broken bone to heal.' 
      });
      return;
    }

    const cost = 110;
    if (p.balance < cost) {
      socket.emit('heal-broken-bone-result', { 
        success: false, 
        message: 'Not enough money ($110 required).' 
      });
      return;
    }

    // Heal the debuff
    await logTransaction(socket, -cost, 'Broken Bone Healing ($110)', p, docRef);   // p = playerData, docRef = the Firestore reference
    p.balance -= cost;
    p.hasBrokenBone = false;
    p.bonePenaltyEndTimeLow = 0;
    p.bonePenaltyEndTimeMid = 0;
    p.bonePenaltyEndTimeHigh = 0;

    await docRef.set(p);

    socket.emit('heal-broken-bone-result', { 
      success: true, 
      message: '🦴 Bone healed! You feel much better.' 
    });
    socket.emit('update-stats', p);
  });

  socket.on('update-profile', async (data) => {
    const email = socket.data.email;
    if (!email || typeof data.photoURL !== 'string') return;

    const docRef = db.collection('players').doc(email);
    const doc = await docRef.get();
    if (!doc.exists) return;

    let p = doc.data();
    p.photoURL = data.photoURL;

    await docRef.set(p);
    socket.emit('update-stats', p);
  });

  socket.on('update-visibility', async (data) => {
    const email = socket.data.email;
    if (!email || typeof data.showArmor !== 'boolean' || typeof data.showWeapon !== 'boolean') return;

    const docRef = db.collection('players').doc(email);
    const doc = await docRef.get();
    if (!doc.exists) return;

    let p = doc.data();
    p.showArmor = data.showArmor;
    p.showWeapon = data.showWeapon;

    await docRef.set(p);
    socket.emit('update-stats', p);
  });

  socket.on('purchase-armor', async (data) => { // NEW: Purchase armor
    const email = socket.data.email;
    if (!email || !Array.isArray(data.items) || typeof data.totalCost !== 'number') return;

    const docRef = db.collection('players').doc(email);
    const doc = await docRef.get();
    if (!doc.exists) return;

    let p = doc.data();

    if (p.balance < data.totalCost) return; // Not enough balance

    // Validate total cost on server to prevent cheating
    let calculatedCost = 0;
    for (const item of data.items) {
      if (typeof item.cost === 'number') {
        calculatedCost += item.cost;
      }
    }
    if (calculatedCost !== data.totalCost) return; // Mismatch, possible cheat

    // Add items to inventory (append full objects)
    p.inventory = p.inventory.concat(data.items);
    await logTransaction(socket, -data.totalCost, 'Gear Purchased (Armor/Weapons)', p, docRef);   // p = playerData, docRef = the Firestore reference
    p.balance -= data.totalCost;

    await docRef.set(p);
    socket.emit('update-stats', p);
  });

  // ==================== VEHICLES ====================
  socket.on('request-vehicles', () => handleRequestVehicles(socket));

  socket.on('purchase-vehicles', async (data) => {await handlePurchaseVehicles(db, socket, data);});
  
  socket.on('equip-armor', async (data) => { // NEW: Equip armor
    const email = socket.data.email;
    if (!email || typeof data.slot !== 'string' || typeof data.item !== 'object') return;

    const docRef = db.collection('players').doc(email);
    const doc = await docRef.get();
    if (!doc.exists) return;

    let p = doc.data();
    const slot = data.slot;
    const item = data.item;

    if (item.type !== slot) return;

    if (p[slot] !== null) {
      p.inventory.push(p[slot]);
      p.defense -= p[slot].defense || 0;
    }

    p[slot] = item;
    p.defense += item.defense || 0;

    // NEW: Marksmanship bonus only applies to weapons
    if (slot === 'weapon') {
      p = recalculateOverallPower(p);
    }

    const index = p.inventory.findIndex(i => i.name === item.name && i.type === item.type);
    if (index !== -1) {
      p.inventory.splice(index, 1);
    }

    await docRef.set(p);
    socket.emit('update-stats', p);
  });

  socket.on('unequip-armor', async (data) => {
    const email = socket.data.email;
    if (!email || typeof data.slot !== 'string') return;

    const docRef = db.collection('players').doc(email);
    const doc = await docRef.get();
    if (!doc.exists) return;

    let p = doc.data();
    const slot = data.slot;

    if (p[slot] !== null) {
      const equipped = p[slot];
      p.inventory.push(equipped);
      p.defense -= equipped.defense || 0;
      p[slot] = null;
      if (slot === 'weapon') {
        p.overallPower = 0;   // Remove weapon → no bonus
      }
    }

    await docRef.set(p);
    socket.emit('update-stats', p);
  });

  socket.on('sell-items', async (data) => {
    const email = socket.data.email;
    if (!email || !Array.isArray(data.items) || typeof data.totalSellValue !== 'number' || ![60,80,100].includes(data.rate)) return;

    const docRef = db.collection('players').doc(email);
    const doc = await docRef.get();
    if (!doc.exists) return;

    let p = doc.data();

    // NEW: Check if banned
    if (Date.now() < (p.sellBanEndTime || 0)) {
      socket.emit('sell-result', { success: false, message: 'You are banned from selling. Try later.' });
      return;
    }

    // Validate total sell value at rate
    let calculatedValue = 0;
    const rateFactor = data.rate / 100;
    for (const item of data.items) {
      if (typeof item.cost === 'number') {
        calculatedValue += Math.floor(item.cost * rateFactor);
      }
    }
    if (calculatedValue !== data.totalSellValue) return; // Cheat?

    // NEW: Random success based on rate
    let successChance = 1.0;  // 60%
    let banMs = 0;
    if (data.rate === 80) {
      successChance = 0.45;
      banMs = 3 * 60 * 60 * 1000;  // 3h
    } else if (data.rate === 100) {
      successChance = 0.12;
      banMs = 8 * 60 * 60 * 1000;  // 8h
    }

    const isSuccess = Math.random() < successChance;

    if (!isSuccess && banMs > 0) {
      p.sellBanEndTime = Date.now() + banMs;
      await docRef.set(p);
      socket.emit('sell-result', { success: false, message: `Sale failed! Banned from selling for ${banMs / (60*60*1000)} hours.` });
      socket.emit('update-stats', p);  // Send ban time
      return;
    }

    // Success: Remove items, add money
    for (const soldItem of data.items) {
      const index = p.inventory.findIndex(i => 
        i.name === soldItem.name && 
        i.type === soldItem.type && 
        i.power === soldItem.power
      );
      if (index !== -1) {
        p.inventory.splice(index, 1);
      }
    }

    await logTransaction(socket, data.totalSellValue, 'Items Sold', p, docRef);   // p = playerData, docRef = the Firestore reference
    p.balance += data.totalSellValue;

    await docRef.set(p);
    socket.emit('sell-result', { success: true, message: 'Items sold!' });
    socket.emit('update-stats', p);
  });

  // NEW: Handler for buying property (updated to add claim entry)
  socket.on('buy-property', async (propertyName) => {
    await handleBuyProperty(db, socket, propertyName);  // Call the function from properties.js
  });

  socket.on('buy-upgrade', async (data) => {
    const { propertyName, upgradeName } = data;
    await handleBuyUpgrade(db, socket, propertyName, upgradeName);
  });

  // ==================== ALLOCATE ATTRIBUTE POINTS ====================
  socket.on('allocate-attribute', async (data) => {
    const email = socket.data.email;
    const attribute = data.attribute;
    if (!email || !['intelligence', 'skill', 'marksmanship'].includes(attribute)) return;

    const docRef = db.collection('players').doc(email);
    const doc = await docRef.get();
    if (!doc.exists) return;

    let p = doc.data();
    if ((p.unallocatedAttributePoints || 0) <= 0) return;

    const oldMarksmanship = p.marksmanship || 0;
    const oldPower = p.overallPower || 0;

    p[attribute] = (p[attribute] || 0) + 1;
    p.unallocatedAttributePoints = (p.unallocatedAttributePoints || 0) - 1;

    // FIXED: More robust check + logging so we can see exactly what happens
    if (attribute === 'marksmanship' && p.weapon?.power != null) {
      p = recalculateOverallPower(p);
      console.log(`[SERVER] Marksmanship ${oldMarksmanship} → ${p.marksmanship} | Power ${oldPower} → ${p.overallPower} for ${email}`);
    }

    await docRef.set(p);
    socket.emit('update-stats', p);
    console.log(`[SERVER] Allocated ${attribute} for ${email}`);
  });

  // NEW: Handler for claiming income (now per-property)
  socket.on('claim-income', async () => {
    await handleClaimIncome(db, socket);  // Call the function from properties.js
  });

  // ==================== BOND MARKET HANDLERS (with 2-minute cooldown) ====================
  socket.on('request-bond-market', async () => {
    await handleRequestBondMarket(db, socket);
  });

  socket.on('refresh-bond-market', async () => {
    await handleRefreshBondMarket(db, socket);
  });

  socket.on('buy-bond', async (bondData) => {
    await handleBuyBond(db, socket, bondData);
  });

  // ==================== PRIVATE MESSAGES ====================
  socket.on('private-message', async (data) => {
    if (!data || typeof data.to !== 'string' || typeof data.msg !== 'string') return;

    const from = socket.data.displayName;
    if (!from) return;

    const msgId = data.id || Date.now().toString();

    const baseMsg = {
      from: from,
      msg: data.msg,
      id: msgId
    };

    // NEW: Find recipient by name (assume unique)
    const querySnapshot = await db.collection('players').where('displayName', '==', data.to).limit(1).get();
    if (querySnapshot.empty) return;

    const recipientDoc = querySnapshot.docs[0];
    const toEmail = recipientDoc.id;
    const recipientData = recipientDoc.data();

    // NEW: Save message for recipient
    const msgForRecipient = {
      type: 'private',
      data: baseMsg,
      timestamp: new Date().toISOString(),
      isRead: false
    };

    await recipientDoc.ref.update({
      messages: admin.firestore.FieldValue.arrayUnion(msgForRecipient)
    });

    // NEW: Save for sender too
    const senderDoc = await db.collection('players').doc(socket.data.email).get();
    if (senderDoc.exists) {
      const msgForSender = {
        type: 'private',
        data: { ...baseMsg, to: data.to, isFromMe: true },
        timestamp: new Date().toISOString(),
        isRead: true  // Sender sees their own as read
      };

      await senderDoc.ref.update({
        messages: admin.firestore.FieldValue.arrayUnion(msgForSender)
      });
    }

    // Send to recipient if online
    const targetSocket = onlineSockets.get(data.to);
    if (targetSocket) {
      targetSocket.emit('private-message', baseMsg);
    } else if (recipientData.fcmTokens && recipientData.fcmTokens.length > 0) {
      // FIXED: Send push if offline (use sendEachForMulticast)
      const fcmMessage = {
        notification: {
          title: `${from} sent a message`,
          body: data.msg
        },
        android: {
          priority: 'high'  // Removed invalid "group" field; grouping is client-side
        },
        data: {
          type: 'private',
          sender: from,  // FIXED: Renamed 'from' to 'sender' to avoid reserved key error
          msg: data.msg,
          id: msgId
        },
        tokens: recipientData.fcmTokens  // List of tokens
      };

      try {
        const response = await admin.messaging().sendEachForMulticast(fcmMessage);
        console.log(`Push sent to ${data.to}. Success: ${response.successCount}, Failure: ${response.failureCount}`);
        if (response.failureCount > 0) {
          response.responses.forEach((resp, index) => {
            if (!resp.success) {
              console.log('Failure for token ' + recipientData.fcmTokens[index] + ': ' + (resp.error ? resp.error.message : 'Unknown error'));
            }
          });
        }
      } catch (error) {
        console.error('Error sending push to ' + data.to + ': ' + error);
      }
    }

    // Echo to sender
    socket.emit('private-message', { ...baseMsg, to: data.to, isFromMe: true });
  });

  // ==================== ANNOUNCEMENTS ====================
  socket.on('announcement', async (text) => {
    if (typeof text === 'string' && text.length > 0) {
      // NEW: Save to special announcements box
      const annRef = await db.collection('announcements').add({
        text: text,
        timestamp: new Date().toISOString()
      });
      const annId = annRef.id;

      // Send to all online
      io.emit('announcement', { text: text, id: annId });

      // NEW: Send push to group
      const fcmMessage = {
        topic: 'announcements',
        notification: {
          title: 'Mod Announcement',
          body: text
        },
        android: {
          priority: 'high'  // Removed invalid "group" field; grouping is client-side
        },
        data: {
          type: 'announcement',
          text: text,
          id: annId
        }
      };

      await admin.messaging().send(fcmMessage);
      console.log('Sent announcement push');
    }
  });

  socket.on('disconnect', () => {
    if (socket.data.displayName) {
      const name = socket.data.displayName;
      removeFromOnlineList(name);
      onlinePlayers.delete(name);
      onlineSockets.delete(name);
      io.emit('online-players', Array.from(onlinePlayers));
      console.log(`[SERVER] ${name} left - online now: ${onlinePlayers.size}`);
    }
  });
});

const port = process.env.PORT || 3000;
server.listen(port, () => console.log(`Server running on ${port}`));