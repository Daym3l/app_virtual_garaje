import 'package:supabase_flutter/supabase_flutter.dart';
import '../utils/consumption.dart';

enum AlertLevel { error, warning, info }

class MaintenanceAlert {
  const MaintenanceAlert({
    required this.type,
    required this.level,
    required this.subtitle,
    required this.sortKey,
  });

  final String type;
  final AlertLevel level;
  final String subtitle;
  final double sortKey;
}

class WarrantyAlert {
  const WarrantyAlert({
    required this.type,
    required this.level,
    required this.subtitle,
    required this.sortKey,
  });

  final String type;
  final AlertLevel level;
  final String subtitle;
  final double sortKey;
}

class DashboardData {
  const DashboardData({
    required this.lastFuelDate,
    required this.lastFuelLiters,
    required this.lastFuelCost,
    required this.avgConsumption,
    required this.alerts,
    required this.warranties,
    required this.kmThisMonth,
  });

  final DateTime? lastFuelDate;
  final double? lastFuelLiters;
  final double? lastFuelCost;
  final double? avgConsumption;
  final List<MaintenanceAlert> alerts;
  final List<WarrantyAlert> warranties;
  final double kmThisMonth;

  bool get hasUrgentAlert => alerts.any((a) => a.level == AlertLevel.error);
  int get urgentCount => alerts.where((a) => a.level == AlertLevel.error).length;

  // Compat getters para _StatsGrid
  String? get nextMaintenance => alerts.isEmpty ? null : alerts.first.type;
  bool get nextMaintenanceUrgent => alerts.isEmpty ? false : alerts.first.level == AlertLevel.error;
  int? get nextMaintenanceDaysLeft => null;
}

class DashboardService {
  static SupabaseClient get _db => Supabase.instance.client;

