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
const messaging = admin.messaging();  // NEW FOR FCM: Initialize messaging

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

// NEW FOR IMPROVED PUSH: A big toy box for each player's messages to group them!
const notificationQueues = new Map(); // Key: recipient displayName, Value: {messages: [], timer: null}

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
        messages: []   // ← NEW: empty message box
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

  // ==================== PRIVATE MESSAGES (updated for grouping push) ====================
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

    const targetSocket = onlineSockets.get(data.to);
    if (targetSocket) {
      targetSocket.emit('private-message', baseMsg);
      socket.emit('private-message', { ...baseMsg, to: data.to, isFromMe: true });
    }

    // NEW FOR IMPROVED PUSH: Add to queue instead of sending right away
    const recipient = data.to;
    if (!notificationQueues.has(recipient)) {
      notificationQueues.set(recipient, {messages: [], timer: null});
    }
    const queue = notificationQueues.get(recipient);
    queue.messages.push({from: from, msg: data.msg});

    if (!queue.timer) {
      queue.timer = setTimeout(async () => {
        // Like opening the toy box after waiting!
        const count = queue.messages.length;
        let title = '';
        let body = '';

        if (count === 1) {
          title = `New Message from ${queue.messages[0].from}`;
          body = queue.messages[0].msg.length > 50 ? `${queue.messages[0].msg.substring(0, 47)}...` : queue.messages[0].msg;
        } else {
          const senders = [...new Set(queue.messages.map(m => m.from))]; // Unique friends
          title = `You have ${count} new messages`;
          body = `From ${senders.join(' and ')}`; // Like "From Bob and Alice"
        }

        // Get the phone beep token (same as before)
        const recipientDoc = await db.collection('players').where('displayName', '==', recipient).limit(1).get();
        if (!recipientDoc.empty) {
          const recipientData = recipientDoc.docs[0].data();
          const fcmToken = recipientData.fcmToken;
          if (fcmToken) {
            const payload = {
              notification: {
                title: title,
                body: body,
              },
            };
            try {
              await messaging.send({ ...payload, token: fcmToken });
              console.log(`Grouped notification sent to ${recipient}`);
            } catch (error) {
              console.error('Error sending grouped notification:', error);
            }
          }
        }

        // Empty the box for next time
        queue.messages = [];
        queue.timer = null;
      }, 5000); // Wait 5 seconds (like counting 1-2-3-4-5)
    }
  });

  socket.on('announcement', async (text) => {
    if (typeof text === 'string' && text.length > 0) {
      io.emit('announcement', text);

      // NEW FOR FCM: Send to all players with tokens (no grouping for now, since rare)
      const allPlayers = await db.collection('players').get();
      const tokens = [];
      allPlayers.forEach((doc) => {
        const playerData = doc.data();
        if (playerData.fcmToken) tokens.push(playerData.fcmToken);
      });

      if (tokens.length > 0) {
        const payload = {
          notification: {
            title: 'Mod Announcement',
            body: text.length > 50 ? `${text.substring(0, 47)}...` : text,
          },
        };
        try {
          await messaging.sendMulticast({ ...payload, tokens });
          console.log(`Announcement notification sent to ${tokens.length} players`);
        } catch (error) {
          console.error('Error sending announcement notifications:', error);
        }
      }
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