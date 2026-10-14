Scriptname SkyrimNet_BakaIntegration_MCM extends SKI_ConfigBase

SkyrimNet_BakaIntegration Property Main Auto

Int _enabledOID
Int _panicOID
Int _lapSitOID
Int _playerTargetOID
Int _femaleOnlyOID
Int _animatedTearsOID
Int _hugDurOID
Int _molestDurOID
Int _kissDurOID
Int _touchDurOID
Int _stageDurOID
Int _cooldownOID
Int _resistEnabledOID
Int _resistDifficultyOID
Int _npcEscapeChanceOID
Int _npcStageTimeOID
Int _escalationWindowOID
Int _escalationDifficultyOID
Int _spankPlayerOID
Int _spankMaleOID
Int _spankFurnitureOID
Int _spankTatIntensityOID
Int _spankHealFactorOID
Int _sexBackendOID
Int _expressionsOID
Int _exprIntensityOID
Int _creatureEscOID
Int _creatureOnPCOID
Int _creatureCombatOID
Int _creatureFollowerHitOID
Int _creatureSceneOID
Int _llmGateOID
Int _notifyOID
Int _debugLogOID
Int _creatureVictimSexOID
Int _creatureBackendOID
Int _creatureSuccessOID
Int _creatureHitChanceOID
Int _humanOnHitOID
Int _humanHitChanceOID
Int _escapeGraceOID
Int _creatureStruggleDurOID
Int _creatureGraceOID
Int _creatureGroupSizeOID
Int _sellSlaveryOID
Int _followerSlaveryOID
Int _slaveryDistOID
Int _tiedHoursOID
;  detection + inflation triggers (Plugins page)
Int _cumDetectOID
Int _slProxyOID
Int _fhuAwareOID
;  "Downed State (Acheron Bridge)" section (Plugins page) — consolidated from the
; bridge's own MCM. Settings stay in StorageUtil (player-keyed, same SNAcheron.* keys and
; defaults as the bridge MCM — no CK property link, no data migration; the bridge quest
; reads them each tick via _LoadSettings).
Int _achEnabledOID
Int _achCueOID
Int _achProxOID
Int _achConfirmOID
Int _achHandoffOID
Int _achGetUpKeyOID
Int _achEngageOID
Int _achDebugOID
;  "SlaveTats Degradation Sets" section (Plugins page) — SNBaka_SlaveTatsModule state
; (SNBaka.ST.* StorageUtil keys, player-keyed). Set section/name values are picked from the
; PrismaUI SlaveTats menu (SNSlaveTats_Menu view) rather than typed here; the MCM exposes
; the event toggles + Refresh + status, presence-gated like the other plugin sections.
Int _stEnabledOID
Int _stSpankOID
Int _stDefeatOID
Int _stEscalOID
Int _stRefreshOID
Int _stStatusOID
Int _stPickOID
;  Task 4 — color / release / observation additions (SNBaka.ST.* keys, module defaults).
Int _stDefaultColorOID
Int _stRemoveOnReleaseOID
Int _stObserveOID
;  Task 2.1 — Execute-gate MCM cycling option ("Execution Action Use", General page).
; Player-keyed StorageUtil key "SNBaka.ExecuteGateLevel": 0 = Unlimited (default, strategist-
; recommended + user-flagged for confirm in the  gate report), 1 = Companions ask,
; 2 = Always ask. Read directly via GetIntValue (same StorageUtil pattern as the SNAcheron.*
; options - no CK property link; Execute_Execute is the enforcement point).
Int _execGateOID

Event OnConfigInit()
    ModName = "Baka SkyrimNet"
    _BuildPages()
EndEvent

; SkyUI MCM quests DO reliably receive OnGameReload on every load — unlike a bare Quest, whose
; OnPlayerLoadGame never fires. So we use it to re-run the main quest's Setup() on every load, which
; re-asserts the decorator + mod-event registrations (RegisterForModEvent does NOT survive save/load).
; This is what makes the creature hand-off and the AEL/menu events work after a reload.
Event OnGameReload()
    Parent.OnGameReload()
    If Main
        Main.Setup()
    EndIf
EndEvent

; Bumped to 2 in v1.1 (added the "Scenes & FX" page), to 3 for the "Plugins" page (Lap Sitting).
; : bumped to 4 -- added the detection-trigger toggles (Cum Detection / FHU Inflation) to
; the EXISTING "Plugins" page. Version-field lesson (confirmed live, see rev notes above): an
; existing save keeps whatever Pages[]/_BuildPages state it last wrote UNLESS the version is
; bumped so SkyUI fires OnVersionUpdate. No NEW page this time, but new OPTIONS on an existing
; page still need the bump on existing saves (the page content is cached with the save too).
; : bumped to 5 -- the "Downed State (Acheron Bridge)" section was consolidated onto the
; Plugins page (the bridge's own standalone MCM quest remains in its esp but is superseded by
; this section). Same StorageUtil keys/defaults as the bridge MCM (SNAcheron.*, player-keyed) —
; NO data migration: a save that used the old MCM reads identical values here.
; : bumped to 6 -- the "SlaveTats Degradation Sets" section was added to the Plugins
; page (SNBaka_SlaveTatsModule state: SNBaka.ST.* StorageUtil keys, player-keyed, defaults
; set in the module). No data migration (new keys only).
; : bumped to 7 -- SlaveTats section gained the  options (module-wide default
; color, removal-on-release, ambient observation). No data migration (new keys only; the
; v7 marker distinguishes the crossing save for dogfood).
Int Function GetVersion()
    Return 7
EndFunction

Event OnVersionUpdate(Int aVersion)
    If aVersion < 5
        ;  consolidation marker (one-time, per-player): distinguishes a Hadrian-era save
        ; (pre-consolidation, bridge MCM era) that has been migrated onto the unified MCM from a
        ; fresh install. Deliberately NOT read by any code yet — it is the dogfood/headline probe
        ; key for the migration test (grep SNBaka.MCMConsolidated in Papyrus.0.log).
        StorageUtil.SetIntValue(Game.GetPlayer(), "SNBaka.MCMConsolidated", 5)
        Debug.Trace("[SNBaka] MCM v5: Acheron-bridge settings consolidated onto the Plugins page (SNBaka.MCMConsolidated=5 marker set)")
    EndIf
    If aVersion < 6
        ;  self-migration marker (one-time, per-player): distinguishes a save that crossed
        ; the SlaveTats-section rev from a fresh install. Dogfood probe (grep SNBaka.ST.MCMv6 in
        ; Papyrus.0.log); not read by code.
        StorageUtil.SetIntValue(Game.GetPlayer(), "SNBaka.ST.MCMv6", 1)
        Debug.Trace("[SNBaka] MCM v6: SlaveTats degradation-set section added to the Plugins page (SNBaka.ST.MCMv6=1 marker set)")
    EndIf
    If aVersion < 7
        ;  marker (one-time, per-player): SlaveTats section gained default-color /
        ; removal-on-release / observation options. Dogfood probe (grep SNBaka.ST.MCMv7).
        StorageUtil.SetIntValue(Game.GetPlayer(), "SNBaka.ST.MCMv7", 1)
        Debug.Trace("[SNBaka] MCM v7: SlaveTats REV-74 options added (SNBaka.ST.MCMv7=1 marker set)")
    EndIf
    _BuildPages()
EndEvent

Function _BuildPages()
    Pages    = new String[6]
    Pages[0] = "General"
    Pages[1] = "Timing"
    Pages[2] = "Resist"
    Pages[3] = "Spank"
    Pages[4] = "Scenes & FX"
    Pages[5] = "Plugins"
EndFunction

