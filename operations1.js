const admin = require('firebase-admin');
const { logTransaction, cleanupExpiredCrimeFreeze, clearCrimeFreezeForPlayer } = require('./utils');
const { markPlayerAsDead } = require('./combat.js');
const { weaponTemplates } = require('./weapons.js');
const { getPrisonChance } = require('./operations_prison_chance');
const { calculateBulletSteal } = require('./operations_bullets');
const { handleBrokenBone } = require('./operations_broken_bones');
const { applySuccessLoot } = require('./operations_success_loot');

const lowLevelOps = ["Mug a passerby", "Loot a grocery store", "Rob a bank", "Loot weapons store"];
const midLevelOps = ["Attack military barracks", "Storm a laboratory", "Attack central issue facility"];
const highLevelOps = ["Strike an armory", "Raid a vehicle depot", "Assault an aircraft hangar", "Invade country"];

const validOperations = new Set([
  ...lowLevelOps,
  ...midLevelOps,
  ...highLevelOps
]);

// ==================== CONSTANTS (for maintainability) ====================
const JUSTICE_WINDOW_MS = 6000;      // Time witness has to decide take/return
const CRIME_FREEZE_MS = 17000;       // How long criminal's loot is frozen
const ALERT_COOLDOWN_MS = 10000;     // Cooldown before same witness can be alerted again
const WITNESS_TRIGGER_PROB = 0.95;   // 95% chance a successful low-level crime triggers justice system

