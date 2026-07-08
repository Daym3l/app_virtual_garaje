import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_theme.dart';
import '../models/vehicle.dart';
import '../services/fuel_service.dart';
import '../services/odometer_service.dart';
import '../services/suggestions_service.dart';
import '../widgets/autocomplete_field.dart';

class FuelScreen extends StatefulWidget {
  const FuelScreen({super.key, required this.vehicle, required this.onRegisterFab});
  final Vehicle vehicle;
  final void Function(VoidCallback) onRegisterFab;

  @override
  State<FuelScreen> createState() => _FuelScreenState();
}

class _FuelScreenState extends State<FuelScreen> {
  List<FuelLog> _fuelLogs = [];
  List<EnergyLog> _energyLogs = [];
  bool _loading = true;

  bool get _isElectric => widget.vehicle.isElectric;

  @override
  void initState() {
    super.initState();
    _load();
    widget.onRegisterFab(_openForm);
  }

  @override
  void didUpdateWidget(FuelScreen old) {
    super.didUpdateWidget(old);
    if (old.vehicle.id != widget.vehicle.id) { _load(); widget.onRegisterFab(_openForm); }
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    if (_isElectric) {
      final logs = await FuelService.fetchEnergyLogs(widget.vehicle.id);
      if (mounted) setState(() { _energyLogs = logs; _loading = false; });
    } else {
      final logs = await FuelService.fetchFuelLogs(widget.vehicle.id);
      if (mounted) setState(() { _fuelLogs = logs; _loading = false; });
    }
  }

  void _openForm() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _isElectric
          ? _EnergyForm(vehicle: widget.vehicle, onSaved: () { Navigator.pop(context); _load(); })
          : _FuelForm(vehicle: widget.vehicle, onSaved: () { Navigator.pop(context); _load(); }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final accentColor = _isElectric ? AppColors.success : AppColors.warning;
    final logs = _isElectric ? _energyLogs.length : _fuelLogs.length;

    return RefreshIndicator(
      color: AppColors.accent,
      backgroundColor: AppColors.card,
      onRefresh: _load,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(
            child: _FuelHeader(
              vehicle: widget.vehicle,
              fuelLogs: _fuelLogs,
              energyLogs: _energyLogs,
              accentColor: accentColor,
            ),
          ),
          if (_loading)
            const SliverFillRemaining(
              child: Center(child: CircularProgressIndicator(color: AppColors.accent, strokeWidth: 2)),
            )
          else if (logs == 0)
            SliverFillRemaining(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(_isElectric ? Icons.bolt_outlined : Icons.local_gas_station_outlined,
                        size: 48, color: AppColors.textTertiary),
                    const SizedBox(height: 12),
                    Text(
                      _isElectric ? 'Sin registros de carga' : 'Sin registros de combustible',
                      style: GoogleFonts.inter(fontSize: 14, color: AppColors.textTertiary),
                    ),
                  ],
                ),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
              sliver: SliverList(
                delegate: _isElectric
                    ? SliverChildBuilderDelegate(
                        (_, i) => _EnergyCard(log: _energyLogs[i]),
                        childCount: _energyLogs.length,
                      )
                    : SliverChildBuilderDelegate(
                        (_, i) => _FuelCard(log: _fuelLogs[i]),
                        childCount: _fuelLogs.length,
                      ),
              ),
            ),
        ],
      ),
    );
  }
}

class _FuelHeader extends StatelessWidget {
  const _FuelHeader({
    required this.vehicle,
    required this.fuelLogs,
    required this.energyLogs,
    required this.accentColor,
  });
  final Vehicle vehicle;
  final List<FuelLog> fuelLogs;
  final List<EnergyLog> energyLogs;
  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    final isElectric = vehicle.isElectric;
    String totalStr = '—';
    String costStr = '—';
    String avgStr = '—';

