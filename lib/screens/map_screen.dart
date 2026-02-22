import 'dart:async';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:latlong2/latlong.dart';
import 'package:techathon/models/search_loc.dart';
import '../data/accident_zones_data.dart';
import 'package:google_generative_ai/google_generative_ai.dart';

// ---------------------------------------------------------------------------
// Proper Heatmap Layer — pixel-buffer Gaussian density accumulation
// ---------------------------------------------------------------------------
class _HeatmapLayer extends StatefulWidget {
  final List<dynamic> zones;
  const _HeatmapLayer({required this.zones});

  @override
  State<_HeatmapLayer> createState() => _HeatmapLayerState();
}

class _HeatmapLayerState extends State<_HeatmapLayer> {
  ui.Image? _heatmapImage;
  MapCamera? _lastCamera;
  List<dynamic>? _lastZones;
  bool _building = false;

  @override
  Widget build(BuildContext context) {
    final camera = MapCamera.of(context);

    if (!_building && (camera != _lastCamera || widget.zones != _lastZones)) {
      _lastCamera = camera;
      _lastZones = widget.zones;
      _buildHeatmapImage(camera, context);
    }

    return MobileLayerTransformer(
      child: _heatmapImage == null
          ? const SizedBox.shrink()
          : CustomPaint(
              painter: _HeatmapImagePainter(image: _heatmapImage!),
              size: Size(
                MediaQuery.of(context).size.width,
                MediaQuery.of(context).size.height,
              ),
            ),
    );
  }

  Future<void> _buildHeatmapImage(
    MapCamera camera,
    BuildContext context,
  ) async {
    if (widget.zones.isEmpty) return;
    _building = true;

    final size = MediaQuery.of(context).size;
    final w = size.width.toInt();
    final h = size.height.toInt();

    const scale = 2;
    final gw = (w / scale).ceil();
    final gh = (h / scale).ceil();
    final density = Float32List(gw * gh);
    double maxDensity = 0;

    for (final zone in widget.zones) {
      final screenOffset = camera.latLngToScreenOffset(
        LatLng(zone.latitude as double, zone.longitude as double),
      );

      final px = screenOffset.dx / scale;
      final py = screenOffset.dy / scale;

      final metersPerPx = _metersPerPixel(camera.zoom, zone.latitude as double);
      final radiusPx = ((zone.radiusMeters as double) / metersPerPx / scale)
          .clamp(20.0, 280.0);

      final weight = _zoneWeight(zone);

      final minX = (px - radiusPx).floor().clamp(0, gw - 1);
      final maxX = (px + radiusPx).ceil().clamp(0, gw - 1);
      final minY = (py - radiusPx).floor().clamp(0, gh - 1);
      final maxY = (py + radiusPx).ceil().clamp(0, gh - 1);
      final r2 = radiusPx * radiusPx;

      for (int gy = minY; gy <= maxY; gy++) {
        for (int gx = minX; gx <= maxX; gx++) {
          final dx = gx - px;
          final dy = gy - py;
          final dist2 = dx * dx + dy * dy;
          if (dist2 > r2) continue;

          final gaussian = exp(-3.5 * dist2 / r2);
          density[gy * gw + gx] += gaussian * weight;
          if (density[gy * gw + gx] > maxDensity) {
            maxDensity = density[gy * gw + gx];
          }
        }
      }
    }

    if (maxDensity == 0) {
      _building = false;
      return;
    }

    final rgba = Uint8List(gw * gh * 4);
    for (int i = 0; i < gw * gh; i++) {
      final t = (density[i] / maxDensity).clamp(0.0, 1.0);
      if (t < 0.02) continue;

      final color = _heatColor(t);
      final alpha = ((t - 0.02) / 0.98 * 210).round().clamp(0, 210);

      rgba[i * 4 + 0] = color.red;
      rgba[i * 4 + 1] = color.green;
      rgba[i * 4 + 2] = color.blue;
      rgba[i * 4 + 3] = alpha;
    }

    final completer = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      rgba,
      gw,
      gh,
      ui.PixelFormat.rgba8888,
      completer.complete,
    );
    final image = await completer.future;

