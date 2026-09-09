# Controls

## Overview

Employ controls to receive user input.

## Topics

- ``Button``
- ``TextField``
- ``SecureField``
- ``TextEditor``
- ``Slider``
- ``Toggle``
- ``Picker``
- ``DatePicker``
- ``Menu``
- ``List``

### Grouping and labelling

- ``Form``
- ``Section``
- ``DisclosureGroup``
- ``LabeledContent``
- ``Label``

### Value entry and display

- ``Stepper``
- ``Gauge``
- ``ColorPicker``
- ``Link``

### Related

- ``ButtonStyle``
- ``ButtonRole``
- ``PrimitiveButtonStyle``
- ``DatePickerStyle``
- ``DatePickerComponents``
- ``MenuItem``
- ``ToggleStyle``
- ``TextContentType``

## Discussion

> Note: Added 2026-09-09. The nine types in the two sections above -- `Form`, `Section`,
> `DisclosureGroup`, `LabeledContent`, `Label`, `Stepper`, `Gauge`, `ColorPicker` and `Link` -- all
> exist in `Sources/SwiftCrossUI/Views/`, one file each, and until this edit not one of them was
> curated anywhere in this documentation catalog. That is not a cosmetic gap. Two of the project's
> own planning documents were asserting, as of this week, that *none* of them existed, and a dated
> ten-item API audit that described itself as "checked rather than trusted" had four of its ten
> answers wrong in the same direction -- `ButtonRole`, `Image(systemName:)`, `Section` and
> `.textFieldStyle` were all recorded as absent and all four ship.
>
> The mechanism is worth naming because it will happen again. A claim that an API is missing is
> written at the one moment it is true. Implementing the API does not send anyone back to the
> document that said it was missing, and an absent DocC topic entry produces no build failure and
> no broken link -- the symbol simply does not appear in the rendered catalog, which looks
> identical to it not existing. So the claim ages into a falsehood with nothing anywhere signalling
> that it has.
>
> The check is cheap and should be run before repeating any "there is no X" in this repository. Note
> that the pattern has to admit every declaration shape, including `typealias`: a first pass of this
> audit used a `struct|class|enum|protocol` pattern and reported ``PalettePickerStyle`` as missing,
> when in fact it is a `public typealias` for ``SegmentedPickerStyle`` at
> `Sources/SwiftCrossUI/Views/Styles/PickerStyle/PalettePickerStyle.swift:4`. Always carry a
> positive and a negative control in the same run, or the result means nothing:
>
> ```shell
> $ grep -rlE "public [a-z ]*(struct|class|enum|protocol|typealias) NAME\b" Sources/SwiftCrossUI/
> $ grep -rlE "public [a-z ]*(struct|class|enum|protocol|typealias) VStack\b" Sources/SwiftCrossUI/          # must find a file
> $ grep -rlE "public [a-z ]*(struct|class|enum|protocol|typealias) ZZZNotARealType\b" Sources/SwiftCrossUI/ # must find nothing
> ```
