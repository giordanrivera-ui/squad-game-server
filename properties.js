const admin = require('firebase-admin');

const properties = [
  {
    name: "Micropod",
    cost: 15000,
    income: 840,
    description: "A compact, efficient urban dwelling designed for minimalist living in bustling city centers, offering basic amenities in a small footprint."
  },
  {
    name: "Cottage",
    cost: 45000,
    income: 2150,
    description: "A cozy, single-story home with a quaint charm, perfect for small families or retirees seeking a peaceful rural or suburban retreat."
  },
  {
    name: "Bungalow",
    cost: 98000,
    income: 4400,
    description: "A single-level residence with a low-pitched roof and wide veranda, ideal for comfortable living in temperate climates with easy accessibility."
  },
  {
    name: "Townhouse",
    cost: 150000,
    income: 6400,
    description: "A multi-story attached home in urban rows, combining privacy with community living, suitable for professionals in city environments."
  },
  {
    name: "Suburban home",
    cost: 210000,
    income: 8750,
    description: "A spacious family house in residential neighborhoods, featuring multiple bedrooms and a yard for everyday comfort and child-rearing."
  },
  {
    name: "Villa",
    cost: 300000,
    income: 11880,
    description: "An elegant countryside estate with expansive grounds, offering luxury and seclusion for those desiring a refined lifestyle away from urban hustle."
  },
  {
    name: "Mansion",
    cost: 500000,
    income: 18520,
    description: "A grand, opulent residence with numerous rooms and high-end features, symbolizing wealth and providing ample space for entertaining."
  },
  {
    name: "Mid-Rise Block",
    cost: 1200000,
    income: 43400,
    description: "A multi-unit apartment building of moderate height, catering to urban dwellers with shared amenities and convenient city access."
  },
  {
    name: "Residential Tower",
    cost: 3800000,
    income: 126700,
    description: "A high-rise condominium complex offering modern living spaces with panoramic views and premium facilities in metropolitan areas."
  },
  {
    name: "Skyscraper",
    cost: 9000000,
    income: 276900,
    description: "A towering architectural marvel housing luxury apartments and offices, representing pinnacle urban development and investment potential."
  }
];

// ==================== IMPROVED TRANSACTION LOGGER (Server-side persistence) ====================
async function logTransaction(socket, amount, description, playerData, docRef) {
  if (!socket || typeof amount !== 'number' || !playerData || !docRef) {
    console.warn('[TX] Invalid logTransaction call - missing params');
    return;
  }

  const newBalance = (playerData.balance || 0) + amount;

  const txData = {
    amount: amount,
    description: description,
    balanceAfter: Math.round(newBalance),
    timestamp: admin.firestore.FieldValue.serverTimestamp()
  };

  // Live update to client (for immediate UI)
  socket.emit('new-transaction', {
    amount: amount,
    description: description,
    balanceAfter: Math.round(newBalance)
  });

  // Permanent storage on server (always succeeds, uses admin SDK)
  try {
    await docRef.collection('transactions').add(txData);
    console.log(`[TX SAVED] ${description} | $${amount} → Balance: $${newBalance}`);
  } catch (err) {
    console.error('[TX ERROR] Failed to save transaction:', err);
  }
}

const upgradeCosts = {
  "Fiber Optic": {
    "Micropod": 540,
    "Cottage": 720,
    "Bungalow": 900,
    "Townhouse": 1080,
    "Suburban home": 1260,
    "Villa": 1530,
    "Mansion": 1800,
    "Mid-Rise Block": 2070,
    "Residential Tower": 2530,
    "Skyscraper": 3200,
  },
  "Smart Appliances": {
    "Micropod": 800,
    "Cottage": 1000,
    "Bungalow": 1200,
    "Townhouse": 1400,
    "Suburban home": 1600,
    "Villa": 1900,
    "Mansion": 2220,
    "Mid-Rise Block": 2550,
    "Residential Tower": 3200,
    "Skyscraper": 4700,
  },
  "Double Glazing": {
    "Micropod": 1100,
    "Cottage": 1320,
    "Bungalow": 1550,
    "Townhouse": 1800,
    "Suburban home": 2020,
    "Villa": 2250,
    "Mansion": 2600,
    "Mid-Rise Block": 2900,
    "Residential Tower": 4000,
    "Skyscraper": 5500,
  },
  "Energy Recovery Ventilation": {
    "Micropod": 1450,
    "Cottage": 1700,
    "Bungalow": 1950,
    "Townhouse": 2200,
    "Suburban home": 2500,
    "Villa": 2750,
    "Mansion": 3250,
    "Mid-Rise Block": 3800,
    "Residential Tower": 4500,
    "Skyscraper": 6500,
  },
};

