--!strict
--[[
	RoundSystem.lua — the round director and player lifecycle.

	Registered as the service "RoundLoop" (ZombieSystem reads the live phase from
	it) and as the service "Round" (Boot uses it for drop-in).

	Responsibilities:
	 * Walk Config.Round.phases forever, broadcasting RoundState 4x a second.
	 * Own the character of every player: spawn a SpawnLocation-free drop-in, keep
	   ps.position in sync with the character so zombies/noise/pacts can see them,
	   drain stamina while sprinting, and run death -> downed -> bleedout -> respawn.
	 * Fire the once-per-phase transitions the other systems do not own
	   (horde clear on Deployment, pact settle on Debrief).
]] 

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Types = require(Shared:WaitForChild("Types"))

local Runtime = require(script.Parent.Runtime)
local Net = require(script.Parent.Net)

local RoundSystem = {}

local PHASES = Config.Round.phases

local index = 1
local phaseStartedAt = 0
local running = false
local broadcastAccumulator = 0
local pendingDropIn: { [number]: boolean } = {}
local downedAt: { [number]: number } = {}

local function currentPhase(): Types.PhaseName
	local name = PHASES[index].name
	return name :: Types.PhaseName
end

local function phaseDuration(): number
	return PHASES[index].duration
end

--- Seconds left in the current phase.
function RoundSystem.timeLeft(now: number?): number
	local clock = now or Runtime.now()
	local left = phaseStartedAt + phaseDuration() - clock
	if left < 0 then
		return 0
	end
	return left
end

--- The live phase name. Read by ZombieSystem every frame.
function RoundSystem.phaseName(): Types.PhaseName
	return currentPhase()
end

--- 1-based index of the current phase.
function RoundSystem.index(): number
	return index
end

local function tally(): (number, number, number)
	local survivors, dead, extracted = 0, 0, 0
	for _, ps in pairs(Runtime.allStates()) do
		if ps.extracted then
			extracted += 1
		elseif ps.alive and not ps.downed then
			survivors += 1
		else
			dead += 1
		end
	end
	return survivors, dead, extracted
end

--- Builds a RoundState payload from the live phase + world.
function RoundSystem.payload(): Types.RoundStatePayload
	local ZombieSystem = Runtime.service("Zombies")
	local survivors, dead, extracted = tally()
	return {
		phase = currentPhase(),
		phaseTimeLeft = RoundSystem.timeLeft(),
		phaseDuration = phaseDuration(),
		waveIndex = ZombieSystem.waveIndex(),
		zombieCount = ZombieSystem.count(),
		survivors = survivors,
		dead = dead,
		extracted = extracted,
	}
end

-- ---------------------------------------------------------------------------
-- Character lifecycle
-- ---------------------------------------------------------------------------

local function randomDropPosition(): Vector3
	local half = Config.District.studsPerSide / 2 - 20
	local x = math.random() * half * 2 - half
	local z = math.random() * half * 2 - half
	return Vector3.new(x, Config.District.groundY + 4, z)
end

local function characterOf(ps: Runtime.PlayerState): Model?
	local character = ps.player.Character
	if character == nil then
		return nil
	end
	return character
end

local function humanoidOf(ps: Runtime.PlayerState): Humanoid?
	local character = characterOf(ps)
	if character == nil then
		return nil
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	return humanoid
end

local function rootOf(ps: Runtime.PlayerState): BasePart?
	local character = characterOf(ps)
	if character == nil then
		return nil
	end
	return character:FindFirstChild("HumanoidRootPart") :: BasePart?
end

--- Drops a player into the district: full health, armed, weapons lowered.
function RoundSystem.dropIn(ps: Runtime.PlayerState): ()
	ps.alive = true
	ps.downed = false
	ps.extracted = false
	ps.health = ps.maxHealth
	ps.stamina = ps.maxStamina
	ps.weaponLowered = true
	ps.lastFiredAt = 0
	ps.sprinting = false

	local root = rootOf(ps)
	if root ~= nil then
		root.CFrame = CFrame.new(randomDropPosition())
	end
	local humanoid = humanoidOf(ps)
	if humanoid ~= nil then
		humanoid.WalkSpeed = Config.Player.walkSpeed
		humanoid.Health = humanoid.MaxHealth
	end
	ps.position = if root ~= nil then root.Position else Vector3.zero
	Net.send(ps.player, "RoundState", RoundSystem.payload())
