import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_theme.dart';
import '../models/vehicle.dart';
import '../services/maintenance_service.dart';

class MaintenanceScreen extends StatefulWidget {
  const MaintenanceScreen({super.key, required this.vehicle, required this.onRegisterFab});
  final Vehicle vehicle;
  final void Function(VoidCallback) onRegisterFab;

  @override
  State<MaintenanceScreen> createState() => _MaintenanceScreenState();
}

class _MaintenanceScreenState extends State<MaintenanceScreen> {
  List<MaintenanceRecord> _records = [];
  bool _loading = true;
  String _filter = 'todos'; // todos | pendientes | completados

  @override
  void initState() {
    super.initState();
    _load();
    widget.onRegisterFab(_openForm);
  }

  @override
  void didUpdateWidget(MaintenanceScreen old) {
    super.didUpdateWidget(old);
    if (old.vehicle.id != widget.vehicle.id) { _load(); widget.onRegisterFab(_openForm); }
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final records = await MaintenanceService.fetchRecords(widget.vehicle.id);
    if (mounted) setState(() { _records = records; _loading = false; });
  }

  List<MaintenanceRecord> get _filtered {
    switch (_filter) {
      case 'pendientes': return _records.where((r) => !r.isCompleted).toList();
      case 'completados': return _records.where((r) => r.isCompleted).toList();
      default: return _records;
    }
  }

  void _openForm() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _MaintenanceForm(
        vehicle: widget.vehicle,
        onSaved: () { Navigator.pop(context); _load(); },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      color: AppColors.accent,
      backgroundColor: AppColors.card,
      onRefresh: _load,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(child: _MaintenanceHeader(records: _records)),
          SliverToBoxAdapter(child: _FilterTabs(active: _filter, onChanged: (f) => setState(() => _filter = f))),
          if (_loading)
            const SliverFillRemaining(
              child: Center(child: CircularProgressIndicator(color: AppColors.accent, strokeWidth: 2)),
            )
          else if (_filtered.isEmpty)
            SliverFillRemaining(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.build_outlined, size: 48, color: AppColors.textTertiary),
                    const SizedBox(height: 12),
                    Text('Sin registros', style: GoogleFonts.inter(fontSize: 14, color: AppColors.textTertiary)),
                  ],
                ),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (_, i) => _RecordCard(
                    record: _filtered[i],
                    vehicle: widget.vehicle,
                    onComplete: () async {
                      await MaintenanceService.markCompleted(_filtered[i].id);
                      _load();
                    },
                  ),
                  childCount: _filtered.length,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _MaintenanceHeader extends StatelessWidget {
  const _MaintenanceHeader({required this.records});
  final List<MaintenanceRecord> records;

  @override
  Widget build(BuildContext context) {
    final pending = records.where((r) => !r.isCompleted).length;
    final urgent = records.where((r) => r.isUrgent && !r.isCompleted).length;
    final completed = records.where((r) => r.isCompleted).length;

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
          Expanded(child: _Cell(label: 'PENDIENTES', value: '$pending', color: pending > 0 ? AppColors.warning : AppColors.success)),
          Container(width: 1, height: 40, color: AppColors.borderSubtle),
          Expanded(child: _Cell(label: 'URGENTES', value: '$urgent', color: urgent > 0 ? AppColors.danger : AppColors.textTertiary)),
          Container(width: 1, height: 40, color: AppColors.borderSubtle),
          Expanded(child: _Cell(label: 'COMPLETADOS', value: '$completed', color: AppColors.textSecondary)),
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
        Text(label, style: GoogleFonts.jetBrainsMono(fontSize: 8, color: AppColors.textTertiary, letterSpacing: 0.8)),
        const SizedBox(height: 4),
        Text(value, style: GoogleFonts.jetBrainsMono(fontSize: 22, fontWeight: FontWeight.w700, color: color)),
      ],
    );
  }
}

class _FilterTabs extends StatelessWidget {
  const _FilterTabs({required this.active, required this.onChanged});
  final String active;
  final ValueChanged<String> onChanged;

