-- Authored geometry and extracted controller lifetime checks only.
-- No native game source, input, network, or server outcome is simulated.
return function(Planner,source)
    local report={total=0,passed=0,failed=0,results={}}
    local function test(name,body)
        report.total=report.total+1
        local ok,err=pcall(body)
        report[ok and "passed" or "failed"]=report[ok and "passed" or "failed"]+1
        report.results[#report.results+1]={name=name,passed=ok,error=not ok and tostring(err) or nil}
    end
    local function fixture()
        local s={now=100.2,launchAt=100,role="WR",passType="Floater",
            arc={P0=Vector3.new(0,6,-30),P1=Vector3.new(20,3.5,65),Flight=3.1,Apex=42},
            position=Vector3.new(0,3,0),velocity=Vector3.new(0,0,20),lookDirection=Vector3.new(0,0,1),
            grounded=true,canJump=true,canDive=true,jumpSpeed=math.sqrt(2*196.2*6),gravity=196.2,
            walkSpeed=27,runSpeed=20,sprintSeconds=4,groundRootY=3,turfY=0,diveDistance=14.7,
            maxHorizon=3,margin=.4,requireAirborne=true,preferAirborne=true,chase=true,allowHold=false,
            bounds={minX=-50,maxX=50,minZ=-50,maxZ=80},
            config={CatchRadius=3.75,DiveCatchRadius=2.5,WaistDrop=1,HandOffset=.5,
                HandUpOffset=3.5,DiveReach=2.4,Moves={Dive={Time=.35,Tip=.5,Ground=.75,GetUp=.35}}}}
        return s,{point=Vector3.new(0,3,10),untilAt=100.8,sprintStartAt=100.5,sprintDrain=25,reserve=10}
    end
    test("funded actual state permits only a robust airborne jump after the stem",function()
        local s,stage=fixture()
        local w,why=Planner.forecastStem(s,stage,100)
        assert(w,why)
        assert(w.plan.kind=="jump" and w.plan.airborneFinish=="jump" and not w.plan.diveAt)
        assert(w.plan.margin>=s.margin and not w.plan.risk)
        assert(w.plan.jumpAt>=stage.untilAt and w.plan.firstTouchAt>=w.plan.jumpAt)
        assert(w.staminaAfterCatch>=stage.reserve)
        assert(w.projected.canDive==false and w.projected.reactionDelay==.12)
        assert(s.now==100.2 and s.position==Vector3.new(0,3,0) and s.canDive==true,
            "Forecast must not mutate the live snapshot")
        assert(stage.point==Vector3.new(0,3,10))
    end)
    test("unknown nonfinite and expired stage timing fails closed",function()
        for _,key in ipairs({"untilAt","sprintStartAt","sprintDrain","reserve"}) do
            for _,value in ipairs({false,0/0,math.huge,-math.huge}) do
                local s,stage=fixture();stage[key]=value
                local ok,w=pcall(Planner.forecastStem,s,stage,100)
                assert(ok and w==nil,key.." accepted invalid timing or threw")
            end
            local s,stage=fixture();stage[key]=nil
            assert(Planner.forecastStem(s,stage,100)==nil)
        end
        for _,untilAt in ipairs({100.2,100.23,102.21,102.99}) do
            local s,stage=fixture();stage.untilAt=untilAt
            assert(Planner.forecastStem(s,stage,100)==nil)
        end
    end)
    test("low current stamina cannot borrow an old final sprint budget",function()
        local s,stage=fixture()
        for _,stamina in ipairs({0,10,20,0/0,math.huge}) do
            assert(Planner.forecastStem(s,stage,stamina)==nil)
        end
        assert(Planner.forecastStem(s,stage,nil)==nil)
    end)
    test("observed slowdown denies an otherwise funded nominal stem",function()
        local s,stage=fixture();assert(Planner.forecastStem(s,stage,100))
        s.walkSpeed=12.15;s.runSpeed=9
        local w,why=Planner.forecastStem(s,stage,100)
        assert(not w and why=="Middle stem is behind schedule")
    end)
    test("actual grounding and jump availability are required",function()
        local s,stage=fixture();s.grounded=false
        assert(Planner.forecastStem(s,stage,100)==nil)
        s,stage=fixture();s.canJump=false
        assert(Planner.forecastStem(s,stage,100)==nil)
        s,stage=fixture();s.grounded=nil
        assert(Planner.forecastStem(s,stage,100)==nil)
        s,stage=fixture();s.role="DB"
        assert(Planner.forecastStem(s,stage,100)==nil)
    end)
    test("standing contact during the stem immediately needs catch ownership",function()
        local s,stage=fixture()
        s.arc={P0=Vector3.new(0,3,5),P1=Vector3.new(0,3,5),Flight=3.1,Apex=0}
        local w,why=Planner.forecastStem(s,stage,100)
        assert(not w and why=="Ball requires catching control now")
    end)
    test("out of bounds or already reached stem does not extend movement",function()
        local s,stage=fixture();stage.point=Vector3.new(51,3,10)
        assert(Planner.forecastStem(s,stage,100)==nil)
        s,stage=fixture();stage.point=s.position
        assert(Planner.forecastStem(s,stage,100)==nil)
        s,stage=fixture();stage.point=Vector3.new(0/0,3,10)
        assert(Planner.forecastStem(s,stage,100)==nil)
    end)
    test("an unreachable later ball cannot authorize the intermediate stage",function()
        local s,stage=fixture();s.arc.P1=Vector3.new(500,3.5,500)
        assert(Planner.forecastStem(s,stage,100)==nil)
    end)
    local section=assert(source:match("(    local function updatePostThrowStem.-)    local function updateWRReturn"),
        "Production post-throw stage function not found")
    local smooth=assert(source:match("(    local function smoothDirection.-)    local function avoidPlayers"))
    local catchMove=assert(source:match("(                h:Move%(avoid.active and avoid.direction.-,false%))"),
        "Production catch avoidance/steering dispatch not found")
    local routeCut=assert(source:match("(        if directive.hardCut==true.-)        return true,avoid.active"))
    local reset=assert(source:match("            (stemFinished,stemForecast,nextStemCheck,stemLastSpeed,stemLastSprint=false,nil,0,nil,nil)"),
        "Production per-throw reset not found")
    reset=reset..";"..assert(source:match("            (stemLastRun,stemLastStage=nil,nil)"))
    reset=reset..";"..assert(source:match("            (stemWasActive=false)"))
    local harnessFactory=assert(loadstring([[
        return function(stemSprintSeconds)
            local state={now=100.2,walkSpeed=27,runSpeed=20,sprintPending=false,grounded=true,canJump=true,
                stamina=100,forecastCalls=0,moves=0,canMove=true,valid=true,logs={}}
            local stemFinished,stemForecast,nextStemCheck,stemLastSpeed,stemLastSprint=false,nil,0,nil,nil
            local stemLastRun,stemLastStage,stemWasActive
            local steering=Vector3.new(0,0,1)
            local avoidanceState={sentinel=true}
            local originalAvoidance=avoidanceState
            local plan,jumped,jumpRequest,dived,message=nil,false,nil,false,nil
            local nextSolve=99
            local root={Position=Vector3.new(0,3,0)}
            local h={PlatformStand=false,FloorMaterial=Enum.Material.Grass}
            function h:Move(direction)state.lastMove=direction end
            local Moves={Upright=function()return not h.PlatformStand end}
            local function motionState()return {grounded=state.grounded,physicalAirborne=not state.grounded}end
            local oldTypeof=typeof
            local function typeof(v) return type(v)=="table" and v._v2 and "Vector2" or oldTypeof(v) end
            local s={role="WR",offset=Vector3.zero,catchIntent={postThrowStem={
                point={X=0,Y=10,_v2=true},untilAt=100.8,sprintStartAt=100.5,sprintDrain=25,reserve=10}}}
            local me={GetAttribute=function(_,name)
                if name=="Stamina" then return state.stamina end
                assert(name=="SprintOn");return false
            end}
            local workspace={GetServerTimeNow=function()return state.now end}
            local function snapshot()
                return {now=state.now,walkSpeed=state.walkSpeed,runSpeed=state.runSpeed,
                    sprintPending=state.sprintPending,grounded=state.grounded,canJump=state.canJump}
            end
            local Planner={stemSprintSeconds=stemSprintSeconds,forecastStem=function(fresh,stage,stamina)
                state.forecastCalls=state.forecastCalls+1
                if not state.valid or not fresh.canJump or stamina<30 or fresh.runSpeed<10 then
                    return nil,"No current witness"
                end
                return {plan={contactAt=102.9},staminaAfterCatch=35}
            end}
            local function updateFullplay(copy)
                assert(copy.allowPostThrowStem==true)
                state.moves=state.moves+1
                return state.canMove,"Stage movement"
            end
            local function xyz(v)return {x=v.X,y=v.Y,z=v.Z}end
            local function log(kind,data)state.logs[#state.logs+1]={kind=kind,data=data}end
    ]]..smooth..section..[[
            local api={state=state,context=s,humanoid=h}
            function api.tick(at) state.now=at or state.now;return updatePostThrowStem(s,root,h,state.now,.016) end
            function api.newThrow() ]]..reset..[[;plan=nil;jumped=false;jumpRequest=nil;dived=false end
            function api.setCatchState(value)
                plan=value=="plan" and {} or nil
                jumped=value=="jumped";jumpRequest=value=="request" and {} or nil;dived=value=="dived"
            end
            function api.finished()return stemFinished,nextSolve end
            function api.steering()return steering end
            function api.avoidancePreserved()return avoidanceState==originalAvoidance end
            function api.move(desired,active,dt)
                dt=dt or .016
                local avoid={direction=desired,active=active==true}
    ]]..catchMove..[[
                return state.lastMove
            end
            function api.routeMove(desired,hardCut,active,dt)
                dt=dt or .016
                local directive={hardCut=hardCut}
                local flat=desired
                local strength=math.min(flat.Magnitude,1)
                local avoid={direction=desired,active=active==true}
    ]]..routeCut..[[
                return state.lastMove
            end
            return api
        end
    ]]))()
    local function harness() return harnessFactory(Planner.stemSprintSeconds) end
    test("first invalid witness hands off permanently for that throw",function()
        local h=harness();h.state.valid=false
        assert(not h.tick() and h.finished())
        h.state.valid=true
        assert(not h.tick(100.4) and h.state.forecastCalls==1 and h.state.moves==0)
        h.newThrow();h.context.catchIntent.postThrowStem.untilAt=101
        assert(h.tick(100.41) and h.state.forecastCalls==2)
    end)
    test("catch action ownership or platform stand prevents stem movement",function()
        for _,kind in ipairs({"plan","jumped","request","dived"}) do
            local h=harness();h.setCatchState(kind)
            assert(not h.tick() and h.finished() and h.state.moves==0)
        end
        local h=harness();h.humanoid.PlatformStand=true
        assert(not h.tick() and h.finished() and h.state.moves==0)
    end)
    test("missing intent or invalid point cannot begin a stage",function()
        local h=harness();h.context.catchIntent=nil
        assert(not h.tick() and h.finished())
        h=harness();h.context.catchIntent.postThrowStem.point=Vector3.zero
        assert(not h.tick() and h.finished() and h.state.moves==0)
        for _,value in ipairs({true,42,"invalid"}) do
            h=harness();h.context.catchIntent.postThrowStem=value
            assert(not h.tick() and h.finished() and h.state.moves==0)
        end
    end)
    test("deadline and loss of route movement release catch control immediately",function()
        local h=harness();assert(h.tick());assert(not h.tick(100.77) and h.finished())
        local _,nextSolve=h.finished();assert(nextSolve==0)
        h=harness();h.state.canMove=false
        assert(not h.tick() and h.finished())
        h.state.canMove=true;assert(not h.tick(100.4))
    end)
    test("grounding loss releases even inside the witness cache interval",function()
        local h=harness();assert(h.tick());h.state.grounded=false
        assert(not h.tick(100.21) and h.finished())
    end)
    test("native speed change rechecks the forecast before moving",function()
        local h=harness();assert(h.tick());h.state.walkSpeed=12.15;h.state.valid=false
        assert(not h.tick(100.21) and h.finished() and h.state.moves==1)
    end)
    test("jump availability loss invalidates a cached witness before moving",function()
        local h=harness();assert(h.tick());h.state.canJump=false
        assert(not h.tick(100.21) and h.finished() and h.state.moves==1)
    end)
    test("insufficient current stamina invalidates a cached witness before moving",function()
        local h=harness();assert(h.tick());h.state.stamina=20
        assert(not h.tick(100.21) and h.finished() and h.state.moves==1)
    end)
    test("run speed change invalidates a cached witness before moving",function()
        local h=harness();assert(h.tick());h.state.runSpeed=9
        assert(not h.tick(100.21) and h.finished() and h.state.moves==1)
    end)
    test("changed stage values cannot reuse the previous geometry witness",function()
        for _,change in ipairs({
            function(stage)stage.point={X=1,Y=10,_v2=true}end,
            function(stage)stage.untilAt=100.79 end,
            function(stage)stage.sprintStartAt=100.49 end,
            function(stage)stage.reserve=11 end,
            function(stage)stage.sprintDrain=26 end,
        }) do
            local h=harness();assert(h.tick());change(h.context.catchIntent.postThrowStem)
            h.state.valid=false
            assert(not h.tick(100.21) and h.finished() and h.state.forecastCalls==2 and h.state.moves==1)
        end
    end)
    test("cached path that falls behind capacity hands off without another move",function()
        local h=harness();assert(h.tick())
        -- No physical progress is credited by this fixture. The remaining
        -- observed capacity must eventually reject the old witness.
        assert(not h.tick(100.49) and h.finished() and h.state.moves==1)
    end)
    local function close(a,b) return (a-b).Magnitude<1e-8 end
    local function hardCuts(h)
        local count=0
        for _,item in ipairs(h.state.logs) do if item.kind=="wrHardCut" then count=count+1 end end
        return count
    end
    test("grounded stem handoff commits one clear ninety-degree input then smooths corrections",function()
        local h=harness();assert(h.tick());assert(h.tick(100.21))
        assert(hardCuts(h)==0 and close(h.steering(),Vector3.new(0,0,1)))
        assert(not h.tick(100.77) and h.steering()==nil and hardCuts(h)==1)
        local cut=h.move(Vector3.new(1,0,0),false)
        assert(close(cut,Vector3.new(1,0,0)),"First clear cut still retained the previous heading")
        local nextDirection=h.move(Vector3.new(0,0,-1),false)
        assert(nextDirection.X>.98 and nextDirection.Z<0 and nextDirection.Z>-.2,
            "Later correction must retain the production turn-rate limit")
        assert(not h.tick(100.79) and hardCuts(h)==1)
        local later=h.move(Vector3.new(0,0,-1),false)
        assert(later.Z<nextDirection.Z and later.X>0 and hardCuts(h)==1)
    end)
    test("handoff preserves avoidance and its movement command wins over the clear-cut direction",function()
        local h=harness();assert(h.tick());assert(not h.tick(100.77))
        assert(h.avoidancePreserved())
        local avoiding=Vector3.new(-.4,0,.6)
        assert(close(h.move(avoiding,true),avoiding) and h.steering()==nil)
        assert(h.avoidancePreserved() and hardCuts(h)==1)
        assert(close(h.move(Vector3.new(1,0,0),false),Vector3.new(1,0,0)))
    end)
    test("unstarted DB airborne and committed-action stages do not reset steering",function()
        local h=harness();h.state.valid=false;assert(not h.tick())
        assert(hardCuts(h)==0 and h.steering()~=nil)
        for _,kind in ipairs({"DB","airborne","platform","plan","jumped","request","dived"}) do
            h=harness();assert(h.tick())
            if kind=="DB" then h.context.role="DB"
            elseif kind=="airborne" then h.state.grounded=false;h.humanoid.FloorMaterial=Enum.Material.Air
            elseif kind=="platform" then h.humanoid.PlatformStand=true
            else h.setCatchState(kind) end
            assert(not h.tick(100.21))
            assert(hardCuts(h)==0 and close(h.steering(),Vector3.new(0,0,1)),kind.." reset steering")
            assert(h.avoidancePreserved())
        end
    end)
    test("route hard-cut uses actual dispatch while later route corrections remain smooth",function()
        local h=harness()
        assert(close(h.routeMove(Vector3.new(1,0,0),true,false),Vector3.new(1,0,0)))
        assert(hardCuts(h)==1 and h.avoidancePreserved())
        local later=h.routeMove(Vector3.new(0,0,-1),false,false)
        assert(later.X>.98 and later.Z<0 and later.Z>-.2 and hardCuts(h)==1)
    end)
    test("route hard-cut does not override avoidance or non-WR airborne action gates",function()
        for _,kind in ipairs({"avoidance","DB","airborne","platform","jumped","request","dived"}) do
            local h=harness()
            if kind=="DB" then h.context.role="DB"
            elseif kind=="airborne" then h.state.grounded=false
            elseif kind=="platform" then h.humanoid.PlatformStand=true
            elseif kind~="avoidance" then h.setCatchState(kind) end
            local direction=h.routeMove(Vector3.new(1,0,0),true,kind=="avoidance")
            assert(hardCuts(h)==0 and h.avoidancePreserved(),kind.." authorized a reset")
            if kind=="avoidance" then assert(close(direction,Vector3.new(1,0,0)))
            else assert(direction.Z>.98 and direction.X>0 and direction.X<.2) end
        end
    end)
    test("recovery and late sprint use their time union without charging the walking gap",function()
        assert(math.abs(Planner.stemSprintSeconds(100,101,100.8,100.2)-.4)<1e-8)
        assert(math.abs(Planner.stemSprintSeconds(100,101,100.8,100.9)-1)<1e-8)
        assert(math.abs(Planner.stemSprintSeconds(100,101,100.8,99)-.2)<1e-8)
        assert(Planner.stemSprintSeconds(100,101,100.8,"invalid")==nil)
    end)
    test("short-field pacing cannot borrow unrequested native running speed",function()
        local s,stage=fixture();assert(Planner.forecastStem(s,stage,100))
        stage.stemRunSpeed=3
        local w,why=Planner.forecastStem(s,stage,100)
        assert(not w and why=="Middle stem is behind schedule")
        stage.stemRunSpeed=0;assert(Planner.forecastStem(s,stage,100)==nil)
    end)
    test("active recovery is charged against future catch stamina",function()
        local s,stage=fixture();stage.recoveryUntilAt=100.4
        local w,why=Planner.forecastStem(s,stage,100);assert(w,why)
        assert(math.abs(w.staminaAtCut-87.5)<1e-8)
    end)
    test("paced run and recovery changes invalidate cached controller eligibility",function()
        local h=harness();assert(h.tick())
        h.context.catchIntent.postThrowStem.stemRunSpeed=3
        assert(not h.tick(100.21) and h.finished() and h.state.moves==1)
        h=harness();assert(h.tick())
        h.context.catchIntent.postThrowStem.recoveryUntilAt=100.3
        assert(h.tick(100.21) and h.state.forecastCalls==2)
    end)
    local catchDirection=assert(source:match("(            if plan.diveAt or plan.continuousCatch then.-)                local actionAt="))
    local drive=assert(loadstring([[
        return function(plan,delta,now,atTarget)
            local parkedPosition,jumped=nil,false
            local motion={grounded=false}
            local reachAirborne=true
            local root={Position=Vector3.zero}
    ]]..catchDirection..[[
                return moving,desired,atTarget
            end
            return moving,nil,atTarget
        end
    ]]))()
    test("continuous Floater keeps moving after crossing its target instead of reversing midair",function()
        local p={kind="jump",continuousCatch=true,direction=Vector3.new(-.6,0,.8),stopAt=101.08}
        local moving,direction,parked=drive(p,-p.direction*.8,100.98,true)
        assert(moving and not parked and direction:Dot(p.direction)>.999)
        moving,direction,parked=drive(p,Vector3.zero,101.02,true)
        assert(moving and not parked and direction:Dot(p.direction)>.999)
    end)
    test("continuous catch input ends at its explicit post-contact deadline",function()
        local p={kind="jump",continuousCatch=true,direction=Vector3.new(-.6,0,.8),stopAt=101.08}
        local moving,direction=drive(p,p.direction,101.09,false)
        assert(not moving and direction==nil)
    end)
    test("ordinary catch direction and stop behavior remain separate from continuous Floater",function()
        local p={kind="move",direction=Vector3.new(1,0,0),stopAt=101.08}
        local moving,direction=drive(p,Vector3.new(-2,0,0),101,false)
        assert(moving and direction.X<-.99)
        assert(not drive(p,Vector3.new(-2,0,0),101.1,false))
        assert(source:find('not plan.timedArrival and not plan.continuousCatch and motion.grounded',1,true),
            "Stationary-plan conversion must not replace a continuous witness")
    end)
    return report
end
