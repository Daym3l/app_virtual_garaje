import 'dart:math';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_theme.dart';
import '../services/auth_service.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  bool _loading = false;
  String? _error;

  Future<void> _handleGoogleSignIn() async {
    setState(() { _loading = true; _error = null; });
    try {
      await AuthService.signInWithGoogle();
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Column(
        children: [
          const _HeroZone(),
          Expanded(
            child: _FormZone(
              loading: _loading,
              error: _error,
              onGoogleSignIn: _handleGoogleSignIn,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Hero zone ─────────────────────────────────────────────────────────────────

class _HeroZone extends StatefulWidget {
  const _HeroZone();

  @override
  State<_HeroZone> createState() => _HeroZoneState();
}

class _HeroZoneState extends State<_HeroZone>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _pulse;
  late Animation<double> _fadeIn;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat(reverse: true);

    _pulse = Tween<double>(begin: 0.5, end: 1.0).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
    _fadeIn = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _ctrl,
        curve: const Interval(0.0, 0.3, curve: Curves.easeOut),
      ),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final heroH = size.height * 0.50;

    return SizedBox(
      height: heroH,
      width: double.infinity,
      child: Stack(
        children: [
          // Deep space background
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                stops: [0.0, 0.45, 1.0],
                colors: [
                  Color(0xFF02050C),
                  Color(0xFF030A18),
                  Color(0xFF061020),
                ],
              ),
            ),
          ),

          // Stars
          const _StarField(),

          // Isometric garage scene
          Positioned.fill(
            child: AnimatedBuilder(
              animation: _ctrl,
              builder: (_, __) => CustomPaint(
                painter: _IsometricGaragePainter(
                  pulseValue: _pulse.value,
                  fadeIn: _fadeIn.value,
                ),
              ),
            ),
          ),

          // Bottom fade into form
          Positioned(
            bottom: 0, left: 0, right: 0,
            child: Container(
              height: 60,
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [Color(0xFF050E1C), Colors.transparent],
                ),
              ),
            ),
          ),

          // App label — top left
          Positioned(
            top: 52, left: 20,
            child: FadeTransition(
              opacity: _fadeIn,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'MI GARAJE VIRTUAL',
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 10,
                      color: AppColors.accent,
                      letterSpacing: 1.8,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    'Tu flota,\nen tu mano.',
                    style: GoogleFonts.inter(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary,
                      height: 1.15,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Isometric garage painter ──────────────────────────────────────────────────

class _IsometricGaragePainter extends CustomPainter {
  const _IsometricGaragePainter({
    required this.pulseValue,
    required this.fadeIn,
  });

  final double pulseValue;
  final double fadeIn;

  // Iso projection helpers
  Offset _iso(double x, double y, double z, Offset origin) {
    return Offset(
      origin.dx + (x - z) * 0.72,
      origin.dy + (x + z) * 0.42 - y * 0.85,
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // Anchor: lower-center slightly left
    final origin = Offset(w * 0.50, h * 0.88);

    // Unit size
    const u = 52.0;

    _drawGarageBuilding(canvas, origin, u);
    _drawFloor(canvas, origin, u, size);
    _drawCars(canvas, origin, u);
    _drawLights(canvas, origin, u);
  }

  void _drawGarageBuilding(Canvas canvas, Offset o, double u) {
    // Building dimensions: 4u wide, 3u deep, 2.5u tall
    final bW = 4.0 * u;
    final bD = 3.0 * u;
    final bH = 2.5 * u;

    // 8 corners of the box
    final fbl = _iso(0, 0, 0, o);       // front-bottom-left
    final fbr = _iso(bW, 0, 0, o);      // front-bottom-right
    final bbl = _iso(0, 0, bD, o);      // back-bottom-left
    final bbr = _iso(bW, 0, bD, o);     // back-bottom-right
    final ftl = _iso(0, bH, 0, o);      // front-top-left
    final ftr = _iso(bW, bH, 0, o);     // front-top-right
    final btl = _iso(0, bH, bD, o);     // back-top-left
    final btr = _iso(bW, bH, bD, o);    // back-top-right

    final wallFill = Paint()..style = PaintingStyle.fill;
    final edgePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0
      ..color = AppColors.accent.withValues(alpha: 0.35);

    // Left face (darker)
    wallFill.color = const Color(0xFF040C1A);
    _drawFace(canvas, [fbl, bbl, btl, ftl], wallFill);
    _drawFace(canvas, [fbl, bbl, btl, ftl], edgePaint);

    // Right face
    wallFill.color = const Color(0xFF050E1C);
    _drawFace(canvas, [fbr, bbr, btr, ftr], wallFill);
    _drawFace(canvas, [fbr, bbr, btr, ftr], edgePaint);

    // Front face (most visible)
    wallFill.color = const Color(0xFF071424);
    _drawFace(canvas, [fbl, fbr, ftr, ftl], wallFill);

    // Front face edge
    _drawFace(canvas, [fbl, fbr, ftr, ftl],
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2
          ..color = AppColors.accent.withValues(alpha: 0.5));

    // Roof
    wallFill.color = const Color(0xFF050E1C);
    _drawFace(canvas, [ftl, ftr, btr, btl], wallFill);
    _drawFace(canvas, [ftl, ftr, btr, btl],
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.0
          ..color = AppColors.accent.withValues(alpha: 0.4));

    // Roof accent stripe
    final roofStripe = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = AppColors.accent.withValues(alpha: 0.6 * pulseValue);
    canvas.drawLine(
      _iso(bW * 0.1, bH, 0, o),
      _iso(bW * 0.1, bH, bD, o),
      roofStripe,
    );
    canvas.drawLine(
      _iso(bW * 0.9, bH, 0, o),
      _iso(bW * 0.9, bH, bD, o),
      roofStripe,
    );

    // Garage door on front face (centered)
    _drawGarageDoor(canvas, o, u, bW, bH);

    // Side window on left face
    _drawSideWindow(canvas, o, u, bD, bH);
  }

  void _drawGarageDoor(Canvas canvas, Offset o, double u, double bW, double bH) {
    final dL = bW * 0.18;
    final dR = bW * 0.82;
    final dB = 0.05 * u;
    final dT = bH * 0.90;

    final dl = _iso(dL, dB, 0, o);
    final dr = _iso(dR, dB, 0, o);
    final tr = _iso(dR, dT, 0, o);
    final tl = _iso(dL, dT, 0, o);

    // Door background
    _drawFace(canvas, [dl, dr, tr, tl],
        Paint()..color = const Color(0xFF030810));

    // Door glow border
    _drawFace(canvas, [dl, dr, tr, tl],
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 6
          ..color = AppColors.accent.withValues(alpha: 0.12 * pulseValue)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6));

    // Door frame
    _drawFace(canvas, [dl, dr, tr, tl],
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..color = AppColors.accent.withValues(alpha: 0.7));

    // Horizontal panel lines (4 panels)
    for (int i = 1; i <= 3; i++) {
      final py = dB + (dT - dB) * i / 4;
      canvas.drawLine(
        _iso(dL + 1, py, 0, o),
        _iso(dR - 1, py, 0, o),
        Paint()
          ..color = AppColors.accent.withValues(alpha: 0.18)
          ..strokeWidth = 0.8,
      );
    }

    // Handle
    final hY = dB + (dT - dB) * 0.5;
    canvas.drawLine(
      _iso(bW * 0.43, hY, 0, o),
      _iso(bW * 0.57, hY, 0, o),
      Paint()
        ..color = AppColors.accent.withValues(alpha: 0.7)
        ..strokeWidth = 2.0
        ..strokeCap = StrokeCap.round,
    );
  }

  void _drawSideWindow(Canvas canvas, Offset o, double u, double bD, double bH) {
    final wZ1 = bD * 0.25;
    final wZ2 = bD * 0.65;
    final wY1 = bH * 0.55;
    final wY2 = bH * 0.82;

    final bl = _iso(0, wY1, wZ1, o);
    final br = _iso(0, wY1, wZ2, o);
    final tr = _iso(0, wY2, wZ2, o);
    final tl = _iso(0, wY2, wZ1, o);

    _drawFace(canvas, [bl, br, tr, tl],
        Paint()..color = AppColors.accent.withValues(alpha: 0.06));
    _drawFace(canvas, [bl, br, tr, tl],
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.0
          ..color = AppColors.accent.withValues(alpha: 0.35));

    // Cross divider
    canvas.drawLine(
      Offset((bl.dx + br.dx) / 2, bl.dy),
      Offset((tl.dx + tr.dx) / 2, tl.dy),
      Paint()..color = AppColors.accent.withValues(alpha: 0.2)..strokeWidth = 0.7,
    );
    canvas.drawLine(
      Offset(bl.dx, (bl.dy + tl.dy) / 2),
      Offset(br.dx, (br.dy + tr.dy) / 2),
      Paint()..color = AppColors.accent.withValues(alpha: 0.2)..strokeWidth = 0.7,
    );
  }

  void _drawFloor(Canvas canvas, Offset o, double u, Size size) {
    final bW = 4.0 * u;
    final bD = 3.0 * u;

    // Extended floor
    final fbl = _iso(-u, 0, 0, o);
    final fbr = _iso(bW + u, 0, 0, o);
    final bbl = _iso(-u, 0, bD + u, o);
    final bbr = _iso(bW + u, 0, bD + u, o);

    _drawFace(canvas, [fbl, fbr, bbr, bbl],
        Paint()..color = const Color(0xFF040C18));

    // Grid lines on floor
    final gridPaint = Paint()
      ..color = AppColors.accent.withValues(alpha: 0.08)
      ..strokeWidth = 0.6;

    for (int i = -1; i <= 5; i++) {
      canvas.drawLine(
        _iso(i * u, 0, 0, o),
        _iso(i * u, 0, bD + u, o),
        gridPaint,
      );
    }
    for (int i = 0; i <= 4; i++) {
      canvas.drawLine(
        _iso(-u, 0, i * u, o),
        _iso(bW + u, 0, i * u, o),
        gridPaint,
      );
    }

    // Floor accent line at building edge
    canvas.drawLine(
      _iso(0, 0, 0, o),
      _iso(bW, 0, 0, o),
      Paint()
        ..color = AppColors.accent.withValues(alpha: 0.4)
        ..strokeWidth = 1.2,
    );
  }

  void _drawCars(Canvas canvas, Offset o, double u) {
    // Car 1: inside garage (center)
    _drawCar(canvas, o, u,
      x: u * 0.9, z: u * 0.5,
      color: AppColors.accent,
      headlightColor: AppColors.accent,
      scale: 0.85,
    );

    // Car 2: outside left, parked
    _drawCar(canvas, o, u,
      x: -u * 0.7, z: u * 0.3,
      color: const Color(0xFF3DCC7E),
      headlightColor: const Color(0xFF3DCC7E),
      scale: 0.72,
    );

    // Car 3: outside right
    _drawCar(canvas, o, u,
      x: u * 3.1, z: -u * 0.5,
      color: const Color(0xFFFFB830),
      headlightColor: const Color(0xFFFFB830),
      scale: 0.68,
    );
  }

  void _drawCar(
    Canvas canvas,
    Offset o,
    double u, {
    required double x,
    required double z,
    required Color color,
    required Color headlightColor,
    required double scale,
  }) {
    final cW = u * 1.4 * scale;
    final cH = u * 0.55 * scale;
    final cD = u * 0.65 * scale;
    final roofH = u * 0.38 * scale;
    final roofOff = u * 0.22 * scale;

    final bodyFill = Paint()
      ..color = color.withValues(alpha: 0.12)
      ..style = PaintingStyle.fill;
    final bodyStroke = Paint()
      ..color = color.withValues(alpha: 0.55)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.1
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    // Body — front face
    _drawFace(canvas, [
      _iso(x, 0, z, o),
      _iso(x + cW, 0, z, o),
      _iso(x + cW, cH, z, o),
      _iso(x, cH, z, o),
    ], bodyFill);
    _drawFace(canvas, [
      _iso(x, 0, z, o),
      _iso(x + cW, 0, z, o),
      _iso(x + cW, cH, z, o),
      _iso(x, cH, z, o),
    ], bodyStroke);

    // Body — top face
    _drawFace(canvas, [
      _iso(x, cH, z, o),
      _iso(x + cW, cH, z, o),
      _iso(x + cW, cH, z + cD, o),
      _iso(x, cH, z + cD, o),
    ], bodyFill..color = color.withValues(alpha: 0.08));
    _drawFace(canvas, [
      _iso(x, cH, z, o),
      _iso(x + cW, cH, z, o),
      _iso(x + cW, cH, z + cD, o),
      _iso(x, cH, z + cD, o),
    ], bodyStroke..color = color.withValues(alpha: 0.35));

    // Roof
    _drawFace(canvas, [
      _iso(x + roofOff, cH, z + cD * 0.1, o),
      _iso(x + cW - roofOff, cH, z + cD * 0.1, o),
      _iso(x + cW - roofOff, cH + roofH, z + cD * 0.2, o),
      _iso(x + roofOff, cH + roofH, z + cD * 0.2, o),
    ], bodyFill..color = color.withValues(alpha: 0.15));
    _drawFace(canvas, [
      _iso(x + roofOff, cH, z + cD * 0.1, o),
      _iso(x + cW - roofOff, cH, z + cD * 0.1, o),
      _iso(x + cW - roofOff, cH + roofH, z + cD * 0.2, o),
      _iso(x + roofOff, cH + roofH, z + cD * 0.2, o),
    ], bodyStroke..color = color.withValues(alpha: 0.5));

    // Headlight
    final hlPos = _iso(x + cW * 0.88, cH * 0.5, z, o);
    canvas.drawCircle(hlPos, 3 * scale,
        Paint()
          ..color = headlightColor.withValues(alpha: 0.5 * pulseValue)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5));
    canvas.drawCircle(hlPos, 1.5 * scale,
        Paint()..color = headlightColor.withValues(alpha: 0.9));

    // Taillight (red)
    final tlPos = _iso(x + cW * 0.12, cH * 0.5, z, o);
    canvas.drawCircle(tlPos, 2 * scale,
        Paint()
          ..color = const Color(0xFFFF4D4D).withValues(alpha: 0.4 * pulseValue)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4));
    canvas.drawCircle(tlPos, 1.2 * scale,
        Paint()..color = const Color(0xFFFF4D4D).withValues(alpha: 0.8));

    // Wheels (4 dots)
    for (final wPos in [
      _iso(x + cW * 0.22, 0, z + cD * 0.1, o),
      _iso(x + cW * 0.78, 0, z + cD * 0.1, o),
      _iso(x + cW * 0.22, 0, z + cD * 0.8, o),
      _iso(x + cW * 0.78, 0, z + cD * 0.8, o),
    ]) {
      canvas.drawCircle(wPos, 3.5 * scale,
          Paint()..color = const Color(0xFF02060E));
      canvas.drawCircle(wPos, 3.5 * scale,
          Paint()
            ..color = color.withValues(alpha: 0.45)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.0);
    }
  }

  void _drawLights(Canvas canvas, Offset o, double u) {
    final bW = 4.0 * u;
    final bH = 2.5 * u;

    // Overhead ceiling light strip (inside garage, above door)
    final lA = _iso(bW * 0.25, bH * 0.97, 0.2, o);
    final lB = _iso(bW * 0.75, bH * 0.97, 0.2, o);

    canvas.drawLine(lA, lB,
        Paint()
          ..color = AppColors.accent.withValues(alpha: 0.18 * pulseValue)
          ..strokeWidth = 8
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8));
    canvas.drawLine(lA, lB,
        Paint()
          ..color = AppColors.accent.withValues(alpha: 0.75 * pulseValue)
          ..strokeWidth = 1.5
          ..strokeCap = StrokeCap.round);

    // Light cone downward
    final coneBase1 = _iso(bW * 0.20, 0, 0.3, o);
    final coneBase2 = _iso(bW * 0.80, 0, 0.3, o);
    final conePath = Path()
      ..moveTo(lA.dx, lA.dy)
      ..lineTo(lB.dx, lB.dy)
      ..lineTo(coneBase2.dx, coneBase2.dy)
      ..lineTo(coneBase1.dx, coneBase1.dy)
      ..close();
    canvas.drawPath(conePath,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              AppColors.accent.withValues(alpha: 0.09 * pulseValue),
              AppColors.accent.withValues(alpha: 0.0),
            ],
          ).createShader(Rect.fromPoints(lA, coneBase1)));

    // Neon edge strips on building corners
    _drawNeon(canvas,
        _iso(0, 0, 0, o), _iso(0, bH, 0, o),
        AppColors.accent, 0.45 * pulseValue);
    _drawNeon(canvas,
        _iso(bW, 0, 0, o), _iso(bW, bH, 0, o),
        AppColors.accent, 0.35 * pulseValue);
    _drawNeon(canvas,
        _iso(0, bH, 0, o), _iso(bW, bH, 0, o),
        AppColors.accent, 0.4 * pulseValue);

    // Ground neon line (door threshold)
    _drawNeon(canvas,
        _iso(bW * 0.18, 0.5, 0, o), _iso(bW * 0.82, 0.5, 0, o),
        AppColors.accent, 0.6 * pulseValue);
  }

  void _drawNeon(Canvas canvas, Offset a, Offset b, Color color, double opacity) {
    canvas.drawLine(a, b,
        Paint()
          ..color = color.withValues(alpha: opacity * 0.5)
          ..strokeWidth = 4
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4));
    canvas.drawLine(a, b,
        Paint()
          ..color = color.withValues(alpha: opacity)
          ..strokeWidth = 1.2
          ..strokeCap = StrokeCap.round);
  }

  void _drawFace(Canvas canvas, List<Offset> pts, Paint paint) {
    if (pts.isEmpty) return;
    final path = Path()..moveTo(pts[0].dx, pts[0].dy);
    for (int i = 1; i < pts.length; i++) {
      path.lineTo(pts[i].dx, pts[i].dy);
    }
    path.close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_IsometricGaragePainter old) =>
      old.pulseValue != pulseValue;
}

