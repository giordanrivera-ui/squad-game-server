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

    // Live countdown for progress bars (exactly like bonds_screen.dart and properties_screen.dart)
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });

    // Listen for server updates to in-progress courses
    SocketService().inProgressCoursesNotifier.addListener(_refreshUI);
  }

  void _refreshUI() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    SocketService().inProgressCoursesNotifier.removeListener(_refreshUI);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final inProgressCourses = SocketService().inProgressCoursesNotifier.value;
    final availableCourses = SocketService().coursesNotifier.value;

    final playerCompleted = SocketService()
        .statsNotifier
        .value['completedCourses'] as List<dynamic>? ?? [];

    return Scaffold(
      appBar: StatusAppBar(
        title: 'Training Courses',
        statsNotifier: SocketService().statsNotifier,
        time: 'Live', // Changed to "Live" for consistency with other screens
        onMenuPressed: () => Navigator.pop(context),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ==================== IN PROGRESS SECTION ====================
          if (inProgressCourses.isNotEmpty) ...[
            const Text(
              'In Progress',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 12),
            ...inProgressCourses.map((course) => _buildInProgressCard(course)),
            const SizedBox(height: 32),
          ],

          // ==================== AVAILABLE COURSES SECTION ====================
          const Text(
            'Available Courses',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 12),

          if (availableCourses.isEmpty)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(40.0),
                child: CircularProgressIndicator(),
              ),
            )
          else
            ...availableCourses.map((course) {
              final courseId = course['id'] as String?;
              final alreadyPurchased = playerCompleted.any((c) =>
                  c is Map && c['id'] == courseId);

              return _buildAvailableCourseCard(
                course,
                alreadyPurchased,
                courseId,
              );
            }),
        ],
      ),
    );
  }

  // ==================== IN-PROGRESS CARD (live progress bar) ====================
  Widget _buildInProgressCard(Map<String, dynamic> course) {
    final completionTime = course['completionTime'] as int? ?? 0;
    final now = SocketService().currentServerTime;
    final remainingMs = (completionTime - now).clamp(0, 999999999);
    final totalMs = (course['durationMinutes'] as int) * 60 * 1000.0;
    final progress = totalMs > 0 ? 1.0 - (remainingMs / totalMs) : 0.0;

    final minutesLeft = (remainingMs ~/ 60000);
    final secondsLeft = ((remainingMs % 60000) ~/ 1000).toString().padLeft(2, '0');

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      color: Colors.grey[900], // Normal vibrant color (not greyed out)
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
                  child: Text(
                    course['name'],
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.amber.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Text(
                    'IN PROGRESS',
                    style: TextStyle(
                      color: Colors.amber,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      letterSpacing: 1.2,
                    ),
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
                Text(
                  'Time Remaining',
                  style: TextStyle(color: Colors.grey[400], fontSize: 14),
                ),
                Text(
                  '$minutesLeft:$secondsLeft',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.amber,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'Effect: ${course['effect']}',
              style: const TextStyle(fontSize: 15, color: Colors.white70),
            ),
          ],
        ),
      ),
    );
  }

  // ==================== AVAILABLE COURSE CARD (your original design) ====================
  Widget _buildAvailableCourseCard(
    Map<String, dynamic> course,
    bool alreadyPurchased,
    String? courseId,
  ) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      color: alreadyPurchased ? Colors.grey[800] : null,
      child: InkWell(
        onTap: alreadyPurchased
            ? null
            : () {
                if (courseId != null) {
                  SocketService().purchaseCourse(courseId);
                }
              },
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                course['name'],
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: alreadyPurchased ? Colors.grey[400] : Colors.white,
                ),
              ),
              const SizedBox(height: 12),

              Row(
                children: [
                  const Icon(Icons.attach_money, color: Colors.green, size: 20),
                  Text(
                    ' \$${course['cost']}',
                    style: TextStyle(
                      fontSize: 18,
                      color: alreadyPurchased ? Colors.grey[400] : null,
                    ),
                  ),
                  const Spacer(),
                  const Icon(Icons.timer, color: Colors.orange, size: 20),
                  Text(
                    ' ${course['durationMinutes']} min',
                    style: TextStyle(
                      fontSize: 18,
                      color: alreadyPurchased ? Colors.grey[400] : null,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 12),
              Text(
                'Effect: ${course['effect']}',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: alreadyPurchased ? Colors.grey[400] : null,
                ),
              ),

              if (course['requirements'] != "None")
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    'Requirements: ${course['requirements']}',
                    style: TextStyle(
                      fontSize: 15,
                      color: alreadyPurchased ? Colors.grey[500] : Colors.grey,
                    ),
                  ),
                ),

              if (alreadyPurchased)
                const Padding(
                  padding: EdgeInsets.only(top: 12),
                  child: Text(
                    '✓ Already purchased',
                    style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold),
                  ),
                )
              else
                const Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    'Tap to enroll →',
                    style: TextStyle(fontSize: 14, color: Colors.blue),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}