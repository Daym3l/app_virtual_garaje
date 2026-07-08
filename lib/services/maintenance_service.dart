import 'package:supabase_flutter/supabase_flutter.dart';

class MaintenanceItem {
  const MaintenanceItem({required this.type, this.notes = ''});
  final String type;
  final String notes;

  Map<String, dynamic> toJson() => {'type': type, 'notes': notes};
}

class MaintenancePart {
  const MaintenancePart({required this.name, this.price});
  final String name;
  final double? price;

  Map<String, dynamic> toJson() => {'name': name, 'price': price};
}

/// Normaliza el JSONB `items` (o cualquier entrada no confiable): solo tipos
/// conocidos, sin duplicados (gana el primero), notas no-string → ''. Vacío o
/// NULL (filas antiguas) → un item con el tipo de la columna `type`.
List<MaintenanceItem> normalizeItems(dynamic raw, String fallbackType) {
  final items = <MaintenanceItem>[];
  final seen = <String>{};
  if (raw is List) {
    for (final entry in raw) {
      if (entry is! Map) continue;
      final type = entry['type'];
      if (type is! String || !kMaintenanceTypes.contains(type) || seen.contains(type)) continue;
      final notes = entry['notes'];
      seen.add(type);
      items.add(MaintenanceItem(type: type, notes: notes is String ? notes : ''));
    }
  }
  if (items.isEmpty) return [MaintenanceItem(type: fallbackType)];
  return items;
}

/// Normaliza el JSONB `parts_list`: solo entradas con `name` no vacío;
/// `price` numérico finito >= 0 o null. NULL/basura → [].
List<MaintenancePart> normalizeParts(dynamic raw) {
  if (raw is! List) return const [];
  final parts = <MaintenancePart>[];
  for (final entry in raw) {
    if (entry is! Map) continue;
    final name = entry['name'];
    if (name is! String || name.trim().isEmpty) continue;
    final price = entry['price'];
    final validPrice = price is num && price.toDouble().isFinite && price >= 0;
    parts.add(MaintenancePart(name: name.trim(), price: validPrice ? price.toDouble() : null));
  }
  return parts;
}

/// Etiqueta compacta: "Batería" para un item, "Batería +2" para tres.
String itemsLabel(List<MaintenanceItem> items) {
  if (items.isEmpty) return '';
  final primary = kMaintenanceTypeLabels[items.first.type] ?? items.first.type;
  return items.length > 1 ? '$primary +${items.length - 1}' : primary;
}

double partsTotal(List<MaintenancePart> parts) =>
    parts.fold(0.0, (sum, p) => sum + (p.price ?? 0));

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
    this.intervalKm,
    this.intervalDays,
    this.performedBy,
    this.parts,
    this.warrantyUntil,
    this.items = const [],
    this.partsList = const [],
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
  final double? intervalKm;
  final int? intervalDays;
  final String? performedBy;
  final String? parts;
  final DateTime? warrantyUntil;
  final List<MaintenanceItem> items;
  final List<MaintenancePart> partsList;

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
        intervalKm: (j['interval_km'] as num?)?.toDouble(),
        intervalDays: (j['interval_days'] as num?)?.toInt(),
        performedBy: j['performed_by'] as String?,
        parts: j['parts'] as String?,
        warrantyUntil: j['warranty_until'] != null
            ? DateTime.parse(j['warranty_until'] as String)
            : null,
        items: normalizeItems(j['items'], j['type'] as String),
        partsList: normalizeParts(j['parts_list']),
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
  'transmission',
  'suspension',
  'brakes',
  'tires',
  'alignment',
  'filters',
  'battery',
  'cooling',
  'electrical',
  'engine',
  'exhaust',
  'steering',
  'belts',
  'diagnostics',
  'other',
];

const kMaintenanceTypeLabels = {
  'oilChange': 'Cambio de aceite',
  'transmission': 'Transmisión',
  'suspension': 'Suspensión',
  'brakes': 'Frenos',
  'tires': 'Neumáticos',
  'alignment': 'Alineación',
  'filters': 'Filtros',
  'battery': 'Batería',
  'cooling': 'Refrigeración',
  'electrical': 'Eléctrico',
  'engine': 'Motor',
  'exhaust': 'Escape',
  'steering': 'Dirección',
  'belts': 'Correas',
  'diagnostics': 'Diagnóstico',
  'other': 'Otro',
};

class MaintenanceInterval {
  const MaintenanceInterval({this.km, this.days});
  final double? km;
  final int? days;
}

const kMaintenanceIntervals = <String, MaintenanceInterval>{
  'oilChange': MaintenanceInterval(km: 5000, days: 180),
  'filters': MaintenanceInterval(km: 15000, days: 365),
  'tires': MaintenanceInterval(km: 10000, days: 180),
  'brakes': MaintenanceInterval(km: 20000, days: 365),
  'alignment': MaintenanceInterval(km: 10000, days: 180),
  'engine': MaintenanceInterval(km: 30000, days: 730),
  'transmission': MaintenanceInterval(km: 40000, days: 730),
  'cooling': MaintenanceInterval(km: 40000, days: 730),
  'belts': MaintenanceInterval(km: 60000, days: 1825),
  'battery': MaintenanceInterval(days: 1095),
  'suspension': MaintenanceInterval(km: 20000, days: 365),
  'steering': MaintenanceInterval(km: 20000, days: 365),
  'exhaust': MaintenanceInterval(km: 30000, days: 730),
  'electrical': MaintenanceInterval(days: 365),
  'diagnostics': MaintenanceInterval(days: 365),
  'other': MaintenanceInterval(),
};

MaintenanceInterval defaultInterval(String type) =>
    kMaintenanceIntervals[type] ?? const MaintenanceInterval();

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
    required List<MaintenanceItem> items,
    required String description,
    required String serviceCategory,
    required DateTime date,
    required double mileage,
    required double cost,
    bool isCompleted = true,
    bool isUrgent = false,
    double? intervalKm,
    int? intervalDays,
    String? performedBy,
    List<MaintenancePart> partsList = const [],
    DateTime? warrantyUntil,
  }) async {
    // next_* lo calcula el trigger de la BD al pasar un registro pendiente a
    // completado. En un INSERT el trigger no se dispara, así que para registros
    // creados ya completados se calcula aquí a partir de los intervalos.
    double? nextMileage;
    DateTime? nextDate;
    if (isCompleted) {
      if (intervalKm != null) nextMileage = mileage + intervalKm;
      if (intervalDays != null) nextDate = date.add(Duration(days: intervalDays));
    }
    await _db.from('maintenances').insert({
      'vehicle_id': vehicleId,
      'type': items.first.type,
      'items': items.map((i) => i.toJson()).toList(),
      'description': description,
      'service_category': serviceCategory,
      'date': date.toIso8601String(),
      'mileage': mileage,
      'cost': cost,
      'is_completed': isCompleted,
      'is_urgent': isUrgent,
      'interval_km': intervalKm,
      'interval_days': intervalDays,
      'next_mileage': nextMileage,
      'next_date': nextDate?.toIso8601String().split('T').first,
      'performed_by': performedBy,
      'parts': null,
      'parts_list': partsList.map((p) => p.toJson()).toList(),
      'warranty_until': warrantyUntil?.toIso8601String().split('T').first,
    });
  }

  static Future<void> markCompleted(String id) async {
    await _db
        .from('maintenances')
        .update({'is_completed': true})
        .eq('id', id);
  }
}
