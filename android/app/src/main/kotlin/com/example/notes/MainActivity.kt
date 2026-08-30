package com.example.notes

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        flutterEngine.platformViewsController.registry.registerViewFactory(
            "com.example.notes/low_latency_canvas",
            LowLatencyDrawingViewFactory(flutterEngine.dartExecutor.binaryMessenger)
        )
    }
}
