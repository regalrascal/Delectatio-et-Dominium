Scriptname SkyrimNet_BakaSL
; SexLab bridge. ALL SexLab script types (SexLabFramework, sslBaseAnimation) live ONLY in here, so
; the main script references none of them and the mod loads/runs WITHOUT SexLab installed. These are
; global functions called by name; if SexLab is absent this script just no-ops (Installed() = false),
; it does not break the caller.

; Cached: on a modlist without SexLab.esm at all (e.g. OStim-only, like this one), an uncached
; Game.GetFormFromFile("SexLab.esm") logs a hard Papyrus ERROR — not a silent None — on every single
; call. _SL() is reached from IsInSexAnimation(), which is polled every ~0.2s in several wait loops
; (_DefeatGroundWindow, _PollResist, etc.), so uncached this spammed 50+ errors per session in testing —
; real Papyrus VM load stacking up right as other mods are also erroring at scene-end. The error only
; fires when the plugin is ABSENT (a present plugin just resolves, no error either way), so caching
; "confirmed absent" as a plain Int (this StorageUtil stub has no Form storage functions) is enough to
; skip every subsequent lookup once we know there's nothing to find.
SexLabFramework Function _SL() Global
    ; S316 fix: the absence used to be cached in StorageUtil on the None key, which rides the
    ; SAVE - a game first run without the mod never detected it after the mod was installed.
    ; The SKSE load-order lookup below is error-free when the plugin is absent, so no cache.
    If Game.GetModByName("SexLab.esm") == 255 && Game.GetLightModByName("SexLab.esm") == 65535
        Return None
    EndIf
    Return Game.GetFormFromFile(0x000D62, "SexLab.esm") as SexLabFramework
EndFunction

Bool Function Installed() Global
    Return _SL() != None
EndFunction

Faction Function AnimFaction() Global
    SexLabFramework sl = _SL()
    If sl
        Return sl.AnimatingFaction
    EndIf
    Return None
EndFunction

; [L2c — P+ runtime fence, GATE 2 approved 09-15] TreatAsFemale/ClearForcedSex are P+ members
; (absent on base SexLab AE). 3-state, StorageUtil-cached on the None key (same pattern as the
; SNBakaSL.Absent absence cache): 0 = unknown (fail-safe: override OFF), 1 = P+ confirmed,
; 2 = ruled out (base SexLab). The version is read ONCE, lazily at the first escalation handoff —
; never at main-script Setup — because a pre-init GetVersion() could misread and cache "base
; SexLab" permanently on a P+ install; by the first handoff the framework quest is in play, so
; the answer is safe to cache. GetVersion is signature-true on BOTH installed frameworks (base
; AE v166b L27-29, P+ 2.18.1 L22-25); base reads 16600, P+ 21801 — the >= 20000 threshold
; separates them. One read per process, not per handoff.
Int Function _PplusDetected() Global
    Int cached = StorageUtil.GetIntValue(None, "SNBakaSL.PplusDetected", 0)
    If cached != 0
        Return cached
    EndIf
    SexLabFramework sl = _SL()
    If !sl
        Return 0    ; SexLab absent — stays unknown (fail-safe off); callers only reach this with SexLab in play
    EndIf
    Int v = sl.GetVersion()
    If v >= 20000
        StorageUtil.SetIntValue(None, "SNBakaSL.PplusDetected", 1)
        Debug.Trace("[SNBakaSL] P+ CONFIRMED at first handoff: SexLab version " + v + " — L2 override enabled")
        Return 1
    EndIf
    StorageUtil.SetIntValue(None, "SNBakaSL.PplusDetected", 2)
    Debug.Trace("[SNBakaSL] P+ RULED OUT at first handoff: SexLab version " + v + " (base SexLab) — L2 override fenced off")
    Return 2
EndFunction

