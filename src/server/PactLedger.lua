--!strict
--[[
	PactLedger.lua — the permanent memory of every promise.

	The ledger is keyed by the ordered pair of UserIds (Util.pairKey) and lives
	for the whole server session. It survives respawn because it never touches
	Player instances; it is a pure UserId -> counts table.

	Contract:
	  * kept   increments when a pact runs its course (both extract, or the
	           round ends with the pact unbroken).
	  * broken increments PERMANENTLY the moment a pacted partner lands damage
	    on the other party.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Types = require(Shared:WaitForChild("Types"))
local Util = require(Shared:WaitForChild("Util"))

local PactLedger = {}

local ledger: { [string]: Types.LedgerEntry } = {}

local function ensure(key: string): Types.LedgerEntry
	local entry = ledger[key]
	if entry == nil then
		entry = { kept = 0, broken = 0 }
		ledger[key] = entry
	end
	return entry
end

--- Returns the history between two UserIds (never nil).
function PactLedger.get(a: number, b: number): Types.LedgerEntry
	local key = Util.pairKey(a, b)
	return ensure(key)
end

--- Records a broken pact between two UserIds. Permanent for the session.
function PactLedger.recordBroken(a: number, b: number): Types.LedgerEntry
	local entry = ensure(Util.pairKey(a, b))
	entry.broken += 1
	return entry
end

--- Records a kept pact between two UserIds.
function PactLedger.recordKept(a: number, b: number): Types.LedgerEntry
	local entry = ensure(Util.pairKey(a, b))
	entry.kept += 1
	return entry
end

--- Builds the wire-friendly history for one pair.
function PactLedger.history(a: number, b: number, pacted: boolean): Types.PactHistory
	local entry = ensure(Util.pairKey(a, b))
	return {
		kept = entry.kept,
		broken = entry.broken,
		pacted = pacted,
	}
end

--- Snapshot for the debrief: every pair this player has history with.
function PactLedger.snapshotFor(
	userId: number,
	nameFor: (number) -> string?
): { Types.DebriefPactRow }
	local rows: { Types.DebriefPactRow } = {}
	for key, entry in pairs(ledger) do
		local lo, hi = string.match(key, "^(%d+):(%d+)$")
		if lo and hi then
			local lowId = tonumber(lo) :: number
			local highId = tonumber(hi) :: number
			if lowId == userId or highId == userId then
				local otherId = if lowId == userId then highId else lowId
				local name = nameFor(otherId)
				if name ~= nil then
					table.insert(rows, { name = name, kept = entry.kept, broken = entry.broken })
				end
			end
		end
	end
	table.sort(rows, function(a, b)
		return a.name < b.name
	end)
	return rows
end

--- Resets the ledger (round teardown / tests).
function PactLedger.reset(): ()
	ledger = {}
end

return PactLedger