    if (mounted) {
      setState(() {
        _heatmapImage?.dispose();
        _heatmapImage = image;
        _building = false;
      });
    } else {
      image.dispose();
      _building = false;
    }
  }

  static double _zoneWeight(dynamic zone) {
    final severity = (zone.severityLevel as int).clamp(1, 5) / 5.0;
    final count = (zone.accidentCount as int).clamp(1, 50) / 50.0;
    return severity * 0.6 + count * 0.4;
  }

  static double _metersPerPixel(double zoom, double latitude) {
    const earthCircumference = 40075016.686;
    return earthCircumference * cos(latitude * pi / 180) / pow(2, zoom + 8);
  }

  static Color _heatColor(double t) {
    const stops = [
      Color(0xFF0000FF),
      Color(0xFF00FFFF),
      Color(0xFF00FF00),
      Color(0xFFFFFF00),
      Color(0xFFFF0000),
    ];
    if (t <= 0) return stops[0];
    if (t >= 1) return stops[4];
    final pos = t * (stops.length - 1);
    final lo = pos.floor().clamp(0, stops.length - 2);
    return Color.lerp(stops[lo], stops[lo + 1], pos - lo)!;
  }

  @override
  void dispose() {
    _heatmapImage?.dispose();
    super.dispose();
  }
}

class _HeatmapImagePainter extends CustomPainter {
  final ui.Image image;
  const _HeatmapImagePainter({required this.image});

  @override
  void paint(Canvas canvas, Size size) {
    final src = Rect.fromLTWH(
      0,
      0,
      image.width.toDouble(),
      image.height.toDouble(),
    );
    final dst = Rect.fromLTWH(0, 0, size.width, size.height);
    final paint = Paint()
      ..filterQuality = FilterQuality.medium
      ..isAntiAlias = true;
    canvas.drawImageRect(image, src, dst, paint);
  }

  @override
  bool shouldRepaint(_HeatmapImagePainter old) => old.image != image;
}

// ---------------------------------------------------------------------------
// AI Risk Analysis Data Model
// ---------------------------------------------------------------------------
class AiRiskAnalysis {
  final String riskLevel;
  final double riskScore;
  final String riskSummary;
  final List<String> primaryDrivers;
  final List<String> recommendedActions;

  AiRiskAnalysis({
    required this.riskLevel,
    required this.riskScore,
    required this.riskSummary,
    required this.primaryDrivers,
    required this.recommendedActions,
  });
}

// ---------------------------------------------------------------------------
// Risk Score Normalizer
// Bands:  Low = 0.00–0.40 | Medium = 0.41–0.70 | High = 0.71–1.00
// ---------------------------------------------------------------------------
({String riskLevel, double riskScore}) _normalizeRisk(double rawScore) {
  if (rawScore <= 0.40) {
    return (riskLevel: 'Low', riskScore: rawScore.clamp(0.0, 0.40));
  } else if (rawScore <= 0.70) {
    return (riskLevel: 'Medium', riskScore: rawScore.clamp(0.41, 0.70));
  } else {
    return (riskLevel: 'High', riskScore: rawScore.clamp(0.71, 1.0));
  }
}

