package icu.yzvibe.android.platform

import android.content.Context
import android.net.nsd.NsdManager
import android.net.nsd.NsdServiceInfo
import android.net.wifi.WifiManager

/** Short-lived discovery, only while the device picker is visible. */
class LanDiscovery(context: Context, private val found: (String, String) -> Unit) : AutoCloseable {
    private val manager = context.getSystemService(Context.NSD_SERVICE) as NsdManager
    private val lock =
        (context.applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager)
            .createMulticastLock("yzvibe-discovery")
            .apply { setReferenceCounted(false) }
    private var open = false
    private val listener =
        object : NsdManager.DiscoveryListener {
            override fun onDiscoveryStarted(type: String) {}

            override fun onDiscoveryStopped(type: String) {}

            override fun onStartDiscoveryFailed(type: String, code: Int) {
                close()
            }

            override fun onStopDiscoveryFailed(type: String, code: Int) {
                lock.releaseIfHeld()
            }

            override fun onServiceLost(service: NsdServiceInfo) {}

            override fun onServiceFound(service: NsdServiceInfo) {
                @Suppress("DEPRECATION")
                manager.resolveService(
                    service,
                    object : NsdManager.ResolveListener {
                        override fun onResolveFailed(info: NsdServiceInfo, code: Int) {}

                        override fun onServiceResolved(info: NsdServiceInfo) {
                            val host = info.host?.hostAddress ?: return
                            if (open)
                                found(
                                    info.serviceName,
                                    "http://${if (host.contains(':')) "[$host]" else host}:${info.port}",
                                )
                        }
                    },
                )
            }
        }

    fun start() {
        if (open) return
        open = true
        lock.acquire()
        manager.discoverServices("_yzvibe._tcp.", NsdManager.PROTOCOL_DNS_SD, listener)
    }

    override fun close() {
        if (open) {
            open = false
            runCatching { manager.stopServiceDiscovery(listener) }
        }
        lock.releaseIfHeld()
    }

    private fun WifiManager.MulticastLock.releaseIfHeld() {
        if (isHeld) release()
    }
}
