import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_theme.dart';
import '../models/vehicle.dart';
import '../services/auth_service.dart';
import '../services/vehicle_service.dart';
import 'dashboard_screen.dart';

// ── Tab index constants ───────────────────────────────────────────────────────

class AppTab {
  static const home = 0;
  static const kms = 1;
  static const fuel = 2;
  static const maintenance = 3;
  static const routes = 4;
}

// ── Shell ─────────────────────────────────────────────────────────────────────

class ShellScreen extends StatefulWidget {
  const ShellScreen({super.key});

  @override
  State<ShellScreen> createState() => _ShellScreenState();
}

class _ShellScreenState extends State<ShellScreen> {
  int _tab = AppTab.home;
  List<Vehicle> _vehicles = [];
  Vehicle? _activeVehicle;
  bool _drawerOpen = false;
  bool _loadingVehicles = true;
  String? _snackMessage;
  Color _snackColor = AppColors.success;

  @override
  void initState() {
    super.initState();
    _loadVehicles();
  }

  Future<void> _loadVehicles() async {
    try {
      final list = await VehicleService.fetchVehicles();
      if (mounted) {
        setState(() {
          _vehicles = list;
          _activeVehicle = list.isNotEmpty ? list.first : null;
          _loadingVehicles = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loadingVehicles = false);
        _showSnack('Error cargando vehículos', color: AppColors.danger);
      }
    }
  }

  void _showSnack(String msg, {Color? color}) {
    setState(() {
      _snackMessage = msg;
      _snackColor = color ?? AppColors.success;
    });
    Future.delayed(const Duration(milliseconds: 2500), () {
      if (mounted) setState(() => _snackMessage = null);
    });
  }

  void _setVehicle(Vehicle v) {
    setState(() {
      _activeVehicle = v;
      _drawerOpen = false;
    });
    _showSnack('Vehículo activo: ${v.name}');
  }

  String get _tabTitle {
    switch (_tab) {
      case AppTab.home: return 'Inicio';
      case AppTab.kms: return 'Kilometraje';
      case AppTab.fuel: return (_activeVehicle?.isElectric ?? false) ? 'Energía' : 'Combustible';
      case AppTab.maintenance: return 'Mantenimiento';
      case AppTab.routes: return 'Rutas';
      default: return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
      ),
      child: Scaffold(
        backgroundColor: AppColors.background,
        body: _loadingVehicles
            ? const Center(
                child: CircularProgressIndicator(color: AppColors.accent),
              )
            : Stack(
                children: [
                  // Main content
                  Column(
                    children: [
                      _TopBar(
                        title: _tabTitle,
                        activeVehicle: _activeVehicle,
                        onVehicleTap: () => setState(() => _drawerOpen = true),
                      ),
                      Expanded(child: _tabBody()),
                    ],
                  ),

                  // Bottom nav
                  Positioned(
                    left: 0, right: 0, bottom: 0,
                    child: _BottomNav(
                      activeTab: _tab,
                      onTabChanged: (t) => setState(() => _tab = t),
                    ),
                  ),

                  // FAB
                  _FabButton(tab: _tab, onPressed: () => _showSnack('FAB tapped')),

                  // Drawer overlay
                  if (_drawerOpen)
                    GestureDetector(
                      onTap: () => setState(() => _drawerOpen = false),
                      child: Container(color: const Color(0x80000000)),
                    ),

                  // Vehicle drawer
                  AnimatedPositioned(
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeInOut,
                    left: _drawerOpen ? 0 : -MediaQuery.of(context).size.width * 0.78,
                    top: 0, bottom: 0,
                    width: MediaQuery.of(context).size.width * 0.78,
                    child: _VehicleDrawer(
                      vehicles: _vehicles,
                      activeVehicle: _activeVehicle,
                      onVehicleSelected: _setVehicle,
                      onClose: () => setState(() => _drawerOpen = false),
                    ),
                  ),

                  // Snackbar
                  if (_snackMessage != null)
                    Positioned(
                      left: 16, right: 16, bottom: 70,
                      child: _Snackbar(message: _snackMessage!, color: _snackColor),
                    ),
                ],
              ),
      ),
    );
  }

