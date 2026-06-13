const admin = require('firebase-admin');
const { logTransaction } = require('./utils');
const { markPlayerAsDead } = require('./combat.js');
const { weaponTemplates } = require('./weapons.js');
const { getPrisonChance } = require('./operations_prison_chance');
const { calculateBulletSteal } = require('./operations_bullets');
const { handleBrokenBone } = require('./operations_broken_bones');

const lowLevelOps = ["Mug a passerby", "Loot a grocery store", "Rob a bank", "Loot weapons store"];
const midLevelOps = ["Attack military barracks", "Storm a laboratory", "Attack central issue facility"];
const highLevelOps = ["Strike an armory", "Raid a vehicle depot", "Assault an aircraft hangar", "Invade country"];

const validOperations = new Set([
  ...lowLevelOps,
  ...midLevelOps,
  ...highLevelOps
]);

function getEpinephrineQuality(skill, intelligence) {
  const s = skill || 0;
  const i = intelligence || 0;

  let chances;

  if (s >= 9 && i >= 9) {
    chances = [0, 8, 21, 38, 33];        // Quality 1 to 5
  } else if (s >= 6 && i >= 6) {
    chances = [6, 14, 25, 30, 25];
  } else if (s >= 3 && i >= 3) {
    chances = [10, 19, 28, 25, 18];
  } else {
    chances = [16, 24, 26, 22, 12];      // Default
  }

  // Convert percentages to cumulative weights
  const cumulative = [];
  let sum = 0;
  for (let c of chances) {
    sum += c;
    cumulative.push(sum);
  }

  const roll = Math.random() * 100;

  if (roll < cumulative[0]) return 1;
  if (roll < cumulative[1]) return 2;
  if (roll < cumulative[2]) return 3;
  if (roll < cumulative[3]) return 4;
  return 5;
}

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

  // =====================================================
  // PRISON CHANCE
  // =====================================================
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

    // Loot Weapons Store
    if (operation === "Loot weapons store") {
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
      if (exp > 21364) stealChance = 0.72;
      if (exp > 25864) stealChance = 0.78;
      if (exp > 31514) stealChance = 0.82;
      if (exp > 38214) stealChance = 0.89;

      if (Math.random() < stealChance) {
        let knifeThreshold = 30, batThreshold = 55, macheteThreshold = 75, maulThreshold = 95;

        if (exp > 3514) { knifeThreshold = 20; batThreshold = 45; macheteThreshold = 70; maulThreshold = 93; }
        if (exp > 10214) { knifeThreshold = 14; batThreshold = 32; macheteThreshold = 57; maulThreshold = 84; }
        if (exp > 21364) { knifeThreshold = 8; batThreshold = 26; macheteThreshold = 50; maulThreshold = 78; }

        const rand = Math.random() * 100;
        if (rand < knifeThreshold) stolenWeapon = weaponTemplates.find(w => w.name === 'Small Knife');
        else if (rand < batThreshold) stolenWeapon = weaponTemplates.find(w => w.name === 'Baseball Bat');
        else if (rand < macheteThreshold) stolenWeapon = weaponTemplates.find(w => w.name === 'Machete');
        else if (rand < maulThreshold) stolenWeapon = weaponTemplates.find(w => w.name === 'Splitting Maul');
        else stolenWeapon = weaponTemplates.find(w => w.name === 'Ruger Mark IV');

        if (stolenWeapon) {
          message += ` You also stole a ${stolenWeapon.name}!`;
        }
      }
    }

    // Attack Military Barracks
    if (operation === "Attack military barracks") {
      let stealChance = 0.12;
      if (exp > 49) stealChance = 0.15;
      if (exp > 514) stealChance = 0.21;
      if (exp > 1264) stealChance = 0.26;
      if (exp > 2314) stealChance = 0.32;
      if (exp > 3514) stealChance = 0.36;
      if (exp > 5014) stealChance = 0.42;
      if (exp > 6864) stealChance = 0.46;
      if (exp > 8864) stealChance = 0.55;
      if (exp > 10214) stealChance = 0.60;
      if (exp > 11464) stealChance = 0.62;
      if (exp > 14214) stealChance = 0.65;
      if (exp > 17414) stealChance = 0.68;
      if (exp > 21364) stealChance = 0.74;
      if (exp > 25864) stealChance = 0.78;
      if (exp > 31514) stealChance = 0.82;
      if (exp > 38214) stealChance = 0.86;

      if (Math.random() < stealChance) {
        const isEichenwald = p.location === "Eichenwald";
        let glockThreshold, remingtonThreshold, waltherThreshold, mossbergThreshold, mp5Threshold, ump5Threshold;

        if (isEichenwald) {
          if (exp <= 3514) { glockThreshold = 38; remingtonThreshold = 60; waltherThreshold = 75; mossbergThreshold = 91; mp5Threshold = 97; ump5Threshold = 100; }
          else if (exp <= 10214) { glockThreshold = 25; remingtonThreshold = 47; waltherThreshold = 65; mossbergThreshold = 85; mp5Threshold = 95; ump5Threshold = 100; }
          else { glockThreshold = 16; remingtonThreshold = 28; waltherThreshold = 50; mossbergThreshold = 70; mp5Threshold = 88; ump5Threshold = 100; }
        } else {
          glockThreshold = 42; remingtonThreshold = 72; mossbergThreshold = 91; mp5Threshold = 97;
          if (exp > 3514) { glockThreshold = 33; remingtonThreshold = 63; mossbergThreshold = 85; mp5Threshold = 95; }
          if (exp > 10214) { glockThreshold = 24; remingtonThreshold = 48; mossbergThreshold = 70; mp5Threshold = 88; }
        }

        const rand = Math.random() * 100;
        if (rand < glockThreshold) stolenWeapon = weaponTemplates.find(w => w.name === 'Glock 45 Gen 5');
        else if (rand < remingtonThreshold) stolenWeapon = weaponTemplates.find(w => w.name === 'Remington R1 Enhanced');
        else if (rand < waltherThreshold && isEichenwald) stolenWeapon = weaponTemplates.find(w => w.name === 'Walther PDP Pro');
        else if (rand < mossbergThreshold) stolenWeapon = weaponTemplates.find(w => w.name === 'Mossberg 590 Shotgun');
        else if (rand < mp5Threshold) stolenWeapon = weaponTemplates.find(w => w.name === 'MP5 SMG');
        else stolenWeapon = weaponTemplates.find(w => w.name === 'H&K UMP5');

        if (stolenWeapon) {
          message += ` You also stole a ${stolenWeapon.name}!`;
        }
      }
    }

    // Storm a Laboratory - Epinephrine
    if (operation === "Storm a laboratory") {
      if (Math.random() * 100 < 60) {
        const quality = getEpinephrineQuality(p.skill, p.intelligence || 0);
        const value = (quality >= 4) ? 30 : 20;

        epinephrine = {
          name: "Epinephrine solution",
          type: "consumable",
          quality,
          value
        };
        message += ` You also stole an Epinephrine solution (Quality ${quality})!`;
      }
    }

    // Attack Central Issue Facility
    if (operation === "Attack central issue facility") {
      let stealChance = 0.05;
      if (exp > 49) stealChance = 0.08;
      if (exp > 514) stealChance = 0.11;
      if (exp > 1264) stealChance = 0.15;
      if (exp > 2314) stealChance = 0.18;
      if (exp > 3514) stealChance = 0.20;
      if (exp > 5014) stealChance = 0.23;
      if (exp > 6864) stealChance = 0.26;
      if (exp > 8864) stealChance = 0.30;
      if (exp > 10214) stealChance = 0.34;
      if (exp > 11464) stealChance = 0.38;
      if (exp > 14214) stealChance = 0.42;
      if (exp > 17414) stealChance = 0.46;
      if (exp > 21364) stealChance = 0.49;
      if (exp > 25864) stealChance = 0.53;
      if (exp > 31514) stealChance = 0.57;
      if (exp > 38214) stealChance = 0.61;

      if (Math.random() < stealChance) {
        const isVostokgrad = p.location === "Vostokgrad";
        let ump5Threshold, ak74Threshold, brenThreshold, carbineThreshold, scarThreshold, m16Threshold;

        if (isVostokgrad) {
          if (exp <= 3514) { ump5Threshold = 42; ak74Threshold = 64; brenThreshold = 76; carbineThreshold = 92; scarThreshold = 98; m16Threshold = 100; }
          else if (exp <= 10214) { ump5Threshold = 32; ak74Threshold = 55; brenThreshold = 70; carbineThreshold = 88; scarThreshold = 96; m16Threshold = 100; }
          else { ump5Threshold = 25; ak74Threshold = 45; brenThreshold = 63; carbineThreshold = 82; scarThreshold = 94; m16Threshold = 100; }
        } else {
          ump5Threshold = 46; ak74Threshold = 75; carbineThreshold = 92; scarThreshold = 98;
          if (exp > 3514) { ump5Threshold = 38; ak74Threshold = 68; carbineThreshold = 88; scarThreshold = 96; }
          if (exp > 10214) { ump5Threshold = 31; ak74Threshold = 62; carbineThreshold = 82; scarThreshold = 94; }
        }

        const rand = Math.random() * 100;
        if (rand < ump5Threshold) stolenWeapon = weaponTemplates.find(w => w.name === 'H&K UMP5');
        else if (rand < ak74Threshold) stolenWeapon = weaponTemplates.find(w => w.name === 'SLR104 AK-74');
        else if (rand < brenThreshold && isVostokgrad) stolenWeapon = weaponTemplates.find(w => w.name === 'CZ Bren 2');
        else if (rand < carbineThreshold) stolenWeapon = weaponTemplates.find(w => w.name === 'M4 Carbine');
        else if (rand < scarThreshold) stolenWeapon = weaponTemplates.find(w => w.name === 'SCAR-16 Mk II');
        else stolenWeapon = weaponTemplates.find(w => w.name === 'M16A4');

        if (stolenWeapon) {
          message += ` You also stole a ${stolenWeapon.name}!`;
        }
      }
    }

    // Strike an Armory
    if (operation === "Strike an armory") {
      let stealChance = 0.04;
      if (exp > 49) stealChance = 0.06;
      if (exp > 514) stealChance = 0.09;
      if (exp > 1264) stealChance = 0.12;
      if (exp > 2314) stealChance = 0.15;
      if (exp > 3514) stealChance = 0.18;
      if (exp > 5014) stealChance = 0.21;
      if (exp > 6864) stealChance = 0.23;
      if (exp > 8864) stealChance = 0.26;
      if (exp > 10214) stealChance = 0.30;
      if (exp > 11464) stealChance = 0.34;
      if (exp > 14214) stealChance = 0.38;
      if (exp > 17414) stealChance = 0.42;
      if (exp > 21364) stealChance = 0.45;
      if (exp > 25864) stealChance = 0.48;
      if (exp > 31514) stealChance = 0.52;
      if (exp > 38214) stealChance = 0.56;

      if (Math.random() < stealChance) {
        let m4Threshold, scarThreshold, m16Threshold, m24Threshold;
        if (exp <= 3514) { m4Threshold = 45; scarThreshold = 75; m16Threshold = 91; m24Threshold = 100; }
        else if (exp <= 10214) { m4Threshold = 38; scarThreshold = 68; m16Threshold = 89; m24Threshold = 100; }
        else { m4Threshold = 34; scarThreshold = 65; m16Threshold = 86; m24Threshold = 100; }

        const rand = Math.random() * 100;
        if (rand < m4Threshold) stolenWeapon = weaponTemplates.find(w => w.name === 'M4 Carbine');
        else if (rand < scarThreshold) stolenWeapon = weaponTemplates.find(w => w.name === 'SCAR-16 Mk II');
        else if (rand < m16Threshold) stolenWeapon = weaponTemplates.find(w => w.name === 'M16A4');
        else stolenWeapon = weaponTemplates.find(w => w.name === 'M24 Sniper');

        if (stolenWeapon) {
          message += ` You also stole a ${stolenWeapon.name}!`;
        }
      }
    }

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
  const { io, imprisonedPlayers, addExperienceAndGrantPoints, removeFromOnlineList } = deps;
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
    // STEP A: Fast initial cooldown check (outside transaction)
    // ============================================
    const initialSnap = await docRef.get();
    if (!initialSnap.exists) {
      socket.emit('error', { message: 'Player not found' });
      return;
    }

    let initialP = initialSnap.data();
    const operation = data.operation;

    // Calculate level and cooldown (same as before)
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

      // Re-check cooldown inside transaction (critical for safety)
      const freshLast = level === "low" ? (p.lastLowLevelOp || 0)
                       : level === "mid" ? (p.lastMidLevelOp || 0)
                       : (p.lastHighLevelOp || 0);

      if (Date.now() - freshLast < cooldownTime) {
        throw new Error('On cooldown');
      }

      // ============================================
      // CALL THE EXTRACTED FUNCTION (This is the key improvement)
      // ============================================
      const outcome = resolveOperation(p, operation, level, exp);

      // Apply the outcome inside the transaction
      if (outcome.isCaught) {
        p.prisonEndTime = Date.now() + 60000;
      } else {
        p.balance = (p.balance || 0) + outcome.money;
        p.health = Math.max(0, p.health - outcome.actualDamage);

        // Add experience
        p = await addExperienceAndGrantPoints(docRef, p, outcome.expGain);

        // Apply loot
        if (outcome.stolenWeapon) {
          p.inventory.push(outcome.stolenWeapon);
        }
        if (outcome.epinephrine) {
          p.inventory.push(outcome.epinephrine);
        }
        if (outcome.bulletsStolen > 0) {
          p.bullets = (p.bullets || 0) + outcome.bulletsStolen;
        }

        // Set cooldown timers (using the time returned from resolveOperation)
        const cooldownStartTime = outcome.boneCooldownTime || Date.now();
        if (level === "low") p.lastLowLevelOp = cooldownStartTime;
        else if (level === "mid") p.lastMidLevelOp = cooldownStartTime;
        else if (level === "high") p.lastHighLevelOp = cooldownStartTime;

        // Handle death
        if (outcome.shouldDie) {
          p.dead = true;
          p.health = 0;
          p.displayName = null;
          p.displayNameLower = null;
        }
      }

      // Write the final state
      transaction.set(docRef, p);

      // Return everything needed outside the transaction
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

    // Broadcast prison list
    const prisonList = Array.from(imprisonedPlayers, ([displayName, prisonEndTime]) => ({
      displayName,
      prisonEndTime
    }));
    io.emit('prison-list-update', { list: prisonList, serverTime: Date.now() });

    // Log transaction only on successful money gain
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
      stolenWeapon: outcome.stolenWeapon
    });

    socket.emit('update-stats', p);

    // Handle death side effects
    if (diedThisOperation && oldDisplayName) {
      removeFromOnlineList(oldDisplayName);
      await markPlayerAsDead(db, p, email, oldDisplayName, io);
      socket.emit('player-died');
    }

  } catch (error) {
    if (error.message === 'On cooldown') return;
    console.error('[OPERATION ERROR]', error);
    socket.emit('error', { message: 'Operation failed. Please try again.' });
  }
}

module.exports = { handleExecuteOperation };