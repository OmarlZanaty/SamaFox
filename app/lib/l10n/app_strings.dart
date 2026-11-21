/// Localization strings for SamaFox app
/// This file contains all text strings used in the app
/// To add a new language, create a new class (e.g., AppStringsAr for Arabic)
/// and implement the same structure

abstract class AppStrings {
  // Common
  String get appName;
  String get loading;
  String get error;
  String get retry;
  String get cancel;
  String get save;
  String get delete;
  String get edit;
  String get done;
  String get yes;
  String get no;
  String get ok;
  String get search;
  String get settings;
  String get back;
  String get close;
  String get confirm;
  String get apply;
  String get clear;
  String get all;
  String get online;
  String get offline;

  // Splash Screen
  String get splashTagline;

  // Login Screen
  String get welcomeBack;
  String get signInToContinue;
  String get email;
  String get password;
  String get forgotPassword;
  String get signIn;
  String get continueAsGuest;
  String get orContinueWith;
  String get google;
  String get facebook;
  String get dontHaveAccount;
  String get signUp;
  String get createAccount;
  String get forgotPasswordComingSoon;
  String get googleLoginComingSoon;
  String get facebookLoginComingSoon;
  String get registrationComingSoon;
  String get pleaseEnterEmail;
  String get invalidEmail;
  String get pleaseEnterPassword;
  String get passwordTooShort;
  String get guestLoginFailed;
  String get registrationFailed;

  // Home Screen
  String get home;
  String get searchComingSoon;
  String get createFirstRoom;
  String get guest;
  String get noRoomsAvailable;
  String get createRoom;
  String get roomName;
  String get fullName;
  String get enterYourFullName;
  String get nameIsRequired;
  String get confirmPassword;
  String get confirmPasswordHint;
  String get pleaseConfirmPassword;
  String get passwordsDoNotMatch;
  String get genderOptional;
  String get selectGender;
  String get countryOptional;
  String get selectCountry;
  String get searchCountry;
  String get register;
  String get description;
  String get create;
  String get roomCreatedSuccessfully;
  String get failedToCreateRoom;
  String get enterYourEmail;
  String get enterYourPassword;
  String get passwordIsRequired;

  // Profile Screen
  String get myProfile;
  String get followers;
  String get following;
  String get coins;
  String get accountDetails;
  String get notProvided;
  String get notSet;
  String get phone;
  String get country;
  String get level;
  String get vipStatus;
  String get vipLevel;
  String get noUserData;
  String get editProfile;
  String get bio;
  String get dateOfBirth;
  String get gender;
  String get male;
  String get female;
  String get other;
  String get changeAvatar;
  String get changeCover;
  String get profileUpdated;

  // Messages Screen
  String get messages;
  String get noConversationsYet;
  String get justNow;
  String get noMessages;
  String get newMessage;
  String get deleteConversation;
  String get blockUser;
  String get reportUser;

  // Chat Conversation Screen
  String get chatWith;
  String get typing;
  String get sendMessage;
  String get voiceCall;
  String get videoCall;
  String get attachment;
  String get emoji;
  String get photo;
  String get video;
  String get document;
  String get location;

  // Gifts Screen
  String get gifts;
  String get noGiftsAvailable;
  String get send;
  String get giftSentSuccessfully;
  String get failedToSendGift;
  String get myGifts;
  String get sendGift;
  String get giftStore;
  String get price;
  String get buy;
  String get purchased;

  // Gift Store Screen
  String get popularGifts;
  String get newGifts;
  String get premiumGifts;
  String get balance;
  String get insufficientBalance;
  String get purchaseSuccessful;
  String get purchaseFailed;

  // Settings Screen
  String get language;
  String get theme;
  String get notifications;
  String get privacy;
  String get about;
  String get logout;
  String get darkMode;
  String get lightMode;
  String get accountSettings;
  String get changePassword;
  String get blockedUsers;
  String get deleteAccount;
  String get termsOfService;
  String get privacyPolicy;
  String get version;
  String get logoutConfirm;
  String get deleteAccountConfirm;

  // Room Screen
  String get members;
  String get chat;
  String get typeMessage;
  String get mute;
  String get unmute;
  String get speaker;
  String get leave;
  String get joinRoom;
  String get leaveRoom;
  String get roomFull;
  String get roomClosed;
  String get inviteFriends;
  String get roomSettings;
  String get kickUser;
  String get banUser;
  String get makeAdmin;
  String get makeSpeaker;
  String get muteMic;
  String get unmuteMic;

  // Explore Screen
  String get explore;
  String get trending;
  String get recommended;
  String get categories;
  String get seeAll;
  String get noRooms;
  String get filter;
  String get sortBy;
  String get popularity;
  String get newest;
  String get mostMembers;

  // Wallet Screen
  String get wallet;
  String get myBalance;
  String get addCoins;
  String get transactions;
  String get transactionHistory;
  String get deposit;
  String get withdrawal;
  String get amount;
  String get date;
  String get status;
  String get pending;
  String get completed;
  String get failed;
  String get noTransactions;

