
-- params
local ProfilingEnabled = false
local ProfilingSamplingRate = 100 -- every N instructions

-- globals
DW_RiscVCore = nil
local IsRunning = false
local CloseButton = nil

local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGOUT")

frame:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" and arg1 == "DoomWithin" then
        DoomWithinProfiling = {}
    elseif event == "PLAYER_LOGOUT" then
        if DW_RiscVCore ~= nil and ProfilingEnabled then
            DoomWithinProfiling = DW_RiscVCore.profiling_log
        end
    end
end)


local function ShowCloseButton()
    if CloseButton then
        CloseButton:Show()
        return
    end
    CloseButton = CreateFrame("Button", "DoomWithinCloseButton", UIParent, "UIPanelButtonTemplate")
    CloseButton:SetText("X")
    CloseButton:SetSize(30, 30)
    CloseButton:SetPoint("CENTER", 305, 315)
    CloseButton:SetScript("OnClick", function() StopDoom() end)
    CloseButton:Show()
end

local function LoadChunkChain(cur_idx, text) 
    if cur_idx > #_DW_DoomLoadFuncs then
        RunNextFrame(function()
            ShowCloseButton()
            IsRunning = true
            DW_RiscVCore:Run()
        end)

        text:Hide()
        text:SetParent(nil) 
        print("Doom started.")
        return
    end
    text:SetText("Loading memory chunk " .. cur_idx .. " of " .. #_DW_DoomLoadFuncs)
    
    _DW_DoomLoadFuncs[cur_idx](DW_RiscVCore)
    RunNextFrame(function() LoadChunkChain(cur_idx + 1, text) end)
end

function StartDoom()
    
    print("Starting Doom...")
    if IsRunning then
        print("Doom is already running.")
        return
    end

    DW_RiscVCore = RVEMU_GetCore()
    
    local text = UIParent:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    text:SetPoint("CENTER")
    text:SetText("Initializing emulator...")
    
    RunNextFrame(function() 
        DW_RiscVCore:InitCPU(_DW_Init_doom)

        if ProfilingEnabled then
            DW_RiscVCore:EnableProfiling(ProfilingSamplingRate)
        end

        LoadChunkChain(1, text)
    end)
end

function StopDoom()
    if not IsRunning then
        print("Doom is not running.")
        return
    end

    if CloseButton then
        CloseButton:Hide()
    end

    DW_RiscVCore:Stop()
    IsRunning = false
    print("Doom stopped.")
end

local function AddonCommands(msg, editbox)
    local _, _, cmd, args = string.find(msg, "%s?(%w+)%s?(.*)")
    if cmd == "start" then
        StartDoom()
    elseif cmd == "stop" then
        StopDoom()
    else
        print("Syntax: /doomwithin (start|stop)");
    end
end
  
SLASH_DOOMWITHIN1, SLASH_DOOMWITHIN2 = '/doomwithin', '/dw'
SlashCmdList["DOOMWITHIN"] = AddonCommands
