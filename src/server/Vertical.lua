--!strict
--[[
	Vertical.lua — THE ASCENT.

	District.lua builds the ground city. This module stacks the sky on top of it:
	tier after tier of shrinking platforms climbing into the clouds, each joined
	to the tier below by grand staircases, exactly like the concept art's
	pyramid silhouette. Cold blue at the bottom, forge-orange at the top.

	Everything here is additive — it reads Config.District and returns a handle.
	Nothing it does can break the ground district, and deleting the single
	Vertical.build() call in Boot restores the flat world.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))

local Vertical = {}

export type TierHandle = {
	index: number,
	y: number,
	center: Vector3,
	platform: BasePart,
	stairfoot: Vector3,
	blocks: { BasePart },
}

export type AscentHandle = {
	folder: Folder,
	tiers: { TierHandle },
	summit: Vector3,
	checkpoints: { Vector3 },
	checkpointPads: { BasePart },
	forgeCore: Vector3,
}

local cfg = Config.District

local function tint(alpha: number): Color3
	-- Blends the cold bottom colour into the hot top colour.
	return cfg.ascentColdColor:Lerp(cfg.ascentHotColor, alpha)
end

local function newPart(props: { [string]: any }): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = true
	p.CanQuery = true
	p.CanTouch = false
	for k, v in pairs(props) do
		(p :: any)[k] = v
	end
	return p
end

-- A real, walkable staircase from one point up to another.
local function makeStairs(
	folder: Folder,
	foot: Vector3,
	head: Vector3,
	width: number,
	color: Color3
): ()
	local delta = head - foot
	local horizontal = Vector3.new(delta.X, 0, delta.Z)
	local run = horizontal.Magnitude
	local rise = delta.Y
	local steps = math.max(8, math.floor(rise / 2.2))
	local dir = if run > 0.01 then horizontal.Unit else Vector3.new(0, 0, 1)

	local stairFolder = Instance.new("Folder")
	stairFolder.Name = "GrandStaircase"
	stairFolder.Parent = folder

	for i = 1, steps do
		local t = i / steps
		local pos = foot + horizontal * t + Vector3.new(0, rise * t, 0)
		local tread = newPart({
			Name = "Step",
			Size = Vector3.new(width, 1.2, math.max(2.4, run / steps + 1.2)),
			CFrame = CFrame.lookAt(pos, pos + dir),
			Material = Enum.Material.Concrete,
			Color = color,
			Parent = stairFolder,
		})
		_ = tread
	end

	-- Side rails so a fall off the grand staircase has a silhouette.
	for _, side in ipairs({ -1, 1 }) do
		local offset = dir:Cross(Vector3.new(0, 1, 0)).Unit * (width / 2 + 0.6) * side
		newPart({
			Name = "StairRail",
			Size = Vector3.new(0.8, 2.4, run + 3),
			CFrame = CFrame.lookAt(
				foot + horizontal * 0.5 + offset + Vector3.new(0, rise * 0.5 + 1, 0),
				foot + horizontal * 0.5 + offset + Vector3.new(0, rise * 0.5 + 1, 0) + dir
			),
			Material = Enum.Material.Metal,
			Color = cfg.trimColor,
			Parent = stairFolder,
		})
	end
end

