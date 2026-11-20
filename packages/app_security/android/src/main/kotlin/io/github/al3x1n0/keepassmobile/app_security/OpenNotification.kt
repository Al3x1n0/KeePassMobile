package io.github.al3x1n0.keepassmobile.app_security

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.graphics.drawable.Icon
import android.os.Build
import io.flutter.plugin.common.EventChannel

/**
 * Notifica fissa del database aperto con l'azione "Blocca", come la notifica
 * "database sbloccato" di `OngoingNotificationsService` di Keepass2Android ma
 * senza servizio in primo piano (decisione D19 rivista, ADR-012).
 *
 * Senza servizio la notifica può sopravvivere al processo che l'ha mostrata:
 * - all'avvio di un processo nuovo quella rimasta si toglie ([cancelStale]);
 * - "Blocca" senza Dart in ascolto toglie solo la notifica ([lockRequested]);
 * - alla chiusura del motore Flutter (database perso) si toglie.
 *
 * Un processo può avere più motori (compilazione automatica, ADR-013): la
 * notifica e "Blocca" appartengono al plugin del motore che li ha usati, e gli
 * altri motori non li toccano.
 *
 * Testi senza dati del database: la notifica è visibile anche sulla schermata
 * di blocco.
 */
internal object OpenNotification {
  const val ACTION_LOCK = "io.github.al3x1n0.keepassmobile.app_security.LOCK_DATABASE"
  private const val CHANNEL_ID = "open_database"
  private const val NOTIFICATION_ID = 200
  private const val LOCK_REQUEST = 0
  private const val OPEN_REQUEST = 1

  /** Plugin (motore Flutter) che ha mostrato la notifica; `null` se non c'è. */
  private var owner: Any? = null

  /** Destinatario di "Blocca" mentre Dart ascolta, e il suo plugin. */
  private var lockSink: EventChannel.EventSink? = null
  private var lockOwner: Any? = null

  /** Ascolto di "Blocca" per il motore di [plugin]. */
  fun lockEvents(plugin: Any) = object : EventChannel.StreamHandler {
    override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
      lockSink = events
      lockOwner = plugin
    }

    override fun onCancel(arguments: Any?) {
      if (lockOwner === plugin) {
        lockSink = null
        lockOwner = null
      }
    }
  }

  fun show(
    context: Context,
    plugin: Any,
    channelName: String,
    title: String,
    text: String,
    lock: String,
  ): Boolean {
    val manager = context.getSystemService(NotificationManager::class.java) ?: return false
    if (!manager.areNotificationsEnabled()) return false
    val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
      manager.createNotificationChannel(
        NotificationChannel(CHANNEL_ID, channelName, NotificationManager.IMPORTANCE_LOW).apply {
          setShowBadge(false)
        },
      )
      Notification.Builder(context, CHANNEL_ID)
    } else {
      @Suppress("DEPRECATION")
      Notification.Builder(context).setPriority(Notification.PRIORITY_LOW)
    }
    val icon = Icon.createWithResource(context, R.drawable.app_security_ic_lock)
    val lockIntent = PendingIntent.getBroadcast(
      context,
      LOCK_REQUEST,
      Intent(context, OpenNotificationReceiver::class.java).setAction(ACTION_LOCK),
      PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
    )
    builder
      .setSmallIcon(icon)
      .setContentTitle(title)
      .setContentText(text)
      .setOngoing(true)
      .setOnlyAlertOnce(true)
      .setShowWhen(false)
      .setCategory(Notification.CATEGORY_STATUS)
      .setVisibility(Notification.VISIBILITY_PUBLIC)
      .addAction(Notification.Action.Builder(icon, lock, lockIntent).build())
    openApp(context)?.let { builder.setContentIntent(it) }
    manager.notify(NOTIFICATION_ID, builder.build())
    owner = plugin
    return true
  }

  /** Toglie la notifica se l'ha mostrata [plugin] (o se non è di nessuno). */
  fun hide(context: Context, plugin: Any) {
    if (owner == null || owner === plugin) cancel(context)
  }

  /** Toglie la notifica rimasta da un processo precedente. */
  fun cancelStale(context: Context) {
    if (owner == null) cancel(context)
  }

  /** Motore di [plugin] chiuso: il suo database in memoria non c'è più. */
  fun detach(context: Context, plugin: Any) {
    hide(context, plugin)
    if (lockOwner === plugin) {
      lockSink = null
      lockOwner = null
    }
  }

  fun lockRequested(context: Context) {
    val sink = lockSink
    if (sink != null) sink.success(EVENT) else cancel(context)
  }

  private fun cancel(context: Context) {
    context.getSystemService(NotificationManager::class.java)?.cancel(NOTIFICATION_ID)
    owner = null
  }

  /** Riporta in primo piano l'app (o la avvia, se è stata chiusa). */
  private fun openApp(context: Context): PendingIntent? {
    val launch = context.packageManager.getLaunchIntentForPackage(context.packageName) ?: return null
    launch.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_RESET_TASK_IF_NEEDED)
    return PendingIntent.getActivity(
      context,
      OPEN_REQUEST,
      launch,
      PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
    )
  }

  private const val EVENT = "lock"
}

/** Azione "Blocca" della notifica; non esportato: le altre app non la inviano. */
class OpenNotificationReceiver : BroadcastReceiver() {
  override fun onReceive(context: Context, intent: Intent) {
    if (intent.action == OpenNotification.ACTION_LOCK) {
      OpenNotification.lockRequested(context.applicationContext)
    }
  }
}
