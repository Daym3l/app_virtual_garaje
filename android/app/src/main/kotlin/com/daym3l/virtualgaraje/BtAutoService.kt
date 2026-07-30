package com.daym3l.virtualgaraje

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.bluetooth.BluetoothDevice
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.location.Location
import android.location.LocationListener
import android.location.LocationManager
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import org.json.JSONArray
import org.json.JSONObject
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone
import kotlin.math.atan2
import kotlin.math.cos
import kotlin.math.sin
import kotlin.math.sqrt

/**
 * Servicio en primer plano que vigila la conexión Bluetooth clásica del
 * dispositivo configurado. Al conectarse arranca el registro GPS de la ruta;
 * al desconectarse espera el timeout configurado y, si no se reconecta, la
 * finaliza y la deja en una cola local que la app (Dart) sube a Supabase.
 *
 * La configuración se lee de las SharedPreferences que escribe Flutter
 * (fichero "FlutterSharedPreferences", claves con prefijo "flutter.").
 */
class BtAutoService : Service() {
    companion object {
        const val CHANNEL_ID = "auto_route"
        const val NOTIF_ID = 7701
        private const val PREFS_FLUTTER = "FlutterSharedPreferences"
        const val PREFS_NATIVE = "bt_auto_native"
        const val KEY_CAPTURED = "captured_routes"
    }

    private val handler = Handler(Looper.getMainLooper())
    private var receiver: BroadcastReceiver? = null
    private var locationManager: LocationManager? = null
    private var locationListener: LocationListener? = null

