--!strict
--[[
	ZombieSystem.lua — the horde: the clock that makes every decision urgent.

	* Zombies are POOLED. We warm a fixed pool and reuse instances rather than
	  instancing unbounded new parts.
	* One shared Heartbeat step (registered via Runtime) drives every zombie;
	  there is no per-zombie connection.
	* Escalating waves are read from Config.Waves, which is validated against
	  the Active phase length at load time.
	* Specials: a Shrieker summons a burst of walkers on death; a Stalker hunts
	  the most isolated player.
	* Noise convergence: a zombie walks toward the district's hottest noise node
	  when that node is closer than the nearest player.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Util = require(Shared:WaitForChild("Util"))

local Runtime = require(script.Parent.Runtime)
local NoiseSystem = require(script.Parent.NoiseSystem)

local ZombieSystem = {}

export type Zombie = {
	model: Model,
	part: Part,
	id: string,
	kind: string,
	health: number,
	lastAttackAt: number,
	active: boolean,
	targetUserId: number?,
	spawnedAt: number,
}

local pool: { Zombie } = {}
local active: { Zombie } = {}
local waveIndex = 0
local spawnAccumulator = 0
local waveBroadcast: (number, number) -> () = function() end
local rng = Random.new()

local function attachPart(
	model: Model,
	body: Part,
	name: string,
	size: Vector3,
	offset: CFrame,
	color: Color3,
	material: Enum.Material?
): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.CFrame = body.CFrame * offset
	part.Anchored = false
	part.CanCollide = false
	part.CanQuery = true
	part.Color = color
	part.Material = material or Enum.Material.SmoothPlastic
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = model

	local weld = Instance.new("WeldConstraint")
	weld.Part0 = body
	weld.Part1 = part
	weld.Parent = part

	return part
end

local function buildModel(kind: string): (Model, Part)
	local cfg = Config.Zombies[kind]
	local model = Instance.new("Model")
	model.Name = "Zombie_" .. kind

	local body = Instance.new("Part")
	body.Name = "Body"
	body.Size = cfg.size
	body.Anchored = false
	body.CanCollide = true
	body.CanQuery = true
	body.Color = cfg.color
	body.Material = Enum.Material.Sand
	body.TopSurface = Enum.SurfaceType.Smooth
	body.BottomSurface = Enum.SurfaceType.Smooth
	body.Parent = model

	local labelGui = Instance.new("BillboardGui")
	labelGui.Name = "ThreatLabel"
	labelGui.Size = UDim2.fromScale(4, 1)
	labelGui.StudsOffset = Vector3.new(0, cfg.size.Y + 1.3, 0)
	labelGui.AlwaysOnTop = true
	labelGui.Parent = body

	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBlack
	label.TextScaled = true
	label.TextColor3 = Config.Palette.blood
	label.TextStrokeTransparency = 0.25
	label.Text = string.upper(cfg.displayName)
	label.Parent = labelGui

	local head = Instance.new("Part")
	head.Name = "Head"
	head.Shape = Enum.PartType.Ball
	head.Size = Vector3.new(cfg.size.X, cfg.size.X, cfg.size.X)
	head.Color = cfg.color:Lerp(Color3.fromRGB(190, 190, 160), 0.18)
	head.Material = Enum.Material.Slate
	head.CanCollide = false
	head.CanQuery = false
	head.Parent = model

	local motor = Instance.new("Motor6D")
	motor.Name = "Neck"
	motor.Part0 = body
	motor.Part1 = head
	motor.C0 = CFrame.new(0, cfg.size.Y / 2, 0)
	motor.Parent = body

	local armColor = cfg.color:Lerp(Color3.fromRGB(165, 155, 130), 0.25)
	local legColor = cfg.color:Lerp(Color3.fromRGB(28, 30, 34), 0.35)
	attachPart(
		model,
		body,
		"LeftArm",
		Vector3.new(0.45, cfg.size.Y * 0.62, 0.45),
		CFrame.new(-cfg.size.X * 0.75, cfg.size.Y * 0.02, -0.25)
			* CFrame.Angles(math.rad(-24), 0, math.rad(-12)),
		armColor,
		Enum.Material.Slate
	)
	attachPart(
		model,
		body,
		"RightArm",
		Vector3.new(0.45, cfg.size.Y * 0.62, 0.45),
		CFrame.new(cfg.size.X * 0.75, cfg.size.Y * 0.02, -0.25)
			* CFrame.Angles(math.rad(-24), 0, math.rad(12)),
		armColor,
		Enum.Material.Slate
	)
	attachPart(
		model,
		body,
		"LeftLeg",
		Vector3.new(0.5, cfg.size.Y * 0.55, 0.5),
		CFrame.new(-cfg.size.X * 0.25, -cfg.size.Y * 0.74, 0),
		legColor,
		Enum.Material.Concrete
	)
	attachPart(
		model,
		body,
		"RightLeg",
		Vector3.new(0.5, cfg.size.Y * 0.55, 0.5),
		CFrame.new(cfg.size.X * 0.25, -cfg.size.Y * 0.74, 0),
		legColor,
		Enum.Material.Concrete
	)
	attachPart(
		model,
		body,
		"ChestRag",
		Vector3.new(cfg.size.X * 1.08, cfg.size.Y * 0.18, 0.12),
		CFrame.new(0, cfg.size.Y * 0.18, -cfg.size.Z / 2 - 0.04),
		Config.Palette.blood,
		Enum.Material.Fabric
	)
	attachPart(
		model,
		body,
		"LeftEye",
		Vector3.new(0.18, 0.18, 0.08),
		CFrame.new(-cfg.size.X * 0.22, cfg.size.Y / 2 + cfg.size.X * 0.08, -cfg.size.X / 2),
		Config.Palette.amber,
		Enum.Material.Neon
	)
	attachPart(
		model,
		body,
		"RightEye",
		Vector3.new(0.18, 0.18, 0.08),
		CFrame.new(cfg.size.X * 0.22, cfg.size.Y / 2 + cfg.size.X * 0.08, -cfg.size.X / 2),
		Config.Palette.amber,
		Enum.Material.Neon
	)

	model.PrimaryPart = body
	return model, body
end

local function makeRecord(kind: string, index: number): Zombie
	local model, body = buildModel(kind)
	return {
		model = model,
		part = body,
		id = string.format("z%03d_%s", index, kind),
		kind = kind,
		health = Config.Zombies[kind].health,
		lastAttackAt = 0,
		active = false,
		targetUserId = nil,
		spawnedAt = 0,
	}
end

local function deactivate(zombie: Zombie): ()
	zombie.active = false
	zombie.model.Parent = nil
	zombie.health = Config.Zombies[zombie.kind].health
	zombie.targetUserId = nil
end

local function acquire(kind: string): Zombie?
	for _, zombie in ipairs(pool) do
		if not zombie.active and zombie.kind == kind then
			return zombie
		end
	end
	local activeCount = 0
	for _, zombie in ipairs(pool) do
		if zombie.active then
			activeCount += 1
		end
	end
	if activeCount >= Config.ZombieMaxCount or #pool >= Config.ZombieMaxCount then
		return nil
	end
	local zombie = makeRecord(kind, #pool + 1)
	table.insert(pool, zombie)
	return zombie
end

local function ascentLevel(position: Vector3): number
	local tierHeight = math.max(1, Config.District.ascentTierHeight)
	return math.clamp(math.floor((position.Y - Config.District.groundY) / tierHeight) + 1, 1, 10)
end

local function difficultyScale(position: Vector3): number
	return 1 + (ascentLevel(position) - 1) * 0.16
end

local function chooseKindFor(position: Vector3): string
	local level = ascentLevel(position)
	local roll = rng:NextNumber()
	if level >= 7 and roll < 0.32 then
		return "stalker"
	elseif level >= 4 and roll < 0.26 then
		return "shrieker"
	end
	return "walker"
end

local function spawnPosition(around: Vector3): Vector3
	local Zones = Runtime.service("Zones")
	local cfg = Config.SafeZones
	local half = Config.District.studsPerSide / 2 - 4
	-- Retry a few times to keep the horde out of safe zones and checkpoints.
	-- If every roll lands in safety we accept the last one rather than stall.
	local pos = around
	for _ = 1, cfg.zombieSpawnRetries do
		local angle = rng:NextNumber() * math.pi * 2
		local distance =
			rng:NextNumber(Config.ZombieSpawnDistanceMin, Config.ZombieSpawnDistanceMax)
		pos = around + Vector3.new(math.cos(angle) * distance, 0, math.sin(angle) * distance)
		pos = Vector3.new(
			math.clamp(pos.X, -half, half),
			Config.District.groundY + 4,
			math.clamp(pos.Z, -half, half)
		)
		if not Zones.isSafe(pos) then
			return pos
		end
	end
	return pos
end

local function spawnOne(kind: string, around: Vector3): Zombie?
	local zombie = acquire(kind)
	if zombie == nil then
		return nil
	end
	local cfg = Config.Zombies[kind]
	zombie.active = true
	zombie.health = math.floor(cfg.health * difficultyScale(around))
	zombie.lastAttackAt = 0
	zombie.targetUserId = nil
	zombie.spawnedAt = Runtime.now()
	zombie.model:PivotTo(CFrame.new(spawnPosition(around)))
	zombie.model.Parent = workspace
	table.insert(active, zombie)
	return zombie
end

--- Spawns a burst of walkers at a position (Shrieker death, events).
function ZombieSystem.spawnBurst(position: Vector3, count: number): ()
	for _ = 1, count do
		spawnOne("walker", position)
	end
end

--- Spawns a special zombie at a position.
function ZombieSystem.spawnSpecial(kind: string, position: Vector3): Zombie?
	return spawnOne(kind, position)
end

local function mostIsolatedUser(): number?
	local states = Runtime.aliveStates()
	local bestId: number? = nil
	local bestScore = -math.huge
	for _, ps in ipairs(states) do
		local nearest = math.huge
		for _, other in ipairs(states) do
			if other.userId ~= ps.userId then
				local dist = (other.position - ps.position).Magnitude
				if dist < nearest then
					nearest = dist
				end
			end
		end
		if nearest > bestScore then
			bestScore = nearest
			bestId = ps.userId
		end
	end
	return bestId
end

local function nearestPlayer(position: Vector3): Runtime.PlayerState?
	local best: Runtime.PlayerState? = nil
	local bestDist = math.huge
	for _, ps in ipairs(Runtime.aliveStates()) do
		local dist = (ps.position - position).Magnitude
		if dist < bestDist then
			bestDist = dist
			best = ps
		end
	end
	return best
end

local function applyContactDamage(zombie: Zombie, ps: Runtime.PlayerState, now: number): ()
	local cfg = Config.Zombies[zombie.kind]
	if now - zombie.lastAttackAt < cfg.attackCooldown then
		return
	end
	zombie.lastAttackAt = now
	local combat = Runtime.service("Combat")
	combat.damagePlayer(
		ps,
		cfg.damage * difficultyScale(zombie.part.Position),
		"Zombie",
		zombie.part.Position
	)
end

local function moveZombie(zombie: Zombie, dt: number, goal: Vector3): ()
	local cfg = Config.Zombies[zombie.kind]
	local position = zombie.part.Position
	local flatGoal = Vector3.new(goal.X, position.Y, goal.Z)
	local delta = flatGoal - position
	if delta.Magnitude < 0.5 then
		return
	end
	local advance = math.min(cfg.walkSpeed * dt, delta.Magnitude)
	local nextPosition = position + delta.Unit * advance
	zombie.part.CFrame = CFrame.lookAt(nextPosition, flatGoal)
end

local function spawnWaveSpecial(spawnAround: Vector3): ()
	local entries: { { id: string, weight: number } } = {}
	for id, cfg in pairs(Config.Zombies) do
		if id ~= "walker" and cfg.weight > 0 then
			table.insert(entries, { id = id, weight = cfg.weight })
		end
	end
	if #entries == 0 then
		return
	end
	local pick = Util.weightedPick(entries, function(entry)
		return entry.weight
	end)
	spawnOne(pick.id, spawnAround)
end

local function advanceWave(roundLoop: any): ()
	local elapsed = roundLoop.phaseElapsed()
	local schedule = Config.Waves
	local targetWave = 0
	for i, wave in ipairs(schedule) do
		if elapsed >= wave.atSeconds then
			targetWave = i
		end
	end
	if targetWave <= waveIndex then
		return
	end
	waveIndex = targetWave
	local wave = schedule[waveIndex]
	local states = Runtime.aliveStates()
	local around = if #states > 0 then states[1].position else Vector3.zero
	for _ = 1, wave.specials do
		spawnWaveSpecial(around)
	end
	waveBroadcast(waveIndex, wave.specials)
end

local function step(dt: number, now: number): ()
	local roundLoop = Runtime.service("RoundLoop")
	local hordeLive = roundLoop.phaseName() == "Active" or roundLoop.phaseName() == "Deployment"
	if hordeLive then
		advanceWave(roundLoop)
		spawnAccumulator += dt
		if spawnAccumulator >= Config.ZombieSpawnInterval then
			spawnAccumulator = 0
			local states = Runtime.aliveStates()
			local around = if #states > 0 then states[1].position else Vector3.zero
			local wave = Config.Waves[math.max(1, waveIndex)]
			local targetCount = if roundLoop.phaseName() == "Deployment"
				then math.max(8, math.floor(wave.count * 0.75))
				else wave.count
			local activeCount = #active
			if activeCount < targetCount and activeCount < Config.ZombieMaxCount then
				spawnOne(chooseKindFor(around), around)
			end
		end
	end

	local hot = NoiseSystem.hottest()
	local hotPosition = hot and hot.position or nil
	local isolatedId = mostIsolatedUser()

	local keep: { Zombie } = {}
	for _, zombie in ipairs(active) do
		if not zombie.active or zombie.health <= 0 then
			deactivate(zombie)
		else
			local cfg = Config.Zombies[zombie.kind]
			local position = zombie.part.Position
			local goal: Vector3? = nil

			if cfg.targetsIsolated and isolatedId ~= nil then
				local target = Runtime.getStateByUserId(isolatedId)
				if target ~= nil then
					goal = target.position
					zombie.targetUserId = isolatedId
				end
			end

			local nearest = nearestPlayer(position)
			if goal == nil and hotPosition ~= nil and hotPosition ~= nil then
				local noiseDist = (hotPosition - position).Magnitude
				if nearest == nil or noiseDist < (nearest.position - position).Magnitude then
					goal = hotPosition
				end
			end

			if goal == nil and nearest ~= nil then
				goal = nearest.position
				zombie.targetUserId = nearest.userId
			end

			if goal ~= nil then
				moveZombie(zombie, dt, goal)
			end

			if nearest ~= nil and (nearest.position - position).Magnitude <= 5 then
				applyContactDamage(zombie, nearest, now)
			end

			if
				nearest ~= nil
				and (nearest.position - position).Magnitude > Config.ZombieDespawnDistance
			then
				deactivate(zombie)
			else
				table.insert(keep, zombie)
			end
		end
	end
	active = keep
end

--- Called by the combat system when a zombie takes damage. Returns true + a
--- kill flag when this hit killed it.
function ZombieSystem.damage(zombie: Zombie, damage: number): (boolean, boolean)
	zombie.health -= damage
	if zombie.health <= 0 then
		local cfg = Config.Zombies[zombie.kind]
		local position = zombie.part.Position
		if cfg.onDeathBurst > 0 then
			ZombieSystem.spawnBurst(position, cfg.onDeathBurst)
		end
		deactivate(zombie)
		return true, true
	end
	return false, false
end

--- Finds the nearest active zombie to a position within `maxDist`.
function ZombieSystem.nearest(position: Vector3, maxDist: number): Zombie?
	local best: Zombie? = nil
	local bestDist = maxDist
	for _, zombie in ipairs(active) do
		local dist = (zombie.part.Position - position).Magnitude
		if dist <= bestDist then
			bestDist = dist
			best = zombie
		end
	end
	return best
end

--- Active zombie count (HUD / debrief).
function ZombieSystem.count(): number
	return #active
end

--- The current wave index (0 before the first wave).
function ZombieSystem.waveIndex(): number
	return waveIndex
end

--- Clears the horde between rounds.
function ZombieSystem.reset(): ()
	for _, zombie in ipairs(active) do
		deactivate(zombie)
	end
	active = {}
	waveIndex = 0
	spawnAccumulator = 0
end

--- Wires the wave broadcaster and starts the shared step.
function ZombieSystem.start(): ()
	local Net = require(script.Parent.Net)
	waveBroadcast = function(index: number, specials: number): ()
		Net.broadcast("RoundState", { waveIndex = index, specials = specials })
	end
	for _ = 1, Config.ZombiePoolWarmup do
		table.insert(pool, makeRecord("walker", #pool + 1))
	end
	Runtime.registerStep(step)
end

--- Maps a hit part back to its pooled zombie (combat raycast resolution).
function ZombieSystem.byPart(part: BasePart): Zombie?
	for _, zombie in ipairs(active) do
		if zombie.part == part or zombie.model == part.Parent then
			return zombie
		end
	end
	return nil
end

return ZombieSystem
