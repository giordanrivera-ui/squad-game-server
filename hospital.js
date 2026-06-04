const admin = require('firebase-admin');
const { logTransaction } = require('./utils');

// ==================== DYNAMIC MAINTENANCE FEE CALCULATOR ====================
// Base: $10 at 4:00 (240s)
// Tier 1 (4:00 → 3:00): Every 20s reduced = +$4
// Tier 2 (3:00 → 2:00): Every 20s reduced = +$5
function calculateMaintenanceFee(healingDurationMs) {
  const durationSec = Math.round((healingDurationMs || 240000) / 1000);
  
  if (durationSec >= 240) return 10;
  
  let fee = 10;
  
  // Tier 1 reductions (240s → 180s)
  if (durationSec < 240) {
    const reductionsTier1 = Math.floor((240 - durationSec) / 20);
    fee += Math.min(reductionsTier1, 3) * 4;
  }
  
  // Tier 2 reductions (below 180s)
  if (durationSec < 180) {
    const reductionsTier2 = Math.floor((180 - durationSec) / 20);
    fee += reductionsTier2 * 5;
  }
  
  return fee;
}

async function getAllHospitalOwnership(hospitalOwnershipRef) {
  const snapshot = await hospitalOwnershipRef.get();
  const ownership = {};
  snapshot.docs.forEach(doc => {
    ownership[doc.id] = doc.data();
  });
  return ownership;
}

// ==================== TIMED HEALING (START) ====================
async function handleStartHealing(db, socket) {
  const email = socket.data.email;
  if (!email) return;

  const docRef = db.collection('players').doc(email);
  const doc = await docRef.get();
  if (!doc.exists) return;

  let p = doc.data();

  if (p.dead === true || (p.health ?? 100) <= 0) {
    socket.emit('heal-result', { success: false, message: 'You are dead and cannot heal.' });
    return;
  }

  if (p.healingEndTime && p.healingEndTime > Date.now()) {
    socket.emit('heal-result', { success: false, message: 'You are already healing.' });
    return;
  }

  const cost = 50;
  if (p.balance < cost) {
    socket.emit('heal-result', { success: false, message: 'Not enough money.' });
    return;
  }

  await logTransaction(socket, -cost, 'Started Healing ($50)', p, docRef);

  p.balance -= cost;
  p.usedAdForHealing = false;
  p.healingEndTime = Date.now() + 360000;

  await docRef.set(p);
  socket.emit('update-stats', p);
  socket.emit('heal-result', { 
    success: true, 
    message: 'Healing started... (6 minutes remaining)' 
  });
}

// ==================== CLAIM HEALING (SECURE) ====================
async function handleClaimHealing(db, socket) {
  const email = socket.data.email;
  if (!email) return;

  const docRef = db.collection('players').doc(email);
  const doc = await docRef.get();
  if (!doc.exists) return;

  let p = doc.data();

  // CRITICAL SECURITY CHECK
  if (!p.healingEndTime || p.healingEndTime > Date.now()) {
    socket.emit('heal-result', { success: false, message: 'Healing is not finished yet.' });
    return;
  }

  // Healing time is up → apply full heal
  p.health = 100;
  p.healingEndTime = 0;

  await docRef.set(p);
  socket.emit('update-stats', p);
  socket.emit('heal-result', { 
    success: true, 
    message: '✅ You are now fully healed!' 
  });
}

