import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:math' show max;
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'firebase_options.dart';

// Models for structured user data
class DailyUserStats {
  final String date; // YYYY-MM-DD format
  final int cigarettesSmoked;
  final int longestNonCigaretteStreak; // in days
  final double? avgTimeBetweenCigarettes; // in minutes, null if 0 or 1 cigarettes

  DailyUserStats({
    required this.date,
    required this.cigarettesSmoked,
    required this.longestNonCigaretteStreak,
    this.avgTimeBetweenCigarettes,
  });

  // Convert to JSON for Firebase
  Map<String, dynamic> toJson() => {
    'date': date,
    'cigarettesSmoked': cigarettesSmoked,
    'longestNonCigaretteStreak': longestNonCigaretteStreak,
    'avgTimeBetweenCigarettes': avgTimeBetweenCigarettes,
  };

  // Create from JSON
  factory DailyUserStats.fromJson(Map<String, dynamic> json) => DailyUserStats(
    date: json['date'] as String,
    cigarettesSmoked: json['cigarettesSmoked'] as int,
    longestNonCigaretteStreak: json['longestNonCigaretteStreak'] as int,
    avgTimeBetweenCigarettes: json['avgTimeBetweenCigarettes'] as double?,
  );
}

class UserStats {
  final DailyUserStats todayStats;
  final List<DailyUserStats> history; // last 120 days

  UserStats({
    required this.todayStats,
    required this.history,
  });

  // Compute current week average
  double get currentWeekAverage {
    int total = 0;
    int count = 0;
    for (final day in history.take(7)) {
      total += day.cigarettesSmoked;
      count++;
    }
    return count > 0 ? total / count : 0.0;
  }

  // Compute 4-month average
  double get fourMonthAverage {
    int total = 0;
    for (final day in history) {
      total += day.cigarettesSmoked;
    }
    return history.isNotEmpty ? total / history.length : 0.0;
  }

  // Get time since last cigarette
  Duration? get timeSinceLastCigarette {
    if (todayStats.cigarettesSmoked == 0 && history.skip(1).isEmpty) {
      return null; // No cigarettes ever recorded
    }
    // Find the most recent day with a cigarette
    for (final day in history) {
      if (day.cigarettesSmoked > 0) {
        final dayDate = DateTime.parse(day.date);
        return DateTime.now().difference(dayDate);
      }
    }
    return null;
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  // Uncomment the line below to populate with mock data for testing
  // await CigaretteDataService.populateMockData();
  runApp(const MainApp());
}

class MainApp extends StatelessWidget {
  const MainApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: const AuthWrapper(),
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.red,
          brightness: Brightness.dark,
        ),
      ),
    );
  }
}

// Auth wrapper - shows login if not authenticated, main app if authenticated
class AuthWrapper extends StatelessWidget {
  const AuthWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    // Always land on HomePage. If user is logged in, pass userId; otherwise null.
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final userId = snapshot.data?.uid;
        return HomePage(userId: userId);
      },
    );
  }
}