const upgradeBoosts = {
  "Fiber Optic": {
    "Micropod": 30,
    "Cottage": 40,
    "Bungalow": 50,
    "Townhouse": 60,
    "Suburban home": 70,
    "Villa": 85,
    "Mansion": 100,
    "Mid-Rise Block": 115,
    "Residential Tower": 140,
    "Skyscraper": 175,
  },
  "Smart Appliances": {
    "Micropod": 40,
    "Cottage": 50,
    "Bungalow": 60,
    "Townhouse": 70,
    "Suburban home": 80,
    "Villa": 95,
    "Mansion": 110,
    "Mid-Rise Block": 125,
    "Residential Tower": 150,
    "Skyscraper": 210,
  },
  "Double Glazing": {
    "Micropod": 50,
    "Cottage": 60,
    "Bungalow": 70,
    "Townhouse": 80,
    "Suburban home": 90,
    "Villa": 100,
    "Mansion": 115,
    "Mid-Rise Block": 130,
    "Residential Tower": 170,
    "Skyscraper": 230,
  },
  "Energy Recovery Ventilation": {
    "Micropod": 60,
    "Cottage": 70,
    "Bungalow": 80,
    "Townhouse": 90,
    "Suburban home": 90,
    "Villa": 110,
    "Mansion": 130,
    "Mid-Rise Block": 150,
    "Residential Tower": 180,
    "Skyscraper": 260,
  },
};

async function handleBuyProperty(db, socket, propertyName) {
  const email = socket.data.email;
  if (!email || typeof propertyName !== 'string') return;

  const docRef = db.collection('players').doc(email);
  const doc = await docRef.get();
  if (!doc.exists) return;

  let p = doc.data();

  // Check if already owned
  const owned = p.ownedProperties || [];
  if (owned.includes(propertyName)) return;

  // Find property
  const prop = properties.find(pr => pr.name === propertyName);
  if (!prop) return;

  // Check balance
  if (p.balance < prop.cost) return;

  const now = Date.now();
  p.balance -= prop.cost;
  await logTransaction(socket, -prop.cost, `Property Purchased: ${propertyName}`, p, docRef);   // p = playerData, docRef = the Firestore reference

  p.ownedProperties = [...owned, propertyName];
  p.propertyClaims = [...(p.propertyClaims || []), {name: propertyName, lastClaim: now}];  // Add per-property entry

  await docRef.set(p);
  socket.emit('update-stats', p);
}

async function handleBuyUpgrade(db, socket, propertyName, upgradeName) {
  const email = socket.data.email;
  if (!email || typeof propertyName !== 'string' || typeof upgradeName !== 'string') return;

  const docRef = db.collection('players').doc(email);
  const doc = await docRef.get();
  if (!doc.exists) return;

  let p = doc.data();

  // Check if owns property
  const owned = p.ownedProperties || [];
  if (!owned.includes(propertyName)) return;

  // Check if already has upgrade
  const ownedUps = p.ownedUpgrades?.[propertyName] || [];
  if (ownedUps.includes(upgradeName)) return;

  // Get cost
  const cost = upgradeCosts[upgradeName]?.[propertyName];
  if (cost === undefined) return;

  // Check balance
  if (p.balance < cost) return;

  p.balance -= cost;
  await logTransaction(socket, -cost, `Upgrade Purchased: ${upgradeName} on ${propertyName}`, p, docRef);   // p = playerData, docRef = the Firestore reference

  if (!p.ownedUpgrades) p.ownedUpgrades = {};
  if (!p.ownedUpgrades[propertyName]) p.ownedUpgrades[propertyName] = [];
  p.ownedUpgrades[propertyName].push(upgradeName);

  await docRef.set(p);
  socket.emit('update-stats', p);
}

async function handleClaimIncome(db, socket) {
  const email = socket.data.email;
  if (!email) return;

  const docRef = db.collection('players').doc(email);
  const doc = await docRef.get();
  if (!doc.exists) return;

  let p = doc.data();

  const now = Date.now();
  const intervalMs = 2 * 60 * 1000;  // 2 min test; 4*60*60*1000 for prod

  let totalAward = 0;
  let updatedClaims = [];

  const claims = p.propertyClaims || [];
  const owned = p.ownedProperties || [];

  // Only process owned properties (in case of future sell/remove)
  for (const claim of claims) {
    if (!owned.includes(claim.name)) continue;

    const prop = properties.find(pr => pr.name === claim.name);
    if (!prop) continue;

    const lastClaim = claim.lastClaim || 0;
    const elapsedMs = now - lastClaim;
    if (elapsedMs < intervalMs) {
      updatedClaims.push(claim);  // No change
      continue;
    }

    const intervals = Math.floor(elapsedMs / intervalMs);

    // Calculate boost
    const ownedUps = p.ownedUpgrades?.[claim.name] || [];
    let boost = 0;
    for (const up of ownedUps) {
      boost += upgradeBoosts[up]?.[claim.name] || 0;
    }

    const award = intervals * (prop.income + boost);
    totalAward += award;

    // Update this property's lastClaim
    updatedClaims.push({
      name: claim.name,
      lastClaim: lastClaim + (intervals * intervalMs)
    });
  }

  if (totalAward > 0) {
    p.balance += totalAward;
    await logTransaction(socket, totalAward, 'Property Income', p, docRef);   // p = playerData, docRef = the Firestore reference
    p.propertyClaims = updatedClaims;  // Save updated per-property claims
    await docRef.set(p);
    socket.emit('update-stats', p);
    socket.emit('income-claimed', { amount: totalAward });  // Optional notify
  }
}

// Export everything so server.js can use it
module.exports = {
  properties,
  handleBuyProperty,
  handleBuyUpgrade,
  handleClaimIncome
};