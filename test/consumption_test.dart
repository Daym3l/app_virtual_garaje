import 'package:flutter_test/flutter_test.dart';
import 'package:app_virtual_garaje/utils/consumption.dart';

ConsumptionEntry e(String date, double mileage, double liters, {bool full = true}) =>
    ConsumptionEntry(
      date: DateTime.parse('${date}T12:00:00Z'),
      mileage: mileage,
      liters: liters,
      isTankFull: full,
    );

void main() {
  final now = DateTime.utc(2026, 10, 26, 12);

  test('acumula parciales entre tanques llenos', () {
    final v = vehicleConsumption([
      e('2026-09-01', 1000, 40),
      e('2026-09-10', 1200, 10, full: false),
      e('2026-09-20', 1500, 30),
    ], now: now);
    expect(v.recent, closeTo(40 / 500 * 100, 1e-9));
    expect(v.isEstimate, isFalse);
  });

  test('descarta un tramo imposible en vez de dejar que domine', () {
    final v = vehicleConsumption([
      e('2026-08-01', 1000, 40),
      e('2026-08-15', 1500, 40),
      e('2026-08-16', 1503, 40), // odómetro mal tecleado: 1333 L/100km
      e('2026-09-01', 2003, 40),
    ], now: now);
    expect(v.discarded, 1);
    expect(v.recent, closeTo(80 / 1000 * 100, 1e-9));
  });

  test('ignora tramos de hace más de 6 meses en el valor reciente', () {
    final v = vehicleConsumption([
      e('2025-01-01', 1000, 40),
      e('2025-02-01', 1200, 40), // 20 L/100km viejo
      e('2026-09-01', 1700, 40),
      e('2026-09-20', 2200, 40), // 8 L/100km recientes
    ], now: now);
    expect(v.recent, closeTo(8, 1e-9));
  });

  test('sin medición reciente no presenta un dato viejo como actual', () {
    final v = vehicleConsumption([
      e('2025-01-01', 1000, 40),
      e('2025-02-01', 1500, 40),
    ], now: now);
    expect(v.recent, isNull);
    expect(v.isStale, isTrue);
    expect(v.historical, closeTo(8, 1e-9));
  });

  test('solo parciales: estimación agregada', () {
    final v = vehicleConsumption([
      e('2026-09-01', 1000, 20, full: false),
      e('2026-09-10', 1250, 20, full: false),
      e('2026-09-20', 1500, 20, full: false),
    ], now: now);
    expect(v.recent, closeTo(40 / 500 * 100, 1e-9));
    expect(v.isEstimate, isTrue);
  });
}
