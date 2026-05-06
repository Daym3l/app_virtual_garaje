import 'package:supabase_flutter/supabase_flutter.dart';

class MaintenanceRecord {
  const MaintenanceRecord({
    required this.id,
    required this.vehicleId,
    required this.type,
    required this.description,
    required this.serviceCategory,
    required this.date,
    required this.mileage,
    required this.cost,
    required this.isCompleted,
    required this.isUrgent,
    this.nextMileage,
    this.nextDate,
  });

  final String id;
  final String vehicleId;
  final String type;
  final String description;
  final String serviceCategory;
  final DateTime date;
  final double mileage;
  final double cost;
  final bool isCompleted;
  final bool isUrgent;
  final double? nextMileage;
  final DateTime? nextDate;

  factory MaintenanceRecord.fromJson(Map<String, dynamic> j) =>
      MaintenanceRecord(
        id: j['id'] as String,
        vehicleId: j['vehicle_id'] as String,
        type: j['type'] as String,
        description: j['description'] as String? ?? '',
        serviceCategory: j['service_category'] as String? ?? 'general',
        date: DateTime.parse(j['date'] as String),
        mileage: (j['mileage'] as num?)?.toDouble() ?? 0,
        cost: (j['cost'] as num?)?.toDouble() ?? 0,
        isCompleted: j['is_completed'] as bool? ?? false,
        isUrgent: j['is_urgent'] as bool? ?? false,
        nextMileage: (j['next_mileage'] as num?)?.toDouble(),
        nextDate: j['next_date'] != null
            ? DateTime.parse(j['next_date'] as String)
            : null,
      );
}

const kServiceCategories = ['preventive', 'repair', 'inspection'];

const kServiceCategoryLabels = {
  'preventive': 'Preventivo',
  'repair': 'Reparación',
  'inspection': 'Inspección',
};

const kMaintenanceTypes = [
  'oilChange',
  'brakes',
  'engine',
  'transmission',
  'electrical',
  'steering',
  'other',
];

const kMaintenanceTypeLabels = {
  'oilChange': 'Cambio de aceite',
  'brakes': 'Frenos',
  'engine': 'Motor',
  'transmission': 'Transmisión',
  'electrical': 'Sistema eléctrico',
  'steering': 'Dirección',
  'other': 'Otro',
};

class MaintenanceService {
  static SupabaseClient get _db => Supabase.instance.client;

  static Future<List<MaintenanceRecord>> fetchRecords(String vehicleId) async {
    final data = await _db
        .from('maintenances')
        .select()
        .eq('vehicle_id', vehicleId)
        .order('date', ascending: false)
        .limit(50);
    return (data as List).map((j) => MaintenanceRecord.fromJson(j)).toList();
  }

  static Future<void> addRecord({
    required String vehicleId,
    required String type,
    required String description,
    required String serviceCategory,
    required DateTime date,
    required double mileage,
    required double cost,
    bool isCompleted = true,
    bool isUrgent = false,
    double? nextMileage,
    DateTime? nextDate,
  }) async {
    await _db.from('maintenances').insert({
      'vehicle_id': vehicleId,
      'type': type,
      'description': description,
      'service_category': serviceCategory,
      'date': date.toIso8601String(),
      'mileage': mileage,
      'cost': cost,
      'is_completed': isCompleted,
      'is_urgent': isUrgent,
      'next_mileage': nextMileage,
      'next_date': nextDate?.toIso8601String().split('T').first,
    });
  }

  static Future<void> markCompleted(String id) async {
    await _db
        .from('maintenances')
        .update({'is_completed': true})
        .eq('id', id);
  }
}
