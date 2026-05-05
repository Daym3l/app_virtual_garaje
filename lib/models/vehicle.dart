enum FuelType { gasolina, diesel, electrico, hibrido, otro }

enum VehicleType { car, moto, truck, other }

class Vehicle {
  const Vehicle({
    required this.id,
    required this.name,
    required this.type,
    required this.fuelType,
    required this.plate,
    required this.brand,
    required this.model,
    required this.year,
    required this.km,
    required this.initialKm,
    this.color,
    this.batteryCapacity,
    this.fuelTankCapacity,
    this.imageBase64,
  });

  final String id;
  final String name;
  final VehicleType type;
  final FuelType fuelType;
  final String plate;
  final String brand;
  final String model;
  final int year;
  final double km;
  final double initialKm;
  final String? color;
  final double? batteryCapacity;
  final double? fuelTankCapacity;
  final String? imageBase64;

  bool get isElectric => fuelType == FuelType.electrico;
  double get totalKm => (km - initialKm).clamp(0, double.infinity);

  String get displayName => '$brand $model $year';

  factory Vehicle.fromJson(Map<String, dynamic> j) {
    return Vehicle(
      id: j['id'] as String,
      brand: j['brand'] as String,
      model: j['model'] as String,
      year: j['year'] as int,
      plate: j['plate'] as String,
      color: j['color'] as String?,
      km: (j['current_mileage'] as num).toDouble(),
      initialKm: (j['initial_mileage'] as num).toDouble(),
      type: _parseVehicleType(j['vehicle_type'] as String? ?? 'car'),
      fuelType: _parseFuelType(j['engine_type'] as String? ?? 'gasolina'),
      batteryCapacity: (j['battery_capacity'] as num?)?.toDouble(),
      fuelTankCapacity: (j['fuel_tank_capacity'] as num?)?.toDouble(),
      imageBase64: j['image_base64'] as String?,
      name: '${j['brand']} ${j['model']}',
    );
  }

  static VehicleType _parseVehicleType(String s) {
    switch (s.toLowerCase()) {
      case 'moto': case 'motorcycle': return VehicleType.moto;
      case 'truck': case 'camion': return VehicleType.truck;
      default: return VehicleType.car;
    }
  }

  static FuelType _parseFuelType(String s) {
    switch (s.toLowerCase()) {
      case 'diesel': case 'diésel': return FuelType.diesel;
      case 'electrico': case 'eléctrico': case 'electric': return FuelType.electrico;
      case 'hibrido': case 'híbrido': case 'hybrid': return FuelType.hibrido;
      default: return FuelType.gasolina;
    }
  }
}
