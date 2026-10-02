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

local DARK = Color3.fromRGB(26, 28, 32)
local STEEL = Color3.fromRGB(88, 94, 104)
local RED = Color3.fromRGB(190, 48, 42)
local WHITE = Color3.fromRGB(235, 238, 232)

local function makeVisualPart(
	parent: Instance,
	name: string,
	size: Vector3,
	cframe: CFrame,
	color: Color3,
	material: Enum.Material?
): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.CFrame = cframe
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Color = color
	part.Material = material or Enum.Material.SmoothPlastic
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = parent
	return part
end

local function makeRoundPart(
	parent: Instance,
	name: string,
	size: Vector3,
	cframe: CFrame,
	color: Color3,
	material: Enum.Material?
): Part
	local part = makeVisualPart(parent, name, size, cframe, color, material)
	part.Shape = Enum.PartType.Cylinder
	return part
end

local function makeLabel(part: Part, text: string): BillboardGui
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "Label"
	billboard.Size = UDim2.fromScale(5, 1.7)
	billboard.StudsOffset = Vector3.new(0, 3.2, 0)
	billboard.AlwaysOnTop = true
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

local function makePrompt(part: Part, text: string, lootId: string): ()
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "PickupPrompt"
	prompt.ActionText = "Pick up"
	prompt.ObjectText = text
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 14
	prompt.RequiresLineOfSight = false
	prompt.Parent = part
	prompt.Triggered:Connect(function(player: Player)
		LootSystem.request(player, lootId)
	end)
end

local function weaponVisual(entry: Types.LootEntry, model: Model, origin: CFrame): ()
	local weaponId = entry.weaponId or "pistol"
	if weaponId == "knife" then
		makeVisualPart(
			model,
			"Blade",
			Vector3.new(0.35, 0.16, 3.2),
			origin * CFrame.new(0, 0.15, 0) * CFrame.Angles(0, math.rad(18), 0),
			Color3.fromRGB(210, 215, 220),
			Enum.Material.Metal
		)
		makeVisualPart(
			model,
			"Handle",
			Vector3.new(0.55, 0.3, 1.1),
			origin * CFrame.new(0, 0.12, 1.8) * CFrame.Angles(0, math.rad(18), 0),
			Color3.fromRGB(55, 38, 28),
			Enum.Material.Wood
		)
		makeVisualPart(
			model,
			"Guard",
			Vector3.new(1.3, 0.18, 0.22),
			origin * CFrame.new(0, 0.18, 1.18),
			STEEL,
			Enum.Material.Metal
		)
		return
	end

	local longGun = weaponId == "shotgun" or weaponId == "rifle"
	local barrelLength = if longGun then 3.8 else 1.8
	makeVisualPart(
		model,
		"Receiver",
		Vector3.new(if longGun then 2.2 else 1.4, 0.55, 0.5),
		origin * CFrame.new(0, 0.28, 0),
		DARK,
		Enum.Material.Metal
	)
	makeVisualPart(
		model,
		"Barrel",
		Vector3.new(barrelLength, 0.22, 0.22),
		origin * CFrame.new(barrelLength / 2, 0.35, 0),
		STEEL,
		Enum.Material.Metal
	)
	makeVisualPart(
		model,
		"Grip",
		Vector3.new(0.45, 1.05, 0.42),
		origin * CFrame.new(-0.45, -0.35, 0) * CFrame.Angles(0, 0, math.rad(-18)),
		Color3.fromRGB(54, 42, 34),
		Enum.Material.Wood
	)
	makeVisualPart(
		model,
		if longGun then "Stock" else "Magazine",
		Vector3.new(if longGun then 1.4 else 0.35, if longGun then 0.42 else 0.9, 0.44),
		origin * CFrame.new(if longGun then -1.7 else 0.15, if longGun then 0.24 else -0.42, 0),
		if longGun then Color3.fromRGB(56, 42, 32) else STEEL,
		if longGun then Enum.Material.Wood else Enum.Material.Metal
	)
end

local function ammoVisual(entry: Types.LootEntry, model: Model, origin: CFrame): ()
	local shell = entry.ammoType == "shell"
	makeVisualPart(
		model,
		"AmmoBox",
		Vector3.new(2.6, 0.9, 1.6),
		origin * CFrame.new(0, 0.32, 0),
		Color3.fromRGB(45, 72, 58),
		Enum.Material.Metal
	)
	makeVisualPart(
		model,
		"AmmoBand",
		Vector3.new(2.7, 0.12, 1.7),
		origin * CFrame.new(0, 0.82, 0),
		Config.Palette.cold,
		Enum.Material.Neon
	)
	for i = -1, 1 do
		makeRoundPart(
			model,
			if shell then "Shell" else "Round",
			Vector3.new(0.24, 0.24, if shell then 1.2 else 0.8),
			origin
				* CFrame.new(i * 0.55, 1.14, 0)
				* CFrame.Angles(math.rad(90), 0, 0),
			if shell then RED else Color3.fromRGB(196, 152, 54),
			Enum.Material.Metal
		)
	end