// Login page
class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  late TextEditingController _emailController;
  late TextEditingController _passwordController;
  bool _isLoading = false;
  bool _isSignUp = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _emailController = TextEditingController();
    _passwordController = TextEditingController();
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _handleAuth() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      if (_isSignUp) {
        await FirebaseService.signUp(
          _emailController.text.trim(),
          _passwordController.text,
        );
        await _afterSignIn();
      } else {
        await FirebaseService.signIn(
          _emailController.text.trim(),
          _passwordController.text,
        );
        await _afterSignIn();
      }
    } catch (e) {
      setState(() {
        _errorMessage = e.toString();
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  // After a successful sign-in/signup, ask user whether to sync local data or use online data
  Future<void> _afterSignIn() async {
    final user = FirebaseService.getCurrentUser();
    if (user == null) return;

    // Show a prompt asking how to handle data
    final choice = await showDialog<String?>(
      context: context,
      barrierDismissible: true,
      builder: (context) {
        return AlertDialog(
          title: const Text('Sync Data'),
          content: const Text(
            'Would you like to sync your local data to your online account, or replace local data with the online data?\n\nChoose "Sync Local" to upload your current local entries to the cloud.\nChoose "Use Online" to overwrite local data with what is stored in your account.'
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop('cancel'),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop('use_online'),
              child: const Text('Use Online'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop('sync_local'),
              child: const Text('Sync Local'),
            ),
          ],
        );
      },
    );

    try {
      if (choice == 'sync_local') {
        await FirebaseService.syncLocalDataToFirestore(user.uid);
        await FirebaseService.updateLastSyncTime(user.uid);
      } else if (choice == 'use_online') {
        await FirebaseService.replaceLocalWithFirestoreData(user.uid);
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Sync error: $e';
      });
    }

    // Close the login page/modal
    if (Navigator.of(context).canPop()) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const SizedBox(height: 60),
                const Text(
                  'Cigarette Counter',
                  style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                Text(
                  _isSignUp ? 'Create an Account' : 'Welcome Back',
                  style: TextStyle(fontSize: 16, color: Colors.grey[400]),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 60),
                // Email field
                TextField(
                  controller: _emailController,
                  decoration: InputDecoration(
                    hintText: 'Email',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    contentPadding: const EdgeInsets.all(16),
                  ),
                  keyboardType: TextInputType.emailAddress,
                  enabled: !_isLoading,
                ),
                const SizedBox(height: 16),
                // Password field
                TextField(
                  controller: _passwordController,
                  decoration: InputDecoration(
                    hintText: 'Password',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    contentPadding: const EdgeInsets.all(16),
                  ),
                  obscureText: true,
                  enabled: !_isLoading,
                ),
                const SizedBox(height: 24),
                // Social login buttons
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _isLoading
                            ? null
                            : () async {
                                setState(() { _isLoading = true; _errorMessage = null; });
                                try {
                                  await FirebaseService.signInWithGoogle();
                                  await _afterSignIn();
                                } catch (e) {
                                  setState(() { _errorMessage = e.toString(); });
                                } finally {
                                  setState(() { _isLoading = false; });
                                }
                              },
                        icon: const Icon(Icons.account_circle),
                        label: const Text('Sign in with Google'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _isLoading
                            ? null
                            : () async {
                                setState(() { _isLoading = true; _errorMessage = null; });
                                try {
                                  await FirebaseService.signInWithApple();
                                  await _afterSignIn();
                                } catch (e) {
                                  setState(() { _errorMessage = e.toString(); });
                                } finally {
                                  setState(() { _isLoading = false; });
                                }
                              },
                        icon: const Icon(Icons.apple),
                        label: const Text('Sign in with Apple'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                // Error message
                if (_errorMessage != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16.0),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.red.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.red),
                      ),
                      child: Text(
                        _errorMessage!,
                        style: const TextStyle(color: Colors.red, fontSize: 12),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                // Auth button
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _handleAuth,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                      disabledBackgroundColor: Colors.red.withOpacity(0.5),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: _isLoading
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor:
                                  AlwaysStoppedAnimation<Color>(Colors.white),
                            ),
                          )
                        : Text(
                            _isSignUp ? 'Sign Up' : 'Sign In',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                  ),
                ),
                const SizedBox(height: 16),
                // Toggle button
                TextButton(
                  onPressed: _isLoading
                      ? null
                      : () {
                          setState(() {
                            _isSignUp = !_isSignUp;
                            _errorMessage = null;
                          });
                        },
                  child: Text(
                    _isSignUp
                        ? 'Already have an account? Sign In'
                        : "Don't have an account? Sign Up",
                    style: const TextStyle(color: Colors.blue, fontSize: 14),
                  ),
                ),
                const SizedBox(height: 24),
                // Back / Return button
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () {
                      if (Navigator.of(context).canPop()) Navigator.of(context).pop();
                    },
                    icon: const Icon(Icons.arrow_back),
                    label: const Text('Back'),
                  ),
                ),
                const SizedBox(height: 36),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class HomePage extends StatefulWidget {
  final String? userId;

  const HomePage({super.key, this.userId});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _selectedIndex = 0;

  late final List<Widget> _pages = [
    MainPage(onUpdate: _refresh),
    const FriendsPage(),
    StatsPage(onUpdate: _refresh),
  ];

  void _refresh() {
    setState(() {});
  }

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _pages[_selectedIndex],
      appBar: null, // AppBar is in each page now
      bottomNavigationBar: BottomNavigationBar(
        items: const <BottomNavigationBarItem>[
          BottomNavigationBarItem(
            icon: Icon(Icons.home),
            label: 'Main',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.people),
            label: 'Friends',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.bar_chart),
            label: 'Stats',
          ),
        ],
        currentIndex: _selectedIndex,
        onTap: _onItemTapped,
      ),
    );
  }
}

