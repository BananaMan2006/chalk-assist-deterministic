-- Executes the real controller's helper/navigation/catch movement blocks.
-- Avoidance decisions and Humanoid calls are fixtures, not native physics.
return function(source)
    local helpers=assert(source:match("(    local function smoothDirection.-)    local function moveWRApproach"))
    local navigation=assert(source:match("(    local function updateFullplay.-)    local function updateWRReturn"))
    local catch=assert(source:match("            if moving then\n(.-)            else\n                h:Move%(Vector3.zero"))
    local cancellation=assert(source:match("(    local function releaseSprint.-)    local walls"))
    local handoff=assert(source:match("            local preserveMovement=(.-)\n            cancel%(preserveMovement%)"))
    local compile=loadstring or load
    local cancelFactory=assert(compile([[
return function(f)
    local navigation,ownsSprint=true,true
    local navigationIdleSince,navigationIdleRoot=1,f.root
    local trackedSprintRoot,sprintTracking=f.root,f.tracking
    local steering,atTarget,parkedPosition=f.direction,true,f.root
    local controlledHumanoid=f.h
    local avoidanceState,avoidanceRoot,avoidancePhase,lastAvoidanceReason={token=true},f.root,"Live","blocked"
    local avoidanceStatus={active=true,blocked=true}
    local plan,lastSnapshot={},{ }
    local jumped,dived,jumpRequest=true,true,{}
    local confirmedCatchJump,groundedReachSince,reachAirborne={},1,false
    local wrFake,wrReturn={},{}
    local UIS={IsKeyDown=function() return false end}
    local Enum={KeyCode={LeftShift="left",RightShift="right"}}
    local Moves={HoldSprint=function(value)
        f.sprinting=value;f.sprintCalls[#f.sprintCalls+1]=value
    end}
    local carrierAssist={cancel=function() f.carrierCancelled=f.carrierCancelled+1 end}
    local function releaseInput() f.inputReleased=true end
]]..cancellation..[[
    return function(preserve)
        cancel(preserve)
        return {clean=plan==nil and lastSnapshot==nil and not jumped and not dived and jumpRequest==nil
            and confirmedCatchJump==nil and groundedReachSince==nil and reachAirborne==nil
            and wrFake==nil and wrReturn==nil and not atTarget and parkedPosition==nil,
            steering=steering,controlledHumanoid=controlledHumanoid,ownsSprint=ownsSprint,
            tracking=sprintTracking,root=trackedSprintRoot,navigation=navigation,
            avoidanceActive=avoidanceStatus.active,idleSince=navigationIdleSince,idleRoot=navigationIdleRoot}
    end
end
]],"player-avoidance-cancel-fixture"))()
    local canHandoff=assert(compile([[
return function(s,ownsSprint,sprinting,controlledHumanoid)
    local me={GetAttribute=function() return sprinting end}
    return ]]..handoff.."\nend\n","player-avoidance-handoff-fixture"))()
    local factory=assert(compile([[
return function(f)
    local steering,navigation,controlledHumanoid,ownsSprint
    local navigationIdleSince,navigationIdleRoot
    local jumped,dived,jumpRequest
    local trackedSprintRoot,sprintTracking
    local avoidanceState,avoidanceRoot,avoidancePhase,lastAvoidanceReason
    local avoidanceStatus={active=false,blocked=false}
    local lastAvoidanceLog=0
    local Field={MinX=-30,MaxX=30,BackZ=0,EndZ=120}
    local Config={RunSpeed=20,SprintSpeed=27}
    local Enum={Material={Air="Air"}}
    local ctx={fullplay=function() return f.directive end}
    local me={GetAttribute=function(_,key)
        if key=="SprintOn" then return f.sprinting end
        if key=="Stamina" then return f.stamina end
    end}
    local Moves={Upright=function() return true end,HoldSprint=function(value)
        f.sprinting=value;f.sprintCalls[#f.sprintCalls+1]=value
    end}
    local carrierAssist=f.carrier
    local function ownInput() end
    local function releaseSprint() f.sprinting=false end
    local function sprintBudget() return {canSprint=f.canSprint~=false} end
    local function xyz(value) return value end
    local function log(kind,data) f.logs[#f.logs+1]={kind=kind,data=data} end
    local PlayerAvoidance={update=function(previous,input)
        f.helperCalls[#f.helperCalls+1]={previous=previous,input=input}
        local decision=f.decision or {}
        return {token=#f.helperCalls},{direction=decision.direction or input.desiredDirection,
            sprint=decision.sprint==nil and input.requestedSprint or decision.sprint,
            active=decision.active==true,blocked=decision.blocked==true,reason=decision.reason}
    end}
]]..helpers..navigation..[[
    return {
        navigate=function(s,dt)
            jumped,dived,jumpRequest=f.jumped,f.dived,f.jumpRequest
            return updateFullplay(s,f.root,f.h,f.now,dt or 1/60)
        end,
        avoid=function(s,direction,requested,canDetour)
            return avoidPlayers(s,f.root,f.h,f.now,1/60,direction,requested,canDetour)
        end,
        status=function() return avoidanceStatus end,
        catch=function(s,dt)
            local root,h,now=f.root,f.h,f.now
            local plan=f.plan
            local delta=(plan.approachTarget-root.Position)*Vector3.new(1,0,1)
            local jumped,jumpRequest,dived=f.jumped,f.jumpRequest,f.dived
            local nextReplan=f.nextReplan or math.huge
            dt=dt or 1/60
]]..catch..[[
            f.nextReplan=nextReplan
        end,
    }
end
]],"player-avoidance-controller-fixture"))()
    local report={total=0,passed=0,failed=0,results={}}
    local function equal(actual,expected,label)
        assert(actual==expected,(label or "mismatch")..": expected "..tostring(expected)..", got "..tostring(actual))
    end
    local function close(a,b,label) assert((a-b).Magnitude<1e-8,label or "movement vector changed") end
    local function test(name,body)
        report.total=report.total+1
        local ok,err=pcall(body)
        report[ok and "passed" or "failed"]=report[ok and "passed" or "failed"]+1
        report.results[#report.results+1]={name=name,passed=ok,error=not ok and tostring(err) or nil}
    end
    local function fixture()
        local f={now=10,stamina=100,sprinting=false,moves={},sprintCalls={},helperCalls={},logs={}}
        f.root={Position=Vector3.new(0,3,5),AssemblyLinearVelocity=Vector3.zero}
        f.h={WalkSpeed=20,FloorMaterial="Ground",Move=function(_,direction,relative)
            equal(relative,false);f.moves[#f.moves+1]=direction
        end}
        f.context={role="DB",phase="Live",playBudget={dbReserve=40}}
        f.plan={direction=Vector3.new(0,0,1),approachTarget=Vector3.new(0,3,20),contactAt=12}
        f.api=factory(f)
        return f
    end
    test("manual low-stamina catch preserves user sprint and analog strength",function()
        local f=fixture();f.context.playBudget=nil;f.sprinting=true;f.canSprint=false;f.stamina=1
        f.plan.movementScale=.4;f.api.catch(f.context)
        equal(#f.helperCalls,0);equal(#f.sprintCalls,0);equal(f.sprinting,true)
        close(f.moves[1],Vector3.new(0,0,.4))
    end)
    test("catch avoidance receives the current approach point and earliest arrival deadline",function()
        local f=fixture();f.plan.kind="jumpDive";f.plan.stopAt=11.8;f.plan.diveAt=11.5
        f.api.catch(f.context)
        local input=f.helperCalls[#f.helperCalls].input
        close(input.targetPosition,f.plan.approachTarget)
        equal(input.arriveBy,11.5)
        f.plan.kind="jump";f.plan.diveAt=nil;f.plan.stopAt=12.08
        f.api.catch(f.context);equal(f.helperCalls[#f.helperCalls].input.arriveBy,12)
        f.plan.kind="pursue";f.api.catch(f.context)
        equal(f.helperCalls[#f.helperCalls].input.arriveBy,nil)
        equal(f.helperCalls[#f.helperCalls].input.targetPosition,nil)
    end)
    test("clear navigation preserves directive strength and an already-on sprint",function()
        local f=fixture();f.sprinting=true
        f.directive={direction=Vector3.new(0,0,.35),sprint=true,preserveDepth=true}
        assert(f.api.navigate(f.context));assert(f.api.navigate(f.context))
        close(f.moves[1],f.directive.direction);close(f.moves[2],f.directive.direction)
        equal(#f.sprintCalls,0);equal(f.helperCalls[1].input.requestedSprint,true)
    end)
    test("WR route arrival is forwarded without giving DB navigation a catch deadline",function()
        local f=fixture();f.context.role="WR"
        f.directive={direction=Vector3.new(0,0,1),sprint=false,
            avoidanceArrival={targetPosition=Vector3.new(0,3,40),arriveBy=11.8}}
        f.api.navigate(f.context)
        local input=f.helperCalls[#f.helperCalls].input
        close(input.targetPosition,f.directive.avoidanceArrival.targetPosition);equal(input.arriveBy,11.8)
        f.context.role="DB";f.api.navigate(f.context)
        equal(f.helperCalls[#f.helperCalls].input.targetPosition,nil)
        equal(f.helperCalls[#f.helperCalls].input.arriveBy,nil)
    end)
    test("blocked navigation applies bypass direction and disables sprint once",function()
        local f=fixture();f.sprinting=true
        f.directive={direction=Vector3.new(0,0,1),sprint=true,preserveDepth=true}
        f.decision={direction=Vector3.new(.6,0,0),sprint=false,active=true,blocked=true,reason="blocked"}
        assert(f.api.navigate(f.context));assert(f.api.navigate(f.context))
        close(f.moves[1],f.decision.direction);close(f.moves[2],f.decision.direction)
        equal(#f.sprintCalls,1);equal(f.sprintCalls[1],false)
        equal(f.api.status().blocked,true)
    end)
    test("navigation applies explicit holds and obeys collision and sprint overrides",function()
        local f=fixture()
        f.directive={direction=Vector3.new(0,0,1),sprint=false}
        f.api.navigate(f.context);f.api.navigate(f.context)
        equal(#f.moves,2);close(f.moves[1],f.directive.direction)
        f.directive.direction=Vector3.zero
        f.api.navigate(f.context);close(f.moves[#f.moves],Vector3.zero)
        f.directive.direction=Vector3.new(0,0,1)
        f.decision={active=true,direction=Vector3.new(1,0,0),sprint=false}
        f.api.navigate(f.context);close(f.moves[#f.moves],f.decision.direction)
        f.decision=nil;f.directive.sprint=true;f.canSprint=false
        f.api.navigate(f.context);equal(f.sprinting,false)
    end)
    test("confirmed Full Auto stop discards the old backward heading before forward coverage restarts",function()
        local f=fixture()
        f.directive={direction=Vector3.new(0,0,-1),sprint=false,preserveDepth=true}
        f.api.navigate(f.context)
        close(f.moves[#f.moves],Vector3.new(0,0,-1))
        f.directive.direction=Vector3.zero
        f.now=10.1;f.api.navigate(f.context)
        f.now=10.24;f.api.navigate(f.context)
        assert(f.helperCalls[#f.helperCalls].input.currentDirection,"short stop cleared heading early")
        f.now=10.26;f.api.navigate(f.context)
        equal(f.helperCalls[#f.helperCalls].input.currentDirection,nil)
        equal(f.helperCalls[#f.helperCalls].previous,nil,"stale avoidance survived confirmed stop")
        f.directive.direction=Vector3.new(0,0,1)
        f.now=10.28;f.api.navigate(f.context)
        close(f.moves[#f.moves],Vector3.new(0,0,1),"forward restart walked backward")
        equal(f.sprinting,false)
    end)
    test("moving direction reversals retain the native controller turn bound",function()
        local f=fixture()
        f.directive={direction=Vector3.new(0,0,-1),sprint=false,preserveDepth=true}
        f.api.navigate(f.context);f.root.AssemblyLinearVelocity=Vector3.new(0,0,-20)
        f.directive.direction=Vector3.new(0,0,1);f.now=11;f.api.navigate(f.context)
        local output=f.moves[#f.moves]
        assert(output.Z<0,"moving reversal bypassed steering")
        assert(output:Dot(Vector3.new(0,0,-1))>=math.cos(9/60)-1e-8,"turn exceeded9rad/sec")
    end)
    test("zero requested movement while coasting does not count as a confirmed stop",function()
        local f=fixture()
        f.directive={direction=Vector3.new(0,0,-1),sprint=false};f.api.navigate(f.context)
        f.directive.direction=Vector3.zero;f.root.AssemblyLinearVelocity=Vector3.new(0,0,-2)
        f.now=10.1;f.api.navigate(f.context);f.now=11;f.api.navigate(f.context)
        f.directive.direction=Vector3.new(0,0,1);f.api.navigate(f.context)
        assert(f.moves[#f.moves].Z<0,"coasting reset a live travel heading")
    end)
    test("movement resumption and root changes restart the idle confirmation interval",function()
        for _,change in ipairs({"movement","root"}) do
            local f=fixture();f.directive={direction=Vector3.new(0,0,-1),sprint=false}
            f.api.navigate(f.context);f.directive.direction=Vector3.zero
            f.now=10.1;f.api.navigate(f.context)
            if change=="movement" then
                f.now=10.2;f.directive.direction=Vector3.new(0,0,-1);f.api.navigate(f.context)
            else
                f.root={Position=Vector3.new(0,3,5),AssemblyLinearVelocity=Vector3.zero}
            end
            f.now=10.21;f.directive.direction=Vector3.zero;f.api.navigate(f.context)
            f.now=10.3;f.directive.direction=Vector3.new(0,0,1);f.api.navigate(f.context)
            assert(f.moves[#f.moves].Z<0,change.." reused an older idle interval")
        end
    end)
    test("manual catch airborne and committed action states cannot clear navigation steering",function()
        for _,gate in ipairs({"manual","arc","air","jumped","jumpRequest","dived"}) do
            local f=fixture();f.directive={direction=Vector3.new(0,0,-1),sprint=false}
            f.api.navigate(f.context)
            if gate=="manual" then f.context.playBudget=nil
            elseif gate=="arc" then f.context.arc={}
            elseif gate=="air" then f.h.FloorMaterial="Air"
            else f[gate]=true end
            f.directive.direction=Vector3.zero
            f.now=10.1;f.api.navigate(f.context);f.now=10.4;f.api.navigate(f.context)
            f.directive.direction=Vector3.new(0,0,1);f.api.navigate(f.context)
            assert(f.moves[#f.moves].Z<0,gate.." lost its existing steering")
        end
    end)
    test("clear catch does not toggle an already-on sprint",function()
        local f=fixture();f.sprinting=true;f.api.catch(f.context);f.api.catch(f.context)
        equal(#f.sprintCalls,0);close(f.moves[1],f.plan.direction)
    end)
    test("blocked catch applies bypass and requests an early replan",function()
        local f=fixture();f.sprinting=true
        f.decision={direction=Vector3.new(.5,0,0),sprint=false,active=true,blocked=true,reason="blocked"}
        f.api.catch(f.context);close(f.moves[1],f.decision.direction)
        equal(#f.sprintCalls,1);equal(f.sprintCalls[1],false)
        equal(f.nextReplan,10.1)
    end)
    test("turning Full Auto off clears status and old bypass state",function()
        local f=fixture();local direction=Vector3.new(0,0,1)
        f.decision={active=true,blocked=true,reason="blocked"}
        f.api.avoid(f.context,direction,true,true);equal(f.api.status().active,true)
        f.context.playBudget=nil
        local disabled=f.api.avoid(f.context,direction,true,true)
        close(disabled.direction,direction);equal(disabled.sprint,true);equal(f.api.status().active,false)
        f.context.playBudget={dbReserve=40};f.api.avoid(f.context,direction,true,true)
        equal(f.helperCalls[2].previous,nil)
    end)
    test("character and phase changes reset previous bypass state",function()
        local f=fixture();local direction=Vector3.new(0,0,1)
        f.api.avoid(f.context,direction,true,true);f.api.avoid(f.context,direction,true,true)
        assert(f.helperCalls[2].previous)
        f.context.phase="RAC";f.api.avoid(f.context,direction,true,true)
        equal(f.helperCalls[3].previous,nil)
        f.root={Position=Vector3.new(0,3,5),AssemblyLinearVelocity=Vector3.zero}
        f.api.avoid(f.context,direction,true,true);equal(f.helperCalls[4].previous,nil)
    end)
    test("catch action deadlines and committed actions forbid detours",function()
        for _,key in ipairs({"jumpAt","diveAt","contactAt"}) do
            local f=fixture();f.plan[key]=10.3;f.api.catch(f.context)
            equal(f.helperCalls[1].input.canDetour,false,key)
        end
        for _,key in ipairs({"jumped","jumpRequest","dived"}) do
            local f=fixture();f[key]=true;f.api.catch(f.context)
            equal(f.helperCalls[1].input.canDetour,false,key)
        end
        local f=fixture();f.api.catch(f.context);equal(f.helperCalls[1].input.canDetour,true)
    end)
    test("airborne and platform-standing movement never authorizes a detour",function()
        local f=fixture();f.h.FloorMaterial="Air";f.api.catch(f.context)
        equal(f.helperCalls[1].input.canDetour,false)
        f.h.FloorMaterial="Ground";f.h.PlatformStand=true;f.api.catch(f.context)
        equal(f.helperCalls[2].input.canDetour,false)
    end)
    test("reserve-denied navigation does not request sprint from the helper",function()
        local f=fixture();f.canSprint=false;f.directive={direction=Vector3.new(0,0,1),sprint=true}
        f.api.navigate(f.context);equal(f.helperCalls[1].input.requestedSprint,false)
        equal(f.sprinting,false);close(f.moves[1],Vector3.new(0,0,1))
    end)
    test("active carrier action takes priority without an avoidance call",function()
        local f=fixture();f.carrier={update=function() return true,"carrier burst" end}
        f.api=factory(f);f.directive={direction=Vector3.new(0,0,1),sprint=true};f.sprinting=true
        local active,note=f.api.navigate(f.context)
        equal(active,true);equal(note,"carrier burst");equal(#f.helperCalls,0);equal(#f.moves,0)
        equal(f.sprinting,false)
    end)
    test("committed WR route permits checked sprint detours while ordinary DB coverage does not",function()
        local f=fixture();f.context.role="WR";f.context.catchIntent={continuousSprint=true}
        f.api.catch(f.context)
        equal(f.helperCalls[1].input.allowSprintDetour,true)
        equal(f.helperCalls[1].input.sprintSpeed,27)
        f.context.role="DB";f.api.catch(f.context)
        equal(f.helperCalls[2].input.allowSprintDetour,false)
        f.context.role="WR";f.context.phase="RAC";f.api.catch(f.context)
        equal(f.helperCalls[3].input.allowSprintDetour,false)
        f.context.phase="Live";f.context.catchIntent.continuousSprint=false;f.api.catch(f.context)
        equal(f.helperCalls[4].input.allowSprintDetour,false)
        f.context.catchIntent=nil;f.api.catch(f.context)
        equal(f.helperCalls[5].input.allowSprintDetour,false)
    end)
    test("DB interception permits a checked sprint only with a live ball and reachable arrival",function()
        local f=fixture();f.context.arc={};f.plan.kind="jumpDive"
        f.api.catch(f.context)
        equal(f.helperCalls[1].input.allowSprintDetour,true)
        equal(f.helperCalls[1].input.sprintSpeed,27)
        f.plan.kind="pursue";f.api.catch(f.context)
        equal(f.helperCalls[2].input.allowSprintDetour,false)
        f.plan.kind="jump";f.context.arc=nil;f.api.catch(f.context)
        equal(f.helperCalls[3].input.allowSprintDetour,false)
        f.context.arc={};f.context.phase="RAC";f.api.catch(f.context)
        equal(f.helperCalls[4].input.allowSprintDetour,false)
    end)
    test("DB checked sprint still obeys reserve action and ground restrictions",function()
        local f=fixture();f.context.arc={};f.plan.kind="jumpDive";f.canSprint=false
        f.api.catch(f.context)
        equal(f.helperCalls[1].input.allowSprintDetour,true)
        equal(f.helperCalls[1].input.requestedSprint,false)
        f.canSprint=true;f.plan.jumpAt=10.2;f.api.catch(f.context)
        equal(f.helperCalls[2].input.canDetour,false)
        f.plan.jumpAt=nil;f.h.FloorMaterial="Air";f.api.catch(f.context)
        equal(f.helperCalls[3].input.canDetour,false)
        f.context.playBudget=nil;f.api.catch(f.context)
        equal(#f.helperCalls,3)
    end)
    test("WR sprint detour permission preserves budget and catch action gates",function()
        local f=fixture();f.context.role="WR";f.context.catchIntent={continuousSprint=true}
        f.canSprint=false;f.api.catch(f.context)
        equal(f.helperCalls[1].input.allowSprintDetour,true)
        equal(f.helperCalls[1].input.requestedSprint,false)
        f.canSprint=true;f.plan.jumpAt=10.2;f.api.catch(f.context)
        equal(f.helperCalls[2].input.canDetour,false)
        f.context.playBudget=nil;f.api.catch(f.context)
        equal(#f.helperCalls,2)
    end)
    test("a WR catch handoff can keep a checked sprint before the abandoned stem deadline",function()
        local f=fixture();f.context.role="WR";f.context.arc={};f.context.catchIntent={continuousSprint=false}
        f.api.catch(f.context)
        equal(f.helperCalls[1].input.allowSprintDetour,true)
        equal(f.helperCalls[1].input.requestedSprint,true)
        f.canSprint=false;f.api.catch(f.context)
        equal(f.helperCalls[2].input.requestedSprint,false)
        f.plan.kind="pursue";f.api.catch(f.context)
        equal(f.helperCalls[3].input.allowSprintDetour,false)
    end)
    test("committed WR navigation retains a helper-approved active sprint",function()
        local f=fixture();f.context.role="WR";f.context.catchIntent={continuousSprint=true}
        f.directive={direction=Vector3.new(0,0,1),sprint=true}
        f.decision={direction=Vector3.new(.6,0,.8),sprint=true,active=true,blocked=false}
        f.api.navigate(f.context)
        equal(f.helperCalls[1].input.allowSprintDetour,true)
        equal(f.sprinting,true);close(f.moves[1],f.decision.direction)
    end)
    test("roster duplicates are inspected once and field offset reaches helper",function()
        local f=fixture()
        local other={Position=Vector3.new(1,3,5),AssemblyLinearVelocity=Vector3.zero}
        local character={FindFirstChild=function() return other end,
            FindFirstChildOfClass=function() return {Health=100} end}
        f.context.opponent=character;f.context.opponents={character,character}
        f.context.offset=Vector3.new(100,0,200)
        f.api.catch(f.context)
        local input=f.helperCalls[1].input
        equal(#input.opponents,1);equal(input.bounds.minX,70.5);equal(input.bounds.minZ,200.5)
    end)
    test("throw handoff clears catch actions without stopping existing movement",function()
        local f=fixture();f.tracking={pending=true};f.direction=Vector3.new(0,0,1)
        f.h.Parent={};f.carrierCancelled=0;f.sprinting=true
        local state=cancelFactory(f)(true)
        equal(state.clean,true);equal(state.navigation,false);equal(f.carrierCancelled,1)
        equal(#f.sprintCalls,0);equal(#f.moves,0);equal(f.inputReleased,nil)
        equal(state.controlledHumanoid,f.h);equal(state.ownsSprint,true)
        equal(state.tracking,f.tracking);equal(state.root,f.root);close(state.steering,f.direction)
        equal(state.idleSince,nil);equal(state.idleRoot,nil)
        equal(f.sprinting,true)
    end)
    test("normal cancellation clears catch actions and releases movement",function()
        local f=fixture();f.tracking={pending=true};f.direction=Vector3.new(0,0,1)
        f.h.Parent={};f.carrierCancelled=0;f.sprinting=true
        local state=cancelFactory(f)()
        equal(state.clean,true);equal(state.navigation,false);equal(f.carrierCancelled,1)
        equal(#f.sprintCalls,1);equal(f.sprintCalls[1],false);equal(f.inputReleased,true)
        equal(#f.moves,1);close(f.moves[1],Vector3.zero)
        equal(state.controlledHumanoid,nil);equal(state.ownsSprint,false)
        equal(state.tracking,nil);equal(state.root,nil);equal(state.steering,nil)
        equal(state.idleSince,nil);equal(state.idleRoot,nil)
        equal(state.avoidanceActive,false)
    end)
    test("throw handoff requires Full Auto and a live owned sprint",function()
        local h={Parent={},PlatformStand=false}
        local full={playBudget={dbReserve=40}}
        assert(canHandoff(full,true,true,h))
        assert(not canHandoff({},true,true,h),"manual movement was preserved")
        assert(not canHandoff(full,false,true,h),"unowned sprint was preserved")
        assert(not canHandoff(full,true,false,h),"inactive sprint was preserved")
        assert(not canHandoff(full,true,true,nil),"missing humanoid was preserved")
        assert(not canHandoff(full,true,true,{}),"removed humanoid was preserved")
        assert(not canHandoff(full,true,true,{Parent={},PlatformStand=true}),"diving humanoid was preserved")
    end)
    return report
end
