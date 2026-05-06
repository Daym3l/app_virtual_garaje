import 'package:google_sign_in/google_sign_in.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/env.dart';
import 'fcm_service.dart';

final _googleSignIn = GoogleSignIn(
  serverClientId: Env.googleServerClientId,
);

class AuthService {
  static SupabaseClient get _supabase => Supabase.instance.client;

  static Future<void> initialize() async {}

  static Future<AuthResponse> signInWithGoogle() async {
    final googleUser = await _googleSignIn.signIn();
    if (googleUser == null) throw Exception('Google sign-in cancelled');

    final googleAuth = await googleUser.authentication;
    final idToken = googleAuth.idToken;
    final accessToken = googleAuth.accessToken;

    if (idToken == null) throw Exception('No ID token from Google');

    return _supabase.auth.signInWithIdToken(
      provider: OAuthProvider.google,
      idToken: idToken,
      accessToken: accessToken,
    );
  }

  static Future<void> signOut() async {
    await FcmService().clearToken();
    await Future.wait([
      _googleSignIn.signOut(),
      _supabase.auth.signOut(),
    ]);
  }

  static Session? get currentSession => _supabase.auth.currentSession;
  static User? get currentUser => _supabase.auth.currentUser;
}
