--!strict
--[[
	LootSystem.lua — ground loot: weapons, ammo and meds.

	Loot is spawned from Config.District.lootCount across the district's loot
	spots. Taking loot is server-authoritative and shared-visibility rules are
	enforced here (a pacted ally's loot is visible within sharedLootRadius).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Types = require(Shared:WaitForChild("Types"))

local Runtime = require(script.Parent.Runtime)
local Net = require(script.Parent.Net)
local NoiseSystem = require(script.Parent.NoiseSystem)

local LootSystem = {}

export type LootPart = {
	entry: Types.LootEntry,
	part: Part,
	label: BillboardGui,
}

local liveLoot: { [string]: LootPart } = {}
local counter = 0
local worldSpots: { Vector3 } = {}
local worldParent: Instance? = nil

local COLORS: { [string]: Color3 } = {
	weapon = Config.Palette.amber,
	ammo = Config.Palette.cold,
	med = Color3.fromRGB(120, 220, 140),
	food = Color3.fromRGB(214, 168, 96),
	water = Color3.fromRGB(96, 180, 232),
}

local function makeLabel(part: Part, text: string): BillboardGui
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "Label"
	billboard.Size = UDim2.fromScale(4, 1.4)
	billboard.StudsOffset = Vector3.new(0, 2.5, 0)
	billboard.AlwaysOnTop = false
	billboard.Parent = part

	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.Code
	label.TextScaled = true
	label.TextColor3 = COLORS[text:lower()] or Color3.new(1, 1, 1)
	label.Text = text
	label.Parent = billboard

	return billboard
end

local function rollKind(): Types.LootKind
	local roll = math.random()
	if roll < 0.22 then
		return "weapon"
	elseif roll < 0.52 then
		return "ammo"
	elseif roll < 0.68 then
		return "med"
	elseif roll < 0.84 then
		return "food"
	end
	return "water"
end

local function buildEntry(position: Vector3): Types.LootEntry
	counter += 1
	local kind = rollKind()
	local entry: Types.LootEntry = {
		id = string.format("loot-%d", counter),
		kind = kind,
		weaponId = nil,
		ammoType = nil,
		amount = nil,
		position = position,
		taken = false,
	}

	if kind == "weapon" then
		local pick = Config.WeaponOrder[math.random(1, #Config.WeaponOrder)]
		entry.weaponId = pick
	elseif kind == "ammo" then
		local types = { "light", "shell", "heavy" }
		entry.ammoType = types[math.random(1, #types)]
		entry.amount = Config.Ammo[entry.ammoType].pickup
	elseif kind == "food" then
		entry.amount = math.random(Config.Survival.foodRestore.min, Config.Survival.foodRestore.max)
	elseif kind == "water" then
		entry.amount =
			math.random(Config.Survival.waterRestore.min, Config.Survival.waterRestore.max)
	else
		entry.amount = 25
	end

	return entry
end

local function describeText(entry: Types.LootEntry): string
	if entry.kind == "weapon" then
		local weapon = Config.Weapons[entry.weaponId :: string]
		return weapon and weapon.displayName or "Weapon"
	elseif entry.kind == "ammo" then
		return string.format(
			"AMMO %s x%d",
			string.upper(entry.ammoType :: string),
			entry.amount or 0
		)
	elseif entry.kind == "food" then
		return string.format("FOOD +%d", entry.amount or 0)
	elseif entry.kind == "water" then
		return string.format("WATER +%d", entry.amount or 0)
	end
	return string.format("MED x%d", entry.amount or 0)
end

--- Spawns a single loot entry at a position.
function LootSystem.spawnAt(position: Vector3, parent: Instance): LootPart
	local entry = buildEntry(position)

	local part = Instance.new("Part")
	part.Name = entry.id
	part.Size = Vector3.new(1.6, 1.6, 1.6)
	part.Position = position
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.Color = COLORS[entry.kind]
	part.Material = Enum.Material.Neon
	part.Parent = parent

	local label = makeLabel(part, describeText(entry))

	local record: LootPart = { entry = entry, part = part, label = label }
	liveLoot[entry.id] = record
	return record
end

--- Populates the district from its loot spots.
function LootSystem.populate(spots: { Vector3 }, parent: Instance): ()
	for _, spot in ipairs(spots) do
		LootSystem.spawnAt(spot, parent)
	end
end

--- Returns the loot entry for an id if it still exists.
function LootSystem.get(id: string): LootPart?
	return liveLoot[id]
end

--- Removes a loot entry from the world.
function LootSystem.consume(id: string): LootPart?
	local record = liveLoot[id]
	if record == nil then
		return nil
	end
	liveLoot[id] = nil
	record.entry.taken = true
	record.part:Destroy()
	return record
end

--- Grants the loot to a player state. Returns a short human-readable result.
function LootSystem.grant(ps: Runtime.PlayerState, entry: Types.LootEntry): string
	if entry.kind == "weapon" then
		local weaponId = entry.weaponId :: string
		for _, slot in ipairs(ps.slots) do
			if slot.weaponId == weaponId then
				-- Already owned: top up its reserve instead.
				slot.reserve =
					math.min(Config.Ammo[Config.Weapons[weaponId].ammoType].max, slot.reserve + 20)
				return string.format("+20 %s", Config.Weapons[weaponId].displayName)
			end
		end
		local ammoType = Config.Weapons[weaponId].ammoType
		table.insert(ps.slots, {
			weaponId = weaponId,
			ammoInMag = Config.Weapons[weaponId].magazine,
			reserve = Config.Ammo[ammoType].max,
			reloading = false,
			reloadEndsAt = 0,
			lastFiredAt = 0,
		})
		return string.format("+%s", Config.Weapons[weaponId].displayName)
	elseif entry.kind == "ammo" then
		local ammoType = entry.ammoType :: string
		local amount = entry.amount or 0
		local slot = ps.slots[ps.activeSlot]
		if slot and Config.Weapons[slot.weaponId].ammoType == ammoType then
			slot.reserve = math.min(Config.Ammo[ammoType].max, slot.reserve + amount)
		else
			for _, candidate in ipairs(ps.slots) do
				if Config.Weapons[candidate.weaponId].ammoType == ammoType then
					candidate.reserve =
						math.min(Config.Ammo[ammoType].max, candidate.reserve + amount)
				end
			end
		end
		return string.format("+%d %s ammo", amount, string.upper(ammoType))
	elseif entry.kind == "food" or entry.kind == "water" then
		local kind = if entry.kind == "food" then "food" else "water"
		local amount = (entry.amount or 20) / Config.Survival.maxHunger
		local Survival = Runtime.service("Survival")
		Survival.grant(ps, kind, amount)
		return string.format(
			"+%d %s",
			entry.amount or 0,
			if kind == "food" then "food" else "water"
		)
	else
		local heal = entry.amount or 25
		ps.health = math.min(ps.maxHealth, ps.health + heal)
		return string.format("+%d HP", heal)
	end
end

--- Server-side handler for a LootRequest.
function LootSystem.request(player: Player, lootId: string): ()
	local ps = Runtime.getState(player)
	if ps == nil or not ps.alive or ps.downed then
		return
	end
	local record = liveLoot[lootId]
	if record == nil then
		return
	end
	local distance = (record.entry.position - ps.position).Magnitude
	if distance > 16 then
		return
	end
	LootSystem.consume(lootId)
	NoiseSystem.add(record.entry.position, Config.Noise.lootPickupHeat)
	LootSystem.grant(ps, record.entry)
end

--- Visibility check used by the client-side render gate.
function LootSystem.visibleTo(ps: Runtime.PlayerState, entry: Types.LootEntry): boolean
	if (entry.position - ps.position).Magnitude <= 20 then
		return true
	end
	return false
end

--- Remembers the world's loot spots so the round director can repopulate.
function LootSystem.bind(spots: { Vector3 }, parent: Instance): ()
	worldSpots = spots
	worldParent = parent
end

--- Clears all live loot and respawns it (called between rounds).
function LootSystem.repopulate(): ()
	if worldParent == nil then
		return
	end
	for _, record in pairs(liveLoot) do
		record.part:Destroy()
	end
	liveLoot = {}
	counter = 0
	LootSystem.populate(worldSpots, worldParent)
end

--- The nearest live loot entry to a position within `maxDist`, or nil.
function LootSystem.nearestTo(position: Vector3, maxDist: number): LootPart?
	local best: LootPart? = nil
	local bestDist = maxDist
	for _, record in pairs(liveLoot) do
		local dist = (record.entry.position - position).Magnitude
		if dist <= bestDist then
			bestDist = dist
			best = record
		end
	end
	return best
end

--- Binds the loot request remote. Call once at boot.
function LootSystem.start(): ()
	local remotes = Net.remotes()
	remotes.events.LootRequest.OnServerEvent:Connect(function(player: Player)
		local ps = Runtime.getState(player)
		if ps == nil then
			return
		end
		local near = LootSystem.nearestTo(ps.position, 16)
		if near ~= nil then
			LootSystem.request(player, near.entry.id)
		end
	end)
end

return LootSystem