// ==================== BROKEN BONE HEALING ====================
async function handleHealBrokenBone(db, socket) {
  const email = socket.data.email;
  if (!email) return;

  const docRef = db.collection('players').doc(email);
  const doc = await docRef.get();
  if (!doc.exists) return;

  let p = doc.data();

  if (p.dead === true || (p.health ?? 100) <= 0) {
    socket.emit('heal-broken-bone-result', { 
      success: false, 
      message: 'You are dead and cannot heal.' 
    });
    return;
  }

  if (p.location !== "Lónghǎi") {
    socket.emit('heal-broken-bone-result', { 
      success: false, 
      message: 'Orthopedic Surgeon is only available in Lónghǎi.' 
    });
    return;
  }

  if (!p.hasBrokenBone) {
    socket.emit('heal-broken-bone-result', { 
      success: false, 
      message: 'You do not have a broken bone to heal.' 
    });
    return;
  }

  const cost = 110;
  if (p.balance < cost) {
    socket.emit('heal-broken-bone-result', { 
      success: false, 
      message: 'Not enough money ($110 required).' 
    });
    return;
  }

  await logTransaction(socket, -cost, 'Broken Bone Healing ($110)', p, docRef);
  p.balance -= cost;
  p.hasBrokenBone = false;
  p.bonePenaltyEndTimeLow = 0;
  p.bonePenaltyEndTimeMid = 0;
  p.bonePenaltyEndTimeHigh = 0;

  await docRef.set(p);

  socket.emit('heal-broken-bone-result', { 
    success: true, 
    message: '🦴 Bone healed! You feel much better.' 
  });
  socket.emit('update-stats', p);
}

async function handleClaimHospital(socket, data, { hospitalOwnershipRef }) {
  const email = socket.data.email;
  const displayName = socket.data.displayName;

  if (!email || !displayName || typeof data.location !== 'string' || typeof data.index !== 'number') {
    socket.emit('hospital-claim-result', { success: false, message: 'Invalid request.' });
    return;
  }

  const docId = `${data.location}-hospital-${data.index}`;
  const hospitalDoc = await hospitalOwnershipRef.doc(docId).get();

  if (!hospitalDoc.exists) {
    socket.emit('hospital-claim-result', { success: false, message: 'Hospital does not exist.' });
    return;
  }

  const hospital = hospitalDoc.data();

  if (hospital.isPublic) {
    socket.emit('hospital-claim-result', { success: false, message: 'Public hospitals cannot be claimed.' });
    return;
  }

  if (hospital.ownerEmail) {
    socket.emit('hospital-claim-result', { success: false, message: 'This hospital is already owned.' });
    return;
  }

  // Claim it
  await hospitalOwnershipRef.doc(docId).update({
    ownerEmail: email,
    ownerDisplayName: displayName,
    claimedAt: Date.now(),
    offerInjuryHealing: false,
    offerOrthopedicServices: false,
    offerPerformanceTherapy: false,
    offerDiseaseTherapy: false,
    customHealCost: 50,
    customHealingDuration: 240000,          // ← NEW: default 4 minutes
    hasEfficientDoctors: false,
    efficientDoctorsResearchEndTime: 0
  });

  socket.emit('hospital-claim-result', { 
    success: true, 
    message: `You now own the private hospital in ${data.location}!` 
  });

  const freshOwnership = await getAllHospitalOwnership(hospitalOwnershipRef);
  (socket.server || socket).emit('hospital-ownership-update', freshOwnership);

  console.log(`[HOSPITAL] ${displayName} claimed ${docId} — broadcast sent to all players`);
}

async function handleReleaseHospital(socket, data, { hospitalOwnershipRef }) {
  const email = socket.data.email;
  const { docId } = data;
  if (!email || !docId) return;

  const hospitalDoc = await hospitalOwnershipRef.doc(docId).get();
  if (!hospitalDoc.exists) return;

  const hospitalData = hospitalDoc.data();
  if (hospitalData.ownerEmail !== email) {
    socket.emit('error', { message: 'You do not own this hospital.' });
    return;
  }

  await hospitalOwnershipRef.doc(docId).update({
    ownerEmail: null,
    ownerDisplayName: null,
    claimedAt: null,
    customHealCost: 50,
    customHealingDuration: 240000,
    hasEfficientDoctors: false,
    efficientDoctorsResearchEndTime: 0
  });

  console.log(`[HOSPITAL] ${email} released hospital ${docId}`);

  const freshOwnership = await getAllHospitalOwnership(hospitalOwnershipRef);
  (socket.server || socket).emit('hospital-ownership-update', freshOwnership);
}

