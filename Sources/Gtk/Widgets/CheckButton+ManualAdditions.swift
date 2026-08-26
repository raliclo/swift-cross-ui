import CGtk

extension CheckButton {
    /// Joins this button to `group`'s group, in which GTK keeps at most one
    /// member active and turns the previous one off itself. Passing `nil`
    /// leaves the button on its own.
    ///
    /// This is how GTK 4 builds radio buttons: a grouped check button draws a
    /// radio indicator instead of a check, and there is no separate radio
    /// widget to use.
    ///
    /// Note that GTK refuses to deactivate a group's active member in response
    /// to a *click*, but not in response to a programmatic `active = false`,
    /// which turns the whole group off.
    public func setGroup(_ group: CheckButton?) {
        gtk_check_button_set_group(castedPointer(), group?.castedPointer())
    }
}