String Function _IntensityTags(String intensity) Global
    If intensity == "aggressive"
        Return "Aggressive,Rough,Forced,Rape,Hardcore,Dom,Domination,Defeat,Brutal,Forsaken,Bound,Spanking,Violent,Painful"
    ElseIf intensity == "loving"
        Return "Loving,Hugging,Kissing,Caressing,Cuddle,Tender,Romantic,Sensual,Passionate,Gentle"
    EndIf
    Return ""
EndFunction

String Function _ExcludeTags(String position, String intensity) Global
    String ex = ""
    If intensity == "aggressive"
        ex = "Loving,Hugging,Caressing,Cuddle,Tender,Romantic,Sensual,Gentle,Foreplay"
    ElseIf intensity == "loving"
        ex = "Aggressive,Rough,Forced,Rape,Hardcore,Dom,Domination,Defeat,Brutal,Violent,Painful"
    EndIf
    String posEx = ""
    If position == "vaginal"
        posEx = "Anal,Oral"
    ElseIf position == "anal"
        posEx = "Vaginal,Oral"
    ElseIf position == "oral"
        posEx = "Vaginal,Anal"
    EndIf
    If ex != "" && posEx != ""
        Return ex + "," + posEx
    ElseIf posEx != ""
        Return posEx
    EndIf
    Return ex
EndFunction

; Starts a SexLab scene with the position/intensity tag filter. Returns the thread id, or -1 if
; SexLab isn't installed. (Tag-match logic moved verbatim from the old main-script _ResolveSexAnims.)
Int Function StartScene(Actor[] akActors, Actor akVictim, Actor akAggressor, String position, String intensity) Global
    SexLabFramework sl = _SL()
    If !sl
        Return -1
    EndIf
    String intTags = _IntensityTags(intensity)
    sslBaseAnimation[] anims
    ; GetAnimationsByTags only ever searches HUMAN animation slots — confirmed by reading
    ; SexLabFramework.psc itself: it's a thin wrapper around AnimSlots.GetByTags, and never touches
    ; CreatureSlots. For a creature pair it silently returns nothing usable, so SexLab falls back to
    ; picking blind and frequently fails to start at all. GetCreatureAnimationsByActorsTags is the
    ; public, documented creature-aware equivalent (same official pattern SexLabFramework's own
    ; QuickStart() uses internally to decide between the two).
    If SkyrimNet_BakaIntegration._AnyCreatureIn(akActors)
        If intTags != ""
            anims = sl.GetCreatureAnimationsByActorsTags(akActors.Length, akActors, intTags, _ExcludeTags(position, intensity), False)
            If !(anims && anims.Length > 0)
                anims = sl.GetCreatureAnimationsByActorsTags(akActors.Length, akActors, intTags, _ExcludeTags("", intensity), False)
            EndIf
        EndIf
        If !(anims && anims.Length > 0)
            anims = sl.GetCreatureAnimationsByActors(akActors.Length, akActors)
        EndIf
    ElseIf intTags != ""
        anims = sl.GetAnimationsByTags(2, intTags, _ExcludeTags(position, intensity), False)
        If !(anims && anims.Length > 0)
            anims = sl.GetAnimationsByTags(2, intTags, _ExcludeTags("", intensity), False)
        EndIf
    ElseIf position != ""
        anims = sl.GetAnimationsByTags(2, position, "", False)
    EndIf
    ; anims may be None/empty here -> SexLab picks from everything.
    ; [L2 — docs\MALE_VICTIM_L2_TREATASSEX.md] Male-victim TreatAsSex at the handoff: B0 (evidence
    ; §8.9) proved the M+M pairing dies at SexLab's compatibility layer (64 aggressive-family scenes
    ; initialized, [0,0,0] compatible) because every receiving position in those packs is F-tagged.
    ; Treating a male victim as female for SexLab MATCHING turns every F-tagged receiving position
    ; into a strict match — broad cross-pack qualification by construction, human AND creature paths
    ; (both funnel through here). Gate is _SexOf(akVictim) != 1 (the leveled-safe port), so female
    ; victims never enter the branch: the female path is behaviorally byte-identical. The override is
    ; PERSISTENT (a GenderFaction rank, not scene-scoped) — the flag below tracks it and
    ; ClearVictimOverride (called by the main script at both scene-end hooks) rolls it back. The
    ; accepted visual tradeoff (female-authored skeletons on male frames) is on record; jank feeds
    ; the M2M tag-curation ledger item, not a rollback.
    Bool l2Applied = False
    If akVictim && SkyrimNet_BakaIntegration._SexOf(akVictim) != 1
        ; [L2c — P+ runtime fence] unknown (0) or ruled-out (2) → override OFF (fail-safe default).
        ; OStim never reaches this code (the caller's backend selector routes BakaSL.StartScene only
        ; at backend==1), so the version fence is the only guard needed here. If a future path adds
        ; another BakaSL.StartScene call site, this gate must travel with it.
        If _PplusDetected() != 1
            Debug.Trace("[SNBakaSL] L2 override SKIPPED (base SexLab — override inert): " + akVictim.GetDisplayName() + " — TreatAsFemale is a P+ member; StartSex proceeds on the real-sex pool")
        Else
            If StorageUtil.GetIntValue(akVictim, "SNBakaSL.L2Override", 0) == 1
                Debug.Trace("[SNBakaSL] L2 PREVIOUS-OVERRIDE-UNROLLED (MISSED rollback): " + akVictim.GetDisplayName() + " still carries the TreatAsFemale flag from an earlier scene — rolling forward")
            EndIf
            sl.TreatAsFemale(akVictim)
            StorageUtil.SetIntValue(akVictim, "SNBakaSL.L2Override", 1)
            l2Applied = True
            Debug.Trace("[SNBakaSL] L2 override APPLIED: TreatAsFemale(" + akVictim.GetDisplayName() + ") before StartSex — male victim at the escalation handoff")
        EndIf
    ElseIf akVictim
        Debug.Trace("[SNBakaSL] L2 override SKIPPED: " + akVictim.GetDisplayName() + " is female — no override needed")
    Else
        Debug.Trace("[SNBakaSL] L2 override SKIPPED: no victim in this scene")
    EndIf
    Int tid = sl.StartSex(akActors, anims, akVictim, akAggressor, True, "")
    If l2Applied && tid < 0
        ; Scene never started — roll the persistent override back immediately, or it leaks past the
        ; scene-scoped contract into everything SexLab checks afterwards.
        sl.ClearForcedSex(akVictim)
        StorageUtil.SetIntValue(akVictim, "SNBakaSL.L2Override", 0)
        Debug.Trace("[SNBakaSL] L2 rollback EXECUTED (start-failed): ClearForcedSex(" + akVictim.GetDisplayName() + ") tid=" + tid)
    EndIf
    Return tid
