import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/accident_zone.dart';

class ApiService {
  static const String baseUrl = "https://ai-road-risk-intelligence.onrender.com";
  static const String zonesEndpoint = "/risk_heatmap";

  // Map risk_level to severity number (1-5) with smart detection
  static int _mapRiskLevelToSeverity(dynamic riskLevel) {
    if (riskLevel == null) return 1;

    String level = riskLevel.toString().toLowerCase().trim();

    if (double.tryParse(level) != null) {
      final score = double.parse(level);
      if (score >= 70) return 5;
      if (score >= 50) return 4;
      if (score >= 30) return 3;
      if (score >= 10) return 2;
      return 1;
    }

    if (level.contains('critical') || level.contains('critical_area')) return 5;
    if (level.contains('extreme')) return 5;
    if (level.contains('very high') || level.contains('veryhigh')) return 5;
    if (level.contains('high') && !level.contains('very')) return 4;
    if (level.contains('medium') || level.contains('moderate')) return 3;
    if (level.contains('low') && !level.contains('very')) return 2;
    if (level.contains('very low') || level.contains('verylow')) return 1;

    return level.startsWith('c') || level.startsWith('e') ? 5 :
           level.startsWith('h') ? 4 :
           level.startsWith('m') ? 3 :
           level.startsWith('l') ? 2 : 1;
  }

  // ✅ Creates a default AccidentZone from a raw location map when parsing fails
  static AccidentZone _createDefaultZone(dynamic location) {
    return AccidentZone(
      id: (location['id'] ?? location['location_id'] ?? '').toString(),
      latitude: double.tryParse(location['latitude']?.toString() ??
                               location['lat']?.toString() ?? '0') ?? 0.0,
      longitude: double.tryParse(location['longitude']?.toString() ??
                                location['lng']?.toString() ??
                                location['lon']?.toString() ?? '0') ?? 0.0,
      radiusMeters: 200.0,
      title: (location['location_name'] ?? location['name'] ?? 'Unknown Location').toString(),
      description: '',
      severityLevel: 1,
      accidentCount: 0,
    );
  }

  // ✅ Returns hardcoded fallback zones when the API is unavailable
  static List<AccidentZone> _getStaticFallbackZones() {
    debugPrint('Using static fallback zones');
    return [
      AccidentZone(
        id: 'fallback_1',
        latitude: 19.0760,
        longitude: 72.8777,
        radiusMeters: 300,
        title: 'High Risk Zone - Mumbai',
        description: 'Fallback data: High accident frequency area',
        severityLevel: 4,
        accidentCount: 12,
      ),
      AccidentZone(
        id: 'fallback_2',
        latitude: 19.0330,
        longitude: 73.0297,
        radiusMeters: 250,
        title: 'Moderate Risk Zone',
        description: 'Fallback data: Moderate accident frequency area',
        severityLevel: 3,
        accidentCount: 6,
      ),
      AccidentZone(
        id: 'fallback_3',
        latitude: 19.1136,
        longitude: 72.8697,
        radiusMeters: 200,
        title: 'Critical Risk Zone',
        description: 'Fallback data: Critical accident frequency area',
        severityLevel: 5,
        accidentCount: 20,
      ),
    ];
  }

