/**
 * Pure calculation helpers for the properties feature.
 * No side-effects, no Firestore, no sockets – fully unit-testable.
 */

const {
  PROPERTIES,
  UPGRADE_COSTS,
  UPGRADE_BOOSTS,
  CLAIM_INTERVAL_MS
} = require('./constants');

function getProperty(name) {
  return PROPERTIES.find(p => p.name === name) || null;
}

function getUpgradeCost(propertyName, upgradeName) {
  return UPGRADE_COSTS[upgradeName]?.[propertyName];
}

function getUpgradeBoost(propertyName, upgradeName) {
  return UPGRADE_BOOSTS[upgradeName]?.[propertyName] || 0;
}

/**
 * Sum all owned upgrade boosts for a single property.
 */
function calculateBoost(propertyName, ownedUpgradeNames = []) {
  let boost = 0;
  for (const up of ownedUpgradeNames) {
    boost += UPGRADE_BOOSTS[up]?.[propertyName] || 0;
  }
  return boost;
}

/**
 * Calculate the full claim award for a player.
 * Returns exact same structure the original handleClaimIncome computed.
 */
function calculateClaimAward(player, now = Date.now()) {
  const intervalMs = CLAIM_INTERVAL_MS;
  const claims = player.propertyClaims || [];
  const owned = player.ownedProperties || [];
  const ownedUpgrades = player.ownedUpgrades || {};

  let totalAward = 0;
  const updatedClaims = [];

  for (const claim of claims) {
    if (!owned.includes(claim.name)) continue;

    const prop = getProperty(claim.name);
    if (!prop) continue;

    const lastClaim = claim.lastClaim || 0;
    const elapsedMs = now - lastClaim;

    if (elapsedMs < intervalMs) {
      updatedClaims.push(claim);
      continue;
    }

    const intervals = Math.floor(elapsedMs / intervalMs);

    const ownedUps = ownedUpgrades[claim.name] || [];
    const boost = calculateBoost(claim.name, ownedUps);

    const award = intervals * (prop.income + boost);
    totalAward += award;

    updatedClaims.push({
      name: claim.name,
      lastClaim: lastClaim + (intervals * intervalMs)
    });
  }

  return {
    totalAward,
    updatedClaims,
    playerBefore: player
  };
}

/**
 * Earliest next claim time across all owned properties.
 * Used by the scheduler.
 */
function getEarliestNextClaimTime(claims, owned) {
  if (!claims || !owned || claims.length === 0 || owned.length === 0) return null;

  const intervalMs = CLAIM_INTERVAL_MS;
  const times = claims
    .filter(c => owned.includes(c.name) && typeof c.lastClaim === 'number')
    .map(c => c.lastClaim + intervalMs);

  return times.length > 0 ? Math.min(...times) : null;
}

/**
 * Validate that a property can be bought by this player data.
 */
function validateBuyProperty(player, propertyName) {
  const owned = player.ownedProperties || [];
  if (owned.includes(propertyName)) return 'already_owned';

  const prop = getProperty(propertyName);
  if (!prop) return 'invalid_property';

  return null;
}

/**
 * Validate that an upgrade can be bought.
 */
function validateBuyUpgrade(player, propertyName, upgradeName) {
  const owned = player.ownedProperties || [];
  if (!owned.includes(propertyName)) return 'property_not_owned';

  const ownedUps = player.ownedUpgrades?.[propertyName] || [];
  if (ownedUps.includes(upgradeName)) return 'already_owned';

  const cost = getUpgradeCost(propertyName, upgradeName);
  if (cost === undefined) return 'invalid_upgrade';

  return null;
}

module.exports = {
  getProperty,
  getUpgradeCost,
  getUpgradeBoost,
  calculateBoost,
  calculateClaimAward,
  getEarliestNextClaimTime,
  validateBuyProperty,
  validateBuyUpgrade,
  PROPERTIES, // re-export for convenience
  CLAIM_INTERVAL_MS,
};