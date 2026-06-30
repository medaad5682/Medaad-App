import 'package:flutter/material.dart';
import '../../../core/services/teacher_service.dart';
import '../../../core/constants/app_colors.dart';
import 'package:Medaad/l10n/generated/app_localizations.dart';

class ManageTeamScreen extends StatefulWidget {
  const ManageTeamScreen({Key? key}) : super(key: key);

  @override
  State<ManageTeamScreen> createState() => _ManageTeamScreenState();
}

class _ManageTeamScreenState extends State<ManageTeamScreen> {
  final TeacherService _teacherService = TeacherService();
  final TextEditingController _searchController = TextEditingController();

  List<dynamic> _teamMembers = []; // المشرفون الحاليون
  List<dynamic> _searchResults = []; // نتائج البحث
  bool _isLoadingTeam = true;
  bool _isSearching = false;

  @override
  void initState() {
    super.initState();
    _loadTeam();
  }

  // جلب المشرفين الحاليين
  Future<void> _loadTeam() async {
    setState(() => _isLoadingTeam = true);
    try {
      final data = await _teacherService.getTeamMembers();
      if (mounted) {
        setState(() {
          _teamMembers = data;
          _isLoadingTeam = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoadingTeam = false);
      }
    }
  }

  // البحث عن طلاب لترقيتهم
  Future<void> _searchStudents(String query) async {
    // ✅ إضافة تنبيه للمستخدم إذا كان النص قصيراً جداً عند الضغط على زر البحث
    if (query.trim().length < 3) {
      setState(() => _searchResults = []);
      if (query.trim().isNotEmpty) {
         ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context)!.searchMinCharsWarning), backgroundColor: AppColors.accentOrange),
        );
      }
      return;
    }

    setState(() => _isSearching = true);
    try {
      final results = await _teacherService.searchStudentsForTeam(query.trim());
      if (mounted) {
        setState(() {
          _searchResults = results;
          _isSearching = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isSearching = false);
    }
  }

  // تنفيذ الترقية أو الحذف
  Future<void> _handleAction(String userId, String action, String confirmText) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.backgroundSecondary, // ✅ خلفية متوافقة مع الثيم
        title: Text(
          action == 'promote' ? AppLocalizations.of(context)!.promoteStudentDialogTitle : AppLocalizations.of(context)!.removeSupervisorDialogTitle,
          style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold),
        ),
        content: Text(
          confirmText,
          style: TextStyle(color: AppColors.textSecondary), // ✅ نص متوافق
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false), 
            child: Text(AppLocalizations.of(context)!.cancel, style: TextStyle(color: AppColors.textSecondary))
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: action == 'promote' ? AppColors.success : AppColors.error,
              foregroundColor: Colors.white,
            ),
            child: Text(AppLocalizations.of(context)!.confirm),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    // إظهار مؤشر تحميل
    showDialog(
      context: context, 
      barrierDismissible: false,
      builder: (_) => Center(child: CircularProgressIndicator(color: AppColors.accentYellow))
    );

    try {
      await _teacherService.manageTeamMember(action: action, userId: userId);
      
      if (mounted) {
        Navigator.pop(context); // إغلاق اللودينج
        
        // تنظيف وإعادة تحميل البيانات
        if (action == 'promote') {
           _searchController.clear();
           setState(() => _searchResults = []);
        }
        await _loadTeam(); // تحديث قائمة الفريق

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(action == 'promote' ? AppLocalizations.of(context)!.promoteSuccessMessage : AppLocalizations.of(context)!.demoteSuccessMessage),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context); // إغلاق اللودينج
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context)!.errorOccurredWithDetails(e.toString())), backgroundColor: AppColors.error),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundPrimary, // ✅ خلفية رئيسية متوافقة
      appBar: AppBar(
        title: Text(AppLocalizations.of(context)!.manageTeamTitle, style: TextStyle(color: AppColors.textPrimary)),
        backgroundColor: AppColors.backgroundSecondary, // ✅ هيدر متوافق
        elevation: 0,
        iconTheme: IconThemeData(color: AppColors.accentYellow),
      ),
      body: Column(
        children: [
          // -----------------------------------------------------
          // 1. قسم البحث والترقية
          // -----------------------------------------------------
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.backgroundSecondary, // ✅ خلفية القسم متوافقة
              border: Border(bottom: BorderSide(color: AppColors.textSecondary.withOpacity(0.1))),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  AppLocalizations.of(context)!.addNewSupervisorTitle, 
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppColors.textPrimary)
                ),
                const SizedBox(height: 5),
                Text(
                  AppLocalizations.of(context)!.addSupervisorSubtitle, 
                  style: TextStyle(fontSize: 12, color: AppColors.textSecondary)
                ),
                const SizedBox(height: 15),
                TextField(
                  controller: _searchController,
                  style: TextStyle(color: AppColors.textPrimary), // ✅ لون النص متوافق
                  textInputAction: TextInputAction.search, // ✅ تغيير زر الكيبورد لزر بحث
                  onSubmitted: (val) => _searchStudents(val), // ✅ البحث عند الضغط على Enter في الكيبورد
                  onChanged: (val) {
                    setState(() {}); // ✅ تحديث الواجهة فقط لإظهار/إخفاء زر الحذف، دون تنفيذ البحث
                  },
                  decoration: InputDecoration(
                    hintText: AppLocalizations.of(context)!.searchByNameOrUsernameHint,
                    hintStyle: TextStyle(color: AppColors.textSecondary.withOpacity(0.5)),
                    prefixIcon: Icon(Icons.person_search, color: AppColors.textSecondary),
                    suffixIcon: _isSearching 
                        ? Padding(padding: const EdgeInsets.all(10), child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.accentYellow)) 
                        : Row( // ✅ استخدام Row لإضافة زر البحث وزر الحذف
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (_searchController.text.isNotEmpty)
                                IconButton(
                                  icon: Icon(Icons.clear, color: AppColors.textSecondary),
                                  onPressed: () {
                                    _searchController.clear();
                                    setState(() => _searchResults = []);
                                  }
                                ),
                              // ✅ زر البحث اليدوي
                              IconButton(
                                icon: Icon(Icons.search, color: AppColors.accentYellow),
                                onPressed: () => _searchStudents(_searchController.text),
                              ),
                            ],
                          ),
                    filled: true,
                    fillColor: AppColors.backgroundPrimary, // ✅ لون الحقل متوافق
                    contentPadding: const EdgeInsets.symmetric(horizontal: 15, vertical: 10),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                  ),
                ),
              ],
            ),
          ),

          // -----------------------------------------------------
          // 2. قائمة نتائج البحث (تظهر فقط عند البحث)
          // -----------------------------------------------------
          if (_searchResults.isNotEmpty)
            Container(
              constraints: const BoxConstraints(maxHeight: 250),
              color: AppColors.backgroundPrimary, // ✅
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 5),
                    child: Text(AppLocalizations.of(context)!.searchResultsLabel, style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.accentYellow)),
                  ),
                  Expanded(
                    child: ListView.separated(
                      itemCount: _searchResults.length,
                      separatorBuilder: (ctx, i) => Divider(height: 1, color: AppColors.textSecondary.withOpacity(0.1)),
                      itemBuilder: (context, index) {
                        final student = _searchResults[index];
                        return ListTile(
                          leading: CircleAvatar(
                            backgroundColor: AppColors.backgroundSecondary,
                            child: Icon(Icons.person_outline, color: AppColors.accentYellow),
                          ),
                          title: Text(student['first_name'] ?? AppLocalizations.of(context)!.noNameFallback, style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
                          subtitle: Text("@${student['username']} • ${student['phone']}", style: TextStyle(color: AppColors.textSecondary)),
                          trailing: ElevatedButton(
                            onPressed: () => _handleAction(
                              student['id'].toString(), 
                              'promote', 
                              AppLocalizations.of(context)!.promoteConfirmMessage(student['first_name'] ?? AppLocalizations.of(context)!.noNameFallback)
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.success, 
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 12),
                              minimumSize: const Size(60, 32)
                            ),
                            child: Text(AppLocalizations.of(context)!.promoteAction),
                          ),
                        );
                      },
                    ),
                  ),
                  Divider(thickness: 5, color: AppColors.textSecondary.withOpacity(0.05)), 
                ],
              ),
            ),

          // -----------------------------------------------------
          // 3. قائمة المشرفين الحاليين
          // -----------------------------------------------------
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Row(
              children: [
                Icon(Icons.shield_outlined, color: AppColors.accentYellow, size: 20),
                const SizedBox(width: 8),
                Text(
                  AppLocalizations.of(context)!.currentSupervisorsCountLabel(_teamMembers.length.toString()), 
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: AppColors.textPrimary)
                ),
              ],
            ),
          ),

          Expanded(
            child: _isLoadingTeam
                ? Center(child: CircularProgressIndicator(color: AppColors.accentYellow))
                : _teamMembers.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.group_off_outlined, size: 60, color: AppColors.textSecondary.withOpacity(0.3)),
                            const SizedBox(height: 10),
                            Text(AppLocalizations.of(context)!.noSupervisorsCurrently, style: TextStyle(color: AppColors.textSecondary)),
                          ],
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.all(10),
                        itemCount: _teamMembers.length,
                        itemBuilder: (context, index) {
                          final member = _teamMembers[index];
                          return Card(
                            margin: const EdgeInsets.only(bottom: 10),
                            elevation: 0,
                            color: AppColors.backgroundSecondary, // ✅ لون الكارت
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                              side: BorderSide(color: AppColors.textSecondary.withOpacity(0.1))
                            ),
                            child: ListTile(
                              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                              leading: CircleAvatar(
                                radius: 25,
                                backgroundColor: AppColors.backgroundPrimary,
                                child: Icon(Icons.security, color: AppColors.accentYellow),
                              ),
                              title: Text(
                                member['first_name'] ?? AppLocalizations.of(context)!.unknownFallback,
                                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppColors.textPrimary),
                              ),
                              subtitle: Padding(
                                padding: const EdgeInsets.only(top: 4.0),
                                child: Text(
                                  "@${member['username']} • ${member['phone']}",
                                  style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
                                ),
                              ),
                              trailing: IconButton(
                                icon: Icon(Icons.remove_circle_outline, color: AppColors.error),
                                tooltip: AppLocalizations.of(context)!.removeSupervisorTooltip,
                                onPressed: () => _handleAction(
                                  member['id'].toString(), 
                                  'demote', 
                                  AppLocalizations.of(context)!.demoteConfirmMessage(member['first_name'] ?? AppLocalizations.of(context)!.unknownFallback)
                                ),
                              ),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}
