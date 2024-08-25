
local RiscVCore = nil

local function LoadChunkChain(cur_idx, text) 
    if cur_idx > #_DW_DoomLoadFuncs then
        RunNextFrame(function() RiscVCore:Run() end)

        text:Hide()
        text:SetParent(nil) 
        print("Doom started.")
        return
    end
    text:SetText("Loading memory chunk " .. cur_idx .. " of " .. #_DW_DoomLoadFuncs)
    
    _DW_DoomLoadFuncs[cur_idx](RiscVCore)
    RunNextFrame(function() LoadChunkChain(cur_idx + 1, text) end)
end

local function StartDoom()
    
    print("Starting Doom...")
    
    RiscVCore = RVEMU_GetCore()

    local text = UIParent:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    text:SetPoint("CENTER")
    text:SetText("Initializing emulator...")
    
    RunNextFrame(function() 
        RiscVCore:InitCPU(_DW_Init_doom)
        LoadChunkChain(1, text)
    end)
end

local function StopDoom()
    RiscVCore:Stop()
    print("Doom stopped.")
end

local function AddonCommands(msg, editbox)
    local _, _, cmd, args = string.find(msg, "%s?(%w+)%s?(.*)")
    print(cmd)
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
