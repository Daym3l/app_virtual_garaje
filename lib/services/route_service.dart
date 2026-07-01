import 'dart:convert';
import 'dart:math';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'pending_routes_store.dart';

class RoutePoint {
  const RoutePoint({
    required this.latitude,
    required this.longitude,
    required this.timestamp,
    required this.speed,
    required this.altitude,
  });

  final double latitude;
  final double longitude;
  final DateTime timestamp;
  final double speed;
  final double altitude;

  factory RoutePoint.fromPosition(Position pos) => RoutePoint(
    latitude: pos.latitude,
    longitude: pos.longitude,
    timestamp: pos.timestamp,
    speed: (pos.speed * 3.6).clamp(0, 300), // m/s → km/h
    altitude: pos.altitude,
  );

  factory RoutePoint.fromJson(Map<String, dynamic> j) => RoutePoint(
    latitude: (j['latitude'] as num?)?.toDouble() ?? 0,
    longitude: (j['longitude'] as num?)?.toDouble() ?? 0,
    timestamp: DateTime.tryParse(j['timestamp']?.toString() ?? '') ?? DateTime.now(),
    speed: (j['speed'] as num?)?.toDouble() ?? 0,
    altitude: (j['altitude'] as num?)?.toDouble() ?? 0,
  );

  LatLng get latLng => LatLng(latitude, longitude);

  Map<String, dynamic> toJson() => {
    'latitude': latitude,
    'longitude': longitude,
    'timestamp': timestamp.toUtc().toIso8601String(),
    'speed': speed,
    'altitude': altitude,
  };
}

class RouteRecord {
  const RouteRecord({
    required this.id,
    required this.vehicleId,
    required this.startTime,
    required this.endTime,
    required this.points,
    required this.totalDistance,
    required this.averageSpeed,
    this.notes,
  });

  final String id;
  final String vehicleId;
  final DateTime startTime;
  final DateTime endTime;
  final List<LatLng> points;
  final double totalDistance; // km
  final double averageSpeed;  // km/h
  final String? notes;

  Duration get duration => endTime.difference(startTime);

  factory RouteRecord.fromJson(Map<String, dynamic> j) {
    // points puede ser List o String (jsonb devuelto como texto)
    dynamic rawPoints = j['points'];
    if (rawPoints is String) {
      try { rawPoints = jsonDecode(rawPoints); } catch (_) { rawPoints = []; }
    }
    List<LatLng> pts = [];
    if (rawPoints is List) {
      for (final p in rawPoints) {
        try {
          if (p is Map) {
            final lat = p['latitude'] ?? p['lat'];
            final lng = p['longitude'] ?? p['lng'];
            if (lat != null && lng != null) {
              pts.add(LatLng(_toDouble(lat), _toDouble(lng)));
            }
          }
        } catch (_) {}
      }
    }
    return RouteRecord(
      id: j['id'] as String,
      vehicleId: j['vehicle_id'] as String,
      startTime: DateTime.parse(j['start_time'] as String),
      endTime: DateTime.parse(j['end_time'] as String),
      points: pts,
      totalDistance: _toDouble(j['total_distance']),
      averageSpeed: _toDouble(j['average_speed']),
      notes: (j['notes'] as String?)?.isEmpty == true ? null : j['notes'] as String?,
    );
  }

  static double _toDouble(dynamic v) {
    if (v == null) return 0.0;
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v) ?? 0.0;
    return 0.0;
  }
}

class RouteService {
  static SupabaseClient get _db => Supabase.instance.client;

