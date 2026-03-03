const express = require('express');
const http = require('http');
const { Server } = require('socket.io');
const admin = require('firebase-admin');

const app = express();
const server = http.createServer(app);
const io = new Server(server, { cors: { origin: "*" } });

// Firebase Admin
const serviceAccount = JSON.parse(process.env.FIREBASE_SERVICE_ACCOUNT);
admin.initializeApp({
  credential: admin.credential.cert(serviceAccount)
});

const db = admin.firestore();

// ==================== GLOBAL PRISON LIST ====================
const imprisonedPlayers = new Map(); // Key: displayName, Value: prisonEndTime

// ==================== LOCATIONS ====================
const normalLocations = [
  "Riverstone", "Thornbury", "Vostokgrad", "Eichenwald", "Montclair",
  "Valleora", "Lónghǎi", "Sakuragawa", "Cawayan Heights"
];

// ==================== TRAVEL COSTS ====================
const travelCosts = {
  "Riverstone": 40, "Thornbury": 45, "Vostokgrad": 110, "Eichenwald": 60,
  "Montclair": 85, "Valleora": 70, "Lónghǎi": 140, "Sakuragawa": 95,
  "Cawayan Heights": 55
};

// ==================== ONLINE PLAYERS TRACKING ====================
const onlinePlayers = new Set();
const onlineSockets = new Map();

const timeFormatter = new Intl.DateTimeFormat('en-GB', { 
  timeZone: 'Europe/London', 
  hour: '2-digit', 
  minute: '2-digit', 
  hour12: false 
});

setInterval(() => {
  io.emit('time', timeFormatter.format(new Date()));
}, 30000);

