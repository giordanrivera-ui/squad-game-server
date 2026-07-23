/**
 * Thin compatibility shim.
 * All research logic now lives in hospital/services/ResearchService.js
 * and is accessed via hospital.js / HospitalManager.
 *
 * This file exists only so any leftover require('./hospital_research') statements
 * continue to resolve without crashing.
 */

const { researchService, RESEARCH_TYPES } = require('./hospital/services/ResearchService');
const { hospitalRepository } = require('./hospital/services/HospitalRepository');

async function handleStartEfficientDoctorsResearch(db, socket, hospitalDocId) {
  return researchService.startEfficientDoctors(db, socket, hospitalDocId);
}

async function handleStartPerformanceResearch(db, socket, hospitalDocId, researchConfig, hasField, endTimeField, researchName) {
  if (endTimeField === 'enhancedStaminaResearchEndTime') {
    return researchService.startEnhancedStamina(db, socket, hospitalDocId);
  }
  if (endTimeField === 'enhancedConstitutionResearchEndTime') {
    return researchService.startEnhancedConstitution(db, socket, hospitalDocId);
  }
}

async function handleClaimEfficientDoctorsResearch(db, socket, hospitalDocId) {
  return researchService.claimEfficientDoctors(db, socket, hospitalDocId);
}

async function handleClaimPerformanceResearch(db, socket, hospitalDocId, hasField, endTimeField, researchName) {
  if (endTimeField === 'enhancedStaminaResearchEndTime') {
    return researchService.claimEnhancedStamina(db, socket, hospitalDocId);
  }
  if (endTimeField === 'enhancedConstitutionResearchEndTime') {
    return researchService.claimEnhancedConstitution(db, socket, hospitalDocId);
  }
}

async function catchUpEfficientDoctorsResearch() { /* handled by unified catch-up */ }
async function catchUpPerformanceResearches() { /* handled by unified catch-up */ }

async function getAllHospitalOwnership(ref) {
  return hospitalRepository.getAllOwnership();
}

function getEarliestResearchEndTime(hospitalData) {
  const times = [
    hospitalData.efficientDoctorsResearchEndTime,
    hospitalData.enhancedStaminaResearchEndTime,
    hospitalData.enhancedConstitutionResearchEndTime
  ].filter(t => typeof t === 'number' && t > 0);
  if (times.length === 0) return null;
  return Math.min(...times);
}

module.exports = {
  handleStartEfficientDoctorsResearch,
  handleStartPerformanceResearch,
  handleClaimEfficientDoctorsResearch,
  handleClaimPerformanceResearch,
  catchUpEfficientDoctorsResearch,
  catchUpPerformanceResearches,
  getAllHospitalOwnership,
  getEarliestResearchEndTime,
  RESEARCH_TYPES
};