  // Premium/VIP Screen
  String get premium;
  String get upgradeToPremium;
  String get premiumFeatures;
  String get exclusiveBadge;
  String get unlimitedGifts;
  String get prioritySupport;
  String get adFree;
  String get customThemes;
  String get subscribe;
  String get monthly;
  String get yearly;
  String get lifetime;
  String get currentPlan;
  String get renewsOn;

  // Challenges Screen
  String get challenges;
  String get dailyChallenges;
  String get weeklyChallenges;
  String get completedChallenges;
  String get inProgress;
  String get notStarted;
  String get reward;
  String get claimReward;
  String get noChallenges;
  String get progress;

  // Leaderboard Screen
  String get leaderboard;
  String get topUsers;
  String get topRooms;
  String get daily;
  String get weekly;
  String get allTime;
  String get rank;
  String get points;
  String get yourRank;

  // Achievements Screen
  String get achievements;
  String get locked;
  String get unlocked;
  String get earnedOn;
  String get noAchievements;
  String get totalAchievements;

  // Search Screen
  String get searchUsers;
  String get searchRooms;
  String get recentSearches;
  String get noResults;
  String get searchHint;

  // Notifications Screen
  String get notification;
  String get markAllRead;
  String get noNotifications;
  String get newFollower;
  String get giftReceived;
  String get roomInvite;

  // Analytics Screen (for room owners)
  String get analytics;
  String get roomAnalytics;
  String get totalVisitors;
  String get activeMembers;
  String get peakHours;
  String get engagement;
  String get insights;

  // Help & Support Screen
  String get help;
  String get helpCenter;
  String get faq;
  String get contactSupport;
  String get reportProblem;
  String get feedback;
  String get sendFeedback;
  String get commonQuestions;

  // Admin Dashboard (if admin)
  String get adminDashboard;
  String get manageUsers;
  String get manageRooms;
  String get reports;
  String get statistics;
  String get systemSettings;

  // Navigation
  String get profile;

  // Errors
  String get somethingWentWrong;
  String get networkError;
  String get tryAgain;
  String get connectionLost;
  String get serverError;
  String get unauthorized;
  String get notFound;
}

/// English strings implementation
class AppStringsEn extends AppStrings {
  // Common
  @override
  String get appName => 'SamaFox';
  @override
  String get loading => 'Loading...';
  @override
  String get error => 'Error';
  @override
  String get retry => 'Retry';
  @override
  String get cancel => 'Cancel';
  @override
  String get save => 'Save';
  @override
  String get delete => 'Delete';
  @override
  String get edit => 'Edit';
  @override
  String get done => 'Done';
  @override
  String get yes => 'Yes';
  @override
  String get no => 'No';
  @override
  String get ok => 'OK';
  @override
  String get search => 'Search';
  @override
  String get settings => 'Settings';
  @override
  String get back => 'Back';
  @override
  String get close => 'Close';
  @override
  String get confirm => 'Confirm';
  @override
  String get apply => 'Apply';
  @override
  String get clear => 'Clear';
  @override
  String get all => 'All';
  @override
  String get online => 'Online';
  @override
  String get offline => 'Offline';

  // Splash Screen
  @override
  String get splashTagline => 'Voice Chat & Social Platform';

  // Login Screen
  @override
  String get welcomeBack => 'Welcome Back!';
  @override
  String get signInToContinue => 'Sign in to continue your journey';
  @override
  String get email => 'Email';
  @override
  String get password => 'Password';
  @override
  String get forgotPassword => 'Forgot Password?';
  @override
  String get signIn => 'Sign In';
  @override
  String get continueAsGuest => 'Continue as Guest';
  @override
  String get orContinueWith => 'Or continue with';
  @override
  String get google => 'Google';
  @override
  String get facebook => 'Facebook';
  @override
  String get dontHaveAccount => "Don't have an account? ";
  @override
  String get signUp => 'Sign Up';
  @override
  String get createAccount => 'Create Account';
  @override
  String get forgotPasswordComingSoon => 'Forgot password feature coming soon';
  @override
  String get googleLoginComingSoon => 'Google login coming soon';
  @override
  String get facebookLoginComingSoon => 'Facebook login coming soon';
  @override
  String get registrationComingSoon => 'Registration coming soon';
  @override
  String get pleaseEnterEmail => 'Please enter your email';
  @override
  String get invalidEmail => 'Invalid email';
  @override
  String get pleaseEnterPassword => 'Please enter your password';
  @override
  String get passwordTooShort => 'Password must be at least 6 characters';
  @override
  String get guestLoginFailed => 'Guest login failed';
  @override
  String get registrationFailed => 'Registration failed';