function resolveOperation(p, operation, level, exp) {
  let money = 0;
  let rawDamage = 0;
  let expGain = 0;
  let message = "";
  let stolenWeapon = null;
  let epinephrine = null;
  let bulletsStolen = 0;
  let shouldDie = false;
  let oldDisplayName = null;
  let oldBalance = p.balance || 0;
  let boneCooldownTime = Date.now();
  let actualDamage = 0;
  let totalDefense = 0;

  const now = Date.now();

  // OPERATION REWARD CALCULATION =====================================================

  if (operation === "Mug a passerby") {
    const hasBasic = (p.completedCourses || []).some(c =>
      c.id === "street-tactics" && (c.completionTime ?? 0) <= now
    );
    const hasAdvanced = (p.completedCourses || []).some(c =>
      c.id === "advanced-street-tactics" && (c.completionTime ?? 0) <= now
    );
    const hasExceptional = (p.completedCourses || []).some(c =>
      c.id === "exceptional-street-tactics" && (c.completionTime ?? 0) <= now
    );

    if (hasExceptional) {
      money = Math.floor(Math.random() * 101) + 36;
      expGain = 22;
    } else if (hasAdvanced) {
      money = Math.floor(Math.random() * 97) + 28;
      expGain = 18;
    } else if (hasBasic) {
      money = Math.floor(Math.random() * 93) + 20;
      expGain = 14;
    } else {
      money = Math.floor(Math.random() * 91) + 10;
      expGain = 10;
    }

    rawDamage = Math.floor(Math.random() * 26) + 5;
    message = `You mugged a passerby and got $${money}!`;

  } else if (operation === "Loot a grocery store") {
    const hasAdvanced = (p.completedCourses || []).some(c =>
      c.id === "advanced-street-tactics" && (c.completionTime ?? 0) <= now
    );
    const hasExceptional = (p.completedCourses || []).some(c =>
      c.id === "exceptional-street-tactics" && (c.completionTime ?? 0) <= now
    );

    if (hasExceptional) {
      money = Math.floor(Math.random() * 73) + 48;
      expGain = 22;
    } else if (hasAdvanced) {
      money = Math.floor(Math.random() * 71) + 40;
      expGain = 19;
    } else {
      money = Math.floor(Math.random() * 71) + 30;
      expGain = 15;
    }

    rawDamage = Math.floor(Math.random() * 21) + 15;
    message = `You looted the grocery store and stole $${money}!`;

  } else if (operation === "Rob a bank") {
    rawDamage = Math.floor(Math.random() * 41) + 15;

    const hasExceptional = (p.completedCourses || []).some(c =>
      c.id === "exceptional-street-tactics" && (c.completionTime ?? 0) <= now
    );

    if (hasExceptional) {
      expGain = 29;

      if (exp <= 49)          money = Math.floor(Math.random() * 61) + 30;
      else if (exp <= 514)    money = Math.floor(Math.random() * 71) + 30;
      else if (exp <= 1264)   money = Math.floor(Math.random() * 81) + 40;
      else if (exp <= 2314)   money = Math.floor(Math.random() * 91) + 60;
      else if (exp <= 3514)   money = Math.floor(Math.random() * 101) + 80;
      else if (exp <= 5014)   money = Math.floor(Math.random() * 111) + 90;
      else if (exp <= 6864)   money = Math.floor(Math.random() * 121) + 120;
      else if (exp <= 8864)   money = Math.floor(Math.random() * 111) + 150;
      else if (exp <= 10214)  money = Math.floor(Math.random() * 121) + 180;
      else if (exp <= 11464)  money = Math.floor(Math.random() * 141) + 200;
      else if (exp <= 14214)  money = Math.floor(Math.random() * 121) + 240;
      else if (exp <= 17414)  money = Math.floor(Math.random() * 126) + 275;
      else if (exp <= 21364)  money = Math.floor(Math.random() * 156) + 320;
      else if (exp <= 25864)  money = Math.floor(Math.random() * 241) + 360;
      else if (exp <= 31514)  money = Math.floor(Math.random() * 251) + 450;
      else if (exp <= 38214)  money = Math.floor(Math.random() * 281) + 500;
      else                    money = Math.floor(Math.random() * 401) + 600;

      money += 8;
    } else {
      expGain = 25;

      if (exp <= 49)          money = Math.floor(Math.random() * 61) + 30;
      else if (exp <= 514)    money = Math.floor(Math.random() * 71) + 30;
      else if (exp <= 1264)   money = Math.floor(Math.random() * 81) + 40;
      else if (exp <= 2314)   money = Math.floor(Math.random() * 91) + 60;
      else if (exp <= 3514)   money = Math.floor(Math.random() * 101) + 80;
      else if (exp <= 5014)   money = Math.floor(Math.random() * 111) + 90;
      else if (exp <= 6864)   money = Math.floor(Math.random() * 121) + 120;
      else if (exp <= 8864)   money = Math.floor(Math.random() * 111) + 150;
      else if (exp <= 10214)  money = Math.floor(Math.random() * 121) + 180;
      else if (exp <= 11464)  money = Math.floor(Math.random() * 141) + 200;
      else if (exp <= 14214)  money = Math.floor(Math.random() * 121) + 240;
      else if (exp <= 17414)  money = Math.floor(Math.random() * 126) + 275;
      else if (exp <= 21364)  money = Math.floor(Math.random() * 156) + 320;
      else if (exp <= 25864)  money = Math.floor(Math.random() * 241) + 360;
      else if (exp <= 31514)  money = Math.floor(Math.random() * 251) + 450;
      else if (exp <= 38214)  money = Math.floor(Math.random() * 281) + 500;
      else                    money = Math.floor(Math.random() * 401) + 600;
    }

    message = `You robbed the bank and escaped with $${money}!`;

  } else if (operation === "Loot weapons store") {
    const hasExceptional = (p.completedCourses || []).some(c =>
      c.id === "exceptional-street-tactics" && (c.completionTime ?? 0) <= now
    );

    if (hasExceptional) {
      money = Math.floor(Math.random() * 41) + 15;
      expGain = 13;
    } else {
      money = Math.floor(Math.random() * 41) + 10;
      expGain = 10;
    }

    rawDamage = Math.floor(Math.random() * 41) + 20;
    message = `You looted the weapons store and stole $${money}!`;

  } else if (operation === "Attack military barracks") {
    money = Math.floor(Math.random() * 131) + 50;
    rawDamage = Math.floor(Math.random() * 38) + 25;
    expGain = 35;
    message = `You attacked the military barracks and got $${money}!`;

  } else if (operation === "Storm a laboratory") {
    money = Math.floor(Math.random() * (160 - 60 + 1)) + 60;
    rawDamage = Math.floor(Math.random() * (52 - 20 + 1)) + 20;
    expGain = 27;
    message = `You stormed a laboratory and got $${money}!`;

  } else if (operation === "Strike an armory") {
    money = Math.floor(Math.random() * 301) + 350;
    rawDamage = Math.floor(Math.random() * 31) + 35;
    expGain = 45;
    message = `You struck an armory and got $${money}!`;

  } else if (operation === "Attack central issue facility") {
    money = Math.floor(Math.random() * 121) + 80;
    rawDamage = Math.floor(Math.random() * 41) + 25;
    expGain = 32;
    message = `You attacked the central issue facility and got $${money}!`;

  } else if (operation === "Raid a vehicle depot") {
    money = Math.floor(Math.random() * 351) + 500;
    rawDamage = Math.floor(Math.random() * 26) + 40;
    expGain = 52;
    message = `You raided a vehicle depot and got $${money}!`;

  } else if (operation === "Assault an aircraft hangar") {
    money = Math.floor(Math.random() * 401) + 700;
    rawDamage = Math.floor(Math.random() * 31) + 45;
    expGain = 58;
    message = `You assaulted an aircraft hangar and got $${money}!`;

  } else if (operation === "Invade country") {
    money = Math.floor(Math.random() * 501) + 900;
    rawDamage = Math.floor(Math.random() * 36) + 50;
    expGain = 65;
    message = `You invaded a country and escaped with $${money}!`;
  }

  // PRISON CHANCE =====================================================
  const prisonChance = getPrisonChance(level, exp);
  const isCaught = Math.random() < prisonChance;

  // Calculate defense and actual damage ONLY ONCE for the whole operation
  totalDefense =
    (p.headwear?.defense || 0) +
    (p.armor?.defense || 0) +
    (p.footwear?.defense || 0);

  if (isCaught) {
    actualDamage = rawDamage;
    message = `You were caught! You have been sent to prison for 60 seconds.`;
  } else {
    actualDamage = Math.max(0, rawDamage - totalDefense);

    // Weapons and epinephrine stealing
    const lootResult = applySuccessLoot(p, operation, exp, message);
    message = lootResult.message;
    stolenWeapon = lootResult.stolenWeapon;
    epinephrine = lootResult.epinephrine;

    // Bullet Stealing
    const bulletResult = calculateBulletSteal(level, message);
    message = bulletResult.message;
    bulletsStolen = bulletResult.bulletsStolen;

    // Broken Bone
    const boneResult = handleBrokenBone(p, level, message);
    message = boneResult.message;
    boneCooldownTime = boneResult.normalCooldownStartTime;

    // Death Check
    if (p.health - actualDamage <= 0) {
      shouldDie = true;
      oldDisplayName = p.displayName;
    }
  }

  return {
    money,
    rawDamage,
    expGain,
    message,
    isCaught,
    stolenWeapon,
    epinephrine,
    bulletsStolen,
    shouldDie,
    oldDisplayName,
    oldBalance,
    boneCooldownTime,
    actualDamage,
    totalDefense
  };
}

