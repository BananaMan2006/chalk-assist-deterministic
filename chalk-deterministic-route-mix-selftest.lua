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
            selectionIndex=0,mode="1v1",role="WR",phase="PreSnap",campingCounterUsed=false}
        for key,item in pairs(extra or {}) do value[key]=item end
        return value
    end
    local function choose(value) return assert(Policy.chooseScheduledRoute(value,Config,Field,RouteMath,Planner)) end

    test("automatic WR keeps Floaters at every cycle without observed camping",function()
        for _,cycle in ipairs({0,1,3,4,9,19}) do
            local c=choose(input({routeCycle=cycle}))
            assert(c.payload.Pass=="Floater" and c.payload.StartX==Field.MidX)
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
    local function campingInput(extra)
        local p=input({routeCycle=2,opponentPosition=Vector3.new(Field.MidX,3,Field.GoalZ+2*Field.YD),
            opponentVelocity=Vector3.zero,recentRoutes={
                {roundKey="first",campingObservationKnown=true,observedEndzoneCamping=true},
                {roundKey="second",campingObservationKnown=true,observedEndzoneCamping=true}}})
        for key,value in pairs(extra or {}) do p[key]=value end
        return p
    end
    test("third qualifying play responds immediately with a funded moving Bullet before goal",function()
        local c=choose(campingInput())
        assert(c.payload.Pass=="Bullet" and c.rareCampingBullet and c.rareBullet and c.continuousBulletCatch)
        assert(c.campingGateReason=="counter_selected" and c.campingEvidenceCount==2 and c.campingCurrentWaiting)
        assert(c.routeStrategy=="deep_middle_bullet" and c.payload.StartX==Field.MidX)
        assert(c.stemYards>=(Field.GoalZ/Field.YD)-5 and c.cutAngle>=60)
        assert(c.cutAt<=c.plan.Launch and not c.postThrowStem)
        assert(c.estimatedCatchZ<Field.GoalZ-.25 and c.estimatedCatchZ>=Field.GoalZ-6*Field.YD)
        assert(not c.estimatedCatchInsideGoal and not c.requireDive and c.requireAirborne)
        assert(c.estimatedStopAt>=c.estimatedCatchAt+.012 and c.estimatedFirstTouchAt<=c.estimatedCatchAt)
        assert(c.finalSprintStamina>=10+Config.Moves.Juke.Cost and c.carryReserve>=30)
        assert(c.carryClearance>=2.5*Field.YD and c.estimatedSeparation>=5*Field.YD)
        local command=assert(Policy.movement(input({phase="Live",elapsed=.75,position=Vector3.new(0,3,20),
            routePlan=c.plan,routeStrategy=c.routeStrategy,slowStem=true,slowStemTime=c.cutAt,
            earlyStemSprintSeconds=c.earlyStemSprintSeconds,stemSprintStart=c.stemSprintStart,
            estimatedStemRegeneration=c.estimatedStemRegeneration,estimatedCatchAt=c.estimatedCatchAt,
            finalSprintReserve=c.finalSprintReserve,
            middleStemDeep=true,routeWaypoint=2}),Config,Field,RouteMath))
        assert(command.sprint and not command.stemFeint,"Bullet lost the funded middle-stem schedule")
        local p=input({phase="Live",elapsed=c.cutAt,position=Vector3.new(0,3,c.stemYards*Field.YD),
            routePlan=c.plan,routeStrategy=c.routeStrategy,slowStem=true,slowStemTime=c.cutAt,
            middleStemDeep=true,routeWaypoint=2,stamina=c.carryReserve+1,finalSprintReserve=c.finalSprintReserve})
        assert(not Policy.movement(p,Config,Field,RouteMath).sprint,"final approach spent the carrier move reserve")
        p.finalSprintReserve=nil;p.stamina=100
        assert(not Policy.movement(p,Config,Field,RouteMath).sprint,"missing rare-route reserve was guessed")
    end)
    test("camping evidence must cover two distinct recent plays and the opponent must still wait",function()
        local cases={campingInput({opponentVelocity=Vector3.new(Config.RunSpeed,0,0)}),
            campingInput({opponentPosition=Vector3.new(0,3,Field.GoalZ-3*Field.YD)})}
        local one=campingInput();table.remove(one.recentRoutes,1);cases[#cases+1]=one
        local unknown=campingInput();unknown.recentRoutes[2].campingObservationKnown=false;cases[#cases+1]=unknown
        local following=campingInput();following.recentRoutes[2].observedEndzoneCamping=false;cases[#cases+1]=following
        local repeated=campingInput();repeated.recentRoutes[2].roundKey="first";cases[#cases+1]=repeated
        local missing=campingInput();missing.opponentVelocity=nil;cases[#cases+1]=missing
        for _,p in ipairs(cases) do assert(choose(p).payload.Pass=="Floater","unproven camping enabled a Bullet") end
    end)
    test("used or missing session allowance cannot be revived by the old cycle slot",function()
        local used=choose(campingInput({routeCycle=19,campingCounterUsed=true}))
        assert(used.payload.Pass=="Floater" and used.campingGateReason=="already_attempted")
        assert(used.campingEvidenceCount==2 and used.campingCurrentWaiting)
        local unknown=campingInput({routeCycle=19});unknown.campingCounterUsed=nil
        local c=choose(unknown)
        assert(c.payload.Pass=="Floater" and c.campingGateReason=="counter_state_unknown")
    end)
    test("unfunded or parked Bullet counter-route preserves the Floater fallback",function()
        local noBullet={pose=Planner.pose,forecastStem=Planner.forecastStem}
        noBullet.solve=function(s)
            local plan,why=Planner.solve(s)
            if plan and s.passType=="Bullet" then plan.stopAt=plan.contactAt-.01 end
            return plan,why
        end
        local c=assert(Policy.chooseScheduledRoute(campingInput(),Config,Field,RouteMath,noBullet))
        assert(c.payload.Pass=="Floater" and not c.rareBullet,"parked counter-route was admitted")
        assert(c.campingGateReason=="no_funded_counter" and c.campingEvidenceCount==2)
        c=choose(campingInput({stamina=20}))
        assert(c.payload.Pass=="Floater" and not c.rareBullet,"low stamina enabled unfunded Bullet")
        assert(c.campingGateReason=="no_funded_floater")
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
    local function narrowRouteFixture(cycle)
        -- Numeric geometry from the inset-route regression, independent of
        -- player identity. Native and authored route contracts both shorten
        -- the deepest requested sideline leg under the ink budget.
        local f={MinX=-30.2121302485466,MaxX=67.99998158216476,MidX=18.893925666809082,
            BackZ=-44.012135207653046,LOSZ=-19.459107249975204,GoalZ=103.30604553222656,
            EndZ=152.4120985865593,YD=4.910605591535568,TurfY=1.63686865568161}
        local e=setmetatable({script={Parent={Config="config",Field="field"}},
            require=function(module)
                assert(module=="config" or module=="field")
                return module=="config" and Config or f
            end},{__index=_G})
        local routeMath=assert(load(routeSource,"wide route regression","t",e))()
        local p=input({LOS=f.LOSZ,stamina=75,routeCycle=cycle or 0,
            position=Vector3.new(18.894983291625977,4.636867523193359,-20.977327346801758),
            opponentPosition=Vector3.new(18.882123947143555,4.636789321899414,20.03057861328125),
            opponentVelocity=Vector3.zero})
        return p,f,routeMath
    end
    test("deep inset route does not hide a funded sideline airborne catch",function()
        for _,cycle in ipairs({0,1}) do
            local p,f,routeMath=narrowRouteFixture(cycle)
            local c=assert(Policy.chooseScheduledRoute(p,Config,f,routeMath,Planner))
            local side=c.side
            local targetInset=side<0 and c.plan.Target.X-f.MinX or f.MaxX-c.plan.Target.X
            assert(targetInset<=Config.RouteEdgeMargin+.1,"deeper inset route ended the width search")
            assert(c.catchSidelineInset<=1.5*f.YD and c.targetSidelineInset<=f.YD)
            assert(c.stemYards>=(f.GoalZ-f.LOSZ)/f.YD*.65,"wider route cut too early")
            assert(c.reachable and c.finishReachable and c.estimatedCatchInsideGoal and c.requireAirborne)
            assert(c.finalSprintStamina>=10 and c.estimatedContactMargin>=.6)
            assert(c.estimatedStopAt>=c.estimatedFirstTouchAt and c.estimatedCatchZ>=f.GoalZ)
            assert(c.forecastCount<=50,"bounded sideline search expanded excessively")
            local points=c.payload.Points
            assert(c.sanitizedEndpointX==points[#points].X and c.ballTargetX==c.plan.Target.X)
            assert(c.estimatedCatchX>=f.MinX+.5 and c.estimatedCatchX<=f.MaxX-.5)
            assert(c.side==(cycle==0 and -1 or 1),"width preference erased available mirrored side")
        end
    end)
    test("unfunded wider catch preserves the existing reachable inset fallback",function()
        local p,f,routeMath=narrowRouteFixture(0)
        local function wide(s) return math.abs(s.arc.P1.X-f.MidX)>(f.MaxX-f.MinX)*.46 end
        local constrained={pose=Planner.pose}
        constrained.solve=function(s)
            if wide(s) then return nil,"fixture rejects wider contact" end
            return Planner.solve(s)
        end
        constrained.forecastStem=function(s,...)
            if wide(s) then return nil,"fixture rejects wider handoff" end
            return Planner.forecastStem(s,...)
        end
        local c=assert(Policy.chooseScheduledRoute(p,Config,f,routeMath,constrained))
        assert(c.reachable and c.finishReachable and not c.bestEffort,"rejected width erased funded fallback")
        local inset=c.side<0 and c.plan.Target.X-f.MinX or f.MaxX-c.plan.Target.X
        assert(inset>Config.RouteEdgeMargin+.1)
        assert(c.requireAirborne and c.estimatedCatchInsideGoal and c.finalSprintStamina>=10)
    end)
    test("post-throw stem survives native sanitation and has a funded jump witness",function()
        local c=choose(input({position=Vector3.new(0,3,-2)}))
        assert(c.postThrowStem and c.cutAt>c.plan.Launch)
        assert(c.stemSprintSeconds<=2 and c.earlyStemSprintSeconds>=.4 and c.earlyStemSprintSeconds<=.9)
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
    test("long opening sprint reallocates the late burst and later spending needs current stamina",function()
        local c=choose(input())
        assert(c.stemSprintSeconds>=.9 and c.earlyStemSprintSeconds==.9)
        local late=c.cutAt-c.stemSprintStart
        assert(math.abs(late-(c.stemSprintSeconds-.9))<1e-6 and c.stemSprintSeconds<=2)
        local p=input({phase="Live",elapsed=.75,position=Vector3.new(0,3,20),routePlan=c.plan,
            routeStrategy=c.routeStrategy,postThrowStem=c.postThrowStem,slowStem=true,slowStemTime=c.cutAt,
            stemSprintStart=c.stemSprintStart,earlyStemSprintSeconds=c.earlyStemSprintSeconds,
            estimatedStemRegeneration=c.estimatedStemRegeneration,estimatedCatchAt=c.estimatedCatchAt,
            middleStemDeep=true,routeWaypoint=2})
        assert(Policy.movement(p,Config,Field,RouteMath).sprint,"opening input ended at the old .6-second boundary")
        p.elapsed=.95;p.position=Vector3.new(0,3,26)
        assert(not Policy.movement(p,Config,Field,RouteMath).sprint,"opening input failed to release")
        p.elapsed=c.stemSprintStart+.01;p.position=Vector3.new(0,3,c.stemYards*Field.YD-15)
        local required=((c.cutAt-p.elapsed)+(c.estimatedCatchAt-c.cutAt+.12))*Config.SprintDrain+10
        p.stamina=required-1
        assert(not Policy.movement(p,Config,Field,RouteMath).sprint,"late burst borrowed future regeneration")
        p.stamina=required+.01
        assert(Policy.movement(p,Config,Field,RouteMath).sprint,"funded late burst was lost")
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
    local function partialRecoveryInput(extra)
        local p=input({phase="Live",elapsed=2,routePlan={
            Points={Vector2.new(0,0),Vector2.new(0,90),Vector2.new(-40,130)},
            Times={0,4.25,6.5},Arrival=6.5},
            routeStrategy="deep_middle_floater",slowStem=true,slowStemTime=4.25,
            stemSprintStart=3.65,earlyStemSprintSeconds=.6,estimatedCatchAt=6.3,
            middleStemDeep=true,routeWaypoint=2,position=Vector3.new(0,3,36),stamina=90,currentWalkSpeed=20})
        for k,v in pairs(extra or {}) do p[k]=v end
        return p
    end
    test("partial recovery uses idle funded budget without spending the catch allowance",function()
        local p=partialRecoveryInput()
        local originalStamina=p.stamina
        local scheduled=p.slowStemTime-p.stemSprintStart
        local final=p.estimatedCatchAt-p.slowStemTime+.12
        local required=(scheduled+final)*Config.SprintDrain+10
        assert(required+.6*Config.SprintDrain>p.stamina,"fixture already funds the full burst")
        local c=assert(Policy.movement(p,Config,Field,RouteMath))
        local expected=(p.stamina-required)/Config.SprintDrain-.12
        assert(c.sprint and math.abs(c.stemRecoverySeconds-expected)<1e-8)
        assert(c.stemRecoverySeconds>=.12 and c.stemRecoverySeconds<.6)
        assert(p.stamina-(scheduled+final+c.stemRecoverySeconds+.12)*Config.SprintDrain>=10-1e-8)
        assert(p.stamina==originalStamina,"movement invented stamina")
        assert(c.moveSpeed==Config.SprintSpeed and not c.hardCut and not c.finalSprintCommitted)
        assert(math.abs(c.routeScheduleCapacity-(Config.RunSpeed*(p.slowStemTime-p.elapsed)
            +(Config.SprintSpeed-Config.RunSpeed)*(scheduled+c.stemRecoverySeconds)))<1e-8)
        p.stemRecoveryUntil=c.stemRecoveryUntil;p.stemRecoverySpent=c.stemRecoverySeconds
        p.elapsed=p.elapsed+.05;p.stamina=p.stamina-.05*Config.SprintDrain
        local active=assert(Policy.movement(p,Config,Field,RouteMath))
        assert(active.sprint and not active.stemRecoverySeconds,"active burst was allocated twice")
        assert(math.abs(active.routeScheduleCapacity-(Config.RunSpeed*(p.slowStemTime-p.elapsed)
            +(Config.SprintSpeed-Config.RunSpeed)*(scheduled+p.stemRecoveryUntil-p.elapsed)))<1e-8,
            "active recovery and scheduled sprint were double-counted")
    end)
    test("partial recovery rejects an unfunded minimum and honors the route reserve and total cap",function()
        local p=partialRecoveryInput({stamina=85})
        assert(not Policy.movement(p,Config,Field,RouteMath).stemRecoverySeconds,
            "allocated less than the funded minimum plus dispatch allowance")
        p.stamina=90;p.routeStrategy="deep_middle_bullet";p.finalSprintReserve=30
        assert(not Policy.movement(p,Config,Field,RouteMath).stemRecoverySeconds,"spent the carry move reserve")
        p.routeStrategy="deep_middle_floater";p.finalSprintReserve=10;p.stemRecoverySpent=.49
        assert(not Policy.movement(p,Config,Field,RouteMath).stemRecoverySeconds,"exceeded the remaining route cap")
        p.stemRecoverySpent=.6
        assert(not Policy.movement(p,Config,Field,RouteMath).stemRecoverySeconds,"restarted an exhausted cap")
        p.stemRecoverySpent=.4
        local limited=assert(Policy.movement(p,Config,Field,RouteMath))
        assert(limited.stemRecoverySeconds and p.stemRecoverySpent+limited.stemRecoverySeconds<=.6+1e-8)
    end)
    test("new partial recovery needs observed normal speed while previously funded bursts are unchanged",function()
        local p=partialRecoveryInput()
        for _,speed in ipairs({9,12.15,0,math.huge,0/0}) do
            p.currentWalkSpeed=speed
            assert(not Policy.movement(p,Config,Field,RouteMath).stemRecoverySeconds,
                "partial recovery spent stamina during a native slowdown or invalid observation")
        end
        p.currentWalkSpeed=nil
        assert(not Policy.movement(p,Config,Field,RouteMath).stemRecoverySeconds,"unknown native speed funded partial recovery")
        p.currentWalkSpeed=27;assert(Policy.movement(p,Config,Field,RouteMath).stemRecoverySeconds)
        p.currentWalkSpeed=9;p.stamina=100
        local existing=assert(Policy.movement(p,Config,Field,RouteMath))
        assert(existing.stemRecoverySeconds==.6,"new partial guard changed an existing fully funded burst")
    end)
    test("recovery ends before scheduled sprint and cannot begin after throw or a committed cut",function()
        local p=partialRecoveryInput({elapsed=3.52,stamina=100})
        local nearLate=assert(Policy.movement(p,Config,Field,RouteMath))
        assert(nearLate.stemRecoveryUntil and nearLate.stemRecoveryUntil<=p.stemSprintStart+1e-8)
        p.stemRecoveryUntil=nearLate.stemRecoveryUntil;p.stemRecoverySpent=nearLate.stemRecoverySeconds
        p.elapsed=p.stemSprintStart+.01
        local late=assert(Policy.movement(p,Config,Field,RouteMath))
        assert(late.sprint and not late.stemRecoverySeconds)
        assert(math.abs(late.routeScheduleCapacity-Config.SprintSpeed*(p.slowStemTime-p.elapsed))<1e-8,
            "expired recovery was added to scheduled sprint")
        p=partialRecoveryInput({ballActive=true,passStarted=true,allowPostThrowStem=true,postThrowStem=true})
        assert(not Policy.movement(p,Config,Field,RouteMath).stemRecoverySeconds,"invented post-throw recovery")
        p=partialRecoveryInput({finalSprintCommitted=true})
        local committed=assert(Policy.movement(p,Config,Field,RouteMath))
        assert(committed.finalSprintCommitted and not committed.stemRecoverySeconds,"reopened the committed stem")
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
    test("opening reallocation retains funded Floaters across remaining field lengths",function()
        for _,yards in ipairs({25,20,15,10,6,3,1,.25}) do
            local los=Field.GoalZ-yards*Field.YD
            local c=choose(input({LOS=los,position=Vector3.new(0,3,los-2)}))
            assert(c.payload.Pass=="Floater" and c.reachable and not c.bestEffort,"lost funded Floater at "..yards)
            assert(c.stemSprintSeconds<=2 and c.earlyStemSprintSeconds<=.9)
            assert(math.abs(c.earlyStemSprintSeconds+c.cutAt-c.stemSprintStart-c.stemSprintSeconds)<1e-6)
            assert(not c.postThrowStem or c.plan.Launch+.1>=c.earlyStemSprintSeconds,
                "opening burst escaped the post-throw prefix budget")
            assert(c.finalSprintStamina>=10 and c.estimatedStopAt>=c.estimatedFirstTouchAt)
            assert(c.estimatedCatchZ>=Field.GoalZ+.25 and c.ballTargetZ>=Field.GoalZ+4*Field.YD)
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
    test("setup stamina budgets preserve lower actual values and reject invalid observations",function()
        assert(Policy.setupStaminaBudget(100,Config)==75)
        assert(Policy.setupStaminaBudget(75,Config)==75)
        assert(Policy.setupStaminaBudget(100,Config,60)==60)
        assert(Policy.setupStaminaBudget(30,Config,60)==30)
        assert(Policy.setupStaminaBudget(0,Config)==0 and Policy.setupStaminaBudget(0/0,Config)==0)
        assert(Policy.setupStaminaBudget(100,Config,math.huge)==75)
        assert(Policy.setupStaminaBudget(100,Config,-1)==75)
        assert(Policy.setupStaminaBudget(200,{Stamina=200})==150,"allowance assumed fixed native maximum")
    end)
    test("reduced setup stamina funds an executable opening and only bounded rest regeneration",function()
        local c=choose(input({stamina=75}))
        assert(c.reachable and not c.bestEffort and c.estimatedCatchStamina>=10)
        local deficit=Config.Stamina-75
        local opening=c.earlyStemSprintSeconds*Config.SprintDrain
        local rest=math.max(0,c.stemSprintStart-c.earlyStemSprintSeconds-Config.RegenDelay-.2)
        assert(c.estimatedStemRegeneration<=deficit+opening+1e-8)
        assert(c.estimatedStemRegeneration<=rest*Config.StaminaRegen+1e-8)
        assert(75>=opening+10,"future regeneration funded an unaffordable opening")
        local p=input({phase="Live",elapsed=.1,position=Vector3.new(0,3,0),stamina=75,currentWalkSpeed=20,
            routePlan=c.plan,routeStrategy=c.routeStrategy,slowStem=true,slowStemTime=c.cutAt,
            earlyStemSprintSeconds=c.earlyStemSprintSeconds,stemSprintStart=c.stemSprintStart,
            estimatedStemRegeneration=c.estimatedStemRegeneration,estimatedCatchAt=c.estimatedCatchAt,
            finalSprintReserve=c.finalSprintReserve,middleStemDeep=true,routeWaypoint=2})
        assert(Policy.movement(p,Config,Field,RouteMath).sprint,"funded opening was suppressed at actual75")
        p.stamina=0
        assert(not Policy.movement(p,Config,Field,RouteMath).sprint,"future refill spent unavailable opening stamina")
    end)
    test("missing or disabled regeneration cannot fund a low-budget route",function()
        local oldRate,oldDelay=Config.StaminaRegen,Config.RegenDelay
        for _,value in ipairs({0,-1,0/0}) do
            Config.StaminaRegen=value
            local c=choose(input({stamina=75}))
            assert(not c.estimatedStemRegeneration or c.estimatedStemRegeneration==0)
        end
        Config.StaminaRegen=oldRate;Config.RegenDelay=nil
        local c=choose(input({stamina=75}))
        assert(not c.estimatedStemRegeneration or c.estimatedStemRegeneration==0)
        Config.RegenDelay=oldDelay
        local low=choose(input({stamina=0}))
        assert(low.bestEffort or not low.reachable,"regeneration invented an executable zero-stamina opening")
    end)
    Vector2,typeof=oldVector2,oldTypeof
    return report
end