  // Home Screen
  @override
  String get home => 'Home';
  @override
  String get searchComingSoon => 'Search coming soon!';
  @override
  String get createFirstRoom => 'Create your first room!';
  @override
  String get guest => 'Guest';
  @override
  String get noRoomsAvailable => 'No rooms available';
  @override
  String get createRoom => 'Create Room';
  @override
  String get roomName => 'Room Name';
  @override
  String get fullName => 'Full Name';
  @override
  String get enterYourFullName => 'Enter your full name';
  @override
  String get nameIsRequired => 'Name is required';
  @override
  String get confirmPassword => 'Confirm Password';
  @override
  String get confirmPasswordHint => 'Confirm password';
  @override
  String get pleaseConfirmPassword => 'Please confirm password';
  @override
  String get passwordsDoNotMatch => 'Passwords do not match';
  @override
  String get genderOptional => 'Gender (Optional)';
  @override
  String get selectGender => 'Select gender';
  @override
  String get countryOptional => 'Country (Optional)';
  @override
  String get selectCountry => 'Select country';
  @override
  String get searchCountry => 'Search country';
  @override
  String get register => 'Register';
  @override
  String get description => 'Description';
  @override
  String get create => 'Create';
  @override
  String get roomCreatedSuccessfully => 'Room created successfully';
  @override
  String get failedToCreateRoom => 'Failed to create room';
  @override
  String get enterYourEmail => 'Enter your email';
  @override
  String get enterYourPassword => 'Enter your password';
  @override
  String get passwordIsRequired => 'Password is required';

  // Profile Screen
  @override
  String get myProfile => 'My Profile';
  @override
  String get followers => 'Followers';
  @override
  String get following => 'Following';
  @override
  String get coins => 'Coins';
  @override
  String get accountDetails => 'Account Details';
  @override
  String get notProvided => 'Not provided';
  @override
  String get notSet => 'Not set';
  @override
  String get phone => 'Phone';
  @override
  String get country => 'Country';
  @override
  String get level => 'Level';
  @override
  String get vipStatus => 'VIP Status';
  @override
  String get vipLevel => 'VIP Level';
  @override
  String get noUserData => 'No user data';
  @override
  String get editProfile => 'Edit Profile';
  @override
  String get bio => 'Bio';
  @override
  String get dateOfBirth => 'Date of Birth';
  @override
  String get gender => 'Gender';
  @override
  String get male => 'Male';
  @override
  String get female => 'Female';
  @override
  String get other => 'Other';
  @override
  String get changeAvatar => 'Change Avatar';
  @override
  String get changeCover => 'Change Cover';
  @override
  String get profileUpdated => 'Profile updated successfully';

  // Messages Screen
  @override
  String get messages => 'Messages';
  @override
  String get noConversationsYet => 'No conversations yet';
  @override
  String get justNow => 'Just now';
  @override
  String get noMessages => 'No messages';
  @override
  String get newMessage => 'New Message';
  @override
  String get deleteConversation => 'Delete Conversation';
  @override
  String get blockUser => 'Block User';
  @override
  String get reportUser => 'Report User';

  // Chat Conversation Screen
  @override
  String get chatWith => 'Chat with';
  @override
  String get typing => 'typing...';
  @override
  String get sendMessage => 'Send';
  @override
  String get voiceCall => 'Voice Call';
  @override
  String get videoCall => 'Video Call';
  @override
  String get attachment => 'Attachment';
  @override
  String get emoji => 'Emoji';
  @override
  String get photo => 'Photo';
  @override
  String get video => 'Video';
  @override
  String get document => 'Document';
  @override
  String get location => 'Location';

  // Gifts Screen
  @override
  String get gifts => 'Gifts';
  @override
  String get noGiftsAvailable => 'No gifts available';
  @override
  String get send => 'Send';
  @override
  String get giftSentSuccessfully => 'Gift sent successfully';
  @override
  String get failedToSendGift => 'Failed to send gift';
  @override
  String get myGifts => 'My Gifts';
  @override
  String get sendGift => 'Send Gift';
  @override
  String get giftStore => 'Gift Store';
  @override
  String get price => 'Price';
  @override
  String get buy => 'Buy';
  @override
  String get purchased => 'Purchased';

  // Gift Store Screen
  @override
  String get popularGifts => 'Popular Gifts';
  @override
  String get newGifts => 'New Gifts';
  @override
  String get premiumGifts => 'Premium Gifts';
  @override
  String get balance => 'Balance';
  @override
  String get insufficientBalance => 'Insufficient balance';
  @override
  String get purchaseSuccessful => 'Purchase successful';
  @override
  String get purchaseFailed => 'Purchase failed';

