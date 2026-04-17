package com.example.skychatlocal

import android.Manifest
import android.annotation.SuppressLint
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.Color
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.location.Location
import android.location.LocationListener
import android.location.LocationManager
import android.media.AudioManager
import android.media.ToneGenerator
import android.net.Uri
import android.net.wifi.WifiManager
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.VibrationEffect
import android.os.Vibrator
import android.text.format.Formatter
import android.util.Log
import android.view.WindowManager
import android.webkit.PermissionRequest
import android.webkit.ValueCallback
import android.webkit.WebChromeClient
import android.webkit.WebView
import android.webkit.WebViewClient
import android.widget.ImageView
import android.widget.TextView
import android.widget.Toast
import androidx.appcompat.app.AlertDialog
import androidx.appcompat.app.AppCompatActivity
import androidx.core.app.ActivityCompat
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.splashscreen.SplashScreen.Companion.installSplashScreen
import com.google.zxing.BarcodeFormat
import com.google.zxing.MultiFormatWriter
import java.net.Inet4Address
import java.net.NetworkInterface
import java.security.SecureRandom
import java.util.Collections
import kotlin.math.roundToInt

interface WebServerListener {
    fun onMessageFromWeb(json: String)
    fun onClientDisconnected()
}

class MainActivity : AppCompatActivity(), WebServerListener, SensorEventListener, LocationListener {

    private var server: LocalServer? = null
    private var meshManager: MeshManager? = null
    private var toneGenerator: ToneGenerator? = null
    private val PORT = 8080
    private val CHANNEL_ID = "airchat_discovery_channel"
    private val NOTIFICATION_ID = 1001

    private var fileUploadCallback: ValueCallback<Array<Uri>>? = null
    private val FILE_CHOOSER_RESULT_CODE = 100

    // SENSORS
    private lateinit var sensorManager: SensorManager
    private var accelerometer: Sensor? = null
    private var magnetometer: Sensor? = null
    private var locationManager: LocationManager? = null

    private val accelerometerReading = FloatArray(3)
    private val magnetometerReading = FloatArray(3)
    private val rotationMatrix = FloatArray(9)
    private val orientationAngles = FloatArray(3)

    private var lastUpdate = 0L
    private lateinit var webView: WebView

    private var roomKeyBase64: String = ""

