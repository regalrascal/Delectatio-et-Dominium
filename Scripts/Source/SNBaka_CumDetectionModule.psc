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
;  CUM-V2 STATE LAYER ( Task 3, unblocked by the  re-dogfood):
; DeDService.* state-family writes ride EVERY cum application signal, gated on
; DeD_ServicePresent() (SKSE.GetPluginVersion probe; the wiring is inert without the
; DLL -- no error, no orphan writes, v1 behavior exactly). State family (module
; "cum", keys per service-dll.md ):
;   cum.present          Bool, actor-keyed     -- TRUE while a cum effect persists
;   cum.last_location    String, actor-keyed   -- location literal (OCum Area domain
;                                                 or SL FX domain mouth/vagina/rectum)
;   cum.last_source      String, actor-keyed   -- "ocum" | "sexlab_pplus" | "sexlab_vanilla" | "sl_proxy"
;   cum.last_applied_rt  Float, actor-keyed    -- Utility.GetCurrentRealTime() at write
; Ambient timer rule (module "cum", rule "ambient"): cadence 60s (: was 120s --
; the first maintenance/expiry tick must land at 60s; maintenance recast, expiry
; and the ambient cue all ride this ONE clock), predicate class 1 (STATE_BOOL_TRUE)
; on cum.present, failsafe 600s, callback "sdb_cum_ambient_due".
; : the rule's time base is APPLICATION-ANCHORED -- the scheduler re-anchors
; the rule (age=0, next due=cadence) on the predicate's False->True rising edge, so
; the first ambient cue lands application + 60s (never mid-grid), and missed dues
; are SKIPPED, never drained as catch-up bursts (the 10-18 paired 1s-apart fires).
; The 600s failsafe re-anchors with it (a fresh application always gets its full
; window); if the failsafe DISARMS the rule mid-session, the next _WriteCumState
; re-arms it (AddTimerRule is key-deduped, so this is a no-op while the rule lives).
; Timer events arrive as the standard 4-slot ModEvent shape (EventPump.cpp):
; (eventName, strArg, numArg, sender) -- numArg 1 = expired (failsafe), 0 = due tick.
; VERBATIM-NARRATION GUARDRAIL (, in every touched cue): event text is written
; for the LLM to narrate VERBATIM -- never summarize, never paraphrase, never fold
; into other narration; the event text IS the narration.
;
;
;  CUM APPLIANCE AUTHORITY (matrix of record, cum-effects.md ): WE
; apply/maintain the cum visual for the state's duration. Tier routing:
;   OCum present (OStim+OCum or SL+OCum) -> OCum DRIVE: call OCumMaleScript.
;     ApplyCum(target, target, area, 1, 1.0, "", 0) -- the GENERIC entry; the
;     location is a plain String ARGUMENT dispatched to per-area functions
;     (OCumMaleScript.psc L304-345, [035.00002] tree; ThreadID=0 = the
;     out-of-scene path). FINAL 0.b ANSWER: the visual is NOT spell-carried --
;     OCumSpell -> OCumEffect is ONLY a cleanup timer (OnEffectFinish cleans
;     out-of-scene, re-casts in-scene, OCumEffect.psc L7-13); the overlay itself
;     is applied by CumOntoArea -> ReadyOverlay (OCumMaleScript.psc L510-536),
;     so a bare Cast of their spell can NEVER produce a location-correct
;     visual. The drive point is the SCRIPT call, not the spell form. Quest
;     resolution: QUST EDIDs in OCum.esp -- "OCumQuest" carries OCumScript,
;     "OCumMaleQuest" carries OCumMaleScript (esp byte-census 2026-10-17);
;     Quest.GetQuest needs no hardcoded formIDs.
;   SL only (SLACS)  -> SexLab's own combo-spell overlays stand (sslActorLibrary
;     AddCum PPLUS L805 / ClearCum L834; persist-until-dispelled). When OCum is
;     present we REPLACE them (ClearCum first -- replace-not-stack, the
;     double-visual guard; also note SL AddCum re-called on an already-cummed
;     actor ESCALATES the texture tier 1->2, so we never re-AddCum).
;   neither         -> state-only (documented degradation).
;   SL proxy (no location) -> never claims overlay application (proxy rule of
;     record); state-only, no drive call.
; MAINTENANCE: ambient ticks are sender-None FOREVER (Scheduler.cpp L124/L149 --
; EventPump::Emit(rule.callbackEvent, nullptr, ...); rule/ambient ticks are not
; actor-addressed), so the wearer is CACHED at application: DeDService type-4
; "cum.wearer" state row (the native FormID slot) + a StorageUtil form pointer
; (None-keyed; PapyrusUtil cosave-persisted, StorageUtil.psc L80/L115) for the
; sender-None tick to find them. Lifetime N=10min (named constant, all expiry
; sites read it). Expiry (tick clock) and the 600s failsafe BOTH clear the
; visual AND the state (/120 shipped the failsafe as skip-only). Refresh:
; OCum tier recasts OCumSpell on the wearer each maintenance tick -- their own
; cleanup timer (MCM default 5min, OCumMCMScript L342) is SHORTER than our
; lifetime, and the recast resets its duration so OnEffectFinish never cleans
; before our expiry (their own in-scene re-cast pattern, OCumEffect.psc L12).
; OCum re-entry is INTENDED: our SL-leg drive calls their ApplyCum, which
; re-emits ocum_applied_cum (SendCumAppliedEvents, OCumMaleScript.psc L316) ->
; our handler re-writes state source as "ocum" (the visual IS OCum's now --
; correct tier for maintenance) and the cue double-fire is eaten by the shared
; 15s window.
; D5 STALE-STAMP CLAMP: SNBaka.LastCumCueRT is a GetCurrentRealTime float that
; PERSISTS in the cosave, and GetCurrentRealTime resets each launch -- a stamp
; from a longer-prior session reads as "future", so now - stamp < 15.0 locks
; the shared cum-cue window until the NEW session's clock passes the OLD
; session's stamp (up to hours). Same class as the  muse-stamp clamp
; (SkyrimNet_AnimationsGS.psc L1021, read-time clamp precedent).  clamps
; at every OnPlayerLoadGame (motherboard), BEFORE Setup() re-arms anything,
; plus the same-class player-keyed deadline stamps (class sweep, see
; ClampStaleRTStamps). NPC-keyed instances of the class cannot be enumerated
; at load (StorageUtil has no key walk) -- documented degradation, polish note.
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

; ----  D5: stale cosave real-time stamp clamp (load-time) ----
; GetCurrentRealTime() resets each launch, but StorageUtil stamps persist in
; the cosave -- a stamp written late in a LONGER prior session reads as
; "future" here, and every `now - stamp < window` check locks until the new
; session's clock passes the old stamp (up to hours). Same class as the 
; muse-stamp clamp (SkyrimNet_AnimationsGS.psc L108-116/L1021 -- the precedent
; clamps at read;  clamps ONCE at load, BEFORE Setup() re-arms anything,
; which covers every read in the session at a single site). Called from the
; motherboard's OnPlayerLoadGame. CLASS SWEEP (fork Sources, 2026-10-17): the
; None-keyed LastCumCueRT is clamped directly; the same-class PLAYER-keyed
; deadline stamps (SNBaka.AutoGetUpDeadlineRT / SNBaka.DefeatGraceUntilRT /
; SNBaka.LastCreatureAttemptRT / SNBaka.LastHitRT / SNAcheron.FreshDownRT /
; SNAcheron.LastDefeatedRT) are clamped on PlayerRef. NPC-keyed instances of
; the class exist (Acheron/Baka downed flows stamp akVictim/akA1/akA2) but
; StorageUtil has no key walk -- they CANNOT be enumerated at load; their
; stale reads self-heal as the new session's clock advances past the old
; stamp, and the load-time latch resets already clear the owning flows.
; Documented degradation; polish note in cum-effects.md .
Function ClampStaleRTStamps(SkyrimNet_BakaIntegration akHost) Global
    Float nowRT = Utility.GetCurrentRealTime()
    Int clamped = 0
    ; None-keyed shared cum-cue cooldown stamp (the two read sites: _FireCumCue
    ; and HandleSLStageEnd).
    Float stamp = StorageUtil.GetFloatValue(None, "SNBaka.LastCumCueRT", -999.0)
    If stamp > nowRT
        StorageUtil.SetFloatValue(None, "SNBaka.LastCumCueRT", 0.0)
        clamped += 1
        akHost._Log("[SNBaka] cum cue stamp clamped (stale cosave value): " + stamp + " > now=" + nowRT + " (REV-122 D5)")
    EndIf
    ; Player-keyed deadline stamps of the same class (sweep set; see header).
    Actor player = Game.GetPlayer()
    If player
        Int i = 0
        String[] sweep = New String[6]
        sweep[0] = "SNBaka.AutoGetUpDeadlineRT"
        sweep[1] = "SNBaka.DefeatGraceUntilRT"
        sweep[2] = "SNBaka.LastCreatureAttemptRT"
        sweep[3] = "SNBaka.LastHitRT"
        sweep[4] = "SNAcheron.FreshDownRT"
        sweep[5] = "SNAcheron.LastDefeatedRT"
        While i < sweep.Length
            Float pStamp = StorageUtil.GetFloatValue(player, sweep[i], -999.0)
            If pStamp > nowRT
                StorageUtil.SetFloatValue(player, sweep[i], 0.0)
                clamped += 1
                akHost._Log("[SNBaka] stale cosave stamp clamped (stale cosave value): key=" + sweep[i] + " " + pStamp + " > now=" + nowRT + " (REV-122 D5)")
            EndIf
            i += 1
        EndWhile
    EndIf
    If clamped > 0
        akHost._Log("[SNBaka] stale RT stamp clamp: " + clamped + " key(s) clamped at load (REV-122 D5)")
    EndIf
