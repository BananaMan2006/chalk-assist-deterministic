-- Actual callback/tick/cancellation source with authored services and real avoidance math.
-- No native physics, network acceptance, or catch-rescue outcome is simulated.
return function(source,Avoidance)
    local cancellation=assert(source:match('(    local function releaseSprint.-)    local walls'))
    cancellation=cancellation:gsub('local function cancel%(preserveMovement%)', 'local function cancel(preserveMovement) f.cancelPreserves[#f.cancelPreserves+1]=preserveMovement==true')
    local continuation=source:match('(    local function claimFinite.-)    local function tick') or ''
    local tick=assert(source:match('(    local function tick%(dt%).-)    if createTackle then'))
    local touched=assert(source:match('(    local touchedConnection=.-)    function controller.history'))
    local enabled=assert(source:match('(    function controller.setEnabled.-)    function controller.releaseFullplay'))
    local match=assert(source:match('(    function controller.onMatch.-)    function controller.onFx'))
    local fx=assert(source:match('(    function controller.onFx.-)    local touchedConnection='))
    local unload=assert(source:match('(    function controller.unload.-)    log%("loaded"'))
    local factory=assert((loadstring or load)([[
return function(f,Avoidance)
    local os={clock=function()return f.clock end}
    local me={Character={},GetAttribute=function(_,key) if key=='SprintOn' then return f.sprinting end return f.touchValue end,
        GetAttributeChangedSignal=function() return {Connect=function(_,fn) f.touch=fn;return {Disconnect=function()f.disconnected=true end} end} end}
    local Enum={Material={Air='Air'},KeyCode={LeftShift='left',RightShift='right'}}
    local Config={RunSpeed=20,SprintSpeed=27}
    local ctx={snapshot=function()return f.s end}
    local workspace={GetServerTimeNow=function()return f.time end}
    local UIS={IsKeyDown=function()return false end,GetFocusedTextBox=function()return f.focused end}
    local GuiService={};setmetatable(GuiService,{__index=function(_,k) if k=='MenuIsOpen' then return f.menu end end})
    local Moves={Upright=function()return not f.notUpright end,HoldSprint=function(value) f.sprinting=value;f.sprintCalls=f.sprintCalls+1 end}
    local RunService={UnbindFromRenderStep=function()f.unbound=true end}
    local bindName='authored-bind'
    local alive,auto,inputOwned=true,true,true
    local plan,lastSnapshot=f.plan,{requireEndzoneCatch=f.s.role=='WR'}
    local throwKey,throwRole,claimedKey=f.s.launchAt,f.s.role,nil
    local claimObservedAt,claimTraceCount,claimTraceNext=nil,0,0
    local pendingClaimMotion,lastCatchMotion=nil,{root=f.root,h=f.h,launchAt=f.s.launchAt,at=f.time-.01,direction=f.direction}
    local controlledHumanoid,ownsSprint=f.h,true
    local jumped,dived,jumpRequest=true,false,nil
    local confirmedCatchJump,groundedReachSince,reachAirborne
    local steering,atTarget,parkedPosition=f.direction.Unit,false,nil
    local navigation,catching=false,true
    local navigationIdleSince,navigationIdleRoot
    local avoidanceState,avoidanceRoot,avoidancePhase,lastAvoidanceReason
    local avoidanceStatus={active=false,blocked=false}
    local trackedSprintRoot,sprintTracking,trackedMotionRoot,trackedAirborne
    local wrFake,wrReturn,wrDefenderDeadline,wrFakeUsed,lastWRSkipReason
    local nextSolve,nextCheck,nextReplan,lastDive,lastJump=0,0,0,-math.huge,f.time-.268
    local stemFinished,stemForecast,nextStemCheck,stemLastSpeed,stemLastSprint,stemLastRun,stemLastStage,stemWasActive
    local lastPauseReason,message
    local counters={throws=0,catches=0,incomplete=0,opponentCatches=0,lostToInterception=0,breakups=0,intercepted=0}
    local lastResult,lastLogTime
    local controller={}
    local function xyz(v)return v end
    local function log(kind,data) f.logs[#f.logs+1]={kind=kind,data=data}end
    local function saveFailure()end
    local function releaseInput()inputOwned=false;f.inputReleased=true end
    local function ownInput()inputOwned=true end
    local function healthyCharacter() if f.noCharacter then return nil,nil end return f.root,f.h end
    local function humanoidState()return 'Freefall'end
    local function networkPing()return .089 end
    local function observePendingClaim()f.observations=f.observations+1 end
    local function sprintBudget()return {canSprint=not f.noBudget}end
    local function enforceSprintReserve() if f.noBudget then f.sprinting=false;ownsSprint=false end end
    local function locomotionState()end
    local function updateFullplay()return false end
    local function clippedDistance(_,_,distance)return f.wall and 0 or distance end
    local function snapshot(s,root,h,now)
        return {physicalAirborne=not f.noPhysicalAir,reachAirborne=not f.shortReach,
            bounds=f.bounds,wrDiveGoalZ=f.goal,opponents=f.opponents,opponent=f.opponent}
    end
    local Planner={capsule=function(_,cf) return cf.Position,cf.Position+Vector3.new(0,3.5,0),3.75 end,
        ballAt=function()return Vector3.new(0,15,0)end}
    local PlayerAvoidance=Avoidance
]]..cancellation..continuation..tick..enabled..match..fx..touched..unload..[[
    return {touch=function()f.touch()end,tick=function()tick(1/60)end,
        enabled=function(v)controller.setEnabled(v)end,match=function(d)controller.onMatch(d)end,
        fx=function(d)controller.onFx(d)end,
        result=function()controller.onFx({Type='BallResult',Result='Incomplete',Pos=Vector3.zero})end,
        unload=function()controller.unload()end,
        state=function()return {pending=pendingClaimMotion,plan=plan,owned=inputOwned,last=lastCatchMotion}end,
        gate=function(k,v)
            if k=='dived' then dived=v elseif k=='jumped' then jumped=v elseif k=='jumpRequest' then jumpRequest=v
            elseif k=='commandAt' then lastCatchMotion.at=v elseif k=='commandDirection' then lastCatchMotion.direction=v
            elseif k=='inputOwned' then inputOwned=v elseif k=='auto' then auto=v end
        end}
end
]],'claim-motion-controller-fixture'))()
    local report={total=0,passed=0,failed=0,results={}}
    local function test(name,body)
        report.total=report.total+1;local ok,err=pcall(body)
        report[ok and 'passed' or 'failed']=report[ok and 'passed' or 'failed']+1
        report.results[#report.results+1]={name=name,passed=ok,error=not ok and tostring(err) or nil}
    end
    local function fixture()
        local f={time=100,clock=1000,touchValue=999.999,logs={},moves={},cancelPreserves={},sprintCalls=0,sprinting=true,observations=0,goal=100,
            bounds={minX=-100,maxX=100,minZ=0,maxZ=150},direction=Vector3.new(.504955,0,.84029)}
        f.root={Position=Vector3.new(54,10.7,118),AssemblyLinearVelocity=f.direction*27}
        f.root.CFrame={Position=f.root.Position}
        f.h={Parent=true,WalkSpeed=27,FloorMaterial='Air',PlatformStand=false,
            Move=function(_,direction,relative) assert(relative==false);f.moves[#f.moves+1]=direction end}
        f.s={enabled=true,phase='Live',role='WR',launchAt=97.1487,arc={},playBudget={wrReserve=10},opponents={}}
        f.plan={kind='jump',continuousCatch=true,reachable=true,stopAt=100.1015308,contactAt=100.021531,direction=f.direction.Unit}
        f.api=factory(f,Avoidance);return f
    end
    test('native local claim preserves the exact continuous command only to its original stop',function()
        local f=fixture();f.api.touch()
        assert(f.api.state().pending and f.api.state().owned,'local claim cancelled the still-valid continuous command')
        assert(#f.moves==0 and f.sprintCalls==0,'claim started a new input or speed request')
        f.time=100.06456;f.api.tick()
        assert((f.moves[#f.moves]-f.direction).Magnitude<1e-8 and f.api.state().pending)
        assert(math.abs(f.moves[#f.moves].Magnitude-f.direction.Magnitude)<1e-8,'pacing was normalized to full speed')
        f.time=f.plan.stopAt;f.api.tick()
        assert(not f.api.state().pending and not f.api.state().owned and f.moves[#f.moves].Magnitude==0)
        assert(f.observations==2 and f.sprintCalls==1,'expiry did not release normally')
    end)
    test('claim continuation never starts for unconfirmed or unbounded movement',function()
        for _,gate in ipairs({'QB','dive','diveAt','noJump','pendingJump','notContinuous','unreachable','staleCommand','wrongHeading','longStop','expired','infinite','manual','air','platform','staleTouch','resetTouch','futureTouch','nanTouch'}) do
            local f=fixture()
            if gate=='QB' then f.s.role='QB' elseif gate=='dive' then f.api.gate('dived',true)
            elseif gate=='diveAt' then f.plan.diveAt=100 elseif gate=='noJump' then f.api.gate('jumped',false)
            elseif gate=='pendingJump' then f.api.gate('jumpRequest',{}) elseif gate=='notContinuous' then f.plan.continuousCatch=false
            elseif gate=='unreachable' then f.plan.reachable=false elseif gate=='staleCommand' then f.api.gate('commandAt',99.94)
            elseif gate=='wrongHeading' then f.api.gate('commandDirection',Vector3.new(-1,0,0))
            elseif gate=='longStop' then f.plan.stopAt=100.151 elseif gate=='expired' then f.plan.stopAt=100
            elseif gate=='infinite' then f.plan.stopAt=math.huge elseif gate=='manual' then f.api.gate('inputOwned',false)
            elseif gate=='air' then f.h.FloorMaterial='Ground' elseif gate=='platform' then f.h.PlatformStand=true
            elseif gate=='staleTouch' then f.touchValue=f.clock-.051 elseif gate=='resetTouch' then f.touchValue=false
            elseif gate=='futureTouch' then f.touchValue=f.clock+.01 else f.touchValue=0/0 end
            f.api.touch();assert(not f.api.state().pending,gate..' started continuation')
        end
    end)
    test('pending claim immediately yields to result phase disable menus and unload',function()
        for _,gate in ipairs({'result','phasePacket','phaseSnapshot','disable','assist','testing','menu','text','unload','missingRoot','launch','role','arc','manual','budget','sprint','speed'}) do
            local f=fixture();f.api.touch();assert(f.api.state().pending)
            f.time=100.03;f.cancelPreserves={}
            if gate=='result' then f.api.result()
            elseif gate=='phasePacket' then f.api.match({Phase='RAC'})
            elseif gate=='disable' then f.api.enabled(false)
            elseif gate=='unload' then f.api.unload()
            else
                if gate=='phaseSnapshot' then f.s.phase='RAC' elseif gate=='assist' then f.s.enabled=false
                elseif gate=='testing' then f.s.testing=true elseif gate=='menu' then f.menu=true
                elseif gate=='text' then f.focused=true elseif gate=='missingRoot' then f.noCharacter=true
                elseif gate=='launch' then f.s.launchAt=98;f.noCharacter=true
                elseif gate=='role' then f.s.role='DB' elseif gate=='arc' then f.s.arc={}
                elseif gate=='manual' then f.api.gate('inputOwned',false)
                elseif gate=='budget' then f.noBudget=true elseif gate=='sprint' then f.sprinting=false
                elseif gate=='speed' then f.h.WalkSpeed=20 end
                f.api.tick()
            end
            assert(not f.api.state().pending and not f.api.state().owned,gate..' retained pending movement')
            if gate=='launch' then assert(f.cancelPreserves[1]==false,'new throw retained the prior claim command') end
            assert(f.moves[#f.moves].Magnitude==0,gate..' failed to release the owned command')
        end
    end)
    test('pending claim never substitutes a detour through a collision wall or boundary',function()
        for _,gate in ipairs({'body','teamBody','wall','bounds','goal','ground','nativeMove','physicalAir','shortReach','nanPosition','rootChange'}) do
            local f=fixture();f.api.touch();assert(f.api.state().pending);f.time=100.03
            if gate=='body' then f.opponent={position=f.root.Position+Vector3.new(.2,0,2),velocity=Vector3.zero}
            elseif gate=='teamBody' then f.opponents={{position=f.root.Position+Vector3.new(.2,0,2),velocity=Vector3.zero}}
            elseif gate=='wall' then f.wall=true elseif gate=='bounds' then f.bounds.maxZ=118.1
            elseif gate=='goal' then f.goal=119 elseif gate=='ground' then f.h.FloorMaterial='Ground'
            elseif gate=='nativeMove' then f.notUpright=true elseif gate=='physicalAir' then f.noPhysicalAir=true
            elseif gate=='shortReach' then f.shortReach=true elseif gate=='nanPosition' then f.root.Position=Vector3.new(0/0,10,118)
            else f.root={Position=f.root.Position,AssemblyLinearVelocity=Vector3.zero} end
            f.api.tick();assert(not f.api.state().pending and f.moves[#f.moves].Magnitude==0,gate..' retained or redirected movement')
        end
    end)
    test('independent finite geometry airborne and missing-budget exits use actual tick',function()
        for _,gate in ipairs({'noBudgetTable','missingArc','nanSpeed','infiniteSpeed','nilBounds','nanBounds','shortReach','noPhysicalAir'}) do
            local f=fixture();f.api.touch();assert(f.api.state().pending);f.time=100.02
            if gate=='noBudgetTable' then f.s.playBudget=nil elseif gate=='missingArc' then f.s.arc=nil
            elseif gate=='nanSpeed' then f.h.WalkSpeed=0/0 elseif gate=='infiniteSpeed' then f.h.WalkSpeed=math.huge
            elseif gate=='nilBounds' then f.bounds=nil elseif gate=='nanBounds' then f.bounds.maxX=0/0
            elseif gate=='shortReach' then f.shortReach=true else f.noPhysicalAir=true end
            f.api.tick();assert(not f.api.state().pending and not f.api.state().owned,gate)
            assert(f.moves[#f.moves].Magnitude==0,gate..' left movement active')
            assert(f.sprintCalls==1,gate..' did not only release sprint')
        end
    end)
    test('independent duplicate native callbacks cannot extend the original deadline',function()
        local f=fixture();f.api.touch();assert(f.api.state().pending)
        f.time=100.025;f.api.touch()
        assert(not f.api.state().pending and not f.api.state().owned,'duplicate callback restarted pending command')
        assert(f.moves[#f.moves].Magnitude==0 and f.sprintCalls==1,'duplicate callback did not release')
    end)
    test('independent all terminal native outcomes release without adding actions',function()
        for _,result in ipairs({'Catch','Swatted','Intercepted','Incomplete','BallStop'}) do
            local f=fixture();f.api.touch();assert(f.api.state().pending)
            f.api.fx(result=='BallStop' and {Type='BallStop'} or {Type='BallResult',Result=result,Pos=Vector3.zero})
            assert(not f.api.state().pending and not f.api.state().owned,result)
            assert(#f.moves==1 and f.moves[1].Magnitude==0 and f.sprintCalls==1,result..' added movement/sprint action')
        end
    end)
    test('independent invalid command cannot start continuation',function()
        for _,value in ipairs({Vector3.zero,Vector3.new(0/0,0,0),Vector3.new(math.huge,0,0),Vector3.new(0,0,1.1)}) do
            local f=fixture();f.api.gate('commandDirection',value);f.api.touch()
            assert(not f.api.state().pending and not f.api.state().owned,'invalid command preserved')
        end
    end)
    test('DB continuous jump keeps only its checked paced command until the original stop',function()
        local f=fixture();f.s.role='DB';f.s.playBudget={dbReserve=40};f.goal=140
        f.direction=Vector3.new(.25,0,.44);f.plan.direction=f.direction.Unit
        f.api=factory(f,Avoidance);f.api.touch()
        assert(f.api.state().pending and f.api.state().pending.role=='DB')
        f.time=100.04;f.api.tick()
        assert((f.moves[#f.moves]-f.direction).Magnitude<1e-8 and f.sprintCalls==0)
        f.time=f.plan.stopAt;f.api.tick()
        assert(not f.api.state().pending and f.moves[#f.moves].Magnitude==0)
    end)
    test('DB pending jump motion yields to changed role reserve result or crossing body',function()
        for _,gate in ipairs({'role','reserve','result','body'}) do
            local f=fixture();f.s.role='DB';f.s.playBudget={dbReserve=40};f.api=factory(f,Avoidance)
            f.api.touch();assert(f.api.state().pending)
            f.time=100.04
            if gate=='role' then f.s.role='WR'
            elseif gate=='reserve' then f.noBudget=true
            elseif gate=='body' then f.opponent={position=f.root.Position+Vector3.new(.2,0,2),velocity=Vector3.zero} end
            if gate=='result' then f.api.result() else f.api.tick() end
            assert(not f.api.state().pending and f.moves[#f.moves].Magnitude==0,gate)
        end
    end)
    return report
end
