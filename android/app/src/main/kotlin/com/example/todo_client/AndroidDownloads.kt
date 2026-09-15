package com.example.todo_client

import android.Manifest
import android.app.Activity
import android.content.ContentValues
import android.content.Intent
import android.content.pm.PackageManager
import android.media.MediaScannerConnection
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.DocumentsContract
import android.provider.MediaStore
import android.provider.OpenableColumns
import android.webkit.MimeTypeMap
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.IOException
import java.util.concurrent.Executors

class AndroidDownloads(private val activity: Activity, messenger: BinaryMessenger) {
    private val prefs = activity.getSharedPreferences("download_directory", Activity.MODE_PRIVATE)
    private val resolver get() = activity.contentResolver
    private val worker = Executors.newSingleThreadExecutor()
    private var pickerResult: MethodChannel.Result? = null
    private var permissionSave: Pair<MethodCall, MethodChannel.Result>? = null

    init {
        MethodChannel(messenger, "todo_client/downloads").setMethodCallHandler { call, result ->
            when (call.method) {
                "getDirectory" -> result.success(directoryLabel())
                "chooseDirectory" -> chooseDirectory(result)
                "resetDirectory" -> {
                    val previous = prefs.getString("uri", null)
                    prefs.edit().clear().commit()
                    releaseGrant(previous)
                    result.success("Download")
                }
                "saveDownload" -> {
                    if (Build.VERSION.SDK_INT < 29 && prefs.getString("uri", null) == null &&
                        activity.checkSelfPermission(Manifest.permission.WRITE_EXTERNAL_STORAGE) != PackageManager.PERMISSION_GRANTED) {
                        if (permissionSave != null) {
                            result.error("busy", "请先完成存储权限授权", null)
                        } else {
                            permissionSave = call to result
                            activity.requestPermissions(arrayOf(Manifest.permission.WRITE_EXTERNAL_STORAGE), PERMISSION_REQUEST)
                        }
                    } else save(call, result)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun directoryLabel() = prefs.getString("label", null) ?: "Download"

    private fun releaseGrant(value: String?) {
        if (value == null) return
        try {
            resolver.releasePersistableUriPermission(Uri.parse(value), Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
        } catch (_: Exception) { /* Already revoked by the user or provider. */ }
    }

    private fun chooseDirectory(result: MethodChannel.Result) {
        if (pickerResult != null) {
            result.error("busy", "目录选择器已打开", null)
            return
        }
        pickerResult = result
        try {
            val intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).apply {
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION or
                    Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION or Intent.FLAG_GRANT_PREFIX_URI_PERMISSION)
                if (Build.VERSION.SDK_INT >= 26) {
                    prefs.getString("uri", null)?.let { putExtra(DocumentsContract.EXTRA_INITIAL_URI, Uri.parse(it)) }
                }
            }
            activity.startActivityForResult(intent, DIRECTORY_REQUEST)
        } catch (e: Exception) {
            pickerResult = null
            result.error("directory_picker_failed", "无法打开系统目录选择器：${e.message}", null)
        }
    }

    fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (requestCode != DIRECTORY_REQUEST) return
        val result = pickerResult ?: return
        pickerResult = null
        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null) {
            result.success(null) // Cancellation leaves the current directory intact.
            return
        }
        try {
            val flags = data.flags and (Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
            if (flags and Intent.FLAG_GRANT_WRITE_URI_PERMISSION == 0) throw IOException("所选目录未授予写入权限")
            resolver.takePersistableUriPermission(uri, flags)
            val document = DocumentsContract.buildDocumentUriUsingTree(uri, DocumentsContract.getTreeDocumentId(uri))
            val documentId = DocumentsContract.getTreeDocumentId(uri)
            val label = if (uri.authority == "com.android.externalstorage.documents" && documentId.startsWith("primary:")) {
                "内部存储/" + documentId.removePrefix("primary:")
            } else displayName(document, "所选目录")
            val previous = prefs.getString("uri", null)
            if (!prefs.edit().putString("uri", uri.toString()).putString("label", label).commit()) {
                throw IOException("无法记住下载目录，请重试")
            }
            if (previous != uri.toString()) releaseGrant(previous)
            result.success(label)
        } catch (e: Exception) {
            result.error("directory_permission_failed", "无法使用该目录：${e.message}", null)
        }
    }

    fun onRequestPermissionsResult(requestCode: Int, grantResults: IntArray) {
        if (requestCode != PERMISSION_REQUEST) return
        val pending = permissionSave ?: return
        permissionSave = null
        if (grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED) {
            save(pending.first, pending.second)
        } else {
            pending.second.error("permission_denied", "未获得下载目录写入权限，请在设置中选择可写入的目录", null)
        }
    }

    private fun save(call: MethodCall, result: MethodChannel.Result) {
        val sourcePath = call.argument<String>("sourcePath")
        val requestedName = call.argument<String>("fileName")
        val tree = prefs.getString("uri", null)
        val label = directoryLabel()
        worker.execute {
            try {
                val source = File(sourcePath ?: throw IOException("缺少临时文件")).canonicalFile
                val cache = activity.cacheDir.canonicalFile
                if (!source.path.startsWith(cache.path + File.separator) || !source.isFile) {
                    throw IOException("下载临时文件不存在")
                }
                val name = requestedName.orEmpty().replace(Regex("[\\\\/\\p{Cntrl}]"), "_")
                    .take(180).takeUnless { it.isBlank() || it == "." || it == ".." } ?: "download"
                val mime = MimeTypeMap.getSingleton().getMimeTypeFromExtension(name.substringAfterLast('.', "").lowercase())
                    ?: "application/octet-stream"
                val location = when {
                    tree != null -> saveToTree(source, name, mime, Uri.parse(tree), label)
                    Build.VERSION.SDK_INT >= 29 -> saveToDownloads(source, name, mime)
                    else -> saveLegacy(source, name, mime)
                }
                activity.runOnUiThread { result.success(location) }
            } catch (e: Exception) {
                activity.runOnUiThread {
                    result.error("save_failed", "文件保存失败，请检查剩余空间或在设置中重新选择下载目录。${e.message ?: ""}", null)
                }
            }
        }
    }

    private fun copy(source: File, uri: Uri) {
        val expected = source.length()
        val copied = (resolver.openOutputStream(uri, "w") ?: throw IOException("无法写入所选目录")).use { output ->
            source.inputStream().use { input -> input.copyTo(output) }.also { output.flush() }
        }
        if (copied != expected) throw IOException("文件未完整写入")
    }

    private fun displayName(uri: Uri, fallback: String): String {
        resolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use { cursor ->
            if (cursor.moveToFirst() && !cursor.isNull(0)) return cursor.getString(0)
        }
        return fallback
    }

    private fun saveToTree(source: File, name: String, mime: String, tree: Uri, label: String): String {
        if (resolver.persistedUriPermissions.none { it.uri == tree && it.isWritePermission }) {
            throw IOException("目录授权已失效，请重新选择目录")
        }
        val parent = DocumentsContract.buildDocumentUriUsingTree(tree, DocumentsContract.getTreeDocumentId(tree))
        val destination = DocumentsContract.createDocument(resolver, parent, mime, name)
            ?: throw IOException("无法在所选目录创建文件")
        try {
            copy(source, destination)
            return "$label/${displayName(destination, name)}"
        } catch (e: Exception) {
            try { DocumentsContract.deleteDocument(resolver, destination) } catch (_: Exception) {}
            throw e
        }
    }

    @android.annotation.TargetApi(29)
    private fun saveToDownloads(source: File, name: String, mime: String): String {
        val values = ContentValues().apply {
            put(MediaStore.Downloads.DISPLAY_NAME, name)
            put(MediaStore.Downloads.MIME_TYPE, mime)
            put(MediaStore.Downloads.RELATIVE_PATH, Environment.DIRECTORY_DOWNLOADS)
            put(MediaStore.Downloads.IS_PENDING, 1)
        }
        val destination = resolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values)
            ?: throw IOException("无法在 Download 创建文件")
        try {
            copy(source, destination)
            val actualName = displayName(destination, name)
            val complete = ContentValues().apply { put(MediaStore.Downloads.IS_PENDING, 0) }
            if (resolver.update(destination, complete, null, null) != 1) throw IOException("无法发布下载文件")
            return "Download/$actualName"
        } catch (e: Exception) {
            try { resolver.delete(destination, null, null) } catch (_: Exception) {}
            throw e
        }
    }

    @Suppress("DEPRECATION")
    private fun saveLegacy(source: File, name: String, mime: String): String {
        val directory = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS)
        if (!directory.isDirectory && !directory.mkdirs()) throw IOException("无法创建 Download 目录")
        var destination = File(directory, name)
        var suffix = 1
        val dot = name.lastIndexOf('.').takeIf { it > 0 } ?: name.length
        while (!destination.createNewFile()) {
            destination = File(directory, "${name.substring(0, dot)} (${suffix++})${name.substring(dot)}")
        }
        try {
            source.inputStream().use { input -> destination.outputStream().use { output -> input.copyTo(output) } }
            if (destination.length() != source.length()) throw IOException("文件未完整写入")
            MediaScannerConnection.scanFile(activity, arrayOf(destination.path), arrayOf(mime), null)
            return "Download/${destination.name}"
        } catch (e: Exception) {
            destination.delete()
            throw e
        }
    }

    companion object {
        private const val DIRECTORY_REQUEST = 47021
        private const val PERMISSION_REQUEST = 47022
    }
}
