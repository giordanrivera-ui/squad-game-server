// ====================== vehicles.js ======================
const admin = require('firebase-admin');

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

  // Live update to client
  socket.emit('new-transaction', {
    amount: amount,
    description: description,
    balanceAfter: Math.round(newBalance)
  });

  // Permanent storage
  try {
    await docRef.collection('transactions').add(txData);
    console.log(`[TX SAVED] ${description} | $${amount} → Balance: $${newBalance}`);
  } catch (err) {
    console.error('[TX ERROR] Failed to save transaction:', err);
  }
}

// ==================== VEHICLE MASTER LIST (SERVER-AUTHORITATIVE) ====================
const vehicleTemplates = [
  { name: 'Bicycle', power: 50, cost: 350, skillReq: 0, description: 'A human-powered vehicle with two wheels, propelled by pedaling.', defense: 0},
  { name: 'Motorcycle', power: 75, cost: 4200, skillReq: 0, description: 'A two-wheeled powered vehicle with a seat or saddle, designed for rider and passenger.', defense: 1},
  { name: 'Corolla', power: 150, cost: 18000, skillReq: 0, description: 'A compact sedan known for reliability, fuel efficiency, and affordability.', defense: 2},
  { name: 'Jeep', power: 200, cost: 36000, skillReq: 1, description: 'Rugged off-road SUV with removable doors/roof, excellent trail capability.', defense: 3},
  { name: 'Strada Pickup Truck', power: 280, cost: 55000, skillReq: 1, description: 'Mid-size pickup with rugged design, diesel engine, good for work/adventure.', defense: 3},
  { name: 'Hummer H1', power: 360, cost: 80000, skillReq: 2, description: 'Civilian version of military Humvee, extreme off-road 4x4 with high ground clearance.', defense: 4},
  { name: 'M998 Humvee', power: 500, cost: 92000, skillReq: 4, description: 'Military 4x4 utility vehicle, highly mobile, multi-purpose.', defense: 4},
  { name: 'M-ATV', power: 750, cost: 475000, skillReq: 5, description: 'Mine-resistant ambush-protected all-terrain vehicle for troop protection in hazardous environments.', defense: 5},
  { name: 'MaxxPro MRAP', power: 900, cost: 1400000, skillReq: 6, description: 'Armored fighting vehicle designed for IED protection, V-hull design.', defense: 5},
  { name: 'AMPV', power: 1200, cost: 4500000, skillReq: 8, description: 'Armored multi-purpose vehicle replacing M113, for troop transport and support.', defense: 6},
  { name: 'Stryker M1126', power: 1500, cost: 5250000, skillReq: 10, description: 'Wheeled armored personnel carrier, highly mobile 8x8 for infantry transport.', defense: 7},
  { name: 'M1 Abrams', power: 2000, cost: 8200000, skillReq: 12, description: 'Third-generation main battle tank with advanced armor, 120mm gun, high mobility.', defense: 8},
];

// ==================== REQUEST VEHICLES LIST ====================
function handleRequestVehicles(socket) {
  socket.emit('vehicles-list', vehicleTemplates);
}

// ==================== PURCHASE VEHICLES (SECURE SERVER VALIDATION) ====================
async function handlePurchaseVehicles(db, socket, data) {
  const email = socket.data.email;
  if (!email || !Array.isArray(data.items) || typeof data.totalCost !== 'number') {
    socket.emit('purchase-result', { success: false, message: 'Invalid request' });
    return;
  }

  const docRef = db.collection('players').doc(email);
  const doc = await docRef.get();
  if (!doc.exists) return;

  let p = doc.data();

  // 1. Check balance
  if (p.balance < data.totalCost) {
    socket.emit('purchase-result', { success: false, message: 'Not enough money' });
    return;
  }

  // 2. Validate every vehicle against server master list
  for (const item of data.items) {
    const template = vehicleTemplates.find(v => v.name === item.name);
    if (!template || template.cost !== item.cost) {
      socket.emit('purchase-result', { success: false, message: 'Invalid vehicle data' });
      return;
    }
  }

  // 3. Log transaction and update inventory
  await logTransaction(socket, -data.totalCost, 'Vehicles Purchased', p, docRef);
  p.balance -= data.totalCost;
  p.inventory = p.inventory.concat(data.items);

  await docRef.set(p);
  socket.emit('update-stats', p);

  socket.emit('purchase-result', { success: true, message: 'Vehicles purchased!' });
}

module.exports = {
  vehicleTemplates,
  handleRequestVehicles,
  handlePurchaseVehicles
};