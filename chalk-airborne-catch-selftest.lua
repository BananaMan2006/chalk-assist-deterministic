-- Authored geometry/controller gates only. No native input or server catch claim.
return function(Planner,source)
    local report={total=0,passed=0,failed=0,results={}}
    local function test(name,body)
        report.total=report.total+1
        local ok,err=pcall(body)
        report[ok and "passed" or "failed"]=report[ok and "passed" or "failed"]+1
        report.results[#report.results+1]={name=name,passed=ok,error=not ok and tostring(err) or nil}
    end
    local function fixture()
        return {now=100,launchAt=100,role="WR",arc={P0=Vector3.new(0,6,-30),
            P1=Vector3.new(20,3.5,20),Flight=.9,Apex=0},position=Vector3.new(0,3,0),
            velocity=Vector3.zero,lookDirection=Vector3.new(0,0,1),grounded=true,
            jumpSpeed=math.sqrt(2*196.2*6),gravity=196.2,walkSpeed=27,runSpeed=20,sprintSeconds=4,
            groundRootY=3,turfY=0,diveDistance=14.7,canJump=true,canDive=true,maxHorizon=2.2,
            margin=.4,preferAirborne=true,requireAirborne=true,preferJumpDive=true,chase=true,allowHold=false,
            config={CatchRadius=3.75,DiveCatchRadius=2.5,WaistDrop=1,HandOffset=.5,
                HandUpOffset=3.5,DiveReach=2.4,Moves={Dive={Time=.35,Tip=.5,Ground=.75,GetUp=.35}}}}
    end
    local function dispatch(s,p)
        local cf,air,vy=Planner.pose(s,p,p.diveAt-.000001)
        local fresh={}for k,v in pairs(s)do fresh[k]=v end
        fresh.now=p.diveAt;fresh.position=cf.Position
        fresh.velocity=p.direction*27+Vector3.new(0,vy,0)
        fresh.grounded=false;fresh.canJump=false
        assert(air)
        return fresh
    end
    test("WR times jump and dive for airborne first contact, not early prone arrival",function()
        local s=fixture();local p,why=Planner.solve(s)
        assert(p and p.kind=="jumpDive" and p.airborneFinish=="jumpDive",why)
        assert(p.jumpAt>s.now+.4 and p.diveAt>p.jumpAt+.06)
        assert(p.firstTouchAt>=p.diveAt+.03 and p.margin>=s.margin and not p.risk)
        local cf,air=Planner.pose(s,p,p.firstTouchAt)
        assert(air and cf.Position.Y>s.turfY+.75)
        assert(Planner.airborneFinish(s,p)=="jumpDive")
    end)
    test("unavailable dive retains an airborne jump catch",function()
        local s=fixture();s.canDive=false
        local p,why=Planner.solve(s)
        assert(p and p.airborneFinish=="jump" and not p.diveAt and p.jumpAt,why)
    end)
    test("already grounded overlap has no deliberate catch plan and reports that limitation",function()
        local s=fixture();s.launchAt=s.now-.2
        s.arc={P0=Vector3.new(0,4,0),P1=Vector3.new(0,4,0),Flight=100,Apex=0}
        local p,why=Planner.solve(s)
        assert(p==nil and why=="No robust airborne WR contact available")
    end)
    test("grounded dive recovery is never called an airborne catch",function()
        local s=fixture();s.canJump=false;s.walkSpeed=0;s.runSpeed=0
        local p={kind="dive",direction=Vector3.new(1,0,0),_speed=0,_runSpeed=0,_sprintSeconds=0,
            _reaction=0,_aimDistance=0,_diveDelay=.1,diveAt=100.1,contactAt=101,
            contactPosition=Vector3.new(14.7,1,0),rootTarget=Vector3.new(14.7,.6,0)}
        assert(Planner.airborneFinish(s,p,{at=100.8})==nil)
    end)
    test("later airborne pose cannot hide contact before the dive",function()
        local s=fixture();local p=assert(Planner.solve(s))
        local finish,why=Planner.airborneFinish(s,p,{at=p.diveAt-.001})
        assert(finish==nil and why=="Contact precedes the dive")
    end)
    test("dispatch check uses observed current position and rejects changed trajectory",function()
        local s=fixture();local p=assert(Planner.solve(s));local fresh=dispatch(s,p)
        assert(Planner.validateAirborneDive(fresh,p))
        fresh.position=fresh.position+Vector3.new(40,0,0)
        assert(not Planner.validateAirborneDive(fresh,p))
    end)
    test("dispatch check refuses grounded or shortened native-air reach",function()
        local s=fixture();local p=assert(Planner.solve(s));local fresh=dispatch(s,p)
        fresh.grounded=true;assert(not Planner.validateAirborneDive(fresh,p))
        fresh.grounded=false;fresh.reachAirborne=false
        assert(not Planner.validateAirborneDive(fresh,p))
    end)
    test("WR aerial flags leave DB earliest-contact selection unchanged",function()
        local s=fixture();s.role="DB";s.requireAirborne=false;s.preferAirborne=false;s.preferJumpDive=false
        local before=assert(Planner.solve(s));s.preferAirborne=true;s.requireAirborne=true;s.preferJumpDive=true
        local after=assert(Planner.solve(s))
        assert(after.kind==before.kind and after.contactAt==before.contactAt)
        assert(after.jumpAt==before.jumpAt and after.diveAt==before.diveAt and after.margin==before.margin)
        assert(after.airborneFinish==nil)
    end)
    test("no arc and unreachable pursuit never invent a jump or dive",function()
        local s=fixture();s.arc=nil;assert(Planner.solve(s)==nil and Planner.pursuit(s)==nil)
        s=fixture();s.arc.P0=s.arc.P0+Vector3.new(200,0,0);s.arc.P1=s.arc.P1+Vector3.new(200,0,0)
        assert(Planner.solve(s)==nil)
        local p=assert(Planner.pursuit(s));assert(p.reachable==false and not p.jumpAt and not p.diveAt)
    end)
    test("floater takes earlier robust airborne contact instead of later downfield contact",function()
        local s=fixture();s.arc.P1=Vector3.new(30,3.5,35);s.arc.Apex=10;s.arc.Flight=1.5
        s.passType="Bullet";local later=assert(Planner.solve(s))
        s.passType="Floater";local early=assert(Planner.solve(s))
        assert(early.airborneFinish and early.contactAt<later.contactAt-.1)
        assert(early.margin>=s.margin and not early.risk and early.earliestAirborne)
        local current=Planner.pose(s,early,early.firstTouchAt)
        assert(current.Position.Y>s.turfY+.75)
    end)
    test("late dispatch is rejected instead of chasing a missed airborne contact",function()
        local s=fixture();local p=assert(Planner.solve(s));local fresh=dispatch(s,p)
        fresh.now=p.contactAt+.02
        assert(not Planner.validateAirborneDive(fresh,p))
    end)
    test("adaptive first contact finds short grounded bullet overlap before a later jump",function()
        local s=fixture();s.arc={P0=Vector3.new(-9.49,7.2,0),P1=Vector3.new(90.51,7.2,0),Flight=1,Apex=0}
        s.timingMargin=.001
        local p={kind="jump",direction=Vector3.new(1,0,0),_speed=27,_runSpeed=27,_sprintSeconds=4,
            _reaction=0,_aimDistance=100,_jumpDelay=.16,jumpAt=100.16,contactAt=100.174}
        p.contactPosition=Planner.ballAt(s.arc,.174);p.rootTarget=Planner.pose(s,p,p.contactAt).Position
        for _,at in ipairs({100.173,100.174,100.175}) do
            local cf,air=Planner.pose(s,p,at);local a,b,r=Planner.capsule(s,cf,air)
            assert(r-Planner.segmentDistance(Planner.ballAt(s.arc,at-s.launchAt),a,b)>=s.margin)
        end
        s.requireAirborne=false;local coarse=Planner.firstTouch(s,p)
        assert(coarse.at>=p.jumpAt,"Fixture no longer reproduces the 40 ms alias")
        s.requireAirborne=true;local fine=Planner.firstTouch(s,p)
        assert(fine.at<100.14 and fine.at>100.12 and not fine.uncertain)
        local _,air=Planner.pose(s,p,fine.at);assert(not air)
        assert(Planner.airborneFinish(s,p,fine)==nil)
    end)
    test("first-contact sampling budget fails closed",function()
        local s=fixture();local p=assert(Planner.solve(s));p.contactAt=110
        local touch=Planner.firstTouch(s,p)
        assert(touch.uncertain and Planner.airborneFinish(s,p,touch)==nil)
    end)
    local staleGuard=assert(source:match("(    local function cancelStaleAction.-)    local walls"))
    local actionSection=assert(source:match("(        local actionNow=workspace:GetServerTimeNow%(%).-)        message=plan.reachable==false"))
    local dispatchFixture=assert(loadstring([[
        return function(input,clocks,role)
            local result={jumps=0,dives=0,cancels=0,finished=false}
            local plan=input
            local now=100
            local nextSolve=0
            local jumped,dived=false,false
            local jumpRequest,lastSnapshot,lastJump,lastDive=nil,{},0,0
            local reachAirborne,message,motion
            local atTarget,parkedPosition=false,nil
            local counters={dives=0}
            local clockIndex=0
            local workspace={GetServerTimeNow=function()
                clockIndex=math.min(clockIndex+1,#clocks)
                return clocks[clockIndex]
            end}
            local s={role=role}
            local root={Position=Vector3.new(0,5,0),AssemblyLinearVelocity=Vector3.zero}
            local h={FloorMaterial="Air",PlatformStand=false}
            function h:Move()end
            function h:ChangeState()result.jumps=result.jumps+1 end
            local Enum={HumanoidStateType={Jumping="Jumping"},Material={Air="Air"}}
            local Config={Moves={Dive={Cooldown=1.6}}}
            local Moves={Upright=function()return true end}
            local function motionState()return {grounded=true,diveModeMatchesMotion=true}end
            local function log()end
            local function xyz()return {}end
            local function snapshot()return {}end
            local function solveActual()return nil end
            local function divePermitted()return true end
            local function releaseSprint()end
            local function nativeDive()result.dives=result.dives+1;h.PlatformStand=true end
            local function cancel()result.cancels=result.cancels+1;plan=nil;jumpRequest=nil end
            local Planner={validateAirborneDive=function()return true end,
                pose=function()return {Position=root.Position}end}
    ]]..staleGuard..[[
            local function tick()
    ]]..actionSection..[[
                result.finished=true
            end
            tick()
            result.nextSolve=nextSolve;result.jumpRequested=h.Jump==true
            return result
        end
    ]]))()
    test("slow planning cancels overdue jump and dive before inputs for both roles",function()
        for _,role in ipairs({"WR","DB"})do
            for _,kind in ipairs({"jump","dive"})do
                local p={kind=kind,contactAt=100.5,direction=Vector3.new(1,0,0)}
                p[kind=="jump" and "jumpAt" or "diveAt"]=100.025
                local r=dispatchFixture(p,{100.12},role)
                assert(r.cancels==1 and r.jumps==0 and r.dives==0 and not r.jumpRequested)
                assert(not r.finished and math.abs(r.nextSolve-100.165)<.000001)
            end
        end
    end)
    test("elapsed contact blocks an action even inside its 75 ms action grace",function()
        local r=dispatchFixture({kind="jump",jumpAt=100.02,contactAt=100.04},{100.05},"DB")
        assert(r.cancels==1 and r.jumps==0 and not r.finished)
    end)
    test("clock delay during pre-jump native checks is caught at actual dispatch",function()
        local r=dispatchFixture({kind="jump",jumpAt=100.02,contactAt=100.5},{100.03,100.12},"WR")
        assert(r.cancels==1 and r.jumps==0 and not r.jumpRequested and not r.finished)
    end)
    test("clock delay during pre-dive validation is caught at actual dispatch",function()
        local r=dispatchFixture({kind="dive",diveAt=100.02,contactAt=100.5,
            airborneFinish="jumpDive",direction=Vector3.new(1,0,0)},{100.03,100.03,100.12},"WR")
        assert(r.cancels==1 and r.dives==0 and not r.finished)
    end)
    test("future and timely actions retain their original dispatch behavior",function()
        local wait=dispatchFixture({kind="jump",jumpAt=100.02,contactAt=100.5},{100.01},"WR")
        assert(wait.finished and wait.cancels==0 and wait.jumps==0)
        local jump=dispatchFixture({kind="jump",jumpAt=100.02,contactAt=100.5},{100.03},"DB")
        assert(jump.finished and jump.cancels==0 and jump.jumps==1 and jump.jumpRequested)
        local dive=dispatchFixture({kind="dive",diveAt=100.02,contactAt=100.5,
            direction=Vector3.new(1,0,0)},{100.03},"DB")
        assert(dive.finished and dive.cancels==0 and dive.dives==1)
    end)
    test("controller exits catch actions outside live ball phase",function()
        local gate=assert(source:match('(        if s.phase~="Live" or not s.arc or not s.launchAt then.-)        navigation=false\n        if tackleAssist'))
        local factory=assert(loadstring([[
            local calls=0
            local function cancel()end
            local function healthyCharacter()return nil,nil end
            local function updateFullplay()return false end
            local function release()end
            local dt,now=0.016,100
            local function run(s)
        ]]..gate..[[
                calls=calls+1
            end
            return run,function()return calls end
        ]]))
        local run,calls=factory()
        for _,s in ipairs({{phase="Hike",arc={},launchAt=100},{phase="Live",launchAt=100},
            {phase="Live",arc={}}}) do run(s)end
        assert(calls()==0)
        run({phase="Live",arc={},launchAt=100});assert(calls()==1)
    end)
    return report
end
