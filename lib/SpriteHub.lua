-- Provider coordination for Scott's Sprite Menu.
--
-- This module contains no art and never enables/disables a mod.  It chooses
-- an owner only among providers that the Loader has already activated.

local CRYSTAL = "crystal_animated_sprites_with_shiny_visuals"
local FIRERED = "firered_battle_sprites"
local BATTLE_ART = "BATTLE_ART_VOXEL_FORK"
local HUB_ID = "scotts_sprite_hub"
local PLAYER_FRONT_FLIP = "playerFrontFlip"

local Hub = {}
Hub.__index = Hub

local function findIndex(values, wanted)
  for index, value in ipairs(values or {}) do
    if value == wanted then return index end
  end
  return nil
end

local function short(text, limit)
  text = tostring(text or "-"):upper()
  limit = limit or 17
  if #text <= limit then return text end
  return text:sub(1, limit - 1) .. "."
end

function Hub.new(mod)
  return setmetatable({ mod = mod, game = nil, lastNonRomMode = nil }, Hub)
end

function Hub:handle(id)
  local ok, found = pcall(self.mod.find, id)
  return ok and found or nil
end

function Hub:battleArtHandle()
  return self:handle(BATTLE_ART)
end

function Hub:battleArt()
  local found = self:battleArtHandle()
  local lib = found and found.exports and found.exports.lib
  if not (lib and type(lib.require) == "function") then return nil end
  local ok, result = pcall(lib.require, "BattleArt")
  return ok and result or nil
end

function Hub:spriteControl()
  local found = self:battleArtHandle()
  local control = found and found.exports and found.exports.spriteControl
  local apiVersion = type(control) == "table"
    and (control.apiVersion or control.api_version) or nil
  if type(control) == "table" and apiVersion == 1
      and type(control.profile) == "function"
      and type(control.applyProfile) == "function" then
    return control
  end
  return nil
end

function Hub:crystalHandle()
  return self:handle(CRYSTAL)
end

function Hub:fireRedHandle()
  return self:handle(FIRERED)
end

function Hub:crystalReady()
  local found = self:crystalHandle()
  local exports = found and found.exports
  return exports and type(exports.applyOption) == "function"
         and type(exports.listPlayerSprites) == "function"
end

function Hub:activePack()
  local crystal, fireRed = self:crystalHandle(), self:fireRedHandle()
  if crystal and fireRed then return "conflict" end
  if crystal then
    return self:crystalReady() and "crystal" or "crystal_update"
  end
  if fireRed then return "firered" end
  return "battle_art"
end

function Hub:packLabel()
  local pack = self:activePack()
  if pack == "crystal" then return "CRYSTAL 2.0"
  elseif pack == "crystal_update" then return "UPDATE CRYSTAL"
  elseif pack == "firered" then return "FIRE RED"
  elseif pack == "conflict" then return "PACK CONFLICT"
  end
  return "BATTLE ART"
end

function Hub:packVersion()
  local pack = self:activePack()
  local found = (pack == "crystal" or pack == "crystal_update")
    and self:crystalHandle() or (pack == "firered" and self:fireRedHandle())
  return found and tostring(found.version or "UNKNOWN") or "BUILT IN"
end

function Hub:hasTrainerControl()
  local control = self:spriteControl()
  if not control or type(control.values) ~= "function" then return false end
  local okOpponent, opponent = pcall(control.values, "opponentTrainer")
  local okPlayer, player = pcall(control.values, "playerTrainer")
  return okOpponent and okPlayer
    and findIndex(opponent, "battle_art") and findIndex(opponent, "modded")
    and findIndex(player, "battle_art") and findIndex(player, "modded")
    and true or false
end

function Hub:setBattleArtSetting(setting, value, game)
  if not setting or type(setting.get) ~= "function"
      or type(setting.setIndex) ~= "function" then
    return false, "SETTING UNAVAILABLE"
  end
  local index = findIndex(setting.values, value)
  if not index then return false, "VALUE UNAVAILABLE" end
  local okCurrent, current = pcall(setting.get, setting)
  if okCurrent and current == value then return true, value end
  local ok, result = pcall(setting.setIndex, setting, index, game)
  return ok, ok and result or tostring(result)
