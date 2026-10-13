/// A result builder for ``Commands``: ``CommandMenu``s, ``CommandGroup``s and
/// other ``Commands``, in any mix, with `if` and `for`.
/// ``Commands`` 的 result builder:``CommandMenu``、``CommandGroup`` 與其他 ``Commands`` 可任意混用，並支援 `if` 與 `for`。
@resultBuilder
public struct CommandsBuilder {
    public static func buildExpression(_ menu: CommandMenu) -> Commands {
        Commands(menus: [menu])
    }

    public static func buildExpression(_ group: CommandGroup) -> Commands {
        Commands(menus: [], groups: [group])
    }

    public static func buildExpression(_ commands: Commands) -> Commands {
        commands
    }

    public static func buildBlock(_ parts: Commands...) -> Commands {
        parts.reduce(.empty) { $0.overlayed(with: $1) }
    }

    public static func buildOptional(_ part: Commands?) -> Commands {
        part ?? .empty
    }

    public static func buildEither(first part: Commands) -> Commands {
        part
    }

    public static func buildEither(second part: Commands) -> Commands {
        part
    }

    public static func buildArray(_ parts: [Commands]) -> Commands {
        parts.reduce(.empty) { $0.overlayed(with: $1) }
    }
}
