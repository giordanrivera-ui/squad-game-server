const express = require('express');
const http = require('http');
const { Server } = require('socket.io');
const app = express();
const server = http.createServer(app);
const io = new Server(server, { cors: { origin: "*" } });

const players = new Map();

const timeFormatter = new Intl.DateTimeFormat('en-GB', { timeZone: 'Europe/London', hour: '2-digit', minute: '2-digit', hour12: false });

setInterval(() => {
  io.emit('time', timeFormatter.format(new Date()));
}, 30000);

io.on('connection', (socket) => {
  socket.on('register', (email) => {
    if (!players.has(email)) {
      players.set(email, { balance: 0, health: 100, lastRob: 0 });
    }
    socket.emit('init', players.get(email));
    socket.data.email = email; // Remember who this socket is
  });

  socket.on('rob-bank', () => {
    const email = socket.data.email;
    if (!email) return;
    const p = players.get(email);
    if (!p || Date.now() - p.lastRob < 60000) return;

    const money = Math.floor(Math.random() * 91) + 10;
    const loss = Math.floor(Math.random() * 11) + 10;

    p.balance += money;
    p.health = Math.max(0, p.health - loss);
    p.lastRob = Date.now();

    socket.emit('update-stats', p);
  });

  socket.on('message', (msg) => {
    const email = socket.data.email || 'Anonymous';
    io.emit('message', `${email}: ${msg}`);
  });

  socket.on('disconnect', () => {
    // Keep player data (they can log back in)
  });
});

const port = process.env.PORT || 3000;
server.listen(port, () => console.log(`Server running on ${port}`));