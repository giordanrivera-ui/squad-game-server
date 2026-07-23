/**
 * ResearchService – start / complete / catch-up for the three hospital researches.
 * Mechanics identical to original: $1000, 30 s, same fields, same messages.
 *
 * Improvements:
 *  1. Money debit + research start are atomic (one transaction).
 *  2. Completion always goes through HospitalRepository (no cache bypass).
 */

const admin = require('firebase-admin');
const {
  EFFICIENT_DOCTORS_RESEARCH,
  ENHANCED_STAMINA_RESEARCH,
  ENHANCED_CONSTITUTION_RESEARCH
} = require('../../hospital_constants');
const { hospitalRepository } = require('./HospitalRepository');
const { timerService } = require('./TimerService');

const RESEARCH_TYPES = {
  EFFICIENT_DOCTORS: 'efficient-doctors',
  ENHANCED_STAMINA: 'enhanced-stamina',
  ENHANCED_CONSTITUTION: 'enhanced-constitution'
};

const RESEARCH_CONFIG = {
  [RESEARCH_TYPES.EFFICIENT_DOCTORS]: {
    config: EFFICIENT_DOCTORS_RESEARCH,
    hasField: 'hasEfficientDoctors',
    endTimeField: 'efficientDoctorsResearchEndTime',
    name: 'Efficient Doctors'
  },
  [RESEARCH_TYPES.ENHANCED_STAMINA]: {
    config: ENHANCED_STAMINA_RESEARCH,
    hasField: 'hasEnhancedStamina',
    endTimeField: 'enhancedStaminaResearchEndTime',
    name: 'Enhanced Stamina'
  },
  [RESEARCH_TYPES.ENHANCED_CONSTITUTION]: {
    config: ENHANCED_CONSTITUTION_RESEARCH,
    hasField: 'hasEnhancedConstitution',
    endTimeField: 'enhancedConstitutionResearchEndTime',
    name: 'Enhanced Constitution'
  }
};