EndFunction

; [L2] Scene-end rollback for the TreatAsFemale override applied in StartScene. Called by
; SkyrimNet_BakaIntegration at BOTH scene-end hooks (the human _EscalationCleanup wait-loop and
; the creature-escalation wait-loop). Flag-gated: female scenes never set SNBakaSL.L2Override, so
; this returns without touching anything on them (female path byte-identical). Idempotent and
; belt-and-braces: a MISSED rollback here is self-healing — the next StartScene on the same victim
; traces PREVIOUS-OVERRIDE-UNROLLED and rolls forward.
Function ClearVictimOverride(Actor akVictim) Global
    If !akVictim
        Debug.Trace("[SNBakaSL] L2 rollback SKIPPED: no actor at the scene-end hook")
        Return
    EndIf
    If StorageUtil.GetIntValue(akVictim, "SNBakaSL.L2Override", 0) != 1
        Return    ; no override pending (female scene, or already rolled back) — nothing to do
    EndIf
    SexLabFramework sl = _SL()
    If sl
        sl.ClearForcedSex(akVictim)
        StorageUtil.SetIntValue(akVictim, "SNBakaSL.L2Override", 0)
        Debug.Trace("[SNBakaSL] L2 rollback EXECUTED (scene-end): ClearForcedSex(" + akVictim.GetDisplayName() + ") — override reverted, SexLab sees the actor's real sex again")
    Else
        Debug.Trace("[SNBakaSL] L2 rollback MISSED: SexLab absent — ClearForcedSex(" + akVictim.GetDisplayName() + ") impossible, flag persists (self-heals at next handoff)")
    EndIf
