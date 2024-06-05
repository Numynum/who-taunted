WhoTaunted = LibStub("AceAddon-3.0"):NewAddon("WhoTaunted", "AceEvent-3.0", "AceConsole-3.0", "AceTimer-3.0", "AceComm-3.0", "AceSerializer-3.0")
local AceConfig = LibStub("AceConfigDialog-3.0");
local L = LibStub("AceLocale-3.0"):GetLocale("WhoTaunted");

local PlayerName, PlayerRealm = UnitName("player");
local UserID = tonumber(tostring(UnitGUID("player")):sub(12), 16);
local BgDisable = false;
local DisableInPvPZone = false;
local GroupDisable = false;
local version, build, date, tocVersion = GetBuildInfo();
local WhoTauntedVersion = GetAddOnMetadata("WhoTaunted", "Version");
local NewVersionAvailable = false;
local RecentTaunts = {};
local TauntTypes = {
	Normal = "Normal",
	AOE    = "AOE",
	Failed = "Failed",
};
local Env = {
	DeathGrip = 49576,
	Provoke = 115546,
	BlackOxStatue = 61146,
	RighteousDefense = 31789,
	Left = {
		Base = "|c",
		One  = "lc1",
		Two  = "lc2",
	},
	Right = {
		Base = "|r",
		One  = "lr1",
		Two  = "lr2",
	},
	Prefix = {
		Version = "WhoTaunted_Versi",
	},
};

local orgGetSpellLink = GetSpellLink;
local linkCache = {};
local function GetSpellLink(ID)
    if not linkCache[ID] then
        linkCache[ID] = orgGetSpellLink(ID);
    end
    
    return linkCache[ID];
end
local tauntListMap = {SingleTarget = {}, AOE = {}};

function WhoTaunted:OnInitialize()
    for _, spellID in pairs(self.TauntsList.SingleTarget) do
        tauntListMap.SingleTarget[spellID] = true;
    end
    for _, spellID in pairs(self.TauntsList.AOE) do
        tauntListMap.AOE[spellID] = true;
    end

	self:RegisterEvent("PLAYER_ENTERING_WORLD", "EnteringWorldOnEvent");
	self:RegisterEvent("PLAYER_REGEN_ENABLED", "RegenEnabledOnEvent");
	self:RegisterEvent("ZONE_CHANGED_NEW_AREA", "ZoneChangedOnEvent");
	self:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED", "CombatLog");
	self:RegisterEvent("UPDATE_CHAT_WINDOWS", "UpdateChatWindowsOnEvent");
	self:RegisterEvent("GUILD_ROSTER_UPDATE", "GuildRosterUpdateOnEvent");
	self:RegisterEvent("GROUP_ROSTER_UPDATE", "GroupRosterUpdateOnEvent");

	self:RegisterChatCommand("whotaunted", "ChatCommand");
	self:RegisterChatCommand("wtaunted", "ChatCommand");
	self:RegisterChatCommand("wtaunt", "ChatCommand");

	self:RegisterComm(Env.Prefix.Version);

	self.db = LibStub("AceDB-3.0"):New("WhoTauntedDB", self.defaults, "Default");
	LibStub("AceConfig-3.0"):RegisterOptionsTable("WhoTaunted", self.options);
	self.options.args.Profiles = LibStub("AceDBOptions-3.0"):GetOptionsTable(self.db);
	AceConfig:AddToBlizOptions("WhoTaunted", "Who Taunted?");

	--Convert the old Options "profile" to the new "Default"
	if (self.db:GetCurrentProfile() == "profile") and (self.db.profile.ConvertedProfiles == false) then
		self.db:SetProfile("Default");
		self.db:CopyProfile("profile", true);
		self.db:DeleteProfile("profile", true);
		self.db.profile.ConvertedProfiles = true;
	end

	self:Print("|cffffff78"..WhoTauntedVersion.."|r has loaded!");
    if NumyProfiler then
        NumyProfiler:WrapModules("WhoTaunted", 'Main', self);
    end
