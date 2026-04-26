import 'package:flutter/material.dart';
import 'dart:async';
import 'socket_service.dart';
import 'status_app_bar.dart';

class CoursesPage extends StatefulWidget {
  const CoursesPage({super.key});

  @override
  State<CoursesPage> createState() => _CoursesPageState();
}

class _CoursesPageState extends State<CoursesPage> {
  Timer? _countdownTimer;

  // HR chain IDs for stacking + smart connector logic (UNTOUCHED)
  final List<String> _hrChainIds = const [
    "hr-research",
    "hr-research-advanced",
    "hr-research-exceptional",
  ];

  // ==================== NEW: Street Tactics chain (exact mirror of HR) ====================
  final List<String> _streetTacticsChainIds = const [
    "street-tactics",
    "advanced-street-tactics",
    "exceptional-street-tactics",
  ];

  // Offset used when stacking completed chain courses
  static const double _hrStackOffset = -48.0;

  // Helper to detect any chain course
  bool _isChainCourse(String id) {
    return _hrChainIds.contains(id) || _streetTacticsChainIds.contains(id);
  }

  // Helper to check if two courses belong to the same chain
  bool _areInSameChain(String id1, String id2) {
    if (_hrChainIds.contains(id1) && _hrChainIds.contains(id2)) return true;
    if (_streetTacticsChainIds.contains(id1) && _streetTacticsChainIds.contains(id2)) return true;
    return false;
  }

