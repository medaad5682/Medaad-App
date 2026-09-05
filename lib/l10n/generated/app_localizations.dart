// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Arabic (`ar`).
class AppLocalizationsAr extends AppLocalizations {
  AppLocalizationsAr([String locale = 'ar']) : super(locale);

  @override
  String get appTitle => 'مــــداد';

  @override
  String get cancel => 'إلغاء';

  @override
  String get save => 'حفظ';

  @override
  String get delete => 'حذف';

  @override
  String get confirm => 'تأكيد';

  @override
  String get confirmDelete => 'تأكيد الحذف';

  @override
  String get ok => 'حسناً';

  @override
  String get yes => 'نعم';

  @override
  String get no => 'لا';

  @override
  String get close => 'إغلاق';

  @override
  String get retry => 'إعادة المحاولة';

  @override
  String get loading => 'جاري التحميل...';

  @override
  String get error => 'خطأ';

  @override
  String get success => 'تم بنجاح';

  @override
  String get language => 'اللغة';

  @override
  String get languageEnglish => 'الإنجليزية';

  @override
  String get languageArabic => 'العربية';

  @override
  String get languageChangeRestartNotice =>
      'سيتم إعادة تشغيل التطبيق لتطبيق اللغة الجديدة.';

  @override
  String get splashTagline => 'ننمّي قدراتك';

  @override
  String get splashLoadingSystem => 'جاري تحميل النظام';

  @override
  String get termsWelcomeTitle => 'مرحباً بك';

  @override
  String get termsDialogBody =>
      'يرجى الموافقة على الشروط والأحكام وسياسة الخصوصية للمتابعة.';

  @override
  String get termsAndConditions => 'الشروط والأحكام';

  @override
  String get privacyPolicy => 'سياسة الخصوصية';

  @override
  String get decline => 'رفض';

  @override
  String get accept => 'موافق';

  @override
  String get appUpdateTitle => 'تحديث التطبيق';

  @override
  String get updateLater => 'لاحقًا';

  @override
  String get updateNow => 'تحديث الآن';

  @override
  String get offlineModeEnteredMessage =>
      'لا يوجد اتصال بالإنترنت. جاري الدخول لوضع عدم الاتصال.';

  @override
  String get offlineModeLimitedMessage => 'وضع عدم الاتصال (وصول محدود)';

  @override
  String get connectionError => 'خطأ في الاتصال';

  @override
  String get signIn => 'تسجيل الدخول';

  @override
  String get createAccount => 'إنشاء حساب';

  @override
  String get passwordLabel => 'كلمة المرور';

  @override
  String get alreadyHaveAccount => 'لديك حساب بالفعل؟ ';

  @override
  String get newStudentQuestion => 'طالب جديد؟ ';

  @override
  String get loginEmptyFieldsError =>
      'يرجى إدخال اسم المستخدم/الهاتف وكلمة المرور';

  @override
  String get loginFailedDefault => 'فشل تسجيل الدخول';

  @override
  String get loginTitle => 'تسجيل الدخول';

  @override
  String get loginSubtitle => 'يرجى تسجيل الدخول للمتابعة.';

  @override
  String get usernameOrPhoneLabel => 'اسم المستخدم أو الهاتف';

  @override
  String get usernameOrPhoneHint => 'أدخل اسم المستخدم أو 01xxxxxxxxx';

  @override
  String get browseAsGuest => 'تصفح كزائر';

  @override
  String get registerAllFieldsRequired => 'جميع الحقول مطلوبة';

  @override
  String get registerUsernameInvalid =>
      'يجب أن يتكون اسم المستخدم من حروف إنجليزية وأرقام فقط';

  @override
  String get registerPhoneInvalid => 'رقم هاتف غير صالح (11 رقم يبدأ بـ 01)';

  @override
  String get registerPasswordTooShort =>
      'يجب أن تتكون كلمة المرور من 6 أحرف على الأقل';

  @override
  String get registerPasswordMismatch => 'كلمتا المرور غير متطابقتين';

  @override
  String get registerSuccessMessage =>
      'تم إنشاء الحساب بنجاح. يرجى تسجيل الدخول.';

  @override
  String get registerFailedDefault => 'فشل إنشاء الحساب';

  @override
  String get emailLabel => 'البريد الإلكتروني';

  @override
  String get emailHint => 'example@email.com';

  @override
  String get emailInvalid => 'يرجى إدخال بريد إلكتروني صحيح';

  @override
  String get otpTitle => 'تحقق من بريدك الإلكتروني';

  @override
  String get otpSubtitle => 'أرسلنا رمز تحقق مكوّن من 6 أرقام إلى';

  @override
  String get otpCodeHint => 'رمز التحقق المكوّن من 6 أرقام';

  @override
  String get otpVerifyButton => 'تأكيد الرمز';

  @override
  String get otpDidntReceive => 'لم يصلك الرمز؟';

  @override
  String get otpResendButton => 'إعادة إرسال الرمز';

  @override
  String otpResendIn(int seconds) {
    return 'إعادة الإرسال بعد $seconds ث';
  }

  @override
  String get otpCodeRequired => 'يرجى إدخال رمز التحقق المكوّن من 6 أرقام';

  @override
  String get otpSentMessage => 'تم إرسال رمز التحقق إلى بريدك الإلكتروني';

  @override
  String get otpVerifiedMessage => 'تم التحقق من البريد الإلكتروني بنجاح';

  @override
  String get otpSendFailedDefault => 'تعذر إرسال رمز التحقق';

  @override
  String get otpVerifyFailedDefault => 'الرمز غير صحيح أو منتهي الصلاحية';

  @override
  String get otpChangeEmail => 'تغيير البريد الإلكتروني';

  @override
  String get registerSubtitle => 'املأ البيانات للانضمام إلينا.';

  @override
  String get fullNameLabel => 'الاسم الكامل';

  @override
  String get fullNameHint => 'اسمك الكامل';

  @override
  String get phoneNumberOptionalLabel => 'رقم الهاتف (اختياري)';

  @override
  String get phoneNumberHint => '01xxxxxxxxx';

  @override
  String get usernameEnglishOnlyLabel => 'اسم المستخدم (إنجليزي فقط)';

  @override
  String get usernameHint => 'اسم المستخدم';

  @override
  String get confirmPasswordLabel => 'تأكيد كلمة المرور';

  @override
  String get navHome => 'الرئيسية';

  @override
  String get navCourses => 'الكورسات';

  @override
  String get navDownloads => 'التحميلات';

  @override
  String get navProfile => 'الملف الشخصي';

  @override
  String get homeWelcomeGreeting => 'مرحباً';

  @override
  String get guestFallbackName => 'زائر';

  @override
  String get encouragement1 => 'المعرفة هي مفتاح إطلاق إمكاناتك الحقيقية.';

  @override
  String get encouragement2 => 'كل خبير كان يوماً مبتدئاً. استمر في التعلم.';

  @override
  String get encouragement3 =>
      'نسختك المستقبلية ستشكرك على الجهد الذي تبذله اليوم.';

  @override
  String get encouragement4 => 'استثمر في نفسك؛ فالتعليم يمنحك أفضل عائد.';

  @override
  String get encouragement5 => 'التعلّم لا يُتعب العقل أبداً. حافظ على فضولك!';

  @override
  String get suggestedForYou => 'مقترح لك';

  @override
  String get searchResults => 'نتائج البحث';

  @override
  String get activeLabel => 'نشط';

  @override
  String get noCoursesFound => 'لم يتم العثور على كورسات';

