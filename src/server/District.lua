--!strict
--[[
	District.lua — procedural, part-based, night-time urban district.

	Everything is generated from Config.District: a ~120x120 playable ground
	with a street grid, buildings of varied height on the blocks, amber street
	lighting, and extraction points. Re-theme the whole world by editing Config.
	No meshes are used anywhere.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Types = require(Shared:WaitForChild("Types"))

local District = {}

export type ExtractionPoint = {
	id: string,
	position: Vector3,
	pad: Part,
	marker: Part,
	light: PointLight,
}

export type DistrictHandle = {
	folder: Folder,
	propFolder: Folder,
	extractions: { ExtractionPoint },
	half: number, -- half the playable width
	origin: Vector3,
	props: { Part }, -- breakable street props
	lootSpots: { Vector3 },
}

local LIGHT = "StreetLight"

local function gridPosition(index: number, count: number, spacing: number): number
	return (index - (count - 1) / 2) * spacing
end

local function makeGround(folder: Folder, cfg: Config.DistrictConfig): Part
	local half = cfg.studsPerSide / 2
	local ground = Instance.new("Part")
	ground.Name = "Ground"
	ground.Size = Vector3.new(cfg.studsPerSide, 2, cfg.studsPerSide)
	ground.Position = Vector3.new(0, cfg.groundY - 1, 0)
	ground.Anchored = true
	ground.Color = cfg.groundColor
	ground.Material = Enum.Material.Asphalt
	ground.TopSurface = Enum.SurfaceType.Smooth
	ground.Parent = folder

	-- Invisible ceiling-less boundary walls keep players inside the district.
	local wallHeight = 120
	local function wall(name: string, size: Vector3, pos: Vector3)
		local part = Instance.new("Part")
		part.Name = name
		part.Size = size
		part.Position = pos
		part.Anchored = true
		part.Transparency = 1
		part.CanCollide = true
		part.CanQuery = false
		part.Parent = folder
	end
	wall(
		"WallN",
		Vector3.new(cfg.studsPerSide + 4, wallHeight, 1),
		Vector3.new(0, wallHeight / 2, -half)
	)
	wall(
		"WallS",
		Vector3.new(cfg.studsPerSide + 4, wallHeight, 1),
		Vector3.new(0, wallHeight / 2, half)
	)
	wall(
		"WallE",
		Vector3.new(1, wallHeight, cfg.studsPerSide + 4),
		Vector3.new(half, wallHeight / 2, 0)
	)
	wall(
		"WallW",
		Vector3.new(1, wallHeight, cfg.studsPerSide + 4),
		Vector3.new(-half, wallHeight / 2, 0)
	)

	return ground
end

local function makeStreetGrid(folder: Folder, cfg: Config.DistrictConfig): ()
	local count = math.max(2, math.floor(cfg.studsPerSide / cfg.blockSize))
	local spacing = cfg.studsPerSide / count
	local half = cfg.studsPerSide / 2

	for i = 1, count - 1 do
		local offset = -half + spacing * i
		local roadZ = Instance.new("Part")
		roadZ.Name = "StreetZ"
		roadZ.Size = Vector3.new(cfg.studsPerSide, 0.4, cfg.streetWidth)
		roadZ.Position = Vector3.new(0, cfg.groundY + 0.2, offset)
		roadZ.Anchored = true
		roadZ.Color = cfg.streetColor
		roadZ.Material = Enum.Material.Concrete
		roadZ.Parent = folder

		local roadX = Instance.new("Part")
		roadX.Name = "StreetX"
		roadX.Size = Vector3.new(cfg.streetWidth, 0.4, cfg.studsPerSide)
		roadX.Position = Vector3.new(offset, cfg.groundY + 0.2, 0)
		roadX.Anchored = true
		roadX.Color = cfg.streetColor
		roadX.Material = Enum.Material.Concrete
		roadX.Parent = folder
	end
end

local function chooseColor(cfg: Config.DistrictConfig): Color3
	return cfg.blockColors[math.random(1, #cfg.blockColors)]
end

--- Builds a single building (base + roof trim) centred on (x, z).
local function makeBuilding(
	folder: Folder,
	cfg: Config.DistrictConfig,
	x: number,
	z: number,
	width: number
): Part
	local height = cfg.buildingHeights[math.random(1, #cfg.buildingHeights)]
	local base = Instance.new("Part")
	base.Name = "Building"
	base.Size = Vector3.new(width, height, width)
	base.Position = Vector3.new(x, cfg.groundY + height / 2, z)
	base.Anchored = true
	base.Color = chooseColor(cfg)
	base.Material = Enum.Material.Concrete
	base.Parent = folder

	local roof = Instance.new("Part")
	roof.Name = "Roof"
	roof.Size = Vector3.new(width + 2, 1.5, width + 2)
	roof.Position = Vector3.new(x, cfg.groundY + height + 0.75, z)
	roof.Anchored = true
	roof.Color = cfg.roofColor
	roof.Material = Enum.Material.Slate
	roof.Parent = folder

	return base
end

local function makeBuildings(folder: Folder, cfg: Config.DistrictConfig): ()
	local count = math.max(2, math.floor(cfg.studsPerSide / cfg.blockSize))
	local spacing = cfg.studsPerSide / count
	local half = cfg.studsPerSide / 2
	local placed = 0

	for gx = 1, count do
		for gz = 1, count do
			if placed >= cfg.buildingCount then
				return
			end
			local x = -half + spacing * (gx - 0.5)
			local z = -half + spacing * (gz - 0.5)
			local width =
				math.max(8, math.min(cfg.blockSize - 4, spacing * 0.7 + math.random() * 4))
			-- Skip a couple of blocks so the streets have plazas to cross.
			if math.random() > 0.08 then
				makeBuilding(folder, cfg, x, z, width)
				placed += 1
			end
		end
	end
end

local function makeStreetLight(folder: Folder, cfg: Config.DistrictConfig, x: number, z: number): ()
	local pole = Instance.new("Part")
	pole.Name = "LightPole"
	pole.Size = Vector3.new(0.6, cfg.lightHeight, 0.6)
	pole.Position = Vector3.new(x, cfg.groundY + cfg.lightHeight / 2, z)
	pole.Anchored = true
	pole.Color = cfg.charcoal or Config.Palette.charcoal
	pole.Material = Enum.Material.Metal
	pole.Parent = folder

	local lamp = Instance.new("Part")
	lamp.Name = "Lamp"
	lamp.Shape = Enum.PartType.Ball
	lamp.Size = Vector3.new(2, 2, 2)
	lamp.Position = Vector3.new(x, cfg.groundY + cfg.lightHeight, z)
	lamp.Anchored = true
	lamp.CanCollide = false
	lamp.CanQuery = false
	lamp.Color = cfg.lightColor
	lamp.Material = Enum.Material.Neon
	lamp.Parent = folder

	local light = Instance.new("PointLight")
	light.Name = LIGHT
	light.Color = cfg.lightColor
	light.Range = 34
	light.Brightness = 2.5
	light.Shadows = true
	light.Parent = lamp
end

local function makeLighting(folder: Folder, cfg: Config.DistrictConfig): ()
	local spacing = cfg.studsPerSide / 5
	local half = cfg.studsPerSide / 2
	for ix = 0, 5 do
		for iz = 0, 5 do
			local x = -half + spacing * ix
			local z = -half + spacing * iz
			makeStreetLight(folder, cfg, x, z)
		end
	end
end

-- Breakable street props that raise noise when destroyed.
local function makeProps(folder: Folder, cfg: Config.DistrictConfig): { Part }
	local props: { Part } = {}
	local half = cfg.studsPerSide / 2
	for _ = 1, 26 do
		local part = Instance.new("Part")
		part.Name = "Prop"
		part.Size = Vector3.new(1.5, 3, 1.5)
		local x = math.random() * cfg.studsPerSide - half
		local z = math.random() * cfg.studsPerSide - half
		part.Position = Vector3.new(x, cfg.groundY + 1.5, z)
		part.Anchored = true
		part.Color = Config.Palette.cold
		part.Material = Enum.Material.Metal
		part.Parent = folder
		table.insert(props, part)
	end
	return props
end

local function makeExtraction(
	folder: Folder,
	cfg: Config.DistrictConfig,
	index: number
): ExtractionPoint
	local half = cfg.studsPerSide / 2 - 10
	local angle = (index - 1) / math.max(1, cfg.extractionCount) * math.pi * 2
	local x = math.cos(angle) * half
	local z = math.sin(angle) * half

	local pad = Instance.new("Part")
	pad.Name = string.format("Extraction_%d", index)
	pad.Shape = Enum.PartType.Cylinder
	pad.Size = Vector3.new(1, cfg.extractionRadius * 2, cfg.extractionRadius * 2)
	pad.CFrame = CFrame.new(Vector3.new(x, cfg.groundY + 0.5, z))
		* CFrame.Angles(0, 0, math.rad(90))
	pad.Anchored = true
	pad.CanCollide = false
	pad.CanQuery = false
	pad.Color = Config.Palette.amber
	pad.Material = Enum.Material.Neon
	pad.Transparency = 0.55
	pad.Parent = folder

	local marker = Instance.new("Part")
	marker.Name = "Marker"
	marker.Size = Vector3.new(2, 40, 2)
	marker.Position = Vector3.new(x, cfg.groundY + 20, z)
	marker.Anchored = true
	marker.CanCollide = false
	marker.CanQuery = false
	marker.Color = Config.Palette.amber
	marker.Material = Enum.Material.Neon
	marker.Transparency = 0.35
	marker.Parent = folder

	local light = Instance.new("PointLight")
	light.Color = Config.Palette.amber
	light.Range = cfg.extractionRadius * 2
	light.Brightness = 3
	light.Parent = marker

	return {
		id = string.format("EX-%d", index),
		position = Vector3.new(x, cfg.groundY, z),
		pad = pad,
		marker = marker,
		light = light,
	}
end

local function makeLootSpots(cfg: Config.DistrictConfig): { Vector3 }
	local spots: { Vector3 } = {}
	local half = cfg.studsPerSide / 2 - 6
	for _ = 1, cfg.lootCount do
		local x = math.random() * cfg.studsPerSide - cfg.studsPerSide / 2
		local z = math.random() * cfg.studsPerSide - cfg.studsPerSide / 2
		x = math.clamp(x, -half, half)
		z = math.clamp(z, -half, half)
		table.insert(spots, Vector3.new(x, cfg.groundY + 2, z))
	end
	return spots
end

--- Generates the whole district and parents it under a workspace folder.
function District.generate(parent: Instance): DistrictHandle
	local cfg = Config.District
	local folder = Instance.new("Folder")
	folder.Name = "District"
	folder.Parent = parent

	makeGround(folder, cfg)
	makeStreetGrid(folder, cfg)
	makeBuildings(folder, cfg)
	makeLighting(folder, cfg)

	local propFolder = Instance.new("Folder")
	propFolder.Name = "Props"
	propFolder.Parent = folder
	local props = makeProps(propFolder, cfg)

	local extractions: { ExtractionPoint } = {}
	for i = 1, cfg.extractionCount do
		table.insert(extractions, makeExtraction(folder, cfg, i))
	end

	return {
		folder = folder,
		propFolder = propFolder,
		extractions = extractions,
		half = cfg.studsPerSide / 2,
		origin = Vector3.new(0, cfg.groundY, 0),
		props = props,
		lootSpots = makeLootSpots(cfg),
	}
end

--- Sends a list of extraction states over the wire.
function District.describeExtractions(handle: DistrictHandle): { Types.ExtractionPointState }
	local out: { Types.ExtractionPointState } = {}
	for _, point in ipairs(handle.extractions) do
		table.insert(out, {
			id = point.id,
			position = point.position,
			open = false,
			openAt = 0,
			closeAt = 0,
		})
	end
	return out
end

return District
