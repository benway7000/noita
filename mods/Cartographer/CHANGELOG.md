# Changelog: fork changes

These are the changes in this fork compared to upstream [willyamjarcand/noita_cartographer](https://github.com/willyamjarcand/noita_cartographer) at `13ed75d` (2026-08-03).

## Added

- **M-Nee keybinding.** When [M-Nee](https://steamcommunity.com/sharedfiles/filedetails/?id=3043711058) is enabled, the map toggle is an M-Nee binding named "Cartographer → Toggle map", defaulting to M. You can rebind it, and it is muted while another mod has a text field focused. The binding is weak, so Ctrl+M (M-Nee's own menu) doesn't also toggle the map. Without M-Nee, the mod falls back to the raw M key. The binding is defined in `files/mnee.lua`, which is appended to `mods/mnee/bindings.lua`.
- **Modifier keys block the fallback M key.** With M-Nee off, holding Ctrl, Shift or Alt stops M from toggling the map.
- **Cursed rock has its own colour.** Chunks in `solid_wall_tower` are drawn in a reddish brown (`0x8E4A3E`). These are the cursed rock walls around the tower, the wizards' den and the world edges. That biome shares the display name `_EMPTY_` with many others, so it is identified by its biome file (`DebugBiomeMapGetFilename`). Chunks from older saves that are tagged `_EMPTY_` are checked again once per session.

## Changed

- **The map is saved to its own file instead of the run's globals.** The file is `save00/cartographer_map.dat`. Globals end up inside `world_state.xml`, and a long run's map can reach several megabytes.
  - The data is stored as raw bytes, with no base64 and no 2 MB cap.
  - The file holds a header (`CARTOGRAPHER 2`, a run ID and the marker byte count), then the markers, then the chunk data in the existing VM1 format.
  - The run ID is kept in the `CARTOGRAPHER_RUN_ID` global, and the file is only loaded when its ID matches. A new game gets a new ID, so it never picks up an old map.
  - Writes go to a `.tmp` file that is then renamed over the old one. If loading can't find the main file, it falls back to the `.tmp`.
  - **Migration:** a map stored in the old globals is still loaded, from either the `CARTOGRAPHER_*` keys or the pre-rename `VALHEIM_MAP_*` keys. Those globals are cleared after the first successful file write.
  - The mod now needs unsafe mods enabled (`request_no_api_restrictions="1"`), because sandboxed mods have no `io`. The file path is built from `USERPROFILE`, which Proton also sets.
- **Save errors are shown on the map.** The old "map too large to save" warning is replaced by "map not saved (reason)", which is shown whenever a write fails.
- The map's backdrop and terrain are drawn at explicit GUI Z levels (-6900 and -7000), so they render above other mods' GUIs.
- The descriptions in `mod.xml` and `settings.lua` now mention M-Nee rebinding, the unsafe-mods requirement and the file-based save.
- Removed `persist.clear()`, which nothing called.

## Fixed

- **The map is cleared when New Game+ starts.** NG+ keeps the same run, with its globals and run ID, but regenerates the world, so the old terrain used to stay on the map. The mod now checks `NEW_GAME_PLUS_COUNT` every frame. When the count goes up, it clears the map and markers and drops any save in progress, and this works whether or not the map is set to persist across saves. The save file is now tied to `run_id:ng_count`, so quitting and resuming in NG+ never loads the previous cycle's map. Files saved before this fix contain only the run ID. They are still loaded outside NG+ but ignored once NG+ has started.
