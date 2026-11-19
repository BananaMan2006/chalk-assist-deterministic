-- Portable local autoexec loader for the verified Chalk It Up place.
-- Use your executor's autoexec folder; keep the main file in its workspace.
-- It runs once per joined server after attachment. F8 unloading stays unloaded.
-- No account/path assumptions. It cannot attach an executor and downloads no code.

local EXPECTED_GAME_ID = 10770281752
local EXPECTED_PLACE_ID = 116097127629859
local MAIN_FILE = "chalk-it-up-1v1.lua"
local TIMEOUT_SECONDS = 90
local MARKER = "__ChalkDeterministicAutoBoot"
local env = (type(getgenv) == "function" and getgenv()) or _G

local function report(message)
    if type(writefile) == "function" then
        pcall(writefile, "ciu_autoload_status.txt", message)
    end
end
local function runningAssist()
    if not env.ChalkDB or type(env.ChalkDB.status) ~= "function" then return false end
    if type(env.ChalkDB.context) == "function" then
        local good, context = pcall(env.ChalkDB.context)
        if good and type(context) == "table" and context.jobId
            and context.jobId ~= game.JobId then return false end
    end
    local ok, status = pcall(env.ChalkDB.status)
    return ok and type(status) == "table" and type(status.auto) == "table" and status.product == "deterministic"
end

task.spawn(function()
    local deadline = os.clock() + TIMEOUT_SECONDS
    local boot
    local function waitUntil(read, description)
        repeat
            local value = read()
            if value then return value end
            if os.clock() >= deadline then
                error("Timed out waiting for " .. description, 0)
            end
            task.wait(0.1)
        until false
    end
    local function child(parent, name)
        return waitUntil(function() return parent:FindFirstChild(name) end,
            parent.Name .. "." .. name)
    end
    local function interrupted()
        if env[MARKER] ~= boot or boot.state == "unloaded" then return true end
        if runningAssist() then boot.state = "loaded";return true end
        return false
    end

    local success, failure = pcall(function()
        waitUntil(function() return game:IsLoaded() end, "Roblox to load")
        if game.GameId ~= EXPECTED_GAME_ID or game.PlaceId ~= EXPECTED_PLACE_ID then
            return -- Never load this assist in another game or an unverified place.
        end

        local previous = env[MARKER]
        if type(previous) == "table" and previous.jobId == game.JobId
            and previous.placeId == game.PlaceId and previous.gameId == game.GameId then
            return -- Includes an earlier successful run that the user unloaded.
        end
        boot = {jobId=game.JobId, placeId=game.PlaceId, gameId=game.GameId,
            state="waiting"}
        env[MARKER] = boot
        if previous==nil and runningAssist() then
            boot.state = "already-running"
            report("Chalk Assist is already running in this server.")
            return
        end
        report("Waiting for Chalk It Up to finish loading.")

        local players = game:GetService("Players")
        local me = waitUntil(function() return players.LocalPlayer end, "your player")
        child(me, "PlayerGui")
        local scripts = child(me, "PlayerScripts")
        local client = child(scripts, "Game")
        local moves = child(client, "Moves")
        assert(moves:IsA("ModuleScript"), "Game.Moves is not a ModuleScript")

        local rs = game:GetService("ReplicatedStorage")
        local shared = child(rs, "Shared")
        child(shared, "Config")
        child(shared, "Field")
        child(shared, "DivePath")
        local remotes = child(rs, "Remotes")
        child(remotes, "Match")
        child(remotes, "Fx")
        local field = child(child(workspace, "Fields"), "Field1")
        local lines = child(field, "Lines")
        for _, name in ipairs({"Sideline_L", "Sideline_R", "BackLine", "EndLine", "GoalLine"}) do
            child(lines, name)
        end
        child(field, "Endzone")
        if interrupted() then return end

        assert(type(readfile) == "function", "Executor readfile is unavailable")
        assert(type(loadstring) == "function", "Executor loadstring is unavailable")
        local source = readfile(MAIN_FILE)
        assert(type(source)=="string" and source:match("^%-%- Chalk%-Release: %d+%.%d+%.%d+\r?\n%-%- Chalk%-Product: deterministic\r?\n"),
            "Installed file is not a deterministic Chalk Assist release")
        local run, compileError = loadstring(source)
        if interrupted() then return end
        assert(run, compileError)
        boot.state = "starting"
        run()
        assert(runningAssist(),
            "Chalk Assist did not finish starting")
        boot.state = "loaded"
        report("Chalk Assist loaded automatically in Chalk It Up.")
    end)

    if not success then
        if boot and env[MARKER] == boot then env[MARKER] = nil end
        report("Chalk Assist auto-load failed: " .. tostring(failure))
        warn("Chalk Assist auto-load failed: " .. tostring(failure))
    end
end)