Event OnPageReset(String page)
    If page == "General"
        SetCursorFillMode(TOP_TO_BOTTOM)
        _enabledOID        = AddToggleOption("Enable Mod",            Main.bEnabled)
        _playerTargetOID   = AddToggleOption("Player Can Be Target",  Main.bPlayerCanBeTarget)
        _femaleOnlyOID     = AddMenuOption("Target Sex",   _targetSexName(Main.iTargetSex))
        _animatedTearsOID  = AddToggleOption("Animated Tears",        Main.bAnimatedTearsEnabled)
        _cooldownOID       = AddSliderOption("AI Action Cooldown",    Main.fNPCGlobalCooldown, "{0}s")
        AddEmptyOption()
        AddHeaderOption("Capture")
        ; OFF removes the Sell-to-Slavery action entirely (not offered to the LLM). Detection first:
        ; with Simple Slavery Plus Plus absent the toggle renders greyed-out and inert instead of
        ; pretending the feature exists -- same plugin-presence pattern Ostim_interactions uses for
        ; Stage Flow (detect the actual .esp, gate the UI on it).
        If Main.IsSimpleSlaveryInstalled()
            _sellSlaveryOID = AddToggleOption("Allow Sell to Slavery",  Main.bSellToSlavery)
        Else
            _sellSlaveryOID = AddToggleOption("Allow Sell to Slavery (Simple Slavery++ not installed)", False, OPTION_FLAG_DISABLED)
        EndIf
        ; Same presence-gated pattern for the FOLLOWER slavery action (Follower Slavery Mod). Its
        ; readiness flag only flips after the player clicks Install in FSM's own MCM.
        If Main.IsFollowerSlaveryInstalled()
            _followerSlaveryOID = AddToggleOption("Allow Follower Enslavement", Main.bFollowerSlavery)
        Else
            _followerSlaveryOID = AddToggleOption("Allow Follower Enslavement (FSM not installed)", False, OPTION_FLAG_DISABLED)
        EndIf
        _slaveryDistOID = AddSliderOption("Player Distance to Allow It", Main.fSlaveryPlayerDistance, "{0}")
        _tiedHoursOID   = AddSliderOption("Tied Prisoner Duration",      Main.fTiedHours, "{0} h")
        AddEmptyOption()
        AddHeaderOption("Maintenance")
        ; Panic button: force-clears every hold Baka (or a stale Acheron pacify) could have left on
        ; any loaded actor -- for actors stuck non-aggressive/untargetable after something went wrong.
        ; Leaves genuinely downed/defeated actors alone (HelpUp / the get-up key is their way out).
        _panicOID = AddTextOption("EMERGENCY: reset stuck actor states", "RUN")
        AddEmptyOption()
        ;  DOGFOOD-FIXTURE: this script is the -NEUTERED DEAD QUEST (detached
        ; from the quest record — SNBaka_MCM.psc is the LIVE MCM). The  Execute-gate
        ; option block below was BUILT HERE BY MISTAKE and never rendered in-game. 
        ; Task 1 PORTED the whole block (declaration/option/dialog legs/name fns/InfoText)
        ; into the live SNBaka_MCM.psc (GetVersion 4 -> 5 there). It is retained here,
        ; comment-out of render lines intentionally NOT done (dead script, never runs) —
        ; but treat this block as HISTORICAL only; do not extend it.
        ;  Task 2.1 — Execute-gate cycling option (family convention: menu option + name
        ; function, like "Target Sex"/"Scene Framework"). Level names user-ruled 2026-10-10.
        _execGateOID = AddMenuOption("Execution Action Use", _execGateName(_ExecGateLevel()))
    ElseIf page == "Timing"
        SetCursorFillMode(TOP_TO_BOTTOM)
        AddHeaderOption("Animation Durations")
        _hugDurOID    = AddSliderOption("Hug Loop Duration",         Main.fHugLoopDuration,    "{0}s")
        _molestDurOID = AddSliderOption("Molest Loop Duration",      Main.fMolestLoopDuration, "{0}s")
        _kissDurOID   = AddSliderOption("Kiss Duration (per stage)", Main.fKissLoopDuration,   "{0}s")
        _touchDurOID  = AddSliderOption("Touch Duration",            Main.fTouchLoopDuration,  "{0}s")
        _stageDurOID  = AddSliderOption("Sequence Stage Duration",   Main.fSequenceStageTimer, "{0}s")
    ElseIf page == "Resist"
        SetCursorFillMode(TOP_TO_BOTTOM)
        AddHeaderOption("Struggle QTE")
        _resistEnabledOID        = AddToggleOption("Enable Resist Minigame",    Main.bResistEnabled)
        _resistDifficultyOID     = AddSliderOption("Escape Difficulty",          Main.fResistDifficulty,    "{0}%")
        AddTextOption("QTE Keys", "Configured in Flash Games - Struggling QTE  (WASD / d-pad)", OPTION_FLAG_DISABLED)
        AddEmptyOption()
        AddHeaderOption("NPC-vs-NPC Struggle (no QTE, auto-rolled)")
        _npcEscapeChanceOID = AddSliderOption("Victim Escape Chance", Main.fNPCEscapeChance, "{0}%")
        _npcStageTimeOID    = AddSliderOption("Stage Duration",       Main.fNPCStageTime,    "{0}s")
        _escapeGraceOID     = AddSliderOption("Post-Escape Grace",    Main.fEscapeGraceDuration, "{0}s")
        AddEmptyOption()
        AddHeaderOption("Defeat window (fallback only)")
        _escalationWindowOID     = AddSliderOption("Escalation Window",  Main.fEscalationWindow,    "{0}s")
        _escalationDifficultyOID = AddSliderOption("Escalation QTE",     Main.fEscalationDifficulty, "{0}%")
    ElseIf page == "Spank"
        SetCursorFillMode(TOP_TO_BOTTOM)
        AddHeaderOption("Behaviour")
        _spankPlayerOID    = AddToggleOption("Player Can Be Spanked",  Main.bPlayerCanBeSpanked)
        _spankMaleOID      = AddToggleOption("Allow Male Targets",     Main.bSpankMaleTargets)
        _spankFurnitureOID = AddToggleOption("Furniture Reactions",    Main.bSpankFurnitureTriggers)
        AddEmptyOption()
        AddHeaderOption("Tattoo Marks")
        _spankTatIntensityOID = AddSliderOption("Spanks Per Stage", Main.SpankTatIntensity as Float, "{0}")
        _spankHealFactorOID   = AddSliderOption("Hours Per Stage",  Main.SpankHealFactor as Float,   "{0} hr")
    ElseIf page == "Scenes & FX"
        SetCursorFillMode(TOP_TO_BOTTOM)
        AddHeaderOption("Sex Framework")
        _sexBackendOID    = AddMenuOption("Scene Framework", _backendName(Main.iSexBackend))
        AddEmptyOption()
        AddHeaderOption("Expressions")
        _expressionsOID   = AddToggleOption("Facial Expressions",  Main.bExpressionsEnabled)
        _exprIntensityOID = AddSliderOption("Expression Intensity", Main.fExpressionIntensity, "{2}")
        AddHeaderOption("Creatures (opt-in)")
        _creatureEscOID       = AddToggleOption("Enable Creature Escalation", Main.bCreatureEscalation)
        _creatureOnPCOID      = AddToggleOption("Can Target the Player",      Main.bCreatureOnPlayer)
        _creatureCombatOID    = AddToggleOption("Allow Mid-Combat",           Main.bCreatureCombatAllowed)
        _creatureFollowerHitOID = AddToggleOption("Escalate on Hit Mid-Combat (followers + player)", Main.bCreatureEscalateFollowersOnHit)
        _creatureSceneOID     = AddToggleOption("Escalate to Sex After Win", Main.bCreatureSceneAllowed)
        _llmGateOID           = AddToggleOption("LLM Decides Escalations",   Main.bLLMGateEscalation)
        _notifyOID            = AddToggleOption("Show Corner Notifications", Main.bShowNotifications)
        _debugLogOID          = AddToggleOption("Enable Debug Logging",      Main.bDebugLog)
        _creatureVictimSexOID = AddMenuOption("Victim Sex Allowed",  _victimSexName(Main.iCreatureVictimSex))
        _creatureBackendOID   = AddMenuOption("Creature Framework",  _backendName(Main.iCreatureBackend))
        _creatureSuccessOID   = AddSliderOption("NPC Success Chance", Main.iCreatureSuccessPct as Float, "{0}%")
        _creatureHitChanceOID = AddSliderOption("Chance to Struggle on Hit", Main.iCreatureHitEngageChance as Float, "{0}%")
        _creatureStruggleDurOID = AddSliderOption("Struggle Duration", Main.fCreatureStruggleDuration, "{1}s")
        _creatureGraceOID     = AddSliderOption("Post-Defeat Grace",   Main.fPostDefeatGraceDuration, "{0}s")
        _creatureGroupSizeOID = AddSliderOption("Max Group Size",      Main.iCreatureGroupMaxSize as Float, "{0}")
        AddHeaderOption("Humanoids (mid-combat)")
        _humanOnHitOID       = AddToggleOption("Escalate on Hit Mid-Combat (followers + player)", Main.bHumanEscalateOnHit)
        _humanHitChanceOID   = AddSliderOption("Chance to Struggle on Hit", Main.iHumanHitEngageChance as Float, "{0}%")
    ElseIf page == "Plugins"
        SetCursorFillMode(TOP_TO_BOTTOM)
        ; Optional third-party mod integrations — each autodetected, greyed out when the mod is
        ; absent (same presence-gated pattern as the SS++/FSM toggles on General).
        AddHeaderOption("Immersive Lap Sitting")
        If Main.IsLapSitInstalled()
            _lapSitOID = AddToggleOption("Enable Lap Sitting Actions", Main.bLapSitEnabled)
        Else
            _lapSitOID = AddToggleOption("Enable Lap Sitting Actions (mod not installed)", False, OPTION_FLAG_DISABLED)
        EndIf
        ;  detection + inflation triggers -- same presence-gated pattern as Lap Sitting.
        AddHeaderOption("Cum Detection (OCum / SexLab)")
        If Main._OCumInstalled()
            _cumDetectOID = AddToggleOption("Cum Cues (OCum + SexLab climax proxy)", Main.bCumDetectionEnabled)
            If Main.bCumDetectionEnabled
                _slProxyOID = AddToggleOption("SexLab Climax Proxy Share", Main.bSLProxyEnabled)
            Else
                _slProxyOID = AddToggleOption("SexLab Climax Proxy Share", Main.bSLProxyEnabled, OPTION_FLAG_DISABLED)
            EndIf
        Else
            _cumDetectOID = AddToggleOption("Cum Cues (OCum not installed)", False, OPTION_FLAG_DISABLED)
            _slProxyOID   = -1
        EndIf
        AddHeaderOption("FHU Inflation Awareness")
        If Main._FHUInstalled()
            _fhuAwareOID = AddToggleOption("Inflation Level Cues (Fill Her Up)", Main.bFHUInflationEnabled)
        Else
            _fhuAwareOID = AddToggleOption("Inflation Level Cues (mod not installed)", False, OPTION_FLAG_DISABLED)
        EndIf
        ; : consolidated bridge settings — same SNAcheron.* keys/defaults the bridge MCM
        ; wrote (player-keyed StorageUtil; the bridge quest re-reads them every tick). Presence-
        ; gated on the bridge esp exactly like the other plugin sections; the bridge's own MCM
        ; quest still exists in its esp but this page is now the primary surface (Option-B ruling).
        AddEmptyOption()
        AddHeaderOption("Downed State (Acheron Bridge)")
        Actor _achP = Main.PlayerRef
        If !_achP
            _achP = Game.GetPlayer()
        EndIf
        If Main.IsAcheronBridgeInstalled()
            _achEnabledOID  = AddToggleOption("Bridge Enabled",            StorageUtil.GetIntValue(_achP,   "SNAcheron.Enabled",           1) == 1)
            _achCueOID      = AddSliderOption("Reminder Cue Interval",     StorageUtil.GetFloatValue(_achP, "SNAcheron.CueInterval",       30.0),  "{0} s")
            _achProxOID     = AddSliderOption("Creature Check Interval",   StorageUtil.GetFloatValue(_achP, "SNAcheron.ProxInterval",      10.0),  "{0} s")
            _achConfirmOID  = AddSliderOption("Auto Get-Up Timer",         StorageUtil.GetFloatValue(_achP, "SNAcheron.AutoGetUpSeconds",  600.0), "{0} s")
            _achHandoffOID  = AddToggleOption("Creature Pounce On Recovery", StorageUtil.GetIntValue(_achP, "SNAcheron.CreatureHandoff",    1) == 1)
            _achGetUpKeyOID = AddKeyMapOption("Get-Up Key (hold 3s)",      StorageUtil.GetIntValue(_achP,   "SNAcheron.GetUpKey",          51))
            _achEngageOID   = AddSliderOption("Creature Engagement Chance", StorageUtil.GetFloatValue(_achP, "SNAcheron.CreatureEngageChance", 50.0), "{0}%")
            _achDebugOID    = AddToggleOption("Enable Debug Logging",      StorageUtil.GetIntValue(_achP,   "SNAcheron.DebugLog",          1) == 1)
        Else
            _achEnabledOID  = AddToggleOption("Bridge Enabled (Acheron bridge not installed)", False, OPTION_FLAG_DISABLED)
            _achCueOID      = -1
            _achProxOID     = -1
            _achConfirmOID  = -1
            _achHandoffOID  = -1
            _achGetUpKeyOID = -1
            _achEngageOID   = -1
            _achDebugOID    = -1
        EndIf
        ;  SlaveTats degradation sets — same presence-gated pattern as the sections
        ; above. Set section/name pairs are chosen in the PrismaUI SlaveTats menu; here we
        ; expose the master/event toggles, a pack-list Refresh (rebuilds the SlaveTats cache
        ; after enabling a pack in MO2 — see SNBaka_SlaveTatsModule.RefreshPacks), and a
        ; status line summarizing discovery + the chosen sets.
        AddEmptyOption()
        AddHeaderOption("SlaveTats Degradation Sets")
        Actor _stP = Main.PlayerRef
        If !_stP
            _stP = Game.GetPlayer()
        EndIf
        If SNBaka_SlaveTatsModule.Installed()
            _stEnabledOID = AddToggleOption("Module Enabled",               StorageUtil.GetIntValue(_stP,  "SNBaka.ST.Enabled",           1) == 1)
            _stSpankOID   = AddToggleOption("Apply Set On Spank",           StorageUtil.GetIntValue(_stP,  "SNBaka.ST.ApplyOnSpank",      1) == 1)
            _stDefeatOID  = AddToggleOption("Apply Set On Defeat",          StorageUtil.GetIntValue(_stP,  "SNBaka.ST.ApplyOnDefeat",     1) == 1)
            _stEscalOID   = AddToggleOption("Apply Set On Escalation",      StorageUtil.GetIntValue(_stP,  "SNBaka.ST.ApplyOnEscalation", 0) == 1)
            _stRefreshOID = AddTextOption("Refresh Pack List",             "Refresh")
            _stStatusOID  = AddTextOption("Discovered Sections",           StorageUtil.GetIntValue(_stP, "SNBaka.ST.SectionCount", 0) + " (sets: choose in SlaveTats menu)")
            _stPickOID    = AddTextOption("Choose Sets (SlaveTats Menu)",  "Open")
            ;  Task 4: module-wide default color (picker per-set colors override),
            ; removal-on-release, and the ambient observation pass toggle.
            _stDefaultColorOID   = AddTextOption("Default Mark Color",     _ST_ColorLabel(StorageUtil.GetIntValue(_stP, "SNBaka.ST.DefaultColor", 0)))
            _stRemoveOnReleaseOID = AddToggleOption("Remove Marks On Release", StorageUtil.GetIntValue(_stP, "SNBaka.ST.RemoveOnRelease", 1) == 1)
            _stObserveOID         = AddToggleOption("Ambient Observation Cues", StorageUtil.GetIntValue(_stP, "SNBaka.ST.Observe", 1) == 1)
        Else
            _stEnabledOID = AddToggleOption("Module Enabled (SlaveTats not installed)", False, OPTION_FLAG_DISABLED)
            _stSpankOID   = -1
            _stDefeatOID  = -1
            _stEscalOID   = -1
            _stRefreshOID = -1
            _stStatusOID  = -1
            _stPickOID    = -1
            _stDefaultColorOID    = -1
            _stRemoveOnReleaseOID = -1
            _stObserveOID         = -1
        EndIf
    EndIf
