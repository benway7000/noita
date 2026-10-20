# Changelog: fork changes

These are the changes in this fork compared to upstream [TheHorscht/AdvancedSpellInventory](https://github.com/TheHorscht/AdvancedSpellInventory) at `638c170` (v0.10.1, "Add mod setting to hide button", 2026-03-13). Upstream's own release history is in [changelog.txt](changelog.txt).

## Added

- **Scrollable storage that grows as needed.** Storage is no longer a fixed grid. It always keeps one empty row below the last stored spell.
  - Scroll with the mouse wheel while the cursor is over the storage. While the cursor is there, the wheel no longer switches wands.
  - A scrollbar appears once there are more rows than fit on screen. You can drag its thumb or click the track to page up or down, and hovering it shows "Rows X-Y of Z".
  - The scroll position is saved in the run's globals.
  - Auto-storage, "store all spells from wand" and shift-click place spells even when their target slot is scrolled out of view. A spell that matches a stored stack is added to that stack wherever it is. Otherwise it goes into the first free slot, searching from the current view onward and wrapping around.
- **New sort buttons:** "Delay" sorts by cast delay (`fire_rate_wait`) and "Recharge" sorts by recharge time (`reload_time`). Spells with equal values are sorted alphabetically.
- **API for other mods, used by WandBlueprints.** Requests go through these globals:
  - `AdvancedSpellInventory_api_request` takes `id|wand_entity_id|store_entities|slot:ACTION_ID,...`. The mod moves the listed spell entities into storage, then takes the requested spells out of storage and places them on the wand at the given slots. When it has to choose between stacks, it takes from the one with the most uses left.
  - `AdvancedSpellInventory_api_response` returns `id|missing slot:ACTION_ID,...`.
  - `AdvancedSpellInventory_api_heartbeat` is written every frame while storage is usable.
- **Hotkey works while the vanilla inventory is open.** Pressing it closes the vanilla inventory and opens the spell storage. The mod shares an `InvHotkey_closed_inventory_frame` frame stamp with InventoryBags, so one hotkey bound to both mods opens both.
- **Blinking cursor in the filter text field.** Typing goes through a hidden input, so the visible field never had a cursor before.

## Changed

- **Tooltips stay on screen.** For slots in the lower half of the screen, the tooltip opens above the slot, and every tooltip is kept inside the screen edges. To place it, the tooltip is drawn invisibly for one frame first to measure its size.
- The sort buttons now appear in a fixed order: A-Z, Uses, Amount, Type, Delay, Recharge. Before, the order depended on `pairs()` iteration.
- **Setting:** "Amount of rows" is now "Visible storage rows", which sets how many rows are visible at once. It can be changed at runtime and takes effect after a restart (`MOD_SETTING_SCOPE_RUNTIME_RESTART`), so it no longer needs a new game.
- The storage is saved right away after sorting it and after spell uses are refreshed.

## Fixed

- `AdvancedSpellInventory_is_open` now stays accurate. It's reset to closed when the player spawns, and set to closed when "opening the inventory closes the spell inventory" closes the panel. Before, a stale `1` could make WandBlueprints think the panel was open.
- Spells taken out of storage are switched to their in-inventory state explicitly. Before, they relied on `Inventory2Component`, which is disabled while the cursor is over the panel.
- The hidden text input's own cursor no longer shows up at the mouse position.
- Widget IDs no longer change when the filter field gains or loses focus, or when the cursor blinks. Changing IDs made Noita's GUI jitter the following widgets.
- The second filter row is placed using the first row's measured height, not the height of whichever widget was drawn last.