  static const _tabs = [('todos', 'Todos'), ('pendientes', 'Pendientes'), ('completados', 'Completados')];

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Row(
        children: _tabs.map((t) {
          final isActive = t.$1 == active;
          return GestureDetector(
            onTap: () => onChanged(t.$1),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: isActive ? AppColors.accent.withValues(alpha: 0.15) : AppColors.card,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: isActive ? AppColors.accent.withValues(alpha: 0.4) : AppColors.borderSubtle),
              ),
              child: Text(
                t.$2,
                style: GoogleFonts.inter(
                  fontSize: 12,
                  fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
                  color: isActive ? AppColors.accent : AppColors.textTertiary,
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _DetailRow {
  const _DetailRow(this.label, this.value);
  final String label;
  final String value;
}

class _DetailSheet extends StatelessWidget {
  const _DetailSheet({required this.icon, required this.iconColor, required this.title, required this.subtitle, required this.rows, this.isCompleted = false, this.isUrgent = false});
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final List<_DetailRow> rows;
  final bool isCompleted;
  final bool isUrgent;

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
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(child: Text(title, style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.textPrimary))),
                        if (isUrgent) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(color: AppColors.danger.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(20)),
                            child: Text('URGENTE', style: GoogleFonts.jetBrainsMono(fontSize: 8, fontWeight: FontWeight.w700, color: AppColors.danger)),
                          ),
                        ],
                      ],
                    ),
                    Text(subtitle, style: GoogleFonts.inter(fontSize: 12, color: AppColors.textTertiary)),
                  ],
                ),
              ),
            ],
          ),
          if (rows.isNotEmpty) ...[
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
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(e.value.label, style: GoogleFonts.inter(fontSize: 13, color: AppColors.textTertiary)),
                            const SizedBox(width: 16),
                            Flexible(child: Text(e.value.value, textAlign: TextAlign.end, style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary))),
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
        ],
      ),
    );
  }
}

class _RecordCard extends StatelessWidget {
  const _RecordCard({required this.record, required this.vehicle, required this.onComplete});
  final MaintenanceRecord record;
  final Vehicle vehicle;
  final VoidCallback onComplete;

  Color get _statusColor {
    if (record.isCompleted) return AppColors.success;
    if (record.isUrgent) return AppColors.danger;
    if (record.nextDate != null && record.nextDate!.isBefore(DateTime.now().add(const Duration(days: 7)))) return AppColors.warning;
    if (record.nextMileage != null && (record.nextMileage! - vehicle.km) <= 500) return AppColors.warning;
    return AppColors.accent;
  }

  String get _typeLabel => kMaintenanceTypeLabels[record.type] ?? record.type;

