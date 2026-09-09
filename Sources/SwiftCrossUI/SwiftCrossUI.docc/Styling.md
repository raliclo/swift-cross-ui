# Styling

## Topics

### Fonts

- ``View/font(_:)``
- ``View/emphasized()``
- ``Font``

### Color

- ``View/foregroundColor(_:)``
- ``View/colorScheme(_:)``
- ``ColorScheme``

### Corner radius

- ``View/cornerRadius(_:)``

### Picker styles

- ``PickerStyle``
- ``DefaultPickerStyle``
- ``InlinePickerStyle``
- ``MenuPickerStyle``
- ``PalettePickerStyle``
- ``SegmentedPickerStyle``
- ``RadioGroupPickerStyle``
- ``WheelPickerStyle``

### Toggle styles

- ``View/toggleStyle(_:)``
- ``View/toggleColor(_:)``
- ``ToggleStyle``

### Button styles

- ``View/buttonStyle(_:)-(PrimitiveButtonStyle?)``
- ``View/buttonStyle(_:)-(S)``
- ``ButtonStyle``
- ``ButtonStyleConfiguration``
- ``PrimitiveButtonStyle``

### Label styles

- ``View/labelStyle(_:)``
- ``LabelStyle``
- ``LabelStyleConfiguration``
- ``DefaultLabelStyle``
- ``TitleAndIconLabelStyle``
- ``TitleOnlyLabelStyle``
- ``IconOnlyLabelStyle``

### Text field styles

- ``View/textFieldStyle(_:)``
- ``TextFieldStyle``
- ``AutomaticTextFieldStyle``
- ``PlainTextFieldStyle``
- ``RoundedBorderTextFieldStyle``
- ``SquareBorderTextFieldStyle``

### List styles

- ``View/listStyle(_:)``
- ``ListStyle``
- ``AutomaticListStyle``
- ``SidebarListStyle``

## Discussion

> Note: The text field and list style sections were added 2026-09-09. Both families ship --
> `Sources/SwiftCrossUI/Views/Styles/TextFieldStyle/` and
> `Sources/SwiftCrossUI/Views/Styles/ListStyle/`, with the modifiers at
> `Views/Modifiers/Style/TextFieldStyleModifier.swift:13` and
> `Views/Modifiers/Style/ListStyleModifier.swift:20` -- and neither was curated on this page. This
> matters here more than it would on most pages: a dated API audit in this repository had recorded
> `.textFieldStyle` as *not existing*, and an uncurated symbol is invisible in the rendered catalog,
> so the documentation offered no way to contradict that. Regenerate the style lists with
> `grep -rhoE "public (struct|typealias|protocol) [A-Za-z]+" Sources/SwiftCrossUI/Views/Styles/`.
