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

  @override
  void initState() {
    super.initState();
    SocketService().requestCourses();

    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        setState(() {});
      
        if (SocketService().coursesNotifier.value.any((c) => 
            c['status'] == 'inProgress')) {
          SocketService().requestCourses();   // re-fetch so new courses appear
        }
      }

    });
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    super.dispose();
  }

    // ── CONNECTOR FOR HR RESEARCH CHAIN ──
  Widget _buildHRConnector() {
    return Padding(
      padding: const EdgeInsets.only(left: 52, right: 20, top: 8, bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Vertical line with nodes at both ends
          SizedBox(
            width: 28,
            height: 56,
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Main vertical line
                Positioned(
                  top: 14,
                  bottom: 14,
                  left: 12,
                  child: Container(
                    width: 4,
                    decoration: BoxDecoration(
                      color: Colors.amber.withOpacity(0.75),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                // Top node (circle)
                Positioned(
                  top: 8,
                  left: 8,
                  child: Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: Colors.amber,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.grey[900]!, width: 2.5),
                    ),
                  ),
                ),
                // Bottom node (circle)
                Positioned(
                  bottom: 8,
                  left: 8,
                  child: Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: Colors.amber,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.grey[900]!, width: 2.5),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          // Optional label (feels very polished)
          Expanded(
            child: Text(
              'Requires previous course to be completed',
              style: TextStyle(
                color: Colors.amber.withOpacity(0.85),
                fontSize: 13,
                fontStyle: FontStyle.italic,
                height: 1.3,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── BUILD LIST WITH CONNECTOR INSERTED ──
  List<Widget> _buildCoursesWithConnector(List<Map<String, dynamic>> courses) {
    final List<Widget> widgets = [];

    for (int i = 0; i < courses.length; i++) {
      widgets.add(_buildCourseCard(courses[i]));

      // Insert connector exactly between the two HR courses
      if (i < courses.length - 1 &&
          courses[i]['id'] == "hr-research" &&
          courses[i + 1]['id'] == "hr-research-advanced") {
        widgets.add(_buildHRConnector());
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

    Widget _buildCourseCard(Map<String, dynamic> course) {
    String status = course['status'] as String? ?? 'available';
    int? completionTime = course['completionTime'] as int?;

    if (status == 'inProgress' && completionTime != null) {
      final remainingMs = (completionTime - SocketService().currentServerTime).clamp(0, 999999999);
      if (remainingMs <= 0) status = 'completed';
    }

    if (status == 'inProgress') {
      final completionTime = course['completionTime'] as int? ?? 0;
      final remainingMs = (completionTime - SocketService().currentServerTime).clamp(0, 999999999);
      final totalMs = (course['durationMinutes'] as int) * 60 * 1000.0;
      final progress = totalMs > 0 ? 1.0 - (remainingMs / totalMs) : 0.0;

      final minutesLeft = (remainingMs ~/ 60000);
      final secondsLeft = ((remainingMs % 60000) ~/ 1000).toString().padLeft(2, '0');

      return Card(
        margin: const EdgeInsets.only(bottom: 16),
        color: Colors.grey[900],
        child: Padding(
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
      );
    }

    if (status == 'completed') {
      return Card(
        margin: const EdgeInsets.only(bottom: 16),
        color: Colors.green[900],
        child: Padding(
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
      );
    }

    // ==================== AVAILABLE COURSE (with requirement check) ====================
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: InkWell(
        onTap: () async {
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
                SnackBar(
                  content: Text(message),
                  backgroundColor: Colors.orange,
                  duration: const Duration(seconds: 4),
                ),
              );
              return;
            }
          }

          // All requirements met → purchase
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
    );
  }
}