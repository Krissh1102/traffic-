import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

// ---------------------------------------------------------------------------
// ZoneNotificationService
//
// Watches the user's live position and fires local push notifications when
// they enter or leave a "red" (high-severity) accident zone.
//
// Setup (pubspec.yaml):
//   flutter_local_notifications: ^17.0.0
//
// Android – add to AndroidManifest.xml inside <manifest>:
//   <uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>
//
// iOS – add to ios/Runner/Info.plist:
//   <key>NSLocationWhenInUseUsageDescription</key>
//   <string>Used to warn you about nearby accident zones.</string>
// ---------------------------------------------------------------------------
class ZoneNotificationService {
  ZoneNotificationService._();
  static final ZoneNotificationService instance = ZoneNotificationService._();

  // ── Public state ──────────────────────────────────────────────────────────
  /// Stream of zone-entry/exit events for the UI to react to.
  final _eventStreamController =
      StreamController<ZoneProximityEvent>.broadcast();
  Stream<ZoneProximityEvent> get eventStream => _eventStreamController.stream;

  // ── Internals ─────────────────────────────────────────────────────────────
  final FlutterLocalNotificationsPlugin _notificationsPlugin =
      FlutterLocalNotificationsPlugin();

  StreamSubscription<Position>? _positionSubscription;
  List<dynamic> _zones = [];

  /// IDs of zones the user is *currently inside*.
  final Set<String> _activeZoneIds = {};

  bool _initialized = false;
  int _notificationId = 0;

  // ── Minimum severity level to trigger a notification (1-5). ──────────────
  static const int _minSeverity = 3;

  // ── Init ──────────────────────────────────────────────────────────────────
  Future<void> initialize() async {
    if (_initialized) return;

    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    await _notificationsPlugin.initialize(
      settings: const InitializationSettings(
          android: androidSettings, iOS: iosSettings),
    );

    // Request Android 13+ notification permission
    await _notificationsPlugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();

    _initialized = true;
  }

  // ── Start / Stop tracking ─────────────────────────────────────────────────
  void startTracking(List<dynamic> zones) {
    _zones = zones;
    _positionSubscription?.cancel();

    _positionSubscription = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 10, // fire every 10 m of movement
      ),
    ).listen(_onPositionUpdate);
  }

  void updateZones(List<dynamic> zones) {
    _zones = zones;
  }

  void stopTracking() {
    _positionSubscription?.cancel();
    _positionSubscription = null;
    _activeZoneIds.clear();
  }

  // ── Core logic ────────────────────────────────────────────────────────────
  void _onPositionUpdate(Position position) {
    final userLatLng = LatLng(position.latitude, position.longitude);

    for (final zone in _zones) {
      if ((zone.severityLevel as int) < _minSeverity) continue;

      final zoneId = '${zone.latitude}_${zone.longitude}';
      final distanceMeters = _haversineDistanceMeters(
        userLatLng,
        LatLng(zone.latitude as double, zone.longitude as double),
      );

      final isInside = distanceMeters <= (zone.radiusMeters as double);
      final wasInside = _activeZoneIds.contains(zoneId);

      if (isInside && !wasInside) {
        // ── Entered zone ──────────────────────────────────────────────
        _activeZoneIds.add(zoneId);
        _fireNotification(
          title: '⚠️ Entering High-Risk Zone',
          body:
              '${zone.title} – ${zone.accidentCount} accident${zone.accidentCount == 1 ? '' : 's'} recorded here. Drive carefully!',
          isEntry: true,
        );
        _eventStreamController.add(ZoneProximityEvent(
          zone: zone,
          isEntry: true,
        ));
      } else if (!isInside && wasInside) {
        // ── Left zone ─────────────────────────────────────────────────
        _activeZoneIds.remove(zoneId);
        _fireNotification(
          title: '✅ Left High-Risk Zone',
          body: 'You\'ve exited ${zone.title}. Stay safe!',
          isEntry: false,
        );
        _eventStreamController.add(ZoneProximityEvent(
          zone: zone,
          isEntry: false,
        ));
      }
    }
  }

  
  Future<void> _fireNotification({
    required String title,
    required String body,
    required bool isEntry,
  }) async {
    if (!_initialized) await initialize();

 
    const int redColor = 0xFFFF0000;
    const int greenColor = 0xFF4CAF50;

    final androidDetails = AndroidNotificationDetails(
      isEntry ? 'zone_entry' : 'zone_exit',
      isEntry ? 'Zone Entry Alerts' : 'Zone Exit Alerts',
      channelDescription: isEntry
          ? 'Notifies when you enter a high-risk accident zone'
          : 'Notifies when you leave a high-risk accident zone',
      importance: isEntry ? Importance.high : Importance.defaultImportance,
      priority: isEntry ? Priority.high : Priority.defaultPriority,
      color: Color(isEntry ? 0xFFFF0000 : 0xFF4CAF50),
      icon: '@mipmap/ic_launcher',
      playSound: true,
      enableVibration: isEntry,
    );

    final iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
      interruptionLevel:
          isEntry ? InterruptionLevel.timeSensitive : InterruptionLevel.active,
    );

    await _notificationsPlugin.show(
      id: _notificationId++,
      title: title,
      body: body,
      // details: NotificationDetails(android: androidDetails, iOS: iosDetails),
    );
  }

  // ── Haversine distance (metres) ───────────────────────────────────────────
  static double _haversineDistanceMeters(LatLng a, LatLng b) {
    const r = 6371000.0; // Earth radius in metres
    final lat1 = a.latitude * pi / 180;
    final lat2 = b.latitude * pi / 180;
    final dLat = (b.latitude - a.latitude) * pi / 180;
    final dLon = (b.longitude - a.longitude) * pi / 180;
    final sinLat = sin(dLat / 2);
    final sinLon = sin(dLon / 2);
    final h =
        sinLat * sinLat + cos(lat1) * cos(lat2) * sinLon * sinLon;
    return 2 * r * asin(sqrt(h));
  }

  void dispose() {
    stopTracking();
    _eventStreamController.close();
  }
}

// ---------------------------------------------------------------------------
// ZoneProximityEvent  – emitted on entry / exit
// ---------------------------------------------------------------------------
class ZoneProximityEvent {
  final dynamic zone;
  final bool isEntry;

  const ZoneProximityEvent({required this.zone, required this.isEntry});
}