  static Future<List<AccidentZone>> fetchZones() async {
    try {
      final url = '$baseUrl$zonesEndpoint';
      debugPrint('Fetching zones from: $url');
      final response = await http.get(Uri.parse(url)).timeout(
        const Duration(seconds: 10),
        onTimeout: () => throw Exception('Request timeout'),
      );

      debugPrint('Response status: ${response.statusCode}');
      debugPrint('Response body: ${response.body.substring(0, response.body.length < 500 ? response.body.length : 500)}');

      if (response.statusCode == 200) {
        final dynamic decodedBody = json.decode(response.body);
        debugPrint('Decoded body type: ${decodedBody.runtimeType}');

        List<dynamic> data = [];

        if (decodedBody is List) {
          data = decodedBody;
        } else if (decodedBody is Map) {
          data = decodedBody['risky_locations'] ??
                 decodedBody['risky-locations'] ??
                 decodedBody['locations'] ??
                 decodedBody['data'] ??
                 decodedBody['zones'] ??
                 decodedBody['results'] ??
                 [];
        }

        if (data.isEmpty) {
          debugPrint('Warning: No risky locations found in API response');
          return _getStaticFallbackZones();
        }

        debugPrint('Found ${data.length} risky locations');

        final List<AccidentZone> zones = data
            .map<AccidentZone?>((location) {
              try {
                int severity = 1;

                if (location['risk_level'] != null) {
                  severity = _mapRiskLevelToSeverity(location['risk_level']);
                } else if (location['risk_score'] != null) {
                  severity = _mapRiskLevelToSeverity(location['risk_score']);
                } else if (location['severity_level'] != null) {
                  severity = _mapRiskLevelToSeverity(location['severity_level']);
                } else if (location['risk_category'] != null) {
                  severity = _mapRiskLevelToSeverity(location['risk_category']);
                } else {
                  final count = int.tryParse(location['accident_count']?.toString() ?? '0') ?? 0;
                  if (count > 10) severity = 5;
                  else if (count > 7) severity = 4;
                  else if (count > 4) severity = 3;
                  else if (count > 1) severity = 2;
                  else severity = 1;
                }

                debugPrint('🔍 Zone risk mapping: risk_level=${location['risk_level']}, risk_score=${location['risk_score']}, mapped_severity=$severity');

                return AccidentZone(
                  id: (location['id'] ?? location['location_id'] ?? location['location id'] ?? location['risk_id'] ?? '').toString(),
                  latitude: double.tryParse(location['latitude']?.toString() ??
                                           location['lat']?.toString() ??
                                           location['latitude_from_api']?.toString() ??
                                           location['location']?['latitude']?.toString() ?? '0') ?? 0.0,
                  longitude: double.tryParse(location['longitude']?.toString() ??
                                            location['lng']?.toString() ??
                                            location['lon']?.toString() ??
                                            location['longitude_from_api']?.toString() ??
                                            location['location']?['longitude']?.toString() ?? '0') ?? 0.0,
                  radiusMeters: double.tryParse(location['radius_meters']?.toString() ??
                                               location['radiusMeters']?.toString() ??
                                               location['radius']?.toString() ??
                                               location['area_radius']?.toString() ?? '200') ?? 200.0,
                  title: (location['location_name'] ??
                         location['name'] ??
                         location['title'] ??
                         location['address'] ??
                         location['area_name'] ?? 'Risky Location').toString(),
                  description: (location['description'] ??
                               location['risk_description'] ??
                               location['details'] ??
                               location['risk_factors'] ?? '').toString(),
                  severityLevel: severity,
                  accidentCount: int.tryParse(location['accident_count']?.toString() ??
                                             location['incidents']?.toString() ??
                                             location['count']?.toString() ??
                                             location['total_casualties']?.toString() ?? '0') ?? 0,
                );
              } catch (e) {
                debugPrint('Error mapping location: $location, Error: $e');
                return _createDefaultZone(location);
              }
            })
            .whereType<AccidentZone>()
            .toList();

        final Map<int, int> severityCount = {};
        for (final zone in zones) {
          severityCount[zone.severityLevel] = (severityCount[zone.severityLevel] ?? 0) + 1;
        }
        debugPrint('📊 Severity distribution: $severityCount');

        return zones;
      } else {
        debugPrint('API returned status ${response.statusCode}');
        return _getStaticFallbackZones();
      }
    } catch (e) {
      debugPrint('API Error: $e');
      return _getStaticFallbackZones();
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // Heatmap Data
  // ═══════════════════════════════════════════════════════════════════════════

  static Future<List<Map<String, dynamic>>> fetchHeatmapData() async {
    try {
      final url = '$baseUrl/risk_heatmap';
      debugPrint('Fetching heatmap data from: $url');

      final response = await http.get(Uri.parse(url)).timeout(
        const Duration(seconds: 10),
        onTimeout: () => throw Exception('Heatmap request timeout'),
      );

      debugPrint('Heatmap response status: ${response.statusCode}');

      if (response.statusCode == 200) {
        final dynamic decodedBody = json.decode(response.body);
        debugPrint('Heatmap data received: ${decodedBody.runtimeType}');

        List<Map<String, dynamic>> heatmapPoints = [];

        if (decodedBody is List) {
          heatmapPoints = List<Map<String, dynamic>>.from(decodedBody);
        } else if (decodedBody is Map) {
          final data = decodedBody['data'] ?? decodedBody['heatmap'] ?? decodedBody['points'] ?? [];
          if (data is List) {
            heatmapPoints = List<Map<String, dynamic>>.from(data);
          }
        }

        debugPrint('Heatmap points found: ${heatmapPoints.length}');
        return heatmapPoints;
      } else {
        debugPrint('Heatmap API error: ${response.statusCode}');
        return [];
      }
    } catch (e) {
      debugPrint('Heatmap fetch error: $e');
      return [];
    }
  }

  static Future<Map<String, dynamic>> fetchDashboardStatistics() async {
    try {
      final url = '$baseUrl/dashboard/statistics';
      debugPrint('Fetching dashboard statistics from: $url');

      final response = await http.get(Uri.parse(url)).timeout(
        const Duration(seconds: 10),
        onTimeout: () => throw Exception('Statistics request timeout'),
      );

      if (response.statusCode == 200) {
        final dynamic decodedBody = json.decode(response.body);
        if (decodedBody is Map) {
          debugPrint('Dashboard statistics received');
          return Map<String, dynamic>.from(decodedBody);
        }
      }
      return {};
    } catch (e) {
      debugPrint('Statistics fetch error: $e');
      return {};
    }
  }
}