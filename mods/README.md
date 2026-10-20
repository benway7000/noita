# Noita mods

Each folder here is one mod. `../link.sh` symlinks them into Noita's `mods/` folder.

- **New mod:** create a folder here, then run `../link.sh`.
- **Removed mod:** delete its symlink from Noita's `mods/` folder by hand.
- **Release:** from this folder, run `zip -r ../<Mod>.zip <Mod> -x '*.bak'`.

## Dependencies

[M-Nee](https://steamcommunity.com/sharedfiles/filedetails/?id=3043711058) (custom input framework) handles hotkeys. Subscribe on the Workshop and enable it alongside these mods.

Optional for every mod here. Without it, Cartographer falls back to a fixed M key, and the other mods' hotkeys are unavailable.
