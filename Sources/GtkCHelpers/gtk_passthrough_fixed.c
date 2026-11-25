// The declaration lives in gtk_helpers.h; see the note there for why it is not
// in a header of its own.
// 宣告位於 gtk_helpers.h；不另立標頭檔的理由記於該處。
#include "gtk_helpers.h"

#include <math.h>

#define GTK_TYPE_PASSTHROUGH_FIXED (gtk_passthrough_fixed_get_type())

// Spelled out because G_DEFINE_TYPE generates the get_type function but not the
// checking macros -- those come from the G_DECLARE_* family, which needs the
// struct in a header, and this type's struct is deliberately private to this
// file.
// 手動定義，因為 G_DEFINE_TYPE 只產生 get_type 函式，不產生型別檢查巨集——後者出自 G_DECLARE_*
// 系列，而該系列需要把 struct 放在標頭檔中，但此型別的 struct 刻意只存在於本檔案內。
#define GTK_IS_PASSTHROUGH_FIXED(obj) \
    (G_TYPE_CHECK_INSTANCE_TYPE((obj), GTK_TYPE_PASSTHROUGH_FIXED))

typedef struct _GtkPassthroughFixed {
    GtkFixed parent_instance;

    // Whether this one draws something. False for the structural containers
    // SwiftCrossUI's layout is built from, and set from the alpha channel for a
    // colour rectangle.
    // 此元件是否有繪製內容。SwiftCrossUI 版面所使用的結構性容器為 false；色塊則依其 alpha 通道
    // 設定。
    gboolean opaque;

    // The visual-effect chain this container draws its children through, set
    // by gtk_passthrough_fixed_set_effect. FALSE for every container but a
    // visual-effect one; a container with FALSE draws exactly as GtkFixed does.
    // 本容器繪製子元件時所經過的視覺效果鏈，由 gtk_passthrough_fixed_set_effect 設定。除了視覺效果
    // 容器之外都是 FALSE;為 FALSE 的容器繪製方式與 GtkFixed 完全相同。
    gboolean has_effect;
    float blur;
    float saturation;
    float brightness;
    float contrast;
    float grayscale;
    float hue_degrees;
    gboolean invert;

    // blendMode(_:), one of the SCUI_BLEND_* values (gtk_helpers.h); SCUI_BLEND_NORMAL,
    // 0, draws as before. Set by gtk_passthrough_fixed_set_blend_mode; see scui_snapshot_blended.
    // blendMode(_:),為 SCUI_BLEND_* 之一(gtk_helpers.h);SCUI_BLEND_NORMAL(0)照舊繪製。由
    // gtk_passthrough_fixed_set_blend_mode 設定；見 scui_snapshot_blended。
    int blend_mode;
    // The container's opacity while a blend mode is set, applied to the content before
    // it is blended (the widget itself stays at 1); see scui_snapshot_blended.
    // 設有混合模式時容器的 opacity,在混合前乘到內容上(widget 本身維持 1);見 scui_snapshot_blended。
    float blend_opacity;

    // shadow(color:radius:x:y:), drawn beneath the (adjusted) children by
    // gtk_snapshot_push_shadow; set by gtk_passthrough_fixed_set_shadow.
    // shadow(color:radius:x:y:),以 gtk_snapshot_push_shadow 畫在(調整後的)子元件下方；由
    // gtk_passthrough_fixed_set_shadow 設定。
    gboolean has_shadow;
    GskShadow shadow;
} GtkPassthroughFixed;

typedef struct _GtkPassthroughFixedClass {
    GtkFixedClass parent_class;
} GtkPassthroughFixedClass;

G_DEFINE_TYPE(GtkPassthroughFixed, gtk_passthrough_fixed, GTK_TYPE_FIXED)

// Claims a point only if something has made this container interactive.
//
// GTK calls `contains` on a widget only after it has already offered the point
// to every child, so returning FALSE here removes the container from hit
// testing without hiding what it holds.
//
// The test is whether any event controller is attached. GtkBackend attaches a
// tap gesture to the widget it is asked to make tappable, so a stack carrying
// `.onTapGesture` has one and keeps its whole frame clickable, while a stack
// that is only structure has none and lets clicks through to whatever is
// behind it.
//
// 只有在此容器已被賦予互動能力時，才攔截該點。
//
// GTK 只會在把該點提供給所有子元件之後，才對 widget 呼叫 `contains`，因此在此回傳 FALSE 可將
// 容器自 hit testing 中移除，而不會遮蔽其所承載的內容。
//
// 判斷依據是「是否掛有任何 event controller」。GtkBackend 會把 tap gesture 掛在它被要求使其可
// 點擊的那個 widget 上，因此帶有 `.onTapGesture` 的 stack 會有 controller，其整個範圍仍可點擊；
// 而純粹作為結構的 stack 則沒有，點擊會穿透至其後方的元件。
static gboolean gtk_passthrough_fixed_contains(GtkWidget *widget, double x, double y) {
    GtkPassthroughFixed *self = (GtkPassthroughFixed *)widget;

    if (!self->opaque) {
        GListModel *controllers = gtk_widget_observe_controllers(widget);
        guint count = g_list_model_get_n_items(controllers);
        g_object_unref(controllers);

        if (count == 0) {
            return FALSE;
        }
    }

    return GTK_WIDGET_CLASS(gtk_passthrough_fixed_parent_class)->contains(widget, x, y);
}

