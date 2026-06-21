const admin = require('firebase-admin');
const { logTransaction, getRankTitle, addExperienceAndGrantPoints } = require('./utils');

// ==================== TEST HANDLERS ====================

async function handleAddTestExp(db, socket, amount) {
  const email = socket.data.email;
  if (!email || typeof amount !== 'number') return;

  const docRef = db.collection('players').doc(email);
  const doc = await docRef.get();
  if (!doc.exists) return;

  let p = doc.data();
  p = await addExperienceAndGrantPoints(docRef, p, amount);

  await docRef.set(p);
  socket.emit('update-stats', p);
}

async function handleAddTestMoney(db, socket, amount) {
  const email = socket.data.email;
  if (!email || typeof amount !== 'number') return;

  const docRef = db.collection('players').doc(email);
  const doc = await docRef.get();
  if (!doc.exists) return;

  let p = doc.data();

  await logTransaction(socket, amount, 'Test Money Added', p, docRef);

  p.balance = (p.balance || 0) + amount;

  await docRef.set(p);
  socket.emit('update-stats', p);
}

async function handleAddTestBullets(db, socket, amount) {
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
}

async function handleResetMartialArt(db, socket) {
  const email = socket.data.email;
  if (!email) return;

  const docRef = db.collection('players').doc(email);
  const doc = await docRef.get();
  if (!doc.exists) return;

  let p = doc.data();
  p.martialArt = null;           // Clear the martial art

  await docRef.set(p);
  socket.emit('update-stats', p);

  console.log(`[TEST] Martial art reset for ${email}`);
}

module.exports = {
  handleAddTestExp,
  handleAddTestMoney,
  handleAddTestBullets,
  handleResetMartialArt,
};