  // Settings Screen
  @override
  String get language => 'Language';
  @override
  String get theme => 'Theme';
  @override
  String get notifications => 'Notifications';
  @override
  String get privacy => 'Privacy';
  @override
  String get about => 'About';
  @override
  String get logout => 'Logout';
  @override
  String get darkMode => 'Dark Mode';
  @override
  String get lightMode => 'Light Mode';
  @override
  String get accountSettings => 'Account Settings';
  @override
  String get changePassword => 'Change Password';
  @override
  String get blockedUsers => 'Blocked Users';
  @override
  String get deleteAccount => 'Delete Account';
  @override
  String get termsOfService => 'Terms of Service';
  @override
  String get privacyPolicy => 'Privacy Policy';
  @override
  String get version => 'Version';
  @override
  String get logoutConfirm => 'Are you sure you want to logout?';
  @override
  String get deleteAccountConfirm => 'Are you sure you want to delete your account? This action cannot be undone.';

  // Room Screen
  @override
  String get members => 'Members';
  @override
  String get chat => 'Chat';
  @override
  String get typeMessage => 'Type a message...';
  @override
  String get mute => 'Mute';
  @override
  String get unmute => 'Unmute';
  @override
  String get speaker => 'Speaker';
  @override
  String get leave => 'Leave';
  @override
  String get joinRoom => 'Join Room';
  @override
  String get leaveRoom => 'Leave Room';
  @override
  String get roomFull => 'Room is full';
  @override
  String get roomClosed => 'Room is closed';
  @override
  String get inviteFriends => 'Invite Friends';
  @override
  String get roomSettings => 'Room Settings';
  @override
  String get kickUser => 'Kick User';
  @override
  String get banUser => 'Ban User';
  @override
  String get makeAdmin => 'Make Admin';
  @override
  String get makeSpeaker => 'Make Speaker';
  @override
  String get muteMic => 'Mute Mic';
  @override
  String get unmuteMic => 'Unmute Mic';

  // Explore Screen
  @override
  String get explore => 'Explore';
  @override
  String get trending => 'Trending';
  @override
  String get recommended => 'Recommended';
  @override
  String get categories => 'Categories';
  @override
  String get seeAll => 'See All';
  @override
  String get noRooms => 'No rooms found';
  @override
  String get filter => 'Filter';
  @override
  String get sortBy => 'Sort By';
  @override
  String get popularity => 'Popularity';
  @override
  String get newest => 'Newest';
  @override
  String get mostMembers => 'Most Members';

  // Wallet Screen
  @override
  String get wallet => 'Wallet';
  @override
  String get myBalance => 'My Balance';
  @override
  String get addCoins => 'Add Coins';
  @override
  String get transactions => 'Transactions';
  @override
  String get transactionHistory => 'Transaction History';
  @override
  String get deposit => 'Deposit';
  @override
  String get withdrawal => 'Withdrawal';
  @override
  String get amount => 'Amount';
  @override
  String get date => 'Date';
  @override
  String get status => 'Status';
  @override
  String get pending => 'Pending';
  @override
  String get completed => 'Completed';
  @override
  String get failed => 'Failed';
  @override
  String get noTransactions => 'No transactions yet';

  // Premium/VIP Screen
  @override
  String get premium => 'Premium';
  @override
  String get upgradeToPremium => 'Upgrade to Premium';
  @override
  String get premiumFeatures => 'Premium Features';
  @override
  String get exclusiveBadge => 'Exclusive Badge';
  @override
  String get unlimitedGifts => 'Unlimited Gifts';
  @override
  String get prioritySupport => 'Priority Support';
  @override
  String get adFree => 'Ad-Free Experience';
  @override
  String get customThemes => 'Custom Themes';
  @override
  String get subscribe => 'Subscribe';
  @override
  String get monthly => 'Monthly';
  @override
  String get yearly => 'Yearly';
  @override
  String get lifetime => 'Lifetime';
  @override
  String get currentPlan => 'Current Plan';
  @override
  String get renewsOn => 'Renews on';

  // Challenges Screen
  @override
  String get challenges => 'Challenges';
  @override
  String get dailyChallenges => 'Daily Challenges';
  @override
  String get weeklyChallenges => 'Weekly Challenges';
  @override
  String get completedChallenges => 'Completed';
  @override
  String get inProgress => 'In Progress';
  @override
  String get notStarted => 'Not Started';
  @override
  String get reward => 'Reward';
  @override
  String get claimReward => 'Claim Reward';
  @override
  String get noChallenges => 'No challenges available';
  @override
  String get progress => 'Progress';

  // Leaderboard Screen
  @override
  String get leaderboard => 'Leaderboard';
  @override
  String get topUsers => 'Top Users';
  @override
  String get topRooms => 'Top Rooms';
  @override
  String get daily => 'Daily';
  @override
  String get weekly => 'Weekly';
  @override
  @override
  String get allTime => 'All Time';
  @override
  String get rank => 'Rank';
  @override
  String get points => 'Points';
  @override
  String get yourRank => 'Your Rank';

  // Achievements Screen
  @override
  String get achievements => 'Achievements';
  @override
  String get locked => 'Locked';
  @override
  String get unlocked => 'Unlocked';
  @override
  String get earnedOn => 'Earned on';
  @override
  String get noAchievements => 'No achievements yet';
  @override
  String get totalAchievements => 'Total Achievements';