void gtk_passthrough_fixed_set_opaque(GtkWidget *widget, gboolean opaque) {
    if (widget == NULL || !GTK_IS_PASSTHROUGH_FIXED(widget)) {
        return;
    }
    ((GtkPassthroughFixed *)widget)->opaque = opaque;
}

// The visual-effect chain, in the order AppKitBackend applies it: blur, then
// saturation, brightness and contrast, then grayscale, then hue, then inversion. Drawn here
// rather than through a CSS `filter` because CSS has no grayscale that matches
// AppKit's: `grayscale(1)` is the same operation as `saturate(0)`, while
// AppKit's CIColorMonochrome tinted with 0.5 grey maps the luminance through an
// overlay in linear light, which makes a darker grey than saturation 0 does
// (P39, 2026-10-16: the user chose AppKit's). That needs per-channel curves,
// which only a component transfer node can draw.
//
// 視覺效果鏈，順序與 AppKitBackend 相同：模糊，然後飽和度、亮度與對比，然後灰階，然後色相，最後顏色反轉。
// 之所以在此繪製而不經由 CSS `filter`，是因為 CSS 沒有與 AppKit 相符的灰階:`grayscale(1)` 與
// `saturate(0)` 是同一個運算，而 AppKit 以 0.5 灰上色的 CIColorMonochrome 會在線性光中把亮度經過
// overlay 映射，得到比 saturation 0 更暗的灰(P39,2026-10-16:使用者選擇以 AppKit 為準)。那需要
// 逐通道的曲線，只有 component transfer 節點畫得出來。

G_GNUC_UNUSED static float scui_srgb_to_linear(float v) {
    return v <= 0.04045f ? v / 12.92f : powf((v + 0.055f) / 1.055f, 2.4f);
}

// A colour matrix in GTK's own layout, the one gtkcssfiltervalue.c uses:
// m[input * 4 + output], with `offset` added to red, green and blue.
// GTK 自身的色彩矩陣排列(同 gtkcssfiltervalue.c):m[輸入 * 4 + 輸出],`offset` 加到紅綠藍。
static void scui_push_matrix(GtkSnapshot *snapshot, const float m[16], float offset) {
    graphene_matrix_t matrix;
    graphene_vec4_t vector;
    graphene_matrix_init_from_float(&matrix, m);
    graphene_vec4_init(&vector, offset, offset, offset, 0.0f);
    gtk_snapshot_push_color_matrix(snapshot, &matrix, &vector);
}

// Blur, saturation, brightness and contrast around the children; returns the
// number of pushes to pop. Saturation and contrast are the CSS Filter Effects
// matrices, as before. Brightness adds to each channel, as SwiftUI's does and
// as UIKitBackend and AndroidBackend draw it; CSS `brightness()` multiplies,
// which left black black where the others lift it.
// 在子元件外圍套上模糊、飽和度、亮度與對比；回傳需要 pop 的次數。飽和度與對比沿用 CSS Filter
// Effects 的矩陣。亮度是加到每個通道上，與 SwiftUI 相同，也是 UIKitBackend 與 AndroidBackend 的
// 畫法;CSS 的 `brightness()` 是乘法，會讓黑色維持黑色，而其他 backend 會把它提亮。
static int scui_push_adjustments(GtkSnapshot *snapshot, const GtkPassthroughFixed *self) {
    int pushes = 0;
    // First of these, so blur and the colour controls below change what casts the shadow,
    // not the shadow; hue rotation and grayscale, pushed around this, tint it too.
    // 放在這些之中的第一個，因此下方的模糊與色彩控制改變的是投出陰影的內容，而不是陰影本身；在外圍套用的
    // 色相旋轉與灰階也會改變陰影的顏色。
    if (self->has_shadow) {
        gtk_snapshot_push_shadow(snapshot, &self->shadow, 1);
        pushes++;
    }
    // Outermost first: the last effect to apply is pushed first.
    // 由外而內:最後套用的效果最先 push。
    if (self->contrast != 1.0f) {
        float c = self->contrast;
        const float m[16] = {c, 0, 0, 0, 0, c, 0, 0, 0, 0, c, 0, 0, 0, 0, 1};
        scui_push_matrix(snapshot, m, 0.5f - 0.5f * c);
        pushes++;
    }
    if (self->brightness != 0.0f) {
        const float m[16] = {1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1};
        scui_push_matrix(snapshot, m, self->brightness);
        pushes++;
    }
    if (self->saturation != 1.0f) {
        float s = self->saturation;
        const float m[16] = {
            0.213f + 0.787f * s, 0.213f - 0.213f * s, 0.213f - 0.213f * s, 0,
            0.715f - 0.715f * s, 0.715f + 0.285f * s, 0.715f - 0.715f * s, 0,
            0.072f - 0.072f * s, 0.072f - 0.072f * s, 0.072f + 0.928f * s, 0,
            0, 0, 0, 1,
        };
        scui_push_matrix(snapshot, m, 0.0f);
        pushes++;
    }
    if (self->blur > 0.0f) {
        // CSS blur(r) is a Gaussian with standard deviation r; GSK's radius
        // is twice that, as gtkcssfiltervalue.c passes it.
        // CSS 的 blur(r) 是標準差為 r 的高斯模糊;GSK 的半徑是它的兩倍，與 gtkcssfiltervalue.c 相同。
        gtk_snapshot_push_blur(snapshot, 2.0f * self->blur);
        pushes++;
    }
    return pushes;
}

