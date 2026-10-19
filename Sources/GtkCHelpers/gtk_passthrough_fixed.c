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
// saturation, brightness and contrast, then grayscale, then hue. Drawn here
// rather than through a CSS `filter` because CSS has no grayscale that matches
// AppKit's: `grayscale(1)` is the same operation as `saturate(0)`, while
// AppKit's CIColorMonochrome tinted with 0.5 grey maps the luminance through an
// overlay in linear light, which makes a darker grey than saturation 0 does
// (P39, 2026-10-16: the user chose AppKit's). That needs per-channel curves,
// which only a component transfer node can draw.
//
// 視覺效果鏈，順序與 AppKitBackend 相同：模糊，然後飽和度、亮度與對比，然後灰階，最後色相。
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

static void gtk_passthrough_fixed_snapshot(GtkWidget *widget, GtkSnapshot *snapshot) {
    GtkPassthroughFixed *self = (GtkPassthroughFixed *)widget;
    if (!self->has_effect) {
        if (!scui_snapshot_children_painting_text(widget, snapshot)) {
            GTK_WIDGET_CLASS(gtk_passthrough_fixed_parent_class)->snapshot(widget, snapshot);
        }
        return;
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
}

void gtk_passthrough_fixed_set_effect(
    GtkWidget *widget, float blur, float saturation, float brightness, float contrast,
    float grayscale, float hue_degrees
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
    self->has_effect = blur > 0.0f || saturation != 1.0f || brightness != 0.0f ||
                       contrast != 1.0f || grayscale > 0.0f || hue_degrees != 0.0f;
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
