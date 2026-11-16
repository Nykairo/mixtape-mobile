package dev.softwarevault.mixtape_native

import android.content.ContentProvider
import android.content.ContentValues
import android.content.Context
import android.database.Cursor
import android.database.MatrixCursor
import android.net.Uri
import android.os.ParcelFileDescriptor
import android.provider.OpenableColumns
import java.io.File

/**
 * Hands a picture Mixtape made (the Rewind card) to the app it's shared with, read-only and only for
 * that one share. The pictures wait in the cache's "shared" folder; nothing else can be reached
 * through here. Small on purpose: androidx's FileProvider would do the same and bring a library along.
 */
class SharedFiles : ContentProvider() {
    override fun onCreate() = true

    private fun fileOf(uri: Uri): File? {
        val context = context ?: return null
        val name = uri.lastPathSegment ?: return null
        if (name.contains('/') || name.startsWith(".")) return null
        val f = File(folder(context), name)
        return if (f.isFile) f else null
    }

    override fun openFile(uri: Uri, mode: String): ParcelFileDescriptor? {
        val f = fileOf(uri) ?: return null
        return ParcelFileDescriptor.open(f, ParcelFileDescriptor.MODE_READ_ONLY)
    }

    override fun getType(uri: Uri): String = if (uri.lastPathSegment?.endsWith(".png") == true) "image/png" else "application/octet-stream"

    override fun query(uri: Uri, projection: Array<out String>?, selection: String?, args: Array<out String>?, order: String?): Cursor? {
        val f = fileOf(uri) ?: return null
        val columns = projection ?: arrayOf(OpenableColumns.DISPLAY_NAME, OpenableColumns.SIZE)
        val row = columns.map { if (it == OpenableColumns.SIZE) f.length() else if (it == OpenableColumns.DISPLAY_NAME) f.name else null }
        return MatrixCursor(columns, 1).apply { addRow(row.toTypedArray()) }
    }

    override fun insert(uri: Uri, values: ContentValues?): Uri? = null
    override fun delete(uri: Uri, selection: String?, args: Array<out String>?) = 0
    override fun update(uri: Uri, values: ContentValues?, selection: String?, args: Array<out String>?) = 0

    companion object {
        fun folder(context: Context) = File(context.cacheDir, "shared").apply { mkdirs() }

        fun uriOf(context: Context, file: File): Uri = Uri.parse("content://${context.packageName}.mixtape.shared/${file.name}")
    }
}