  String _dateStr(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  void _showDetail(BuildContext context) {
    final catLabel = kServiceCategoryLabels[record.serviceCategory] ?? record.serviceCategory;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _DetailSheet(
        icon: Icons.build_outlined,
        iconColor: _statusColor,
        title: _typeLabel,
        subtitle: _dateStr(record.date),
        isCompleted: record.isCompleted,
        isUrgent: record.isUrgent,
        rows: [
          if (record.description.isNotEmpty) _DetailRow('Descripción', record.description),
          _DetailRow('Categoría', catLabel),
          _DetailRow('Odómetro', '${record.mileage.toStringAsFixed(0)} km'),
          if (record.cost > 0) _DetailRow('Costo', '\$${record.cost.toStringAsFixed(2)}'),
          if (record.nextMileage != null) _DetailRow('Próx. km', '${record.nextMileage!.toStringAsFixed(0)} km'),
          if (record.nextDate != null) _DetailRow('Próx. fecha', _dateStr(record.nextDate!)),
          if (record.performedBy != null && record.performedBy!.isNotEmpty) _DetailRow('Taller', record.performedBy!),
          if (record.parts != null && record.parts!.isNotEmpty) _DetailRow('Piezas', record.parts!),
          if (record.warrantyUntil != null) _DetailRow('Garantía hasta', _dateStr(record.warrantyUntil!)),
          _DetailRow('Estado', record.isCompleted ? 'Completado' : 'Pendiente'),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final color = _statusColor;
    return GestureDetector(
      onTap: () => _showDetail(context),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.borderSubtle),
        ),
        child: Row(
          children: [
            Container(
              width: 4,
              height: 72,
              decoration: BoxDecoration(
                color: color,
                borderRadius: const BorderRadius.only(topLeft: Radius.circular(10), bottomLeft: Radius.circular(10)),
              ),
            ),
            const SizedBox(width: 12),
            Container(
              width: 36, height: 36,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(Icons.build_outlined, size: 17, color: color),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(_typeLabel, style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                        if (record.isUrgent && !record.isCompleted) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(color: AppColors.danger.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(20)),
                            child: Text('URGENTE', style: GoogleFonts.jetBrainsMono(fontSize: 8, fontWeight: FontWeight.w700, color: AppColors.danger)),
                          ),
                        ],
                      ],
                    ),
                    if (record.description.isNotEmpty)
                      Text(record.description, style: GoogleFonts.inter(fontSize: 11, color: AppColors.textTertiary), maxLines: 1, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Text(_dateStr(record.date), style: GoogleFonts.inter(fontSize: 10, color: AppColors.textTertiary)),
                        if (record.nextDate != null) ...[
                          Text(' · próx: ${_dateStr(record.nextDate!)}', style: GoogleFonts.inter(fontSize: 10, color: AppColors.textTertiary)),
                        ] else if (record.nextMileage != null) ...[
                          Text(' · próx: ${record.nextMileage!.toStringAsFixed(0)} km', style: GoogleFonts.inter(fontSize: 10, color: AppColors.textTertiary)),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ),
            if (!record.isCompleted)
              GestureDetector(
                onTap: onComplete,
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Icon(Icons.check_circle_outline, size: 22, color: AppColors.success.withValues(alpha: 0.7)),
                ),
              )
            else
              const Padding(
                padding: EdgeInsets.all(14),
                child: Icon(Icons.check_circle, size: 22, color: AppColors.success),
              ),
          ],
        ),
      ),
    );
  }
}

// ── Form ──────────────────────────────────────────────────────────────────────

class _MaintenanceForm extends StatefulWidget {
  const _MaintenanceForm({required this.vehicle, required this.onSaved});
  final Vehicle vehicle;
  final VoidCallback onSaved;

  @override
  State<_MaintenanceForm> createState() => _MaintenanceFormState();
}