static void scui_snapshot_adjusted(GtkWidget *widget, GtkSnapshot *snapshot) {
    int pushes = scui_push_adjustments(snapshot, (GtkPassthroughFixed *)widget);
    if (!scui_snapshot_children_painting_text(widget, snapshot)) {
        GTK_WIDGET_CLASS(gtk_passthrough_fixed_parent_class)->snapshot(widget, snapshot);
    }
    for (int i = 0; i < pushes; i++) {
        gtk_snapshot_pop(snapshot);
    }
}

#if GTK_CHECK_VERSION(4, 20, 0)
// The curves, built once, as functions rather than tables: the GPU renderer
// takes about 33 table entries across all four channels and draws black past
// that ("tables too big in component transfer"), measured 2026-10-16 with GSK
// 4.24 -- a 256-entry decode turned P39's grayscale cell black. The Cairo
// renderer has no such limit.
//
// `decode` is sRGB to linear as two steps, (v + 0.055) / 1.055 and then the
// power 2.4; `encode` is 1.055 v^(1/2.4) - 0.055. Both drop the short linear
// segment near black, which moves at most 3 of 255 levels and only below 15
// (0.7 % of colours, checked against the exact curves). `overlay` is
// CIColorMonochrome's mapping of linear luminance L against the tint c (0.5
// grey, linear 0.214): 2Lc below L = 0.5 and 1 - 2(1 - L)(1 - c) above, which
// is piecewise linear through (0, 0), (0.5, c) and (1, 1), so a three-entry
// table draws it exactly.
//
// 曲線只建一次，而且用函數而非查表:GPU renderer 四個通道合計只收約 33 個表格值，超過就畫成黑色
// (「tables too big in component transfer」),2026-10-16 以 GSK 4.24 量得——256 格的 decode 讓
// P39 的灰階格整格變黑。Cairo renderer 沒有這個限制。
//
// `decode` 是 sRGB 轉線性，分兩步:(v + 0.055) / 1.055,再取 2.4 次方;`encode` 是
// 1.055 v^(1/2.4) - 0.055。兩者都略去黑色附近那一小段線性區，最多移動 255 階中的 3 階，且只在 15
// 以下(對照精確曲線，占顏色的 0.7%)。`overlay` 是 CIColorMonochrome 將線性亮度 L 對上色值 c
// (0.5 灰，線性為 0.214)的映射:L < 0.5 時為 2Lc,以上為 1 - 2(1 - L)(1 - c);它是經過 (0, 0)、
// (0.5, c)、(1, 1) 的分段線性函數，所以三格的表就能精確畫出。
static GskComponentTransfer *scui_decode_shift, *scui_decode_power, *scui_encode, *scui_overlay,
    *scui_identity;

static void scui_ensure_transfers(void) {
    if (scui_identity != NULL) {
        return;
    }
    float overlay[3] = {0.0f, scui_srgb_to_linear(0.5f), 1.0f};
    scui_decode_shift = gsk_component_transfer_new_linear(1.0f / 1.055f, 0.055f / 1.055f);
    scui_decode_power = gsk_component_transfer_new_gamma(1.0f, 2.4f, 0.0f);
    scui_encode = gsk_component_transfer_new_gamma(1.055f, 1.0f / 2.4f, -0.055f);
    scui_overlay = gsk_component_transfer_new_table(3, overlay);
    scui_identity = gsk_component_transfer_new_identity();
}

static void scui_push_transfer(GtkSnapshot *snapshot, const GskComponentTransfer *rgb) {
    gtk_snapshot_push_component_transfer(snapshot, rgb, rgb, rgb, scui_identity);
}

// sRGB to linear: two pushes.
// sRGB 轉線性：兩次 push。
static void scui_push_decode(GtkSnapshot *snapshot) {
    scui_push_transfer(snapshot, scui_decode_power);
    scui_push_transfer(snapshot, scui_decode_shift);
}

