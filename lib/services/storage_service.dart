import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/workshop.dart';

class StorageService {
  static const String _workshopsKey = 'stored_workshops_clean_v1';

  static Future<List<Workshop>> loadWorkshops() async {
    final prefs = await SharedPreferences.getInstance();
    final String? rawData = prefs.getString(_workshopsKey);

    if (rawData == null || rawData.isEmpty) {
      return [];
    }

    try {
      final List<dynamic> list = jsonDecode(rawData);
      return list.map((item) => Workshop.fromMap(Map<String, dynamic>.from(item))).toList();
    } catch (e) {
      return [];
    }
  }

  static Future<void> saveWorkshops(List<Workshop> workshops) async {
    final prefs = await SharedPreferences.getInstance();
    final jsonList = workshops.map((w) => w.toMap()).toList();
    await prefs.setString(_workshopsKey, jsonEncode(jsonList));
  }

  static Future<void> clearAll() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_workshopsKey);
  }
}
