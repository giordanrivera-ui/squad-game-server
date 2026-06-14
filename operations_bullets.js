function calculateBulletSteal(level, message) {
  let bulletsStolen = 0;

  if (level !== "low") {
    let bulletStealChance = 0;
    if (level === "mid") bulletStealChance = 0.99;
    else if (level === "high") bulletStealChance = 0.40;

    if (bulletStealChance > 0 && Math.random() < bulletStealChance) {
      let bulletsToSteal = 1;
      const rand = Math.random();

      if (level === "mid") {
        bulletsToSteal = (rand < 0.65) ? 1 : 2;
      } else if (level === "high") {
        if (rand < 0.50) bulletsToSteal = 1;
        else if (rand < 0.90) bulletsToSteal = 2;
        else bulletsToSteal = 3;
      }

      bulletsStolen = bulletsToSteal;
      message += ` You also stole ${bulletsToSteal} bullet${bulletsToSteal > 1 ? 's' : ''}!`;
    }
  }

  return {
    bulletsStolen,
    message
  };
}

module.exports = { calculateBulletSteal };