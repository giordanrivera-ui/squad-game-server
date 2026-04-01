const admin = require('firebase-admin');

const { generateRandomDriver } = require('./drivers.js');

// ==================== IMPROVED TRANSACTION LOGGER ====================
async function logTransaction(socket, amount, description, playerData, docRef) {
  if (!socket || typeof amount !== 'number' || !playerData || !docRef) {
    console.warn('[TX] Invalid logTransaction call - missing params');
    return;
  }

  const newBalance = (playerData.balance || 0) + amount;

  const txData = {
    amount: amount,
    description: description,
    balanceAfter: Math.round(newBalance),
    timestamp: admin.firestore.FieldValue.serverTimestamp()
  };

  // Live update to client
  socket.emit('new-transaction', {
    amount: amount,
    description: description,
    balanceAfter: Math.round(newBalance)
  });

        // Permanent storage
  try {
    await docRef.collection('transactions').add(txData);
    console.log(`[TX SAVED] ${description} | $${amount} → Balance: $${newBalance}`);
  } catch (err) {
    console.error('[TX ERROR] Failed to save transaction:', err);
  }
}

// ==================== AUTO DRIVER SALARY DEDUCTIONS ====================
function startDriverSalaryChecker(db, { onlineSockets }) {
  setInterval(async () => {
    try {
      const now = Date.now();
      const snapshot = await db.collection('players').get();
      const batch = db.batch();
      const playersToNotify = [];

      for (const doc of snapshot.docs) {
        let p = doc.data();
        if (!p.hiredDrivers || p.hiredDrivers.length === 0) continue;

        let updatedDrivers = [];
        let totalSalaryThisCycle = 0;

        for (const driver of p.hiredDrivers) {
          if (!driver.nextSalaryPaymentTime || !driver.salary) {
            updatedDrivers.push(driver);
            continue;
          }

          if (now >= driver.nextSalaryPaymentTime) {
            const salary = Math.round(driver.salary);
            totalSalaryThisCycle += salary;

            driver.nextSalaryPaymentTime = now + 3600 * 1000;
            updatedDrivers.push(driver);

            console.log(`[SALARY] ${p.displayName || doc.id} paid $${salary} to ${driver.name}`);
          } else {
            updatedDrivers.push(driver);
          }
        }

        if (totalSalaryThisCycle > 0) {
          batch.update(doc.ref, {
            balance: admin.firestore.FieldValue.increment(-totalSalaryThisCycle),
            hiredDrivers: updatedDrivers
          });

          const txRef = doc.ref.collection('transactions').doc();
          batch.set(txRef, {
            amount: -totalSalaryThisCycle,
            description: `Driver Salaries ($${totalSalaryThisCycle})`,
            balanceAfter: (p.balance || 0) - totalSalaryThisCycle,
            timestamp: admin.firestore.FieldValue.serverTimestamp()
          });

          if (p.displayName) {
            playersToNotify.push({
              displayName: p.displayName,
              email: doc.id,
              totalDeducted: totalSalaryThisCycle
            });
          }
        } else {
          if (JSON.stringify(p.hiredDrivers) !== JSON.stringify(updatedDrivers)) {
            batch.update(doc.ref, { hiredDrivers: updatedDrivers });
          }
        }
      }

      await batch.commit();

      for (const player of playersToNotify) {
        const socket = onlineSockets.get(player.displayName);
        if (socket) {
          const freshDoc = await db.collection('players').doc(player.email).get();
          const freshData = freshDoc.data();
          socket.emit('update-stats', freshData);
          socket.emit('new-transaction', {
            amount: -player.totalDeducted,
            description: 'Driver Salaries',
            balanceAfter: (freshData.balance || 0)
          });
        }
      }
    } catch (e) {
      console.error('Driver salary checker error:', e);
    }
  }, 1000);
}

