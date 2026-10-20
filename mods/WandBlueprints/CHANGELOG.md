# Changelog

See [README.md](README.md) for what the mod does and how to use it.

## 2026-10-19

### Changed

- **Removed "Clear & Apply"; Apply covers it.** Plain Apply already took the blueprint's unused spells off the wand. The only difference was that Clear & Apply sent every spell through Advanced Spell Inventory, including ones that were already in the right place. Apply now does what Clear & Apply did, but leaves correctly placed spells where they are, so they keep their charges.
- **M-Nee is now a hard requirement for hotkeys.** If M-Nee isn't enabled, the mod prints "M-Nee is not enabled, hotkeys will not work" once, instead of quietly running without hotkeys. The mod now appends its binding file to M-Nee unconditionally. The `mod.xml` description says M-Nee is required.

### Fixed

- Widget IDs no longer change when a text field gains or loses focus, or when its cursor blinks. Changing IDs made Noita's GUI jitter the widgets below the field. The cursor now blinks by changing its alpha instead of being skipped every other frame.
- Button backgrounds no longer overlap the row above them, and there's less empty space above the button text.

## 2026-10-16: first version

- First release. Blueprints can be saved from a wand or created empty, sorted into category tabs, edited by drag and drop, and applied from the panel or with up to 10 M-Nee hotkeys.
- Spells come from the wand itself, then the spell inventory, then Advanced Spell Inventory's storage.
- Settings: Show button, Applying blueprints requires wand tinkering, and Reset button position.
