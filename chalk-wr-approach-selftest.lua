-- Pure approach tests; no characters, input, services, or remote calls.
return function(Approach,Planner)
    local results,failed={},0
    local function test(name,fn)
        local ok,err=pcall(fn)
        table.insert(results,{name=name,passed=ok,error=not ok and tostring(err) or nil})
        if not ok then failed=failed+1 end
    end
    local function fixture(safety)
        local s={now=100,role="WR",grounded=true,position=Vector3.new(0,3,0),
            velocity=Vector3.zero,lookDirection=Vector3.new(0,0,1),walkSpeed=27,runSpeed=20,
            sprintSeconds=4,reactionDelay=0,maxHorizon=3,turfY=0,gravity=196.2,
            bounds={minX=-100,maxX=100,minZ=-100,maxZ=100}}
        local p={kind="move",reachable=true,rootTarget=Vector3.new(0,3,10),stopAt=100.4,
            contactAt=102,firstTouchAt=102,safety=safety or "clear",effectiveProgress=10}
        return s,p
    end
    local function solver(p,adjust)
        local mock={calls=0}
        mock.solve=function(s)
            mock.calls=mock.calls+1
            local arrival=s.now+((p.rootTarget-s.position)*Vector3.new(1,0,1)).Magnitude/s.walkSpeed
            local nextPlan={kind="move",reachable=arrival<=p.firstTouchAt,rootTarget=p.rootTarget,
                contactAt=p.contactAt,firstTouchAt=p.firstTouchAt,stopAt=arrival,
                safety=p.safety,effectiveProgress=p.effectiveProgress}
            if adjust then adjust(nextPlan,s) end
            return nextPlan.reachable and nextPlan or nil
        end
        return mock
    end
    test("WR first moves directly away from the catch point",function()
        local s,p=fixture();local mock=solver(p)
        local fake,why=Approach.choose(mock,s,p)
        assert(fake,why)
        assert(fake.direction:Dot((p.rootTarget-s.position).Unit)<-0.99)
        assert((fake.waypoint-s.position).Z<0 and typeof(fake.entryDirection)=="Vector3")
        assert(mock.calls<=10,"preferred-direction search exceeded ten planner calls")
    end)
    test("latest feasible detour leaves approximately 125 ms arrival slack",function()
        local s,p=fixture();local fake,why=Approach.choose(solver(p),s,p)
        assert(fake,why)
        assert(fake.slack>=0.125-0.001 and fake.slack<=0.16,tostring(fake.slack))
        assert(math.abs(fake.catchAt-fake.arrivalAt-fake.slack)<0.001)
        assert(fake.deadline==s.now+fake.duration and fake.catchAt<=p.firstTouchAt+0.015)
    end)
    test("contested catch may fake with spare time without delaying contact",function()
        local s,p=fixture("contested");p.defenderAt=101
        local fake,why=Approach.choose(solver(p),s,p)
        assert(fake,why)
        assert(fake.baselineSafety=="contested" and fake.catchAt<=p.firstTouchAt+0.015)
    end)
    test("unknown defender visibility retains an honest unknown baseline",function()
        local s,p=fixture("unknown")
        local fake,why=Approach.choose(solver(p),s,p)
        assert(fake and fake.baselineSafety=="unknown",why)
    end)
    test("detour cannot worsen defender risk",function()
        local s,p=fixture("clear")
        assert(Approach.choose(solver(p,function(n) n.safety="unknown" end),s,p)==nil)
        p.safety="unknown"
        assert(Approach.choose(solver(p,function(n) n.safety="contested" end),s,p)==nil)
    end)
    test("contested fake cannot delay original contact beyond 15 ms",function()
        local s,p=fixture("contested")
        assert(Approach.choose(solver(p,function(n)
            n.firstTouchAt=n.firstTouchAt+0.03;n.contactAt=n.contactAt+0.03
        end),s,p)==nil)
    end)
    test("clear catch preserves original absolute defender deadline",function()
        local s,p=fixture();p.defenderAt=102.09
        assert(Approach.choose(solver(p,function(n) n.contactAt=n.contactAt+0.02 end),s,p)==nil)
    end)
    test("ordinary catch cannot become a jump or dive to accommodate a fake",function()
        local s,p=fixture()
        assert(Approach.choose(solver(p,function(n,f) n.jumpAt=f.now+0.05 end),s,p)==nil)
        assert(Approach.choose(solver(p,function(n,f) n.diveAt=f.now+0.05 end),s,p)==nil)
    end)
    test("no fake is attempted without arrival slack",function()
        local s,p=fixture();p.stopAt=101.95
        local mock=solver(p)
        assert(Approach.choose(mock,s,p)==nil and mock.calls==0)
    end)
    test("last-chance catch never spends time on a fake",function()
        local s,p=fixture();p.risk="last-resort"
        local mock=solver(p)
        assert(Approach.choose(mock,s,p)==nil and mock.calls==0)
    end)
    test("fake return requires normal catch margins",function()
        local s,p=fixture()
        local checked=false
        local mock=solver(p,function(n,f)
            assert(f.allowLastResort==false,"Forecast must disable narrow catches")
            checked=true;n.risk="last-resort"
        end)
        assert(Approach.choose(mock,s,p)==nil and checked)
    end)
    test("blocked straight-away path permits only a backward diagonal",function()
        local s,p=fixture()
        s.clipDiveDistance=function(_,direction,distance)
            return direction.Z< -0.95 and 0 or distance
        end
        local fake,why=Approach.choose(solver(p),s,p)
        assert(fake,why)
        assert(fake.direction.Z<0 and math.abs(fake.direction.X)>0.1)
        s.bounds={minX=-0.1,maxX=0.1,minZ=-0.1,maxZ=0.1}
        assert(Approach.choose(solver(p),s,p)==nil)
    end)
    test("fake cannot collect the ball along its curved path",function()
        local s,p=fixture();s.arc={};s.launchAt=99
        local mock=solver(p)
        mock.ballAt=function() return s.position end
        mock.capsule=function() return s.position,s.position,3.75 end
        mock.segmentDistance=function() return 0 end
        assert(Approach.choose(mock,s,p)==nil and mock.calls==0)
    end)
    test("return contract models turn time and remaining sprint without mutation",function()
        local s,p=fixture();s.sprintSeconds=0.5;s.velocity=Vector3.new(0,0,27)
        local fake,why=Approach.choose(solver(p),s,p)
        assert(fake,why)
        local current={}
        for k,v in pairs(s) do current[k]=v end
        current.now=s.now+fake.duration;current.position=fake.waypoint
        current.steeringDirection=fake.direction;current.reactionDelay=0
        current.sprintSeconds=math.max(0,s.sprintSeconds-fake.duration)
        current.walkSpeed=current.sprintSeconds>0 and s.walkSpeed or s.runSpeed
        current.velocity=fake.direction*current.walkSpeed
        local plan,slack,forecast=Approach.checkReturn(solver(p),current,fake)
        assert(plan and type(slack)=="number" and typeof(forecast.direction)=="Vector3")
        assert(forecast.turnDuration>=0 and forecast.turnDuration<=math.pi/9+0.001)
        assert(math.abs(forecast.snapshot.now-current.now-forecast.turnDuration)<0.001)
        assert(math.abs(forecast.snapshot.sprintSeconds-math.max(0,current.sprintSeconds-forecast.turnDuration))<0.001)
        assert(s.sprintSeconds==0.5 and s.position==Vector3.new(0,3,0))
    end)
    if Planner then
        test("real planner preserves a late grounded catch after an away-first fake",function()
            local s=fixture()
            s.arc={P0=Vector3.new(0,30,-20),P1=Vector3.new(0,3,20),Flight=3,Apex=0}
            s.launchAt=99.8;s.position=Vector3.new(0,3,17)
            s.canJump,s.canDive,s.allowHold=false,false,false
            s.chase=true;s.jumpSpeed=math.sqrt(2*196.2*6);s.diveDistance=9;s.groundRootY=3
            s.config={CatchRadius=3.75,WaistDrop=1,HandOffset=0.5,HandUpOffset=3.5}
            s.margin=0.4
            s.opponents={{position=Vector3.new(500,3,500),velocity=Vector3.zero,
                grounded=true,canJump=false,canDive=false,walkSpeed=27}}
            local plan=Planner.solve(s)
            assert(plan and not plan.jumpAt and not plan.diveAt)
            local fake,why=Approach.choose(Planner,s,plan)
            assert(fake and fake.followupPlan.reachable and not fake.followupPlan.jumpAt,tostring(why))
            assert(fake.catchAt<=plan.firstTouchAt+0.015)
        end)
    end
    return {total=#results,passed=#results-failed,failed=failed,results=results}
end