class ResearchService {
  /**
   * Start any of the three researches.
   * researchType must be one of RESEARCH_TYPES values.
   */
  async startResearch(db, socket, hospitalDocId, researchType) {
    const email = socket.data.email;
    if (!email || !hospitalDocId) {
      socket.emit('research-result', { success: false, message: 'Invalid request.' });
      return;
    }

    const meta = RESEARCH_CONFIG[researchType];
    if (!meta) {
      socket.emit('research-result', { success: false, message: 'Unknown research type.' });
      return;
    }

    // Fast-fail checks (cheap, outside transaction)
    const hospital = hospitalRepository.get(hospitalDocId);
    if (!hospital) {
      socket.emit('research-result', { success: false, message: 'Hospital not found.' });
      return;
    }
    if (!hospital.isOwnedBy(email)) {
      socket.emit('research-result', { success: false, message: 'You do not own this hospital.' });
      return;
    }
    if (hospital[meta.hasField] === true) {
      socket.emit('research-result', {
        success: false,
        message: `${meta.name} already researched.`
      });
      return;
    }
    if (hospital.isResearchInProgress(meta.endTimeField)) {
      socket.emit('research-result', { success: false, message: 'Research already in progress.' });
      return;
    }

    try {
      const playerRef = db.collection('players').doc(email);
      const hospitalRef = hospitalRepository.collectionRef.doc(hospitalDocId);
      const completionTime = Date.now() + meta.config.durationMs;
      let newBalanceAfter = null;

      // ---------- ATOMIC: money debit + hospital research start ----------
      await db.runTransaction(async (transaction) => {
        // Re-validate inside the transaction (closes races)
        const playerSnap = await transaction.get(playerRef);
        if (!playerSnap.exists) throw new Error('Player not found');

        const player = playerSnap.data();
        if ((player.balance || 0) < meta.config.cost) {
          throw new Error('Not enough money');
        }

        const hospitalSnap = await transaction.get(hospitalRef);
        if (!hospitalSnap.exists) throw new Error('Hospital not found');

        const hospitalData = hospitalSnap.data();
        if (hospitalData.ownerEmail !== email) throw new Error('Not owner');
        if (hospitalData[meta.hasField] === true) throw new Error('Already researched');
        if (hospitalData[meta.endTimeField] > Date.now()) throw new Error('Already in progress');

        // All good → write both sides atomically
        newBalanceAfter = (player.balance || 0) - meta.config.cost;

        transaction.update(playerRef, {
          balance: admin.firestore.FieldValue.increment(-meta.config.cost)
        });

        // Research start on hospital
        const hospitalUpdates = {
          [meta.endTimeField]: completionTime
        };

        // nextResearchEndTime (include the new end time we are writing)
        const otherTimes = [
          hospitalData.efficientDoctorsResearchEndTime,
          hospitalData.enhancedStaminaResearchEndTime,
          hospitalData.enhancedConstitutionResearchEndTime
        ].filter(t => typeof t === 'number' && t > 0);

        otherTimes.push(completionTime);
        hospitalUpdates.nextResearchEndTime = Math.min(...otherTimes);

        transaction.update(hospitalRef, hospitalUpdates);

        // Transaction log (same atomic unit)
        const txRef = playerRef.collection('transactions').doc();
        transaction.set(txRef, {
          amount: -meta.config.cost,
          description: `Researched: ${meta.name}`,
          balanceAfter: newBalanceAfter,
          timestamp: admin.firestore.FieldValue.serverTimestamp()
        });
      });

      // ---------- Only after the transaction succeeded ----------

      // Keep in-memory cache in sync (no second write)
      const cachedHospital = hospitalRepository.get(hospitalDocId);
      if (cachedHospital) {
        cachedHospital[meta.endTimeField] = completionTime;
        cachedHospital.recalculateNextResearchEndTime();
      }
      hospitalRepository.broadcast();

      // Schedule precise timer
      const timerKey = `${hospitalDocId}:${researchType}`;
      timerService.schedule(timerKey, completionTime, async ({ force }) => {
        await this._completeResearch(hospitalDocId, researchType, force);
      });

      // Notify client
      const freshPlayer = await playerRef.get();
      socket.emit('update-stats', freshPlayer.data());
      socket.emit('new-transaction', {
        amount: -meta.config.cost,
        description: `Researched: ${meta.name}`,
        balanceAfter: newBalanceAfter
      });
      socket.emit('research-result', {
        success: true,
        message: `🔬 Researching ${meta.name}... (${meta.config.durationMs / 1000} seconds)`
      });

      console.log(`[HOSPITAL RESEARCH] ${email} started ${meta.name} research on ${hospitalDocId}`);
    } catch (error) {
      console.error('[RESEARCH ERROR]', error);

      let message = 'Something went wrong while starting research. Please try again.';
      if (error.message === 'Not enough money') {
        message = 'Not enough money ($1000 required).';
      } else if (error.message === 'Already researched') {
        message = `${meta.name} already researched.`;
      } else if (error.message === 'Already in progress') {
        message = 'Research already in progress.';
      } else if (error.message === 'Not owner') {
        message = 'You do not own this hospital.';
      }

      socket.emit('research-result', { success: false, message });
    }
  }

  /**
   * Internal completion – always goes through the repository.
   * Uses updateWithTransaction so cache + broadcast stay consistent.
   */
  async _completeResearch(hospitalDocId, researchType, force = false) {
    const meta = RESEARCH_CONFIG[researchType];
    if (!meta) return;

    const applied = await hospitalRepository.updateWithTransaction(
      hospitalDocId,
      (transaction, data) => {
        const endTimeStillActive = data[meta.endTimeField] > 0;
        const shouldComplete = force || endTimeStillActive;

        if (!shouldComplete) return null;
        if (data[meta.hasField] === true) return null; // already done

        const updates = {
          [meta.hasField]: true,
          [meta.endTimeField]: 0
        };

        // Recalculate nextResearchEndTime from the other two researches
        const otherTimes = [];
        if (researchType !== RESEARCH_TYPES.EFFICIENT_DOCTORS && data.efficientDoctorsResearchEndTime > 0) {
          otherTimes.push(data.efficientDoctorsResearchEndTime);
        }
        if (researchType !== RESEARCH_TYPES.ENHANCED_STAMINA && data.enhancedStaminaResearchEndTime > 0) {
          otherTimes.push(data.enhancedStaminaResearchEndTime);
        }
        if (researchType !== RESEARCH_TYPES.ENHANCED_CONSTITUTION && data.enhancedConstitutionResearchEndTime > 0) {
          otherTimes.push(data.enhancedConstitutionResearchEndTime);
        }

        if (otherTimes.length > 0) {
          updates.nextResearchEndTime = Math.min(...otherTimes);
        } else {
          updates.nextResearchEndTime = admin.firestore.FieldValue.delete();
        }

        return updates;
      }
    );

    if (applied) {
      console.log(`[RESEARCH COMPLETE] ${meta.name} finished on ${hospitalDocId}`);
    }
  }

