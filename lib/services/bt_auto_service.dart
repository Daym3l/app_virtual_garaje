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
}