// Linear luminance in every channel, with CIColorMonochrome's weights.
// 每個通道都是線性亮度，權重與 CIColorMonochrome 相同。
static void scui_push_luminance(GtkSnapshot *snapshot) {
    const float m[16] = {
        0.2125f, 0.2125f, 0.2125f, 0,
        0.7154f, 0.7154f, 0.7154f, 0,
        0.0721f, 0.0721f, 0.0721f, 0,
        0, 0, 0, 1,
    };
    scui_push_matrix(snapshot, m, 0.0f);
}

// The grey branch in linear light: decode, luminance, overlay. Four pushes.
// 線性光中的灰色分支:decode、亮度、overlay。四次 push。
static void scui_push_linear_grey(GtkSnapshot *snapshot) {
    scui_push_transfer(snapshot, scui_overlay);
    scui_push_luminance(snapshot);
    scui_push_decode(snapshot);
}

static void scui_pop(GtkSnapshot *snapshot, int count) {
    for (int i = 0; i < count; i++) {
        gtk_snapshot_pop(snapshot);
    }
}

static void scui_snapshot_grey(GtkWidget *widget, GtkSnapshot *snapshot, float amount) {
    scui_ensure_transfers();
    scui_push_transfer(snapshot, scui_encode);
    if (amount >= 1.0f) {
        scui_push_linear_grey(snapshot);
        scui_snapshot_adjusted(widget, snapshot);
        scui_pop(snapshot, 5);
        return;
    }
    // A partial amount blends the original and the grey in linear light, as
    // Core Image does, then encodes once. The children are drawn twice.
    // 部分強度在線性光中混合原圖與灰圖(同 Core Image),再編碼一次。子元件會被繪製兩次。
    gtk_snapshot_push_cross_fade(snapshot, amount);
    scui_push_decode(snapshot);
    scui_snapshot_adjusted(widget, snapshot);
    scui_pop(snapshot, 3);
    scui_push_linear_grey(snapshot);
    scui_snapshot_adjusted(widget, snapshot);
    scui_pop(snapshot, 4);
    scui_pop(snapshot, 2);
}
#endif

// The children through the visual-effect chain; drawn as is when there is none.
// 子元件經過視覺效果鏈繪製；沒有效果時原樣繪製。
static void scui_snapshot_content(GtkWidget *widget, GtkSnapshot *snapshot) {
    GtkPassthroughFixed *self = (GtkPassthroughFixed *)widget;
    if (!self->has_effect) {
        if (!scui_snapshot_children_painting_text(widget, snapshot)) {
            GTK_WIDGET_CLASS(gtk_passthrough_fixed_parent_class)->snapshot(widget, snapshot);
        }
        return;
    }

    // colorInvert() is the last effect to apply, so it is pushed first: 1 minus each
    // of red, green and blue. / colorInvert() 是最後套用的效果，因此最先 push:紅綠藍各自變為 1 減原值。
    if (self->invert) {
        const float m[16] = {-1, 0, 0, 0, 0, -1, 0, 0, 0, 0, -1, 0, 0, 0, 0, 1};
        scui_push_matrix(snapshot, m, 1.0f);
    }

    gboolean hue = self->hue_degrees != 0.0f;
    if (hue) {
        // The CSS Filter Effects hue rotation, as gtkcssfiltervalue.c builds it.
        // CSS Filter Effects 的色相旋轉，與 gtkcssfiltervalue.c 的建法相同。
        float radians = self->hue_degrees * (float)G_PI / 180.0f;
        float c = cosf(radians), s = sinf(radians);
        const float m[16] = {
            0.213f + 0.787f * c - 0.213f * s, 0.213f - 0.213f * c + 0.143f * s,
            0.213f - 0.213f * c - 0.787f * s, 0,
            0.715f - 0.715f * c - 0.715f * s, 0.715f + 0.285f * c + 0.140f * s,
            0.715f - 0.715f * c + 0.715f * s, 0,
            0.072f - 0.072f * c + 0.928f * s, 0.072f - 0.072f * c - 0.283f * s,
            0.072f + 0.928f * c + 0.072f * s, 0,
            0, 0, 0, 1,
        };
        scui_push_matrix(snapshot, m, 0.0f);
    }

    if (self->grayscale > 0.0f) {
#if GTK_CHECK_VERSION(4, 20, 0)
        scui_snapshot_grey(widget, snapshot, self->grayscale);
#else
        // GTK before 4.20 has no component transfer, so the linear-light curve
        // cannot be drawn; this is the CSS grayscale, the same grey as
        // saturation 0. Recorded in queue.md item 23 (Linux).
        // 4.20 之前的 GTK 沒有 component transfer,畫不出線性光的曲線;此為 CSS 灰階，與 saturation 0
        // 同一種灰。記錄於 queue.md 第 23 項(Linux)。
        float g = 1.0f - self->grayscale;
        const float m[16] = {
            0.2126f + 0.7874f * g, 0.2126f - 0.2126f * g, 0.2126f - 0.2126f * g, 0,
            0.7152f - 0.7152f * g, 0.7152f + 0.2848f * g, 0.7152f - 0.7152f * g, 0,
            0.0722f - 0.0722f * g, 0.0722f - 0.0722f * g, 0.0722f + 0.9278f * g, 0,
            0, 0, 0, 1,
        };
        scui_push_matrix(snapshot, m, 0.0f);
        scui_snapshot_adjusted(widget, snapshot);
        gtk_snapshot_pop(snapshot);
#endif
    } else {
        scui_snapshot_adjusted(widget, snapshot);
    }

    if (hue) {
        gtk_snapshot_pop(snapshot);
    }
    if (self->invert) {
        gtk_snapshot_pop(snapshot);
    }
}