end

local function respawnCharacter(ps: Runtime.PlayerState): ()
	local ok = pcall(function()
		ps.player:LoadCharacter()
	end)
	if not ok then
		return
	end
	if currentPhase() == "Active" or currentPhase() == "Deployment" then
		RoundSystem.dropIn(ps)
	else
		pendingDropIn[ps.userId] = true
	end
end

--- Puts a player into the downed state instead of killing them outright. A pact
--- ally must revive them before bleedout; otherwise they die and respawn.
function RoundSystem.downPlayer(ps: Runtime.PlayerState): ()
	if ps.downed or not ps.alive then
		return
	end
	ps.downed = true
	ps.health = 0
	downedAt[ps.userId] = Runtime.now()
	Net.send(ps.player, "HudState", RoundSystem.hudFor(ps))
end

local function killPlayer(ps: Runtime.PlayerState): ()
	ps.downed = false
	ps.alive = false
	downedAt[ps.userId] = nil
	task.delay(Config.Player.respawnDelay, function()
		if ps.player.Parent ~= nil then
			respawnCharacter(ps)
		end
	end)
end

local function onCharacterAdded(ps: Runtime.PlayerState): ()
	local humanoid = humanoidOf(ps)
	if humanoid == nil then
		return
	end
	humanoid.WalkSpeed = Config.Player.walkSpeed
end

local function onPlayerAdded(player: Player): ()
	local ps = Runtime.getState(player)
	if ps == nil then
		return
	end
	player.CharacterAdded:Connect(function()
		onCharacterAdded(ps)
	end)
	if player.Character ~= nil then
		onCharacterAdded(ps)
	end
	if currentPhase() == "Active" or currentPhase() == "Deployment" then
		RoundSystem.dropIn(ps)
	else
		pendingDropIn[player.UserId] = true
	end
end

-- ---------------------------------------------------------------------------
-- Per-frame work: position sync + stamina
-- ---------------------------------------------------------------------------

local function syncPosition(ps: Runtime.PlayerState, dt: number): ()
	local root = rootOf(ps)
	if root == nil then
		return
	end
	ps.position = root.Position

	if not ps.alive or ps.downed then
		return
	end

	if ps.sprinting and ps.stamina > 0 then
		ps.stamina -= Config.Player.staminaDrain * dt
		local humanoid = humanoidOf(ps)
		if humanoid ~= nil then
			humanoid.WalkSpeed = Config.Player.sprintSpeed
		end
	else
		ps.sprinting = false
		ps.stamina = math.min(ps.maxStamina, ps.stamina + Config.Player.staminaRegen * dt)
		local humanoid = humanoidOf(ps)
		if humanoid ~= nil then
			humanoid.WalkSpeed = Config.Player.walkSpeed
		end
	end

	if ps.downed then
		local downedFor = Runtime.now() - (downedAt[ps.userId] or Runtime.now())
		if downedFor >= Config.Player.bleedoutTime then
			killPlayer(ps)
		end
	end
end

-- ---------------------------------------------------------------------------
-- HUD
-- ---------------------------------------------------------------------------

--- The per-player survival HUD payload (health, stamina, weapon, extract).
function RoundSystem.hudFor(ps: Runtime.PlayerState, extractionProgress: number?): Types.HudStatePayload
	local weapon: Types.WeaponHudState? = nil
	local slot = ps.slots[ps.activeSlot]
	if slot ~= nil then
		local cfg = Config.Weapons[slot.weaponId]
		local progress = 0
		if slot.reloading then
			local total = cfg.reloadTime
			local left = math.max(0, slot.reloadEndsAt - Runtime.now())
			progress = if total > 0 then 1 - left / total else 1
		end
		weapon = {
			id = slot.weaponId,
			displayName = cfg.displayName,
			ammoInMag = slot.ammoInMag,
			magazine = cfg.magazine,
			reserve = slot.reserve,
			reloading = slot.reloading,
			reloadProgress = math.clamp(progress, 0, 1),
		}
	end
	local Extraction = Runtime.service("Extraction")
	return {
		health = ps.health,
		maxHealth = ps.maxHealth,
		stamina = ps.stamina,
		maxStamina = ps.maxStamina,
		heat = 0,
		weapon = weapon,
		weaponLowered = ps.weaponLowered,
		extractionOpen = Extraction.anyOpen(),
		extractionProgress = extractionProgress or 0,
		isDowned = ps.downed,
		alive = ps.alive,
	}