EndFunction

; [REV-187 / Spec ddng-force-strip-guard v1.2, Component 2.5 — upstream pre-clear]
; Clear DDNG's stale per-actor strip bookkeeping at DeD's own pipeline exits, BEFORE it can
; strand into the cosave (the ISSUE-6 bug class: the state survives save/load and re-strips
; every redressed actor ~1s after each equip via DeviousDevices.dll+55D5).
; DDNG presence-gated (honest degradation, zero behavior change when absent): plugin version
; probe ("DeviousDevices"), cached on the None key (the SNBakaSL.Absent absence-cache pattern):
; 0 = unknown, 1 = present, 2 = absent-confirmed (skip every call after).
; The ONLY state mutation anywhere: zadNativeFunctions.SetActorStripped(akActor, false) —
; and ONLY when DD's own queries PROVE staleness: IsActorStripped(actor) == true AND
; GetDevices(actor).Length == 0 (zero worn devices). Constraint of record (user 2026-11-17):
; devices present -> NEVER clear, NEVER interfere — log-and-defer, DD owns the actor.
; Never touches the strip path: DeD strips via SexLab (StripActor above), not via DD state.
; Idempotent and safe to repeat; call sites are belt-and-braces (redress / teardown / StopScene).
Bool Function ClearStaleDDStrip(Actor akActor) Global
    If !akActor
        Return False
    EndIf
    ; DDNG presence fence (cached; 2 = absent-confirmed, no-op forever after)
    Int ddState = StorageUtil.GetIntValue(None, "SNBakaSL.DDPresent", 0)
    If ddState == 2
        Return False
    EndIf
    If SKSE.GetPluginVersion("DeviousDevices") <= 0
        StorageUtil.SetIntValue(None, "SNBakaSL.DDPresent", 2)
        Debug.Trace("[SNBakaSL] DDFix: DeviousDevices plugin absent — stale-strip pre-clear permanently inert on this load")
        Return False
    EndIf
    If ddState != 1
        StorageUtil.SetIntValue(None, "SNBakaSL.DDPresent", 1)
    EndIf
    ; zadNativeFunctions is a Hidden global-native script (PapyrusUtil/StorageUtil pattern):
    ; called by NAME, never via form resolve. The natives bind at load when DeviousDevices.dll
    ; registers them — which the version probe above already confirmed.
    ; Read-only probe first — never mutate on an actor carrying any device
    Armor[] devices = zadNativeFunctions.GetDevices(akActor)
    If devices && devices.Length > 0
        Debug.Trace("[SNBakaSL] DDFix: devices present (" + devices.Length + ") on " + akActor.GetDisplayName() + " — deferring to DD (never clear)")
        Return False
    EndIf
    If !zadNativeFunctions.IsActorStripped(akActor)
        Return False    ; clean actor — silent (no log spam from the teardown sweep)
    EndIf
    zadNativeFunctions.SetActorStripped(akActor, False)
    Debug.Trace("[SNBakaSL] DDFix: cleared stale DD strip state on " + akActor.GetDisplayName() + " (zero devices, IsActorStripped was true)")
    Return True
EndFunction

; [REV-187 / Component 4] Arm the redress window for one actor (game-time stamp, actor-keyed).
; Called at the Component 2.5 sweep sites — the DLL guard's strip-cycle callback only acts
; inside this window (fDDGuardWindow, default 10s), so a DD unequip long after any redress is
; log-only, never acted on. Idempotent; re-arming just re-stamps.
Function NoteDDRedress(Actor akActor) Global
    If !akActor
        Return
    EndIf
    StorageUtil.SetFloatValue(akActor, "SNBaka.DDGuardRedressAt", Utility.GetCurrentGameTime())
    ; [REV-187 / Component 4] single-slot retry budget resets with each redress window
    StorageUtil.UnsetIntValue(akActor, "SNBaka.DDGuardRetriedForm")
