import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import '../theme/app_theme.dart';
import '../models/vehicle.dart';
import '../services/dashboard_service.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({
    super.key,
    required this.vehicle,
    this.onSwitchTab,
    this.isPaidMember = false,
  });

  final Vehicle vehicle;
  final ValueChanged<int>? onSwitchTab;
  final bool isPaidMember;

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  DashboardData? _data;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(DashboardScreen old) {
    super.didUpdateWidget(old);
    if (old.vehicle.id != widget.vehicle.id) _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await DashboardService.fetch(
        widget.vehicle.id,
        isElectric: widget.vehicle.isElectric,
        currentMileage: widget.vehicle.km,
      );
      if (mounted) setState(() { _data = data; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
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
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                if (_loading) ...[
                  _HeroCard(vehicle: widget.vehicle, data: null),
                  const SizedBox(height: 10),
                  _SkeletonGrid(),
                ] else if (_error != null) ...[
                  _HeroCard(vehicle: widget.vehicle, data: null),
                  const SizedBox(height: 10),
                  _ErrorBanner(message: _error!, onRetry: _load),
                ] else ...[
                  _HeroCard(vehicle: widget.vehicle, data: _data!),
                  const SizedBox(height: 10),
                  _AlertsSection(alerts: _data!.alerts),
                  const SizedBox(height: 10),
                  _StatsGrid(vehicle: widget.vehicle, data: _data!),
                  const SizedBox(height: 16),
                  _QuickActions(vehicle: widget.vehicle, onSwitchTab: widget.onSwitchTab, isPaidMember: widget.isPaidMember),
                  const SizedBox(height: 16),
                  const _WebBanner(),
                ],
              ]),
            ),
          ),
        ],
      ),
    );
  }

}

// ── Hero card ─────────────────────────────────────────────────────────────────

