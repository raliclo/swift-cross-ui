# Custom backends

## Overview

With being open and extensible as a core goal, SwiftCrossUI allows custom
backends to be implemented in third-party packages.

"Simply" implement the ``BaseAppBackend`` protocol and you're good to go!

- Note: While ``BaseAppBackend`` is all that's required for a functional,
  production-ready backend, there are more features (part of ``FullAppBackend``)
  that you may want to implement. These features are all optional and may be
  omitted if your underlying UI framework doesn't support them.

  See the documentation for ``FullAppBackend`` and the ``BackendFeatures``
  namespace enum for more details.

## Topics

### Protocols
- <doc:AppBackend-refactor>
- ``BackendFeatures``
- ``BaseAppBackend``
- ``FullAppBackend``

### Supporting Types
- ``CellPosition``
- ``MenuImplementationStyle``
- ``DialogResult``
- ``ResolvedMenu``
- ``BackendPickerStyle``
- ``BackendDatePickerStyle``
- ``BackendListStyle``
- ``BackendTextFieldStyle``
- ``BackendToggleStyle``

## Discussion

> Note: Added 2026-09-09. `BackendPickerStyle` was the only `Backend*Style` type curated here, and
> the omission of the other four was not a judgement call -- they simply had not been written yet
> when this list was made, and adding a file to `Sources/SwiftCrossUI/Backend/` does not prompt
> anyone to revisit the page that enumerates that folder. All five now sit side by side in that
> directory. Regenerate the list with `ls Sources/SwiftCrossUI/Backend/`, which is the only reliable
> way to keep an enumeration of a folder honest.
