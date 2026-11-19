-- Explicit geometry and native-action fixtures, not server tackle/physics tests.
return function(create)
    local offlineStateEnum=type(Enum)=="table" and Enum.HumanoidStateType==nil
    if offlineStateEnum then Enum.HumanoidStateType={Jumping="Jumping"} end
    local report={total=0,passed=0,failed=0,results={}}
    local Config={SprintSpeed=27,Moves={Juke={Cost=20,Cooldown=.9,Speed=42,Time=.18},
        Spin={Cost=25,Cooldown=1.6,Forward=24,Side=18,Time=.45},
        Truck={Cost=45,Cooldown=2.5,Lunge=22,LungeTime=.22,LiveRange=10}},
        Tackle={GrabRange=3.5,GrabSlack=2}}
    local Field={MinX=-30,MaxX=30,BackZ=0,EndZ=140,GoalZ=120,YD=3}
    local function test(name,body)
        report.total=report.total+1
        local ok,err=pcall(body)
        report[ok and "passed" or "failed"]=report[ok and "passed" or "failed"]+1
        report.results[#report.results+1]={name=name,passed=ok,error=not ok and tostring(err) or nil}
    end
    local function input(extra)
        local p={mode="1v1",role="WR",phase="RAC",carrierIsMe=true,upright=true,
            grounded=true,healthy=true,now=10,stamina=100,
            position=Vector3.new(0,3,40),velocity=Vector3.new(0,0,20),rightDirection=Vector3.new(1,0,0),
            lookDirection=Vector3.new(0,0,1),
            opponentPosition=Vector3.new(2,3,52),opponentVelocity=Vector3.new(0,0,-10)}
        for k,v in pairs(extra or {}) do p[k]=v end
        return p
    end
    local policy=create({Config=Config,Field=Field,Moves={}})
    local function decide(p) return policy.decide(p) end
    test("near closing defender selects native juke away from pressure",function()
        local c=assert(decide(input()))
        assert(c.action=="juke" and c.sign==-1 and c.endpoint.X<0)
        assert(c.duration==.18 and c.cooldown==.9 and c.contactIn<=.45)
        assert(math.abs(c.endpoint.X+42*.18)<1e-9)
        assert(math.abs(c.endpoint.Z-(40+20*.6000000238418579*.18))<1e-9)
        assert(c.minClearance>5.75)
    end)
    test("distant separating and harmless crossing defenders do not cause a juke",function()
        assert(not decide(input({opponentPosition=Vector3.new(0,3,80)})))
        assert(not decide(input({opponentVelocity=Vector3.new(0,0,30)})))
        assert(not decide(input({opponentPosition=Vector3.new(10,3,52)})))
        assert(not decide(input({opponentPosition=Vector3.new(2,10,52)})))
    end)
    test("possession phase health air and team gates never request offensive moves",function()
        for _,change in ipairs({{carrierIsMe=false},{enemyCarrier=true},{role="DB"},{phase="Live"},
            {phase="Run"},{mode="Team"},{upright=false},{grounded=false},{healthy=false},
            {ballActive=true},{testing=true},{enabled=false}}) do
            assert(not decide(input(change)))
        end
    end)
    test("stamina retains ten units after native cost and cooldown blocks retries",function()
        assert(not decide(input({stamina=29})))
        assert(decide(input({stamina=30})))
        assert(not decide(input({nextAttempt=10.01})))
        assert(decide(input({nextAttempt=10})))
    end)
    test("sideline choice uses the open side and rejects unsafe starting space",function()
        local p=input({position=Vector3.new(27,3,40),opponentPosition=Vector3.new(29,3,52)})
        local c=assert(decide(p))
        assert(c.sign==-1 and c.endpoint.X<27)
        p.position=Vector3.new(29,3,40)
        assert(not decide(p))
    end)
    test("blocked preferred path chooses clear alternative and both blocked yields none",function()
        local p=input({clipDistance=function(_,direction,distance)
            return direction.X<0 and 0 or distance
        end})
        assert(assert(decide(p)).sign==1)
        p.clipDistance=function() return 0 end
        assert(not decide(p))
        p.clipDistance=function() error("fixture raycast failure") end
        assert(not decide(p))
    end)
    test("field translation preserves decision and world geometry overrides base bounds",function()
        local p=input();local a=assert(decide(p));local offset=Vector3.new(100,0,-200)
        p.position=p.position+offset;p.opponentPosition=p.opponentPosition+offset;p.offset=offset
        local b=assert(decide(p))
        assert(a.sign==b.sign and (b.endpoint-a.endpoint-offset).Magnitude<1e-8)
        p.offset=nil;p.geo={MinX=70,MaxX=130,BackZ=-200,EndZ=-60}
        assert(assert(decide(p)).sign==a.sign)
    end)
    test("invalid vectors and another burst speed fail closed",function()
        assert(not decide(input({velocity=Vector3.new(0,0,100)})))
        assert(not decide(input({rightDirection=Vector3.zero})))
        assert(not decide(input({position=Vector3.new(0/0,3,40)})))
        assert(not decide(input({now=0/0})))
    end)
    local function harness(behavior,available)
        local h={calls={},logs={},stamina=100,upright=true}
        h.root={Position=Vector3.new(0,3,40),AssemblyLinearVelocity=Vector3.new(0,0,20),
            CFrame={RightVector=Vector3.new(1,0,0),LookVector=Vector3.new(0,0,1)}}
        function h.root:FindFirstChild(name) return name=="Burst" and self.burst or nil end
        h.humanoid={Health=100,WalkSpeed=27,PlatformStand=false,FloorMaterial=Enum.Material.Grass,
            UseJumpPower=false,JumpHeight=6,GetStateEnabled=function() return true end,
            ChangeState=function(_,state) h.requestedState=state end}
        h.character={}
        h.enemyRoot={Position=Vector3.new(2,3,52),AssemblyLinearVelocity=Vector3.new(0,0,-10)}
        h.enemyHum={Health=100,PlatformStand=false}
        h.enemy={FindFirstChild=function(_,name) return name=="HumanoidRootPart" and h.enemyRoot end,
            FindFirstChildOfClass=function(_,name) return name=="Humanoid" and h.enemyHum end}
        h.player={Character=h.character,GetAttribute=function(_,name) return name=="Stamina" and h.stamina end}
        h.snapshot={enabled=true,mode="1v1",phase="RAC",role="WR",carrier=h.character,opponent=h.enemy}
        h.runtime={Config=Config,Field=Field,player=h.player,Moves={Upright=function() return h.upright end},
            clippedDistance=function(_,_,distance) return distance end,
            log=function(kind,data) h.logs[#h.logs+1]={kind=kind,data=data} end}
        if behavior~="unavailable" then
            h.runtime.nativeJuke=function(sign)
                h.calls[#h.calls+1]=sign
                if behavior=="error" then error("fixture native rejection") end
                if behavior~="unconfirmed" then h.root.burst={} end
                return nil
            end
            for _,action in ipairs({"spin","truck"}) do
                h.runtime[action=="spin" and "nativeSpin" or "nativeTruck"]=function()
                    h.calls[#h.calls+1]=action
                    if behavior=="error" then error("fixture native rejection") end
                    if behavior~="unconfirmed" then h.root.burst={} end
                end
            end
        end
        if available then
            if available.juke==false then h.runtime.nativeJuke=nil end
            if available.spin==false then h.runtime.nativeSpin=nil end
            if available.truck==false then h.runtime.nativeTruck=nil end
            if available.jump==false then h.humanoid.GetStateEnabled=function()return false end end
        end
        h.api=create(h.runtime)
        function h:update(now) return self.api.update(self.snapshot,self.root,self.humanoid,now or 10) end
        return h
    end
    test("only an observed native burst owns movement for a bounded duration",function()
        local h=harness()
        local position,velocity,speed=h.root.Position,h.root.AssemblyLinearVelocity,h.humanoid.WalkSpeed
        assert(h:update(10));assert(#h.calls==1 and h.calls[1]==-1)
        local requested=h.logs[#h.logs].data
        assert(requested.staminaBefore==100 and requested.staminaAfter==100 and requested.staminaAfterImmediate)
        assert(h:update(10.1) and #h.calls==1)
        h.stamina=80
        assert(not h:update(10.23) and #h.calls==1)
        assert(h.logs[#h.logs].kind=="carrierMoveEnd" and h.logs[#h.logs].data.staminaBefore==100
            and h.logs[#h.logs].data.staminaAfter==80,"post-burst telemetry lost observed stamina change")
        assert(h.api.status().observedBursts==1 and h.api.status().lastOutcome=="burstObserved")
        assert(h.root.Position==position and h.root.AssemblyLinearVelocity==velocity and h.humanoid.WalkSpeed==speed,
            "helper wrote movement directly instead of invoking native action")
    end)
    test("native nil without Burst is unconfirmed and never holds movement",function()
        local h=harness("unconfirmed")
        assert(not h:update(10) and #h.calls==1)
        assert(not h:update(10.2) and #h.calls==1)
        assert(h.api.status().lastOutcome=="unconfirmed" and h.api.status().observedBursts==0)
        assert(not h:update(11.01) and #h.calls==2)
    end)
    test("native error is isolated and rate limited while navigation can continue",function()
        local h=harness("error")
        assert(not h:update(10) and #h.calls==1)
        assert(h.api.status().error and not h:update(10.5) and #h.calls==1)
    end)
    test("missing native action or existing unrelated burst never invokes juke",function()
        local h=harness("unavailable")
        assert(not h:update() and not h.api.status().available)
        h=harness();h.root.burst={}
        assert(not h:update() and #h.calls==0)
    end)
    test("native one-on-one context without Mode still permits confirmed WR RAC",function()
        local h=harness();h.snapshot.mode=nil
        assert(h:update() and #h.calls==1)
        for _,change in ipairs({{mode="Team"},{role="TWR"},{phase="Run"}}) do
            local blocked=harness();blocked.snapshot.mode=nil
            for key,value in pairs(change) do blocked.snapshot[key]=value end
            assert(not blocked:update() and #blocked.calls==0)
        end
    end)
    test("confirmed carrier and native upright gates are checked before action",function()
        for _,gate in ipairs({"otherCarrier","missingCarrier","air","fallen","nativeHold","defenderDead","disabled"}) do
            local h=harness()
            if gate=="otherCarrier" then h.snapshot.carrier=h.enemy
            elseif gate=="missingCarrier" then h.snapshot.carrier=nil
            elseif gate=="air" then h.humanoid.FloorMaterial=Enum.Material.Air
            elseif gate=="fallen" then h.humanoid.PlatformStand=true
            elseif gate=="nativeHold" then h.upright=false
            elseif gate=="defenderDead" then h.enemyHum.Health=0
            else h.snapshot.enabled=false end
            assert(not h:update() and #h.calls==0,gate.." invoked native action")
        end
    end)
    test("moving diving tackler remains a threat despite PlatformStand",function()
        local h=harness();h.enemyHum.PlatformStand=true
        h.enemyRoot.AssemblyLinearVelocity=Vector3.new(0,0,-35)
        assert(h:update() and #h.calls==1,"native dive's PlatformStand suppressed evasion")
        local event=h.logs[#h.logs].data
        assert(event.opponentPlatformStand==true and event.opponentVelocity.z==-35)
        local away=harness();away.enemyHum.PlatformStand=true
        away.enemyRoot.AssemblyLinearVelocity=Vector3.new(0,0,35)
        assert(not away:update() and #away.calls==0,"separating dive caused unnecessary evasion")
        local down=harness();down.enemyHum.PlatformStand=true
        down.enemyRoot.AssemblyLinearVelocity=Vector3.zero
        assert(not down:update() and #down.calls==0,"stationary downed defender spent evasion stamina")
    end)
    test("possession loss missing burst cancel and unload release ownership without resetting cooldown",function()
        local h=harness();assert(h:update(10))
        h.snapshot.carrier=nil;assert(not h:update(10.05) and not h.api.status().active)
        h.snapshot.carrier=h.character;h.root.burst=nil
        assert(not h:update(10.2) and #h.calls==1)
        assert(h:update(11.01) and #h.calls==2)
        h.root.burst=nil;assert(not h:update(11.05))
        h.api.cancel();assert(not h:update(11.2) and #h.calls==2)
        h.api.unload();assert(not h:update(15) and #h.calls==2)
    end)
    local function hasAction(candidates,action)
        for _,c in ipairs(candidates) do if c.action==action then return c end end
    end
    test("repeated identical geometry keeps the same juke sign",function()
        for i=1,10 do
            local h=harness();h.enemyRoot.Position=Vector3.new(0,3,54)
            assert(h:update() and h.calls[1]==-1 and h.api.status().observedBursts==1)
        end
    end)
    test("missing juke does not trigger fallback moves without a close closing threat",function()
        for _,position in ipairs({Vector3.new(0,3,80),Vector3.new(20,3,54)}) do
            local h=harness(nil,{juke=false});h.enemyRoot.Position=position
            assert(not h:update() and #h.calls==0 and not h.humanoid.Jump)
        end
        local h=harness(nil,{juke=false});h.enemyRoot.AssemblyLinearVelocity=Vector3.new(0,0,30)
        assert(not h:update() and #h.calls==0 and not h.humanoid.Jump)
    end)
    test("native Spin is offered only when both random-side paths clear geometry",function()
        local p=input({opponentPosition=Vector3.new(0,3,54)})
        local c=assert(hasAction(policy.candidates(p),"spin"))
        assert(c.randomSide and not c.sign and c.minClearance>5.75)
        p.position=Vector3.new(22,3,40);p.opponentPosition=Vector3.new(22,3,54)
        assert(not hasAction(policy.candidates(p),"spin"),"one unsafe spin side was ignored")
        p=input({opponentPosition=Vector3.new(0,3,54),stamina=34})
        assert(not hasAction(policy.candidates(p),"spin"))
        p.stamina=35;assert(hasAction(policy.candidates(p),"spin"))
    end)
    test("native Spin fallback confirms actual Burst without choosing its random side",function()
        local h=harness(nil,{juke=false,jump=false});h.enemyRoot.Position=Vector3.new(0,3,54)
        assert(h:update() and h.calls[1]=="spin" and h.api.status().observedBursts==1)
        assert(h.logs[#h.logs].data.sign==nil)
        h.root.burst=nil;assert(not h:update(11) and #h.calls==1,"spin cooldown was discarded")
    end)
    test("Truck requires close frontal threat native stamina reserve and an in-bounds lunge",function()
        local p=input({opponentPosition=Vector3.new(0,3,48),stamina=55})
        local c=assert(hasAction(policy.candidates(p),"truck"))
        assert(c.contactAttempt and math.abs(c.endpoint.Z-44.84)<1e-8)
        for _,change in ipairs({{stamina=54},{lookDirection=Vector3.new(1,0,0)},
            {opponentPosition=Vector3.new(0,3,52)},{opponentVelocity=Vector3.new(0,0,30)},
            {clipDistance=function() return 0 end}}) do
            local q=input({opponentPosition=Vector3.new(0,3,48)})
            for k,v in pairs(change) do q[k]=v end
            assert(not hasAction(policy.candidates(q),"truck"))
        end
        p.position=Vector3.new(0,3,135);p.opponentPosition=Vector3.new(0,3,143)
        assert(not hasAction(policy.candidates(p),"truck"))
    end)
    test("native Truck fallback needs observed Burst and respects ordinary cooldown",function()
        local h=harness(nil,{juke=false,spin=false,jump=false});h.enemyRoot.Position=Vector3.new(0,3,48)
        assert(h:update() and h.calls[1]=="truck" and h.api.status().observedBursts==1)
        h.root.burst=nil;assert(not h:update(12) and #h.calls==1)
        local denied=harness("unconfirmed",{juke=false,spin=false,jump=false});denied.enemyRoot.Position=Vector3.new(0,3,48)
        assert(not denied:update() and denied.calls[1]=="truck" and denied.api.status().observedBursts==0)
    end)
    test("normal carry jump requires a real vertical clearance window without spending move stamina",function()
        local p=input({opponentPosition=Vector3.new(0,3,54),canJump=true,
            jumpSpeed=math.sqrt(2*196.2*6),gravity=196.2,stamina=10})
        local c=assert(hasAction(policy.candidates(p),"jump"))
        assert(c.minClearance>4.5 and not c.sign)
        for _,change in ipairs({{canJump=false},{jumpSpeed=0},{grounded=false},{stamina=9},
            {opponentPosition=Vector3.new(0,3,48)},{clipDistance=function() return 0 end}}) do
            local q={};for k,v in pairs(p) do q[k]=v end;for k,v in pairs(change) do q[k]=v end
            assert(not hasAction(policy.candidates(q),"jump"))
        end
    end)
    test("carry jump confirms observed takeoff rather than its request or requested Humanoid state",function()
        local h=harness();h.enemyRoot.Position=Vector3.new(0,3,54);h.stamina=10
        assert(not h:update() and h.humanoid.Jump and h.requestedState==Enum.HumanoidStateType.Jumping)
        assert(#h.calls==0 and h.api.status().observedJumps==0 and h.api.status().jumpPending)
        assert(not h:update(10.05) and h.api.status().observedJumps==0)
        h.root.Position=h.root.Position+Vector3.new(0,.3,0)
        h.root.AssemblyLinearVelocity=Vector3.new(0,40,20);h.humanoid.FloorMaterial=Enum.Material.Air
        assert(not h:update(10.06) and h.api.status().observedJumps==1 and not h.humanoid.Jump)
        h:update(10.1);assert(h.api.status().observedJumps==1)
    end)
    test("unconfirmed or cancelled carry jump never records execution or holds jump indefinitely",function()
        local h=harness();h.enemyRoot.Position=Vector3.new(0,3,54);h.stamina=10
        h:update();h:update(10.2)
        assert(h.api.status().observedJumps==0 and not h.humanoid.Jump and h.api.status().lastOutcome=="jumpUnconfirmed")
        h=harness();h.enemyRoot.Position=Vector3.new(0,3,54);h.stamina=10
        h:update();h.snapshot.carrier=nil;h:update(10.02)
        assert(h.api.status().observedJumps==0 and not h.humanoid.Jump and not h.api.status().jumpPending)
    end)
    test("safe fallback selection repeats exactly and never calls a random chooser",function()
        local random=math.random
        math.random=function()error("unexpected random chooser")end
        local ok,err=pcall(function()
            for i=1,8 do
                local spin=harness(nil,{juke=false,jump=false});spin.enemyRoot.Position=Vector3.new(0,3,54)
                assert(spin:update() and spin.calls[1]=="spin")
                local truck=harness(nil,{juke=false,spin=false,jump=false});truck.enemyRoot.Position=Vector3.new(0,3,48)
                assert(truck:update() and truck.calls[1]=="truck")
                local jump=harness();jump.enemyRoot.Position=Vector3.new(0,3,54);jump.stamina=10
                assert(not jump:update() and jump.humanoid.Jump and #jump.calls==0)
            end
        end)
        math.random=random;assert(ok,err)
    end)
    report.fixture="Native Juke numeric configuration with explicit positions; no server acceptance, collision physics, or tackle outcome simulation."
    if offlineStateEnum then Enum.HumanoidStateType=nil end
    return report
end
