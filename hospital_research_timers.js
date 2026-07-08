const admin = require('firebase-admin');
const { getEarliestResearchEndTime, getAllHospitalOwnership } = require('./hospital_research');

// ==================== HOSPITAL RESEARCH TIMERS (Improved Version) ====================
// Uses precise per-research timers instead of polling.
// Includes retry logic + force completion to protect player progress.

const activeResearchTimers = new Map();

const RESEARCH_TYPES = {
  EFFICIENT_DOCTORS: 'efficient-doctors',
  ENHANCED_STAMINA: 'enhanced-stamina',
  ENHANCED_CONSTITUTION: 'enhanced-constitution'
};

const MAX_RETRIES = 5;

/**
 * Attempts to complete a research.
 * If force = true, it will complete the research even if the timer has already been cleared.
 */
async function attemptResearchCompletion(db, hospitalDocId, researchType, io, force = false) {
  const hospitalRef = db.collection('hospitals').doc(hospitalDocId);

  await db.runTransaction(async (transaction) => {
    const hospitalDoc = await transaction.get(hospitalRef);
    if (!hospitalDoc.exists) {
      throw new Error('Hospital no longer exists');
    }

    const h = hospitalDoc.data();
    let updates = {};
    let researchName = '';

    const endTimeStillActive =
      (researchType === RESEARCH_TYPES.EFFICIENT_DOCTORS && h.efficientDoctorsResearchEndTime > 0) ||
      (researchType === RESEARCH_TYPES.ENHANCED_STAMINA && h.enhancedStaminaResearchEndTime > 0) ||
      (researchType === RESEARCH_TYPES.ENHANCED_CONSTITUTION && h.enhancedConstitutionResearchEndTime > 0);

    const shouldComplete = force || endTimeStillActive;

    if (!shouldComplete) {
      return; // Nothing to do
    }

    if (researchType === RESEARCH_TYPES.EFFICIENT_DOCTORS && !h.hasEfficientDoctors) {
      updates.hasEfficientDoctors = true;
      updates.efficientDoctorsResearchEndTime = 0;
      researchName = 'Efficient Doctors';
    } 
    else if (researchType === RESEARCH_TYPES.ENHANCED_STAMINA && !h.hasEnhancedStamina) {
      updates.hasEnhancedStamina = true;
      updates.enhancedStaminaResearchEndTime = 0;
      researchName = 'Enhanced Stamina';
    } 
    else if (researchType === RESEARCH_TYPES.ENHANCED_CONSTITUTION && !h.hasEnhancedConstitution) {
      updates.hasEnhancedConstitution = true;
      updates.enhancedConstitutionResearchEndTime = 0;
      researchName = 'Enhanced Constitution';
    }

    if (Object.keys(updates).length === 0) {
      return;
    }

    // === SUCCESS LOG MOVED INSIDE THE TRANSACTION ===
    // This only runs when we actually write something
    const newNextTime = getEarliestResearchEndTime({ ...h, ...updates });
    if (newNextTime) {
      updates.nextResearchEndTime = newNextTime;
    } else {
      updates.nextResearchEndTime = admin.firestore.FieldValue.delete();
    }

    transaction.update(hospitalRef, updates);
    console.log(`[RESEARCH COMPLETE] ${researchName} finished on ${hospitalDocId}`);
  });

  // Broadcast after successful transaction (this is fine to keep outside)
  const freshOwnership = await getAllHospitalOwnership(db.collection('hospitals'));
  (io.server || io).emit('hospital-ownership-update', freshOwnership);
}

/**
 * Schedules a research completion timer (initial or retry).
 */
