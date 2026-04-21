import 'package:flutter/material.dart';
import 'socket_service.dart';
import 'status_app_bar.dart';

class CoursesPage extends StatefulWidget {
  const CoursesPage({super.key});

  @override
  State<CoursesPage> createState() => _CoursesPageState();
}

class _CoursesPageState extends State<CoursesPage> {
  @override
  void initState() {
    super.initState();
    SocketService().requestCourses();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: StatusAppBar(
        title: 'Training Courses',
        statsNotifier: SocketService().statsNotifier,
        time: '—',
        onMenuPressed: () => Navigator.pop(context),
      ),
      body: ValueListenableBuilder<List<Map<String, dynamic>>>(
        valueListenable: SocketService().coursesNotifier,
        builder: (context, courses, child) {
          if (courses.isEmpty) {
            return const Center(child: CircularProgressIndicator());
          }

          final playerCompleted = SocketService()
              .statsNotifier
              .value['completedCourses'] as List<dynamic>? ?? [];

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: courses.length,
            itemBuilder: (context, index) {
              final course = courses[index];
              final courseId = course['id'] as String?;

              // Check if player has already purchased this course
              final alreadyPurchased = playerCompleted.any((c) =>
                  c is Map && c['id'] == courseId);

              return Card(
                margin: const EdgeInsets.only(bottom: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                color: alreadyPurchased ? Colors.grey[800] : null, // Grey out
                child: InkWell(
                  onTap: alreadyPurchased
                      ? null // Disable tap
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
                            Text(' \$${course['cost']}', 
                                style: TextStyle(fontSize: 18, color: alreadyPurchased ? Colors.grey[400] : null)),
                            const Spacer(),
                            const Icon(Icons.timer, color: Colors.orange, size: 20),
                            Text(' ${course['durationMinutes']} min', 
                                style: TextStyle(fontSize: 18, color: alreadyPurchased ? Colors.grey[400] : null)),
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
            },
          );
        },
      ),
    );
  }
}