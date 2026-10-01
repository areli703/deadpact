--!strict
--[[
	NoiseSystem.lua — the heat map that makes the world feel alive.

	Gunfire, sprinting and breaking props add heat at a world position. Heat
	decays over time. Every consumer (zombies) asks this system for the hottest
	location; nothing else may compute convergence.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Types = require(Shared:WaitForChild("Types"))

local Runtime = require(script.Parent.Runtime)
local Net = require(script.Parent.Net)

local NoiseSystem = {}

export type NoiseNode = {
	position: Vector3,
	heat: number,
	lastAt: number,
}

local nodes: { NoiseNode } = {}
local nodeGrid: { [string]: NoiseNode } = {}
local GRID = 12 -- studs per node cell; nearby noise merges into one node

local function cellKey(position: Vector3): string
	local gx = math.floor(position.X / GRID + 0.5)
	local gz = math.floor(position.Z / GRID + 0.5)
	return string.format("%d,%d", gx, gz)
end

--- Adds heat at a world position. `heat` is in Config.Noise units.
function NoiseSystem.add(position: Vector3, heat: number): ()
	if heat <= 0 then
		return
	end
	local key = cellKey(position)
	local node = nodeGrid[key]
	if node == nil then
		node = {
			position = Vector3.new(position.X, position.Y, position.Z),
			heat = 0,
			lastAt = Runtime.now(),
		}
		nodeGrid[key] = node
		table.insert(nodes, node)
	end
	node.heat = math.min(Config.Noise.maxHeat, node.heat + heat)
	node.lastAt = Runtime.now()
end

--- The hottest node at or above the alert threshold, or nil.
function NoiseSystem.hottest(): NoiseNode?
	local best: NoiseNode? = nil
	for _, node in ipairs(nodes) do
		if node.heat >= Config.Noise.alertThreshold then
			if best == nil or node.heat > best.heat then
				best = node
			end
		end
	end
	return best
end

--- Heat at a specific point (for the client's local indicator), 0..1.
function NoiseSystem.heatAt(position: Vector3): number
	local key = cellKey(position)
	local node = nodeGrid[key]
	if node == nil then
		return 0
	end
	return math.clamp(node.heat / Config.Noise.maxHeat, 0, 1)
end

--- Total district heat, 0..1 (used for wave pressure readouts).
function NoiseSystem.totalHeatNormalised(): number
	local total = 0
	for _, node in ipairs(nodes) do
		total += node.heat
	end
	if #nodes == 0 then
		return 0
	end
	return math.clamp(total / (Config.Noise.maxHeat * #nodes), 0, 1)
end

local function prune(now: number): ()
	local keep: { NoiseNode } = {}
	for _, node in ipairs(nodes) do
		if node.heat > 0.5 then
			table.insert(keep, node)
		else
			nodeGrid[cellKey(node.position)] = nil
		end
	end
	nodes = keep
end

local function step(dt: number, now: number): ()
	local decay = Config.Noise.decayPerSecond * dt
	for _, node in ipairs(nodes) do
		node.heat = math.max(0, node.heat - decay)
	end
	prune(now)
end

--- Emits a noise pulse to clients so the world visibly reacts.
function NoiseSystem.emitPulse(position: Vector3, heat: number): ()
	if heat < Config.Noise.alertThreshold then
		return
	end
	local payload: Types.NoisePulsePayload = {
		position = position,
		heat = math.clamp(heat / Config.Noise.maxHeat, 0, 1),
		loud = true,
	}
	Net.broadcast("NoisePulse", payload)
end

--- Registers the decay step. Call once at boot.
function NoiseSystem.start(): ()
	Runtime.registerStep(step)
end

return NoiseSystem