  @override
  void initState() {
    super.initState();
    SocketService().requestCourses();

    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        setState(() {});
      
        if (SocketService().coursesNotifier.value.any((c) => 
            c['status'] == 'inProgress')) {
          SocketService().requestCourses();
        }
      }
    });
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    super.dispose();
  }

  // ── OVERLAY LOGIC (HR logic untouched + Street Tactics added) ──
  double _getOverlayOpacity(String courseId) {
    if (!_isChainCourse(courseId)) return 0.0;

    final allCourses = SocketService().coursesNotifier.value;
    final completedIds = allCourses
        .where((c) => (c['status'] as String?) == 'completed')
        .map((c) => c['id'] as String)
        .toSet();

    // HR chain (100% unchanged)
    if (courseId == "hr-research") {
      if (completedIds.contains("hr-research-exceptional")) {
        return 0.65; // darker overlay
      }
      if (completedIds.contains("hr-research-advanced")) {
        return 0.35; // normal semi-transparent
      }
    } else if (courseId == "hr-research-advanced") {
      if (completedIds.contains("hr-research-exceptional")) {
        return 0.35;
      }
    }

    // Street Tactics chain (exact mirror of HR)
    else if (courseId == "street-tactics") {
      if (completedIds.contains("exceptional-street-tactics")) return 0.65;
      if (completedIds.contains("advanced-street-tactics")) return 0.35;
    } else if (courseId == "advanced-street-tactics") {
      if (completedIds.contains("exceptional-street-tactics")) return 0.35;
    }

    return 0.0;
  }

  // ── TIGHTER CONNECTOR LINE (unchanged) ──
  Widget _buildHRConnectorLine() {
    return Padding(
      padding: const EdgeInsets.only(left: 39, top: 0),
      child: SizedBox(
        height: 28,
        child: Align(
          alignment: Alignment.centerLeft,
          child: Container(
            width: 4,
            height: 28,
            decoration: BoxDecoration(
              color: Colors.amber.withOpacity(0.9),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
      ),
    );
  }

  // ── BUILD LIST WITH STACKING + NODES + SMART CONNECTOR (now supports BOTH chains) ──
  List<Widget> _buildCoursesWithConnector(List<Map<String, dynamic>> courses) {
    final List<Widget> widgets = [];
    double accumulatedCompensation = 0.0;

    for (int i = 0; i < courses.length; i++) {
      final course = courses[i];
      final String id = course['id'] as String;
      final bool isCompleted = (course['status'] as String?) == 'completed';
      final bool isChain = _isChainCourse(id);

      // Should this card stack (overlap) the previous completed course in same chain?
      bool shouldStack = false;
      if (isChain && i > 0) {
        final prev = courses[i - 1];
        final prevId = prev['id'] as String;
        final prevCompleted = (prev['status'] as String?) == 'completed';

        if (_areInSameChain(prevId, id) && prevCompleted && isCompleted) {
          shouldStack = true;
        }
      }

      // Node visibility
      bool showBottomNode = false;
      bool showTopNode = false;

      // Show bottom node only on the LAST completed course in chain when next is pending
      if (isChain && isCompleted && i < courses.length - 1) {
        final nextCourse = courses[i + 1];
        final nextId = nextCourse['id'] as String;

        if (_areInSameChain(id, nextId) && 
            (nextCourse['status'] as String?) != 'completed') {
          showBottomNode = true;
        }
      }

      // Show top node only on the FIRST pending course in chain when previous is completed
      if (isChain && !isCompleted && i > 0) {
        final prev = courses[i - 1];
        final prevId = prev['id'] as String;
        final prevCompleted = (prev['status'] as String?) == 'completed';

        if (_areInSameChain(prevId, id) && prevCompleted) {
          showTopNode = true;
        }
      }

      widgets.add(_buildCourseCard(
        course,
        showTopConnectorNode: showTopNode,
        showBottomConnectorNode: showBottomNode,
        stackOffset: shouldStack ? _hrStackOffset : 0.0,
        topCompensationOffset: accumulatedCompensation,
        overlayOpacity: _getOverlayOpacity(id),
      ));

      // Accumulate offset on EVERY stacked card
      if (shouldStack) {
        accumulatedCompensation += _hrStackOffset;
      }

      // Insert connector line ONLY between last completed and next pending in SAME chain
      if (isChain && isCompleted && i < courses.length - 1) {
        final nextCourse = courses[i + 1];
        final nextId = nextCourse['id'] as String;

        if (_areInSameChain(id, nextId) && 
            (nextCourse['status'] as String?) != 'completed') {
          widgets.add(_buildHRConnectorLine());
        }
      }
    }
    return widgets;
  }
  
  @override
  Widget build(BuildContext context) {
    final courses = SocketService().coursesNotifier.value;

    return Scaffold(
      appBar: StatusAppBar(
        title: 'Training Courses',
        statsNotifier: SocketService().statsNotifier,
        time: 'Live',
        onMenuPressed: () => Navigator.pop(context),
      ),
      body: courses.isEmpty
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(40.0),
                child: CircularProgressIndicator(),
              ),
            )
          : ListView(
              padding: const EdgeInsets.all(16),
              children: _buildCoursesWithConnector(courses),
            ),
    );
  }

  Widget _buildCourseCard(
    Map<String, dynamic> course, {
    bool showTopConnectorNode = false,
    bool showBottomConnectorNode = false,
    double stackOffset = 0.0,
    double topCompensationOffset = 0.0,
    double overlayOpacity = 0.0,
  }) {
    String status = course['status'] as String? ?? 'available';
    int? completionTime = course['completionTime'] as int?;

    if (status == 'inProgress' && completionTime != null) {
      final remainingMs = (completionTime - SocketService().currentServerTime).clamp(0, 999999999);
      if (remainingMs <= 0) status = 'completed';
    }

    // ── NODE BUILDER (amber circles) ──
    Widget buildNode({required bool isTop}) {
      return Positioned(
        top: isTop ? -10 : null,
        bottom: isTop ? null : -10,
        left: 32,
        child: Container(
          width: 20,
          height: 20,
          decoration: BoxDecoration(
            color: Colors.amber,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.grey[900]!, width: 3),
          ),
        ),
      );
    }

    // ── IN PROGRESS CARD ──
    if (status == 'inProgress') {
      final completionTimeVal = course['completionTime'] as int? ?? 0;
      final remainingMs = (completionTimeVal - SocketService().currentServerTime).clamp(0, 999999999);
      final totalMs = (course['durationMinutes'] as int) * 60 * 1000.0;
      final progress = totalMs > 0 ? 1.0 - (remainingMs / totalMs) : 0.0;

      final minutesLeft = (remainingMs ~/ 60000);
      final secondsLeft = ((remainingMs % 60000) ~/ 1000).toString().padLeft(2, '0');

      Widget card = Card(
        margin: EdgeInsets.only(
          bottom: showBottomConnectorNode ? 4 : (stackOffset < 0 ? 8 : 16),
        ),
        color: Colors.grey[900],
        clipBehavior: Clip.none,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.school_outlined, color: Colors.amber, size: 28),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(course['name'],
                            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white)),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.amber.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Text(
                          'IN PROGRESS',
                          style: TextStyle(color: Colors.amber, fontWeight: FontWeight.bold, fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  LinearProgressIndicator(
                    value: progress,
                    color: Colors.amber,
                    backgroundColor: Colors.grey[700],
                    minHeight: 12,
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Time Remaining', style: TextStyle(color: Colors.grey[400])),
                      Text('$minutesLeft:$secondsLeft',
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.amber)),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text('Effect: ${course['effect']}', style: const TextStyle(fontSize: 15, color: Colors.white70)),
                ],
              ),
            ),
            if (showTopConnectorNode) buildNode(isTop: true),
            if (showBottomConnectorNode) buildNode(isTop: false),
          ],
        ),
      );

      final double totalOffset = stackOffset + topCompensationOffset;
      return totalOffset != 0.0
          ? Transform.translate(offset: Offset(0, totalOffset), child: card)
          : card;
    }

    // ── COMPLETED CARD (with requested semi-transparent overlay) ──
    if (status == 'completed') {
      Widget card = Card(
        margin: EdgeInsets.only(
          bottom: showBottomConnectorNode ? 0 : (stackOffset < 0 ? 8 : 8),
        ),
        color: Colors.green[900],
        clipBehavior: Clip.hardEdge,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  const Icon(Icons.check_circle, color: Colors.greenAccent, size: 32),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(course['name'],
                            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white)),
                        Text('✓ Completed — ${course['effect']}',
                            style: const TextStyle(color: Colors.greenAccent)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            
            // ── SEMI-TRANSPARENT OVERLAY (applied only to completed chain courses) ──
            if (overlayOpacity > 0.0)
              Positioned.fill(
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(overlayOpacity),
                  ),
                ),
              ),
            
            if (showTopConnectorNode) buildNode(isTop: true),
            if (showBottomConnectorNode) buildNode(isTop: false),
          ],
        ),
      );

      final double totalOffset = stackOffset + topCompensationOffset;
      return totalOffset != 0.0
          ? Transform.translate(offset: Offset(0, totalOffset), child: card)
          : card;
    }

    // ── AVAILABLE CARD ──
    Widget card = Card(
      margin: EdgeInsets.only(
        bottom: showBottomConnectorNode ? -4 : (stackOffset < 0 ? 8 : 16),
      ),
      clipBehavior: Clip.none,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          InkWell(
            onTap: () async {
              // Validation for Advanced HR (UNTOUCHED)
              if (course['id'] == "hr-research-advanced") {
                final stats = SocketService().statsNotifier.value;
                final List<String> missing = [];

                if ((stats['balance'] ?? 0) < 5000) missing.add("\$5000");
                if ((stats['intelligence'] ?? 0) < 2) missing.add("Intelligence level of 2");
                final basicCompleted = (stats['completedCourses'] ?? [])
                    .any((c) => c['id'] == "hr-research" && (c['completionTime'] ?? 0) <= SocketService().currentServerTime);
                if (!basicCompleted) missing.add("completed Human Resource Research");

                if (missing.isNotEmpty) {
                  final message = missing.length == 1 
                      ? "You need ${missing[0]} to enroll in Advanced Human Resource Research."
                      : "You are missing: ${missing.join(', ')} to enroll in Advanced Human Resource Research.";

                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(message), backgroundColor: Colors.orange),
                  );
                  return;
                }
              }

              // Validation for Exceptional HR (UNTOUCHED)
              if (course['id'] == "hr-research-exceptional") {
                final stats = SocketService().statsNotifier.value;
                final List<String> missing = [];

                if ((stats['balance'] ?? 0) < 7000) missing.add("\$7000");
                if ((stats['intelligence'] ?? 0) < 4) missing.add("Intelligence level of 4");

                final advancedCompleted = (stats['completedCourses'] ?? [])
                    .any((c) => c['id'] == "hr-research-advanced" && (c['completionTime'] ?? 0) <= SocketService().currentServerTime);

                if (!advancedCompleted) missing.add("completed Advanced Human Resource Research");

                if (missing.isNotEmpty) {
                  final message = missing.length == 1 
                      ? "You need ${missing[0]} to enroll in Exceptional Human Resource Research."
                      : "You are missing: ${missing.join(', ')} to enroll in Exceptional Human Resource Research.";

                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(message), backgroundColor: Colors.orange),
                  );
                  return;
                }
              }

              // ==================== NEW: Street Tactics client validation (exact mirror) ====================
              if (course['id'] == "advanced-street-tactics") {
                final stats = SocketService().statsNotifier.value;
                final List<String> missing = [];

                if ((stats['balance'] ?? 0) < 4000) missing.add("\$4000");
                if ((stats['skill'] ?? 0) < 1) missing.add("Skill level of 1");
                if ((stats['marksmanship'] ?? 0) < 1) missing.add("Marksmanship level of 1");

                final basicCompleted = (stats['completedCourses'] ?? [])
                    .any((c) => c['id'] == "street-tactics" && (c['completionTime'] ?? 0) <= SocketService().currentServerTime);

                if (!basicCompleted) missing.add("completed Street Tactics");

                if (missing.isNotEmpty) {
                  final message = missing.length == 1 
                      ? "You need ${missing[0]} to enroll in Advanced Street Tactics."
                      : "You are missing: ${missing.join(', ')} to enroll in Advanced Street Tactics.";

                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(message), backgroundColor: Colors.orange),
                  );
                  return;
                }
              }

              if (course['id'] == "exceptional-street-tactics") {
                final stats = SocketService().statsNotifier.value;
                final List<String> missing = [];

                if ((stats['balance'] ?? 0) < 6000) missing.add("\$6000");
                final advancedCompleted = (stats['completedCourses'] ?? [])
                    .any((c) => c['id'] == "advanced-street-tactics" && (c['completionTime'] ?? 0) <= SocketService().currentServerTime);

                if (!advancedCompleted) missing.add("completed Advanced Street Tactics");

                if (missing.isNotEmpty) {
                  final message = missing.length == 1 
                      ? "You need ${missing[0]} to enroll in Exceptional Street Tactics."
                      : "You are missing: ${missing.join(', ')} to enroll in Exceptional Street Tactics.";

                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(message), backgroundColor: Colors.orange),
                  );
                  return;
                }
              }

              SocketService().purchaseCourse(course['id']);
            },
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(course['name'], style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      const Icon(Icons.attach_money, color: Colors.green),
                      Text(' \$${course['cost']}'),
                      const Spacer(),
                      const Icon(Icons.timer, color: Colors.orange),
                      Text(' ${course['durationMinutes']} min'),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text('Effect: ${course['effect']}', style: const TextStyle(fontSize: 16)),
                  if (course['requirements'] != "None")
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text('Requirements: ${course['requirements']}',
                          style: const TextStyle(color: Colors.grey)),
                    ),
                  const Align(
                    alignment: Alignment.centerRight,
                    child: Text('Tap to enroll →', style: TextStyle(color: Colors.blue)),
                  ),
                ],
              ),
            ),
          ),
          if (showTopConnectorNode) buildNode(isTop: true),
          if (showBottomConnectorNode) buildNode(isTop: false),
        ],
      ),
    );

    final double totalOffset = stackOffset + topCompensationOffset;
    return totalOffset != 0.0
        ? Transform.translate(offset: Offset(0, totalOffset), child: card)
        : card;
  }
}