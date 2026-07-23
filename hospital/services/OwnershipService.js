/**
 * OwnershipService – claim, release, service toggles, custom costs/durations,
 * epinephrine quality selection.
 * All validation rules and messages match the original exactly.
 */

const { getAvailableBalance } = require('../../utils');
const {
  ALLOWED_HOSPITAL_SERVICE_FIELDS,
  DEFAULT_PRIVATE_HEAL_COST,
  DEFAULT_PRIVATE_HEAL_DURATION_MS
} = require('../../hospital_constants');
const { hospitalRepository } = require('./HospitalRepository');
const { timerService } = require('./TimerService');

class OwnershipService {
  async claimHospital(socket, data) {
    const email = socket.data.email;
    const displayName = socket.data.displayName;

    if (!email || !displayName || typeof data.location !== 'string' || typeof data.index !== 'number') {
      socket.emit('hospital-claim-result', { success: false, message: 'Invalid request.' });
      return;
    }

    const docId = `${data.location}-hospital-${data.index}`;
    const hospital = hospitalRepository.get(docId);

    if (!hospital) {
      socket.emit('hospital-claim-result', { success: false, message: 'Hospital does not exist.' });
      return;
    }

    if (hospital.isPublic) {
      socket.emit('hospital-claim-result', { success: false, message: 'Public hospitals cannot be claimed.' });
      return;
    }

    if (hospital.ownerEmail) {
      socket.emit('hospital-claim-result', { success: false, message: 'This hospital is already owned.' });
      return;
    }

    // Claim it (exact original defaults)
    timerService.cancelAllForHospital(docId);

    await hospitalRepository.update(docId, (h) => {
      h.applyClaim(email, displayName);
    });

    socket.emit('hospital-claim-result', {
      success: true,
      message: `You now own the private hospital in ${data.location}!`
    });

    console.log(`[HOSPITAL] ${displayName} claimed ${docId} — broadcast sent to all players`);
  }

  async releaseHospital(socket, data) {
    const email = socket.data.email;
    const { docId } = data;
    if (!email || !docId) return;

    timerService.cancelAllForHospital(docId);

    const hospital = hospitalRepository.get(docId);
    if (!hospital) return;

    if (!hospital.isOwnedBy(email)) {
      socket.emit('error', { message: 'You do not own this hospital.' });
      return;
    }

    await hospitalRepository.update(docId, (h) => {
      h.applyRelease();
    });

    console.log(`[HOSPITAL] ${email} released hospital ${docId}`);
  }

  async updateHospitalService(socket, data, { db }) {
    const email = socket.data.email;
    const { docId, field, value } = data;

    if (!email || !docId || !field || typeof value !== 'boolean') {
      socket.emit('error', { message: 'Invalid hospital service update.' });
      return;
    }

    const hospital = hospitalRepository.get(docId);
    if (!hospital) return;

    if (!hospital.isOwnedBy(email)) {
      socket.emit('error', { message: 'You do not own this hospital.' });
      return;
    }

    if (!ALLOWED_HOSPITAL_SERVICE_FIELDS.includes(field)) {
      socket.emit('error', { message: 'Invalid service field.' });
      return;
    }

    // Special check when enabling Injury Healing
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

    await hospitalRepository.update(docId, (h) => {
      h[field] = value;
    });

    console.log(`[HOSPITAL] ${email} updated ${field} on ${docId} → ${value}`);

    if (field === 'offerInjuryHealing' && value === false) {
      console.log(`[HOSPITAL] Injury Healing turned OFF for ${docId} — maintenance fee stopped`);
    }
  }

  async updateHealCost(socket, data) {
    const email = socket.data.email;
    const { docId, newCost } = data;

    if (!email || !docId || typeof newCost !== 'number' || newCost < 1) {
      socket.emit('error', { message: 'Invalid heal cost.' });
      return;
    }

    const hospital = hospitalRepository.get(docId);
    if (!hospital) return;

    if (!hospital.isOwnedBy(email)) {
      socket.emit('error', { message: 'You do not own this hospital.' });
      return;
    }

    await hospitalRepository.update(docId, (h) => {
      h.customHealCost = newCost;
    });

    console.log(`[HOSPITAL] ${email} changed heal cost of ${docId} to $${newCost}`);
  }

  async updateHealingDuration(socket, data) {
    const email = socket.data.email;
    const { docId, healingDurationMs } = data;

    if (!email || !docId || typeof healingDurationMs !== 'number') {
      socket.emit('error', { message: 'Invalid healing duration.' });
      return;
    }

    const hospital = hospitalRepository.get(docId);
    if (!hospital) return;

    if (!hospital.isOwnedBy(email)) {
      socket.emit('error', { message: 'You do not own this hospital.' });
      return;
    }

    if (!hospital.isValidHealingDuration(healingDurationMs)) {
      const hasEfficient = hospital.hasEfficientDoctors === true;
      socket.emit('error', {
        message: hasEfficient
          ? 'Healing duration must be between 2:00 and 4:00.'
          : 'Healing duration must be between 3:00 and 4:00.'
      });
      return;
    }

    await hospitalRepository.update(docId, (h) => {
      h.customHealingDuration = healingDurationMs;
    });

    console.log(`[HOSPITAL] ${email} changed healing duration of ${docId} to ${healingDurationMs} ms`);
  }

  async updateStaminaCost(socket, data) {
    const email = socket.data.email;
    const { docId, newCost } = data;

    if (!email || !docId || typeof newCost !== 'number' || newCost < 1) {
      socket.emit('error', { message: 'Invalid stamina cost.' });
      return;
    }

    const hospital = hospitalRepository.get(docId);
    if (!hospital) return;

    if (!hospital.isOwnedBy(email)) {
      socket.emit('error', { message: 'You do not own this hospital.' });
      return;
    }

    await hospitalRepository.update(docId, (h) => {
      h.customStaminaCost = newCost;
    });

    console.log(`[HOSPITAL] ${email} changed Stamina cost of ${docId} to $${newCost}`);
  }

  async updateConstitutionCost(socket, data) {
    const email = socket.data.email;
    const { docId, newCost } = data;

    if (!email || !docId || typeof newCost !== 'number' || newCost < 1) {
      socket.emit('error', { message: 'Invalid constitution cost.' });
      return;
    }

    const hospital = hospitalRepository.get(docId);
    if (!hospital) return;

    if (!hospital.isOwnedBy(email)) {
      socket.emit('error', { message: 'You do not own this hospital.' });
      return;
    }

    await hospitalRepository.update(docId, (h) => {
      h.customConstitutionCost = newCost;
    });

    console.log(`[HOSPITAL] ${email} changed Constitution cost of ${docId} to $${newCost}`);
  }

  async setSelectedEpinephrineQuality(socket, data) {
    const email = socket.data.email;
    const { hospitalDocId, quality } = data;

    if (!email || !hospitalDocId) return;

    const hospital = hospitalRepository.get(hospitalDocId);
    if (!hospital) return;

    if (!hospital.isOwnedBy(email)) {
      socket.emit('error', { message: 'You do not own this hospital.' });
      return;
    }

    await hospitalRepository.update(hospitalDocId, (h) => {
      h.selectedEpinephrineQuality = quality || null;
    });

    console.log(
      `[HOSPITAL] ${email} set selected Epinephrine quality to ${quality} on ${hospitalDocId}`
    );
  }
}

const ownershipService = new OwnershipService();

module.exports = {
  OwnershipService,
  ownershipService
};
