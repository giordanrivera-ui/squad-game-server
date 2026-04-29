const admin = require('firebase-admin');
const { logTransaction } = require('./utils');
const { syncPartyTeamSynergy } = require('./specialOperations.js');

const courseTemplates = [
    {
    id: "team-synergy",
    name: "Team Synergy",
    cost: 2000,
    durationMinutes: 2,
    effect: "Increases the overall power of a Special Operation party by 2.5%",
    requirements: "None"
  },
  {
    id: "advanced-team-synergy",
    name: "Advanced Team Synergy",
    cost: 4000,
    durationMinutes: 2,
    effect: "Increases the overall power of a Special Operation party by 5%",
    requirements: "Team Synergy completed and minimum skill, intelligence and marksmanship of 1."
  },
  {
    id: "exceptional-team-synergy",
    name: "Exceptional Team Synergy",
    cost: 6000,
    durationMinutes: 2,
    effect: "Increases the overall power of a Special Operation party by 7.5%",
    requirements: "Team Synergy completed and minimum skill, intelligence and marksmanship of 2."
  },
  {
    id: "street-tactics",
    name: "Street Tactics",
    cost: 2000,
    durationMinutes: 2,
    effect: "Increases the amount of money and exp gained from mugging passerbys",
    requirements: "None"
  },
  {
    id: "advanced-street-tactics",
    name: "Advanced Street Tactics",
    cost: 4000,
    durationMinutes: 2,
    effect: "Further increases the amount of money and exp gained from mugging passerbys and looting grocery stores.",
    requirements: "Street Tactics completed and minimum Skill of 1 and minimum marksmanship of 1"
  },
  {
    id: "exceptional-street-tactics",
    name: "Exceptional Street Tactics",
    cost: 6000,
    durationMinutes: 2,
    effect: "Further increases the amount of money and exp gained from mugging passerbys and all other low level ops.",
    requirements: "Advanced Street Tactics completed and minimum Skill of 2 and minimum marksmanship of 2"
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
    requirements: "Human Resource Research completed and a minimum Intelligence of 2."
  },
  {
    id: "hr-research-exceptional",
    name: "Exceptional Human Resource Research",
    cost: 7000,
    durationMinutes: 2,
    effect: "Further increases the average quality of the drivers you will scout in Taxi Tycoon.",
    requirements: "Advanced Human Resource Research completed and a minimum Intelligence of 4."
  },
  {
    id: "property-acumen",
    name: "Business & Property Acumen",
    cost: 8000,
    durationMinutes: 2,
    effect: "Increase the income of all properties by 1%",
    requirements: "Minimum intelligence of 2"
  },
  {
    id: "advanced-property-acumen",
    name: "Advanced Business & Property Acumen",
    cost: 20000,
    durationMinutes: 2,
    effect: "Increase the income of all properties by another 1%",
    requirements: "Minimum intelligence of 4"
  },
  {
    id: "exceptional-property-acumen",
    name: "Exceptional Business & Property Acumen",
    cost: 45000,
    durationMinutes: 2,
    effect: "Increase the income of all properties by another 1%",
    requirements: "Minimum intelligence of 6"
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

// ==================== FIXED + ENHANCED UNIFIED COURSE LIST ====================
function getUnifiedCourses(playerData) {
  const now = Date.now();

  return courseTemplates.map(template => {
    const completedCourse = (playerData.completedCourses || [])
      .find(c => c.id === template.id);

    if (completedCourse && completedCourse.completionTime <= now) {
      return { 
        ...template, 
        status: 'completed' 
      };
    }

    if (completedCourse && completedCourse.completionTime > now) {
      const remainingMs = completedCourse.completionTime - now;
      const totalMs = template.durationMinutes * 60 * 1000;
      return {
        ...template,
        status: 'inProgress',
        completionTime: completedCourse.completionTime,
        progress: Math.max(0, 1 - (remainingMs / totalMs)),
        remainingMs: remainingMs,
      };
    }

    // HR chain logic – now also used by server validation
    if (template.id === "hr-research-advanced") {
      const basicCompleted = (playerData.completedCourses || [])
        .some(c => c.id === "hr-research" && c.completionTime <= now);
      if (!basicCompleted) return null;
    }

    if (template.id === "hr-research-exceptional") {
      const advancedCompleted = (playerData.completedCourses || [])
        .some(c => c.id === "hr-research-advanced" && c.completionTime <= now);
      if (!advancedCompleted) return null;
    }

    // ==================== NEW: Street Tactics chain logic (exact mirror of HR) ====================
    if (template.id === "advanced-street-tactics") {
      const basicCompleted = (playerData.completedCourses || [])
        .some(c => c.id === "street-tactics" && c.completionTime <= now);
      if (!basicCompleted) return null;
    }

    if (template.id === "exceptional-street-tactics") {
      const advancedCompleted = (playerData.completedCourses || [])
        .some(c => c.id === "advanced-street-tactics" && c.completionTime <= now);
      if (!advancedCompleted) return null;
    }

    return { 
      ...template, 
      status: 'available',
    };
  }).filter(Boolean);
}

async function handleRequestCourses(db, socket) {
  const email = socket.data.email;
  if (!email) return;

  const doc = await db.collection('players').doc(email).get();
  const playerData = doc.exists ? doc.data() : {};

  const unifiedCourses = getUnifiedCourses(playerData);

  socket.emit('courses-list', unifiedCourses);
}

async function handlePurchaseCourse(db, socket, courseId, { onlineSockets, syncPartyTeamSynergy }) {
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


  if (course.id === "hr-research-advanced") {
    const errors = [];

    if ((p.balance || 0) < 5000) errors.push("$5000");
    if ((p.intelligence || 0) < 2) errors.push("Intelligence level of 2");
    const basicCompleted = (p.completedCourses || []).some(c => 
      c.id === "hr-research" && c.completionTime <= Date.now()
    );
    if (!basicCompleted) errors.push("completed Human Resource Research");

    if (errors.length > 0) {
      const message = errors.length === 1 
        ? `You need ${errors[0]} to enroll in Advanced Human Resource Research.`
        : `You are missing: ${errors.join(', ')} to enroll in Advanced Human Resource Research.`;

      socket.emit('course-result', { success: false, message });
      return;
    }
  }

  if (course.id === "hr-research-exceptional") {
    const errors = [];

    if ((p.balance || 0) < 7000) errors.push("$7000");
    if ((p.intelligence || 0) < 4) errors.push("Intelligence level of 4");
    const advancedCompleted = (p.completedCourses || []).some(c => 
      c.id === "hr-research-advanced" && c.completionTime <= Date.now()
    );
    if (!advancedCompleted) errors.push("completed Advanced Human Resource Research");

    if (errors.length > 0) {
      const message = errors.length === 1 
        ? `You need ${errors[0]} to enroll in Exceptional Human Resource Research.`
        : `You are missing: ${errors.join(', ')} to enroll in Exceptional Human Resource Research.`;

      socket.emit('course-result', { success: false, message });
      return;
    }
  }

  if (course.id === "advanced-street-tactics") {
    const errors = [];

    if ((p.balance || 0) < 4000) errors.push("$4000");
    if ((p.skill || 0) < 1) errors.push("Skill level of 1");
    if ((p.marksmanship || 0) < 1) errors.push("Marksmanship level of 1");

    const basicCompleted = (p.completedCourses || []).some(c => 
      c.id === "street-tactics" && c.completionTime <= Date.now()
    );
    if (!basicCompleted) errors.push("completed Street Tactics");

    if (errors.length > 0) {
      const message = errors.length === 1 
        ? `You need ${errors[0]} to enroll in Advanced Street Tactics.`
        : `You are missing: ${errors.join(', ')} to enroll in Advanced Street Tactics.`;

      socket.emit('course-result', { success: false, message });
      return;
    }
  }

  if (course.id === "exceptional-street-tactics") {
    const errors = [];

    if ((p.balance || 0) < 6000) errors.push("$6000");
    if ((p.skill || 0) < 2) errors.push("Skill level of 2");
    if ((p.marksmanship || 0) < 2) errors.push("Marksmanship level of 2");

    const advancedCompleted = (p.completedCourses || []).some(c => 
      c.id === "advanced-street-tactics" && c.completionTime <= Date.now()
    );
    if (!advancedCompleted) errors.push("completed Advanced Street Tactics");

    if (errors.length > 0) {
      const message = errors.length === 1 
        ? `You need ${errors[0]} to enroll in Exceptional Street Tactics.`
        : `You are missing: ${errors.join(', ')} to enroll in Exceptional Street Tactics.`;

      socket.emit('course-result', { success: false, message });
      return;
    }
  }

  // Normal balance check (applies to all courses)
  if ((p.balance || 0) < course.cost) {
    socket.emit('course-result', { success: false, message: 'Not enough money.' });
    return;
  }

  // === Proceed with purchase ===
  await logTransaction(socket, -course.cost, `Course Purchased: ${course.name}`, p, docRef);
  p.balance -= course.cost;

  if (!p.completedCourses) p.completedCourses = [];
  const now = Date.now();
  const completionTime = now + (course.durationMinutes * 60 * 1000);

  p.completedCourses.push({
    id: course.id,
    name: course.name,
    completionTime: completionTime
  });

  // ==================== NEW: Team Synergy family handling ====================
  // If this was any of the three Team Synergy courses AND the player is currently
  // leading a party, immediately recalculate and broadcast the new power.
  const isTeamSynergyCourse = 
    course.id === "team-synergy" ||
    course.id === "advanced-team-synergy" ||
    course.id === "exceptional-team-synergy";

  if (isTeamSynergyCourse && 
      p.activeSpecialOperationParty && 
      p.activeSpecialOperationParty.leaderEmail === email) {
    
    await syncPartyTeamSynergy(db, email, { onlineSockets });
    console.log(`[COURSE] ${p.displayName} completed ${course.name} — party power updated live`);
  }

  await docRef.set(p);
  socket.emit('update-stats', p);

  const updatedPlayer = (await docRef.get()).data();
  const unifiedCourses = getUnifiedCourses(updatedPlayer);

  socket.emit('courses-list', unifiedCourses);
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