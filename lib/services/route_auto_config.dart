import 'package:shared_preferences/shared_preferences.dart';

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

class RouteAutoConfigService {
  static const _kEnabled = 'route_auto_enabled';
  static const _kAddress = 'route_auto_device_address';
  static const _kName = 'route_auto_device_name';
  static const _kTimeout = 'route_auto_disconnect_timeout_min';
  static const _kVehicle = 'route_auto_active_vehicle_id';

  static Future<RouteAutoConfig> load() async {
    final prefs = await SharedPreferences.getInstance();
    final timeout = prefs.getInt(_kTimeout) ?? 3;
    return RouteAutoConfig(
      enabled: prefs.getBool(_kEnabled) ?? false,
      deviceAddress: prefs.getString(_kAddress),
      deviceName: prefs.getString(_kName),
      disconnectTimeoutMin:
          RouteAutoConfig.timeoutOptions.contains(timeout) ? timeout : 3,
      activeVehicleId: prefs.getString(_kVehicle),
    );
  }

  static Future<void> save(RouteAutoConfig config) async {
    final prefs = await SharedPreferences.getInstance();
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
    if (config.activeVehicleId != null) {
      await prefs.setString(_kVehicle, config.activeVehicleId!);
    }
  }

  /// Actualiza solo el vehículo activo (se llama al cambiar de vehículo o al
  /// entrar a la pantalla de rutas), sin tocar el resto de la configuración.
  static Future<void> setActiveVehicle(String vehicleId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kVehicle, vehicleId);
  }
}