  // Search Screen
  @override
  String get searchUsers => 'Search Users';
  @override
  String get searchRooms => 'Search Rooms';
  @override
  String get recentSearches => 'Recent Searches';
  @override
  String get noResults => 'No results found';
  @override
  String get searchHint => 'Search for users, rooms...';

  // Notifications Screen
  @override
  String get notification => 'Notifications';
  @override
  String get markAllRead => 'Mark All Read';
  @override
  String get noNotifications => 'No notifications';
  @override
  String get newFollower => 'started following you';
  @override
  @override
  String get giftReceived => 'sent you a gift';
  @override
  String get roomInvite => 'invited you to a room';

  // Analytics Screen
  @override
  String get analytics => 'Analytics';
  @override
  String get roomAnalytics => 'Room Analytics';
  @override
  String get totalVisitors => 'Total Visitors';
  @override
  String get activeMembers => 'Active Members';
  @override
  String get peakHours => 'Peak Hours';
  @override
  String get engagement => 'Engagement';
  @override
  String get insights => 'Insights';

  // Help & Support Screen
  @override
  String get help => 'Help & Support';
  @override
  String get helpCenter => 'Help Center';
  @override
  String get faq => 'FAQ';
  @override
  String get contactSupport => 'Contact Support';
  @override
  String get reportProblem => 'Report a Problem';
  @override
  String get feedback => 'Feedback';
  @override
  String get sendFeedback => 'Send Feedback';
  @override
  String get commonQuestions => 'Common Questions';

  // Admin Dashboard
  @override
  String get adminDashboard => 'Admin Dashboard';
  @override
  String get manageUsers => 'Manage Users';
  @override
  String get manageRooms => 'Manage Rooms';
  @override
  String get reports => 'Reports';
  @override
  String get statistics => 'Statistics';
  @override
  String get systemSettings => 'System Settings';

  // Navigation
  @override
  String get profile => 'Profile';

  // Errors
  @override
  String get somethingWentWrong => 'Something went wrong';
  @override
  String get networkError => 'Network error';
  @override
  String get tryAgain => 'Try again';
  @override
  String get connectionLost => 'Connection lost';
  @override
  String get serverError => 'Server error';
  @override
  String get unauthorized => 'Unauthorized';
  @override
  String get notFound => 'Not found';
}

/// Arabic strings implementation
class AppStringsAr extends AppStrings {
  // Common
  @override
  String get appName => 'SamaFox';
  @override
  String get loading => 'جاري التحميل...';
  @override
  String get error => 'خطأ';
  @override
  String get retry => 'إعادة المحاولة';
  @override
  String get cancel => 'إلغاء';
  @override
  String get save => 'حفظ';
  @override
  String get delete => 'حذف';
  @override
  String get edit => 'تعديل';
  @override
  String get done => 'تم';
  @override
  String get yes => 'نعم';
  @override
  String get no => 'لا';
  @override
  String get ok => 'موافق';
  @override
  String get search => 'بحث';

  @override
  String get settings => 'الإعدادات';
  @override
  String get back => 'رجوع';
  @override
  String get close => 'إغلاق';
  @override
  String get confirm => 'تأكيد';
  @override
  String get apply => 'تطبيق';
  @override
  String get clear => 'مسح';
  @override
  String get all => 'الكل';
  @override
  String get online => 'متصل';
  @override
  String get offline => 'غير متصل';

  // Splash Screen
  @override
  String get splashTagline => 'منصة الدردشة الصوتية والتواصل الاجتماعي';

  // Login Screen
  @override
  String get welcomeBack => 'مرحباً بعودتك!';
  @override
  String get signInToContinue => 'سجل الدخول لمتابعة رحلتك';
  @override
  String get email => 'البريد الإلكتروني';
  @override
  String get password => 'كلمة المرور';
  @override
  String get forgotPassword => 'نسيت كلمة المرور؟';
  @override
  String get signIn => 'تسجيل الدخول';
  @override
  String get continueAsGuest => 'المتابعة كضيف';
  @override
  String get orContinueWith => 'أو تابع باستخدام';
  @override
  String get google => 'جوجل';
  @override
  String get facebook => 'فيسبوك';
  @override
  String get dontHaveAccount => 'ليس لديك حساب؟ ';
  @override
  String get signUp => 'إنشاء حساب';
  @override
  String get forgotPasswordComingSoon => 'ميزة استعادة كلمة المرور قريباً';
  @override
  String get googleLoginComingSoon => 'تسجيل الدخول بجوجل قريباً';
  @override
  String get facebookLoginComingSoon => 'تسجيل الدخول بفيسبوك قريباً';
  @override
  String get registrationComingSoon => 'التسجيل قريباً';
  @override
  String get pleaseEnterEmail => 'الرجاء إدخال البريد الإلكتروني';
  @override
  String get pleaseEnterPassword => 'الرجاء إدخال كلمة المرور';
  @override
  String get guestLoginFailed => 'فشل تسجيل الدخول كضيف';
  @override
  String get createAccount => 'إنشاء حساب';
  @override
  String get passwordTooShort => 'يجب أن تكون كلمة المرور 6 أحرف على الأقل';
  @override
  String get registrationFailed => 'فشل التسجيل';
  @override
  String get invalidEmail => 'بريد إلكتروني غير صحيح';

