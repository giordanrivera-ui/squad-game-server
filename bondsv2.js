const admin = require('firebase-admin');
const { logTransaction, getAvailableBalance, cleanupExpiredCrimeFreeze } = require('./utils');

// ==================== BOND CONFIGURATION ====================
const BOND_MATURITY_MS = 8 * 60 * 1000;
const BOND_PAYMENT_INTERVAL_MS = 2 * 60 * 1000;
const BOND_NUM_PAYMENTS = 4;
const BOND_MARKET_COOLDOWN_MS = 2 * 60 * 1000;
const PROCESS_CONCURRENCY = 15;

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

// ==================== IN-MEMORY SCHEDULER STATE ====================
const pending = new Map(); // email → nextPaymentTime (number)
let currentTimeout = null;
let isProcessing = false;
let schedulerDeps = null; // { onlineSockets }

// ==================== PURE HELPERS ====================
function getEarliestNextPaymentTime(bonds) {
  if (!bonds || bonds.length === 0) return null;
  const validTimes = bonds
    .map(b => b.nextPaymentTime)
    .filter(t => typeof t === 'number' && t > 0);
  return validTimes.length > 0 ? Math.min(...validTimes) : null;
}

function advanceBondPayments(original, now) {
  let bond = { ...original };
  let couponOnlyTotal = 0;
  let maturityTotal = 0;

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

  return {
    bond,
    couponOnlyTotal,
    maturityTotal,
    stillActive: bond.paymentsRemaining > 0
  };
}

function getMinPending() {
  let minTime = Infinity;
  let minEmail = null;
  for (const [email, time] of pending) {
    if (time < minTime) {
      minTime = time;
      minEmail = email;
    }
  }
  return minEmail ? { email: minEmail, time: minTime } : null;
}

// ==================== SCHEDULER CORE ====================
function scheduleNext() {
  if (currentTimeout) {
    clearTimeout(currentTimeout);
    currentTimeout = null;
  }

  if (isProcessing) return; // will be re-armed after current run finishes

  const next = getMinPending();
  if (!next) return;

  const delay = Math.max(0, next.time - Date.now());
  currentTimeout = setTimeout(() => {
    processDueBonds().catch(err => {
      console.error('[BOND SCHEDULER ERROR]', err);
      isProcessing = false;
      scheduleNext();
    });
  }, delay);
}

function updatePlayerInScheduler(email, nextPaymentTime) {
  if (typeof nextPaymentTime === 'number' && nextPaymentTime > 0) {
    pending.set(email, nextPaymentTime);
  } else {
    pending.delete(email);
  }
  scheduleNext(); // re-evaluate (may cancel & reschedule earlier/later/none)
}

async function processDueBonds() {
  if (isProcessing) return;
  isProcessing = true;

  try {
    const now = Date.now();
    const dueEmails = [];
    for (const [email, time] of pending) {
      if (time <= now) dueEmails.push(email);
    }

    if (dueEmails.length === 0) return;

    console.log(`[BOND SCHEDULER] Processing ${dueEmails.length} player(s) with due payments`);

    // Limited concurrency
    for (let i = 0; i < dueEmails.length; i += PROCESS_CONCURRENCY) {
      const batch = dueEmails.slice(i, i + PROCESS_CONCURRENCY);
      await Promise.all(
        batch.map(email => processPlayerBondPayments(email, now))
      );
    }
  } finally {
    isProcessing = false;
    scheduleNext();
  }
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
      return { couponAmount, nextBondPaymentTime: p.nextBondPaymentTime };
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

    // Update in-memory scheduler immediately
    updatePlayerInScheduler(email, result.nextBondPaymentTime);

  } catch (error) {
    console.error('[BUY BOND ERROR]', error);
    socket.emit('bond-result', {
      success: false,
      message: error.message || 'Purchase failed. Please try again.'
    });
  }
}

