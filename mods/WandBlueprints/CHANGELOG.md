# Changelog

See [README.md](README.md) for what the mod does and how to use it.

## 2026-10-23

### Added

- **See which of your wands match a blueprint.** The mod checks your 4 wands about twice a second, whichever way their spells were changed. A wand matches when it holds exactly a blueprint's spells, or the layout Apply produces on a smaller wand. Matches show in four places:
  - **Wand names:** a matching wand is named after its blueprint, so the name appears in the game's own tooltip and inventory. The original name is kept in a `VariableStorageComponent` on the wand and restored when it stops matching. Setting: "Name wands after their blueprint".
  - **Blueprint list:** rows say "Wand 1, 3" for the wands that match them.
  - **Wands panel:** left of the list, it shows your 4 wands, their spells and their matching blueprint. Click a matching wand to jump to its blueprint, which flashes briefly, or a non-matching one to save it as a new blueprint. Setting: "Show wands panel".
  - **Hotbar:** each matching wand's slot gets a badge: the key the blueprint's hotkey is bound to in M-Nee (such as "u"), or its icon if the hotkey isn't bound, and the held wand's blueprint name shows under the hotbar. Positions come from the game's layout values (`UI_BARS_POS_X/Y`, `INVENTORY_ICON_SIZE`). Setting: "Show blueprints on the hotbar".
- While the wands panel is shown, the hover preview of a blueprint opens below it.

## 2026-10-20

### Changed

- **The blueprint list scrolls instead of using pages.** It scrolls one row at a time with the mouse wheel over the panel, and has a scrollbar you can drag or click to jump a screen. The page footer is gone. While the cursor is over the panel, wand switching is turned off so the mouse wheel scrolls the list, the same as Advanced Spell Inventory's storage. Wand switching comes back on for a few frames after each apply, so the game picks up the changed wand.
- A saved blueprint is scrolled into view instead of jumping to its page.
- **Each row shows the blueprint's spells as a strip of tiny icons** (1/4 size, 5px) under its name. Spells that don't fit show as "+N", and hovering the strip opens the full preview. The rows are taller, so the list shows 8 blueprints at a time instead of 9.

### Fixed

- The typing mute (M-Nee service mode) is re-applied every frame while a field has focus, so another mod ending its own typing can't lift it early, for example when you click from Advanced Spell Inventory's filter straight into a blueprint field.
- If the player disappears while a text field has focus (polymorph, death), the field loses focus and the typing mute is lifted. Before, M-Nee stayed muted until the player came back.
- The category tabs on the left of the panel are drawn fully outside the panel border, like Inventory Bags' tabs. Before, the panel covered their right edge while their icons were drawn on top of it.

## 2026-10-19

### Changed

- **Removed "Clear & Apply"; Apply covers it.** Plain Apply already took the blueprint's unused spells off the wand. The only difference was that Clear & Apply sent every spell through Advanced Spell Inventory, including ones that were already in the right place. Apply now does what Clear & Apply did, but leaves correctly placed spells where they are, so they keep their charges.
- **M-Nee is now a hard requirement for hotkeys.** If M-Nee isn't enabled, the mod prints "M-Nee is not enabled, hotkeys will not work" once, instead of quietly running without hotkeys. The mod now appends its binding file to M-Nee unconditionally. The `mod.xml` description says M-Nee is required.

### Fixed

- The on-screen button is hidden while Advanced Spell Inventory's or Inventory Bags' panel is open. By default it sat on top of them.
- Widget IDs no longer change when a text field gains or loses focus, or when its cursor blinks. Changing IDs made Noita's GUI jitter the widgets below the field. The cursor now blinks by changing its alpha instead of being skipped every other frame.
- Button backgrounds no longer overlap the row above them, and there's less empty space above the button text.

## 2026-10-16: first version

- First release. Blueprints can be saved from a wand or created empty, sorted into category tabs, edited by drag and drop, and applied from the panel or with up to 10 M-Nee hotkeys.
- Spells come from the wand itself, then the spell inventory, then Advanced Spell Inventory's storage.
- Settings: Show button, Applying blueprints requires wand tinkering, and Reset button position.
