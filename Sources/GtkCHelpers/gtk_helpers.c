#include "gtk_helpers.h"

// develop requires GTK 4.22 or newer (the user's decision, 2026-11-17). GTK
// 4.14 -- Ubuntu 24.04 LTS -- is supported on Ubuntu-24-04-branch instead,
// which carries a workaround for a scroll-chaining difference: before 4.20.1
// a wheel across a one-axis GtkScrolledWindow never reached the scroll view
// around it (P8, CI run 43992716580). Checked here, at build time, so an
// older GTK fails with this reason rather than at run time with a symptom.
// develop 要求 GTK 4.22 以上(使用者的決定,2026-11-17)。GTK 4.14——Ubuntu 24.04 LTS——改由 Ubuntu-24-04-branch 支援，該分支帶有
// 一個捲動轉交差異的 workaround:4.20.1 之前，橫越單軸 GtkScrolledWindow 的滾輪到不了外圍的捲動視圖(P8,CI run 43992716580)。
// 在這裡、在建置時檢查，舊版 GTK 才會帶著這個原因失敗，而不是在執行時只看到症狀。
#if !GTK_CHECK_VERSION(4, 22, 0)
#error "swift-cross-ui develop requires GTK 4.22 or newer; for GTK 4.14 (Ubuntu 24.04) use the Ubuntu-24-04-branch branch"
#endif

GtkWidget *wrapped_gtk_message_dialog_new() {
    #pragma clang diagnostic push
    #pragma clang diagnostic ignored "-Wdeprecated-declarations"
    return gtk_message_dialog_new(
        NULL,
        GTK_DIALOG_MODAL | GTK_DIALOG_DESTROY_WITH_PARENT,
        GTK_MESSAGE_INFO,
        GTK_BUTTONS_NONE,
        ""
    );
    #pragma clang diagnostic pop
}

GtkLabel *wrapped_gtk_widget_as_label(GtkWidget *widget) {
    if (widget == NULL || !GTK_IS_LABEL(widget)) {
        return NULL;
    }
    return GTK_LABEL(widget);
}

const GConnectFlags SHIM_G_CONNECT_AFTER = G_CONNECT_AFTER;
// Was `G_CONNECT_AFTER`, which is a different flag. Corrected 2026-09-11.
// Nothing reached it -- `ConnectFlags.swapped` in Signals.swift is an enum case
// with no caller -- so this changed no behaviour, which is exactly why it could
// sit here being wrong. A shim whose whole job is to carry one constant across
// the language boundary, carrying the wrong one, fails silently by
// construction: the call still connects, just not the way it was asked to.
// 原本寫的是 `G_CONNECT_AFTER`,那是另一個旗標。2026-09-11 更正。
// 沒有任何地方觸及它——Signals.swift 裡的 `ConnectFlags.swapped` 是一個沒有呼叫端的 enum case
// ——因此這次更正不改變任何行為;而那正是它得以在此處保持錯誤的原因。一個「唯一職責就是把某個常數
// 帶過語言邊界」的 shim,若帶錯了常數,其失敗方式在構造上就是沉默的:那個呼叫仍然會連接成功,
// 只是連接的方式與所要求的不同。
const GConnectFlags SHIM_G_CONNECT_SWAPPED = G_CONNECT_SWAPPED;
// `G_CONNECT_DEFAULT` is plain zero -- no AFTER, no SWAPPED -- and is what a
// signal wants when its handler is the mechanism rather than an addition to a
// default handler. GtkSignalListItemFactory's setup/bind/unbind are that case.
// `G_CONNECT_DEFAULT` 就是單純的零——不 AFTER、也不 SWAPPED——而當一個 signal 的 handler
// **本身就是那個機制**、而非附加在某個預設 handler 之後時,要的就是它。
// GtkSignalListItemFactory 的 setup/bind/unbind 正是這種情形。
const GConnectFlags SHIM_G_CONNECT_DEFAULT = G_CONNECT_DEFAULT;
const GApplicationFlags SHIM_G_APPLICATION_HANDLES_OPEN = G_APPLICATION_HANDLES_OPEN;

gboolean scui_primary_button_warps_slider(void) {
    gboolean warps = TRUE;
    g_object_get(gtk_settings_get_default(), "gtk-primary-button-warps-slider", &warps, NULL);
    return warps;
}

