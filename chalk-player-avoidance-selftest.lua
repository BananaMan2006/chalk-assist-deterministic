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
    return report
end
