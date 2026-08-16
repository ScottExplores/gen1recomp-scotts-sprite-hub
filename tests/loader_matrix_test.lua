-- Real API-2 Loader matrix. Usage:
--   luajit loader_matrix_test.lua ENGINE_ROOT INSTALL_ROOT SCENARIO

local argv = rawget(_G, "arg") or {}
local engineRoot = assert(argv[1], "engine root required"):gsub("\\", "/")
local installRoot = assert(argv[2], "install root required"):gsub("\\", "/")
local scenario = assert(argv[3], "scenario required")
package.path = installRoot .. "/?.lua;" .. installRoot .. "/?/init.lua;"
  .. engineRoot .. "/?.lua;" .. engineRoot .. "/?/init.lua;"
  .. package.path

love = require("tests.love_stub")

local T = require("tests.modkit")
local sets = {
  crystal = {
    "BATTLE_ART_VOXEL_FORK",
    "crystal_animated_sprites_with_shiny_visuals",
    "gen1_modern_ui", "gen1recomp_ds", "scotts_sprite_hub",
  },
  firered = {
    "BATTLE_ART_VOXEL_FORK", "firered_battle_sprites",
    "scotts_sprite_hub",
  },
  battle_art = { "BATTLE_ART_VOXEL_FORK", "scotts_sprite_hub" },
  hub_only = { "scotts_sprite_hub" },
  conflict = {
    "BATTLE_ART_VOXEL_FORK",
    "crystal_animated_sprites_with_shiny_visuals",
    "firered_battle_sprites", "scotts_sprite_hub",
  },
}
local ids = assert(sets[scenario], "unknown scenario: " .. scenario)
local paths = {}
for index, id in ipairs(ids) do paths[index] = "mods/" .. id end

local run = T.sdk.loadMods(paths, {
  data = require("tests.modkit.fixtures").fresh(),
  root = installRoot,
  generation = 1,
})

if scenario == "conflict" then
  local crystal = run.loader.mods.crystal_animated_sprites_with_shiny_visuals
  local fireRed = run.loader.mods.firered_battle_sprites
  local bothLoaded = crystal and fireRed
    and crystal.state == "loaded" and fireRed.state == "loaded"
  T.eq(bothLoaded, false, "Crystal and FireRed are rejected as a pair")
  T.check(#(run.errors or {}) > 0,
    "production Loader reports the Crystal/FireRed conflict")
  run.release()
  T.finish("Scott's Sprite Menu conflict rejection")
  return
end

for _, id in ipairs(ids) do
  local loaded = run.loader.mods[id]
  T.check(loaded ~= nil, "Loader discovered " .. id)
  if loaded then
    T.eq(loaded.state, "loaded", id .. " reached loaded state")
    T.check(loaded.failed ~= true, id .. " did not fail")
  end
end
for key, err in pairs(run.errors or {}) do
  io.stderr:write("loader error " .. tostring(key) .. ": " .. tostring(err) .. "\n")
