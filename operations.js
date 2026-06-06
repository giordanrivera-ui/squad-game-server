const admin = require('firebase-admin');
const { logTransaction } = require('./utils');
const { markPlayerAsDead } = require('./combat.js');
const { weaponTemplates } = require('./weapons.js');

const lowLevelOps = ["Mug a passerby", "Loot a grocery store", "Rob a bank", "Loot weapons store"];
const midLevelOps = ["Attack military barracks", "Storm a laboratory", "Attack central issue facility"];
const highLevelOps = ["Strike an armory", "Raid a vehicle depot", "Assault an aircraft hangar", "Invade country"];

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

async function handleExecuteOperation(db, socket, data, deps) {
  const { io, imprisonedPlayers, addExperienceAndGrantPoints, removeFromOnlineList } = deps;

  const email = socket.data.email;
  if (!email || typeof data.operation !== 'string') return;

  const docRef = db.collection('players').doc(email);
  const doc = await docRef.get();
  if (!doc.exists) return;

  let p = doc.data();
  const operation = data.operation;

  // ==================== COOLDOWN LOGIC WITH SKILL REDUCTION ====================
  const skill = p.skill || 0;
  let reductionMs = Math.floor(skill * 500);

  if (p.enhancedStaminaEndTime && Date.now() < p.enhancedStaminaEndTime) {
    reductionMs += 3000;
  }

  let isHighLevel = false;
  let cooldownTime = 60000 - reductionMs;
  let lastOpTime = p.lastLowLevelOp || 0;

  if (midLevelOps.includes(operation)) {
    cooldownTime = 72000 - reductionMs;
    lastOpTime = p.lastMidLevelOp || 0;
  } else if (highLevelOps.includes(operation)) {
    cooldownTime = 80000 - reductionMs;
    lastOpTime = p.lastHighLevelOp || 0;
    isHighLevel = true;
  }

  cooldownTime = Math.max(cooldownTime, 30000);

  if (Date.now() - lastOpTime < cooldownTime) return;

  let money = 0;
  let rawDamage = 0;
  let expGain = 0;
  let message = "";
  let isCaught = false;

  const exp = p.experience || 0;

  if (operation === "Mug a passerby") {
    // ==================== STREET TACTICS COURSE BONUS (Basic + Advanced + Exceptional) ====================
    const now = Date.now();

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
      money = Math.floor(Math.random() * 101) + 36;   // $36 – $136
      expGain = 22;
    } else if (hasAdvanced) {
      money = Math.floor(Math.random() * 97) + 28;   // $28 – $124
      expGain = 18;
    } else if (hasBasic) {
      money = Math.floor(Math.random() * 93) + 20;   // $20 – $112
      expGain = 14;
    } else {
      money = Math.floor(Math.random() * 91) + 10;   // $10 – $100
      expGain = 10;
    }

    rawDamage = Math.floor(Math.random() * 26) + 5;
    message = `You mugged a passerby and got $${money}!`;
  }

  else if (operation === "Loot a grocery store") {
    // ==================== STREET TACTICS COURSE BONUS - Advanced + Exceptional ====================
    const now = Date.now();
    const hasAdvanced = (p.completedCourses || []).some(c =>
      c.id === "advanced-street-tactics" && (c.completionTime ?? 0) <= now
    );

    const hasExceptional = (p.completedCourses || []).some(c =>
      c.id === "exceptional-street-tactics" && (c.completionTime ?? 0) <= now
    );

    if (hasExceptional) {
      money = Math.floor(Math.random() * 73) + 48;   // $48 – $120
      expGain = 22;
    } else if (hasAdvanced) {
      money = Math.floor(Math.random() * 71) + 40;   // $40 – $110
      expGain = 19;
    } else {
      money = Math.floor(Math.random() * 71) + 30;   // $30 – $100
      expGain = 15;
    }

    rawDamage = Math.floor(Math.random() * 21) + 15;
    message = `You looted the grocery store and stole $${money}!`;

  } else if (operation === "Rob a bank") {
    rawDamage = Math.floor(Math.random() * 41) + 15;

    const now = Date.now();
    const hasExceptional = (p.completedCourses || []).some(c =>
      c.id === "exceptional-street-tactics" && (c.completionTime ?? 0) <= now
    );

    if (hasExceptional) {
      expGain = 29;
      // Original money roll, then add $8 bonus
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

      money += 8;   // Exceptional Street Tactics bonus
    } else {
      expGain = 25;
      // Original money calculation (unchanged)
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
    }

    message = `You robbed the bank and escaped with $${money}!`;
  } else if (operation === "Loot weapons store") {
    const now = Date.now();
    const hasExceptional = (p.completedCourses || []).some(c =>
      c.id === "exceptional-street-tactics" && (c.completionTime ?? 0) <= now
    );

    if (hasExceptional) {
      money = Math.floor(Math.random() * 41) + 15;   // original $10–$50 + $5 bonus
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

  // Prison chance (exact same scaling as original)
  let prisonChance;
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
  } else if (isHighLevel) {
    prisonChance = 0.54;
    if (exp > 49) prisonChance = 0.52;
    if (exp > 514) prisonChance = 0.50;
    if (exp > 1264) prisonChance = 0.45;
    if (exp > 2314) prisonChance = 0.42;
    if (exp > 3514) prisonChance = 0.38;
    if (exp > 5014) prisonChance = 0.33;
    if (exp > 6864) prisonChance = 0.30;
    if (exp > 8864) prisonChance = 0.28;
    if (exp > 10214) prisonChance = 0.25;
    if (exp > 11464) prisonChance = 0.23;
    if (exp > 14214) prisonChance = 0.21;
    if (exp > 17414) prisonChance = 0.20;
    if (exp > 21364) prisonChance = 0.18;
    if (exp > 25864) prisonChance = 0.17;
    if (exp > 31514) prisonChance = 0.16;
    if (exp > 38214) prisonChance = 0.15;
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

    await logTransaction(socket, money, `${operation}`, p, docRef);   // p = playerData, docRef = the Firestore reference

    p.balance += money;


    p.health = Math.max(0, p.health - actualDamage);

    p = await addExperienceAndGrantPoints(docRef, p, expGain);
    
    // ==================== EXISTING WEAPON STEALING (unchanged) ====================
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
        let knifeThreshold = 30; // (30%)
        let batThreshold = 55; // 30 + (25%)
        let macheteThreshold = 75; // 55 + (20%)
        let maulThreshold = 95; // 75 + (20%)
        if (exp > 3514) { 
          knifeThreshold = 20; 
          batThreshold = 45; 
          macheteThreshold = 70; 
          maulThreshold = 93; 
        }
        if (exp > 10214) { 
          knifeThreshold = 14; 
          batThreshold = 32; 
          macheteThreshold = 57; 
          maulThreshold = 84; 
        }
        if (exp > 21364) { 
          knifeThreshold = 8; // (8%)
          batThreshold = 26; // 8 + (18%)
          macheteThreshold = 50; // 26 + (24%) 
          maulThreshold = 78; // 50 + (28%)
        }

        const rand = Math.random() * 100;
        let weapon;
        if (rand < knifeThreshold) weapon = weaponTemplates.find(w => w.name === 'Small Knife');
        else if (rand < batThreshold) weapon = weaponTemplates.find(w => w.name === 'Baseball Bat');
        else if (rand < macheteThreshold) weapon = weaponTemplates.find(w => w.name === 'Machete');
        else if (rand < maulThreshold) weapon = weaponTemplates.find(w => w.name === 'Splitting Maul');
        else weapon = weaponTemplates.find(w => w.name === 'Ruger Mark IV');

        p.inventory.push(weapon);
        message += ` You also stole a ${weapon.name}!`;
      }
    }

    else if (operation === "Attack military barracks") {
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
          // NEW Eichenwald-specific drop table
          if (exp <= 3514) {
            glockThreshold = 38;
            remingtonThreshold = 60;   // 38 + (22%)
            waltherThreshold = 75;     // 64 + (15%)
            mossbergThreshold = 91;    // 75 + (16%)
            mp5Threshold = 97;         // 91 + (6%)
            ump5Threshold = 100;       // 97 + (3%)
          } else if (exp <= 10214) {
            glockThreshold = 25;
            remingtonThreshold = 47;   // 25 + (22%)
            waltherThreshold = 65;     // 47 + (18%)
            mossbergThreshold = 85;    // 65 + (20%)
            mp5Threshold = 95;         // 85 + (10%)
            ump5Threshold = 100;       // 95 + (5%)
          } else {
            glockThreshold = 16;
            remingtonThreshold = 28;   // 16 + 12
            waltherThreshold = 50;     // 28 + 22
            mossbergThreshold = 70;    // 50 + 20
            mp5Threshold = 88;         // 70 + 18
            ump5Threshold = 100;       // 88 + 12
          }
        } else {
          // Original non-Eichenwald drop table (unchanged)
          glockThreshold = 42;
          remingtonThreshold = 72;
          mossbergThreshold = 91;
          mp5Threshold = 97;
          if (exp > 3514) {
            glockThreshold = 33;
            remingtonThreshold = 63;
            mossbergThreshold = 85;
            mp5Threshold = 95; }
          if (exp > 10214) {
            glockThreshold = 24;
            remingtonThreshold = 48;
            mossbergThreshold = 70;
            mp5Threshold = 88; }
        }

        const rand = Math.random() * 100;

        let weapon;
        if (rand < glockThreshold) weapon = weaponTemplates.find(w => w.name === 'Glock 45 Gen 5');
        else if (rand < remingtonThreshold) weapon = weaponTemplates.find(w => w.name === 'Remington R1 Enhanced');
        else if (rand < waltherThreshold && isEichenwald) weapon = weaponTemplates.find(w => w.name === 'Walther PDP Pro');
        else if (rand < mossbergThreshold) weapon = weaponTemplates.find(w => w.name === 'Mossberg 590 Shotgun');
        else if (rand < mp5Threshold) weapon = weaponTemplates.find(w => w.name === 'MP5 SMG');
        else weapon = weaponTemplates.find(w => w.name === 'H&K UMP5');

        p.inventory.push(weapon);
        message += ` You also stole a ${weapon.name}!`;
      }
    }

    // ==================== EPINEPHRINE SOLUTION LOOT ====================
    if (operation === "Storm a laboratory") {

      const stealRoll = Math.random() * 100;

      if (stealRoll < 60) {   // 60% chance
        const quality = getEpinephrineQuality(p.skill, p.intelligence || 0);
        const value = (quality >= 4) ? 30 : 20;

        const epinephrine = {
          name: "Epinephrine solution",
          type: "consumable",
          quality: quality,
          value: value
        };

        if (!p.inventory) p.inventory = [];
        p.inventory.push(epinephrine);

        // Append to the existing message instead of emitting separately
        message += ` You also stole an Epinephrine solution (Quality ${quality})!`;
      }
    }
    
    if (operation === "Attack central issue facility") {
      let stealChance = 0.05; // Beggar
      if (exp > 49) stealChance = 0.08; // Thug
      if (exp > 514) stealChance = 0.11; // Recruit
      if (exp > 1264) stealChance = 0.15; // Private
      if (exp > 2314) stealChance = 0.18; // Private First Class
      if (exp > 3514) stealChance = 0.20; // Corporal
      if (exp > 5014) stealChance = 0.23; // Sergeant
      if (exp > 6864) stealChance = 0.26; // Sergeant First Class
      if (exp > 8864) stealChance = 0.30; // Warrant Officer
      if (exp > 10214) stealChance = 0.34; //
      if (exp > 11464) stealChance = 0.38; //
      if (exp > 14214) stealChance = 0.42; // Major
      if (exp > 17414) stealChance = 0.46; //
      if (exp > 21364) stealChance = 0.49; // Colonel
      if (exp > 25864) stealChance = 0.53; //
      if (exp > 31514) stealChance = 0.57; //
      if (exp > 38214) stealChance = 0.61; //

      if (Math.random() < stealChance) {
        const isVostokgrad = p.location === "Vostokgrad";

        let ump5Threshold, ak74Threshold, brenThreshold, carbineThreshold, scarThreshold, m16Threshold;

        if (isVostokgrad) {
          // ====================== VOSTOKGRAD SPECIAL DROP TABLE ======================
          if (exp <= 3514) {                    // Low EXP
            ump5Threshold = 42;
            ak74Threshold = 64;
            brenThreshold = 76;
            carbineThreshold = 92;
            scarThreshold = 98;
            m16Threshold = 100;
          } else if (exp <= 10214) {            // Mid EXP
            ump5Threshold = 32;
            ak74Threshold = 55;
            brenThreshold = 70;
            carbineThreshold = 88;
            scarThreshold = 96;
            m16Threshold = 100;
          } else {                              // High EXP
            ump5Threshold = 25;
            ak74Threshold = 45;
            brenThreshold = 63;
            carbineThreshold = 82;
            scarThreshold = 94;
            m16Threshold = 100;
          }
        } else {
          // Original non-Vostokgrad table (unchanged)
          ump5Threshold = 46;
          ak74Threshold = 75;
          carbineThreshold = 92;
          scarThreshold = 98;
          if (exp > 3514) {
            ump5Threshold = 38;
            ak74Threshold = 68;
            carbineThreshold = 88;
            scarThreshold = 96;
          }
          if (exp > 10214) {
            ump5Threshold = 31;
            ak74Threshold = 62;
            carbineThreshold = 82;
            scarThreshold = 94;
          }
        }

        const rand = Math.random() * 100;

        let weapon;
        if (rand < ump5Threshold) weapon = weaponTemplates.find(w => w.name === 'H&K UMP5');
        else if (rand < ak74Threshold) weapon = weaponTemplates.find(w => w.name === 'SLR104 AK-74');
        else if (rand < brenThreshold && isVostokgrad) weapon = weaponTemplates.find(w => w.name === 'CZ Bren 2');
        else if (rand < carbineThreshold) weapon = weaponTemplates.find(w => w.name === 'M4 Carbine');
        else if (rand < scarThreshold) weapon = weaponTemplates.find(w => w.name === 'SCAR-16 Mk II');
        else weapon = weaponTemplates.find(w => w.name === 'M16A4');

        p.inventory.push(weapon);
        message += ` You also stole a ${weapon.name}!`;
      }
    }

    if (operation === "Strike an armory") {
      let stealChance = 0.04; // Beggar
      if (exp > 49) stealChance = 0.06;     // Thug
      if (exp > 514) stealChance = 0.09;    // Recruit
      if (exp > 1264) stealChance = 0.12;   // Private
      if (exp > 2314) stealChance = 0.15;   // Private First Class
      if (exp > 3514) stealChance = 0.18;   // Corporal
      if (exp > 5014) stealChance = 0.21;   // Sergeant
      if (exp > 6864) stealChance = 0.23;   // Sergeant First Class
      if (exp > 8864) stealChance = 0.26;   // Warrant Officer
      if (exp > 10214) stealChance = 0.30;  // First Lieutenant
      if (exp > 11464) stealChance = 0.34;  // Captain
      if (exp > 14214) stealChance = 0.38;  // Major
      if (exp > 17414) stealChance = 0.42;  // Lieutenant Colonel
      if (exp > 21364) stealChance = 0.45;  // Colonel
      if (exp > 25864) stealChance = 0.48;  // General
      if (exp > 31514) stealChance = 0.52;  // General of the Army
      if (exp > 38214) stealChance = 0.56;  // Supreme Commander

      if (Math.random() < stealChance) {
        let m4Threshold, scarThreshold, m16Threshold, m24Threshold;

        if (exp <= 3514) {                    // Low EXP
          m4Threshold   = 45;
          scarThreshold = 75;   // 45 + 30%
          m16Threshold  = 91;   // 75 + 16%
          m24Threshold  = 100;  // 91 + 9%
        } else if (exp <= 10214) {            // Mid EXP
          m4Threshold   = 38;
          scarThreshold = 68;   // 38 + 30%
          m16Threshold  = 89;   // 68 + 21%
          m24Threshold  = 100;  // 89 + 11%
        } else {                              // High EXP
          m4Threshold   = 34;
          scarThreshold = 65;   // 34 + 31%
          m16Threshold  = 86;   // 65 + 21%
          m24Threshold  = 100;  // 86 + 14%
        }

        const rand = Math.random() * 100;

        let weapon;
        if (rand < m4Threshold) weapon = weaponTemplates.find(w => w.name === 'M4 Carbine');
        else if (rand < scarThreshold) weapon = weaponTemplates.find(w => w.name === 'SCAR-16 Mk II');
        else if (rand < m16Threshold) weapon = weaponTemplates.find(w => w.name === 'M16A4');
        else weapon = weaponTemplates.find(w => w.name === 'M24 Sniper');

        p.inventory.push(weapon);
        message += ` You also stole a ${weapon.name}!`;
      }
    }
    
    // ==================== NEW: BULLET STEALING LOGIC ====================
    let bulletStealChance = 0;
    if (midLevelOps.includes(operation)) {
      bulletStealChance = 0.35;
    } else if (isHighLevel) {
      bulletStealChance = 0.40;
    }

    if (bulletStealChance > 0 && Math.random() < bulletStealChance) {
      let bulletsStolen = 1;
      const rand = Math.random();

      if (midLevelOps.includes(operation)) {
        bulletsStolen = (rand < 0.65) ? 1 : 2;
      } else if (isHighLevel) {
        if (rand < 0.50) bulletsStolen = 1;
        else if (rand < 0.90) bulletsStolen = 2;
        else bulletsStolen = 3;
      }

      p.bullets = (p.bullets || 0) + bulletsStolen;
      message += ` You also stole ${bulletsStolen} bullet${bulletsStolen > 1 ? 's' : ''}!`;
    }

    // ==================== BROKEN BONE DEBUFF (unchanged) ====================
    let brokenBoneChance = 0;
    if (lowLevelOps.includes(operation)) {
      brokenBoneChance = 0.05;
    } else if (midLevelOps.includes(operation)) {
      brokenBoneChance = 0.09;
    } else if (isHighLevel) {
      brokenBoneChance = 0.14;
    }

    if (!p.hasBrokenBone && brokenBoneChance > 0 && Math.random() < brokenBoneChance) {
      p.hasBrokenBone = true;
      message += " 💥 You broke a bone during the operation!";
      console.log(`[SERVER] ${p.displayName} broke a bone during ${operation}`);
    }

    // ==================== PER-LEVEL BROKEN BONE PENALTY (exactly as requested) ====================
    const now = Date.now();

    // Normal cooldown for this level starts ONLY after its own bone penalty ends
    let normalCooldownStartTime = now;

    if (p.hasBrokenBone) {
      if (lowLevelOps.includes(operation)) {
        p.bonePenaltyEndTimeLow = now + 10000;
        normalCooldownStartTime = now + 10000;
        message += " ⏳ Low-level ops locked for 10s (bone recovery).";
      } else if (midLevelOps.includes(operation)) {
        p.bonePenaltyEndTimeMid = now + 10000;
        normalCooldownStartTime = now + 10000;
        message += " ⏳ Mid-level ops locked for 10s (bone recovery).";
      } else if (isHighLevel) {
        p.bonePenaltyEndTimeHigh = now + 10000;
        normalCooldownStartTime = now + 10000;
        message += " ⏳ High-level ops locked for 10s (bone recovery).";
      }
    }

    // Apply the (possibly delayed) normal cooldown start time
    if (lowLevelOps.includes(operation)) p.lastLowLevelOp = normalCooldownStartTime;
    else if (midLevelOps.includes(operation)) p.lastMidLevelOp = normalCooldownStartTime;
    else if (highLevelOps.includes(operation)) p.lastHighLevelOp = normalCooldownStartTime;
  }

  await docRef.set(p);

  // Broadcast prison list
  const prisonList = Array.from(imprisonedPlayers, ([displayName, prisonEndTime]) => ({ displayName, prisonEndTime }));
  io.emit('prison-list-update', { list: prisonList, serverTime: Date.now() });
  
  socket.emit('operation-result', {
    operation,
    money,
    rawDamage,
    actualDamage: isCaught ? rawDamage : Math.max(0, rawDamage - ((p.headwear?.defense || 0) + (p.armor?.defense || 0) + (p.footwear?.defense || 0))),
    totalDefense: isCaught ? 0 : ((p.headwear?.defense || 0) + (p.armor?.defense || 0) + (p.footwear?.defense || 0)),
    message,
    isCaught,
    prisonEndTime: p.prisonEndTime || 0
  });

  socket.emit('update-stats', p);

  if (p.health <= 0 && !isCaught) {
    const oldName = p.displayName;
    p.dead = true;
    p.health = 0;
    p.displayName = null;
    p.displayNameLower = null;

    if (oldName) {
        removeFromOnlineList(oldName);
    }

    if (oldName) {
      await markPlayerAsDead(db, p, email, oldName, io);
    }

    await docRef.set(p);
    socket.emit('player-died');
    console.log(`[SERVER] ${email} died from operation (old name: ${oldName || 'none'})`);
  }
}

module.exports = { handleExecuteOperation };