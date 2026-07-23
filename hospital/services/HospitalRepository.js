/**
 * HospitalRepository – in-memory Map is the live source of truth.
 * Firestore is the durable store. All mutations go through update().
 * Broadcasts keep the exact original 'hospital-ownership-update' full payload
 * so existing clients continue to work without changes.
 */

const admin = require('firebase-admin');
const Hospital = require('../models/Hospital');

class HospitalRepository {
  constructor() {
    /** @type {Map<string, Hospital>} */
    this.cache = new Map();
    this.db = null;
    this.collectionRef = null;
    this.io = null; // set later so we can broadcast
  }

  /**
   * Must be called once at server startup after Firebase is initialised.
   */
  async initialize(db, io) {
    this.db = db;
    this.collectionRef = db.collection('hospitals');
    this.io = io;

    const snapshot = await this.collectionRef.get();
    this.cache.clear();

    snapshot.docs.forEach(doc => {
      this.cache.set(doc.id, new Hospital(doc.id, doc.data()));
    });

    console.log(`[HOSPITAL REPO] Loaded ${this.cache.size} hospitals into memory`);
    return this.cache.size;
  }

  /** Return a Hospital instance (or null) */
  get(id) {
    return this.cache.get(id) || null;
  }

  /** Return plain object map { [id]: hospital.toJSON() } – exact original shape */
  getAllOwnership() {
    const ownership = {};
    for (const [id, hospital] of this.cache) {
      ownership[id] = hospital.toJSON();
    }
    return ownership;
  }

  /**
   * Atomic in-memory mutation + Firestore write + full ownership broadcast.
   * mutator(hospital) may mutate the Hospital instance in place.
   * Returns the updated Hospital.
   */
  async update(id, mutator) {
    const hospital = this.cache.get(id);
    if (!hospital) {
      throw new Error(`Hospital ${id} not found in cache`);
    }

    // Run mutator (may throw)
    await mutator(hospital);

    // Persist the whole document (simple & consistent with original)
    await this.collectionRef.doc(id).set(hospital.toJSON(), { merge: true });

    // Broadcast full ownership map (exact original event + payload)
    this._broadcastOwnership();

    return hospital;
  }

  async updateWithTransaction(id, transactionFn) {
    const hospitalRef = this.collectionRef.doc(id);
    let appliedUpdates = null;

    await this.db.runTransaction(async (transaction) => {
      const snap = await transaction.get(hospitalRef);
      if (!snap.exists) {
        throw new Error(`Hospital ${id} no longer exists`);
      }

      const currentData = snap.data();
      const updates = await transactionFn(transaction, currentData);

      if (!updates || Object.keys(updates).length === 0) {
        return; // nothing to do
      }

      transaction.update(hospitalRef, updates);
      appliedUpdates = updates;
    });

    // Only touch the cache + broadcast if the transaction actually wrote something
    if (appliedUpdates) {
      const hospital = this.cache.get(id);
      if (hospital) {
        // Apply every field that was written
        for (const [key, value] of Object.entries(appliedUpdates)) {
          if (value && value.constructor && value.constructor.name === 'FieldValue') {
            // Handle FieldValue.delete()
            hospital[key] = 0;
          } else {
            hospital[key] = value;
          }
        }
        // Always recalculate nextResearchEndTime from the model’s own logic
        hospital.recalculateNextResearchEndTime();
      }
      this._broadcastOwnership();
    }

    return appliedUpdates;
  }

  /**
   * Create a brand-new hospital document (used by initializeHospitals).
   * Only called when the doc does not yet exist.
   */
  async createIfMissing(id, initialData) {
    if (this.cache.has(id)) return this.cache.get(id);

    const hospital = new Hospital(id, initialData);
    this.cache.set(id, hospital);
    await this.collectionRef.doc(id).set(hospital.toJSON());
    return hospital;
  }

  /** Force a broadcast of the current full ownership map */
  _broadcastOwnership() {
    if (!this.io) return;
    const ownership = this.getAllOwnership();
    // Support both io and socket that has .server
    const emitter = this.io.server || this.io;
    emitter.emit('hospital-ownership-update', ownership);
  }

  /** Public helper used by other services that need to emit after external changes */
  broadcast() {
    this._broadcastOwnership();
  }

  /** Direct Firestore write for fields that live only in Firestore (rare) */
  async rawUpdate(id, fields) {
    await this.collectionRef.doc(id).update(fields);
    // Also update cache if the hospital is loaded
    const hospital = this.cache.get(id);
    if (hospital) {
      Object.assign(hospital, fields);
      if (fields.nextResearchEndTime === admin.firestore.FieldValue.delete()) {
        hospital.nextResearchEndTime = 0;
      }
    }
  }
}

// Singleton
const hospitalRepository = new HospitalRepository();

module.exports = {
  HospitalRepository,
  hospitalRepository
};