end

function WhoTaunted:OnEnable()
	if (type(tonumber(self.db.profile.AnounceTauntsOutput)) == "number") or (type(tonumber(self.db.profile.AnounceAOETauntsOutput)) == "number") or (type(tonumber(self.db.profile.AnounceFailsOutput)) == "number") then
		self.db.profile.AnounceTauntsOutput = self.OutputTypes.Self;
		self.db.profile.AnounceAOETauntsOutput = self.OutputTypes.Self;
		self.db.profile.AnounceFailsOutput = self.OutputTypes.Self;
	end

	self:CheckOptions();
end

function WhoTaunted:OnDisable()
	self:UnregisterAllEvents();
	self:ClearRecentTaunts();
end

function WhoTaunted:UpdateChatWindowsOnEvent(event, ...)
	self:UpdateChatWindows();
end

function WhoTaunted:CombatLog()
	local timestamp, subEvent, hideCaster, srcGUID, srcName, srcFlags, srcFlags2, dstGUID, dstName, dstFlags, dstFlags2, spellID, spellName, spellSchool, extraSpellID, extraSpellName, extraSpellSchool, auraType = CombatLogGetCurrentEventInfo();
	self:DisplayTaunt(subEvent, srcName, spellID, dstGUID, dstName, extraSpellID, GetServerTime());
end

function WhoTaunted:EnteringWorldOnEvent(event, ...)
	local inInstance, instanceType = IsInInstance();
    BgDisable = inInstance and instanceType == "pvp" and self.db.profile.DisableInBG;
    self:GroupRosterUpdateOnEvent();
	self:ClearRecentTaunts();
end

function WhoTaunted:RegenEnabledOnEvent(event, ...)
	self:ClearRecentTaunts();
end

function WhoTaunted:UpdateCLUERegistered()
    if 
        self.db.profile.Disabled or BgDisable or DisableInPvPZone or GroupDisable
    then
        self:UnregisterEvent("COMBAT_LOG_EVENT_UNFILTERED");
    else
        self:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED", "CombatLog");
    end
end

function WhoTaunted:ZoneChangedOnEvent(event, ...)
    DisableInPvPZone = self.db.profile.DisableInPvPZone and self:IsPvPZone(C_Map.GetBestMapForUnit("player"));
    self:UpdateCLUERegistered();
end

function WhoTaunted:GuildRosterUpdateOnEvent(event, ...)
	self:SendCommData(GUILD);
end

function WhoTaunted:GroupRosterUpdateOnEvent(event, ...)
    GroupDisable = not (IsInGroup(LE_PARTY_CATEGORY_HOME) or IsInRaid(LE_PARTY_CATEGORY_HOME) or IsInGroup(LE_PARTY_CATEGORY_INSTANCE) or IsInRaid(LE_PARTY_CATEGORY_INSTANCE));
    self:UpdateCLUERegistered();
	self:SendCommData(GROUP);
end

function WhoTaunted:ChatCommand(input)
	if (not input) or (input:trim() == "") then
		InterfaceOptionsFrame_OpenToCategory("Who Taunted?");
	end
end

