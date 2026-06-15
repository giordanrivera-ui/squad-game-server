function getPrisonChance(level, exp) {
  let prisonChance;

  if (level === "mid") {
    prisonChance = 0.47;
    if (exp > 49) prisonChance = 0.44;
    if (exp > 514) prisonChance = 0.42;
    if (exp > 1264) prisonChance = 0.38;
    if (exp > 2314) prisonChance = 0.36;
    if (exp > 3514) prisonChance = 0.34;
    if (exp > 5014) prisonChance = 0.31;
    if (exp > 6864) prisonChance = 0.29;
    if (exp > 8864) prisonChance = 0.26;
    if (exp > 10214) prisonChance = 0.25;
    if (exp > 11464) prisonChance = 0.24;
    if (exp > 14214) prisonChance = 0.22;
    if (exp > 17414) prisonChance = 0.20;
    if (exp > 21364) prisonChance = 0.16;
    if (exp > 25864) prisonChance = 0.14;
    if (exp > 31514) prisonChance = 0.12;
    if (exp > 38214) prisonChance = 0.10;

  } else if (level === "high") {
    prisonChance = 0.54;
    if (exp > 49) prisonChance = 0.52;
    if (exp > 514) prisonChance = 0.50;
    if (exp > 1264) prisonChance = 0.45;
    if (exp > 2314) prisonChance = 0.42;
    if (exp > 3514) prisonChance = 0.38;
    if (exp > 5014) prisonChance = 0.33;
    if (exp > 6864) prisonChance = 0.30;
    if (exp > 8864) prisonChance = 0.27;
    if (exp > 10214) prisonChance = 0.25;
    if (exp > 11464) prisonChance = 0.23;
    if (exp > 14214) prisonChance = 0.21;
    if (exp > 17414) prisonChance = 0.20;
    if (exp > 21364) prisonChance = 0.18;
    if (exp > 25864) prisonChance = 0.16;
    if (exp > 31514) prisonChance = 0.15;
    if (exp > 38214) prisonChance = 0.14;

  } else {
    // low level (default)
    prisonChance = 0.27;
    if (exp > 49) prisonChance = 0.25;
    if (exp > 514) prisonChance = 0.21;
    if (exp > 1264) prisonChance = 0.20;
    if (exp > 2314) prisonChance = 0.19;
    if (exp > 3514) prisonChance = 0.18;
    if (exp > 5014) prisonChance = 0.17;
    if (exp > 6864) prisonChance = 0.16;
    if (exp > 8864) prisonChance = 0.15;
    if (exp > 10214) prisonChance = 0.14;
    if (exp > 11464) prisonChance = 0.13;
    if (exp > 14214) prisonChance = 0.12;
    if (exp > 17414) prisonChance = 0.11;
    if (exp > 21364) prisonChance = 0.10;
    if (exp > 25864) prisonChance = 0.08;
    if (exp > 31514) prisonChance = 0.07;
    if (exp > 38214) prisonChance = 0.06;
  }

  return prisonChance;
}

module.exports = { getPrisonChance };