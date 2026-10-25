Scriptname SNBaka_FHUInflationModule
;  Task 2: FHU-inflation module (recordless detection class -- module contract
; point 3, fomod.md section architecture). Extracted BEHAVIOR-PRESERVING from the
; /65 detection-triggers section of SkyrimNet_BakaIntegration.psc (the ?64
; class: signatures and sentinels moved verbatim; only the call shape changed).
; The FHU HEARTBEAT SELF-HEAL pattern (: the poll arms from Setup() AND the
; OnUpdateGameTime heartbeat because the MCM reload chain was stale at save-load) is
; PRESERVED IN FULL: the arming points (Setup + heartbeat), the idempotent arming
; guard, and the multiplexed real-time tick all remain on the motherboard -- a
; recordless script cannot own an OnUpdate chain. This module owns the poll BODY and
; the cue logic only.
;
;  (FHU v2 session 1) ADDS, per the  rulings + the mid- user
; rulings (hook choice + orifice-aware inflate):
;   (a) ENTRY-AROUSAL CAPTURE: HandleSceneStartSL stashes per-actor arousal tier at
;       SL scene start (HookAnimationStart, user-ruled capture point; the 
;       chain via the motherboard's _DaemonArousalTier) + consent context (thread
;       IsAggressive / VictimRef), cleared at scene end (HookAnimationEnd). The
;       INSTANT inflate cue's arousal branch reads the STASHED tier, never the live
;       post-collapse read.
;   (b) CONSENT-CONTEXT PRIMARY: the inflate cue branches on the stashed consent
;       context FIRST (1 consensual / 2 non-consensual / absent = agnostic per the
;       sec.81 1c precedent), arousal tier secondary.
;   (c) DEFLATE/AMBIENT KEEP THE LIVE READ: no capture machinery on those paths;
;       wording treats the post-collapse state as the state.
;   (d) CREATURE-CUM AMBIENT CUE: poll-tick ambient (one shot per inflation
;       episode, sentinel'd skips for human/unsupported injectors) when the
;       inflation source resolves to a non-human creature; {{creature}} resolves to
;       the race EDITOR ID via the injector formlists + MiscUtil.GetRaceEditorID
;       (pre-check 3.2 verdict: a real race name, not just a race class); canned
;       one-liners per creature class keyed to the FHU per-race cum-effect
;       FormLists (the enumeration source), generic fallback for the rest.
;       Template fixed fields USER-QUOTED ( ruling (d)), register-cited;
;       canned lines are sec.7 DRAFTs (, approval pending).
;   (e) PER-ORIFICE DEFLATE: sdb_fhu_deflate_vaginal / _anal / _oral fired per the
;       three-literal discriminator (which sr.inflater.cum.* float dropped); the
;       generic sdb_fhu_deflate is RETIRED with them (retire-and-replace).
;   NEW (mid- user ruling): the INSTANT inflate cue is ORIFICE-AWARE -- the
;       wording branches on the dominant cum.* delta at inflate time.
;
;   HONEST PREMISE CORRECTION ( pre-check 3.3, evidence-cited): the v1
;   PollLevels walked ONLY sr.inflater.amount; the three per-orifice floats were
;   never read. This revision EXTENDS the poll with per-orifice caches
;   (SNBaka.FHULast.V/.A/.O.<formid>) -- the discriminator is sound, the "v1 poll
;   walks them already" premise was false.
;
;   OStim parity (mid- user ruling): the OStim capture listener is NOT
;   BUILT -- the SL FHU Baka Ostim 0.18 bridge is DISABLED in the active Ultra
;   profile (modlist.txt) and the enabled FHU 2.11 Beta has zero OStim
;   registrations (SexLab hooks only, sr_inflateQuest L383-385); OStim-driven
;   fills do not occur in-profile. STOP-and-report honored; capture is
;   SL-scenes-only; absent stash = context-agnostic fallback, sentinel'd.
;
;    (FHU v2 final lane) ADDS: the AMBIENT BYSTANDER REACTION CUE (the
;   planner's 30%/60% expose bands, the cum-ambient /127/133c/134a/134f
;   pattern applied to FHU; the user's 2026-10-24 shape: prompt-directed cue to
;   the reacting actor + MCM-gated direct narration follow-up):
;   (a) while an actor's inflation amount sits at/above the NOTICEABLE band
;       (default 30% of FHU maxInflation -- the MCM slider is the user valve
;       per the C5 ruling; FHU's own percentage math is amount/maxInflation*100,
;       sr_inflateQuest L3394, maxInflationDefault 6.0 = sr_inflateConfig L60),
;       a per-actor ambient reaction cue fires every 60s real time: ONE
;       RegisterEvent("sdb_fhu_ambient", desc, akActor, None) -- the cum-ambient
;       entry-19 subjectless/gamemaster shape ("Nearby characters notice ..."),
;       P2 trigger-bus semantics per the  restore (RegisterEvent IS the
;       load-bearing emission; NO cue yaml -- same as sdb_cum_ambient).
;   (b) wording branches by BAND (noticeable = curious stares / suggestive
;       comments; heavy = scandalized whispers -- the planner rows) and by
;       SOURCE (creature-sourced reads the creature class; human-sourced reads
;       generic; indeterminate source SKIPS cleanly, sentinel'd). Band + source
;       wordings are sec.7 DRAFTs (, register entry 34).
;   (c) LIFECYCLE: anchor at first band crossing -- the first ambient fires AT
;       BAND ENTRY ( first-fire acceleration; the instant cue owns the fresh-inflation
;       moment; no catch-up per the  rule); keys clear when the amount
;       drops below the noticeable band (deflate / the module's clear paths);
;       a 7200s-RT failsafe-class lifetime guard exhausts the episode so a
;       stuck state cannot fire forever.
;   (d) MCM-GATED NARRATION FOLLOW-UP (the second surface, the 153/134f
;       pattern): bFHUAmbientNarration (Fill Her Up MCM "Ambient Narration",
;       DEFAULT OFF) gates sdb_fhu_ambient_narr -- the yaml
;       sdb_fhu_ambient_narr.yaml (eventType-only, direct_narration, guidance
;       = sec.7 DRAFT, register entry 34) matches that event type ONLY.
;
; State: NONE of its own beyond StorageUtil (all keys None-keyed with the actor
; formid embedded, same convention as the v1 FHULast cache). The
; bFHUInflationEnabled toggle remains the motherboard's Auto property (read
; through akHost). Keys:
;   SNBaka.FHULast.<formid>          amount cache (v1, unchanged)
;   SNBaka.FHULast.V/A/O.<formid>    per-orifice cum caches ()
;   SNBaka.FHU.EntryTier.<formid>    captured arousal tier 1/2/3 (absent = no capture)
;   SNBaka.FHU.EntryContext.<formid> 1 consensual / 2 non-consensual (absent = agnostic)
;   SNBaka.FHUCreatureFired.<formid> creature-ambient episode flag
;   SNBaka.FHU.AmbNext.<formid>    ambient-expose next-fire RT stamp (0/absent = not anchored)
;   SNBaka.FHU.AmbStart.<formid>   ambient-expose episode start RT (lifetime guard)
;   SNBaka.FHU.AmbDone.<formid>    ambient-expose failsafe-exhausted flag ()
;
; Logging: every sentinel goes through akHost._Log() -- identical strings, identical
; bDebugLog gating (sentinel parity per sec.67; the [SNBaka] tag preserved
; verbatim). RegisterEvent desc strings are ASCII ( rider) and
; sec.7-DRAFT-flagged.

; ---- Presence probe (cached; absence cached on the None key once -- the
; SNBakaSL.Absent-cache lesson). MOVED VERBATIM from the motherboard's _FHUInstalled.
; sr_inflateQuest QUST 0x000D63 in sr_FillHerUp.esp (formID parsed from the plugin
; binary; identical in BOTH installed variants -- the base hotfix esp and the
; "SL FHU Baka Ostim 0.18" patch esp). ----
Bool Function Installed() Global
    If StorageUtil.GetIntValue(None, "SNBaka.FHUAbsent", 0) == 1
        Return False
    EndIf
    If Game.GetFormFromFile(0x000D63, "sr_FillHerUp.esp") != None
        Return True
    EndIf
    StorageUtil.SetIntValue(None, "SNBaka.FHUAbsent", 1)
    Return False
EndFunction

; ---- FHU INFLATION AWARENESS (Task 3b: fallback poll design) ----
; What FHU's external stack actually exposes (as-read): sr_InfEventManager's
; broadcast system exists to register REFERENCE-ALIAS event scripts -- joining needs
; esp records in sr_FillHerUp.esp, which is out of the Papyrus-only scope, so the
; formal handshake is NOT joined (flagged, not improvised).
; FHU's ModEvents carry no per-actor level payload (sr.inflater.start/.absorb are
; parameterless broadcasts; fhu.playerInflated / fhu.playerCumUpdate are player-only).
; The per-actor level surface is StorageUtil:
;   sr.inflater.amount (float, per actor) -- the level scale behind the 10 stage armors
;   sr.inflater.cum.vaginal/.anal/.oral (floats, per actor) -- per-orifice loads
;   sr.inflater.injector / .analinjector (formlists, per inflated actor) -- who injected
;   sr.inflater.Actors (formlist, keyed on the sr_inflateQuest form 0x000D63)
; Level changes forward as sdb_fhu_inflate (increase) / per-orifice deflate types
; (decrease, ). sr.inflater.start is used ONLY as an immediate-poll nudge.
;
; : MOVED BODY of the motherboard's OnFHUStartSignal event (zero-arg handler --
; sr.inflater.start is a parameterless broadcast; the  4-slot shape is retired).
Function HandleFHUStartSignal(SkyrimNet_BakaIntegration akHost) Global
    If akHost.bEnabled && akHost.bFHUInflationEnabled && Installed()
        akHost._Log("[SNBaka] OnFHUStartSignal: sr.inflater.start received -- immediate level poll")
        PollLevels(akHost)
    EndIf
