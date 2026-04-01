
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';

class JeepneyRoute {
  final String name;
  final String filePath;
  final Color color;
  bool isVisible;
  Polyline? polylineData;

  JeepneyRoute({
    required this.name,
    required this.filePath,
    required this.color,
    this.isVisible = false,
  });
}