package com.daym3l.virtualgaraje

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build

/**
 * Relanza el servicio de auto-ruta tras reiniciar el teléfono. Sin esto la
 * vigilancia solo se reanudaba al abrir la app, así que un reinicio dejaba de
 * registrar rutas sin que se notara.
 */
class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Intent.ACTION_BOOT_COMPLETED &&
            intent.action != Intent.ACTION_MY_PACKAGE_REPLACED
        ) {
            return
        }
        val prefs = context.getSharedPreferences(
            "FlutterSharedPreferences",
            Context.MODE_PRIVATE,
        )
        val enabled = prefs.getBoolean("flutter.route_auto_enabled", false)
        val address = prefs.getString("flutter.route_auto_device_address", null)
        if (!enabled || address.isNullOrEmpty()) return

        BtAutoService.logEvent(context, "reinicio del sistema: relanzando el servicio")
        val service = Intent(context, BtAutoService::class.java)
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(service)
            } else {
                context.startService(service)
            }
        } catch (e: Exception) {
            BtAutoService.logEvent(context, "ERROR al relanzar tras el reinicio: ${e.message}")
        }
    }
}