EndFunction

; ----  (a)/(b): ENTRY CAPTURE at SL scene start ----
; Armed on the motherboard as OnSLAnimationStart (HookAnimationStart -- user-ruled
; capture point mid-: fires once at true scene start; payload 2-push
; PushInt(thread_id), PushBool(HasPlayer), same shape as the proven HookStageEnd).
; Capture-only: this module NEVER drives FHU inflation.
Function HandleSceneStartSL(SkyrimNet_BakaIntegration akHost, Int aiThreadID) Global
    If !(akHost.bEnabled && akHost.bFHUInflationEnabled && Installed())
        Return
    EndIf
    SexLabFramework sl = SkyrimNet_BakaSL._SL()
    If !sl
        akHost._Log("[SNBaka] FHU entry-capture: SexLab accessor None -- no capture for thread " + aiThreadID)
        Return
    EndIf
    sslThreadController tc = sl.GetController(aiThreadID)
    If !tc
        akHost._Log("[SNBaka] FHU entry-capture: no controller for thread " + aiThreadID + " -- no capture")
        Return
    EndIf
    Bool bAggressive = tc.IsAggressive
    Int i = 0
    While i < tc.Positions.Length
        Actor a = tc.Positions[i]
        If a
            Int tier = akHost._DaemonArousalTier(a)
            Int ctx = 1
            If bAggressive && a == tc.VictimRef
                ctx = 2
            EndIf
            String sCtx = "consensual"
            If ctx == 2
                sCtx = "non-consensual"
            EndIf
            StorageUtil.SetIntValue(None, "SNBaka.FHU.EntryTier." + a.GetFormID(), tier)
            StorageUtil.SetIntValue(None, "SNBaka.FHU.EntryContext." + a.GetFormID(), ctx)
            akHost._Log("[SNBaka] FHU entry-capture: " + a.GetDisplayName() + " arousal tier " + tier + " context " + sCtx + " (thread " + aiThreadID + ")")
        EndIf
        i += 1
    EndWhile
EndFunction

; ----  (a): CAPTURE CLEARED at SL scene end ----
; Armed as OnSLAnimationEnd (HookAnimationEnd -- the capture/clear bracket ruling).
Function HandleSceneEndSL(SkyrimNet_BakaIntegration akHost, Int aiThreadID) Global
    If !(akHost.bEnabled && akHost.bFHUInflationEnabled && Installed())
        Return
    EndIf
    SexLabFramework sl = SkyrimNet_BakaSL._SL()
    If !sl
        Return
    EndIf
    sslThreadController tc = sl.GetController(aiThreadID)
    If !tc
        Return
    EndIf
    Int i = 0
    While i < tc.Positions.Length
        Actor a = tc.Positions[i]
        If a
            StorageUtil.UnsetIntValue(None, "SNBaka.FHU.EntryTier." + a.GetFormID())
            StorageUtil.UnsetIntValue(None, "SNBaka.FHU.EntryContext." + a.GetFormID())
            akHost._Log("[SNBaka] FHU entry-capture cleared at scene end: " + a.GetDisplayName() + " (thread " + aiThreadID + ")")
        EndIf
        i += 1
    EndWhile
EndFunction

