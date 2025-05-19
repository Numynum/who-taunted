WhoTaunted = LibStub("AceAddon-3.0"):NewAddon("WhoTaunted", "AceEvent-3.0", "AceConsole-3.0", "AceTimer-3.0", "AceComm-3.0", "AceSerializer-3.0")
local AceConfig = LibStub("AceConfigDialog-3.0");
local L = LibStub("AceLocale-3.0"):GetLocale("WhoTaunted");

local PlayerName = UnitName("player");
local BgDisable = false;
local DisableInPvPZone = false;
local GroupDisable = false;
local WhoTauntedVersion = C_AddOns.GetAddOnMetadata("WhoTaunted", "Version");
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

local orgGetSpellLink = C_Spell and C_Spell.GetSpellLink or GetSpellLink;
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
	self:RegisterEvent("GROUP_ROSTER_UPDATE", "GroupRosterUpdateOnEvent");

	self:RegisterChatCommand("whotaunted", "ChatCommand");
	self:RegisterChatCommand("wtaunted", "ChatCommand");
	self:RegisterChatCommand("wtaunt", "ChatCommand");

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

function WhoTaunted:UpdateChatWindowsOnEvent()
	self:UpdateChatWindows();
end

function WhoTaunted:CombatLog()
	local _, subEvent, _, _, srcName, _, _, dstGUID, dstName, _, _, spellID, _, _, extraSpellID = CombatLogGetCurrentEventInfo();
	self:DisplayTaunt(subEvent, srcName, spellID, dstGUID, dstName, extraSpellID, GetServerTime());
end

function WhoTaunted:EnteringWorldOnEvent()
	local inInstance, instanceType = IsInInstance();
    BgDisable = inInstance and instanceType == "pvp" and self.db.profile.DisableInBG;
    self:GroupRosterUpdateOnEvent();
	self:ClearRecentTaunts();
end

function WhoTaunted:RegenEnabledOnEvent()
	self:ClearRecentTaunts();
end

function WhoTaunted:UpdateCLUERegistered()
    if self.db.profile.Disabled or BgDisable or DisableInPvPZone or GroupDisable then
        self:UnregisterEvent("COMBAT_LOG_EVENT_UNFILTERED");
    else
        self:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED", "CombatLog");
    end
end

function WhoTaunted:ZoneChangedOnEvent()
    DisableInPvPZone = self.db.profile.DisableInPvPZone and self:IsPvPZone(C_Map.GetBestMapForUnit("player"));
    self:UpdateCLUERegistered();
end

function WhoTaunted:GroupRosterUpdateOnEvent()
    GroupDisable = not (IsInGroup() or IsInRaid());
    self:UpdateCLUERegistered();
end

function WhoTaunted:ChatCommand()
    Settings.OpenToCategory("Who Taunted?");
end

function WhoTaunted:DisplayTaunt(Event, Name, ID, TargetGUID, Target, FailType, Time)
    if
        ID == Env.DeathGrip -- Ignore Death Grip Pull Effect for non-Blood Specs
        or not Event or not Name or not ID or not Time or not Target
        or (self.db.profile.HideOwnTaunts and Name == PlayerName)
        or not UnitIsPlayer(Name)
        or not (UnitInParty(Name) or UnitInRaid(Name))
        or self:IsRecentTaunt(Name, ID, Time)
    then return; end

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
		for _, v in pairs(self.TauntsList.SingleTarget) do
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
		for _, v in pairs(self.TauntsList.AOE) do
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
		for _, v in pairs(self.PvPZoneIDs) do
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
		RecentTaunts[TauntName][TauntTime] = TauntID;
	end
end

function WhoTaunted:IsRecentTaunt(TauntName, TauntID, TauntTime)
	if TauntName and TauntID and TauntTime and RecentTaunts[TauntName] and RecentTaunts[TauntName][TauntTime] then
        if RecentTaunts[TauntName][TauntTime] == TauntID then return true end

        local spellRecentTaunt = GetSpellInfo(RecentTaunts[TauntName][TauntTime]);
        local spell = GetSpellInfo(TauntID);
        if (spellRecentTaunt) and (spell) and (spellRecentTaunt == spell) then
            return true;
        end
	end

	return false;
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

function WhoTaunted:OutPut(msg, output)
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
		for _, v in pairs({ GetChatWindowChannels(i) }) do
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
		local name = GetChatWindowInfo(i);
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
		local name = GetChatWindowInfo(i);
		if (name) and (name:trim() ~= "") and (tostring(name) == tostring(ChatWindow)) then
			IsChatWindow = true;
			break;
		end
	end

	return IsChatWindow;
end

function WhoTaunted:PrintToChatWindow(message, ChatWindow)
	for i = 1, NUM_CHAT_WINDOWS, 1 do
		local name = GetChatWindowInfo(i);
		if (name) and (name:trim() ~= "") and (tostring(name) == tostring(ChatWindow)) then
			self:Print(_G["ChatFrame"..i], tostring(message));
		end
	end
end

function WhoTaunted:GetClassColor(Unit)
	local _, classFilename = UnitClass(Unit);
	local ClassColor = "00FFFFFF";

	if (Unit) and (classFilename) then
		ClassColor = select(4, GetClassColor(classFilename));
	end

	return ClassColor;
end

function WhoTaunted:GetSpellName(ID)
	local spellName = "";

	local name = GetSpellInfo(ID);
	if (name) then
		spellName = name;
	end

	return spellName;
end
