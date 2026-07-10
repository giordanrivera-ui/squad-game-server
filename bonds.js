const admin = require('firebase-admin');
const { logTransaction, getAvailableBalance, cleanupExpiredCrimeFreeze } = require('./utils');

// ==================== BOND CONFIGURATION ====================
const BOND_MATURITY_MS = 8 * 60 * 1000;
const BOND_PAYMENT_INTERVAL_MS = 2 * 60 * 1000;
const BOND_NUM_PAYMENTS = 4;
const BOND_MARKET_COOLDOWN_MS = 2 * 60 * 1000;
const BOND_CHECKER_INTERVAL_MS = 10000; // 10 seconds

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

// ==================== HELPER ====================
function getEarliestNextPaymentTime(bonds) {
  if (!bonds || bonds.length === 0) return null;

  const validTimes = bonds
    .map(b => b.nextPaymentTime)
    .filter(t => typeof t === 'number' && t > 0);

  return validTimes.length > 0 ? Math.min(...validTimes) : null;
}

// ==================== GENERATE RANDOM BOND MARKET ====================
function generateRandomBondMarket(location) {
  const bonds = [];
  const random = Math.random;

  // 3 Treasury Bonds
  for (let i = 1; i <= 3; i++) {
    const couponRate = (4.4 + Math.floor(random() * 33) * 0.1).toFixed(1);
    bonds.push({
      title: `${location} ${couponRate}% Treasury Bond`,
      couponRate: parseFloat(couponRate),
      cost: 400 + Math.floor(random() * 4997) * 100
    });
  }

  // 12 Corporate Bonds
  const shuffled = [...corporateTemplates].sort(() => random() - 0.5);
  for (let i = 0; i < 12; i++) {
    const couponRate = (4.4 + Math.floor(random() * 33) * 0.1).toFixed(1);
    const title = shuffled[i].replace("Y", couponRate);
    bonds.push({
      title,
      couponRate: parseFloat(couponRate),
      cost: 400 + Math.floor(random() * 4997) * 100
    });
  }

  bonds.sort((a, b) => a.cost - b.cost);
  return bonds;
}

// ==================== REQUEST / REFRESH BOND MARKET ====================
async function handleRequestBondMarket(db, socket) {
  const email = socket.data.email;
  if (!email) return;

  const docRef = db.collection('players').doc(email);
  const doc = await docRef.get();
  let playerData = doc.data() || {};
  let bonds = playerData.bondMarket || [];
  let cooldownEnd = playerData.bondMarketCooldownEnd || 0;
  const location = playerData.location || "Unknown City";

  if (bonds.length === 0) {
    bonds = generateRandomBondMarket(location);
    await docRef.update({
      bondMarket: bonds,
      bondMarketCooldownEnd: Date.now() + BOND_MARKET_COOLDOWN_MS
    });
    cooldownEnd = Date.now() + BOND_MARKET_COOLDOWN_MS;
  }

  socket.emit('bond-market-update', { bonds, cooldownEndTime: cooldownEnd });
}

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
  const newCooldownEnd = now + BOND_MARKET_COOLDOWN_MS;

  await docRef.update({
    bondMarket: newBonds,
    bondMarketCooldownEnd: newCooldownEnd
  });

  socket.emit('bond-market-update', {
    bonds: newBonds,
    cooldownEndTime: newCooldownEnd
  });
}

