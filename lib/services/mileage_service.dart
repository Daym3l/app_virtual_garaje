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
        date: DateTime.parse(j['date'] as String),
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
        .order('date', ascending: false)
        .limit(50);
    return (data as List).map((j) => MileageLog.fromJson(j)).toList();
  }

  static Future<void> addLog({
    required String vehicleId,
    required double mileage,
    String? notes,
  }) async {
    await _db.from('mileage_logs').insert({
      'vehicle_id': vehicleId,
      'mileage': mileage,
      'date': DateTime.now().toIso8601String(),
      'notes': notes,
    });
    await _db
        .from('vehicles')
        .update({'current_mileage': mileage})
        .eq('id', vehicleId);
  }
}
