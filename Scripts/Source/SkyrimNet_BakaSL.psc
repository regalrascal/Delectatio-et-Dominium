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
    If StorageUtil.GetIntValue(None, "SNBakaSL.Absent", 0) == 1
        Return None
    EndIf
    SexLabFramework sl = Game.GetFormFromFile(0x000D62, "SexLab.esm") as SexLabFramework
    If !sl
        StorageUtil.SetIntValue(None, "SNBakaSL.Absent", 1)
    EndIf
    Return sl
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
    ; .9) proved the M+M pairing dies at SexLab's compatibility layer (64 aggressive-family scenes
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

; Force-end a running scene immediately (Quickly=true skips the normal fade/orgasm wind-down) --
; used when real combat resumes around an animating actor and the scene has to stop right now rather
; than wait for it to end on its own.
Function StopScene(Int tid) Global
    SexLabFramework sl = _SL()
    If sl && tid >= 0
        sslThreadController tc = sl.GetController(tid)
        If tc
            tc.EndAnimation(true)
        EndIf
    EndIf
EndFunction

; [ 2a-ii] Thread positions for SkyrimNet_BakaDetection's SexLab
; orgasm-hook proxy: HookStageEnd delivers the thread id; this resolves the
; controller's actor list through the same cached-bridge pattern as everything
; above (SexLab absent -> empty array, caller no-ops). sslThreadController
; .Positions is signature-true to the installed P+ source; the compile stub
; (tools/compile/local/sslThreadController.psc) was extended to match.
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
