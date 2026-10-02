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

-- Payload state is declared up here so RoundSystem.payload() (defined above the
-- Payload section) closes over the SAME locals instead of reading nil globals.
local payloadState: string = "Idle" -- Idle | Carried | Secured
local carrierId: number? = nil

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

--- Seconds elapsed in the current phase. Used by the wave director.
function RoundSystem.phaseElapsed(now: number?): number
	return math.max(0, (now or Runtime.now()) - phaseStartedAt)
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
	local carrierName: string? = nil
	if payloadState == "Carried" and carrierId ~= nil then
		local cps = Runtime.getStateByUserId(carrierId)
		if cps ~= nil then
			carrierName = cps.player.DisplayName
		end
	end
	return {
		phase = currentPhase(),
		phaseTimeLeft = RoundSystem.timeLeft(),
		phaseDuration = phaseDuration(),
		waveIndex = ZombieSystem.waveIndex(),
		zombieCount = ZombieSystem.count(),
		survivors = survivors,
		dead = dead,
		extracted = extracted,
		payloadState = payloadState,
		carrierName = carrierName,
	}
end

-- ---------------------------------------------------------------------------
-- Character lifecycle
-- ---------------------------------------------------------------------------

--- Finds a safe drop-in position: prefer the anchored spawn pad, then settle
--- onto whatever is directly below with a downward raycast so a player can
--- never be placed inside geometry (or under the ground) on join. This is the
--- floor-collapse fix — the old code teleported players to a random point at
--- y=4, often inside a solid building or in mid-air over the void.
local function safeDropPosition(ps: Runtime.PlayerState?): Vector3
	local District = Runtime.service("District")

	-- Prefer the player's claimed checkpoint; fall back to the spawn apron.
	if ps ~= nil then
		local Zones = Runtime.service("Zones")
		local anchor = Zones.anchorFor(ps)
		if anchor ~= nil then
			return anchor + Vector3.new(0, 5, 0)
		end
	end

	local base = (District and District.spawnPosition)
		or Vector3.new(0, Config.District.groundY + 6, 0)

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = {}
	local result = workspace:Raycast(base + Vector3.new(0, 40, 0), Vector3.new(0, -200, 0), params)
	if result ~= nil then
		return result.Position + Vector3.new(0, 5, 0)
	end
	return base
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
	ps.hunger = 1
	ps.thirst = 1
	ps.tempC = Config.Survival.ambientTemp
	ps.weaponLowered = true
	ps.lastFiredAt = 0
	ps.sprinting = false
	ps.carryingPayload = false

	local root = rootOf(ps)
	if root ~= nil then
		root.CFrame = CFrame.new(safeDropPosition(ps))
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
-- The Payload — the round's objective ("why are we here")
-- ---------------------------------------------------------------------------

local claimAccum: { [number]: number } = {}

local function districtPayload(): any
	local District = Runtime.service("District")
	return District and District.payload
end

--- Puts the payload back on its pad at the district centre.
local function resetPayload(): ()
	payloadState = "Idle"
	carrierId = nil
	claimAccum = {}
	local payload = districtPayload()
	if payload ~= nil then
		payload.core.CFrame = CFrame.new(payload.position)
		payload.core.Transparency = 0
		payload.core.Color = Config.Palette.amber
	end
end

--- Public: current payload state + the carrier's UserId (for HUD / other systems).
function RoundSystem.payloadState(): (string, number?)
	return payloadState, carrierId
end

local function grabPayload(ps: Runtime.PlayerState): ()
	payloadState = "Carried"
	carrierId = ps.userId
	ps.carryingPayload = true
	local payload = districtPayload()
	if payload ~= nil then
		payload.core.Color = Config.Palette.blood
	end
end

local function releasePayload(ps: Runtime.PlayerState): ()
	ps.carryingPayload = false
	if carrierId == ps.userId then
		resetPayload()
	end
end