  static Future<DashboardData> fetch(
    String vehicleId, {
    bool isElectric = false,
    required double currentMileage,
  }) async {
    final now = DateTime.now();
    final monthStart = DateTime(now.year, now.month, 1).toIso8601String();
    final today = DateTime(now.year, now.month, now.day).toIso8601String().split('T').first;

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

      // Fuel logs for consumption calc (full-to-full)
      isElectric
          ? Future.value(<dynamic>[])
          : _db
              .from('fuel_logs')
              .select('mileage, liters, is_tank_full')
              .eq('vehicle_id', vehicleId)
              .gt('mileage', 0)
              .order('mileage', ascending: false)
              .limit(100),

      // All pending maintenances with next_date or next_mileage
      _db
          .from('maintenances')
          .select('type, next_date, next_mileage, is_urgent')
          .eq('vehicle_id', vehicleId)
          .eq('is_completed', false),

      // Active warranties (warranty_until >= today)
      _db
          .from('maintenances')
          .select('type, description, warranty_until')
          .eq('vehicle_id', vehicleId)
          .not('warranty_until', 'is', null)
          .gte('warranty_until', today)
          .order('warranty_until', ascending: true),

      // Km this month + baseline
      Future.wait([
        _db
            .from('mileage_logs')
            .select('mileage')
            .eq('vehicle_id', vehicleId)
            .gte('date', monthStart),
        _db
            .from('mileage_logs')
            .select('mileage')
            .eq('vehicle_id', vehicleId)
            .lt('date', monthStart)
            .order('date', ascending: false)
            .limit(1),
      ]),
    ]);

    final lastLog = futures[0];
    final consumptionLogs = futures[1];
    final maintLogs = futures[2];
    final warrantyLogs = futures[3];
    final kmFutures = futures[4] as List<List<dynamic>>;
    final mileageLogsThisMonth = kmFutures[0];
    final mileageLogsBaseline = kmFutures[1];

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

    // Avg consumption (full-to-full: acumula parciales entre tanques llenos)
    double? avgConsumption;
    if (!isElectric && consumptionLogs.isNotEmpty) {
      final entries = consumptionLogs
          .map((r) => ConsumptionEntry(
                mileage: (r['mileage'] as num?)?.toDouble() ?? 0,
                liters: (r['liters'] as num?)?.toDouble() ?? 0,
                isTankFull: (r['is_tank_full'] as bool?) ?? false,
              ))
          .toList();
      final result = computeConsumption(entries);
      if (result.avgL100km != null && result.avgL100km! > 0) {
        avgConsumption = 100 / result.avgL100km!;
      }
    }

    // Alerts
    final alerts = _buildAlerts(maintLogs, currentMileage, now);
    final warranties = _buildWarranties(warrantyLogs, now);

    // Km this month
    double kmThisMonth = 0;
    final allValues = [
      ...mileageLogsThisMonth.map((r) => (r['mileage'] as num?)?.toDouble() ?? 0.0),
      ...mileageLogsBaseline.map((r) => (r['mileage'] as num?)?.toDouble() ?? 0.0),
    ].where((v) => v > 0).toList();
    if (allValues.length >= 2) {
      final maxVal = allValues.reduce((a, b) => a > b ? a : b);
      final minVal = allValues.reduce((a, b) => a < b ? a : b);
      kmThisMonth = maxVal - minVal;
    } else if (mileageLogsThisMonth.length == 1 && mileageLogsBaseline.isNotEmpty) {
      final current = (mileageLogsThisMonth.first['mileage'] as num?)?.toDouble() ?? 0;
      final baseline = (mileageLogsBaseline.first['mileage'] as num?)?.toDouble() ?? 0;
      kmThisMonth = (current - baseline).clamp(0, double.infinity);
    }

    return DashboardData(
      lastFuelDate: lastFuelDate,
      lastFuelLiters: lastFuelLiters,
      lastFuelCost: lastFuelCost,
      avgConsumption: avgConsumption,
      alerts: alerts,
      warranties: warranties,
      kmThisMonth: kmThisMonth,
    );
  }

  static List<WarrantyAlert> _buildWarranties(List rows, DateTime now) {
    final today = DateTime(now.year, now.month, now.day);
    final alerts = <WarrantyAlert>[];

    for (final raw in rows) {
      final m = raw as Map<String, dynamic>;
      final until = DateTime.tryParse(m['warranty_until']?.toString() ?? '');
      if (until == null) continue;
      final target = DateTime(until.year, until.month, until.day);
      final daysLeft = target.difference(today).inDays;
      if (daysLeft < 0) continue;

      final type = _translateType((m['type'] as String?) ?? '');
      final level = daysLeft <= 30 ? AlertLevel.warning : AlertLevel.info;

      final String subtitle;
      if (daysLeft == 0) {
        subtitle = 'Vence hoy · ${_fmtDate(target)}';
      } else if (daysLeft == 1) {
        subtitle = 'Vence mañana · ${_fmtDate(target)}';
      } else {
        subtitle = 'Vence en $daysLeft días · ${_fmtDate(target)}';
      }

      alerts.add(WarrantyAlert(
        type: type,
        level: level,
        subtitle: subtitle,
        sortKey: daysLeft.toDouble(),
      ));
    }

    alerts.sort((a, b) => a.sortKey.compareTo(b.sortKey));
    return alerts;
  }

  static String _fmtDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  static List<MaintenanceAlert> _buildAlerts(
    List maintLogs,
    double currentMileage,
    DateTime now,
  ) {
    final alerts = <MaintenanceAlert>[];

    for (final raw in maintLogs) {
      final m = raw as Map<String, dynamic>;
      final rawType = (m['type'] as String?) ?? '';
      final type = _translateType(rawType);
      final isUrgent = (m['is_urgent'] as bool?) ?? false;
      final nextMileage = (m['next_mileage'] as num?)?.toDouble();
      final nextDate = DateTime.tryParse(m['next_date']?.toString() ?? '');

      // Relevance filter
      final kmLeft = nextMileage != null ? nextMileage - currentMileage : null;
      final daysLeft = nextDate != null ? nextDate.difference(now).inDays : null;

      final relevant = isUrgent ||
          (kmLeft != null && kmLeft <= 1000) ||
          (daysLeft != null && daysLeft <= 30);
      if (!relevant) continue;

      // Level por km
      AlertLevel kmLevel = AlertLevel.info;
      if (kmLeft != null) {
        if (kmLeft <= 0) {
          kmLevel = AlertLevel.error;
        } else if (kmLeft <= 500) {
          kmLevel = AlertLevel.warning;
        }
      }

      // Level por fecha
      AlertLevel dateLevel = AlertLevel.info;
      if (daysLeft != null) {
        if (daysLeft <= 0) {
          dateLevel = AlertLevel.error;
        } else if (daysLeft <= 7) {
          dateLevel = AlertLevel.warning;
        }
      }

      // Peor nivel; isUrgent → siempre error
      AlertLevel level;
      if (isUrgent) {
        level = AlertLevel.error;
      } else {
        level = _worst(kmLevel, dateLevel);
      }

      // Subtítulo: mostrar fecha si urgente, fecha en error/warning, o sin kmLeft
      final showDate = isUrgent ||
          dateLevel == AlertLevel.error ||
          dateLevel == AlertLevel.warning ||
          kmLeft == null ||
          kmLevel == AlertLevel.info;

      final String subtitle;
      if (showDate && daysLeft != null) {
        if (daysLeft == 0) {
          subtitle = 'Vencido hace hoy';
        } else if (daysLeft < 0) {
          subtitle = 'Vencido hace ${-daysLeft} día(s)';
        } else {
          subtitle = 'Vence en $daysLeft día(s)';
        }
      } else if (!showDate && kmLeft != null) {
        if (kmLeft <= 0) {
          subtitle = 'Vencido hace ${(-kmLeft).toStringAsFixed(0)} km';
        } else {
          subtitle = 'Vence en ${kmLeft.toStringAsFixed(0)} km';
        }
      } else {
        subtitle = 'Sin fecha ni recorrido definido';
      }

      // sortKey: min(kmLeft, daysLeft*100) — menor = más urgente
      final sortKey = [
        if (kmLeft != null) kmLeft,
        if (daysLeft != null) daysLeft * 100.0,
        if (isUrgent) -double.maxFinite,
      ].fold<double>(double.maxFinite, (a, b) => b < a ? b : a);

      alerts.add(MaintenanceAlert(
        type: type,
        level: level,
        subtitle: subtitle,
        sortKey: sortKey,
      ));
    }

    alerts.sort((a, b) => a.sortKey.compareTo(b.sortKey));
    return alerts;
  }

  static AlertLevel _worst(AlertLevel a, AlertLevel b) {
    if (a == AlertLevel.error || b == AlertLevel.error) return AlertLevel.error;
    if (a == AlertLevel.warning || b == AlertLevel.warning) return AlertLevel.warning;
    return AlertLevel.info;
  }

  static const _typeMap = {
    'oil': 'Aceite',
    'oil_change': 'Cambio de aceite',
    'filter': 'Filtros',
    'filters': 'Filtros',
    'brakes': 'Frenos',
    'tires': 'Neumáticos',
    'tyres': 'Neumáticos',
    'battery': 'Batería',
    'transmission': 'Transmisión',
    'suspension': 'Suspensión',
    'steering': 'Dirección',
    'air_conditioning': 'Climatización',
    'ac': 'Climatización',
    'bodywork': 'Carrocería',
    'electrical': 'Electricidad',
    'fluids': 'Líquidos',
    'timing_belt': 'Distribución',
    'clutch': 'Embrague',
    'exhaust': 'Escape',
    'itv': 'ITV/Revisión',
    'inspection': 'ITV/Revisión',
    'revision': 'Revisión',
    'spark_plugs': 'Bujías',
    'coolant': 'Refrigerante',
    'alignment': 'Alineación',
  };

  static String _translateType(String raw) {
    if (raw.isEmpty) return 'Mantenimiento';
    return _typeMap[raw.toLowerCase()] ?? _capitalize(raw);
  }

  static String _capitalize(String s) {
    if (s.isEmpty) return s;
    return s[0].toUpperCase() + s.substring(1).replaceAll('_', ' ');
  }
}
