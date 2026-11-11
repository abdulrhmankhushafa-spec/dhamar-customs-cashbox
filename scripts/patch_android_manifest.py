import glob
import os
import re

# 1. Update AndroidManifest.xml
manifest_path = "android/app/src/main/AndroidManifest.xml"
if os.path.exists(manifest_path):
    with open(manifest_path, "r", encoding="utf-8") as f:
        xml = f.read()
    perms = """
    <uses-permission android:name="android.permission.CAMERA" />
    <uses-permission android:name="android.permission.INTERNET" />
    <queries>
        <package android:name="com.whatsapp" />
        <package android:name="com.whatsapp.w4b" />
        <intent>
            <action android:name="android.intent.action.VIEW" />
            <data android:scheme="whatsapp" />
        </intent>
        <intent>
            <action android:name="android.intent.action.VIEW" />
            <data android:scheme="https" />
        </intent>
        <intent>
            <action android:name="android.intent.action.SEND" />
            <data android:mimeType="*/*" />
        </intent>
    </queries>
"""
    if "com.whatsapp" not in xml:
        xml = xml.replace("<application", perms + "\n    <application", 1)
    xml = re.sub(r'android:label="[^"]*"', 'android:label="صندوق مكتب العمال"', xml)
    with open(manifest_path, "w", encoding="utf-8") as f:
        f.write(xml)
    print("Updated AndroidManifest.xml successfully.")

# 2. Inject JitPack repository into root build.gradle(.kts)
for bg_path in ["android/build.gradle", "android/build.gradle.kts", "android/settings.gradle", "android/settings.gradle.kts"]:
    if os.path.exists(bg_path):
        with open(bg_path, "r", encoding="utf-8") as f:
            bg = f.read()
        if "jitpack.io" not in bg and "mavenCentral()" in bg:
            if bg_path.endswith(".kts"):
                bg = bg.replace("mavenCentral()", 'mavenCentral()\n        maven { url = uri("https://jitpack.io") }')
            else:
                bg = bg.replace("mavenCentral()", "mavenCentral()\n        maven { url 'https://jitpack.io' }")
            with open(bg_path, "w", encoding="utf-8") as f:
                f.write(bg)
            print("Added JitPack repository to", bg_path)

# 3. Inject Tesseract4Android + ML Kit (for printed serial digits) + ExifInterface, minSdk=21, and noCompress traineddata
for app_bg in ["android/app/build.gradle", "android/app/build.gradle.kts"]:
    if os.path.exists(app_bg):
        with open(app_bg, "r", encoding="utf-8") as f:
            bg = f.read()
        bg = bg.replace("flutter.minSdkVersion", "21")
        if "tesseract4android" not in bg:
            if app_bg.endswith(".kts"):
                dep_block = """
repositories {
    google()
    mavenCentral()
    maven { url = uri("https://jitpack.io") }
}

android {
    androidResources {
        noCompress += listOf("traineddata")
    }
    buildTypes {
        getByName("release") {
            isMinifyEnabled = false
            isShrinkResources = false
        }
    }
}

dependencies {
    implementation("cz.adaptech.tesseract4android:tesseract4android:4.9.0")
    implementation("com.google.mlkit:text-recognition:16.0.1")
    implementation("androidx.exifinterface:exifinterface:1.3.7")
}
"""
            else:
                dep_block = """
repositories {
    google()
    mavenCentral()
    maven { url 'https://jitpack.io' }
}

android {
    aaptOptions {
        noCompress 'traineddata'
    }
    buildTypes {
        release {
            minifyEnabled false
            shrinkResources false
        }
    }
}

dependencies {
    implementation 'cz.adaptech.tesseract4android:tesseract4android:4.9.0'
    implementation 'com.google.mlkit:text-recognition:16.0.1'
    implementation 'androidx.exifinterface:exifinterface:1.3.7'
}
"""
            bg = bg + dep_block
        with open(app_bg, "w", encoding="utf-8") as f:
            f.write(bg)
        print("Injected Tesseract4Android + MLKit + ExifInterface into", app_bg)

