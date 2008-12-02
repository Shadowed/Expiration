--[[ 
	Expiration, Mayen/Amarand/Dayliss from Icecrown (US) PvE
]]

Expiration = LibStub("AceAddon-3.0"):NewAddon("Expiration", "AceEvent-3.0")
ExpirationTest = {}

local L = ExpirationLocals
local groupInfo = ExpirationTest
local nameToGUID = {}
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
			cooldowns = false,
			location = "console",
		},
	}

	self.db = LibStub:GetLibrary("AceDB-3.0"):New("ExpirationDB", self.defaults)
	self.revision = tonumber(string.match("$Revision$", "(%d+)") or 1)
	self.cooldowns = ExpirationSpells

	self:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
	
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
		if( arg ~= "console" and arg ~= "frame" and not validTypes[arg] ) then
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
	--[[
	elseif( cmd == "cooldowns" ) then
		self.db.profile.cooldowns = not self.db.profile.cooldowns
		
		if( self.db.profile.health ) then
			self:Print(L["Now keeping track of player cooldowns on death."])
		else
			self:Print(L["No longer track of player cooldowns on death."])
		end
	]]
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
		self:Echo(L["/expiration location <console/frame/raid/party/guild/officer> - Default location to send reports."])
		self:Echo(L["/expiration health - Toggles showing players health in death report."])
		--self:Echo(L["/expiration cooldown - Toggles showing players cooldowns in death report."])
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
	--["SPELL_CAST_SUCCESS"] = -1,
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
	if( not events[eventType] or bit.band(destFlags, COMBATLOG_OBJECT_TYPE_PLAYER) ~= COMBATLOG_OBJECT_TYPE_PLAYER or ( bit.band(destFlags, COMBATLOG_OBJECT_AFFILIATION_PARTY) ~= COMBATLOG_OBJECT_AFFILIATION_PARTY and bit.band(destFlags, COMBATLOG_OBJECT_AFFILIATION_RAID) ~= COMBATLOG_OBJECT_AFFILIATION_RAID and bit.band(destFlags, COMBATLOG_OBJECT_AFFILIATION_MINE) ~= COMBATLOG_OBJECT_AFFILIATION_MINE ) ) then return end
	
	groupInfo[destGUID] = groupInfo[destGUID] or {history = {}, reports = {}, fades = {}}
	local playerInfo = groupInfo[destGUID]
	
	-- Save cooldown information
	--if( self.db.profile.cooldowns and eventType == "SPELL_CAST_SUCCESS" ) then
	--	return
	--end
	
	-- Save last event in case they died after
	if( killEvents[eventType] ) then
		playerInfo.lastEvent = eventType
		playerInfo.lastSpell = eventType == "ENVIRONMENTAL_DAMAGE" and getglobal("ACTION_ENVIRONMENTAL_DAMAGE_" .. (select(1, ...))) or eventType == "SWING_DAMAGE" and L["Melee"] or (select(2, ...))
		playerInfo.lastSource = eventType == "ENVIRONMENTAL_DAMAGE" and L["Environment"] or sourceName
		playerInfo.lastTime = timestamp
	end
	
	if( events[eventType] > 0 and (select(events[eventType], ...)) < self.db.profile.threshold ) then
		return
	end
		
	-- Store everything in our regular history table, but put it into the fades table if a buff faded
	-- this way we can compact it more
	local field = "history"
	if( eventType == "SPELL_AURA_REMOVED" and select(4, ...) == "BUFF" ) then
		field = "fades"	
	end
	
	self:AddEvent(field, destName, destGUID, timestamp, eventType, sourceGUID, sourceName, sourceFlags, destGUID, destName, destFlags, ...)
	
	-- They died, so wrap this up into a report
	if( eventType == "UNIT_DIED" ) then
		self:AddReport(timestamp, destGUID)
	
		-- Lets us see info on people even if they left the raid
		nameToGUID[string.lower(destName)] = destGUID
	end
end

-- Simply lets us store this in a more usable format for post processing when we need it
local function compactList(...)
	local text = ""
	for i=1, select("#", ...) do
		if( i > 1 ) then
			text = text .. "|" .. (select(i, ...) or "!nil")
		else
			text = select(i, ...) or "!nil"
		end
	end
	
	return text
end

