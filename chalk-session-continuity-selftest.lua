return function(createSession,coreSource)
    local result={total=0,passed=0,failed=0,results={}}
    local function test(name,fn)
        result.total=result.total+1;local ok,err=pcall(fn)
        result.results[#result.results+1]={name=name,passed=ok,error=not ok and tostring(err) or nil}
        if ok then result.passed=result.passed+1 else result.failed=result.failed+1 end
    end
    local function eq(a,b) assert(a==b,tostring(a).." ~= "..tostring(b)) end
    local function fixture(shared,job,entry,matchServer)
        shared=shared or {time=1000,serial=0};local h={shared=shared,applies=0,stops=0}
        h.s={enabled=true,alive=true,autoplay=false,fullAuto=false,selectedMode="1v1",modeAvailable=true,matchServer=matchServer==true}
        h.game={GameId=10770281752,PlaceId=116097127629859,JobId=job or "origin"}
        local transport={}
        function transport:GetTeleportSetting() if h.failRead then error("read") end;return shared.value end
        function transport:SetTeleportSetting(_,value)
            if h.failWrite then error("write") end
            -- Actual teleport settings are serialized, not references shared with callers.
            if type(value)=="table" then local t={};for k,v in pairs(value) do t[k]=v end;shared.value=t else shared.value=value end
        end
        h.api=createSession({entry={entryKind=entry or "autoexec"},snapshot=function() return h.s end,
            modeAvailable=function(mode) return h.s.modeAvailable and mode=="1v1" end,
            apply=function(fullAuto,mode)
                h.applies=h.applies+1
                if h.beforeApply then h.beforeApply() end
                h.s.fullAuto=fullAuto;h.s.autoplay=true;h.s.selectedMode=mode
                if h.applyError then error("apply") end
                return true
            end,stop=function() h.stops=h.stops+1;h.s.fullAuto=false;h.s.autoplay=false end},
            {game=h.game,teleport=transport,now=function() return shared.time end,
             uuid=function() shared.serial=shared.serial+1;return "ticket-"..shared.serial end})
        function h:enable()
            self.s.fullAuto=true;self.s.autoplay=true
            self.api.onChoice("fullplay",true);self.api.onChoice("autoplay",true)
        end
        function h:found(packet)
            self.api.onQueue(packet or {Status="Found",Mode="1v1"},
                {enabled=true,owned=true,pending="Join",queuedMode="1v1"})
        end
        return h
    end
    test("fresh and manual entries never inherit enabled settings",function()
        local a=fixture();a:enable();a:found()
        local b=fixture(a.shared,"match","manual",true)
        eq(b.api.resume("origin"),false);eq(b.applies,0);eq(a.shared.value,false)
    end)
    test("owned lobby match lobby round trip carries explicit choices once",function()
        local a=fixture();a:enable();a:found()
        local b=fixture(a.shared,"match","teleport",true)
        eq(b.api.resume("origin"),true);eq(b.s.fullAuto,true);eq(b.s.autoplay,true)
        eq(b.api.resume("origin"),false);eq(b.applies,1)
        b.api.onMatch({Phase="Result",MatchOver=true})
        local c=fixture(a.shared,"lobby2","teleport",false)
        eq(c.api.resume("match"),true);eq(c.s.fullAuto,true);eq(c.s.autoplay,true)
        eq(c.api.status().ownedMatch,false)
    end)
    test("owned match aborted before any round continues only into the lobby",function()
        local a=fixture();a:enable();a:found()
        local b=fixture(a.shared,"empty-match","teleport",true)
        assert(b.api.resume("origin"));eq(a.shared.value,false)
        b.api.onTeleport("Enum.TeleportState.Started",b.game.PlaceId)
        eq(b.api.status().destination,"lobby")
        local nonce,expires=a.shared.value.nonce,a.shared.value.expiresAt
        a.shared.time=a.shared.time+1
        b.api.onTeleport("Enum.TeleportState.InProgress",b.game.PlaceId)
        eq(a.shared.value.nonce,nonce);eq(a.shared.value.expiresAt,expires)
        local c=fixture(a.shared,"returned-lobby","teleport",false)
        assert(c.api.resume("empty-match"));eq(c.s.fullAuto,true);eq(c.s.autoplay,true)
        eq(c.api.status().ownedMatch,false)
    end)
    test("aborted-match return does not treat another match as a lobby",function()
        local a=fixture();a:enable();a:found()
        local b=fixture(a.shared,"empty-match","teleport",true);assert(b.api.resume("origin"))
        b.api.onTeleport("Started",b.game.PlaceId)
        local c=fixture(a.shared,"unrelated-match","teleport",true)
        eq(c.api.resume("empty-match"),false);eq(c.applies,0)
    end)
    test("aborted return needs known ownership destination and current ON choices",function()
        for _,kind in ipairs({"unowned","unknown-place","other-place","not-match","off","F8","failed","testing"}) do
            local a=fixture();a:enable();a:found()
            local b=fixture(a.shared,"empty-match","teleport",true)
            if kind~="unowned" then assert(b.api.resume("origin"))
            else b:enable();a.shared.value=false end
            local destination=b.game.PlaceId
            if kind=="unknown-place" then destination=nil
            elseif kind=="other-place" then destination=999
            elseif kind=="not-match" then b.s.matchServer=false
            elseif kind=="off" then b.s.autoplay=false;b.api.onChoice("autoplay",false)
            elseif kind=="F8" then b.api.unload()
            elseif kind=="failed" then b.api.onTeleport("Failed",destination)
            elseif kind=="testing" then b.s.testing=true end
            b.api.onTeleport("Started",destination)
            eq(b.api.status().armed,false)
            local c=fixture(a.shared,"returned-lobby","teleport",false)
            eq(c.api.resume("empty-match"),false);eq(c.applies,0)
        end
    end)
    test("unowned or mode-mismatched Found never arms",function()
        local a=fixture();a:enable()
        a.api.onQueue({Status="Found",Mode="1v1"},{enabled=true,owned=false,queuedMode="1v1"})
        eq(a.api.status().armed,false)
        a:found({Status="Found",Mode="2v2"});eq(a.api.status().armed,false)
        a:found({Status="Found"});eq(a.api.status().armed,true)
    end)
    test("unowned manually entered match cannot arm return",function()
        local a=fixture(nil,"manualmatch","autoexec",true);a:enable()
        a.api.onMatch({MatchOver=true});eq(a.api.status().armed,false)
    end)
    test("OFF after irrevocable queue registration cancels continuation",function()
        local a=fixture();a:enable();a:found();a.s.autoplay=false;a.api.onChoice("autoplay",false)
        local b=fixture(a.shared,"match","teleport",true)
        eq(b.api.resume("origin"),false);eq(b.applies,0)
    end)
    test("failed platform revocation is reported without claiming stale lease was cancelled",function()
        local a=fixture();a:enable();a:found();a.failWrite=true
        a.s.autoplay=false;a.api.onChoice("autoplay",false)
        eq(a.api.status().revocationFailed,true)
        assert(a.api.status().message:find("may resume",1,true))
        -- The unavailable client-session storage is the only cross-VM channel.
        -- Its old serialized value remains; this limitation must be explicit.
        eq(type(a.shared.value),"table")
        a.failWrite=false;a.api.cancel()
        eq(a.api.status().revocationFailed,false);eq(a.shared.value,false)
    end)
    test("Full Auto OFF carries only Autoplay and never revives Full Auto",function()
        local a=fixture();a:enable();a:found();a.s.fullAuto=false;a.api.onChoice("fullplay",false)
        local b=fixture(a.shared,"match","teleport",true)
        eq(b.api.resume("origin"),true);eq(b.s.fullAuto,false);eq(b.s.autoplay,true)
    end)
    test("Assist OFF before later Found cannot revive gameplay",function()
        local a=fixture();a:enable();a.s.fullAuto=false;a.api.onChoice("assist",false);a:found()
        local b=fixture(a.shared,"match","teleport",true)
        eq(b.api.resume("origin"),true);eq(b.s.fullAuto,false)
        assert(coreSource:find('and assist and assist.status().enabled==true',1,true))
    end)
    test("autoexec-first runtime can consume later queued handoff",function()
        local a=fixture();a:enable();a:found()
        local b=fixture(a.shared,"match","autoexec",true)
        eq(b.s.autoplay,false);eq(b.api.resume("origin"),true)
    end)
    test("destination user OFF wins over delayed queued handoff",function()
        local a=fixture();a:enable();a:found()
        local b=fixture(a.shared,"match","autoexec",true)
        b.api.onChoice("autoplay",false)
        eq(b.api.resume("origin"),false);eq(b.applies,0)
    end)
    test("F8 and same-job replacement invalidate prior lease",function()
        local a=fixture();a:enable();a:found();a.api.unload()
        local b=fixture(a.shared,"match","teleport",true)
        eq(b.api.resume("origin"),false);eq(b.applies,0)
    end)
    test("cross-job automatic disposal preserves handoff but same-job reload revokes",function()
        local a=fixture();a:enable();a:found();a.api.unload("match")
        local b=fixture(a.shared,"match","teleport",true)
        eq(b.api.resume("origin"),true)
        local c=fixture();c:enable();c:found();c.api.unload("origin")
        eq(fixture(c.shared,"match","teleport",true).api.resume("origin"),false)
    end)
    test("actual core startup preserves only cross-job automatic old-runtime cleanup",function()
        local prefix=assert(coreSource:match("^(.-)local shared = RS:WaitForChild"))
        for _,kind in ipairs({"teleport","autoexec","manual"}) do
            local a=fixture();a:enable();a:found()
            local env=setmetatable({}, {__index=_G});env._G=env
            env.getgenv=function() return env end
            env.game={JobId="match",GetService=function(_,name)
                return name=="Players" and {LocalPlayer={}} or {}
            end}
            env.ChalkDB={status=function() return {} end,context=function() return {jobId="origin"} end,
                unload=function(_,destination) a.api.unload(destination) end}
            local run
            if type(setfenv)=="function" then run=assert(loadstring(prefix));setfenv(run,env)
            else run=assert(load(prefix,"core cleanup fixture","t",env)) end
            run({entryKind=kind})
            local b=fixture(a.shared,"match","teleport",true)
            eq(b.api.resume("origin"),kind~="manual")
        end
    end)
    test("consume happens before application and duplicate callbacks",function()
        local a=fixture();a:enable();a:found()
        local b=fixture(a.shared,"match","teleport",true)
        local c=fixture(a.shared,"match","autoexec",true)
        b.beforeApply=function() eq(a.shared.value,false);eq(c.api.resume("origin"),false) end
        eq(b.api.resume("origin"),true);eq(c.applies,0)
    end)
    test("same source wrong source and wrong destination kind stay OFF",function()
        local a=fixture();a:enable();a:found()
        eq(fixture(a.shared,"origin","teleport",true).api.resume("origin"),false)
        eq(fixture(a.shared,"match","teleport",true).api.resume("unrelated"),false)
        eq(fixture(a.shared,"lobby","teleport",false).api.resume("origin"),false)
    end)
    test("expired corrupt and future leases remain OFF",function()
        for _,mutate in ipairs({function(v) v.expiresAt=999 end,function(v) v.fullAuto="true" end,
            function(v) v.issuedAt=2000;v.expiresAt=2120 end,function(v) v.schemaVersion=2 end}) do
            local a=fixture();a:enable();a:found();mutate(a.shared.value)
            eq(fixture(a.shared,"match","teleport",true).api.resume("origin"),false)
        end
    end)
    test("failed and unsupported teleports revoke",function()
        for _,args in ipairs({{"Enum.TeleportState.Failed"},{"Started",999}}) do
            local a=fixture();a:enable();a:found();a.api.onTeleport(args[1],args[2])
            eq(a.shared.value,false)
            eq(fixture(a.shared,"match","teleport",true).api.resume("origin"),false)
        end
    end)
    test("native MatchOver only and no visual test can arm return",function()
        local a=fixture();a:enable();a:found()
        local b=fixture(a.shared,"match","teleport",true);assert(b.api.resume("origin"))
        b.api.onMatch({matchOver=true});eq(b.api.status().armed,false)
        b.s.testing=true;b.api.onMatch({MatchOver=true});eq(b.api.status().armed,false)
    end)
    test("queue fault or implicit disabled state cannot rearm completed match",function()
        local a=fixture();a:enable();a:found()
        local b=fixture(a.shared,"match","teleport",true);assert(b.api.resume("origin"))
        b.s.autoplay=false;b.api.refresh();b.s.autoplay=true
        b.api.onMatch({MatchOver=true});eq(b.api.status().armed,false)
    end)
    test("unavailable mode or failed consume never enables",function()
        for _,kind in ipairs({"mode","write","read"}) do
            local a=fixture();a:enable();a:found()
            local b=fixture(a.shared,"match","teleport",true)
            if kind=="mode" then b.s.modeAvailable=false elseif kind=="write" then b.failWrite=true else b.failRead=true end
            eq(b.api.resume("origin"),false);eq(b.applies,0)
        end
    end)
    test("apply failure stops partially enabled features without retry",function()
        local a=fixture();a:enable();a:found()
        local b=fixture(a.shared,"match","teleport",true);b.applyError=true
        eq(b.api.resume("origin"),false);eq(b.stops,1);eq(b.s.fullAuto,false);eq(b.s.autoplay,false)
        eq(b.api.resume("origin"),false);eq(b.applies,1)
    end)
    test("refresh preserves original expiry and latest flags",function()
        local a=fixture();a:enable();a:found();local expires=a.shared.value.expiresAt
        a.shared.time=1050;a.api.refresh();eq(a.shared.value.expiresAt,expires)
        a.shared.time=1121;a.api.refresh();eq(a.shared.value,false)
    end)
    return result
end
