package dev.swiftcrossui.androidbackend

import android.app.Activity
import android.graphics.Bitmap
import android.webkit.WebView
import android.webkit.WebViewClient

/// **Reports from `onPageStarted`, not from `shouldOverrideUrlLoading`, and the
/// difference is one whole navigation.**
///
/// `shouldOverrideUrlLoading` is asked only about navigations the PAGE starts --
/// a tapped link. The first load is started by `loadUrl` from our own code, so
/// it was never reported at all: P38 rendered example.com and printed
/// `Navigations reported: 0` on 2026-09-17, where AppKit and UIKit both printed
/// 1. Nothing failed; the page was there, and the count beside it was a page
/// behind reality.
///
/// `onPageStarted` fires for every navigation whoever starts it, which is what
/// WKWebView's `didCommit` does on the two Apple backends -- so the three now
/// mean the same thing by one report.
///
/// **回報改由 `onPageStarted` 發出,而不是 `shouldOverrideUrlLoading`,而兩者之差正好是一次完整的
/// 導覽。**
///
/// `shouldOverrideUrlLoading` 只會針對**頁面自己**發起的導覽被詢問——例如被點擊的連結。第一次載入是
/// 由我們自己的程式以 `loadUrl` 發起的,因此它從來不曾被回報:2026-09-17 的 P38 畫出了 example.com,
/// 旁邊卻寫著 `Navigations reported: 0`,而 AppKit 與 UIKit 兩者都寫 1。沒有任何東西失敗;頁面就在
/// 那裡,只是它旁邊的計數比現實少了一次。
///
/// `onPageStarted` 對每一次導覽都會觸發,不論由誰發起——那正是 WKWebView 的 `didCommit` 在兩個 Apple
/// backend 上所做的事,於是這三者現在以同一份回報說著同一件事。
class CustomWebView(activity: Activity) : WebView(activity) {
    var onNavigate: SwiftAction? = null

    var loadingUrl: String? = null
        private set

    init {
        webViewClient =
            object : WebViewClient() {
                override fun onPageStarted(webView: WebView, url: String, favicon: Bitmap?) {
                    loadingUrl = url
                    onNavigate?.call()
                }
            }

        settings.javaScriptEnabled = true
    }

    override fun loadUrl(url: String) {
        loadingUrl = url
        super.loadUrl(url)
    }
}