    if (isElectric && energyLogs.isNotEmpty) {
      final totalEnergy = energyLogs.fold(0.0, (s, l) => s + l.energyAdded);
      totalStr = '${totalEnergy.toStringAsFixed(1)} kWh';
      costStr = '${energyLogs.length} cargas';
    } else if (!isElectric && fuelLogs.isNotEmpty) {
      final totalL = fuelLogs.fold(0.0, (s, l) => s + l.liters);
      final totalCost = fuelLogs.fold(0.0, (s, l) => s + l.cost);
      final withConsumption = fuelLogs.where((l) => l.consumption != null).toList();
      totalStr = '${totalL.toStringAsFixed(1)} L';
      costStr = '\$${totalCost.toStringAsFixed(2)}';
      if (withConsumption.isNotEmpty) {
        final avg = withConsumption.fold(0.0, (s, l) => s + l.consumption!) / withConsumption.length;
        avgStr = '${avg.toStringAsFixed(1)} L/100km';
      }
    }

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.borderSubtle),
      ),
      child: Row(
        children: [
          Expanded(child: _Cell(label: isElectric ? 'TOTAL CARGADO' : 'TOTAL COMB.', value: totalStr, color: accentColor)),
          Container(width: 1, height: 40, color: AppColors.borderSubtle),
          Expanded(child: _Cell(label: isElectric ? 'SESIONES' : 'GASTO TOTAL', value: costStr, color: AppColors.textSecondary)),
          if (!isElectric) ...[
            Container(width: 1, height: 40, color: AppColors.borderSubtle),
            Expanded(child: _Cell(label: 'EFICIENCIA', value: avgStr, color: AppColors.textSecondary)),
          ],
        ],
      ),
    );
  }
}

class _Cell extends StatelessWidget {
  const _Cell({required this.label, required this.value, required this.color});
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(label, style: GoogleFonts.jetBrainsMono(fontSize: 8, color: AppColors.textTertiary, letterSpacing: 0.8), textAlign: TextAlign.center),
        const SizedBox(height: 4),
        Text(value, style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w700, color: color), textAlign: TextAlign.center),
      ],
    );
  }
}

void _showFuelDetail(BuildContext context, FuelLog log) {
  showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (_) => _DetailSheet(
      icon: Icons.local_gas_station_outlined,
      iconColor: AppColors.warning,
      title: '${log.liters.toStringAsFixed(2)} L',
      subtitle: _fmtDate(log.date),
      rows: [
        _DetailRow('Costo', '\$${log.cost.toStringAsFixed(2)}'),
        _DetailRow('Precio/L', log.costPerLiter != null ? '\$${log.costPerLiter!.toStringAsFixed(3)}/L' : '—'),
        _DetailRow('Odómetro', '${log.mileage.toStringAsFixed(0)} km'),
        if (log.consumption != null) _DetailRow('Consumo', '${log.consumption!.toStringAsFixed(1)} L/100km'),
        if (log.station?.isNotEmpty == true) _DetailRow('Estación', log.station!),
        _DetailRow('Tanque lleno', log.isTankFull ? 'Sí' : 'No'),
      ],
    ),
  );
}

void _showEnergyDetail(BuildContext context, EnergyLog log) {
  showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (_) => _DetailSheet(
      icon: Icons.bolt_outlined,
      iconColor: AppColors.success,
      title: '${log.energyAdded.toStringAsFixed(1)} kWh',
      subtitle: _fmtDate(log.date),
      rows: [
        _DetailRow('Odómetro', '${log.odometer.toStringAsFixed(0)} km'),
        _DetailRow('Nivel inicial', '${log.initialLevel.toStringAsFixed(0)}%'),
        _DetailRow('Nivel final', '${log.finalLevel.toStringAsFixed(0)}%'),
        _DetailRow('Energía añadida', '${log.energyAdded.toStringAsFixed(1)} kWh'),
        if (log.connectorType?.isNotEmpty == true) _DetailRow('Conector', log.connectorType!),
        if (log.location?.isNotEmpty == true) _DetailRow('Ubicación', log.location!),
      ],
    ),
  );
}

