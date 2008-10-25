--[[ 
	Expiration, Mayen/Amarand/Dayliss from Icecrown (US) PvE
]]

Expiration = LibStub("AceAddon-3.0"):NewAddon("Expiration", "AceEvent-3.0")

local L = ExpirationLocals
local groupInfo = {}
local groupUnitMap = {}
local raidMap, partyMap = {}, {}
local validTypes = {
	["party"] = "PARTY", ["p"] = "PARTY",
	["raid"] = "RAID", ["r"] = "RAID",
	["guild"] = "GUILD", ["g"] = "GUILD",
	["officer"] = "OFFICER", ["o"] = "OFFICE",
	["whisper"] = "WHISPER", ["w"] = "WHISPER",
	["channel"] = "CHANNEL", ["c"] = "CHANNEL",
}


function Expiration:OnInitialize()
	self.defaults = {
		profile = {
			lines = 20,
			threshold = 0,
			reports = 5,
			health = true,
			location = "console",
		},
	}

	self.db = LibStub:GetLibrary("AceDB-3.0"):New("ExpirationDB", self.defaults)
	--self.db.RegisterCallback(self, "OnProfileChanged", "Reload")
	--self.db.RegisterCallback(self, "OnProfileCopied", "Reload")
	--self.db.RegisterCallback(self, "OnProfileReset", "Reload")

	self.revision = tonumber(string.match("$Revision: 979 $", "(%d+)") or 1)

	self:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
	self:RegisterEvent("PLAYER_ENTERING_WORLD", "UpdateRoster")
	self:RegisterEvent("RAID_ROSTER_UPDATED", "UpdateRoster")
	
	-- So we don't have to keep creating these
	for i=1, MAX_RAID_MEMBERS do
		table.insert(raidMap, "raid" .. i)
	end
	
	for i=1, MAX_PARTY_MEMBERS do
		table.insert(partyMap, "party" .. i)
	end
end

SLASH_EXPIRATION1 = "/expiration"
SLASH_EXPIRATION2 = "/exp"
SlashCmdList["EXPIRATION"] = function(msg)
	local self = Expiration
	local cmd, arg = string.split(" ", msg or "", 2)
	cmd = string.lower(cmd or "")
	
	if( cmd == "lines" and arg ) then
		self.db.profile.lines = tonumber(arg) or self.db.profile.lines
		self:Print(string.format(L["Total lines stored per death set to %d."], self.db.profile.lines))
	
	elseif( cmd == "threshold" and arg ) then
		self.db.profile.threshold = tonumber(arg) or self.db.profile.threshold
		self:Print(string.format(L["Damage/healing threshold set to %d."], self.db.profile.threshold))
		
	elseif( cmd == "reports" and arg ) then
		self.db.profile.reports = tonumber(arg) or self.db.profile.reports
		self:Print(string.format(L["Total saved death reports set to %d."], self.db.profile.reports))
	
	elseif( cmd == "location" and arg ) then
		arg = string.lower(arg)
		if( arg ~= "console" and not validTypes[arg] ) then
			self:Print(string.format(L["Invalid report location entered \"%s\"."], arg))
			return
		end
		
		self.db.profile.location = arg
		self:Print(string.format(L["Set default report location to \"%s\"."], arg))

	elseif( cmd == "health" ) then
		self.db.profile.health = not self.db.profile.health
		
		if( self.db.profile.health ) then
			self:Print(L["Now showing health in death reports."])
		else
			self:Print(L["No longer showing health in death reports."])
		end
	
	elseif( cmd == "report" and arg ) then
		local name, report, dest, lines = string.split(" ", arg)
		if( not name ) then
			self:Print(L["You must provide a name to report on."])
			return
		end
		
		report = report and string.lower(report) or nil
		dest = dest and string.lower(dest) or nil
		
		self:Report(name, report, dest, lines)
	else
		self:Print(L["Slash commands"])
		self:Echo(L["/expiration lines <num> - Total number of lines to save per a death report."])
		self:Echo(L["/expiration threshold <num> - Minimum number of damage/healing needed to save the event."])
		self:Echo(L["/expiration reports <num> - Total number of death reports to save per a person."])
		self:Echo(L["/expiration location <console/raid/party/guild/officer> - Default location to send reports."])
		self:Echo(L["/expiration report <name> <report# or \'last\'> [dest[:target]] [lines] - Report on a given player."])
	end
