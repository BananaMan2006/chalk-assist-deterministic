-- Matchmaking uses the same Join/Leave remote as the game's Play menu.
return function(ctx,Policy)
    local Players=game:GetService("Players")
    local RS=game:GetService("ReplicatedStorage")
    local RunService=game:GetService("RunService")
    local Http=game:GetService("HttpService")
    local player=Players.LocalPlayer
    local Config=require(RS.Shared.Config)
    local queue=RS:WaitForChild("Remotes"):WaitForChild("Queue")
    local SettingsFile="ciu_deterministic_autoplay_v1.json"
    local alive=true
    local connections={}
    local settings={}
    if type(readfile)=="function" then
        local good,value=pcall(function() return Http:JSONDecode(readfile(SettingsFile)) end)
        if good and type(value)=="table" then settings=value end
    end
    local modes=Policy.modes(Config)
    local previous=ctx.previousState
    local sameJob=type(previous)=="table" and previous.jobId==game.JobId
    local state=Policy.new(modes,sameJob and previous or settings)
    local managed=ctx.preferencesManaged==true
    local preferredEnabled=state.enabled
    local ready=not managed
    if sameJob then
        state:restore(previous,workspace:GetServerTimeNow())
    end
    if ctx.startDisabled==true then
        -- Keep the selected mode, but never inherit input/queue ownership.
        state.enabled=false
        if not (managed and sameJob) then
            state.owned=false
            state.pending=nil
            state.cancelWanted=false
        end
        state.message="Autoplay off"
    end
    local lastMatchFoundId,lastMatchFoundAt,lastMatchFoundMode
    if sameJob then
        lastMatchFoundId,lastMatchFoundAt,lastMatchFoundMode=
            previous.lastMatchFoundId,previous.lastMatchFoundAt,previous.lastMatchFoundMode
    end
    local saveError,lastSaved
    local function save()
        local savedEnabled=state.enabled
        if managed then savedEnabled=preferredEnabled end
        local encoded=Http:JSONEncode({enabled=savedEnabled,selectedMode=state.selectedMode})
        if encoded==lastSaved then return end
        if type(writefile)~="function" then saveError="Settings cannot be saved on this executor";return end
        local ok,err=pcall(writefile,SettingsFile,encoded)
        if ok then lastSaved=encoded;saveError=nil else saveError=tostring(err) end
    end
    local function found(mode)
        lastMatchFoundId=Http:GenerateGUID(false)
        lastMatchFoundAt=workspace:GetServerTimeNow()
        lastMatchFoundMode=mode or state.queuedMode or state.selectedMode
        if type(writefile)=="function" then
            local ok,err=pcall(function()
                writefile("ciu_match_alert.json",Http:JSONEncode({id=lastMatchFoundId,time=lastMatchFoundAt,
                    gameId=game.GameId,placeId=game.PlaceId,jobId=game.JobId,mode=lastMatchFoundMode}))
            end)
            if not ok then saveError="Match alert could not be saved: "..tostring(err) end
        end
    end
    connections[#connections+1]=queue.OnClientEvent:Connect(function(packet)
        if not alive then return end
        if type(ctx.onQueue)=="function" then pcall(ctx.onQueue,packet,state:status()) end
        if state:observeQueue(packet,workspace:GetServerTimeNow()) then found(packet.Mode) end
        save()
        if type(ctx.onStateChanged)=="function" then pcall(ctx.onStateChanged) end
    end)
    local function visible(object)
        local node=object
        while node and node~=player.PlayerGui do
            if node:IsA("GuiObject") and not node.Visible then return false end
            if node:IsA("ScreenGui") and not node.Enabled then return false end
            node=node.Parent
        end
        return node==player.PlayerGui
    end
    local function bootstrap()
        local playerGui=player:FindFirstChild("PlayerGui")
        local gui=playerGui and playerGui:FindFirstChild("PlayMenu")
        local play=gui and gui:FindFirstChild("Play",true)
        if not play or not visible(play) then return end
        local idle,searching,foundState,leaving=false,false,false,false
        for _,object in ipairs(play:GetDescendants()) do
            if (object:IsA("TextLabel") or object:IsA("TextButton")) and visible(object) then
                local value=string.upper(object.Text)
                idle=idle or value=="PLAY"
                searching=searching or string.find(value,"SEARCHING",1,true)==1
                foundState=foundState or value=="MATCH FOUND!" or value=="GET READY"
                leaving=leaving or value=="GG!" or string.find(value,"HEADING BACK",1,true)==1
            end
        end
        local status=leaving and "Leaving" or foundState and "Found" or searching and "Searching" or idle and "Idle"
        if status and state:bootstrap(status,nil,workspace:GetServerTimeNow())
            and workspace:GetAttribute("MatchServer")~=true then
            -- GET READY after teleport describes the same game that already
            -- emitted Found in the lobby; its durable alert survives the hop.
            found()
        end
    end
    local function tick()
        if not ready then return end
        local current=ctx.snapshot()
        current.matchServer=workspace:GetAttribute("MatchServer")==true
        current.dataLoaded=player:GetAttribute("DataLoaded")==true
        local now=workspace:GetServerTimeNow()
        -- Observe an existing native queue before making any request. This also
        -- covers reloads where its Searching/Found event already happened.
        if state.queueStatus=="Unknown" then bootstrap() end
        local action=state:step(current,now)
        if action then
            local ok,err=pcall(function()
                if action.command=="Join" then queue:FireServer("Join",action.mode)
                else queue:FireServer("Leave") end
            end)
            if not ok then state:observeQueue({Status="Error",Message=tostring(err)},now) end
        end
        save()
        if type(ctx.onStateChanged)=="function" then pcall(ctx.onStateChanged) end
    end
    local accumulator=0
    connections[#connections+1]=RunService.Heartbeat:Connect(function(dt)
        if not alive then return end
        accumulator=accumulator+dt
        if accumulator<0.25 then return end
        accumulator=0
        local ok,err=pcall(tick)
        if not ok then
            state.enabled=false;state.message="Autoplay paused: "..tostring(err);save()
            if type(ctx.onStateChanged)=="function" then pcall(ctx.onStateChanged) end
        end
    end)
    local api={}
    function api.modes()
        local result={}
        for _,entry in ipairs(modes) do result[#result+1]={key=entry.key,label=entry.label,available=entry.available} end
        return result
    end
    function api.selectMode(key)
        local ok,reason=state:selectMode(key);if ok then save() end;return ok,reason
    end
    function api.setEnabled(value,transient)
        ready=true
        local result=state:setEnabled(value)
        if managed and transient~=true then preferredEnabled=value==true end
        -- OFF must cancel an owned lobby search before an F8 unload can
        -- disconnect the periodic tick. Active matches still fail the gate.
        if not result then pcall(tick) end
        save()
        return result
    end
    function api.status()
        local result=state:status()
        result.jobId=game.JobId
        result.lastMatchFoundId,result.lastMatchFoundAt,result.lastMatchFoundMode=
            lastMatchFoundId,lastMatchFoundAt,lastMatchFoundMode
        result.saveError=saveError
        result.preferredEnabled=state.enabled
        if managed then result.preferredEnabled=preferredEnabled end
        return result
    end
    function api.unload()
        if not alive then return end
        alive=false
        for _,connection in ipairs(connections) do connection:Disconnect() end
        -- Reloads preserve queue ownership through api.status; do not cancel
        -- a legitimate search simply because the assist is being updated.
    end
    save()
    return api
end