async function handleExecuteOperation(db, socket, data, deps) {
  const { 
    io, 
    imprisonedPlayers, 
    addExperienceAndGrantPoints, 
    removeFromOnlineList, 
    onlinePlayers, 
    onlineSockets, 
    crimeAlertCooldowns,
    crimeWitnessOpportunities
  } = deps;

  const email = socket.data.email;

  if (!crimeWitnessOpportunities) {
    console.warn('[OPERATIONS] WARNING: crimeWitnessOpportunities was not passed to handleExecuteOperation.');
    console.warn('[OPERATIONS] The Justice / Deliver Justice system will be DISABLED for this operation.');
  }

  if (!email || typeof data.operation !== 'string') {
    socket.emit('error', { message: 'Invalid request.' });
    return;
  }

  if (!validOperations.has(data.operation)) {
    console.warn(`[SERVER] Invalid operation attempted: ${data.operation} by ${email}`);
    socket.emit('error', { message: 'Invalid operation.' });
    return;
  }

  const docRef = db.collection('players').doc(email);

  try {
    // STEP A: Fast initial checks (outside transaction) ============================================
    const initialSnap = await docRef.get();
    if (!initialSnap.exists) {
      socket.emit('error', { message: 'Player not found' });
      return;
    }

    let initialP = initialSnap.data();
    const operation = data.operation;
    const displayName = initialP.displayName || socket.data.displayName;

    // === Prison Check (Fast Path) ===
    if (initialP.prisonEndTime && Date.now() < initialP.prisonEndTime) {
      socket.emit('operation-result', {
        operation,
        isCaught: true,
        message: "You are currently in prison and cannot perform operations.",
        prisonEndTime: initialP.prisonEndTime
      });
      return;
    }

    // Calculate level and cooldown
    const skill = initialP.skill || 0;
    let reductionMs = Math.floor(skill * 500);
    if (initialP.enhancedStaminaEndTime && Date.now() < initialP.enhancedStaminaEndTime) {
      reductionMs += 3000;
    }

    let cooldownTime = 60000 - reductionMs;
    let lastOpTime = initialP.lastLowLevelOp || 0;
    let level = "low";

    if (midLevelOps.includes(operation)) {
      cooldownTime = 72000 - reductionMs;
      lastOpTime = initialP.lastMidLevelOp || 0;
      level = "mid";
    } else if (highLevelOps.includes(operation)) {
      cooldownTime = 80000 - reductionMs;
      lastOpTime = initialP.lastHighLevelOp || 0;
      level = "high";
    }
    cooldownTime = Math.max(cooldownTime, 30000);

    if (Date.now() - lastOpTime < cooldownTime) {
      return; // Silent cooldown
    }

    // ==================== PRE-COMPUTE WITNESS / FREEZE DECISION (OUTSIDE TX - STABLE ACROSS RETRIES) ====================
    // We decide the target ONCE before entering the transaction.
    // This avoids:
    //   - Non-deterministic witness selection on Firestore retry
    //   - Side effects (cooldown deletion) inside retryable code
    //   - Closure variable leakage bugs
    // The actual freeze amount is still determined inside the tx (after resolveOperation knows the money).
    let freezeTargetName = null;
    let freezeTargetSocket = null;
    let crimeTextForAlert = "";

    const isLowLevelCrime = lowLevelOps.includes(operation) && 
                           (operation === "Mug a passerby" || operation === "Loot a grocery store");

    if (isLowLevelCrime && Math.random() < WITNESS_TRIGGER_PROB) {
      const nowPre = Date.now();
      const eligiblePlayers = [];

            for (const name of onlinePlayers || []) {
        if (name === displayName) continue;
        const cooldownEnd = crimeAlertCooldowns.get(name);

        if (!cooldownEnd || cooldownEnd <= nowPre) {
          // === CLEANUP: Remove expired cooldowns from memory ===
          if (cooldownEnd) {
            crimeAlertCooldowns.delete(name);
          }
          eligiblePlayers.push(name);
        }
      }

      if (eligiblePlayers.length > 0) {
        const randomIndex = Math.floor(Math.random() * eligiblePlayers.length);
        const chosenName = eligiblePlayers[randomIndex];
        const chosenSocket = onlineSockets.get(chosenName);

        if (chosenSocket) {
          freezeTargetName = chosenName;
          freezeTargetSocket = chosenSocket;
          crimeTextForAlert = operation === "Mug a passerby"
            ? `${displayName} mugged a passerby`
            : `${displayName} looted a grocery store`;
        }
      }
    }

    // STEP B: Run everything inside a single atomic transaction ============================================
    const txResult = await db.runTransaction(async (transaction) => {
      const freshSnap = await transaction.get(docRef);
      if (!freshSnap.exists) throw new Error('Player not found');

      let p = freshSnap.data();
      const exp = p.experience || 0;
      cleanupExpiredCrimeFreeze(p);

      // === Re-check prison inside transaction ===
      if (p.prisonEndTime && Date.now() < p.prisonEndTime) {
        throw new Error('In prison');
      }

      // Re-check cooldown inside transaction
      const freshLast = level === "low" ? (p.lastLowLevelOp || 0)
                       : level === "mid" ? (p.lastMidLevelOp || 0)
                       : (p.lastHighLevelOp || 0);

      if (Date.now() - freshLast < cooldownTime) {
        throw new Error('On cooldown');
      }

      // Call the extracted function (pure)
      const outcome = resolveOperation(p, operation, level, exp);

      // Apply the outcome inside the transaction
      if (outcome.isCaught) {
        p.prisonEndTime = Date.now() + 60000;
      } else {
        p.balance = (p.balance || 0) + outcome.money;
        p.health = Math.max(0, p.health - outcome.actualDamage);
        p.health = Math.min(p.health, p.maxHealth || 100);

        p = await addExperienceAndGrantPoints(docRef, p, outcome.expGain);

        if (outcome.stolenWeapon) {
          p.inventory.push(outcome.stolenWeapon);
        }
        if (outcome.epinephrine) {
          p.inventory.push(outcome.epinephrine);
        }
        if (outcome.bulletsStolen > 0) {
          p.bullets = (p.bullets || 0) + outcome.bulletsStolen;
        }

        const cooldownStartTime = outcome.boneCooldownTime || Date.now();
        if (level === "low") p.lastLowLevelOp = cooldownStartTime;
        else if (level === "mid") p.lastMidLevelOp = cooldownStartTime;
        else if (level === "high") p.lastHighLevelOp = cooldownStartTime;

        if (outcome.shouldDie) {
          p.dead = true;
          p.health = 0;
          p.displayName = null;
          p.displayNameLower = null;
        }

        // ==================== APPLY FREEZE INSIDE TX IF WE PRE-DECIDED (ATOMIC WITH LOOT) ====================
        // Uses the pre-chosen target (stable across retries). Amount is known now.
        if (freezeTargetName && !outcome.isCaught) {
          const nowTx = Date.now();
          const thisFreezeUntil = nowTx + CRIME_FREEZE_MS;

          if (!p.crimeFreezeUntil || p.crimeFreezeUntil < thisFreezeUntil) {
            p.crimeFreezeUntil = thisFreezeUntil;
          }
          p.frozenCrimeMoney = (p.frozenCrimeMoney || 0) + outcome.money;

          if (outcome.stolenWeapon) {
            outcome.stolenWeapon.frozenUntil = p.crimeFreezeUntil;
          }
          if (outcome.epinephrine) {
            outcome.epinephrine.frozenUntil = p.crimeFreezeUntil;
          }
        }
      }

      transaction.set(docRef, p);

      return {
        p,
        outcome,
        prisonEndTime: p.prisonEndTime || 0,
        diedThisOperation: outcome.shouldDie,
        oldDisplayName: outcome.oldDisplayName,
        oldBalance: outcome.oldBalance,
        // Freeze metadata for post-tx handling (only meaningful if freezeTargetName was set)
        freezeTargetName,
        actualFrozenAmount: (freezeTargetName && !outcome.isCaught) ? outcome.money : 0,
        crimeTextForAlert
      };
    });

    // STEP C: Things that happen AFTER successful transaction (only on commit) ============================================
    const { 
      p, outcome, prisonEndTime, diedThisOperation, oldDisplayName, oldBalance,
      freezeTargetName: txFreezeTarget, actualFrozenAmount, crimeTextForAlert: txCrimeText
    } = txResult;

    if (outcome.isCaught) {
      imprisonedPlayers.set(p.displayName, prisonEndTime);
    }

    // ==================== RECORD JUSTICE OPPORTUNITY + SEND ALERT (only after successful atomic commit) ====================
    if (txFreezeTarget && actualFrozenAmount > 0 && crimeWitnessOpportunities && freezeTargetSocket) {
      const now = Date.now();

      if (!crimeWitnessOpportunities.has(txFreezeTarget)) {
        crimeWitnessOpportunities.set(txFreezeTarget, new Map());
      }

      const opportunities = crimeWitnessOpportunities.get(txFreezeTarget);

      // Create the opportunity object
const opportunityObj = {
  expiry: now + JUSTICE_WINDOW_MS,
  frozenAmount: actualFrozenAmount
};

// === Start a precise 6-second timer ===
// If the witness does nothing, this timer will unfreeze the criminal's loot exactly on time.
const timeoutId = setTimeout(async () => {
  try {
    // Double-check: Does this opportunity still exist? (witness might have acted)
    const stillExists = crimeWitnessOpportunities.has(txFreezeTarget) &&
                        crimeWitnessOpportunities.get(txFreezeTarget).has(p.displayName);

    if (stillExists) {
      console.log(`[JUSTICE] 6s window expired with no action from ${txFreezeTarget} on ${p.displayName} → auto-unfreezing loot (ignored)`);
      
      // Unfreeze the criminal's money and items
      await clearCrimeFreezeForPlayer(db, p.displayName).catch(console.error);
      
      // Remove the opportunity from the map
      const opps = crimeWitnessOpportunities.get(txFreezeTarget);
      if (opps) {
        opps.delete(p.displayName);
        if (opps.size === 0) {
          crimeWitnessOpportunities.delete(txFreezeTarget);
        }
      }
    }
  } catch (err) {
    console.error('[JUSTICE] Error in 6s auto-unfreeze timeout:', err);
  }
}, JUSTICE_WINDOW_MS);   // This is 6000 milliseconds = 6 seconds

// Attach the timer ID to the opportunity so we can cancel it later if witness acts
opportunityObj.timeoutId = timeoutId;

// Save the opportunity
opportunities.set(p.displayName, opportunityObj);

      console.log(`[JUSTICE] Recorded opportunity for ${txFreezeTarget} to deliver justice on ${p.displayName} (amount: $${actualFrozenAmount})`);

      // Only alert if the target is still online right now
      if (onlineSockets.has(txFreezeTarget)) {
        freezeTargetSocket.emit('crime-alert', {
          message: txCrimeText,
          perpetrator: p.displayName
        });
      }

      // Set cooldown ONLY on successful processing
      crimeAlertCooldowns.set(txFreezeTarget, now + ALERT_COOLDOWN_MS);
    }

    // Broadcast prison list
    const prisonList = Array.from(imprisonedPlayers, ([displayName, prisonEndTime]) => ({
      displayName,
      prisonEndTime
    }));
    io.emit('prison-list-update', { list: prisonList, serverTime: Date.now() });

    if (!outcome.isCaught && outcome.money > 0) {
      const playerForLog = { balance: oldBalance };
      await logTransaction(socket, outcome.money, operation, playerForLog, docRef);
    }

    socket.emit('operation-result', {
      operation,
      money: outcome.money,
      rawDamage: outcome.rawDamage,
      actualDamage: outcome.actualDamage,
      totalDefense: outcome.isCaught ? 0 : outcome.totalDefense,
      message: outcome.message,
      isCaught: outcome.isCaught,
      prisonEndTime,
      stolenWeapon: outcome.stolenWeapon,
      epinephrine: outcome.epinephrine,
      bulletsStolen: outcome.bulletsStolen
    });

    socket.emit('update-stats', p);

    if (diedThisOperation && oldDisplayName) {
      removeFromOnlineList(oldDisplayName);
      await markPlayerAsDead(db, p, email, oldDisplayName, io);
      socket.emit('player-died');

      
      
      try {
        await clearCrimeFreezeForPlayer(db, email, true);
      } catch (e) {
        console.error('[LOOT] Failed to clear freeze on player death:', e);
      }
    }

  } catch (error) {
    if (error.message === 'On cooldown') return;
    if (error.message === 'In prison') return;

    console.error('[OPERATION ERROR]', error);
    socket.emit('error', { message: 'Operation failed. Please try again.' });
  }
}

module.exports = { handleExecuteOperation };