// ── Star field ────────────────────────────────────────────────────────────────

class _StarField extends StatelessWidget {
  const _StarField();

  @override
  Widget build(BuildContext context) {
    final rng = Random(99);
    return LayoutBuilder(builder: (context, constraints) {
      return Stack(
        children: List.generate(35, (i) {
          final x = rng.nextDouble() * constraints.maxWidth;
          final y = rng.nextDouble() * constraints.maxHeight * 0.35;
          final sz = 0.8 + rng.nextDouble() * 1.2;
          final op = 0.15 + rng.nextDouble() * 0.45;
          return Positioned(
            left: x, top: y,
            child: Container(
              width: sz, height: sz,
              decoration: BoxDecoration(
                color: AppColors.textPrimary.withValues(alpha: op),
                shape: BoxShape.circle,
              ),
            ),
          );
        }),
      );
    });
  }
}

// ── Form zone ─────────────────────────────────────────────────────────────────

class _FormZone extends StatelessWidget {
  const _FormZone({
    required this.loading,
    required this.error,
    required this.onGoogleSignIn,
  });

  final bool loading;
  final String? error;
  final VoidCallback onGoogleSignIn;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [
          BoxShadow(
            color: Color(0x90000000),
            blurRadius: 40,
            offset: Offset(0, -8),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Pill handle
            Center(
              child: Container(
                width: 36, height: 4,
                margin: const EdgeInsets.only(bottom: 24),
                decoration: BoxDecoration(
                  color: AppColors.borderSubtle,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Text(
              'Accede a tu garaje',
              style: GoogleFonts.inter(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Gestiona tu flota de vehículos desde cualquier lugar.',
              style: GoogleFonts.inter(
                fontSize: 13,
                color: AppColors.textSecondary,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 32),
            _GoogleButton(loading: loading, onPressed: onGoogleSignIn),
            if (error != null) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: AppColors.dangerDim,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.danger.withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline,
                        color: AppColors.danger, size: 14),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        error!,
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          color: AppColors.danger,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const Spacer(),
            Center(
              child: Text(
                'v1.0.0-beta · Mi Garaje Virtual',
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 10,
                  color: AppColors.textTertiary,
                  letterSpacing: 0.5,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Google button ─────────────────────────────────────────────────────────────

class _GoogleButton extends StatefulWidget {
  const _GoogleButton({required this.loading, required this.onPressed});
  final bool loading;
  final VoidCallback onPressed;

  @override
  State<_GoogleButton> createState() => _GoogleButtonState();
}

class _GoogleButtonState extends State<_GoogleButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      onTap: widget.loading ? null : widget.onPressed,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        transform: Matrix4.identity()..scale(_pressed ? 0.97 : 1.0),
        transformAlignment: Alignment.center,
        decoration: BoxDecoration(
          color: _pressed ? const Color(0x225B9DFF) : const Color(0x0FFFFFFF),
          border: Border.all(
            color: _pressed
                ? AppColors.accent
                : AppColors.accent.withValues(alpha: 0.35),
            width: 1.5,
          ),
          borderRadius: BorderRadius.circular(12),
          boxShadow: _pressed
              ? []
              : [
                  BoxShadow(
                    color: AppColors.accent.withValues(alpha: 0.10),
                    blurRadius: 16,
                    offset: const Offset(0, 4),
                  ),
                ],
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (widget.loading)
                const SizedBox(
                  width: 20, height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2, color: AppColors.accent,
                  ),
                )
              else ...[
                SizedBox(
                  width: 22, height: 22,
                  child: CustomPaint(painter: _GoogleIconPainter()),
                ),
                const SizedBox(width: 12),
                Text(
                  'Continuar con Google',
                  style: GoogleFonts.inter(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ── Google icon ───────────────────────────────────────────────────────────────

class _GoogleIconPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final r = size.width / 2 - 1;
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round;

    p.color = const Color(0xFF4285F4);
    canvas.drawArc(Rect.fromCircle(center: Offset(cx, cy), radius: r), -2.2, 1.8, false, p);
    p.color = const Color(0xFFEA4335);
    canvas.drawArc(Rect.fromCircle(center: Offset(cx, cy), radius: r), -3.9, 1.8, false, p);
    p.color = const Color(0xFFFBBC05);
    canvas.drawArc(Rect.fromCircle(center: Offset(cx, cy), radius: r), 2.1, 1.1, false, p);
    p.color = const Color(0xFF34A853);
    canvas.drawArc(Rect.fromCircle(center: Offset(cx, cy), radius: r), 3.1, 1.0, false, p);
    p..color = const Color(0xFF4285F4)..strokeWidth = 2.0;
    canvas.drawLine(Offset(cx, cy), Offset(size.width - 1, cy), p);
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}
