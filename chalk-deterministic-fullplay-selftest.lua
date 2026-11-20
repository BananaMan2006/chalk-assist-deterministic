-- Supplied RouteMath source, with explicit numeric geometry and service fixtures.
-- No Roblox physics, network outcome, GUI input, or opponent behavior is simulated.
return function(Policy,create,routeSource,Planner)
    local report={total=0,passed=0,failed=0,results={}}
    local oldVector2,oldTypeof=Vector2,typeof
    local M,V={},{}
    local function vec(x,y) return setmetatable({X=x,Y=y},M) end
    function V.Dot(a,b) return a.X*b.X+a.Y*b.Y end
    function V.Lerp(a,b,t) return a+(b-a)*t end
    M.__index=function(a,k)
        if k=="Magnitude" then return math.sqrt(a.X*a.X+a.Y*a.Y) end
        if k=="Unit" then return a/a.Magnitude end
        return V[k]
    end
    M.__add=function(a,b) return vec(a.X+b.X,a.Y+b.Y) end
    M.__sub=function(a,b) return vec(a.X-b.X,a.Y-b.Y) end
    M.__mul=function(a,b) return type(a)=="number" and vec(a*b.X,a*b.Y) or vec(a.X*b,a.Y*b) end
    M.__div=function(a,b) return vec(a.X/b,a.Y/b) end
    Vector2={new=vec,zero=vec(0,0)}
    typeof=function(value) return getmetatable(value)==M and "Vector2" or oldTypeof(value) end
    local Config={RunSpeed=20,SprintSpeed=27,Stamina=100,SprintDrain=25,StaminaRegen=18,RegenDelay=.8,HikeTime=3,PreSnapDBSpeed=12,
        MinPointGapYards=.5,SidelineMarginYards=2,RouteEdgeMargin=1,BehindLOSYards=3,
        MaxInkYards=30,MaxPoints=200,DefaultGoYards=25,SimplifyTolerance=.6,
        CornerMinAngle=45,CornerMaxAngle=135,CornerMaxPenalty=.25,
        FillSpeed=24,MinLaunch=.4,ReleaseHeight=6,CatchHeight=3.5,QBBackYards=7,
        HandUpOffset=3.5,JumpHeight=6,CatchRadius=3.75,
        Moves={Dive={Yards=3,Time=.35},Juke={Cost=20}},
        Pass={Bullet={Flight=1.05,Apex=6},Floater={Flight=3.1,Apex=42,Lead=4}},
        ReleaseDefs={LegalRelease={}}}
    local Field={MinX=-49,MaxX=49,MidX=0,BackZ=-25,LOSZ=15,GoalZ=140,EndZ=170,YD=5,TurfY=0}
    local env=setmetatable({script={Parent={Config="config",Field="field"}},
        require=function(module)
            assert(module=="config" or module=="field","unexpected native module dependency")
            return module=="config" and Config or Field
        end},{__index=_G})
    local RouteMath=assert(load(routeSource,"native RouteMath","t",env))()
    local function test(name,body)
        report.total=report.total+1
        local ok,reason=pcall(body)
        report[ok and "passed" or "failed"]=report[ok and "passed" or "failed"]+1
        report.results[#report.results+1]={name=name,passed=ok,error=not ok and tostring(reason) or nil}
    end
    local function copy(value)
        if type(value)~="table" then return value end
        local result={};for key,item in pairs(value) do result[key]=copy(item) end
        return result
    end
    local function harness(options)
        options=options or {}
        local f={time=0,submits={},writes={},reads={},events={},listeners={},attrs={Stamina=100},
            boardOpen=true,assist=true,accountId=123,releases=0}
        f.root={Position=Vector3.new(0,3,15),AssemblyLinearVelocity=Vector3.zero}
        f.opponentRoot={Position=Vector3.new(3,3,25),AssemblyLinearVelocity=Vector3.zero}
        f.character={Name="authored-self",FindFirstChild=function(_,key) return key=="HumanoidRootPart" and f.root or nil end}
        f.opponent={Name="authored-opponent",FindFirstChild=function(_,key) return key=="HumanoidRootPart" and f.opponentRoot or nil end}
        f.player={Character=f.character,GetAttribute=function(_,key) return f.attrs[key] end}
        f.humanoid={WalkSpeed=20,PlatformStand=false}
        f.character.FindFirstChildOfClass=function(_,key) return key=="Humanoid" and f.humanoid or nil end
        f.snapshot={enabled=true,mode="1v1",phase="PreSnap",role="WR",LOS=15,offset=Vector3.zero,
            opponent=f.opponent,preSnapEnds=15,roundKey="authored-round-1"}
        f.gui={MenuIsOpen=false}
        local heartbeat={Connect=function(_,callback)
            local c={callback=callback,connected=true,Disconnect=function(self) self.connected=false end}
            f.listeners[#f.listeners+1]=c;return c
        end}
        local http={JSONEncode=function(_,value)
            if value.kind then f.events[#f.events+1]=copy(value);return "authored-event" end
            return copy(value)
        end,JSONDecode=function(_,value) return copy(value) end}
        local function forbidden() error("model/network/RNG service must never be invoked") end
        f.services={player=f.player,world={GetServerTimeNow=function() return f.time end},rs={},jobId="authored-server",
            Config=Config,Field=Field,RouteMath=RouteMath,Planner=Planner,http=http,guiService=f.gui,
            uis={GetFocusedTextBox=function() return f.focused end},runService={Heartbeat=heartbeat},
            players={GetPlayerFromCharacter=function() return {UserId=f.accountId} end},
            board={IsOpen=function() return f.boardOpen end,Close=function() f.boardOpen=false end},
            submit=function(payload)
                if f.submitError then error(f.submitError) end
                f.submits[#f.submits+1]=payload
            end,
            read=function(path)
                f.reads[#f.reads+1]=path
                assert(path=="ciu_deterministic_fullplay_v1.json","read old settings or journal")
                if options.saved==nil then error("new product file missing") end
                return options.saved
            end,
            write=function(path,value)
                if f.writeError then error(f.writeError) end
                f.writes[#f.writes+1]={path=path,value=copy(value)}
            end,append=function(path) assert(path=="ciu_deterministic_events.jsonl") end,
            createLearning=forbidden,uniform=forbidden,createJam=forbidden,
            Generator={propose=forbidden},MovementExploration={candidates=forbidden}}
        f.api=create({snapshot=function() return f.snapshot end,previousState=options.previousState,
            version=options.version,buildId=options.buildId,
            assistEnabled=function() return f.assist end,release=function() f.releases=f.releases+1 end},Policy,f.services)
        function f:tick(dt)
            self.time=self.time+(dt or .2)
            for _,c in ipairs(self.listeners) do if c.connected then c.callback(dt or .2) end end
        end
        function f:settle() for _=1,8 do self:tick() end end
        function f:navigate() return self.api.navigate(self.snapshot,self.root,self.humanoid,self.time,.05) end
        function f:newRound(index)
            self.snapshot.phase="Result";self:tick()
            self.snapshot.phase="PreSnap";self.snapshot.preSnapEnds=self.time+15
            self.snapshot.roundKey="authored-round-"..tostring(index);self.boardOpen=true;self:settle()
        end
        return f
    end
    local function sameRoute(a,b)
        assert(a.Pass==b.Pass and a.StartX==b.StartX and #a.Points==#b.Points)
        for i,point in ipairs(a.Points) do assert(point.X==b.Points[i].X and point.Y==b.Points[i].Y) end
    end
    test("logs carry injected release identity and exact native final scores",function()
        local f=harness({version="5.1.1",buildId=string.rep("a",64)})
        f.api.setEnabled(true)
        f.api.onMatch({Phase="Result",Result="Touchdown",Point="Them",MatchOver=true,
            ScorerIsYou=false,You=0,Them=4,ToWin=4,Round=6,Down=1})
        local event=f.events[#f.events]
        assert(event.kind=="result" and event.version=="5.1.1" and event.buildId==string.rep("a",64))
        assert(event.fullAuto==true and event.matchOver==true and event.scorerIsYou==false)
        assert(event.you==0 and event.them==4 and event.toWin==4 and event.round==6 and event.down==1)
        assert(event.won==nil and event.winner==nil)
    end)
    test("terminal lobby packet preserves unknown scores without inferring a winner",function()
        local f=harness();f.api.setEnabled(true)
        f.api.onMatch({Phase="Lobby",MatchOver=true,Point="You",You=0/0,Them=math.huge})
        local event=f.events[#f.events]
        assert(event.kind=="result" and event.phase=="Lobby" and event.matchOver==true)
        assert(event.you==nil and event.them==nil and event.toWin==nil)
        assert(event.won==nil and event.winner==nil and event.version=="unversioned")
    end)
    test("native contact notices log only local observations without enabling control or copying packet identities",function()
        local f=harness();f.snapshot.phase="Live";f.humanoid.WalkSpeed=9;f.attrs.Stamina=88
        local start=#f.events
        for _,kind in ipairs({"Jammed","Blocked","JamHit","JamWhiff"}) do
            f.api.onFx({Type=kind,Player=f.player,Victim=f.opponent,Name="do-not-record",Dir=Vector3.new(9,0,8),
                arbitrary={token="do-not-record"}})
            local e=f.events[#f.events]
            assert(e.kind=="nativeContactFx" and e.eventType==kind and e.role=="WR" and e.phase=="Live")
            assert(e.isLocalVictim==(kind=="Jammed" or kind=="Blocked"))
            assert(e.speed==9 and e.stamina==88 and e.position.x==f.root.Position.X)
            assert(e.Player==nil and e.Victim==nil and e.Name==nil and e.Dir==nil and e.arbitrary==nil)
        end
        assert(#f.events==start+4 and #f.writes==0 and #f.submits==0 and #f.listeners==1)
        assert(not f.api.status().enabled and f.humanoid.WalkSpeed==9 and f.attrs.Stamina==88)
    end)
    test("native contact diagnostics filter unknown types and bound repeated notifications",function()
        local f=harness();local start=#f.events
        for _,packet in ipairs({false,{}, {Type="Jam"},{Type="jammed"},{Type="Unknown"}}) do f.api.onFx(packet) end
        assert(#f.events==start)
        for _=1,40 do f.api.onFx({Type="Jammed"}) end
        assert(#f.events==start+1)
        f.time=.05;f.api.onFx({Type="Jammed"});assert(#f.events==start+1)
        f.time=.101;f.api.onFx({Type="Jammed"});assert(#f.events==start+2)
        f.snapshot.testing=true;f.time=1;f.api.onFx({Type="Blocked"});assert(#f.events==start+2)
        f.snapshot.testing=false;f.character=nil;f.player.Character=nil
        f.humanoid.WalkSpeed=0/0;f.attrs.Stamina=0/0;f.api.onFx({Type="Blocked"})
        local e=f.events[#f.events]
        assert(e.eventType=="Blocked" and e.position==nil and e.speed==nil and e.stamina==nil)
        f.api.unload();local count=#f.events;f.time=2;f.api.onFx({Type="Jammed"});assert(#f.events==count)
    end)
    test("old enabled settings and model histories cannot enable or seed this product",function()
        local previous={enabled=true,learning={enabled=true,sharedEnabled=true},routeMemory={
            jobId="authored-server",opponentKey="authored-opponent",opponentUserId=123,
            savedAt=0,recentRoutes={{pass="Floater",depth=25,shape="straight",success=false}},selectionIndex=99}}
        local f=harness({previousState=previous});f:settle()
        local s=f.api.status()
        assert(not s.enabled and s.policyMode=="deterministic" and s.learning==nil)
        assert(#f.reads==1 and f.reads[1]=="ciu_deterministic_fullplay_v1.json" and #f.writes==0 and #f.submits==0)
        assert(#s.sessionHistory.recentRoutes==0 and s.sessionHistory.selectionIndex==0 and s.sessionHistory.persisted==false)
        assert(f.api.setLearning==nil and f.api.setSharedLearning==nil and f.api.setLearningEndpoint==nil)
        assert(f.api.learningCandidates==nil and f.api.learningActionExecuted==nil)
    end)
    test("explicit enable writes only isolated non-resuming settings",function()
        local f=harness();assert(f.api.setEnabled(true));f:settle()
        assert(f.api.status().enabled and #f.submits==1 and not f.api.status().error)
        assert(#f.writes==2 and f.writes[1].path=="ciu_deterministic_fullplay_v1.json")
        local v=f.writes[1].value
        assert(v.policyMode=="deterministic" and v.lastRequestedEnabled and v.autoResume==false)
        f.api.setEnabled(false);assert(f.releases==1 and f:navigate()==nil)
        local fresh=harness({previousState=f.api.status()});assert(not fresh.api.status().enabled)
    end)
    test("actual route selection is repeatable without model or RNG calls",function()
        local priorRandom,priorMathRandom=Random,math.random
        Random={new=function() error("RNG instantiated") end};math.random=function() error("RNG sampled") end
        local ok,err=pcall(function()
            local a,b=harness(),harness();a.api.setEnabled(true);b.api.setEnabled(true)
            for i=1,4 do
                if i==1 then a:settle();b:settle() else a:newRound(i);b:newRound(i) end
                assert(#a.submits==i and #b.submits==i);sameRoute(a.submits[i],b.submits[i])
                a.snapshot.phase="Live";b.snapshot.phase="Live";a.snapshot.snapAt=a.time;b.snapshot.snapAt=b.time
                local x,y=a:navigate(),b:navigate();assert(x and y)
                assert((x.direction-y.direction).Magnitude<1e-10 and x.sprint==y.sprint)
            end
        end)
        Random,math.random=priorRandom,priorMathRandom
        assert(ok,err)
    end)
    test("legacy learned policy overrides cannot replace deterministic choices",function()
        local base={mode="1v1",LOS=15,offset=Vector3.zero,position=Vector3.new(0,3,15),
            opponentPosition=Vector3.new(3,3,25),opponentVelocity=Vector3.zero,stamina=100,
            role="WR",phase="Live",elapsed=0}
        local a=assert(Policy.chooseRoute(base,Config,Field,RouteMath))
        local altered=table.clone(base);local calls=0
        altered.chooseLearnedRoute=function() calls=calls+1;error("legacy route hook invoked") end
        altered.generatedCandidates={{reachable=true,finishReachable=true}}
        local b=assert(Policy.chooseRoute(altered,Config,Field,RouteMath))
        sameRoute(a.payload,b.payload);assert(calls==0)
        base.role="DB";base.phase="PreSnap"
        altered=table.clone(base);altered.learnedDefense={setupX=-999,setupZ=999,liveDepth=99}
        local x=Policy.movement(base,Config,Field,RouteMath)
        local y=Policy.movement(altered,Config,Field,RouteMath)
        assert((x.target-y.target).Magnitude<1e-10 and x.sprint==y.sprint)
    end)
    test("route session observations are bounded and never persisted",function()
        local f=harness();f.api.setEnabled(true);f:settle()
        for i=1,9 do
            if i>1 then f:newRound(i) end
            f.snapshot.phase="Live"
            f.api.onFx({Type="BallResult",Result="Swatted"})
        end
        local s=f.api.status().sessionHistory
        assert(#s.recentRoutes==6 and #s.recentSelections==6 and s.selectionIndex==9)
        assert(#f.writes==10 and #f.reads==1 and f.reads[1]=="ciu_deterministic_fullplay_v1.json")
        f.accountId=456;f.opponent.Name="another-authored-opponent"
        s=f.api.status().sessionHistory
        assert(#s.recentRoutes==0 and #s.recentSelections==0 and s.selectionIndex==0)
    end)
    test("lobby clears session outcomes even when the old opponent remains in context",function()
        local f=harness();f.api.setEnabled(true);f:settle();f.snapshot.phase="Live"
        f.api.onFx({Type="BallResult",Result="Incomplete"})
        assert(#f.api.status().sessionHistory.recentRoutes==1)
        f.snapshot.phase="Lobby";local s=f.api.status()
        assert(#s.sessionHistory.recentRoutes==0 and not s.sessionHistory.opponentKnown and not s.submitted)
        assert(f.api.catchIntent()==nil)
    end)
    test("unknown catch ownership does not fabricate a successful route",function()
        local f=harness();f.api.setEnabled(true);f:settle();f.snapshot.phase="Live"
        f.api.onFx({Type="BallResult",Result="Catch"})
        assert(#f.api.status().sessionHistory.recentRoutes==0 and f.api.status().activeRoute)
        f.api.onFx({Type="BallResult",Result="Catch",Catcher=f.character})
        local s=f.api.status().sessionHistory
        assert(#s.recentRoutes==1 and s.recentRoutes[1].success)
        f.api.onFx({Type="BallResult",Result="Catch",Catcher=f.character})
        assert(#f.api.status().sessionHistory.recentRoutes==1)
    end)
    test("known opponent catches count as failed route outcomes",function()
        local f=harness();f.api.setEnabled(true);f:settle();f.snapshot.phase="Live"
        f.api.onFx({Type="BallResult",Result="Catch",Catcher=f.opponent})
        local s=f.api.status().sessionHistory
        assert(#s.recentRoutes==1 and s.recentRoutes[1].success==false)
    end)
    test("pause and 1v1-only gates prevent setup or movement without changing native speed",function()
        local f=harness();f.api.setEnabled(true);f.snapshot.role="DB";f.snapshot.phase="Hike"
        f.humanoid.WalkSpeed=12;f.root.Position=Vector3.new(0,3,40)
        local active=assert(f:navigate());assert(not active.sprint)
        for _,condition in ipairs({"menu","text","assist","testing","team","platform","core"}) do
            if condition=="menu" then f.gui.MenuIsOpen=true elseif condition=="text" then f.focused={}
            elseif condition=="assist" then f.assist=false elseif condition=="testing" then f.snapshot.testing=true
            elseif condition=="team" then f.snapshot.mode="Team" elseif condition=="platform" then f.humanoid.PlatformStand=true
            else f.snapshot.enabled=false end
            assert(f:navigate()==nil,condition.." did not pause navigation")
            f.gui.MenuIsOpen=false;f.focused=nil;f.assist=true;f.snapshot.testing=false
            f.snapshot.mode="1v1";f.humanoid.PlatformStand=false;f.snapshot.enabled=true
        end
        assert(f.humanoid.WalkSpeed==12)
        f.snapshot.role="WR";f.snapshot.phase="PreSnap";f.snapshot.mode="Team";f:settle()
        assert(#f.submits==0 and f.api.status().supportedMode=="1v1")
    end)
    test("normal movement keeps native speed and stamina reserves",function()
        local f=harness();f.api.setEnabled(true);f.snapshot.role="DB";f.snapshot.phase="Live"
        f.snapshot.snapAt=-5;f.root.Position=Vector3.new(0,3,20)
        f.opponentRoot.Position=Vector3.new(0,3,60);f.opponentRoot.AssemblyLinearVelocity=Vector3.new(0,0,27)
        f.attrs.Stamina=39
        local directive=assert(f:navigate())
        assert(not directive.sprint and directive.direction.Magnitude<=1.0000001)
        assert(f.humanoid.WalkSpeed==20 and f.root.Position.Z==20)
        local budget=f.api.movementBudget();assert(budget.dbReserve==40 and budget.wrReserve==10)
        assert(directive.learningToken==nil and directive.learningKey==nil)
    end)
    test("failed submissions do not create successful or selected session history",function()
        local f=harness();f.api.setEnabled(true);f.submitError="authored-submit-failure";f:settle()
        local s=f.api.status()
        assert(s.error and not s.submitted and #f.submits==0)
        assert(s.sessionHistory.selectionIndex==0 and #s.sessionHistory.recentSelections==0)
    end)
    test("observed defensive outcomes update fixed rules once within this session",function()
        local f=harness();f.api.setEnabled(true);f.snapshot.role="DB"
        for i=1,8 do
            f.snapshot.phase="PreSnap";f.snapshot.preSnapEnds=f.time+15
            f.snapshot.roundKey="defensive-round-"..i;f:tick()
            f.snapshot.phase="Live";f.time=f.time+1
            f.root.Position=Vector3.new(0,3,28);f.opponentRoot.Position=Vector3.new(0,3,30)
            local packet={Type="Throw",LaunchAt=f.time,Arc={P0=Vector3.new(0,6,10),
                P1=Vector3.new(0,3.5,Field.GoalZ),Flight=3.1,Apex=42}}
            f.api.onFx(packet)
            local active=f.api.status().activeDefense
            assert(active and active.pass=="Floater" and active.roundKey==f.snapshot.roundKey)
            f.api.onFx({Type="BallResult",Result="Catch",Catcher=f.opponent})
            f.api.onFx({Type="BallResult",Result="Catch",Catcher=f.opponent})
            f.api.onFx(packet)
            assert(f.api.status().activeDefense==nil,"duplicate throw reopened a resolved attempt")
        end
        local state=f.api.status()
        assert(#state.sessionHistory.recentDefense==6 and state.defenseProfile.samples==6)
        assert(state.defenseProfile.depthBiasYards==2.5 and #f.writes==1)
        local fresh=harness({previousState=state})
        assert(fresh.api.status().defenseProfile.samples==0 and not fresh.api.status().enabled)
    end)
    test("ambiguous or missing defensive throw information cannot alter session rules",function()
        local f=harness();f.api.setEnabled(true);f.snapshot.role="DB";f.snapshot.phase="Live"
        for _,packet in ipairs({{Type="Throw"},{Type="Throw",LaunchAt=0,Arc={P0=Vector3.zero,
            P1=Vector3.new(0,3,120),Flight=9,Apex=9}}}) do
            f.api.onFx(packet);f.api.onFx({Type="BallResult",Result="Catch",Catcher=f.opponent})
        end
        assert(f.api.status().defenseProfile.samples==0)
    end)
    test("settings write failure is visible and does not call legacy storage",function()
        local f=harness();f.writeError="authored-write-failure"
        local ok,err=f.api.setEnabled(true);assert(ok and err and f.api.status().enabled)
        f:settle();assert(#f.submits==1 and #f.reads==1 and f.reads[1]=="ciu_deterministic_fullplay_v1.json")
    end)
    test("selected starting X is submitted and steering distinguishes request from observed placement",function()
        local old=Policy.chooseScheduledRoute
        Policy.chooseScheduledRoute=function()
            local points={Vector2.new(15,15),Vector2.new(15,45),Vector2.new(-29,95)}
            local plan=RouteMath.Plan(points,"Bullet")
            return {payload={Points=points,StartX=15,Pass="Bullet"},plan=plan,shape="quarter_stem_opposite_side",
                depth=26,side=-1,slowStem=true,slowStemTime=1.5,routeFamily="quarter_stem",
                middleStemDeep=true,preferAirborne=true,preferJumpDive=true,requireDive=false}
        end
        local ok,err=pcall(function()
            local f=harness();f.api.setEnabled(true);f:settle()
            assert(f.submits[1].StartX==15 and f.submits[1].Points[1].X==15)
            assert(f.api.status().startX==15 and not f.api.status().startPositionObserved)
            local request=assert(f:navigate());assert(request.direction.X>0 and not request.sprint)
            assert(f.root.Position.X==0,"setup steering moved character directly")
            f.root.Position=Vector3.new(15,3,15);assert(f.api.status().startPositionObserved)
            f.snapshot.phase="Hike";f.humanoid.WalkSpeed=0;assert(f:navigate()==nil)
            f.snapshot.snapAt=f.time;f.api.onMatch({Phase="Hike"})
            local intent=f.api.catchIntent();assert(intent.requireAirborne and intent.preferAirborne and intent.preferJumpDive and not intent.requireDive)
            assert(not intent.continuousSprint)
            f.time=f.time+1.51
            assert(f.api.catchIntent().continuousSprint,"Throw handoff lost final sprint when no navigation frame occurred at cut")
        end)
        Policy.chooseScheduledRoute=old
        assert(ok,err)
    end)
    test("fixed route cycle persists across sessions while Full Auto still starts off",function()
        local saved
        for i=0,19 do
            local f=harness({saved=saved});local initial=f.api.status()
            assert(not initial.enabled and initial.routeCycle==i)
            assert(#initial.sessionHistory.recentSelections==0)
            f.api.setEnabled(true);f:settle()
            local state=f.api.status()
            assert(state.activeRoute.scheduledFamily=="middle_stem")
            assert(state.activeRoute.pass=="Floater" or i==19 and state.activeRoute.pass=="Bullet")
            assert(state.routeCycle==(i+1)%20)
            saved=f.writes[#f.writes].value
            assert(saved.routeCycle==(i+1)%20 and saved.lastRequestedEnabled and saved.autoResume==false)
            for _,entry in ipairs(f.writes) do
                assert(entry.path=="ciu_deterministic_fullplay_v1.json")
                assert(entry.value.recentRoutes==nil and entry.value.model==nil)
            end
        end
    end)
    test("catchIntent before navigation preserves exactly one hard cut and absolute stem timing",function()
        local f=harness();f.api.setEnabled(true);f:settle()
        local selected=assert(f.api.status().activeRoute)
        f.snapshot.phase="Live";f.snapshot.snapAt=f.time;f.api.onMatch({Phase="Hike"})
        local start=f.time
        local intent=assert(f.api.catchIntent());local stage=assert(intent.postThrowStem)
        assert(intent.routeStrategy=="deep_middle_floater" and intent.pass==selected.pass)
        assert(math.abs(stage.untilAt-start-selected.cutAt)<1e-6)
        assert(math.abs(stage.sprintStartAt-start-selected.stemSprintStart)<1e-6)
        assert(stage.reserve==10 and stage.plannedStemSprintSeconds==selected.stemSprintSeconds)
        f.time=start+selected.cutAt+.001
        intent=f.api.catchIntent()
        assert(intent.continuousSprint and not intent.postThrowStem)
        assert(f:navigate().hardCut,"catchIntent consumed the hard-cut command")
        assert(not f:navigate().hardCut,"same route issued the hard cut twice")
        f:newRound(2)
        local nextRoute=assert(f.api.status().activeRoute)
        f.snapshot.phase="Live";f.snapshot.snapAt=f.time;f.api.onMatch({Phase="Hike"})
        f.time=f.time+nextRoute.cutAt+.001;f.api.catchIntent()
        assert(f:navigate().hardCut,"new round did not reset hard-cut state")
    end)
    test("unfunded legal Floater is explicitly best effort instead of native default Bullet",function()
        local f=harness();f.attrs.Stamina=0;f.api.setEnabled(true);f:settle()
        local state=f.api.status()
        assert(#f.submits==1 and f.submits[1].Pass=="Floater" and state.submitted and state.routeCycle==1)
        assert(state.activeRoute.bestEffort and state.activeRoute.reachable==false)
        assert(state.activeRoute.estimatedCatchAt==nil and state.activeRoute.finalSprintStamina==nil)
        assert(state.message:find("best effort",1,true) and not f.api.catchIntent().postThrowStem)
    end)
    test("near-goal next down submits an airborne Floater before native default timeout",function()
        local f=harness();local los=Field.GoalZ-1.3*Field.YD
        f.snapshot.LOS=los;f.root.Position=Vector3.new(Field.MidX,3,los-2)
        f.api.setEnabled(true);f:settle()
        assert(#f.submits==1 and f.submits[1].Pass=="Floater" and not f.boardOpen)
        local selected=assert(f.api.status().activeRoute)
        assert(selected.shortField and selected.estimatedCatchInsideGoal)
        assert(selected.estimatedStopAt>=selected.estimatedFirstTouchAt)
    end)
    test("corrupt route cycle defaults to zero and never enables automatic play",function()
        for _,value in ipairs({-1,20,21,1.5,"4",math.huge}) do
            local f=harness({saved={schemaVersion=1,routeCycle=value,enabled=true,lastRequestedEnabled=true}})
            assert(f.api.status().routeCycle==0 and not f.api.status().enabled)
        end
        local f=harness({saved={schemaVersion=99,routeCycle=4,enabled=true}})
        assert(f.api.status().routeCycle==0 and not f.api.status().enabled)
    end)
    test("unload stops callbacks and releases control",function()
        local f=harness();f.api.setEnabled(true);f.api.unload();f:settle()
        assert(f.releases==1 and #f.submits==0 and f:navigate()==nil)
        f.api.unload();assert(f.releases==1)
    end)
    local function observedRoute(body,flags)
        local old=Policy.chooseScheduledRoute
        Policy.chooseScheduledRoute=function()
            local points={Vector2.new(0,15),Vector2.new(0,75),Vector2.new(-29,145)}
            local choice={payload={Points=points,StartX=0,Pass="Floater"},plan=RouteMath.Plan(points,"Floater"),
                shape="middle_left",depth=26,side=-1,routeStrategy="deep_middle_floater"}
            for key,value in pairs(flags or {}) do choice[key]=value end
            if choice.pass then choice.payload.Pass=choice.pass end
            return choice
        end
        local ok,err=pcall(body)
        Policy.chooseScheduledRoute=old
        assert(ok,err)
    end
    local function startObservation(f,offset)
        offset=offset or Vector3.zero
        f.snapshot.offset=offset;f.snapshot.phase="Live";f.snapshot.snapAt=f.time
        f.root.Position=Vector3.new(0,3,15)+offset
        f.opponentRoot.Position=Vector3.new(0,3,Field.GoalZ)+offset
        f.opponentRoot.AssemblyLinearVelocity=Vector3.zero
        f:tick(.2)
    end
    local function observationStep(f,dz,dt)
        f.root.Position=f.root.Position+Vector3.new(0,0,dz or 3)
        f:tick(dt or .2)
    end
    local function finishObservation(f)
        f.api.onFx({Type="Throw"})
        f.api.onFx({Type="BallResult",Result="Incomplete"})
        local history=f.api.status().sessionHistory.recentRoutes
        return assert(history[#history])
    end
    test("two completed camping observations are ephemeral, bounded and frozen at the throw",function()
        observedRoute(function()
            local f=harness();f.api.setEnabled(true);f:settle()
            for play=1,2 do
                if play>1 then f.opponentRoot.AssemblyLinearVelocity=Vector3.zero;f:newRound(play) end
                startObservation(f)
                for _=1,6 do observationStep(f) end
                assert(#f.api.status().sessionHistory.recentRoutes==play-1,"uncompleted play became evidence")
                f.api.onFx({Type="Throw"})
                f.snapshot.arc={};f.opponentRoot.Position=Vector3.new(0,3,30)
                f.opponentRoot.AssemblyLinearVelocity=Vector3.new(0,0,27);f:tick(1)
                f.api.onFx({Type="BallResult",Result="Incomplete"})
                f.api.onFx({Type="BallResult",Result="Incomplete"})
                local history=f.api.status().sessionHistory.recentRoutes
                assert(#history==play and history[play].campingObservationKnown and history[play].observedEndzoneCamping)
                assert(math.abs(history[play].campingObservationSeconds-1.2)<1e-6)
                assert(math.abs(history[play].campingOwnProgressYards-3.6)<1e-6)
                assert(history[play].campingDefenderDisplacementYards==0)
                f.snapshot.arc=nil
            end
            for _,entry in ipairs(f.writes) do assert(entry.value.recentRoutes==nil and entry.value.observedEndzoneCamping==nil) end
            local fresh=harness({previousState=f.api.status(),saved=f.writes[#f.writes].value})
            assert(#fresh.api.status().sessionHistory.recentRoutes==0)
        end)
    end)
    test("following, transient deep alignment and out-and-back travel do not qualify as camping",function()
        observedRoute(function()
            for _,scenario in ipairs({"following","transient","out-and-back"}) do
                local f=harness();f.api.setEnabled(true);f:settle();startObservation(f)
                for i=1,6 do
                    if scenario=="following" then
                        f.opponentRoot.Position=f.opponentRoot.Position+Vector3.new(0,0,3)
                        f.opponentRoot.AssemblyLinearVelocity=Vector3.new(0,0,15)
                    elseif scenario=="transient" and i==2 then
                        f.opponentRoot.Position=Vector3.new(0,3,Field.GoalZ-2*Field.YD)
                    elseif scenario=="transient" and i==3 then
                        f.opponentRoot.Position=Vector3.new(0,3,Field.GoalZ)
                    elseif scenario=="out-and-back" then
                        f.opponentRoot.Position=Vector3.new(i%2==0 and 0 or 1,3,Field.GoalZ)
                        f.opponentRoot.AssemblyLinearVelocity=Vector3.new(5,0,0)
                    end
                    observationStep(f)
                end
                local item=finishObservation(f)
                assert(item.campingObservationKnown and not item.observedEndzoneCamping,scenario)
                if scenario=="out-and-back" then assert(item.campingDefenderDisplacementYards>1) end
            end
        end)
    end)
    test("insufficient progress, short windows, missing observations and pauses stay unknown",function()
        observedRoute(function()
            for _,scenario in ipairs({"short","stationary","gap","missing","menu","unknown-velocity"}) do
                local f=harness();f.api.setEnabled(true);f:settle();startObservation(f)
                for i=1,scenario=="short" and 3 or 6 do
                    if scenario=="missing" and i==3 then f.snapshot.opponent=nil end
                    if scenario=="menu" and i==3 then f.gui.MenuIsOpen=true end
                    if scenario=="unknown-velocity" and i==3 then f.opponentRoot.AssemblyLinearVelocity=nil end
                    observationStep(f,scenario=="stationary" and 0 or 3,scenario=="gap" and i==3 and .6 or .2)
                    f.snapshot.opponent=f.opponent;f.gui.MenuIsOpen=false;f.opponentRoot.AssemblyLinearVelocity=Vector3.zero
                end
                local item=finishObservation(f)
                assert(item.campingObservationKnown==false and item.observedEndzoneCamping==false,scenario)
            end
        end)
    end)
    test("camping evidence uses the world goal offset and completed following resets the recent pair",function()
        observedRoute(function()
            local f=harness();f.api.setEnabled(true);f:settle()
            startObservation(f,Vector3.new(400,20,700))
            for _=1,6 do observationStep(f) end
            assert(finishObservation(f).observedEndzoneCamping)
            f:newRound(2);startObservation(f)
            for _=1,6 do observationStep(f) end
            assert(finishObservation(f).observedEndzoneCamping)
            f:newRound(3);startObservation(f)
            for _=1,6 do
                f.opponentRoot.Position=f.opponentRoot.Position+Vector3.new(0,0,3)
                f.opponentRoot.AssemblyLinearVelocity=Vector3.new(0,0,15);observationStep(f)
            end
            f.api.onMatch({Phase="Result",Result="Incomplete"})
            local items=f.api.status().sessionHistory.recentRoutes
            assert(#items==3 and items[2].observedEndzoneCamping and items[3].campingObservationKnown)
            assert(items[3].observedEndzoneCamping==false)
        end)
    end)
    test("explicit off, changed opponent and unload revoke camping evidence",function()
        observedRoute(function()
            for _,reset in ipairs({"off","opponent","unload"}) do
                local f=harness();f.api.setEnabled(true);f:settle();startObservation(f)
                for _=1,6 do observationStep(f) end
                assert(finishObservation(f).observedEndzoneCamping)
                f:newRound(2);startObservation(f);for _=1,6 do observationStep(f) end
                if reset=="off" then
                    f.api.setEnabled(false);f.api.setEnabled(true)
                    assert(finishObservation(f).campingObservationKnown==false,"partial resumed play retained evidence")
                elseif reset=="opponent" then f.accountId=456;f.api.status()
                else f.api.unload() end
                for _,item in ipairs(f.api.status().sessionHistory.recentRoutes) do
                    assert(not item.observedEndzoneCamping and not item.campingObservationKnown,reset)
                end
            end
        end)
    end)
    test("continuous Bullet catch intent is restricted to an explicitly selected rare camping Bullet",function()
        for _,case in ipairs({{pass="Bullet",rareCampingBullet=true,continuousBulletCatch=true},
            {pass="Bullet",continuousBulletCatch=true},{pass="Floater",rareCampingBullet=true,continuousBulletCatch=true},
            {pass="Bullet",rareCampingBullet=true}}) do
            observedRoute(function()
                local f=harness();f.api.setEnabled(true);f:settle()
                local intent=assert(f.api.catchIntent())
                local expected=case.pass=="Bullet" and case.rareCampingBullet==true and case.continuousBulletCatch==true
                assert(intent.continuousBulletCatch==expected)
                assert(not intent.requireDive)
            end,case)
        end
    end)
    test("rare camping Bullet preserves its move reserve only until confirmed own possession",function()
        observedRoute(function()
            for _,notice in ipairs({"Catch","RAC"}) do
                local f=harness();f.api.setEnabled(true);f:settle();f.snapshot.phase="Live"
                assert(f.api.movementBudget().wrReserve==30 and f.api.movementBudget().dbReserve==40)
                assert(f.api.movementBudget(true).wrReserve==30 and f.api.movementBudget(true).dbReserve==2)
                assert(f.api.movementBudget(false).dbReserve==40 and f.api.movementBudget("true").dbReserve==40)
                f.api.onFx({Type="BallResult",Result="Catch"})
                assert(f.api.movementBudget().wrReserve==30,"unknown catcher released the carry reserve")
                if notice=="Catch" then f.api.onFx({Type="BallResult",Result="Catch",Catcher=f.character})
                else f.api.onMatch({Phase="RAC",Carrier=f.character}) end
                assert(f.api.movementBudget().wrReserve==10,"confirmed carrier could not spend its reserved move")
                f:newRound(2)
                assert(f.api.movementBudget().wrReserve==30,"new route inherited old possession")
                f.api.setEnabled(false);assert(f.api.movementBudget()==nil)
            end
        end,{pass="Bullet",rareCampingBullet=true,carryReserve=30})
        for _,flags in ipairs({{pass="Floater",rareCampingBullet=true,carryReserve=30},
            {pass="Bullet",carryReserve=30},{pass="Bullet",rareCampingBullet=true,carryReserve=math.huge},
            {pass="Bullet",rareCampingBullet=true,carryReserve=101}}) do
            observedRoute(function()
                local f=harness();f.api.setEnabled(true);f:settle()
                assert(f.api.movementBudget().wrReserve==10)
            end,flags)
        end
    end)
    test("only WR route navigation forwards an absolute observed avoidance arrival deadline",function()
        local old=Policy.movement
        local target=Vector3.new(20,3,60)
        local kind,deadline="route",5
        local observedSpeed
        Policy.movement=function(input)
            observedSpeed=input.currentWalkSpeed
            return {kind=kind,target=target,routeDeadline=deadline,sprint=false}
        end
        local ok,err=pcall(function()
            local f=harness();f.api.setEnabled(true);f.time=100
            f.snapshot.phase="Live";f.snapshot.snapAt=98
            local request=assert(f:navigate())
            assert(request.avoidanceArrival.targetPosition==target and request.avoidanceArrival.arriveBy==103)
            assert(observedSpeed==20)
            f.humanoid.WalkSpeed=9;assert(f:navigate());assert(observedSpeed==9 and f.humanoid.WalkSpeed==9)
            f.humanoid.WalkSpeed=20
            f.snapshot.role="DB";assert(f:navigate().avoidanceArrival==nil)
            f.snapshot.role="WR";kind="carry";assert(f:navigate().avoidanceArrival==nil)
            kind="route";deadline=nil;assert(f:navigate().avoidanceArrival==nil)
            deadline=5;f.snapshot.snapAt=nil;assert(f:navigate().avoidanceArrival==nil)
        end)
        Policy.movement=old;assert(ok,err)
    end)
    test("one successfully submitted camping counter remains spent across OFF and the next round",function()
        observedRoute(function()
            local selected=Policy.chooseScheduledRoute
            local seen={}
            Policy.chooseScheduledRoute=function(input,...)
                seen[#seen+1]=input.campingCounterUsed
                local choice=selected(input,...)
                if input.campingCounterUsed then
                    choice.payload.Pass="Floater";choice.rareCampingBullet=false;choice.continuousBulletCatch=false
                    choice.campingGateReason="session_counter_used"
                end
                return choice
            end
            local f=harness();f.api.setEnabled(true);f:settle()
            assert(seen[1]==false and f.api.status().sessionHistory.campingCounterUsed)
            local route=f.api.status().activeRoute
            assert(route.campingGateReason=="counter_selected" and route.campingEvidenceCount==2
                and route.campingCurrentKnown and route.campingCurrentWaiting)
            local event
            for _,row in ipairs(f.events) do if row.kind=="routeRequested" then event=row end end
            assert(event and event.campingCounterUsed and event.campingEvidenceCount==2
                and event.campingCurrentKnown and event.campingCurrentWaiting)
            f.api.setEnabled(false);f.api.setEnabled(true)
            assert(f.api.status().sessionHistory.campingCounterUsed,"OFF restored an already spent counter")
            f:newRound(2)
            assert(seen[#seen]==true and f.submits[2].Pass=="Floater")
            assert(f.api.status().activeRoute.campingGateReason=="session_counter_used")
            f.accountId=456
            assert(not f.api.status().sessionHistory.campingCounterUsed,"new opponent inherited the counter")
            local fresh=harness({previousState={campingCounterUsed=true},saved={schemaVersion=1,campingCounterUsed=true}})
            assert(not fresh.api.status().sessionHistory.campingCounterUsed)
        end,{pass="Bullet",rareCampingBullet=true,continuousBulletCatch=true,
            campingGateReason="counter_selected",campingEvidenceCount=2,campingCurrentKnown=true,campingCurrentWaiting=true})
    end)
    test("unavailable candidates and failed submissions do not consume the camping counter",function()
        observedRoute(function()
            local select=Policy.chooseScheduledRoute
            local unavailable=true
            Policy.chooseScheduledRoute=function(...)
                if unavailable then return nil,"authored unavailable counter" end
                return select(...)
            end
            local f=harness();f.api.setEnabled(true);f:settle()
            assert(not f.api.status().sessionHistory.campingCounterUsed and #f.submits==0)
            unavailable=false;f.submitError="authored native submit failure";f:newRound(2)
            assert(not f.api.status().sessionHistory.campingCounterUsed and #f.submits==0)
            f.submitError=nil;f:newRound(3)
            assert(f.api.status().sessionHistory.campingCounterUsed and #f.submits==1)
            f.snapshot.phase="Lobby"
            assert(not f.api.status().sessionHistory.campingCounterUsed)
        end,{pass="Bullet",rareCampingBullet=true})
    end)
    Vector2,typeof=oldVector2,oldTypeof
    report.fixture="Authored offline services and geometry; locally supplied RouteMath is not copied or published. No server outcome claim."
    return report
end