class _MaintenanceFormState extends State<_MaintenanceForm> {
  String _type = kMaintenanceTypes.first;
  String _category = kServiceCategories.first; // ignore: prefer_final_fields
  DateTime _date = DateTime.now();
  final _descCtrl = TextEditingController();
  final _kmCtrl = TextEditingController();
  final _costCtrl = TextEditingController();
  final _intervalKmCtrl = TextEditingController();
  final _intervalDaysCtrl = TextEditingController();
  final _performedByCtrl = TextEditingController();
  final _partsCtrl = TextEditingController();
  DateTime? _warrantyDate;
  bool _provenanceOpen = false;
  bool _isCompleted = true;
  bool _isUrgent = false;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _applyIntervalDefaults(_type);
  }

  void _applyIntervalDefaults(String type) {
    final d = defaultInterval(type);
    _intervalKmCtrl.text = d.km != null ? d.km!.toStringAsFixed(0) : '';
    _intervalDaysCtrl.text = d.days != null ? d.days.toString() : '';
  }

  @override
  void dispose() {
    _descCtrl.dispose(); _kmCtrl.dispose(); _costCtrl.dispose();
    _intervalKmCtrl.dispose(); _intervalDaysCtrl.dispose();
    _performedByCtrl.dispose(); _partsCtrl.dispose();
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

  Future<void> _pickWarrantyDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _warrantyDate ?? DateTime.now().add(const Duration(days: 365)),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365 * 10)),
      builder: (ctx, child) => Theme(
        data: ThemeData.dark().copyWith(
          colorScheme: const ColorScheme.dark(primary: AppColors.accent, surface: AppColors.card),
        ),
        child: child!,
      ),
    );
    if (picked != null) setState(() => _warrantyDate = picked);
  }

  Future<void> _save() async {
    final km = double.tryParse(_kmCtrl.text.replaceAll(',', '.')) ?? widget.vehicle.km;
    final cost = double.tryParse(_costCtrl.text.replaceAll(',', '.')) ?? 0;
    final intervalKm = _intervalKmCtrl.text.trim().isNotEmpty
        ? double.tryParse(_intervalKmCtrl.text.replaceAll(',', '.'))
        : null;
    final intervalDays = _intervalDaysCtrl.text.trim().isNotEmpty
        ? int.tryParse(_intervalDaysCtrl.text.trim())
        : null;
    final performedBy = _performedByCtrl.text.trim();
    final parts = _partsCtrl.text.trim();
    setState(() { _saving = true; _error = null; });
    try {
      await MaintenanceService.addRecord(
        vehicleId: widget.vehicle.id,
        type: _type,
        description: _descCtrl.text.trim(),
        serviceCategory: _category,
        date: _date,
        mileage: km,
        cost: cost,
        isCompleted: _isCompleted,
        isUrgent: _isUrgent,
        intervalKm: intervalKm,
        intervalDays: intervalDays,
        performedBy: performedBy.isEmpty ? null : performedBy,
        parts: parts.isEmpty ? null : parts,
        warrantyUntil: _warrantyDate,
      );
      widget.onSaved();
    } catch (e) {
      if (mounted) setState(() { _saving = false; _error = 'Error al guardar'; });
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
            Text('Registrar Mantenimiento', style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
            const SizedBox(height: 20),

            // ── Fecha de realización ──
            Text('FECHA DE REALIZACIÓN', style: GoogleFonts.jetBrainsMono(fontSize: 10, color: AppColors.textTertiary, letterSpacing: 0.8)),
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
            const SizedBox(height: 20),

            // ── Datos del servicio ──
            Text('DATOS DEL SERVICIO', style: GoogleFonts.jetBrainsMono(fontSize: 10, color: AppColors.textTertiary, letterSpacing: 0.8)),
            const SizedBox(height: 12),

            // Categoría con subtítulos
            Text('CATEGORÍA', style: GoogleFonts.jetBrainsMono(fontSize: 10, color: AppColors.textTertiary, letterSpacing: 0.8)),
            const SizedBox(height: 8),
            Row(
              children: [
                _CategoryBtn(value: 'preventive', selected: _category, label: 'Preventivo', sub: 'Planificado, periódico', onTap: (v) => setState(() => _category = v)),
                const SizedBox(width: 8),
                _CategoryBtn(value: 'repair', selected: _category, label: 'Reparación', sub: 'Fallo o avería', onTap: (v) => setState(() => _category = v)),
                const SizedBox(width: 8),
                _CategoryBtn(value: 'inspection', selected: _category, label: 'Inspección', sub: 'Diagnóstico, ITV', onTap: (v) => setState(() => _category = v)),
              ],
            ),
            const SizedBox(height: 16),

            // Tipo dropdown
            Text('TIPO DE MANTENIMIENTO', style: GoogleFonts.jetBrainsMono(fontSize: 10, color: AppColors.textTertiary, letterSpacing: 0.8)),
            const SizedBox(height: 6),
            Container(
              decoration: BoxDecoration(
                color: AppColors.card,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.borderSubtle),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _type,
                  isExpanded: true,
                  dropdownColor: AppColors.card,
                  style: GoogleFonts.inter(fontSize: 14, color: AppColors.textPrimary),
                  iconEnabledColor: AppColors.textTertiary,
                  onChanged: (v) { if (v != null) setState(() { _type = v; _applyIntervalDefaults(v); }); },
                  items: kMaintenanceTypes.map((t) => DropdownMenuItem(
                    value: t,
                    child: Text(kMaintenanceTypeLabels[t] ?? t),
                  )).toList(),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Descripción / notas
            _FormField(label: 'DESCRIPCIÓN / NOTAS', controller: _descCtrl, hint: 'Detalles del servicio, taller, observaciones...', maxLines: 3),
            const SizedBox(height: 12),

            // Odómetro + Costo
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _FormField(
                        label: 'ODÓMETRO (KM)',
                        controller: _kmCtrl,
                        hint: widget.vehicle.km.toStringAsFixed(0),
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[\d,.]'))],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          const Icon(Icons.pin_drop_outlined, size: 12, color: AppColors.accent),
                          const SizedBox(width: 4),
                          Text('Actual: ${_fmtKm(widget.vehicle.km)} km', style: GoogleFonts.inter(fontSize: 11, color: AppColors.accent)),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(child: _FormField(label: 'COSTO (\$)', controller: _costCtrl, hint: '0', keyboardType: const TextInputType.numberWithOptions(decimal: true), inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[\d,.]'))])),
              ],
            ),
            const SizedBox(height: 12),

            // ── Repetición / intervalos ──
            Row(
              children: [
                Text('REPETICIÓN', style: GoogleFonts.jetBrainsMono(fontSize: 10, color: AppColors.textTertiary, letterSpacing: 0.8)),
                const SizedBox(width: 8),
                const Icon(Icons.info_outline, size: 12, color: AppColors.textTertiary),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    'El próximo servicio se calcula al completar',
                    style: GoogleFonts.inter(fontSize: 10, color: AppColors.textTertiary),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(child: _FormField(label: 'CADA CUÁNTOS KM', controller: _intervalKmCtrl, hint: '5000', keyboardType: TextInputType.number, inputFormatters: [FilteringTextInputFormatter.digitsOnly])),
                const SizedBox(width: 12),
                Expanded(child: _FormField(label: 'CADA CUÁNTOS DÍAS', controller: _intervalDaysCtrl, hint: '180', keyboardType: TextInputType.number, inputFormatters: [FilteringTextInputFormatter.digitsOnly])),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'Valores sugeridos según el tipo. Ajusta si tu vehículo requiere intervalos distintos.',
              style: GoogleFonts.inter(fontSize: 10, color: AppColors.textTertiary),
            ),
            const SizedBox(height: 20),

            // ── Estado ──
            Text('ESTADO', style: GoogleFonts.jetBrainsMono(fontSize: 10, color: AppColors.textTertiary, letterSpacing: 0.8)),
            const SizedBox(height: 8),
            Container(
              decoration: BoxDecoration(color: AppColors.card, borderRadius: BorderRadius.circular(10), border: Border.all(color: AppColors.borderSubtle)),
              child: Column(
                children: [
                  _ToggleRow(
                    label: 'Servicio completado',
                    sub: 'Marca si el mantenimiento ya fue realizado',
                    value: _isCompleted,
                    onChanged: (v) => setState(() => _isCompleted = v),
                  ),
                  Divider(height: 1, color: AppColors.borderSubtle),
                  _ToggleRow(
                    label: 'Urgente',
                    sub: 'Requiere atención inmediata',
                    value: _isUrgent,
                    activeColor: AppColors.danger,
                    onChanged: (v) => setState(() => _isUrgent = v),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // ── Taller y piezas (colapsable) ──
            GestureDetector(
              onTap: () => setState(() => _provenanceOpen = !_provenanceOpen),
              behavior: HitTestBehavior.opaque,
              child: Container(
                decoration: BoxDecoration(color: AppColors.card, borderRadius: BorderRadius.circular(10), border: Border.all(color: AppColors.borderSubtle)),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('TALLER Y PIEZAS', style: GoogleFonts.jetBrainsMono(fontSize: 10, color: AppColors.textTertiary, letterSpacing: 0.8)),
                          const SizedBox(height: 2),
                          Text('Quién lo hizo, qué piezas, garantía', style: GoogleFonts.inter(fontSize: 10, color: AppColors.textTertiary)),
                        ],
                      ),
                    ),
                    AnimatedRotation(
                      turns: _provenanceOpen ? 0.25 : 0,
                      duration: const Duration(milliseconds: 150),
                      child: const Icon(Icons.chevron_right, size: 18, color: AppColors.textTertiary),
                    ),
                  ],
                ),
              ),
            ),
            if (_provenanceOpen) ...[
              const SizedBox(height: 12),
              _FormField(label: 'TALLER / MECÁNICO', controller: _performedByCtrl, hint: 'Taller Central, Juan García...'),
              const SizedBox(height: 12),
              _FormField(label: 'PIEZAS USADAS', controller: _partsCtrl, hint: 'Filtro aceite, aceite 5W40 4L...', maxLines: 2),
              const SizedBox(height: 12),
              Text('GARANTÍA HASTA', style: GoogleFonts.jetBrainsMono(fontSize: 10, color: AppColors.textTertiary, letterSpacing: 0.8)),
              const SizedBox(height: 6),
              GestureDetector(
                onTap: _pickWarrantyDate,
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: AppColors.card,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: _warrantyDate != null ? AppColors.accent.withValues(alpha: 0.4) : AppColors.borderSubtle),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.calendar_today_outlined, size: 16, color: _warrantyDate != null ? AppColors.accent : AppColors.textTertiary),
                      const SizedBox(width: 10),
                      Text(
                        _warrantyDate != null
                            ? '${_warrantyDate!.day.toString().padLeft(2, '0')}/${_warrantyDate!.month.toString().padLeft(2, '0')}/${_warrantyDate!.year}'
                            : 'dd/mm/aaaa',
                        style: GoogleFonts.inter(fontSize: 14, color: _warrantyDate != null ? AppColors.textPrimary : AppColors.textTertiary),
                      ),
                      if (_warrantyDate != null) ...[
                        const Spacer(),
                        GestureDetector(
                          onTap: () => setState(() => _warrantyDate = null),
                          child: const Icon(Icons.close, size: 16, color: AppColors.textTertiary),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],

            if (_error != null) ...[const SizedBox(height: 10), Text(_error!, style: GoogleFonts.inter(fontSize: 12, color: AppColors.danger))],
            const SizedBox(height: 20),
            _SaveButton(saving: _saving, label: 'Guardar mantenimiento', onTap: _save),
          ],
        ),
      ),
    );
  }

  String _fmtKm(double v) => v.toStringAsFixed(0).replaceAllMapped(
      RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]}.');
}

