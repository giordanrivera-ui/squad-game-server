const { logTransaction } = require('./utils');

// ==================== LOCATIONS ====================
const normalLocations = [
  "Riverstone", "Thornbury", "Vostokgrad", "Eichenwald", "Montclair",
  "Valleora", "Lónghǎi", "Sakuragawa", "Cawayan Heights"
];

// ==================== TRAVEL COSTS ====================
const travelCosts = {
  "Riverstone": 40,
  "Thornbury": 45,
  "Vostokgrad": 110,
  "Eichenwald": 60,
  "Montclair": 85,
  "Valleora": 70,
  "Lónghǎi": 140,
  "Sakuragawa": 95,
  "Cawayan Heights": 55
};

// ==================== TRAVEL HANDLER ====================
async function handleTravel(db, socket, destination) {
  const email = socket.data.email;
  if (!email || typeof destination !== 'string') return;

  const docRef = db.collection('players').doc(email);
  const doc = await docRef.get();
  if (!doc.exists) return;

  let p = doc.data();

  if (p.location === destination || travelCosts[destination] === undefined) return;

  const cost = travelCosts[destination];
  if (p.balance < cost) return;

  await logTransaction(socket, -cost, `Travel to ${destination}`, p, docRef);
  p.balance -= cost;

  p.location = destination;

  await docRef.set(p);
  socket.emit('update-stats', p);
}

module.exports = {
  normalLocations,
  travelCosts,
  handleTravel
};