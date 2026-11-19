-- Pure motion classification. No services, character mutation, or game inputs.
-- groundRootY, when supplied, MUST be a trusted standing/pre-takeoff reference;
-- do not derive it from the current elevated root merely because FloorMaterial
-- still reports ground. Without that reference use the normal field turf+3.
local Motion={}
local function finite(n)
    return type(n)=="number" and n==n and math.abs(n)<math.huge
end
-- Full-auto reserves are excluded from both reach prediction and dispatch.
-- A short dispatch allowance covers the next frame/native sprint-off delay.
function Motion.sprintBudget(role,stamina,drain,policy)
    stamina=finite(stamina) and math.max(0,stamina) or 0
    drain=finite(drain) and math.max(1,drain) or 25
    local requested=type(policy)=="table" and (role=="DB" and policy.dbReserve
        or role=="WR" and policy.wrReserve) or nil
    local reserved=finite(requested)
    local reserve=reserved and math.max(0,math.min(95,requested)) or 2
    local dispatch=reserved and drain*.12 or 0
    local available=math.max(0,stamina-reserve-dispatch)
    return {seconds=available/drain,canSprint=available>0,
        reserve=reserve,cutoff=reserve+dispatch,enforced=reserved}
end
-- SprintOn acknowledges the local request, not the server's actual speed.
-- Keep this observation across replans; callers clear it when ownership or the
-- character changes. Penalties and confirmed sprint use their own forecasts.
function Motion.sprintState(previous,now,actualSpeed,sprinting,runSpeed,sprintSpeed)
    if not sprinting or not finite(now) or not finite(actualSpeed)
        or actualSpeed<runSpeed*.95 or actualSpeed>=sprintSpeed*.95 then return nil end
    local since=type(previous)=="table" and previous.since or nil
    if not finite(since) or since>now then since=now end
    local age=math.max(0,now-since)
    return {since=since,age=age,pending=age>=.15}
end
-- A live movement penalty must affect the forecast. A delayed sprint request
-- instead uses observed normal speed with scale1 until sprint is confirmed.
function Motion.locomotion(actualSpeed,sprinting,runSpeed,sprintSpeed,sprintSeconds,sprintState)
    local scale=1
    if finite(actualSpeed) and actualSpeed>=0 and actualSpeed<runSpeed*.95 then
        local expected=sprinting and sprintSpeed or runSpeed
        scale=math.max(0,math.min(1,actualSpeed/math.max(1,expected)))
    end
    local pending=scale==1 and sprinting and sprintSeconds>0
        and finite(actualSpeed) and actualSpeed>=runSpeed*.95 and actualSpeed<sprintSpeed*.95
        and type(sprintState)=="table" and sprintState.pending==true
    local speed=pending and math.min(sprintSpeed,actualSpeed)
        or (sprintSeconds>0 and sprintSpeed or runSpeed)*scale
    return {walkSpeed=speed,runSpeed=pending and math.min(runSpeed,speed) or runSpeed*scale,
        speedScale=scale,sprintPending=pending==true,
        sprintPendingAge=type(sprintState)=="table" and sprintState.age or nil}
end
function Motion.shouldRefreshLocomotion(previous,current,blocked)
    return not blocked and type(previous)=="table" and type(current)=="table"
        and ((previous.sprintPending==true)~=(current.sprintPending==true)
            or math.abs((current.speedScale or 1)-(previous.speedScale or 1))>.08)
end
function Motion.classify(s)
    s=type(s)=="table" and s or {}
    local nativeAirborne=s.floorAirborne==true
    local base=finite(s.groundRootY) and s.groundRootY
        or (finite(s.turfY) and s.turfY+3 or nil)
    local valid=finite(s.rootY) and finite(s.verticalSpeed) and base~=nil
    local elevation=valid and s.rootY-base or nil
    local elevated=valid and elevation>0.15
    local ascent=elevated and s.verticalSpeed>5 or false
    local descent=elevated and s.verticalSpeed < -5 or false
    -- Optional already-confirmed airborne state keeps an apex from looking
    -- grounded. A stationary elevated character with no such history is NOT
    -- classified as ascending or airborne from height alone.
    local knownAloft=elevated and s.knownAirborne==true or false
    local physicalAirborne=nativeAirborne or ascent or descent or knownAloft
    local reason=nativeAirborne and "native airborne"
        or ascent and "rising despite ground flag"
        or descent and "falling despite ground flag"
        or knownAloft and "confirmed flight above ground"
        or not valid and "invalid motion snapshot"
        or "grounded"
    return {
        valid=valid,
        grounded=valid and not physicalAirborne,
        physicalAirborne=physicalAirborne,
        nativeAirborne=nativeAirborne,
        -- Catching and DivePath read the native floor flag themselves. This
        -- helper must never grant their airborne reach/momentum prematurely.
        reachAirborne=nativeAirborne,
        diveModeMatchesMotion=valid and physicalAirborne==nativeAirborne,
        ascendingDespiteGround=not nativeAirborne and ascent,
        fallingDespiteGround=not nativeAirborne and descent,
        elevation=elevation,
        groundRootY=base,
        reason=reason,
    }
end
-- A pursuit solved while the native floor flag lagged behind takeoff had
-- neither airborne catch reach nor a legal dive. Revisit that restricted
-- forecast as soon as native airborne actions are available, without
-- interrupting a healthy jump/dive plan or an action still being confirmed.
function Motion.shouldRefreshPursuit(plan,previous,current,blocked)
    return not blocked and type(plan)=="table" and plan.kind=="pursue"
        and plan.reachable==false and type(previous)=="table"
        and previous.physicalAirborne==true and previous.nativeAirborne==false
        and previous.reachAirborne==false and previous.canDive==false
        and type(current)=="table" and current.nativeAirborne==true
        and current.diveModeMatchesMotion==true
end
return Motion