EndEvent

Event OnOptionSelect(Int option)
    If option == _enabledOID
        Main.bEnabled = !Main.bEnabled
        SetToggleOptionValue(_enabledOID, Main.bEnabled)
    ElseIf option == _panicOID
        Int stuck = Main.PanicReset()
        Debug.Notification("Baka: emergency reset done - " + stuck + " actor(s) had a stuck state.")
    ElseIf option == _lapSitOID
        Main.bLapSitEnabled = !Main.bLapSitEnabled
        SetToggleOptionValue(_lapSitOID, Main.bLapSitEnabled)
        If Main.bLapSitEnabled
            Debug.Notification("Lap Sitting actions enabled (returns to the action menu after a reload).")
        Else
            SkyrimNetApi.UnregisterAction("SitOnLap")
            Debug.Notification("Lap Sitting actions disabled and removed from the action menu.")
        EndIf
    ElseIf option == _cumDetectOID
        Main.bCumDetectionEnabled = !Main.bCumDetectionEnabled
        SetToggleOptionValue(_cumDetectOID, Main.bCumDetectionEnabled)
        SetOptionFlags(_slProxyOID, OPTION_FLAG_DISABLED * ((!Main.bCumDetectionEnabled) as Int))
        If Main.bCumDetectionEnabled
            Main.Setup()
            Debug.Notification("Cum cues enabled.")
        Else
            Debug.Notification("Cum cues disabled.")
        EndIf
    ElseIf option == _slProxyOID
        Main.bSLProxyEnabled = !Main.bSLProxyEnabled
        SetToggleOptionValue(_slProxyOID, Main.bSLProxyEnabled)
    ElseIf option == _fhuAwareOID
        Main.bFHUInflationEnabled = !Main.bFHUInflationEnabled
        SetToggleOptionValue(_fhuAwareOID, Main.bFHUInflationEnabled)
        Main.Setup()   ; re-arms or disarms the level poll right now
    ElseIf option == _achEnabledOID
        ;  bridge master switch — same SNAcheron.Enabled key the bridge MCM wrote; the
        ; bridge quest re-reads it on its next tick. Nudges the motherboard lifecycle surface
        ; (per the  ruling: toggles nudge Main._ArmModules()) so the bridge picks the change
        ; up immediately instead of on its own self-heal cadence.
        Actor achP1 = Main.PlayerRef
        If !achP1
            achP1 = Game.GetPlayer()
        EndIf
        Int vAch = 1 - StorageUtil.GetIntValue(achP1, "SNAcheron.Enabled", 1)
        StorageUtil.SetIntValue(achP1, "SNAcheron.Enabled", vAch)
        SetToggleOptionValue(_achEnabledOID, vAch == 1)
        Main._ArmModules()
    ElseIf option == _achHandoffOID
        Actor achP2 = Main.PlayerRef
        If !achP2
            achP2 = Game.GetPlayer()
        EndIf
        Int vHand = 1 - StorageUtil.GetIntValue(achP2, "SNAcheron.CreatureHandoff", 1)
        StorageUtil.SetIntValue(achP2, "SNAcheron.CreatureHandoff", vHand)
        SetToggleOptionValue(_achHandoffOID, vHand == 1)
    ElseIf option == _achDebugOID
        Actor achP3 = Main.PlayerRef
        If !achP3
            achP3 = Game.GetPlayer()
        EndIf
        Int vDbg = 1 - StorageUtil.GetIntValue(achP3, "SNAcheron.DebugLog", 1)
        StorageUtil.SetIntValue(achP3, "SNAcheron.DebugLog", vDbg)
        SetToggleOptionValue(_achDebugOID, vDbg == 1)
    ElseIf option == _stEnabledOID
        _ST_Toggle("SNBaka.ST.Enabled", _stEnabledOID, 1)
    ElseIf option == _stSpankOID
        _ST_Toggle("SNBaka.ST.ApplyOnSpank", _stSpankOID, 1)
    ElseIf option == _stDefeatOID
        _ST_Toggle("SNBaka.ST.ApplyOnDefeat", _stDefeatOID, 1)
    ElseIf option == _stEscalOID
        _ST_Toggle("SNBaka.ST.ApplyOnEscalation", _stEscalOID, 0)
    ElseIf option == _stRefreshOID
        SNBaka_SlaveTatsModule.RefreshPacks()
        Actor stP1 = Main.PlayerRef
        If !stP1
            stP1 = Game.GetPlayer()
        EndIf
        SetTextOptionValue(_stStatusOID, StorageUtil.GetIntValue(stP1, "SNBaka.ST.SectionCount", 0) + " (sets: choose in SlaveTats menu)")
        Debug.Notification("SlaveTats: pack list refreshed - " + StorageUtil.GetIntValue(stP1, "SNBaka.ST.SectionCount", 0) + " sections visible.")
    ElseIf option == _stPickOID
        ;  dogfood fix: the set picker had no in-game entry point (OpenSetMenu was
        ; dead code). Close the MCM first — PrismaUI modal needs the game input focus.
        SNBaka_SlaveTatsModule.OpenSetMenu()
    ElseIf option == _stDefaultColorOID
        ; : cycle Default -> Black -> Red -> Crimson -> Dark Red -> Blue -> Green
        ; -> Purple -> Pink -> Default. Stored as the 0xRRGGBB int the module reads
        ; (SNBaka.ST.DefaultColor; 0 = pack default / no recolor).
        Actor stP2 = Main.PlayerRef
        If !stP2
            stP2 = Game.GetPlayer()
        EndIf
        Int[] palette = _ST_ColorPalette()
        Int cur = StorageUtil.GetIntValue(stP2, "SNBaka.ST.DefaultColor", 0)
        Int nxt = 0
        Int ci = palette.Find(cur)
        If ci < 0 || ci >= palette.Length - 1
            nxt = palette[0]
        Else
            nxt = palette[ci + 1]
        EndIf
        StorageUtil.SetIntValue(stP2, "SNBaka.ST.DefaultColor", nxt)
        SetTextOptionValue(_stDefaultColorOID, _ST_ColorLabel(nxt))
    ElseIf option == _stRemoveOnReleaseOID
        _ST_Toggle("SNBaka.ST.RemoveOnRelease", _stRemoveOnReleaseOID, 1)
    ElseIf option == _stObserveOID
        _ST_Toggle("SNBaka.ST.Observe", _stObserveOID, 1)
    ElseIf option == _animatedTearsOID
        Main.bAnimatedTearsEnabled = !Main.bAnimatedTearsEnabled
        SetToggleOptionValue(_animatedTearsOID, Main.bAnimatedTearsEnabled)
        ; If just enabled and spell not yet resolved, try now
        If Main.bAnimatedTearsEnabled && !Main.TearSpell
            Main.TearSpell = Game.GetFormFromFile(0x000802, "EmoTears4NPCs.esp") as Spell
        EndIf
    ElseIf option == _playerTargetOID
        Main.bPlayerCanBeTarget = !Main.bPlayerCanBeTarget
        SetToggleOptionValue(_playerTargetOID, Main.bPlayerCanBeTarget)
    ElseIf option == _sellSlaveryOID
        Main.bSellToSlavery = !Main.bSellToSlavery
        SetToggleOptionValue(_sellSlaveryOID, Main.bSellToSlavery)
        If Main.bSellToSlavery
            ; YAML re-registers it on the next game load; can't cleanly re-add it mid-session.
            Debug.Notification("Sell to Slavery re-enabled (returns to the action menu after a reload).")
        Else
            ; Remove it from the LLM action menu entirely, right now.
            SkyrimNetApi.UnregisterAction("SellToSlavery")
            Debug.Notification("Sell to Slavery disabled and removed from the action menu.")
        EndIf
    ElseIf option == _followerSlaveryOID
        Main.bFollowerSlavery = !Main.bFollowerSlavery
        SetToggleOptionValue(_followerSlaveryOID, Main.bFollowerSlavery)
        If Main.bFollowerSlavery
            Debug.Notification("Follower Enslavement enabled (returns to the action menu after a reload).")
        Else
            SkyrimNetApi.UnregisterAction("EnslaveFollower")
            Debug.Notification("Follower Enslavement disabled and removed from the action menu.")
        EndIf
    ElseIf option == _resistEnabledOID
        Main.bResistEnabled = !Main.bResistEnabled
        SetToggleOptionValue(_resistEnabledOID, Main.bResistEnabled)
    ElseIf option == _spankPlayerOID
        Main.bPlayerCanBeSpanked = !Main.bPlayerCanBeSpanked
        SetToggleOptionValue(_spankPlayerOID, Main.bPlayerCanBeSpanked)
    ElseIf option == _spankMaleOID
        Main.bSpankMaleTargets = !Main.bSpankMaleTargets
        SetToggleOptionValue(_spankMaleOID, Main.bSpankMaleTargets)
    ElseIf option == _spankFurnitureOID
        Main.bSpankFurnitureTriggers = !Main.bSpankFurnitureTriggers
        SetToggleOptionValue(_spankFurnitureOID, Main.bSpankFurnitureTriggers)
    ElseIf option == _expressionsOID
        Main.bExpressionsEnabled = !Main.bExpressionsEnabled
        SetToggleOptionValue(_expressionsOID, Main.bExpressionsEnabled)
    ElseIf option == _creatureEscOID
        Main.bCreatureEscalation = !Main.bCreatureEscalation
        SetToggleOptionValue(_creatureEscOID, Main.bCreatureEscalation)
    ElseIf option == _creatureOnPCOID
        Main.bCreatureOnPlayer = !Main.bCreatureOnPlayer
        SetToggleOptionValue(_creatureOnPCOID, Main.bCreatureOnPlayer)
    ElseIf option == _creatureCombatOID
        Main.bCreatureCombatAllowed = !Main.bCreatureCombatAllowed
        SetToggleOptionValue(_creatureCombatOID, Main.bCreatureCombatAllowed)
    ElseIf option == _creatureFollowerHitOID
        Main.bCreatureEscalateFollowersOnHit = !Main.bCreatureEscalateFollowersOnHit
        SetToggleOptionValue(_creatureFollowerHitOID, Main.bCreatureEscalateFollowersOnHit)
    ElseIf option == _creatureSceneOID
        Main.bCreatureSceneAllowed = !Main.bCreatureSceneAllowed
        SetToggleOptionValue(_creatureSceneOID, Main.bCreatureSceneAllowed)
    ElseIf option == _llmGateOID
        Main.bLLMGateEscalation = !Main.bLLMGateEscalation
        SetToggleOptionValue(_llmGateOID, Main.bLLMGateEscalation)
    ElseIf option == _notifyOID
        Main.bShowNotifications = !Main.bShowNotifications
        SetToggleOptionValue(_notifyOID, Main.bShowNotifications)
    ElseIf option == _debugLogOID
        Main.bDebugLog = !Main.bDebugLog
        SetToggleOptionValue(_debugLogOID, Main.bDebugLog)
    ElseIf option == _humanOnHitOID
        Main.bHumanEscalateOnHit = !Main.bHumanEscalateOnHit
        SetToggleOptionValue(_humanOnHitOID, Main.bHumanEscalateOnHit)
    EndIf
