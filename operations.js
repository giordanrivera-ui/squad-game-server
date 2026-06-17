const admin = require('firebase-admin');
const { logTransaction } = require('./utils');
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

  // =====================================================
  // OPERATION REWARD CALCULATION
  // =====================================================

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
    actualDamage = rawDamage;   // For caught players we still report the raw damage to client
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

  // =====================================================
  // RETURN OUTCOME
  // =====================================================
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
  const { io, imprisonedPlayers, addExperienceAndGrantPoints, removeFromOnlineList, onlinePlayers, onlineSockets } = deps;
  const email = socket.data.email;

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
    // ============================================
    // STEP A: Fast initial checks (outside transaction)
    // ============================================
    const initialSnap = await docRef.get();
    if (!initialSnap.exists) {
      socket.emit('error', { message: 'Player not found' });
      return;
    }

    let initialP = initialSnap.data();
    const operation = data.operation;

    // === NEW: Prison Check (Fast Path) ===
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

    // ============================================
    // STEP B: Run everything inside a transaction
    // ============================================
    const txResult = await db.runTransaction(async (transaction) => {
      const freshSnap = await transaction.get(docRef);
      if (!freshSnap.exists) throw new Error('Player not found');

      let p = freshSnap.data();
      const exp = p.experience || 0;

      // === NEW: Re-check prison inside transaction ===
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

      // Call the extracted function
      const outcome = resolveOperation(p, operation, level, exp);

      // Apply the outcome inside the transaction
      if (outcome.isCaught) {
        p.prisonEndTime = Date.now() + 60000;
      } else {
        p.balance = (p.balance || 0) + outcome.money;
        p.health = Math.max(0, p.health - outcome.actualDamage);

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
      }

      transaction.set(docRef, p);

      return {
        p,
        outcome,
        prisonEndTime: p.prisonEndTime || 0,
        diedThisOperation: outcome.shouldDie,
        oldDisplayName: outcome.oldDisplayName,
        oldBalance: outcome.oldBalance
      };
    });

    // ============================================
    // STEP C: Things that happen AFTER successful transaction
    // ============================================
    const { p, outcome, prisonEndTime, diedThisOperation, oldDisplayName, oldBalance } = txResult;

    if (outcome.isCaught) {
      imprisonedPlayers.set(p.displayName, prisonEndTime);
    }

    // ==================== NEW: Crime Alert with 10s Cooldown (Lazy Cleanup) ====================
if (!outcome.isCaught) {
  const lowLevelCrimes = ["Mug a passerby", "Loot a grocery store"];
  
  if (lowLevelCrimes.includes(operation) && Math.random() < 0.95) {
    const now = Date.now();

    // Build list of eligible players + clean expired cooldowns on the fly
    const eligiblePlayers = [];

    for (const name of onlinePlayers || []) {
      if (name === p.displayName) continue; // Don't alert the perpetrator

      const cooldownEnd = crimeAlertCooldowns.get(name);

      if (!cooldownEnd || cooldownEnd <= now) {
        // Player is eligible (and clean up expired entry if it exists)
        if (cooldownEnd) {
          crimeAlertCooldowns.delete(name); // Lazy cleanup
        }
        eligiblePlayers.push(name);
      }
    }

    if (eligiblePlayers.length > 0) {
      // Pick a random eligible player
      const randomIndex = Math.floor(Math.random() * eligiblePlayers.length);
      const targetName = eligiblePlayers[randomIndex];
      const targetSocket = onlineSockets.get(targetName);

      if (targetSocket) {
        const crimeText = operation === "Mug a passerby" 
          ? `${p.displayName} mugged a passerby` 
          : `${p.displayName} looted a grocery store`;

        targetSocket.emit('crime-alert', {
          message: crimeText,
          perpetrator: p.displayName
        });

        // Apply 10-second cooldown
        crimeAlertCooldowns.set(targetName, now + 10000);
      }
    }
  }
}
// ==================== END NEW FEATURE ====================

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
    }

  } catch (error) {
    if (error.message === 'On cooldown') return;
    if (error.message === 'In prison') return; // Silent or you can emit a message here

    console.error('[OPERATION ERROR]', error);
    socket.emit('error', { message: 'Operation failed. Please try again.' });
  }
}

module.exports = { handleExecuteOperation };