io.on('connection', (socket) => {
  socket.on('register', async (data) => {
    const email = data.email;
    const displayName = data.displayName || 'Anonymous';

    if (!email) return;

    const docRef = db.collection('players').doc(email);
    const doc = await docRef.get();

    let playerData;

    if (doc.exists) {
      playerData = doc.data();
      if (playerData.experience === undefined) playerData.experience = 0;
      if (playerData.intelligence === undefined) playerData.intelligence = 0;
      if (playerData.skill === undefined) playerData.skill = 0;
      if (playerData.marksmanship === undefined) playerData.marksmanship = 0;
      if (playerData.stealth === undefined) playerData.stealth = 0;
      if (playerData.defense === undefined) playerData.defense = 0;
      if (playerData.photoURL === undefined) playerData.photoURL = '';
      if (playerData.inventory === undefined) playerData.inventory = [];
      if (playerData.headwear === undefined) playerData.headwear = null;
      if (playerData.armor === undefined) playerData.armor = null;
      if (playerData.footwear === undefined) playerData.footwear = null;
      if (playerData.lastLowLevelOp === undefined) playerData.lastLowLevelOp = 0;
      if (playerData.prisonEndTime === undefined) playerData.prisonEndTime = 0;
      await docRef.set(playerData);
    } else {
      const randomLocation = normalLocations[Math.floor(Math.random() * normalLocations.length)];

      playerData = {
        balance: 0,
        health: 100,
        lastRob: 0,
        displayName: displayName,
        location: randomLocation,
        messages: [],
        fcmTokens: [],
        experience: 0,
        intelligence: 0,
        skill: 0,
        marksmanship: 0,
        stealth: 0,
        defense: 0,
        photoURL: '',
        inventory: [],
        headwear: null,
        armor: null,
        footwear: null,
        lastLowLevelOp: 0,
        prisonEndTime: 0
      };

      await docRef.set(playerData);
    }

    socket.data.email = email;
    socket.data.displayName = displayName;

    onlinePlayers.add(displayName);
    onlineSockets.set(displayName, socket);

    io.emit('online-players', Array.from(onlinePlayers));

    console.log(`[SERVER] ${displayName} joined - online now: ${onlinePlayers.size}`);

    socket.emit('init', {
      player: playerData,
      locations: normalLocations,
      travelCosts: travelCosts
    });
    socket.emit('time', timeFormatter.format(new Date()));
  });

  // ==================== TEST BUTTONS ====================
  socket.on('add-test-exp', async (amount) => {
    const email = socket.data.email;
    if (!email || typeof amount !== 'number') return;

    const docRef = db.collection('players').doc(email);
    const doc = await docRef.get();
    if (!doc.exists) return;

    let p = doc.data();
    p.experience = (p.experience || 0) + amount;

    await docRef.set(p);
    socket.emit('update-stats', p);
  });

  socket.on('add-test-money', async (amount) => {
    const email = socket.data.email;
    if (!email || typeof amount !== 'number') return;

    const docRef = db.collection('players').doc(email);
    const doc = await docRef.get();
    if (!doc.exists) return;

    let p = doc.data();
    p.balance = (p.balance || 0) + amount;

    await docRef.set(p);
    socket.emit('update-stats', p);
  });

  // ==================== EXECUTE OPERATION ====================
  socket.on('execute-operation', async (data) => {
    const email = socket.data.email;
    if (!email || typeof data.operation !== 'string') return;

    const docRef = db.collection('players').doc(email);
    const doc = await docRef.get();
    if (!doc.exists) return;

    let p = doc.data();
    const operation = data.operation;

    const lowLevelOps = [
      "Mug a passerby",
      "Loot a grocery store",
      "Rob a bank",
      "Loot weapons store"
    ];

    if (!lowLevelOps.includes(operation)) return;

    if (Date.now() - (p.lastLowLevelOp || 0) < 60000) return;

    let money = 0;
    let rawDamage = 0;
    let expGain = 0;
    let message = "";
    let isCaught = false;

    if (operation === "Mug a passerby") {
      money = Math.floor(Math.random() * 91) + 10;
      rawDamage = Math.floor(Math.random() * 26) + 5;
      expGain = 10;
      message = `You mugged a passerby and got $${money}!`;
    } 
    else if (operation === "Loot a grocery store") {
      money = Math.floor(Math.random() * 71) + 30;
      rawDamage = Math.floor(Math.random() * 21) + 15;
      expGain = 15;
      message = `You looted the grocery store and stole $${money}!`;
    } 
    else if (operation === "Rob a bank") {
      rawDamage = Math.floor(Math.random() * 41) + 15;
      expGain = 25;

      const exp = p.experience || 0;
      if (exp <= 499)          money = Math.floor(Math.random() * 71) + 30;
      else if (exp <= 1249)    money = Math.floor(Math.random() * 81) + 40;
      else if (exp <= 2299)    money = Math.floor(Math.random() * 91) + 60;
      else if (exp <= 3499)    money = Math.floor(Math.random() * 101) + 80;
      else if (exp <= 4999)    money = Math.floor(Math.random() * 111) + 90;
      else if (exp <= 6849)    money = Math.floor(Math.random() * 121) + 120;
      else if (exp <= 8849)    money = Math.floor(Math.random() * 111) + 150;
      else if (exp <= 10199)   money = Math.floor(Math.random() * 121) + 180;
      else if (exp <= 11449)   money = Math.floor(Math.random() * 141) + 200;
      else if (exp <= 14199)   money = Math.floor(Math.random() * 121) + 240;
      else if (exp <= 17399)   money = Math.floor(Math.random() * 126) + 275;
      else if (exp <= 21349)   money = Math.floor(Math.random() * 156) + 320;
      else if (exp <= 25849)   money = Math.floor(Math.random() * 241) + 360;
      else if (exp <= 31499)   money = Math.floor(Math.random() * 251) + 450;
      else if (exp <= 38199)   money = Math.floor(Math.random() * 281) + 500;
      else                     money = Math.floor(Math.random() * 401) + 600;

      message = `You robbed the bank and escaped with $${money}!`;
    }

    // Prison Chance
    let prisonChance = 0.30;
    const exp = p.experience || 0;
    if (exp > 499) prisonChance = 0.21;
    if (exp > 1249) prisonChance = 0.20;
    if (exp > 2299) prisonChance = 0.19;
    if (exp > 3499) prisonChance = 0.18;
    if (exp > 4999) prisonChance = 0.17;
    if (exp > 6849) prisonChance = 0.16;
    if (exp > 8849) prisonChance = 0.15;
    if (exp > 10199) prisonChance = 0.14;
    if (exp > 11449) prisonChance = 0.13;
    if (exp > 14199) prisonChance = 0.12;
    if (exp > 17399) prisonChance = 0.11;
    if (exp > 21349) prisonChance = 0.10;
    if (exp > 25849) prisonChance = 0.08;
    if (exp > 31499) prisonChance = 0.07;
    if (exp > 38199) prisonChance = 0.06;

    isCaught = Math.random() < prisonChance;

    if (isCaught) {
      p.prisonEndTime = Date.now() + 60000;
      imprisonedPlayers.set(p.displayName, p.prisonEndTime);
      message = `You were caught! You have been sent to prison for 60 seconds.`;
    } else {
      const totalDefense = 
        (p.headwear?.defense || 0) + 
        (p.armor?.defense || 0) + 
        (p.footwear?.defense || 0);

      const actualDamage = Math.max(0, rawDamage - totalDefense);

      p.balance += money;
      p.health = Math.max(0, p.health - actualDamage);
      p.experience += expGain;
    }

    p.lastLowLevelOp = Date.now();

    await docRef.set(p);

    // Broadcast updated prison list to ALL players
    const prisonList = Array.from(imprisonedPlayers, ([displayName, prisonEndTime]) => ({
      displayName,
      prisonEndTime
    }));
    io.emit('prison-list-update', prisonList);

    // Send result to the player who did the operation
    socket.emit('operation-result', {
      operation: operation,
      money: money,
      rawDamage: rawDamage,
      actualDamage: isCaught ? rawDamage : Math.max(0, rawDamage - 
        ((p.headwear?.defense || 0) + (p.armor?.defense || 0) + (p.footwear?.defense || 0))),
      totalDefense: isCaught ? 0 : 
        ((p.headwear?.defense || 0) + (p.armor?.defense || 0) + (p.footwear?.defense || 0)),
      message: message,
      isCaught: isCaught,
      prisonEndTime: p.prisonEndTime || 0
    });

    socket.emit('update-stats', p);

    if (p.health <= 0 && !isCaught) {
      await docRef.delete();
      console.log(`Player ${email} died and data was reset`);
    }
  });

  // ==================== REQUEST PRISON LIST (This was missing) ====================
  socket.on('request-prison-list', () => {
    const prisonList = Array.from(imprisonedPlayers, ([displayName, prisonEndTime]) => ({
      displayName,
      prisonEndTime
    }));
    socket.emit('prison-list-update', prisonList);
  });

  // ==================== OTHER HANDLERS (unchanged) ====================
  socket.on('message', (msg) => {
    const name = socket.data.displayName || 'Anonymous';
    io.emit('message', `${name}: ${msg}`);
  });

  socket.on('travel', async (destination) => {
    const email = socket.data.email;
    if (!email || typeof destination !== 'string') return;

    const docRef = db.collection('players').doc(email);
    const doc = await docRef.get();
    if (!doc.exists) return;

    let p = doc.data();

    if (p.location === destination || travelCosts[destination] === undefined) return;

    const cost = travelCosts[destination];
    if (p.balance < cost) return;

    p.balance -= cost;
    p.location = destination;

    await docRef.set(p);
    socket.emit('update-stats', p);
  });

  socket.on('heal', async () => {
    const email = socket.data.email;
    if (!email) return;

    const docRef = db.collection('players').doc(email);
    const doc = await docRef.get();
    if (!doc.exists) return;

    let p = doc.data();
    if (p.health >= 100) return;

    const cost = 50;
    if (p.balance < cost) return;

    p.balance -= cost;
    p.health = 100;

    await docRef.set(p);
    socket.emit('update-stats', p);
  });

  // NEW: Update profile (e.g., photoURL)
  socket.on('update-profile', async (data) => {
    const email = socket.data.email;
    if (!email || typeof data.photoURL !== 'string') return;

    const docRef = db.collection('players').doc(email);
    const doc = await docRef.get();
    if (!doc.exists) return;

    let p = doc.data();
    p.photoURL = data.photoURL;

    await docRef.set(p);
    socket.emit('update-stats', p);
  });

  // NEW: Purchase armor
  socket.on('purchase-armor', async (data) => {
    const email = socket.data.email;
    if (!email || !Array.isArray(data.items) || typeof data.totalCost !== 'number') return;

    const docRef = db.collection('players').doc(email);
    const doc = await docRef.get();
    if (!doc.exists) return;

    let p = doc.data();

    if (p.balance < data.totalCost) return; // Not enough balance

    // Validate total cost on server to prevent cheating
    let calculatedCost = 0;
    for (const item of data.items) {
      if (typeof item.cost === 'number') {
        calculatedCost += item.cost;
      }
    }
    if (calculatedCost !== data.totalCost) return; // Mismatch, possible cheat

    // Add items to inventory (append full objects)
    p.inventory = p.inventory.concat(data.items);
    p.balance -= data.totalCost;

    await docRef.set(p);
    socket.emit('update-stats', p);
  });

  // NEW: Equip armor
  socket.on('equip-armor', async (data) => {
    const email = socket.data.email;
    if (!email || typeof data.slot !== 'string' || typeof data.item !== 'object') return;

    const docRef = db.collection('players').doc(email);
    const doc = await docRef.get();
    if (!doc.exists) return;

    let p = doc.data();
    const slot = data.slot;
    const item = data.item;

    if (item.type !== slot) return;

    if (p[slot] !== null) {
      p.inventory.push(p[slot]);
      p.defense -= p[slot].defense || 0;
    }

    p[slot] = item;
    p.defense += item.defense || 0;
    const index = p.inventory.findIndex(i => i.name === item.name && i.type === item.type);
    if (index !== -1) {
      p.inventory.splice(index, 1);
    }

    await docRef.set(p);
    socket.emit('update-stats', p);
  });

  // NEW: Unequip armor
  socket.on('unequip-armor', async (data) => {
    const email = socket.data.email;
    if (!email || typeof data.slot !== 'string') return;

    const docRef = db.collection('players').doc(email);
    const doc = await docRef.get();
    if (!doc.exists) return;

    let p = doc.data();
    const slot = data.slot;

    if (p[slot] !== null) {
      const equipped = p[slot];
      p.inventory.push(equipped);
      p.defense -= equipped.defense || 0;
      p[slot] = null;
    }

    await docRef.set(p);
    socket.emit('update-stats', p);
  });

    // ==================== PRIVATE MESSAGES ====================
  socket.on('private-message', async (data) => {
    if (!data || typeof data.to !== 'string' || typeof data.msg !== 'string') return;

    const from = socket.data.displayName;
    if (!from) return;

    const msgId = data.id || Date.now().toString();

    const baseMsg = {
      from: from,
      msg: data.msg,
      id: msgId
    };

    // NEW: Find recipient by name (assume unique)
    const querySnapshot = await db.collection('players').where('displayName', '==', data.to).limit(1).get();
    if (querySnapshot.empty) return;

    const recipientDoc = querySnapshot.docs[0];
    const toEmail = recipientDoc.id;
    const recipientData = recipientDoc.data();

    // NEW: Save message for recipient
    const msgForRecipient = {
      type: 'private',
      data: baseMsg,
      timestamp: new Date().toISOString(),
      isRead: false
    };

    await recipientDoc.ref.update({
      messages: admin.firestore.FieldValue.arrayUnion(msgForRecipient)
    });

    // NEW: Save for sender too
    const senderDoc = await db.collection('players').doc(socket.data.email).get();
    if (senderDoc.exists) {
      const msgForSender = {
        type: 'private',
        data: { ...baseMsg, to: data.to, isFromMe: true },
        timestamp: new Date().toISOString(),
        isRead: true  // Sender sees their own as read
      };

      await senderDoc.ref.update({
        messages: admin.firestore.FieldValue.arrayUnion(msgForSender)
      });
    }

    // Send to recipient if online
    const targetSocket = onlineSockets.get(data.to);
    if (targetSocket) {
      targetSocket.emit('private-message', baseMsg);
    } else if (recipientData.fcmTokens && recipientData.fcmTokens.length > 0) {
      // FIXED: Send push if offline (use sendEachForMulticast)
      const fcmMessage = {
        notification: {
          title: `${from} sent a message`,
          body: data.msg
        },
        android: {
          priority: 'high'  // Removed invalid "group" field; grouping is client-side
        },
        data: {
          type: 'private',
          sender: from,  // FIXED: Renamed 'from' to 'sender' to avoid reserved key error
          msg: data.msg,
          id: msgId
        },
        tokens: recipientData.fcmTokens  // List of tokens
      };

      try {
        const response = await admin.messaging().sendEachForMulticast(fcmMessage);
        console.log(`Push sent to ${data.to}. Success: ${response.successCount}, Failure: ${response.failureCount}`);
        if (response.failureCount > 0) {
          response.responses.forEach((resp, index) => {
            if (!resp.success) {
              console.log('Failure for token ' + recipientData.fcmTokens[index] + ': ' + (resp.error ? resp.error.message : 'Unknown error'));
            }
          });
        }
      } catch (error) {
        console.error('Error sending push to ' + data.to + ': ' + error);
      }
    }

    // Echo to sender
    socket.emit('private-message', { ...baseMsg, to: data.to, isFromMe: true });
  });

  // ==================== ANNOUNCEMENTS ====================
  socket.on('announcement', async (text) => {
    if (typeof text === 'string' && text.length > 0) {
      // NEW: Save to special announcements box
      const annRef = await db.collection('announcements').add({
        text: text,
        timestamp: new Date().toISOString()
      });
      const annId = annRef.id;

      // Send to all online
      io.emit('announcement', { text: text, id: annId });

      // NEW: Send push to group
      const fcmMessage = {
        topic: 'announcements',
        notification: {
          title: 'Mod Announcement',
          body: text
        },
        android: {
          priority: 'high'  // Removed invalid "group" field; grouping is client-side
        },
        data: {
          type: 'announcement',
          text: text,
          id: annId
        }
      };

      await admin.messaging().send(fcmMessage);
      console.log('Sent announcement push');
    }
  });

  socket.on('disconnect', () => {
    if (socket.data.displayName) {
      const name = socket.data.displayName;
      onlinePlayers.delete(name);
      onlineSockets.delete(name);
      io.emit('online-players', Array.from(onlinePlayers));
      console.log(`[SERVER] ${name} left - online now: ${onlinePlayers.size}`);
    }
  });
});

const port = process.env.PORT || 3000;
server.listen(port, () => console.log(`Server running on ${port}`));