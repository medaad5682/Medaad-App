import 'models/course_model.dart';

// --- 1. User Model (Required for Edit Profile) ---
class User {
  final String id;
  final String name;
  final String username;
  final List<String> enrolledCourses;

  User(
      {required this.id,
      required this.name,
      required this.username,
      required this.enrolledCourses});
}

// --- 2. Teacher Model ---
class Teacher {
  final String id;
  final String name;
  final String specialty;
  final String avatar;
  final String bio;

  Teacher(
      {required this.id,
      required this.name,
      required this.specialty,
      required this.avatar,
      required this.bio});
}

// --- 3. Mock Teachers ---
final List<Teacher> mockTeachers = [
  Teacher(
    id: 't1',
    name: 'Dr. Alex Rivera',
    specialty: 'UI/UX Design Master',
    avatar: 'https://i.pravatar.cc/150?u=t1',
    bio:
        'Award-winning designer with 10+ years of experience in mobile interfaces.',
  ),
  Teacher(
    id: 't2',
    name: 'Eng. Sarah Jenkins',
    specialty: 'Fullstack Architect',
    avatar: 'https://i.pravatar.cc/150?u=t2',
    bio:
        'Lead developer at top tech firm, passionate about React and scalable systems.',
  ),
];

// --- 4. Mock Exams ---
final ExamModel mockExam = ExamModel(
  id: 'e1',
  title: 'Material 3 Foundations Exam',
  durationMinutes: 15,
  questions: [
    Question(
      id: 'q1',
      text: 'What is the primary feature of Material You?',
      options: [
        'Strict color palettes',
        'Dynamic color extraction',
        'No shadows',
        '3D elements'
      ],
      correctIndex: 1,
      imageUrl: 'https://picsum.photos/seed/m3_1/600/300',
    )
  ],
);

// --- 5. Mock Courses ---
final List<CourseModel> mockCourses = [
  CourseModel(
    id: 'c1',
    teacherId: 't1',
    title: 'Modern UI Design with Material 3',
    rating: 4.8,
    reviews: 1240,
    description:
        'Master the latest design language by Google. Learn dynamic coloring and adaptive layouts.',
    fullPrice: 500,
    category: 'Design',
    exams: [mockExam],
    subjects: [
      Subject(
        id: 's1',
        title: 'Design Foundations',
        price: 200,
        chapters: [
          Chapter(
            id: 'ch1',
            title: 'Dynamic Coloring',
            lessons: [
              Lesson(
                  id: 'l1',
                  title: 'Extraction Logic',
                  type: LessonType.video,
                  duration: '12:45',
                  url: 'https://www.w3schools.com/html/mov_bbb.mp4'),
            ],
          ),
        ],
      ),
      Subject(
        id: 's2',
        title: 'Layout Systems',
        price: 350,
        chapters: [
          Chapter(
            id: 'ch2',
            title: 'Grid vs Flex',
            lessons: [
              Lesson(
                  id: 'l2',
                  title: 'Responsive Grids',
                  type: LessonType.video,
                  duration: '15:20',
                  url: 'https://www.w3schools.com/html/mov_bbb.mp4'),
            ],
          ),
        ],
      ),
    ],
    instructorName: '',
    code: '',
  ),
  CourseModel(
    id: 'c2',
    teacherId: 't2',
    title: 'Advanced React Architecture',
    rating: 4.9,
    reviews: 2150,
    description: 'Deep dive into patterns, performance, and state management.',
    fullPrice: 800,
    category: 'Development',
    subjects: [
      Subject(
        id: 's3',
        title: 'React Core Internals',
        price: 450,
        chapters: [],
      ),
    ],
    instructorName: '',
    code: '',
  ),
];