function WhoTaunted:DisplayTaunt(Event, Name, ID, TargetGUID, Target, FailType, Time)
    if 
        ID == Env.DeathGrip -- Ignore Death Grip Pull Effect for non-Blood Specs
        or not Event or not Name or not ID or not Time or not Target 
        or (self.db.profile.HideOwnTaunts and Name == PlayerName)
        or self:IsRecentTaunt(Name, ID, Time) 
        or not UnitIsPlayer(Name) or not (UnitInParty(Name) or UnitInRaid(Name))
    then 
        return; 
    end
    
    local OutputMessage = nil;
    local IsTaunt, TauntType;
    local OutputType;


    if (Event == "SPELL_AURA_APPLIED") then
        IsTaunt, TauntType = self:IsTaunt(ID);
        if 
            not IsTaunt
            or (TauntType == TauntTypes.Normal and not self.db.profile.AnounceTaunts)
            or (TauntType == TauntTypes.AOE and not self.db.profile.AnounceAOETaunts)
        then
            return;
        end
        OutputType = self:GetOutputType(TauntType);
        local Spell = GetSpellLink(ID);
        if (not Spell) then
            Spell = self:GetSpellName(ID);
        end

        if (TauntType == TauntTypes.Normal) then
            OutputMessage = self:OutputMessageNormal(Name, Target, Spell, OutputType);
        elseif (TauntType == TauntTypes.AOE) then
            OutputMessage = self:OutputMessageAOE(Name, Target, Spell, ID, OutputType);
        end
    elseif (Event == "SPELL_CAST_SUCCESS") then
        IsTaunt, TauntType = self:IsTaunt(ID);
        if (not IsTaunt) or ((TauntType == TauntTypes.Normal) and (ID ~= Env.Provoke)) or ((TauntType == TauntTypes.AOE) and (self.db.profile.AnounceAOETaunts == false)) then
            return;
        end
        OutputType = self:GetOutputType(TauntType);
        local Spell = GetSpellLink(ID);
        if (not Spell) then
            Spell = self:GetSpellName(ID);
        end

        --Monk AOE Taunt for casting Provoke (115546) on Black Ox Statue (61146)
        if (ID == Env.Provoke) and (TargetGUID) and (string.match(TargetGUID, tostring(Env.BlackOxStatue))) then
            IsTaunt, TauntType = true, TauntTypes.AOE;
            OutputMessage = self:OutputMessageAOE(Name, Target, Spell, ID, OutputType);
        else
            if (TauntType == TauntTypes.Normal) then
                OutputMessage = self:OutputMessageNormal(Name, Target, Spell, OutputType);
            elseif (TauntType == TauntTypes.AOE) then
                OutputMessage = self:OutputMessageAOE(Name, Target, Spell, ID, OutputType);
            end
        end
    elseif (Event == "SPELL_MISSED") then
        IsTaunt, TauntType = self:IsTaunt(ID);
        if (not Target) or (not FailType) or (not IsTaunt) or ((TauntType == TauntTypes.Normal) and (self.db.profile.AnounceTaunts == false)) or ((TauntType == TauntTypes.AOE) and (self.db.profile.AnounceAOETaunts == false)) then
            return;
        end
        TauntType = TauntTypes.Failed;
        OutputType = self:GetOutputType(TauntType);
        local Spell = GetSpellLink(ID);
        if (not Spell) then
            Spell = self:GetSpellName(ID);
        end
        OutputMessage = self:OutputMessageFailed(Name, Target, Spell, ID, OutputType, FailType);
    else
        return;
    end
    if (OutputMessage) and (TauntType) then
        if (OutputType ~= self.OutputTypes.Self) then
            if (self.db.profile.Prefix == true) then
                OutputMessage = L["<WhoTaunted>"].." "..OutputMessage;
            end
        end
        self:AddRecentTaunt(Name, ID, Time);
        self:OutPut(OutputMessage:trim(), OutputType);
    end
end

