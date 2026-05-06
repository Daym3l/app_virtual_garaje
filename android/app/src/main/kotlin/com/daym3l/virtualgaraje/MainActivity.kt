package com.daym3l.virtualgaraje

import android.app.NotificationChannel
import android.app.NotificationManager
import android.os.Build
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                "maintenance_alerts",
                "Alertas de Mantenimiento",
                NotificationManager.IMPORTANCE_HIGH,
            ).apply {
                description = "Notificaciones de mantenimientos próximos y vencidos"
            }
            val manager = getSystemService(NotificationManager::class.java)
            manager.createNotificationChannel(channel)
        }
    }
}