--- Per-frame payload logic: claim on the pad, drop on death, secure on extract.
local function stepPayload(dt: number): ()
	local payload = districtPayload()
	if payload == nil then
		return
	end

	if payloadState == "Idle" then
		local best: Runtime.PlayerState? = nil
		local bestAcc = 0
		for _, ps in pairs(Runtime.allStates()) do
			if ps.alive and not ps.downed and not ps.extracted then
				local dist = (ps.position - payload.position).Magnitude
				if dist <= 14 then
					local acc = (claimAccum[ps.userId] or 0) + dt
					claimAccum[ps.userId] = acc
					if acc > bestAcc then
						bestAcc = acc
						best = ps
					end
				else
					claimAccum[ps.userId] = 0
				end
			end
		end
		if best ~= nil and bestAcc >= Config.Purpose.secureHoldTime then
			grabPayload(best :: Runtime.PlayerState)
		end
	elseif payloadState == "Carried" and carrierId ~= nil then
		local ps = Runtime.getStateByUserId(carrierId)
		if ps == nil or not ps.alive or ps.downed then
			if ps ~= nil then
				releasePayload(ps)
			else
				resetPayload()
			end
			return
		end
		-- Bind the floating core to the carrier so everyone can see who has it.
		local root = rootOf(ps)
		if root ~= nil then
			payload.core.CFrame = root.CFrame * CFrame.new(0, 3.4, 0)
		end
		-- The win: carry it out through an extraction zone.
		if ps.extracted then
			payloadState = "Secured"
			ps.carryingPayload = false
			ps.securedPayload = true
			ps.bankedScore += Config.Purpose.extractScore
			payload.core.Transparency = 1
		end
	end
end

local function syncPosition(ps: Runtime.PlayerState, dt: number): ()
	local root = rootOf(ps)
	if root == nil then
		return
	end
	ps.position = root.Position

	if not ps.alive or ps.downed then
		return
	end

	local humanoid = humanoidOf(ps)
	local carrying = ps.carryingPayload
	if carrying and not Config.Purpose.carrierCanSprint then
		ps.sprinting = false
	end

	if ps.sprinting and ps.stamina > 0 and not carrying then
		ps.stamina -= Config.Player.staminaDrain * dt
		if humanoid ~= nil then
			humanoid.WalkSpeed = Config.Player.sprintSpeed
		end
	else
		ps.sprinting = false
		if not carrying then
			ps.stamina = math.min(ps.maxStamina, ps.stamina + Config.Player.staminaRegen * dt)
		end
		if humanoid ~= nil then
			humanoid.WalkSpeed = if carrying
				then Config.Purpose.carrierWalkSpeed
				else Config.Player.walkSpeed
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
function RoundSystem.hudFor(
	ps: Runtime.PlayerState,
	extractionProgress: number?
): Types.HudStatePayload
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
			melee = cfg.melee,
			carryingPayload = ps.carryingPayload,
		}
	end
	local Extraction = Runtime.service("Extraction")
	local Survival = Runtime.service("Survival")
	return {
		health = ps.health,
		maxHealth = ps.maxHealth,
		stamina = ps.stamina,
		maxStamina = ps.maxStamina,
		heat = 0,
		hunger = ps.hunger,
		thirst = ps.thirst,
		tempC = ps.tempC,
		exposure = Survival.band(ps.tempC),
		medKits = ps.medKits,
		foodItems = ps.foodItems,
		waterItems = ps.waterItems,
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
	resetPayload()
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
			warn(
				string.format(
					"DEADPACT round: %s transition failed: %s",
					currentPhase(),
					tostring(err)
				)
			)
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

	stepPayload(dt)

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
			Net.send(
				ps.player,
				"HudState",
				RoundSystem.hudFor(ps, Extraction.progressFor(ps.userId))
			)
		end
	end
end

--- Starts the director. Call once, after every system is registered.
function RoundSystem.start(): ()
	running = true
	phaseStartedAt = Runtime.now()
	local fn = TRANSITIONS[currentPhase()]
	if fn ~= nil then
		local ok, err = pcall(fn)
		if not ok then
			warn(
				string.format(
					"DEADPACT round: %s transition failed: %s",
					currentPhase(),
					tostring(err)
				)
			)
		end
	end
	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in ipairs(Players:GetPlayers()) do
		onPlayerAdded(player)
	end
	Runtime.registerStep(step)
	Net.broadcast("RoundState", RoundSystem.payload())
end

return RoundSystem
