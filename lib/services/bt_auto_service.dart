import 'dart:convert';
import 'package:flutter/services.dart';

/// Un dispositivo Bluetooth emparejado en el teléfono.
class BtDevice {
  const BtDevice({required this.name, required this.address});
  final String name;
  final String address;

  factory BtDevice.fromMap(Map map) => BtDevice(
        name: (map['name'] as String?)?.trim().isNotEmpty == true
            ? map['name'] as String
            : 'Dispositivo sin nombre',
        address: map['address'] as String,
      );
}

/// Un evento del registro del servicio de auto-ruta.
class BtEvent {
  const BtEvent({required this.time, required this.message});
  final DateTime time;
  final String message;
}

/// Estado del servicio nativo y de los permisos que necesita.
class BtDiagnostics {
  const BtDiagnostics({
    required this.serviceRunning,
    required this.state,
    required this.points,
    required this.distanceKm,
    required this.disconnectedAt,
    required this.startedAt,
    required this.capturedPending,
    required this.hasProgress,
    required this.deviceConnected,
    required this.permLocation,
    required this.permLocationBackground,
    required this.permBluetooth,
    required this.permNotifications,
    required this.gpsEnabled,
    required this.exactAlarms,
    required this.batteryUnrestricted,
    required this.events,
  });

  final bool serviceRunning;
  final String state;
  final int points;
  final double distanceKm;
  final DateTime? disconnectedAt;
  final DateTime? startedAt;
  final int capturedPending;
  final bool hasProgress;
  final bool deviceConnected;
  final bool permLocation;
  final bool permLocationBackground;
  final bool permBluetooth;
  final bool permNotifications;
  final bool gpsEnabled;
  final bool exactAlarms;
  final bool batteryUnrestricted;
  final List<BtEvent> events;

  bool get routeActive => serviceRunning && (state == 'en ruta' || state == 'en espera');
  bool get waitingReconnect => state == 'en espera';

  factory BtDiagnostics.fromMap(Map map) {
    final rawEvents = map['events'] as String? ?? '[]';
    final events = <BtEvent>[];
    try {
      for (final e in (jsonDecode(rawEvents) as List)) {
        if (e is! Map) continue;
        events.add(BtEvent(
          time: DateTime.fromMillisecondsSinceEpoch((e['t'] as num?)?.toInt() ?? 0),
          message: e['m']?.toString() ?? '',
        ));
      }
    } catch (_) {}
    final disconnected = (map['disconnected_at'] as num?)?.toInt() ?? 0;
    final started = (map['started_at'] as num?)?.toInt() ?? 0;
    return BtDiagnostics(
      serviceRunning: map['service_running'] == true,
      state: map['state']?.toString() ?? 'desconocido',
      points: (map['points'] as num?)?.toInt() ?? 0,
      distanceKm: (map['distance_km'] as num?)?.toDouble() ?? 0,
      disconnectedAt: disconnected > 0
          ? DateTime.fromMillisecondsSinceEpoch(disconnected)
          : null,
      startedAt: started > 0 ? DateTime.fromMillisecondsSinceEpoch(started) : null,
      capturedPending: (map['captured_pending'] as num?)?.toInt() ?? 0,
      hasProgress: map['has_progress'] == true,
      deviceConnected: map['device_connected'] == true,
      permLocation: map['perm_location'] == true,
      permLocationBackground: map['perm_location_background'] == true,
      permBluetooth: map['perm_bluetooth'] == true,
      permNotifications: map['perm_notifications'] == true,
      gpsEnabled: map['gps_enabled'] == true,
      exactAlarms: map['exact_alarms'] == true,
      batteryUnrestricted: map['battery_unrestricted'] == true,
      events: events.reversed.toList(),
    );
  }
}

/// Puente hacia el código nativo Android para el auto-tracking por Bluetooth
/// clásico: listar dispositivos emparejados y arrancar/detener el servicio de
/// segundo plano que vigila la conexión.
class BtAutoService {
  static const _channel = MethodChannel('virtualgaraje/bt_auto');

  /// Solicita el permiso BLUETOOTH_CONNECT (Android 12+) y devuelve si quedó
  /// concedido. En versiones anteriores no hace falta y devuelve true.
  static Future<bool> ensureBluetoothPermission() async {
    try {
      return await _channel.invokeMethod<bool>('ensurePermission') ?? false;
    } on PlatformException {
      return false;
    }
  }