EndFunction

; Force-end a running scene immediately (Quickly=true skips the normal fade/orgasm wind-down) --
; used when real combat resumes around an animating actor and the scene has to stop right now rather
; than wait for it to end on its own.
Function StopScene(Int tid) Global
    SexLabFramework sl = _SL()
    If sl && tid >= 0
        sslThreadController tc = sl.GetController(tid)
        If tc
            Actor[] sceneActors = tc.Positions   ; [REV-187] capture BEFORE EndAnimation — the controller may empty on stop
            tc.EndAnimation(true)
            ; [REV-187 / Spec ddng-force-strip-guard v1.2, Component 2.5 call site (c)] The quick-stop
            ; path skips SexLab's normal orgasm/wind-down stage, so any DDNG hook that would have run
            ; at animation-end is skipped — this is the path most likely to strand DD's per-actor strip
            ; bookkeeping into the cosave (ISSUE-6). Sweep every scene actor immediately after the stop.
            If sceneActors
                Int i = 0
                While i < sceneActors.Length
                    ClearStaleDDStrip(sceneActors[i])
                    NoteDDRedress(sceneActors[i])
                    i += 1
                EndWhile
            EndIf
        EndIf
    EndIf
EndFunction

; [REV-63 2a-ii] Thread positions for SkyrimNet_BakaDetection's SexLab
; orgasm-hook proxy: HookStageEnd delivers the thread id; this resolves the
; controller's actor list through the same cached-bridge pattern as everything
; above (SexLab absent -> empty array, caller no-ops). sslThreadController
; .Positions is signature-true to the installed P+ source; the compile stub
; (tools/compile/local/sslThreadController.psc) was extended to match.
; [S331] The actors in akActor's SexLab scene (the thread roster), None when akActor is in no
; scene or SexLab is absent. The spank key used a cell scan only, which missed a partner who
; is not listed in the player's cell (REV-196 dogfood: Ronja in thread 0, "found 0 NPC(s)").
Actor[] Function SceneActorsOf(Actor akActor) Global
    SexLabFramework sl = _SL()
    If !sl || !akActor
        Return None
    EndIf
    Return SLThreadPositions(sl.FindActorController(akActor))
EndFunction

Actor[] Function SLThreadPositions(Int tid) Global
    SexLabFramework sl = _SL()
    If !sl || tid < 0
        Return None
    EndIf
    sslThreadController tc = sl.GetController(tid)
    If !tc || !tc.Positions
        Return None
    EndIf
    Return tc.Positions
EndFunction

; [REV-144 Strip] Downed-menu "Strip" (baka-module.md REV-134e + REV-136 rulings
; (iii)/(i)(a)): SexLab StripActor is the PRIMARY undress (tracked re-equip
; context, worn-slot aware, animate), UnstripActor the restore re-equip. Both
; signatures are signature-true to the installed P+ source (sslActorLibrary.psc
; L125 / L144); the compile stubs (tools/compile/local/sslActorLibrary.psc in
; BOTH stub trees) were extended to match. SexLab absent -> None / no-op, and the
; caller takes the vanilla per-slot fallback (presence-gated, honest degradation).
Form[] Function StripActor(Actor akActor, Bool abAnimate) Global
    SexLabFramework sl = _SL()
    If !sl
        Return None
    EndIf
    ; VictimRef = akActor: the downed target IS the strip victim, so SexLab's
    ; GetStripForms picks the victim strip set (aggressor set would respect
    ; "keep underwear" style config on the wrong side).
    Return sl.ActorLib.StripActor(akActor, akActor, abAnimate, False)
EndFunction

Function UnstripActor(Actor akActor, Form[] akStripped) Global
    SexLabFramework sl = _SL()
    If !sl || !akStripped
        Return
    EndIf
    sl.ActorLib.UnstripActor(akActor, akStripped, False)
EndFunction
