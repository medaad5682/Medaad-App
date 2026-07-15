import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_ar.dart';
import 'app_localizations_en.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'generated/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
      : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
    delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
  ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('ar'),
    Locale('en')
  ];

  /// The application name shown in the title bar / task switcher
  ///
  /// In en, this message translates to:
  /// **'Medaad'**
  String get appTitle;

  /// Generic Cancel button label
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// Generic Save button label
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get save;

  /// Generic Delete button label
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get delete;

  /// Generic Confirm button label
  ///
  /// In en, this message translates to:
  /// **'Confirm'**
  String get confirm;

  /// Title shown on delete-confirmation dialogs
  ///
  /// In en, this message translates to:
  /// **'Confirm Delete'**
  String get confirmDelete;

  /// Generic OK button label
  ///
  /// In en, this message translates to:
  /// **'OK'**
  String get ok;

  /// Generic affirmative button label
  ///
  /// In en, this message translates to:
  /// **'Yes'**
  String get yes;

  /// Generic negative button label
  ///
  /// In en, this message translates to:
  /// **'No'**
  String get no;

  /// Generic Close button label
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get close;

  /// Generic Retry button label
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get retry;

  /// Generic loading indicator label
  ///
  /// In en, this message translates to:
  /// **'Loading...'**
  String get loading;

  /// Generic error dialog/title label
  ///
  /// In en, this message translates to:
  /// **'Error'**
  String get error;

  /// Generic success dialog/title label
  ///
  /// In en, this message translates to:
  /// **'Success'**
  String get success;

  /// Label for the language setting / switcher
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get language;

  /// Name of the English language option in the language switcher
  ///
  /// In en, this message translates to:
  /// **'English'**
  String get languageEnglish;

  /// Name of the Arabic language option in the language switcher
  ///
  /// In en, this message translates to:
  /// **'Arabic'**
  String get languageArabic;

  /// Notice shown to the user when changing language, explaining the app will restart
  ///
  /// In en, this message translates to:
  /// **'The app will restart to apply the new language.'**
  String get languageChangeRestartNotice;

  /// Tagline shown under the logo on the splash screen
  ///
  /// In en, this message translates to:
  /// **'EMPOWERING YOUR GROWTH'**
  String get splashTagline;

  /// Loading label shown under the progress bar on the splash screen
  ///
  /// In en, this message translates to:
  /// **'LOADING SYSTEM'**
  String get splashLoadingSystem;

  /// Title of the first-launch terms & privacy acceptance dialog
  ///
  /// In en, this message translates to:
  /// **'Welcome'**
  String get termsWelcomeTitle;

  /// Body text of the first-launch terms & privacy acceptance dialog
  ///
  /// In en, this message translates to:
  /// **'Please accept our Terms & Privacy Policy to continue.'**
  String get termsDialogBody;

  /// Label/title for Terms & Conditions, used as a list item and screen title
  ///
  /// In en, this message translates to:
  /// **'Terms & Conditions'**
  String get termsAndConditions;

  /// Label/title for Privacy Policy, used as a list item and screen title
  ///
  /// In en, this message translates to:
  /// **'Privacy Policy'**
  String get privacyPolicy;

  /// Button label to decline the terms & privacy policy
  ///
  /// In en, this message translates to:
  /// **'DECLINE'**
  String get decline;

  /// Button label to accept the terms & privacy policy
  ///
  /// In en, this message translates to:
  /// **'ACCEPT'**
  String get accept;

  /// Title of the app update dialog
  ///
  /// In en, this message translates to:
  /// **'App Update'**
  String get appUpdateTitle;

  /// Button label to dismiss an optional app update dialog
  ///
  /// In en, this message translates to:
  /// **'Later'**
  String get updateLater;

  /// Button label to open the store and update the app
  ///
  /// In en, this message translates to:
  /// **'Update Now'**
  String get updateNow;

  /// Snackbar message shown when the app falls back to offline mode with cached data
  ///
  /// In en, this message translates to:
  /// **'No Internet. Entering Offline Mode.'**
  String get offlineModeEnteredMessage;

  /// Snackbar message shown when the app falls back to offline mode with no cached data
  ///
  /// In en, this message translates to:
  /// **'Offline Mode (Limited Access)'**
  String get offlineModeLimitedMessage;

  /// Generic error message shown when a network request fails
  ///
  /// In en, this message translates to:
  /// **'Connection Error'**
  String get connectionError;

  /// Sign in button label / link text
  ///
  /// In en, this message translates to:
  /// **'SIGN IN'**
  String get signIn;

  /// Create account header, button label, and link text
  ///
  /// In en, this message translates to:
  /// **'CREATE ACCOUNT'**
  String get createAccount;

  /// Input field label for password, used on login and register screens
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get passwordLabel;

  /// Prompt on the register screen linking back to login
  ///
  /// In en, this message translates to:
  /// **'Already have an account? '**
  String get alreadyHaveAccount;

  /// Prompt on the login screen linking to registration
  ///
  /// In en, this message translates to:
  /// **'New student? '**
  String get newStudentQuestion;

  /// Validation error when login fields are left empty
  ///
  /// In en, this message translates to:
  /// **'Please enter username/phone and password'**
  String get loginEmptyFieldsError;

  /// Fallback error message when login fails without a specific server message
  ///
  /// In en, this message translates to:
  /// **'Login failed'**
  String get loginFailedDefault;

  /// Header title on the login screen
  ///
  /// In en, this message translates to:
  /// **'LOGIN'**
  String get loginTitle;

  /// Subtitle under the login header
  ///
  /// In en, this message translates to:
  /// **'PLEASE LOGIN TO CONTINUE.'**
  String get loginSubtitle;

  /// Input field label for the login identifier field
  ///
  /// In en, this message translates to:
  /// **'Username or Phone'**
  String get usernameOrPhoneLabel;

  /// Hint text for the login identifier field
  ///
  /// In en, this message translates to:
  /// **'Enter username or 01xxxxxxxxx'**
  String get usernameOrPhoneHint;

  /// Button label to continue into the app as a guest
  ///
  /// In en, this message translates to:
  /// **'BROWSE AS GUEST'**
  String get browseAsGuest;

  /// Validation error when required register fields are empty
  ///
  /// In en, this message translates to:
  /// **'All fields are required'**
  String get registerAllFieldsRequired;

  /// Validation error when the chosen username contains invalid characters
  ///
  /// In en, this message translates to:
  /// **'Username must be English letters & numbers only'**
  String get registerUsernameInvalid;

  /// Validation error for an invalid phone number format
  ///
  /// In en, this message translates to:
  /// **'Invalid phone number (11 digits starting with 01)'**
  String get registerPhoneInvalid;

  /// Validation error when the password is too short
  ///
  /// In en, this message translates to:
  /// **'Password must be at least 6 characters'**
  String get registerPasswordTooShort;

  /// Validation error when password and confirm password differ
  ///
  /// In en, this message translates to:
  /// **'Passwords do not match'**
  String get registerPasswordMismatch;

  /// Snackbar message shown after successful registration
  ///
  /// In en, this message translates to:
  /// **'Account created successfully. Please login.'**
  String get registerSuccessMessage;

  /// Fallback error message when registration fails without a specific server message
  ///
  /// In en, this message translates to:
  /// **'Registration failed'**
  String get registerFailedDefault;

  /// Subtitle under the register header
  ///
  /// In en, this message translates to:
  /// **'FILL IN THE DETAILS TO JOIN US.'**
  String get registerSubtitle;

  /// Input field label for full name
  ///
  /// In en, this message translates to:
  /// **'Full Name'**
  String get fullNameLabel;

  /// Hint text for the full name field
  ///
  /// In en, this message translates to:
  /// **'Your full name'**
  String get fullNameHint;

  /// Input field label for the optional phone number field on register
  ///
  /// In en, this message translates to:
  /// **'Phone Number (Optional)'**
  String get phoneNumberOptionalLabel;

  /// Hint text showing the expected phone number format
  ///
  /// In en, this message translates to:
  /// **'01xxxxxxxxx'**
  String get phoneNumberHint;

  /// Input field label for username, clarifying English-only characters
  ///
  /// In en, this message translates to:
  /// **'Username (English Only)'**
  String get usernameEnglishOnlyLabel;

  /// Hint text for the username field on register
  ///
  /// In en, this message translates to:
  /// **'username'**
  String get usernameHint;

  /// Input field label for confirming the chosen password
  ///
  /// In en, this message translates to:
  /// **'Confirm Password'**
  String get confirmPasswordLabel;

  /// Bottom navigation bar label for the Home tab
  ///
  /// In en, this message translates to:
  /// **'Home'**
  String get navHome;

  /// Bottom navigation bar label for the My Courses tab
  ///
  /// In en, this message translates to:
  /// **'Courses'**
  String get navCourses;

  /// Bottom navigation bar label for the Downloads tab
  ///
  /// In en, this message translates to:
  /// **'Downloads'**
  String get navDownloads;

  /// Bottom navigation bar label for the Profile tab
  ///
  /// In en, this message translates to:
  /// **'Profile'**
  String get navProfile;

  /// Small greeting label above the user's name on the home screen
  ///
  /// In en, this message translates to:
  /// **'WELCOME'**
  String get homeWelcomeGreeting;

  /// Fallback display name on home screen when the user has no first name set (e.g. guest mode)
  ///
  /// In en, this message translates to:
  /// **'GUEST'**
  String get guestFallbackName;

  /// First motivational quote shown in the home screen slider
  ///
  /// In en, this message translates to:
  /// **'Knowledge is the key to unlocking your true potential.'**
  String get encouragement1;

  /// Second motivational quote shown in the home screen slider
  ///
  /// In en, this message translates to:
  /// **'Every expert was once a beginner. Keep learning.'**
  String get encouragement2;

  /// Third motivational quote shown in the home screen slider
  ///
  /// In en, this message translates to:
  /// **'Your future self will thank you for the effort you put in today.'**
  String get encouragement3;

  /// Fourth motivational quote shown in the home screen slider
  ///
  /// In en, this message translates to:
  /// **'Invest in yourself; education pays the best interest.'**
  String get encouragement4;

  /// Fifth motivational quote shown in the home screen slider
  ///
  /// In en, this message translates to:
  /// **'Learning never exhausts the mind. Stay curious!'**
  String get encouragement5;

  /// Section title shown above the course list when there is no active search
  ///
  /// In en, this message translates to:
  /// **'SUGGESTED FOR YOU'**
  String get suggestedForYou;

  /// Section title shown above the course list when filtering by search
  ///
  /// In en, this message translates to:
  /// **'SEARCH RESULTS'**
  String get searchResults;

  /// Small status badge shown next to the course list section title
  ///
  /// In en, this message translates to:
  /// **'ACTIVE'**
  String get activeLabel;

  /// Empty state message when no courses match the current search or list
  ///
  /// In en, this message translates to:
  /// **'No courses found'**
  String get noCoursesFound;

  /// Hint text for the course search field on the home screen
  ///
  /// In en, this message translates to:
  /// **'Search course name or code...'**
  String get searchCourseHint;

  /// Header title on the My Courses / Library screen, shown in both the guest and logged-in views
  ///
  /// In en, this message translates to:
  /// **'LIBRARY'**
  String get libraryTitle;

  /// Small subtitle shown under the Library header when browsing as a guest
  ///
  /// In en, this message translates to:
  /// **'GUEST MODE'**
  String get guestModeLabel;

  /// Title shown to guests on the Library screen explaining they must log in to see their courses
  ///
  /// In en, this message translates to:
  /// **'LOGIN REQUIRED'**
  String get loginRequiredTitle;

  /// Body message shown to guests on the Library screen below the login-required title
  ///
  /// In en, this message translates to:
  /// **'Sign in to view and access your enrolled courses.'**
  String get loginRequiredMessage;

  /// Message shown on the Course Details screen when the course data could not be loaded
  ///
  /// In en, this message translates to:
  /// **'Course not found'**
  String get courseNotFound;

  /// Fallback instructor name on the Course Details screen when none is provided
  ///
  /// In en, this message translates to:
  /// **'Unknown Instructor'**
  String get unknownInstructor;

  /// Snackbar shown when tapping the instructor card but no teacher profile id exists
  ///
  /// In en, this message translates to:
  /// **'Instructor profile not available'**
  String get instructorProfileUnavailable;

  /// Small label above the instructor's name on the Course Details screen
  ///
  /// In en, this message translates to:
  /// **'INSTRUCTOR'**
  String get instructorLabel;

  /// Fallback text on the Course Details screen when a course has no description
  ///
  /// In en, this message translates to:
  /// **'No description available.'**
  String get noDescriptionAvailable;

  /// Heading shown to teacher accounts on the Course Details screen, replacing the purchase section
  ///
  /// In en, this message translates to:
  /// **'TEACHER ACCOUNT'**
  String get teacherAccountLabel;

  /// Explanatory message shown to teacher accounts in place of the purchase options
  ///
  /// In en, this message translates to:
  /// **'Teachers cannot purchase courses.'**
  String get teachersCannotPurchaseMessage;

  /// Section title on the Course Details screen when in free-activation mode
  ///
  /// In en, this message translates to:
  /// **'COURSE CONTENT'**
  String get courseContentLabel;

  /// Section title on the Course Details screen when not in free-activation mode
  ///
  /// In en, this message translates to:
  /// **'PURCHASE OPTIONS'**
  String get purchaseOptionsLabel;

  /// Label for the full-course option card in free-activation mode
  ///
  /// In en, this message translates to:
  /// **'FULL COURSE'**
  String get fullCourseLabel;

  /// Label for the full-course option card in paid mode
  ///
  /// In en, this message translates to:
  /// **'FULL COURSE ACCESS'**
  String get fullCourseAccessLabel;

  /// Subtitle describing what the full-course option includes
  ///
  /// In en, this message translates to:
  /// **'Access all subjects & exams'**
  String get accessAllSubjectsExams;

  /// Badge shown when the student already owns the full course
  ///
  /// In en, this message translates to:
  /// **'COURSE OWNED'**
  String get courseOwnedLabel;

  /// Section title above the list of individually-purchasable subjects
  ///
  /// In en, this message translates to:
  /// **'INDIVIDUAL SUBJECTS'**
  String get individualSubjectsLabel;

  /// Small badge shown next to a subject the student already owns
  ///
  /// In en, this message translates to:
  /// **'OWNED'**
  String get ownedLabel;

  /// Price displayed with the EGP currency suffix
  ///
  /// In en, this message translates to:
  /// **'{price} EGP'**
  String priceEgp(String price);

  /// Label above the total price in the bottom checkout bar
  ///
  /// In en, this message translates to:
  /// **'TOTAL PAYABLE'**
  String get totalPayableLabel;

  /// Label shown in the bottom bar instead of a price when in free-activation mode
  ///
  /// In en, this message translates to:
  /// **'Free Activation'**
  String get freeActivationLabel;

  /// Button label to activate a free course/subject
  ///
  /// In en, this message translates to:
  /// **'ACTIVATE'**
  String get activateButton;

  /// Button label to proceed to checkout for a paid course/subject
  ///
  /// In en, this message translates to:
  /// **'CHECKOUT'**
  String get checkoutButton;

  /// Snackbar error when trying to activate without selecting any items
  ///
  /// In en, this message translates to:
  /// **'Please select items first'**
  String get selectItemsFirstError;

  /// Snackbar shown after a successful free activation
  ///
  /// In en, this message translates to:
  /// **'Activation Successful! ✅'**
  String get activationSuccessMessage;

  /// Snackbar shown when a free activation request fails
  ///
  /// In en, this message translates to:
  /// **'Failed to activate. Try again.'**
  String get activationFailedMessage;

  /// Fallback instructor name on the Course Materials (subject list) screen when none is provided
  ///
  /// In en, this message translates to:
  /// **'Instructor'**
  String get instructorFallback;

  /// Subtitle under the course title on the Course Materials screen, prompting the student to pick a subject
  ///
  /// In en, this message translates to:
  /// **'CHOOSE SUBJECT'**
  String get chooseSubjectLabel;

  /// Empty state message on the Course Materials screen when a course has no subjects
  ///
  /// In en, this message translates to:
  /// **'NO SUBJECTS FOUND'**
  String get noSubjectsFound;

  /// Error message on the Subject Materials screen when chapter/exam data fails to load
  ///
  /// In en, this message translates to:
  /// **'Failed to load content.'**
  String get failedToLoadContent;

  /// Title of the dialog where a student writes anonymous feedback about a chapter
  ///
  /// In en, this message translates to:
  /// **'We\'d love your feedback'**
  String get studentFeedbackDialogTitle;

  /// Hint text inside the anonymous chapter feedback text field
  ///
  /// In en, this message translates to:
  /// **'Write your feedback or notes about this chapter (anonymous)'**
  String get studentFeedbackHint;

  /// Snackbar shown after a student successfully submits anonymous chapter feedback
  ///
  /// In en, this message translates to:
  /// **'Your feedback was submitted successfully, thank you!'**
  String get studentFeedbackSuccessMessage;

  /// Snackbar shown when submitting anonymous chapter feedback fails
  ///
  /// In en, this message translates to:
  /// **'A connection error occurred'**
  String get studentFeedbackConnectionError;

  /// Generic Submit button label
  ///
  /// In en, this message translates to:
  /// **'Submit'**
  String get submitLabel;

  /// Snackbar shown when a teacher fails to load anonymous student feedback for a chapter
  ///
  /// In en, this message translates to:
  /// **'Failed to load feedback'**
  String get teacherFeedbackFetchFailed;

  /// Title of the dialog where a teacher reviews anonymous feedback submitted by students for a chapter
  ///
  /// In en, this message translates to:
  /// **'Anonymous Student Feedback'**
  String get teacherFeedbackDialogTitle;

  /// Empty state message in the teacher's anonymous feedback dialog when no feedback exists
  ///
  /// In en, this message translates to:
  /// **'No feedback submitted yet'**
  String get teacherFeedbackEmptyState;

  /// Subtitle under the subject title on the Subject Materials screen
  ///
  /// In en, this message translates to:
  /// **'SUBJECT CONTENTS'**
  String get subjectContentsLabel;

  /// Tab label for the chapters list on the Subject Materials screen
  ///
  /// In en, this message translates to:
  /// **'Chapters'**
  String get chaptersTabLabel;

  /// Tab label for the exams list on the Subject Materials screen, showing the exam count
  ///
  /// In en, this message translates to:
  /// **'Exams ({count})'**
  String examsTabLabel(int count);

  /// Empty state message when a subject has no exams yet
  ///
  /// In en, this message translates to:
  /// **'No exams available yet'**
  String get noExamsAvailable;

  /// Exam status badge: the student hasn't attempted the exam yet
  ///
  /// In en, this message translates to:
  /// **'UNSOLVED'**
  String get examStatusUnsolved;

  /// Exam status badge: submitted and awaiting manual teacher grading
  ///
  /// In en, this message translates to:
  /// **'PENDING'**
  String get examStatusPending;

  /// Exam status badge: completed but retake is allowed for practice
  ///
  /// In en, this message translates to:
  /// **'PRACTICE'**
  String get examStatusPractice;

  /// Exam status badge: completed and no retake allowed
  ///
  /// In en, this message translates to:
  /// **'COMPLETED'**
  String get examStatusCompleted;

  /// Exam status badge: the exam window has expired
  ///
  /// In en, this message translates to:
  /// **'EXPIRED'**
  String get examStatusExpired;

  /// Fallback exam title when none is set, shown in the exams list
  ///
  /// In en, this message translates to:
  /// **'Untitled Exam'**
  String get untitledExamFallback;

  /// Exam duration shown in minutes on the exam list item
  ///
  /// In en, this message translates to:
  /// **'{minutes} MINS'**
  String examDurationMinutes(String minutes);

  /// Tooltip on the teacher's edit-exam icon button
  ///
  /// In en, this message translates to:
  /// **'Edit Exam'**
  String get editExamTooltip;

  /// Tooltip on the teacher's exam statistics icon button
  ///
  /// In en, this message translates to:
  /// **'Statistics'**
  String get statisticsTooltip;

  /// Generic fallback exam title used in a few places (stats screen, exam view)
  ///
  /// In en, this message translates to:
  /// **'Exam'**
  String get examFallbackTitle;

  /// Title of the dialog shown when a student opens an exam that's awaiting manual teacher grading
  ///
  /// In en, this message translates to:
  /// **'Under Review'**
  String get examPendingReviewTitle;

  /// Message shown when a submitted exam is still awaiting teacher grading
  ///
  /// In en, this message translates to:
  /// **'This exam is pending review by the teacher'**
  String get examPendingReviewMessage;

  /// Fallback title passed to the Exam Result screen when the exam has no title
  ///
  /// In en, this message translates to:
  /// **'Exam Result'**
  String get examResultFallbackTitle;

  /// Snackbar shown when an exam result cannot be opened because no attempt id is available
  ///
  /// In en, this message translates to:
  /// **'Error: Cannot load result.'**
  String get examResultLoadError;

  /// Title of the dialog offering to view a previous result or retake a completed exam
  ///
  /// In en, this message translates to:
  /// **'Exam Options'**
  String get examOptionsDialogTitle;

  /// Body of the dialog offering to view a previous result or retake a completed exam
  ///
  /// In en, this message translates to:
  /// **'You\'ve already completed this exam. Would you like to view your previous result or retake the exam for practice?'**
  String get examRetakeOptionsMessage;

  /// Button label to view a previously completed exam's result
  ///
  /// In en, this message translates to:
  /// **'View Result'**
  String get viewResultButton;

  /// Button label to retake a completed exam for practice
  ///
  /// In en, this message translates to:
  /// **'Retake for Practice'**
  String get retakeForPracticeButton;

  /// Title of the dialog confirming the student wants to start an exam
  ///
  /// In en, this message translates to:
  /// **'Confirm Start Exam'**
  String get confirmStartExamTitle;

  /// Body of the dialog confirming the student wants to start an exam
  ///
  /// In en, this message translates to:
  /// **'Are you ready? The exam and timer will begin once you confirm.'**
  String get confirmStartExamMessage;

  /// Button label to begin an exam attempt
  ///
  /// In en, this message translates to:
  /// **'Start Exam'**
  String get startExamButton;

  /// Empty state message when a subject has no chapters yet
  ///
  /// In en, this message translates to:
  /// **'No chapters found'**
  String get noChaptersFound;

  /// Fallback course title passed to the Chapter Contents screen when none is known
  ///
  /// In en, this message translates to:
  /// **'Unknown Course'**
  String get unknownCourseFallback;

  /// Fallback chapter title when none is set
  ///
  /// In en, this message translates to:
  /// **'Chapter'**
  String get chapterFallbackTitle;

  /// Count of videos + PDFs shown on a chapter list item
  ///
  /// In en, this message translates to:
  /// **'{count} CONTENTS'**
  String contentsCountLabel(int count);

  /// Button label on the guest Library screen to go to the login screen
  ///
  /// In en, this message translates to:
  /// **'LOGIN NOW'**
  String get loginNowButton;

  /// Small subtitle under the Library header on the logged-in Library/My Courses screen
  ///
  /// In en, this message translates to:
  /// **'MY LESSONS'**
  String get myLessonsSubtitle;

  /// Empty state message when the student's library has no enrolled courses
  ///
  /// In en, this message translates to:
  /// **'NO ACTIVE COURSES'**
  String get noActiveCourses;

  /// Header title on the course market/store screen
  ///
  /// In en, this message translates to:
  /// **'MARKET'**
  String get marketTitle;

  /// Hint text for the search field on the course market screen
  ///
  /// In en, this message translates to:
  /// **'Find excellence...'**
  String get searchCourseMarketHint;

  /// Auto-added key for appInformation
  ///
  /// In en, this message translates to:
  /// **'App Information'**
  String get appInformation;

  /// Auto-added key for craftedWithPassion
  ///
  /// In en, this message translates to:
  /// **'Crafted with passion for learners everywhere.'**
  String get craftedWithPassion;

  /// Auto-added key for legalAndDocs
  ///
  /// In en, this message translates to:
  /// **'Legal & Docs'**
  String get legalAndDocs;

  /// Auto-added key for contactSupport
  ///
  /// In en, this message translates to:
  /// **'Contact Support'**
  String get contactSupport;

  /// Auto-added key for supportContactNotAvailable
  ///
  /// In en, this message translates to:
  /// **'Support contact not available'**
  String get supportContactNotAvailable;

  /// Auto-added key for developedBy
  ///
  /// In en, this message translates to:
  /// **'Developed By'**
  String get developedBy;

  /// Auto-added key for downloadedSubjectsLabel
  ///
  /// In en, this message translates to:
  /// **'DOWNLOADED SUBJECTS'**
  String get downloadedSubjectsLabel;

  /// Auto-added key for downloadedChaptersLabel
  ///
  /// In en, this message translates to:
  /// **'DOWNLOADED CHAPTERS'**
  String get downloadedChaptersLabel;

  /// Auto-added key for downloadsTitle
  ///
  /// In en, this message translates to:
  /// **'DOWNLOADS'**
  String get downloadsTitle;

  /// Auto-added key for localCoursesLabel
  ///
  /// In en, this message translates to:
  /// **'LOCAL COURSES'**
  String get localCoursesLabel;

  /// Auto-added key for noStoredFiles
  ///
  /// In en, this message translates to:
  /// **'NO STORED FILES'**
  String get noStoredFiles;

  /// Auto-added key for activeDownloadsLabel
  ///
  /// In en, this message translates to:
  /// **'ACTIVE DOWNLOADS'**
  String get activeDownloadsLabel;

  /// Auto-added key for downloadingItemPlaceholder
  ///
  /// In en, this message translates to:
  /// **'Downloading Item...'**
  String get downloadingItemPlaceholder;

  /// Auto-added key for errorPreparingVideoPlayback
  ///
  /// In en, this message translates to:
  /// **'Error preparing video playback'**
  String get errorPreparingVideoPlayback;

  /// Auto-added key for errorOpeningPdf
  ///
  /// In en, this message translates to:
  /// **'Error opening PDF'**
  String get errorOpeningPdf;

  /// Auto-added key for fileRemoved
  ///
  /// In en, this message translates to:
  /// **'File removed'**
  String get fileRemoved;

  /// Auto-added key for failedToDeleteFile
  ///
  /// In en, this message translates to:
  /// **'Failed to delete file'**
  String get failedToDeleteFile;

  /// Auto-added key for offlineVideoFallbackTitle
  ///
  /// In en, this message translates to:
  /// **'Offline Video'**
  String get offlineVideoFallbackTitle;

  /// Auto-added key for documentFallbackTitle
  ///
  /// In en, this message translates to:
  /// **'Document'**
  String get documentFallbackTitle;

  /// Auto-added key for noVideosDownloaded
  ///
  /// In en, this message translates to:
  /// **'NO VIDEOS DOWNLOADED'**
  String get noVideosDownloaded;

  /// Auto-added key for noPdfsDownloaded
  ///
  /// In en, this message translates to:
  /// **'NO PDFS DOWNLOADED'**
  String get noPdfsDownloaded;

  /// Auto-added placeholder key for filesCountLabel
  ///
  /// In en, this message translates to:
  /// **'{count} FILES'**
  String filesCountLabel(int count);

  /// Auto-added placeholder key for activeCountLabel
  ///
  /// In en, this message translates to:
  /// **'{count} ACTIVE'**
  String activeCountLabel(int count);

  /// Auto-added placeholder key for filesDownloadedCountLabel
  ///
  /// In en, this message translates to:
  /// **'{count} FILES DOWNLOADED'**
  String filesDownloadedCountLabel(int count);

  /// Auto-added placeholder key for videosTabWithCount
  ///
  /// In en, this message translates to:
  /// **'Videos ({count})'**
  String videosTabWithCount(int count);

  /// Auto-added placeholder key for pdfsTabWithCount
  ///
  /// In en, this message translates to:
  /// **'PDFs ({count})'**
  String pdfsTabWithCount(int count);

  /// Auto-added placeholder key for sizeInMb
  ///
  /// In en, this message translates to:
  /// **'{size} MB'**
  String sizeInMb(String size);

  /// Auto-added placeholder key for downloadPercentLabel
  ///
  /// In en, this message translates to:
  /// **'{percent}%'**
  String downloadPercentLabel(int percent);

  /// fallback label
  ///
  /// In en, this message translates to:
  /// **'Unknown Subject'**
  String get unknownSubjectFallback;

  /// fallback label
  ///
  /// In en, this message translates to:
  /// **'Unknown Chapter'**
  String get unknownChapterFallback;

  /// Auto-added
  ///
  /// In en, this message translates to:
  /// **'Please fill all fields'**
  String get pleaseFillAllFields;

  /// Auto-added
  ///
  /// In en, this message translates to:
  /// **'Password Updated Successfully'**
  String get passwordUpdatedSuccessfully;

  /// Auto-added
  ///
  /// In en, this message translates to:
  /// **'Failed to update password'**
  String get failedToUpdatePassword;

  /// Auto-added
  ///
  /// In en, this message translates to:
  /// **'Connection error. Please try again.'**
  String get connectionErrorTryAgain;

  /// Auto-added
  ///
  /// In en, this message translates to:
  /// **'CHANGE PASSWORD'**
  String get changePasswordTitle;

  /// Auto-added
  ///
  /// In en, this message translates to:
  /// **'Current Password'**
  String get currentPasswordLabel;

  /// Auto-added
  ///
  /// In en, this message translates to:
  /// **'New Password'**
  String get newPasswordLabel;

  /// Auto-added
  ///
  /// In en, this message translates to:
  /// **'Confirm New Password'**
  String get confirmNewPasswordLabel;

  /// Auto-added
  ///
  /// In en, this message translates to:
  /// **'Create new password'**
  String get createNewPasswordHint;

  /// Auto-added
  ///
  /// In en, this message translates to:
  /// **'Confirm new password'**
  String get confirmNewPasswordHint;

  /// Auto-added
  ///
  /// In en, this message translates to:
  /// **'UPDATE PASSWORD'**
  String get updatePasswordButton;

  /// Auto-added
  ///
  /// In en, this message translates to:
  /// **'Please login to view notifications.'**
  String get pleaseLoginToViewNotifications;

  /// Auto-added
  ///
  /// In en, this message translates to:
  /// **'Failed to load notifications.'**
  String get failedToLoadNotifications;

  /// Auto-added
  ///
  /// In en, this message translates to:
  /// **'Connection error. Please try again later.'**
  String get connectionErrorTryAgainLater;

  /// Auto-added
  ///
  /// In en, this message translates to:
  /// **'Notifications'**
  String get notificationsTitle;

  /// Auto-added
  ///
  /// In en, this message translates to:
  /// **'No notifications yet'**
  String get noNotificationsYet;

  /// Auto-added
  ///
  /// In en, this message translates to:
  /// **'New Notification'**
  String get newNotificationFallback;

  /// Auto-added
  ///
  /// In en, this message translates to:
  /// **'Today, {time}'**
  String todayAtLabel(String time);

  /// Auto-added
  ///
  /// In en, this message translates to:
  /// **'Yesterday, {time}'**
  String yesterdayAtLabel(String time);

  /// Title of the bottom sheet where the student picks which video player to use
  ///
  /// In en, this message translates to:
  /// **'SELECT PLAYER'**
  String get selectPlayerTitle;

  /// Message shown when no video players are enabled for a course
  ///
  /// In en, this message translates to:
  /// **'No active players available.'**
  String get noActivePlayersAvailable;

  /// Title of the bottom sheet where the student picks a video quality to download
  ///
  /// In en, this message translates to:
  /// **'SELECT DOWNLOAD QUALITY'**
  String get selectDownloadQualityTitle;

  /// Snackbar shown when a video or PDF download begins
  ///
  /// In en, this message translates to:
  /// **'Download Started...'**
  String get downloadStartedMessage;

  /// Snackbar shown when a video or PDF download finishes successfully
  ///
  /// In en, this message translates to:
  /// **'Download Completed!'**
  String get downloadCompletedMessage;

  /// Snackbar shown when a video or PDF download fails
  ///
  /// In en, this message translates to:
  /// **'Download Failed'**
  String get downloadFailedMessage;

  /// Snackbar shown when a PDF download begins
  ///
  /// In en, this message translates to:
  /// **'PDF Download Started...'**
  String get pdfDownloadStartedMessage;

  /// Snackbar shown when a PDF download finishes successfully
  ///
  /// In en, this message translates to:
  /// **'PDF Download Completed!'**
  String get pdfDownloadCompletedMessage;

  /// Plain tab label (no count) for the videos tab on the chapter contents screen
  ///
  /// In en, this message translates to:
  /// **'Videos'**
  String get videosTabLabel;

  /// Plain tab label (no count) for the PDFs tab on the chapter contents screen
  ///
  /// In en, this message translates to:
  /// **'PDFs'**
  String get pdfsTabLabel;

  /// Empty state message when a chapter has no video lessons
  ///
  /// In en, this message translates to:
  /// **'No video lessons'**
  String get noVideoLessonsMessage;

  /// Empty state message when a chapter has no PDF files
  ///
  /// In en, this message translates to:
  /// **'No PDF files'**
  String get noPdfFilesMessage;

  /// Small label tag shown next to a video lesson's duration
  ///
  /// In en, this message translates to:
  /// **'VIDEO'**
  String get videoLabel;

  /// Small label tag shown under a PDF document's title
  ///
  /// In en, this message translates to:
  /// **'STUDY MATERIAL'**
  String get studyMaterialLabel;

  /// Notice shown to a teacher when a video is still being encoded and cannot be watched or downloaded yet
  ///
  /// In en, this message translates to:
  /// **'Playback and download will be available once video processing is complete'**
  String get videoProcessingNotice;

  /// Button label to start watching a video lesson
  ///
  /// In en, this message translates to:
  /// **'Watch Now'**
  String get watchNowButton;

  /// Button label to open a PDF document
  ///
  /// In en, this message translates to:
  /// **'Open File'**
  String get openFileButton;

  /// Button label to download a video or PDF
  ///
  /// In en, this message translates to:
  /// **'Download'**
  String get downloadButton;

  /// Status label shown when a video or PDF has already been downloaded
  ///
  /// In en, this message translates to:
  /// **'SAVED'**
  String get savedLabel;

  /// Status label shown while a download is in progress
  ///
  /// In en, this message translates to:
  /// **'PROCESSING...'**
  String get processingLabel;

  /// Status label shown when downloading has been disabled for this content
  ///
  /// In en, this message translates to:
  /// **'DOWNLOAD DISABLED'**
  String get downloadDisabledLabel;

  /// Error snackbar shown when refreshing a video's encoding status fails
  ///
  /// In en, this message translates to:
  /// **'Failed to refresh video status'**
  String get videoStatusRefreshFailed;

  /// Badge label for a video that is currently being encoded on the streaming backend
  ///
  /// In en, this message translates to:
  /// **'Encoding'**
  String get encodingStatusEncoding;

  /// Badge label for a video that has finished encoding and is ready to watch
  ///
  /// In en, this message translates to:
  /// **'Ready'**
  String get encodingStatusReady;

  /// Badge label for a video that is queued and waiting to be encoded
  ///
  /// In en, this message translates to:
  /// **'Waiting to process'**
  String get encodingStatusWaiting;

  /// Label shown on the encoding-status badge while it is being manually refreshed
  ///
  /// In en, this message translates to:
  /// **'Updating'**
  String get updatingLabel;

  /// Error snackbar shown when a link fails to open in the browser/app
  ///
  /// In en, this message translates to:
  /// **'Could not launch link'**
  String get couldNotLaunchLink;

  /// Snackbar shown after copying a value (wallet number, link) to the clipboard
  ///
  /// In en, this message translates to:
  /// **'Copied to clipboard'**
  String get copiedToClipboard;

  /// Validation error shown when the student tries to submit checkout without a receipt screenshot
  ///
  /// In en, this message translates to:
  /// **'Please upload the payment receipt image'**
  String get pleaseUploadReceiptImage;

  /// Title of the confirmation dialog shown after a purchase request is submitted
  ///
  /// In en, this message translates to:
  /// **'REQUEST SENT'**
  String get requestSentTitle;

  /// Body text of the confirmation dialog shown after a purchase request is submitted
  ///
  /// In en, this message translates to:
  /// **'We have received your request.\nYou will be notified once approved.'**
  String get requestReceivedMessage;

  /// Fallback error message shown when submitting a purchase request fails
  ///
  /// In en, this message translates to:
  /// **'Failed to send request'**
  String get failedToSendRequest;

  /// Title of the checkout screen
  ///
  /// In en, this message translates to:
  /// **'CHECKOUT'**
  String get checkoutTitle;

  /// Label above the total payable amount on the checkout screen
  ///
  /// In en, this message translates to:
  /// **'TOTAL AMOUNT'**
  String get totalAmountLabel;

  /// Snackbar shown when a discount code is applied successfully
  ///
  /// In en, this message translates to:
  /// **'Discount code applied successfully!'**
  String get discountCodeAppliedSuccess;

  /// Fallback error message shown when a discount code fails validation
  ///
  /// In en, this message translates to:
  /// **'Invalid or already-used discount code.'**
  String get discountCodeInvalid;

  /// Label above the discount code input field on checkout
  ///
  /// In en, this message translates to:
  /// **'DISCOUNT CODE'**
  String get discountCodeLabel;

  /// Hint text inside the discount code input field
  ///
  /// In en, this message translates to:
  /// **'Enter code here'**
  String get enterCodeHint;

  /// Button label to apply a discount code
  ///
  /// In en, this message translates to:
  /// **'APPLY'**
  String get applyButton;

  /// Section header listing cash wallet payment numbers on checkout
  ///
  /// In en, this message translates to:
  /// **'CASH WALLETS'**
  String get cashWalletsLabel;

  /// Label on a card showing a cash wallet number
  ///
  /// In en, this message translates to:
  /// **'WALLET NUMBER'**
  String get walletNumberLabel;

  /// Section header listing InstaPay phone numbers on checkout
  ///
  /// In en, this message translates to:
  /// **'INSTAPAY NUMBERS'**
  String get instapayNumbersLabel;

  /// Label on a card showing an InstaPay phone number
  ///
  /// In en, this message translates to:
  /// **'INSTAPAY PHONE'**
  String get instapayPhoneLabel;

  /// Section header listing InstaPay payment links on checkout
  ///
  /// In en, this message translates to:
  /// **'INSTAPAY LINKS / USERNAME'**
  String get instapayLinksLabel;

  /// Message shown when no payment methods are configured for checkout
  ///
  /// In en, this message translates to:
  /// **'Payment methods unavailable'**
  String get paymentMethodsUnavailable;

  /// Secondary message shown alongside the payment-methods-unavailable notice
  ///
  /// In en, this message translates to:
  /// **'Please contact support or try again later.'**
  String get contactSupportOrRetryLater;

  /// Label above the receipt screenshot upload box on checkout
  ///
  /// In en, this message translates to:
  /// **'UPLOAD RECEIPT'**
  String get uploadReceiptLabel;

  /// Placeholder text inside the empty receipt upload box
  ///
  /// In en, this message translates to:
  /// **'Tap to upload screenshot'**
  String get tapToUploadScreenshot;

  /// Label above the optional notes field on checkout
  ///
  /// In en, this message translates to:
  /// **'NOTES (OPTIONAL)'**
  String get notesOptionalLabel;

  /// Hint text inside the optional checkout notes field
  ///
  /// In en, this message translates to:
  /// **'Add any notes...'**
  String get addNotesHint;

  /// Button label to submit the checkout/payment request
  ///
  /// In en, this message translates to:
  /// **'CONFIRM PAYMENT'**
  String get confirmPaymentButton;

  /// Tooltip on a button that copies a value to the clipboard
  ///
  /// In en, this message translates to:
  /// **'Copy'**
  String get copyTooltip;

  /// Button label to open an InstaPay payment link
  ///
  /// In en, this message translates to:
  /// **'Open Link / InstaPay'**
  String get openLinkInstapayButton;

  /// Notice shown when profile data couldn't be refreshed from the server and a cached copy is shown instead
  ///
  /// In en, this message translates to:
  /// **'Could not fetch latest data, showing cached version.'**
  String get couldNotFetchLatestData;

  /// Snackbar shown after the profile is saved successfully
  ///
  /// In en, this message translates to:
  /// **'Profile Updated Successfully'**
  String get profileUpdatedSuccess;

  /// Fallback error message shown when saving profile changes fails
  ///
  /// In en, this message translates to:
  /// **'Failed to update profile'**
  String get failedToUpdateProfile;

  /// Title of the edit profile screen
  ///
  /// In en, this message translates to:
  /// **'EDIT PROFILE'**
  String get editProfileTitle;

  /// Hint under the profile photo on the edit profile screen
  ///
  /// In en, this message translates to:
  /// **'Tap to change photo'**
  String get tapToChangePhoto;

  /// Hint text for the full name field on the edit profile screen
  ///
  /// In en, this message translates to:
  /// **'Enter your full name'**
  String get editFullNameHint;

  /// Validation error when the full name field is left empty
  ///
  /// In en, this message translates to:
  /// **'Name is required'**
  String get nameRequiredValidation;

  /// Label for the phone number field on the edit profile screen
  ///
  /// In en, this message translates to:
  /// **'Phone Number'**
  String get phoneNumberLabel;

  /// Validation error when the phone number is too short
  ///
  /// In en, this message translates to:
  /// **'Invalid phone number'**
  String get invalidPhoneNumberValidation;

  /// Label for the username field on the edit profile screen
  ///
  /// In en, this message translates to:
  /// **'Username'**
  String get usernameLabel;

  /// Hint text for the username field on the edit profile screen
  ///
  /// In en, this message translates to:
  /// **'English letters & numbers only'**
  String get usernameEnglishNumbersOnlyHint;

  /// Validation error when the username field is left empty
  ///
  /// In en, this message translates to:
  /// **'Username is required'**
  String get usernameRequiredValidation;

  /// Validation error when the username contains invalid characters
  ///
  /// In en, this message translates to:
  /// **'Only English letters & numbers allowed (No spaces)'**
  String get usernameInvalidCharsValidation;

  /// Section header for teacher-specific fields on the edit profile screen
  ///
  /// In en, this message translates to:
  /// **'TEACHER INFO'**
  String get teacherInfoLabel;

  /// Label for the teacher's specialty/job title field
  ///
  /// In en, this message translates to:
  /// **'Specialty / Job Title'**
  String get specialtyJobTitleLabel;

  /// Hint text for the teacher's specialty/job title field
  ///
  /// In en, this message translates to:
  /// **'e.g. Physics Teacher'**
  String get specialtyHint;

  /// Label for the teacher's WhatsApp number field
  ///
  /// In en, this message translates to:
  /// **'WhatsApp Number (For Students)'**
  String get whatsappNumberLabel;

  /// Hint text for the teacher's WhatsApp number field
  ///
  /// In en, this message translates to:
  /// **'201xxxxxxxxx'**
  String get whatsappNumberHint;

  /// Helper text explaining the expected WhatsApp number format
  ///
  /// In en, this message translates to:
  /// **'Enter number with country code without \'+\' (e.g. 201xxxxxxxxx)'**
  String get whatsappNumberNotice;

  /// Label for the teacher's bio field
  ///
  /// In en, this message translates to:
  /// **'Bio / About Me'**
  String get bioAboutMeLabel;

  /// Hint text for the teacher's bio field
  ///
  /// In en, this message translates to:
  /// **'Tell students about yourself...'**
  String get bioHint;

  /// Section header for payment method fields on the edit profile screen
  ///
  /// In en, this message translates to:
  /// **'PAYMENT METHODS'**
  String get paymentMethodsLabel;

  /// Title above the dynamic list of cash wallet numbers
  ///
  /// In en, this message translates to:
  /// **'Cash Wallet Numbers'**
  String get cashWalletNumbersTitle;

  /// Hint text for a cash wallet number input field
  ///
  /// In en, this message translates to:
  /// **'Enter Wallet Number'**
  String get enterWalletNumberHint;

  /// Title above the dynamic list of InstaPay phone numbers
  ///
  /// In en, this message translates to:
  /// **'InstaPay Numbers'**
  String get instapayNumbersTitle;

  /// Hint text for an InstaPay phone number input field
  ///
  /// In en, this message translates to:
  /// **'Enter InstaPay Phone Number'**
  String get enterInstapayPhoneHint;

  /// Title above the dynamic list of InstaPay links/usernames
  ///
  /// In en, this message translates to:
  /// **'InstaPay Links / Usernames'**
  String get instapayLinksUsernamesTitle;

  /// Hint text for an InstaPay link/username input field
  ///
  /// In en, this message translates to:
  /// **'username@instapay or Link'**
  String get instapayLinkHint;

  /// Button label to save profile changes
  ///
  /// In en, this message translates to:
  /// **'SAVE CHANGES'**
  String get saveChangesButton;

  /// Helper text shown when a dynamic payment-method list is empty
  ///
  /// In en, this message translates to:
  /// **'Click + to add a number/link'**
  String get clickPlusToAddHint;

  /// Fallback error message shown when an exam attempt fails to start
  ///
  /// In en, this message translates to:
  /// **'Failed to start exam'**
  String get failedToStartExam;

  /// Fallback error message shown when access to an exam is denied
  ///
  /// In en, this message translates to:
  /// **'Access Denied'**
  String get accessDeniedFallback;

  /// Message shown when the student tries to retake an already-completed exam
  ///
  /// In en, this message translates to:
  /// **'Exam already completed'**
  String get examAlreadyCompleted;

  /// Warning shown when the student tries to submit an exam with unanswered questions
  ///
  /// In en, this message translates to:
  /// **'Cannot submit yet. You have {count} unanswered questions!'**
  String cannotSubmitUnanswered(int count);

  /// Error message shown when submitting an exam attempt fails
  ///
  /// In en, this message translates to:
  /// **'Failed to submit. Try again.'**
  String get failedToSubmitTryAgain;

  /// Title of the confirmation dialog shown when leaving the exam screen
  ///
  /// In en, this message translates to:
  /// **'Exit Exam?'**
  String get exitExamTitle;

  /// Body text of the exit-exam confirmation dialog
  ///
  /// In en, this message translates to:
  /// **'Leaving the exam screen now will AUTOMATICALLY SUBMIT your current answers and you cannot return.\n\nAre you sure?'**
  String get exitExamWarningMessage;

  /// Button label to cancel exiting the exam and remain on the screen
  ///
  /// In en, this message translates to:
  /// **'Stay'**
  String get stayButton;

  /// Button label to submit the exam and leave the screen
  ///
  /// In en, this message translates to:
  /// **'Submit & Exit'**
  String get submitAndExitButton;

  /// Placeholder shown when an essay question has no model answer set
  ///
  /// In en, this message translates to:
  /// **'No model answer provided.'**
  String get noModelAnswerProvided;

  /// Instruction shown above the text field for an essay/written exam question
  ///
  /// In en, this message translates to:
  /// **'Written Question — Type your answer below'**
  String get writtenQuestionInstructions;

  /// Hint text inside the essay answer text field
  ///
  /// In en, this message translates to:
  /// **'Write your answer here...'**
  String get writeAnswerHint;

  /// Character count shown below an essay answer field
  ///
  /// In en, this message translates to:
  /// **'{count} characters'**
  String charactersCountLabel(int count);

  /// Tooltip on the flag button to mark a question for review
  ///
  /// In en, this message translates to:
  /// **'Mark Question'**
  String get markQuestionTooltip;

  /// Header showing the current question number out of the total
  ///
  /// In en, this message translates to:
  /// **'Q {current}/{total}'**
  String questionCounterLabel(int current, int total);

  /// Badge shown when viewing an exam in model-answer review mode
  ///
  /// In en, this message translates to:
  /// **'MODEL ANSWER'**
  String get modelAnswerLabel;

  /// Small badge marking an essay/written question
  ///
  /// In en, this message translates to:
  /// **'WRITTEN QUESTION'**
  String get writtenQuestionBadge;

  /// Fallback text if a question's text is missing
  ///
  /// In en, this message translates to:
  /// **'Question Text'**
  String get questionTextFallback;

  /// Button label to go to the previous exam question
  ///
  /// In en, this message translates to:
  /// **'BACK'**
  String get backButton;

  /// Button label to close the exam when in model-answer review mode
  ///
  /// In en, this message translates to:
  /// **'CLOSE'**
  String get examCloseButton;

  /// Button label to finish and submit the exam on the last question
  ///
  /// In en, this message translates to:
  /// **'FINISH'**
  String get examFinishButton;

  /// Button label to move to the next exam question
  ///
  /// In en, this message translates to:
  /// **'NEXT'**
  String get examNextButton;

  /// Fallback shown for an essay question the student left blank
  ///
  /// In en, this message translates to:
  /// **'(No answer submitted)'**
  String get noAnswerSubmittedFallback;

  /// Short badge marking an essay question on the exam results screen
  ///
  /// In en, this message translates to:
  /// **'WRITTEN'**
  String get writtenBadgeShort;

  /// Header showing a question's position in the exam
  ///
  /// In en, this message translates to:
  /// **'Question {number}'**
  String questionNumberLabel(int number);

  /// Score shown for a graded essay question
  ///
  /// In en, this message translates to:
  /// **'{earned} / {max} pts'**
  String pointsScoredLabel(int earned, int max);

  /// Score placeholder shown for an essay question that hasn't been graded yet
  ///
  /// In en, this message translates to:
  /// **'— / {max} pts'**
  String pointsPendingLabel(int max);

  /// Label above the student's submitted answer on the exam results screen
  ///
  /// In en, this message translates to:
  /// **'YOUR ANSWER'**
  String get yourAnswerLabel;

  /// Label above the teacher's written feedback on a graded essay question
  ///
  /// In en, this message translates to:
  /// **'TEACHER FEEDBACK'**
  String get teacherFeedbackLabel;

  /// Error message shown when exam results fail to load
  ///
  /// In en, this message translates to:
  /// **'Failed to load results'**
  String get failedToLoadResults;

  /// Title shown when an exam has been submitted but not yet graded
  ///
  /// In en, this message translates to:
  /// **'Awaiting Teacher Review'**
  String get awaitingTeacherReview;

  /// Body text shown while an exam attempt awaits teacher grading
  ///
  /// In en, this message translates to:
  /// **'Your exam has been submitted and is being reviewed by your teacher. You will be notified once grading is complete.'**
  String get examUnderReviewMessage;

  /// Button label to return to the course from the exam results screen
  ///
  /// In en, this message translates to:
  /// **'BACK TO COURSE'**
  String get backToCourseButton;

  /// Status label shown when the student passed the exam
  ///
  /// In en, this message translates to:
  /// **'PASSED'**
  String get examPassedLabel;

  /// Status label shown when the student failed the exam
  ///
  /// In en, this message translates to:
  /// **'FAILED'**
  String get examFailedLabel;

  /// App bar title when viewing results of a practice exam attempt
  ///
  /// In en, this message translates to:
  /// **'PRACTICE RESULT'**
  String get practiceResultTitle;

  /// App bar title when viewing results of a graded exam attempt
  ///
  /// In en, this message translates to:
  /// **'EXAM RESULTS'**
  String get examResultsTitle;

  /// Notice shown on practice-mode exam results explaining the score isn't recorded
  ///
  /// In en, this message translates to:
  /// **'This is a practice result (Practice Mode). This result has not been saved to your permanent grade record.'**
  String get practiceModeNotice;

  /// Section header above the per-question breakdown on the exam results screen
  ///
  /// In en, this message translates to:
  /// **'DETAILED ANALYSIS'**
  String get detailedAnalysisLabel;

  /// Notice shown when an exam has essay questions still awaiting a grade
  ///
  /// In en, this message translates to:
  /// **'Written questions pending grading'**
  String get writtenQuestionsPendingGrading;

  /// Snackbar shown when the WhatsApp link fails to open
  ///
  /// In en, this message translates to:
  /// **'Could not open WhatsApp'**
  String get couldNotOpenWhatsapp;

  /// Error message shown when a teacher profile fails to load
  ///
  /// In en, this message translates to:
  /// **'Error loading profile'**
  String get errorLoadingProfile;

  /// Button label to open a WhatsApp chat with the teacher
  ///
  /// In en, this message translates to:
  /// **'Chat on WhatsApp'**
  String get chatOnWhatsapp;

  /// Fallback text when a teacher has not provided a bio
  ///
  /// In en, this message translates to:
  /// **'No bio available.'**
  String get noBioAvailable;

  /// Section header listing a teacher's available courses
  ///
  /// In en, this message translates to:
  /// **'AVAILABLE COURSES'**
  String get availableCoursesLabel;

  /// Generic fallback title when an item has no title
  ///
  /// In en, this message translates to:
  /// **'Untitled'**
  String get untitledFallback;

  /// Button to close the video player after a security violation
  ///
  /// In en, this message translates to:
  /// **'CLOSE PLAYER'**
  String get closePlayer;

  /// Dialog title for the delete-account confirmation
  ///
  /// In en, this message translates to:
  /// **'Delete Account'**
  String get deleteAccountTitle;

  /// Body text of the delete-account confirmation dialog
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to delete your account? This action cannot be undone and you will lose all your subscriptions.'**
  String get deleteAccountConfirmMessage;

  /// Snackbar shown after successfully deleting the account
  ///
  /// In en, this message translates to:
  /// **'Account deleted successfully.'**
  String get accountDeletedSuccessfully;

  /// Snackbar shown when account deletion fails
  ///
  /// In en, this message translates to:
  /// **'Error deleting account: {error}'**
  String errorDeletingAccount(String error);

  /// Title of the video player settings bottom sheet
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settingsTitle;

  /// Label showing the currently selected video quality
  ///
  /// In en, this message translates to:
  /// **'Quality: {quality}'**
  String qualityLabel(String quality);

  /// Label showing the currently selected playback speed
  ///
  /// In en, this message translates to:
  /// **'Speed: {speed}x'**
  String speedLabel(String speed);

  /// Countdown shown before video playback starts
  ///
  /// In en, this message translates to:
  /// **'Starting in {seconds}'**
  String startingInCountdown(String seconds);

  /// Status text shown while the video stream is stabilizing before playback
  ///
  /// In en, this message translates to:
  /// **'Video Ready - Stabilizing Stream...'**
  String get videoReadyStabilizing;

  /// Heading shown on the full-screen security alert overlay during video playback
  ///
  /// In en, this message translates to:
  /// **'SECURITY ALERT'**
  String get securityAlertTitle;

  /// Message shown when screen recording is detected during video playback
  ///
  /// In en, this message translates to:
  /// **'Screen Recording Detected.\nPlayback has been disabled.'**
  String get screenRecordingDetectedMessage;

  /// Heading for the final warning shown after a recording violation
  ///
  /// In en, this message translates to:
  /// **'⚠️ Final Warning'**
  String get finalWarningTitle;

  /// Detailed warning message shown after a recording violation
  ///
  /// In en, this message translates to:
  /// **'Recording content violates the terms of use.\nRepeating this will permanently ban your account and delete all your data.'**
  String get contentRecordingViolationMessage;

  /// PDF annotation tool: pen
  ///
  /// In en, this message translates to:
  /// **'Pen'**
  String get pdfToolPen;

  /// PDF annotation tool: text highlighter
  ///
  /// In en, this message translates to:
  /// **'Highlight Text'**
  String get pdfToolHighlightText;

  /// PDF annotation tool: freehand highlighter
  ///
  /// In en, this message translates to:
  /// **'Freehand Highlight'**
  String get pdfToolFreehandHighlight;

  /// PDF annotation tool: eraser
  ///
  /// In en, this message translates to:
  /// **'Eraser'**
  String get pdfToolEraser;

  /// PDF annotation tool: comment
  ///
  /// In en, this message translates to:
  /// **'Comment'**
  String get pdfToolComment;

  /// PDF annotation tool: underline
  ///
  /// In en, this message translates to:
  /// **'Underline'**
  String get pdfToolUnderline;

  /// PDF annotation tool: text
  ///
  /// In en, this message translates to:
  /// **'Text'**
  String get pdfToolText;

  /// PDF annotation tool: shapes
  ///
  /// In en, this message translates to:
  /// **'Shapes'**
  String get pdfToolShapes;

  /// PDF annotation tool: image
  ///
  /// In en, this message translates to:
  /// **'Image'**
  String get pdfToolImage;

  /// Tooltip for the undo button in the PDF annotation toolbar
  ///
  /// In en, this message translates to:
  /// **'Undo'**
  String get undoTooltip;

  /// Tooltip when palm rejection is enabled
  ///
  /// In en, this message translates to:
  /// **'Palm Rejection: On'**
  String get palmRejectionOn;

  /// Tooltip when palm rejection is disabled
  ///
  /// In en, this message translates to:
  /// **'Palm Rejection: Off'**
  String get palmRejectionOff;

  /// Label for the bold text toggle in PDF text annotation panel
  ///
  /// In en, this message translates to:
  /// **'Bold'**
  String get boldLabel;

  /// Label for the underline text toggle in PDF text annotation panel
  ///
  /// In en, this message translates to:
  /// **'Underline'**
  String get underlineLabel;

  /// Label for the shape border color picker
  ///
  /// In en, this message translates to:
  /// **'Border: '**
  String get borderLabel;

  /// Label for the shape fill color picker
  ///
  /// In en, this message translates to:
  /// **'Fill: '**
  String get fillLabel;

  /// Title of the custom color picker dialog
  ///
  /// In en, this message translates to:
  /// **'Choose a Color'**
  String get chooseColorTitle;

  /// Label for the saturation slider in the color picker
  ///
  /// In en, this message translates to:
  /// **'Saturation'**
  String get saturationLabel;

  /// Label for the brightness slider in the color picker
  ///
  /// In en, this message translates to:
  /// **'Brightness'**
  String get brightnessLabel;

  /// Confirm button in the custom color picker dialog
  ///
  /// In en, this message translates to:
  /// **'Select'**
  String get selectAction;

  /// Snackbar shown when video protection setup fails
  ///
  /// In en, this message translates to:
  /// **'Warning: Some protection features may not work'**
  String get protectionFeaturesWarning;

  /// Title of the recording-detected security warning dialog
  ///
  /// In en, this message translates to:
  /// **'⚠️ Security Warning'**
  String get securityWarningTitle;

  /// Main message of the recording-detected security warning dialog
  ///
  /// In en, this message translates to:
  /// **'An audio recording attempt was detected!'**
  String get audioRecordingDetectedMessage;

  /// Bulleted consequences list in the recording-detected security warning dialog
  ///
  /// In en, this message translates to:
  /// **'• Playback has been stopped automatically\n• Recording violates intellectual property rights\n• Your account may be suspended'**
  String get recordingConsequencesMessage;

  /// Button to exit the video player after a recording warning
  ///
  /// In en, this message translates to:
  /// **'Exit'**
  String get exitAction;

  /// Small badge label shown when video protection is active
  ///
  /// In en, this message translates to:
  /// **'Protected'**
  String get protectedBadge;

  /// Title shown on the full-screen overlay when screen recording is detected
  ///
  /// In en, this message translates to:
  /// **'Recording Detected!'**
  String get recordingDetectedTitle;

  /// Message shown on the full-screen overlay when screen recording is detected
  ///
  /// In en, this message translates to:
  /// **'Playback has been stopped'**
  String get playbackStoppedMessage;

  /// Loading message while verifying a PDF file
  ///
  /// In en, this message translates to:
  /// **'Verifying file...'**
  String get verifyingFileMessage;

  /// Loading message while initializing PDF protection
  ///
  /// In en, this message translates to:
  /// **'Initializing protection...'**
  String get initializingProtectionMessage;

  /// Loading message while downloading a PDF directly
  ///
  /// In en, this message translates to:
  /// **'Downloading directly...'**
  String get directDownloadMessage;

  /// Error message when a protected PDF fails to open
  ///
  /// In en, this message translates to:
  /// **'Failed to open the protected file.'**
  String get failedOpenProtectedFile;

  /// Title of the PDF page index drawer
  ///
  /// In en, this message translates to:
  /// **'Page Index'**
  String get pageIndexTitle;

  /// Label for a page entry in the PDF page index drawer
  ///
  /// In en, this message translates to:
  /// **'Page {number}'**
  String pageNumberLabel(String number);

  /// Context-menu button label to highlight selected PDF text
  ///
  /// In en, this message translates to:
  /// **'Highlight'**
  String get highlightLabel;

  /// Context-menu button label to underline selected PDF text
  ///
  /// In en, this message translates to:
  /// **'Underline'**
  String get underlineActionLabel;

  /// Generic edit button label in the PDF viewer context menu
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get editAction;

  /// Snackbar shown when no markup is found in the current text selection
  ///
  /// In en, this message translates to:
  /// **'No highlight or underline in this selection'**
  String get noMarkupInSelectionMessage;

  /// Title of the edit sheet for an existing highlight
  ///
  /// In en, this message translates to:
  /// **'Edit Highlight'**
  String get editHighlightTitle;

  /// Title of the edit sheet for an existing underline
  ///
  /// In en, this message translates to:
  /// **'Edit Underline'**
  String get editUnderlineTitle;

  /// Button to delete an existing highlight
  ///
  /// In en, this message translates to:
  /// **'Delete Highlight'**
  String get deleteHighlightLabel;

  /// Button to delete an existing underline
  ///
  /// In en, this message translates to:
  /// **'Delete Underline'**
  String get deleteUnderlineLabel;

  /// Title of the edit sheet for an existing shape annotation
  ///
  /// In en, this message translates to:
  /// **'Edit Shape'**
  String get editShapeTitle;

  /// Button to delete an existing shape annotation
  ///
  /// In en, this message translates to:
  /// **'Delete Shape'**
  String get deleteShapeLabel;

  /// Title of the dialog when adding a new comment annotation
  ///
  /// In en, this message translates to:
  /// **'Add Comment'**
  String get addCommentTitle;

  /// Title of the dialog when viewing/editing an existing comment annotation
  ///
  /// In en, this message translates to:
  /// **'Comment'**
  String get commentTitle;

  /// Hint text for the comment text field when editing is enabled
  ///
  /// In en, this message translates to:
  /// **'Write your notes here...'**
  String get writeNotesHint;

  /// Hint text for the comment text field when editing is disabled
  ///
  /// In en, this message translates to:
  /// **'No text...'**
  String get noTextHint;

  /// Label showing the current comment icon scale
  ///
  /// In en, this message translates to:
  /// **'Icon Size: {size}'**
  String iconSizeLabel(String size);

  /// Label showing the current comment opacity percentage
  ///
  /// In en, this message translates to:
  /// **'Opacity: {percent}%'**
  String opacityLabel(String percent);

  /// Snackbar confirming comment defaults were saved
  ///
  /// In en, this message translates to:
  /// **'Default settings saved'**
  String get defaultSettingsSaved;

  /// Button to save current comment style as the default
  ///
  /// In en, this message translates to:
  /// **'Save as Default'**
  String get saveAsDefaultLabel;

  /// Placeholder text shown in the live text-annotation preview before typing
  ///
  /// In en, this message translates to:
  /// **'Text preview...'**
  String get textPreviewPlaceholder;

  /// Hint text for the text-annotation input field
  ///
  /// In en, this message translates to:
  /// **'Write text here...'**
  String get writeTextHint;

  /// Snackbar shown when fetching exam statistics fails
  ///
  /// In en, this message translates to:
  /// **'Failed to fetch statistics: {error}'**
  String failedFetchStats(String error);

  /// AppBar title showing statistics for a specific exam
  ///
  /// In en, this message translates to:
  /// **'Statistics: {examTitle}'**
  String statisticsForTitle(String examTitle);

  /// Stat card label for total exam attempt count
  ///
  /// In en, this message translates to:
  /// **'Number of Attempts'**
  String get numberOfAttemptsLabel;

  /// Stat card label for average exam percentage
  ///
  /// In en, this message translates to:
  /// **'Average Percentage'**
  String get averagePercentageLabel;

  /// Section heading for the top-10 students leaderboard
  ///
  /// In en, this message translates to:
  /// **'Honor Roll (Top 10)'**
  String get honorRollTitle;

  /// Empty state message when no students have completed the exam
  ///
  /// In en, this message translates to:
  /// **'No completed attempts yet'**
  String get noCompletedAttemptsYet;

  /// Fallback name when a student's name is missing
  ///
  /// In en, this message translates to:
  /// **'Unknown Student'**
  String get unknownStudentFallback;

  /// Generic fallback when a value is not available
  ///
  /// In en, this message translates to:
  /// **'Not available'**
  String get notAvailable;

  /// Score shown with a points suffix
  ///
  /// In en, this message translates to:
  /// **'{score} pts'**
  String pointsSuffix(String score);

  /// Video player error message shown on a network/streaming failure
  ///
  /// In en, this message translates to:
  /// **'A network connection problem occurred.\nPlease check your internet connection and try again.'**
  String get networkConnectionProblemMessage;

  /// Video player error message shown when player initialization fails
  ///
  /// In en, this message translates to:
  /// **'Failed to initialize the player: {error}'**
  String playerInitFailedMessage(String error);

  /// Video player error message shown when the video fails to load
  ///
  /// In en, this message translates to:
  /// **'Failed to load the video.'**
  String get videoLoadFailedMessage;

  /// Video player error message shown when no quality streams are available
  ///
  /// In en, this message translates to:
  /// **'No sources available for this video.'**
  String get noSourcesAvailableMessage;

  /// Label for the dark mode toggle menu item
  ///
  /// In en, this message translates to:
  /// **'Dark Mode'**
  String get darkModeLabel;

  /// Label for the light mode toggle menu item
  ///
  /// In en, this message translates to:
  /// **'Light Mode'**
  String get lightModeLabel;

  /// No description provided for @failedLoadExamDetails.
  ///
  /// In en, this message translates to:
  /// **'Failed to load exam data: {error}'**
  String failedLoadExamDetails(String error);

  /// No description provided for @startDateAfterEndError.
  ///
  /// In en, this message translates to:
  /// **'The start date cannot be after the end date!'**
  String get startDateAfterEndError;

  /// No description provided for @endDateBeforeStartError.
  ///
  /// In en, this message translates to:
  /// **'The end date cannot be before the start date!'**
  String get endDateBeforeStartError;

  /// No description provided for @deleteExamTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete Exam'**
  String get deleteExamTitle;

  /// No description provided for @deleteExamConfirmMessage.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to delete this exam?\n\n⚠️ Warning: All questions and all student results linked to this exam will be permanently deleted.'**
  String get deleteExamConfirmMessage;

  /// No description provided for @permanentDeleteAction.
  ///
  /// In en, this message translates to:
  /// **'Delete Permanently'**
  String get permanentDeleteAction;

  /// No description provided for @examDeletedSuccessfully.
  ///
  /// In en, this message translates to:
  /// **'Exam deleted successfully'**
  String get examDeletedSuccessfully;

  /// No description provided for @deleteFailedMessage.
  ///
  /// In en, this message translates to:
  /// **'Delete failed: {error}'**
  String deleteFailedMessage(String error);

  /// No description provided for @atLeastOneQuestionRequired.
  ///
  /// In en, this message translates to:
  /// **'You must add at least one question'**
  String get atLeastOneQuestionRequired;

  /// No description provided for @selectExamStartEndTime.
  ///
  /// In en, this message translates to:
  /// **'Please set the exam start and end time'**
  String get selectExamStartEndTime;

  /// No description provided for @startTimeAfterEndError.
  ///
  /// In en, this message translates to:
  /// **'Error: start time is after end time!'**
  String get startTimeAfterEndError;

  /// No description provided for @examUpdatedSuccessfully.
  ///
  /// In en, this message translates to:
  /// **'Exam updated successfully'**
  String get examUpdatedSuccessfully;

  /// No description provided for @examCreatedSuccessfully.
  ///
  /// In en, this message translates to:
  /// **'Exam created successfully'**
  String get examCreatedSuccessfully;

  /// No description provided for @genericErrorOccurred.
  ///
  /// In en, this message translates to:
  /// **'An error occurred: {error}'**
  String genericErrorOccurred(String error);

  /// No description provided for @editExamTitle.
  ///
  /// In en, this message translates to:
  /// **'Edit Exam'**
  String get editExamTitle;

  /// No description provided for @createNewExamTitle.
  ///
  /// In en, this message translates to:
  /// **'Create New Exam'**
  String get createNewExamTitle;

  /// No description provided for @processingMessage.
  ///
  /// In en, this message translates to:
  /// **'Processing...'**
  String get processingMessage;

  /// No description provided for @examTitleLabel.
  ///
  /// In en, this message translates to:
  /// **'Exam Title'**
  String get examTitleLabel;

  /// No description provided for @examTitleHint.
  ///
  /// In en, this message translates to:
  /// **'Example: First-term comprehensive exam'**
  String get examTitleHint;

  /// No description provided for @requiredField.
  ///
  /// In en, this message translates to:
  /// **'Required'**
  String get requiredField;

  /// No description provided for @durationMinutesLabel.
  ///
  /// In en, this message translates to:
  /// **'Duration (minutes)'**
  String get durationMinutesLabel;

  /// No description provided for @durationHint.
  ///
  /// In en, this message translates to:
  /// **'Enter the exam duration'**
  String get durationHint;

  /// No description provided for @randomizeQuestionsTitle.
  ///
  /// In en, this message translates to:
  /// **'Randomize Question Order'**
  String get randomizeQuestionsTitle;

  /// No description provided for @randomizeQuestionsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Each student sees a different question order'**
  String get randomizeQuestionsSubtitle;

  /// No description provided for @randomizeOptionsTitle.
  ///
  /// In en, this message translates to:
  /// **'Randomize Option Order'**
  String get randomizeOptionsTitle;

  /// No description provided for @randomizeOptionsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Shuffle answer positions within each question'**
  String get randomizeOptionsSubtitle;

  /// No description provided for @allowRetakeTitle.
  ///
  /// In en, this message translates to:
  /// **'Allow Retake (Practice)'**
  String get allowRetakeTitle;

  /// No description provided for @allowRetakeSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Student can retake the exam without affecting their first score'**
  String get allowRetakeSubtitle;

  /// No description provided for @notifyStudentsTitle.
  ///
  /// In en, this message translates to:
  /// **'Notify Students'**
  String get notifyStudentsTitle;

  /// No description provided for @notifyStudentsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Send a notification to enrolled students when the exam starts'**
  String get notifyStudentsSubtitle;

  /// No description provided for @activationDateTimeLabel.
  ///
  /// In en, this message translates to:
  /// **'Activation Date & Time (Start)'**
  String get activationDateTimeLabel;

  /// No description provided for @startsAtLabel.
  ///
  /// In en, this message translates to:
  /// **'Starts: {date}'**
  String startsAtLabel(String date);

  /// No description provided for @tapToSetStart.
  ///
  /// In en, this message translates to:
  /// **'Tap to set the start'**
  String get tapToSetStart;

  /// No description provided for @closingDateTimeLabel.
  ///
  /// In en, this message translates to:
  /// **'Closing Date & Time (End)'**
  String get closingDateTimeLabel;

  /// No description provided for @endsAtLabel.
  ///
  /// In en, this message translates to:
  /// **'Ends: {date}'**
  String endsAtLabel(String date);

  /// No description provided for @tapToSetEnd.
  ///
  /// In en, this message translates to:
  /// **'Tap to set the end'**
  String get tapToSetEnd;

  /// No description provided for @questionsCountLabel.
  ///
  /// In en, this message translates to:
  /// **'Questions ({count})'**
  String questionsCountLabel(String count);

  /// No description provided for @addQuestionAction.
  ///
  /// In en, this message translates to:
  /// **'Add Question'**
  String get addQuestionAction;

  /// No description provided for @noQuestionsAddedYet.
  ///
  /// In en, this message translates to:
  /// **'No questions added yet'**
  String get noQuestionsAddedYet;

  /// No description provided for @essayBadge.
  ///
  /// In en, this message translates to:
  /// **'Essay'**
  String get essayBadge;

  /// No description provided for @essayQuestionSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Manual grading • Max score {score} • {imageStatus}'**
  String essayQuestionSubtitle(String score, String imageStatus);

  /// No description provided for @mcqQuestionSubtitle.
  ///
  /// In en, this message translates to:
  /// **'{count} options • {imageStatus}'**
  String mcqQuestionSubtitle(String count, String imageStatus);

  /// No description provided for @newImageStatus.
  ///
  /// In en, this message translates to:
  /// **'New image'**
  String get newImageStatus;

  /// No description provided for @savedImageStatus.
  ///
  /// In en, this message translates to:
  /// **'Saved image'**
  String get savedImageStatus;

  /// No description provided for @textOnlyStatus.
  ///
  /// In en, this message translates to:
  /// **'Text only'**
  String get textOnlyStatus;

  /// No description provided for @saveChangesAction.
  ///
  /// In en, this message translates to:
  /// **'Save Changes'**
  String get saveChangesAction;

  /// No description provided for @saveAndPublishExamAction.
  ///
  /// In en, this message translates to:
  /// **'Save & Publish Exam'**
  String get saveAndPublishExamAction;

  /// No description provided for @newQuestionTitle.
  ///
  /// In en, this message translates to:
  /// **'New Question'**
  String get newQuestionTitle;

  /// No description provided for @editQuestionTitle.
  ///
  /// In en, this message translates to:
  /// **'Edit Question'**
  String get editQuestionTitle;

  /// No description provided for @questionTextLabel.
  ///
  /// In en, this message translates to:
  /// **'Question Text'**
  String get questionTextLabel;

  /// No description provided for @questionTypeLabel.
  ///
  /// In en, this message translates to:
  /// **'Question Type'**
  String get questionTypeLabel;

  /// No description provided for @mcqTypeOption.
  ///
  /// In en, this message translates to:
  /// **'Multiple Choice'**
  String get mcqTypeOption;

  /// No description provided for @essayTypeOption.
  ///
  /// In en, this message translates to:
  /// **'Essay (Manual Grading)'**
  String get essayTypeOption;

  /// No description provided for @newImageSelectedStatus.
  ///
  /// In en, this message translates to:
  /// **'New image selected'**
  String get newImageSelectedStatus;

  /// No description provided for @imageSavedPreviouslyStatus.
  ///
  /// In en, this message translates to:
  /// **'Image saved previously'**
  String get imageSavedPreviouslyStatus;

  /// No description provided for @noImageStatus.
  ///
  /// In en, this message translates to:
  /// **'No image'**
  String get noImageStatus;

  /// No description provided for @uploadChangeImageTooltip.
  ///
  /// In en, this message translates to:
  /// **'Upload/change image'**
  String get uploadChangeImageTooltip;

  /// No description provided for @deleteImageTooltip.
  ///
  /// In en, this message translates to:
  /// **'Delete image'**
  String get deleteImageTooltip;

  /// No description provided for @maxScoreForQuestionLabel.
  ///
  /// In en, this message translates to:
  /// **'Max score for this question:'**
  String get maxScoreForQuestionLabel;

  /// No description provided for @scoreLabel.
  ///
  /// In en, this message translates to:
  /// **'Score'**
  String get scoreLabel;

  /// No description provided for @essayInfoMessage.
  ///
  /// In en, this message translates to:
  /// **'The student will write their answer in a text box, which you\'ll need to grade manually after submission.'**
  String get essayInfoMessage;

  /// No description provided for @modelAnswerOptionalLabel.
  ///
  /// In en, this message translates to:
  /// **'Model Answer (optional):'**
  String get modelAnswerOptionalLabel;

  /// No description provided for @modelAnswerHint.
  ///
  /// In en, this message translates to:
  /// **'Write the model answer here for the student to see after the result is shown...'**
  String get modelAnswerHint;

  /// No description provided for @modelAnswerInfoMessage.
  ///
  /// In en, this message translates to:
  /// **'This answer will be shown to the student on the result/review screen after grading, as a reference to compare with their own answer.'**
  String get modelAnswerInfoMessage;

  /// No description provided for @optionsSelectCorrectLabel.
  ///
  /// In en, this message translates to:
  /// **'Options (select the correct one):'**
  String get optionsSelectCorrectLabel;

  /// No description provided for @addOptionAction.
  ///
  /// In en, this message translates to:
  /// **'Add Option'**
  String get addOptionAction;

  /// No description provided for @optionNumberLabel.
  ///
  /// In en, this message translates to:
  /// **'Option {number}'**
  String optionNumberLabel(String number);

  /// No description provided for @deleteOptionTooltip.
  ///
  /// In en, this message translates to:
  /// **'Delete option'**
  String get deleteOptionTooltip;

  /// No description provided for @saveQuestionAction.
  ///
  /// In en, this message translates to:
  /// **'Save Question'**
  String get saveQuestionAction;

  /// No description provided for @minTwoOptionsRequired.
  ///
  /// In en, this message translates to:
  /// **'The question must have at least two options'**
  String get minTwoOptionsRequired;

  /// No description provided for @maxScoreRequiredForEssay.
  ///
  /// In en, this message translates to:
  /// **'You must set a max score for the essay question'**
  String get maxScoreRequiredForEssay;

  /// No description provided for @fillAllOptionsOrDelete.
  ///
  /// In en, this message translates to:
  /// **'Please fill in all option fields or delete the empty ones'**
  String get fillAllOptionsOrDelete;

  /// Snackbar shown when fetching the teacher's financial statistics fails
  ///
  /// In en, this message translates to:
  /// **'Error: {error}'**
  String errorFetchingFinancialStats(String error);

  /// AppBar title of the teacher's financial statistics screen
  ///
  /// In en, this message translates to:
  /// **'Statistics & Earnings'**
  String get financialStatsTitle;

  /// Summary card label for total unique students count
  ///
  /// In en, this message translates to:
  /// **'Total Students'**
  String get totalStudentsLabel;

  /// Summary card label for total earnings
  ///
  /// In en, this message translates to:
  /// **'Total Earnings'**
  String get totalEarningsLabel;

  /// Total earnings value formatted with the EGP currency suffix
  ///
  /// In en, this message translates to:
  /// **'{amount} EGP'**
  String earningsEgpAmount(String amount);

  /// Section title above the per-course student count list on the financial stats screen
  ///
  /// In en, this message translates to:
  /// **'📊 Course Statistics'**
  String get coursesStatsSectionTitle;

  /// Section title above the per-subject student count list on the financial stats screen
  ///
  /// In en, this message translates to:
  /// **'📚 Subject Statistics (Individual)'**
  String get subjectsStatsSectionTitle;

  /// Number of students badge shown next to a course/subject stat tile
  ///
  /// In en, this message translates to:
  /// **'{count} students'**
  String studentCountLabel(String count);

  /// Snackbar warning shown when the team-member search query is too short
  ///
  /// In en, this message translates to:
  /// **'Please enter at least 3 characters to search'**
  String get searchMinCharsWarning;

  /// Title of the confirmation dialog when promoting a student to supervisor
  ///
  /// In en, this message translates to:
  /// **'Promote Student'**
  String get promoteStudentDialogTitle;

  /// Title of the confirmation dialog when removing a supervisor
  ///
  /// In en, this message translates to:
  /// **'Remove Supervisor'**
  String get removeSupervisorDialogTitle;

  /// Snackbar shown after successfully promoting a student to supervisor
  ///
  /// In en, this message translates to:
  /// **'Student promoted and permissions granted successfully'**
  String get promoteSuccessMessage;

  /// Snackbar shown after successfully removing a supervisor
  ///
  /// In en, this message translates to:
  /// **'Supervisor removed successfully'**
  String get demoteSuccessMessage;

  /// Generic error snackbar with the error details appended
  ///
  /// In en, this message translates to:
  /// **'An error occurred: {error}'**
  String errorOccurredWithDetails(String error);

  /// AppBar title of the manage team (supervisors) screen
  ///
  /// In en, this message translates to:
  /// **'Manage Team'**
  String get manageTeamTitle;

  /// Heading of the search section used to add a new supervisor
  ///
  /// In en, this message translates to:
  /// **'Add New Supervisor'**
  String get addNewSupervisorTitle;

  /// Subtitle explaining the add-supervisor search section
  ///
  /// In en, this message translates to:
  /// **'Search for a student to promote and automatically grant them full permissions'**
  String get addSupervisorSubtitle;

  /// Hint text for the supervisor search field
  ///
  /// In en, this message translates to:
  /// **'Search by name or username...'**
  String get searchByNameOrUsernameHint;

  /// Label above the list of student search results
  ///
  /// In en, this message translates to:
  /// **'Search results:'**
  String get searchResultsLabel;

  /// Fallback text shown when a student's name is missing
  ///
  /// In en, this message translates to:
  /// **'No Name'**
  String get noNameFallback;

  /// Confirmation dialog body when promoting a student to supervisor
  ///
  /// In en, this message translates to:
  /// **'Student \'{name}\' will be promoted to supervisor and granted access to all of your current courses.\n\nAre you sure?'**
  String promoteConfirmMessage(String name);

  /// Button label to promote a student to supervisor
  ///
  /// In en, this message translates to:
  /// **'Promote'**
  String get promoteAction;

  /// Heading showing the number of current team supervisors
  ///
  /// In en, this message translates to:
  /// **'Current Supervisors ({count})'**
  String currentSupervisorsCountLabel(String count);

  /// Empty state message when there are no team supervisors yet
  ///
  /// In en, this message translates to:
  /// **'No supervisors currently'**
  String get noSupervisorsCurrently;

  /// Generic fallback text for an unknown name
  ///
  /// In en, this message translates to:
  /// **'Unknown'**
  String get unknownFallback;

  /// Tooltip on the icon button that removes a supervisor
  ///
  /// In en, this message translates to:
  /// **'Remove supervision'**
  String get removeSupervisorTooltip;

  /// Confirmation dialog body when demoting a supervisor back to a regular student
  ///
  /// In en, this message translates to:
  /// **'Supervisor permissions will be revoked from \'{name}\' and they will return to being a regular student.\n\nThey will no longer be able to manage content.'**
  String demoteConfirmMessage(String name);

  /// Snackbar warning shown when the student search query is too short
  ///
  /// In en, this message translates to:
  /// **'Enter at least 3 digits/letters'**
  String get searchMinDigitsLettersWarning;

  /// Snackbar shown when a student search fails or returns no result
  ///
  /// In en, this message translates to:
  /// **'Student not found or an error occurred: {error}'**
  String studentNotFoundOrError(String error);

  /// Title of the confirmation dialog and tooltip for revoking a student's access to content
  ///
  /// In en, this message translates to:
  /// **'Revoke Access'**
  String get revokeAccessDialogTitle;

  /// Body of the confirmation dialog for revoking a student's access
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to remove this permission? The student will be prevented from accessing this content.'**
  String get revokeAccessConfirmMessage;

  /// Button label confirming the revoke-access action
  ///
  /// In en, this message translates to:
  /// **'Confirm Revoke'**
  String get confirmRevokeAction;

  /// Snackbar shown after successfully granting a student access to content
  ///
  /// In en, this message translates to:
  /// **'Access granted successfully'**
  String get accessGrantedSuccessMessage;

  /// Snackbar shown after successfully revoking a student's access to content
  ///
  /// In en, this message translates to:
  /// **'Access revoked successfully'**
  String get accessRevokedSuccessMessage;

  /// Generic operation-failed snackbar with error details appended
  ///
  /// In en, this message translates to:
  /// **'Operation failed: {error}'**
  String operationFailedWithDetails(String error);

  /// Snackbar shown after successfully granting multiple permissions at once
  ///
  /// In en, this message translates to:
  /// **'{count} permissions granted successfully'**
  String bulkGrantSuccessMessage(String count);

  /// Snackbar shown when bulk-granting access fails
  ///
  /// In en, this message translates to:
  /// **'An error occurred while granting access: {error}'**
  String bulkGrantErrorWithDetails(String error);

  /// Snackbar shown when the add-access dialog is opened before course data has finished loading
  ///
  /// In en, this message translates to:
  /// **'Loading course data... please try again shortly.'**
  String get loadingCoursesRetryMessage;

  /// Title of the dialog where a teacher selects courses/subjects to grant a student access to
  ///
  /// In en, this message translates to:
  /// **'Choose permissions to grant'**
  String get choosePermissionsToGrantTitle;

  /// Button label to grant the selected number of permissions
  ///
  /// In en, this message translates to:
  /// **'Grant ({count})'**
  String grantWithCountAction(String count);

  /// AppBar title of the manage students (access control) screen
  ///
  /// In en, this message translates to:
  /// **'Manage Students (My Students)'**
  String get manageStudentsTitle;

  /// Hint text for the student search field on the manage students screen
  ///
  /// In en, this message translates to:
  /// **'Phone number or username'**
  String get phoneOrUsernameHint;

  /// Generic Search button label
  ///
  /// In en, this message translates to:
  /// **'Search'**
  String get searchAction;

  /// Heading above a student's current list of granted permissions
  ///
  /// In en, this message translates to:
  /// **'Current Permissions:'**
  String get currentPermissionsLabel;

  /// Button label that opens the dialog to manage a student's permissions
  ///
  /// In en, this message translates to:
  /// **'Manage Permissions'**
  String get managePermissionsAction;

  /// Empty state message when a student has no granted permissions
  ///
  /// In en, this message translates to:
  /// **'This student doesn\'t have any permissions currently'**
  String get noAccessCurrentlyMessage;

  /// Fallback text shown when an item's title is missing
  ///
  /// In en, this message translates to:
  /// **'Undefined'**
  String get undefinedFallback;

  /// Small subtitle badge indicating a permission grants the full course
  ///
  /// In en, this message translates to:
  /// **'Full course'**
  String get fullCourseBadgeLabel;

  /// Small subtitle badge indicating a permission grants a single subject only
  ///
  /// In en, this message translates to:
  /// **'Individual subject'**
  String get individualSubjectBadgeLabel;

  /// Empty state prompt shown before any student search has been performed
  ///
  /// In en, this message translates to:
  /// **'Search for a student to manage their permissions'**
  String get searchForStudentPrompt;

  /// Student phone number shown with a phone emoji prefix
  ///
  /// In en, this message translates to:
  /// **'📞 {phone}'**
  String phoneEmojiLabel(String phone);

  /// Student username shown with a person emoji prefix
  ///
  /// In en, this message translates to:
  /// **'👤 {username}'**
  String usernameEmojiLabel(String username);

  /// Title of the dialog where a teacher enters a reason for rejecting a subscription request
  ///
  /// In en, this message translates to:
  /// **'Rejection Reason'**
  String get rejectionReasonDialogTitle;

  /// Hint text for the rejection reason text field
  ///
  /// In en, this message translates to:
  /// **'Write the rejection reason here...'**
  String get rejectionReasonHint;

  /// Button label confirming the rejection of a subscription request
  ///
  /// In en, this message translates to:
  /// **'Confirm Rejection'**
  String get confirmRejectionAction;

  /// Transient snackbar shown while a request decision is being submitted
  ///
  /// In en, this message translates to:
  /// **'Processing...'**
  String get processingActionMessage;

  /// Snackbar shown after successfully approving a student's subscription request
  ///
  /// In en, this message translates to:
  /// **'Student approved successfully'**
  String get studentApprovedSuccessMessage;

  /// Snackbar shown after rejecting a student's subscription request
  ///
  /// In en, this message translates to:
  /// **'Request rejected'**
  String get requestRejectedMessage;

  /// Snackbar shown when trying to view a receipt image before auth data has loaded
  ///
  /// In en, this message translates to:
  /// **'Error: authentication data isn\'t ready'**
  String get authDataNotReadyError;

  /// Error message shown when a receipt image fails to load
  ///
  /// In en, this message translates to:
  /// **'Failed to load the image - check your connection'**
  String get imageLoadFailedCheckConnection;

  /// AppBar title of the student subscription requests screen
  ///
  /// In en, this message translates to:
  /// **'Subscription Requests'**
  String get subscriptionRequestsTitle;

  /// Tab label for pending subscription requests
  ///
  /// In en, this message translates to:
  /// **'Pending'**
  String get tabPending;

  /// Tab label for approved subscription requests
  ///
  /// In en, this message translates to:
  /// **'Approved'**
  String get tabApproved;

  /// Tab label for rejected subscription requests
  ///
  /// In en, this message translates to:
  /// **'Rejected'**
  String get tabRejected;

  /// Empty state message shown when a subscription requests tab has no items
  ///
  /// In en, this message translates to:
  /// **'No requests in this list'**
  String get noRequestsInListMessage;

  /// Fallback text shown when a requester's name is missing
  ///
  /// In en, this message translates to:
  /// **'Unknown Name'**
  String get unknownNameFallback;

  /// Label above the course/subject title in a subscription request card
  ///
  /// In en, this message translates to:
  /// **'Requested Content:'**
  String get requestedContentLabel;

  /// Fallback text shown when the requested course title is missing
  ///
  /// In en, this message translates to:
  /// **'Not specified'**
  String get notSpecifiedFallback;

  /// Label above a student's note in a subscription request card
  ///
  /// In en, this message translates to:
  /// **'Student\'s note:'**
  String get studentNoteLabel;

  /// Label above the rejection reason shown in a rejected request card
  ///
  /// In en, this message translates to:
  /// **'Rejection reason:'**
  String get rejectionReasonLabel;

  /// Title of the screen listing a student's subscription requests
  ///
  /// In en, this message translates to:
  /// **'My Requests'**
  String get myRequestsTitle;

  /// Subtitle under the My Requests screen title
  ///
  /// In en, this message translates to:
  /// **'TRACK YOUR ORDERS'**
  String get trackYourOrdersLabel;

  /// Empty state message shown when the student has no subscription requests
  ///
  /// In en, this message translates to:
  /// **'No requests found'**
  String get noRequestsFound;

  /// Status label shown when a subscription request was approved
  ///
  /// In en, this message translates to:
  /// **'Approved'**
  String get requestStatusApproved;

  /// Status label shown when a subscription request was rejected
  ///
  /// In en, this message translates to:
  /// **'Rejected'**
  String get requestStatusRejected;

  /// Status label shown when a subscription request is still pending
  ///
  /// In en, this message translates to:
  /// **'Pending'**
  String get requestStatusPending;

  /// Fallback text shown when a request's course title is missing
  ///
  /// In en, this message translates to:
  /// **'Unknown item'**
  String get unknownItemFallback;

  /// Label above the student's own note in a request card
  ///
  /// In en, this message translates to:
  /// **'Your note:'**
  String get yourNoteLabel;

  /// Label above the price in a subscription request card
  ///
  /// In en, this message translates to:
  /// **'Total'**
  String get totalLabel;

  /// Standalone currency label shown under a price amount
  ///
  /// In en, this message translates to:
  /// **'EGP'**
  String get egpCurrencyLabel;

  /// Button label to reject a pending subscription request
  ///
  /// In en, this message translates to:
  /// **'Reject Request'**
  String get rejectRequestAction;

  /// Button label to accept and activate a pending subscription request
  ///
  /// In en, this message translates to:
  /// **'Accept & Activate'**
  String get acceptAndActivateAction;

  /// Snackbar shown when the initial load of subscription requests fails
  ///
  /// In en, this message translates to:
  /// **'An error occurred while loading: {error}'**
  String errorLoadingDataWithDetails(String error);

  /// Snackbar shown when fetching a page of subscription requests fails
  ///
  /// In en, this message translates to:
  /// **'Failed to fetch data: {error}'**
  String failedToFetchDataWithDetails(String error);

  /// Validation warning shown when saving a video with a zero duration
  ///
  /// In en, this message translates to:
  /// **'⚠️ Please enter the actual video duration (it can\'t be left at zero)'**
  String get videoDurationRequiredWarning;

  /// Validation warning shown when the minutes/seconds duration fields exceed 59
  ///
  /// In en, this message translates to:
  /// **'⚠️ Minutes and seconds must not exceed 59'**
  String get minutesSecondsMaxWarning;

  /// Validation warning shown when creating a PDF item without selecting a file
  ///
  /// In en, this message translates to:
  /// **'Please select a PDF file'**
  String get pleaseSelectPdfFileWarning;

  /// Error thrown when a YouTube URL can't be parsed into a valid video ID
  ///
  /// In en, this message translates to:
  /// **'Invalid video URL'**
  String get invalidVideoUrlError;

  /// Snackbar shown after successfully updating a content item
  ///
  /// In en, this message translates to:
  /// **'Updated Successfully'**
  String get updatedSuccessfullyMessage;

  /// Snackbar shown after successfully creating a content item
  ///
  /// In en, this message translates to:
  /// **'Created Successfully'**
  String get createdSuccessfullyMessage;

  /// Snackbar shown when saving a content item fails
  ///
  /// In en, this message translates to:
  /// **'Error: {error}'**
  String contentSaveErrorWithDetails(String error);

  /// Validation warning shown when trying to upload a video without selecting a file
  ///
  /// In en, this message translates to:
  /// **'⚠️ Please select a video file first'**
  String get pleaseSelectVideoFileFirstWarning;

  /// Snackbar shown after a video upload completes but duration extraction is still pending
  ///
  /// In en, this message translates to:
  /// **'✅ Video uploaded successfully; its duration will be extracted automatically once processing completes'**
  String get videoUploadedDurationPendingMessage;

  /// Snackbar shown after a video upload completes successfully
  ///
  /// In en, this message translates to:
  /// **'✅ Video uploaded successfully and will be available once processing completes'**
  String get videoUploadedSuccessMessage;

  /// Body of the confirmation dialog shown before deleting a content item
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to delete this item? This cannot be undone.'**
  String get confirmDeleteItemMessage;

  /// Snackbar shown after successfully deleting a content item
  ///
  /// In en, this message translates to:
  /// **'Deleted Successfully'**
  String get deletedSuccessfullyMessage;

  /// Snackbar shown when deleting a content item fails
  ///
  /// In en, this message translates to:
  /// **'Delete Failed: {error}'**
  String deleteFailedWithDetails(String error);

  /// Status text shown while a resumable video upload session is being prepared
  ///
  /// In en, this message translates to:
  /// **'Preparing upload session...'**
  String get preparingUploadSessionStatus;

  /// Status text showing the percentage progress of a video upload
  ///
  /// In en, this message translates to:
  /// **'Uploading video... {percent}%'**
  String uploadingVideoProgressStatus(String percent);

  /// Status text shown when a resumable video upload is paused due to lost connectivity
  ///
  /// In en, this message translates to:
  /// **'⏸️ Connection lost — waiting for the connection to return to continue automatically'**
  String get connectionLostWaitingStatus;

  /// Status text shown while a completed video upload is being confirmed/saved
  ///
  /// In en, this message translates to:
  /// **'Saving video data...'**
  String get savingVideoDataStatus;

  /// AppBar title when editing an existing course
  ///
  /// In en, this message translates to:
  /// **'Edit Course'**
  String get editCourseTitle;

  /// AppBar title when creating a new course
  ///
  /// In en, this message translates to:
  /// **'New Course'**
  String get newCourseTitle;

  /// AppBar title when editing an existing subject
  ///
  /// In en, this message translates to:
  /// **'Edit Subject'**
  String get editSubjectTitle;

  /// AppBar title when creating a new subject
  ///
  /// In en, this message translates to:
  /// **'New Subject'**
  String get newSubjectTitle;

  /// AppBar title when editing an existing chapter
  ///
  /// In en, this message translates to:
  /// **'Edit Chapter'**
  String get editChapterTitle;

  /// AppBar title when creating a new chapter
  ///
  /// In en, this message translates to:
  /// **'New Chapter'**
  String get newChapterTitle;

  /// AppBar title when editing an existing video
  ///
  /// In en, this message translates to:
  /// **'Edit Video'**
  String get editVideoTitle;

  /// AppBar title when creating a new video
  ///
  /// In en, this message translates to:
  /// **'New Video'**
  String get newVideoTitle;

  /// AppBar title when editing an existing PDF
  ///
  /// In en, this message translates to:
  /// **'Edit PDF'**
  String get editPdfTitle;

  /// AppBar title when creating a new PDF
  ///
  /// In en, this message translates to:
  /// **'New PDF'**
  String get newPdfTitle;

  /// Button label to cancel an in-progress resumable video upload
  ///
  /// In en, this message translates to:
  /// **'Cancel Upload'**
  String get cancelUploadAction;

  /// Status text shown while a PDF file is being uploaded
  ///
  /// In en, this message translates to:
  /// **'Uploading File...'**
  String get uploadingFileStatus;

  /// Status text shown while content data is being saved to the server
  ///
  /// In en, this message translates to:
  /// **'Saving Data...'**
  String get savingDataStatus;

  /// Label for the title/name text field on the content form
  ///
  /// In en, this message translates to:
  /// **'Title / Name'**
  String get titleNameLabel;

  /// Label for the optional folder/group name field when creating or editing a chapter
  ///
  /// In en, this message translates to:
  /// **'Folder (optional)'**
  String get chapterFolderLabel;

  /// Hint text for the optional chapter folder field
  ///
  /// In en, this message translates to:
  /// **'e.g. Term 1, Unit 2 (leave empty for no folder)'**
  String get chapterFolderHint;

  /// Hint text for the title/name field on the content form
  ///
  /// In en, this message translates to:
  /// **'Enter title here'**
  String get enterTitleHereHint;

  /// Label for the description text field on the content form
  ///
  /// In en, this message translates to:
  /// **'Description'**
  String get descriptionFieldLabel;

  /// Hint text for the description field on the content form
  ///
  /// In en, this message translates to:
  /// **'Enter description'**
  String get enterDescriptionHint;

  /// Label for the price text field on the content form
  ///
  /// In en, this message translates to:
  /// **'Price (EGP)'**
  String get priceEgpFieldLabel;

  /// Hint text for the price field on the content form
  ///
  /// In en, this message translates to:
  /// **'0.0'**
  String get zeroPointZeroHint;

  /// Tab label for choosing YouTube link as the video source
  ///
  /// In en, this message translates to:
  /// **'YouTube Link'**
  String get youtubeLinkTabLabel;

  /// Tab label for choosing direct file upload as the video source
  ///
  /// In en, this message translates to:
  /// **'Upload Video File'**
  String get uploadVideoFileTabLabel;

  /// Info note shown when replacing an existing uploaded video while editing
  ///
  /// In en, this message translates to:
  /// **'Selecting a new file here will fully replace the current video once the upload completes.'**
  String get newFileReplaceWarning;

  /// Label for the YouTube URL text field
  ///
  /// In en, this message translates to:
  /// **'YouTube Video Link'**
  String get youtubeVideoLinkLabel;

  /// Label above the hours/minutes/seconds duration fields for a YouTube video
  ///
  /// In en, this message translates to:
  /// **'Actual video duration ⏱️'**
  String get actualVideoDurationLabel;

  /// Label for the hours duration field
  ///
  /// In en, this message translates to:
  /// **'Hours'**
  String get hoursLabel;

  /// Label for the minutes duration field
  ///
  /// In en, this message translates to:
  /// **'Minutes'**
  String get minutesLabel;

  /// Label for the seconds duration field
  ///
  /// In en, this message translates to:
  /// **'Seconds'**
  String get secondsLabel;

  /// Helper text below the YouTube duration fields
  ///
  /// In en, this message translates to:
  /// **'Paste the full YouTube link and set its duration to show it to students'**
  String get pasteYoutubeLinkHint;

  /// Placeholder shown when no video file has been picked yet
  ///
  /// In en, this message translates to:
  /// **'No file selected'**
  String get noFileSelectedVideo;

  /// Helper text prompting the teacher to pick a video file
  ///
  /// In en, this message translates to:
  /// **'Tap to select a video file from your device'**
  String get tapToSelectVideoFile;

  /// Status text shown while the app extracts a local video file's duration
  ///
  /// In en, this message translates to:
  /// **'Extracting video duration...'**
  String get extractingVideoDurationStatus;

  /// Info banner shown when a resumable upload session is detected for the selected video file
  ///
  /// In en, this message translates to:
  /// **'A previously interrupted upload for this file was found — the upload will resume from where it left off'**
  String get resumableUploadFoundMessage;

  /// Button label to resume a previously failed/paused video upload
  ///
  /// In en, this message translates to:
  /// **'Resume Upload'**
  String get resumeUploadAction;

  /// Info note explaining resumable video uploads
  ///
  /// In en, this message translates to:
  /// **'The video upload can be paused and resumed later; it also resumes automatically after a connection drop instead of starting over.'**
  String get uploadPauseResumeInfoMessage;

  /// Label above the duration fields for an uploaded video file
  ///
  /// In en, this message translates to:
  /// **'Video duration (extracted automatically, editable) ⏱️'**
  String get videoDurationAutoExtractedLabel;

  /// Placeholder shown when no PDF file has been picked yet
  ///
  /// In en, this message translates to:
  /// **'No file selected'**
  String get noPdfFileSelected;

  /// Helper text prompting the teacher to pick a PDF file
  ///
  /// In en, this message translates to:
  /// **'Tap to select PDF'**
  String get tapToSelectPdfLabel;

  /// Toggle label for sending a notification when new content is published
  ///
  /// In en, this message translates to:
  /// **'Send notification to students'**
  String get sendNotificationToStudentsLabel;

  /// Subtitle explaining the notify-students toggle
  ///
  /// In en, this message translates to:
  /// **'Alert subscribed students about this new content'**
  String get notifySubscribedStudentsSubtitle;

  /// Submit button label (uppercase) when editing an existing content item
  ///
  /// In en, this message translates to:
  /// **'SAVE CHANGES'**
  String get saveChangesUpperAction;

  /// Submit button label when resuming a paused video upload
  ///
  /// In en, this message translates to:
  /// **'Resume & Upload Video'**
  String get resumeAndUploadVideoAction;

  /// Submit button label when starting a fresh video upload
  ///
  /// In en, this message translates to:
  /// **'Upload Video'**
  String get uploadVideoAction;

  /// Submit button label (uppercase) when creating a new content item
  ///
  /// In en, this message translates to:
  /// **'CREATE'**
  String get createUpperAction;

  /// Button label (uppercase) to permanently delete a content item while editing
  ///
  /// In en, this message translates to:
  /// **'DELETE PERMANENTLY'**
  String get deletePermanentlyUpperAction;

  /// Header title on the Profile screen
  ///
  /// In en, this message translates to:
  /// **'MY PROFILE'**
  String get myProfileTitle;

  /// Profile screen subtitle shown to teachers
  ///
  /// In en, this message translates to:
  /// **'TEACHER DASHBOARD'**
  String get teacherDashboardSubtitle;

  /// Profile screen subtitle shown to students
  ///
  /// In en, this message translates to:
  /// **'MANAGE YOUR ACCOUNT'**
  String get manageYourAccountSubtitle;

  /// Display name shown for a guest (not logged in) user
  ///
  /// In en, this message translates to:
  /// **'GUEST USER'**
  String get guestUserName;

  /// Username placeholder shown for a guest user
  ///
  /// In en, this message translates to:
  /// **'Not Logged In'**
  String get notLoggedInLabel;

  /// Fallback display name when the user has no first name set
  ///
  /// In en, this message translates to:
  /// **'User'**
  String get defaultUserNameLabel;

  /// Section header for teacher-only options on the Profile screen
  ///
  /// In en, this message translates to:
  /// **'TEACHER CONTROLS'**
  String get teacherControlsSection;

  /// Menu item: teacher's incoming subscription requests
  ///
  /// In en, this message translates to:
  /// **'Incoming Requests'**
  String get incomingRequestsMenu;

  /// Menu item: manage students
  ///
  /// In en, this message translates to:
  /// **'My Students'**
  String get myStudentsMenu;

  /// Menu item: manage teaching team
  ///
  /// In en, this message translates to:
  /// **'Manage Team'**
  String get manageTeamMenu;

  /// Menu item: financial statistics
  ///
  /// In en, this message translates to:
  /// **'Financial Stats'**
  String get financialStatsMenu;

  /// Section header for account settings on the Profile screen
  ///
  /// In en, this message translates to:
  /// **'ACCOUNT SETTINGS'**
  String get accountSettingsSection;

  /// Menu item: edit profile
  ///
  /// In en, this message translates to:
  /// **'Edit Profile'**
  String get editProfileMenu;

  /// Menu item: change password
  ///
  /// In en, this message translates to:
  /// **'Change Password'**
  String get changePasswordMenu;

  /// Menu item: student's own requests
  ///
  /// In en, this message translates to:
  /// **'My Requests'**
  String get myRequestsMenu;

  /// Section header for general app settings on the Profile screen
  ///
  /// In en, this message translates to:
  /// **'GENERAL'**
  String get generalSection;

  /// Menu item: app information / about screen
  ///
  /// In en, this message translates to:
  /// **'App Information'**
  String get appInformationMenu;

  /// Menu item: app language switcher
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get languageMenu;

  /// Section header for destructive account actions
  ///
  /// In en, this message translates to:
  /// **'DANGER ZONE'**
  String get dangerZoneSection;

  /// Menu item: permanently delete the account
  ///
  /// In en, this message translates to:
  /// **'Delete My Account'**
  String get deleteMyAccountMenu;

  /// Button shown to guests to log in or register
  ///
  /// In en, this message translates to:
  /// **'LOGIN / REGISTER'**
  String get loginRegisterButton;

  /// Button to log out of the account
  ///
  /// In en, this message translates to:
  /// **'LOGOUT'**
  String get logoutButton;

  /// Title of the language picker bottom sheet
  ///
  /// In en, this message translates to:
  /// **'Select Language'**
  String get selectLanguageTitle;

  /// Language option label for English
  ///
  /// In en, this message translates to:
  /// **'English'**
  String get englishLanguageOption;

  /// Language option label for Arabic
  ///
  /// In en, this message translates to:
  /// **'العربية'**
  String get arabicLanguageOption;

  /// Label/snackbar text shown when high-quality audio track is active
  ///
  /// In en, this message translates to:
  /// **'HQ Audio'**
  String get hqAudioLabel;

  /// Badge shown while the user is fast-forwarding by holding to seek at double speed
  ///
  /// In en, this message translates to:
  /// **'speed×2'**
  String get doubleSpeedLabel;

  /// Label shown instead of a price when a course is free
  ///
  /// In en, this message translates to:
  /// **'Free Access'**
  String get freeAccessLabel;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['ar', 'en'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'ar':
      return AppLocalizationsAr();
    case 'en':
      return AppLocalizationsEn();
  }

  throw FlutterError(
      'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
      'an issue with the localizations generation tool. Please file an issue '
      'on GitHub with a reproducible sample app and the gen-l10n configuration '
      'that was used.');
}
