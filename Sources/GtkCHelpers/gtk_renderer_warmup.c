// The path part of GtkBackend's renderer warm-up (GtkBackend+RendererWarmUp.swift).
//
// In C, not Swift, for the version guard: GskPath, gtk_snapshot_append_fill and
// gtk_snapshot_append_stroke are GTK 4.14 API, and Swift cannot ask
// GTK_CHECK_VERSION. Called from Swift directly they were a compile error on
// any GTK before 4.14 (Ubuntu 22.04 ships 4.6, Debian 12 4.8) rather than a
// warm-up with no paths in it (review, 2026-10-29). The rest of the project
// guards GskPath the same way; see gtk_passthrough_drawing_area.c.
//
// GtkBackend renderer 預熱中的路徑部分(GtkBackend+RendererWarmUp.swift)。
//
// 寫成 C 而不是 Swift,是為了版本保護:GskPath、gtk_snapshot_append_fill 與 gtk_snapshot_append_stroke
// 是 GTK 4.14 的 API,而 Swift 問不了 GTK_CHECK_VERSION。直接從 Swift 呼叫時，任何 4.14 之前的 GTK
// (Ubuntu 22.04 附 4.6、Debian 12 附 4.8)都會編譯失敗，而不是一次不含路徑的預熱(審查,2026-10-29)。
// 專案其他地方也以同樣方式保護 GskPath;見 gtk_passthrough_drawing_area.c。

#include "include/gtk_helpers.h"

void scui_snapshot_append_warmup_paths(
    GtkSnapshot *snapshot, const graphene_rect_t *bounds, const GdkRGBA *color
) {
#if GTK_CHECK_VERSION(4, 14, 0)
    GskPathBuilder *builder = gsk_path_builder_new();
    gsk_path_builder_add_rect(builder, bounds);
    graphene_point_t centre = GRAPHENE_POINT_INIT(
        bounds->origin.x + bounds->size.width / 2, bounds->origin.y + bounds->size.height / 2
    );
    // 20 points across the 64-point warm-up square, as when this was Swift.
    // 在 64 點的預熱方塊中為 20 點，與寫在 Swift 時相同。
    gsk_path_builder_add_circle(
        builder, &centre, MIN(bounds->size.width, bounds->size.height) * 20.0f / 64.0f
    );
    GskPath *path = gsk_path_builder_free_to_path(builder);
    gtk_snapshot_append_fill(snapshot, path, GSK_FILL_RULE_WINDING, color);
    GskStroke *stroke = gsk_stroke_new(2);
    gtk_snapshot_append_stroke(snapshot, path, stroke, color);
    gsk_stroke_free(stroke);
    gsk_path_unref(path);
#else
    (void)snapshot;
    (void)bounds;
    (void)color;
#endif
}