// ==================== PROCESS ONE PLAYER ====================
async function processPlayerBondPayments(email, now) {
  if (!schedulerDeps) return;
  const { onlineSockets } = schedulerDeps;
  const db = schedulerDeps.db;
  const playerDocRef = db.collection('players').doc(email);

  try {
    const result = await db.runTransaction(async (transaction) => {
      const snap = await transaction.get(playerDocRef);
      if (!snap.exists) return null;

      let p = snap.data();
      const hasBonds = p.ownedBonds && p.ownedBonds.length > 0;

      if (!hasBonds) {
        if (p.hasActiveBonds === true || p.nextBondPaymentTime) {
          transaction.update(playerDocRef, {
            hasActiveBonds: false,
            nextBondPaymentTime: null
          });
        }
        return { nextPaymentTime: null, displayName: p.displayName };
      }

      let updatedBonds = [];
      let couponOnlyTotal = 0;
      let maturityTotal = 0;

      for (const original of p.ownedBonds) {
        if (!original.nextPaymentTime || !original.paymentsRemaining) {
          updatedBonds.push(original);
          continue;
        }

        const advanced = advanceBondPayments(original, now);
        couponOnlyTotal += advanced.couponOnlyTotal;
        maturityTotal += advanced.maturityTotal;

        if (advanced.stillActive) {
          updatedBonds.push(advanced.bond);
        }
      }

      const stillHasBonds = updatedBonds.length > 0;
      const totalRefund = couponOnlyTotal + maturityTotal;
      const nextPaymentTime = getEarliestNextPaymentTime(updatedBonds);

      if (totalRefund > 0) {
        transaction.update(playerDocRef, {
          balance: admin.firestore.FieldValue.increment(totalRefund),
          ownedBonds: updatedBonds,
          hasActiveBonds: stillHasBonds,
          nextBondPaymentTime: nextPaymentTime
        });

        const oldBalance = p.balance || 0;

        if (couponOnlyTotal > 0) {
          const txRef = playerDocRef.collection('transactions').doc();
          transaction.set(txRef, {
            amount: couponOnlyTotal,
            description: 'Bond Coupon Payment',
            balanceAfter: oldBalance + couponOnlyTotal,
            timestamp: admin.firestore.FieldValue.serverTimestamp()
          });
        }

        if (maturityTotal > 0) {
          const txRef = playerDocRef.collection('transactions').doc();
          transaction.set(txRef, {
            amount: maturityTotal,
            description: 'Bond Coupon Payment & Maturity',
            balanceAfter: oldBalance + totalRefund,
            timestamp: admin.firestore.FieldValue.serverTimestamp()
          });
        }

        console.log(`[BOND COUPON] ${p.displayName || email} received $${totalRefund}`);

        return {
          totalRefund,
          isMaturity: maturityTotal > 0,
          displayName: p.displayName,
          nextPaymentTime
        };
      } else {
        transaction.update(playerDocRef, {
          ownedBonds: updatedBonds,
          hasActiveBonds: stillHasBonds,
          nextBondPaymentTime: nextPaymentTime
        });
        return {
          totalRefund: 0,
          displayName: p.displayName,
          nextPaymentTime
        };
      }
    });

    // Always keep the in-memory scheduler in sync with the result
    if (result) {
      updatePlayerInScheduler(email, result.nextPaymentTime);
    } else {
      pending.delete(email);
    }

    // Live push to player if online
    if (result && result.totalRefund > 0 && result.displayName && onlineSockets) {
      const socket = onlineSockets.get(result.displayName);
      if (socket) {
        const fresh = (await playerDocRef.get()).data();
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
    console.error(`[BOND PAYMENT ERROR] Player ${email}:`, err);
  }
}

// ==================== STARTUP / REBUILD ====================
async function rebuildBondScheduler(db) {
  try {
    console.log('[BONDS] Rebuilding in-memory scheduler from active bonds...');
    pending.clear();

    // 1. Ask Firestore for every player who currently has the flag "hasActiveBonds = true"
    const snapshot = await db.collection('players')
      .where('hasActiveBonds', '==', true)
      .get();

    let fixed = 0;               // how many players we corrected
    let batch = db.batch();      // ← create the FIRST empty box
    let batchCount = 0;          // how many sticky notes are currently in the box

    // 2. Go through every player one by one
    for (const doc of snapshot.docs) {
      const p = doc.data();
      const owned = p.ownedBonds || [];
      const hasBonds = owned.length > 0;
      const correctTime = hasBonds ? getEarliestNextPaymentTime(owned) : null;

      if (hasBonds && correctTime) {
        // This player really has bonds → put them in our memory Map
        pending.set(doc.id, correctTime);

        // If the flags on the document are wrong, write a correction sticky note
        if (p.hasActiveBonds !== true || p.nextBondPaymentTime !== correctTime) {
          batch.update(doc.ref, {
            hasActiveBonds: true,
            nextBondPaymentTime: correctTime
          });
          fixed++;
          batchCount++;          // we added one sticky note
        }
      } else {
        // Player has the flag but actually has no bonds → clean the flag
        batch.update(doc.ref, {
          hasActiveBonds: false,
          nextBondPaymentTime: null
        });
        fixed++;
        batchCount++;            // we added one sticky note
      }

      // 3. If the box now has 400 sticky notes, hand it over and start a new box
      if (batchCount >= 400) {
        await batch.commit();    // hand the full box to Firestore
        batch = db.batch();      // ← create a BRAND NEW empty box
        batchCount = 0;          // the new box starts empty
      }
    }

    // 4. After the loop finishes, hand over any remaining sticky notes
    //    (this happens when the last box has fewer than 400 notes)
    if (batchCount > 0) {
      await batch.commit();
    }

    console.log(`[BONDS] Scheduler rebuilt. ${pending.size} active player(s). Fixed ${fixed} flag(s).`);
  } catch (e) {
    console.error('[BONDS] Rebuild error:', e);
  }
}

function startBondScheduler(db, deps) {
  schedulerDeps = { ...deps, db };
  scheduleNext();
  console.log('[BONDS] Event-driven bond scheduler started');
}

// ==================== INSTANT CATCH-UP ON LOGIN / RECONNECT ====================
async function processOverdueForPlayer(db, email, onlineSockets) {
  if (!email) return;

  // Ensure deps exist
  if (!schedulerDeps) {
    schedulerDeps = { onlineSockets, db };
  } else {
    schedulerDeps.onlineSockets = onlineSockets;
  }

  // Always read the live document — never trust the Map alone
  const doc = await db.collection('players').doc(email).get();
  if (!doc.exists) return;

  const p = doc.data();
  const owned = p.ownedBonds || [];
  if (owned.length === 0) {
    // Clean stale flags if present
    if (p.hasActiveBonds || p.nextBondPaymentTime) {
      await doc.ref.update({
        hasActiveBonds: false,
        nextBondPaymentTime: null
      });
      pending.delete(email);
    }
    return;
  }

  const earliest = getEarliestNextPaymentTime(owned);
  const now = Date.now();

  // Always keep Map in sync
  updatePlayerInScheduler(email, earliest);

  // Force process if anything is overdue
  if (earliest && earliest <= now) {
    await processPlayerBondPayments(email, now);
  }
}

module.exports = {
  handleRequestBondMarket,
  handleRefreshBondMarket,
  handleBuyBond,
  startBondScheduler,
  rebuildBondScheduler,
  processOverdueForPlayer,
  // Kept for any external callers that might still reference the old name
  updateGlobalEarliestBondDueTime: async () => {} // no-op
};