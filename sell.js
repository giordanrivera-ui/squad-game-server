function registerSellHandlers(socket, { db, logTransaction }) {
  socket.on('sell-items', async (data) => {
    const email = socket.data.email;
    if (!email || !Array.isArray(data.items) || typeof data.totalSellValue !== 'number' || ![60, 80, 100].includes(data.rate)) return;

    const docRef = db.collection('players').doc(email);
    const doc = await docRef.get();
    if (!doc.exists) return;

    let p = doc.data();

    // Check if banned from selling
    if (Date.now() < (p.sellBanEndTime || 0)) {
      socket.emit('sell-result', { success: false, message: 'You are banned from selling. Try later.' });
      return;
    }

    // Validate total sell value at rate (anti-cheat)
    let calculatedValue = 0;
    const rateFactor = data.rate / 100;
    for (const item of data.items) {
      if (typeof item.cost === 'number') {
        calculatedValue += Math.floor(item.cost * rateFactor);
      }
    }
    if (calculatedValue !== data.totalSellValue) return;

    // Determine success chance and ban duration based on rate
    let successChance = 1.0;
    let banMs = 0;

    if (data.rate === 80) {
      successChance = 0.45;
      banMs = 3 * 60 * 60 * 1000; // 3 hours
    } else if (data.rate === 100) {
      successChance = 0.12;
      banMs = 8 * 60 * 60 * 1000; // 8 hours
    }

    const isSuccess = Math.random() < successChance;

    // Failed sale → apply ban
    if (!isSuccess && banMs > 0) {
      p.sellBanEndTime = Date.now() + banMs;
      await docRef.set(p);
      socket.emit('sell-result', {
        success: false,
        message: `Sale failed! Banned from selling for ${banMs / (60 * 60 * 1000)} hours.`,
      });
      socket.emit('update-stats', p);
      return;
    }

    // Successful sale: remove items from inventory
    for (const soldItem of data.items) {
      if (soldItem.frozenUntil && soldItem.frozenUntil > Date.now()) {
        socket.emit('sell-result', { 
          success: false, 
          message: 'You cannot sell items stolen from a recent crime yet.' 
        });
        return;
      }

      const index = p.inventory.findIndex(
        (i) => i.name === soldItem.name && i.type === soldItem.type && i.power === soldItem.power
      );
      if (index !== -1) {
        p.inventory.splice(index, 1);
      }
    }

    // Log transaction and update balance
    await logTransaction(socket, data.totalSellValue, 'Items Sold', p, docRef);
    p.balance += data.totalSellValue;

    await docRef.set(p);
    socket.emit('sell-result', { success: true, message: 'Items sold!' });
    socket.emit('update-stats', p);
  });
}

module.exports = { registerSellHandlers };