-- One enterable block: four walls, a real doorway, a roof. Same silhouette
-- language as the ground district so the world reads as one city.
local function makeBlock(folder: Folder, center: Vector3, height: number, color: Color3): BasePart
	local w = cfg.blockSize * 0.52
	local t = cfg.wallThickness
	local doorW = cfg.doorWidth
	local doorH = cfg.doorHeight * 0.8

	local model = Instance.new("Model")
	model.Name = "AscentBlock"
	model.Parent = folder

	local roof = newPart({
		Name = "Roof",
		Size = Vector3.new(w, 1.4, w),
		CFrame = CFrame.new(center + Vector3.new(0, height, 0)),
		Material = Enum.Material.Slate,
		Color = cfg.roofColor,
		Parent = model,
	})

	local interior = newPart({
		Name = "InteriorFloor",
		Size = Vector3.new(w - t * 2, 0.8, w - t * 2),
		CFrame = CFrame.new(center + Vector3.new(0, 0.6, 0)),
		Material = Enum.Material.Concrete,
		Color = cfg.interiorColor,
		Parent = model,
	})
	_ = interior

	-- Walls. The two long sides carry a doorway gap in the middle.
	for _, side in ipairs({ "N", "S", "E", "W" }) do
		local horizontal = side == "N" or side == "S"
		local len = w
		local along = if horizontal then Vector3.new(1, 0, 0) else Vector3.new(0, 0, 1)
		local normal = if side == "N"
			then Vector3.new(0, 0, -1)
			elseif side == "S" then Vector3.new(0, 0, 1)
			elseif side == "E" then Vector3.new(1, 0, 0)
			else Vector3.new(-1, 0, 0)
		local wallCenter = center + normal * (w / 2) + Vector3.new(0, height / 2, 0)

		if horizontal then
			-- Split the wall into two leaves with a walk-through doorway between.
			local leaf = (len - doorW) / 2
			for _, s in ipairs({ -1, 1 }) do
				local leafCenter = wallCenter + along * ((doorW / 2 + leaf / 2) * s)
				newPart({
					Name = "Wall",
					Size = Vector3.new(leaf, height, t),
					CFrame = CFrame.new(leafCenter),
					Material = Enum.Material.Brick,
					Color = color,
					Parent = model,
				})
			end
			-- Lintel over the door.
			newPart({
				Name = "Lintel",
				Size = Vector3.new(doorW, math.max(1, height - doorH), t),
				CFrame = CFrame.new(
					wallCenter
						+ Vector3.new(
							0,
							doorH / 2 + (height - doorH) / 2 - height / 2 + height / 2,
							0
						)
				) * CFrame.new(0, 0, 0),
				Material = Enum.Material.Brick,
				Color = color,
				Parent = model,
			})
		else
			newPart({
				Name = "Wall",
				Size = Vector3.new(t, height, len),
				CFrame = CFrame.new(wallCenter),
				Material = Enum.Material.Brick,
				Color = color,
				Parent = model,
			})
		end

		-- Lit window band partway up every wall.
		local win = newPart({
			Name = "Window",
			Size = if horizontal
				then Vector3.new(cfg.windowWidth, cfg.windowHeight * 0.6, t * 0.6)
				else Vector3.new(t * 0.6, cfg.windowHeight * 0.6, cfg.windowWidth),
			CFrame = CFrame.new(wallCenter + normal * 0.15),
			Material = Enum.Material.Glass,
			Color = cfg.glassColor,
			Transparency = 0.35,
			CanCollide = false,
			Parent = model,
		})
		local light = Instance.new("PointLight")
		light.Color = cfg.lightColor
		light.Range = 16
		light.Brightness = 1.1
		light.Parent = win
	end

	local glow = Instance.new("PointLight")
	glow.Color = Enum.Material.Glass == Enum.Material.Glass and cfg.lightColor or cfg.lightColor
	glow.Range = 24
	glow.Brightness = 1.4
	glow.Parent = roof
	_ = glow

	return roof
end

