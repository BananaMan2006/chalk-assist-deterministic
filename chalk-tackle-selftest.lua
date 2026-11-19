-- Isolated character fixtures; native actions are replaced with recording stubs.
return function(Planner,createTackle,Config,Field)
    -- Lua's offline runtime names its upvalue reader differently from the
    -- native executor. Inspect the actual fixture closure in either runtime.
    local priorGetUps=getupvalues
    if not (debug and debug.getupvalues) and not getupvalues and debug and debug.getupvalue then
        getupvalues=function(fn)
            local result={}
            for i=1,30 do
                local name,value=debug.getupvalue(fn,i)
                if not name then break end
                result[#result+1]=value
            end
            return result
        end
    end
    local results,failed={},0
    local function test(name,fn)
        local fixture=Instance.new("Folder")
        local ok,err=pcall(fn,fixture)
        fixture:Destroy()
        table.insert(results,{name=name,passed=ok,error=not ok and tostring(err) or nil})
        if not ok then failed=failed+1 end
    end
    local function setup(folder,options)
        options=options or {}
        local target=Instance.new("Model");target.Name="TestCarrier";target.Parent=folder
        local targetRoot=Instance.new("Part");targetRoot.Name="HumanoidRootPart";targetRoot.Parent=target
        targetRoot.Position=Vector3.new(options.distance or 3,Field.TurfY+3+(options.height or 0),0)
        targetRoot.AssemblyLinearVelocity=Vector3.new(options.horizontalSpeed or 0,options.verticalSpeed or 0,0)
        local targetHum=Instance.new("Humanoid");targetHum.Parent=target
        local own=Instance.new("Model");own.Parent=folder
        local root={Position=Vector3.new(0,Field.TurfY+3,0),AssemblyLinearVelocity=Vector3.zero,
            CFrame=CFrame.lookAt(Vector3.new(0,Field.TurfY+3,0),Vector3.new(1,Field.TurfY+3,0)),Anchored=false}
        local h={Health=100,Sit=false,FloorMaterial=Enum.Material.Grass,UseJumpPower=false,
            JumpHeight=6,WalkSpeed=20}
        local actions={grabs=0,dives=0,jumps=0,holds=0,releases=0,logs={}}
        local nativeOpponent=target
        local runtime={Config=Config,Field=Field,me={Character=own,GetAttribute=function() return 100 end},
            Moves={Upright=function() return true end,SetOpponent=function() return nativeOpponent end},
            nativeGrabTarget=function() return options.validGrab and targetRoot or nil end,
            nativeTackle=function() actions.grabs=actions.grabs+1 end,
            canDive=function() return options.canDive~=false end,
            canJump=function() return options.canJump==true end,
            clippedDistance=function(_,_,distance) return options.blocked and 0 or distance end,
            dive=function() actions.dives=actions.dives+1;return not options.rejectDive end,
            jump=function() actions.jumps=actions.jumps+1 end,
            hold=function(_,direction) actions.holds=actions.holds+1;actions.direction=direction end,
            release=function() actions.releases=actions.releases+1 end,
            log=function(kind,fields) table.insert(actions.logs,{kind=kind,fields=fields}) end}
        local s={enabled=true,alive=true,role="DB",phase=options.phase or "RAC",
            mode=options.mode,carrier=target,carrierRole=options.carrierRole,
            enemyCarrier=options.enemy~=false,defending=options.enemy~=false}
        return createTackle(Planner,runtime),s,root,h,actions,targetRoot
    end
    test("native-valid close carrier uses grab without dive",function(f)
        local a,s,r,h,n=setup(f,{validGrab=true})
        a.update(s,r,h,100,1/60)
        assert(n.grabs==1 and n.dives==0 and n.jumps==0)
    end)
    test("teammate possession never triggers tackle or movement",function(f)
        local a,s,r,h,n=setup(f,{validGrab=true,enemy=false})
        a.update(s,r,h,100,1/60)
        assert(n.grabs+n.dives+n.jumps+n.holds==0)
    end)
    test("nil native grab never calls native tackle callback",function(f)
        local a,s,r,h,n=setup(f,{validGrab=false})
        a.update(s,r,h,100,1/60)
        assert(n.grabs==0 and n.dives==0 and n.holds==1)
    end)
    test("cancellation releases only owned input once",function(f)
        local a,s,r,h,n=setup(f,{validGrab=false})
        a.cancel();assert(n.releases==0)
        a.update(s,r,h,100,1/60);a.cancel();a.cancel()
        assert(n.releases==1)
    end)
    test("distant carrier leaves manual movement untouched",function(f)
        local a,s,r,h,n=setup(f,{distance=100,canJump=true})
        a.update(s,r,h,100,1/60)
        assert(n.grabs+n.dives+n.jumps+n.holds==0)
    end)
    test("live QB cannot trigger a dive tackle",function(f)
        local a,s,r,h,n=setup(f,{distance=8,phase="Live",mode="Team",carrierRole="QB",canDive=false})
        a.update(s,r,h,100,1/60)
        assert(n.dives==0 and n.holds==0)
    end)
    test("ordinary reachable carrier uses dive without jumping",function(f)
        local a,s,r,h,n=setup(f,{distance=8,canJump=true})
        a.update(s,r,h,100,1/60)
        assert(n.dives==1 and n.jumps==0)
    end)
    test("wall-limited unreachable dive is rejected",function(f)
        local a,s,r,h,n=setup(f,{distance=10,blocked=true,canJump=false})
        a.update(s,r,h,100,1/60)
        assert(n.dives+n.jumps+n.holds==0)
    end)
    test("airborne high carrier can select jump then dive",function(f)
        local a,s,r,h,n=setup(f,{distance=8,height=4.2,verticalSpeed=40,canJump=true})
        a.update(s,r,h,100,1/60)
        assert(n.jumps==1 and n.dives==0)
        a.cancel();assert(n.releases==1)
    end)
    test("close airborne QB allows jump-grab with diving disabled",function(f)
        local a,s,r,h,n=setup(f,{distance=3,height=4.2,verticalSpeed=40,phase="Live",
            mode="Team",carrierRole="QB",canDive=false,canJump=true})
        a.update(s,r,h,100,1/60)
        assert(n.jumps==1 and n.dives==0 and n.grabs==0)
    end)
    test("far head-on carrier triggers one brief diagonal fake per possession",function(f)
        local a,s,r,h,n=setup(f,{distance=100,horizontalSpeed=-20})
        a.update(s,r,h,100,1/60)
        assert(n.holds==1 and n.direction.X>0 and math.abs(n.direction.Z)>0.5)
        a.update(s,r,h,100.1,1/60)
        assert(n.holds==2)
        a.update(s,r,h,100.5,1/60)
        a.update(s,r,h,101,1/60)
        assert(n.holds==2 and n.releases==1 and n.grabs+n.dives+n.jumps==0)
        local starts,ends=0,0
        for _,event in ipairs(n.logs) do
            if event.kind=="defensiveFakeStart" then starts=starts+1 end
            if event.kind=="defensiveFakeEnd" then ends=ends+1 end
        end
        assert(starts==1 and ends==1)
    end)
    test("closing into tackle range cancels fake before native grab",function(f)
        local a,s,r,h,n,target=setup(f,{distance=100,horizontalSpeed=-20,validGrab=true})
        a.update(s,r,h,100,1/60)
        assert(n.holds==1 and n.grabs==0)
        target.Position=r.Position+Vector3.new(3,0,0)
        a.update(s,r,h,100.1,1/60)
        assert(n.grabs==1 and n.holds==1 and n.dives==0 and n.releases==1)
        local ended=false
        for _,event in ipairs(n.logs) do
            if event.kind=="defensiveFakeEnd" and event.fields.reason=="entered tackle range" then ended=true end
        end
        assert(ended)
    end)
    test("near-endzone and advanced runs skip defensive fake",function(f)
        local a,s,r,h,n,target=setup(f,{distance=100,horizontalSpeed=-20})
        s.geo={MinX=-200,MaxX=200,BackZ=-100,EndZ=200,GoalZ=10*Field.YD,YD=Field.YD}
        a.update(s,r,h,100,1/60)
        assert(n.holds+n.grabs+n.dives+n.jumps==0)
        a.cancel(true);s.geo.GoalZ=1000;target.AssemblyLinearVelocity=Vector3.zero
        a.update(s,r,h,101,1/60)
        target.Position=target.Position+Vector3.new(0,0,9*Field.YD)
        target.AssemblyLinearVelocity=(r.Position-target.Position).Unit*20
        a.update(s,r,h,101.1,1/60)
        assert(n.holds+n.grabs+n.dives+n.jumps==0)
    end)
    test("identical tackle inputs always choose the same robust ground dive",function(f)
        local first
        for i=1,10 do
            local a,s,r,h,n=setup(f,{distance=7,height=1,verticalSpeed=25,canJump=true})
            a.update(s,r,h,100,1/60)
            assert(n.dives==1 and n.jumps==0)
            local planned
            for _,row in ipairs(n.logs) do if row.kind=="tacklePlan"then planned=row.fields end end
            assert(planned and planned.contactWindow>=.039 and planned.margin>=planned.requiredMargin)
            if first then
                assert(planned.contactIn==first.contactIn and planned.direction.x==first.direction.x
                    and planned.direction.z==first.direction.z)
            else first=planned end
        end
    end)
    test("jump dive rechecks a changed carrier before committing",function(f)
        local a,s,r,h,n,target=setup(f,{distance=8,height=4.2,verticalSpeed=40,canJump=true})
        a.update(s,r,h,100,1/60);assert(n.jumps==1 and n.dives==0)
        h.FloorMaterial=Enum.Material.Air;target.Position=target.Position+Vector3.new(100,0,0)
        a.update(s,r,h,100.11,1/60)
        assert(n.dives==0 and n.releases==1)
    end)
    test("required jump dives only after airborne confirmation and a fresh contact witness",function(f)
        local a,s,r,h,n,target=setup(f,{distance=8,height=4.2,verticalSpeed=40,canJump=true})
        a.update(s,r,h,100,1/60);assert(n.jumps==1 and n.dives==0)
        a.update(s,r,h,100.09,1/60);assert(n.dives==0,"grounded jump request triggered dive")
        local elapsed=.10;local gravity=workspace.Gravity;local speed=math.sqrt(2*gravity*h.JumpHeight)
        h.FloorMaterial=Enum.Material.Air
        r.Position=r.Position+Vector3.new(h.WalkSpeed*elapsed,speed*elapsed-.5*gravity*elapsed*elapsed,0)
        r.AssemblyLinearVelocity=Vector3.new(h.WalkSpeed,speed-gravity*elapsed,0)
        target.Position=target.Position+Vector3.new(0,40*elapsed-.5*gravity*elapsed*elapsed,0)
        target.AssemblyLinearVelocity=Vector3.new(0,40-gravity*elapsed,0)
        a.update(s,r,h,100.10,1/60);assert(n.dives==1)
        a.update(s,r,h,100.12,1/60);assert(n.dives==1,"one committed tackle repeated")
    end)
    test("near goal keeps an immediately reachable dive instead of spending a jump",function(f)
        for _,goal in ipairs({1000,.09}) do
            local a,s,r,h,n,target=setup(f,{distance=7,height=1,verticalSpeed=25,canJump=true})
            target.AssemblyLinearVelocity=Vector3.new(0,25,1)
            s.geo={GoalZ=goal,MinX=-200,MaxX=200,BackZ=-100,EndZ=200,YD=Field.YD}
            a.update(s,r,h,100,1/60);assert(n.dives==1 and n.jumps==0)
        end
    end)
    test("unavailable jump and wall clipping cannot create a new tackle path",function(f)
        local a,s,r,h,n=setup(f,{distance=8,canJump=false})
        a.update(s,r,h,100,1/60);assert(n.dives==1 and n.jumps==0)
        a,s,r,h,n=setup(f,{distance=10,canJump=true,blocked=true})
        a.update(s,r,h,100,1/60);assert(n.grabs+n.dives+n.jumps==0)
    end)
    getupvalues=priorGetUps
    return {total=#results,passed=#results-failed,failed=failed,results=results}
end
