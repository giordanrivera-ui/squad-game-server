const admin = require('firebase-admin');

// ==================== IMPROVED TRANSACTION LOGGER (same as every other file) ====================
async function logTransaction(socket, amount, description, playerData, docRef) {
  if (!socket || typeof amount !== 'number' || !playerData || !docRef) {
    console.warn('[TX] Invalid logTransaction call - missing params');
    return;
  }

  const newBalance = (playerData.balance || 0) + amount;
  
  const txData = {
    amount: amount,
    description: description,
    balanceAfter: Math.round(newBalance),
    timestamp: admin.firestore.FieldValue.serverTimestamp()
  };

  socket.emit('new-transaction', {
    amount: amount,
    description: description,
    balanceAfter: Math.round(newBalance)
  });

  try {
    await docRef.collection('transactions').add(txData);
    console.log(`[TX SAVED] ${description} | $${amount} → Balance: $${newBalance}`);
  } catch (err) {
    console.error('[TX ERROR] Failed to save transaction:', err);
  }
}

// ==================== CORPORATE BOND TEMPLATES (moved here) ====================
const corporateTemplates = [
  "Orange Inc. Y Corporate Bond",
  "Nanosoft Y Corporate Bond",
  "Amazin Y Corporate Bond",
  "Nikola Y Corporate Bond",
  "ByteSway Y Corporate Bond",
  "JPMarlow Y Corporate Bond",
  "Fjord Motors Y Corporate Bond",
  "MalMart Y Corporate Bond",
  "Beauchênel Y Corporate Bond",
  "Herizon Y Corporate Bond",
  "McDawsons Y Corporate Bond",
  "Webflicks Y Corporate Bond",
  "NestDepot Y Corporate Bond",
  "Mvidea Y Corporate Bond",
  "Starducks Coffee Y Corporate Bond"
];

// ==================== GENERATE RANDOM BOND MARKET (moved here) ====================
function generateRandomBondMarket(location) {
  const bonds = [];
  const random = Math.random;

  // First 3: Treasury Bonds
  for (let i = 1; i <= 3; i++) {
    const couponRate = (1.0 + Math.floor(random() * 10) * 0.1).toFixed(1);
    const title = `${location} ${couponRate}% Treasury Bond`;
    bonds.push({
      title: title,
      couponRate: parseFloat(couponRate),
      cost: 400 + Math.floor(random() * 4997) * 100
    });
  }

  // 12 corporate bonds
  const shuffledTemplates = [...corporateTemplates].sort(() => random() - 0.5);
  for (let i = 0; i < 12; i++) {
    const couponRate = (1.0 + Math.floor(random() * 10) * 0.1).toFixed(1);
    const template = shuffledTemplates[i];
    const title = template.replace("Y", couponRate);
    bonds.push({
      title: title,
      couponRate: parseFloat(couponRate),
      cost: 400 + Math.floor(random() * 4997) * 100
    });
  }
  
  bonds.sort((a, b) => a.cost - b.cost);
  return bonds;
}

// ==================== REQUEST BOND MARKET HANDLER ====================
async function handleRequestBondMarket(db, socket) {
  const email = socket.data.email;
  if (!email) return;
  const docRef = db.collection('players').doc(email);
  const doc = await docRef.get();
  let playerData = doc.data() || {};
  let bonds = playerData.bondMarket || [];
  const cooldownEnd = playerData.bondMarketCooldownEnd || 0;
  const location = playerData.location || "Unknown City";

  if (bonds.length === 0) {
    bonds = generateRandomBondMarket(location);
    await docRef.update({
      bondMarket: bonds,
      bondMarketCooldownEnd: Date.now() + 120000
    });
  }

  socket.emit('bond-market-update', {
    bonds,
    cooldownEndTime: cooldownEnd
  });
}

