package io.github.al3x1n0.keepassmobile.app_security

import android.Manifest
import android.app.Activity
import android.app.NotificationManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.hardware.biometrics.BiometricManager
import android.os.Build
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.PluginRegistry

/**
 * Eventi di sicurezza per KeePassMobile: spegnimento dello schermo, come
 * `App.OnScreenOff` di Keepass2Android.
 *
 * `ACTION_SCREEN_OFF` si riceve solo con un receiver registrato a runtime:
 * viene registrato quando Dart inizia ad ascoltare e rimosso quando smette.
 *
 * `hasStrongBiometrics`: biometria forte registrata (proposta dello sblocco
 * biometrico). Prima di Android 10 risponde `false`.
 *
 * Notifica del database aperto con "Blocca" ([OpenNotification]) e permesso
 * `POST_NOTIFICATIONS` (Android 13+), chiesto dall'activity.
 */
class AppSecurityPlugin :
  FlutterPlugin,
  EventChannel.StreamHandler,
  MethodChannel.MethodCallHandler,
  ActivityAware,
  PluginRegistry.RequestPermissionsResultListener {
  private var context: Context? = null
  private var channel: EventChannel? = null
  private var lockChannel: EventChannel? = null
  private var methods: MethodChannel? = null
  private var receiver: BroadcastReceiver? = null
  private var activityBinding: ActivityPluginBinding? = null
  private var pendingPermission: MethodChannel.Result? = null

  override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
    context = binding.applicationContext
    // Notifica rimasta da un processo chiuso dal sistema: nessun database aperto.
    OpenNotification.cancelStale(binding.applicationContext)
    channel = EventChannel(binding.binaryMessenger, CHANNEL).also {
      it.setStreamHandler(this)
    }
    lockChannel = EventChannel(binding.binaryMessenger, LOCK_CHANNEL).also {
      it.setStreamHandler(OpenNotification.lockEvents(this))
    }
    methods = MethodChannel(binding.binaryMessenger, METHODS).also {
      it.setMethodCallHandler(this)
    }
  }

  override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
    when (call.method) {
      "getAppVersion" -> result.success(getAppVersion())
      "hasStrongBiometrics" -> result.success(hasStrongBiometrics())
      "requestNotificationPermission" -> requestNotificationPermission(result)
      "showOpenNotification" -> {
        val ctx = context
        if (ctx == null) {
          result.success(false)
          return
        }
        result.success(
          OpenNotification.show(
            ctx,
            this,
            channelName = call.argument<String>("channel") ?: "",
            title = call.argument<String>("title") ?: "",
            text = call.argument<String>("text") ?: "",
            lock = call.argument<String>("lock") ?: "",
          ),
        )
      }
      "hideOpenNotification" -> {
        context?.let { OpenNotification.hide(it, this) }
        result.success(true)
      }
      else -> result.notImplemented()
    }
  }

  private fun getAppVersion(): String? {
    val ctx = context ?: return null
    return try {
      val info = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
        ctx.packageManager.getPackageInfo(ctx.packageName, PackageManager.PackageInfoFlags.of(0))
      } else {
        @Suppress("DEPRECATION")
        ctx.packageManager.getPackageInfo(ctx.packageName, 0)
      }
      info.versionName
    } catch (e: PackageManager.NameNotFoundException) {
      null
    } catch (e: SecurityException) {
      null
    }
  }

  private fun hasStrongBiometrics(): Boolean {
    val ctx = context ?: return false
    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) return false
    val manager = ctx.getSystemService(BiometricManager::class.java) ?: return false
    return try {
      val status = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
        manager.canAuthenticate(BiometricManager.Authenticators.BIOMETRIC_STRONG)
      } else {
        @Suppress("DEPRECATION")
        manager.canAuthenticate()
      }
      status == BiometricManager.BIOMETRIC_SUCCESS
    } catch (e: SecurityException) {
      false
    }
  }

  private fun notificationsEnabled(): Boolean =
    context?.getSystemService(NotificationManager::class.java)?.areNotificationsEnabled() ?: false

  private fun requestNotificationPermission(result: MethodChannel.Result) {
    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) {
      result.success(notificationsEnabled())
      return
    }
    val activity: Activity? = activityBinding?.activity
    if (activity == null || pendingPermission != null) {
      result.success(notificationsEnabled())
      return
    }
    if (activity.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) ==
      PackageManager.PERMISSION_GRANTED
    ) {
      result.success(notificationsEnabled())
      return
    }
    pendingPermission = result
    activity.requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), PERMISSION_REQUEST)
  }

  override fun onRequestPermissionsResult(
    requestCode: Int,
    permissions: Array<out String>,
    grantResults: IntArray,
  ): Boolean {
    if (requestCode != PERMISSION_REQUEST) return false
    val result = pendingPermission ?: return true
    pendingPermission = null
    result.success(grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED)
    return true
  }

  override fun onAttachedToActivity(binding: ActivityPluginBinding) {
    activityBinding = binding
    binding.addRequestPermissionsResultListener(this)
  }

  override fun onDetachedFromActivityForConfigChanges() = onDetachedFromActivity()

  override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) =
    onAttachedToActivity(binding)

  override fun onDetachedFromActivity() {
    activityBinding?.removeRequestPermissionsResultListener(this)
    activityBinding = null
    pendingPermission?.success(notificationsEnabled())
    pendingPermission = null
  }

  override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
    onCancel(null)
    // Motore chiuso: il database in memoria non c'è più.
    OpenNotification.detach(binding.applicationContext, this)
    channel?.setStreamHandler(null)
    channel = null
    lockChannel?.setStreamHandler(null)
    lockChannel = null
    methods?.setMethodCallHandler(null)
    methods = null
    context = null
  }

  override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
    val ctx = context ?: return
    onCancel(null)
    val screenOff = object : BroadcastReceiver() {
      override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == Intent.ACTION_SCREEN_OFF) events.success(EVENT)
      }
    }
    val filter = IntentFilter(Intent.ACTION_SCREEN_OFF)
    // Broadcast di sistema: arriva anche con RECEIVER_NOT_EXPORTED, che
    // esclude le altre app.
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
      ctx.registerReceiver(screenOff, filter, Context.RECEIVER_NOT_EXPORTED)
    } else {
      ctx.registerReceiver(screenOff, filter)
    }
    receiver = screenOff
  }

  override fun onCancel(arguments: Any?) {
    val registered = receiver ?: return
    receiver = null
    context?.unregisterReceiver(registered)
  }

  private companion object {
    const val CHANNEL = "io.github.al3x1n0.keepassmobile/app_security/screen_off"
    const val LOCK_CHANNEL = "io.github.al3x1n0.keepassmobile/app_security/notification_lock"
    const val METHODS = "io.github.al3x1n0.keepassmobile/app_security"
    const val EVENT = "screen_off"
    const val PERMISSION_REQUEST = 0x4b50
  }
}
