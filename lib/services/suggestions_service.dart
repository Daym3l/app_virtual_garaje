import 'package:supabase_flutter/supabase_flutter.dart';

/// Sugerencias de autocompletado vía la RPC `get_field_suggestions`
/// (compartida con la web): valores que el usuario ya escribió en un campo.
/// kind: 'station' (fuel_logs), 'provider' (maintenances.performed_by),
/// 'location' (energy_logs).
class SuggestionsService {
  static SupabaseClient get _db => Supabase.instance.client;

  // Caché por sesión: las sugerencias apenas cambian con un formulario abierto.
  static final Map<String, List<String>> _cache = {};

  static Future<List<String>> get(String kind) async {
    final cached = _cache[kind];
    if (cached != null) return cached;
    try {
      final data = await _db
          .rpc('get_field_suggestions', params: {'p_kind': kind})
          .timeout(const Duration(seconds: 8));
      final values = (data as List)
          .map((row) => (row as Map)['value'] as String?)
          .whereType<String>()
          .toList();
      _cache[kind] = values;
      return values;
    } catch (_) {
      return const [];
    }
  }

  /// Descarta la caché de un kind para que el próximo fetch refleje valores
  /// recién guardados.
  static void invalidate(String kind) => _cache.remove(kind);
}
