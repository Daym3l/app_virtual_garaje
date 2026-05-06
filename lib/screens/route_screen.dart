import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import '../theme/app_theme.dart';
import '../models/vehicle.dart';
import '../services/route_service.dart';

class RouteScreen extends StatefulWidget {
  const RouteScreen({super.key, required this.vehicle, required this.onRegisterFab});
  final Vehicle vehicle;
  final void Function(VoidCallback) onRegisterFab;

  @override
  State<RouteScreen> createState() => _RouteScreenState();
}

class _RouteScreenState extends State<RouteScreen> {
  List<RouteRecord> _routes = [];
  bool _loading = true;
  bool _tracking = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
    widget.onRegisterFab(_startTracking);
  }

  @override
  void didUpdateWidget(RouteScreen old) {
    super.didUpdateWidget(old);
    if (old.vehicle.id != widget.vehicle.id) {
      _load();
      widget.onRegisterFab(_startTracking);
    }
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final routes = await RouteService.fetchRoutes(widget.vehicle.id);
      if (mounted) setState(() { _routes = routes; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _loading = false; _error = e.toString(); });
    }
  }

  void _startTracking() async {
    if (_tracking) return;
    final granted = await RouteService.requestPermission();
    if (!granted) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Permiso de ubicación requerido')),
        );
      }
      return;
    }
    if (!mounted) return;
    final vehicle = widget.vehicle; // snapshot before async gap
    setState(() => _tracking = true);
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      isDismissible: false,
      enableDrag: false,
      backgroundColor: Colors.transparent,
      builder: (_) => _TrackingSheet(
        vehicle: vehicle,
        onFinished: () {
          Navigator.pop(context);
          setState(() => _tracking = false);
          _load();
        },
      ),
    );
    if (mounted) setState(() => _tracking = false);
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
          SliverToBoxAdapter(child: _Header(routes: _routes)),
          if (_loading)
            const SliverFillRemaining(
              child: Center(child: CircularProgressIndicator(color: AppColors.accent, strokeWidth: 2)),
            )
          else if (_error != null)
            SliverFillRemaining(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.error_outline, size: 40, color: AppColors.danger),
                      const SizedBox(height: 12),
                      Text(_error!, style: GoogleFonts.inter(fontSize: 12, color: AppColors.textTertiary), textAlign: TextAlign.center),
                    ],
                  ),
                ),
              ),
            )
          else if (_routes.isEmpty)
            SliverFillRemaining(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.route_outlined, size: 48, color: AppColors.textTertiary),
                    const SizedBox(height: 12),
                    Text('Sin rutas registradas', style: GoogleFonts.inter(fontSize: 14, color: AppColors.textTertiary)),
                  ],
                ),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (_, i) => _RouteCard(
                    route: _routes[i],
                    onTap: () => _openDetail(_routes[i]),
                  ),
                  childCount: _routes.length,
                ),
              ),
            ),
        ],
      ),
    );
  }

  void _openDetail(RouteRecord route) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => _RouteDetailScreen(route: route),
    ));
  }
}

// ── Header ────────────────────────────────────────────────────────────────────

class _Header extends StatelessWidget {
  const _Header({required this.routes});
  final List<RouteRecord> routes;

  @override
  Widget build(BuildContext context) {
    final totalKm = routes.fold(0.0, (s, r) => s + r.totalDistance);
    final totalMin = routes.fold(0, (s, r) => s + r.duration.inMinutes);
    final avgSpeed = routes.isNotEmpty
        ? routes.fold(0.0, (s, r) => s + r.averageSpeed) / routes.length
        : 0.0;

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
          Expanded(child: _Cell(label: 'TOTAL KM', value: totalKm.toStringAsFixed(1), unit: 'km', color: AppColors.accent)),
          Container(width: 1, height: 40, color: AppColors.borderSubtle),
          Expanded(child: _Cell(label: 'TIEMPO', value: _fmtMin(totalMin), unit: 'total', color: AppColors.textSecondary)),
          Container(width: 1, height: 40, color: AppColors.borderSubtle),
          Expanded(child: _Cell(label: 'VEL. MEDIA', value: avgSpeed.toStringAsFixed(0), unit: 'km/h', color: AppColors.textSecondary)),
        ],
      ),
    );
  }

  String _fmtMin(int min) {
    if (min < 60) return '${min}m';
    return '${min ~/ 60}h ${min % 60}m';
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

// ── Route card ────────────────────────────────────────────────────────────────

class _RouteCard extends StatelessWidget {
  const _RouteCard({required this.route, required this.onTap});
  final RouteRecord route;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
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
              child: const Icon(Icons.route_outlined, size: 18, color: AppColors.accent),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${route.totalDistance.toStringAsFixed(2)} km',
                    style: GoogleFonts.jetBrainsMono(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                  ),
                  Text(
                    _fmtDuration(route.duration),
                    style: GoogleFonts.inter(fontSize: 11, color: AppColors.textTertiary),
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(_fmtDate(route.startTime), style: GoogleFonts.inter(fontSize: 11, color: AppColors.textTertiary)),
                Text('${route.averageSpeed.toStringAsFixed(0)} km/h', style: GoogleFonts.jetBrainsMono(fontSize: 10, color: AppColors.accent)),
              ],
            ),
            const SizedBox(width: 8),
            const Icon(Icons.chevron_right, size: 16, color: AppColors.textTertiary),
          ],
        ),
      ),
    );
  }

  String _fmtDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  String _fmtDuration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes % 60;
    final s = d.inSeconds % 60;
    if (h > 0) return '${h}h ${m}m';
    if (m > 0) return '${m}m ${s}s';
    return '${s}s';
  }
}

