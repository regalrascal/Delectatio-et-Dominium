Scriptname SNBaka_CumDetectionModule
;  Task 2: cum-detection module (recordless detection class -- module contract
; point 3, fomod.md section architecture). Extracted BEHAVIOR-PRESERVING from the
; /65 detection-triggers section of SkyrimNet_BakaIntegration.psc (the 
; class: every handler signature and sentinel moved verbatim; only the call shape
; changed -- the motherboard's ModEvent handlers forward here, because ModEvents are
; Form-members and a recordless script can never receive a ModEvent dispatch).
; NO foreign types beyond what the moved code already used: SkyrimNet_BakaSL (our own
; SexLab bridge, compile-stubbed in tools\compile\local) and SkyrimNetApi.
;
; State: NONE of its own. All toggles (bEnabled, bCumDetectionEnabled, bSLProxyEnabled,
; iCumCueMode) remain the MOTHERBOARD'S Auto properties (the MCM reads them as
; Main.* -- moving them would be a structural MCM change, explicitly out of scope);
; they are read through the akHost parameter. The shared 15s cum-cue cooldown key
; (SNBaka.LastCumCueRT, None-keyed) is unchanged -- same key, same window, so the
; cooldown still spans the OCum events AND the SL proxy exactly as before.
;
; Logging: every sentinel goes through akHost._Log() -- identical strings, identical
; bDebugLog gating (sentinel parity per ; the [SNBaka] tag is preserved verbatim
; so existing log greps keep working).

; ---- Presence probe (cached: GetFormFromFile on an ABSENT esp logs a hard Papyrus
; error, not a silent None -- the SNBakaSL.Absent-cache lesson). Absence is cached
; on the None key once. MOVED VERBATIM from the motherboard's _OCumInstalled. ----
Bool Function Installed() Global
    If StorageUtil.GetIntValue(None, "SNBaka.OCumAbsent", 0) == 1
        Return False
    EndIf
    If Game.GetFormFromFile(0x000800, "OCum.esp") != None
        Return True
    EndIf
    StorageUtil.SetIntValue(None, "SNBaka.OCumAbsent", 1)
    Return False
EndFunction

; ---- CUM DETECTION (OCum / OStim side) ----
; : handler signatures derived from the senders' ACTUAL ModEvent push
; sequences (statically re-confirmed from the installed trees, per the  root
; cause of record):
;   ocum_applied_cum (OCumMaleScript.psc L689-695, [035.00002] tree):
;     PushForm(Orgasmer), PushForm(Target), PushFloat(AmountML),
;     PushString(Area), PushString(SceneID)                 -- 5 args
;   ocum_applied_cum_npc_scene (same file, L697-704):
;     Form Orgasmer, Form Target, Int ThreadID, Float AmountML,
;     String Area, String SceneID                           -- 6 args
; The  4-slot (eventName, strArg, numArg, sender) shape was RETIRED.
;  bonus (user ruling): the TARGET (second Form push) is now recoverable --
; named-partner cue wording is PRIMARY; the  unnamed wording is the fallback
; only (Target == None guard).
; : this is the MOVED BODY of the motherboard's OnOCumApplied event (signature
; verbatim; the motherboard forwards Self + the event args).
Function HandleOCumApplied(SkyrimNet_BakaIntegration akHost, Form akOrgasmer, Form akTarget, Float afAmountML, String asArea, String asSceneID) Global
    If !akHost.bEnabled || !akHost.bCumDetectionEnabled || !Installed()
        Return
    EndIf
    Actor orgasmer = akOrgasmer as Actor
    If !orgasmer || orgasmer.IsDead()
        Return
    EndIf
    Actor target = akTarget as Actor
    ;  full-payload sentinel: reception verified at the ARGUMENT level.
    akHost._Log("[SNBaka] OnOCumApplied: orgasmer=" + orgasmer.GetDisplayName() + " target=" + (target as Form) + " amount=" + afAmountML + "ml area=" + asArea + " sceneID=" + asSceneID)
    _FireCumCue(akHost, orgasmer, target)
EndFunction

; : the npc_scene variant carries ThreadID as a 3rd (Int) push, so it needs its
; own 6-arg handler. Identical gating/cue logic; thread id is logged in the sentinel.
; : MOVED BODY of the motherboard's OnOCumAppliedNPCScene event.
Function HandleOCumAppliedNPCScene(SkyrimNet_BakaIntegration akHost, Form akOrgasmer, Form akTarget, Int aiThreadID, Float afAmountML, String asArea, String asSceneID) Global
    If !akHost.bEnabled || !akHost.bCumDetectionEnabled || !Installed()
        Return
    EndIf
    Actor orgasmer = akOrgasmer as Actor
    If !orgasmer || orgasmer.IsDead()
        Return
    EndIf
    Actor target = akTarget as Actor
    akHost._Log("[SNBaka] OnOCumApplied [npc-scene]: orgasmer=" + orgasmer.GetDisplayName() + " target=" + (target as Form) + " thread=" + aiThreadID + " amount=" + afAmountML + "ml area=" + asArea + " sceneID=" + asSceneID)
    _FireCumCue(akHost, orgasmer, target)