local isTauntCache = {}
function WhoTaunted:IsTaunt(SpellID)
    if nil ~= isTauntCache[SpellID] then
        return (not not isTauntCache[SpellID]), (isTauntCache[SpellID] or "");
    end
	local IsTaunt, TauntType = false, "";
    
    if tauntListMap.SingleTarget[SpellID] then
        IsTaunt, TauntType = true, TauntTypes.Normal;
    elseif tauntListMap.AOE[SpellID] then
        IsTaunt, TauntType = true, TauntTypes.AOE;
    end
	if (not IsTaunt) then
		for k, v in pairs(self.TauntsList.SingleTarget) do
			local spellTauntList = GetSpellInfo(v);
			local spell = GetSpellInfo(SpellID);
			if (spellTauntList) and (spell) and (spellTauntList == spell) then
				IsTaunt, TauntType = true, TauntTypes.Normal;
                self:Print("found spell name match, update ST TauntList", SpellID, v)
				break;
			end
		end
	end
	if (not IsTaunt) then
		for k, v in pairs(self.TauntsList.AOE) do
			local spellTauntList = GetSpellInfo(v);
			local spell = GetSpellInfo(SpellID);
			if (spellTauntList) and (spell) and (spellTauntList == spell) then
				IsTaunt, TauntType = true, TauntTypes.AOE;
                self:Print("found spell name match, update AOE TauntList", SpellID, v)
				break;
			end
		end
	end

    isTauntCache[SpellID] = IsTaunt and TauntType or false;
	return IsTaunt, TauntType;
end

function WhoTaunted:IsPvPZone(MapID)
	local IsPvPZone = false;

	if (MapID) and (type(MapID) == "number") then
		for k, v in pairs(self.PvPZoneIDs) do
			if (MapID == v) then
				IsPvPZone = true;
				break;
			end
		end
	end

	return IsPvPZone;
end

function WhoTaunted:AddRecentTaunt(TauntName, TauntID, TauntTime)
	if (TauntName) and (TauntID) and (TauntTime) and (type(TauntTime) == "number") then
        RecentTaunts[TauntName] = RecentTaunts[TauntName] or {};
		table.insert(RecentTaunts[TauntName], {
			ID = TauntID,
			TimeStamp = TauntTime,
		});
	end
end

function WhoTaunted:IsRecentTaunt(TauntName, TauntID, TauntTime)
	local IsRecentTaunt = false;

	if (TauntName) and (TauntID) and (TauntTime) and (type(TauntTime) == "number") and (RecentTaunts[TauntName]) then
		for k, v in pairs(RecentTaunts[TauntName]) do
            if (v.TimeStamp == TauntTime) then
                local spellRecentTaunt = GetSpellInfo(v.ID);
                local spell = GetSpellInfo(TauntID);
                if (spellRecentTaunt) and (spell) and (spellRecentTaunt == spell) then
                    IsRecentTaunt = true;
                    break;
                end
			end
		end
	end

	return IsRecentTaunt;
end

function WhoTaunted:ClearRecentTaunts()
	RecentTaunts = {};
end

function WhoTaunted:OutputMessageNormal(Name, Target, Spell, OutputType)
	local OutputMessage = nil;

	OutputMessage = Env.Left.One..Name..Env.Right.One.." "..L["taunted"].." "..Target;
	if (Spell) and (self.db.profile.DisplayAbility == true) then
		OutputMessage = OutputMessage.." "..L["using"].." "..Spell..".";
	else
		OutputMessage = OutputMessage..".";
	end

	if (OutputType == self.OutputTypes.Self) then
		OutputMessage = OutputMessage:gsub(Env.Left.One, Env.Left.Base .. self:GetClassColor(Name)):gsub(Env.Right.One, Env.Right.Base);
	else
		OutputMessage = OutputMessage:gsub(Env.Left.One, ""):gsub(Env.Right.One, "");
	end

	return OutputMessage;
end

