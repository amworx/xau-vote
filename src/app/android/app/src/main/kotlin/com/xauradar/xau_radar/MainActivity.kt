package com.xauradar.xau_radar

import android.content.Intent
import android.net.Uri
import android.os.Build
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * Host activity plus the platform half of the in-app updater.
 *
 * Dart owns the check/download state machine; Android is only asked for two
 * things it alone can answer: what version is actually installed, and how to
 * hand a finished APK to the system installer.
 */
class MainActivity : FlutterActivity() {

    private companion object {
        const val CHANNEL = "com.xauvote.app/update"
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "installedVersion" -> result.success(installedVersion())

                    "installApk" -> {
                        val path = call.argument<String>("path")
                        if (path.isNullOrBlank()) {
                            result.error("bad_path", "No APK path supplied", null)
                        } else {
                            installApk(File(path), result)
                        }
                    }

                    // Lets Dart explain *why* nothing happened instead of
                    // failing silently on devices below Android 8.
                    "canInstallPackages" -> result.success(
                        Build.VERSION.SDK_INT >= Build.VERSION_CODES.O
                    )

                    else -> result.notImplemented()
                }
            }
    }

    /**
     * Version actually installed, as `{versionName}` and `versionCode`.
     *
     * Read from the package manager rather than a Dart constant, so the check
     * stays correct after an update instead of comparing a build-time literal
     * against a newer installed build.
     */
    private fun installedVersion(): Map<String, String> {
        val info = packageManager.getPackageInfo(packageName, 0)
        val code = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            info.longVersionCode
        } else {
            @Suppress("DEPRECATION")
            info.versionCode.toLong()
        }
        // Long is not one of the types Flutter's standard codec can carry
        // unambiguously, so the code is sent as a string and parsed in Dart.
        return mapOf(
            "versionName" to (info.versionName ?: "unknown"),
            "versionCode" to code.toString(),
        )
    }

    /**
     * Opens the system installer for [apk].
     *
     * Errors are reported back to Dart instead of thrown, because the caller
     * shows the user a message and needs to know whether the failure was a
     * missing file, a revoked install permission, or a missing handler.
     */
    private fun installApk(apk: File, result: MethodChannel.Result) {
        if (!apk.exists()) {
            result.error("missing_file", "Downloaded APK not found", apk.path)
            return
        }
        // A partially written file would install as a corrupt app.
        if (apk.length() == 0L) {
            result.error("empty_file", "Downloaded APK is empty", apk.path)
            return
        }

        try {
            val uri: Uri = FileProvider.getUriForFile(
                this,
                "$packageName.updateprovider",
                apk,
            )
            val intent = Intent(Intent.ACTION_VIEW).apply {
                setDataAndType(uri, "application/vnd.android.package-archive")
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            startActivity(intent)
            result.success(null)
        } catch (e: SecurityException) {
            result.error(
                "permission_denied",
                "Install permission is not granted for this app",
                e.message,
            )
        } catch (e: android.content.ActivityNotFoundException) {
            result.error("no_installer", "No package installer available", e.message)
        }
    }
}