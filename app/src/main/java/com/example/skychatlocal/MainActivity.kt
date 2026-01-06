package com.example.skychatlocal

import android.Manifest
import android.annotation.SuppressLint
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.Color
import android.media.AudioManager
import android.media.ToneGenerator
import android.net.wifi.WifiManager
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.text.format.Formatter
import android.util.Log
import android.view.WindowManager
import android.webkit.PermissionRequest
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

class MainActivity : AppCompatActivity(), WebServerListener {

    private var server: LocalServer? = null
    private var meshManager: MeshManager? = null
    private var toneGenerator: ToneGenerator? = null
    private val PORT = 8080
    private val CHANNEL_ID = "airchat_discovery_channel"
    private val NOTIFICATION_ID = 1001

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

        meshManager = MeshManager(this, "Node-${Build.MODEL}",
            onMessageReceived = { server?.broadcastToAll(it) },
            onDeviceLost = { onClientDisconnected() },
            onPeerFound = { id, name ->
                runOnUiThread {
                    startPulsingEffect()
                    showDiscoveryNotification(name)
                    AlertDialog.Builder(this)
                        .setTitle("AirChat Detectat")
                        .setMessage("Găsit server '$name'. Conectare?")
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
        // SCHIMBARE: HTTP simplu
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

    private fun startPulsingEffect() {
        runOnUiThread { findViewById<WebView>(R.id.webView).evaluateJavascript("startPulsing();", null) }
    }

    private fun stopPulsingEffect() {
        runOnUiThread { findViewById<WebView>(R.id.webView).evaluateJavascript("stopPulsing();", null) }
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

    override fun onMessageFromWeb(json: String) { meshManager?.sendMessage(json) }
    override fun onClientDisconnected() { runOnUiThread { Toast.makeText(this, "Deconectat!", Toast.LENGTH_SHORT).show() } }

    private fun checkAllPermissions() {
        val p = mutableListOf(Manifest.permission.ACCESS_FINE_LOCATION, Manifest.permission.RECORD_AUDIO)
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
        }

        // SCHIMBARE: Nu mai avem nevoie de SSL Error Handler
        webView.webViewClient = WebViewClient()

        webView.webChromeClient = object : WebChromeClient() {
            override fun onPermissionRequest(request: PermissionRequest) { request.grant(request.resources) }
            override fun onConsoleMessage(message: android.webkit.ConsoleMessage?): Boolean {
                Log.d("WebViewConsole", "${message?.message()}")
                return true
            }
        }

        // SCHIMBARE: HTTP
        webView.loadUrl("http://127.0.0.1:$PORT")
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