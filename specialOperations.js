const admin = require('firebase-admin');
const { getRankTitle } = require('./combat.js');

// ====================== SPECIAL OPERATIONS MODULE ======================
const specialOperationConfigs = {
  "Raid cartel supply line": {
    positions: ["Operation Leader", "Rifleman", "Driver"],
    maxPlayers: 3
  },
  "Bank Heist": {
    positions: ["Operation Leader", "Gunner 1", "Gunner 2", "Driver"],
    maxPlayers: 4
  },
  "Siege military base": {
    positions: ["Operation Leader", "Gunner 1", "Gunner 2", "Driver", "Artilleryman"],
    maxPlayers: 5
  }
};

// Helper to create a fresh party object
function createSpecialOperationParty(operation, email, displayName, experience = 0, photoURL = '') {
  const config = specialOperationConfigs[operation];
  if (!config) throw new Error(`Unknown special operation: ${operation}`);

  const party = {
    operation,
    leaderEmail: email,
    leaderName: displayName || 'Unknown',
    status: 'recruiting',
    createdAt: Date.now(),
    positions: {}
  };

  config.positions.forEach(pos => {
    if (pos === 'Operation Leader') {
      party.positions[pos] = {
        email,
        displayName: displayName || 'Leader',
        photoURL: photoURL || '',
        rank: getRankTitle(experience)
      };
    } else {
      party.positions[pos] = null;
    }
  });

  return party;
}

// ==================== INITIATE SPECIAL OPERATION ====================
async function handleInitiateSpecialOp(db, socket, data, logTransaction) {
  const email = socket.data.email;
  if (!email || typeof data?.operation !== 'string') {
    socket.emit('special-op-initiated', { success: false, message: 'Invalid request.' });
    return;
  }

  const docRef = db.collection('players').doc(email);
  const doc = await docRef.get();
  if (!doc.exists) {
    socket.emit('special-op-initiated', { success: false, message: 'Player not found.' });
    return;
  }

  let p = doc.data();

  // Prevent starting a new one if already in one
  if (p.activeSpecialOperationParty) {
    socket.emit('special-op-initiated', { 
      success: false, 
      message: 'You already have an active special operation.' 
    });
    return;
  }

  const config = specialOperationConfigs[data.operation];
 if (!config) {
    socket.emit('special-op-initiated', { success: false, message: 'Unknown special operation.' });
    return;
  }

  const cost = 100;
  if ((p.balance || 0) < cost) {
    socket.emit('special-op-initiated', { 
      success: false, 
      message: 'Not enough money to initiate this special operation ($100 required).' 
    });
    return;
  }

  // Create full party tracking object
  const party = createSpecialOperationParty(data.operation, email, p.displayName, p.experience || 0, p.photoURL || '');

  // Deduct cost
  await logTransaction(socket, -cost, `Initiated Special Operation: ${data.operation}`, p, docRef);

  p.balance -= cost;
  p.activeSpecialOperation = data.operation;           // backward compatibility
  p.activeSpecialOperationParty = party;               // new full tracking

  await docRef.set(p);
  socket.emit('update-stats', p);

  socket.emit('special-op-initiated', { 
    success: true, 
    message: `✅ ${data.operation} launched! Crew is now forming.` 
  });

  console.log(`[SPECIAL-OP] ${p.displayName || email} started "${data.operation}" with full party tracking`);
}

// ==================== ACCEPT INVITE HANDLER ====================
async function handleAcceptSpecialOpInvite(db, socket, data, { onlineSockets }) {
  const joinerEmail = socket.data.email;
  const joinerName = socket.data.displayName;
  const { leaderName, position, operation } = data;

  if (!joinerEmail || !leaderName || !position || !operation) {
    socket.emit('special-op-join-result', { success: false, message: 'Invalid invite data.' });
    return;
  }

    // Find leader
  const leaderQuery = await db.collection('players')
  .where('displayName', '==', leaderName)
  .limit(1)
  .get();

  if (leaderQuery.empty) {
    socket.emit('special-op-join-result', { success: false, message: 'Leader no longer online or operation cancelled.' });
    return;
  }

  const leaderDocRef = leaderQuery.docs[0].ref;
  let leaderData = leaderQuery.docs[0].data();

  const party = leaderData.activeSpecialOperationParty;
  if (!party || party.operation !== operation || party.positions[position] != null) {
    socket.emit('special-op-join-result', { success: false, message: 'Position already taken or operation no longer exists.' });
    return;
  }

  // Calculate joiner's real rank
  const joinerDoc = await db.collection('players').doc(joinerEmail).get();
  const joinerExp = joinerDoc.data()?.experience || 0;

  party.positions[position] = {
    email: joinerEmail,
    displayName: joinerName,
    photoURL: socket.data.photoURL || '',
    rank: getRankTitle(joinerExp)
  };

  // Update leader
  await leaderDocRef.update({ activeSpecialOperationParty: party });

  await db.collection('players').doc(joinerEmail).update({
    activeSpecialOperation: operation,
    activeSpecialOperationParty: party
  });

  // Notify both
  socket.emit('special-op-join-result', { 
    success: true, 
    message: `You joined as ${position}!`,
    party 
  });

    // Notify leader (live update)
  const leaderSocket = onlineSockets.get(leaderName);
  if (leaderSocket) {
    leaderSocket.emit('special-op-party-update', { party });
  }

  console.log(`[SPECIAL-OP] ${joinerName} joined ${operation} as ${position}`);
}

