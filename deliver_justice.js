const admin = require('firebase-admin');

// ==================== HELPER: Clean up expired loot decision safely ====================
async function cleanupExpiredLootDecision(witnessName, savedDecision, db) {
  if (!savedDecision) return;

  const criminalQuery = await db.collection('players')
    .where('displayName', '==', savedDecision.perpetrator)
    .limit(1)
    .get();

  if (criminalQuery.empty) return;

  const criminalRef = criminalQuery.docs[0].ref;

  const frozenMoney = savedDecision.frozenMoney || 0;
  const frozenItems = savedDecision.frozenItems || [];

  const itemsToRemoveSignatures = new Set(
    frozenItems.map(item => `${item.name}|${item.type || ''}|${item.frozenUntil}`)
  );

  try {
    await db.runTransaction(async (transaction) => {
      const criminalSnap = await transaction.get(criminalRef);
      if (!criminalSnap.exists) return;

      let criminalData = criminalSnap.data();

      if (frozenMoney > 0) {
        criminalData.balance = Math.max(0, (criminalData.balance || 0) - frozenMoney);
      }

      const currentInventory = criminalData.inventory || [];
      const updatedInventory = currentInventory.filter(item => {
        const signature = `${item.name}|${item.type || ''}|${item.frozenUntil}`;
        const isPartOfThisDecision = itemsToRemoveSignatures.has(signature);
        if (isPartOfThisDecision) return false;
        const isStillFrozen = item.frozenUntil && item.frozenUntil > Date.now();
        return !item.frozenUntil || isStillFrozen;
      });

      criminalData.inventory = updatedInventory;
      const currentFrozen = criminalData.frozenCrimeMoney || 0;
      criminalData.frozenCrimeMoney = Math.max(0, currentFrozen - frozenMoney);

      if (criminalData.frozenCrimeMoney === 0) {
        delete criminalData.frozenCrimeMoney;
        delete criminalData.crimeFreezeUntil;
      }

      transaction.set(criminalRef, criminalData);
    });

    console.log(`[LOOT] Cleaned up expired decision for ${witnessName} (criminal = ${savedDecision.perpetrator})`);
  } catch (err) {
    console.error('[LOOT EXPIRED CLEANUP ERROR]', err);
  }
}