  @override
  String get searchCourseHint => 'ابحث باسم الكورس أو الكود...';

  @override
  String get libraryTitle => 'المكتبة';

  @override
  String get guestModeLabel => 'وضع الزائر';

  @override
  String get loginRequiredTitle => 'يجب تسجيل الدخول';

  @override
  String get loginRequiredMessage =>
      'سجّل الدخول لعرض كورساتك المسجلة والوصول إليها.';

  @override
  String get courseNotFound => 'الكورس غير موجود';

  @override
  String get unknownInstructor => 'مدرّس غير معروف';

  @override
  String get instructorProfileUnavailable => 'الملف الشخصي للمدرّس غير متاح';

  @override
  String get instructorLabel => 'المدرّس';

  @override
  String get noDescriptionAvailable => 'لا يوجد وصف متاح.';

  @override
  String get teacherAccountLabel => 'حساب معلم';

  @override
  String get teachersCannotPurchaseMessage => 'لا يمكن للمعلمين شراء الكورسات.';

  @override
  String get courseContentLabel => 'محتوى الكورس';

  @override
  String get purchaseOptionsLabel => 'خيارات الشراء';

  @override
  String get fullCourseLabel => 'الكورس الكامل';

  @override
  String get fullCourseAccessLabel => 'الوصول للكورس الكامل';

  @override
  String get accessAllSubjectsExams => 'الوصول لجميع المواد والامتحانات';

  @override
  String get courseOwnedLabel => 'الكورس مملوك';

  @override
  String get individualSubjectsLabel => 'المواد الفردية';

  @override
  String get ownedLabel => 'مملوك';

  @override
  String priceEgp(String price) {
    return '$price جنيه';
  }

  @override
  String get totalPayableLabel => 'المبلغ الإجمالي';

  @override
  String get freeActivationLabel => 'تفعيل مجاني';

  @override
  String get activateButton => 'تفعيل';

  @override
  String get checkoutButton => 'الدفع';

  @override
  String get selectItemsFirstError => 'يرجى اختيار عناصر أولاً';

  @override
  String get activationSuccessMessage => 'تم التفعيل بنجاح! ✅';

  @override
  String get activationFailedMessage => 'فشل التفعيل. حاول مرة أخرى.';

  @override
  String get instructorFallback => 'المدرّس';

  @override
  String get chooseSubjectLabel => 'اختر المادة';

  @override
  String get noSubjectsFound => 'لا توجد مواد';

  @override
  String get failedToLoadContent => 'فشل تحميل المحتوى.';

  @override
  String get studentFeedbackDialogTitle => 'رأيك يهمنا';

  @override
  String get studentFeedbackHint =>
      'اكتب رأيك أو ملاحظاتك عن هذا الفصل (رأيك مجهول الهوية)';

  @override
  String get studentFeedbackSuccessMessage => 'تم إرسال رأيك بنجاح، شكراً لك!';

  @override
  String get studentFeedbackConnectionError => 'حدث خطأ في الاتصال';

  @override
  String get submitLabel => 'إرسال';

  @override
  String get teacherFeedbackFetchFailed => 'فشل جلب الآراء';

  @override
  String get teacherFeedbackDialogTitle => 'آراء الطلاب المجهولة';

  @override
  String get teacherFeedbackEmptyState => 'لا توجد آراء مسجلة حتى الآن';

  @override
  String get subjectContentsLabel => 'محتوى المادة';

  @override
  String get chaptersTabLabel => 'الفصول';

  @override
  String examsTabLabel(int count) {
    return 'الامتحانات ($count)';
  }

  @override
  String get noExamsAvailable => 'لا توجد امتحانات متاحة بعد';

  @override
  String get examStatusUnsolved => 'غير محلول';

  @override
  String get examStatusPending => 'قيد المراجعة';

  @override
  String get examStatusPractice => 'تدريب';

  @override
  String get examStatusCompleted => 'مكتمل';

  @override
  String get examStatusExpired => 'منتهي';

  @override
  String get untitledExamFallback => 'امتحان بدون عنوان';

  @override
  String examDurationMinutes(String minutes) {
    return '$minutes دقيقة';
  }

  @override
  String get editExamTooltip => 'تعديل الامتحان';

  @override
  String get statisticsTooltip => 'الإحصائيات';

  @override
  String get examFallbackTitle => 'امتحان';

  @override
  String get examPendingReviewTitle => 'قيد المراجعة';

  @override
  String get examPendingReviewMessage => 'الامتحان قيد المراجعة من المعلم';

  @override
  String get examResultFallbackTitle => 'نتيجة الامتحان';

  @override
  String get examResultLoadError => 'خطأ: تعذر تحميل النتيجة.';

  @override
  String get examOptionsDialogTitle => 'خيارات الامتحان';

  @override
  String get examRetakeOptionsMessage =>
      'لقد أكملت هذا الامتحان من قبل. هل تود عرض نتيجتك السابقة أم إعادة الامتحان للتدريب؟';

  @override
  String get viewResultButton => 'عرض النتيجة';

  @override
  String get retakeForPracticeButton => 'إعادة للتدريب';

  @override
  String get confirmStartExamTitle => 'تأكيد بدء الامتحان';

  @override
  String get confirmStartExamMessage =>
      'هل أنت مستعد؟ سيتم بدء الامتحان واحتساب الوقت بمجرد تأكيدك.';

  @override
  String get startExamButton => 'بدء الامتحان';

  @override
  String get noChaptersFound => 'لا توجد فصول';

  @override
  String get unknownCourseFallback => 'كورس غير معروف';

  @override
  String get chapterFallbackTitle => 'فصل';

  @override
  String contentsCountLabel(int count) {
    return '$count محتوى';
  }

  @override
  String get loginNowButton => 'تسجيل الدخول الآن';

  @override
  String get myLessonsSubtitle => 'دروسي';

  @override
  String get noActiveCourses => 'لا توجد كورسات نشطة';

  @override
  String get marketTitle => 'المتجر';

  @override
  String get searchCourseMarketHint => 'ابحث عن التميز...';

  @override
  String get appInformation => 'معلومات التطبيق';

  @override
  String get craftedWithPassion => 'صُنع بشغف لكل المتعلمين في كل مكان.';

  @override
  String get legalAndDocs => 'قانوني ووثائق';

  @override
  String get contactSupport => 'تواصل مع الدعم';

  @override
  String get supportContactNotAvailable => 'تواصل الدعم غير متاح حالياً';

  @override
  String get developedBy => 'تطوير';

  @override
  String get downloadedSubjectsLabel => 'المواد المحملة';

  @override
  String get downloadedChaptersLabel => 'الفصول المحملة';

  @override
  String get downloadsTitle => 'التحميلات';

  @override
  String get localCoursesLabel => 'كورسات محلية';

  @override
  String get noStoredFiles => 'لا توجد ملفات مخزنة';

  @override
  String get activeDownloadsLabel => 'التحميلات النشطة';

  @override
  String get downloadingItemPlaceholder => 'جارٍ تحميل العنصر...';

  @override
  String get errorPreparingVideoPlayback => 'خطأ في تجهيز تشغيل الفيديو';

  @override
  String get errorOpeningPdf => 'خطأ في فتح ملف PDF';

  @override
  String get fileRemoved => 'تم حذف الملف';

  @override
  String get failedToDeleteFile => 'فشل حذف الملف';

  @override
  String get offlineVideoFallbackTitle => 'فيديو غير متصل';