// blendMode(_:): the content (with its effect chain, then the container's opacity)
// combined with what has already been drawn behind this container. GSK 4.22's copy
// node is what reaches those pixels: gtk_snapshot_push_copy stores the render target
// as it stands -- the window background and every widget drawn before this one, up
// to the nearest offscreen group such as an ancestor's opacity below 1 -- and a paste
// node draws it again inside the push. Each mode is drawn by the GSK node that
// computes it:
//
//   multiply ... luminosity   a blend node: bottom the pasted backdrop, top the
//                             content. That is already the whole result of
//                             compositing the content onto the backdrop (the W3C
//                             formula, alpha included), so a composite node with
//                             SOURCE puts it IN PLACE of the backdrop over the
//                             bounds. Drawn over the backdrop instead, as before,
//                             a translucent backdrop counted twice and came out
//                             too opaque.
//   sourceAtop, destinationOver, destinationOut
//                             a composite node with that Porter-Duff operator,
//                             which composites the content onto the backdrop
//                             itself, restricted to the bounds by its mask.
//   plusLighter, plusDarker   see scui_plus_node: built from a cross-fade, colour
//                             matrices, a lighten or darken blend and an alpha
//                             mask, exact for any backdrop alpha, and put in place
//                             of the backdrop by a SOURCE composite as above.
//
// The container's opacity is applied here, to the content before it is blended,
// and the widget itself stays at opacity 1 (GtkBackend+VisualEffects.swift): GTK
// draws a widget below opacity 1 into an offscreen group, and a copy taken inside
// it sees only that empty group, never the backdrop.
//
// blendMode(_:):內容(連同其效果鏈，再乘上容器的 opacity)與本容器後方已畫好的內容結合。取得那些像素靠的是
// GSK 4.22 的 copy 節點:gtk_snapshot_push_copy 把 render target 的現狀存下——視窗背景，以及在本元件之前
// 畫好的每個 widget,直到最近的離屏群組(例如祖先小於 1 的 opacity)為止——paste 節點則在 push 之內把它
// 再畫一次。每種模式都由能算出它的 GSK 節點繪製：
//
//   multiply ... luminosity   blend 節點：下層是貼上的背景，上層是內容。它本身就是「把內容合成到背景上」的
//                             完整結果(W3C 公式，含 alpha),所以用 SOURCE 的 composite 節點在 bounds 內
//                             「取代」背景。以前是畫在背景之上，半透明的背景因此被算了兩次，結果太不透明。
//   sourceAtop、destinationOver、destinationOut
//                             以該 Porter-Duff 運算子的 composite 節點，把內容直接合成到背景上，並以其遮罩
//                             限制在 bounds 之內。
//   plusLighter、plusDarker   見 scui_plus_node:由 cross-fade、色彩矩陣、lighten 或 darken 混合與 alpha
//                             遮罩組成，對任何背景 alpha 都精確，再如上以 SOURCE composite 取代背景。
//
// 容器的 opacity 在此套用：先乘到內容上再混合，widget 本身維持 opacity 1(GtkBackend+VisualEffects.swift)。
// GTK 會把 opacity 小於 1 的 widget 畫進離屏群組，在其中取的 copy 只看得到那個空的群組，看不到背景。

// A colour matrix node in GTK's layout (m[input * 4 + output]) with a full offset.
// GTK 排列(m[輸入 * 4 + 輸出])的色彩矩陣節點，帶完整的 offset。
static GskRenderNode *scui_matrix_node(
    GskRenderNode *child, const float m[16], float r, float g, float b, float a
) {
    graphene_matrix_t matrix;
    graphene_vec4_t offset;
    graphene_matrix_init_from_float(&matrix, m);
    graphene_vec4_init(&offset, r, g, b, a);
    return gsk_color_matrix_node_new(child, &matrix, &offset);
}

