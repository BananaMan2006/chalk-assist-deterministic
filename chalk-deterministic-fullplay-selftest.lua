-- Supplied RouteMath source, with explicit numeric geometry and service fixtures.
-- No Roblox physics, network outcome, GUI input, or opponent behavior is simulated.
return function(Policy,create,routeSource)
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
    local Config={RunSpeed=20,SprintSpeed=27,Stamina=100,SprintDrain=25,HikeTime=3,PreSnapDBSpeed=12,
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
            Config=Config,Field=Field,RouteMath=RouteMath,http=http,guiService=f.gui,
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
            assert(state.activeRoute.scheduledFamily==(i%5==4 and "quarter_stem" or "middle_stem"))
            assert(state.routeCycle==(i+1)%20)
            saved=f.writes[#f.writes].value
            assert(saved.routeCycle==(i+1)%20 and saved.lastRequestedEnabled and saved.autoResume==false)
            for _,entry in ipairs(f.writes) do
                assert(entry.path=="ciu_deterministic_fullplay_v1.json")
                assert(entry.value.recentRoutes==nil and entry.value.model==nil)
            end
        end
    end)
    test("unreachable cut request never submits a straight route or advances the schedule",function()
        local f=harness();f.attrs.Stamina=0;f.api.setEnabled(true);f:settle()
        local state=f.api.status()
        assert(#f.submits==0 and state.error and state.routeCycle==0 and not state.submitted)
        assert(#state.sessionHistory.recentSelections==0)
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
    Vector2,typeof=oldVector2,oldTypeof
    report.fixture="Authored offline services and geometry; locally supplied RouteMath is not copied or published. No server outcome claim."
    return report
end
