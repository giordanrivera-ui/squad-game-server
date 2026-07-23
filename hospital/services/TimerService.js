/**
 * Central TimerService – owns every setTimeout used by the hospital system.
 * Exact retry + force-completion behaviour from the original research timers.
 */

const MAX_RETRIES = 5;

class TimerService {
  constructor() {
    /** @type {Map<string, NodeJS.Timeout>} */
    this.activeTimers = new Map();
  }

  /**
   * Schedule a one-shot timer.
   * key should be unique, e.g. `${hospitalId}:efficient-doctors`
   */
  schedule(key, endTime, callback, retryCount = 0) {
    // Cancel any existing timer for this key
    this.cancel(key);

    const remainingMs = Math.max(0, endTime - Date.now());

    if (remainingMs === 0) {
      // Fire immediately (async so caller doesn't block)
      Promise.resolve()
        .then(() => callback({ force: false, retryCount }))
        .catch(err => {
          console.error(`[TIMER] Immediate callback failed for ${key}:`, err.message);
          this._retryOrForce(key, endTime, callback, retryCount);
        });
      return;
    }

    const timeoutId = setTimeout(async () => {
      try {
        await callback({ force: false, retryCount });
        this.activeTimers.delete(key);
      } catch (err) {
        console.error(`[TIMER ERROR] Attempt ${retryCount + 1} failed for ${key}:`, err.message);
        this._retryOrForce(key, endTime, callback, retryCount);
      }
    }, remainingMs);

    this.activeTimers.set(key, timeoutId);
    console.log(`[TIMER] Scheduled ${key} (attempt ${retryCount + 1}, in ${Math.round(remainingMs / 1000)}s)`);
  }

  _retryOrForce(key, originalEndTime, callback, retryCount) {
    if (retryCount < MAX_RETRIES) {
      const delayMs = 1000 * (retryCount + 1);
      console.log(`[TIMER] Retrying ${key} in ${delayMs / 1000}s`);
      // Schedule a short retry that will call the same callback again
      this.schedule(key, Date.now() + delayMs, callback, retryCount + 1);
    } else {
      console.error(`[CRITICAL] ${key} failed after max retries. Attempting final force completion...`);
      this.activeTimers.delete(key);
      Promise.resolve()
        .then(() => callback({ force: true, retryCount }))
        .catch(finalErr => {
          console.error(`[TIMER] Final force completion also failed for ${key}:`, finalErr);
        });
    }
  }

  cancel(key) {
    if (this.activeTimers.has(key)) {
      clearTimeout(this.activeTimers.get(key));
      this.activeTimers.delete(key);
    }
  }

  /**
   * Cancel every timer that belongs to a hospital (key starts with hospitalId)
   */
  cancelAllForHospital(hospitalId) {
    let cancelled = 0;
    for (const [key, timeoutId] of this.activeTimers) {
      if (key.startsWith(hospitalId)) {
        clearTimeout(timeoutId);
        this.activeTimers.delete(key);
        cancelled++;
      }
    }
    if (cancelled > 0) {
      console.log(`[TIMER] Cancelled ${cancelled} timer(s) for ${hospitalId}`);
    }
  }

  /** Debug helper */
  getActiveCount() {
    return this.activeTimers.size;
  }
}

// Singleton – one timer service for the whole process
const timerService = new TimerService();

module.exports = {
  TimerService,
  timerService
};