  Widget _tabBody() {
    if (_activeVehicle == null) {
      return Center(
        child: Text(
          'Sin vehículos registrados',
          style: GoogleFonts.inter(fontSize: 15, color: AppColors.textTertiary),
        ),
      );
    }

    switch (_tab) {
      case AppTab.home:
        return DashboardScreen(vehicle: _activeVehicle!);
      default:
        final labels = ['', 'Kilometraje', 'Combustible', 'Mantenimiento', 'Rutas'];
        return Padding(
          padding: const EdgeInsets.only(bottom: 56),
          child: Center(
            child: Text(
              labels[_tab],
              style: GoogleFonts.inter(fontSize: 18, color: AppColors.textTertiary),
            ),
          ),
        );
    }
  }
}

// ── TopBar ────────────────────────────────────────────────────────────────────

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.title,
    required this.activeVehicle,
    required this.onVehicleTap,
  });

  final String title;
  final Vehicle? activeVehicle;
  final VoidCallback onVehicleTap;

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.of(context).padding.top;
    return Container(
      padding: EdgeInsets.fromLTRB(16, top + 10, 16, 10),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(
          bottom: BorderSide(color: AppColors.borderSubtle),
        ),
      ),
      child: Row(
        children: [
          // Title
          Expanded(
            child: Text(
              title,
              style: GoogleFonts.inter(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
          ),

          // Vehicle chip
          GestureDetector(
            onTap: onVehicleTap,
            child: Container(
              padding: const EdgeInsets.fromLTRB(7, 5, 10, 5),
              decoration: BoxDecoration(
                color: AppColors.card,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: AppColors.accent.withValues(alpha: 0.4),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (activeVehicle != null) ...[
                    _VehicleIcon(vehicle: activeVehicle!, size: 14),
                    const SizedBox(width: 6),
                    Text(
                      activeVehicle!.name,
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ] else
                    Text(
                      'Sin vehículo',
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textTertiary,
                      ),
                    ),
                  const SizedBox(width: 4),
                  const Icon(Icons.expand_more,
                      size: 14, color: AppColors.textTertiary),
                ],
              ),
            ),
          ),

          const SizedBox(width: 10),

          // Avatar
          _Avatar(),
        ],
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final user = AuthService.currentUser;
    final initials = _initials(user?.email ?? user?.userMetadata?['name'] ?? '?');
    final photoUrl = user?.userMetadata?['avatar_url'] as String?;

    return Container(
      width: 32, height: 32,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: AppColors.accent.withValues(alpha: 0.5),
        ),
        gradient: const LinearGradient(
          colors: [Color(0xFF1A3A6A), Color(0xFF0A1828)],
        ),
      ),
      child: photoUrl != null
          ? ClipOval(child: Image.network(photoUrl, fit: BoxFit.cover))
          : Center(
              child: Text(
                initials,
                style: GoogleFonts.inter(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
    );
  }

  String _initials(String s) {
    final parts = s.trim().split(RegExp(r'[\s@]'));
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts[0][0].toUpperCase();
    return (parts[0][0] + parts[1][0]).toUpperCase();
  }
}

// ── BottomNav ─────────────────────────────────────────────────────────────────

class _BottomNav extends StatelessWidget {
  const _BottomNav({required this.activeTab, required this.onTabChanged});

  final int activeTab;
  final ValueChanged<int> onTabChanged;

  static const _items = [
    _NavItem('Inicio',       Icons.home_rounded,       Icons.home_outlined),
    _NavItem('Km',           Icons.speed_rounded,      Icons.speed_outlined),
    _NavItem('Combustible',  Icons.local_gas_station,  Icons.local_gas_station_outlined),
    _NavItem('Manten.',      Icons.build_rounded,      Icons.build_outlined),
    _NavItem('Rutas',        Icons.place_rounded,      Icons.place_outlined),
  ];

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).padding.bottom;
    return Container(
      padding: EdgeInsets.fromLTRB(0, 0, 0, bottom),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.borderSubtle)),
      ),
      child: Row(
        children: List.generate(_items.length, (i) {
          final active = i == activeTab;
          return Expanded(
            child: GestureDetector(
              onTap: () => onTabChanged(i),
              behavior: HitTestBehavior.opaque,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      active ? _items[i].icon : _items[i].iconOutlined,
                      size: 22,
                      color: active ? AppColors.accent : AppColors.textTertiary,
                      shadows: active
                          ? [Shadow(color: AppColors.accent.withValues(alpha: 0.7), blurRadius: 8)]
                          : null,
                    ),
                    const SizedBox(height: 3),
                    Text(
                      _items[i].label,
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 9,
                        fontWeight: active ? FontWeight.w700 : FontWeight.w400,
                        color: active ? AppColors.accent : AppColors.textTertiary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}

class _NavItem {
  const _NavItem(this.label, this.icon, this.iconOutlined);
  final String label;
  final IconData icon;
  final IconData iconOutlined;
}


// ── Vehicle drawer ────────────────────────────────────────────────────────────

class _VehicleDrawer extends StatelessWidget {
  const _VehicleDrawer({
    required this.vehicles,
    required this.activeVehicle,
    required this.onVehicleSelected,
    required this.onClose,
  });

  final List<Vehicle> vehicles;
  final Vehicle? activeVehicle;
  final ValueChanged<Vehicle> onVehicleSelected;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.of(context).padding.top;
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(
          right: BorderSide(color: AppColors.borderSubtle),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Container(
            padding: EdgeInsets.fromLTRB(16, top + 16, 16, 16),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: AppColors.borderSubtle)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'MIS VEHÍCULOS',
                        style: GoogleFonts.jetBrainsMono(
                          fontSize: 10,
                          color: AppColors.accent,
                          letterSpacing: 1.2,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${vehicles.length} registrados',
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          color: AppColors.textTertiary,
                        ),
                      ),
                    ],
                  ),
                ),
                GestureDetector(
                  onTap: onClose,
                  child: const Icon(Icons.close,
                      color: AppColors.textTertiary, size: 20),
                ),
              ],
            ),
          ),

          // Vehicle list
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.all(12),
              itemCount: vehicles.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (_, i) {
                final v = vehicles[i];
                final active = activeVehicle != null && v.id == activeVehicle!.id;
                return GestureDetector(
                  onTap: () => onVehicleSelected(v),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: active
                          ? AppColors.accent.withValues(alpha: 0.12)
                          : AppColors.card,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: active
                            ? AppColors.accent.withValues(alpha: 0.4)
                            : AppColors.borderSubtle,
                      ),
                    ),
                    child: Row(
                      children: [
                        // Icon container
                        Container(
                          width: 38, height: 38,
                          decoration: BoxDecoration(
                            color: active
                                ? AppColors.accent.withValues(alpha: 0.15)
                                : AppColors.surface,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: AppColors.borderSubtle),
                          ),
                          child: Center(
                            child: _VehicleIcon(vehicle: v, size: 20),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                v.name,
                                style: GoogleFonts.inter(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.textPrimary,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '${v.plate} · ${_formatKm(v.km)}',
                                style: GoogleFonts.jetBrainsMono(
                                  fontSize: 10,
                                  color: AppColors.textTertiary,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (active)
                          Container(
                            width: 8, height: 8,
                            decoration: BoxDecoration(
                              color: AppColors.accent,
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: AppColors.accent.withValues(alpha: 0.6),
                                  blurRadius: 6,
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),

          // Sign out button
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
            child: GestureDetector(
              onTap: () async => AuthService.signOut(),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: AppColors.dangerDim,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: AppColors.danger.withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.logout, size: 16, color: AppColors.danger),
                    const SizedBox(width: 8),
                    Text(
                      'Cerrar sesión',
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppColors.danger,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatKm(double km) {
    if (km >= 1000) {
      return '${(km / 1000).toStringAsFixed(1)}k km';
    }
    return '${km.toStringAsFixed(0)} km';
  }
}

// ── FAB ───────────────────────────────────────────────────────────────────────

class _FabButton extends StatefulWidget {
  const _FabButton({required this.tab, required this.onPressed});
  final int tab;
  final VoidCallback onPressed;

  @override
  State<_FabButton> createState() => _FabButtonState();
}

class _FabButtonState extends State<_FabButton> {
  bool _pressed = false;

  String get _label {
    switch (widget.tab) {
      case AppTab.kms: return 'Registrar km';
      case AppTab.fuel: return 'Repostar';
      case AppTab.maintenance: return 'Mantenimiento';
      case AppTab.routes: return '▶ INICIAR RUTA';
      default: return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.tab == AppTab.home) return const SizedBox.shrink();
    final bottom = MediaQuery.of(context).padding.bottom + 72;

    return Positioned(
      right: 16, bottom: bottom,
      child: GestureDetector(
        onTapDown: (_) => setState(() => _pressed = true),
        onTapUp: (_) => setState(() => _pressed = false),
        onTapCancel: () => setState(() => _pressed = false),
        onTap: widget.onPressed,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 100),
          transform: Matrix4.identity()..scale(_pressed ? 0.95 : 1.0),
          transformAlignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
          decoration: BoxDecoration(
            color: AppColors.accent,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: AppColors.accent.withValues(alpha: 0.5),
                blurRadius: 20,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.add, size: 18, color: AppColors.background),
              const SizedBox(width: 8),
              Text(
                _label,
                style: widget.tab == AppTab.routes
                    ? GoogleFonts.jetBrainsMono(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: AppColors.background,
                        letterSpacing: 1.0,
                      )
                    : GoogleFonts.inter(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AppColors.background,
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Snackbar ──────────────────────────────────────────────────────────────────

class _Snackbar extends StatelessWidget {
  const _Snackbar({required this.message, required this.color});
  final String message;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.5)),
        boxShadow: const [
          BoxShadow(color: Color(0x80000000), blurRadius: 20, offset: Offset(0, 4)),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 8, height: 8,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              boxShadow: [BoxShadow(color: color.withValues(alpha: 0.6), blurRadius: 6)],
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: GoogleFonts.inter(
                fontSize: 13,
                color: AppColors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Vehicle icon (SVG custom) ─────────────────────────────────────────────────

class _VehicleIcon extends StatelessWidget {
  const _VehicleIcon({required this.vehicle, required this.size});
  final Vehicle vehicle;
  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size, height: size,
      child: CustomPaint(
        painter: _VehicleIconPainter(
          isMoto: vehicle.type == VehicleType.moto,
          color: AppColors.accent,
        ),
      ),
    );
  }
}

class _VehicleIconPainter extends CustomPainter {
  const _VehicleIconPainter({required this.isMoto, required this.color});
  final bool isMoto;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * 0.08
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final w = size.width;
    final h = size.height;

    if (isMoto) {
      // Moto silhouette
      final body = Path();
      body.moveTo(w * 0.15, h * 0.65);
      body.lineTo(w * 0.35, h * 0.35);
      body.lineTo(w * 0.55, h * 0.30);
      body.lineTo(w * 0.72, h * 0.38);
      body.lineTo(w * 0.85, h * 0.65);
      canvas.drawPath(body, paint);

      // Handlebars
      canvas.drawLine(Offset(w * 0.60, h * 0.28), Offset(w * 0.78, h * 0.28), paint);

      // Wheels
      canvas.drawCircle(Offset(w * 0.22, h * 0.70), w * 0.17, paint);
      canvas.drawCircle(Offset(w * 0.78, h * 0.70), w * 0.17, paint);
    } else {
      // Car silhouette
      final body = Path();
      body.moveTo(w * 0.05, h * 0.68);
      body.lineTo(w * 0.12, h * 0.68);
      body.lineTo(w * 0.20, h * 0.42);
      body.lineTo(w * 0.35, h * 0.26);
      body.lineTo(w * 0.65, h * 0.26);
      body.lineTo(w * 0.80, h * 0.42);
      body.lineTo(w * 0.88, h * 0.55);
      body.lineTo(w * 0.95, h * 0.58);
      body.lineTo(w * 0.95, h * 0.68);
      body.close();
      canvas.drawPath(body, paint);

      // Wheels
      canvas.drawCircle(Offset(w * 0.26, h * 0.74), w * 0.13, paint);
      canvas.drawCircle(Offset(w * 0.74, h * 0.74), w * 0.13, paint);
    }
  }

  @override
  bool shouldRepaint(_VehicleIconPainter old) =>
      old.isMoto != isMoto || old.color != color;
}
