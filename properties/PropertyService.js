/**
 * PropertyService – all database mutations + the passive income scheduler.
 *
 * - Every balance / ownership change is performed inside a Firestore transaction.
 * - Transaction history documents are written inside the same transaction.
 * - Socket emits happen only after the transaction has successfully committed.
 * - Mechanics, messages, data shape and client-visible payloads are identical
 *   to the original implementation.
 * - Income is now fully passive (mirrors the bonds scheduler).
 */

const admin = require('firebase-admin');
const { getAvailableBalance, cleanupExpiredCrimeFreeze } = require('../utils');
const {
  PROPERTIES,
  UPGRADE_COSTS,
  CLAIM_INTERVAL_MS
} = require('./constants');
const {
  getProperty,
  getUpgradeCost,
  calculateClaimAward,
  getEarliestNextClaimTime,
  validateBuyProperty,
  validateBuyUpgrade
} = require('./PropertyCalculator');

// ==================== IN-MEMORY SCHEDULER STATE ====================
const propertyPending = new Map(); // email → nextClaimTime
let propertyTimeout = null;
let isProcessingProperties = false;
let propertySchedulerDeps = null; // { onlineSockets, db }

const PROCESS_CONCURRENCY = 15;

// ==================== SCHEDULER CORE ====================
function scheduleNextProperty() {
  if (propertyTimeout) {
    clearTimeout(propertyTimeout);
    propertyTimeout = null;
  }

  if (isProcessingProperties) return;

  let earliest = Infinity;
  let earliestEmail = null;
  for (const [email, time] of propertyPending) {
    if (time < earliest) {
      earliest = time;
      earliestEmail = email;
    }
  }
  if (!earliestEmail) return;

  const delay = Math.max(0, earliest - Date.now());
  propertyTimeout = setTimeout(() => {
    processDueProperties().catch(err => {
      console.error('[PROPERTY SCHEDULER ERROR]', err);
      isProcessingProperties = false;
      scheduleNextProperty();
    });
  }, delay);
}

function updatePlayerInPropertyScheduler(email, nextClaimTime) {
  if (typeof nextClaimTime === 'number' && nextClaimTime > 0) {
    propertyPending.set(email, nextClaimTime);
  } else {
    propertyPending.delete(email);
  }
  scheduleNextProperty();
}

async function processDueProperties() {
  if (isProcessingProperties) return;
  isProcessingProperties = true;

  try {
    const now = Date.now();
    const dueEmails = [];
    for (const [email, time] of propertyPending) {
      if (time <= now) dueEmails.push(email);
    }

    if (dueEmails.length === 0) return;

    console.log(`[PROPERTY SCHEDULER] Processing ${dueEmails.length} player(s) with due income`);

    for (let i = 0; i < dueEmails.length; i += PROCESS_CONCURRENCY) {
      const batch = dueEmails.slice(i, i + PROCESS_CONCURRENCY);
      await Promise.all(
        batch.map(email => processPlayerPropertyIncome(email, now))
      );
    }
  } finally {
    isProcessingProperties = false;
    scheduleNextProperty();
  }
}

async function processPlayerPropertyIncome(email, now) {
  if (!propertySchedulerDeps) return;
  const { db, onlineSockets } = propertySchedulerDeps;
  const docRef = db.collection('players').doc(email);

  try {
    const result = await db.runTransaction(async (transaction) => {
      const snap = await transaction.get(docRef);
      if (!snap.exists) return null;

      let p = snap.data();
      const owned = p.ownedProperties || [];
      const claims = p.propertyClaims || [];

      if (owned.length === 0) {
        if (p.hasActiveProperties === true || p.nextPropertyClaimTime) {
          transaction.update(docRef, {
            hasActiveProperties: false,
            nextPropertyClaimTime: null
          });
        }
        return { nextClaimTime: null, displayName: p.displayName };
      }

      const { totalAward, updatedClaims } = calculateClaimAward(p, now);
      const nextClaimTime = getEarliestNextClaimTime(updatedClaims, owned);

      if (totalAward > 0) {
        const newBalance = (p.balance || 0) + totalAward;

        transaction.update(docRef, {
          balance: admin.firestore.FieldValue.increment(totalAward),
          propertyClaims: updatedClaims,
          hasActiveProperties: true,
          nextPropertyClaimTime: nextClaimTime
        });

        // History log written inside the same transaction
        const txRef = docRef.collection('transactions').doc();
        transaction.set(txRef, {
          amount: totalAward,
          description: 'Property Income',
          balanceAfter: Math.round(newBalance),
          timestamp: admin.firestore.FieldValue.serverTimestamp()
        });

        return {
          totalAward,
          nextClaimTime,
          displayName: p.displayName,
          newBalance: Math.round(newBalance)
        };
      } else {
        transaction.update(docRef, {
          propertyClaims: updatedClaims,
          hasActiveProperties: true,
          nextPropertyClaimTime: nextClaimTime
        });
        return {
          totalAward: 0,
          nextClaimTime,
          displayName: p.displayName
        };
      }
    });

    if (result) {
      updatePlayerInPropertyScheduler(email, result.nextClaimTime);
    } else {
      propertyPending.delete(email);
    }

    // Live push to player if online
    if (result && result.totalAward > 0 && result.displayName && onlineSockets) {
      const socket = onlineSockets.get(result.displayName);
      if (socket) {
        const fresh = (await docRef.get()).data();
        socket.emit('update-stats', fresh);
        socket.emit('new-transaction', {
          amount: result.totalAward,
          description: 'Property Income',
          balanceAfter: result.newBalance
        });
        socket.emit('income-claimed', { amount: result.totalAward });
      }
    }
  } catch (err) {
    console.error(`[PROPERTY INCOME ERROR] Player ${email}:`, err);
  }
}

