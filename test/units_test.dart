import 'package:flutter_test/flutter_test.dart';
import 'package:app_virtual_garaje/utils/units.dart';

void main() {
  test('litros: se muestra en L/100km sin convertir', () {
    expect(consumptionToDisplay(8, FuelUnit.liters), 8);
    expect(consumptionLabel(FuelUnit.liters), 'L/100km');
  });

  test('galones: L/100km → mpg', () {
    expect(consumptionToDisplay(8, FuelUnit.gallons), closeTo(29.4, 0.05));
    expect(consumptionLabel(FuelUnit.gallons), 'mpg');
  });

  test('valor desconocido o ausente en BD → litros', () {
    expect(FuelUnit.fromDb(null), FuelUnit.liters);
    expect(FuelUnit.fromDb('gallons'), FuelUnit.gallons);
  });
}