// ==================== OPTIMIZED DRIVER PROGRESS CHECKER (Scalable) ====================
function startDriverProgressChecker(db) {
  setInterval(async () => {
    try {
      const now = Date.now();
      // Only fetch players who have at least one hired driver (much smaller result set)
      const snapshot = await db.collection('players')
        .where('hiredDrivers', '!=', null)   // still scans, but filters better
        .get();

      const batch = db.batch();
      let totalProcessed = 0;

      for (const doc of snapshot.docs) {
        let p = doc.data();
        if (!p.hiredDrivers || p.hiredDrivers.length === 0 || !p.taxiFleet) continue;

        totalProcessed++;

        let changed = false;

        const assignmentMap = {};
        for (const vehicle of p.taxiFleet) {
          if (vehicle.assignedDriverName) {
            assignmentMap[vehicle.name] = vehicle.assignedDriverName;
          }
        }

        for (const driver of p.hiredDrivers) {
          const driverName = driver.name;
          if (!driverName) continue;

          let currentVehicleName = null;
          for (const [vehName, assignedName] of Object.entries(assignmentMap)) {
            if (assignedName === driverName) {
              currentVehicleName = vehName;
              break;
            }
          }

          if (!currentVehicleName) continue;

          // === vehicleTime (exact ms) ===
          if (!driver.vehicleTime) driver.vehicleTime = {};
          const startTimeKey = `startTime_${currentVehicleName}`;
          const startTime = driver[startTimeKey];

          if (startTime) {
            const elapsed = now - startTime;
            driver.vehicleTime[currentVehicleName] = (driver.vehicleTime[currentVehicleName] || 0) + elapsed;
            driver[startTimeKey] = now;
            changed = true;
          } else {
            driver[startTimeKey] = now;
            changed = true;
          }

          // === vehicleExperience derived from time ===
          if (!driver.vehicleExperience) driver.vehicleExperience = {};
          const totalMs = driver.vehicleTime[currentVehicleName] || 0;
          const newExp = Math.floor(totalMs / 120000);

          if (driver.vehicleExperience[currentVehicleName] !== newExp) {
            driver.vehicleExperience[currentVehicleName] = newExp;
            changed = true;
          }
        }

        if (changed) {
          batch.update(doc.ref, { hiredDrivers: p.hiredDrivers });
        }
      }

      await batch.commit();
      console.log(`[PROGRESS] Processed ${totalProcessed} players with active drivers`);
    } catch (e) {
      console.error('Driver progress checker error:', e);
    }
  }, 30000); // still every 30 seconds
}

// ==================== TAXI JOB FINDER & COUNTDOWN CHECKER (FIXED - LIVE UPDATES ON EVERY STATUS CHANGE) ====================
function startTaxiJobChecker(db, { onlineSockets }) {
  setInterval(async () => {
    try {
      const now = Date.now();
      const snapshot = await db.collection('players').get();
      const batch = db.batch();
      const playersToNotify = [];   // players who need a live update-stats

      for (const doc of snapshot.docs) {
        let p = doc.data();
        if (!p.taxiFleet || p.taxiFleet.length === 0) continue;

        let changed = false;

        for (const vehicle of p.taxiFleet) {
          if (!vehicle.assignedDriverName) continue;

          const driver = p.hiredDrivers.find(d => d.name === vehicle.assignedDriverName);
          if (!driver) continue;

          const skill = driver.drivingSkill || 1;
          const baseCooldown = Math.max(10, 53 - skill);

          // ==================== JOB START ====================
          if (vehicle.status === 'Finding customer' || !vehicle.status) {
            if (!vehicle.nextCustomerTime) {
              vehicle.nextCustomerTime = now + baseCooldown * 1000;
              changed = true;
            }

            if (now >= vehicle.nextCustomerTime) {
              vehicle.status = 'Job ongoing';
              const jobSeconds = Math.floor(Math.random() * 181) + 120; // 2–5 minutes
              vehicle.jobEndTime = now + jobSeconds * 1000;
              vehicle.jobDurationSeconds = jobSeconds;

              delete vehicle.nextCustomerTime;
              changed = true;

              console.log(`[JOB START] ${vehicle.assignedDriverName} started job on ${vehicle.name}`);
            }
          } 
          // ==================== JOB END + PAYOUT ====================
          else if (vehicle.status === 'Job ongoing' && vehicle.jobEndTime) {
            if (now >= vehicle.jobEndTime) {
              const seconds = vehicle.jobDurationSeconds || 180;
              const money = Math.round((seconds / 3) * ((skill / 100) + 1));

              // Add money
              p.balance = (p.balance || 0) + money;

              // Save permanent transaction
              const txRef = doc.ref.collection('transactions').doc();
              batch.set(txRef, {
                amount: money,
                description: `Taxi Job Payout (${vehicle.assignedDriverName} on ${vehicle.name})`,
                balanceAfter: p.balance,
                timestamp: admin.firestore.FieldValue.serverTimestamp()
              });

              // Live transaction for online players
              const socket = onlineSockets.get(p.displayName);
              if (socket) {
                socket.emit('new-transaction', {
                  amount: money,
                  description: `Taxi Job Payout (${vehicle.assignedDriverName} on ${vehicle.name})`,
                  balanceAfter: p.balance
                });
              }

              // Reset for next job
              vehicle.status = 'Finding customer';
              vehicle.nextCustomerTime = now + baseCooldown * 1000;
              delete vehicle.jobEndTime;
              delete vehicle.jobDurationSeconds;

              changed = true;

              console.log(`[JOB END] ${vehicle.assignedDriverName} completed job on ${vehicle.name} (+$${money})`);
            }
          }
        }

        // If anything changed for this player, mark them for live update
        if (changed) {
          batch.update(doc.ref, { taxiFleet: p.taxiFleet });
          if (p.displayName) {
            playersToNotify.push(p.displayName);
          }
        }
      }

      await batch.commit();

      // ==================== LIVE UPDATES TO ALL AFFECTED PLAYERS ====================
      for (const displayName of playersToNotify) {
        const socket = onlineSockets.get(displayName);
        if (socket) {
          const freshDoc = await db.collection('players').doc(socket.data.email).get();
          if (freshDoc.exists) {
            socket.emit('update-stats', freshDoc.data());
          }
        }
      }
    } catch (e) {
      console.error('Taxi Job Checker error:', e);
    }
  }, 1000);
}