void scui_show_uri(const char *uri) {
#if GTK_CHECK_VERSION(4, 10, 0)
    // The GTask behind the launch holds its own reference to the launcher.
    // launch 背後的 GTask 自己持有 launcher 的參考。
    GtkUriLauncher *launcher = gtk_uri_launcher_new(uri);
    gtk_uri_launcher_launch(launcher, NULL, NULL, NULL, NULL);
    g_object_unref(launcher);
#else
    gtk_show_uri(NULL, uri, GDK_CURRENT_TIME);
#endif
}

void scui_css_provider_load(GtkCssProvider *provider, const char *data, gssize length) {
#if GTK_CHECK_VERSION(4, 12, 0)
    GBytes *bytes = g_bytes_new(data, (gsize)length);
    gtk_css_provider_load_from_bytes(provider, bytes);
    g_bytes_unref(bytes);
#else
    gtk_css_provider_load_from_data(provider, data, length);
#endif
}

GtkStyleContext *scui_widget_add_own_css_provider(GtkWidget *widget, GtkCssProvider *provider, guint priority) {
G_GNUC_BEGIN_IGNORE_DEPRECATIONS
    GtkStyleContext *context = gtk_widget_get_style_context(widget);
    gtk_style_context_add_provider(context, GTK_STYLE_PROVIDER(provider), priority);
G_GNUC_END_IGNORE_DEPRECATIONS
    g_object_ref(context);
    return context;
}

void scui_style_context_remove_own_css_provider(GtkStyleContext *context, GtkCssProvider *provider) {
G_GNUC_BEGIN_IGNORE_DEPRECATIONS
    gtk_style_context_remove_provider(context, GTK_STYLE_PROVIDER(provider));
G_GNUC_END_IGNORE_DEPRECATIONS
    g_object_unref(context);
}

void scui_calendar_set_date(GtkCalendar *calendar, GDateTime *date) {
#if GTK_CHECK_VERSION(4, 20, 0)
    gtk_calendar_set_date(calendar, date);
#else
    gtk_calendar_select_day(calendar, date);
#endif
}

void scui_dialog_add_button(GtkDialog *dialog, const char *label, int response_id) {
G_GNUC_BEGIN_IGNORE_DEPRECATIONS
    gtk_dialog_add_button(dialog, label, response_id);
G_GNUC_END_IGNORE_DEPRECATIONS
}

// ---------------------------------------------------------------------------
// contentShape(_:eoFill:)
//
// GTK picks the widget under the pointer by asking children before their
// parent, and a widget's `contains` vfunc decides only for the widget itself
// -- it cannot stop a child from being picked, and it is a class method, so a
// widget this backend did not subclass has none of ours. What does exclude a
// whole subtree from picking is `can-target`. So a shaped widget's
// `can-target` follows the pointer: an emission hook on GdkSurface::event,
// which runs before GTK's own handler and so before it picks, converts each
// pointer position into every shaped widget's coordinates on that surface and
// sets `can-target` to whether the point is inside the shape. The press that
// follows is then picked through to whatever is underneath.
//
// `allowsHitTesting(false)` also sets `can-target`, so it is recorded here and
// both are combined: a widget is targetable only when hit testing is allowed
// and the pointer is inside its shape.
//
// GTK 以「先問子元件、再問父元件」的方式挑選指標下的 widget,而 widget 的 `contains` vfunc 只替該 widget
// 自己作答——它無法阻止子元件被挑中，而且它是類別方法，本 backend 沒有建立 subclass 的 widget 就沒有我們的
// 版本。真正能把一整棵子樹排除在挑選之外的是 `can-target`。因此有形狀的 widget 的 `can-target` 跟隨指標：
// GdkSurface::event 上的 emission hook 在 GTK 自己的 handler 之前執行，也就在它挑選之前；它把每個指標位置
// 換算到該 surface 上每個有形狀 widget 的座標，並把 `can-target` 設為「該點是否在形狀內」。接下來的按壓便會
// 被挑選穿透到下方的東西。
//
// `allowsHitTesting(false)` 同樣設定 `can-target`,因此在此記錄並與之合併：只有在允許命中測試、且指標位於
// 形狀內時，widget 才可被當作目標。

