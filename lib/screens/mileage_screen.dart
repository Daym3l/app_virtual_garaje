import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_theme.dart';
import '../models/vehicle.dart';
import '../services/mileage_service.dart';
import '../services/odometer_service.dart';

class MileageScreen extends StatefulWidget {
  const MileageScreen({super.key, required this.vehicle, required this.onRegisterFab});
  final Vehicle vehicle;
  final void Function(VoidCallback) onRegisterFab;

  @override
  State<MileageScreen> createState() => _MileageScreenState();
}

class _MileageScreenState extends State<MileageScreen> {
  List<MileageLog> _logs = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
    widget.onRegisterFab(_openForm);
  }

  @override
  void didUpdateWidget(MileageScreen old) {
    super.didUpdateWidget(old);
    if (old.vehicle.id != widget.vehicle.id) { _load(); widget.onRegisterFab(_openForm); }
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final logs = await MileageService.fetchLogs(widget.vehicle.id);
    if (mounted) setState(() { _logs = logs; _loading = false; });
  }

  void _openForm() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _MileageForm(
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
          SliverToBoxAdapter(
            child: _Header(vehicle: widget.vehicle, logs: _logs),
          ),
          if (_loading)
            const SliverFillRemaining(
              child: Center(
                child: CircularProgressIndicator(color: AppColors.accent, strokeWidth: 2),
              ),
            )
          else if (_logs.isEmpty)
            SliverFillRemaining(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.speed_outlined, size: 48, color: AppColors.textTertiary),
                    const SizedBox(height: 12),
                    Text(
                      'Sin registros de kilometraje',
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
                delegate: SliverChildBuilderDelegate(
                  (_, i) => _LogCard(log: _logs[i], prev: i < _logs.length - 1 ? _logs[i + 1] : null),
                  childCount: _logs.length,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.vehicle, required this.logs});
  final Vehicle vehicle;
  final List<MileageLog> logs;

  @override
  Widget build(BuildContext context) {
    final total = vehicle.totalKm;
    final lastLog = logs.isNotEmpty ? logs.first : null;
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
          Expanded(
            child: _Cell(
              label: 'ODÓMETRO ACTUAL',
              value: _fmt(vehicle.km),
              unit: 'KM',
              color: AppColors.accent,
            ),
          ),
          Container(width: 1, height: 40, color: AppColors.borderSubtle),
          Expanded(
            child: _Cell(
              label: 'KM TOTALES',
              value: _fmt(total),
              unit: 'KM',
              color: AppColors.textSecondary,
            ),
          ),
          Container(width: 1, height: 40, color: AppColors.borderSubtle),
          Expanded(
            child: _Cell(
              label: 'REGISTROS',
              value: '${logs.length}',
              unit: lastLog != null ? _relDate(lastLog.date) : '—',
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  String _fmt(double v) {
    final s = v.toStringAsFixed(0);
    final buf = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write('.');
      buf.write(s[i]);
    }
    return buf.toString();
  }

  String _relDate(DateTime d) {
    final diff = DateTime.now().difference(d).inDays;
    if (diff == 0) return 'hoy';
    if (diff == 1) return 'ayer';
    return 'hace $diff d';
  }
}

class _Cell extends StatelessWidget {
  const _Cell({required this.label, required this.value, required this.unit, required this.color});
  final String label;
  final String value;
  final String unit;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(label, style: GoogleFonts.jetBrainsMono(fontSize: 8, color: AppColors.textTertiary, letterSpacing: 0.8)),
        const SizedBox(height: 4),
        Text(value, style: GoogleFonts.jetBrainsMono(fontSize: 18, fontWeight: FontWeight.w700, color: color)),
        Text(unit, style: GoogleFonts.jetBrainsMono(fontSize: 9, color: AppColors.textTertiary)),
      ],
    );
  }
}

void _showMileageDetail(BuildContext context, MileageLog log, MileageLog? prev) {
  final diff = prev != null ? log.mileage - prev.mileage : null;
  showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (_) => _DetailSheet(
      icon: Icons.speed_outlined,
      iconColor: AppColors.accent,
      title: '${_fmtKm(log.mileage)} km',
      subtitle: _fmtDate(log.date),
      rows: [
        if (diff != null && diff > 0) _DetailRow('Diferencia', '+${_fmtKm(diff)} km'),
        if (log.notes?.isNotEmpty == true) _DetailRow('Notas', log.notes!),
      ],
    ),
  );
}

String _fmtKm(double v) => v.toStringAsFixed(0).replaceAllMapped(
    RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]}.');

