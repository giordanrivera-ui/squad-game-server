const admin = require('firebase-admin');
const { logTransaction } = require('./utils');
const { EFFICIENT_DOCTORS_RESEARCH, ENHANCED_STAMINA_RESEARCH, ENHANCED_CONSTITUTION_RESEARCH } = require('./hospital_constants');
const { 
  scheduleHospitalResearch, 
  cancelHospitalResearchTimers, 
  catchUpActiveHospitalResearches,
  RESEARCH_TYPES 
} = require('./hospital_research_timers');

// ==================== SAFE HELPER FUNCTION ====================
function getEarliestResearchEndTime(hospitalData) {
  const times = [
    hospitalData.efficientDoctorsResearchEndTime,
    hospitalData.enhancedStaminaResearchEndTime,
    hospitalData.enhancedConstitutionResearchEndTime
  ].filter(t => typeof t === 'number' && t > 0);

  if (times.length === 0) return null;
  return Math.min(...times);
}

// ==================== START RESEARCH ====================
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

    const playerRef = db.collection('players').doc(email);
    const playerDoc = await playerRef.get();
    if (!playerDoc.exists || (playerDoc.data().balance || 0) < EFFICIENT_DOCTORS_RESEARCH.cost) {
      socket.emit('research-result', { success: false, message: 'Not enough money ($1000 required).' });
      return;
    }

    const playerData = playerDoc.data();

    await logTransaction(socket, -EFFICIENT_DOCTORS_RESEARCH.cost, 'Researched: Efficient Doctors', playerData, playerRef);

    await playerRef.update({
      balance: admin.firestore.FieldValue.increment(-EFFICIENT_DOCTORS_RESEARCH.cost)
    });

    const completionTime = Date.now() + EFFICIENT_DOCTORS_RESEARCH.durationMs;

    // ==================== Calculate correct nextResearchEndTime ====================
    const updatedHospital = {
      ...hospitalData,
      efficientDoctorsResearchEndTime: completionTime
    };
    const newNextTime = getEarliestResearchEndTime(updatedHospital);

    await hospitalRef.update({
      efficientDoctorsResearchEndTime: completionTime,
      nextResearchEndTime: newNextTime
    });
    // ====================================================================================

    scheduleHospitalResearch(db, hospitalDocId, RESEARCH_TYPES.EFFICIENT_DOCTORS, completionTime, socket.server || socket);

    const freshPlayer = await playerRef.get();
    socket.emit('update-stats', freshPlayer.data());
    socket.emit('research-result', {
      success: true,
      message: `🔬 Researching Efficient Doctors... (30 seconds)`
    });

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

async function handleStartPerformanceResearch(db, socket, hospitalDocId, researchConfig, hasField, endTimeField, researchName) {
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

    if (hospitalData[hasField] === true) {
      socket.emit('research-result', { success: false, message: `${researchName} already researched.` });
      return;
    }

    if (hospitalData[endTimeField] && hospitalData[endTimeField] > Date.now()) {
      socket.emit('research-result', { success: false, message: 'Research already in progress.' });
      return;
    }

    const playerRef = db.collection('players').doc(email);
    const playerDoc = await playerRef.get();
    if (!playerDoc.exists || (playerDoc.data().balance || 0) < researchConfig.cost) {
      socket.emit('research-result', { success: false, message: 'Not enough money ($1000 required).' });
      return;
    }

    const playerData = playerDoc.data();

    await logTransaction(socket, -researchConfig.cost, `Researched: ${researchName}`, playerData, playerRef);

    await playerRef.update({
      balance: admin.firestore.FieldValue.increment(-researchConfig.cost)
    });

    const completionTime = Date.now() + researchConfig.durationMs;

    // ==================== Calculate correct nextResearchEndTime ====================
    const updatedHospital = {
      ...hospitalData,
      [endTimeField]: completionTime
    };
    const newNextTime = getEarliestResearchEndTime(updatedHospital);

    await hospitalRef.update({
      [endTimeField]: completionTime,
      nextResearchEndTime: newNextTime
    });
    // ====================================================================================

        // Safer way to decide which research type this is
    let researchTypeKey;
    if (endTimeField === 'enhancedStaminaResearchEndTime') {
      researchTypeKey = RESEARCH_TYPES.ENHANCED_STAMINA;
    } else if (endTimeField === 'enhancedConstitutionResearchEndTime') {
      researchTypeKey = RESEARCH_TYPES.ENHANCED_CONSTITUTION;
    } else {
      console.error(`[RESEARCH BUG] Unknown research type: ${researchName}`);
      return; // Stop here so we don't schedule a broken timer
    }

    scheduleHospitalResearch(db, hospitalDocId, researchTypeKey, completionTime, socket.server || socket);

    const freshPlayer = await playerRef.get();
    socket.emit('update-stats', freshPlayer.data());
    socket.emit('research-result', {
      success: true,
      message: `🔬 Researching ${researchName}... (30 seconds)`
    });

    const freshOwnership = await getAllHospitalOwnership(db.collection('hospitals'));
    (socket.server || socket).emit('hospital-ownership-update', freshOwnership);

    console.log(`[HOSPITAL RESEARCH] ${email} started ${researchName} research on ${hospitalDocId}`);

  } catch (error) {
    console.error('[RESEARCH ERROR]', error);
    socket.emit('research-result', {
      success: false,
      message: 'Something went wrong while starting research. Please try again.'
    });
  }
}

