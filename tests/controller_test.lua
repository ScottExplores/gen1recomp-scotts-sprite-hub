local argv = rawget(_G, "arg") or {}
local root = assert(argv[1], "mod root required"):gsub("\\", "/"):gsub("/$", "")
local Hub = assert(loadfile(root .. "/lib/SpriteHub.lua"))()

local passed = 0
local function eq(actual, expected, message)
  assert(actual == expected, (message or "mismatch") .. ": expected "
    .. tostring(expected) .. ", got " .. tostring(actual))
  passed = passed + 1
end
local function check(value, message)
  assert(value, message or "check failed")
  passed = passed + 1
end

local writes = 0
local game = {
  save = { options = { crystalTrainers = "both", modOptions = {} } },
  mods = { modOptions = {} },
  writeOptions = function() writes = writes + 1 end,
}

local function setting(values, labels, initial)
  local result = { values = values, labels = labels, index = initial or 1 }
  function result:read() return self.index end
  function result:get() return self.values[self.index] end
  function result:setIndex(index, passedGame)
    self.index = ((index - 1) % #self.values) + 1
    if passedGame and passedGame.writeOptions then passedGame:writeOptions() end
    return self:get()
  end
  function result:cycle(passedGame, direction)
    return self:setIndex(self.index + (direction or 1), passedGame)
  end
  return result
end

local battleArt = {
  duplicateSetting = setting({ "battle_art", "modded" },
    { "BATTLE ART", "MODDED" }, 1),
  frontFlipSetting = setting({ "battle_art", "default" },
    { "BATTLE ART", "DEFAULT" }, 1),
  opponentTrainerSourceSetting = setting({ "battle_art", "modded" },
    { "BATTLE ART", "MODDED" }, 1),
  playerTrainerSourceSetting = setting({ "battle_art", "modded" },
    { "BATTLE ART", "MODDED" }, 1),
  setting = setting({ "static", "animated", "rom" },
    { "STATIC", "ANIMATED", "ROM" }, 2),
  frontAnimationSetting = setting({ "gen1", "gen2", "gen3", "gen4", "gen5" },
    { "GEN 1", "GEN 2", "GEN 3", "GEN 4", "GEN 5" }, 5),
  backAnimationSetting = setting({ "gen1", "gen2", "gen3", "gen4", "gen5" },
    { "GEN 1", "GEN 2", "GEN 3", "GEN 4", "GEN 5" }, 5),
  viewSetting = setting({ "front", "back" }, { "FRONT", "BACK" }, 2),
  backPlacementSetting = setting({ "auto", "world", "ui" },
    { "AUTO", "WORLD", "OG UI" }, 1),
  trainerSetting = setting({ "gen1", "gen2", "gen3" },
    { "GEN 1", "GEN 2", "GEN 3" }, 1),
  playerArtSetting = setting({ "png", "gen1", "rom" },
    { "PNG", "GEN 1", "ROM" }, 1),
  playerAnimationSetting = setting({ "png", "red", "rom" },
    { "PNG", "RED", "ROM" }, 2),
}

local profile = {
  pokemon = "battle_art", opponentTrainer = "battle_art",
  playerTrainer = "battle_art", frontFlip = "battle_art",
}
local control = { apiVersion = 1 }
local lastControlChanges
function control.profile()
  local copy = {}
  for key, value in pairs(profile) do copy[key] = value end
  return copy
end
function control.owners()
  return { pokemon = profile.pokemon,
           opponentTrainer = profile.opponentTrainer,
           playerTrainer = profile.playerTrainer }
end
function control.values(surface)
  if surface == "frontFlip" then return { "battle_art", "default" } end
  return { "battle_art", "modded" }
end
function control.applyProfile(changes, passedGame)
  lastControlChanges = {}
  for key, value in pairs(changes) do lastControlChanges[key] = value end
  for key, value in pairs(changes) do profile[key] = value end
  if passedGame and passedGame.writeOptions then passedGame:writeOptions() end
  return true, control.profile()
end

local applied = {}
local crystal = {
  id = "crystal_animated_sprites_with_shiny_visuals",
  version = "2.0.0",
  exports = {
    applyOption = function(key, value) applied[key] = value end,
    listPlayerSprites = function()
      return { "red.png", "kris_flip.png" }
    end,
  },
}
local fireRed = { id = "firered_battle_sprites", version = "0.1.0", exports = {} }
local battleHandle = {
  id = "BATTLE_ART_VOXEL_FORK", version = "1.9.2-scott-kfp.3",
  exports = {
    spriteControl = control,
    lib = { require = function(name)
      assert(name == "BattleArt")
      return battleArt
    end },
  },
}
local loaded = {
  BATTLE_ART_VOXEL_FORK = battleHandle,
  crystal_animated_sprites_with_shiny_visuals = crystal,
}
local mod = {
  id = "scotts_sprite_hub",
  find = function(id) return loaded[id] end,
  options = { get = function(_, key)
    local bucket = game.mods.modOptions.scotts_sprite_hub
    if bucket and bucket[key] ~= nil then return bucket[key] end
    if key == "playerFrontFlip" then return true end
  end },
}
local hub = Hub.new(mod)

eq(hub:activePack(), "crystal", "Crystal v2 detected")
eq(hub:packLabel(), "CRYSTAL 2.0", "Crystal pack label")
check(hub:enforce(game), "Crystal ownership enforced")
eq(profile.pokemon, "modded", "Crystal alone owns Pokemon art")
eq(profile.frontFlip, "battle_art",
  "Crystal voxel player front faces the opponent by default")
eq(profile.opponentTrainer, "modded",
  "Crystal default immediately owns opponent trainer")
eq(profile.playerTrainer, "modded",
  "Crystal default immediately owns player trainer")
eq(hub:playerFrontFlipLabel(game), "ON", "player-front flip defaults ON")

-- The hub option owns only Battle Art's staged player FRONT orientation.
-- Switching it cannot take Pokemon pixels or either trainer away from the
-- provider, and the setting survives a later ownership reconciliation.
local beforeFlipWrites = writes
check(hub:setPlayerFrontFlip(game, false), "player-front flip turns OFF")
eq(profile.frontFlip, "default", "OFF preserves authored front direction")
eq(lastControlChanges.frontFlip, "default", "only frontFlip contract changes")
eq(lastControlChanges.pokemon, nil, "flip leaves Pokemon ownership alone")
eq(lastControlChanges.opponentTrainer, nil,
  "flip leaves opponent-trainer ownership alone")
eq(lastControlChanges.playerTrainer, nil,
  "flip leaves player-trainer ownership alone")
eq(profile.pokemon, "modded", "Crystal keeps Pokemon art while flip is OFF")
eq(profile.opponentTrainer, "modded", "Crystal keeps opponent trainer")
eq(profile.playerTrainer, "modded", "Crystal keeps player trainer")
eq(game.save.options.modOptions.scotts_sprite_hub.playerFrontFlip, false,
  "hub flip persists in save options")
eq(game.mods.modOptions.scotts_sprite_hub.playerFrontFlip, false,
  "hub flip mirrors into Loader options")
check(writes > beforeFlipWrites, "hub flip asks Gen1Recomp to write options")
eq(hub:playerFrontFlipLabel(game), "OFF", "hub reads persisted OFF")
check(hub:enforce(game), "species ownership can be re-enforced while OFF")
eq(profile.frontFlip, "default", "enforce does not reset hub flip")
check(hub:setPlayerFrontFlip(game, true), "player-front flip turns ON")
eq(profile.frontFlip, "battle_art", "ON mirrors the staged player front")
eq(hub:playerFrontFlipLabel(game), "ON", "hub reads persisted ON")

check(hub:setTrainerSource(game, "crystal"), "Crystal trainer source selected")
eq(profile.opponentTrainer, "modded", "Battle Art yields opponent trainer")
eq(profile.playerTrainer, "modded", "Battle Art yields player trainer")
eq(game.save.options.crystalTrainers, "both", "Crystal owns both trainers")
eq(applied.crystalTrainers, "both", "Crystal live setter called")
eq(hub:trainerSource(game), "crystal", "trainer source reports Crystal")

game.save.options.crystalTrainers = "all"
check(hub:setTrainerSource(game, "battle_art"), "Battle Art trainers selected")
eq(game.save.options.crystalTrainers, "overworld",
  "trainer handoff preserves Crystal overworld art")
eq(profile.opponentTrainer, "battle_art", "Battle Art owns opponent trainer")
eq(profile.playerTrainer, "battle_art", "Battle Art owns player trainer")
eq(hub:trainerSource(game), "battle_art", "trainer source reports Battle Art")

check(hub:setTrainerSource(game, "rom"), "ROM trainers selected")
eq(profile.opponentTrainer, "modded", "Battle Art yields opponent to ROM")
eq(profile.playerTrainer, "modded", "Battle Art yields player to ROM")
eq(game.save.options.crystalTrainers, "overworld",
  "ROM selection does not remove overworld choice")
eq(hub:trainerSource(game), "rom", "trainer source reports ROM")

game.save.options.crystalTrainers = "none"
profile.opponentTrainer, profile.playerTrainer = "battle_art", "modded"
check(hub:reconcileCrystalTrainerMode(game, "none"),
  "Crystal NONE reconciliation succeeds")
eq(profile.opponentTrainer, "battle_art",
  "Crystal NONE preserves configured Battle Art opponent")
eq(profile.playerTrainer, "modded",
  "Crystal NONE preserves configured ROM player")
check(hub:cycleCrystalMode(game, 1), "Crystal partial mode cycles")
eq(game.save.options.crystalTrainers, "player", "Crystal player-only stored")
eq(profile.opponentTrainer, "battle_art",
  "player-only Crystal leaves opponent to Battle Art")
eq(profile.playerTrainer, "modded", "player-only Crystal owns player")
eq(hub:trainerSource(game), "mixed", "partial surface ownership is honest")

eq(hub:playerViewLabel(), "BACK", "player view reads Battle Art")
check(hub:cyclePlayerView(game, 1), "player view cycles")
eq(hub:playerViewLabel(), "FRONT", "player view persists through provider")
eq(game.save.options.crystalFront, true,
  "main player view synchronizes Crystal front preference")
eq(applied.crystalFront, true, "main player view applies Crystal live")

local crystalRows = hub:crystalRows(game)
eq(#crystalRows, 4, "all Crystal v2 settings exposed")
check(crystalRows[1].step(game, 1), "Crystal front setting changes")
eq(game.save.options.crystalFront, false, "Crystal row synchronizes BACK")
eq(battleArt.viewSetting:get(), "back", "Crystal row synchronizes Battle Art")
eq(applied.crystalFront, false, "Crystal synchronized view applied live")
check(crystalRows[3].step(game, 1), "Crystal player cycles")
eq(game.save.options.crystalPlayerSprite, "kris_flip.png",
  "Crystal player choice stored at source")
check(crystalRows[4].step(game, 1), "Crystal battle pic cycles")
eq(game.save.options.crystalBattlePic, "back", "Crystal battle pic stored")
check(writes > 0, "provider and Battle Art changes persisted")

loaded.crystal_animated_sprites_with_shiny_visuals = nil
loaded.firered_battle_sprites = fireRed
profile.pokemon, profile.frontFlip = "battle_art", "default"
eq(hub:activePack(), "firered", "FireRed alternative detected")
check(hub:enforce(game), "FireRed ownership enforced")
eq(profile.pokemon, "modded", "FireRed alone owns Pokemon art")
eq(profile.frontFlip, "battle_art", "FireRed uses Battle Art orientation")
eq(#hub:trainerChoices(), 2, "FireRed has Battle Art/ROM trainer choices")

loaded.firered_battle_sprites = nil
profile.pokemon, profile.frontFlip = "modded", "default"
eq(hub:activePack(), "battle_art", "Battle Art-only pack detected")
check(hub:enforce(game), "Battle Art-only ownership enforced")
eq(profile.pokemon, "battle_art", "Battle Art owns Pokemon art alone")
eq(profile.frontFlip, "battle_art", "Battle Art owns orientation alone")

-- Global BATTLE ART=ROM disables Battle Art trainer pictures even when the
-- ownership settings still say battle_art. The hub reports what is visible,
-- and selecting BATTLE ART restores a usable non-ROM mode.
battleArt.setting.index = 3
profile.opponentTrainer, profile.playerTrainer = "battle_art", "battle_art"
eq(hub:trainerSource(game), "rom", "global ROM mode reports ROM trainers")
check(hub:setTrainerSource(game, "battle_art"),
  "Battle Art trainer choice leaves global ROM mode")
eq(battleArt.setting:get(), "animated", "trainer choice restores ANIMATED")
eq(hub:trainerSource(game), "battle_art", "Battle Art trainer source is visible")

loaded.crystal_animated_sprites_with_shiny_visuals = crystal
loaded.firered_battle_sprites = fireRed
local beforeConflict = control.profile()
local okConflict = hub:enforce(game)
eq(okConflict, false, "Crystal/FireRed conflict refuses ownership mutation")
eq(hub:activePack(), "conflict", "conflict reported")
eq(profile.pokemon, beforeConflict.pokemon, "conflict leaves owner unchanged")

loaded.firered_battle_sprites = nil
loaded.crystal_animated_sprites_with_shiny_visuals = {
  id = crystal.id, version = "1.4.0", exports = {},
}
eq(hub:activePack(), "crystal_update", "old Crystal requires update")
eq(hub:trainerSource(game), "update_crystal", "old Crystal trainer row fails safe")
local beforeOld = control.profile()
local oldChanged = hub:setTrainerSource(game, "crystal")
eq(oldChanged, false, "old Crystal claims no trainer change")
eq(profile.playerTrainer, beforeOld.playerTrainer,
  "old Crystal cannot mutate trainer owner")

-- kfp.2 compatibility: species ownership uses the legacy settings, but
-- trainers cannot be handed off through the unrelated global battle mode.
loaded.crystal_animated_sprites_with_shiny_visuals = crystal
battleHandle.exports.spriteControl = nil
battleArt.duplicateSetting.index, battleArt.frontFlipSetting.index = 1, 1
check(hub:enforce(game), "kfp.2 species fallback remains safe")
eq(battleArt.duplicateSetting:get(), "modded", "kfp.2 yields Pokemon art")
eq(battleArt.frontFlipSetting:get(), "battle_art",
  "kfp.2 fallback honours the hub's ON orientation")
eq(hub:trainerSource(game), "update_battle_art", "kfp.2 trainer row asks update")
local oldBattleMode = battleArt.setting:get()
local oldTrainerChanged = hub:setTrainerSource(game, "rom")
eq(oldTrainerChanged, false, "kfp.2 trainer handoff is refused")
eq(battleArt.setting:get(), oldBattleMode,
  "kfp.2 fail-safe never abuses global Battle Art mode")

print(("Scott's Sprite Menu controller tests passed: %d assertions"):format(passed))