end

function Hub:cycleBattleArtSetting(setting, game, direction)
  if not setting or type(setting.cycle) ~= "function" then return false end
  local ok = pcall(setting.cycle, setting, game, direction or 1)
  return ok
end

-- This is the hub's own presentation preference, independent of whichever
-- provider owns Pokemon pixels. The save bucket is checked first while a
-- game is live, followed by the Loader mirror used by mod.options:get; the
-- schema default is ON so Crystal v2's player-front card is oriented in the
-- voxel scene where Crystal deliberately skips its separate 2D flip pass.
function Hub:playerFrontFlip(game)
  game = game or self.game
  local saveOptions = game and game.save and game.save.options
  local saveBucket = saveOptions and saveOptions.modOptions
    and saveOptions.modOptions[HUB_ID]
  if type(saveBucket) == "table"
      and type(saveBucket[PLAYER_FRONT_FLIP]) == "boolean" then
    return saveBucket[PLAYER_FRONT_FLIP]
  end

  local loader = game and game.mods
  local loaderBucket = loader and loader.modOptions
    and loader.modOptions[HUB_ID]
  if type(loaderBucket) == "table"
      and type(loaderBucket[PLAYER_FRONT_FLIP]) == "boolean" then
    return loaderBucket[PLAYER_FRONT_FLIP]
  end

  local options = self.mod and self.mod.options
  if options and type(options.get) == "function" then
    local ok, value = pcall(options.get, options, PLAYER_FRONT_FLIP)
    if ok and type(value) == "boolean" then return value end
  end
  return true
end

function Hub:playerFrontFlipLabel(game)
  return self:playerFrontFlip(game) and "ON" or "OFF"
end

local function optionBucket(container)
  if type(container) ~= "table" then return nil end
  container[HUB_ID] = container[HUB_ID] or {}
  if type(container[HUB_ID]) ~= "table" then return nil end
  return container[HUB_ID]
end

function Hub:writePlayerFrontFlip(game, enabled)
  local options = game and game.save and game.save.options
  if type(options) ~= "table" then return false, "GAME NOT READY" end

  options.modOptions = options.modOptions or {}
  local saveBucket = optionBucket(options.modOptions)
  if not saveBucket then return false, "OPTIONS UNAVAILABLE" end
  saveBucket[PLAYER_FRONT_FLIP] = enabled

  -- Match ManagerState:setOption: mod.options:get reads the Loader mirror,
  -- while writeOptions persists the save copy. Keeping both in step also
  -- means a later enforce cannot revive an obsolete provider-side value.
  local loader = game.mods
  if loader then
    loader.modOptions = loader.modOptions or {}
    local loaderBucket = optionBucket(loader.modOptions)
    if not loaderBucket then return false, "OPTIONS UNAVAILABLE" end
    loaderBucket[PLAYER_FRONT_FLIP] = enabled
  end

  if game.writeOptions then
    local ok, err = pcall(game.writeOptions, game)
    if not ok then return false, tostring(err) end
  end
  return true, enabled
end

function Hub:setPlayerFrontFlip(game, enabled)
  if type(enabled) ~= "boolean" then return false, "BOOLEAN REQUIRED" end
  if not (game and game.save and type(game.save.options) == "table") then
    return false, "GAME NOT READY"
  end

  -- frontFlip is a presentation-only Battle Art contract. Applying this
  -- one-field profile cannot transfer Pokemon or trainer ownership, and
  -- Battle Art consumes it only for the staged player FRONT card.
  local value = enabled and "battle_art" or "default"
  local ok, result = self:applyOwnership({ frontFlip = value }, game)
  if not ok then return false, result end
  local persisted, persistResult = self:writePlayerFrontFlip(game, enabled)
  if not persisted then return false, persistResult end
  return true, enabled
end

