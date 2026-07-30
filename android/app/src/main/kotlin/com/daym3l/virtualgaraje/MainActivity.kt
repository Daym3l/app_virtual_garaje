package com.daym3l.virtualgaraje

import android.Manifest
import android.app.NotificationChannel
import android.app.NotificationManager
import android.bluetooth.BluetoothManager
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val channelName = "virtualgaraje/bt_auto"
    private val btPermissionRequestCode = 4231
    private var pendingPermissionResult: MethodChannel.Result? = null

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

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "ensurePermission" -> ensurePermission(result)
                    "getBondedDevices" -> getBondedDevices(result)
                    "isConnected" -> isConnected(call.argument<String>("address"), result)
                    // El servicio de vigilancia se implementa en la Fase 2.
                    "startService" -> result.success(null)
                    "stopService" -> result.success(null)
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

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == btPermissionRequestCode) {
            val granted = grantResults.isNotEmpty() &&
                grantResults[0] == PackageManager.PERMISSION_GRANTED
            pendingPermissionResult?.success(granted)
            pendingPermissionResult = null
        }
    }

    private fun bluetoothAdapter() =
        (getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager)?.adapter

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
                mapOf("name" to (d.name ?: ""), "address" to d.address)
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
