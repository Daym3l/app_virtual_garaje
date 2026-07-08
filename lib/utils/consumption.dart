/// Consumo de combustible por método "full-to-full" (puerto de
/// lib/utils/consumption.ts de la web).
///
/// Un segmento válido va de una carga con tanque lleno a la SIGUIENTE carga
/// con tanque lleno (por odómetro), acumulando los litros de las parciales
/// intermedias. El promedio es ponderado (Σ litros ÷ Σ km × 100).
///
/// Fallback: sin 2 cargas llenas se estima con el agregado (rango de odómetro
/// vs litros totales excluyendo la primera carga) y se marca `isEstimate`.
library;

class ConsumptionEntry {
  const ConsumptionEntry({
    required this.mileage,
    required this.liters,
    required this.isTankFull,
  });

  final double mileage;
  final double liters;
  final bool isTankFull;
}

class ConsumptionResult {
  const ConsumptionResult({this.avgL100km, this.isEstimate = false});
  final double? avgL100km;
  final bool isEstimate;
}

List<ConsumptionEntry> _validEntries(List<ConsumptionEntry> entries) {
  final valid = entries.where((e) => e.mileage > 0 && e.liters > 0).toList()
    ..sort((a, b) => a.mileage.compareTo(b.mileage));
  return valid;
}

ConsumptionResult computeConsumption(List<ConsumptionEntry> entries) {
  final sorted = _validEntries(entries);

  // Segmentos full-to-full
  double totalKm = 0;
  double totalLiters = 0;
  ConsumptionEntry? anchor;
  double segLiters = 0;

  for (final entry in sorted) {
    if (anchor != null) segLiters += entry.liters;
    if (!entry.isTankFull) continue;

    if (anchor != null) {
      final km = entry.mileage - anchor.mileage;
      if (km > 0) {
        totalKm += km;
        totalLiters += segLiters;
      }
    }
    anchor = entry;
    segLiters = 0;
  }

  if (totalKm > 0 && totalLiters > 0) {
    return ConsumptionResult(avgL100km: totalLiters / totalKm * 100);
  }

  // Fallback agregado: rango de odómetro vs litros sin la primera carga
  if (sorted.length >= 2) {
    final km = sorted.last.mileage - sorted.first.mileage;
    final liters = sorted.skip(1).fold(0.0, (s, e) => s + e.liters);
    if (km > 0 && liters > 0) {
      return ConsumptionResult(avgL100km: liters / km * 100, isEstimate: true);
    }
  }

  return const ConsumptionResult();
}