-- Add an event message to the specified id history
function Expiration:AddEvent(field, name, guid, ...)
	-- No info found
	local playerInfo = groupInfo[guid]
	if( not playerInfo ) then
		return
	end
	
	-- Prune old record if we hit our limit
	if( #(playerInfo[field]) >= self.db.profile.lines ) then
		table.remove(playerInfo[field], 1)
	end
		
	-- Add the current and max health
	local health = ""
	local healthMax = ""
	if( self.db.profile.health and UnitExists(name) ) then
		health = UnitHealth(name)
		healthMax = UnitHealthMax(name)
	end
	
	table.insert(playerInfo[field], compactList(health, healthMax, ...))
end

function Expiration:AddReport(timestamp, guid)
	local playerInfo = groupInfo[guid]
	local report
	
	-- Reuse an old report if we can
	if( #(playerInfo.reports) >= self.db.profile.reports ) then
		report = table.remove(playerInfo.reports, 1)
		report.isParsed = nil
		
		-- Reset what we have saved
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
		report.deathStamp = playerInfo.lastTime
	elseif( playerInfo.lastSource ) then
		report.cause = playerInfo.lastSource
		report.deathStamp = playerInfo.lastTime
	elseif( playerInfo.lastSpell ) then
		report.cause = playerInfo.lastSpell
		report.deathStamp = playerInfo.lastTime
	else
		report.cause = "???"
		report.deathStamp = timestamp
	end
	
	-- Move the data of the death into the report
	for _, data in pairs(playerInfo.history) do
		table.insert(report, data)
	end
	
	for _, data in pairs(playerInfo.fades) do
		table.insert(report, data)
	end
	
	-- Store this death
	table.insert(playerInfo.reports, report)
	
	-- Reset our saved data
	playerInfo.lastTime = nil
	
	for i=#(playerInfo.history), 1, -1 do table.remove(playerInfo.history, i) end
	for i=#(playerInfo.fades), 1, -1 do table.remove(playerInfo.fades, i) end
end

-- Sort it using the timestamp	
local function sortReport(a, b)
	local timeA = select(3, string.split("|", a))
	local timeB = select(3, string.split("|", b))
	
	return timeA < timeB
end

-- Tries to get the compressed spells to look as close as possible to the Blizzard ones
-- but it's not 100% perfect since I don't want to reimplement the entire damn thing
local defaultLineColor = { a = 1.0, r = 1.0, g = 1.0, b = 1.0 }
local function parseSpell(eventType, spellID, spellName, spellSchool)
	local settings = Blizzard_CombatLog_CurrentSettings.settings

	-- Color ability names
	if( settings.abilityColoring ) then
		if( settings.abilitySchoolColoring ) then
			abilityColor = CombatLog_Color_ColorArrayBySchool(tonumber(spellSchool), filterSettings)
		elseif( spellSchool ) then 
			abilityColor = settings.colors.defaults.spell
		end
	end

	-- Highlight this color
	if( settings.abilityHighlighting ) then
		abilityColor = CombatLog_Color_HighlightColorArray(abilityColor or defaultLineColor)
	end
	
	if( abilityColor ) then
		abilityColor = CombatLog_Color_FloatToText(abilityColor)
		spellName = string.format("|c%s%s|r", abilityColor, spellName)
	end

	if( settings.braces and settings.spellBraces ) then
		spellName = string.format(TEXT_MODE_A_STRING_BRACE_SPELL, "FFFFFFFF", spellName, "FFFFFFFF")
	end
	
	local text = string.format(TEXT_MODE_A_STRING_SPELL, spellID, eventType, spellName, spellID)
	
	return text
end

-- Parse the data into the actual Blizzard text value
local messageData = {}
local function parseMessage(...)
	-- This is a little bit of a hack, we need to convert everything into a number if needed
	-- because Blizzard expects it to be one, but since we can't modify a vararg
	-- we have to push it all into a table, I'll come up with a cleaner method soon thats not ugly.
	for id in pairs(messageData) do messageData[id] = nil end
	for i=3, select("#", ...) do
		local data = select(i, ...)
		if( data ~= "!nil" ) then
			messageData[i - 2] = tonumber(data) or data
		end
	end
	
	-- Parse it into the combat log format
	local text = CombatLog_OnEvent(Blizzard_CombatLog_CurrentSettings, unpack(messageData))
	
	-- Add the health info we have to
	local health, maxHealth = select(1, ...)
	health = tonumber(health)
	maxHealth = tonumber(maxHealth)
	
	if( health and maxHealth ) then
		local percent = health / maxHealth
		local r, g
		if( percent > 0.5 ) then
			r = 510 * (1 - percent)
			g = 255
		else
			r = 255
			g = 510 * percent
		end
		
		return string.format("%05.2f [|cff%02X%02X00%d %d%%|r] %s", messageData[1] % 60, r, g, health, percent * 100, text)
	end

	return string.format("%05.2f %s", messageData[1] % 60, text)
end

-- Parse the report if needed
-- Because we store reports with the raw data we're provided instead of parsing them, we might have to
-- compile it all into readable text and do fancy work like that.
local compressedBuffs = {}
local function parseReport(report)
	if( report.isParsed ) then
		return
	end

	report.isParsed = true

	-- Sort the table so the the last entry is the death
	table.sort(report, sortReport)

	-- Compress all buff fades within the last 0.5 seconds before we died
	local buffThreshold = report.deathStamp - 0.5

	-- Reset our temp table for buffs
	for i=#(compressedBuffs), 1, -1 do table.remove(compressedBuffs, i) end

	-- Now find all buffs that faded within the threshold
	local savedData
	for i=#(report), 1, -1 do
		local data = report[i]
		local timestamp, eventType, _, _, _, _, _, _, spellID, spellName, spellSchool, auraType = select(3, string.split("|", data))
		if( eventType == "SPELL_AURA_REMOVED" and auraType == "BUFF" ) then
			if( tonumber(timestamp) >= buffThreshold ) then
				table.insert(compressedBuffs, parseSpell(eventType, spellID, spellName, spellSchool))

				-- If it's the first buff we added, will "save" it so the rest of the buffs can go in this line
				if( not savedData ) then
					savedData = parseMessage(string.split("|", data))
					report[i] = "SAVED"
				else
					table.remove(report, i)
				end
			else
				report[i] = parseMessage(string.split("|", data))
			end
		else
			report[i] = parseMessage(string.split("|", data))
		end
	end

	-- We have compressed buffs
	if( savedData ) then
		-- Because we remove entries, we have to search for our saved one again, slightly silly but oh well.
		for id, data in pairs(report) do
			if( data == "SAVED" ) then
				report[id] = string.gsub(savedData, "|Hspell:(.-)|h(.-)|h", table.concat(compressedBuffs, ", "))
				break
			end
		end
	end
end

-- Show the report in a frame
function Expiration:ReportFrame(name, lines, report)
	if( not self.frame ) then
		local backdrop = {
			bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
			edgeFile = "Interface\\ChatFrame\\ChatFrameBackground",
			tile = true,
			edgeSize = 1,
			tileSize = 5,
			insets = {left = 1, right = 1, top = 1, bottom = 1}
		}

		self.frame = CreateFrame("Frame", nil, UIParent)
		self.frame:SetWidth(550)
		self.frame:SetHeight(275)
		self.frame:SetBackdrop(backdrop)
		self.frame:SetBackdropColor(0.0, 0.0, 0.0, 1.0)
		self.frame:SetBackdropBorderColor(0.65, 0.65, 0.65, 1.0)
		self.frame:SetMovable(true)
		self.frame:EnableMouse(true)
		self.frame:Hide()
		
		-- Positioner thing
		local mover = CreateFrame("Button", nil, self.frame)
		mover:SetPoint("TOPLEFT", self.frame, "TOPLEFT", 0, 0)
		mover:SetPoint("TOPRIGHT", self.frame, "TOPRIGHT", -15, 0)
		mover:SetHeight(18)

		mover:SetScript("OnMouseUp", function(self)
			if( self.isMoving ) then
				local parent = self:GetParent()
				local scale = parent:GetEffectiveScale()

				self.isMoving = nil
				parent:StopMovingOrSizing()

				Expiration.db.profile.position = {x = parent:GetLeft() * scale, y = parent:GetTop() * scale}
			end
		end)

		mover:SetScript("OnMouseDown", function(self, mouse)
			local parent = self:GetParent()

			-- Start moving!
			if( parent:IsMovable() and mouse == "LeftButton" ) then
				self.isMoving = true
				parent:StartMoving()

			-- Reset position
			elseif( mouse == "RightButton" ) then
				parent:ClearAllPoints()
				parent:SetPoint("CENTER", UIParent, "CENTER")

				Expiration.db.profile.position = nil
			end
		end)
		
		self.frame.mover = mover
		
		-- Fix edit box size
		self.frame:SetScript("OnShow", function(self)
			self.child:SetHeight(self.scroll:GetHeight())
			self.child:SetWidth(self.scroll:GetWidth())
			self.editBox:SetWidth(self.scroll:GetWidth())
		end)
		
		-- Report description
		self.frame.title = self.frame:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
		self.frame.title:SetPoint("TOPLEFT", self.frame, "TOPLEFT", 2, -2)
		
		-- Close button (Shocking!)
		local button = CreateFrame("Button", nil, self.frame, "UIPanelCloseButton")
		button:SetPoint("TOPRIGHT", self.frame, "TOPRIGHT", 6, 6)
		button:SetScript("OnClick", function()
			HideUIPanel(self.frame)
		end)
		
		self.frame.closeButton = button
		
		-- Create the container frame for the scroll box
		local container = CreateFrame("Frame", nil, self.frame)
		container:SetHeight(265)
		container:SetWidth(1)
		container:ClearAllPoints()
		container:SetPoint("BOTTOMLEFT", self.frame, 0, -9)
		container:SetPoint("BOTTOMRIGHT", self.frame, 4, 0)
		
		self.frame.container = container
		
		-- Scroll frame
		local scroll = CreateFrame("ScrollFrame", "ExpirationFrameScroll", container, "UIPanelScrollFrameTemplate")
		scroll:SetPoint("TOPLEFT", 5, 0)
		scroll:SetPoint("BOTTOMRIGHT", -28, 10)
		
		self.frame.scroll = scroll
		
		local child = CreateFrame("Frame", nil, scroll)
		scroll:SetScrollChild(child)
		child:SetHeight(2)
		child:SetWidth(2)
		
		self.frame.child = child

		-- Create the actual edit box
		local editBox = CreateFrame("EditBox", nil, child)
		editBox:SetPoint("TOPLEFT")
		editBox:SetHeight(50)
		editBox:SetWidth(50)

		editBox:SetMultiLine(true)
		editBox:SetAutoFocus(false)
		editBox:EnableMouse(true)
		editBox:SetFontObject(GameFontHighlightSmall)
		editBox:SetTextInsets(0, 0, 0, 0)
		editBox:SetScript("OnEscapePressed", editBox.ClearFocus)
		scroll:SetScript("OnMouseUp", function() editBox:SetFocus() end)	

		self.frame.editBox = editBox		

		if( self.db.profile.position ) then
			local scale = self.frame:GetEffectiveScale()
			
			self.frame:ClearAllPoints()
			self.frame:SetPoint("TOPLEFT", nil, "BOTTOMLEFT", self.db.profile.position.x / scale, self.db.profile.position.y / scale)
		else
			self.frame:SetPoint("CENTER", UIParent, "CENTER")
		end
	end
	
	-- Set who the report is about
	self.frame.title:SetFormattedText(L["Report for %s (Last %d events)"], name, lines)
	self.frame:Show()
	
	-- Add all the data
	local reportText
	for line = #(report) - lines + 1, #(report) do
		if( report[line] ) then
			local text = string.format("%d. %s", #(report) - line + 1, report[line])
			if( reportText ) then
				reportText = reportText .. "\n" .. text
			else
				reportText = text
			end
		end
	end
	
	self.frame.editBox:SetText(reportText)
end

-- Send a report
function Expiration:Report(name, reportNum, dest, lines)
	-- Search for the player
	local playerInfo
	local guid = nameToGUID[string.lower(name or "")]
	if( guid ) then
		name = UnitName(name)
		playerInfo = groupInfo[guid]
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
			self:Echo(string.format("%d) %s - %s", id, date("%H:%M:%S", report.time), report.cause))
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
	
	-- Parse it if needed to get it into a usable format
	parseReport(report)

	-- Make sure it's a valid line count
	lines = lines or self.db.profile.lines
	lines = lines < 1 and 1 or lines > #(report) and #(report) or lines
	
	-- WHISPER:Distomos, CHANNEL:1, etc
	local type, target = strsplit(":", dest, 2)
	target = string.trim(target or "")
	
	if( type == "console" ) then
		self:Print(string.format(L["Report for %s (Last %d events)"], name, lines))
		for line = #(report) - lines + 1, #(report) do
			if( report[line] ) then
				self:Echo(string.format("%d. %s", #(report) - line + 1, report[line]))
			end
		end
		return
	elseif( type == "frame" ) then
		self:ReportFrame(name, lines, report)
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
		if( report[line] ) then
			SendChatMessage(string.format("%d. %s", #(report) - line + 1, report[line]), type, nil, target)
		end
	end
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