// ==================== CLAIM RESEARCH ====================
async function handleClaimEfficientDoctorsResearch(db, socket, hospitalDocId) {
  const email = socket.data.email;
  if (!email || !hospitalDocId) return;

  const hospitalRef = db.collection('hospitals').doc(hospitalDocId);
  const hospitalDoc = await hospitalRef.get();
  if (!hospitalDoc.exists) return;

  const hospitalData = hospitalDoc.data();
  if (hospitalData.ownerEmail !== email) return;

  if (!hospitalData.efficientDoctorsResearchEndTime || hospitalData.efficientDoctorsResearchEndTime > Date.now()) {
    
    // If the research is already finished (completed by timer), tell the player nicely
    if (hospitalData.hasEfficientDoctors === true) {
      cancelHospitalResearchTimers(hospitalDocId);
        socket.emit('research-result', {
            success: true,
            message: '✅ Efficient Doctors research already completed automatically!'
        });
    }
    return;
}

  await hospitalRef.update({
    hasEfficientDoctors: true,
    efficientDoctorsResearchEndTime: 0
  });

  // Recalculate next research time
  const freshHospital = await hospitalRef.get();
  const newNextTime = getEarliestResearchEndTime(freshHospital.data());
  await hospitalRef.update({ nextResearchEndTime: newNextTime });

  console.log(`[HOSPITAL RESEARCH] ${email} completed Efficient Doctors research on ${hospitalDocId}`);

  const freshOwnership = await getAllHospitalOwnership(db.collection('hospitals'));
  (socket.server || socket).emit('hospital-ownership-update', freshOwnership);

  socket.emit('research-result', {
    success: true,
    message: '✅ Efficient Doctors research complete! Minimum healing time is now 2:00.'
  });
}

async function handleClaimPerformanceResearch(db, socket, hospitalDocId, hasField, endTimeField, researchName) {
  const email = socket.data.email;
  if (!email || !hospitalDocId) return;

  const hospitalRef = db.collection('hospitals').doc(hospitalDocId);
  const hospitalDoc = await hospitalRef.get();
  if (!hospitalDoc.exists) return;

  const hospitalData = hospitalDoc.data();
  if (hospitalData.ownerEmail !== email) return;

  if (!hospitalData[endTimeField] || hospitalData[endTimeField] > Date.now()) {
    
    // If the research is already finished (completed by the timer), 
    // tell the player a clear message instead of doing nothing
    if (hospitalData[hasField] === true) {
        cancelHospitalResearchTimers(hospitalDocId);
        socket.emit('research-result', {
            success: true,
            message: `✅ ${researchName} research already completed automatically!`
        });
    }
    return;
}

  await hospitalRef.update({
    [hasField]: true,
    [endTimeField]: 0
  });

  // Recalculate next research time
  const freshHospital = await hospitalRef.get();
  const newNextTime = getEarliestResearchEndTime(freshHospital.data());
  await hospitalRef.update({ nextResearchEndTime: newNextTime });

  console.log(`[HOSPITAL RESEARCH] ${email} completed ${researchName} research on ${hospitalDocId}`);

  const freshOwnership = await getAllHospitalOwnership(db.collection('hospitals'));
  (socket.server || socket).emit('hospital-ownership-update', freshOwnership);

  socket.emit('research-result', {
    success: true,
    message: `✅ ${researchName} research complete!`
  });
}