function WhoTaunted:OutputMessageAOE(Name, Target, Spell, ID, OutputType)
	local OutputMessage = nil;

	OutputMessage = Env.Left.One..Name..Env.Right.One.." "..L["AOE"].." "..L["taunted"];
	if (Spell) and (self.db.profile.DisplayAbility == true) then
		if (ID == Env.Provoke) then
			--Monk AOE Taunt for casting Provoke (115546) on Black Ox Statue (61146)
			OutputMessage = OutputMessage.." "..L["using"].." "..Spell.." "..L["on Black Ox Statue"]..".";
		else
			--Show the Righteous Defense Target if the option is toggled (and supported in the WoW Client)
			if (Target) and (ID == Env.RighteousDefense) and (self.db.profile.RighteousDefenseTarget == true) then
				OutputMessage = OutputMessage.." "..L["off of"].." "..Env.Left.Two..Target..Env.Right.Two;
			end
			OutputMessage = OutputMessage.." "..L["using"].." "..Spell..".";
		end
	else
		OutputMessage = OutputMessage..".";
	end

	if (OutputType == self.OutputTypes.Self) then
		OutputMessage = OutputMessage:gsub(Env.Left.One, Env.Left.Base .. self:GetClassColor(Name)):gsub(Env.Right.One, Env.Right.Base):gsub(Env.Left.Two, Env.Left.Base .. self:GetClassColor(Target)):gsub(Env.Right.Two, Env.Right.Base);
	else
		OutputMessage = OutputMessage:gsub(Env.Left.One, ""):gsub(Env.Right.One, ""):gsub(Env.Left.Two, ""):gsub(Env.Right.Two, "");
	end

	return OutputMessage;
end

function WhoTaunted:OutputMessageFailed(Name, Target, Spell, ID, OutputType, FailType)
	local OutputMessage = nil;

	OutputMessage = Env.Left.One..Name..L["'s"]..Env.Right.One.." "..L["taunt"];
	if (Spell) and (self.db.profile.DisplayAbility == true) then
		OutputMessage = OutputMessage.." "..Spell;
	end
	OutputMessage = OutputMessage.." "..L["against"].." "..Target.." "..Env.Left.Two..string.upper(L["Failed:"].." "..FailType)..Env.Right.Two.."!";

	if (OutputType == self.OutputTypes.Self) then
		OutputMessage = OutputMessage:gsub(Env.Left.One, Env.Left.Base..self:GetClassColor(Name)):gsub(Env.Right.One, Env.Right.Base):gsub(Env.Left.Two, "|c00FF0000"):gsub(Env.Right.Two, Env.Right.Base);
	else
		OutputMessage = OutputMessage:gsub(Env.Left.One, ""):gsub(Env.Right.One, ""):gsub(Env.Left.Two, ""):gsub(Env.Right.Two, "");
	end

	return OutputMessage;
end

function WhoTaunted:OutPut(msg, output, dest)
	if (not output) or (output == "") then
		output = self.OutputTypes.Self;
	end
	if (msg) then
		if (self:FormatString(output) == self:FormatString(self.OutputTypes.Raid)) then
			if (IsInRaid(LE_PARTY_CATEGORY_HOME)) and (GetNumGroupMembers() >= 1) then
				ChatThrottleLib:SendChatMessage("NORMAL", "WhoTaunted", tostring(msg), "RAID");
			end
		elseif (self:FormatString(output) == self:FormatString(self.OutputTypes.RaidWarning)) or (self:FormatString(output) == self:FormatString(self.OutputTypes.RaidWarning):gsub(" ", "")) then
			if (IsInRaid(LE_PARTY_CATEGORY_HOME)) and (GetNumGroupMembers() >= 1) then
				local isLeader = UnitIsGroupLeader("player");
				local isAssistant = UnitIsGroupAssistant("player");
				if ((isLeader) and (isLeader == true)) or ((isAssistant) and (isAssistant == true)) then
					ChatThrottleLib:SendChatMessage("NORMAL", "WhoTaunted", tostring(msg), "RAID_WARNING");
				else
					ChatThrottleLib:SendChatMessage("NORMAL", "WhoTaunted", tostring(msg), "RAID");
				end
			elseif (self.db.profile.DefaultToSelf == true) then
				self:Print(tostring(msg));
			end
		elseif (self:FormatString(output) == self:FormatString(self.OutputTypes.Party)) then
			if (IsInGroup(LE_PARTY_CATEGORY_HOME)) and (GetNumSubgroupMembers() >= 1) then
				ChatThrottleLib:SendChatMessage("NORMAL", "WhoTaunted", tostring(msg), "PARTY");
			elseif (self.db.profile.DefaultToSelf == true) then
				self:Print(tostring(msg));
			end
		elseif (self:FormatString(output) == self:FormatString(self.OutputTypes.Officer)) then
			if (IsInGuild()) then
				ChatThrottleLib:SendChatMessage("NORMAL", "WhoTaunted", tostring(msg), "OFFICER");
			elseif (self.db.profile.DefaultToSelf == true) then
				self:Print(tostring(msg));
			end
		elseif (self:FormatString(output) == self:FormatString(self.OutputTypes.Self)) then
			if (self:IsChatWindow(self.db.profile.ChatWindow) == true) then
				self:PrintToChatWindow(tostring(msg), self.db.profile.ChatWindow);
			else
				self:Print(tostring(msg));
			end
		else
			self:Print(tostring(msg));
		end
	end