; : MOVED VERBATIM from the motherboard's _PollFHULevels (called by the
; motherboard's multiplexed OnUpdate tick and the seed pass in its _FHUStartPoll).
; : body EXTENDED -- per-orifice caches + the creature-ambient pass ride
; the same 10s poll (no new timer class; accept-the-mechanic per ruling (c)).
;  (dogfood 2.1 fix, RELEASE-BLOCKING): the installed FHU Baka Edition
; 2.11 writes sr.inflater.amount ONE-SHOT at Inflate() end -- the FormListAdd
; and the amount write land together, between two poll ticks (verified in the
; 2.11 sources: sr_inflateThread.Inflate tail, FormListAdd + SetFloatValue
; adjacent). The v1 semantics treated an actor's FIRST sighting as baseline-
; only (last == -1 -> record, no fire) -- correct when the poll could watch
; the amount climb tick by tick, but under the one-shot write contract the
; poll only ever sees the FINAL amount on first sight, so every FIRST
; inflation of an actor was silently swallowed (the dogfood: cue chain dead,
; SL + OStim both, no log errors). Fix: on LIVE polls (not the arm-time seed
; pass, abSeedPass=True) a first-sighting with cur > 0 fires the inflate cue
; with last = 0 -- the full jump is the event. Re-inflations of already-
; baselined actors and deflates (progressive writes) are unchanged. The
; arm-time seed pass keeps baseline-only semantics so a stale inflated actor
; never fires a boot cue.
Function PollLevels(SkyrimNet_BakaIntegration akHost, Bool abSeedPass = False) Global
    Form fhq = Game.GetFormFromFile(0x000D63, "sr_FillHerUp.esp")
    If !fhq
        Return
    EndIf
    Int n = StorageUtil.FormListCount(fhq, "sr.inflater.Actors")
    Int i = 0
    While i < n
        Actor a = StorageUtil.FormListGet(fhq, "sr.inflater.Actors", i) as Actor
        If a
            Float cur = StorageUtil.GetFloatValue(a, "sr.inflater.amount", 0.0)
            Float curV = StorageUtil.GetFloatValue(a, "sr.inflater.cum.vaginal", 0.0)
            Float curA = StorageUtil.GetFloatValue(a, "sr.inflater.cum.anal", 0.0)
            Float curO = StorageUtil.GetFloatValue(a, "sr.inflater.cum.oral", 0.0)
            String sId = a.GetFormID()
            Float last = StorageUtil.GetFloatValue(None, "SNBaka.FHULast." + sId, -1.0)
            Float lastV = StorageUtil.GetFloatValue(None, "SNBaka.FHULast.V." + sId, -1.0)
            Float lastA = StorageUtil.GetFloatValue(None, "SNBaka.FHULast.A." + sId, -1.0)
            Float lastO = StorageUtil.GetFloatValue(None, "SNBaka.FHULast.O." + sId, -1.0)
            If last < 0.0 && !abSeedPass && cur > 0.0
                ;  first-sighting on a LIVE poll: the one-shot write
                ; contract means this actor was inflated between two ticks --
                ; the full 0 -> cur jump IS the inflate event (see header).
                ; Per-orifice "last" values pass 0.0 so _FireChange's delta
                ; logic resolves the dominant orifice from the current loads.
                _FireChange(akHost, a, 0.0, cur, 0.0, curV, 0.0, curA, 0.0, curO)
                akHost._Log("[SNBaka] FHU first-sighting fire (REV-159): " + a.GetDisplayName() + " amount 0.0 -> " + cur + " (one-shot write contract, first inflation)")
            ElseIf last >= 0.0 && Math.Abs(cur - last) > 0.001
                _FireChange(akHost, a, last, cur, lastV, curV, lastA, curA, lastO, curO)
            EndIf
            StorageUtil.SetFloatValue(None, "SNBaka.FHULast." + sId, cur)
            If lastV >= 0.0
                StorageUtil.SetFloatValue(None, "SNBaka.FHULast.V." + sId, curV)
                StorageUtil.SetFloatValue(None, "SNBaka.FHULast.A." + sId, curA)
                StorageUtil.SetFloatValue(None, "SNBaka.FHULast.O." + sId, curO)
            EndIf
            _CheckCreatureAmbient(akHost, a, cur, curV, curA, curO)
            _CheckAmbientExpose(akHost, a, cur)   ; : bystander reaction pass (30%/60% bands)
        EndIf
        i += 1
    EndWhile
EndFunction

; : MOVED VERBATIM from the motherboard's _FireFHUChange.
; : REWRITTEN -- orifice-aware instant inflate (context primary, captured
; arousal secondary) + per-orifice deflate split (rulings (a)/(b)/(e) + the mid-rev
; orifice-aware inflate ruling). DRAFT cue texts: sec.7 approval pending; wording
; rule 3b-ii stands (never assert WHY -- no framework, source, or mechanism named).
Function _FireChange(SkyrimNet_BakaIntegration akHost, Actor akActor, Float afLast, Float afCur, \
        Float afLastV, Float afCurV, Float afLastA, Float afCurA, Float afLastO, Float afCurO) Global
    String sId = akActor.GetFormID()
    If afCur > afLast
        ; ---- INSTANT INFLATE: orifice = dominant cum.* delta ----
        Float dV = afCurV - afLastV
        Float dA = afCurA - afLastA
        Float dO = afCurO - afLastO
        Int orifice = 0
        If dV >= dA && dV >= dO && dV > 0.0
            orifice = 1
        ElseIf dA >= dO && dA > 0.0
            orifice = 2
        ElseIf dO > 0.0
            orifice = 3
        EndIf
        String sOrifice = "none"
        String sContainer = "belly"
        If orifice == 1
            sOrifice = "vaginal"
            sContainer = "womb"
        ElseIf orifice == 2
            sOrifice = "anal"
            sContainer = "bowels"
        ElseIf orifice == 3
            sOrifice = "oral"
            sContainer = "stomach"
        EndIf
        Int ctx = StorageUtil.GetIntValue(None, "SNBaka.FHU.EntryContext." + sId, 0)
        Int tier = StorageUtil.GetIntValue(None, "SNBaka.FHU.EntryTier." + sId, 0)
        String sCtx = "agnostic"
        String desc = akActor.GetDisplayName() + "'s " + sContainer + " is noticeably fuller now, swelling with warmth."
        If ctx == 2
            sCtx = "non-consensual"
            desc = akActor.GetDisplayName() + "'s " + sContainer + " swells fuller, heavy and unwanted."
        ElseIf ctx == 1
            sCtx = "consensual"
            desc = akActor.GetDisplayName() + "'s " + sContainer + " is noticeably fuller now, warm and welcome."
        EndIf
        If tier == 3
            desc = desc + " A flush of heat rides them."
        ElseIf tier == 1
            desc = desc + " A shiver of unease runs through them."
        EndIf
        akHost._Log("[SNBaka] _FireFHUChange: " + akActor.GetDisplayName() + " amount " + afLast + " -> " + afCur + " -> sdb_fhu_inflate orifice " + sOrifice + " context " + sCtx + " arousal tier " + tier)
        SkyrimNetApi.RegisterEvent("sdb_fhu_inflate", desc, akActor, None)
        ;  (Follow-up Prompt pattern, the  shape): the direct
        ; narration is a SEPARATE, MCM-gated surface. The narration yaml
        ; (sdb_fhu_inflate_narr.yaml, sec.7 DRAFT = register entry 33) matches
        ; the sdb_fhu_inflate_narr event type ONLY, so the cue (mandatory,
        ; above) and the narration (optional, Fill Her Up MCM "Follow-up
        ; Prompt") are fully separable. Default OFF = cue-only. The follow-up
        ; event's own desc is a plain marker (the rendered text lives in the
        ; yaml); no template variables per the D8/sec.137 binding rule.
        If akHost.bFHUInflateNarration
            akHost._Log("[SNBaka] FHU inflate: follow-up prompt ON -- narration event fired (REV-153)")
            SkyrimNetApi.RegisterEvent("sdb_fhu_inflate_narr", "[sdb_fhu_inflate_narr] Follow-up narration moment for the inflation cue.", akActor, None)
        Else
            akHost._Log("[SNBaka] FHU inflate: follow-up prompt OFF -- narration skipped (REV-153)")
        EndIf
    Else
        ; ---- DEFLATE: per-orifice split (which cum.* float dropped) ----
        Float dropV = afLastV - afCurV
        Float dropA = afLastA - afCurA
        Float dropO = afLastO - afCurO
        Int orifice = 0
        If dropV >= dropA && dropV >= dropO && dropV > 0.001
            orifice = 1
        ElseIf dropA >= dropO && dropA > 0.001
            orifice = 2
        ElseIf dropO > 0.001
            orifice = 3
        EndIf
        If orifice == 0
            ; No per-orifice delta above threshold: amount dropped, so something
            ; left -- attribute to the dominant CURRENT load; if every orifice
            ; reads zero this is an amount-only edge: silent skip, sentinel'd
            ; (the generic deflate type is retired and never fires).
            If afCurV <= 0.001 && afCurA <= 0.001 && afCurO <= 0.001
                akHost._Log("[SNBaka] _FireFHUChange: " + akActor.GetDisplayName() + " amount " + afLast + " -> " + afCur + " -- deflate with no per-orifice signal, no cue (generic type retired)")
                Return
            EndIf
            If afCurV >= afCurA && afCurV >= afCurO
                orifice = 1
            ElseIf afCurA >= afCurO
                orifice = 2
            Else
                orifice = 3
            EndIf
            akHost._Log("[SNBaka] _FireFHUChange: deflate with no per-orifice delta above threshold -- attributed to dominant current orifice " + orifice)
        EndIf
        String evType
        String desc
        If orifice == 1
            evType = "sdb_fhu_deflate_vaginal"
            desc = akActor.GetDisplayName() + " is suddenly hit by an undeniable need to evacuate -- with legs squeezed together, the pressure pours out of them, leaving their womb lighter."
        ElseIf orifice == 2
            evType = "sdb_fhu_deflate_anal"
            desc = akActor.GetDisplayName() + " can no longer hold it in -- they clench and helplessly let it out of their backside, relief and embarrassment mingling."
        Else
            evType = "sdb_fhu_deflate_oral"
            desc = akActor.GetDisplayName() + " doubles over and brings up what was forced down their throat, eyes watering."
        EndIf
        akHost._Log("[SNBaka] _FireFHUChange: " + akActor.GetDisplayName() + " amount " + afLast + " -> " + afCur + " -> " + evType)
        SkyrimNetApi.RegisterEvent(evType, desc, akActor, None)
    EndIf
