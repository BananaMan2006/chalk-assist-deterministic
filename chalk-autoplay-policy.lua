-- Pure, clock-driven matchmaking policy. Only native Join/Leave commands leave it.
local Policy={}
local activePhases={Pick=true,PreSnap=true,Hike=true,Live=true,RAC=true,Run=true,Result=true}
local queueStates={Searching=true,Found=true,Idle=true,Error=true,Leaving=true}

function Policy.modes(config)
    local result,seen={},{}
    local queue=type(config.Queue)=="table" and config.Queue or {}
    local live=type(queue.Live)=="table" and queue.Live or {}
    local function add(key,label)
        if type(key)=="string" and not seen[key] then
            seen[key]=true
            result[#result+1]={key=key,label=label or key,available=live[key]==true}
        end
    end
    for _,key in ipairs(type(queue.Modes)=="table" and queue.Modes or {}) do add(key) end
    local ranked=type(config.Ranked)=="table" and config.Ranked.Modes or {}
    local keys={}
    for key in pairs(type(ranked)=="table" and ranked or {}) do
        if type(key)=="string" then keys[#keys+1]=key end
    end
    table.sort(keys)
    for _,key in ipairs(keys) do add(key,"Ranked "..tostring(ranked[key])) end
    return result
end

function Policy.new(modes,settings)
    settings=type(settings)=="table" and settings or {}
    local self={modes=modes,allowed={},labels={},enabled=false,selectedMode=nil,
        queueStatus="Unknown",owned=false,failures=0,retryAt=0,activeSeen=false,
        cancelWanted=false,foundNotified=false,message="Autoplay off"}
    for _,entry in ipairs(modes) do
        self.labels[entry.key]=entry.label
        if entry.available then self.allowed[entry.key]=true;self.selectedMode=self.selectedMode or entry.key end
    end
    if self.allowed[settings.selectedMode] then self.selectedMode=settings.selectedMode end
    -- A removed/unavailable saved selection must not silently start a
    -- different mode. The fallback is only for the disabled selector.
    self.enabled=settings.enabled==true and self.allowed[settings.selectedMode]==true
    if self.enabled then self.message="Waiting for lobby" end
    return setmetatable(self,{__index=Policy})
end

function Policy:selectMode(key)
    if not self.allowed[key] then return false,"This mode is not available" end
    if key~=self.selectedMode then
        self.selectedMode=key
        if self.owned and (self.queueStatus=="Searching" or self.pending=="Join") then
            self.cancelWanted=true
        end
    end
    return true
end
function Policy:setEnabled(value)
    if value==true and self.queueStatus=="Blocked" then return false end
    self.enabled=value==true and self.allowed[self.selectedMode]==true
    if self.enabled then
        self.failures=0
        self.message="Waiting for lobby"
    else
        if self.owned and (self.queueStatus=="Searching" or self.pending=="Join") then
            self.cancelWanted=true
        end
        self.message="Autoplay off"
    end
    return self.enabled
end
function Policy:fail(reason,now)
    self.failures=self.failures+1
    self.retryAt=now+math.min(30,5*2^(self.failures-1))
    self.message=reason or "Queue request failed"
    if self.failures>=3 then
        self.enabled=false
        self.message="Autoplay paused after three queue failures"
    end
end
function Policy:observeQueue(packet,now,bootstrap)
    if type(packet)~="table" or not queueStates[packet.Status] then return false end
    local status=packet.Status
    local previous,pending,owned=self.queueStatus,self.pending,self.owned
    if type(packet.Mode)=="string" then self.queuedMode=packet.Mode end
    if bootstrap then self.owned=false end
    self.queueStatus=status
    if status=="Searching" then
        if pending=="Leave" then
            -- A delayed/repeated search acknowledgement cannot undo an
            -- outstanding cancellation or cause another Leave each frame.
            self.queueStatus="Cancelling"
            self.message="Cancelling previous search"
            return false
        end
        self.pending=nil
        self.foundNotified=false
        if owned and not bootstrap then self.failures=0 end
        self.message=(self.owned and "Autoplay searching · " or "Searching · ")
            ..(self.labels[self.queuedMode] or self.queuedMode or "selected mode")
    elseif status=="Found" then
        self.pending=nil
        self.owned=false
        self.cancelWanted=false
        self.message="Game found"
        if not self.foundNotified then self.foundNotified=true;return true end
    elseif status=="Leaving" then
        self.pending=nil
        self.owned=false
        self.cancelWanted=false
        self.message="Returning to lobby"
    elseif status=="Idle" then
        self.pending=nil
        self.owned=false
        self.foundNotified=false
        self.cancelWanted=false
        -- A user cancelling an accepted queue is respected instead of being
        -- immediately put back in it. Our own Leave has a pending marker.
        if owned and previous=="Searching" and pending~="Leave" then
            self.enabled=false
            self.message="Queue stopped · autoplay paused"
        else self.message=self.enabled and "Ready to find next game" or "Autoplay off" end
        self.retryAt=math.max(self.retryAt,now+1)
    else
        if pending=="Leave" then
            self.pending=nil;self.enabled=false;self.cancelWanted=false
            self.queueStatus="Blocked"
            self.message="Autoplay paused · queue cancellation failed"
            return false
        end
        self.pending=nil
        self.owned=false
        self.cancelWanted=false
        self.foundNotified=false
        if owned and not bootstrap then self:fail(packet.Message or "Queue request failed",now)
        else self.retryAt=math.max(self.retryAt,now+5);self.message=packet.Message or "Queue unavailable" end
    end
    return false
end
function Policy:bootstrap(status,mode,now)
    if self.queueStatus~="Unknown" or self.pending or self.owned then return false end
    return self:observeQueue({Status=status,Mode=mode},now,true)
end

function Policy:step(snapshot,now)
    local s=type(snapshot)=="table" and snapshot or {}
    local phase=s.phase
    if phase~="Lobby" then
        self.lobbySince=nil
        if activePhases[phase] then
            self.activeSeen=true
            self.owned=false;self.pending=nil;self.cancelWanted=false
            self.queueStatus="Match"
            self.message=self.enabled and "Next game: "..(self.labels[self.selectedMode] or "select a mode") or "Autoplay off"
        end
        self.lastPhase=phase
        return nil
    end
    if self.activeSeen then
        self.activeSeen=false
        self.queueStatus=s.matchServer and "Leaving" or "Unknown"
        self.owned=false;self.pending=nil;self.cancelWanted=false
        self.foundNotified=false
    end
    self.lastPhase=phase
    self.lobbySince=self.lobbySince or now
    if s.testing or s.alive==false or s.matchServer or s.dataLoaded~=true then return nil end
    if self.pending=="Join" and self.cancelWanted then self.pending=nil end
    if self.pending then
        if now-self.requestAt<10 then return nil end
        if self.pending=="Leave" then
            self.pending=nil;self.cancelWanted=false;self.enabled=false;self.queueStatus="Blocked"
            self.message="Autoplay paused · queue cancellation was not confirmed"
            return nil
        end
        self:fail("Queue did not respond · cancelling before retry",now)
        self.pending=nil;self.cancelWanted=true
    end
    if self.cancelWanted and self.owned and self.queueStatus~="Found" and self.queueStatus~="Leaving" then
        self.pending="Leave";self.requestAt=now;self.queueStatus="Cancelling"
        self.message="Cancelling previous search"
        return {command="Leave"}
    end
    if not self.enabled then return nil end
    if not self.allowed[self.selectedMode] then self.enabled=false;self.message="Selected mode is unavailable";return nil end
    if now-self.lobbySince<1.25 or now<self.retryAt then return nil end
    if self.queueStatus~="Idle" and self.queueStatus~="Error" then return nil end
    self.pending="Join";self.requestAt=now;self.owned=true;self.queuedMode=self.selectedMode
    self.queueStatus="Requesting";self.message="Finding "..self.labels[self.selectedMode]
    return {command="Join",mode=self.selectedMode}
end
function Policy:status()
    return {enabled=self.enabled,selectedMode=self.selectedMode,label=self.labels[self.selectedMode],
        queueStatus=self.queueStatus,queuedMode=self.queuedMode,owned=self.owned,
        pending=self.pending,requestAt=self.requestAt,retryAt=self.retryAt,failures=self.failures,
        cancelWanted=self.cancelWanted,activeSeen=self.activeSeen,lastPhase=self.lastPhase,
        foundNotified=self.foundNotified,message=self.message}
end
function Policy:restore(runtime,now)
    if type(runtime)~="table" then return end
    local accepted={Unknown=true,Idle=true,Error=true,Requesting=true,Searching=true,Found=true,
        Leaving=true,Match=true,Cancelling=true,Blocked=true}
    if not accepted[runtime.queueStatus] then return end
    self.queueStatus=runtime.queueStatus
    self.queuedMode=type(runtime.queuedMode)=="string" and runtime.queuedMode or nil
    self.owned=runtime.owned==true
    self.pending=(runtime.pending=="Join" or runtime.pending=="Leave") and runtime.pending or nil
    self.requestAt=type(runtime.requestAt)=="number" and runtime.requestAt or (self.pending and now or nil)
    self.retryAt=type(runtime.retryAt)=="number" and runtime.retryAt or now
    self.failures=math.max(0,math.min(3,tonumber(runtime.failures) or 0))
    self.cancelWanted=runtime.cancelWanted==true
    self.activeSeen=runtime.activeSeen==true
    self.lastPhase=runtime.lastPhase
    self.foundNotified=runtime.foundNotified==true
    self.message=type(runtime.message)=="string" and runtime.message or self.message
end
return Policy
