Scriptname DeD_MCM extends SKI_ConfigBase

; ============================================================================
; DeD_MCM (renamed from SNBaka_MCM at REV-107) — REV-76 REPLACEMENT MCM quest
; ("Delectatio et Dominium").
;
; Lineage: the direct successor of SkyrimNet_BakaIntegration_MCM (the v7 MCM).
; The old quest was neutered at REV-76 (script detached, record kept; its
; cached save-instance was pathological beyond version dispatch — see
; PROJECT_STATE §75/§76). This quest is a FRESH formID (QUST 04000D99): an
; existing save spins up a fresh instance and registers fresh.
;
; CANARY RULE (user ruling, REV-76 — standing for every MCM-touching build):
;   - versioned marker key  SNBaka.MCMDeD.vN  (written once, first registration)
;   - load-time self-check sentinel: ONE greppable "[SNBaka] MCM canary" line
;     at first registration AND at every OnGameReload delivery (which doubles
;     as the SKI_PlayerLoadGameAlias delivery probe — the exact event the old
;     quest never received).
;   - every MCM-touching revision's dogfood includes the EXISTING-SAVE RENDER
;     GATE (old save: all pages render, all sections present).
;
; CLEAN BASELINE (user ruling): version restarts at 1; post-replacement
; updates flow through GetVersion -> OnVersionUpdate on this baseline. The
; old quest's v5/v6/v7 migration markers are NOT re-run here (the saves that
; crossed those revs carry the markers already; they are probes, not data).
;
; Settings: zero migration (REV-76 Task-1 audit) — all player state lives in
; StorageUtil (SNBaka.*, SNBaka.ST.*, SNAcheron.*, player-keyed) or as
; properties on the surviving MAIN quest (04000D62). Known pre-existing skew
; (fEscapeGraceDuration dual-write, old script L793) carried unchanged.
; ============================================================================

; ============================================================================
; REV-106 SEVERANCE (user ruling of record 2026-10-1X, "Boundary S4a" - the SHAPE
; OF RECORD): the MCM quest is the FRAMEWORK's config surface - every module hangs
; its pages on it presence-gated; Baka's settings become module pages like any
; other; the eventual PHYSICAL host is a DeD Framework esp (S4b, esp session -
; this session is script-only, no esp bytes, scriptname/EDID unchanged; the rename
; rides S4b). Task 1.1: the MCM stops using the compiled `Main` property (the esp
; VMAD auto-fill link is what kept the MCM hostage to the motherboard quest) and
; resolves the motherboard AT RUNTIME via GetFormFromFile(0xD62, Baka esp) + cast
; - the same resolution pattern as SkyrimNet_BakaIntegration.GetMain (that script,
; L1207) and SkyrimNet_BakaInteg_SpankPartner (L13). Absent motherboard = None =
; the Baka pages don't build (§74 precedent); the MCM itself lives on. Setting
; storage is UNCHANGED (§73/§75 discipline: no new migration; the resolver hands
; back the exact same quest instance the compiled link used to).
; NOTE (physical reachability, recorded §112): today the MCM quest record and the
; motherboard quest record are co-homed in SkyrimNet_BakaIntegration.esp, so the
; absent-motherboard state is not physically reachable until S4b moves the MCM
; quest record to the framework esp. This machinery is the logical re-home; the
; S4b gate activates it.
; ============================================================================

