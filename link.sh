#!/bin/sh
# Symlink every mod in ./mods into Noita's mods folder. Safe to re-run.
NOITA_MODS="${NOITA_MODS:-$HOME/.local/share/Steam/steamapps/common/Noita/mods}"
cd "$(dirname "$0")/mods" || exit 1
for d in */; do
  ln -sfnv "$PWD/${d%/}" "$NOITA_MODS/${d%/}"
done
