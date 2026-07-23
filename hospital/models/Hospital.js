/**
 * Hospital model – pure data + behaviour helpers.
 * Mirrors every field and rule from the original system exactly.
 */

const {
  DEFAULT_PRIVATE_HEAL_COST,
  DEFAULT_PRIVATE_HEAL_DURATION_MS,
  DEFAULT_STAMINA_COST,
  DEFAULT_CONSTITUTION_COST,
  MIN_HEAL_DURATION_NO_RESEARCH_MS,
  MIN_HEAL_DURATION_WITH_RESEARCH_MS,
  MAX_HEAL_DURATION_MS,
  BASE_MAINTENANCE_FEE
} = require('../../hospital_constants');

class Hospital {
  constructor(id, data = {}) {
    this.id = id;
    this.location = data.location || '';
    this.index = data.index || 1;
    this.isPublic = data.isPublic === true;

    // Ownership
    this.ownerEmail = data.ownerEmail || null;
    this.ownerDisplayName = data.ownerDisplayName || null;
    this.claimedAt = data.claimedAt || null;

    // Service toggles
    this.offerInjuryHealing = data.offerInjuryHealing === true;
    this.offerOrthopedicServices = data.offerOrthopedicServices === true;
    this.offerPerformanceTherapy = data.offerPerformanceTherapy === true;
    this.offerDiseaseTherapy = data.offerDiseaseTherapy === true;
    this.offerEnhancedStamina = data.offerEnhancedStamina === true;
    this.offerEnhancedConstitution = data.offerEnhancedConstitution === true;

    // Custom pricing / duration
    this.customHealCost = data.customHealCost ?? DEFAULT_PRIVATE_HEAL_COST;
    this.customHealingDuration = data.customHealingDuration ?? DEFAULT_PRIVATE_HEAL_DURATION_MS;
    this.customStaminaCost = data.customStaminaCost ?? DEFAULT_STAMINA_COST;
    this.customConstitutionCost = data.customConstitutionCost ?? DEFAULT_CONSTITUTION_COST;

    // Research state
    this.hasEfficientDoctors = data.hasEfficientDoctors === true;
    this.efficientDoctorsResearchEndTime = data.efficientDoctorsResearchEndTime || 0;
    this.hasEnhancedStamina = data.hasEnhancedStamina === true;
    this.enhancedStaminaResearchEndTime = data.enhancedStaminaResearchEndTime || 0;
    this.hasEnhancedConstitution = data.hasEnhancedConstitution === true;
    this.enhancedConstitutionResearchEndTime = data.enhancedConstitutionResearchEndTime || 0;
    this.nextResearchEndTime = data.nextResearchEndTime || 0;

    // Epinephrine selection for Enhanced Stamina service
    this.selectedEpinephrineQuality = data.selectedEpinephrineQuality ?? null;

    // Misc (kept for compatibility)
    this.createdAt = data.createdAt || Date.now();
  }

  /** Convert back to plain object suitable for Firestore / broadcast */
  toJSON() {
    return {
      location: this.location,
      index: this.index,
      isPublic: this.isPublic,
      ownerEmail: this.ownerEmail,
      ownerDisplayName: this.ownerDisplayName,
      claimedAt: this.claimedAt,
      offerInjuryHealing: this.offerInjuryHealing,
      offerOrthopedicServices: this.offerOrthopedicServices,
      offerPerformanceTherapy: this.offerPerformanceTherapy,
      offerDiseaseTherapy: this.offerDiseaseTherapy,
      offerEnhancedStamina: this.offerEnhancedStamina,
      offerEnhancedConstitution: this.offerEnhancedConstitution,
      customHealCost: this.customHealCost,
      customHealingDuration: this.customHealingDuration,
      customStaminaCost: this.customStaminaCost,
      customConstitutionCost: this.customConstitutionCost,
      hasEfficientDoctors: this.hasEfficientDoctors,
      efficientDoctorsResearchEndTime: this.efficientDoctorsResearchEndTime,
      hasEnhancedStamina: this.hasEnhancedStamina,
      enhancedStaminaResearchEndTime: this.enhancedStaminaResearchEndTime,
      hasEnhancedConstitution: this.hasEnhancedConstitution,
      enhancedConstitutionResearchEndTime: this.enhancedConstitutionResearchEndTime,
      nextResearchEndTime: this.nextResearchEndTime || null,
      selectedEpinephrineQuality: this.selectedEpinephrineQuality,
      createdAt: this.createdAt
    };
  }

