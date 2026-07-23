/**
 * Thin compatibility shim.
 * All timer logic now lives in hospital/services/TimerService.js
 * and ResearchService.
 */

const { timerService } = require('./hospital/services/TimerService');
const { researchService, RESEARCH_TYPES } = require('./hospital/services/ResearchService');

function scheduleHospitalResearch(db, hospitalDocId, researchType, endTime, io, retryCount = 0) {
  const key = `${hospitalDocId}:${researchType}`;
  timerService.schedule(key, endTime, async ({ force }) => {
    // The researchService completion is already wired when startResearch is called.
    // This shim exists only for any external callers of the old API.
  }, retryCount);
}

function cancelHospitalResearchTimers(hospitalDocId) {
  timerService.cancelAllForHospital(hospitalDocId);
}

async function catchUpActiveHospitalResearches(db, io) {
  return researchService.catchUpAll(db, io);
}

async function attemptResearchCompletion() {
  // no-op in new system
}

module.exports = {
  scheduleHospitalResearch,
  cancelHospitalResearchTimers,
  catchUpActiveHospitalResearches,
  RESEARCH_TYPES,
  attemptResearchCompletion
};