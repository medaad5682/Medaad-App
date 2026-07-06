import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../core/constants/app_colors.dart';
import '../../l10n/generated/app_localizations.dart';
import 'home_screen.dart';
import 'my_courses_screen.dart';
import 'profile_screen.dart';
import 'downloaded_files_screen.dart'; 

class MainWrapper extends StatefulWidget {
  const MainWrapper({super.key});

  @override
  State<MainWrapper> createState() => _MainWrapperState();
}

class _MainWrapperState extends State<MainWrapper> {
  int _currentIndex = 0;

  final List<Widget> _pages = [
    const HomeScreen(),
    const MyCoursesScreen(),
    const DownloadedFilesScreen(), 
    const ProfileScreen(),
  ];

  void _onTabTapped(int index) {
    setState(() {
      _currentIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    // ✅ الحصول على حشوة النظام السفلية (ارتفاع شريط التنقل الخاص بالهاتف)
    final double bottomPadding = MediaQuery.of(context).padding.bottom;

    return Scaffold(
      backgroundColor: AppColors.backgroundPrimary,
      body: IndexedStack(
        index: _currentIndex,
        children: _pages,
      ),
      // ✅ تعديل البار السفلي لدعم Safe Area
      bottomNavigationBar: Container(
        // ❌ تم حذف height: 80 الثابت من هنا ليصبح الارتفاع ديناميكياً
        decoration: BoxDecoration(
          color: AppColors.backgroundSecondary.withOpacity(0.9), 
          border: const Border(
            top: BorderSide(color: Colors.white10), 
          ),
        ),
        // ✅ إضافة مسافة سفلية بمقدار ارتفاع أزرار النظام
        padding: EdgeInsets.only(bottom: bottomPadding), 
        
        // ✅ استخدام SizedBox للحفاظ على ارتفاع تصميم البار (80) + المسافة السفلية
        child: SizedBox(
          height: 80, 
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildNavItem(0, LucideIcons.home, AppLocalizations.of(context)!.navHome),
              _buildNavItem(1, LucideIcons.bookOpen, AppLocalizations.of(context)!.navCourses),
              _buildNavItem(2, LucideIcons.download, AppLocalizations.of(context)!.navDownloads),
              _buildNavItem(3, LucideIcons.user, AppLocalizations.of(context)!.navProfile),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem(int index, IconData icon, String label) {
    final isSelected = _currentIndex == index;
    
    return GestureDetector(
      onTap: () => _onTabTapped(index),
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: 80, 
        child: Stack(
          alignment: Alignment.center,
          children: [
            if (isSelected)
              Positioned(
                top: 0,
                child: Container(
                  width: 48,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.accentYellow,
                    borderRadius: BorderRadius.circular(2),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.accentYellow.withOpacity(0.5),
                        blurRadius: 12, 
                      )
                    ],
                  ),
                ),
              ),

            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const SizedBox(height: 8), 
                Icon(
                  icon,
                  size: 24,
                  color: isSelected ? AppColors.accentYellow : AppColors.textSecondary,
                ),
                const SizedBox(height: 6),
                Text(
                  label.toUpperCase(),
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.5, 
                    color: isSelected 
                        ? AppColors.accentYellow 
                        : AppColors.textSecondary.withOpacity(0.6),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