    override fun onCreate(savedInstanceState: Bundle?) {
        val splashScreen = installSplashScreen()
        setTheme(R.style.Theme_SkyChatLocal)
        super.onCreate(savedInstanceState)
        var keepShowing = true
        splashScreen.setKeepOnScreenCondition { keepShowing }
        Handler(Looper.getMainLooper()).postDelayed({ keepShowing = false }, 2000)
        setContentView(R.layout.activity_main)

        // Generate E2E Room Key
        val rawKey = ByteArray(32)
        SecureRandom().nextBytes(rawKey)
        roomKeyBase64 = android.util.Base64.encodeToString(rawKey, android.util.Base64.URL_SAFE or android.util.Base64.NO_WRAP)
        
        // Generate Short Code for PC/Laptop connection
        val chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
        val shortCode = (1..4).map { chars.random() }.joinToString("")

        createNotificationChannel()
        toneGenerator = ToneGenerator(AudioManager.STREAM_ALARM, 100)
        checkAllPermissions()

        val ipText = findViewById<TextView>(R.id.ipText)
        val qrImage = findViewById<ImageView>(R.id.qrImage)
        webView = findViewById(R.id.webView)

        // INIT SENSORS
        sensorManager = getSystemService(Context.SENSOR_SERVICE) as SensorManager
        accelerometer = sensorManager.getDefaultSensor(Sensor.TYPE_ACCELEROMETER)
        magnetometer = sensorManager.getDefaultSensor(Sensor.TYPE_MAGNETIC_FIELD)
        locationManager = getSystemService(Context.LOCATION_SERVICE) as LocationManager

        meshManager = MeshManager(this, "Node-${Build.MODEL}", roomKeyBase64,
            onMessageReceived = { server?.broadcastToAll(it) },
            onDeviceLost = { onClientDisconnected() },
            onPeerFound = { id, name ->
                runOnUiThread {
                    startPulsingEffect()
                    showDiscoveryNotification(name)
                    AlertDialog.Builder(this)
                        .setTitle("AirChat Detectat")
                        .setMessage("Găsit Mesh '$name'. Conectare?")
                        .setCancelable(false)
                        .setPositiveButton("Conectare") { _, _ ->
                            meshManager?.connectToPeer(id)
                            stopPulsingEffect()
                            Toast.makeText(this, "Conectare...", Toast.LENGTH_SHORT).show()
                        }
                        .setNegativeButton("Nu") { d, _ ->
                            d.dismiss()
                            stopPulsingEffect()
                        }
                        .show()
                }
            }
        )
        meshManager?.start()

        val ipAddress = getSmartIpAddress()
        
        try {
            server = LocalServer(this, PORT, ipAddress, roomKeyBase64, shortCode, this)
            server?.start() // Use default timeout
        } catch (e: Exception) { Toast.makeText(this, "Err: ${e.message}", Toast.LENGTH_LONG).show() }

        val url = "http://$ipAddress:$PORT/#$roomKeyBase64"
        
        // Afisare IP + Short code special pentru laptopuri/browsere
        ipText.text = getString(R.string.pc_connect_text, ipAddress, PORT, shortCode)

        try {
            val smallQr = generateQrCode(url, dpToPx(64))
            qrImage.setImageBitmap(smallQr)
            qrImage.setOnClickListener { showLargeQrDialog(generateQrCode(url, dpToPx(260))) }
        } catch (_: Exception) {}

        setupWebView(webView)
    }

    override fun onResume() {
        super.onResume()
        accelerometer?.also { sensorManager.registerListener(this, it, SensorManager.SENSOR_DELAY_NORMAL) }
        magnetometer?.also { sensorManager.registerListener(this, it, SensorManager.SENSOR_DELAY_NORMAL) }

        if (ActivityCompat.checkSelfPermission(this, Manifest.permission.ACCESS_FINE_LOCATION) == PackageManager.PERMISSION_GRANTED) {
            try {
                var lastKnownLocation: Location? = null
                if (locationManager?.isProviderEnabled(LocationManager.GPS_PROVIDER) == true) {
                    locationManager?.requestLocationUpdates(LocationManager.GPS_PROVIDER, 2000L, 1f, this)
                    val loc = locationManager?.getLastKnownLocation(LocationManager.GPS_PROVIDER)
                    if (loc != null) lastKnownLocation = loc
                }
                if (locationManager?.isProviderEnabled(LocationManager.NETWORK_PROVIDER) == true) {
                    locationManager?.requestLocationUpdates(LocationManager.NETWORK_PROVIDER, 2000L, 1f, this)
                    val loc = locationManager?.getLastKnownLocation(LocationManager.NETWORK_PROVIDER)
                    if (loc != null && (lastKnownLocation == null || loc.time > lastKnownLocation.time)) {
                        lastKnownLocation = loc
                    }
                }
                lastKnownLocation?.let { onLocationChanged(it) }
            } catch (e: Exception) {
                Log.e("AirChat", "Location provider not available: ${e.message}")
            }
        }
    }

    override fun onPause() {
        super.onPause()
        sensorManager.unregisterListener(this)
        locationManager?.removeUpdates(this)
    }

