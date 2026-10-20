# Changelog: fork changes

These are the changes in this fork compared to upstream [TheHorscht/InventoryBags](https://github.com/TheHorscht/InventoryBags) at `4097a89` (v0.11.0, "Add white/blacklist for autostorage", 2025-06-19). Upstream's own release history is in [changelog.txt](changelog.txt).

All code changes are in `init.lua`. Most other files differ from upstream only in line endings.

## Added

- **Hotkey works while the vanilla inventory is open.** Pressing the toggle hotkey closes the vanilla inventory and opens the bags. Before, it did nothing. The mod shares an `InvHotkey_closed_inventory_frame` frame stamp with AdvancedSpellInventory, so one hotkey bound to both mods opens both.
- **Show button setting.** Hides the on-screen button, so the bags open only with the M-Nee hotkey. It's on by default, and hiding it also disables button dragging.

## Changed

- **The wand sort order is remembered.** The last sort button you clicked and its direction are saved in globals (`InventoryBags_wand_sort_index` and `InventoryBags_wand_sort_direction`). That sort is applied again whenever the stored wand list is rebuilt, for example after a wand is stored or taken out. Before, the list went back to the default order.

## Fixed

- Removed unused code from the wand sort comparator. It deserialized both wands on every comparison, which made sorting slow.