// ==================== HELPER: Process Loot Decision (Take vs Return) ====================
async function processLootDecision(witnessName, choice, witnessSocket = null, isAuto = false, deps) {
  const { db, onlineSockets, lootDecisionWindows, logTransaction, clearCrimeFreezeForPlayer } = deps;

  const decision = lootDecisionWindows.get(witnessName);
  if (!decision) return;

  if (decision.timeoutId) {
    clearTimeout(decision.timeoutId);
  }

  lootDecisionWindows.delete(witnessName);

  const witnessQuery = await db.collection('players').where('displayName', '==', witnessName).limit(1).get();
  const criminalQuery = await db.collection('players').where('displayName', '==', decision.perpetrator).limit(1).get();

  if (witnessQuery.empty || criminalQuery.empty) {
    console.log(`[LOOT] Criminal ${decision.perpetrator} no longer exists (died?). Cleaning up witness decision.`);
    
    if (witnessQuery.docs[0]) {
      witnessQuery.docs[0].ref.update({
        pendingLootDecision: admin.firestore.FieldValue.delete()
      }).catch(err => console.error('[LOOT] Failed to clear persisted decision (non-fatal):', err));
    }
    if (witnessSocket) {
      witnessSocket.emit('loot-decision-result', {
        success: false,
        message: 'The criminal has died or left. Decision cancelled.'
      });
    }
    return;
  }

  const witnessRef = witnessQuery.docs[0].ref;
  const criminalRef = criminalQuery.docs[0].ref;

  const frozenMoney = decision.frozenMoney || 0;
  const frozenItems = decision.frozenItems || [];

  const criminalSocket = onlineSockets.get(decision.perpetrator);

  const itemsToRemoveSignatures = new Set(
    frozenItems.map(item => `${item.name}|${item.type || ''}|${item.frozenUntil}`)
  );

  let lootSuccess = false;

  try {
    await db.runTransaction(async (transaction) => {
      const witnessSnap = await transaction.get(witnessRef);
      const criminalSnap = await transaction.get(criminalRef);

      if (!witnessSnap.exists || !criminalSnap.exists) {
        throw new Error('Player not found during loot transaction');
      }

      let witnessData = witnessSnap.data();
      let criminalData = criminalSnap.data();

      const cleanItems = frozenItems.map(item => {
        const { frozenUntil, ...clean } = item;
        return clean;
      });

      if (choice === 'take') {
        if (frozenMoney > 0) {
          witnessData.balance = (witnessData.balance || 0) + frozenMoney;
          criminalData.balance = Math.max(0, (criminalData.balance || 0) - frozenMoney);
        }
        if (cleanItems.length > 0) {
          witnessData.inventory = [...(witnessData.inventory || []), ...cleanItems];
        }

        const currentInventory = criminalData.inventory || [];
        const updatedInventory = currentInventory.filter(item => {
          const signature = `${item.name}|${item.type || ''}|${item.frozenUntil}`;
          const isPartOfThisDecision = itemsToRemoveSignatures.has(signature);
          if (isPartOfThisDecision) return false;
          const isStillFrozen = item.frozenUntil && item.frozenUntil > Date.now();
          return !item.frozenUntil || isStillFrozen;
        });

        criminalData.inventory = updatedInventory;
        const currentFrozen = criminalData.frozenCrimeMoney || 0;
        criminalData.frozenCrimeMoney = Math.max(0, currentFrozen - frozenMoney);

        if (criminalData.frozenCrimeMoney === 0) {
          delete criminalData.frozenCrimeMoney;
          delete criminalData.crimeFreezeUntil;
        }

      } else {
        if (frozenMoney > 0) {
          criminalData.balance = Math.max(0, (criminalData.balance || 0) - frozenMoney);
        }

        const currentInventory = criminalData.inventory || [];
        const updatedInventory = currentInventory.filter(item => {
          const signature = `${item.name}|${item.type || ''}|${item.frozenUntil}`;
          const isPartOfThisDecision = itemsToRemoveSignatures.has(signature);
          if (isPartOfThisDecision) return false;
          const isStillFrozen = item.frozenUntil && item.frozenUntil > Date.now();
          return !item.frozenUntil || isStillFrozen;
        });

        criminalData.inventory = updatedInventory;
        const currentFrozen = criminalData.frozenCrimeMoney || 0;
        criminalData.frozenCrimeMoney = Math.max(0, currentFrozen - frozenMoney);

        if (criminalData.frozenCrimeMoney === 0) {
          delete criminalData.frozenCrimeMoney;
          delete criminalData.crimeFreezeUntil;
        }
      }

      transaction.set(witnessRef, witnessData);
      transaction.set(criminalRef, criminalData);
    });

    console.log(`[LOOT] ${choice.toUpperCase()} completed safely for ${witnessName} vs ${decision.perpetrator}`);
    lootSuccess = true;

  } catch (err) {
    console.error('[LOOT TRANSACTION ERROR]', err);
  }

  if (lootSuccess && choice === 'take' && frozenMoney > 0) {
    if (witnessSocket) {
      const witnessData = (await witnessRef.get()).data();
      await logTransaction(witnessSocket, frozenMoney, `Took loot from ${decision.perpetrator}`, witnessData, witnessRef);
    }
    if (criminalSocket) {
      const criminalData = (await criminalRef.get()).data();
      await logTransaction(criminalSocket, -frozenMoney, `Lost loot to ${witnessName} (justice)`, criminalData, criminalRef);
    }
  } else if (lootSuccess && choice === 'return' && frozenMoney > 0 && criminalSocket) {
    const criminalData = (await criminalRef.get()).data();
    await logTransaction(criminalSocket, -frozenMoney, `Lost loot (justice returned)`, criminalData, criminalRef);
  }

  if (witnessSocket) {
    witnessSocket.emit('loot-decision-result', { 
      success: lootSuccess, 
      choice, 
      amount: frozenMoney 
    });
    if (lootSuccess) {
      const updatedWitness = await witnessRef.get();
      witnessSocket.emit('update-stats', updatedWitness.data());
    }
  }

  if (criminalSocket) {
    criminalSocket.emit('loot-decision-result', {
      success: lootSuccess,
      choice,
      takenBy: choice === 'take' ? witnessName : undefined,
      amount: frozenMoney
    });
    if (lootSuccess) {
      const updatedCriminal = await criminalRef.get();
      criminalSocket.emit('update-stats', updatedCriminal.data());
    }
  }

  if (witnessQuery.docs[0]) {
    witnessQuery.docs[0].ref.update({
      pendingLootDecision: admin.firestore.FieldValue.delete()
    }).catch(err => console.error('[LOOT] Failed to clear persisted decision (non-fatal):', err));
  }
}

