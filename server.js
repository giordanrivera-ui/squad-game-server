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

// ==================== LOCATIONS ====================
const normalLocations = [
  "Riverstone",
  "Thornbury",
  "Vostokgrad",
  "Eichenwald",
  "Montclair",
  "Valleora",
  "Lónghǎi",
  "Sakuragawa",
  "Cawayan Heights"
];

// ==================== TRAVEL COSTS ====================
const travelCosts = {
  "Riverstone": 40,
  "Thornbury": 45,
  "Vostokgrad": 110,
  "Eichenwald": 60,
  "Montclair": 85,
  "Valleora": 70,
  "Lónghǎi": 140,
  "Sakuragawa": 95,
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
    } else {
      // NEW PLAYER → now also starts with empty messages box
      const randomLocation = normalLocations[Math.floor(Math.random() * normalLocations.length)];

      playerData = {
        balance: 0,
        health: 100,
        lastRob: 0,
        displayName: displayName,
        location: randomLocation,
        messages: [],   // empty message box
        fcmTokens: []   // NEW: For push note keys
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
  });

  socket.on('rob-bank', async () => {
    const email = socket.data.email;
    if (!email) return;

    const docRef = db.collection('players').doc(email);
    const doc = await docRef.get();
    if (!doc.exists) return;

    let p = doc.data();

    if (Date.now() - (p.lastRob || 0) < 60000) return;

    const money = Math.floor(Math.random() * 91) + 10;
    const loss = Math.floor(Math.random() * 11) + 10;

    p.balance += money;
    p.health = Math.max(0, p.health - loss);
    p.lastRob = Date.now();

    await docRef.set(p);
    socket.emit('update-stats', p);

    if (p.health <= 0) {
      await docRef.delete();
      console.log(`Player ${email} died and data was reset`);
    }
  });

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
      // NEW: Send push if offline
      const fcmMessage = {
        tokens: recipientData.fcmTokens,
        notification: {
          title: `${from} sent a message`,
          body: data.msg
        },
        android: {
          notification: {
            group: `messages_from_${from.replace(/\s/g, '_')}`  // Bunch by sender
          },
          priority: 'high'
        },
        data: {
          type: 'private',
          from: from,
          msg: data.msg,
          id: msgId
        }
      };

      await admin.messaging().sendMulticast(fcmMessage);
      console.log(`Sent push to ${data.to}`);
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
          notification: {
            group: 'mod_announcements'  // Bunch announcements
          },
          priority: 'high'
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