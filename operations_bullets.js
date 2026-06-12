function tryStealBullets(player, level, message) {
  let bulletStealChance = 0;

  if (level === "mid") {
    bulletStealChance = 0.35;
  } else if (level === "high") {
    bulletStealChance = 0.40;
  }

  // If no chance or roll fails → return original message
  if (bulletStealChance === 0 || Math.random() >= bulletStealChance) {
    return message;
  }

  // Success → determine how many bullets to steal
  let bulletsStolen = 1;
  const rand = Math.random();

  if (level === "mid") {
    bulletsStolen = (rand < 0.65) ? 1 : 2;
  } else if (level === "high") {
    if (rand < 0.50) bulletsStolen = 1;
    else if (rand < 0.90) bulletsStolen = 2;
    else bulletsStolen = 3;
  }

  // Apply bullets to player
  player.bullets = (player.bullets || 0) + bulletsStolen;

  // Append message
  message += ` You also stole ${bulletsStolen} bullet${bulletsStolen > 1 ? 's' : ''}!`;

  return message;
}

module.exports = { tryStealBullets };