// ==================== REFRESH BOND MARKET HANDLER ====================
async function handleRefreshBondMarket(db, socket) {
  const email = socket.data.email;
  if (!email) return;
  const docRef = db.collection('players').doc(email);
  const doc = await docRef.get();
  let playerData = doc.data() || {};
  const now = Date.now();
  const cooldownEnd = playerData.bondMarketCooldownEnd || 0;
  const location = playerData.location || "Unknown City";

  if (now < cooldownEnd) {
    socket.emit('bond-market-update', {
      bonds: playerData.bondMarket || [],
      cooldownEndTime: cooldownEnd
    });
    return;
  }

  const newBonds = generateRandomBondMarket(location);
  const newCooldownEnd = now + 120000;
  await docRef.update({
    bondMarket: newBonds,
    bondMarketCooldownEnd: newCooldownEnd
  });
  socket.emit('bond-market-update', {
    bonds: newBonds,
    cooldownEndTime: newCooldownEnd
  });
  console.log(`[BONDS] ${email} refreshed market at ${location}`);
}

// ==================== BUY BOND HANDLER ====================
async function handleBuyBond(db, socket, bondData) {
  const email = socket.data.email;
  if (!email || !bondData?.title || typeof bondData.cost !== 'number') {
    socket.emit('bond-result', { success: false, message: 'Invalid bond data.' });
    return;
  }
  const docRef = db.collection('players').doc(email);
  const doc = await docRef.get();
  if (!doc.exists) return;
  let p = doc.data();
  const marketBonds = p.bondMarket || [];
  const matchingIndex = marketBonds.findIndex(b =>
    b.title === bondData.title && b.cost === bondData.cost
  );
  if (matchingIndex === -1) {
    socket.emit('bond-result', { success: false, message: 'This bond is no longer available.' });
    return;
  }
  if ((p.balance || 0) < bondData.cost) {
    socket.emit('bond-result', { success: false, message: 'Insufficient funds.' });
    return;
  }
  const maturityTime = Date.now() + 8 * 60 * 1000;
  await logTransaction(socket, -bondData.cost, `Bond Purchased: ${bondData.title}`, p, docRef);
  p.balance -= bondData.cost;
  if (!p.ownedBonds) p.ownedBonds = [];
  p.ownedBonds.push({
    ...marketBonds[matchingIndex],
    purchaseTime: Date.now(),
    maturityTime: maturityTime
  });
  p.bondMarket = marketBonds.filter((_, i) => i !== matchingIndex);
  await docRef.set(p);
  socket.emit('update-stats', p);
  socket.emit('bond-result', {
    success: true,
    message: `✅ Bought ${bondData.title}! Matures in exactly 8 minutes.`
  });
}

// ==================== AUTO BOND MATURITY (moved here) ====================
// This runs forever and refunds matured bonds for EVERY player
function startBondMaturityChecker(db) {
  setInterval(async () => {
    try {
      const now = Date.now();
      const snapshot = await db.collection('players').get();
      const batch = db.batch();
      for (const doc of snapshot.docs) {
        let p = doc.data();
        if (!p.ownedBonds || p.ownedBonds.length === 0) continue;
        let refundTotal = 0;
        const remainingBonds = [];
        for (const bond of p.ownedBonds) {
          if (bond.maturityTime && now >= bond.maturityTime) {
            refundTotal += bond.cost || 0;
          } else {
            remainingBonds.push(bond);
          }
        }
        if (refundTotal > 0) {
          batch.update(doc.ref, {
            balance: admin.firestore.FieldValue.increment(refundTotal),
            ownedBonds: remainingBonds
          });
          const txRef = doc.ref.collection('transactions').doc();
          batch.set(txRef, {
            amount: refundTotal,
            description: 'Bond Maturity',
            balanceAfter: (p.balance || 0) + refundTotal,
            timestamp: admin.firestore.FieldValue.serverTimestamp()
          });
          console.log(`[BOND MATURITY] ${p.displayName || doc.id} refunded $${refundTotal}`);
        }
      }
      await batch.commit();
    } catch (e) {
      console.error('Bond maturity error:', e);
    }
  }, 1000); // every second (same as before)
}

// Export everything so server.js can use it
module.exports = {
  handleRequestBondMarket,
  handleRefreshBondMarket,
  handleBuyBond,
  startBondMaturityChecker
};