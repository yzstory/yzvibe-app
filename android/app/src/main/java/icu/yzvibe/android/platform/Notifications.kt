package icu.yzvibe.android.platform

import android.Manifest
import android.app.*
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import icu.yzvibe.android.MainActivity
import icu.yzvibe.android.core.Snapshot
import icu.yzvibe.android.core.str

/** Vendor SDK adapters provide registration; an APNs token must never be reused here. */
interface PushProvider {
    val id: String

    suspend fun register(): PushRegistration

    suspend fun unregister()
}

data class PushRegistration(val provider: String, val token: String, val applicationId: String)

class TaskNotifications(private val context: Context) {
    private val manager = context.getSystemService(NotificationManager::class.java)

    init {
        manager.createNotificationChannel(
            NotificationChannel("tasks", "进行中的任务", NotificationManager.IMPORTANCE_LOW)
        )
        manager.createNotificationChannel(
            NotificationChannel("approvals", "审批提醒", NotificationManager.IMPORTANCE_DEFAULT)
        )
    }

    fun update(snapshot: Snapshot) {
        if (
            Build.VERSION.SDK_INT >= 33 &&
                context.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) !=
                    PackageManager.PERMISSION_GRANTED
        )
            return
        val intent =
            PendingIntent.getActivity(
                context,
                0,
                Intent(context, MainActivity::class.java),
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
        val running =
            snapshot.sessions.filter { it.str("status") in listOf("running", "waiting_approval") }
        if (running.isEmpty()) manager.cancel(100)
        else
            manager.notify(
                100,
                Notification.Builder(context, "tasks")
                    .setSmallIcon(android.R.drawable.stat_notify_sync)
                    .setContentTitle("${running.size} 个任务进行中")
                    .setContentText(running.take(3).joinToString(" · ") { it.str("title") })
                    .setStyle(
                        Notification.InboxStyle().also { style ->
                            running.take(3).forEach {
                                style.addLine("${it.str("agent")} · ${it.str("title")}")
                            }
                            style.setSummaryText("应用离开前台后，此状态可能不是最新")
                        }
                    )
                    .setOnlyAlertOnce(true)
                    .setContentIntent(intent)
                    .build(),
            )
        if (snapshot.approvals.isEmpty()) manager.cancel(101)
        else
            manager.notify(
                101,
                Notification.Builder(context, "approvals")
                    .setSmallIcon(android.R.drawable.ic_dialog_alert)
                    .setContentTitle("${snapshot.approvals.size} 项待审批")
                    .setContentText(snapshot.approvals.first().str("summary"))
                    .setOnlyAlertOnce(true)
                    .setContentIntent(intent)
                    .build(),
            )
    }
}
