import 'package:dio/dio.dart';
import '../constants/api_constants.dart';
import 'api_client.dart';
import '../../data/models/survey_model.dart';

/// خدمة إدارة الاستبيانات (Feedback / Survey).
///
/// القواعد المطلوبة:
/// - لا يظهر الاستبيان مرة أخرى لو الطالب حلّه من قبل (يتحقق منها السيرفر
///   عبر جدول survey_responses).
/// - لو الطالب تجاهل (skip) استبيان غير إلزامي، يُعاد سؤاله عند إعادة فتح
///   التطبيق فقط (وليس فوراً) => لذلك لا نخزّن التجاهل بشكل دائم، فقط في
///   الذاكرة (session) طول ما التطبيق شغال.
/// - استبيان واحد فقط في المرة الواحدة: نتحقق من وجود استبيان معلّق مرة
///   واحدة فقط لكل "جلسة تشغيل" للتطبيق (حتى لو المستخدم رجع لنفس الشاشة
///   عدة مرات) حتى لا تظهر نوافذ متتالية.
class SurveyService {
  SurveyService._();

  /// true إذا كنا بالفعل تحققنا من وجود استبيان معلّق في هذه الجلسة.
  static bool _checkedThisSession = false;

  /// أرقام الاستبيانات التي تم تجاهلها (skip) في هذه الجلسة فقط، لمنع
  /// إعادة عرضها فوراً، مع السماح بإعادة عرضها بعد إعادة فتح التطبيق.
  static final Set<int> _skippedThisSession = {};

  static bool get alreadyCheckedThisSession => _checkedThisSession;

  /// يُستدعى مرة واحدة تقريباً عند دخول المستخدم للشاشة الرئيسية.
  /// يرجّع null لو مفيش استبيان مناسب للعرض الآن.
  static Future<SurveyModel?> fetchPendingSurveyIfNeeded() async {
    if (_checkedThisSession) return null;
    _checkedThisSession = true;

    try {
      final response = await ApiClient.instance.get(
        '${ApiConstants.baseUrl}/api/student/surveys/pending',
      );

      if (response.statusCode == 200 &&
          response.data['success'] == true &&
          response.data['survey'] != null) {
        final survey = SurveyModel.fromJson(response.data['survey']);
        if (_skippedThisSession.contains(survey.id)) return null;
        return survey;
      }
    } on DioException catch (_) {
      // تجاهل بصمت: عدم توفر الإنترنت لا يجب أن يعطل الشاشة الرئيسية
    } catch (_) {}
    return null;
  }

  static void markSkippedThisSession(int surveyId) {
    _skippedThisSession.add(surveyId);
  }

  /// يُستدعى عند تسجيل الخروج حتى تُعاد كل الفحوصات عند الدخول مرة أخرى.
  static void resetSession() {
    _checkedThisSession = false;
    _skippedThisSession.clear();
  }

  static Future<bool> submitSurvey({
    required int surveyId,
    required List<SurveyAnswerDraft> answers,
  }) async {
    final response = await ApiClient.instance.post(
      '${ApiConstants.baseUrl}/api/student/surveys/submit',
      data: {
        'survey_id': surveyId,
        'answers': answers.map((a) => a.toJson()).toList(),
      },
    );
    return response.statusCode == 200 && response.data['success'] == true;
  }
}
