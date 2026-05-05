import 'package:supabase_flutter/supabase_flutter.dart';

class DashboardData {
  const DashboardData({
    required this.lastFuelDate,
    required this.lastFuelLiters,
    required this.lastFuelCost,
    required this.avgConsumption,
    required this.nextMaintenance,
    required this.nextMaintenanceDaysLeft,
    required this.nextMaintenanceUrgent,
    required this.kmThisMonth,
  });

  final DateTime? lastFuelDate;
  final double? lastFuelLiters;
  final double? lastFuelCost;
  final double? avgConsumption; // L/100km, null for electric
  final String? nextMaintenance;
  final int? nextMaintenanceDaysLeft; // null = no upcoming
  final bool nextMaintenanceUrgent;
  final double kmThisMonth;
}

class DashboardService {
  static SupabaseClient get _db => Supabase.instance.client;

  static Future<DashboardData> fetch(String vehicleId, {bool isElectric = false}) async {
    final now = DateTime.now();
    final monthStart = DateTime(now.year, now.month, 1).toIso8601String();

    final futures = await Future.wait([
      // Last fuel/energy log
      isElectric
          ? _db
              .from('energy_logs')
              .select('date, energy_added, odometer')
              .eq('vehicle_id', vehicleId)
              .order('date', ascending: false)
              .limit(1)
          : _db
              .from('fuel_logs')
              .select('date, liters, cost, consumption')
              .eq('vehicle_id', vehicleId)
              .order('date', ascending: false)
              .limit(1),

      // Last 6 fuel logs to calculate consumption from mileage deltas
      isElectric
          ? Future.value(<dynamic>[])
          : _db
              .from('fuel_logs')
              .select('mileage, liters, consumption, is_tank_full')
              .eq('vehicle_id', vehicleId)
              .order('mileage', ascending: false)
              .limit(6),

      // Next pending maintenance
      _db
          .from('maintenances')
          .select('type, next_date, is_urgent')
          .eq('vehicle_id', vehicleId)
          .eq('is_completed', false)
          .not('next_date', 'is', null)
          .order('next_date', ascending: true)
          .limit(1),

      // Km this month from mileage_logs
      _db
          .from('mileage_logs')
          .select('mileage')
          .eq('vehicle_id', vehicleId)
          .gte('date', monthStart),
    ]);

    final lastLog = futures[0];
    final consumptionLogs = futures[1];
    final nextMaintLogs = futures[2];
    final mileageLogs = futures[3];

    // Last fill
    DateTime? lastFuelDate;
    double? lastFuelLiters;
    double? lastFuelCost;
    if (lastLog.isNotEmpty) {
      final l = lastLog.first as Map<String, dynamic>;
      lastFuelDate = DateTime.tryParse(l['date']?.toString() ?? '');
      if (isElectric) {
        lastFuelLiters = (l['energy_added'] as num?)?.toDouble();
      } else {
        lastFuelLiters = (l['liters'] as num?)?.toDouble();
        lastFuelCost = (l['cost'] as num?)?.toDouble();
      }
    }

    // Avg consumption — prefer stored `consumption` field; fallback: calc from mileage deltas
    double? avgConsumption;
    if (!isElectric && consumptionLogs.isNotEmpty) {
      // Try stored consumption values first
      final stored = consumptionLogs
          .map((r) => (r['consumption'] as num?)?.toDouble())
          .whereType<double>()
          .toList();
      if (stored.isNotEmpty) {
        avgConsumption = stored.reduce((a, b) => a + b) / stored.length;
      } else {
        // Calculate from consecutive mileage + liters (ordered desc by mileage)
        final logs = consumptionLogs
            .map((r) => (
                  mileage: (r['mileage'] as num?)?.toDouble() ?? 0,
                  liters: (r['liters'] as num?)?.toDouble() ?? 0,
                ))
            .toList();
        final samples = <double>[];
        for (int i = 0; i < logs.length - 1; i++) {
          final kmDelta = logs[i].mileage - logs[i + 1].mileage;
          if (kmDelta > 0 && logs[i].liters > 0) {
            samples.add(logs[i].liters / kmDelta * 100); // L/100km
          }
        }
        if (samples.isNotEmpty) {
          avgConsumption = samples.reduce((a, b) => a + b) / samples.length;
        }
      }
    }

    // Next maintenance
    String? nextMaintenance;
    int? nextMaintDaysLeft;
    bool nextMaintUrgent = false;
    if (nextMaintLogs.isNotEmpty) {
      final m = nextMaintLogs.first as Map<String, dynamic>;
      nextMaintenance = m['type'] as String?;
      nextMaintUrgent = (m['is_urgent'] as bool?) ?? false;
      final nextDate = DateTime.tryParse(m['next_date']?.toString() ?? '');
      if (nextDate != null) {
        nextMaintDaysLeft = nextDate.difference(now).inDays;
      }
    }

    // Km this month
    double kmThisMonth = 0;
    if (mileageLogs.isNotEmpty) {
      final values = mileageLogs
          .map((r) => (r['mileage'] as num?)?.toDouble() ?? 0.0)
          .toList();
      kmThisMonth = values.isNotEmpty ? values.last - values.first : 0;
      if (kmThisMonth < 0) kmThisMonth = 0;
    }

    return DashboardData(
      lastFuelDate: lastFuelDate,
      lastFuelLiters: lastFuelLiters,
      lastFuelCost: lastFuelCost,
      avgConsumption: avgConsumption,
      nextMaintenance: nextMaintenance,
      nextMaintenanceDaysLeft: nextMaintDaysLeft,
      nextMaintenanceUrgent: nextMaintUrgent,
      kmThisMonth: kmThisMonth,
    );
  }
}