end

-- Events to watch in general
local events = {
	["ENVIRONMENTAL_DAMAGE"] = 2,
	["SWING_DAMAGE"] = 1,
	["RANGE_DAMAGE"] = 4,
	["SPELL_DAMAGE"] = 4,
	["SPELL_HEAL"] = 4,
	["SPELL_DRAIN"] = 4,
	["SPELL_LEECH"] = 4,
	["SPELL_INSTAKILL"] = -1,
	["SPELL_AURA_APPLIED"] = -1,
	["SPELL_AURA_APPLIED_DOSE"] = -1,
	["SPELL_AURA_REFRESHED"] = -1,
	["SPELL_AURA_REMOVED"] = -1,
	["SPELL_AURA_REMOVED_DOSE"] = -1,
	["SPELL_AURA_DISPELLED"] = -1,
	["SPELL_AURA_STOLEN"] = -1,
	["SPELL_PERIODIC_DAMAGE"] = 4,
	["SPELL_PERIODIC_HEAL"] = 4,
	["SPELL_PERIODIC_DRAIN"] = 4,
	["SPELL_PERIODIC_LEECH"] = 4,
	["SPELL_DISPEL_FAILED"] = -1,
	["DAMAGE_SHIELD"] = 4,
	["UNIT_DIED"] = -1,
	["UNIT_DESTROYED"] = -1,
}

-- Events to show what finished a player
local killEvents = {
	["ENVIRONMENTAL_DAMAGE"] = true,
	["SWING_DAMAGE"] = true,
	["RANGE_DAMAGE"] = true,
	["SPELL_DAMAGE"] = true,
	["SPELL_DRAIN"] = true,
	["SPELL_LEECH"] = true,
	["SPELL_INSTAKILL"] = true,
	["SPELL_PERIODIC_DAMAGE"] = true,
	["SPELL_PERIODIC_DRAIN"] = true,
	["SPELL_PERIODIC_LEECH"] = true,
	["DAMAGE_SHIELD"] = true,
}

-- We only care about things that happen to group members
local COMBATLOG_OBJECT_AFFILIATION_MINE = COMBATLOG_OBJECT_AFFILIATION_MINE
local COMBATLOG_OBJECT_AFFILIATION_PARTY = COMBATLOG_OBJECT_AFFILIATION_PARTY
local COMBATLOG_OBJECT_AFFILIATION_RAID = COMBATLOG_OBJECT_AFFILIATION_RAID
local COMBATLOG_OBJECT_TYPE_PLAYER = COMBATLOG_OBJECT_TYPE_PLAYER
local GROUP_AFFILIATION = bit.bor(COMBATLOG_OBJECT_AFFILIATION_PARTY, COMBATLOG_OBJECT_AFFILIATION_RAID, COMBATLOG_OBJECT_AFFILIATION_MINE)

function Expiration:COMBAT_LOG_EVENT_UNFILTERED(event, timestamp, eventType, sourceGUID, sourceName, sourceFlags, destGUID, destName, destFlags, ...)
	if( not events[eventType] or ( bit.band(destFlags, GROUP_AFFILIATION) == 0 or bit.band(destFlags, COMBATLOG_OBJECT_TYPE_PLAYER) ~= COMBATLOG_OBJECT_TYPE_PLAYER ) ) then return end
	
	groupInfo[destGUID] = groupInfo[destGUID] or {history = {}, reports = {}}
	
	local playerInfo = groupInfo[destGUID]
	if( killEvents[eventType] ) then
		playerInfo.lastEvent = eventType
		playerInfo.lastSpell = eventType == "ENVIRONMENTAL_DAMAGE" and getglobal("ACTION_ENVIRONMENTAL_DAMAGE_" .. (select(1, ...))) or eventType == "SWING_DAMAGE" and L["Melee"] or (select(2, ...))
		playerInfo.lastSource = eventType == "ENVIRONMENTAL_DAMAGE" and L["Environment"] or sourceName
	end
	
	if( events[eventType] > 0 and (select(events[eventType], ...)) < self.db.profile.threshold ) then
		return
	end
	
	self:AddEvent(destGUID, timestamp, CombatLog_OnEvent(Blizzard_CombatLog_CurrentSettings, timestamp, eventType, sourceGUID, sourceName, sourceFlags, destGUID, destName, destFlags, ...))

	-- They died, so wrap this up into a report
	if( eventType == "UNIT_DIED" ) then
		self:AddReport(destGUID)
	end
