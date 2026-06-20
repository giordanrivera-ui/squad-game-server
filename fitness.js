function getTrainingDescription(type) {
  switch (type) {
    case 'calisthenics':
      return 'Calisthenics Training';
    case 'olympic_weightlifting':
      return 'Olympic Weightlifting Session';
    case 'parkour':
      return 'Parkour Training';
    case 'gymnastics':
      return 'Gymnastics Training';
    default:
      return 'Fitness Training';
  }
}

function updateMaxHealth(player) {
  const strength = player.strength || 0;
  const previousMax = player.maxHealth || 100;

  if (strength >= 10) {
    player.maxHealth = 105;
  } else {
    player.maxHealth = 100;
  }

  // Top up current health when max health increases
  if (player.maxHealth > previousMax) {
    const healthGain = player.maxHealth - previousMax;
    player.health = Math.min(player.maxHealth, (player.health || 0) + healthGain);
  }

  return player;
}

function registerFitnessHandlers(socket, { db, logTransaction }) {
  socket.on('perform-training', async (data) => {
    const email = socket.data.email;
    if (!email || !data.type) return;

    const docRef = db.collection('players').doc(email);
    const doc = await docRef.get();
    if (!doc.exists) return;

    let p = doc.data();
    const currentToll = p.physicalToll || 0;

    let tollIncrease = 1;
    if (data.type === 'olympic_weightlifting' || data.type === 'gymnastics') {
      tollIncrease = 2;
    }

    // Calculate total cost
    let totalCost = 0;
    let tempToll = currentToll;

    for (let i = 0; i < tollIncrease; i++) {
      const cost = Math.round(10 * Math.pow(1.17, tempToll));
      totalCost += cost;
      tempToll += 1;
    }

    if ((p.balance || 0) < totalCost) {
      socket.emit('training-result', {
        success: false,
        message: `Not enough money. This training costs $${totalCost}.`
      });
      return;
    }

    // Log transaction
    const description = getTrainingDescription(data.type);
    await logTransaction(socket, -totalCost, description, p, docRef);

    // Update local balance
    p.balance = (p.balance || 0) - totalCost;

    // Increase physical toll
    p.physicalToll = currentToll + tollIncrease;

    // Apply stat increase
    let statIncreased = '';
    let amount = 0;

    switch (data.type) {
      case 'calisthenics':
        p.strength = (p.strength || 0) + 1;
        statIncreased = 'Strength';
        amount = 1;
        break;
      case 'olympic_weightlifting':
        p.strength = (p.strength || 0) + 2;
        statIncreased = 'Strength';
        amount = 2;
        break;
      case 'parkour':
        p.stealth = (p.stealth || 0) + 1;
        statIncreased = 'Stealth';
        amount = 1;
        break;
      case 'gymnastics':
        p.stealth = (p.stealth || 0) + 2;
        statIncreased = 'Stealth';
        amount = 2;
        break;
      default:
        return;
    }

    // Update max health
    p = updateMaxHealth(p);

    await docRef.set(p);
    socket.emit('update-stats', p);

    socket.emit('training-result', {
      success: true,
      message: `+${amount} ${statIncreased}! (Cost: $${totalCost})`,
      stat: statIncreased.toLowerCase(),
      amount,
      cost: totalCost
    });
  });
}

module.exports = {
  registerFitnessHandlers,
  updateMaxHealth,
  getTrainingDescription
};