function Hub:applyOwnership(profile, game)
  local control = self:spriteControl()
  if control then
    local okProfile, current = pcall(control.profile)
    if not okProfile or type(current) ~= "table" then current = {} end
    local changes = {}
    for key, value in pairs(profile or {}) do
      if current[key] ~= value then changes[key] = value end
    end
    if next(changes) == nil then return true, current end
    local ok, changed, result = pcall(control.applyProfile, changes, game)
    if not ok then return false, tostring(changed) end
    return changed, result
  end

  -- Battle Art kfp.2 fallback: Pokemon/flip ownership existed, but trainer
  -- ownership did not.  Never fake a trainer handoff with the global BATTLE
  -- ART mode; that would silently change unrelated battle presentation.
  local battleArt = self:battleArt()
  if not battleArt then return false, "UPDATE BATTLE ART" end
  if profile.pokemon then
    local ok, err = self:setBattleArtSetting(
      battleArt.duplicateSetting, profile.pokemon, game)
    if not ok then return false, err end
  end
  if profile.frontFlip then
    local ok, err = self:setBattleArtSetting(
      battleArt.frontFlipSetting, profile.frontFlip, game)
    if not ok then return false, err end
  end
  if profile.opponentTrainer or profile.playerTrainer then
    return false, "UPDATE BATTLE ART"
  end
  return true
end

function Hub:enforceSpecies(game)
  local pack = self:activePack()
  if pack == "conflict" then return false, "PACK CONFLICT" end
  local frontFlip = self:playerFrontFlip(game)
    and "battle_art" or "default"
  if pack == "crystal" or pack == "crystal_update" then
    return self:applyOwnership({
      pokemon = "modded", frontFlip = frontFlip,
    }, game)
  elseif pack == "firered" then
    return self:applyOwnership({
      pokemon = "modded", frontFlip = frontFlip,
    }, game)
  end
  return self:applyOwnership({
    pokemon = "battle_art", frontFlip = frontFlip,
  }, game)
end

function Hub:enforce(game)
  if game then self.game = game end
  local activeGame = game or self.game
  local ok, result = self:enforceSpecies(activeGame)
  if not ok then return ok, result end

  -- Crystal's trainer option is a second ownership switch: when one of its
  -- battle portraits is enabled, Battle Art must yield that exact surface.
  -- Wait for a real Game so the provider-owned Battle Art setting is also
  -- persisted; the load-time enforce(nil) call only warms setting caches.
  if activeGame and self:crystalReady() and self:hasTrainerControl() then
    local trainersOK, trainersResult = self:reconcileCrystalTrainerMode(
      activeGame, self:crystalMode(activeGame))
    if not trainersOK then return false, trainersResult end
  end

  local battleArt = self:battleArt()
  local mode = battleArt and battleArt.setting and battleArt.setting:get()
  if mode and mode ~= "rom" then self.lastNonRomMode = mode end
  if self:crystalReady() and activeGame then
    local synced, syncResult = self:syncPlayerView(activeGame)
    if not synced then return false, syncResult end
  end
  return ok, result
end

local function crystalTrainerParts(mode)
  return {
    opponent = mode == "trainers" or mode == "both" or mode == "all",
    player = mode == "player" or mode == "both" or mode == "all",
    overworld = mode == "overworld" or mode == "all",
  }
end

function Hub:crystalMode(game)
  local options = game and game.save and game.save.options
  local mode = options and options.crystalTrainers
  if mode == "none" or mode == "player" or mode == "trainers"
      or mode == "both" or mode == "overworld" or mode == "all" then
    return mode
  end
  return "both"
end

function Hub:setCrystalOption(game, key, value)
  local found = self:crystalHandle()
  local apply = found and found.exports and found.exports.applyOption
  if type(apply) ~= "function" then return false, "UPDATE CRYSTAL" end
  if not (game and game.save and game.save.options) then
    return false, "GAME NOT READY"
  end
  local ok, err = pcall(apply, key, value)
  if not ok then return false, tostring(err) end
  game.save.options[key] = value
  if game.writeOptions then pcall(game.writeOptions, game) end
  return true, value
