// courses.js
const courseTemplates = [
  {
    id: "basic-combat",
    name: "Basic Combat Training",
    cost: 850,
    durationMinutes: 45,
    effect: "+8 Marksmanship • +3 Overall Power",
    requirements: "None"
  },
  {
    id: "advanced-tactics",
    name: "Advanced Street Tactics",
    cost: 2400,
    durationMinutes: 90,
    effect: "+15 Skill • Unlock mid-level operation bonuses",
    requirements: "Rank: Corporal+"
  },
  {
    id: "marksmanship-master",
    name: "Marksmanship Mastery",
    cost: 5200,
    durationMinutes: 180,
    effect: "+25 Marksmanship • +12% weapon bonus",
    requirements: "Rank: Sergeant+ • Intelligence 8+"
  },
  {
    id: "taxi-management",
    name: "Taxi Fleet Management",
    cost: 1800,
    durationMinutes: 60,
    effect: "+20% taxi job income • Unlock driver scouting discount",
    requirements: "Own at least 1 vehicle in fleet"
  },
  {
    id: "business-acumen",
    name: "Business & Property Acumen",
    cost: 3100,
    durationMinutes: 120,
    effect: "+15% property income • Unlock advanced upgrades",
    requirements: "Own 2+ properties"
  },
  {
    id: "stealth-operations",
    name: "Stealth & Infiltration",
    cost: 4100,
    durationMinutes: 150,
    effect: "+18 Stealth • Lower prison chance on operations",
    requirements: "Rank: Lieutenant+"
  },
  {
    id: "intelligence-network",
    name: "Intelligence Network Building",
    cost: 6700,
    durationMinutes: 240,
    effect: "+22 Intelligence • +10% hit success chance",
    requirements: "Rank: Major+"
  }
];

async function handleRequestCourses(socket) {
  socket.emit('courses-list', courseTemplates);
}

module.exports = {
  courseTemplates,
  handleRequestCourses
};