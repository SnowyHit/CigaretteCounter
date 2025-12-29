import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

class WidgetService {
  static const String _widgetDataKey = 'widget_data';
  static const String _todayCountKey = 'today_count';

  // Initialize the home screen widget
  static Future<void> initializeWidget() async {
    try {
      await updateWidgetData();
      print('Widget service initialized successfully');
    } catch (e) {
      print('Error initializing widget: $e');
    }
  }

  // Update widget data when a cigarette is logged
  static Future<void> updateWidgetData({int? todayCount, String? lastCigaretteTime}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      // Get current count if not provided
      final count = todayCount ?? (prefs.getInt(_todayCountKey) ?? 0);
      
      // Create widget data
      final widgetData = {
        'count': count,
        'lastUpdate': DateTime.now().toIso8601String(),
        'message': count == 0 ? 'Start tracking today!' : 'Keep going! $count logged',
      };
      
      // Save to shared preferences
      await prefs.setString(_widgetDataKey, jsonEncode(widgetData));
      
      print('Widget data updated with count: $count');
    } catch (e) {
      print('Error updating widget: $e');
    }
  }

  // Get widget data
  static Future<Map<String, dynamic>?> getWidgetData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final dataString = prefs.getString(_widgetDataKey);
      
      if (dataString == null) return null;
      
      return jsonDecode(dataString) as Map<String, dynamic>;
    } catch (e) {
      print('Error getting widget data: $e');
      return null;
    }
  }

  // Handle widget click (called from native code)
  static Future<void> handleWidgetClick() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      // Increment count
      final currentCount = prefs.getInt(_todayCountKey) ?? 0;
      await prefs.setInt(_todayCountKey, currentCount + 1);
      
      // Update widget
      await updateWidgetData(todayCount: currentCount + 1);
      
      print('Widget clicked - count incremented to ${currentCount + 1}');
    } catch (e) {
      print('Error handling widget click: $e');
    }
  }
}