typedef struct {
    double *points;
    int *counts;
    int contours;
    gboolean even_odd;
    gboolean inside;
} ScuiContentShape;

static GPtrArray *scui_shaped_widgets = NULL;
static gboolean scui_shape_hook_installed = FALSE;

static GQuark scui_shape_quark(void) {
    return g_quark_from_static_string("scui-content-shape");
}

static GQuark scui_hit_testing_disabled_quark(void) {
    return g_quark_from_static_string("scui-hit-testing-disabled");
}

static void scui_shape_free(gpointer data) {
    ScuiContentShape *shape = data;
    g_free(shape->points);
    g_free(shape->counts);
    g_free(shape);
}

// The same rule as HitRegion.contains in SwiftCrossUI, so every backend agrees.
// 與 SwiftCrossUI 的 HitRegion.contains 相同的規則，讓每個 backend 的答案一致。
static gboolean scui_shape_region_contains(const ScuiContentShape *shape, double x, double y) {
    int winding = 0;
    int crossings = 0;
    const double *contour = shape->points;
    for (int c = 0; c < shape->contours; c++) {
        int count = shape->counts[c];
        if (count >= 3) {
            double px = contour[2 * (count - 1)];
            double py = contour[2 * (count - 1) + 1];
            for (int i = 0; i < count; i++) {
                double cx = contour[2 * i];
                double cy = contour[2 * i + 1];
                if ((py <= y) != (cy <= y)) {
                    double t = (y - py) / (cy - py);
                    if (px + t * (cx - px) > x) {
                        crossings++;
                        winding += cy > py ? 1 : -1;
                    }
                }
                px = cx;
                py = cy;
            }
        }
        contour += 2 * count;
    }
    return shape->even_odd ? (crossings % 2 == 1) : (winding != 0);
}

static void scui_shape_apply_can_target(GtkWidget *widget, gboolean inside) {
    gboolean disabled = GPOINTER_TO_INT(
        g_object_get_qdata(G_OBJECT(widget), scui_hit_testing_disabled_quark()));
    gboolean target = !disabled && inside;
    if (gtk_widget_get_can_target(widget) != target) {
        gtk_widget_set_can_target(widget, target);
    }
}

// A button press with no pointer move before it.
//
// GTK sends a button press to the pointer focus it picked at the last motion or
// crossing; it does not pick again at the press (handle_pointing_event in
// gtkmain.c). A shaped widget's `can-target` is updated for the press position
// above, but too late for that press if the pointer got there without a
// motion -- a touchscreen promoted to a mouse, a synthesised click, a layout or
// shape change under a still pointer. GTK has no public way to re-pick nor to
// make an event, so the hook works out both targets itself:
//
// - after every motion and crossing it records the widget GTK is about to pick
//   (the same `gtk_widget_pick`, run after `can-target` was updated, so it is
//   GTK's answer), and
// - at a press it picks again at the press position. If the two differ, the
//   press is misdirected: until its button is released, this backend's gesture
//   handlers that are not on the fresh target's chain refuse it
//   (scui_content_shape_press_reaches), and the press, the motions and the
//   release are handed to the press forwarder, which runs the gestures of the
//   widgets on the fresh target's chain that GTK will not deliver to.
//
// 沒有先移動指標就按下的按鍵。
//
// GTK 把按鍵按下送往它在上一次移動或 crossing 時挑選的 pointer focus;按下時並不重新挑選(gtkmain.c 的
// handle_pointing_event)。上方已依按下的位置更新有形狀 widget 的 `can-target`,但若指標是在沒有移動事件的
// 情況下抵達該處——觸控螢幕被提升為滑鼠、合成的點擊、指標靜止時版面或形狀改變——對這次按下就已太遲。GTK
// 沒有公開的方式重新挑選，也無法建立事件，因此 hook 自己算出兩個目標：
//
// - 每次移動與 crossing 之後，記錄 GTK 即將挑中的 widget(同一個 `gtk_widget_pick`,在 `can-target` 更新後
//   執行，所以就是 GTK 的答案);
// - 按下時在按下的位置重新挑選。兩者不同時，這次按下就是被送錯的：直到該按鍵放開為止，本 backend 不在新
//   目標鏈上的手勢 handler 都拒絕它(scui_content_shape_press_reaches),而按下、移動與放開都交給 press
//   forwarder,由它執行新目標鏈上那些 GTK 不會送達之 widget 的手勢。

