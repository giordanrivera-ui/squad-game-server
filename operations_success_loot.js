const { weaponTemplates } = require('./weapons.js');

// ==================== EPINEPHRINE QUALITY  ====================
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

// ==================== MAIN LOOT HANDLER ====================
function applySuccessLoot(p, operation, exp, currentMessage) {
    let message = currentMessage;
    let stolenWeapon = null;
    let epinephrine = null;

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
                // ==================== FIX: Add value for Net Worth calculation ====================
                stolenWeapon = {
                    ...stolenWeapon,
                    value: stolenWeapon.cost || 0
                };
                message += ` You also stole a ${stolenWeapon.name}!`;
            }
        }
    }

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
                // ==================== FIX: Add value for Net Worth calculation ====================
                stolenWeapon = {
                    ...stolenWeapon,
                    value: stolenWeapon.cost || 0
                };
                message += ` You also stole a ${stolenWeapon.name}!`;
            }
        }
    }

  if (operation === "Storm a laboratory") {
    if (Math.random() * 100 < 90) {
        const quality = getEpinephrineQuality(p.skill, p.intelligence || 0);
        const value = (quality >= 4) ? 30 : 20;

        epinephrine = {
          name: "Epinephrine solution",
          type: "consumable",
          quality,
          value
        };
      }
  }

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
          // ==================== FIX: Add value for Net Worth calculation ====================
          stolenWeapon = {
              ...stolenWeapon,
              value: stolenWeapon.cost || 0
          };
          message += ` You also stole a ${stolenWeapon.name}!`;
        }
      }
  }

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
          // ==================== FIX: Add value for Net Worth calculation ====================
          stolenWeapon = {
              ...stolenWeapon,
              value: stolenWeapon.cost || 0
          };
          message += ` You also stole a ${stolenWeapon.name}!`;
        }
      }
  }

  return {
    message,
    stolenWeapon,
    epinephrine
  };
}

module.exports = {
  applySuccessLoot,
  getEpinephrineQuality
};