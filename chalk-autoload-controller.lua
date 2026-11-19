-- Portable teleport registration; never attaches an executor or installs OS files.
-- ctx.bootstrapSource is embedded by the builder from chalk-bootstrap.lua.
return function(ctx,services)
    ctx=ctx or {};services=services or {}
    local runtimeGame=services.game or game
    local env=services.env or (type(getgenv)=="function" and getgenv() or _G)
    local global=services.globals or env
    local GAME_ID,PLACE_ID=10770281752,116097127629859
    local BOOT,QUEUE="__ChalkDeterministicAutoBoot","__ChalkDeterministicTeleportQueue"
    local alive=true
    local connection
    local retried=false
    local status={supported=false,queued=false,queueAvailable=false,attempts=0,
        message="Executor attachment is required; use its autoexec option for fresh launches."}
    local function sameJob(value)
        return type(value)=="table" and value.gameId==runtimeGame.GameId
            and value.placeId==runtimeGame.PlaceId and value.jobId==runtimeGame.JobId
    end
    local function identity(state)
        return {gameId=runtimeGame.GameId,placeId=runtimeGame.PlaceId,jobId=runtimeGame.JobId,state=state}
    end
    local function candidates()
        local result,seen={},{}
        local function add(value,name)
            if type(value)=="function" and not seen[value] then
                seen[value]=true;result[#result+1]={fn=value,name=name}
            end
        end
        add(global.queue_on_teleport or queue_on_teleport,"queue_on_teleport")
        add(global.queueonteleport or queueonteleport,"queueonteleport")
        local nativeSyn=global.syn or syn
        add(type(nativeSyn)=="table" and nativeSyn.queue_on_teleport,"syn.queue_on_teleport")
        return result
    end
    local function queue()
        if not alive or not status.supported then return false end
        if sameJob(env[QUEUE]) and env[QUEUE].queued and env[QUEUE].sessionProtocol==1 then
            status.queued=true;status.queueAvailable=true
            status.message="Automatic loading is queued for the next teleport."
            return true
        end
        local choices=candidates()
        status.queueAvailable=#choices>0
        if #choices==0 then
            status.message="This executor has no teleport queue; use its autoexec folder for automatic loading."
            return false
        end
        if type(ctx.bootstrapSource)~="string" or ctx.bootstrapSource=="" then
            status.message="Automatic loader source is missing from this build."
            return false
        end
        local payload="(function(...)\n"..ctx.bootstrapSource.."\nend)({automatic=true,teleportSourceJob="
            ..string.format("%q",runtimeGame.JobId).."})"
        for _,choice in ipairs(choices) do
            status.attempts=status.attempts+1
            local ok,result=pcall(choice.fn,payload)
            if ok and result~=false then
                local marker=identity("queued");marker.queued=true;marker.sessionProtocol=1
                env[QUEUE]=marker
                status.queued=true;status.provider=choice.name
                status.message="Automatic loading is queued for the next teleport."
                return true
            end
        end
        status.message="The executor rejected the teleport queue; one retry is allowed when teleporting."
        return false
    end
    local api={}
    function api.status()
        local copy={};for key,value in pairs(status) do copy[key]=value end
        return copy
    end
    function api.unload(preserve)
        if not alive then return end
        alive=false
        if connection then connection:Disconnect();connection=nil end
        if preserve~=true and status.supported and sameJob(env[BOOT]) then env[BOOT].state="unloaded" end
        -- A successful executor queue cannot generally be revoked. It only
        -- runs after a future teleport; same-job automatic restarts stay blocked.
    end
    if runtimeGame.GameId~=GAME_ID or runtimeGame.PlaceId~=PLACE_ID then
        status.message="Automatic loading is limited to the supported Chalk It Up place."
        return api
    end
    status.supported=true
    local boot=env[BOOT]
    if sameJob(boot) then boot.state="loaded" else env[BOOT]=identity("loaded") end
    queue()
    local connected=pcall(function()
        local me=services.player or runtimeGame:GetService("Players").LocalPlayer
        if not me or not me.OnTeleport then return end
        connection=me.OnTeleport:Connect(function(state,placeId)
            if not alive then return end
            if type(ctx.onTeleport)=="function" then pcall(ctx.onTeleport,state,placeId) end
            if status.queued or retried then return end
            local name=tostring(state)
            if name=="Started" or name=="InProgress" or name:match("%.Started$") or name:match("%.InProgress$") then
                retried=true;queue()
            end
        end)
    end)
    status.retryCallback=connected and connection~=nil
    return api
end
