import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'config/env.dart';
import 'services/auth_service.dart';
import 'services/fcm_service.dart';
import 'services/route_service.dart';
import 'theme/app_theme.dart';
import 'screens/login_screen.dart';
import 'screens/shell_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp();

  await Supabase.initialize(
    url: Env.supabaseUrl,
    anonKey: Env.supabaseAnonKey,
  );

  await AuthService.initialize();
  await FcmService().init();

  runApp(const GarajeApp());
}

class GarajeApp extends StatelessWidget {
  const GarajeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Mi Garaje Virtual',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      home: const _AuthGate(),
    );
  }
}

class _AuthGate extends StatefulWidget {
  const _AuthGate();

  @override
  State<_AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<_AuthGate> {
  bool? _loggedIn;

  @override
  void initState() {
    super.initState();
    _loggedIn = AuthService.currentSession != null;
    if (_loggedIn!) _syncPendingRoutes();

    Supabase.instance.client.auth.onAuthStateChange.listen((data) {
      if (!mounted) return;
      final loggedIn = data.session != null;
      setState(() => _loggedIn = loggedIn);
      if (loggedIn) _syncPendingRoutes();
    });
  }

  void _syncPendingRoutes() {
    RouteService.syncPending().catchError((_) => 0);
  }

  @override
  Widget build(BuildContext context) {
    if (_loggedIn == null) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(
            color: AppColors.accent,
            strokeWidth: 2,
          ),
        ),
      );
    }
    if (_loggedIn!) return const ShellScreen();
    return const LoginScreen();
  }
}