async function handleUpdateHospitalService(socket, data, { hospitalOwnershipRef, db }) {
  const email = socket.data.email;
  const { docId, field, value } = data;

  if (!email || !docId || !field || typeof value !== 'boolean') {
    socket.emit('error', { message: 'Invalid hospital service update.' });
    return;
  }

  const hospitalDoc = await hospitalOwnershipRef.doc(docId).get();
  if (!hospitalDoc.exists) return;

  const hospitalData = hospitalDoc.data();

  if (hospitalData.ownerEmail !== email) {
    socket.emit('error', { message: 'You do not own this hospital.' });
    return;
  }

  const allowedFields = ['offerInjuryHealing', 'offerOrthopedicServices', 'offerPerformanceTherapy', 'offerDiseaseTherapy'];

  if (!allowedFields.includes(field)) {
    socket.emit('error', { message: 'Invalid service field.' });
    return;
  }

  if (field === 'offerInjuryHealing' && value === true) {
    const playerDoc = await db.collection('players').doc(email).get();
    const currentBalance = playerDoc.exists ? (playerDoc.data().balance || 0) : 0;

    if (currentBalance < 10) {
      socket.emit('error', { 
        message: 'You need at least $10 balance to enable Injury Healing (maintenance fee).' 
      });
      return;
    }
  }

  await hospitalOwnershipRef.doc(docId).update({ [field]: value });

  console.log(`[HOSPITAL] ${email} updated ${field} on ${docId} → ${value}`);

  const freshOwnership = await getAllHospitalOwnership(hospitalOwnershipRef);
  (socket.server || socket).emit('hospital-ownership-update', freshOwnership);

  if (field === 'offerInjuryHealing' && value === false) {
    console.log(`[HOSPITAL] Injury Healing turned OFF for ${docId} — maintenance fee stopped`);
  }
}

function startHospitalMaintenanceChecker(db, { onlineSockets, io }) {
  setInterval(async () => {
    try {
      const now = Date.now();
      const batch = db.batch();
      const playersToNotify = [];
      let hospitalsToDisable = [];

      // ONLY fetch hospitals that actually have Injury Healing enabled
      const activeHospitals = await db.collection('hospitals')
        .where('offerInjuryHealing', '==', true)
        .get();

      for (const doc of activeHospitals.docs) {
        const h = doc.data();
        if (!h.ownerEmail) continue;

        const ownerRef = db.collection('players').doc(h.ownerEmail);
        const ownerDoc = await ownerRef.get();
        if (!ownerDoc.exists) continue;

        const owner = ownerDoc.data();
        
        // ==================== DYNAMIC FEE ====================
        const fee = calculateMaintenanceFee(h.customHealingDuration);

        if ((owner.balance || 0) >= fee) {
          // Has enough money → deduct normally
          batch.update(ownerRef, {
            balance: admin.firestore.FieldValue.increment(-fee)
          });

          const txRef = ownerRef.collection('transactions').doc();
          batch.set(txRef, {
            amount: -fee,
            description: `Hospital Maintenance - Injury Healing ($${fee})`,
            balanceAfter: (owner.balance || 0) - fee,
            timestamp: admin.firestore.FieldValue.serverTimestamp()
          });

          playersToNotify.push({
            email: h.ownerEmail,
            displayName: owner.displayName,
            fee: fee
          });

          console.log(`[HOSPITAL MAINT] $${fee} deducted from ${owner.displayName || h.ownerEmail}`);
        } else {
          // ==================== AUTO-DISABLE LOGIC ====================
          console.log(`[HOSPITAL MAINT] ${owner.displayName || h.ownerEmail} has insufficient funds ($${(owner.balance || 0)}). Auto-disabling Injury Healing for hospital ${doc.id} (fee was $${fee})`);

          hospitalsToDisable.push(doc.ref);

          if (owner.displayName) {
            const ownerSocket = onlineSockets.get(owner.displayName);
            if (ownerSocket) {
              ownerSocket.emit('error', {
                message: `Injury Healing has been automatically disabled on your hospital because you don't have enough money for the $${fee} maintenance fee.`
              });
            }
          }
        }
      }

      // Disable hospitals that couldn't afford the fee
      for (const hospitalRef of hospitalsToDisable) {
        batch.update(hospitalRef, { offerInjuryHealing: false });
      }

      await batch.commit();

      if (hospitalsToDisable.length > 0) {
        console.log(`[HOSPITAL MAINT] Auto-disabled Injury Healing on ${hospitalsToDisable.length} hospital(s).`);

        // === FIX: Broadcast the update to all clients ===
        const freshOwnership = await getAllHospitalOwnership(db.collection('hospitals'));
        io.emit('hospital-ownership-update', freshOwnership);

        // Also notify the specific owners (optional but nice)
        for (const doc of hospitalsToDisable) {
          const h = (await doc.get()).data();
          if (h?.ownerEmail) {
            const ownerSocket = onlineSockets.get(h.ownerDisplayName);
            if (ownerSocket) {
              ownerSocket.emit('error', {
                message: "Injury Healing has been automatically disabled because you don't have enough money for the maintenance fee."
              });
            }
          }
        }
      }

      // Notify players who paid
      for (const p of playersToNotify) {
        const socket = onlineSockets.get(p.displayName);
        if (socket) {
          const fresh = await db.collection('players').doc(p.email).get();
          socket.emit('update-stats', fresh.data());
          socket.emit('new-transaction', {
            amount: -p.fee,
            description: `Hospital Maintenance - Injury Healing ($${p.fee})`,
            balanceAfter: fresh.data().balance
          });
        }
      }
    } catch (e) {
      console.error('Hospital maintenance error:', e);
    }
  }, 120000);
}

