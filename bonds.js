const admin = require('firebase-admin');

// ==================== IMPROVED TRANSACTION LOGGER ====================
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

// ==================== CORPORATE BOND TEMPLATES ====================
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

// ==================== GENERATE RANDOM BOND MARKET ====================
function generateRandomBondMarket(location) {
  const bonds = [];
  const random = Math.random;

  // First 3: Treasury Bonds
  for (let i = 1; i <= 3; i++) {
    const couponRate = (4.4 + Math.floor(random() * 33) * 0.1).toFixed(1);
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
    const couponRate = (4.4 + Math.floor(random() * 33) * 0.1).toFixed(1);
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

// ==================== REQUEST / REFRESH BOND MARKET (unchanged) ====================
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

// ==================== BUY BOND — NOW CALCULATES COUPON ====================
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
  // ====================== NEW COUPON CALCULATION ======================
  const couponRateDecimal = bondData.couponRate / 100;
  const totalCoupon = Math.round(couponRateDecimal * bondData.cost);   // e.g. 5% of $100,000 = $5,000

  await logTransaction(socket, -bondData.cost, `Bond Purchased: ${bondData.title}`, p, docRef);

  p.balance -= bondData.cost;

  if (!p.ownedBonds) p.ownedBonds = [];
  p.ownedBonds.push({
    ...marketBonds[matchingIndex],
    purchaseTime: Date.now(),
    totalCoupon: totalCoupon,      // NEW
    paymentsMade: 0                // NEW — tracks how many of the 4 coupon payments have been made
  });

  p.bondMarket = marketBonds.filter((_, i) => i !== matchingIndex);

  await docRef.set(p);
  socket.emit('update-stats', p);
  socket.emit('bond-result', {
    success: true,
    message: `✅ Bought ${bondData.title}! Coupon $${totalCoupon} will be paid in 4 installments (every 2 min). Final payment includes principal.`
  });
}

// ==================== NEW BOND PAYMENT CHECKER (4 installments every 2 min) ====================
function startBondMaturityChecker(db, { onlineSockets }) {
  setInterval(async () => {
    try {
      const now = Date.now();
      const snapshot = await db.collection('players').get();
      const batch = db.batch();
      const playersToNotify = [];

      for (const doc of snapshot.docs) {
        let p = doc.data();
        if (!p.ownedBonds || p.ownedBonds.length === 0) continue;

        let bondsToKeep = [];
        let totalPaidThisCycle = 0;

        for (const bond of p.ownedBonds) {
          const elapsedMs = now - bond.purchaseTime;
          const intervalMs = 2 * 60 * 1000; // 2 minutes
          const paymentsDue = Math.min(4, Math.floor(elapsedMs / intervalMs));

          const alreadyPaid = bond.paymentsMade || 0;

          if (paymentsDue > alreadyPaid) {
            const numToPayNow = paymentsDue - alreadyPaid;
            const couponPerPayment = Math.floor(bond.totalCoupon / 4);

            let amountNow = couponPerPayment * numToPayNow;

            const isFinalPayment = paymentsDue >= 4;
            if (isFinalPayment) {
              amountNow += bond.cost || 0;   // ← principal returned on the 4th payment
            }

            totalPaidThisCycle += amountNow;

            // Update the bond record
            bond.paymentsMade = paymentsDue;

            if (!isFinalPayment) {
              bondsToKeep.push(bond);
            }
            // else: bond is fully matured and removed
          } else {
            bondsToKeep.push(bond);
          }
        }

        if (totalPaidThisCycle > 0) {
          batch.update(doc.ref, {
            balance: admin.firestore.FieldValue.increment(totalPaidThisCycle),
            ownedBonds: bondsToKeep
          });

          const txRef = doc.ref.collection('transactions').doc();
          batch.set(txRef, {
            amount: totalPaidThisCycle,
            description: 'Bond Coupon + Maturity',
            balanceAfter: (p.balance || 0) + totalPaidThisCycle,
            timestamp: admin.firestore.FieldValue.serverTimestamp()
          });

          console.log(`[BOND PAYOUT] ${p.displayName || doc.id} received $${totalPaidThisCycle}`);

          if (p.displayName) {
            playersToNotify.push({
              displayName: p.displayName,
              email: doc.id,
              totalPaidThisCycle
            });
          }
        }
      }

      await batch.commit();

      // ==================== LIVE UI UPDATE ====================
      for (const player of playersToNotify) {
        const socket = onlineSockets.get(player.displayName);
        if (socket) {
          const freshDoc = await db.collection('players').doc(player.email).get();
          const freshData = freshDoc.data();
          socket.emit('update-stats', freshData);
          socket.emit('new-transaction', {
            amount: player.totalPaidThisCycle,
            description: 'Bond Coupon + Maturity',
            balanceAfter: (freshData.balance || 0)
          });
        }
      }
    } catch (e) {
      console.error('Bond payment error:', e);
    }
  }, 1000);
}

// Export everything
module.exports = {
  handleRequestBondMarket,
  handleRefreshBondMarket,
  handleBuyBond,
  startBondMaturityChecker
};