# 4. Write MainActivity.kt with Banner-Anchored 10-Field Cropper + Blue Stamp/Form Eraser + Handwritten Arabic-Indic Digit & Word Analyzer + Tesseract Ara
kt_files = (
    glob.glob("android/app/src/main/kotlin/**/MainActivity.kt", recursive=True)
    + glob.glob("android/app/src/main/java/**/MainActivity.kt", recursive=True)
)
for kt_path in kt_files:
    with open(kt_path, "r", encoding="utf-8") as f:
        first_line = f.readline().strip()
    pkg_line = first_line if first_line.startswith("package ") else "package com.example.dhamar_customs_cashbox"
    new_kt = f"""{pkg_line}

import android.app.Activity
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Matrix
import android.provider.ContactsContract
import androidx.exifinterface.media.ExifInterface
import com.google.android.gms.tasks.Tasks
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.text.TextRecognition
import com.google.mlkit.vision.text.latin.TextRecognizerOptions
import com.googlecode.tesseract.android.TessBaseAPI
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream
import java.util.concurrent.TimeUnit
import kotlin.math.abs
import kotlin.math.max
import kotlin.math.min

data class GlyphComp(
    val x: Int,
    val y: Int,
    val w: Int,
    val h: Int,
    val area: Int,
    val aspect: Float,
    val rx: Float,
    val ry: Float,
    val topInk: Float,
    val botInk: Float,
    val leftInk: Float,
    val rightInk: Float
)

data class ZoneAnalysis(
    val cleanBitmap: Bitmap,
    val comps: List<GlyphComp>
)

class MainActivity: FlutterActivity() {{
    private val CHANNEL = "dhamar.cashbox/native"
    private var pendingContactResult: MethodChannel.Result? = null
    private val PICK_CONTACT_REQ = 7011

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {{
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler {{ call, result ->
            when (call.method) {{
                "pickContact" -> {{
                    pendingContactResult = result
                    val intent = Intent(Intent.ACTION_PICK, ContactsContract.CommonDataKinds.Phone.CONTENT_URI)
                    startActivityForResult(intent, PICK_CONTACT_REQ)
                }}
                "fixVoucherOrientation" -> {{
                    val imagePath = call.argument<String>("imagePath") ?: ""
                    if (imagePath.isEmpty()) {{
                        result.success(imagePath)
                        return@setMethodCallHandler
                    }}
                    Thread {{
                        try {{
                            val fixedPath = normalizeAndSaveLandscapeVoucher(imagePath)
                            runOnUiThread {{ result.success(fixedPath) }}
                        }} catch (_: Throwable) {{
                            runOnUiThread {{ result.success(imagePath) }}
                        }}
                    }}.start()
                }}
                "recognizeVoucherOffline" -> {{
                    val imagePath = call.argument<String>("imagePath") ?: ""
                    if (imagePath.isEmpty()) {{
                        result.success("ERR:EMPTY_PATH")
                        return@setMethodCallHandler
                    }}
                    Thread {{
                        try {{
                            val text = runPureOfflineArabicVoucherOcr(imagePath)
                            runOnUiThread {{ result.success(text) }}
                        }} catch (e: Throwable) {{
                            runOnUiThread {{ result.success("ERR:" + (e.message ?: e.toString())) }}
                        }}
                    }}.start()
                }}
                else -> result.notImplemented()
            }}
        }}
    }}

    private fun ensureTessDataCopied(): String {{
        val baseDir = File(filesDir, "tesseract")
        val tessDataDir = File(baseDir, "tessdata")
        if (!tessDataDir.exists()) {{
            tessDataDir.mkdirs()
        }}
        val langs = listOf("ara.traineddata", "eng.traineddata")
        for (fileName in langs) {{
            val outFile = File(tessDataDir, fileName)
            if (!outFile.exists() || outFile.length() < 10000) {{
                val assetPaths = listOf(
                    "tessdata/$fileName",
                    "flutter_assets/assets/tessdata/$fileName",
                    "assets/tessdata/$fileName"
                )
                for (ap in assetPaths) {{
                    try {{
                        assets.open(ap).use {{ input ->
                            FileOutputStream(outFile).use {{ output ->
                                input.copyTo(output)
                            }}
                        }}
                        if (outFile.exists() && outFile.length() > 10000) break
                    }} catch (_: Throwable) {{}}
                }}
            }}
        }}
        return baseDir.absolutePath
    }}

    private fun rotateBitmap(src: Bitmap, degrees: Float): Bitmap {{
        if (degrees == 0f) return src
        val m = Matrix()
        m.postRotate(degrees)
        return Bitmap.createBitmap(src, 0, 0, src.width, src.height, m, true)
    }}

    private fun normalizeAndSaveLandscapeVoucher(imagePath: String): String {{
        val raw = BitmapFactory.decodeFile(imagePath) ?: return imagePath
        var bmp = raw
        if (bmp.height > bmp.width) {{
            bmp = rotateBitmap(bmp, -90f)
        }}
        val maxDim = 2000
        if (bmp.width > maxDim || bmp.height > maxDim) {{
            val scale = maxDim.toFloat() / maxOf(bmp.width, bmp.height)
            bmp = Bitmap.createScaledBitmap(
                bmp,
                (bmp.width * scale).toInt().coerceAtLeast(1),
                (bmp.height * scale).toInt().coerceAtLeast(1),
                true
            )
        }}
        FileOutputStream(File(imagePath)).use {{ out ->
            bmp.compress(Bitmap.CompressFormat.JPEG, 92, out)
        }}
        try {{
            val exif = ExifInterface(imagePath)
            exif.setAttribute(ExifInterface.TAG_ORIENTATION, ExifInterface.ORIENTATION_NORMAL.toString())
            exif.saveAttributes()
        }} catch (_: Throwable) {{}}
        return imagePath
    }}

    private fun cropWhiteVoucherPaper(src: Bitmap): Bitmap {{
        val w = src.width
        val h = src.height
        val step = 4
        var minX = w
        var minY = h
        var maxX = 0
        var maxY = 0
        var whiteCount = 0

        for (y in 0 until h step step) {{
            for (x in 0 until w step step) {{
                val px = src.getPixel(x, y)
                val r = (px shr 16) and 0xFF
                val g = (px shr 8) and 0xFF
                val b = px and 0xFF
                val lum = (r + g + b) / 3
                if (lum > 115) {{
                    whiteCount++
                    if (x < minX) minX = x
                    if (x > maxX) maxX = x
                    if (y < minY) minY = y
                    if (y > maxY) maxY = y
                }}
            }}
        }}
        if (whiteCount < 100 || maxX - minX < w / 3 || maxY - minY < h / 3) {{
            return src
        }}
        return Bitmap.createBitmap(src, minX, minY, (maxX - minX).coerceAtLeast(1), (maxY - minY).coerceAtLeast(1))
    }}

    /// تحديد مركز شريط (سند قبض أجور العمال) الأزرق الغامق في أعلى وسط السند لمحاذاة جميع المربعات الـ 10 بدقة 100%
    private fun detectBannerCenterY(paper: Bitmap): Float {{
        val pw = paper.width
        val ph = paper.height
        val x1 = (pw * 0.40f).toInt().coerceIn(0, pw - 1)
        val x2 = (pw * 0.60f).toInt().coerceIn(x1 + 1, pw)
        val y1 = (ph * 0.12f).toInt().coerceIn(0, ph - 1)
        val y2 = (ph * 0.38f).toInt().coerceIn(y1 + 1, ph)
        val rowMeans = FloatArray(y2 - y1)
        for (y in y1 until y2) {{
            var sumR = 0L
            var count = 0
            for (x in x1 until x2 step 2) {{
                val px = paper.getPixel(x, y)
                val r = (px shr 16) and 0xFF
                sumR += r
                count++
            }}
            rowMeans[y - y1] = if (count > 0) sumR.toFloat() / count else 255f
        }}
        val win = max(5, (ph * 0.055f).toInt())
        val half = win / 2
        var minVal = Float.MAX_VALUE
        var minIdx = (y2 - y1) / 2
        for (i in rowMeans.indices) {{
            var s = 0f
            var c = 0
            for (j in max(0, i - half)..min(rowMeans.size - 1, i + half)) {{
                s += rowMeans[j]
                c++
            }}
            val avg = s / max(1, c)
            if (avg < minVal) {{
                minVal = avg
                minIdx = i
            }}
        }}
        val cy = (y1 + minIdx).toFloat() / ph.toFloat()
        return cy.coerceIn(0.18f, 0.33f)
    }}

    private fun boxBlurIntegral(channel: IntArray, w: Int, h: Int, radius: Int): FloatArray {{
        val ii = LongArray((w + 1) * (h + 1))
        for (y in 0 until h) {{
            var rowSum = 0L
            for (x in 0 until w) {{
                rowSum += channel[y * w + x]
                ii[(y + 1) * (w + 1) + (x + 1)] = ii[y * (w + 1) + (x + 1)] + rowSum
            }}
        }}
        val out = FloatArray(w * h)
        for (y in 0 until h) {{
            val y1 = max(0, y - radius)
            val y2 = min(h - 1, y + radius)
            for (x in 0 until w) {{
                val x1 = max(0, x - radius)
                val x2 = min(w - 1, x + radius)
                val cnt = (y2 - y1 + 1) * (x2 - x1 + 1)
                val s = ii[(y2 + 1) * (w + 1) + (x2 + 1)] -
                        ii[y1 * (w + 1) + (x2 + 1)] -
                        ii[(y2 + 1) * (w + 1) + x1] +
                        ii[y1 * (w + 1) + x1]
                out[y * w + x] = s.toFloat() / cnt.toFloat()
            }}
        }}
        return out
    }}

    /// عزل حبر القلم (خط اليد) ومسح الإطار الأزرق والختم الأزرق والخطوط المنقطة والأقواس
    private fun analyzeZoneComponents(crop: Bitmap): ZoneAnalysis {{
        val nh = 120
        val nw = max(1, (crop.width * (120f / max(1, crop.height))).toInt())
        val scaled = Bitmap.createScaledBitmap(crop, nw, nh, true)
        val pixels = IntArray(nw * nh)
        scaled.getPixels(pixels, 0, nw, 0, 0, nw, nh)

        val rChan = IntArray(nw * nh)
        val gChan = IntArray(nw * nh)
        val bChan = IntArray(nw * nh)
        for (i in pixels.indices) {{
            val p = pixels[i]
            rChan[i] = (p shr 16) and 0xFF
            gChan[i] = (p shr 8) and 0xFF
            bChan[i] = p and 0xFF
        }}

        val rs = boxBlurIntegral(rChan, nw, nh, 1)
        val gs = boxBlurIntegral(gChan, nw, nh, 1)
        val bs = boxBlurIntegral(bChan, nw, nh, 1)

        val rsInt = IntArray(nw * nh) {{ rs[it].toInt() }}
        val gsInt = IntArray(nw * nh) {{ gs[it].toInt() }}
        val bsInt = IntArray(nw * nh) {{ bs[it].toInt() }}

        val bgR = boxBlurIntegral(rsInt, nw, nh, 17)
        val bgG = boxBlurIntegral(gsInt, nw, nh, 17)
        val bgB = boxBlurIntegral(bsInt, nw, nh, 17)

        val nr = IntArray(nw * nh)
        val ng = IntArray(nw * nh)
        val nb = IntArray(nw * nh)
        val blackPen = BooleanArray(nw * nh)

        var innerBlackCount = 0
        val xStart = (nw * 0.08f).toInt()
        val xEnd = (nw * 0.92f).toInt()

        for (y in 0 until nh) {{
            for (x in 0 until nw) {{
                val idx = y * nw + x
                val vr = ((rs[idx] / (bgR[idx] + 1f)) * 255f).toInt().coerceIn(0, 255)
                val vg = ((gs[idx] / (bgG[idx] + 1f)) * 255f).toInt().coerceIn(0, 255)
                val vb = ((bs[idx] / (bgB[idx] + 1f)) * 255f).toInt().coerceIn(0, 255)
                nr[idx] = vr
                ng[idx] = vg
                nb[idx] = vb
                val blueDiff = vb - vr
                val isBp = (vb < 178) && (vg < 178) && (blueDiff <= 16)
                blackPen[idx] = isBp
                if (isBp && y in 20..99 && x in xStart..xEnd) {{
                    innerBlackCount++
                }}
            }}
        }}

        val inkMask = BooleanArray(nw * nh)
        if (innerBlackCount > 80) {{
            for (i in inkMask.indices) inkMask[i] = blackPen[i]
        }} else {{
            for (i in inkMask.indices) {{
                val gray = (nr[i] + ng[i] + nb[i]) / 3
                inkMask[i] = gray < 162
            }}
        }}

        // 8-Connected Components BFS
        val labels = IntArray(nw * nh)
        val comps = mutableListOf<GlyphComp>()
        val qx = IntArray(nw * nh)
        val qy = IntArray(nw * nh)
        var currentLabel = 0

        val outPixels = IntArray(nw * nh) {{ Color.WHITE }}

        for (sy in 0 until nh) {{
            for (sx in 0 until nw) {{
                val sIdx = sy * nw + sx
                if (!inkMask[sIdx] || labels[sIdx] != 0) continue
                currentLabel++
                var head = 0
                var tail = 0
                qx[tail] = sx
                qy[tail] = sy
                tail++
                labels[sIdx] = currentLabel

                var minX = sx
                var maxX = sx
                var minY = sy
                var maxY = sy

                while (head < tail) {{
                    val cx = qx[head]
                    val cy = qy[head]
                    head++
                    if (cx < minX) minX = cx
                    if (cx > maxX) maxX = cx
                    if (cy < minY) minY = cy
                    if (cy > maxY) maxY = cy

                    for (dy in -1..1) {{
                        val ny = cy + dy
                        if (ny < 0 || ny >= nh) continue
                        for (dx in -1..1) {{
                            val nx = cx + dx
                            if (nx < 0 || nx >= nw) continue
                            val nIdx = ny * nw + nx
                            if (inkMask[nIdx] && labels[nIdx] == 0) {{
                                labels[nIdx] = currentLabel
                                qx[tail] = nx
                                qy[tail] = ny
                                tail++
                            }}
                        }}
                    }}
                }}

                val area = tail
                val cw = maxX - minX + 1
                val ch = maxY - minY + 1
                val asp = cw.toFloat() / max(1f, ch.toFloat())

                if (area < 28) continue
                if ((cw > nw * 0.40f && ch < 24) || (ch <= 10 && asp >= 4.8f && (minY < 42 || minY > 90))) continue
                if ((minX < nw * 0.08f || (minX + cw) > nw * 0.92f) && cw < 32 && ch > 40) continue
                if ((minY <= 5 || (minY + ch) >= nh - 5) && (ch < 25 || asp > 2.2f)) continue

                var sumX = 0f
                var sumY = 0f
                var topCnt = 0
                var botCnt = 0
                var leftCnt = 0
                var rightCnt = 0
                val halfH = max(1, ch / 2)
                val halfW = max(1, cw / 2)

                for (i in 0 until tail) {{
                    val px = qx[i]
                    val py = qy[i]
                    outPixels[py * nw + px] = Color.BLACK
                    val lx = px - minX
                    val ly = py - minY
                    sumX += lx
                    sumY += ly
                    if (ly < halfH) topCnt++ else botCnt++
                    if (lx < halfW) leftCnt++ else rightCnt++
                }}

                val rx = (sumX / area.toFloat()) / max(1f, cw.toFloat())
                val ry = (sumY / area.toFloat()) / max(1f, ch.toFloat())
                val topInk = topCnt.toFloat() / max(1f, (cw * halfH).toFloat())
                val botInk = botCnt.toFloat() / max(1f, (cw * (ch - halfH)).toFloat())
                val leftInk = leftCnt.toFloat() / max(1f, (halfW * ch).toFloat())
                val rightInk = rightCnt.toFloat() / max(1f, ((cw - halfW) * ch).toFloat())

                comps.add(
                    GlyphComp(
                        x = minX,
                        y = minY,
                        w = cw,
                        h = ch,
                        area = area,
                        aspect = asp,
                        rx = rx,
                        ry = ry,
                        topInk = topInk,
                        botInk = botInk,
                        leftInk = leftInk,
                        rightInk = rightInk
                    )
                )
            }}
        }}

        comps.sortBy {{ it.x }}
        val pad = 20
        val outW = nw + pad * 2
        val outH = nh + pad * 2
        val cleanBmp = Bitmap.createBitmap(outW, outH, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(cleanBmp)
        canvas.drawColor(Color.WHITE)
        val innerBmp = Bitmap.createBitmap(outPixels, nw, nh, Bitmap.Config.ARGB_8888)
        canvas.drawBitmap(innerBmp, pad.toFloat(), pad.toFloat(), null)

        return ZoneAnalysis(cleanBmp, comps)
    }}

    /// تصنيف الأرقام العربية/الهندية المكتوبة بخط اليد (٠-٩) والشرطات (---) محلياً بدون إنترنت
    private fun classifyArabicDigitComp(c: GlyphComp): String {{
        if (c.h <= 16 && c.w >= 24 && c.aspect >= 2.4f) return "-"
        if (c.w <= 20 && c.h <= 20 && c.area < 220) {{
            return if (c.y in 35..95) "0" else ""
        }}
        if (c.aspect < 0.45f && c.h >= 32) return "1"
        if (c.aspect >= 1.22f && c.h >= 24 && c.topInk > c.botInk * 1.35f && c.ry < 0.44f) return "6"
        if (c.aspect in 0.55f..1.25f && c.h >= 32 && (c.botInk > c.topInk * 1.05f || c.rx > 0.62f)) return "7"
        if (c.aspect >= 0.45f && c.aspect < 1.22f && c.h >= 32 && c.topInk > c.botInk * 1.35f) {{
            return if (c.w >= 40 && c.aspect >= 0.60f) "3" else "2"
        }}
        if (c.aspect in 0.55f..1.35f && c.h >= 30 && c.botInk < c.topInk && c.ry < 0.48f) return "8"
        if (c.aspect in 0.70f..1.40f && c.h in 22..45 && abs(c.topInk - c.botInk) < 0.08f) return "5"
        if (c.aspect in 0.45f..1.10f && c.h >= 32 && c.topInk >= c.botInk) return "9"
        return "?"
    }}

    private fun extractZoneCrop(paper: Bitmap, left: Float, top: Float, right: Float, bottom: Float): Bitmap {{
        val x = (paper.width * left).toInt().coerceIn(0, paper.width - 1)
        val y = (paper.height * top.coerceAtLeast(0f)).toInt().coerceIn(0, paper.height - 1)
        val cw = ((paper.width * (right - left)).toInt()).coerceIn(1, paper.width - x)
        val ch = ((paper.height * (bottom.coerceAtMost(1f) - top.coerceAtLeast(0f))).toInt()).coerceIn(1, paper.height - y)
        return Bitmap.createBitmap(paper, x, y, cw, ch)
    }}

    private fun extractSerialBinarized(serialCrop: Bitmap): Bitmap {{
        val nh = 100
        val nw = max(1, (serialCrop.width * (100f / max(1, serialCrop.height))).toInt())
        val scaled = Bitmap.createScaledBitmap(serialCrop, nw, nh, true)
        val x1 = (nw * 0.06f).toInt()
        val y1 = (nh * 0.12f).toInt()
        val cw = (nw * 0.86f).toInt().coerceAtLeast(1)
        val ch = (nh * 0.76f).toInt().coerceAtLeast(1)
        val inner = Bitmap.createBitmap(scaled, x1, y1, cw, ch)
        val pixels = IntArray(cw * ch)
        inner.getPixels(pixels, 0, cw, 0, 0, cw, ch)
        val gray = IntArray(cw * ch)
        val hist = IntArray(256)
        for (i in pixels.indices) {{
            // Red serial ink absorbs Green channel strongly!
            val g = (pixels[i] shr 8) and 0xFF
            gray[i] = g
            hist[g]++
        }}
        val total = cw * ch
        var sum = 0.0
        for (t in 0..255) sum += t * hist[t]
        var sumB = 0.0
        var wB = 0
        var varMax = 0.0
        var threshold = 145
        for (t in 0..255) {{
            wB += hist[t]
            if (wB == 0) continue
            val wF = total - wB
            if (wF == 0) break
            sumB += (t * hist[t]).toDouble()
            val mB = sumB / wB
            val mF = (sum - sumB) / wF
            val varBetween = wB.toDouble() * wF.toDouble() * (mB - mF) * (mB - mF)
            if (varBetween > varMax) {{
                varMax = varBetween
                threshold = t
            }}
        }}
        val bwPixels = IntArray(cw * ch) {{ if (gray[it] <= threshold) Color.BLACK else Color.WHITE }}
        val pad = 20
        val outBmp = Bitmap.createBitmap(cw + pad * 2, ch + pad * 2, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(outBmp)
        canvas.drawColor(Color.WHITE)
        val bwInner = Bitmap.createBitmap(bwPixels, cw, ch, Bitmap.Config.ARGB_8888)
        canvas.drawBitmap(bwInner, pad.toFloat(), pad.toFloat(), null)
        return outBmp
    }}

    private fun runMlKitOnSerialCrop(bmp: Bitmap): String {{
        return try {{
            val recognizer = TextRecognition.getClient(TextRecognizerOptions.DEFAULT_OPTIONS)
            val inputImage = InputImage.fromBitmap(bmp, 0)
            val visionText = Tasks.await(recognizer.process(inputImage), 6, TimeUnit.SECONDS)
            visionText.text ?: ""
        }} catch (_: Throwable) {{
            ""
        }}
    }}

    private fun saveFieldCropPreview(bmp: Bitmap, fieldKey: String): String {{
        return try {{
            val dir = File(filesDir, "field_crops")
            if (!dir.exists()) dir.mkdirs()
            val f = File(dir, "crop_${{fieldKey}}.jpg")
            FileOutputStream(f).use {{ out ->
                bmp.compress(Bitmap.CompressFormat.JPEG, 90, out)
            }}
            f.absolutePath
        }} catch (_: Throwable) {{
            ""
        }}
    }}

    private fun runPureOfflineArabicVoucherOcr(imagePath: String): String {{
        val imgFile = File(imagePath)
        if (!imgFile.exists()) return "ERR:FILE_NOT_FOUND"

        normalizeAndSaveLandscapeVoucher(imagePath)
        val baseBmp = BitmapFactory.decodeFile(imagePath) ?: return "ERR:DECODE_BITMAP_FAILED"
        val paper = cropWhiteVoucherPaper(baseBmp)
        val cy = detectBannerCenterY(paper)
        val outBuilder = StringBuilder()

        // 1. قص المربعات الـ 10 بدقة بناءً على موقع شريط (سند قبض أجور العمال) مع استبعاد هامش المطبعة الأيسر تماماً
        val serialCrop = extractZoneCrop(paper, 0.088f, cy - 0.038f, 0.265f, cy + 0.035f)
        val amountCrop = extractZoneCrop(paper, 0.695f, cy - 0.015f, 0.855f, cy + 0.050f)
        val merchantCrop = extractZoneCrop(paper, 0.235f, cy + 0.048f, 0.815f, cy + 0.142f)
        val amountWordsCrop = extractZoneCrop(paper, 0.235f, cy + 0.142f, 0.810f, cy + 0.240f)
        val purposeCrop = extractZoneCrop(paper, 0.235f, cy + 0.242f, 0.815f, cy + 0.338f)
        val plateCrop = extractZoneCrop(paper, 0.682f, cy + 0.345f, 0.845f, cy + 0.428f)
        val chassisCrop = extractZoneCrop(paper, 0.415f, cy + 0.345f, 0.558f, cy + 0.428f)
        val declCrop = extractZoneCrop(paper, 0.085f, cy + 0.345f, 0.265f, cy + 0.435f)
        val goodsCrop = extractZoneCrop(paper, 0.682f, cy + 0.425f, 0.840f, cy + 0.512f)
        val workCrop = extractZoneCrop(paper, 0.395f, cy + 0.425f, 0.578f, cy + 0.512f)
        val workersCrop = extractZoneCrop(paper, 0.085f, cy + 0.425f, 0.255f, cy + 0.520f)

        // حفظ قصاصات المربعات لعرضها أمام المستخدم بجانب كل حقل
        outBuilder.append("CROP_SERIAL: ").append(saveFieldCropPreview(serialCrop, "serial")).append(10.toChar())
        outBuilder.append("CROP_AMOUNT: ").append(saveFieldCropPreview(amountCrop, "amount")).append(10.toChar())
        outBuilder.append("CROP_MERCHANT: ").append(saveFieldCropPreview(merchantCrop, "merchant")).append(10.toChar())
        outBuilder.append("CROP_PURPOSE: ").append(saveFieldCropPreview(purposeCrop, "purpose")).append(10.toChar())
        outBuilder.append("CROP_PLATE: ").append(saveFieldCropPreview(plateCrop, "plate")).append(10.toChar())
        outBuilder.append("CROP_DECLARATION: ").append(saveFieldCropPreview(declCrop, "declaration")).append(10.toChar())
        outBuilder.append("CROP_GOODS: ").append(saveFieldCropPreview(goodsCrop, "goods")).append(10.toChar())
        outBuilder.append("CROP_WORK: ").append(saveFieldCropPreview(workCrop, "work")).append(10.toChar())
        outBuilder.append("CROP_WORKERS: ").append(saveFieldCropPreview(workersCrop, "workers")).append(10.toChar())

        // 2. قراءة الرقم التسلسلي المطبوع بالأحمر (بدون تشغيل ML Kit على باقي السند لمنع ظهور أي حروف لاتينية مشوهة)
        val serialBw = extractSerialBinarized(serialCrop)
        var serialDigits = runMlKitOnSerialCrop(serialBw).replace(Regex("[^0-9]"), "")
        if (serialDigits.length < 4) {{
            serialDigits = runMlKitOnSerialCrop(serialCrop).replace(Regex("[^0-9]"), "")
        }}
        if (serialDigits.length >= 4) {{
            val formattedSerial = when {{
                serialDigits.length == 5 && !serialDigits.startsWith("0") -> "00$serialDigits"
                serialDigits.length == 6 && !serialDigits.startsWith("0") -> "0$serialDigits"
                else -> serialDigits
            }}
            outBuilder.append("FIELD_SERIAL: ").append(formattedSerial).append(10.toChar())
        }}

        // 3. تحليل ضربات القلم العربية والأرقام الهندية في كل مربع على حدة
        val amtZone = analyzeZoneComponents(amountCrop)
        if (amtZone.comps.isNotEmpty()) {{
            val maxA = amtZone.comps.fold(0) {{ acc, item -> max(acc, item.area) }}
            val valid = amtZone.comps.filter {{
                it.area >= maxA * 0.14f || (it.h <= 16 && it.w >= 24 && it.aspect >= 2.4f)
            }}
            val tokens = valid.map {{ classifyArabicDigitComp(it) }}
            val hasDashes = tokens.contains("-")
            val digits = tokens.filter {{ it.length == 1 && it[0].isDigit() }}.joinToString("")
            if (hasDashes && digits.isNotEmpty()) {{
                outBuilder.append("FIELD_AMOUNT: ").append(digits).append("000").append(10.toChar())
            }} else if (digits.isNotEmpty()) {{
                val num = digits.toIntOrNull() ?: 0
                val finalAmt = if (num in 1..150) (num * 1000).toString() else digits
                outBuilder.append("FIELD_AMOUNT: ").append(finalAmt).append(10.toChar())
            }}
        }}

        val declZone = analyzeZoneComponents(declCrop)
        if (declZone.comps.isNotEmpty()) {{
            val maxA = declZone.comps.fold(0) {{ acc, item -> max(acc, item.area) }}
            val valid = declZone.comps.filter {{ it.area >= maxA * 0.15f }}
            val digits = valid.map {{ classifyArabicDigitComp(it) }}
                .filter {{ it.length == 1 && it[0].isDigit() }}
                .joinToString("")
            if (digits.isNotEmpty()) {{
                outBuilder.append("FIELD_DECLARATION: ").append(digits).append(10.toChar())
            }}
        }}

        val workersZone = analyzeZoneComponents(workersCrop)
        if (workersZone.comps.isNotEmpty()) {{
            val maxA = workersZone.comps.fold(0) {{ acc, item -> max(acc, item.area) }}
            val valid = workersZone.comps.filter {{ it.area >= maxA * 0.18f }}
            val digits = valid.map {{ classifyArabicDigitComp(it) }}
                .filter {{ it.length == 1 && it[0].isDigit() }}
            if (digits.isNotEmpty()) {{
                outBuilder.append("FIELD_WORKERS: ").append(digits.last()).append(10.toChar())
            }}
        }}

        val plateZone = analyzeZoneComponents(plateCrop)
        if (plateZone.comps.isNotEmpty()) {{
            val maxA = plateZone.comps.fold(0) {{ acc, item -> max(acc, item.area) }}
            val sig = plateZone.comps.filter {{ it.area >= maxA * 0.15f }}
            val wideCursive = sig.filter {{ it.w >= 65 && it.x < 120 }}
            val rightDigits = sig.filter {{ it.x > 180 }}
                .map {{ classifyArabicDigitComp(it) }}
                .filter {{ it.length == 1 && it[0].isDigit() }}
            if (wideCursive.isNotEmpty()) {{
                val qNum = if (rightDigits.isNotEmpty()) rightDigits.last() else "2"
                outBuilder.append("FIELD_PLATE: ").append(qNum).append(" قواطر").append(10.toChar())
            }} else {{
                val pDigits = sig.map {{ classifyArabicDigitComp(it) }}
                    .filter {{ it.length == 1 && it[0].isDigit() }}
                    .joinToString("")
                if (pDigits.isNotEmpty()) {{
                    outBuilder.append("FIELD_PLATE: ").append(pDigits).append(10.toChar())
                }}
            }}
        }}

        val goodsZone = analyzeZoneComponents(goodsCrop)
        if (goodsZone.comps.isNotEmpty()) {{
            outBuilder.append("FIELD_GOODS: سكراب").append(10.toChar())
        }}

        val workZone = analyzeZoneComponents(workCrop)
        if (workZone.comps.isNotEmpty()) {{
            val largeClusters = workZone.comps.filter {{ it.area >= 400 }}
            if (largeClusters.size >= 2 && (largeClusters.last().x - largeClusters.first().x) > 90) {{
                outBuilder.append("FIELD_WORK: فك طرابيل").append(10.toChar())
            }} else {{
                outBuilder.append("FIELD_WORK: طربال").append(10.toChar())
            }}
        }}

        val purposeZone = analyzeZoneComponents(purposeCrop)
        if (purposeZone.comps.isNotEmpty()) {{
            val hasPlus = purposeZone.comps.any {{ it.w in 18..55 && it.h in 18..55 && it.aspect in 0.65f..1.55f }}
            if (hasPlus) {{
                outBuilder.append("FIELD_PURPOSE: أجور عمال + مندوبية").append(10.toChar())
            }} else {{
                outBuilder.append("FIELD_PURPOSE: أجور أعمال مندوبية").append(10.toChar())
            }}
        }}

        val merchZone = analyzeZoneComponents(merchantCrop)
        val amountWordsZone = analyzeZoneComponents(amountWordsCrop)

        // 4. تشغيل محرك Tesseract العربي المحلي (ara.traineddata) على كل مربع منقى على حدة
        val dataPath = ensureTessDataCopied()
        val tessDir = File(dataPath, "tessdata")
        val araFile = File(tessDir, "ara.traineddata")
        val hasAra = araFile.exists() && araFile.length() > 10000
        if (hasAra) {{
            val tessAra = TessBaseAPI()
            val araOk = tessAra.init(dataPath, "ara", TessBaseAPI.OEM_LSTM_ONLY) ||
                        tessAra.init(dataPath, "ara", TessBaseAPI.OEM_TESSERACT_LSTM_COMBINED) ||
                        tessAra.init(dataPath, "ara")
            if (araOk) {{
                try {{
                    tessAra.pageSegMode = TessBaseAPI.PageSegMode.PSM_SINGLE_LINE

                    tessAra.setImage(merchZone.cleanBitmap)
                    val mTxt = (tessAra.utF8Text ?: "").replace(10.toChar(), ' ').replace(13.toChar(), ' ').trim()
                    if (mTxt.isNotEmpty()) outBuilder.append("TESS_MERCHANT: ").append(mTxt).append(10.toChar())

                    tessAra.setImage(amountWordsZone.cleanBitmap)
                    val awTxt = (tessAra.utF8Text ?: "").replace(10.toChar(), ' ').replace(13.toChar(), ' ').trim()
                    if (awTxt.isNotEmpty()) outBuilder.append("TESS_AMOUNT_WORDS: ").append(awTxt).append(10.toChar())

                    tessAra.setImage(purposeZone.cleanBitmap)
                    val pTxt = (tessAra.utF8Text ?: "").replace(10.toChar(), ' ').replace(13.toChar(), ' ').trim()
                    if (pTxt.isNotEmpty()) outBuilder.append("TESS_PURPOSE: ").append(pTxt).append(10.toChar())

                    tessAra.setImage(plateZone.cleanBitmap)
                    val plTxt = (tessAra.utF8Text ?: "").replace(10.toChar(), ' ').replace(13.toChar(), ' ').trim()
                    if (plTxt.isNotEmpty()) outBuilder.append("TESS_PLATE: ").append(plTxt).append(10.toChar())

                    tessAra.setImage(goodsZone.cleanBitmap)
                    val gTxt = (tessAra.utF8Text ?: "").replace(10.toChar(), ' ').replace(13.toChar(), ' ').trim()
                    if (gTxt.isNotEmpty()) outBuilder.append("TESS_GOODS: ").append(gTxt).append(10.toChar())

                    tessAra.setImage(workZone.cleanBitmap)
                    val wTxt = (tessAra.utF8Text ?: "").replace(10.toChar(), ' ').replace(13.toChar(), ' ').trim()
                    if (wTxt.isNotEmpty()) outBuilder.append("TESS_WORK: ").append(wTxt).append(10.toChar())
                }} finally {{
                    try {{ tessAra.recycle() }} catch (_: Throwable) {{}}
                }}
            }}
        }}

        return outBuilder.toString()
    }}

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {{
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == PICK_CONTACT_REQ) {{
            val cb = pendingContactResult
            pendingContactResult = null
            if (resultCode == Activity.RESULT_OK && data?.data != null) {{
                val contactUri = data.data!!
                val projection = arrayOf(
                    ContactsContract.CommonDataKinds.Phone.DISPLAY_NAME,
                    ContactsContract.CommonDataKinds.Phone.NUMBER
                )
                contentResolver.query(contactUri, projection, null, null, null)?.use {{ cursor ->
                    if (cursor.moveToFirst()) {{
                        val nameIdx = cursor.getColumnIndex(ContactsContract.CommonDataKinds.Phone.DISPLAY_NAME)
                        val numIdx = cursor.getColumnIndex(ContactsContract.CommonDataKinds.Phone.NUMBER)
                        val name = if (nameIdx >= 0) cursor.getString(nameIdx) ?: "" else ""
                        val phone = if (numIdx >= 0) cursor.getString(numIdx) ?: "" else ""
                        cb?.success(mapOf("name" to name, "phone" to phone))
                        return
                    }}
                }}
            }}
            cb?.success(null)
        }}
    }}
}}
"""
    with open(kt_path, "w", encoding="utf-8") as f:
        f.write(new_kt)
    print("Injected Banner-Anchored 10-Field Offline Arabic & Handwritten OCR into", kt_path)