// ==================== PRIVATE HOSPITAL HEALING (Updated to use custom duration) ====================
async function handleStartPrivateHealing(db, socket, data, { onlineSockets }) {
  const patientEmail = socket.data.email;
  const hospitalDocId = data.hospitalDocId;
  const ownerEmail = data.ownerEmail;

  if (!patientEmail || !hospitalDocId || !ownerEmail) return;

  const patientRef = db.collection('players').doc(patientEmail);
  const ownerRef = db.collection('players').doc(ownerEmail);
  const hospitalRef = db.collection('hospitals').doc(hospitalDocId);

  // Fast-path checks
  const patientDocCheck = await patientRef.get();
  if (patientDocCheck.exists) {
    const patientData = patientDocCheck.data();

    if (patientData.dead === true || (patientData.health ?? 100) <= 0) {
      socket.emit('heal-result', { 
        success: false, 
        message: 'You are dead and cannot heal.' 
      });
      return;
    }

    if (patientData.healingEndTime && patientData.healingEndTime > Date.now()) {
      socket.emit('heal-result', { 
        success: false, 
        message: 'You are already healing.' 
      });
      return;
    }
  }

  const hospitalDocCheck = await hospitalRef.get();
  if (!hospitalDocCheck.exists) {
    socket.emit('heal-result', { success: false, message: 'Hospital no longer exists.' });
    return;
  }
  const hospitalCheckData = hospitalDocCheck.data();
  if (!hospitalCheckData.offerInjuryHealing) {
    socket.emit('heal-result', { 
      success: false, 
      message: 'This hospital is not currently offering injury healing.' 
    });
    return;
  }
  if (!hospitalCheckData.ownerEmail || hospitalCheckData.ownerEmail !== ownerEmail) {
    socket.emit('heal-result', { 
      success: false, 
      message: 'This hospital is no longer owned by the specified owner.' 
    });
    return;
  }

  try {
    await db.runTransaction(async (transaction) => {
      const patientDoc = await transaction.get(patientRef);
      if (!patientDoc.exists) return;

      const patient = patientDoc.data();

      if (patient.healingEndTime && patient.healingEndTime > Date.now()) {
        throw new Error('Already healing');
      }

      if (patient.dead === true || (patient.health ?? 100) <= 0) {
        throw new Error('Dead or no health');
      }

      const hospitalDoc = await transaction.get(hospitalRef);
      if (!hospitalDoc.exists) {
        throw new Error('Hospital no longer exists');
      }
      const hospitalData = hospitalDoc.data();

      if (!hospitalData.offerInjuryHealing) {
        throw new Error('Service not offered');
      }

      if (!hospitalData.ownerEmail || hospitalData.ownerEmail !== ownerEmail) {
        throw new Error('Invalid hospital owner');
      }

      const healCost = hospitalData.customHealCost ?? 50;
      const healingDuration = hospitalData.customHealingDuration ?? 240000;   // ← USE CUSTOM DURATION

      const ownerDoc = await transaction.get(ownerRef);
      if (!ownerDoc.exists) return;

      const owner = ownerDoc.data();

      if ((patient.balance || 0) < healCost) {
        throw new Error('Not enough money');
      }

      const newPatientBalance = (patient.balance || 0) - healCost;
      const newOwnerBalance = (owner.balance || 0) + healCost;

      transaction.update(patientRef, {
        balance: newPatientBalance,
        healingEndTime: Date.now() + healingDuration     // ← DYNAMIC DURATION
      });

      transaction.update(ownerRef, {
        balance: newOwnerBalance
      });

      const patientTxRef = patientRef.collection('transactions').doc();
      transaction.set(patientTxRef, {
        amount: -healCost,
        description: `Healed at Private Hospital ($${healCost})`,
        balanceAfter: newPatientBalance,
        timestamp: admin.firestore.FieldValue.serverTimestamp()
      });

      const ownerTxRef = ownerRef.collection('transactions').doc();
      transaction.set(ownerTxRef, {
        amount: healCost,
        description: `Private Hospital Healing Fee ($${healCost})`,
        balanceAfter: newOwnerBalance,
        timestamp: admin.firestore.FieldValue.serverTimestamp()
      });
    });

    // === SUCCESS PATH ===
    const freshHospital = await hospitalRef.get();
    const actualHealCost = freshHospital.exists 
      ? (freshHospital.data().customHealCost ?? 50) 
      : 50;

    const actualDurationMs = freshHospital.exists 
      ? (freshHospital.data().customHealingDuration ?? 240000) 
      : 240000;

    const durationMinutes = Math.floor(actualDurationMs / 60000);
    const durationSeconds = Math.floor((actualDurationMs % 60000) / 1000);
    const durationText = durationSeconds > 0 
      ? `${durationMinutes}:${durationSeconds.toString().padStart(2, '0')}` 
      : `${durationMinutes} minutes`;

    socket.emit('new-transaction', {
      amount: -actualHealCost,
      description: `Healed at Private Hospital ($${actualHealCost})`,
      balanceAfter: (await patientRef.get()).data().balance
    });

    const freshPatient = await patientRef.get();
    socket.emit('update-stats', freshPatient.data());
    socket.emit('heal-result', { 
      success: true, 
      message: `Healing started for $${actualHealCost} (${durationText})` 
    });

    // Notify owner
    const ownerDoc = await ownerRef.get();
    const owner = ownerDoc.data();
    if (owner && owner.displayName) {
      const ownerSocket = onlineSockets.get(owner.displayName);
      if (ownerSocket) {
        ownerSocket.emit('update-stats', ownerDoc.data());
        ownerSocket.emit('new-transaction', {
          amount: actualHealCost,
          description: `Private Hospital Healing Fee ($${actualHealCost})`,
          balanceAfter: ownerDoc.data().balance
        });
      }
    }

    console.log(`[PRIVATE HEAL] ${patientEmail} paid $${actualHealCost} to ${ownerEmail} — duration: ${actualDurationMs}ms`);

  } catch (error) {
    console.error('Private healing error:', error);

    if (error.message === 'Not enough money') {
      const freshHospital = await hospitalRef.get();
      const actualHealCost = freshHospital.exists 
        ? (freshHospital.data().customHealCost ?? 50) 
        : 50;

      socket.emit('heal-result', { 
        success: false, 
        message: `Not enough money ($${actualHealCost} required).` 
      });
    } else if (error.message === 'Already healing') {
      socket.emit('heal-result', { success: false, message: 'You are already healing.' });
    } else if (error.message === 'Service not offered' || error.message === 'Hospital no longer exists') {
      socket.emit('heal-result', { 
        success: false, 
        message: 'This hospital is not currently offering injury healing.' 
      });
    } else if (error.message === 'Dead or no health') {
      socket.emit('heal-result', { 
        success: false, 
        message: 'You are dead and cannot heal.' 
      });
    } else if (error.message === 'Invalid hospital owner') {
      socket.emit('heal-result', { 
        success: false, 
        message: 'This hospital is no longer owned by that player.' 
      });
    }
  }
}

