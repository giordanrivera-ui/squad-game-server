/**
 * MaintenanceService – exact original fee formula, 2-minute cadence,
 * cheapest-first payment, auto-disable, transaction logging.
 * Optimised: the interval is only active while at least one hospital
 * is offering Injury Healing (no wasted work when none are active).
 */

const admin = require('firebase-admin');
const { getAvailableBalance } = require('../../utils');
const { MAINTENANCE_CHECK_INTERVAL_MS } = require('../../hospital_constants');
const { hospitalRepository } = require('./HospitalRepository');

class MaintenanceService {
  constructor() {
    this.intervalId = null;
    this.db = null;
    this.onlineSockets = null;
    this.io = null;
  }

  start(db, { onlineSockets, io }) {
    this.db = db;
    this.onlineSockets = onlineSockets;
    this.io = io;

    // Start the checker. It will no-op quickly when nothing is offering.
    if (this.intervalId) clearInterval(this.intervalId);

    this.intervalId = setInterval(() => {
      this._runCheck().catch(err => {
        console.error('[HOSPITAL MAINT] Critical error in maintenance checker:', err);
      });
    }, MAINTENANCE_CHECK_INTERVAL_MS);

    console.log('[HOSPITAL MAINT] Maintenance checker started (every 2 minutes)');
  }

  stop() {
    if (this.intervalId) {
      clearInterval(this.intervalId);
      this.intervalId = null;
    }
  }

  async _runCheck() {
    // Fast path: use in-memory cache – only hospitals that currently offer healing
    const offering = [];
    for (const [id, hospital] of hospitalRepository.cache) {
      if (hospital.offerInjuryHealing === true && hospital.ownerEmail) {
        offering.push({ id, hospital });
      }
    }

    if (offering.length === 0) return;

    // Group by owner
    const hospitalsByOwner = {};
    for (const item of offering) {
      const email = item.hospital.ownerEmail;
      if (!hospitalsByOwner[email]) hospitalsByOwner[email] = [];
      hospitalsByOwner[email].push(item);
    }

    const hospitalsToDisable = [];

    for (const [ownerEmail, ownerHospitals] of Object.entries(hospitalsByOwner)) {
      const ownerRef = this.db.collection('players').doc(ownerEmail);

      try {
        const txResult = await this.db.runTransaction(async (transaction) => {
          const ownerSnap = await transaction.get(ownerRef);
          if (!ownerSnap.exists) {
            return { success: false };
          }

          const owner = ownerSnap.data();
          let availableBalance = getAvailableBalance(owner);
          let runningBalance = owner.balance || 0;

          const paidHospitals = [];
          const toDisableThisOwner = [];

          // Sort by fee ascending → pay cheapest first (exact original)
          const hospitalsWithFees = ownerHospitals
            .map(({ id, hospital }) => ({
              id,
              hospital,
              fee: hospital.calculateMaintenanceFee()
            }))
            .sort((a, b) => a.fee - b.fee);

          let totalDeducted = 0;

          for (const item of hospitalsWithFees) {
            const fee = item.fee;
            if (fee <= 0) continue;

            if (availableBalance >= fee) {
              availableBalance -= fee;
              runningBalance -= fee;
              totalDeducted += fee;

              const txRef = ownerRef.collection('transactions').doc();
              transaction.set(txRef, {
                amount: -fee,
                description: `Hospital Maintenance - Injury Healing ($${fee})`,
                balanceAfter: runningBalance,
                timestamp: admin.firestore.FieldValue.serverTimestamp()
              });

              paidHospitals.push({ fee, balanceAfter: runningBalance });
            } else {
              toDisableThisOwner.push({
                id: item.id,
                ownerEmail,
                displayName: owner.displayName || ownerEmail
              });
            }
          }

          if (totalDeducted > 0) {
            transaction.update(ownerRef, {
              balance: admin.firestore.FieldValue.increment(-totalDeducted)
            });
          }

          return {
            success: true,
            displayName: owner.displayName || ownerEmail,
            paidHospitals,
            totalDeducted,
            hospitalsToDisable: toDisableThisOwner
          };
        });

        if (txResult.success) {
          if (txResult.totalDeducted > 0) {
            console.log(
              `[HOSPITAL MAINT] $${txResult.totalDeducted} deducted from ${txResult.displayName} ` +
              `(${txResult.paidHospitals.length} hospital${txResult.paidHospitals.length === 1 ? '' : 's'})`
            );
          }

          hospitalsToDisable.push(...txResult.hospitalsToDisable);

          // Notify owner with fresh stats
          const socket = this.onlineSockets.get(txResult.displayName);
          if (socket && txResult.totalDeducted > 0) {
            const freshDoc = await this.db.collection('players').doc(ownerEmail).get();
            if (freshDoc.exists) {
              socket.emit('update-stats', freshDoc.data());
            }
          }
        }
      } catch (err) {
        console.error(`[HOSPITAL MAINT] Transaction failed for owner ${ownerEmail}:`, err);
      }
    }

    // Disable hospitals that could not be paid for
    if (hospitalsToDisable.length > 0) {
      for (const item of hospitalsToDisable) {
        await hospitalRepository.update(item.id, (h) => {
          h.offerInjuryHealing = false;
        });
      }

      console.log(
        `[HOSPITAL MAINT] Auto-disabled Injury Healing on ${hospitalsToDisable.length} hospital(s).`
      );

      // Notify affected owners (deduplicated)
      const notifiedOwners = new Set();
      for (const item of hospitalsToDisable) {
        if (notifiedOwners.has(item.ownerEmail)) continue;
        notifiedOwners.add(item.ownerEmail);

        const socket = this.onlineSockets.get(item.displayName);
        if (socket) {
          socket.emit('error', {
            message:
              "Injury Healing has been automatically disabled on one or more of your hospitals because you don't have enough money for the maintenance fee(s)."
          });
        }
      }
    }
  }
}

const maintenanceService = new MaintenanceService();

module.exports = {
  MaintenanceService,
  maintenanceService
};
