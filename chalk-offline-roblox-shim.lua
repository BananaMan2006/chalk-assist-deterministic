-- Offline fixture math only. Double precision, no Roblox engine/physics/network.
-- Unsupported engine APIs are intentionally absent rather than silently mocked.
local V,VM={},{}
local function vector(x,y,z) return setmetatable({X=x or 0,Y=y or 0,Z=z or 0},VM) end
function V.Dot(a,b) return a.X*b.X+a.Y*b.Y+a.Z*b.Z end
function V.Cross(a,b) return vector(a.Y*b.Z-a.Z*b.Y,a.Z*b.X-a.X*b.Z,a.X*b.Y-a.Y*b.X) end
function V.Lerp(a,b,t) return a+(b-a)*t end
VM.__index=function(a,k)
    if k=='Magnitude' then return math.sqrt(V.Dot(a,a)) end
    if k=='Unit' then local m=math.sqrt(V.Dot(a,a));return vector(a.X/m,a.Y/m,a.Z/m) end
    return V[k]
end
VM.__add=function(a,b) return vector(a.X+b.X,a.Y+b.Y,a.Z+b.Z) end
VM.__sub=function(a,b) return vector(a.X-b.X,a.Y-b.Y,a.Z-b.Z) end
VM.__unm=function(a) return vector(-a.X,-a.Y,-a.Z) end
VM.__mul=function(a,b)
    if type(a)=='number' then return vector(a*b.X,a*b.Y,a*b.Z) end
    if type(b)=='number' then return vector(a.X*b,a.Y*b,a.Z*b) end
    return vector(a.X*b.X,a.Y*b.Y,a.Z*b.Z)
end
VM.__div=function(a,b)
    if type(b)=='number' then return vector(a.X/b,a.Y/b,a.Z/b) end
    return vector(a.X/b.X,a.Y/b.Y,a.Z/b.Z)
end
VM.__eq=function(a,b) return a.X==b.X and a.Y==b.Y and a.Z==b.Z end
VM.__tostring=function(a) return string.format('Vector3(%.9g, %.9g, %.9g)',a.X,a.Y,a.Z) end
Vector3={new=vector,zero=vector(),one=vector(1,1,1),xAxis=vector(1,0,0),yAxis=vector(0,1,0),zAxis=vector(0,0,1)}

local C,CM={},{}
local function frame(p,r,u,b) return setmetatable({_p=p,_r=r,_u=u,_b=b},CM) end
local function rotate(c,v) return c._r*v.X+c._u*v.Y+c._b*v.Z end
function C.lookAt(p,target,up)
    up=up or Vector3.yAxis
    local delta=target-p
    assert(delta.Magnitude>1e-12,'offline lookAt requires distinct points')
    local back=-delta.Unit
    local right=up:Cross(back)
    assert(right.Magnitude>1e-12,'offline lookAt does not implement parallel-up fallback')
    right=right.Unit
    return frame(p,right,back:Cross(right),back)
