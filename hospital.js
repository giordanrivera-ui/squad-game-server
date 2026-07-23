/**
 * hospital.js – public entry point.
 * Re-exports the exact same API that the original hospital.js exposed so
 * server.js (and any other consumers) continue to work without changes.
 *
 * Internally everything is routed through the new modular HospitalManager.
 */

const {
  ENHANCED_STAMINA_RESEARCH,
  ENHANCED_CONSTITUTION_RESEARCH,
  EFFICIENT_DOCTORS_RESEARCH
} = require('./hospital_constants');

const { hospitalManager } = require('./hospital/HospitalManager');
const { hospitalRepository } = require('./hospital/services/HospitalRepository');

// ---------------------------------------------------------------------------
// Backward-compatible function exports (exact original signatures)
// ---------------------------------------------------------------------------

async function handleStartHealing(db, socket) {
  return hospitalManager.startPublicHealing(db, socket);
}

async function handleClaimHealing(db, socket) {
  return hospitalManager.claimPublicHealing(db, socket);
}

async function handleWatchAdForFasterHealing(db, socket) {
  return hospitalManager.watchAdForFasterHealing(db, socket);
}

async function handleHealBrokenBone(db, socket) {
  return hospitalManager.healBrokenBone(db, socket);
}

async function handleClaimHospital(socket, data, _deps) {
  return hospitalManager.claimHospital(socket, data);
}

async function handleReleaseHospital(socket, data, _deps) {
  return hospitalManager.releaseHospital(socket, data);
}

async function handleUpdateHospitalService(socket, data, deps) {
  return hospitalManager.updateHospitalService(socket, data, deps);
}

async function handleStartPrivateHealing(db, socket, data, deps) {
  return hospitalManager.startPrivateHealing(db, socket, data, deps);
}

async function handleClaimPrivateHealing(db, socket) {
  return hospitalManager.claimPrivateHealing(db, socket);
}

async function handleUpdateHospitalHealCost(socket, data, _deps) {
  return hospitalManager.updateHealCost(socket, data);
}

async function handleUpdateHospitalHealingDuration(socket, data, _deps) {
  return hospitalManager.updateHealingDuration(socket, data);
}

async function handleUpdateHospitalStaminaCost(socket, data, _deps) {
  return hospitalManager.updateStaminaCost(socket, data);
}

async function handleUpdateHospitalConstitutionCost(socket, data, _deps) {
  return hospitalManager.updateConstitutionCost(socket, data);
}

async function handlePurchaseEnhancedStamina(db, socket, data, deps) {
  return hospitalManager.purchaseEnhancedStamina(db, socket, data, deps);
}

async function handleSetSelectedEpinephrineQuality(socket, data, _deps) {
  return hospitalManager.setSelectedEpinephrineQuality(socket, data);
}

async function handleStartEfficientDoctorsResearch(db, socket, hospitalDocId) {
  return hospitalManager.startEfficientDoctorsResearch(db, socket, hospitalDocId);
}

async function handleClaimEfficientDoctorsResearch(db, socket, hospitalDocId) {
  return hospitalManager.claimEfficientDoctorsResearch(db, socket, hospitalDocId);
}

async function handleStartPerformanceResearch(db, socket, hospitalDocId, researchConfig, hasField, endTimeField, researchName) {
  // Map the old generic call to the new typed methods
  if (endTimeField === 'enhancedStaminaResearchEndTime') {
    return hospitalManager.startEnhancedStaminaResearch(db, socket, hospitalDocId);
  }
  if (endTimeField === 'enhancedConstitutionResearchEndTime') {
    return hospitalManager.startEnhancedConstitutionResearch(db, socket, hospitalDocId);
  }
  console.error(`[HOSPITAL] Unknown performance research: ${researchName}`);
}

async function handleClaimPerformanceResearch(db, socket, hospitalDocId, hasField, endTimeField, researchName) {
  if (endTimeField === 'enhancedStaminaResearchEndTime') {
    return hospitalManager.claimEnhancedStaminaResearch(db, socket, hospitalDocId);
  }
  if (endTimeField === 'enhancedConstitutionResearchEndTime') {
    return hospitalManager.claimEnhancedConstitutionResearch(db, socket, hospitalDocId);
  }
}

function startHospitalMaintenanceChecker(db, deps) {
  return hospitalManager.startMaintenanceChecker(db, deps);
}

function calculateMaintenanceFee(healingDurationMs) {
  return hospitalManager.calculateMaintenanceFee(healingDurationMs);
}

// Catch-up helpers (kept for any external callers; the real work is in catchUpAll)
async function catchUpEfficientDoctorsResearch(db, { io }) {
  // No-op – handled by the unified catch-up
}
async function catchUpPerformanceResearches(db, { io }) {
  // No-op – handled by the unified catch-up
}

/**
 * registerHospitalHandlers – exact same socket event surface as original.
 */
