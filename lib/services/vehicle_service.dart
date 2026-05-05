import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/vehicle.dart';

class VehicleService {
  static SupabaseClient get _db => Supabase.instance.client;

  static String? get _userId => _db.auth.currentUser?.id;

  static Future<List<Vehicle>> fetchVehicles() async {
    if (_userId == null) return [];

    final data = await _db
        .from('vehicles')
        .select()
        .eq('user_id', _userId!)
        .order('created_at');

    return (data as List).map((j) => Vehicle.fromJson(j)).toList();
  }

  static Future<void> updateMileage(String vehicleId, double km) async {
    await _db
        .from('vehicles')
        .update({'current_mileage': km, 'updated_at': DateTime.now().toIso8601String()})
        .eq('id', vehicleId);
  }
}
