# Scott's Sprite Menu 0.2.1

Scott's Sprite Menu is a small controller mod. It adds one **SPRITES** entry
to the Gen 1 Start menu and keeps the visible page short:

It contains no sprite or icon assets; all art stays in separate providers.

- **PACK** is information only. The active pack is selected in **MODS** and
  requires a full restart; it never changes while the game is running.
- **PLAYER POKEMON** selects Battle Art's front/back player-side view.
- **MY POKEMON FLIP** mirrors only your Pokemon's staged **FRONT** card. It
  defaults to **ON** so your Pokemon faces the opponent in the voxel battle;
  **OFF** preserves the art's authored direction. It never flips a back
  sprite, an enemy Pokemon, or either trainer portrait.
- **TRAINER ART** selects Crystal, Battle Art, or ROM when those sources are
  actually available.
- **ADVANCED** contains separate Battle Art and Crystal pages.

While the hub is active, those known Battle Art/Crystal sprite rows are
removed from the ordinary in-game **OPTIONS** list so there is one organized
place to find them. Unrelated game, voxel, camera, lighting, and third-party
rows are untouched. The Mod Manager's per-mod settings pages remain available
as a diagnostic/fallback route.

The menu uses Gen1Recomp's normal `OptionRows` screen. Gen1 Modern UI can
therefore group **SPRITES** under **MOD MENUS**, and Scott's Dual Screen mod
can route the same ordinary menu surface to the Thor lower display. This mod
does not patch either presentation mod.

## One owner at a time

The active Pokemon pack is detected at boot and is deliberately immutable for
that run:

- Crystal loaded: Crystal owns Pokemon pictures and Battle Art stages them.
- FireRed loaded: FireRed owns Pokemon pictures and Battle Art stages them.
- Neither loaded: Battle Art owns Pokemon pictures.

In every case, **MY POKEMON FLIP** is the sole source of truth for the staged
player-front orientation. **ON** maps to Battle Art's `frontFlip=battle_art`
contract and **OFF** maps to `frontFlip=default`. Crystal v2 skips its own 2D
player-front mirror while a voxel battle is active, so the hub's default ON
also fixes Crystal's voxel-facing direction without double-flipping its normal
2D battle card. Reapplying pack ownership never resets this preference.

Crystal and FireRed remain separate packages and conflict with each other.
To change between them, use the mod manager, enable only one, and restart.
The hub never changes a mod's enabled state.

Battle Art 1.9.2-scott-kfp.3 or newer also provides independent opponent- and
player-trainer ownership. At startup and after each change made on the hub's
Crystal page, the hub makes Battle Art yield exactly the portraits Crystal
supplies. It also reconciles a provider-side change when that provider
announces the supported `mod.options_changed` event. Crystal's **NONE** and
**OVERWORLD** modes leave the user's existing Battle Art/ROM portrait choices
unchanged. On an older Battle Art build the trainer-source row shows **UPDATE
BATTLE ART** and makes no change. Likewise, an older Crystal
build without the v2 `applyOption` API shows **UPDATE CRYSTAL**; the hub never
pretends that an unsupported setting was changed.

Provider settings are written to the provider's own source of truth. Battle
Art changes use its exported setting API. Crystal changes update the Crystal
save option and call Crystal's exported `applyOption`, then ask Gen1Recomp to
persist options. The hub's one `playerFrontFlip` preference is mirrored to
both `save.options.modOptions` and the Loader's `modOptions` table before
`writeOptions`, exactly like the Mod Manager. A Mod Manager change is applied
live through `mod.options_changed`.

The hub has no duplicate provider sprite-settings schema.

## Art, icons, and licensing boundary

This package ships **no Pokemon art, trainer art, menu art, font, icon, or
generated/recreated Gen 2 sprite**. `LICENSE` covers only this adapter's
original Lua code, documentation, and tests. It does not relicense or grant
rights to Crystal Animated Sprites, the private FireRed pack, Battle Art, any
Pokemon asset, or any separately installed provider. Each provider and every
art asset remains in its own package under its own provenance and terms.

The planned Gen 2 pocket/bag interface is separate future work. Its intended
route is a separate `optional_import` that reads the user's own Pokemon Gold
ROM at runtime and imports the authentic `PackMenuGFX` / `PackGFX`, pocket
tiles, and palettes. No Gen 2 icons would be bundled, generated, or redrawn by
this controller. That import and its provenance checks are roadmap only, not a
feature of v0.2.1. Keeping the current hub compact and using a separate
Advanced page leaves room for that future Thor lower-screen interface without
changing sprite ownership.

## Installation

Install this mod alongside Scott's Battle Art Kanto. Install either Crystal
Animated Sprites v2 or the FireRed alternative, not both. Gen1 Modern UI and
Scott's Dual Screen are optional.

If you already have Sprite Menu 0.2.0, install
`scotts_sprite_hub-0.2.1.zip` manually one final time. Version 0.2.0 did not
contain a GitHub repository address, so Gen1Recomp cannot discover this
bootstrap update on its own. Version 0.2.1 records the public
`ScottExplores/gen1recomp-scotts-sprite-hub` repository in its manifest;
after 0.2.1 is installed, future GitHub releases can be found through
Gen1Recomp's normal mod updater.

Battle Art is listed as an optional companion in the manifest so Gen1Recomp's
official isolated package validator can mount and inspect this ZIP by itself.
It remains the operational provider for this menu: if it is missing, the hub
loads safely, claims no sprite surfaces, and its provider controls report
**UPDATE BATTLE ART** rather than making a change.

Open **START > SPRITES**. With Modern UI's default grouping enabled, open
**START > MOD MENUS > SPRITES** instead.