EndEvent

;  — get-up key rebinding for the consolidated bridge section. Writes the same
; SNAcheron.GetUpKey StorageUtil key the bridge's own MCM used (identical defaults/handling;
; the bridge quest reads it every tick, so no nudge is needed for a keybind).
Event OnOptionKeyMapChange(Int option, Int keyCode, String conflictControl, String conflictName)
    If option == _achGetUpKeyOID
        Actor achPk = Main.PlayerRef
        If !achPk
            achPk = Game.GetPlayer()
        EndIf
        StorageUtil.SetIntValue(achPk, "SNAcheron.GetUpKey", keyCode)
        SetKeyMapOptionValue(_achGetUpKeyOID, keyCode)
    EndIf
EndEvent

Event OnOptionMenuOpen(Int option)
    If option == _sexBackendOID
        SetMenuDialogOptions(_backendNames())
        SetMenuDialogStartIndex(Main.iSexBackend)
        SetMenuDialogDefaultIndex(0)
    ElseIf option == _creatureBackendOID
        SetMenuDialogOptions(_backendNames())
        SetMenuDialogStartIndex(Main.iCreatureBackend)
        SetMenuDialogDefaultIndex(0)
    ElseIf option == _creatureVictimSexOID
        SetMenuDialogOptions(_victimSexNames())
        SetMenuDialogStartIndex(Main.iCreatureVictimSex)
        SetMenuDialogDefaultIndex(0)
    ElseIf option == _femaleOnlyOID
        SetMenuDialogOptions(_targetSexNames())
        SetMenuDialogStartIndex(Main.iTargetSex)
        SetMenuDialogDefaultIndex(0)
    ElseIf option == _execGateOID
        SetMenuDialogOptions(_execGateNames())
        SetMenuDialogStartIndex(_ExecGateLevel())
        SetMenuDialogDefaultIndex(0)
    EndIf
