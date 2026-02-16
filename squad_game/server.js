const express = require('express');  // "Use the express tool"
const http = require('http');        // "Use the http tool for web stuff"
const { Server } = require('socket.io');  // "Use socket.io for real-time"

const app = express();               // "Start a simple web app"
const server = http.createServer(app);  // "Wrap it in a web server"
const io = new Server(server, { cors: { origin: "*" } });  // "Add real-time magic; * means anyone can connect"

io.on('connection', (socket) => {    // "When a player connects..."
  console.log('A player joined!');   // "Print a message to screen"
  socket.on('message', (msg) => {    // "If they send a message..."
    io.emit('message', msg);         // "...send it to EVERYONE"
  });
  // Add your game rules here later, like "move player" or "update score"
});

const port = process.env.PORT || 3000;
server.listen(port, () => console.log(`Server running on port ${port}!`));