package dev.swiftcrossui.androidbackend.activityresults

import android.app.Activity
import android.content.ContentResolver
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.provider.DocumentsContract
import android.provider.OpenableColumns
import android.webkit.MimeTypeMap
import androidx.activity.result.contract.ActivityResultContract

// ActivityResultContracts.OpenMultipleDocuments doesn't set the starting directory.
class FilesActivityContract : ActivityResultContract<FilesActivityContract.Options, Set<Uri>>() {
    data class Options(
        val allowMultiple: Boolean,
        val mimeTypes: Array<String>,
        val rootDirectory: String?,
        // Every extension the allowed types accept, their own and the narrower
        // ones that also count (ContentType.conformingFileExtensions).
        // 允許的型別接受的每一個副檔名：它們自己的，以及也算數的較窄型別的(ContentType.conformingFileExtensions)。
        val extensions: Array<String>,
    )

    // What parseResult needs from createIntent: the picker filters by the MIME
    // type the storage provider reports, and an extension Android does not know
    // (`swift`) is reported as application/octet-stream -- measured on the API 36
    // emulator 2026-10-07: under text/plain, also-text.swift is disabled. So
    // octet-stream is added when an allowed extension has no MIME type, and what
    // comes back is then checked by name, or every unknown binary file would pass.
    // parseResult 需要從 createIntent 取得的東西：選擇器依 storage provider 回報的 MIME 過濾，而
    // Android 不認得的副檔名(`swift`)會被報成 application/octet-stream——2026-10-07 在 API 36 模擬器上
    // 實測：text/plain 之下 also-text.swift 是停用的。因此當某個允許的副檔名沒有 MIME 時就加上
    // octet-stream，回來的結果再依檔名檢查，否則每一個未知的二進位檔都會通過。
    private var resolver: ContentResolver? = null
    private var checkedExtensions: Set<String> = emptySet()

    override fun createIntent(context: Context, input: Options): Intent {
        resolver = context.contentResolver
        val mimeTypes = linkedSetOf(*input.mimeTypes)
        var unknownExtension = false
        if (mimeTypes.isNotEmpty()) {
            for (extension in input.extensions) {
                val mime = MimeTypeMap.getSingleton().getMimeTypeFromExtension(extension.lowercase())
                if (mime != null) mimeTypes.add(mime) else unknownExtension = true
            }
        }
        if (unknownExtension) mimeTypes.add("application/octet-stream")
        checkedExtensions =
            if (unknownExtension) input.extensions.map { it.lowercase() }.toSet() else emptySet()

        return Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            putExtra(Intent.EXTRA_ALLOW_MULTIPLE, input.allowMultiple)

            when (mimeTypes.size) {
                0 -> setType("*/*")
                1 -> setType(mimeTypes.first())
                else -> {
                    setType("*/*")
                    putExtra(Intent.EXTRA_MIME_TYPES, mimeTypes.toTypedArray())
                }
            }

            if (input.rootDirectory != null) {
                putExtra(DocumentsContract.EXTRA_INITIAL_URI, Uri.parse(input.rootDirectory))
            }
        }
    }

    override fun parseResult(resultCode: Int, intent: Intent?): Set<Uri> {
        if (intent == null || resultCode != Activity.RESULT_OK) return emptySet<Uri>()

        val result = linkedSetOf<Uri>()

        val intentData = intent.data
        if (intentData != null) {
            result.add(intentData)
        }

        val clipData = intent.clipData
        if (clipData != null) {
            for (i in 0..<clipData.itemCount) {
                val uri = clipData.getItemAt(i).uri
                if (uri != null) {
                    result.add(uri)
                }
            }
        }

        if (checkedExtensions.isEmpty()) return result
        return result.filterTo(linkedSetOf()) { uri ->
            val extension = displayName(uri)?.substringAfterLast('.', "")?.lowercase()
            val accepted = extension != null && extension in checkedExtensions
            if (!accepted) {
                android.util.Log.w(
                    "SwiftCrossUI",
                    "open dialog: ${displayName(uri) ?: uri} is not one of " +
                        "$checkedExtensions; the picker offered it only as application/octet-stream"
                )
            }
            accepted
        }
    }

    private fun displayName(uri: Uri): String? =
        resolver?.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use {
            if (it.moveToFirst()) it.getString(0) else null
        }
}
