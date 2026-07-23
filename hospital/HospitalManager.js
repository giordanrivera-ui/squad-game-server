/**
 * HospitalManager – single public façade used by the rest of the server.
 * All original mechanics are preserved; this class simply wires the services.
 */

const { hospitalCounts } = require('../hospital_constants');
const { hospitalRepository } = require('./services/HospitalRepository');
const { researchService } = require('./services/ResearchService');
const { healingService } = require('./services/HealingService');
const { ownershipService } = require('./services/OwnershipService');
const { maintenanceService } = require('./services/MaintenanceService');
const { timerService } = require('./services/TimerService');

class HospitalManager {
  /**
   * Initialise the in-memory cache and ensure all hospital documents exist.
   * Called once from server startup.
   */
  async initialize(db, io) {
    // Ensure every hospital document exists (exact original logic)
    for (const [location, count] of Object.entries(hospitalCounts)) {
      for (let i = 1; i <= count; i++) {
        const docId = `${location}-hospital-${i}`;
        const existing = hospitalRepository.get(docId);
        if (!existing) {
          // We need the collection to be ready; initialize will load existing ones
          // so we create missing ones after the load.
        }
      }
    }

    await hospitalRepository.initialize(db, io);

    // Create any that are still missing
    for (const [location, count] of Object.entries(hospitalCounts)) {
      for (let i = 1; i <= count; i++) {
        const docId = `${location}-hospital-${i}`;
        if (!hospitalRepository.get(docId)) {
          await hospitalRepository.createIfMissing(docId, {
            location,
            index: i,
            isPublic: i === 1,
            ownerEmail: null,
            ownerDisplayName: null,
            createdAt: Date.now()
          });
        }
      }
    }

    console.log(`[HOSPITAL MANAGER] Initialised ${hospitalRepository.cache.size} hospitals`);
  }

  // ---------- Ownership ----------
  claimHospital(socket, data) {
    return ownershipService.claimHospital(socket, data);
  }

  releaseHospital(socket, data) {
    return ownershipService.releaseHospital(socket, data);
  }

  updateHospitalService(socket, data, deps) {
    return ownershipService.updateHospitalService(socket, data, deps);
  }

  updateHealCost(socket, data) {
    return ownershipService.updateHealCost(socket, data);
  }

  updateHealingDuration(socket, data) {
    return ownershipService.updateHealingDuration(socket, data);
  }

  updateStaminaCost(socket, data) {
    return ownershipService.updateStaminaCost(socket, data);
  }

  updateConstitutionCost(socket, data) {
    return ownershipService.updateConstitutionCost(socket, data);
  }

  setSelectedEpinephrineQuality(socket, data) {
    return ownershipService.setSelectedEpinephrineQuality(socket, data);
  }

  // ---------- Healing ----------
  startPublicHealing(db, socket) {
    return healingService.startPublicHealing(db, socket);
  }

  claimPublicHealing(db, socket) {
    return healingService.claimPublicHealing(db, socket);
  }

  watchAdForFasterHealing(db, socket) {
    return healingService.watchAdForFasterHealing(db, socket);
  }

  healBrokenBone(db, socket) {
    return healingService.healBrokenBone(db, socket);
  }

  startPrivateHealing(db, socket, data, deps) {
    return healingService.startPrivateHealing(db, socket, data, deps);
  }

  claimPrivateHealing(db, socket) {
    return healingService.claimPrivateHealing(db, socket);
  }

  purchaseEnhancedStamina(db, socket, data, deps) {
    return healingService.purchaseEnhancedStamina(db, socket, data, deps);
  }

  // ---------- Research ----------
  startEfficientDoctorsResearch(db, socket, hospitalDocId) {
    return researchService.startEfficientDoctors(db, socket, hospitalDocId);
  }

  claimEfficientDoctorsResearch(db, socket, hospitalDocId) {
    return researchService.claimEfficientDoctors(db, socket, hospitalDocId);
  }

  startEnhancedStaminaResearch(db, socket, hospitalDocId) {
    return researchService.startEnhancedStamina(db, socket, hospitalDocId);
  }

  claimEnhancedStaminaResearch(db, socket, hospitalDocId) {
    return researchService.claimEnhancedStamina(db, socket, hospitalDocId);
  }

  startEnhancedConstitutionResearch(db, socket, hospitalDocId) {
    return researchService.startEnhancedConstitution(db, socket, hospitalDocId);
  }

  claimEnhancedConstitutionResearch(db, socket, hospitalDocId) {
    return researchService.claimEnhancedConstitution(db, socket, hospitalDocId);
  }

  catchUpAllResearches(db, io) {
    return researchService.catchUpAll(db, io);
  }

  // ---------- Maintenance ----------
  startMaintenanceChecker(db, deps) {
    return maintenanceService.start(db, deps);
  }

  // ---------- Helpers used by old API ----------
  getAllOwnership() {
    return hospitalRepository.getAllOwnership();
  }

  calculateMaintenanceFee(healingDurationMs) {
    // For backward-compat export – create a temporary hospital-like object
    const temp = {
      customHealingDuration: healingDurationMs || 240000,
      calculateMaintenanceFee() {
        const durationSec = Math.round((this.customHealingDuration || 240000) / 1000);
        if (durationSec >= 240) return 10;
        let fee = 10;
        if (durationSec < 240) {
          const reductionsTier1 = Math.floor((240 - durationSec) / 20);
          fee += Math.min(reductionsTier1, 3) * 4;
        }
        if (durationSec < 180) {
          const reductionsTier2 = Math.floor((180 - durationSec) / 20);
          fee += reductionsTier2 * 5;
        }
        return fee;
      }
    };
    return temp.calculateMaintenanceFee();
  }
}

const hospitalManager = new HospitalManager();

module.exports = {
  HospitalManager,
  hospitalManager
};
