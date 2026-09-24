--------------------------------------------------------------------------------
--------------------------------------------------------------------------------

function widget:GetInfo()
	return {
		name      = "AI Difficulty",
		desc      = "Shows and changes an AI's difficulty profile from the battle room (right-click the AI).",
		author    = "akudilcz fork",
		date      = "2026.09",
		license   = "GNU LGPL, v2.1 or later",
		layer     = 0,
		enabled   = true  --  loaded by default?
	}
end

--------------------------------------------------------------------------------
-- An AI's difficulty is its "profile" option (AIOptions.lua, type list). This widget finds
-- that list for an AI library, names the current choice and offers a picker that updates
-- a bot already in the battle: lobby:UpdateAi(aiName, {aiOptions = ...}).
--------------------------------------------------------------------------------

local profileCache = {} -- "lib version" -> items list (or false when the AI has no profile option)

local function AiVersion(lobby, aiLib, aiVersion)
	if aiVersion and aiVersion ~= "" and aiVersion ~= "<not-versioned>" then
		return aiVersion
	end
	-- the bot was added without a version: use the newest installed one for the battle's game
	local battle = lobby and lobby.GetMyBattleID and lobby:GetBattle(lobby:GetMyBattleID())
	local ais = VFS.GetAvailableAIs(battle and battle.gameName)
	local best
	for _, ai in ipairs(ais or {}) do
		if ai.shortName == aiLib and ai.version ~= "<not-versioned>" then
			best = ai.version
		end
	end
	return best
end

-- the profile choices of an AI library: { {key, name, desc}, ... } or nil
local function GetProfiles(lobby, aiLib, aiVersion)
	if not aiLib then
		return nil
	end
	local version = AiVersion(lobby, aiLib, aiVersion)
	if not version then
		return nil
	end
	local cacheKey = aiLib .. " " .. version
	local cached = profileCache[cacheKey]
	if cached ~= nil then
		return cached or nil
	end

	local path = "AI/Skirmish/" .. aiLib .. "/" .. version .. "/AIOptions.lua"
	local items = false
	if VFS.FileExists(path) then
		local ok, options = pcall(VFS.Include, path)
		if ok and type(options) == "table" then
			for _, option in ipairs(options) do
				if option.key == "profile" and option.type == "list" and type(option.items) == "table" then
					items = {}
					for i, item in ipairs(option.items) do
						items[i] = {key = item.key, name = item.name or item.key, desc = item.desc}
					end
					local customize = WG.Chobby.Configuration.gameConfig.CustomAiProfiles
					if customize then
						customize(aiLib, items) -- in place: drops hidden profiles, adds the game's own
					end
					break
				end
			end
		end
	end
	profileCache[cacheKey] = items
	return items or nil
end

-- short label for a profile key, e.g. "hard_aggressive" -> "Hard aggressive"
local function ProfileLabel(key)
	if not key or key == "" then
		return nil
	end
	local label = tostring(key):gsub("_", " ")
	return label:sub(1, 1):upper() .. label:sub(2)
end

-- the label of the profile a bot in the battle currently has, or nil
local function GetCurrentLabel(lobby, aiName)
	local bs = lobby and lobby:GetUserBattleStatus(aiName)
	if not (bs and bs.aiLib and bs.aiOptions and bs.aiOptions.profile) then
		return nil
	end
	if not GetProfiles(lobby, bs.aiLib, bs.aiVersion) then
		return nil
	end
	return ProfileLabel(bs.aiOptions.profile)
end

local function SetProfile(lobby, aiName, key)
	local bs = lobby:GetUserBattleStatus(aiName)
	if not (bs and bs.aiLib) then
		return
	end
	local options = {}
	for k, v in pairs(bs.aiOptions or {}) do
		options[k] = v
	end
	options.profile = key
	lobby:UpdateAi(aiName, {aiOptions = options})
	if lobby.name ~= "singleplayer" then
		-- hosted battles: the same command ai_list_window uses when adding a bot with options
		lobby:SayBattle("!aiProfile " .. aiName .. " " .. Json.encode(options))
	end
	if bs.aiLib == "BARb" then
		WG.Chobby.Configuration:SetConfigValue("lastBarbAiProfile", key)
	end
end

local function OpenPicker(aiName, lobby)
	local bs = lobby and lobby:GetUserBattleStatus(aiName)
	local profiles = bs and GetProfiles(lobby, bs.aiLib, bs.aiVersion)
	if not profiles then
		if WG.Chobby and WG.Chobby.InformationPopup then
			WG.Chobby.InformationPopup("This AI has no difficulty setting.")
		end
		return
	end
	local current = bs.aiOptions and bs.aiOptions.profile

	local rowHeight = 46
	local height = 90 + rowHeight * #profiles + 50
	local pickerWindow = Window:New {
		caption = "",
		name = "AiDifficultyWindow",
		parent = screen0,
		width = 420,
		height = height,
		resizable = false,
		draggable = false,
		classname = "main_window",
	}

	local function CloseFunction()
		if pickerWindow then
			pickerWindow:Dispose()
			pickerWindow = nil
		end
	end

	TextBox:New {
		x = 15,
		y = 15,
		right = 15,
		height = 60,
		text = "Difficulty for " .. aiName,
		objectOverrideFont = WG.Chobby.Configuration:GetFont(3),
		parent = pickerWindow,
	}

	for i, profile in ipairs(profiles) do
		local isCurrent = (profile.key == current)
		Button:New {
			x = 15,
			right = 15,
			y = 70 + (i - 1) * rowHeight,
			height = rowHeight - 6,
			caption = profile.name .. (isCurrent and "   (current)" or ""),
			tooltip = profile.desc,
			classname = isCurrent and "action_button" or "option_button",
			objectOverrideFont = WG.Chobby.Configuration:GetFont(2),
			parent = pickerWindow,
			OnClick = {
				function()
					SetProfile(lobby, aiName, profile.key)
					CloseFunction()
				end
			},
		}
	end

	Button:New {
		right = 15,
		width = 120,
		bottom = 8,
		height = 40,
		caption = i18n("cancel"),
		objectOverrideFont = WG.Chobby.Configuration:GetFont(2),
		classname = "negative_button",
		OnClick = { CloseFunction },
		parent = pickerWindow,
	}

	WG.Chobby.PriorityPopup(pickerWindow, CloseFunction, CloseFunction, screen0)
end

function widget:Initialize()
	VFS.Include(LUA_DIRNAME .. "widgets/chobby/headers/exports.lua", nil, VFS.RAW_FIRST)

	WG.AiDifficulty = {
		GetProfiles = GetProfiles,
		GetCurrentLabel = GetCurrentLabel,
		SetProfile = SetProfile,
		Open = OpenPicker,
	}
end
