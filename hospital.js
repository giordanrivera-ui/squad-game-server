const admin = require('firebase-admin');
const { logTransaction, getAvailableBalance } = require('./utils');
const { EFFICIENT_DOCTORS_RESEARCH, ENHANCED_STAMINA_RESEARCH, ENHANCED_CONSTITUTION_RESEARCH, ALLOWED_HOSPITAL_SERVICE_FIELDS } = require('./hospital_constants');
const { handleWatchAdForFasterHealing } = require('./ads');
const { handleStartEfficientDoctorsResearch, handleStartPerformanceResearch, handleClaimEfficientDoctorsResearch, handleClaimPerformanceResearch, catchUpEfficientDoctorsResearch, catchUpPerformanceResearches, getAllHospitalOwnership, getEarliestResearchEndTime } = require('./hospital_research');

// ==================== HELPER: Broadcast hospital ownership update ====================
async function broadcastHospitalOwnership(hospitalOwnershipRef, ioOrSocket) {
  const ownership = await getAllHospitalOwnership(hospitalOwnershipRef);
  (ioOrSocket.server || ioOrSocket).emit('hospital-ownership-update', ownership);
}

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

// ==================== TIMED HEALING (START) ====================
async function handleStartHealing(db, socket) {
  const email = socket.data.email;
  if (!email) return;

  const docRef = db.collection('players').doc(email);
  const doc = await docRef.get();
  if (!doc.exists) return;

  let p = doc.data();

  const maxHp = p.maxHealth || 100;
  if (p.dead === true || (p.health ?? maxHp) <= 0) {
    socket.emit('heal-result', { success: false, message: 'You are dead and cannot heal.' });
    return;
  }

  if (p.healingEndTime && p.healingEndTime > Date.now()) {
    socket.emit('heal-result', { success: false, message: 'You are already healing.' });
    return;
  }

  const cost = 50;
  const availableBalance = getAvailableBalance(p);
  if (availableBalance < cost) {
      socket.emit('heal-result', { 
          success: false, 
          message: 'Not enough money (some funds may be temporarily frozen).' 
      });
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
  p.health = p.maxHealth || 100;
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

  const maxHp = p.maxHealth || 100;
  if (p.dead === true || (p.health ?? maxHp) <= 0) {
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
  const availableBalance = getAvailableBalance(p);
  if (availableBalance < cost) {
      socket.emit('heal-broken-bone-result', { 
          success: false, 
          message: 'Not enough money ($110 required). Some funds may be temporarily frozen.' 
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
    customHealingDuration: 240000,
    customStaminaCost: 150,
    customConstitutionCost: 150,
    hasEfficientDoctors: false,
    efficientDoctorsResearchEndTime: 0,
    hasEnhancedStamina: false,
    enhancedStaminaResearchEndTime: 0,
    hasEnhancedConstitution: false,
    enhancedConstitutionResearchEndTime: 0,
    offerEnhancedStamina: false,
    offerEnhancedConstitution: false,
    selectedEpinephrineQuality: null
  });

  socket.emit('hospital-claim-result', { 
    success: true, 
    message: `You now own the private hospital in ${data.location}!` 
  });

  await broadcastHospitalOwnership(hospitalOwnershipRef, socket);

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
    customStaminaCost: 150,
    customConstitutionCost: 150,
    hasEfficientDoctors: false,
    efficientDoctorsResearchEndTime: 0,
    hasEnhancedStamina: false,
    enhancedStaminaResearchEndTime: 0,
    hasEnhancedConstitution: false,
    enhancedConstitutionResearchEndTime: 0,
    offerEnhancedStamina: false,
    offerEnhancedConstitution: false,
    selectedEpinephrineQuality: null,
  });

  console.log(`[HOSPITAL] ${email} released hospital ${docId}`);

  await broadcastHospitalOwnership(hospitalOwnershipRef, socket);
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

  const allowedFields = ALLOWED_HOSPITAL_SERVICE_FIELDS;

  if (!allowedFields.includes(field)) {
    socket.emit('error', { message: 'Invalid service field.' });
    return;
  }

  if (field === 'offerInjuryHealing' && value === true) {
    const playerDoc = await db.collection('players').doc(email).get();
    
    const playerData = playerDoc.exists ? playerDoc.data() : {};
    const availableBalance = getAvailableBalance(playerData);

    if (availableBalance < 10) {
      socket.emit('error', { 
        message: 'You need at least $10 available balance to enable Injury Healing (maintenance fee).' 
      });
      return;
    }
  }

  await hospitalOwnershipRef.doc(docId).update({ [field]: value });

  console.log(`[HOSPITAL] ${email} updated ${field} on ${docId} → ${value}`);

  await broadcastHospitalOwnership(hospitalOwnershipRef, socket);

  if (field === 'offerInjuryHealing' && value === false) {
    console.log(`[HOSPITAL] Injury Healing turned OFF for ${docId} — maintenance fee stopped`);
  }
}

function startHospitalMaintenanceChecker(db, { onlineSockets, io }) {
  setInterval(async () => {
    try {
      const snapshot = await db.collection('hospitals')
        .where('offerInjuryHealing', '==', true)
        .get();

      if (snapshot.empty) return;

      // Group hospitals by owner for efficient per-owner processing
      const hospitalsByOwner = {};
      for (const doc of snapshot.docs) {
        const h = doc.data();
        if (!h.ownerEmail) continue;

        if (!hospitalsByOwner[h.ownerEmail]) {
          hospitalsByOwner[h.ownerEmail] = [];
        }
        hospitalsByOwner[h.ownerEmail].push({ ref: doc.ref, data: h });
      }

      if (Object.keys(hospitalsByOwner).length === 0) {
        return;
      }

      const hospitalsToDisable = [];

      // Process each owner in its own atomic transaction
      for (const [ownerEmail, ownerHospitals] of Object.entries(hospitalsByOwner)) {
        const ownerRef = db.collection('players').doc(ownerEmail);

        try {
          const txResult = await db.runTransaction(async (transaction) => {
            const ownerSnap = await transaction.get(ownerRef);
            if (!ownerSnap.exists) {
              return { success: false };
            }

            const owner = ownerSnap.data();
            let availableBalance = getAvailableBalance(owner);
            let runningBalance = owner.balance || 0;

            const paidHospitals = [];
            const toDisableThisOwner = [];

            // Sort by fee ascending → pay cheapest hospitals first (maximizes number kept active)
            const hospitalsWithFees = ownerHospitals
              .map(hospital => ({
                ...hospital,
                fee: calculateMaintenanceFee(hospital.data.customHealingDuration || 240000)
              }))
              .sort((a, b) => a.fee - b.fee);

            let totalDeducted = 0;

            for (const hospital of hospitalsWithFees) {
              const fee = hospital.fee;
              if (fee <= 0) continue;

              if (availableBalance >= fee) {
                // Can afford this hospital
                availableBalance -= fee;
                runningBalance -= fee;
                totalDeducted += fee;

                // Create transaction log
                const txRef = ownerRef.collection('transactions').doc();
                transaction.set(txRef, {
                  amount: -fee,
                  description: `Hospital Maintenance - Injury Healing ($${fee})`,
                  balanceAfter: runningBalance,
                  timestamp: admin.firestore.FieldValue.serverTimestamp()
                });

                paidHospitals.push({ fee, balanceAfter: runningBalance });
              } else {
                // Cannot afford → will be disabled after transaction
                toDisableThisOwner.push({
                  ref: hospital.ref,
                  ownerEmail,
                  displayName: owner.displayName || ownerEmail
                });
              }
            }

            // Apply single atomic deduction for all paid hospitals
            if (totalDeducted > 0) {
              transaction.update(ownerRef, {
                balance: admin.firestore.FieldValue.increment(-totalDeducted)
              });
            }

            return {
              success: true,
              displayName: owner.displayName || ownerEmail,
              paidHospitals,
              totalDeducted,
              hospitalsToDisable: toDisableThisOwner
            };
          });

          // === Post-transaction handling ===
          if (txResult.success) {
            if (txResult.totalDeducted > 0) {
              console.log(
                `[HOSPITAL MAINT] $${txResult.totalDeducted} deducted from ${txResult.displayName} ` +
                `(${txResult.paidHospitals.length} hospital${txResult.paidHospitals.length === 1 ? '' : 's'})`
              );
            }

            hospitalsToDisable.push(...txResult.hospitalsToDisable);

            // Send one clean update to the owner
            const socket = onlineSockets.get(txResult.displayName);
            if (socket && txResult.totalDeducted > 0) {
              const freshDoc = await db.collection('players').doc(ownerEmail).get();
              if (freshDoc.exists) {
                socket.emit('update-stats', freshDoc.data());
              }
            }
          }
        } catch (err) {
          console.error(`[HOSPITAL MAINT] Transaction failed for owner ${ownerEmail}:`, err);
        }
      }

      // === Disable hospitals that couldn't be paid for ===
      if (hospitalsToDisable.length > 0) {
        const batch = db.batch();
        for (const item of hospitalsToDisable) {
          batch.update(item.ref, { offerInjuryHealing: false });
        }
        await batch.commit();

        console.log(`[HOSPITAL MAINT] Auto-disabled Injury Healing on ${hospitalsToDisable.length} hospital(s).`);

        await broadcastHospitalOwnership(db.collection('hospitals'), io);

        // Notify affected owners (deduplicated)
        const notifiedOwners = new Set();
        for (const item of hospitalsToDisable) {
          if (notifiedOwners.has(item.ownerEmail)) continue;
          notifiedOwners.add(item.ownerEmail);

          const socket = onlineSockets.get(item.displayName);
          if (socket) {
            socket.emit('error', {
              message: "Injury Healing has been automatically disabled on one or more of your hospitals because you don't have enough money for the maintenance fee(s)."
            });
          }
        }
      }

    } catch (err) {
      console.error('[HOSPITAL MAINT] Critical error in maintenance checker:', err);
    }
  }, 120000);
}

// ==================== PRIVATE HOSPITAL HEALING ====================
async function handleStartPrivateHealing(db, socket, data, { onlineSockets }) {
  const patientEmail = socket.data.email;
  const hospitalDocId = data.hospitalDocId;
  const ownerEmail = data.ownerEmail;

  if (!patientEmail || !hospitalDocId || !ownerEmail) return;

  const patientRef = db.collection('players').doc(patientEmail);
  const ownerRef = db.collection('players').doc(ownerEmail);
  const hospitalRef = db.collection('hospitals').doc(hospitalDocId);

  const patientDocCheck = await patientRef.get();
  if (patientDocCheck.exists) {
    const patientData = patientDocCheck.data();
    const maxHp = patientData.maxHealth || 100;

    if (patientData.dead === true || (patientData.health ?? maxHp) <= 0) {
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
      const maxHp = patient.maxHealth || 100;

      if (patient.healingEndTime && patient.healingEndTime > Date.now()) {
        throw new Error('Already healing');
      }

      if (patient.dead === true || (patient.health ?? maxHp) <= 0) {
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
      const healingDuration = hospitalData.customHealingDuration ?? 240000;

      const ownerDoc = await transaction.get(ownerRef);
      if (!ownerDoc.exists) return;

      const owner = ownerDoc.data();

      const availableBalance = getAvailableBalance(patient);
      if (availableBalance < healCost) {
        throw new Error('Not enough money');
      }

      const newPatientBalance = (patient.balance || 0) - healCost;
      const newOwnerBalance = (owner.balance || 0) + healCost;

      transaction.update(patientRef, {
        balance: newPatientBalance,
        healingEndTime: Date.now() + healingDuration
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

  p.health = p.maxHealth || 100;
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

  await broadcastHospitalOwnership(hospitalOwnershipRef, socket);
}

// ==================== UPDATE CUSTOM STAMINA COST ====================
async function handleUpdateHospitalStaminaCost(socket, data, { hospitalOwnershipRef }) {
  const email = socket.data.email;
  const { docId, newCost } = data;

  if (!email || !docId || typeof newCost !== 'number' || newCost < 1) {
    socket.emit('error', { message: 'Invalid stamina cost.' });
    return;
  }

  const hospitalDoc = await hospitalOwnershipRef.doc(docId).get();
  if (!hospitalDoc.exists) return;

  const hospitalData = hospitalDoc.data();
  if (hospitalData.ownerEmail !== email) {
    socket.emit('error', { message: 'You do not own this hospital.' });
    return;
  }

  await hospitalOwnershipRef.doc(docId).update({ customStaminaCost: newCost });

  console.log(`[HOSPITAL] ${email} changed Stamina cost of ${docId} to $${newCost}`);

  await broadcastHospitalOwnership(hospitalOwnershipRef, socket);
}

// ==================== UPDATE CUSTOM CONSTITUTION COST ====================
async function handleUpdateHospitalConstitutionCost(socket, data, { hospitalOwnershipRef }) {
  const email = socket.data.email;
  const { docId, newCost } = data;

  if (!email || !docId || typeof newCost !== 'number' || newCost < 1) {
    socket.emit('error', { message: 'Invalid constitution cost.' });
    return;
  }

  const hospitalDoc = await hospitalOwnershipRef.doc(docId).get();
  if (!hospitalDoc.exists) return;

  const hospitalData = hospitalDoc.data();
  if (hospitalData.ownerEmail !== email) {
    socket.emit('error', { message: 'You do not own this hospital.' });
    return;
  }

  await hospitalOwnershipRef.doc(docId).update({ customConstitutionCost: newCost });

  console.log(`[HOSPITAL] ${email} changed Constitution cost of ${docId} to $${newCost}`);

  await broadcastHospitalOwnership(hospitalOwnershipRef, socket);
}

// ==================== UPDATE CUSTOM HEALING DURATION ====================
async function handleUpdateHospitalHealingDuration(socket, data, { hospitalOwnershipRef }) {
  const email = socket.data.email;
  const { docId, healingDurationMs } = data;

  if (!email || !docId || typeof healingDurationMs !== 'number') {
    socket.emit('error', { message: 'Invalid healing duration.' });
    return;
  }

  const hospitalDoc = await hospitalOwnershipRef.doc(docId).get();
  if (!hospitalDoc.exists) return;

  const hospitalData = hospitalDoc.data();

  if (hospitalData.ownerEmail !== email) {
    socket.emit('error', { message: 'You do not own this hospital.' });
    return;
  }

  const hasEfficientDoctors = hospitalData.hasEfficientDoctors === true;
  const minAllowed = hasEfficientDoctors ? 120000 : 180000;

  if (healingDurationMs < minAllowed || healingDurationMs > 240000) {
    socket.emit('error', { 
      message: hasEfficientDoctors 
        ? 'Healing duration must be between 2:00 and 4:00.' 
        : 'Healing duration must be between 3:00 and 4:00.' 
    });
    return;
  }

  await hospitalOwnershipRef.doc(docId).update({ 
    customHealingDuration: healingDurationMs 
  });

  console.log(`[HOSPITAL] ${email} changed healing duration of ${docId} to ${healingDurationMs} ms`);

  await broadcastHospitalOwnership(hospitalOwnershipRef, socket);
}

// ==================== HOSPITAL RESEARCH COMPLETION CHECKER ====================
function startHospitalResearchChecker(db, { io }) {
  setInterval(async () => {
    try {
      const now = Date.now();

      const snapshot = await db.collection('hospitals')
        .where('nextResearchEndTime', '<=', now)
        .get();

      if (snapshot.empty) {
        return;
      }

      const batch = db.batch();
      let completedCount = 0;

      for (const doc of snapshot.docs) {
        const h = doc.data();
        let updates = {};

        if (h.efficientDoctorsResearchEndTime > 0 && h.efficientDoctorsResearchEndTime <= now) {
          updates.hasEfficientDoctors = true;
          updates.efficientDoctorsResearchEndTime = 0;
        }

        if (h.enhancedStaminaResearchEndTime > 0 && h.enhancedStaminaResearchEndTime <= now) {
          updates.hasEnhancedStamina = true;
          updates.enhancedStaminaResearchEndTime = 0;
        }

        if (h.enhancedConstitutionResearchEndTime > 0 && h.enhancedConstitutionResearchEndTime <= now) {
          updates.hasEnhancedConstitution = true;
          updates.enhancedConstitutionResearchEndTime = 0;
        }

        if (Object.keys(updates).length > 0) {
          const newNextTime = getEarliestResearchEndTime({ ...h, ...updates });
          updates.nextResearchEndTime = newNextTime;

          batch.update(doc.ref, updates);
          completedCount++;
        }
      }

      if (completedCount > 0) {
        await batch.commit();
        console.log(`[HOSPITAL RESEARCH] Auto-completed ${completedCount} research(es)`);

        await broadcastHospitalOwnership(db.collection('hospitals'), io);
      }

    } catch (e) {
      console.error('Hospital research checker error:', e);
    }
  }, 5000);
}

// ==================== ENHANCED STAMINA SERVICE ====================
async function handlePurchaseEnhancedStamina(db, socket, data, { onlineSockets }) {
  const patientEmail = socket.data.email;
  const hospitalDocId = data.hospitalDocId;
  const ownerEmail = data.ownerEmail;

  if (!patientEmail || !hospitalDocId || !ownerEmail) return;

  const patientRef = db.collection('players').doc(patientEmail);
  const ownerRef = db.collection('players').doc(ownerEmail);
  const hospitalRef = db.collection('hospitals').doc(hospitalDocId);

  let buffDurationMinutes = 5;

  try {
    await db.runTransaction(async (transaction) => {
      const patientDoc = await transaction.get(patientRef);
      if (!patientDoc.exists) throw new Error('Player not found');

      const patient = patientDoc.data();

      if (patient.enhancedStaminaEndTime && patient.enhancedStaminaEndTime > Date.now()) {
        throw new Error('Enhanced Stamina is already active');
      }

      const hospitalDoc = await transaction.get(hospitalRef);
      if (!hospitalDoc.exists) throw new Error('Hospital not found');

      const hospitalData = hospitalDoc.data();

      if (!hospitalData.offerEnhancedStamina) {
        throw new Error('This hospital is not offering Enhanced Stamina');
      }

      const cost = hospitalData.customStaminaCost ?? 150;

      const availableBalance = getAvailableBalance(patient);
      if (availableBalance < cost) {
        throw new Error('Not enough money');
      }

      const ownerDoc = await transaction.get(ownerRef);
      if (!ownerDoc.exists) throw new Error('Hospital owner not found');

      const owner = ownerDoc.data();

      const newPatientBalance = (patient.balance || 0) - cost;
      const newOwnerBalance = (owner.balance || 0) + cost;

      const selectedQuality = hospitalData.selectedEpinephrineQuality;

      if (selectedQuality && selectedQuality >= 1 && selectedQuality <= 5) {
        const ownerInventory = owner.inventory || [];
        const index = ownerInventory.findIndex(item =>
          item.name === "Epinephrine solution" && item.quality === selectedQuality
        );

        if (index !== -1) {
          if (selectedQuality === 1) buffDurationMinutes = 6;
          else if (selectedQuality === 2) buffDurationMinutes = 7;
          else if (selectedQuality === 3) buffDurationMinutes = 8;
          else if (selectedQuality === 4) buffDurationMinutes = 10;
          else if (selectedQuality === 5) buffDurationMinutes = 12;

          ownerInventory.splice(index, 1);
          transaction.update(ownerRef, { inventory: ownerInventory });
        }
      }

      const buffEndTime = Date.now() + (buffDurationMinutes * 60 * 1000);

      transaction.update(patientRef, {
        balance: newPatientBalance,
        enhancedStaminaEndTime: buffEndTime
      });

      transaction.update(ownerRef, {
        balance: newOwnerBalance
      });

      const patientTxRef = patientRef.collection('transactions').doc();
      transaction.set(patientTxRef, {
        amount: -cost,
        description: `Purchased Enhanced Stamina (${hospitalData.location})`,
        balanceAfter: newPatientBalance,
        timestamp: admin.firestore.FieldValue.serverTimestamp()
      });

      const ownerTxRef = ownerRef.collection('transactions').doc();
      transaction.set(ownerTxRef, {
        amount: cost,
        description: `Enhanced Stamina Service Fee`,
        balanceAfter: newOwnerBalance,
        timestamp: admin.firestore.FieldValue.serverTimestamp()
      });
    });

    const freshPatient = await patientRef.get();
    const freshOwnerDoc = await ownerRef.get();
    const ownerData = freshOwnerDoc.data();

    socket.emit('update-stats', freshPatient.data());

    const ownerSocket = onlineSockets.get(ownerData.displayName);
    if (ownerSocket) {
      ownerSocket.emit('update-stats', ownerData);
    }

    socket.emit('enhanced-stamina-purchased', { 
      success: true, 
      message: `Enhanced Stamina activated! -3s cooldown for ${buffDurationMinutes} minutes.` 
    });

  } catch (error) {
    console.error('Enhanced Stamina purchase error:', error.message);
    socket.emit('enhanced-stamina-purchased', { 
      success: false, 
      message: error.message 
    });
  }
}

// ==================== SET SELECTED EPINEPHRINE QUALITY ====================
async function handleSetSelectedEpinephrineQuality(socket, data, { hospitalOwnershipRef }) {
  const email = socket.data.email;
  const { hospitalDocId, quality } = data;

  if (!email || !hospitalDocId) return;

  const hospitalRef = hospitalOwnershipRef.doc(hospitalDocId);
  const hospitalDoc = await hospitalRef.get();

  if (!hospitalDoc.exists) return;

  const hospitalData = hospitalDoc.data();

  if (hospitalData.ownerEmail !== email) {
    socket.emit('error', { message: 'You do not own this hospital.' });
    return;
  }

  await hospitalRef.update({
    selectedEpinephrineQuality: quality || null
  });

  console.log(`[HOSPITAL] ${email} set selected Epinephrine quality to ${quality} on ${hospitalDocId}`);

  await broadcastHospitalOwnership(hospitalOwnershipRef, socket);
}

function registerHospitalHandlers(socket, deps) {
  const {db, hospitalOwnershipRef, onlineSockets, ENHANCED_STAMINA_RESEARCH, ENHANCED_CONSTITUTION_RESEARCH } = deps;

  socket.on('heal-broken-bone', async () => { await handleHealBrokenBone(db, socket); });
  socket.on('start-healing', async () => { await handleStartHealing(db, socket); });
  socket.on('watch-ad-for-faster-healing', async () => { await handleWatchAdForFasterHealing(db, socket); });
  socket.on('claim-healing', async () => { await handleClaimHealing(db, socket); });
  socket.on('claim-hospital', (data) => handleClaimHospital(socket, data, { hospitalOwnershipRef }));
  socket.on('release-hospital', (data) => handleReleaseHospital(socket, data, { hospitalOwnershipRef }));
  socket.on('update-hospital-service', (data) => handleUpdateHospitalService(socket, data, { hospitalOwnershipRef, db }));
  socket.on('start-private-healing', async (data) => { await handleStartPrivateHealing(db, socket, data, { onlineSockets });});
  socket.on('claim-private-healing', async () => { await handleClaimPrivateHealing(db, socket); });
  socket.on('update-hospital-heal-cost', (data) => handleUpdateHospitalHealCost(socket, data, { hospitalOwnershipRef }));
  socket.on('update-hospital-healing-duration', (data) => handleUpdateHospitalHealingDuration(socket, data, { hospitalOwnershipRef }));
  socket.on('start-efficient-doctors-research', async (data) => { await handleStartEfficientDoctorsResearch(db, socket, data.hospitalDocId); });
  socket.on('claim-efficient-doctors-research', async (data) => { await handleClaimEfficientDoctorsResearch(db, socket, data.hospitalDocId); });
  socket.on('start-enhanced-stamina-research', async (data) => { await handleStartPerformanceResearch(
      db, socket, data.hospitalDocId, 
      ENHANCED_STAMINA_RESEARCH, 
      'hasEnhancedStamina', 
      'enhancedStaminaResearchEndTime', 
      'Enhanced Stamina'); });

  socket.on('claim-enhanced-stamina-research', async (data) => { 
    await handleClaimPerformanceResearch(
      db, socket, data.hospitalDocId, 
      'hasEnhancedStamina', 
      'enhancedStaminaResearchEndTime', 
      'Enhanced Stamina'
    ); 
  });

  socket.on('start-enhanced-constitution-research', async (data) => { 
    await handleStartPerformanceResearch( db, socket, data.hospitalDocId, 
      ENHANCED_CONSTITUTION_RESEARCH, 'hasEnhancedConstitution', 
      'enhancedConstitutionResearchEndTime', 'Enhanced Constitution'); });
  socket.on('claim-enhanced-constitution-research', async (data) => { await handleClaimPerformanceResearch( db, socket, data.hospitalDocId, 'hasEnhancedConstitution', 'enhancedConstitutionResearchEndTime', 'Enhanced Constitution'); });
  socket.on('update-hospital-stamina-cost', (data) => handleUpdateHospitalStaminaCost(socket, data, { hospitalOwnershipRef }));
  socket.on('update-hospital-constitution-cost', (data) => handleUpdateHospitalConstitutionCost(socket, data, { hospitalOwnershipRef }));
  socket.on('purchase-enhanced-stamina', async (data) => { await handlePurchaseEnhancedStamina(db, socket, data, { onlineSockets }); });
  socket.on('set-selected-epinephrine-quality', (data) => handleSetSelectedEpinephrineQuality(socket, data, { hospitalOwnershipRef }));
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
  startHospitalResearchChecker,
  catchUpEfficientDoctorsResearch,
  calculateMaintenanceFee,
  handleStartPerformanceResearch,
  handleClaimPerformanceResearch,
  catchUpPerformanceResearches,
  handleUpdateHospitalStaminaCost,
  handleUpdateHospitalConstitutionCost,
  handlePurchaseEnhancedStamina,
  handleSetSelectedEpinephrineQuality,
  ENHANCED_STAMINA_RESEARCH,
  ENHANCED_CONSTITUTION_RESEARCH,
  registerHospitalHandlers,
};