class _HeroCard extends StatelessWidget {
  const _HeroCard({required this.vehicle, required this.data});
  final Vehicle vehicle;
  final DashboardData? data;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Label superior
          Text(
            'VEHÍCULO ACTIVO',
            style: GoogleFonts.jetBrainsMono(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: AppColors.textTertiary,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 10),
          // Icono + nombre + matrícula/año
          Row(
            children: [
              _BigVehicleIcon(vehicle: vehicle),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      vehicle.displayName,
                      style: GoogleFonts.inter(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${vehicle.plate} · ${vehicle.year}',
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        color: AppColors.textTertiary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          // Celdas odómetro + eficiencia
          Row(
            children: [
              Expanded(
                child: _HeroCell(
                  label: 'ODÓMETRO',
                  value: _formatKm(vehicle.km),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _HeroCell(
                  label: 'EFICIENCIA',
                  value: data?.avgConsumption != null
                      ? data!.avgConsumption!.toStringAsFixed(1)
                      : '—',
                  unit: vehicle.isElectric ? 'kWh/100km' : 'km/L',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }


  String _formatKm(double km) {
    final n = km.toStringAsFixed(0);
    final buf = StringBuffer();
    for (int i = 0; i < n.length; i++) {
      if (i > 0 && (n.length - i) % 3 == 0) buf.write('.');
      buf.write(n[i]);
    }
    return '${buf.toString()} Km';
  }
}

class _HeroCell extends StatelessWidget {
  const _HeroCell({required this.label, required this.value, this.unit});
  final String label;
  final String value;
  final String? unit;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: GoogleFonts.jetBrainsMono(
              fontSize: 9,
              fontWeight: FontWeight.w600,
              color: AppColors.textTertiary,
              letterSpacing: 1.0,
            ),
          ),
          const SizedBox(height: 4),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                value,
                style: GoogleFonts.inter(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
              if (unit != null) ...[
                const SizedBox(width: 4),
                Text(
                  unit!,
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 9,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textTertiary,
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

// ── Stats grid ────────────────────────────────────────────────────────────────

class _StatsGrid extends StatelessWidget {
  const _StatsGrid({required this.vehicle, required this.data});
  final Vehicle vehicle;
  final DashboardData data;

  @override
  Widget build(BuildContext context) {
    final isElectric = vehicle.isElectric;
    final maintAlert = data.alerts.isEmpty ? null : data.alerts.first;
    final maintColor = maintAlert == null
        ? AppColors.success
        : switch (maintAlert.level) {
            AlertLevel.error => AppColors.danger,
            AlertLevel.warning => AppColors.warning,
            AlertLevel.info => AppColors.accent,
          };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'RESUMEN',
          style: GoogleFonts.jetBrainsMono(
            fontSize: 10,
            fontWeight: FontWeight.w600,
            color: AppColors.textTertiary,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: 8),
        _StatCard(
          icon: isElectric ? Icons.bolt : Icons.local_gas_station_outlined,
          iconColor: isElectric ? AppColors.success : AppColors.warning,
          label: isElectric ? 'ÚLTIMO CARGA' : 'ÚLTIMO REPOSTAJE',
          value: data.lastFuelLiters != null
              ? '${data.lastFuelLiters!.toStringAsFixed(1)} ${isElectric ? 'kWh' : 'L'}'
              : '—',
          sub: _lastFuelSub(data, isElectric),
          dot: null,
        ),
        const SizedBox(height: 8),
        _StatCard(
          icon: Icons.build_outlined,
          iconColor: maintColor,
          label: 'PRÓX. MANTENIMIENTO',
          value: maintAlert?.type ?? 'Al día',
          sub: maintAlert != null ? _maintSub(maintAlert) : 'Sin pendientes',
          dot: maintAlert != null ? maintColor : null,
        ),
        const SizedBox(height: 8),
        _StatCard(
          icon: Icons.place_outlined,
          iconColor: AppColors.accent,
          label: 'KM ESTE MES',
          value: _formatKmMes(data.kmThisMonth),
          sub: '${_formatKm(vehicle.totalKm)} totales',
          dot: null,
        ),
      ],
    );
  }

  String _lastFuelSub(DashboardData d, bool isElectric) {
    final parts = <String>[];
    if (d.lastFuelCost != null) parts.add('\$${d.lastFuelCost!.toStringAsFixed(2)}');
    if (d.lastFuelDate != null) parts.add(_relativeDate(d.lastFuelDate!));
    return parts.isEmpty ? 'Sin registros' : parts.join(' · ');
  }

  String _maintSub(MaintenanceAlert a) => a.subtitle;

  String _relativeDate(DateTime date) {
    final diff = DateTime.now().difference(date).inDays;
    if (diff == 0) return 'hoy';
    if (diff == 1) return 'ayer';
    return 'hace $diff días';
  }

  String _formatKmMes(double km) {
    if (km <= 0) return '0 km';
    return '${_formatNum(km)} km';
  }

  String _formatKm(double km) => '${_formatNum(km)} km';

  String _formatNum(double n) {
    final s = n.toStringAsFixed(0);
    final buf = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write('.');
      buf.write(s[i]);
    }
    return buf.toString();
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.value,
    required this.sub,
    required this.dot,
  });

  final IconData icon;
  final Color iconColor;
  final String label;
  final String value;
  final String sub;
  final Color? dot; // null = sin punto

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.borderSubtle),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 20, color: iconColor),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 9,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textTertiary,
                    letterSpacing: 0.8,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: GoogleFonts.inter(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 1),
                Text(
                  sub,
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    color: AppColors.textTertiary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          if (dot != null)
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: dot,
                shape: BoxShape.circle,
                boxShadow: [BoxShadow(color: dot!.withValues(alpha: 0.5), blurRadius: 6)],
              ),
            ),
        ],
      ),
    );
  }
}

// ── Alerts ────────────────────────────────────────────────────────────────────

class _AlertsSection extends StatelessWidget {
  const _AlertsSection({required this.alerts});
  final List<MaintenanceAlert> alerts;

