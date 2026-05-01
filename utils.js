const admin = require('firebase-admin');

// ==================== CENTRALIZED TRANSACTION LOGGER (SHARED UTILITY) ====================
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

  // Permanent storage on server
  try {
    await docRef.collection('transactions').add(txData);
    console.log(`[TX SAVED] ${description} | $${amount} → Balance: $${newBalance}`);
  } catch (err) {
    console.error('[TX ERROR] Failed to save transaction:', err);
  }
}

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

module.exports = { logTransaction, getRankTitle, RANK_THRESHOLDS };