/**
 * HealingService – public healing, private hospital healing, broken-bone,
 * ad reduction, and claim handlers.
 * Every cost, duration, message and security check is identical to the original.
 */

const admin = require('firebase-admin');
const { logTransaction, getAvailableBalance } = require('../../utils');
const {
  PUBLIC_HEAL_COST,
  PUBLIC_HEAL_DURATION_MS,
  AD_REDUCED_HEAL_DURATION_MS,
  BROKEN_BONE_COST,
  BROKEN_BONE_LOCATION,
  DEFAULT_PRIVATE_HEAL_COST,
  DEFAULT_PRIVATE_HEAL_DURATION_MS,
  EPINEPHRINE_DURATION_MINUTES,
  DEFAULT_ENHANCED_STAMINA_MINUTES
} = require('../../hospital_constants');
const { hospitalRepository } = require('./HospitalRepository');

class HealingService {
  // ==================== PUBLIC HEALING ====================
  async startPublicHealing(db, socket) {
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

    const availableBalance = getAvailableBalance(p);
    if (availableBalance < PUBLIC_HEAL_COST) {
      socket.emit('heal-result', {
        success: false,
        message: 'Not enough money (some funds may be temporarily frozen).'
      });
      return;
    }

    await logTransaction(socket, -PUBLIC_HEAL_COST, 'Started Healing ($50)', p, docRef);

    p.balance -= PUBLIC_HEAL_COST;
    p.usedAdForHealing = false;
    p.healingEndTime = Date.now() + PUBLIC_HEAL_DURATION_MS;

    await docRef.set(p);
    socket.emit('update-stats', p);
    socket.emit('heal-result', {
      success: true,
      message: 'Healing started... (6 minutes remaining)'
    });
  }

  async claimPublicHealing(db, socket) {
    const email = socket.data.email;
    if (!email) return;

    const docRef = db.collection('players').doc(email);
    const doc = await docRef.get();
    if (!doc.exists) return;

    let p = doc.data();

    // CRITICAL SECURITY CHECK – exact original
    if (!p.healingEndTime || p.healingEndTime > Date.now()) {
      socket.emit('heal-result', { success: false, message: 'Healing is not finished yet.' });
      return;
    }

    p.health = p.maxHealth || 100;
    p.healingEndTime = 0;

    await docRef.set(p);
    socket.emit('update-stats', p);
    socket.emit('heal-result', {
      success: true,
      message: '✅ You are now fully healed!'
    });
  }

  // ==================== AD REDUCTION (public only) ====================
  async watchAdForFasterHealing(db, socket) {
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

    const newHealingEndTime = Date.now() + AD_REDUCED_HEAL_DURATION_MS;

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

  // ==================== BROKEN BONE ====================
  async healBrokenBone(db, socket) {
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

    if (p.location !== BROKEN_BONE_LOCATION) {
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

    const availableBalance = getAvailableBalance(p);
    if (availableBalance < BROKEN_BONE_COST) {
      socket.emit('heal-broken-bone-result', {
        success: false,
        message: 'Not enough money ($110 required). Some funds may be temporarily frozen.'
      });
      return;
    }

    await logTransaction(socket, -BROKEN_BONE_COST, 'Broken Bone Healing ($110)', p, docRef);
    p.balance -= BROKEN_BONE_COST;
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

  // ==================== PRIVATE HOSPITAL HEALING ====================
  async startPrivateHealing(db, socket, data, { onlineSockets }) {
    const patientEmail = socket.data.email;
    const hospitalDocId = data.hospitalDocId;
    const ownerEmail = data.ownerEmail;

    if (!patientEmail || !hospitalDocId || !ownerEmail) return;

    const patientRef = db.collection('players').doc(patientEmail);
    const ownerRef = db.collection('players').doc(ownerEmail);
    const hospitalRef = db.collection('hospitals').doc(hospitalDocId);

    // Pre-checks (exact original)
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

        const healCost = hospitalData.customHealCost ?? DEFAULT_PRIVATE_HEAL_COST;
        const healingDuration = hospitalData.customHealingDuration ?? DEFAULT_PRIVATE_HEAL_DURATION_MS;

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

      // Post-transaction notifications (exact original)
      const freshHospital = await hospitalRef.get();
      const actualHealCost = freshHospital.exists
        ? (freshHospital.data().customHealCost ?? DEFAULT_PRIVATE_HEAL_COST)
        : DEFAULT_PRIVATE_HEAL_COST;

      const actualDurationMs = freshHospital.exists
        ? (freshHospital.data().customHealingDuration ?? DEFAULT_PRIVATE_HEAL_DURATION_MS)
        : DEFAULT_PRIVATE_HEAL_DURATION_MS;

      const durationMinutes = Math.floor(actualDurationMs / 60000);
      const durationSeconds = Math.floor((actualDurationMs % 60000) / 1000);
      const durationText = durationSeconds > 0
        ? `${durationMinutes}:${durationSeconds.toString().padStart(2, '0')}`
        : `${durationMinutes} minutes`;

      const freshPatient = await patientRef.get();
      socket.emit('new-transaction', {
        amount: -actualHealCost,
        description: `Healed at Private Hospital ($${actualHealCost})`,
        balanceAfter: freshPatient.data().balance
      });
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

      console.log(
        `[PRIVATE HEAL] ${patientEmail} paid $${actualHealCost} to ${ownerEmail} — duration: ${actualDurationMs}ms`
      );
    } catch (error) {
      console.error('Private healing error:', error);

      if (error.message === 'Not enough money') {
        const freshHospital = await hospitalRef.get();
        const actualHealCost = freshHospital.exists
          ? (freshHospital.data().customHealCost ?? DEFAULT_PRIVATE_HEAL_COST)
          : DEFAULT_PRIVATE_HEAL_COST;

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

  async claimPrivateHealing(db, socket) {
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

  // ==================== ENHANCED STAMINA PURCHASE ====================
  async purchaseEnhancedStamina(db, socket, data, { onlineSockets }) {
    const patientEmail = socket.data.email;
    const hospitalDocId = data.hospitalDocId;
    const ownerEmail = data.ownerEmail;

    if (!patientEmail || !hospitalDocId || !ownerEmail) return;

    const patientRef = db.collection('players').doc(patientEmail);
    const ownerRef = db.collection('players').doc(ownerEmail);
    const hospitalRef = db.collection('hospitals').doc(hospitalDocId);

    let buffDurationMinutes = DEFAULT_ENHANCED_STAMINA_MINUTES;

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
            buffDurationMinutes = EPINEPHRINE_DURATION_MINUTES[selectedQuality] || DEFAULT_ENHANCED_STAMINA_MINUTES;
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
}

const healingService = new HealingService();

module.exports = {
  HealingService,
  healingService
};
