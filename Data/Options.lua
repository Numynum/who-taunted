local WhoTaunted = WhoTaunted;
local L = LibStub("AceLocale-3.0"):GetLocale("WhoTaunted");

WhoTaunted.OutputTypes = {
	Self = L["Self"],
	Party = L["Party"],
	Raid = L["Raid"],
	RaidWarning = L["Raid Warning"],
	Say = L["Say"],
	Yell = L["Yell"],
};

WhoTaunted.options = {
	name = "Who Taunted?",
	type = 'group',
	args = {
		Intro = {
			order = 10,
			type = "description",
			name = GetAddOnMetadata("WhoTaunted", "Notes"),
		},
		Disabled = {
			type = "toggle",
			name = L["Disable Who Taunted?"],
			desc = L["Disables Who Taunted?."],
			width = "full",
			get = function(info) return WhoTaunted.db.profile.Disabled; end,
			set = function(info, v) WhoTaunted.db.profile.Disabled = v; end,
			order = 20
		},
		General = {
			name = L["General"],
			type = "group",
			--guiInline = true,
			disabled = false,
			order = 30,
			args = {
				DisableInBG = {
					type = "toggle",
					name = L["Disable Who Taunted? in Battlegrounds"],
					desc = L["Disables Who Taunted? while you are in a battleground."],
					width = "full",
					get = function(info) return WhoTaunted.db.profile.DisableInBG; end,
					set = function(info, v)
						WhoTaunted.db.profile.DisableInBG = v;
						WhoTaunted:EnteringWorldOnEvent();
					end,
					order = 10
				},
				DisableInPvPZone = {
					type = "toggle",
					name = L["Disable Who Taunted? in PvP Zones"],
					desc = L["Disables Who Taunted? while you are in PvP Zones such as Ashran."],
					width = "full",
					get = function(info) return WhoTaunted.db.profile.DisableInPvPZone; end,
					set = function(info, v)
						WhoTaunted.db.profile.DisableInPvPZone = v;
						WhoTaunted:ZoneChangedOnEvent();
					end,
					order = 20
				},
				HideOwnTaunts = {
					type = "toggle",
					name = L["Hide Own Taunts"],
					desc = L["Don't show your own taunts."],
					width = "full",
					get = function(info) return WhoTaunted.db.profile.HideOwnTaunts; end,
					set = function(info, v) WhoTaunted.db.profile.HideOwnTaunts = v; end,
					order = 30
				},
				HideOwnFailedTaunts = {
					type = "toggle",
					name = L["Hide Own Failed Taunts"],
					desc = L["Don't show your own failed taunts."],
					width = "full",
					get = function(info) return WhoTaunted.db.profile.HideOwnFailedTaunts; end,
					set = function(info, v) WhoTaunted.db.profile.HideOwnFailedTaunts = v; end,
					order = 40
				},
				DisplayAbility = {
					type = "toggle",
					name = L["Display Ability"],
					desc = L["Display the ability that was used to taunt."],
					width = "full",
					get = function(info) return WhoTaunted.db.profile.DisplayAbility; end,
					set = function(info, v) WhoTaunted.db.profile.DisplayAbility = v; end,
					order = 50
				},
			},
		},
		Announcements = {
			name = L["Announcements"],
			type = "group",
			disabled = false,
			order = 40,
			args = {
				ChatWindow = {
					type = "select",
					values = WhoTaunted:GetChatWindows(),
					name = L["Chat Window"],
					desc = L["The chat window taunts will be announced in when the output is set to"].." "..WhoTaunted.OutputTypes.Self..".",
					width = "100",
					get = function(info) return WhoTaunted.db.profile.ChatWindow; end,
					set = function(info, v) WhoTaunted.db.profile.ChatWindow = v; end,
					order = 10
				},
				AnounceTaunts = {
					type = "toggle",
					name = L["Anounce Taunts"],
					desc = L["Anounce taunts."],
					width = "full",
					get = function(info) return WhoTaunted.db.profile.AnounceTaunts; end,
					set = function(info, v) WhoTaunted.db.profile.AnounceTaunts = v; end,
					order = 20
				},
				AnounceAOETaunts = {
					type = "toggle",
					name = L["Anounce AOE Taunts"],
					desc = L["Anounce AOE Taunts."],
					width = "full",
					get = function(info) return WhoTaunted.db.profile.AnounceAOETaunts; end,
					set = function(info, v) WhoTaunted.db.profile.AnounceAOETaunts = v; end,
					order = 30
				},
				AnounceFails = {
					type = "toggle",
					name = L["Anounce Fails"],
					desc = L["Anounce taunts that fail."],
					width = "full",
					get = function(info) return WhoTaunted.db.profile.AnounceFails; end,
					set = function(info, v) WhoTaunted.db.profile.AnounceFails = v; end,
					order = 40
				},
			},
		},
	}
}


