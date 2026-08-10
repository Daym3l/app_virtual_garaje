package com.daym3l.virtualgaraje

import android.Manifest
import android.app.AlarmManager
import android.app.NotificationChannel
import android.app.NotificationManager
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothManager
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.location.LocationManager
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.os.Bundle
import android.provider.Settings
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    companion object {
        /// Pestaña a abrir cuando la app se lanza desde la notificación de la
        /// auto-ruta. Dart la consume al arrancar y al volver a primer plano.
        const val EXTRA_OPEN_TAB = "open_tab"
        @Volatile private var pendingTab: String? = null
    }

    private val channelName = "virtualgaraje/bt_auto"
    private val btPermissionRequestCode = 4231
    private val notifPermissionRequestCode = 4232
    private val backgroundLocationRequestCode = 4233
    private var pendingPermissionResult: MethodChannel.Result? = null
    private var pendingNotifPermissionResult: MethodChannel.Result? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        intent?.getStringExtra(EXTRA_OPEN_TAB)?.let { pendingTab = it }
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

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        intent.getStringExtra(EXTRA_OPEN_TAB)?.let { pendingTab = it }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "ensurePermission" -> ensurePermission(result)
                    "ensureNotificationPermission" -> ensureNotificationPermission(result)
                    "getBondedDevices" -> getBondedDevices(result)
                    "isConnected" -> isConnected(call.argument<String>("address"), result)
                    "startService" -> startBtService(result)
                    "stopService" -> stopBtService(result)
                    "drainCapturedRoutes" -> drainCapturedRoutes(result)
                    "checkPendingRoute" -> checkPendingRoute(result)
                    "diagnostics" -> diagnostics(result)
                    "requestBatteryExemption" -> requestBatteryExemption(result)
                    "requestBackgroundLocation" -> requestBackgroundLocation(result)
                    "clearEventLog" -> clearEventLog(result)
                    "consumePendingTab" -> {
                        result.success(pendingTab)
                        pendingTab = null
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun hasBtConnectPermission(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) return true
        return ContextCompat.checkSelfPermission(
            this,
            Manifest.permission.BLUETOOTH_CONNECT,
        ) == PackageManager.PERMISSION_GRANTED
    }

    private fun ensurePermission(result: MethodChannel.Result) {
        if (hasBtConnectPermission()) {
            result.success(true)
            return
        }
        pendingPermissionResult = result
        ActivityCompat.requestPermissions(
            this,
            arrayOf(Manifest.permission.BLUETOOTH_CONNECT),
            btPermissionRequestCode,
        )
    }

    /// Sin POST_NOTIFICATIONS (Android 13+) el servicio corre pero su
    /// notificación no se ve, y el usuario no sabe si está registrando.
    private fun ensureNotificationPermission(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) {
            result.success(true)
            return
        }
        if (ContextCompat.checkSelfPermission(this, Manifest.permission.POST_NOTIFICATIONS) ==
            PackageManager.PERMISSION_GRANTED
        ) {
            result.success(true)
            return
        }
        pendingNotifPermissionResult = result
        ActivityCompat.requestPermissions(
            this,
            arrayOf(Manifest.permission.POST_NOTIFICATIONS),
            notifPermissionRequestCode,
        )
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        val granted = grantResults.isNotEmpty() &&
            grantResults[0] == PackageManager.PERMISSION_GRANTED
        if (requestCode == btPermissionRequestCode) {
            pendingPermissionResult?.success(granted)
            pendingPermissionResult = null
        } else if (requestCode == notifPermissionRequestCode) {
            pendingNotifPermissionResult?.success(granted)
            pendingNotifPermissionResult = null
        }
    }

    private fun startBtService(result: MethodChannel.Result) {
        val intent = Intent(this, BtAutoService::class.java)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            startForegroundService(intent)
        } else {
            startService(intent)
        }
        result.success(null)
    }

    private fun stopBtService(result: MethodChannel.Result) {
        stopService(Intent(this, BtAutoService::class.java))
        result.success(null)
    }

    /// Red de seguridad: fuerza al servicio a cerrar una ruta cuyo timeout de
    /// desconexión ya venció, por si la alarma se retrasó en Doze.
    private fun checkPendingRoute(result: MethodChannel.Result) {
        val intent = Intent(this, BtAutoService::class.java).setAction(BtAutoService.ACTION_CHECK)
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                startForegroundService(intent)
            } else {
                startService(intent)
            }
        } catch (e: Exception) {
            // El servicio puede estar detenido (auto-ruta desactivada): sin efecto.
        }
        result.success(null)
    }

    private fun drainCapturedRoutes(result: MethodChannel.Result) {
        val prefs = getSharedPreferences(BtAutoService.PREFS_NATIVE, Context.MODE_PRIVATE)
        val raw = prefs.getString(BtAutoService.KEY_CAPTURED, "[]")
        prefs.edit().remove(BtAutoService.KEY_CAPTURED).apply()
        result.success(raw)
    }

    /// Estado del servicio + permisos del sistema + historial de eventos. La
    /// auto-ruta se prueba conduciendo, sin acceso a logcat: el diagnóstico
    /// tiene que verse dentro de la app.
    private fun diagnostics(result: MethodChannel.Result) {
        val lm = getSystemService(Context.LOCATION_SERVICE) as? LocationManager
        val alarms = getSystemService(AlarmManager::class.java)
        val nativePrefs = getSharedPreferences(BtAutoService.PREFS_NATIVE, Context.MODE_PRIVATE)
        val captured = runCatching {
            org.json.JSONArray(nativePrefs.getString(BtAutoService.KEY_CAPTURED, "[]")).length()
        }.getOrDefault(0)

        result.success(
            mapOf(
                "service_running" to BtAutoService.running,
                "state" to BtAutoService.state,
                "points" to BtAutoService.livePoints,
                "distance_km" to BtAutoService.liveDistanceKm,
                "disconnected_at" to BtAutoService.liveDisconnectedAt,
                "started_at" to BtAutoService.liveStartedAt,
                "captured_pending" to captured,
                "has_progress" to (nativePrefs.getString(BtAutoService.KEY_PROGRESS, null) != null),
                "device_connected" to isTargetConnectedNow(),
                "perm_location" to (
                    ContextCompat.checkSelfPermission(this, Manifest.permission.ACCESS_FINE_LOCATION) ==
                        PackageManager.PERMISSION_GRANTED
                    ),
                "perm_location_background" to (
                    Build.VERSION.SDK_INT < Build.VERSION_CODES.Q ||
                        ContextCompat.checkSelfPermission(this, Manifest.permission.ACCESS_BACKGROUND_LOCATION) ==
                        PackageManager.PERMISSION_GRANTED
                    ),
                "perm_bluetooth" to hasBtConnectPermission(),
                "perm_notifications" to (
                    Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU ||
                        ContextCompat.checkSelfPermission(this, Manifest.permission.POST_NOTIFICATIONS) ==
                        PackageManager.PERMISSION_GRANTED
                    ),
                "gps_enabled" to (lm?.isProviderEnabled(LocationManager.GPS_PROVIDER) ?: false),
                "battery_unrestricted" to isBatteryUnrestricted(),
                "exact_alarms" to (
                    Build.VERSION.SDK_INT < Build.VERSION_CODES.S || alarms?.canScheduleExactAlarms() == true
                    ),
                "events" to (nativePrefs.getString(BtAutoService.KEY_EVENTS, "[]") ?: "[]"),
            ),
        )
    }

    /// Sin ACCESS_BACKGROUND_LOCATION el sistema no deja arrancar un servicio
    /// en primer plano de tipo "location" desde segundo plano, así que la
    /// auto-ruta no se reanuda tras reiniciar el teléfono ni al actualizar.
    /// Desde Android 11 el permiso solo se concede desde los ajustes.
    private fun requestBackgroundLocation(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
            result.success(true)
            return
        }
        if (ContextCompat.checkSelfPermission(this, Manifest.permission.ACCESS_BACKGROUND_LOCATION) ==
            PackageManager.PERMISSION_GRANTED
        ) {
            result.success(true)
            return
        }
        if (Build.VERSION.SDK_INT == Build.VERSION_CODES.Q) {
            ActivityCompat.requestPermissions(
                this,
                arrayOf(Manifest.permission.ACCESS_BACKGROUND_LOCATION),
                backgroundLocationRequestCode,
            )
        } else {
            runCatching {
                startActivity(
                    Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS)
                        .setData(Uri.parse("package:$packageName")),
                )
            }
        }
        result.success(false)
    }

    private fun isBatteryUnrestricted(): Boolean {
        val pm = getSystemService(PowerManager::class.java) ?: return true
        return pm.isIgnoringBatteryOptimizations(packageName)
    }

    /// Sin exención, muchos fabricantes matan el servicio con la pantalla
    /// apagada y la ruta nunca se cierra ni se guarda.
    private fun requestBatteryExemption(result: MethodChannel.Result) {
        if (isBatteryUnrestricted()) {
            result.success(true)
            return
        }
        try {
            startActivity(
                Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS)
                    .setData(Uri.parse("package:$packageName")),
            )
        } catch (e: Exception) {
            // Algunas ROMs no exponen el diálogo: abrir los ajustes generales.
            runCatching { startActivity(Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS)) }
        }
        result.success(false)
    }

    private fun clearEventLog(result: MethodChannel.Result) {
        getSharedPreferences(BtAutoService.PREFS_NATIVE, Context.MODE_PRIVATE)
            .edit().remove(BtAutoService.KEY_EVENTS).apply()
        result.success(null)
    }

    private fun isTargetConnectedNow(): Boolean {
        if (!hasBtConnectPermission()) return false
        val target = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            .getString("flutter.route_auto_device_address", null) ?: return false
        val adapter = bluetoothAdapter() ?: return false
        return try {
            val device = adapter.bondedDevices.firstOrNull { it.address == target } ?: return false
            device.javaClass.getMethod("isConnected").invoke(device) as? Boolean ?: false
        } catch (e: Exception) {
            false
        }
    }

    private fun bluetoothAdapter() =
        (getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager)?.adapter

    /// El alias es el nombre que el usuario le puso al dispositivo en los
    /// ajustes de Bluetooth; `name` es el de fábrica. Se prefiere el alias para
    /// que la lista coincida con lo que ve en el teléfono.
    private fun deviceLabel(device: BluetoothDevice): String {
        val alias = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            device.alias
        } else {
            try {
                device.javaClass.getMethod("getAliasName").invoke(device) as? String
            } catch (e: Exception) {
                null
            }
        }
        return alias?.takeIf { it.isNotBlank() }
            ?: device.name?.takeIf { it.isNotBlank() }
            ?: device.address
    }

    private fun getBondedDevices(result: MethodChannel.Result) {
        if (!hasBtConnectPermission()) {
            result.error("no_permission", "Falta permiso Bluetooth", null)
            return
        }
        val adapter = bluetoothAdapter()
        if (adapter == null) {
            result.error("no_adapter", "Bluetooth no disponible en el dispositivo", null)
            return
        }
        try {
            val list = adapter.bondedDevices.map { d ->
                mapOf("name" to deviceLabel(d), "address" to d.address)
            }
            result.success(list)
        } catch (e: SecurityException) {
            result.error("no_permission", e.message, null)
        }
    }

    private fun isConnected(address: String?, result: MethodChannel.Result) {
        if (address == null || !hasBtConnectPermission()) {
            result.success(false)
            return
        }
        val adapter = bluetoothAdapter()
        if (adapter == null) {
            result.success(false)
            return
        }
        try {
            val device = adapter.bondedDevices.firstOrNull { it.address == address }
            if (device == null) {
                result.success(false)
                return
            }
            // BluetoothDevice.isConnected() es oculto pero estable; via reflexión.
            val connected = device.javaClass.getMethod("isConnected").invoke(device) as? Boolean
            result.success(connected ?: false)
        } catch (e: Exception) {
            result.success(false)
        }
    }
}
