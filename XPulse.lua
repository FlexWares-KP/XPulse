-- AI assistance disclaimer: This addon was developed with assistance from AI tools.
-- AI-generated suggestions were reviewed and adapted by the author; verify behavior
-- and report issues through the project repository.

local ADDON_NAME = "XPulse"
local SAVED_VARIABLES = "XPulseSavedVariables"
local MIN_SCALE = 0.5
local MAX_SCALE = 2
local DEFAULT_SCALE = 1

local DEFAULTS =
{
    x = 0,
    y = 0,
    scale = DEFAULT_SCALE,
    positionCaptured = false,
}

local saved
local progressBar
local mover
local moveMode = false
local hooksInstalled = false
local applyScheduled = false

local function Print(message)
    CHAT_ROUTER:AddSystemMessage("|c66ccffXPulse:|r " .. message)
end

local function ClampScale(scale)
    return math.max(MIN_SCALE, math.min(MAX_SCALE, scale))
end

local function GetProgressBar()
    if PLAYER_PROGRESS_BAR and PLAYER_PROGRESS_BAR.control then
        return PLAYER_PROGRESS_BAR.control
    end

    return ZO_PlayerProgress
end

local function CaptureInitialPosition()
    if saved.positionCaptured then
        if type(saved.defaultX) ~= "number" or type(saved.defaultY) ~= "number" then
            saved.defaultX = saved.x
            saved.defaultY = saved.y
        end
        return type(saved.x) == "number" and type(saved.y) == "number"
    end

    local x, y = progressBar:GetLeft(), progressBar:GetTop()
    if type(x) ~= "number" or type(y) ~= "number" then
        return false
    end

    saved.x = x
    saved.y = y
    saved.defaultX = x
    saved.defaultY = y
    saved.positionCaptured = true
    return true
end

local function ApplyBarPosition()
    progressBar = progressBar or GetProgressBar()
    if not progressBar or not CaptureInitialPosition() then
        return false
    end

    saved.scale = ClampScale(tonumber(saved.scale) or DEFAULT_SCALE)
    progressBar:SetScale(saved.scale)
    progressBar:ClearAnchors()
    progressBar:SetAnchor(TOPLEFT, GuiRoot, TOPLEFT, saved.x, saved.y)
    return true
end

local function UpdateMover()
    if not mover or not progressBar then
        return false
    end

    local width, height = progressBar:GetWidth(), progressBar:GetHeight()
    if type(width) ~= "number" or type(height) ~= "number" or width <= 0 or height <= 0 then
        return false
    end

    mover:SetDimensions(width * saved.scale, height * saved.scale)
    mover:ClearAnchors()
    mover:SetAnchor(TOPLEFT, GuiRoot, TOPLEFT, saved.x, saved.y)
    return true
end

local function ApplySettings()
    if not ApplyBarPosition() then
        return false
    end

    if moveMode then
        UpdateMover()
    end
    return true
end

local function SaveMoverPosition()
    local x, y = mover:GetLeft(), mover:GetTop()
    if type(x) == "number" and type(y) == "number" then
        saved.x = math.floor(x + 0.5)
        saved.y = math.floor(y + 0.5)
        ApplyBarPosition()
    end
end

local function CreateMover()
    mover = WINDOW_MANAGER:CreateTopLevelWindow(ADDON_NAME .. "Mover")
    mover:SetMouseEnabled(true)
    mover:SetMovable(true)
    mover:SetClampedToScreen(true)
    mover:SetHidden(true)

    local backdrop = WINDOW_MANAGER:CreateControl(ADDON_NAME .. "MoverBackdrop", mover, CT_BACKDROP)
    backdrop:SetAnchorFill()
    backdrop:SetCenterTexture("", 8, 8)
    backdrop:SetCenterColor(0.1, 0.6, 1, 0.2)
    backdrop:SetEdgeTexture("", 1, 1, 1, 1)
    backdrop:SetEdgeColor(0.2, 0.8, 1, 0.95)

    local label = WINDOW_MANAGER:CreateControl(ADDON_NAME .. "MoverLabel", mover, CT_LABEL)
    label:SetAnchor(TOP, mover, TOP, 0, 2)
    label:SetFont("ZoFontGameBold")
    label:SetColor(1, 1, 1, 1)
    label:SetText("XPulse move mode")

    mover:SetHandler("OnMove", function()
        SaveMoverPosition()
    end)
    mover:SetHandler("OnMoveStop", function()
        SaveMoverPosition()
        Print(string.format("Position saved: %d, %d.", saved.x, saved.y))
    end)
