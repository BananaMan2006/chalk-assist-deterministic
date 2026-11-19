-- One-hop client-session handoff. No files, learned state, or enabled preferences.
-- Teleport settings expire when the client leaves this Roblox universe.
return function(ctx,services)
    ctx=ctx or {};services=services or {}
    local runtime=services.game or game
    local originJob=runtime.JobId
    local now=services.now or os.time
    local settingKey="ChalkDeterministicSessionV1"
    local entry=type(ctx.entry)=="table" and ctx.entry or {}
    local automatic=entry.entryKind=="autoexec" or entry.entryKind=="teleport"
    local supported=runtime.GameId==10770281752 and runtime.PlaceId==116097127629859
    local alive,untouched,applying=true,true,false
    local ownedMatch,outbound,completed=false,nil,false
    local status={available=false,resumed=false,message="Fresh launch · automation starts off"}
    local transport=services.teleport
    if not transport then pcall(function() transport=runtime:GetService("TeleportService") end) end
    local function text(v) return type(v)=="string" and #v>0 and #v<=128 end
    local function finite(v) return type(v)=="number" and v==v and math.abs(v)<math.huge end
    local function read()
        if not supported or not transport then return nil end
        local ok,v=pcall(function() return transport:GetTeleportSetting(settingKey) end)
        if not ok then status.message="Session handoff unavailable";return nil end
        return v
    end
    local function write(v)
        if not supported or not transport then return false end
        local ok=pcall(function() transport:SetTeleportSetting(settingKey,v) end)
        status.available=ok
        if not ok then status.message="Session handoff unavailable" end
        return ok
    end
    local function snapshot()
        local ok,s=pcall(ctx.snapshot)
        if not ok or type(s)~="table" then return nil end
        return s
    end
    local function eligible(s)
        return s and s.enabled==true and s.autoplay==true and text(s.selectedMode)
            and s.modeAvailable==true and s.testing~=true and s.alive~=false
    end
    local function revoke(reason)
        outbound=nil
        local revoked=write(false)
        status.revocationFailed=not revoked
        status.message=revoked and (reason or "Session continuation cancelled")
            or "Session cancellation failed; automation may resume after teleport"
    end
    local function arm(kind)
        local s=snapshot()
        if not alive or not eligible(s) then revoke();return false end
        local t=now()
        if not finite(t) then revoke();return false end
        local nonce
        if type(services.uuid)=="function" then nonce=services.uuid()
        else pcall(function() nonce=runtime:GetService("HttpService"):GenerateGUID(false) end) end
        if not text(nonce) then revoke("Session token unavailable");return false end
        outbound={schemaVersion=1,nonce=nonce,sourceJob=originJob,
            gameId=runtime.GameId,placeId=runtime.PlaceId,issuedAt=t,expiresAt=t+120,
            destination=kind,fullAuto=s.fullAuto==true,autoplay=true,selectedMode=s.selectedMode}
        if not write(outbound) then outbound=nil;return false end
        status.revocationFailed=false
        status.message="Session continuation ready for "..kind
        return true
    end
    local api={}
    function api.refresh()
        if not alive or applying then return end
        local s=snapshot()
        if not eligible(s) then
            if outbound or ownedMatch then ownedMatch=false;completed=false;revoke() end
            return
        end
        if not outbound then return end
        -- Never extend an old handoff simply because a heartbeat ran.
        if now()>outbound.expiresAt then revoke("Session continuation expired");return end
        outbound.fullAuto=s.fullAuto==true;outbound.selectedMode=s.selectedMode
        if not write(outbound) then outbound=nil end
    end
    function api.onChoice(kind,value)
        if not alive or applying then return end
        untouched=false
        if kind=="master" and value~=true or kind=="autoplay" and value~=true
            or kind=="assist" and value~=true then
            ownedMatch=false;completed=false;revoke();return
        end
        api.refresh()
    end
    function api.onQueue(packet,before)
        if not alive or type(packet)~="table" or type(before)~="table" then return end
        if packet.Status=="Found" and before.enabled==true and before.owned==true
            and before.pending~="Leave" and before.cancelWanted~=true
            and text(before.queuedMode) and (packet.Mode==nil or packet.Mode==before.queuedMode) then
            ownedMatch=false;completed=false;arm("match")
        elseif packet.Status=="Idle" or packet.Status=="Error" then
            -- A pending outbound match handoff cannot survive cancellation.
            if outbound and outbound.destination=="match" then revoke("Queue handoff cancelled") end
        elseif packet.Status=="Leaving" and ownedMatch and completed then
            arm("lobby")
        end
    end
    function api.onMatch(data)
        if not alive or type(data)~="table" then return end
        local s=snapshot()
        if s and s.testing then return end
        if ownedMatch and not completed and data.MatchOver==true then
            completed=true;arm("lobby")
        end
    end
    function api.onTeleport(state,placeId)
        if not alive then return end
        if placeId~=nil and placeId~=runtime.PlaceId then
            ownedMatch=false;completed=false;revoke("Unrelated destination");return
        end
        local name=tostring(state):match("([^%.]+)$")
        if name=="Failed" or name=="Cancelled" then revoke("Teleport did not complete")
        elseif name=="Started" or name=="InProgress" then api.refresh() end
    end
    function api.resume(sourceJob)
        if not alive or not automatic or not untouched or status.resumed
            or not text(sourceJob) or sourceJob==originJob then return false end
        local v=read();local s=snapshot();local t=now()
        local valid=type(v)=="table" and v.schemaVersion==1 and text(v.nonce)
            and v.sourceJob==sourceJob and v.gameId==runtime.GameId and v.placeId==runtime.PlaceId
            and finite(v.issuedAt) and finite(v.expiresAt) and finite(t)
            and v.issuedAt<=t+2 and v.expiresAt>=t and v.expiresAt-v.issuedAt==120
            and type(v.fullAuto)=="boolean" and v.autoplay==true and text(v.selectedMode)
            and (v.destination=="match" or v.destination=="lobby")
            and s and s.alive~=false and s.testing~=true
            and type(s.matchServer)=="boolean"
            and ((v.destination=="match") == s.matchServer)
        if not valid then
            if type(v)=="table" and v.sourceJob==sourceJob then revoke("No valid session handoff")
            else status.message="No valid session handoff" end
            return false
        end
        local good,allowed=pcall(ctx.modeAvailable,v.selectedMode)
        if not good or allowed~=true then revoke("Previous queue mode is unavailable");return false end
        -- If consumption cannot be recorded, do not enable anything.
        if not write(false) then return false end
        applying=true
        local ok,result=pcall(ctx.apply,v.fullAuto,v.selectedMode)
        applying=false;untouched=false
        if not ok or result~=true then
            if type(ctx.stop)=="function" then pcall(ctx.stop) end
            status.message="Session handoff could not be applied";return false
        end
        ownedMatch=v.destination=="match";completed=false
        status.resumed=true;status.message="Continued this play session"
        return true
    end
    function api.cancel(reason)
        untouched=false;ownedMatch=false;completed=false;revoke(reason)
    end
    function api.status()
        return {available=status.available,resumed=status.resumed,ownedMatch=ownedMatch,
            revocationFailed=status.revocationFailed==true,
            armed=outbound~=nil,destination=outbound and outbound.destination or nil,message=status.message}
    end
    function api.unload(automaticDestinationJob)
        if not alive then return end
        if text(automaticDestinationJob) and automaticDestinationJob~=originJob then
            -- An inherited old API may be disposed by automatic startup in
            -- the next job. Its one-hop handoff belongs to that destination.
            alive=false;outbound=nil;return
        end
        api.cancel("Session continuation cancelled by unload");alive=false
    end
    if not automatic then revoke("Manual launch · automation starts off") end
    return api
end
