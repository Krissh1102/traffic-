/// Represents an accident-prone area on the map.
/// Uses plain lat/lng to stay independent of any map provider.
class AccidentZone {
  final String id;
  final double latitude;
  final double longitude;
  final double radiusMeters;
  final String title;
  final String description;
  final int severityLevel; // 1-5, 5 being most dangerous
  final int accidentCount;

  const AccidentZone({
    required this.id,
    required this.latitude,
    required this.longitude,
    required this.radiusMeters,
    required this.title,
    required this.description,
    required this.severityLevel,
    this.accidentCount = 0,
  });

  /// Returns a color based on severity (red = high, orange = medium, amber = low)
  int get severityColor {
    switch (severityLevel) {
      case 5:
        return 0xFFFF1744; // Deep red
      case 4:
        return 0xFFFF5722; // Orange red
      case 3:
        return 0xFFFF9800; // Orange
      case 2:
        return 0xFFFFC107; // Amber
      default:
        return 0xFF8BC34A; // Light green
    }
  }
}