end

function Hub:trainerOwners()
  local control = self:spriteControl()
  if not control then return nil end
  local ok, profile = pcall(control.profile)
  if not ok or type(profile) ~= "table" then return nil end
  return profile.opponentTrainer, profile.playerTrainer
end

function Hub:trainerSource(game)
  if self:crystalHandle() and not self:crystalReady() then
    return "update_crystal"
  end
  if not self:hasTrainerControl() then return "update_battle_art" end

  local opponentOwner, playerOwner = self:trainerOwners()
  if not opponentOwner or not playerOwner then return "update_battle_art" end
  local battleArt = self:battleArt()
  local mode = battleArt and battleArt.setting and battleArt.setting:get()
  local crystal = self:crystalReady()
    and crystalTrainerParts(self:crystalMode(game)) or {}
  local function visible(owner, crystalOwns)
    if owner == "battle_art" then
      return mode == "rom" and "rom" or "battle_art"
    end
    return crystalOwns and "crystal" or "rom"
  end
  local opponent = visible(opponentOwner, crystal.opponent)
  local player = visible(playerOwner, crystal.player)
  return opponent == player and opponent or "mixed"
end

function Hub:trainerLabel(game)
  local source = self:trainerSource(game)
  local labels = {
    crystal = "CRYSTAL", battle_art = "BATTLE ART", rom = "ROM",
    mixed = "MIXED", update_crystal = "UPDATE CRYSTAL",
    update_battle_art = "UPDATE BATTLE ART",
  }
  return labels[source] or "UNAVAILABLE"
end

function Hub:trainerChoices()
  if self:crystalHandle() and not self:crystalReady() then return nil end
  if not self:hasTrainerControl() then return nil end
  if self:crystalReady() then
    return { "crystal", "battle_art", "rom" }
  end
  return { "battle_art", "rom" }
end

function Hub:setTrainerSource(game, source)
  local choices = self:trainerChoices()
  if not findIndex(choices, source) then
    return false, self:trainerLabel(game)
  end

  local crystalMode = self:crystalReady() and self:crystalMode(game) or nil
  local parts = crystalMode and crystalTrainerParts(crystalMode) or {}
  local quietMode = parts.overworld and "overworld" or "none"

  if source == "crystal" then
    -- Make the provider live first. If it rejects the request, Battle Art
    -- remains the visible owner rather than yielding to an empty field.
    local wanted = parts.overworld and "all" or "both"
    local ok, err = self:setCrystalOption(game, "crystalTrainers", wanted)
    if not ok then return false, err end
    return self:applyOwnership({
      opponentTrainer = "modded", playerTrainer = "modded",
    }, game)
  end

  if crystalMode then
    local ok, err = self:setCrystalOption(
      game, "crystalTrainers", quietMode)
    if not ok then return false, err end
  end
  if source == "battle_art" then
    local battleArt = self:battleArt()
    local modeSetting = battleArt and battleArt.setting
    local current = modeSetting and modeSetting:get()
    if current == "rom" then
      local wanted = self.lastNonRomMode
      if wanted ~= "static" and wanted ~= "animated" then wanted = "animated" end
      local modeOK, modeErr = self:setBattleArtSetting(
        modeSetting, wanted, game)
      if not modeOK then return false, modeErr end
    elseif current then
      self.lastNonRomMode = current
    end
  end
  local owner = source == "battle_art" and "battle_art" or "modded"
  return self:applyOwnership({
    opponentTrainer = owner, playerTrainer = owner,
  }, game)
end

