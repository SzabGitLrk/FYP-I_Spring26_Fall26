package com.example.eyris_app;

import android.content.Context;
import android.media.AudioManager;
import android.media.ToneGenerator;
import android.net.wifi.WifiManager;
import android.os.Handler;
import android.os.Looper;

import androidx.annotation.NonNull;

import io.flutter.embedding.android.FlutterActivity;
import io.flutter.embedding.engine.FlutterEngine;
import io.flutter.plugin.common.MethodChannel;

public class MainActivity extends FlutterActivity {
    private static final String MULTICAST_CHANNEL =
            "com.example.eyris_app/wifi_multicast_lock";
    private static final String BEEP_CHANNEL =
            "com.example.eyris_app/warning_beep";
    private WifiManager.MulticastLock multicastLock;
    private ToneGenerator warningToneGenerator;

    @Override
    public void configureFlutterEngine(@NonNull FlutterEngine flutterEngine) {
        super.configureFlutterEngine(flutterEngine);
        new MethodChannel(flutterEngine.getDartExecutor().getBinaryMessenger(), MULTICAST_CHANNEL)
                .setMethodCallHandler((call, result) -> {
                    if ("acquire".equals(call.method)) {
                        acquireMulticastLock(result);
                    } else if ("release".equals(call.method)) {
                        releaseMulticastLock();
                        result.success(null);
                    } else {
                        result.notImplemented();
                    }
                });
        new MethodChannel(flutterEngine.getDartExecutor().getBinaryMessenger(), BEEP_CHANNEL)
                .setMethodCallHandler((call, result) -> {
                    if ("playWarningBeep".equals(call.method)) {
                        playWarningBeep(result);
                    } else {
                        result.notImplemented();
                    }
                });
    }

    private void acquireMulticastLock(MethodChannel.Result result) {
        try {
            if (multicastLock == null || !multicastLock.isHeld()) {
                WifiManager wifiManager = (WifiManager) getApplicationContext()
                        .getSystemService(Context.WIFI_SERVICE);
                if (wifiManager == null) {
                    result.error("WIFI_UNAVAILABLE", "Wi-Fi service unavailable", null);
                    return;
                }
                multicastLock = wifiManager.createMulticastLock("eyris_udp_4567");
                multicastLock.setReferenceCounted(false);
                multicastLock.acquire();
            }
            result.success(null);
        } catch (SecurityException error) {
            result.error("MULTICAST_LOCK_FAILED", error.getMessage(), null);
        }
    }

    private void releaseMulticastLock() {
        if (multicastLock != null && multicastLock.isHeld()) {
            multicastLock.release();
        }
        multicastLock = null;
    }

    private void playWarningBeep(MethodChannel.Result result) {
        try {
            if (warningToneGenerator != null) {
                result.success(null);
                return;
            }
            ToneGenerator tone = new ToneGenerator(AudioManager.STREAM_ALARM, 80);
            warningToneGenerator = tone;
            tone.startTone(ToneGenerator.TONE_PROP_BEEP, 180);
            new Handler(Looper.getMainLooper()).postDelayed(() -> {
                tone.release();
                if (warningToneGenerator == tone) warningToneGenerator = null;
            }, 220);
            result.success(null);
        } catch (RuntimeException error) {
            warningToneGenerator = null;
            result.error("WARNING_BEEP_FAILED", error.getMessage(), null);
        }
    }

    @Override
    protected void onDestroy() {
        releaseMulticastLock();
        if (warningToneGenerator != null) {
            warningToneGenerator.release();
            warningToneGenerator = null;
        }
        super.onDestroy();
    }
}