// ==================== BUY BOND ====================
async function handleBuyBond(db, socket, bondData) {
  const email = socket.data.email;
  if (!email || !bondData?.title || typeof bondData.cost !== 'number') {
    socket.emit('bond-result', { success: false, message: 'Invalid bond data.' });
    return;
  }

  const docRef = db.collection('players').doc(email);
  const now = Date.now();

  try {
    const result = await db.runTransaction(async (transaction) => {
      const snap = await transaction.get(docRef);
      if (!snap.exists) throw new Error('Player not found');

      let p = snap.data();
      cleanupExpiredCrimeFreeze(p);
      const available = getAvailableBalance(p);

      const market = p.bondMarket || [];
      const index = market.findIndex(b => b.title === bondData.title && b.cost === bondData.cost);
      if (index === -1) throw new Error('This bond is no longer available.');
      if (available < bondData.cost) throw new Error('Not enough money (some funds may be temporarily frozen).');

      const bond = market[index];
      const couponAmount = (bond.couponRate / 100) * bondData.cost;

      p.balance -= bondData.cost;
      if (!p.ownedBonds) p.ownedBonds = [];

      p.ownedBonds.push({
        ...bond,
        purchaseTime: now,
        maturityTime: now + BOND_MATURITY_MS,
        couponAmount,
        paymentsRemaining: BOND_NUM_PAYMENTS,
        nextPaymentTime: now + BOND_PAYMENT_INTERVAL_MS
      });

      p.nextBondPaymentTime = getEarliestNextPaymentTime(p.ownedBonds);
      p.bondMarket = market.filter((_, i) => i !== index);
      p.hasActiveBonds = true;

      transaction.set(docRef, p);
      return { couponAmount };
    });

    const fresh = (await docRef.get()).data();
    const balanceBefore = fresh.balance + bondData.cost;

    await logTransaction(socket, -bondData.cost, `Bond Purchased: ${bondData.title}`, 
      { ...fresh, balance: balanceBefore }, docRef);

    socket.emit('update-stats', fresh);
    socket.emit('bond-result', {
      success: true,
      message: `✅ Bought ${bondData.title}! Coupon $${result.couponAmount.toFixed(0)} will be paid in ${BOND_NUM_PAYMENTS} installments every 2 minutes.`
    });

    await updateGlobalEarliestBondDueTime(db);

  } catch (error) {
    console.error('[BUY BOND ERROR]', error);
    socket.emit('bond-result', {
      success: false,
      message: error.message || 'Purchase failed. Please try again.'
    });
  }
}

// ==================== PROCESS ONE PLAYER'S BOND PAYMENTS (Correct & Safe Version) ====================
async function processPlayerBondPayments(db, playerDoc, now, onlineSockets) {
  const playerEmail = playerDoc.id;

  try {
    const result = await db.runTransaction(async (transaction) => {
      const snap = await transaction.get(playerDoc.ref);
      if (!snap.exists) return null;

      let p = snap.data();
      const hasBonds = p.ownedBonds && p.ownedBonds.length > 0;

      if (!hasBonds) {
        if (p.hasActiveBonds === true || p.nextBondPaymentTime) {
          transaction.update(playerDoc.ref, {
            hasActiveBonds: false,
            nextBondPaymentTime: null
          });
        }
        return null;
      }

      let updatedBonds = [];
      let couponOnlyTotal = 0;
      let maturityTotal = 0;

      for (const original of p.ownedBonds) {
        if (!original.nextPaymentTime || !original.paymentsRemaining) {
          updatedBonds.push(original);
          continue;
        }

        let bond = { ...original };

        while (now >= bond.nextPaymentTime && bond.paymentsRemaining > 0) {
          const paymentAmount = Math.round(bond.couponAmount / 4);

          if (bond.paymentsRemaining === 1) {
            maturityTotal += paymentAmount + bond.cost;
          } else {
            couponOnlyTotal += paymentAmount;
          }

          bond.paymentsRemaining--;
          if (bond.paymentsRemaining > 0) {
            bond.nextPaymentTime += BOND_PAYMENT_INTERVAL_MS;
          }
        }

        if (bond.paymentsRemaining > 0) {
          updatedBonds.push(bond);
        }
      }

      const stillHasBonds = updatedBonds.length > 0;
      const totalRefund = couponOnlyTotal + maturityTotal;

      if (totalRefund > 0) {
        const nextPaymentTime = getEarliestNextPaymentTime(updatedBonds);

        transaction.update(playerDoc.ref, {
          balance: admin.firestore.FieldValue.increment(totalRefund),
          ownedBonds: updatedBonds,
          hasActiveBonds: stillHasBonds,
          nextBondPaymentTime: nextPaymentTime
        });

        const oldBalance = p.balance || 0;

        if (couponOnlyTotal > 0) {
          const txRef = playerDoc.ref.collection('transactions').doc();
          transaction.set(txRef, {
            amount: couponOnlyTotal,
            description: 'Bond Coupon Payment',
            balanceAfter: oldBalance + couponOnlyTotal,
            timestamp: admin.firestore.FieldValue.serverTimestamp()
          });
        }

        if (maturityTotal > 0) {
          const txRef = playerDoc.ref.collection('transactions').doc();
          transaction.set(txRef, {
            amount: maturityTotal,
            description: 'Bond Coupon Payment & Maturity',
            balanceAfter: oldBalance + totalRefund,
            timestamp: admin.firestore.FieldValue.serverTimestamp()
          });
        }

        console.log(`[BOND COUPON] ${p.displayName || playerEmail} received $${totalRefund}`);

        return {
          totalRefund,
          isMaturity: maturityTotal > 0,
          displayName: p.displayName
        };
      } else {
        const nextPaymentTime = getEarliestNextPaymentTime(updatedBonds);
        transaction.update(playerDoc.ref, {
          ownedBonds: updatedBonds,
          nextBondPaymentTime: nextPaymentTime
        });
        return null;
      }
    });

    // ==================== SEND UPDATE TO PLAYER (Safe version with fresh read) ====================
    if (result && result.displayName && onlineSockets) {
      const socket = onlineSockets.get(result.displayName);
      if (socket) {
        // We do one extra read here to get the CORRECT final balance
        const fresh = (await db.collection('players').doc(playerEmail).get()).data();
        
        socket.emit('update-stats', fresh);
        socket.emit('new-transaction', {
          amount: result.totalRefund,
          description: result.isMaturity 
            ? 'Bond Coupon Payment & Maturity' 
            : 'Bond Coupon Payment',
          balanceAfter: fresh.balance
        });
      }
    }

  } catch (err) {
    console.error(`[BOND PAYMENT ERROR] Player ${playerEmail}:`, err);
  }
}