; ============================================================================
; REV-107 S4b (the PHYSICAL re-home): the MCM quest record MOVED from
; SkyrimNet_BakaIntegration.esp (QUST 04000D99) to the NEW DeD_Framework.esp
; (fresh formID 02000800, masters Skyrim+Update ONLY). Scriptname + EDID renamed
; SNBaka_MCM -> DeD_MCM; the esp VMAD re-binds the renamed script with ZERO
; compiled properties (the S4a resolver is the only motherboard link now; the
; old VMAD's stale `main` property binding is not carried over).
; IDENTITY BOUNDARY (byte-verified this rev): ModName "Delectatio et Dominium",
; all StorageUtil keys (SNBaka.*, SNBaka.ST.*, SNAcheron.*), all "[SNBaka] *"
; log markers, and every GetFormFromFile literal are UNCHANGED — the rename
; touches the script FILE only, exactly like the LoadAlias-era lesson.
; Existing-save expectation: the old 04000D99 cosave instance is orphaned on
; first load after the move (dead cached MCM config instance, KNOWN-BENIGN per
; the REV-76 replacement history; settings live in StorageUtil per §75) —
; one-session cosmetic cost; the new quest instance registers fresh.
; ============================================================================

; ============================================================================
; REV-109 MCM RESTRUCTURE (user ruling 2026-10-1X, era roadmap item 7 + the
; REV-88 planner ticket of record - the productization restructure):
;   - framework-level configurables gather under a NEW "Settings" page (first
;     page): master enable (Enable Mod, moved from General), the global action
;     cooldown (moved from General), the stuck-state reset (moved from
;     General's Maintenance section), the debug log (moved from Scenes & FX),
;     plus the title header + tagline (first-page rider, REV-76 convention).
;   - the five Baka pages fold under a "Baka Interactions" section: SkyUI
;     SKI_ConfigBase Pages[] is a FLAT left-pane list with NO sub-page
;     nesting, so the section is realized as prefixed sibling pages
;     ("Baka - General" / "Baka - Timing" / "Baka - Resist" / "Baka - Spank"
;     / "Baka - Scenes & FX"), grouped contiguously - the §81 precedent
;     (separate expandable pages, not one long page); choice FLAGGED for the
;     user gate (Task 2.1).
;   - module pages UNCHANGED in position/content (Lap Sitting / Cum Effects /
;     Fill Her Up / Acheron / SlaveTats / GS Poses).
;   - NO NEW OPTIONS (no-stubbing rule): what does not exist today (clean
;     uninstall, stop-all beyond the panic reset, framework-native settings)
;     is the REV-109 gap list (era doc; polish pool), not built here.
;   - RIDERS (user ruling 2026-10-1X): the full-surface ASCII sweep (receipt:
;     0 non-ASCII in every runtime string literal, swept comment-stripped
;     this rev) + the display-length audit (labels >40 chars / values >30
;     chars = findings; fixes per class (a) shorten / (b) label-vs-info split;
;     every reworded string -> §7 register, bulk entry).
; ============================================================================

; ============================================================================
; REV-109c MCM RESTRUCTURE PASS 3 (user ruling 2026-10-1X): the "Baka
; Interactions" page is ONE page whose body STACKS the six family sections
; (General / Timing / Resist / Spank / Scenes & FX / Lap Sitting - the
; user's own wording), each preceded by a section-header row:
;   - SUPERSESSION BANNER (not silent deletion): REV-109b's in-page
;     section-NAVIGATION model - the _biSection state, the index render,
;     the "Open" rows, the "<< Back" rows, the nav OIDs + the
;     CurrentPage-guarded handler chain - is REMOVED by this pass per the
;     user's ruling. Register entry 17a ("Open"/"<< Back" drafts) is VOIDED
;     with it: the strings it gated no longer exist.
;   - PAGE HEADER: the REV-76 title + tagline rider (carried from the
;     Settings header pair).
;   - SECTION HEADERS: the REV-80 house pattern - spacer + header row
;     (the "Auto-Apply Sets" exemplar, SlaveTats page).
;   - CENSUS (Task 1.3): every REV-109 option present EXACTLY ONCE in the
;     stacked body, zero lost, zero duplicated (before == after enforced;
;     receipt in the build record).
;   - ASCII sweep (Task 1.5): the new surfaces are the page/section header
;     rows + spacers; the six section names are the user's own list
;     (register 17b, cited not gated).
; ============================================================================

SkyrimNet_BakaIntegration Main    ; REV-106: plain member variable, NOT a compiled
                                  ; Auto property - resolved at runtime below. All
                                  ; consumer sites are unchanged (same name, same
                                  ; members); only the BINDING changed.

Bool _gsFound = False             ; REV-106: cached GS esp presence (a found state
                                  ; is permanent for a save's lifetime; an absent
                                  ; esp re-probes at the next _BuildPages - the
                                  ; GetFormFromFile-on-absent-esp hard-error rule
                                  ; cited at SNBaka_CumDetectionModule L22).

; REV-106 Task 1.1 - the motherboard resolution, presence-gated, sentinel-once:
; when found, the result is cached for the session (plugins can't change mid-run),
; so the "found" sentinel logs ONCE; when absent, _ResolveMain re-probes at every
; OnGameReload, so the "absent" sentinel logs ONCE PER LOAD (the REV-105
; busy-service probe's once-per-load discipline; grep
; "[SNBaka] MCM motherboard resolution" in Papyrus.0.log).
SkyrimNet_BakaIntegration Function _ResolveMain()
    If Main != None
        Return Main
    EndIf
    Main = Game.GetFormFromFile(0xD62, "SkyrimNet_BakaIntegration.esp") as SkyrimNet_BakaIntegration
    If Main != None
        Debug.Trace("[SNBaka] MCM motherboard resolution (REV-106 S4a): found - module pages build")
    Else
        Debug.Trace("[SNBaka] MCM motherboard resolution (REV-106 S4a): ABSENT - Baka module pages not built (framework MCM carries on)")
    EndIf
    Return Main
EndFunction

; REV-106 Task 1.3 - GS Poses presence gate (the leaked one: the page previously
; rendered unconditionally and wrote GSAnim.GenderPolicy even with the GS esp
; absent - a dead page per the §74 class). Same probe the motherboard's module-arm
; uses (SkyrimNet_BakaIntegration L9068: GetFormFromFile(0xD61, GS esp)). Log-only
; sentinel; no player-facing text.
Bool Function _GSInstalled()
    If _gsFound
        Return True
    EndIf
    If Game.GetFormFromFile(0xD61, "SkyrimNet_AnimationsGS.esp") != None
        _gsFound = True
        Debug.Trace("[SNBaka] MCM GS-poses probe (REV-106 S4a): present")
        Return True
    EndIf
    Debug.Trace("[SNBaka] MCM GS-poses probe (REV-106 S4a): absent - GS Poses page not built")
    Return False
EndFunction


Int _enabledOID = -1
Int _panicOID = -1
Int _lapSitOID = -1
Int _playerTargetOID = -1
Int _femaleOnlyOID = -1
; REV-145 (baka-daemon.md REV-144 SS-B/SS-D): the ambient daemon controls.
; REV-146a (user ruling: Prisma ONLY): _mephalaOID/_molagBalOID RETIRE -
; the MCM toggles are GONE; the Prisma footer buttons (numeric 900/901)
; are the only mode surface. _ambientSexOID = the three-level target-sex
; dropdown (ruling (c), the SS-C fold).
Int _mephalaOID = -1
Int _molagBalOID = -1
Int _ambientSexOID = -1
Int _execGateOID = -1      ; REV-93 Task 1: ported from the DEAD v7 script (REV-92 built it there by
                      ; mistake — SkyrimNet_BakaIntegration_MCM is the neutered pre-REV-76 quest;
                      ; THIS quest is the live MCM). Levels: 0 Unlimited / 1 Companions ask /
                      ; 2 Always ask; key SNBaka.ExecuteGateLevel (player-keyed StorageUtil).
                      ; REV-94 Task 2.2: DEFAULT = 0 (Unlimited) USER-CONFIRMED 2026-10-11
                      ; (literal default in _ExecGateLevel below and in _ExecuteGateLevel on
                      ; the integration side: GetIntValue(..., 0) both).
Int _animatedTearsOID = -1
Int _hugDurOID = -1
Int _molestDurOID = -1
Int _kissDurOID = -1
Int _touchDurOID = -1
Int _stageDurOID = -1
Int _cooldownOID = -1
Int _resistEnabledOID = -1
Int _resistDifficultyOID = -1
Int _npcEscapeChanceOID = -1
Int _npcStageTimeOID = -1
Int _escalationWindowOID = -1
Int _escalationDifficultyOID = -1
Int _qteKeysOID = -1        ; REV-109 length audit (class (b) split): the QTE-keys
                            ; text option gains an OID purely to carry its detail
                            ; in InfoText (label short, detail in the info).
Int _spankPlayerOID = -1
Int _spankMaleOID = -1
Int _spankFurnitureOID = -1
Int _spankTatIntensityOID = -1
Int _spankHealFactorOID = -1
Int _sexBackendOID = -1
Int _expressionsOID = -1
Int _exprIntensityOID = -1
Int _creatureEscOID = -1
Int _creatureOnPCOID = -1
Int _creatureCombatOID = -1
Int _creatureFollowerHitOID = -1
Int _creatureSceneOID = -1
Int _llmGateOID = -1
Int _tattooAskOID = -1    ; [REV-178e rider 4 / S250] LLM tattoo selection kill-switch row
Int _bakaCaseCueOID = -1  ; [REV-179 Leg 2] SNBaka.CaseInCue compose-time toggle row
Int _notifyOID = -1
Int _debugLogOID = -1
Int _creatureVictimSexOID = -1
Int _creatureBackendOID = -1
Int _creatureSuccessOID = -1
Int _creatureHitChanceOID = -1
Int _humanOnHitOID = -1
Int _humanHitChanceOID = -1
Int _escapeGraceOID = -1
Int _creatureStruggleDurOID = -1
Int _creatureGraceOID = -1
Int _creatureGroupSizeOID = -1
Int _sellSlaveryOID = -1
Int _followerSlaveryOID = -1
Int _slaveryDistOID = -1
Int _tiedHoursOID = -1
; REV-63 detection + inflation triggers (own pages since REV-80: Cum Effects / Fill Her Up)
Int _cumDetectOID = -1
Int _decalOID = -1     ; REV-134d: Decal Source Selection dropdown (retires the _slProxyOID toggle)
Int _fhuAwareOID = -1
; REV-153: Follow-up Prompt on the Fill Her Up page (the REV-134f pattern
; applied to FHU; label/tooltip DRAFT per the user's exchange shape -- "a
; similar format to the cum detection prompt + optional direct narration
; trigger", register-cited, entry 33) -- the MCM gate for the optional
; inflation-cue direct narration (motherboard property bFHUInflateNarration,
; default OFF; the gated sdb_fhu_inflate_narr event type + its yaml carry the
; register entry-33 guidance DRAFT).
Int _fhuNarrOID = -1
; REV-154: FHU ambient bystander cues on the Fill Her Up page (the planner's
; 30%/60% expose bands, the cum-ambient pattern applied to FHU; the 153/134f
; Follow-up Prompt pattern for the narration second surface): the
; "Ambient Narration" toggle (motherboard bFHUAmbientNarration, DEFAULT OFF;
; gated sdb_fhu_ambient_narr event type + its yaml carry the register
; entry-34 guidance DRAFT) + the two band-floor sliders (percents of FHU
; maxInflation; planner defaults 30/60; label/tooltip DRAFTs, register
; entry 34 -- the C5 ruling: planner values = defaults, MCM = the user valve).
Int _fhuAmbNarrOID = -1
Int _fhuNoticeOID = -1
Int _fhuHeavyOID = -1
; REV-161 4.4: the FHU ambient cadence slider (key SNBaka.FHUAmbientCadence,
; default 60s = the REV-154 historic cadence; label = register DRAFT).
Int _fhuAmbCadOID = -1
; REV-159 5.1/5.2 (user-ruled at the dogfood): the Baka-side mode-narration
; toggles + cadence sliders on the Baka Interactions page (Ambient Modes
; section). Narration toggles = motherboard properties bMephalaModeNarration
; / bMolagBalModeNarration (DEFAULT OFF; the gated second surface for daemon
; mode-action executions, 134f pattern; labels/tooltips = register entry 37
; DRAFTs). Cadence sliders = StorageUtil keys SNBaka.MephalaCadence /
; SNBaka.MolagBalCadence (15s-240s; defaults 45/15, read live at every arm +
; tick -- no re-arm needed).
; [REV-174 D3 LEG 4] _mephNarrOID/_molagNarrOID REMOVED with the motherboard
; narration properties (the reaction lanes + their per-lane toggles are the surface)
Int _mephCadOID   = -1
Int _molagCadOID  = -1
; REV-167 t3 (entry 44, §3.4/§5-2.5): the selection surfaces. Baka
; Interactions gains the Molag's Madness + Banded Actions toggles
; (the Madness/Banded keys RETIRED at REV-174; any stored value is inert),
; the four Baka-mode subject/target dropdowns (SNBaka.MephalaSubject/
; Target, SNBaka.MolagBalSubject/Target, DEFAULT 0 = Random = shipped
; behavior), and the Target Link Weight slider (SNBaka.TargetLinkWeight
; float, DEFAULT 70). GS Poses gains the four GS-mode dropdowns
; (GSAnim.SanguineSubject/Target, GSAnim.SheogorathSubject/Target) and
; the Sheogorath Selection toggle (GSAnim.SheoSelection, DEFAULT ON =
; Perverse Fit -- the runtime default already holds). Labels + tooltips
; are register entry 44 DRAFTs (the user's pen). [REV-174 A3/D1] the
; Madness + Banded toggle OIDs are RETIRED with the toggles.
Int _mephSubOID      = -1
Int _mephTgtOID      = -1
Int _molagSubOID     = -1
Int _molagTgtOID     = -1
; [REV-178 L3] the per-mode Selection Method dropdown OIDs (above the pools)
Int _mephMethodOID   = -1
Int _molagMethodOID  = -1
Int _sangMethodOID   = -1
Int _sheoMethodOID   = -1
; [REV-174a A36c] _linkWtOID RETIRED with the Target Link Weight slider (RP is
; prompt-side now, A36a; the two-tier weighted draws retired with it). The
; member stays declared per the REV-146a never-bound (-1) no-op convention.
Int _linkWtOID       = -1
; [REV-174a A34b] per-module player-target toggles: Baka's "NPCs May Target
; You" stays on its page (REV-145 home); GS gains "Player can be targeted"
; on the GS Poses page (GSAnim.PlayerTargetable, the exact key the roster
; gate + _PoseVibe guard read). [REV-174a D4] Settings-page Debug
; Notifications (shared GSAnim.DebugNotify key, default OFF).
Int _gsPlayerTgtOID  = -1
Int _gsCaseCueOID    = -1    ; [REV-179 Leg 2] GSAnim.CaseInCue compose-time toggle row
Int _gsDebugNotifyOID = -1
Int _sangSubOID      = -1
Int _sangTgtOID      = -1
Int _sheoSubOID      = -1
Int _sheoTgtOID      = -1
Int _sheoSelOID      = -1
; REV-159 5.1/5.2/5.3 -> [REV-174e Leg 4]: the Sanguine + Sheogorath
; mode-narration toggles REMOVED (2026-10-31 user ruling, decoupled from cadence;
; keys GSAnim.SanguineModeNarr/GSAnim.SheogorathModeNarr orphaned, no migration; the
; fanned-out lane toggles are the sole narration gate); the cadence sliders
; (GSAnim.NudgeInterval of record 137f / GSAnim.T3Interval, 15s-240s), and
; the three per-route pose-narration toggles (DEFAULT ON, current behavior
; preserved; TITLES USER-AUTHORED per the 137f rider, register-cited:
; "Sanguine Pose Narration" / "Emergent Pose Narration" / "Player Initiated
; Pose Narration"; tooltips = register entry 37 DRAFTs with the lean
; "narration cue" resolution).
; [REV-174e Leg 4] _sangNarrOID/_sheoNarrOID REMOVED with the Mode Narration
;   toggles (keys orphaned, no migration; Reaction Lanes = sole gate surface)
Int _sangCadOID       = -1
Int _sheoCadOID       = -1
; [REV-174d Leg 3.2] _poseNarrSangOID RETIRED with the "Sanguine Pose Narration" toggle
;   (REV-174a D3 lanes-only; key GSAnim.PoseNarrSanguine orphaned, no migration).
Int _poseNarrEmOID    = -1
Int _poseNarrPlOID    = -1
; [REV-178b Leg 2.3] the pose reaction-lane toggles (GS Poses page).
Int _gsPoseLaneNarrOID     = -1
Int _gsPoseLaneThoughtOID  = -1
Int _gsPoseLanePSpeechOID  = -1
Int _gsPoseLanePThoughtOID = -1
; [REV-174 D3 A15] REACTION-LANE toggles -- the master + 8 Baka lane
; properties (Baka Interactions page) + the GS master/lane StorageUtil keys
; (GS Poses page). ALL ON by default (R-LANE-DEFAULTS; A15). Labels/tooltips
; are register DRAFTs at the user's pen.
Int _reactArbOID          = -1
Int _mephLaneNarrOID      = -1
Int _mephLaneThoughtOID   = -1
Int _mephLanePSpeechOID   = -1
Int _mephLanePThoughtOID  = -1
Int _molagLaneNarrOID     = -1
Int _molagLaneThoughtOID  = -1
Int _molagLanePSpeechOID  = -1
Int _molagLanePThoughtOID = -1
; [REV-174f Leg 4.4] Baka ACTION lanes (neutral fanned set; None-keyed
; SNBaka.Action.Lane_* StorageUtil keys, defaults narr/pspeech/pthought ON,
; thought OFF per the A15 mirror; register DRAFT).
Int _bakaActLaneNarrOID    = -1
Int _bakaActLaneThoughtOID = -1
Int _bakaActLanePSpeechOID = -1
Int _bakaActLanePThoughtOID = -1
Int _gsReactArbOID        = -1
Int _gsSangLaneNarrOID    = -1
Int _gsSangLaneThoughtOID = -1
Int _gsSangLanePSpeechOID = -1
Int _gsSangLanePThoughtOID = -1
Int _gsSheoLaneNarrOID    = -1
Int _gsSheoLaneThoughtOID = -1
Int _gsSheoLanePSpeechOID = -1
Int _gsSheoLanePThoughtOID = -1

; REV-134c: More Cum (register 24, ruled at REV-133c but mis-built into the RETIRED
; v7 script -- the §148 wrong-script root cause) is finally built HERE, in the live
; script. Default OFF (user ruling, REV-134c; motherboard property bMoreCumEnabled
; flipped to False in the same rev).
Int _moreCumOID = -1
; REV-134f: Follow-up Prompt (user-ruled dogfood 2026-10-21, name + tooltip
; verbatim) -- the MCM gate for the optional ambient-cue direct narration
; (motherboard property bCumFollowUpNarration, default OFF; the gated
; sdb_cum_ambient_narr event type + its yaml carry the register entry-22 text).
Int _cumFollowUpOID = -1
; REV-161 4.4: the cum ambient cadence slider (key SNBaka.CumAmbientCadence,
; default 60s = the REV-122 historic cadence; the accept re-arms the rule live).
Int _cumAmbCadOID = -1
; REV-68 "Downed State (Acheron Bridge)" settings (own "Acheron" page since REV-79) — consolidated from the
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
; REV-72 "SlaveTats Degradation Sets" section (own "SlaveTats" page since REV-79) — SNBaka_SlaveTatsModule state
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
; REV-74 Task 4 — color / release / observation additions (SNBaka.ST.* keys, module defaults).
Int _stDefaultColorOID
Int _stRemoveOnReleaseOID
Int _stObserveOID
; REV-156 — ambient exposure pass surfaces (the daemon-tick consumer of
; ResolveVisibility; the REV-74 Observe toggle is FOLDED to it as master
; gate). Register entry 35 DRAFTs (labels/tooltips at the user's pen).
Int _stAmbientPctOID     ; "Ambient Exposure Chance" (SNBaka.ST.AmbientPct, default 35)
Int _stAmbientNarrOID    ; "Tattoo Ambient Narration" (SNBaka.ST.AmbientNarr, DEFAULT OFF)
Int _stAmbFloorOID       ; REV-161 4.4: "Tattoo Ambient Cue Interval" (SNBaka.ST.AmbientFloor, DEFAULT 600s)
; REV-85 Phase B — GS Poses top-level page: the gender policy mode selector
; (GSAnim.GenderPolicy StorageUtil int on None; 0 = female-only default).
Int _gsGenderPolicyOID = -1
Int _stIntroOID = -1        ; REV-109 length audit (class (b) split): the ST intro
                            ; text option - short label, full sentence in InfoText.
Int _gsIntroOID = -1        ; REV-109 length audit (class (b) split): the GS Poses
                            ; intro text option - same shape.
; REV-109c: the REV-109b in-page navigation state + nav OIDs (_biSection,
; _biBackOID, _biNav*OID) are REMOVED with the navigation model per the
; pass-3 ruling (supersession banner at the file header). The stacked body
; renders every section unconditionally - no section state, no nav OIDs.

Event OnConfigInit()
    ModName = "Delectatio et Dominium"
    _ResolveMain()   ; REV-106 S4a: runtime motherboard resolution BEFORE the page build
    _BuildPages()
    ; REV-76 canary — first-registration sentinel (one-time, per-player): versioned
    ; marker + the one greppable line. Grep "[SNBaka] MCM canary" in Papyrus.0.log.
    StorageUtil.SetIntValue(Game.GetPlayer(), "SNBaka.MCMDeD.v1", 1)
    Debug.Trace("[SNBaka] MCM canary: Delectatio et Dominium registered (v" + GetVersion() + ", pages=" + Pages.Length + " [incl Acheron + SlaveTats], Main=" + Main + ")")
EndEvent

; SkyUI MCM quests DO reliably receive OnGameReload on every load — unlike a bare Quest, whose
; OnPlayerLoadGame never fires. So we use it to re-run the main quest's Setup() on every load, which
; re-asserts the decorator + mod-event registrations (RegisterForModEvent does NOT survive save/load).
; This is what makes the creature hand-off and the AEL/menu events work after a reload.
Event OnGameReload()
    Parent.OnGameReload()
    _ResolveMain()   ; REV-106 S4a: re-probe per load while the motherboard is absent
                     ; (once-per-load sentinel; a found result is cached, never re-probed)
    ; REV-76 canary — load-time self-check sentinel (doubles as the alias-delivery
    ; probe: this event is dispatched via SKI_PlayerLoadGameAlias, the exact event
    ; the OLD quest's instance never received on the Hadrian save; grep
    ; "[SNBaka] MCM canary reload").
    Debug.Trace("[SNBaka] MCM canary reload: OnGameReload delivered, Main=" + Main)
    If Main
        Main.Setup()
    EndIf
EndEvent

; ============================================================================
; VERSION — REV-76 CLEAN BASELINE (user ruling): this quest is a fresh
; replacement (QUST 04000D99), so the version restarts at 1. An existing save
; has no cached state for THIS quest's formID — everything OnConfigInit builds
; is fresh, so no v-bump is needed for the replacement itself. Future content
; changes to pages/options bump this number (the canonical path from here;
; the SkyUI version-field lesson documented at length in the old script's
; header applies unchanged).
; The old quest's v1..v7 lineage (REV-68 Acheron consolidation, REV-72
; SlaveTats section, REV-74 color/release/observation) is history — see
; PROJECT_STATE §75/§76. Migration markers are NOT re-run: zero migration
; was the audit's ruling (Task 1), and old markers stay as dogfood probes.
; ============================================================================
Int Function GetVersion()
    ; REV-79: FIRST canonical bump on the REV-76 clean baseline (v1 -> v2) —
    ; the MCM restructure is user-visible (Acheron + SlaveTats promote to
    ; top-level pages), which is exactly what this machinery exists for.
    ; REV-80: SECOND canonical bump (v2 -> v3) — the Plugins page DISSOLVES:
    ; each integration becomes its own top-level page (user ruling); the
    ; SlaveTats page's set-assignment section is retitled "Auto-Apply Sets"
    ; (configuration-vs-picker clarity, §7-approved copy).
    ; REV-85: THIRD canonical bump (v3 -> v4) — the "GS Poses" top-level page
    ; joins (gender policy home, posing-gender.md §2b; page-count 10 -> 11).
    ; REV-93: FOURTH canonical bump (v4 -> v5) — the Execute-gate option
    ; (REV-92, mis-built in the DEAD v7 script) is ported into THIS live
    ; script's General page (dogfood-failure fix; wrong-script defect).
    ; REV-106: FIFTH canonical bump (v5 -> v6) — S4a severance: the MCM becomes the
    ; framework's config surface; pages go presence-gated (motherboard resolution for
    ; the 8 Baka pages, GS esp probe for GS Poses). Page STRUCTURE is now combo-
    ; dependent, so every pre-severance save crosses this bump once and rebuilds.
    ; REV-107: SIXTH canonical bump (v6 -> v7) — S4b physical re-home: the quest
    ; record moves to DeD_Framework.esp (02000800) and the script/EDID rename to
    ; DeD_MCM. No page/OID change; the bump exists for the fresh-instance canary
    ; (every existing save spins the moved quest's fresh instance and crosses it).
    ; REV-109: SEVENTH canonical bump (v7 -> v8) — the productization MCM
    ; restructure: a new first "Settings" page; the five Baka pages renamed into
    ; the "Baka - " section prefix; page-count 11 -> 12 (Main+GS combo). Page
    ; STRUCTURE changed, so every existing save crosses this bump once and
    ; rebuilds (the four-saga rule; the v2 canary lesson applies - rebuild
    ; before the canary trace).
    ; REV-109b: EIGHTH canonical bump (v8 -> v9) - the Option A restructure
    ; fix: the five "Baka - " prefix pages + the Lap Sitting page fold into
    ; ONE "Baka Interactions" page hosting six in-page sections; page-count
    ; 12 -> 7 (Main+GS combo). Page STRUCTURE changed, so every existing
    ; save crosses this bump once and rebuilds (the four-saga rule; rebuild
    ; before the canary trace, the v2 lesson standing).
    ; REV-109c: NINTH canonical bump (v9 -> v10) - restructure pass 3: the
    ; section NAVIGATION model is removed; the six sections STACK in the one
    ; page body under section headers. Page COUNT is unchanged (7/6), but
    ; the page BODY structure changed, so every existing save crosses this
    ; bump once and rebuilds (the four-saga rule; v2 lesson standing).
    ; REV-134c: TENTH canonical bump (v10 -> v11) - the More Cum toggle joins
    ; the Cum Effects page (register 24, ruled; mis-built into the retired
    ; v7 script at REV-133c, §148 root cause) and every Cum-page option
    ; gains a plain-language description row. New option on an existing
    ; page + visible body change: every existing save crosses this bump
    ; once and rebuilds. No data migration (motherboard property only,
    ; default flipped to OFF by user ruling).
    ; REV-134d: ELEVENTH canonical bump (v11 -> v12) - THE MCM REDESIGN
    ; (user-ruled R2): "Cum Cues" renamed to "Cum Cues Module Toggle"; the
    ; "SexLab Climax Proxy Share" toggle RETIRED (replaced by the
    ; "Decal Source Selection" cycling menu option, presence-gated); the
    ; REV-134c static subtext rows REMOVED in favor of info-text tooltips.
    ; Visible body change on an existing page: every existing save crosses
    ; this bump once and rebuilds (the four-saga rule; v2 lesson standing).
    ; KEY MIGRATION (flagged, default-fresh per the user's OCum-default
    ; ruling): bSLProxyEnabled is NOT migrated to iDecalSource -- the
    ; dropdown starts at 0/OCum on every save.
    ; REV-145: TWELFTH canonical bump (v12 -> v13) - THE BAKA-DAEMON SESSION:
    ; the Ambient Modes section (Mephala Mode / Molag Bal Mode toggles) joins
    ; the Baka Interactions page; "NPCs May Target You" (the REV-144 central
    ; player-target policy, entry-30a DRAFT label) replaces "Player Can Be
    ; Target"; "Ambient Target Policy" (the three-level target-sex dropdown,
    ; ruling (c)) replaces "Target Sex"; the fold-in rows ("Player Can Be
    ; Spanked", "Allow Male Targets", "Victim Sex Allowed") are REMOVED (the
    ; motherboard properties stay declared). Visible body change on existing
    ; pages: every existing save crosses this bump once and rebuilds (the
    ; four-saga rule; v2 lesson standing).
    ; REV-153: FOURTEENTH canonical bump (v14 -> v15) - the Follow-up Prompt
    ; toggle joins the Fill Her Up page (the 134f Follow-up Prompt pattern
    ; applied to FHU; label + tooltip are register entry-33 DRAFTs at the
    ; user's pen). New option on an existing page + visible body change:
    ; every existing save crosses this bump once and rebuilds (the four-saga
    ; rule; v2 lesson standing). No data migration (motherboard property
    ; only, default OFF).
    ; REV-154: FIFTEENTH canonical bump (v15 -> v16) - the FHU ambient
    ; bystander surfaces join the Fill Her Up page (the "Ambient Narration"
    ; toggle + the Noticeable/Heavy band sliders; labels + tooltips are
    ; register entry-34 DRAFTs at the user's pen). New options on an existing
    ; page + visible body change: every existing save crosses this bump once
    ; and rebuilds (the four-saga rule; v2 lesson standing). No data
    ; migration (motherboard properties only; narration defaults OFF, bands
    ; default to the planner values 30/60).
    ; REV-159: SEVENTEENTH canonical bump (v16 -> v17) - THE POLISH SESSION
    ; (dogfood fixes + build-out): (3.2b) the FHU awareness toggle RETITLED
    ; "Module Toggle - Fill Her Up Awareness" with its three-row subtext
    ; retired to a SetInfoText tooltip (user-provided verbatim); (3.2c) the
    ; duplicate "Bedroom drama for SkyrimNet" tagline REMOVED from the Baka
    ; Interactions page; (5.1) the Mephala/Molag Bal Mode Narration toggles +
    ; (5.2) the Mephala/Molag Bal cadence sliders join the Baka Interactions
    ; page; (5.1/5.2/5.3) the GS Poses page gains the Sanguine/Sheogorath
    ; narration toggles + cadence sliders + the three USER-AUTHORED pose-
    ; narration toggles. Visible body change on existing pages: every existing
    ; save crosses this bump once and rebuilds (the four-saga rule; v2 lesson
    ; standing). No data migration (new keys all default to their historic
    ; behavior; narration toggles default OFF, pose-narration toggles default
    ; ON).
    ; REV-161: EIGHTEENTH canonical bump (v17 -> v18) - the ambient cadence
    ; sliders (one per module page, the 159 slider pattern; labels = register
    ; DRAFTs at the user's pen; defaults unchanged): Fill Her Up page gains
    ; the FHU Ambient Cue Interval slider (key SNBaka.FHUAmbientCadence,
    ; default 60s, read live at every pass -- no re-arm needed); Cum Effects
    ; page gains the Cum Ambient Cue Interval slider (key
    ; SNBaka.CumAmbientCadence, default 60s; the accept re-arms the DeDService
    ; ambient timer rule live); SlaveTats page gains the Tattoo Ambient Cue
    ; Interval slider (existing key SNBaka.ST.AmbientFloor, default 600s,
    ; already read live by AmbientExposurePass). Visible body change on three
    ; existing pages: every existing save crosses this bump once and rebuilds
    ; (the four-saga rule; v2 lesson standing). No data migration (all keys
    ; default to their historic behavior).
    ; REV-174: TWENTIETH canonical bump (v19 -> v20) -- the Madness +
    ; Banded Actions toggles RETIRED; Molag Bal Subject's DEFAULT flips
    ; to Bio Led (value 3, MolagBal-only this build). No data migration:
    ; stored keys read live; absent keys take the new defaults.
    ; REV-174a: TWENTY-FIRST canonical bump (v20 -> v21) -- the selection
    ; rework (A35 parity): uniform vocabularies both modules (subject
    ; Random/Companions Only/Arousal Based; target + Bio Led/Wide, minus
    ; "Companions & Player"); GS gains "Player can be targeted"; Settings
    ; gains Debug Notifications; the Target Link Weight slider RETIRED
    ;; (A36c). DATA MIGRATION runs (unlike v20): stored selection values
    ;; are remapped once (_SelVocabMigrate3) because their meanings
    ;; changed -- silent re-meaning is a doctrine violation.
    ; REV-174a A46 (closeout): TWENTY-SECOND canonical bump (v21 -> v22) --
    ; the "Wide" target option is RETIRED pre-ship (never user-facing;
    ; dropdown shrinks 7 -> 6, values renumber). _SelVocabMigrate4 remaps
    ; stored v21-space values (3 Wide -> 0 Random per A46; 4/5/6 -> 3/4/5).
    ; REV-178: TWENTY-THIRD canonical bump (v22 -> v23) -- the narrative-
    ; selection surface: per-mode Selection Method dropdown above the
    ; Subject/Target POOLS; Bio Led + Relationship Priority target options
    ; RETIRED (OR1 funeral) and Arousal Based subject option RETIRED (OR6 --
    ; arousal is a pack fact); cadence defaults 60s all modes (R9 -- default
    ; change only, stored values untouched). DATA MIGRATION runs:
    ; _SelVocabMigrate5 remaps stored pool values into the v23 space BEFORE
    ; the rebuild (silent re-meaning is a doctrine violation).
    ; REV-178b: TWENTY-FOURTH canonical bump (v23 -> v24) -- the menu
    ; restructure + selection-spread instruction + GS pose reaction lanes:
    ; GS page "Pose Narration" renamed "General Pose Reactions" (toggles
    ; relabeled "...Pose Reactions"); NEW "Reaction Lanes" pose section
    ; (arbitration master moved up + 4 new GSAnim.PoseLane_* toggles);
    ; "Reaction Lanes (GS)" renamed "Mode Reaction Lanes"; Baka page "Action
    ; Reaction Lanes" renamed "Reaction Lanes" + moved up (no "Action"
    ; prefix), mode section renamed "Mode Reaction Lanes". No data migration
    ; (new keys take A15-mirror defaults; renamed rows reuse their keys --
    ; one lineage, no orphans).
    ; [REV-179] v25 (render-seam + CASE compose-time toggle): canary marker -
    ; pages rebuilt FIRST (the v2 lesson, standing). No data migration (new
    ; keys GSAnim.CaseInCue / SNBaka.CaseInCue default; no rows renamed).
    Return 25
EndFunction

Event OnVersionUpdate(Int aVersion)
    ; REV-76 clean baseline: no migration blocks. Future bumps append their
    ; markers here (versioned SNBaka.MCMDeD.vN per the canary rule).
    ; REV-79 v2 (restructure): canary marker + the module-facing MCM marker
    ; lineage (SNBaka.ST.MCMv7 -> MCMv8, REV-74's convention continued).
    StorageUtil.SetIntValue(Game.GetPlayer(), "SNBaka.MCMDeD.v2", 1)
    StorageUtil.SetIntValue(Game.GetPlayer(), "SNBaka.ST.MCMv8", 1)
    ; REV-80 v3 (Plugins dissolved): canary marker + MCM marker lineage
    ; continued (MCMv8 -> MCMv9). Pages rebuilt FIRST so the canary reports
    ; the NEW page count (the v2 canary traced before _BuildPages and printed
    ; the stale cached count on existing saves — flaw noted at dogfood).
    StorageUtil.SetIntValue(Game.GetPlayer(), "SNBaka.MCMDeD.v3", 1)
    StorageUtil.SetIntValue(Game.GetPlayer(), "SNBaka.ST.MCMv9", 1)
    ; REV-85 v4 (GS Poses page): canary marker — pages rebuilt FIRST so the
    ; canary reports the NEW page count (the v2 lesson, applied by convention).
    StorageUtil.SetIntValue(Game.GetPlayer(), "SNBaka.MCMDeD.v4", 1)
    ; REV-93 v5 (Execute-gate option ported from the dead v7 script into the
    ; live General page): canary marker — pages rebuilt FIRST (the v2 lesson).
    StorageUtil.SetIntValue(Game.GetPlayer(), "SNBaka.MCMDeD.v5", 1)
    ; REV-106 v6 (S4a severance): canary marker — pages rebuilt FIRST (the v2
    ; lesson; the rebuild now resolves the motherboard + probes GS so the canary
    ; reports the new combo-dependent page set).
    StorageUtil.SetIntValue(Game.GetPlayer(), "SNBaka.MCMDeD.v6", 1)
    ; REV-107 v7 (S4b physical re-home): canary marker — record now lives in
    ; DeD_Framework.esp; ModName/keys/markers unchanged (identity boundary).
    StorageUtil.SetIntValue(Game.GetPlayer(), "SNBaka.MCMDeD.v7", 1)
    ; REV-109 v8 (productization MCM restructure): canary marker — pages rebuilt
    ; FIRST so the canary reports the NEW page count (the v2 lesson, standing).
    StorageUtil.SetIntValue(Game.GetPlayer(), "SNBaka.MCMDeD.v8", 1)
    ; REV-109b v9 (Option A restructure fix): canary marker - the six Baka
    ; family pages fold into the single "Baka Interactions" section page;
    ; the Pages rebuild below reports the 7/6-page shape (v2 lesson, standing).
    StorageUtil.SetIntValue(Game.GetPlayer(), "SNBaka.MCMDeD.v9", 1)
    ; REV-109c v10 (restructure pass 3): canary marker - the navigation model
    ; is removed; the six Baka family sections stack under section headers in
    ; the one page body; the Pages rebuild below reports the unchanged
    ; 7/6-page shape (v2 lesson, standing).
    StorageUtil.SetIntValue(Game.GetPlayer(), "SNBaka.MCMDeD.v10", 1)
    ; REV-134c v11 (More Cum + Cum-page descriptions): canary marker - pages
    ; rebuilt FIRST (the v2 lesson, standing). Marker SNBaka.MCMDeD.v11; the
    ; retired v7 script's SNBaka.MCMv8 marker (REV-133c) is NOT re-run here:
    ; that marker belonged to the wrong-lineage receipt (§148) and is history.
    StorageUtil.SetIntValue(Game.GetPlayer(), "SNBaka.MCMDeD.v11", 1)
    ; REV-134d v12 (the MCM redesign): canary marker - pages rebuilt FIRST
    ; (the v2 lesson, standing). Marker SNBaka.MCMDeD.v12.
    StorageUtil.SetIntValue(Game.GetPlayer(), "SNBaka.MCMDeD.v12", 1)
    ; REV-145 v13 (baka-daemon session): canary marker - pages rebuilt FIRST
    ; (the v2 lesson, standing). Marker SNBaka.MCMDeD.v13.
    StorageUtil.SetIntValue(Game.GetPlayer(), "SNBaka.MCMDeD.v13", 1)
    ; REV-146a v14 (dogfood fix pass): canary marker - pages rebuilt FIRST
    ; (the v2 lesson, standing). Marker SNBaka.MCMDeD.v14. The Mephala/Molag
    ; Bal MCM toggles are REMOVED (user ruling: Prisma panel ONLY); the target-
    ; sex dropdown + NPCs May Target You stay (settings, not mode controls).
    StorageUtil.SetIntValue(Game.GetPlayer(), "SNBaka.MCMDeD.v14", 1)
    ; REV-153 v15 (FHU Follow-up Prompt): canary marker - pages rebuilt FIRST
    ; (the v2 lesson, standing). Marker SNBaka.MCMDeD.v15.
    StorageUtil.SetIntValue(Game.GetPlayer(), "SNBaka.MCMDeD.v15", 1)
    ; REV-154 v16 (FHU ambient bystander cues): canary marker - pages rebuilt
    ; FIRST (the v2 lesson, standing). Marker SNBaka.MCMDeD.v16.
    StorageUtil.SetIntValue(Game.GetPlayer(), "SNBaka.MCMDeD.v16", 1)
    ; REV-159 v17 (the polish session): canary marker - pages rebuilt FIRST
    ; (the v2 lesson, standing). Marker SNBaka.MCMDeD.v17. FHU awareness
    ; retitle + tooltip; Baka tagline removal; the Baka page mode-narration +
    ; cadence rows; the GS Poses page build-out (narration toggles, cadence
    ; sliders, the three user-authored pose-narration toggles).
    StorageUtil.SetIntValue(Game.GetPlayer(), "SNBaka.MCMDeD.v17", 1)
    ; REV-161 v18 (ambient cadence sliders): canary marker - pages rebuilt FIRST
    ; (the v2 lesson, standing). Marker SNBaka.MCMDeD.v18.
    StorageUtil.SetIntValue(Game.GetPlayer(), "SNBaka.MCMDeD.v18", 1)
    ; REV-167 v19 (entry 44, the Ambient Modes selection surfaces): canary
    ; marker - pages rebuilt FIRST (the v2 lesson, standing). Marker
    ; SNBaka.MCMDeD.v19.
    StorageUtil.SetIntValue(Game.GetPlayer(), "SNBaka.MCMDeD.v19", 1)
    ; REV-174a v21 (the selection rework, A35): canary marker - pages rebuilt
    ; FIRST (the v2 lesson, standing). Marker SNBaka.MCMDeD.v21. The vocab
    ; MIGRATION runs BEFORE the rebuild (stored meanings changed).
    StorageUtil.SetIntValue(Game.GetPlayer(), "SNBaka.MCMDeD.v21", 1)
    _SelVocabMigrate3()
    ; REV-174a A46 v22 (Wide retirement): canary marker - the MIGRATION runs
    ; BEFORE the rebuild (the v21 lesson, standing). Marker SNBaka.MCMDeD.v22.
    StorageUtil.SetIntValue(Game.GetPlayer(), "SNBaka.MCMDeD.v22", 1)
    _SelVocabMigrate4()
    ; REV-178 v23 (the narrative-selection surface): canary marker - the
    ; MIGRATION runs BEFORE the rebuild (the v21 lesson, standing). Marker
    ; SNBaka.MCMDeD.v23.
    StorageUtil.SetIntValue(Game.GetPlayer(), "SNBaka.MCMDeD.v23", 1)
    _SelVocabMigrate5()
    ; REV-178b v24 (menu restructure + pose lanes + spread instruction):
    ; canary marker - pages rebuilt FIRST (the v2 lesson, standing). No data
    ; migration (new keys default; renamed rows reuse keys). Marker
    ; SNBaka.MCMDeD.v24.
    StorageUtil.SetIntValue(Game.GetPlayer(), "SNBaka.MCMDeD.v24", 1)
    ; REV-179 v25 (render-seam fixes + the CASE compose-time toggles): canary
    ; marker - pages rebuilt FIRST (the v2 lesson, standing). No data migration
    ; (new keys GSAnim.CaseInCue / SNBaka.CaseInCue default ON; no rows
    ; renamed). Marker SNBaka.MCMDeD.v25.
    StorageUtil.SetIntValue(Game.GetPlayer(), "SNBaka.MCMDeD.v25", 1)
    _BuildPages()
    Debug.Trace("[SNBaka] MCM canary: v25 OnVersionUpdate (REV-179: render-seam yaml closer strip + GSAnim.CaseInCue / SNBaka.CaseInCue compose-time toggles, default ON; pages: " + Pages.Length + ", Main=" + Main + ")")
EndEvent

; ============================================================================
; REV-79 MCM RESTRUCTURE (user ruling, §80 Task 4 item 5): each plugin
; INTEGRATION gets its own top-level page — one integration, one page. The
; two integration-scale sections left "Plugins" ("Acheron", "SlaveTats"); the
; three toggle-scale detection sections stay grouped there (Lap Sitting /
; Cum Detection / FHU Inflation — promoting each would be three near-empty
; pages; judgment call recorded in the REV-79 gate report). Every integration
; page greys out with "(mod not installed)" at PAGE level when the underlying
; mod is absent (the existing per-section presence gates, extended).
;
; REV-80 POLISH RIDER (user rulings, §81): the Plugins page is DISSOLVED —
; "one integration, one page" is now total: Lap Sitting / Cum Effects /
; Fill Her Up each promote to their own top-level page (expandable later;
; the REV-79 near-empty-pages judgment is superseded by the user ruling).
; No residual Plugins page remains. Absent states stay page-level grey-outs
; "(mod not installed)". The SlaveTats page's set-assignment section is
; retitled "Auto-Apply Sets" (it configures which set fires automatically
; per event; the in-game picker always offers the full range — §7 copy).
; ============================================================================

Function _BuildPages()
    ; REV-80: 10 pages — the Plugins page is dissolved; every integration is
    ; a top-level left-pane page (one integration, one page, expandable later).
    ; REV-85: 11 pages — "GS Poses" joins as a top-level page (gender policy
    ; home, posing-gender.md §2b ruling: MCM-page home, page-count bump).
    ; REV-106 S4a: the page set is PRESENCE-GATED (the framework-MCM ruling):
    ;   - the 8 Baka module pages build ONLY when the motherboard resolves;
    ;   - GS Poses builds ONLY when the GS esp is present (Task 1.3 — the page
    ;     previously leaked: it rendered unconditionally with the GS esp absent,
    ;     a dead page writing unread keys);
    ;   - Acheron + SlaveTats are ALWAYS present (framework pages: they carry
    ;     no motherboard dependency — see the de-Mained consumer sites).
    ; Both-installed users see the IDENTICAL 11-page set as [REV-105], ORDER
    ; preserved (the Pages array is positional). Combo table recorded §112.
    _ResolveMain()
    If Main
        ; REV-109b (Option A): ONE "Baka Interactions" page hosts the six
        ; family sections via in-page section navigation (Task 0.1 pattern;
        ; SL Defeat precedent). Pages[]: 7 (Main+GS) / 6 (Main-only). The
        ; five "Baka - " prefix pages and the Lap Sitting page are GONE as
        ; left-pane entries - replaced, not patched.
        If _GSInstalled()
            Pages    = new String[7]
            Pages[0] = "Settings"
            Pages[1] = "Baka Interactions"
            Pages[2] = "Cum Effects"
            Pages[3] = "Fill Her Up"
            Pages[4] = "Acheron"
            Pages[5] = "SlaveTats"
            Pages[6] = "GS Poses"
        Else
            Pages    = new String[6]
            Pages[0] = "Settings"
            Pages[1] = "Baka Interactions"
            Pages[2] = "Cum Effects"
            Pages[3] = "Fill Her Up"
            Pages[4] = "Acheron"
            Pages[5] = "SlaveTats"
        EndIf
    ElseIf _GSInstalled()
        ; REV-109: the Settings page rides the motherboard gate in this session:
        ; every option on it is motherboard state TODAY (the honest-scope gap
        ; list is the era doc's; framework-native settings don't exist yet), so
        ; a motherboard-less combo has no real Settings content and the page
        ; does not build (§74 dead-page precedent).
        Pages    = new String[3]
        Pages[0] = "Acheron"
        Pages[1] = "SlaveTats"
        Pages[2] = "GS Poses"
    Else
        Pages    = new String[2]
        Pages[0] = "Acheron"
        Pages[1] = "SlaveTats"
    EndIf
EndFunction

Event OnPageReset(String page)
    ; REV-106 S4a (count amended REV-109b): the module pages (Baka
    ; Interactions incl. Lap Sitting, Cum Effects, Fill Her Up) carry a motherboard presence rider —
    ; when the motherboard is absent they are never in Pages[] (see _BuildPages);
    ; this belt-and-suspenders guard makes the render bodies unreachable even if a
    ; stale cached Pages array ever named one (defensive only — no behavior delta
    ; in any combo reachable today; activates with the S4b quest-record move).
    If page == "Settings" && Main
        ; REV-109 MCM RESTRUCTURE (era roadmap item 7): the framework-level
        ; configurables page. Ships with WHAT EXISTS TODAY (the no-stubbing
        ; rule): master enable, the global action cooldown, the stuck-state
        ; reset, the debug log - all MOVED existing options (handler blocks
        ; unchanged; OIDs are position-free). The title header + tagline ride
        ; the FIRST page (the REV-76 rider, carried from General).
        ; GAP LIST (registered, era doc REV-109 section - polish pool, NOT
        ; built here): clean-uninstall; stop-all beyond the panic reset;
        ; framework-native (non-motherboard) settings.
        SetCursorFillMode(TOP_TO_BOTTOM)
        AddHeaderOption("Delectatio et Dominium")
        AddTextOption("Bedroom drama for SkyrimNet", "", OPTION_FLAG_DISABLED)
        AddEmptyOption()
        AddHeaderOption("Framework")
        _enabledOID        = AddToggleOption("Enable Mod",            Main.bEnabled)
        _cooldownOID       = AddSliderOption("AI Action Cooldown",    Main.fNPCGlobalCooldown, "{0}s")
        _debugLogOID       = AddToggleOption("Enable Debug Logging",   Main.bDebugLog)
        ; [REV-174a D4] Debug Notifications: the SHARED fire-receipt gate both
        ; modules read (GSAnim.DebugNotify, None-keyed, DEFAULT OFF -- additive;
        ; hotkey activation feedback stays ungated in the GS module itself).
        _gsDebugNotifyOID  = AddToggleOption("Debug Notifications",    StorageUtil.GetIntValue(None, "GSAnim.DebugNotify", 0) == 1)
        AddEmptyOption()
        AddHeaderOption("Maintenance")
        ; Panic button: force-clears every hold Baka (or a stale Acheron pacify) could have left on
        ; any loaded actor -- for actors stuck non-aggressive/untargetable after something went wrong.
        ; Leaves genuinely downed/defeated actors alone (HelpUp / the get-up key is their way out).
        _panicOID = AddTextOption("EMERGENCY: reset stuck actor states", "RUN")
    ElseIf page == "Baka Interactions" && Main
        ; REV-109c (user ruling, MCM restructure pass 3, 2026-10-1X): ONE page,
        ; the six family sections STACKED in the body - NO navigation, NO state
        ; machine (REV-109b's _biSection model is REMOVED per the ruling;
        ; supersession banner at the file header). Page header = the REV-76
        ; title + tagline rider (the Settings header pair); each section rides
        ; the REV-80 section-header pattern - spacer row + header row (the
        ; "Auto-Apply Sets" exemplar, SlaveTats page). Section bodies are the
        ; REV-109/109b bodies MOVED VERBATIM (+ de-indent only; Lap Sitting
        ; folds in per the user's list): census before == after, zero options
        ; lost, zero duplicated; handlers UNCHANGED - OIDs are position-free,
        ; so every option's load/save path is identical (1.4: layout + the
        ; fold + the version machinery ONLY; any settings semantics delta =
        ; STOP). Presence gating UNCHANGED: the page rides the motherboard
        ; gate (Pages[] build); the Lap Sitting toggle keeps its own grey-out.
        SetCursorFillMode(TOP_TO_BOTTOM)
        AddHeaderOption("Baka Interactions")
        ; REV-159 3.2(c) (user-ruled): the duplicate "Bedroom drama for SkyrimNet"
        ; tagline REMOVED here (it stays on the first page's Delectatio et
        ; Dominium header pair, its home of record); AddEmptyOption kept so the
        ; row layout is unchanged.
        AddEmptyOption()
        ; ---- General (the former "Baka - General" body, moved verbatim) ----
        AddHeaderOption("General")
        ; REV-145: the REV-144 fold-ins surface here. "NPCs May Target You" =
        ; the central player-target policy (SNBaka.PlayerTargetPolicy, player-
        ; keyed, default OFF) -- label/tooltip = pending-approvals entry 30a
        ; DRAFT, register-cited. "Ambient Target Policy" = the three-level
        ; target-sex dropdown (ruling (c)); the retired "Player Can Be Target" /
        ; "Target Sex" / "Allow Male Targets" / "Victim Sex Allowed" rows fold
        ; under these two (properties stay declared for save-member compatibility).
        _playerTargetOID   = AddToggleOption("NPCs May Target You", _PlayerTargetPolicyOn())
        _ambientSexOID     = AddMenuOption("Ambient Target Policy", _targetSexLevelName(Main._TargetSexLevel()))
        _animatedTearsOID  = AddToggleOption("Animated Tears",        Main.bAnimatedTearsEnabled)
        AddEmptyOption()
        ; ---- Ambient Modes (REV-145) -> REV-146a: the two mode TOGGLES are
        ; REMOVED (user ruling: the Prisma footer buttons are the ONLY mode
        ; surface); the target-sex dropdown + player-target policy above STAY
        ; (settings, not mode controls). The mode FLAGS themselves live on
        ; StorageUtil and are untouched - existing saves keep their modes.
        ; REV-159 5.1/5.2 (user-ruled at the dogfood): the mode-NARRATION
        ; toggles + the mode cadence sliders join here (settings, not mode
        ; controls -- the mode on/off surface stays Prisma-only). Labels +
        ; tooltips are register entry 37 DRAFTs (134f naming pattern); the
        ; cadence keys are read live at every arm + tick (no re-arm needed).
        AddEmptyOption()
        AddHeaderOption("Ambient Modes")
        ; [REV-174 D3 LEG 4] the two Mode Narration toggles REMOVED with the
        ; motherboard properties (reaction lanes are the live surface).
        _mephCadOID   = AddSliderOption("Mephala Tick Interval",  StorageUtil.GetFloatValue(None, "SNBaka.MephalaCadence", 60.0), "{0}s")
        _molagCadOID  = AddSliderOption("Molag Bal Tick Interval", StorageUtil.GetFloatValue(None, "SNBaka.MolagBalCadence", 60.0), "{0}s")
        ; [REV-179 Leg 2] the CASE compose-time toggle (ruling of record (c),
        ; 178d dogfood): SNBaka.CaseInCue, None-keyed, DEFAULT ON, read fresh
        ; per fire by _DaemonComposeDesc. Label + tooltip = register DRAFT.
        _bakaCaseCueOID = AddToggleOption("Reasoning Line in Cues", StorageUtil.GetIntValue(None, "SNBaka.CaseInCue", 1) == 1)
        ; REV-167 t3 (entry 44, §3.4/§15.8): the per-mode Selection block --
        ; both new toggles (DEFAULT OFF) + both Baka modes' subject/target
        ; dropdowns + the Target Link Weight slider. Labels/tooltips are
        ; register entry 44 DRAFTs. Defaults: Random/Random = shipped
        ; behavior on upgrade (§15.9); weight 70.
        ; [REV-174a A34b/D2] the REV-174a selection rework: subject menus are the
        ; uniform 3-option list (Random / Companions Only / Arousal Based --
        ; Bio Led MOVED to Target Selection; RP + the two-tier weighted draws +
        ; the Target Link Weight slider RETIRED per A36a/A36c); target menus are
        ; the uniform 7-option list. Molag Bal Subject default 3 (Bio Led,
        ; REV-174) flips to 0 (Random) -- Bio Led is target-side now.
        AddEmptyOption()
        AddHeaderOption("Mode Selection")
        ; [REV-174 A3] Madness + Banded toggles RETIRED from this page.
        ; [REV-178 L3] the narrative-selection surface: Selection Method ABOVE
        ; the Subject/Target POOLS (v23 vocab space, _SelVocabMigrate5 remaps
        ; stored values; keys reused -- one lineage, no orphans). Defaults per
        ; R1: Method = Narrative (1) for Mephala/Molag Bal; pools Everyone.
        _mephMethodOID   = AddMenuOption("Mephala Selection Method", _selMethodName(StorageUtil.GetIntValue(None, "SNBaka.MephalaSelectionMethod", 1)))
        _mephSubOID      = AddMenuOption("Mephala Subject Pool", _selSubjectName(StorageUtil.GetIntValue(None, "SNBaka.MephalaSubject", 0)))
        _mephTgtOID      = AddMenuOption("Mephala Target Pool", _selTargetName(StorageUtil.GetIntValue(None, "SNBaka.MephalaTarget", 0)))
        _molagMethodOID  = AddMenuOption("Molag Bal Selection Method", _selMethodName(StorageUtil.GetIntValue(None, "SNBaka.MolagBalSelectionMethod", 1)))
        _molagSubOID     = AddMenuOption("Molag Bal Subject Pool", _selSubjectName(StorageUtil.GetIntValue(None, "SNBaka.MolagBalSubject", 0)))
        _molagTgtOID     = AddMenuOption("Molag Bal Target Pool", _selTargetName(StorageUtil.GetIntValue(None, "SNBaka.MolagBalTarget", 0)))
        ; [REV-174a A36c] the Target Link Weight slider row REMOVED (RP is
        ; prompt-side now; no mechanical two-tier draws remain to weight).
        ; [REV-174 D3 A15] REACTION LANES (Baka modes): master + 8 lanes, ALL
        ; ON by default (motherboard properties, read FRESH per fire).
        AddEmptyOption()
        ; [REV-178b Leg 2.2] BAKA PAGE MIRROR of the GS structure: the neutral
        ;   action-lane section MOVES UP (renamed "Reaction Lanes", no "Action"
        ;   prefix; funeral for the "Action Reaction Lanes" header) and the
        ;   mode-lane section follows it renamed "Mode Reaction Lanes" (funeral
        ;   for the plain "Reaction Lanes" header as the MODE section's name).
        ;   Same visual order as GS: general/action-class lanes above mode
        ;   lanes. Labels register DRAFT at the user's pen.
        AddHeaderOption("Reaction Lanes")
        _reactArbOID          = AddToggleOption("LLM Reaction Arbitration", Main.bReactArbitration)
        ; [REV-174f Leg 4.4] ACTION LANES (neutral fanned set; fires on
        ; LLM/player-initiated interactions ONLY -- daemon/mode fires keep the
        ; mode-branded lanes below; defaults mirror A15).
        _bakaActLaneNarrOID     = AddToggleOption("Narration Lane", StorageUtil.GetIntValue(None, "SNBaka.Action.Lane_narr", 1) == 1)
        _bakaActLaneThoughtOID  = AddToggleOption("Thought Lane", StorageUtil.GetIntValue(None, "SNBaka.Action.Lane_thought", 0) == 1)
        _bakaActLanePSpeechOID  = AddToggleOption("Speech Reaction Lane", StorageUtil.GetIntValue(None, "SNBaka.Action.Lane_pspeech", 1) == 1)
        _bakaActLanePThoughtOID = AddToggleOption("Private Thought Lane", StorageUtil.GetIntValue(None, "SNBaka.Action.Lane_pthought", 1) == 1)
        AddEmptyOption()
        AddHeaderOption("Mode Reaction Lanes")
        _mephLaneNarrOID      = AddToggleOption("Mephala Narration Lane", Main.bMephalaLaneNarr)
        _mephLaneThoughtOID   = AddToggleOption("Mephala Thought Lane", Main.bMephalaLaneThought)
        _mephLanePSpeechOID   = AddToggleOption("Mephala Speech Reaction Lane", Main.bMephalaLanePSpeech)
        _mephLanePThoughtOID  = AddToggleOption("Mephala Private Thought Lane", Main.bMephalaLanePThought)
        _molagLaneNarrOID     = AddToggleOption("Molag Bal Narration Lane", Main.bMolagBalLaneNarr)
        _molagLaneThoughtOID  = AddToggleOption("Molag Bal Thought Lane", Main.bMolagBalLaneThought)
        _molagLanePSpeechOID  = AddToggleOption("Molag Bal Speech Reaction Lane", Main.bMolagBalLanePSpeech)
        _molagLanePThoughtOID = AddToggleOption("Molag Bal Private Thought Lane", Main.bMolagBalLanePThought)
        ; [REV-178b Leg 2.2] the bottom-stuck "Action Reaction Lanes" section
        ;   RETIRED (moved up + renamed above; funeral for the header + the four
        ;   "Action"-prefixed toggle labels).
        AddEmptyOption()
        AddHeaderOption("Capture")
        ; OFF removes the Sell-to-Slavery action entirely (not offered to the LLM). Detection first:
        ; with Simple Slavery Plus Plus absent the toggle renders greyed-out and inert instead of
        ; pretending the feature exists -- same plugin-presence pattern Ostim_interactions uses for
        ; Stage Flow (detect the actual .esp, gate the UI on it).
        If Main.IsSimpleSlaveryInstalled()
            _sellSlaveryOID = AddToggleOption("Allow Sell to Slavery",  Main.bSellToSlavery)
        Else
            _sellSlaveryOID = AddToggleOption("Allow Sell to Slavery (not installed)", False, OPTION_FLAG_DISABLED)
        EndIf
        ; Same presence-gated pattern for the FOLLOWER slavery action (Follower Slavery Mod). Its
        ; readiness flag only flips after the player clicks Install in FSM's own MCM.
        If Main.IsFollowerSlaveryInstalled()
            _followerSlaveryOID = AddToggleOption("Allow Follower Enslavement", Main.bFollowerSlavery)
        Else
            _followerSlaveryOID = AddToggleOption("Follower Enslavement (not installed)", False, OPTION_FLAG_DISABLED)
        EndIf
        _slaveryDistOID = AddSliderOption("Player Distance to Allow It", Main.fSlaveryPlayerDistance, "{0}")
        _tiedHoursOID   = AddSliderOption("Tied Prisoner Duration",      Main.fTiedHours, "{0} h")
        ; REV-109: the Maintenance section (panic reset) moved to Settings
        ; (framework-level, per the restructure); the Execute-gate stays here -
        ; it is capture behavior, not framework state.
        _execGateOID = AddMenuOption("Execution Action Use", _execGateName(_ExecGateLevel()))
        ; ---- Timing (the former "Baka - Timing" body, moved verbatim) ----
        AddHeaderOption("Timing")
        AddEmptyOption()
        AddHeaderOption("Animation Durations")
        _hugDurOID    = AddSliderOption("Hug Loop Duration",         Main.fHugLoopDuration,    "{0}s")
        _molestDurOID = AddSliderOption("Molest Loop Duration",      Main.fMolestLoopDuration, "{0}s")
        _kissDurOID   = AddSliderOption("Kiss Duration (per stage)", Main.fKissLoopDuration,   "{0}s")
        _touchDurOID  = AddSliderOption("Touch Duration",            Main.fTouchLoopDuration,  "{0}s")
        _stageDurOID  = AddSliderOption("Sequence Stage Duration",   Main.fSequenceStageTimer, "{0}s")
        ; ---- Resist (the former "Baka - Resist" body, moved verbatim) ----
        AddHeaderOption("Resist")
        AddEmptyOption()
        AddHeaderOption("Struggle QTE")
        _resistEnabledOID        = AddToggleOption("Enable Resist Minigame",    Main.bResistEnabled)
        _resistDifficultyOID     = AddSliderOption("Escape Difficulty",          Main.fResistDifficulty,    "{0}%")
        _qteKeysOID = AddTextOption("QTE Keys", "Flash Games - Struggling QTE", OPTION_FLAG_DISABLED)
        AddEmptyOption()
        AddHeaderOption("NPC-vs-NPC Struggle (no QTE, auto-rolled)")
        _npcEscapeChanceOID = AddSliderOption("Victim Escape Chance", Main.fNPCEscapeChance, "{0}%")
        _npcStageTimeOID    = AddSliderOption("Stage Duration",       Main.fNPCStageTime,    "{0}s")
        _escapeGraceOID     = AddSliderOption("Post-Escape Grace",    Main.fEscapeGraceDuration, "{0}s")
        AddEmptyOption()
        AddHeaderOption("Defeat window (fallback only)")
        _escalationWindowOID     = AddSliderOption("Escalation Window",  Main.fEscalationWindow,    "{0}s")
        _escalationDifficultyOID = AddSliderOption("Escalation QTE",     Main.fEscalationDifficulty, "{0}%")
        ; ---- Spank (the former "Baka - Spank" body, moved verbatim) ----
        AddHeaderOption("Spank")
        AddEmptyOption()
        AddHeaderOption("Behaviour")
        ; REV-145 fold-in: "Player Can Be Spanked" (retired at REV-144 -- the
        ; central player-target policy owns it, surfaced as "NPCs May Target
        ; You" in General) and "Allow Male Targets" (folds under the Ambient
        ; Target Policy dropdown, SS-C) are REMOVED as MCM rows; the motherboard
        ; properties stay declared for save-member/VMAD compatibility.
        _spankFurnitureOID = AddToggleOption("Furniture Reactions",    Main.bSpankFurnitureTriggers)
        AddEmptyOption()
        AddHeaderOption("Tattoo Marks")
        _spankTatIntensityOID = AddSliderOption("Spanks Per Stage", Main.SpankTatIntensity as Float, "{0}")
        _spankHealFactorOID   = AddSliderOption("Hours Per Stage",  Main.SpankHealFactor as Float,   "{0} hr")
        ; ---- Scenes & FX (the former "Baka - Scenes & FX" body, moved verbatim) ----
        AddHeaderOption("Scenes & FX")
        AddEmptyOption()
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
        _tattooAskOID         = AddToggleOption("LLM Chooses Tattoo Designs", Main.bTattooSelectAsk)    ; REV-178e rider 4 / S250
        _notifyOID            = AddToggleOption("Show Corner Notifications", Main.bShowNotifications)
        ; REV-109: "Enable Debug Logging" moved to the Settings page (framework-level).
        ; REV-145 fold-in: "Victim Sex Allowed" (iCreatureVictimSex) folds under the
        ; Ambient Target Policy dropdown (SS-C: same level mapping) -- row REMOVED;
        ; the property stays declared for save-member compatibility.
        _creatureBackendOID   = AddMenuOption("Creature Framework",  _backendName(Main.iCreatureBackend))
        _creatureSuccessOID   = AddSliderOption("NPC Success Chance", Main.iCreatureSuccessPct as Float, "{0}%")
        _creatureHitChanceOID = AddSliderOption("Chance to Struggle on Hit", Main.iCreatureHitEngageChance as Float, "{0}%")
        _creatureStruggleDurOID = AddSliderOption("Struggle Duration", Main.fCreatureStruggleDuration, "{1}s")
        _creatureGraceOID     = AddSliderOption("Post-Defeat Grace",   Main.fPostDefeatGraceDuration, "{0}s")
        _creatureGroupSizeOID = AddSliderOption("Max Group Size",      Main.iCreatureGroupMaxSize as Float, "{0}")
        AddHeaderOption("Humanoids (mid-combat)")
        _humanOnHitOID       = AddToggleOption("Escalate on Hit Mid-Combat (followers + player)", Main.bHumanEscalateOnHit)
        _humanHitChanceOID   = AddSliderOption("Chance to Struggle on Hit", Main.iHumanHitEngageChance as Float, "{0}%")
        ; ---- Lap Sitting (the former top-level page, folded in per the user's list) ----
        AddHeaderOption("Lap Sitting")
        AddEmptyOption()
        AddHeaderOption("Immersive Lap Sitting")
        If Main.IsLapSitInstalled()
            _lapSitOID = AddToggleOption("Enable Lap Sitting Actions", Main.bLapSitEnabled)
        Else
            _lapSitOID = AddToggleOption("Lap Sitting Actions (not installed)", False, OPTION_FLAG_DISABLED)
        EndIf
    ElseIf page == "Cum Effects" && Main
        ; REV-80: promoted from the dissolved Plugins page (one integration,
        ; one page). REV-63 detection toggles, presence-gated as before.
        ; REV-134c: More Cum (register 24) finally built HERE (the live MCM)
        ; instead of the retired v7 script (§148 wrong-script root cause);
        ; default OFF (user ruling). Also REV-134c: every option gains a
        ; plain-language description (user ruling: the names were too vague).
        ; SkyUI has no tooltips, so each description is a disabled
        ; AddTextOption static row directly under its toggle.
        SetCursorFillMode(TOP_TO_BOTTOM)
        AddHeaderOption("Cum Detection (OCum / SexLab)")
        If Main._OCumInstalled()
            ; REV-134d (R2, user-ruled 2026-10-21, names verbatim): the Cum-page
            ; redesign -- "Cum Cues Module Toggle" (renamed from "Cum Cues (OCum +
            ; SexLab climax proxy)"); the "SexLab Climax Proxy Share" toggle is
            ; RETIRED and replaced by the "Decal Source Selection" dropdown (a
            ; cycling menu option over the supported decal sources,
            ; presence-gated: absent sources are not offered); "More Cum" keeps
            ; its name. Descriptions are TOOLTIPS (SetInfoText on highlight, the
            ; REV-134c "SkyUI has no tooltips" finding superseded -- the info-text
            ; surface the script already uses everywhere else), NOT subtext rows:
            ; the REV-134c static AddTextOption description rows are REMOVED per
            ; the user's ruling ("remove subtext description once tooltip
            ; replacement is made").
            _cumDetectOID = AddToggleOption("Cum Cues Module Toggle", Main.bCumDetectionEnabled)
            If Main.bCumDetectionEnabled
                _decalOID = AddMenuOption("Decal Source Selection", _decalSourceLabel())
            Else
                _decalOID = AddMenuOption("Decal Source Selection", _decalSourceLabel(), OPTION_FLAG_DISABLED)
            EndIf
            If Main.bCumDetectionEnabled
                _moreCumOID = AddToggleOption("More Cum", Main.bMoreCumEnabled)
                ; REV-134f: Follow-up Prompt -- same gating posture as More Cum
                ; (user-ruled name verbatim; tooltip text is the user's verbatim
                ; ruling, delivered as SetInfoText on highlight per REV-134d R2).
                _cumFollowUpOID = AddToggleOption("Follow-up Prompt", Main.bCumFollowUpNarration)
                ; REV-161 4.4: the ambient cadence slider (label = register DRAFT;
                ; key SNBaka.CumAmbientCadence, default 60s = the historic cadence).
                _cumAmbCadOID = AddSliderOption("Ambient Cue Interval", StorageUtil.GetFloatValue(None, "SNBaka.CumAmbientCadence", 60.0), "{0}s")
            Else
                _moreCumOID = AddToggleOption("More Cum", Main.bMoreCumEnabled, OPTION_FLAG_DISABLED)
                _cumFollowUpOID = AddToggleOption("Follow-up Prompt", Main.bCumFollowUpNarration, OPTION_FLAG_DISABLED)
                _cumAmbCadOID = AddSliderOption("Ambient Cue Interval", StorageUtil.GetFloatValue(None, "SNBaka.CumAmbientCadence", 60.0), "{0}s", OPTION_FLAG_DISABLED)
            EndIf
        Else
            _cumDetectOID = AddToggleOption("Cum Cues (OCum not installed)", False, OPTION_FLAG_DISABLED)
            _decalOID     = -1
            _moreCumOID   = -1
            _cumFollowUpOID = -1
            _cumAmbCadOID   = -1
        EndIf
    ElseIf page == "Fill Her Up" && Main
        ; REV-80: promoted from the dissolved Plugins page (one integration,
        ; one page). Presence-greyed at page level when the mod is absent.
        ; REV-134c: description row added (user ruling: vague names).
        SetCursorFillMode(TOP_TO_BOTTOM)
        AddHeaderOption("FHU Inflation Awareness")
        If Main._FHUInstalled()
            ; REV-159 3.2(b) (USER-PROVIDED verbatim): title "Inflation Level
            ; Cues (Fill Her Up)" -> "Module Toggle - Fill Her Up Awareness";
            ; the three-row subtext RETIRED in favor of the tooltip delivered
            ; as SetInfoText on highlight (the SetInfoText pattern, the
            ; REV-134d R2 precedent): "Enable/disable cues and reactions for
            ; Fill Her Up Baka" (user-quoted).
            _fhuAwareOID = AddToggleOption("Module Toggle - Fill Her Up Awareness", Main.bFHUInflationEnabled)
            ; REV-153: Follow-up Prompt -- same gating posture as the Cum
            ; Effects page's 134f toggle (greyed when the cue module is off;
            ; label DRAFT per the exchange shape, tooltip on highlight).
            If Main.bFHUInflationEnabled
                _fhuNarrOID = AddToggleOption("Follow-up Prompt", Main.bFHUInflateNarration)
            Else
                _fhuNarrOID = AddToggleOption("Follow-up Prompt", Main.bFHUInflateNarration, OPTION_FLAG_DISABLED)
            EndIf
            ; REV-154: the ambient bystander surfaces -- same gating posture as
            ; the Follow-up Prompt toggle (greyed when the cue module is off;
            ; labels/tooltips = register entry-34 DRAFTs, the user's pen).
            Int iAmbFlags = OPTION_FLAG_DISABLED * ((!Main.bFHUInflationEnabled) as Int)
            _fhuAmbNarrOID = AddToggleOption("Ambient Narration", Main.bFHUAmbientNarration, iAmbFlags)
            _fhuNoticeOID = AddSliderOption("Noticeable Band", Main.iFHUAmbientNoticeBand as Float, "{0}%", iAmbFlags)
            _fhuHeavyOID = AddSliderOption("Heavy Band", Main.iFHUAmbientHeavyBand as Float, "{0}%", iAmbFlags)
            ; REV-161 4.4: the ambient cadence slider (label = register DRAFT;
            ; key SNBaka.FHUAmbientCadence, default 60s = the REV-154 historic
            ; cadence, read live at every pass -- no re-arm needed).
            _fhuAmbCadOID = AddSliderOption("Ambient Cue Interval", StorageUtil.GetFloatValue(None, "SNBaka.FHUAmbientCadence", 60.0), "{0}s", iAmbFlags)
        Else
            _fhuAwareOID = AddToggleOption("Module Toggle - Fill Her Up Awareness (not installed)", False, OPTION_FLAG_DISABLED)
            _fhuNarrOID = -1
            _fhuAmbNarrOID = -1
            _fhuNoticeOID = -1
            _fhuHeavyOID = -1
            _fhuAmbCadOID = -1
        EndIf

    ElseIf page == "Acheron"
        ; REV-79 restructure: the Downed State bridge promoted from a Plugins section to
        ; its own page (one integration, one page). Absent state is page-level: every
        ; option greyed + the header names the missing mod (per-section gate, extended).
        SetCursorFillMode(TOP_TO_BOTTOM)
        AddHeaderOption("Downed State (Acheron Bridge)")
        Actor _achP = Game.GetPlayer()
        If !_achP
            _achP = Game.GetPlayer()
        EndIf
        If Game.GetFormFromFile(0x800, "SkyrimNet_AcheronIntegration.esp") != None   ; REV-106 S4a: de-Mained — same probe the motherboard module-arm uses (SkyrimNet_BakaIntegration L586); the Acheron page no longer consults the motherboard
            _achEnabledOID  = AddToggleOption("Bridge Enabled",            StorageUtil.GetIntValue(_achP,   "SNAcheron.Enabled",           1) == 1)
            _achCueOID      = AddSliderOption("Reminder Cue Interval",     StorageUtil.GetFloatValue(_achP, "SNAcheron.CueInterval",       30.0),  "{0} s")
            _achProxOID     = AddSliderOption("Creature Check Interval",   StorageUtil.GetFloatValue(_achP, "SNAcheron.ProxInterval",      10.0),  "{0} s")
            _achConfirmOID  = AddSliderOption("Auto Get-Up Timer",         StorageUtil.GetFloatValue(_achP, "SNAcheron.AutoGetUpSeconds",  600.0), "{0} s")
            _achHandoffOID  = AddToggleOption("Creature Pounce On Recovery", StorageUtil.GetIntValue(_achP, "SNAcheron.CreatureHandoff",    1) == 1)
            _achGetUpKeyOID = AddKeyMapOption("Get-Up Key (hold 3s)",      StorageUtil.GetIntValue(_achP,   "SNAcheron.GetUpKey",          51))
            _achEngageOID   = AddSliderOption("Creature Engagement Chance", StorageUtil.GetFloatValue(_achP, "SNAcheron.CreatureEngageChance", 50.0), "{0}%")
            _achDebugOID    = AddToggleOption("Enable Debug Logging",      StorageUtil.GetIntValue(_achP,   "SNAcheron.DebugLog",          1) == 1)
        Else
            _achEnabledOID  = AddToggleOption("Bridge Enabled (not installed)", False, OPTION_FLAG_DISABLED)
            _achCueOID      = -1
            _achProxOID     = -1
            _achConfirmOID  = -1
            _achHandoffOID  = -1
            _achGetUpKeyOID = -1
            _achEngageOID   = -1
            _achDebugOID    = -1
        EndIf
    ElseIf page == "SlaveTats"
        ; REV-79 restructure: the SlaveTats degradation-set section promoted from the
        ; Plugins page to its own page (one integration, one page — the page the picker
        ; walkthrough is re-baselined against). Absent state page-level like Acheron's.
        ; REV-80 §7 copy fix: the set-assignment block is titled WHAT IT IS — "Auto-Apply
        ; Sets" configures which set each EVENT fires automatically (spank / defeat /
        ; escalation); the actual set choice happens in the in-game Tattoo Menu picker,
        ; which always offers the full range regardless of what is configured here.
        ; Presence-greyed at page level when SlaveTats is absent.
        SetCursorFillMode(TOP_TO_BOTTOM)
        AddHeaderOption("SlaveTats Degradation Sets")
        Actor _stP = Game.GetPlayer()
        If !_stP
            _stP = Game.GetPlayer()
        EndIf
        If SNBaka_SlaveTatsModule.Installed()
            _stEnabledOID = AddToggleOption("Module Enabled",               StorageUtil.GetIntValue(_stP,  "SNBaka.ST.Enabled",           1) == 1)
            AddEmptyOption()
            AddHeaderOption("Auto-Apply Sets")
            _stIntroOID = AddTextOption("Sets are picked in the Tattoo Menu.", "", OPTION_FLAG_DISABLED)
            _stSpankOID   = AddToggleOption("Apply Set On Spank",           StorageUtil.GetIntValue(_stP,  "SNBaka.ST.ApplyOnSpank",      1) == 1)
            _stDefeatOID  = AddToggleOption("Apply Set On Defeat",          StorageUtil.GetIntValue(_stP,  "SNBaka.ST.ApplyOnDefeat",     1) == 1)
            _stEscalOID   = AddToggleOption("Apply Set On Escalation",      StorageUtil.GetIntValue(_stP,  "SNBaka.ST.ApplyOnEscalation", 0) == 1)
            AddEmptyOption()
            AddHeaderOption("Packs & Marks")
            _stRefreshOID = AddTextOption("Refresh Pack List",             "Refresh")
            _stStatusOID  = AddTextOption("Sections Available",             StorageUtil.GetIntValue(_stP, "SNBaka.ST.SectionCount", 0) + " sections")
            _stPickOID    = AddTextOption("Open Set Picker (In-Game)",     "Open")
            ; REV-74 Task 4: module-wide default color (picker per-set colors override),
            ; removal-on-release, and the ambient observation pass toggle.
            _stDefaultColorOID   = AddTextOption("Default Mark Color",     _ST_ColorLabel(StorageUtil.GetIntValue(_stP, "SNBaka.ST.DefaultColor", 0)))
            _stRemoveOnReleaseOID = AddToggleOption("Remove Marks On Release", StorageUtil.GetIntValue(_stP, "SNBaka.ST.RemoveOnRelease", 1) == 1)
            _stObserveOID         = AddToggleOption("Ambient Observation Cues", StorageUtil.GetIntValue(_stP, "SNBaka.ST.Observe", 1) == 1)
            _stAmbientPctOID      = AddSliderOption("Ambient Exposure Chance", StorageUtil.GetIntValue(_stP, "SNBaka.ST.AmbientPct", 35) as Float, "{0}%")
            _stAmbientNarrOID     = AddToggleOption("Tattoo Ambient Narration", StorageUtil.GetIntValue(_stP, "SNBaka.ST.AmbientNarr", 0) == 1)
            ; REV-161 4.4: the ambient interval slider (label = register DRAFT;
            ; existing key SNBaka.ST.AmbientFloor, default 600s, already read
            ; live by AmbientExposurePass -- no module change needed).
            _stAmbFloorOID        = AddSliderOption("Ambient Cue Interval", StorageUtil.GetFloatValue(_stP, "SNBaka.ST.AmbientFloor", 600.0), "{0}s")
        Else
            _stEnabledOID = AddToggleOption("Module Enabled (not installed)", False, OPTION_FLAG_DISABLED)
            _stSpankOID   = -1
            _stDefeatOID  = -1
            _stEscalOID   = -1
            _stRefreshOID = -1
            _stStatusOID  = -1
            _stPickOID    = -1
            _stDefaultColorOID    = -1
            _stRemoveOnReleaseOID = -1
            _stObserveOID         = -1
            _stAmbientPctOID      = -1
            _stAmbientNarrOID     = -1
            _stAmbFloorOID        = -1
        EndIf
    ElseIf page == "GS Poses"
        ; REV-85 Phase B: the gender policy home (posing-gender.md §2b). One menu
        ; option, three modes; the GS script reads the key on every gate (no nudge
        ; needed — every check is a fresh StorageUtil read). Mode names mirror the
        ; policy vocabulary of record.
        ; REV-159 5.1/5.2/5.3 (user-ruled at the dogfood): the page build-out --
        ; the Sanguine + Sheogorath mode-narration toggles (DEFAULT OFF) and
        ; cadence sliders (15s-240s, writing the arbiters' live cadence keys),
        ; plus the three per-route pose-narration toggles (TITLES USER-AUTHORED
        ; per the 137f rider, register-cite; DEFAULT ON -- current behavior
        ; preserved). Tooltips = register entry 37 DRAFTs ("narration cue" lean).
        SetCursorFillMode(TOP_TO_BOTTOM)
        AddHeaderOption("GSPoses - Pose Gender Policy")
        _gsIntroOID = AddTextOption("Who may be posed, by body:", "", OPTION_FLAG_DISABLED)
        _gsGenderPolicyOID = AddMenuOption("Pose Gender Policy", _gsGenderPolicyName(StorageUtil.GetIntValue(None, "GSAnim.GenderPolicy", 0)))
        AddEmptyOption()
        ; [REV-178b Leg 2.1] section renamed "Pose Narration" -> "General Pose
        ;   Reactions" (retiring the "Narration" phrasing; register DRAFT label);
        ;   toggles relabeled "...Pose Reactions" (keys unchanged, one lineage).
        AddHeaderOption("General Pose Reactions")
        ; [REV-174d Leg 3.2] "Sanguine Pose Narration" toggle RETIRED (REV-174a D3 lanes-only;
        ;   key GSAnim.PoseNarrSanguine orphaned, no migration). Emergent/Player UNCHANGED.
        _poseNarrEmOID   = AddToggleOption("Emergent Pose Reactions", StorageUtil.GetIntValue(None, "GSAnim.PoseNarrEmergent", 1) == 1)
        _poseNarrPlOID   = AddToggleOption("Player Initiated Pose Reactions", StorageUtil.GetIntValue(None, "GSAnim.PoseNarrPlayer", 1) == 1)
        ; [REV-178b Leg 2.3] POSE REACTION LANES (new surface -- the 174f Baka
        ;   action-lane shape mirrored GS-side): four fanned lanes on emergent +
        ;   player-initiated pose fires (gsanim_pose_lane_*); keys
        ;   GSAnim.PoseLane_{narr|thought|pspeech|pthought}, defaults mirror A15
        ;   (narr/pspeech/pthought ON, thought OFF). Labels register DRAFT.
        AddEmptyOption()
        AddHeaderOption("Reaction Lanes")
        _gsReactArbOID         = AddToggleOption("LLM Reaction Arbitration", StorageUtil.GetIntValue(None, "GSAnim.ReactArbitration", 1) == 1)
        _gsPoseLaneNarrOID     = AddToggleOption("Pose Narration Lane", StorageUtil.GetIntValue(None, "GSAnim.PoseLane_narr", 1) == 1)
        _gsPoseLaneThoughtOID  = AddToggleOption("Pose Thought Lane", StorageUtil.GetIntValue(None, "GSAnim.PoseLane_thought", 0) == 1)
        _gsPoseLanePSpeechOID  = AddToggleOption("Pose Speech Reaction Lane", StorageUtil.GetIntValue(None, "GSAnim.PoseLane_pspeech", 1) == 1)
        _gsPoseLanePThoughtOID = AddToggleOption("Pose Private Thought Lane", StorageUtil.GetIntValue(None, "GSAnim.PoseLane_pthought", 1) == 1)
        AddEmptyOption()
        AddHeaderOption("Mode Cadence")
        ; [REV-174e Leg 4] the two Mode Narration rows REMOVED (user ruling
        ;   2026-10-31; keys orphaned, no migration; the Reaction Lanes section
        ;   is the sole narration gate surface).
        _sangCadOID  = AddSliderOption("Sanguine Tick Interval", StorageUtil.GetFloatValue(None, "GSAnim.NudgeInterval", 60.0), "{0}s")
        _sheoCadOID  = AddSliderOption("Sheogorath Tick Interval", StorageUtil.GetFloatValue(None, "GSAnim.T3Interval", 60.0), "{0}s")
        ; REV-167 t3 (entry 44, §3.4/§15.8): the GS modes' per-mode Selection
        ; block -- Sanguine + Sheogorath subject/target dropdowns (GSAnim.*
        ; keys, DEFAULT 0 = Random = shipped behavior) + the Sheogorath
        ; Selection toggle (§7.4: DEFAULT ON = Perverse Fit -- the runtime
        ; default 1 already holds; this is the MCM surface only).
        AddEmptyOption()
        AddHeaderOption("Mode Selection")
        ; [REV-178 L3] the narrative-selection surface on the GS page too:
        ; Method ABOVE the pools; R1 default Sheogorath = Random (0) -- the
        ; only mode not defaulting to Narrative. Keys reused post-migrate5.
        _sangMethodOID = AddMenuOption("Sanguine Selection Method", _selMethodName(StorageUtil.GetIntValue(None, "GSAnim.SanguineSelectionMethod", 1)))
        _sangSubOID  = AddMenuOption("Sanguine Subject Pool", _selSubjectName(StorageUtil.GetIntValue(None, "GSAnim.SanguineSubject", 0)))
        _sangTgtOID  = AddMenuOption("Sanguine Target Pool", _selTargetName(StorageUtil.GetIntValue(None, "GSAnim.SanguineTarget", 0)))
        _sheoMethodOID = AddMenuOption("Sheogorath Selection Method", _selMethodName(StorageUtil.GetIntValue(None, "GSAnim.SheogorathSelectionMethod", 0)))
        _sheoSubOID  = AddMenuOption("Sheogorath Subject Pool", _selSubjectName(StorageUtil.GetIntValue(None, "GSAnim.SheogorathSubject", 0)))
        _sheoTgtOID  = AddMenuOption("Sheogorath Target Pool", _selTargetName(StorageUtil.GetIntValue(None, "GSAnim.SheogorathTarget", 0)))
        _sheoSelOID  = AddToggleOption("Sheogorath Selection", StorageUtil.GetIntValue(None, "GSAnim.SheoSelection", 1) == 1)
        ; [REV-174a A34b] GS's player-target toggle (the exact None-keyed
        ; GSAnim.PlayerTargetable key the roster gate + _PoseVibe guard read;
        ; DEFAULT OFF; label DRAFT at the user's pen).
        _gsPlayerTgtOID = AddToggleOption("Player can be targeted", StorageUtil.GetIntValue(None, "GSAnim.PlayerTargetable", 0) == 1)
        ; [REV-174 D3 A15] REACTION LANES (GS modes): 8 mode lanes, ALL
        ; ON by default (GSAnim.* keys, None-keyed, read FRESH per fire).
        ; [REV-178b Leg 2.1] header renamed "Reaction Lanes (GS)" ->
        ;   "Mode Reaction Lanes" (disambiguation vs the pose Reaction Lanes
        ;   section above; funeral for the old header). The arbitration master
        ;   row MOVED UP to the pose lane section (one master, shown once).
        AddEmptyOption()
        AddHeaderOption("Mode Reaction Lanes")
        _gsSangLaneNarrOID     = AddToggleOption("Sanguine Narration Lane", StorageUtil.GetIntValue(None, "GSAnim.SanguineLane_narr", 1) == 1)
        _gsSangLaneThoughtOID  = AddToggleOption("Sanguine Thought Lane", StorageUtil.GetIntValue(None, "GSAnim.SanguineLane_thought", 1) == 1)
        _gsSangLanePSpeechOID  = AddToggleOption("Sanguine Speech Reaction Lane", StorageUtil.GetIntValue(None, "GSAnim.SanguineLane_pspeech", 1) == 1)
        _gsSangLanePThoughtOID = AddToggleOption("Sanguine Private Thought Lane", StorageUtil.GetIntValue(None, "GSAnim.SanguineLane_pthought", 1) == 1)
        _gsSheoLaneNarrOID     = AddToggleOption("Sheogorath Narration Lane", StorageUtil.GetIntValue(None, "GSAnim.SheogorathLane_narr", 1) == 1)
        _gsSheoLaneThoughtOID  = AddToggleOption("Sheogorath Thought Lane", StorageUtil.GetIntValue(None, "GSAnim.SheogorathLane_thought", 1) == 1)
        _gsSheoLanePSpeechOID  = AddToggleOption("Sheogorath Speech Reaction Lane", StorageUtil.GetIntValue(None, "GSAnim.SheogorathLane_pspeech", 1) == 1)
        _gsSheoLanePThoughtOID = AddToggleOption("Sheogorath Private Thought Lane", StorageUtil.GetIntValue(None, "GSAnim.SheogorathLane_pthought", 1) == 1)
        ; [REV-179 Leg 2] the CASE compose-time toggle (ruling of record (c),
        ; 178d dogfood): GSAnim.CaseInCue, None-keyed, DEFAULT ON, read fresh
        ; per fire by _GSComposeDesc. Label + tooltip = register DRAFT.
        AddEmptyOption()
        AddHeaderOption("Cue Shape")
        _gsCaseCueOID = AddToggleOption("Reasoning Line in Cues", StorageUtil.GetIntValue(None, "GSAnim.CaseInCue", 1) == 1)
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
        SetOptionFlags(_decalOID, OPTION_FLAG_DISABLED * ((!Main.bCumDetectionEnabled) as Int))
        SetOptionFlags(_moreCumOID, OPTION_FLAG_DISABLED * ((!Main.bCumDetectionEnabled) as Int))
        SetOptionFlags(_cumFollowUpOID, OPTION_FLAG_DISABLED * ((!Main.bCumDetectionEnabled) as Int))
        If Main.bCumDetectionEnabled
            Main.Setup()
            Debug.Notification("Cum cues enabled.")
        Else
            Debug.Notification("Cum cues disabled.")
        EndIf
    ElseIf option == _moreCumOID
        ; REV-134c (register 24, ruled at REV-133c; built into the live MCM here
        ; -- the §148 wrong-script fix). Default is OFF (motherboard property
        ; flipped with this rev); the extras router (SNBaka_CumDetectionModule
        ; L302) reads the property live, no re-arm needed.
        Main.bMoreCumEnabled = !Main.bMoreCumEnabled
        SetToggleOptionValue(_moreCumOID, Main.bMoreCumEnabled)
        If Main.bMoreCumEnabled
            Debug.Notification("More Cum enabled: finishes will apply extra decals on additional body parts.")
        Else
            Debug.Notification("More Cum disabled.")
        EndIf
    ElseIf option == _cumFollowUpOID
        ; REV-134f (user-ruled 2026-10-21): optional direct narration for the
        ; ambient cum cue. Read live at every ambient tick -- no re-arm needed;
        ; OFF removes the narration line entirely (cue stays, per the REV-134d
        ; cue-only anatomy verdict which is this property's default).
        Main.bCumFollowUpNarration = !Main.bCumFollowUpNarration
        SetToggleOptionValue(_cumFollowUpOID, Main.bCumFollowUpNarration)
        If Main.bCumFollowUpNarration
            Debug.Notification("Follow-up Prompt enabled: ambient cum cues also produce a direct narration line.")
        Else
            Debug.Notification("Follow-up Prompt disabled.")
        EndIf
    ElseIf option == _fhuAwareOID
        Main.bFHUInflationEnabled = !Main.bFHUInflationEnabled
        SetToggleOptionValue(_fhuAwareOID, Main.bFHUInflationEnabled)
        ; REV-153: keep the Follow-up Prompt toggle's flag in step with the
        ; cue module toggle (the 134f SetOptionFlags posture).
        SetOptionFlags(_fhuNarrOID, OPTION_FLAG_DISABLED * ((!Main.bFHUInflationEnabled) as Int))
        ; REV-154: the ambient surfaces grey in step with the cue module toggle
        ; (the 134f SetOptionFlags posture, extended to the narr toggle + both
        ; band sliders).
        Int iAmbFlags = OPTION_FLAG_DISABLED * ((!Main.bFHUInflationEnabled) as Int)
        SetOptionFlags(_fhuAmbNarrOID, iAmbFlags)
        SetOptionFlags(_fhuNoticeOID, iAmbFlags)
        SetOptionFlags(_fhuHeavyOID, iAmbFlags)
        Main.Setup()   ; re-arms or disarms the level poll right now
    ElseIf option == _fhuNarrOID
        ; REV-153 (user-ruled 2026-10-24, the 134f Follow-up Prompt pattern
        ; applied to FHU): optional direct narration for the inflation cue.
        ; Read live at every inflate fire -- no re-arm needed; OFF removes the
        ; narration event entirely (the cue stays, per the 134f cue-only
        ; anatomy verdict which is this property's default).
        Main.bFHUInflateNarration = !Main.bFHUInflateNarration
        SetToggleOptionValue(_fhuNarrOID, Main.bFHUInflateNarration)
        If Main.bFHUInflateNarration
            Debug.Notification("Follow-up Prompt enabled: inflation cues also produce a direct narration line.")
        Else
            Debug.Notification("Follow-up Prompt disabled.")
        EndIf
    ElseIf option == _fhuAmbNarrOID
        ; REV-154 (the 153/134f pattern, applied to the AMBIENT bystander cue):
        ; optional direct narration, read live at every ambient fire -- no
        ; re-arm needed; OFF removes the narration event entirely (the
        ; ambient cue stays, per the 134d cue-only anatomy verdict which is
        ; this property's default). Notification text = register entry-34 DRAFT.
        Main.bFHUAmbientNarration = !Main.bFHUAmbientNarration
        SetToggleOptionValue(_fhuAmbNarrOID, Main.bFHUAmbientNarration)
        If Main.bFHUAmbientNarration
            Debug.Notification("Ambient Narration enabled: ambient bystander cues also produce a direct narration line.")
        Else
            Debug.Notification("Ambient Narration disabled.")
        EndIf
    ElseIf option == _achEnabledOID
        ; REV-68 bridge master switch — same SNAcheron.Enabled key the bridge MCM wrote; the
        ; bridge quest re-reads it on its next tick. Nudges the motherboard lifecycle surface
        ; (per the §68 ruling: toggles nudge Main._ArmModules()) so the bridge picks the change
        ; up immediately instead of on its own self-heal cadence.
        Actor achP1 = Game.GetPlayer()
        If !achP1
            achP1 = Game.GetPlayer()
        EndIf
        Int vAch = 1 - StorageUtil.GetIntValue(achP1, "SNAcheron.Enabled", 1)
        StorageUtil.SetIntValue(achP1, "SNAcheron.Enabled", vAch)
        SetToggleOptionValue(_achEnabledOID, vAch == 1)
        ; REV-106 S4a: the lifecycle nudge is motherboard-dependent — guard it so
        ; this Acheron-page toggle works with the motherboard absent too (the bridge
        ; re-reads the key on its own self-heal cadence either way, per §68).
        If Main
            Main._ArmModules()
        EndIf
    ElseIf option == _achHandoffOID
        Actor achP2 = Game.GetPlayer()
        If !achP2
            achP2 = Game.GetPlayer()
        EndIf
        Int vHand = 1 - StorageUtil.GetIntValue(achP2, "SNAcheron.CreatureHandoff", 1)
        StorageUtil.SetIntValue(achP2, "SNAcheron.CreatureHandoff", vHand)
        SetToggleOptionValue(_achHandoffOID, vHand == 1)
    ElseIf option == _achDebugOID
        Actor achP3 = Game.GetPlayer()
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
        Actor stP1 = Game.GetPlayer()
        If !stP1
            stP1 = Game.GetPlayer()
        EndIf
        SetTextOptionValue(_stStatusOID, StorageUtil.GetIntValue(stP1, "SNBaka.ST.SectionCount", 0) + " sections")
        Debug.Notification("SlaveTats: pack list refreshed - " + StorageUtil.GetIntValue(stP1, "SNBaka.ST.SectionCount", 0) + " sections visible.")
    ElseIf option == _stPickOID
        ; REV-72 dogfood fix: the set picker had no in-game entry point (OpenSetMenu was
        ; dead code). Close the MCM first — PrismaUI modal needs the game input focus.
        SNBaka_SlaveTatsModule.OpenSetMenu()
    ElseIf option == _stDefaultColorOID
        ; REV-74: cycle Default -> Black -> Red -> Crimson -> Dark Red -> Blue -> Green
        ; -> Purple -> Pink -> Default. Stored as the 0xRRGGBB int the module reads
        ; (SNBaka.ST.DefaultColor; 0 = pack default / no recolor).
        Actor stP2 = Game.GetPlayer()
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
    ElseIf option == _stAmbientNarrOID
        _ST_Toggle("SNBaka.ST.AmbientNarr", _stAmbientNarrOID, 0)
    ElseIf option == _animatedTearsOID
        Main.bAnimatedTearsEnabled = !Main.bAnimatedTearsEnabled
        SetToggleOptionValue(_animatedTearsOID, Main.bAnimatedTearsEnabled)
        ; If just enabled and spell not yet resolved, try now
        If Main.bAnimatedTearsEnabled && !Main.TearSpell
            Main.TearSpell = Game.GetFormFromFile(0x000802, "EmoTears4NPCs.esp") as Spell
        EndIf
    ElseIf option == _playerTargetOID
        ; REV-145: the central player-target policy (SNBaka.PlayerTargetPolicy,
        ; player-keyed, default OFF; the REV-144 bPlayerCanBeSpanked/bPlayerCanBeTarget
        ; fold-ins). The motherboard gates read it live on every consult.
        Actor pol = Game.GetPlayer()
        Int v = 1 - StorageUtil.GetIntValue(pol, "SNBaka.PlayerTargetPolicy", 0)
        StorageUtil.SetIntValue(pol, "SNBaka.PlayerTargetPolicy", v)
        SetToggleOptionValue(_playerTargetOID, v == 1)
    ; [REV-174a A34b] GS's player-target toggle (GSAnim.PlayerTargetable,
    ; None-keyed, default OFF -- the exact key the GS roster gate + _PoseVibe
    ; guard + lane backstop read; read live, no re-arm needed).
    ElseIf option == _gsPlayerTgtOID
        Int gv = 1 - StorageUtil.GetIntValue(None, "GSAnim.PlayerTargetable", 0)
        StorageUtil.SetIntValue(None, "GSAnim.PlayerTargetable", gv)
        SetToggleOptionValue(_gsPlayerTgtOID, gv == 1)
    ; [REV-174a D4] Debug Notifications (shared GSAnim.DebugNotify gate; the
    ; fire-receipt wrapper in both modules reads it live).
    ElseIf option == _gsDebugNotifyOID
        Int dv = 1 - StorageUtil.GetIntValue(None, "GSAnim.DebugNotify", 0)
        StorageUtil.SetIntValue(None, "GSAnim.DebugNotify", dv)
        SetToggleOptionValue(_gsDebugNotifyOID, dv == 1)
    ; REV-146a: _mephalaOID/_molagBalOID handlers REMOVED (user ruling:
    ; Prisma panel is the only mode surface -- the motherboard toggles live
    ; in SkyrimNet_BakaIntegration, unchanged). Their OID members retire as
    ; never-bound (-1) no-ops.
    ; [REV-174 D3 LEG 4] the mode-narration toggle handlers REMOVED with the
    ; properties (reaction lanes are the live surface).
    ; REV-159 5.1/5.3: the GS-side StorageUtil-keyed toggles (the _ST_Toggle
    ; helper pattern, None-keyed GSAnim.* keys).
    ; [REV-174e Leg 4] the mode-narration toggle handlers REMOVED with the
    ;   rows (keys GSAnim.SanguineModeNarr/GSAnim.SheogorathModeNarr orphaned,
    ;   no migration).
    ; REV-159 5.3: the three per-route pose-narration toggles (TITLES
    ; USER-AUTHORED, 137f rider; DEFAULT ON -- current behavior preserved).
    ; [REV-174d Leg 3.2] "Sanguine Pose Narration" tooltip RETIRED with the toggle
    ;   (REV-174a D3 lanes-only; key GSAnim.PoseNarrSanguine orphaned, no migration).
    ElseIf option == _poseNarrEmOID
        _GS_Toggle("GSAnim.PoseNarrEmergent", _poseNarrEmOID, 1)
    ElseIf option == _poseNarrPlOID
        _GS_Toggle("GSAnim.PoseNarrPlayer", _poseNarrPlOID, 1)
    ; [REV-178b Leg 2.3] the pose reaction-lane toggles (GSAnim.PoseLane_*,
    ; None-keyed, default mirrors A15; register DRAFT tooltips).
    ElseIf option == _gsPoseLaneNarrOID
        _GS_Toggle("GSAnim.PoseLane_narr", _gsPoseLaneNarrOID, 1)
    ElseIf option == _gsPoseLaneThoughtOID
        _GS_Toggle("GSAnim.PoseLane_thought", _gsPoseLaneThoughtOID, 0)
    ElseIf option == _gsPoseLanePSpeechOID
        _GS_Toggle("GSAnim.PoseLane_pspeech", _gsPoseLanePSpeechOID, 1)
    ElseIf option == _gsPoseLanePThoughtOID
        _GS_Toggle("GSAnim.PoseLane_pthought", _gsPoseLanePThoughtOID, 1)
    ; [REV-179 Leg 2] the CASE compose-time toggles (GSAnim.CaseInCue /
    ; SNBaka.CaseInCue, None-keyed, DEFAULT ON; plain desc everywhere
    ; downstream when OFF -- the composers read the key fresh per fire).
    ElseIf option == _bakaCaseCueOID
        _GS_Toggle("SNBaka.CaseInCue", _bakaCaseCueOID, 1)
    ElseIf option == _gsCaseCueOID
        _GS_Toggle("GSAnim.CaseInCue", _gsCaseCueOID, 1)
    ; REV-167 t3 (entry 44, §3.4): the selection toggles.
    ; [REV-174 A3] Madness + Banded handlers RETIRED with the toggles.
    ElseIf option == _sheoSelOID
        _GS_Toggle("GSAnim.SheoSelection", _sheoSelOID, 1)
        If StorageUtil.GetIntValue(None, "GSAnim.SheoSelection", 1) == 1
            Debug.Notification("Sheogorath Selection: Perverse Fit.")
        Else
            Debug.Notification("Sheogorath Selection: Random.")
        EndIf
    ; [REV-174 D3 A15] reaction-lane toggles. Baka modes: motherboard
    ; properties (read FRESH per fire, no re-arm needed). GS modes: the
    ; _GS_Toggle helper (None-keyed GSAnim.* keys, default 1 = ON).
    ElseIf option == _reactArbOID
        Main.bReactArbitration = !Main.bReactArbitration
        SetToggleOptionValue(_reactArbOID, Main.bReactArbitration)
    ElseIf option == _mephLaneNarrOID
        Main.bMephalaLaneNarr = !Main.bMephalaLaneNarr
        SetToggleOptionValue(_mephLaneNarrOID, Main.bMephalaLaneNarr)
    ElseIf option == _mephLaneThoughtOID
        Main.bMephalaLaneThought = !Main.bMephalaLaneThought
        SetToggleOptionValue(_mephLaneThoughtOID, Main.bMephalaLaneThought)
    ElseIf option == _mephLanePSpeechOID
        Main.bMephalaLanePSpeech = !Main.bMephalaLanePSpeech
        SetToggleOptionValue(_mephLanePSpeechOID, Main.bMephalaLanePSpeech)
    ElseIf option == _mephLanePThoughtOID
        Main.bMephalaLanePThought = !Main.bMephalaLanePThought
        SetToggleOptionValue(_mephLanePThoughtOID, Main.bMephalaLanePThought)
    ElseIf option == _molagLaneNarrOID
        Main.bMolagBalLaneNarr = !Main.bMolagBalLaneNarr
        SetToggleOptionValue(_molagLaneNarrOID, Main.bMolagBalLaneNarr)
    ElseIf option == _molagLaneThoughtOID
        Main.bMolagBalLaneThought = !Main.bMolagBalLaneThought
        SetToggleOptionValue(_molagLaneThoughtOID, Main.bMolagBalLaneThought)
    ElseIf option == _molagLanePSpeechOID
        Main.bMolagBalLanePSpeech = !Main.bMolagBalLanePSpeech
        SetToggleOptionValue(_molagLanePSpeechOID, Main.bMolagBalLanePSpeech)
    ElseIf option == _molagLanePThoughtOID
        Main.bMolagBalLanePThought = !Main.bMolagBalLanePThought
        SetToggleOptionValue(_molagLanePThoughtOID, Main.bMolagBalLanePThought)
    ElseIf option == _gsReactArbOID
        _GS_Toggle("GSAnim.ReactArbitration", _gsReactArbOID, 1)
    ElseIf option == _gsSangLaneNarrOID
        _GS_Toggle("GSAnim.SanguineLane_narr", _gsSangLaneNarrOID, 1)
    ElseIf option == _gsSangLaneThoughtOID
        _GS_Toggle("GSAnim.SanguineLane_thought", _gsSangLaneThoughtOID, 1)
    ElseIf option == _gsSangLanePSpeechOID
        _GS_Toggle("GSAnim.SanguineLane_pspeech", _gsSangLanePSpeechOID, 1)
    ElseIf option == _gsSangLanePThoughtOID
        _GS_Toggle("GSAnim.SanguineLane_pthought", _gsSangLanePThoughtOID, 1)
    ElseIf option == _gsSheoLaneNarrOID
        _GS_Toggle("GSAnim.SheogorathLane_narr", _gsSheoLaneNarrOID, 1)
    ElseIf option == _gsSheoLaneThoughtOID
        _GS_Toggle("GSAnim.SheogorathLane_thought", _gsSheoLaneThoughtOID, 1)
    ElseIf option == _gsSheoLanePSpeechOID
        _GS_Toggle("GSAnim.SheogorathLane_pspeech", _gsSheoLanePSpeechOID, 1)
    ElseIf option == _gsSheoLanePThoughtOID
        _GS_Toggle("GSAnim.SheogorathLane_pthought", _gsSheoLanePThoughtOID, 1)
    ; [REV-174f Leg 4.4] Baka ACTION lanes (None-keyed; thought defaults OFF)
    ElseIf option == _bakaActLaneNarrOID
        _GS_Toggle("SNBaka.Action.Lane_narr", _bakaActLaneNarrOID, 1)
    ElseIf option == _bakaActLaneThoughtOID
        _GS_Toggle("SNBaka.Action.Lane_thought", _bakaActLaneThoughtOID, 0)
    ElseIf option == _bakaActLanePSpeechOID
        _GS_Toggle("SNBaka.Action.Lane_pspeech", _bakaActLanePSpeechOID, 1)
    ElseIf option == _bakaActLanePThoughtOID
        _GS_Toggle("SNBaka.Action.Lane_pthought", _bakaActLanePThoughtOID, 1)
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
    ; REV-145: the _spankPlayerOID/_spankMaleOID legs are RETIRED with their rows
    ; (REV-144 policy + the SS-C fold); nothing else touches those properties.
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
    ElseIf option == _tattooAskOID    ; REV-178e rider 4 / S250
        Main.bTattooSelectAsk = !Main.bTattooSelectAsk
        SetToggleOptionValue(_tattooAskOID, Main.bTattooSelectAsk)
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
    ; REV-109c: the REV-109b section-navigation handler chain is REMOVED with
    ; the navigation model (supersession banner at the file header). The
    ; stacked body has no nav OIDs; the handlers above are the full set.
EndEvent

; REV-68 — get-up key rebinding for the consolidated bridge section. Writes the same
; SNAcheron.GetUpKey StorageUtil key the bridge's own MCM used (identical defaults/handling;
; the bridge quest reads it every tick, so no nudge is needed for a keybind).
Event OnOptionKeyMapChange(Int option, Int keyCode, String conflictControl, String conflictName)
    If option == _achGetUpKeyOID
        Actor achPk = Game.GetPlayer()
        If !achPk
            achPk = Game.GetPlayer()
        EndIf
        StorageUtil.SetIntValue(achPk, "SNAcheron.GetUpKey", keyCode)
        SetKeyMapOptionValue(_achGetUpKeyOID, keyCode)
    EndIf
EndEvent

; ============================================================================
; REV-134d (R2, user-ruled 2026-10-21): THE DECAL SOURCE DROPDOWN.
; The "SexLab Climax Proxy Share" boolean toggle is RETIRED; this cycling menu
; option lists the supported cum decal sources, PRESENCE-GATED (absent sources
; are not offered): 0=OCum (default, user-ruled), 1=SexLab, 2=P+, 3=SLACS 2 + SCO.
; The user's label texts verbatim. The module's routing maps to the selection
; (SNBaka_CumDetectionModule._SelectedDecalLane -- the boolean's "ask OCum to
; decal SL scenes" logic is selection 0's behavior, remapped; the old toggle's
; DETECTION gate bSLProxyEnabled stays dormant on the motherboard, save-persisted).
; ============================================================================
Bool Function _decalSourceAvailable(Int i)
    If i == 0
        Return Main && Main._OCumInstalled()
    ElseIf i == 1
        Return SkyrimNet_BakaSL.Installed()
    ElseIf i == 2
        Return SkyrimNet_BakaSL._PplusDetected() == 1
    ElseIf i == 3
        Return Game.IsPluginInstalled("SLACS_2_Plus_SCO.esp")
    EndIf
    Return False
EndFunction

String Function _decalSourceName(Int i)
    If i == 1
        Return "SexLab"
    ElseIf i == 2
        Return "P+"
    ElseIf i == 3
        Return "SLACS 2 + SCO"
    EndIf
    Return "OCum"
EndFunction

; The available list (presence-gated): parallel value/name arrays; the
; ACCEPTED menu index maps back through the value array.
String[] Function _decalSourceNames()
    String[] a = new String[4]
    Int n = 0
    Int i = 0
    While i < 4
        If _decalSourceAvailable(i)
            a[n] = _decalSourceName(i)
            n += 1
        EndIf
        i += 1
    EndWhile
    ; REV-134d: Papyrus array sizes must be compile-time constants (no
    ; runtime-resize helper on the import path) -- the trim uses
    ; constant-size branches.
    Return _TrimDecalNames(a, n)
EndFunction

String[] Function _TrimDecalNames(String[] a, Int n)
    If n <= 0
        String[] z = new String[1]
        z[0] = ""
        Return z
    ElseIf n == 1
        String[] o1 = new String[1]
        o1[0] = a[0]
        Return o1
    ElseIf n == 2
        String[] o2 = new String[2]
        o2[0] = a[0]
        o2[1] = a[1]
        Return o2
    ElseIf n == 3
        String[] o3 = new String[3]
        o3[0] = a[0]
        o3[1] = a[1]
        o3[2] = a[2]
        Return o3
    EndIf
    String[] o4 = new String[4]
    o4[0] = a[0]
    o4[1] = a[1]
    o4[2] = a[2]
    o4[3] = a[3]
    Return o4
EndFunction

Int[] Function _decalSourceValues()
    Int[] a = new Int[4]
    Int n = 0
    Int i = 0
    While i < 4
        If _decalSourceAvailable(i)
            a[n] = i
            n += 1
        EndIf
        i += 1
    EndWhile
    ; REV-134d: same constant-size rule -- branch trim (the caller guards
    ; on vals.Length).
    Return _TrimDecalValues(a, n)
EndFunction

Int[] Function _TrimDecalValues(Int[] a, Int n)
    If n <= 0
        Int[] z = new Int[1]
        z[0] = 0
        Return z
    ElseIf n == 1
        Int[] o1 = new Int[1]
        o1[0] = a[0]
        Return o1
    ElseIf n == 2
        Int[] o2 = new Int[2]
        o2[0] = a[0]
        o2[1] = a[1]
        Return o2
    ElseIf n == 3
        Int[] o3 = new Int[3]
        o3[0] = a[0]
        o3[1] = a[1]
        o3[2] = a[2]
        Return o3
    EndIf
    Int[] o4 = new Int[4]
    o4[0] = a[0]
    o4[1] = a[1]
    o4[2] = a[2]
    o4[3] = a[3]
    Return o4
EndFunction

; The CURRENT value's display label: the selection verbatim when the source
; is present; the FIRST AVAILABLE source otherwise (a stale/present-absent
; selection degrades on display -- named, and the module's lane resolution
; performs the same degradation at drive time).
String Function _decalSourceLabel()
    Int sel = 0
    If Main
        sel = Main.iDecalSource
    EndIf
    If _decalSourceAvailable(sel)
        Return _decalSourceName(sel)
    EndIf
    Int[] vals = _decalSourceValues()
    If vals.Length > 0
        Return _decalSourceName(vals[0])
    EndIf
    Return _decalSourceName(sel)
EndFunction

Int Function _decalSourceMenuIndex(Int source)
    Int[] vals = _decalSourceValues()
    Int i = 0
    While i < vals.Length
        If vals[i] == source
            Return i
        EndIf
        i += 1
    EndWhile
    Return 0
EndFunction

Event OnOptionMenuOpen(Int option)
    If option == _decalOID
        ; REV-134d: the Decal Source Selection dropdown -- available sources
        ; only (presence-gated); start at the current selection's position;
        ; default = the first available source (0/OCum when present,
        ; user-ruled).
        SetMenuDialogOptions(_decalSourceNames())
        Int sel = 0
        If Main
            sel = Main.iDecalSource
        EndIf
        SetMenuDialogStartIndex(_decalSourceMenuIndex(sel))
        SetMenuDialogDefaultIndex(0)
    ElseIf option == _sexBackendOID
        SetMenuDialogOptions(_backendNames())
        SetMenuDialogStartIndex(Main.iSexBackend)
        SetMenuDialogDefaultIndex(0)
    ElseIf option == _creatureBackendOID
        SetMenuDialogOptions(_backendNames())
        SetMenuDialogStartIndex(Main.iCreatureBackend)
        SetMenuDialogDefaultIndex(0)
    ; REV-145: the _creatureVictimSexOID/_femaleOnlyOID legs are RETIRED with
    ; their rows (the SS-C fold); the _ambientSexOID dropdown replaces them.
    ElseIf option == _ambientSexOID
        SetMenuDialogOptions(_targetSexLevelNames())
        SetMenuDialogStartIndex(Main._TargetSexLevel() - 1)
        SetMenuDialogDefaultIndex(0)
    ElseIf option == _gsGenderPolicyOID
        SetMenuDialogOptions(_gsGenderPolicyNames())
        SetMenuDialogStartIndex(StorageUtil.GetIntValue(None, "GSAnim.GenderPolicy", 0))
        SetMenuDialogDefaultIndex(0)
    ; [REV-178 L3] the selection dropdowns: Method above the Subject/Target
    ; POOLS (v23 vocab; defaults per R1 -- Method default differs per mode,
    ; so each OID reads its own key/default).
    ElseIf option == _mephMethodOID || option == _molagMethodOID || option == _sangMethodOID || option == _sheoMethodOID
        SetMenuDialogOptions(_selMethodNames())
        If option == _mephMethodOID
            SetMenuDialogStartIndex(StorageUtil.GetIntValue(None, "SNBaka.MephalaSelectionMethod", 1))
            SetMenuDialogDefaultIndex(1)
        ElseIf option == _molagMethodOID
            SetMenuDialogStartIndex(StorageUtil.GetIntValue(None, "SNBaka.MolagBalSelectionMethod", 1))
            SetMenuDialogDefaultIndex(1)
        ElseIf option == _sangMethodOID
            SetMenuDialogStartIndex(StorageUtil.GetIntValue(None, "GSAnim.SanguineSelectionMethod", 1))
            SetMenuDialogDefaultIndex(1)
        Else
            SetMenuDialogStartIndex(StorageUtil.GetIntValue(None, "GSAnim.SheogorathSelectionMethod", 0))
            SetMenuDialogDefaultIndex(0)
        EndIf
    ElseIf option == _mephSubOID || option == _molagSubOID
        SetMenuDialogOptions(_selSubjectNames())
        If option == _mephSubOID
            SetMenuDialogStartIndex(StorageUtil.GetIntValue(None, "SNBaka.MephalaSubject", 0))
        Else
            SetMenuDialogStartIndex(StorageUtil.GetIntValue(None, "SNBaka.MolagBalSubject", 0))
        EndIf
        SetMenuDialogDefaultIndex(0)
    ElseIf option == _sangSubOID || option == _sheoSubOID
        SetMenuDialogOptions(_selSubjectNames())
        If option == _sangSubOID
            SetMenuDialogStartIndex(StorageUtil.GetIntValue(None, "GSAnim.SanguineSubject", 0))
        Else
            SetMenuDialogStartIndex(StorageUtil.GetIntValue(None, "GSAnim.SheogorathSubject", 0))
        EndIf
        SetMenuDialogDefaultIndex(0)
    ElseIf option == _mephTgtOID || option == _molagTgtOID || option == _sangTgtOID || option == _sheoTgtOID
        SetMenuDialogOptions(_selTargetNames())
        If option == _mephTgtOID
            SetMenuDialogStartIndex(StorageUtil.GetIntValue(None, "SNBaka.MephalaTarget", 0))
        ElseIf option == _molagTgtOID
            SetMenuDialogStartIndex(StorageUtil.GetIntValue(None, "SNBaka.MolagBalTarget", 0))
        ElseIf option == _sangTgtOID
            SetMenuDialogStartIndex(StorageUtil.GetIntValue(None, "GSAnim.SanguineTarget", 0))
        Else
            SetMenuDialogStartIndex(StorageUtil.GetIntValue(None, "GSAnim.SheogorathTarget", 0))
        EndIf
        SetMenuDialogDefaultIndex(0)
    ElseIf option == _execGateOID
        SetMenuDialogOptions(_execGateNames())
        SetMenuDialogStartIndex(_ExecGateLevel())
        SetMenuDialogDefaultIndex(0)
    EndIf
EndEvent

Event OnOptionMenuAccept(Int option, Int index)
    If option == _decalOID
        ; REV-134d: map the accepted menu index back through the available-
        ; values array (absent sources were never offered, so the index is
        ; always in range); write the motherboard property (save-persisted,
        ; default-fresh -- no old-toggle migration); the module's routing
        ; reads it live (no re-arm needed).
        Int[] vals = _decalSourceValues()
        If index >= 0 && index < vals.Length
            Main.iDecalSource = vals[index]
            SetMenuOptionValue(_decalOID, _decalSourceName(Main.iDecalSource))
            Debug.Notification("Decal source set - " + _decalSourceName(Main.iDecalSource))
        EndIf
    ElseIf option == _sexBackendOID
        Main.iSexBackend = index
        SetMenuOptionValue(_sexBackendOID, _backendName(index))
    ElseIf option == _creatureBackendOID
        Main.iCreatureBackend = index
        SetMenuOptionValue(_creatureBackendOID, _backendName(index))
    ; REV-145: the _creatureVictimSexOID/_femaleOnlyOID legs are RETIRED with
    ; their rows (the SS-C fold); the _ambientSexOID dropdown replaces them.
    ElseIf option == _ambientSexOID
        ; Ruling (c), the SS-C level mapping. Labels USER-AUTHORED, register-
        ; cited. The motherboard gates read the level live on every consult.
        If index < 0 || index > 2
            index = 0
        EndIf
        StorageUtil.SetIntValue(None, "SNBaka.TargetSexLevel", index + 1)
        SetMenuOptionValue(_ambientSexOID, _targetSexLevelName(index + 1))
        Debug.Notification("Ambient target policy set - " + _targetSexLevelName(index + 1))
    ElseIf option == _gsGenderPolicyOID
        ; REV-85 Phase B: write GSAnim.GenderPolicy (StorageUtil int on None, the
        ; GS script's own key style; save-persisted, no migration — 0 is shipped
        ; default). The GS gates read it fresh on every check, so this is live.
        If index < 0 || index > 2
            index = 0
        EndIf
        StorageUtil.SetIntValue(None, "GSAnim.GenderPolicy", index)
        SetMenuOptionValue(_gsGenderPolicyOID, _gsGenderPolicyName(index))
        Debug.Notification("GS Poses: pose gender policy set - " + _gsGenderPolicyName(index))
    ; [REV-178 L3] the twelve selection writes (Method + the Subject/Target
    ; POOLS; method clamped 0-1, subject 0-2, target 0-3); every key is read
    ; live at every draw. A Target Pool = "Player Only" (1) AUTO-ACTIVATES
    ; that module's player-target toggle (Baka: SNBaka.PlayerTargetPolicy
    ; player-keyed; GS: GSAnim.PlayerTargetable None-keyed) -- named
    ; notification, never silent.
    ElseIf option == _mephMethodOID
        If index < 0 || index > 1
            index = 1
        EndIf
        StorageUtil.SetIntValue(None, "SNBaka.MephalaSelectionMethod", index)
        SetMenuOptionValue(_mephMethodOID, _selMethodName(index))
        Debug.Notification("Mephala selection method set - " + _selMethodName(index))
    ElseIf option == _mephSubOID
        If index < 0 || index > 2
            index = 0
        EndIf
        StorageUtil.SetIntValue(None, "SNBaka.MephalaSubject", index)
        SetMenuOptionValue(_mephSubOID, _selSubjectName(index))
        Debug.Notification("Mephala subject pool set - " + _selSubjectName(index))
    ElseIf option == _mephTgtOID
        If index < 0 || index > 3
            index = 0
        EndIf
        StorageUtil.SetIntValue(None, "SNBaka.MephalaTarget", index)
        SetMenuOptionValue(_mephTgtOID, _selTargetName(index))
        Debug.Notification("Mephala target pool set - " + _selTargetName(index))
        If index == 1
            StorageUtil.SetIntValue(Game.GetPlayer(), "SNBaka.PlayerTargetPolicy", 1)
            SetToggleOptionValue(_playerTargetOID, True)
            Debug.Notification("Player targeting enabled (NPCs May Target You)")
        EndIf
    ElseIf option == _molagMethodOID
        If index < 0 || index > 1
            index = 1
        EndIf
        StorageUtil.SetIntValue(None, "SNBaka.MolagBalSelectionMethod", index)
        SetMenuOptionValue(_molagMethodOID, _selMethodName(index))
        Debug.Notification("Molag Bal selection method set - " + _selMethodName(index))
    ElseIf option == _molagSubOID
        If index < 0 || index > 2
            index = 0
        EndIf
        StorageUtil.SetIntValue(None, "SNBaka.MolagBalSubject", index)
        SetMenuOptionValue(_molagSubOID, _selSubjectName(index))
        Debug.Notification("Molag Bal subject pool set - " + _selSubjectName(index))
    ElseIf option == _molagTgtOID
        If index < 0 || index > 3
            index = 0
        EndIf
        StorageUtil.SetIntValue(None, "SNBaka.MolagBalTarget", index)
        SetMenuOptionValue(_molagTgtOID, _selTargetName(index))
        Debug.Notification("Molag Bal target pool set - " + _selTargetName(index))
        If index == 1
            StorageUtil.SetIntValue(Game.GetPlayer(), "SNBaka.PlayerTargetPolicy", 1)
            SetToggleOptionValue(_playerTargetOID, True)
            Debug.Notification("Player targeting enabled (NPCs May Target You)")
        EndIf
    ElseIf option == _sangMethodOID
        If index < 0 || index > 1
            index = 1
        EndIf
        StorageUtil.SetIntValue(None, "GSAnim.SanguineSelectionMethod", index)
        SetMenuOptionValue(_sangMethodOID, _selMethodName(index))
        Debug.Notification("Sanguine selection method set - " + _selMethodName(index))
    ElseIf option == _sangSubOID
        If index < 0 || index > 2
            index = 0
        EndIf
        StorageUtil.SetIntValue(None, "GSAnim.SanguineSubject", index)
        SetMenuOptionValue(_sangSubOID, _selSubjectName(index))
        Debug.Notification("Sanguine subject pool set - " + _selSubjectName(index))
    ElseIf option == _sangTgtOID
        If index < 0 || index > 3
            index = 0
        EndIf
        StorageUtil.SetIntValue(None, "GSAnim.SanguineTarget", index)
        SetMenuOptionValue(_sangTgtOID, _selTargetName(index))
        Debug.Notification("Sanguine target pool set - " + _selTargetName(index))
        If index == 1
            StorageUtil.SetIntValue(None, "GSAnim.PlayerTargetable", 1)
            SetToggleOptionValue(_gsPlayerTgtOID, True)
            Debug.Notification("Player targeting enabled (Player can be targeted)")
        EndIf
    ElseIf option == _sheoMethodOID
        If index < 0 || index > 1
            index = 0
        EndIf
        StorageUtil.SetIntValue(None, "GSAnim.SheogorathSelectionMethod", index)
        SetMenuOptionValue(_sheoMethodOID, _selMethodName(index))
        Debug.Notification("Sheogorath selection method set - " + _selMethodName(index))
    ElseIf option == _sheoSubOID
        If index < 0 || index > 2
            index = 0
        EndIf
        StorageUtil.SetIntValue(None, "GSAnim.SheogorathSubject", index)
        SetMenuOptionValue(_sheoSubOID, _selSubjectName(index))
        Debug.Notification("Sheogorath subject pool set - " + _selSubjectName(index))
    ElseIf option == _sheoTgtOID
        If index < 0 || index > 3
            index = 0
        EndIf
        StorageUtil.SetIntValue(None, "GSAnim.SheogorathTarget", index)
        SetMenuOptionValue(_sheoTgtOID, _selTargetName(index))
        Debug.Notification("Sheogorath target pool set - " + _selTargetName(index))
        If index == 1
            StorageUtil.SetIntValue(None, "GSAnim.PlayerTargetable", 1)
            SetToggleOptionValue(_gsPlayerTgtOID, True)
            Debug.Notification("Player targeting enabled (Player can be targeted)")
        EndIf
    ElseIf option == _execGateOID
        ; REV-93 Task 1 (port): player-keyed StorageUtil write (same pattern as the
        ; SNAcheron.* options; no CK property link). Execute_Execute re-reads it on
        ; every fire.
        _SetExecGateLevel(index)
        SetMenuOptionValue(_execGateOID, _execGateName(index))
    EndIf
EndEvent

; REV-93 Task 1 (port of the REV-92 block) - Execute-gate level names (user-ruled
; 2026-10-10; ASCII-only per the runtime-string ASCII rider).
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
    Actor p = Game.GetPlayer()
    If !p
        p = Game.GetPlayer()
    EndIf
    Return StorageUtil.GetIntValue(p, "SNBaka.ExecuteGateLevel", 0)
EndFunction

Function _SetExecGateLevel(Int i)
    Actor p = Game.GetPlayer()
    If !p
        p = Game.GetPlayer()
    EndIf
    StorageUtil.SetIntValue(p, "SNBaka.ExecuteGateLevel", i)
EndFunction

; ============================================================================
; REV-145: the ambient-target-policy dropdown labels (ruling (c); labels
; USER-AUTHORED, register-cited: baka-daemon.md REV-144 SS-C map verbatim) and
; the 30a policy read for the toggle's displayed state.
; ============================================================================
String[] Function _targetSexLevelNames()
    String[] a = new String[3]
    a[0] = "Only female targets"
    a[1] = "Male and female targets, male aggressors"
    a[2] = "Anything goes"
    Return a
EndFunction

String Function _targetSexLevelName(Int iLevel)
    If iLevel == 2
        Return "Male and female targets, male aggressors"
    ElseIf iLevel == 3
        Return "Anything goes"
    EndIf
    Return "Only female targets"
EndFunction

; Entry-30a DRAFT label read: the central player-target policy's live state.
Bool Function _PlayerTargetPolicyOn()
    Actor p = Game.GetPlayer()
    If !p
        Return False
    EndIf
    Return StorageUtil.GetIntValue(p, "SNBaka.PlayerTargetPolicy", 0) == 1
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

; REV-85 Phase B — GS Poses page: gender policy mode names (GSAnim.GenderPolicy).
; The default index is 0 everywhere (female-only = shipped default, no migration).
String[] Function _gsGenderPolicyNames()
    String[] a = new String[3]
    a[0] = "Female only"
    a[1] = "Curated (men: neutral set)"
    a[2] = "All poses"
    Return a
EndFunction

String Function _gsGenderPolicyName(Int i)
    If i == 1
        Return "Curated (men: neutral set)"
    ElseIf i == 2
        Return "All poses"
    EndIf
    Return "Female only"
EndFunction

; [REV-174a A35] the UNIFORM selection vocabularies (both modules -- the
; parity table of record, REV-174a_A35_PARITY.md).
; Subject: 0 Random / 1 Companions Only / 2 Arousal Based (NEW; legacy 2 RP
; and 3 Bio Led retired subject-side -- RP/Bio Led are target-side now).
; Target: 0 Random / 1 Bio Led (NEW -- moved from Baka subject, A36/D2) /
; 2 Relationship Priority / 3 Player Only / 4 Companions Only /
; 5 Non-Companion NPCs Only ("Companions & Player" RETIRED per A34d -- the
; per-module player-target toggle governs the player everywhere).
; [REV-174a A46] "Wide" (v21 slot 3) RETIRED pre-ship: it did not fit the
; built mechanisms nor the composed desc templates (every template ends
; subject -> action -> TARGET), and every action is already for the room via
; the direct-narration lane (audience nearby_npcs). No shipped text to retire.
String[] Function _selSubjectNames()
    ; [REV-178 L3] subject vocabulary reworked: the SUBJECT POOL (OR6: no
    ; arousal-qualified pool anywhere -- arousal rides the pack as a fact).
    ; 0 Everyone / 1 Companions Only / 2 Non-Companion NPCs Only.
    String[] s = New String[3]
    s[0] = "Everyone"
    s[1] = "Companions Only"
    s[2] = "Non-Companion NPCs Only"
    Return s
EndFunction

String[] Function _selTargetNames()
    ; [REV-178 L3] target vocabulary reworked (the TARGET POOL): Bio Led +
    ; Relationship Priority RETIRED as options (OR1 funeral: RP subsumed --
    ; relationship glosses ride every pack; Bio Led = the Narrative target
    ; behavior, needs no option). OR6: NO High Arousal anywhere.
    ; 0 Everyone / 1 Player Only / 2 Companions Only / 3 Non-Companion NPCs Only.
    String[] s = New String[4]
    s[0] = "Everyone"
    s[1] = "Player Only"
    s[2] = "Companions Only"
    s[3] = "Non-Companion NPCs Only"
    Return s
EndFunction

String[] Function _selMethodNames()
    ; [REV-178 L3] the SELECTION METHOD dropdown (sits ABOVE the pools; R1
    ; defaults: Narrative for all modes except Sheogorath = Random).
    ; 0 Random / 1 Narrative Selection.
    String[] s = New String[2]
    s[0] = "Random"
    s[1] = "Narrative Selection"
    Return s
EndFunction

String Function _selSubjectName(Int i)
    If i == 1
        Return "Companions Only"
    ElseIf i == 2
        Return "Non-Companion NPCs Only"
    EndIf
    Return "Everyone"
EndFunction

String Function _selTargetName(Int i)
    If i == 1
        Return "Player Only"
    ElseIf i == 2
        Return "Companions Only"
    ElseIf i == 3
        Return "Non-Companion NPCs Only"
    EndIf
    Return "Everyone"
EndFunction

String Function _selMethodName(Int i)
    If i == 1
        Return "Narrative Selection"
    EndIf
    Return "Random"
EndFunction

; [REV-178 L3 migration] one-time pool-space remap (marker
; SNBaka.MCMDeD.selvocab5, None-keyed; run BEFORE _BuildPages on the v23
; bump): the v22 vocabularies re-mean into the REV-178 pool space --
; silent re-meaning is a doctrine violation, so stored values are
; translated, named, once. Subject: 2 (Arousal Based) -> 0 Everyone
; (arousal is a pack fact now, never a pool filter -- OR6; sentinel'd).
; Target: 1 Bio Led -> 0 Everyone (the Narrative target behavior; OR1
; funeral), 2 RP -> 0 Everyone (retired, glosses ride the pack), 
; 3 Player Only -> 1, 4 Companions Only -> 2, 5 Non-Companion -> 3.
Function _SelVocabMigrate5()
    If StorageUtil.GetIntValue(None, "SNBaka.MCMDeD.selvocab5", 0) == 1
        Return
    EndIf
    StorageUtil.SetIntValue(None, "SNBaka.MCMDeD.selvocab5", 1)
    String[] sKeys = new String[4]
    sKeys[0] = "SNBaka.MephalaSubject"
    sKeys[1] = "SNBaka.MolagBalSubject"
    sKeys[2] = "GSAnim.SanguineSubject"
    sKeys[3] = "GSAnim.SheogorathSubject"
    Int i = 0
    While i < 4
        Int v = StorageUtil.GetIntValue(None, sKeys[i], 0)
        If v == 2
            StorageUtil.SetIntValue(None, sKeys[i], 0)
            Debug.Trace("[SNBaka] selection vocab migration: subject key " + sKeys[i] + " 2 (Arousal Based) -> 0 (Everyone; arousal is a pack fact under OR6, never a pool filter) -- REV-178")
        EndIf
        i += 1
    EndWhile
    String[] tKeys = new String[4]
    tKeys[0] = "SNBaka.MephalaTarget"
    tKeys[1] = "SNBaka.MolagBalTarget"
    tKeys[2] = "GSAnim.SanguineTarget"
    tKeys[3] = "GSAnim.SheogorathTarget"
    Int[] tMap = new Int[6]
    tMap[0] = 0
    tMap[1] = 0
    tMap[2] = 0
    tMap[3] = 1
    tMap[4] = 2
    tMap[5] = 3
    i = 0
    While i < 4
        Int v2 = StorageUtil.GetIntValue(None, tKeys[i], 0)
        If v2 > 0
            Int nV = tMap[v2]
            StorageUtil.SetIntValue(None, tKeys[i], nV)
            Debug.Trace("[SNBaka] selection vocab migration: target key " + tKeys[i] + " " + v2 + " -> " + nV + " (pool space rework; Bio Led/RP retired per OR1, Player Only renumbered to 1) -- REV-178")
        EndIf
        i += 1
    EndWhile
EndFunction

; [REV-174a A35 migration] one-time vocab remap (marker SNBaka.MCMDeD.selvocab3,
; None-keyed; run BEFORE _BuildPages on the v21 bump): the stored values' MEANINGS
; changed, and silent re-meaning is a doctrine violation -- so legacy values are
; translated, named, once. Subject 2 (RP) / 3 (Bio Led) -> 0 Random (their new
; home is Target Selection; sentinel'd, the user re-picks). Target: 1->2, 2->4,
; 3->5, 4->5, 5->6.
Function _SelVocabMigrate3()
    If StorageUtil.GetIntValue(None, "SNBaka.MCMDeD.selvocab3", 0) == 1
        Return
    EndIf
    StorageUtil.SetIntValue(None, "SNBaka.MCMDeD.selvocab3", 1)
    String[] sKeys = new String[4]
    sKeys[0] = "SNBaka.MephalaSubject"
    sKeys[1] = "SNBaka.MolagBalSubject"
    sKeys[2] = "GSAnim.SanguineSubject"
    sKeys[3] = "GSAnim.SheogorathSubject"
    Int i = 0
    While i < 4
        Int v = StorageUtil.GetIntValue(None, sKeys[i], 0)
        If v == 2 || v == 3
            StorageUtil.SetIntValue(None, sKeys[i], 0)
            Debug.Trace("[SNBaka] selection vocab migration: subject key " + sKeys[i] + " " + v + " -> 0 (Random; RP/Bio Led are target-side options now) -- REV-174a A35")
        EndIf
        i += 1
    EndWhile
    String[] tKeys = new String[4]
    tKeys[0] = "SNBaka.MephalaTarget"
    tKeys[1] = "SNBaka.MolagBalTarget"
    tKeys[2] = "GSAnim.SanguineTarget"
    tKeys[3] = "GSAnim.SheogorathTarget"
    Int[] tMap = new Int[6]
    tMap[0] = 0
    tMap[1] = 2
    tMap[2] = 4
    tMap[3] = 5
    tMap[4] = 5
    tMap[5] = 6
    i = 0
    While i < 4
        Int v2 = StorageUtil.GetIntValue(None, tKeys[i], 0)
        If v2 > 0
            Int nV = tMap[v2]
            StorageUtil.SetIntValue(None, tKeys[i], nV)
            Debug.Trace("[SNBaka] selection vocab migration: target key " + tKeys[i] + " " + v2 + " -> " + nV + " -- REV-174a A35")
        EndIf
        i += 1
    EndWhile
EndFunction

; [REV-174a A46 migration] one-time Wide-retirement remap (marker
; SNBaka.MCMDeD.selvocab4, None-keyed; run BEFORE _BuildPages on the v22
; bump): the v21 7-slot target values are re-read into the 6-slot space --
; 3 (Wide) -> 0 Random (A46 ruling: the option is withdrawn; a saved Wide
; becomes the shipped Random draw, sentinel'd), 4 -> 3, 5 -> 4, 6 -> 5.
; 0/1/2 are unchanged. Runs after selvocab3, so any legacy save passes both
; remaps in order on the same bump.
Function _SelVocabMigrate4()
    If StorageUtil.GetIntValue(None, "SNBaka.MCMDeD.selvocab4", 0) == 1
        Return
    EndIf
    StorageUtil.SetIntValue(None, "SNBaka.MCMDeD.selvocab4", 1)
    String[] tKeys = new String[4]
    tKeys[0] = "SNBaka.MephalaTarget"
    tKeys[1] = "SNBaka.MolagBalTarget"
    tKeys[2] = "GSAnim.SanguineTarget"
    tKeys[3] = "GSAnim.SheogorathTarget"
    Int[] tMap = new Int[7]
    tMap[0] = 0
    tMap[1] = 1
    tMap[2] = 2
    tMap[3] = 0
    tMap[4] = 3
    tMap[5] = 4
    tMap[6] = 5
    Int i = 0
    While i < 4
        Int v = StorageUtil.GetIntValue(None, tKeys[i], 0)
        If v > 2
            Int nV = tMap[v]
            StorageUtil.SetIntValue(None, tKeys[i], nV)
            Debug.Trace("[SNBaka] selection vocab migration (A46 Wide retirement): target key " + tKeys[i] + " " + v + " -> " + nV + " (3=Wide->Random per A46; 4/5/6 renumbered) -- REV-174a")
        EndIf
        i += 1
    EndWhile
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
        SetSliderDialogDefaultValue(60.0)
        SetSliderDialogRange(0.0, 120.0)
        SetSliderDialogInterval(5.0)
    ElseIf option == _stAmbientPctOID
        ; REV-156: user-ruled default 35 -- the chance each daemon-tick
        ; ambient exposure pass fires a visible-tattoo reaction cue.
        SetSliderDialogStartValue(StorageUtil.GetIntValue(Game.GetPlayer(), "SNBaka.ST.AmbientPct", 35) as Float)
        SetSliderDialogDefaultValue(35.0)
        SetSliderDialogRange(0.0, 100.0)
        SetSliderDialogInterval(5.0)
    ElseIf option == _fhuNoticeOID
        ; REV-154: planner default 30 -- the percent-of-max floor for ambient
        ; bystander reactions (curious stares / suggestive comments).
        SetSliderDialogStartValue(Main.iFHUAmbientNoticeBand as Float)
        SetSliderDialogDefaultValue(60.0)
        SetSliderDialogRange(5.0, 95.0)
        SetSliderDialogInterval(5.0)
    ElseIf option == _fhuHeavyOID
        ; REV-154: planner default 60 -- the percent-of-max escalation floor
        ; (scandalized whispers).
        SetSliderDialogStartValue(Main.iFHUAmbientHeavyBand as Float)
        SetSliderDialogDefaultValue(60.0)
        SetSliderDialogRange(10.0, 100.0)
        SetSliderDialogInterval(5.0)
    ; REV-159 5.2: the four mode-cadence sliders (user-ruled range 15s-240s;
    ; defaults = each arbiter's historic cadence).
    ElseIf option == _mephCadOID
        SetSliderDialogStartValue(StorageUtil.GetFloatValue(None, "SNBaka.MephalaCadence", 60.0))
        SetSliderDialogDefaultValue(60.0)
        SetSliderDialogRange(15.0, 240.0)
        SetSliderDialogInterval(5.0)
    ElseIf option == _molagCadOID
        SetSliderDialogStartValue(StorageUtil.GetFloatValue(None, "SNBaka.MolagBalCadence", 60.0))
        SetSliderDialogDefaultValue(60.0)
        SetSliderDialogRange(15.0, 240.0)
        SetSliderDialogInterval(5.0)
    ElseIf option == _sangCadOID
        SetSliderDialogStartValue(StorageUtil.GetFloatValue(None, "GSAnim.NudgeInterval", 60.0))
        SetSliderDialogDefaultValue(60.0)
        SetSliderDialogRange(15.0, 240.0)
        SetSliderDialogInterval(5.0)
    ElseIf option == _sheoCadOID
        SetSliderDialogStartValue(StorageUtil.GetFloatValue(None, "GSAnim.T3Interval", 60.0))
        SetSliderDialogDefaultValue(60.0)
        SetSliderDialogRange(15.0, 240.0)
        SetSliderDialogInterval(5.0)
    ; REV-161 4.4: the three ambient cadence sliders (15s-240s for the two
    ; 60s-cadence modules; 60s-1800s for the tattoo observation floor; defaults
    ; = each module's historic cadence -- defaults unchanged).
    ElseIf option == _fhuAmbCadOID
        SetSliderDialogStartValue(StorageUtil.GetFloatValue(None, "SNBaka.FHUAmbientCadence", 60.0))
        SetSliderDialogDefaultValue(60.0)
        SetSliderDialogRange(15.0, 240.0)
        SetSliderDialogInterval(5.0)
    ElseIf option == _cumAmbCadOID
        SetSliderDialogStartValue(StorageUtil.GetFloatValue(None, "SNBaka.CumAmbientCadence", 60.0))
        SetSliderDialogDefaultValue(60.0)
        SetSliderDialogRange(15.0, 240.0)
        SetSliderDialogInterval(5.0)
    ElseIf option == _stAmbFloorOID
        SetSliderDialogStartValue(StorageUtil.GetFloatValue(Game.GetPlayer(), "SNBaka.ST.AmbientFloor", 600.0))
        SetSliderDialogDefaultValue(600.0)
        SetSliderDialogRange(60.0, 1800.0)
        SetSliderDialogInterval(30.0)
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
        SetSliderDialogStartValue(StorageUtil.GetFloatValue(Game.GetPlayer(), "SNAcheron.CueInterval", 30.0))
        SetSliderDialogDefaultValue(60.0)
        SetSliderDialogRange(10.0, 120.0)
        SetSliderDialogInterval(5.0)
    ElseIf option == _achProxOID
        SetSliderDialogStartValue(StorageUtil.GetFloatValue(Game.GetPlayer(), "SNAcheron.ProxInterval", 10.0))
        SetSliderDialogDefaultValue(10.0)
        SetSliderDialogRange(5.0, 60.0)
        SetSliderDialogInterval(5.0)
    ElseIf option == _achConfirmOID
        SetSliderDialogStartValue(StorageUtil.GetFloatValue(Game.GetPlayer(), "SNAcheron.AutoGetUpSeconds", 600.0))
        SetSliderDialogDefaultValue(600.0)
        SetSliderDialogRange(60.0, 3600.0)
        SetSliderDialogInterval(30.0)
    ElseIf option == _achEngageOID
        SetSliderDialogStartValue(StorageUtil.GetFloatValue(Game.GetPlayer(), "SNAcheron.CreatureEngageChance", 50.0))
        SetSliderDialogDefaultValue(50.0)
        SetSliderDialogRange(0.0, 100.0)
        SetSliderDialogInterval(5.0)
    ; [REV-174a A36c] the Target Link Weight slider legs REMOVED with the row
    ; (RP is prompt-side; no mechanical two-tier draws remain to weight).
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
    ElseIf option == _fhuNoticeOID
        ; REV-154: read live at every poll tick -- no re-arm needed.
        Main.iFHUAmbientNoticeBand = value as Int
        SetSliderOptionValue(_fhuNoticeOID, value, "{0}%")
    ElseIf option == _stAmbientPctOID
        ; REV-156: read live at every daemon tick -- no re-arm needed.
        StorageUtil.SetIntValue(Game.GetPlayer(), "SNBaka.ST.AmbientPct", value as Int)
        SetSliderOptionValue(_stAmbientPctOID, value, "{0}%")
    ElseIf option == _fhuHeavyOID
        Main.iFHUAmbientHeavyBand = value as Int
        SetSliderOptionValue(_fhuHeavyOID, value, "{0}%")
    ; REV-159 5.2: the cadence keys are read live at every daemon arm/tick and
    ; every muse/T3 gate (no re-arm needed).
    ElseIf option == _mephCadOID
        StorageUtil.SetFloatValue(None, "SNBaka.MephalaCadence", value)
        SetSliderOptionValue(_mephCadOID, value, "{0}s")
    ElseIf option == _molagCadOID
        StorageUtil.SetFloatValue(None, "SNBaka.MolagBalCadence", value)
        SetSliderOptionValue(_molagCadOID, value, "{0}s")
    ElseIf option == _sangCadOID
        StorageUtil.SetFloatValue(None, "GSAnim.NudgeInterval", value)
        SetSliderOptionValue(_sangCadOID, value, "{0}s")
    ElseIf option == _sheoCadOID
        StorageUtil.SetFloatValue(None, "GSAnim.T3Interval", value)
        SetSliderOptionValue(_sheoCadOID, value, "{0}s")
    ; [REV-174a A36c] the link-weight accept leg REMOVED with the slider.
    ; REV-161 4.4: the three ambient cadence writes. FHU + Tattoo keys are
    ; read live at every pass (no re-arm needed); the Cum rule is re-armed
    ; live (RemoveTimerRule + AddTimerRule with the new cadence, the same
    ; key-deduped idempotent shape the module's own re-arm uses) -- guarded
    ; so an absent/off module never gets spuriously armed from the MCM.
    ElseIf option == _fhuAmbCadOID
        StorageUtil.SetFloatValue(None, "SNBaka.FHUAmbientCadence", value)
        SetSliderOptionValue(_fhuAmbCadOID, value, "{0}s")
    ElseIf option == _cumAmbCadOID
        StorageUtil.SetFloatValue(None, "SNBaka.CumAmbientCadence", value)
        If Main && Main._OCumInstalled() && Main.bCumDetectionEnabled
            DeDService.RemoveTimerRule("cum", "ambient")
            DeDService.AddTimerRule("cum", "ambient", value, 1, None, "cum.present", 600.0, "sdb_cum_ambient_due")
            Debug.Trace("[SNBaka] MCM: cum ambient rule re-armed at " + value + "s cadence (REV-161 4.4)")
        EndIf
        SetSliderOptionValue(_cumAmbCadOID, value, "{0}s")
    ElseIf option == _stAmbFloorOID
        StorageUtil.SetFloatValue(Game.GetPlayer(), "SNBaka.ST.AmbientFloor", value)
        SetSliderOptionValue(_stAmbFloorOID, value, "{0}s")
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
        StorageUtil.SetFloatValue(Game.GetPlayer(), "SNAcheron.CueInterval", value)
        SetSliderOptionValue(_achCueOID, value, "{0} s")
    ElseIf option == _achProxOID
        StorageUtil.SetFloatValue(Game.GetPlayer(), "SNAcheron.ProxInterval", value)
        SetSliderOptionValue(_achProxOID, value, "{0} s")
    ElseIf option == _achConfirmOID
        StorageUtil.SetFloatValue(Game.GetPlayer(), "SNAcheron.AutoGetUpSeconds", value)
        SetSliderOptionValue(_achConfirmOID, value, "{0} s")
    ElseIf option == _achEngageOID
        StorageUtil.SetFloatValue(Game.GetPlayer(), "SNAcheron.CreatureEngageChance", value)
        SetSliderOptionValue(_achEngageOID, value, "{0}%")
    EndIf
EndEvent

Event OnOptionHighlight(Int option)
    ; REV-134d (R2, user-ruled 2026-10-21, texts VERBATIM): the Cum-page
    ; descriptions are now TOOLTIPS (SetInfoText, shown on highlight), not
    ; subtext rows (the REV-134c static rows are removed per the ruling).
    If option == _cumDetectOID
        SetInfoText("Enable/disable the SkyrimNet cum detection cues created by this module.")
    ElseIf option == _decalOID
        SetInfoText("Pick the cum decal source for this module to apply and track.")
    ElseIf option == _moreCumOID
        SetInfoText("Adds additional location friendly cum decals on orgasm events.")
    ElseIf option == _cumFollowUpOID
        ; REV-134f: the user's tooltip text, verbatim.
        SetInfoText("Additional direct narration for cum application events")
    ElseIf option == _fhuNarrOID
        ; REV-153: tooltip DRAFT per the user's exchange shape ("a similar
        ; format to the cum detection prompt + optional direct narration
        ; trigger") -- register entry 33, the user's pen.
        SetInfoText("Additional direct narration for inflation cues")
    ElseIf option == _fhuAmbNarrOID
        ; REV-154: tooltip DRAFT (register entry 34, the user's pen).
        SetInfoText("Additional direct narration for ambient bystander cues")
    ElseIf option == _fhuNoticeOID
        ; REV-154: tooltip DRAFT (register entry 34, the user's pen).
        SetInfoText("Bystander reactions start once inflation passes this percent of Fill Her Up's maximum (default 30%).")
    ElseIf option == _fhuHeavyOID
        ; REV-154: tooltip DRAFT (register entry 34, the user's pen).
        SetInfoText("Reactions escalate to scandalized whispers above this percent (default 60%).")
    ElseIf option == _fhuAwareOID
        ; REV-159 3.2(b) (USER-PROVIDED verbatim): the retired three-row subtext
        ; delivered as the tooltip on highlight (SetInfoText pattern).
        SetInfoText("Enable/disable cues and reactions for Fill Her Up Baka")
    ; REV-159 5.1/5.2/5.3: the new mode-narration + cadence + pose-narration
    ; tooltip DRAFTS (register entry 37, the user's pen; the 134f naming
    ; pattern; the pose-narration tooltips use the lean "narration cue"
    ; resolution of the user's {{prompt/trigger}} placeholders).
    ; [REV-174 D3 LEG 4] the mode-narration tooltips REMOVED with the toggles.
    ElseIf option == _mephCadOID
        SetInfoText("Seconds between Mephala Mode action opportunities (default 60s).")
    ElseIf option == _molagCadOID
        SetInfoText("Seconds between Molag Bal Mode action opportunities (default 60s).")
    ; [REV-179 Leg 2] tooltip DRAFT at the user's pen (register Entry 56).
    ElseIf option == _bakaCaseCueOID
        SetInfoText("When on (default), mode action cues end with the model's one-line why-now motive and the witness closing line. Turn off for plain cues: just who did what to whom -- no reasoning line and no closer, in cues and narration alike.")
    ; [REV-179 rider] the Entry-55 item-4 DRAFT GAP closed (SetInfoText owed at
    ; the user's pen since 178e; text DRAFT register Entry 56).
    ElseIf option == _tattooAskOID
        SetInfoText("When on (default), tattoo actions have the model choose the actual design from the packs installed for that body -- a second look at the scene, recent dialogue, and the full list of options. When off, the action's suggested pack and name are validated against your installed packs instead (curated pick, no second look).")
    ; [REV-174e Leg 4] the mode-narration highlight stubs REMOVED with the rows.
    ElseIf option == _sangCadOID
        SetInfoText("Seconds between Sanguine Mode pose opportunities (default 60s).")
    ElseIf option == _sheoCadOID
        SetInfoText("Seconds between Sheogorath Mode pose opportunities (default 60s).")
    ; [REV-179 Leg 2] tooltip DRAFT at the user's pen (register Entry 56).
    ElseIf option == _gsCaseCueOID
        SetInfoText("When on (default), pose and mode cues end with the model's one-line why-now motive and the witness closing line. Turn off for plain cues: just who did what to whom -- no reasoning line and no closer, in cues and narration alike.")
    ; [REV-174d Leg 3.2] "Sanguine Pose Narration" handler RETIRED with the toggle
    ;   (REV-174a D3 lanes-only; key GSAnim.PoseNarrSanguine orphaned, no migration).
    ; [REV-178b Leg 2.1] tooltip DRAFTs for the relabeled pose-reaction toggles
    ;   and the new pose lanes (register DRAFT batch at the user's pen).
    ElseIf option == _poseNarrEmOID
        SetInfoText("Send the reaction cues when autonomous or emergent forces pose an NPC (default on).")
    ElseIf option == _poseNarrPlOID
        SetInfoText("Send the reaction cues when you pose an NPC or gesture for them to stop (default on).")
    ElseIf option == _gsPoseLaneNarrOID || option == _gsPoseLaneThoughtOID
        SetInfoText("Fanned narration or NPC-thought reaction lane on emergent and player-initiated pose fires (rotates, never the same lane twice in a row; default narration on, thought off).")
    ElseIf option == _gsPoseLanePSpeechOID || option == _gsPoseLanePThoughtOID
        SetInfoText("Fanned player-speech or player-private-thought reaction lane on emergent and player-initiated pose fires (default on).")
    ; [REV-178 L3] the pool-surface tooltips (register DRAFT batch -- the
    ; user's pen owns final wording; §8.1 class discipline).
    ; [REV-174a A35 -> REV-174d Leg 1] the selection-surface tooltip; Bio Led +
    ;   Relationship Priority now carry the USER-RULED final sentences (dogfood items
    ;   5/6, verify-then-apply: the A35 draft was live on disk, corrected text applied).
    ; [REV-174 A3] Madness + Banded tooltips RETIRED with the toggles.
    ; [REV-174a A36c] the link-weight tooltip RETIRED with the slider.
    ; [REV-178] Bio Led + Relationship Priority option tooltips RETIRED with
    ;   the options (OR1 funeral; Bio Led's ruled tooltip text retires WITH the
    ;   option -- it described a targeting mode that no longer exists).
    ElseIf option == _mephMethodOID || option == _molagMethodOID || option == _sangMethodOID || option == _sheoMethodOID
        SetInfoText("Narrative Selection: the AI reads the scene and each candidate's facts (bio, relationship with you, arousal, mood) and picks the subject that makes the best story. Random: pure chance. (Default: Narrative; Sheogorath defaults to Random.)")
    ElseIf option == _mephSubOID || option == _molagSubOID || option == _sangSubOID || option == _sheoSubOID
        SetInfoText("Choose who can initiate this mode's actions: anyone eligible (default), your companions only, or non-companion NPCs only. The player is never picked as the initiator.")
    ElseIf option == _mephTgtOID || option == _molagTgtOID || option == _sangTgtOID || option == _sheoTgtOID
        SetInfoText("Choose who this mode's actions can happen to: anyone eligible (default), you only (needs this module's player-targeting toggle on, auto-enabled), your companions only, or non-companion NPCs only.")
    ElseIf option == _gsPlayerTgtOID
        SetInfoText("Allow this module's modes to target you (default off). Choosing Player Only under a Target Selection above turns this on automatically.")
    ElseIf option == _gsDebugNotifyOID
        SetInfoText("Show a corner notification when this framework's mode/pose reaction lanes fire (default off; a debugging aid).")
    ElseIf option == _sheoSelOID
        SetInfoText("When on (default), Sheogorath picks perversely fitting poses via the AI. When off, poses are drawn by pure random chance.")
    ; [REV-174 D3 A15] reaction-lane tooltip DRAFTS (register, the user's pen).
    ElseIf option == _reactArbOID || option == _gsReactArbOID
        SetInfoText("When on (default), the AI's REACT pick decides which reaction lanes fire per event; a missing or invalid pick fails open (all enabled lanes). When off, all enabled lanes always fire.")
    ElseIf option == _mephLaneNarrOID || option == _molagLaneNarrOID || option == _gsSangLaneNarrOID || option == _gsSheoLaneNarrOID
        SetInfoText("The narration reaction lane: a visible narration event asking nearby characters to witness and react (default on).")
    ElseIf option == _bakaActLaneNarrOID
        SetInfoText("[DRAFT] The action narration lane: on LLM- or player-initiated interactions, a visible narration event asking nearby characters to witness and react (default on). Daemon/mode fires use the mode-branded lanes instead.")
    ElseIf option == _mephLaneThoughtOID || option == _molagLaneThoughtOID || option == _gsSangLaneThoughtOID || option == _gsSheoLaneThoughtOID
        SetInfoText("The (public) thought reaction lane: a spoken-aloud inner thought for nearby characters (default on).")
    ElseIf option == _mephLanePSpeechOID || option == _molagLanePSpeechOID || option == _gsSangLanePSpeechOID || option == _gsSheoLanePSpeechOID
        SetInfoText("The speech reaction lane: nearby characters may comment out loud (default on).")
    ElseIf option == _bakaActLanePSpeechOID
        SetInfoText("[DRAFT] The action speech lane: nearby characters may comment out loud on LLM- or player-initiated interactions (default on). Daemon/mode fires use the mode-branded lanes instead.")
    ElseIf option == _mephLanePThoughtOID || option == _molagLanePThoughtOID || option == _gsSangLanePThoughtOID || option == _gsSheoLanePThoughtOID
        SetInfoText("The private thought reaction lane: a private inner thought for nearby characters, spoken to no one (default on).")
    ElseIf option == _bakaActLaneThoughtOID || option == _bakaActLanePThoughtOID
        SetInfoText("[DRAFT] The action thought / private-thought lanes: inner-thought reactions to LLM- or player-initiated interactions (thought defaults OFF; private thought defaults on). Daemon/mode fires use the mode-branded lanes instead.")
    ElseIf option == _enabledOID
        SetInfoText("Master switch for all Baka motion interactions.")
    ElseIf option == _animatedTearsOID
        SetInfoText("Apply animated 3D tears to female victims during aggressive scenes. Requires Emotional Tears Effect SE (EmoTears4NPCs.esp). Has no effect if that mod is not installed.")
    ElseIf option == _playerTargetOID
        ; REV-150 4.4 (register entry 30a CLOSED at this build): the user's
        ; 2026-10-24 edit pass REMOVED the saves-migration sentence ("Existing
        ; saves started with their old spank-target setting." - Cline's draft,
        ; never the user's; shipped at REV-145 while the entry was open). The
        ; remaining tooltip text is the WORDING OF RECORD (PROJECT_STATE
        ; 170.1 correction; this line is the 30a source-debt payment).
        SetInfoText("When on, NPCs and creatures may choose you as the target of their autonomous actions (the Baka module's single central gate; your own initiations are never blocked). When off, nothing targets you unless you start it.")
    ElseIf option == _ambientSexOID
        SetInfoText("The three-level target-sex policy for NPC-initiated actions and the ambient modes: only female targets; male and female targets with male aggressors; or anything goes. Anatomically-specific actions always require female bodies regardless. Existing saves started from their old Target Sex setting.")
    ; REV-146a: the _mephalaOID/_molagBalOID info texts REMOVED with their
    ; toggles (Prisma-only ruling; unbound OIDs never reach this handler).
    ElseIf option == _cooldownOID
        SetInfoText("Minimum real-time seconds between NPC-initiated actions. Default 30s.")
    ElseIf option == _execGateOID
        SetInfoText("REV-93: how the Execute action may be used. Unlimited = no gate. Companions ask / Always ask = the confirm dialog appears (companion-initiated only, or every time). Player hotkey Execute bypasses this gate.")
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
    ; REV-145: the _spankPlayerOID/_spankMaleOID highlight legs are RETIRED with
    ; their rows (REV-144 policy + the SS-C fold).
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
    ; REV-145: the _creatureVictimSexOID highlight leg is RETIRED with its row
    ; (the SS-C fold under Ambient Target Policy).
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
        ; [REV-181 T3] fix-2 semantics note + the defer-to-host guidance (register DRAFT - user pen).
        SetInfoText("NPCs ONLY: hard ceiling on how long an abandoned, unattended down lasts before they get up on their own - NPCs have no get-up key, so this stands in for it. The PLAYER never auto-recovers: get-up key, being helped, or winning a QTE are the only ways up. Resets to the full duration whenever someone interacts with the victim (a struggle, choke, inspect, escalation, etc.), so it never expires mid-scene. While a fight is still live, anyone able standing nearby postpones it a minute at a time; once the fight is over, only the player's presence still does, and it buys a single 60 s extension - recovery then lands about a minute after the last witnessed moment. If Acheron's own downed system (or another defeat mod) still manages this actor, defer to the host mod's timer for anything it controls - this ceiling only governs the downs DeD holds. Default 600 s (10 min).")
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
        ; REV-156: re-pointed to the daemon-tick ambient exposure pass (the
        ; v1 ~4h heartbeat pass is retired). Register entry 35 DRAFT.
        SetInfoText("Master gate for ambient tattoo reaction cues: while a Baka daemon mode is on, every daemon tick rolls a chance for nearby personas to notice any VISIBLE tattoo - covered marks are not reacted to, marks applied by any means are. Default ON.")
    ElseIf option == _stAmbientPctOID
        ; REV-156. Register entry 35 DRAFT.
        SetInfoText("Chance each daemon-tick ambient pass fires a visible-tattoo reaction cue when someone nearby has an exposed mark (default 35%). Failing rolls are silent.")
    ElseIf option == _stAmbientNarrOID
        ; REV-156: the Follow-up Prompt pattern (134f/153/154) applied to the
        ; tattoo ambient cue - the gated second surface. DEFAULT OFF. Register
        ; entry 35 DRAFT.
        SetInfoText("Additional direct narration for ambient tattoo reaction cues (a second prompt surface on top of the mandatory cue). Default OFF.")
    ElseIf option == _qteKeysOID
        ; REV-109 length audit (class (b) split): the WASD / d-pad detail moved
        ; here from the (over-length) value string.
        SetInfoText("Struggle QTE keys: WASD / d-pad. Not configured here - set them in the 'Flash Games' mod's Struggling QTE section.")
    ElseIf option == _stIntroOID
        ; REV-109 length audit (class (b) split): the full sentence moved here
        ; from the (over-length) label.
        SetInfoText("Sets are chosen in the in-game Tattoo Menu; this section only decides WHICH events fire them automatically.")
    ElseIf option == _gsIntroOID
        ; REV-109 length audit (class (b) split): the full explanation moved
        ; here from the (over-length) label.
        SetInfoText("Who may be posed, by body: female-only keeps the shipped behavior; curated admits men to the neutral set; all-poses opens the whole library.")
    EndIf
EndEvent

; REV-74 — default-color palette shared by the MCM cycle and the picker swatches.
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

; REV-72 SlaveTats toggle helper — flips a player-keyed SNBaka.ST.* int between 1 and 0.
Function _ST_Toggle(String asKey, Int aiOID, Int aiDefault)
    Actor p = Game.GetPlayer()
    If !p
        p = Game.GetPlayer()
    EndIf
    Int v = 1 - StorageUtil.GetIntValue(p, asKey, aiDefault)
    StorageUtil.SetIntValue(p, asKey, v)
    SetToggleOptionValue(aiOID, v == 1)
EndFunction

; REV-159 5.1/5.3: GS toggle helper — flips a None-keyed GSAnim.* int between
; 1 and 0 (the _ST_Toggle pattern, None-keyed).
Function _GS_Toggle(String asKey, Int aiOID, Int aiDefault)
    Int v = 1 - StorageUtil.GetIntValue(None, asKey, aiDefault)
    StorageUtil.SetIntValue(None, asKey, v)
    SetToggleOptionValue(aiOID, v == 1)
EndFunction

; REV-159: "enabled"/"disabled" for the GS narration notifications.
String Function _OnOff(Int aiV)
    If aiV == 1
        Return "enabled"
    EndIf
    Return "disabled"
EndFunction
