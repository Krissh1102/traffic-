import 'dart:ui';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:techathon/models/accident_zone.dart';
import 'package:techathon/service/api_service.dart';
import 'package:url_launcher/url_launcher.dart';

// ─────────────────────────────────────────────
//  Placeholder screens
// ─────────────────────────────────────────────
class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Dashboard')),
      body: const Center(child: Text('Dashboard coming soon')),
    );
  }
}

class RiskAnalysisScreen extends StatelessWidget {
  const RiskAnalysisScreen({super.key});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Risk Analysis')),
      body: const Center(child: Text('Risk Analysis coming soon')),
    );
  }
}

class ChatbotScreen extends StatelessWidget {
  const ChatbotScreen({super.key});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Chatbot')),
      body: const Center(child: Text('Chatbot coming soon')),
    );
  }
}

// ─────────────────────────────────────────────
//  Map Screen
// ─────────────────────────────────────────────

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> with TickerProviderStateMixin {
  // ✅ FIX: Track whether the map controller is ready to use
  bool _mapReady = false;

  final MapController _mapController = MapController();
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  Position? _currentPosition;
  String? _locationError;
  bool _isLoadingLocation = true;
  List<dynamic> _allZones = [];
  int _lastZoneCount = -1;

  static const double _defaultZoom = 15.0;
  static const LatLng _defaultCenter = LatLng(12.9716, 77.5946);

  late AnimationController _pulseController;
  late AnimationController _slideController;

  @override
  void initState() {
    super.initState();
    _useDefaultLocation();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);

    _slideController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _getCurrentLocation();
    });

    _slideController.forward();
  }

  @override
  void dispose() {
    _mapController.dispose();
    _pulseController.dispose();
    _slideController.dispose();
    super.dispose();
  }

  // ── Location helpers ──────────────────────────────────────────────────────

  Future<void> _getCurrentLocation() async {
    if (!mounted) return;

    setState(() {
      _isLoadingLocation = true;
      _locationError = null;
    });

    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied ||
            permission == LocationPermission.deniedForever) {
          if (mounted) {
            setState(() {
              _locationError = 'Location permission denied';
              _isLoadingLocation = false;
            });
          }
          return;
        }
      }

      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (mounted) {
          setState(() {
            _locationError = 'Location services are disabled';
            _isLoadingLocation = false;
          });
        }
        return;
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
      ).timeout(const Duration(seconds: 5), onTimeout: () {
        throw Exception('Location request timeout');
      });

      if (mounted) {
        setState(() {
          _currentPosition = position;
          _isLoadingLocation = false;
        });
        _animateToCurrentLocation();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _locationError = 'Could not get location: ${e.toString()}';
          _isLoadingLocation = false;
        });
      }
    }
  }

  void _useDefaultLocation() {
    _currentPosition = Position(
      latitude: _defaultCenter.latitude,
      longitude: _defaultCenter.longitude,
      timestamp: DateTime.now(),
      accuracy: 0,
      altitude: 0,
      altitudeAccuracy: 0,
      heading: 0,
      headingAccuracy: 0,
      speed: 0,
      speedAccuracy: 0,
    );
  }

  // ✅ FIX: Only call _mapController.move() when map is ready
  void _animateToCurrentLocation() {
    if (_currentPosition == null || !_mapReady) return;
    _mapController.move(
      LatLng(_currentPosition!.latitude, _currentPosition!.longitude),
      _defaultZoom,
    );
  }

  LatLng get _initialCenter {
    if (_currentPosition != null) {
      return LatLng(_currentPosition!.latitude, _currentPosition!.longitude);
    }
    return _defaultCenter;
  }

  // ✅ FIX: Guard _fitMapToZones with _mapReady check
  void _fitMapToZones(List<AccidentZone> zones) {
    if (zones.isEmpty || !_mapReady) return;

    double minLat = zones.first.latitude;
    double maxLat = zones.first.latitude;
    double minLng = zones.first.longitude;
    double maxLng = zones.first.longitude;

    for (final zone in zones) {
      minLat = math.min(minLat, zone.latitude);
      maxLat = math.max(maxLat, zone.latitude);
      minLng = math.min(minLng, zone.longitude);
      maxLng = math.max(maxLng, zone.longitude);
    }

    const paddingFactor = 0.07;
    final latPadding = (maxLat - minLat) * paddingFactor;
    final lngPadding = (maxLng - minLng) * paddingFactor;

    minLat -= latPadding;
    maxLat += latPadding;
    minLng -= lngPadding;
    maxLng += lngPadding;

    final centerLat = (minLat + maxLat) / 2;
    final centerLng = (minLng + maxLng) / 2;

    const viewportWidth = 800.0;
    const viewportHeight = 600.0;
    const tileSize = 256.0;

    final latRange = maxLat - minLat;
    final lngRange = maxLng - minLng;

    final latZoom = (math.log(360.0 / latRange) / math.ln2) -
        (math.log(viewportHeight / tileSize) / math.ln2);
    final lngZoom = (math.log(360.0 / lngRange) / math.ln2) -
        (math.log(viewportWidth / tileSize) / math.ln2);

    final zoom = math.min(latZoom, lngZoom).clamp(3.0, 15.0);

    debugPrint('🗺️ Auto-fit zoom: $zoom');
    _mapController.move(LatLng(centerLat, centerLng), zoom);
  }

  // ── Navigation helpers ────────────────────────────────────────────────────

  void _navigateToZone(dynamic zone) {
    if (!_mapReady) return;
    _mapController.move(LatLng(zone.latitude, zone.longitude), 16.0);
    Future.delayed(const Duration(milliseconds: 500), () {
      _showZoneDetails(context, zone);
    });
  }

  void _showLocationSearch() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _LocationSearchModal(
        allZones: _allZones,
        onLocationSelected: (lat, lng, name) {
          Navigator.pop(context);
          if (_mapReady) _mapController.move(LatLng(lat, lng), 15.0);
        },
        onZoneSelected: (zone) {
          Navigator.pop(context);
          _navigateToZone(zone);
        },
      ),
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      drawer: _buildDrawer(context),
      body: Stack(
        children: [
          // ── Map ─────────────────────────────────────────────────────────
          FutureBuilder<List<AccidentZone>>(
            future: ApiService.fetchZones(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                return Center(
                  child: Text(
                    "Error: ${snapshot.error}",
                    textAlign: TextAlign.center,
                  ),
                );
              }
              final zones = snapshot.data ?? [];
              _allZones = zones;

              debugPrint('🗺️ MapScreen received ${zones.length} zones');

              final Map<int, List<AccidentZone>> zonesBySeverity = {};
              for (final zone in zones) {
                zonesBySeverity.putIfAbsent(zone.severityLevel, () => []).add(zone);
              }

              if (zones.isNotEmpty && zones.length != _lastZoneCount) {
                _lastZoneCount = zones.length;
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  _fitMapToZones(zones);
                });
              }

              return FlutterMap(
                mapController: _mapController,
                options: MapOptions(
                  initialCenter: _initialCenter,
                  initialZoom: _defaultZoom,
                  // ✅ FIX: Set _mapReady = true once map is initialized
                  onMapReady: () {
                    setState(() => _mapReady = true);
                  },
                ),
                children: [
                  TileLayer(
                    urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                    userAgentPackageName: 'com.example.techathon',
                  ),

                  // Low Risk (Level 1-2) - Green
                  CircleLayer(
                    circles: [
                      for (final zone in zonesBySeverity[1] ?? [])
                        CircleMarker(
                          point: LatLng(zone.latitude, zone.longitude),
                          radius: (zone.radiusMeters * 1.5).toDouble(),
                          useRadiusInMeter: true,
                          color: const Color(0xFF8BC34A).withOpacity(0.4),
                          borderStrokeWidth: 3,
                          borderColor: const Color(0xFF8BC34A),
                        ),
                      for (final zone in zonesBySeverity[2] ?? [])
                        CircleMarker(
                          point: LatLng(zone.latitude, zone.longitude),
                          radius: (zone.radiusMeters * 1.5).toDouble(),
                          useRadiusInMeter: true,
                          color: const Color(0xFF8BC34A).withOpacity(0.4),
                          borderStrokeWidth: 3,
                          borderColor: const Color(0xFF8BC34A),
                        ),
                    ],
                  ),

                  // Medium Risk (Level 3) - Orange
                  CircleLayer(
                    circles: [
                      for (final zone in zonesBySeverity[3] ?? [])
                        CircleMarker(
                          point: LatLng(zone.latitude, zone.longitude),
                          radius: (zone.radiusMeters * 1.5).toDouble(),
                          useRadiusInMeter: true,
                          color: const Color(0xFFFF9800).withOpacity(0.5),
                          borderStrokeWidth: 3,
                          borderColor: const Color(0xFFFF9800),
                        ),
                    ],
                  ),

                  // High Risk (Level 4-5) - Red
                  CircleLayer(
                    circles: [
                      for (final zone in zonesBySeverity[4] ?? [])
                        CircleMarker(
                          point: LatLng(zone.latitude, zone.longitude),
                          radius: (zone.radiusMeters * 1.5).toDouble(),
                          useRadiusInMeter: true,
                          color: const Color(0xFFFF5722).withOpacity(0.6),
                          borderStrokeWidth: 3,
                          borderColor: const Color(0xFFFF5722),
                        ),
                      for (final zone in zonesBySeverity[5] ?? [])
                        CircleMarker(
                          point: LatLng(zone.latitude, zone.longitude),
                          radius: (zone.radiusMeters * 1.5).toDouble(),
                          useRadiusInMeter: true,
                          color: const Color(0xFFFF1744).withOpacity(0.7),
                          borderStrokeWidth: 3,
                          borderColor: const Color(0xFFFF1744),
                        ),
                    ],
                  ),

                  // Markers
                  MarkerLayer(
                    markers: [
                      for (final zone in zones)
                        Marker(
                          point: LatLng(zone.latitude, zone.longitude),
                          width: 45,
                          height: 45,
                          child: GestureDetector(
                            onTap: () => _showZoneDetails(context, zone),
                            child: Container(
                              decoration: BoxDecoration(
                                color: Color(zone.severityColor),
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                    color: Color(zone.severityColor).withOpacity(0.5),
                                    blurRadius: 8,
                                    spreadRadius: 2,
                                  ),
                                ],
                              ),
                              child: const Icon(
                                Icons.warning,
                                color: Colors.white,
                                size: 24,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              );
            },
          ),

          // Loading overlay
          if (_isLoadingLocation)
            BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
              child: Container(
                color: Colors.black26,
                alignment: Alignment.center,
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final isTablet = constraints.maxWidth > 600;
                    return Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: isTablet ? 40 : 32,
                        vertical: isTablet ? 32 : 24,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.2),
                            blurRadius: 20,
                            offset: const Offset(0, 10),
                          ),
                        ],
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            width: isTablet ? 60 : 50,
                            height: isTablet ? 60 : 50,
                            child: CircularProgressIndicator(
                              strokeWidth: 3,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                Theme.of(context).primaryColor,
                              ),
                            ),
                          ),
                          SizedBox(height: isTablet ? 24 : 20),
                          Text(
                            'Locating you...',
                            style: TextStyle(
                              fontSize: isTablet ? 20 : 18,
                              fontWeight: FontWeight.w600,
                              color: Colors.black87,
                            ),
                          ),
                          SizedBox(height: isTablet ? 10 : 8),
                          Text(
                            'Finding accident-prone areas nearby',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: isTablet ? 15 : 13,
                              color: Colors.black54,
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ),

          // Risk Level Legend
          Positioned(
            top: 20,
            right: 12,
            child: Card(
              elevation: 8,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.15),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Risk Level',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 8),
                    _buildLegendItem('Low Risk', const Color(0xFF8BC34A)),
                    _buildLegendItem('Medium Risk', const Color(0xFFFF9800)),
                    _buildLegendItem('High Risk', const Color(0xFFFF5722)),
                    _buildLegendItem('Critical', const Color(0xFFFF1744)),
                  ],
                ),
              ),
            ),
          ),

          // Top bar + FAB
          SafeArea(
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, -1),
                end: Offset.zero,
              ).animate(
                CurvedAnimation(
                  parent: _slideController,
                  curve: Curves.easeOutCubic,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildTopBar(),
                  const Spacer(),
                  _buildLocationButton(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Drawer ────────────────────────────────────────────────────────────────

  Widget _buildDrawer(BuildContext context) {
    final primary = Theme.of(context).primaryColor;

    return Drawer(
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.only(
          topRight: Radius.circular(24),
          bottomRight: Radius.circular(24),
        ),
      ),
      child: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(24, 56, 24, 28),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [primary, primary.withOpacity(0.75)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(Icons.shield_outlined, color: Colors.white, size: 32),
                ),
                const SizedBox(height: 16),
                const Text(
                  'SafeRoute',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Accident Zone Navigator',
                  style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 13),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _drawerItem(context, icon: Icons.dashboard_rounded, label: 'Dashboard',
              subtitle: 'Overview & stats', onTap: () {
            Navigator.pop(context);
            Navigator.push(context, MaterialPageRoute(builder: (_) => const DashboardScreen()));
          }),
          _drawerItem(context, icon: Icons.bar_chart_rounded, label: 'Risk Analysis',
              subtitle: 'Zone risk insights', onTap: () {
            Navigator.pop(context);
            Navigator.push(context, MaterialPageRoute(builder: (_) => const RiskAnalysisScreen()));
          }),
          _drawerItem(context, icon: Icons.smart_toy_rounded, label: 'Chatbot',
              subtitle: 'Ask safety questions', onTap: () {
            Navigator.pop(context);
            Navigator.push(context, MaterialPageRoute(builder: (_) => const ChatbotScreen()));
          }),
          const Spacer(),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Text('v1.0.0  •  SafeRoute',
                style: TextStyle(fontSize: 12, color: Colors.grey[400])),
          ),
        ],
      ),
    );
  }

  Widget _drawerItem(BuildContext context,
      {required IconData icon,
      required String label,
      required String subtitle,
      required VoidCallback onTap}) {
    final primary = Theme.of(context).primaryColor;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: primary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: primary, size: 22),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(label,
                          style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 15,
                              color: Colors.black87)),
                      const SizedBox(height: 2),
                      Text(subtitle,
                          style: TextStyle(fontSize: 12, color: Colors.grey[500])),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right, color: Colors.grey[400], size: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLegendItem(String label, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 14,
            height: 14,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              border: Border.all(color: color.withOpacity(0.7), width: 1),
            ),
          ),
          const SizedBox(width: 8),
          Text(label,
              style: const TextStyle(
                  fontSize: 11, color: Colors.black87, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  Widget _buildTopBar() {
    final screenWidth = MediaQuery.of(context).size.width;
    final isTablet = screenWidth > 600;

    return Container(
      margin: EdgeInsets.all(isTablet ? 24 : 16),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Colors.white.withOpacity(0.95),
                  Colors.white.withOpacity(0.85),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white.withOpacity(0.3), width: 1.5),
              boxShadow: [
                BoxShadow(
                    color: Colors.black.withOpacity(0.15),
                    blurRadius: 20,
                    offset: const Offset(0, 4)),
              ],
            ),
            child: Row(
              children: [
                Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(16), bottomLeft: Radius.circular(16)),
                    onTap: () => _scaffoldKey.currentState?.openDrawer(),
                    child: Padding(
                      padding: EdgeInsets.symmetric(
                          horizontal: isTablet ? 20 : 16, vertical: isTablet ? 18 : 14),
                      child: Icon(Icons.menu_rounded,
                          color: Colors.grey[700], size: isTablet ? 26 : 22),
                    ),
                  ),
                ),
                Container(width: 1, height: isTablet ? 28 : 24, color: Colors.grey[200]),
                Expanded(
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: _showLocationSearch,
                      borderRadius: const BorderRadius.only(
                          topRight: Radius.circular(16), bottomRight: Radius.circular(16)),
                      child: Padding(
                        padding: EdgeInsets.symmetric(
                            horizontal: isTablet ? 20 : 16, vertical: isTablet ? 18 : 14),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                'Search for a place or address',
                                style: TextStyle(
                                    fontSize: isTablet ? 16 : 15,
                                    color: Colors.grey[600],
                                    fontWeight: FontWeight.w400),
                              ),
                            ),
                            SizedBox(width: isTablet ? 12 : 8),
                            if (_locationError != null)
                              Tooltip(
                                message: _locationError!,
                                child: Icon(Icons.error_outline,
                                    color: Colors.red, size: isTablet ? 22 : 20),
                              )
                            else
                              Icon(Icons.search,
                                  color: Colors.grey[700], size: isTablet ? 26 : 22),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLocationButton() {
    final screenWidth = MediaQuery.of(context).size.width;
    final isTablet = screenWidth > 600;

    return Padding(
      padding: EdgeInsets.all(isTablet ? 24 : 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: _isLoadingLocation ? null : _animateToCurrentLocation,
              borderRadius: BorderRadius.circular(16),
              child: Container(
                padding: EdgeInsets.all(isTablet ? 20 : 16),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Theme.of(context).primaryColor,
                      Theme.of(context).primaryColor.withOpacity(0.8),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Theme.of(context).primaryColor.withOpacity(0.4),
                      blurRadius: 15,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Icon(Icons.my_location_rounded,
                    color: Colors.white, size: isTablet ? 32 : 28),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showZoneDetails(BuildContext context, dynamic zone) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isTablet = screenWidth > 600;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(24),
            topRight: Radius.circular(24),
          ),
        ),
        padding: EdgeInsets.all(isTablet ? 32 : 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: isTablet ? 50 : 40,
                height: 4,
                decoration: BoxDecoration(
                    color: Colors.grey[300], borderRadius: BorderRadius.circular(2)),
              ),
            ),
            SizedBox(height: isTablet ? 24 : 20),
            Row(
              children: [
                Container(
                  padding: EdgeInsets.all(isTablet ? 16 : 12),
                  decoration: BoxDecoration(
                    color: Color(zone.severityColor).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(Icons.warning_rounded,
                      color: Color(zone.severityColor), size: isTablet ? 32 : 28),
                ),
                SizedBox(width: isTablet ? 20 : 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(zone.title,
                          style: TextStyle(
                              fontSize: isTablet ? 24 : 20, fontWeight: FontWeight.bold)),
                      SizedBox(height: isTablet ? 6 : 4),
                      Text('${zone.accidentCount} accidents recorded',
                          style: TextStyle(
                              fontSize: isTablet ? 16 : 14, color: Colors.grey[600])),
                    ],
                  ),
                ),
              ],
            ),
            SizedBox(height: isTablet ? 28 : 24),
            Container(
              padding: EdgeInsets.all(isTablet ? 20 : 16),
              decoration: BoxDecoration(
                  color: Colors.grey[100], borderRadius: BorderRadius.circular(12)),
              child: Row(
                children: [
                  Icon(Icons.info_outline, color: Colors.grey[700], size: isTablet ? 24 : 20),
                  SizedBox(width: isTablet ? 16 : 12),
                  Expanded(
                    child: Text('Drive carefully in this area and follow traffic rules',
                        style: TextStyle(fontSize: isTablet ? 15 : 13)),
                  ),
                ],
              ),
            ),
            SizedBox(height: isTablet ? 20 : 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () async {
                  Navigator.pop(context);
                  final url = Uri.parse(
                    'https://www.google.com/maps/@?api=1&map_action=pano&viewpoint=${zone.latitude},${zone.longitude}',
                  );
                  await launchUrl(url, mode: LaunchMode.externalApplication);
                },
                icon: const Icon(Icons.streetview),
                label: const Text('Open Street View'),
                style: ElevatedButton.styleFrom(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
            SizedBox(height: isTablet ? 20 : 16),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
//  Location Search Modal
// ─────────────────────────────────────────────

class _LocationSearchModal extends StatefulWidget {
  final List<dynamic> allZones;
  final Function(double, double, String) onLocationSelected;
  final Function(dynamic) onZoneSelected;

  const _LocationSearchModal({
    required this.allZones,
    required this.onLocationSelected,
    required this.onZoneSelected,
  });

  @override
  State<_LocationSearchModal> createState() => _LocationSearchModalState();
}

class _LocationSearchModalState extends State<_LocationSearchModal> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  List<dynamic> _filteredZones = [];
  bool _isSearching = false;

  late Future<List<AccidentZone>> _zonesFuture;

  @override
  void initState() {
    super.initState();
    _zonesFuture = ApiService.fetchZones();
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    setState(() {
      final query = _searchController.text.toLowerCase().trim();
      if (query.isEmpty) {
        _filteredZones = [];
        _isSearching = false;
      } else {
        _isSearching = true;
        _filteredZones = widget.allZones
            .where((zone) => zone.title.toLowerCase().contains(query))
            .toList();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    final screenWidth = MediaQuery.of(context).size.width;
    final isTablet = screenWidth > 600;
    final keyboardHeight = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      height: screenHeight * 0.9,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(24),
          topRight: Radius.circular(24),
        ),
      ),
      child: Column(
        children: [
          Container(
            margin: const EdgeInsets.only(top: 12, bottom: 16),
            width: 40,
            height: 4,
            decoration:
                BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2)),
          ),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: isTablet ? 24 : 16, vertical: 8),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back),
                  onPressed: () => Navigator.pop(context),
                  color: Colors.grey[700],
                ),
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                        color: Colors.grey[100], borderRadius: BorderRadius.circular(12)),
                    child: TextField(
                      controller: _searchController,
                      focusNode: _searchFocusNode,
                      style: TextStyle(fontSize: isTablet ? 16 : 15, color: Colors.black87),
                      decoration: InputDecoration(
                        hintText: 'Search for a place or address',
                        hintStyle:
                            TextStyle(color: Colors.grey[500], fontSize: isTablet ? 16 : 15),
                        prefixIcon:
                            Icon(Icons.search, color: Colors.grey[600], size: isTablet ? 24 : 22),
                        suffixIcon: _searchController.text.isNotEmpty
                            ? IconButton(
                                icon: Icon(Icons.clear,
                                    color: Colors.grey[600], size: isTablet ? 22 : 20),
                                onPressed: () {
                                  _searchController.clear();
                                  setState(() {
                                    _filteredZones = [];
                                    _isSearching = false;
                                  });
                                },
                              )
                            : null,
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.symmetric(
                            horizontal: isTablet ? 16 : 12, vertical: isTablet ? 16 : 14),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: Colors.grey[300]),
          Expanded(
            child: _isSearching && _filteredZones.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.search_off, size: isTablet ? 80 : 64, color: Colors.grey[400]),
                        SizedBox(height: isTablet ? 20 : 16),
                        Text('No results found',
                            style: TextStyle(
                                fontSize: isTablet ? 18 : 16,
                                color: Colors.grey[600],
                                fontWeight: FontWeight.w500)),
                        SizedBox(height: isTablet ? 12 : 8),
                        Text('Try searching for accident zones',
                            style: TextStyle(
                                fontSize: isTablet ? 14 : 13, color: Colors.grey[500])),
                      ],
                    ),
                  )
                : _isSearching && _filteredZones.isNotEmpty
                    ? ListView.separated(
                        padding: EdgeInsets.symmetric(vertical: isTablet ? 12 : 8),
                        itemCount: _filteredZones.length,
                        separatorBuilder: (_, __) => Divider(height: 1, color: Colors.grey[200]),
                        itemBuilder: (context, index) {
                          final zone = _filteredZones[index];
                          return ListTile(
                            contentPadding: EdgeInsets.symmetric(
                                horizontal: isTablet ? 24 : 16, vertical: isTablet ? 12 : 8),
                            leading: Container(
                              padding: EdgeInsets.all(isTablet ? 12 : 10),
                              decoration: BoxDecoration(
                                color: Color(zone.severityColor).withOpacity(0.1),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Icon(Icons.warning_rounded,
                                  color: Color(zone.severityColor), size: isTablet ? 26 : 24),
                            ),
                            title: Text(zone.title,
                                style: TextStyle(
                                    fontSize: isTablet ? 16 : 15,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.black87)),
                            subtitle: Text('${zone.accidentCount} accidents recorded',
                                style: TextStyle(
                                    fontSize: isTablet ? 14 : 13, color: Colors.grey[600])),
                            trailing: Icon(Icons.arrow_forward_ios,
                                size: isTablet ? 18 : 16, color: Colors.grey[400]),
                            onTap: () => widget.onZoneSelected(zone),
                          );
                        },
                      )
                    : _buildRecentAndSuggestions(isTablet),
          ),
          SizedBox(height: keyboardHeight > 0 ? keyboardHeight : 0),
        ],
      ),
    );
  }

  Widget _buildRecentAndSuggestions(bool isTablet) {
    return ListView(
      padding: EdgeInsets.symmetric(
          horizontal: isTablet ? 24 : 16, vertical: isTablet ? 16 : 12),
      children: [
        ListTile(
          contentPadding: EdgeInsets.symmetric(vertical: isTablet ? 12 : 8),
          leading: Container(
            padding: EdgeInsets.all(isTablet ? 12 : 10),
            decoration: BoxDecoration(
                color: Colors.blue.withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
            child: Icon(Icons.my_location, color: Colors.blue, size: isTablet ? 26 : 24),
          ),
          title: Text('Use current location',
              style: TextStyle(
                  fontSize: isTablet ? 16 : 15,
                  fontWeight: FontWeight.w600,
                  color: Colors.black87)),
          subtitle: Text('Find accident zones near you',
              style: TextStyle(fontSize: isTablet ? 14 : 13, color: Colors.grey[600])),
          onTap: () => Navigator.pop(context),
        ),
        SizedBox(height: isTablet ? 24 : 16),
        Text('Accident-Prone Areas',
            style: TextStyle(
                fontSize: isTablet ? 15 : 14,
                fontWeight: FontWeight.bold,
                color: Colors.grey[800])),
        SizedBox(height: isTablet ? 16 : 12),
        ...widget.allZones.take(8).map((zone) {
          return Column(
            children: [
              ListTile(
                contentPadding: EdgeInsets.symmetric(vertical: isTablet ? 8 : 4),
                leading: Container(
                  padding: EdgeInsets.all(isTablet ? 10 : 8),
                  decoration: BoxDecoration(
                    color: Color(zone.severityColor).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(Icons.place, color: Color(zone.severityColor),
                      size: isTablet ? 24 : 22),
                ),
                title: Text(zone.title,
                    style: TextStyle(
                        fontSize: isTablet ? 15 : 14,
                        fontWeight: FontWeight.w500,
                        color: Colors.black87)),
                subtitle: Text('${zone.accidentCount} accidents',
                    style: TextStyle(fontSize: isTablet ? 13 : 12, color: Colors.grey[600])),
                trailing: Icon(Icons.north_west, size: isTablet ? 18 : 16, color: Colors.grey[400]),
                onTap: () => widget.onZoneSelected(zone),
              ),
              if (widget.allZones.indexOf(zone) < 7)
                Divider(height: 1, color: Colors.grey[200]),
            ],
          );
        }),
      ],
    );
  }
}