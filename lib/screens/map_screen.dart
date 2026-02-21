import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../data/accident_zones_data.dart';
import '../models/accident_zone.dart';

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> with TickerProviderStateMixin {
  final MapController _mapController = MapController();
  Position? _currentPosition;
  String? _locationError;
  bool _isLoadingLocation = true;
  List<dynamic> _allZones = [];
  static const double _defaultZoom = 15.0;
  static const LatLng _defaultCenter = LatLng(12.9716, 77.5946);

  late AnimationController _pulseController;
  late AnimationController _slideController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);

    _slideController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );

    _getCurrentLocation();
    _slideController.forward();
  }

  @override
  void dispose() {
    _mapController.dispose();
    _pulseController.dispose();
    _slideController.dispose();
    super.dispose();
  }

  Future<void> _getCurrentLocation() async {
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
          setState(() {
            _locationError = 'Location permission denied';
            _isLoadingLocation = false;
            _useDefaultLocation();
          });
          return;
        }
      }

      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        setState(() {
          _locationError = 'Location services are disabled';
          _isLoadingLocation = false;
          _useDefaultLocation();
        });
        return;
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );

      setState(() {
        _currentPosition = position;
        _isLoadingLocation = false;
      });

      _animateToCurrentLocation();
    } catch (e) {
      setState(() {
        _locationError = 'Could not get location: $e';
        _isLoadingLocation = false;
        _useDefaultLocation();
      });
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

  void _animateToCurrentLocation() {
    if (_currentPosition == null) return;

    final center = LatLng(
      _currentPosition!.latitude,
      _currentPosition!.longitude,
    );
    _mapController.move(center, _defaultZoom);
  }

  LatLng get _initialCenter {
    if (_currentPosition != null) {
      return LatLng(_currentPosition!.latitude, _currentPosition!.longitude);
    }
    return _defaultCenter;
  }

  void _navigateToZone(dynamic zone) {
    final center = LatLng(zone.latitude, zone.longitude);
    _mapController.move(center, 16.0);

    // Show zone details after navigation
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
          _mapController.move(LatLng(lat, lng), 15.0);
        },
        onZoneSelected: (zone) {
          Navigator.pop(context);
          _navigateToZone(zone);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final zones = getAccidentZones(
      _currentPosition?.latitude,
      _currentPosition?.longitude,
    );

    // Store all zones for search
    _allZones = zones;

    return Scaffold(
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _initialCenter,
              initialZoom: _defaultZoom,
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.example.techathon',
              ),
              CircleLayer(
                circles: [
                  for (final zone in zones)
                    CircleMarker(
                      point: LatLng(zone.latitude, zone.longitude),
                      radius: zone.radiusMeters,
                      useRadiusInMeter: true,
                      color: Color(zone.severityColor).withOpacity(0.25),
                      borderStrokeWidth: 2,
                      borderColor: Color(zone.severityColor),
                    ),
                ],
              ),
              if (_currentPosition != null)
                MarkerLayer(
                  markers: [
                    Marker(
                      point: LatLng(
                        _currentPosition!.latitude,
                        _currentPosition!.longitude,
                      ),
                      width: 60,
                      height: 60,
                      child: AnimatedBuilder(
                        animation: _pulseController,
                        builder: (context, child) {
                          return Stack(
                            alignment: Alignment.center,
                            children: [
                              // Outer pulse ring
                              Container(
                                width:
                                    60 * (0.5 + _pulseController.value * 0.5),
                                height:
                                    60 * (0.5 + _pulseController.value * 0.5),
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: Theme.of(context).primaryColor
                                      .withOpacity(
                                        0.3 * (1 - _pulseController.value),
                                      ),
                                ),
                              ),
                              // Inner dot with shadow
                              Container(
                                width: 20,
                                height: 20,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: Colors.white,
                                  boxShadow: [
                                    BoxShadow(
                                      color: Theme.of(
                                        context,
                                      ).primaryColor.withOpacity(0.5),
                                      blurRadius: 8,
                                      spreadRadius: 2,
                                    ),
                                  ],
                                ),
                                child: Center(
                                  child: Container(
                                    width: 12,
                                    height: 12,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: Theme.of(context).primaryColor,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                  ],
                ),
              MarkerLayer(
                markers: [
                  for (final zone in zones)
                    Marker(
                      point: LatLng(zone.latitude, zone.longitude),
                      width: 40,
                      height: 40,
                      child: GestureDetector(
                        onTap: () => _showZoneDetails(context, zone),
                        child: Container(
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.white,
                            boxShadow: [
                              BoxShadow(
                                color: Color(
                                  zone.severityColor,
                                ).withOpacity(0.4),
                                blurRadius: 8,
                                spreadRadius: 2,
                              ),
                            ],
                          ),
                          child: Icon(
                            Icons.warning_rounded,
                            color: Color(zone.severityColor),
                            size: 28,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
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
          SafeArea(
            child: SlideTransition(
              position:
                  Tween<Offset>(
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
              border: Border.all(
                color: Colors.white.withOpacity(0.3),
                width: 1.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.15),
                  blurRadius: 20,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () => _showLocationSearch(),
                borderRadius: BorderRadius.circular(16),
                child: Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: isTablet ? 20 : 16,
                    vertical: isTablet ? 18 : 14,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.search,
                        color: Colors.grey[700],
                        size: isTablet ? 26 : 22,
                      ),
                      SizedBox(width: isTablet ? 16 : 12),
                      Expanded(
                        child: Text(
                          'Search for a place or address',
                          style: TextStyle(
                            fontSize: isTablet ? 16 : 15,
                            color: Colors.grey[600],
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                      ),
                      if (_locationError != null)
                        Tooltip(
                          message: _locationError!,
                          child: Icon(
                            Icons.error_outline,
                            color: Colors.red,
                            size: isTablet ? 22 : 20,
                          ),
                        )
                      else
                        Container(
                          padding: EdgeInsets.all(isTablet ? 8 : 6),
                          decoration: BoxDecoration(
                            color: Theme.of(
                              context,
                            ).primaryColor.withOpacity(0.1),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.my_location,
                            color: Theme.of(context).primaryColor,
                            size: isTablet ? 18 : 16,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
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
                child: Icon(
                  Icons.my_location_rounded,
                  color: Colors.white,
                  size: isTablet ? 32 : 28,
                ),
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
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
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
                  child: Icon(
                    Icons.warning_rounded,
                    color: Color(zone.severityColor),
                    size: isTablet ? 32 : 28,
                  ),
                ),
                SizedBox(width: isTablet ? 20 : 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        zone.title,
                        style: TextStyle(
                          fontSize: isTablet ? 24 : 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      SizedBox(height: isTablet ? 6 : 4),
                      Text(
                        '${zone.accidentCount} accidents recorded',
                        style: TextStyle(
                          fontSize: isTablet ? 16 : 14,
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            SizedBox(height: isTablet ? 28 : 24),
            Container(
              padding: EdgeInsets.all(isTablet ? 20 : 16),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.info_outline,
                    color: Colors.grey[700],
                    size: isTablet ? 24 : 20,
                  ),
                  SizedBox(width: isTablet ? 16 : 12),
                  Expanded(
                    child: Text(
                      'Drive carefully in this area and follow traffic rules',
                      style: TextStyle(fontSize: isTablet ? 15 : 13),
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(height: isTablet ? 20 : 16),
          ],
        ),
      ),
    );
  }
}

// Location Search Modal Widget
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

  @override
  void initState() {
    super.initState();
    _searchFocusNode.requestFocus();
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
        _filteredZones = widget.allZones.where((zone) {
          return zone.title.toLowerCase().contains(query);
        }).toList();
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
          // Drag handle
          Container(
            margin: const EdgeInsets.only(top: 12, bottom: 16),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey[300],
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          // Search bar
          Padding(
            padding: EdgeInsets.symmetric(
              horizontal: isTablet ? 24 : 16,
              vertical: 8,
            ),
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
                      color: Colors.grey[100],
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: TextField(
                      controller: _searchController,
                      focusNode: _searchFocusNode,
                      style: TextStyle(
                        fontSize: isTablet ? 16 : 15,
                        color: Colors.black87,
                      ),
                      decoration: InputDecoration(
                        hintText: 'Search for a place or address',
                        hintStyle: TextStyle(
                          color: Colors.grey[500],
                          fontSize: isTablet ? 16 : 15,
                        ),
                        prefixIcon: Icon(
                          Icons.search,
                          color: Colors.grey[600],
                          size: isTablet ? 24 : 22,
                        ),
                        suffixIcon: _searchController.text.isNotEmpty
                            ? IconButton(
                                icon: Icon(
                                  Icons.clear,
                                  color: Colors.grey[600],
                                  size: isTablet ? 22 : 20,
                                ),
                                onPressed: () {
                                  _searchController.clear();
                                  _filteredZones = [];
                                  _isSearching = false;
                                  setState(() {});
                                },
                              )
                            : null,
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: isTablet ? 16 : 12,
                          vertical: isTablet ? 16 : 14,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          Divider(height: 1, color: Colors.grey[300]),

          // Results
          Expanded(
            child: _isSearching && _filteredZones.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.search_off,
                          size: isTablet ? 80 : 64,
                          color: Colors.grey[400],
                        ),
                        SizedBox(height: isTablet ? 20 : 16),
                        Text(
                          'No results found',
                          style: TextStyle(
                            fontSize: isTablet ? 18 : 16,
                            color: Colors.grey[600],
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        SizedBox(height: isTablet ? 12 : 8),
                        Text(
                          'Try searching for accident zones',
                          style: TextStyle(
                            fontSize: isTablet ? 14 : 13,
                            color: Colors.grey[500],
                          ),
                        ),
                      ],
                    ),
                  )
                : _isSearching && _filteredZones.isNotEmpty
                ? ListView.separated(
                    padding: EdgeInsets.symmetric(vertical: isTablet ? 12 : 8),
                    itemCount: _filteredZones.length,
                    separatorBuilder: (context, index) =>
                        Divider(height: 1, color: Colors.grey[200]),
                    itemBuilder: (context, index) {
                      final zone = _filteredZones[index];
                      return ListTile(
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: isTablet ? 24 : 16,
                          vertical: isTablet ? 12 : 8,
                        ),
                        leading: Container(
                          padding: EdgeInsets.all(isTablet ? 12 : 10),
                          decoration: BoxDecoration(
                            color: Color(zone.severityColor).withOpacity(0.1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(
                            Icons.warning_rounded,
                            color: Color(zone.severityColor),
                            size: isTablet ? 26 : 24,
                          ),
                        ),
                        title: Text(
                          zone.title,
                          style: TextStyle(
                            fontSize: isTablet ? 16 : 15,
                            fontWeight: FontWeight.w600,
                            color: Colors.black87,
                          ),
                        ),
                        subtitle: Text(
                          '${zone.accidentCount} accidents recorded',
                          style: TextStyle(
                            fontSize: isTablet ? 14 : 13,
                            color: Colors.grey[600],
                          ),
                        ),
                        trailing: Icon(
                          Icons.arrow_forward_ios,
                          size: isTablet ? 18 : 16,
                          color: Colors.grey[400],
                        ),
                        onTap: () => widget.onZoneSelected(zone),
                      );
                    },
                  )
                : _buildRecentAndSuggestions(isTablet),
          ),

          // Bottom padding for keyboard
          SizedBox(height: keyboardHeight > 0 ? keyboardHeight : 0),
        ],
      ),
    );
  }

  Widget _buildRecentAndSuggestions(bool isTablet) {
    return ListView(
      padding: EdgeInsets.symmetric(
        horizontal: isTablet ? 24 : 16,
        vertical: isTablet ? 16 : 12,
      ),
      children: [
        // Current Location
        ListTile(
          contentPadding: EdgeInsets.symmetric(vertical: isTablet ? 12 : 8),
          leading: Container(
            padding: EdgeInsets.all(isTablet ? 12 : 10),
            decoration: BoxDecoration(
              color: Colors.blue.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              Icons.my_location,
              color: Colors.blue,
              size: isTablet ? 26 : 24,
            ),
          ),
          title: Text(
            'Use current location',
            style: TextStyle(
              fontSize: isTablet ? 16 : 15,
              fontWeight: FontWeight.w600,
              color: Colors.black87,
            ),
          ),
          subtitle: Text(
            'Find accident zones near you',
            style: TextStyle(
              fontSize: isTablet ? 14 : 13,
              color: Colors.grey[600],
            ),
          ),
          onTap: () => Navigator.pop(context),
        ),

        SizedBox(height: isTablet ? 24 : 16),

        // Accident Zones Section
        Text(
          'Accident-Prone Areas',
          style: TextStyle(
            fontSize: isTablet ? 15 : 14,
            fontWeight: FontWeight.bold,
            color: Colors.grey[800],
          ),
        ),
        SizedBox(height: isTablet ? 16 : 12),

        // Show all zones
        ...widget.allZones.take(8).map((zone) {
          return Column(
            children: [
              ListTile(
                contentPadding: EdgeInsets.symmetric(
                  vertical: isTablet ? 8 : 4,
                ),
                leading: Container(
                  padding: EdgeInsets.all(isTablet ? 10 : 8),
                  decoration: BoxDecoration(
                    color: Color(zone.severityColor).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    Icons.place,
                    color: Color(zone.severityColor),
                    size: isTablet ? 24 : 22,
                  ),
                ),
                title: Text(
                  zone.title,
                  style: TextStyle(
                    fontSize: isTablet ? 15 : 14,
                    fontWeight: FontWeight.w500,
                    color: Colors.black87,
                  ),
                ),
                subtitle: Text(
                  '${zone.accidentCount} accidents',
                  style: TextStyle(
                    fontSize: isTablet ? 13 : 12,
                    color: Colors.grey[600],
                  ),
                ),
                trailing: Icon(
                  Icons.north_west,
                  size: isTablet ? 18 : 16,
                  color: Colors.grey[400],
                ),
                onTap: () => widget.onZoneSelected(zone),
              ),
              if (widget.allZones.indexOf(zone) < 7)
                Divider(height: 1, color: Colors.grey[200]),
            ],
          );
        }).toList(),
      ],
    );
  }
}