// ==================== ASSIGN / UNASSIGN / OTHER HANDLERS (unchanged except minor cleanup) ====================
async function handleAssignToFleet(db, socket, vehicle) {
  const email = socket.data.email;
  if (!email || !vehicle || !vehicle.name) {
    socket.emit('fleet-result', { success: false, message: 'Invalid vehicle' });
    return;
  }

  const docRef = db.collection('players').doc(email);
  const doc = await docRef.get();
  if (!doc.exists) return;

  let p = doc.data();

  const index = p.inventory.findIndex(v => 
    v.name === vehicle.name && 
    v.power === vehicle.power && 
    v.health === (vehicle.health || 100)
  );

  if (index === -1) {
    socket.emit('fleet-result', { success: false, message: 'Vehicle not found in inventory' });
    return;
  }

  const assignedVehicle = p.inventory.splice(index, 1)[0];

  assignedVehicle.fleetId = `fleet_${Date.now()}_${Math.random().toString(36).slice(2)}`;

  if (!p.taxiFleet) p.taxiFleet = [];
  p.taxiFleet.push(assignedVehicle);

  await docRef.set(p);

  socket.emit('update-stats', p);
  socket.emit('fleet-result', { 
    success: true, 
    message: `${assignedVehicle.name} assigned to your taxi fleet!` 
  });
}

async function handleRemoveFromFleet(db, socket, payload) {
  const email = socket.data.email;
  if (!email) {
    socket.emit('fleet-result', { success: false, message: 'Not logged in' });
    return;
  }

  let vehiclesToRemove = payload?.vehicles || payload;
  let items = Array.isArray(vehiclesToRemove) ? vehiclesToRemove : [vehiclesToRemove];
  if (items.length === 0) {
    socket.emit('fleet-result', { success: false, message: 'No vehicles selected' });
    return;
  }

  const docRef = db.collection('players').doc(email);
  const doc = await docRef.get();
  if (!doc.exists) return;

  let p = doc.data();
  if (!p.taxiFleet) p.taxiFleet = [];
  if (!p.inventory) p.inventory = [];

  const removedVehicles = [];
  const toRemoveKeys = new Set();
  items.forEach(item => {
    const key = `${item.name}|${item.power}|${item.health ?? 100}`;
    toRemoveKeys.add(key);
  });

  p.taxiFleet = p.taxiFleet.filter(v => {
    const vHealth = v.health ?? 100;
    const key = `${v.name}|${v.power}|${vHealth}`;
    if (toRemoveKeys.has(key)) {
      removedVehicles.push(v);
      return false;
    }
    return true;
  });

  if (removedVehicles.length > 0) {
    p.inventory = [...p.inventory, ...removedVehicles];
    await docRef.set(p);
    socket.emit('update-stats', p);
    socket.emit('fleet-result', { 
      success: true, 
      message: `${removedVehicles.length} vehicle(s) moved back to inventory` 
    });
  } else {
    socket.emit('fleet-result', { success: false, message: 'No matching vehicles found to remove' });
  }
}

