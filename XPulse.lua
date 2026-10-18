-- AI assistance disclaimer: This addon was developed with assistance from AI tools.
-- AI-generated suggestions were reviewed and adapted by the author; verify behavior
-- and report issues through the project repository.

local ADDON_NAME = "XPulse"
local SAVED_VARIABLES = "XPulseSavedVariables"
local MIN_SCALE = 0.5
local MAX_SCALE = 2
local DEFAULT_SCALE = 1
local HISTORY_LIMIT = 10
local SETTINGS_PANEL_ID = "XPulseSettings"

local DEFAULTS =
{
    x = 0,
    y = 0,
    scale = DEFAULT_SCALE,
    positionCaptured = false,
    defaultScale = DEFAULT_SCALE,
    history = {},
}

local saved
local progressBar
local mover
local settingsPanel
local moveMode = false
local moveStartState
local hooksInstalled = false
local applyScheduled = false

local function Print(message)
    CHAT_ROUTER:AddSystemMessage("|c66ccffXPulse:|r " .. message)
end

local function ClampScale(scale)
    return math.max(MIN_SCALE, math.min(MAX_SCALE, scale))
end

local function IsValidState(state)
    return type(state) == "table"
        and type(state.x) == "number"
        and type(state.y) == "number"
        and type(state.scale) == "number"
end

local function CopyState(state)
    if not IsValidState(state) then
        return nil
    end

    return
    {
        x = state.x,
        y = state.y,
        scale = ClampScale(state.scale),
    }
end

local function StatesEqual(first, second)
    return IsValidState(first)
        and IsValidState(second)
        and first.x == second.x
        and first.y == second.y
        and first.scale == second.scale
end

local function GetHistory()
    if type(saved.history) ~= "table" then
        saved.history = {}
    end

    return saved.history
end

local function PushHistory(state)
    local copy = CopyState(state)
    if not copy then
        return
    end

    local history = GetHistory()
    if StatesEqual(history[1], copy) then
        return
    end

    table.insert(history, 1, copy)
    while #history > HISTORY_LIMIT do
        table.remove(history)
    end
end

local function GetCurrentState()
    if not saved
        or type(saved.x) ~= "number"
        or type(saved.y) ~= "number"
    then
        return nil
    end

    saved.scale = ClampScale(tonumber(saved.scale) or DEFAULT_SCALE)
    return
    {
        x = saved.x,
        y = saved.y,
        scale = saved.scale,
    }
end

local function RefreshSettingsPanel()
    if settingsPanel and CALLBACK_MANAGER then
        CALLBACK_MANAGER:FireCallbacks("LAM-RefreshPanel", settingsPanel)
    end
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
            local defaultX, defaultY = progressBar:GetLeft(), progressBar:GetTop()
            if type(defaultX) == "number" and type(defaultY) == "number" then
                saved.defaultX = defaultX
                saved.defaultY = defaultY
            else
                saved.defaultX = saved.x
                saved.defaultY = saved.y
            end
        end
        if type(saved.defaultScale) ~= "number" then
            local defaultScale = progressBar:GetScale()
            saved.defaultScale = type(defaultScale) == "number" and ClampScale(defaultScale) or DEFAULT_SCALE
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
    local defaultScale = progressBar:GetScale()
    saved.defaultScale = type(defaultScale) == "number" and ClampScale(defaultScale) or DEFAULT_SCALE
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

local function ApplyState(state)
    if not IsValidState(state) then
        return false
    end

    saved.x = state.x
    saved.y = state.y
    saved.scale = ClampScale(state.scale)
    return ApplySettings()
end

local function GetOriginalState()
    if not saved.positionCaptured
        or type(saved.defaultX) ~= "number"
        or type(saved.defaultY) ~= "number"
    then
        return nil
    end

    return
    {
        x = saved.defaultX,
        y = saved.defaultY,
        scale = ClampScale(tonumber(saved.defaultScale) or DEFAULT_SCALE),
    }
end