-- A platform ring: the floor of one tier, plus the pillars holding it up.
local function makePlatform(folder: Folder, y: number, radius: number, color: Color3): BasePart
	local platform = newPart({
		Name = "TierPlatform",
		Size = Vector3.new(radius * 2, 3, radius * 2),
		CFrame = CFrame.new(Vector3.new(0, y, 0)),
		Material = Enum.Material.Concrete,
		Color = color:Lerp(cfg.groundColor, 0.35),
		Parent = folder,
	})

	-- Structural pillars reaching down toward the tier below.
	if y > cfg.groundY + 4 then
		for i = 0, 7 do
			local a = (i / 8) * math.pi * 2
			local px = math.cos(a) * (radius * 0.62)
			local pz = math.sin(a) * (radius * 0.62)
			local below = y - cfg.ascentTierHeight
			local pillarHeight = math.max(10, below - cfg.groundY)
			newPart({
				Name = "SupportPillar",
				Size = Vector3.new(6, pillarHeight, 6),
				CFrame = CFrame.new(Vector3.new(px, y - pillarHeight / 2 - 1.5, pz)),
				Material = Enum.Material.Metal,
				Color = cfg.trimColor,
				Parent = folder,
			})
		end
	end

	-- Parapet around the rim so the tier reads as a district, not a slab.
	for _, side in ipairs({ "N", "S", "E", "W" }) do
		local normal = if side == "N"
			then Vector3.new(0, 0, -1)
			elseif side == "S" then Vector3.new(0, 0, 1)
			elseif side == "E" then Vector3.new(1, 0, 0)
			else Vector3.new(-1, 0, 0)
		local along = if side == "N" or side == "S"
			then Vector3.new(1, 0, 0)
			else Vector3.new(0, 0, 1)
		-- Leave a gap on the south rim for the grand staircase.
		local gapAtSouth = side == "S"
		for s = -1, 1 do
			if not gapAtSouth then
				newPart({
					Name = "Parapet",
					Size = Vector3.new(radius * 2, 3.2, 1.2)
						* CFrame.Angles(0, 0, 0).LookVector.Magnitude,
					CFrame = CFrame.new(Vector3.new(0, y + 2.2, 0) + normal * radius)
						* CFrame.Angles(0, math.atan2(normal.X, normal.Z), 0),
					Material = Enum.Material.Concrete,
					Color = color,
					Parent = folder,
				})
			else
				local half = radius * 0.5
				local center = Vector3.new(0, y + 2.2, 0)
					+ normal * radius
					+ along * (half + half * 0.5) * s
				newPart({
					Name = "Parapet",
					Size = if along.X ~= 0
						then Vector3.new(half, 3.2, 1.2)
						else Vector3.new(1.2, 3.2, half),
					CFrame = CFrame.new(center)
						* CFrame.Angles(0, math.atan2(normal.X, normal.Z), 0),
					Material = Enum.Material.Concrete,
					Color = color,
					Parent = folder,
				})
			end
		end
	end

	return platform
end

