-- Numeric fixture values observed on 2026-11-15 for isolated authored tests.
-- This is only fixture input, not a replacement for the game's Config module.
return {
    CatchRadius=3.75,DiveCatchRadius=2.5,WaistDrop=1,HandOffset=0.5,
    HandUpOffset=3.5,DiveReach=2.4,CatchHeight=3.5,
    RunSpeed=20,SprintSpeed=27,JumpHeight=6,SprintDrain=25,
    Moves={
        Dive={Yards=3,Time=.35,Tip=.5,Ground=.75,GetUp=.35,Range=3.5,Reach=5,MinFrac=.15},
        Jam={Speed=34,Time=.18,Range=3.5,Window=1.5},
    },
    -- Config's grab settings live at Config.Tackle in the cached module.
    Tackle={GrabRange=3.5,GrabCooldown=.6},
}