function registerHospitalHandlers(socket, deps) {
  const {
    db,
    hospitalOwnershipRef, // kept for signature compatibility (unused internally)
    onlineSockets,
    ENHANCED_STAMINA_RESEARCH: _esr,
    ENHANCED_CONSTITUTION_RESEARCH: _ecr
  } = deps;

  socket.on('heal-broken-bone', async () => {
    await hospitalManager.healBrokenBone(db, socket);
  });

  socket.on('start-healing', async () => {
    await hospitalManager.startPublicHealing(db, socket);
  });

  socket.on('watch-ad-for-faster-healing', async () => {
    await hospitalManager.watchAdForFasterHealing(db, socket);
  });

  socket.on('claim-healing', async () => {
    await hospitalManager.claimPublicHealing(db, socket);
  });

  socket.on('claim-hospital', (data) => {
    hospitalManager.claimHospital(socket, data);
  });

  socket.on('release-hospital', (data) => {
    hospitalManager.releaseHospital(socket, data);
  });

  socket.on('update-hospital-service', (data) => {
    hospitalManager.updateHospitalService(socket, data, { hospitalOwnershipRef, db });
  });

  socket.on('start-private-healing', async (data) => {
    await hospitalManager.startPrivateHealing(db, socket, data, { onlineSockets });
  });

  socket.on('claim-private-healing', async () => {
    await hospitalManager.claimPrivateHealing(db, socket);
  });

  socket.on('update-hospital-heal-cost', (data) => {
    hospitalManager.updateHealCost(socket, data);
  });

  socket.on('update-hospital-healing-duration', (data) => {
    hospitalManager.updateHealingDuration(socket, data);
  });

  socket.on('start-efficient-doctors-research', async (data) => {
    await hospitalManager.startEfficientDoctorsResearch(db, socket, data.hospitalDocId);
  });

  socket.on('claim-efficient-doctors-research', async (data) => {
    await hospitalManager.claimEfficientDoctorsResearch(db, socket, data.hospitalDocId);
  });

  socket.on('start-enhanced-stamina-research', async (data) => {
    await hospitalManager.startEnhancedStaminaResearch(db, socket, data.hospitalDocId);
  });

  socket.on('claim-enhanced-stamina-research', async (data) => {
    await hospitalManager.claimEnhancedStaminaResearch(db, socket, data.hospitalDocId);
  });

  socket.on('start-enhanced-constitution-research', async (data) => {
    await hospitalManager.startEnhancedConstitutionResearch(db, socket, data.hospitalDocId);
  });

  socket.on('claim-enhanced-constitution-research', async (data) => {
    await hospitalManager.claimEnhancedConstitutionResearch(db, socket, data.hospitalDocId);
  });

  socket.on('update-hospital-stamina-cost', (data) => {
    hospitalManager.updateStaminaCost(socket, data);
  });

  socket.on('update-hospital-constitution-cost', (data) => {
    hospitalManager.updateConstitutionCost(socket, data);
  });

  socket.on('purchase-enhanced-stamina', async (data) => {
    await hospitalManager.purchaseEnhancedStamina(db, socket, data, { onlineSockets });
  });

  socket.on('set-selected-epinephrine-quality', (data) => {
    hospitalManager.setSelectedEpinephrineQuality(socket, data);
  });
}

/**
 * One-time startup helper that replaces the old initializeHospitals + catch-up calls.
 * Call this from server.js after Firebase is ready and before accepting connections.
 */
async function initializeHospitalSystem(db, io) {
  await hospitalManager.initialize(db, io);
  await hospitalManager.catchUpAllResearches(db, io);
}

// ---------------------------------------------------------------------------
// Exports – identical surface to the original hospital.js
// ---------------------------------------------------------------------------
module.exports = {
  // Core handlers
  handleStartHealing,
  handleClaimHealing,
  handleHealBrokenBone,
  handleClaimHospital,
  handleReleaseHospital,
  handleUpdateHospitalService,
  startHospitalMaintenanceChecker,
  handleStartPrivateHealing,
  handleClaimPrivateHealing,
  handleUpdateHospitalHealCost,
  handleWatchAdForFasterHealing,
  handleUpdateHospitalHealingDuration,
  handleStartEfficientDoctorsResearch,
  handleClaimEfficientDoctorsResearch,
  catchUpEfficientDoctorsResearch,
  calculateMaintenanceFee,
  handleStartPerformanceResearch,
  handleClaimPerformanceResearch,
  catchUpPerformanceResearches,
  handleUpdateHospitalStaminaCost,
  handleUpdateHospitalConstitutionCost,
  handlePurchaseEnhancedStamina,
  handleSetSelectedEpinephrineQuality,

  // Constants re-exported for consumers that imported them from hospital.js
  ENHANCED_STAMINA_RESEARCH,
  ENHANCED_CONSTITUTION_RESEARCH,
  EFFICIENT_DOCTORS_RESEARCH,

  // Registration
  registerHospitalHandlers,

  // New (optional) unified init – preferred over the old scattered calls
  initializeHospitalSystem,

  // Internal access if needed
  hospitalManager,
  hospitalRepository,

  getAllHospitalOwnership: () => hospitalRepository.getAllOwnership(),
};
