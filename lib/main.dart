import 'package:flutter/material.dart';

import 'screens/map_screen.dart';
void main() {
  runApp(const TechathonApp());
}

class TechathonApp extends StatelessWidget {
  const TechathonApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Techathon - Accident Zones',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.amber),
        useMaterial3: true,
      ),
      home: const MapScreen(),
    );
  }
}