async function handleClaimPrivateHealing(db, socket) {
  const email = socket.data.email;
  if (!email) return;

  const docRef = db.collection('players').doc(email);
  const doc = await docRef.get();
  if (!doc.exists) return;

  let p = doc.data();
  if (!p.healingEndTime || p.healingEndTime > Date.now()) return;

  p.health = 100;
  p.healingEndTime = 0;

  await docRef.set(p);
  socket.emit('update-stats', p);
  socket.emit('heal-result', { success: true, message: '✅ Fully healed at private hospital!' });
}

// ==================== UPDATE CUSTOM HEAL COST ====================
async function handleUpdateHospitalHealCost(socket, data, { hospitalOwnershipRef }) {
  const email = socket.data.email;
  const { docId, newCost } = data;

  if (!email || !docId || typeof newCost !== 'number' || newCost < 1) {
    socket.emit('error', { message: 'Invalid heal cost.' });
    return;
  }

  const hospitalDoc = await hospitalOwnershipRef.doc(docId).get();
  if (!hospitalDoc.exists) return;

  const hospitalData = hospitalDoc.data();
  if (hospitalData.ownerEmail !== email) {
    socket.emit('error', { message: 'You do not own this hospital.' });
    return;
  }

  await hospitalOwnershipRef.doc(docId).update({ customHealCost: newCost });

  console.log(`[HOSPITAL] ${email} changed heal cost of ${docId} to $${newCost}`);

  const freshOwnership = await getAllHospitalOwnership(hospitalOwnershipRef);
  (socket.server || socket).emit('hospital-ownership-update', freshOwnership);
}

