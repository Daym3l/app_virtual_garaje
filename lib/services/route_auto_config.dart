import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'bt_auto_service.dart';

/// Configuración del auto-tracking de rutas por Bluetooth. Se persiste en
/// SharedPreferences para que sobreviva a reinicios y esté disponible también
/// para el servicio de segundo plano.
class RouteAutoConfig {
  const RouteAutoConfig({
    this.enabled = false,
    this.deviceAddress,
    this.deviceName,
    this.disconnectTimeoutMin = 3,
    this.activeVehicleId,
  });

  /// Auto-tracking activado por el usuario.
  final bool enabled;

  /// MAC del dispositivo Bluetooth vinculado (p. ej. el estéreo del carro).
  final String? deviceAddress;

  /// Nombre legible del dispositivo, para mostrar en la UI.
  final String? deviceName;

  /// Minutos a esperar tras una desconexión antes de finalizar la ruta.
  /// Si el dispositivo se reconecta dentro de la ventana, la ruta continúa.
  final int disconnectTimeoutMin;

  /// Vehículo al que se atribuyen las rutas automáticas. El servicio de
  /// segundo plano no tiene contexto de UI, así que se persiste aquí.
  final String? activeVehicleId;

  /// Opciones válidas para el timeout de desconexión (minutos).
  static const List<int> timeoutOptions = [1, 3, 5, 10];

  bool get isConfigured => deviceAddress != null && deviceAddress!.isNotEmpty;

  RouteAutoConfig copyWith({
    bool? enabled,
    String? deviceAddress,
    String? deviceName,
    int? disconnectTimeoutMin,
    String? activeVehicleId,
  }) => RouteAutoConfig(
        enabled: enabled ?? this.enabled,
        deviceAddress: deviceAddress ?? this.deviceAddress,
        deviceName: deviceName ?? this.deviceName,
        disconnectTimeoutMin: disconnectTimeoutMin ?? this.disconnectTimeoutMin,
        activeVehicleId: activeVehicleId ?? this.activeVehicleId,
      );
}

/// La configuración se guarda **por usuario** (`route_auto_<uid>_*`): varias
/// cuentas pueden compartir el teléfono y el dispositivo Bluetooth de uno no
/// debe aparecer configurado en la sesión de otro.
///
/// El servicio nativo no conoce sesiones: lee siempre las claves "espejo" sin
/// uid (`route_auto_enabled`, `route_auto_device_address`, …), que reflejan al
/// usuario con sesión abierta. `applyForCurrentUser` y `clearActive` mantienen
/// ese espejo al día en cada login/logout.
class RouteAutoConfigService {
  static const _kEnabled = 'route_auto_enabled';
  static const _kAddress = 'route_auto_device_address';
  static const _kName = 'route_auto_device_name';
  static const _kTimeout = 'route_auto_disconnect_timeout_min';
  static const _kVehicle = 'route_auto_active_vehicle_id';
  static const _kLegacyMigrated = 'route_auto_legacy_migrated';

  static String? get _uid => Supabase.instance.client.auth.currentUser?.id;

  static String _userKey(String base, String uid) => '${base}_$uid';

  /// Config del usuario con sesión abierta. Sin sesión devuelve la vacía.
  static Future<RouteAutoConfig> load() async {
    final uid = _uid;
    if (uid == null) return const RouteAutoConfig();
    final prefs = await SharedPreferences.getInstance();
    await _migrateLegacy(prefs, uid);

    final timeout = prefs.getInt(_userKey(_kTimeout, uid)) ?? 3;
    return RouteAutoConfig(
      enabled: prefs.getBool(_userKey(_kEnabled, uid)) ?? false,
      deviceAddress: prefs.getString(_userKey(_kAddress, uid)),
      deviceName: prefs.getString(_userKey(_kName, uid)),
      disconnectTimeoutMin:
          RouteAutoConfig.timeoutOptions.contains(timeout) ? timeout : 3,
      activeVehicleId: prefs.getString(_userKey(_kVehicle, uid)),
    );
  }

