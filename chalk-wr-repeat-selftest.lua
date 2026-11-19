-- Event/movement ownership checks with explicit mock services, not game physics.
return function(create)
    local report={total=0,passed=0,failed=0,results={}}
    local oldEnum=Enum
    Enum=table.clone(Enum or {})
    Enum.RenderPriority={Character={Value=300}}
    local function node(name,children)
        local n={Name=name,children=children or {}}
        function n:FindFirstChild(key) return self.children[key] end
        function n:GetChildren() local result={};for _,v in pairs(self.children) do result[#result+1]=v end;return result end
        for _,child in pairs(n.children) do child.Parent=n end
        return n
    end
    local function harness(previous)
        local h={time=0,matchServer=false,focused=false,menu=false,moves={},unbound=false}
        local pad=node("WRPad");pad.Position=Vector3.new(0,1,0);pad.Size=Vector3.new(10,.4,10)
        function pad:IsA(class) return class=="BasePart" end
        local model=node("Field2",{WRPad=pad})
        local lobby=node("Lobby",{Field2=model})
        local world=node("Workspace",{Lobby=lobby})
        function world:GetServerTimeNow() return h.time end
        function world:GetAttribute(key) return key=="MatchServer" and h.matchServer or nil end
        local root=node("HumanoidRootPart");root.Position=Vector3.new(0,4,-18);root.Anchored=false
        local humanoid=node("Humanoid");humanoid.Health=100;humanoid.WalkSpeed=20
        function humanoid:Move(direction,cameraRelative)
            assert(cameraRelative==false)
            h.moves[#h.moves+1]=direction;h.lastMove=direction
        end
        local character=node("Character",{HumanoidRootPart=root,Humanoid=humanoid})
        function character:FindFirstChildOfClass(class) return class=="Humanoid" and humanoid or nil end
        local player={Character=character}
        local run={}
        function run:BindToRenderStep(name,priority,callback)
            assert(name=="ChalkDB_WRRepeat" and priority==302);h.step=callback
        end
        function run:UnbindFromRenderStep(name) h.unbound=name=="ChalkDB_WRRepeat" end
        local uis={}
        function uis:GetFocusedTextBox() return h.focused end
        local gui={MenuIsOpen=false}
        h.snapshot={phase="Lobby",alive=true,enabled=true,testing=false}
        h.queue={enabled=false,queueStatus="Idle"}
        h.api=create({previousState=previous,snapshot=function() return h.snapshot end,
            autoplay=function() return h.queue end,disableAutoplay=function() h.disabledAutoplay=true;h.queue.enabled=false end},
            {world=world,player=player,runService=run,uis=uis,guiService=gui,jobId="job-a"})
        h.root,h.pad,h.model,h.lobby,h.world,h.player,h.character,h.humanoid,h.gui=
            root,pad,model,lobby,world,player,character,humanoid,gui
        function h:addPad(index,position,name)
            local part=node(name or "WRPad")
            part.Position=position;part.Size=Vector3.new(10,.4,10)
            function part:IsA(class) return class=="BasePart" end
            local field=node("Field"..index,{[part.Name]=part})
            field.Parent=self.lobby
            self.lobby.children[field.Name]=field
            return part,field
        end
        function h:tick(dt)
            self.time=self.time+(dt or .1);self.step(dt or .1)
        end
        function h:event(packet)
            if not self.snapshot.testing and packet.Phase then self.snapshot.phase=packet.Phase end
            self.api.onMatch(packet)
        end
        function h:walk()
            self.api.setEnabled(true);self:tick(.1);self:tick(.4)
            assert(self.api.status().moving,"expected pad walk")
        end
        return h
    end
    local function test(name,body)
        report.total=report.total+1
        local ok,reason=pcall(body)
        report[ok and "passed" or "failed"]=report[ok and "passed" or "failed"]+1
        report.results[#report.results+1]={name=name,passed=ok,error=not ok and tostring(reason) or nil}
    end
    test("off by default and no cross-server enabled restore",function()
        for _,old in ipairs({{}, {enabled=true,field=2,jobId="other"}}) do
            local h=harness(old);h:tick(1)
            assert(not h.api.status().enabled and #h.moves==0 and h.api.status().field==nil)
        end
    end)
    test("same-server restore keeps enabled but reselects the nearest pad",function()
        local h=harness({enabled=true,field=2,jobId="job-a",moving=true,error="old",counters={walks=50}})
        h:addPad(5,Vector3.new(100,1,0));h.root.Position=Vector3.new(90,4,0)
        assert(h.api.status().enabled and not h.api.status().moving)
        assert(not h.api.status().error and h.api.status().counters.walks==0)
        h:tick(.1);h:tick(.4)
        assert(h.api.status().field==5 and h.api.status().moving and h.lastMove.X>0)
    end)
    test("enable cancels autoplay and settles before ordinary forward input",function()
        local h=harness();h.queue.enabled=true;h.api.setEnabled(true);h:tick(.1)
        assert(h.disabledAutoplay and #h.moves==0)
        h:tick(.4)
        assert(h.api.status().field==2 and h.api.status().moving and h.lastMove.Z>0)
        assert(h.lastMove.Magnitude<=1 and h.humanoid.WalkSpeed==20)
    end)
    test("per-play Result never walks; full match reset resumes",function()
        local h=harness();h:walk();h:event({Phase="Result",Field=2})
        assert(not h.api.status().moving and h.lastMove.Magnitude==0)
        local count=#h.moves;h:tick(3);assert(#h.moves==count)
        h:event({Phase="Result",Field=2,MatchOver=true});h:event({Phase="Lobby"});h:tick(.4)
        assert(h.api.status().moving and h.api.status().counters.completedMatches==1)
    end)
    test("match start releases immediately before another render",function()
        local h=harness();h:walk();h:event({Phase="PreSnap",Field=2})
        assert(not h.api.status().moving and h.lastMove.Magnitude==0)
        assert(h.api.status().counters.matchStarts==1)
        h:tick(2);assert(not h.api.status().moving)
    end)
    test("pad arrival hysteresis does not twitch",function()
        local h=harness();h:walk();h.root.Position=Vector3.new(0,4,-1);h:tick()
        assert(h.api.status().onPad and not h.api.status().moving)
        local count=#h.moves
        h.root.Position=Vector3.new(0,4,-2);h:tick();assert(#h.moves==count)
        h.root.Position=Vector3.new(0,4,-3);h:tick();assert(h.api.status().moving)
        assert(h.api.status().counters.arrivals==1)
    end)
    test("background input taper does not overshoot target",function()
        local h=harness();h:walk();h.root.Position=Vector3.new(0,4,-3);h:tick(.8)
        assert(h.lastMove.Magnitude*20*.8<3 and h.lastMove.Magnitude>0)
    end)
    test("off B-off and unload each release movement",function()
        for _,action in ipairs({"off","B","unload"}) do
            local h=harness();h:walk()
            if action=="off" then h.api.setEnabled(false)
            elseif action=="B" then h.snapshot.enabled=false;h.api.release()
            else h.api.unload() end
            assert(not h.api.status().moving and h.lastMove.Magnitude==0)
            local count=#h.moves;h:tick(1);assert(#h.moves==count)
            if action=="unload" then assert(h.unbound) end
        end
    end)
    test("text and game menu pause then settle again",function()
        for _,kind in ipairs({"text","menu"}) do
            local h=harness();h:walk()
            if kind=="text" then h.focused=true else h.gui.MenuIsOpen=true end
            h:tick();assert(not h.api.status().moving and h.api.status().enabled)
            h.focused=false;h.gui.MenuIsOpen=false;h:tick(.1);assert(not h.api.status().moving)
            h:tick(.4);assert(h.api.status().moving)
        end
    end)
    test("pending or manual queue prevents movement while autoplay off",function()
        for _,kind in ipairs({"Searching","Found","Leaving","Cancelling","pending"}) do
            local h=harness();h.api.setEnabled(true)
            h.queue.queueStatus=kind;h.queue.pending=kind=="pending" and "Join" or nil
            h:tick(.1);h:tick(2);assert(not h.api.status().moving and #h.moves==0)
        end
    end)
    test("phase arriving before return teleport cannot cross map",function()
        local h=harness();h:event({Phase="Result",Field=2,MatchOver=true});h.api.setEnabled(true)
        h.root.Position=Vector3.new(-90,4,50);h:event({Phase="Lobby"});h:tick(.5)
        assert(not h.api.status().moving and h.api.status().enabled)
        h.root.Position=Vector3.new(0,4,-18);h:tick(.1);assert(h.api.status().moving)
    end)
    test("no-progress timeout pauses without endlessly moving",function()
        local h=harness();h:walk();h:tick(2.6)
        assert(not h.api.status().enabled and not h.api.status().moving)
        assert(string.find(h.api.status().error,"Path blocked",1,true))
    end)
    test("character replacement stops and requires re-enable",function()
        local h=harness();h:walk();h.player.Character={};h:tick()
        assert(not h.api.status().enabled and h.lastMove.Magnitude==0)
    end)
    test("native field packet cannot override the nearest lobby pad",function()
        local h=harness();h:addPad(5,Vector3.new(100,1,0))
        h:event({Phase="PreSnap",Field=2});h.api.setEnabled(true)
        h.root.Position=Vector3.new(90,4,0);h:event({Phase="Lobby"});h:tick(.4)
        assert(h.api.status().field==5 and h.api.status().enabled and h.api.status().moving)
        h:event({Phase="PreSnap",Field=5})
        assert(h.api.status().enabled and not h.api.status().moving)
    end)
    test("turning on beside another field discards the prior pad",function()
        local h=harness();h:addPad(5,Vector3.new(100,1,0));h:walk()
        assert(h.api.status().field==2)
        h.api.setEnabled(false);h.root.Position=Vector3.new(90,4,0)
        h.api.setEnabled(true);h:tick(.1);h:tick(.4)
        assert(h.api.status().field==5 and h.lastMove.X>0)
    end)
    test("each full lobby return chooses from the new character position",function()
        local h=harness();h:addPad(5,Vector3.new(100,1,0));h:walk()
        h:event({Phase="PreSnap",Field=2})
        h:event({Phase="Result",Field=2,MatchOver=true})
        h.root.Position=Vector3.new(90,4,0);h:event({Phase="Lobby"});h:tick(.4)
        assert(h.api.status().field==5 and h.api.status().moving and h.lastMove.X>0)
    end)
    test("equal-distance WR pads consistently choose the lower field number",function()
        local h=harness();h:addPad(1,Vector3.new(0,1,-36));h:walk()
        assert(h.api.status().field==1 and h.lastMove.Z<0)
    end)
    test("only nearby same-floor WR parts are candidates",function()
        local h=harness();h:addPad(3,Vector3.new(0,1,-18),"DBPad")
        local invalid=h:addPad(4,Vector3.new(0,1,-18));function invalid:IsA() return false end
        h:addPad(7,Vector3.new(0,50,-18))
        h:addPad(5,Vector3.new(0,1,-10));h:walk()
        assert(h.api.status().field==5 and h.lastMove.Z>0)
    end)
    test("a removed WR pad is replaced with the next nearest valid pad",function()
        local h=harness();h:addPad(5,Vector3.new(12,1,0));h:walk()
        h.model.children.WRPad=nil;h.pad.Parent=nil;h:tick(1.1)
        assert(h.api.status().field==5 and h.api.status().moving and h.lastMove.X>0)
    end)
    test("a lobby position jump selects a nearby pad instead of chasing the old field",function()
        local h=harness();h:addPad(5,Vector3.new(100,1,0));h:walk()
        h.root.Position=Vector3.new(90,4,0);h:tick(1.1)
        assert(h.api.status().enabled and h.api.status().field==5 and h.api.status().moving)
    end)
    test("synthetic test packets cannot replace native field",function()
        local h=harness();h:event({Phase="Lobby",Field=2});h:walk();h.snapshot.testing=true
        h.api.onMatch({Phase="Live",Field=5,MatchOver=true})
        assert(h.api.status().field~=5 and not h.api.status().moving)
        assert(h.api.status().counters.completedMatches==0)
        h.snapshot.phase="Live";h:tick();assert(not h.api.status().moving)
        h.snapshot.testing=false;h.snapshot.phase="Lobby";h:tick(.1);h:tick(.4)
        assert(h.api.status().moving)
    end)
    test("MatchServer is never allowed to walk a local pad",function()
        local h=harness();h.matchServer=true
        assert(not h.api.setEnabled(true));h:tick(1);assert(#h.moves==0)
    end)
    Enum=oldEnum
    return report
end