    private var tracking = false
    private val points = JSONArray()
    private var startTimeMs = 0L
    private var totalDistanceKm = 0.0
    private var lastLat = 0.0
    private var lastLng = 0.0
    private var hasLast = false
    private var finalizeRunnable: Runnable? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        createChannel()
        startForeground(NOTIF_ID, buildNotification("Auto-ruta activa", "Esperando conexión del dispositivo"))
        registerBtReceiver()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (!isEnabled() || deviceAddress() == null) {
            stopSelf()
            return START_NOT_STICKY
        }
        return START_STICKY
    }

    override fun onDestroy() {
        receiver?.let { runCatching { unregisterReceiver(it) } }
        stopTracking()
        finalizeRunnable?.let { handler.removeCallbacks(it) }
        super.onDestroy()
    }

    // ── Config (leída de las prefs de Flutter) ──────────────────────────────────

    private fun flutterPrefs() = getSharedPreferences(PREFS_FLUTTER, Context.MODE_PRIVATE)
    private fun isEnabled() = flutterPrefs().getBoolean("flutter.route_auto_enabled", false)
    private fun deviceAddress(): String? =
        flutterPrefs().getString("flutter.route_auto_device_address", null)
    private fun vehicleId(): String? =
        flutterPrefs().getString("flutter.route_auto_active_vehicle_id", null)
    private fun timeoutMs(): Long {
        // shared_preferences guarda los int de Dart como Long.
        val min = flutterPrefs().getLong("flutter.route_auto_disconnect_timeout_min", 3L)
        return min * 60_000L
    }

    // ── Bluetooth ───────────────────────────────────────────────────────────────

    private fun registerBtReceiver() {
        val filter = IntentFilter().apply {
            addAction(BluetoothDevice.ACTION_ACL_CONNECTED)
            addAction(BluetoothDevice.ACTION_ACL_DISCONNECTED)
        }
        receiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context, intent: Intent) {
                val device: BluetoothDevice? = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                    intent.getParcelableExtra(BluetoothDevice.EXTRA_DEVICE, BluetoothDevice::class.java)
                } else {
                    @Suppress("DEPRECATION")
                    intent.getParcelableExtra(BluetoothDevice.EXTRA_DEVICE)
                }
                val target = deviceAddress() ?: return
                if (device?.address != target) return
                when (intent.action) {
                    BluetoothDevice.ACTION_ACL_CONNECTED -> onDeviceConnected()
                    BluetoothDevice.ACTION_ACL_DISCONNECTED -> onDeviceDisconnected()
                }
            }
        }
        // Broadcasts del sistema: NOT_EXPORTED es lo correcto (el sistema está
        // exento de la restricción de exportación en API 34+).
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(receiver, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            @Suppress("UnspecifiedRegisterReceiverFlag")
            registerReceiver(receiver, filter)
        }
    }

    private fun onDeviceConnected() {
        // Si veníamos de una desconexión dentro de la ventana, cancelar el cierre.
        finalizeRunnable?.let { handler.removeCallbacks(it); finalizeRunnable = null }
        if (tracking) return
        startTracking()
    }

    private fun onDeviceDisconnected() {
        if (!tracking) return
        finalizeRunnable?.let { handler.removeCallbacks(it) }
        val r = Runnable { finalizeRoute() }
        finalizeRunnable = r
        handler.postDelayed(r, timeoutMs())
        updateNotification("Ruta pausada", "Desconectado · se cerrará si no reconecta")
    }

    // ── GPS ─────────────────────────────────────────────────────────────────────

    private fun hasLocationPermission(): Boolean =
        ContextCompat.checkSelfPermission(this, android.Manifest.permission.ACCESS_FINE_LOCATION) ==
            PackageManager.PERMISSION_GRANTED

    private fun startTracking() {
        if (!hasLocationPermission()) {
            updateNotification("Auto-ruta", "Falta permiso de ubicación")
            return
        }
        tracking = true
        startTimeMs = System.currentTimeMillis()
        while (points.length() > 0) points.remove(0)
        totalDistanceKm = 0.0
        hasLast = false

        val lm = getSystemService(Context.LOCATION_SERVICE) as LocationManager
        locationManager = lm
        val listener = object : LocationListener {
            override fun onLocationChanged(location: Location) = onNewLocation(location)
            override fun onStatusChanged(provider: String?, status: Int, extras: android.os.Bundle?) {}
            override fun onProviderEnabled(provider: String) {}
            override fun onProviderDisabled(provider: String) {}
        }
        locationListener = listener
        try {
            if (lm.isProviderEnabled(LocationManager.GPS_PROVIDER)) {
                lm.requestLocationUpdates(LocationManager.GPS_PROVIDER, 2000L, 5f, listener, Looper.getMainLooper())
            }
        } catch (_: SecurityException) {}
        updateNotification("Ruta en curso", "Registrando recorrido…")
    }

    private fun onNewLocation(loc: Location) {
        if (!tracking) return
        if (hasLast) {
            totalDistanceKm += haversineKm(lastLat, lastLng, loc.latitude, loc.longitude)
        }
        lastLat = loc.latitude
        lastLng = loc.longitude
        hasLast = true
        val p = JSONObject().apply {
            put("latitude", loc.latitude)
            put("longitude", loc.longitude)
            put("timestamp", isoUtc(loc.time))
            put("speed", (loc.speed * 3.6).coerceIn(0.0, 300.0))
            put("altitude", if (loc.hasAltitude()) loc.altitude else 0.0)
        }
        points.put(p)
        updateNotification("Ruta en curso", String.format(Locale.US, "%.2f km", totalDistanceKm))
    }

    private fun stopTracking() {
        locationListener?.let { l -> runCatching { locationManager?.removeUpdates(l) } }
        locationListener = null
        tracking = false
    }

    private fun finalizeRoute() {
        finalizeRunnable = null
        if (!tracking) return
        val endTimeMs = System.currentTimeMillis()
        stopTracking()

        val vId = vehicleId()
        // Solo guardar rutas con recorrido real y vehículo conocido.
        if (vId != null && points.length() >= 2 && totalDistanceKm > 0.05) {
            val durationSec = ((endTimeMs - startTimeMs) / 1000.0).coerceAtLeast(1.0)
            val avgSpeed = totalDistanceKm / durationSec * 3600.0
            val route = JSONObject().apply {
                put("vehicle_id", vId)
                put("start_time", isoUtc(startTimeMs))
                put("end_time", isoUtc(endTimeMs))
                put("points", points)
                put("total_distance", totalDistanceKm)
                put("average_speed", avgSpeed)
            }
            appendCapturedRoute(route)
        }
        updateNotification("Auto-ruta activa", "Esperando conexión del dispositivo")
    }

    // ── Cola local (la drena Dart al abrir la app) ──────────────────────────────

    private fun appendCapturedRoute(route: JSONObject) {
        val prefs = getSharedPreferences(PREFS_NATIVE, Context.MODE_PRIVATE)
        val arr = runCatching { JSONArray(prefs.getString(KEY_CAPTURED, "[]")) }.getOrDefault(JSONArray())
        arr.put(route)
        prefs.edit().putString(KEY_CAPTURED, arr.toString()).apply()
    }

    // ── Notificación foreground ─────────────────────────────────────────────────

    private fun createChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "Auto-ruta",
                NotificationManager.IMPORTANCE_LOW,
            ).apply { description = "Registro automático de rutas por Bluetooth" }
            getSystemService(NotificationManager::class.java).createNotificationChannel(channel)
        }
    }

    private fun buildNotification(title: String, text: String): Notification =
        NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle(title)
            .setContentText(text)
            .setSmallIcon(android.R.drawable.ic_menu_mylocation)
            .setOngoing(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .build()

    private fun updateNotification(title: String, text: String) {
        getSystemService(NotificationManager::class.java)
            .notify(NOTIF_ID, buildNotification(title, text))
    }

    // ── Utilidades ──────────────────────────────────────────────────────────────

    private fun isoUtc(ms: Long): String {
        val fmt = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'", Locale.US)
        fmt.timeZone = TimeZone.getTimeZone("UTC")
        return fmt.format(Date(ms))
    }

    private fun haversineKm(lat1: Double, lon1: Double, lat2: Double, lon2: Double): Double {
        val r = 6371.0
        val dLat = Math.toRadians(lat2 - lat1)
        val dLon = Math.toRadians(lon2 - lon1)
        val a = sin(dLat / 2) * sin(dLat / 2) +
            cos(Math.toRadians(lat1)) * cos(Math.toRadians(lat2)) * sin(dLon / 2) * sin(dLon / 2)
        return r * 2 * atan2(sqrt(a), sqrt(1 - a))
    }
}