EndFunction

; ----  (d): CREATURE-CUM AMBIENT CUE ----
; Poll-tick ambient, one shot per inflation episode (flag set on the first
; evaluation of a non-zero episode, cleared when amount returns to zero). SKIP
; human/unsupported (silent to the cue stream, sentinel'd). {{creature}}
; resolves to the race EDITOR ID via the injector formlists +
; MiscUtil.GetRaceEditorID (pre-check 3.2 verdict: a real race name, not just a
; race class; the editor ID ships as-is -- a pretty-name pass is sec.7 polish,
; gap named). The canned line keys on the FHU per-race cum-effect FormLists'
; creature classes (Dragon/Spider/Troll/Draugr/Chaurus/Bear --
; sr_inflateConfig L1769-1789) with a generic fallback for the remaining
; creature races (the ~38 CREATURERACE_CUM_AMOUNT classes without effect lists
; -- gaps named in the register); the container word keys on the dominant
; cum.* type (womb/bowels/stomach per the user-quoted template). Template
; fixed fields are USER-QUOTED ( ruling (d)): register-cited, no
; approval loop on them; the canned lines are sec.7 DRAFTs ().
Function _CheckCreatureAmbient(SkyrimNet_BakaIntegration akHost, Actor akActor, Float afCur, Float afCurV, Float afCurA, Float afCurO) Global
    String kFlag = "SNBaka.FHUCreatureFired." + akActor.GetFormID()
    If afCur <= 0.001
        If StorageUtil.GetIntValue(None, kFlag, 0) != 0
            StorageUtil.UnsetIntValue(None, kFlag)
            akHost._Log("[SNBaka] FHU creature ambient: episode ended for " + akActor.GetDisplayName() + " -- flag cleared")
        EndIf
        Return
    EndIf
    If StorageUtil.GetIntValue(None, kFlag, 0) != 0
        Return
    EndIf
    StorageUtil.SetIntValue(None, kFlag, 1)
    Actor inj = None
    Int nInj = StorageUtil.FormListCount(akActor, "sr.inflater.injector")
    If nInj > 0
        inj = StorageUtil.FormListGet(akActor, "sr.inflater.injector", 0) as Actor
    EndIf
    If !inj
        nInj = StorageUtil.FormListCount(akActor, "sr.inflater.analinjector")
        If nInj > 0
            inj = StorageUtil.FormListGet(akActor, "sr.inflater.analinjector", 0) as Actor
        EndIf
    EndIf
    If !inj
        akHost._Log("[SNBaka] FHU creature ambient: no injector recorded for " + akActor.GetDisplayName() + " -- skip (unsupported)")
        Return
    EndIf
    Race r = inj.GetLeveledActorBase().GetRace()
    If !r
        akHost._Log("[SNBaka] FHU creature ambient: injector " + inj.GetDisplayName() + " has no race -- skip (unsupported)")
        Return
    EndIf
    If StorageUtil.FormListCount(r, "sr.inflater.race.cum.effects") > 0
        akHost._Log("[SNBaka] FHU creature ambient: injector " + inj.GetDisplayName() + " is humanoid -- skip (human)")
        Return
    EndIf
    String sRace = MiscUtil.GetRaceEditorID(r)
    If sRace == ""
        akHost._Log("[SNBaka] FHU creature ambient: injector race editor ID unresolved -- skip (unsupported)")
        Return
    EndIf
    String sContainer = "belly"
    If afCurV >= afCurA && afCurV >= afCurO && afCurV > 0.0
        sContainer = "womb"
    ElseIf afCurA >= afCurO && afCurA > 0.0
        sContainer = "bowels"
    ElseIf afCurO > 0.0
        sContainer = "stomach"
    EndIf
    String desc = akActor.GetDisplayName() + " feels the " + sRace + " cum sloshing around in their " + sContainer + ". They feel " + _CreatureClassLine(sRace) + "."
    akHost._Log("[SNBaka] FHU creature ambient: firing sdb_fhu_creature_cum for " + akActor.GetDisplayName() + " (injector race " + sRace + ", container " + sContainer + ")")
    SkyrimNetApi.RegisterEvent("sdb_fhu_creature_cum", desc, akActor, None)
EndFunction

; : canned-description map (sec.7 DRAFT, , approval pending);
; class patterns mirror FHU's own GetRaceIndex approach (sr_inflateQuest L935+
; substring matching) against the creature classes that carry
; CREATURERACE_CUM_EFFECTS entries (the FormList enumeration source,
; sr_inflateConfig L1769-1789). Generic fallback covers the remaining creature
; races (wolves/horses/etc. -- CREATURERACE_CUM_AMOUNT classes without effect
; lists); those gaps are named in the register.
String Function _CreatureClassLine(String asRace) Global
    If StringUtil.Find(asRace, "Dragon") >= 0 || StringUtil.Find(asRace, "Alduin") >= 0
        Return "a searing, immense heat spread deep inside them"
    ElseIf StringUtil.Find(asRace, "Spider") >= 0
        Return "a thick, clinging weight shift inside them with every step"
    ElseIf StringUtil.Find(asRace, "Troll") >= 0
        Return "a heavy, musky fullness that will not settle"
    ElseIf StringUtil.Find(asRace, "Draugr") >= 0 || StringUtil.Find(asRace, "AshSpawn") >= 0
        Return "a cold, grave-dank heaviness deep in their core"
    ElseIf StringUtil.Find(asRace, "Chaurus") >= 0
        Return "a slick, tingling residue that numbs as it sits"
    ElseIf StringUtil.Find(asRace, "Bear") >= 0
        Return "a dense, animal warmth packed tight inside them"
    EndIf
    Return "a strange, foreign warmth shifting inside them"
