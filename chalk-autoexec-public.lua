(function(...)
-- Portable Chalk Assist startup. Executor attachment is still required.
-- Automatic callers pass {automatic=true}; a manual run can restart after F8.
local options=(...)
options=type(options)=="table" and options or {}
local GAME_ID,PLACE_ID=10770281752,116097127629859
local MAIN_URL="https://raw.githubusercontent.com/BananaMan2006/chalk-assist-deterministic/main/chalk-it-up-1v1.lua"
local CACHE_FILE="chalk-deterministic-cache.lua"
local MAIN_FILE="chalk-it-up-1v1.lua"
local MIN_RELEASE="5.1.26"
local MARKER="__ChalkDeterministicAutoBoot"
local env=type(getgenv)=="function" and getgenv() or _G
local boot
local deadline=os.clock()+90
local teleportSource=options.automatic==true and type(options.teleportSourceJob)=="string"
    and #options.teleportSourceJob>0 and #options.teleportSourceJob<=128 and options.teleportSourceJob or nil
local function revokeHandoff()
    pcall(function() game:GetService("TeleportService"):SetTeleportSetting("ChalkDeterministicSessionV1",false) end)
end
local function report(message)
    if type(writefile)=="function" then pcall(writefile,"ciu_autoload_status.txt",message) end
end
local function running()
    local api=env.ChalkDB
    if type(api)~="table" or type(api.status)~="function" then return false end
    if type(api.context)=="function" then
        local good,current=pcall(api.context)
        if good and type(current)=="table" and current.jobId and current.jobId~=game.JobId then return false end
    end
    local ok,s=pcall(api.status)
    return ok and type(s)=="table" and type(s.auto)=="table" and s.product=="deterministic"
end
local function sameJob(value)
    return type(value)=="table" and value.gameId==game.GameId
        and value.placeId==game.PlaceId and value.jobId==game.JobId
end
local function settleRunning()
    if not running() then return false end
    local api=env.ChalkDB
    if teleportSource and type(api.resumeTeleportSession)=="function" then
        local ready,s=pcall(api.status)
        if not ready or type(s)~="table" or type(s.sessionContinuity)~="table" then return false end
        pcall(api.resumeTeleportSession,teleportSource)
    elseif options.automatic~=true then
        if type(api.cancelTeleportSession)=="function" then pcall(api.cancelTeleportSession,"Manual reload") end
        for _,name in ipairs({"setFullplay","setAuto","setAutoplay"}) do
            if type(api[name])=="function" then pcall(api[name],false) end
        end
    end
    return true
end
local function interrupted()
    if env[MARKER]~=boot then return "superseded" end
    if boot.state=="unloaded" then return "unloaded" end
    if settleRunning() then boot.state="loaded";return "already-running" end
end
local function waitFor(read,name)
    repeat
        local value=read()
        if value then return value end
        if os.clock()>=deadline then error("Timed out waiting for "..name,0) end
        task.wait(.1)
    until false
end
local function child(parent,name)
    return waitFor(function() return parent:FindFirstChild(name) end,name)
end
local function release(value)
    if type(value)~="string" then return end
    local a,b,c=value:match("^(%d+)%.(%d+)%.(%d+)$")
    if not a then return end
    local parts={a,b,c}
    for i,part in ipairs(parts) do
        if #part>6 or (#part>1 and part:sub(1,1)=="0") then return end
        parts[i]=tonumber(part)
    end
    return parts
end
local function compare(a,b)
    for i=1,3 do
        if a[i]~=b[i] then return a[i]>b[i] and 1 or -1 end
    end
    return 0
end
local function sourceRelease(source)
    if type(source)~="string" or #source==0 or #source>2*1024*1024 then return end
    -- The builder stamps the first line. Do not accept an unversioned or
    -- malformed CDN response as a replacement for an installed release.
    return release(source:match("^%-%- Chalk%-Release: ([^\r\n]+)\r?\n%-%- Chalk%-Product: deterministic\r?\n"))
end
local function compile(source)
    local ok,chunk=pcall(loadstring,source,"Chalk Assist")
    if ok and type(chunk)=="function" then return chunk end
end
local function download()
    -- A new join should revalidate the public build instead of reusing an
    -- executor's in-process URL cache. No installation identity is sent.
    local url=MAIN_URL.."?chalk_boot="..tostring(os.time())
    local available,httpGet=pcall(function() return game.HttpGet end)
    if available and type(httpGet)=="function" then
        local ok,body=pcall(httpGet,game,url)
        if ok and type(body)=="string" then return body end
    end
    local send=type(request)=="function" and request
        or type(http_request)=="function" and http_request
        or type(syn)=="table" and type(syn.request)=="function" and syn.request
    if send then
        local ok,response=pcall(send,{Url=url,Method="GET",Headers={["Cache-Control"]="no-cache"}})
        if ok and type(response)=="table" and tonumber(response.StatusCode)==200 then return response.Body end
    end
end
local ok,result=pcall(function()
    waitFor(function() return game:IsLoaded() end,"Roblox")
    if game.GameId~=GAME_ID or game.PlaceId~=PLACE_ID then
        if teleportSource then revokeHandoff() end
        return "unsupported-game"
    end
    if options.automatic~=true then revokeHandoff() end
    local previous=env[MARKER]
    if sameJob(previous) then
        if previous.state=="waiting" or previous.state=="starting" then
            if teleportSource then
                -- Local autoexec may win the loading race. Wait for its OFF
                -- runtime, then let that runtime validate the one-hop lease.
                repeat
                    if settleRunning() then return "already-running" end
                    local current=env[MARKER]
                    if sameJob(current) and current.state=="unloaded" then return "already-started" end
                    task.wait(.1)
                until os.clock()>=deadline
            end
            return "already-starting"
        end
        if settleRunning() then return "already-running" end
        if options.automatic then return "already-started" end -- F8 stays unloaded in this server.
    elseif previous==nil and settleRunning() then
        env[MARKER]={gameId=game.GameId,placeId=game.PlaceId,jobId=game.JobId,state="loaded"}
        return "already-running"
    end
    boot={gameId=game.GameId,placeId=game.PlaceId,jobId=game.JobId,state="waiting"}
    env[MARKER]=boot
    local me=waitFor(function() return game:GetService("Players").LocalPlayer end,"LocalPlayer")
    child(me,"PlayerGui")
    local moves=child(child(child(me,"PlayerScripts"),"Game"),"Moves")
    assert(moves:IsA("ModuleScript"),"Game.Moves is unavailable")
    local rs=game:GetService("ReplicatedStorage")
    local shared=child(rs,"Shared")
    for _,name in ipairs({"Config","Field","DivePath"}) do child(shared,name) end
    local remotes=child(rs,"Remotes")
    child(remotes,"Match");child(remotes,"Fx")
    local field=child(child(workspace,"Fields"),"Field1")
    local lines=child(field,"Lines")
    for _,name in ipairs({"Sideline_L","Sideline_R","BackLine","EndLine","GoalLine"}) do child(lines,name) end
    child(field,"Endzone")
    local stopped=interrupted()
    if stopped then return stopped end
    assert(type(loadstring)=="function","Executor loadstring is unavailable")
    local minimum=assert(release(MIN_RELEASE),"Bootstrap release metadata is unavailable")
    local source=download()
    local chunk,downloaded
    local floor=minimum
    local localSource,localChunk
    -- Read both candidates after HTTP returns: a manual update may have
    -- installed a newer release while the network request was in flight.
    if type(readfile)=="function" then
        for _,path in ipairs({CACHE_FILE,MAIN_FILE}) do
            local readOK,cached=pcall(readfile,path)
            if readOK then
                local version=sourceRelease(cached)
                if version and compare(version,floor)>=0 then
                    local cachedChunk=compile(cached)
                    if cachedChunk then
                        floor,localSource,localChunk=version,cached,cachedChunk
                    end
                end
            end
        end
    end
    local downloadedVersion=sourceRelease(source)
    if downloadedVersion and compare(downloadedVersion,floor)>=0 then
        chunk=compile(source)
        downloaded=chunk~=nil
    end
    if not chunk then source,chunk=localSource,localChunk end
    stopped=interrupted() -- HTTP/file APIs can yield while a manual load or F8 runs.
    if stopped then return stopped end
    assert(chunk,"No valid Chalk Assist release at or above "..MIN_RELEASE.." is available; try again manually")
    boot.state="starting"
    chunk({entryKind=teleportSource and "teleport" or options.automatic==true and "autoexec" or "manual",
        teleportSourceJob=teleportSource})
    assert(running(),"Chalk Assist did not finish starting")
    boot.state="loaded"
    if downloaded and type(writefile)=="function" then
        pcall(writefile,CACHE_FILE,source)
        pcall(writefile,MAIN_FILE,source)
    end
    report(downloaded and "Chalk Assist loaded from the public repository."
        or "Chalk Assist loaded from the newest valid local release; the public download was unavailable, invalid, or older.")
    return downloaded and "loaded-public" or "loaded-cache"
end)
if not ok then
    if teleportSource then revokeHandoff() end
    if boot and env[MARKER]==boot then env[MARKER]=nil end
    report("Chalk Assist startup failed. Try the loader again manually.")
    if type(warn)=="function" then warn("Chalk Assist startup failed: "..tostring(result)) end
    return false,tostring(result)
end
return true,result

end)({automatic=true})
