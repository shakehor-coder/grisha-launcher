package com.grisha.launcher

import android.content.ActivityNotFoundException
import android.app.role.RoleManager
import android.content.ComponentName
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
import java.io.File
import java.io.FileOutputStream
import java.util.Locale
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {
    private val appsChannelName = "com.grisha.launcher/apps"
    private val wallpaperChannelName = "com.grisha.launcher/wallpaper"
    private val backgroundExecutor: ExecutorService = Executors.newSingleThreadExecutor()
    private val iconExecutor: ExecutorService = Executors.newFixedThreadPool(4)
    private val mainHandler = Handler(Looper.getMainLooper())
    private var pendingWallpaperResult: MethodChannel.Result? = null
    private var pendingWallpaperType: String? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, appsChannelName)
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
                    "getAppIcons" -> {
                        val packageNames = call.argument<List<String>>("packageNames")
                            ?: emptyList()
                        val sizePx = call.argument<Int>("sizePx") ?: 96
                        runInBackground(result) { getAppIcons(packageNames, sizePx) }
                    }
                    "isDefaultLauncher" -> result.success(isDefaultLauncher())
                    "requestDefaultLauncher" -> result.success(requestDefaultLauncher())
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
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, wallpaperChannelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "pickImageWallpaper" -> pickWallpaper("image", result)
                    "pickVideoWallpaper" -> pickWallpaper("video", result)
                    "pickCustomIcon" -> pickWallpaper("icon", result)
                    else -> result.notImplemented()
                }
            }
    }

    override fun onDestroy() {
        backgroundExecutor.shutdown()
        iconExecutor.shutdown()
        super.onDestroy()
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != WALLPAPER_PICK_REQUEST) {
            return
        }

        val result = pendingWallpaperResult ?: return
        val wallpaperType = pendingWallpaperType ?: "image"
        pendingWallpaperResult = null
        pendingWallpaperType = null

        val uri = data?.data
        if (resultCode != RESULT_OK || uri == null) {
            result.success(null)
            return
        }

        runInBackground(result) {
            val path = copyPickedWallpaper(uri, wallpaperType)
            mapOf("type" to wallpaperType, "path" to path)
        }
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

        val apps = activities
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
        cleanupIconCache(apps.mapNotNull { it["packageName"] as? String }.toSet())
        return apps
    }

    private fun getAppIcon(packageName: String, sizePx: Int): String? {
        return getCachedIconPath(packageName, sizePx)
    }

    private fun getAppIcons(packageNames: List<String>, sizePx: Int): Map<String, String?> {
        val uniquePackages = packageNames.filter { it.isNotBlank() }.distinct()
        val futures = uniquePackages.associateWith { packageName ->
            iconExecutor.submit<String?> { getCachedIconPath(packageName, sizePx) }
        }
        return futures.mapValues { (_, future) ->
            try {
                future.get()
            } catch (_: Throwable) {
                null
            }
        }
    }

    private fun getCachedIconPath(packageName: String, sizePx: Int): String? {
        val safeSize = sizePx.coerceIn(48, 192)
        val iconFile = iconFile(packageName, safeSize)
        if (iconFile.exists() && iconFile.length() > 0) {
            return iconFile.absolutePath
        }

        return try {
            writeDrawableToPng(packageManager.getApplicationIcon(packageName), safeSize, iconFile)
            iconFile.absolutePath
        } catch (_: PackageManager.NameNotFoundException) {
            null
        } catch (_: Throwable) {
            iconFile.delete()
            null
        }
    }

    private fun launchApp(packageName: String, result: MethodChannel.Result) {
        val launchIntent = packageManager.getLaunchIntentForPackage(packageName)
            ?: resolveLaunchIntent(packageName)
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

    private fun resolveLaunchIntent(packageName: String): Intent? {
        val launcherIntent = Intent(Intent.ACTION_MAIN)
            .addCategory(Intent.CATEGORY_LAUNCHER)
            .setPackage(packageName)
        val activities = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            packageManager.queryIntentActivities(
                launcherIntent,
                PackageManager.ResolveInfoFlags.of(0)
            )
        } else {
            @Suppress("DEPRECATION")
            packageManager.queryIntentActivities(launcherIntent, 0)
        }
        val activityInfo = activities.firstOrNull()?.activityInfo ?: return null
        return Intent(Intent.ACTION_MAIN)
            .addCategory(Intent.CATEGORY_LAUNCHER)
            .setComponent(ComponentName(activityInfo.packageName, activityInfo.name))
    }

    private fun isDefaultLauncher(): Boolean {
        val intent = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_HOME)
        val resolveInfo = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            packageManager.resolveActivity(
                intent,
                PackageManager.ResolveInfoFlags.of(PackageManager.MATCH_DEFAULT_ONLY.toLong())
            )
        } else {
            @Suppress("DEPRECATION")
            packageManager.resolveActivity(intent, PackageManager.MATCH_DEFAULT_ONLY)
        }
        return resolveInfo?.activityInfo?.packageName == packageName
    }

    private fun requestDefaultLauncher(): Boolean {
        if (isXiaomiDevice()) {
            return openFirstAvailable(miuiDefaultLauncherIntents() + defaultLauncherIntents())
        }

        if (tryRequestHomeRole()) {
            return true
        }

        if (isSamsungDevice()) {
            return openFirstAvailable(samsungDefaultLauncherIntents() + defaultLauncherIntents())
        }

        return openFirstAvailable(defaultLauncherIntents())
    }

    private fun tryRequestHomeRole(): Boolean {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val roleManager = getSystemService(RoleManager::class.java)
            if (roleManager != null &&
                roleManager.isRoleAvailable(RoleManager.ROLE_HOME) &&
                !roleManager.isRoleHeld(RoleManager.ROLE_HOME)
            ) {
                return startActivitySafely(roleManager.createRequestRoleIntent(RoleManager.ROLE_HOME))
            }
        }
        return false
    }

    private fun defaultLauncherIntents(): List<Intent> {
        val homeIntent = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_HOME)
        val chooserIntent = Intent.createChooser(homeIntent, "Выберите лаунчер")

        return listOf(
            Intent(Settings.ACTION_MANAGE_DEFAULT_APPS_SETTINGS),
            Intent(Settings.ACTION_HOME_SETTINGS),
            chooserIntent,
            Intent(Settings.ACTION_SETTINGS)
        )
    }

    private fun miuiDefaultLauncherIntents(): List<Intent> {
        return listOf(
            Intent(Settings.ACTION_MANAGE_DEFAULT_APPS_SETTINGS),
            Intent(Settings.ACTION_HOME_SETTINGS),
            Intent().setComponent(
                ComponentName(
                    "com.android.settings",
                    "com.android.settings.Settings\$ManageDefaultAppsSettingsActivity"
                )
            ),
            Intent().setComponent(
                ComponentName(
                    "com.android.settings",
                    "com.android.settings.Settings\$HomeSettingsActivity"
                )
            ),
            Intent().setComponent(
                ComponentName(
                    "com.miui.securitycenter",
                    "com.miui.appmanager.DefaultAppSettingsActivity"
                )
            ),
            Intent().setComponent(
                ComponentName(
                    "com.miui.securitycenter",
                    "com.miui.appmanager.ApplicationsSettingsActivity"
                )
            )
        )
    }

    private fun samsungDefaultLauncherIntents(): List<Intent> {
        return listOf(
            Intent(Settings.ACTION_MANAGE_DEFAULT_APPS_SETTINGS),
            Intent(Settings.ACTION_HOME_SETTINGS),
            Intent().setComponent(
                ComponentName(
                    "com.android.settings",
                    "com.android.settings.Settings\$DefaultAppSettingsActivity"
                )
            ),
            Intent().setComponent(
                ComponentName(
                    "com.android.settings",
                    "com.android.settings.Settings\$HomeSettingsActivity"
                )
            ),
            Intent().setComponent(
                ComponentName(
                    "com.samsung.android.settings",
                    "com.samsung.android.settings.defaultapp.DefaultAppSettingsActivity"
                )
            )
        )
    }

    private fun openFirstAvailable(intents: List<Intent>): Boolean {
        return intents.any { startActivitySafely(it) }
    }

    private fun startActivitySafely(intent: Intent): Boolean {
        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        return try {
            startActivity(intent)
            true
        } catch (_: ActivityNotFoundException) {
            false
        } catch (_: SecurityException) {
            false
        }
    }

    private fun isXiaomiDevice(): Boolean {
        val manufacturer = Build.MANUFACTURER.lowercase(Locale.US)
        val brand = Build.BRAND.lowercase(Locale.US)
        return manufacturer.contains("xiaomi") ||
            manufacturer.contains("redmi") ||
            manufacturer.contains("poco") ||
            brand.contains("xiaomi") ||
            brand.contains("redmi") ||
            brand.contains("poco")
    }

    private fun isSamsungDevice(): Boolean {
        val manufacturer = Build.MANUFACTURER.lowercase(Locale.US)
        val brand = Build.BRAND.lowercase(Locale.US)
        return manufacturer.contains("samsung") || brand.contains("samsung")
    }

    private fun openAppInfo(packageName: String) {
        val intent = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS)
            .setData(Uri.parse("package:$packageName"))
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        startActivity(intent)
    }

    private fun pickWallpaper(type: String, result: MethodChannel.Result) {
        if (pendingWallpaperResult != null) {
            result.error("picker_busy", "Another wallpaper picker is already open", null)
            return
        }

        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT)
            .addCategory(Intent.CATEGORY_OPENABLE)
            .setType(if (type == "video") "video/*" else "image/*")
            .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)

        pendingWallpaperResult = result
        pendingWallpaperType = type
        try {
            startActivityForResult(intent, WALLPAPER_PICK_REQUEST)
        } catch (error: ActivityNotFoundException) {
            pendingWallpaperResult = null
            pendingWallpaperType = null
            result.error("picker_unavailable", "No gallery app can pick this media", error.message)
        }
    }

    private fun copyPickedWallpaper(uri: Uri, type: String): String {
        val extension = if (type == "video") "mp4" else "jpg"
        if (type == "icon") {
            return copyPickedCustomIcon(uri, extension)
        }
        val file = File(
            wallpaperDir(),
            "launcher_wallpaper_${System.currentTimeMillis()}.$extension"
        )
        contentResolver.openInputStream(uri).use { input ->
            if (input == null) {
                throw IllegalStateException("Unable to open selected wallpaper")
            }
            FileOutputStream(file).use { output ->
                input.copyTo(output)
            }
        }
        cleanupOldWallpapers(file)
        return file.absolutePath
    }

    private fun copyPickedCustomIcon(uri: Uri, extension: String): String {
        val file = File(
            customIconDir(),
            "custom_icon_${System.currentTimeMillis()}.$extension"
        )
        contentResolver.openInputStream(uri).use { input ->
            if (input == null) {
                throw IllegalStateException("Unable to open selected icon")
            }
            FileOutputStream(file).use { output ->
                input.copyTo(output)
            }
        }
        return file.absolutePath
    }

    private fun cleanupOldWallpapers(current: File) {
        current.parentFile
            ?.listFiles { file ->
                file.isFile &&
                    file.name.startsWith("launcher_wallpaper_") &&
                    file.name != current.name
            }
            ?.forEach { it.delete() }
    }

    private fun wallpaperDir(): File {
        return File(filesDir, "wallpapers").also { it.mkdirs() }
    }

    private fun iconFile(packageName: String, sizePx: Int): File {
        return File(iconDir(), "${safeIconName(packageName)}_$sizePx.png")
    }

    private fun cleanupIconCache(activePackages: Set<String>) {
        val activeNames = activePackages.map { safeIconName(it) }.toSet()
        iconDir()
            .listFiles { file -> file.isFile && file.extension == "png" }
            ?.forEach { file ->
                val belongsToInstalledApp = activeNames.any { safeName ->
                    file.name.startsWith("${safeName}_")
                }
                if (!belongsToInstalledApp) {
                    file.delete()
                }
            }
    }

    private fun safeIconName(packageName: String): String {
        return packageName.replace(Regex("[^A-Za-z0-9._-]"), "_")
    }

    private fun iconDir(): File {
        return File(filesDir, "icons").also { it.mkdirs() }
    }

    private fun customIconDir(): File {
        return File(filesDir, "custom-icons").also { it.mkdirs() }
    }

    private fun writeDrawableToPng(drawable: Drawable, sizePx: Int, target: File) {
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

        val temp = File(target.parentFile, "${target.name}.tmp")
        FileOutputStream(temp).use { output ->
            scaledBitmap.compress(Bitmap.CompressFormat.PNG, 100, output)
        }
        if (target.exists()) {
            target.delete()
        }
        temp.renameTo(target)
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

    companion object {
        private const val WALLPAPER_PICK_REQUEST = 4107
    }
}