  @override
  String get documentFallbackTitle => 'مستند';

  @override
  String get noVideosDownloaded => 'لا توجد فيديوهات محملة';

  @override
  String get noPdfsDownloaded => 'لا توجد ملفات PDF محملة';

  @override
  String filesCountLabel(int count) {
    return '$count ملف';
  }

  @override
  String activeCountLabel(int count) {
    return '$count نشط';
  }

  @override
  String get keepAppOpenDuringDownloadWarning =>
      'لا تغلق التطبيق أو تضعه في الخلفية أثناء التحميل حتى لا يتوقف';

  @override
  String filesDownloadedCountLabel(int count) {
    return '$count ملف تم تحميله';
  }

  @override
  String videosTabWithCount(int count) {
    return 'فيديوهات ($count)';
  }

  @override
  String pdfsTabWithCount(int count) {
    return 'ملفات PDF ($count)';
  }

  @override
  String sizeInMb(String size) {
    return '$size ميجابايت';
  }

  @override
  String downloadPercentLabel(int percent) {
    return '$percent٪';
  }

  @override
  String get unknownSubjectFallback => 'مادة غير معروفة';

  @override
  String get unknownChapterFallback => 'فصل غير معروف';

  @override
  String get pleaseFillAllFields => 'يرجى تعبئة جميع الحقول';

  @override
  String get passwordUpdatedSuccessfully => 'تم تحديث كلمة المرور بنجاح';

  @override
  String get failedToUpdatePassword => 'فشل تحديث كلمة المرور';

  @override
  String get connectionErrorTryAgain =>
      'خطأ في الاتصال. يرجى المحاولة مرة أخرى.';

  @override
  String get changePasswordTitle => 'تغيير كلمة المرور';

  @override
  String get currentPasswordLabel => 'كلمة المرور الحالية';

  @override
  String get newPasswordLabel => 'كلمة المرور الجديدة';

  @override
  String get confirmNewPasswordLabel => 'تأكيد كلمة المرور الجديدة';

  @override
  String get createNewPasswordHint => 'أنشئ كلمة مرور جديدة';

  @override
  String get confirmNewPasswordHint => 'أكّد كلمة المرور الجديدة';

  @override
  String get updatePasswordButton => 'تحديث كلمة المرور';

  @override
  String get pleaseLoginToViewNotifications =>
      'الرجاء تسجيل الدخول لعرض الإشعارات.';

  @override
  String get failedToLoadNotifications => 'فشل في تحميل الإشعارات.';

  @override
  String get connectionErrorTryAgainLater =>
      'خطأ في الاتصال. يرجى المحاولة لاحقاً.';

  @override
  String get notificationsTitle => 'الإشعارات';

  @override
  String get noNotificationsYet => 'لا توجد إشعارات حتى الآن';

  @override
  String get newNotificationFallback => 'إشعار جديد';

  @override
  String todayAtLabel(String time) {
    return 'اليوم، $time';
  }

  @override
  String yesterdayAtLabel(String time) {
    return 'أمس، $time';
  }

  @override
  String get selectPlayerTitle => 'اختر المشغل';

  @override
  String get noActivePlayersAvailable => 'لا يوجد مشغلات متاحة حالياً.';

  @override
  String get selectDownloadQualityTitle => 'اختر جودة التحميل';

  @override
  String get downloadStartedMessage => 'بدأ التحميل...';

  @override
  String get downloadCompletedMessage => 'اكتمل التحميل!';

  @override
  String get downloadFailedMessage => 'فشل التحميل';

  @override
  String get resumeDownloadAction => 'استئناف';

  @override
  String get pdfDownloadStartedMessage => 'بدأ تحميل الملف...';

  @override
  String get pdfDownloadCompletedMessage => 'اكتمل تحميل الملف!';

  @override
  String get videosTabLabel => 'الفيديوهات';

  @override
  String get pdfsTabLabel => 'الملفات';

  @override
  String get noVideoLessonsMessage => 'لا توجد دروس فيديو';

  @override
  String get noPdfFilesMessage => 'لا توجد ملفات PDF';

  @override
  String get videoLabel => 'فيديو';

  @override
  String get studyMaterialLabel => 'مادة دراسية';

  @override
  String get videoProcessingNotice =>
      'سيتاح التشغيل والتحميل بعد اكتمال معالجة الفيديو';

  @override
  String get watchNowButton => 'شاهد الآن';

  @override
  String get openFileButton => 'فتح الملف';

  @override
  String get downloadButton => 'تحميل';

  @override
  String get savedLabel => 'تم الحفظ';

  @override
  String get processingLabel => 'جاري المعالجة...';

  @override
  String get downloadDisabledLabel => 'التحميل غير متاح';

  @override
  String get videoStatusRefreshFailed => 'تعذر تحديث حالة الفيديو';

  @override
  String get encodingStatusEncoding => 'قيد المعالجة';

  @override
  String get encodingStatusReady => 'جاهز';

  @override
  String get encodingStatusWaiting => 'في انتظار المعالجة';

  @override
  String get updatingLabel => 'جاري التحديث';

  @override
  String get couldNotLaunchLink => 'تعذر فتح الرابط';

  @override
  String get copiedToClipboard => 'تم النسخ';

  @override
  String get pleaseUploadReceiptImage => 'يرجى رفع صورة إيصال الدفع';

  @override
  String get requestSentTitle => 'تم إرسال الطلب';

  @override
  String get requestReceivedMessage =>
      'لقد استلمنا طلبك.\nسيتم إعلامك فور الموافقة عليه.';

  @override
  String get failedToSendRequest => 'فشل إرسال الطلب';

  @override
  String get checkoutTitle => 'إتمام الدفع';

  @override
  String get totalAmountLabel => 'المبلغ الإجمالي';

  @override
  String get discountCodeAppliedSuccess => 'تم تطبيق كود الخصم بنجاح!';

  @override
  String get discountCodeInvalid => 'كود الخصم غير صحيح أو تم استخدامه مسبقاً.';

  @override
  String get discountCodeLabel => 'كود الخصم';

  @override
  String get enterCodeHint => 'أدخل الكود هنا';

  @override
  String get applyButton => 'تطبيق';

  @override
  String get cashWalletsLabel => 'محافظ نقدية';

  @override
  String get walletNumberLabel => 'رقم المحفظة';

  @override
  String get instapayNumbersLabel => 'أرقام إنستاباي';

  @override
  String get instapayPhoneLabel => 'رقم إنستاباي';

  @override
  String get instapayLinksLabel => 'روابط / اسم مستخدم إنستاباي';

  @override
  String get paymentMethodsUnavailable => 'طرق الدفع غير متاحة';

  @override
  String get contactSupportOrRetryLater =>
      'يرجى التواصل مع الدعم أو المحاولة لاحقاً.';

  @override
  String get uploadReceiptLabel => 'رفع إيصال الدفع';

  @override
  String get tapToUploadScreenshot => 'اضغط لرفع صورة الإيصال';

  @override
  String get notesOptionalLabel => 'ملاحظات (اختياري)';

  @override
  String get addNotesHint => 'أضف أي ملاحظات...';

  @override
  String get confirmPaymentButton => 'تأكيد الدفع';

  @override
  String get copyTooltip => 'نسخ';

  @override
  String get openLinkInstapayButton => 'فتح الرابط / إنستاباي';

  @override
  String get couldNotFetchLatestData =>
      'تعذر جلب أحدث البيانات، يتم عرض النسخة المخزنة.';