EndFunction

; : cum visual/state lifetime, seconds (10 min, matrix of record).
; Named constant -- every expiry site reads this one function.
Float Function _CumLifetimeSec() Global
    Return 600.0
EndFunction

; ---- : DeDService presence probe + cum.* state family ----
; DLL presence via SKSE.GetPluginVersion (SKSE.psc global native: "get a plugins
; version number, -1 if the plugin is not loaded"; in the island import set).
;  D1 FIX: the probe string is the plugin's DECLARED name -- "DeDService"
; (SKSEPluginDeclaration .Name, dll-source-ded __DeDServicePlugin.cpp L6), which
; is the name SKSE itself registers and logs (skse64.log: `loading plugin
; "DeDService"` / `plugin DeDService.dll (00000001 DeDService 01000000) loaded
; correctly`).  shipped "DeDService.dll", which GetPluginVersion can never
; resolve -> the state layer stayed inert both dogfood loads ( D1 receipts).
; Never cached: cheap, and a mid-session DLL state change (impossible in
; practice) stays honest. Returns -1 when absent; > 0 requires a real version.
Bool Function DeD_ServicePresent() Global
    Return SKSE.GetPluginVersion("DeDService") > 0
EndFunction

; Registers the cum.* state family + the ambient timer rule (module "cum").
; Idempotent (the DLL treats re-registration as update); called from the
; motherboard's _ArmModules() so it rides every arm/re-arm pass.
Function ArmStateLayer(SkyrimNet_BakaIntegration akHost) Global
    If !DeD_ServicePresent()
        akHost._Log("[SNBaka] cum-v2 state layer: DeDService absent -- wiring inert (v1 behavior)")
        Return
    EndIf
    ; value types per DeDService.psc: 0=Int, 1=Float, 2=String, 3=Bool, 4=FormID
    DeDService.RegisterState("cum", "present", 3, True, "false")
    DeDService.RegisterState("cum", "last_location", 2, True, "")
    DeDService.RegisterState("cum", "last_source", 2, True, "")
    DeDService.RegisterState("cum", "last_applied_rt", 1, True, "0.0")
    ; : expiry clock + wearer cache. cum.expires_rt is the state
    ; lifetime deadline (now + _CumLifetimeSec()); cum.wearer is type 4
    ; (FormID slot, DeDService.psc L8) so the sender-None ambient tick can
    ; address the wearer (Scheduler.cpp L124/L149 -- rule ticks are never
    ; actor-addressed). The StorageUtil form pointer mirrors it for the
    ; sender-None callback leg.
    DeDService.RegisterState("cum", "expires_rt", 1, True, "0.0")
    DeDService.RegisterState("cum", "wearer", 4, True, "")
    ; ambient: cadence 60s (; was 120s -- first maintenance/expiry tick
    ; lands at 60s), class-1 (STATE_BOOL_TRUE on cum.present),
    ; failsafe 600s, callback sdb_cum_ambient_due (4-slot ModEvent shape).
    ;  4.4: the cadence is MCM-settable (key SNBaka.CumAmbientCadence,
    ; DEFAULT 60s = the historic cadence; read at every arm/re-arm -- the MCM
    ; slider accept re-arms the rule with the new value).
    DeDService.AddTimerRule("cum", "ambient", StorageUtil.GetFloatValue(None, "SNBaka.CumAmbientCadence", 60.0), 1, None, "cum.present", 600.0, "sdb_cum_ambient_due")
    ; : get_ded_cum decorator -- MODULE-OWNED per cum-effects.md 
    ; 1.1(a) + the  ownership ruling (module-specific state schema = module
    ; logic). Registered at arm so it rides every arm/re-arm pass (idempotent,
    ; same class as AddTimerRule). rc=0 = registered OK (Phase 6a.1 instrument).
    Int rcDedCum = SkyrimNetApi.RegisterDecorator("get_ded_cum", "SNBaka_CumDetectionModule", "GetDedCum")
    akHost._Log("[SNBaka] decorator register: get_ded_cum rc=" + rcDedCum + " (REV-129)")
    ; : get_ded_cum_any decorator -- module-owned companion (cum-prompt
    ; -spec.md .3): the witness-eligibility read (any tracked actor in the
    ; observer's cell marked) WITHOUT exposing the full state JSON to rule
    ; operators. Same arm-site idempotence as get_ded_cum above.
    Int rcDedCumAny = SkyrimNetApi.RegisterDecorator("get_ded_cum_any", "SNBaka_CumDetectionModule", "GetDedCumAny")
    akHost._Log("[SNBaka] decorator register: get_ded_cum_any rc=" + rcDedCumAny + " (REV-132b)")
    akHost._Log("[SNBaka] cum-v2 state layer armed: cum.* registered + ambient rule (60s/class-1/600s failsafe; )")
EndFunction

; Single write point for every cum application signal (OCum events, P+ listener,
; vanilla keyword reconciliation, SL proxy). asLocation "" = unknown -> state
; records the source but leaves last_location empty.
; : also (re)arms the lifetime deadline and caches the wearer (type-4
; state row + None-keyed StorageUtil form pointer) for the sender-None ambient
; tick, and re-applies/maintains the visual per the tier matrix (_ApplyCumVisual)
; EXCEPT when asSource == "ocum" -- the OCum legs ADOPT the visual their own
; ApplyCum already applied (drive call only on SL legs; a second call would
; re-stack their overlays). The ocum_applied_cum re-entry from our own drive
; call re-lands here with source "ocum" -- that rewrite is the correct
; maintenance tier, and the shared 15s cue window eats the cue double-fire.
;  (R2, user-ruled): resolve the appliance lane from the SELECTED decal
; source (motherboard iDecalSource: 0=OCum default, 1=SexLab, 2=P+, 3=SLACS-2+SCO).
; "ocum" -> the OCum drive; anything else -> the SLACS lane. Degradation is honest:
; a selected-but-absent source falls back to the other lane when present, else the
; caller's scene-source tiering (state-only if that fails too). P+ note: AddCum IS
; P+'s native CumFX surface (the sexlab 0050/0550 appliance family), so selections
; 1/2/3 all drive the same SLACS-family lane -- the distinction is the source the
; user declares to apply and track (SLACS-2+SCO renders its replacer textures over
; the same spells when installed).
String Function _SelectedDecalLane(SkyrimNet_BakaIntegration akHost, String asSceneSource) Global
    Int sel = 0
    If akHost
        sel = akHost.iDecalSource
    EndIf
    Bool ocumOK = Installed()
    Bool slOK = SkyrimNet_BakaSL.Installed()
    If sel == 0
        If ocumOK
            Return "ocum"
        ElseIf slOK
            Return "slacs"
        EndIf
    Else
        If slOK
            Return "slacs"
        ElseIf ocumOK
            Return "ocum"
        EndIf
    EndIf
    Return asSceneSource
EndFunction

;  (R3, user-ruled 2026-10-21): the More Cum EXPANSION MAP, verbatim
; intent. "back" in the ruling = OCum's "butt" area (user-confirmed same
; session). Returns a comma-joined area list ("" = no extras for this
; location). The old  map (throat/mouth -> face+chest; vaginal/anal
; -> thighs) is SUPERSEDED.
String Function _MoreCumExtras(String asLocation) Global
    If asLocation == "rectum" || asLocation == "ass" || asLocation == "anal"
        Return "butt,thighs"
    ElseIf asLocation == "vagina" || asLocation == "pussy"
        Return "belly,thighs"
    ElseIf asLocation == "hands"
        Return "chest"
    ElseIf asLocation == "throat"
        Return "face,mouth,chest"
    ElseIf asLocation == "face"
        Return "throat,mouth,chest"
    EndIf
    Return ""
EndFunction

Function _WriteCumState(SkyrimNet_BakaIntegration akHost, Actor akTarget, String asLocation, String asSource) Global
    If !akTarget || !DeD_ServicePresent()
        Return
    EndIf
    DeDService.SetStateBool(akTarget, "cum.present", True)
    DeDService.SetStateString(akTarget, "cum.last_location", asLocation)
    DeDService.SetStateString(akTarget, "cum.last_source", asSource)
    ;  (cum-prompt-spec.md s9, the null contract): the LOCATION SET is
    ; accumulated as a StorageUtil string list (unique append, capped at 6 --
    ; the per-location bio construction's data source; the decorator's
    ; "locations" field reads THIS list and is therefore never null and never
    ; larger than 6 entries). cum.last_location stays the single newest write
    ; (the cue's wording source, unchanged).
    If asLocation != ""
        ; : unique-append with recency refresh via StringListFind/Remove
        ; (the PapyrusUtil StorageUtil API: Find/Remove, not Get/RemoveAt).
        If StorageUtil.StringListFind(akTarget, "DeD_Cum_Locations", asLocation) >= 0
            StorageUtil.StringListRemove(akTarget, "DeD_Cum_Locations", asLocation, True)
        ElseIf StorageUtil.StringListCount(akTarget, "DeD_Cum_Locations") >= 6
            StorageUtil.StringListRemoveAt(akTarget, "DeD_Cum_Locations", 0)
        EndIf
        StorageUtil.StringListAdd(akTarget, "DeD_Cum_Locations", asLocation, False)
    EndIf
    DeDService.SetStateFloat(akTarget, "cum.last_applied_rt", Utility.GetCurrentRealTime())
    ; : expiry + wearer cache. Every application signal REFRESHES the
    ; deadline (latest-write-wins, matching how OCum re-entries extend the
    ; visual), and re-points the cache at the latest wearer.
    Float expiresRT = Utility.GetCurrentRealTime() + _CumLifetimeSec()
    DeDService.SetStateFloat(akTarget, "cum.expires_rt", expiresRT)
    DeDService.SetStateFormID(akTarget, "cum.wearer", akTarget)
    StorageUtil.SetFormValue(None, "SNBaka.CumWearer", akTarget)
    ; : bio-fragment windowing (cum-prompt-spec.md .1, the 0171
    ; SADirt_PromptShow precedent): the show window REOPENS immediately on
    ; every application so state updates land in the next bio render without
    ; hygiene-style repetition; the ambient maintenance pass (60s tick)
    ; advances the open/close cadence (~1 min open per ~10 min marked).
    StorageUtil.SetFloatValue(akTarget, "DeD_Cum_PromptShowUntil", Utility.GetCurrentRealTime() + 60.0)
    StorageUtil.SetFloatValue(akTarget, "DeD_Cum_PromptNextOpenRT", 0.0)
    StorageUtil.SetIntValue(akTarget, "DeD_Cum_PromptShow", 1)
    ; : visual drive per tier matrix. "ocum" = their ApplyCum already
    ; applied the overlay (adopt); every other source drives/replaces.
    ; : the drive is now SCENE-SOURCE-TIERED (see _ApplyCumVisual).
    ;  (R2): the drive lane is the SELECTED decal source (the dropdown),
    ; resolved once here and shared by the primary drive + the More Cum extras.
    ; Adopt rule: an OCum-scene organic application with OCum selected keeps the
    ; adopt-no-drive behavior (OCum already drew its own overlay); any other
    ; selection drives the chosen appliance (the SLACS lane's replace-not-stack
    ; clears OCum textures first, per the  symmetric matrix).
    String lane = _SelectedDecalLane(akHost, asSource)
    If lane != "ocum" || asSource != "ocum"
        _ApplyCumVisual(akTarget, asLocation, lane)
    EndIf
    ;  Task 2.2 (register 24, ruled): MORE CUM -- when enabled, sex
    ; scenes generate cum decals on additional body parts.  (R3,
    ; user-ruled 2026-10-21): the EXPANSION MAP, verbatim intent --
    ;   anus    -> back + thighs   (OCum "back" == its "butt" area, user-confirmed)
    ;   vaginal -> belly + thighs
    ;   hands   -> chest
    ;   throat  -> face + mouth + chest
    ;   face    -> throat + mouth + chest
    ; SOURCE-AGNOSTIC: extras route through the SELECTED decal source's appliance
    ; (the lane above), regardless of scene source.
    ; PER-SOURCE HONESTY (named, never silently dropped): the OCum appliance
    ; draws every map area natively (OCumMaleScript.psc L323-343); the
    ; SLACS/P+ combo-spell appliance has exactly three flags (vaginal/oral/
    ; anal) -- extras outside those three are VISUAL NO-OPS on that lane
    ; (the state's location set still records them, so the ambient wording
    ; stays honest to what the OCum lane WOULD draw; on the SLACS lane the
    ; extras' own-area words appear only when a combo flag matches).
    ; RE-ENTRY HONESTY: the extra ApplyCum drives re-emit ocum_applied_cum,
    ; whose re-entry rewrites last_location to the extra area and joins it to
    ; DeD_Cum_Locations (decals ARE observable cum areas). No recursion: the
    ; extras are applied via _ApplyCumVisual directly -- the extra drive path
    ; never re-enters _WriteCumState's extras branch.
    If asLocation != "" && akHost && akHost.bMoreCumEnabled
        String extras = _MoreCumExtras(asLocation)
        If extras != ""
            String extraList = ""
            String[] areas = PapyrusUtil.StringSplit(extras, ",")
            Int i = 0
            While i < areas.Length
                If areas[i] != ""
                    _ApplyCumVisual(akTarget, areas[i], lane)
                    If extraList != ""
                        extraList = extraList + "+"
                    EndIf
                    extraList = extraList + areas[i]
                EndIf
                i += 1
            EndWhile
            akHost._Log("[SNBaka] More Cum: " + asLocation + " -> additional decals (" + extraList + ") via decal source " + akHost.iDecalSource + " (REV-134d)")
        EndIf
    EndIf
    ; : keep the ambient rule ALIVE across a mid-session failsafe disarm
    ; (600s after the last application the rule disarms itself; a later in-session
    ; application would otherwise run ambient-dead until the next game reload).
    ; AddTimerRule is key-deduped (Scheduler.cpp L66), so this is a no-op while
    ; the rule lives -- the re-arm only lands after a failsafe disarm.
    ;  4.4: the re-arm reads the MCM cadence key (default 60s).
    DeDService.AddTimerRule("cum", "ambient", StorageUtil.GetFloatValue(None, "SNBaka.CumAmbientCadence", 60.0), 1, None, "cum.present", 600.0, "sdb_cum_ambient_due")
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
    ; : the Area string now reaches the fire path (location-variant
    ; dispatch, cum-effects v2 item 2 -- it was dropped here in v1).
    ;  EVENT-LEVEL SOURCE ENFORCEMENT (ownership ruling of record): the
    ; OCum Orgasmer payload is PER-EVENT (OCumMaleScript.psc L689-695/L697-704,
    ; PushForm(Orgasmer) first, one event per application), and a female
    ; non-futa source does not own our cues OR our state -- her application is
    ; SN-SexLab's lane entirely. Validated BEFORE the state write ('s
    ; write-before-cue order is superseded here: her event writes nothing).
    If !_EventSourceOwnsCum(akHost, orgasmer)
        Return
    EndIf
    _WriteCumState(akHost, target, asArea, "ocum")
    _FireCumCue(akHost, orgasmer, target, asArea)
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
    ; : Area reaches the fire path here too (location-variant dispatch).
    ; : event-level source enforcement BEFORE the state write (same as
    ; the 5-arg handler -- the 6-arg payload is likewise per-event Orgasmer).
    If !_EventSourceOwnsCum(akHost, orgasmer)
        Return
    EndIf
    _WriteCumState(akHost, target, asArea, "ocum")
    _FireCumCue(akHost, orgasmer, target, asArea)
EndFunction

; : location-variant dispatch (cum-effects v2 item 2, in-script Area
; dispatch per the  scout shape). One phrase per OCum Area literal --
; the OCumMaleScript.psc ApplyCum dispatch class (L323-343, [035.00002]):
; 11 literals (belly/butt/chest/face/feet/hands/mouth/rectum/thighs/throat/
; vagina). : phrases are the USER-EDITED WORDING OF RECORD (register
; entry 18 CLOSED at  -- user edits applied verbatim in the fork
; register copy, provenance: fork docs/pending-approvals.md L442-453,
; 2026-10-16 15:52).
; Returns "" for unknown/empty Area -> the caller falls back to the v1 wording.
;  (2026-10-18, register entry 18 RE-RULING, user-edited this
; exchange): the 11 literals now carry the RECEIVER's name ({{receiver}} =
; target.GetDisplayName(); akTarget param added -- wording plumbing only);
; the base sentence's "finishing all over {{receiver}}" class is REMOVED
; (receiver naming deferred to the literals); the unified example is the
; ONLY phrasing regardless of source framework (no OCum/SL mentions).
; Discrepancy repairs of record: literal 1's register text carried a stale
; "B" placeholder -- applied as {{receiver}} per the set's own convention;
; literal 3's "(chest if male)" is a user ANNOTATION, implemented as a
; receiver-sex wording selection (breasts/chest), not literal text.
; SL LEG LIMIT (stated): the StageEnd proxy has no Area signal and passes ""
; -- location-agnostic until the v2 state layer exists.
String Function _LocationPhrase(String asArea, Actor akTarget = None) Global
    String t = ""
    If akTarget
        t = akTarget.GetDisplayName()
    EndIf
    If asArea == "belly"
        Return "the cum splatters across " + t + "'s belly in thick ropes"
    ElseIf asArea == "butt"
        Return "the cum pumps across " + t + "'s ass, basting them with thick globules"
    ElseIf asArea == "chest"
        If akTarget && SkyrimNet_BakaIntegration._SexOf(akTarget) == 0
            Return "the cum pumps across " + t + "'s chest, trickling sluggishly down their chest"
        EndIf
        Return "the cum pumps across " + t + "'s chest, trickling sluggishly down their breasts"
    ElseIf asArea == "face"
        Return "the cum shoots across " + t + "'s face in thick ropes"
    ElseIf asArea == "feet"
        Return "the cum gushes over " + t + "'s feet"
    ElseIf asArea == "hands"
        Return "the cum pumps out all over " + t + "'s hands"
    ElseIf asArea == "mouth"
        Return t + "'s mouth floods with jets of hot cum"
    ElseIf asArea == "rectum"
        Return "load after load of cum pumps deep into " + t + "'s ass"
    ElseIf asArea == "thighs"
        Return "the mess settling across " + t + "'s thighs"
    ElseIf asArea == "throat"
        Return "gouts of hot cum pump directly down " + t + "'s throat"
    ElseIf asArea == "vagina"
        Return "hot, thick cum is pumped deep into " + t + "'s pussy"
    EndIf
    Return ""
EndFunction

; : shared event-level source enforcement (ownership ruling of record:
; our lane = male/futa-source applications; SN-SexLab keeps female-source ones
; entirely -- no cue, no state write, no ambient debt). Validated against the
; EVENT'S OWN payload source (P+ SourceRef / OCum Orgasmer -- both per-event,
; verified against the senders), not the thread's resolved male. Interim
; actor-model rule unchanged from : male = _SexOf==0 (leveled-safe
; ActorBase->GetSex, motherboard L727); the SL futa signal (_sex==4) stays
; unrecoverable from a plain ActorBase here (futa honesty limit, ).
; Returns True (no log) on a valid source; False with the ownership sentinel
; on a female non-futa source. None sources return False silently (the
; reconciliation leg's honest-skip case -- handled by its own logging).
Bool Function _EventSourceOwnsCum(SkyrimNet_BakaIntegration akHost, Actor akSource) Global
    If akSource && SkyrimNet_BakaIntegration._SexOf(akSource) == 0
        Return True
    EndIf
    If akSource
        akHost._Log("[SNBaka] female-source event declined (SN-SL lane) (REV-126): source=" + akSource.GetDisplayName())
    EndIf
    Return False
EndFunction

; : shared outbound leg for both OCum events (was inline in the  handler).
; Shared 15s cum-cue cooldown (with the SL proxy) -- HJ/FJ scenes loop over multiple
; givers and multi-fire; one narrator cue per 15s. Cooldown behavior is IDENTICAL to
;  (same key, same window, same write point) -- only the call shape changed.
; : MOVED VERBATIM from the motherboard's _FireCumCue.
; : asArea param added (location-variant wording; "" = fallback). The
; v1 dedupe/cooldown is UNTOUCHED; unknown areas and the no-target legs keep
; the v1 wording verbatim.
Function _FireCumCue(SkyrimNet_BakaIntegration akHost, Actor orgasmer, Actor target, String asArea = "") Global
    ;  SOURCE-VALIDATION (register entry 19 note of record, user-edited:
    ; the location wordings "only make sense for male or futa characters
    ; cumming with/in/on a partner"). Interim actor-model rule: the SOURCE of a
    ; cum cue must be male (_SexOf==0, the repo's leveled-safe ActorBase ->
    ; GetSex precedent, motherboard L727). FUTA HONESTY (v1 limit): SexLab's
    ; futa signal (_sex==4) lives inside SL's internal gender model and is not
    ; recoverable from a plain ActorBase GetSex() here; OCum/P+ female sources
    ; are skipped. Futa handling = polish note (cum-effects.md ).
    ; : BACKSTOP ONLY -- every caller now validates the event's own
    ; source BEFORE its state write (entry-point enforcement), so a decline
    ; here means a path was missed (or the reconciliation leg's honest None).
    ; The sentinel is the  ownership wording (state: declined events
    ; write nothing upstream).
    If !orgasmer || SkyrimNet_BakaIntegration._SexOf(orgasmer) != 0
        akHost._Log("[SNBaka] _FireCumCue: female-source event declined (SN-SL lane) (REV-126 backstop)")
        Return
    EndIf
    Float nowRT = Utility.GetCurrentRealTime()
    If nowRT - StorageUtil.GetFloatValue(None, "SNBaka.LastCumCueRT", -999.0) < 15.0
        akHost._Log("[SNBaka] _FireCumCue: cue suppressed (shared 15s cum-cue cooldown)")
        Return
    EndIf
    StorageUtil.SetFloatValue(None, "SNBaka.LastCumCueRT", nowRT)
    String locPhrase = _LocationPhrase(asArea, target)
    If locPhrase
        akHost._Log("[SNBaka] _FireCumCue: location variant area=" + asArea)
    EndIf
    ;  (register entry 18 re-ruling + unified-only note, user-edited
    ; 2026-10-18): base sentence is "{{giver}} just came," and the literal
    ; carries the receiver; the "finishing all over X" class is REMOVED;
    ; the unified phrasing is the ONLY option regardless of source framework
    ; -- both mode branches produce the identical unified text (the MCM mode
    ; toggle no longer changes cue wording).
    String desc
    If akHost.iCumCueMode == 1
        ; per-source mode -- wording UNIFIED per the user's ruling ()
        If target
            If locPhrase
                desc = orgasmer.GetDisplayName() + " just came, " + locPhrase + "."
            Else
                desc = orgasmer.GetDisplayName() + " just came."
            EndIf
        Else
            desc = orgasmer.GetDisplayName() + " just came."
        EndIf
    Else
        ; unified (framework-neutral) wording -- wording of record 
        If target
            If locPhrase
                desc = orgasmer.GetDisplayName() + " just came, " + locPhrase + "."
            Else
                desc = orgasmer.GetDisplayName() + " just came."
            EndIf
        Else
            desc = orgasmer.GetDisplayName() + " just came."
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
    ;  instrumentation (report-only; PROJECT_STATE 125 open item):
    ; entry receipt BEFORE the gate chain + a named per-gate trace, so
    ; "HookStageEnd never delivered" is distinguishable from "delivered but
    ; gated off" and from "gated off by WHICH gate". Log-only; zero behavior
    ; change -- any behavior fix this evidence motivates is REPORTED, not
    ; shipped (session STOP rule).
    akHost._Log("[SNBaka] OnSLStageEnd: event RECEIVED thread=" + aiThreadID + " hasPlayer=" + abHasPlayer + " (REV-116 instrument)")
    If !akHost.bEnabled
        akHost._Log("[SNBaka] OnSLStageEnd: returned at gate -- bEnabled=false (REV-116 instrument)")
        Return
    EndIf
    If !akHost.bCumDetectionEnabled
        akHost._Log("[SNBaka] OnSLStageEnd: returned at gate -- bCumDetectionEnabled=false (REV-116 instrument)")
        Return
    EndIf
    If !akHost.bSLProxyEnabled
        akHost._Log("[SNBaka] OnSLStageEnd: returned at gate -- bSLProxyEnabled=false (REV-116 instrument)")
        Return
    EndIf
    If !SkyrimNet_BakaSL.Installed()
        akHost._Log("[SNBaka] OnSLStageEnd: returned at gate -- BakaSL.Installed()=false (REV-116 instrument)")
        Return
    EndIf
    Int threadID = aiThreadID
    If threadID < 0
        akHost._Log("[SNBaka] OnSLStageEnd: returned -- threadID=" + threadID + " negative (REV-116 instrument)")
        Return
    EndIf
    Actor[] positions = SkyrimNet_BakaSL.SLThreadPositions(threadID)
    If !positions || positions.Length == 0
        akHost._Log("[SNBaka] OnSLStageEnd: thread=" + threadID + " hasPlayer=" + abHasPlayer + " -- no positions resolved, skipping")
        Return
    EndIf
    Actor lead = positions[0]
    ;  cum-v2 PROXY DEMOTION (v2-map of record, cum-effects.md ):
    ; before the fallback wording, try keyword reconciliation per-position -- the
    ; vanilla-SL location signal (AddCum combo-spell keywords readable post-hoc).
    ; First position with a location wins (V > A > O priority inside the check);
    ; a hit fires the LOCATION-variant cue + per-target state write, and the
    ; proxy wording is skipped. Reconciliation runs ONLY when the P+ listener
    ; did not already cover this orgasm (P+ fires SexLabApplyCumFX directly;
    ; on P+ the keywords are also readable, but double-cueing is avoided by the
    ; shared 15s cooldown and the direct listener's earlier write -- so the
    ; reconciliation pass runs to fill the state layer when the cue was
    ; suppressed, not to double-fire narration).
    ;  D2 FIX: the reconciliation leg's SOURCE is the thread's actual
    ; source actor, NOT the lead.  passed lead = positions[0] = the
    ; female WEARER (Hroki) while the actual source (Hadrian, P+ payload-proven)
    ; went unexamined -> every reconciled cue hit source-invalid ( D2
    ; receipts, 5 across both loads). Resolution path: the P+ listener carries
    ; the payload's source directly (it fires first and its state write precedes
    ; this pass); this pass resolves the source from the thread itself per the
    ; interim actor-model rule -- the first male position (_SexOf==0), else None
    ; (honest skip inside _FireCumCue: the state write above stands, the cue is
    ; simply not misattributed to the wearer).
    ;  note: the per-target state write on this leg is legitimate under
    ; the ownership ruling even when the resolved source is None -- SL's own
    ; ApplyCumFX gating (sslActorAlias.psc L921-923, male/futa sources only)
    ; means a Cum keyword present on a position PROVES a male/futa-source
    ; application; the None case is a resolution miss, not a female-source event.
    Actor srcActor = _ResolveThreadSource(positions)
    Int p = 0
    While p < positions.Length
        Actor pos = positions[p]
        If pos
            String kloc = _SLKeywordLocation(pos)
            If kloc
                _WriteCumState(akHost, pos, kloc, "sexlab_vanilla")
                ; cue: location-variant via the shared fire path (15s cooldown applies)
                _FireCumCue(akHost, srcActor, pos, kloc)
                akHost._Log("[SNBaka] OnSLStageEnd: thread=" + threadID + " position=" + pos.GetDisplayName() + " keyword-reconciled location=" + kloc + " (proxy wording skipped)")
                Return
            EndIf
        EndIf
        p += 1
    EndWhile
    ;  D3 FIX: the cooldown stamp is FIRE-ONLY on this path too. 
    ; stamped SNBaka.LastCumCueRT BEFORE the source check, so keywordless
    ; mid-scene stage-ends ate the shared 15s window and both legitimate P+
    ; cues died on "cue suppressed" ( D3 receipts). Order is now:
    ; source-validation -> cooldown gate -> stamp -> fire. Suppressed/skipped
    ; stage-end passes never touch the window. (Verified same-order in
    ; _FireCumCue: both returns precede its stamp.)
    ;  source-validation,  wording: the proxy's lead actor is the
    ; resolved source; female non-futa lead -> declined (SN-SL lane -- no cue;
    ; no state was written on this fallback path).
    If !lead || SkyrimNet_BakaIntegration._SexOf(lead) != 0
        akHost._Log("[SNBaka] OnSLStageEnd: female-source event declined (SN-SL lane) (REV-126)")
        Return
    EndIf
    ; Shared 15s cum-cue cooldown (see _FireCumCue).
    Float nowRT = Utility.GetCurrentRealTime()
    If nowRT - StorageUtil.GetFloatValue(None, "SNBaka.LastCumCueRT", -999.0) < 15.0
        Return
    EndIf
    StorageUtil.SetFloatValue(None, "SNBaka.LastCumCueRT", nowRT)
    String desc
    If akHost.iCumCueMode == 1
        ; per-source mode -- wording UNIFIED per the  ruling
        desc = lead.GetDisplayName() + " just came."
    Else
        ; unified (framework-neutral) wording -- wording of record 
        desc = lead.GetDisplayName() + " just came."
    EndIf
    akHost._Log("[SNBaka] OnSLStageEnd: thread=" + threadID + " lead=" + lead.GetDisplayName() + " -> sdb_cum_applied (SL proxy)")
    SkyrimNetApi.RegisterEvent("sdb_cum_applied", desc, lead, None)
EndFunction

;  D2: source resolution for the keyword-reconciliation leg (caller
; HandleSLStageEnd). Interim actor-model rule of record: the SOURCE is the
; first male position in the thread (_SexOf==0, the motherboard L727 leveled-
; safe ActorBase -> GetSex precedent). No male position -> None -> the cue is
; skipped honestly inside _FireCumCue (the per-target state write above the
; call still stands); the cue is never misattributed to the wearer/lead.
Actor Function _ResolveThreadSource(Actor[] akPositions) Global
    Int i = 0
    While i < akPositions.Length
        Actor a = akPositions[i]
        If a && SkyrimNet_BakaIntegration._SexOf(a) == 0
            Return a
        EndIf
        i += 1
    EndWhile
    Return None
EndFunction

; ---- : SL-SIDE LOCATION SIGNALS (cum-v2 wiring,  v2-map rows) ----
; Two flavors, both now location-capable (the v1 "location-agnostic SL" note is
; superseded -- / v2-map of record):
;   P+ (version >= 20000, BakaSL._PplusDetected==1): push-time signal -- the
;     SexLabApplyCumFX ModEvent (sslThreadModel.psc L2234-2238, PPLUS V2.18.1:
;     PushForm(TargetRef), PushForm(SourceRef), PushInt(aiType)). aiType from
;     sslActorLibrary: FX_VAGINAL=0, FX_ANAL=1, FX_ORAL=2. Vanilla 1.66b never
;     sends this event (0 ApplyCumFX hits in its tree -- listener idles there).
;   vanilla SL (base AE): KEYWORD-RECONCILIATION signal -- the AddCum combo
;     spells carry Cum{Vaginal,Oral,Anal}Keyword MagicEffect keywords on the
;     TARGET (readable post-hoc via HasMagicEffectWithKeyword), checked at cue
;     time from the stage-end proxy. Keywords resolve through SexLabFramework
;     .Config (sslSystemConfig) -- present on BOTH flavors (v166b L102-104,
;     PPLUS L2023-2033).
; The stage-end proxy DEMOTES to last-resort fallback: HandleSLStageEnd now
; tries, in order, P+/vanilla reconciliation (location-capable cue + state
; write per-position); the proxy wording fires only when reconciliation yields
; nothing (or is disabled -- bSLProxyEnabled still gates the whole SL leg).

; P+ listener: HandleSLApplyCumFX receives (TargetRef, SourceRef, aiType).
; Gated like every detection handler; idles harmlessly on vanilla SL.
Function HandleSLApplyCumFX(SkyrimNet_BakaIntegration akHost, Form akTarget, Form akSource, Int aiType) Global
    If !akHost.bEnabled || !akHost.bCumDetectionEnabled || !SkyrimNet_BakaSL.Installed()
        Return
    EndIf
    If SkyrimNet_BakaSL._PplusDetected() != 1
        Return    ; vanilla never sends it; a stray delivery on vanilla is ignored
    EndIf
    Actor target = akTarget as Actor
    Actor source = akSource as Actor
    If !target || !source
        Return
    EndIf
    String loc = ""
    If aiType == 0
        loc = "vagina"
    ElseIf aiType == 1
        loc = "rectum"
    ElseIf aiType == 2
        loc = "mouth"
    EndIf
    akHost._Log("[SNBaka] OnSLApplyCumFX [P+]: source=" + source.GetDisplayName() + " target=" + target.GetDisplayName() + " aiType=" + aiType + " -> " + loc)
    ;  EVENT-LEVEL SOURCE ENFORCEMENT: validate the EVENT'S OWN SourceRef
    ; (the ModEvent payload, sslThreadModel.psc L2234-2238 -- not the thread's
    ; resolved male). SL itself only fires ApplyCumFX for male/futa sources
    ; (sslActorAlias.psc L921-923, _sex != 1 && _sex != 4), so this is
    ; defense-in-depth against a stray/foreign delivery -- but a female-source
    ; event is declined here too: cue AND state write (SN-SL lane).
    If !_EventSourceOwnsCum(akHost, source)
        Return
    EndIf
    _WriteCumState(akHost, target, loc, "sexlab_pplus")
    _FireCumCue(akHost, source, target, loc)
EndFunction

; Vanilla keyword reconciliation: returns the SL FX-domain location literal for
; akTarget if a Cum keyword effect is present, "" otherwise. Priority V > A > O
; mirrors sslActorLibrary.ApplyCumFX's own dispatch priority.
String Function _SLKeywordLocation(Actor akTarget) Global
    SexLabFramework sl = SkyrimNet_BakaSL._SL()
    If !sl || !sl.Config || !akTarget
        Return ""
    EndIf
    If sl.Config.CumVaginalKeyword && akTarget.HasMagicEffectWithKeyword(sl.Config.CumVaginalKeyword)
        Return "vagina"
    EndIf
    If sl.Config.CumAnalKeyword && akTarget.HasMagicEffectWithKeyword(sl.Config.CumAnalKeyword)
        Return "rectum"
    EndIf
    If sl.Config.CumOralKeyword && akTarget.HasMagicEffectWithKeyword(sl.Config.CumOralKeyword)
        Return "mouth"
    EndIf
    Return ""
EndFunction

; ---- : CUM APPLIANCE AUTHORITY (visual drive + maintenance) ----
; Tier matrix of record (header + cum-effects.md ). asLocation is our
; FX-domain literal ("vagina"|"rectum"|"mouth"). No drive call when the
; location is unknown or the source is the SL proxy (proxy never claims
; overlay application) -- state-only, documented degradation.
;  Task 2.1 (ruled): the appliance is tiered BY SCENE SOURCE, not by
; install order. OCum-source scenes (OStim/OCum events) use the OCum appliance;
; SL/P+ scenes use the SL overlay appliance (sl.ActorLib.AddCum combo spells).
; SLACS inventory note (2.2 ruling: resolved by what the decals actually
; draw): SLACS_2_SCO_v079_5 is a TEXTURE REPLACER -- verified present in the
; LoreRim modlist (build-time receipt, rev133c_presence.txt) -- it overrides
; the textures the SAME AddCum combo spells draw, so no runtime detection is
; needed or possible; base SL textures render when it is absent. Replace-
; not-stack is now SYMMETRIC: whichever appliance takes ownership drops the
; other system's visual first (OCum clean when SLACS takes over; SLACS
; ClearCum when OCum takes over). Maintenance re-drives never re-call SLACS
; AddCum (it ESCALATES the texture tier 1->2 on an already-cummed actor).
Function _ApplyCumVisual(Actor akTarget, String asLocation, String asSource) Global
    If !akTarget || !asLocation
        Return    ; state-only degradation (no location -> no overlay claim)
    EndIf
    ; ---- OCum lane: OCum-source scenes (and any OCum re-drive) ----
    If asSource == "ocum"
        If Installed()
            OCumMaleScript male = _OCumMale()
            If male
                ; OCumMaleScript.psc L303-345 (GPL -- cited, not copied): the
                ; generic entry; Area is a String argument dispatched to
                ; per-area overlay application (CumOntoArea L523-536).
                ; ThreadID=0 = the out-of-scene path. Re-emits ocum_applied_cum
                ; (L316) -> our own handler re-writes state source as "ocum"
                ; and the cue double-fire is eaten by the shared 15s window.
                ; : area routed through _LocationNoun (our literals ->
                ; OCum's own nouns; OCum's own nouns pass through unchanged).
                String ocumArea = _LocationNoun(asLocation)
                If ocumArea == ""
                    ocumArea = asLocation
                EndIf
                male.ApplyCum(akTarget, akTarget, ocumArea, 1, 1.0, "", 0)
                Return
            EndIf
        EndIf
        ; OCum lane degraded (OCum absent or quest unresolvable): fall
        ; through to the SLACS lane below -- documented degradation.
    EndIf
    ; ---- SLACS lane: SL/P+ scenes (the SL overlay appliance) ----
    If SkyrimNet_BakaSL.Installed()
        SexLabFramework sl = SkyrimNet_BakaSL._SL()
        If sl && sl.ActorLib
            ; sslActorLibrary PPLUS L805/L834: AddCum(Actor, Vaginal, Oral,
            ; Anal) -- bool flags per area, spells persist-until-dispelled.
            ; : throat resolves to the ORAL decal (the SLACS
            ; inventory question -- resolved by what the decals actually
            ; draw: the combo spells have exactly three flags).
            ;  GUARD: an area outside the three flags (face/belly/
            ; butt/thighs/chest/hands...) is a VISUAL NO-OP here -- and must
            ; ALSO skip the replace-not-stack clear below (a no-op that
            ; strips the OCum visual without drawing anything is NOT an
            ; honest drive). State-only, named, never silently dropped.
            Bool flagVag = asLocation == "vagina"
            Bool flagOral = asLocation == "mouth" || asLocation == "throat"
            Bool flagAnal = asLocation == "rectum" || asLocation == "ass"
            If flagVag || flagOral || flagAnal
                ; Replace-not-stack (symmetric): if OCum textures are on the
                ; wearer (stack case), drop them first -- SLACS becomes the sole
                ; visual authority for SL scenes ( matrix).
                If Installed()
                    OCumScript main = _OCumMain()
                    If main
                        main.CleanCumTexturesFromActor(akTarget)
                    EndIf
                EndIf
                sl.ActorLib.AddCum(akTarget, flagVag, flagOral, flagAnal)
            EndIf
        EndIf
        ; SL present but ActorLib unresolvable: state-only degradation.
        Return
    EndIf
    ; ---- SL absent: OCum fallback appliance (documented degradation) ----
    If Installed()
        OCumMaleScript male = _OCumMale()
        If male
            String ocumArea = _LocationNoun(asLocation)
            If ocumArea == ""
                ocumArea = asLocation
            EndIf
            male.ApplyCum(akTarget, akTarget, ocumArea, 1, 1.0, "", 0)
        EndIf
    EndIf
    ; ---- Neither framework -> state-only (documented degradation) ----
EndFunction

; Tier removal: clears BOTH systems' visuals. Used by expiry and the 600s
; failsafe (the failsafe must not orphan the visual past lifetime).
Function _ClearCumVisual(Actor akTarget) Global
    If !akTarget
        Return
    EndIf
    If Installed()
        OCumScript main = _OCumMain()
        If main
            main.CleanCumTexturesFromActor(akTarget)    ; OCumScript.psc (cited)
        EndIf
    EndIf
    If SkyrimNet_BakaSL.Installed()
        SexLabFramework sl = SkyrimNet_BakaSL._SL()
        If sl && sl.ActorLib
            sl.ActorLib.ClearCum(akTarget)
        EndIf
    EndIf
EndFunction

; Runtime quest resolvers -- QUST EDIDs byte-confirmed in OCum.esp; no
; hardcoded formIDs (Quest.GetQuest is the EDID path).
OCumScript Function _OCumMain() Global
    Return Quest.GetQuest("OCumQuest") as OCumScript
EndFunction

;  Task 2.3, leg 2: BATH-COMPLETION CLEAR (SLACS-2's DnB_CleanActorDirt,
; the 1-Form-push ModEvent from Dirty_BathingQuest.PlayBatheAnimation L140-145
; -- source-verified in SLACS_2_SCO_v079_5\Scripts\Source). The state + visual
; clear TOGETHER; only the WEARER OF RECORD is affected (a bath by anyone else
; touches nothing -- the singular-wearer state model). Registration is
; presence-gated on the motherboard (Game.IsPluginInstalled("SLACS_2_Plus_SCO.esp")).
Function HandleBathClean(SkyrimNet_BakaIntegration akHost, Form akBathing) Global
    If !akHost.bEnabled || !akHost.bCumDetectionEnabled
        Return
    EndIf
    Actor wearer = StorageUtil.GetFormValue(None, "SNBaka.CumWearer", None) as Actor
    If !wearer || akBathing != (wearer as Form)
        Return    ; not the wearer of record: the bath touches no cum state
    EndIf
    akHost._Log("[SNBaka] DnB_CleanActorDirt: bath-completion clear (wearer=" + wearer.GetDisplayName() + ", visual + state, REV-133c)")
    _ClearCumVisual(wearer)
    DeDService.ClearActorState(wearer, "cum")
    StorageUtil.UnsetIntValue(wearer, "DeD_Cum_PromptShow")
    StorageUtil.UnsetFloatValue(wearer, "DeD_Cum_PromptShowUntil")
    StorageUtil.UnsetFloatValue(wearer, "DeD_Cum_PromptNextOpenRT")
    StorageUtil.StringListClear(wearer, "DeD_Cum_Locations")
    StorageUtil.UnsetFormValue(None, "SNBaka.CumWearer")
EndFunction

OCumMaleScript Function _OCumMale() Global
    Return Quest.GetQuest("OCumMaleQuest") as OCumMaleScript
EndFunction

; Ambient timer handler: sdb_cum_ambient_due arrives as the standard 4-slot
; ModEvent shape (eventName, strArg, numArg, sender) -- numArg 1 = failsafe
; expired, 0 = due tick. Scheduler.cpp emits with sender=None (rule ticks are
; not actor-addressed, L124/L149), so the wearer is recovered from the
;  cache (None-keyed StorageUtil form pointer, mirrored by the
; DeDService type-4 "cum.wearer" row) and the ambient cue stays subjectless.
;  REWRITE: the tick is now (in order) failsafe-clear -> expiry-clear
; -> maintenance refresh -> ambient cue. The failsafe used to be skip-only
; (/120) which orphaned the visual past lifetime.
Function HandleCumAmbientDue(SkyrimNet_BakaIntegration akHost, Float afNumArg, Form akSender) Global
    If !akHost.bEnabled || !akHost.bCumDetectionEnabled || !DeD_ServicePresent()
        Return
    EndIf
    Actor wearer = StorageUtil.GetFormValue(None, "SNBaka.CumWearer", None) as Actor
    If afNumArg >= 1.0
        ; 600s failsafe: rule starved/misarmed past its window -- clear BOTH
        ; the visual and the state (; was skip-only).
        akHost._Log("[SNBaka] sdb_cum_ambient_due: failsafe-expired tick (numArg=" + afNumArg + ") -- clearing visual + state (REV-122)")
        If wearer
            _ClearCumVisual(wearer)
            DeDService.ClearActorState(wearer, "cum")
            ; : windowing keys ride the same clear (else a stale
            ; show flag survives the state clear into the next marked period).
            StorageUtil.UnsetIntValue(wearer, "DeD_Cum_PromptShow")
            StorageUtil.UnsetFloatValue(wearer, "DeD_Cum_PromptShowUntil")
            StorageUtil.UnsetFloatValue(wearer, "DeD_Cum_PromptNextOpenRT")
            ; : the accumulated location set rides the same clear.
            StorageUtil.StringListClear(wearer, "DeD_Cum_Locations")
        EndIf
        StorageUtil.UnsetFormValue(None, "SNBaka.CumWearer")
        Return
    EndIf
    If !wearer
        Return    ; nothing cached: no state to maintain (or pre- state)
    EndIf
    ;  Task 2.3 (ruled): BATH/WATER CLEARING, leg 1 -- SWIMMING.
    ; Swimming = full immersion -- the visual + state clear TOGETHER on the
    ; next ambient tick (swimming-only degradation; no timer chain of its
    ; own). Leg 2 -- the bath-completion surface -- is the presence-gated
    ; DnB_CleanActorDirt listener (HandleBathClean below; SLACS-2 verified
    ; installed: SLACS_2_Plus_SCO.esp). BiS Renewed's own quest is NOT in
    ; the LoreRim modlist (the SLACS-2 quest is the same surface family and
    ; IS the one present) -- the listener never fires if the plugin is absent.
    If wearer.IsSwimming()
        akHost._Log("[SNBaka] sdb_cum_ambient_due: wearer swimming -- bath clear, visual + state (REV-133c)")
        _ClearCumVisual(wearer)
        DeDService.ClearActorState(wearer, "cum")
        StorageUtil.UnsetIntValue(wearer, "DeD_Cum_PromptShow")
        StorageUtil.UnsetFloatValue(wearer, "DeD_Cum_PromptShowUntil")
        StorageUtil.UnsetFloatValue(wearer, "DeD_Cum_PromptNextOpenRT")
        StorageUtil.StringListClear(wearer, "DeD_Cum_Locations")
        StorageUtil.UnsetFormValue(None, "SNBaka.CumWearer")
        Return
    EndIf
    ; Expiry: lifetime clock (cum.expires_rt, refreshed by every application
    ; signal) -- clear BOTH systems' visuals + the state, drop the cache.
    If Utility.GetCurrentRealTime() >= DeDService.GetStateFloat(wearer, "cum.expires_rt", 0.0)
        akHost._Log("[SNBaka] sdb_cum_ambient_due: cum lifetime expired (wearer=" + wearer.GetDisplayName() + ") -- clearing visual + state (REV-122)")
        _ClearCumVisual(wearer)
        DeDService.ClearActorState(wearer, "cum")
        ; : windowing keys ride the same clear (see failsafe leg).
        StorageUtil.UnsetIntValue(wearer, "DeD_Cum_PromptShow")
        StorageUtil.UnsetFloatValue(wearer, "DeD_Cum_PromptShowUntil")
        StorageUtil.UnsetFloatValue(wearer, "DeD_Cum_PromptNextOpenRT")
        ; : the accumulated location set rides the same clear.
        StorageUtil.StringListClear(wearer, "DeD_Cum_Locations")
        StorageUtil.UnsetFormValue(None, "SNBaka.CumWearer")
        Return
    EndIf
    ; Maintenance refresh: keep the visual authoritative for the remaining
    ; lifetime. OCum tier: recast OCumSpell on the wearer -- their own cleanup
    ; timer (MCM default 5min) is SHORTER than our 10-min lifetime; the recast
    ; resets its duration so OnEffectFinish never cleans early (their own
    ; in-scene re-cast pattern, OCumEffect.psc L12). SLACS tier: nothing to do
    ; (persist-until-dispelled; re-calling AddCum would ESCALATE the texture
    ; tier -- never done). State-only tier: nothing to do.
    String src = DeDService.GetStateString(wearer, "cum.last_source", "")
    If src == "ocum" && Installed()
        OCumMaleScript male = _OCumMale()
        If male && male.OCumSpell
            male.OCumSpell.Cast(wearer)
        Else
            OCumScript main = _OCumMain()
            If main && main.OCumSpell
                main.OCumSpell.Cast(wearer)
            EndIf
        EndIf
    EndIf
    ; : windowing advance (cum-prompt-spec.md .1): ~1 min open per
    ; ~10 min of marked time (the 0171 SADirt_PromptShow precedent). Tick
    ; logic: inside the open window -> show=1; window closed -> show=0 and arm
    ; the next open at +9 min; next-open due -> reopen for 60s. Every
    ; application REOPENS immediately (_WriteCumState) so state updates land.
    Float winNow = Utility.GetCurrentRealTime()
    Float winShowUntil = StorageUtil.GetFloatValue(wearer, "DeD_Cum_PromptShowUntil", 0.0)
    Float winNextOpen = StorageUtil.GetFloatValue(wearer, "DeD_Cum_PromptNextOpenRT", 0.0)
    If winNow < winShowUntil
        StorageUtil.SetIntValue(wearer, "DeD_Cum_PromptShow", 1)
    ElseIf winNextOpen > 0.0 && winNow >= winNextOpen
        StorageUtil.SetFloatValue(wearer, "DeD_Cum_PromptShowUntil", winNow + 60.0)
        StorageUtil.SetFloatValue(wearer, "DeD_Cum_PromptNextOpenRT", 0.0)
        StorageUtil.SetIntValue(wearer, "DeD_Cum_PromptShow", 1)
    Else
        If winNextOpen == 0.0
            StorageUtil.SetFloatValue(wearer, "DeD_Cum_PromptNextOpenRT", winNow + 540.0)
        EndIf
        StorageUtil.SetIntValue(wearer, "DeD_Cum_PromptShow", 0)
    EndIf
    ;  THE RESTORE (2026-10-20, the regression's fix): the ambient
    ; RegisterEvent call is RESTORED as the ONLY emission. The 
    ; conservative ruling's dependency read was INVERTED -- the
    ; misdiagnosis, on record, caught by the user's dogfood: the
    ; RegisterEvent call IS load-bearing (the trigger-engine's native bus
    ; entry, SkyrimNetApi.psc -- RegisterEvent(eventType, content,
    ; originatorActor, targetActor)), and the emitter-less yaml does NOT
    ; fire ('s own evidence; the orphan question answered by
    ; regression, not by SN-team follow-up). The restored shape is the
    ; design of record: P2 class -- trigger-bus semantics (waits its turn,
    ; merges, budget-counted; the Conversation_System doc's emission-class
    ; table) -- with NO DirectNarration machinery anywhere in the ambient
    ; chain (stays dead). The yaml (sdb_cum_ambient.yaml) is inert by this
    ; same evidence -- RETAINED verbatim as inert documentation (its
    ; response.content = the approved cue-guidance text; non-role recorded
    ; in cum-effects.md  + PROJECT_STATE ).
    ; Ambient cue (unchanged  behavior): sender=None -> subjectless;
    ; the narrator applies it to whoever the moment fits.
    Actor narrTarget = akSender as Actor
    ;  (Task 3.1, cum-prompt-spec.md s9): the ambient cue is
    ; PRE-SHAPED per-fire in Papyrus from the phrase pieces -- wearer-naming,
    ; freshness-banded (<600 fresh / <3600 dried / else faded -- the 0175 band
    ; matrix of record), location-aware (the accumulated set, plain-English
    ; join) -- ALL PLAIN TEXT, zero template syntax, so it cannot inherit the
    ; beta-28 response-content render failure class (the .cpp:372 receipts).
    ; Wording posture: the "Nearby characters notice that ..." prefix is
    ; register entry 19's ruled wording of record (kept verbatim); the
    ; name/freshness/location insertions are STRATEGIST DRAFT and ride the
    ; entry-26 batch (the user rules the phrase family once). The subjectless
    ; base (entry 19 verbatim, "someone is covered in cum ...") remains the
    ; no-wearer / no-pieces fallback -- the ruled text is always reachable.
    String desc = _AmbientDesc(wearer)
    akHost._Log("[SNBaka] sdb_cum_ambient_due: ambient cue fired (sender=" + akSender + "; maintenance pass done, src=" + src + "; emission restored )")
    SkyrimNetApi.RegisterEvent("sdb_cum_ambient", desc, narrTarget, None)
    ;  (user-ruled dogfood 2026-10-21): Follow-up Prompt -- the direct
    ; narration is now a SEPARATE, MCM-gated surface. The narration yaml
    ; (sdb_cum_ambient_narr.yaml, register entry-22 ruled text verbatim) matches
    ; the sdb_cum_ambient_narr event type ONLY, so the cue (mandatory, above)
    ; and the narration (optional, Cum Effects MCM "Follow-up Prompt") are
    ; fully separable. Default OFF = cue-only, per the  anatomy
    ; verdict; the stale overwrite-overlay sdb_cum_ambient.yaml that kept
    ; narrating un-gated after that verdict was the live leg of this fix
    ; (deleted from the modlist overlay this rev). The follow-up event's own
    ; desc is a plain marker (the rendered text lives in the yaml).
    If akHost.bCumFollowUpNarration
        akHost._Log("[SNBaka] sdb_cum_ambient_due: follow-up prompt ON -- narration event fired (REV-134f)")
        SkyrimNetApi.RegisterEvent("sdb_cum_ambient_narr", "[sdb_cum_ambient_narr] Follow-up narration moment for the ambient cum cue.", narrTarget, None)
    EndIf
EndFunction

; ---- : THE PRE-SHAPED AMBIENT (Task 3.1; entry-26 phrase batch) ----
; Plain-text phrase pieces composed per-fire. Location nouns (the bio
; fragment's s9 table mirrored ONE-WORD-CLASS-SIMPLER for the one-line cue):
; a body-place noun per location key; unknown keys contribute nothing (the
; freshness phrase still lands). Freshness bands = the 0175 matrix of record.
String Function _LocationNoun(String asArea) Global
    If asArea == "belly"
        Return "belly"
    ElseIf asArea == "butt"
        Return "ass"
    ElseIf asArea == "chest"
        Return "chest"
    ElseIf asArea == "face"
        Return "face"
    ElseIf asArea == "feet"
        Return "feet"
    ElseIf asArea == "hands"
        Return "hands"
    ElseIf asArea == "mouth"
        Return "mouth"
    ElseIf asArea == "rectum"
        Return "ass"
    ElseIf asArea == "thighs"
        Return "thighs"
    ElseIf asArea == "throat"
        Return "throat"
    ElseIf asArea == "vagina"
        Return "pussy"
    EndIf
    Return ""
EndFunction

String Function _AmbientDesc(Actor wearer) Global
    String base = "Nearby characters notice that someone is covered in cum from a recent sexual encounter."
    If !wearer
        Return base
    EndIf
    String nm = wearer.GetDisplayName()
    If nm == ""
        Return base
    EndIf
    ; Location pieces: plain-English join over the accumulated set (;
    ; dedupe by noun so butt/rectum collapse, order = recency).
    String pieces = ""
    Int nLoc = StorageUtil.StringListCount(wearer, "DeD_Cum_Locations")
    Int iLoc = 0
    While iLoc < nLoc
        String noun = _LocationNoun(StorageUtil.StringListGet(wearer, "DeD_Cum_Locations", iLoc))
        If noun != "" && StringUtil.Find(pieces, noun) < 0
            If pieces != ""
                pieces = pieces + ", "
            EndIf
            pieces = pieces + noun
        EndIf
        iLoc += 1
    EndWhile
    ; Freshness band (the 0175 matrix of record; applied_rt==0 = not-yet-set ->
    ; fresh band, the s9 null contract's never-null default).
    Float appliedRT = DeDService.GetStateFloat(wearer, "cum.last_applied_rt", 0.0)
    Int fresh = (Utility.GetCurrentRealTime() - appliedRT) as Int
    If fresh < 0
        fresh = 0
    EndIf
    String freshPhrase = ""
    If fresh < 600
        freshPhrase = "still fresh"
    ElseIf fresh < 3600
        freshPhrase = "dried"
    Else
        freshPhrase = "an old, faded residue"
    EndIf
    ; Composition: entry 19's ruled prefix shape ("Nearby characters notice
    ; that ..."), wearer-named, freshness-banded, location-aware tail.
    String desc = "Nearby characters notice that " + nm + " is covered in cum"
    If pieces != ""
        desc = desc + " on the " + pieces
    EndIf
    desc = desc + " from a recent sexual encounter"
    If freshPhrase == "still fresh"
        desc = desc + ", still fresh"
    ElseIf freshPhrase == "dried"
        desc = desc + ", now dried"
    Else
        desc = desc + ", an old faded residue now"
    EndIf
    desc = desc + "."
    Return desc
EndFunction

; ---- : get_ded_cum DECORATOR (module-owned;  1.1(a) as-built) ----
; Returns the WEARER-OF-RECORD cum facts as JSON for trigger response
; templates. Wearer-keyed: resolves the wearer regardless of the passed
; actor (the state layer carries a singular wearer), with "self" carrying
; the direction bit. Unmarked or expired world: {"present": false}.
; Consumers of record: the tick's RegisterEvent("sdb_cum_ambient") emission
; (RESTORED  -- the only fire source; P2 trigger-bus class) and the
; staged prompt fragments (0175/0520)
; (wearer-naming + freshness class; the documented originator_uuid arg).
; sdb_cum_ambient.yaml: INERT by the  regression evidence (an
; emitter-less yaml does not fire) -- retained verbatim as inert
; documentation only.
String Function GetDedCum(Actor akActor) Global
    Actor wearer = StorageUtil.GetFormValue(None, "SNBaka.CumWearer", None) as Actor
    If !wearer
        Return "{\"present\": false}"
    EndIf
    Float now = Utility.GetCurrentRealTime()
    Float expiresRT = DeDService.GetStateFloat(wearer, "cum.expires_rt", 0.0)
    If expiresRT > 0.0 && now >= expiresRT
        Return "{\"present\": false}"
    EndIf
    String wearerName = wearer.GetDisplayName()
    If wearerName == ""
        wearerName = "the cum soaked person"
    EndIf
    Bool isSelf = (akActor == wearer)
    String loc = DeDService.GetStateString(wearer, "cum.last_location", "")
    String src = DeDService.GetStateString(wearer, "cum.last_source", "")
    Float appliedRT = DeDService.GetStateFloat(wearer, "cum.last_applied_rt", 0.0)
    Int freshness = (now - appliedRT) as Int
    If freshness < 0
        freshness = 0
    EndIf
    Int expiresIn = (expiresRT - now) as Int
    ;  (the null contract, cum-prompt-spec.md s9): "locations" reads the
    ; ACCUMULATED DeD_Cum_Locations string list -- always a well-formed JSON
    ; array (possibly empty, never null), unique, recency-ordered, capped at 6.
    ; freshness_s is an Int >= 0 (never null; not-yet-set -> 0 = fresh band).
    ; source may be "" when a write path skipped the source arg (documented:
    ; "" = unknown source; fragments must not branch on it being non-empty).
    String locArr = "["
    Int nLoc = StorageUtil.StringListCount(wearer, "DeD_Cum_Locations")
    Int iLoc = 0
    While iLoc < nLoc
        If iLoc > 0
            locArr = locArr + ", "
        EndIf
        locArr = locArr + "\"" + StorageUtil.StringListGet(wearer, "DeD_Cum_Locations", iLoc) + "\""
        iLoc += 1
    EndWhile
    locArr = locArr + "]"
    String s = "{\"present\": true, \"wearer_name\": \"" + wearerName + "\", \"self\": " + isSelf
    s += ", \"locations\": " + locArr + ", \"source\": \"" + src + "\""
    s += ", \"applied_rt\": " + appliedRT + ", \"freshness_s\": " + freshness + ", \"expires_in_s\": " + expiresIn + "}"
    Return s
EndFunction

; ---- : get_ded_cum_any DECORATOR (module-owned companion; cum-prompt-spec.md .3) ----
; The witness-eligibility read: {"any": true, "nearest": "<name>"} when the
; wearer of record is marked, unexpired, and shares the observer's cell (or
; IS the observer); {"any": false} otherwise. Deliberately minimal -- rule
; operators get eligibility + the nearest name, never the full state JSON
; (the speaker/target rule, prompts-and-decorators.md L57, applies: the
; observer is always the actor in scope, compliant by construction).
String Function GetDedCumAny(Actor akObserver) Global
    Actor wearer = StorageUtil.GetFormValue(None, "SNBaka.CumWearer", None) as Actor
    If !wearer
        Return "{\"any\": false}"
    EndIf
    Float now = Utility.GetCurrentRealTime()
    Float expiresRT = DeDService.GetStateFloat(wearer, "cum.expires_rt", 0.0)
    If expiresRT > 0.0 && now >= expiresRT
        Return "{\"any\": false}"
    EndIf
    If akObserver != wearer
        If !akObserver || !wearer.GetParentCell() || akObserver.GetParentCell() != wearer.GetParentCell()
            Return "{\"any\": false}"
        EndIf
    EndIf
    String nearest = wearer.GetDisplayName()
    If nearest == ""
        nearest = "the cum soaked person"
    EndIf
    Return "{\"any\": true, \"nearest\": \"" + nearest + "\"}"
EndFunction

; ----  Task 1.2 (ruled 2026-10-20, rider 2.5b): THE AFTERMATH
; ---- RETIREMENT. The scene-end +10s hold chain ( Option A) is RETIRED
; ---- whole: this HandleSLAnimationEnd receipt + HandleAftermathDue below
; ---- are DELETED, the motherboard's _ArmCumAftermathHold/mux leg/listener
; ---- with them, and sdb_cum_aftermath.yaml removed from the layer. The
; ---- two-moment structure of record STANDS: application cue at climax (the
; ---- fact) + ambient at +60s (the room). Both retirements' reopening notes
; ---- live in cum-effects.md (room-too-quiet findings -> the delayed-ambient
; ---- design conversation).
