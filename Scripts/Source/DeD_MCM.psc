Scriptname DeD_MCM extends SKI_ConfigBase

; ============================================================================
; DeD_MCM (renamed from SNBaka_MCM at ) —  REPLACEMENT MCM quest
; ("Delectatio et Dominium").
;
; Lineage: the direct successor of SkyrimNet_BakaIntegration_MCM (the v7 MCM).
; The old quest was neutered at  (script detached, record kept; its
; cached save-instance was pathological beyond version dispatch — see
; PROJECT_STATE /). This quest is a FRESH formID (QUST 04000D99): an
; existing save spins up a fresh instance and registers fresh.
;
; CANARY RULE (user ruling,  — standing for every MCM-touching build):
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
; Settings: zero migration ( Task-1 audit) — all player state lives in
; StorageUtil (SNBaka.*, SNBaka.ST.*, SNAcheron.*, player-keyed) or as
; properties on the surviving MAIN quest (04000D62). Known pre-existing skew
; (fEscapeGraceDuration dual-write, old script L793) carried unchanged.
; ============================================================================

; ============================================================================
;  SEVERANCE (user ruling of record 2026-10-1X, "Boundary S4a" - the SHAPE
; OF RECORD): the MCM quest is the FRAMEWORK's config surface - every module hangs
; its pages on it presence-gated; Baka's settings become module pages like any
; other; the eventual PHYSICAL host is a DeD Framework esp (S4b, esp session -
; this session is script-only, no esp bytes, scriptname/EDID unchanged; the rename
; rides S4b). Task 1.1: the MCM stops using the compiled `Main` property (the esp
; VMAD auto-fill link is what kept the MCM hostage to the motherboard quest) and
; resolves the motherboard AT RUNTIME via GetFormFromFile(0xD62, Baka esp) + cast
; - the same resolution pattern as SkyrimNet_BakaIntegration.GetMain (that script,
; L1207) and SkyrimNet_BakaInteg_SpankPartner (L13). Absent motherboard = None =
; the Baka pages don't build ( precedent); the MCM itself lives on. Setting
; storage is UNCHANGED (/ discipline: no new migration; the resolver hands
; back the exact same quest instance the compiled link used to).
; NOTE (physical reachability, recorded ): today the MCM quest record and the
; motherboard quest record are co-homed in SkyrimNet_BakaIntegration.esp, so the
; absent-motherboard state is not physically reachable until S4b moves the MCM
; quest record to the framework esp. This machinery is the logical re-home; the
; S4b gate activates it.
; ============================================================================

; ============================================================================
;  S4b (the PHYSICAL re-home): the MCM quest record MOVED from
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
; the  replacement history; settings live in StorageUtil per ) —
; one-session cosmetic cost; the new quest instance registers fresh.
; ============================================================================

