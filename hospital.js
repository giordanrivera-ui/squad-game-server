const admin = require('firebase-admin');
const { logTransaction } = require('./utils');

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
  p.healingEndTime = Date.now() + 120000;   // exactly 2 minutes

  await docRef.set(p);
  socket.emit('update-stats', p);
  socket.emit('heal-result', { 
    success: true, 
    message: 'Healing started... (2 minutes remaining)' 
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
    customHealCost: 50          // ← FIX: reset to default so new owner doesn't inherit old price
  });

  socket.emit('hospital-claim-result', { 
    success: true, 
    message: `You now own the private hospital in ${data.location}!` 
  });

  // ==================== FIXED: PROPER GLOBAL BROADCAST (same pattern as release) ====================
  const freshOwnership = await getAllHospitalOwnership(hospitalOwnershipRef);
  
  (socket.server || socket).emit('hospital-ownership-update', freshOwnership);   // ← This is the correct line

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
    customHealCost: 50
  });

  console.log(`[HOSPITAL] ${email} released hospital ${docId}`);

  const freshOwnership = await getAllHospitalOwnership(hospitalOwnershipRef);
  (socket.server || socket).emit('hospital-ownership-update', freshOwnership);
}

async function handleUpdateHospitalService(socket, data, { hospitalOwnershipRef }) {
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

  await hospitalOwnershipRef.doc(docId).update({ [field]: value });

  console.log(`[HOSPITAL] ${email} updated ${field} on ${docId} → ${value}`);

  const freshOwnership = await getAllHospitalOwnership(hospitalOwnershipRef);
  (socket.server || socket).emit('hospital-ownership-update', freshOwnership);

  // ==================== NEW: Instant fee stop when turning off Injury Healing ====================
  if (field === 'offerInjuryHealing' && value === false) {
    console.log(`[HOSPITAL] Injury Healing turned OFF for ${docId} — maintenance fee stopped`);
    // Optional: You can also notify the owner here if you want
  }
}

function startHospitalMaintenanceChecker(db, { onlineSockets }) {
  setInterval(async () => {
    try {
      const now = Date.now();
      const batch = db.batch();
      const playersToNotify = [];

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
        const fee = 10;

        if ((owner.balance || 0) >= fee) {
          batch.update(ownerRef, {
            balance: admin.firestore.FieldValue.increment(-fee)
          });

          const txRef = ownerRef.collection('transactions').doc();
          batch.set(txRef, {
            amount: -fee,
            description: 'Hospital Maintenance - Injury Healing',
            balanceAfter: (owner.balance || 0) - fee,
            timestamp: admin.firestore.FieldValue.serverTimestamp()
          });

          playersToNotify.push({
            email: h.ownerEmail,
            displayName: owner.displayName,
            fee: fee
          });

          console.log(`[HOSPITAL MAINT] $${fee} deducted from ${owner.displayName || h.ownerEmail}`);
        }
      }

      await batch.commit();

      // Live UI updates
      for (const p of playersToNotify) {
        const socket = onlineSockets.get(p.displayName);
        if (socket) {
          const fresh = await db.collection('players').doc(p.email).get();
          socket.emit('update-stats', fresh.data());
          socket.emit('new-transaction', {
            amount: -p.fee,
            description: 'Hospital Maintenance - Injury Healing',
            balanceAfter: fresh.data().balance
          });
        }
      }
    } catch (e) {
      console.error('Hospital maintenance error:', e);
    }
  }, 120000); // 2 minutes
}

// ==================== PRIVATE HOSPITAL HEALING (Fixed stale healCost) ====================
async function handleStartPrivateHealing(db, socket, data, { onlineSockets }) {
  const patientEmail = socket.data.email;
  const hospitalDocId = data.hospitalDocId;
  const ownerEmail = data.ownerEmail;

  if (!patientEmail || !hospitalDocId || !ownerEmail) return;

  const patientRef = db.collection('players').doc(patientEmail);
  const ownerRef = db.collection('players').doc(ownerEmail);
  const hospitalRef = db.collection('hospitals').doc(hospitalDocId);

  // === FAST-PATH CHECKS (good UX, non-authoritative) ===
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

  // Fast-path hospital check + ownership verification
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

      // NEW: Authoritative ownership check inside transaction
      if (!hospitalData.ownerEmail || hospitalData.ownerEmail !== ownerEmail) {
        throw new Error('Invalid hospital owner');
      }

      const healCost = hospitalData.customHealCost ?? 50;

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
        healingEndTime: Date.now() + 120000
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

    socket.emit('new-transaction', {
      amount: -actualHealCost,
      description: `Healed at Private Hospital ($${actualHealCost})`,
      balanceAfter: (await patientRef.get()).data().balance
    });

    const freshPatient = await patientRef.get();
    socket.emit('update-stats', freshPatient.data());
    socket.emit('heal-result', { 
      success: true, 
      message: `Healing started for $${actualHealCost} (2 minutes)` 
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

    console.log(`[PRIVATE HEAL] ${patientEmail} paid $${actualHealCost} to ${ownerEmail}`);

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

  // Broadcast to everyone so private healing screens update instantly
  const freshOwnership = await getAllHospitalOwnership(hospitalOwnershipRef);
  (socket.server || socket).emit('hospital-ownership-update', freshOwnership);
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
  handleUpdateHospitalHealCost
};