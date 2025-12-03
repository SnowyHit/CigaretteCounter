import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:math' show max;

void main() {
  runApp(const MainApp());
}

class MainApp extends StatelessWidget {
  const MainApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: const HomePage(),
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

class HomePage extends StatefulWidget {
  const HomePage({super.key});

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

// Data Service
class CigaretteDataService {
  static Future<void> addCigarette() async {
    final prefs = await SharedPreferences.getInstance();
    final today = _getTodayKey();
    final count = prefs.getInt(today) ?? 0;
    await prefs.setInt(today, count + 1);
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
  late Future<List<Map<String, dynamic>>> _weeklyAverages;
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
      _weeklyAverages = CigaretteDataService.getWeeklyAverages(8);
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
                  const SizedBox(height: 20),

                  // Weekly averages (daily average per week)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 8.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Weekly Averages (avg cigarettes / day)',
                          style: TextStyle(fontSize: 14, color: Colors.grey, fontWeight: FontWeight.w500),
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          height: 120,
                          child: FutureBuilder<List<Map<String, dynamic>>>(
                            future: _weeklyAverages,
                            builder: (context, snapshot) {
                              if (!snapshot.hasData) {
                                return const Center(child: CircularProgressIndicator());
                              }
                              final weeks = snapshot.data!;
                              return ListView.separated(
                                scrollDirection: Axis.horizontal,
                                itemBuilder: (context, index) {
                                  final w = weeks[index];
                                  final label = w['start'] as String;
                                  final avg = (w['avg'] as double);
                                  final total = (w['total'] as int);
                                  return Container(
                                    width: 140,
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: Colors.grey[50],
                                      borderRadius: BorderRadius.circular(12),
                                      boxShadow: [
                                        BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 6),
                                      ],
                                    ),
                                    child: Column(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      crossAxisAlignment: CrossAxisAlignment.center,
                                      children: [
                                        Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
                                        const SizedBox(height: 8),
                                        Text(avg.toStringAsFixed(1), style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.blue)),
                                        const SizedBox(height: 6),
                                        Text('$total total', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                                      ],
                                    ),
                                  );
                                },
                                separatorBuilder: (_, __) => const SizedBox(width: 12),
                                itemCount: weeks.length,
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 20),

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
      _data = CigaretteDataService.getLast4Months();
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
                      '4-Month Heatmap',
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Last 120 days of cigarette usage',
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
                            // Week rows
                            ...List.generate(17, (weekIndex) {
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
                                          final ratio = value / maxValueSafe;
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
                                                  child: Text(
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
