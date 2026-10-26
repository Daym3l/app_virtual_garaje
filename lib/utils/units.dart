/// Unidades de los ajustes del usuario (`user_settings.fuel_unit`, compartido
/// con la web). Puerto de lib/utils/units.ts.
enum FuelUnit {
  liters,
  gallons;

  static FuelUnit fromDb(String? value) =>
      value == 'gallons' ? FuelUnit.gallons : FuelUnit.liters;
}

/// L/100km → la unidad de consumo del usuario (mpg con galones).
double consumptionToDisplay(double l100km, FuelUnit unit) =>
    unit == FuelUnit.gallons && l100km > 0 ? 235.215 / l100km : l100km;

String consumptionLabel(FuelUnit unit) =>
    unit == FuelUnit.gallons ? 'mpg' : 'L/100km';
