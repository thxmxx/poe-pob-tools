-- Headless PoB on a PoB XML. Run via the matching tools/pob_swapitems.sh.
local xmlPath, itemsPath, outPath, mainSkillName, targetLevel = arg[1], arg[2], arg[3], arg[4], tonumber(arg[5])
-- PoB's bundled LuaJIT accepts compound assignment (a += b, s ..= t); stock LuaJIT does not.
-- Rewrite `lhs op= expr` lines to `lhs = lhs op (expr)` when files are loaded.
local function rewrite(src)
	return (src:gsub("([^\n]*)", function(line)
		local ind, lhs, op, rhs = line:match("^(%s*)([%a_][%w_%.%[%]\"']*)%s*([%+%-%*/%%]%.?)=%s*(.-)%s*$")
		if not lhs then
			ind, lhs, op, rhs = line:match("^(%s*)([%a_][%w_%.%[%]\"']*)%s*(%.%.)=%s*(.-)%s*$")
		end
		if lhs and rhs ~= "" and not rhs:match("^=") then
			return ind .. lhs .. " = " .. lhs .. " " .. op .. " (" .. rhs .. ")"
		end
		return line
	end))
end
local l_loadfile = loadfile
function loadfile(path, ...)
	local f = io.open(path, "rb")
	if not f then return l_loadfile(path, ...) end
	local src = f:read("*a"); f:close()
	if src:find("[%+%-%*/%.]=") then src = rewrite(src) end
	return load(src, "@" .. path)
end
function dofile(path)
	local fn = assert(loadfile(path)); return fn()
end
-- same rewrite for modules loaded through require()
local loaders = package.loaders or package.searchers
table.insert(loaders, 2, function(name)
	local path = package.searchpath and package.searchpath(name, package.path)
	if not path then
		local rel = name:gsub("%.", "/")
		for pat in package.path:gmatch("[^;]+") do
			local cand = pat:gsub("%?", rel)
			local fh = io.open(cand, "rb")
			if fh then fh:close(); path = cand; break end
		end
	end
	if not path then return nil end
	local fn, err = loadfile(path)
	if not fn then error("error loading module '" .. name .. "' from file '" .. path .. "':\n\t" .. err) end
	return fn
end)

-- Headless Inflate() is a stub, so timeless jewel data (zip parts) can't be read.
-- Serve the pre-decompressed tables from tools/data/timeless/<Name>.bin instead
-- (generated once by decompressing Data/TimelessJewelData/<Name>.zip.part* with zlib).
do
	local here = debug.getinfo(1, "S").source:match("^@(.*)/[^/]*$") or "."
	package.preload["Modules.DataJewelFileLoader"] = function()
		return function(jewelTypeName)
			local f = io.open(here .. "/data/timeless/" .. jewelTypeName .. ".bin", "rb")
			if not f then return nil end
			local s = f:read("*a"); f:close(); return s
		end
	end
end
dofile("HeadlessWrapper.lua")
local dkjson = require("dkjson")
-- Replace items in a PoB XML with given raw item texts and save a new XML.
-- Usage (via pob_swapitems.sh): BUILD.xml ITEMS.json OUT.xml "Main Skill" [LEVEL]
--   ITEMS.json = {"<PoB slot name>": "<raw item text>", ...}
local function readFile(p) local f = assert(io.open(p, "rb")); local s = f:read("*a"); f:close(); return s end
loadBuildFromXML(readFile(xmlPath), "x")
runCallback("OnFrame")
local items = dkjson.decode(readFile(itemsPath))
local out = { swapped = {} }
for slotName, raw in pairs(items) do
	if raw == "" then
		-- empty string = leave the slot empty
		local slot = build.itemsTab.slots[slotName] or build.itemsTab.sockets[tonumber(slotName:match("^Jewel (%d+)$") or -1)]
		assert(slot, "no slot " .. slotName)
		slot:SetSelItemId(0)
		out.swapped[#out.swapped + 1] = slotName .. " <- (empty)"
		goto continue
	end
	raw = (raw:gsub("%[[^%]|]-|([^%]]-)%]", "%1"):gsub("%[([^%]]-)%]", "%1"))
	local item = new("Item"):Item(raw)
	item:NormaliseQuality()
	build.itemsTab:AddItem(item, true)
	local slot = build.itemsTab.slots[slotName] or build.itemsTab.sockets[tonumber(slotName:match("^Jewel (%d+)$") or -1)]
	assert(slot, "no slot " .. slotName)
	slot:SetSelItemId(item.id)
	out.swapped[#out.swapped + 1] = slotName .. " <- " .. tostring(item.name)
	::continue::
end
-- "flasks on": every filled flask slot active
for name, slot in pairs(build.itemsTab.slots) do
	if name:match("^Flask %d$") then
		slot.active = slot.selItemId ~= 0
		build.itemsTab.activeItemSet[name].active = slot.active
	end
end
build.itemsTab:PopulateSlots()
build.itemsTab:AddUndoState()
if targetLevel then build.characterLevel = targetLevel; build.characterLevelAutoMode = false end
if mainSkillName and mainSkillName ~= "" then
	for i, g in ipairs(build.skillsTab.socketGroupList) do
		for _, gem in ipairs(g.gemList) do if gem.nameSpec == mainSkillName and g.enabled ~= false then build.mainSocketGroup = i end end
	end
end
build.configTab:BuildModList()
build.buildFlag = true; runCallback("OnFrame")
local o = build.calcsTab.mainOutput
out.stats = { dps = o.CombinedDPS, ehp = o.TotalEHP, life = o.Life, es = o.EnergyShield, mana = o.Mana, manaUnres = o.ManaUnreserved,
	fire = o.FireResist, cold = o.ColdResist, light = o.LightningResist, chaos = o.ChaosResist, str = o.Str, dex = o.Dex, int = o.Int,
	reqStr = o.ReqStr, reqDex = o.ReqDex, reqInt = o.ReqInt, move = o.EffectiveMovementSpeedMod, nodes = (function() local n = 0 for _ in pairs(build.spec.allocNodes) do n = n + 1 end return n end)(), crit = o.CritChance, speed = o.Speed }
local f = assert(io.open(outPath, "w")); f:write(build:SaveDB("swap")); f:close()
print(dkjson.encode(out, { indent = true }))