end
T.eq(#(run.errors or {}), 0, "production Loader reported no errors")

local hub = run.loader.exports.scotts_sprite_hub
T.check(hub and type(hub.activePack) == "function", "hub exports loaded")
T.eq(hub and hub.version, "0.2.1", "hub exports current version")
T.check(hub and type(hub.playerFrontFlip) == "function"
    and type(hub.setPlayerFrontFlip) == "function",
  "hub exports player-front flip controls")
if scenario == "hub_only" then
  T.eq(hub.playerFrontFlip(), true,
    "standalone hub reads the safe ON schema default")
  local schema = run.loader.optionSchemas.scotts_sprite_hub
  T.eq(schema and #schema, 1, "standalone hub defines one local option")
  T.eq(schema and schema[1] and schema[1].key, "playerFrontFlip",
    "standalone schema owns only the flip preference")
  T.eq(schema and schema[1] and schema[1].default, true,
    "standalone flip preference defaults ON")
  T.eq(hub.ownership(), nil,
    "standalone validation claims no missing provider surfaces")
  T.eq(hub.trainerSource(), "update_battle_art",
    "standalone trainer controls fail safe with an update prompt")
  local changed, reason = hub.enforce()
  T.eq(changed, false, "standalone enforcement makes no false change")
  T.eq(reason, "UPDATE BATTLE ART",
    "standalone enforcement reports the missing operational companion")
  local dummy = {
    save = { options = { modOptions = {} } }, mods = run.loader,
    writeOptions = function() error("must not persist an unapplied toggle") end,
  }
  local toggled, toggleReason = hub.setPlayerFrontFlip(dummy, false)
  T.eq(toggled, false, "standalone toggle makes no false provider change")
  T.eq(toggleReason, "UPDATE BATTLE ART",
    "standalone toggle reports the missing operational companion")
  T.eq(dummy.save.options.modOptions.scotts_sprite_hub, nil,
    "standalone failed toggle does not persist a false success")
  run.release()
  T.finish("Scott's Sprite Menu standalone validation")
  return
end

local battleExports = run.loader.exports.BATTLE_ART_VOXEL_FORK
local control = battleExports and battleExports.spriteControl
T.eq(control and control.apiVersion, 1,
  "exact Battle Art camelCase sprite-control API is present")
T.check(control and type(control.applyProfile) == "function",
  "exact Battle Art ownership setter is callable")

local expectedPack = ({ crystal = "crystal", firered = "firered",
                        battle_art = "battle_art" })[scenario]
T.eq(hub.activePack(), expectedPack, "active pack is immutable at boot")
local profile = control.profile()
if scenario == "crystal" then
  T.eq(profile.pokemon, "modded", "Crystal owns Pokemon species pictures")
  T.eq(profile.frontFlip, "battle_art",
    "Crystal voxel player front faces the opponent by default")
elseif scenario == "firered" then
  T.eq(profile.pokemon, "modded", "FireRed owns Pokemon species pictures")
  T.eq(profile.frontFlip, "battle_art", "FireRed uses Battle Art orientation")
else
  T.eq(profile.pokemon, "battle_art", "Battle Art owns species pictures alone")
  T.eq(profile.frontFlip, "battle_art", "Battle Art owns orientation alone")
end

local stack = { states = {} }
function stack:push(state) self.states[#self.states + 1] = state end
function stack:pop() return table.remove(self.states) end
function stack:top() return self.states[#self.states] end
local pressed = {}
local input = {}
function input:wasPressed(name) return pressed[name] == true end
local writes = 0
local game = {
  data = run.data,
  mods = run.loader,
  save = {
    options = {
      colors = "gbc", crystalTrainers = "both",
      modOptions = {},
    },
    party = {}, flags = {}, player = { name = "RED" },
  },
  stack = stack,
  input = input,
  writeOptions = function() writes = writes + 1 end,
}

run.loader.events:emit("game.ready", { game = game })
profile = control.profile()
T.eq(hub.playerFrontFlip(game), true, "game starts with hub flip ON")

-- ManagerState writes both buckets before announcing the change. The hub's
-- own event must apply that stored value immediately without transferring
-- Pokemon or trainer ownership.
local beforeEventOwners = control.owners()
run.loader.modOptions.scotts_sprite_hub = { playerFrontFlip = false }
game.save.options.modOptions.scotts_sprite_hub = { playerFrontFlip = false }
run.loader.events:emit("mod.options_changed", {
  mod = "scotts_sprite_hub", key = "playerFrontFlip", value = false,
})
profile = control.profile()
T.eq(profile.frontFlip, "default", "Mod Manager OFF applies live")
T.eq(profile.pokemon, beforeEventOwners.pokemon,
  "Mod Manager flip leaves Pokemon owner unchanged")
T.eq(profile.opponentTrainer, beforeEventOwners.opponentTrainer,
  "Mod Manager flip leaves opponent trainer unchanged")
T.eq(profile.playerTrainer, beforeEventOwners.playerTrainer,
  "Mod Manager flip leaves player trainer unchanged")
run.loader.modOptions.scotts_sprite_hub.playerFrontFlip = true
game.save.options.modOptions.scotts_sprite_hub.playerFrontFlip = true
run.loader.events:emit("mod.options_changed", {
  mod = "scotts_sprite_hub", key = "playerFrontFlip", value = true,
})
T.eq(control.profile().frontFlip, "battle_art",
  "Mod Manager ON applies live")
if scenario == "crystal" then
  T.eq(profile.opponentTrainer, "modded",
    "first boot makes Crystal the sole opponent-trainer provider")
  T.eq(profile.playerTrainer, "modded",
    "first boot makes Crystal the sole player-trainer provider")
  T.eq(hub.trainerSource(game), "crystal",
    "first boot reports one coherent Crystal trainer source")
  T.eq(game.save.options.crystalFront, false,
    "Crystal preference synchronizes to Battle Art's default BACK view")

  -- The Battle Art Mod Manager remains a diagnostics route. Its own event
  -- first updates Battle Art's cached owner; the hub must then reclaim any
  -- portrait that the active Crystal mode supplies, or both providers draw.
  run.loader.events:emit("mod.options_changed", {
    mod = "BATTLE_ART_VOXEL_FORK",
    key = "opponentTrainerSource", value = "battle_art",
  })
  profile = control.profile()
  T.eq(profile.opponentTrainer, "modded",
    "raw manager cannot double-own Crystal opponent trainer")
  run.loader.events:emit("mod.options_changed", {
    mod = "BATTLE_ART_VOXEL_FORK",
    key = "playerTrainerSource", value = "battle_art",
  })
  profile = control.profile()
  T.eq(profile.playerTrainer, "modded",
    "raw manager cannot double-own Crystal player trainer")

  -- A provider-side live option change can announce itself through the
  -- Loader's supported event. NONE/OVERWORLD are not a BA-vs-ROM choice, so
  -- the hub preserves those configured per-surface owners; a partial Crystal
  -- mode yields only the portrait Crystal actually supplies.
  local crystalExports = run.loader.exports
    .crystal_animated_sprites_with_shiny_visuals
  control.applyProfile({
    opponentTrainer = "battle_art", playerTrainer = "modded",
  }, game)
  game.save.options.crystalTrainers = "none"
  crystalExports.applyOption("crystalTrainers", "none")
  run.loader.events:emit("mod.options_changed", {
    mod = "crystal_animated_sprites_with_shiny_visuals",
    key = "crystalTrainers", value = "none",
  })
  profile = control.profile()
  T.eq(profile.opponentTrainer, "battle_art",
    "live Crystal NONE preserves configured Battle Art opponent")
  T.eq(profile.playerTrainer, "modded",
    "live Crystal NONE preserves configured ROM player")

  game.save.options.crystalTrainers = "trainers"
  crystalExports.applyOption("crystalTrainers", "trainers")
  run.loader.events:emit("mod.options_changed", {
    mod = "crystal_animated_sprites_with_shiny_visuals",
    key = "crystalTrainers", value = "trainers",
  })
  profile = control.profile()
  T.eq(profile.opponentTrainer, "modded",
    "live Crystal TRAINER claims only the opponent portrait")
  T.eq(profile.playerTrainer, "modded",
    "live partial mode preserves configured ROM player")
  T.eq(hub.trainerSource(game), "mixed",
    "live partial mode honestly reports Crystal plus ROM")

  game.save.options.crystalTrainers = "both"
  crystalExports.applyOption("crystalTrainers", "both")
  run.loader.events:emit("mod.options_changed", {
    mod = "crystal_animated_sprites_with_shiny_visuals",
    key = "crystalTrainers", value = "both",
  })
  profile = control.profile()
  T.eq(profile.opponentTrainer, "modded",
    "live Crystal BOTH owns opponent without duplicate draw")
  T.eq(profile.playerTrainer, "modded",
    "live Crystal BOTH owns player without duplicate draw")
  T.eq(hub.trainerSource(game), "crystal",
    "live Crystal BOTH restores one coherent provider")

  local selected = hub.setTrainerSource(game, "crystal")
  T.eq(selected, true, "exact Crystal v2 trainer source applies")
  T.eq(hub.trainerSource(game), "crystal",
    "exact providers agree on Crystal trainer ownership")
  profile = control.profile()
  T.eq(profile.opponentTrainer, "modded", "opponent trainer has one owner")
  T.eq(profile.playerTrainer, "modded", "player trainer has one owner")
  T.check(writes > 0, "exact provider settings persist")

  game.save.options.crystalFront = false
  run.loader.events:emit("mod.options_changed", {
    mod = "BATTLE_ART_VOXEL_FORK", key = "playerView", value = "front",
  })
  T.eq(game.save.options.crystalFront, true,
    "manager-side Battle Art view immediately synchronizes Crystal")
end

-- Hub post-filters the completed list. Known duplicate sprite rows disappear,
-- but an unrelated row survives by identity and Dual Screen's row remains.
local unrelated = { id = "unrelated.example", label = "UNRELATED" }
local function optionRows()
  return run.loader.hooks:call("ui.options.rows",
    function(_, rows) return rows end, game, { unrelated })
end
local hidden = {
  crystalSpriteOptions = true,
  ["BATTLE_ART_VOXEL_FORK:battleArt"] = true,
  ["BATTLE_ART_VOXEL_FORK:opponentTrainerSource"] = true,
  ["BATTLE_ART_VOXEL_FORK:playerTrainerSource"] = true,
  ["BATTLE_ART_VOXEL_FORK:trainerArtSet"] = true,
  ["BATTLE_ART_VOXEL_FORK:playerArtSet"] = true,
  ["BATTLE_ART_VOXEL_FORK:playerAnimatedSet"] = true,
  ["BATTLE_ART_VOXEL_FORK:frontAnimatedSet"] = true,
  ["BATTLE_ART_VOXEL_FORK:backAnimatedSet"] = true,
  ["BATTLE_ART_VOXEL_FORK:duplicateFix"] = true,
  ["BATTLE_ART_VOXEL_FORK:playerView"] = true,
  ["BATTLE_ART_VOXEL_FORK:frontFlip"] = true,
  ["BATTLE_ART_VOXEL_FORK:backPlacement"] = true,
}
local rowsA, rowsB = optionRows(), optionRows()
local unrelatedCount, dualCount = 0, 0
for _, row in ipairs(rowsA) do
  T.check(not hidden[row.id], "known duplicate option row removed: "
    .. tostring(row.id))
  if row == unrelated then unrelatedCount = unrelatedCount + 1 end
  if row.id == "gen1recomp_ds" then dualCount = dualCount + 1 end
end
T.eq(unrelatedCount, 1, "unrelated options row survives by identity")
T.eq(#rowsA, #rowsB, "options filter is idempotent")
if scenario == "crystal" then
  T.eq(dualCount, 1, "Dual Screen option remains outside the sprite hub")
end

-- Exactly one Start entry. Modern UI groups it under MOD MENUS; without
-- Modern the same source descriptor stays directly reachable.
local vanilla = {
  { id = "vanilla.item", label = "ITEM" },
  { id = "vanilla.option", label = "OPTION" },
  { id = "vanilla.mods", label = "MODS" },
}
local startRows = run.loader.hooks:call("ui.start_menu.items",
  function(_, items) return items end, game, vanilla)
local direct, grouped
for _, item in ipairs(startRows) do
  if item.id == "scotts_sprite_hub.open" then direct = item end
  if item.id == "gen1_modern_ui.mod_menus" then grouped = item end
end
if scenario == "crystal" then
  T.eq(direct, nil, "Modern UI removes unpinned SPRITES from root Start")
  T.check(grouped and type(grouped.onSelect) == "function",
    "Modern UI creates MOD MENUS")
  grouped.onSelect()
  local menu = stack:top()
  local found = 0
  for _, item in ipairs(menu and menu.items or {}) do
    if item.id == "scotts_sprite_hub.open" then found = found + 1 end
  end
  T.eq(found, 1, "SPRITES appears exactly once inside MOD MENUS")
  stack:pop()
else
  T.check(direct and type(direct.onSelect) == "function",
    "SPRITES is directly reachable without Modern UI")
end

-- Engine screen resolution stamps the Options suffix that Modern UI uses to
-- recognize an arbitrary OptionRows adapter.
local Screens = require("src.ui.Screens")
Screens.invalidate()
local main = Screens.build(game, hub.screenIds.main)
T.eq(main.screenId, "ScottsSpriteOptions", "main screen has Options suffix")
T.eq(#main.rows, 5, "main screen remains a compact five-row surface")
T.check(type(main.update) == "function" and type(main.draw) == "function",
  "main is a semantic OptionRows screen")

local flipRow
for _, row in ipairs(main.rows or {}) do
  if row.label == "MY POKEMON FLIP" then flipRow = row break end
end
T.check(flipRow and type(flipRow.step) == "function",
  "player-front flip row is live on the main screen")
T.eq(flipRow.value(game), "ON", "main flip row begins ON")
local ownersBeforeRow, writesBeforeRow = control.owners(), writes
T.eq(flipRow.step(game, 1), true, "main flip row switches OFF")
T.eq(flipRow.value(game), "OFF", "main flip row reports OFF")
T.eq(control.profile().frontFlip, "default",
  "main OFF maps to Battle Art DEFAULT")
T.eq(game.save.options.modOptions.scotts_sprite_hub.playerFrontFlip, false,
  "main row persists OFF in save options")
T.eq(run.loader.modOptions.scotts_sprite_hub.playerFrontFlip, false,
  "main row mirrors OFF into Loader options")
T.check(writes > writesBeforeRow, "main row invokes writeOptions")
local ownersAfterRow = control.owners()
T.eq(ownersAfterRow.pokemon, ownersBeforeRow.pokemon,
  "main row preserves Pokemon ownership")
T.eq(ownersAfterRow.opponentTrainer, ownersBeforeRow.opponentTrainer,
  "main row preserves opponent-trainer ownership")
T.eq(ownersAfterRow.playerTrainer, ownersBeforeRow.playerTrainer,
  "main row preserves player-trainer ownership")
T.eq(hub.enforce(game), true, "ownership enforce still succeeds while OFF")
T.eq(control.profile().frontFlip, "default",
  "ownership enforce does not reset persisted OFF")
T.eq(flipRow.step(game, -1), true, "main flip row switches ON")
T.eq(flipRow.value(game), "ON", "main flip row reports ON")
T.eq(control.profile().frontFlip, "battle_art",
  "main ON maps to Battle Art orientation")

if scenario == "crystal" then
  -- Exercise the current live UI route itself, not only the exported
  -- controller. The hub's Crystal row owns the write/apply/reconcile
  -- sequence because Crystal v2's original row has no change event.
  T.eq(hub.setTrainerSource(game, "battle_art"), true,
    "live-row setup hands both trainers to Battle Art")
  local crystalScreen = Screens.build(game, hub.screenIds.crystal)
  local replaceRow
  for _, row in ipairs(crystalScreen.rows or {}) do
    if row.label == "REPLACE SPRITES" then replaceRow = row break end
  end
  T.check(replaceRow and type(replaceRow.step) == "function",
    "Crystal live trainer row is reachable in Advanced")
  T.eq(replaceRow.step(game, 1), true,
    "Crystal live row changes NONE to PLAYER")
  T.eq(game.save.options.crystalTrainers, "player",
    "Crystal live row writes provider source of truth")
  profile = control.profile()
  T.eq(profile.opponentTrainer, "battle_art",
    "Crystal live PLAYER leaves opponent with Battle Art")
  T.eq(profile.playerTrainer, "modded",
    "Crystal live PLAYER yields player portrait to Crystal")
end

if scenario ~= "crystal" then
  -- Regression: opening over Start, closing, and reopening never pushes a
  -- duplicate StartMenu. Nested screens likewise reveal their parent.
  stack.states = { { screenId = "StartMenu" } }
  direct.onSelect()
  T.eq(#stack.states, 2, "SPRITES opens one screen over Start")
  pressed = { a = true }
  stack:top():update(0)
  pressed = {}
  T.eq(#stack.states, 3, "PACK opens one nested info screen")
  pressed = { b = true }
  stack:top():update(0)
  pressed = {}
  T.eq(#stack.states, 2, "nested BACK reveals the same hub")
  pressed = { b = true }
  stack:top():update(0)
  pressed = {}
  T.eq(#stack.states, 1, "hub BACK reveals existing Start only")
  direct.onSelect()
  T.eq(#stack.states, 2, "hub reopens without duplicate Start")
end

if scenario == "crystal" then
  local order = {}
  for index, id in ipairs(run.loader.order or {}) do order[id] = index end
  T.check(order.gen1_modern_ui < order.gen1recomp_ds,
    "Modern UI loads before lower-screen compositor")
  T.check(order.gen1recomp_ds < order.scotts_sprite_hub,
    "hub loads after optional presentation owners")

  local function hookPriority(name, owner)
    for _, entry in ipairs(run.loader.hooks.chains[name] or {}) do
      if entry.owner == owner then return entry.priority end
    end
  end
  T.eq(hookPriority("render.hud", "gen1recomp_ds"), 300,
    "Dual Screen wraps outside Modern UI HUD")
  T.eq(hookPriority("render.hud", "gen1_modern_ui"), 100,
    "Modern UI presenter remains on downstream lower route")
  T.eq(hookPriority("ui.options.rows", "scotts_sprite_hub"), 1000,
    "hub filter sees all provider rows")
end

run.release()
T.finish("Scott's Sprite Menu Loader " .. scenario)