  @override
  Widget build(BuildContext context) {
    if (alerts.isEmpty) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.borderSubtle),
        ),
        child: Row(
          children: [
            const Icon(Icons.check_circle_outline,
                size: 16, color: AppColors.success),
            const SizedBox(width: 10),
            Text(
              'Sin alertas activas',
              style: GoogleFonts.inter(
                  fontSize: 12, color: AppColors.textTertiary),
            ),
          ],
        ),
      );
    }

    return Column(
      children: alerts.map((a) => _AlertRow(alert: a)).toList(),
    );
  }
}

class _AlertRow extends StatelessWidget {
  const _AlertRow({required this.alert});
  final MaintenanceAlert alert;

  Color get _color => switch (alert.level) {
        AlertLevel.error => AppColors.danger,
        AlertLevel.warning => AppColors.warning,
        AlertLevel.info => AppColors.accent,
      };

  String get _badge => switch (alert.level) {
        AlertLevel.error => 'URGENTE',
        AlertLevel.warning => 'PRONTO',
        AlertLevel.info => 'PRÓXIMO',
      };

  @override
  Widget build(BuildContext context) {
    final color = _color;
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          // Borde izquierdo 4px
          Container(
            width: 4,
            height: 48,
            decoration: BoxDecoration(
              color: color,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(10),
                bottomLeft: Radius.circular(10),
              ),
            ),
          ),
          const SizedBox(width: 12),
          // Punto de color
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  alert.type,
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
                Text(
                  alert.subtitle,
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    color: AppColors.textTertiary,
                  ),
                ),
              ],
            ),
          ),
          // Badge
          Container(
            margin: const EdgeInsets.only(right: 12),
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              _badge,
              style: GoogleFonts.jetBrainsMono(
                fontSize: 9,
                fontWeight: FontWeight.w700,
                color: color,
                letterSpacing: 0.8,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Quick actions ─────────────────────────────────────────────────────────────

class _QuickActions extends StatelessWidget {
  const _QuickActions({required this.vehicle, this.onSwitchTab, this.isPaidMember = false});
  final Vehicle vehicle;
  final ValueChanged<int>? onSwitchTab;
  final bool isPaidMember;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'ACCIONES RÁPIDAS',
          style: GoogleFonts.jetBrainsMono(
            fontSize: 10,
            color: AppColors.accent,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _ActionButton(
                icon: Icons.speed_rounded,
                label: 'Registrar km',
                onTap: () => onSwitchTab?.call(1),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _ActionButton(
                icon: vehicle.isElectric ? Icons.bolt : Icons.local_gas_station,
                label: vehicle.isElectric ? 'Cargar' : 'Repostar',
                onTap: () => onSwitchTab?.call(2),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _ActionButton(
                icon: Icons.build_rounded,
                label: 'Manten.',
                onTap: () => onSwitchTab?.call(3),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _ActionButton(
                icon: isPaidMember ? Icons.place_rounded : Icons.lock_outline_rounded,
                label: 'Ruta',
                accent: isPaidMember,
                onTap: () => onSwitchTab?.call(4),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _ActionButton extends StatefulWidget {
  const _ActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.accent = false,
  });
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool accent;

  @override
  State<_ActionButton> createState() => _ActionButtonState();
}

class _ActionButtonState extends State<_ActionButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      onTap: widget.onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 100),
        transform: Matrix4.identity()..scale(_pressed ? 0.95 : 1.0),
        transformAlignment: Alignment.center,
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: widget.accent
              ? (_pressed ? AppColors.accent.withValues(alpha: 0.85) : AppColors.accent.withValues(alpha: 0.15))
              : (_pressed ? AppColors.cardHover : AppColors.card),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: widget.accent ? AppColors.accent.withValues(alpha: 0.5) : AppColors.borderSubtle,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(widget.icon, size: 22, color: AppColors.accent),
            const SizedBox(height: 6),
            Text(
              widget.label,
              style: GoogleFonts.inter(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary,
              ),
              textAlign: TextAlign.center,
              maxLines: 2,
            ),
          ],
        ),
      ),
    );
  }
}

// ── Skeleton ──────────────────────────────────────────────────────────────────

