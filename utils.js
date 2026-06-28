const admin = require('firebase-admin');

function getAvailableBalance(player) {
  if (!player) return 0;

  const now = Date.now();

  // Auto-clean expired freeze data from the local object
  if (player.crimeFreezeUntil && player.crimeFreezeUntil <= now) {
    delete player.crimeFreezeUntil;
    delete player.frozenCrimeMoney;
  }

  // Freeze is still active
  if (player.crimeFreezeUntil && player.crimeFreezeUntil > now) {
    const frozen = player.frozenCrimeMoney || 0;
    return Math.max(0, (player.balance || 0) - frozen);
  }

  return player.balance || 0;
}

// ==================== CENTRALIZED TRANSACTION LOGGER ====================
async function logTransaction(socket, amount, description, playerData, docRef) {
  if (!socket || typeof amount !== 'number' || !playerData || !docRef) {
    console.warn('[TX] Invalid logTransaction call - missing params');
    return;
  }

  const currentBalance = playerData.balance || 0;
  const newBalance = currentBalance + amount;

  const txData = {
    amount: amount,
    description: description,
    balanceAfter: Math.round(newBalance),
    timestamp: admin.firestore.FieldValue.serverTimestamp()
  };

  socket.emit('new-transaction', {
    amount: amount,
    description: description,
    balanceAfter: Math.round(newBalance)
  });

  try {
    await docRef.collection('transactions').add(txData);
    console.log(`[TX SAVED] ${description} | $${amount} → Balance: $${newBalance}`);
  } catch (err) {
    console.error('[TX ERROR] Failed to save transaction:', err);
  }
}

// ==================== RANK SYSTEM ====================
const RANK_THRESHOLDS = [
  { maxExp: 49, title: 'Beggar' },
  { maxExp: 514, title: 'Thug' },
  { maxExp: 1264, title: 'Recruit' },
  { maxExp: 2314, title: 'Private' },
  { maxExp: 3514, title: 'Private First Class' },
  { maxExp: 5014, title: 'Corporal' },
  { maxExp: 6864, title: 'Sergeant' },
  { maxExp: 8864, title: 'Sergeant First Class' },
  { maxExp: 10214, title: 'Warrant Officer' },
  { maxExp: 11464, title: 'First Lieutenant' },
  { maxExp: 14214, title: 'Captain' },
  { maxExp: 17414, title: 'Major' },
  { maxExp: 21364, title: 'Lieutenant Colonel' },
  { maxExp: 25864, title: 'Colonel' },
  { maxExp: 31514, title: 'General' },
  { maxExp: 38214, title: 'General of the Army' },
  { maxExp: Infinity, title: 'Supreme Commander' }
];

function getRankTitle(exp) {
  for (const { maxExp, title } of RANK_THRESHOLDS) {
    if (exp <= maxExp) return title;
  }
  return 'Supreme Commander';
}

// ==================== CENTRALIZED EXP + ATTRIBUTE POINTS HELPER ====================
async function addExperienceAndGrantPoints(docRef, playerData, amount, { onlineSockets } = {}) {
  const oldExp = playerData.experience || 0;
  playerData.experience = oldExp + amount;

  const oldRank = getRankTitle(oldExp);
  const newRank = getRankTitle(playerData.experience);

  if (newRank !== oldRank && playerData.experience > oldExp) {
    if (playerData.unallocatedAttributePoints === undefined) playerData.unallocatedAttributePoints = 0;
    playerData.unallocatedAttributePoints += 3;
    console.log(`[SERVER] Rank-up: ${oldRank} → ${newRank} | +3 points (total: ${playerData.unallocatedAttributePoints})`);

    if (playerData.activeSpecialOperationParty && onlineSockets) {
      // Optional: sync party rank if you have the function
      // syncPartyMemberRank(...) 
    }
  }

  playerData.rank = newRank;

  return playerData;
}

function cleanupExpiredCrimeFreeze(player) {
  if (!player) return false;

  const now = Date.now();

  if (player.crimeFreezeUntil && player.crimeFreezeUntil <= now) {
    delete player.crimeFreezeUntil;
    delete player.frozenCrimeMoney;
    return true; // We cleaned something
  }

  return false; // Nothing to clean
}

// ==================== HELPER: Clear frozen loot from a criminal ====================
// This runs when justice opportunity expires, witness loses justice, witness disconnects,
// or when the criminal dies.
// It unfreezes the criminal's money and items so they are not stuck forever.
async function clearCrimeFreezeForPlayer(db, identifier, isEmail = false) {
  if (!identifier) return;

  try {
    let playerRef;
    let resolvedDisplayName = identifier;

    if (isEmail) {
      // Lookup directly by document ID (email) — used in death path
      playerRef = db.collection('players').doc(identifier);
    } else {
      // Find the criminal in the database by displayName
      const query = await db.collection('players')
        .where('displayName', '==', identifier)
        .limit(1)
        .get();

      if (query.empty) return;
      playerRef = query.docs[0].ref;
      resolvedDisplayName = identifier;
    }

    // Remove the frozen money and freeze timer (safe even if fields don't exist)
    await playerRef.update({
      frozenCrimeMoney: admin.firestore.FieldValue.delete(),
      crimeFreezeUntil: admin.firestore.FieldValue.delete()
    });

    // Also remove any "frozenUntil" tags from items in their inventory
    const snap = await playerRef.get();
    if (snap.exists) {
      let data = snap.data();
      if (data.inventory && Array.isArray(data.inventory)) {
        let changed = false;
        data.inventory = data.inventory.map(item => {
          if (item.frozenUntil) {
            changed = true;
            const { frozenUntil, ...cleanItem } = item;
            return cleanItem;
          }
          return item;
        });
        if (changed) {
          await playerRef.update({ inventory: data.inventory });
        }
      }
    }

    console.log(`[CRIME FREEZE] Cleared frozen loot for ${resolvedDisplayName} (justice window closed, lost, or player died)`);
  } catch (err) {
    console.error(`[CRIME FREEZE] Failed to clear freeze for ${identifier}:`, err);
  }
}

module.exports = { 
  logTransaction, 
  getRankTitle, 
  RANK_THRESHOLDS,
  addExperienceAndGrantPoints,
  getAvailableBalance,
  cleanupExpiredCrimeFreeze,
  clearCrimeFreezeForPlayer,
};