typedef struct {
    GWeakRef pick;
    gboolean known;
} ScuiNativePick;

static GQuark scui_native_pick_quark(void) {
    return g_quark_from_static_string("scui-content-shape-native-pick");
}

static void scui_native_pick_free(gpointer data) {
    ScuiNativePick *record = data;
    g_weak_ref_clear(&record->pick);
    g_free(record);
}

static ScuiNativePick *scui_native_pick_record(GtkWidget *native) {
    ScuiNativePick *record = g_object_get_qdata(G_OBJECT(native), scui_native_pick_quark());
    if (record == NULL) {
        record = g_new0(ScuiNativePick, 1);
        g_weak_ref_init(&record->pick, NULL);
        g_object_set_qdata_full(
            G_OBJECT(native), scui_native_pick_quark(), record, scui_native_pick_free);
    }
    return record;
}

// Zero-filled statics are valid empty GWeakRefs. / 以零填滿的 static 即是有效的空 GWeakRef。
static GWeakRef scui_misdirected_fresh;
static GWeakRef scui_misdirected_stale;
static GWeakRef scui_misdirected_native;
static gboolean scui_misdirected_active = FALSE;
static guint scui_misdirected_button = 0;
static ScuiPressForwarder scui_press_forwarder = NULL;

void scui_content_shape_set_press_forwarder(ScuiPressForwarder forwarder) {
    scui_press_forwarder = forwarder;
}

gboolean scui_content_shape_press_reaches(GtkWidget *widget) {
    if (!scui_misdirected_active || widget == NULL) {
        return TRUE;
    }
    GtkWidget *fresh = g_weak_ref_get(&scui_misdirected_fresh);
    gboolean reaches = fresh != NULL && (fresh == widget || gtk_widget_is_ancestor(fresh, widget));
    if (fresh != NULL) {
        g_object_unref(fresh);
    }
    return reaches;
}

static void scui_forward(int phase, GtkWidget *native, double nx, double ny) {
    GtkWidget *fresh = g_weak_ref_get(&scui_misdirected_fresh);
    GtkWidget *stale = g_weak_ref_get(&scui_misdirected_stale);
    if (fresh != NULL && scui_press_forwarder != NULL) {
        graphene_point_t point = GRAPHENE_POINT_INIT((float)nx, (float)ny);
        graphene_point_t local;
        if (gtk_widget_compute_point(native, fresh, &point, &local)) {
            scui_press_forwarder(fresh, stale, phase, scui_misdirected_button, local.x, local.y);
        }
    }
    if (fresh != NULL) {
        g_object_unref(fresh);
    }
    if (stale != NULL) {
        g_object_unref(stale);
    }
}

static void scui_misdirected_clear(void) {
    scui_misdirected_active = FALSE;
    scui_misdirected_button = 0;
    g_weak_ref_set(&scui_misdirected_fresh, NULL);
    g_weak_ref_set(&scui_misdirected_stale, NULL);
    g_weak_ref_set(&scui_misdirected_native, NULL);
}

static const GdkModifierType scui_button_masks =
    GDK_BUTTON1_MASK | GDK_BUTTON2_MASK | GDK_BUTTON3_MASK | GDK_BUTTON4_MASK | GDK_BUTTON5_MASK;

