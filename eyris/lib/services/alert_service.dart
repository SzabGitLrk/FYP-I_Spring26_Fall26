import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:flutter/material.dart';
import '../models/alert_model.dart';

class AlertService {
  static const String _alertsKey = 'alerts_history';
  
  Future<void> saveAlert(String message, String type) async {
    final prefs = await SharedPreferences.getInstance();
    final alerts = await getAlerts();
    
    String icon = _getIconForType(type);
    Color color = _getColorForType(type);
    
    final newAlert = AlertModel(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      message: message,
      timestamp: _getCurrentTimestamp(),
      type: type,
      icon: icon,
      color: color,
    );
    
    alerts.insert(0, newAlert);
    if (alerts.length > 100) alerts.removeLast();
    
    final alertsJson = alerts.map((a) => a.toMap()).toList();
    await prefs.setString(_alertsKey, jsonEncode(alertsJson));
  }
  
  Future<List<AlertModel>> getAlerts() async {
    final prefs = await SharedPreferences.getInstance();
    final String? alertsString = prefs.getString(_alertsKey);
    
    if (alertsString == null || alertsString.isEmpty) {
      return [];
    }
    
    final List<dynamic> alertsJson = jsonDecode(alertsString);
    return alertsJson.map((json) => AlertModel.fromMap(json)).toList();
  }
  
  Future<void> clearAlerts() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_alertsKey);
  }
  
  Future<void> deleteAlert(String id) async {
    final alerts = await getAlerts();
    final updatedAlerts = alerts.where((a) => a.id != id).toList();
    
    final prefs = await SharedPreferences.getInstance();
    final alertsJson = updatedAlerts.map((a) => a.toMap()).toList();
    await prefs.setString(_alertsKey, jsonEncode(alertsJson));
  }
  
  String _getIconForType(String type) {
    switch (type) {
      case 'obstacle': return '⚠️';
      case 'navigation': return '🧭';
      case 'system': return '🔋';
      default: return '🔔';
    }
  }
  
  Color _getColorForType(String type) {
    switch (type) {
      case 'obstacle': return Colors.red;
      case 'navigation': return Colors.blue;
      case 'system': return Colors.orange;
      default: return Colors.grey;
    }
  }
  
  String _getCurrentTimestamp() {
    final now = DateTime.now();
    final time = "${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}";
    final date = "${now.day}/${now.month}/${now.year}";
    return "$time • $date";
  }
}