// Firebase Service
class FirebaseService {
  static final FirebaseAuth _auth = FirebaseAuth.instance;
  static final FirebaseFirestore _db = FirebaseFirestore.instance;

  // Create user document in Firestore after signup
  static Future<void> createUserProfile(String userId, String email) async {
    try {
      final userDoc = _db.collection('users').doc(userId);
      
      // Create profile document
      await userDoc.set({
        'email': email,
        'createdAt': Timestamp.now(),
        'lastUpdated': Timestamp.now(),
        'displayName': email.split('@')[0], // Use email prefix as default name
      });

      print('User profile created for $userId');
    } catch (e) {
      print('Error creating user profile: $e');
      rethrow;
    }
  }

  // Sign up new user
  static Future<UserCredential?> signUp(String email, String password) async {
    try {
      final credential = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
      
      // Create user profile structure in Firestore
      if (credential.user != null) {
        await createUserProfile(credential.user!.uid, email);
      }
      
      return credential;
    } on FirebaseAuthException catch (e) {
      print('Firebase Auth Error: ${e.message}');
      rethrow;
    }
  }

  // Sign in existing user
  static Future<UserCredential?> signIn(String email, String password) async {
    try {
      return await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
    } on FirebaseAuthException catch (e) {
      print('Firebase Auth Error: ${e.message}');
      rethrow;
    }
  }

  // Sign out user
  static Future<void> signOut() async {
    try {
      await _auth.signOut();
    } catch (e) {
      print('Error signing out: $e');
      rethrow;
    }
  }

  // Get current user
  static User? getCurrentUser() {
    return _auth.currentUser;
  }

  // Sync local data to Firestore (upload all stored data)
  static Future<void> syncLocalDataToFirestore(String userId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final allKeys = prefs.getKeys();
      final batch = _db.batch();

      for (final key in allKeys) {
        // Only sync date keys (YYYY-MM-DD format)
        if (key.length == 10 && key.contains('-')) {
          try {
            final dailyStats = await CigaretteDataService.buildDailyStats(key);
            
            final docRef = _db
                .collection('users')
                .doc(userId)
                .collection('dailyStats')
                .doc(key);
            
            batch.set(docRef, dailyStats.toJson());
          } catch (_) {}
        }
      }

      await batch.commit();
      print('Local data synced to Firestore for user $userId');
    } catch (e) {
      print('Error syncing data to Firestore: $e');
      rethrow;
    }
  }

  // Save a single day's stats to Firestore
  static Future<void> saveDailyStatsToFirestore(
    String userId,
    DailyUserStats dailyStats,
  ) async {
    try {
      await _db
          .collection('users')
          .doc(userId)
          .collection('dailyStats')
          .doc(dailyStats.date)
          .set(dailyStats.toJson());
    } catch (e) {
      print('Error saving daily stats to Firestore: $e');
      rethrow;
    }
  }

  // Fetch all user data from Firestore
  static Future<Map<String, int>> fetchHeatmapDataFromFirestore(
    String userId,
  ) async {
    try {
      final snapshot = await _db
          .collection('users')
          .doc(userId)
          .collection('dailyStats')
          .orderBy('date')
          .get();

      final heatmapData = <String, int>{};
      for (final doc in snapshot.docs) {
        final data = doc.data();
        heatmapData[doc.id] = data['cigarettesSmoked'] as int? ?? 0;
      }

      return heatmapData;
    } catch (e) {
      print('Error fetching data from Firestore: $e');
      return {};
    }
  }

  // Get user profile from Firestore
  static Future<Map<String, dynamic>?> getUserProfile(String userId) async {
    try {
      final doc = await _db.collection('users').doc(userId).get();
      return doc.data();
    } catch (e) {
      print('Error fetching user profile: $e');
      return null;
    }
  }

  // Update last sync time
  static Future<void> updateLastSyncTime(String userId) async {
    try {
      await _db.collection('users').doc(userId).update({
        'lastUpdated': Timestamp.now(),
      });
    } catch (e) {
      print('Error updating last sync time: $e');
    }
  }

  // Web-friendly Google sign-in (uses popup); mobile requires google_sign_in package
  static Future<UserCredential?> signInWithGoogle() async {
    try {
      if (kIsWeb) {
        final provider = GoogleAuthProvider();
        return await _auth.signInWithPopup(provider);
      } else {
        // Mobile flow is not implemented here; recommend adding `google_sign_in` package.
        throw UnimplementedError('Google sign-in on mobile requires the google_sign_in package.');
      }
    } catch (e) {
      print('Error during Google sign-in: $e');
      rethrow;
    }
  }

  // Placeholder for Apple sign-in. On web this is typically not used; on iOS/macOS add `sign_in_with_apple`.
  static Future<UserCredential?> signInWithApple() async {
    try {
      // Apple sign-in implementation depends on platform packages. For now, throw to indicate missing support.
      throw UnimplementedError('Apple sign-in requires `sign_in_with_apple` package and platform configuration.');
    } catch (e) {
      print('Error during Apple sign-in: $e');
      rethrow;
    }
  }

  // Replace local SharedPreferences date entries with Firestore data (overwrites matching date keys)
  static Future<void> replaceLocalWithFirestoreData(String userId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final remote = await fetchHeatmapDataFromFirestore(userId);

      // Optionally clear existing date keys before applying remote dataset
      final allKeys = prefs.getKeys();
      for (final key in allKeys) {
        if (key.length == 10 && key.contains('-')) {
          await prefs.remove(key);
        }
      }

      for (final entry in remote.entries) {
        await prefs.setInt(entry.key, entry.value);
      }

      await updateLastSyncTime(userId);
      print('Replaced local data with Firestore data for $userId');
    } catch (e) {
      print('Error replacing local data: $e');
      rethrow;
    }
  }
}