-- ---------------------------------------------------------------------------
-- Builds the whole ascent and returns a handle describing every tier.
function Vertical.build(parent: Instance): AscentHandle
	local root = Instance.new("Folder")
	root.Name = "TheAscent"
	root.Parent = parent

	local tiers: { TierHandle } = {}
	local checkpoints: { Vector3 } = {}
	local checkpointPads: { BasePart } = {}
	local prevCenter = Vector3.new(0, cfg.groundY, -cfg.studsPerSide / 2 + 10)

	for i = 1, cfg.ascentTiers do
		local alpha = (i - 1) / math.max(1, cfg.ascentTiers - 1)
		local color = tint(alpha)
		local y = cfg.groundY + cfg.ascentTierHeight * i
		-- Shrinking radius gives the pyramid silhouette seen in the concept art.
		local radius = cfg.ascentPlatformRadius * (1 - 0.1 * (i - 1))
		local center = Vector3.new(0, y, 0)

		local tierFolder = Instance.new("Folder")
		tierFolder.Name = string.format("Tier%d", i)
		tierFolder.Parent = root

		local platform = makePlatform(tierFolder, y, radius, color)

		-- Grand staircase climbing in from the tier below.
		local foot = prevCenter + Vector3.new(0, 0, -cfg.ascentPlatformRadius * 0.7)
		local head = center + Vector3.new(0, 0, -radius * 0.72)
		makeStairs(tierFolder, foot, head, cfg.ascentStairWidth, color)

		-- A second, narrower fire-escape style climb on the opposite side so a
		-- solo player always has a route that is not the main funnel.
		local sideFoot = prevCenter + Vector3.new(cfg.ascentPlatformRadius * 0.55, 0, 0)
		local sideHead = center + Vector3.new(radius * 0.6, 0, 0)
		makeStairs(tierFolder, sideFoot, sideHead, cfg.ascentStairWidth * 0.55, cfg.trimColor)

		-- Enterable blocks around the tier rim.
		local blocks: { BasePart } = {}
		for b = 1, cfg.ascentBlockCount do
			local a = (b / cfg.ascentBlockCount) * math.pi * 2 + 0.6
			local bx = math.cos(a) * radius * 0.55
			local bz = math.sin(a) * radius * 0.55
			local height = 26 + ((i + b) % 3) * 10
			table.insert(blocks, makeBlock(tierFolder, Vector3.new(bx, y + 1.6, bz), height, color))
		end

		-- Overhead bridge to the next tier: the elevated walkway silhouette.
		if i > 1 then
			newPart({
				Name = "Skybridge",
				Size = Vector3.new(10, 1.4, cfg.ascentTierHeight * 0.5),
				CFrame = CFrame.new(Vector3.new(radius * 0.5, y - cfg.ascentTierHeight * 0.25, 0))
					* CFrame.Angles(math.rad(-38), 0, 0),
				Material = Enum.Material.Metal,
				Color = cfg.trimColor,
				Parent = tierFolder,
			})
		end

		table.insert(tiers, {
			index = i,
			y = y,
			center = center,
			platform = platform,
			stairfoot = foot,
			blocks = blocks,
		})

		-- A checkpoint every other tier, on the staircase landing.
		if i % 2 == 0 then
			local cpPos = head + Vector3.new(0, 3, 0)
			local pad = newPart({
				Name = "Checkpoint",
				Size = Vector3.new(12, 1, 12),
				CFrame = CFrame.new(cpPos),
				Material = Enum.Material.Neon,
				Color = Color3.fromRGB(120, 226, 160),
				Parent = tierFolder,
			})
			local beacon = Instance.new("PointLight")
			beacon.Color = Color3.fromRGB(120, 226, 160)
			beacon.Range = 40
			beacon.Brightness = 2
			beacon.Parent = pad
			table.insert(checkpoints, cpPos)
			table.insert(checkpointPads, pad)
		end

		prevCenter = center
	end

	-- The summit: the current final objective, a wide boss arena in the clouds.
	local summitY = cfg.groundY + cfg.ascentTierHeight * (cfg.ascentTiers + 1)
	local summit = Vector3.new(0, summitY, 0)
	local summitFolder = Instance.new("Folder")
	summitFolder.Name = "Summit"
	summitFolder.Parent = root

	local arena = newPart({
		Name = "SummitArena",
		Size = Vector3.new(150, 6, 150),
		CFrame = CFrame.new(summit),
		Material = Enum.Material.Rock,
		Color = tint(1),
		Parent = summitFolder,
	})
	local beaconColor = Color3.fromRGB(255, 138, 60)
	local beam = newPart({
		Name = "SummitBeacon",
		Size = Vector3.new(3, 90, 3),
		CFrame = CFrame.new(summit + Vector3.new(0, 48, 0)),
		Material = Enum.Material.Neon,
		Color = beaconColor,
		CanCollide = false,
		Parent = summitFolder,
	})
	local beamLight = Instance.new("PointLight")
	beamLight.Color = beaconColor
	beamLight.Range = 120
	beamLight.Brightness = 3
	beamLight.Parent = beam
	_ = arena

	makeStairs(
		summitFolder,
		prevCenter + Vector3.new(0, 0, -cfg.ascentPlatformRadius * 0.7),
		summit + Vector3.new(0, 0, -55),
		cfg.ascentStairWidth,
		tint(1)
	)

	return {
		folder = root,
		tiers = tiers,
		summit = summit,
		checkpoints = checkpoints,
		checkpointPads = checkpointPads,
		-- The hot heart of the upper city. Survival reads this to decide where
		-- the air turns from freezing to furnace-hot.
		forgeCore = Vector3.new(0, cfg.groundY + cfg.ascentTierHeight * cfg.ascentTiers, 0),
	}
end

--- Alias kept so callers can use either name (Boot uses Vertical.generate).
Vertical.generate = Vertical.build

return Vertical