end
function C.new(x,y,z,...)
    if getmetatable(x)==VM then
        if getmetatable(y)==VM then return C.lookAt(x,y) end
        return frame(x,Vector3.xAxis,Vector3.yAxis,Vector3.zAxis)
    end
    local n={...}
    if #n==9 then
        return frame(vector(x,y,z),vector(n[1],n[4],n[7]),vector(n[2],n[5],n[8]),vector(n[3],n[6],n[9]))
    end
    assert(#n==0,'unsupported offline CFrame.new overload')
    return frame(vector(x,y,z),Vector3.xAxis,Vector3.yAxis,Vector3.zAxis)
end
function C.Angles(x,y,z)
    local cx,sx,cy,sy,cz,sz=math.cos(x),math.sin(x),math.cos(y),math.sin(y),math.cos(z),math.sin(z)
    local rx=frame(Vector3.zero,vector(1,0,0),vector(0,cx,sx),vector(0,-sx,cx))
    local ry=frame(Vector3.zero,vector(cy,0,-sy),vector(0,1,0),vector(sy,0,cy))
    local rz=frame(Vector3.zero,vector(cz,sz,0),vector(-sz,cz,0),vector(0,0,1))
    return rx*ry*rz
end
function C.VectorToWorldSpace(c,v) return rotate(c,v) end
function C.PointToWorldSpace(c,v) return c._p+rotate(c,v) end
function C.VectorToObjectSpace(c,v) return vector(c._r:Dot(v),c._u:Dot(v),c._b:Dot(v)) end
function C.PointToObjectSpace(c,v) return C.VectorToObjectSpace(c,v-c._p) end
CM.__index=function(c,k)
    if k=='Position' or k=='p' then return c._p end
    if k=='RightVector' or k=='XVector' then return c._r end
    if k=='UpVector' or k=='YVector' then return c._u end
    if k=='LookVector' then return -c._b end
    if k=='ZVector' then return c._b end
    return C[k]
end
CM.__mul=function(a,b)
    if getmetatable(b)==VM then return C.PointToWorldSpace(a,b) end
    assert(getmetatable(b)==CM,'unsupported offline CFrame multiplication')
    return frame(C.PointToWorldSpace(a,b._p),rotate(a,b._r),rotate(a,b._u),rotate(a,b._b))
end
CM.__add=function(c,v) return frame(c._p+v,c._r,c._u,c._b) end
CM.__sub=function(c,v) return frame(c._p-v,c._r,c._u,c._b) end
CFrame=C
CFrame.identity=C.new()
function typeof(x)
    local mt=getmetatable(x)
    if mt==VM then return 'Vector3' end
    if mt==CM then return 'CFrame' end
    if type(x)=='table' and rawget(x,'_offlineInstance') then return 'Instance' end
    return type(x)
end
math.clamp=math.clamp or function(x,a,b) assert(a<=b,'invalid clamp range');return math.max(a,math.min(b,x)) end
math.atan2=math.atan2 or function(y,x) return math.atan(y,x) end
math.sign=math.sign or function(x) return x>0 and 1 or (x<0 and -1 or 0) end
table.clone=table.clone or function(t) local r={};for k,v in pairs(t) do r[k]=v end;return setmetatable(r,getmetatable(t)) end
table.clear=table.clear or function(t) for k in pairs(t) do t[k]=nil end end
table.find=table.find or function(t,v,first) for i=first or 1,#t do if t[i]==v then return i end end end
loadstring=load
unpack=table.unpack
-- No-op yield only: fixtures use this to cooperate during pure numeric scans.
task={wait=function() return 0 end}
workspace={Gravity=196.2}
Enum={Material={Air='Air',Grass='Grass',Plastic='Plastic'}}

-- Isolated data-only fixtures for tackle/jam tests. No simulation or services.
local I,IM={},{}
function I.IsA(i,class) return i.ClassName==class or class=='Instance' or (class=='BasePart' and i.ClassName=='Part') end
function I.GetChildren(i) local r={};for child in pairs(i._children) do r[#r+1]=child end;return r end
function I.FindFirstChild(i,name) for child in pairs(i._children) do if child.Name==name then return child end end end
function I.FindFirstChildOfClass(i,class) for child in pairs(i._children) do if child.ClassName==class then return child end end end
function I.GetAttribute(i,name) return i._attributes[name] end
function I.SetAttribute(i,name,value) i._attributes[name]=value end
function I.Destroy(i) for _,child in ipairs(i:GetChildren()) do child:Destroy() end;i.Parent=nil;i._destroyed=true end
IM.__index=function(i,k)
    if I[k] then return I[k] end
    return i._props[k]
end
IM.__newindex=function(i,k,v)
    if k=='Parent' then
        local old=i._props.Parent
        if old then old._children[i]=nil end
        if v then v._children[i]=true end
    elseif k=='Position' and i.ClassName=='Part' then
        local c=i._props.CFrame
        i._props.CFrame=frame(v,c._r,c._u,c._b)
    elseif k=='CFrame' and i.ClassName=='Part' then i._props.Position=v.Position end
    i._props[k]=v
end
Instance={new=function(class)
    assert(class=='Folder' or class=='Model' or class=='Part' or class=='Humanoid','unsupported fixture Instance: '..tostring(class))
    local p={ClassName=class,Name=class}
    if class=='Part' then
        p.Position=Vector3.zero;p.CFrame=CFrame.identity;p.AssemblyLinearVelocity=Vector3.zero;p.Anchored=false
    elseif class=='Humanoid' then
        p.Health=100;p.Sit=false;p.FloorMaterial=Enum.Material.Air;p.UseJumpPower=true;p.JumpPower=50;p.JumpHeight=7.2;p.WalkSpeed=16
    end
    return setmetatable({_offlineInstance=true,_props=p,_children={},_attributes={}},IM)
end}

-- Independent axis/rotation identities plus native planner expected-value tests
-- in chalk-intercept-selftest.lua calibrate the subset used here.
local function near(a,b) assert((a-b).Magnitude<1e-10,tostring(a)..' != '..tostring(b)) end
near(vector(1,2,3)*vector(4,5,6),vector(4,10,18))
near(Vector3.xAxis:Cross(Vector3.yAxis),Vector3.zAxis)
local facing=CFrame.lookAt(vector(3,4,5),vector(4,4,5))
near(facing.LookVector,Vector3.xAxis)
near(facing*vector(0,0,-2),vector(5,4,5))
near((facing*CFrame.Angles(-math.pi/2,0,0)).UpVector,Vector3.xAxis)
near((CFrame.Angles(math.pi/2,0,0)).UpVector,Vector3.zAxis)
return {precision='double',enginePhysics=false,instanceFixturesOnly=true}