// Data Service
class CigaretteDataService {
  static Future<void> addCigarette() async {
    final prefs = await SharedPreferences.getInstance();
    final today = _getTodayKey();
    final count = prefs.getInt(today) ?? 0;
    await prefs.setInt(today, count + 1);
    await _pruneOldData(); // Clean up data older than 1 year
    
    // Sync to Firestore if user is logged in
    final user = FirebaseService.getCurrentUser();
    if (user != null) {
      try {
        final dailyStats = await buildDailyStats(today);
        await FirebaseService.saveDailyStatsToFirestore(user.uid, dailyStats);
      } catch (e) {
        print('Warning: Could not sync to Firestore: $e');
      }
    }
  }

  static Future<Map<String, int>> getLast4Months() async {
    final prefs = await SharedPreferences.getInstance();
    final data = <String, int>{};

    for (int i = 119; i >= 0; i--) {
      final date = DateTime.now().subtract(Duration(days: i));
      final key = _getDateKey(date);
      final count = prefs.getInt(key) ?? 0;
      data[key] = count;
    }

    return data;
  }

  static Future<int> getTodayCount() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_getTodayKey()) ?? 0;
  }

  static Future<double> getAverageCigarettesPerDay() async {
    final data = await getLast4Months();
    int total = 0;
    for (final count in data.values) {
      total += count;
    }
    return total / 120;
  }

  static Future<DateTime?> getLastCigaretteTime() async {
    final prefs = await SharedPreferences.getInstance();
    final timestamp = prefs.getInt('last_cigarette_time');
    if (timestamp == null) return null;
    return DateTime.fromMillisecondsSinceEpoch(timestamp);
  }

  static Future<void> _recordLastCigaretteTime() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('last_cigarette_time', DateTime.now().millisecondsSinceEpoch);
  }

  // Returns a list of weekly averages for the last [weeks] weeks.
  // Each item is a map with keys: 'start' (String), 'total' (int), 'avg' (double)
  static Future<List<Map<String, dynamic>>> getWeeklyAverages(int weeks) async {
    final prefs = await SharedPreferences.getInstance();
    // Build list of last 120 days (oldest->newest)
    final days = <Map<String, dynamic>>[];
    for (int i = 119; i >= 0; i--) {
      final date = DateTime.now().subtract(Duration(days: i));
      final key = _getDateKey(date);
      final count = prefs.getInt(key) ?? 0;
      days.add({'date': date, 'key': key, 'count': count});
    }

    // Group into weeks starting from the oldest in the list.
    final List<Map<String, dynamic>> result = [];
    final int daysPerWeek = 7;
    // We'll take the most recent `weeks` weeks
    final int totalWeeksAvailable = (days.length / daysPerWeek).floor();
    final int takeWeeks = weeks.clamp(1, totalWeeksAvailable);

    for (int w = 0; w < takeWeeks; w++) {
      final start = days.length - ((w + 1) * daysPerWeek);
      final end = start + daysPerWeek;
      final weekSlice = days.sublist(start, end);
      int total = 0;
      for (final d in weekSlice) {
        total += (d['count'] as int);
      }
      final avg = total / daysPerWeek;
      final startDate = weekSlice.first['date'] as DateTime;
      result.add({
        'start': _getDateKey(startDate),
        'total': total,
        'avg': avg,
      });
    }

    // result currently is newest-first (because we iterated w from 0); reverse to oldest-first
    return result.reversed.toList();
  }

  // Returns the average cigarettes per day for the current (most recent) 7-day period
  static Future<double> getCurrentWeekAverage() async {
    final prefs = await SharedPreferences.getInstance();
    int total = 0;
    for (int i = 0; i < 7; i++) {
      final date = DateTime.now().subtract(Duration(days: i));
      final key = _getDateKey(date);
      total += prefs.getInt(key) ?? 0;
    }
    return total / 7.0;
  }

  // Calculate longest non-cigarette streak up to a given date
  static Future<int> calculateLongestStreak(String upToDate) async {
    final data = await getLast4Months();
    final entries = data.entries.toList();
    final targetIndex = entries.indexWhere((e) => e.key == upToDate);
    if (targetIndex == -1) return 0;

    int longestStreak = 0;
    int currentStreak = 0;

    for (int i = 0; i <= targetIndex; i++) {
      if (entries[i].value == 0) {
        currentStreak++;
        longestStreak = max(longestStreak, currentStreak);
      } else {
        currentStreak = 0;
      }
    }

    return longestStreak;
  }

  // Calculate average time between cigarettes for a given day
  static Future<double?> calculateAvgTimeBetweenCigarettes(String dateKey) async {
    final prefs = await SharedPreferences.getInstance();
    final count = prefs.getInt(dateKey) ?? 0;
    if (count <= 1) return null; // Need at least 2 to compute average

    // For now, return a simple estimate based on cigarettes per day
    // In future with timestamp tracking, this would be more accurate
    const wakingHours = 16.0; // assume 8 hours sleep
    final minutesPerDay = wakingHours * 60;
    return minutesPerDay / count;
  }

  // Build a DailyUserStats for a specific date
  static Future<DailyUserStats> buildDailyStats(String dateKey) async {
    final prefs = await SharedPreferences.getInstance();
    final cigarettesSmoked = prefs.getInt(dateKey) ?? 0;
    final longestStreak = await calculateLongestStreak(dateKey);
    final avgTime = await calculateAvgTimeBetweenCigarettes(dateKey);

    return DailyUserStats(
      date: dateKey,
      cigarettesSmoked: cigarettesSmoked,
      longestNonCigaretteStreak: longestStreak,
      avgTimeBetweenCigarettes: avgTime,
    );
  }

  // Build complete UserStats with today's stats and full history
  static Future<UserStats> getUserStats() async {
    final today = _getTodayKey();
    final todayStats = await buildDailyStats(today);

    final data = await getLast4Months();
    final history = <DailyUserStats>[];

    for (final entry in data.entries) {
      final dayStats = await buildDailyStats(entry.key);
      history.add(dayStats);
    }

    return UserStats(todayStats: todayStats, history: history);
  }

  // Prune data older than 1 year
  static Future<void> _pruneOldData() async {
    final prefs = await SharedPreferences.getInstance();
    final oneYearAgo = DateTime.now().subtract(const Duration(days: 365));
    final allKeys = prefs.getKeys();

    for (final key in allKeys) {
      // Only process date keys (YYYY-MM-DD format)
      if (key.length == 10 && key.contains('-')) {
        try {
          final dateStr = key;
          final date = DateTime.parse(dateStr);
          if (date.isBefore(oneYearAgo)) {
            await prefs.remove(key);
          }
        } catch (_) {
          // Skip non-date keys
        }
      }
    }
  }

  // Build heatmap data from first recorded date to today, filling gaps with 0s
  static Future<Map<String, int>> getHeatmapData() async {
    final prefs = await SharedPreferences.getInstance();
    final allKeys = prefs.getKeys();
    DateTime? firstDate;

    // Find the oldest date in the data
    for (final key in allKeys) {
      if (key.length == 10 && key.contains('-')) {
        try {
          final date = DateTime.parse(key);
          if (firstDate == null || date.isBefore(firstDate)) {
            firstDate = date;
          }
        } catch (_) {}
      }
    }

    // If no data exists, return empty
    if (firstDate == null) {
      return {};
    }

    // Fill from first date to today, including gaps
    final heatmapData = <String, int>{};
    final today = DateTime.now();
    var current = firstDate;

    while (!current.isAfter(today)) {
      final key = _getDateKey(current);
      heatmapData[key] = prefs.getInt(key) ?? 0;
      current = current.add(const Duration(days: 1));
    }

    return heatmapData;
  }

  // Populate with mock data for testing (last 2 months with varied data)
  static Future<void> populateMockData() async {
    final prefs = await SharedPreferences.getInstance();
    final today = DateTime.now();
    final twoMonthsAgo = today.subtract(const Duration(days: 60));

    var current = twoMonthsAgo;
    final random = DateTime.now().microsecond % 100; // Pseudo-random seed

    int dayCount = 0;
    while (!current.isAfter(today)) {
      final key = _getDateKey(current);
      
      // Generate varied cigarette counts
      int cigaretteCount;
      if (dayCount % 7 == 0) {
        // Every week has a perfect day (0 cigarettes)
        cigaretteCount = 0;
      } else if (dayCount % 7 == 1) {
        // Low day
        cigaretteCount = (random + dayCount) % 5;
      } else if (dayCount % 7 == 6) {
        // High day
        cigaretteCount = 15 + (random + dayCount) % 8;
      } else {
        // Normal variation
        cigaretteCount = 5 + (random + dayCount) % 12;
      }

      await prefs.setInt(key, cigaretteCount);
      current = current.add(const Duration(days: 1));
      dayCount++;
    }

    print('Mock data populated for last 60 days');
  }

  static String _getTodayKey() {
    return _getDateKey(DateTime.now());
  }

  static String _getDateKey(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }
}

