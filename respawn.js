function registerRespawnHandler(socket, { db, normalLocations, getRankTitle }) {
  socket.on('respawn', async () => {
    const email = socket.data.email;
    if (!email) return;

    const docRef = db.collection('players').doc(email);
    const doc = await docRef.get();
    if (!doc.exists) return;

    let p = doc.data();

    if (p.dead) {
      const oldName = p.displayName;

      if (oldName) {
        // Save dead profile snapshot
        const deadProfile = {
          displayName: oldName,
          displayNameLower: oldName.toLowerCase(),
          experience: p.experience || 0,
          balance: p.balance || 0,
          headwear: p.headwear || null,
          armor: p.armor || null,
          footwear: p.footwear || null,
          weapon: p.weapon || null,
          overallPower: p.overallPower || 0,
          deathTime: admin.firestore.FieldValue.serverTimestamp(),
          originalEmail: email
        };
        await db.collection('deadProfiles').doc(oldName.toLowerCase()).set(deadProfile);

        // Add old name to usedNames
        await db.collection('usedNames').doc(oldName.toLowerCase()).set({
          name: oldName,
          taken: true,
          originalEmail: email,
          takenAt: admin.firestore.FieldValue.serverTimestamp()
        });
      }

      // Wipe old transaction history
      const txSnapshot = await docRef.collection('transactions').get();
      if (!txSnapshot.empty) {
        const batch = db.batch();
        txSnapshot.docs.forEach((txDoc) => batch.delete(txDoc.ref));
        await batch.commit();
      }

      // Reset player to default state
      const randomLocation = normalLocations[Math.floor(Math.random() * normalLocations.length)];

      p = {
        ...p,
        balance: 0,
        health: 100,
        maxHealth: 100,
        bullets: 0,
        lastRob: 0,
        displayName: null,
        displayNameLower: null,
        location: randomLocation,
        experience: 0,
        intelligence: 0,
        skill: 0,
        strength: 0,
        physicalToll: 0,
        marksmanship: 0,
        stealth: 0,
        defense: 0,
        kills: 0,
        photoURL: '',
        inventory: [],
        headwear: null,
        armor: null,
        footwear: null,
        overallPower: 0,
        weapon: null,
        lastLowLevelOp: 0,
        lastMidLevelOp: 0,
        lastHighLevelOp: 0,
        sellBanEndTime: 0,
        prisonEndTime: 0,
        ownedBonds: [],
        ownedProperties: [],
        lastIncomeClaim: Date.now(),
        propertyClaims: [],
        showArmor: true,
        showWeapon: true,
        hasBrokenBone: false,
        bonePenaltyEndTimeLow: 0,
        bonePenaltyEndTimeMid: 0,
        bonePenaltyEndTimeHigh: 0,
        dead: false,
        usedAdForHealing: false,
        ownedUpgrades: {},
        unallocatedAttributePoints: 0,
        taxiFleet: [],
        scoutedDrivers: [],
        hiredDrivers: [],
        hasActiveTaxiJobs: false,
        activeSpecialOperation: null,
        activeSpecialOperationParty: null,
        completedCourses: [],
        martialArt: null,
      };

      p.rank = getRankTitle(0);

      // Prevent invalid display name
      if (p.displayName && (p.displayName.length > 22 || ['.', '/', '\\'].includes(p.displayName[0]))) {
        p.displayName = null;
      }

      await docRef.set(p);
      socket.emit('update-stats', p);
    }
  });
}

module.exports = { registerRespawnHandler };