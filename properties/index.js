/**
 * Public façade for the properties feature.
 * Exports the exact same surface that the original properties.js provided
 * so that server.js (and any other consumers) continue to work with only
 * a path change.
 */

const { PROPERTIES } = require('./constants');
const {
  propertyService,
  rebuildPropertyScheduler,
  startPropertyScheduler,
  processOverduePropertiesForPlayer
} = require('./PropertyService');

// ---------- Backward-compatible handler signatures ----------

async function handleBuyProperty(db, socket, propertyName) {
  return propertyService.buyProperty(db, socket, propertyName);
}

async function handleBuyUpgrade(db, socket, propertyName, upgradeName) {
  return propertyService.buyUpgrade(db, socket, propertyName, upgradeName);
}

async function handleClaimIncome(db, socket) {
  return propertyService.claimIncome(db, socket);
}

module.exports = {
  // Original data export
  properties: PROPERTIES,

  // Original handler names – identical signatures
  handleBuyProperty,
  handleBuyUpgrade,
  handleClaimIncome,

  // New scheduler surface
  rebuildPropertyScheduler,
  startPropertyScheduler,
  processOverduePropertiesForPlayer,

  // Optional direct access
  propertyService,
};