async function handleScoutDrivers(db, socket, count) {
  const email = socket.data.email;
  if (!email || typeof count !== 'number' || count < 1) return;

  const docRef = db.collection('players').doc(email);
  const doc = await docRef.get();
  if (!doc.exists) return;

  let p = doc.data();
  const totalCost = count * 20;

  if ((p.balance || 0) < totalCost) {
    socket.emit('fleet-result', { success: false, message: 'Not enough money to scout drivers.' });
    return;
  }

  const newDrivers = [];
  for (let i = 0; i < count; i++) {
    newDrivers.push(generateRandomDriver(p.location));
  }

  await logTransaction(socket, -totalCost, `Scouted ${count} Driver${count > 1 ? 's' : ''}`, p, docRef);
  p.balance -= totalCost;

  if (!p.scoutedDrivers) p.scoutedDrivers = [];
  p.scoutedDrivers = [...p.scoutedDrivers, ...newDrivers];

  await docRef.set(p);
  socket.emit('update-stats', p);

  socket.emit('fleet-result', { 
    success: true, 
    message: `Successfully scouted ${count} driver${count > 1 ? 's' : ''}!` 
  });
}

async function handleClearScoutedDrivers(db, socket) {
  const email = socket.data.email;
  if (!email) return;

  const docRef = db.collection('players').doc(email);
  const doc = await docRef.get();
  if (!doc.exists) return;

  let p = doc.data();
  p.scoutedDrivers = [];

  await docRef.set(p);
  socket.emit('update-stats', p);
  console.log(`[HR] Cleared scoutedDrivers for ${email}`);
}

// ==================== ASSIGN DRIVER TO VEHICLE (IMMEDIATE TIMER START) ====================
async function handleAssignDriverToVehicle(db, socket, data) {
  const email = socket.data.email;
  if (!email || !data.driverId || !data.vehicle) {
    console.log('[ASSIGN] Missing driverId or vehicle data');
    socket.emit('fleet-result', { success: false, message: 'Missing driver or vehicle data' });
    return;
  }

  const docRef = db.collection('players').doc(email);
  const doc = await docRef.get();
  if (!doc.exists) return;

  let p = doc.data();
  if (!p.hiredDrivers || !p.taxiFleet) return;

  const fleetId = data.vehicle.fleetId;
  if (!fleetId) {
    socket.emit('fleet-result', { success: false, message: 'Vehicle missing fleetId' });
    return;
  }

  const vehicleIndex = p.taxiFleet.findIndex(v => v.fleetId === fleetId);
  if (vehicleIndex === -1) {
    socket.emit('fleet-result', { success: false, message: 'Vehicle no longer in fleet' });
    return;
  }

  // Find driver by unique driverId (this was the missing piece)
  const driver = p.hiredDrivers.find(d => d.driverId === data.driverId);
  if (!driver) {
    console.log('[ASSIGN] Driver not found by ID');
    return;
  }

  const vehicleName = p.taxiFleet[vehicleIndex].name;

  // === IMMEDIATE TIMER START ===
  if (!driver.vehicleTime) driver.vehicleTime = {};
  if (!driver.vehicleExperience) driver.vehicleExperience = {};

  const startTimeKey = `startTime_${vehicleName}`;
  driver[startTimeKey] = Date.now();
  driver.vehicleTime[vehicleName] = driver.vehicleTime[vehicleName] || 0;

  // Assign using unique driverId
  p.taxiFleet[vehicleIndex].assignedDriverId = driver.driverId;
  p.taxiFleet[vehicleIndex].assignedDriverName = driver.name;  // keep for display
  p.taxiFleet[vehicleIndex].status = 'Finding customer';

  await docRef.set(p);
  socket.emit('update-stats', p);

  socket.emit('fleet-result', { 
    success: true, 
    message: `${driver.name} assigned to ${vehicleName}!` 
  });

  console.log(`[ASSIGN SUCCESS] ${driver.name} (ID: ${driver.driverId}) → ${vehicleName}`);
}

