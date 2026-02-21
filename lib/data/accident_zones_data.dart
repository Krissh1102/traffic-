import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/accident_zone.dart';

Future<List<AccidentZone>> getAccidentZones([double? userLat, double? userLng]) async {
  final uri = Uri.http(
    'ai-road-risk-intelligence.onrender.com',
    '/risk_heatmap',
    {
      if (userLat != null) 'lat': userLat.toString(),
      if (userLng != null) 'lon': userLng.toString(),
    },
  );

  try {
    final response = await http.get(uri).timeout(const Duration(seconds: 15));

    if (response.statusCode == 200) {
      final List<dynamic> data = jsonDecode(response.body);
      return data.asMap().entries.map((entry) {
        final i = entry.key;
        final Map<String, dynamic> zone = entry.value;

        final int apiSeverity = (zone['severity'] as num?)?.toInt() ?? 1;
        final double intensity = (zone['intensity'] as num?)?.toDouble() ?? 0.0;
        final int casualties = (zone['casualties'] as num?)?.toInt() ?? 0;
        final int vehicles = (zone['vehicles'] as num?)?.toInt() ?? 0;
        final String severityLabel = zone['severity_label'] as String? ?? 'Unknown';


        final int derivedSeverity = _mapSeverity(apiSeverity, intensity);

        // Radius scales with intensity (100m–300m)
        final double radius = 100 + (intensity * 400);

        return AccidentZone(
          id: 'zone_${i + 1}',
          latitude: (zone['lat'] as num).toDouble(),
          longitude: (zone['lon'] as num).toDouble(),
          radiusMeters: radius,
          title: '$severityLabel Risk Zone',
          description:
              '$casualties casualt${casualties == 1 ? 'y' : 'ies'} · '
              '$vehicles vehicle${vehicles == 1 ? '' : 's'} involved',
          severityLevel: derivedSeverity,
          accidentCount: casualties,
        );
      }).toList();
    } else {
      // ignore: avoid_print
      print('[AccidentZoneService] Non-200 status: ${response.statusCode}');
      return [];
    }
  } catch (e) {
    print('[AccidentZoneService] Error fetching zones: $e');
    return [];
  }
}

int _mapSeverity(int apiSeverity, double intensity) {
  switch (apiSeverity) {
    case 1: 
      return intensity >= 0.7 ? 5 : 4;
    case 3: 
      return intensity >= 0.6 ? 4 : 3;
    case 2: // Slight
    default:
      return intensity >= 0.5 ? 2 : 1;
  }
}