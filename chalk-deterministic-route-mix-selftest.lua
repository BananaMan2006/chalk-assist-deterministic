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
    local Field={MinX=-49,MaxX=49,MidX=0,BackZ=-25,LOSZ=0,GoalZ=125,EndZ=150,YD=5,TurfY=0}
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
    local function input(extra)
        local value={LOS=0,offset=Vector3.zero,position=Vector3.new(0,3,0),stamina=100,
            selectionIndex=0,mode="1v1",role="WR",phase="PreSnap"}
        for key,item in pairs(extra or {}) do value[key]=item end
        return value
    end
    local function choose(value) return assert(Policy.chooseScheduledRoute(value,Config,Field,RouteMath,Planner)) end

    test("automatic WR keeps deep middle Floaters with at most one checked Bullet slot",function()
        for _,cycle in ipairs({0,1,3,4,9,19}) do
            local c=choose(input({routeCycle=cycle}))
            assert((c.payload.Pass=="Floater" or cycle==19 and c.payload.Pass=="Bullet") and c.payload.StartX==Field.MidX)
            assert(c.routeFamily=="middle_stem" and c.scheduledFamily=="middle_stem")
            assert(c.stemYards>=Field.GoalZ/Field.YD*.65,"middle stem cut too early")
            assert(c.requireAirborne and not c.requireDive and not c.preferJumpDive)
            if c.payload.Pass=="Floater" then
                assert(c.ballTargetZ>=Field.GoalZ+4*Field.YD)
                assert(c.estimatedCatchZ>=Field.GoalZ+.25 and c.estimatedCatchInsideGoal)
                assert(c.estimatedStopAt>=c.estimatedFirstTouchAt)
            end
            if c.payload.Pass=="Bullet" then assert(c.rareBullet and c.cutAt<=c.plan.Launch) end
        end
    end)
    test("both sharp-cut sides remain available without changing the middle start",function()
        local left=choose(input({routeCycle=0}));local right=choose(input({routeCycle=1}))
        assert(left.side==-1 and right.side==1)
        for _,c in ipairs({left,right}) do
            local p=c.payload.Points;local leg=p[3]-p[2]
            assert(math.abs(p[2].X-p[1].X)<.001 and c.side*leg.X>=2*Field.YD)
            local angle=math.deg(math.acos(leg.Y/leg.Magnitude))
            assert(angle>=40 and angle<=115)
        end
    end)
    test("post-throw stem survives native sanitation and has a funded jump witness",function()
        local c=choose(input({position=Vector3.new(0,3,-2)}))
        assert(c.postThrowStem and c.cutAt>c.plan.Launch)
        assert(c.stemSprintSeconds<=2 and c.earlyStemSprintSeconds>=.4 and c.earlyStemSprintSeconds<=.6)
        assert(math.abs(c.stemSprintSeconds-(c.earlyStemSprintSeconds+c.cutAt-c.stemSprintStart))<1e-6)
        assert(c.estimatedContactMargin>=.6 and c.finalSprintStamina>=10)
        assert(c.estimatedCatchAt<c.plan.Arrival and c.estimatedCatchAt>c.cutAt)
        local cost=(c.stemSprintSeconds+c.finalSprintDuration)*Config.SprintDrain
        assert(math.abs(c.finalSprintStamina-(100-cost+(c.estimatedStemRegeneration or 0)))<1e-5)
        assert(math.abs(c.finalSprintDuration-(c.estimatedCatchAt-c.cutAt+.12))<1e-6)
    end)
    test("missing contact planner fails closed instead of restoring Bullets",function()
        local c,why=Policy.chooseScheduledRoute(input(),Config,Field,RouteMath)
        assert(not c and why:find("forecast",1,true))
        local noStage={solve=Planner.solve,pose=Planner.pose}
        c=Policy.chooseScheduledRoute(input(),Config,Field,RouteMath,noStage)
        assert(not c or c.payload.Pass=="Floater" and not c.postThrowStem)
    end)
    test("low and unknown stamina mark legal deep Floater attempts as unverified",function()
        for _,stamina in ipairs({0,10,20}) do
            local c=Policy.chooseScheduledRoute(input({stamina=stamina}),Config,Field,RouteMath,Planner)
            assert(c and c.payload.Pass=="Floater" and c.ballTargetZ>=Field.GoalZ+4*Field.YD)
            assert(c.bestEffort and not c.reachable and not c.finishReachable and not c.postThrowStem)
            assert(c.finalSprintStamina==nil and c.estimatedCatchAt==nil)
        end
        local p=input();p.stamina=nil
        assert(Policy.chooseScheduledRoute(p,Config,Field,RouteMath,Planner).bestEffort)
    end)
    test("explicit failed lane changes side; unknown outcomes do not invent failure",function()
        local baseline=choose(input({routeCycle=0}))
        local failed=choose(input({routeCycle=0,recentRoutes={{success=false,result="Intercepted",side=baseline.side}}}))
        local unknown=choose(input({routeCycle=0,recentRoutes={{result="mystery",side=baseline.side}}}))
        assert(failed.side~=baseline.side and unknown.side==baseline.side)
    end)
    test("stationary deep middle blocker is included in travel budget",function()
        local c=choose(input({opponentPosition=Vector3.new(0,3,8*Field.YD),opponentVelocity=Vector3.zero}))
        assert(c.payload.Pass=="Floater" and c.payload.StartX==Field.MidX)
        assert(c.stemDetour and c.stemTravelDistance>c.stemYards*Field.YD)
        assert(c.finalSprintStamina>=10)
    end)
    test("spawn gap and world offset remain part of the forecast",function()
        local p=input({position=Vector3.new(100,3,198),offset=Vector3.new(100,0,200)})
        local c=choose(p)
        assert(c.payload.StartX==Field.MidX and c.payload.Points[1].Y==0)
        assert(c.stemTravelDistance>=c.stemYards*Field.YD+1.99)
        assert(c.estimatedCatchZ<Field.EndZ and c.finalSprintStamina>=10)
    end)
    test("live ball never grants route control without fresh explicit stem permission",function()
        local c=choose(input())
        local p=input({phase="Live",elapsed=c.plan.Launch+.1,routePlan=c.plan,ballActive=true,passStarted=true,
            routeStrategy=c.routeStrategy,postThrowStem=true,slowStem=true,slowStemTime=c.cutAt,
            stemSprintStart=c.stemSprintStart,earlyStemSprintSeconds=c.earlyStemSprintSeconds,estimatedCatchAt=c.estimatedCatchAt,middleStemDeep=true,
            position=Vector3.new(0,3,c.stemYards*Field.YD-8),routeWaypoint=2})
        assert(not Policy.movement(p,Config,Field,RouteMath))
        p.allowPostThrowStem=true
        local command=assert(Policy.movement(p,Config,Field,RouteMath))
        assert(command.routeWaypoint==2 and not command.finalSprintCommitted and command.target.X==0)
        p.elapsed=c.cutAt
        assert(not Policy.movement(p,Config,Field,RouteMath))
        p.elapsed=c.plan.Launch+.1;p.role="DB"
        assert(not Policy.movement(p,Config,Field,RouteMath))
    end)
    test("stem sprint is scheduled and retains the forecast final reserve",function()
        local c=choose(input());assert(c.stemSprintSeconds>0)
        local p=input({phase="Live",elapsed=c.stemSprintStart-.2,routePlan=c.plan,
            routeStrategy=c.routeStrategy,postThrowStem=c.postThrowStem,slowStem=true,slowStemTime=c.cutAt,
            stemSprintStart=c.stemSprintStart,earlyStemSprintSeconds=c.earlyStemSprintSeconds,estimatedCatchAt=c.estimatedCatchAt,middleStemDeep=true,
            estimatedStemRegeneration=c.estimatedStemRegeneration,
            position=Vector3.new(0,3,c.stemYards*Field.YD-15),routeWaypoint=2})
        local walking=assert(Policy.movement(p,Config,Field,RouteMath))
        assert(not walking.sprint and walking.moveSpeed<=Config.RunSpeed)
        p.elapsed=.1
        local early=assert(Policy.movement(p,Config,Field,RouteMath))
        assert(early.sprint and early.moveSpeed==Config.SprintSpeed and not early.hardCut)
        p.elapsed=c.stemSprintStart+.01
        local sprinting=assert(Policy.movement(p,Config,Field,RouteMath))
        assert(sprinting.sprint and sprinting.moveSpeed==Config.SprintSpeed and not sprinting.finalSprintCommitted)
        p.stamina=15
        assert(not Policy.movement(p,Config,Field,RouteMath).sprint)
    end)
    test("hard cut is a one-time movement directive and catch position uses first touch",function()
        local c=choose(input())
        assert(c.estimatedFirstTouchAt<=c.estimatedCatchAt)
        assert(c.estimatedCatchInsideGoal==(c.estimatedCatchZ>=Field.GoalZ))
        assert(not c.estimatedStopAt or c.estimatedStopAt>=c.estimatedFirstTouchAt)
        local p=input({phase="Live",elapsed=c.cutAt,routePlan=c.plan,routeStrategy=c.routeStrategy,
            slowStem=true,slowStemTime=c.cutAt,middleStemDeep=true,routeWaypoint=2})
        local cut=assert(Policy.movement(p,Config,Field,RouteMath))
        assert(cut.hardCut and cut.finalSprintCommitted and cut.routeWaypoint==3)
        p.finalSprintCommitted=true
        assert(not Policy.movement(p,Config,Field,RouteMath).hardCut)
    end)
    test("measured stem debt permits a bounded funded burst and counts scheduled sprint",function()
        local plan={Points={Vector2.new(0,0),Vector2.new(0,90),Vector2.new(-40,130)},
            Times={0,4.248038177,6.49845},Arrival=6.49845}
        local p=input({phase="Live",elapsed=2.156745195,routePlan=plan,
            routeStrategy="deep_middle_floater",slowStem=true,slowStemTime=4.248038177,
            stemSprintStart=3.648038177,earlyStemSprintSeconds=.6,estimatedCatchAt=6.299385834,
            middleStemDeep=true,routeWaypoint=2,position=Vector3.new(-3.73174,3,42.65),stamina=100})
        local recovered=assert(Policy.movement(p,Config,Field,RouteMath))
        assert(recovered.sprint and recovered.stemRecoverySeconds>=.12 and recovered.stemRecoverySeconds<=.6)
        assert(recovered.routeWaypoint==2 and not recovered.finalSprintCommitted and not recovered.hardCut)
        assert(recovered.routeScheduleCapacity>46.02)
        p.stemRecoveryUntil=recovered.stemRecoveryUntil;p.stemRecoverySpent=recovered.stemRecoverySeconds
        p.elapsed=p.elapsed+.05
        local held=assert(Policy.movement(p,Config,Field,RouteMath))
        assert(held.sprint and not held.stemRecoverySeconds,"latched burst was allocated twice")
        p.stemRecoveryUntil=0;p.stemRecoverySpent=.6
        assert(not Policy.movement(p,Config,Field,RouteMath).sprint,"extra sprint exceeded route cap")
        p.stemRecoverySpent=0;p.stamina=70
        assert(not Policy.movement(p,Config,Field,RouteMath).sprint,"recovery spent the final catch reserve")
        p.stamina=100;p.position=Vector3.new(0,3,50)
        local clear=assert(Policy.movement(p,Config,Field,RouteMath))
        assert(not clear.sprint and not clear.routeTimingDebt,"scheduled late sprint was ignored")
        p.position=Vector3.new(-3.73174,3,42.65);p.ballActive=true;p.passStarted=true
        p.allowPostThrowStem=true;p.postThrowStem=true
        local afterThrow=assert(Policy.movement(p,Config,Field,RouteMath))
        assert(not afterThrow.stemRecoverySeconds,"new recovery burst invented after catch handoff")
    end)
    test("short remaining downs use a paced side Floater with no parked first contact",function()
        for _,yards in ipairs({1.3,.25}) do
            local los=Field.GoalZ-yards*Field.YD
            local c=choose(input({LOS=los,position=Vector3.new(0,3,los-2)}))
            assert(c.shortField and c.payload.Pass=="Floater")
            assert(math.abs(c.payload.Points[1].Y-los)<.001,"short LOS was moved backward")
            assert(c.payload.Points[2].Y>Field.GoalZ and c.payload.Points[3].Y>=c.payload.Points[2].Y)
            assert(c.stemRunSpeed>0 and c.stemRunSpeed<Config.RunSpeed)
            assert(c.ballTargetZ>=Field.GoalZ+4*Field.YD and c.estimatedCatchZ>=Field.GoalZ+.25)
            assert(c.estimatedStopAt>=c.estimatedFirstTouchAt and c.finalSprintStamina>=10)
        end
    end)
    test("regeneration forecast is bounded to spent opening sprint and needs native constants",function()
        local c=choose(input())
        assert(c.estimatedStemRegeneration>=0 and c.estimatedStemRegeneration<=c.earlyStemSprintSeconds*Config.SprintDrain)
        local stripped={};for k,v in pairs(Config) do stripped[k]=v end
        stripped.StaminaRegen=nil;stripped.RegenDelay=nil
        local without=Policy.chooseScheduledRoute(input(),stripped,Field,RouteMath,Planner)
        assert(not without or without.bestEffort or without.estimatedStemRegeneration==0)
    end)
    test("new deep stem does not use the legacy opposite-side feint",function()
        local c=choose(input());local p=input({phase="Live",elapsed=.15,routePlan=c.plan,
            routeStrategy=c.routeStrategy,postThrowStem=c.postThrowStem,slowStem=true,slowStemTime=c.cutAt,
            stemSprintStart=c.stemSprintStart,estimatedCatchAt=c.estimatedCatchAt,middleStemDeep=true,
            routeFamily="middle_stem",routeSide=c.side,opponentPosition=Vector3.new(3,3,20),routeWaypoint=2})
        local command=assert(Policy.movement(p,Config,Field,RouteMath))
        assert(not command.stemFeint and command.target.X==Field.MidX)
    end)
    Vector2,typeof=oldVector2,oldTypeof
    return report
end