static gboolean scui_shape_surface_event_hook(
    GSignalInvocationHint *hint, guint n_params, const GValue *params, gpointer data
) {
    (void)hint;
    (void)data;
    if (scui_shaped_widgets == NULL || scui_shaped_widgets->len == 0 || n_params < 2) {
        return TRUE;
    }
    GdkSurface *surface = g_value_get_object(&params[0]);
    GdkEvent *event = g_value_peek_pointer(&params[1]);
    if (surface == NULL || event == NULL) {
        return TRUE;
    }
    GdkEventType type = gdk_event_get_event_type(event);
    switch (type) {
        case GDK_MOTION_NOTIFY:
        case GDK_BUTTON_PRESS:
        case GDK_BUTTON_RELEASE:
        case GDK_ENTER_NOTIFY:
        case GDK_TOUCH_BEGIN:
        case GDK_TOUCH_UPDATE:
        // A drag over the window is picked afresh at every motion too, so a
        // drop target follows its shape. / 拖放經過視窗時每次移動也都重新挑選，讓拖放目標依循形狀。
        case GDK_DRAG_ENTER:
        case GDK_DRAG_MOTION:
        case GDK_DROP_START:
            break;
        default:
            return TRUE;
    }
    double x, y;
    if (!gdk_event_get_position(event, &x, &y)) {
        return TRUE;
    }
    GtkNative *native = gtk_native_get_for_surface(surface);
    if (native == NULL) {
        return TRUE;
    }
    // Surface to native-widget coordinates, the conversion GTK makes before it
    // picks. / 由 surface 座標換算到 native widget 座標，與 GTK 挑選前所做的換算相同。
    double nx, ny;
    gtk_native_get_surface_transform(native, &nx, &ny);
    graphene_point_t point = GRAPHENE_POINT_INIT((float)(x - nx), (float)(y - ny));
    for (guint i = 0; i < scui_shaped_widgets->len; i++) {
        GtkWidget *widget = g_ptr_array_index(scui_shaped_widgets, i);
        if (gtk_widget_get_native(widget) != native) {
            continue;
        }
        ScuiContentShape *shape = g_object_get_qdata(G_OBJECT(widget), scui_shape_quark());
        graphene_point_t local;
        if (shape == NULL
            || !gtk_widget_compute_point(GTK_WIDGET(native), widget, &point, &local)) {
            continue;
        }
        shape->inside = scui_shape_region_contains(shape, local.x, local.y);
        scui_shape_apply_can_target(widget, shape->inside);
    }

    // What GTK picks, and whether a press goes where it is seen; see above.
    // GTK 挑選的對象，以及按下是否送往看得見的地方；見上方。
    GtkWidget *native_widget = GTK_WIDGET(native);
    GdkModifierType held = gdk_event_get_modifier_state(event) & scui_button_masks;
    ScuiNativePick *record = scui_native_pick_record(native_widget);
    switch (type) {
        case GDK_MOTION_NOTIFY:
        case GDK_ENTER_NOTIFY:
            if (scui_misdirected_active && type == GDK_MOTION_NOTIFY) {
                GtkWidget *forwarded = g_weak_ref_get(&scui_misdirected_native);
                if (forwarded == native_widget) {
                    scui_forward(SCUI_PRESS_MOTION, native_widget, point.x, point.y);
                }
                if (forwarded != NULL) {
                    g_object_unref(forwarded);
                }
            }
            // Under an implicit grab GTK keeps its target; it picks again only
            // with no button held. / 在隱式 grab 之下 GTK 保留其目標；只有沒有按住按鍵時才重新挑選。
            if (held == 0) {
                GtkWidget *pick = gtk_widget_pick(native_widget, point.x, point.y, GTK_PICK_DEFAULT);
                g_weak_ref_set(&record->pick, pick != NULL ? pick : native_widget);
                record->known = TRUE;
            }
            break;
        case GDK_BUTTON_PRESS: {
            // A press with another button held goes to the grab, and one while a
            // misdirected press is still down is part of it.
            // 按住其他按鍵時的按下會送往 grab;被送錯的按下尚未放開時的按下則屬於它。
            if (held != 0 || scui_misdirected_active || !record->known) {
                break;
            }
            GtkWidget *fresh = gtk_widget_pick(native_widget, point.x, point.y, GTK_PICK_DEFAULT);
            if (fresh == NULL) {
                fresh = native_widget;
            }
            GtkWidget *stale = g_weak_ref_get(&record->pick);
            // An unknown target (destroyed since) is left to GTK.
            // 未知的目標(之後已被銷毀)交給 GTK 處理。
            if (stale != NULL && stale != fresh) {
                scui_misdirected_active = TRUE;
                scui_misdirected_button = gdk_button_event_get_button(event);
                g_weak_ref_set(&scui_misdirected_fresh, fresh);
                g_weak_ref_set(&scui_misdirected_stale, stale);
                g_weak_ref_set(&scui_misdirected_native, native_widget);
                scui_forward(SCUI_PRESS_PRESSED, native_widget, point.x, point.y);
            }
            if (stale != NULL) {
                g_object_unref(stale);
            }
            break;
        }
        case GDK_BUTTON_RELEASE:
            if (scui_misdirected_active
                && gdk_button_event_get_button(event) == scui_misdirected_button) {
                scui_forward(SCUI_PRESS_RELEASED, native_widget, point.x, point.y);
                scui_misdirected_clear();
            }
            // GTK picks again at a release of the only button held.
            // 放開唯一按住的按鍵時，GTK 會重新挑選。
            if (held != 0 && (held & (held - 1)) == 0) {
                GtkWidget *pick = gtk_widget_pick(native_widget, point.x, point.y, GTK_PICK_DEFAULT);
                g_weak_ref_set(&record->pick, pick != NULL ? pick : native_widget);
                record->known = TRUE;
            }
            break;
        default:
            break;
    }
    return TRUE;
}