EndFunction

; : shared outbound leg for both OCum events (was inline in the  handler).
; Shared 15s cum-cue cooldown (with the SL proxy) -- HJ/FJ scenes loop over multiple
; givers and multi-fire; one narrator cue per 15s. Cooldown behavior is IDENTICAL to
;  (same key, same window, same write point) -- only the call shape changed.
; : MOVED VERBATIM from the motherboard's _FireCumCue.
Function _FireCumCue(SkyrimNet_BakaIntegration akHost, Actor orgasmer, Actor target) Global
    Float nowRT = Utility.GetCurrentRealTime()
    If nowRT - StorageUtil.GetFloatValue(None, "SNBaka.LastCumCueRT", -999.0) < 15.0
        akHost._Log("[SNBaka] _FireCumCue: cue suppressed (shared 15s cum-cue cooldown)")
        Return
    EndIf
    StorageUtil.SetFloatValue(None, "SNBaka.LastCumCueRT", nowRT)
    String desc
    If akHost.iCumCueMode == 1
        ; per-source (OStim/OCum) wording -- DRAFT,  approval pending
        If target
            desc = orgasmer.GetDisplayName() + " just came inside " + target.GetDisplayName() + "; OCum applies the result."
        Else
            desc = orgasmer.GetDisplayName() + " just came inside an OStim scene; OCum applies the result."
        EndIf
    Else
        ; unified (framework-neutral) wording -- DRAFT,  approval pending
        If target
            desc = orgasmer.GetDisplayName() + " just came, finishing all over " + target.GetDisplayName() + "."
        Else
            desc = orgasmer.GetDisplayName() + " just came, finishing all over their partner."
        EndIf
    EndIf
    SkyrimNetApi.RegisterEvent("sdb_cum_applied", desc, orgasmer, target)
EndFunction

; ---- SEXLAB ORGASM-HOOK PROXY (amendment 2a-ii; verdict of record: PROXY) ----
; SexLab has NO dedicated cum-state API (no event/faction/spell surface; its cum
; overlays are mesh/particle only). sslThreadModel.SendThreadEvent broadcasts
; "Hook<Name>" ModEvents carrying (thread_id, HasPlayer) for the stage/animation
; lifecycle; StageEnd covers stage completions including the orgasm stage. Evidence
; supports the PROXY case: the cue rides "a SexLab scene reached release" and NEVER
; claims overlay application. numArg = thread_id (first numeric push).
; : signature derived from the sender's ACTUAL pushes (sslThreadModel
; PPLUS V2.18.1, SetupThreadEvent: PushInt(thread_id), PushBool(HasPlayer) -- 2 args).
; : MOVED BODY of the motherboard's OnSLStageEnd event.
Function HandleSLStageEnd(SkyrimNet_BakaIntegration akHost, Int aiThreadID, Bool abHasPlayer) Global
    If !akHost.bEnabled || !akHost.bCumDetectionEnabled || !akHost.bSLProxyEnabled || !SkyrimNet_BakaSL.Installed()
        Return
    EndIf
    Int threadID = aiThreadID
    If threadID < 0
        Return
    EndIf
    Actor[] positions = SkyrimNet_BakaSL.SLThreadPositions(threadID)
    If !positions || positions.Length == 0
        akHost._Log("[SNBaka] OnSLStageEnd: thread=" + threadID + " hasPlayer=" + abHasPlayer + " -- no positions resolved, skipping")
        Return
    EndIf
    Actor lead = positions[0]
    ; Shared 15s cum-cue cooldown (see _FireCumCue).
    Float nowRT = Utility.GetCurrentRealTime()
    If nowRT - StorageUtil.GetFloatValue(None, "SNBaka.LastCumCueRT", -999.0) < 15.0
        Return
    EndIf
    StorageUtil.SetFloatValue(None, "SNBaka.LastCumCueRT", nowRT)
    String desc
    If akHost.iCumCueMode == 1
        ; per-source (SexLab) wording -- DRAFT,  approval pending; proxy rule:
        ; "release" only, never overlay application.
        desc = lead.GetDisplayName() + "'s SexLab scene just reached its release."
    Else
        ; unified (framework-neutral) wording -- DRAFT,  approval pending
        desc = lead.GetDisplayName() + " just came, finishing all over their partner."
    EndIf
    akHost._Log("[SNBaka] OnSLStageEnd: thread=" + threadID + " lead=" + lead.GetDisplayName() + " -> sdb_cum_applied (SL proxy)")
    SkyrimNetApi.RegisterEvent("sdb_cum_applied", desc, lead, None)
EndFunction