// ==================== CANCEL SPECIAL OPERATION ====================
async function handleCancelSpecialOp(db, socket) {
  const email = socket.data.email;
  if (!email) return;

  const docRef = db.collection('players').doc(email);
  const doc = await docRef.get();
  if (!doc.exists) return;

  let p = doc.data();

  if (p.activeSpecialOperationParty) {
    console.log(`[SPECIAL-OP] ${p.displayName || email} cancelled "${p.activeSpecialOperationParty.operation}"`);

    // Clear both fields
    p.activeSpecialOperation = null;
    delete p.activeSpecialOperationParty;

    await docRef.set(p);
    socket.emit('update-stats', p);
  }
}

// ==================== ASSIGN SPECIAL-OP WEAPON ====================
async function handleAssignSpecialWeapon(db, socket, data) {
  const email = socket.data.email;
  if (!email || !data?.weapon || !data?.position) {
    socket.emit('error', { message: 'Invalid special weapon assignment.' });
    return;
  }

  const docRef = db.collection('players').doc(email);
  const doc = await docRef.get();
  if (!doc.exists) return;

  let p = doc.data();

  // Find and remove the weapon from inventory
  const weaponToAssign = data.weapon;
  const index = p.inventory.findIndex(i =>
    i.name === weaponToAssign.name &&
    i.type === 'weapon' &&
    i.power === weaponToAssign.power
  );

  if (index === -1) {
    socket.emit('error', { message: 'Weapon not found in inventory.' });
    return;
  }

  p.inventory.splice(index, 1);

  await docRef.set(p);
  socket.emit('update-stats', p);

  console.log(`[SPECIAL-OP] ${p.displayName} assigned ${weaponToAssign.name} to ${data.position} (removed from inventory)`);
}

// ==================== LIVE RANK SYNC FOR SPECIAL OPS PARTY ====================
async function syncPartyMemberRank(db, playerEmail, newRank) {
  try {
    const playerDoc = await db.collection('players').doc(playerEmail).get();
    const p = playerDoc.data();
    if (!p?.activeSpecialOperationParty) return;

    const party = p.activeSpecialOperationParty;
    const leaderEmail = party.leaderEmail;

    let changed = false;

    // Update this player's rank in the party object
    for (const [position, occupant] of Object.entries(party.positions)) {
      if (occupant && occupant.email === playerEmail) {
        if (occupant.rank !== newRank) {
          occupant.rank = newRank;
          changed = true;
        }
        break;
      }
    }

    if (!changed) return;

    // Save the updated party to EVERY member of the party
    const batch = db.batch();
    const emailsInParty = Object.values(party.positions)
      .filter(o => o && o.email)
      .map(o => o.email);

    for (const email of emailsInParty) {
      const docRef = db.collection('players').doc(email);
      batch.update(docRef, { activeSpecialOperationParty: party });
    }

    await batch.commit();

    // Notify all online party members
    for (const email of emailsInParty) {
      const memberDoc = await db.collection('players').doc(email).get();
      const memberName = memberDoc.data()?.displayName;
      if (memberName) {
        const socket = onlineSockets.get(memberName); // onlineSockets is in server.js
        if (socket) {
          socket.emit('special-op-party-update', { party });
        }
      }
    }

    console.log(`[SPECIAL-OP] Rank sync: ${playerEmail} → ${newRank}`);
  } catch (e) {
    console.error('[SPECIAL-OP] Rank sync error:', e);
  }
}

module.exports = {
  handleInitiateSpecialOp,
  handleCancelSpecialOp,
  handleAssignSpecialWeapon,
  handleAcceptSpecialOpInvite,
  syncPartyMemberRank   // ← NEW EXPORT
};