; ============================================================================
;  MCM RESTRUCTURE (user ruling 2026-10-1X, era roadmap item 7 + the
;  planner ticket of record - the productization restructure):
;   - framework-level configurables gather under a NEW "Settings" page (first
;     page): master enable (Enable Mod, moved from General), the global action
;     cooldown (moved from General), the stuck-state reset (moved from
;     General's Maintenance section), the debug log (moved from Scenes & FX),
;     plus the title header + tagline (first-page rider,  convention).
;   - the five Baka pages fold under a "Baka Interactions" section: SkyUI
;     SKI_ConfigBase Pages[] is a FLAT left-pane list with NO sub-page
;     nesting, so the section is realized as prefixed sibling pages
;     ("Baka - General" / "Baka - Timing" / "Baka - Resist" / "Baka - Spank"
;     / "Baka - Scenes & FX"), grouped contiguously - the  precedent
;     (separate expandable pages, not one long page); choice FLAGGED for the
;     user gate (Task 2.1).
;   - module pages UNCHANGED in position/content (Lap Sitting / Cum Effects /
;     Fill Her Up / Acheron / SlaveTats / GS Poses).
;   - NO NEW OPTIONS (no-stubbing rule): what does not exist today (clean
;     uninstall, stop-all beyond the panic reset, framework-native settings)
;     is the  gap list (era doc; polish pool), not built here.
;   - RIDERS (user ruling 2026-10-1X): the full-surface ASCII sweep (receipt:
;     0 non-ASCII in every runtime string literal, swept comment-stripped
;     this rev) + the display-length audit (labels >40 chars / values >30
;     chars = findings; fixes per class (a) shorten / (b) label-vs-info split;
;     every reworded string ->  register, bulk entry).
; ============================================================================

; ============================================================================
;  MCM RESTRUCTURE PASS 3 (user ruling 2026-10-1X): the "Baka
; Interactions" page is ONE page whose body STACKS the six family sections
; (General / Timing / Resist / Spank / Scenes & FX / Lap Sitting - the
; user's own wording), each preceded by a section-header row:
;   - SUPERSESSION BANNER (not silent deletion): 's in-page
;     section-NAVIGATION model - the _biSection state, the index render,
;     the "Open" rows, the "<< Back" rows, the nav OIDs + the
;     CurrentPage-guarded handler chain - is REMOVED by this pass per the
;     user's ruling. Register entry 17a ("Open"/"<< Back" drafts) is VOIDED
;     with it: the strings it gated no longer exist.
;   - PAGE HEADER: the  title + tagline rider (carried from the
;     Settings header pair).
;   - SECTION HEADERS: the  house pattern - spacer + header row
;     (the "Auto-Apply Sets" exemplar, SlaveTats page).
;   - CENSUS (Task 1.3): every  option present EXACTLY ONCE in the
;     stacked body, zero lost, zero duplicated (before == after enforced;
;     receipt in the build record).
;   - ASCII sweep (Task 1.5): the new surfaces are the page/section header
;     rows + spacers; the six section names are the user's own list
;     (register 17b, cited not gated).
; ============================================================================

SkyrimNet_BakaIntegration Main    ; : plain member variable, NOT a compiled
                                  ; Auto property - resolved at runtime below. All
                                  ; consumer sites are unchanged (same name, same
                                  ; members); only the BINDING changed.

Bool _gsFound = False             ; : cached GS esp presence (a found state
                                  ; is permanent for a save's lifetime; an absent
                                  ; esp re-probes at the next _BuildPages - the
                                  ; GetFormFromFile-on-absent-esp hard-error rule
                                  ; cited at SNBaka_CumDetectionModule L22).

;  Task 1.1 - the motherboard resolution, presence-gated, sentinel-once:
; when found, the result is cached for the session (plugins can't change mid-run),
; so the "found" sentinel logs ONCE; when absent, _ResolveMain re-probes at every
; OnGameReload, so the "absent" sentinel logs ONCE PER LOAD (the 
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

;  Task 1.3 - GS Poses presence gate (the leaked one: the page previously
; rendered unconditionally and wrote GSAnim.GenderPolicy even with the GS esp
; absent - a dead page per the  class). Same probe the motherboard's module-arm
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
Int _execGateOID = -1      ;  Task 1: ported from the DEAD v7 script ( built it there by
                      ; mistake — SkyrimNet_BakaIntegration_MCM is the neutered pre- quest;
                      ; THIS quest is the live MCM). Levels: 0 Unlimited / 1 Companions ask /
                      ; 2 Always ask; key SNBaka.ExecuteGateLevel (player-keyed StorageUtil).
                      ;  Task 2.2: DEFAULT = 0 (Unlimited) USER-CONFIRMED 2026-10-11
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
Int _qteKeysOID = -1        ;  length audit (class (b) split): the QTE-keys
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
;  detection + inflation triggers (own pages since : Cum Effects / Fill Her Up)
Int _cumDetectOID = -1
Int _slProxyOID = -1
Int _fhuAwareOID = -1
;  "Downed State (Acheron Bridge)" settings (own "Acheron" page since ) — consolidated from the
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
;  "SlaveTats Degradation Sets" section (own "SlaveTats" page since ) — SNBaka_SlaveTatsModule state
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
;  Phase B — GS Poses top-level page: the gender policy mode selector
; (GSAnim.GenderPolicy StorageUtil int on None; 0 = female-only default).
Int _gsGenderPolicyOID = -1
Int _stIntroOID = -1        ;  length audit (class (b) split): the ST intro
                            ; text option - short label, full sentence in InfoText.
Int _gsIntroOID = -1        ;  length audit (class (b) split): the GS Poses
                            ; intro text option - same shape.
; : the  in-page navigation state + nav OIDs (_biSection,
; _biBackOID, _biNav*OID) are REMOVED with the navigation model per the
; pass-3 ruling (supersession banner at the file header). The stacked body
; renders every section unconditionally - no section state, no nav OIDs.

Event OnConfigInit()
    ModName = "Delectatio et Dominium"
    _ResolveMain()   ;  S4a: runtime motherboard resolution BEFORE the page build
    _BuildPages()
    ;  canary — first-registration sentinel (one-time, per-player): versioned
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
    _ResolveMain()   ;  S4a: re-probe per load while the motherboard is absent
                     ; (once-per-load sentinel; a found result is cached, never re-probed)
    ;  canary — load-time self-check sentinel (doubles as the alias-delivery
    ; probe: this event is dispatched via SKI_PlayerLoadGameAlias, the exact event
    ; the OLD quest's instance never received on the Hadrian save; grep
    ; "[SNBaka] MCM canary reload").
    Debug.Trace("[SNBaka] MCM canary reload: OnGameReload delivered, Main=" + Main)
    If Main
        Main.Setup()
    EndIf
EndEvent

; ============================================================================
; VERSION —  CLEAN BASELINE (user ruling): this quest is a fresh
; replacement (QUST 04000D99), so the version restarts at 1. An existing save
; has no cached state for THIS quest's formID — everything OnConfigInit builds
; is fresh, so no v-bump is needed for the replacement itself. Future content
; changes to pages/options bump this number (the canonical path from here;
; the SkyUI version-field lesson documented at length in the old script's
; header applies unchanged).
; The old quest's v1..v7 lineage ( Acheron consolidation, 
; SlaveTats section,  color/release/observation) is history — see
; PROJECT_STATE /. Migration markers are NOT re-run: zero migration
; was the audit's ruling (Task 1), and old markers stay as dogfood probes.
; ============================================================================
Int Function GetVersion()
    ; : FIRST canonical bump on the  clean baseline (v1 -> v2) —
    ; the MCM restructure is user-visible (Acheron + SlaveTats promote to
    ; top-level pages), which is exactly what this machinery exists for.
    ; : SECOND canonical bump (v2 -> v3) — the Plugins page DISSOLVES:
    ; each integration becomes its own top-level page (user ruling); the
    ; SlaveTats page's set-assignment section is retitled "Auto-Apply Sets"
    ; (configuration-vs-picker clarity, -approved copy).
    ; : THIRD canonical bump (v3 -> v4) — the "GS Poses" top-level page
    ; joins (gender policy home, posing-gender.md ; page-count 10 -> 11).
    ; : FOURTH canonical bump (v4 -> v5) — the Execute-gate option
    ; (, mis-built in the DEAD v7 script) is ported into THIS live
    ; script's General page (dogfood-failure fix; wrong-script defect).
    ; : FIFTH canonical bump (v5 -> v6) — S4a severance: the MCM becomes the
    ; framework's config surface; pages go presence-gated (motherboard resolution for
    ; the 8 Baka pages, GS esp probe for GS Poses). Page STRUCTURE is now combo-
    ; dependent, so every pre-severance save crosses this bump once and rebuilds.
    ; : SIXTH canonical bump (v6 -> v7) — S4b physical re-home: the quest
    ; record moves to DeD_Framework.esp (02000800) and the script/EDID rename to
    ; DeD_MCM. No page/OID change; the bump exists for the fresh-instance canary
    ; (every existing save spins the moved quest's fresh instance and crosses it).
    ; : SEVENTH canonical bump (v7 -> v8) — the productization MCM
    ; restructure: a new first "Settings" page; the five Baka pages renamed into
    ; the "Baka - " section prefix; page-count 11 -> 12 (Main+GS combo). Page
    ; STRUCTURE changed, so every existing save crosses this bump once and
    ; rebuilds (the four-saga rule; the v2 canary lesson applies - rebuild
    ; before the canary trace).
    ; : EIGHTH canonical bump (v8 -> v9) - the Option A restructure
    ; fix: the five "Baka - " prefix pages + the Lap Sitting page fold into
    ; ONE "Baka Interactions" page hosting six in-page sections; page-count
    ; 12 -> 7 (Main+GS combo). Page STRUCTURE changed, so every existing
    ; save crosses this bump once and rebuilds (the four-saga rule; rebuild
    ; before the canary trace, the v2 lesson standing).
    ; : NINTH canonical bump (v9 -> v10) - restructure pass 3: the
    ; section NAVIGATION model is removed; the six sections STACK in the one
    ; page body under section headers. Page COUNT is unchanged (7/6), but
    ; the page BODY structure changed, so every existing save crosses this
    ; bump once and rebuilds (the four-saga rule; v2 lesson standing).
    Return 10
EndFunction

Event OnVersionUpdate(Int aVersion)
    ;  clean baseline: no migration blocks. Future bumps append their
    ; markers here (versioned SNBaka.MCMDeD.vN per the canary rule).
    ;  v2 (restructure): canary marker + the module-facing MCM marker
    ; lineage (SNBaka.ST.MCMv7 -> MCMv8, 's convention continued).
    StorageUtil.SetIntValue(Game.GetPlayer(), "SNBaka.MCMDeD.v2", 1)
    StorageUtil.SetIntValue(Game.GetPlayer(), "SNBaka.ST.MCMv8", 1)
    ;  v3 (Plugins dissolved): canary marker + MCM marker lineage
    ; continued (MCMv8 -> MCMv9). Pages rebuilt FIRST so the canary reports
    ; the NEW page count (the v2 canary traced before _BuildPages and printed
    ; the stale cached count on existing saves — flaw noted at dogfood).
    StorageUtil.SetIntValue(Game.GetPlayer(), "SNBaka.MCMDeD.v3", 1)
    StorageUtil.SetIntValue(Game.GetPlayer(), "SNBaka.ST.MCMv9", 1)
    ;  v4 (GS Poses page): canary marker — pages rebuilt FIRST so the
    ; canary reports the NEW page count (the v2 lesson, applied by convention).
    StorageUtil.SetIntValue(Game.GetPlayer(), "SNBaka.MCMDeD.v4", 1)
    ;  v5 (Execute-gate option ported from the dead v7 script into the
    ; live General page): canary marker — pages rebuilt FIRST (the v2 lesson).
    StorageUtil.SetIntValue(Game.GetPlayer(), "SNBaka.MCMDeD.v5", 1)
    ;  v6 (S4a severance): canary marker — pages rebuilt FIRST (the v2
    ; lesson; the rebuild now resolves the motherboard + probes GS so the canary
    ; reports the new combo-dependent page set).
    StorageUtil.SetIntValue(Game.GetPlayer(), "SNBaka.MCMDeD.v6", 1)
    ;  v7 (S4b physical re-home): canary marker — record now lives in
    ; DeD_Framework.esp; ModName/keys/markers unchanged (identity boundary).
    StorageUtil.SetIntValue(Game.GetPlayer(), "SNBaka.MCMDeD.v7", 1)
    ;  v8 (productization MCM restructure): canary marker — pages rebuilt
    ; FIRST so the canary reports the NEW page count (the v2 lesson, standing).
    StorageUtil.SetIntValue(Game.GetPlayer(), "SNBaka.MCMDeD.v8", 1)
    ;  v9 (Option A restructure fix): canary marker - the six Baka
    ; family pages fold into the single "Baka Interactions" section page;
    ; the Pages rebuild below reports the 7/6-page shape (v2 lesson, standing).
    StorageUtil.SetIntValue(Game.GetPlayer(), "SNBaka.MCMDeD.v9", 1)
    ;  v10 (restructure pass 3): canary marker - the navigation model
    ; is removed; the six Baka family sections stack under section headers in
    ; the one page body; the Pages rebuild below reports the unchanged
    ; 7/6-page shape (v2 lesson, standing).
    StorageUtil.SetIntValue(Game.GetPlayer(), "SNBaka.MCMDeD.v10", 1)
    _BuildPages()
    Debug.Trace("[SNBaka] MCM canary: v10 OnVersionUpdate (REV-109c restructure: Baka Interactions stacked sections, presence-gated pages: " + Pages.Length + ", Main=" + Main + ")")
EndEvent

; ============================================================================
;  MCM RESTRUCTURE (user ruling,  Task 4 item 5): each plugin
; INTEGRATION gets its own top-level page — one integration, one page. The
; two integration-scale sections left "Plugins" ("Acheron", "SlaveTats"); the
; three toggle-scale detection sections stay grouped there (Lap Sitting /
; Cum Detection / FHU Inflation — promoting each would be three near-empty
; pages; judgment call recorded in the  gate report). Every integration
; page greys out with "(mod not installed)" at PAGE level when the underlying
; mod is absent (the existing per-section presence gates, extended).
;
;  POLISH RIDER (user rulings, ): the Plugins page is DISSOLVED —
; "one integration, one page" is now total: Lap Sitting / Cum Effects /
; Fill Her Up each promote to their own top-level page (expandable later;
; the  near-empty-pages judgment is superseded by the user ruling).
; No residual Plugins page remains. Absent states stay page-level grey-outs
; "(mod not installed)". The SlaveTats page's set-assignment section is
; retitled "Auto-Apply Sets" (it configures which set fires automatically
; per event; the in-game picker always offers the full range —  copy).
; ============================================================================

Function _BuildPages()
    ; : 10 pages — the Plugins page is dissolved; every integration is
    ; a top-level left-pane page (one integration, one page, expandable later).
    ; : 11 pages — "GS Poses" joins as a top-level page (gender policy
    ; home, posing-gender.md  ruling: MCM-page home, page-count bump).
    ;  S4a: the page set is PRESENCE-GATED (the framework-MCM ruling):
    ;   - the 8 Baka module pages build ONLY when the motherboard resolves;
    ;   - GS Poses builds ONLY when the GS esp is present (Task 1.3 — the page
    ;     previously leaked: it rendered unconditionally with the GS esp absent,
    ;     a dead page writing unread keys);
    ;   - Acheron + SlaveTats are ALWAYS present (framework pages: they carry
    ;     no motherboard dependency — see the de-Mained consumer sites).
    ; Both-installed users see the IDENTICAL 11-page set as [], ORDER
    ; preserved (the Pages array is positional). Combo table recorded .
    _ResolveMain()
    If Main
        ;  (Option A): ONE "Baka Interactions" page hosts the six
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
        ; : the Settings page rides the motherboard gate in this session:
        ; every option on it is motherboard state TODAY (the honest-scope gap
        ; list is the era doc's; framework-native settings don't exist yet), so
        ; a motherboard-less combo has no real Settings content and the page
        ; does not build ( dead-page precedent).
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
    ;  S4a (count amended ): the module pages (Baka
    ; Interactions incl. Lap Sitting, Cum Effects, Fill Her Up) carry a motherboard presence rider —
    ; when the motherboard is absent they are never in Pages[] (see _BuildPages);
    ; this belt-and-suspenders guard makes the render bodies unreachable even if a
    ; stale cached Pages array ever named one (defensive only — no behavior delta
    ; in any combo reachable today; activates with the S4b quest-record move).
    If page == "Settings" && Main
        ;  MCM RESTRUCTURE (era roadmap item 7): the framework-level
        ; configurables page. Ships with WHAT EXISTS TODAY (the no-stubbing
        ; rule): master enable, the global action cooldown, the stuck-state
        ; reset, the debug log - all MOVED existing options (handler blocks
        ; unchanged; OIDs are position-free). The title header + tagline ride
        ; the FIRST page (the  rider, carried from General).
        ; GAP LIST (registered, era doc  section - polish pool, NOT
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
        AddEmptyOption()
        AddHeaderOption("Maintenance")
        ; Panic button: force-clears every hold Baka (or a stale Acheron pacify) could have left on
        ; any loaded actor -- for actors stuck non-aggressive/untargetable after something went wrong.
        ; Leaves genuinely downed/defeated actors alone (HelpUp / the get-up key is their way out).
        _panicOID = AddTextOption("EMERGENCY: reset stuck actor states", "RUN")
    ElseIf page == "Baka Interactions" && Main
        ;  (user ruling, MCM restructure pass 3, 2026-10-1X): ONE page,
        ; the six family sections STACKED in the body - NO navigation, NO state
        ; machine ('s _biSection model is REMOVED per the ruling;
        ; supersession banner at the file header). Page header = the 
        ; title + tagline rider (the Settings header pair); each section rides
        ; the  section-header pattern - spacer row + header row (the
        ; "Auto-Apply Sets" exemplar, SlaveTats page). Section bodies are the
        ; /109b bodies MOVED VERBATIM (+ de-indent only; Lap Sitting
        ; folds in per the user's list): census before == after, zero options
        ; lost, zero duplicated; handlers UNCHANGED - OIDs are position-free,
        ; so every option's load/save path is identical (1.4: layout + the
        ; fold + the version machinery ONLY; any settings semantics delta =
        ; STOP). Presence gating UNCHANGED: the page rides the motherboard
        ; gate (Pages[] build); the Lap Sitting toggle keeps its own grey-out.
        SetCursorFillMode(TOP_TO_BOTTOM)
        AddHeaderOption("Baka Interactions")
        AddTextOption("Bedroom drama for SkyrimNet", "", OPTION_FLAG_DISABLED)
        AddEmptyOption()
        ; ---- General (the former "Baka - General" body, moved verbatim) ----
        AddHeaderOption("General")
        _playerTargetOID   = AddToggleOption("Player Can Be Target",  Main.bPlayerCanBeTarget)
        _femaleOnlyOID     = AddMenuOption("Target Sex",   _targetSexName(Main.iTargetSex))
        _animatedTearsOID  = AddToggleOption("Animated Tears",        Main.bAnimatedTearsEnabled)
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
        ; : the Maintenance section (panic reset) moved to Settings
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
        _spankPlayerOID    = AddToggleOption("Player Can Be Spanked",  Main.bPlayerCanBeSpanked)
        _spankMaleOID      = AddToggleOption("Allow Male Targets",     Main.bSpankMaleTargets)
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
        _notifyOID            = AddToggleOption("Show Corner Notifications", Main.bShowNotifications)
        ; : "Enable Debug Logging" moved to the Settings page (framework-level).
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
        ; : promoted from the dissolved Plugins page (one integration,
        ; one page).  detection toggles, presence-gated as before.
        SetCursorFillMode(TOP_TO_BOTTOM)
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
    ElseIf page == "Fill Her Up" && Main
        ; : promoted from the dissolved Plugins page (one integration,
        ; one page). Presence-greyed at page level when the mod is absent.
        SetCursorFillMode(TOP_TO_BOTTOM)
        AddHeaderOption("FHU Inflation Awareness")
        If Main._FHUInstalled()
            _fhuAwareOID = AddToggleOption("Inflation Level Cues (Fill Her Up)", Main.bFHUInflationEnabled)
        Else
            _fhuAwareOID = AddToggleOption("Inflation Level Cues (not installed)", False, OPTION_FLAG_DISABLED)
        EndIf
    ElseIf page == "Acheron"
        ;  restructure: the Downed State bridge promoted from a Plugins section to
        ; its own page (one integration, one page). Absent state is page-level: every
        ; option greyed + the header names the missing mod (per-section gate, extended).
        SetCursorFillMode(TOP_TO_BOTTOM)
        AddHeaderOption("Downed State (Acheron Bridge)")
        Actor _achP = Game.GetPlayer()
        If !_achP
            _achP = Game.GetPlayer()
        EndIf
        If Game.GetFormFromFile(0x800, "SkyrimNet_AcheronIntegration.esp") != None   ;  S4a: de-Mained — same probe the motherboard module-arm uses (SkyrimNet_BakaIntegration L586); the Acheron page no longer consults the motherboard
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
        ;  restructure: the SlaveTats degradation-set section promoted from the
        ; Plugins page to its own page (one integration, one page — the page the picker
        ; walkthrough is re-baselined against). Absent state page-level like Acheron's.
        ;   copy fix: the set-assignment block is titled WHAT IT IS — "Auto-Apply
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
            ;  Task 4: module-wide default color (picker per-set colors override),
            ; removal-on-release, and the ambient observation pass toggle.
            _stDefaultColorOID   = AddTextOption("Default Mark Color",     _ST_ColorLabel(StorageUtil.GetIntValue(_stP, "SNBaka.ST.DefaultColor", 0)))
            _stRemoveOnReleaseOID = AddToggleOption("Remove Marks On Release", StorageUtil.GetIntValue(_stP, "SNBaka.ST.RemoveOnRelease", 1) == 1)
            _stObserveOID         = AddToggleOption("Ambient Observation Cues", StorageUtil.GetIntValue(_stP, "SNBaka.ST.Observe", 1) == 1)
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
        EndIf
    ElseIf page == "GS Poses"
        ;  Phase B: the gender policy home (posing-gender.md ). One menu
        ; option, three modes; the GS script reads the key on every gate (no nudge
        ; needed — every check is a fresh StorageUtil read). Mode names mirror the
        ; policy vocabulary of record.
        SetCursorFillMode(TOP_TO_BOTTOM)
        AddHeaderOption("GSPoses - Pose Gender Policy")
        _gsIntroOID = AddTextOption("Who may be posed, by body:", "", OPTION_FLAG_DISABLED)
        _gsGenderPolicyOID = AddMenuOption("Pose Gender Policy", _gsGenderPolicyName(StorageUtil.GetIntValue(None, "GSAnim.GenderPolicy", 0)))
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
        Actor achP1 = Game.GetPlayer()
        If !achP1
            achP1 = Game.GetPlayer()
        EndIf
        Int vAch = 1 - StorageUtil.GetIntValue(achP1, "SNAcheron.Enabled", 1)
        StorageUtil.SetIntValue(achP1, "SNAcheron.Enabled", vAch)
        SetToggleOptionValue(_achEnabledOID, vAch == 1)
        ;  S4a: the lifecycle nudge is motherboard-dependent — guard it so
        ; this Acheron-page toggle works with the motherboard absent too (the bridge
        ; re-reads the key on its own self-heal cadence either way, per ).
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
        ;  dogfood fix: the set picker had no in-game entry point (OpenSetMenu was
        ; dead code). Close the MCM first — PrismaUI modal needs the game input focus.
        SNBaka_SlaveTatsModule.OpenSetMenu()
    ElseIf option == _stDefaultColorOID
        ; : cycle Default -> Black -> Red -> Crimson -> Dark Red -> Blue -> Green
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
    ; : the  section-navigation handler chain is REMOVED with
    ; the navigation model (supersession banner at the file header). The
    ; stacked body has no nav OIDs; the handlers above are the full set.
EndEvent

;  — get-up key rebinding for the consolidated bridge section. Writes the same
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
    ElseIf option == _gsGenderPolicyOID
        SetMenuDialogOptions(_gsGenderPolicyNames())
        SetMenuDialogStartIndex(StorageUtil.GetIntValue(None, "GSAnim.GenderPolicy", 0))
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
    ElseIf option == _gsGenderPolicyOID
        ;  Phase B: write GSAnim.GenderPolicy (StorageUtil int on None, the
        ; GS script's own key style; save-persisted, no migration — 0 is shipped
        ; default). The GS gates read it fresh on every check, so this is live.
        If index < 0 || index > 2
            index = 0
        EndIf
        StorageUtil.SetIntValue(None, "GSAnim.GenderPolicy", index)
        SetMenuOptionValue(_gsGenderPolicyOID, _gsGenderPolicyName(index))
        Debug.Notification("GS Poses: pose gender policy set - " + _gsGenderPolicyName(index))
    ElseIf option == _execGateOID
        ;  Task 1 (port): player-keyed StorageUtil write (same pattern as the
        ; SNAcheron.* options; no CK property link). Execute_Execute re-reads it on
        ; every fire.
        _SetExecGateLevel(index)
        SetMenuOptionValue(_execGateOID, _execGateName(index))
    EndIf
EndEvent

;  Task 1 (port of the  block) - Execute-gate level names (user-ruled
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

;  Phase B — GS Poses page: gender policy mode names (GSAnim.GenderPolicy).
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
        SetSliderDialogStartValue(StorageUtil.GetFloatValue(Game.GetPlayer(), "SNAcheron.CueInterval", 30.0))
        SetSliderDialogDefaultValue(30.0)
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
    ElseIf option == _qteKeysOID
        ;  length audit (class (b) split): the WASD / d-pad detail moved
        ; here from the (over-length) value string.
        SetInfoText("Struggle QTE keys: WASD / d-pad. Not configured here - set them in the 'Flash Games' mod's Struggling QTE section.")
    ElseIf option == _stIntroOID
        ;  length audit (class (b) split): the full sentence moved here
        ; from the (over-length) label.
        SetInfoText("Sets are chosen in the in-game Tattoo Menu; this section only decides WHICH events fire them automatically.")
    ElseIf option == _gsIntroOID
        ;  length audit (class (b) split): the full explanation moved
        ; here from the (over-length) label.
        SetInfoText("Who may be posed, by body: female-only keeps the shipped behavior; curated admits men to the neutral set; all-poses opens the whole library.")
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
    Actor p = Game.GetPlayer()
    If !p
        p = Game.GetPlayer()
    EndIf
    Int v = 1 - StorageUtil.GetIntValue(p, asKey, aiDefault)
    StorageUtil.SetIntValue(p, asKey, v)
    SetToggleOptionValue(aiOID, v == 1)
EndFunction
