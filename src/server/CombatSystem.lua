--!strict
--[[
	CombatSystem.lua — weapons, damage, reloads and the revive handshake.

	Registered as the service "Combat" (ZombieSystem calls damagePlayer) and as
	the owner of every C->S input remote except loot / revive / pact choice,
	which the round director and pact system own.

	Everything here is server-authoritative: the client only ever sends a
	*request*. Fire is resolved with a real raycast from the shooter's camera
	root, so a client cannot simply declare a hit.

	Two weapon families share this file:
	 * Firearms — hitscan, spread, magazines, reloads, headshot multipliers,
	   per-pellet resolution for shotguns, and a muzzle flash / recoil signal.
	 * Melee — a short-range swing with a backstab multiplier and ZERO noise,
	   so the knife is the quiet way to clear a room or finish a downed enemy.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Types = require(Shared:WaitForChild("Types"))

local Runtime = require(script.Parent.Runtime)
local Net = require(script.Parent.Net)
local NoiseSystem = require(script.Parent.NoiseSystem)

local CombatSystem = {}

local rng = Random.new()

local function zombies(): any
	return Runtime.service("Zombies")
end

local function round(): any
	return Runtime.service("Round")
end

local function rootOf(player: Player): BasePart?
	local character = player.Character
	if character == nil then
		return nil
	end
	return character:FindFirstChild("HumanoidRootPart") :: BasePart?
end

-- ---------------------------------------------------------------------------
-- Damage in / out
-- ---------------------------------------------------------------------------

--- Applies damage to a player. Zero health downs them (a pact ally can revive;
--- otherwise the round director bleeds them out).
function CombatSystem.damagePlayer(
	ps: Runtime.PlayerState,
	amount: number,
	_source: string,
	_position: Vector3
): ()
	if not ps.alive or ps.downed or ps.extracted then
		return
	end
	ps.health -= amount
	if ps.health <= 0 then
		ps.health = 0
		round().downPlayer(ps)
	end
end

-- ---------------------------------------------------------------------------
-- Reload bookkeeping (firearms only)
-- ---------------------------------------------------------------------------

local function beginReload(slot: Runtime.WeaponSlot): ()
	if slot.reloading then
		return
	end
	local cfg = Config.Weapons[slot.weaponId]
	if cfg.melee or slot.ammoInMag >= cfg.magazine or slot.reserve <= 0 then
		return
	end
	slot.reloading = true
	slot.reloadEndsAt = Runtime.now() + cfg.reloadTime
end

local function finishReload(slot: Runtime.WeaponSlot): ()
	local cfg = Config.Weapons[slot.weaponId]
	local take = math.min(cfg.magazine - slot.ammoInMag, slot.reserve)
	slot.ammoInMag += take
	slot.reserve -= take
	slot.reloading = false
	slot.reloadEndsAt = 0
end

-- ---------------------------------------------------------------------------
-- Feedback
-- ---------------------------------------------------------------------------

local function sendFeedback(ps: Runtime.PlayerState, cfg: Config.WeaponConfig, origin: Vector3): ()
	Net.send(ps.player, "WeaponFeedback", {
		weaponId = ps.slots[ps.activeSlot].weaponId,
		melee = cfg.melee,
		recoil = cfg.recoil,
		muzzleScale = cfg.muzzleScale,
		origin = origin,
	})
end

-- ---------------------------------------------------------------------------
-- Firing
-- ---------------------------------------------------------------------------

local function raycastFrom(
	ps: Runtime.PlayerState,
	origin: Vector3,
	direction: Vector3,
	range: number
)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { ps.player.Character }
	return workspace:Raycast(origin, direction * range, params)
end

--- Melee swing: a short raycast that hits anything in front of the player,
--- with a backstab multiplier when the hit comes from behind.
local function meleeSwing(ps: Runtime.PlayerState, cfg: Config.WeaponConfig, now: number): ()
	local slot = ps.slots[ps.activeSlot]
	slot.lastFiredAt = now
	ps.lastFiredAt = now
	ps.weaponLowered = false

	local root = rootOf(ps)
	if root == nil then
		return
	end
	local origin = root.Position + Vector3.new(0, 1.2, 0)
	local direction = root.CFrame.LookVector

	-- The knife makes no noise — that is its whole point.
	local result = raycastFrom(ps, origin, direction, cfg.range)
	local hit = result ~= nil
	local killed = false
	if result ~= nil then
		local z = zombies().byPart(result.Instance)
		if z ~= nil then
			local damage = cfg.damage
			-- Backstab: if the zombie is facing away from us, hit it harder.
			local toMe = (origin - z.part.Position).Unit
			if z.part.CFrame.LookVector:Dot(toMe) > 0.25 then
				damage *= cfg.backstabMultiplier
			end
			local _, didKill = zombies().damage(z, damage)
			killed = didKill
			if killed then
				ps.kills += 1
			end
		end
	end

	sendFeedback(ps, cfg, origin)
	Net.send(ps.player, "HitMarker", {
		hit = hit,
		killed = killed,
		source = "Melee",
	})
end

--- Resolves one shot for a player: cadence, ammo, a real raycast, damage,
--- noise and hit feedback. Handles multi-pellet weapons (shotguns).
function CombatSystem.fire(ps: Runtime.PlayerState): ()
	if not ps.alive or ps.downed or ps.extracted then
		return
	end
	local slot = ps.slots[ps.activeSlot]
	if slot == nil then
		return
	end
	local cfg = Config.Weapons[slot.weaponId]
	local now = Runtime.now()
	if now - slot.lastFiredAt < 1 / cfg.fireRate then
		return
	end

	if cfg.melee then
		meleeSwing(ps, cfg, now)
		return
	end

	if slot.reloading then
		return
	end
	if slot.ammoInMag <= 0 then
		beginReload(slot)
		return
	end

	local root = rootOf(ps)
	if root == nil then
		return
	end

	slot.lastFiredAt = now
	ps.lastFiredAt = now
	ps.weaponLowered = false
	slot.ammoInMag -= 1

	local origin = root.Position + Vector3.new(0, 1.2, 0)
	local baseDir: Vector3 = root.CFrame.LookVector
	local spread = math.rad(cfg.spread)
	local pellets = Config.PelletCounts[slot.weaponId] or 1

	local anyHit = false
	local anyKill = false
	for _ = 1, pellets do
		local direction = baseDir
		if spread > 0 then
			direction = (CFrame.fromEulerAnglesXYZ(
				(rng:NextNumber() - 0.5) * spread,
				(rng:NextNumber() - 0.5) * spread,
				0
			) * baseDir).Unit
		end

		local result = raycastFrom(ps, origin, direction, cfg.range)
		if result ~= nil then
			anyHit = true
			local z = zombies().byPart(result.Instance)
			if z ~= nil then
				local damage = cfg.damage
				if result.Instance.Name == "Head" then
					damage *= cfg.headshotMultiplier
				end
				local _, didKill = zombies().damage(z, damage)
				if didKill then
					anyKill = true
					ps.kills += 1
				end
			end
		end
	end

	NoiseSystem.add(origin, cfg.noise)
	sendFeedback(ps, cfg, origin)
	Net.send(ps.player, "HitMarker", {
		hit = anyHit,
		killed = anyKill,
		source = "Weapon",
	})

	if slot.ammoInMag <= 0 then
		beginReload(slot)
	end
end

--- Player-initiated reload (no-op for melee).
function CombatSystem.reload(ps: Runtime.PlayerState): ()
	local slot = ps.slots[ps.activeSlot]
	if slot ~= nil then
		beginReload(slot)
	end
end

--- Cycles to the next weapon slot.
function CombatSystem.swap(ps: Runtime.PlayerState): ()
	if #ps.slots <= 1 then
		return
	end
	ps.activeSlot = ps.activeSlot % #ps.slots + 1
	Net.send(ps.player, "HudState", Runtime.service("Round").hudFor(ps))
end

--- Raises/lowers the weapon (lowering is what unlocks a pact prompt).
function CombatSystem.lower(ps: Runtime.PlayerState, lowered: unknown): ()
	ps.weaponLowered = lowered == true
end

--- Server-authoritative sprint flag (drives stamina + noise).
function CombatSystem.sprint(ps: Runtime.PlayerState, on: unknown): ()
	ps.sprinting = on == true
end

-- ---------------------------------------------------------------------------

local function step(_dt: number, now: number): ()
	for _, ps in pairs(Runtime.allStates()) do
		local slot = ps.slots[ps.activeSlot]
		if slot ~= nil and slot.reloading and now >= slot.reloadEndsAt then
			finishReload(slot)
		end
	end
end

--- Binds the input remotes and registers the reload step. Call once at boot.
function CombatSystem.start(): ()
	local remotes = Net.remotes()
	remotes.events.FireRequest.OnServerEvent:Connect(function(player: Player)
		local ps = Runtime.getState(player)
		if ps ~= nil then
			CombatSystem.fire(ps)
		end
	end)
	remotes.events.ReloadRequest.OnServerEvent:Connect(function(player: Player)
		local ps = Runtime.getState(player)
		if ps ~= nil then
			CombatSystem.reload(ps)
		end
	end)
	remotes.events.SwapWeapon.OnServerEvent:Connect(function(player: Player)
		local ps = Runtime.getState(player)
		if ps ~= nil then
			CombatSystem.swap(ps)
		end
	end)
	remotes.events.LowerWeapon.OnServerEvent:Connect(function(player: Player, lowered: unknown)
		local ps = Runtime.getState(player)
		if ps ~= nil then
			CombatSystem.lower(ps, lowered)
		end
	end)
	remotes.events.SprintState.OnServerEvent:Connect(function(player: Player, on: unknown)
		local ps = Runtime.getState(player)
		if ps ~= nil then
			CombatSystem.sprint(ps, on)
		end
	end)
	Runtime.registerStep(step)
end

return CombatSystem