end

-- ---------------------------------------------------------------------------
-- Phase transitions
-- ---------------------------------------------------------------------------

local function enterIntermission(): ()
	local ZombieSystem = Runtime.service("Zombies")
	ZombieSystem.reset()
end

local function enterDeployment(): ()
	local ZombieSystem = Runtime.service("Zombies")
	local LootSystem = Runtime.service("Loot")
	local Extraction = Runtime.service("Extraction")
	ZombieSystem.reset()
	Extraction.reset()
	LootSystem.repopulate()
	pendingDropIn = {}
	for _, ps in pairs(Runtime.allStates()) do
		RoundSystem.dropIn(ps)
	end
end

local function enterActive(): ()
	local Extraction = Runtime.service("Extraction")
	Extraction.closeAll()
end

local function enterExtraction(): ()
	local Extraction = Runtime.service("Extraction")
	Extraction.openAll()
end

local function enterDebrief(): ()
	local PactSystem = Runtime.service("Pacts")
	local Extraction = Runtime.service("Extraction")
	Extraction.closeAll()
	PactSystem.settleKept()

	local ZombieSystem = Runtime.service("Zombies")
	ZombieSystem.reset()

	for _, ps in pairs(Runtime.allStates()) do
		local rows = require(script.Parent.PactLedger).snapshotFor(ps.userId)
		local payload: Types.DebriefPayload = {
			phase = "Debrief",
			survived = ps.alive,
			extracted = ps.extracted,
			bankedScore = ps.bankedScore,
			pacts = rows,
			kills = ps.kills,
		}
		Net.send(ps.player, "Debrief", payload)
	end
	PactSystem.resetRound()
end

local TRANSITIONS: { [string]: () -> () } = {
	Intermission = enterIntermission,
	Deployment = enterDeployment,
	Active = enterActive,
	Extraction = enterExtraction,
	Debrief = enterDebrief,
}

local function advancePhase(now: number): ()
	index += 1
	if index > #PHASES then
		index = 1
	end
	phaseStartedAt = now
	local fn = TRANSITIONS[currentPhase()]
	if fn ~= nil then
		local ok, err = pcall(fn)
		if not ok then
			warn(string.format("DEADPACT round: %s transition failed: %s", currentPhase(), tostring(err)))
		end
	end
	Net.broadcast("RoundState", RoundSystem.payload())
end

local function step(dt: number, now: number): ()
	if not running then
		return
	end

	for _, ps in pairs(Runtime.allStates()) do
		syncPosition(ps, dt)
	end

	if now - phaseStartedAt >= phaseDuration() then
		advancePhase(now)
	end

	-- Keep the drop-in queue honest: anyone waiting gets dropped when open.
	if currentPhase() == "Active" or currentPhase() == "Deployment" then
		for userId in pairs(pendingDropIn) do
			local ps = Runtime.getStateByUserId(userId)
			if ps ~= nil then
				RoundSystem.dropIn(ps)
			end
			pendingDropIn[userId] = nil
		end
	end

	broadcastAccumulator += dt
	if broadcastAccumulator >= 0.25 then
		broadcastAccumulator = 0
		local Extraction = Runtime.service("Extraction")
		Net.broadcast("RoundState", RoundSystem.payload())
		for _, ps in pairs(Runtime.allStates()) do
			Net.send(ps.player, "HudState", RoundSystem.hudFor(ps, Extraction.progressFor(ps.userId)))
		end
	end
end

--- Starts the director. Call once, after every system is registered.
function RoundSystem.start(): ()
	running = true
	phaseStartedAt = Runtime.now()
	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in ipairs(Players:GetPlayers()) do
		onPlayerAdded(player)
	end
	Runtime.registerStep(step)
	Net.broadcast("RoundState", RoundSystem.payload())
end

return RoundSystem
