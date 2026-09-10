import AndroidKit
import SwiftJava

/// `android.widget.PopupWindow`, declared here for the one method AndroidKit's
/// own binding leaves out.
///
/// **AndroidKit binds 45 methods on `PopupWindow` and neither
/// `getContentView` nor `setBackgroundDrawable` is among them.** That was found
/// by listing the generated binding's own methods on 2026-09-10, after code
/// written on a machine that cannot compile this backend used
/// `setBackgroundDrawable` and did not build here. Declaring the missing method
/// is the same technique `CustomSlider` already uses for the toolkit's own
/// Kotlin class -- a hand-written `@JavaMethod` against a known Java signature.
///
/// Kept separate from any use of it so the reason survives: a reader who finds
/// `popover.as(PopupWindowContent.self)` in the popover file and wonders why it
/// is not simply `popover.getContentView()` is one hop from the answer.
///
/// `android.widget.PopupWindow`,此處宣告它,只為了 AndroidKit 自身的 binding 漏掉的那一個方法。
///
/// **AndroidKit 在 `PopupWindow` 上綁定了 45 個方法,而 `getContentView` 與
/// `setBackgroundDrawable` 都不在其中。** 這是 2026-09-10 以「列出該產生式 binding 自身的方法」查出來的
/// ——在此之前,一段寫於「無法編譯本 backend 之機器」上的程式使用了 `setBackgroundDrawable`,而它在此處
/// 建不起來。宣告那個缺失的方法,與 `CustomSlider` 對本工具組自有 Kotlin 類別所採用的是同一種手法:
/// 針對一個已知的 Java 簽章手寫一個 `@JavaMethod`。
///
/// 與它的使用處分開存放,好讓理由能存活下來:讀者若在 popover 檔案中看到
/// `popover.as(PopupWindowContent.self)` 而納悶為何不直接寫 `popover.getContentView()`,
/// 只需一步就能找到答案。
@JavaClass("android.widget.PopupWindow")
class PopupWindowContent: JavaObject {
    @JavaMethod
    func getContentView() -> AndroidKit.View!
}
