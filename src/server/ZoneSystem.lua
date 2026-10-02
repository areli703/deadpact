--!strict
--[[
	ZoneSystem.lua — safe zones and checkpoints.

	A safe zone is the only place the climb lets you breathe: the air is
	normalized toward a comfortable temperature and your health slowly mends.
	The first survivor to reach a checkpoint claims it as their respawn anchor,
	so a death high on the ascent does not send you all the way back down.

	Safe zones are also where zombies may never spawn — the wave director asks
	this module before it places a horde.
]]

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))

local Runtime = require(script.Parent.Runtime)

local ZoneSystem = {}

type Zone = {
	index: number,
	position: Vector3,
	pad: BasePart?,
	claimedBy: number?,
}

local zones: { Zone } = {}
local spawnPadPosition: Vector3? = nil
local ready = false

--- Registers every checkpoint + the spawn apron as safe zones.
function ZoneSystem.setup(district: any): ()
	zones = {}
	spawnPadPosition = district.spawnPosition

	local ascent = district.ascent
	if ascent ~= nil then
		for i, pos in ipairs(ascent.checkpoints) do
			local pad = ascent.checkpointPads and ascent.checkpointPads[i] or nil
			table.insert(zones, {
				index = i,
				position = pos,
				pad = pad,
				claimedBy = nil,
			})
		end
	end

	ready = true
	print(string.format("[DEADPACT] zones online — %d checkpoints + spawn apron", #zones))
end

--- True while a position sits inside any safe zone (checkpoint or spawn apron).
function ZoneSystem.isSafe(position: Vector3): boolean
	local cfg = Config.SafeZones
	if spawnPadPosition ~= nil and (position - spawnPadPosition).Magnitude <= cfg.spawnRadius then
		return true
	end
	for _, zone in ipairs(zones) do
		if (position - zone.position).Magnitude <= cfg.radius then
			return true
		end
	end
	return false
end

--- The respawn anchor for a player: their highest claimed checkpoint, else the
--- spawn apron. Returns nil when the world has no zones at all.
function ZoneSystem.anchorFor(ps: Runtime.PlayerState): Vector3?
	local best: Vector3? = nil
	for _, zone in ipairs(zones) do
		if zone.claimedBy == ps.userId and zone.index <= ps.respawnZone then
			best = zone.position
		end
	end
	if best ~= nil then
		return best
	end
	return spawnPadPosition
end

--- Finds the checkpoint this position is standing in, if any.
local function zoneAt(position: Vector3): Zone?
	local cfg = Config.SafeZones
	for _, zone in ipairs(zones) do
		if (position - zone.position).Magnitude <= cfg.radius then
			return zone
		end
	end
	return nil
end

--- One step: healing + warmth inside safe zones, and checkpoint capture.
local function step(dt: number, _now: number): ()
	if not ready then
		return
	end
	local cfg = Config.SafeZones

	for _, ps in pairs(Runtime.allStates()) do
		if not ps.alive or ps.downed then
			continue
		end

		local humanoid = ps.player.Character
			and ps.player.Character:FindFirstChildOfClass("Humanoid")

		-- The spawn apron is safe too, but it is never claimed.
		local insideSpawn = spawnPadPosition ~= nil
			and (ps.position - spawnPadPosition).Magnitude <= cfg.spawnRadius
		if insideSpawn then
			ps.tempC += (cfg.comfortTemp - ps.tempC) * math.clamp(cfg.warmRate * dt, 0, 1)
			if humanoid ~= nil and humanoid.Health < humanoid.MaxHealth then
				local healed = math.min(cfg.healRate * dt, humanoid.MaxHealth - humanoid.Health)
				humanoid.Health = humanoid.Health + healed
				ps.health = math.min(ps.maxHealth, ps.health + healed)
			end
		end

		local zone = zoneAt(ps.position)
		if zone == nil then
			continue
		end

		-- Capture: the first living survivor to reach a checkpoint claims it.
		if zone.claimedBy == nil then
			zone.claimedBy = ps.userId
			ps.respawnZone = math.max(ps.respawnZone, zone.index)
			local pad = zone.pad
			if pad ~= nil then
				pad.Color = Color3.fromRGB(120, 226, 160)
				local light = pad:FindFirstChildOfClass("PointLight")
				if light ~= nil then
					light.Brightness = 4
				end
			end
			print(
				string.format("[DEADPACT] checkpoint %d claimed by %s", zone.index, ps.player.Name)
			)
		elseif zone.claimedBy == ps.userId then
			ps.respawnZone = math.max(ps.respawnZone, zone.index)
		end

		-- Recovery, once inside.
		ps.tempC += (cfg.comfortTemp - ps.tempC) * math.clamp(cfg.warmRate * dt, 0, 1)
		if humanoid ~= nil and humanoid.Health < humanoid.MaxHealth then
			local healed = math.min(cfg.healRate * dt, humanoid.MaxHealth - humanoid.Health)
			humanoid.Health = humanoid.Health + healed
			ps.health = math.min(ps.maxHealth, ps.health + healed)
		end
	end
end

--- Registers the zone step. Called once by Boot.
function ZoneSystem.start(): ()
	Runtime.provide("Zones", ZoneSystem)
	Runtime.registerStep(step)
end

return ZoneSystem
