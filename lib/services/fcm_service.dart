import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

@pragma('vm:entry-point')
Future<void> _backgroundHandler(RemoteMessage message) async {}

class FcmService {
  final _messaging = FirebaseMessaging.instance;
  final _supabase = Supabase.instance.client;

  Future<void> init() async {
    FirebaseMessaging.onBackgroundMessage(_backgroundHandler);

    final settings = await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    if (settings.authorizationStatus == AuthorizationStatus.authorized) {
      final token = await _messaging.getToken();
      if (token != null) await _saveToken(token);
      _messaging.onTokenRefresh.listen(_saveToken);
    }

    FirebaseMessaging.onMessage.listen(_onForegroundMessage);
    FirebaseMessaging.onMessageOpenedApp.listen(_onNotificationTap);
  }

  Future<void> _saveToken(String token) async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return;

    await _supabase.from('user_profiles').update({
      'fcm_token': token,
      'fcm_token_updated_at': DateTime.now().toIso8601String(),
    }).eq('id', userId);
  }

  Future<void> clearToken() async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return;

    await _supabase.from('user_profiles').update({
      'fcm_token': null,
      'fcm_token_updated_at': null,
    }).eq('id', userId);
  }

  void _onForegroundMessage(RemoteMessage message) {
    // App en primer plano — FCM no muestra notif automáticamente en Android
    // La pantalla de mantenimiento puede escuchar este stream si necesita reaccionar
  }

  void _onNotificationTap(RemoteMessage message) {
    // Usuario tocó notif con app en background
    // Navegar a mantenimiento cuando esté implementada esa pantalla
  }
}