  static Future<void> save(RouteAutoConfig config) async {
    final uid = _uid;
    if (uid == null) return;
    final prefs = await SharedPreferences.getInstance();

    await prefs.setBool(_userKey(_kEnabled, uid), config.enabled);
    if (config.deviceAddress != null) {
      await prefs.setString(_userKey(_kAddress, uid), config.deviceAddress!);
    } else {
      await prefs.remove(_userKey(_kAddress, uid));
    }
    if (config.deviceName != null) {
      await prefs.setString(_userKey(_kName, uid), config.deviceName!);
    } else {
      await prefs.remove(_userKey(_kName, uid));
    }
    await prefs.setInt(_userKey(_kTimeout, uid), config.disconnectTimeoutMin);
    if (config.activeVehicleId != null) {
      await prefs.setString(_userKey(_kVehicle, uid), config.activeVehicleId!);
    }
    await _writeMirror(prefs, config);
  }

  /// Actualiza solo el vehículo activo (se llama al cambiar de vehículo o al
  /// entrar a la pantalla de rutas), sin tocar el resto de la configuración.
  static Future<void> setActiveVehicle(String vehicleId) async {
    final uid = _uid;
    if (uid == null) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_userKey(_kVehicle, uid), vehicleId);
    await prefs.setString(_kVehicle, vehicleId);
  }

  /// Vuelca la config del usuario actual al espejo que lee el servicio nativo y
  /// arranca o detiene la vigilancia según corresponda. Se llama al iniciar
  /// sesión y al abrir la app.
  static Future<RouteAutoConfig> applyForCurrentUser() async {
    final config = await load();
    final prefs = await SharedPreferences.getInstance();
    await _writeMirror(prefs, config);
    if (config.enabled && config.isConfigured) {
      await BtAutoService.startService();
    } else {
      await BtAutoService.stopService();
    }
    return config;
  }

  /// Al cerrar sesión el servicio se detiene y el espejo se vacía: la config
  /// del usuario queda guardada bajo su uid, pero no se aplica a quien entre
  /// después.
  static Future<void> clearActive() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kEnabled, false);
    await prefs.remove(_kAddress);
    await prefs.remove(_kName);
    await prefs.remove(_kVehicle);
    await BtAutoService.stopService();
  }

  static Future<void> _writeMirror(
    SharedPreferences prefs,
    RouteAutoConfig config,
  ) async {
    await prefs.setBool(_kEnabled, config.enabled);
    if (config.deviceAddress != null) {
      await prefs.setString(_kAddress, config.deviceAddress!);
    } else {
      await prefs.remove(_kAddress);
    }
    if (config.deviceName != null) {
      await prefs.setString(_kName, config.deviceName!);
    } else {
      await prefs.remove(_kName);
    }
    await prefs.setInt(_kTimeout, config.disconnectTimeoutMin);
    // Se borra si el usuario no tiene vehículo activo: dejar el del anterior
    // atribuiría sus rutas automáticas a un vehículo ajeno.
    if (config.activeVehicleId != null) {
      await prefs.setString(_kVehicle, config.activeVehicleId!);
    } else {
      await prefs.remove(_kVehicle);
    }
  }

  /// Antes de esta versión la config era global. Se adjudica al primer usuario
  /// que abra la app tras actualizar —el dueño del teléfono en la práctica— y
  /// se borran las claves sueltas para que nadie más la herede.
  static Future<void> _migrateLegacy(SharedPreferences prefs, String uid) async {
    if (prefs.getBool(_kLegacyMigrated) ?? false) return;
    await prefs.setBool(_kLegacyMigrated, true);

    final address = prefs.getString(_kAddress);
    if (address == null || address.isEmpty) return;
    if (prefs.getString(_userKey(_kAddress, uid)) != null) return;

    await prefs.setBool(_userKey(_kEnabled, uid), prefs.getBool(_kEnabled) ?? false);
    await prefs.setString(_userKey(_kAddress, uid), address);
    final name = prefs.getString(_kName);
    if (name != null) await prefs.setString(_userKey(_kName, uid), name);
    await prefs.setInt(_userKey(_kTimeout, uid), prefs.getInt(_kTimeout) ?? 3);
    final vehicle = prefs.getString(_kVehicle);
    if (vehicle != null) await prefs.setString(_userKey(_kVehicle, uid), vehicle);
  }
}
