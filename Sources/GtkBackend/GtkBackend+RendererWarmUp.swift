#if os(Windows) || os(Linux)
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
        ///
        /// Linux too since 2026-10-23. Under WSLg the NVIDIA driver behind Mesa's
        /// d3d12 compiles every shader again in each process (perf: 17% of P96's
        /// samples in libnvidia-gpucomp, 29% in Mesa, whose own disk cache already
        /// holds them), and P96's first moving frame waited 870 ms for it. With
        /// this warm-up, which now also draws a filled and a stroked path and a
        /// transformed fill, it waits about 560 ms, and P96 draws 48.3-49.0 fps in
        /// its first 3 s against 41.0-41.7 without (interleaved, two rounds).
        /// 自 2026-10-23 起 Linux 也執行。WSLg 下，Mesa d3d12 背後的 NVIDIA 驅動在每個行程都重新編譯每個 shader(perf:
        /// P96 的取樣有 17% 在 libnvidia-gpucomp、29% 在 Mesa,而 Mesa 自己的磁碟快取早已存有它們),P96 第一個移動的幀為此
        /// 等了 870 毫秒。有了本預熱(現在也畫一條填色路徑、一條描邊路徑與一個變換後的填色)後約等 560 毫秒，P96 前 3 秒
        /// 為 48.3–49.0 fps,不預熱為 41.0–41.7(交錯量測兩輪)。
        func warmUpRenderer(of window: Gtk.Window) {
            guard ProcessInfo.processInfo.environment["SCUI_GTK_WARMUP"] != "0" else { return }
            // A window of its own, never `window`: realizing the app's window this
            // early fixed things GTK decides at realization. P92 on Windows GTK had
            // no menu bar from this function's first version (d93cd3ce,
            // 2026-10-21) until 2026-10-23 and passed with SCUI_GTK_WARMUP=0;
            // unrealizing the window afterwards brought the menu bar back but lost
            // GTK's own title bar. The programs are kept for the display, so a
            // throwaway window warms the app's as well.
            // 用自己的視窗，絕不用 `window`:這麼早 realize app 的視窗，會把 GTK 在 realize 時決定的事定下來。Windows GTK
            // 上的 P92 從本函式第一版(d93cd3ce,2026-10-21)到 2026-10-23 都沒有選單列，加上 SCUI_GTK_WARMUP=0 則通過;
            // 事後 unrealize 視窗能讓選單列回來，卻失去 GTK 自己的標題列。程式依 display 保存，所以用完即丟的視窗也能
            // 替 app 的視窗預熱。
            _ = window
            guard let probe = gtk_window_new() else { return }
            defer { gtk_window_destroy(UnsafeMutableRawPointer(probe).assumingMemoryBound(to: GtkWindow.self)) }
            gtk_widget_realize(probe)
            guard let native = gtk_widget_get_native(probe),
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
            let layout = gtk_widget_create_pango_layout(probe, "Ag 0.1")
            gtk_snapshot_append_layout(snapshot, layout, &grey)
            g_object_unref(UnsafeMutableRawPointer(layout))

            // A filled and a stroked path, as GtkBackend draws every Shape since
            // f84ee359, and a fill under the transform Fixed.setChildMatrix builds.
            // 填色與描邊的路徑(自 f84ee359 起 GtkBackend 以此繪製每個 Shape),以及 Fixed.setChildMatrix
            // 所建變換下的填色。
            let builder = gsk_path_builder_new()
            gsk_path_builder_add_rect(builder, &bounds)
            var centre = graphene_point_t(x: 32, y: 32)
            gsk_path_builder_add_circle(builder, &centre, 20)
            if let path = gsk_path_builder_free_to_path(builder) {
                gtk_snapshot_append_fill(snapshot, path, GSK_FILL_RULE_WINDING, &grey)
                let stroke = gsk_stroke_new(2)
                gtk_snapshot_append_stroke(snapshot, path, stroke, &grey)
                gsk_stroke_free(stroke)
                gsk_path_unref(path)
            }
            var offset = graphene_point_t(x: 3.5, y: 2.25)
            var matrix = graphene_matrix_t()
            graphene_matrix_init_from_2d(&matrix, 0.866, 0.5, -0.5, 0.866, 0, 0)
            let transform = gsk_transform_matrix(gsk_transform_translate(nil, &offset), &matrix)
            gtk_snapshot_save(snapshot)
            gtk_snapshot_transform(snapshot, transform)
            gtk_snapshot_append_color(snapshot, &grey, &bounds)
            gtk_snapshot_restore(snapshot)
            gsk_transform_unref(transform)

            guard let node = gtk_snapshot_free_to_node(snapshot) else { return }
            defer { gsk_render_node_unref(node) }
            if let texture = gsk_renderer_render_texture(renderer, node, nil) {
                g_object_unref(UnsafeMutableRawPointer(texture))
            }
        }
    }
#endif
