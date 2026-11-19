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
    local function choose(value) return assert(Policy.chooseScheduledRoute(value,Config,Field,RouteMath)) end
    test("fixed five-play schedule defaults to four middle stems and one quarter stem",function()
        local counts={middle_stem=0,quarter_stem=0}
        for i=0,19 do
            local c=choose(input({selectionIndex=i}))
            assert(c.routeFamily,"family fallback at "..i..": "..tostring(c.scheduleOverride))
            assert(c.routeFamily==(i%5==4 and "quarter_stem" or "middle_stem"))
            assert(c.scheduleOverride==nil)
            counts[c.routeFamily]=counts[c.routeFamily]+1
        end
        assert(counts.middle_stem==16 and counts.quarter_stem==4)
    end)
    test("ordinary center DB two yards ahead retains the four-to-one default schedule",function()
        local counts={middle_stem=0,quarter_stem=0}
        for i=0,19 do
            local c=choose(input({selectionIndex=i,opponentPosition=Vector3.new(0,3,2*Field.YD),
                opponentVelocity=Vector3.zero}))
            assert(c.routeFamily==(i%5==4 and "quarter_stem" or "middle_stem"))
            assert(c.scheduleOverride==nil and not c.stemBlocked)
            counts[c.routeFamily]=counts[c.routeFamily]+1
        end
        assert(counts.middle_stem==16 and counts.quarter_stem==4)
    end)
    test("reachable middle routes use three Floaters and one Bullet with ordinary center coverage",function()
        for _,defender in ipairs({false,Vector3.new(0,3,2*Field.YD)}) do
            local counts={Floater=0,Bullet=0}
            for i=0,19 do
                local c=choose(input({selectionIndex=i,opponentPosition=defender or nil,
                    opponentVelocity=Vector3.zero}))
                if i%5~=4 then
                    local expected=i%5==3 and "Bullet" or "Floater"
                    assert(c.routeFamily=="middle_stem" and c.payload.Pass==expected)
                    assert(c.scheduledPass==expected and c.passPreferenceOverride==nil)
                    assert(not c.anticipatedLane and not c.stemBlocked)
                    assert(c.finalSprintStamina>=10 and c.cutAt<=c.plan.Launch+.015)
                    if expected=="Floater" then
                        assert(c.stemYards>=12 and c.depth>=24,"preferred Floater cut too early or shortened the route")
                    end
                    counts[c.payload.Pass]=counts[c.payload.Pass]+1
                end
            end
            assert(counts.Floater==12 and counts.Bullet==4)
        end
    end)
    test("middle Floater preference falls back when its final sprint cannot be funded",function()
        local c=choose(input({selectionIndex=0,stamina=90,
            opponentPosition=Vector3.new(0,3,2*Field.YD),opponentVelocity=Vector3.zero}))
        assert(c.routeFamily=="middle_stem" and c.payload.Pass=="Bullet")
        assert(c.scheduledPass=="Floater" and c.passPreferenceOverride=="preferred_pass_unreachable")
        assert(c.finalSprintStamina>=10 and c.cutAt<=c.plan.Launch+.015)
    end)
    test("a deep defender waiting on the preferred Floater lane changes that route",function()
        local before=choose(input({selectionIndex=0}))
        assert(before.payload.Pass=="Floater")
        local waiting=before.payload.Points[2]:Lerp(before.plan.Target,.85)
        local after=choose(input({selectionIndex=0,
            opponentPosition=Vector3.new(waiting.X,3,waiting.Y),opponentVelocity=Vector3.zero}))
        assert(not after.anticipatedLane and not after.stemBlocked)
        assert(after.side~=before.side or after.routeFamily~=before.routeFamily
            or after.payload.Pass~=before.payload.Pass or after.payload.StartX~=before.payload.StartX,
            "Floater preference ignored observed deep coverage")
        assert(after.finalSprintStamina>=10 and after.cutAt<=after.plan.Launch+.015)
    end)
    test("actual close center jam may override the scheduled middle family",function()
        local c=choose(input({opponentPosition=Vector3.new(0,3,.8*Field.YD),opponentVelocity=Vector3.zero}))
        assert(c.routeFamily=="quarter_stem" and c.scheduleOverride=="observed_lane_coverage")
    end)
    test("a slow defender deep on a tight middle stem selects a clear alternative",function()
        for _,velocity in ipairs({Vector3.zero,Vector3.new(-4.96,0,-10.89),Vector3.new(2.49,0,-11.74)}) do
            local c=choose(input({position=Vector3.new(0,3,-1.52),
                opponentPosition=Vector3.new(0,3,8*Field.YD),opponentVelocity=velocity}))
            assert(c.routeFamily=="quarter_stem" and c.scheduleOverride=="observed_lane_coverage")
            assert(not c.stemBlocked and not c.anticipatedLane)
            assert(c.finalSprintStamina>=10 and c.cutAt<=c.plan.Launch+.015)
        end
    end)
    test("quarter starts occupy actual quarter width and never finish straight",function()
        local starts,turns={},{}
        for _,index in ipairs({4,9,14,19}) do
            local c=choose(input({selectionIndex=index}))
            assert(c.routeFamily=="quarter_stem")
            local x=c.payload.StartX
            assert(math.abs(math.abs(x)-24.5)<1e-6)
            assert(c.payload.Points[1].X==x and c.payload.Points[2].X==x)
            assert(math.abs(c.payload.Points[3].X-x)>=2*Field.YD)
            starts[x<0 and "left" or "right"]=true;turns[c.cutDirection]=true
        end
        assert(starts.left and starts.right,"quarter starting side never changes")
        assert(turns.same_side and turns.opposite_side,"quarter cut direction never changes")
    end)
    test("every scheduled final sprint is funded through native arrival plus dispatch",function()
        for _,stamina in ipairs({100,95,90,80,65,40,10,0}) do
            for i=0,4 do
                local c,reason=Policy.chooseScheduledRoute(input({selectionIndex=i,stamina=stamina}),Config,Field,RouteMath)
                if c then
                    assert(c.routeFamily)
                    assert(c.slowStemSpeed<=Config.RunSpeed and c.slowStemSpeed>=Config.RunSpeed*.25)
                    assert(c.finalSprintStamina>=10-1e-6)
                    assert(math.abs(c.finalSprintDuration-(c.plan.Arrival-c.cutAt+.12))<1e-6)
                    assert(stamina-c.finalSprintDuration*Config.SprintDrain>=10-1e-6)
                    assert(c.cutAt<=c.plan.Launch+.015 and c.cutAt>0)
                    assert(c.preferAirborne and c.preferJumpDive and not c.requireDive)
                else assert(type(reason)=="string" and reason:find("No cut route",1,true)) end
            end
        end
    end)
    test("repeated actual contests override the preferred route family",function()
        local c=choose(input({recentRoutes={{routeFamily="middle_stem",result="Swatted",success=false},
            {routeFamily="middle_stem",result="Intercepted",success=false}}}))
        assert(c.routeFamily=="quarter_stem" and c.scheduleOverride=="recent_contests")
    end)
    test("explicit incompletes change the failed lane then repeated failures change family",function()
        local before=choose(input())
        local failure={routeFamily="middle_stem",pass=before.payload.Pass,side=before.side,
            result="Incomplete",success=false}
        local once=choose(input({recentRoutes={failure}}))
        assert(once.routeFamily=="middle_stem" and once.side~=before.side)
        local twice=choose(input({recentRoutes={failure,failure}}))
        assert(twice.routeFamily=="quarter_stem" and twice.scheduleOverride=="recent_contests")
        local unknown=choose(input({recentRoutes={{routeFamily="middle_stem",pass=before.payload.Pass,
            side=before.side,result="Unknown",success=false}}}))
        assert(unknown.routeFamily==before.routeFamily and unknown.side==before.side and unknown.scheduleOverride==nil)
    end)
    test("a defender waiting in the intended lane changes the route or family",function()
        local before=choose(input())
        local a,b=before.payload.Points[2],before.plan.Target
        local waiting=a:Lerp(b,.65)
        local after=choose(input({opponentPosition=Vector3.new(waiting.X,3,waiting.Y),opponentVelocity=Vector3.zero}))
        assert(after.routeFamily and (after.side~=before.side or after.routeFamily~=before.routeFamily
            or after.payload.StartX~=before.payload.StartX),"kept running into the observed lane")
        assert(not after.anticipatedLane,"selected another visibly anticipated lane")
    end)
    test("schedule uses field coordinates consistently across translated arenas",function()
        local a=choose(input({selectionIndex=4}))
        local b=choose(input({selectionIndex=4,offset=Vector3.new(300,0,-200),position=Vector3.new(300,3,-200)}))
        assert(a.routeFamily==b.routeFamily and a.cutDirection==b.cutDirection and a.payload.StartX==b.payload.StartX)
        for i,p in ipairs(a.payload.Points) do assert((p-b.payload.Points[i]).Magnitude<1e-8) end
    end)
    test("setup steering moves to submitted start through normal unsprinted movement",function()
        for _,startX in ipairs({0,-24.5,24.5}) do
            local p=input({position=Vector3.new(10,3,0),startX=startX})
            local c=assert(Policy.movement(p,Config,Field,RouteMath))
            assert(c.kind=="lineup" and c.target.X==startX and not c.sprint)
            p.phase="Hike";c=assert(Policy.movement(p,Config,Field,RouteMath))
            assert(c.kind=="lineup" and c.target.X==startX and not c.sprint)
        end
    end)
    test("live stem slows before a blocker while retaining the final sprint deadline",function()
        local c=choose(input())
        local p=input({phase="Live",elapsed=.1,routePlan=c.plan,middleStemDeep=true,slowStem=true,
            slowStemTime=c.cutAt,routeWaypoint=2,position=Vector3.new(c.payload.StartX,3,1)})
        local clear=assert(Policy.movement(p,Config,Field,RouteMath))
        p.opponentPosition=Vector3.new(c.payload.StartX,3,6);p.opponentVelocity=Vector3.zero
        local blocked=assert(Policy.movement(p,Config,Field,RouteMath))
        assert(not blocked.sprint and blocked.moveSpeed<=clear.moveSpeed and blocked.routeDeadline==c.cutAt)
        p.elapsed=c.cutAt+.01;p.stamina=100;p.opponentPosition=nil
        local final=assert(Policy.movement(p,Config,Field,RouteMath))
        assert(final.sprint and final.finalSprintCommitted and final.moveSpeed==Config.SprintSpeed)
    end)
    test("the three observed late stem states do not spend more deadline time slowing to seven",function()
        local plan={Points={Vector2.new(0,0),Vector2.new(0,60),Vector2.new(48,120)},
            Times={0,3,6},Arrival=6.258876}
        for _,state in ipairs({{.965,12.764,6.347},{.705,8.086,6.428},{1.110,15.455,6.008}}) do
            local p=input({phase="Live",elapsed=state[1],position=Vector3.new(0,3,state[2]),
                opponentPosition=Vector3.new(0,3,state[2]+state[3]),opponentVelocity=Vector3.zero,
                routePlan=plan,middleStemDeep=true,slowStem=true,slowStemTime=2.985462,routeWaypoint=2})
            local c=assert(Policy.movement(p,Config,Field,RouteMath))
            assert(c.moveSpeed==Config.RunSpeed and not c.sprint and c.routeWaypoint==2)
            assert(c.routeTimingDebt and c.routeTimingReason=="observed_stem_delay")
        end
    end)
    test("body pacing can still slow when actual remaining distance leaves spare time",function()
        local plan={Points={Vector2.new(0,0),Vector2.new(0,30),Vector2.new(48,100)},
            Times={0,3,6},Arrival=6}
        local p=input({phase="Live",elapsed=.2,position=Vector3.new(0,3,20),
            opponentPosition=Vector3.new(0,3,26),opponentVelocity=Vector3.zero,
            routePlan=plan,middleStemDeep=true,slowStem=true,slowStemTime=3,routeWaypoint=2})
        local c=assert(Policy.movement(p,Config,Field,RouteMath))
        assert(c.moveSpeed<=7 and not c.sprint and not c.routeTimingDebt)
        assert((c.target-p.position).Magnitude<=7*(3-.2-.12))
    end)
    test("stem deception uses only reachable spare walking time and never moves into the defender",function()
        local plan={Points={Vector2.new(0,0),Vector2.new(0,30),Vector2.new(48,100)},Times={0,3,6},Arrival=6}
        local p=input({phase="Live",elapsed=.2,routePlan=plan,middleStemDeep=true,slowStem=true,
            slowStemTime=3,routeWaypoint=2,routeFamily="middle_stem",routeSide=1,
            position=Vector3.new(0,3,0),opponentPosition=Vector3.new(10,3,-5),opponentVelocity=Vector3.zero})
        local c=assert(Policy.movement(p,Config,Field,RouteMath))
        assert(c.stemFeint and c.target.X<0 and c.target.Z>0 and not c.sprint)
        assert(c.routeDeadline==3 and c.moveSpeed<=Config.RunSpeed)
        p.elapsed=2.7;c=assert(Policy.movement(p,Config,Field,RouteMath))
        assert(not c.stemFeint,"late deception spent the catch window")
        p.elapsed=.2;p.opponentPosition=Vector3.new(-3,3,10)
        c=assert(Policy.movement(p,Config,Field,RouteMath));assert(not c.stemFeint,"feint ran into the blocker")
        p.opponentPosition=Vector3.new(0,3,4)
        c=assert(Policy.movement(p,Config,Field,RouteMath));assert(not c.stemFeint,"feint crossed the defender between endpoints")
    end)
    test("DB holds a small flexible live cushion without sprinting to chase an offset",function()
        local p=input({role="DB",phase="Live",elapsed=5,position=Vector3.new(0,3,27.5),
            opponentPosition=Vector3.new(0,3,30),opponentVelocity=Vector3.zero})
        local c=assert(Policy.movement(p,Config,Field,RouteMath))
        assert(c.target.Z==p.position.Z and not c.sprint)
        p.position=Vector3.new(0,3,33);c=assert(Policy.movement(p,Config,Field,RouteMath))
        assert(c.target.Z==33 and not c.sprint,"nearby goal-side position was needlessly erased")
        p.position=Vector3.new(0,3,10);p.opponentVelocity=Vector3.new(0,0,27)
        c=assert(Policy.movement(p,Config,Field,RouteMath));assert(c.sprint and c.target.Z>10)
        p.stamina=39;c=assert(Policy.movement(p,Config,Field,RouteMath));assert(not c.sprint)
    end)
    Vector2,typeof=oldVector2,oldTypeof
    report.fixture="Authored geometry and local native/approximate route timing. No server catch or win guarantee."
    return report
end