// ==================== STARTUP / REBUILD ====================
async function rebuildPropertyScheduler(db) {
  try {
    console.log('[PROPERTIES] Rebuilding in-memory scheduler from active properties...');
    propertyPending.clear();

    const snapshot = await db.collection('players')
      .where('hasActiveProperties', '==', true)
      .get();

    let fixed = 0;
    let batch = db.batch();
    let batchCount = 0;

    for (const doc of snapshot.docs) {
      const p = doc.data();
      const owned = p.ownedProperties || [];
      const claims = p.propertyClaims || [];
      const correctTime = owned.length > 0 ? getEarliestNextClaimTime(claims, owned) : null;

      if (owned.length > 0 && correctTime) {
        propertyPending.set(doc.id, correctTime);

        if (p.hasActiveProperties !== true || p.nextPropertyClaimTime !== correctTime) {
          batch.update(doc.ref, {
            hasActiveProperties: true,
            nextPropertyClaimTime: correctTime
          });
          fixed++;
          batchCount++;
        }
      } else {
        batch.update(doc.ref, {
          hasActiveProperties: false,
          nextPropertyClaimTime: null
        });
        fixed++;
        batchCount++;
      }

      if (batchCount >= 400) {
        await batch.commit();
        batch = db.batch();
        batchCount = 0;
      }
    }

    if (batchCount > 0) {
      await batch.commit();
    }

    console.log(`[PROPERTIES] Scheduler rebuilt. ${propertyPending.size} active player(s). Fixed ${fixed} flag(s).`);
  } catch (e) {
    console.error('[PROPERTIES] Rebuild error:', e);
  }
}

function startPropertyScheduler(db, deps) {
  propertySchedulerDeps = { ...deps, db };
  scheduleNextProperty();
  console.log('[PROPERTIES] Event-driven property income scheduler started');
}

// ==================== INSTANT CATCH-UP ON LOGIN / RECONNECT ====================
async function processOverduePropertiesForPlayer(db, email, onlineSockets) {
  if (!email) return;

  if (!propertySchedulerDeps) {
    propertySchedulerDeps = { onlineSockets, db };
  } else {
    propertySchedulerDeps.onlineSockets = onlineSockets;
  }

  const doc = await db.collection('players').doc(email).get();
  if (!doc.exists) return;

  const p = doc.data();
  const owned = p.ownedProperties || [];
  if (owned.length === 0) {
    if (p.hasActiveProperties || p.nextPropertyClaimTime) {
      await doc.ref.update({
        hasActiveProperties: false,
        nextPropertyClaimTime: null
      });
      propertyPending.delete(email);
    }
    return;
  }

  const earliest = getEarliestNextClaimTime(p.propertyClaims || [], owned);
  const now = Date.now();

  updatePlayerInPropertyScheduler(email, earliest);

  if (earliest && earliest <= now) {
    await processPlayerPropertyIncome(email, now);
  }
}

