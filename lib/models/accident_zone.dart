
class AccidentZone {
  final String id;
  final double latitude;
  final double longitude;
  final double radiusMeters;
  final String title;
  final String description;
  final int severityLevel; 
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

  int get severityColor {
    switch (severityLevel) {
      case 5:
        return 0xFFFF1744; 
      case 4:
        return 0xFFFF5722; 
      case 3:
        return 0xFFFF9800; // Orange
      case 2:
        return 0xFFFFC107; // Amber
      default:
        return 0xFF8BC34A; // Light green
    }
  }
}
