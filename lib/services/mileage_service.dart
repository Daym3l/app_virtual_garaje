import 'package:supabase_flutter/supabase_flutter.dart';

class MileageLog {
  const MileageLog({
    required this.id,
    required this.vehicleId,
    required this.mileage,
    required this.date,
    this.notes,
  });

  final String id;
  final String vehicleId;
  final double mileage;
  final DateTime date;
  final String? notes;

  factory MileageLog.fromJson(Map<String, dynamic> j) => MileageLog(
        id: j['id'] as String,
        vehicleId: j['vehicle_id'] as String,
        mileage: (j['mileage'] as num).toDouble(),
        // Los registros manuales se guardan a mediodía UTC (día de calendario),
        // pero los que crea una ruta llevan la hora real de fin: sin toLocal()
        // esos salían con la fecha corrida.
        date: DateTime.parse(j['date'] as String).toLocal(),
        notes: j['notes'] as String?,
      );
}

class MileageService {
  static SupabaseClient get _db => Supabase.instance.client;

  static Future<List<MileageLog>> fetchLogs(String vehicleId) async {
    final data = await _db
        .from('mileage_logs')
        .select()
        .eq('vehicle_id', vehicleId)
        // Todos los registros se guardan a mediodía UTC (día de calendario), así
        // que dentro de un mismo día ordena el propio odómetro: solo avanza, y
        // es lo único fiable aquí (created_at va vacío en las filas que inserta
        // la app). Deja las diferencias entre registros siempre positivas.
        .order('date', ascending: false)
        .order('mileage', ascending: false)
        .limit(50);
    return (data as List).map((j) => MileageLog.fromJson(j)).toList();
  }

  static Future<void> addLog({
    required String vehicleId,
    required double mileage,
    String? notes,
    DateTime? date,
  }) async {
    // El odómetro se guarda como entero (km recorridos no llevan decimales).
    final km = mileage.roundToDouble();
    // La fecha es solo día de calendario: se fija a mediodía UTC para que
    // se conserve la misma fecha en cualquier zona horaria (evita que un
    // registro se corra al día anterior/siguiente al interpretarse en UTC).
    final d = date ?? DateTime.now();
    final normalizedDate = DateTime.utc(d.year, d.month, d.day, 12);
    await _db.from('mileage_logs').insert({
      'vehicle_id': vehicleId,
      'mileage': km,
      'date': normalizedDate.toIso8601String(),
      'notes': notes,
    });
    await _db
        .from('vehicles')
        .update({'current_mileage': km})
        .eq('id', vehicleId);
  }
}
