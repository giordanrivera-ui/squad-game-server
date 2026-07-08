const express = require('express');
const http = require('http');
const { Server } = require('socket.io');
const admin = require('firebase-admin');
const app = express();
const server = http.createServer(app);


const io = new Server(server, { 
  cors: { origin: "*" },
  pingTimeout: 10000,  // 10 sec timeout before disconnect
  pingInterval: 5000   // Ping every 5 sec to check alive
});

const { logTransaction, getRankTitle, addExperienceAndGrantPoints, getAvailableBalance, cleanupExpiredCrimeFreeze, clearCrimeFreezeForPlayer } = require('./utils');
const { properties, handleBuyProperty, handleBuyUpgrade, handleClaimIncome } = require('./properties.js');
const { handleKillAttempt, markPlayerAsDead } = require('./combat.js');
const { handleExecuteOperation } = require('./operations.js');
const { handleRequestBondMarket, handleRefreshBondMarket, handleBuyBond, startBondMaturityChecker, reconcileBondFlags } = require('./bonds.js');
const { weaponTemplates, handleRequestWeapons, handlePurchaseWeapons } = require('./weapons.js');
const { vehicleTemplates, handleRequestVehicles, handlePurchaseVehicles } = require('./vehicles.js');
const { startDriverSalaryChecker, startDriverProgressChecker, startTaxiJobChecker, registerTaxiHandlers } = require('./taxi_tycoon.js');
const { startHospitalMaintenanceChecker, startHospitalResearchChecker, catchUpEfficientDoctorsResearch, catchUpPerformanceResearches, ENHANCED_STAMINA_RESEARCH, ENHANCED_CONSTITUTION_RESEARCH, handleUpdateHospitalStaminaCost, handleUpdateHospitalConstitutionCost, handlePurchaseEnhancedStamina, handleSetSelectedEpinephrineQuality, registerHospitalHandlers } = require('./hospital.js');
const { hospitalCounts } = require('./hospital_constants');
const { handleInitiateSpecialOp, handleCancelSpecialOp, handleAssignSpecialWeapon, handleAcceptSpecialOpInvite, syncPartyMemberRank, handleLeaveSpecialOp, syncPartyMemberMarksmanship, syncPartyTeamSynergy } = require('./specialOperations.js');
const { handleRequestCourses, handlePurchaseCourse } = require('./courses.js');
const { normalLocations, travelCosts, handleTravel } = require('./travel.js');
const { registerFitnessHandlers, updateMaxHealth } = require('./fitness.js');
const { handleAddTestExp, handleAddTestMoney, handleAddTestBullets, handleResetMartialArt } = require('./test_handlers');
const { registerRespawnHandler } = require('./respawn.js');
const { registerSellHandlers } = require('./sell.js');
const Human = require('./human');
const { setupPeterTheBeggar } = require('./peterthebeggar');

// Firebase Admin
const serviceAccount = JSON.parse(process.env.FIREBASE_SERVICE_ACCOUNT);
admin.initializeApp({
  credential: admin.credential.cert(serviceAccount)
});

const db = admin.firestore();

// Initialize default hospitals if they don't exist
async function initializeHospitals() {
  for (const [location, count] of Object.entries(hospitalCounts)) {
    for (let i = 1; i <= count; i++) {
      const docId = `${location}-hospital-${i}`;
      const doc = await hospitalOwnershipRef.doc(docId).get();
      if (!doc.exists) {
        await hospitalOwnershipRef.doc(docId).set({
          location: location,
          index: i,
          isPublic: i === 1,                    // only first hospital is public
          ownerEmail: null,
          ownerDisplayName: null,
          createdAt: Date.now()
        });
      }
    }
  }
}

