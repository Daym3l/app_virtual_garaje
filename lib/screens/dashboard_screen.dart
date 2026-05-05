import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_theme.dart';
import '../models/vehicle.dart';
import '../services/dashboard_service.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key, required this.vehicle});

  final Vehicle vehicle;

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
                _HeroCard(vehicle: widget.vehicle),
                const SizedBox(height: 16),
                if (_loading)
                  _SkeletonGrid()
                else if (_error != null)
                  _ErrorBanner(message: _error!, onRetry: _load)
                else ...[
                  _StatsGrid(vehicle: widget.vehicle, data: _data!),
                  const SizedBox(height: 16),
                  if (_hasAlert(_data!)) ...[
                    _AlertsSection(data: _data!),
                    const SizedBox(height: 16),
                  ],
                  _QuickActions(vehicle: widget.vehicle),
                ],
              ]),
            ),
          ),
        ],
      ),
    );
  }

  bool _hasAlert(DashboardData d) {
    if (d.nextMaintenanceDaysLeft == null) return false;
    return d.nextMaintenanceDaysLeft! <= 30 || d.nextMaintenanceUrgent;
  }
}

// ── Hero card ─────────────────────────────────────────────────────────────────

class _HeroCard extends StatelessWidget {
  const _HeroCard({required this.vehicle});
  final Vehicle vehicle;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF0D2144), Color(0xFF0A1828)],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.accent.withValues(alpha: 0.25)),
        boxShadow: [
          BoxShadow(
            color: AppColors.accent.withValues(alpha: 0.08),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          // Vehicle icon big
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: AppColors.accent.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.accent.withValues(alpha: 0.3)),
            ),
            child: Center(
              child: _BigVehicleIcon(vehicle: vehicle),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  vehicle.displayName,
                  style: GoogleFonts.inter(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    _Chip(label: vehicle.plate, icon: Icons.credit_card),
                    const SizedBox(width: 8),
                    _Chip(
                      label: _fuelLabel(vehicle),
                      icon: vehicle.isElectric
                          ? Icons.bolt
                          : Icons.local_gas_station_outlined,
                      color: vehicle.isElectric
                          ? AppColors.success
                          : AppColors.warning,
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    const Icon(Icons.speed_rounded,
                        size: 14, color: AppColors.textTertiary),
                    const SizedBox(width: 4),
                    Text(
                      _formatKm(vehicle.km),
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: AppColors.accent,
                      ),
                    ),
                    Text(
                      '  odómetro',
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        color: AppColors.textTertiary,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _fuelLabel(Vehicle v) {
    switch (v.fuelType) {
      case FuelType.diesel: return 'Diésel';
      case FuelType.electrico: return 'Eléctrico';
      case FuelType.hibrido: return 'Híbrido';
      default: return 'Gasolina';
    }
  }

  String _formatKm(double km) {
    final n = km.toStringAsFixed(0);
    final buf = StringBuffer();
    for (int i = 0; i < n.length; i++) {
      if (i > 0 && (n.length - i) % 3 == 0) buf.write('.');
      buf.write(n[i]);
    }
    return '${buf.toString()} km';
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.icon, this.color});
  final String label;
  final IconData icon;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color ?? AppColors.textTertiary;
    return Container(
      padding: const EdgeInsets.fromLTRB(6, 3, 8, 3),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: c.withValues(alpha: 0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: c),
          const SizedBox(width: 4),
          Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: c,
            ),
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

    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _StatCard(
                icon: isElectric ? Icons.bolt : Icons.local_gas_station_outlined,
                iconColor: isElectric ? AppColors.success : AppColors.warning,
                label: isElectric ? 'Último carga' : 'Último repostaje',
                value: data.lastFuelLiters != null
                    ? '${data.lastFuelLiters!.toStringAsFixed(1)} ${isElectric ? 'kWh' : 'L'}'
                    : '—',
                sub: data.lastFuelDate != null
                    ? _relativeDate(data.lastFuelDate!)
                    : 'Sin registros',
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _StatCard(
                icon: isElectric ? Icons.bolt_outlined : Icons.water_drop_outlined,
                iconColor: AppColors.accent,
                label: isElectric ? 'Consumo (kWh/100km)' : 'Eficiencia (L/100km)',
                value: data.avgConsumption != null
                    ? data.avgConsumption!.toStringAsFixed(1)
                    : '—',
                sub: data.avgConsumption != null
                    ? 'promedio últimas cargas'
                    : 'Sin datos suficientes',
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _StatCard(
                icon: Icons.build_outlined,
                iconColor: _maintColor(data),
                label: 'Próx. mantenimiento',
                value: data.nextMaintenance ?? '—',
                sub: _maintSub(data),
                valueMaxLines: 2,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _StatCard(
                icon: Icons.calendar_month_outlined,
                iconColor: AppColors.accent,
                label: 'Km este mes',
                value: data.kmThisMonth > 0
                    ? '${data.kmThisMonth.toStringAsFixed(0)} km'
                    : '0 km',
                sub: _monthLabel(),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Color _maintColor(DashboardData d) {
    if (d.nextMaintenanceUrgent) return AppColors.danger;
    if (d.nextMaintenanceDaysLeft != null && d.nextMaintenanceDaysLeft! <= 14) {
      return AppColors.warning;
    }
    return AppColors.success;
  }

  String _maintSub(DashboardData d) {
    if (d.nextMaintenance == null) return 'Al día';
    if (d.nextMaintenanceDaysLeft == null) return 'Pendiente';
    final days = d.nextMaintenanceDaysLeft!;
    if (days < 0) return 'Vencido hace ${(-days)} días';
    if (days == 0) return 'Hoy';
    return 'en $days días';
  }

  String _relativeDate(DateTime date) {
    final diff = DateTime.now().difference(date).inDays;
    if (diff == 0) return 'hoy';
    if (diff == 1) return 'ayer';
    return 'hace $diff días';
  }

  String _monthLabel() {
    const months = [
      '', 'Enero', 'Febrero', 'Marzo', 'Abril', 'Mayo', 'Junio',
      'Julio', 'Agosto', 'Septiembre', 'Octubre', 'Noviembre', 'Diciembre',
    ];
    return months[DateTime.now().month];
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.value,
    required this.sub,
    this.valueMaxLines = 1,
  });

  final IconData icon;
  final Color iconColor;
  final String label;
  final String value;
  final String sub;
  final int valueMaxLines;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(7),
                ),
                child: Icon(icon, size: 14, color: iconColor),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  style: GoogleFonts.inter(
                    fontSize: 10,
                    color: AppColors.textTertiary,
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            value,
            style: GoogleFonts.jetBrainsMono(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
            maxLines: valueMaxLines,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 2),
          Text(
            sub,
            style: GoogleFonts.inter(
              fontSize: 10,
              color: AppColors.textTertiary,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

// ── Alerts ────────────────────────────────────────────────────────────────────

class _AlertsSection extends StatelessWidget {
  const _AlertsSection({required this.data});
  final DashboardData data;

  @override
  Widget build(BuildContext context) {
    final isUrgent = data.nextMaintenanceUrgent ||
        (data.nextMaintenanceDaysLeft != null && data.nextMaintenanceDaysLeft! < 0);
    final color = isUrgent ? AppColors.danger : AppColors.warning;
    final days = data.nextMaintenanceDaysLeft;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          Icon(
            isUrgent ? Icons.warning_rounded : Icons.notifications_outlined,
            size: 20,
            color: color,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isUrgent ? 'Mantenimiento urgente' : 'Mantenimiento próximo',
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: color,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _alertBody(days),
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _alertBody(int? days) {
    final name = data.nextMaintenance ?? 'Mantenimiento';
    if (days == null) return name;
    if (days < 0) return '$name · Vencido hace ${-days} días';
    if (days == 0) return '$name · Vence hoy';
    return '$name · Vence en $days días';
  }
}

// ── Quick actions ─────────────────────────────────────────────────────────────

class _QuickActions extends StatelessWidget {
  const _QuickActions({required this.vehicle});
  final Vehicle vehicle;

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
                onTap: () {},
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _ActionButton(
                icon: vehicle.isElectric ? Icons.bolt : Icons.local_gas_station,
                label: vehicle.isElectric ? 'Cargar' : 'Repostar',
                onTap: () {},
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _ActionButton(
                icon: Icons.build_rounded,
                label: 'Mantenimiento',
                onTap: () {},
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
  });
  final IconData icon;
  final String label;
  final VoidCallback onTap;

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
          color: _pressed ? AppColors.cardHover : AppColors.card,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.borderSubtle),
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
