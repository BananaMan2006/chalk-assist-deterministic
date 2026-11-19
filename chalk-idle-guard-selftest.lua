-- Lifecycle and scheduling tests only; no native input or Roblox idle timer.
return function(create)
    local report={total=0,passed=0,failed=0,results={}}
    local function test(name,body)
        report.total=report.total+1
        local ok,reason=pcall(body)
        report[ok and "passed" or "failed"]=report[ok and "passed" or "failed"]+1
        report.results[#report.results+1]={name=name,passed=ok,error=not ok and tostring(reason) or nil}
    end
    local function harness()
        local h={time=0,listeners={},timers={},deliveries={},disconnects=0,cancellations=0}
        local signal={}
        function signal:Connect(callback)
            local entry={callback=callback,connected=true}
            h.listeners[#h.listeners+1]=entry
            function entry:Disconnect()
                if self.connected then self.connected=false;h.disconnects=h.disconnects+1 end
            end
            return entry
        end
        h.player=setmetatable({Idled=signal},{__index=function(_,key)
            error("Guard accessed unnecessary player state: "..tostring(key))
        end})
        h.services={player=h.player,now=function() return h.time end,
            delay=function(seconds,callback)
                assert(seconds>0,"timer must not spin")
                local timer={at=h.time+seconds,callback=callback,pending=true}
                h.timers[#h.timers+1]=timer
                return timer
            end,
            cancel=function(timer)
                h.cancellations=h.cancellations+1
                if h.cancelError then error(h.cancelError) end
                timer.pending=false
            end,
            keepAlive=function()
                h.deliveries[#h.deliveries+1]=h.time
                if h.deliveryError then error(h.deliveryError) end
                if h.onDelivery then h.onDelivery() end
            end}
        function h:load() self.api=create(self.services);return self.api end
        function h:fire(seconds)
            for _,listener in ipairs(self.listeners) do
                if listener.connected then listener.callback(seconds) end
            end
        end
        function h:advance(seconds)
            local untilTime=self.time+seconds
            while true do
                local earliest
                for _,timer in ipairs(self.timers) do
                    if timer.pending and timer.at<=untilTime
                        and (not earliest or timer.at<earliest.at) then earliest=timer end
                end
                if not earliest then break end
                self.time=earliest.at;earliest.pending=false;earliest.callback()
            end
            self.time=untilTime
        end
        function h:activeListeners()
            local n=0;for _,listener in ipairs(self.listeners) do if listener.connected then n=n+1 end end
            return n
        end
        function h:pendingTimers()
            local n=0;for _,timer in ipairs(self.timers) do if timer.pending then n=n+1 end end
            return n
        end
        return h
    end

    test("startup delivery and one recurring 60-second timer",function()
        local h=harness();h:load()
        local s=h.api.status()
        assert(s.enabled and s.listener and s.interval==60)
        assert(s.attempts==1 and s.successes==1 and s.lastReason=="startup" and s.lastSuccess==0)
        assert(h:activeListeners()==1 and h:pendingTimers()==1)
        h:advance(59.999);assert(#h.deliveries==1)
        h:advance(.001);assert(#h.deliveries==2 and h.api.status().lastReason=="interval")
        h:advance(60);assert(#h.deliveries==3 and h:pendingTimers()==1)
    end)
    test("repeated idle events throttle delivery but retain idle diagnostics",function()
        local h=harness();h:load()
        for i=1,20 do h:fire(120+i) end
        assert(#h.deliveries==1 and h.api.status().idleEvents==20)
        h:advance(44.999);h:fire(165)
        assert(#h.deliveries==1)
        h:advance(.001);h:fire(166)
        local s=h.api.status()
        assert(#h.deliveries==2 and s.lastReason=="idle" and s.idleSeconds==166)
        h:fire(167);assert(#h.deliveries==2 and h.api.status().idleEvents==23)
    end)
    test("idle pulse and periodic pulse share the same cooldown",function()
        local h=harness();h:load();h:advance(45);h:fire(165)
        h:advance(15);assert(#h.deliveries==2 and h:pendingTimers()==1)
        h:advance(60);assert(#h.deliveries==3 and h.api.status().lastSuccess==120)
    end)
    test("failed delivery is contained and retries recover status",function()
        local h=harness();h.deliveryError="simulated unavailable input";h:load()
        local s=h.api.status()
        assert(s.attempts==1 and s.successes==0 and s.lastSuccess==nil)
        assert(string.find(s.error,"simulated unavailable input",1,true))
        h:fire(120);assert(#h.deliveries==1,"failure must also be throttled")
        h.deliveryError=nil;h:advance(60);s=h.api.status()
        assert(s.attempts==2 and s.successes==1 and s.error==nil and s.lastSuccess==60)
        assert(h:activeListeners()==1 and h:pendingTimers()==1)
    end)
    test("unload disconnects and cancels; stale callbacks cannot deliver or reschedule",function()
        local h=harness();h:load()
        local oldListener=h.listeners[1].callback
        local oldTimer=h.timers[1].callback
        h.api.unload();h.api.unload()
        assert(h.disconnects==1 and h.cancellations==1)
        assert(not h.api.status().enabled and not h.api.status().listener)
        assert(h:activeListeners()==0 and h:pendingTimers()==0)
        h:advance(120);oldListener(240);oldTimer()
        assert(#h.deliveries==1 and h.api.status().idleEvents==0 and #h.timers==1)
    end)
    test("timer cancellation failure still invalidates delayed work",function()
        local h=harness();h:load();h.cancelError="simulated cancellation race"
        h.api.unload();assert(not h.api.status().enabled and h:activeListeners()==0)
        h:advance(60)
        assert(#h.deliveries==1 and h:pendingTimers()==0 and #h.timers==1)
    end)
    test("reload leaves one listener and one effective periodic timer",function()
        local h=harness();local old=h:load()
        local oldCallback=h.listeners[1].callback
        old.unload();local replacement=h:load()
        assert(old~=replacement and h:activeListeners()==1 and h:pendingTimers()==1)
        h:advance(45);oldCallback(165);h:fire(165)
        assert(#h.deliveries==3 and old.status().attempts==1 and replacement.status().attempts==2)
        h:advance(75)
        assert(#h.deliveries==4 and h:activeListeners()==1 and h:pendingTimers()==1)
    end)
    test("unload during delivery prevents the next periodic schedule",function()
        local h=harness();h:load()
        h.onDelivery=function() h.api.unload() end
        h:advance(60)
        assert(#h.deliveries==2 and not h.api.status().enabled)
        assert(h:activeListeners()==0 and h:pendingTimers()==0 and #h.timers==1)
    end)
    test("no character, phase, UI, or assist state is required",function()
        local h=harness();h:load();h:advance(120)
        h:fire("180");h:advance(60)
        assert(h.api.status().enabled and #h.deliveries==4)
        assert(h.api.status().idleSeconds==180)
    end)
    return report
end