  /** Exact original maintenance fee formula */
  calculateMaintenanceFee() {
    const durationSec = Math.round((this.customHealingDuration || DEFAULT_PRIVATE_HEAL_DURATION_MS) / 1000);

    if (durationSec >= 240) return BASE_MAINTENANCE_FEE;

    let fee = BASE_MAINTENANCE_FEE;

    // Tier 1 reductions (240s → 180s)
    if (durationSec < 240) {
      const reductionsTier1 = Math.floor((240 - durationSec) / 20);
      fee += Math.min(reductionsTier1, 3) * 4;
    }

    // Tier 2 reductions (below 180s)
    if (durationSec < 180) {
      const reductionsTier2 = Math.floor((180 - durationSec) / 20);
      fee += reductionsTier2 * 5;
    }

    return fee;
  }

  /** Min allowed healing duration based on Efficient Doctors research */
  getMinHealingDurationMs() {
    return this.hasEfficientDoctors
      ? MIN_HEAL_DURATION_WITH_RESEARCH_MS
      : MIN_HEAL_DURATION_NO_RESEARCH_MS;
  }

  /** Validate a proposed custom healing duration (exact original rules) */
  isValidHealingDuration(ms) {
    if (typeof ms !== 'number') return false;
    const min = this.getMinHealingDurationMs();
    return ms >= min && ms <= MAX_HEAL_DURATION_MS;
  }

  /** Recalculate nextResearchEndTime from the three possible end times */
  recalculateNextResearchEndTime() {
    const times = [
      this.efficientDoctorsResearchEndTime,
      this.enhancedStaminaResearchEndTime,
      this.enhancedConstitutionResearchEndTime
    ].filter(t => typeof t === 'number' && t > 0);

    this.nextResearchEndTime = times.length === 0 ? 0 : Math.min(...times);
    return this.nextResearchEndTime;
  }

  /** Apply claim defaults (exact original set of fields) */
  applyClaim(ownerEmail, ownerDisplayName) {
    this.ownerEmail = ownerEmail;
    this.ownerDisplayName = ownerDisplayName;
    this.claimedAt = Date.now();
    this.offerInjuryHealing = false;
    this.offerOrthopedicServices = false;
    this.offerPerformanceTherapy = false;
    this.offerDiseaseTherapy = false;
    this.customHealCost = DEFAULT_PRIVATE_HEAL_COST;
    this.customHealingDuration = DEFAULT_PRIVATE_HEAL_DURATION_MS;
    this.customStaminaCost = DEFAULT_STAMINA_COST;
    this.customConstitutionCost = DEFAULT_CONSTITUTION_COST;
    this.hasEfficientDoctors = false;
    this.efficientDoctorsResearchEndTime = 0;
    this.hasEnhancedStamina = false;
    this.enhancedStaminaResearchEndTime = 0;
    this.hasEnhancedConstitution = false;
    this.enhancedConstitutionResearchEndTime = 0;
    this.offerEnhancedStamina = false;
    this.offerEnhancedConstitution = false;
    this.selectedEpinephrineQuality = null;
    this.nextResearchEndTime = 0;
  }

  /** Apply release defaults (exact original) */
  applyRelease() {
    this.ownerEmail = null;
    this.ownerDisplayName = null;
    this.claimedAt = null;
    this.customHealCost = DEFAULT_PRIVATE_HEAL_COST;
    this.customHealingDuration = DEFAULT_PRIVATE_HEAL_DURATION_MS;
    this.customStaminaCost = DEFAULT_STAMINA_COST;
    this.customConstitutionCost = DEFAULT_CONSTITUTION_COST;
    this.hasEfficientDoctors = false;
    this.efficientDoctorsResearchEndTime = 0;
    this.hasEnhancedStamina = false;
    this.enhancedStaminaResearchEndTime = 0;
    this.hasEnhancedConstitution = false;
    this.enhancedConstitutionResearchEndTime = 0;
    this.offerEnhancedStamina = false;
    this.offerEnhancedConstitution = false;
    this.selectedEpinephrineQuality = null;
    this.nextResearchEndTime = 0;
    // Note: service toggles other than the performance ones are left as-is on release
    // (matching original which only reset the listed fields)
  }

  isOwnedBy(email) {
    return this.ownerEmail === email;
  }

  isResearchInProgress(endTimeField) {
    const t = this[endTimeField];
    return typeof t === 'number' && t > Date.now();
  }
}

module.exports = Hospital;
