# Wand Blueprints

A Noita mod that saves the spell layout of a wand as a blueprint, lets you edit it, and puts it back onto any wand later. Blueprints carry over between runs.

## Requirements

- **[M-Nee](https://steamcommunity.com/sharedfiles/filedetails/?id=3043711058)** for hotkeys. The panel still works without it, through its on-screen button.
- **Optional: [Advanced Spell Inventory](../AdvancedSpellInventory).** Applying a blueprint can then take spells from its storage and put spells that come off the wand back into it.

## Usage

Open the panel with the on-screen button or the **Toggle panel** hotkey. You can move the button by right-click dragging it.

### Making blueprints

- **New from held wand** copies the held wand's spells. Always-cast spells and trailing empty slots are left out.
- **New empty** starts from 10 empty slots.

New blueprints go into the category of the open tab. The tabs on the left are All, Combat, Digging, Travel, Healing and Other, and each tab's tooltip shows how many blueprints it holds. Under each name is a strip of tiny icons showing the blueprint's spells, so you can tell blueprints apart at a glance. Hover a blueprint's icon, name or spell strip to see its note and spells at full size.

The list shows 8 blueprints at a time. To scroll it, use the mouse wheel over the panel, drag the scrollbar, or click the scrollbar's track to jump 8 blueprints. While the cursor is over the panel, the mouse wheel doesn't switch wands.

Each blueprint has these buttons:

| Button | Does |
|---|---|
| Apply | Puts the blueprint's spells onto the held wand |
| Edit | Opens the editor |
| Overwrite | Replaces the blueprint's spells with the held wand's. Click twice to confirm |
| Delete | Deletes the blueprint. Click twice to confirm |

### Editing

The editor has fields for the name, note, hotkey, icon and category. You edit the spells by drag and drop, as on a wand:

- Drag spells from the palette onto the slot strip. You can filter the palette by name or by spell type.
- To remove a spell, right-click it, drop it back onto the palette, or drag it out into the world.
- Drop a spell onto the icon slot to make it the blueprint's icon.
- Use **-** / **+** to change the slot count. **Load from held wand** replaces the slots with the held wand's spells.

While you're typing in a field, player controls and every M-Nee binding are disabled, including other mods' bindings such as Cartographer's map key. Each hotkey belongs to one blueprint only. If you give a blueprint a hotkey that another blueprint already uses, the blueprint you saved last keeps it.

### Applying

Click **Apply**, or press the blueprint's hotkey (**Blueprint hotkey 1** to **10** in M-Nee). The blueprint goes onto the wand you're holding. By default this only works where wands can be edited, which means in a Holy Mountain or with the Tinker With Wands Everywhere perk.

The mod looks for each spell in this order:

1. Spells already in the right slot stay where they are.
2. Other spells already on the wand are moved to the slot they belong in, keeping their charges.
3. The spell inventory.
4. Advanced Spell Inventory's storage. When there's a choice, the spell with the most uses left is taken.

Spells the blueprint doesn't use come off the wand. They go into Advanced Spell Inventory if it's running. Otherwise they go into the spell inventory, or are dropped at your feet if that's full.

If the blueprint has more slots than the wand, empty slots are removed from the right until it fits. A message reports any spells that couldn't be found or didn't fit, such as "Spark Bolt x2".

### Which wands match a blueprint

About twice a second, the mod checks your 4 wands. A wand matches a blueprint when it holds exactly the blueprint's spells in the same slots, ignoring trailing empty slots. It also matches the layout Apply produces when it removes empty slots to fit a smaller wand. It doesn't matter how the spells got there: this mod, a Holy Mountain, or another mod. Blueprints without spells never match.

You can see matches in four places, and each one except the list markers has a setting to turn it off:

- **Wand name:** a matching wand is named after its blueprint, so the name shows in the game's own wand tooltip and inventory. The wand's original name is kept on the wand and comes back once its spells stop matching.
- **Blueprint list:** a blueprint's row says "Wand 1, 3" when those wands match it.
- **Wands panel:** left of the blueprint list, it shows your 4 wands with their spells and the blueprint each one matches. Click a matching wand to jump to its blueprint, or a non-matching one to save it as a new blueprint.
- **Hotbar:** each matching wand's slot gets a small badge with the key the blueprint's hotkey is bound to in M-Nee (such as "u"), or the blueprint's icon if its hotkey isn't bound. The held wand's blueprint name shows under the hotbar. The hotbar marks hide while the full inventory is open, and the name hides while Inventory Bags is open.

Wands stored in Inventory Bags or lying on the ground aren't checked, so a stored or dropped wand keeps whatever name it had. They're checked again once they're back in your hotbar.

## Settings

| Setting | Default | |
|---|---|---|
| Show button | on | Shows the on-screen button that opens the panel |
| Applying blueprints requires wand tinkering | on | Turn this off to apply blueprints anywhere |
| Name wands after their blueprint | on | Matching wands show the blueprint's name in the game's tooltip |
| Show wands panel | on | Shows your 4 wands next to the blueprint list |
| Show blueprints on the hotbar | on | Hotbar badges, and the held wand's blueprint name |
| Reset button position | — | Moves the button back to where it started |

## Hotkeys (M-Nee)

| Binding | Default |
|---|---|
| Toggle panel | unbound |
| Blueprint hotkey 1–10 | unbound |

## How it works

- Blueprints are stored in the `WandBlueprints.data` mod setting, in the `WBP1` text format described at the top of [files/storage.lua](files/storage.lua). Blueprints saved before categories existed load as Other.
- Advanced Spell Inventory runs in its own Lua state, so the two mods talk through Globals. A request goes into `AdvancedSpellInventory_api_request`, and the answer comes back in `AdvancedSpellInventory_api_response`. The mod only sends requests while Advanced Spell Inventory's heartbeat global is fresh. If no response comes in time, the mod withdraws the request and finishes the apply without Advanced Spell Inventory.
- The mod bundles TheHorscht's [EZWand](https://github.com/TheHorscht/EZWand) and EZInventory libraries in `lib/`.

See [CHANGELOG.md](CHANGELOG.md) for the release history.
