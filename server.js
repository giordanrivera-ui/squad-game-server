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
const { handleKillAttempt, markPlayerAsDead } = require('./combat.js');

// Firebase Admin
const serviceAccount = JSON.parse(process.env.FIREBASE_SERVICE_ACCOUNT);
admin.initializeApp({
  credential: admin.credential.cert(serviceAccount)
});

const db = admin.firestore();

// ==================== GLOBAL PRISON LIST ====================
const imprisonedPlayers = new Map(); // Key: displayName, Value: prisonEndTime

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
}, 2000); // Check every minute

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
      if (playerData.sellBanEndTime === undefined) playerData.sellBanEndTime = 0;
      if (playerData.ownedProperties === undefined) playerData.ownedProperties = [];
      if (playerData.ownedUpgrades === undefined) playerData.ownedUpgrades = {};
      if (playerData.lastIncomeClaim === undefined) playerData.lastIncomeClaim = Date.now();
      if (playerData.propertyClaims === undefined) playerData.propertyClaims = [];
      if (playerData.showArmor === undefined) playerData.showArmor = true;
      if (playerData.showWeapon === undefined) playerData.showWeapon = true;
      if (playerData.dead === undefined) playerData.dead = false;

      if (playerData.displayName) {
        playerData.displayNameLower = playerData.displayName.toLowerCase();
      }

      // If displayName is null (after death) and client sends a new one, set it
      if (!playerData.displayName && displayName !== 'Anonymous') {
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
        sellBanEndTime: 0,
        prisonEndTime: 0,
        ownedProperties: [],
        lastIncomeClaim: Date.now(),
        propertyClaims: [],
        showArmor: true,
        showWeapon: true,
        dead: false,
        ownedUpgrades: {},
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

    // NEW: If player is dead, force death screen and hide from online list
    if (playerData.dead === true) {
      socket.emit('player-died');  // Force client to show death screen

      // Remove from online list
      if (playerData.displayName) {
        onlinePlayers.delete(playerData.displayName);
        onlineSockets.delete(playerData.displayName);
        io.emit('online-players', Array.from(onlinePlayers));
      }

      console.log(`[SERVER] ${playerData.displayName || email} reconnected while dead — forcing death screen`);
    }

    socket.data.email = email;
    socket.data.displayName = displayName;

    onlinePlayers.add(displayName);
    onlineSockets.set(displayName, socket);

    io.emit('online-players', Array.from(onlinePlayers));

    console.log(`[SERVER] ${displayName} joined - online now: ${onlinePlayers.size}`);


    socket.emit('init', {
      player: playerData,
      locations: normalLocations,
      travelCosts: travelCosts,
      properties: properties
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
      // NEW: Save dead profile snapshot BEFORE reset
      const deadProfile = {
        displayName: oldName,
        displayNameLower: oldName.toLowerCase(),
        experience: p.experience || 0,  // For rank
        balance: p.balance || 0,        // For wealth title
        headwear: p.headwear || null,
        armor: p.armor || null,
        footwear: p.footwear || null,
        weapon: p.weapon || null,
        overallPower: p.overallPower || 0,
        deathTime: admin.firestore.FieldValue.serverTimestamp(),  // When they died
        originalEmail: email  // Optional: Track owner
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
      sellBanEndTime: 0,
      prisonEndTime: 0,
      ownedProperties: [],
      lastIncomeClaim: Date.now(),
      propertyClaims: [],
      showArmor: true,
      showWeapon: true,
      dead: false,
      ownedUpgrades: {},
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
    p.experience = (p.experience || 0) + amount;

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

  // ====================== KILL ATTEMPT ======================
  socket.on('attempt-kill', async (data) => {
    await handleKillAttempt(db, socket, data, onlineSockets);
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
    const email = socket.data.email;
    if (!email || typeof data.operation !== 'string') return;

    const docRef = db.collection('players').doc(email);
    const doc = await docRef.get();
    if (!doc.exists) return;

    let p = doc.data();
    const operation = data.operation;

    const lowLevelOps = [
      "Mug a passerby",
      "Loot a grocery store",
      "Rob a bank",
      "Loot weapons store"
    ];

    const midLevelOps = [
      "Attack military barracks",
      "Storm a laboratory",
      "Attack central issue facility"
    ];

    if (!lowLevelOps.includes(operation) && !midLevelOps.includes(operation)) return;

    let cooldownTime = 60000; // low
    let lastOpTime = p.lastLowLevelOp || 0;
    if (midLevelOps.includes(operation)) {
      cooldownTime = 72000; // mid
      lastOpTime = p.lastMidLevelOp || 0;
    }
    if (Date.now() - lastOpTime < cooldownTime) return;

    let money = 0;
    let rawDamage = 0;
    let expGain = 0;
    let message = "";
    let isCaught = false;

    if (operation === "Mug a passerby") {
      money = Math.floor(Math.random() * 91) + 10;
      rawDamage = Math.floor(Math.random() * 26) + 5;
      expGain = 10;
      message = `You mugged a passerby and got $${money}!`;} 
    else if (operation === "Loot a grocery store") {
      money = Math.floor(Math.random() * 71) + 30;
      rawDamage = Math.floor(Math.random() * 21) + 15;
      expGain = 15;
      message = `You looted the grocery store and stole $${money}!`;} 
    else if (operation === "Rob a bank") {
      rawDamage = Math.floor(Math.random() * 41) + 15;
      expGain = 25;

      const exp = p.experience || 0;
      if (exp <= 49)          money = Math.floor(Math.random() * 61) + 30;
      else if (exp <= 514)     money = Math.floor(Math.random() * 71) + 30;
      else if (exp <= 1264)    money = Math.floor(Math.random() * 81) + 40;
      else if (exp <= 2314)    money = Math.floor(Math.random() * 91) + 60;
      else if (exp <= 3514)    money = Math.floor(Math.random() * 101) + 80;
      else if (exp <= 5014)    money = Math.floor(Math.random() * 111) + 90;
      else if (exp <= 6864)    money = Math.floor(Math.random() * 121) + 120;
      else if (exp <= 8864)    money = Math.floor(Math.random() * 111) + 150;
      else if (exp <= 10214)   money = Math.floor(Math.random() * 121) + 180;
      else if (exp <= 11464)   money = Math.floor(Math.random() * 141) + 200;
      else if (exp <= 14214)   money = Math.floor(Math.random() * 121) + 240;
      else if (exp <= 17414)   money = Math.floor(Math.random() * 126) + 275;
      else if (exp <= 21364)   money = Math.floor(Math.random() * 156) + 320;
      else if (exp <= 25864)   money = Math.floor(Math.random() * 241) + 360;
      else if (exp <= 31514)   money = Math.floor(Math.random() * 251) + 450;
      else if (exp <= 38214)   money = Math.floor(Math.random() * 281) + 500;
      else                     money = Math.floor(Math.random() * 401) + 600;

      message = `You robbed the bank and escaped with $${money}!`;} 
    else if (operation === "Loot weapons store") {
      money = Math.floor(Math.random() * 41) + 10;
      rawDamage = Math.floor(Math.random() * 41) + 20;
      expGain = 10;
      message = `You looted the weapons store and stole $${money}!`;}
    else if (operation === "Attack military barracks") {
      money = Math.floor(Math.random() * 131) + 50;
      rawDamage = Math.floor(Math.random() * 38) + 25;
      expGain = 35;
      message = `You attacked the military barracks and got $${money}!`;}
    else if (operation === "Storm a laboratory") {
      money = Math.floor(Math.random() * (160 - 60 + 1)) + 60;
      rawDamage = Math.floor(Math.random() * (52 - 20 + 1)) + 20;
      expGain = 27;
      message = `You stormed a laboratory and got $${money}!`;}

    let prisonChance;
    const exp = p.experience || 0;

    if (midLevelOps.includes(operation)) {
      prisonChance = 0.47;
      if (exp > 49) prisonChance = 0.45;
      if (exp > 514) prisonChance = 0.42;
      if (exp > 1264) prisonChance = 0.38;
      if (exp > 2314) prisonChance = 0.36;
      if (exp > 3514) prisonChance = 0.34;
      if (exp > 5014) prisonChance = 0.31;
      if (exp > 6864) prisonChance = 0.29;
      if (exp > 8864) prisonChance = 0.26;
      if (exp > 10214) prisonChance = 0.25;
      if (exp > 11464) prisonChance = 0.24;
      if (exp > 14214) prisonChance = 0.22;
      if (exp > 17414) prisonChance = 0.20;
      if (exp > 21364) prisonChance = 0.16;
      if (exp > 25864) prisonChance = 0.14;
      if (exp > 31514) prisonChance = 0.12;
      if (exp > 38214) prisonChance = 0.10;
    } else {
      prisonChance = 0.27;
      if (exp > 49) prisonChance = 0.25;
      if (exp > 514) prisonChance = 0.21;
      if (exp > 1264) prisonChance = 0.20;
      if (exp > 2314) prisonChance = 0.19;
      if (exp > 3514) prisonChance = 0.18;
      if (exp > 5014) prisonChance = 0.17;
      if (exp > 6864) prisonChance = 0.16;
      if (exp > 8864) prisonChance = 0.15;
      if (exp > 10214) prisonChance = 0.14;
      if (exp > 11464) prisonChance = 0.13;
      if (exp > 14214) prisonChance = 0.12;
      if (exp > 17414) prisonChance = 0.11;
      if (exp > 21364) prisonChance = 0.10;
      if (exp > 25864) prisonChance = 0.08;
      if (exp > 31514) prisonChance = 0.07;
      if (exp > 38214) prisonChance = 0.06;
    }

    isCaught = Math.random() < prisonChance;

    if (isCaught) {
      p.prisonEndTime = Date.now() + 60000;
      imprisonedPlayers.set(p.displayName, p.prisonEndTime);
      message = `You were caught! You have been sent to prison for 60 seconds.`;
    } else {
      const totalDefense = 
        (p.headwear?.defense || 0) + 
        (p.armor?.defense || 0) + 
        (p.footwear?.defense || 0);

      const actualDamage = Math.max(0, rawDamage - totalDefense);

      p.balance += money;
      p.health = Math.max(0, p.health - actualDamage);
      p.experience += expGain;

      if (operation === "Loot weapons store") {
        // Weapon steal chance based on rank (using pre-gain exp)
        let stealChance = 0.22;
        if (exp > 49) stealChance = 0.25;
        if (exp > 514) stealChance = 0.30;
        if (exp > 1264) stealChance = 0.35;
        if (exp > 2314) stealChance = 0.40;
        if (exp > 3514) stealChance = 0.45;
        if (exp > 5014) stealChance = 0.50;
        if (exp > 6864) stealChance = 0.55;
        if (exp > 8864) stealChance = 0.60;
        if (exp > 10214) stealChance = 0.65;
        if (exp > 11464) stealChance = 0.65;
        if (exp > 14214) stealChance = 0.65;
        if (exp > 17414) stealChance = 0.70;
        if (exp > 21364) stealChance = 0.70;
        if (exp > 25864) stealChance = 0.75;
        if (exp > 31514) stealChance = 0.80;
        if (exp > 38214) stealChance = 0.85;

        // Inside the if (operation === "Loot weapons store") block in the success else (!isCaught):
        if (Math.random() < stealChance) {
          let knifeThreshold = 30;
          let batThreshold = 55;
          let macheteThreshold = 75;
          let maulThreshold = 95;

          if (exp > 3514) {  // Corporal+
            knifeThreshold = 20;
            batThreshold = 45;
            macheteThreshold = 70;
            maulThreshold = 93;
          }
          if (exp > 10214) {  // First Lieutenant+
            knifeThreshold = 14;
            batThreshold = 32;
            macheteThreshold = 57;
            maulThreshold = 84;
          }

          const rand = Math.random() * 100;
          let weapon;
          if (rand < knifeThreshold) {
            weapon = {
              name: 'Small Knife',
              description: 'A compact blade for quick stabs and slashes in close-quarters combat.',
              power: 10,
              cost: 30,
              type: 'weapon'
            };
          } else if (rand < batThreshold) {
            weapon = {
              name: 'Baseball Bat',
              description: 'A sturdy wooden club ideal for blunt force trauma in melee situations.',
              power: 18,
              cost: 120,
              type: 'weapon'
            };
          } else if (rand < macheteThreshold) {
            weapon = {
              name: 'Machete',
              description: 'A large chopping blade effective for hacking through obstacles or enemies.',
              power: 25,
              cost: 250,
              type: 'weapon'
            };
          } else if (rand < maulThreshold) {
            weapon = {
              name: 'Splitting Maul',
              description: 'A heavy hammer-axe hybrid designed for powerful overhead strikes.',
              power: 30,
              cost: 350,
              type: 'weapon'
            };
          } else {
            weapon = {
              name: 'Ruger Mark IV',
              description: 'A reliable .22 caliber pistol perfect for target practice and small game.',
              power: 70,
              cost: 520,
              type: 'weapon'
            };
          }
          p.inventory.push(weapon);
          message += ` You also stole a ${weapon.name}!`;
        }
      }

      if (operation === "Attack military barracks") {
        let stealChance = 0.12;
        if (exp > 49) stealChance = 0.15;
        if (exp > 514) stealChance = 0.20;
        if (exp > 1264) stealChance = 0.25;
        if (exp > 2314) stealChance = 0.30;
        if (exp > 3514) stealChance = 0.35;
        if (exp > 5014) stealChance = 0.40;
        if (exp > 6864) stealChance = 0.45;
        if (exp > 8864) stealChance = 0.55;
        if (exp > 10214) stealChance = 0.60;
        if (exp > 11464) stealChance = 0.62;
        if (exp > 14214) stealChance = 0.65;
        if (exp > 17414) stealChance = 0.68;
        if (exp > 21364) stealChance = 0.72;
        if (exp > 25864) stealChance = 0.75;
        if (exp > 31514) stealChance = 0.80;
        if (exp > 38214) stealChance = 0.85;

        if (Math.random() < stealChance) {
          let glockThreshold = 42;
          let remingtonThreshold = 72;
          let mossbergThreshold = 91;
          let mp5Threshold = 97;

          if (exp > 3514) {  // Corporal to Warrant
            glockThreshold = 33;
            remingtonThreshold = 63;
            mossbergThreshold = 85;
            mp5Threshold = 95;
          }
          if (exp > 10214) {  // First Lt+
            glockThreshold = 24;
            remingtonThreshold = 48;
            mossbergThreshold = 70;
            mp5Threshold = 88;
          }

          const rand = Math.random() * 100;
          let weapon;
          if (rand < glockThreshold) {
            weapon = {
              name: 'Glock 45 Gen 5',
              description: 'A versatile 9mm handgun known for its durability and high-capacity magazine.',
              power: 150,
              cost: 700,
              type: 'weapon'
            };
          } else if (rand < remingtonThreshold) {
            weapon = {
              name: 'Remington R1 Enhanced',
              description: 'A 1911-style .45 pistol with improved ergonomics and accuracy.',
              power: 200,
              cost: 830,
              type: 'weapon'
            };
          } else if (rand < mossbergThreshold) {
            weapon = {
              name: 'Mossberg 590 Shotgun',
              description: 'A pump-action 12-gauge shotgun excellent for close-range crowd control.',
              power: 260,
              cost: 1200,
              type: 'weapon'
            };
          } else if (rand < mp5Threshold) {
            weapon = {
              name: 'MP5 SMG',
              description: 'A compact 9mm submachine gun favored for its controllability in full-auto fire.',
              power: 330,
              cost: 4000,
              type: 'weapon'
            };
          } else {
            weapon = {
              name: 'H&K UMP5',
              description: 'A .45 caliber submachine gun offering superior stopping power in CQB.',
              power: 380,
              cost: 4600,
              type: 'weapon'
            };
          }
          p.inventory.push(weapon);
          message += ` You also stole a ${weapon.name}!`;
        }
      }

      if (lowLevelOps.includes(operation)) {
        p.lastLowLevelOp = Date.now();
      } else if (midLevelOps.includes(operation)) {
        p.lastMidLevelOp = Date.now();
      }
    }

    await docRef.set(p);

    // Broadcast updated prison list to ALL players
    const prisonList = Array.from(imprisonedPlayers, ([displayName, prisonEndTime]) => ({
      displayName,
      prisonEndTime
    }));
    io.emit('prison-list-update', {
      list: prisonList,
      serverTime: Date.now()
    });

    // Send result to the player who did the operation
    socket.emit('operation-result', {
      operation: operation,
      money: money,
      rawDamage: rawDamage,
      actualDamage: isCaught ? rawDamage : Math.max(0, rawDamage - 
        ((p.headwear?.defense || 0) + (p.armor?.defense || 0) + (p.footwear?.defense || 0))),
      totalDefense: isCaught ? 0 : 
        ((p.headwear?.defense || 0) + (p.armor?.defense || 0) + (p.footwear?.defense || 0)),
      message: message,
      isCaught: isCaught,
      prisonEndTime: p.prisonEndTime || 0
    });

    socket.emit('update-stats', p);

    if (p.health <= 0 && !isCaught) {
      p.dead = true;  // NEW: Mark as dead
      p.health = 0;   // Ensure health is 0
      await markPlayerAsDead(db, p, email, p.displayName);
      await docRef.set(p);  // Save changes (don't delete doc anymore)
      socket.emit('player-died');  // NEW: Notify client
      console.log(`Player ${email} died and marked as dead`);
    }
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

    p.balance -= cost;
    p.health = 100;

    await docRef.set(p);
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
    p.balance -= data.totalCost;

    await docRef.set(p);
    socket.emit('update-stats', p);
  });

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

    if (slot === 'weapon') {
      p.overallPower = item.power || 0;
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
        p.overallPower = 0;
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

  // NEW: Handler for claiming income (now per-property)
  socket.on('claim-income', async () => {
    await handleClaimIncome(db, socket);  // Call the function from properties.js
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
      onlinePlayers.delete(name);
      onlineSockets.delete(name);
      io.emit('online-players', Array.from(onlinePlayers));
      console.log(`[SERVER] ${name} left - online now: ${onlinePlayers.size}`);
    }
  });
});

const port = process.env.PORT || 3000;
server.listen(port, () => console.log(`Server running on ${port}`));