// ==================== UPDATE CUSTOM HEALING DURATION (FIXED) ====================
async function handleUpdateHospitalHealingDuration(socket, data, { hospitalOwnershipRef }) {
  const email = socket.data.email;
  const { docId, healingDurationMs } = data;

  if (!email || !docId || typeof healingDurationMs !== 'number') {
    socket.emit('error', { message: 'Invalid healing duration.' });
    return;
  }

  // Get the hospital document
  const hospitalDoc = await hospitalOwnershipRef.doc(docId).get();
  if (!hospitalDoc.exists) return;

  const hospitalData = hospitalDoc.data();

  // Security check: only owner can change it
  if (hospitalData.ownerEmail !== email) {
    socket.emit('error', { message: 'You do not own this hospital.' });
    return;
  }

  // ==================== NEW: Dynamic minimum (the actual fix) ====================
  const hasEfficientDoctors = hospitalData.hasEfficientDoctors === true;

  // If researched → allow 2:00 (120000). If not → keep 3:00 (180000)
  const minAllowed = hasEfficientDoctors ? 120000 : 180000;

  // Final validation using the dynamic minimum
  if (healingDurationMs < minAllowed || healingDurationMs > 240000) {
    socket.emit('error', { 
      message: hasEfficientDoctors 
        ? 'Healing duration must be between 2:00 and 4:00.' 
        : 'Healing duration must be between 3:00 and 4:00.' 
    });
    return;
  }

  // Save the new duration
  await hospitalOwnershipRef.doc(docId).update({ 
    customHealingDuration: healingDurationMs 
  });

  console.log(`[HOSPITAL] ${email} changed healing duration of ${docId} to ${healingDurationMs} ms`);

  // Broadcast the change to all clients (so the manager screen updates)
  const freshOwnership = await getAllHospitalOwnership(hospitalOwnershipRef);
  (socket.server || socket).emit('hospital-ownership-update', freshOwnership);
}