  /**
   * Manual claim (kept for exact original behaviour / fallback).
   * If the research is already finished by the timer, emit a friendly message.
   */
  async claimResearch(db, socket, hospitalDocId, researchType) {
    const email = socket.data.email;
    if (!email || !hospitalDocId) return;

    const meta = RESEARCH_CONFIG[researchType];
    if (!meta) return;

    const hospital = hospitalRepository.get(hospitalDocId);
    if (!hospital || !hospital.isOwnedBy(email)) return;

    // Already finished by timer?
    if (hospital[meta.hasField] === true) {
      timerService.cancel(`${hospitalDocId}:${researchType}`);
      socket.emit('research-result', {
        success: true,
        message: `✅ ${meta.name} research already completed automatically!`
      });
      return;
    }

    // Still in progress?
    if (!hospital[meta.endTimeField] || hospital[meta.endTimeField] > Date.now()) {
      return;
    }

    // Time is up → complete
    await this._completeResearch(hospitalDocId, researchType, false);

    socket.emit('research-result', {
      success: true,
      message: researchType === RESEARCH_TYPES.EFFICIENT_DOCTORS
        ? '✅ Efficient Doctors research complete! Minimum healing time is now 2:00.'
        : `✅ ${meta.name} research complete!`
    });
  }

  /**
   * Startup catch-up: complete any overdue researches and re-schedule future ones.
   */
  async catchUpAll(db, io) {
    console.log('[RESEARCH] Starting catch-up for researches after server restart...');

    if (hospitalRepository.cache.size === 0) {
      await hospitalRepository.initialize(db, io);
    }

    let scheduledCount = 0;
    let completedCount = 0;
    const now = Date.now();

    for (const [id, hospital] of hospitalRepository.cache) {
      const researches = [
        { type: RESEARCH_TYPES.EFFICIENT_DOCTORS, endTime: hospital.efficientDoctorsResearchEndTime },
        { type: RESEARCH_TYPES.ENHANCED_STAMINA, endTime: hospital.enhancedStaminaResearchEndTime },
        { type: RESEARCH_TYPES.ENHANCED_CONSTITUTION, endTime: hospital.enhancedConstitutionResearchEndTime }
      ];

      for (const r of researches) {
        if (r.endTime > 0) {
          if (r.endTime > now) {
            const timerKey = `${id}:${r.type}`;
            timerService.schedule(timerKey, r.endTime, async ({ force }) => {
              await this._completeResearch(id, r.type, force);
            });
            scheduledCount++;
          } else {
            await this._completeResearch(id, r.type, false).catch(() => {});
            completedCount++;
          }
        }
      }
    }

    console.log(
      `[RESEARCH] Catch-up finished. Rescheduled ${scheduledCount} future researches. ` +
      `Completed ${completedCount} overdue researches.`
    );
  }

  // Convenience wrappers that match the original function signatures
  async startEfficientDoctors(db, socket, hospitalDocId) {
    return this.startResearch(db, socket, hospitalDocId, RESEARCH_TYPES.EFFICIENT_DOCTORS);
  }

  async startEnhancedStamina(db, socket, hospitalDocId) {
    return this.startResearch(db, socket, hospitalDocId, RESEARCH_TYPES.ENHANCED_STAMINA);
  }

  async startEnhancedConstitution(db, socket, hospitalDocId) {
    return this.startResearch(db, socket, hospitalDocId, RESEARCH_TYPES.ENHANCED_CONSTITUTION);
  }

  async claimEfficientDoctors(db, socket, hospitalDocId) {
    return this.claimResearch(db, socket, hospitalDocId, RESEARCH_TYPES.EFFICIENT_DOCTORS);
  }

  async claimEnhancedStamina(db, socket, hospitalDocId) {
    return this.claimResearch(db, socket, hospitalDocId, RESEARCH_TYPES.ENHANCED_STAMINA);
  }

  async claimEnhancedConstitution(db, socket, hospitalDocId) {
    return this.claimResearch(db, socket, hospitalDocId, RESEARCH_TYPES.ENHANCED_CONSTITUTION);
  }
}

const researchService = new ResearchService();

module.exports = {
  ResearchService,
  researchService,
  RESEARCH_TYPES
};