EndEvent

Event OnOptionMenuAccept(Int option, Int index)
    If option == _sexBackendOID
        Main.iSexBackend = index
        SetMenuOptionValue(_sexBackendOID, _backendName(index))
    ElseIf option == _creatureBackendOID
        Main.iCreatureBackend = index
        SetMenuOptionValue(_creatureBackendOID, _backendName(index))
    ElseIf option == _creatureVictimSexOID
        Main.iCreatureVictimSex = index
        SetMenuOptionValue(_creatureVictimSexOID, _victimSexName(index))
    ElseIf option == _femaleOnlyOID
        Main.iTargetSex = index
        SetMenuOptionValue(_femaleOnlyOID, _targetSexName(index))
    ElseIf option == _execGateOID
        ;  Task 2.1 — player-keyed StorageUtil write (same pattern as the SNAcheron.*
        ; options; no CK property link). Execute_Execute re-reads it on every fire.
        _SetExecGateLevel(index)
        SetMenuOptionValue(_execGateOID, _execGateName(index))
    EndIf
EndEvent

;  Task 2.1 — Execute-gate level names (user-ruled 2026-10-10; ASCII-only per the
; runtime-string ASCII rider).
String[] Function _execGateNames()
    String[] a = new String[3]
    a[0] = "Unlimited"
    a[1] = "Companions ask"
    a[2] = "Always ask"
    Return a
EndFunction

String Function _execGateName(Int i)
    If i == 1
        Return "Companions ask"
    ElseIf i == 2
        Return "Always ask"
    EndIf
    Return "Unlimited"
EndFunction

Int Function _ExecGateLevel()
    Actor p = Main.PlayerRef
    If !p
        p = Game.GetPlayer()
    EndIf
    Return StorageUtil.GetIntValue(p, "SNBaka.ExecuteGateLevel", 0)
EndFunction

Function _SetExecGateLevel(Int i)
    Actor p = Main.PlayerRef
    If !p
        p = Game.GetPlayer()
    EndIf
    StorageUtil.SetIntValue(p, "SNBaka.ExecuteGateLevel", i)
EndFunction


String[] Function _targetSexNames()
    String[] a = new String[3]
    a[0] = "Both"
    a[1] = "Female only"
    a[2] = "Male only"
    Return a
EndFunction

String Function _targetSexName(Int i)
    If i == 1
        Return "Female only"
    ElseIf i == 2
        Return "Male only"
    EndIf
    Return "Both"
EndFunction

; Creature victim sex uses the SAME scheme as the general Target Sex: 0 = Both, 1 = Female, 2 = Male.
; (No "None" option — that only ever disabled the whole feature and was the reason creatures never
;  escalated by default.)
String[] Function _victimSexNames()
    Return _targetSexNames()
EndFunction

String Function _victimSexName(Int i)
    Return _targetSexName(i)
EndFunction

String[] Function _backendNames()
    String[] a = new String[3]
    a[0] = "Auto"
    a[1] = "SexLab"
    a[2] = "OStim"
    Return a
EndFunction

String Function _backendName(Int i)
    If i == 1
        Return "SexLab"
    ElseIf i == 2
        Return "OStim"
    EndIf
    Return "Auto"
EndFunction

