class Lesson {
  final String title;
  final String duration;
  final bool isFree; // هل الدرس مجاني للمعاينة؟

  Lesson({required this.title, required this.duration, this.isFree = false});
}

class Chapter {
  final String title;
  final String subtitle; // عدد الدروس والساعات
  final List<Lesson> lessons;

  Chapter({required this.title, required this.subtitle, required this.lessons});
}

// بيانات تجريبية (Mock Data)
final List<Chapter> dummyChapters = [
  Chapter(
    title: "1. Introduction to Mechanics",
    subtitle: "3 Lessons • 45 mins",
    lessons: [
      Lesson(title: "Welcome to the Course", duration: "05:00", isFree: true),
      Lesson(title: "What is Physics?", duration: "15:00", isFree: true),
      Lesson(title: "Vectors & Scalars", duration: "25:00"),
    ],
  ),
  Chapter(
    title: "2. Newton's Laws of Motion",
    subtitle: "5 Lessons • 2h 10m",
    lessons: [
      Lesson(title: "First Law: Inertia", duration: "20:00"),
      Lesson(title: "Second Law: F=ma", duration: "35:00"),
      Lesson(title: "Third Law: Action & Reaction", duration: "15:00"),
      Lesson(title: "Free Body Diagrams", duration: "40:00"),
      Lesson(title: "Practice Problems", duration: "20:00"),
    ],
  ),
  Chapter(title: "3. Work, Energy & Power", subtitle: "4 Lessons • 1h 30m", lessons: []),
];