// ==================== REGISTER SOCKET HANDLERS ====================
function registerDeliverJusticeHandlers(socket, deps) {
  const { 
    db, 
    onlineSockets, 
    crimeWitnessOpportunities, 
    lootDecisionWindows, 
    clearCrimeFreezeForPlayer, 
    logTransaction 
  } = deps;

  // ==================== DELIVER JUSTICE ====================
  socket.on('deliver-justice', async (data) => {
    const witnessName = socket.data.displayName;
    const perpetratorName = data?.perpetrator;
    if (!witnessName || !perpetratorName) return;

    const opportunities = crimeWitnessOpportunities.get(witnessName);
    const opportunityData = opportunities?.get(perpetratorName);

    const opportunityExpiry = typeof opportunityData === 'number' 
        ? opportunityData 
        : opportunityData?.expiry;

    if (!opportunityExpiry || Date.now() > opportunityExpiry) {
      socket.emit('deliver-justice-result', {
        success: false,
        message: 'You did not witness this crime or the opportunity has expired.'
      });
      return;
    }

    opportunities.delete(perpetratorName);
    if (opportunities.size === 0) crimeWitnessOpportunities.delete(witnessName);

    if (typeof opportunityData === 'object' && opportunityData.timeoutId) {
      clearTimeout(opportunityData.timeoutId);
      console.log(`[JUSTICE] Cancelled 6s auto-unfreeze timer for ${perpetratorName} because ${witnessName} acted`);
    }

    const witnessQuery = await db.collection('players').where('displayName', '==', witnessName).limit(1).get();
    const criminalQuery = await db.collection('players').where('displayName', '==', perpetratorName).limit(1).get();

    if (witnessQuery.empty || criminalQuery.empty) {
      console.log(`[JUSTICE] Criminal or witness no longer exists during deliver-justice.`);
      return;
    }

    const witnessDoc = witnessQuery.docs[0];
    const criminalDoc = criminalQuery.docs[0];
    const witness = witnessDoc.data();
    const criminal = criminalDoc.data();

    // ==================== ARCHETYPE + RPS + SCORING ====================
    const wStr = witness.strength || 0;
    const wSte = witness.stealth || 0;
    const cStr = criminal.strength || 0;
    const cSte = criminal.stealth || 0;

    const witnessTotal = wStr + wSte;
    const criminalTotal = cStr + cSte;

    const getArchetype = (str, ste) => {
      if (str === 0 && ste === 0) return 'Mixed';
      if (str === 0) return 'Pure Stealth';
      if (ste === 0) return 'Pure Strength';

      const ratio = Math.max(str, ste) / Math.min(str, ste);
      if (ratio >= 1.5) return str > ste ? 'Pure Strength' : 'Pure Stealth';
      return 'Mixed';
    };

    const witnessArchetype = getArchetype(wStr, wSte);
    const criminalArchetype = getArchetype(cStr, cSte);

    let rpsWinner = null;
    if (witnessArchetype === criminalArchetype) {
      rpsWinner = 'tie';
    } else if (
      (witnessArchetype === 'Pure Stealth' && criminalArchetype === 'Mixed') ||
      (witnessArchetype === 'Mixed' && criminalArchetype === 'Pure Strength') ||
      (witnessArchetype === 'Pure Strength' && criminalArchetype === 'Pure Stealth')
    ) {
      rpsWinner = 'witness';
    } else {
      rpsWinner = 'criminal';
    }

    // ==================== SCORE + BONUS CALCULATION ====================
    let witnessScore = 0;
    let criminalScore = 0;
    let archetypeBonus = 0;
    let dominanceBonus = 0;
    let witnessInvestmentBonus = 0;
    let criminalInvestmentBonus = 0;

    if (rpsWinner === 'witness') {
      archetypeBonus = 24;
      dominanceBonus = Math.min((Math.max(wStr, wSte) / Math.max(Math.max(cStr, cSte), 1)) * 12, 30);
      witnessInvestmentBonus = Math.min(witnessTotal / 3, 20);

      witnessScore = archetypeBonus + dominanceBonus + witnessInvestmentBonus;
      criminalScore = 20;

    } else if (rpsWinner === 'criminal') {
      archetypeBonus = 24;
      dominanceBonus = Math.min((Math.max(cStr, cSte) / Math.max(Math.max(wStr, wSte), 1)) * 12, 30);
      criminalInvestmentBonus = Math.min(criminalTotal / 3, 20);

      criminalScore = archetypeBonus + dominanceBonus + criminalInvestmentBonus;
      witnessScore = 20;

    } else {
      witnessScore = 10;
      criminalScore = 10;
      archetypeBonus = 10;

      if (witnessTotal > criminalTotal) {
        witnessInvestmentBonus = witnessTotal / 3;
        criminalInvestmentBonus = criminalTotal / 4.5;
      } else if (criminalTotal > witnessTotal) {
        criminalInvestmentBonus = criminalTotal / 3;
        witnessInvestmentBonus = witnessTotal / 4.5;
      } else {
        witnessInvestmentBonus = 10;
        criminalInvestmentBonus = 10;
      }

      witnessScore += witnessInvestmentBonus;
      criminalScore += criminalInvestmentBonus;
    }

    const witnessRoll = Math.floor(Math.random() * (70 - 22 + 1)) + 22;
    const criminalRoll = Math.floor(Math.random() * (70 - 22 + 1)) + 22;

    const witnessFinal = witnessRoll + witnessScore;
    const criminalFinal = criminalRoll + criminalScore;
    const witnessWins = witnessFinal > criminalFinal;

    // ==================== EMIT RESULTS ====================
    const payload = {
      witnessName,
      perpetratorName,
      witnessArchetype,
      criminalArchetype,
      rpsWinner,
      witnessScore: Math.round(witnessScore),
      criminalScore: Math.round(criminalScore),
      witnessFinal: Math.round(witnessFinal),
      criminalFinal: Math.round(criminalFinal),
      witnessRoll,
      criminalRoll,
      archetypeBonus: Math.round(archetypeBonus),
      dominanceBonus: Math.round(dominanceBonus),
      witnessInvestmentBonus: Math.round(witnessInvestmentBonus),
      criminalInvestmentBonus: Math.round(criminalInvestmentBonus),
      isWinner: witnessWins,
      viewerIsWitness: true
    };

    socket.emit('deliver-justice-result', payload);

    const criminalSocket = onlineSockets.get(perpetratorName);
    if (criminalSocket) {
      criminalSocket.emit('deliver-justice-result', {
        ...payload,
        isWinner: !witnessWins,
        viewerIsWitness: false
      });
    }

    if (!witnessWins) {
      clearCrimeFreezeForPlayer(db, perpetratorName);
    }

    if (witnessWins) {
      const frozenMoney = (typeof opportunityData === 'object' && opportunityData.frozenAmount) 
          ? opportunityData.frozenAmount 
          : (criminal.frozenCrimeMoney || 0);

      const frozenItems = [];

      const decisionData = {
        perpetrator: perpetratorName,
        expiry: Date.now() + 10000,
        frozenMoney,
        frozenItems: JSON.parse(JSON.stringify(frozenItems))
      };

      const timeoutId = setTimeout(async () => {
        try {
          await processLootDecision(witnessName, 'return', null, true, deps);
        } catch (err) {
          console.error(`[LOOT] Auto-forfeit failed for ${witnessName}:`, err);
        }
        lootDecisionWindows.delete(witnessName);
      }, 10000);

      decisionData.timeoutId = timeoutId;
      lootDecisionWindows.set(witnessName, decisionData);

      socket.emit('loot-decision-pending', {
        perpetrator: decisionData.perpetrator,
        expiry: decisionData.expiry,
        frozenMoney: decisionData.frozenMoney
      });

      const witnessDocRef = db.collection('players').doc(socket.data.email);
      witnessDocRef.update({
        pendingLootDecision: {
          perpetrator: perpetratorName,
          expiry: decisionData.expiry,
          frozenMoney: decisionData.frozenMoney,
          frozenItems: decisionData.frozenItems,
          createdAt: Date.now()
        }
      }).catch(err => console.error('[LOOT] Failed to persist decision:', err));

      console.log(`[JUSTICE] ${witnessName} won on ${perpetratorName}. 10s loot decision scheduled.`);
    }
  });

  // ==================== DECIDE LOOT FATE ====================
  socket.on('decide-loot-fate', async (data) => {
    const witnessName = socket.data.displayName;
    const { perpetrator, choice } = data;

    if (!witnessName || !perpetrator || !['take', 'return'].includes(choice)) return;

    const decision = lootDecisionWindows.get(witnessName);
    if (!decision || decision.perpetrator !== perpetrator) {
      socket.emit('loot-decision-result', { success: false, message: 'No active loot decision.' });
      return;
    }

    if (Date.now() > decision.expiry) {
      socket.emit('loot-decision-result', { success: false, message: 'The decision window has closed.' });
      return;
    }

    await processLootDecision(witnessName, choice, socket, false, deps);
  });
}

module.exports = {
  registerDeliverJusticeHandlers,
  cleanupExpiredLootDecision,
  processLootDecision
};