String _fmtDate(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

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
                          children: [
                            Text(e.value.label, style: GoogleFonts.inter(fontSize: 13, color: AppColors.textTertiary)),
                            Flexible(child: Text(e.value.value, textAlign: TextAlign.end, style: GoogleFonts.jetBrainsMono(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary))),
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

class _LogCard extends StatelessWidget {
  const _LogCard({required this.log, required this.prev});
  final MileageLog log;
  final MileageLog? prev;

  @override
  Widget build(BuildContext context) {
    final diff = prev != null ? log.mileage - prev!.mileage : null;
    return GestureDetector(
      onTap: () => _showMileageDetail(context, log, prev),
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
              color: AppColors.accent.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.speed_outlined, size: 18, color: AppColors.accent),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${_fmt(log.mileage)} km',
                  style: GoogleFonts.jetBrainsMono(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                ),
                if (log.notes?.isNotEmpty == true)
                  Text(log.notes!, style: GoogleFonts.inter(fontSize: 11, color: AppColors.textTertiary)),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(_dateStr(log.date), style: GoogleFonts.inter(fontSize: 11, color: AppColors.textTertiary)),
              if (diff != null && diff > 0)
                Text(
                  '+${_fmt(diff)} km',
                  style: GoogleFonts.jetBrainsMono(fontSize: 10, fontWeight: FontWeight.w600, color: AppColors.success),
                ),
            ],
          ),
        ],
      ),
    ),   // Container
    );   // GestureDetector
  }

  String _fmt(double v) => v.toStringAsFixed(0).replaceAllMapped(
      RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]}.');

  String _dateStr(DateTime d) {
    return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
  }
}

class _MileageForm extends StatefulWidget {
  const _MileageForm({required this.vehicle, required this.onSaved});
  final Vehicle vehicle;
  final VoidCallback onSaved;

  @override
  State<_MileageForm> createState() => _MileageFormState();
}

class _MileageFormState extends State<_MileageForm> {
  final _kmCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  DateTime _selectedDate = DateTime.now();
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _kmCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(now.year - 5),
      lastDate: now,
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: const ColorScheme.dark(
            primary: AppColors.accent,
            onPrimary: AppColors.background,
            surface: AppColors.card,
            onSurface: AppColors.textPrimary,
          ),
          dialogTheme: const DialogThemeData(backgroundColor: AppColors.surface),
        ),
        child: child!,
      ),
    );
    if (picked != null) setState(() => _selectedDate = picked);
  }

  Future<void> _save() async {
    final km = double.tryParse(_kmCtrl.text.replaceAll(',', '.'));
    if (km == null || km <= 0) {
      setState(() => _error = 'Ingresa un kilometraje válido');
      return;
    }
    setState(() { _saving = true; _error = null; });
    final odoError = await OdometerService.validate(
      vehicleId: widget.vehicle.id,
      date: _selectedDate,
      valueKm: km,
      excludeSource: 'mileage',
    );
    if (odoError != null) {
      if (mounted) setState(() { _saving = false; _error = odoError; });
      return;
    }
    try {
      await MileageService.addLog(
        vehicleId: widget.vehicle.id,
        mileage: km,
        notes: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
        date: _selectedDate,
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
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40, height: 4,
              decoration: BoxDecoration(color: AppColors.borderSubtle, borderRadius: BorderRadius.circular(2)),
            ),
          ),
          const SizedBox(height: 20),
          Text('Registrar Kilometraje', style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
          const SizedBox(height: 4),
          Text('Actual: ${widget.vehicle.km.toStringAsFixed(0)} km', style: GoogleFonts.inter(fontSize: 12, color: AppColors.textTertiary)),
          const SizedBox(height: 20),
          _FormField(
            label: 'ODÓMETRO ACTUAL (KM)',
            controller: _kmCtrl,
            hint: widget.vehicle.km.toStringAsFixed(0),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[\d,.]'))],
          ),
          const SizedBox(height: 12),
          _DateField(date: _selectedDate, onTap: _pickDate),
          const SizedBox(height: 12),
          _FormField(
            label: 'NOTAS (OPCIONAL)',
            controller: _notesCtrl,
            hint: 'Ej: Revisión general, viaje largo...',
          ),
          if (_error != null) ...[
            const SizedBox(height: 10),
            Text(_error!, style: GoogleFonts.inter(fontSize: 12, color: AppColors.danger)),
          ],
          const SizedBox(height: 20),
          _SaveButton(saving: _saving, label: 'Guardar kilometraje', onTap: _save),
        ],
      ),
    );
  }
}

// ── Shared form widgets ───────────────────────────────────────────────────────

class _DateField extends StatelessWidget {
  const _DateField({required this.date, required this.onTap});
  final DateTime date;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final label = '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('FECHA', style: GoogleFonts.jetBrainsMono(fontSize: 10, color: AppColors.textTertiary, letterSpacing: 0.8)),
        const SizedBox(height: 6),
        GestureDetector(
          onTap: onTap,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: AppColors.card,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.borderSubtle),
            ),
            child: Row(
              children: [
                const Icon(Icons.calendar_today_outlined, size: 16, color: AppColors.textTertiary),
                const SizedBox(width: 10),
                Text(label, style: GoogleFonts.inter(fontSize: 14, color: AppColors.textPrimary)),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _FormField extends StatelessWidget {
  const _FormField({
    required this.label,
    required this.controller,
    required this.hint,
    this.keyboardType,
    this.inputFormatters,
  });
  final String label;
  final TextEditingController controller;
  final String hint;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;

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
          style: GoogleFonts.inter(fontSize: 14, color: AppColors.textPrimary),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: GoogleFonts.inter(fontSize: 14, color: AppColors.textTertiary),
            filled: true,
            fillColor: AppColors.card,
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: AppColors.borderSubtle),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: AppColors.borderSubtle),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: AppColors.accent),
            ),
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
              ? const SizedBox(
                  width: 20, height: 20,
                  child: CircularProgressIndicator(color: AppColors.background, strokeWidth: 2),
                )
              : Text(label, style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.background)),
        ),
      ),
    );
  }
}
