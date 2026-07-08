// ==================== PROPER SHUFFLE (Fisher-Yates) ====================
// This creates a truly random order of the array.
// It does NOT modify the original array - it returns a new shuffled copy.
function shuffleArray(array) {
  // Step A: Make a copy of the array so we don't change the original
  const newArray = array.slice();   // "slice()" with no numbers = copy everything

  // Step B: Go backwards through the array (from last item to second item)
  for (let i = newArray.length - 1; i > 0; i--) {
    
    // Step C: Pick a random position from 0 up to (and including) position i
    // Math.random() gives a number between 0 and 0.999...
    // Math.floor() rounds it down to a whole number (integer)
    const j = Math.floor(Math.random() * (i + 1));
    
    // Step D: Swap the items at positions i and j
    // This is the actual "shuffle" step
    const temp = newArray[i];      // Remember what was at position i
    newArray[i] = newArray[j];     // Put the random item into position i
    newArray[j] = temp;            // Put the old item into the random position
  }

  // Step E: Return the fully shuffled array
  return newArray;
}

function getPeterMessage(hunger) {
  if (hunger >= 91) {
    return "You see Peter the Beggar walking by. It seems he has eaten recently and is quite full.";
  } else if (hunger >= 71) {
    return "You see Peter the Beggar walking by. He seems quite peckish.";
  } else if (hunger >= 51) {
    return "You see Peter the Beggar walking by. It looks like he's looking for food, he must be hungry.";
  } else if (hunger >= 31) {
    return "You see Peter the Beggar walking by. He looks very hungry.";
  } else {
    return "You see Peter the Beggar walking by. It looks like he hasn't eaten for days. He's starving.";
  }
}

function updatePeterVicinity(peter, onlinePlayers, onlineSockets) {
  const onlineList = Array.from(onlinePlayers);

  if (onlineList.length === 0) {
    peter.vicinity = [];
    return;
  }

    // Shuffle properly using Fisher-Yates (fair and professional)
  const shuffled = shuffleArray(onlineList);
  const selectedPlayers = shuffled.slice(0, 5);

  peter.vicinity = selectedPlayers;

  // Send overlay to selected players
  selectedPlayers.forEach(playerName => {
    const playerSocket = onlineSockets.get(playerName);
    if (playerSocket) {
      const message = getPeterMessage(peter.hunger);
      playerSocket.emit('peter-sighting', {
        message: message,
        hunger: peter.hunger
      });
    }
  });

  console.log(`[PETER] Vicinity updated. Players who saw him: ${selectedPlayers.join(', ')}`);
}

// Setup function that starts the 30-second cycle
function setupPeterTheBeggar(humans, onlinePlayers, onlineSockets) {
  setInterval(() => {
    const peter = humans.get('Peter the Beggar');
    if (!peter) return;

    // Decrease hunger
    if (peter.hunger > 0) {
      peter.hunger -= 1;
      if (peter.hunger < 0) peter.hunger = 0;
    }

    // Keep the "last update time" fresh in memory (helps on restart)
    peter.lastHungerUpdate = Date.now();

    // ==================== REST / NAP / SLEEP LOGIC ====================
    // Initialize tracking properties if they don't exist
    if (peter.consecutiveWalkingStreak === undefined) peter.consecutiveWalkingStreak = 0;
    if (peter.restCyclesRemaining === undefined) peter.restCyclesRemaining = 0;

    // CASE 1: Peter is currently resting, napping, or sleeping
    if (peter.restCyclesRemaining > 0) {
      peter.restCyclesRemaining--;

      // Clear vicinity during rest/nap/sleep (no players see him)
      peter.vicinity = [];

      // When rest/nap/sleep period ends, reset the walking streak
      if (peter.restCyclesRemaining === 0) {
        peter.consecutiveWalkingStreak = 0;
        console.log('[PETER] Finished resting/napping/sleeping. Streak reset.');
      } else {
        console.log(`[PETER] Still resting... ${peter.restCyclesRemaining} cycles remaining.`);
      }

      return; // Skip normal vicinity update this cycle
    }

    // CASE 2: Peter is walking around (not resting)
    peter.consecutiveWalkingStreak++;

    let shouldRestThisCycle = false;
    let restDuration = 0; // 1 = rest, 2 = nap, 5 = sleep

    const streak = peter.consecutiveWalkingStreak;

    if (streak === 4) {
      // After 4 consecutive walking cycles → 50% chance to rest on the 5th cycle
      if (Math.random() < 0.5) {
        shouldRestThisCycle = true;
        restDuration = 1; // rest (1 cycle)
      }
    } 
    else if (streak === 5) {
      // After 5 walking cycles → decide for the 6th cycle
      const roll = Math.random();
      if (roll < 0.4) {
        shouldRestThisCycle = true;
        restDuration = 1; // rest
      } else if (roll < 0.5) {
        shouldRestThisCycle = true;
        restDuration = 2; // nap (2 cycles)
      }
      // 50% chance: continue walking (do nothing)
    } 
    else if (streak === 6) {
      // After 6 walking cycles → decide for the 7th cycle
      const roll = Math.random();
      if (roll < 0.3) {
        shouldRestThisCycle = true;
        restDuration = 1; // rest
      } else if (roll < 0.5) {
        shouldRestThisCycle = true;
        restDuration = 2; // nap
      }
      // 50% chance: continue walking
    } 
    else if (streak === 7) {
      // After 7 walking cycles (has been walking for 7 straight cycles)
      const roll = Math.random();
      if (roll < 0.5) {
        shouldRestThisCycle = true;
        restDuration = 2; // nap (2 cycles)
      } else {
        shouldRestThisCycle = true;
        restDuration = 5; // sleep (5 cycles)
      }
    }

    if (shouldRestThisCycle && restDuration > 0) {
      // Start resting/napping/sleeping
      peter.restCyclesRemaining = restDuration;
      peter.vicinity = [];

      const type = restDuration === 1 ? 'rest' : restDuration === 2 ? 'nap' : 'sleep';
      console.log(`[PETER] Starting ${restDuration}-cycle ${type} (after ${streak} walking cycles).`);
    } else {
      // Normal walking cycle - update vicinity and notify players
      updatePeterVicinity(peter, onlinePlayers, onlineSockets);
    }

  }, 30000); // Every 30 seconds

  console.log('[PETER] Peter the Beggar 30-second cycle started with rest/nap/sleep logic.');
}

module.exports = {
  setupPeterTheBeggar,
  getPeterMessage,
  updatePeterVicinity
};