// ==================== BOND MATURITY CHECKER ====================
function startBondMaturityChecker(db, { onlineSockets }) {
  setInterval(async () => {
    try {
      const now = Date.now();

      // Step 1: Check our small note first (very fast)
      const metaSnap = await db.collection('system').doc('bondScheduler').get();
      const earliestDue = metaSnap.data()?.earliestNextPaymentTime || 0;

      if (now < earliestDue) {
        return; // Nothing is due yet, so skip the big search
      }

      // Step 2: Only do the bigger search if something might be due
      const snapshot = await db.collection('players')
        .where('nextBondPaymentTime', '>', 0)
        .where('nextBondPaymentTime', '<=', now)
        .orderBy('nextBondPaymentTime')
        .limit(100)
        .get();

      if (snapshot.empty) {
        await updateGlobalEarliestBondDueTime(db);
        return;
      }

      // Step 3: Process the payments that are due
      for (const doc of snapshot.docs) {
        await processPlayerBondPayments(db, doc, now, onlineSockets);
      }

      // Step 4: Update our small note with the new next due time
      await updateGlobalEarliestBondDueTime(db);

    } catch (err) {
      console.error('[BOND CHECKER ERROR]', err);
    }
  }, 10000); // Check every 10 seconds
}

// ==================== STARTUP RECONCILIATION ====================
async function reconcileBondFlags(db) {
  try {
    console.log('[BONDS] Starting bond flag reconciliation...');
    const snapshot = await db.collection('players').get();
    const batch = db.batch();
    let fixed = 0;

    for (const doc of snapshot.docs) {
      const p = doc.data();
      const hasBonds = p.ownedBonds && p.ownedBonds.length > 0;

      if (hasBonds) {
        const correctTime = getEarliestNextPaymentTime(p.ownedBonds);
        if (p.hasActiveBonds !== true || p.nextBondPaymentTime !== correctTime) {
          batch.update(doc.ref, {
            hasActiveBonds: true,
            nextBondPaymentTime: correctTime
          });
          fixed++;
        }
      } else if (p.hasActiveBonds === true || p.nextBondPaymentTime) {
        batch.update(doc.ref, {
          hasActiveBonds: false,
          nextBondPaymentTime: null
        });
        fixed++;
      }
    }

    if (fixed > 0) {
      await batch.commit();
      console.log(`[BONDS] Reconciliation complete. Fixed ${fixed} player(s).`);
    } else {
      console.log('[BONDS] Reconciliation complete. Nothing to fix.');
    }
  } catch (e) {
    console.error('[BONDS] Reconciliation error:', e);
  }
}

// ==================== HELPER FUNCTION ====================
async function updateGlobalEarliestBondDueTime(db) {
  try {
    const snap = await db.collection('players')
      .where('nextBondPaymentTime', '>', 0)
      .orderBy('nextBondPaymentTime')
      .limit(1)
      .get();

    const earliest = snap.empty ? null : snap.docs[0].data().nextBondPaymentTime;

    await db.collection('system').doc('bondScheduler').set({
      earliestNextPaymentTime: earliest
    }, { merge: true });

  } catch (err) {
    console.error('[BOND] Failed to update global earliest due time:', err);
  }
}

module.exports = {
  handleRequestBondMarket,
  handleRefreshBondMarket,
  handleBuyBond,
  startBondMaturityChecker,
  reconcileBondFlags,
  updateGlobalEarliestBondDueTime
};