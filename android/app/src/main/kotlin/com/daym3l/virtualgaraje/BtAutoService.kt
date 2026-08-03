package com.daym3l.virtualgaraje

import android.app.AlarmManager
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.location.Location
import android.location.LocationListener
import android.location.LocationManager
import android.os.Build
import android.os.IBinder
import android.os.Looper
import android.os.SystemClock
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import org.json.JSONArray
import org.json.JSONObject
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone
import java.util.UUID
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
 * El cierre se programa con AlarmManager, no con Handler: el teléfono entra en
 * Doze con la pantalla apagada y los callbacks diferidos del handler no
 * despiertan la CPU, así que la ruta se quedaba abierta indefinidamente.
 *
 * El estado de la ruta en curso se persiste en las prefs nativas tras cada
 * cambio relevante: si el sistema mata el proceso, al reiniciarse el servicio
 * la retoma (o la cierra, si ya venció el timeout) en vez de perderla.
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
        const val KEY_PROGRESS = "route_in_progress"
        const val ACTION_FINALIZE = "com.daym3l.virtualgaraje.action.FINALIZE_ROUTE"
        const val ACTION_CHECK = "com.daym3l.virtualgaraje.action.CHECK_ROUTE"
        private const val ALARM_REQUEST = 7702
        private const val PERSIST_EVERY_POINTS = 5
    }

    private var receiver: BroadcastReceiver? = null
    private var locationManager: LocationManager? = null
    private var locationListener: LocationListener? = null

    private var tracking = false
    private var paused = false
    private var routeId: String? = null
    private var points = JSONArray()
    private var startTimeMs = 0L
    private var disconnectedAtMs = 0L
    private var totalDistanceKm = 0.0
    private var lastLat = 0.0
    private var lastLng = 0.0
    private var hasLast = false
    private var pointsSincePersist = 0

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        createChannel()
        startForeground(NOTIF_ID, buildNotification("Auto-ruta activa", "Esperando conexión del dispositivo"))
        registerBtReceiver()
        restoreProgress()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_FINALIZE -> {
                finalizeRoute()
                return START_STICKY
            }
            ACTION_CHECK -> {
                finalizeIfStale()
                // La app puede lanzar el chequeo con la auto-ruta ya desactivada:
                // en ese caso el servicio no debe quedarse vivo.
                if (!isEnabled() || deviceAddress() == null) {
                    stopSelf()
                    return START_NOT_STICKY
                }
                return START_STICKY
            }
        }
        if (!isEnabled() || deviceAddress() == null) {
            stopSelf()
            return START_NOT_STICKY
        }
        return START_STICKY
    }

    override fun onDestroy() {
        receiver?.let { runCatching { unregisterReceiver(it) } }
        cancelFinalizeAlarm()
        // Al pararse el servicio con una ruta abierta se cierra y se guarda:
        // perder el recorrido sería peor que registrarlo con el corte de aquí.
        if (tracking) finalizeRoute()
        super.onDestroy()
    }

    // ── Config (leída de las prefs de Flutter) ──────────────────────────────────

    private fun flutterPrefs() = getSharedPreferences(PREFS_FLUTTER, Context.MODE_PRIVATE)
    private fun nativePrefs() = getSharedPreferences(PREFS_NATIVE, Context.MODE_PRIVATE)
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

    private fun isTargetConnected(): Boolean {
        val target = deviceAddress() ?: return false
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S &&
            ContextCompat.checkSelfPermission(this, android.Manifest.permission.BLUETOOTH_CONNECT) !=
            PackageManager.PERMISSION_GRANTED
        ) {
            return false
        }
        val adapter = (getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager)?.adapter
            ?: return false
        return try {
            val device = adapter.bondedDevices.firstOrNull { it.address == target } ?: return false
            device.javaClass.getMethod("isConnected").invoke(device) as? Boolean ?: false
        } catch (e: Exception) {
            false
        }
    }

    private fun onDeviceConnected() {
        cancelFinalizeAlarm()
        if (tracking) {
            if (paused) resumeTracking()
            return
        }
        startTracking()
    }

    private fun onDeviceDisconnected() {
        if (!tracking || paused) return
        pauseTracking(System.currentTimeMillis())
    }

    // ── Ciclo de vida de la ruta ────────────────────────────────────────────────

    private fun startTracking() {
        if (!hasLocationPermission()) {
            updateNotification("Auto-ruta", "Falta permiso de ubicación")
            return
        }
        tracking = true
        paused = false
        routeId = UUID.randomUUID().toString()
        startTimeMs = System.currentTimeMillis()
        disconnectedAtMs = 0L
        points = JSONArray()
        totalDistanceKm = 0.0
        hasLast = false
        pointsSincePersist = 0
        startLocationUpdates()
        persistProgress()
        updateNotification("Ruta en curso", "Registrando recorrido…")
    }

    /**
     * Desconexión: se corta el GPS (el coche está parado, no hay recorrido que
     * registrar) y se programa el cierre. Si reconecta antes del timeout la
     * ruta continúa; el tramo sin GPS se cierra en línea recta.
     */
    private fun pauseTracking(atMs: Long) {
        paused = true
        disconnectedAtMs = atMs
        stopLocationUpdates()
        persistProgress()
        scheduleFinalizeAlarm(timeoutMs())
        val min = timeoutMs() / 60_000L
        updateNotification("Ruta pausada", "Desconectado · se cerrará en $min min si no reconecta")
    }

    private fun resumeTracking() {
        paused = false
        disconnectedAtMs = 0L
        startLocationUpdates()
        persistProgress()
        updateNotification("Ruta en curso", String.format(Locale.US, "%.2f km", totalDistanceKm))
    }

    /**
     * Cierra la ruta y la deja en la cola local. El fin es el momento real de
     * la desconexión, no el de esta llamada: la alarma puede dispararse tarde
     * si el teléfono estaba en Doze y eso inflaría la duración.
     */
    private fun finalizeRoute() {
        cancelFinalizeAlarm()
        if (!tracking) return
        val endTimeMs = if (disconnectedAtMs > 0) disconnectedAtMs else System.currentTimeMillis()
        stopLocationUpdates()
        tracking = false
        paused = false

        val vId = vehicleId()
        // Solo guardar rutas con recorrido real y vehículo conocido.
        if (vId != null && points.length() >= 2 && totalDistanceKm > 0.05) {
            val durationSec = ((endTimeMs - startTimeMs) / 1000.0).coerceAtLeast(1.0)
            val avgSpeed = totalDistanceKm / durationSec * 3600.0
            val route = JSONObject().apply {
                // id estable: si la ruta se importa dos veces, el upsert de
                // Supabase la reconoce y el odómetro no se suma por duplicado.
                put("route_id", routeId ?: UUID.randomUUID().toString())
                put("vehicle_id", vId)
                put("start_time", isoUtc(startTimeMs))
                put("end_time", isoUtc(endTimeMs))
                put("points", points)
                put("total_distance", totalDistanceKm)
                put("average_speed", avgSpeed)
            }
            appendCapturedRoute(route)
        }
        clearProgress()
        routeId = null
        points = JSONArray()
        totalDistanceKm = 0.0
        hasLast = false
        disconnectedAtMs = 0L
        updateNotification("Auto-ruta activa", "Esperando conexión del dispositivo")
    }

    /** Cierra la ruta si ya venció el timeout (red de seguridad si la alarma no corrió). */
    private fun finalizeIfStale() {
        if (!tracking || !paused || disconnectedAtMs <= 0) return
        if (System.currentTimeMillis() - disconnectedAtMs >= timeoutMs()) finalizeRoute()
    }

    // ── Alarma de cierre ────────────────────────────────────────────────────────

    private fun finalizePendingIntent(): PendingIntent {
        val intent = Intent(this, BtAutoService::class.java).setAction(ACTION_FINALIZE)
        val flags = PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        return PendingIntent.getService(this, ALARM_REQUEST, intent, flags)
    }

    private fun scheduleFinalizeAlarm(delayMs: Long) {
        val am = getSystemService(AlarmManager::class.java) ?: return
        val triggerAt = SystemClock.elapsedRealtime() + delayMs.coerceAtLeast(0)
        val pi = finalizePendingIntent()
        val exact = Build.VERSION.SDK_INT < Build.VERSION_CODES.S || am.canScheduleExactAlarms()
        try {
            if (exact) {
                am.setExactAndAllowWhileIdle(AlarmManager.ELAPSED_REALTIME_WAKEUP, triggerAt, pi)
            } else {
                // Sin permiso de alarmas exactas: en Doze puede retrasarse, pero
                // el fin de la ruta es la hora de desconexión, así que el retraso
                // solo demora el guardado, no falsea los datos.
                am.setAndAllowWhileIdle(AlarmManager.ELAPSED_REALTIME_WAKEUP, triggerAt, pi)
            }
        } catch (e: SecurityException) {
            am.setAndAllowWhileIdle(AlarmManager.ELAPSED_REALTIME_WAKEUP, triggerAt, pi)
        }
    }

    private fun cancelFinalizeAlarm() {
        getSystemService(AlarmManager::class.java)?.cancel(finalizePendingIntent())
    }

    // ── GPS ─────────────────────────────────────────────────────────────────────

    private fun hasLocationPermission(): Boolean =
        ContextCompat.checkSelfPermission(this, android.Manifest.permission.ACCESS_FINE_LOCATION) ==
            PackageManager.PERMISSION_GRANTED

    private fun startLocationUpdates() {
        if (!hasLocationPermission()) return
        if (locationListener != null) return
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
        } catch (e: SecurityException) {
            locationListener = null
        }
    }

    private fun stopLocationUpdates() {
        locationListener?.let { l -> runCatching { locationManager?.removeUpdates(l) } }
        locationListener = null
    }

    private fun onNewLocation(loc: Location) {
        if (!tracking || paused) return
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
        if (++pointsSincePersist >= PERSIST_EVERY_POINTS) {
            pointsSincePersist = 0
            persistProgress()
        }
        updateNotification("Ruta en curso", String.format(Locale.US, "%.2f km", totalDistanceKm))
    }

    // ── Persistencia de la ruta en curso ────────────────────────────────────────

    private fun persistProgress() {
        if (!tracking) return
        val json = JSONObject().apply {
            put("route_id", routeId)
            put("start_time_ms", startTimeMs)
            put("disconnected_at_ms", disconnectedAtMs)
            put("paused", paused)
            put("total_distance", totalDistanceKm)
            put("last_lat", lastLat)
            put("last_lng", lastLng)
            put("has_last", hasLast)
            put("points", points)
        }
        nativePrefs().edit().putString(KEY_PROGRESS, json.toString()).apply()
    }

    private fun clearProgress() {
        nativePrefs().edit().remove(KEY_PROGRESS).apply()
    }

    private fun restoreProgress() {
        val raw = nativePrefs().getString(KEY_PROGRESS, null) ?: return
        val json = runCatching { JSONObject(raw) }.getOrNull() ?: run { clearProgress(); return }

        routeId = json.optString("route_id").takeIf { it.isNotBlank() } ?: UUID.randomUUID().toString()
        startTimeMs = json.optLong("start_time_ms", System.currentTimeMillis())
        disconnectedAtMs = json.optLong("disconnected_at_ms", 0L)
        paused = json.optBoolean("paused", false)
        totalDistanceKm = json.optDouble("total_distance", 0.0)
        lastLat = json.optDouble("last_lat", 0.0)
        lastLng = json.optDouble("last_lng", 0.0)
        hasLast = json.optBoolean("has_last", false)
        points = json.optJSONArray("points") ?: JSONArray()
        tracking = true
        pointsSincePersist = 0

        if (paused) {
            val elapsed = System.currentTimeMillis() - disconnectedAtMs
            if (disconnectedAtMs <= 0 || elapsed >= timeoutMs()) finalizeRoute()
            else scheduleFinalizeAlarm(timeoutMs() - elapsed)
            return
        }
        // Estábamos conectados cuando murió el proceso: si el dispositivo sigue
        // conectado se reanuda; si no, se cuenta como desconexión de ahora.
        if (isTargetConnected()) {
            startLocationUpdates()
            updateNotification("Ruta en curso", String.format(Locale.US, "%.2f km", totalDistanceKm))
        } else {
            pauseTracking(System.currentTimeMillis())
        }
    }

    // ── Cola local (la drena Dart al abrir la app) ──────────────────────────────

    private fun appendCapturedRoute(route: JSONObject) {
        val prefs = nativePrefs()
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