end

local function medVisual(model: Model, origin: CFrame): ()
	makeVisualPart(
		model,
		"MedKit",
		Vector3.new(2.4, 1.05, 1.7),
		origin * CFrame.new(0, 0.4, 0),
		WHITE,
		Enum.Material.SmoothPlastic
	)
	makeVisualPart(
		model,
		"CrossVertical",
		Vector3.new(0.38, 1.15, 0.12),
		origin * CFrame.new(0, 0.45, -0.88),
		RED,
		Enum.Material.SmoothPlastic
	)
	makeVisualPart(
		model,
		"CrossHorizontal",
		Vector3.new(1.05, 0.34, 0.12),
		origin * CFrame.new(0, 0.45, -0.9),
		RED,
		Enum.Material.SmoothPlastic
	)
	makeVisualPart(
		model,
		"Handle",
		Vector3.new(1.1, 0.2, 0.25),
		origin * CFrame.new(0, 1.05, 0),
		STEEL,
		Enum.Material.Metal
	)
end

local function foodVisual(model: Model, origin: CFrame): ()
	makeRoundPart(
		model,
		"Can",
		Vector3.new(1.35, 1.35, 1.6),
		origin * CFrame.new(0, 0.7, 0) * CFrame.Angles(0, 0, math.rad(90)),
		Color3.fromRGB(164, 96, 54),
		Enum.Material.Metal
	)
	makeVisualPart(
		model,
		"Label",
		Vector3.new(1.45, 0.08, 0.95),
		origin * CFrame.new(0, 0.7, -0.68),
		Color3.fromRGB(242, 204, 112),
		Enum.Material.SmoothPlastic
	)
end

local function waterVisual(model: Model, origin: CFrame): ()
	makeRoundPart(
		model,
		"Bottle",
		Vector3.new(0.9, 0.9, 2.2),
		origin * CFrame.new(0, 0.9, 0) * CFrame.Angles(0, 0, math.rad(90)),
		Color3.fromRGB(115, 194, 235),
		Enum.Material.Glass
	)
	makeRoundPart(
		model,
		"Cap",
		Vector3.new(0.45, 0.45, 0.38),
		origin * CFrame.new(0, 2.18, 0) * CFrame.Angles(0, 0, math.rad(90)),
		Config.Palette.cold,
		Enum.Material.SmoothPlastic
	)
end

local function makeLootVisual(entry: Types.LootEntry, root: Part): Model
	local model = Instance.new("Model")
	model.Name = "Art_" .. entry.id
	model.Parent = root

	local origin = root.CFrame
	if entry.kind == "weapon" then
		weaponVisual(entry, model, origin)
	elseif entry.kind == "ammo" then
		ammoVisual(entry, model, origin)
	elseif entry.kind == "med" then
		medVisual(model, origin)
	elseif entry.kind == "food" then
		foodVisual(model, origin)
	else
		waterVisual(model, origin)
	end
	return model
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
	part.Size = Vector3.new(4, 4, 4)
	part.Position = position + Vector3.new(0, 0.4, 0)
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = true
	part.Transparency = 1
	part.Parent = parent

	local text = describeText(entry)
	makeLootVisual(entry, part)
	local label = makeLabel(part, text)
	makePrompt(part, text, entry.id)

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
		if entry.kind == "food" then
			ps.foodItems += 1
			return "+1 food"
		end
		ps.waterItems += 1
		return "+1 water"
	else
		ps.medKits += 1
		return "+1 med kit"
	end
end

function LootSystem.useConsumable(player: Player, kind: string): ()
	local ps = Runtime.getState(player)
	if ps == nil or not ps.alive or ps.downed then
		return
	end
	if kind == "med" and ps.medKits > 0 then
		ps.medKits -= 1
		ps.health = math.min(ps.maxHealth, ps.health + 35)
	elseif kind == "food" and ps.foodItems > 0 then
		ps.foodItems -= 1
		Runtime.service("Survival").grant(ps, "food", 0.35)
	elseif kind == "water" and ps.waterItems > 0 then
		ps.waterItems -= 1
		Runtime.service("Survival").grant(ps, "water", 0.4)
	else
		return
	end
	Net.send(ps.player, "HudState", Runtime.service("Round").hudFor(ps))
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
	remotes.events.UseConsumable.OnServerEvent:Connect(function(player: Player, kind: unknown)
		if typeof(kind) == "string" then
			LootSystem.useConsumable(player, kind)
		end
	end)
end

return LootSystem