Event OnOptionSliderOpen(Int option)
    If option == _hugDurOID
        SetSliderDialogStartValue(Main.fHugLoopDuration)
        SetSliderDialogDefaultValue(8.0)
        SetSliderDialogRange(2.0, 30.0)
        SetSliderDialogInterval(1.0)
    ElseIf option == _molestDurOID
        SetSliderDialogStartValue(Main.fMolestLoopDuration)
        SetSliderDialogDefaultValue(8.0)
        SetSliderDialogRange(2.0, 30.0)
        SetSliderDialogInterval(1.0)
    ElseIf option == _kissDurOID
        SetSliderDialogStartValue(Main.fKissLoopDuration)
        SetSliderDialogDefaultValue(6.0)
        SetSliderDialogRange(2.0, 20.0)
        SetSliderDialogInterval(1.0)
    ElseIf option == _touchDurOID
        SetSliderDialogStartValue(Main.fTouchLoopDuration)
        SetSliderDialogDefaultValue(6.0)
        SetSliderDialogRange(2.0, 20.0)
        SetSliderDialogInterval(1.0)
    ElseIf option == _stageDurOID
        SetSliderDialogStartValue(Main.fSequenceStageTimer)
        SetSliderDialogDefaultValue(4.0)
        SetSliderDialogRange(1.0, 15.0)
        SetSliderDialogInterval(0.5)
    ElseIf option == _cooldownOID
        SetSliderDialogStartValue(Main.fNPCGlobalCooldown)
        SetSliderDialogDefaultValue(30.0)
        SetSliderDialogRange(0.0, 120.0)
        SetSliderDialogInterval(5.0)
    ElseIf option == _resistDifficultyOID
        SetSliderDialogStartValue(Main.fResistDifficulty)
        SetSliderDialogDefaultValue(70.0)
        SetSliderDialogRange(10.0, 95.0)
        SetSliderDialogInterval(5.0)
    ElseIf option == _npcEscapeChanceOID
        SetSliderDialogStartValue(Main.fNPCEscapeChance)
        SetSliderDialogDefaultValue(35.0)
        SetSliderDialogRange(0.0, 100.0)
        SetSliderDialogInterval(5.0)
    ElseIf option == _npcStageTimeOID
        SetSliderDialogStartValue(Main.fNPCStageTime)
        SetSliderDialogDefaultValue(5.0)
        SetSliderDialogRange(1.0, 15.0)
        SetSliderDialogInterval(0.5)
    ElseIf option == _escapeGraceOID
        SetSliderDialogStartValue(Main.fEscapeGraceDuration)
        SetSliderDialogDefaultValue(4.0)
        SetSliderDialogRange(0.0, 30.0)
        SetSliderDialogInterval(1.0)
    ElseIf option == _slaveryDistOID
        SetSliderDialogStartValue(Main.fSlaveryPlayerDistance)
        SetSliderDialogDefaultValue(1500.0)
        SetSliderDialogRange(500.0, 6000.0)
        SetSliderDialogInterval(100.0)
    ElseIf option == _tiedHoursOID
        SetSliderDialogStartValue(Main.fTiedHours)
        SetSliderDialogDefaultValue(12.0)
        SetSliderDialogRange(1.0, 72.0)
        SetSliderDialogInterval(1.0)
    ElseIf option == _escalationWindowOID
        SetSliderDialogStartValue(Main.fEscalationWindow)
        SetSliderDialogDefaultValue(20.0)
        SetSliderDialogRange(5.0, 60.0)
        SetSliderDialogInterval(5.0)
    ElseIf option == _escalationDifficultyOID
        SetSliderDialogStartValue(Main.fEscalationDifficulty)
        SetSliderDialogDefaultValue(70.0)
        SetSliderDialogRange(10.0, 95.0)
        SetSliderDialogInterval(5.0)
    ElseIf option == _spankTatIntensityOID
        SetSliderDialogStartValue(Main.SpankTatIntensity as Float)
        SetSliderDialogDefaultValue(2.0)
        SetSliderDialogRange(1.0, 10.0)
        SetSliderDialogInterval(1.0)
    ElseIf option == _spankHealFactorOID
        SetSliderDialogStartValue(Main.SpankHealFactor as Float)
        SetSliderDialogDefaultValue(2.0)
        SetSliderDialogRange(1.0, 10.0)
        SetSliderDialogInterval(1.0)
    ElseIf option == _exprIntensityOID
        SetSliderDialogStartValue(Main.fExpressionIntensity)
        SetSliderDialogDefaultValue(0.5)
        SetSliderDialogRange(0.0, 1.0)
        SetSliderDialogInterval(0.05)
    ElseIf option == _creatureSuccessOID
        SetSliderDialogStartValue(Main.iCreatureSuccessPct as Float)
        SetSliderDialogDefaultValue(50.0)
        SetSliderDialogRange(0.0, 100.0)
        SetSliderDialogInterval(5.0)
    ElseIf option == _creatureHitChanceOID
        SetSliderDialogStartValue(Main.iCreatureHitEngageChance as Float)
        SetSliderDialogDefaultValue(25.0)
        SetSliderDialogRange(0.0, 100.0)
        SetSliderDialogInterval(5.0)
    ElseIf option == _creatureStruggleDurOID
        SetSliderDialogStartValue(Main.fCreatureStruggleDuration)
        SetSliderDialogDefaultValue(20.0)
        SetSliderDialogRange(5.0, 40.0)
        SetSliderDialogInterval(1.0)
    ElseIf option == _creatureGraceOID
        SetSliderDialogStartValue(Main.fPostDefeatGraceDuration)
        SetSliderDialogDefaultValue(100.0)
        SetSliderDialogRange(0.0, 300.0)
        SetSliderDialogInterval(10.0)
    ElseIf option == _creatureGroupSizeOID
        SetSliderDialogStartValue(Main.iCreatureGroupMaxSize as Float)
        SetSliderDialogDefaultValue(3.0)
        SetSliderDialogRange(1.0, 3.0)
        SetSliderDialogInterval(1.0)
    ElseIf option == _humanHitChanceOID
        SetSliderDialogStartValue(Main.iHumanHitEngageChance as Float)
        SetSliderDialogDefaultValue(25.0)
        SetSliderDialogRange(0.0, 100.0)
        SetSliderDialogInterval(5.0)
    ElseIf option == _achCueOID
        SetSliderDialogStartValue(StorageUtil.GetFloatValue(Main.PlayerRef, "SNAcheron.CueInterval", 30.0))
        SetSliderDialogDefaultValue(30.0)
        SetSliderDialogRange(10.0, 120.0)
        SetSliderDialogInterval(5.0)
    ElseIf option == _achProxOID
        SetSliderDialogStartValue(StorageUtil.GetFloatValue(Main.PlayerRef, "SNAcheron.ProxInterval", 10.0))
        SetSliderDialogDefaultValue(10.0)
        SetSliderDialogRange(5.0, 60.0)
        SetSliderDialogInterval(5.0)
    ElseIf option == _achConfirmOID
        SetSliderDialogStartValue(StorageUtil.GetFloatValue(Main.PlayerRef, "SNAcheron.AutoGetUpSeconds", 600.0))
        SetSliderDialogDefaultValue(600.0)
        SetSliderDialogRange(60.0, 3600.0)
        SetSliderDialogInterval(30.0)
    ElseIf option == _achEngageOID
        SetSliderDialogStartValue(StorageUtil.GetFloatValue(Main.PlayerRef, "SNAcheron.CreatureEngageChance", 50.0))
        SetSliderDialogDefaultValue(50.0)
        SetSliderDialogRange(0.0, 100.0)
        SetSliderDialogInterval(5.0)
    EndIf
EndEvent

Event OnOptionSliderAccept(Int option, Float value)
    If option == _hugDurOID
        Main.fHugLoopDuration = value
        SetSliderOptionValue(_hugDurOID, value, "{0}s")
    ElseIf option == _molestDurOID
        Main.fMolestLoopDuration = value
        SetSliderOptionValue(_molestDurOID, value, "{0}s")
    ElseIf option == _kissDurOID
        Main.fKissLoopDuration = value
        SetSliderOptionValue(_kissDurOID, value, "{0}s")
    ElseIf option == _touchDurOID
        Main.fTouchLoopDuration = value
        SetSliderOptionValue(_touchDurOID, value, "{0}s")
    ElseIf option == _stageDurOID
        Main.fSequenceStageTimer = value
        SetSliderOptionValue(_stageDurOID, value, "{0}s")
    ElseIf option == _cooldownOID
        Main.fNPCGlobalCooldown = value
        SetSliderOptionValue(_cooldownOID, value, "{0}s")
    ElseIf option == _resistDifficultyOID
        Main.fResistDifficulty = value
        SetSliderOptionValue(_resistDifficultyOID, value, "{0}%")
    ElseIf option == _npcEscapeChanceOID
        Main.fNPCEscapeChance = value
        SetSliderOptionValue(_npcEscapeChanceOID, value, "{0}%")
    ElseIf option == _npcStageTimeOID
        Main.fNPCStageTime = value
        SetSliderOptionValue(_npcStageTimeOID, value, "{0}s")
    ElseIf option == _escapeGraceOID
        Main.fEscapeGraceDuration = value
        ; StorageUtil mirror: the Acheron bridge applies the same grace after its get-up key QTE win,
        ; and (no hard script reference between the mods, by design) reads this shared key instead.
        StorageUtil.SetFloatValue(Game.GetPlayer(), "SNBaka.EscapeGraceDuration", value)
        SetSliderOptionValue(_escapeGraceOID, value, "{0}s")
    ElseIf option == _slaveryDistOID
        Main.fSlaveryPlayerDistance = value
        SetSliderOptionValue(_slaveryDistOID, value, "{0}")
    ElseIf option == _tiedHoursOID
        Main.fTiedHours = value
        SetSliderOptionValue(_tiedHoursOID, value, "{0} h")
    ElseIf option == _escalationWindowOID
        Main.fEscalationWindow = value
        SetSliderOptionValue(_escalationWindowOID, value, "{0}s")
    ElseIf option == _escalationDifficultyOID
        Main.fEscalationDifficulty = value
        SetSliderOptionValue(_escalationDifficultyOID, value, "{0}%")
    ElseIf option == _spankTatIntensityOID
        Main.SpankTatIntensity = value as Int
        SetSliderOptionValue(_spankTatIntensityOID, value, "{0}")
    ElseIf option == _spankHealFactorOID
        Main.SpankHealFactor = value as Int
        Main.ApplyFadeSettings()
        SetSliderOptionValue(_spankHealFactorOID, value, "{0} hr")
    ElseIf option == _exprIntensityOID
        Main.fExpressionIntensity = value
        SetSliderOptionValue(_exprIntensityOID, value, "{2}")
    ElseIf option == _creatureSuccessOID
        Main.iCreatureSuccessPct = value as Int
        SetSliderOptionValue(_creatureSuccessOID, value, "{0}%")
    ElseIf option == _creatureHitChanceOID
        Main.iCreatureHitEngageChance = value as Int
        SetSliderOptionValue(_creatureHitChanceOID, value, "{0}%")
    ElseIf option == _humanHitChanceOID
        Main.iHumanHitEngageChance = value as Int
        SetSliderOptionValue(_humanHitChanceOID, value, "{0}%")
    ElseIf option == _creatureStruggleDurOID
        Main.fCreatureStruggleDuration = value
        SetSliderOptionValue(_creatureStruggleDurOID, value, "{1}s")
    ElseIf option == _creatureGraceOID
        Main.fPostDefeatGraceDuration = value
        SetSliderOptionValue(_creatureGraceOID, value, "{0}s")
    ElseIf option == _creatureGroupSizeOID
        Main.iCreatureGroupMaxSize = value as Int
        SetSliderOptionValue(_creatureGroupSizeOID, value, "{0}")
    ElseIf option == _achCueOID
        StorageUtil.SetFloatValue(Main.PlayerRef, "SNAcheron.CueInterval", value)
        SetSliderOptionValue(_achCueOID, value, "{0} s")
    ElseIf option == _achProxOID
        StorageUtil.SetFloatValue(Main.PlayerRef, "SNAcheron.ProxInterval", value)
        SetSliderOptionValue(_achProxOID, value, "{0} s")
    ElseIf option == _achConfirmOID
        StorageUtil.SetFloatValue(Main.PlayerRef, "SNAcheron.AutoGetUpSeconds", value)
        SetSliderOptionValue(_achConfirmOID, value, "{0} s")
    ElseIf option == _achEngageOID
        StorageUtil.SetFloatValue(Main.PlayerRef, "SNAcheron.CreatureEngageChance", value)
        SetSliderOptionValue(_achEngageOID, value, "{0}%")
    EndIf