EndFunction

; ---- : FHU AMBIENT BYSTANDER REACTION CUE (the planner's 30%/60% expose
; bands; the cum-ambient pattern applied to FHU). Poll-tick ambient: the 10s RT
; level poll (motherboard _RT_POLL_INTERVAL 10.0) walks every inflated actor
; already -- the per-actor next-fire RT stamp rides it (the ObservationPass
; per-actor-cooldown pattern,  rider; NOT a DeDService timer rule: FHU
; has no DeDService state family and no compiled sr_* reference is possible --
; fork Scripts\Source carries zero sr_*.psc stubs). Cadence 60s RT per actor,
; anchored at FIRST band crossing (first ambient fires AT band entry as of the
;  first-fire acceleration; the instant cue owns the fresh-inflation
; moment; no catch-up per ).
; Band floors = PERCENT of FHU maxInflation via the MCM sliders (C5 ruling:
; planner values 30/60 are the defaults, the MCM is the user valve). Band +
; source wordings are sec.7 DRAFTs (, register entry 34). All
; RegisterEvent descs ASCII ( rider).
Float Function _FHUMaxInflation() Global
    ; FHU's vaginal/anal capacity default (sr_inflateConfig.psc L60
    ; maxInflationDefault = 6.0, assigned at config load L364). No Papyrus
    ; surface against FHU scripts exists in-tree (no stubs), so the percent
    ; mapping rides the 6.0 default constant -- NAMED GAP: if the user raises
    ; maxInflation in FHU's own MCM, these bands still scale to the default
    ; 6.0 (surfaced at the  gate report; a live-read pass would need an
    ; sr_inflateQuest stub, out of Papyrus-only scope).
    Return 6.0
EndFunction

Function _CheckAmbientExpose(SkyrimNet_BakaIntegration akHost, Actor akActor, Float afCur) Global
    String sId = akActor.GetFormID()
    String kNext  = "SNBaka.FHU.AmbNext." + sId
    String kStart = "SNBaka.FHU.AmbStart." + sId
    String kDone  = "SNBaka.FHU.AmbDone." + sId
    Float fNotice = _FHUMaxInflation() * (akHost.iFHUAmbientNoticeBand as Float) / 100.0
    Float fHeavy  = _FHUMaxInflation() * (akHost.iFHUAmbientHeavyBand as Float) / 100.0
    If fHeavy < fNotice
        fHeavy = fNotice    ; clamp: the heavy band can never sit below noticeable
    EndIf
    Float now = Utility.GetCurrentRealTime()
    ;  4.4: the ambient cadence is MCM-settable (key
    ; SNBaka.FHUAmbientCadence, DEFAULT 60s = the  historic cadence,
    ; read live at every pass -- the 159 slider pattern, no re-arm needed).
    Float fCad = StorageUtil.GetFloatValue(None, "SNBaka.FHUAmbientCadence", 60.0)
    If afCur < fNotice
        ; Lifecycle end: state cleared below the band (deflate / module clear
        ; paths) -- drop every episode key so the next episode re-anchors fresh.
        If StorageUtil.GetFloatValue(None, kNext, 0.0) != 0.0 || StorageUtil.GetIntValue(None, kDone, 0) != 0
            StorageUtil.UnsetFloatValue(None, kNext)
            StorageUtil.UnsetFloatValue(None, kStart)
            StorageUtil.UnsetIntValue(None, kDone)
            akHost._Log("[SNBaka] FHU ambient expose: " + akActor.GetDisplayName() + " dropped below the noticeable band -- episode keys cleared (REV-154)")
        EndIf
        Return
    EndIf
    If StorageUtil.GetIntValue(None, kDone, 0) != 0
        Return    ; failsafe-exhausted episode: silent until the state clears
    EndIf
    Float nextAt = StorageUtil.GetFloatValue(None, kNext, 0.0)
    If nextAt == 0.0
        ; Band entry: anchor the episode.  (Issue #4, user ruling --
        ; first-fire acceleration): the FIRST ambient fires AT BAND ENTRY, not
        ; one cadence later -- the +60s dead-air dies; the instant inflate cue
        ; still owns the fresh-moment narrative, and the cadence paces every
        ; LATER fire. A re-crossing never catches up on missed ticks (
        ; rule, unchanged).
        StorageUtil.SetFloatValue(None, kStart, now)
        StorageUtil.SetFloatValue(None, kNext, now)
        akHost._Log("[SNBaka] FHU ambient expose: band entered for " + akActor.GetDisplayName() + " (amount " + afCur + " >= noticeable " + fNotice + ") -- first ambient fires NOW (REV-164 acceleration; cadence key  paces later fires)")
        ; Fall through: nextAt == now, so the cadence check below admits the
        ; immediate first fire.
    EndIf
    If now < nextAt
        Return
    EndIf
    ; Failsafe-class lifetime guard (the  600s class, scaled to a
    ; state that can persist): 7200s RT of continuous firing exhausts the
    ; episode -- a stuck state cannot fire forever.
    If now - StorageUtil.GetFloatValue(None, kStart, now) > 7200.0
        StorageUtil.SetIntValue(None, kDone, 1)
        StorageUtil.UnsetFloatValue(None, kNext)
        akHost._Log("[SNBaka] FHU ambient expose: lifetime guard tripped for " + akActor.GetDisplayName() + " (episode past 7200s RT) -- ambient exhausted until the state clears (REV-154)")
        Return
    EndIf
    _AmbientFire(akHost, akActor, afCur, fHeavy, now, kNext)
EndFunction

