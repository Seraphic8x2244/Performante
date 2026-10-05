-- Performante
-- Vanilla WoW 1.12.1 / Lua 5.0.3
-- 0.1 baseline: live CHAT_MSG_ADDON counter by communication prefix.

local ADDON_NAME = "Performante"
local ADDON_VERSION = GetAddOnMetadata(ADDON_NAME, "Version")
local L = Performante_L

local Performante = CreateFrame("Frame", "PerformanteFrame", UIParent)
local counts = {}
local sorted = {}
local totalMessages = 0
local paused = false
local dirty = true
local updateElapsed = 0
local MAX_ROWS = 12

Performante:SetWidth(330)
Performante:SetHeight(286)
Performante:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
Performante:SetMovable(1)
Performante:EnableMouse(1)
Performante:RegisterForDrag("LeftButton")
Performante:SetFrameStrata("DIALOG")
Performante:SetBackdrop({
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true,
    tileSize = 16,
    edgeSize = 16,
    insets = { left = 4, right = 4, top = 4, bottom = 4 }
})
Performante:SetBackdropColor(0, 0, 0, 0.90)

Performante:SetScript("OnDragStart", function()
    this:StartMoving()
end)

Performante:SetScript("OnDragStop", function()
    this:StopMovingOrSizing()
end)

local title = Performante:CreateFontString(nil, "OVERLAY", "GameFontNormal")
title:SetPoint("TOPLEFT", Performante, "TOPLEFT", 12, -10)
title:SetText(L.TITLE .. " " .. (ADDON_VERSION or ""))

local status = Performante:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
status:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -5)
status:SetText(L.TOTAL .. ": 0")

local closeButton = CreateFrame("Button", nil, Performante, "UIPanelCloseButton")
closeButton:SetPoint("TOPRIGHT", Performante, "TOPRIGHT", -2, -2)
closeButton:SetScript("OnClick", function()
    Performante:Hide()
end)

local prefixHeader = Performante:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
prefixHeader:SetPoint("TOPLEFT", Performante, "TOPLEFT", 14, -55)
prefixHeader:SetText(L.PREFIX)

local countHeader = Performante:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
countHeader:SetPoint("TOPRIGHT", Performante, "TOPRIGHT", -18, -55)
countHeader:SetText(L.MESSAGES)

local divider = Performante:CreateTexture(nil, "ARTWORK")
divider:SetTexture(1, 1, 1)
divider:SetAlpha(0.20)
divider:SetHeight(1)
divider:SetPoint("TOPLEFT", Performante, "TOPLEFT", 12, -70)
divider:SetPoint("TOPRIGHT", Performante, "TOPRIGHT", -12, -70)

local rows = {}
local i
for i = 1, MAX_ROWS do
    local row = {}

    row.prefix = Performante:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.prefix:SetPoint("TOPLEFT", Performante, "TOPLEFT", 14, -73 - ((i - 1) * 15))
    row.prefix:SetWidth(238)
    row.prefix:SetJustifyH("LEFT")
    row.prefix:SetText("")

    row.count = Performante:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.count:SetPoint("TOPRIGHT", Performante, "TOPRIGHT", -18, -73 - ((i - 1) * 15))
    row.count:SetWidth(60)
    row.count:SetJustifyH("RIGHT")
    row.count:SetText("")

    rows[i] = row
end

local overflow = Performante:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
overflow:SetPoint("TOPLEFT", Performante, "TOPLEFT", 14, -257)
overflow:SetText("")

local function BuildSortedList()
    sorted = {}

    local prefix, count
    for prefix, count in pairs(counts) do
        table.insert(sorted, { prefix = prefix, count = count })
    end

    table.sort(sorted, function(a, b)
        if a.count == b.count then
            return a.prefix < b.prefix
        end
        return a.count > b.count
    end)
end

local function Refresh()
    if not dirty then
        return
    end

    BuildSortedList()

    if paused then
        status:SetText(L.TOTAL .. ": " .. totalMessages .. "   |cffffcc00" .. L.PAUSED .. "|r")
    else
        status:SetText(L.TOTAL .. ": " .. totalMessages)
    end

    local numRows = table.getn(sorted)
    local index
    for index = 1, MAX_ROWS do
        if index <= numRows then
            rows[index].prefix:SetText(sorted[index].prefix)
            rows[index].count:SetText(tostring(sorted[index].count))
        else
            rows[index].prefix:SetText("")
            rows[index].count:SetText("")
        end
    end

    if numRows > MAX_ROWS then
        overflow:SetText("+ " .. (numRows - MAX_ROWS) .. " " .. L.MORE_PREFIXES)
    else
        overflow:SetText("")
    end

    dirty = false
end

local function ResetCounts()
    counts = {}
    sorted = {}
    totalMessages = 0
    dirty = true
    Refresh()
end

local resetButton = CreateFrame("Button", nil, Performante, "UIPanelButtonTemplate")
resetButton:SetWidth(72)
resetButton:SetHeight(20)
resetButton:SetPoint("BOTTOMLEFT", Performante, "BOTTOMLEFT", 12, 10)
resetButton:SetText(L.RESET)
resetButton:SetScript("OnClick", function()
    ResetCounts()
end)

local pauseButton = CreateFrame("Button", nil, Performante, "UIPanelButtonTemplate")
pauseButton:SetWidth(72)
pauseButton:SetHeight(20)
pauseButton:SetPoint("LEFT", resetButton, "RIGHT", 8, 0)
pauseButton:SetText(L.PAUSE)
pauseButton:SetScript("OnClick", function()
    paused = not paused
    if paused then
        pauseButton:SetText(L.RESUME)
    else
        pauseButton:SetText(L.PAUSE)
    end
    dirty = true
    Refresh()
end)

Performante:RegisterEvent("CHAT_MSG_ADDON")
Performante:SetScript("OnEvent", function()
    if event == "CHAT_MSG_ADDON" then
        if paused then
            return
        end

        local prefix = arg1
        if not prefix or prefix == "" then
            prefix = "<no prefix>"
        end

        if counts[prefix] then
            counts[prefix] = counts[prefix] + 1
        else
            counts[prefix] = 1
        end

        totalMessages = totalMessages + 1
        dirty = true
    end
end)

Performante:SetScript("OnUpdate", function()
    updateElapsed = updateElapsed + arg1
    if updateElapsed >= 0.5 then
        updateElapsed = 0
        Refresh()
    end
end)

SLASH_PERFORMANTE1 = "/performante"
SLASH_PERFORMANTE2 = "/perf"
SlashCmdList["PERFORMANTE"] = function(msg)
    local command = string.lower(msg or "")

    if command == "reset" then
        ResetCounts()
        Performante:Show()
    elseif command == "pause" then
        paused = true
        pauseButton:SetText(L.RESUME)
        dirty = true
        Refresh()
    elseif command == "resume" then
        paused = false
        pauseButton:SetText(L.PAUSE)
        dirty = true
        Refresh()
    elseif command == "show" then
        Performante:Show()
    elseif command == "hide" then
        Performante:Hide()
    else
        if Performante:IsShown() then
            Performante:Hide()
        else
            Performante:Show()
        end
    end
end

Refresh()
