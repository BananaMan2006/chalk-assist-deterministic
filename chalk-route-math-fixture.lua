-- Authored offline contract fixture, not copied or decompiled game source.
-- It models documented route bounds, ink, corner delays and clipped pass lead.
-- Passing this fixture is not proof of current server/game implementation parity.
return function(Config,Field)
    local R={}
    local function clip(x,a,b) return math.max(a,math.min(b,x)) end
    local function finite(x) return type(x)=="number" and x==x and math.abs(x)<math.huge end
    function R.Length(points)
        local total=0
        for i=2,#points do total=total+(points[i]-points[i-1]).Magnitude end
        return total
    end
    local function pointToSegment(point,a,b)
        local direction=b-a
        local lengthSquared=direction:Dot(direction)
        local fraction=lengthSquared>0 and clip((point-a):Dot(direction)/lengthSquared,0,1) or 0
        return (point-(a+direction*fraction)).Magnitude
    end
    local function simplify(points,tolerance)
        local selected={[1]=true,[#points]=true}
        local work={{1,#points}}
        while #work>0 do
            local interval=table.remove(work)
            local first,last=interval[1],interval[2]
            local greatest,index=tolerance,nil
            for i=first+1,last-1 do
                local deviation=pointToSegment(points[i],points[first],points[last])
                if deviation>greatest then greatest,index=deviation,i end
            end
            if index then
                selected[index]=true
                work[#work+1]={first,index};work[#work+1]={index,last}
            end
        end
        local result={}
        for i,p in ipairs(points) do if selected[i] then result[#result+1]=p end end
        return result
    end
    function R.Sanitize(raw,startX,los)
        los=los or Field.LOSZ
        local startMargin=Config.SidelineMarginYards*Field.YD
        startX=clip(startX or Field.MidX,Field.MinX+startMargin,Field.MaxX-startMargin)
        local edge=Config.RouteEdgeMargin
        local minimumZ=math.max(Field.BackZ+edge,los-Config.BehindLOSYards*Field.YD)
        local function bounded(p)
            return Vector2.new(clip(p.X,Field.MinX+edge,Field.MaxX-edge),clip(p.Y,minimumZ,Field.EndZ-edge))
        end
        local accepted={Vector2.new(startX,los)}
        local remaining=Config.MaxInkYards*Field.YD
        local minimumGap=Config.MinPointGapYards*Field.YD
        if type(raw)=="table" then
            for i=1,math.min(#raw,Config.MaxPoints) do
                local p=raw[i]
                if typeof(p)=="Vector2" and finite(p.X) and finite(p.Y) then
                    p=bounded(p)
                    local delta=p-accepted[#accepted]
                    if delta.Magnitude>=minimumGap then
                        if delta.Magnitude>remaining then
                            accepted[#accepted+1]=accepted[#accepted]+delta.Unit*remaining
                            break
                        end
                        remaining=remaining-delta.Magnitude;accepted[#accepted+1]=p
                    end
                end
            end
        end
        if #accepted==1 then accepted[2]=bounded(accepted[1]+Vector2.new(0,Config.DefaultGoYards*Field.YD)) end
        return simplify(accepted,Config.SimplifyTolerance)
    end
    function R.Plan(points,pass)
        pass=Config.Pass[pass] and pass or "Bullet"
        local selected=Config.Pass[pass]
        local times={0}
        for i=2,#points do
            local seconds=(points[i]-points[i-1]).Magnitude/Config.FillSpeed
            if i>=3 then
                local incoming,outgoing=points[i-1]-points[i-2],points[i]-points[i-1]
                local degrees=math.deg(math.acos(clip(incoming.Unit:Dot(outgoing.Unit),-1,1)))
                local fraction=clip((degrees-Config.CornerMinAngle)/(Config.CornerMaxAngle-Config.CornerMinAngle),0,1)
                seconds=seconds+fraction*Config.CornerMaxPenalty
            end
            times[i]=times[i-1]+seconds
        end
        local last=points[#points]
        local target=last
        if #points>=2 and (selected.Lead or 0)>0 then
            local lead=last+(last-points[#points-1]).Unit*(selected.Lead*Field.YD)
            target=Vector2.new(clip(lead.X,Field.MinX+Config.RouteEdgeMargin,Field.MaxX-Config.RouteEdgeMargin),
                clip(lead.Y,Field.BackZ+Config.RouteEdgeMargin,Field.EndZ-Config.RouteEdgeMargin))
        end
        local leadTime=(target-last).Magnitude/Config.FillSpeed
        local arrival=math.max(times[#times]+leadTime,Config.MinLaunch+selected.Flight)
        return {Points=points,Times=times,Pass=pass,Flight=selected.Flight,Apex=selected.Apex,
            Target=target,LeadTime=leadTime,Arrival=arrival,Launch=arrival-selected.Flight}
    end
    return R
end
