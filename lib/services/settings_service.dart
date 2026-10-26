import 'package:supabase_flutter/supabase_flutter.dart';
import '../utils/units.dart';

class SettingsService {
  static SupabaseClient get _db => Supabase.instance.client;

  static Future<FuelUnit> fetchFuelUnit() async {
    final userId = _db.auth.currentUser?.id;
    if (userId == null) return FuelUnit.liters;

    final data = await _db
        .from('user_settings')
        .select('fuel_unit')
        .eq('user_id', userId)
        .maybeSingle();
    return FuelUnit.fromDb(data?['fuel_unit'] as String?);
  }
}