end


-- Add an event message to the specified id history
function Expiration:AddEvent(guid, timestamp, message)
	if( not message ) then return end
	local playerInfo = groupInfo[guid]
	
	if( #(playerInfo.history) >= self.db.profile.lines ) then
		table.remove(playerInfo.history, 1)
	end
		
	-- Format with health
	if( self.db.profile.health and groupUnitMap[guid] ) then
		local health = UnitHealth(groupUnitMap[guid])
		local percent = health / UnitHealthMax(groupUnitMap[guid])
		local r, g
		
		if( percent > 0.5 ) then
			r = 510 * (1 - percent)
			g = 255
		else
			r = 255
			g = 510 * percent
		end
		
		table.insert(playerInfo.history, string.format("%05.2f [|cff%02X%02X00%d %d%%|r] %s", timestamp % 60, r, g, health, percent * 100, message))
	else
		table.insert(playerInfo.history, string.format("%05.2f %s", timestamp % 60, message))
	end
end

function Expiration:AddReport(guid)
	local playerInfo = groupInfo[guid]
	local report
	
	-- Reuse an old report if we can
	if( #(playerInfo.reports) >= self.db.profile.reports ) then
		report = tabel.remove(playerInfo.reports, 1)
		
		for i=#(report), 1, -1 do
			table.remove(report, i)
		end
	else
		report = {}
	end
	
	report.time = time()
	
	-- Figure out what killed them (If we can)
	if( playerInfo.lastSource and playerInfo.lastSpell ) then
		report.cause = string.format("%s (%s)", playerInfo.lastSource, playerInfo.lastSpell)
	elseif( playerInfo.lastSource ) then
		report.cause = playerInfo.lastSource
	elseif( playerInfo.lastSpell ) then
		report.cause = playerInfo.lastSpell
	else
		report.cause = "???"
	end
	
	-- Copy the report in
	for id, msg in pairs(playerInfo.history) do
		report[id] = msg
	end
	
	
	table.insert(playerInfo.reports, report)
end
	
-- Send a report
function Expiration:Report(name, reportNum, dest, lines)
	-- Search for the player
	local playerInfo
	for guid, unit in pairs(groupUnitMap) do
		local uName = string.lower(UnitName(unit) or "")
		if( string.lower(name) == uName ) then
			playerInfo = groupInfo[guid]
			break
		end
	end
	
	if( not playerInfo ) then
		self:Print(string.format(L["No data found for player \"%s\"."], name))
		return
	end
	
	if( #(playerInfo.reports) == 0 ) then
		self:Print(string.format(L["No deaths found for player \"%s\"."], name))
		return
	end

	-- No report specified, list them all
	local report
	if( not reportNum ) then
		self:Print(string.format(L["Deaths for player %s (%d total)"], name, #(playerInfo.reports)))
		for id, report in pairs(playerInfo.reports) do
			self:Echo(string.format("%d) %s - %s", id, date("%H:%M:%S"), report.cause))
		end
		return
	-- Use the last found report
	elseif( reportNum == "last" ) then
		report = playerInfo.reports[#(playerInfo.reports)]
	-- Use a specific ID
	else
		report = playerInfo.reports[tonumber(reportNum) or 0]
	end
	
	-- No report found with this ID
	if( not report ) then
		self:Print(string.format(L["Cannot find report id \"%s\" for \"%s\"."], reportNum or "", name))
		return
	end
	
	if( type(dest) == "string" ) then
		dest = string.lower(dest)
		lines = tonumber(lines)
	else
		lines = tonumber(dest)
		dest = self.db.profile.location
	end
	
	-- Make sure it's a valid line count
	lines = lines or self.db.profile.lines
	lines = lines < 1 and 1 or lines > #(report) and #(report) or lines
	
	-- WHISPER:Distomos, CHANNEL:1, etc
	local type, target = strsplit(":", dest, 2);
	target = string.trim(target or "")
	
	if( type == "console" ) then
		self:Print(string.format(L["Report for %s (Last %d events)"], name, lines))
		for line = #(report) - lines + 1, #(report) do
			self:Echo(string.format("%d. %s", #report - line + 1, report[line]))
		end
		return
	elseif( not validType[type] ) then
		self:Print(string.format(L["Invalid chat destination entered \"%s\"."], type))
		return
	end
	
	if( ( type == "PARTY" and GetNumPartyMembers() == 0 ) or ( type == "RAID" and GetNumRaidMembers() == 0 ) ) then
		self:Print(string.format(L["You must be in a %s to use this destination."], L[type]))
		return
	elseif( ( type == "GUILD" or type == "OFFICER" ) and not IsInGuild() ) then
		self:Print(string.format(L["You must be in a %s to use this destination."], L["GUILD"]))
		return
	elseif( type == "WHISPER" or type == "CHANNEL" ) then
		if( target == "" ) then
			self:Print(L["You must enter a destination for this channel destination."])
			return
		end
		
		if( type == "CHANNEL" ) then
			local id = GetChannelName(target)
			if( not id or id == 0 ) then
				self:Print(string.format(L["You are not in channel #%d."], target))
				return
			end
			
			target = id
		end
	end
	
	-- Finally, send it out
	target = target == "" and nil or target
	
	SendChatMessage(string.format(L["Expiration report for %s (Last %d events)"], name, lines), type, nil, target)
	for line = #(report - lines + 1), #(report) do
		SendChatMessage(string.format("%d. %s", #report - line + 1, report[line]), type, nil, target)
	end
end


function Expiration:UpdateRoster()
	for i=1, GetNumRaidMembers() do
		groupUnitMap[UnitGUID(raidMap[i])] = raidMap[i]
	end

	for i=1, GetNumPartyMembers() do
		groupUnitMap[UnitGUID(partyMap[i])] = partyMap[i]
	end

	groupUnitMap[UnitGUID("player")] = "player"
end

function Expiration:Echo(msg)
	DEFAULT_CHAT_FRAME:AddMessage(msg)
end

function Expiration:Print(msg)
	DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99Expiration|r: " .. msg)
end

-- ID -> Icon code
local icons = {"{rt1}", "{rt2}", "{rt3}", "{rt4}", "{rt5}", "{rt6}", "{rt7}", "{rt8}"}
local function getIconTag(id)
	return icons[tonumber(id)]
end

-- Strip codes we can't send with SendChatMessage
function Expiration:CleanString(msg)
	msg = string.gsub(msg, "|c%x%x%x%x%x%x%x%x(.-)|r", "%1")
	msg = string.gsub(msg, "|Hunit:0x%x+:(.-)|h.-|h", "%1")
	msg = string.gsub(msg, "|Haction:.-|h(.-)|h", "%1")
	msg = string.gsub(msg, "|Hicon:%d+:%a-|h|TInterface\\TargetingFrame\\UI%-RaidTargetingIcon_(%d)%.blp:%d|t|h", getIconTag)
	msg = string.gsub(msg, "|Hspell:.-:.-|h(.-)|h", "%1")

	if( GetLocale() == "koKR" ) then
		msg = string.gsub(msg, "|1??", "?(?)")
		msg = string.gsub(msg, "|1??", "?(?)")
		msg = string.gsub(msg, "|1???", "??(?)")
	end

	return msg
end