// ---------------------------------------------------------------------------
// AI Risk Analysis Service
// ---------------------------------------------------------------------------
Future<AiRiskAnalysis> fetchAiRiskAnalysis(double lat, double lon) async {
  // ── Step 1: Existing risk-score API ──────────────────────────────────────
  final uri = Uri.parse(
    'https://ai-road-risk-intelligence.onrender.com/predict_location?lat=$lat&lon=$lon',
  );
  final response = await http.post(uri).timeout(const Duration(seconds: 30));
  if (response.statusCode != 200) {
    throw Exception('Failed to fetch risk score: ${response.statusCode}');
  }

  final scoreJson = jsonDecode(response.body) as Map<String, dynamic>;
  final rawScore = (scoreJson['risk_score'] as num).toDouble();

  // ── Step 2: Normalize score → consistent level + clamped score ───────────
  final normalized = _normalizeRisk(rawScore);
  final riskLevel = normalized.riskLevel;
  final riskScore = normalized.riskScore;

  // ── Step 3: Gemini for natural-language narrative ─────────────────────────
  final model = GenerativeModel(
    model: 'gemini-2.5-flash',
    apiKey: 'AIzaSyCWy4pFkoocKlJzwG4IWkDbpR4rEBZzXf4',
  );

  final prompt =
      '''
You are a road safety analyst. A machine-learning model has assessed the accident risk for the road location at coordinates ($lat, $lon).

Assessment result:
- Risk Level: $riskLevel  (Low = 0–40%, Medium = 41–70%, High = 71–100%)
- Risk Score: ${(riskScore * 100).toStringAsFixed(1)}%

Using your knowledge of typical road hazards for this type of score and location, respond ONLY with the following JSON — no markdown, no extra text:

{
  "riskSummary": "A 2–3 sentence explanation of why this location carries a $riskLevel risk level at ${(riskScore * 100).toStringAsFixed(1)}%.",
  "primaryDrivers": ["Short driver label 1", "Short driver label 2", "Short driver label 3"],
  "recommendedActions": ["Actionable advice 1", "Actionable advice 2", "Actionable advice 3"]
}
''';

  final geminiResponse = await model.generateContent([Content.text(prompt)]);
  final rawText = (geminiResponse.text ?? '{}').trim();

  // Strip any accidental markdown fences Gemini might add
  final cleaned = rawText
      .replaceAll(RegExp(r'^```json\s*', multiLine: true), '')
      .replaceAll(RegExp(r'^```\s*', multiLine: true), '')
      .trim();

  final geminiJson = jsonDecode(cleaned) as Map<String, dynamic>;

  return AiRiskAnalysis(
    riskLevel: riskLevel,
    riskScore: riskScore,
    riskSummary: geminiJson['riskSummary'] as String,
    primaryDrivers: (geminiJson['primaryDrivers'] as List)
        .map((e) => e.toString())
        .toList(),
    recommendedActions: (geminiJson['recommendedActions'] as List)
        .map((e) => e.toString())
        .toList(),
  );
}

// ---------------------------------------------------------------------------
// AI Risk Summary Bottom Sheet
// ---------------------------------------------------------------------------
class _AiRiskSheet extends StatelessWidget {
  final LatLng location;
  final AiRiskAnalysis analysis;

  const _AiRiskSheet({required this.location, required this.analysis});

  Color get _riskColor {
    switch (analysis.riskLevel.toLowerCase()) {
      case 'high':
        return const Color(0xFFE53935);
      case 'medium':
        return const Color(0xFFFB8C00);
      case 'low':
        return const Color(0xFF43A047);
      default:
        return const Color(0xFF1E88E5);
    }
  }

  IconData get _riskIcon {
    switch (analysis.riskLevel.toLowerCase()) {
      case 'high':
        return Icons.dangerous_rounded;
      case 'medium':
        return Icons.warning_amber_rounded;
      case 'low':
        return Icons.check_circle_rounded;
      default:
        return Icons.info_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isTablet = MediaQuery.of(context).size.width > 600;
    final scorePercent = (analysis.riskScore * 100).toStringAsFixed(1);

    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF0F1923),
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(28),
          topRight: Radius.circular(28),
        ),
      ),
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          isTablet ? 32 : 20,
          16,
          isTablet ? 32 : 20,
          MediaQuery.of(context).padding.bottom + 24,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Drag handle
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 20),
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),

            // Header with AI badge
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF6C63FF), Color(0xFF3B82F6)],
                    ),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.auto_awesome, color: Colors.white, size: 12),
                      SizedBox(width: 4),
                      Text(
                        'AI Analysis',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                Text(
                  '${location.latitude.toStringAsFixed(4)}, ${location.longitude.toStringAsFixed(4)}',
                  style: const TextStyle(color: Colors.white38, fontSize: 11),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // Risk level card
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: _riskColor.withOpacity(0.12),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: _riskColor.withOpacity(0.3),
                  width: 1.5,
                ),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: _riskColor.withOpacity(0.2),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(_riskIcon, color: _riskColor, size: 28),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${analysis.riskLevel} Risk',
                          style: TextStyle(
                            color: _riskColor,
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.3,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Risk Score: $scorePercent%',
                          style: const TextStyle(
                            color: Colors.white60,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Score ring
                  SizedBox(
                    width: 56,
                    height: 56,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        CircularProgressIndicator(
                          value: analysis.riskScore,
                          strokeWidth: 5,
                          backgroundColor: Colors.white12,
                          valueColor: AlwaysStoppedAnimation(_riskColor),
                        ),
                        Text(
                          '$scorePercent%',
                          style: TextStyle(
                            color: _riskColor,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // Risk Summary
            _SectionLabel(label: 'Risk Summary'),
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.05),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.white12),
              ),
              child: Text(
                analysis.riskSummary,
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 13.5,
                  height: 1.65,
                ),
              ),
            ),

            const SizedBox(height: 20),

            // Primary Risk Drivers
            _SectionLabel(label: 'Primary Risk Drivers'),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: analysis.primaryDrivers.map((driver) {
                final label = driver.replaceAll('_', ' ');
                return Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 7,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF6C63FF).withOpacity(0.15),
                    borderRadius: BorderRadius.circular(30),
                    border: Border.all(
                      color: const Color(0xFF6C63FF).withOpacity(0.4),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.trending_up_rounded,
                        color: Color(0xFF9B8BFF),
                        size: 14,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        label,
                        style: const TextStyle(
                          color: Color(0xFFBEB5FF),
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),

            const SizedBox(height: 20),

            // Recommended Actions
            _SectionLabel(label: 'Recommended Actions'),
            const SizedBox(height: 10),
            ...analysis.recommendedActions.asMap().entries.map((entry) {
              final index = entry.key;
              final action = entry.value;
              return Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.04),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.white10),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 26,
                      height: 26,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF3B82F6), Color(0xFF6C63FF)],
                        ),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        '${index + 1}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        action,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 13,
                          height: 1.55,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String label;
  const _SectionLabel({required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 3,
          height: 16,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF6C63FF), Color(0xFF3B82F6)],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 14,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.3,
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Loading sheet shown while AI analysis is fetching
// ---------------------------------------------------------------------------
class _AiLoadingSheet extends StatefulWidget {
  final LatLng location;
  const _AiLoadingSheet({required this.location});

