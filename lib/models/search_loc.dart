import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

class LocationSearchModel {
  final String name;
  final String displayName;
  final double latitude;
  final double longitude;

  const LocationSearchModel({
    required this.name,
    required this.displayName,
    required this.latitude,
    required this.longitude,
  });

  factory LocationSearchModel.fromJson(Map<String, dynamic> json) {
    return LocationSearchModel(
      name: (json['display_name'] as String).split(',').first,
      displayName: json['display_name'],
      latitude: double.parse(json['lat']),
      longitude: double.parse(json['lon']),
    );
  }
}

class LocationSearchModal extends StatefulWidget {
  final List<dynamic> allZones;
  final Function(double, double, String) onLocationSelected;
  final Function(dynamic) onZoneSelected;

  const LocationSearchModal({
    super.key,
    required this.allZones,
    required this.onLocationSelected,
    required this.onZoneSelected,
  });

  @override
  State<LocationSearchModal> createState() => _LocationSearchModalState();
}

class _LocationSearchModalState extends State<LocationSearchModal> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _focusNode = FocusNode();

  List<dynamic> _filteredZones = [];
  List<LocationSearchModel> _placeResults = [];

  bool _isSearching = false;
  bool _isLoadingPlaces = false;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _focusNode.requestFocus();
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchController.dispose();
    _focusNode.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onSearchChanged() {
    final query = _searchController.text.trim().toLowerCase();

    if (_debounce?.isActive ?? false) _debounce!.cancel();

    if (query.isEmpty) {
      setState(() {
        _isSearching = false;
        _filteredZones = [];
        _placeResults = [];
        _isLoadingPlaces = false;
      });
      return;
    }

    setState(() {
      _isSearching = true;
      _filteredZones = widget.allZones.where((zone) {
        return zone.title.toLowerCase().contains(query);
      }).toList();
    });

    if (query.length >= 3) {
      // Show loading immediately so the user knows a search is pending
      setState(() => _isLoadingPlaces = true);
      _debounce = Timer(const Duration(milliseconds: 500), () {
        _searchPlaces(query);
      });
    } else {
      setState(() {
        _placeResults = [];
        _isLoadingPlaces = false;
      });
    }
  }

  Future<void> _searchPlaces(String query) async {
    try {
      final uri = Uri.https('nominatim.openstreetmap.org', '/search', {
        'q': query,
        'format': 'json',
        'limit': '6',
        'countrycodes': 'in',
      });

      final response = await http.get(
        uri,
        headers: {'User-Agent': 'techathon-app'},
      );

      if (response.statusCode == 200) {
        final List data = json.decode(response.body);
        if (mounted) {
          setState(() {
            _placeResults = data
                .map((e) => LocationSearchModel.fromJson(e))
                .toList();
          });
        }
      }
    } catch (e) {
      debugPrint("Search error: $e");
    }

    if (mounted) setState(() => _isLoadingPlaces = false);
  }

  bool get _hasNoResults =>
      _isSearching &&
      !_isLoadingPlaces &&
      _placeResults.isEmpty &&
      _filteredZones.isEmpty;

  @override
  Widget build(BuildContext context) {
    final isTablet = MediaQuery.of(context).size.width > 600;
    final keyboardHeight = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      height: MediaQuery.of(context).size.height * 0.9,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          // ── Handle bar ────────────────────────────────────────────────
          const SizedBox(height: 12),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey[300],
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),

          // ── Search Bar ────────────────────────────────────────────────
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
                      focusNode: _focusNode,
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
                                  setState(() {
                                    _filteredZones = [];
                                    _placeResults = [];
                                    _isSearching = false;
                                    _isLoadingPlaces = false;
                                  });
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

          // ── Body ──────────────────────────────────────────────────────
          Expanded(
            child: !_isSearching
                ? _buildDefaultList(isTablet)
                : _hasNoResults
                ? _buildNoResults(isTablet)
                : _buildSearchResults(isTablet),
          ),

          SizedBox(height: keyboardHeight),
        ],
      ),
    );
  }

  // ── Default (no query) ─────────────────────────────────────────────────────
  Widget _buildDefaultList(bool isTablet) {
    return ListView(
      padding: EdgeInsets.symmetric(
        horizontal: isTablet ? 24 : 16,
        vertical: isTablet ? 16 : 12,
      ),
      children: [
        // Current location tile
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
        Text(
          'Accident-Prone Areas',
          style: TextStyle(
            fontSize: isTablet ? 15 : 14,
            fontWeight: FontWeight.bold,
            color: Colors.grey[800],
          ),
        ),
        SizedBox(height: isTablet ? 16 : 12),

        if (widget.allZones.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Center(
              child: Text(
                'No zones loaded yet',
                style: TextStyle(color: Colors.grey[500], fontSize: 14),
              ),
            ),
          )
        else
          ...widget.allZones.take(8).toList().asMap().entries.map((e) {
            final zone = e.value;
            final isLast = e.key >= widget.allZones.take(8).length - 1;
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
                    '${zone.accidentCount} accident${zone.accidentCount == 1 ? '' : 's'}',
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
                if (!isLast) Divider(height: 1, color: Colors.grey[200]),
              ],
            );
          }).toList(),
      ],
    );
  }

  // ── No results state ───────────────────────────────────────────────────────
  Widget _buildNoResults(bool isTablet) {
    return Center(
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
            'Try a different search term',
            style: TextStyle(
              fontSize: isTablet ? 14 : 13,
              color: Colors.grey[500],
            ),
          ),
        ],
      ),
    );
  }

  // ── Search results ─────────────────────────────────────────────────────────
  Widget _buildSearchResults(bool isTablet) {
    return ListView(
      padding: EdgeInsets.symmetric(vertical: isTablet ? 12 : 8),
      children: [
        // ── Places from Nominatim ──────────────────────────────────────
        if (_isLoadingPlaces) ...[
          Padding(
            padding: EdgeInsets.symmetric(
              horizontal: isTablet ? 24 : 16,
              vertical: 12,
            ),
            child: Row(
              children: [
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation(Colors.grey[500]),
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  'Searching places...',
                  style: TextStyle(
                    color: Colors.grey[500],
                    fontSize: isTablet ? 14 : 13,
                  ),
                ),
              ],
            ),
          ),
        ] else if (_placeResults.isNotEmpty) ...[
          _sectionHeader('Places', isTablet),
          ...List.generate(_placeResults.length, (index) {
            final place = _placeResults[index];
            final isLast = index == _placeResults.length - 1;
            return Column(
              children: [
                ListTile(
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: isTablet ? 24 : 16,
                    vertical: isTablet ? 8 : 4,
                  ),
                  leading: Container(
                    padding: EdgeInsets.all(isTablet ? 10 : 8),
                    decoration: BoxDecoration(
                      color: Colors.blue.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      Icons.location_on,
                      color: Colors.blue,
                      size: isTablet ? 24 : 22,
                    ),
                  ),
                  title: Text(
                    place.name,
                    style: TextStyle(
                      fontSize: isTablet ? 15 : 14,
                      fontWeight: FontWeight.w600,
                      color: Colors.black87,
                    ),
                  ),
                  subtitle: Text(
                    place.displayName,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
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
                  onTap: () {
                    widget.onLocationSelected(
                      place.latitude,
                      place.longitude,
                      place.displayName,
                    );
                  },
                ),
                if (!isLast) Divider(height: 1, color: Colors.grey[200]),
              ],
            );
          }),
        ],

        // ── Matching accident zones ────────────────────────────────────
        if (_filteredZones.isNotEmpty) ...[
          _sectionHeader('Accident Zones', isTablet),
          ...List.generate(_filteredZones.length, (index) {
            final zone = _filteredZones[index];
            final isLast = index == _filteredZones.length - 1;
            return Column(
              children: [
                ListTile(
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: isTablet ? 24 : 16,
                    vertical: isTablet ? 8 : 4,
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
                ),
                if (!isLast) Divider(height: 1, color: Colors.grey[200]),
              ],
            );
          }),
        ],
      ],
    );
  }

  Widget _sectionHeader(String title, bool isTablet) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        isTablet ? 24 : 16,
        isTablet ? 20 : 16,
        isTablet ? 24 : 16,
        isTablet ? 8 : 6,
      ),
      child: Text(
        title,
        style: TextStyle(
          fontSize: isTablet ? 13 : 12,
          fontWeight: FontWeight.bold,
          color: Colors.grey[500],
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}
