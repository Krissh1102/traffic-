import '../models/accident_zone.dart';

/// Sample accident-prone zones data.
/// Replace with API or local database in production.
List<AccidentZone> getAccidentZones([double? userLat, double? userLng]) {
  const baseLat = 12.9716;
  const baseLng = 77.5946;

  return [
    AccidentZone(
      id: 'zone_1',
      latitude: baseLat + 0.002,
      longitude: baseLng + 0.001,
      radiusMeters: 150,
      title: 'High-risk intersection',
      description: 'Multiple collisions reported in past 6 months',
      severityLevel: 5,
      accidentCount: 12,
    ),
    AccidentZone(
      id: 'zone_2',
      latitude: baseLat - 0.003,
      longitude: baseLng + 0.002,
      radiusMeters: 200,
      title: 'Sharp curve zone',
      description: 'Poor visibility during monsoon',
      severityLevel: 4,
      accidentCount: 8,
    ),
    AccidentZone(
      id: 'zone_3',
      latitude: baseLat + 0.001,
      longitude: baseLng - 0.002,
      radiusMeters: 120,
      title: 'School zone crossing',
      description: 'Peak hour congestion and pedestrian accidents',
      severityLevel: 3,
      accidentCount: 5,
    ),
    AccidentZone(
      id: 'zone_4',
      latitude: baseLat - 0.001,
      longitude: baseLng - 0.001,
      radiusMeters: 180,
      title: 'Highway merge point',
      description: 'Lane-changing incidents common',
      severityLevel: 4,
      accidentCount: 7,
    ),
    AccidentZone(
      id: 'zone_5',
      latitude: baseLat + 0.004,
      longitude: baseLng + 0.003,
      radiusMeters: 100,
      title: 'Roundabout exit',
      description: 'Minor collisions during rush hours',
      severityLevel: 2,
      accidentCount: 3,
    ),
  ];
}
