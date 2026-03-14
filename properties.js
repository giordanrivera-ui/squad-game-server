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
  p.ownedProperties = [...owned, propertyName];
  p.propertyClaims = [...(p.propertyClaims || []), {name: propertyName, lastClaim: now}];  // Add per-property entry

  await docRef.set(p);
  socket.emit('update-stats', p);
}

// Function to handle claiming income (moved and turned into a function)
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
    const award = intervals * prop.income;
    totalAward += award;

    // Update this property's lastClaim
    updatedClaims.push({
      name: claim.name,
      lastClaim: lastClaim + (intervals * intervalMs)
    });
  }

  if (totalAward > 0) {
    p.balance += totalAward;
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
  handleClaimIncome
};