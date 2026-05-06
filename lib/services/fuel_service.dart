import 'package:supabase_flutter/supabase_flutter.dart';

class FuelLog {
  const FuelLog({
    required this.id,
    required this.vehicleId,
    required this.date,
    required this.liters,
    required this.cost,
    required this.mileage,
    this.costPerLiter,
    this.station,
    this.isTankFull = true,
    this.consumption,
  });

  final String id;
  final String vehicleId;
  final DateTime date;
  final double liters;
  final double cost;
  final double mileage;
  final double? costPerLiter;
  final String? station;
  final bool isTankFull;
  final double? consumption;

  factory FuelLog.fromJson(Map<String, dynamic> j) => FuelLog(
        id: j['id'] as String,
        vehicleId: j['vehicle_id'] as String,
        date: DateTime.parse(j['date'] as String),
        liters: (j['liters'] as num).toDouble(),
        cost: (j['cost'] as num).toDouble(),
        mileage: (j['mileage'] as num).toDouble(),
        costPerLiter: (j['cost_per_liter'] as num?)?.toDouble(),
        station: j['station'] as String?,
        isTankFull: j['is_tank_full'] as bool? ?? true,
        consumption: (j['consumption'] as num?)?.toDouble(),
      );
}

class EnergyLog {
  const EnergyLog({
    required this.id,
    required this.vehicleId,
    required this.date,
    required this.odometer,
    required this.initialLevel,
    required this.finalLevel,
    required this.energyAdded,
    this.connectorType,
    this.location,
  });

  final String id;
  final String vehicleId;
  final DateTime date;
  final double odometer;
  final double initialLevel;
  final double finalLevel;
  final double energyAdded;
  final String? connectorType;
  final String? location;

  factory EnergyLog.fromJson(Map<String, dynamic> j) => EnergyLog(
        id: j['id'] as String,
        vehicleId: j['vehicle_id'] as String,
        date: DateTime.parse(j['date'] as String),
        odometer: (j['odometer'] as num).toDouble(),
        initialLevel: (j['initial_level'] as num).toDouble(),
        finalLevel: (j['final_level'] as num).toDouble(),
        energyAdded: (j['energy_added'] as num).toDouble(),
        connectorType: j['connector_type'] as String?,
        location: j['location'] as String?,
      );
}

class FuelService {
  static SupabaseClient get _db => Supabase.instance.client;

  static Future<List<FuelLog>> fetchFuelLogs(String vehicleId) async {
    final data = await _db
        .from('fuel_logs')
        .select()
        .eq('vehicle_id', vehicleId)
        .order('date', ascending: false)
        .limit(50);
    return (data as List).map((j) => FuelLog.fromJson(j)).toList();
  }

  static Future<List<EnergyLog>> fetchEnergyLogs(String vehicleId) async {
    final data = await _db
        .from('energy_logs')
        .select()
        .eq('vehicle_id', vehicleId)
        .order('date', ascending: false)
        .limit(50);
    return (data as List).map((j) => EnergyLog.fromJson(j)).toList();
  }

  static Future<void> addFuelLog({
    required String vehicleId,
    required DateTime date,
    required double liters,
    required double cost,
    required double mileage,
    String? station,
    bool isTankFull = true,
  }) async {
    final costPerLiter = liters > 0 ? cost / liters : null;
    await _db.from('fuel_logs').insert({
      'vehicle_id': vehicleId,
      'date': date.toIso8601String(),
      'liters': liters,
      'cost': cost,
      'mileage': mileage,
      'cost_per_liter': costPerLiter,
      'station': station?.isEmpty == true ? null : station,
      'is_tank_full': isTankFull,
    });
    await _db
        .from('vehicles')
        .update({'current_mileage': mileage})
        .eq('id', vehicleId);
  }

  static Future<void> addEnergyLog({
    required String vehicleId,
    required DateTime date,
    required double odometer,
    required double initialLevel,
    required double finalLevel,
    required double energyAdded,
    String? connectorType,
    String? location,
  }) async {
    await _db.from('energy_logs').insert({
      'vehicle_id': vehicleId,
      'date': date.toIso8601String().split('T').first,
      'odometer': odometer,
      'initial_level': initialLevel.round(),
      'final_level': finalLevel.round(),
      'energy_added': energyAdded,
      'connector_type': connectorType?.isEmpty == true ? null : connectorType,
      'location': location?.isEmpty == true ? null : location,
    });
    await _db
        .from('vehicles')
        .update({'current_mileage': odometer})
        .eq('id', vehicleId);
  }
}