static void scui_shape_widget_finalized(gpointer data, GObject *where_the_object_was) {
    (void)data;
    if (scui_shaped_widgets != NULL) {
        g_ptr_array_remove(scui_shaped_widgets, where_the_object_was);
    }
}

void scui_content_shape_set(
    GtkWidget *widget, const double *points, const int *counts, int contours, gboolean even_odd
) {
    if (widget == NULL) {
        return;
    }
    if (scui_shaped_widgets == NULL) {
        scui_shaped_widgets = g_ptr_array_new();
    }
    gboolean listed = g_ptr_array_find(scui_shaped_widgets, widget, NULL);

    if (contours < 0) {
        if (listed) {
            g_ptr_array_remove(scui_shaped_widgets, widget);
            g_object_weak_unref(G_OBJECT(widget), scui_shape_widget_finalized, NULL);
        }
        g_object_set_qdata(G_OBJECT(widget), scui_shape_quark(), NULL);
        scui_shape_apply_can_target(widget, TRUE);
        return;
    }

    if (!scui_shape_hook_installed) {
        // The class has to exist before its signal can be looked up.
        // 必須先有該類別，才能查到它的訊號。
        gpointer klass = g_type_class_ref(GDK_TYPE_SURFACE);
        guint signal_id = g_signal_lookup("event", GDK_TYPE_SURFACE);
        if (signal_id != 0) {
            g_signal_add_emission_hook(signal_id, 0, scui_shape_surface_event_hook, NULL, NULL);
            scui_shape_hook_installed = TRUE;
        }
        g_type_class_unref(klass);
    }

    int total = 0;
    for (int c = 0; c < contours; c++) {
        total += counts[c];
    }
    ScuiContentShape *old = g_object_get_qdata(G_OBJECT(widget), scui_shape_quark());
    ScuiContentShape *shape = g_new0(ScuiContentShape, 1);
    shape->points = g_memdup2(points, sizeof(double) * 2 * (gsize)total);
    shape->counts = g_memdup2(counts, sizeof(int) * (gsize)contours);
    shape->contours = contours;
    shape->even_odd = even_odd;
    // Until the pointer moves, keep whatever the last move decided.
    // 在指標移動之前，沿用上一次移動所決定的結果。
    shape->inside = old != NULL ? old->inside : TRUE;
    g_object_set_qdata_full(G_OBJECT(widget), scui_shape_quark(), shape, scui_shape_free);

    if (!listed) {
        g_ptr_array_add(scui_shaped_widgets, widget);
        g_object_weak_ref(G_OBJECT(widget), scui_shape_widget_finalized, NULL);
    }
}

gboolean scui_content_shape_contains(GtkWidget *widget, double x, double y) {
    if (widget == NULL) {
        return TRUE;
    }
    ScuiContentShape *shape = g_object_get_qdata(G_OBJECT(widget), scui_shape_quark());
    return shape == NULL || scui_shape_region_contains(shape, x, y);
}

void scui_content_shape_set_hit_testing(GtkWidget *widget, gboolean allows) {
    if (widget == NULL) {
        return;
    }
    g_object_set_qdata(
        G_OBJECT(widget), scui_hit_testing_disabled_quark(), GINT_TO_POINTER(!allows));
    ScuiContentShape *shape = g_object_get_qdata(G_OBJECT(widget), scui_shape_quark());
    scui_shape_apply_can_target(widget, shape == NULL || shape->inside);
}