// plusLighter and plusDarker on premultiplied colour, S the content and D the
// backdrop, with the result's alpha Ra = min(1, Sa + Da):
//   plusLighter  R = min(1, S + D)                                (Core Animation's plusL)
//   plusDarker   R = max(0, Ra - (Sa - S) - (Da - D))             (its mirror: the
//                "darkness" Sa - S and Da - D adds up; over an opaque D it is
//                max(0, S + D - Sa), Core Graphics' max(0, 1 - ((1 - D) + (1 - S)))
//                for S over white, as before, and the same as AndroidBackend)
//
// GSK has no node that adds two images, and its colour matrix works on
// un-premultiplied colour, so this goes through the average A = (S + D) / 2, a
// cross-fade at 0.5 (premultiplied), whose alpha is a = (Sa + Da) / 2 and whose
// un-premultiplied colour is c = (S + D) / (Sa + Da). Then, with s = Sa + Da:
//   alpha        Ra = min(1, 2a): a matrix doubling alpha (GSK clamps).
//   colour       R / Ra is c where s <= 1 (nothing is clamped). Where s > 1, Ra = 1
//                and it is min(1, S + D) or max(0, S + D - (s - 1)): A over black,
//                doubled, or A over white, doubled minus 1 -- call it O, opaque.
//                For s <= 1 O is at most c (lighter) or at least c (darker), and
//                for s > 1 the other way round, so the colour is max(c, O) for
//                plusLighter and min(c, O) for plusDarker: a lighten or darken
//                blend of two opaque images, which is exact per channel.
//   result       that colour, opaque, masked by the alpha: colour x Ra.
// The tree is built from nodes rather than a snapshot because A is used three
// times; the paste in it refers to the nearest copy, the one around the result.
//
// 預乘色彩上的 plusLighter 與 plusDarker,S 為內容、D 為背景，結果的 alpha Ra = min(1, Sa + Da):
//   plusLighter  R = min(1, S + D)                                (Core Animation 的 plusL)
//   plusDarker   R = max(0, Ra - (Sa - S) - (Da - D))             (它的鏡像：「暗度」Sa - S 與 Da - D 相加；
//                D 不透明時即 max(0, S + D - Sa),也就是 S 疊在白色上時 Core Graphics 的
//                max(0, 1 - ((1 - D) + (1 - S))),與先前相同，也與 AndroidBackend 相同)
//
// GSK 沒有把兩張影像相加的節點，且其色彩矩陣作用於未預乘的顏色，因此經由平均值 A = (S + D) / 2——0.5 的
// cross-fade(預乘)——其 alpha 為 a = (Sa + Da) / 2,未預乘顏色為 c = (S + D) / (Sa + Da)。令 s = Sa + Da:
//   alpha        Ra = min(1, 2a):把 alpha 加倍的矩陣(GSK 會箝制)。
//   顏色         s <= 1 時 R / Ra 就是 c(沒有任何箝制)。s > 1 時 Ra = 1,顏色為 min(1, S + D) 或
//                max(0, S + D - (s - 1)):A 疊在黑色上再加倍，或 A 疊在白色上加倍減 1——記為 O,不透明。
//                s <= 1 時 O 不大於 c(lighter)或不小於 c(darker),s > 1 時相反，因此顏色是 plusLighter 的
//                max(c, O)、plusDarker 的 min(c, O):兩張不透明影像的 lighten 或 darken 混合，逐通道精確。
//   結果         把該顏色(不透明)以 alpha 遮罩：顏色 x Ra。
// 以節點而非 snapshot 建樹，因為 A 要用三次；其中的 paste 指向最近的 copy,即包住結果的那一個。
static GskRenderNode *scui_plus_node(
    GskRenderNode *content, const graphene_rect_t *bounds, gboolean lighter
) {
    GskRenderNode *paste = gsk_paste_node_new(bounds, 0);
    GskRenderNode *average = gsk_cross_fade_node_new(paste, content, 0.5f);
    gsk_render_node_unref(paste);

    // c, opaque: the colour kept, alpha replaced by 1. / c,不透明：顏色不變,alpha 換成 1。
    const float keep_colour[16] = {1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0};
    GskRenderNode *unpremultiplied = scui_matrix_node(average, keep_colour, 0, 0, 0, 1);

    // O: A over black (or white), doubled (minus 1). / O:A 疊在黑(或白)上，加倍(減 1)。
    const GdkRGBA under = lighter ? (GdkRGBA){0, 0, 0, 1} : (GdkRGBA){1, 1, 1, 1};
    GskRenderNode *backing = gsk_color_node_new(&under, bounds);
    GskRenderNode *layers[2] = {backing, average};
    GskRenderNode *flattened = gsk_container_node_new(layers, 2);
    gsk_render_node_unref(backing);
    const float twice[16] = {2, 0, 0, 0, 0, 2, 0, 0, 0, 0, 2, 0, 0, 0, 0, 1};
    float shift = lighter ? 0.0f : -1.0f;
    GskRenderNode *opaque = scui_matrix_node(flattened, twice, shift, shift, shift, 0);
    gsk_render_node_unref(flattened);

    GskRenderNode *colour = gsk_blend_node_new(
        unpremultiplied, opaque, lighter ? GSK_BLEND_MODE_LIGHTEN : GSK_BLEND_MODE_DARKEN
    );
    gsk_render_node_unref(unpremultiplied);
    gsk_render_node_unref(opaque);

    // Ra = min(1, 2a). / Ra = min(1, 2a)。
    const float twice_alpha[16] = {1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 2};
    GskRenderNode *alpha = scui_matrix_node(average, twice_alpha, 0, 0, 0, 0);
    gsk_render_node_unref(average);

    GskRenderNode *result = gsk_mask_node_new(colour, alpha, GSK_MASK_MODE_ALPHA);
    gsk_render_node_unref(colour);
    gsk_render_node_unref(alpha);
    return result;
}

