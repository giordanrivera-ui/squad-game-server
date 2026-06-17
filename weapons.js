const admin = require('firebase-admin');
const { logTransaction } = require('./utils');

// ==================== WEAPON MASTER LIST (SERVER-AUTHORITATIVE) ====================
const weaponTemplates = [
  { name: 'Small Knife', description: 'A compact blade for quick stabs and slashes in close-quarters combat.', power: 10, cost: 30, type: 'weapon' },
  { name: 'Baseball Bat', description: 'A sturdy wooden club ideal for blunt force trauma in melee situations.', power: 18, cost: 120, type: 'weapon' },
  { name: 'Machete', description: 'A large chopping blade effective for hacking through obstacles or enemies.', power: 25, cost: 250, type: 'weapon' },
  { name: 'Splitting Maul', description: 'A heavy hammer-axe hybrid designed for powerful overhead strikes.', power: 30, cost: 350, type: 'weapon' },
  { name: 'Ruger Mark IV', description: 'A reliable .22 caliber pistol perfect for target practice and small game.', power: 70, cost: 520, type: 'weapon' },
  { name: 'Glock 45 Gen 5', description: 'A versatile 9mm handgun known for its durability and high-capacity magazine.', power: 150, cost: 700, type: 'weapon' },
  { name: 'Remington R1 Enhanced', description: 'A 1911-style .45 pistol with improved ergonomics and accuracy.', power: 190, cost: 780, type: 'weapon' },
  { name: 'Walther PDP Pro', description: 'A premium 9mm striker-fired pistol optimized for tactical use with modular ergonomics, crisp trigger, and full optics-ready capability.', power: 210, cost: 850, type: 'weapon' },
  { name: 'Mossberg 590 Shotgun', description: 'A pump-action 12-gauge shotgun excellent for close-range crowd control.', power: 260, cost: 1200, type: 'weapon' },
  { name: 'MP5 SMG', description: 'A compact 9mm submachine gun favored for its controllability in full-auto fire.', power: 330, cost: 4000, type: 'weapon' },
  { name: 'H&K UMP5', description: 'A .45 caliber submachine gun offering superior stopping power in CQB.', power: 380, cost: 4600, type: 'weapon' },
  { name: 'SLR104 AK-74', description: 'A modernized 5.45mm assault rifle with reliable performance in various conditions.', power: 405, cost: 6200, type: 'weapon' },
  { name: 'CZ Bren 2', description: 'A modern Czech 5.56mm assault rifle renowned for its exceptional reliability, lightweight modular design, and superior ergonomics.', power: 430, cost: 7500, type: 'weapon' },
  { name: 'M4 Carbine', description: 'A lightweight 5.56mm carbine widely used for its modularity and accuracy.', power: 480, cost: 8400, type: 'weapon' },
  { name: 'SCAR-16 Mk II', description: 'A battle-proven 5.56mm assault rifle with quick barrel swap capabilities.', power: 530, cost: 10500, type: 'weapon' },
  { name: 'M16A4', description: 'A full-length 5.56mm rifle known for its precision in semi-automatic fire.', power: 550, cost: 16400, type: 'weapon' },
  { name: 'XM7', description: 'A next-generation 6.8x51mm battle rifle adopted by the U.S. Army for superior range, penetration, and lethality compared to legacy 5.56mm platforms.', power: 575, cost: 17200, type: 'weapon' },
  { name: 'M24 Sniper', description: 'A bolt-action 7.62mm rifle designed for long-range precision shots.', power: 610, cost: 22000, type: 'weapon' },
  { name: 'Barrett M82', description: 'A .50 caliber anti-materiel rifle capable of penetrating light armor at distance.', power: 640, cost: 28000, type: 'weapon' },
];

// ==================== REQUEST WEAPONS LIST ====================
function handleRequestWeapons(socket) {
  socket.emit('weapons-list', weaponTemplates);
}

// ==================== PURCHASE WEAPONS (SECURE SERVER VALIDATION) ====================
async function handlePurchaseWeapons(db, socket, data) {
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

  // 2. Validate every weapon against server master list
  for (const item of data.items) {
    const template = weaponTemplates.find(w => w.name === item.name);
    if (!template || template.cost !== item.cost || template.power !== item.power) {
      socket.emit('purchase-result', { success: false, message: 'Invalid weapon data' });
      return;
    }
  }

  await logTransaction(socket, -data.totalCost, 'Weapons Purchased', p, docRef);

  p.balance -= data.totalCost;

  // ==================== Add value field for Net Worth calculation ====================
  const weaponsWithValue = data.items.map(item => ({
    ...item,
    value: item.cost || 0,
    type: 'weapon'
  }));

  p.inventory = p.inventory.concat(weaponsWithValue);

  await docRef.set(p);
  socket.emit('update-stats', p);
  socket.emit('purchase-result', { success: true, message: 'Weapons purchased!' });
}

module.exports = {
  weaponTemplates,
  handleRequestWeapons,
  handlePurchaseWeapons
};