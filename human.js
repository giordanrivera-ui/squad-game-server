class Human {
  constructor(data = {}) {
    this.name = data.name || 'Unknown Human';
    this.health = data.health ?? 100;
    this.hunger = data.hunger ?? 100;
    this.balance = data.balance ?? 0;
    this.strength = data.strength ?? 0;
    this.stealth = data.stealth ?? 0;
    this.martialArt = data.martialArt || null;
    this.weapon = data.weapon || null;
    this.drunk = data.drunk ?? false;
    this.vicinity = data.vicinity || [];
    this.lastHungerUpdate = data.lastHungerUpdate || Date.now();
    }

  // Optional helper methods you can expand later
  isAlive() {
    return this.health > 0;
  }

  takeDamage(amount) {
    this.health = Math.max(0, this.health - amount);
  }

  heal(amount) {
    this.health = Math.min(100, this.health + amount); // assuming 100 is max
  }

  addToVicinity(playerName) {
    if (!this.vicinity.includes(playerName)) {
      this.vicinity.push(playerName);
    }
  }

  removeFromVicinity(playerName) {
    this.vicinity = this.vicinity.filter(name => name !== playerName);
  }

  // ==================== FIRESTORE HELPER ====================
  toFirestore() {
    return {
        health: this.health,
        hunger: this.hunger,
        balance: this.balance,
        strength: this.strength,
        stealth: this.stealth,
        martialArt: this.martialArt,
        weapon: this.weapon,
        drunk: this.drunk,
        vicinity: this.vicinity,
        lastHungerUpdate: this.lastHungerUpdate || Date.now(),   // ← Add this line
        updatedAt: Date.now()
    };
    }
}

module.exports = Human;