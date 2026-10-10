package com.nischalpandey.noctune

import android.app.ActivityManager
import android.content.Context
import android.os.Build
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Reports how much memory this device has and whether it is 64-bit, which
 * decides how elaborate the navigation bar's glass effect is allowed to be.
 */
class DeviceProfileChannel(private val context: Context) : MethodChannel.MethodCallHandler {
    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "memory" -> {
                val manager =
                    context.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
                val info = ActivityManager.MemoryInfo().also(manager::getMemoryInfo)
                result.success(
                    mapOf(
                        "lowRam" to manager.isLowRamDevice,
                        "totalMb" to (info.totalMem / (1024L * 1024L)).toInt(),
                        "has64Bit" to Build.SUPPORTED_64_BIT_ABIS.isNotEmpty(),
                    ),
                )
            }
            else -> result.notImplemented()
        }
    }
}
