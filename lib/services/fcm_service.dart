import 'dart:async';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

@pragma('vm:entry-point')
Future<void> _backgroundHandler(RemoteMessage message) async {}

class FcmService {
  static final navigateToMaintenance = StreamController<void>.broadcast();

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

    // App abierta desde notif con app cerrada
    final initial = await _messaging.getInitialMessage();
    if (initial != null) _onNotificationTap(initial);
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

  void _onForegroundMessage(RemoteMessage message) {}

  void _onNotificationTap(RemoteMessage message) {
    navigateToMaintenance.add(null);
  }
}
