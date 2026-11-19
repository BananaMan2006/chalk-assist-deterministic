-- Authored, intentionally simplified route-math test double.
-- This is not copied game code and does not claim native timing equivalence.
local Config=require(script.Parent.Config)
local Field=require(script.Parent.Field)
local M={}
local function clamp(x,a,b) return math.max(a,math.min(b,x)) end
function M.Length(points)
    local length=0
    for i=2,#points do length=length+(points[i]-points[i-1]).Magnitude end
    return length
end
function M.Sanitize(raw,startX,los)
    local startMargin=(Config.SidelineMarginYards or 2)*Field.YD
    startX=clamp(startX,Field.MinX+startMargin,Field.MaxX-startMargin)
    local points={Vector2.new(startX,los)}
    local budget=(Config.MaxInkYards or 30)*Field.YD
    local used=0
    for i=2,math.min(#raw,Config.MaxPoints or 200) do
        local point=Vector2.new(clamp(raw[i].X,Field.MinX+1,Field.MaxX-1),
            clamp(raw[i].Y,math.max(Field.BackZ+1,los-(Config.BehindLOSYards or 3)*Field.YD),Field.EndZ-1))
        local delta=point-points[#points]
        if delta.Magnitude>.01 then
            if used+delta.Magnitude>budget then
                local left=budget-used
                if left>.01 then points[#points+1]=points[#points]+delta.Unit*left end
                break
            end
            used=used+delta.Magnitude;points[#points+1]=point
        end
    end
    return points
end
function M.Plan(points,pass)
    local definition=assert(Config.Pass[pass])
    local times={0}
    for i=2,#points do
        times[i]=times[i-1]+(points[i]-points[i-1]).Magnitude/Config.FillSpeed
        if i>2 then times[i]=times[i]+.12 end
    end
    local target=points[#points]
    local outgoing=target-points[#points-1]
    if (definition.Lead or 0)>0 and outgoing.Magnitude>0 then
        local proposed=target+outgoing.Unit*(definition.Lead*Field.YD)
        target=Vector2.new(clamp(proposed.X,Field.MinX+1,Field.MaxX-1),clamp(proposed.Y,Field.BackZ+1,Field.EndZ-1))
    end
    local lead=(target-points[#points]).Magnitude/Config.FillSpeed
    local arrival=math.max(times[#times]+lead,(Config.MinLaunch or .4)+definition.Flight)
    return {Points=points,Times=times,Pass=pass,Target=target,Flight=definition.Flight,Apex=definition.Apex,
        LeadTime=lead,Arrival=arrival,Launch=arrival-definition.Flight}
end
function M.PointAt(plan,elapsed)
    for i=2,#plan.Points do
        if elapsed<=plan.Times[i] then
            local t=clamp((elapsed-plan.Times[i-1])/(plan.Times[i]-plan.Times[i-1]),0,1)
            return plan.Points[i-1]:Lerp(plan.Points[i],t)
        end
    end
    return plan.Target
end
return M
