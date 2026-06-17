import 'package:flutter/material.dart';

class AlertModel {
  final String id;
  final String message;
  final String timestamp;
  final String type;
  final String icon;
  final Color color;
  
  AlertModel({
    required this.id,
    required this.message,
    required this.timestamp,
    required this.type,
    required this.icon,
    required this.color,
  });
  
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'message': message,
      'timestamp': timestamp,
      'type': type,
      'icon': icon,
      // CHANGE: .value replaced with .toARGB32()
      'colorValue': color.toARGB32(), 
    };
  }
  
  factory AlertModel.fromMap(Map<String, dynamic> map) {
    return AlertModel(
      id: map['id'],
      message: map['message'],
      timestamp: map['timestamp'],
      type: map['type'],
      icon: map['icon'],
      // The Color() constructor still accepts the 32-bit integer perfectly
      color: Color(map['colorValue']),
    );
  }
}