String _fmtDate(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

class _FuelCard extends StatelessWidget {
  const _FuelCard({required this.log});
  final FuelLog log;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => _showFuelDetail(context, log),
      child: Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.borderSubtle),
      ),
      child: Row(
        children: [
          Container(
            width: 38, height: 38,
            decoration: BoxDecoration(
              color: AppColors.warning.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.local_gas_station_outlined, size: 18, color: AppColors.warning),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${log.liters.toStringAsFixed(2)} L',
                  style: GoogleFonts.jetBrainsMono(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                ),
                Text(
                  '${log.mileage.toStringAsFixed(0)} km${log.station?.isNotEmpty == true ? ' · ${log.station}' : ''}',
                  style: GoogleFonts.inter(fontSize: 11, color: AppColors.textTertiary),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('\$${log.cost.toStringAsFixed(2)}', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
              Text(_dateStr(log.date), style: GoogleFonts.inter(fontSize: 11, color: AppColors.textTertiary)),
              if (log.consumption != null)
                Text('${log.consumption!.toStringAsFixed(1)} L/100km', style: GoogleFonts.jetBrainsMono(fontSize: 9, color: AppColors.accent)),
            ],
          ),
        ],
      ),
    ),   // Container
    );   // GestureDetector
  }

  String _dateStr(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
}

