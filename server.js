// Updated server.js - Copy this entire code and replace your old server.js
const express = require('express');
const http = require('http');
const { Server } = require('socket.io');
const app = express();
const server = http.createServer(app);
const io = new Server(server, { cors: { origin: "*" } });

const players = new Map(); // Stores player data: socket.id -> {balance, health, lastRob}

const timeFormatter = new Intl.DateTimeFormat('en-GB', {
  timeZone: 'Europe/London',
  hour: '2-digit',
  minute: '2-digit',
  hour12: false
});

// Send UK time to all players every 30 seconds
setInterval(() => {
  const now = new Date();
  const timeStr = timeFormatter.format(now);
  io.emit('time', timeStr);
}, 30000);

io.on('connection', (socket) => {
  console.log('Player joined:', socket.id);

  // Initialize new player
  players.set(socket.id, {
    balance: 1000,
    health: 100,
    lastRob: 0
  });

  // Send initial stats to this player only
  socket.emit('init', players.get(socket.id));

  // Broadcast messages (chat)
  socket.on('message', (msg) => {
    io.emit('message', msg); // Broadcast to everyone
  });

  // Handle rob-bank request
  socket.on('rob-bank', () => {
    const player = players.get(socket.id);
    if (!player) return;

    const now = Date.now();
    if (now - player.lastRob < 60000) {
      // Cooldown active - ignore
      return;
    }

    // Random money: 10-100
    const money = Math.floor(Math.random() * 91) + 10;
    // Random health loss: 10-20
    const healthLoss = Math.floor(Math.random() * 11) + 10;

    player.balance += money;
    player.health = Math.max(0, player.health - healthLoss);
    player.lastRob = now;

    // Send updated stats back to this player only
    socket.emit('update-stats', player);
    console.log(`Player ${socket.id.slice(0,8)} robbed: +$${money}, -${healthLoss} HP`);
  });

  // Clean up on disconnect
  socket.on('disconnect', () => {
    console.log('Player left:', socket.id);
    players.delete(socket.id);
  });
});

const port = process.env.PORT || 3000;
server.listen(port, () => console.log(`Server running on port ${port}!`));