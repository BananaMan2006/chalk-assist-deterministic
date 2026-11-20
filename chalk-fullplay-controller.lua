-- Deterministic 1v1 setup/navigation. Fixed rules use bounded session observations.
-- No model, training, random selection, or shared service. Catch/tackle retain priority.
return function(ctx,Policy,services)
    services=services or {}
    local player=services.player or game:GetService("Players").LocalPlayer
    local world=services.world or workspace
    local rs=services.rs or game:GetService("ReplicatedStorage")
    local Config=services.Config or require(rs.Shared.Config)
    local Field=services.Field or require(rs.Shared.Field)
    local RouteMath=services.RouteMath or require(rs.Shared.RouteMath)
    local Planner=ctx.Planner or services.Planner
    local board=services.board or require(player.PlayerScripts.Game.RouteBoard)
    local submit=services.submit or function(payload) rs.Remotes.Submit:FireServer(payload) end
    local uis=services.uis or game:GetService("UserInputService")
    local guiService=services.guiService or game:GetService("GuiService")
    local run=services.runService or game:GetService("RunService")
    local http=services.http or game:GetService("HttpService")
    local read=services.read or readfile
    local write=services.write or writefile
    local append=services.append or appendfile
    local jobId=services.jobId or (game and game.JobId) or ""
    local settingsFile="ciu_deterministic_fullplay_v1.json"
    -- A reload, teleport, or prior saved ON preference must not resume control.
    -- This product never opens the former settings, route history, or journals.
    local enabled=false
    local routeCycle=0
    -- This counter is a fixed schedule preference, not an outcome/model. Only
    -- the new product's file is read; a saved ON flag never resumes control.
    if type(read)=="function" then
        local ok,saved=pcall(function() return http:JSONDecode(read(settingsFile)) end)
        local value=ok and type(saved)=="table" and saved.schemaVersion==1 and saved.routeCycle
        if type(value)=="number" and value==value and value>=0 and value<20 and value==math.floor(value) then
            routeCycle=value
        end
    end
    local alive=true
    local selected,routePlan,routeSource,planPass
    local routeWaypoint=2
    local lastLoggedWaypoint
    local roundKey,submitted,nextSubmit,submitTries=nil,false,0,0
    local laneSide,priorTarget,lastPhase,lastKind,lastSample=nil,nil,nil,nil,0
    local finalSprintCommitted=false
    local hardCutIssued=false
    local stemRecoveryUntil,stemRecoverySpent=0,0
    local recoveryObservedAt,recoveryObservedSprint
    local observedStartStamina,staminaObservedRound
    local observedSnapAt
    local message,errorMessage,saveError="Full auto off",nil,nil
    local navigationError
    local recentRoutes,memoryOpponent,activeRoute={},nil,nil
    local recentDefense,activeDefense={},nil
    local memoryOpponentId,memorySavedAt
    local recentSelections,selectionIndex={},0
    local lastLateBendTrialTrigger
    local observationStarted
    local campingObservation
    local ownPossessionObserved=false
    local campingCounterUsed=false
    local counters={routeRequests=0,rounds=0,pointsWon=0,pointsLost=0}
    local contactFxTimes={}
    local api={}
    local function log(kind,data)
        if type(append)~="function" then return end
        data=data or {};data.kind=kind;data.time=world:GetServerTimeNow()
        data.version=type(ctx.version)=="string" and ctx.version or "unversioned"
        data.buildId=ctx.buildId;data.policyMode="deterministic";data.fullAuto=enabled
        pcall(function() append("ciu_deterministic_events.jsonl",http:JSONEncode(data)..string.char(10)) end)
    end
    local function savePreferences()
        if type(write)~="function" then saveError="Saving full auto setting is unavailable";return end
        local ok,err=pcall(function()
            write(settingsFile,http:JSONEncode({schemaVersion=1,policyMode="deterministic",
                lastRequestedEnabled=enabled,autoResume=false,routeCycle=routeCycle}))
        end)
        saveError=not ok and tostring(err) or nil
    end
    local function pauseReason(s)
        if not alive or not enabled then return "Full auto off" end
        if not s.enabled or ctx.assistEnabled and not ctx.assistEnabled() then return "Full auto paused · assist off" end
        if s.testing then return "Full auto paused · local test" end
        if s.mode=="Team" or (s.mode and s.mode~="1v1") then return "Full auto · 1v1 only" end
        if uis:GetFocusedTextBox() or guiService.MenuIsOpen then return "Full auto paused · menu or text input" end
    end
    local function rootOf(character)
        return character and character:FindFirstChild("HumanoidRootPart")
    end
    local function coordinates(point)
        if typeof(point)=="Vector3" then return {x=point.X,y=point.Y,z=point.Z} end
    end
    local function descriptor(value)
        if type(value)~="table" or (value.pass~="Bullet" and value.pass~="Floater")
            or type(value.shape)~="string" or #value.shape>32 or type(value.depth)~="number"
            or value.depth~=value.depth or value.depth<0 or value.depth>100 then return nil end
        local out={}
        for _,key in ipairs({"pass","side","depth","shape","family","signature","success",
            "contested","result","time","roundKey","arrival","catchSuccess",
            "terminalResult","terminalAt","terminalPointLost","cutCount","lastCutAt","experimentalAttempt",
            "trialTrigger","experimentalClearanceGap","middleStemDeep","stemYards","cutLeadTime",
            "finishMode","estimatedFinishAt","estimatedFinishZ","finishReachable","finishDistance",
            "finishTravelTime","finishReserve","finishFraction","routeStrategy","slowStem",
            "slowStemTime","slowStemSpeed","slowStemStartupSlack","cutAt","startSprintAt","forceDiveFinish",
            "requireDive","finalSprint","finalSprintDuration","finalSprintReserve","finalSprintStamina",
            "sidelineInset","sidelineFallback","sidelineFallbackReason","diveWitnessElapsed",
            "diveWitnessX","diveWitnessZ","diveWitnessMargin","adaptiveUnderneath",
            "observedDefenderDepthYards","underneathDepthLimit","carryReserve","carryMoveReady","estimatedCatchStamina",
            "pacedSlant","slantWalkUntil","slantSprintDuration","routeFamily","cutDirection",
            "scheduledFamily","scheduleOverride","scheduledPass","passPreferenceOverride",
            "anticipatedLane","stemBlocked","preferAirborne","preferJumpDive","requireAirborne",
            "bestEffort","bestEffortReason","reachable","campingGateReason"}) do
            local v=value[key]
            if type(v)=="boolean" or type(v)=="string" and #v<=512
                or type(v)=="number" and v==v and math.abs(v)<math.huge then out[key]=v end
        end
        for _,key in ipairs({"estimatedCatchAt","estimatedCatchZ","estimatedFirstTouchAt","estimatedStopAt","estimatedContactMargin","stemSprintSeconds","stemSprintStart",
            "earlyStemSprintSeconds","stemRunSpeed","estimatedStemRegeneration","ballTargetZ","shortField",
            "stemTravelDistance","postThrowStem","stemDetour","forecastCount","cutAngle","estimatedCatchInsideGoal","rareBullet",
            "rareCampingBullet","continuousBulletCatch","carryMoveReserve","observedEndzoneCamping","campingObservationKnown",
            "campingEvidenceCount","campingCurrentKnown","campingCurrentWaiting","campingCounterUsed",
            "campingObservationSeconds","campingOwnProgressYards","campingDefenderDisplacementYards"}) do
            local v=value[key]
            if type(v)=="boolean" or type(v)=="number" and v==v and math.abs(v)<math.huge then out[key]=v end
        end
        return out
    end
    local function copyRecent()
        local result={}
        for _,item in ipairs(recentRoutes) do result[#result+1]=descriptor(item) end
        return result
    end
    local function copySelections()
        local result={}
        for _,item in ipairs(recentSelections) do result[#result+1]=descriptor(item) end
        return result
    end
    local function finite(value)
        return type(value)=="number" and value==value and math.abs(value)<math.huge
    end
    local function observeStartStamina(s)
        if s.mode and s.mode~="1v1" then
            observedStartStamina,staminaObservedRound=nil,nil
            return
        end
        if not enabled or s.testing or s.role~="WR" or s.phase~="Live" or s.arc or not finite(s.snapAt) then return end
        local elapsed=world:GetServerTimeNow()-s.snapAt
        local key=tostring(s.roundKey or s.preSnapEnds or s.snapAt)
        if key==staminaObservedRound or elapsed<0 or elapsed>.25 then return end
        local value=tonumber(player:GetAttribute("Stamina"))
        if not finite(value) or value<0 or not finite(Config.Stamina) or value>Config.Stamina then return end
        staminaObservedRound=key
        observedStartStamina=observedStartStamina and math.min(observedStartStamina,value) or value
        log("startStamina",{observed=value,elapsed=elapsed,matchMinimum=observedStartStamina,
            planningBudget=Policy.setupStaminaBudget(value,Config,observedStartStamina),
            setupAllowanceFraction=.25,empiricalAllowance=true})
    end
    local function accountStemRecovery(input)
        local at=input.elapsed
        local confirmed=input.role=="WR" and input.phase=="Live" and not input.ballActive
            and not input.passStarted and input.sprintOn==true
            and finite(input.currentWalkSpeed) and input.currentWalkSpeed>Config.RunSpeed+.05
        if finite(at) and finite(recoveryObservedAt) and confirmed and recoveryObservedSprint
            and at>recoveryObservedAt then
            local last=math.min(at,stemRecoveryUntil,
                finite(input.stemSprintStart) and input.stemSprintStart or stemRecoveryUntil)
            local spent=math.min(.1,math.max(0,last-recoveryObservedAt))
            stemRecoverySpent=math.min(.6,stemRecoverySpent+spent)
        end
        -- An allocated burst is an outstanding request, not observed spending.
        -- Walking/denied requests cannot consume the cap. Long observations
        -- contribute at most100ms rather than erasing every low-FPS interval.
        recoveryObservedAt=finite(at) and at or nil
        recoveryObservedSprint=confirmed and finite(at) and at<stemRecoveryUntil
        input.stemRecoverySpent=stemRecoverySpent
    end
    local function defenseDescriptor(value)
        if type(value)~="table" or (value.pass~="Bullet" and value.pass~="Floater")
            or not finite(value.launchAt) or not finite(value.depthAtThrow)
            or not finite(value.targetDepthYards) or not finite(value.goalDistanceYards)
            or type(value.deepEndzone)~="boolean" or type(value.playKey)~="string"
            or #value.playKey>256 then return nil end
        local out={}
        for _,key in ipairs({"pass","launchAt","depthAtThrow","targetDepthYards","goalDistanceYards",
            "deepEndzone","playKey","roundKey","result","opponentCaught","time"}) do
            local v=value[key]
            if type(v)=="boolean" or type(v)=="string" and #v<=256 or finite(v) then out[key]=v end
        end
        return out
    end
    local function copyDefense()
        local result={}
        for _,item in ipairs(recentDefense) do result[#result+1]=defenseDescriptor(item) end
        return result
    end
    local function defenseProfile()
        local bias,losses=0,0
        for _,item in ipairs(recentDefense) do
            if item.pass=="Floater" and item.deepEndzone then
                if item.opponentCaught and item.depthAtThrow<=.5 then
                    bias=math.min(2.5,bias+1.25);losses=losses+1
                elseif item.result=="Swatted" or item.result=="Intercepted" then
                    bias=math.max(0,bias-.25)
                end
            elseif item.pass=="Bullet" and not item.deepEndzone and item.opponentCaught then
                bias=math.max(0,bias-.5)
            end
        end
        local attempts=0
        for i=math.max(1,#recentDefense-2),#recentDefense do
            local item=recentDefense[i]
            if item.pass=="Floater" and item.deepEndzone then attempts=attempts+1 end
        end
        local latest=recentDefense[#recentDefense]
        -- Repeated observed deep throws describe the opponent's current play
        -- selection even when stopped. A newly short pass removes this shade;
        -- the fixed outcome-response rules above remain unchanged.
        local shortLatest=latest and latest.targetDepthYards<8
        return {depthBiasYards=bias,samples=#recentDefense,deepFloaterLosses=losses,
            recentDeepAttempts=attempts,deepAttemptShadeYards=attempts>=2 and not shortLatest and 0.75 or 0}
    end
    local function validId(value)
        return type(value)=="number" and value==value and value>0 and value<math.huge
            and value==math.floor(value)
    end
    local function opponentIdentity(s)
        local key=s.opponent and s.opponent.Name
        if type(key)~="string" or key=="" or #key>128 then return nil end
        local ok,id=pcall(function()
            local players=services.players or game:GetService("Players")
            local account=players:GetPlayerFromCharacter(s.opponent)
            return account and account.UserId
        end)
        return key,ok and validId(id) and id or nil
    end
    local function sameOpponent(memory,key,id)
        if type(memory)~="table" then return false end
        if validId(memory.opponentUserId) and validId(id) then return memory.opponentUserId==id end
        return memory.opponentKey==key
    end
    local function sessionRecord()
        return {schema=1,scope="current_opponent_session",persisted=false,
            opponentKnown=memoryOpponent~=nil,updatedAt=memorySavedAt,
            recentRoutes=copyRecent(),recentSelections=copySelections(),
            recentDefense=copyDefense(),selectionIndex=selectionIndex,
            campingCounterUsed=campingCounterUsed,
            lastLateBendTrialTrigger=lastLateBendTrialTrigger}
    end
    local function updateSessionHistory()
        memorySavedAt=world:GetServerTimeNow()
    end
    local campingFields={"observedEndzoneCamping","campingObservationKnown","campingObservationSeconds",
        "campingOwnProgressYards","campingDefenderDisplacementYards"}
    local function clearCampingEvidence()
        -- Explicit OFF/unload revokes this observation, including evidence from
        -- completed plays. Ordinary route failures remain session-local.
        for _,list in ipairs({recentRoutes,recentSelections}) do
            for _,item in ipairs(list) do
                for _,key in ipairs(campingFields) do item[key]=nil end
            end
        end
        if activeRoute then
            for _,key in ipairs(campingFields) do activeRoute[key]=nil end
        end
        campingObservation=activeRoute and {key=activeRoute.roundKey,invalid=true,frozen=true} or nil
    end
    local function clearSessionHistory()
        campingObservation=nil
        ownPossessionObserved=false
        campingCounterUsed=false
        recentRoutes,activeRoute={},nil
        recentDefense,activeDefense={},nil
        recentSelections,selectionIndex={},0
        memoryOpponent,memoryOpponentId,memorySavedAt=nil,nil,nil
        lastLateBendTrialTrigger=nil
        finalSprintCommitted=false
        hardCutIssued=false
        stemRecoveryUntil,stemRecoverySpent=0,0
        recoveryObservedAt,recoveryObservedSprint=nil,nil
        observedStartStamina,staminaObservedRound=nil,nil
        selected,routePlan,routeSource,planPass=nil,nil,nil,nil
        submitted=false;roundKey=nil;submitTries=0;nextSubmit=0;observedSnapAt=nil
        routeWaypoint=2;lastLoggedWaypoint=nil
        laneSide,priorTarget,lastKind=nil,nil,nil
    end
    local function syncOpponent(s)
        if s.phase=="Lobby" then
            if memoryOpponent or selected or #recentSelections>0 or #recentRoutes>0 then clearSessionHistory() end
            return
        end
        local key,id=opponentIdentity(s)
        if not key then return end
        if memoryOpponent and sameOpponent({opponentKey=memoryOpponent,opponentUserId=memoryOpponentId},key,id) then
            memoryOpponent=key;memoryOpponentId=id or memoryOpponentId
            return
        end
        clearSessionHistory()
        memoryOpponent,memoryOpponentId=key,id
        updateSessionHistory()
    end
    local function roundIdentity(s)
        return tostring(s.roundKey or s.preSnapEnds or "current")
    end
    local function freezeCampingObservation()
        local o=campingObservation
        if not o or o.frozen then return end
        local now=world:GetServerTimeNow()
        if not finite(now) or not o.lastAt or now<o.lastAt or now-o.lastAt>.35 then o.invalid=true end
        o.frozen=true
    end
    local function observeCamping(s,paused)
        if not activeRoute then return end
        local o=campingObservation
        if not o or o.key~=activeRoute.roundKey then
            o={key=activeRoute.roundKey};campingObservation=o
        end
        if o.frozen then return end
        if s.arc~=nil or s.passStarted==true or s.phase=="RAC" or s.phase=="Run" or s.phase=="Result" then
            freezeCampingObservation();return
        end
        if paused or s.alive==false or s.role~="WR" or not memoryOpponent
            or roundIdentity(s)~=o.key then o.invalid=true;return end
        if s.phase~="Live" then
            if o.lastAt then o.invalid=true end
            return
        end
        local root,opponent=rootOf(player.Character),rootOf(s.opponent)
        local position,other=root and root.Position,opponent and opponent.Position
        local velocity=opponent and opponent.AssemblyLinearVelocity
        local offset=s.offset or Vector3.zero
        local now,yd=world:GetServerTimeNow(),Field.YD
        local function validPoint(p)
            return typeof(p)=="Vector3" and finite(p.X) and finite(p.Y) and finite(p.Z)
        end
        if not validPoint(position) or not validPoint(other) or not validPoint(velocity)
            or not validPoint(offset) or not finite(now) or not finite(yd) or yd<=0
            or not finite(Field.GoalZ) or not finite(Config.RunSpeed) or Config.RunSpeed<=0 then
            o.invalid=true;return
        end
        if o.lastAt then
            local dt=now-o.lastAt
            if dt<0 or dt>.35 then o.invalid=true end
            if dt<=0 then return end
            o.seconds=o.seconds+dt
            o.distance=o.distance+((other-o.lastOpponent)*Vector3.new(1,0,1)).Magnitude
        else
            o.seconds=0;o.distance=0;o.startZ=position.Z;o.yd=yd;o.allCamping=true
        end
        if o.yd~=yd then o.invalid=true end
        local speed=(velocity*Vector3.new(1,0,1)).Magnitude
        local separation=((other-position)*Vector3.new(1,0,1)).Magnitude
        -- This labels an observed stationary deep defender, never intention or
        -- future behavior. Accumulated path rejects out-and-back movement.
        o.allCamping=o.allCamping and other.Z>=Field.GoalZ+offset.Z-yd
            and speed<=Config.RunSpeed*.4 and separation>=4*yd
        o.progress=(position.Z-o.startZ)/yd
        o.lastAt,o.lastOpponent=now,other
    end
    local function attachCampingObservation(item)
        freezeCampingObservation()
        local o=campingObservation
        local known=o and o.key==item.roundKey and not o.invalid
            and (o.seconds or 0)>=1-1e-6 and (o.progress or 0)>=3-1e-6
        item.campingObservationKnown=known==true
        item.observedEndzoneCamping=known==true and o.allCamping==true and o.distance<=o.yd+1e-6
        if o and o.key==item.roundKey and o.lastAt then
            item.campingObservationSeconds=o.seconds
            item.campingOwnProgressYards=o.progress
            item.campingDefenderDisplacementYards=o.distance/o.yd
        end
    end
    local function recordOutcome(result,success)
        if not activeRoute then return end
        local item=descriptor(activeRoute)
        if item then attachCampingObservation(item) end
        activeRoute=nil
        campingObservation=nil
        finalSprintCommitted=false
        if not item then return end
        item.success=success;item.contested=result=="Swatted" or result=="Intercepted"
        if result=="Catch" and success then item.catchSuccess=true;ownPossessionObserved=true end
        item.result=result;item.time=world:GetServerTimeNow()
        recentRoutes[#recentRoutes+1]=item
        while #recentRoutes>6 do table.remove(recentRoutes,1) end
        updateSessionHistory()
        log("routeOutcome",item)
    end
    local function defenseContext(s)
        return s.role=="DB" and (s.mode==nil or s.mode=="1v1") and not s.testing and s.alive~=false
    end
    local function observeDefenseThrow(s,data)
        if not enabled or not defenseContext(s) or not memoryOpponent
            or (s.phase~="Live" and s.phase~="Hike") then return end
        local arc=type(data.Arc)=="table" and data.Arc or s.arc
        local pass=(data.Pass=="Bullet" or data.Pass=="Floater") and data.Pass
            or (s.passType=="Bullet" or s.passType=="Floater") and s.passType or nil
        local launch=finite(data.LaunchAt) and data.LaunchAt or s.launchAt
        if type(arc)~="table"
            or typeof(arc.P0)~="Vector3" or typeof(arc.P1)~="Vector3"
            or not finite(arc.P0.X) or not finite(arc.P0.Y) or not finite(arc.P0.Z)
            or not finite(arc.P1.X) or not finite(arc.P1.Y) or not finite(arc.P1.Z)
            or not finite(arc.Flight) or arc.Flight<=0
            or not finite(arc.Apex) or arc.Apex<0 or not finite(launch) then return end
        if not pass then
            -- Native Throw packets can omit the pass label. Classify only an
            -- exact, unique match to the visible configured arc; unknown or
            -- ambiguous arcs must not change the defensive session rules.
            for _,name in ipairs({"Bullet","Floater"}) do
                local definition=type(Config.Pass)=="table" and Config.Pass[name]
                if type(definition)=="table" and finite(definition.Flight) and finite(definition.Apex)
                    and arc.Flight==definition.Flight and arc.Apex==definition.Apex then
                    if pass then return end
                    pass=name
                end
            end
            if not pass then return end
        end
        local root,opponent=rootOf(player.Character),rootOf(s.opponent)
        if not root or not opponent or not finite(root.Position.Z) or not finite(opponent.Position.Z) then return end
        local playKey=jobId..":"..tostring(launch)
        if activeDefense and activeDefense.playKey==playKey then return end
        for _,item in ipairs(recentDefense) do if item.playKey==playKey then return end end
        local offset=typeof(s.offset)=="Vector3" and s.offset or Vector3.zero
        local los=finite(s.LOS) and s.LOS or Field.LOSZ
        local remaining=(Field.GoalZ+offset.Z-arc.P1.Z)/Field.YD
        local depth=(arc.P1.Z-offset.Z-los)/Field.YD
        activeDefense=defenseDescriptor({pass=pass,launchAt=launch,playKey=playKey,
            roundKey=roundIdentity(s),
            depthAtThrow=(root.Position.Z-opponent.Position.Z)/Field.YD,
            targetDepthYards=depth,goalDistanceYards=remaining,
            deepEndzone=depth>=12 and remaining<=3 and arc.P1.Z<=Field.EndZ+offset.Z,
            time=world:GetServerTimeNow()})
    end
    local function recordDefense(result,opponentCaught)
        if not activeDefense then return end
        local item=defenseDescriptor(activeDefense);activeDefense=nil
        if not item then return end
        item.result=result;item.opponentCaught=opponentCaught==true;item.time=world:GetServerTimeNow()
        recentDefense[#recentDefense+1]=item
        while #recentDefense>6 do table.remove(recentDefense,1) end
        updateSessionHistory()
        local profile=defenseProfile()
        log("defenseOutcome",{pass=item.pass,result=result,opponentCaught=item.opponentCaught,
            deepEndzone=item.deepEndzone,depthAtThrow=item.depthAtThrow,targetDepthYards=item.targetDepthYards,
            goalDistanceYards=item.goalDistanceYards,depthBiasYards=profile.depthBiasYards,
            deepAttemptShadeYards=profile.deepAttemptShadeYards,recentDeepAttempts=profile.recentDeepAttempts,
            samples=profile.samples,playKey=item.playKey})
    end
    local function enemyCaught(s,catcher)
        if catcher==player or catcher==player.Character then return false end
        if catcher~=nil then
            if catcher==s.opponent then return true end
            local ok,character=pcall(function() return catcher.Character end)
            if ok and character~=nil and character==s.opponent then return true end
            return false
        end
        return s.enemyCarrier==true and s.carrier==s.opponent
    end
    local function inputFor(s,root)
        local opponent=rootOf(s.enemyCarrier and s.carrier or s.opponent)
        local choice=selected or activeRoute
        return {LOS=s.LOS,offset=s.offset or Vector3.zero,position=root.Position,velocity=root.AssemblyLinearVelocity,
            opponentPosition=opponent and opponent.Position,
            opponentVelocity=opponent and opponent.AssemblyLinearVelocity,
            stamina=tonumber(player:GetAttribute("Stamina")) or 0,
            sprintOn=player:GetAttribute("SprintOn")==true,
            role=s.role,phase=s.phase,mode=s.mode,ballActive=s.arc~=nil,passStarted=s.passStarted==true,
            carrierIsMe=s.carrier~=nil and s.carrier==player.Character,
            enemyCarrier=s.enemyCarrier==true,routePlan=routePlan,
            elapsed=s.snapAt and math.max(0,world:GetServerTimeNow()-s.snapAt) or nil,
            setupSeconds=math.max(0,(s.snapAt or s.preSnapEnds and (s.preSnapEnds+(Config.HikeTime or 3))
                or world:GetServerTimeNow())-world:GetServerTimeNow()),
            laneSide=laneSide,priorTarget=priorTarget,recentRoutes=recentRoutes,
            campingCounterUsed=campingCounterUsed,
            recentSelections=recentSelections,selectionIndex=selectionIndex,routeCycle=routeCycle,routeWaypoint=routeWaypoint,
            lastLateBendTrialTrigger=lastLateBendTrialTrigger,defenseProfile=defenseProfile(),
            middleStemDeep=choice and choice.middleStemDeep==true,
            slowStem=choice and choice.slowStem==true,slowStemTime=choice and choice.slowStemTime,
            routeStrategy=choice and choice.routeStrategy,postThrowStem=choice and choice.postThrowStem==true,
            stemSprintStart=choice and choice.stemSprintStart,estimatedCatchAt=choice and choice.estimatedCatchAt,
            earlyStemSprintSeconds=choice and choice.earlyStemSprintSeconds,
            stemRunSpeed=choice and choice.stemRunSpeed,
            finalSprintReserve=choice and choice.finalSprintReserve,
            estimatedStemRegeneration=choice and choice.estimatedStemRegeneration,
            stemRecoveryUntil=stemRecoveryUntil,stemRecoverySpent=stemRecoverySpent,
            allowPostThrowStem=s.allowPostThrowStem==true,gravity=world.Gravity,
            pacedSlant=choice and choice.pacedSlant==true,slantWalkUntil=choice and choice.slantWalkUntil,
            passType=s.passType,startX=selected and selected.payload.StartX,
            routeFamily=choice and choice.routeFamily,routeSide=choice and choice.side,
            finalSprintCommitted=finalSprintCommitted}
    end
    local function resetRound(key)
        local pending=activeRoute and activeRoute.roundKey==key and activeRoute or nil
        if not pending then campingObservation=nil end
        ownPossessionObserved=false
        roundKey=key;submitted=pending~=nil;nextSubmit=0;submitTries=0;observedSnapAt=nil
        observationStarted=world:GetServerTimeNow()
        hardCutIssued=false
        stemRecoveryUntil,stemRecoverySpent=0,0
        recoveryObservedAt,recoveryObservedSprint=nil,nil
        staminaObservedRound=nil
        activeRoute=pending
        if not pending then finalSprintCommitted=false end
        if not activeDefense or activeDefense.roundKey~=key then activeDefense=nil end
        routeWaypoint=2
        selected,routePlan,routeSource,planPass=nil,nil,nil,nil
        laneSide,priorTarget,lastKind=nil,nil,nil
        errorMessage=nil
    end
    local function setup()
        local s=ctx.snapshot()
        syncOpponent(s)
        observeStartStamina(s)
        if (s.phase=="RAC" or s.phase=="Run") and s.carrier==player.Character and s.carrier~=nil then
            ownPossessionObserved=true
        end
        if s.phase~=lastPhase then
            if s.phase=="PreSnap" then resetRound(roundIdentity(s)) end
            if s.phase=="Lobby" or s.phase=="Result" then
                laneSide,priorTarget,lastKind=nil,nil,nil
            end
            lastPhase=s.phase
        end
        if finite(s.snapAt) then observedSnapAt=s.snapAt end
        local paused=pauseReason(s)
        observeCamping(s,paused)
        if paused then message=paused;return end
        if s.phase=="Lobby" then message="Full auto · waiting for match";return end
        if s.phase=="Result" then message="Full auto · waiting for next round";return end
        if s.arc then message="Full auto · catch/intercept assist";return end
        if s.phase~="PreSnap" or s.role~="WR" then return end
        local key=roundIdentity(s)
        if key~=roundKey then resetRound(key) end
        if submitted then
            local choice=selected or activeRoute
            message=choice and choice.bestEffort and "Full auto · Floater best effort (no funded catch forecast)"
                or choice and choice.adaptiveUnderneath and "Full auto · Underneath: defender deep"
                or "Full auto · route submitted"
            return
        end
        local now=world:GetServerTimeNow()
        if submitTries>=3 or now<nextSubmit then return end
        -- Do not submit over an already closed/manual-submitted board.
        if not board.IsOpen() then message="Full auto · waiting for route board";return end
        local remaining=type(s.preSnapEnds)=="number" and s.preSnapEnds-now or math.huge
        local observation=1
        local defender=rootOf(s.opponent)
        if defender then
            local velocity=defender.AssemblyLinearVelocity
            local depth=defender.Position.Z-(s.offset and s.offset.Z or 0)-(s.LOS or Field.LOSZ)
            if velocity and velocity.Z>math.max(2,(Config.PreSnapDBSpeed or 12)*.5)
                and depth>=0 and depth<Policy.underneathTriggerYards()*Field.YD then observation=3 end
        end
        if now-(observationStarted or now)<observation and remaining>.5 then
            message="Full auto · reading defender position";return
        end
        local root=rootOf(player.Character)
        if not root then message="Full auto · waiting for character";return end
        submitTries=submitTries+1;nextSubmit=now+1
        local input=inputFor(s,root)
        local setupStamina=input.stamina
        input.stamina=Policy.setupStaminaBudget(setupStamina,Config,observedStartStamina)
        -- These automatic candidates are forecast without a release prefix.
        -- Equipped/owned releases remain available to the native manual menu;
        -- do not silently add their cost, motion or timing to this forecast.
        input.release=nil
        local solveStarted=os.clock()
        local chosen,reason=Policy.chooseScheduledRoute(input,Config,Field,RouteMath,Planner)
        local solveMs=(os.clock()-solveStarted)*1000
        if not chosen then
            local failure=tostring(reason or "No feasible cut route")
            if errorMessage~=failure then
                log("routeUnavailable",{reason=failure:sub(1,180),stamina=input.stamina,routeCycle=routeCycle})
            end
            errorMessage=failure
            message="Full auto · "..errorMessage
            return
        end
        assert(chosen.payload and chosen.plan,"Invalid route plan")
        -- Do not mutate the selected candidate or native manual payload.
        local payload=table.clone(chosen.payload)
        payload.Release=nil
        submit(payload)
        -- A failed selection or native submit must not spend the one session
        -- counter. Explicit OFF clears observations, not a completed attempt.
        if chosen.rareCampingBullet==true then campingCounterUsed=true end
        selected,routePlan=chosen,chosen.plan
        activeRoute=descriptor({pass=chosen.payload.Pass,side=chosen.side,depth=chosen.depth,
            shape=chosen.shape,family=chosen.family,signature=chosen.signature,
            routeFamily=chosen.routeFamily,cutDirection=chosen.cutDirection,scheduledFamily=chosen.scheduledFamily,
            scheduleOverride=chosen.scheduleOverride,anticipatedLane=chosen.anticipatedLane,stemBlocked=chosen.stemBlocked,
            scheduledPass=chosen.scheduledPass,passPreferenceOverride=chosen.passPreferenceOverride,
            preferAirborne=chosen.preferAirborne,preferJumpDive=chosen.preferJumpDive,requireAirborne=true,
            bestEffort=chosen.bestEffort,bestEffortReason=chosen.bestEffortReason,reachable=chosen.reachable,
            roundKey=roundKey,time=now,arrival=chosen.plan.Arrival,cutCount=chosen.cutCount,lastCutAt=chosen.lastCutAt,
            experimentalAttempt=chosen.experimentalAttempt,trialTrigger=chosen.trialTrigger,
            experimentalClearanceGap=chosen.experimentalClearanceGap,middleStemDeep=chosen.middleStemDeep,
            stemYards=chosen.stemYards,cutLeadTime=chosen.cutLeadTime,finishMode=chosen.finishMode,
            estimatedFinishAt=chosen.estimatedFinishAt,estimatedFinishZ=chosen.estimatedFinishZ,
            finishReachable=chosen.finishReachable,finishDistance=chosen.finishDistance,
            finishTravelTime=chosen.finishTravelTime,finishReserve=chosen.finishReserve,
            finishFraction=chosen.finishFraction,routeStrategy=chosen.routeStrategy,
            slowStem=chosen.slowStem,slowStemTime=chosen.slowStemTime,cutAt=chosen.cutAt,
            slowStemStartupSlack=chosen.slowStemStartupSlack,
            startSprintAt=chosen.startSprintAt,forceDiveFinish=chosen.forceDiveFinish,
            requireDive=chosen.requireDive,finalSprint=chosen.finalSprint,slowStemSpeed=chosen.slowStemSpeed,
            finalSprintDuration=chosen.finalSprintDuration,finalSprintReserve=chosen.finalSprintReserve,
            finalSprintStamina=chosen.finalSprintStamina,sidelineInset=chosen.sidelineInset,
            adaptiveUnderneath=chosen.adaptiveUnderneath,observedDefenderDepthYards=chosen.observedDefenderDepthYards,
            underneathDepthLimit=chosen.underneathDepthLimit,carryReserve=chosen.carryReserve,carryMoveReady=chosen.carryMoveReady,
            estimatedCatchStamina=chosen.estimatedCatchStamina,
            estimatedCatchAt=chosen.estimatedCatchAt,estimatedContactMargin=chosen.estimatedContactMargin,
            estimatedCatchZ=chosen.estimatedCatchZ,estimatedFirstTouchAt=chosen.estimatedFirstTouchAt,
            estimatedStopAt=chosen.estimatedStopAt,
            stemSprintSeconds=chosen.stemSprintSeconds,stemSprintStart=chosen.stemSprintStart,
            earlyStemSprintSeconds=chosen.earlyStemSprintSeconds,
            stemRunSpeed=chosen.stemRunSpeed,estimatedStemRegeneration=chosen.estimatedStemRegeneration,
            ballTargetZ=chosen.ballTargetZ,shortField=chosen.shortField,
            stemTravelDistance=chosen.stemTravelDistance,postThrowStem=chosen.postThrowStem,
            stemDetour=chosen.stemDetour,forecastCount=chosen.forecastCount,
            cutAngle=chosen.cutAngle,estimatedCatchInsideGoal=chosen.estimatedCatchInsideGoal,rareBullet=chosen.rareBullet,
            rareCampingBullet=chosen.rareCampingBullet,continuousBulletCatch=chosen.continuousBulletCatch,
            carryMoveReserve=chosen.carryMoveReserve,
            campingGateReason=chosen.campingGateReason,campingEvidenceCount=chosen.campingEvidenceCount,
            campingCurrentKnown=chosen.campingCurrentKnown,campingCurrentWaiting=chosen.campingCurrentWaiting,
            campingCounterUsed=campingCounterUsed,
            pacedSlant=chosen.pacedSlant,slantWalkUntil=chosen.slantWalkUntil,slantSprintDuration=chosen.slantSprintDuration,
            sidelineFallback=chosen.sidelineFallback,sidelineFallbackReason=chosen.sidelineFallbackReason,
            diveWitnessElapsed=chosen.diveWitnessElapsed,diveWitnessX=chosen.diveWitnessX,
            diveWitnessZ=chosen.diveWitnessZ,diveWitnessMargin=chosen.diveWitnessMargin})
        if chosen.trialTrigger then lastLateBendTrialTrigger=chosen.trialTrigger end
        routeWaypoint=2
        recentSelections[#recentSelections+1]=descriptor(activeRoute)
        while #recentSelections>6 do table.remove(recentSelections,1) end
        selectionIndex=selectionIndex+1
        routeCycle=(routeCycle+1)%20
        savePreferences()
        updateSessionHistory()
        submitted=true;counters.routeRequests=counters.routeRequests+1
        -- Same close operation used when the normal route menu finishes.
        local closed,closeError=pcall(board.Close)
        errorMessage=not closed and tostring(closeError) or nil
        message=chosen.bestEffort and "Full auto · Floater best effort (no funded catch forecast)"
            or chosen.adaptiveUnderneath and "Full auto · Underneath: defender deep"
            or "Full auto · "..chosen.payload.Pass.." route submitted"
        log("routeRequested",{pass=chosen.payload.Pass,startX=chosen.payload.StartX,
            campingGateReason=chosen.campingGateReason,campingEvidenceCount=chosen.campingEvidenceCount,
            campingCurrentKnown=chosen.campingCurrentKnown,campingCurrentWaiting=chosen.campingCurrentWaiting,
            campingCounterUsed=campingCounterUsed,
            points=#chosen.payload.Points,arrival=chosen.plan.Arrival,launch=chosen.plan.Launch,
            estimatedSeparation=chosen.estimatedSeparation,estimateOnly=true,
            bestEffort=chosen.bestEffort,bestEffortReason=chosen.bestEffortReason,reachable=chosen.reachable,
            cutAngle=chosen.cutAngle,estimatedCatchInsideGoal=chosen.estimatedCatchInsideGoal,
            postThrowStem=chosen.postThrowStem,forecastCount=chosen.forecastCount,solveMs=solveMs,
            earlyStemSprintSeconds=chosen.earlyStemSprintSeconds,stemSprintSeconds=chosen.stemSprintSeconds,
            stemSprintStart=chosen.stemSprintStart,
            stemRunSpeed=chosen.stemRunSpeed,estimatedStemRegeneration=chosen.estimatedStemRegeneration,
            ballTargetZ=chosen.ballTargetZ,shortField=chosen.shortField,
            estimatedFirstTouchAt=chosen.estimatedFirstTouchAt,estimatedStopAt=chosen.estimatedStopAt,
            shape=chosen.shape,depth=chosen.depth,family=chosen.family,signature=chosen.signature,
            adaptationPenalty=chosen.adaptationPenalty,recentFailureCount=chosen.recentFailureCount,
            repeatPenalty=chosen.repeatPenalty,mixBonus=chosen.mixBonus,baseScore=chosen.baseScore,
            selectionScore=chosen.selectionScore,qualityGap=chosen.qualityGap,selectionIndex=selectionIndex,
            cutCount=chosen.cutCount,lastCutAt=chosen.lastCutAt,cutBonus=chosen.cutBonus,
            experimentalAttempt=chosen.experimentalAttempt,trialTrigger=chosen.trialTrigger,
            experimentalClearanceGap=chosen.experimentalClearanceGap,
            middleStemDeep=chosen.middleStemDeep,stemYards=chosen.stemYards,cutLeadTime=chosen.cutLeadTime,
            finishMode=chosen.finishMode,estimatedFinishAt=chosen.estimatedFinishAt,
            estimatedFinishZ=chosen.estimatedFinishZ,finishReachable=chosen.finishReachable,
            finishDistance=chosen.finishDistance,finishTravelTime=chosen.finishTravelTime,
            finishReserve=chosen.finishReserve,finishFraction=chosen.finishFraction,routeStrategy=chosen.routeStrategy,
            slowStem=chosen.slowStem,slowStemTime=chosen.slowStemTime,cutAt=chosen.cutAt,
            slowStemStartupSlack=chosen.slowStemStartupSlack,
            startSprintAt=chosen.startSprintAt,requireDive=chosen.requireDive,
            slowStemSpeed=chosen.slowStemSpeed,finalSprintDuration=chosen.finalSprintDuration,
            finalSprintReserve=chosen.finalSprintReserve,finalSprintStamina=chosen.finalSprintStamina,
            adaptiveUnderneath=chosen.adaptiveUnderneath,observedDefenderDepthYards=chosen.observedDefenderDepthYards,
            underneathDepthLimit=chosen.underneathDepthLimit,carryReserve=chosen.carryReserve,carryMoveReady=chosen.carryMoveReady,
            sidelineInset=chosen.sidelineInset,sidelineFallback=chosen.sidelineFallback,
            sidelineFallbackReason=chosen.sidelineFallbackReason,
            diveWitnessElapsed=chosen.diveWitnessElapsed,diveWitnessX=chosen.diveWitnessX,
            diveWitnessZ=chosen.diveWitnessZ,diveWitnessMargin=chosen.diveWitnessMargin,
            hikeTime=chosen.hikeTime,setupDefenderReach=chosen.setupDefenderReach,
            estimatedCatchZ=chosen.estimatedCatchZ,estimatedCatchAt=chosen.estimatedCatchAt,
            estimatedRACDistance=chosen.estimatedRACDistance,estimatedCatchStamina=chosen.estimatedCatchStamina,
            pacedSlant=chosen.pacedSlant,slantWalkUntil=chosen.slantWalkUntil,slantSprintDuration=chosen.slantSprintDuration,
            uprightCatchReachable=chosen.uprightCatchReachable,
            nearGoalFloaterAvailable=chosen.nearGoalFloaterAvailable,
            insideGoalFloaterAvailable=chosen.insideGoalFloaterAvailable,
            goalCatchPreference=chosen.goalCatchPreference,goalReferenceScore=chosen.goalReferenceScore,
            goalClearanceToleranceUsed=chosen.goalClearanceToleranceUsed,
            pressureMode=chosen.pressureMode,eligibleRouteCount=chosen.eligibleRouteCount,
            defenderEnvelopeMargin=chosen.defenderEnvelopeMargin,
            bestDefenderEnvelopeMargin=chosen.bestDefenderEnvelopeMargin,
            position=coordinates(input.position),opponentPosition=coordinates(input.opponentPosition),
            opponentVelocity=coordinates(input.opponentVelocity),offset=coordinates(input.offset),
            LOS=input.LOS,stamina=input.stamina,setupStamina=setupStamina,
            planningStamina=input.stamina,observedStartStamina=observedStartStamina,
            setupAllowanceFraction=.25,empiricalSetupAllowance=true})
    end
    local accumulator=0
    local connection=run.Heartbeat:Connect(function(dt)
        accumulator=accumulator+dt
        if accumulator<.15 then return end
        accumulator=0
        local ok,err=pcall(setup)
        if not ok then errorMessage=tostring(err);message="Full auto · "..errorMessage end
    end)
    local function navigate(s,root,h,now,dt)
        if pauseReason(s) or not root or not h or h.PlatformStand then return nil end
        if s.role=="WR" and (s.phase=="PreSnap" or s.phase=="Hike") and (tonumber(h.WalkSpeed) or 0)<=0 then return nil end
        if finite(s.snapAt) then observedSnapAt=s.snapAt end
        observeStartStamina(s)
        if s.route and #s.route>=2 and (routeSource~=s.route or planPass~=s.passType) then
            if routeSource~=nil then routeWaypoint=2 end
            routePlan=RouteMath.Plan(s.route,s.passType or selected and selected.payload.Pass or "Bullet")
            routeSource,planPass=s.route,s.passType
        end
        local input=inputFor(s,root);input.dt=dt
        input.currentWalkSpeed=tonumber(h.WalkSpeed)
        accountStemRecovery(input)
        if input.role=="WR" and input.carrierIsMe
            and (input.phase=="RAC" or input.phase=="Run") and lastKind~="carry" then
            -- Catch steering may finish far from the pre-throw route target.
            -- Start carry smoothing at the actual catch position, then retain
            -- only the subsequent carry targets and chosen escape side.
            input.priorTarget=root.Position
            input.laneSide=nil
        end
        local choice=Policy.movement(input,Config,Field,RouteMath)
        if not choice then return nil end
        if choice.routeWaypoint then routeWaypoint=choice.routeWaypoint end
        if choice.finalSprintCommitted==true then finalSprintCommitted=true end
        if finite(choice.stemRecoveryUntil) and finite(choice.stemRecoverySeconds) then
            stemRecoveryUntil=choice.stemRecoveryUntil
            recoveryObservedAt=input.elapsed
            recoveryObservedSprint=input.sprintOn==true and finite(input.currentWalkSpeed)
                and input.currentWalkSpeed>Config.RunSpeed+.05
        end
        local hardCut=choice.finalSprintCommitted==true
            and (input.routeStrategy=="deep_middle_floater" or input.routeStrategy=="deep_middle_bullet")
            and not hardCutIssued
        if hardCut then hardCutIssued=true end
        laneSide,priorTarget=choice.laneSide,choice.target
        local delta=(choice.target-root.Position)*Vector3.new(1,0,1)
        local distance=delta.Magnitude
        local moving=distance>(choice.stopDistance or .8)
        local direction=moving and delta.Unit or Vector3.zero
        if moving then
            -- Native movement only; taper close to a target at low frame rates.
            direction=direction*math.min(1,distance/math.max(1,h.WalkSpeed*math.max(dt,.016)))
            if type(choice.moveSpeed)=="number" then
                -- Account for native sprint on/off replication delay without
                -- changing WalkSpeed or moving faster than the current speed.
                direction=direction*math.min(1,math.max(0,choice.moveSpeed)/math.max(1,h.WalkSpeed))
            elseif type(choice.moveScale)=="number" then
                direction=direction*math.max(0,math.min(1,choice.moveScale))
            end
        end
        local routeChoice=selected or activeRoute
        message=choice.kind=="route" and routeChoice and routeChoice.bestEffort
            and "Full auto · Floater best effort (no funded catch forecast)"
            or choice.kind=="route" and routeChoice and routeChoice.adaptiveUnderneath
                and "Full auto · Underneath: defender deep" or "Full auto · "..choice.kind
        local sampleInterval=.2
        if lastKind~=choice.kind or choice.routeWaypoint~=lastLoggedWaypoint or now-lastSample>=sampleInterval then
            lastKind,lastSample=choice.kind,now
            lastLoggedWaypoint=choice.routeWaypoint
            local opponent,velocity=input.opponentPosition,input.opponentVelocity
            local localVelocity=root.AssemblyLinearVelocity
            log("navigate",{action=choice.kind,phase=s.phase,role=s.role,elapsed=input.elapsed,
                x=root.Position.X,z=root.Position.Z,targetX=choice.target.X,targetZ=choice.target.Z,
                velocityX=localVelocity and localVelocity.X,velocityZ=localVelocity and localVelocity.Z,
                directionX=direction.X,directionZ=direction.Z,
                sprintOn=input.sprintOn,requestedSprint=moving and choice.sprint==true,
                opponentX=opponent and opponent.X,opponentZ=opponent and opponent.Z,
                opponentVelocityX=velocity and velocity.X,opponentVelocityZ=velocity and velocity.Z,
                opponentDistance=opponent and ((opponent-root.Position)*Vector3.new(1,0,1)).Magnitude,
                stamina=input.stamina,laneSide=laneSide,speed=h.WalkSpeed,moving=moving,
                routeWaypoint=choice.routeWaypoint,defenseDepthBiasYards=input.defenseProfile.depthBiasYards,
                defenseAttemptShadeYards=input.defenseProfile.deepAttemptShadeYards,
                defenseSamples=input.defenseProfile.samples,routeMoveSpeed=choice.moveSpeed,
                routeDeadline=choice.routeDeadline,finalSprintCommitted=finalSprintCommitted,
                routeScheduleCapacity=choice.routeScheduleCapacity,stemRecoveryUntil=stemRecoveryUntil,
                stemRecoverySpent=stemRecoverySpent,
                routeTimingDebt=choice.routeTimingDebt,routeTimingReason=choice.routeTimingReason})
        end
        local avoidanceArrival
        if input.role=="WR" and choice.kind=="route" and finite(choice.routeDeadline) and finite(input.elapsed) then
            avoidanceArrival={targetPosition=choice.target,arriveBy=now+choice.routeDeadline-input.elapsed}
            -- Retaining a scheduled sprint around a body must belong to a
            -- funded route in this exact live round, not a stale deadline.
            if submitted and activeRoute and activeRoute.reachable==true and not activeRoute.bestEffort
                and activeRoute.roundKey==roundIdentity(s) and s.phase=="Live"
                and not s.arc and not s.passStarted and finite(s.snapAt) then
                avoidanceArrival.routeRoundKey=activeRoute.roundKey
                avoidanceArrival.snapAt=s.snapAt
            end
        end
        return {direction=direction,sprint=moving and choice.sprint==true,message=message,
            hardCut=hardCut,
            avoidanceArrival=avoidanceArrival,
            preserveDepth=choice.kind=="shadow"}
    end
    function api.navigate(s,root,h,now,dt)
        local ok,result=pcall(navigate,s,root,h,now,dt)
        if not ok then
            navigationError=tostring(result)
            errorMessage=navigationError
            message="Full auto navigation paused"
            return nil
        end
        if navigationError then
            if errorMessage==navigationError then errorMessage=nil end
            navigationError=nil
        end
        return result
    end
    function api.setEnabled(value)
        enabled=value==true
        errorMessage=nil
        laneSide,priorTarget,lastKind=nil,nil,nil
        if not enabled then finalSprintCommitted=false;clearCampingEvidence() end
        if not enabled and ctx.release then ctx.release() end
        message=enabled and "Full auto · ready" or "Full auto off"
        savePreferences()
        log("enabled",{enabled=enabled})
        return true,saveError
    end
    function api.onMatch(data)
        if not alive or type(data)~="table" then return end
        local s=ctx.snapshot();syncOpponent(s)
        if (data.Phase=="RAC" or data.Phase=="Run")
            and (data.Carrier==player or data.Carrier==player.Character and data.Carrier~=nil
                or s.carrier==player.Character and s.carrier~=nil) then ownPossessionObserved=true end
        if finite(s.snapAt) then observedSnapAt=s.snapAt end
        if defenseContext(s) then
            if data.Phase=="Result" and data.Result=="Touchdown"
                and (data.Point=="Opp" or data.Point=="Them" or data.ScorerIsYou==false) then
                recordDefense("Touchdown",true)
            elseif data.Phase=="Result" and (data.Result=="Swatted" or data.Result=="Intercepted"
                or data.Result=="Incomplete") then recordDefense(data.Result,false)
            elseif (data.Phase=="RAC" or data.Phase=="Run") and enemyCaught(s,data.Carrier) then
                recordDefense("Catch",true)
            end
        end
        if data.Phase=="PreSnap" or data.Phase=="Pick" or data.Phase=="Lobby" then activeDefense=nil end
        if activeRoute and s.role=="WR" and data.Phase=="Result" then
            -- Fallback when the server's terminal round packet arrives without
            -- the matching BallResult. A later duplicate cannot add twice.
            if data.Result=="Swatted" or data.Result=="Intercepted" or data.Result=="Incomplete" then
                recordOutcome(data.Result,false)
            elseif data.Result=="Touchdown" and (data.Point=="You" or data.ScorerIsYou==true) then
                recordOutcome("Catch",true)
            end
        end
        if s.role=="WR" and (s.mode==nil or s.mode=="1v1") and not s.testing and data.Phase=="Result"
            and data.Result=="Tackled" then
            local key=tostring(s.roundKey or s.preSnapEnds or roundKey or "current")
            -- An adaptive underneath/slant catch may deliberately advance the
            -- next down. Keep that progress separate from a lost point; a
            -- later duplicate without Point must never erase a confirmed loss.
            if activeRoute and activeRoute.roundKey==key then recordOutcome("Catch",true) end
            for i=#recentRoutes,1,-1 do
                local item=recentRoutes[i]
                if item.roundKey==key and (item.catchSuccess==true or item.result=="Catch" and item.success) then
                    local pointLost=item.terminalPointLost==true or data.Point=="Opp"
                        or data.Point=="Them" or data.ScorerIsYou==false
                    local progress=(item.adaptiveUnderneath==true or item.pacedSlant==true) and not pointLost
                    if item.terminalResult~="Tackled" or item.success~=progress
                        or item.terminalPointLost~=pointLost then
                        item.catchSuccess=true;item.success=progress;item.terminalPointLost=pointLost
                        item.terminalResult="Tackled";item.terminalAt=world:GetServerTimeNow()
                        updateSessionHistory()
                        log("routeOutcomeUpdated",descriptor(item))
                    end
                    break
                end
            end
        end
        if data.Phase=="Hike" then counters.rounds=counters.rounds+1 end
        if enabled and data.Phase=="Result" then
            if data.Point=="You" or data.ScorerIsYou==true then counters.pointsWon=counters.pointsWon+1
            elseif data.Point=="Them" or data.Point=="Opp" or data.ScorerIsYou==false then counters.pointsLost=counters.pointsLost+1 end
        end
        if enabled and (data.Phase=="Result" or data.MatchOver==true) then
            -- Keep supplied native scores; missing scores remain absent. A
            -- point, animation or requested action never invents a match win.
            log("result",{result=data.Result,point=data.Point,matchOver=data.MatchOver,
                scorerIsYou=data.ScorerIsYou,phase=data.Phase,role=s.role,mode=s.mode,
                you=finite(data.You) and data.You or nil,
                them=finite(data.Them) and data.Them or nil,
                toWin=finite(data.ToWin) and data.ToWin or nil,
                round=finite(data.Round) and data.Round or nil,
                down=finite(data.Down) and data.Down or nil})
        end
    end
    function api.onFx(data)
        if not alive or type(data)~="table" then return end
        local eventType=data.Type
        if eventType=="Jammed" or eventType=="Blocked" or eventType=="JamHit" or eventType=="JamWhiff" then
            local s=ctx.snapshot()
            local now=world:GetServerTimeNow()
            if s.testing or not finite(now) then return end
            local last=contactFxTimes[eventType]
            if last and now>=last and now-last<.1 then return end
            contactFxTimes[eventType]=now
            local character=player.Character
            local root=rootOf(character)
            local h=character and character:FindFirstChildOfClass("Humanoid")
            local point=root and root.Position
            local speed=h and h.WalkSpeed
            local stamina=tonumber(player:GetAttribute("Stamina"))
            -- These are recipient-local native notifications. Jammed/Blocked
            -- concern this client; JamHit/Whiff do not identify a local victim.
            -- Never copy packet fields, actors, identities or native payloads.
            local roles={WR=true,DB=true,QB=true,TWR=true,TDB=true,TQB=true,RUSH=true,D=true}
            local phases={Lobby=true,PreSnap=true,Pick=true,Hike=true,Live=true,RAC=true,Run=true,Result=true}
            log("nativeContactFx",{eventType=eventType,isLocalVictim=eventType=="Jammed" or eventType=="Blocked",
                role=roles[s.role] and s.role or nil,phase=phases[s.phase] and s.phase or nil,
                position=typeof(point)=="Vector3" and finite(point.X) and finite(point.Y) and finite(point.Z)
                    and coordinates(point) or nil,
                speed=finite(speed) and speed or nil,stamina=finite(stamina) and stamina or nil})
            return
        end
        if eventType~="BallResult" and eventType~="Throw" then return end
        local s=ctx.snapshot();syncOpponent(s)
        if data.Type=="Throw" then
            if activeRoute and s.role=="WR" then freezeCampingObservation() end
            observeDefenseThrow(s,data);return
        end
        if defenseContext(s) then
            if data.Result=="Catch" and enemyCaught(s,data.Catcher) then recordDefense("Catch",true)
            elseif data.Result=="Swatted" or data.Result=="Intercepted" or data.Result=="Incomplete" then
                recordDefense(data.Result,false)
            end
        end
        if not activeRoute or s.role~="WR" or s.mode=="Team" or s.testing then return end
        local result=data.Result
        if result=="Catch" then
            local mine=data.Catcher==player or data.Catcher==player.Character
                or data.Catcher==nil and s.carrier==player.Character
            if mine then recordOutcome(result,true)
            elseif enemyCaught(s,data.Catcher) then recordOutcome(result,false) end
        elseif result=="Swatted" or result=="Intercepted" or result=="Incomplete" then
            recordOutcome(result,false)
        end
    end
    function api.status()
        local snapshot=ctx.snapshot()
        syncOpponent(snapshot)
        local startX=selected and selected.payload.StartX
        local root=rootOf(player.Character)
        local offset=typeof(snapshot.offset)=="Vector3" and snapshot.offset or Vector3.zero
        local startObserved=startX and root and (snapshot.phase=="PreSnap" or snapshot.phase=="Hike")
            and math.abs(root.Position.X-offset.X-startX)<=Field.YD*.5 or false
        return {enabled=enabled,message=message,error=errorMessage,saveError=saveError,
            supportedMode="1v1",policyMode="deterministic",routeCycle=routeCycle,submitted=submitted,
            pass=selected and selected.payload.Pass or nil,startX=startX,startPositionObserved=startObserved,
            counters=table.clone(counters),
            sessionHistory=sessionRecord(),
            defenseProfile=defenseProfile(),activeDefense=defenseDescriptor(activeDefense),
            finalSprintCommitted=finalSprintCommitted,
            observedStartStamina=observedStartStamina,setupAllowanceFraction=.25,
            stemRecoverySpent=stemRecoverySpent,stemRecoveryUntil=stemRecoveryUntil,
            routeWaypoint=routeWaypoint,routeRoundKey=roundIdentity(ctx.snapshot()),
            activeRoute=descriptor(activeRoute)}
    end
    function api.catchIntent()
        -- Core context calls this; never recurse through ctx.snapshot/status.
        local choice=selected or activeRoute
        if not alive or not enabled or not submitted or not activeRoute or not choice then return nil end
        if finite(observedSnapAt) and choice.slowStem==true and finite(choice.slowStemTime)
            and world:GetServerTimeNow()>=observedSnapAt+choice.slowStemTime then
            finalSprintCommitted=true
        end
        local point=routePlan and type(routePlan.Points)=="table" and routePlan.Points[routeWaypoint]
        if typeof(point)~="Vector2" or not finite(point.X) or not finite(point.Y) then point=nil end
        local stage
        local cut=routePlan and routePlan.Points and routePlan.Points[2]
        if (choice.routeStrategy=="deep_middle_floater" or choice.routeStrategy=="deep_middle_bullet") and choice.postThrowStem==true
            and not finalSprintCommitted and finite(observedSnapAt) and finite(choice.cutAt)
            and finite(choice.stemSprintStart) and finite(choice.estimatedCatchAt)
            and typeof(cut)=="Vector2" and world:GetServerTimeNow()<observedSnapAt+choice.cutAt then
            stage={point=cut,untilAt=observedSnapAt+choice.cutAt,
                sprintStartAt=observedSnapAt+choice.stemSprintStart,
                contactAt=observedSnapAt+choice.estimatedCatchAt,reserve=10,
                sprintDrain=Config.SprintDrain or 25,finalSprintSeconds=choice.finalSprintDuration,
                plannedStemSprintSeconds=choice.stemSprintSeconds}
            stage.stemRunSpeed=choice.stemRunSpeed
            if stemRecoveryUntil>world:GetServerTimeNow()-observedSnapAt then
                stage.recoveryUntilAt=observedSnapAt+stemRecoveryUntil
            end
        end
        return {deepFinish=choice.middleStemDeep==true,side=choice.side,waypoint=point,goalZ=Field.GoalZ,endZ=Field.EndZ,
            routeStrategy=choice.routeStrategy,
            postThrowStem=stage,
            pass=selected and selected.payload.Pass or activeRoute.pass,
            continuousBulletCatch=choice.rareCampingBullet==true and choice.continuousBulletCatch==true
                and (selected and selected.payload.Pass or activeRoute.pass)=="Bullet",
            requireAirborne=true,requireDive=choice.requireDive==true,preferAirborne=true,
            preferJumpDive=choice.preferJumpDive==true,
            continuousSprint=finalSprintCommitted,finalSprint=finalSprintCommitted}
    end
    function api.movementBudget(committedPursuit)
        if not alive or not enabled then return nil end
        -- Called while the core builds its snapshot: never recurse into it.
        -- A rare short Bullet reserves one actual native carrier move until
        -- confirmed possession; normal carrier decisions may then spend it.
        local choice=selected or activeRoute
        local reserve=10
        if activeRoute and not ownPossessionObserved and choice and choice.rareCampingBullet==true
            and (selected and selected.payload.Pass or activeRoute.pass)=="Bullet"
            and finite(choice.carryReserve) and choice.carryReserve>=10
            and choice.carryReserve<=(Config.Stamina or 100) then reserve=choice.carryReserve end
        return {dbReserve=committedPursuit==true and 2 or 40,wrReserve=reserve}
    end
    function api.unload()
        if not alive then return end
        clearCampingEvidence()
        alive=false;connection:Disconnect()
        if ctx.release then ctx.release() end
    end
    return api
end
