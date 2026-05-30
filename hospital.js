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

  await hospitalOwnershipRef.doc(docId).update({
    ownerEmail: email,
    ownerDisplayName: displayName,
    claimedAt: Date.now(),
    offerInjuryHealing: false,
    offerOrthopedicServices: false,
    offerPerformanceTherapy: false,
    offerDiseaseTherapy: false
  });

  socket.emit('hospital-claim-result', { 
    success: true, 
    message: `You now own the private hospital in ${data.location}!` 
  });

  const freshOwnership = await getAllHospitalOwnership(hospitalOwnershipRef);
  socket.server?.emit || socket.emit('hospital-ownership-update', freshOwnership);
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
    claimedAt: null
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

  console.log(`[HOSPITAL] ${email} updated ${field} on ${docId}`);

  const freshOwnership = await getAllHospitalOwnership(hospitalOwnershipRef);
  (socket.server || socket).emit('hospital-ownership-update', freshOwnership);
}

// ==================== EXPORTS ====================
module.exports = {
  handleStartHealing,
  handleClaimHealing,
  handleHealBrokenBone,
  handleClaimHospital,
  handleReleaseHospital,
  handleUpdateHospitalService
};