end

function WhoTaunted:GetOutputType(TauntType)
	local OutputType = self.OutputTypes.Self;

	if (TauntType == TauntTypes.Normal) then
		OutputType = self.OutputTypes[self.db.profile.AnounceTauntsOutput];
	elseif (TauntType == TauntTypes.AOE) then
		OutputType = self.OutputTypes[self.db.profile.AnounceAOETauntsOutput];
	elseif (TauntType == TauntTypes.Failed) then
		OutputType = self.OutputTypes[self.db.profile.AnounceFailsOutput];
	end

	return OutputType;
end

function WhoTaunted:FormatString(s)
	return string.lower(tostring(s)):trim();
end

function WhoTaunted:IsChatChannel(ChannelName)
	local IsChatChannel = false;

	for i = 1, NUM_CHAT_WINDOWS, 1 do
		for k, v in pairs({ GetChatWindowChannels(i) }) do
			if (self:FormatString(v) == self:FormatString(ChannelName)) then
				IsChatChannel = true;
				break;
			end
		end
		if (IsChatChannel == true) then
			break;
		end
	end

	return IsChatChannel;
end

function WhoTaunted:UpdateChatWindows()
	self.options.args.Announcements.args.ChatWindow.values = self:GetChatWindows();
end

function WhoTaunted:GetChatWindows()
	local ChatWindows = {};

	for i = 1, NUM_CHAT_WINDOWS, 1 do
		local name, fontSize, r, g, b, alpha, shown, locked, docked, uninteractable = GetChatWindowInfo(i);
		if (name) and (tostring(name) ~= COMBAT_LOG) and (tostring(name) ~= VOICE) and (name:trim() ~= "") then
			ChatWindows[tostring(name)] = tostring(name);

			if (self.db) and (i == 1) and ((self.db.profile.ChatWindow == "") or (self:IsChatWindow(self.db.profile.ChatWindow) == false)) then
				self.db.profile.ChatWindow = tostring(name);
			end
		end
	end

	return ChatWindows;
end

function WhoTaunted:IsChatWindow(ChatWindow)
	local IsChatWindow = false;

	for i = 1, NUM_CHAT_WINDOWS, 1 do
		local name, fontSize, r, g, b, alpha, shown, locked, docked, uninteractable = GetChatWindowInfo(i);
		if (name) and (name:trim() ~= "") and (tostring(name) == tostring(ChatWindow)) then
			IsChatWindow = true;
			break;
		end
	end

	return IsChatWindow;
end

function WhoTaunted:PrintToChatWindow(message, ChatWindow)
	for i = 1, NUM_CHAT_WINDOWS, 1 do
		local name, fontSize, r, g, b, alpha, shown, locked, docked, uninteractable = GetChatWindowInfo(i);
		if (name) and (name:trim() ~= "") and (tostring(name) == tostring(ChatWindow)) then
			self:Print(_G["ChatFrame"..i], tostring(message));
		end
	end
