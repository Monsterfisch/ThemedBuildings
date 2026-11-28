--[[
Themed Buildings: chapel, church and cathedral look European or Arabian depending on the lord
of the player who owns them.

How:
* At game start the game loads every .gm1 sheet. Right after that, the church sheet
  (tile_churches, gm 49) is copied into a free gm slot and gmResourceModifier swaps in
  resources/tile_churches_themed.gm1, the same sheet with the three buildings redrawn.
* renderMap reads a building tile's picture number in two places (ground diamonds, then the
  building strips). Both reads are hooked: when the picture belongs to a chapel, church or
  cathedral and the owner's lord culture differs from the one the game files show, the same
  picture of the themed sheet is drawn instead. Nothing is written into the map or the save.
* The owner's culture comes from the game's own lord type function (0 European, 1 Arabian),
  which aiSwapper also answers for custom AI lords. It is asked once per player per game tick.
]]

local NAME = "themed-buildings"
local GM_CHURCHES = 49
local GM_SLOTS = 240
local GM_HEADER = 5208
local SHEET_IMAGES = 286           -- cathedral 169 + church 81 + chapel 36
local GROUP_RUIN = 286             -- vanilla only: the ruined cathedral, 169 more
local GROUP_CHURCH = 169
local GROUP_CHAPEL = 250
local RESOURCE = "ucp/modules/" .. NAME .. "/resources/tile_churches_themed.gm1"
local CACHE = "ucp/" .. NAME .. "-tile_churches.gm1"
local CULTURE = { european = 0, arabian = 1 }
-- The game tick counter: mov ecx, [edi+0x998] / mov edx, [ticks] in updateUnits. The mask load
-- before it is patched by other modules.
local AOB_TICKS = "8B 8F 98 09 00 00 8B 15 ? ? ? ?"

local themed = {}

local function log_(level, text)
  log(level, NAME .. ": " .. text)
end

local function scan(name, pattern)
  local found, address = pcall(core.AOBScan, pattern)
  if not found then error(name .. " not found", 0) end
  return address
end

local function tickCounter()
  local found, site = pcall(core.AOBScan, AOB_TICKS)
  if not found then error("game tick counter: not found") end
  return core.readInteger(site + 8)
end

local function u8(address)
  return core.readByte(address) & 0xFF
end

local function readAll(path)
  local file = io.open(path, "rb")
  if file == nil then
    return nil
  end
  local data = file:read("a")
  file:close()
  return data
end

---gmResourceModifier reads the file itself (not through UCP), so a module installed as a zip
---needs the sheet on disk: keep a copy in ucp/.
local function sheetPath()
  local data = readAll(RESOURCE)
  if data == nil then
    error(NAME .. ": missing " .. RESOURCE)
  end
  if readAll(CACHE) ~= data then
    local file = io.open(CACHE, "wb")
    if file == nil then
      error(NAME .. ": could not write " .. CACHE)
    end
    file:write(data)
    file:close()
  end
  return CACHE, string.unpack("<I4", data, 13), string.unpack("<I4", data, 21)
end

local function switch(value, name)
  if value == nil then return false end
  if type(value) == "boolean" then return value end
  log_(ERROR, "Invalid " .. name .. " setting type. Using off.")
  return false
end

local function culture(value, default, building)
  if value == nil then return default end
  if type(value) ~= "string" then
    log_(ERROR, "Invalid " .. building .. " culture setting type.")
    return default
  end
  local index = CULTURE[value]
  if index == nil then
    log_(WARNING, "Unknown " .. building .. " culture. Using the default.")
    return default
  end
  return index
end

-- Render hooks ------------------------------------------------------------------------------