class _EnergyCard extends StatelessWidget {
  const _EnergyCard({required this.log});
  final EnergyLog log;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => _showEnergyDetail(context, log),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.borderSubtle),
        ),
        child: Row(
          children: [
            Container(
              width: 38, height: 38,
              decoration: BoxDecoration(
                color: AppColors.success.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.bolt_outlined, size: 18, color: AppColors.success),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${log.energyAdded.toStringAsFixed(1)} kWh',
                    style: GoogleFonts.jetBrainsMono(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                  ),
                  Text(
                    '${log.initialLevel.toStringAsFixed(0)}% → ${log.finalLevel.toStringAsFixed(0)}%${log.location?.isNotEmpty == true ? ' · ${log.location}' : ''}',
                    style: GoogleFonts.inter(fontSize: 11, color: AppColors.textTertiary),
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text('${log.odometer.toStringAsFixed(0)} km', style: GoogleFonts.inter(fontSize: 12, color: AppColors.textPrimary)),
                Text(_dateStr(log.date), style: GoogleFonts.inter(fontSize: 11, color: AppColors.textTertiary)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _dateStr(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
}

// ── Detail sheet ──────────────────────────────────────────────────────────────

class _DetailRow {
  const _DetailRow(this.label, this.value);
  final String label;
  final String value;
}

class _DetailSheet extends StatelessWidget {
  const _DetailSheet({required this.icon, required this.iconColor, required this.title, required this.subtitle, required this.rows});
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final List<_DetailRow> rows;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: AppColors.borderSubtle, borderRadius: BorderRadius.circular(2)))),
          const SizedBox(height: 20),
          Row(
            children: [
              Container(
                width: 44, height: 44,
                decoration: BoxDecoration(color: iconColor.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
                child: Icon(icon, size: 22, color: iconColor),
              ),
              const SizedBox(width: 14),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: GoogleFonts.jetBrainsMono(fontSize: 20, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                  Text(subtitle, style: GoogleFonts.inter(fontSize: 12, color: AppColors.textTertiary)),
                ],
              ),
            ],
          ),
          const SizedBox(height: 20),
          Container(
            decoration: BoxDecoration(color: AppColors.card, borderRadius: BorderRadius.circular(10), border: Border.all(color: AppColors.borderSubtle)),
            child: Column(
              children: rows.asMap().entries.map((e) {
                final isLast = e.key == rows.length - 1;
                return Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(e.value.label, style: GoogleFonts.inter(fontSize: 13, color: AppColors.textTertiary)),
                          Text(e.value.value, style: GoogleFonts.jetBrainsMono(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                        ],
                      ),
                    ),
                    if (!isLast) Divider(height: 1, color: AppColors.borderSubtle),
                  ],
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Forms ─────────────────────────────────────────────────────────────────────

class _FuelForm extends StatefulWidget {
  const _FuelForm({required this.vehicle, required this.onSaved});
  final Vehicle vehicle;
  final VoidCallback onSaved;

  @override
  State<_FuelForm> createState() => _FuelFormState();
}

class _FuelFormState extends State<_FuelForm> {
  final _litersCtrl = TextEditingController();
  final _costCtrl = TextEditingController();
  final _kmCtrl = TextEditingController();
  final _stationCtrl = TextEditingController();
  DateTime _date = DateTime.now();
  bool _isTankFull = true;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _litersCtrl.dispose(); _costCtrl.dispose();
    _kmCtrl.dispose(); _stationCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
      builder: (ctx, child) => Theme(
        data: ThemeData.dark().copyWith(
          colorScheme: const ColorScheme.dark(primary: AppColors.accent, surface: AppColors.card),
        ),
        child: child!,
      ),
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _save() async {
    final liters = double.tryParse(_litersCtrl.text.replaceAll(',', '.'));
    final cost = double.tryParse(_costCtrl.text.replaceAll(',', '.'));
    final km = double.tryParse(_kmCtrl.text.replaceAll(',', '.'));
    if (liters == null || liters <= 0) { setState(() => _error = 'Ingresa litros válidos'); return; }
    if (cost == null || cost < 0) { setState(() => _error = 'Ingresa costo válido'); return; }
    if (km == null || km <= 0) { setState(() => _error = 'Ingresa kilometraje válido'); return; }
    setState(() { _saving = true; _error = null; });
    final odoError = await OdometerService.validate(
      vehicleId: widget.vehicle.id,
      date: _date,
      valueKm: km,
      excludeSource: 'fuel',
    );
    if (odoError != null) {
      if (mounted) setState(() { _saving = false; _error = odoError; });
      return;
    }
    try {
      await FuelService.addFuelLog(
        vehicleId: widget.vehicle.id,
        date: _date,
        liters: liters,
        cost: cost,
        mileage: km,
        station: _stationCtrl.text.trim(),
        isTankFull: _isTankFull,
      );
      if (_stationCtrl.text.trim().isNotEmpty) SuggestionsService.invalidate('station');
      widget.onSaved();
    } catch (e) {
      if (mounted) setState(() { _saving = false; _error = 'Error al guardar: $e'; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    final accentColor = widget.vehicle.fuelType == FuelType.diesel ? AppColors.warning : AppColors.accent;
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: EdgeInsets.fromLTRB(16, 20, 16, 24 + bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: AppColors.borderSubtle, borderRadius: BorderRadius.circular(2)))),
            const SizedBox(height: 20),
            Text('Registrar Repostaje', style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
            const SizedBox(height: 20),
            Text('FECHA DE REPOSTAJE', style: GoogleFonts.jetBrainsMono(fontSize: 10, color: AppColors.textTertiary, letterSpacing: 0.8)),
            const SizedBox(height: 6),
            GestureDetector(
              onTap: _pickDate,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: AppColors.card,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.accent.withValues(alpha: 0.4)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.calendar_today_outlined, size: 16, color: AppColors.accent),
                    const SizedBox(width: 10),
                    Text(
                      '${_date.day.toString().padLeft(2, '0')}/${_date.month.toString().padLeft(2, '0')}/${_date.year}',
                      style: GoogleFonts.inter(fontSize: 14, color: AppColors.textPrimary),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(child: _FormField(label: 'LITROS', controller: _litersCtrl, hint: '0.00', keyboardType: const TextInputType.numberWithOptions(decimal: true), inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[\d,.]'))])),
                const SizedBox(width: 12),
                Expanded(child: _FormField(label: 'COSTO (\$)', controller: _costCtrl, hint: '0.00', keyboardType: const TextInputType.numberWithOptions(decimal: true), inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[\d,.]'))])),
              ],
            ),
            const SizedBox(height: 12),
            _FormField(label: 'ODÓMETRO (KM)', controller: _kmCtrl, hint: widget.vehicle.km.toStringAsFixed(0), keyboardType: const TextInputType.numberWithOptions(decimal: true), inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[\d,.]'))]),
            const SizedBox(height: 12),
            AutocompleteField(label: 'ESTACIÓN (OPCIONAL)', controller: _stationCtrl, hint: 'Ej: Cupet, Shell...', kind: 'station'),
            const SizedBox(height: 12),
            GestureDetector(
              onTap: () => setState(() => _isTankFull = !_isTankFull),
              child: Row(
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    width: 20, height: 20,
                    decoration: BoxDecoration(
                      color: _isTankFull ? accentColor : Colors.transparent,
                      border: Border.all(color: _isTankFull ? accentColor : AppColors.borderSubtle),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: _isTankFull ? const Icon(Icons.check, size: 14, color: AppColors.background) : null,
                  ),
                  const SizedBox(width: 10),
                  Text('Tanque lleno', style: GoogleFonts.inter(fontSize: 13, color: AppColors.textSecondary)),
                ],
              ),
            ),
            if (_error != null) ...[const SizedBox(height: 10), Text(_error!, style: GoogleFonts.inter(fontSize: 12, color: AppColors.danger))],
            const SizedBox(height: 20),
            _SaveButton(saving: _saving, label: 'Guardar repostaje', onTap: _save),
          ],
        ),
      ),
    );
  }
}

class _EnergyForm extends StatefulWidget {
  const _EnergyForm({required this.vehicle, required this.onSaved});
  final Vehicle vehicle;
  final VoidCallback onSaved;

  @override
  State<_EnergyForm> createState() => _EnergyFormState();
}

class _EnergyFormState extends State<_EnergyForm> {
  final _kmCtrl = TextEditingController();
  final _initialCtrl = TextEditingController();
  final _finalCtrl = TextEditingController();
  final _energyCtrl = TextEditingController();
  final _locationCtrl = TextEditingController();
  DateTime _date = DateTime.now();
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _initialCtrl.addListener(_recalcEnergy);
    _finalCtrl.addListener(_recalcEnergy);
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
      builder: (ctx, child) => Theme(
        data: ThemeData.dark().copyWith(
          colorScheme: const ColorScheme.dark(primary: AppColors.accent, surface: AppColors.card),
        ),
        child: child!,
      ),
    );
    if (picked != null) setState(() => _date = picked);
  }

  void _recalcEnergy() {
    final initial = double.tryParse(_initialCtrl.text.replaceAll(',', '.'));
    final finalLevel = double.tryParse(_finalCtrl.text.replaceAll(',', '.'));
    if (initial != null && finalLevel != null && finalLevel > initial) {
      final capacity = widget.vehicle.batteryCapacity ?? 0;
      if (capacity > 0) {
        final kwh = (finalLevel - initial) / 100 * capacity;
        _energyCtrl.text = kwh.toStringAsFixed(1);
      }
    }
  }

  @override
  void dispose() {
    _kmCtrl.dispose(); _initialCtrl.dispose();
    _finalCtrl.dispose(); _energyCtrl.dispose();
    _locationCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final km = double.tryParse(_kmCtrl.text.replaceAll(',', '.'));
    final initial = double.tryParse(_initialCtrl.text.replaceAll(',', '.'));
    final finalLevel = double.tryParse(_finalCtrl.text.replaceAll(',', '.'));
    final energy = double.tryParse(_energyCtrl.text.replaceAll(',', '.'));
    if (km == null || km <= 0) { setState(() => _error = 'Ingresa kilometraje válido'); return; }
    if (initial == null) { setState(() => _error = 'Ingresa nivel inicial'); return; }
    if (finalLevel == null) { setState(() => _error = 'Ingresa nivel final'); return; }
    if (finalLevel <= initial) { setState(() => _error = 'Nivel final debe ser mayor al inicial'); return; }
    final energyValue = energy ?? ((finalLevel - initial) / 100 * (widget.vehicle.batteryCapacity ?? 0));
    if (energyValue <= 0) { setState(() => _error = 'Ingresa la energía añadida'); return; }
    setState(() { _saving = true; _error = null; });
    final odoError = await OdometerService.validate(
      vehicleId: widget.vehicle.id,
      date: _date,
      valueKm: km,
      excludeSource: 'energy',
    );
    if (odoError != null) {
      if (mounted) setState(() { _saving = false; _error = odoError; });
      return;
    }
    try {
      await FuelService.addEnergyLog(
        vehicleId: widget.vehicle.id,
        date: _date,
        odometer: km,
        initialLevel: initial,
        finalLevel: finalLevel,
        energyAdded: energyValue,
        location: _locationCtrl.text.trim(),
      );
      if (_locationCtrl.text.trim().isNotEmpty) SuggestionsService.invalidate('location');
      widget.onSaved();
    } catch (e) {
      if (mounted) setState(() { _saving = false; _error = 'Error al guardar: $e'; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: EdgeInsets.fromLTRB(16, 20, 16, 24 + bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: AppColors.borderSubtle, borderRadius: BorderRadius.circular(2)))),
            const SizedBox(height: 20),
            Text('Registrar Carga', style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
            const SizedBox(height: 20),
            Text('FECHA DE CARGA', style: GoogleFonts.jetBrainsMono(fontSize: 10, color: AppColors.textTertiary, letterSpacing: 0.8)),
            const SizedBox(height: 6),
            GestureDetector(
              onTap: _pickDate,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: AppColors.card,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.accent.withValues(alpha: 0.4)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.calendar_today_outlined, size: 16, color: AppColors.accent),
                    const SizedBox(width: 10),
                    Text(
                      '${_date.day.toString().padLeft(2, '0')}/${_date.month.toString().padLeft(2, '0')}/${_date.year}',
                      style: GoogleFonts.inter(fontSize: 14, color: AppColors.textPrimary),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            _FormField(label: 'ODÓMETRO (KM)', controller: _kmCtrl, hint: widget.vehicle.km.toStringAsFixed(0), keyboardType: const TextInputType.numberWithOptions(decimal: true), inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[\d,.]'))]),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(child: _FormField(label: 'NIVEL INICIAL (%)', controller: _initialCtrl, hint: '20', keyboardType: TextInputType.number, inputFormatters: [FilteringTextInputFormatter.digitsOnly])),
                const SizedBox(width: 12),
                Expanded(child: _FormField(label: 'NIVEL FINAL (%)', controller: _finalCtrl, hint: '100', keyboardType: TextInputType.number, inputFormatters: [FilteringTextInputFormatter.digitsOnly])),
              ],
            ),
            const SizedBox(height: 12),
            _FormField(
              label: (widget.vehicle.batteryCapacity ?? 0) > 0 ? 'ENERGÍA AÑADIDA (kWh) — AUTO' : 'ENERGÍA AÑADIDA (kWh)',
              controller: _energyCtrl,
              hint: '0.0',
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[\d,.]'))],
              readOnly: (widget.vehicle.batteryCapacity ?? 0) > 0,
            ),
            const SizedBox(height: 12),
            AutocompleteField(label: 'UBICACIÓN (OPCIONAL)', controller: _locationCtrl, hint: 'Ej: Cargador casa, Mall...', kind: 'location'),
            if (_error != null) ...[const SizedBox(height: 10), Text(_error!, style: GoogleFonts.inter(fontSize: 12, color: AppColors.danger))],
            const SizedBox(height: 20),
            _SaveButton(saving: _saving, label: 'Guardar carga', onTap: _save),
          ],
        ),
      ),
    );
  }
}

// ── Shared ────────────────────────────────────────────────────────────────────

class _FormField extends StatelessWidget {
  const _FormField({required this.label, required this.controller, required this.hint, this.keyboardType, this.inputFormatters, this.readOnly = false});
  final String label;
  final TextEditingController controller;
  final String hint;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;
  final bool readOnly;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: GoogleFonts.jetBrainsMono(fontSize: 10, color: AppColors.textTertiary, letterSpacing: 0.8)),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          readOnly: readOnly,
          keyboardType: keyboardType ?? TextInputType.text,
          inputFormatters: inputFormatters,
          style: GoogleFonts.inter(fontSize: 14, color: readOnly ? AppColors.textSecondary : AppColors.textPrimary),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: GoogleFonts.inter(fontSize: 14, color: AppColors.textTertiary),
            filled: true,
            fillColor: AppColors.card,
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppColors.borderSubtle)),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppColors.borderSubtle)),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppColors.accent)),
          ),
        ),
      ],
    );
  }
}

class _SaveButton extends StatelessWidget {
  const _SaveButton({required this.saving, required this.label, required this.onTap});
  final bool saving;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: saving ? null : onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: saving ? AppColors.accent.withValues(alpha: 0.5) : AppColors.accent,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Center(
          child: saving
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: AppColors.background, strokeWidth: 2))
              : Text(label, style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.background)),
        ),
      ),
    );
  }
}
