// This file holds all the magic words and numbers we use a lot

class SocketEvents {
  static const String register = 'register';
  static const String robBank = 'rob-bank';
  static const String message = 'message';
  static const String time = 'time';
  static const String init = 'init';
  static const String updateStats = 'update-stats';
  static const String onlinePlayers = 'online-players';
  static const String travel = 'travel';
  static const String privateMessage = 'private-message';   // ← NEW
  static const String announcement = 'announcement';        // ← NEW for mods
}

class GameConstants {
  static const String serverUrl = 'https://squad-game-server.onrender.com';
  static const int robCooldownSeconds = 60;
  static const int maxChatMessages = 100;
}