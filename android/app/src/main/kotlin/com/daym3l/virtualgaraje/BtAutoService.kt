package com.daym3l.virtualgaraje

import android.app.AlarmManager
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothProfile
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
import android.util.Log
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
        const val KEY_EVENTS = "event_log"
        const val ACTION_FINALIZE = "com.daym3l.virtualgaraje.action.FINALIZE_ROUTE"
        const val ACTION_CHECK = "com.daym3l.virtualgaraje.action.CHECK_ROUTE"
        private const val ALARM_REQUEST = 7702
        private const val RECONCILE_REQUEST = 7704
        // Backstop por si no llega ningún broadcast: repaso frecuente pero sin
        // despertar el teléfono (se ejecuta cuando ya está despierto).
        private const val RECONCILE_INTERVAL_MS = 2 * 60_000L
        private const val CONNECTION_RECHECK_MS = 15_000L
        /// Los fixes de red tienen cientos de metros (o km) de error: mezclarlos
        /// con los de GPS inflaba la distancia. Solo valen puntos finos.
        private const val MAX_ACCURACY_M = 50f
        /// Salto entre puntos que ningún carro haría: es error de posición.
        private const val MAX_SPEED_KMH = 200.0
        private const val MIN_SEGMENT_KM = 0.005
        private const val ACTION_A2DP_STATE = "android.bluetooth.a2dp.profile.action.CONNECTION_STATE_CHANGED"
        private const val ACTION_HEADSET_STATE = "android.bluetooth.headset.profile.action.CONNECTION_STATE_CHANGED"
        private const val PERSIST_EVERY_POINTS = 5
        private const val TAG = "BtAuto"
        private const val MAX_EVENTS = 120

        /// Estado observable desde la UI (mismo proceso) para el diagnóstico.
        @Volatile var running = false
        @Volatile var state = "detenido"
        @Volatile var livePoints = 0
        @Volatile var liveDistanceKm = 0.0
        @Volatile var liveDisconnectedAt = 0L
        @Volatile var liveStartedAt = 0L

        /// Registro de eventos: la auto-ruta se prueba en la calle, sin adb, así
        /// que el historial se persiste y se muestra dentro de la app.
        fun logEvent(context: Context, msg: String) {
            Log.i(TAG, msg)
            val prefs = context.getSharedPreferences(PREFS_NATIVE, Context.MODE_PRIVATE)
            val arr = runCatching { JSONArray(prefs.getString(KEY_EVENTS, "[]")) }
                .getOrDefault(JSONArray())
            arr.put(JSONObject().put("t", System.currentTimeMillis()).put("m", msg))
            val out = if (arr.length() > MAX_EVENTS) {
                JSONArray().also { trimmed ->
                    for (i in (arr.length() - MAX_EVENTS) until arr.length()) trimmed.put(arr.get(i))
                }
            } else {
                arr
            }
            prefs.edit().putString(KEY_EVENTS, out.toString()).apply()
        }
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
    private var lastConnectionCheckMs = 0L
    private var lastFixTimeMs = 0L
    private var networkListening = false
    private var networkOnlyFallbackUsed = false
    private var lastLoggedConnected: Boolean? = null
    private var a2dpProxy: BluetoothProfile? = null
    private var headsetProxy: BluetoothProfile? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        createChannel()
        try {
            startForeground(NOTIF_ID, buildNotification("Auto-ruta activa", "Esperando conexión del dispositivo"))
            running = true
            state = "esperando"
            log("servicio iniciado (dispositivo=${deviceAddress() ?: "sin configurar"}, timeout=${timeoutMs() / 60_000}min)")
        } catch (e: Exception) {
            // Android 14 rechaza el tipo "location" sin permiso de ubicación.
            log("ERROR al arrancar en primer plano: ${e.javaClass.simpleName} ${e.message}")
            stopSelf()
            return
        }
        registerBtReceiver()
        bindProfileProxies()
        restoreProgress()
        // ACL_CONNECTED solo llega cuando la conexión ocurre; si el dispositivo
        // ya estaba conectado al arrancar el servicio (config guardada dentro
        // del carro, app reinstalada, teléfono reiniciado) el evento nunca
        // llega y la ruta no empezaría jamás.
        syncWithConnectionState()
        scheduleReconcileAlarm()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_FINALIZE -> {
                log("alarma de cierre disparada")
                finalizeRoute()
                return START_STICKY
            }
            ACTION_CHECK -> {
                finalizeIfStale()
                syncWithConnectionState()
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
        log("servicio detenido (ruta abierta=$tracking)")
        receiver?.let { runCatching { unregisterReceiver(it) } }
        cancelFinalizeAlarm()
        cancelReconcileAlarm()
        closeProfileProxies()
        // Al pararse el servicio con una ruta abierta se cierra y se guarda:
        // perder el recorrido sería peor que registrarlo con el corte de aquí.
        if (tracking) finalizeRoute()
        running = false
        state = "detenido"
        super.onDestroy()
    }

    private fun log(msg: String) = logEvent(this, msg)

    // ── Config (leída de las prefs de Flutter) ──────────────────────────────────

    private fun flutterPrefs() = getSharedPreferences(PREFS_FLUTTER, Context.MODE_PRIVATE)
    private fun nativePrefs() = getSharedPreferences(PREFS_NATIVE, Context.MODE_PRIVATE)
    private fun isEnabled() = flutterPrefs().getBoolean("flutter.route_auto_enabled", false)
    private fun deviceAddress(): String? =
        flutterPrefs().getString("flutter.route_auto_device_address", null)
    private fun vehicleId(): String? =
        flutterPrefs().getString("flutter.route_auto_active_vehicle_id", null)
    private fun deviceLabel(): String =
        flutterPrefs().getString("flutter.route_auto_device_name", null)
            ?.takeIf { it.isNotBlank() }
            ?: "dispositivo del carro"
    private fun timeoutMs(): Long {
        // shared_preferences guarda los int de Dart como Long.
        val min = flutterPrefs().getLong("flutter.route_auto_disconnect_timeout_min", 3L)
        return min * 60_000L
    }

    // ── Bluetooth ───────────────────────────────────────────────────────────────

    private fun registerBtReceiver() {
        // No basta con ACL: según el equipo y la ROM el enlace ACL puede caer o
        // mantenerse sin que llegue el broadcast, mientras que los perfiles
        // (A2DP/manos libres) sí notifican. Se escucha todo y se decide por el
        // estado real, no por el evento concreto que llegó.
        val filter = IntentFilter().apply {
            addAction(BluetoothDevice.ACTION_ACL_CONNECTED)
            addAction(BluetoothDevice.ACTION_ACL_DISCONNECTED)
            addAction(ACTION_A2DP_STATE)
            addAction(ACTION_HEADSET_STATE)
            addAction(BluetoothAdapter.ACTION_STATE_CHANGED)
            addAction(BluetoothAdapter.ACTION_CONNECTION_STATE_CHANGED)
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
                // Los eventos del adaptador (BT apagado) no traen dispositivo.
                if (device != null && device.address != target) return

                log("evento BT: ${intent.action?.substringAfterLast('.')} (${device?.address ?: "adaptador"})")
                syncWithConnectionState()
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
        val device = try {
            adapter.bondedDevices.firstOrNull { it.address == target }
        } catch (e: Exception) {
            null
        } ?: return false

        // isConnected() (oculto) mira el enlace ACL. Si el ACL cayó pero algún
        // perfil sigue activo —o al revés— cualquiera de los dos cuenta como
        // "el carro sigue conectado".
        val aclConnected = try {
            device.javaClass.getMethod("isConnected").invoke(device) as? Boolean ?: false
        } catch (e: Exception) {
            false
        }
        if (aclConnected) return true
        // Ojo: getProfileConnectionState() es del adaptador entero (un reloj
        // conectado lo daría por bueno). Hay que mirar los dispositivos
        // conectados de cada perfil y buscar el nuestro.
        return try {
            listOfNotNull(a2dpProxy, headsetProxy).any { proxy ->
                proxy.connectedDevices.any { it.address == target }
            }
        } catch (e: Exception) {
            false
        }
    }

    /// Proxies de perfil para saber, por dispositivo, si el carro sigue
    /// conectado aunque el enlace ACL no lo refleje.
    private fun bindProfileProxies() {
        val adapter = (getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager)?.adapter ?: return
        val listener = object : BluetoothProfile.ServiceListener {
            override fun onServiceConnected(profile: Int, proxy: BluetoothProfile) {
                when (profile) {
                    BluetoothProfile.A2DP -> a2dpProxy = proxy
                    BluetoothProfile.HEADSET -> headsetProxy = proxy
                }
                syncWithConnectionState()
            }

            override fun onServiceDisconnected(profile: Int) {
                when (profile) {
                    BluetoothProfile.A2DP -> a2dpProxy = null
                    BluetoothProfile.HEADSET -> headsetProxy = null
                }
            }
        }
        runCatching { adapter.getProfileProxy(this, listener, BluetoothProfile.A2DP) }
        runCatching { adapter.getProfileProxy(this, listener, BluetoothProfile.HEADSET) }
    }

    private fun closeProfileProxies() {
        val adapter = (getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager)?.adapter ?: return
        a2dpProxy?.let { runCatching { adapter.closeProfileProxy(BluetoothProfile.A2DP, it) } }
        headsetProxy?.let { runCatching { adapter.closeProfileProxy(BluetoothProfile.HEADSET, it) } }
        a2dpProxy = null
        headsetProxy = null
    }

    private fun onDeviceConnected() {
        cancelFinalizeAlarm()
        if (tracking) {
            if (paused) resumeTracking() else log("ya había una ruta en curso, nada que hacer")
            return
        }
        startTracking()
    }

    private fun onDeviceDisconnected() {
        if (!tracking) {
            log("desconexión sin ruta en curso, ignorada")
            return
        }
        if (paused) {
            log("desconexión repetida, ya estaba en espera")
            return
        }
        pauseTracking(System.currentTimeMillis())
    }

    // ── Ciclo de vida de la ruta ────────────────────────────────────────────────

    private fun startTracking() {
        if (!hasLocationPermission()) {
            log("ERROR: no se puede arrancar la ruta, falta permiso de ubicación")
            updateNotification("Auto-ruta", "Falta permiso de ubicación")
            return
        }
        log("ruta iniciada")
        tracking = true
        paused = false
        state = "en ruta"
        livePoints = 0
        liveDistanceKm = 0.0
        liveDisconnectedAt = 0L
        liveStartedAt = startTimeMs
        routeId = UUID.randomUUID().toString()
        startTimeMs = System.currentTimeMillis()
        disconnectedAtMs = 0L
        points = JSONArray()
        totalDistanceKm = 0.0
        hasLast = false
        pointsSincePersist = 0
        startLocationUpdates()
        persistProgress()
        updateNotification(
            "Ruta en curso · ${deviceLabel()}",
            "Conectado · registrando recorrido",
            startTimeMs,
        )
    }

    /**
     * Desconexión: se corta el GPS (el coche está parado, no hay recorrido que
     * registrar) y se programa el cierre. Si reconecta antes del timeout la
     * ruta continúa; el tramo sin GPS se cierra en línea recta.
     */
    private fun pauseTracking(atMs: Long) {
        paused = true
        state = "en espera"
        disconnectedAtMs = atMs
        liveDisconnectedAt = atMs
        stopLocationUpdates()
        persistProgress()
        scheduleFinalizeAlarm(timeoutMs())
        val min = timeoutMs() / 60_000L
        log("ruta en espera: ${points.length()} puntos, ${"%.2f".format(Locale.US, totalDistanceKm)} km · cierre en $min min")
        updateNotification(
            "Ruta en espera",
            "Desconectado · se cerrará en $min min si no reconecta",
            atMs,
        )
    }

    private fun resumeTracking() {
        paused = false
        state = "en ruta"
        disconnectedAtMs = 0L
        liveDisconnectedAt = 0L
        startLocationUpdates()
        persistProgress()
        log("reconectado dentro de la ventana, ruta reanudada")
        updateNotification(
            "Ruta en curso · ${deviceLabel()}",
            String.format(Locale.US, "Conectado · %.2f km", totalDistanceKm),
            startTimeMs,
        )
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
        if (vId == null) {
            log("ruta DESCARTADA: no hay vehículo activo guardado")
        } else if (points.length() < 2) {
            log("ruta DESCARTADA: solo ${points.length()} punto(s) GPS (¿ubicación desactivada o sin señal?)")
        } else if (totalDistanceKm <= 0.05) {
            log("ruta DESCARTADA: distancia ${"%.3f".format(Locale.US, totalDistanceKm)} km, por debajo del mínimo")
        }
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
            log("ruta GUARDADA: ${"%.2f".format(Locale.US, totalDistanceKm)} km, ${points.length()} puntos · pendiente de subir")
        }
        clearProgress()
        routeId = null
        points = JSONArray()
        totalDistanceKm = 0.0
        hasLast = false
        disconnectedAtMs = 0L
        state = "esperando"
        livePoints = 0
        liveDistanceKm = 0.0
        liveDisconnectedAt = 0L
        liveStartedAt = 0L
        updateNotification("Auto-ruta activa", "Esperando conexión del dispositivo")
    }

    /**
     * Reconcilia el estado de la ruta con la conexión real del dispositivo. Los
     * broadcast ACL son la vía normal, pero se pierden si el servicio no estaba
     * vivo cuando ocurrió el cambio; esto lo corrige.
     */
    private fun syncWithConnectionState() {
        if (!isEnabled() || deviceAddress() == null) return
        val connected = isTargetConnected()
        if (connected != lastLoggedConnected) {
            lastLoggedConnected = connected
            log("estado real del dispositivo: ${if (connected) "conectado" else "desconectado"}")
        }
        if (connected && !tracking) {
            log("el dispositivo ya estaba conectado, arrancando ruta")
            startTracking()
        } else if (connected && paused) {
            resumeTracking()
        } else if (!connected && tracking && !paused) {
            log("el dispositivo ya no estaba conectado, pasando a espera")
            pauseTracking(System.currentTimeMillis())
        }
    }

    /**
     * Repaso periódico por si se perdió algún broadcast ACL (proceso muerto en
     * el momento de conectar/desconectar). Inexacto: solo es una red.
     */
    private fun scheduleReconcileAlarm() {
        val am = getSystemService(AlarmManager::class.java) ?: return
        val intent = Intent(this, BtAutoService::class.java).setAction(ACTION_CHECK)
        val pi = PendingIntent.getService(
            this,
            RECONCILE_REQUEST,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        am.setInexactRepeating(
            AlarmManager.ELAPSED_REALTIME_WAKEUP,
            SystemClock.elapsedRealtime() + RECONCILE_INTERVAL_MS,
            RECONCILE_INTERVAL_MS,
            pi,
        )
    }

    private fun cancelReconcileAlarm() {
        val intent = Intent(this, BtAutoService::class.java).setAction(ACTION_CHECK)
        val pi = PendingIntent.getService(
            this,
            RECONCILE_REQUEST,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        getSystemService(AlarmManager::class.java)?.cancel(pi)
    }

    /** Cierra la ruta si ya venció el timeout (red de seguridad si la alarma no corrió). */
    private fun finalizeIfStale() {
        if (!tracking || !paused || disconnectedAtMs <= 0) return
        if (System.currentTimeMillis() - disconnectedAtMs >= timeoutMs()) {
            log("timeout vencido detectado al abrir la app, cerrando ruta")
            finalizeRoute()
        }
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
        log("cierre programado en ${delayMs / 1000}s (alarma ${if (exact) "exacta" else "inexacta"})")
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
        if (!hasLocationPermission()) {
            log("ERROR: sin permiso de ubicación, no hay registro GPS")
            return
        }
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
        val gpsOk = requestProvider(lm, listener, LocationManager.GPS_PROVIDER)
        // La red solo es un puente hasta que el GPS fije: sus fixes tienen
        // cientos de metros de error y no sirven para medir el recorrido.
        networkOnlyFallbackUsed = requestProvider(lm, listener, LocationManager.NETWORK_PROVIDER)
        networkListening = networkOnlyFallbackUsed

        if (!gpsOk && !networkListening) {
            locationListener = null
            log("ERROR: no hay proveedores de ubicación activos (¿ubicación del teléfono apagada?)")
            return
        }
        log("registro de ubicación activo: ${if (gpsOk) "gps" else ""}${if (gpsOk && networkListening) " + " else ""}${if (networkListening) "red (provisional)" else ""}")

        // El primer fix de GPS puede tardar minutos. Sembrar con la última
        // posición conocida evita que un trayecto corto se quede sin puntos,
        // pero solo si es reciente y fina: una vieja falsearía la distancia.
        if (points.length() == 0) {
            val last = try {
                lm.getLastKnownLocation(LocationManager.GPS_PROVIDER)
            } catch (e: SecurityException) {
                null
            }
            if (last != null &&
                System.currentTimeMillis() - last.time < 2 * 60_000L &&
                (!last.hasAccuracy() || last.accuracy <= MAX_ACCURACY_M)
            ) {
                onNewLocation(last)
                log("posición inicial tomada de la última conocida")
            }
        }
    }

    private fun requestProvider(lm: LocationManager, listener: LocationListener, provider: String): Boolean =
        try {
            if (lm.isProviderEnabled(provider)) {
                lm.requestLocationUpdates(provider, 2000L, 5f, listener, Looper.getMainLooper())
                true
            } else {
                false
            }
        } catch (e: SecurityException) {
            log("ERROR al pedir ubicación ($provider): ${e.message}")
            false
        } catch (e: IllegalArgumentException) {
            false
        }

    /// En cuanto el GPS entrega un fix la red sobra: se corta para que sus
    /// puntos gruesos no entren en el cálculo de distancia.
    private fun stopNetworkUpdates() {
        networkListening = false
        val lm = locationManager ?: return
        val listener = locationListener ?: return
        // removeUpdates() no distingue proveedor: se rehace el registro solo
        // con GPS.
        runCatching { lm.removeUpdates(listener) }
        requestProvider(lm, listener, LocationManager.GPS_PROVIDER)
        log("GPS fijado, se deja de usar la ubicación por red")
    }

    private fun stopLocationUpdates() {
        locationListener?.let { l -> runCatching { locationManager?.removeUpdates(l) } }
        locationListener = null
        networkListening = false
        networkOnlyFallbackUsed = false
    }

    private fun onNewLocation(loc: Location) {
        if (!tracking || paused) return

        // Un fix impreciso (red, GPS sin fijar) mueve la posición cientos de
        // metros sin que el carro se mueva: cuenta como recorrido y dispara la
        // distancia. Mejor perder el punto que inventar kilómetros.
        if (loc.hasAccuracy() && loc.accuracy > MAX_ACCURACY_M) return
        // En cuanto hay GPS se deja de escuchar la red, que solo servía para
        // no quedarse sin ningún punto al principio.
        if (loc.provider == LocationManager.GPS_PROVIDER && networkListening) stopNetworkUpdates()
        if (networkOnlyFallbackUsed && loc.provider != LocationManager.GPS_PROVIDER && hasLast) return

        if (hasLast) {
            val segmentKm = haversineKm(lastLat, lastLng, loc.latitude, loc.longitude)
            val dtHours = ((loc.time - lastFixTimeMs).coerceAtLeast(1L)) / 3_600_000.0
            val impliedKmh = segmentKm / dtHours
            if (impliedKmh > MAX_SPEED_KMH) {
                log("punto descartado: salto de ${"%.2f".format(Locale.US, segmentKm)} km (${impliedKmh.toInt()} km/h)")
                return
            }
            if (segmentKm >= MIN_SEGMENT_KM) totalDistanceKm += segmentKm
        }
        lastLat = loc.latitude
        lastLng = loc.longitude
        lastFixTimeMs = loc.time
        hasLast = true
        val p = JSONObject().apply {
            put("latitude", loc.latitude)
            put("longitude", loc.longitude)
            put("timestamp", isoUtc(loc.time))
            put("speed", (loc.speed * 3.6).coerceIn(0.0, 300.0))
            put("altitude", if (loc.hasAltitude()) loc.altitude else 0.0)
        }
        points.put(p)
        livePoints = points.length()
        liveDistanceKm = totalDistanceKm
        state = "en ruta"
        val now = System.currentTimeMillis()
        if (now - lastConnectionCheckMs > CONNECTION_RECHECK_MS) {
            lastConnectionCheckMs = now
            syncWithConnectionState()
        }
        if (++pointsSincePersist >= PERSIST_EVERY_POINTS) {
            pointsSincePersist = 0
            persistProgress()
        }
        updateNotification(
            "Ruta en curso · ${deviceLabel()}",
            String.format(Locale.US, "Conectado · %.2f km · %d puntos", totalDistanceKm, points.length()),
            startTimeMs,
        )
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
        livePoints = points.length()
        liveDistanceKm = totalDistanceKm
        liveStartedAt = startTimeMs
        log("ruta en curso recuperada: ${points.length()} puntos, ${"%.2f".format(Locale.US, totalDistanceKm)} km, pausada=$paused")

        if (paused) {
            state = "en espera"
            liveDisconnectedAt = disconnectedAtMs
            val elapsed = System.currentTimeMillis() - disconnectedAtMs
            if (disconnectedAtMs <= 0 || elapsed >= timeoutMs()) {
                log("el timeout ya había vencido, cerrando")
                finalizeRoute()
            } else {
                scheduleFinalizeAlarm(timeoutMs() - elapsed)
            }
            return
        }
        // Estábamos conectados cuando murió el proceso: si el dispositivo sigue
        // conectado se reanuda; si no, se cuenta como desconexión de ahora.
        if (isTargetConnected()) {
            state = "en ruta"
            startLocationUpdates()
            updateNotification(
                "Ruta en curso · ${deviceLabel()}",
                String.format(Locale.US, "Conectado · %.2f km", totalDistanceKm),
                startTimeMs,
            )
        } else {
            log("el dispositivo ya no está conectado, se cuenta como desconexión")
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

    /// Al tocar la notificación se abre la app en Rutas, donde se ve la ruta
    /// que se está registrando ahora mismo.
    private fun contentIntent(): PendingIntent {
        val intent = Intent(this, MainActivity::class.java)
            .setAction(Intent.ACTION_MAIN)
            .addCategory(Intent.CATEGORY_LAUNCHER)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
            .putExtra(MainActivity.EXTRA_OPEN_TAB, "routes")
        val flags = PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        return PendingIntent.getActivity(this, 7703, intent, flags)
    }

    /**
     * @param since instante desde el que contar el cronómetro (inicio de la
     * ruta o de la espera); null deja la notificación sin contador.
     */
    private fun buildNotification(title: String, text: String, since: Long? = null): Notification {
        val builder = NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle(title)
            .setContentText(text)
            .setSmallIcon(android.R.drawable.ic_menu_mylocation)
            .setOngoing(true)
            .setContentIntent(contentIntent())
            .setPriority(NotificationCompat.PRIORITY_LOW)
        if (since != null && since > 0) {
            // El cronómetro lo pinta el sistema: se actualiza solo, sin que el
            // servicio tenga que despertar cada segundo.
            builder.setWhen(since).setShowWhen(true).setUsesChronometer(true)
        } else {
            builder.setShowWhen(false).setUsesChronometer(false)
        }
        return builder.build()
    }

    private fun updateNotification(title: String, text: String, since: Long? = null) {
        getSystemService(NotificationManager::class.java)
            .notify(NOTIF_ID, buildNotification(title, text, since))
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