function Hub:cycleTrainerSource(game, direction)
  local choices = self:trainerChoices()
  if not choices then return false end
  local current = self:trainerSource(game)
  local index = findIndex(choices, current) or 1
  index = ((index - 1 + (direction or 1)) % #choices) + 1
  return self:setTrainerSource(game, choices[index])
end

function Hub:reconcileCrystalTrainerMode(game, mode)
  if not self:hasTrainerControl() then return false, "UPDATE BATTLE ART" end
  local parts = crystalTrainerParts(mode)
  local changes = {}
  if parts.opponent then changes.opponentTrainer = "modded" end
  if parts.player then changes.playerTrainer = "modded" end

  -- NONE and OVERWORLD do not choose between Battle Art and the ROM.  Keep
  -- the user's existing per-surface owner instead of silently forcing Battle
  -- Art. Partial Crystal modes likewise leave the other portrait alone.
  if next(changes) == nil then return true, self:trainerOwners() end
  return self:applyOwnership(changes, game)
end

function Hub:playerViewLabel()
  if self:crystalHandle() and not self:crystalReady() then
    return "UPDATE CRYSTAL"
  end
  local battleArt = self:battleArt()
  local value = battleArt and battleArt.viewSetting
    and battleArt.viewSetting:get() or nil
  return value == "front" and "FRONT" or "BACK"
end

function Hub:setPlayerView(game, value)
  local battleArt = self:battleArt()
  local setting = battleArt and battleArt.viewSetting
  if value ~= "front" and value ~= "back" then return false end
  if not setting or not findIndex(setting.values, value) then
    return false, "UPDATE BATTLE ART"
  end
  if self:crystalHandle() and not self:crystalReady() then
    return false, "UPDATE CRYSTAL"
  end

  -- Validate both APIs before the first write. Crystal is applied first; the
  -- already-validated Battle Art setting then establishes the same view.
  if self:crystalReady() then
    local ok, err = self:setCrystalOption(
      game, "crystalFront", value == "front")
    if not ok then return false, err end
  end
  return self:setBattleArtSetting(setting, value, game)
end

function Hub:syncPlayerView(game)
  local battleArt = self:battleArt()
  local setting = battleArt and battleArt.viewSetting
  if not setting then return false, "UPDATE BATTLE ART" end
  local value = setting:get() == "front" and "front" or "back"
  if not self:crystalReady() then return true, value end
  local options = game and game.save and game.save.options
  local wanted = value == "front"
  if options and options.crystalFront == wanted then return true, value end
  return self:setCrystalOption(game, "crystalFront", wanted)
end

function Hub:cyclePlayerView(game, direction)
  local battleArt = self:battleArt()
  local setting = battleArt and battleArt.viewSetting
  if not setting then return false end
  local current = setting:get() == "front" and "front" or "back"
  local values = { "front", "back" }
  local index = findIndex(values, current) or 1
  local wanted = values[((index - 1 + (direction or 1)) % #values) + 1]
  return self:setPlayerView(game, wanted)
end

function Hub:battleArtRow(setting, label, afterStep)
  return {
    label = label,
    value = function()
      if not setting or type(setting.read) ~= "function" then
        return "UNAVAILABLE"
      end
      local index = setting:read()
      return short(setting.labels and setting.labels[index]
                   or setting.values and setting.values[index])
    end,
    step = function(game, direction)
      local changed = self:cycleBattleArtSetting(setting, game, direction)
      if changed and afterStep then afterStep(game) end
      return changed
    end,
  }
end

function Hub:battleArtRows()
  local battleArt = self:battleArt()
  if not battleArt then
    return { { label = "BATTLE ART", value = function()
      return "UPDATE BATTLE ART"
    end } }
  end
  return {
    self:battleArtRow(battleArt.setting, "MODE", function(game)
      if battleArt.forceRomPlayer then battleArt.forceRomPlayer(game) end
      local mode = battleArt.setting:get()
      if mode ~= "rom" then self.lastNonRomMode = mode end
    end),
    self:battleArtRow(battleArt.frontAnimationSetting, "FRONT GENERATION"),
    self:battleArtRow(battleArt.backAnimationSetting, "BACK GENERATION"),
    self:battleArtRow(battleArt.trainerSetting, "TRAINER GENERATION"),
    self:battleArtRow(battleArt.playerArtSetting, "PLAYER STATIC"),
    self:battleArtRow(battleArt.playerAnimationSetting, "PLAYER ANIMATED"),
    self:battleArtRow(battleArt.backPlacementSetting, "BACK PLACEMENT"),
  }
end

function Hub:crystalModeLabel(game)
  local labels = {
    none = "NONE", player = "PLAYER", trainers = "TRAINER",
    both = "PLAYER + TRAINER", overworld = "OVERWORLD", all = "ALL",
  }
  return labels[self:crystalMode(game)] or "PLAYER + TRAINER"
end

function Hub:cycleCrystalMode(game, direction)
  if not self:hasTrainerControl() then return false end
  local values = { "none", "player", "trainers", "both", "overworld", "all" }
  local index = findIndex(values, self:crystalMode(game)) or 4
  local wanted = values[((index - 1 + (direction or 1)) % #values) + 1]
  local ok, err = self:setCrystalOption(game, "crystalTrainers", wanted)
  if not ok then return false, err end
  return self:reconcileCrystalTrainerMode(game, wanted)
end

function Hub:crystalPlayerList()
  local found = self:crystalHandle()
  local list = found and found.exports and found.exports.listPlayerSprites
  if type(list) ~= "function" then return { "red.png" } end
  local ok, result = pcall(list)
  if not ok or type(result) ~= "table" or #result == 0 then
    return { "red.png" }
  end
  return result
end

function Hub:crystalPlayerLabel(game)
  local options = game and game.save and game.save.options
  local value = options and options.crystalPlayerSprite or "red.png"
  value = tostring(value):gsub("%.png$", ""):gsub("_flip$", "")
  return short(value)
end

function Hub:cycleCrystalPlayer(game, direction)
  local list = self:crystalPlayerList()
  local options = game and game.save and game.save.options
  local current = options and options.crystalPlayerSprite or "red.png"
  local index = findIndex(list, current) or 1
  local wanted = list[((index - 1 + (direction or 1)) % #list) + 1]
  return self:setCrystalOption(game, "crystalPlayerSprite", wanted)
end

function Hub:crystalRows(game)
  if not self:crystalHandle() then
    return { { label = "CRYSTAL PACK", value = function()
      return "NOT LOADED"
    end } }
  end
  if not self:crystalReady() then
    return { { label = "CRYSTAL PACK", value = function()
      return "UPDATE CRYSTAL"
    end } }
  end

  return {
    {
      label = "FRONT SPRITES",
      value = function() return self:playerViewLabel() end,
      step = function(g)
        local wanted = self:playerViewLabel() == "FRONT" and "back" or "front"
        return self:setPlayerView(g, wanted)
      end,
    },
    {
      label = "REPLACE SPRITES",
      value = function(g)
        if not self:hasTrainerControl() then return "UPDATE BATTLE ART" end
        return self:crystalModeLabel(g)
      end,
      step = function(g, direction)
        return self:cycleCrystalMode(g, direction)
      end,
    },
    {
      label = "PLAYER SPRITE",
      value = function(g) return self:crystalPlayerLabel(g) end,
      step = function(g, direction)
        return self:cycleCrystalPlayer(g, direction)
      end,
    },
    {
      label = "BATTLE PIC",
      value = function(g)
        return g.save.options.crystalBattlePic == "back" and "BACK" or "FRONT"
      end,
      step = function(g)
        local wanted = g.save.options.crystalBattlePic == "back"
          and "front" or "back"
        return self:setCrystalOption(g, "crystalBattlePic", wanted)
      end,
    },
  }
end

function Hub:ownership()
  local control = self:spriteControl()
  if control then
    local ok, owners = pcall(control.owners)
    if ok then return owners end
  end
  local battleArt = self:battleArt()
  if not battleArt then return nil end
  return {
    pokemon = battleArt.duplicateSetting and battleArt.duplicateSetting:get(),
    opponentTrainer = "unavailable",
    playerTrainer = "unavailable",
  }
end

Hub.ids = {
  hub = HUB_ID,
  crystal = CRYSTAL,
  firered = FIRERED,
  battleArt = BATTLE_ART,
}

return Hub
