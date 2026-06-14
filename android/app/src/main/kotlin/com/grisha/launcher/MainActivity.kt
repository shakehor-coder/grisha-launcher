package com.grisha.launcher

import android.content.ActivityNotFoundException
import android.content.Intent
import android.content.pm.ApplicationInfo
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.drawable.BitmapDrawable
import android.graphics.drawable.Drawable
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.util.Locale
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {
    private val channelName = "com.grisha.launcher/apps"
    private val backgroundExecutor: ExecutorService = Executors.newSingleThreadExecutor()
    private val mainHandler = Handler(Looper.getMainLooper())

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getInstalledApps" -> runInBackground(result) { getInstalledApps() }
                    "getAppIcon" -> {
                        val packageName = call.argument<String>("packageName")
                        val sizePx = call.argument<Int>("sizePx") ?: 96
                        if (packageName.isNullOrBlank()) {
                            result.error("missing_package", "packageName is required", null)
                        } else {
                            runInBackground(result) { getAppIcon(packageName, sizePx) }
                        }
                    }
                    "launchApp" -> {
                        val packageName = call.argument<String>("packageName")
                        if (packageName.isNullOrBlank()) {
                            result.error("missing_package", "packageName is required", null)
                        } else {
                            launchApp(packageName, result)
                        }
                    }
                    "openAppInfo" -> {
                        val packageName = call.argument<String>("packageName")
                        if (packageName.isNullOrBlank()) {
                            result.error("missing_package", "packageName is required", null)
                        } else {
                            openAppInfo(packageName)
                            result.success(true)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    override fun onDestroy() {
        backgroundExecutor.shutdown()
        super.onDestroy()
    }

    private fun getInstalledApps(): List<Map<String, Any?>> {
        val launcherIntent = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER)
        val activities = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            packageManager.queryIntentActivities(
                launcherIntent,
                PackageManager.ResolveInfoFlags.of(0)
            )
        } else {
            @Suppress("DEPRECATION")
            packageManager.queryIntentActivities(launcherIntent, 0)
        }

        return activities
            .mapNotNull { resolveInfo ->
                val activityInfo = resolveInfo.activityInfo ?: return@mapNotNull null
                val appInfo = activityInfo.applicationInfo ?: return@mapNotNull null
                val label = resolveInfo.loadLabel(packageManager)?.toString()
                    ?: appInfo.loadLabel(packageManager)?.toString()
                    ?: activityInfo.packageName

                mapOf(
                    "label" to label,
                    "packageName" to activityInfo.packageName,
                    "isSystem" to ((appInfo.flags and ApplicationInfo.FLAG_SYSTEM) != 0),
                    "category" to categoryName(appInfo.category)
                )
            }
            .distinctBy { it["packageName"] as String }
            .sortedBy { (it["label"] as String).lowercase(Locale.getDefault()) }
    }

    private fun getAppIcon(packageName: String, sizePx: Int): ByteArray? {
        val safeSize = sizePx.coerceIn(48, 192)
        return try {
            drawableToPng(packageManager.getApplicationIcon(packageName), safeSize)
        } catch (_: PackageManager.NameNotFoundException) {
            null
        }
    }

    private fun launchApp(packageName: String, result: MethodChannel.Result) {
        val launchIntent = packageManager.getLaunchIntentForPackage(packageName)
        if (launchIntent == null) {
            result.error("not_launchable", "No launch intent found for $packageName", null)
            return
        }

        launchIntent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        try {
            startActivity(launchIntent)
            result.success(true)
        } catch (error: ActivityNotFoundException) {
            result.error("not_found", "Unable to launch $packageName", error.message)
        }
    }

    private fun openAppInfo(packageName: String) {
        val intent = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS)
            .setData(Uri.parse("package:$packageName"))
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        startActivity(intent)
    }

    private fun drawableToPng(drawable: Drawable, sizePx: Int): ByteArray {
        val bitmap = if (drawable is BitmapDrawable && drawable.bitmap != null) {
            drawable.bitmap
        } else {
            val width = drawable.intrinsicWidth.takeIf { it > 0 } ?: 96
            val height = drawable.intrinsicHeight.takeIf { it > 0 } ?: 96
            Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888).also { bitmap ->
                val canvas = Canvas(bitmap)
                drawable.setBounds(0, 0, canvas.width, canvas.height)
                drawable.draw(canvas)
            }
        }
        val scaledBitmap = if (bitmap.width == sizePx && bitmap.height == sizePx) {
            bitmap
        } else {
            Bitmap.createScaledBitmap(bitmap, sizePx, sizePx, true)
        }

        return ByteArrayOutputStream().use { stream ->
            scaledBitmap.compress(Bitmap.CompressFormat.PNG, 100, stream)
            stream.toByteArray()
        }
    }

    private fun categoryName(category: Int): String {
        return when (category) {
            ApplicationInfo.CATEGORY_GAME -> "Игры"
            ApplicationInfo.CATEGORY_AUDIO -> "Аудио"
            ApplicationInfo.CATEGORY_VIDEO -> "Видео"
            ApplicationInfo.CATEGORY_IMAGE -> "Фото"
            ApplicationInfo.CATEGORY_SOCIAL -> "Соцсети"
            ApplicationInfo.CATEGORY_NEWS -> "Новости"
            ApplicationInfo.CATEGORY_MAPS -> "Карты"
            ApplicationInfo.CATEGORY_PRODUCTIVITY -> "Работа"
            else -> "Приложения"
        }
    }

    private fun <T> runInBackground(result: MethodChannel.Result, block: () -> T) {
        backgroundExecutor.execute {
            try {
                val value = block()
                mainHandler.post { result.success(value) }
            } catch (error: Throwable) {
                mainHandler.post {
                    result.error("background_error", error.message, null)
                }
            }
        }
    }
}