class _SkeletonGrid extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(child: _Skeleton(height: 100)),
            const SizedBox(width: 12),
            Expanded(child: _Skeleton(height: 100)),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(child: _Skeleton(height: 100)),
            const SizedBox(width: 12),
            Expanded(child: _Skeleton(height: 100)),
          ],
        ),
      ],
    );
  }
}

class _Skeleton extends StatefulWidget {
  const _Skeleton({required this.height});
  final double height;

  @override
  State<_Skeleton> createState() => _SkeletonState();
}

class _SkeletonState extends State<_Skeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _anim = Tween<double>(begin: 0.4, end: 0.8).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _anim,
      builder: (_, __) => Container(
        height: widget.height,
        decoration: BoxDecoration(
          color: AppColors.card.withValues(alpha: _anim.value),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.borderSubtle),
        ),
      ),
    );
  }
}

// ── Error banner ──────────────────────────────────────────────────────────────

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.dangerDim,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.danger.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: AppColors.danger, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Error cargando datos',
              style: GoogleFonts.inter(
                fontSize: 13,
                color: AppColors.textPrimary,
              ),
            ),
          ),
          GestureDetector(
            onTap: onRetry,
            child: Text(
              'Reintentar',
              style: GoogleFonts.inter(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: AppColors.accent,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Web banner ────────────────────────────────────────────────────────────────

class _WebBanner extends StatelessWidget {
  const _WebBanner();

  static const _url = 'https://mi-garaje-virtual.vercel.app';

  Future<void> _open() async {
    final uri = Uri.parse(_url);
    if (await canLaunchUrl(uri)) await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.accent.withValues(alpha: 0.20)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: AppColors.accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.language_rounded, size: 17, color: AppColors.accent),
              ),
              const SizedBox(width: 10),
              Text(
                'MI GARAJE VIRTUAL — WEB',
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: AppColors.accent,
                  letterSpacing: 1.0,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'Administra tu flota completa desde el portal web',
            style: GoogleFonts.inter(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Agrega vehículos, cambia tu plan de membresía y más desde cualquier navegador.',
            style: GoogleFonts.inter(
              fontSize: 12,
              color: AppColors.textTertiary,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              _WebChip(
                icon: Icons.directions_car_outlined,
                label: '+ Vehículo',
                onTap: _open,
              ),
              const SizedBox(width: 8),
              _WebChip(
                icon: Icons.star_outline_rounded,
                label: 'Membresía',
                onTap: _open,
              ),
            ],
          ),
          const SizedBox(height: 12),
          GestureDetector(
            onTap: _open,
            child: Row(
              children: [
                Text(
                  'mi-garaje-virtual.vercel.app',
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 10,
                    color: AppColors.accent.withValues(alpha: 0.7),
                    letterSpacing: 0.4,
                  ),
                ),
                const SizedBox(width: 4),
                Icon(Icons.arrow_forward_rounded, size: 12, color: AppColors.accent.withValues(alpha: 0.7)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _WebChip extends StatefulWidget {
  const _WebChip({required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  State<_WebChip> createState() => _WebChipState();
}

class _WebChipState extends State<_WebChip> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      onTap: widget.onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 100),
        transform: Matrix4.identity()..scale(_pressed ? 0.95 : 1.0),
        transformAlignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: _pressed
              ? AppColors.accent.withValues(alpha: 0.25)
              : AppColors.accent.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.accent.withValues(alpha: 0.30)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(widget.icon, size: 14, color: AppColors.accent),
            const SizedBox(width: 6),
            Text(
              widget.label,
              style: GoogleFonts.inter(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.accent,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Big vehicle icon ──────────────────────────────────────────────────────────

class _BigVehicleIcon extends StatelessWidget {
  const _BigVehicleIcon({required this.vehicle});
  final Vehicle vehicle;

  @override
  Widget build(BuildContext context) {
    final icon = switch (vehicle.type) {
      VehicleType.moto => Icons.two_wheeler,
      VehicleType.truck => Icons.local_shipping_outlined,
      _ => Icons.directions_car_outlined,
    };
    return Icon(icon, size: 36, color: AppColors.accent);
  }
}