local function SaveMoverPosition()
    if not mover then
        return false
    end

    local x, y = mover:GetLeft(), mover:GetTop()
    if type(x) == "number" and type(y) == "number" then
        local newX = math.floor(x + 0.5)
        local newY = math.floor(y + 0.5)
        if saved.x ~= newX or saved.y ~= newY then
            saved.x = newX
            saved.y = newY
            ApplyBarPosition()
        end
        return true
    end

    return false
end

local function BeginMoverPosition()
    if not moveStartState then
        moveStartState = GetCurrentState()
    end
end

local function CommitMoverPosition()
    if not moveStartState then
        return false
    end

    SaveMoverPosition()
    local currentState = GetCurrentState()
    local changed = currentState and not StatesEqual(moveStartState, currentState)
    if changed then
        PushHistory(moveStartState)
    end
    moveStartState = nil
    return changed
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

    mover:SetHandler("OnMoveStart", function()
        BeginMoverPosition()
    end)
    mover:SetHandler("OnMove", function()
        BeginMoverPosition()
        SaveMoverPosition()
    end)
    mover:SetHandler("OnMoveStop", function()
        if CommitMoverPosition() then
            Print(string.format("Position saved: %d, %d.", saved.x, saved.y))
            RefreshSettingsPanel()
        end
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

local function SetMoveMode(enabled, announce)
    enabled = enabled == true
    if enabled == moveMode then
        if enabled then
            UpdateMover()
            mover:SetHidden(false)
        end
        return true
    end

    if not enabled then
        if moveStartState then
            CommitMoverPosition()
        end
        moveMode = false
        mover:SetHidden(true)
        if announce then
            Print("Move mode disabled.")
        end
        RefreshSettingsPanel()
        return true
    end

    if not ApplySettings() then
        Print("The experience bar is not ready yet. Try again after entering the world.")
        RefreshSettingsPanel()
        return false
    end

    moveMode = true
    mover:SetHidden(false)
    UpdateMover()
    if announce then
        Print("Move mode enabled. Drag the highlighted bar, then use /xpulse move to lock it.")
    end
    RefreshSettingsPanel()
    return true
end

local function ToggleMoveMode()
    SetMoveMode(not moveMode, true)
end

local function SetScalePercent(percent, announce)
    percent = tonumber(percent)
    if not percent or percent < MIN_SCALE * 100 or percent > MAX_SCALE * 100 then
        if announce then
            Print("Use /xpulse scale <50-200>, for example /xpulse scale 80.")
        end
        return false
    end

    if not ApplyBarPosition() then
        Print("The experience bar is not ready yet. Try again after entering the world.")
        return false
    end

    local newScale = ClampScale(percent / 100)
    local currentState = GetCurrentState()
    if currentState and currentState.scale ~= newScale then
        PushHistory(currentState)
    end

    saved.scale = newScale
    if not ApplySettings() then
        Print("The experience bar is not ready yet. Try again after entering the world.")
        return false
    end

    if announce then
        Print(string.format("Experience bar scale set to %d%%.", math.floor(saved.scale * 100 + 0.5)))
    end
    RefreshSettingsPanel()
    return true
end

local function SetScale(argument)
    SetScalePercent(argument, true)
end

local function ResetToLast()
    if not ApplyBarPosition() then
        Print("The experience bar is not ready yet. Try again after entering the world.")
        return false
    end

    local currentState = GetCurrentState()
    local history = GetHistory()
    local previousState
    while #history > 0 and not previousState do
        local candidate = table.remove(history, 1)
        if IsValidState(candidate) and not StatesEqual(currentState, candidate) then
            previousState = CopyState(candidate)
        end
    end

    if not previousState then
        Print("There is no previous position and scale to restore.")
        RefreshSettingsPanel()
        return false
    end

    if not ApplyState(previousState) then
        if currentState then
            saved.x = currentState.x
            saved.y = currentState.y
            saved.scale = currentState.scale
        end
        table.insert(history, 1, previousState)
        Print("The experience bar could not be reset. Try again after entering the world.")
        RefreshSettingsPanel()
        return false
    end

    Print(string.format("Restored position and scale: %d, %d at %d%%.",
        saved.x, saved.y, math.floor(saved.scale * 100 + 0.5)))
    RefreshSettingsPanel()
    return true
end

local function ResetToOriginal()
    if not ApplyBarPosition() then
        Print("The experience bar is not ready yet. Try again after entering the world.")
        return false
    end

    local originalState = GetOriginalState()
    local currentState = GetCurrentState()
    if not originalState or not currentState then
        Print("The original experience bar position is not available yet.")
        return false
    end

    if StatesEqual(currentState, originalState) then
        Print("The experience bar is already at its original position and scale.")
        return false
    end

    PushHistory(currentState)
    if not ApplyState(originalState) then
        saved.x = currentState.x
        saved.y = currentState.y
        saved.scale = currentState.scale
        Print("The experience bar could not be reset. Try again after entering the world.")
        RefreshSettingsPanel()
        return false
    end

    Print("Position and scale reset to the original game defaults.")
    RefreshSettingsPanel()
    return true
end

local function CreateSettingsPanel()
    settingsPanel = LibAddonMenu2:RegisterAddonPanel(SETTINGS_PANEL_ID,
    {
        type = "panel",
        name = ADDON_NAME,
        displayName = ADDON_NAME,
        author = "Ixis",
        version = "1.0.0",
        registerForRefresh = true,
    })

    LibAddonMenu2:RegisterOptionControls(SETTINGS_PANEL_ID,
    {
        {
            type = "header",
            name = "Experience bar",
        },
        {
            type = "checkbox",
            name = "Move experience bar",
            tooltip = "Enable drag mode for the experience bar. Disable it to lock the bar in place.",
            getFunc = function()
                return moveMode
            end,
            setFunc = function(value)
                SetMoveMode(value, false)
            end,
            default = false,
        },
        {
            type = "slider",
            name = "Experience bar scale",
            tooltip = "Set the experience bar size from 50% to 200%.",
            min = MIN_SCALE * 100,
            max = MAX_SCALE * 100,
            step = 1,
            decimals = 0,
            clampInput = true,
            getFunc = function()
                return math.floor(saved.scale * 100 + 0.5)
            end,
            setFunc = function(value)
                SetScalePercent(value, false)
            end,
            default = DEFAULT_SCALE * 100,
        },
        {
            type = "header",
            name = "Reset",
        },
        {
            type = "button",
            name = "Reset to last position and scale",
            tooltip = "Step back to the most recently saved position and scale. Up to 10 previous states are remembered.",
            func = ResetToLast,
            disabled = function()
                return #GetHistory() == 0
            end,
        },
        {
            type = "button",
            name = "Reset to original",
            tooltip = "Restore the experience bar to its original game position and size.",
            func = ResetToOriginal,
        },
    })
end

local function ShowHelp()
    Print("/xpulse move - toggle drag mode.")
    Print("/xpulse scale <50-200> - resize the experience bar.")
    Print("/xpulse reset last - restore the previous position and scale.")
    Print("/xpulse reset original - restore the original game position and size.")
end

local function HandleSlashCommand(text)
    local command, argument = string.match(string.lower(text or ""), "^(%S*)%s*(.-)%s*$")
    if command == "move" then
        ToggleMoveMode()
    elseif command == "scale" or command == "size" then
        SetScale(argument)
    elseif command == "reset" then
        if argument == "last" or argument == "previous" then
            ResetToLast()
        elseif argument == "" or argument == "original" or argument == "default" then
            ResetToOriginal()
        else
            ShowHelp()
        end
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
    CreateSettingsPanel()
    SLASH_COMMANDS["/xpulse"] = HandleSlashCommand

    EVENT_MANAGER:RegisterForEvent(ADDON_NAME .. "_Activated", EVENT_PLAYER_ACTIVATED, OnPlayerActivated)
    EVENT_MANAGER:RegisterForEvent(ADDON_NAME .. "_Resize", EVENT_SCREEN_RESIZED, function()
        ScheduleApply()
    end)
end)
