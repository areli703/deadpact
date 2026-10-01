--!strict
--[[
	PactSystem.lua — THE PACT, the signature mechanic.

	When two un-pacted players come within Config.Pact.radius with weapons
	lowered, both receive a PactPrompt and have Config.Pact.decisionWindow
	seconds to choose ALLY / FIGHT / IGNORE. Both must choose.

	  ALLY  + ALLY  -> pact formed: friendly fire off, shared loot, mutual revive,
	                   recorded in the ledger.
	  either FIGHT  -> PvP enabled between that pair.
	  anything else -> nothing.

	A pact is marked BROKEN, permanently in the ledger, the moment a pacted
	partner lands damage on the other. Decision state lives on the server; the
	client only renders prompts and forwards the player's choice.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Types = require(Shared:WaitForChild("Types"))
local Util = require(Shared:WaitForChild("Util"))

local Runtime = require(script.Parent.Runtime)
local Net = require(script.Parent.Net)
local PactLedger = require(script.Parent.PactLedger)

local PactSystem = {}

export type Relation = "Pact" | "Hostile" | "Neutral"

type PromptRecord = {
	a: number,
	b: number,
	startedAt: number,
	expiresAt: number,
	choiceA: Types.PactChoice?,
	choiceB: Types.PactChoice?,
	resolved: boolean,
}

type PactRecord = {
	a: number,
	b: number,
	formedAt: number,
}

local prompts: { [string]: PromptRecord } = {}
local pacts: { [string]: PactRecord } = {}
local hostile: { [string]: boolean } = {}
local cooldowns: { [string]: number } = {}

--- Whether a player's weapon counts as lowered (toggle on AND not fired lately).
function PactSystem.isLowered(ps: Runtime.PlayerState, now: number): boolean
	if not ps.weaponLowered then
		return false
	end
	return (now - ps.lastFiredAt) >= Config.Pact.loweredAfterSeconds
end

--- Symmetric pair relation, used to gate friendly fire and revives.
function PactSystem.relation(a: number, b: number): Relation
	local key = Util.pairKey(a, b)
	if pacts[key] ~= nil then
		return "Pact"
	elseif hostile[key] then
		return "Hostile"
	end
	return "Neutral"
end

--- True if `healer` may revive `target`.
function PactSystem.canRevive(healer: number, target: number): boolean
	return PactSystem.relation(healer, target) == "Pact"
end

--- Whether `attacker` is allowed to damage `victim`.
function PactSystem.canDamage(attacker: number, victim: number): boolean
	if attacker == victim then
		return false
	end
	local relation = PactSystem.relation(attacker, victim)
	-- Friendly fire is off for allies; only an explicit FIGHT enables PvP.
	return relation == "Hostile"
end

--- Called by the weapon system whenever one player damages another. Breaks any
--- existing pact between them and bumps the ledger permanently.
function PactSystem.registerDamage(attacker: number, victim: number): ()
	local key = Util.pairKey(attacker, victim)
	local pact = pacts[key]
	if pact ~= nil then
		pacts[key] = nil
		PactLedger.recordBroken(attacker, victim)
		hostile[key] = true
		local attackerPs = Runtime.getStateByUserId(attacker)
		local victimPs = Runtime.getStateByUserId(victim)
		local history = PactLedger.history(attacker, victim, false)
		if attackerPs ~= nil then
			local payload: Types.PactResultPayload = {
				partnerUserId = victim,
				partnerName = victimPs and victimPs.player.DisplayName or "Unknown",
				outcome = "Ignored",
				broken = true,
				history = history,
			}
			Net.send(attackerPs.player, "PactResult", payload)
		end
		if victimPs ~= nil then
			local payload: Types.PactResultPayload = {
				partnerUserId = attacker,
				partnerName = attackerPs and attackerPs.player.DisplayName or "Unknown",
				outcome = "Ignored",
				broken = true,
				history = history,
			}
			Net.send(victimPs.player, "PactResult", payload)
		end
	end
end

local function beginPrompt(a: Runtime.PlayerState, b: Runtime.PlayerState, now: number): ()
	local key = Util.pairKey(a.userId, b.userId)
	local window = Config.Pact.decisionWindow
	prompts[key] = {
		a = a.userId,
		b = b.userId,
		startedAt = now,
		expiresAt = now + window,
		choiceA = nil,
		choiceB = nil,
		resolved = false,
	}
	cooldowns[key] = now + Config.Pact.promptCooldown

	local distance = (a.position - b.position).Magnitude
	local history = PactLedger.history(a.userId, b.userId, false)

	local payloadA: Types.PactPromptPayload = {
		partnerUserId = b.userId,
		partnerName = b.player.DisplayName,
		distance = distance,
		history = history,
		window = window,
	}
	local payloadB: Types.PactPromptPayload = {
		partnerUserId = a.userId,
		partnerName = a.player.DisplayName,
		distance = distance,
		history = history,
		window = window,
	}
	Net.send(a.player, "PactPrompt", payloadA)
	Net.send(b.player, "PactPrompt", payloadB)
end

local function resolve(record: PromptRecord): ()
	record.resolved = true
	local key = Util.pairKey(record.a, record.b)
	prompts[key] = nil

	local aPs = Runtime.getStateByUserId(record.a)
	local bPs = Runtime.getStateByUserId(record.b)

	local choiceA: Types.PactDecision = record.choiceA or "None"
	local choiceB: Types.PactDecision = record.choiceB or "None"

	if choiceA == "Ally" and choiceB == "Ally" then
		pacts[key] = { a = record.a, b = record.b, formedAt = Runtime.now() }
		hostile[key] = nil
		local history = PactLedger.history(record.a, record.b, true)
		if aPs then
			Net.send(
				aPs.player,
				"PactResult",
				{
					partnerUserId = record.b,
					partnerName = bPs and bPs.player.DisplayName or "Unknown",
					outcome = "Pacted",
					broken = false,
					history = history,
				} :: Types.PactResultPayload
			)
		end
		if bPs then
			Net.send(
				bPs.player,
				"PactResult",
				{
					partnerUserId = record.a,
					partnerName = aPs and aPs.player.DisplayName or "Unknown",
					outcome = "Pacted",
					broken = false,
					history = history,
				} :: Types.PactResultPayload
			)
		end
	elseif choiceA == "Fight" or choiceB == "Fight" then
		hostile[key] = true
		pacts[key] = nil
		local history = PactLedger.history(record.a, record.b, false)
		if aPs then
			Net.send(
				aPs.player,
				"PactResult",
				{
					partnerUserId = record.b,
					partnerName = bPs and bPs.player.DisplayName or "Unknown",
					outcome = "Hostile",
					broken = false,
					history = history,
				} :: Types.PactResultPayload
			)
		end
		if bPs then
			Net.send(
				bPs.player,
				"PactResult",
				{
					partnerUserId = record.a,
					partnerName = aPs and aPs.player.DisplayName or "Unknown",
					outcome = "Hostile",
					broken = false,
					history = history,
				} :: Types.PactResultPayload
			)
		end
	else
		local history = PactLedger.history(record.a, record.b, false)
		if aPs then
			Net.send(
				aPs.player,
				"PactResult",
				{
					partnerUserId = record.b,
					partnerName = bPs and bPs.player.DisplayName or "Unknown",
					outcome = "Ignored",
					broken = false,
					history = history,
				} :: Types.PactResultPayload
			)
		end
		if bPs then
			Net.send(
				bPs.player,
				"PactResult",
				{
					partnerUserId = record.a,
					partnerName = aPs and aPs.player.DisplayName or "Unknown",
					outcome = "Ignored",
					broken = false,
					history = history,
				} :: Types.PactResultPayload
			)
		end
	end
end

--- Server handler for the client's choice. Server-authoritative: an unknown or
--- already-resolved prompt is silently discarded.
function PactSystem.onChoice(player: Player, partnerUserId: number, choice: string): ()
	local ps = Runtime.getState(player)
	if ps == nil or not ps.alive or ps.downed or ps.extracted then
		return
	end
	if choice ~= "Ally" and choice ~= "Fight" and choice ~= "Ignore" then
		return
	end
	local key = Util.pairKey(player.UserId, partnerUserId)
	local record = prompts[key]
	if record == nil or record.resolved then
		return
	end
	local now = Runtime.now()
	if now > record.expiresAt then
		return
	end
	if record.a == player.UserId then
		record.choiceA = choice
	elseif record.b == player.UserId then
		record.choiceB = choice
	else
		return
	end
	if record.choiceA ~= nil and record.choiceB ~= nil then
		resolve(record)
	end
end

local function step(_dt: number, now: number): ()
	local states = Runtime.aliveStates()

	-- Open new prompts.
	for i = 1, #states do
		for j = i + 1, #states do
			local a = states[i]
			local b = states[j]
			local key = Util.pairKey(a.userId, b.userId)
			if prompts[key] == nil and pacts[key] == nil and not hostile[key] then
				local distance = (a.position - b.position).Magnitude
				local cooldown = cooldowns[key] or 0
				if
					distance <= Config.Pact.radius
					and now >= cooldown
					and PactSystem.isLowered(a, now)
					and PactSystem.isLowered(b, now)
				then
					beginPrompt(a, b, now)
				end
			end
		end
	end

	-- Expire un-answered prompts: a missing choice is an IGNORE.
	for _key, record in pairs(prompts) do
		if not record.resolved and now > record.expiresAt then
			resolve(record)
		end
	end
end

--- Number of live pacts (debrief / diagnostics).
function PactSystem.activePactCount(): number
	local count = 0
	for _ in pairs(pacts) do
		count += 1
	end
	return count
end

--- Marks every surviving pact as KEPT in the ledger, then clears pacts.
function PactSystem.settleKept(): ()
	for _key, pact in pairs(pacts) do
		PactLedger.recordKept(pact.a, pact.b)
	end
	pacts = {}
	hostile = {}
end

--- Clears all transient decision state between rounds (ledger is preserved).
function PactSystem.resetRound(): ()
	prompts = {}
	pacts = {}
	hostile = {}
	cooldowns = {}
end

--- Binds remotes and registers the step. Call once at boot.
function PactSystem.start(): ()
	local remotes = Net.remotes()
	remotes.events.PactChoice.OnServerEvent:Connect(
		function(player: Player, partnerUserId: unknown, choice: unknown)
			if typeof(partnerUserId) == "number" and typeof(choice) == "string" then
				PactSystem.onChoice(player, partnerUserId, choice)
			end
		end
	)

	-- Revive: the healer revives the nearest downed PACT ally in range.
	remotes.events.ReviveRequest.OnServerEvent:Connect(function(player: Player)
		local ps = Runtime.getState(player)
		if ps == nil or ps.downed or not ps.alive then
			return
		end
		local best: Runtime.PlayerState? = nil
		local bestDist = Config.Pact.reviveRange
		for _, other in pairs(Runtime.allStates()) do
			if other.userId ~= ps.userId and other.downed and PactSystem.canRevive(ps.userId, other.userId) then
				local dist = (other.position - ps.position).Magnitude
				if dist <= bestDist then
					bestDist = dist
					best = other
				end
			end
		end
		if best ~= nil then
			best.downed = false
			best.health = best.maxHealth
			Net.send(best.player, "HudState", Runtime.service("Round").hudFor(best))
		end
	end)

	-- One-shot snapshot so a late joiner is never blank.
	remotes.functions.GetInitialState.OnServerInvoke = function(player: Player)
		local ps = Runtime.getState(player)
		if ps == nil then
			return nil
		end
		local Round = Runtime.service("Round")
		return {
			round = Round.payload(),
			hud = Round.hudFor(ps, Runtime.service("Extraction").progressFor(ps.userId)),
		}
	end

	Runtime.registerStep(step)
end

return PactSystem
