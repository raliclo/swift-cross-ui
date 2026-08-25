// See gtk_helpers.h for why this exists: a plain GtkFixed over-allocates to its
// children, so overflow: hidden clips to the wrong (larger) box. This subclass
// measures to its own size request and clips in snapshot, so an oversized child
// is cut to the frame it was given (#389).
#include "gtk_helpers.h"

#define GTK_TYPE_SCUI_CLIP_FIXED (scui_clip_fixed_get_type())

typedef struct _ScuiClipFixed {
    GtkFixed parent_instance;
} ScuiClipFixed;

typedef struct _ScuiClipFixedClass {
    GtkFixedClass parent_class;
} ScuiClipFixedClass;

G_DEFINE_TYPE(ScuiClipFixed, scui_clip_fixed, GTK_TYPE_FIXED)

// Report the size request as the minimum and natural size, so the parent
// allocates the frame rather than the child's larger bounds.
static void scui_clip_fixed_measure(
    GtkWidget *widget,
    GtkOrientation orientation,
    int for_size,
    int *minimum,
    int *natural,
    int *minimum_baseline,
    int *natural_baseline
) {
    (void)for_size;
    int req_width = -1, req_height = -1;
    gtk_widget_get_size_request(widget, &req_width, &req_height);
    int value = (orientation == GTK_ORIENTATION_HORIZONTAL) ? req_width : req_height;
    if (value < 0) {
        value = 0;
    }
    *minimum = value;
    *natural = value;
    *minimum_baseline = -1;
    *natural_baseline = -1;
}

// Clip children to the size request -- the frame SwiftCrossUI decided -- rather
// than the allocation. In this backend the two can differ: the parent hands this
// widget a taller allocation than requested, and clipping to that would let the
// child spill exactly as far as the wrong number allows. The request is the
// frame the clip is meant to enforce.
static void scui_clip_fixed_snapshot(GtkWidget *widget, GtkSnapshot *snapshot) {
    int req_width = -1, req_height = -1;
    gtk_widget_get_size_request(widget, &req_width, &req_height);
    float width = req_width > 0 ? (float)req_width : (float)gtk_widget_get_width(widget);
    float height = req_height > 0 ? (float)req_height : (float)gtk_widget_get_height(widget);
    graphene_rect_t bounds = GRAPHENE_RECT_INIT(0.0f, 0.0f, width, height);
    gtk_snapshot_push_clip(snapshot, &bounds);
    GTK_WIDGET_CLASS(scui_clip_fixed_parent_class)->snapshot(widget, snapshot);
    gtk_snapshot_pop(snapshot);
}

static void scui_clip_fixed_class_init(ScuiClipFixedClass *klass) {
    GTK_WIDGET_CLASS(klass)->measure = scui_clip_fixed_measure;
    GTK_WIDGET_CLASS(klass)->snapshot = scui_clip_fixed_snapshot;
}

static void scui_clip_fixed_init(ScuiClipFixed *self) {
    gtk_widget_set_overflow(GTK_WIDGET(self), GTK_OVERFLOW_HIDDEN);
}

GtkWidget *scui_clip_fixed_new(void) {
    return g_object_new(GTK_TYPE_SCUI_CLIP_FIXED, NULL);
}
