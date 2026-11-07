extends RefCounted

## Where this game's own files are, wherever this copy of it happens to live. The logic is dot-game's [DotGamePaths]; this keeps the game's name for it. Hold paths in a `static var`, not a `const`.

const _SELF := preload("hungry_paths.gd")


static func root() -> String: return DotGamePaths.root_of(_SELF)


static func rebase(path: String) -> String: return DotGamePaths.rebase_onto(path, root())


static func rebase_onto(path: String, here: String) -> String: return DotGamePaths.rebase_onto(path, here)
