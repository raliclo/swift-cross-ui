#if os(Windows)
    import CGtk
    import Foundation
    import Gtk

    extension GtkBackend {
        /// Realizes a new window and draws one small offscreen frame with its
        /// renderer, before the window's content exists.
        ///
        /// On Windows a GPU renderer (GL, NGL or Vulkan alike) spends about 0.2 s
        /// of the main thread on its first frame, compiling the programs it
        /// draws with. That frame comes after `onAppear`, so an animation started
        /// there loses its first quarter second: P97 sampled nothing before
        /// 0.39-0.45 s and its speed(2) row jumped, where WSLg (Mesa keeps a
        /// shader cache on disk) starts at 0.16 and `GSK_RENDERER=cairo` at
        /// 0.17-0.19. Measured 2026-10-21, interleaved, three rounds: realizing
        /// alone took 15-30 ms and moved the start to 0.36-0.38; drawing one
        /// frame of the common node types here took 155-187 ms (750 ms on an
        /// exe's very first launch) and moved it to 0.19 with no jumps. The cost
        /// is not new, only paid before the content appears instead of after.
        /// The programs are kept per GL context, which the display shares, so a
        /// later window pays almost nothing. `SCUI_GTK_WARMUP=0` turns it off,
        /// for measuring.
        ///
        /// 在視窗內容存在之前，先 realize 新視窗，並以它的 renderer 在螢幕外畫一小幀。Windows 上的 GPU renderer
        /// (GL、NGL、Vulkan 皆然)第一幀要花約 0.2 秒主執行緒時間編譯它用來繪製的程式。那一幀在 `onAppear`
        /// 之後，因此在那裡開始的動畫會失去最初的四分之一秒:P97 在 0.39–0.45 秒前取不到樣本、speed(2) 那列出現
        /// 跳躍;WSLg(Mesa 在磁碟上保留 shader 快取)從 0.16 開始,`GSK_RENDERER=cairo` 則是 0.17–0.19。2026-10-21
        /// 交錯量測三輪：只 realize 花 15–30 毫秒，起點移到 0.36–0.38;在此畫一幀常見節點花 155–187 毫秒(exe 第一次
        /// 啟動時 750 毫秒),起點移到 0.19 且沒有跳躍。成本不是新增的，只是改在內容出現之前付。程式依 GL context
        /// 保存，而 display 共用該 context,所以之後的視窗幾乎不花成本。`SCUI_GTK_WARMUP=0` 可關閉，供量測用。
        func warmUpRenderer(of window: Gtk.Window) {
            guard ProcessInfo.processInfo.environment["SCUI_GTK_WARMUP"] != "0" else { return }
            gtk_widget_realize(window.widgetPointer)
            guard let native = gtk_widget_get_native(window.widgetPointer),
                let renderer = gtk_native_get_renderer(native)
            else { return }

            // One of each node a typical first frame draws: fills, a rounded
            // clip, a gradient, a border, a shadow and text.
            // 典型第一幀會畫的節點各一個：填色、圓角裁切、漸層、邊框、陰影與文字。
            let snapshot = gtk_snapshot_new()
            var bounds = graphene_rect_t(
                origin: graphene_point_t(x: 0, y: 0),
                size: graphene_size_t(width: 64, height: 64)
            )
            var grey = GdkRGBA(red: 0.5, green: 0.5, blue: 0.5, alpha: 0.5)
            gtk_snapshot_append_color(snapshot, &grey, &bounds)
            var rounded = GskRoundedRect()
            gsk_rounded_rect_init_from_rect(&rounded, &bounds, 8)
            gtk_snapshot_push_rounded_clip(snapshot, &rounded)
            gtk_snapshot_append_color(snapshot, &grey, &bounds)
            gtk_snapshot_pop(snapshot)
            var stops = [
                GskColorStop(offset: 0, color: grey),
                GskColorStop(offset: 1, color: GdkRGBA(red: 1, green: 0, blue: 0, alpha: 1)),
            ]
            var start = graphene_point_t(x: 0, y: 0)
            var end = graphene_point_t(x: 64, y: 0)
            gtk_snapshot_append_linear_gradient(snapshot, &bounds, &start, &end, &stops, 2)
            var widths: [Float] = [1, 1, 1, 1]
            var colors = [grey, grey, grey, grey]
            gtk_snapshot_append_border(snapshot, &rounded, &widths, &colors)
            gtk_snapshot_append_outset_shadow(snapshot, &rounded, &grey, 0, 2, 0, 4)
            let layout = gtk_widget_create_pango_layout(window.widgetPointer, "Ag 0.1")
            gtk_snapshot_append_layout(snapshot, layout, &grey)
            g_object_unref(UnsafeMutableRawPointer(layout))

            guard let node = gtk_snapshot_free_to_node(snapshot) else { return }
            defer { gsk_render_node_unref(node) }
            if let texture = gsk_renderer_render_texture(renderer, node, nil) {
                g_object_unref(UnsafeMutableRawPointer(texture))
            }
        }
    }
#endif
