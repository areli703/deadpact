--!strict
--[[
	Util.lua — small shared helpers. No game logic lives here, only maths and
	plumbing that both sides are allowed to use.
]]

local Util = {}

--- Clamps `value` into the inclusive range [min, max].
function Util.clamp(value: number, min: number, max: number): number
	if value < min then
		return min
	elseif value > max then
		return max
	end
	return value
end

--- Linear interpolation.
function Util.lerp(a: number, b: number, t: number): number
	return a + (b - a) * t
end

--- Formats a whole number of seconds as M:SS.
function Util.formatClock(seconds: number): string
	local total = math.max(0, math.floor(seconds))
	local minutes = math.floor(total / 60)
	local secs = total % 60
	return string.format("%d:%02d", minutes, secs)
end

--- Rounds to `places` decimal places.
function Util.round(value: number, places: number): number
	local scale = 10 ^ (places or 0)
	return math.floor(value * scale + 0.5) / scale
end

--- Deterministically hashes a pair of UserIds into a single ledger key.
function Util.pairKey(a: number, b: number): string
	local lo = math.min(a, b)
	local hi = math.max(a, b)
	return string.format("%d:%d", lo, hi)
end

--- Ordered key (direction matters for a decision, but the ledger is a pair).
function Util.orderedKey(a: number, b: number): string
	return string.format("%d->%d", a, b)
end

--- Returns a random unit Vector3 on the horizontal plane.
function Util.randomUnit2D(): Vector3
	local theta = math.random() * math.pi * 2
	return Vector3.new(math.cos(theta), 0, math.sin(theta))
end

--- Picks a weighted entry from `entries` using `weight(entry)`.
function Util.weightedPick<T>(entries: { T }, weight: (T) -> number): T
	local total = 0
	for _, entry in ipairs(entries) do
		total += weight(entry)
	end
	local roll = math.random() * total
	local acc = 0
	for _, entry in ipairs(entries) do
		acc += weight(entry)
		if roll <= acc then
			return entry
		end
	end
	return entries[#entries]
end

--- Returns the closest point to `from` among `points` that is within `maxDist`,
--- or nil if none qualify.
function Util.nearest<T>(from: Vector3, points: { T }, position: (T) -> Vector3, maxDist: number): T?
	local best: T? = nil
	local bestDist = maxDist
	for _, entry in ipairs(points) do
		local dist = (position(entry) - from).Magnitude
		if dist <= bestDist then
			bestDist = dist
			best = entry
		end
	end
	return best
end

--- Creates a Part with common defaults. Server-only in practice, but harmless
--- to define here so the client can reuse the shape if it ever needs to.
function Util.makePart(props: { [string]: any }): Part
	local part = Instance.new("Part")
	part.Anchored = true
	part.CanCollide = true
	part.CanQuery = true
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Material = Enum.Material.Concrete
	for key, value in pairs(props) do
		(part :: any)[key] = value
	end
	return part
end

--- Deep-merges `override` into `base` (base is not mutated).
function Util.shallowMerge(base: { [string]: any }, override: { [string]: any }): { [string]: any }
	local out: { [string]: any } = {}
	for key, value in pairs(base) do
		out[key] = value
	end
	for key, value in pairs(override) do
		out[key] = value
	end
	return out
end

return Util
