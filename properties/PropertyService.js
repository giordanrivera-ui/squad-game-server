/**
 * PropertyService – all database mutations for the properties feature.
 * Every balance / ownership change is performed inside a Firestore transaction.
 * Mechanics, messages, data shape and socket payloads are identical to the original.
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
  validateBuyProperty,
  validateBuyUpgrade
} = require('./PropertyCalculator');

class PropertyService {
  /**
   * Buy a property. Fully transactional.
   * Preserves original silent-fail behaviour for already-owned / invalid names
   * and the exact error message for insufficient funds.
   */
  async buyProperty(db, socket, propertyName) {
    const email = socket.data.email;
    if (!email || typeof propertyName !== 'string') return;

    const docRef = db.collection('players').doc(email);
    const prop = getProperty(propertyName);
    if (!prop) return; // silent like original

    try {
      const result = await db.runTransaction(async (transaction) => {
        const snap = await transaction.get(docRef);
        if (!snap.exists) return null;

        let p = snap.data();

        // Exact original freeze cleanup behaviour
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

        const updates = {
          balance: newBalance,
          ownedProperties: newOwned,
          propertyClaims: newClaims
        };

        // Persist any freeze cleanup that happened on the local object
        if (wasCleaned || (!p.crimeFreezeUntil && p.frozenCrimeMoney !== undefined)) {
          updates.crimeFreezeUntil = admin.firestore.FieldValue.delete();
          updates.frozenCrimeMoney = admin.firestore.FieldValue.delete();
        }

        transaction.update(docRef, updates);

        // Transaction log written atomically with the balance change
        const txRef = docRef.collection('transactions').doc();
        transaction.set(txRef, {
          amount: -prop.cost,
          description: `Property Purchased: ${propertyName}`,
          balanceAfter: newBalance,
          timestamp: admin.firestore.FieldValue.serverTimestamp()
        });

        return {
          newBalance,
          cost: prop.cost,
          description: `Property Purchased: ${propertyName}`,
          updatedPlayer: {
            ...p,
            balance: newBalance,
            ownedProperties: newOwned,
            propertyClaims: newClaims
          }
        };
      });

      if (!result || result.skip) return;

      // Live feedback – identical to original
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

  /**
   * Buy an upgrade for an owned property. Fully transactional.
   */
  async buyUpgrade(db, socket, propertyName, upgradeName) {
    const email = socket.data.email;
    if (!email || typeof propertyName !== 'string' || typeof upgradeName !== 'string') return;

    const docRef = db.collection('players').doc(email);
    const cost = getUpgradeCost(propertyName, upgradeName);
    if (cost === undefined) return; // silent

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
          newBalance,
          cost,
          description: `Upgrade Purchased: ${upgradeName} on ${propertyName}`,
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
   * Claim all accrued property income. Fully transactional.
   * Preserves the exact catch-up math, the “only write if money earned”
   * rule, the transaction-log description, and the income-claimed event.
   */
  async claimIncome(db, socket) {
    const email = socket.data.email;
    if (!email) return;

    const docRef = db.collection('players').doc(email);

    try {
      const result = await db.runTransaction(async (transaction) => {
        const snap = await transaction.get(docRef);
        if (!snap.exists) {
          return { totalAward: 0 };
        }

        const p = snap.data();
        const now = Date.now();

        const { totalAward, updatedClaims, playerBefore } = calculateClaimAward(p, now);

        if (totalAward <= 0) {
          return { totalAward: 0 };
        }

        // Atomic balance + claims update
        transaction.update(docRef, {
          balance: admin.firestore.FieldValue.increment(totalAward),
          propertyClaims: updatedClaims
        });

        // Transaction log written inside the same atomic unit
        const txRef = docRef.collection('transactions').doc();
        const balanceAfter = (p.balance || 0) + totalAward;
        transaction.set(txRef, {
          amount: totalAward,
          description: 'Property Income',
          balanceAfter: Math.round(balanceAfter),
          timestamp: admin.firestore.FieldValue.serverTimestamp()
        });

        return {
          totalAward,
          playerBefore,
          balanceAfter
        };
      });

      if (!result || result.totalAward <= 0) return;

      // Live feedback – identical events and payloads to original
      socket.emit('new-transaction', {
        amount: result.totalAward,
        description: 'Property Income',
        balanceAfter: result.balanceAfter
      });

      // Fresh read so client receives the absolute latest document
      const freshDoc = await docRef.get();
      if (freshDoc.exists) {
        socket.emit('update-stats', freshDoc.data());
      }
      socket.emit('income-claimed', { amount: result.totalAward });
    } catch (error) {
      console.error('[CLAIM ERROR] Transaction failed for', email, error);
      socket.emit('income-claimed', {
        success: false,
        message: 'Claim failed — please try again.'
      });
    }
  }
}

const propertyService = new PropertyService();

module.exports = {
  PropertyService,
  propertyService
};