  // Home Screen
  @override
  String get home => 'الرئيسية';
  @override
  String get searchComingSoon => 'البحث قريباً!';
  @override
  String get createFirstRoom => 'أنشئ غرفتك الأولى!';
  @override
  String get guest => 'ضيف';
  @override
  String get noRoomsAvailable => 'لا توجد غرف متاحة';
  @override
  String get createRoom => 'إنشاء غرفة';
  @override
  String get roomName => 'اسم الغرفة';
  @override
  String get description => 'الوصف';
  @override
  String get create => 'إنشاء';
  @override
  String get roomCreatedSuccessfully => 'تم إنشاء الغرفة بنجاح';
  @override
  String get failedToCreateRoom => 'فشل إنشاء الغرفة';
  @override
  String get fullName => 'الاسم الكامل';
  @override
  String get enterYourFullName => 'أدخل اسمك الكامل';
  @override
  String get nameIsRequired => 'الاسم مطلوب';
  @override
  String get confirmPassword => 'تأكيد كلمة المرور';
  @override
  String get confirmPasswordHint => 'تأكيد كلمة المرور';
  @override
  String get pleaseConfirmPassword => 'الرجاء تأكيد كلمة المرور';
  @override
  String get passwordsDoNotMatch => 'كلمات المرور غير متطابقة';
  @override
  String get genderOptional => 'النوع (اختياري)';
  @override
  String get selectGender => 'اختر النوع';
  @override
  String get countryOptional => 'الدولة (اختيارية)';
  @override
  String get selectCountry => 'اختر الدولة';
  @override
  String get searchCountry => 'ابحث عن الدولة';
  @override
  String get register => 'تسجيل';
  @override
  String get enterYourEmail => 'أدخل بريدك الإلكتروني';
  @override
  String get enterYourPassword => 'أدخل كلمة مرورك';
  @override
  String get passwordIsRequired => 'كلمة المرور مطلوبة';

  // Profile Screen
  @override
  String get myProfile => 'ملفي الشخصي';
  @override
  String get followers => 'المتابعون';
  @override
  String get following => 'المتابَعون';
  @override
  String get coins => 'العملات';
  @override
  String get accountDetails => 'تفاصيل الحساب';
  @override
  String get notProvided => 'غير محدد';
  @override
  String get notSet => 'غير مضبوط';
  @override
  String get phone => 'الهاتف';
  @override
  String get country => 'الدولة';
  @override
  String get level => 'المستوى';
  @override
  String get vipStatus => 'حالة VIP';
  @override
  String get vipLevel => 'مستوى VIP';
  @override
  String get noUserData => 'لا توجد بيانات مستخدم';
  @override
  String get editProfile => 'تعديل الملف الشخصي';
  @override
  String get bio => 'النبذة';
  @override
  String get dateOfBirth => 'تاريخ الميلاد';
  @override
  String get gender => 'الجنس';
  @override
  String get male => 'ذكر';
  @override
  String get female => 'أنثى';
  @override
  String get other => 'آخر';
  @override
  String get changeAvatar => 'تغيير الصورة';
  @override
  String get changeCover => 'تغيير الغلاف';
  @override
  String get profileUpdated => 'تم تحديث الملف الشخصي بنجاح';

  // Messages Screen
  @override
  String get messages => 'الرسائل';
  @override
  String get noConversationsYet => 'لا توجد محادثات بعد';
  @override
  String get justNow => 'الآن';
  @override
  String get noMessages => 'لا توجد رسائل';
  @override
  String get newMessage => 'رسالة جديدة';
  @override
  String get deleteConversation => 'حذف المحادثة';
  @override
  String get blockUser => 'حظر المستخدم';
  @override
  String get reportUser => 'الإبلاغ عن المستخدم';

  // Chat Conversation Screen
  @override
  String get chatWith => 'محادثة مع';
  @override
  String get typing => 'يكتب...';
  @override
  String get sendMessage => 'إرسال';
  @override
  String get voiceCall => 'مكالمة صوتية';
  @override
  String get videoCall => 'مكالمة فيديو';
  @override
  String get attachment => 'مرفق';
  @override
  String get emoji => 'إيموجي';
  @override
  String get photo => 'صورة';
  @override
  String get video => 'فيديو';
  @override
  String get document => 'مستند';
  @override
  String get location => 'الموقع';