// ==================== WATCH AD TO REDUCE HEALING TIME ====================
async function handleWatchAdForFasterHealing(db, socket) {
  const email = socket.data.email;
  if (!email) return;

  const docRef = db.collection('players').doc(email);
  const doc = await docRef.get();
  if (!doc.exists) return;

  let p = doc.data();

  if (!p.healingEndTime || p.healingEndTime <= Date.now()) {
    socket.emit('heal-result', { 
      success: false, 
      message: 'You are not currently healing.' 
    });
    return;
  }

  if (p.usedAdForHealing === true) {
    socket.emit('heal-result', { 
      success: false, 
      message: 'You already used an ad to speed up this healing.' 
    });
    return;
  }

  const threeMinutesInMs = 3 * 60 * 1000;
  const newHealingEndTime = Date.now() + threeMinutesInMs;

  if (newHealingEndTime < p.healingEndTime) {
    p.healingEndTime = newHealingEndTime;
  }

  p.usedAdForHealing = true;

  await docRef.set(p);

  socket.emit('update-stats', p);
  socket.emit('heal-result', { 
    success: true, 
    message: '✅ Ad watched! Healing time reduced to 3 minutes total.' 
  });

  console.log(`[HEALING] ${email} used ad to reduce healing time`);
}

// ==================== EFFICIENT DOCTORS RESEARCH (Hospital Technology) ====================
const EFFICIENT_DOCTORS_RESEARCH = {
  id: "efficient-doctors",
  name: "Efficient Doctors",
  cost: 1000,
  durationMs: 30000, // 30 seconds
  effect: "Unlocks 2:00 minimum healing duration with 20-second increments (2:00 → 4:00)"
};

async function handleStartEfficientDoctorsResearch(db, socket, hospitalDocId) {
  const email = socket.data.email;
  if (!email || !hospitalDocId) {
    socket.emit('research-result', { success: false, message: 'Invalid request.' });
    return;
  }

  try {
    const hospitalRef = db.collection('hospitals').doc(hospitalDocId);
    const hospitalDoc = await hospitalRef.get();
    if (!hospitalDoc.exists) {
      socket.emit('research-result', { success: false, message: 'Hospital not found.' });
      return;
    }

    const hospitalData = hospitalDoc.data();
    if (hospitalData.ownerEmail !== email) {
      socket.emit('research-result', { success: false, message: 'You do not own this hospital.' });
      return;
    }

    if (hospitalData.hasEfficientDoctors === true) {
      socket.emit('research-result', { success: false, message: 'Efficient Doctors already researched.' });
      return;
    }

    if (hospitalData.efficientDoctorsResearchEndTime && hospitalData.efficientDoctorsResearchEndTime > Date.now()) {
      socket.emit('research-result', { success: false, message: 'Research already in progress.' });
      return;
    }

    // Check player balance
    const playerRef = db.collection('players').doc(email);
    const playerDoc = await playerRef.get();
    if (!playerDoc.exists || (playerDoc.data().balance || 0) < EFFICIENT_DOCTORS_RESEARCH.cost) {
      socket.emit('research-result', { success: false, message: 'Not enough money ($1000 required).' });
      return;
    }

    const playerData = playerDoc.data();

    // Deduct money + log transaction
    await logTransaction(socket, -EFFICIENT_DOCTORS_RESEARCH.cost, 'Researched: Efficient Doctors', playerData, playerRef);
    
    await playerRef.update({
      balance: admin.firestore.FieldValue.increment(-EFFICIENT_DOCTORS_RESEARCH.cost)
    });

    // Start 30-second research timer
    const completionTime = Date.now() + EFFICIENT_DOCTORS_RESEARCH.durationMs;
    await hospitalRef.update({
      efficientDoctorsResearchEndTime: completionTime
    });

    // Send success feedback
    const freshPlayer = await playerRef.get();
    socket.emit('update-stats', freshPlayer.data());
    socket.emit('research-result', {
      success: true,
      message: `🔬 Researching Efficient Doctors... (30 seconds)`
    });

    // Tell everyone the hospital changed
    const freshOwnership = await getAllHospitalOwnership(db.collection('hospitals'));
    (socket.server || socket).emit('hospital-ownership-update', freshOwnership);

    console.log(`[HOSPITAL RESEARCH] ${email} started Efficient Doctors research on ${hospitalDocId}`);

  } catch (error) {
    console.error('[RESEARCH ERROR]', error);
    socket.emit('research-result', { 
      success: false, 
      message: 'Something went wrong while starting research. Please try again.' 
    });
  }
}

