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

  // === NEW: Calculate Coupon and prepare 4 payments ===
  const couponAmount = (bondData.couponRate / 100)* bondData.cost;   // e.g. 0.05 * 100000 = 5000
  const now = Date.now();
  const maturityTime = now + 8 * 60 * 1000;                   // still 8 minutes total

  await logTransaction(socket, -bondData.cost, `Bond Purchased: ${bondData.title}`, p, docRef);

  p.balance -= bondData.cost;
  if (!p.ownedBonds) p.ownedBonds = [];

  p.ownedBonds.push({
    ...marketBonds[matchingIndex],
    purchaseTime: now,
    maturityTime: maturityTime,           // kept for progress bar
    couponAmount: couponAmount,           // NEW
    paymentsRemaining: 4,                 // NEW
    nextPaymentTime: now + 2 * 60 * 1000  // first coupon payment in exactly 2 minutes
  });
  p.bondMarket = marketBonds.filter((_, i) => i !== matchingIndex);
  await docRef.set(p);
  socket.emit('update-stats', p);
  socket.emit('bond-result', {
    success: true,
    message: `✅ Bought ${bondData.title}! Coupon $${couponAmount.toFixed(0)} will be paid in 4 installments every 2 minutes.`
  });
}

// ==================== AUTO BOND COUPON PAYMENTS (with special final description) ====================
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

        let updatedBonds = [];
        let refundTotalThisCycle = 0;
        let useMaturityDescription = false;   // ← NEW: flag for final payment

        for (const bond of p.ownedBonds) {
          if (!bond.nextPaymentTime || !bond.paymentsRemaining) {
            updatedBonds.push(bond);
            continue;
          }

          if (now >= bond.nextPaymentTime && bond.paymentsRemaining > 0) {
            let paymentAmount = bond.couponAmount / 4;

            // Last payment also returns the principal
            if (bond.paymentsRemaining === 1) {
              paymentAmount += bond.cost;
              useMaturityDescription = true;   // ← NEW: this is the final payment
            }

            refundTotalThisCycle += paymentAmount;

            // Update bond for next cycle
            bond.paymentsRemaining--;
            if (bond.paymentsRemaining > 0) {
              bond.nextPaymentTime += 2 * 60 * 1000;
              updatedBonds.push(bond);
            }
            // else: fully paid → do not push back (bond disappears)
          } else {
            updatedBonds.push(bond);
          }
        }

        if (refundTotalThisCycle > 0) {
          batch.update(doc.ref, {
            balance: admin.firestore.FieldValue.increment(refundTotalThisCycle),
            ownedBonds: updatedBonds
          });

          const txRef = doc.ref.collection('transactions').doc();
          const description = useMaturityDescription 
            ? 'Bond Coupon Payment & Maturity' 
            : 'Bond Coupon Payment';

          batch.set(txRef, {
            amount: refundTotalThisCycle,
            description: description,           // ← now uses the correct text
            balanceAfter: (p.balance || 0) + refundTotalThisCycle,
            timestamp: admin.firestore.FieldValue.serverTimestamp()
          });

          console.log(`[BOND COUPON] ${p.displayName || doc.id} received $${refundTotalThisCycle} (${description})`);

          if (p.displayName) {
            playersToNotify.push({
              displayName: p.displayName,
              email: doc.id,
              refundTotal: refundTotalThisCycle
            });
          }
        }
      }

      await batch.commit();

      // Live UI updates (unchanged)
      for (const player of playersToNotify) {
        const socket = onlineSockets.get(player.displayName);
        if (socket) {
          const freshDoc = await db.collection('players').doc(player.email).get();
          const freshData = freshDoc.data();
          socket.emit('update-stats', freshData);
          socket.emit('new-transaction', {
            amount: player.refundTotal,
            description: 'Bond Coupon Payment',   // live event still uses short name (you can change this too if you want)
            balanceAfter: (freshData.balance || 0)
          });
        }
      }
    } catch (e) {
      console.error('Bond coupon error:', e);
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