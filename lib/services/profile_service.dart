import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/user_profile.dart';

class ProfileService {
  static SupabaseClient get _db => Supabase.instance.client;

  static Future<UserProfile?> fetchProfile() async {
    final userId = _db.auth.currentUser?.id;
    if (userId == null) return null;

    final data = await _db
        .from('user_profiles')
        .select('id, membership, membership_status, membership_expires_at, role')
        .eq('id', userId)
        .maybeSingle();

    if (data == null) return null;
    return UserProfile.fromJson(data);
  }
}
