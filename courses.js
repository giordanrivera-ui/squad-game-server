const admin = require('firebase-admin');
const { logTransaction } = require('./utils');

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
    id: "hr-research",
    name: "Human Resource Research",
    cost: 2500,
    durationMinutes: 2,
    effect: "Increases the average quality of the drivers you will scout in Taxi Tycoon.",
    requirements: "None"
  },
  {
    id: "hr-research-advanced",
    name: "Advanced Human Resource Research",
    cost: 5000,
    durationMinutes: 2,
    effect: "Further increases the average quality of the drivers you will scout in Taxi Tycoon.",
    requirements: "Human Resource Research and a minimum Intelligence of 2."
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

// Add at the top of courses.js (after courseTemplates)
function getInProgressCourses(playerData) {
  const now = Date.now();
  return (playerData.completedCourses || [])
    .filter(c => c.completionTime > now)
    .map(c => {
      const template = courseTemplates.find(t => t.id === c.id);
      return {
        ...c,
        durationMinutes: template ? template.durationMinutes : 0,   // ← ADD THIS
      };
    });
}

// Helper to get available courses for a player (handles the HR chain)
function getAvailableCourses(playerData) {
  const completedIds = new Set(
    (playerData.completedCourses || []).map(c => c.id)
  );

  return courseTemplates.filter(course => {
    // Special HR Research chain logic
    if (course.id === "hr-research") {
      return !completedIds.has("hr-research");           // Show basic only if not purchased
    }
    if (course.id === "hr-research-advanced") {
      return completedIds.has("hr-research");            // Show advanced ONLY after basic is purchased
    }

    // All other courses always show
    return true;
  });
}

async function handleRequestCourses(db, socket) {
  const email = socket.data.email;
  if (!email) return;

  const doc = await db.collection('players').doc(email).get();
  const playerData = doc.exists ? doc.data() : {};

  const availableCourses = getAvailableCourses(playerData);
  const inProgress = getInProgressCourses(playerData);

  socket.emit('courses-list', availableCourses);
  socket.emit('in-progress-courses', inProgress);
}

// ==================== PURCHASE COURSE ====================
async function handlePurchaseCourse(db, socket, courseId) {
  const email = socket.data.email;
  if (!email) return;

  const docRef = db.collection('players').doc(email);
  const doc = await docRef.get();
  if (!doc.exists) return;

  let p = doc.data();

  const course = courseTemplates.find(c => c.id === courseId);
  if (!course) {
    socket.emit('course-result', { success: false, message: 'Course not found.' });
    return;
  }

  // Prevent repurchase
  if (p.completedCourses && p.completedCourses.some(c => c.id === course.id)) {
    socket.emit('course-result', { 
      success: false, 
      message: `You have already enrolled in ${course.name}.` 
    });
    return;
  }

  if ((p.balance || 0) < course.cost) {
    socket.emit('course-result', { success: false, message: 'Not enough money.' });
    return;
  }

  // Deduct cost immediately
  await logTransaction(socket, -course.cost, `Course Purchased: ${course.name}`, p, docRef);
  p.balance -= course.cost;

  // Record completion time
  if (!p.completedCourses) p.completedCourses = [];
  const now = Date.now();
  const completionTime = now + (course.durationMinutes * 60 * 1000);

  p.completedCourses.push({
    id: course.id,
    name: course.name,
    completionTime: completionTime
  });

  await docRef.set(p);
  socket.emit('update-stats', p);

  // === ADD THIS RIGHT AFTER THE EXISTING emit('update-stats') ===
  const updatedPlayer = (await docRef.get()).data();
  const available = getAvailableCourses(updatedPlayer);
  const inProgress = getInProgressCourses(updatedPlayer);

  socket.emit('courses-list', available);           // available courses
  socket.emit('in-progress-courses', inProgress);   // ← NEW event

  socket.emit('course-result', {
    success: true,
    message: `✅ Enrolled in ${course.name}! Effect activates in ${course.durationMinutes} minutes.`
  });
}

module.exports = {
  courseTemplates,
  handleRequestCourses,
  handlePurchaseCourse
};