end

local function ScheduleApply(delay)
    if applyScheduled then
        return
    end

    applyScheduled = true
    zo_callLater(function()
        applyScheduled = false
        ApplySettings()
    end, delay or 0)
end

local function InstallProgressBarHooks()
    if hooksInstalled or not PLAYER_PROGRESS_BAR then
        return
    end

    if type(PLAYER_PROGRESS_BAR.RefreshTemplate) == "function" then
        ZO_PreHook(PLAYER_PROGRESS_BAR, "RefreshTemplate", function()
            ScheduleApply()
        end)
    end

    if type(PLAYER_PROGRESS_BAR.Show) == "function" then
        ZO_PreHook(PLAYER_PROGRESS_BAR, "Show", function()
            ScheduleApply()
        end)
    end

    hooksInstalled = true
end

local function ToggleMoveMode()
    if not ApplySettings() then
        Print("The experience bar is not ready yet. Try again after entering the world.")
        return
    end

    moveMode = not moveMode
    mover:SetHidden(not moveMode)
    if moveMode then
        UpdateMover()
        Print("Move mode enabled. Drag the highlighted bar, then use /xpulse move to lock it.")
    else
        Print("Move mode disabled.")
    end
end

local function SetScale(argument)
    local percent = tonumber(argument)
    if not percent or percent < MIN_SCALE * 100 or percent > MAX_SCALE * 100 then
        Print("Use /xpulse scale <50-200>, for example /xpulse scale 80.")
        return
    end

    saved.scale = ClampScale(percent / 100)
    if ApplySettings() then
        Print(string.format("Experience bar scale set to %d%%.", math.floor(saved.scale * 100 + 0.5)))
    else
        Print("The experience bar is not ready yet. Try again after entering the world.")
    end
end

local function ResetSettings()
    if not ApplyBarPosition() then
        Print("The experience bar is not ready yet. Try again after entering the world.")
        return
    end

    saved.x = saved.defaultX
    saved.y = saved.defaultY
    saved.scale = DEFAULT_SCALE
    if not ApplySettings() then
        Print("The experience bar could not be reset. Try again after entering the world.")
        return
    end
    if moveMode then
        UpdateMover()
    end
    Print("Position and scale reset to the values captured when XPulse first loaded.")
end

local function ShowHelp()
    Print("/xpulse move - toggle drag mode.")
    Print("/xpulse scale <50-200> - resize the experience bar.")
    Print("/xpulse reset - restore the initial position and size.")
end

local function HandleSlashCommand(text)
    local command, argument = string.match(string.lower(text or ""), "^(%S*)%s*(.-)%s*$")
    if command == "move" then
        ToggleMoveMode()
    elseif command == "scale" or command == "size" then
        SetScale(argument)
    elseif command == "reset" then
        ResetSettings()
    else
        ShowHelp()
    end
end

local function OnPlayerActivated()
    EVENT_MANAGER:UnregisterForEvent(ADDON_NAME .. "_Activated", EVENT_PLAYER_ACTIVATED)
    InstallProgressBarHooks()
    ScheduleApply(1000)
end

EVENT_MANAGER:RegisterForEvent(ADDON_NAME .. "_Loaded", EVENT_ADD_ON_LOADED, function(_, addonName)
    if addonName ~= ADDON_NAME then
        return
    end

    EVENT_MANAGER:UnregisterForEvent(ADDON_NAME .. "_Loaded", EVENT_ADD_ON_LOADED)
    saved = ZO_SavedVars:NewAccountWide(SAVED_VARIABLES, 1, nil, DEFAULTS)
    CreateMover()
    SLASH_COMMANDS["/xpulse"] = HandleSlashCommand

    EVENT_MANAGER:RegisterForEvent(ADDON_NAME .. "_Activated", EVENT_PLAYER_ACTIVATED, OnPlayerActivated)
    EVENT_MANAGER:RegisterForEvent(ADDON_NAME .. "_Resize", EVENT_SCREEN_RESIZED, function()
        ScheduleApply()
    end)
end)
