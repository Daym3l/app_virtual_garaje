import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'services/auth_service.dart';
import 'theme/app_theme.dart';
import 'screens/login_screen.dart';
import 'screens/shell_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: 'https://xhriebayxtznjehmldhv.supabase.co',
    anonKey:
        'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InhocmllYmF5eHR6bmplaG1sZGh2Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzcyODY5MTAsImV4cCI6MjA5Mjg2MjkxMH0.BnpaeDUe2joTRHe-9CyEOdOlvCqmyTkxxPYU2UgEpco',
  );

  await AuthService.initialize();

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
  bool _loggedIn = false;

  @override
  void initState() {
    super.initState();
    _loggedIn = AuthService.currentSession != null;

    Supabase.instance.client.auth.onAuthStateChange.listen((data) {
      if (!mounted) return;
      setState(() => _loggedIn = data.session != null);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loggedIn) {
      return const ShellScreen();
    }
    return const LoginScreen();
  }
}
