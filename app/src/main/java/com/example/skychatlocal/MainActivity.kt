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

    override fun onCreate(savedInstanceState: Bundle?) {
        val splashScreen = installSplashScreen()
        setTheme(R.style.Theme_SkyChatLocal)
        super.onCreate(savedInstanceState)
        var keepShowing = true
        splashScreen.setKeepOnScreenCondition { keepShowing }
        Handler(Looper.getMainLooper()).postDelayed({ keepShowing = false }, 2000)
        setContentView(R.layout.activity_main)

        createNotificationChannel()
        toneGenerator = ToneGenerator(AudioManager.STREAM_ALARM, 100)
        checkAllPermissions()

        val ipText = findViewById<TextView>(R.id.ipText)
        val qrImage = findViewById<ImageView>(R.id.qrImage)
        val webView = findViewById<WebView>(R.id.webView)

        // INIT SENSORS
        sensorManager = getSystemService(Context.SENSOR_SERVICE) as SensorManager
        accelerometer = sensorManager.getDefaultSensor(Sensor.TYPE_ACCELEROMETER)
        magnetometer = sensorManager.getDefaultSensor(Sensor.TYPE_MAGNETIC_FIELD)
        locationManager = getSystemService(Context.LOCATION_SERVICE) as LocationManager

        meshManager = MeshManager(this, "Node-${Build.MODEL}",
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

        try {
            server = LocalServer(this, PORT, this)
            server?.start(3600000)
        } catch (e: Exception) { Toast.makeText(this, "Err: ${e.message}", Toast.LENGTH_LONG).show() }

        val ipAddress = getSmartIpAddress()
        val url = "http://$ipAddress:$PORT"
        ipText.text = url

        ipText.setOnLongClickListener {
            runOnUiThread {
                startPulsingEffect()
                showDiscoveryNotification("Demo Server")
                AlertDialog.Builder(this).setTitle("Demo").setMessage("Test Pulsare").setPositiveButton("OK") { _, _ -> stopPulsingEffect() }.show()
            }
            true
        }

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
            locationManager?.requestLocationUpdates(LocationManager.GPS_PROVIDER, 2000L, 1f, this)
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
                findViewById<WebView>(R.id.webView).evaluateJavascript("updateMyHeading($azimuth)", null)
            }
        }
    }

    override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) {}

    // --- LOCATION EVENTS ---
    override fun onLocationChanged(location: Location) {
        val lat = location.latitude
        val lon = location.longitude
        runOnUiThread {
            findViewById<WebView>(R.id.webView).evaluateJavascript("updateMyLocation($lat, $lon)", null)
        }
    }

    private fun startPulsingEffect() {
        runOnUiThread { findViewById<WebView>(R.id.webView).evaluateJavascript("startPulsing();", null) }
    }

    private fun stopPulsingEffect() {
        runOnUiThread { findViewById<WebView>(R.id.webView).evaluateJavascript("stopPulsing();", null) }
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
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) p.add(Manifest.permission.POST_NOTIFICATIONS)
        ActivityCompat.requestPermissions(this, p.toTypedArray(), 101)
    }

    private fun getSmartIpAddress(): String {
        try {
            val wm = applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
            val ip = wm.connectionInfo.ipAddress
            if (ip != 0) return Formatter.formatIpAddress(ip)
            for (intf in Collections.list(NetworkInterface.getNetworkInterfaces())) {
                for (addr in Collections.list(intf.inetAddresses)) {
                    if (!addr.isLoopbackAddress && addr is Inet4Address) return addr.hostAddress ?: "192.168.43.1"
                }
            }
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
        }

        webView.webViewClient = WebViewClient()

        webView.webChromeClient = object : WebChromeClient() {
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

        webView.loadUrl("http://127.0.0.1:$PORT")
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (requestCode == FILE_CHOOSER_RESULT_CODE) {
            fileUploadCallback?.onReceiveValue(WebChromeClient.FileChooserParams.parseResult(resultCode, data))
            fileUploadCallback = null
        } else {
            super.onActivityResult(requestCode, resultCode, data)
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