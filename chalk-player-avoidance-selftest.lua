-- Deterministic geometry/lifecycle tests; no game services or native inputs.
return function(Avoidance)
    local report={total=0,passed=0,failed=0,results={}}
    local function test(name,body)
        report.total=report.total+1
        local ok,reason=pcall(body)
        report[ok and "passed" or "failed"]=report[ok and "passed" or "failed"]+1
        report.results[#report.results+1]={name=name,passed=ok,error=not ok and tostring(reason) or nil}
    end
    local function fixture(extra)
        local input={now=0,dt=.025,position=Vector3.zero,velocity=Vector3.new(0,0,27),
            desiredDirection=Vector3.new(0,0,1),currentDirection=Vector3.new(0,0,1),
            requestedSprint=true,walkSpeed=27,runSpeed=20,canDetour=true,opponents={},
            bounds={minX=-30,maxX=30,minZ=-30,maxZ=50}}
        for k,v in pairs(extra or {}) do input[k]=v end
        return input
    end
    local function same(a,b) assert((a-b).Magnitude<1e-7,"direction changed") end
    local function legal(input,direction)
        local point=input.position+direction*input.walkSpeed*input.dt
        local b=input.bounds
        assert(point.X>=b.minX-1e-7 and point.X<=b.maxX+1e-7
            and point.Z>=b.minZ-1e-7 and point.Z<=b.maxZ+1e-7,"steering left legal bounds")
    end

    test("fresh clear movement retains the exact vector magnitude and sprint request",function()
        for _,strength in ipairs({.1,.6,1}) do
            for _,sprint in ipairs({false,true}) do
                local p=fixture({desiredDirection=Vector3.new(.3,0,.4)*strength,requestedSprint=sprint})
                local _,d=Avoidance.update(nil,p)
                assert(d.direction==p.desiredDirection and d.sprint==sprint)
                assert(not d.active and not d.blocked and not d.changed)
            end
        end
    end)
    test("far behind departing and vertically separated players preserve clear movement",function()
        for _,other in ipairs({
            {position=Vector3.new(0,0,40),velocity=Vector3.zero},
            {position=Vector3.new(0,0,-5),velocity=Vector3.zero},
            {position=Vector3.new(0,0,5),velocity=Vector3.new(0,0,30)},
            {position=Vector3.new(0,8,4),velocity=Vector3.zero},
            {position=Vector3.new(0,-8,4),velocity=Vector3.zero},
        }) do
            local p=fixture({opponents={other}});local _,d=Avoidance.update(nil,p)
            same(d.direction,p.desiredDirection);assert(not d.active and d.sprint)
        end
    end)
    test("moving crossing capsule triggers avoidance before physical contact",function()
        local p=fixture({opponents={{position=Vector3.new(5,0,3),velocity=Vector3.new(-20,0,0)}}})
        assert(p.opponents[1].position.Magnitude>4.25)
        local state,d=Avoidance.update(nil,p)
        assert(d.active and d.changed and not d.sprint and not d.blocked and state.side)
        assert(d.direction.Magnitude<=p.desiredDirection.Magnitude);legal(p,d.direction)
    end)
    test("proactive walk bypass clears a stationary blocker without touching or side chatter",function()
        local state,side,minDistance=nil,nil,math.huge
        local p=fixture({opponents={{position=Vector3.new(0,0,8),velocity=Vector3.zero}}})
        local goal=Vector3.new(0,0,35)
        local sawActive,sawClear=false,false
        for _=1,200 do
            p.desiredDirection=(goal-p.position).Unit
            local d;state,d=Avoidance.update(state,p)
            if d.active then
                sawActive=true;assert(not d.sprint)
                if d.side then
                    side=side or d.side;assert(d.side==side,"bypass side flipped")
                end
            elseif sawActive then sawClear=true end
            legal(p,d.direction)
            p.position=p.position+d.direction*p.walkSpeed*p.dt
            minDistance=math.min(minDistance,(p.position-p.opponents[1].position).Magnitude)
            p.now=p.now+p.dt;p.walkSpeed=d.sprint and 27 or 20
            p.currentDirection=state.heading or p.desiredDirection
            if p.position.Z>16 and sawClear then break end
        end
        assert(sawActive and sawClear and p.position.Z>16,"bypass never resumed normal movement")
        assert(minDistance>=3.6,"proactive bypass entered the collision capsule")
    end)
    test("overlapping forward turn waits when every checked movement speed worsens contact",function()
        for _,side in ipairs({-1,1}) do
            local p=fixture({dt=1/60,walkSpeed=20,
                opponents={{position=Vector3.new(side*.25,0,3.1),velocity=Vector3.zero}}})
            local state,d=Avoidance.update(nil,p)
            assert(d.active and not d.sprint and d.direction.Magnitude==0,
                "failed clearance checks were bypassed by the overlapping full-walk fallback")
            assert(state.heading:Dot(p.desiredDirection)<1 and state.heading.Z>0,
                "waiting discarded the bounded turn")
            local firstHeading=state.heading
            p.now=p.now+p.dt
            state,d=Avoidance.update(state,p)
            assert(d.direction.Magnitude==0 and state.heading:Dot(p.desiredDirection)<firstHeading.Z,
                "zero movement restarted the turn instead of retaining progress")
        end
    end)
    test("centered and mirrored overlap escapes resume after a bounded turn without permanent holding",function()
        for _,offset in ipairs({-.25,0,.25}) do
            local obstacle=Vector3.new(offset,0,3.1)
            local p=fixture({dt=1/60,walkSpeed=20,
                opponents={{position=obstacle,velocity=Vector3.zero}}})
            local state,firstMotion,cleared,side=nil,nil,false,nil
            local initialGap=obstacle.Magnitude
            for _=1,90 do
                local oldHeading=state and state.heading or p.currentDirection
                local d;state,d=Avoidance.update(state,p)
                if d.active then
                    assert(not d.sprint,"overlapping escape spent sprint")
                    if d.side then
                        side=side or d.side
                        assert(d.side==side,"waiting changed the chosen passing side")
                    end
                    local angle=math.acos(math.max(-1,math.min(1,oldHeading.Unit:Dot(state.heading.Unit))))
                    assert(angle<=8*p.dt+1e-7,"escape bypassed the bounded turn")
                end
                if d.direction.Magnitude>.001 then
                    firstMotion=firstMotion or p.now
                    p.currentDirection=d.direction.Unit
                end
                legal(p,d.direction)
                p.position=p.position+d.direction*p.walkSpeed*p.dt
                assert((p.position-obstacle).Magnitude>=initialGap-.16,
                    "escape substantially deepened the initial overlap")
                assert(math.abs(p.position.X)<6,"escape took an unnecessarily wide side path")
                if not d.active and p.position.Z>7 then cleared=true;break end
                p.now=p.now+p.dt
            end
            assert(firstMotion and firstMotion>0 and firstMotion<.25,
                "safe translation did not resume after the short bounded turn")
            assert(cleared and p.now<1,"overlap escape remained held instead of restoring forward movement")
        end
    end)
    test("already safe sideways overlap escapes still move immediately",function()
        for _,side in ipairs({-1,1}) do
            local p=fixture({dt=1/60,walkSpeed=20,currentDirection=Vector3.new(side,0,0),
                opponents={{position=Vector3.new(-side*.25,0,3.1),velocity=Vector3.zero}}})
            local _,d=Avoidance.update(nil,p)
            assert(d.active and not d.sprint and d.direction.Magnitude>.99,
                "safe contact escape was unnecessarily held")
            local ending=(p.opponents[1].position-d.direction*p.walkSpeed*.25).Magnitude
            assert(ending>p.opponents[1].position.Magnitude+.25)
            legal(p,d.direction)
        end
    end)
    test("retained side is stable across small opponent jitter and roster reordering",function()
        local p=fixture({opponents={{position=Vector3.new(0,0,6),velocity=Vector3.zero}}})
        local state,d=Avoidance.update(nil,p);local side=state.side;assert(side)
        for i=1,12 do
            p.now=p.now+.025;p.currentDirection=state.heading
            local threat={position=Vector3.new(i%2==0 and .08 or -.08,0,6),velocity=Vector3.zero}
            local far={position=Vector3.new(20,0,20),velocity=Vector3.zero}
            p.opponents=i%2==0 and {threat,far} or {far,threat}
            state,d=Avoidance.update(state,p)
            assert(d.active and state.side==side)
        end
    end)
    test("oscillating clearance boundary cannot alternate bypass and return headings every frame",function()
        local bypass=Vector3.new(-math.sin(math.rad(35)),0,math.cos(math.rad(35)))
        local p=fixture({walkSpeed=20,currentDirection=bypass})
        local state={active=true,side=-1,heading=bypass}
        for i=1,12 do
            p.now=i*.025
            -- Direct-path clearance crosses the3.75stud capsule boundary;
            -- the already chosen left bypass remains physically clear.
            p.opponents={{position=Vector3.new(i%2==1 and 3.8 or 3.7,0,4),velocity=Vector3.zero}}
            local d;state,d=Avoidance.update(state,p)
            same(state.heading,bypass)
            assert(d.active and not d.sprint and state.side==-1)
            p.currentDirection=state.heading
        end
        p.opponents={{position=Vector3.new(3.8,0,4),velocity=Vector3.zero}}
        for i=1,5 do
            p.now=.3+i*.025
            local d;state,d=Avoidance.update(state,p)
            same(state.heading,bypass);assert(d.reason=="holding passing side")
            p.currentDirection=state.heading
        end
        p.now=.45
        local d;state,d=Avoidance.update(state,p)
        assert(d.reason=="returning to path" and state.heading.X>bypass.X)
        for _=1,12 do
            p.now=p.now+.025;p.currentDirection=state.heading
            state,d=Avoidance.update(state,p)
        end
        assert(not d.active and d.sprint);same(d.direction,p.desiredDirection)
    end)
    test("release hysteresis never holds an old bypass into a sideline",function()
        local p=fixture({now=.05,position=Vector3.new(9.5,0,0),
            bounds={minX=-10,maxX=10,minZ=-10,maxZ=30},currentDirection=Vector3.new(1,0,0)})
        local state={active=true,heading=Vector3.new(1,0,0),side=1,clearSince=.04}
        local _,d=Avoidance.update(state,p)
        assert(d.reason~="holding passing side","hysteresis overrode the bounds check")
        legal(p,d.direction)
    end)
    test("material catch-target change starts a bounded return without the old clear-frame hold",function()
        local old=Vector3.new(.988,0,.157).Unit
        local previousDesired=Vector3.new(.75,0,-.66).Unit
        local goal=Vector3.new(-.22,0,.975).Unit
        local p=fixture({now=.05,dt=.025,desiredDirection=goal,currentDirection=old,
            allowSprintDetour=true,sprintSpeed=27})
        local state={active=true,heading=old,side=1,desiredHeading=previousDesired,clearSince=.04}
        local firstDot=old:Dot(goal)
        local d;state,d=Avoidance.update(state,p)
        assert(d.reason=="returning to path" and state.returningToChangedGoal,
            "new catch direction retained the previous target's passing hold")
        assert(state.heading:Dot(goal)>firstDot and d.sprint)
        assert(math.acos(math.clamp(state.heading:Dot(old),-1,1))<=8*p.dt+1e-6)
        -- The next frames are still inside the old .12-second debounce. The
        -- change exemption must survive rather than produce one turn then hold.
        for _=1,3 do
            local before=state.heading
            p.now=p.now+p.dt;p.currentDirection=before
            state,d=Avoidance.update(state,p)
            assert(d.reason=="returning to path" and state.returningToChangedGoal)
            assert(state.heading:Dot(goal)>before:Dot(goal))
            assert(math.acos(math.clamp(state.heading:Dot(before),-1,1))<=8*p.dt+1e-6)
        end
        for _=1,20 do
            p.now=p.now+p.dt;p.currentDirection=state.heading
            state,d=Avoidance.update(state,p)
            if not d.active then break end
        end
        assert(not d.active and state.returningToChangedGoal==nil)
        same(d.direction,goal);same(state.desiredHeading,goal)
    end)
    test("changed goal still checks the bounded return heading for player collisions",function()
        local old=Vector3.new(1,0,0)
        local p=fixture({now=.05,desiredDirection=Vector3.new(0,0,1),currentDirection=old,
            allowSprintDetour=true,sprintSpeed=27,
            opponents={{position=Vector3.new(4.5,0,0),velocity=Vector3.zero}}})
        local previous={active=true,heading=old,side=-1,desiredHeading=Vector3.new(0,0,-1),clearSince=.04}
        local state,d=Avoidance.update(previous,p)
        assert(d.active and not d.sprint,"changed goal bypassed current-path collision safety")
        assert(math.acos(math.clamp(state.heading:Dot(old),-1,1))<=8*p.dt+1e-6)
        local relative=p.opponents[1].position-p.position
        local velocity=-d.direction*p.walkSpeed
        local time=velocity:Dot(velocity)>.000001
            and math.clamp(-relative:Dot(velocity)/velocity:Dot(velocity),0,.25) or 0
        assert((relative+velocity*time).Magnitude>=3.75-1e-6,
            "return turn was allowed to cross the collision capsule")
        legal(p,d.direction)
    end)
    test("small requested-heading jitter preserves ordinary passing-side hysteresis",function()
        local bypass=Vector3.new(-math.sin(math.rad(35)),0,math.cos(math.rad(35)))
        local p=fixture({walkSpeed=20,currentDirection=bypass})
        local state={active=true,side=-1,heading=bypass,desiredHeading=Vector3.new(0,0,1)}
        for i=1,4 do
            p.now=i*.025
            p.desiredDirection=Vector3.new(i%2==0 and .02 or -.02,0,1).Unit
            local d;state,d=Avoidance.update(state,p)
            assert(d.reason=="holding passing side" and not state.returningToChangedGoal)
            same(state.heading,bypass)
        end
    end)
    test("sideline bypass selects the open side and remains bounded",function()
        local p=fixture({bounds={minX=-20,maxX=2,minZ=-20,maxZ=30},
            opponents={{position=Vector3.new(0,0,5),velocity=Vector3.zero}}})
        local state,d=Avoidance.update(nil,p)
        assert(d.active and state.side==-1,"bypass chose the closed sideline")
        for _=1,12 do
            legal(p,d.direction)
            p.position=p.position+d.direction*p.walkSpeed*p.dt;p.now=p.now+p.dt
            p.currentDirection=state.heading
            state,d=Avoidance.update(state,p)
            assert(d.direction.X<=.00001)
        end
    end)
    test("no bounded bypass releases sprint and does not push into the obstacle",function()
        local p=fixture({bounds={minX=-1,maxX=1,minZ=-10,maxZ=20},
            opponents={{position=Vector3.new(0,0,3.5),velocity=Vector3.zero}}})
        local state,d=Avoidance.update(nil,p)
        assert(d.active and not d.sprint);same(d.direction,Vector3.zero)
        for _=1,8 do p.now=p.now+.025;state,d=Avoidance.update(state,p) end
        assert(d.blocked and d.reason=="no room to pass" and not d.sprint)
    end)
    test("recorded-style low displacement detects blocking despite reported velocity27",function()
        local p=fixture();local state,d
        for i=0,9 do
            p.now=i*.05;p.dt=.05;p.position=Vector3.new(0,0,p.now*(.77/.43))
            p.velocity=Vector3.new(0,0,27)
            p.opponents={{position=p.position+Vector3.new(0,0,3.7),velocity=Vector3.zero}}
            state,d=Avoidance.update(state,p)
        end
        assert(d.blocked and not d.sprint and d.progressSpeed<2,
            "reported velocity concealed physical blocking")
    end)
    test("real positional progress prevents false blocking even when reported velocity is zero",function()
        local p=fixture({velocity=Vector3.zero,walkSpeed=20});local state,d
        for i=0,10 do
            p.now=i*.025;p.position=Vector3.new(0,0,20*p.now)
            p.opponents={{position=p.position+Vector3.new(3.9,0,0),velocity=Vector3.new(0,0,20)}}
            state,d=Avoidance.update(state,p)
            assert(not d.blocked)
        end
        assert(d.progressSpeed and d.progressSpeed>19)
    end)
    test("brief contact does not claim prolonged blocking before its observation window",function()
        local p=fixture({opponents={{position=Vector3.new(0,0,3.7),velocity=Vector3.zero}}})
        local state,d
        for i=0,4 do p.now=i*.025;state,d=Avoidance.update(state,p);assert(not d.blocked) end
        p.now=.2;state,d=Avoidance.update(state,p);assert(d.blocked)
    end)
    test("committed movement bypass clears detour and progress state without changing input",function()
        local p=fixture({opponents={{position=Vector3.new(0,0,3.7),velocity=Vector3.zero}}})
        local state,d
        for i=0,8 do p.now=i*.025;state,d=Avoidance.update(state,p) end
        assert(d.active and d.blocked)
        p.canDetour=false;state,d=Avoidance.update(state,p)
        assert(next(state)==nil and not d.active and not d.blocked and d.sprint)
        same(d.direction,p.desiredDirection)
        p.canDetour=true;p.now=p.now+.025;state,d=Avoidance.update(state,p)
        assert(not d.blocked,"old contact timer survived priority handoff")
    end)
    test("zero movement resets stale state and never fabricates a detour",function()
        local p=fixture({desiredDirection=Vector3.zero})
        local state,d=Avoidance.update({active=true,side=-1,blocked=true},p)
        assert(next(state)==nil and not d.active and not d.blocked)
        same(d.direction,Vector3.zero);assert(d.sprint)
    end)
    test("first detour starts from actual current heading with a bounded turn",function()
        local p=fixture({currentDirection=Vector3.new(1,0,0),
            opponents={{position=Vector3.new(0,0,6),velocity=Vector3.zero}}})
        local previous={active=false,heading=Vector3.new(-1,0,0)}
        local state,d=Avoidance.update(previous,p)
        assert(d.active)
        local angle=math.acos(math.clamp(state.heading:Dot(p.currentDirection),-1,1))
        assert(angle<=8*p.dt+.000001,"detour jumped to desired goal or stale heading")
    end)
    test("turning away from an opponent still protects the actual current travel direction",function()
        local p=fixture({currentDirection=Vector3.new(0,0,-1),
            opponents={{position=Vector3.new(0,0,-5),velocity=Vector3.zero}}})
        local state,d=Avoidance.update(nil,p)
        assert(d.active and not d.sprint,"desired clear goal hid an imminent collision on the current heading")
        local angle=math.acos(math.clamp(state.heading:Dot(p.currentDirection),-1,1))
        assert(angle<=8*p.dt+.000001)
        local projected=p.position+d.direction*p.walkSpeed*.25
        assert((projected-p.opponents[1].position).Magnitude>=3.75)
    end)
    test("smoothed return to a clear path remains bounds-safe beside a sideline",function()
        local p=fixture({position=Vector3.new(9.5,0,0),bounds={minX=-10,maxX=10,minZ=-10,maxZ=30},
            currentDirection=Vector3.new(1,0,0)})
        local state={active=true,heading=Vector3.new(1,0,0),side=1}
        local sawClear=false
        for _=1,20 do
            local d;state,d=Avoidance.update(state,p)
            legal(p,d.direction)
            p.position=p.position+d.direction*p.walkSpeed*p.dt
            p.now=p.now+p.dt;p.currentDirection=state.heading
            if not d.active then sawClear=true;assert(d.sprint);same(d.direction,p.desiredDirection);break end
        end
        assert(sawClear,"safe return never restored normal movement")
    end)
    test("active detours never increase requested movement strength or enable unrequested sprint",function()
        local p=fixture({desiredDirection=Vector3.new(0,0,.6),requestedSprint=false,
            opponents={{position=Vector3.new(0,0,4.5),velocity=Vector3.zero}}})
        local state,d
        for i=0,12 do
            p.now=i*.025;state,d=Avoidance.update(state,p)
            assert(not d.sprint and d.direction.Magnitude<=.6+.000001)
        end
    end)
    test("invalid inputs are contained and cannot produce nonfinite steering",function()
        for _,p in ipairs({{},fixture({desiredDirection=false}),fixture({desiredDirection=Vector3.new(0/0,0,1)})}) do
            local _,d=Avoidance.update(nil,p);same(d.direction,Vector3.zero);assert(not d.sprint and not d.active)
        end
        local p=fixture({position=false});local _,d=Avoidance.update(nil,p)
        same(d.direction,p.desiredDirection);assert(not d.active)
        p=fixture({opponents={{position=false},{position=Vector3.new(0/0,0,4)},{position=Vector3.new(0,0,50)}}})
        _,d=Avoidance.update(nil,p);assert(not d.active and d.sprint)
    end)
    test("malformed bounds cannot authorize a new sideways path",function()
        local p=fixture({bounds={minX=10,maxX=-10},
            opponents={{position=Vector3.new(0,0,4),velocity=Vector3.zero}}})
        local _,d=Avoidance.update(nil,p)
        assert(d.active and not d.sprint);same(d.direction,Vector3.zero)
    end)
    test("state updates are pure and sample history remains bounded",function()
        local sample={time=0,position=Vector3.zero}
        local previous={samples={sample},side=-1,active=false}
        local p=fixture({now=.1})
        local state=Avoidance.update(previous,p)
        assert(state~=previous and state.samples~=previous.samples and #previous.samples==1)
        assert(previous.samples[1]==sample and sample.time==0 and previous.now==nil)
        for i=1,200 do p.now=.1+i*.005;p.position=Vector3.new(0,0,p.now*20);state=Avoidance.update(state,p) end
        assert(#state.samples<=32)
    end)
    test("clock rollback discards stale contact history",function()
        local p=fixture({now=10,opponents={{position=Vector3.new(0,0,3.7),velocity=Vector3.zero}}})
        local state,d
        for i=0,8 do p.now=10+i*.025;state,d=Avoidance.update(state,p) end
        assert(d.blocked)
        p.now=1;state,d=Avoidance.update(state,p);assert(not d.blocked and #state.samples==1)
    end)
    test("recorded8892 clear passing heading retains an explicitly requested native sprint",function()
        local bypass=Vector3.new(.837928056716919,0,.5457807183265686).Unit
        for _,speed in ipairs({20,27}) do
            local p=fixture({now=.2,walkSpeed=speed,allowSprintDetour=true,sprintSpeed=27,
                position=Vector3.new(35.56631088256836,4.636868,42.002105712890625),
                desiredDirection=Vector3.new(.3488311767578125,0,.9371855854988098).Unit,
                currentDirection=bypass,bounds={minX=-29.712,maxX=67.5,minZ=-43.512,maxZ=151.912},
                opponents={{position=Vector3.new(30.28558921813965,4.636789,42.14754867553711),
                    velocity=Vector3.new(19.106891632080078,0,-5.664046287536621)}}})
            local old={active=true,heading=bypass,side=1,clearSince=.18}
            local state,d=Avoidance.update(old,p)
            assert(d.active and d.sprint and not d.blocked and d.reason=="holding passing side")
            same(d.direction,bypass);same(state.heading,bypass)
            p.allowSprintDetour=false
            local _,default=Avoidance.update(old,p)
            assert(default.active and not default.sprint)
            same(default.direction,bypass*(20/speed))
        end
    end)
    test("explicit opt out is identical to default across a moving detour",function()
        local a,b
        local p=fixture({opponents={{position=Vector3.new(0,0,8),velocity=Vector3.zero}}})
        for _=1,50 do
            p.allowSprintDetour=nil
            local da;a,da=Avoidance.update(a,p)
            p.allowSprintDetour=false;p.sprintSpeed=27
            local db;b,db=Avoidance.update(b,p)
            same(da.direction,db.direction)
            assert(da.sprint==db.sprint and da.active==db.active and da.blocked==db.blocked
                and da.reason==db.reason and a.side==b.side)
            p.position=p.position+da.direction*p.walkSpeed*p.dt
            p.now=p.now+p.dt;p.currentDirection=a.heading or p.desiredDirection
        end
    end)
    test("prospective27 collision slows a path that is clear at current20",function()
        local p=fixture({walkSpeed=20,allowSprintDetour=true,sprintSpeed=27,
            opponents={{position=Vector3.new(0,0,10),velocity=Vector3.zero}}})
        local _,d=Avoidance.update(nil,p)
        assert(d.active and not d.sprint,"sprint safety reused walking-only clearance")
        assert(d.direction.Magnitude<=1);legal(p,d.direction)
    end)
    test("actual20 crossing still slows even when prospective27 would escape",function()
        local p=fixture({dt=.004,walkSpeed=20,allowSprintDetour=true,sprintSpeed=27,
            opponents={{position=Vector3.new(-6,0,1),velocity=Vector3.new(20,0,0)}}})
        local _,d=Avoidance.update(nil,p)
        assert(d.active and not d.sprint,"prospective clearance hid the current-speed collision")
    end)
    test("prospective lookahead includes obstacles beyond slowed native speed shortlist",function()
        local p=fixture({walkSpeed=8,allowSprintDetour=true,sprintSpeed=27,
            opponents={{position=Vector3.new(0,0,9.6),velocity=Vector3.zero}}})
        local _,d=Avoidance.update(nil,p)
        assert(d.active and not d.sprint,"future sprint obstacle was excluded by current slow speed")
    end)
    test("sprint option never spends sprint during contact or measured physical blocking",function()
        local p=fixture({allowSprintDetour=true,sprintSpeed=27});local state,d
        for i=0,9 do
            p.now=i*.05;p.dt=.05;p.position=Vector3.new(0,0,p.now*(.77/.43))
            p.velocity=Vector3.new(0,0,27)
            p.opponents={{position=p.position+Vector3.new(0,0,3.7),velocity=Vector3.zero}}
            state,d=Avoidance.update(state,p)
            assert(d.active and not d.sprint,"contact escape retained sprint")
        end
        assert(d.blocked and d.progressSpeed<2)
    end)
    test("held sprint heading is rejected when only prospective speed leaves bounds",function()
        local heading=Vector3.new(1,0,1).Unit
        local p=fixture({now=.2,position=Vector3.new(5,0,0),walkSpeed=20,
            currentDirection=heading,allowSprintDetour=true,sprintSpeed=27,
            bounds={minX=-20,maxX=9.5,minZ=-20,maxZ=50}})
        local _,d=Avoidance.update({active=true,heading=heading,side=1,clearSince=.18},p)
        assert(d.active and not d.sprint and d.reason=="holding passing side")
        same(d.direction,heading);legal(p,d.direction)
    end)
    test("safe sprint return keeps bounded turns and original analog strength",function()
        local old=Vector3.new(1,0,1).Unit
        local p=fixture({now=.2,walkSpeed=20,desiredDirection=Vector3.new(0,0,.6),
            currentDirection=old,allowSprintDetour=true,sprintSpeed=27})
        local state,d=Avoidance.update({active=true,heading=old,side=1,clearSince=0},p)
        assert(d.active and d.sprint and d.reason=="returning to path")
        assert(math.abs(d.direction.Magnitude-.6)<1e-6)
        assert(math.acos(math.clamp(state.heading:Dot(old),-1,1))<=8*p.dt+1e-6)
        p.requestedSprint=false
        local _,off=Avoidance.update({active=true,heading=old,side=1,clearSince=0},p)
        assert(not off.sprint and off.direction.Magnitude<=.6+1e-6)
    end)
    test("sprint exception requires an explicit valid native speed and preserves action priority",function()
        local heading=Vector3.new(1,0,1).Unit
        local p=fixture({now=.2,currentDirection=heading,allowSprintDetour=true})
        local state={active=true,heading=heading,side=1,clearSince=.18}
        for _,speed in ipairs({false,0,0/0,19}) do
            p.sprintSpeed=speed
            local _,d=Avoidance.update(state,p);assert(d.active and not d.sprint)
        end
        p.sprintSpeed=27;p.canDetour=false
        local reset,d=Avoidance.update(state,p)
        assert(next(reset)==nil and not d.active and d.sprint)
        same(d.direction,p.desiredDirection)
    end)
    test("opted in sprint bypass clears blocker without entering capsule or switching sides",function()
        local p=fixture({allowSprintDetour=true,sprintSpeed=27,
            opponents={{position=Vector3.new(0,0,8),velocity=Vector3.zero}}})
        local goal=Vector3.new(0,0,35)
        local state,side,minDistance=nil,nil,math.huge
        local sprintDetour,slowTurn,clear=false,false,false
        for _=1,160 do
            p.desiredDirection=(goal-p.position).Unit
            local d;state,d=Avoidance.update(state,p)
            if d.active then
                if d.sprint then sprintDetour=true else slowTurn=true end
                if d.side then side=side or d.side;assert(d.side==side) end
            elseif sprintDetour then clear=true end
            legal(p,d.direction)
            p.position=p.position+d.direction*p.walkSpeed*p.dt
            minDistance=math.min(minDistance,(p.position-p.opponents[1].position).Magnitude)
            p.walkSpeed=d.sprint and 27 or 20
            p.currentDirection=state.heading or p.desiredDirection;p.now=p.now+p.dt
            if clear and p.position.Z>16 then break end
        end
        assert(sprintDetour and slowTurn and clear,"did not exercise slow turn and safe sprint bypass")
        assert(minDistance>=3.6,"retaining sprint entered the physical capsule")
    end)
    test("timed catch takes a small clear bypass instead of the first coarse35degree angle",function()
        local p=fixture({dt=.1,walkSpeed=20,requestedSprint=false,
            opponents={{position=Vector3.new(3.6,0,4),velocity=Vector3.zero}}})
        local _,ordinary=Avoidance.update(nil,p)
        p.targetPosition=Vector3.new(0,0,30);p.arriveBy=1.5
        local state,d=Avoidance.update(nil,p)
        assert(d.active and state.side==-1 and not d.sprint)
        local angle=math.acos(math.clamp(d.direction.Unit:Dot(p.desiredDirection),-1,1))
        assert(angle<=math.rad(10)+1e-6 and angle>0,"small safe passing angle was skipped")
        assert(d.direction.Z>ordinary.direction.Z,"refinement did not reduce sideways travel")
        local relative=p.opponents[1].position-p.position
        local velocity=-d.direction*p.walkSpeed
        local at=math.clamp(-relative:Dot(velocity)/velocity:Dot(velocity),0,.25)
        assert((relative+velocity*at).Magnitude>=3.75-1e-6,"shorter path crossed the capsule")
        legal(p,d.direction)
    end)
    test("catch with no travel slack returns without spending the clearpath hold",function()
        local old=Vector3.new(-math.sin(math.rad(35)),0,math.cos(math.rad(35)))
        local p=fixture({now=.05,walkSpeed=20,requestedSprint=false,currentDirection=old,
            targetPosition=Vector3.new(0,0,30),arriveBy=1.55})
        local previous={active=true,heading=old,side=-1,desiredHeading=p.desiredDirection,clearSince=.04}
        local state,d=Avoidance.update(previous,p)
        assert(d.reason=="returning to path" and state.returningForDeadline)
        assert(state.heading:Dot(p.desiredDirection)>old:Dot(p.desiredDirection))
        assert(math.acos(math.clamp(state.heading:Dot(old),-1,1))<=8*p.dt+1e-6)
        assert(previous.returningForDeadline==nil,"deadline decision mutated prior state")
        for _=1,3 do
            p.now=p.now+p.dt;p.currentDirection=state.heading
            local before=state.heading
            state,d=Avoidance.update(state,p)
            assert(d.reason~="holding passing side","deadline return restarted the old hold")
            assert(state.heading:Dot(p.desiredDirection)>=before:Dot(p.desiredDirection)-1e-6)
            legal(p,d.direction)
        end
    end)
    test("funded catch path retains ordinary boundary hysteresis",function()
        local old=Vector3.new(-math.sin(math.rad(35)),0,math.cos(math.rad(35)))
        local p=fixture({now=.05,walkSpeed=20,requestedSprint=false,currentDirection=old,
            targetPosition=Vector3.new(0,0,10),arriveBy=2})
        local state,d=Avoidance.update({active=true,heading=old,side=-1,clearSince=.04},p)
        assert(d.reason=="holding passing side" and not state.returningForDeadline)
        same(d.direction,old)
    end)
    test("expired catch deadline cannot bypass collision or field bounds",function()
        local p=fixture({now=1,targetPosition=Vector3.new(0,0,20),arriveBy=.9,
            allowSprintDetour=true,sprintSpeed=27,bounds={minX=-1,maxX=1,minZ=-10,maxZ=30},
            opponents={{position=Vector3.new(0,0,3.5),velocity=Vector3.zero}}})
        local _,d=Avoidance.update(nil,p)
        same(d.direction,Vector3.zero);assert(d.active and not d.sprint)
        legal(p,d.direction)
    end)
    test("deadline return still checks the bounded currentheading collision",function()
        local old=Vector3.new(1,0,0)
        local p=fixture({now=.05,currentDirection=old,targetPosition=Vector3.new(0,0,30),arriveBy=.5,
            allowSprintDetour=true,sprintSpeed=27,
            opponents={{position=Vector3.new(4.5,0,0),velocity=Vector3.zero}}})
        local state,d=Avoidance.update({active=true,heading=old,side=-1,clearSince=.04},p)
        assert(d.active and not d.sprint)
        local relative=p.opponents[1].position-p.position
        local velocity=-d.direction*p.walkSpeed
        local at=velocity:Dot(velocity)>.000001
            and math.clamp(-relative:Dot(velocity)/velocity:Dot(velocity),0,.25) or 0
        assert((relative+velocity*at).Magnitude>=3.75-1e-6)
        assert(math.acos(math.clamp(state.heading:Dot(old),-1,1))<=8*p.dt+1e-6)
        legal(p,d.direction)
    end)
    test("malformed optional deadlines preserve default avoidance",function()
        local p=fixture({now=.05,walkSpeed=20,currentDirection=Vector3.new(1,0,1).Unit})
        local previous={active=true,heading=p.currentDirection,side=1,clearSince=.04}
        local _,expected=Avoidance.update(previous,p)
        for _,deadline in ipairs({false,0/0,math.huge}) do
            p.targetPosition=Vector3.new(0,0,20);p.arriveBy=deadline
            local _,d=Avoidance.update(previous,p)
            same(d.direction,expected.direction);assert(d.reason==expected.reason and d.sprint==expected.sprint)
        end
        p.arriveBy=1;p.targetPosition=Vector3.new(0/0,0,20)
        local _,d=Avoidance.update(previous,p);same(d.direction,expected.direction)
    end)
    test("timed bypass keeps one side and reduces lateral distance in authored movement",function()
        local function run(timed)
            local p=fixture({allowSprintDetour=true,sprintSpeed=27,
                opponents={{position=Vector3.new(0,0,8),velocity=Vector3.zero}}})
            local goal=Vector3.new(0,0,35)
            if timed then p.targetPosition=goal;p.arriveBy=1.3 end
            local state,side,path,minimum=nil,nil,0,math.huge
            for _=1,200 do
                p.desiredDirection=(goal-p.position).Unit
                local d;state,d=Avoidance.update(state,p)
                if d.side then side=side or d.side;assert(d.side==side,"timed bypass switched sides") end
                legal(p,d.direction)
                local step=d.direction*p.walkSpeed*p.dt
                p.position=p.position+step;path=path+step.Magnitude
                minimum=math.min(minimum,(p.position-p.opponents[1].position).Magnitude)
                p.walkSpeed=d.sprint and 27 or 20
                p.currentDirection=state.heading or p.desiredDirection;p.now=p.now+p.dt
                if not d.active and p.position.Z>16 then return path,minimum end
            end
            error("timed bypass never returned to the path")
        end
        local ordinary=run(false)
        local timed,minimum=run(true)
        assert(timed<ordinary-.3,"shorter safe angles did not reduce the detour")
        assert(minimum>=3.75-1e-6,"deadline spent physical capsule clearance")
        -- This fixture integrates requested movement directly. It does not
        -- claim Roblox inertia, latency, or a catch outcome is reproduced.
    end)
    return report
end
