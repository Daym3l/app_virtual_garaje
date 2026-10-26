/// Consumo de combustible por método "full-to-full" (puerto de
/// lib/utils/consumption.ts de la web).
///
/// Un segmento válido va de una carga con tanque lleno a la SIGUIENTE carga
/// con tanque lleno (por odómetro), acumulando los litros de las parciales
/// intermedias. El promedio es ponderado (Σ litros ÷ Σ km × 100).
///
/// Fallback: sin 2 cargas llenas se estima con el agregado (rango de odómetro
/// vs litros totales excluyendo la primera carga) y se marca `isEstimate`.
/// Ver `vehicleConsumption`, la única entrada pública.
library;

class ConsumptionEntry {
  const ConsumptionEntry({
    this.date,
    required this.mileage,
    required this.liters,
    required this.isTankFull,
  });

  final DateTime? date;
  final double mileage;
  final double liters;
  final bool isTankFull;
}

List<ConsumptionEntry> _validEntries(List<ConsumptionEntry> entries) {
  final valid = entries.where((e) => e.mileage > 0 && e.liters > 0).toList()
    ..sort((a, b) => a.mileage.compareTo(b.mileage));
  return valid;
}

// ─── Consumo del vehículo (puerto de vehicleConsumption de la web) ──────────
//
// Los tramos se CONSTRUYEN por odómetro, pero "reciente" se decide por FECHA.
// Se descartan tramos imposibles (odómetro mal tecleado, dos llenos casi sin
// recorrer) porque uno solo domina el promedio ponderado.

const double minSegmentKm = 10;
const double minPlausibleL100km = 1;
const double maxPlausibleL100km = 100;
const int recentWindowMonths = 6;

class _Segment {
  const _Segment(this.endDate, this.km, this.liters);
  final DateTime? endDate;
  final double km;
  final double liters;

  double get l100km => liters / km * 100;

  bool get isPlausible =>
      km >= minSegmentKm &&
      l100km >= minPlausibleL100km &&
      l100km <= maxPlausibleL100km;
}

class VehicleConsumption {
  const VehicleConsumption({
    this.recent,
    this.historical,
    this.isEstimate = false,
    this.isStale = false,
    this.discarded = 0,
  });

  /// L/100km de los últimos [recentWindowMonths] meses; null sin medición.
  final double? recent;
  final double? historical;
  final bool isEstimate;

  /// Hay histórico pero ninguna medición reciente.
  final bool isStale;

  /// Tramos descartados por imposibles: hay cargas que revisar.
  final int discarded;
}

List<_Segment> _fullToFullSegments(List<ConsumptionEntry> entries) {
  final sorted = _validEntries(entries);
  final segments = <_Segment>[];
  ConsumptionEntry? anchor;
  double liters = 0;

  for (final entry in sorted) {
    if (anchor != null) liters += entry.liters;
    if (!entry.isTankFull) continue;
    if (anchor != null) {
      final km = entry.mileage - anchor.mileage;
      if (km > 0) segments.add(_Segment(entry.date, km, liters));
    }
    anchor = entry;
    liters = 0;
  }
  return segments;
}

double? _weightedAvg(Iterable<_Segment> segments) {
  final km = segments.fold(0.0, (s, e) => s + e.km);
  final liters = segments.fold(0.0, (s, e) => s + e.liters);
  return km > 0 && liters > 0 ? liters / km * 100 : null;
}

double? _aggregateOver(List<ConsumptionEntry> entries) {
  final sorted = _validEntries(entries);
  if (sorted.length < 2) return null;
  final km = sorted.last.mileage - sorted.first.mileage;
  final liters = sorted.skip(1).fold(0.0, (s, e) => s + e.liters);
  if (km <= 0 || liters <= 0) return null;
  final avg = liters / km * 100;
  if (avg < minPlausibleL100km || avg > maxPlausibleL100km) return null;
  return avg;
}

/// Único cálculo de "cuánto consume" el vehículo; mismo resultado que la web.
VehicleConsumption vehicleConsumption(
  List<ConsumptionEntry> entries, {
  DateTime? now,
}) {
  now ??= DateTime.now();
  final cutoff = DateTime(now.year, now.month - recentWindowMonths, now.day,
      now.hour, now.minute, now.second);

  final all = _fullToFullSegments(entries);
  final plausible = all.where((s) => s.isPlausible).toList();
  final discarded = all.length - plausible.length;
  final dated = plausible.where((s) => s.endDate != null).toList();
  final historical = _weightedAvg(plausible);

  final window = dated.where((s) => !s.endDate!.isBefore(cutoff));
  if (window.isNotEmpty) {
    return VehicleConsumption(
      recent: _weightedAvg(window),
      historical: historical,
      discarded: discarded,
    );
  }

  // Sin tramos llenos recientes (p. ej. siempre reposta parcial): agregado
  // sobre las cargas recientes.
  final windowAgg = _aggregateOver(entries
      .where((e) => e.date != null && !e.date!.isBefore(cutoff))
      .toList());
  if (windowAgg != null) {
    return VehicleConsumption(
      recent: windowAgg,
      historical: historical,
      isEstimate: true,
      discarded: discarded,
    );
  }

  if (dated.isNotEmpty) {
    return VehicleConsumption(
      historical: historical,
      isStale: true,
      discarded: discarded,
    );
  }

  if (plausible.isNotEmpty) {
    return VehicleConsumption(
      recent: historical,
      historical: historical,
      discarded: discarded,
    );
  }

  final agg = _aggregateOver(entries);
  return VehicleConsumption(
    recent: agg,
    historical: agg,
    isEstimate: agg != null,
    discarded: discarded,
  );
}
