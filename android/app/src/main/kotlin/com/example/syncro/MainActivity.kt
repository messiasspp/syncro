package com.example.syncro

import android.os.Build
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableHighRefreshRate()
    }

    override fun onResume() {
        super.onResume()
        enableHighRefreshRate()
    }

    private fun enableHighRefreshRate() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            val currentDisplay = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                display
            } else {
                @Suppress("DEPRECATION")
                windowManager.defaultDisplay
            } ?: return

            val supportedModes = currentDisplay.supportedModes
            if (supportedModes.isNullOrEmpty()) return

            val activeMode = currentDisplay.mode
            // Pick the mode matching current resolution with the highest refresh rate (e.g. 120Hz)
            val highestRefreshMode = supportedModes
                .filter {
                    it.physicalWidth == activeMode.physicalWidth &&
                        it.physicalHeight == activeMode.physicalHeight
                }
                .maxByOrNull { it.refreshRate }
                ?: supportedModes.maxByOrNull { it.refreshRate }
                ?: return

            val layoutParams = window.attributes
            if (layoutParams.preferredDisplayModeId != highestRefreshMode.modeId ||
                layoutParams.preferredRefreshRate != highestRefreshMode.refreshRate
            ) {
                layoutParams.preferredDisplayModeId = highestRefreshMode.modeId
                layoutParams.preferredRefreshRate = highestRefreshMode.refreshRate
                window.attributes = layoutParams
            }
        }
    }
}