  @override
  String get profileUpdatedSuccess => 'تم تحديث الملف الشخصي بنجاح';

  @override
  String get failedToUpdateProfile => 'فشل تحديث الملف الشخصي';

  @override
  String get editProfileTitle => 'تعديل الملف الشخصي';

  @override
  String get tapToChangePhoto => 'اضغط لتغيير الصورة';

  @override
  String get editFullNameHint => 'أدخل اسمك الكامل';

  @override
  String get nameRequiredValidation => 'الاسم مطلوب';

  @override
  String get phoneNumberLabel => 'رقم الهاتف';

  @override
  String get invalidPhoneNumberValidation => 'رقم هاتف غير صالح';

  @override
  String get usernameLabel => 'اسم المستخدم';

  @override
  String get usernameEnglishNumbersOnlyHint => 'حروف إنجليزية وأرقام فقط';

  @override
  String get usernameRequiredValidation => 'اسم المستخدم مطلوب';

  @override
  String get usernameInvalidCharsValidation =>
      'يُسمح فقط بحروف إنجليزية وأرقام (بدون مسافات)';

  @override
  String get teacherInfoLabel => 'بيانات المعلم';

  @override
  String get specialtyJobTitleLabel => 'التخصص / المسمى الوظيفي';

  @override
  String get specialtyHint => 'مثال: مدرس فيزياء';

  @override
  String get whatsappNumberLabel => 'رقم الواتساب (للطلاب)';

  @override
  String get whatsappNumberHint => '201xxxxxxxxx';

  @override
  String get whatsappNumberNotice =>
      'أدخل الرقم مع كود الدولة بدون \'+\' (مثال: 201xxxxxxxxx)';

  @override
  String get bioAboutMeLabel => 'نبذة / عن نفسك';

  @override
  String get bioHint => 'أخبر الطلاب عن نفسك...';

  @override
  String get paymentMethodsLabel => 'طرق الدفع';

  @override
  String get cashWalletNumbersTitle => 'أرقام المحافظ النقدية';

  @override
  String get enterWalletNumberHint => 'أدخل رقم المحفظة';

  @override
  String get instapayNumbersTitle => 'أرقام إنستاباي';

  @override
  String get enterInstapayPhoneHint => 'أدخل رقم هاتف إنستاباي';

  @override
  String get instapayLinksUsernamesTitle => 'روابط / أسماء مستخدمين إنستاباي';

  @override
  String get instapayLinkHint => 'username@instapay أو رابط';

  @override
  String get saveChangesButton => 'حفظ التغييرات';

  @override
  String get clickPlusToAddHint => 'اضغط + لإضافة رقم/رابط';

  @override
  String get failedToStartExam => 'فشل بدء الامتحان';

  @override
  String get accessDeniedFallback => 'تم رفض الوصول';

  @override
  String get examAlreadyCompleted => 'تم إكمال الامتحان بالفعل';

  @override
  String cannotSubmitUnanswered(int count) {
    return 'لا يمكن التسليم بعد. لديك $count أسئلة غير مُجابة!';
  }

  @override
  String get failedToSubmitTryAgain => 'فشل التسليم. حاول مرة أخرى.';

  @override
  String get exitExamTitle => 'الخروج من الامتحان؟';

  @override
  String get exitExamWarningMessage =>
      'الخروج من شاشة الامتحان الآن سيؤدي إلى تسليم إجاباتك الحالية تلقائياً ولن تتمكن من العودة.\n\nهل أنت متأكد؟';

  @override
  String get stayButton => 'البقاء';

  @override
  String get submitAndExitButton => 'تسليم وخروج';

  @override
  String get noModelAnswerProvided => 'لا توجد إجابة نموذجية متاحة.';

  @override
  String get writtenQuestionInstructions => 'سؤال مقالي — اكتب إجابتك أدناه';

  @override
  String get writeAnswerHint => 'اكتب إجابتك هنا...';

  @override
  String charactersCountLabel(int count) {
    return '$count حرف';
  }

  @override
  String get markQuestionTooltip => 'تحديد السؤال';

  @override
  String questionCounterLabel(int current, int total) {
    return 'س $current/$total';
  }

  @override
  String get modelAnswerLabel => 'الإجابة النموذجية';

  @override
  String get writtenQuestionBadge => 'سؤال مقالي';

  @override
  String get questionTextFallback => 'نص السؤال';

  @override
  String get backButton => 'السابق';

  @override
  String get examCloseButton => 'إغلاق';

  @override
  String get examFinishButton => 'إنهاء';

  @override
  String get examNextButton => 'التالي';

  @override
  String get noAnswerSubmittedFallback => '(لم يتم إرسال إجابة)';

  @override
  String get writtenBadgeShort => 'مقالي';

  @override
  String questionNumberLabel(int number) {
    return 'السؤال $number';
  }

  @override
  String pointsScoredLabel(int earned, int max) {
    return '$earned / $max نقطة';
  }

  @override
  String pointsPendingLabel(int max) {
    return '— / $max نقطة';
  }

  @override
  String get yourAnswerLabel => 'إجابتك';

  @override
  String get teacherFeedbackLabel => 'ملاحظات المعلم';

  @override
  String get failedToLoadResults => 'فشل تحميل النتائج';

  @override
  String get awaitingTeacherReview => 'بانتظار مراجعة المعلم';

  @override
  String get examUnderReviewMessage =>
      'تم إرسال امتحانك وهو الآن قيد المراجعة من قِبل معلمك. سيتم إعلامك فور اكتمال التصحيح.';

  @override
  String get backToCourseButton => 'العودة إلى الكورس';

  @override
  String get examPassedLabel => 'ناجح';

  @override
  String get examFailedLabel => 'راسب';

  @override
  String get practiceResultTitle => 'نتيجة التدريب';

  @override
  String get examResultsTitle => 'نتائج الامتحان';

  @override
  String get practiceModeNotice =>
      'هذه نتيجة تدريبية (Practice Mode). لم يتم حفظ هذه النتيجة في سجل درجاتك الدائم.';

  @override
  String get detailedAnalysisLabel => 'تحليل مفصل';

  @override
  String get writtenQuestionsPendingGrading =>
      'الأسئلة المقالية بانتظار التصحيح';

  @override
  String get couldNotOpenWhatsapp => 'تعذر فتح واتساب';

  @override
  String get errorLoadingProfile => 'حدث خطأ أثناء تحميل الملف الشخصي';

  @override
  String get chatOnWhatsapp => 'تواصل عبر واتساب';

  @override
  String get noBioAvailable => 'لا توجد نبذة تعريفية.';

  @override
  String get availableCoursesLabel => 'الكورسات المتاحة';

  @override
  String get untitledFallback => 'بدون عنوان';

  @override
  String get closePlayer => 'إغلاق المشغل';

  @override
  String get deleteAccountTitle => 'حذف الحساب';

  @override
  String get deleteAccountConfirmMessage =>
      'هل أنت متأكد من رغبتك في حذف حسابك؟ لا يمكن التراجع عن هذا الإجراء وستفقد جميع اشتراكاتك.';

  @override
  String get accountDeletedSuccessfully => 'تم حذف الحساب بنجاح.';

  @override
  String errorDeletingAccount(String error) {
    return 'حدث خطأ أثناء حذف الحساب: $error';
  }

  @override
  String get settingsTitle => 'الإعدادات';

  @override
  String qualityLabel(String quality) {
    return 'الجودة: $quality';
  }

  @override
  String speedLabel(String speed) {
    return 'السرعة: ${speed}x';
  }