async function handleClaimEfficientDoctorsResearch(db, socket, hospitalDocId) {
  const email = socket.data.email;
  if (!email || !hospitalDocId) return;

  const hospitalRef = db.collection('hospitals').doc(hospitalDocId);
  const hospitalDoc = await hospitalRef.get();
  if (!hospitalDoc.exists) return;

  const hospitalData = hospitalDoc.data();
  if (hospitalData.ownerEmail !== email) return;

  if (!hospitalData.efficientDoctorsResearchEndTime || hospitalData.efficientDoctorsResearchEndTime > Date.now()) {
    return; // Not finished yet
  }

  // Complete the research
  await hospitalRef.update({
    hasEfficientDoctors: true,
    efficientDoctorsResearchEndTime: 0
  });

  console.log(`[HOSPITAL RESEARCH] ${email} completed Efficient Doctors research on ${hospitalDocId}`);

  // Broadcast update — this will make the slider extend immediately in open manager screens
  const freshOwnership = await getAllHospitalOwnership(db.collection('hospitals'));
  (socket.server || socket).emit('hospital-ownership-update', freshOwnership);

  socket.emit('research-result', {
    success: true,
    message: '✅ Efficient Doctors research complete! Minimum healing time is now 2:00.'
  });
}

// ==================== CATCH-UP RESEARCH ON SERVER START (for long research times) ====================
async function catchUpEfficientDoctorsResearch(db, { io }) {
  try {
    const now = Date.now();

    const overdue = await db.collection('hospitals')
      .where('efficientDoctorsResearchEndTime', '>', 0)
      .where('efficientDoctorsResearchEndTime', '<=', now)
      .get();

    if (overdue.empty) return;

    const batch = db.batch();
    for (const doc of overdue.docs) {
      batch.update(doc.ref, {
        hasEfficientDoctors: true,
        efficientDoctorsResearchEndTime: 0
      });
    }
    await batch.commit();

    console.log(`[HOSPITAL RESEARCH] Caught up and completed ${overdue.size} overdue Efficient Doctors research(es) on startup`);

    // Tell all clients immediately
    const freshOwnership = await getAllHospitalOwnership(db.collection('hospitals'));
    io.emit('hospital-ownership-update', freshOwnership);

  } catch (e) {
    console.error('Catch-up research error on startup:', e);
  }
}

// ==================== EFFICIENT DOCTORS RESEARCH COMPLETION CHECKER ====================
function startEfficientDoctorsResearchChecker(db, { io }) {
  setInterval(async () => {
    try {
      const now = Date.now();

      // Find all hospitals that have research running and the time is up
      const hospitalsToComplete = await db.collection('hospitals')
        .where('efficientDoctorsResearchEndTime', '>', 0)
        .where('efficientDoctorsResearchEndTime', '<=', now)
        .get();

      if (hospitalsToComplete.empty) return;

      const batch = db.batch();

      for (const doc of hospitalsToComplete.docs) {
        batch.update(doc.ref, {
          hasEfficientDoctors: true,
          efficientDoctorsResearchEndTime: 0
        });
      }

      await batch.commit();

      console.log(`[HOSPITAL RESEARCH] Auto-completed Efficient Doctors research on ${hospitalsToComplete.size} hospital(s)`);

      // Broadcast to all clients so manager screens update immediately
      const freshOwnership = await getAllHospitalOwnership(db.collection('hospitals'));
      io.emit('hospital-ownership-update', freshOwnership);

    } catch (e) {
      console.error('Efficient Doctors research checker error:', e);
    }
  }, 5000); // Check every 5 seconds
}

module.exports = {
  handleStartHealing,
  handleClaimHealing,
  handleHealBrokenBone,
  handleClaimHospital,
  handleReleaseHospital,
  handleUpdateHospitalService,
  startHospitalMaintenanceChecker,
  handleStartPrivateHealing,
  handleClaimPrivateHealing,
  handleUpdateHospitalHealCost,
  handleWatchAdForFasterHealing,
  handleUpdateHospitalHealingDuration,
  handleStartEfficientDoctorsResearch,
  handleClaimEfficientDoctorsResearch,
  startEfficientDoctorsResearchChecker,
  catchUpEfficientDoctorsResearch,
  calculateMaintenanceFee   // ← Exported in case other modules need it later
};