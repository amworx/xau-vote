package com.xauvote.app

import android.content.ClipData
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * Host activity plus the platform half of the in-app updater.
 *
 * Dart owns the check/download state machine; Android is only asked for the
 * three things it alone can answer: what version is actually installed, whether
 * this app is currently allowed to install packages, and how to hand a finished
 * APK to the system installer.
 *
 * ── Why `canRequestPackageInstalls` is the only honest check ────────────────
 * `REQUEST_INSTALL_PACKAGES` is NOT granted at install time. From Android 8 the
 * user grants it per-source in Settings, so `checkSelfPermission` and
 * `context.checkPermission` both keep returning GRANTED forever while the system
 * refuses the install. The only truthful question is
 * `PackageManager.canRequestPackageInstalls()`.
 *
 * This previously reported `SDK_INT >= O`, which is true on every device this
 * app can run on - so Dart believed it could always install, launched the
 * installer, and the system refused. From the user's side that looked exactly
 * like the app missing a permission, with no way to grant it: there was no
 * handler that opens the install-permission screen at all.
 */
class MainActivity : FlutterActivity() {

    private companion object {
        const val CHANNEL = "com.xauvote.app/update"
        const val APK_MIME = "application/vnd.android.package-archive"
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "installedVersion" -> result.success(installedVersion())

                    // Whether the user has actually allowed this app to install
                    // packages. Not an SDK check.
                    "canInstallPackages" -> result.success(canRequestPackageInstallsCompat())

                    // Opens the system screen where the user grants it, so the
                    // app can ask instead of leaving the user to find it.
                    "requestInstallPermission" -> {
                        requestInstallPermission(result)
                    }

                    "installApk" -> {
                        val path = call.argument<String>("path")
                        if (path.isNullOrBlank()) {
                            result.error("bad_path", "No APK path supplied", null)
                        } else {
                            installApk(File(path), result)
                        }
                    }

                    else -> result.notImplemented()
                }
            }
    }

    /**
     * True when this app may install packages right now.
     *
     * Below Android 8 installation needed no runtime grant, so the answer is
     * unconditionally true there.
     */
    private fun canRequestPackageInstallsCompat(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return true
        return packageManager.canRequestPackageInstalls()
    }

    /**
     * Sends the user to the system screen that grants install permission.
     *
     * `ACTION_MANAGE_UNKNOWN_APP_SOURCES` is the "Install unknown apps" screen,
     * and passing `package:` scopes it to this app. If a device does not
     * resolve it, the app's own details page still carries the toggle.
     * The result reports whether a screen was opened, never whether the user
     * actually granted anything — that can only be re-read afterwards with
     * [canRequestPackageInstallsCompat].
     */
    private fun requestInstallPermission(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            // Nothing to grant on this version; already allowed.
            result.success(true)
            return
        }
        if (canRequestPackageInstallsCompat()) {
            // Already granted - do not send the user somewhere unnecessary.
            result.success(true)
            return
        }
        try {
            val specific = Intent(
                Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                Uri.parse("package:$packageName"),
            )
            startActivity(specific)
            result.success(true)
        } catch (e: android.content.ActivityNotFoundException) {
            try {
                startActivity(
                    Intent(
                        Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                        Uri.parse("package:$packageName"),
                    ),
                )
                result.success(true)
            } catch (e2: android.content.ActivityNotFoundException) {
                result.error(
                    "no_settings",
                    "This device has no screen for granting install permission",
                    e2.message,
                )
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
     * The install permission is checked BEFORE launching, and reported as a
     * distinct `needs_permission` failure rather than a generic error. Without
     * this the system refuses inside the installer UI while Dart has already
     * been told the launch succeeded, so the button appears to do nothing.
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
        if (!canRequestPackageInstallsCompat()) {
            result.error(
                "needs_permission",
                "Install permission has not been granted for this app",
                apk.path,
            )
            return
        }

        try {
            val uri: Uri = FileProvider.getUriForFile(
                this,
                "$packageName.updateprovider",
                apk,
            )
            val intent = Intent(Intent.ACTION_VIEW).apply {
                setDataAndType(uri, APK_MIME)
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                // The read grant is attached to the ClipData as well as the
                // data URI. On several Android versions the flag on the intent
                // data alone is not honoured by the package installer, which
                // then fails to read the file it was just handed.
                clipData = ClipData.newRawUri("xv-update", uri)
                // Tell the installer this is a deliberate, non-sideloaded
                // update so it does not add an extra unknown-source warning.
                putExtra(Intent.EXTRA_NOT_UNKNOWN_SOURCE, true)
                putExtra(Intent.EXTRA_INSTALLER_PACKAGE_NAME, packageName)
            }
            startActivity(intent)
            result.success(null)
        } catch (e: SecurityException) {
            result.error(
                "permission_denied",
                "Install permission is not granted for this app",
                e.message,
            )
        } catch (e: IllegalArgumentException) {
            // FileProvider could not map the path - the download landed outside
            // res/xml/update_paths.xml.
            result.error("bad_uri", "APK path is not shared with the installer", e.message)
        } catch (e: android.content.ActivityNotFoundException) {
            result.error("no_installer", "No package installer available", e.message)
        }
    }
}