// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'Medaad';

  @override
  String get cancel => 'Cancel';

  @override
  String get save => 'Save';

  @override
  String get delete => 'Delete';

  @override
  String get confirm => 'Confirm';

  @override
  String get confirmDelete => 'Confirm Delete';

  @override
  String get ok => 'OK';

  @override
  String get yes => 'Yes';

  @override
  String get no => 'No';

  @override
  String get close => 'Close';

  @override
  String get retry => 'Retry';

  @override
  String get loading => 'Loading...';

  @override
  String get error => 'Error';

  @override
  String get success => 'Success';

  @override
  String get language => 'Language';

  @override
  String get languageEnglish => 'English';

  @override
  String get languageArabic => 'Arabic';

  @override
  String get languageChangeRestartNotice =>
      'The app will restart to apply the new language.';

  @override
  String get splashTagline => 'EMPOWERING YOUR GROWTH';

  @override
  String get splashLoadingSystem => 'LOADING SYSTEM';

  @override
  String get termsWelcomeTitle => 'Welcome';

  @override
  String get termsDialogBody =>
      'Please accept our Terms & Privacy Policy to continue.';

  @override
  String get termsAndConditions => 'Terms & Conditions';

  @override
  String get privacyPolicy => 'Privacy Policy';

  @override
  String get decline => 'DECLINE';

  @override
  String get accept => 'ACCEPT';

  @override
  String get appUpdateTitle => 'App Update';

  @override
  String get updateLater => 'Later';

  @override
  String get updateNow => 'Update Now';

  @override
  String get offlineModeEnteredMessage => 'No Internet. Entering Offline Mode.';

  @override
  String get offlineModeLimitedMessage => 'Offline Mode (Limited Access)';

  @override
  String get connectionError => 'Connection Error';

  @override
  String get signIn => 'SIGN IN';

  @override
  String get createAccount => 'CREATE ACCOUNT';

  @override
  String get passwordLabel => 'Password';

  @override
  String get alreadyHaveAccount => 'Already have an account? ';

  @override
  String get newStudentQuestion => 'New student? ';

  @override
  String get loginEmptyFieldsError =>
      'Please enter username/phone and password';

  @override
  String get loginFailedDefault => 'Login failed';

  @override
  String get loginTitle => 'LOGIN';

  @override
  String get loginSubtitle => 'PLEASE LOGIN TO CONTINUE.';

  @override
  String get usernameOrPhoneLabel => 'Username or Phone';

  @override
  String get usernameOrPhoneHint => 'Enter username or 01xxxxxxxxx';

  @override
  String get browseAsGuest => 'BROWSE AS GUEST';

  @override
  String get registerAllFieldsRequired => 'All fields are required';

  @override
  String get registerUsernameInvalid =>
      'Username must be English letters & numbers only';

  @override
  String get registerPhoneInvalid =>
      'Invalid phone number (11 digits starting with 01)';

  @override
  String get registerPasswordTooShort =>
      'Password must be at least 6 characters';

  @override
  String get registerPasswordMismatch => 'Passwords do not match';

  @override
  String get registerSuccessMessage =>
      'Account created successfully. Please login.';

  @override
  String get registerFailedDefault => 'Registration failed';

  @override
  String get registerSubtitle => 'FILL IN THE DETAILS TO JOIN US.';

  @override
  String get fullNameLabel => 'Full Name';

  @override
  String get fullNameHint => 'Your full name';

  @override
  String get phoneNumberOptionalLabel => 'Phone Number (Optional)';

  @override
  String get phoneNumberHint => '01xxxxxxxxx';

  @override
  String get usernameEnglishOnlyLabel => 'Username (English Only)';

  @override
  String get usernameHint => 'username';

  @override
  String get confirmPasswordLabel => 'Confirm Password';

  @override
  String get navHome => 'Home';

  @override
  String get navCourses => 'Courses';

  @override
  String get navDownloads => 'Downloads';

  @override
  String get navProfile => 'Profile';

  @override
  String get homeWelcomeGreeting => 'WELCOME';

  @override
  String get guestFallbackName => 'GUEST';

  @override
  String get encouragement1 =>
      'Knowledge is the key to unlocking your true potential.';

  @override
  String get encouragement2 =>
      'Every expert was once a beginner. Keep learning.';

  @override
  String get encouragement3 =>
      'Your future self will thank you for the effort you put in today.';

  @override
  String get encouragement4 =>
      'Invest in yourself; education pays the best interest.';

  @override
  String get encouragement5 =>
      'Learning never exhausts the mind. Stay curious!';

  @override
  String get suggestedForYou => 'SUGGESTED FOR YOU';

  @override
  String get searchResults => 'SEARCH RESULTS';

  @override
  String get activeLabel => 'ACTIVE';

  @override
  String get noCoursesFound => 'No courses found';

  @override
  String get searchCourseHint => 'Search course name or code...';

  @override
  String get libraryTitle => 'LIBRARY';

  @override
  String get guestModeLabel => 'GUEST MODE';

  @override
  String get loginRequiredTitle => 'LOGIN REQUIRED';

  @override
  String get loginRequiredMessage =>
      'Sign in to view and access your enrolled courses.';

  @override
  String get courseNotFound => 'Course not found';

  @override
  String get unknownInstructor => 'Unknown Instructor';

  @override
  String get instructorProfileUnavailable => 'Instructor profile not available';

  @override
  String get instructorLabel => 'INSTRUCTOR';

  @override
  String get noDescriptionAvailable => 'No description available.';

  @override
  String get teacherAccountLabel => 'TEACHER ACCOUNT';

  @override
  String get teachersCannotPurchaseMessage =>
      'Teachers cannot purchase courses.';

  @override
  String get courseContentLabel => 'COURSE CONTENT';

  @override
  String get purchaseOptionsLabel => 'PURCHASE OPTIONS';

  @override
  String get fullCourseLabel => 'FULL COURSE';

  @override
  String get fullCourseAccessLabel => 'FULL COURSE ACCESS';

  @override
  String get accessAllSubjectsExams => 'Access all subjects & exams';

  @override
  String get courseOwnedLabel => 'COURSE OWNED';

  @override
  String get individualSubjectsLabel => 'INDIVIDUAL SUBJECTS';

  @override
  String get ownedLabel => 'OWNED';

  @override
  String priceEgp(String price) {
    return '$price EGP';
  }

  @override
  String get totalPayableLabel => 'TOTAL PAYABLE';

  @override
  String get freeActivationLabel => 'Free Activation';

  @override
  String get activateButton => 'ACTIVATE';

  @override
  String get checkoutButton => 'CHECKOUT';

  @override
  String get selectItemsFirstError => 'Please select items first';

  @override
  String get activationSuccessMessage => 'Activation Successful! ✅';

  @override
  String get activationFailedMessage => 'Failed to activate. Try again.';

  @override
  String get instructorFallback => 'Instructor';

  @override
  String get chooseSubjectLabel => 'CHOOSE SUBJECT';

  @override
  String get noSubjectsFound => 'NO SUBJECTS FOUND';

  @override
  String get failedToLoadContent => 'Failed to load content.';

  @override
  String get studentFeedbackDialogTitle => 'We\'d love your feedback';

  @override
  String get studentFeedbackHint =>
      'Write your feedback or notes about this chapter (anonymous)';

  @override
  String get studentFeedbackSuccessMessage =>
      'Your feedback was submitted successfully, thank you!';

  @override
  String get studentFeedbackConnectionError => 'A connection error occurred';

  @override
  String get submitLabel => 'Submit';

  @override
  String get teacherFeedbackFetchFailed => 'Failed to load feedback';

  @override
  String get teacherFeedbackDialogTitle => 'Anonymous Student Feedback';

  @override
  String get teacherFeedbackEmptyState => 'No feedback submitted yet';

  @override
  String get subjectContentsLabel => 'SUBJECT CONTENTS';

  @override
  String get chaptersTabLabel => 'Chapters';

  @override
  String examsTabLabel(int count) {
    return 'Exams ($count)';
  }

  @override
  String get noExamsAvailable => 'No exams available yet';

  @override
  String get examStatusUnsolved => 'UNSOLVED';

  @override
  String get examStatusPending => 'PENDING';

  @override
  String get examStatusPractice => 'PRACTICE';

  @override
  String get examStatusCompleted => 'COMPLETED';

  @override
  String get examStatusExpired => 'EXPIRED';

  @override
  String get untitledExamFallback => 'Untitled Exam';

  @override
  String examDurationMinutes(String minutes) {
    return '$minutes MINS';
  }

  @override
  String get editExamTooltip => 'Edit Exam';

  @override
  String get statisticsTooltip => 'Statistics';

  @override
  String get examFallbackTitle => 'Exam';

  @override
  String get examPendingReviewTitle => 'Under Review';

  @override
  String get examPendingReviewMessage =>
      'This exam is pending review by the teacher';

  @override
  String get examResultFallbackTitle => 'Exam Result';

  @override
  String get examResultLoadError => 'Error: Cannot load result.';

  @override
  String get examOptionsDialogTitle => 'Exam Options';

  @override
  String get examRetakeOptionsMessage =>
      'You\'ve already completed this exam. Would you like to view your previous result or retake the exam for practice?';

  @override
  String get viewResultButton => 'View Result';

  @override
  String get retakeForPracticeButton => 'Retake for Practice';

  @override
  String get confirmStartExamTitle => 'Confirm Start Exam';

  @override
  String get confirmStartExamMessage =>
      'Are you ready? The exam and timer will begin once you confirm.';

  @override
  String get startExamButton => 'Start Exam';

  @override
  String get noChaptersFound => 'No chapters found';

  @override
  String get unknownCourseFallback => 'Unknown Course';

  @override
  String get chapterFallbackTitle => 'Chapter';

  @override
  String contentsCountLabel(int count) {
    return '$count CONTENTS';
  }

  @override
  String get loginNowButton => 'LOGIN NOW';

  @override
  String get myLessonsSubtitle => 'MY LESSONS';

  @override
  String get noActiveCourses => 'NO ACTIVE COURSES';

  @override
  String get marketTitle => 'MARKET';

  @override
  String get searchCourseMarketHint => 'Find excellence...';

  @override
  String get appInformation => 'App Information';

  @override
  String get craftedWithPassion =>
      'Crafted with passion for learners everywhere.';

  @override
  String get legalAndDocs => 'Legal & Docs';

  @override
  String get contactSupport => 'Contact Support';

  @override
  String get supportContactNotAvailable => 'Support contact not available';

  @override
  String get developedBy => 'Developed By';

  @override
  String get downloadedSubjectsLabel => 'DOWNLOADED SUBJECTS';

  @override
  String get downloadedChaptersLabel => 'DOWNLOADED CHAPTERS';

  @override
  String get downloadsTitle => 'DOWNLOADS';

  @override
  String get localCoursesLabel => 'LOCAL COURSES';

  @override
  String get noStoredFiles => 'NO STORED FILES';

  @override
  String get activeDownloadsLabel => 'ACTIVE DOWNLOADS';

  @override
  String get downloadingItemPlaceholder => 'Downloading Item...';

  @override
  String get errorPreparingVideoPlayback => 'Error preparing video playback';

  @override
  String get errorOpeningPdf => 'Error opening PDF';

  @override
  String get fileRemoved => 'File removed';

  @override
  String get failedToDeleteFile => 'Failed to delete file';

  @override
  String get offlineVideoFallbackTitle => 'Offline Video';

  @override
  String get documentFallbackTitle => 'Document';

  @override
  String get noVideosDownloaded => 'NO VIDEOS DOWNLOADED';

  @override
  String get noPdfsDownloaded => 'NO PDFS DOWNLOADED';

  @override
  String filesCountLabel(int count) {
    return '$count FILES';
  }

  @override
  String activeCountLabel(int count) {
    return '$count ACTIVE';
  }

  @override
  String filesDownloadedCountLabel(int count) {
    return '$count FILES DOWNLOADED';
  }

  @override
  String videosTabWithCount(int count) {
    return 'Videos ($count)';
  }

  @override
  String pdfsTabWithCount(int count) {
    return 'PDFs ($count)';
  }

  @override
  String sizeInMb(String size) {
    return '$size MB';
  }

  @override
  String downloadPercentLabel(int percent) {
    return '$percent%';
  }

  @override
  String get unknownSubjectFallback => 'Unknown Subject';

  @override
  String get unknownChapterFallback => 'Unknown Chapter';

  @override
  String get pleaseFillAllFields => 'Please fill all fields';

  @override
  String get passwordUpdatedSuccessfully => 'Password Updated Successfully';

  @override
  String get failedToUpdatePassword => 'Failed to update password';

  @override
  String get connectionErrorTryAgain => 'Connection error. Please try again.';

  @override
  String get changePasswordTitle => 'CHANGE PASSWORD';

  @override
  String get currentPasswordLabel => 'Current Password';

  @override
  String get newPasswordLabel => 'New Password';

  @override
  String get confirmNewPasswordLabel => 'Confirm New Password';

  @override
  String get createNewPasswordHint => 'Create new password';

  @override
  String get confirmNewPasswordHint => 'Confirm new password';

  @override
  String get updatePasswordButton => 'UPDATE PASSWORD';

  @override
  String get pleaseLoginToViewNotifications =>
      'Please login to view notifications.';

  @override
  String get failedToLoadNotifications => 'Failed to load notifications.';

  @override
  String get connectionErrorTryAgainLater =>
      'Connection error. Please try again later.';

  @override
  String get notificationsTitle => 'Notifications';

  @override
  String get noNotificationsYet => 'No notifications yet';

  @override
  String get newNotificationFallback => 'New Notification';

  @override
  String todayAtLabel(String time) {
    return 'Today, $time';
  }

  @override
  String yesterdayAtLabel(String time) {
    return 'Yesterday, $time';
  }

  @override
  String get selectPlayerTitle => 'SELECT PLAYER';

  @override
  String get noActivePlayersAvailable => 'No active players available.';

  @override
  String get selectDownloadQualityTitle => 'SELECT DOWNLOAD QUALITY';

  @override
  String get downloadStartedMessage => 'Download Started...';

  @override
  String get downloadCompletedMessage => 'Download Completed!';

  @override
  String get downloadFailedMessage => 'Download Failed';

  @override
  String get pdfDownloadStartedMessage => 'PDF Download Started...';

  @override
  String get pdfDownloadCompletedMessage => 'PDF Download Completed!';

  @override
  String get videosTabLabel => 'Videos';

  @override
  String get pdfsTabLabel => 'PDFs';

  @override
  String get noVideoLessonsMessage => 'No video lessons';

  @override
  String get noPdfFilesMessage => 'No PDF files';

  @override
  String get videoLabel => 'VIDEO';

  @override
  String get studyMaterialLabel => 'STUDY MATERIAL';

  @override
  String get videoProcessingNotice =>
      'Playback and download will be available once video processing is complete';

  @override
  String get watchNowButton => 'Watch Now';

  @override
  String get openFileButton => 'Open File';

  @override
  String get downloadButton => 'Download';

  @override
  String get savedLabel => 'SAVED';

  @override
  String get processingLabel => 'PROCESSING...';

  @override
  String get downloadDisabledLabel => 'DOWNLOAD DISABLED';

  @override
  String get videoStatusRefreshFailed => 'Failed to refresh video status';

  @override
  String get encodingStatusEncoding => 'Encoding';

  @override
  String get encodingStatusReady => 'Ready';

  @override
  String get encodingStatusWaiting => 'Waiting to process';

  @override
  String get updatingLabel => 'Updating';

  @override
  String get couldNotLaunchLink => 'Could not launch link';

  @override
  String get copiedToClipboard => 'Copied to clipboard';

  @override
  String get pleaseUploadReceiptImage =>
      'Please upload the payment receipt image';

  @override
  String get requestSentTitle => 'REQUEST SENT';

  @override
  String get requestReceivedMessage =>
      'We have received your request.\nYou will be notified once approved.';

  @override
  String get failedToSendRequest => 'Failed to send request';

  @override
  String get checkoutTitle => 'CHECKOUT';

  @override
  String get totalAmountLabel => 'TOTAL AMOUNT';

  @override
  String get discountCodeAppliedSuccess =>
      'Discount code applied successfully!';

  @override
  String get discountCodeInvalid => 'Invalid or already-used discount code.';

  @override
  String get discountCodeLabel => 'DISCOUNT CODE';

  @override
  String get enterCodeHint => 'Enter code here';

  @override
  String get applyButton => 'APPLY';

  @override
  String get cashWalletsLabel => 'CASH WALLETS';

  @override
  String get walletNumberLabel => 'WALLET NUMBER';

  @override
  String get instapayNumbersLabel => 'INSTAPAY NUMBERS';

  @override
  String get instapayPhoneLabel => 'INSTAPAY PHONE';

  @override
  String get instapayLinksLabel => 'INSTAPAY LINKS / USERNAME';

  @override
  String get paymentMethodsUnavailable => 'Payment methods unavailable';

  @override
  String get contactSupportOrRetryLater =>
      'Please contact support or try again later.';

  @override
  String get uploadReceiptLabel => 'UPLOAD RECEIPT';

  @override
  String get tapToUploadScreenshot => 'Tap to upload screenshot';

  @override
  String get notesOptionalLabel => 'NOTES (OPTIONAL)';

  @override
  String get addNotesHint => 'Add any notes...';

  @override
  String get confirmPaymentButton => 'CONFIRM PAYMENT';

  @override
  String get copyTooltip => 'Copy';

  @override
  String get openLinkInstapayButton => 'Open Link / InstaPay';

  @override
  String get couldNotFetchLatestData =>
      'Could not fetch latest data, showing cached version.';

  @override
  String get profileUpdatedSuccess => 'Profile Updated Successfully';

  @override
  String get failedToUpdateProfile => 'Failed to update profile';

  @override
  String get editProfileTitle => 'EDIT PROFILE';

  @override
  String get tapToChangePhoto => 'Tap to change photo';

  @override
  String get editFullNameHint => 'Enter your full name';

  @override
  String get nameRequiredValidation => 'Name is required';

  @override
  String get phoneNumberLabel => 'Phone Number';

  @override
  String get invalidPhoneNumberValidation => 'Invalid phone number';

  @override
  String get usernameLabel => 'Username';

  @override
  String get usernameEnglishNumbersOnlyHint => 'English letters & numbers only';

  @override
  String get usernameRequiredValidation => 'Username is required';

  @override
  String get usernameInvalidCharsValidation =>
      'Only English letters & numbers allowed (No spaces)';

  @override
  String get teacherInfoLabel => 'TEACHER INFO';

  @override
  String get specialtyJobTitleLabel => 'Specialty / Job Title';

  @override
  String get specialtyHint => 'e.g. Physics Teacher';

  @override
  String get whatsappNumberLabel => 'WhatsApp Number (For Students)';

  @override
  String get whatsappNumberHint => '201xxxxxxxxx';

  @override
  String get whatsappNumberNotice =>
      'Enter number with country code without \'+\' (e.g. 201xxxxxxxxx)';

  @override
  String get bioAboutMeLabel => 'Bio / About Me';

  @override
  String get bioHint => 'Tell students about yourself...';

  @override
  String get paymentMethodsLabel => 'PAYMENT METHODS';

  @override
  String get cashWalletNumbersTitle => 'Cash Wallet Numbers';

  @override
  String get enterWalletNumberHint => 'Enter Wallet Number';

  @override
  String get instapayNumbersTitle => 'InstaPay Numbers';

  @override
  String get enterInstapayPhoneHint => 'Enter InstaPay Phone Number';

  @override
  String get instapayLinksUsernamesTitle => 'InstaPay Links / Usernames';

  @override
  String get instapayLinkHint => 'username@instapay or Link';

  @override
  String get saveChangesButton => 'SAVE CHANGES';

  @override
  String get clickPlusToAddHint => 'Click + to add a number/link';

  @override
  String get failedToStartExam => 'Failed to start exam';

  @override
  String get accessDeniedFallback => 'Access Denied';

  @override
  String get examAlreadyCompleted => 'Exam already completed';

  @override
  String cannotSubmitUnanswered(int count) {
    return 'Cannot submit yet. You have $count unanswered questions!';
  }

  @override
  String get failedToSubmitTryAgain => 'Failed to submit. Try again.';

  @override
  String get exitExamTitle => 'Exit Exam?';

  @override
  String get exitExamWarningMessage =>
      'Leaving the exam screen now will AUTOMATICALLY SUBMIT your current answers and you cannot return.\n\nAre you sure?';

  @override
  String get stayButton => 'Stay';

  @override
  String get submitAndExitButton => 'Submit & Exit';

  @override
  String get noModelAnswerProvided => 'No model answer provided.';

  @override
  String get writtenQuestionInstructions =>
      'Written Question — Type your answer below';

  @override
  String get writeAnswerHint => 'Write your answer here...';

  @override
  String charactersCountLabel(int count) {
    return '$count characters';
  }

  @override
  String get markQuestionTooltip => 'Mark Question';

  @override
  String questionCounterLabel(int current, int total) {
    return 'Q $current/$total';
  }

  @override
  String get modelAnswerLabel => 'MODEL ANSWER';

  @override
  String get writtenQuestionBadge => 'WRITTEN QUESTION';

  @override
  String get questionTextFallback => 'Question Text';

  @override
  String get backButton => 'BACK';

  @override
  String get examCloseButton => 'CLOSE';

  @override
  String get examFinishButton => 'FINISH';

  @override
  String get examNextButton => 'NEXT';

  @override
  String get noAnswerSubmittedFallback => '(No answer submitted)';

  @override
  String get writtenBadgeShort => 'WRITTEN';

  @override
  String questionNumberLabel(int number) {
    return 'Question $number';
  }

  @override
  String pointsScoredLabel(int earned, int max) {
    return '$earned / $max pts';
  }

  @override
  String pointsPendingLabel(int max) {
    return '— / $max pts';
  }

  @override
  String get yourAnswerLabel => 'YOUR ANSWER';

  @override
  String get teacherFeedbackLabel => 'TEACHER FEEDBACK';

  @override
  String get failedToLoadResults => 'Failed to load results';

  @override
  String get awaitingTeacherReview => 'Awaiting Teacher Review';

  @override
  String get examUnderReviewMessage =>
      'Your exam has been submitted and is being reviewed by your teacher. You will be notified once grading is complete.';

  @override
  String get backToCourseButton => 'BACK TO COURSE';

  @override
  String get examPassedLabel => 'PASSED';

  @override
  String get examFailedLabel => 'FAILED';

  @override
  String get practiceResultTitle => 'PRACTICE RESULT';

  @override
  String get examResultsTitle => 'EXAM RESULTS';

  @override
  String get practiceModeNotice =>
      'This is a practice result (Practice Mode). This result has not been saved to your permanent grade record.';

  @override
  String get detailedAnalysisLabel => 'DETAILED ANALYSIS';

  @override
  String get writtenQuestionsPendingGrading =>
      'Written questions pending grading';

  @override
  String get couldNotOpenWhatsapp => 'Could not open WhatsApp';

  @override
  String get errorLoadingProfile => 'Error loading profile';

  @override
  String get chatOnWhatsapp => 'Chat on WhatsApp';

  @override
  String get noBioAvailable => 'No bio available.';

  @override
  String get availableCoursesLabel => 'AVAILABLE COURSES';

  @override
  String get untitledFallback => 'Untitled';

  @override
  String get closePlayer => 'CLOSE PLAYER';

  @override
  String get deleteAccountTitle => 'Delete Account';

  @override
  String get deleteAccountConfirmMessage =>
      'Are you sure you want to delete your account? This action cannot be undone and you will lose all your subscriptions.';

  @override
  String get accountDeletedSuccessfully => 'Account deleted successfully.';

  @override
  String errorDeletingAccount(String error) {
    return 'Error deleting account: $error';
  }

  @override
  String get settingsTitle => 'Settings';

  @override
  String qualityLabel(String quality) {
    return 'Quality: $quality';
  }

  @override
  String speedLabel(String speed) {
    return 'Speed: ${speed}x';
  }

  @override
  String startingInCountdown(String seconds) {
    return 'Starting in $seconds';
  }

  @override
  String get videoReadyStabilizing => 'Video Ready - Stabilizing Stream...';

  @override
  String get securityAlertTitle => 'SECURITY ALERT';

  @override
  String get screenRecordingDetectedMessage =>
      'Screen Recording Detected.\nPlayback has been disabled.';

  @override
  String get finalWarningTitle => '⚠️ Final Warning';

  @override
  String get contentRecordingViolationMessage =>
      'Recording content violates the terms of use.\nRepeating this will permanently ban your account and delete all your data.';

  @override
  String get pdfToolPen => 'Pen';

  @override
  String get pdfToolHighlightText => 'Highlight Text';

  @override
  String get pdfToolFreehandHighlight => 'Freehand Highlight';

  @override
  String get pdfToolEraser => 'Eraser';

  @override
  String get pdfToolComment => 'Comment';

  @override
  String get pdfToolUnderline => 'Underline';

  @override
  String get pdfToolText => 'Text';

  @override
  String get pdfToolShapes => 'Shapes';

  @override
  String get pdfToolImage => 'Image';

  @override
  String get undoTooltip => 'Undo';

  @override
  String get palmRejectionOn => 'Palm Rejection: On';

  @override
  String get palmRejectionOff => 'Palm Rejection: Off';

  @override
  String get boldLabel => 'Bold';

  @override
  String get underlineLabel => 'Underline';

  @override
  String get borderLabel => 'Border: ';

  @override
  String get fillLabel => 'Fill: ';

  @override
  String get chooseColorTitle => 'Choose a Color';

  @override
  String get saturationLabel => 'Saturation';

  @override
  String get brightnessLabel => 'Brightness';

  @override
  String get selectAction => 'Select';

  @override
  String get protectionFeaturesWarning =>
      'Warning: Some protection features may not work';

  @override
  String get securityWarningTitle => '⚠️ Security Warning';

  @override
  String get audioRecordingDetectedMessage =>
      'An audio recording attempt was detected!';

  @override
  String get recordingConsequencesMessage =>
      '• Playback has been stopped automatically\n• Recording violates intellectual property rights\n• Your account may be suspended';

  @override
  String get exitAction => 'Exit';

  @override
  String get protectedBadge => 'Protected';

  @override
  String get recordingDetectedTitle => 'Recording Detected!';

  @override
  String get playbackStoppedMessage => 'Playback has been stopped';

  @override
  String get verifyingFileMessage => 'Verifying file...';

  @override
  String get initializingProtectionMessage => 'Initializing protection...';

  @override
  String get directDownloadMessage => 'Downloading directly...';

  @override
  String get failedOpenProtectedFile => 'Failed to open the protected file.';

  @override
  String get pageIndexTitle => 'Page Index';

  @override
  String pageNumberLabel(String number) {
    return 'Page $number';
  }

  @override
  String get highlightLabel => 'Highlight';

  @override
  String get underlineActionLabel => 'Underline';

  @override
  String get editAction => 'Edit';

  @override
  String get noMarkupInSelectionMessage =>
      'No highlight or underline in this selection';

  @override
  String get editHighlightTitle => 'Edit Highlight';

  @override
  String get editUnderlineTitle => 'Edit Underline';

  @override
  String get deleteHighlightLabel => 'Delete Highlight';

  @override
  String get deleteUnderlineLabel => 'Delete Underline';

  @override
  String get editShapeTitle => 'Edit Shape';

  @override
  String get deleteShapeLabel => 'Delete Shape';

  @override
  String get addCommentTitle => 'Add Comment';

  @override
  String get commentTitle => 'Comment';

  @override
  String get writeNotesHint => 'Write your notes here...';

  @override
  String get noTextHint => 'No text...';

  @override
  String iconSizeLabel(String size) {
    return 'Icon Size: $size';
  }

  @override
  String opacityLabel(String percent) {
    return 'Opacity: $percent%';
  }

  @override
  String get defaultSettingsSaved => 'Default settings saved';

  @override
  String get saveAsDefaultLabel => 'Save as Default';

  @override
  String get textPreviewPlaceholder => 'Text preview...';

  @override
  String get writeTextHint => 'Write text here...';

  @override
  String failedFetchStats(String error) {
    return 'Failed to fetch statistics: $error';
  }

  @override
  String statisticsForTitle(String examTitle) {
    return 'Statistics: $examTitle';
  }

  @override
  String get numberOfAttemptsLabel => 'Number of Attempts';

  @override
  String get averagePercentageLabel => 'Average Percentage';

  @override
  String get honorRollTitle => 'Honor Roll (Top 10)';

  @override
  String get noCompletedAttemptsYet => 'No completed attempts yet';

  @override
  String get unknownStudentFallback => 'Unknown Student';

  @override
  String get notAvailable => 'Not available';

  @override
  String pointsSuffix(String score) {
    return '$score pts';
  }

  @override
  String get networkConnectionProblemMessage =>
      'A network connection problem occurred.\nPlease check your internet connection and try again.';

  @override
  String playerInitFailedMessage(String error) {
    return 'Failed to initialize the player: $error';
  }

  @override
  String get videoLoadFailedMessage => 'Failed to load the video.';

  @override
  String get noSourcesAvailableMessage =>
      'No sources available for this video.';

  @override
  String get darkModeLabel => 'Dark Mode';

  @override
  String get lightModeLabel => 'Light Mode';

  @override
  String failedLoadExamDetails(String error) {
    return 'Failed to load exam data: $error';
  }

  @override
  String get startDateAfterEndError =>
      'The start date cannot be after the end date!';

  @override
  String get endDateBeforeStartError =>
      'The end date cannot be before the start date!';

  @override
  String get deleteExamTitle => 'Delete Exam';

  @override
  String get deleteExamConfirmMessage =>
      'Are you sure you want to delete this exam?\n\n⚠️ Warning: All questions and all student results linked to this exam will be permanently deleted.';

  @override
  String get permanentDeleteAction => 'Delete Permanently';

  @override
  String get examDeletedSuccessfully => 'Exam deleted successfully';

  @override
  String deleteFailedMessage(String error) {
    return 'Delete failed: $error';
  }

  @override
  String get atLeastOneQuestionRequired => 'You must add at least one question';

  @override
  String get selectExamStartEndTime => 'Please set the exam start and end time';

  @override
  String get startTimeAfterEndError => 'Error: start time is after end time!';

  @override
  String get examUpdatedSuccessfully => 'Exam updated successfully';

  @override
  String get examCreatedSuccessfully => 'Exam created successfully';

  @override
  String genericErrorOccurred(String error) {
    return 'An error occurred: $error';
  }

  @override
  String get editExamTitle => 'Edit Exam';

  @override
  String get createNewExamTitle => 'Create New Exam';

  @override
  String get processingMessage => 'Processing...';

  @override
  String get examTitleLabel => 'Exam Title';

  @override
  String get examTitleHint => 'Example: First-term comprehensive exam';

  @override
  String get requiredField => 'Required';

  @override
  String get durationMinutesLabel => 'Duration (minutes)';

  @override
  String get durationHint => 'Enter the exam duration';

  @override
  String get randomizeQuestionsTitle => 'Randomize Question Order';

  @override
  String get randomizeQuestionsSubtitle =>
      'Each student sees a different question order';

  @override
  String get randomizeOptionsTitle => 'Randomize Option Order';

  @override
  String get randomizeOptionsSubtitle =>
      'Shuffle answer positions within each question';

  @override
  String get allowRetakeTitle => 'Allow Retake (Practice)';

  @override
  String get allowRetakeSubtitle =>
      'Student can retake the exam without affecting their first score';

  @override
  String get notifyStudentsTitle => 'Notify Students';

  @override
  String get notifyStudentsSubtitle =>
      'Send a notification to enrolled students when the exam starts';

  @override
  String get activationDateTimeLabel => 'Activation Date & Time (Start)';

  @override
  String startsAtLabel(String date) {
    return 'Starts: $date';
  }

  @override
  String get tapToSetStart => 'Tap to set the start';

  @override
  String get closingDateTimeLabel => 'Closing Date & Time (End)';

  @override
  String endsAtLabel(String date) {
    return 'Ends: $date';
  }

  @override
  String get tapToSetEnd => 'Tap to set the end';

  @override
  String questionsCountLabel(String count) {
    return 'Questions ($count)';
  }

  @override
  String get addQuestionAction => 'Add Question';

  @override
  String get noQuestionsAddedYet => 'No questions added yet';

  @override
  String get essayBadge => 'Essay';

  @override
  String essayQuestionSubtitle(String score, String imageStatus) {
    return 'Manual grading • Max score $score • $imageStatus';
  }

  @override
  String mcqQuestionSubtitle(String count, String imageStatus) {
    return '$count options • $imageStatus';
  }

  @override
  String get newImageStatus => 'New image';

  @override
  String get savedImageStatus => 'Saved image';

  @override
  String get textOnlyStatus => 'Text only';

  @override
  String get saveChangesAction => 'Save Changes';

  @override
  String get saveAndPublishExamAction => 'Save & Publish Exam';

  @override
  String get newQuestionTitle => 'New Question';

  @override
  String get editQuestionTitle => 'Edit Question';

  @override
  String get questionTextLabel => 'Question Text';

  @override
  String get questionTypeLabel => 'Question Type';

  @override
  String get mcqTypeOption => 'Multiple Choice';

  @override
  String get essayTypeOption => 'Essay (Manual Grading)';

  @override
  String get newImageSelectedStatus => 'New image selected';

  @override
  String get imageSavedPreviouslyStatus => 'Image saved previously';

  @override
  String get noImageStatus => 'No image';

  @override
  String get uploadChangeImageTooltip => 'Upload/change image';

  @override
  String get deleteImageTooltip => 'Delete image';

  @override
  String get maxScoreForQuestionLabel => 'Max score for this question:';

  @override
  String get scoreLabel => 'Score';

  @override
  String get essayInfoMessage =>
      'The student will write their answer in a text box, which you\'ll need to grade manually after submission.';

  @override
  String get modelAnswerOptionalLabel => 'Model Answer (optional):';

  @override
  String get modelAnswerHint =>
      'Write the model answer here for the student to see after the result is shown...';

  @override
  String get modelAnswerInfoMessage =>
      'This answer will be shown to the student on the result/review screen after grading, as a reference to compare with their own answer.';

  @override
  String get optionsSelectCorrectLabel => 'Options (select the correct one):';

  @override
  String get addOptionAction => 'Add Option';

  @override
  String optionNumberLabel(String number) {
    return 'Option $number';
  }

  @override
  String get deleteOptionTooltip => 'Delete option';

  @override
  String get saveQuestionAction => 'Save Question';

  @override
  String get minTwoOptionsRequired =>
      'The question must have at least two options';

  @override
  String get maxScoreRequiredForEssay =>
      'You must set a max score for the essay question';

  @override
  String get fillAllOptionsOrDelete =>
      'Please fill in all option fields or delete the empty ones';

  @override
  String errorFetchingFinancialStats(String error) {
    return 'Error: $error';
  }

  @override
  String get financialStatsTitle => 'Statistics & Earnings';

  @override
  String get totalStudentsLabel => 'Total Students';

  @override
  String get totalEarningsLabel => 'Total Earnings';

  @override
  String earningsEgpAmount(String amount) {
    return '$amount EGP';
  }

  @override
  String get coursesStatsSectionTitle => '📊 Course Statistics';

  @override
  String get subjectsStatsSectionTitle => '📚 Subject Statistics (Individual)';

  @override
  String studentCountLabel(String count) {
    return '$count students';
  }

  @override
  String get searchMinCharsWarning =>
      'Please enter at least 3 characters to search';

  @override
  String get promoteStudentDialogTitle => 'Promote Student';

  @override
  String get removeSupervisorDialogTitle => 'Remove Supervisor';

  @override
  String get promoteSuccessMessage =>
      'Student promoted and permissions granted successfully';

  @override
  String get demoteSuccessMessage => 'Supervisor removed successfully';

  @override
  String errorOccurredWithDetails(String error) {
    return 'An error occurred: $error';
  }

  @override
  String get manageTeamTitle => 'Manage Team';

  @override
  String get addNewSupervisorTitle => 'Add New Supervisor';

  @override
  String get addSupervisorSubtitle =>
      'Search for a student to promote and automatically grant them full permissions';

  @override
  String get searchByNameOrUsernameHint => 'Search by name or username...';

  @override
  String get searchResultsLabel => 'Search results:';

  @override
  String get noNameFallback => 'No Name';

  @override
  String promoteConfirmMessage(String name) {
    return 'Student \'$name\' will be promoted to supervisor and granted access to all of your current courses.\n\nAre you sure?';
  }

  @override
  String get promoteAction => 'Promote';

  @override
  String currentSupervisorsCountLabel(String count) {
    return 'Current Supervisors ($count)';
  }

  @override
  String get noSupervisorsCurrently => 'No supervisors currently';

  @override
  String get unknownFallback => 'Unknown';

  @override
  String get removeSupervisorTooltip => 'Remove supervision';

  @override
  String demoteConfirmMessage(String name) {
    return 'Supervisor permissions will be revoked from \'$name\' and they will return to being a regular student.\n\nThey will no longer be able to manage content.';
  }

  @override
  String get searchMinDigitsLettersWarning => 'Enter at least 3 digits/letters';

  @override
  String studentNotFoundOrError(String error) {
    return 'Student not found or an error occurred: $error';
  }

  @override
  String get revokeAccessDialogTitle => 'Revoke Access';

  @override
  String get revokeAccessConfirmMessage =>
      'Are you sure you want to remove this permission? The student will be prevented from accessing this content.';

  @override
  String get confirmRevokeAction => 'Confirm Revoke';

  @override
  String get accessGrantedSuccessMessage => 'Access granted successfully';

  @override
  String get accessRevokedSuccessMessage => 'Access revoked successfully';

  @override
  String operationFailedWithDetails(String error) {
    return 'Operation failed: $error';
  }

  @override
  String bulkGrantSuccessMessage(String count) {
    return '$count permissions granted successfully';
  }

  @override
  String bulkGrantErrorWithDetails(String error) {
    return 'An error occurred while granting access: $error';
  }

  @override
  String get loadingCoursesRetryMessage =>
      'Loading course data... please try again shortly.';

  @override
  String get choosePermissionsToGrantTitle => 'Choose permissions to grant';

  @override
  String grantWithCountAction(String count) {
    return 'Grant ($count)';
  }

  @override
  String get manageStudentsTitle => 'Manage Students (My Students)';

  @override
  String get phoneOrUsernameHint => 'Phone number or username';

  @override
  String get searchAction => 'Search';

  @override
  String get currentPermissionsLabel => 'Current Permissions:';

  @override
  String get managePermissionsAction => 'Manage Permissions';

  @override
  String get noAccessCurrentlyMessage =>
      'This student doesn\'t have any permissions currently';

  @override
  String get undefinedFallback => 'Undefined';

  @override
  String get fullCourseBadgeLabel => 'Full course';

  @override
  String get individualSubjectBadgeLabel => 'Individual subject';

  @override
  String get searchForStudentPrompt =>
      'Search for a student to manage their permissions';

  @override
  String phoneEmojiLabel(String phone) {
    return '📞 $phone';
  }

  @override
  String usernameEmojiLabel(String username) {
    return '👤 $username';
  }

  @override
  String get rejectionReasonDialogTitle => 'Rejection Reason';

  @override
  String get rejectionReasonHint => 'Write the rejection reason here...';

  @override
  String get confirmRejectionAction => 'Confirm Rejection';

  @override
  String get processingActionMessage => 'Processing...';

  @override
  String get studentApprovedSuccessMessage => 'Student approved successfully';

  @override
  String get requestRejectedMessage => 'Request rejected';

  @override
  String get authDataNotReadyError => 'Error: authentication data isn\'t ready';

  @override
  String get imageLoadFailedCheckConnection =>
      'Failed to load the image - check your connection';

  @override
  String get subscriptionRequestsTitle => 'Subscription Requests';

  @override
  String get tabPending => 'Pending';

  @override
  String get tabApproved => 'Approved';

  @override
  String get tabRejected => 'Rejected';

  @override
  String get noRequestsInListMessage => 'No requests in this list';

  @override
  String get unknownNameFallback => 'Unknown Name';

  @override
  String get requestedContentLabel => 'Requested Content:';

  @override
  String get notSpecifiedFallback => 'Not specified';

  @override
  String get studentNoteLabel => 'Student\'s note:';

  @override
  String get rejectionReasonLabel => 'Rejection reason:';

  @override
  String get myRequestsTitle => 'My Requests';

  @override
  String get trackYourOrdersLabel => 'TRACK YOUR ORDERS';

  @override
  String get noRequestsFound => 'No requests found';

  @override
  String get requestStatusApproved => 'Approved';

  @override
  String get requestStatusRejected => 'Rejected';

  @override
  String get requestStatusPending => 'Pending';

  @override
  String get unknownItemFallback => 'Unknown item';

  @override
  String get yourNoteLabel => 'Your note:';

  @override
  String get totalLabel => 'Total';

  @override
  String get egpCurrencyLabel => 'EGP';

  @override
  String get rejectRequestAction => 'Reject Request';

  @override
  String get acceptAndActivateAction => 'Accept & Activate';

  @override
  String errorLoadingDataWithDetails(String error) {
    return 'An error occurred while loading: $error';
  }

  @override
  String failedToFetchDataWithDetails(String error) {
    return 'Failed to fetch data: $error';
  }

  @override
  String get videoDurationRequiredWarning =>
      '⚠️ Please enter the actual video duration (it can\'t be left at zero)';

  @override
  String get minutesSecondsMaxWarning =>
      '⚠️ Minutes and seconds must not exceed 59';

  @override
  String get pleaseSelectPdfFileWarning => 'Please select a PDF file';

  @override
  String get invalidVideoUrlError => 'Invalid video URL';

  @override
  String get updatedSuccessfullyMessage => 'Updated Successfully';

  @override
  String get createdSuccessfullyMessage => 'Created Successfully';

  @override
  String contentSaveErrorWithDetails(String error) {
    return 'Error: $error';
  }

  @override
  String get pleaseSelectVideoFileFirstWarning =>
      '⚠️ Please select a video file first';

  @override
  String get videoUploadedDurationPendingMessage =>
      '✅ Video uploaded successfully; its duration will be extracted automatically once processing completes';

  @override
  String get videoUploadedSuccessMessage =>
      '✅ Video uploaded successfully and will be available once processing completes';

  @override
  String get confirmDeleteItemMessage =>
      'Are you sure you want to delete this item? This cannot be undone.';

  @override
  String get deletedSuccessfullyMessage => 'Deleted Successfully';

  @override
  String deleteFailedWithDetails(String error) {
    return 'Delete Failed: $error';
  }

  @override
  String get preparingUploadSessionStatus => 'Preparing upload session...';

  @override
  String uploadingVideoProgressStatus(String percent) {
    return 'Uploading video... $percent%';
  }

  @override
  String get connectionLostWaitingStatus =>
      '⏸️ Connection lost — waiting for the connection to return to continue automatically';

  @override
  String get savingVideoDataStatus => 'Saving video data...';

  @override
  String get editCourseTitle => 'Edit Course';

  @override
  String get newCourseTitle => 'New Course';

  @override
  String get editSubjectTitle => 'Edit Subject';

  @override
  String get newSubjectTitle => 'New Subject';

  @override
  String get editChapterTitle => 'Edit Chapter';

  @override
  String get newChapterTitle => 'New Chapter';

  @override
  String get editVideoTitle => 'Edit Video';

  @override
  String get newVideoTitle => 'New Video';

  @override
  String get editPdfTitle => 'Edit PDF';

  @override
  String get newPdfTitle => 'New PDF';

  @override
  String get cancelUploadAction => 'Cancel Upload';

  @override
  String get uploadingFileStatus => 'Uploading File...';

  @override
  String get savingDataStatus => 'Saving Data...';

  @override
  String get titleNameLabel => 'Title / Name';

  @override
  String get chapterFolderLabel => 'Folder (optional)';

  @override
  String get chapterFolderHint => 'e.g. Term 1, Unit 2 (leave empty for no folder)';

  @override
  String get enterTitleHereHint => 'Enter title here';

  @override
  String get descriptionFieldLabel => 'Description';

  @override
  String get enterDescriptionHint => 'Enter description';

  @override
  String get priceEgpFieldLabel => 'Price (EGP)';

  @override
  String get zeroPointZeroHint => '0.0';

  @override
  String get youtubeLinkTabLabel => 'YouTube Link';

  @override
  String get uploadVideoFileTabLabel => 'Upload Video File';

  @override
  String get newFileReplaceWarning =>
      'Selecting a new file here will fully replace the current video once the upload completes.';

  @override
  String get youtubeVideoLinkLabel => 'YouTube Video Link';

  @override
  String get actualVideoDurationLabel => 'Actual video duration ⏱️';

  @override
  String get hoursLabel => 'Hours';

  @override
  String get minutesLabel => 'Minutes';

  @override
  String get secondsLabel => 'Seconds';

  @override
  String get pasteYoutubeLinkHint =>
      'Paste the full YouTube link and set its duration to show it to students';

  @override
  String get noFileSelectedVideo => 'No file selected';

  @override
  String get tapToSelectVideoFile =>
      'Tap to select a video file from your device';

  @override
  String get extractingVideoDurationStatus => 'Extracting video duration...';

  @override
  String get resumableUploadFoundMessage =>
      'A previously interrupted upload for this file was found — the upload will resume from where it left off';

  @override
  String get resumeUploadAction => 'Resume Upload';

  @override
  String get uploadPauseResumeInfoMessage =>
      'The video upload can be paused and resumed later; it also resumes automatically after a connection drop instead of starting over.';

  @override
  String get videoDurationAutoExtractedLabel =>
      'Video duration (extracted automatically, editable) ⏱️';

  @override
  String get noPdfFileSelected => 'No file selected';

  @override
  String get tapToSelectPdfLabel => 'Tap to select PDF';

  @override
  String get sendNotificationToStudentsLabel => 'Send notification to students';

  @override
  String get notifySubscribedStudentsSubtitle =>
      'Alert subscribed students about this new content';

  @override
  String get saveChangesUpperAction => 'SAVE CHANGES';

  @override
  String get resumeAndUploadVideoAction => 'Resume & Upload Video';

  @override
  String get uploadVideoAction => 'Upload Video';

  @override
  String get createUpperAction => 'CREATE';

  @override
  String get deletePermanentlyUpperAction => 'DELETE PERMANENTLY';

  @override
  String get myProfileTitle => 'MY PROFILE';

  @override
  String get teacherDashboardSubtitle => 'TEACHER DASHBOARD';

  @override
  String get manageYourAccountSubtitle => 'MANAGE YOUR ACCOUNT';

  @override
  String get guestUserName => 'GUEST USER';

  @override
  String get notLoggedInLabel => 'Not Logged In';

  @override
  String get defaultUserNameLabel => 'User';

  @override
  String get teacherControlsSection => 'TEACHER CONTROLS';

  @override
  String get incomingRequestsMenu => 'Incoming Requests';

  @override
  String get myStudentsMenu => 'My Students';

  @override
  String get manageTeamMenu => 'Manage Team';

  @override
  String get financialStatsMenu => 'Financial Stats';

  @override
  String get accountSettingsSection => 'ACCOUNT SETTINGS';

  @override
  String get editProfileMenu => 'Edit Profile';

  @override
  String get changePasswordMenu => 'Change Password';

  @override
  String get myRequestsMenu => 'My Requests';

  @override
  String get generalSection => 'GENERAL';

  @override
  String get appInformationMenu => 'App Information';

  @override
  String get languageMenu => 'Language';

  @override
  String get dangerZoneSection => 'DANGER ZONE';

  @override
  String get deleteMyAccountMenu => 'Delete My Account';

  @override
  String get loginRegisterButton => 'LOGIN / REGISTER';

  @override
  String get logoutButton => 'LOGOUT';

  @override
  String get selectLanguageTitle => 'Select Language';

  @override
  String get englishLanguageOption => 'English';

  @override
  String get arabicLanguageOption => 'العربية';

  @override
  String get hqAudioLabel => 'HQ Audio';

  @override
  String get doubleSpeedLabel => 'speed×2';

  @override
  String get freeAccessLabel => 'Free Access';
}
