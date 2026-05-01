const admin = require('firebase-admin');
const { logTransaction } = require('./utils');

// ==================== HEAL HANDLER ====================
async function handleHeal(db, socket) {
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
}

// ==================== HEAL BROKEN BONE HANDLER ====================
async function handleHealBrokenBone(db, socket) {
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
  handleHeal,
  handleHealBrokenBone
};