class _CategoryBtn extends StatelessWidget {
  const _CategoryBtn({required this.value, required this.selected, required this.label, required this.sub, required this.onTap});
  final String value;
  final String selected;
  final String label;
  final String sub;
  final ValueChanged<String> onTap;

  @override
  Widget build(BuildContext context) {
    final active = value == selected;
    return Expanded(
      child: GestureDetector(
        onTap: () => onTap(value),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
          decoration: BoxDecoration(
            color: active ? AppColors.accent.withValues(alpha: 0.15) : AppColors.card,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: active ? AppColors.accent.withValues(alpha: 0.5) : AppColors.borderSubtle),
          ),
          child: Column(
            children: [
              Text(label, textAlign: TextAlign.center, style: GoogleFonts.inter(fontSize: 12, fontWeight: active ? FontWeight.w700 : FontWeight.w500, color: active ? AppColors.accent : AppColors.textSecondary)),
              const SizedBox(height: 2),
              Text(sub, textAlign: TextAlign.center, style: GoogleFonts.inter(fontSize: 9, color: active ? AppColors.accent.withValues(alpha: 0.7) : AppColors.textTertiary)),
            ],
          ),
        ),
      ),
    );
  }
}

class _ToggleRow extends StatelessWidget {
  const _ToggleRow({required this.label, required this.sub, required this.value, required this.onChanged, this.activeColor = AppColors.accent});
  final String label;
  final String sub;
  final bool value;
  final ValueChanged<bool> onChanged;
  final Color activeColor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                Text(sub, style: GoogleFonts.inter(fontSize: 11, color: AppColors.textTertiary)),
              ],
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeColor: activeColor,
            activeTrackColor: activeColor.withValues(alpha: 0.3),
            inactiveThumbColor: AppColors.textTertiary,
            inactiveTrackColor: AppColors.borderSubtle,
          ),
        ],
      ),
    );
  }
}

class _FormField extends StatelessWidget {
  const _FormField({required this.label, required this.controller, required this.hint, this.keyboardType, this.inputFormatters, this.maxLines = 1});
  final String label;
  final TextEditingController controller;
  final String hint;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: GoogleFonts.jetBrainsMono(fontSize: 10, color: AppColors.textTertiary, letterSpacing: 0.8)),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          keyboardType: keyboardType ?? TextInputType.text,
          inputFormatters: inputFormatters,
          maxLines: maxLines,
          style: GoogleFonts.inter(fontSize: 14, color: AppColors.textPrimary),
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