  @override
  String startingInCountdown(String seconds) {
    return 'البدء خلال $seconds';
  }

  @override
  String get videoReadyStabilizing => 'الفيديو جاهز - جاري استقرار البث...';

  @override
  String get securityAlertTitle => 'تنبيه أمني';

  @override
  String get screenRecordingDetectedMessage =>
      'تم رصد تسجيل للشاشة.\nتم تعطيل التشغيل.';

  @override
  String get finalWarningTitle => '⚠️ تحذير نهائي';

  @override
  String get contentRecordingViolationMessage =>
      'تسجيل المحتوى مخالف لشروط الاستخدام.\nتكرار هذا الأمر سيؤدي إلى حظر حسابك نهائياً وحذف جميع بياناتك.';

  @override
  String get pdfToolPen => 'قلم';

  @override
  String get pdfToolHighlightText => 'تمييز نص';

  @override
  String get pdfToolFreehandHighlight => 'تمييز حر';

  @override
  String get pdfToolEraser => 'ممحاة';

  @override
  String get pdfToolComment => 'ملاحظة';

  @override
  String get pdfToolUnderline => 'تسطير';

  @override
  String get pdfToolText => 'نص';

  @override
  String get pdfToolShapes => 'أشكال';

  @override
  String get pdfToolImage => 'صورة';

  @override
  String get undoTooltip => 'تراجع';

  @override
  String get palmRejectionOn => 'رفض راحة اليد: مفعّل';

  @override
  String get palmRejectionOff => 'رفض راحة اليد: معطّل';

  @override
  String get boldLabel => 'عريض';

  @override
  String get underlineLabel => 'تسطير';

  @override
  String get borderLabel => 'الحدود: ';

  @override
  String get fillLabel => 'التعبئة: ';

  @override
  String get chooseColorTitle => 'اختر لوناً';

  @override
  String get saturationLabel => 'التشبع';

  @override
  String get brightnessLabel => 'السطوع';

  @override
  String get selectAction => 'اختيار';

  @override
  String get protectionFeaturesWarning =>
      'تحذير: قد لا تعمل بعض مميزات الحماية';

  @override
  String get securityWarningTitle => '⚠️ تحذير أمني';

  @override
  String get audioRecordingDetectedMessage => 'تم اكتشاف محاولة تسجيل صوت!';

  @override
  String get recordingConsequencesMessage =>
      '• تم إيقاف التشغيل تلقائياً\n• التسجيل مخالف لحقوق الملكية الفكرية\n• قد يتم إيقاف حسابك';

  @override
  String get exitAction => 'خروج';

  @override
  String get protectedBadge => 'محمي';

  @override
  String get recordingDetectedTitle => 'تم اكتشاف تسجيل!';

  @override
  String get playbackStoppedMessage => 'تم إيقاف التشغيل';

  @override
  String get verifyingFileMessage => 'جار التحقق من الملف...';

  @override
  String get initializingProtectionMessage => 'جار تهيئة الحماية...';

  @override
  String get directDownloadMessage => 'جار التحميل المباشر...';

  @override
  String get failedOpenProtectedFile => 'فشل فتح الملف المحمي.';

  @override
  String get pageIndexTitle => 'فهرس الصفحات';

  @override
  String pageNumberLabel(String number) {
    return 'صفحة $number';
  }

  @override
  String get highlightLabel => 'تمييز';

  @override
  String get underlineActionLabel => 'تسطير';

  @override
  String get editAction => 'تعديل';

  @override
  String get noMarkupInSelectionMessage =>
      'لا يوجد تمييز أو تسطير في هذا التحديد';

  @override
  String get editHighlightTitle => 'تعديل التمييز';

  @override
  String get editUnderlineTitle => 'تعديل التسطير';

  @override
  String get deleteHighlightLabel => 'حذف التمييز';

  @override
  String get deleteUnderlineLabel => 'حذف التسطير';

  @override
  String get editShapeTitle => 'تعديل الشكل';

  @override
  String get deleteShapeLabel => 'حذف الشكل';

  @override
  String get addCommentTitle => 'إضافة تعليق';

  @override
  String get commentTitle => 'التعليق';

  @override
  String get writeNotesHint => 'اكتب ملاحظاتك هنا...';

  @override
  String get noTextHint => 'لا يوجد نص...';

  @override
  String iconSizeLabel(String size) {
    return 'حجم الأيقونة: $size';
  }

  @override
  String opacityLabel(String percent) {
    return 'الشفافية: $percent%';
  }

  @override
  String get defaultSettingsSaved => 'تم حفظ الإعدادات الافتراضية';

  @override
  String get saveAsDefaultLabel => 'حفظ كافتراضي';

  @override
  String get textPreviewPlaceholder => 'معاينة النص...';

  @override
  String get writeTextHint => 'اكتب النص هنا...';

  @override
  String failedFetchStats(String error) {
    return 'فشل جلب الإحصائيات: $error';
  }

  @override
  String statisticsForTitle(String examTitle) {
    return 'إحصائيات: $examTitle';
  }

  @override
  String get numberOfAttemptsLabel => 'عدد المحاولات';

  @override
  String get averagePercentageLabel => 'متوسط النسب';

  @override
  String get honorRollTitle => 'لوحة الشرف (Top 10)';

  @override
  String get noCompletedAttemptsYet => 'لا توجد محاولات مكتملة حتى الآن';

  @override
  String get unknownStudentFallback => 'طالب غير معروف';

  @override
  String get notAvailable => 'غير متوفر';

  @override
  String pointsSuffix(String score) {
    return '$score نقطة';
  }

  @override
  String get networkConnectionProblemMessage =>
      'حدثت مشكلة في الاتصال بالشبكة.\nيرجى التأكد من استقرار الإنترنت وإعادة المحاولة.';

  @override
  String playerInitFailedMessage(String error) {
    return 'فشل في تهيئة المشغل: $error';
  }

  @override
  String get videoLoadFailedMessage => 'فشل في تحميل الفيديو.';

  @override
  String get noSourcesAvailableMessage => 'لا يوجد مصادر متاحة لهذا الفيديو.';

  @override
  String get darkModeLabel => 'الوضع الليلي';

  @override
  String get lightModeLabel => 'الوضع النهاري';

  @override
  String failedLoadExamDetails(String error) {
    return 'فشل تحميل بيانات الامتحان: $error';
  }

  @override
  String get startDateAfterEndError =>
      'تاريخ البدء لا يمكن أن يكون بعد تاريخ الانتهاء!';

  @override
  String get endDateBeforeStartError =>
      'تاريخ الانتهاء لا يمكن أن يكون قبل تاريخ البدء!';

  @override
  String get deleteExamTitle => 'حذف الامتحان';

  @override
  String get deleteExamConfirmMessage =>
      'هل أنت متأكد من حذف هذا الامتحان؟\n\n⚠️ تحذير: سيتم حذف جميع الأسئلة وجميع نتائج الطلاب المرتبطة بهذا الامتحان بشكل نهائي.';

  @override
  String get permanentDeleteAction => 'حذف نهائي';

  @override
  String get examDeletedSuccessfully => 'تم حذف الامتحان بنجاح';

  @override
  String deleteFailedMessage(String error) {
    return 'فشل الحذف: $error';
  }

  @override
  String get atLeastOneQuestionRequired => 'يجب إضافة سؤال واحد على الأقل';

  @override
  String get selectExamStartEndTime => 'يرجى تحديد وقت بداية ونهاية الامتحان';