  // Gifts Screen
  @override
  String get gifts => 'الهدايا';
  @override
  String get noGiftsAvailable => 'لا توجد هدايا متاحة';
  @override
  String get send => 'إرسال';
  @override
  String get giftSentSuccessfully => 'تم إرسال الهدية بنجاح';
  @override
  String get failedToSendGift => 'فشل إرسال الهدية';
  @override
  String get myGifts => 'هداياي';
  @override
  String get sendGift => 'إرسال هدية';
  @override
  String get giftStore => 'متجر الهدايا';
  @override
  String get price => 'السعر';
  @override
  String get buy => 'شراء';
  @override
  String get purchased => 'تم الشراء';

  // Gift Store Screen
  @override
  String get popularGifts => 'الهدايا الشائعة';
  @override
  String get newGifts => 'هدايا جديدة';
  @override
  String get premiumGifts => 'هدايا مميزة';
  @override
  String get balance => 'الرصيد';
  @override
  String get insufficientBalance => 'رصيد غير كافٍ';
  @override
  String get purchaseSuccessful => 'تم الشراء بنجاح';
  @override
  String get purchaseFailed => 'فشل الشراء';

  // Settings Screen
  @override
  String get language => 'اللغة';
  @override
  String get theme => 'المظهر';
  @override
  String get notifications => 'الإشعارات';
  @override
  String get privacy => 'الخصوصية';
  @override
  String get about => 'حول';
  @override
  String get logout => 'تسجيل الخروج';
  @override
  String get darkMode => 'الوضع الداكن';
  @override
  String get lightMode => 'الوضع الفاتح';
  @override
  String get accountSettings => 'إعدادات الحساب';
  @override
  String get changePassword => 'تغيير كلمة المرور';
  @override
  String get blockedUsers => 'المستخدمون المحظورون';
  @override
  String get deleteAccount => 'حذف الحساب';
  @override
  String get termsOfService => 'شروط الخدمة';
  @override
  String get privacyPolicy => 'سياسة الخصوصية';
  @override
  String get version => 'الإصدار';
  @override
  String get logoutConfirm => 'هل أنت متأكد من تسجيل الخروج؟';
  @override
  String get deleteAccountConfirm => 'هل أنت متأكد من حذف حسابك؟ لا يمكن التراجع عن هذا الإجراء.';

  // Room Screen
  @override
  String get members => 'الأعضاء';
  @override
  String get chat => 'الدردشة';
  @override
  String get typeMessage => 'اكتب رسالة...';
  @override
  String get mute => 'كتم';
  @override
  String get unmute => 'إلغاء الكتم';
  @override
  String get speaker => 'السماعة';
  @override
  String get leave => 'مغادرة';
  @override
  String get joinRoom => 'الانضمام للغرفة';
  @override
  String get leaveRoom => 'مغادرة الغرفة';
  @override
  String get roomFull => 'الغرفة ممتلئة';
  @override
  String get roomClosed => 'الغرفة مغلقة';
  @override
  String get inviteFriends => 'دعوة الأصدقاء';
  @override
  String get roomSettings => 'إعدادات الغرفة';
  @override
  String get kickUser => 'طرد المستخدم';
  @override
  String get banUser => 'حظر المستخدم';
  @override
  String get makeAdmin => 'جعله مشرف';
  @override
  String get makeSpeaker => 'جعله متحدث';
  @override
  String get muteMic => 'كتم الميكروفون';
  @override
  String get unmuteMic => 'إلغاء كتم الميكروفون';

  // Explore Screen
  @override
  String get explore => 'استكشاف';
  @override
  String get trending => 'الرائج';
  @override
  String get recommended => 'موصى به';
  @override
  String get categories => 'الفئات';
  @override
  String get seeAll => 'عرض الكل';
  @override
  String get noRooms => 'لا توجد غرف';
  @override
  String get filter => 'تصفية';
  @override
  String get sortBy => 'ترتيب حسب';
  @override
  String get popularity => 'الشعبية';
  @override
  String get newest => 'الأحدث';
  @override
  String get mostMembers => 'الأكثر أعضاء';

  // Wallet Screen
  @override
  String get wallet => 'المحفظة';
  @override
  String get myBalance => 'رصيدي';
  @override
  String get addCoins => 'إضافة عملات';
  @override
  String get transactions => 'المعاملات';
  @override
  String get transactionHistory => 'سجل المعاملات';
  @override
  String get deposit => 'إيداع';
  @override
  String get withdrawal => 'سحب';
  @override
  String get amount => 'المبلغ';
  @override
  String get date => 'التاريخ';
  @override
  String get status => 'الحالة';
  @override
  String get pending => 'قيد الانتظار';
  @override
  String get completed => 'مكتمل';
  @override
  String get failed => 'فشل';
  @override
  String get noTransactions => 'لا توجد معاملات بعد';

