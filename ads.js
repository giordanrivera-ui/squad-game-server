// ==================== WATCH AD TO REDUCE HEALING TIME ====================
async function handleWatchAdForFasterHealing(db, socket) {
  const email = socket.data.email;
  if (!email) return;

  const docRef = db.collection('players').doc(email);
  const doc = await docRef.get();
  if (!doc.exists) return;

  let p = doc.data();

  if (!p.healingEndTime || p.healingEndTime <= Date.now()) {
    socket.emit('heal-result', { 
      success: false, 
      message: 'You are not currently healing.' 
    });
    return;
  }

  if (p.usedAdForHealing === true) {
    socket.emit('heal-result', { 
      success: false, 
      message: 'You already used an ad to speed up this healing.' 
    });
    return;
  }

  const threeMinutesInMs = 3 * 60 * 1000;
  const newHealingEndTime = Date.now() + threeMinutesInMs;

  if (newHealingEndTime < p.healingEndTime) {
    p.healingEndTime = newHealingEndTime;
  }

  p.usedAdForHealing = true;

  await docRef.set(p);

  socket.emit('update-stats', p);
  socket.emit('heal-result', { 
    success: true, 
    message: '✅ Ad watched! Healing time reduced to 3 minutes total.' 
  });

  console.log(`[HEALING] ${email} used ad to reduce healing time`);
}

module.exports = {
  handleWatchAdForFasterHealing
};