; : the per-fire composition + emission (band x source), split out of
; _CheckAmbientExpose for readability. Subjectless entry-19 shape; the actor
; args bind to the inflated actor so the reaction lands in nearby NPCs'
; conversation (P2 trigger-bus semantics per the  restore --
; RegisterEvent is the load-bearing emission, NO cue yaml, same as
; sdb_cum_ambient).
Function _AmbientFire(SkyrimNet_BakaIntegration akHost, Actor akActor, Float afCur, Float afHeavyFloor, Float afNow, String asNextKey) Global
    ; Source resolution (the  creature-ambient resolver, reused):
    ; 0 indeterminate / 1 human / 2 creature. Indeterminate SKIPS cleanly.
    ;  4.4: MCM cadence key (read live per fire; default 60s).
    Float fCad = StorageUtil.GetFloatValue(None, "SNBaka.FHUAmbientCadence", 60.0)
    Int iSource = 0
    Actor inj = None
    Int nInj = StorageUtil.FormListCount(akActor, "sr.inflater.injector")
    If nInj > 0
        inj = StorageUtil.FormListGet(akActor, "sr.inflater.injector", 0) as Actor
    EndIf
    If !inj
        nInj = StorageUtil.FormListCount(akActor, "sr.inflater.analinjector")
        If nInj > 0
            inj = StorageUtil.FormListGet(akActor, "sr.inflater.analinjector", 0) as Actor
        EndIf
    EndIf
    If !inj
        akHost._Log("[SNBaka] FHU ambient expose: no injector recorded for " + akActor.GetDisplayName() + " -- skip (source indeterminate, REV-154)")
    Else
        Race r = inj.GetLeveledActorBase().GetRace()
        If !r
            akHost._Log("[SNBaka] FHU ambient expose: injector " + inj.GetDisplayName() + " has no race -- skip (source indeterminate, REV-154)")
        ElseIf StorageUtil.FormListCount(r, "sr.inflater.race.cum.effects") > 0
            iSource = 1    ; humanoid injector (the  humanoid test)
        Else
            iSource = 2    ; creature injector reads the creature class
        EndIf
    EndIf
    If iSource == 0
        StorageUtil.SetFloatValue(None, asNextKey, afNow + fCad)
        Return
    EndIf
    ; Cue composition: band x source (sec.7 DRAFTs, register entry 34).
    ;  SLIM (ruling (b), register entry 36): the ambient cue drops to
    ; NUDGE-CLASS wording -- the standing facts (band, freshness, the
    ; self/other split) now live in the get_ded_inflation bio fragment
    ; (0176_ded_fhu.prompt) and the moment-of-impact specifics stay in the
    ; APPLICATION events (sdb_fhu_inflate/_narr, per ruling (a), untouched).
    ; Band x source branches kept (the reader still needs the register of
    ; what kind of exposure this is), the directive phrasing removed.
    Bool bHeavy = afCur >= afHeavyFloor
    String sBand = "noticeable"
    String sSrc = "human"
    If bHeavy
        sBand = "heavy"
    EndIf
    String desc
    If iSource == 2
        sSrc = "creature"
        If bHeavy
            desc = "Passersby cannot help stealing glances at " + akActor.GetDisplayName() + "'s hugely swollen belly; murmurs follow them."
        Else
            desc = "A few passersby glance at " + akActor.GetDisplayName() + "'s swollen belly and trade quiet murmurs."
        EndIf
    Else
        If bHeavy
            desc = "Heads turn as " + akActor.GetDisplayName() + " passes; the hugely swollen belly draws every eye."
        Else
            desc = "A few passersby steal glances at " + akActor.GetDisplayName() + "'s noticeably swollen belly."
        EndIf
    EndIf
    akHost._Log("[SNBaka] FHU ambient expose: firing sdb_fhu_ambient for " + akActor.GetDisplayName() + " (amount " + afCur + ", band " + sBand + ", source " + sSrc + ")")
    SkyrimNetApi.RegisterEvent("sdb_fhu_ambient", desc, akActor, None)
    StorageUtil.SetFloatValue(None, asNextKey, afNow + fCad)
    ;  (the 153/134f Follow-up Prompt pattern): the direct narration is
    ; a SEPARATE, MCM-gated surface -- sdb_fhu_ambient_narr.yaml matches the
    ; sdb_fhu_ambient_narr event type ONLY (guidance = sec.7 DRAFT, register
    ; entry 34). The gated event's own desc is a plain marker (the rendered
    ; text lives in the yaml); no template variables per the D8/sec.137 rule.
    If akHost.bFHUAmbientNarration
        akHost._Log("[SNBaka] FHU ambient expose: ambient narration ON -- narration event fired (REV-154)")
        SkyrimNetApi.RegisterEvent("sdb_fhu_ambient_narr", "[sdb_fhu_ambient_narr] Follow-up narration moment for the ambient bystander cue.", akActor, None)
    Else
        akHost._Log("[SNBaka] FHU ambient expose: ambient narration OFF -- narration skipped (REV-154)")
    EndIf
EndFunction

; ---- FHU INFLATION AWARENESS (Task 3b: fallback poll design) ----
; [] The v1 comment block + the -moved HandleFHUStartSignal /
; PollLevels / _FireChange bodies that lived HERE are RETIRED -- the 
; rewrites (chunks 1-4, above) supersede them. History: sr_InfEventManager's
; broadcast system exists to register REFERENCE-ALIAS event scripts (esp records
; in sr_FillHerUp.esp -- out of Papyrus-only scope; flagged, not improvised);
; FHU's ModEvents carry no per-actor payload (sr.inflater.start/.absorb are
; parameterless; fhu.playerInflated / fhu.playerCumUpdate are player-only); the
; per-actor surface is StorageUtil (sr.inflater.amount + 's per-orifice
; cum.vaginal/.anal/.oral reads). Deflation detection stays poll-delta based
; (the SpermOut ability path exposes no event); sr.inflater.start is used ONLY
; as an immediate-poll nudge (now via HandleFHUStartSignal, above).

; (the SpermOut ability path exposes no event); sr.inflater.start is used ONLY
; as an immediate-poll nudge (now via HandleFHUStartSignal, above).