async function getAllHospitalOwnership() {
  const snapshot = await hospitalOwnershipRef.get();
  const ownership = {};
  snapshot.docs.forEach(doc => {
    ownership[doc.id] = doc.data();
  });
  return ownership;
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

// ==================== ONLINE LIST HELPER ====================
function removeFromOnlineList(displayName) {
  if (!displayName) return;
  onlinePlayers.delete(displayName);
  onlineSockets.delete(displayName);
  io.emit('online-players', Array.from(onlinePlayers));
  console.log(`[SERVER] ${displayName} removed from online list (death or cleanup)`);
}

// ==================== Clean up expired loot decision safely (even after restart) ====================
async function cleanupExpiredLootDecision(witnessName, savedDecision) {
  if (!savedDecision) return;

  const criminalQuery = await db.collection('players')
    .where('displayName', '==', savedDecision.perpetrator)
    .limit(1)
    .get();

  if (criminalQuery.empty) return;

  const criminalRef = criminalQuery.docs[0].ref;

  const frozenMoney = savedDecision.frozenMoney || 0;
  const frozenItems = savedDecision.frozenItems || [];

  const itemsToRemoveSignatures = new Set(
    frozenItems.map(item => `${item.name}|${item.type || ''}|${item.frozenUntil}`)
  );

  try {
    await db.runTransaction(async (transaction) => {
      const criminalSnap = await transaction.get(criminalRef);
      if (!criminalSnap.exists) return;

      let criminalData = criminalSnap.data();

      // Destroy the loot (return case)
      if (frozenMoney > 0) {
        criminalData.balance = Math.max(0, (criminalData.balance || 0) - frozenMoney);
      }

      const currentInventory = criminalData.inventory || [];
      const updatedInventory = currentInventory.filter(item => {
        const signature = `${item.name}|${item.type || ''}|${item.frozenUntil}`;
        const isPartOfThisDecision = itemsToRemoveSignatures.has(signature);
        if (isPartOfThisDecision) return false;
        const isStillFrozen = item.frozenUntil && item.frozenUntil > Date.now();
        return !item.frozenUntil || isStillFrozen;
      });

      criminalData.inventory = updatedInventory;
      const currentFrozen = criminalData.frozenCrimeMoney || 0;
      criminalData.frozenCrimeMoney = Math.max(0, currentFrozen - frozenMoney);

      if (criminalData.frozenCrimeMoney === 0) {
        delete criminalData.frozenCrimeMoney;
        delete criminalData.crimeFreezeUntil;
      }

      transaction.set(criminalRef, criminalData);
    });

    console.log(`[LOOT] Cleaned up expired decision for ${witnessName} (criminal = ${savedDecision.perpetrator})`);
  } catch (err) {
    console.error('[LOOT EXPIRED CLEANUP ERROR]', err);
  }
}

// ==================== HELPER: Process Loot Decision (Take vs Return) ====================
async function processLootDecision(witnessName, choice, witnessSocket = null, isAuto = false) {
  const decision = lootDecisionWindows.get(witnessName);
  if (!decision) return;

  // Clear the scheduled timeout if it exists
  if (decision.timeoutId) {
    clearTimeout(decision.timeoutId);
  }

  // NEW SAFETY: Remove from memory map RIGHT NOW so the 30-second poller
  // cannot accidentally run cleanupExpiredLootDecision at the same time.
  lootDecisionWindows.delete(witnessName);

  const witnessQuery = await db.collection('players').where('displayName', '==', witnessName).limit(1).get();
  const criminalQuery = await db.collection('players').where('displayName', '==', decision.perpetrator).limit(1).get();

  if (witnessQuery.empty || criminalQuery.empty) {
  // Criminal no longer exists (probably died) → clean up witness's state so they are not stuck
  console.log(`[LOOT] Criminal ${decision.perpetrator} no longer exists (died?). Cleaning up witness decision.`);
  
  lootDecisionWindows.delete(witnessName);
  
  // Clear the pending decision from witness's database
  if (witnessQuery.docs[0]) {
    witnessQuery.docs[0].ref.update({
      pendingLootDecision: admin.firestore.FieldValue.delete()
    }).catch(() => {});
  }
  
  if (witnessSocket) {
    witnessSocket.emit('loot-decision-result', {
      success: false,
      message: 'The criminal has died or left. Decision cancelled.'
    });
  }
  return;
}

  const witnessRef = witnessQuery.docs[0].ref;
  const criminalRef = criminalQuery.docs[0].ref;

  const frozenMoney = decision.frozenMoney || 0;
  const frozenItems = decision.frozenItems || [];

  const criminalSocket = onlineSockets.get(decision.perpetrator);

  // Create signatures for the items we are deciding on
  const itemsToRemoveSignatures = new Set(
    frozenItems.map(item => 
      `${item.name}|${item.type || ''}|${item.frozenUntil}`
    )
  );

    // ========== SAFE TRANSACTION STARTS HERE ==========
  let lootSuccess = false;   // NEW: We will only say "success" if this becomes true

  try {
    await db.runTransaction(async (transaction) => {
      // Read fresh data inside the transaction
      const witnessSnap = await transaction.get(witnessRef);
      const criminalSnap = await transaction.get(criminalRef);

      if (!witnessSnap.exists || !criminalSnap.exists) {
        throw new Error('Player not found during loot transaction');
      }

      let witnessData = witnessSnap.data();
      let criminalData = criminalSnap.data();

      const cleanItems = frozenItems.map(item => {
        const { frozenUntil, ...clean } = item;
        return clean;
      });

      if (choice === 'take') {
        // === WITNESS TAKES THE LOOT (ALL AT ONCE) ===
        if (frozenMoney > 0) {
          witnessData.balance = (witnessData.balance || 0) + frozenMoney;
          criminalData.balance = Math.max(0, (criminalData.balance || 0) - frozenMoney);
        }

        if (cleanItems.length > 0) {
          witnessData.inventory = [...(witnessData.inventory || []), ...cleanItems];
        }

        // Remove the specific frozen items from criminal + clean frozen fields
        const currentInventory = criminalData.inventory || [];
        const updatedInventory = currentInventory.filter(item => {
          const signature = `${item.name}|${item.type || ''}|${item.frozenUntil}`;
          const isPartOfThisDecision = itemsToRemoveSignatures.has(signature);
          if (isPartOfThisDecision) return false;
          const isStillFrozen = item.frozenUntil && item.frozenUntil > Date.now();
          return !item.frozenUntil || isStillFrozen;
        });

        criminalData.inventory = updatedInventory;
        const currentFrozen = criminalData.frozenCrimeMoney || 0;
        criminalData.frozenCrimeMoney = Math.max(0, currentFrozen - frozenMoney);

        if (criminalData.frozenCrimeMoney === 0) {
          delete criminalData.frozenCrimeMoney;
          delete criminalData.crimeFreezeUntil;
        }

      } else {
        // === RETURN / DESTROY LOOT (ALL AT ONCE) ===
        if (frozenMoney > 0) {
          criminalData.balance = Math.max(0, (criminalData.balance || 0) - frozenMoney);
        }

        const currentInventory = criminalData.inventory || [];
        const updatedInventory = currentInventory.filter(item => {
          const signature = `${item.name}|${item.type || ''}|${item.frozenUntil}`;
          const isPartOfThisDecision = itemsToRemoveSignatures.has(signature);
          if (isPartOfThisDecision) return false;
          const isStillFrozen = item.frozenUntil && item.frozenUntil > Date.now();
          return !item.frozenUntil || isStillFrozen;
        });

        criminalData.inventory = updatedInventory;
        const currentFrozen = criminalData.frozenCrimeMoney || 0;
        criminalData.frozenCrimeMoney = Math.max(0, currentFrozen - frozenMoney);

        if (criminalData.frozenCrimeMoney === 0) {
          delete criminalData.frozenCrimeMoney;
          delete criminalData.crimeFreezeUntil;
        }
      }

      // Write everything back in one atomic operation
      transaction.set(witnessRef, witnessData);
      transaction.set(criminalRef, criminalData);
    });

    console.log(`[LOOT] ${choice.toUpperCase()} completed safely for ${witnessName} vs ${decision.perpetrator}`);
    lootSuccess = true;   // ← NEW: Only mark as success if we reach here

  } catch (err) {
    console.error('[LOOT TRANSACTION ERROR]', err);
    // We do NOT set lootSuccess = true here, so it stays false
  }
  // ========== TRANSACTION ENDS HERE ==========

  // Log transactions (only for 'take' case) — only if it actually succeeded
  if (lootSuccess && choice === 'take' && frozenMoney > 0) {
    if (witnessSocket) {
      const witnessData = (await witnessRef.get()).data();
      await logTransaction(witnessSocket, frozenMoney, `Took loot from ${decision.perpetrator}`, witnessData, witnessRef);
    }
    if (criminalSocket) {
      const criminalData = (await criminalRef.get()).data();
      await logTransaction(criminalSocket, -frozenMoney, `Lost loot to ${witnessName} (justice)`, criminalData, criminalRef);
    }
  } else if (lootSuccess && choice === 'return' && frozenMoney > 0 && criminalSocket) {
    const criminalData = (await criminalRef.get()).data();
    await logTransaction(criminalSocket, -frozenMoney, `Lost loot (justice returned)`, criminalData, criminalRef);
  }

  // Send result messages to players — only say success if the transaction worked
  if (witnessSocket) {
    witnessSocket.emit('loot-decision-result', { 
      success: lootSuccess, 
      choice, 
      amount: frozenMoney 
    });
    if (lootSuccess) {
      const updatedWitness = await witnessRef.get();
      witnessSocket.emit('update-stats', updatedWitness.data());
    }
  }

  if (criminalSocket) {
    criminalSocket.emit('loot-decision-result', {
      success: lootSuccess,
      choice,
      takenBy: choice === 'take' ? witnessName : undefined,
      amount: frozenMoney
    });
    if (lootSuccess) {
      const updatedCriminal = await criminalRef.get();
      criminalSocket.emit('update-stats', updatedCriminal.data());
    }
  }

  // Clean up pendingLootDecision from Firestore (we do this even on failure so the player isn't stuck)
  if (witnessQuery.docs[0]) {
    witnessQuery.docs[0].ref.update({
      pendingLootDecision: admin.firestore.FieldValue.delete()
    }).catch(err => console.error('[LOOT] Failed to clear persisted decision (non-fatal):', err));
  }
}

// ==================== GLOBAL PRISON LIST ====================
const imprisonedPlayers = new Map(); // Key: displayName, Value: prisonEndTime
const crimeAlertCooldowns = new Map(); // Key: displayName, Value: cooldownEndTime
const crimeWitnessOpportunities = new Map();
const lootDecisionWindows = new Map();
const humans = new Map();

// ==================== HUMAN FIRESTORE HELPERS ====================
async function saveHumanToFirestore(human) {
  if (!human || !human.name) return;

  try {
    const docId = human.name.toLowerCase().replace(/ /g, '-'); // e.g. "peter-the-beggar"
    await db.collection('humans').doc(docId).set(human.toFirestore());
    console.log(`[HUMANS] Saved ${human.name} to Firestore`);
  } catch (err) {
    console.error('[HUMANS] Failed to save to Firestore:', err);
  }
}

// ==================== AUTO-CLEANUP EXPIRED PRISONERS ====================
// Runs every second. Removes expired prisoners from the in-memory list
// AND also clears prisonEndTime in their Firestore document so they are
// truly free even if they reconnect later.
setInterval(async () => {
  const now = Date.now();
  let changed = false;
  const releasedPlayers = []; // Track who we released this tick

  for (const [displayName, prisonEndTime] of imprisonedPlayers.entries()) {
    if (prisonEndTime <= now) {
      // === Also clear the prison time in Firestore ===
      try {
        const targetQuery = await db.collection('players')
          .where('displayName', '==', displayName)
          .limit(1)
          .get();

        if (!targetQuery.empty) {
          await targetQuery.docs[0].ref.update({
            prisonEndTime: 0
            // We could also add lastLowLevelOp: 0 here if we want them
            // to be able to do low-level ops immediately after release.
          });
        }
      } catch (err) {
        console.error(`[SERVER] Failed to clear prisonEndTime for ${displayName}:`, err);
      }

      imprisonedPlayers.delete(displayName);
      releasedPlayers.push(displayName);
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

        // Re-fetch fresh data after update
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

// ==================== CLEANUP EXPIRED JUSTICE OPPORTUNITIES ====================
setInterval(() => {
    const now = Date.now();
    let cleaned = 0;

    for (const [witnessName, opportunities] of crimeWitnessOpportunities.entries()) {
        for (const [perpetrator, opportunityData] of opportunities.entries()) {
    // Support both old format (just a number) and new format (an object)
    const expiry = typeof opportunityData === 'number' 
        ? opportunityData 
        : opportunityData.expiry;

    if (expiry <= now) {
                opportunities.delete(perpetrator);
                cleaned++;
            }
        }
        if (opportunities.size === 0) {
            crimeWitnessOpportunities.delete(witnessName);
        }
    }

    if (cleaned > 0) {
        console.log(`[JUSTICE] Cleaned up ${cleaned} expired justice opportunities (freeze ends naturally after 17s)`);
    }
}, 30000);

// ==================== CLEANUP EXPIRED LOOT DECISIONS ====================
setInterval(async () => {
  try {
    const now = Date.now();
    const snapshot = await db.collection('players')
      .where('pendingLootDecision.expiry', '<', now)
      .get();

    for (const doc of snapshot.docs) {
      const decision = doc.data().pendingLootDecision;
      if (!decision) continue;

      const witnessName = doc.data().displayName;

      // SAFETY CHECK: If this decision is still actively being handled
      // (timeout is running or player just clicked), skip it.
      // Only run this cleanup for true "orphaned" decisions (server restart, etc.)
      if (lootDecisionWindows.has(witnessName)) {
        continue;
      }

      console.log(`[LOOT] Cleaning up expired persisted decision for ${witnessName}`);

      // Use the new safe helper that works even after server restart
      await cleanupExpiredLootDecision(witnessName, decision);

      // Remove the pending flag from database
      await doc.ref.update({
        pendingLootDecision: admin.firestore.FieldValue.delete()
      });

      // Also remove from memory map (in case it somehow got re-added)
      lootDecisionWindows.delete(witnessName);
    }
  } catch (err) {
    console.error('[LOOT] Error in expired decision cleanup:', err);
  }
}, 30000);

const hospitalOwnershipRef = db.collection('hospitals');

initializeHospitals().catch(console.error);

// ==================== LOAD IMPRISONED PLAYERS FROM DATABASE ON STARTUP ====================
async function loadActiveImprisonedPlayers() {
  const now = Date.now();
  try {
    const snapshot = await db.collection('players')
      .where('prisonEndTime', '>', now)   // only players whose prison time is still in the future
      .get();

    snapshot.docs.forEach(doc => {
      const data = doc.data();
      if (data.displayName && data.prisonEndTime > now) {
        imprisonedPlayers.set(data.displayName, data.prisonEndTime);
      }
    });

    console.log(`[SERVER] Loaded ${imprisonedPlayers.size} imprisoned players from database after startup`);
  } catch (err) {
    console.error('[SERVER] Failed to load imprisoned players:', err);
  }
}

// ==================== Clean up any frozen money/items left over after a server restart ====================
// This runs only ONCE when the server starts.
// It finds any criminal who still has frozen loot from before the restart and unfreezes them.
// This fixes the "orphaned freeze" problem.
async function cleanupOrphanedCrimeFreezesOnStartup() {
  console.log('[STARTUP] Checking for any leftover frozen crime loot from before restart...');

  try {
    // Ask the database: "Give me all players who have a crimeFreezeUntil time in the future"
    const now = Date.now();
    const snapshot = await db.collection('players')
      .where('crimeFreezeUntil', '>', now)
      .get();

    if (snapshot.empty) {
      console.log('[STARTUP] No leftover frozen loot found. Everything is clean.');
      return;
    }

    console.log(`[STARTUP] Found ${snapshot.size} player(s) with leftover frozen loot. Clearing them now...`);

    // For every player we found, unfreeze them
    for (const doc of snapshot.docs) {
      const displayName = doc.data().displayName;
      if (displayName) {
        await clearCrimeFreezeForPlayer(displayName);
        console.log(`[STARTUP] Cleared frozen loot for ${displayName}`);
      }
    }

    console.log('[STARTUP] Finished clearing leftover frozen loot.');
  } catch (err) {
    console.error('[STARTUP] Error while cleaning leftover frozen loot:', err);
  }
}

// Call the function when server starts
loadActiveImprisonedPlayers().catch(console.error);
cleanupOrphanedCrimeFreezesOnStartup().catch(console.error);

// ==================== ONLINE PLAYERS TRACKING ====================
const onlinePlayers = new Set();
const onlineSockets = new Map();

// ==================== START ALL AUTO-CHECKERS ====================
startBondMaturityChecker(db, { onlineSockets });
reconcileBondFlags(db).catch(console.error);
startDriverSalaryChecker(db, { onlineSockets });
startDriverProgressChecker(db);
startTaxiJobChecker(db, { onlineSockets });
startHospitalMaintenanceChecker(db, { onlineSockets, io });
startHospitalResearchChecker(db, { io });  // generalized checker for all researches
catchUpEfficientDoctorsResearch(db, { io });
catchUpPerformanceResearches(db, { io });

const timeFormatter = new Intl.DateTimeFormat('en-GB', { 
  timeZone: 'Europe/London', 
  hour: '2-digit', 
  minute: '2-digit', 
  hour12: false 
});

setInterval(() => {
  io.emit('time', {
    formatted: timeFormatter.format(new Date()),
    serverTime: Date.now()
  });
}, 30000);

io.on('connection', (socket) => {
  socket.on('register', async (data) => {
    const email = data.email;
    // ==================== DISPLAY NAME VALIDATION ====================
    let displayName = (data.displayName || 'Anonymous').trim();

    if (displayName.length > 22) {
      socket.emit('error', { message: 'Display name cannot exceed 22 characters.' });
      return;
    }
    if (displayName.length === 0) {
      displayName = 'Anonymous';
    }
    if (['.', '/', '\\'].includes(displayName[0])) {
      socket.emit('error', { message: 'Display name cannot start with ".", "/", or "\\".' });
      return;
    }

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
      if (playerData.strength === undefined) playerData.strength = 0;
      if (playerData.physicalToll === undefined) playerData.physicalToll = 0;
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
      if (playerData.prisonEndTime && Date.now() >= playerData.prisonEndTime) {
        playerData.prisonEndTime = 0;
      }
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
      if (playerData.scoutedDrivers === undefined) playerData.scoutedDrivers = [];
      if (playerData.hiredDrivers === undefined) playerData.hiredDrivers = [];
      if (playerData.activeSpecialOperation === undefined) playerData.activeSpecialOperation = null;
      if (playerData.activeSpecialOperationParty === undefined) playerData.activeSpecialOperationParty = null;
      if (playerData.usedAdForHealing === undefined) playerData.usedAdForHealing = false;
      if (playerData.pendingLootDecision === undefined) playerData.pendingLootDecision = null;
      playerData = updateMaxHealth(playerData);

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

      const wasCleaned = cleanupExpiredCrimeFreeze(playerData);
      if (wasCleaned) {
        console.log(`[CLEANUP] Removed expired crime freeze data for ${playerData.displayName || email}`);
      }

      await docRef.set(playerData);
    } else {
      const randomLocation = normalLocations[Math.floor(Math.random() * normalLocations.length)];

      playerData = {
        balance: 0,
        health: 100,
        maxHealth: 100,
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
        strength: 0,
        physicalToll: 0,
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
        usedAdForHealing: false,
        ownedUpgrades: {},
        unallocatedAttributePoints: 0,
        taxiFleet: [],
        scoutedDrivers: [],
        hiredDrivers: [],
        hasActiveTaxiJobs: false,
        activeSpecialOperation: null,
        activeSpecialOperationParty: null,
        pendingLootDecision: null,
      };
      playerData.rank = getRankTitle(playerData.experience || 0);
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
    // If this player is still in prison, add them to the memory list so prison list and rescue work
    if (playerData.prisonEndTime && Date.now() < playerData.prisonEndTime && playerData.displayName) {
      imprisonedPlayers.set(playerData.displayName, playerData.prisonEndTime);
      console.log(`[SERVER] ${playerData.displayName} reconnected while in prison - tracking restored`);
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
      weapons: weaponTemplates,
      hospitalCounts: hospitalCounts,
      hospitalOwnership: await getAllHospitalOwnership()
    });
    socket.emit('time', timeFormatter.format(new Date()));

    // ==================== LOOT DECISION PENDING (on reconnect) ====================
    let activeDecision = lootDecisionWindows.get(socket.data.displayName);

    // If not in memory, try to load from Firestore (handles server restart)
    if (!activeDecision && playerData.pendingLootDecision) {
      const saved = playerData.pendingLootDecision;
      const now = Date.now();

      if (saved.expiry > now) {
        // Still valid — re-hydrate into memory
        const remainingTime = saved.expiry - now;

        const decisionData = {
          perpetrator: saved.perpetrator,
          expiry: saved.expiry,
          frozenMoney: saved.frozenMoney,
          frozenItems: saved.frozenItems
        };

        // Re-schedule the auto-return timeout with remaining time
        const timeoutId = setTimeout(async () => {
          try {
            await processLootDecision(socket.data.displayName, 'return', null, true);
          } catch (err) {
            console.error(`[LOOT] Auto-forfeit failed after restart for ${socket.data.displayName}:`, err);
          }
          lootDecisionWindows.delete(socket.data.displayName);
        }, remainingTime);

        decisionData.timeoutId = timeoutId;
        lootDecisionWindows.set(socket.data.displayName, decisionData);
        activeDecision = decisionData;

        console.log(`[LOOT] Re-hydrated pending decision for ${socket.data.displayName} after reconnect/restart`);
      } else {
        // Expired while server was down — properly clean the criminal's frozen state too
        console.log(`[LOOT] Cleaning expired decision during reconnect for ${socket.data.displayName}`);
        await cleanupExpiredLootDecision(socket.data.displayName, saved);
        
        const docRef = db.collection('players').doc(socket.data.email);
        await docRef.update({ pendingLootDecision: admin.firestore.FieldValue.delete() }).catch(() => {});
      }
    }

    if (activeDecision) {
      socket.emit('loot-decision-pending', {
        perpetrator: activeDecision.perpetrator,
        expiry: activeDecision.expiry,
        frozenMoney: activeDecision.frozenMoney
      });
    }
  });

  registerRespawnHandler(socket, { db, normalLocations, getRankTitle });

  // ==================== TEST BUTTONS ====================
  socket.on('add-test-exp', async (amount) => { await handleAddTestExp(db, socket, amount) });
  socket.on('add-test-money', async (amount) => { await handleAddTestMoney(db, socket, amount) });
  socket.on('add-test-bullets', async (amount) => { await handleAddTestBullets(db, socket, amount) });
  socket.on('reset-martial-art', async () => { await handleResetMartialArt(db, socket) });

  // ==================== RESET PETER HUNGER (Developer Tool) ====================
  socket.on('reset-peter-hunger', async () => {
    const peter = humans.get('Peter the Beggar');
    if (!peter) return;

    peter.hunger = 100;
    peter.lastHungerUpdate = Date.now();

    // Also save to Firestore immediately
    await db.collection('humans').doc('peter-the-beggar').update({
      hunger: 100,
      lastHungerUpdate: Date.now()
    });

    console.log('[PETER] Hunger manually reset to 100 by admin');
  });
  // ==================== COURSES ====================
  socket.on('request-courses', () => {handleRequestCourses(db, socket);});
  socket.on('purchase-course', async (courseId) => {await handlePurchaseCourse(db, socket, courseId, { onlineSockets, syncPartyTeamSynergy });});
  socket.on('course-completed', async (courseId) => {
    const email = socket.data.email;
    if (!email) return;

    const isTeamSynergy = ["team-synergy", "advanced-team-synergy", "exceptional-team-synergy"].includes(courseId);
    if (!isTeamSynergy) return;

    console.log(`[COURSE] ${email} completed ${courseId} — triggering party refresh`);
    await syncPartyTeamSynergy(db, email, { onlineSockets });
  });

  // ==================== TAXI TYCOON, HOSPITAL & FITNESS ====================
  registerTaxiHandlers(socket, { db });
  registerHospitalHandlers(socket, { db, hospitalOwnershipRef, onlineSockets, ENHANCED_STAMINA_RESEARCH, ENHANCED_CONSTITUTION_RESEARCH });
  registerFitnessHandlers(socket, { db, logTransaction });
  registerSellHandlers(socket, { db, logTransaction });

  // ====================== KILL ATTEMPT ======================
  socket.on('attempt-kill', async (data) => {
    await handleKillAttempt(db, socket, data, { 
      onlineSockets, 
      onlinePlayers, 
      io,
      removeFromOnlineList
    });
  });

socket.on('deliver-justice', async (data) => {
  const witnessName = socket.data.displayName;
  const perpetratorName = data?.perpetrator;
  if (!witnessName || !perpetratorName) return;

  // Validate 6-second opportunity
  const opportunities = crimeWitnessOpportunities.get(witnessName);
const opportunityData = opportunities?.get(perpetratorName);

// Get the expiry time (works for both old number and new object)
const opportunityExpiry = typeof opportunityData === 'number' 
    ? opportunityData 
    : opportunityData?.expiry;

if (!opportunityExpiry || Date.now() > opportunityExpiry) {
    socket.emit('deliver-justice-result', {
      success: false,
      message: 'You did not witness this crime or the opportunity has expired.'
    });
    return;
  }

  // Consume the justice opportunity
  opportunities.delete(perpetratorName);
  if (opportunities.size === 0) crimeWitnessOpportunities.delete(witnessName);

  // Cancel the 6-second auto-unfreeze timer because the witness took action
if (typeof opportunityData === 'object' && opportunityData.timeoutId) {
  clearTimeout(opportunityData.timeoutId);
  console.log(`[JUSTICE] Cancelled 6s auto-unfreeze timer for ${perpetratorName} because ${witnessName} acted`);
}

  const witnessQuery = await db.collection('players').where('displayName', '==', witnessName).limit(1).get();
  const criminalQuery = await db.collection('players').where('displayName', '==', perpetratorName).limit(1).get();

  if (witnessQuery.empty || criminalQuery.empty) {
  console.log(`[JUSTICE] Criminal or witness no longer exists during deliver-justice.`);
  return;
}

  const witnessDoc = witnessQuery.docs[0];
  const criminalDoc = criminalQuery.docs[0];
  const witness = witnessDoc.data();
  const criminal = criminalDoc.data();

  // ==================== ARCHETYPE + RPS + SCORING (keep existing logic) ====================
  const wStr = witness.strength || 0;
  const wSte = witness.stealth || 0;
  const cStr = criminal.strength || 0;
  const cSte = criminal.stealth || 0;

  const witnessTotal = wStr + wSte;
  const criminalTotal = cStr + cSte;

  const getArchetype = (str, ste) => {
    // Safety check: if either stat is zero, we can't divide
    if (str === 0 && ste === 0) return 'Mixed';
    if (str === 0) return 'Pure Stealth';
    if (ste === 0) return 'Pure Strength';

    const ratio = Math.max(str, ste) / Math.min(str, ste);
    if (ratio >= 1.5) return str > ste ? 'Pure Strength' : 'Pure Stealth';
    return 'Mixed';
  };

  const witnessArchetype = getArchetype(wStr, wSte);
  const criminalArchetype = getArchetype(cStr, cSte);

  let rpsWinner = null;
  if (witnessArchetype === criminalArchetype) {
    rpsWinner = 'tie';
  } else if (
    (witnessArchetype === 'Pure Stealth' && criminalArchetype === 'Mixed') ||
    (witnessArchetype === 'Mixed' && criminalArchetype === 'Pure Strength') ||
    (witnessArchetype === 'Pure Strength' && criminalArchetype === 'Pure Stealth')
  ) {
    rpsWinner = 'witness';
  } else {
    rpsWinner = 'criminal';
  }

  // ==================== SCORE + BONUS CALCULATION ====================
  let witnessScore = 0;
  let criminalScore = 0;
  let archetypeBonus = 0;
  let dominanceBonus = 0;

  let witnessInvestmentBonus = 0;
  let criminalInvestmentBonus = 0;

  if (rpsWinner === 'witness') {
    archetypeBonus = 24;
    dominanceBonus = Math.min((Math.max(wStr, wSte) / Math.max(Math.max(cStr, cSte), 1)) * 12, 30);
    witnessInvestmentBonus = Math.min(witnessTotal / 3, 20);

    witnessScore = archetypeBonus + dominanceBonus + witnessInvestmentBonus;
    criminalScore = 20;

  } else if (rpsWinner === 'criminal') {
    archetypeBonus = 24;
    dominanceBonus = Math.min((Math.max(cStr, cSte) / Math.max(Math.max(wStr, wSte), 1)) * 12, 30);
    criminalInvestmentBonus = Math.min(criminalTotal / 3, 20);

    criminalScore = archetypeBonus + dominanceBonus + criminalInvestmentBonus;
    witnessScore = 20;

  } else {
    // ==================== TIE LOGIC ====================
    witnessScore = 10;
    criminalScore = 10;
    archetypeBonus = 10;

    if (witnessTotal > criminalTotal) {
      witnessInvestmentBonus = witnessTotal / 3;
      criminalInvestmentBonus = criminalTotal / 4.5;
    } else if (criminalTotal > witnessTotal) {
      criminalInvestmentBonus = criminalTotal / 3;
      witnessInvestmentBonus = witnessTotal / 4.5;
    } else {
      witnessInvestmentBonus = 10;
      criminalInvestmentBonus = 10;
    }

    witnessScore += witnessInvestmentBonus;
    criminalScore += criminalInvestmentBonus;
  }

  const witnessRoll = Math.floor(Math.random() * (70 - 22 + 1)) + 22;
  const criminalRoll = Math.floor(Math.random() * (70 - 22 + 1)) + 22;

  const witnessFinal = witnessRoll + witnessScore;
  const criminalFinal = criminalRoll + criminalScore;
  const witnessWins = witnessFinal > criminalFinal;

  // ==================== EMIT RESULTS ====================
  const payload = {
    witnessName,
    perpetratorName,
    witnessArchetype,
    criminalArchetype,
    rpsWinner,
    witnessScore: Math.round(witnessScore),
    criminalScore: Math.round(criminalScore),
    witnessFinal: Math.round(witnessFinal),
    criminalFinal: Math.round(criminalFinal),
    witnessRoll,
    criminalRoll,
    archetypeBonus: Math.round(archetypeBonus),
    dominanceBonus: Math.round(dominanceBonus),
    witnessInvestmentBonus: Math.round(witnessInvestmentBonus),
    criminalInvestmentBonus: Math.round(criminalInvestmentBonus),
    isWinner: witnessWins,
    viewerIsWitness: true
  };

  socket.emit('deliver-justice-result', payload);

  const criminalSocket = onlineSockets.get(perpetratorName);
  if (criminalSocket) {
    criminalSocket.emit('deliver-justice-result', {
      ...payload,
      isWinner: !witnessWins,
      viewerIsWitness: false
    });
  }

  if (!witnessWins) {
    clearCrimeFreezeForPlayer(db, perpetratorName);
  }

  // ==================== EFFICIENT: Start 10s loot decision with setTimeout ====================
  if (witnessWins) {
    // === IMPORTANT FIX: Use ONLY the money from THIS specific crime ===
    const frozenMoney = (typeof opportunityData === 'object' && opportunityData.frozenAmount) 
        ? opportunityData.frozenAmount 
        : (criminal.frozenCrimeMoney || 0);

    // For Mug/Loot grocery crimes, there are no items stolen in the success loot.
    // So we set frozenItems to empty array. This prevents taking other crimes' items.
    const frozenItems = [];

    const decisionData = {
      perpetrator: perpetratorName,
      expiry: Date.now() + 10000,
      frozenMoney,
      frozenItems: JSON.parse(JSON.stringify(frozenItems))
    };

    // Schedule automatic "Return" after 10 seconds
    const timeoutId = setTimeout(async () => {
      try {
        await processLootDecision(witnessName, 'return', null, true);
      } catch (err) {
        console.error(`[LOOT] Auto-forfeit failed for ${witnessName}:`, err);
      }
      lootDecisionWindows.delete(witnessName);
    }, 10000);

    decisionData.timeoutId = timeoutId;
    lootDecisionWindows.set(witnessName, decisionData);

    // === Tell the player RIGHT NOW that they have a loot decision ===
    socket.emit('loot-decision-pending', {
      perpetrator: decisionData.perpetrator,
      expiry: decisionData.expiry,
      frozenMoney: decisionData.frozenMoney
    });

    const witnessDocRef = db.collection('players').doc(socket.data.email);
    witnessDocRef.update({
        pendingLootDecision: {
            perpetrator: perpetratorName,
            expiry: decisionData.expiry,
            frozenMoney: decisionData.frozenMoney,
            frozenItems: decisionData.frozenItems,
            createdAt: Date.now()
        }
    }).catch(err => console.error('[LOOT] Failed to persist decision:', err));

    console.log(`[JUSTICE] ${witnessName} won on ${perpetratorName}. 10s loot decision scheduled.`);
  }
});

// ==================== Decide-loot-fate ====================
socket.on('decide-loot-fate', async (data) => {
  const witnessName = socket.data.displayName;
  const { perpetrator, choice } = data;

  if (!witnessName || !perpetrator || !['take', 'return'].includes(choice)) return;

  const decision = lootDecisionWindows.get(witnessName);
  if (!decision || decision.perpetrator !== perpetrator) {
    socket.emit('loot-decision-result', { success: false, message: 'No active loot decision.' });
    return;
  }

  // Extra safety: respect the expiry timestamp
  if (Date.now() > decision.expiry) {
    // Timer already expired or about to — let the timeout handle it
    socket.emit('loot-decision-result', { success: false, message: 'The decision window has closed.' });
    return;
  }

  await processLootDecision(witnessName, choice, socket);
});

  // ==================== MARTIAL ARTS SELECTION ====================
  socket.on('select-martial-art', async (data) => {
    const email = socket.data.email;
    if (!email || !data.martialArt) return;

    const docRef = db.collection('players').doc(email);
    await docRef.update({ martialArt: data.martialArt });

    const updatedDoc = await docRef.get();
    socket.emit('update-stats', updatedDoc.data());
  });

  // ==================== PLACE HIT (BOUNTY) ====================
socket.on('place-hit', async (data) => {
  const posterEmail = socket.data.email;
  if (!posterEmail || typeof data.target !== 'string' || typeof data.reward !== 'number' || data.reward < 1000) {
    socket.emit('hit-result', { success: false, message: 'Invalid hit details.' });
    return;
  }

  const posterDoc = await db.collection('players').doc(posterEmail).get();
  if (!posterDoc.exists) return;

  let poster = posterDoc.data();

  // Clean up expired crime freeze data if needed
  const wasCleaned = cleanupExpiredCrimeFreeze(poster);
  if (wasCleaned) {
    await posterDoc.ref.set(poster);
  }

  // ==================== Respect crime freeze ====================
  if (getAvailableBalance(poster) < data.reward) {
    socket.emit('hit-result', { 
      success: false, 
      message: 'Not enough money for the bounty (some funds may be temporarily frozen)' 
    });
    return;
  }

  const durationMinutes = data.durationDays || 5;
  const durationMs = Math.max(durationMinutes * 60 * 1000, 5 * 60 * 1000);

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
  await logTransaction(socket, -data.reward, `Bounty Placed on ${data.target}`, posterDoc.data(), posterDoc.ref);

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
      crimeAlertCooldowns,
      crimeWitnessOpportunities,
      removeFromOnlineList
    });
  });

  // ==================== INITIATE SPECIAL OPERATION (now modular) ====================
  socket.on('initiate-special-op', async (data) => { await handleInitiateSpecialOp(db, socket, data, logTransaction); });

  socket.on('cancel-special-op', async () => {
    await handleCancelSpecialOp(db, socket, { onlineSockets });  // pass onlineSockets
  });

  socket.on('leave-special-op', () => handleLeaveSpecialOp(db, socket, { onlineSockets }));

  socket.on('assign-special-weapon', async (data) => {
    await handleAssignSpecialWeapon(db, socket, data, { onlineSockets });
  });

  socket.on('accept-special-op-invite', async (data) => {
    await handleAcceptSpecialOpInvite(db, socket, data, { onlineSockets });
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
  const saverStealth = saver.stealth || 0;                    // ← Get Stealth

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

  // ==================== DYNAMIC RESCUE CHANCE ====================
  let rescueChance = 0.75; // Base chance

  if (saverStealth >= 10) {
    rescueChance = 0.80; // +5% from Stealth
  }

  const isSuccess = Math.random() < rescueChance;

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

        // Trigger full-screen celebration
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

  socket.on('travel', async (destination) => { await handleTravel(db, socket, destination); });

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

  socket.on('purchase-armor', async (data) => { // Purchase armor
    const email = socket.data.email;
    if (!email || !Array.isArray(data.items) || typeof data.totalCost !== 'number') return;

    const docRef = db.collection('players').doc(email);
    const doc = await docRef.get();
    if (!doc.exists) return;

    let p = doc.data();

    const wasCleaned = cleanupExpiredCrimeFreeze(p);
    if (wasCleaned) {
      await docRef.set(p);
    }

    const availableBalance = getAvailableBalance(p);
    if (availableBalance < data.totalCost) {
        socket.emit('error', { message: 'Not enough money (some funds may be temporarily frozen)' });
        return;
    }

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
  
  // ==================== WEAPONS ====================
  socket.on('request-weapons', () => handleRequestWeapons(socket));

  socket.on('purchase-weapons', async (data) => {
    await handlePurchaseWeapons(db, socket, data);
  });
  
  socket.on('equip-armor', async (data) => { // Equip armor
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

    // Marksmanship bonus only applies to weapons
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

  socket.on('buy-property', async (propertyName) => {await handleBuyProperty(db, socket, propertyName);});

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

    // Always recalculate personal power if they have a personal weapon
    if (attribute === 'marksmanship' && p.weapon?.power != null) {
      p = recalculateOverallPower(p);
      console.log(`[SERVER] Marksmanship ${oldMarksmanship} → ${p.marksmanship} | Personal Power ${oldPower} → ${p.overallPower} for ${email}`);
    }

    // ==================== CRITICAL: Update party even if player has NO personal weapon ====================
    if (attribute === 'marksmanship' && p.activeSpecialOperationParty) {
      await syncPartyMemberMarksmanship(db, email, p.marksmanship, { onlineSockets });
    }

    await docRef.set(p);
    socket.emit('update-stats', p);
    console.log(`[SERVER] Allocated ${attribute} for ${email}`);
  });

  // Handler for claiming income (now per-property)
  socket.on('claim-income', async () => {await handleClaimIncome(db, socket);});

  // ==================== BOND MARKET HANDLERS (with 2-minute cooldown) ====================
  socket.on('request-bond-market', async () => {await handleRequestBondMarket(db, socket);});
  socket.on('refresh-bond-market', async () => {await handleRefreshBondMarket(db, socket);});
  socket.on('buy-bond', async (bondData) => {await handleBuyBond(db, socket, bondData);});

// ==================== PRIVATE MESSAGES (supports text + structured invites) ====================
socket.on('private-message', async (data) => {
  if (!data || typeof data.to !== 'string') return;

  const from = socket.data.displayName;
  if (!from) return;

  const msgId = data.id || Date.now().toString();

  // Support BOTH classic string messages AND structured objects (special invites, etc.)
  let messageContent;
  if (typeof data.msg === 'string') {
    messageContent = data.msg;                    // normal chat message
  } else if (data.type === 'special_invite' || data.type) {
    messageContent = { ...data };                 // keep the full structured object
  } else {
    return; // invalid payload
  }

  const baseMsg = {
    from: from,
    msg: messageContent,     // ← can now be string OR object
    id: msgId
  };

  // Find recipient by name (assume unique)
    const querySnapshot = await db.collection('players').where('displayName', '==', data.to).limit(1).get();
    if (querySnapshot.empty) return;

    const recipientDoc = querySnapshot.docs[0];
    const toEmail = recipientDoc.id;
    const recipientData = recipientDoc.data();

    // Save message for recipient
    const msgForRecipient = {
      type: 'private',
      data: baseMsg,
      timestamp: new Date().toISOString(),
      isRead: false
    };

    await recipientDoc.ref.update({
      messages: admin.firestore.FieldValue.arrayUnion(msgForRecipient)
    });

    // Save for sender too
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
      // Send push if offline (use sendEachForMulticast)
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
          sender: from,
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
      // Save to special announcements box
      const annRef = await db.collection('announcements').add({
        text: text,
        timestamp: new Date().toISOString()
      });
      const annId = annRef.id;

      // Send to all online
      io.emit('announcement', { text: text, id: annId });

      // Send push to group
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

    // === STEP 1: Check if this is still the CURRENT connection ===
    // We look up what socket the server currently thinks belongs to this player
    const currentSocket = onlineSockets.get(name);

    // Only continue with removal if this disconnecting socket
    // is the SAME object as the one we have saved as current.
    // If it's an OLD socket (player already reconnected), we ignore it.
    if (currentSocket === socket) {
      // This is the real/current connection disconnecting → safe to remove

      // === Clean up any active loot decision for this player ===
      const decision = lootDecisionWindows.get(name);
      if (decision && decision.timeoutId) {
        clearTimeout(decision.timeoutId);
        console.log(`[LOOT] Cancelled pending loot decision timeout for ${name} (disconnected)`);
      }

      if (decision && decision.perpetrator) {
        clearCrimeFreezeForPlayer(db, decision.perpetrator).catch(err => {
          console.error(`[LOOT] Failed to unfreeze criminal ${decision.perpetrator} after ${name} disconnected:`, err);
        });
        console.log(`[LOOT] Unfroze ${decision.perpetrator} because witness ${name} disconnected during loot decision`);
      }

      lootDecisionWindows.delete(name);

      // === FIX for dangling state: Also remove the "sticky note" from the database ===
      if (socket.data.email) {
        const playerRef = db.collection('players').doc(socket.data.email);
        playerRef.update({
          pendingLootDecision: admin.firestore.FieldValue.delete()
        }).catch(() => {
          // We ignore any error
        });
      }

      // Now safely remove from online list
      removeFromOnlineList(name);
      crimeWitnessOpportunities.delete(name);

      console.log(`[SERVER] ${name} left - online now: ${onlinePlayers.size}`);
    } else {
      // This is an OLD socket disconnecting after the player already reconnected.
      // We do NOT remove them from the online list.
      // We still clean up loot decisions (safety), but skip the online list removal.
      console.log(`[SERVER] Old/stale disconnect ignored for ${name} (player reconnected with new socket)`);
      
      // Optional: still clean up loot decisions for safety
      const decision = lootDecisionWindows.get(name);
      if (decision && decision.timeoutId) {
        clearTimeout(decision.timeoutId);
      }
      lootDecisionWindows.delete(name);
    }
  }
});
});

// ==================== INITIALIZE HUMANS (WITH FIRESTORE PERSISTENCE) ====================
async function initializeHumans() {
  try {
    const docId = 'peter-the-beggar';
    const doc = await db.collection('humans').doc(docId).get();

    if (doc.exists) {
      const data = doc.data();
      const peter = new Human(data);

      peter.vicinity = [];

      // Calculate missed hunger since last save
      if (data.lastHungerUpdate) {
        const millisecondsPassed = Math.max(0, Date.now() - (data.lastHungerUpdate || 0));   
        const missedTicks = Math.floor(millisecondsPassed / 30000);
        const hungerLost = missedTicks * 1;
        peter.hunger = Math.max(0, peter.hunger - hungerLost);
      }

      peter.lastHungerUpdate = Date.now();

      humans.set(peter.name, peter);
      console.log('[HUMANS] Loaded Peter the Beggar from Firestore');

    } else {
      // First time creating Peter
      const peter = new Human({
        name: 'Peter the Beggar',
        health: 100,
        hunger: 100,
        balance: 5,
        strength: 8,
        stealth: 4,
        martialArt: 'Judo',
        weapon: null,
        drunk: false,
        vicinity: [],
        lastHungerUpdate: Date.now()
      });

      humans.set(peter.name, peter);
      await saveHumanToFirestore(peter);
      console.log('[HUMANS] Created and saved Peter the Beggar to Firestore');
    }

    setupPeterTheBeggar(humans, onlinePlayers, onlineSockets);

  } catch (err) {
    console.error('[HUMANS] Error initializing humans from Firestore:', err);
  }
}

initializeHumans();

// Periodic backup save for Peter every 5 minutes (name is never re-written)
setInterval(async () => {
  const peter = humans.get('Peter the Beggar');
  if (!peter) return;

  const docId = 'peter-the-beggar';

  try {
    await db.collection('humans').doc(docId).set({
      hunger: peter.hunger,
      lastHungerUpdate: Date.now(),
      updatedAt: Date.now()
    }, { merge: true });

    console.log('[HUMANS] Periodic backup save for Peter the Beggar (partial update)');
  } catch (err) {
    console.error('[HUMANS] Failed to save Peter to Firestore:', err);
  }
}, 5 * 60 * 1000);

const port = process.env.PORT || 3000;
server.listen(port, () => console.log(`Server running on ${port}`));