local REMAP = [[
; Two entry points: +0 remap (ecx = picture, eax = map tile: the owner is the building on the
; tile) and +5 remapPlayer (ecx = picture, eax = player: the building preview, which has no
; building yet). Both return ecx and keep every other register and the flags.
  jmp near remap
  jmp near remapPlayer
remap:
  pushfd
  push eax
  push edx
  mov edx, ecx
  sub edx, dword [VARS + 4]          ; picture - first picture of the church sheet
  cmp edx, dword [VARS + 0xC]        ; pictures both sheets have
  jae r_done
  cmp dword [VARS], 0                ; themed sheet not loaded
  je r_done
  movsx eax, word [eax*2 + BMAP]     ; building on the tile
  test eax, eax
  jle r_done
  imul eax, eax, 0x32C
  movzx eax, word [eax + OWNER]
  jmp r_owner
remapPlayer:
  pushfd
  push eax
  push edx
  mov edx, ecx
  sub edx, dword [VARS + 4]
  cmp edx, dword [VARS + 0xC]
  jae r_done
  cmp dword [VARS], 0
  je r_done
r_owner:
  test eax, eax
  jz r_done
  cmp eax, 15
  ja r_done
  push edx
  call lordOf                        ; al = 0 European, 1 Arabian
  pop edx
  cmp edx, CHURCH
  jb r_cathedral
  cmp edx, CHAPEL
  jb r_church
  cmp edx, RUIN
  jae r_cathedral
  cmp al, byte [VARS + 0x12]
  je r_done
  jmp r_swap
r_church:
  cmp al, byte [VARS + 0x11]
  je r_done
  jmp r_swap
r_cathedral:
  cmp al, byte [VARS + 0x10]
  je r_done
r_swap:
  add ecx, dword [VARS]
r_done:
  pop edx
  pop eax
  popfd
  ret

; eax = player 1..15 -> eax = lord type, asked from the game once per player and tick.
lordOf:
  mov edx, dword [TICK]
  cmp edx, dword [VARS + 8]
  je l_cached
  mov dword [VARS + 8], edx
  mov dword [VARS + 0x20], 0xFFFFFFFF
  mov dword [VARS + 0x24], 0xFFFFFFFF
  mov dword [VARS + 0x28], 0xFFFFFFFF
  mov dword [VARS + 0x2C], 0xFFFFFFFF
l_cached:
  movzx edx, byte [VARS + 0x20 + eax]
  cmp edx, 0xFF
  jne l_known
  push ecx
  push eax
  push eax
  mov edx, LORDTYPE
  call edx                           ; stdcall, ret 4
  and eax, 1
  mov edx, eax
  pop eax
  mov byte [VARS + 0x20 + eax], dl
  pop ecx
l_known:
  mov eax, edx
  ret
]]

local HOOK_GROUND = [[
  movzx ecx, word [ebp*2 + GFX]
  push eax
  mov eax, ebp
  call REMAP
  pop eax
  jmp RESUME
]]

local HOOK_BUILDING = [[
  movzx ebp, word [eax*2 + GFX]
  push ecx
  mov ecx, ebp
  call REMAP
  mov ebp, ecx
  pop ecx
  jmp RESUME
]]

-- The building preview: the construction layer holds the pictures of the building being
-- placed, tile by tile, and renderMap reads it twice (ground diamonds, then the building
-- strips). It belongs to the local player, so their lord decides the look.
local HOOK_PREVIEW_GROUND = [[
  movzx eax, word [ebp*2 + LAYER]
  push ecx
  mov ecx, eax
  mov eax, dword [PLAYER]
  call REMAP_PLAYER
  mov eax, ecx
  pop ecx
  jmp RESUME
]]

local HOOK_PREVIEW_BUILDING = [[
  movzx eax, word [eax]
  push ecx
  mov ecx, eax
  mov eax, dword [PLAYER]
  call REMAP_PLAYER
  mov eax, ecx
  pop ecx
  test eax, eax
  jmp RESUME
]]