; ---- : OSTIM CLIMAX DRIVER (self-owned inflation fills) ----
; The planner's final FHU v2 lane: OStim scenes had NO inflation driver in the
; enabled profile (the SL FHU Baka OStim 0.18 bridge is DISABLED in the active
; Ultra profile; the enabled FHU 2.11 Beta registers SexLab hooks only,
; sr_inflateQuest L383-385), so OStim-driven sex never filled FHU. This driver
; REPLICATES the 0.18 bridge's OStim orgasm logic (patch sr_inflateQuest.psc
; L557-678, reference copy: [NoDelete] SL FHU Baka Ostim 0.18 -- the patch is
; DEMOTED TO REFERENCE-ONLY; this module replaces it wholesale) with the two
; user-ruled deviations:
;   (a) GENDER RESOLUTION: OActorUtil.HasSchlong + SexLab GetGender (PPLUS
;       2.18.1 SexLabFramework.psc L1092) -- NEVER AppearsFemale (absent from
;       the installed PPLUS; the patch's own gender call would not compile
;       against this runtime).
;   (b) DOUBLE-FIRE GUARD: if the 0.18 patch esp is ever re-enabled, its
;       sr_inflateQuest fills ocummale (an OCumMaleScript property that exists
;       ONLY in the patch quest script; the 2.11 quest has no such property and
;       its esp leaves it None) -- ocummale != None means the patch owns the
;       OStim lane and this driver STANDS DOWN (noted once per session, no
;       per-event spam).
; Payload (OStim "ostim_actor_orgasm" broadcast): eventName, SceneID:String,
; ThreadID:Float, OrgasmedActor:Form (the orgasming actor = the cum SOURCE).
; Resolution chain: OThread.GetActors(ThreadID) -> MaleCount/CreatureCount via
; HasSchlong / !HasKeyword(ActorTypeNPC) -> orifice indices via
; OMetadata.FindActionForActor("vaginalsex"/"analsex") +
; FindActionForTarget("blowjob"/"deepthroat") -> receiver via
; GetActionTarget/GetActionActor -> pool mask via the quest's
; VAGINAL/ANAL/ORAL consts -> QueueActor(...) + InflateQueued() on the quest
; (2.11 Beta signatures, L2041/L2081), then the immediate PollLevels nudge
; (the sr.inflater.start convention).
; State: NONE beyond StorageUtil counters (None-keyed session fills +
; per-actor receipt):
;   SNBaka.FHU.OStimFills                session fill count (driver liveness)
;   SNBaka.FHU.OStimActorFills.<formid>  per-actor fill count (cum receiver)
;   SNBaka.FHU.OStimGuardNoted           double-fire guard session sentinel
; Armed presence-gated on the motherboard (OStim.esp installed; absent esp =
; event never sent = listener idle, the 0171 convention).
Function HandleOStimOrgasm(SkyrimNet_BakaIntegration akHost, String asEventName, String asSceneID, Float afThreadID, Form akSender) Global
    ; gate 1: master toggles + FHU runtime present (the standing module gate)
    If !(akHost.bEnabled && akHost.bFHUInflationEnabled && Installed())
        Return
    EndIf
    ; gate 2: resolve the FHU quest (installed form 0x06000D63 = the ACTIVE
    ; sr_FillHerUp.esp's sr_inflateQuest, whichever variant is enabled -- the
    ; base hotfix and the 0.18 patch esp share the 0x000D63 record)
    sr_inflateQuest srq = Game.GetFormFromFile(0x000D63, "sr_FillHerUp.esp") as sr_inflateQuest
    If !srq
        Return
    EndIf
    ; gate 3 (DOUBLE-FIRE GUARD): the 0.18 patch quest fills ocummale from
    ; OCum's OCumMaleQuest; the 2.11 quest resolves None. Patch active = patch
    ; owns the OStim lane = this driver stands down.
    If srq.ocummale != None
        If StorageUtil.GetIntValue(None, "SNBaka.FHU.OStimGuardNoted", 0) == 0
            StorageUtil.SetIntValue(None, "SNBaka.FHU.OStimGuardNoted", 1)
            akHost._Log("[SNBaka] OStim climax: double-fire guard -- ocummale present on sr_inflateQuest 0x000D63 (the SL FHU Baka OStim 0.18 patch owns the OStim lane); driver stands down")
        EndIf
        Return
    EndIf
    Actor cummer = akSender as Actor
    If !cummer
        Return
    EndIf
    Actor[] actors = OThread.GetActors(afThreadID as Int)
    If !actors || actors.Length == 0
        akHost._Log("[SNBaka] OStim climax: empty actor list for thread " + (afThreadID as Int) + " -- skip")
        Return
    EndIf
    Int i = actors.Length
    Int iMaleCount = 0
    Int iCreatureCount = 0
    While i > 0
        i -= 1
        If OActorUtil.HasSchlong(actors[i])
            iMaleCount += 1
        EndIf
        If !actors[i].HasKeyword(srq.ActorTypeNPC)
            iCreatureCount += 1
        EndIf
    EndWhile
    If iMaleCount < 1 && iCreatureCount < 1
        akHost._Log("[SNBaka] OStim climax: no schlong/creature source in scene " + asSceneID + " -- skip")
        Return
    EndIf
    Int iCummerIndex = actors.Find(cummer)
    If iCummerIndex < 0
        Return
    EndIf
    ; orifice resolution (the 0.18 chain, verbatim metadata calls)
    Int iVagIndex = OMetadata.FindActionForActor(asSceneID, iCummerIndex, "vaginalsex")
    Int iAnalIndex = OMetadata.FindActionForActor(asSceneID, iCummerIndex, "analsex")
    Int iOralIndex = OMetadata.FindActionForTarget(asSceneID, iCummerIndex, "blowjob")
    If iOralIndex == -1
        iOralIndex = OMetadata.FindActionForTarget(asSceneID, iCummerIndex, "deepthroat")
    EndIf
    Int iPool = 0
    Int iCummedIndex = -1
    If iVagIndex != -1
        iPool = Math.LogicalOr(iPool, srq.VAGINAL)
        iCummedIndex = OMetadata.GetActionTarget(asSceneID, iVagIndex)
    EndIf
    If iAnalIndex != -1
        iPool = Math.LogicalOr(iPool, srq.ANAL)
        iCummedIndex = OMetadata.GetActionTarget(asSceneID, iAnalIndex)
    EndIf
    If iOralIndex != -1
        iPool = Math.LogicalOr(iPool, srq.ORAL)
        iCummedIndex = OMetadata.GetActionActor(asSceneID, iOralIndex)
    EndIf
    If iCummedIndex < 0 || iCummedIndex >= actors.Length || iPool == 0
        Return
    EndIf
    Actor cummed = actors[iCummedIndex]
    ; gender gate (user ruling (a): HasSchlong + GetGender, never AppearsFemale)
    Bool bSchlong = OActorUtil.HasSchlong(cummed)
    Int iGender = srq.sexlab.GetGender(cummed)
    Bool bEligible = False
    If !bSchlong || iGender == 1
        bEligible = srq.config.femaleEnabled
    ElseIf bSchlong && iGender == 0
        bEligible = srq.config.maleEnabled
    EndIf
    If !bEligible
        akHost._Log("[SNBaka] OStim climax: receiver " + cummed.GetLeveledActorBase().GetName() + " fails the gender/config gate (schlong=" + bSchlong + ", gender=" + iGender + ") -- skip")
        Return
    EndIf
    Actor[] cumSource = New Actor[1]
    cumSource[0] = cummer
    akHost._Log("[SNBaka] OStim climax: lane engaged for " + cummed.GetLeveledActorBase().GetName() + " (scene " + asSceneID + ", pool " + iPool + ")")
    Int iThread = srq.QueueActor(cummed, True, iPool, srq.GetCumAmountForActor(cummed, cumSource), 3.0)
    If iThread < 0
        akHost._Log("[SNBaka] OStim climax: inflation slots full, skipping " + cummed.GetLeveledActorBase().GetName())
    Else
        akHost._Log("[SNBaka] OStim climax: queued " + cummed.GetLeveledActorBase().GetName() + " to thread " + iThread)
        StorageUtil.SetFloatValue(None, "SNBaka.FHU.OStimFills", StorageUtil.GetFloatValue(None, "SNBaka.FHU.OStimFills", 0.0) + 1.0)
        StorageUtil.SetFloatValue(cummed, "SNBaka.FHU.OStimActorFills." + cummed.GetFormID(), StorageUtil.GetFloatValue(cummed, "SNBaka.FHU.OStimActorFills." + cummed.GetFormID(), 0.0) + 1.0)
    EndIf
    ; queue drain (the 0.18 order: unconditionally after the queue attempt) +
    ; the immediate poll nudge (the sr.inflater.start convention)
    srq.InflateQueued()
    PollLevels(akHost)
EndFunction
;   SNBaka.FHU.OStimActorFills.<formid>  per-actor fill count (cum receiver)
;   SNBaka.FHU.OStimGuardNoted           double-fire guard session sentinel
; Armed presence-gated on the motherboard (OStim.esp installed; absent esp =
; event never sent = listener idle, the 0171 convention).

; ------------------------------------------------------------------
;  - PROMPT-LAYER EXTENSION (the cum-v2 mold applied to FHU)
; ------------------------------------------------------------------
; Two module-owned decorators (registered at arm - the /132b
; class; the motherboard calls ArmDecorators every arm pass):
;   get_ded_inflation(actor)      bio-lane FACTS (the 0175 mold): the
;                                 self/other split, band (noticeable /
;                                 heavy), freshness_s, and the 0171-class
;                                 window flag prompt_show (opens ~60s per
;                                 600s of banded time; fresh inflation is
;                                 always inside an open window).
;   get_ded_inflation_any(actor)  disposition-lane eligibility (the 132b
;                                 minimal any/nearest class).
; NULL CONTRACT (the  discipline): every absent-framework state
; returns well-formed JSON - FHU absent, quest form unresolved, no
; inflated actors, nothing in band, or an empty cell all read as
; {"present": false} / {"any": false}; band floors default 30/60 when the
; host pointer is unavailable; freshness reads 0; prompt_show reads 1
; only inside an open window; no read can surface null. Documented
; in-code per the 3.5 mandate.
; ------------------------------------------------------------------
Function ArmDecorators(SkyrimNet_BakaIntegration akHost) Global
    Int rcFacts = SkyrimNetApi.RegisterDecorator("get_ded_inflation", "SNBaka_FHUInflationModule", "GetDedInflation")
    Int rcAny = SkyrimNetApi.RegisterDecorator("get_ded_inflation_any", "SNBaka_FHUInflationModule", "GetDedInflationAny")
    ; host pointer cache (the SNBaka.CumWearer form-pointer precedent) so
    ; the decorators can read the MCM band sliders without an argument
    If akHost
        StorageUtil.SetFormValue(None, "SNBaka.FHU.Host", akHost)
    EndIf
    If akHost
        akHost._Log("[SNBaka] decorator register: get_ded_inflation rc=" + rcFacts + " get_ded_inflation_any rc=" + rcAny + " (REV-157)")
    Else
        Debug.Trace("[SNBaka] FHU decorator register: get_ded_inflation rc=" + rcFacts + " get_ded_inflation_any rc=" + rcAny + " (REV-157, no host)")
    EndIf