class MainPage extends StatefulWidget {
  final VoidCallback onUpdate;

  const MainPage({super.key, required this.onUpdate});

  @override
  State<MainPage> createState() => _MainPageState();
}

class _MainPageState extends State<MainPage> with WidgetsBindingObserver {
  late Future<int> _todayCount;
  late Future<double> _average;
  String _timeSinceLastCigarette = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadData();
    _startTimer();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _loadData();
      _updateTimeSinceLastCigarette();
    }
  }

  void _loadData() {
    setState(() {
      _todayCount = CigaretteDataService.getTodayCount();
      _average = CigaretteDataService.getCurrentWeekAverage();
    });
    _updateTimeSinceLastCigarette();
  }

  void _startTimer() {
    Future.delayed(const Duration(seconds: 1), () {
      if (mounted) {
        _updateTimeSinceLastCigarette();
        _startTimer();
      }
    });
  }

  Future<void> _updateTimeSinceLastCigarette() async {
    final lastTime = await CigaretteDataService.getLastCigaretteTime();
    if (lastTime == null) {
      setState(() => _timeSinceLastCigarette = 'No cigarettes recorded');
      return;
    }

    final now = DateTime.now();
    final diff = now.difference(lastTime);

    String timeStr;
    if (diff.inSeconds < 60) {
      timeStr = '${diff.inSeconds}s ago';
    } else if (diff.inMinutes < 60) {
      timeStr = '${diff.inMinutes}m ago';
    } else if (diff.inHours < 24) {
      timeStr = '${diff.inHours}h ago';
    } else {
      timeStr = '${diff.inDays}d ago';
    }

    setState(() => _timeSinceLastCigarette = timeStr);
  }

  Future<void> _onSmokedCigarette() async {
    await CigaretteDataService.addCigarette();
    await CigaretteDataService._recordLastCigaretteTime();
    _loadData();
    widget.onUpdate();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Main'),
        centerTitle: true,
        elevation: 0,
        actions: [
          PopupMenuButton<String>(
            onSelected: (value) async {
              if (value == 'logout') {
                await FirebaseService.signOut();
              }
            },
            itemBuilder: (BuildContext context) => [
              const PopupMenuItem(
                value: 'logout',
                child: Text('Logout'),
              ),
            ],
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 32.0),
            child: SizedBox(
              width: double.infinity,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // Just Smoked Button
                  SizedBox(
                    width: double.infinity,
                    height: 60,
                    child: ElevatedButton(
                      onPressed: _onSmokedCigarette,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 4,
                      ),
                      child: const Text(
                        'Just Smoked a Cigarette',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                  const SizedBox(height: 60),
                  
                  // Today's Count Card
                  _buildStatCard(
                    label: 'Cigarettes Today',
                    valueBuilder: () => FutureBuilder<int>(
                      future: _todayCount,
                      builder: (context, snapshot) {
                        final count = snapshot.data ?? 0;
                        return Text(
                          '$count',
                          style: const TextStyle(
                            fontSize: 56,
                            fontWeight: FontWeight.bold,
                            color: Colors.red,
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 32),
                  
                  // Average Card (This Week)
                  _buildStatCard(
                    label: 'Average per Day (This Week)',
                    valueBuilder: () => FutureBuilder<double>(
                      future: _average,
                      builder: (context, snapshot) {
                        final avg = snapshot.data ?? 0.0;
                        return Text(
                          avg.toStringAsFixed(1),
                          style: const TextStyle(
                            fontSize: 48,
                            fontWeight: FontWeight.bold,
                            color: Colors.blue,
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 32),
                  
                  // Time Since Last Cigarette Card
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: Colors.green.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.green, width: 2),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        const Text(
                          'Time Since Last Cigarette',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey,
                            fontWeight: FontWeight.w500,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          _timeSinceLastCigarette,
                          style: const TextStyle(
                            fontSize: 32,
                            fontWeight: FontWeight.bold,
                            color: Colors.green,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          // Open full-page LoginPage to avoid embedding a Scaffold inside a scrollable sheet
          await Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const LoginPage()),
          );

          // refresh UI after possible auth changes
          _loadData();
          widget.onUpdate();
        },
        label: const Text('Login'),
        icon: const Icon(Icons.login),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
    );
  }

  Widget _buildStatCard({
    required String label,
    required Widget Function() valueBuilder,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 14,
              color: Colors.grey,
              fontWeight: FontWeight.w500,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          valueBuilder(),
        ],
      ),
    );
  }
}

class FriendsPage extends StatelessWidget {
  const FriendsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Friends'),
        centerTitle: true,
        elevation: 0,
      ),
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Icon(
                  Icons.people_outline,
                  size: 64,
                  color: Colors.grey[400],
                ),
                const SizedBox(height: 24),
                Text(
                  'Friends',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                Text(
                  'Coming soon...',
                  style: TextStyle(
                    fontSize: 16,
                    color: Colors.grey[600],
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class StatsPage extends StatefulWidget {
  final VoidCallback onUpdate;

  const StatsPage({super.key, required this.onUpdate});

  @override
  State<StatsPage> createState() => _StatsPageState();
}

class _StatsPageState extends State<StatsPage> {
  late Future<Map<String, int>> _data;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  void _loadData() {
    setState(() {
      _data = CigaretteDataService.getHeatmapData();
    });
  }

  Future<int> _calculateLongestStreak(Map<String, int> data, String selectedDate) async {
    final entries = data.entries.toList();
    final selectedIndex = entries.indexWhere((e) => e.key == selectedDate);
    if (selectedIndex == -1) return 0;

    int longestStreak = 0;
    int currentStreak = 0;

    for (int i = 0; i <= selectedIndex; i++) {
      if (entries[i].value == 0) {
        currentStreak++;
        longestStreak = max(longestStreak, currentStreak);
      } else {
        currentStreak = 0;
      }
    }

    return longestStreak;
  }

  void _showDayDetailsModal(String date, int cigarettesSmoked, Map<String, int> allData) {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (BuildContext context) {
        return GestureDetector(
          onTap: () => Navigator.of(context).pop(),
          child: Material(
            color: Colors.black.withOpacity(0.6),
            child: GestureDetector(
              onTap: () {}, // Prevent closing when tapping inside dialog
              child: Center(
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 24.0),
                  padding: const EdgeInsets.all(28.0),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        date,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.grey,
                        ),
                      ),
                      const SizedBox(height: 28),
                      // Cigarettes smoked
                      Column(
                        children: [
                          const Text(
                            'Cigarettes Smoked',
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '$cigarettesSmoked',
                            style: const TextStyle(
                              fontSize: 48,
                              fontWeight: FontWeight.bold,
                              color: Colors.red,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 32),
                      // Longest streak
                      FutureBuilder<int>(
                        future: _calculateLongestStreak(allData, date),
                        builder: (context, snapshot) {
                          final streak = snapshot.data ?? 0;
                          return Column(
                            children: [
                              const Text(
                                'Longest Non-Cigarette Streak',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.grey,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                '$streak ${streak == 1 ? 'day' : 'days'}',
                                style: const TextStyle(
                                  fontSize: 42,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.green,
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                      const SizedBox(height: 32),
                      ElevatedButton(
                        onPressed: () => Navigator.of(context).pop(),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.grey[200],
                          foregroundColor: Colors.black,
                        ),
                        child: const Text('Close'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Stats'),
        centerTitle: true,
        elevation: 0,
      ),
      body: FutureBuilder<Map<String, int>>(
        future: _data,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final data = snapshot.data!;
          final maxValue = data.values.fold<int>(0, (max, val) => val > max ? val : max).toDouble();
          final maxValueSafe = maxValue > 0 ? maxValue : 1;
          final entries = data.entries.toList();
          
          // Reverse the entries so today is at the top
          final reversedEntries = entries.reversed.toList();

          return SafeArea(
            child: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 24.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    const Text(
                      'Cigarette Heatmap',
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'From first recorded day to today',
                      style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 32),
                    // Heatmap with date labels
                    Center(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            // Week rows - dynamically calculated based on data
                            ...List.generate((reversedEntries.length / 7).ceil(), (weekIndex) {
                              final startIndex = weekIndex * 7;
                              final endIndex = (startIndex + 7 < reversedEntries.length) ? startIndex + 7 : reversedEntries.length;
                              final weekEntries = reversedEntries.sublist(startIndex, endIndex);

                              return Padding(
                                padding: const EdgeInsets.only(bottom: 28.0),
                                child: Column(
                                  children: [
                                    // Week header with date range
                                    Text(
                                      weekEntries.first.key,
                                      style: const TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                        color: Colors.grey,
                                      ),
                                      textAlign: TextAlign.center,
                                    ),
                                    const SizedBox(height: 8),
                                    // Heatmap cells for the week
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: weekEntries.map((entry) {
                                        final value = entry.value.toDouble();

                                        Color boxColor;
                                        if (value == 0) {
                                          boxColor = Colors.grey[300]!;
                                        } else {
                                          // Scale color gradient: 0 = green, 20+ = red
                                          final ratio = (value / 20).clamp(0.0, 1.0);
                                          boxColor = Color.lerp(
                                            Colors.green[400],
                                            Colors.red[600],
                                            ratio,
                                          )!;
                                        }

                                        return Padding(
                                          padding: const EdgeInsets.only(right: 10.0),
                                          child: GestureDetector(
                                            onTap: () {
                                              _showDayDetailsModal(entry.key, entry.value, data);
                                            },
                                            child: Tooltip(
                                              message: '${entry.key}\n${entry.value} cigarettes',
                                              child: Container(
                                                width: 44,
                                                height: 44,
                                                decoration: BoxDecoration(
                                                  color: boxColor,
                                                  borderRadius: BorderRadius.circular(4),
                                                  border: Border.all(
                                                    color: Colors.grey[400]!,
                                                    width: 1,
                                                  ),
                                                ),
                                                child: Center(
                                                  child: entry.value == 0
                                                      ? const Text(
                                                          '🎉',
                                                          style: TextStyle(fontSize: 20),
                                                        )
                                                      : Text(
                                                          '${entry.value}',
                                                          style: TextStyle(
                                                            fontSize: 12,
                                                            fontWeight: FontWeight.bold,
                                                            color: value > maxValueSafe * 0.5 ? Colors.white : Colors.black87,
                                                          ),
                                                        ),
                                                ),
                                              ),
                                            ),
                                          ),
                                        );
                                      }).toList(),
                                    ),
                                  ],
                                ),
                              );
                            }).toList(),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 32),
                    // Legend
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _buildLegendItem('Low', Colors.green[400]!),
                        const SizedBox(width: 32),
                        _buildLegendItem('High', Colors.red[600]!),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildLegendItem(String label, Color color) {
    return Row(
      children: [
        Container(
          width: 16,
          height: 16,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          label,
          style: const TextStyle(fontSize: 12),
        ),
      ],
    );
  }
}