  /// Solicita POST_NOTIFICATIONS (Android 13+). Sin él la notificación de la
  /// auto-ruta no se muestra y no hay forma de ver que está registrando.
  static Future<bool> ensureNotificationPermission() async {
    try {
      return await _channel.invokeMethod<bool>('ensureNotificationPermission') ?? false;
    } on PlatformException {
      return false;
    }
  }

  /// Lista los dispositivos Bluetooth ya emparejados con el teléfono.
  static Future<List<BtDevice>> bondedDevices() async {
    try {
      final result = await _channel.invokeMethod<List<dynamic>>('getBondedDevices');
      if (result == null) return const [];
      return result
          .whereType<Map>()
          .map(BtDevice.fromMap)
          .toList();
    } on PlatformException {
      return const [];
    }
  }

  /// ¿Está actualmente conectado el dispositivo indicado? (best-effort)
  static Future<bool> isConnected(String address) async {
    try {
      return await _channel
              .invokeMethod<bool>('isConnected', {'address': address}) ??
          false;
    } on PlatformException {
      return false;
    }
  }

  /// Arranca el servicio de segundo plano que vigila la conexión del
  /// dispositivo configurado. Idempotente.
  static Future<void> startService() async {
    try {
      await _channel.invokeMethod('startService');
    } on PlatformException {
      // El servicio se implementa en la Fase 2; ignorar si aún no existe.
    }
  }

  /// Detiene el servicio de vigilancia.
  static Future<void> stopService() async {
    try {
      await _channel.invokeMethod('stopService');
    } on PlatformException {
      // Ídem.
    }
  }

  /// Estado del servicio, permisos del sistema e historial de eventos. La
  /// auto-ruta se prueba conduciendo, así que el diagnóstico va en la app.
  static Future<BtDiagnostics?> diagnostics() async {
    try {
      final map = await _channel.invokeMethod<Map<dynamic, dynamic>>('diagnostics');
      if (map == null) return null;
      return BtDiagnostics.fromMap(map);
    } on PlatformException {
      return null;
    }
  }

  /// Pestaña que pidió abrir la notificación de la auto-ruta (o null).
  static Future<String?> consumePendingTab() async {
    try {
      return await _channel.invokeMethod<String>('consumePendingTab');
    } on PlatformException {
      return null;
    }
  }

  /// Pide la ubicación "todo el tiempo" (en Android 11+ abre los ajustes de la
  /// app). Sin ella el servicio no puede reanudarse tras reiniciar el teléfono.
  static Future<bool> requestBackgroundLocation() async {
    try {
      return await _channel.invokeMethod<bool>('requestBackgroundLocation') ?? false;
    } on PlatformException {
      return false;
    }
  }

  /// Abre el diálogo del sistema para quitar la restricción de batería.
  /// Devuelve true si ya estaba exenta.
  static Future<bool> requestBatteryExemption() async {
    try {
      return await _channel.invokeMethod<bool>('requestBatteryExemption') ?? false;
    } on PlatformException {
      return false;
    }
  }

  static Future<void> clearEventLog() async {
    try {
      await _channel.invokeMethod('clearEventLog');
    } on PlatformException {
      // Sin efecto.
    }
  }

  /// Pide al servicio nativo que cierre una ruta cuyo timeout de desconexión
  /// ya venció. Red de seguridad por si la alarma se retrasó en Doze.
  static Future<void> checkPendingRoute() async {
    try {
      await _channel.invokeMethod('checkPendingRoute');
    } on PlatformException {
      // Servicio detenido o auto-ruta desactivada: sin efecto.
    }
  }

  /// Extrae (y limpia) las rutas que el servicio nativo capturó en segundo
  /// plano mientras la app estaba cerrada. Cada entrada es un mapa con
  /// vehicle_id, start_time, end_time, points, total_distance, average_speed.
  static Future<List<Map<String, dynamic>>> drainCapturedRoutes() async {
    try {
      final raw = await _channel.invokeMethod<String>('drainCapturedRoutes');
      if (raw == null || raw.isEmpty) return const [];
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return decoded
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    } catch (_) {
      return const [];
    }
  }
}

