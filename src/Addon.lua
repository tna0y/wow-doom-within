
-- globalslocal game = nil
DW_IsRunning = false

local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGOUT")

frame:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" and arg1 == "DoomWithin" then
        DoomWithinProfiling = {}
    elseif event == "PLAYER_LOGOUT" then
        if game ~= nil and ProfilingEnabled then
            DoomWithinProfiling = game.CPU.profiling_log
        end
    end
end)


local function StartDoom()
    
    print("Starting Doom...")
    if IsRunning then
        print("Doom is already running.")
        return
    end
    game = _DW_Game()
    
    game:Start()
    DW_IsRunning = true
end

local function StopDoom()
    if not IsRunning then
        print("Doom is not running.")
        return
    end

    game:Stop()
    DW_IsRunning = false
    print("Doom stopped.")
end

local function SaveJITRecording()
    if game ~= nil then
        print("Number of JIT recoded jit instructions: " .. #game.cpu.jitRecording)
        DoomWithinJITRecoding = game.cpu.jitRecording
    end
end

local function SaveProfiling()
    if game ~= nil then
        print("Number of Profiled calls: " .. #game.cpu.profiling_log)
        DoomWithinProfiling = game.cpu.profiling_log
    end
end

local function AddonCommands(msg, editbox)
    local _, _, cmd, args = string.find(msg, "%s?(%w+)%s?(.*)")
    if cmd == "start" then
        StartDoom()
    elseif cmd == "stop" then
        StopDoom()
    elseif cmd == "jit" then
        SaveJITRecording()
    elseif cmd == "profile" then
        SaveProfiling()
    else
        print("Unknown command: " .. cmd)
        print("Syntax: /doomwithin (start|stop)");
    end
end
  
SLASH_DOOMWITHIN1, SLASH_DOOMWITHIN2 = '/doomwithin', '/dw'
SlashCmdList["DOOMWITHIN"] = AddonCommands
