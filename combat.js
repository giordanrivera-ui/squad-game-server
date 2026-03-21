// Handles everything related to attempting to kill another player

const admin = require('firebase-admin');

// ==================== HELPER FUNCTIONS (pure math, no DB) ====================
function getUpperBound(exp) {
  if (exp <= 49) return 49;
  if (exp <= 514) return 514;
  if (exp <= 1264) return 1264;  
  if (exp <= 2314) return 2314;
  if (exp <= 3514) return 3514;
  if (exp <= 5014) return 5014;
  if (exp <= 6864) return 6864;
  if (exp <= 8864) return 8864;
  if (exp <= 10214) return 10214;
  if (exp <= 11464) return 11464;
  if (exp <= 14214) return 14214;
  if (exp <= 17414) return 17414;
  if (exp <= 21364) return 21364;
  if (exp <= 25864) return 25864;
  if (exp <= 31514) return 31514;
  if (exp <= 38214) return 38214;
  return 44000;  // Supreme Commander
}

function getRankTitle(exp) {
  if (exp <= 49) return 'Beggar';
  if (exp <= 514) return 'Thug';
  if (exp <= 1264) return 'Recruit';
  if (exp <= 2314) return 'Private';
  if (exp <= 3514) return 'Private First Class';
  if (exp <= 5014) return 'Corporal';
  if (exp <= 6864) return 'Sergeant';
  if (exp <= 8864) return 'Sergeant First Class';
  if (exp <= 10214) return 'Warrant Officer';
  if (exp <= 11464) return 'First Lieutenant';
  if (exp <= 14214) return 'Captain';
  if (exp <= 17414) return 'Major';
  if (exp <= 21364) return 'Lieutenant Colonel';
  if (exp <= 25864) return 'Colonel';
  if (exp <= 31514) return 'General';
  if (exp <= 38214) return 'General of the Army';
  return 'Supreme Commander';
}

function calculateBulletsNeeded(p, o, k) {
  if (o <= 0 || k <= 0 || p <= 0) return Infinity;
  const log10 = Math.log10;
  const inner = 10 * log10(k) - 3 * log10(o) - 2.5 * log10(p);
  const term = 1000 * inner;
  let b = 0.25 * term + term - 0.23 * p + 480;
  b = Math.max(b, 0);
  return Math.round(b);
}

// ==================== HELPER: Save dead profile & mark name used ====================
async function markPlayerAsDead(db, targetData, targetEmail, targetDisplayName) {
  if (!targetDisplayName) return;

  // Save snapshot for dead profile
  const deadProfile = {
    displayName: targetDisplayName,
    displayNameLower: targetDisplayName.toLowerCase(),
    experience: targetData.experience || 0,
    balance: targetData.balance || 0,
    headwear: targetData.headwear || null,
    armor: targetData.armor || null,
    footwear: targetData.footwear || null,
    weapon: targetData.weapon || null,
    overallPower: targetData.overallPower || 0,
    deathTime: admin.firestore.FieldValue.serverTimestamp(),
  };
  await db.collection('deadProfiles').doc(targetDisplayName.toLowerCase()).set(deadProfile);

  // Mark name as permanently used
  await db.collection('usedNames').doc(targetDisplayName.toLowerCase()).set({
    name: targetDisplayName,
    taken: true,
    takenAt: admin.firestore.FieldValue.serverTimestamp()
  });
}