local function rememberPatch(saved, address, size)
  saved[#saved + 1] = { address = address, bytes = core.readBytes(address, size) }
end

local function jump(saved, from, to, size)
  local bytes = { 0xE9, core.itob(to - from - 5) }
  for _ = 6, size do
    bytes[#bytes + 1] = 0x90
  end
  rememberPatch(saved, from, size)
  core.writeCode(from, bytes)
end

local function prepareRender(data, config, tick)
  local ground = scan("ground tile read", "0F B7 0C 6D ? ? ? ? 89 0D ? ? ? ? 7C 13 8B 54 24 28")
  local building = scan("building tile read", "0F B7 2C 45 ? ? ? ? 0F B7 3C 45 ? ? ? ? 8D 04 45")
  local bmap = scan("building map", "0F BF 34 75 ? ? ? ? 89 0D ? ? ? ? 89 44 24 48")
  local owner = scan("building type", "0F B7 A9 ? ? ? ? 0F BF CD 8B 0C 8D")
  local lord = scan("lord type", "8B 44 24 04 83 3C 85 ? ? ? ? FF 75 ? 69 C0")

  local gfx = core.readInteger(ground + 4)
  if core.readInteger(building + 4) ~= gfx then
    error(NAME .. ": the two tile picture reads use different maps")
  end
  if core.readInteger(owner - 4) ~= 0x32C or u8(owner - 6) ~= 0x69 then
    error(NAME .. ": unexpected building size")
  end

  core.writeByte(data + 0x10, culture(config.cathedral, 0, "cathedral"))
  core.writeByte(data + 0x11, culture(config.church, 1, "church"))
  core.writeByte(data + 0x12, culture(config.chapel, 0, "chapel"))

  local values = {
    VARS = data,
    CHURCH = GROUP_CHURCH,
    RUIN = GROUP_RUIN,
    CHAPEL = GROUP_CHAPEL,
    BMAP = core.readInteger(bmap + 4),
    OWNER = core.readInteger(owner + 3) + 4,   -- +0xD2 building type, +0xD6 owner
    LORDTYPE = lord,
    TICK = tick,
  }
  local remap = core.allocateAssembly(REMAP, values)

  local groundHook = core.allocateAssembly(HOOK_GROUND, { GFX = gfx, REMAP = remap, RESUME = ground + 8 })
  local buildingHook = core.allocateAssembly(HOOK_BUILDING,
    { GFX = gfx, REMAP = remap, RESUME = building + 8 })
  return remap, function(saved)
    jump(saved, ground, groundHook, 8)
    jump(saved, building, buildingHook, 8)
  end
end

local function installPreview(saved, remap)
  local previewGround = scan("preview ground read", "0F B7 04 6D ? ? ? ? 33 F6 85 C0 89 74 24 54 A3")
  local previewBuilding = scan("preview building read", "8D 04 45 ? ? ? ? 89 44 24 68 0F B7 00 85 C0")
  local layer = core.readInteger(previewGround + 4)
  if core.readInteger(previewBuilding + 3) ~= layer or u8(previewGround + 0x99) ~= 0xA1 then
    error(NAME .. ": the building preview reads do not look the way they should")
  end
  local player = core.readInteger(previewGround + 0x9A)
  local ground = core.allocateAssembly(HOOK_PREVIEW_GROUND, {
    LAYER = layer, PLAYER = player, REMAP_PLAYER = remap + 5, RESUME = previewGround + 8,
  })
  local building = core.allocateAssembly(HOOK_PREVIEW_BUILDING, {
    PLAYER = player, REMAP_PLAYER = remap + 5, RESUME = previewBuilding + 0xB + 5,
  })
  jump(saved, previewGround, ground, 8)
  jump(saved, previewBuilding + 0xB, building, 5)
end

-- The themed sheet --------------------------------------------------------------------------

local function prepareSheet(data, modifier)
  local loader = scan("gm loader", "53 55 8B 6C 24 0C 56 57 8B D9 33 C0")
  if u8(loader + 0x35) ~= 0xA3 or u8(loader + 0x6F) ~= 0x89 then
    error(NAME .. ": unsupported gm loader")
  end
  local addresses = {
    first = core.readInteger(loader + 0x72),
    count = core.readInteger(loader + 0x36),
    headers = core.readInteger(scan("image headers", "C1 E0 04 81 C1 ? ? ? 00 50 51") + 5),
    sizes = core.readInteger(scan("image sizes", "89 14 BD ? ? ? 00 EB 53") + 3),
    offsets = core.readInteger(scan("image offsets", "8B 2C BD ? ? ? 00 03 D7 3B FA") + 3),
  }

  local path, count, kind = sheetPath()
  if kind ~= 3 or count < SHEET_IMAGES then
    error(NAME .. ": " .. RESOURCE .. " is not a building sheet")
  end
  local resource = modifier:LoadGm1Resource(path)
  if type(resource) ~= "number" or resource < 0 then
    error(NAME .. ": gmResourceModifier could not load " .. path)
  end
  local sheetFailureReported = false
  local original
  local function loadSheet(renderer, names)
    core.writeInteger(data, 0)
    original(renderer, names)
    local saved, attempted = {}, 0
    local ok, message = pcall(function()
      local slot = core.readInteger(renderer + 0x4C)
      local nextImage = core.readInteger(renderer + 0x48)
      local base = renderer + 0x51C + GM_CHURCHES * GM_HEADER
      local baseCount = core.readInteger(base + 12)
      local source = core.readInteger(addresses.first + GM_CHURCHES * 4)
      if slot < 1 or slot >= GM_SLOTS then
        error("no free gm slot")
      end
      if core.readInteger(renderer + 0x51C + slot * GM_HEADER + 12) ~= 0 then
        error("gm slot " .. slot .. " is already used")
      end
      if core.readInteger(base + 20) ~= 3 or baseCount < SHEET_IMAGES then
        error("tile_churches.gm1 has " .. baseCount .. " pictures, needs at least " .. SHEET_IMAGES)
      end
      if nextImage + count > 66000 then
        error("no room for " .. count .. " more pictures")
      end
      local header = renderer + 0x51C + slot * GM_HEADER
      local copied = math.min(count, baseCount)
      local patches = { { header, core.readBytes(base, GM_HEADER) } }
      for index, byte in ipairs(core.itob(count)) do patches[1][2][12 + index] = byte end
      for _, item in ipairs({ { addresses.headers, 16 }, { addresses.offsets, 4 }, { addresses.sizes, 4 } }) do
        patches[#patches + 1] = { item[1] + nextImage * item[2],
          core.readBytes(item[1] + source * item[2], copied * item[2]) }
      end
      patches[#patches + 1] = { addresses.first + slot * 4, core.itob(nextImage) }
      patches[#patches + 1] = { renderer + 0x48, core.itob(nextImage + count) }
      patches[#patches + 1] = { renderer + 0x4C, core.itob(slot + 1) }
      patches[#patches + 1] = { addresses.count, core.itob(slot + 1) }
      for _, patch in ipairs(patches) do rememberPatch(saved, patch[1], #patch[2]) end
      for index, patch in ipairs(patches) do
        attempted = index
        core.writeBytes(patch[1], patch[2])
      end
      if not modifier:SetGm(slot, -1, resource, -1) then
        error("gmResourceModifier declined the themed sheet", 0)
      end
      core.writeInteger(data + 4, source)
      core.writeInteger(data + 0xC, math.min(count, baseCount))
      core.writeInteger(data, nextImage - source)
      log_(INFO, string.format("themed churches in gm slot %d (pictures %d..%d)%s", slot, nextImage,
        nextImage + count - 1, baseCount > GROUP_RUIN and "" or ", tile_churches.gm1 has no ruined cathedral"))
    end)
    if not ok then
      local restored = true
      for i = attempted, 1, -1 do
        if not pcall(core.writeBytes, saved[i].address, saved[i].bytes) then restored = false end
      end
      if not sheetFailureReported then
        sheetFailureReported = true
        local reason = restored and "" or " Some renderer changes could not be restored."
        log_(ERROR, "Themed churches are off: " .. tostring(message) .. reason)
      end
    end
  end
  return function(saved)
    local hookSize = 6
    rememberPatch(saved, loader, hookSize)
    original = core.hookCode(loadSheet, loader, 2, 1, hookSize)
    if type(original) ~= "function" then error("could not hook the graphics loader", 0) end
  end, resource
end

-- Module ------------------------------------------------------------------------------------

local function installTheme(saved, config)
  local modifier = modules.gmResourceModifier
  if modifier == nil then error("gmResourceModifier is unavailable") end
  local tick = tickCounter()
  -- VARS: +0 picture shift (0 = off), +4 first church picture, +8 tick of the lord cache,
  -- +0xC pictures to swap, +0x10..0x12 culture the game files show (cathedral, church, chapel), +0x20 lord per player
  local data = core.allocate(0x40, true)
  core.writeInteger(data + 8, 0x7FFFFFFF)            -- no tick yet: ask the game on first use
  for offset = 0x20, 0x2C, 4 do
    core.writeInteger(data + offset, 0xFFFFFFFF)
  end
  local remap, installRender = prepareRender(data, config, tick)
  local installSheet, resource = prepareSheet(data, modifier)
  local ok, problem = pcall(function()
    installRender(saved)
    installSheet(saved)
  end)
  if not ok then
    local freed, reason = pcall(modifier.FreeGm1Resource, modifier, resource)
    if not freed then log_(WARNING, tostring(reason)) end
    error(problem, 0)
  end
  return remap
end

local function tryInstall(install, input, message, partialMessage)
  local saved = {}
  local ok, result = pcall(install, saved, input)
  if ok then return result end

  local rollbackFailed = false
  for i = #saved, 1, -1 do
    local patch = saved[i]
    local restored, problem = pcall(core.writeCode, patch.address, patch.bytes, false)
    if not restored then
      rollbackFailed = true
      log_(WARNING, string.format("could not restore code at 0x%X: %s", patch.address, tostring(problem)))
    end
  end
  log_(ERROR, (rollbackFailed and partialMessage or message) .. " " .. tostring(result))
end

function themed.enable(self, config)
  config = config or {}
  if type(config) ~= "table" then
    log_(ERROR, "Invalid settings type. Using defaults.")
    return
  end
  local enabled = switch(config.enabled, "enabled")
  local preview = switch(config.preview, "preview")
  if not enabled then
    log_(INFO, "off")
    return
  end
  local remap = tryInstall(installTheme, config, "Themed churches are off. The game or graphics could not be prepared.",
    "Themed church setup failed. Some changes may still be active.")
  if remap ~= nil and preview then
    tryInstall(installPreview, remap, "The themed building preview is off.",
      "Themed building preview setup failed. Some preview changes may still be active.")
  end
end

function themed.disable(self, config)
end

return themed
