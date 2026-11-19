-- Owns one idle listener and one delayed keep-alive, independently of gameplay.
-- Successful input delivery is recorded; it is not proof of a server timer reset.
return function(services)
    services=services or {}
    local player=services.player or game:GetService("Players").LocalPlayer
    local now=services.now or os.clock
    local delay=services.delay or task.delay
    local cancel=services.cancel or task.cancel
    local keepAlive=services.keepAlive or function()
        local camera=workspace.CurrentCamera
        assert(camera,"Camera unavailable for idle keep-alive")
        local virtualUser=game:GetService("VirtualUser")
        virtualUser:CaptureController()
        -- Atomic click: no movement keys, delayed release, or held mouse button.
        virtualUser:ClickButton2(Vector2.zero,camera.CFrame)
    end
    local alive=true
    local connection,timer
    local lastAttempt,lastSuccess,lastReason,lastError,idleSeconds
    local attempts,successes,idleEvents=0,0,0
    local interval,cooldown=60,45
    local api={}

    local function pulse(reason)
        if not alive then return false,"unloaded" end
        local time=now()
        if lastAttempt and time-lastAttempt<cooldown then return false,"cooldown" end
        lastAttempt,lastReason=time,reason
        attempts=attempts+1
        local ok,err=pcall(keepAlive)
        if ok then
            successes=successes+1
            lastSuccess,lastError=time,nil
        else
            lastError=tostring(err)
        end
        return ok,lastError
    end
    local function schedule()
        timer=delay(interval,function()
            timer=nil
            if not alive then return end
            pulse("interval")
            if alive then schedule() end
        end)
    end
    function api.status()
        return {enabled=alive,interval=interval,listener=connection~=nil,
            attempts=attempts,successes=successes,idleEvents=idleEvents,
            lastAttempt=lastAttempt,lastSuccess=lastSuccess,lastReason=lastReason,
            idleSeconds=idleSeconds,error=lastError}
    end
    function api.unload()
        if not alive then return end
        alive=false
        if connection then connection:Disconnect();connection=nil end
        if timer then pcall(cancel,timer);timer=nil end
    end
    connection=player.Idled:Connect(function(seconds)
        if not alive then return end
        idleEvents=idleEvents+1
        idleSeconds=tonumber(seconds)
        pulse("idle")
    end)
    pulse("startup")
    schedule()
    return api
end