// ==================== CATCH-UP FUNCTIONS ====================
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
      const h = doc.data();

      // Finish the research
      batch.update(doc.ref, {
        hasEfficientDoctors: true,
        efficientDoctorsResearchEndTime: 0
      });

      // IMPORTANT: Recalculate nextResearchEndTime after finishing
      const updatedData = { ...h, efficientDoctorsResearchEndTime: 0 };
      const newNextTime = getEarliestResearchEndTime(updatedData);
      batch.update(doc.ref, { nextResearchEndTime: newNextTime });
    }
    await batch.commit();

    console.log(`[HOSPITAL RESEARCH] Caught up and completed ${overdue.size} overdue Efficient Doctors research(es) on startup`);

    const freshOwnership = await getAllHospitalOwnership(db.collection('hospitals'));
    io.emit('hospital-ownership-update', freshOwnership);

  } catch (e) {
    console.error('Catch-up research error on startup:', e);
  }
}

async function catchUpPerformanceResearches(db, { io }) {
  try {
    const now = Date.now();
    const batch = db.batch();
    let totalCompleted = 0;

    // === Stamina Research ===
    const overdueStamina = await db.collection('hospitals')
      .where('enhancedStaminaResearchEndTime', '>', 0)
      .where('enhancedStaminaResearchEndTime', '<=', now)
      .get();

    for (const doc of overdueStamina.docs) {
      const h = doc.data();

      batch.update(doc.ref, {
        hasEnhancedStamina: true,
        enhancedStaminaResearchEndTime: 0
      });

      // Recalculate nextResearchEndTime
      const updatedData = { ...h, enhancedStaminaResearchEndTime: 0 };
      const newNextTime = getEarliestResearchEndTime(updatedData);
      batch.update(doc.ref, { nextResearchEndTime: newNextTime });

      totalCompleted++;
    }

    // === Constitution Research ===
    const overdueConstitution = await db.collection('hospitals')
      .where('enhancedConstitutionResearchEndTime', '>', 0)
      .where('enhancedConstitutionResearchEndTime', '<=', now)
      .get();

    for (const doc of overdueConstitution.docs) {
      const h = doc.data();

      batch.update(doc.ref, {
        hasEnhancedConstitution: true,
        enhancedConstitutionResearchEndTime: 0
      });

      // Recalculate nextResearchEndTime
      const updatedData = { ...h, enhancedConstitutionResearchEndTime: 0 };
      const newNextTime = getEarliestResearchEndTime(updatedData);
      batch.update(doc.ref, { nextResearchEndTime: newNextTime });

      totalCompleted++;
    }

    if (totalCompleted > 0) {
      await batch.commit();
      console.log(`[HOSPITAL RESEARCH] Caught up and completed ${totalCompleted} overdue Performance research(es) on startup`);

      const freshOwnership = await getAllHospitalOwnership(db.collection('hospitals'));
      io.emit('hospital-ownership-update', freshOwnership);
    }

  } catch (e) {
    console.error('Catch-up performance research error on startup:', e);
  }
}

async function getAllHospitalOwnership(hospitalOwnershipRef) {
  const snapshot = await hospitalOwnershipRef.get();
  const ownership = {};
  snapshot.docs.forEach(doc => {
    ownership[doc.id] = doc.data();
  });
  return ownership;
}

module.exports = {
  handleStartEfficientDoctorsResearch,
  handleStartPerformanceResearch,
  handleClaimEfficientDoctorsResearch,
  handleClaimPerformanceResearch,
  getAllHospitalOwnership,
  getEarliestResearchEndTime
};