EndFunction

; Band floors as absolute amounts (MCM percent x maxInflation; defaults
; 30/60 when the host pointer is unavailable - the null contract).
Float Function _AmbNoticeFloor() Global
    SkyrimNet_BakaIntegration host = StorageUtil.GetFormValue(None, "SNBaka.FHU.Host", None) as SkyrimNet_BakaIntegration
    Int pct = 30
    If host
        pct = host.iFHUAmbientNoticeBand
    EndIf
    Return _FHUMaxInflation() * (pct as Float) / 100.0
EndFunction

Float Function _AmbHeavyFloor() Global
    SkyrimNet_BakaIntegration host = StorageUtil.GetFormValue(None, "SNBaka.FHU.Host", None) as SkyrimNet_BakaIntegration
    Int pct = 60
    If host
        pct = host.iFHUAmbientHeavyBand
    EndIf
    Return _FHUMaxInflation() * (pct as Float) / 100.0
EndFunction

; Shared facts-JSON composer. NULL CONTRACT: name falls back to a plain
; noun; freshness clamps >= 0 (clock-reset safe); prompt_show = 1 when
; the episode has not anchored yet (the 10s poll anchors within one tick),
; otherwise the 0171 window - open 60s of every 600s of banded time.
String Function _InflationFactsJson(Actor akInflated, Bool abSelf, Float afAmount, Float afHeavyFloor, Float afNow) Global
    String nm = akInflated.GetDisplayName()
    If nm == ""
        nm = "the swollen person"
    EndIf
    String sBand = "noticeable"
    If afAmount >= afHeavyFloor
        sBand = "heavy"
    EndIf
    Float startRT = StorageUtil.GetFloatValue(None, "SNBaka.FHU.AmbStart." + akInflated.GetFormID(), 0.0)
    Int fr = (afNow - startRT) as Int
    If fr < 0
        fr = 0
    EndIf
    Int show = 1
    If startRT > 0.0
        show = 0
        If (((afNow - startRT) as Int) % 600) < 60
            show = 1
        EndIf
    EndIf
    String s = "{\"present\": true, \"self\": " + abSelf + ", \"name\": \"" + nm + "\""
    s += ", \"band\": \"" + sBand + "\", \"freshness_s\": " + fr + ", \"prompt_show\": " + show + "}"
    Return s
EndFunction

; get_ded_inflation: bio-lane facts for the subject (self branch when the
; subject is in band; otherwise the nearest in-band inflated actor in the
; subject's cell). FHU absent / nothing in band -> {"present": false}.
String Function GetDedInflation(Actor akActor) Global
    If !Installed()
        Return "{\"present\": false}"
    EndIf
    Form fhq = Game.GetFormFromFile(0x000D63, "sr_FillHerUp.esp")
    If !fhq
        Return "{\"present\": false}"
    EndIf
    Float fNotice = _AmbNoticeFloor()
    Float fHeavy = _AmbHeavyFloor()
    If fHeavy < fNotice
        fHeavy = fNotice
    EndIf
    Float now = Utility.GetCurrentRealTime()
    If akActor
        Float amt = StorageUtil.GetFloatValue(akActor, "sr.inflater.amount", 0.0)
        If amt >= fNotice
            Return _InflationFactsJson(akActor, True, amt, fHeavy, now)
        EndIf
        If !akActor.GetParentCell()
            Return "{\"present\": false}"
        EndIf
        Int n = StorageUtil.FormListCount(fhq, "sr.inflater.Actors")
        Int i = 0
        Actor best = None
        Float bestDist = -1.0
        While i < n
            Actor a = StorageUtil.FormListGet(fhq, "sr.inflater.Actors", i) as Actor
            If a && a != akActor && a.GetParentCell() == akActor.GetParentCell() && !a.IsDead()
                Float amtA = StorageUtil.GetFloatValue(a, "sr.inflater.amount", 0.0)
                If amtA >= fNotice
                    Float d = a.GetDistance(akActor)
                    If bestDist < 0.0 || d < bestDist
                        best = a
                        bestDist = d
                    EndIf
                EndIf
            EndIf
            i += 1
        EndWhile
        If best
            Float amtBest = StorageUtil.GetFloatValue(best, "sr.inflater.amount", 0.0)
            Return _InflationFactsJson(best, False, amtBest, fHeavy, now)
        EndIf
    EndIf
    Return "{\"present\": false}"
EndFunction

; get_ded_inflation_any: the witness-eligibility read (the 132b minimal
; class). Any in-band inflated actor in the observer's cell (or the
; observer themself) -> {"any": true, "nearest": "<name>"}; else
; {"any": false}. The speaker/target rule is compliant by construction
; (the observer is always the actor in scope).
String Function GetDedInflationAny(Actor akObserver) Global
    If !Installed() || !akObserver
        Return "{\"any\": false}"
    EndIf
    Form fhq = Game.GetFormFromFile(0x000D63, "sr_FillHerUp.esp")
    If !fhq
        Return "{\"any\": false}"
    EndIf
    Float fNotice = _AmbNoticeFloor()
    If StorageUtil.GetFloatValue(akObserver, "sr.inflater.amount", 0.0) >= fNotice
        String selfNm = akObserver.GetDisplayName()
        If selfNm == ""
            selfNm = "the swollen person"
        EndIf
        Return "{\"any\": true, \"nearest\": \"" + selfNm + "\"}"
    EndIf
    If !akObserver.GetParentCell()
        Return "{\"any\": false}"
    EndIf
    Int n = StorageUtil.FormListCount(fhq, "sr.inflater.Actors")
    Int i = 0
    Actor best = None
    Float bestDist = -1.0
    While i < n
        Actor a = StorageUtil.FormListGet(fhq, "sr.inflater.Actors", i) as Actor
        If a && a != akObserver && a.GetParentCell() == akObserver.GetParentCell() && !a.IsDead()
            If StorageUtil.GetFloatValue(a, "sr.inflater.amount", 0.0) >= fNotice
                Float d = a.GetDistance(akObserver)
                If bestDist < 0.0 || d < bestDist
                    best = a
                    bestDist = d
                EndIf
            EndIf
        EndIf
        i += 1
    EndWhile
    If !best
        Return "{\"any\": false}"
    EndIf
    String nearest = best.GetDisplayName()
    If nearest == ""
        nearest = "the swollen person"
    EndIf
    Return "{\"any\": true, \"nearest\": \"" + nearest + "\"}"
EndFunction
