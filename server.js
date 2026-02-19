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
const onlinePlayers = new Set();   // Tracks currently online display names

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
      // NEW PLAYER → Random starting location
      const randomLocation = normalLocations[Math.floor(Math.random() * normalLocations.length)];

      playerData = {
        balance: 0,
        health: 100,
        lastRob: 0,
        displayName: displayName,
        location: randomLocation
      };

      await docRef.set(playerData);
    }

    // Remember this socket
    socket.data.email = email;
    socket.data.displayName = displayName;

    // Add to online list and broadcast
    onlinePlayers.add(displayName);
    io.emit('online-players', Array.from(onlinePlayers));

    // Send player data to the client
    socket.emit('init', playerData);
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

    // Can't fly to same city or unknown city
    if (p.location === destination || travelCosts[destination] === undefined) return;

    const cost = travelCosts[destination];

    if (p.balance < cost) return;   // not enough money

    // Fly!
    p.balance -= cost;
    p.location = destination;

    await docRef.set(p);
    socket.emit('update-stats', p);   // tells the game screen to update
  });

  socket.on('disconnect', () => {
    if (socket.data.displayName) {
      onlinePlayers.delete(socket.data.displayName);
      io.emit('online-players', Array.from(onlinePlayers));
    }
  });
});

const port = process.env.PORT || 3000;
server.listen(port, () => console.log(`Server running on ${port}`));