EndEvent

Event OnOptionHighlight(Int option)
    If option == _enabledOID
        SetInfoText("Master switch for all Baka motion interactions.")
    ElseIf option == _animatedTearsOID
        SetInfoText("Apply animated 3D tears to female victims during aggressive scenes. Requires Emotional Tears Effect SE (EmoTears4NPCs.esp). Has no effect if that mod is not installed.")
    ElseIf option == _playerTargetOID
        SetInfoText("Allow NPCs to initiate Baka animations on the player.")
    ElseIf option == _femaleOnlyOID
        SetInfoText("Which target sex ALL actions allow: Both, Female only, or Male only. Note: breast/intimate actions always require female targets regardless.")
    ElseIf option == _cooldownOID
        SetInfoText("Minimum real-time seconds between NPC-initiated actions. Default 30s.")
    ElseIf option == _hugDurOID
        SetInfoText("How long BackHug and FrontHug loop phases last.")
    ElseIf option == _molestDurOID
        SetInfoText("How long BackHugMolest loop phase lasts.")
    ElseIf option == _kissDurOID
        SetInfoText("Time held on each stage of kiss animations.")
    ElseIf option == _touchDurOID
        SetInfoText("Duration of single-shot touch animations.")
    ElseIf option == _stageDurOID
        SetInfoText("Seconds per stage in multi-stage sequences (Struggle, ChokeHug, Drunk, etc.).")
    ElseIf option == _resistEnabledOID
        SetInfoText("When enabled, the Flash Games QTE overlay appears during forced animations. Player can fight back using the configured keys.")
    ElseIf option == _resistDifficultyOID
        SetInfoText("How easy it is to escape the main QTE. 70 = default. Higher = easier. Lower = harder.")
    ElseIf option == _npcEscapeChanceOID
        SetInfoText("NPC-vs-NPC struggles (no player involved, no QTE): the victim's % chance to break free, auto-rolled. Lower = the attacker wins more often. Default 35%.")
    ElseIf option == _npcStageTimeOID
        SetInfoText("NPC-vs-NPC struggles: how long each animation stage holds before advancing to the next. Default 5s.")
    ElseIf option == _escapeGraceOID
        SetInfoText("Mercy window: at every exit from a struggle or sex scene (won QTE, NPC escape, get-up key, or the scene simply ending), the victim stays untouchable for this many seconds instead of being spawn-killed the frame protection drops. They can still fight and move during it. 0 disables. Default 4s.")
    ElseIf option == _escalationWindowOID
        SetInfoText("FALLBACK ONLY (used when Acheron is not installed): seconds the attacker has to escalate after a QTE defeat. With Acheron, the downed state is owned by the Acheron bridge instead.")
    ElseIf option == _escalationDifficultyOID
        SetInfoText("Difficulty of the second QTE (choke hold) in the fallback defeat window. Same scale as Escape Difficulty.")
    ElseIf option == _spankPlayerOID
        SetInfoText("Allow the player character to be spanked by NPCs.")
    ElseIf option == _spankMaleOID
        SetInfoText("Allow male actors to be spanked. Off by default - moans and marks are female-only, so male spank is just the impact sound.")
    ElseIf option == _spankFurnitureOID
        SetInfoText("Enable special reactions when the target is using furniture (alchemy lab, forge, etc).")
    ElseIf option == _spankTatIntensityOID
        SetInfoText("How many spanks are needed to advance one mark stage. At 2: 2 spanks = light marks, 4 = medium, 6 = heavy. Men never receive marks.")
    ElseIf option == _spankHealFactorOID
        SetInfoText("In-game hours for each mark stage to heal away. At 2: full marks heal in about 8 in-game hours.")
    ElseIf option == _sellSlaveryOID
        SetInfoText("ON offers the Sell-to-Slavery action (Simple Slavery Plus Plus hand-off; no-ops without SS++). Targets the DEFEATED PLAYER only. OFF removes it from the LLM's menu entirely.")
    ElseIf option == _followerSlaveryOID
        SetInfoText("ON lets NPCs enslave a DOWNED FOLLOWER via the Follower Slavery Mod - only while the player is downed too or farther than the distance slider. Never targets the player (that's Sell to Slavery). PERMANENT until freed through FSM; default OFF.")
    ElseIf option == _slaveryDistOID
        SetInfoText("Follower Enslavement only fires if the player is at least this far from the downed follower (or downed themselves) - close enough to intervene means it never happens. Default 1500 (~21m).")
    ElseIf option == _tiedHoursOID
        SetInfoText("How many GAME hours a tied prisoner stays bound on the ground. While tied they cannot get up on their own - only Help Up (which cuts them loose) or the bindings lapsing frees them. Default 12 h.")
    ElseIf option == _sexBackendOID
        SetInfoText("Which framework plays escalation sex scenes: Auto (SexLab if present, else OStim), or force one. Neither is required; without one, escalation just narrates.")
    ElseIf option == _expressionsOID
        SetInfoText("Apply facial expressions (fear, pain, etc.) to actors during scenes. Requires MfgFix.")
    ElseIf option == _exprIntensityOID
        SetInfoText("Strength of the facial expressions, 0.0-1.0. Default 0.5.")
    ElseIf option == _creatureEscOID
        SetInfoText("Master switch for creatures forcing themselves on downed/losing humans. OFF by default (opt-in).")
    ElseIf option == _creatureOnPCOID
        SetInfoText("Allow creatures to target the PLAYER (not just NPCs). Requires Creature Escalation to be on.")
    ElseIf option == _creatureCombatOID
        SetInfoText("Allow a creature to STRUGGLE a victim down mid-combat. The creature's sex scene itself still waits until combat is fully over.")
    ElseIf option == _creatureFollowerHitOID
        SetInfoText("A creature's own melee hit on a follower or the player can attempt the struggle directly, mid-combat, without waiting for them to go down first. Player also needs 'Can Target the Player' on. Requires Allow Mid-Combat and Creature Escalation too.")
    ElseIf option == _creatureSceneOID
        SetInfoText("ON: a creature winning its struggle claims the victim in a sex scene (needs matching animations installed). OFF: struggles still happen - read as a beast mauling its prey - but a win just leaves the victim downed; no scene ever starts.")
    ElseIf option == _llmGateOID
        SetInfoText("Before a creature claims a DOWNED victim, ask the SkyrimNet LLM a yes/no ('should this escalation happen right now?'). NO backs that victim off ~30s; any LLM error counts as YES. On-hit mid-combat grapples are not gated (an LLM round-trip is too slow for live melee).")
    ElseIf option == _notifyOID
        SetInfoText("Show this mod's top-left corner messages ('X collapses...', 'What will you do to...', etc.). Turn OFF for a clean HUD - narration, dialogue and log traces are unaffected.")
    ElseIf option == _debugLogOID
        SetInfoText("Write this mod's detailed traces to the Papyrus log. Keep ON while testing/reporting issues (the log is how problems get diagnosed); turn OFF for less script-engine load during normal play.")
    ElseIf option == _creatureVictimSexOID
        SetInfoText("Which victim sex creatures may target: Both, Female only, or Male only.")
    ElseIf option == _creatureBackendOID
        SetInfoText("Which framework plays creature sex scenes (Auto / SexLab / OStim).")
    ElseIf option == _creatureSuccessOID
        SetInfoText("Chance a creature's struggle succeeds against an NPC, whether or not they're already downed. Default 50%.")
    ElseIf option == _creatureHitChanceOID
        SetInfoText("Chance that a creature's melee hit on a follower attempts the struggle at all (see 'Escalate on Followers Mid-Combat'). Lower this if it triggers too often. Default 25%.")
    ElseIf option == _creatureStruggleDurOID
        SetInfoText("How long the mid-combat struggle animation holds before the outcome is decided. Default 20s.")
    ElseIf option == _creatureGraceOID
        SetInfoText("After a victim loses a struggle, how many seconds creatures leave them alone before reconsidering them - ends early if real combat resumes. Default 100s.")
    ElseIf option == _creatureGroupSizeOID
        SetInfoText("Once a scene is actually starting, look for up to this many creatures of the same kind nearby to join in (2v1/3v1). 1 = always solo. Decided fresh each time, after the outcome is known.")
    ElseIf option == _humanOnHitOID
        SetInfoText("A hostile HUMANOID's melee hit on a follower or the player can attempt a Struggle right there, mid-combat - the humanoid counterpart of the creature option above. Uses the normal Struggle rules on top (QTE for the player, sex filter, 'Player Can Be Target', locks). Default OFF.")
    ElseIf option == _humanHitChanceOID
        SetInfoText("Chance that a hostile humanoid's melee hit attempts the Struggle at all (shares the same 3s per-victim cooldown as the creature version). Lower this if it triggers too often. Default 25%.")
    ElseIf option == _achEnabledOID
        SetInfoText("Master switch for the downed-state bridge (holding, downed cues, recovery).")
    ElseIf option == _achCueOID
        SetInfoText("How often, while an actor is down, we send a short 'still downed' reminder. Purely narrative - does not affect recovery timing. Default 30 s.")
    ElseIf option == _achProxOID
        SetInfoText("How often we check for a nearby CREATURE, purely to give Baka's creature-escalation pipeline a shot. Does not affect recovery - proximity no longer gates getting up at all. Default 10 s.")
    ElseIf option == _achConfirmOID
        SetInfoText("NPCs ONLY: hard ceiling on how long an abandoned, unattended down lasts before they get up on their own - NPCs have no get-up key, so this stands in for it. The PLAYER never auto-recovers: get-up key, being helped, or winning a QTE are the only ways up. Resets to the full duration whenever someone interacts with the victim (a struggle, choke, inspect, escalation, etc.), so it never expires mid-scene. Default 600 s (10 min).")
    ElseIf option == _achHandoffOID
        SetInfoText("When a downed actor is about to recover because nobody's around, give Baka's creature-escalation pipeline one shot at taking them first, instead of just calming the creature and standing them up. Requires Baka's own 'Creature Escalation' switch (and, for the player, 'Can Target the Player') to ALSO be on in Baka's MCM - this only gates the attempt on the Acheron side. Default ON; harmless if Baka is absent or its own switches are off.")
    ElseIf option == _achGetUpKeyOID
        SetInfoText("Hold this key for 3 seconds while downed (by any means) to attempt a struggle QTE and stand up on your own, independent of any NPC or LLM ever helping you up. Winning frees you immediately with a cue; losing fires its own 'tried and failed' cue so the LLM can react. Default: Comma.")
    ElseIf option == _achEngageOID
        SetInfoText("Chance a nearby creature bothers engaging at all once nobody able is around, rolled fresh every confirm cycle - not one-shot. After a scene ends, it can roll again and re-engage. At 100% this can loop indefinitely by design; lower it if you want downed actors to reliably get free. Default 50%.")
    ElseIf option == _achDebugOID
        SetInfoText("Write the Acheron bridge's detailed traces to the Papyrus log. Keep ON while testing/reporting issues; turn OFF for less script-engine load during normal play.")
    ElseIf option == _stEnabledOID
        SetInfoText("Master switch for the SlaveTats degradation-set module. When off, no event applies any set. The spank-heat marks Baka itself applies are separate and unaffected.")
    ElseIf option == _stSpankOID
        SetInfoText("Apply your chosen degradation set alongside Baka's own spank-heat marks when an actor is spanked. Choose the set in the SlaveTats menu (MCM -> Plugins -> Refresh, then in-game SlaveTats menu). Default ON once a set is chosen.")
    ElseIf option == _stDefeatOID
        SetInfoText("Apply your chosen degradation set when an actor is downed/defeated. Default ON once a set is chosen.")
    ElseIf option == _stEscalOID
        SetInfoText("Apply your chosen degradation set at the escalation handoff (the moment a scene starts). Default OFF. Needs a set chosen in the SlaveTats menu.")
    ElseIf option == _stRefreshOID
        SetInfoText("Rebuild the SlaveTats pack cache from disk. Use after enabling or disabling a tattoo pack in MO2 (MO2 closed, or enabled before launching). Picks up newly visible packs without a game restart.")
    ElseIf option == _stPickOID
        SetInfoText("Open the in-game SlaveTats set picker (choose which degradation set each event applies: spank / defeat / escalation).")
    ElseIf option == _stStatusOID
        SetInfoText("Number of tattoo sections SlaveTats discovered in the last Refresh. Sets are picked in the SlaveTats menu, not typed here.")
    ElseIf option == _stDefaultColorOID
        SetInfoText("Module-wide default color for applied marks (0xRRGGBB). Used when a path doesn't specify a color (LLM actions, event hooks without a per-channel color). The picker's per-pick and per-slot colors override it. 'Pack Default' = no recolor. Click to cycle.")
    ElseIf option == _stRemoveOnReleaseOID
        SetInfoText("Strip the module's degradation marks when a captive is genuinely released (the Release action). Only marks THIS module applied - Baka's own spank heat marks are untouched. Default ON.")
    ElseIf option == _stObserveOID
        SetInfoText("Periodic ambient cue (~every 4 game hours) that a marked actor still wears their degradation marks, so nearby personas can notice and react without polling. Only fires when module-applied marks exist. Default ON.")
    ElseIf option == _execGateOID
        SetInfoText("How much the player is asked before an NPC executes a downed victim. Unlimited: never asked (default). Companions ask: your companions ask first - everyone else acts freely. Always ask: every execution asks first. Your own downed-menu Execute button is never gated.")
    EndIf