// ── Tracking sheet ────────────────────────────────────────────────────────────

class _TrackingSheet extends StatefulWidget {
  const _TrackingSheet({required this.vehicle, required this.onFinished});
  final Vehicle vehicle;
  final VoidCallback onFinished;

  @override
  State<_TrackingSheet> createState() => _TrackingSheetState();
}

class _TrackingSheetState extends State<_TrackingSheet> {
  final List<RoutePoint> _points = [];
  final MapController _mapController = MapController();
  StreamSubscription<Position>? _sub;
  DateTime? _startTime;
  double _currentSpeed = 0;
  double _distanceKm = 0;
  bool _saving = false;
  Timer? _timer;
  Duration _elapsed = Duration.zero;

  @override
  void initState() {
    super.initState();
    _startTime = DateTime.now();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _elapsed = DateTime.now().difference(_startTime!));
    });
    _sub = RouteService.trackingStream().listen((pos) {
      if (!mounted) return;
      final pt = RoutePoint.fromPosition(pos);
      setState(() {
        _points.add(pt);
        _currentSpeed = pt.speed;
        _distanceKm = RouteService.calcDistance(_points);
      });
      try { _mapController.move(pt.latLng, _mapController.camera.zoom); } catch (_) {}
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _finish() async {
    setState(() => _saving = true);
    _sub?.cancel();
    _timer?.cancel();

    final endTime = DateTime.now();
    final duration = endTime.difference(_startTime!);
    final avgSpeed = duration.inSeconds > 0
        ? (_distanceKm / duration.inSeconds * 3600)
        : 0.0;

    try {
      await RouteService.saveRoute(
        vehicleId: widget.vehicle.id,
        startTime: _startTime!,
        endTime: endTime,
        points: _points,
        totalDistance: _distanceKm,
        averageSpeed: avgSpeed,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al guardar: $e'), backgroundColor: AppColors.danger),
        );
      }
    }
    widget.onFinished();
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).padding.bottom;
    return Container(
      height: MediaQuery.of(context).size.height * 0.92,
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          // Handle + header
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
            child: Column(
              children: [
                Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: AppColors.borderSubtle, borderRadius: BorderRadius.circular(2)))),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Container(
                      width: 10, height: 10,
                      decoration: BoxDecoration(
                        color: AppColors.danger,
                        shape: BoxShape.circle,
                        boxShadow: [BoxShadow(color: AppColors.danger.withValues(alpha: 0.6), blurRadius: 8)],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text('RUTA EN CURSO', style: GoogleFonts.jetBrainsMono(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.textPrimary, letterSpacing: 1)),
                    const Spacer(),
                    Text(_fmtElapsed(_elapsed), style: GoogleFonts.jetBrainsMono(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.accent)),
                  ],
                ),
              ],
            ),
          ),

          // Stats row
          Container(
            margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: AppColors.card, borderRadius: BorderRadius.circular(10), border: Border.all(color: AppColors.borderSubtle)),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _StatChip(label: 'DISTANCIA', value: '${_distanceKm.toStringAsFixed(2)} km'),
                Container(width: 1, height: 30, color: AppColors.borderSubtle),
                _StatChip(label: 'VELOCIDAD', value: '${_currentSpeed.toStringAsFixed(0)} km/h'),
                Container(width: 1, height: 30, color: AppColors.borderSubtle),
                _StatChip(label: 'PUNTOS', value: '${_points.length}'),
              ],
            ),
          ),

          // Map
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(0),
              child: FlutterMap(
                mapController: _mapController,
                options: MapOptions(
                  initialCenter: _points.isNotEmpty ? _points.last.latLng : const LatLng(23.1136, -82.3666),
                  initialZoom: 16,
                ),
                children: [
                  TileLayer(
                    urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                    userAgentPackageName: 'com.daym3l.virtualgaraje',
                  ),
                  if (_points.length >= 2)
                    PolylineLayer(
                      polylines: [
                        Polyline(points: _points.map((p) => p.latLng).toList(), color: AppColors.accent, strokeWidth: 4),
                      ],
                    ),
                  if (_points.isNotEmpty)
                    MarkerLayer(
                      markers: [
                        Marker(
                          point: _points.last.latLng,
                          width: 20, height: 20,
                          child: Container(
                            decoration: BoxDecoration(
                              color: AppColors.accent,
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 2),
                              boxShadow: [BoxShadow(color: AppColors.accent.withValues(alpha: 0.5), blurRadius: 8)],
                            ),
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ),

          // Stop button
          Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + bottom),
            child: GestureDetector(
              onTap: _saving ? null : _finish,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 14),
                decoration: BoxDecoration(
                  color: _saving ? AppColors.danger.withValues(alpha: 0.5) : AppColors.danger,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Center(
                  child: _saving
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : Text('Finalizar ruta', style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w700, color: Colors.white)),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _fmtElapsed(Duration d) {
    final h = d.inHours.toString().padLeft(2, '0');
    final m = (d.inMinutes % 60).toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$h:$m:$s';
  }
}

class _StatChip extends StatelessWidget {
  const _StatChip({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(label, style: GoogleFonts.jetBrainsMono(fontSize: 8, color: AppColors.textTertiary, letterSpacing: 0.8)),
        const SizedBox(height: 4),
        Text(value, style: GoogleFonts.jetBrainsMono(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
      ],
    );
  }
}

// ── Route detail screen ───────────────────────────────────────────────────────

class _RouteDetailScreen extends StatelessWidget {
  const _RouteDetailScreen({required this.route});
  final RouteRecord route;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.textPrimary,
        title: Text('Detalle de ruta', style: GoogleFonts.inter(fontSize: 17, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
        elevation: 0,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: AppColors.borderSubtle),
        ),
      ),
      body: Column(
        children: [
          // Map
          SizedBox(
            height: MediaQuery.of(context).size.height * 0.45,
            child: FlutterMap(
              options: MapOptions(
                initialCenter: route.points.isNotEmpty ? _center(route.points) : const LatLng(23.1136, -82.3666),
                initialZoom: _zoom(route.totalDistance),
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.daym3l.virtualgaraje',
                ),
                if (route.points.length >= 2)
                  PolylineLayer(
                    polylines: [
                      Polyline(points: route.points, color: AppColors.accent, strokeWidth: 4),
                    ],
                  ),
                if (route.points.isNotEmpty) ...[
                  MarkerLayer(markers: [
                    Marker(
                      point: route.points.first,
                      width: 16, height: 16,
                      child: Container(decoration: const BoxDecoration(color: AppColors.success, shape: BoxShape.circle)),
                    ),
                    Marker(
                      point: route.points.last,
                      width: 16, height: 16,
                      child: Container(decoration: const BoxDecoration(color: AppColors.danger, shape: BoxShape.circle)),
                    ),
                  ]),
                ],
              ],
            ),
          ),

          // Info
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Container(
                decoration: BoxDecoration(color: AppColors.card, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.borderSubtle)),
                child: Column(
                  children: [
                    _InfoRow('Fecha', _fmtDate(route.startTime)),
                    _InfoRow('Inicio', _fmtTime(route.startTime)),
                    _InfoRow('Fin', _fmtTime(route.endTime)),
                    _InfoRow('Duración', _fmtDuration(route.duration)),
                    _InfoRow('Distancia', '${route.totalDistance.toStringAsFixed(2)} km'),
                    _InfoRow('Vel. media', '${route.averageSpeed.toStringAsFixed(1)} km/h'),
                    _InfoRow('Puntos GPS', '${route.points.length}', isLast: true),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  LatLng _center(List<LatLng> pts) {
    final lat = pts.map((p) => p.latitude).reduce((a, b) => a + b) / pts.length;
    final lng = pts.map((p) => p.longitude).reduce((a, b) => a + b) / pts.length;
    return LatLng(lat, lng);
  }

  double _zoom(double km) {
    if (km < 1) return 16;
    if (km < 5) return 14;
    if (km < 20) return 12;
    if (km < 100) return 10;
    return 8;
  }

  String _fmtDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  String _fmtTime(DateTime d) =>
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

  String _fmtDuration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes % 60;
    final s = d.inSeconds % 60;
    if (h > 0) return '${h}h ${m}m';
    if (m > 0) return '${m}m ${s}s';
    return '${s}s';
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow(this.label, this.value, {this.isLast = false});
  final String label;
  final String value;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label, style: GoogleFonts.inter(fontSize: 13, color: AppColors.textTertiary)),
              Text(value, style: GoogleFonts.jetBrainsMono(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
            ],
          ),
        ),
        if (!isLast) Divider(height: 1, color: AppColors.borderSubtle),
      ],
    );
  }
}
