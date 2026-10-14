Scriptname SNBaka_FHUInflationModule
;  Task 2: FHU-inflation module (recordless detection class -- module contract
; point 3, fomod.md section architecture). Extracted BEHAVIOR-PRESERVING from the
; /65 detection-triggers section of SkyrimNet_BakaIntegration.psc (the 
; class: signatures and sentinels moved verbatim; only the call shape changed).
; The FHU HEARTBEAT SELF-HEAL pattern (: the poll arms from Setup() AND the
; OnUpdateGameTime heartbeat because the MCM reload chain was stale at save-load) is
; PRESERVED IN FULL: the arming points (Setup + heartbeat), the idempotent arming
; guard, and the multiplexed real-time tick all remain on the motherboard -- a
; recordless script cannot own an OnUpdate chain. This module owns the poll BODY and
; the cue logic only.
;
; State: NONE of its own. The bFHUInflationEnabled toggle remains the motherboard's
; Auto property (the MCM reads it as Main.*); read through the akHost parameter.
; The last-seen-level cache (SNBaka.FHULast.<formid>, None-keyed) is unchanged --
; same keys, same comparison window.
;
; Logging: every sentinel goes through akHost._Log() -- identical strings, identical
; bDebugLog gating (sentinel parity per ; the [SNBaka] tag preserved verbatim).

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
;   sr.inflater.Actors (formlist, keyed on the sr_inflateQuest form 0x000D63)
; Level changes forward as sdb_fhu_inflate (increase) / sdb_fhu_deflate (decrease).
; Deflation detection = amount decreasing in the poll (the SpermOut ability path
; exposes no event). sr.inflater.start is used ONLY as an immediate-poll nudge on
; top of the interval.
;
; : MOVED BODY of the motherboard's OnFHUStartSignal event (zero-arg handler --
; sr.inflater.start is a parameterless broadcast; the  4-slot shape is retired).
Function HandleFHUStartSignal(SkyrimNet_BakaIntegration akHost) Global
    If akHost.bEnabled && akHost.bFHUInflationEnabled && Installed()
        akHost._Log("[SNBaka] OnFHUStartSignal: sr.inflater.start received -- immediate level poll")
        PollLevels(akHost)
    EndIf
EndFunction

; : MOVED VERBATIM from the motherboard's _PollFHULevels (called by the
; motherboard's multiplexed OnUpdate tick and the seed pass in its _FHUStartPoll).
Function PollLevels(SkyrimNet_BakaIntegration akHost) Global
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
            String sKey = "SNBaka.FHULast." + a.GetFormID()
            Float last = StorageUtil.GetFloatValue(None, sKey, -1.0)
            If last >= 0.0 && Math.Abs(cur - last) > 0.001
                _FireChange(akHost, a, last, cur)
            EndIf
            StorageUtil.SetFloatValue(None, sKey, cur)
        EndIf
        i += 1
    EndWhile
EndFunction

; : MOVED VERBATIM from the motherboard's _FireFHUChange.
Function _FireChange(SkyrimNet_BakaIntegration akHost, Actor akActor, Float afLast, Float afCur) Global
    String evType
    String desc
    If afCur > afLast
        evType = "sdb_fhu_inflate"
        ; DRAFT cue ( approval pending). Future-proof wording rule (3b-ii):
        ; never assert WHY the level changed -- no framework, source, or
        ; mechanism named. The state is observable; the cause is not.
        desc = akActor.GetDisplayName() + "'s belly is noticeably fuller now, swelling with warmth."
    Else
        evType = "sdb_fhu_deflate"
        desc = akActor.GetDisplayName() + "'s swollen belly is going down at last -- the release leaves them lighter."
    EndIf
    akHost._Log("[SNBaka] _FireFHUChange: " + akActor.GetDisplayName() + " amount " + afLast + " -> " + afCur + " -> " + evType)
    SkyrimNetApi.RegisterEvent(evType, desc, akActor, None)
EndFunction
