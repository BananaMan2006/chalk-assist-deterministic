#!/usr/bin/env python3
"""Assemble the deterministic client from an explicit, local module allowlist."""
from pathlib import Path
import hashlib
import re

ROOT = Path(__file__).resolve().parent
# Order matters: every dependency is declared before its consumer.
MODULES = (
    ("createPreferences", "chalk-preferences.lua"),
    ("Planner", "chalk-intercept-planner.lua"),
    ("createTackle", "chalk-tackle-controller.lua"),
    ("WRApproach", "chalk-wr-approach.lua"),
    ("Motion", "chalk-character-motion.lua"),
    ("PlayerAvoidance", "chalk-player-avoidance.lua"),
    ("createCarrierMoves", "chalk-carrier-moves.lua"),
    ("createAssist", "chalk-intercept-controller.lua"),
    ("AutoplayPolicy", "chalk-autoplay-policy.lua"),
    ("createAutoplay", "chalk-autoplay-controller.lua"),
    ("createWRRepeat", "chalk-wr-repeat-controller.lua"),
    ("createIdleGuard", "chalk-idle-guard.lua"),
    ("FullplayPolicy", "chalk-fullplay-policy.lua"),
    ("createFullplay", "chalk-fullplay-controller.lua"),
    ("createMatchSkip", "chalk-match-skip-controller.lua"),
    ("createSessionContinuity", "chalk-session-continuity.lua"),
    ("createAutoload", "chalk-autoload-controller.lua"),
)

# Hydrate preferences first, construct inert features, then restore once. Runtime
# teardown and queue errors do not replace the user's durable ON/OFF choices.
INITIALIZE = r'''
api.initializePreferences(createPreferences)
assist = createAssist({snapshot=api.context,version=RELEASE_VERSION,buildId="CHALK_BUNDLED_BUILD_ID",fullplay=function(s,root,h,now,dt)
    if fullplay then return fullplay.navigate(s,root,h,now,dt) end
end},Planner,createTackle,WRApproach,Motion,createCarrierMoves,PlayerAvoidance)
assist.setEnabled(false)
autoplay = createAutoplay({snapshot=api.context,startDisabled=true,preferencesManaged=true,
    previousState=previousState and previousState.autoplay,
    onQueue=function(packet,before)
        if sessionContinuity then sessionContinuity.onQueue(packet,before) end
    end,
    onStateChanged=function()
        if sessionContinuity then sessionContinuity.refresh() end
    end},AutoplayPolicy)
repeatWR = createWRRepeat({snapshot=api.context,
    autoplay=function() return autoplay.status() end,
    disableAutoplay=function() return api.setAutoplay(false) end})
repeatWR.setEnabled(false)
fullplay = createFullplay({Planner=Planner,snapshot=api.context,version=RELEASE_VERSION,buildId="CHALK_BUNDLED_BUILD_ID",
    assistEnabled=function() return assist.status().enabled end,
    release=function() if assist.releaseFullplay then assist.releaseFullplay() end end},FullplayPolicy)
matchSkip = createMatchSkip({snapshot=api.context,startDisabled=true,preferencesManaged=true,
    previousState=previousState and previousState.matchSkip})
-- Idle protection sends input. Start it only after the user enables gameplay.
function api.updateIdleGuard()
    local active = alive and enabled and (
        assist.status().enabled or fullplay.status().enabled
        or autoplay.status().enabled or repeatWR.status().enabled)
    if active and not idleGuard then idleGuard=createIdleGuard()
    elseif not active and idleGuard then idleGuard.unload();idleGuard=nil end
end
api.restorePreferences()
api.initializeSessionContinuity(createSessionContinuity)
autoload = createAutoload({bootstrapSource=BOOTSTRAP_SOURCE,
    onTeleport=function(state,placeId)
        if sessionContinuity then sessionContinuity.onTeleport(state,placeId) end
    end})
'''


def assemble(root=ROOT):
    """Return release artifacts without writing files or executing Lua."""
    root = Path(root)
    version = (root / "VERSION").read_text().strip()
    if not re.fullmatch(r"\d+\.\d+\.\d+", version):
        raise ValueError("Invalid release version")
    core = (root / "chalk-overlay-core.lua").read_text()
    bootstrap = (root / "chalk-bootstrap.lua").read_text().replace("CHALK_BOOTSTRAP_VERSION", version)
    if "]====]" in bootstrap:
        raise ValueError("Bootstrap conflicts with the Lua string delimiter")
    if core.count("-- BUNDLED_INTERCEPT_INIT") != 1:
        raise ValueError("Expected one bundle insertion point")
    modules = "\n".join(
        f"local {name} = (function()\n{(root / filename).read_text()}\nend)()"
        for name, filename in MODULES
    )
    initialization = INITIALIZE.replace("BOOTSTRAP_SOURCE", "[====[" + bootstrap + "]====]")
    assembled = "-- Chalk-Release: " + version + "\n-- Chalk-Product: deterministic\n" + core.replace(
        "-- BUNDLED_INTERCEPT_INIT", modules + "\n" + initialization
    ).replace("CHALK_RELEASE_VERSION", version)
    build_id = hashlib.sha256(assembled.encode()).hexdigest()
    return {
        "chalk-it-up-1v1.lua": assembled.replace("CHALK_BUNDLED_BUILD_ID", build_id),
        "chalk-autoexec-public.lua": "(function(...)\n" + bootstrap + "\nend)({automatic=true})\n",
    }


def main():
    for filename, source in assemble().items():
        (ROOT / filename).write_text(source)
        print("Built " + filename)


if __name__ == "__main__":
    main()
