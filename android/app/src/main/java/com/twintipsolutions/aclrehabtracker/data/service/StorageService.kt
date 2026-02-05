package com.twintipsolutions.aclrehabtracker.data.service

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import com.google.firebase.storage.FirebaseStorage
import kotlinx.coroutines.tasks.await
import java.io.ByteArrayOutputStream
import java.io.File

object StorageService {
    private val storage = FirebaseStorage.getInstance()

    suspend fun uploadPhoto(uid: String, measurementId: String, filePath: String): String {
        val file = File(filePath)
        val bitmap = BitmapFactory.decodeFile(file.absolutePath)
        return uploadBitmap(uid, measurementId, bitmap)
    }

    suspend fun uploadBitmap(uid: String, measurementId: String, bitmap: Bitmap): String {
        val baos = ByteArrayOutputStream()
        bitmap.compress(Bitmap.CompressFormat.JPEG, 80, baos)
        val data = baos.toByteArray()

        val ref = storage.reference.child("users/$uid/photos/$measurementId.jpg")
        ref.putBytes(data).await()
        return ref.downloadUrl.await().toString()
    }

    suspend fun deletePhoto(uid: String, measurementId: String) {
        val ref = storage.reference.child("users/$uid/photos/$measurementId.jpg")
        ref.delete().await()
    }
}
