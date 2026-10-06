package io.github.sensorslab.app_scanner

import android.content.Intent
import android.content.pm.ApplicationInfo
import android.content.pm.PackageInfo
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.security.MessageDigest
import java.security.cert.CertificateFactory
import java.security.cert.X509Certificate
import java.util.concurrent.Executors

/**
 * Reads what Android publicly reports about installed apps (flags, target
 * SDK, permissions, exported components, signing certificate, APK path) and
 * hands it to Dart, where the security rules live.
 *
 * Security notes:
 * - No permissions at all: app visibility comes from a <queries> entry for
 *   launcher apps, not from QUERY_ALL_PACKAGES.
 * - Read-only: nothing is modified, stored, or sent (no INTERNET permission).
 * - Package names from Dart are checked against installed packages before use.
 */
class MainActivity : FlutterActivity() {
    private val worker = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "app_scanner/packages").setMethodCallHandler { call, result ->
            when (call.method) {
                "list" -> worker.execute {
                    val out = runCatching { listApps() }
                    main.post { out.fold(result::success) { result.error("FAILED", it.message, null) } }
                }
                "icon" -> {
                    val pkg = call.argument<String>("package")
                    if (!isInstalled(pkg)) {
                        result.error("BAD_ARGS", "unknown package", null)
                    } else {
                        worker.execute {
                            val png = runCatching { iconPng(pkg!!) }.getOrNull()
                            main.post { result.success(png) }
                        }
                    }
                }
                "openSettings" -> {
                    val pkg = call.argument<String>("package")
                    if (!isInstalled(pkg)) {
                        result.error("BAD_ARGS", "unknown package", null)
                    } else {
                        startActivity(Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.fromParts("package", pkg, null)))
                        result.success(null)
                    }
                }
                "sdk" -> result.success(Build.VERSION.SDK_INT)
                else -> result.notImplemented()
            }
        }
    }

    override fun onDestroy() {
        worker.shutdownNow()
        super.onDestroy()
    }

    private fun isInstalled(pkg: String?): Boolean {
        if (pkg == null || !PACKAGE_RE.matches(pkg)) return false
        return runCatching { packageManager.getApplicationInfo(pkg, 0) }.isSuccess
    }

    private fun launcherPackages(): Set<String> {
        val intent = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER)
        return packageManager.queryIntentActivities(intent, 0).map { it.activityInfo.packageName }.toSet()
    }

    @Suppress("DEPRECATION")
    private fun packageInfo(pkg: String): PackageInfo {
        val flags = PackageManager.GET_PERMISSIONS or PackageManager.GET_ACTIVITIES or PackageManager.GET_SERVICES or
            PackageManager.GET_RECEIVERS or PackageManager.GET_PROVIDERS or PackageManager.GET_SIGNING_CERTIFICATES or
            PackageManager.MATCH_DISABLED_COMPONENTS
        return if (Build.VERSION.SDK_INT >= 33) {
            packageManager.getPackageInfo(pkg, PackageManager.PackageInfoFlags.of(flags.toLong()))
        } else {
            packageManager.getPackageInfo(pkg, flags)
        }
    }

    private fun listApps(): List<Map<String, Any?>> {
        val self = packageName
        return launcherPackages().filter { it != self }.mapNotNull { pkg ->
            runCatching { describe(packageInfo(pkg)) }.getOrNull()
        }
    }

    private fun describe(p: PackageInfo): Map<String, Any?> {
        val ai = p.applicationInfo ?: throw IllegalStateException("no application info")
        val launcher = packageManager.getLaunchIntentForPackage(p.packageName)?.component?.className
        val perms = p.requestedPermissions?.mapIndexed { i, name ->
            val granted = (p.requestedPermissionsFlags?.getOrNull(i) ?: 0) and PackageInfo.REQUESTED_PERMISSION_GRANTED != 0
            mapOf("name" to name, "granted" to granted)
        } ?: emptyList()

        fun comp(kind: String, name: String, exported: Boolean, enabled: Boolean, permission: String?, extra: Map<String, Any?> = emptyMap()) =
            mapOf("kind" to kind, "name" to name, "exported" to exported, "enabled" to enabled,
                "permission" to permission, "launcher" to (name == launcher)) + extra

        val components = buildList {
            p.activities?.forEach { add(comp("activity", it.name, it.exported, it.enabled, it.permission)) }
            p.services?.forEach { add(comp("service", it.name, it.exported, it.enabled, it.permission)) }
            p.receivers?.forEach { add(comp("receiver", it.name, it.exported, it.enabled, it.permission)) }
            p.providers?.forEach {
                add(comp("provider", it.name, it.exported, it.enabled, null, mapOf(
                    "readPermission" to it.readPermission, "writePermission" to it.writePermission,
                    "authority" to it.authority, "grantUriPermissions" to it.grantUriPermissions)))
            }
        }

        val certs = signingCertificates(p)
        val installer = runCatching {
            if (Build.VERSION.SDK_INT >= 30) packageManager.getInstallSourceInfo(p.packageName).installingPackageName
            else @Suppress("DEPRECATION") packageManager.getInstallerPackageName(p.packageName)
        }.getOrNull()
        val apkPaths = listOfNotNull(ai.sourceDir) + (ai.splitSourceDirs?.toList() ?: emptyList())

        return mapOf(
            "package" to p.packageName,
            "label" to packageManager.getApplicationLabel(ai).toString(),
            "versionName" to p.versionName,
            "versionCode" to (if (Build.VERSION.SDK_INT >= 28) p.longVersionCode else @Suppress("DEPRECATION") p.versionCode.toLong()),
            "targetSdk" to ai.targetSdkVersion,
            "minSdk" to (if (Build.VERSION.SDK_INT >= 24) ai.minSdkVersion else 0),
            "system" to ((ai.flags and ApplicationInfo.FLAG_SYSTEM) != 0),
            "updatedSystem" to ((ai.flags and ApplicationInfo.FLAG_UPDATED_SYSTEM_APP) != 0),
            "debuggable" to ((ai.flags and ApplicationInfo.FLAG_DEBUGGABLE) != 0),
            "allowBackup" to ((ai.flags and ApplicationInfo.FLAG_ALLOW_BACKUP) != 0),
            "cleartext" to ((ai.flags and ApplicationInfo.FLAG_USES_CLEARTEXT_TRAFFIC) != 0),
            "testOnly" to ((ai.flags and ApplicationInfo.FLAG_TEST_ONLY) != 0),
            "largeHeap" to ((ai.flags and ApplicationInfo.FLAG_LARGE_HEAP) != 0),
            "installer" to installer,
            "firstInstall" to p.firstInstallTime,
            "lastUpdate" to p.lastUpdateTime,
            "apkPaths" to apkPaths,
            "permissions" to perms,
            "components" to components,
            "certificates" to certs,
        )
    }

    @Suppress("DEPRECATION")
    private fun signingCertificates(p: PackageInfo): List<Map<String, Any?>> {
        val sigs: Array<android.content.pm.Signature>? = if (Build.VERSION.SDK_INT >= 28) {
            val info = p.signingInfo
            when {
                info == null -> null
                info.hasMultipleSigners() -> info.apkContentsSigners
                else -> info.signingCertificateHistory
            }
        } else {
            p.signatures
        }
        if (sigs == null) return emptyList()
        val factory = CertificateFactory.getInstance("X.509")
        return sigs.map { sig ->
            val bytes = sig.toByteArray()
            val sha = MessageDigest.getInstance("SHA-256").digest(bytes).joinToString(":") { "%02X".format(it) }
            val cert = runCatching { factory.generateCertificate(bytes.inputStream()) as X509Certificate }.getOrNull()
            mapOf(
                "sha256" to sha,
                "subject" to cert?.subjectX500Principal?.name,
                "algorithm" to cert?.sigAlgName,
                "keyBits" to cert?.publicKey?.let { keyBits(it) },
                "notAfter" to cert?.notAfter?.time,
            )
        }
    }

    private fun keyBits(key: java.security.PublicKey): Int? = when (key) {
        is java.security.interfaces.RSAPublicKey -> key.modulus.bitLength()
        is java.security.interfaces.ECPublicKey -> key.params.order.bitLength()
        else -> null
    }

    private fun iconPng(pkg: String): ByteArray {
        val d = packageManager.getApplicationIcon(pkg)
        val size = 96
        val bmp = android.graphics.Bitmap.createBitmap(size, size, android.graphics.Bitmap.Config.ARGB_8888)
        val canvas = android.graphics.Canvas(bmp)
        d.setBounds(0, 0, size, size)
        d.draw(canvas)
        val out = ByteArrayOutputStream()
        bmp.compress(android.graphics.Bitmap.CompressFormat.PNG, 100, out)
        bmp.recycle()
        return out.toByteArray()
    }

    companion object {
        private val PACKAGE_RE = Regex("^[A-Za-z][A-Za-z0-9_]*(\\.[A-Za-z0-9_]+)+$")
    }
}
