--!strict
--[[
	CombatSystem.lua — weapons, damage, reloads and the revive handshake.

	Registered as the service "Combat" (ZombieSystem calls damagePlayer) and as
	the owner of every C->S input remote except loot / revive / pact choice,
	which the round director and pact system own.

	Everything here is server-authoritative: the client only ever sends a
	*request*. Fire is resolved with a real raycast from the shooter's camera
	root, so a client cannot simply declare a hit.
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
-- Reload bookkeeping (shared by fire + reload request + start-of-mag)
-- ---------------------------------------------------------------------------

local function beginReload(slot: Runtime.WeaponSlot): ()
	if slot.reloading then
		return
	end
	local cfg = Config.Weapons[slot.weaponId]
	if slot.ammoInMag >= cfg.magazine or slot.reserve <= 0 then
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
-- Firing
-- ---------------------------------------------------------------------------

--- Resolves one shot for a player: cadence, ammo, a real raycast, damage,
--- noise and hit feedback.
function CombatSystem.fire(ps: Runtime.PlayerState): ()
	if not ps.alive or ps.downed or ps.extracted then
		return
	end
	local slot = ps.slots[ps.activeSlot]
	if slot == nil or slot.reloading then
		return
	end
	local cfg = Config.Weapons[slot.weaponId]
	local now = Runtime.now()
	if now - slot.lastFiredAt < 1 / cfg.fireRate then
		return
	end
	if slot.ammoInMag <= 0 then
		beginReload(slot)
		return
	end

	local root = rootOf(ps.player)
	if root == nil then
		return
	end

	slot.lastFiredAt = now
	ps.lastFiredAt = now
	ps.weaponLowered = false
	slot.ammoInMag -= 1

	local origin = root.Position + Vector3.new(0, 1.2, 0)
	local direction: Vector3 = root.CFrame.LookVector
	local spread = math.rad(cfg.spread)
	direction = (CFrame.fromEulerAnglesXYZ(
		(rng:NextNumber() - 0.5) * spread,
		(rng:NextNumber() - 0.5) * spread,
		0
	) * direction).Unit

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { ps.player.Character }
	local result = workspace:Raycast(origin, direction * cfg.range, params)

	NoiseSystem.add(origin, cfg.noise)

	local hit = result ~= nil
	local killed = false
	if result ~= nil then
		local zombie = zombies().byPart(result.Instance)
		if zombie ~= nil then
			local _, didKill = zombies().damage(zombie, cfg.damage)
			killed = didKill
			if killed then
				ps.kills += 1
			end
		end
	end

	local marker: Types.HitMarkerPayload = {
		hit = hit,
		killed = killed,
		source = "Weapon",
	}
	Net.send(ps.player, "HitMarker", marker)

	if slot.ammoInMag <= 0 then
		beginReload(slot)
	end
end

--- Player-initiated reload.
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
