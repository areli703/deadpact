--!strict
--[[
	ExtractionSystem.lua — the way out, and the only reason to keep your word.

	Registered as the service "Extraction". During the Extraction phase every pad
	opens; a player who stands inside one for Config.Extraction.holdTime seconds
	banks their score and leaves with it — extracted players drop out of the horde
	target list, so the choice to extract is a real risk/reward decision.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Types = require(Shared:WaitForChild("Types"))

local Runtime = require(script.Parent.Runtime)
local Net = require(script.Parent.Net)

local ExtractionSystem = {}

type Point = {
	id: string,
	position: Vector3,
	pad: Part,
	marker: Part,
	light: PointLight,
	open: boolean,
}

local points: { Point } = {}
local progress: { [number]: number } = {}
local running = false

--- Adopts the district's extraction points. Call once, before start().
function ExtractionSystem.setup(districtPoints: { any }): ()
	points = {}
	for _, point in ipairs(districtPoints) do
		table.insert(points, {
			id = point.id,
			position = point.position,
			pad = point.pad,
			marker = point.marker,
			light = point.light,
			open = false,
		})
	end
end

--- Closes every pad and clears held progress (between rounds).
function ExtractionSystem.reset(): ()
	for _, point in ipairs(points) do
		point.open = false
		point.pad.Transparency = 0.55
		point.marker.Transparency = 0.35
		point.light.Enabled = true
	end
	progress = {}
	ExtractionSystem.broadcast()
end

--- Opens every pad (Extraction phase).
function ExtractionSystem.openAll(): ()
	for _, point in ipairs(points) do
		point.open = true
		point.pad.Transparency = 0.25
		point.marker.Transparency = 0.08
	end
	ExtractionSystem.broadcast()
end

--- Closes every pad (Debrief).
function ExtractionSystem.closeAll(): ()
	ExtractionSystem.reset()
end

--- True while any pad is open.
function ExtractionSystem.anyOpen(): boolean
	for _, point in ipairs(points) do
		if point.open then
			return true
		end
	end
	return false
end

--- True if a position sits inside an open pad.
function ExtractionSystem.anyOpenAt(position: Vector3): boolean
	for _, point in ipairs(points) do
		if
			point.open
			and (point.position - position).Magnitude <= Config.District.extractionRadius
		then
			return true
		end
	end
	return false
end

--- 0..1 hold progress for a player (for the HUD bar).
function ExtractionSystem.progressFor(userId: number): number
	return progress[userId] or 0
end

--- Broadcasts the open/closed state of every pad.
function ExtractionSystem.broadcast(): ()
	local payload: { Types.ExtractionPointState } = {}
	for _, point in ipairs(points) do
		table.insert(payload, {
			id = point.id,
			position = point.position,
			open = point.open,
			openAt = 0,
			closeAt = 0,
		})
	end
	Net.broadcast("ExtractionState", payload)
end

local function step(dt: number, _now: number): ()
	if not running then
		return
	end
	for _, ps in pairs(Runtime.allStates()) do
		if ps.alive and not ps.downed and not ps.extracted then
			if ExtractionSystem.anyOpenAt(ps.position) then
				local held = (progress[ps.userId] or 0) + dt / Config.Extraction.holdTime
				if held >= 1 then
					progress[ps.userId] = 1
					ps.extracted = true
					ps.bankedScore += Config.Extraction.bankedLootScore
					Net.send(ps.player, "HudState", Runtime.service("Round").hudFor(ps))
				else
					progress[ps.userId] = held
				end
			else
				progress[ps.userId] = 0
			end
		end
	end
end

--- Registers the hold step. Call once at boot.
function ExtractionSystem.start(): ()
	running = true
	Runtime.registerStep(step)
end

return ExtractionSystem
