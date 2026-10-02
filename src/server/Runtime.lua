--!strict
--[[
	Runtime.lua — the server's spine.

	* Owns every player's authoritative state table.
	* Owns ONE RunService.Heartbeat connection driving a step-function registry.
	  Every system (zombies, noise, hazards, round) registers a step callable;
	  we never open a separate connection per zombie.
	* Owns the service table so other modules can reach each other without
	  require cycles.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")

local Config = require(Shared:WaitForChild("Config"))

local Runtime = {}

export type WeaponSlot = {
	weaponId: string,
	ammoInMag: number,
	reserve: number,
	reloading: boolean,
	reloadEndsAt: number,
	lastFiredAt: number,
}

export type PlayerState = {
	userId: number,
	player: Player,
	alive: boolean,
	downed: boolean,
	extracted: boolean,
	health: number,
	maxHealth: number,
	stamina: number,
	maxStamina: number,
	-- Survival (see Survival.lua): hunger/thirst are 0..1, tempC is felt degrees.
	hunger: number,
	thirst: number,
	tempC: number,
	weaponLowered: boolean,
	lastFiredAt: number,
	sprinting: boolean,
	lastSprintHeatAt: number,
	slots: { WeaponSlot },
	activeSlot: number,
	bankedScore: number,
	kills: number,
	position: Vector3,
	-- The Payload: true while this player is carrying the round's objective.
	carryingPayload: boolean,
	-- Set true when this player has banked the payload at an extraction zone.
	securedPayload: boolean,
}

export type StepFn = (dt: number, now: number) -> ()

local state: { [number]: PlayerState } = {}
local steps: { StepFn } = {}
local services: { [string]: any } = {}
local started = false
local heartbeatConn: RBXScriptConnection? = nil

--- Registers a named service so modules can look each other up.
function Runtime.provide(name: string, service: any): ()
	services[name] = service
end

--- Fetches a named service; errors loudly if a system boots out of order.
function Runtime.service(name: string): any
	local svc = services[name]
	assert(svc ~= nil, string.format("DEADPACT runtime error: service %q not registered", name))
	return svc
end

--- Registers a per-frame step. All steps share the single Heartbeat loop.
function Runtime.registerStep(fn: StepFn): ()
	table.insert(steps, fn)
end

--- Returns the authoritative state table for a player, or nil.
function Runtime.getState(player: Player): PlayerState?
	return state[player.UserId]
end

--- Returns the authoritative state for a UserId, or nil.
function Runtime.getStateByUserId(userId: number): PlayerState?
	return state[userId]
end

--- Iterates every live player state.
function Runtime.allStates(): { [number]: PlayerState }
	return state
end

--- Iterates only alive (not downed, not extracted) player states.
function Runtime.aliveStates(): { PlayerState }
	local out: { PlayerState } = {}
	for _, ps in pairs(state) do
		if ps.alive and not ps.downed and not ps.extracted then
			table.insert(out, ps)
		end
	end
	return out
end

local function makeSlots(): { WeaponSlot }
	return {
		{
			weaponId = "knife",
			ammoInMag = 0,
			reserve = 0,
			reloading = false,
			reloadEndsAt = 0,
			lastFiredAt = 0,
		},
		{
			weaponId = Config.StartingWeapon,
			ammoInMag = Config.Weapons[Config.StartingWeapon].magazine,
			reserve = Config.Ammo.light.max,
			reloading = false,
			reloadEndsAt = 0,
			lastFiredAt = 0,
		},
	}
end

local function onPlayerAdded(player: Player): ()
	local playerConfig = Config.Player
	state[player.UserId] = {
		userId = player.UserId,
		player = player,
		alive = false,
		downed = false,
		extracted = false,
		health = playerConfig.maxHealth,
		maxHealth = playerConfig.maxHealth,
		stamina = playerConfig.maxStamina,
		maxStamina = playerConfig.maxStamina,
		hunger = 1,
		thirst = 1,
		tempC = Config.Survival.ambientTemp,
		weaponLowered = true,
		lastFiredAt = 0,
		sprinting = false,
		lastSprintHeatAt = 0,
		slots = makeSlots(),
		activeSlot = 1,
		bankedScore = 0,
		kills = 0,
		position = Vector3.zero,
		carryingPayload = false,
		securedPayload = false,
	}
end

local function onPlayerRemoving(player: Player): ()
	state[player.UserId] = nil
end

--- Starts the single Heartbeat loop. Safe to call once.
function Runtime.start(): ()
	assert(not started, "DEADPACT runtime error: Runtime.start() called twice")
	started = true

	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in ipairs(Players:GetPlayers()) do
		onPlayerAdded(player)
	end
	Players.PlayerRemoving:Connect(onPlayerRemoving)

	heartbeatConn = RunService.Heartbeat:Connect(function(dt: number)
		local now = os.clock()
		for _, fn in ipairs(steps) do
			fn(dt, now)
		end
	end)
end

--- Stops the loop (used by tests / teardown).
function Runtime.stop(): ()
	if heartbeatConn then
		heartbeatConn:Disconnect()
		heartbeatConn = nil
	end
	started = false
end

--- Current server clock in seconds.
function Runtime.now(): number
	return os.clock()
end

return Runtime
