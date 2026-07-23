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

const hospitalCounts = {
  "Riverstone": 1,
  "Thornbury": 1,
  "Vostokgrad": 1,
  "Eichenwald": 1,
  "Montclair": 1,
  "Valleora": 1,
  "Lónghǎi": 2,
  "Sakuragawa": 2,
  "Cawayan Heights": 1
};

// ==================== HEALING / FEE CONSTANTS (exact original behaviour) ====================
const PUBLIC_HEAL_COST = 50;
const PUBLIC_HEAL_DURATION_MS = 360000; // 6 minutes
const AD_REDUCED_HEAL_DURATION_MS = 180000; // 3 minutes
const DEFAULT_PRIVATE_HEAL_COST = 50;
const DEFAULT_PRIVATE_HEAL_DURATION_MS = 240000; // 4:00
const MIN_HEAL_DURATION_NO_RESEARCH_MS = 180000; // 3:00
const MIN_HEAL_DURATION_WITH_RESEARCH_MS = 120000; // 2:00
const MAX_HEAL_DURATION_MS = 240000; // 4:00
const BROKEN_BONE_COST = 110;
const BROKEN_BONE_LOCATION = "Lónghǎi";
const DEFAULT_STAMINA_COST = 150;
const DEFAULT_CONSTITUTION_COST = 150;
const MAINTENANCE_CHECK_INTERVAL_MS = 120000; // 2 minutes
const BASE_MAINTENANCE_FEE = 10;

// Epinephrine quality → Enhanced Stamina duration (minutes)
const EPINEPHRINE_DURATION_MINUTES = {
  1: 6,
  2: 7,
  3: 8,
  4: 10,
  5: 12
};
const DEFAULT_ENHANCED_STAMINA_MINUTES = 5;

module.exports = {
  EFFICIENT_DOCTORS_RESEARCH,
  ENHANCED_STAMINA_RESEARCH,
  ENHANCED_CONSTITUTION_RESEARCH,
  ALLOWED_HOSPITAL_SERVICE_FIELDS,
  hospitalCounts,
  PUBLIC_HEAL_COST,
  PUBLIC_HEAL_DURATION_MS,
  AD_REDUCED_HEAL_DURATION_MS,
  DEFAULT_PRIVATE_HEAL_COST,
  DEFAULT_PRIVATE_HEAL_DURATION_MS,
  MIN_HEAL_DURATION_NO_RESEARCH_MS,
  MIN_HEAL_DURATION_WITH_RESEARCH_MS,
  MAX_HEAL_DURATION_MS,
  BROKEN_BONE_COST,
  BROKEN_BONE_LOCATION,
  DEFAULT_STAMINA_COST,
  DEFAULT_CONSTITUTION_COST,
  MAINTENANCE_CHECK_INTERVAL_MS,
  BASE_MAINTENANCE_FEE,
  EPINEPHRINE_DURATION_MINUTES,
  DEFAULT_ENHANCED_STAMINA_MINUTES,
};