  static Future<bool> requestPermission() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return false;

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) return false;
    }
    if (permission == LocationPermission.deniedForever) return false;
    return true;
  }

  static Stream<Position> trackingStream() => Geolocator.getPositionStream(
    locationSettings: AndroidSettings(
      accuracy: LocationAccuracy.bestForNavigation,
      distanceFilter: 5,
      intervalDuration: Duration(seconds: 2),
      foregroundNotificationConfig: ForegroundNotificationConfig(
        notificationText: 'Registrando ruta en curso',
        notificationTitle: 'Mi Garaje Virtual',
        enableWakeLock: true,
      ),
    ),
  );

  static double calcDistance(List<RoutePoint> points) {
    if (points.length < 2) return 0;
    double total = 0;
    for (int i = 1; i < points.length; i++) {
      total += _haversine(points[i - 1].latLng, points[i].latLng);
    }
    return total;
  }

  static double _haversine(LatLng a, LatLng b) {
    const r = 6371.0;
    final dLat = _deg2rad(b.latitude - a.latitude);
    final dLon = _deg2rad(b.longitude - a.longitude);
    final x = sin(dLat / 2) * sin(dLat / 2) +
        cos(_deg2rad(a.latitude)) * cos(_deg2rad(b.latitude)) *
        sin(dLon / 2) * sin(dLon / 2);
    final c = 2 * atan2(sqrt(x), sqrt(1 - x));
    return r * c;
  }

  static double _deg2rad(double d) => d * pi / 180;

  static Future<List<RouteRecord>> fetchRoutes(String vehicleId) async {
    final data = await _db
        .from('routes')
        .select('id, vehicle_id, start_time, end_time, total_distance, average_speed, notes, points')
        .eq('vehicle_id', vehicleId)
        .order('start_time', ascending: false)
        .limit(20)
        .timeout(const Duration(seconds: 10));
    return (data as List).map((j) => RouteRecord.fromJson(j)).toList();
  }

  static Future<void> saveRoute({
    required String vehicleId,
    required DateTime startTime,
    required DateTime endTime,
    required List<RoutePoint> points,
    required double totalDistance,
    required double averageSpeed,
    required double currentMileage,
    required int routeNumber,
    String? notes,
    String? routeId,
  }) async {
    // id de cliente → upsert idempotente: reintentar no duplica la ruta.
    final id = routeId ?? PendingRoutesStore.newId();
    final newMileage = currentMileage + totalDistance;
    await Future.wait([
      _db.from('routes').upsert({
        'id': id,
        'vehicle_id': vehicleId,
        'start_time': startTime.toUtc().toIso8601String(),
        'end_time': endTime.toUtc().toIso8601String(),
        'points': points.map((p) => p.toJson()).toList(),
        'total_distance': totalDistance,
        'average_speed': averageSpeed,
        'notes': notes ?? '',
      }, onConflict: 'id'),
      _db.from('mileage_logs').insert({
        'vehicle_id': vehicleId,
        'mileage': newMileage,
        'date': endTime.toUtc().toIso8601String(),
        'notes': 'Ruta #$routeNumber — ${totalDistance.toStringAsFixed(2)} km recorridos',
      }),
      _db.from('vehicles').update({'current_mileage': newMileage}).eq('id', vehicleId),
    ]).timeout(const Duration(seconds: 15));
  }

  /// Intenta guardar la ruta online; si falla (p. ej. sin red) la guarda en el
  /// respaldo local para reintentar luego. Devuelve `true` si se guardó online,
  /// `false` si quedó encolada.
  static Future<bool> saveOrQueue({
    required String vehicleId,
    required DateTime startTime,
    required DateTime endTime,
    required List<RoutePoint> points,
    required double totalDistance,
    required double averageSpeed,
    required double currentMileage,
    required int routeNumber,
    String? notes,
  }) async {
    final id = PendingRoutesStore.newId();
    try {
      await saveRoute(
        vehicleId: vehicleId,
        startTime: startTime,
        endTime: endTime,
        points: points,
        totalDistance: totalDistance,
        averageSpeed: averageSpeed,
        currentMileage: currentMileage,
        routeNumber: routeNumber,
        notes: notes,
        routeId: id,
      );
      return true;
    } catch (_) {
      await PendingRoutesStore.add(PendingRoute(
        id: id,
        vehicleId: vehicleId,
        startTime: startTime,
        endTime: endTime,
        points: points,
        totalDistance: totalDistance,
        averageSpeed: averageSpeed,
        currentMileage: currentMileage,
        routeNumber: routeNumber,
        notes: notes,
      ));
      return false;
    }
  }

  /// Reintenta subir las rutas del respaldo local. Devuelve cuántas se
  /// sincronizaron. Se detiene al primer fallo (probablemente sigue sin red).
  static Future<int> syncPending() async {
    final pending = await PendingRoutesStore.getAll();
    if (pending.isEmpty) return 0;
    int synced = 0;
    for (final p in pending) {
      try {
        // Recalcula el kilometraje desde el estado actual del vehículo para no
        // introducir regresiones si cambió mientras la ruta estuvo en cola.
        final veh = await _db
            .from('vehicles')
            .select('current_mileage')
            .eq('id', p.vehicleId)
            .maybeSingle()
            .timeout(const Duration(seconds: 10));
        final curMileage =
            (veh?['current_mileage'] as num?)?.toDouble() ?? p.currentMileage;
        await saveRoute(
          vehicleId: p.vehicleId,
          startTime: p.startTime,
          endTime: p.endTime,
          points: p.points,
          totalDistance: p.totalDistance,
          averageSpeed: p.averageSpeed,
          currentMileage: curMileage,
          routeNumber: p.routeNumber,
          notes: p.notes,
          routeId: p.id,
        );
        await PendingRoutesStore.remove(p.id);
        synced++;
      } catch (_) {
        break;
      }
    }
    return synced;
  }
}
