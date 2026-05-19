package com.example.parcel_scanner

import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothManager
import android.bluetooth.BluetoothSocket
import android.content.Context
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.OutputStream
import java.util.UUID
import kotlin.concurrent.thread

/**
 * Bluetooth-Classic SPP (RFCOMM) driver for the HPRT HM-T3 Pro, exposed to
 * Flutter over a MethodChannel.
 *
 * The printer speaks ZPL and is reached over a plain [BluetoothSocket] — no
 * HPRT SDK, no BLE. The socket is held here as process-wide state, so a
 * connection opened from any Flutter screen is shared by all of them.
 */
class HprtPrinterChannel(private val context: Context) :
    MethodChannel.MethodCallHandler {

    companion object {
        const val CHANNEL = "hprt_printer"

        /** Standard Serial Port Profile (RFCOMM) service UUID. */
        private val SPP_UUID: UUID =
            UUID.fromString("00001101-0000-1000-8000-00805F9B34FB")

        /** Bluetooth buffers overrun on large writes — stream in chunks. */
        private const val CHUNK = 2048
    }

    @Volatile private var socket: BluetoothSocket? = null
    @Volatile private var output: OutputStream? = null

    private fun adapter(): BluetoothAdapter? =
        (context.getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager)
            ?.adapter

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        // Every Bluetooth call blocks — run off the main thread and post the
        // MethodChannel result back on the main thread.
        when (call.method) {
            "getPairedPrinters" -> onBg(result) {
                (adapter()?.bondedDevices ?: emptySet())
                    .filter { it.name != null }
                    .map { mapOf("name" to it.name, "address" to it.address) }
            }

            "isConnected" -> onBg(result) { socket?.isConnected == true }

            "connect" -> {
                val address = call.argument<String>("address")
                if (address == null) {
                    result.error("PRINTER", "address is required", null)
                    return
                }
                onBg(result) {
                    val a = adapter() ?: error("Bluetooth is unavailable on this device")
                    if (!a.isEnabled) error("Bluetooth is turned off")
                    a.cancelDiscovery()
                    close() // drop any previous socket
                    val s = a.getRemoteDevice(address)
                        .createRfcommSocketToServiceRecord(SPP_UUID)
                    s.connect() // blocking; throws on failure
                    socket = s
                    output = s.outputStream
                    true
                }
            }

            "printBytes" -> {
                val bytes = call.argument<ByteArray>("bytes")
                if (bytes == null) {
                    result.error("PRINTER", "bytes is required", null)
                    return
                }
                onBg(result) {
                    val out = output ?: error("Printer not connected")
                    var off = 0
                    while (off < bytes.size) {
                        val len = minOf(CHUNK, bytes.size - off)
                        out.write(bytes, off, len)
                        out.flush()
                        off += len
                        if (off < bytes.size) Thread.sleep(20)
                    }
                    true
                }
            }

            "disconnect" -> onBg(result) { close(); true }

            else -> result.notImplemented()
        }
    }

    private fun close() {
        runCatching { output?.close() }
        runCatching { socket?.close() }
        output = null
        socket = null
    }

    /** Runs [block] on a worker thread; delivers the result on the main thread. */
    private fun onBg(result: MethodChannel.Result, block: () -> Any?) {
        thread {
            val outcome = runCatching(block)
            android.os.Handler(android.os.Looper.getMainLooper()).post {
                outcome.fold(
                    onSuccess = { result.success(it) },
                    onFailure = {
                        close()
                        result.error("PRINTER", it.message ?: "printer error", null)
                    },
                )
            }
        }
    }
}
