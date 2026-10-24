package com.example.notes

import android.content.Context
import android.graphics.Color
import android.graphics.PixelFormat
import android.graphics.PointF
import android.opengl.GLES20
import android.opengl.Matrix
import android.util.Log
import android.view.MotionEvent
import android.view.Surface
import android.view.SurfaceHolder
import android.view.SurfaceView
import android.view.View
import androidx.graphics.opengl.egl.EGLManager
import androidx.graphics.lowlatency.GLFrontBufferedRenderer
import androidx.graphics.lowlatency.BufferInfo
import androidx.input.motionprediction.MotionEventPredictor
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.platform.PlatformView
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.nio.FloatBuffer

private const val TAG = "LowLatencyDrawingView"

class LowLatencyDrawingView(
    context: Context,
    private val id: Int,
    messenger: BinaryMessenger
) : PlatformView, SurfaceView(context), SurfaceHolder.Callback, MethodChannel.MethodCallHandler {

    private val methodChannel = MethodChannel(messenger, "com.example.notes/low_latency_canvas_$id")
    
    // Stroke model
    data class StrokeData(
        val points: MutableList<PointF> = mutableListOf(),
        var color: Int = Color.BLACK,
        var width: Float = 5.0f,
        var penType: Int = 1 // 0=fountain, 1=ballpoint, 2=brush
    ) {
        /** Copy made on the UI thread so the render thread never reads a list that is still growing. */
        fun snapshot(): StrokeData = copy(points = points.toMutableList())
    }

    // Only the UI thread touches completedStrokes. The render thread reads renderedStrokes,
    // an immutable copy that publishStrokes() replaces after every change.
    private val completedStrokes = mutableListOf<StrokeData>()
    @Volatile private var renderedStrokes: List<StrokeData> = emptyList()
    private var activeStroke: StrokeData? = null
    
    // Pen settings
    private var currentPenColor = Color.BLACK
    private var currentPenWidth = 5.0f
    private var currentPenType = 1 // ballpoint

    // OpenGL Front Buffer Renderer
    private var frontBufferRenderer: GLFrontBufferedRenderer<StrokeData>? = null
    
    // Motion Event Predictor for stylus input
    private var motionEventPredictor: MotionEventPredictor? = null

    // Reusable objects for zero-allocation rendering
    private val reusablePredictedStroke = StrokeData(points = mutableListOf())
    private var rawByteBuffer: ByteBuffer? = null
    private var vertexBuffer: FloatBuffer? = null

    // OpenGL shaders & program
    private var glProgram = 0
    private var positionHandle = 0
    private var colorHandle = 0
    private var mvpMatrixHandle = 0

    init {
        // Make the SurfaceView transparent so it overlays beautifully on Flutter background
        setZOrderOnTop(true)
        holder.setFormat(PixelFormat.TRANSLUCENT)
        holder.addCallback(this)
        
        methodChannel.setMethodCallHandler(this)
    }

    override fun getView(): View {
        return this
    }

    override fun dispose() {
        methodChannel.setMethodCallHandler(null)
        motionEventPredictor = null
        frontBufferRenderer?.release(true)
        frontBufferRenderer = null
        rawByteBuffer = null
        vertexBuffer = null
    }

    // ── Method Channel Handler ───────────────────────────────────────────────
    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "setStrokes" -> {
                val strokeList = call.arguments as? List<Map<String, Any>>
                if (strokeList != null) {
                    completedStrokes.clear()
                    for (s in strokeList) {
                        val colorVal = (s["color"] as? Number)?.toLong() ?: 0xFF000000L
                        val widthVal = (s["width"] as? Number)?.toFloat() ?: 5.0f
                        val penTypeVal = (s["penType"] as? Number)?.toInt() ?: 1
                        val pointsVal = s["points"] as? List<Map<String, Any>>
                        
                        val stroke = StrokeData(
                            color = colorVal.toInt(),
                            width = widthVal,
                            penType = penTypeVal
                        )
                        if (pointsVal != null) {
                            for (p in pointsVal) {
                                val x = (p["x"] as? Number)?.toFloat() ?: 0f
                                val y = (p["y"] as? Number)?.toFloat() ?: 0f
                                stroke.points.add(PointF(x, y))
                            }
                        }
                        completedStrokes.add(stroke)
                    }
                    // Request redraw of double buffered layer
                    triggerRedraw()
                    result.success(null)
                } else {
                    result.error("INVALID_ARGUMENT", "Expected List of strokes", null)
                }
            }
            "clear" -> {
                completedStrokes.clear()
                activeStroke = null
                triggerRedraw()
                result.success(null)
            }
            "setPenSettings" -> {
                val colorVal = (call.argument<Number>("color"))?.toLong() ?: 0xFF000000L
                val widthVal = (call.argument<Number>("width"))?.toFloat() ?: 5.0f
                val penTypeVal = (call.argument<Number>("penType"))?.toInt() ?: 1
                
                currentPenColor = colorVal.toInt()
                currentPenWidth = widthVal
                currentPenType = penTypeVal
                
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    private fun publishStrokes() {
        renderedStrokes = completedStrokes.toList()
    }

    private fun triggerRedraw() {
        publishStrokes()
        frontBufferRenderer?.renderMultiBufferedLayer(renderedStrokes)
    }

    // ── Touch / Stylus Event Handling ─────────────────────────────────────────
    override fun onTouchEvent(event: MotionEvent): Boolean {
        // Request unbuffered dispatch for touch and stylus events to bypass Android's 1-frame batching lag
        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.LOLLIPOP) {
            requestUnbufferedDispatch(event)
        }

        // Record event in predictor for OnePlus pen prediction
        motionEventPredictor?.record(event)

        val x = event.x
        val y = event.y

        when (event.actionMasked) {
            MotionEvent.ACTION_DOWN -> {
                // Initialize active stroke
                val stroke = StrokeData(
                    color = currentPenColor,
                    width = currentPenWidth,
                    penType = currentPenType
                )
                stroke.points.add(PointF(x, y))
                activeStroke = stroke

                // Render front buffer
                frontBufferRenderer?.renderFrontBufferedLayer(stroke.snapshot())
            }
            MotionEvent.ACTION_MOVE -> {
                val stroke = activeStroke ?: return true
                
                // Add historical coordinates for maximum precision
                val historySize = event.historySize
                for (i in 0 until historySize) {
                    stroke.points.add(PointF(event.getHistoricalX(i), event.getHistoricalY(i)))
                }
                stroke.points.add(PointF(x, y))

                // Render front buffer
                frontBufferRenderer?.renderFrontBufferedLayer(stroke.snapshot())
            }
            MotionEvent.ACTION_UP -> {
                val stroke = activeStroke ?: return true
                stroke.points.add(PointF(x, y))
                
                // Add to completed strokes and commit to double buffer
                completedStrokes.add(stroke)
                publishStrokes()
                frontBufferRenderer?.commit()
                
                // Notify Flutter that a stroke has finished
                notifyStrokeFinished(stroke)
                activeStroke = null
            }
            MotionEvent.ACTION_CANCEL -> {
                frontBufferRenderer?.cancel()
                activeStroke = null
            }
        }
        return true
    }

    private fun notifyStrokeFinished(stroke: StrokeData) {
        val pointsList = stroke.points.map { mapOf("x" to it.x, "y" to it.y) }
        val strokeMap = mapOf(
            "color" to (stroke.color.toLong() and 0xFFFFFFFFL),
            "width" to stroke.width,
            "penType" to stroke.penType,
            "points" to pointsList
        )
        methodChannel.invokeMethod("onStrokeFinished", strokeMap)
    }

    // ── SurfaceHolder Callback ───────────────────────────────────────────────
    override fun surfaceCreated(holder: SurfaceHolder) {
        // A new surface gets a new EGL context, so the GL program must be built again.
        resetGLState()

        // Create Motion Event Predictor
        motionEventPredictor = MotionEventPredictor.newInstance(this)

        // Initialize GLFrontBufferedRenderer
        frontBufferRenderer = GLFrontBufferedRenderer(this, object : GLFrontBufferedRenderer.Callback<StrokeData> {
            override fun onDrawFrontBufferedLayer(
                eglManager: EGLManager,
                width: Int,
                height: Int,
                bufferInfo: BufferInfo,
                transform: FloatArray,
                param: StrokeData
            ) {
                initGL()
                
                val mvpMatrix = setupViewport(width, height)
                
                // Clear the screen with transparency
                GLES20.glClearColor(0.0f, 0.0f, 0.0f, 0.0f)
                GLES20.glClear(GLES20.GL_COLOR_BUFFER_BIT)
                
                // Draw the active stroke points
                drawStroke(param, mvpMatrix)
                
                // Query predicted events to close stylus gap
                val predictor = motionEventPredictor
                if (predictor != null) {
                    val predictedEvent = predictor.predict()
                    if (predictedEvent != null) {
                        try {
                            val predictedStroke = reusablePredictedStroke.apply {
                                points.clear()
                                this.color = param.color
                                this.width = param.width
                                this.penType = param.penType
                            }
                            // Gather predicted points
                            val predictedHistory = predictedEvent.historySize
                            for (i in 0 until predictedHistory) {
                                predictedStroke.points.add(PointF(predictedEvent.getHistoricalX(i), predictedEvent.getHistoricalY(i)))
                            }
                            predictedStroke.points.add(PointF(predictedEvent.x, predictedEvent.y))
                            
                            if (predictedStroke.points.isNotEmpty() && param.points.isNotEmpty()) {
                                // Connect active stroke's last point to first predicted point for smoothness
                                predictedStroke.points.add(0, param.points.last())
                                // Draw predicted points with a lighter alpha (e.g. 60% opacity)
                                val alphaColor = Color.argb(
                                    (Color.alpha(param.color) * 0.6f).toInt(),
                                    Color.red(param.color),
                                    Color.green(param.color),
                                    Color.blue(param.color)
                                )
                                predictedStroke.color = alphaColor
                                drawStroke(predictedStroke, mvpMatrix)
                            }
                        } finally {
                            predictedEvent.recycle()
                        }
                    }
                }
            }

            override fun onDrawMultiBufferedLayer(
                eglManager: EGLManager,
                width: Int,
                height: Int,
                bufferInfo: BufferInfo,
                transform: FloatArray,
                params: Collection<StrokeData>
            ) {
                initGL()
                
                val mvpMatrix = setupViewport(width, height)
                
                // Clear the screen with transparency
                GLES20.glClearColor(0.0f, 0.0f, 0.0f, 0.0f)
                GLES20.glClear(GLES20.GL_COLOR_BUFFER_BIT)
                
                // Draw the latest published snapshot, never the live list the UI thread is changing
                for (stroke in renderedStrokes) {
                    drawStroke(stroke, mvpMatrix)
                }
            }
        })

        // Redraw the strokes that already exist. Without this they stay hidden
        // until the next stroke or clear.
        triggerRedraw()
    }

    override fun surfaceChanged(holder: SurfaceHolder, format: Int, width: Int, height: Int) {
        // GLFrontBufferedRenderer automatically handles surface lifecycle internally
    }

    override fun surfaceDestroyed(holder: SurfaceHolder) {
        // Release the renderer to clean up EGL context and render threads
        frontBufferRenderer?.release(true)
        frontBufferRenderer = null
        motionEventPredictor = null
        resetGLState()
    }

    // The program and its handles belong to the EGL context that created them.
    // Forget them whenever that context is released, so initGL rebuilds them.
    private fun resetGLState() {
        glProgram = 0
        positionHandle = 0
        colorHandle = 0
        mvpMatrixHandle = 0
    }

    // ── OpenGL Drawing Helpers ────────────────────────────────────────────────
    private fun initGL() {
        if (glProgram != 0) return
        
        val vertexShaderCode = """
            attribute vec2 aPosition;
            uniform mat4 uMVPMatrix;
            void main() {
                gl_Position = uMVPMatrix * vec4(aPosition, 0.0, 1.0);
            }
        """.trimIndent()
        
        val fragmentShaderCode = """
            precision mediump float;
            uniform vec4 uColor;
            void main() {
                gl_FragColor = uColor;
            }
        """.trimIndent()
        
        val vertexShader = loadShader(GLES20.GL_VERTEX_SHADER, vertexShaderCode)
        val fragmentShader = loadShader(GLES20.GL_FRAGMENT_SHADER, fragmentShaderCode)
        
        val program = GLES20.glCreateProgram()
        GLES20.glAttachShader(program, vertexShader)
        GLES20.glAttachShader(program, fragmentShader)
        GLES20.glLinkProgram(program)

        val linkStatus = IntArray(1)
        GLES20.glGetProgramiv(program, GLES20.GL_LINK_STATUS, linkStatus, 0)
        if (linkStatus[0] == 0) {
            // glProgram stays 0, so the next callback tries again.
            Log.e(TAG, "GL program link failed: " + GLES20.glGetProgramInfoLog(program))
            GLES20.glDeleteProgram(program)
            return
        }

        glProgram = program
        
        positionHandle = GLES20.glGetAttribLocation(glProgram, "aPosition")
        colorHandle = GLES20.glGetUniformLocation(glProgram, "uColor")
        mvpMatrixHandle = GLES20.glGetUniformLocation(glProgram, "uMVPMatrix")
        
        GLES20.glEnable(GLES20.GL_BLEND)
        GLES20.glBlendFunc(GLES20.GL_SRC_ALPHA, GLES20.GL_ONE_MINUS_SRC_ALPHA)
    }

    private fun loadShader(type: Int, shaderCode: String): Int {
        val shader = GLES20.glCreateShader(type)
        GLES20.glShaderSource(shader, shaderCode)
        GLES20.glCompileShader(shader)
        val compiled = IntArray(1)
        GLES20.glGetShaderiv(shader, GLES20.GL_COMPILE_STATUS, compiled, 0)
        if (compiled[0] == 0) {
            Log.e(TAG, "GL shader compile failed: " + GLES20.glGetShaderInfoLog(shader))
        }
        return shader
    }

    private fun setupViewport(width: Int, height: Int): FloatArray {
        GLES20.glViewport(0, 0, width, height)
        val projection = FloatArray(16)
        Matrix.orthoM(
            projection, 0,
            0f, width.toFloat(),
            height.toFloat(), 0f, // invert Y so 0 is top
            -1f, 1f
        )
        return projection
    }

    private fun getVertexBuffer(capacityInPoints: Int): FloatBuffer {
        val requiredBytes = capacityInPoints * 2 * 4 // 2 floats per point, 4 bytes per float
        // Read each field once into a local. dispose() may null them on the UI thread,
        // so the !! force-unwrap that could fail is gone.
        val currentBuffer = rawByteBuffer
        val currentFloats = vertexBuffer
        if (currentBuffer == null || currentFloats == null || currentBuffer.capacity() < requiredBytes) {
            val newCapacity = Math.max(requiredBytes, (currentBuffer?.capacity() ?: 0) * 2)
            val newBuffer = ByteBuffer.allocateDirect(newCapacity).apply {
                order(ByteOrder.nativeOrder())
            }
            val newFloats = newBuffer.asFloatBuffer()
            rawByteBuffer = newBuffer
            vertexBuffer = newFloats
            return newFloats.apply {
                clear()
                position(0)
            }
        }
        return currentFloats.apply {
            clear()
            position(0)
        }
    }

    private fun drawStroke(stroke: StrokeData, mvpMatrix: FloatArray) {
        if (glProgram == 0) return // no usable program yet (not built, or link failed)
        val points = stroke.points
        if (points.size < 2) return
        
        val vBuffer = getVertexBuffer(points.size).apply {
            for (p in points) {
                put(p.x)
                put(p.y)
            }
            position(0)
        }
        
        GLES20.glUseProgram(glProgram)
        GLES20.glEnable(GLES20.GL_BLEND)
        GLES20.glBlendFunc(GLES20.GL_SRC_ALPHA, GLES20.GL_ONE_MINUS_SRC_ALPHA)
        
        GLES20.glEnableVertexAttribArray(positionHandle)
        GLES20.glVertexAttribPointer(
            positionHandle, 2,
            GLES20.GL_FLOAT, false,
            2 * 4, vBuffer
        )
        
        val color = stroke.color
        val r = Color.red(color) / 255f
        val g = Color.green(color) / 255f
        val b = Color.blue(color) / 255f
        val a = Color.alpha(color) / 255f
        GLES20.glUniform4f(colorHandle, r, g, b, a)
        GLES20.glUniformMatrix4fv(mvpMatrixHandle, 1, false, mvpMatrix, 0)
        
        GLES20.glLineWidth(stroke.width)
        
        GLES20.glDrawArrays(GLES20.GL_LINE_STRIP, 0, points.size)
        GLES20.glDisableVertexAttribArray(positionHandle)
    }
}

class LowLatencyDrawingViewFactory(
    private val messenger: BinaryMessenger
) : io.flutter.plugin.platform.PlatformViewFactory(io.flutter.plugin.common.StandardMessageCodec.INSTANCE) {
    override fun create(context: Context, viewId: Int, args: Any?): PlatformView {
        return LowLatencyDrawingView(context, viewId, messenger)
    }
}
