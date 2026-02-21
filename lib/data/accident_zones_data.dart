// accident_zones_data.dart
// ─────────────────────────────────────────────────────────────────────────────
// AccidentZone model + data helper
// ─────────────────────────────────────────────────────────────────────────────

class AccidentZone {
  final String title;
  final double latitude;
  final double longitude;
  final int accidentCount;
  final int severityColor;   // 0xFFrrggbb int — pass directly to Color()
  final double radiusMeters;

  const AccidentZone({
    required this.title,
    required this.latitude,
    required this.longitude,
    required this.accidentCount,
    required this.severityColor,
    required this.radiusMeters,
  });

  // ── [] operator so zone['key'] works identically to zone.key ──────────────
  // This prevents NoSuchMethodError if any part of the code still uses
  // bracket-style access (zone['latitude'] etc.).
  dynamic operator [](String key) {
    switch (key) {
      case 'title':         return title;
      case 'latitude':      return latitude;
      case 'longitude':     return longitude;
      case 'accidentCount': return accidentCount;
      case 'severityColor': return severityColor;
      case 'radiusMeters':  return radiusMeters;
      default:
        throw ArgumentError('AccidentZone has no field "$key"');
    }
  }
}

// Helper to create AccidentZone from JSON
AccidentZone accidentZoneFromJson(Map<String, dynamic> json) {
  return AccidentZone(
    title: json['title'] as String,
    latitude: json['latitude'] as double,
    longitude: json['longitude'] as double,
    accidentCount: json['accidentCount'] as int,
    severityColor: json['severityColor'] as int,
    radiusMeters: json['radiusMeters'] as double,
  );
}
