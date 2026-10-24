package com.example.untitled3

import android.graphics.ImageFormat
import android.graphics.Rect
import android.graphics.YuvImage
import java.io.ByteArrayOutputStream

object YuvToJpegConverter {

    fun convertYuvToJpeg(
        yPlane: ByteArray,
        uPlane: ByteArray,
        vPlane: ByteArray,
        yRowStride: Int,
        uvRowStride: Int,
        uvPixelStride: Int,
        width: Int,
        height: Int,
        quality: Int
    ): ByteArray? {
        return try {
            // Convert YUV_420_888 planes to NV21 format
            val nv21Size = width * height * 3 / 2
            val nv21 = ByteArray(nv21Size)

            // Y plane
            var nvIndex = 0
            var yIndex = 0
            for (i in 0 until height) {
                System.arraycopy(yPlane, yIndex, nv21, nvIndex, width)
                yIndex += yRowStride
                nvIndex += width
            }

            // UV planes
            val uvHeight = height / 2
            val uvWidth = width / 2

            for (i in 0 until uvHeight) {
                var uIdx = i * uvRowStride
                var vIdx = i * uvRowStride
                for (j in 0 until uvWidth) {
                    nv21[nvIndex++] = vPlane[vIdx]
                    nv21[nvIndex++] = uPlane[uIdx]
                    uIdx += uvPixelStride
                    vIdx += uvPixelStride
                }
            }

            val yuvImage = YuvImage(nv21, ImageFormat.NV21, width, height, null)
            val out = ByteArrayOutputStream()
            yuvImage.compressToJpeg(Rect(0, 0, width, height), quality, out)
            out.toByteArray()
        } catch (e: Exception) {
            e.printStackTrace()
            null
        }
    }
}