static void scui_snapshot_blended(GtkWidget *widget, GtkSnapshot *snapshot, int mode) {
    GtkPassthroughFixed *self = (GtkPassthroughFixed *)widget;

    // The content as one node: the effect chain, then the container's opacity.
    // 內容成為一個節點：效果鏈，再乘上容器的 opacity。
    GtkSnapshot *inner = gtk_snapshot_new();
    gboolean faded = self->blend_opacity < 1.0f;
    if (faded) {
        gtk_snapshot_push_opacity(inner, self->blend_opacity);
    }
    scui_snapshot_content(widget, inner);
    if (faded) {
        gtk_snapshot_pop(inner);
    }
    GskRenderNode *content = gtk_snapshot_free_to_node(inner);
    if (content == NULL) {
        // Nothing drawn: every mode leaves the backdrop as it is. / 什麼都沒畫：每種模式都讓背景維持原樣。
        return;
    }

    // The widget's bounds, grown to the content's (a shadow reaches past them).
    // widget 的範圍，擴大到內容的範圍(陰影會超出)。
    graphene_rect_t bounds = GRAPHENE_RECT_INIT(
        0, 0, (float)gtk_widget_get_width(widget), (float)gtk_widget_get_height(widget)
    );
    graphene_rect_t content_bounds;
    gsk_render_node_get_bounds(content, &content_bounds);
    graphene_rect_union(&bounds, &content_bounds, &bounds);
    const GdkRGBA mask = {1, 1, 1, 1};

    if (mode == SCUI_BLEND_SOURCE_ATOP || mode == SCUI_BLEND_DESTINATION_OVER ||
        mode == SCUI_BLEND_DESTINATION_OUT) {
        GskPorterDuff op = mode == SCUI_BLEND_SOURCE_ATOP ? GSK_PORTER_DUFF_SOURCE_ATOP_DEST
                           : mode == SCUI_BLEND_DESTINATION_OVER ? GSK_PORTER_DUFF_DEST_OVER_SOURCE
                                                                 : GSK_PORTER_DUFF_DEST_OUT_SOURCE;
        gtk_snapshot_push_composite(snapshot, op);
        gtk_snapshot_append_color(snapshot, &mask, &bounds);
        gtk_snapshot_pop(snapshot);
        gtk_snapshot_append_node(snapshot, content);
        gtk_snapshot_pop(snapshot);
        gsk_render_node_unref(content);
        return;
    }

    GskRenderNode *result;
    if (mode == SCUI_BLEND_PLUS_LIGHTER || mode == SCUI_BLEND_PLUS_DARKER) {
        result = scui_plus_node(content, &bounds, mode == SCUI_BLEND_PLUS_LIGHTER);
    } else {
        // SwiftUI's order from multiply to luminosity, as GSK names them.
        // SwiftUI 從 multiply 到 luminosity 的順序，以 GSK 的名稱表示。
        static const GskBlendMode modes[] = {
            [SCUI_BLEND_MULTIPLY] = GSK_BLEND_MODE_MULTIPLY,
            [SCUI_BLEND_SCREEN] = GSK_BLEND_MODE_SCREEN,
            [SCUI_BLEND_OVERLAY] = GSK_BLEND_MODE_OVERLAY,
            [SCUI_BLEND_DARKEN] = GSK_BLEND_MODE_DARKEN,
            [SCUI_BLEND_LIGHTEN] = GSK_BLEND_MODE_LIGHTEN,
            [SCUI_BLEND_COLOR_DODGE] = GSK_BLEND_MODE_COLOR_DODGE,
            [SCUI_BLEND_COLOR_BURN] = GSK_BLEND_MODE_COLOR_BURN,
            [SCUI_BLEND_SOFT_LIGHT] = GSK_BLEND_MODE_SOFT_LIGHT,
            [SCUI_BLEND_HARD_LIGHT] = GSK_BLEND_MODE_HARD_LIGHT,
            [SCUI_BLEND_DIFFERENCE] = GSK_BLEND_MODE_DIFFERENCE,
            [SCUI_BLEND_EXCLUSION] = GSK_BLEND_MODE_EXCLUSION,
            [SCUI_BLEND_HUE] = GSK_BLEND_MODE_HUE,
            [SCUI_BLEND_SATURATION] = GSK_BLEND_MODE_SATURATION,
            [SCUI_BLEND_COLOR] = GSK_BLEND_MODE_COLOR,
            [SCUI_BLEND_LUMINOSITY] = GSK_BLEND_MODE_LUMINOSITY,
        };
        GskRenderNode *paste = gsk_paste_node_new(&bounds, 0);
        result = gsk_blend_node_new(paste, content, modes[mode]);
        gsk_render_node_unref(paste);
    }
    gsk_render_node_unref(content);

    // The result in place of the backdrop over the bounds. / 在 bounds 內以結果取代背景。
    gtk_snapshot_push_copy(snapshot);
    gtk_snapshot_push_composite(snapshot, GSK_PORTER_DUFF_SOURCE);
    gtk_snapshot_append_color(snapshot, &mask, &bounds);
    gtk_snapshot_pop(snapshot);
    gtk_snapshot_append_node(snapshot, result);
    gtk_snapshot_pop(snapshot);
    gtk_snapshot_pop(snapshot);
    gsk_render_node_unref(result);
}

