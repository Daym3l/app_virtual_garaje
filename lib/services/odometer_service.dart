import 'package:supabase_flutter/supabase_flutter.dart';

class OdometerBounds {
  const OdometerBounds({this.lowerBound, this.lowerDate, this.upperBound, this.upperDate});
  final double? lowerBound;
  final DateTime? lowerDate;
  final double? upperBound;
  final DateTime? upperDate;
}

/// Validación de odómetro contra el historial del vehículo, vía la RPC
/// `get_odometer_bounds` (compartida con la web). Una lectura del día D debe
/// cumplir: max(odómetro en días < D) <= valor <= min(odómetro en días > D).
class OdometerService {
  static SupabaseClient get _db => Supabase.instance.client;

  static Future<OdometerBounds> getBounds(
    String vehicleId,
    DateTime date, {
    String? excludeSource,
    String? excludeId,
  }) async {
    final data = await _db.rpc('get_odometer_bounds', params: {
      'p_vehicle_id': vehicleId,
      'p_date': date.toIso8601String(),
      'p_exclude_source': excludeSource,
      'p_exclude_id': excludeId,
    }).timeout(const Duration(seconds: 10));
    final row = data is List ? (data.isNotEmpty ? data.first : null) : data;
    if (row is! Map) return const OdometerBounds();
    return OdometerBounds(
      lowerBound: (row['lower_bound'] as num?)?.toDouble(),
      lowerDate: DateTime.tryParse(row['lower_date']?.toString() ?? ''),
      upperBound: (row['upper_bound'] as num?)?.toDouble(),
      upperDate: DateTime.tryParse(row['upper_date']?.toString() ?? ''),
    );
  }

  /// Devuelve un mensaje de error si el valor está fuera de rango, o null si
  /// es válido. Si la RPC falla (p. ej. sin red) devuelve null: la validación
  /// es una ayuda, no debe bloquear el guardado offline.
  static Future<String?> validate({
    required String vehicleId,
    required DateTime date,
    required double valueKm,
    String? excludeSource,
    String? excludeId,
  }) async {
    if (!valueKm.isFinite) return null;
    final OdometerBounds bounds;
    try {
      // Mediodía para estabilidad del día calendario ante zonas horarias.
      final noon = DateTime(date.year, date.month, date.day, 12);
      bounds = await getBounds(vehicleId, noon,
          excludeSource: excludeSource, excludeId: excludeId);
    } catch (_) {
      return null;
    }
    if (bounds.lowerBound != null && valueKm < bounds.lowerBound!) {
      final when = bounds.lowerDate != null ? ' (registro del ${_fmtDate(bounds.lowerDate!)})' : '';
      return 'El odómetro debe ser mayor o igual a ${_fmtKm(bounds.lowerBound!)} km$when';
    }
    if (bounds.upperBound != null && valueKm > bounds.upperBound!) {
      final when = bounds.upperDate != null ? ' (registro del ${_fmtDate(bounds.upperDate!)})' : '';
      return 'El odómetro debe ser menor o igual a ${_fmtKm(bounds.upperBound!)} km$when';
    }
    return null;
  }

  static String _fmtDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  static String _fmtKm(double v) {
    final isInt = v == v.roundToDouble();
    final intPart = v.truncate().toString().replaceAllMapped(
        RegExp(r'(\d)(?=(\d{3})+$)'), (m) => '${m[1]}.');
    if (isInt) return intPart;
    final dec = (v - v.truncate()).toStringAsFixed(1).substring(2);
    return '$intPart,$dec';
  }
}
