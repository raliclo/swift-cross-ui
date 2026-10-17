import CGtk

/// `GtkFixed` places its child widgets at fixed positions and with fixed sizes.
///
/// `GtkFixed` performs no automatic layout management.
///
/// For most applications, you should not use this container! It keeps
/// you from having to learn about the other GTK containers, but it
/// results in broken applications.  With `GtkFixed`, the following
/// things will result in truncated text, overlapping widgets, and
/// other display bugs:
///
/// - Themes, which may change widget sizes.
///
/// - Fonts other than the one you used to write the app will of course
/// change the size of widgets containing text; keep in mind that
/// users may use a larger font because of difficulty reading the
/// default, or they may be using a different OS that provides different fonts.
///
/// - Translation of text into other languages changes its size. Also,
/// display of non-English text will use a different font in many
/// cases.
///
/// In addition, `GtkFixed` does not pay attention to text direction and
/// thus may produce unwanted results if your app is run under right-to-left
/// languages such as Hebrew or Arabic. That is: normally GTK will order
/// containers appropriately for the text direction, e.g. to put labels to
/// the right of the thing they label when using an RTL language, but it can’t
/// do that with `GtkFixed`. So if you need to reorder widgets depending on
/// the text direction, you would need to manually detect it and adjust child
/// positions accordingly.
///
/// Finally, fixed positioning makes it kind of annoying to add/remove
/// UI elements, since you have to reposition all the other elements. This
/// is a long-term maintenance problem for your application.
///
/// If you know none of these things are an issue for your application,
/// and prefer the simplicity of `GtkFixed`, by all means use the
/// widget. But you should be aware of the tradeoffs.
open class Fixed: Widget {
    public var children: [Widget] = []

    /// Creates a new `GtkFixed`.
    public init() {
        super.init(gtk_fixed_new())
    }

    /// Wraps an existing `GtkFixed`, or one of a type derived from it.
    ///
    /// Exposed so that a subclass can supply its own instance. `Fixed`
    /// previously declared `init()` as a designated initialiser, which stopped
    /// `GObject`'s pointer-taking ones from being inherited, so a subclass had
    /// no way to hand up the widget it created.
    public override init<T>(_ pointer: UnsafeMutablePointer<T>?) {
        super.init(pointer)
    }

    /// Each child's layout position, and the matrix it is drawn under when it has
    /// one -- see ``setChildMatrix(_:_:)``.
    /// 每個子元件的排版位置，以及它被畫在其下的矩陣(若有)——見 ``setChildMatrix(_:_:)``。
    private var childPositions: [ObjectIdentifier: (x: Double, y: Double)] = [:]
    private var childMatrices: [ObjectIdentifier: [Double]] = [:]

    public func put(_ child: Widget, x: Double, y: Double) {
        gtk_fixed_put(castedPointer(), child.widgetPointer, x, y)
        childPositions[ObjectIdentifier(child)] = (x, y)
        childMatrices[ObjectIdentifier(child)] = nil
        children.append(child)
        child.parentWidget = self
    }

    public func put(_ child: Widget, index: Int, x: Double, y: Double) {
        gtk_fixed_put(castedPointer(), child.widgetPointer, x, y)
        childPositions[ObjectIdentifier(child)] = (x, y)
        childMatrices[ObjectIdentifier(child)] = nil
        children.insert(child, at: index)
        child.parentWidget = self
    }

    /// Moves `child`, keeping the matrix it is drawn under, if any.
    /// 移動 `child`,並保留它被畫在其下的矩陣(若有)。
    public func move(_ child: Widget, x: Double, y: Double) {
        let id = ObjectIdentifier(child)
        childPositions[id] = (x, y)
        if let matrix = childMatrices[id] {
            setChildTransform(child, x: x, y: y, matrix: matrix)
        } else {
            gtk_fixed_move(castedPointer(), child.widgetPointer, x, y)
        }
    }

    /// Draws `child` at its position under `matrix` -- (a, b, c, d, tx, ty), CSS
    /// `matrix()` order, about the child's top left -- or plainly for `nil`.
    ///
    /// The child transform GtkFixed already uses for positions, so hit testing
    /// follows the drawing as it does for CSS `transform`, without the style
    /// recalculation a CSS change costs: P96 on macOS, 66 offsets per frame, spent
    /// most of each frame in gtk_css_node_validate and drew 28 fps (2026-10-17).
    ///
    /// 在 `child` 的位置以 `matrix` 繪製它——(a, b, c, d, tx, ty),CSS `matrix()` 的順序，以子元件左上角為準
    /// ——`nil` 則照常繪製。用的是 GtkFixed 本來就拿來放位置的 child transform,所以 hit testing 與 CSS
    /// `transform` 一樣跟著繪製走，卻不必付 CSS 改變的樣式重算：macOS 上的 P96 每幀 66 個 offset,大半時間
    /// 花在 gtk_css_node_validate,只有 28 fps(2026-10-17)。
    public func setChildMatrix(_ child: Widget, _ matrix: [Double]?) {
        let id = ObjectIdentifier(child)
        if matrix == nil, childMatrices[id] == nil {
            return
        }
        childMatrices[id] = matrix
        let position = childPositions[id] ?? (0, 0)
        if let matrix {
            setChildTransform(child, x: position.x, y: position.y, matrix: matrix)
        } else {
            gtk_fixed_move(castedPointer(), child.widgetPointer, position.x, position.y)
        }
    }

    private func setChildTransform(_ child: Widget, x: Double, y: Double, matrix m: [Double]) {
        var point = graphene_point_t(x: Float(x), y: Float(y))
        var matrix = graphene_matrix_t()
        graphene_matrix_init_from_2d(&matrix, m[0], m[1], m[2], m[3], m[4], m[5])
        let transform = gsk_transform_matrix(gsk_transform_translate(nil, &point), &matrix)
        gtk_fixed_set_child_transform(castedPointer(), child.widgetPointer, transform)
        gsk_transform_unref(transform)
    }

    public func remove(_ child: Widget) {
        if let index = children.firstIndex(where: { $0 === child }) {
            gtk_fixed_remove(castedPointer(), child.widgetPointer)
            childPositions[ObjectIdentifier(child)] = nil
            childMatrices[ObjectIdentifier(child)] = nil
            children.remove(at: index)
            child.parentWidget = nil
        }
    }

    public func removeAllChildren() {
        for child in children {
            gtk_fixed_remove(castedPointer(), child.widgetPointer)
            child.parentWidget = nil
        }
        children = []
        childPositions = [:]
        childMatrices = [:]
    }
}