end

function WhoTaunted:GetClassColor(Unit)
	local _, classFilename, _ = UnitClass(Unit);
	local ClassColor = "00FFFFFF";

	if (Unit) and (classFilename) then
		_, _, _, ClassColor = GetClassColor(classFilename);
	end

	return ClassColor;
end

function WhoTaunted:GetSpellName(ID)
	local spellName = "";

	local name, _, _, _, _, _, _ = GetSpellInfo(ID);
	if (name) then
		spellName = name;
	end

	return spellName;
end

function WhoTaunted:SendCommData(commType)
	local inCombat = InCombatLockdown();

	if (inCombat == false) then
		local CommChannel = "";

		if (commType == GROUP) then
			if (IsInGroup(LE_PARTY_CATEGORY_INSTANCE)) or (IsInRaid(LE_PARTY_CATEGORY_INSTANCE)) then
				CommChannel = "INSTANCE_CHAT";
			elseif (IsInRaid(LE_PARTY_CATEGORY_HOME)) then
				CommChannel = "RAID";
			elseif IsInGroup(LE_PARTY_CATEGORY_HOME) then
				CommChannel = "PARTY";
			end
		elseif (commType == GUILD) and (IsInGuild()) then
			CommChannel = "GUILD";
		end

		if (CommChannel ~= "") then
			local CommData = {ID = UserID, WhoTauntedVersion = WhoTauntedVersion };
			self:SendCommMessage(Env.Prefix.Version, self:Serialize(CommData), CommChannel);
		end
	end
end

function WhoTaunted:OnCommReceived(prefix, message, distribution, sender)
	if (prefix == Env.Prefix.Version) and (NewVersionAvailable == false) then
		local success, VersionData = self:Deserialize(message);
		if (success) and (VersionData) and (VersionData.WhoTauntedVersion) and (VersionData.ID ~= UserID) then
			if (self:CompareVersions(WhoTauntedVersion, VersionData.WhoTauntedVersion) == true) then
				NewVersionAvailable = true;
				self:ScheduleTimer(function(self, event, ...)
					self:Print(L["A new Who Taunted? version is available!"]..": ".."|c00FF0000"..VersionData.WhoTauntedVersion.."|r - |cffffff78https://www.curseforge.com/wow/addons/who-taunted|r");
				end, 10);
			end
		end
	end
end

function WhoTaunted:CompareVersions(Version1, Version2)
	Version1 = Version1:gsub("-alpha", ""):gsub("-beta", ""):gsub("v", ""):trim();
	Version2 = Version2:gsub("-alpha", ""):gsub("-beta", ""):gsub("v", ""):trim();

	local a, b, c = strsplit(".", Version1);
	if (a) then
		Version1 = a;
		if (b) then
			if (tonumber(b) < 10) then
				Version1 = Version1.."0"..b;
			else
				Version1 = Version1..b;
			end
		else
			Version1 = Version1.."00";
		end
		if (c) then
			if (tonumber(c) < 10) then
				Version1 = Version1.."0"..c;
			else
				Version1 = Version1..c;
			end
		else
			Version1 = Version1.."00";
		end
	end

	local x, y, z = strsplit(".", Version2);
	if (x) then
		Version2 = x;
		if (y) then
			if (tonumber(y) < 10) then
				Version2 = Version2.."0"..y;
			else
				Version2 = Version2..y;
			end
		else
			Version2 = Version2.."00";
		end
		if (z) then
			if (tonumber(z) < 10) then
				Version2 = Version2.."0"..z;
			else
				Version2 = Version2..z;
			end
		else
			Version2 = Version2.."00";
		end
	end

	local VersionIsGreater = false;

	if ((tonumber(Version1)) and (tonumber(Version2))) and (tonumber(Version2) > tonumber(Version1)) then
		VersionIsGreater = true;
	end

	return VersionIsGreater;
end