// ==================== ORIGINAL HANDLERS (now scheduler-aware) ====================
class PropertyService {
  async buyProperty(db, socket, propertyName) {
    const email = socket.data.email;
    if (!email || typeof propertyName !== 'string') return;

    const docRef = db.collection('players').doc(email);
    const prop = getProperty(propertyName);
    if (!prop) return;

    try {
      const result = await db.runTransaction(async (transaction) => {
        const snap = await transaction.get(docRef);
        if (!snap.exists) return null;

        let p = snap.data();
        const wasCleaned = cleanupExpiredCrimeFreeze(p);

        const validation = validateBuyProperty(p, propertyName);
        if (validation === 'already_owned') return { skip: true };
        if (validation === 'invalid_property') return { skip: true };

        const availableBalance = getAvailableBalance(p);
        if (availableBalance < prop.cost) {
          throw new Error('Not enough money (some funds may be temporarily frozen)');
        }

        const now = Date.now();
        const newBalance = (p.balance || 0) - prop.cost;
        const newOwned = [...(p.ownedProperties || []), propertyName];
        const newClaims = [...(p.propertyClaims || []), { name: propertyName, lastClaim: now }];

        // Compute the true earliest next claim across *all* owned properties
        // (preserves any earlier timers the player already had)
        const nextClaimTime = getEarliestNextClaimTime(newClaims, newOwned);

        const updates = {
          balance: newBalance,
          ownedProperties: newOwned,
          propertyClaims: newClaims,
          hasActiveProperties: true,
          nextPropertyClaimTime: nextClaimTime
        };

        if (wasCleaned) {
          updates.crimeFreezeUntil = admin.firestore.FieldValue.delete();
          updates.frozenCrimeMoney = admin.firestore.FieldValue.delete();
        }

        transaction.update(docRef, updates);

        const txRef = docRef.collection('transactions').doc();
        transaction.set(txRef, {
          amount: -prop.cost,
          description: `Property Purchased: ${propertyName}`,
          balanceAfter: newBalance,
          timestamp: admin.firestore.FieldValue.serverTimestamp()
        });

        return {
          cost: prop.cost,
          description: `Property Purchased: ${propertyName}`,
          newBalance,
          nextClaimTime,
          updatedPlayer: {
            ...p,
            balance: newBalance,
            ownedProperties: newOwned,
            propertyClaims: newClaims,
            hasActiveProperties: true,
            nextPropertyClaimTime: nextClaimTime
          }
        };
      });

      if (!result || result.skip) return;

      // Immediately put the player into the scheduler
      updatePlayerInPropertyScheduler(email, result.nextClaimTime);

      socket.emit('new-transaction', {
        amount: -result.cost,
        description: result.description,
        balanceAfter: result.newBalance
      });
      socket.emit('update-stats', result.updatedPlayer);
    } catch (error) {
      if (error.message && error.message.includes('Not enough money')) {
        socket.emit('error', {
          message: 'Not enough money (some funds may be temporarily frozen)'
        });
      } else {
        console.error('[PROPERTIES] buyProperty error:', error);
      }
    }
  }

  async buyUpgrade(db, socket, propertyName, upgradeName) {
    const email = socket.data.email;
    if (!email || typeof propertyName !== 'string' || typeof upgradeName !== 'string') return;

    const docRef = db.collection('players').doc(email);
    const cost = getUpgradeCost(propertyName, upgradeName);
    if (cost === undefined) return;

    try {
      const result = await db.runTransaction(async (transaction) => {
        const snap = await transaction.get(docRef);
        if (!snap.exists) return null;

        let p = snap.data();
        const wasCleaned = cleanupExpiredCrimeFreeze(p);

        const validation = validateBuyUpgrade(p, propertyName, upgradeName);
        if (validation) return { skip: true };

        const availableBalance = getAvailableBalance(p);
        if (availableBalance < cost) {
          throw new Error('Not enough money (some funds may be temporarily frozen)');
        }

        const newBalance = (p.balance || 0) - cost;
        const ownedUpgrades = { ...(p.ownedUpgrades || {}) };
        if (!ownedUpgrades[propertyName]) ownedUpgrades[propertyName] = [];
        ownedUpgrades[propertyName] = [...ownedUpgrades[propertyName], upgradeName];

        const updates = {
          balance: newBalance,
          ownedUpgrades
        };

        if (wasCleaned) {
          updates.crimeFreezeUntil = admin.firestore.FieldValue.delete();
          updates.frozenCrimeMoney = admin.firestore.FieldValue.delete();
        }

        transaction.update(docRef, updates);

        const txRef = docRef.collection('transactions').doc();
        transaction.set(txRef, {
          amount: -cost,
          description: `Upgrade Purchased: ${upgradeName} on ${propertyName}`,
          balanceAfter: newBalance,
          timestamp: admin.firestore.FieldValue.serverTimestamp()
        });

        return {
          cost,
          description: `Upgrade Purchased: ${upgradeName} on ${propertyName}`,
          newBalance,
          updatedPlayer: {
            ...p,
            balance: newBalance,
            ownedUpgrades
          }
        };
      });

      if (!result || result.skip) return;

      socket.emit('new-transaction', {
        amount: -result.cost,
        description: result.description,
        balanceAfter: result.newBalance
      });
      socket.emit('update-stats', result.updatedPlayer);
    } catch (error) {
      if (error.message && error.message.includes('Not enough money')) {
        socket.emit('error', {
          message: 'Not enough money (some funds may be temporarily frozen)'
        });
      } else {
        console.error('[PROPERTIES] buyUpgrade error:', error);
      }
    }
  }

  /**
   * Manual force-claim (kept for UI button / debugging).
   * The passive scheduler is the normal path.
   */
  async claimIncome(db, socket) {
    const email = socket.data.email;
    if (!email) return;

    // Just force the process for this player right now
    await processPlayerPropertyIncome(email, Date.now());
  }
}

const propertyService = new PropertyService();

module.exports = {
  PropertyService,
  propertyService,
  // Scheduler exports
  rebuildPropertyScheduler,
  startPropertyScheduler,
  processOverduePropertiesForPlayer,
  updatePlayerInPropertyScheduler,
};