    // --- SENSOR EVENTS ---
    override fun onSensorChanged(event: SensorEvent?) {
        if (event == null) return
        if (event.sensor.type == Sensor.TYPE_ACCELEROMETER) {
            System.arraycopy(event.values, 0, accelerometerReading, 0, accelerometerReading.size)
        } else if (event.sensor.type == Sensor.TYPE_MAGNETIC_FIELD) {
            System.arraycopy(event.values, 0, magnetometerReading, 0, magnetometerReading.size)
        }

        // Calculează Azimutul (Busola) doar o dată la 200ms
        val now = System.currentTimeMillis()
        if (now - lastUpdate > 200) {
            lastUpdate = now
            SensorManager.getRotationMatrix(rotationMatrix, null, accelerometerReading, magnetometerReading)
            SensorManager.getOrientation(rotationMatrix, orientationAngles)

            // Convert to degrees (0-360)
            var azimuth = Math.toDegrees(orientationAngles[0].toDouble()).toFloat()
            if (azimuth < 0) azimuth += 360f

            // Trimite în WebView
            runOnUiThread {
                webView.evaluateJavascript("if (typeof updateMyHeading === 'function') updateMyHeading($azimuth)", null)
            }
        }
    }

    override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) {}

    // --- LOCATION EVENTS ---
    override fun onLocationChanged(location: Location) {
        val lat = location.latitude
        val lon = location.longitude
        runOnUiThread {
            webView.evaluateJavascript("if (typeof updateMyLocation === 'function') updateMyLocation($lat, $lon)", null)
        }
    }

    private fun startPulsingEffect() {
        runOnUiThread { webView.evaluateJavascript("if (typeof startPulsing === 'function') startPulsing();", null) }
    }

    private fun stopPulsingEffect() {
        runOnUiThread { webView.evaluateJavascript("if (typeof stopPulsing === 'function') stopPulsing();", null) }
    }

    private fun triggerBuzzVibration() {
        try {
            val vibrator = getSystemService(Context.VIBRATOR_SERVICE) as Vibrator
            if (vibrator.hasVibrator()) {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    vibrator.vibrate(VibrationEffect.createOneShot(500, VibrationEffect.DEFAULT_AMPLITUDE))
                } else {
                    @Suppress("DEPRECATION")
                    vibrator.vibrate(500)
                }
            }
        } catch (e: Exception) { Log.e("AirChat", "Err Vib: ${e.message}") }
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(CHANNEL_ID, "AirChat", NotificationManager.IMPORTANCE_HIGH)
            getSystemService(NotificationManager::class.java).createNotificationChannel(channel)
        }
    }

    @SuppressLint("MissingPermission")
    private fun showDiscoveryNotification(serverName: String) {
        val intent = Intent(this, MainActivity::class.java).apply { flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK }
        val pendingIntent = PendingIntent.getActivity(this, 0, intent, PendingIntent.FLAG_IMMUTABLE)
        val builder = NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.ic_dialog_info)
            .setContentTitle("Server Găsit!")
            .setContentText("Conectare la '$serverName'")
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setContentIntent(pendingIntent)
            .setAutoCancel(true)
        NotificationManagerCompat.from(this).notify(NOTIFICATION_ID, builder.build())
    }

    override fun onMessageFromWeb(json: String) {
        meshManager?.sendMessage(json)
        if (json.contains("\"type\":\"buzz\"")) {
            runOnUiThread { triggerBuzzVibration() }
        }
    }

    override fun onClientDisconnected() { runOnUiThread { Toast.makeText(this, "Deconectat!", Toast.LENGTH_SHORT).show() } }

    private fun checkAllPermissions() {
        val p = mutableListOf(
            Manifest.permission.ACCESS_FINE_LOCATION,
            Manifest.permission.RECORD_AUDIO,
            Manifest.permission.MODIFY_AUDIO_SETTINGS,
            Manifest.permission.VIBRATE
        )
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            p.add(Manifest.permission.BLUETOOTH_SCAN)
            p.add(Manifest.permission.BLUETOOTH_ADVERTISE)
            p.add(Manifest.permission.BLUETOOTH_CONNECT)
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            p.add(Manifest.permission.POST_NOTIFICATIONS)
            p.add(Manifest.permission.NEARBY_WIFI_DEVICES)
        }
        ActivityCompat.requestPermissions(this, p.toTypedArray(), 101)
    }

    private fun getSmartIpAddress(): String {
        try {
            var wifiClientIp: String? = null
            val wm = applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
            val ip = wm.connectionInfo.ipAddress
            if (ip != 0) {
                val ipString = Formatter.formatIpAddress(ip)
                if (ipString != "0.0.0.0") wifiClientIp = ipString
            }
            
            var bestIp: String? = null
            var wlanIp: String? = null
            var apIp: String? = null
            
            for (intf in Collections.list(NetworkInterface.getNetworkInterfaces())) {
                val name = intf.name.lowercase()
                if (name.contains("rmnet") || name.contains("dummy") || name.contains("lo")) continue
                
                for (addr in Collections.list(intf.inetAddresses)) {
                    if (!addr.isLoopbackAddress && addr is Inet4Address) {
                        val hostAddr = addr.hostAddress ?: continue
                        if (name.contains("ap") || name.contains("swlan") || name.contains("hotspot") || name.contains("rndis")) {
                            apIp = hostAddr
                        } else if (name.contains("wlan")) {
                            wlanIp = hostAddr
                        }
                        bestIp = hostAddr
                    }
                }
            }
            return apIp ?: wifiClientIp ?: wlanIp ?: bestIp ?: "192.168.43.1"
        } catch (_: Exception) {}
        return "192.168.43.1"
    }

    @SuppressLint("SetJavaScriptEnabled")
    private fun setupWebView(webView: WebView) {
        webView.clearCache(true)
        webView.clearHistory()

        webView.settings.apply {
            javaScriptEnabled = true
            domStorageEnabled = true
            mediaPlaybackRequiresUserGesture = false
            useWideViewPort = true
            loadWithOverviewMode = true
            cacheMode = android.webkit.WebSettings.LOAD_NO_CACHE
            allowFileAccess = true
            allowContentAccess = true
            setGeolocationEnabled(true)
        }

        webView.webViewClient = WebViewClient()

        webView.webChromeClient = object : WebChromeClient() {
            override fun onGeolocationPermissionsShowPrompt(origin: String?, callback: android.webkit.GeolocationPermissions.Callback?) {
                callback?.invoke(origin, true, false)
            }

            override fun onPermissionRequest(request: PermissionRequest) {
                val resources = request.resources
                for (r in resources) {
                    if (PermissionRequest.RESOURCE_AUDIO_CAPTURE == r) {
                        request.grant(arrayOf(PermissionRequest.RESOURCE_AUDIO_CAPTURE))
                        return
                    }
                }
                request.grant(request.resources)
            }

            override fun onShowFileChooser(webView: WebView?, filePathCallback: ValueCallback<Array<Uri>>?, fileChooserParams: FileChooserParams?): Boolean {
                fileUploadCallback?.onReceiveValue(null)
                fileUploadCallback = filePathCallback
                val intent = fileChooserParams?.createIntent()
                try { startActivityForResult(intent!!, FILE_CHOOSER_RESULT_CODE) } catch (e: Exception) { fileUploadCallback = null; return false }
                return true
            }
        }

        webView.addJavascriptInterface(WebAppInterface(this), "AndroidInterface")
        webView.loadUrl("http://127.0.0.1:$PORT/#$roomKeyBase64")
    }

    inner class WebAppInterface(private val context: Context) {
        @android.webkit.JavascriptInterface
        fun updateSystemUiTheme(theme: String) {
            runOnUiThread {
                val window = (context as MainActivity).window
                window.addFlags(WindowManager.LayoutParams.FLAG_DRAWS_SYSTEM_BAR_BACKGROUNDS)
                val insetsController = androidx.core.view.WindowCompat.getInsetsController(window, window.decorView)
                
                if (theme == "light") {
                    window.statusBarColor = android.graphics.Color.parseColor("#ffffff")
                    window.navigationBarColor = android.graphics.Color.parseColor("#ffffff")
                    insetsController.isAppearanceLightStatusBars = true
                    insetsController.isAppearanceLightNavigationBars = true
                    
                    findViewById<androidx.constraintlayout.widget.ConstraintLayout>(R.id.mainLayout)?.setBackgroundColor(android.graphics.Color.parseColor("#ffffff"))
                    findViewById<TextView>(R.id.ipText)?.apply {
                        setBackgroundColor(android.graphics.Color.parseColor("#ffffff"))
                        setTextColor(android.graphics.Color.parseColor("#000000"))
                    }
                    findViewById<ImageView>(R.id.qrImage)?.setBackgroundColor(android.graphics.Color.parseColor("#ffffff"))
                } else {
                    window.statusBarColor = android.graphics.Color.parseColor("#000000")
                    window.navigationBarColor = android.graphics.Color.parseColor("#000000")
                    insetsController.isAppearanceLightStatusBars = false
                    insetsController.isAppearanceLightNavigationBars = false

                    findViewById<androidx.constraintlayout.widget.ConstraintLayout>(R.id.mainLayout)?.setBackgroundColor(android.graphics.Color.parseColor("#000000"))
                    findViewById<TextView>(R.id.ipText)?.apply {
                        setBackgroundColor(android.graphics.Color.parseColor("#000000"))
                        setTextColor(android.graphics.Color.parseColor("#ffffff"))
                    }
                    findViewById<ImageView>(R.id.qrImage)?.setBackgroundColor(android.graphics.Color.parseColor("#000000"))
                }
            }
        }
        
        @android.webkit.JavascriptInterface
        fun getBatteryLevel(): Int {
            val batteryManager = context.getSystemService(Context.BATTERY_SERVICE) as android.os.BatteryManager
            return batteryManager.getIntProperty(android.os.BatteryManager.BATTERY_PROPERTY_CAPACITY)
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (requestCode == FILE_CHOOSER_RESULT_CODE) {
            fileUploadCallback?.onReceiveValue(WebChromeClient.FileChooserParams.parseResult(resultCode, data))
            fileUploadCallback = null
        } else {
            super.onActivityResult(requestCode, resultCode, data)
        }
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == 101) {
            if (ActivityCompat.checkSelfPermission(this, Manifest.permission.ACCESS_FINE_LOCATION) == PackageManager.PERMISSION_GRANTED) {
                // Dacă locația abia a fost acordată, o pornim imediat
                try {
                    if (locationManager?.isProviderEnabled(LocationManager.GPS_PROVIDER) == true) {
                        locationManager?.requestLocationUpdates(LocationManager.GPS_PROVIDER, 2000L, 1f, this)
                    }
                    if (locationManager?.isProviderEnabled(LocationManager.NETWORK_PROVIDER) == true) {
                        locationManager?.requestLocationUpdates(LocationManager.NETWORK_PROVIDER, 2000L, 1f, this)
                    }
                } catch (e: Exception) {
                    Log.e("AirChat", "Err location: ${e.message}")
                }
            }
        }
    }

    private fun dpToPx(dp: Int) = (dp * resources.displayMetrics.density).roundToInt()
    private fun generateQrCode(text: String, size: Int): Bitmap {
        val m = MultiFormatWriter().encode(text, BarcodeFormat.QR_CODE, size, size, null)
        val p = IntArray(m.width * m.height)
        for (i in p.indices) p[i] = if (m[i % m.width, i / m.width]) Color.BLACK else Color.WHITE
        return Bitmap.createBitmap(m.width, m.height, Bitmap.Config.ARGB_8888).apply { setPixels(p, 0, m.width, 0, 0, m.width, m.height) }
    }
    private fun showLargeQrDialog(bitmap: Bitmap) {
        val i = ImageView(this).apply { setImageBitmap(bitmap); adjustViewBounds = true; setBackgroundColor(Color.BLACK); setPadding(30,30,30,30) }
        AlertDialog.Builder(this).setView(i).setCancelable(true).show()
    }
    override fun onDestroy() { super.onDestroy(); server?.stop(); meshManager?.stop(); toneGenerator?.release(); stopPulsingEffect() }
}