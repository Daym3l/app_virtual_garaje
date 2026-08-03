import 'bt_auto_service.dart';
import 'pending_routes_store.dart';
import 'route_service.dart';

/// Trae al sistema de rutas las que el servicio nativo capturó en segundo
/// plano (auto-tracking por Bluetooth) y las sube a Supabase reutilizando la
/// cola de pendientes existente.
class CapturedRoutesImporter {
  /// Drena la cola nativa, encola cada ruta como pendiente y dispara la
  /// sincronización. Devuelve cuántas rutas se importaron.
  static Future<int> importAndSync() async {
    final captured = await BtAutoService.drainCapturedRoutes();
    int imported = 0;

    for (final m in captured) {
      try {
        final vehicleId = m['vehicle_id'] as String?;
        if (vehicleId == null || vehicleId.isEmpty) continue;

        final points = ((m['points'] as List?) ?? const [])
            .whereType<Map>()
            .map((p) => RoutePoint.fromJson(Map<String, dynamic>.from(p)))
            .toList();
        if (points.length < 2) continue;

        await PendingRoutesStore.add(PendingRoute(
          id: PendingRoutesStore.newId(),
          vehicleId: vehicleId,
          startTime: DateTime.parse(m['start_time'] as String),
          endTime: DateTime.parse(m['end_time'] as String),
          points: points,
          totalDistance: (m['total_distance'] as num?)?.toDouble() ?? 0,
          averageSpeed: (m['average_speed'] as num?)?.toDouble() ?? 0,
          // syncPending re-lee el km actual del vehículo, así que 0 aquí es seguro.
          currentMileage: 0,
          routeNumber: 0,
          notes: 'Ruta automática',
        ));
        imported++;
      } catch (_) {}
    }

    if (imported > 0) {
      try { await RouteService.syncPending(); } catch (_) {}
    }
    return imported;
  }
}
