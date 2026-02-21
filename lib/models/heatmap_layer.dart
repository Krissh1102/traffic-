import 'dart:async';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

class HeatmapLayer extends StatefulWidget {
  final List<dynamic> zones;
  const HeatmapLayer({super.key, required this.zones});

  @override
  State<HeatmapLayer> createState() => _HeatmapLayerState();
}

class _HeatmapLayerState extends State<HeatmapLayer> {
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

      final metersPerPx =
          _metersPerPixel(camera.zoom, zone.latitude as double);
      final radiusPx =
          ((zone.radiusMeters as double) / metersPerPx / scale).clamp(20.0, 280.0);

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
    return earthCircumference *
        cos(latitude * pi / 180) /
        pow(2, zoom + 8);
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

// ---------------------------------------------------------------------------
// Internal painter – stretches the low-res buffer to screen size
// ---------------------------------------------------------------------------
class _HeatmapImagePainter extends CustomPainter {
  final ui.Image image;
  const _HeatmapImagePainter({required this.image});

  @override
  void paint(Canvas canvas, Size size) {
    final src = Rect.fromLTWH(
        0, 0, image.width.toDouble(), image.height.toDouble());
    final dst = Rect.fromLTWH(0, 0, size.width, size.height);
    final paint = Paint()
      ..filterQuality = FilterQuality.medium
      ..isAntiAlias = true;
    canvas.drawImageRect(image, src, dst, paint);
  }

  @override
  bool shouldRepaint(_HeatmapImagePainter old) => old.image != image;
}