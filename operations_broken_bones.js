function handleBrokenBone(player, level, message) {
  const now = Date.now();
  let normalCooldownStartTime = now;

  // === Chance to break a bone this operation ===
  let brokenBoneChance = 0;

  if (level === "low") {
    brokenBoneChance = 0.05;
  } else if (level === "mid") {
    brokenBoneChance = 0.09;
  } else if (level === "high") {
    brokenBoneChance = 0.14;
  }

  if (!player.hasBrokenBone && brokenBoneChance > 0 && Math.random() < brokenBoneChance) {
    player.hasBrokenBone = true;
    message += " 💥 You broke a bone during the operation!";
    console.log(`[SERVER] ${player.displayName} broke a bone during operation`);
  }

  // === Apply bone penalty + delay cooldown if player has a broken bone ===
  if (player.hasBrokenBone) {
    if (level === "low") {
      player.bonePenaltyEndTimeLow = now + 10000;
      normalCooldownStartTime = now + 10000;
      message += " ⏳ Low-level ops locked for 10s (bone recovery).";
    } else if (level === "mid") {
      player.bonePenaltyEndTimeMid = now + 10000;
      normalCooldownStartTime = now + 10000;
      message += " ⏳ Mid-level ops locked for 10s (bone recovery).";
    } else if (level === "high") {
      player.bonePenaltyEndTimeHigh = now + 10000;
      normalCooldownStartTime = now + 10000;
      message += " ⏳ High-level ops locked for 10s (bone recovery).";
    }
  }

  return {
    message,
    normalCooldownStartTime
  };
}

module.exports = { handleBrokenBone };