// ==================== HOSPITAL RESEARCH CONSTANTS ====================

const EFFICIENT_DOCTORS_RESEARCH = {
  id: "efficient-doctors",
  name: "Efficient Doctors",
  cost: 1000,
  durationMs: 30000, // 30 seconds
  effect: "Unlocks 2:00 minimum healing duration with 20-second increments (2:00 → 4:00)"
};

const ENHANCED_STAMINA_RESEARCH = {
  id: "enhanced-stamina",
  name: "Enhanced Stamina",
  cost: 1000,
  durationMs: 30000, // 30 seconds
  effect: "Unlocks enhanced stamina therapy options for patients."
};

const ENHANCED_CONSTITUTION_RESEARCH = {
  id: "enhanced-constitution",
  name: "Enhanced Constitution",
  cost: 1000,
  durationMs: 30000, // 30 seconds
  effect: "Unlocks enhanced constitution therapy options for patients."
};

// ==================== HOSPITAL SERVICE CONFIG ====================
const ALLOWED_HOSPITAL_SERVICE_FIELDS = [
  'offerInjuryHealing', 
  'offerOrthopedicServices', 
  'offerPerformanceTherapy', 
  'offerDiseaseTherapy',
  'offerEnhancedStamina',
  'offerEnhancedConstitution'
];

module.exports = {
  EFFICIENT_DOCTORS_RESEARCH,
  ENHANCED_STAMINA_RESEARCH,
  ENHANCED_CONSTITUTION_RESEARCH,
  ALLOWED_HOSPITAL_SERVICE_FIELDS
};