  // Premium/VIP Screen
  @override
  String get premium => 'بريميوم';
  @override
  String get upgradeToPremium => 'الترقية إلى بريميوم';
  @override
  String get premiumFeatures => 'ميزات بريميوم';
  @override
  String get exclusiveBadge => 'شارة حصرية';
  @override
  String get unlimitedGifts => 'هدايا غير محدودة';
  @override
  String get prioritySupport => 'دعم ذو أولوية';
  @override
  String get adFree => 'بدون إعلانات';
  @override
  String get customThemes => 'ثيمات مخصصة';
  @override
  String get subscribe => 'اشتراك';
  @override
  String get monthly => 'شهري';
  @override
  String get yearly => 'سنوي';
  @override
  String get lifetime => 'مدى الحياة';
  @override
  String get currentPlan => 'الخطة الحالية';
  @override
  String get renewsOn => 'يتجدد في';

  // Challenges Screen
  @override
  String get challenges => 'التحديات';
  @override
  String get dailyChallenges => 'التحديات اليومية';
  @override
  String get weeklyChallenges => 'التحديات الأسبوعية';
  @override
  String get completedChallenges => 'مكتمل';
  @override
  String get inProgress => 'قيد التنفيذ';
  @override
  String get notStarted => 'لم يبدأ';
  @override
  String get reward => 'المكافأة';
  @override
  String get claimReward => 'استلام المكافأة';
  @override
  String get noChallenges => 'لا توجد تحديات متاحة';
  @override
  String get progress => 'التقدم';

  // Leaderboard Screen
  @override
  String get leaderboard => 'لوحة المتصدرين';
  @override
  String get topUsers => 'أفضل المستخدمين';
  @override
  String get topRooms => 'أفضل الغرف';
  @override
  String get daily => 'يومي';
  @override
  String get weekly => 'أسبوعي';
  @override
  @override
  String get allTime => 'كل الوقت';
  @override
  String get rank => 'الترتيب';
  @override
  String get points => 'النقاط';
  @override
  String get yourRank => 'ترتيبك';

  // Achievements Screen
  @override
  String get achievements => 'الإنجازات';
  @override
  String get locked => 'مقفل';
  @override
  String get unlocked => 'مفتوح';
  @override
  String get earnedOn => 'تم الحصول عليه في';
  @override
  String get noAchievements => 'لا توجد إنجازات بعد';
  @override
  String get totalAchievements => 'إجمالي الإنجازات';

  // Search Screen
  @override
  String get searchUsers => 'بحث عن مستخدمين';
  @override
  String get searchRooms => 'بحث عن غرف';
  @override
  String get recentSearches => 'عمليات البحث الأخيرة';
  @override
  String get noResults => 'لا توجد نتائج';
  @override
  String get searchHint => 'ابحث عن مستخدمين، غرف...';

  // Notifications Screen
  @override
  String get notification => 'الإشعارات';
  @override
  String get markAllRead => 'تعليم الكل كمقروء';
  @override
  String get noNotifications => 'لا توجد إشعارات';
  @override
  String get newFollower => 'بدأ بمتابعتك';
  @override
  @override
  String get giftReceived => 'أرسل لك هدية';
  @override
  String get roomInvite => 'دعاك إلى غرفة';

  // Analytics Screen
  @override
  String get analytics => 'التحليلات';
  @override
  String get roomAnalytics => 'تحليلات الغرفة';
  @override
  String get totalVisitors => 'إجمالي الزوار';
  @override
  String get activeMembers => 'الأعضاء النشطون';
  @override
  String get peakHours => 'ساعات الذروة';
  @override
  String get engagement => 'التفاعل';
  @override
  String get insights => 'الرؤى';

  // Help & Support Screen
  @override
  String get help => 'المساعدة والدعم';
  @override
  String get helpCenter => 'مركز المساعدة';
  @override
  String get faq => 'الأسئلة الشائعة';
  @override
  String get contactSupport => 'الاتصال بالدعم';
  @override
  String get reportProblem => 'الإبلاغ عن مشكلة';
  @override
  String get feedback => 'التعليقات';
  @override
  String get sendFeedback => 'إرسال تعليق';
  @override
  String get commonQuestions => 'الأسئلة الشائعة';

  // Admin Dashboard
  @override
  String get adminDashboard => 'لوحة الإدارة';
  @override
  String get manageUsers => 'إدارة المستخدمين';
  @override
  String get manageRooms => 'إدارة الغرف';
  @override
  String get reports => 'التقارير';
  @override
  String get statistics => 'الإحصائيات';
  @override
  String get systemSettings => 'إعدادات النظام';

  // Navigation
  @override
  String get profile => 'الملف الشخصي';

  // Errors
  @override
  String get somethingWentWrong => 'حدث خطأ ما';
  @override
  String get networkError => 'خطأ في الشبكة';
  @override
  String get tryAgain => 'حاول مرة أخرى';
  @override
  String get connectionLost => 'فقد الاتصال';
  @override
  String get serverError => 'خطأ في الخادم';
  @override
  String get unauthorized => 'غير مصرح';
  @override
  String get notFound => 'غير موجود';
}