  @override
  State<_AiLoadingSheet> createState() => _AiLoadingSheetState();
}

class _AiLoadingSheetState extends State<_AiLoadingSheet>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF0F1923),
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(28),
          topRight: Radius.circular(28),
        ),
      ),
      padding: EdgeInsets.fromLTRB(
        24,
        16,
        24,
        MediaQuery.of(context).padding.bottom + 40,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 32),
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          RotationTransition(
            turns: _controller,
            child: Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const SweepGradient(
                  colors: [
                    Color(0xFF6C63FF),
                    Color(0xFF3B82F6),
                    Colors.transparent,
                  ],
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF6C63FF).withOpacity(0.4),
                    blurRadius: 20,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: const Center(
                child: Icon(Icons.auto_awesome, color: Colors.white, size: 24),
              ),
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            'Analyzing Location',
            style: TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '${widget.location.latitude.toStringAsFixed(4)}, ${widget.location.longitude.toStringAsFixed(4)}',
            style: const TextStyle(color: Colors.white38, fontSize: 13),
          ),
          const SizedBox(height: 8),
          const Text(
            'AI is computing accident risk factors…',
            style: TextStyle(color: Colors.white54, fontSize: 13),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// MapScreen
// ---------------------------------------------------------------------------
class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> with TickerProviderStateMixin {
  final MapController _mapController = MapController();
  Position? _currentPosition;
  String? _locationError;
  bool _isLoadingLocation = true;
  bool _isLoadingZones = false;
  bool _showHeatmap = false;
  List _allZones = [];

  LatLng? _selectedLocation;

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

  void _onDoubleTap(TapPosition tapPosition, LatLng latlng) {
    setState(() => _selectedLocation = latlng);
    _showAiAnalysis(latlng);
  }

  Future<void> _showAiAnalysis(LatLng location) async {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      isDismissible: true,
      builder: (ctx) => _AiLoadingSheet(location: location),
    );

    try {
      final analysis = await fetchAiRiskAnalysis(
        location.latitude,
        location.longitude,
      );

      if (!mounted) return;
      Navigator.of(context).pop();

      showModalBottomSheet(
        context: context,
        backgroundColor: Colors.transparent,
        isScrollControlled: true,
        builder: (ctx) => DraggableScrollableSheet(
          initialChildSize: 0.75,
          minChildSize: 0.4,
          maxChildSize: 0.95,
          expand: false,
          builder: (ctx, scrollController) =>
              _AiRiskSheet(location: location, analysis: analysis),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('AI analysis failed: $e'),
          backgroundColor: Colors.red[700],
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      );
    }
  }

  Future<void> _loadZones() async {
    setState(() => _isLoadingZones = true);
    try {
      final zones = await getAccidentZones(
        _currentPosition?.latitude,
        _currentPosition?.longitude,
      );
      if (mounted) {
        setState(() {
          _allZones = zones;
          _isLoadingZones = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoadingZones = false);
    }
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
          await _loadZones();
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
        await _loadZones();
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
      await _loadZones();
    } catch (e) {
      setState(() {
        _locationError = 'Could not get location: $e';
        _isLoadingLocation = false;
        _useDefaultLocation();
      });
      await _loadZones();
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
    _mapController.move(
      LatLng(_currentPosition!.latitude, _currentPosition!.longitude),
      _defaultZoom,
    );
  }

  LatLng get _initialCenter => _currentPosition != null
      ? LatLng(_currentPosition!.latitude, _currentPosition!.longitude)
      : _defaultCenter;

  void _navigateToZone(dynamic zone) {
    _mapController.move(LatLng(zone.latitude, zone.longitude), 16.0);
    Future.delayed(
      const Duration(milliseconds: 500),
      () => _showZoneDetails(context, zone),
    );
  }

  void _showLocationSearch() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => LocationSearchModal(
        allZones: _allZones,
        onLocationSelected: (lat, lng, name) async {
          Navigator.pop(context);
          setState(() {
            _currentPosition = Position(
              latitude: lat,
              longitude: lng,
              timestamp: DateTime.now(),
              accuracy: 0,
              altitude: 0,
              altitudeAccuracy: 0,
              heading: 0,
              headingAccuracy: 0,
              speed: 0,
              speedAccuracy: 0,
            );
          });
          _mapController.move(LatLng(lat, lng), 15.0);
          await _loadZones();
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
    return Scaffold(
      body: Stack(
        children: [
          // ── Map ─────────────────────────────────────────────────────
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _initialCenter,
              initialZoom: _defaultZoom,
              onTap: _onDoubleTap,
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.example.techathon',
              ),

              if (_showHeatmap && _allZones.isNotEmpty)
                _HeatmapLayer(zones: _allZones),

              if (!_showHeatmap && _allZones.isNotEmpty)
                CircleLayer(
                  circles: [
                    for (final zone in _allZones)
                      CircleMarker(
                        point: LatLng(zone.latitude, zone.longitude),
                        radius: zone.radiusMeters,
                        useRadiusInMeter: true,
                        color: Color(zone.severityColor).withOpacity(0.15),
                        borderStrokeWidth: 1.5,
                        borderColor: Color(zone.severityColor).withOpacity(0.7),
                      ),
                  ],
                ),

              // ── Current location marker ──────────────────────────────
              if (_currentPosition != null)
                MarkerLayer(
                  markers: [
                    Marker(
                      point: LatLng(
                        _currentPosition!.latitude,
                        _currentPosition!.longitude,
                      ),
                      width: 80,
                      height: 80,
                      child: AnimatedBuilder(
                        animation: _pulseController,
                        builder: (context, _) => Stack(
                          alignment: Alignment.center,
                          children: [
                            Container(
                              width: 80 * _pulseController.value,
                              height: 80 * _pulseController.value,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: const Color(0xFF4285F4).withOpacity(
                                  0.15 * (1 - _pulseController.value),
                                ),
                              ),
                            ),
                            Container(
                              width: 22,
                              height: 22,
                              decoration: const BoxDecoration(
                                shape: BoxShape.circle,
                                color: Colors.white,
                                boxShadow: [
                                  BoxShadow(
                                    color: Color(0x554285F4),
                                    blurRadius: 6,
                                    spreadRadius: 1,
                                  ),
                                  BoxShadow(
                                    color: Color(0x22000000),
                                    blurRadius: 4,
                                    offset: Offset(0, 2),
                                  ),
                                ],
                              ),
                            ),
                            Container(
                              width: 14,
                              height: 14,
                              decoration: const BoxDecoration(
                                shape: BoxShape.circle,
                                color: Color(0xFF4285F4),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),

              // ── Selected location pin ────────────────────────────────
              if (_selectedLocation != null)
                MarkerLayer(
                  markers: [
                    Marker(
                      point: _selectedLocation!,
                      width: 44,
                      height: 52,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 38,
                            height: 38,
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [Color(0xFF6C63FF), Color(0xFF3B82F6)],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(
                                    0xFF6C63FF,
                                  ).withOpacity(0.5),
                                  blurRadius: 12,
                                  spreadRadius: 2,
                                ),
                              ],
                              border: Border.all(
                                color: Colors.white,
                                width: 2.5,
                              ),
                            ),
                            child: const Icon(
                              Icons.auto_awesome,
                              color: Colors.white,
                              size: 18,
                            ),
                          ),
                          Container(
                            width: 2,
                            height: 10,
                            color: const Color(0xFF6C63FF),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),

              if (_allZones.isNotEmpty)
                MarkerLayer(
                  markers: [
                    for (final zone in _allZones)
                      Marker(
                        point: LatLng(zone.latitude, zone.longitude),
                        width: 18,
                        height: 18,
                        child: GestureDetector(
                          onTap: () => _showZoneDetails(context, zone),
                          child: Container(
                            decoration: BoxDecoration(
                              color: Color(zone.severityColor),
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 2),
                              boxShadow: [
                                BoxShadow(
                                  color: Color(
                                    zone.severityColor,
                                  ).withOpacity(0.6),
                                  blurRadius: 6,
                                  spreadRadius: 1,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
            ],
          ),

          // ── Heatmap legend ──────────────────────────────────────────
          if (_showHeatmap && _allZones.isNotEmpty)
            Positioned(bottom: 110, left: 16, child: _buildLegend()),

          // ── Tap hint tooltip ────────────────────────────────────────
          Positioned(
            bottom: 110,
            right: 16,
            child: AnimatedOpacity(
              opacity: _selectedLocation == null ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 600),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 7,
                ),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.65),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.touch_app, color: Colors.white70, size: 14),
                    SizedBox(width: 6),
                    Text(
                      'Tap for AI analysis',
                      style: TextStyle(color: Colors.white70, fontSize: 11),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // ── Loading overlay ─────────────────────────────────────────
          if (_isLoadingLocation || _isLoadingZones)
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
                              valueColor: AlwaysStoppedAnimation(
                                Theme.of(context).primaryColor,
                              ),
                            ),
                          ),
                          SizedBox(height: isTablet ? 24 : 20),
                          Text(
                            _isLoadingLocation
                                ? 'Locating you...'
                                : 'Loading risk zones...',
                            style: TextStyle(
                              fontSize: isTablet ? 20 : 18,
                              fontWeight: FontWeight.w600,
                              color: Colors.black87,
                            ),
                          ),
                          SizedBox(height: isTablet ? 10 : 8),
                          Text(
                            _isLoadingLocation
                                ? 'Finding accident-prone areas nearby'
                                : 'Fetching live data from the server',
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

          // ── UI controls ─────────────────────────────────────────────
          SafeArea(
            child: SlideTransition(
              position: Tween(begin: const Offset(0, -1), end: Offset.zero)
                  .animate(
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
                  _buildBottomButtons(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLegend() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.55),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Risk Level',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 6),
              Container(
                width: 120,
                height: 10,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(5),
                  gradient: const LinearGradient(
                    colors: [
                      Color(0xFF0000FF),
                      Color(0xFF00FFFF),
                      Color(0xFF00FF00),
                      Color(0xFFFFFF00),
                      Color(0xFFFF0000),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 4),
              const Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Low',
                    style: TextStyle(color: Colors.white70, fontSize: 9),
                  ),
                  Text(
                    'High',
                    style: TextStyle(color: Colors.white70, fontSize: 9),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    final isTablet = MediaQuery.of(context).size.width > 600;
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
                onTap: _showLocationSearch,
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
                      if (_isLoadingZones)
                        SizedBox(
                          width: isTablet ? 20 : 16,
                          height: isTablet ? 20 : 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation(
                              Theme.of(context).primaryColor,
                            ),
                          ),
                        )
                      else if (_locationError != null)
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

  Widget _buildBottomButtons() {
    final isTablet = MediaQuery.of(context).size.width > 600;
    return Padding(
      padding: EdgeInsets.all(isTablet ? 24 : 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          _FABButton(
            onTap: _isLoadingZones ? null : _loadZones,
            isTablet: isTablet,
            active: false,
            activeColor: Colors.green,
            inactiveColor: Colors.white,
            tooltip: 'Refresh risk zones',
            child: Icon(
              Icons.refresh_rounded,
              color: _isLoadingZones ? Colors.grey : Colors.green,
              size: isTablet ? 30 : 26,
            ),
          ),
          SizedBox(width: isTablet ? 14 : 10),
          _FABButton(
            onTap: () => setState(() => _showHeatmap = !_showHeatmap),
            isTablet: isTablet,
            active: _showHeatmap,
            activeColor: Colors.deepOrange,
            inactiveColor: Colors.white,
            tooltip: _showHeatmap ? 'Hide heatmap' : 'Show heatmap',
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 250),
              child: _showHeatmap
                  ? Icon(
                      Icons.layers_clear_rounded,
                      key: const ValueKey('off'),
                      color: Colors.white,
                      size: isTablet ? 30 : 26,
                    )
                  : Icon(
                      Icons.layers_rounded,
                      key: const ValueKey('on'),
                      color: Colors.deepOrange,
                      size: isTablet ? 30 : 26,
                    ),
            ),
          ),
          SizedBox(width: isTablet ? 14 : 10),
          _FABButton(
            onTap: _isLoadingLocation ? null : _animateToCurrentLocation,
            isTablet: isTablet,
            active: true,
            activeColor: Theme.of(context).primaryColor,
            inactiveColor: Theme.of(context).primaryColor,
            tooltip: 'My location',
            child: Icon(
              Icons.my_location_rounded,
              color: Colors.white,
              size: isTablet ? 32 : 28,
            ),
          ),
        ],
      ),
    );
  }

  void _showZoneDetails(BuildContext context, dynamic zone) {
    final isTablet = MediaQuery.of(context).size.width > 600;
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
                        '${zone.accidentCount} accident${zone.accidentCount == 1 ? '' : 's'} recorded',
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
            if (zone.description != null &&
                (zone.description as String).isNotEmpty) ...[
              SizedBox(height: isTablet ? 16 : 12),
              Container(
                width: double.infinity,
                padding: EdgeInsets.all(isTablet ? 16 : 12),
                decoration: BoxDecoration(
                  color: Color(zone.severityColor).withOpacity(0.07),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: Color(zone.severityColor).withOpacity(0.2),
                  ),
                ),
                child: Text(
                  zone.description,
                  style: TextStyle(
                    fontSize: isTablet ? 14 : 13,
                    color: Colors.black87,
                  ),
                ),
              ),
            ],
            SizedBox(height: isTablet ? 16 : 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () {
                  Navigator.pop(context);
                  final loc = LatLng(
                    zone.latitude as double,
                    zone.longitude as double,
                  );
                  setState(() => _selectedLocation = loc);
                  _showAiAnalysis(loc);
                },
                icon: const Icon(Icons.auto_awesome, size: 18),
                label: const Text('AI Risk Analysis'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF6C63FF),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  elevation: 0,
                ),
              ),
            ),
            SizedBox(height: isTablet ? 12 : 8),
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

// ---------------------------------------------------------------------------
// _FABButton
// ---------------------------------------------------------------------------
class _FABButton extends StatelessWidget {
  final VoidCallback? onTap;
  final bool isTablet;
  final bool active;
  final Color activeColor;
  final Color inactiveColor;
  final String tooltip;
  final Widget child;

  const _FABButton({
    required this.onTap,
    required this.isTablet,
    required this.active,
    required this.activeColor,
    required this.inactiveColor,
    required this.tooltip,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            padding: EdgeInsets.all(isTablet ? 20 : 16),
            decoration: BoxDecoration(
              gradient: active
                  ? LinearGradient(
                      colors: [activeColor, activeColor.withOpacity(0.8)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    )
                  : null,
              color: active ? null : inactiveColor,
              borderRadius: BorderRadius.circular(16),
              border: active
                  ? null
                  : Border.all(color: Colors.grey.shade300, width: 1.5),
              boxShadow: [
                BoxShadow(
                  color: activeColor.withOpacity(active ? 0.4 : 0.1),
                  blurRadius: 15,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}