  @override
  String get startTimeAfterEndError => 'خطأ: وقت البداية بعد وقت النهاية!';

  @override
  String get examUpdatedSuccessfully => 'تم تحديث الامتحان بنجاح';

  @override
  String get examCreatedSuccessfully => 'تم إنشاء الامتحان بنجاح';

  @override
  String genericErrorOccurred(String error) {
    return 'حدث خطأ: $error';
  }

  @override
  String get editExamTitle => 'تعديل الامتحان';

  @override
  String get createNewExamTitle => 'إنشاء امتحان جديد';

  @override
  String get processingMessage => 'جاري التنفيذ...';

  @override
  String get examTitleLabel => 'عنوان الامتحان';

  @override
  String get examTitleHint => 'مثال: امتحان شامل الفصل الأول';

  @override
  String get requiredField => 'مطلوب';

  @override
  String get durationMinutesLabel => 'المدة (دقائق)';

  @override
  String get durationHint => 'أدخل مدة الامتحان';

  @override
  String get randomizeQuestionsTitle => 'ترتيب أسئلة عشوائي';

  @override
  String get randomizeQuestionsSubtitle => 'يظهر لكل طالب ترتيب أسئلة مختلف';

  @override
  String get randomizeOptionsTitle => 'ترتيب اختيارات عشوائي';

  @override
  String get randomizeOptionsSubtitle => 'تغيير أماكن الإجابات داخل كل سؤال';

  @override
  String get allowRetakeTitle => 'السماح بإعادة الامتحان (تدريب)';

  @override
  String get allowRetakeSubtitle =>
      'يمكن للطالب إعادة الامتحان دون التأثير على درجته الأولى';

  @override
  String get notifyStudentsTitle => 'إرسال إشعار للطلاب';

  @override
  String get notifyStudentsSubtitle =>
      'إرسال إشعار للطلاب المشتركين عند بدء الامتحان';

  @override
  String get activationDateTimeLabel => 'تاريخ ووقت التفعيل (البداية)';

  @override
  String startsAtLabel(String date) {
    return 'يبدأ: $date';
  }

  @override
  String get tapToSetStart => 'اضغط لتحديد البداية';

  @override
  String get closingDateTimeLabel => 'تاريخ ووقت الإغلاق (النهاية)';

  @override
  String endsAtLabel(String date) {
    return 'ينتهي: $date';
  }

  @override
  String get tapToSetEnd => 'اضغط لتحديد النهاية';

  @override
  String questionsCountLabel(String count) {
    return 'الأسئلة ($count)';
  }

  @override
  String get addQuestionAction => 'إضافة سؤال';

  @override
  String get noQuestionsAddedYet => 'لم تتم إضافة أسئلة بعد';

  @override
  String get essayBadge => 'مقالي';

  @override
  String essayQuestionSubtitle(String score, String imageStatus) {
    return 'تصحيح يدوي • الدرجة العظمى $score • $imageStatus';
  }

  @override
  String mcqQuestionSubtitle(String count, String imageStatus) {
    return '$count اختيارات • $imageStatus';
  }

  @override
  String get newImageStatus => 'صورة جديدة';

  @override
  String get savedImageStatus => 'صورة محفوظة';

  @override
  String get textOnlyStatus => 'نص فقط';

  @override
  String get saveChangesAction => 'حفظ التعديلات';

  @override
  String get saveAndPublishExamAction => 'حفظ ونشر الامتحان';

  @override
  String get newQuestionTitle => 'سؤال جديد';

  @override
  String get editQuestionTitle => 'تعديل السؤال';

  @override
  String get questionTextLabel => 'نص السؤال';

  @override
  String get questionTypeLabel => 'نوع السؤال';

  @override
  String get mcqTypeOption => 'اختياري (متعدد الإجابات)';

  @override
  String get essayTypeOption => 'مقالي (تصحيح يدوي)';

  @override
  String get newImageSelectedStatus => 'تم اختيار صورة جديدة';

  @override
  String get imageSavedPreviouslyStatus => 'صورة محفوظة مسبقاً';

  @override
  String get noImageStatus => 'لا توجد صورة';

  @override
  String get uploadChangeImageTooltip => 'رفع/تغيير صورة';

  @override
  String get deleteImageTooltip => 'حذف الصورة';

  @override
  String get maxScoreForQuestionLabel => 'الدرجة العظمى لهذا السؤال:';

  @override
  String get scoreLabel => 'الدرجة';

  @override
  String get essayInfoMessage =>
      'سيكتب الطالب إجابته في مربع نصي، وستحتاج لتصحيحها يدوياً بعد التسليم.';

  @override
  String get modelAnswerOptionalLabel => 'الإجابة النموذجية (اختياري):';

  @override
  String get modelAnswerHint =>
      'اكتب الإجابة النموذجية هنا ليراها الطالب بعد ظهور النتيجة...';

  @override
  String get modelAnswerInfoMessage =>
      'ستظهر هذه الإجابة للطالب في شاشة النتيجة والمراجعة بعد التصحيح، كمرجع لمقارنة إجابته.';

  @override
  String get optionsSelectCorrectLabel => 'الخيارات (حدد الصحيحة):';

  @override
  String get addOptionAction => 'إضافة خيار';

  @override
  String optionNumberLabel(String number) {
    return 'الخيار $number';
  }

  @override
  String get deleteOptionTooltip => 'حذف الخيار';

  @override
  String get saveQuestionAction => 'حفظ السؤال';

  @override
  String get minTwoOptionsRequired =>
      'يجب أن يحتوي السؤال على خيارين على الأقل';

  @override
  String get maxScoreRequiredForEssay =>
      'يجب تحديد الدرجة العظمى للسؤال المقالي';

  @override
  String get fillAllOptionsOrDelete =>
      'يرجى ملء جميع حقول الخيارات أو حذف الفارغ منها';

  @override
  String errorFetchingFinancialStats(String error) {
    return 'خطأ: $error';
  }

  @override
  String get financialStatsTitle => 'الإحصائيات والأرباح';

  @override
  String get totalStudentsLabel => 'إجمالي الطلاب';

  @override
  String get totalEarningsLabel => 'إجمالي الأرباح';

  @override
  String earningsEgpAmount(String amount) {
    return '$amount ج.م';
  }

  @override
  String get coursesStatsSectionTitle => '📊 إحصائيات الكورسات';

  @override
  String get subjectsStatsSectionTitle => '📚 إحصائيات المواد (فردي)';

  @override
  String studentCountLabel(String count) {
    return '$count طالب';
  }

  @override
  String get searchMinCharsWarning => 'يرجى إدخال 3 أحرف على الأقل للبحث';

  @override
  String get promoteStudentDialogTitle => 'ترقية الطالب';

  @override
  String get removeSupervisorDialogTitle => 'حذف المشرف';

  @override
  String get promoteSuccessMessage => 'تمت الترقية ومنح الصلاحيات بنجاح';

  @override
  String get demoteSuccessMessage => 'تم حذف المشرف بنجاح';

  @override
  String errorOccurredWithDetails(String error) {
    return 'حدث خطأ: $error';
  }

  @override
  String get manageTeamTitle => 'إدارة فريق العمل';

  @override
  String get addNewSupervisorTitle => 'إضافة مشرف جديد';

  @override
  String get addSupervisorSubtitle =>
      'ابحث عن طالب لترقيته ومنحه صلاحيات كاملة تلقائياً';

  @override
  String get searchByNameOrUsernameHint => 'ابحث بالاسم أو اسم المستخدم...';