// ==================== UNASSIGN DRIVER FROM VEHICLE (FINALIZE TIME + CLEAN JOB TIMERS) ====================
async function handleUnassignDriverFromVehicle(db, socket, data) {
  const email = socket.data.email;
  if (!email || !data.driverName) return;

  const docRef = db.collection('players').doc(email);
  const doc = await docRef.get();
  if (!doc.exists) return;

  let p = doc.data();
  if (!p.taxiFleet) return;

  let updated = false;

  for (let i = 0; i < p.taxiFleet.length; i++) {
    const vehicle = p.taxiFleet[i];
    if (vehicle.assignedDriverName === data.driverName) {
      const vehicleName = vehicle.name;

      // Finalize time
      const driver = p.hiredDrivers.find(d => d.name === data.driverName);
      if (driver) {
        const startTimeKey = `startTime_${vehicleName}`;
        const startTime = driver[startTimeKey];
        if (startTime) {
          const elapsed = Date.now() - startTime;
          if (!driver.vehicleTime) driver.vehicleTime = {};
          driver.vehicleTime[vehicleName] = (driver.vehicleTime[vehicleName] || 0) + elapsed;
          delete driver[startTimeKey];
        }
      }

      // Clean vehicle
      delete vehicle.assignedDriverId;
      delete vehicle.assignedDriverName;
      delete vehicle.status;
      delete vehicle.jobEndTime;
      delete vehicle.nextCustomerTime;
      delete vehicle.jobDurationSeconds;

      updated = true;
      break;
    }
  }

  if (updated) {
    await docRef.set(p);
    socket.emit('update-stats', p);
    socket.emit('fleet-result', { 
      success: true, 
      message: `${data.driverName} has been unassigned from their vehicle.` 
    });
  }
}

async function handleFireDrivers(db, socket, payload) {
  const email = socket.data.email;
  if (!email) return;

  let driversToFire = payload;
  if (payload && typeof payload === 'object' && !Array.isArray(payload)) {
    driversToFire = payload.drivers || payload;
  }

  if (!Array.isArray(driversToFire) || driversToFire.length === 0) return;

  const docRef = db.collection('players').doc(email);
  const doc = await docRef.get();
  if (!doc.exists) return;

  let p = doc.data();
  if (!p.hiredDrivers) p.hiredDrivers = [];
  if (!p.taxiFleet) p.taxiFleet = [];

  const driverIdsToFire = new Set(driversToFire.map(d => d.driverId));

  // Remove from hiredDrivers
  p.hiredDrivers = p.hiredDrivers.filter(d => !driverIdsToFire.has(d.driverId));

  // Clean up vehicles
  for (let i = 0; i < p.taxiFleet.length; i++) {
    const vehicle = p.taxiFleet[i];
    if (vehicle.assignedDriverId && driverIdsToFire.has(vehicle.assignedDriverId)) {
      delete vehicle.assignedDriverId;
      delete vehicle.assignedDriverName;
      delete vehicle.status;
      delete vehicle.jobEndTime;
      delete vehicle.nextCustomerTime;
      delete vehicle.jobDurationSeconds;
    }
  }

  await docRef.set(p);

  socket.emit('update-stats', p);
  socket.emit('fleet-result', {
    success: true,
    message: `Fired ${driversToFire.length} driver${driversToFire.length > 1 ? 's' : ''}!`
  });
}

async function handleHireDrivers(db, socket, payload) {
  const email = socket.data.email;
  if (!email) return;

  let driversToHire = payload;
  if (payload && typeof payload === 'object' && !Array.isArray(payload)) {
    driversToHire = payload.drivers || payload;
  }

  if (!Array.isArray(driversToHire) || driversToHire.length === 0) return;

  const docRef = db.collection('players').doc(email);
  const doc = await docRef.get();
  if (!doc.exists) return;

  let p = doc.data();
  if (!p.hiredDrivers) p.hiredDrivers = [];
  if (!p.scoutedDrivers) p.scoutedDrivers = [];

  const now = Date.now();
  const cleanDrivers = driversToHire.map(d => ({
    ...d,
    driverId: `driver_${Date.now()}_${Math.random().toString(36).slice(2)}`,  // ← UNIQUE ID
    hireTime: now,
    nextSalaryPaymentTime: now + 3600 * 1000   // 1 hour as you set earlier
  }));

  p.hiredDrivers = [...p.hiredDrivers, ...cleanDrivers];
  p.scoutedDrivers = [];

  await docRef.set(p);

  socket.emit('update-stats', p);
  socket.emit('fleet-result', { 
    success: true, 
    message: `Hired ${cleanDrivers.length} driver${cleanDrivers.length > 1 ? 's' : ''}!` 
  });
}

module.exports = {
  startDriverSalaryChecker,
  startDriverProgressChecker,
  startTaxiJobChecker,
  handleAssignToFleet,
  handleRemoveFromFleet,
  handleScoutDrivers,
  handleClearScoutedDrivers,
  handleAssignDriverToVehicle,
  handleUnassignDriverFromVehicle,
  handleHireDrivers,
  handleFireDrivers
};