function scheduleHospitalResearch(db, hospitalDocId, researchType, endTime, io, retryCount = 0) {
  const key = `${hospitalDocId}:${researchType}`;

  // Cancel any existing timer for this research
  if (activeResearchTimers.has(key)) {
    clearTimeout(activeResearchTimers.get(key));
  }

  const remainingMs = Math.max(0, endTime - Date.now());

  if (remainingMs === 0) {
    attemptResearchCompletion(db, hospitalDocId, researchType, io).catch(err => {
      console.error(`[RESEARCH TIMER] Immediate completion failed for ${key}:`, err.message);
    });
    return;
  }

  const timeoutId = setTimeout(async () => {
    try {
      await attemptResearchCompletion(db, hospitalDocId, researchType, io);
      activeResearchTimers.delete(key);
    } catch (err) {
      console.error(`[RESEARCH TIMER ERROR] Attempt ${retryCount + 1} failed for ${key}:`, err.message);

      if (retryCount < MAX_RETRIES) {
        const delayMs = 1000 * (retryCount + 1);
        console.log(`[RESEARCH TIMER] Retrying ${researchType} on ${hospitalDocId} in ${delayMs / 1000}s`);

        scheduleHospitalResearch(db, hospitalDocId, researchType, Date.now() + delayMs, io, retryCount + 1);
      } else {
        console.error(`[CRITICAL] Research ${researchType} on hospital ${hospitalDocId} failed after max retries. Attempting final force completion...`);

        activeResearchTimers.delete(key);

        // Final attempt with force = true to protect player progress
        attemptResearchCompletion(db, hospitalDocId, researchType, io, true)
          .catch(finalErr => {
            console.error(`[RESEARCH TIMER] Final force completion also failed for ${researchType} on ${hospitalDocId}.`, finalErr);
          });
      }
    }
  }, remainingMs);

  activeResearchTimers.set(key, timeoutId);
  console.log(`[RESEARCH TIMER] Scheduled ${researchType} for ${hospitalDocId} (attempt ${retryCount + 1})`);
}

/**
 * Cancels all timers for a specific hospital.
 */
function cancelHospitalResearchTimers(hospitalDocId) {
  let cancelled = 0;
  for (const [key, timeoutId] of activeResearchTimers) {
    if (key.startsWith(hospitalDocId)) {
      clearTimeout(timeoutId);
      activeResearchTimers.delete(key);
      cancelled++;
    }
  }
  if (cancelled > 0) {
    console.log(`[RESEARCH TIMER] Cancelled ${cancelled} timer(s) for ${hospitalDocId}`);
  }
}

/**
 * Called on server startup to restore or complete active researches.
 */
async function catchUpActiveHospitalResearches(db, io) {
  console.log('[RESEARCH TIMER] Starting catch-up for researches after server restart...');

  const snapshot = await db.collection('hospitals')
    .where('nextResearchEndTime', '>', 0)
    .get();

  let scheduledCount = 0;
  let completedCount = 0;

  for (const doc of snapshot.docs) {
    const h = doc.data();
    const id = doc.id;
    const now = Date.now();

    const researches = [
      { type: RESEARCH_TYPES.EFFICIENT_DOCTORS, endTime: h.efficientDoctorsResearchEndTime },
      { type: RESEARCH_TYPES.ENHANCED_STAMINA, endTime: h.enhancedStaminaResearchEndTime },
      { type: RESEARCH_TYPES.ENHANCED_CONSTITUTION, endTime: h.enhancedConstitutionResearchEndTime }
    ];

    for (const research of researches) {
      if (research.endTime > 0) {
        if (research.endTime > now) {
          scheduleHospitalResearch(db, id, research.type, research.endTime, io);
          scheduledCount++;
        } else {
          await attemptResearchCompletion(db, id, research.type, io).catch(() => {});
          completedCount++;
        }
      }
    }
  }

  console.log(`[RESEARCH TIMER] Catch-up finished. Rescheduled ${scheduledCount} future researches. Completed ${completedCount} overdue researches.`);
}

module.exports = {
  scheduleHospitalResearch,
  cancelHospitalResearchTimers,
  catchUpActiveHospitalResearches,
  RESEARCH_TYPES,
  attemptResearchCompletion
};