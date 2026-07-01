import 'dart:convert';
import 'dart:math';
import 'package:shared_preferences/shared_preferences.dart';
import 'route_service.dart';

/// Ruta pendiente de sincronizar: se guarda localmente cuando el envío a
/// Supabase falla (p. ej. sin red) para no perder los datos y reintentar
/// cuando vuelva la conexión.
class PendingRoute {
  const PendingRoute({
    required this.id,
    required this.vehicleId,
    required this.startTime,
    required this.endTime,
    required this.points,
    required this.totalDistance,
    required this.averageSpeed,
    required this.currentMileage,
    required this.routeNumber,
    this.notes,
  });

  final String id;
  final String vehicleId;
  final DateTime startTime;
  final DateTime endTime;
  final List<RoutePoint> points;
  final double totalDistance;
  final double averageSpeed;
  final double currentMileage;
  final int routeNumber;
  final String? notes;

  Map<String, dynamic> toJson() => {
    'id': id,
    'vehicle_id': vehicleId,
    'start_time': startTime.toUtc().toIso8601String(),
    'end_time': endTime.toUtc().toIso8601String(),
    'points': points.map((p) => p.toJson()).toList(),
    'total_distance': totalDistance,
    'average_speed': averageSpeed,
    'current_mileage': currentMileage,
    'route_number': routeNumber,
    'notes': notes,
  };

  factory PendingRoute.fromJson(Map<String, dynamic> j) => PendingRoute(
    id: j['id'] as String,
    vehicleId: j['vehicle_id'] as String,
    startTime: DateTime.parse(j['start_time'] as String),
    endTime: DateTime.parse(j['end_time'] as String),
    points: ((j['points'] as List?) ?? [])
        .map((p) => RoutePoint.fromJson(Map<String, dynamic>.from(p as Map)))
        .toList(),
    totalDistance: (j['total_distance'] as num?)?.toDouble() ?? 0,
    averageSpeed: (j['average_speed'] as num?)?.toDouble() ?? 0,
    currentMileage: (j['current_mileage'] as num?)?.toDouble() ?? 0,
    routeNumber: (j['route_number'] as num?)?.toInt() ?? 0,
    notes: j['notes'] as String?,
  );
}

class PendingRoutesStore {
  static const _key = 'pending_routes_v1';

  static String newId() {
    final rnd = Random.secure();
    final bytes = List<int>.generate(16, (_) => rnd.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40; // versión 4
    bytes[8] = (bytes[8] & 0x3f) | 0x80; // variante
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  }

  static Future<List<PendingRoute>> getAll() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_key) ?? const [];
    final out = <PendingRoute>[];
    for (final s in raw) {
      try {
        out.add(PendingRoute.fromJson(jsonDecode(s) as Map<String, dynamic>));
      } catch (_) {}
    }
    return out;
  }

  static Future<void> add(PendingRoute route) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_key) ?? <String>[];
    raw.add(jsonEncode(route.toJson()));
    await prefs.setStringList(_key, raw);
  }

  static Future<void> remove(String id) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_key) ?? <String>[];
    raw.removeWhere((s) {
      try {
        return (jsonDecode(s) as Map<String, dynamic>)['id'] == id;
      } catch (_) {
        return false;
      }
    });
    await prefs.setStringList(_key, raw);
  }

  static Future<int> count() async => (await getAll()).length;

  static Future<int> countForVehicle(String vehicleId) async =>
      (await getAll()).where((r) => r.vehicleId == vehicleId).length;
}