  @override
  String get searchResultsLabel => 'نتائج البحث:';

  @override
  String get noNameFallback => 'بدون اسم';

  @override
  String promoteConfirmMessage(String name) {
    return 'سيتم ترقية الطالب \'$name\' ليصبح مشرفاً وسيتم منحه صلاحية الوصول لجميع كورساتك الحالية.\n\nهل أنت متأكد؟';
  }

  @override
  String get promoteAction => 'ترقية';

  @override
  String currentSupervisorsCountLabel(String count) {
    return 'المشرفون الحاليون ($count)';
  }

  @override
  String get noSupervisorsCurrently => 'لا يوجد مشرفين حالياً';

  @override
  String get unknownFallback => 'غير معروف';

  @override
  String get removeSupervisorTooltip => 'إلغاء الإشراف';

  @override
  String demoteConfirmMessage(String name) {
    return 'سيتم سحب صلاحيات الإشراف من \'$name\' وإعادته كطالب عادي.\n\nلن يتمكن من إدارة المحتوى بعد الآن.';
  }

  @override
  String get searchMinDigitsLettersWarning => 'أدخل 3 أرقام/حروف على الأقل';

  @override
  String studentNotFoundOrError(String error) {
    return 'لم يتم العثور على الطالب أو حدث خطأ: $error';
  }

  @override
  String get revokeAccessDialogTitle => 'سحب الصلاحية';

  @override
  String get revokeAccessConfirmMessage =>
      'هل أنت متأكد من حذف الصلاحية؟ سيتم منع الطالب من الوصول لهذا المحتوى.';

  @override
  String get confirmRevokeAction => 'تأكيد السحب';

  @override
  String get accessGrantedSuccessMessage => 'تمت إضافة الصلاحية بنجاح';

  @override
  String get accessRevokedSuccessMessage => 'تم سحب الصلاحية بنجاح';

  @override
  String operationFailedWithDetails(String error) {
    return 'فشلت العملية: $error';
  }

  @override
  String bulkGrantSuccessMessage(String count) {
    return 'تم منح $count صلاحيات بنجاح';
  }

  @override
  String bulkGrantErrorWithDetails(String error) {
    return 'حدث خطأ أثناء المنح: $error';
  }

  @override
  String get loadingCoursesRetryMessage =>
      'جارِ تحميل بيانات الكورسات... حاول مرة أخرى بعد قليل.';

  @override
  String get choosePermissionsToGrantTitle => 'اختر الصلاحيات لمنحها';

  @override
  String grantWithCountAction(String count) {
    return 'منح ($count)';
  }

  @override
  String get manageStudentsTitle => 'إدارة الطلاب (طلابي)';

  @override
  String get phoneOrUsernameHint => 'رقم الهاتف أو اسم المستخدم';

  @override
  String get searchAction => 'بحث';

  @override
  String get currentPermissionsLabel => 'الصلاحيات الحالية:';

  @override
  String get managePermissionsAction => 'إدارة الصلاحيات';

  @override
  String get noAccessCurrentlyMessage => 'هذا الطالب لا يملك أي صلاحيات حالياً';

  @override
  String get undefinedFallback => 'غير معرّف';

  @override
  String get fullCourseBadgeLabel => 'كورس كامل';

  @override
  String get individualSubjectBadgeLabel => 'مادة فردية';

  @override
  String get searchForStudentPrompt => 'قم بالبحث عن طالب لإدارة صلاحياته';

  @override
  String phoneEmojiLabel(String phone) {
    return '📞 $phone';
  }

  @override
  String usernameEmojiLabel(String username) {
    return '👤 $username';
  }

  @override
  String get rejectionReasonDialogTitle => 'سبب الرفض';

  @override
  String get rejectionReasonHint => 'اكتب سبب الرفض هنا...';

  @override
  String get confirmRejectionAction => 'تأكيد الرفض';

  @override
  String get processingActionMessage => 'جاري تنفيذ العملية...';

  @override
  String get studentApprovedSuccessMessage => 'تم قبول الطالب بنجاح';

  @override
  String get requestRejectedMessage => 'تم رفض الطلب';

  @override
  String get authDataNotReadyError => 'خطأ: بيانات المصادقة غير جاهزة';

  @override
  String get imageLoadFailedCheckConnection =>
      'تعذر تحميل الصورة - تأكد من الاتصال';

  @override
  String get subscriptionRequestsTitle => 'طلبات الاشتراك';

  @override
  String get tabPending => 'قيد الانتظار';

  @override
  String get tabApproved => 'مقبولة';

  @override
  String get tabRejected => 'مرفوضة';

  @override
  String get noRequestsInListMessage => 'لا توجد طلبات في هذه القائمة';

  @override
  String get unknownNameFallback => 'اسم غير معروف';

  @override
  String get requestedContentLabel => 'المحتوى المطلوب:';

  @override
  String get notSpecifiedFallback => 'غير محدد';

  @override
  String get studentNoteLabel => 'ملاحظة الطالب:';

  @override
  String get rejectionReasonLabel => 'سبب الرفض:';

  @override
  String get myRequestsTitle => 'طلباتي';

  @override
  String get trackYourOrdersLabel => 'تتبع طلباتك';

  @override
  String get noRequestsFound => 'لا توجد طلبات';

  @override
  String get requestStatusApproved => 'مقبول';

  @override
  String get requestStatusRejected => 'مرفوض';

  @override
  String get requestStatusPending => 'قيد الانتظار';

  @override
  String get unknownItemFallback => 'عنصر غير معروف';

  @override
  String get yourNoteLabel => 'ملاحظتك:';

  @override
  String get totalLabel => 'الإجمالي';

  @override
  String get egpCurrencyLabel => 'جنيه';

  @override
  String get rejectRequestAction => 'رفض الطلب';

  @override
  String get acceptAndActivateAction => 'قبول وتفعيل';

  @override
  String errorLoadingDataWithDetails(String error) {
    return 'حدث خطأ في التحميل: $error';
  }

  @override
  String failedToFetchDataWithDetails(String error) {
    return 'فشل جلب البيانات: $error';
  }

  @override
  String get videoDurationRequiredWarning =>
      '⚠️ يرجى إدخال مدة الفيديو الفعلية (لا يمكن تركها أصفاراً)';

  @override
  String get minutesSecondsMaxWarning =>
      '⚠️ الدقائق والثواني يجب ألا تتجاوز 59';

  @override
  String get pleaseSelectPdfFileWarning => 'يرجى اختيار ملف PDF';

  @override
  String get invalidVideoUrlError => 'رابط الفيديو غير صحيح';

  @override
  String get updatedSuccessfullyMessage => 'تم التحديث بنجاح';

  @override
  String get createdSuccessfullyMessage => 'تم الإنشاء بنجاح';

  @override
  String contentSaveErrorWithDetails(String error) {
    return 'خطأ: $error';
  }

  @override
  String get pleaseSelectVideoFileFirstWarning =>
      '⚠️ يرجى اختيار ملف فيديو أولاً';

  @override
  String get videoUploadedDurationPendingMessage =>
      '✅ تم رفع الفيديو بنجاح، وسيتم استخراج مدته تلقائياً بعد اكتمال المعالجة';

  @override
  String get videoUploadedSuccessMessage =>
      '✅ تم رفع الفيديو بنجاح وسيكون متاحاً بعد اكتمال المعالجة';

  @override
  String get confirmDeleteItemMessage =>
      'هل أنت متأكد من حذف هذا العنصر؟ لا يمكن التراجع عن هذا الإجراء.';