// ==================== MAIN HANDLER ====================
async function handleKillAttempt(db, socket, data, deps) {
  const { onlineSockets, removeFromOnlineList } = deps;

  const attackerEmail = socket.data.email;
  if (!attackerEmail || typeof data.target !== 'string' || typeof data.bullets !== 'number' || data.bullets <= 0) {
    socket.emit('kill-result', { success: false, message: 'Invalid kill attempt.' });
    return;
  }

  // Get attacker
  const attackerDocRef = db.collection('players').doc(attackerEmail);
  const attackerDoc = await attackerDocRef.get();
  if (!attackerDoc.exists) {
    socket.emit('kill-result', { success: false, message: 'Attacker profile not found.' });
    return;
  }
  let attacker = attackerDoc.data();

  // Checks
  if (attacker.balance < 10000) {
    socket.emit('kill-result', { success: false, message: 'Not enough balance for mobilizing costs.' });
    return;
  }
  if (!attacker.weapon || attacker.overallPower <= 0) {
    socket.emit('kill-result', { success: false, message: 'You must equip a weapon.' });
    return;
  }

  // Find target
  const targetQuery = await db.collection('players').where('displayName', '==', data.target).limit(1).get();
  if (targetQuery.empty) {
    socket.emit('kill-result', { success: false, message: 'Target not found.' });
    return;
  }
  const targetDocRef = targetQuery.docs[0].ref;
  let target = targetQuery.docs[0].data();
  const targetEmail = targetQuery.docs[0].id;

  if (target.dead) {
    socket.emit('kill-result', { success: false, message: 'Target is already dead.' });
    return;
  }

  // Bullet calculation
  const p = getUpperBound(attacker.experience || 0);
  const o = attacker.overallPower || 0;
  const k = getUpperBound(target.experience || 0);
  let b = calculateBulletsNeeded(p, o, k);

  const targetRank = getRankTitle(target.experience || 0);
  if (targetRank === 'Beggar') {
    const attackerRank = getRankTitle(attacker.experience || 0);
    
    // Hard floor for Corporal and every rank above
    if (['Corporal', 'Sergeant', 'Sergeant First Class', 'Warrant Officer',
        'First Lieutenant', 'Captain', 'Major', 'Lieutenant Colonel',
        'Colonel', 'General', 'General of the Army', 'Supreme Commander']
        .includes(attackerRank)) {
      b = Math.max(b, 2000);
    } 
    // Soft floor for everyone below Corporal (if their gun makes it cheaper)
    else if (b < 2000) {
      b = 2000;
    }
  }

  // Special rule for high ranks vs Thug
  const attackerRank = getRankTitle(attacker.experience || 0);
  if (['General', 'General of the Army', 'Supreme Commander'].includes(attackerRank) 
      && targetRank === 'Thug') {
    b = Math.max(b, 3000);
  }

  // Pay mobilizing cost
  attacker.balance -= 10000;

  let success = false;
  let message = '';

  if (data.bullets >= b) {
    success = true;
    message = 'Kill successful! Target eliminated.';

    // === DEATH LOGIC ===
    await markPlayerAsDead(db, target, targetEmail, data.target);

    target.dead = true;
    target.health = 0;
    target.displayName = null;
    target.displayNameLower = null;

    removeFromOnlineList(data.target);

    await targetDocRef.update({ 
      dead: true, 
      health: 0,
      displayName: null,
      displayNameLower: null 
    });

    // Notify target if online
    const targetSocket = onlineSockets.get(data.target);
    if (targetSocket) {
      targetSocket.emit('player-died');
      targetSocket.emit('update-stats', target);
    }

    // === BOUNTY PAYOUT ===
    const hitQuery = await db.collection('hitlist')
      .where('target', '==', data.target)
      .where('active', '==', true)
      .limit(1)
      .get();

    if (!hitQuery.empty) {
      const hitDoc = hitQuery.docs[0];
      const hitData = hitDoc.data();
      attacker.balance += hitData.reward;
      await hitDoc.ref.update({ active: false });
      socket.emit('hit-claimed', { target: data.target, reward: hitData.reward });
    }

    // Deduct bullets
    attacker.bullets -= data.bullets;

  } else {
    success = false;
    message = 'Kill unsuccessful. Bullets deducted.';
    attacker.bullets -= data.bullets;
  }

  // Save attacker (bullets + kills)
  attacker.bullets = Math.max(0, attacker.bullets);
  await attackerDocRef.set(attacker);
  attacker.kills = (attacker.kills || 0) + 1;
  await attackerDocRef.set(attacker);

  // Send result
  socket.emit('kill-result', { success, message });
  socket.emit('update-stats', attacker);
}

module.exports = { 
  handleKillAttempt,
  markPlayerAsDead,
  getUpperBound,          // optional: export if you ever want to use them elsewhere
  getRankTitle,
  calculateBulletsNeeded 
};