EndEvent

;  — default-color palette shared by the MCM cycle and the picker swatches.
Int[] Function _ST_ColorPalette()
    Int[] palette = new Int[9]
    palette[0] = 0x000000      ; sentinel 0 = pack default (stored key value 0)
    palette[1] = 0x1a1a1a      ; Black
    palette[2] = 0x8b1a1a      ; Red
    palette[3] = 0xb01030      ; Crimson
    palette[4] = 0x550a0a      ; Dark Red
    palette[5] = 0x1a1a8b      ; Blue
    palette[6] = 0x1a6b1a      ; Green
    palette[7] = 0x5a1a8b      ; Purple
    palette[8] = 0xc05a8b      ; Pink
    Return palette
EndFunction

String Function _ST_ColorLabel(Int aiColor)
    If aiColor == 0
        Return "Pack Default"
    ElseIf aiColor == 0x1a1a1a
        Return "Black"
    ElseIf aiColor == 0x8b1a1a
        Return "Red"
    ElseIf aiColor == 0xb01030
        Return "Crimson"
    ElseIf aiColor == 0x550a0a
        Return "Dark Red"
    ElseIf aiColor == 0x1a1a8b
        Return "Blue"
    ElseIf aiColor == 0x1a6b1a
        Return "Green"
    ElseIf aiColor == 0x5a1a8b
        Return "Purple"
    ElseIf aiColor == 0xc05a8b
        Return "Pink"
    EndIf
    Return "Custom (0x" + SNBaka_SlaveTatsModule._IntToHex(aiColor) + ")"
EndFunction

;  SlaveTats toggle helper — flips a player-keyed SNBaka.ST.* int between 1 and 0.
Function _ST_Toggle(String asKey, Int aiOID, Int aiDefault)
    Actor p = Main.PlayerRef
    If !p
        p = Game.GetPlayer()
    EndIf
    Int v = 1 - StorageUtil.GetIntValue(p, asKey, aiDefault)
    StorageUtil.SetIntValue(p, asKey, v)
    SetToggleOptionValue(aiOID, v == 1)
EndFunction
