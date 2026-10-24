package com.example.open_car_app

import android.app.Application
import android.util.Log
import com.polidea.rxandroidble2.exceptions.BleDisconnectedException
import com.polidea.rxandroidble2.exceptions.BleGattException
import io.reactivex.exceptions.UndeliverableException
import io.reactivex.plugins.RxJavaPlugins

class OpenCarApplication : Application() {

    override fun onCreate() {
        super.onCreate()

        // flutter_reactive_ble uses RxAndroidBle (RxJava 2) internally and
        // installs no RxJavaPlugins error handler of its own. When the link is
        // lost while an operation is in flight and its subscriber has already
        // been disposed, RxJava 2 has nowhere to route the resulting
        // BleDisconnectedException, wraps it in an UndeliverableException and
        // hands it to the thread's uncaught-exception handler, which kills the
        // process (https://github.com/dariuszseweryn/RxAndroidBle/wiki/FAQ:-UndeliverableException).
        //
        // Only link-loss errors are dropped (and logged); anything else takes
        // RxJava's default path, so genuine bugs still crash.
        RxJavaPlugins.setErrorHandler { throwable ->
            if (isBenignLinkLoss(throwable)) {
                Log.w(TAG, "Ignoring undeliverable BLE error after link loss", throwable)
                return@setErrorHandler
            }
            // Same as RxJava's default when no handler is installed.
            val thread = Thread.currentThread()
            thread.uncaughtExceptionHandler.uncaughtException(thread, throwable)
        }
    }

    companion object {
        private const val TAG = "OpenCarApplication"

        // Bounds the walk down the cause chain, in case it is cyclic.
        private const val MAX_CAUSE_DEPTH = 10

        /**
         * True if [throwable], or something it wraps, is a RxAndroidBle
         * disconnect or GATT error. These are what an operation still in
         * flight fails with when the link drops.
         *
         * The check uses `is` on the exception classes, not their names:
         * release builds are minified by R8, which renames them (the crash
         * report in #49 shows `D0.b`) but rewrites the references to match.
         */
        private fun isBenignLinkLoss(throwable: Throwable): Boolean {
            var current: Throwable? = throwable
            var depth = 0
            while (current != null && depth < MAX_CAUSE_DEPTH) {
                if (current is BleDisconnectedException || current is BleGattException) {
                    return true
                }
                current = current.cause
                depth++
            }
            return false
        }
    }
}
