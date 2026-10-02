--!strict
--[[
	District.lua — procedural, part-based, night-time urban district.

	Everything is generated from Config.District: a 240x240 playable ground with
	a street grid, SIDEWALKS, lane markings, and a grid of city blocks.

	Each block holds ONE enterable building: four walls with a real doorway you
	can walk through, lit windows, interior floor bands, interior lighting and a
	roof with a parapet. The district centre holds a taller landmark that shelters
	THE PAYLOAD — the round's objective.

	A raised, anchored SpawnLocation pad sits on the south apron: players drop
	onto it, so nobody can fall through the ground on join. Re-theme the whole
	world by editing Config. No meshes are used anywhere.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Lighting = game:GetService("Lighting")

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

export type PayloadHandle = {
	model: Model,
	core: BasePart,
	pad: BasePart,
	position: Vector3,
}

export type DistrictHandle = {
	folder: Folder,
	propFolder: Folder,
	extractions: { ExtractionPoint },
	half: number, -- half the playable width
	origin: Vector3,
	props: { Part }, -- breakable street props
	lootSpots: { Vector3 },
	spawnPosition: Vector3, -- anchored spawn pad (floor-collapse fix)
	payload: PayloadHandle,
	landmark: Model,
}

local LIGHT = "StreetLight"

-- ---------------------------------------------------------------------------
-- Small construction helpers
-- ---------------------------------------------------------------------------

local function gridPosition(index: number, count: number, spacing: number): number
	return (index - (count - 1) / 2) * spacing
end

--- Creates an anchored part with defaults and parents it immediately.
local function mk(parent: Instance, props: { [string]: any }): Part
	local part = Instance.new("Part")
	part.Anchored = true
	part.CanCollide = true
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Material = Enum.Material.Concrete
	for key, value in pairs(props) do
		(part :: any)[key] = value
	end
	part.Parent = parent
	return part
end

-- ---------------------------------------------------------------------------
-- Night sky / atmosphere — without this the district reads as a black void.
-- ---------------------------------------------------------------------------

local function makeSky(): ()
	Lighting.ClockTime = 0
	Lighting.Brightness = 2.4
	Lighting.Ambient = Color3.fromRGB(28, 30, 40)
	Lighting.OutdoorAmbient = Color3.fromRGB(46, 52, 70)
	Lighting.EnvironmentDiffuseScale = 0.5
	Lighting.EnvironmentSpecularScale = 0.3
	Lighting.GlobalShadows = true
	Lighting.FogColor = Color3.fromRGB(22, 26, 38)
	Lighting.FogStart = 120
	Lighting.FogEnd = 620

	local existing = Lighting:FindFirstChildOfClass("Atmosphere")
	local atmosphere = existing or Instance.new("Atmosphere")
	atmosphere.Density = 0.36
	atmosphere.Offset = 0.1
	atmosphere.Color = Color3.fromRGB(120, 130, 160)
	atmosphere.Decay = Color3.fromRGB(50, 60, 90)
	atmosphere.Glare = 0.2
	atmosphere.Haze = 1.6
	atmosphere.Parent = Lighting

	local bloom = Lighting:FindFirstChildOfClass("BloomEffect") or Instance.new("BloomEffect")
	bloom.Intensity = 0.7
	bloom.Size = 24
	bloom.Threshold = 1.1
	bloom.Parent = Lighting

	local colorCorrection = Lighting:FindFirstChildOfClass("ColorCorrectionEffect")
		or Instance.new("ColorCorrectionEffect")
	colorCorrection.Brightness = 0.02
	colorCorrection.Contrast = 0.12
	colorCorrection.Saturation = -0.05
	colorCorrection.TintColor = Color3.fromRGB(232, 238, 255)
	colorCorrection.Parent = Lighting
end

-- ---------------------------------------------------------------------------
-- Ground, boundary walls and the spawn pad
-- ---------------------------------------------------------------------------

local function makeGround(folder: Folder, cfg: Config.DistrictConfig): Part
	local half = cfg.studsPerSide / 2
	local ground = mk(folder, {
		Name = "Ground",
		Size = Vector3.new(cfg.studsPerSide, 2, cfg.studsPerSide),
		Position = Vector3.new(0, cfg.groundY - 1, 0),
		Color = cfg.groundColor,
		Material = Enum.Material.Asphalt,
	})

	-- Invisible boundary walls keep players inside the district.
	local wallHeight = 160
	local function wall(name: string, size: Vector3, pos: Vector3)
		local part = mk(folder, {
			Name = name,
			Size = size,
			Position = pos,
			Transparency = 1,
			CanCollide = true,
			CanQuery = false,
		})
		part.Material = Enum.Material.SmoothPlastic
	end
	wall(
		"WallN",
		Vector3.new(cfg.studsPerSide + 6, wallHeight, 2),
		Vector3.new(0, wallHeight / 2, -half)
	)
	wall(
		"WallS",
		Vector3.new(cfg.studsPerSide + 6, wallHeight, 2),
		Vector3.new(0, wallHeight / 2, half)
	)
	wall(
		"WallE",
		Vector3.new(2, wallHeight, cfg.studsPerSide + 6),
		Vector3.new(half, wallHeight / 2, 0)
	)
	wall(
		"WallW",
		Vector3.new(2, wallHeight, cfg.studsPerSide + 6),
		Vector3.new(-half, wallHeight / 2, 0)
	)

	return ground
end

--- A raised, anchored SpawnLocation on the south apron. This is where players
--- drop in, and it is the floor-collapse fix: a solid, non-collapsing surface
--- above the ground instead of a bare teleport into empty air.
local function makeSpawnPad(folder: Folder, cfg: Config.DistrictConfig): Vector3
	local pos = Vector3.new(0, cfg.groundY + 0.5, cfg.studsPerSide / 2 - 20)
	local pad = Instance.new("SpawnLocation")
	pad.Name = "SpawnPad"
	pad.Size = Vector3.new(30, 1, 30)
	pad.Position = pos
	pad.Anchored = true
	pad.CanCollide = true
	pad.Color = cfg.trimColor
	pad.Material = Enum.Material.Metal
	pad.TopSurface = Enum.SurfaceType.Smooth
	pad.Neutral = true
	pad.Enabled = true
	pad.Duration = 0
	pad.Parent = folder

	-- A neon rim so the pad is unmistakable at night.
	local rim = mk(folder, {
		Name = "SpawnRim",
		Size = Vector3.new(30, 0.4, 30),
		Position = pos + Vector3.new(0, 0.55, 0),
		Color = cfg.lightColor,
		Material = Enum.Material.Neon,
		Transparency = 0.35,
		CanCollide = false,
		CanQuery = false,
	})
	rim.CanTouch = false

	local light = Instance.new("PointLight")
	light.Color = cfg.lightColor
	light.Range = 46
	light.Brightness = 3
	light.Parent = pad

	return pos + Vector3.new(0, 3, 0)
end

-- ---------------------------------------------------------------------------
-- Streets: asphalt ribbons with sidewalks and dashed lane markings.
-- ---------------------------------------------------------------------------

local function makeStreetGrid(folder: Folder, cfg: Config.DistrictConfig): ()
	local count = math.max(2, math.floor(cfg.studsPerSide / cfg.blockSize))
	local spacing = cfg.studsPerSide / count
	local half = cfg.studsPerSide / 2
	local sw = cfg.sidewalkWidth

	local function road(
		name: string,
		size: Vector3,
		pos: Vector3,
		material: Enum.Material,
		color: Color3
	)
		mk(folder, {
			Name = name,
			Size = size,
			Position = pos,
			Color = color,
			Material = material,
			CanCollide = false,
			CanQuery = false,
			CanTouch = false,
		})
	end

	for i = 1, count - 1 do
		local offset = -half + spacing * i

		road(
			"StreetZ",
			Vector3.new(cfg.studsPerSide, 0.4, cfg.streetWidth),
			Vector3.new(0, cfg.groundY + 0.2, offset),
			Enum.Material.Asphalt,
			cfg.streetColor
		)
		road(
			"SidewalkZ_N",
			Vector3.new(cfg.studsPerSide, 0.5, sw),
			Vector3.new(0, cfg.groundY + 0.35, offset - cfg.streetWidth / 2 - sw / 2),
			Enum.Material.Concrete,
			cfg.sidewalkColor
		)
		road(
			"SidewalkZ_S",
			Vector3.new(cfg.studsPerSide, 0.5, sw),
			Vector3.new(0, cfg.groundY + 0.35, offset + cfg.streetWidth / 2 + sw / 2),
			Enum.Material.Concrete,
			cfg.sidewalkColor
		)

		road(
			"StreetX",
			Vector3.new(cfg.streetWidth, 0.4, cfg.studsPerSide),
			Vector3.new(offset, cfg.groundY + 0.2, 0),
			Enum.Material.Asphalt,
			cfg.streetColor
		)
		road(
			"SidewalkX_E",
			Vector3.new(sw, 0.5, cfg.studsPerSide),
			Vector3.new(offset + cfg.streetWidth / 2 + sw / 2, cfg.groundY + 0.35, 0),
			Enum.Material.Concrete,
			cfg.sidewalkColor
		)
		road(
			"SidewalkX_W",
			Vector3.new(sw, 0.5, cfg.studsPerSide),
			Vector3.new(offset - cfg.streetWidth / 2 - sw / 2, cfg.groundY + 0.35, 0),
			Enum.Material.Concrete,
			cfg.sidewalkColor
		)

		-- Dashed centre lane markings down both roads.
		local dash = 5
		local gap = 5
		local step = dash + gap
		local n = math.floor(cfg.studsPerSide / step)
		for d = 0, n do
			local along = -half + d * step + dash / 2
			road(
				"LaneZ",
				Vector3.new(0.5, 0.6, dash),
				Vector3.new(along, cfg.groundY + 0.45, offset),
				Enum.Material.SmoothPlastic,
				cfg.laneColor
			)
			road(
				"LaneX",
				Vector3.new(dash, 0.6, 0.5),
				Vector3.new(offset, cfg.groundY + 0.45, along),
				Enum.Material.SmoothPlastic,
				cfg.laneColor
			)
		end
	end
end

local function chooseColor(cfg: Config.DistrictConfig): Color3
	return cfg.blockColors[math.random(1, #cfg.blockColors)]
end

-- ---------------------------------------------------------------------------
-- Buildings
-- ---------------------------------------------------------------------------

local SIDES = { "N", "S", "E", "W" }

--- A full solid wall on `side` of a building centred on (x, z).
local function addWall(
	model: Model,
	cfg: Config.DistrictConfig,
	x: number,
	z: number,
	w: number,
	h: number,
	side: string,
	color: Color3
): ()
	local t = cfg.wallThickness
	if side == "N" then
		mk(model, {
			Name = "WallN",
			Size = Vector3.new(w, h, t),
			Position = Vector3.new(x, h / 2, z - w / 2 + t / 2),
			Color = color,
		})
	elseif side == "S" then
		mk(model, {
			Name = "WallS",
			Size = Vector3.new(w, h, t),
			Position = Vector3.new(x, h / 2, z + w / 2 - t / 2),
			Color = color,
		})
	elseif side == "E" then
		mk(model, {
			Name = "WallE",
			Size = Vector3.new(t, h, w),
			Position = Vector3.new(x + w / 2 - t / 2, h / 2, z),
			Color = color,
		})
	else
		mk(model, {
			Name = "WallW",
			Size = Vector3.new(t, h, w),
			Position = Vector3.new(x - w / 2 + t / 2, h / 2, z),
			Color = color,
		})
	end
end

--- A wall on `side` with a doorway carved through it (two jambs + a lintel),
--- so players can walk straight in.
local function addDoorWall(
	model: Model,
	cfg: Config.DistrictConfig,
	x: number,
	z: number,
	w: number,
	h: number,
	side: string,
	color: Color3
): ()
	local t = cfg.wallThickness
	local doorW = cfg.doorWidth
	local doorH = cfg.doorHeight
	local jamb = math.max(1, (w - doorW) / 2)

	if side == "N" or side == "S" then
		local zz = if side == "N" then z - w / 2 + t / 2 else z + w / 2 - t / 2
		mk(model, {
			Name = "JambL",
			Size = Vector3.new(jamb, h, t),
			Position = Vector3.new(x - w / 2 + jamb / 2, h / 2, zz),
			Color = color,
		})
		mk(model, {
			Name = "JambR",
			Size = Vector3.new(jamb, h, t),
			Position = Vector3.new(x + w / 2 - jamb / 2, h / 2, zz),
			Color = color,
		})
		mk(model, {
			Name = "Lintel",
			Size = Vector3.new(doorW, h - doorH, t),
			Position = Vector3.new(x, doorH + (h - doorH) / 2, zz),
			Color = color,
		})
	else
		local xx = if side == "E" then x + w / 2 - t / 2 else x - w / 2 + t / 2
		mk(model, {
			Name = "JambL",
			Size = Vector3.new(t, h, jamb),
			Position = Vector3.new(xx, h / 2, z - w / 2 + jamb / 2),
			Color = color,
		})
		mk(model, {
			Name = "JambR",
			Size = Vector3.new(t, h, jamb),
			Position = Vector3.new(xx, h / 2, z + w / 2 - jamb / 2),
			Color = color,
		})
		mk(model, {
			Name = "Lintel",
			Size = Vector3.new(t, h - doorH, doorW),
			Position = Vector3.new(xx, doorH + (h - doorH) / 2, z),
			Color = color,
		})
	end

	-- Threshold plate + an entrance glow so the doorway reads clearly.
	local thresh = mk(model, {
		Name = "Threshold",
		Size = if side == "N" or side == "S"
			then Vector3.new(doorW, 0.5, t + 1)
			else Vector3.new(t + 1, 0.5, doorW),
		Color = cfg.trimColor,
		Material = Enum.Material.DiamondPlate,
		CanCollide = false,
		CanQuery = false,
	})
	thresh.CanTouch = false

	local glowPos = if side == "N"
		then Vector3.new(x, 1, z - w / 2)
		elseif side == "S" then Vector3.new(x, 1, z + w / 2)
		elseif side == "E" then Vector3.new(x + w / 2, 1, z)
		else Vector3.new(x - w / 2, 1, z)
	local glow = mk(model, {
		Name = "DoorGlow",
		Size = Vector3.new(1, 1, 1),
		Position = glowPos,
		Color = cfg.lightColor,
		Material = Enum.Material.Neon,
		Transparency = 0.2,
		CanCollide = false,
		CanQuery = false,
	})
	glow.CanTouch = false
	local light = Instance.new("PointLight")
	light.Color = cfg.lightColor
	light.Range = 22
	light.Brightness = 1.6
	light.Parent = glow
end

--- Lit windows on every side and every floor (skipping the doorway column).
local function addWindows(
	model: Model,
	cfg: Config.DistrictConfig,
	x: number,
	z: number,
	w: number,
	h: number,
	floorCount: number,
	bandH: number,
	doorSides: { string }
): ()
	local t = cfg.wallThickness
	local ww = cfg.windowWidth
	local wh = cfg.windowHeight
	local offsets = { -w * 0.26, w * 0.26 }

	local function isDoor(side: string, f: number, off: number): boolean
		if f ~= 0 then
			return false
		end
		for _, s in ipairs(doorSides) do
			if s == side and math.abs(off) < cfg.doorWidth / 2 then
				return true
			end
		end
		return false
	end

	for f = 0, floorCount - 1 do
		local yc = f * bandH + bandH * 0.55
		if yc + wh / 2 > h - 1 then
			continue
		end
		for _, side in ipairs(SIDES) do
			for _, off in ipairs(offsets) do
				if not isDoor(side, f, off) then
					local frame: Part
					local glass: Part
					if side == "N" or side == "S" then
						local zz = if side == "N" then z - w / 2 + t / 2 else z + w / 2 - t / 2
						frame = mk(model, {
							Name = "WindowFrame",
							Size = Vector3.new(ww + 1.2, wh + 1.2, t * 0.4),
							Position = Vector3.new(x + off, yc, zz),
							Color = cfg.trimColor,
							Material = Enum.Material.Metal,
							CanCollide = false,
							CanQuery = false,
						})
						glass = mk(model, {
							Name = "Window",
							Size = Vector3.new(ww, wh, t * 0.5),
							Position = Vector3.new(
								x + off,
								yc,
								zz + (if side == "N" then 0.15 else -0.15)
							),
							Color = cfg.glassColor,
							Material = Enum.Material.Neon,
							Transparency = 0.3,
							CanCollide = false,
							CanQuery = false,
						})
					else
						local xx = if side == "E" then x + w / 2 - t / 2 else x - w / 2 + t / 2
						frame = mk(model, {
							Name = "WindowFrame",
							Size = Vector3.new(t * 0.4, wh + 1.2, ww + 1.2),
							Position = Vector3.new(xx, yc, z + off),
							Color = cfg.trimColor,
							Material = Enum.Material.Metal,
							CanCollide = false,
							CanQuery = false,
						})
						glass = mk(model, {
							Name = "Window",
							Size = Vector3.new(t * 0.5, wh, ww),
							Position = Vector3.new(
								xx + (if side == "E" then -0.15 else 0.15),
								yc,
								z + off
							),
							Color = cfg.glassColor,
							Material = Enum.Material.Neon,
							Transparency = 0.3,
							CanCollide = false,
							CanQuery = false,
						})
					end
					frame.CanTouch = false
					glass.CanTouch = false
				end
			end
		end
	end
end

--- Builds one enterable building centred on (x, z).
--- doorSides: which walls get a doorway. openInterior: skip floor slabs (atrium).
local function makeBuilding(
	folder: Folder,
	cfg: Config.DistrictConfig,
	x: number,
	z: number,
	width: number,
	height: number,
	doorSides: { string },
	openInterior: boolean
): Model
	local model = Instance.new("Model")
	model.Name = "Building"
	model.Parent = folder

	local color = chooseColor(cfg)
	local w = width
	local h = height
	local t = cfg.wallThickness

	local function hasDoor(side: string): boolean
		for _, s in ipairs(doorSides) do
			if s == side then
				return true
			end
		end
		return false
	end

	for _, side in ipairs(SIDES) do
		if hasDoor(side) then
			addDoorWall(model, cfg, x, z, w, h, side, color)
		else
			addWall(model, cfg, x, z, w, h, side, color)
		end
	end

	local floorCount = math.clamp(math.floor(h / cfg.floorBandEvery), 2, 4)
	local bandH = h / floorCount

	-- Interior floor slabs (ground floor is the ground itself).
	if not openInterior then
		for f = 1, floorCount - 1 do
			local y = f * bandH
			mk(model, {
				Name = "FloorSlab",
				Size = Vector3.new(w - 2 * t, 0.6, w - 2 * t),
				Position = Vector3.new(x, y, z),
				Color = cfg.interiorColor,
				Material = Enum.Material.WoodPlanks,
			})
		end
	end

	-- Interior lighting: a glowing ceiling puck per floor band.
	local lights = if openInterior then math.min(floorCount, 2) else floorCount
	for f = 1, lights do
		local y = f * bandH - 0.6
		local puck = mk(model, {
			Name = "CeilingLight",
			Size = Vector3.new(2.4, 0.3, 2.4),
			Position = Vector3.new(x, y, z),
			Color = Color3.fromRGB(255, 226, 180),
			Material = Enum.Material.Neon,
			CanCollide = false,
			CanQuery = false,
		})
		puck.CanTouch = false
		local light = Instance.new("PointLight")
		light.Color = Color3.fromRGB(255, 224, 176)
		light.Range = 30
		light.Brightness = 2.2
		light.Parent = puck
	end

	-- Exterior floor bands: thin rings that read as storeys from the street.
	for f = 1, floorCount - 1 do
		local y = f * bandH
		mk(model, {
			Name = "BandN",
			Size = Vector3.new(w + 0.8, 0.5, t + 0.6),
			Position = Vector3.new(x, y, z - w / 2 + t / 2),
			Color = cfg.trimColor,
			Material = Enum.Material.Metal,
			CanCollide = false,
			CanQuery = false,
		})
		mk(model, {
			Name = "BandS",
			Size = Vector3.new(w + 0.8, 0.5, t + 0.6),
			Position = Vector3.new(x, y, z + w / 2 - t / 2),
			Color = cfg.trimColor,
			Material = Enum.Material.Metal,
			CanCollide = false,
			CanQuery = false,
		})
		mk(model, {
			Name = "BandE",
			Size = Vector3.new(t + 0.6, 0.5, w + 0.8),
			Position = Vector3.new(x + w / 2 - t / 2, y, z),
			Color = cfg.trimColor,
			Material = Enum.Material.Metal,
			CanCollide = false,
			CanQuery = false,
		})
		mk(model, {
			Name = "BandW",
			Size = Vector3.new(t + 0.6, 0.5, w + 0.8),
			Position = Vector3.new(x - w / 2 + t / 2, y, z),
			Color = cfg.trimColor,
			Material = Enum.Material.Metal,
			CanCollide = false,
			CanQuery = false,
		})
	end

	addWindows(model, cfg, x, z, w, h, floorCount, bandH, doorSides)

	-- Roof + parapet + a rooftop unit so the skyline is not a flat lid.
	mk(model, {
		Name = "Roof",
		Size = Vector3.new(w + 1.4, 1.2, w + 1.4),
		Position = Vector3.new(x, h + 0.6, z),
		Color = cfg.roofColor,
		Material = Enum.Material.Slate,
	})
	local p = cfg.roofParapet
	mk(model, {
		Name = "ParapetN",
		Size = Vector3.new(w + 1.4, p, 0.8),
		Position = Vector3.new(x, h + 1.2 + p / 2, z - w / 2 - 0.3),
		Color = cfg.trimColor,
	})
	mk(model, {
		Name = "ParapetS",
		Size = Vector3.new(w + 1.4, p, 0.8),
		Position = Vector3.new(x, h + 1.2 + p / 2, z + w / 2 + 0.3),
		Color = cfg.trimColor,
	})
	mk(model, {
		Name = "ParapetE",
		Size = Vector3.new(0.8, p, w + 1.4),
		Position = Vector3.new(x + w / 2 + 0.3, h + 1.2 + p / 2, z),
		Color = cfg.trimColor,
	})
	mk(model, {
		Name = "ParapetW",
		Size = Vector3.new(0.8, p, w + 1.4),
		Position = Vector3.new(x - w / 2 - 0.3, h + 1.2 + p / 2, z),
		Color = cfg.trimColor,
	})

	if not openInterior and math.random() > 0.4 then
		mk(model, {
			Name = "RooftopUnit",
			Size = Vector3.new(w * 0.3, 2.4, w * 0.3),
			Position = Vector3.new(x + w * 0.15, h + 2.4, z - w * 0.15),
			Color = cfg.trimColor,
			Material = Enum.Material.Metal,
		})
	end

	return model
end

--- Places one enterable building per block, each with a street-facing doorway.
local function makeBuildings(folder: Folder, cfg: Config.DistrictConfig): Model
	local count = math.max(2, math.floor(cfg.studsPerSide / cfg.blockSize))
	local spacing = cfg.studsPerSide / count
	local half = cfg.studsPerSide / 2
	local width = math.max(18, cfg.blockSize - cfg.streetWidth - 2 * cfg.sidewalkWidth - 6)

	local centreIndex = math.ceil(count / 2) -- block reserved for the landmark
	local lastModel: Model? = nil

	for gx = 1, count do
		for gz = 1, count do
			local isCentre = gx == centreIndex and gz == centreIndex
			if not isCentre then
				local x = -half + spacing * (gx - 0.5)
				local z = -half + spacing * (gz - 0.5)
				local side = SIDES[math.random(1, #SIDES)]
				local height = cfg.buildingHeights[math.random(1, #cfg.buildingHeights)]
				lastModel = makeBuilding(folder, cfg, x, z, width, height, { side }, false)
			end
		end
	end

	return lastModel :: Model
end

--- The central landmark: a tall hall open on all four sides that shelters the
--- payload. Its glowing core is visible across the district.
local function makeLandmark(folder: Folder, cfg: Config.DistrictConfig): (Model, PayloadHandle)
	local at = Config.Purpose.landmarkPosition
	local x, z = at.X, at.Z
	local width = math.max(34, cfg.blockSize - cfg.streetWidth - 2 * cfg.sidewalkWidth - 2)
	local height = 82

	local model = makeBuilding(folder, cfg, x, z, width, height, SIDES, true)
	model.Name = "Landmark"

	-- Mezzanine ring: a balcony band that gives the hall verticality.
	local y = height * 0.42
	local ringW = width * 0.72
	local t = cfg.wallThickness
	local ringColor = cfg.trimColor
	for _, side in ipairs(SIDES) do
		if side == "N" or side == "S" then
			mk(model, {
				Name = "Mezzanine",
				Size = Vector3.new(ringW, 0.8, 7),
				Position = Vector3.new(
					x,
					y,
					z + (if side == "N" then -width / 2 + 12 else width / 2 - 12)
				),
				Color = ringColor,
				Material = Enum.Material.Metal,
			})
		else
			mk(model, {
				Name = "Mezzanine",
				Size = Vector3.new(7, 0.8, ringW),
				Position = Vector3.new(
					x + (if side == "W" then -width / 2 + 12 else width / 2 - 12),
					y,
					z
				),
				Color = ringColor,
				Material = Enum.Material.Metal,
			})
		end
	end
	-- Two stair flights up to the mezzanine so it is reachable.
	for i = 0, 11 do
		mk(model, {
			Name = "Stair",
			Size = Vector3.new(t + 6, 1, 1.6),
			Position = Vector3.new(x - width * 0.3, 1 + i * 1.4, z + width * 0.28 - i * 1.6),
			Color = ringColor,
			Material = Enum.Material.DiamondPlate,
		})
	end

	-- Payload pad on the hall floor.
	local pad = Instance.new("Part")
	pad.Name = "PayloadPad"
	pad.Shape = Enum.PartType.Cylinder
	pad.Size = Vector3.new(1, 16, 16)
	pad.CFrame = CFrame.new(Vector3.new(x, cfg.groundY + 0.6, z))
		* CFrame.Angles(0, 0, math.rad(90))
	pad.Anchored = true
	pad.CanCollide = false
	pad.CanQuery = false
	pad.Color = Config.Palette.amber
	pad.Material = Enum.Material.Neon
	pad.Transparency = 0.5
	pad.Parent = model

	local core = mk(model, {
		Name = "PayloadCore",
		Size = Vector3.new(3.2, 3.2, 3.2),
		Position = Vector3.new(x, cfg.groundY + 3.2, z),
		Color = Config.Palette.amber,
		Material = Enum.Material.Neon,
		CanCollide = false,
		CanQuery = false,
		Shape = Enum.PartType.Ball,
	})
	local beacon = Instance.new("PointLight")
	beacon.Color = Config.Palette.amber
	beacon.Range = Config.Purpose.beaconRange
	beacon.Brightness = Config.Purpose.beaconBrightness
	beacon.Shadows = true
	beacon.Parent = core

	return model,
		{
			model = model,
			core = core,
			pad = pad,
			position = Vector3.new(x, cfg.groundY + 3.2, z),
		}
end

-- ---------------------------------------------------------------------------
-- Street lighting
-- ---------------------------------------------------------------------------

local function makeStreetLight(folder: Folder, cfg: Config.DistrictConfig, x: number, z: number): ()
	local pole = mk(folder, {
		Name = "LightPole",
		Size = Vector3.new(0.7, cfg.lightHeight, 0.7),
		Position = Vector3.new(x, cfg.groundY + cfg.lightHeight / 2, z),
		Color = cfg.charcoal or Config.Palette.charcoal,
		Material = Enum.Material.Metal,
	})
	local lamp = mk(folder, {
		Name = "Lamp",
		Size = Vector3.new(2, 2, 2),
		Position = Vector3.new(x, cfg.groundY + cfg.lightHeight, z),
		Color = cfg.lightColor,
		Material = Enum.Material.Neon,
		CanCollide = false,
		CanQuery = false,
		Shape = Enum.PartType.Ball,
	})
	local light = Instance.new("PointLight")
	light.Name = LIGHT
	light.Color = cfg.lightColor
	light.Range = 42
	light.Brightness = 2.6
	light.Shadows = true
	light.Parent = lamp
end

local function makeLighting(folder: Folder, cfg: Config.DistrictConfig): ()
	local spacing = cfg.studsPerSide / 6
	local half = cfg.studsPerSide / 2
	for ix = 0, 6 do
		for iz = 0, 6 do
			local x = -half + spacing * ix
			local z = -half + spacing * iz
			makeStreetLight(folder, cfg, x, z)
		end
	end
end

-- ---------------------------------------------------------------------------
-- Breakable street props
-- ---------------------------------------------------------------------------

local function makeProps(folder: Folder, cfg: Config.DistrictConfig): { Part }
	local props: { Part } = {}
	local half = cfg.studsPerSide / 2 - 6
	local kinds = {
		Vector3.new(2, 2, 2),
		Vector3.new(3, 1.2, 1.2),
		Vector3.new(1.2, 3, 1.2),
		Vector3.new(4, 3, 2),
	}
	for i = 1, 60 do
		local size = kinds[math.random(1, #kinds)]
		local part = mk(folder, {
			Name = "Prop",
			Size = size,
			Position = Vector3.new(
				math.random() * half * 2 - half,
				cfg.groundY + size.Y / 2,
				math.random() * half * 2 - half
			),
			Color = if i % 3 == 0 then Config.Palette.cold else Config.Palette.charcoal,
			Material = Enum.Material.Metal,
		})
		table.insert(props, part)
	end
	return props
end

-- ---------------------------------------------------------------------------
-- Extraction points
-- ---------------------------------------------------------------------------

local function makeExtraction(
	folder: Folder,
	cfg: Config.DistrictConfig,
	index: number
): ExtractionPoint
	local half = cfg.studsPerSide / 2 - 14
	local angle = (index - 1) / math.max(1, cfg.extractionCount) * math.pi * 2
	local x = math.cos(angle) * half
	local z = math.sin(angle) * half

	local pad = Instance.new("Part")
	pad.Name = string.format("Extraction_%d", index)
	pad.Shape = Enum.PartType.Cylinder
	pad.Size = Vector3.new(1, cfg.extractionRadius * 2, cfg.extractionRadius * 2)
	pad.CFrame = CFrame.new(Vector3.new(x, cfg.groundY + 0.6, z))
		* CFrame.Angles(0, 0, math.rad(90))
	pad.Anchored = true
	pad.CanCollide = false
	pad.CanQuery = false
	pad.Color = Config.Palette.amber
	pad.Material = Enum.Material.Neon
	pad.Transparency = 0.55
	pad.Parent = folder

	local marker = mk(folder, {
		Name = "Marker",
		Size = Vector3.new(2, 60, 2),
		Position = Vector3.new(x, cfg.groundY + 30, z),
		Color = Config.Palette.amber,
		Material = Enum.Material.Neon,
		Transparency = 0.35,
		CanCollide = false,
		CanQuery = false,
	})
	local light = Instance.new("PointLight")
	light.Color = Config.Palette.amber
	light.Range = cfg.extractionRadius * 2.5
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
	local clusters = {
		Vector3.new(-36, 0, 18), -- shop/apartment side
		Vector3.new(34, 0, 24), -- police/storefront side
		Vector3.new(-28, 0, -34), -- alley cache
		Vector3.new(28, 0, -28), -- route toward the ascent
		Vector3.new(0, 0, cfg.studsPerSide / 2 - 26), -- spawn apron emergency supply
	}
	for i = 1, cfg.lootCount do
		local center = clusters[((i - 1) % #clusters) + 1]
		local spread = if i <= #clusters then 5 else 10
		local x = center.X + math.random(-spread, spread)
		local z = center.Z + math.random(-spread, spread)
		table.insert(spots, Vector3.new(x, cfg.groundY + 1.8, z))
	end
	return spots
end

-- ---------------------------------------------------------------------------
-- Entry point
-- ---------------------------------------------------------------------------

--- Generates the whole district and parents it under a workspace folder.
function District.generate(parent: Instance): DistrictHandle
	local cfg = Config.District
	local folder = Instance.new("Folder")
	folder.Name = "District"
	folder.Parent = parent

	makeSky()
	makeGround(folder, cfg)
	local spawnPosition = makeSpawnPad(folder, cfg)
	makeStreetGrid(folder, cfg)
	makeBuildings(folder, cfg)
	local landmark, payload = makeLandmark(folder, cfg)
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
		spawnPosition = spawnPosition,
		payload = payload,
		landmark = landmark,
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
