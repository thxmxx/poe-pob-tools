-- Headless Path of Building calculator for a character snapshot.
-- Run via tools/pob.sh (sets cwd to PoB/src and package.path).
-- Usage: pob_calc.lua SNAP.json [CONFIG.json] [MAIN_SKILL_NAME]
--   SNAP.json   = {items: <get-items response>, passives: <get-passive-skills response>}
--   CONFIG.json = {"conditionLowLife": true, "usePowerCharges": true, ...} (PoB ConfigOptions var names)
-- Prints a JSON object with PoB's computed output for the main skill.

local snapPath, cfgPath, mainSkillName = arg[1], arg[2], arg[3] or "Divine Retribution"

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

local function readFile(p)
	local f = assert(io.open(p, "rb")); local s = f:read("*a"); f:close(); return s
end

local snap = dkjson.decode(readFile(snapPath))
if type(snap) == "string" then snap = dkjson.decode(snap) end
local items, passives = snap.items, snap.passives
local ch = items.character

-- Shape the data like ImportTab does for the account-name import
local charData = {
	name = ch.name, class = ch.class, level = ch.level, league = ch.league,
	equipment = items.items, passives = passives, jewels = passives.items,
}

newBuild()
build.importTab:ImportItemsAndSkills(charData, true, true, true)
build.importTab:ImportPassiveTreeAndJewels(charData, true)
runCallback("OnFrame")

-- Apply config
if cfgPath and cfgPath ~= "" and cfgPath ~= "-" then
	local cfg = dkjson.decode(readFile(cfgPath))
	-- "_flasks": true -> tick every flask slot as active (the in-game "using flasks" state)
	if cfg._flasks then
		for name, slot in pairs(build.itemsTab.slots) do
			if name:match("^Flask") and slot.selItemId ~= 0 then
				slot.active = true
				build.itemsTab.activeItemSet[name].active = true
			end
		end
	end
	cfg._flasks = nil
	for k, v in pairs(cfg) do build.configTab.input[k] = v end
	build.configTab:BuildModList()
end

-- Pick the main socket group containing the requested skill
local groups = {}
for i, g in ipairs(build.skillsTab.socketGroupList) do
	local names = {}
	for _, gem in ipairs(g.gemList) do names[#names + 1] = gem.nameSpec end
	groups[#groups + 1] = { index = i, slot = g.slot, gems = names }
	for _, gem in ipairs(g.gemList) do
		if gem.nameSpec == mainSkillName then build.mainSocketGroup = i end
	end
end
build.buildFlag = true
runCallback("OnFrame")

if os.getenv("EXPORT_XML") then
	local f = assert(io.open(os.getenv("EXPORT_XML"), "w")); f:write(build:SaveDB("export")); f:close()
end
local o = build.calcsTab.mainOutput
local keys = {
	"Life", "LifeUnreserved", "LifeRecoverable", "Mana", "EnergyShield", "Str", "Dex", "Int",
	"FireResist", "ColdResist", "LightningResist", "ChaosResist",
	"FireResistOverCap", "ColdResistOverCap", "LightningResistOverCap", "ChaosResistOverCap",
	"BlockChance", "SpellBlockChance", "Armour", "Evasion", "SpellSuppressionChance",
	"LifeRegenRecovery", "TotalEHP", "PhysicalMaximumHitTaken", "ChaosMaximumHitTaken",
	"TotalDPS", "CombinedDPS", "AverageHit", "AverageDamage", "Speed", "CritChance", "CritMultiplier",
	"HitChance", "LifeCost", "ManaCost", "Cooldown", "AreaOfEffectRadiusMetres",
	"PhysicalHitAverage", "LightningHitAverage", "ChaosHitAverage", "ColdHitAverage", "FireHitAverage",
	"PowerChargesMax", "EnduranceChargesMax", "FrenzyChargesMax",
}
local out = { character = ch.name, level = ch.level, mainSkill = mainSkillName, groups = groups, stats = {}, slots = {} }
-- what PoB actually equipped (debugging item swaps)
for name, slot in pairs(build.itemsTab.slots) do
	local it = build.itemsTab.items[slot.selItemId]
	if it then out.slots[name] = (it.name or "?") .. " | " .. (it.rarity or "") .. (slot.active and " | active" or "") end
end
for _, k in ipairs(keys) do
	if o[k] ~= nil then out.stats[k] = o[k] end
end
-- Life breakdown (base / increased / more) with the individual INC sources
do
	local env = build.calcsTab.mainEnv
	local db = env.player.modDB
	local lb = { base = db:Sum("BASE", nil, "Life"), inc = db:Sum("INC", nil, "Life"), more = db:More(nil, "Life"), incSources = {} }
	for _, m in ipairs(db:Tabulate("INC", nil, "Life")) do
		lb.incSources[#lb.incSources + 1] = string.format("%+d%% %s", m.value, tostring(m.mod.source))
	end
	for _, m in ipairs(db:Tabulate("MORE", nil, "Life")) do
		lb.incSources[#lb.incSources + 1] = string.format("MORE %+d%% %s", m.value, tostring(m.mod.source))
	end
	out.lifeBreakdown = lb
end
-- Unlisted but interesting numeric outputs
out.allNumeric = {}
for k, v in pairs(o) do
	if type(v) == "number" then out.allNumeric[k] = v end
end
-- minion skills: PoB keeps the minion's numbers in a nested table
if type(o.Minion) == "table" then
	out.minion = {}
	for k, v in pairs(o.Minion) do
		if type(v) == "number" then out.minion[k] = v end
	end
end
-- per-skill reservation (which skills eat life/mana)
do
	local env = build.calcsTab.mainEnv
	out.reservations = {}
	for _, s in ipairs(env.player.activeSkillList) do
		local sd = s.skillData
		if os.getenv("RESDBG") or (sd.ManaReservedBase or 0) > 0 or (sd.LifeReservedBase or 0) > 0 then
			out.reservations[#out.reservations + 1] = string.format("%s: mana %s (%s%%) life %s (%s%%)", s.activeEffect.grantedEffect.name .. (os.getenv("RESDBG") and (" [mrp=" .. tostring(s.activeEffect.grantedEffectLevel.manaReservationPercent) .. " sup=" .. table.concat((function() local t = {} for _, e in ipairs(s.effectList or {}) do t[#t+1] = e.grantedEffect.name end return t end)(), ",") .. "]") or ""),
				tostring(sd.ManaReservedBase or 0), tostring(sd.ManaReservedPercent or 0), tostring(sd.LifeReservedBase or 0), tostring(sd.LifeReservedPercent or 0))
		end
	end
end
print(dkjson.encode(out, { indent = true }))