  @override
  String get deletedSuccessfullyMessage => 'تم الحذف بنجاح';

  @override
  String deleteFailedWithDetails(String error) {
    return 'فشل الحذف: $error';
  }

  @override
  String get preparingUploadSessionStatus => 'جاري تجهيز جلسة الرفع...';

  @override
  String uploadingVideoProgressStatus(String percent) {
    return 'جاري رفع الفيديو... $percent%';
  }

  @override
  String get connectionLostWaitingStatus =>
      '⏸️ انقطع الاتصال بالإنترنت — في انتظار عودة الاتصال للمتابعة تلقائياً';

  @override
  String get savingVideoDataStatus => 'جاري حفظ بيانات الفيديو...';

  @override
  String get editCourseTitle => 'تعديل الكورس';

  @override
  String get newCourseTitle => 'كورس جديد';

  @override
  String get editSubjectTitle => 'تعديل المادة';

  @override
  String get newSubjectTitle => 'مادة جديدة';

  @override
  String get editChapterTitle => 'تعديل الفصل';

  @override
  String get newChapterTitle => 'فصل جديد';

  @override
  String get editVideoTitle => 'تعديل الفيديو';

  @override
  String get newVideoTitle => 'فيديو جديد';

  @override
  String get editPdfTitle => 'تعديل PDF';

  @override
  String get newPdfTitle => 'PDF جديد';

  @override
  String get cancelUploadAction => 'إلغاء الرفع';

  @override
  String get uploadingFileStatus => 'جاري رفع الملف...';

  @override
  String get savingDataStatus => 'جاري حفظ البيانات...';

  @override
  String get titleNameLabel => 'العنوان / الاسم';

  @override
  String get chapterFolderLabel => 'المجلد (اختياري)';

  @override
  String get chapterFolderHint => 'مثال: الترم الأول، الوحدة 2 (اتركه فارغاً لعدم استخدام مجلد)';

  @override
  String get enterTitleHereHint => 'أدخل العنوان هنا';

  @override
  String get descriptionFieldLabel => 'الوصف';

  @override
  String get enterDescriptionHint => 'أدخل الوصف';

  @override
  String get priceEgpFieldLabel => 'السعر (جنيه)';

  @override
  String get zeroPointZeroHint => '0.0';

  @override
  String get youtubeLinkTabLabel => 'رابط يوتيوب';

  @override
  String get uploadVideoFileTabLabel => 'رفع ملف فيديو';

  @override
  String get newFileReplaceWarning =>
      'اختيار ملف جديد هنا سيستبدل الفيديو الحالي بالكامل بعد اكتمال الرفع.';

  @override
  String get youtubeVideoLinkLabel => 'رابط فيديو يوتيوب';

  @override
  String get actualVideoDurationLabel => 'مدة الفيديو الفعلية ⏱️';

  @override
  String get hoursLabel => 'ساعات';

  @override
  String get minutesLabel => 'دقائق';

  @override
  String get secondsLabel => 'ثواني';

  @override
  String get pasteYoutubeLinkHint =>
      'الصق رابط يوتيوب كاملاً وحدد مدته لتظهر للطلاب';

  @override
  String get noFileSelectedVideo => 'لم يتم اختيار ملف';

  @override
  String get tapToSelectVideoFile => 'اضغط لاختيار ملف فيديو من الجهاز';

  @override
  String get extractingVideoDurationStatus => 'جاري استخراج مدة الفيديو...';

  @override
  String get resumableUploadFoundMessage =>
      'تم العثور على رفع سابق متوقف لهذا الملف — سيتم استكمال الرفع من حيث توقف';

  @override
  String get resumeUploadAction => 'استئناف الرفع';

  @override
  String get uploadPauseResumeInfoMessage =>
      'يمكن إيقاف رفع الفيديو والمتابعة لاحقاً، كما يستأنف الرفع تلقائياً عند انقطاع الاتصال بدلاً من البدء من جديد.';

  @override
  String get videoDurationAutoExtractedLabel =>
      'مدة الفيديو (تُستخرج تلقائياً، يمكن تعديلها) ⏱️';

  @override
  String get noPdfFileSelected => 'لم يتم اختيار ملف';

  @override
  String get tapToSelectPdfLabel => 'اضغط لاختيار PDF';

  @override
  String get sendNotificationToStudentsLabel => 'إرسال إشعار للطلاب';

  @override
  String get notifySubscribedStudentsSubtitle =>
      'تنبيه الطلاب المشتركين بإضافة هذا المحتوى';

  @override
  String get saveChangesUpperAction => 'حفظ التعديلات';

  @override
  String get resumeAndUploadVideoAction => 'استئناف ورفع الفيديو';

  @override
  String get uploadVideoAction => 'رفع الفيديو';

  @override
  String get createUpperAction => 'إنشاء';

  @override
  String get deletePermanentlyUpperAction => 'حذف نهائي';

  @override
  String get myProfileTitle => 'حسابي';

  @override
  String get teacherDashboardSubtitle => 'لوحة تحكم المعلم';

  @override
  String get manageYourAccountSubtitle => 'إدارة حسابك';

  @override
  String get guestUserName => 'زائر';

  @override
  String get notLoggedInLabel => 'غير مسجل الدخول';

  @override
  String get defaultUserNameLabel => 'مستخدم';

  @override
  String get teacherControlsSection => 'أدوات المعلم';

  @override
  String get incomingRequestsMenu => 'الطلبات الواردة';

  @override
  String get myStudentsMenu => 'طلابي';

  @override
  String get manageTeamMenu => 'إدارة الفريق';

  @override
  String get financialStatsMenu => 'الإحصائيات المالية';

  @override
  String get accountSettingsSection => 'إعدادات الحساب';

  @override
  String get editProfileMenu => 'تعديل الملف الشخصي';

  @override
  String get changePasswordMenu => 'تغيير كلمة المرور';

  @override
  String get myRequestsMenu => 'طلباتي';

  @override
  String get generalSection => 'عام';

  @override
  String get appInformationMenu => 'معلومات التطبيق';

  @override
  String get languageMenu => 'اللغة';

  @override
  String get dangerZoneSection => 'منطقة الخطر';

  @override
  String get deleteMyAccountMenu => 'حذف حسابي';

  @override
  String get loginRegisterButton => 'تسجيل الدخول / إنشاء حساب';

  @override
  String get logoutButton => 'تسجيل الخروج';

  @override
  String get selectLanguageTitle => 'اختر اللغة';

  @override
  String get englishLanguageOption => 'English';

  @override
  String get arabicLanguageOption => 'العربية';

  @override
  String get hqAudioLabel => 'صوت عالي الجودة';

  @override
  String get doubleSpeedLabel => 'سرعة×2';

  @override
  String get freeAccessLabel => 'وصول مجاني';

  @override
  String get videoScreenshotSaved => 'تم حفظ اللقطة';

  @override
  String get videoScreenshotFailed => 'فشل حفظ اللقطة';

  @override
  String get videoScreenshotsTitle => 'لقطات الفيديو';

  @override
  String get videoScreenshotsTooltip => 'عرض لقطات الفيديو';

  @override
  String get noVideoScreenshotsYet => 'لا توجد لقطات بعد';

  @override
  String get deleteScreenshotConfirmTitle => 'حذف اللقطة؟';

  @override
  String get deleteScreenshotConfirmBody => 'سيتم حذف هذه اللقطة نهائياً.';
}
