const admin = require('firebase-admin');
const { logTransaction } = require('./utils');

// ==================== TIMED HEALING (START) ====================
async function handleStartHealing(db, socket) {
  const email = socket.data.email;
  if (!email) return;

  const docRef = db.collection('players').doc(email);
  const doc = await docRef.get();
  if (!doc.exists) return;

  let p = doc.data();

  if (p.dead === true || (p.health ?? 100) <= 0) {
    socket.emit('heal-result', { success: false, message: 'You are dead and cannot heal.' });
    return;
  }

  if (p.healingEndTime && p.healingEndTime > Date.now()) {
    socket.emit('heal-result', { success: false, message: 'You are already healing.' });
    return;
  }

  const cost = 50;
  if (p.balance < cost) {
    socket.emit('heal-result', { success: false, message: 'Not enough money.' });
    return;
  }

  await logTransaction(socket, -cost, 'Started Healing ($50)', p, docRef);

  p.balance -= cost;
  p.healingEndTime = Date.now() + 120000;   // exactly 2 minutes

  await docRef.set(p);
  socket.emit('update-stats', p);
  socket.emit('heal-result', { 
    success: true, 
    message: 'Healing started... (2 minutes remaining)' 
  });
}

// ==================== CLAIM HEALING (SECURE) ====================
async function handleClaimHealing(db, socket) {
  const email = socket.data.email;
  if (!email) return;

  const docRef = db.collection('players').doc(email);
  const doc = await docRef.get();
  if (!doc.exists) return;

  let p = doc.data();

  // CRITICAL SECURITY CHECK
  if (!p.healingEndTime || p.healingEndTime > Date.now()) {
    socket.emit('heal-result', { success: false, message: 'Healing is not finished yet.' });
    return;
  }

  // Healing time is up → apply full heal
  p.health = 100;
  p.healingEndTime = 0;

  await docRef.set(p);
  socket.emit('update-stats', p);
  socket.emit('heal-result', { 
    success: true, 
    message: '✅ You are now fully healed!' 
  });
}

// ==================== BROKEN BONE HEALING ====================
async function handleHealBrokenBone(db, socket) {
  const email = socket.data.email;
  if (!email) return;

  const docRef = db.collection('players').doc(email);
  const doc = await docRef.get();
  if (!doc.exists) return;

  let p = doc.data();

  if (p.dead === true || (p.health ?? 100) <= 0) {
    socket.emit('heal-broken-bone-result', { 
      success: false, 
      message: 'You are dead and cannot heal.' 
    });
    return;
  }

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

  await logTransaction(socket, -cost, 'Broken Bone Healing ($110)', p, docRef);
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
}

module.exports = {
  handleStartHealing,
  handleClaimHealing,
  handleHealBrokenBone
};