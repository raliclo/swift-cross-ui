import CGtk

public class ToggleButton: Button {
    public convenience init() {
        self.init(
            gtk_toggle_button_new()
        )
    }

    public convenience init(label: String) {
        self.init(
            gtk_toggle_button_new_with_label(label)
        )
    }

    public convenience init(mnemonic label: String) {
        self.init(
            gtk_toggle_button_new_with_mnemonic(label)
        )
    }

    open override func didMoveToParent() {
        super.didMoveToParent()

        addSignal(name: "toggled") { [weak self] in
            guard let self else { return }
            self.toggled?(self)
        }
    }

    /// Joins this button to `group`'s group, in which GTK keeps at most one
    /// member active and turns the previous one off itself. Passing `nil`
    /// leaves the button on its own.
    ///
    /// Note that GTK refuses to deactivate a group's active member in response
    /// to a *click*, but not in response to a programmatic `active = false`,
    /// which turns the whole group off.
    public func setGroup(_ group: ToggleButton?) {
        gtk_toggle_button_set_group(castedPointer(), group?.castedPointer())
    }

    @GObjectProperty(named: "active") public var active: Bool

    public var toggled: ((ToggleButton) -> Void)?
}