static void gtk_passthrough_fixed_snapshot(GtkWidget *widget, GtkSnapshot *snapshot) {
    int mode = ((GtkPassthroughFixed *)widget)->blend_mode;
    if (mode > SCUI_BLEND_NORMAL && mode <= SCUI_BLEND_PLUS_LIGHTER) {
        scui_snapshot_blended(widget, snapshot, mode);
    } else {
        scui_snapshot_content(widget, snapshot);
    }
}

void gtk_passthrough_fixed_set_blend_mode(GtkWidget *widget, int mode, float opacity) {
    if (widget == NULL || !GTK_IS_PASSTHROUGH_FIXED(widget)) {
        return;
    }
    GtkPassthroughFixed *self = (GtkPassthroughFixed *)widget;
    if (self->blend_mode != mode || self->blend_opacity != opacity) {
        self->blend_mode = mode;
        self->blend_opacity = opacity;
        gtk_widget_queue_draw(widget);
    }
}

void gtk_passthrough_fixed_set_effect(
    GtkWidget *widget, float blur, float saturation, float brightness, float contrast,
    float grayscale, float hue_degrees, gboolean invert
) {
    if (widget == NULL || !GTK_IS_PASSTHROUGH_FIXED(widget)) {
        return;
    }
    GtkPassthroughFixed *self = (GtkPassthroughFixed *)widget;
    self->blur = blur;
    self->saturation = saturation;
    self->brightness = brightness;
    self->contrast = contrast;
    self->grayscale = grayscale;
    self->hue_degrees = hue_degrees;
    self->invert = invert;
    self->has_effect = self->has_shadow || blur > 0.0f || saturation != 1.0f || brightness != 0.0f ||
                       contrast != 1.0f || grayscale > 0.0f || hue_degrees != 0.0f || invert;
    gtk_widget_queue_draw(widget);
}

void gtk_passthrough_fixed_set_shadow(
    GtkWidget *widget, float red, float green, float blue, float alpha, float dx, float dy,
    float radius
) {
    if (widget == NULL || !GTK_IS_PASSTHROUGH_FIXED(widget)) {
        return;
    }
    GtkPassthroughFixed *self = (GtkPassthroughFixed *)widget;
    gboolean had_shadow = self->has_shadow;
    self->shadow.color = (GdkRGBA){red, green, blue, alpha};
    self->shadow.dx = dx;
    self->shadow.dy = dy;
    self->shadow.radius = radius;
    self->has_shadow = alpha > 0.0f;
    if (self->has_shadow) {
        self->has_effect = TRUE;
    } else if (had_shadow) {
        // Recomputed from the other effects, which set_effect last stored.
        // 由 set_effect 最後存下的其他效果重新計算。
        self->has_effect = self->blur > 0.0f || self->saturation != 1.0f ||
                           self->brightness != 0.0f || self->contrast != 1.0f ||
                           self->grayscale > 0.0f || self->hue_degrees != 0.0f || self->invert;
    }
    gtk_widget_queue_draw(widget);
}

static void gtk_passthrough_fixed_class_init(GtkPassthroughFixedClass *klass) {
    GTK_WIDGET_CLASS(klass)->contains = gtk_passthrough_fixed_contains;
    GTK_WIDGET_CLASS(klass)->snapshot = gtk_passthrough_fixed_snapshot;
}

static void gtk_passthrough_fixed_init(GtkPassthroughFixed *self) {
    (void)self;
}

GtkWidget *gtk_passthrough_fixed_new(void) {
    return g_object_new(GTK_TYPE_PASSTHROUGH_FIXED, NULL);
}
