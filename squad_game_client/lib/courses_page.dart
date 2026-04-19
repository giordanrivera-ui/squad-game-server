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
    SocketService().requestCourses(); // Ask server for latest list
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: StatusAppBar(
        title: 'Training Courses',
        statsNotifier: SocketService().statsNotifier,
        time: '—', // Time not critical here
        onMenuPressed: () => Navigator.pop(context),
      ),
      body: ValueListenableBuilder<List<Map<String, dynamic>>>(
        valueListenable: SocketService().coursesNotifier,
        builder: (context, courses, child) {
          if (courses.isEmpty) {
            return const Center(child: CircularProgressIndicator());
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: courses.length,
            itemBuilder: (context, index) {
              final course = courses[index];

              return Card(
                margin: const EdgeInsets.only(bottom: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                child: InkWell(
                  onTap: () {
                    // TODO: Later - purchase / enroll logic
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('${course['name']} selected (enrollment coming soon)'),
                      ),
                    );
                  },
                  borderRadius: BorderRadius.circular(16),
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          course['name'],
                          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 12),

                        Row(
                          children: [
                            const Icon(Icons.attach_money, color: Colors.green, size: 20),
                            Text(' \$${course['cost']}', style: const TextStyle(fontSize: 18)),
                            const Spacer(),
                            const Icon(Icons.timer, color: Colors.orange, size: 20),
                            Text(' ${course['durationMinutes']} min', style: const TextStyle(fontSize: 18)),
                          ],
                        ),

                        const SizedBox(height: 12),
                        Text(
                          'Effect: ${course['effect']}',
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
                        ),

                        if (course['requirements'] != "None")
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text(
                              'Requirements: ${course['requirements']}',
                              style: const TextStyle(fontSize: 15, color: Colors.grey),
                            ),
                          ),

                        const SizedBox(height: 8),
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