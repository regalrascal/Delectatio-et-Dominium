; SkyrimNet Animations — GS Poser : main controller (attach to the SkyrimNet_AnimationsGS quest).
; Animations are by Gunslicer (GSPoses) — https://www.patreon.com/Gunslicer — and are NOT bundled.
Scriptname SkyrimNet_AnimationsGS extends Quest

; Fill in CK: the lesser power that opens the selector (auto-granted to the player on init).
Spell Property OpenSelectorSpell Auto

Actor  PlayerRef
String _sCurrentPose     = ""
String _sCurrentPoseDesc = ""

; ── Phase 2: crosshair-directed NPC posing ──────────────────────────────────
; The actor under the crosshair when the selector power is CAST (None = the grid pick
; poses the player, exactly as before). Captured at cast time because the cursor is
; free while the PrismaUI grid is open, so the crosshair can't be read at pick time.
; Cleared on every exit path of OnPoseSelected (pick, refusal, cancel).
Actor _PendingNpcTarget

; ── Phase 6a: leveled-safe sex lookup ────────────────────────────────────────
; Ported from the Baka "leveledsexfix" community variant (credited there — see the Baka repo's
; Phase 6a port commit): Actor.GetActorBase() returns the EDITOR base, which for generic leveled
; NPCs (bandits, forsworn, vampires, most guards) is a template shell whose sex field is an
; unused placeholder reading MALE — a visibly female bandit reads as male and every female-
; gated path silently refuses her. All three GS gates (crosshair validation, _PoseVibe exec,
; T3 eligibility scan) route through this now. GetLeveledActorBase() (SKSE) returns the game-
; generated base the leveled list resolved to; uniques and the player fall back to the editor
; base (for them it IS the real record). Returns 0 male, 1 female, -1 unknown/none.
Int Function _SexOf(Actor akActor) Global
    If !akActor
        Return -1
    EndIf
    ActorBase bse = akActor.GetLeveledActorBase()
    If !bse
        bse = akActor.GetActorBase()
    EndIf
    If !bse
        Return -1
    EndIf
    Return bse.GetSex()
EndFunction

; ──  Phase B: gender policy (posing-gender.md /, rulings A/B) ───
; One StorageUtil int on None, the proven GSAnim.Muse/Overdrive pattern:
;   GSAnim.GenderPolicy  0 = female-only (shipped default, no behavior change)
;                         1 = curated    (the _VibeMaleOK 11-vibe male-safe set)
;                         2 = all-poses  (no gender gate anywhere)
; Save-persisted, MCM-owned (SNBaka_MCM "GS Poses" page). Every gender gate in
; this script routes through _GenderPolicy() — the 7-site rewire (crosshair
; validation, _PoseVibe, _DaemonScan, muse fire veto, muse context sex field).
; Unknown/clamped values read as 0: never a silent behavior change on an
; unread value (the 6a discipline).
Int Function _GenderPolicy()
    Int iMode = StorageUtil.GetIntValue(None, "GSAnim.GenderPolicy", 0)
    If iMode < 0 || iMode > 2
        Return 0
    EndIf
    Return iMode
EndFunction

;  Phase B: the central admission question — "may THIS actor pose on a
; vibe from the library at all, gender-wise?" Mode 0: females only (shipped
; behavior; males refused, unknown-sex stays blocked — the 6a leveled edge).
; Mode 1: males admitted only for curated (_VibeMaleOK) vibes. Mode 2: no
; gender gate (sex is never a refusal reason). Replaces the per-site female
; tests; the sole authority for every site so the modes can never disagree.
Bool Function _GenderAdmits(Actor ak, String vibe)
    Int iMode = _GenderPolicy()
    If iMode == 2
        Return True
    EndIf
    Int iSex = _SexOf(ak)
    If iSex == 1
        Return True
    EndIf
    If iMode == 1 && iSex == 0 && _VibeMaleOK(vibe)
        Return True
    EndIf
    Return False
EndFunction

;  Phase B: per-mode refusal strings ( ruling B). Mode 0 keeps the
; shipped string verbatim; mode 1 carries the approved curated line; mode 2
; has no gender refusal by construction (callers skip the leg entirely).
String Function _GenderRefusal(Actor ak, Int iMode)
    If iMode == 1
        Return ak.GetDisplayName() + " isn't the type for that pose."
    EndIf
    Return ak.GetDisplayName() + " can't pose: female poses only."
EndFunction

; ── Phase 4: muse daemon + performance mode (overdrive) state ──────────────
; Flags are StorageUtil ints on None (this mod's existing key style). BOTH are flipped by
; grid footer buttons (OVERDRIVE_TOGGLE / MUSE_TOGGLE sentinels). The Muse button was the
; Phase 4b rider, pulled forward into Phase 4 after the "console flip" plan failed
; verification: no vanilla or console-mod command can reach a StorageUtil key, and MCP's
; execute_quest_function would need a public setter this script never had. Muse still
; DEFAULTS OFF: deliberate, for attribution isolation between the description channel
; (the dashboard trigger YAML) and the seeder (this script) during live-fire sessions —
; flip it only when the seeder half belongs in the test.
;   GSAnim.Overdrive          1 = performance mode running (T1 cues, T2 floored cooldowns,
;                             T3 silence-floor auto-pose; expires ~5 min; 2nd press = OFF)
;   GSAnim.Muse               1 = ambient thought-seeder running (throttled GenerateNPCThought)
;   GSAnim.LastPoseFire       global timestamp of the last pose fire — observability only
;                           since  3.3 (the T3 silence-floor reader is retired)
;   GSAnim.LastT3Fire         3.3: T3 multi-poser fire clock — a NEW candidate every
;                           fOdT3IntervalSec; fresh key (absent from old saves, no residue)
;   GSAnim.T3Mark             3.1: per-actor timestamp of the latest T3 dispatch;
;                           consumed by _PoseVibe's success leg within 30s for the user-ruled
;                           on-screen Sheogorath receipt (replaces the _bT3InFlight window)
;   GSAnim.NudgeInterval      3.2: Sanguine nudge interval of record (StorageUtil;
;                           defaults to the fMuseNudgeIntervalSec compile-time value — a KEY,
;                           because the save-resident member value 100.0 was shadowing the
;                           compiled 30.0 on long-lived saves, the diagnosed ~100s gap source)
;   GSAnim.T3Interval         5.2: Sheogorath T3 cadence (StorageUtil, default = the
;                           fOdT3IntervalSec compiled member 15.0; the GS Poses MCM slider
;                           writes it live, 15s-240s)
;   GSAnim.SanguineModeNarr / GSAnim.SheogorathModeNarr
;                            5.1: the per-mode direct-narration toggles (DEFAULT 0 =
;                           OFF; the gated second surface for mode-action executions, 134f
;                           pattern; yamls gsanim_sanguine_mode_narr/gsanim_sheogorath_mode_narr)
;   GSAnim.PoseNarrSanguine / GSAnim.PoseNarrEmergent / GSAnim.PoseNarrPlayer
;                            5.3: the three per-route pose-cue narration toggles
;                           (DEFAULT 1 = ON, current behavior preserved; the GS Poses page
;                           owns them, user-authored titles)
;   GSAnim.LastOdCue          global timestamp of the last T1 ambience cue
;   GSAnim.OverdriveExpire    absolute real-time timestamp when performance mode auto-OFFs
;   GSAnim.CombatSuspendStart when the current player-combat suspend began (0 = not suspended;
;                             the expiry clock is extended by exactly the combat span on resume)
;   GSAnim.MuseGlobal        boot-relative timestamp (Utility.GetCurrentRealTime()) of the
;                           last muse nudge CALL (v1.2: stamped at call time, gates the
;                           ~100s interval — fMuseNudgeIntervalSec).  cross-session
;                           clamp: the stamp persists in saves but the clock is BOOT-
;                           relative, so a stamp from a longer prior session reads as
;                           "just asked" and gates every tick of a shorter next boot —
;                           _MuseTick clamps any stamp > fNow to 0 on read (the 09-15
;                           evening session's total muse silence was exactly this).
;   GSAnim.LastMuse  (actor) per-NPC timestamp of the last LANDED seed. : READ by the
;                           per-NPC floor (fMusePerNpcSec, 120s) in the _MuseTick candidate walk —
;                           a floored candidate is skipped and the walk continues; all-floored is
;                           the "nobody eligible" lap exit, no call spent. Stale-stamp clamp at
;                           read (stamp > fNow -> 0, persisted) per the  MuseGlobal pattern
;                           (boot-relative clock, save-persisted stamp). The seed-time write of
;                           fNow stays as-is.
;   GSAnim.MuseDebugEnd     boot-relative absolute timestamp the muse debug window closes
;                           ( 1c: the window now re-arms per BOOT, not once per
;                           playthrough — first MUSE_TOGGLE ON of each game start; a
;                           stale cross-boot end-stamp is clamped closed on read by
;                           _MuseDebugWindowOpen)
;   GSAnim.MuseDebugDone    1 = a muse debug window is/has been armed (informational; the
;                            per-boot arming is driven by an in-memory member flag,
;                           _bMuseDebugArmedThisBoot, which resets at every game start —
;                           the Phase 4d public ReArmMuseDebug() and the Phase 4e one-shot
;                           migration remain as harmless legacy no-ops on top)
;   GSAnim.ReArm4e         1 = the one-shot Phase 4e debug-window re-arm migration has run
;                           (owned key; keyed independently of the 4d heal branch so its
;                           timing is independent of whether the heal already fired)
;   GSAnim.Vibe      (actor)  vivid label of the pose an actor holds — stored at pose time so
;                             the stop paths can name WHAT ended (Phase 4 event-desc rider)

; ── Cross-mod "don't pose this actor right now" guard ────────────────────────
; The is_busy YAML eligibility gate (see pose_*.yaml) is a snapshot at the moment the LLM decides —
; it can't see an actor that becomes busy between that decision and this exec actually running (a
; struggle starting, a defeat landing, a scene beginning). This is the exec-side backstop, checked
; right before any Debug.SendAnimationEvent, so a pose genuinely never fires mid-scene regardless of
; timing. All soft/optional: every check is either a plain StorageUtil key (0 if the other mod isn't
; installed) or a Faction resolved by FormID (None if that mod isn't installed), so this mod keeps
; working standalone with nothing installed.
Faction _sexLabAnimFac
Faction _ostimSceneFac

Bool Function _IsInSexScene(Actor ak)
    If !_sexLabAnimFac
        _sexLabAnimFac = Game.GetFormFromFile(0x00E50F, "SexLab.esm") as Faction
    EndIf
    If _sexLabAnimFac && ak.GetFactionRank(_sexLabAnimFac) >= 0
        Return True
    EndIf
    If !_ostimSceneFac
        _ostimSceneFac = Game.GetFormFromFile(0x000ECA, "OStim.esp") as Faction
    EndIf
    If _ostimSceneFac && ak.GetFactionRank(_ostimSceneFac) >= 0
        Return True
    EndIf
    Return False
EndFunction

; Covers: a Baka paired animation/struggle (SNBaka.Locked -- also stays 1 through Baka's own
; escalation-to-sex-scene, so that case is covered here too), Baka's own downed/ground-window state
; (SNBaka.OnGround), an Acheron-only hold with no Baka involved (SNAcheron.Held), ANY vanilla
; bleedout regardless of who caused it -- SeverActions, vanilla combat, Acheron, Baka -- (IsBleedingOut,
; the same actor-state check that fixed the downed-follower interact bug in Baka's own DLL), a sex
; scene that didn't go through Baka at all (_IsInSexScene), active combat (the is_in_combat YAML gate
; is the SAME snapshot-at-decision-time problem is_busy already needed a backstop for -- confirmed
; live report: poses should never fire mid-fight, and the eligibility check alone can't see a fight
; that started in the gap between the LLM's decision and this actually running), and already sitting
; on ANYTHING (a real chair, work furniture, or Baka's Lap Sitting integration -- lap-sitting is just
; a vanilla furniture sit under the hood, so this one check catches both for free with no dependency
; on Baka's own state at all).
Bool Function _IsBusyElsewhere(Actor ak)
    ;  S2: the two SNBaka.* busy reads are now gated on the busy-state
    ; service (the Baka motherboard advertises "busy.baka-half"; era doc 5.2 S2:
    ; key names stay the wire format — zero save migration; a contract over the
    ; existing soft reads, not a new interface). Behavior-identical by construction:
    ; Baka present -> the keys are read verbatim as before; Baka absent -> the probe
    ; reads 0 and these reads are skipped, which is exactly the soft-default-0 result
    ; they returned in that same state (the keys' default path is preserved exactly;
    ; the one divergence — stale nonzero keys on a pre-uninstall save no longer read
    ; as busy — is the soft default being made explicit, flagged in PROJECT_STATE 111).
    Bool bBakaBusySvc = _BakaBusyServicePresent()
    If !_bBusySvcProbeSentinel
        _bBusySvcProbeSentinel = True
        Debug.Trace("[SNAnimGS] busy-service probe (REV-105 S2 sentinel): present=" + bBakaBusySvc)
    EndIf
    If bBakaBusySvc
        If StorageUtil.GetIntValue(ak, "SNBaka.Locked",   0) == 1
            If !_bBusySvcBlockSentinel
                _bBusySvcBlockSentinel = True
                Debug.Trace("[SNAnimGS] busy-service result (REV-105 S2 sentinel): actor blocked by SNBaka.Locked")
            EndIf
            Return True
        EndIf
        If StorageUtil.GetIntValue(ak, "SNBaka.OnGround", 0) == 1
            If !_bBusySvcBlockSentinel
                _bBusySvcBlockSentinel = True
                Debug.Trace("[SNAnimGS] busy-service result (REV-105 S2 sentinel): actor blocked by SNBaka.OnGround")
            EndIf
            Return True
        EndIf
    EndIf
    If StorageUtil.GetIntValue(ak, "SNAcheron.Held",  0) == 1
        Return True
    EndIf
    If ak.IsBleedingOut()
        Return True
    EndIf
    If _IsInSexScene(ak)
        Return True
    EndIf
    If ak.IsInCombat()
        Return True
    EndIf
    ;  (idle-interrupt service, spec gs-poses.md  1.4.3): the
    ; GetSitState leg is now CLASS-AWARE — interruptible idle classes (furniture
    ; sits + IdleMarker holds) no longer hard-exclude here; callers route those
    ; actors through _IdleFirePath (detect -> exit -> fire-time recheck -> fire)
    ; instead of silently dropping them. This is the  seated-exclusion
    ; strangling fix: the seated tavern population is REACHABLE now. Essential
    ; idle classes (sleep/downed/mounted/swimming/sneaking) stay
    ; hard-excluded via the callers' own state guards + _IdleClass in the service
    ; (: dialogue dropped from this list — no longer an ESSENTIAL class).
    If _IdleClass(ak) > 0
        Return False
    EndIf
    Return False
EndFunction

; ===================== : THE IDLE-INTERRUPT SERVICE =====================
; Spec of record: gs-poses.md  1.4.1-1.4.3. Pure Papyrus, no DLL, no
; esp; no LLM strings anywhere in the service. The Baka motherboard inherits
; this at the daemon build by calling the two GLOBAL functions cross-script:
;   SkyrimNet_AnimationsGS._IdleClass(ak)
;   SkyrimNet_AnimationsGS._ExitIdle(ak, iClass)
; Idle classes (the taxonomy, 1.4.1):
;    0 = not idle-anchored;  1 = furniture sit (INTERRUPTIBLE);  2 = IdleMarker
;    hold (INTERRUPTIBLE);  -1 sleep, -2 bleedout/downed, -3 mounted, -4
;    swimming, -5 sneaking (all ESSENTIAL, never interrupted). : the
;    -6 mid-dialogue class is RETIRED (user ruling — dialogue guards removed).
; Carried rulings  (2026-10-22): sneaking ESSENTIAL (edge ruled);
;     (2026-10-22) SUPERSEDES the  mid-dialogue narrowing —
;    dialogue is NO LONGER an ESSENTIAL class (guards removed; the
;    vanilla-Dialogue-Menu discriminator UI.IsMenuOpen is gone with it); the
;     PathToReference stand shape RETIRED — stand-in-place
;    only (no pathing, no translation toward ANY reference, no teleports); AI
;    re-grab PREVENTED (hold at exit-issue, supersedes tolerate-and-skip).
; Scripted/quest idles have NO direct Papyrus native — covered ONLY by the
;    fire-time scene/combat guard in _IdleFirePath (surfaced in the 
;    gate report); the  mid-dialogue approximation is retired with the
;    class ( user ruling — unguarded testing).
; Natives verified against installed source ( 3b discipline):
; GetSleepState/GetSitState/IsBleedingOut/IsOnMount/IsSneaking (vanilla
; Actor.psc, Data\Source\Scripts), IsSwimming/GetFurnitureReference (SKSE64
; Actor.psc, installed mods tree), Debug.SendAnimationEvent (vanilla Debug.psc).
; (: UI.IsMenuOpen dropped from this list — no longer called.)

Int Function _IdleClass(Actor ak) Global
    If !ak
        Return 0
    EndIf
    If ak.GetSleepState() != 0
        Return -1
    EndIf
    If ak.IsBleedingOut()
        Return -2
    EndIf
    If StorageUtil.GetIntValue(ak, "SNBaka.OnGround", 0) == 1
        Return -2
    EndIf
    If StorageUtil.GetIntValue(ak, "SNAcheron.Held", 0) == 1
        Return -2
    EndIf
    If ak.IsOnMount()
        Return -3
    EndIf
    If ak.IsSwimming()
        Return -4
    EndIf
    If ak.IsSneaking()
        Return -5
    EndIf
    ;  (user ruling, 2026-10-22 session): the dialogue guard is REMOVED
    ; — no dialogue class in the taxonomy at all. HONEST LIMIT, updated to
    ; record the ruling: the  vanilla-Dialogue-Menu discriminator
    ; (UI.IsMenuOpen) was ruled out by the user — poses are to be tested
    ; UNGUARDED against dialogue; guards removed pending live testing. The
    ; old -6 mid-dialogue class is retired; scripted/quest idles have no
    ; direct Papyrus native and are covered only by the fire-time
    ; scene/combat guard in _IdleFirePath (surfaced in the  gate
    ; report; unchanged by this removal).
    If ak.GetSitState() != 0
        Return 1
    EndIf
    If ak.GetFurnitureReference()
        Return 2
    EndIf
    Return 0
EndFunction

; The exit primitive (1.4.2,  2.1 ruling: STAND-IN-PLACE — no pathing,
; no translation toward ANY reference, no teleports; the 
; PathToReference(player) shape is RETIRED as ruled wrong). ONE technique
; for BOTH interruptible classes: the proven Acheron-pair event
; IdleForceDefaultState (AcheronIntegration L211/L486/L529-531 precedent)
; breaks the furniture sit AND the marker hold; the actor stands where they
; are (pop-stand MVP — smooth-stand polish is OUT OF SCOPE this rev).
; Returns True ONLY when CONFIRMED: the actor is UP (SitState 0) within the
; 4.0s REAL-clock poll window ( 2.1: was 2.0s; the L6998 real-clock
; lesson — never count naive ticks under VM load). PASS signal = SitState 0
; alone; the furniture/marker reference is demoted to the NAMED DISCRIMINATOR
; in the pass/fail sentinels, so a residual failure self-diagnoses from the
; next log. Hold timing: SetDontMove during the confirm window (blocks
; package walk-away mid-stand without fighting the stand anim); on confirm
; the caller swaps to the standard re-grab hold (SetRestrained,
; GSAnim.IdleHold) through the pose; on fail _ReleaseIdleHold releases BOTH
; cleanly (never strand).
Bool Function _ExitIdle(Actor ak, Int iClass) Global
    If !ak || (iClass != 1 && iClass != 2)
        Return False
    EndIf
    ak.SetDontMove(True)   ; : stand-window hold -- blocks walk-away, not the stand
    ; : the DontMove span WIDENED -- held through CONFIRM and the fire handoff
    ; (the [] dogfood evidence: 8/8 BACKSTOP re-anchors were class 2 -- the
    ; sandbox package walked freshly-standed actors to a nearby idle marker inside
    ; the confirm->recheck->fire window the moment DontMove cleared; sub-poll re-sits
    ; produced the exit-FAILED refusals). Released ONLY by the no-fire legs
    ; (_ReleaseIdleHold) and the pose-end machinery (_StopActorPose clears both
    ; restraints) -- a fired pose never strands the hold.
    Debug.SendAnimationEvent(ak, "IdleForceDefaultState")
    Float fStart = Utility.GetCurrentRealTime()
    While (Utility.GetCurrentRealTime() - fStart) < 4.0
        If ak.GetSitState() == 0
            ; : NO SetDontMove(False) here -- the hold persists through fire
            If ak.GetFurnitureReference()
                Debug.Trace("[SNAnimGS] idle-svc exit confirmed: SitState clear, furniture-ref PERSISTED (named discriminator): " + ak.GetDisplayName() + " class=" + iClass)
            Else
                Debug.Trace("[SNAnimGS] idle-svc exit confirmed: both anchors clear: " + ak.GetDisplayName() + " class=" + iClass)
            EndIf
            Debug.Trace("[SNAnimGS] idle-svc exit confirmed: hold spans through fire handoff (REV-137b): " + ak.GetDisplayName() + " class=" + iClass)
            Return True
        EndIf
        Utility.Wait(0.1)   ; : 0.25 -> 0.1 poll (sub-0.25s stand/resit races defeated the [] poll)
    EndWhile
    ; FAIL at 4.0s -- NAME the persisted anchor (the  hypothesis-pair discriminator)
    String sWhich = "sitstate"
    If ak.GetSitState() == 0
        sWhich = "furniture-ref (sitstate clear)"
    ElseIf ak.GetFurnitureReference()
        sWhich = "sitstate AND furniture-ref"
    EndIf
    ak.SetDontMove(False)
    Debug.Trace("[SNAnimGS] idle-svc exit FAILED after 4.0s: " + ak.GetDisplayName() + " class=" + iClass + " -- persisted: " + sWhich)
    Return False
EndFunction

; The fire-time pipeline (1.4.3,  2.2): class detect -> AI HOLD ->
; exit -> RECHECK -> caller fires. The RECHECK is the  revalidation
; precedent, as-built at the Execute kill-time recheck (motherboard
; L7467-7500): re-essential states, RE-ANCHOR (backstop ONLY while the AI
; hold is held — see 2.2 note), candidate validity (gender-policy admit
; live, no scene/combat/pose-active).  sentinels on EVERY leg, unconditional,
; ASCII. Returns True = safe to fire NOW. Member function (reaches member
; guards _IsInSexScene/_GenderAdmits/_GenderPolicy); the GLOBAL primitive pair
; above is the module-neutral cross-script surface the Baka motherboard
; inherits.
Bool Function _IdleFirePath(Actor ak, String sCat)
    Int iClass = _IdleClass(ak)
    Debug.Trace("[SNAnimGS] idle-svc class detect: " + ak.GetDisplayName() + " class=" + iClass)
    If iClass < 0
        Debug.Trace("[SNAnimGS] idle-svc refuse: essential idle class " + iClass + " (" + ak.GetDisplayName() + ") -- never interruptible, skip")
        Return False
    EndIf
    If iClass == 0
        ;  2.2 (finding 2.1, the wander-while-posing defect): the
        ; class-0 leg acquires the re-grab hold AT FIRE — moving/standing
        ; actors were previously NEVER held (early return, no restrain), so
        ; their packages walked them through the pose. Released by the
        ; existing pose-end machinery (_StopActorPose clears IdleHold and
        ; both restraints — belt-and-suspenders) and by the flag-guarded
        ; _ReleaseIdleHold calls on _PoseVibe's refusal legs; the fire paths
        ; re-restrain anyway (_PoseVibe/_PoseDirect), so the swap is a no-op.
        ak.SetRestrained(True)
        StorageUtil.SetIntValue(ak, "GSAnim.IdleHold", 1)
        Debug.Trace("[SNAnimGS] idle-svc AI hold acquired at fire (class 0): " + ak.GetDisplayName())
        _PkgHoldActorAI(ak, True)   ;  3.1: in-flight pathing stop -- DontMove does not stop a travel procedure
        Return True
    EndIf
    ;  2.2 (user ruling, SUPERSEDES tolerate-and-skip): the AI hold is
    ; acquired at EXIT-ISSUE, BEFORE the stand break — the _PoseVibe/
    ; _PoseDirect SetRestrained pattern the codebase already uses — so the
    ; actor's AI package cannot re-grab mid-stand. The hold PERSISTS through
    ; the pose (every fire path re-restrains; every pose-end exit releases
    ; via _StopActorPose, so the actor returns to their package naturally
    ; afterward), which also covers the user-observed NPCs-wandering-mid-pose
    ; defect. Every refusal past this point releases via _ReleaseIdleHold
    ; (no release path strands the hold); on PASS the hold hands off to the
    ; pose machinery and the IdleHold flag clears.
    ak.SetRestrained(True)
    StorageUtil.SetIntValue(ak, "GSAnim.IdleHold", 1)
    Debug.Trace("[SNAnimGS] idle-svc AI hold acquired at exit-issue: " + ak.GetDisplayName() + " class=" + iClass)
    ;  3.1: engage the DoNothing override BEFORE the stand event --
    ; the [] dogfood sitState-persistence refusals (Kleppr/Cosnach)
    ; were the sandbox package re-sitting the freshly-standed actor inside
    ; the confirm poll; with the package pinned, SitState clears clean and
    ; the fire path proceeds. DontMove alone provably did not stop it.
    _PkgHoldActorAI(ak, True)
    Debug.Trace("[SNAnimGS] idle-svc exit issued (stand-in-place): " + ak.GetDisplayName() + " class=" + iClass)
    If !_ExitIdle(ak, iClass)
        _ReleaseIdleHold(ak)
        Debug.Trace("[SNAnimGS] idle-svc exit FAILED: " + ak.GetDisplayName() + " class=" + iClass + " -- skip with reason (idle state did not clear)")
        Return False
    EndIf
    Debug.Trace("[SNAnimGS] idle-svc exit confirmed (stand-in-place): " + ak.GetDisplayName() + " class=" + iClass)
    Int iRe = _IdleClass(ak)
    If iRe < 0
        _ReleaseIdleHold(ak)
        Debug.Trace("[SNAnimGS] idle-svc recheck FAIL: essential state entered after exit (class " + iRe + ", " + ak.GetDisplayName() + ") -- skip")
        Return False
    EndIf
    If iRe > 0
        ;  2.2: UNREACHABLE BACKSTOP ONLY — the AI hold is held from
        ; exit-issue through recheck, so a package re-anchor cannot happen;
        ; the  one-re-exit-then-skip path stays per ruling as the
        ; last-resort sentinel, never the primary path.
        Debug.Trace("[SNAnimGS] idle-svc recheck BACKSTOP: re-anchored despite AI hold (class " + iRe + ", " + ak.GetDisplayName() + ") -- re-exit")
        If !_ExitIdle(ak, iRe)
            _ReleaseIdleHold(ak)
            Debug.Trace("[SNAnimGS] idle-svc recheck FAIL: backstop re-exit did not clear (" + ak.GetDisplayName() + ") -- skip")
            Return False
        EndIf
    EndIf
    If ak.IsInCombat()
        _ReleaseIdleHold(ak)
        Debug.Trace("[SNAnimGS] idle-svc recheck FAIL: combat at fire time (" + ak.GetDisplayName() + ") -- skip")
        Return False
    EndIf
    If _IsInSexScene(ak)
        _ReleaseIdleHold(ak)
        Debug.Trace("[SNAnimGS] idle-svc recheck FAIL: sex scene at fire time (" + ak.GetDisplayName() + ") -- skip")
        Return False
    EndIf
    If ak.IsBleedingOut()
        _ReleaseIdleHold(ak)
        Debug.Trace("[SNAnimGS] idle-svc recheck FAIL: bleedout at fire time (" + ak.GetDisplayName() + ") -- skip")
        Return False
    EndIf
    If StorageUtil.GetStringValue(ak, "GSAnim.Pose", "") != ""
        _ReleaseIdleHold(ak)
        Debug.Trace("[SNAnimGS] idle-svc recheck FAIL: pose already active (" + ak.GetDisplayName() + ") -- skip")
        Return False
    EndIf
    If !_GenderAdmits(ak, sCat)
        _ReleaseIdleHold(ak)
        Debug.Trace("[SNAnimGS] idle-svc recheck FAIL: gender policy veto (cat '" + sCat + "', mode " + _GenderPolicy() + ", " + ak.GetDisplayName() + ") -- skip")
        Return False
    EndIf
    Debug.Trace("[SNAnimGS] idle-svc recheck PASS: safe to fire (" + ak.GetDisplayName() + ", cat '" + sCat + "') -- hold hands off to pose machinery")
    StorageUtil.SetIntValue(ak, "GSAnim.IdleHold", 0)
    Return True
EndFunction

;  3.1 (verdict 2.1c): the Baka-grade package hold. The []
; dogfood proved SetDontMove does NOT stop in-flight package pathing (5
; recheck BACKSTOPs + class-0 glides with the hold live throughout), and
; the in-repo proven comparison (BakaIntegration _HoldActorAI L1775-1799
; + its shipped comment: "SetRestrained/SetDontMove stop walking but NOT
; package re-evaluation") holds: the ONE missing primitive is the
; condition-free DoNothing package override at priority 100 + EvaluatePackage.
; Ported WITHOUT a hard script dependency (the era doctrine: no hard
; Baka dep): the Baka esp's own DoNothing package (PACK local 0xD6A
; (0x04000D6A), SkyrimNet_BakaIntegration.esp; : the 
; literal 0x1E6 was a header misparse - the PACK record's DATA-SIZE
; field read as formID; corrected per the -R rider hex receipt) is soft-read via GetFormFromFile, gated
; on the existing busy.baka-half service probe ( S2 class -- absent
; Baka = present behavior, DontMove/Sandbox hold only, miss sentinel once
; per load). Engaged with the AI hold at fire (class 0) and BEFORE the
; stand (class 1/2 exit-issue -- so the package cannot re-sit mid-stand:
; the [] sitState-persistence refusals class); released at every
; _ReleaseIdleHold no-fire leg, _StopActorPose (pose end), and the
; _PoseVibe empty-pool belt-and-suspenders leg (the flag guards against
; double-add; RemovePackageOverride is safe/idempotent).
Function _PkgHoldActorAI(Actor ak, Bool bHold)
    If !ak
        Return
    EndIf
    Package pkgDoNothing = None
    If _BakaBusyServicePresent()
        pkgDoNothing = Game.GetFormFromFile(0xD6A, "SkyrimNet_BakaIntegration.esp") as Package
    EndIf
    If bHold
        If !pkgDoNothing
            ; : the UNAVAILABLE sentinel is SPLIT into two
            ; independently-latched miss classes (once per load each) -
            ; probe-miss (Baka module absent) vs form-miss (half present,
            ; package form unresolved). The class must never be ambiguous
            ; again (records-hygiene guard for the 137c misparse class).
            Bool bHalfAbsent = !_BakaBusyServicePresent()
            String sMissKey = "GSAnim.PkgFormMiss"
            String sMissMsg = "idle-svc package hold FORM-MISS (Baka half present but DoNothing package unresolved -- check the formID literal) -- DontMove/Sandbox hold only (REV-137e)"
            If bHalfAbsent
                sMissKey = "GSAnim.PkgProbeMiss"
                sMissMsg = "idle-svc package hold PROBE-MISS (busy.baka-half service absent = Baka module not present) -- DontMove/Sandbox hold only (REV-137e)"
            EndIf
            If StorageUtil.GetIntValue(None, sMissKey, 0) == 0
                StorageUtil.SetIntValue(None, sMissKey, 1)
                Debug.Trace("[SNAnimGS] " + sMissMsg)
            EndIf
            Return
        EndIf
        ActorUtil.AddPackageOverride(ak, pkgDoNothing, 100, 1)
        ak.EvaluatePackage()
        StorageUtil.SetIntValue(ak, "GSAnim.PkgHold", 1)
        Debug.Trace("[SNAnimGS] idle-svc package hold ENGAGED (DoNothing override): " + ak.GetDisplayName() + " (REV-137c 3.1)")
    Else
        If StorageUtil.GetIntValue(ak, "GSAnim.PkgHold", 0) != 1
            Return
        EndIf
        If pkgDoNothing
            ActorUtil.RemovePackageOverride(ak, pkgDoNothing)
            ak.EvaluatePackage()
        EndIf
        StorageUtil.SetIntValue(ak, "GSAnim.PkgHold", 0)
        Debug.Trace("[SNAnimGS] idle-svc package hold RELEASED (DoNothing override): " + ak.GetDisplayName() + " (REV-137c 3.1)")
    EndIf
EndFunction

;  2.2: the service AI-hold release — called ONLY on the no-fire paths
; (exit/recheck refusal: the caller skips, the actor must return to their
; package immediately). The FIRE path never releases here — the pose
; machinery takes the hold over at fire (_PoseVibe/_PoseDirect re-restrain),
; and every pose-end exit releases via _StopActorPose (timeout / combat /
; stop-pose; belt-and-suspenders: _StopActorPose clears the IdleHold flag
; itself, so no pose-end exit can strand the hold).
Function _ReleaseIdleHold(Actor ak)
    If !ak
        Return
    EndIf
    StorageUtil.SetIntValue(ak, "GSAnim.IdleHold", 0)
    ak.SetRestrained(False)
    ak.SetDontMove(False)
    _PkgHoldActorAI(ak, False)   ;  3.1: package pin rides the no-fire legs too (never strand)
    Debug.Trace("[SNAnimGS] idle-svc AI hold released (no fire): " + ak.GetDisplayName())
EndFunction

Event OnInit()
    _Setup()
EndEvent

Function _Setup()
    PlayerRef = Game.GetPlayer()
    If OpenSelectorSpell && !PlayerRef.HasSpell(OpenSelectorSpell)
        PlayerRef.AddSpell(OpenSelectorSpell, False)
    EndIf
    ; Pose pick (from the DLL) + NPC Senses "an NPC saw something".
    RegisterForModEvent("SNAnimGS_PoseSelected", "OnPoseSelected")
    RegisterForModEvent("SNAnimGS_StopPose",     "OnStopPose")
    _InitDaemonPools()   ; Phase 4: muse seeds + T1 cues + T3 vibe weights + T2 action names
    Debug.Trace("[SNAnimGS] Setup complete. power granted=" + (OpenSelectorSpell != None))
EndFunction

; Female-only is enforced in _PoseVibe (the exec no-ops on male NPCs) and stated in each action's
; description. We deliberately do NOT gate eligibility on a custom "gsanim_female" decorator: the
; LLM evaluates action eligibility for nearby NPCs before/independent of this quest registering
; the decorator, which floods the log with "Decorator not found" (same trap as baka_flirted).

; ── Called by the power's magic effect (SkyrimNet_AnimGS_Power) ──────────────
; Phase 2: capture the crosshair target AT CAST TIME (the cursor is free while the
; grid is open, so the crosshair can't be read at pick time). A non-actor ref or the
; player himself -> None -> the pick takes the original player path, unchanged.
Function OpenSelector()
    _EnsurePools()   ; Phase 4d: stale-instance heal — the power cast is the earliest touch in any loaded session
    _PendingNpcTarget = Game.GetCurrentCrosshairRef() as Actor
    If _PendingNpcTarget == PlayerRef
        _PendingNpcTarget = None
    EndIf
    If !SNAnimGSUI.IsAvailable()
        Debug.Notification("GS pose selector: UI not ready (PrismaUI / SNAnimGS_UI.dll missing?).")
        _PendingNpcTarget = None
        Return
    EndIf
    SNAnimGSUI.OpenPoseGrid()
    ; Phase 4 self-heal: casting the power revives the daemon loop if it had idled out
    ; (both flags off + no posers = the tick never re-registers). Guarded: with posers
    ; mid-sweep a 15s re-register would stretch their 3s timeout sweep, so only kick
    ; when nobody is posing (and if someone is, the 3s sweep loop is alive anyway and
    ; the arbiter in OnUpdate picks the muse/overdrive intervals up from there).
    If StorageUtil.FormListCount(None, "GSAnim.Posing") == 0
        RegisterForSingleUpdate(15.0)
    EndIf
EndFunction

; ── DLL fires this when the player clicks a pose. asPose = "GS123|desc|category" ("" = cancel) ──
; Phase 2: a crosshair NPC captured at cast time poses THE NPC (validated in order
; not-player -> not-dead -> female -> _IsBusyElsewhere, refusal notifications, and it
; NEVER falls back to posing the player). No target = the original player path,
; unchanged. _PendingNpcTarget is cleared on every exit path.
Event OnPoseSelected(String asEventName, String asPose, Float afNum, Form akSender)
    If asPose == ""
        _PendingNpcTarget = None      ; cancel DISCARDS the capture — deliberately inert: closing the menu never stops any pose
        Return
    EndIf
    ; ── Stop Pose button (Phase 2, revised design) ──
    ; Deliberate stop only — the earlier "stop on cancel" idea was rejected (any menu close
    ; with a captured target would have stopped the pose). Uses _StopActorPose exclusively,
    ; no parallel stop code: it drops the held idle, unrestrains, un-pacifies and empties
    ; GSAnim.Pose, and the 3s OnUpdate sweep then removes the (now-empty) posing-list entry
    ; — so other posers on the shared GSAnim.Posing list are never touched.
    If asPose == "STOP_POSE"
        Actor akStop = _PendingNpcTarget
        _PendingNpcTarget = None
        If !akStop || akStop == PlayerRef
            Debug.Notification("No one targeted.")
        ElseIf !StorageUtil.FormListHas(None, "GSAnim.Posing", akStop)
            Debug.Notification(akStop.GetDisplayName() + " isn't posing.")
        Else
            ; Phase 4 rider: name the pose in the stop wording (GSAnim.Vibe, stored at pose
            ; time; _StopActorPose clears it, so read it BEFORE the stop).
            String sVibe = StorageUtil.GetStringValue(akStop, "GSAnim.Vibe", "")
            _StopActorPose(akStop)
            Debug.Notification(akStop.GetDisplayName() + " stops posing.")
            ;  5.3: the stop gesture is a player-initiated pose event --
            ; gated by the player route toggle (DEFAULT ON), same as _PoseDirect.
            If StorageUtil.GetIntValue(None, "GSAnim.PoseNarrPlayer", 1) == 1
                SkyrimNetApi.RegisterEvent("gsanim_npc_pose", \
                    PlayerRef.GetDisplayName() + " gestures for " + akStop.GetDisplayName() \
                    + " to stop posing; " + akStop.GetDisplayName() + _StopWording(sVibe), \
                    akStop, None)
            Else
                Debug.Trace("[SNAnimGS] gsanim_npc_pose cue GATED-OFF (route 3 player stop, " + akStop.GetDisplayName() + ") -- REV-159 5.3")
            EndIf
        EndIf
        Return
    EndIf
    ; ── Phase 4: Performance Mode toggle (grid footer button sentinel — a blind send with
    ; no pipes, so it can never fall into the pose parse; Papyrus arbitrates ON/OFF, same
    ; pattern as STOP_POSE) ──
    If asPose == "OVERDRIVE_TOGGLE"
        _PendingNpcTarget = None      ; the footer button ignores crosshair targeting — stay clean
        _EnsurePools()   ; Phase 4d: this toggle branch demonstrably runs FIRST in a stale instance (flag + notification succeed while everything array-touching downstream is None) — heal at the switch
        If StorageUtil.GetIntValue(None, "GSAnim.Overdrive", 0) == 1
            _OverdriveOff("Sheogorath Mode ended.")    ; 2nd press = OFF (full restore path)
        Else
            Debug.Trace("[SNAnimGS] sheogorath mode toggle: ON requested (grid footer)")   ;  3.2 receipt
            _OverdriveOn()
        EndIf
        Return
    EndIf
    ; ── Phase 4 amendment: Muse toggle (grid footer button sentinel, same blind-send
    ; pattern; was the Phase 4b rider, pulled forward — see the state block up top for why).
    ; No loop kick here, deliberately: the button is reachable only through the grid, the
    ; grid only through the selector cast, and the cast already self-heals an idled loop;
    ; with posers up the 3s sweep is alive — either way the arbiter picks the flag up.
    ; Fresh-ON seeds on the first tick (throttle stamps start at 0/absent). Overdrive
    ; preempts muse in the arbiter, so muse-while-overdrive just waits its turn (starts
    ; <=15s after overdrive ends or expires) — no extra code for that case.
    If asPose == "MUSE_TOGGLE"
        _PendingNpcTarget = None      ; the footer button ignores crosshair targeting — stay clean
        _EnsurePools()   ; Phase 4d: stale-instance heal at the muse switch — the 4c arm transaction below is StorageUtil-only (member-safe, audited), but the _MuseTick chain behind the flag is not
        If StorageUtil.GetIntValue(None, "GSAnim.Muse", 0) == 1
            StorageUtil.SetIntValue(None, "GSAnim.Muse", 0)
            Debug.Trace("[SNAnimGS] sanguine mode toggle: OFF (grid footer)")   ;  3.2 receipt
            Debug.Notification("Sanguine Mode quieted.")
        Else
            StorageUtil.SetIntValue(None, "GSAnim.Muse", 1)
            Debug.Trace("[SNAnimGS] sanguine mode toggle: ON (grid footer)")   ;  3.2 receipt
            ;  Task 2: the session-scope reset now rides the ReferenceAlias load reset
            ; (SkyrimNet_AnimGS_LoadAlias / SNAnimGS_LoadAlias quest —  Option A ruling,
            ; the skynet_PlayerAlias production pattern). The  MuseSetAt stamp heuristic
            ; is RETIRED: no activation stamp is written, and the OnUpdate stale-stamp reset
            ; branch is deleted. Toggle-at-will within a session is untouched (the 09-16 UX
            ; ruling); the flag now agrees with the stateless grid label at every session
            ; start by construction, not by clock inference.
            ; ── Phase 4c rider ( 1c re-arm semantics): arm the 10-min muse debug
            ; window on the FIRST muse activation of THIS BOOT (was: of the whole
            ; playthrough — a one-shot-per-save window made the 09-15 session diagnostically
            ; blind and had to be re-armed by migration). End-stamp + marker are one
            ; transaction; the arm itself is guarded by an in-memory member flag that resets
            ; at every game start, so each boot gets exactly one fresh window. A mid-window
            ; toggle-off still forfeits the remaining time (re-arms only at the next boot).
            ; While the window is open, _MuseTick notifies every seed + a no-seed heartbeat
            ; on screen; when it passes, notifications simply stop (no ceremony).
            If !_bMuseDebugArmedThisBoot
                _bMuseDebugArmedThisBoot = True
                StorageUtil.SetFloatValue(None, "GSAnim.MuseDebugEnd", \
                    Utility.GetCurrentRealTime() + fMuseDebugWindow)
                StorageUtil.SetIntValue(None, "GSAnim.MuseDebugDone", 1)
            EndIf
            Debug.Notification("Sanguine Mode stirring - thoughts turn warm.")
        EndIf
        Return
    EndIf
    ; The grid sends "GS123|short description|category" -- event to play, description to
    ; narrate, category (poses.js id == vibe name) to time NPC-directed poses. Manual
    ; Find/Substring, not StringUtil.Split -- avoids relying on unclear delimiter semantics
    ; entirely, and (unlike Split) doesn't truncate a description that ever contains a "|".
    ; Shapes that arrive: "GS123|desc|cat"; "GS123|cat" only if a pose ever lacks a d (none
    ; do today -- every poses.js entry has one; the tail would parse as desc, cat stays "",
    ; default timeout, harmless); bare "GS123" from anything pre-Phase-2.
    String sEv   = asPose
    String sDesc = ""
    String sCat  = ""
    Int pipeAt = StringUtil.Find(asPose, "|")
    If pipeAt != -1
        sEv = StringUtil.Substring(asPose, 0, pipeAt)
        String tail = StringUtil.Substring(asPose, pipeAt + 1)
        Int pipe2At = StringUtil.Find(tail, "|")
        If pipe2At == -1
            sDesc = tail
        Else
            sDesc = StringUtil.Substring(tail, 0, pipe2At)
            sCat  = StringUtil.Substring(tail, pipe2At + 1)
        EndIf
    EndIf
    ; Diagnostic for the "UI and played animation don't match" report -- confirms exactly what
    ; event name this parse produced from the raw string the UI sent, so a mismatch can be pinned
    ; to "wrong event parsed" vs "right event parsed, wrong animation plays" (a GSPoses-pack-version
    ; issue, not a Papyrus one) from the very first log line.
    String sTargetLog = "player"
    If _PendingNpcTarget
        sTargetLog = _PendingNpcTarget.GetDisplayName()
    EndIf
    Debug.Trace("[SNAnimGS] OnPoseSelected: raw='" + asPose + "' -> event='" + sEv + "' desc='" + sDesc + "' cat='" + sCat + "' target=" + sTargetLog)
    ; ── NPC-target path (Phase 2) ──
    Actor akTarget = _PendingNpcTarget
    _PendingNpcTarget = None
    If akTarget
        If akTarget == PlayerRef       ; can't happen (capture None's it) -- guard anyway
            Debug.Trace("[SNAnimGS] OnPoseSelected: refusing to pose the player via the NPC path.")
            Return
        EndIf
        If akTarget.IsDead()
            Debug.Notification(akTarget.GetDisplayName() + " can't pose: dead.")
            ;  rider sentinel ( registration,  3.1; unconditional per ):
            ; the crosshair validation chain was Notification-only — admit/refuse was NOT
            ; log-distinguishable (posing-gender.md observability gap, closed here).
            Debug.Trace("[SNAnimGS] crosshair refuse: " + akTarget.GetDisplayName() + " dead")
            Return
        EndIf
        ;  Phase B: the L335 female test is replaced by the central policy
        ; admission (posing-gender.md ) — dead/busy legs unchanged above/below.
        ; Mode 2 loses the leg entirely; 0/1 keep per-mode refusal strings.
        ;  fix: pass sCat (the pick's category) — the shipped call passed an
        ; empty vibe, so curated mode refused EVERY male pick here regardless of pose
        ; (the "curated no better than female-only" dogfood finding; grid cats are
        ; the _VibeMaleOK vibe names).
        If _GenderPolicy() != 2 && !_GenderAdmits(akTarget, sCat)
            Debug.Notification(_GenderRefusal(akTarget, _GenderPolicy()))
            ;  rider sentinel ( registration,  3.1; unconditional per ).
            Debug.Trace("[SNAnimGS] crosshair refuse: " + akTarget.GetDisplayName() \
                + " gender policy veto (cat '" + sCat + "', mode " + _GenderPolicy() + ")")
            Return
        EndIf
        If _IsBusyElsewhere(akTarget)   ; mid-scene/combat -- reason stays vague on purpose
            Debug.Notification(akTarget.GetDisplayName() + " can't pose right now.")
            ;  rider sentinel ( registration,  3.1; unconditional per ).
            Debug.Trace("[SNAnimGS] crosshair refuse: " + akTarget.GetDisplayName() + " busy at pick time")
            Return
        EndIf
        ;  (idle-interrupt service, spec 1.4.4): the crosshair pick path
        ; routes through the service — interruptible idle classes (seated/
        ; marker-held) now EXIT -> RECHECK (incl. the gender-policy admit,
        ; re-checked live here per the fire-time contract) -> fire, instead of
        ; being hard-refused by the formerly class-blind sit leg.
        If !_IdleFirePath(akTarget, sCat)
            Debug.Notification(akTarget.GetDisplayName() + " can't pose right now.")
            Debug.Trace("[SNAnimGS] crosshair refuse: idle interrupt refused at pick time (" + akTarget.GetDisplayName() + ", class-aware)")
            Return
        EndIf
        ;  rider sentinel ( registration,  3.1; unconditional per ): the
        ; ADMIT leg — with the three refuse legs above, every crosshair pick outcome is
        ; now log-distinguishable (mode 1 vs 2 admit included).
        Debug.Trace("[SNAnimGS] crosshair admit: " + akTarget.GetDisplayName() \
            + " (cat '" + sCat + "', mode " + _GenderPolicy() + ")")
        _PoseDirect(akTarget, sEv, sDesc, sCat)
        Return
    EndIf
    ; ── Player path (unchanged behavior) ──
    ; Don't pose the player mid-scene elsewhere (Baka paired anim/struggle/downed, Acheron hold,
    ; bleedout, or any sex scene) -- see _IsBusyElsewhere.
    If _IsBusyElsewhere(PlayerRef) || PlayerRef.GetSitState() != 0
        Return
    EndIf
    _sCurrentPose     = sEv
    _sCurrentPoseDesc = sDesc
    Debug.SendAnimationEvent(PlayerRef, sEv)
    String what = "a deliberate pose"
    If sDesc != ""
        what = "a pose - " + sDesc
    EndIf
    SkyrimNetApi.RegisterEvent("gsanim_player_pose", \
        PlayerRef.GetDisplayName() + " strikes " + what + ", holding it for show.", \
        PlayerRef, None)
EndEvent

; DLL fires this when the player presses a movement key (WASD / jump) while posing — drop the
; held idle (GS poses are designed to hold in place, so any movement should end them).
Event OnStopPose(String asEventName, String asArg, Float afNum, Form akSender)
    If _sCurrentPose != ""
        Debug.SendAnimationEvent(PlayerRef, "IdleForceDefaultState")
        ClearPose()
        Debug.Trace("[SNAnimGS] pose stopped (player moved).")
    EndIf
EndEvent

; Clears the "currently posing" flags.
Function ClearPose()
    _sCurrentPose     = ""
    _sCurrentPoseDesc = ""
EndFunction

; ════════════════════════════════════════════════════════════════════════════
;  NPC POSE VIBES — the LLM fires a vibe action; we play a random pose from it.
;  Female-only, held in place. Casual poses are freed if the NPC enters combat
;  (no one is "holding" them); the submission vibe stays locked through combat.
; ════════════════════════════════════════════════════════════════════════════
; Real-seconds hard stop — NPC poses auto-end after this (the LLM rarely picks StopPosing).
; Active vibes (workout / stretch / dance) hold longer; everything else ends sooner.
Float Property fPoseTimeoutActive  = 45.0 Auto   ; workout, stretch, dance, dance_sexy
Float Property fPoseTimeoutDefault = 25.0 Auto   ; all other vibes

; Per-vibe hard-stop duration. Exercise/stretch/dance read well held longer; the rest get 25s.
Float Function _VibeTimeout(String vibe)
    If vibe == "workout" || vibe == "stretch" || vibe == "dance" || vibe == "dance_sexy"
        Return fPoseTimeoutActive
    EndIf
    Return fPoseTimeoutDefault
EndFunction

; Comma-separated GS events per vibe (compact; edit to re-curate). Mirrors poses.js groups
; minus the player-only ones (explicit, situational).
String Function _VibeCSV(String vibe)
    If vibe == "seduce"
        Return "GS1,GS2,GS3,GS17,GS25,GS26,GS31,GS36,GS56,GS62,GS63,GS66,GS70,GS80,GS84,GS189,GS198"
    ElseIf vibe == "selftouch"
        Return "GS6,GS7,GS18,GS46,GS55,GS60,GS69,GS71,GS72,GS87"
    ElseIf vibe == "present"
        Return "GS4,GS5,GS11,GS37,GS38,GS43,GS86,GS88,GS99,GS118,GS130,GS162,GS190,GS193,GS202"
    ElseIf vibe == "dance"
        Return "GS21,GS27,GS34,GS42,GS47,GS48,GS58,GS59,GS79,GS95,GS125,GS132,GS133,GS154,GS209"
    ElseIf vibe == "dance_sexy"
        Return "GS9,GS10,GS12,GS13,GS14,GS15,GS23,GS29,GS44,GS52,GS61,GS83,GS102,GS107,GS144,GS187"
    ElseIf vibe == "ground_sexy"
        Return "GS253,GS257,GS261,GS267,GS271,GS275,GS282,GS285,GS305,GS306,GS311,GS316"
    ElseIf vibe == "ground_idle"
        Return "GS128,GS256,GS270,GS276,GS278,GS286,GS287,GS289,GS295,GS296,GS313,GS314,GS317,GS697,GS698,GS699,GS706,GS712"
    ElseIf vibe == "workout"
        Return "GS156,GS182,GS658,GS659,GS660,GS661,GS663,GS664,GS665,GS666,GS667,GS672,GS676,GS681,GS683,GS690"
    ElseIf vibe == "stretch"
        Return "GS662,GS668,GS669,GS670,GS671,GS673,GS674,GS678,GS679,GS680,GS684,GS686,GS689,GS691"
    ElseIf vibe == "submission"
        Return "GS51,GS700,GS705,GS707,GS708,GS709,GS710"
    ElseIf vibe == "plead"
        Return "GS701,GS702,GS703"
    ElseIf vibe == "idle"
        Return "GS131,GS135,GS147,GS177,GS196,GS624,GS628,GS629,GS632,GS639"
    ;  muse direct-fire additions: single-actor Babo idle EVENTS, fired only from
    ; the muse rider (_MuseFireVibe -> _PoseVibe) under full GS bookkeeping — never a
    ; Baka two-actor action or scene, never an LLM path (no Pose*_Execute wrapper maps
    ; to these vibes, so the action pipeline can't reach them). "aroused" returns the
    ; FEMALE pair as the pool DEFAULT;  A.3 sex-splits the draw at the single
    ; consumer (_VibeEventsFor, used by _PoseVibe): a male target draws
    ; BaboArousedMale01/02 — Baka's own sex-selecting exec path (BakaIntegration
    ; L8657-8663) is the precedent. Females unchanged.
    ElseIf vibe == "handonchin"
        Return "BaboHandonChin"
    ElseIf vibe == "handonface"
        Return "BaboHandonFace"
    ElseIf vibe == "aroused"
        ;  A.3: female pool default; the male draw is _VibeEventsFor's split.
        Return "BaboArousedFemale01,BaboArousedFemale02"
    ;  Task 3 (approved tiers: Tier 1 + Drink): four more single-actor Babo idle EVENTS
    ; under the same muse-rider discipline — GS bookkeeping only, no Baka *_Execute wrapper,
    ; no LLM action path (no wrapper maps to these vibes). Event names are Baka's own exec
    ; provenance (PoseScratchHead -> BaboIdleScratchingHead, PoseBraceArm -> BaboIdleHoldon,
    ; PoseMeditate -> BaboMeditate, PoseDrink -> BaboDrinkNormal). "drink" is the NORMAL
    ; drink hold ONLY — the blackout variant (BaboDrinkBlackOut, baka_opportunity,
    ; pacify/hold AI) stays Baka's exclusive interaction path and is deliberately NOT
    ; reachable from the muse (accepted semantic: muse fires never trigger opportunity cues).
    ; DRINK GUARD EVALUATION (3b, "does the NPC need a drink item?"): NO item guard is
    ; required — Baka's own PoseDrink_Execute (BakaIntegration.psc:8372) performs no
    ; inventory check and fires BaboDrinkNormal bare, i.e. the Babo animation graph
    ; itself supplies the tankard prop. A muse-side item requirement would DIVERGE from
    ; the proven exec path and skip fires Baka itself performs. No skip-with-reason
    ; guard is therefore added; the guard chain that remains (female, busy, overdrive,
    ; allowlist) is identical to every other fire.
    ElseIf vibe == "scratchhead"
        Return "BaboIdleScratchingHead"
    ElseIf vibe == "bracearm"
        Return "BaboIdleHoldon"
    ElseIf vibe == "meditate"
        Return "BaboMeditate"
    ElseIf vibe == "drink"
        Return "BaboDrinkNormal"
    ;  Task 2c (user advocacy ruling): DROOL joins the muse vocabulary — BaboDroolingFace,
    ; a single-actor facial/body idle via a bare _PlaySoloHold in Baka's own exec (no props, no
    ; furniture, no interaction branch — mechanically clean per the  evaluation pattern).
    ; Thematic frame ON RECORD (user): "reduced to it" — the defeat/lust register, alongside
    ; Aroused. YAML description reported to the user in the  gate for retro-review.
    ElseIf vibe == "drool"
        Return "BaboDroolingFace"
    EndIf
    Return ""
EndFunction

;  A.3 (user ruling 2026-10-07, posing-gender.md): aroused-pool sex-split.
; "aroused" is male-admitted (_VibeMaleOK) but its pool was female-only clips — a male
; admitted to the vibe drew female clips (the Addendum A gap). Split at the SINGLE
; consumer of vibe pools: _PoseVibe's draw (grid picks fire exact events via
; _PoseDirect and never map to "aroused"; the T-initiator legs fire no "aroused"
; vibe; the muse fire L1478 is the sole "aroused" supplier). Males draw
; BaboArousedMale01/02 — Baka's own exec (BakaIntegration L8657-8663) is the
; precedent; females (and unknown sex, already blocked at admission upstream) keep
; the female pair. Every other vibe passes through _VibeCSV unchanged. Sentinel per
;  so the split's live effect is greppable in the funnel.
String Function _VibeEventsFor(Actor ak, String vibe)
    If vibe == "aroused"
        If _SexOf(ak) == 0
            Debug.Trace("[SNAnimGS] aroused pool split: " + ak.GetDisplayName() + " draws male clips (A.3)")
            Return "BaboArousedMale01,BaboArousedMale02"
        EndIf
        Return "BaboArousedFemale01,BaboArousedFemale02"
    EndIf
    Return _VibeCSV(vibe)
EndFunction

; ═══════════════════════════════════════════════════════════════════════════
; : THE POSE PICKER DECOMMISSION (user ruling 2026-10-25, the
; pose_picker_pipeline_descision.txt extract; supersedes the  build
; and the  spec's decision-model leg).
;
; The ruling, verbatim rationale: the picker's thin context pack "robs
; choice context rather than sharpening the decision" -- arousal and
; location may hint at the CATEGORY, but not enough to pick between six
; similar dances, and it is all information the FIRST model already held.
; A pose choice is a semantic judgment made of exactly the context the
; consideration LLM is already holding; paying a second (lesser) model to
; reconstruct that judgment from a stripped pack is cost and latency for
; worse decisions.
;
; The shape now: the consideration call (gsanim_muse_consideration) picks
; the category AND the exact move IN ONE PASS -- its context pack gains the
; itemized pose catalog (warning + description + move list per category,
; _MusePoseCatalogText below; the same payload the retired picker's options
; carried, _VibePoseOptions = poses.js catalog of record), and its output
; contract gains "CLIP: <move key>". The answer's CLIP fires through the
;  sForceEvent exact-pick plumbing (kept -- the machinery was proven;
; only the decision-model call is retired). The ded/pose_picker decision
; template is DELETED; _PosePickWanted/_PosePickPack/_PosePickFallbackFire/
; OnPosePicked and the _posePick* members are RETIRED with it.
;
; Random selection is now RESTRICTED TO SHEOGORATH MODE (the GSAnim.Overdrive
; lane, _OdAutoPose -- deliberately random, no LLM anywhere on that path)
; plus two ruled degenerate cases: single-move categories (random over one
; event is deterministic) and the aroused pair (near-identical clips -- a
; choice over indistinguishable options is not a choice). An absent/invalid
; CLIP in the consideration answer degrades to the pool's random draw,
; sentinel'd (the launch-one fallback discipline: never lose the fire).
; The dialogue/emergent lane is unchanged (137f(d) standing): the main LLM
; picks the member action from its yaml descriptions (the  4.3
; pool-move lines are the semantic-selection mechanism there).
; ═══════════════════════════════════════════════════════════════════════════

; A category's poses as a JSON array of "EVENTKEY: description" strings
; (per-pose descriptions straight from poses.js, the catalog of record --
; descriptions, not bare event keys, so "twerk for me" resolves to the
; twerk-bearing dance_sexy/ground_sexy moves). : with the picker's
; decision-model leg retired, this is the CATALOG SOURCE for the muse
; consideration prompt (via _MuseCatalogOptions/_MusePoseCatalogLine ->
; _MusePackContext's poseCatalog field) -- the same payload the retired
; picker carried, now surfaced to the model that already holds the scene
; context. Returns "" for vibes with no catalog descriptions (the Babo
; single-event vibes, the aroused pair). Sets are the _VibeCSV pools
; verbatim.
String Function _VibePoseOptions(String vibe)
    If vibe == "seduce"
        Return "[\"GS1: seducing\",\"GS2: seducing forward\",\"GS3: seducing, looking back\",\"GS17: flirting suggestively\",\"GS25: seducing, moving butt (subtle)\",\"GS26: seducing, moving butt (subtle)\",\"GS31: hip heart, showing\",\"GS36: butt-showing, seductive\",\"GS56: shy provoking, seducing\",\"GS62: looking back suggestively\",\"GS63: moving body slowly down\",\"GS66: horny, side to side\",\"GS70: shy, biting thumb\",\"GS80: slow hip, shy seducing\",\"GS84: boob-carrying, seducing\",\"GS189: tying hair provocatively\",\"GS198: slow, looking forward\"]"
    ElseIf vibe == "selftouch"
        Return "[\"GS6: touching self, horny\",\"GS7: touching self, very horny\",\"GS18: spanking self provocatively\",\"GS46: touching tits suggestively\",\"GS55: super horny, touching self\",\"GS60: touching self all over\",\"GS69: horny, side to side\",\"GS71: touching self all over\",\"GS72: shyly touching tits\",\"GS87: touching boobs, shy\"]"
    ElseIf vibe == "present"
        Return "[\"GS4: bent, showing ass\",\"GS5: bent showing ass, looking forward\",\"GS11: bent, hands to knees, presenting\",\"GS37: bent over, showing butt (slow)\",\"GS38: moving butt slow, looking back\",\"GS43: round butt showing, sexy slow\",\"GS86: bend over shy, showing butt\",\"GS88: hands to knees, presenting\",\"GS99: bent, slutty slow butt\",\"GS118: bend over, looking forward\",\"GS130: bend over, showing butt shyly\",\"GS162: bend over, showing butt shy\",\"GS190: bending, concentrated (kinda sexy)\",\"GS193: showing a bit of butt, seducing\",\"GS202: bending, concentrated (kinda sexy)\"]"
    ElseIf vibe == "dance"
        Return "[\"GS21: skyrim arm dance\",\"GS27: mambo\",\"GS34: victory dance\",\"GS42: good lateral dance\",\"GS47: modest dance\",\"GS48: long static dance\",\"GS58: modest, no seducing\",\"GS59: waiting, hips, no seducing\",\"GS79: joyful, touching hips\",\"GS95: hip + funny hands\",\"GS125: funny dance\",\"GS132: cool, not only sexy\",\"GS133: cool, not only sexy\",\"GS154: valiant, girly\",\"GS209: funny, useful\"]"
    ElseIf vibe == "dance_sexy"
        Return "[\"GS9: twerking, looking back\",\"GS10: sensual, semi-shy\",\"GS12: sensual hips, hands up\",\"GS13: provocative\",\"GS14: sexy, in circles, bent\",\"GS15: distracted, hips moving\",\"GS23: tik-tok hips\",\"GS29: hip dance, sensual slow\",\"GS44: slow twerking, seducing\",\"GS52: man, lewd suggestion\",\"GS61: slow hips, hand on chin\",\"GS83: heating up\",\"GS102: slutty, butt showing\",\"GS107: slutty, side to side\",\"GS144: sexy, not too slutty\",\"GS187: hands up, hips\"]"
    ElseIf vibe == "ground_sexy"
        Return "[\"GS253: all fours, suggestive\",\"GS257: laying, legs up, sexy\",\"GS261: on stomach, looking back, sexy\",\"GS267: all fours, suggesting\",\"GS271: waiting, sexy, thinking\",\"GS275: on stomach, sexy\",\"GS282: seated, sexy\",\"GS285: sexy, suggesting\",\"GS305: twerking on ground\",\"GS306: twerking on ground\",\"GS311: all fours, provocative\",\"GS316: all fours, provocative\"]"
    ;  (cont.): the remaining six catalog-bearing vibes.
    ElseIf vibe == "ground_idle"
        Return "[\"GS128: squatting, looking at ground\",\"GS256: sitting, playful\",\"GS270: recovering, exhausted\",\"GS276: on stomach, bored\",\"GS278: on stomach, moving legs, bored\",\"GS286: seated, exhausted\",\"GS287: exhausted, trauma\",\"GS289: on stomach, bored\",\"GS295: kneeled\",\"GS296: exhausted, trauma\",\"GS313: back resting\",\"GS314: back resting\",\"GS317: laying laterally\",\"GS697: seated, dark-souls-by-fire\",\"GS698: seated, hugging legs\",\"GS699: hand on stomach\",\"GS706: looking down, thinking\",\"GS712: resting, dark-souls\"]"
    ElseIf vibe == "workout"
        Return "[\"GS156: knees up (kinda sexy)\",\"GS182: jumping, training\",\"GS658: jumping warmup\",\"GS659: push-ups\",\"GS660: deadlifts\",\"GS661: glute lateral raises\",\"GS663: abs\",\"GS664: glute bridge\",\"GS665: static footing\",\"GS666: abs, legs up\",\"GS667: mountain climbers\",\"GS672: lateral leg raises\",\"GS676: squats\",\"GS681: leg up + abs\",\"GS683: glute bridge\",\"GS690: footing, hands on hips\"]"
    ElseIf vibe == "stretch"
        Return "[\"GS662: stretching\",\"GS668: dolphin stretch\",\"GS669: leg stretch\",\"GS670: back stretch\",\"GS671: wall stretch\",\"GS673: all-fours stretch\",\"GS674: sun salute yoga\",\"GS678: leg-stride stretch\",\"GS679: hip stretch (ground)\",\"GS680: butt-up stretch\",\"GS684: back/butt-up stretch\",\"GS686: standing back stretch\",\"GS689: legs-up yoga\",\"GS691: arms-up side stretch\"]"
    ElseIf vibe == "submission"
        Return "[\"GS51: cuffed, dancing (prisoner)\",\"GS700: tied, kneeling, hands behind head\",\"GS705: surrendered, hands up\",\"GS707: standing, hands tied back\",\"GS708: standing, hands tied back\",\"GS709: on ground, tied\",\"GS710: on ground, tied, resting on side\"]"
    ElseIf vibe == "plead"
        Return "[\"GS701: sorry (Japanese dogeza)\",\"GS702: praying / sorry\",\"GS703: begging for money\"]"
    ElseIf vibe == "idle"
        Return "[\"GS131: support / friendship gesture\",\"GS135: shy, nervous, contained\",\"GS147: hands behind, slightly sexy\",\"GS177: arms crossed, suggesting\",\"GS196: victory pose\",\"GS624: idle\",\"GS628: idle\",\"GS629: fist battle prep\",\"GS632: mad, arms crossed\",\"GS639: shy waiting\"]"
    EndIf
    Return ""
EndFunction

; : _VibePoseOptions' JSON array flattened to plain prompt prose for
; the consideration catalog: "GS9 twerking, looking back; GS10 sensual,
; semi-shy; ..." -- the CLIP key stays first (it is what the answer names
; back), the description rides after it. Returns "" for catalog-less vibes.
String Function _MuseCatalogOptions(String vibe)
    String sJson = _VibePoseOptions(vibe)
    If sJson == ""
        Return ""
    EndIf
    Int len = StringUtil.GetLength(sJson)
    If len < 4
        Return ""
    EndIf
    String sBody = StringUtil.Substring(sJson, 2, len - 4)
    String[] items = StringUtil.Split(sBody, "\",\"")
    String sOut = ""
    Int i = 0
    While i < items.Length
        String sItem = items[i]
        Int iColon = StringUtil.Find(sItem, ": ")
        If iColon > 0
            sItem = StringUtil.Substring(sItem, 0, iColon) + " " \
                + StringUtil.Substring(sItem, iColon + 2, StringUtil.GetLength(sItem) - iColon - 2)
        EndIf
        If i > 0
            sOut = sOut + "; "
        EndIf
        sOut = sOut + sItem
        i += 1
    EndWhile
    Return sOut
EndFunction

; : ONE library entry for the consideration prompt's pose catalog --
; the user-ruled shape: (a) the category warning (a category of similar
; moves, not one fixed pose), (b) the short content description (the
; approved _MuseFireLabel one-liner register, reused verbatim), (c) the
; itemized move list (the CLIP keys the answer names back). Catalog-less
; members say so in plain text (one fixed move / near-identical variants --
; no CLIP needed; their draw is the ruled degenerate random).
String Function _MusePoseCatalogLine(String sPose)
    String sVibe = _MuseFireVibe(sPose)
    If sVibe == ""
        Return ""
    EndIf
    String sDesc = _MuseFireLabel(sPose)
    String sOpts = _MuseCatalogOptions(sVibe)
    If sOpts == ""
        If sVibe == "aroused"
            Return sPose + " - " + sDesc + " (two near-identical variants - no CLIP needed)"
        EndIf
        Return sPose + " - " + sDesc + " (one fixed move - no CLIP needed)"
    EndIf
    Return sPose + " - " + sDesc + " [a CATEGORY of similar moves, not one fixed pose - you also pick the exact move]: " + sOpts
EndFunction

; : the full pose catalog for the muse consideration context pack --
; every fireable library member, one entry per line. The separators are the
; two-character JSON escape \n (written \\n here; decoded to a real newline
; at render), and the text carries no quotes/backslashes, so the pack stays
; valid JSON. Order matches the prompt's library/male-safe split and the
; _MuseFireVibe allowlist -- the catalog and the fireable set are ONE list
; (the  2a discipline).
String Function _MusePoseCatalogText()
    String s = _MusePoseCatalogLine("PoseSeduce")
    s = s + "\\n" + _MusePoseCatalogLine("PoseSelfTouch")
    s = s + "\\n" + _MusePoseCatalogLine("PosePresent")
    s = s + "\\n" + _MusePoseCatalogLine("PoseDance")
    s = s + "\\n" + _MusePoseCatalogLine("PoseDanceSexy")
    s = s + "\\n" + _MusePoseCatalogLine("PoseGroundSexy")
    s = s + "\\n" + _MusePoseCatalogLine("PoseGroundIdle")
    s = s + "\\n" + _MusePoseCatalogLine("PoseWorkout")
    s = s + "\\n" + _MusePoseCatalogLine("PoseStretch")
    s = s + "\\n" + _MusePoseCatalogLine("PoseSubmission")
    s = s + "\\n" + _MusePoseCatalogLine("PosePlead")
    s = s + "\\n" + _MusePoseCatalogLine("PoseAroused")
    s = s + "\\n" + _MusePoseCatalogLine("PoseBraceArm")
    s = s + "\\n" + _MusePoseCatalogLine("PoseDrink")
    s = s + "\\n" + _MusePoseCatalogLine("PoseDrool")
    s = s + "\\n" + _MusePoseCatalogLine("PoseHandOnChin")
    s = s + "\\n" + _MusePoseCatalogLine("PoseHandOnFace")
    s = s + "\\n" + _MusePoseCatalogLine("PoseMeditate")
    s = s + "\\n" + _MusePoseCatalogLine("PoseScratchHead")
    Return s
EndFunction

; The post-fire bookkeeping of the muse direct fire (extracted ; 
; note: the decision-callback path is retired with the picker, so this now
; serves the single consideration-fire path -- sentinels, notification and
; interval re-arm stay identical).
Function _MuseFireSuccess(Actor ak, String sPose, Float fStamp)
    ;  Task 1b: male fires carry an explicit [male vocab] tag.
    If _SexOf(ak) == 0
        Debug.Trace("[SNAnimGS] sanguine mode direct fire: " + ak.GetDisplayName() + " (" + sPose + ") [male vocab]")
    Else
        Debug.Trace("[SNAnimGS] sanguine mode direct fire: " + ak.GetDisplayName() + " (" + sPose + ")")
    EndIf
    ;  aroused-lean leg 3: the [arousal lean] sentinel (unchanged).
    If StringUtil.Find(_sMuseArous, "high") != -1
        Debug.Trace("[SNAnimGS] sanguine mode direct fire: high-arousal seed - [arousal lean] applies")
    EndIf
    ;  Task 2e: on-screen notification ONLY on actual fires. ASCII-only.
    Debug.Notification("Sanguine Mode - " + ak.GetDisplayName() + " (" + sPose + ")")
    ;  3.2: the next-nudge clock re-armed at pose START. fStamp: the
    ; synchronous path passes the tick's fNow (unchanged semantics); the
    ; decision-callback path passes the callback-time clock.
    StorageUtil.SetFloatValue(None, "GSAnim.MuseGlobal", fStamp)
    Debug.Trace("[SNAnimGS] sanguine mode interval re-armed at pose start: " + ak.GetDisplayName() + " (REV-137f)")
    ;  5.1 (user-ruled at the dogfood; 134f pattern): the Sanguine MODE
    ; direct-narration trigger -- DEFAULT OFF, GS Poses page toggle
    ; (GSAnim.SanguineModeNarr). Desc = what just happened (actor + pose); the
    ; yaml gsanim_sanguine_mode_narr.yaml (register entry 37 DRAFT) matches the
    ; event type ONLY and asks surrounding NPCs to react. Silent-with-sentinel
    ; on the OFF leg. _MuseFireSuccess is the single choke point for every
    ; genuine Sanguine fire (sync + decision-callback paths).
    If StorageUtil.GetIntValue(None, "GSAnim.SanguineModeNarr", 0) == 1
        SkyrimNetApi.RegisterEvent("gsanim_sanguine_mode_narr", \
            ak.GetDisplayName() + " has just slipped into a pose (" + sPose + ").", ak, None)
        Debug.Trace("[SNAnimGS] sanguine mode narration FIRED (gsanim_sanguine_mode_narr, " + ak.GetDisplayName() + ") -- REV-159 5.1")
    Else
        Debug.Trace("[SNAnimGS] sanguine mode narration OFF -- narration event skipped -- REV-159 5.1")
    EndIf
EndFunction

; : OnPosePicked (the ded/pose_picker decision callback) is RETIRED
; with the picker lane -- the consideration call's own answer now carries the
; exact move (CLIP), parsed in OnMuseConsideration and fired through
; _PoseVibe's sForceEvent leg. No decision callback exists on this path.

Function _PacifyGS(Actor ak, Bool on)
    If !ak
        Return
    EndIf
    If on
        ; [ PR#2 fold (2) - Oldcustard credit, by-concept] CLAIM-BEFORE-READ
        ; + CROSS-TREE ORIGINAL REUSE with the Baka tree: when the Baka side
        ; already holds the pacify, its stored original (SHARED key
        ; SNBaka.OrigAggr) is the true pre-pacify aggression -- store nothing of
        ; our own or the release would restore the already-zeroed value. We
        ; still track our own on/off pairing.
        If StorageUtil.GetIntValue(ak, "GSAnim.Pacified", 0) == 0 && StorageUtil.GetIntValue(ak, "SNBaka.Pacified", 0) == 0
            StorageUtil.SetFloatValue(ak, "SNBaka.OrigAggr", ak.GetActorValue("Aggression"))
            StorageUtil.SetIntValue(ak, "GSAnim.Pacified", 1)
        ElseIf StorageUtil.GetIntValue(ak, "GSAnim.Pacified", 0) == 0
            StorageUtil.SetIntValue(ak, "GSAnim.Pacified", 1)   ; Baka owns the original; we ride it
        EndIf
        ak.SetActorValue("Aggression", 0.0)
        ak.StopCombatAlarm()
        ak.StopCombat()
    ElseIf StorageUtil.GetIntValue(ak, "GSAnim.Pacified", 0) == 1
        ; [ PR#2 fold (2)] release only when the LAST pacify owner goes.
        If StorageUtil.GetIntValue(ak, "SNBaka.Pacified", 0) == 0
            ak.SetActorValue("Aggression", StorageUtil.GetFloatValue(ak, "SNBaka.OrigAggr", 1.0))
        EndIf
        StorageUtil.SetIntValue(ak, "GSAnim.Pacified", 0)
    EndIf
EndFunction

; Play a random pose from `vibe` on a FEMALE NPC, held in place; notify SkyrimNet.
; NOTE: "don't pose when busy" is checked at TWO layers now. The pose_*.yaml eligibility gate
; (is_in_combat==false, is_busy==false, not in the SexLab/OStim animating factions) is the LLM's
; snapshot at decision time. _IsBusyElsewhere below is the exec-side backstop for everything that
; can change between that decision and this actually running -- confirmed happening in practice
; (poses breaking sex scenes/downed poses/Baka struggles), which the eligibility-only snapshot
; can't catch. No hard SexLab/Baka/Acheron script dependency: factions are resolved by FormID and
; the rest are plain StorageUtil keys, so this still compiles and runs standalone.
;  2.3 (outcome-true sentinel,  finding 2.3): _PoseVibe now
; RETURNS Bool — True only when a pose event was actually SENT. The old
; caller-side fire sentinel printed after an internal refusal (gender/busy/
; empty-pool early returns happen BEFORE SendAnimationEvent), misreporting
; fires. Refusal legs release any live idle hold (flag-guarded — the T3
; pre-fire path acquires the class-0 hold BEFORE this dispatch, so a
; refusal here must never strand it).
; /163: sForceEvent -- the exact-pick leg. The retired picker's
; plumbing, kept: the consideration call's CLIP answer () fires
; through this same hardened chain (idle-interrupt + hold + recheck +
; guards) instead of the random draw; empty = the random draw (Sheogorath/T3,
; degenerate pools, and the ruled absent/invalid-CLIP fallback -- every
; pre-existing callsite unchanged). The forced event is validated against
; the pool at draw time (belt-and-suspenders; the caller validates before
; calling too).
;  5.3: aiRoute tags the fire lane for the per-route pose-narration
; toggles (user-authored titles, 137f rider): 1 = Sanguine mode fire
; (consideration picks + fallbacks), 2 = emergent autonomous fire (Sheogorath
; T3 + any LLM-chosen pose action via the Pose*_Execute executors),
; 3 = player-initiated (the grid/crosshair pick; also the stop gesture).
; 0/unknown = untagged -- the cue fires ungated (no behavior change).
; The gate reads StorageUtil keys GSAnim.PoseNarrSanguine/Emergent/Player
; (DEFAULT 1 = ON -- current behavior preserved; the MCM "GS Poses" page owns
; them, register entry 37 DRAFT tooltips).
Bool Function _PoseVibe(Actor ak, String vibe, String label, String sForceEvent = "", Int aiRoute = 0)
    If !ak || ak == PlayerRef
        Return False
    EndIf
    ;  Phase B: gender gate routes through _GenderAdmits (the  vibe-level
    ; split is now mode-aware: mode 0 keeps it exactly — females pass, males only via
    ; _VibeMaleOK, unknown sex stays blocked, never a silent change on an unread value;
    ; mode 1 is the same table as the crosshair admission; mode 2 drops the gate).
    If !_GenderAdmits(ak, vibe)
        ;  3.2 full-chain receipt: the gender-policy refusal is named (was a
        ; silent False on the muse/T3 lanes; the crosshair path has its notification).
        Debug.Trace("[SNAnimGS] pose fire refused: GENDER-POLICY (mode " + _GenderPolicy() \
            + " does not admit " + ak.GetDisplayName() + " for vibe '" + vibe + "')")
        If StorageUtil.GetIntValue(ak, "GSAnim.IdleHold", 0) == 1
            _ReleaseIdleHold(ak)
        EndIf
        Return False
    EndIf
    ; Don't pose someone already busy elsewhere (Baka paired anim/struggle/downed, Acheron hold,
    ; bleedout, or any sex scene) -- see _IsBusyElsewhere. Re-checked live at exec time: the is_busy
    ; YAML eligibility gate is only a snapshot from when the LLM decided, and can't see the NPC
    ; becoming busy between that decision and this actually running.
    If _IsBusyElsewhere(ak)
        ;  3.2 full-chain receipt: the busy refusal is named (was silent).
        Debug.Trace("[SNAnimGS] pose fire refused: BUSY (" + ak.GetDisplayName() + " busy at exec time)")
        If StorageUtil.GetIntValue(ak, "GSAnim.IdleHold", 0) == 1
            _ReleaseIdleHold(ak)
        EndIf
        Return False
    EndIf
    ;  (idle-interrupt service, spec 1.4.4): the exec-time leg routes
    ; through the service — with _IsBusyElsewhere class-aware, seated/marker
    ; candidates reach here and must EXIT -> RECHECK -> fire (covers the muse
    ; direct-fire call and the T3 wrapper dispatch, both of which land in
    ; _PoseVibe); every refusal skips with a  sentinel inside the service.
    If !_IdleFirePath(ak, vibe)
        Return False   ; the service already released the hold + sentinel'd every refusal
    EndIf
    ;  A.3: the draw routes through _VibeEventsFor (the A.3 sex-split for
    ; "aroused"; every other vibe unchanged from _VibeCSV).
    String csv = _VibeEventsFor(ak, vibe)
    If csv == ""
        ;  2.2 belt-and-suspenders: no fire — never strand the hold
        ; (the recheck PASS already handed restraint to this machinery).
        ak.SetRestrained(False)
        ak.SetDontMove(False)
        _PkgHoldActorAI(ak, False)   ;  3.1: same belt-and-suspenders for the package pin
        StorageUtil.SetIntValue(ak, "GSAnim.IdleHold", 0)
        Debug.Trace("[SNAnimGS] pose fire refused: empty vibe event pool ('" + vibe + "', " + ak.GetDisplayName() + ")")
        Return False
    EndIf
    String[] list = StringUtil.Split(csv, ",")
    String ev = list[Utility.RandomInt(0, list.Length - 1)]
    If sForceEvent != ""
        ; : the decision callback's pick -- must be a member of the pool
        ; (the template's options came from this same CSV; a stray key refuses,
        ; the hold was never taken at this point so nothing to release).
        Int iFound = -1
        Int iEv = 0
        While iEv < list.Length && iFound < 0
            If list[iEv] == sForceEvent
                iFound = iEv
            EndIf
            iEv += 1
        EndWhile
        If iFound < 0
            Debug.Trace("[SNAnimGS] pose fire refused: forced event '" + sForceEvent + "' not in pool '" + vibe + "' (REV-152 guard)")
            Return False
        EndIf
        ev = sForceEvent
        Debug.Trace("[SNAnimGS] exact-pick fires: " + ak.GetDisplayName() + " -> " + ev + " (cat '" + vibe + "', consideration CLIP)")
    EndIf
    Bool lockAI = (vibe == "submission")
    ak.SetRestrained(True)
    _PacifyGS(ak, True)
    If lockAI
        ak.SetDontMove(True)   ; bound/surrendered — a fight shouldn't break it
    EndIf
    Debug.SendAnimationEvent(ak, ev)
    StorageUtil.SetStringValue(ak, "GSAnim.Pose",    ev)
    StorageUtil.SetFloatValue(ak,  "GSAnim.Start",   Utility.GetCurrentRealTime())
    StorageUtil.SetFloatValue(ak,  "GSAnim.Timeout", _VibeTimeout(vibe))
    StorageUtil.SetIntValue(ak,    "GSAnim.LockAI",  lockAI as Int)
    StorageUtil.FormListAdd(None,  "GSAnim.Posing", ak, False)
    StorageUtil.SetStringValue(ak,  "GSAnim.Vibe",   label)   ; Phase 4 rider: named-pose stop wording
    StorageUtil.SetFloatValue(None, "GSAnim.LastPoseFire", Utility.GetCurrentRealTime())  ; observability only since  (silence-floor reader retired)
    ;  5.3: the per-route pose-narration gate (DEFAULT ON -- the cue fires
    ; exactly as before unless the user turns a route's toggle off on the GS
    ; Poses page; silent-with-sentinel on the gated-skip leg, ruleset 5).
    Int iNarrGate = 1
    If aiRoute == 1
        iNarrGate = StorageUtil.GetIntValue(None, "GSAnim.PoseNarrSanguine", 1)
    ElseIf aiRoute == 2
        iNarrGate = StorageUtil.GetIntValue(None, "GSAnim.PoseNarrEmergent", 1)
    ElseIf aiRoute == 3
        iNarrGate = StorageUtil.GetIntValue(None, "GSAnim.PoseNarrPlayer", 1)
    EndIf
    If iNarrGate == 1
        SkyrimNetApi.RegisterEvent("gsanim_npc_pose", \
            ak.GetDisplayName() + _PoseVibeDesc(vibe, label), ak, None)
    Else
        Debug.Trace("[SNAnimGS] gsanim_npc_pose cue GATED-OFF (route " + aiRoute + ", " + ak.GetDisplayName() + ") -- REV-159 5.3")
    EndIf
    ;  4.1 (user ruling 2026-10-22, USER-AUTHORED per this ruling -- 17b
    ; precedent, register-cited in gs-poses.md  + posing-gender.md): every
    ; genuine Sheogorath/T3 fire carries an on-screen receipt mirroring the Sanguine
    ; notification format ("Sanguine Mode - <NPC> (<pose>)"). ASCII-only (4f rule).
    ;  3.1 (gated-behind-a-branch verdict, 2.1): the old _bT3InFlight member
    ; window closed at the synchronous ExecuteAction RETURN, before the async dispatch's
    ; fire reached this success leg -- the 10-22 dogfood log shows 4/4 dispatched rc=0
    ; fires with package-hold ENGAGED receipts and 0/4 "T3 FIRE receipt" lines. The gate
    ; is now a per-actor GSAnim.T3Mark timestamp (set at dispatch in _OdAutoPose,
    ; consumed here within 30s) + the overdrive flag, so genuine T3 fires notify while
    ; crosshair/muse fires that merely happen while overdrive runs never masquerade.
    Float fT3Mark = StorageUtil.GetFloatValue(ak, "GSAnim.T3Mark", 0.0)
    Float fNowT3  = Utility.GetCurrentRealTime()
    If fT3Mark > 0.0 && fT3Mark <= fNowT3 && fNowT3 - fT3Mark <= 30.0 \
       && StorageUtil.GetIntValue(None, "GSAnim.Overdrive", 0) == 1
        StorageUtil.SetFloatValue(ak, "GSAnim.T3Mark", 0.0)   ; consume (0.0 = no mark; UnSetValue is not in this API surface)
        Debug.Trace("[SNAnimGS] sheogorath T3 FIRE receipt: " + ak.GetDisplayName() + " (" + vibe + ")")
        Debug.Notification("Sheogorath - " + ak.GetDisplayName() + " (" + vibe + ")")
        ;  5.1 (user-ruled at the dogfood; 134f pattern): the Sheogorath
        ; MODE direct-narration trigger -- DEFAULT OFF, GS Poses page toggle
        ; (GSAnim.SheogorathModeNarr). The desc says what just happened (actor
        ; + pose); the yaml gsanim_sheogorath_mode_narr.yaml (register entry 37
        ; DRAFT) matches the event type ONLY and asks surrounding NPCs to react.
        ; Silent-with-sentinel on the OFF leg.
        If StorageUtil.GetIntValue(None, "GSAnim.SheogorathModeNarr", 0) == 1
            SkyrimNetApi.RegisterEvent("gsanim_sheogorath_mode_narr", \
                ak.GetDisplayName() + " has just been moved into a pose (" + vibe + ").", ak, None)
            Debug.Trace("[SNAnimGS] sheogorath mode narration FIRED (gsanim_sheogorath_mode_narr, " + ak.GetDisplayName() + ") -- REV-159 5.1")
        Else
            Debug.Trace("[SNAnimGS] sheogorath mode narration OFF -- narration event skipped -- REV-159 5.1")
        EndIf
    EndIf
    RegisterForSingleUpdate(3.0)
    Return True   ;  2.3: outcome-true — the event WAS sent
EndFunction

; Phase 2: pose a specific NPC with a specific event — the player's explicit grid pick,
; aimed by crosshair at cast time. Mirrors _PoseVibe (restrain, pacify, anim event,
; GSAnim.* keys, posing list, update timer) but takes the event directly and never locks
; AI (LockAI = 0 — a player-directed pose is not a submission hold; combat still frees
; the NPC via OnUpdate). Validation + refusal notifications already happened in
; OnPoseSelected; on refusal nothing was posed and nothing falls back to the player.
Function _PoseDirect(Actor ak, String ev, String desc, String cat)
    ;  2.2: _PoseDirect acquires the re-grab hold AT FIRE (finding
    ; 2.1 — the wander defect). The restrain call was already here; the
    ; IdleHold flag + sentinel are new so _StopActorPose's belt-and-
    ; suspenders clearing covers this path uniformly (the crosshair service
    ; path sets the flag too — idempotent).
    ak.SetRestrained(True)
    StorageUtil.SetIntValue(ak, "GSAnim.IdleHold", 1)
    Debug.Trace("[SNAnimGS] pose hold acquired at direct fire: " + ak.GetDisplayName())
    _PacifyGS(ak, True)
    Debug.SendAnimationEvent(ak, ev)
    StorageUtil.SetStringValue(ak, "GSAnim.Pose",    ev)
    StorageUtil.SetFloatValue(ak,  "GSAnim.Start",   Utility.GetCurrentRealTime())
    StorageUtil.SetFloatValue(ak,  "GSAnim.Timeout", _VibeTimeout(cat))   ; cat == vibe name; unknown/"" -> default
    StorageUtil.SetIntValue(ak,    "GSAnim.LockAI",  0)
    StorageUtil.FormListAdd(None,  "GSAnim.Posing", ak, False)
    StorageUtil.SetStringValue(ak,  "GSAnim.Vibe",   desc)    ; Phase 4 rider (desc; "" if the pick carried none)
    StorageUtil.SetFloatValue(None, "GSAnim.LastPoseFire", Utility.GetCurrentRealTime())  ; observability only since  (silence-floor reader retired)
    RegisterForSingleUpdate(3.0)
    String what = "a pose"
    If desc != ""
        what = "a pose - " + desc
    EndIf
    ;  5.3: the player-initiated route's pose-narration gate (DEFAULT ON;
    ; GSAnim.PoseNarrPlayer, GS Poses page -- "Player Initiated Pose Narration",
    ; user-authored title).
    If StorageUtil.GetIntValue(None, "GSAnim.PoseNarrPlayer", 1) == 1
        SkyrimNetApi.RegisterEvent("gsanim_npc_pose", \
            ak.GetDisplayName() + " strikes " + what + " at " + PlayerRef.GetDisplayName() + "'s direction.", \
            ak, None)
    Else
        Debug.Trace("[SNAnimGS] gsanim_npc_pose cue GATED-OFF (route 3 player, " + ak.GetDisplayName() + ") -- REV-159 5.3")
    EndIf
EndFunction

Function _StopActorPose(Actor ak)
    If !ak
        Return
    EndIf
    Debug.SendAnimationEvent(ak, "IdleForceDefaultState")
    ak.SetRestrained(False)
    ak.SetDontMove(False)
    StorageUtil.SetIntValue(ak, "GSAnim.IdleHold", 0)   ;  2.2 belt-and-suspenders: never strand the idle hold
    _PkgHoldActorAI(ak, False)   ;  3.1: pose end -- return the actor to their package naturally
    _PacifyGS(ak, False)
    StorageUtil.SetStringValue(ak, "GSAnim.Pose", "")
    StorageUtil.SetStringValue(ak, "GSAnim.Vibe", "")   ; Phase 4 rider: consumed by whichever stop path ran
EndFunction

; Monitor: free casual posers who entered combat / timed out; submission stays unless dead.
Event OnUpdate()
    Int i = StorageUtil.FormListCount(None, "GSAnim.Posing") - 1
    Bool anyLeft = False
    While i >= 0
        Actor ak = StorageUtil.FormListGet(None, "GSAnim.Posing", i) as Actor
        If !ak || StorageUtil.GetStringValue(ak, "GSAnim.Pose", "") == ""
            StorageUtil.FormListRemoveAt(None, "GSAnim.Posing", i)
        Else
            Bool  lockAI  = StorageUtil.GetIntValue(ak, "GSAnim.LockAI", 0) == 1
            Float elapsed = Utility.GetCurrentRealTime() - StorageUtil.GetFloatValue(ak, "GSAnim.Start", 0.0)
            Float timeout = StorageUtil.GetFloatValue(ak, "GSAnim.Timeout", fPoseTimeoutDefault)
            If (!lockAI && ak.IsInCombat()) || elapsed > timeout || ak.IsDead()
                _StopActorPose(ak)
                StorageUtil.FormListRemoveAt(None, "GSAnim.Posing", i)
            Else
                anyLeft = True
            EndIf
        EndIf
        i -= 1
    EndWhile
    ; ──  Task 2: the  session-scope stamp heuristic's reset branch is RETIRED ──
    ; The load reset now rides the ReferenceAlias (SkyrimNet_AnimGS_LoadAlias on the
    ; SNAnimGS_LoadAlias quest — Option A ruling): deterministic OnPlayerLoadGame, the exact
    ; skynet_PlayerAlias production pattern. The MuseSetAt stamp write was deleted at the
    ; toggle site; any stamp left in older saves is inert (nothing reads it). MuseSetAt
    ; was NEVER part of the MuseGlobal/LastMuse clamp family — those read clamps stay.
    ; ── Duty B: Phase 4 daemon (muse + performance mode) — suspended while the player fights ──
    If PlayerRef.IsInCombat()
        ; Duty A above still ran (posers keep their combat-release/timeouts). Record when the
        ; suspend began so the overdrive expiry clock can be paused for exactly that span once
        ; the fight ends; the duties themselves are skipped entirely while in combat.
        If StorageUtil.GetIntValue(None, "GSAnim.Overdrive", 0) == 1 \
           && StorageUtil.GetFloatValue(None, "GSAnim.CombatSuspendStart", 0.0) == 0.0
            StorageUtil.SetFloatValue(None, "GSAnim.CombatSuspendStart", Utility.GetCurrentRealTime())
        EndIf
        ;  user ruling (b) SUPERSEDES the v1.2 muse decouple: no posing during combat,
        ; player or NPC — the muse now suspends while the PLAYER fights too. The call stays
        ; here so the tick gate inside _MuseTick (player-combat = early return, global stamp
        ; NOT spent, tick not counted) is the single choke point, with a reason-coded
        ; MuseSuspend-PlayerCombat trace sentinel so the ON session can confirm suspend/resume.
        ; Only the OVERDRIVE keeps its combat suspend + expiry clock-pause (unchanged).
        If StorageUtil.GetIntValue(None, "GSAnim.Muse", 0) == 1
            _MuseTick()
        EndIf
    Else
        Float fSusp = StorageUtil.GetFloatValue(None, "GSAnim.CombatSuspendStart", 0.0)
        If fSusp > 0.0
            ; Combat just ended: extend the expiry by exactly the suspended span (clock pause).
            Float fSpan = Utility.GetCurrentRealTime() - fSusp
            StorageUtil.SetFloatValue(None, "GSAnim.OverdriveExpire", \
                StorageUtil.GetFloatValue(None, "GSAnim.OverdriveExpire", 0.0) + fSpan)
            StorageUtil.SetFloatValue(None, "GSAnim.CombatSuspendStart", 0.0)
        EndIf
        If StorageUtil.GetIntValue(None, "GSAnim.Overdrive", 0) == 1
            _OverdriveTick()
        ElseIf StorageUtil.GetIntValue(None, "GSAnim.Muse", 0) == 1
            _MuseTick()
        EndIf
    EndIf
    ; ── Interval arbiter — the script's ONLY re-register point ──
    ; Posers need the fast sweep; overdrive polls at 15s (T1 ~20s cadence internal, T3
    ; every-15s multi-poser internal — both time-based inside the tick, so a faster sweep
    ; tick can't accelerate them;  3.3); muse
    ; polls at 15s (internal 2-min/5-min clocks). Both flags off + no posers = idle, zero
    ; cost (same as before Phase 4) — casting the selector power re-arms the loop.
    If anyLeft
        RegisterForSingleUpdate(3.0)
    ElseIf StorageUtil.GetIntValue(None, "GSAnim.Overdrive", 0) == 1
        RegisterForSingleUpdate(15.0)
    ElseIf StorageUtil.GetIntValue(None, "GSAnim.Muse", 0) == 1
        RegisterForSingleUpdate(15.0)
    EndIf
EndEvent

; ════════════════════════════════════════════════════════════════════════════
;  PHASE 4 — MUSE DAEMON + PERFORMANCE MODE (overdrive)
;  One OnUpdate loop (above), two StorageUtil flags. The muse half is a thought-seeder
;  ONLY — GenerateNPCThought seeds worded to feed the NPC's OVERRIDING inner-voice
;  blocks; scene ambience NARRATION is the dashboard trigger's job (gsanim_muse_ambience
;  YAML), never this script. The overdrive half: T1 short-lived ambience cues in scene
;  context (~20s, stable eventId = the previous cue is overwritten, one line at a time),
;  T2 pose-cooldown floor (27 actions set to iOdCooldownFloor instead of 0 — Fix B/4f:
;  zero-cooldown let the LLM chain poses back-to-back, spam confirmed in the 4e re-test),
;  T3 silence-floor auto-pose (>=40s without a pose fire -> one eligible female NPC strikes
;  a solo-safe GS vibe via ExecuteAction, which bypasses eligibility AND cooldowns by
;  design, so our own guard chain is mandatory).
;  Player combat suspends all daemon duties; the overdrive expiry clock pauses for exactly
;  the combat span. Nothing here ever calls DirectNarration.
; ════════════════════════════════════════════════════════════════════════════

Float fOdExpireSeconds   = 300.0     ; Performance Mode auto-OFF after ~5 min (combat pauses the clock)
Int   iOdCooldownFloor   = 10        ; T2 (Fix B, 4f): floor ON applies to all 27 pose cooldowns instead
                                     ;   of 0 — zero-cooldown let the LLM chain poses back-to-back (live
                                     ;   spam confirmed in the 4e re-test). USER TASTE CALL 2026-09-10:
                                     ;   10s; retune here, recompile. OFF restores 0 (live-config parity).
                                     ;   Int — SetActionCooldown takes cooldownTimeSeconds as int.
Float fOdT3IntervalSec  = 15.0      ; T3 ( 3.3, user ruling 2026-10-22 "I want chaos --
                                     ;   multiple posers and poses at the same time"): a NEW candidate
                                     ;   fires every interval with overlapping pose lifetimes permitted
                                     ;   (planner overdrive cadence 15s; the 40s silence floor is RETIRED —
                                     ;   the one-at-a-time constraint it enforced is the subdued feel)
Float fOdCueSeconds      = 20.0      ; T1: ambience cue cadence
Float fMuseNudgeIntervalSec = 30.0   ; muse (v1.2 redesign, docs/MUSE_REDESIGN_DESIGN.md): nudge loop — ONE
                                     ;   consideration call per interval.  Task 2b (user tempo ruling,
                                     ;   formally accepted + recorded): 100s -> 30s. BUDGET RULING RECORDED
                                     ;   (user decision, standing): ~120 calls/hr is the accepted standing
                                     ;   cost while ON — the cadence itself bounds spend. Replaces the old
                                     ;   120s-global / 300s-per-NPC throttle pair (user spec); 's
                                     ;   100.0->60.0 hold is superseded by this ruling.
                                     ;  3.2: this member is NO LONGER the interval of record on
                                     ;   long-lived saves — save state restores a pre- member value
                                     ;   (100.0) over this compiled 30.0 initializer (the deployed []
                                     ;   pex hash-matched the dist yet the 10-22 dogfood log printed
                                     ;   100.000000s — the diagnosed ~100s-gap source). The live interval
                                     ;   now reads the StorageUtil key GSAnim.NudgeInterval with THIS
                                     ;   value as default (fresh key, absent from old saves -> 30.0).
Float fMusePerNpcSec     = 60.0       ;  Task 2b (user tempo ruling): per-NPC floor 120s -> 60s — a
                                     ;   candidate whose LastMuse seed is younger than this is skipped in
                                     ;   the walk (seed-time write of GSAnim.LastMuse unchanged; the READ
                                     ;   clamps stale stamps > fNow to 0 first, same pattern as the
                                     ;   MuseGlobal clamp). The global interval remains the spend bound;
                                     ;   the floor only redistributes targets between NPCs. Sentinel:
                                     ;   "muse npc floor skip".  original: (user ruling 09-16,
                                     ;   docs/MUSE_CADENCE_TUNING_SPEC.md).
Float fMuseDebugWindow   = 600.0     ; Phase 4c rider: one-shot muse debug window, 10 min, first activation only
Float fDaemonRadius      = 2500.0    ; daemon scan/seed radius around the player

; T3 weighted vibe pool — Edit 2: ONE named constant block; retune HERE (minutes, not hours).
; v1 ships deliberately broader than the old 50/20/15/15 sketch — broad expressiveness, not
; an 85%-sexy floor; the first overdrive session's observations drive any retuning.
; Names are ACTION names — ExecuteAction dispatches to the Pose*_Execute wrappers, whose
; own guards (female check + _IsBusyElsewhere) re-run live at dispatch.
String[] _OdVibeNames
Int[]    _OdVibeWeights
Int      _OdWeightTotal   = 0

; The 27 pose actions (12 GS + 15 Baka-described) for the T2 cooldown floor. Live config
; verified: all 27 sit at effective cooldown 0 today, so "restore at OFF" == re-zero —
; exact as of this build. ON sets them to iOdCooldownFloor (Fix B/4f), not 0. Caveat (gate
; report): any pose cooldown later tuned via the dashboard Actions editor gets stomped
; back to 0 at OFF; Phase 5 revisits via GetConfig.
String[] _PoseActions

; Muse (v1.2 redesign — docs/MUSE_REDESIGN_DESIGN.md, user-authoritative spec): the fixed
; seed pool (desire/restraint-slip registers) is DELETED (Change 1 — no canned line survives);
; each nudge is ONE LLM consideration call whose YES-output is a JOB (WHICH pose fits + the
; grounded in-world thought), seeded via GenerateNPCThought. The pose fires through the NPC's
; own action selection — the thought is the nudge, cue-not-floor stands.
; The pending actor bridges the call to OnMuseConsideration (guards re-checked at seed time).
Actor   _musePendingActor = None
;  4.1 ->  3.1: the _bT3InFlight member is RETIRED (save-member of no
; further use; Papyrus silently skips absent names on load). The T3 receipt gate is now
; the per-actor StorageUtil stamp GSAnim.T3Mark, set at dispatch and consumed within 30s
; by _PoseVibe's success leg — see the receipt block there for the async-window evidence.
; OStimExcitementFaction, resolved once via PO3 editor-ID lookup (arousal context for the
; nudge pack); None when OStim is absent — arousal then drops out of the pack gracefully.
Faction _kMuseArousalFaction = None
Bool    _bMuseArousalResolved = False
;  aroused-lean: the tier label of the CURRENT in-flight consideration
; (set in _MusePackContext at ask time, read at fire time for the [arousal lean]
; sentinel) — the single-in-flight pattern of _musePendingActor (one ask, one
; callback; never multi-set).
String  _sMuseArous = ""
;  (picker decommission, user ruling 2026-10-25): the _posePick*
; decision-call pending state (Actor/_posePickVibe/_posePickPose, )
; is RETIRED -- no decision call exists on the muse path anymore; the exact
; move rides the consideration answer itself (OnMuseConsideration's CLIP
; parse), so _musePendingActor is once again the only in-flight state.
; Phase 4c rider: heartbeat rate-limit clock for the one-shot muse debug window. Member,
; not StorageUtil: diagnostic-only precision — a script reload mid-window at worst resets
; the 30s beat spacing; the window BOUNDS are StorageUtil so saves keep them.
Float   _fMuseDebugBeat = 0.0
;  1b/1c riders (boot-scoped member vars — they reset at every game start, unlike the
; StorageUtil stamps that persist in saves and are the residue source being fixed here):
Bool    _bMuseGateLogged        = False  ; 1b: first-gated-tick sentinel fired this boot
Bool    _bMuseDebugArmedThisBoot = False  ; 1c: debug window armed this boot (per-boot re-arm)

; T1 ambience cues — short, present tense, scene-context-only (short-lived events, never
; narration).
String[] _OdCues

Function _InitDaemonPools()
    _DaemonPool = new Actor[64]   ; fixed 64-slot scratch pool (Papyrus: literal sizes only)
    ; T3 pool (weights: Dance 30 / DanceSexy 25 / Stretch 15 / Workout 15 / Seduce 15)
    _OdVibeNames = new String[5]
    _OdVibeNames[0] = "PoseDance"
    _OdVibeNames[1] = "PoseDanceSexy"
    _OdVibeNames[2] = "PoseStretch"
    _OdVibeNames[3] = "PoseWorkout"
    _OdVibeNames[4] = "PoseSeduce"
    _OdVibeWeights = new Int[5]
    _OdVibeWeights[0] = 30
    _OdVibeWeights[1] = 25
    _OdVibeWeights[2] = 15
    _OdVibeWeights[3] = 15
    _OdVibeWeights[4] = 15
    _OdWeightTotal = 100
    ; T2 action names (27 = 12 GS vibes + 15 Baka-described poses)
    _PoseActions = new String[27]
    _PoseActions[0]  = "PoseSeduce"
    _PoseActions[1]  = "PoseSelfTouch"
    _PoseActions[2]  = "PosePresent"
    _PoseActions[3]  = "PoseDance"
    _PoseActions[4]  = "PoseDanceSexy"
    _PoseActions[5]  = "PoseGroundSexy"
    _PoseActions[6]  = "PoseGroundIdle"
    _PoseActions[7]  = "PoseWorkout"
    _PoseActions[8]  = "PoseStretch"
    _PoseActions[9]  = "PoseSubmission"
    _PoseActions[10] = "PosePlead"
    _PoseActions[11] = "PoseIdle"
    _PoseActions[12] = "PoseAroused"
    _PoseActions[13] = "PoseAutograph"
    _PoseActions[14] = "PoseBraceArm"
    _PoseActions[15] = "PoseCrouch"
    _PoseActions[16] = "PoseDogeza"
    _PoseActions[17] = "PoseDrink"
    _PoseActions[18] = "PoseDrool"
    _PoseActions[19] = "PoseFood"
    _PoseActions[20] = "PoseHandOnChin"
    _PoseActions[21] = "PoseHandOnFace"
    _PoseActions[22] = "PoseKneel"
    _PoseActions[23] = "PoseMeditate"
    _PoseActions[24] = "PosePickpocket"
    _PoseActions[25] = "PoseSleep"
    _PoseActions[26] = "PoseScratchHead"
    ; Muse (v1.2 redesign): the _MuseSeeds pool (desire/restraint-slip registers) is DELETED —
    ; Change 1 of docs/MUSE_REDESIGN_DESIGN.md. Every nudge thought is now derived from a live
    ; LLM consideration call, never rotated from a canned pool. Nothing to init here.
    ; T1 ambience cues — short, present tense, scene-context-only
    _OdCues = new String[8]
    _OdCues[0] = "the lute quickens; every eye in the room drags back to the floor"
    _OdCues[1] = "the crowd leans in; the room has contracted to the performance"
    _OdCues[2] = "someone whistles low; a coin rings against the floorboards"
    _OdCues[3] = "the air is charged; strangers stand closer than they did a minute ago"
    _OdCues[4] = "even the barmaid stops, tray balanced on one hand, to watch"
    _OdCues[5] = "the applause is ragged but real; the room wants more"
    _OdCues[6] = "torchlight gutters; faces go amber and soft"
    _OdCues[7] = "a hush, then the beat comes back harder"
EndFunction

; ── Phase 4d: stale-instance lazy-init self-heal ─────────────────────────────
; ROOT CAUSE this closes: OnInit/_Setup (which calls _InitDaemonPools above) runs
; ONLY when the quest instance is CREATED — new game or quest reset — and NEVER on
; save load. A save whose instance predates the build that added these arrays loads
; the NEW code but every pool member restores as None: Papyrus links save state to
; script variables BY NAME and silently skips variables absent from the save — zero
; log warnings, which is why this hid through fresh-game testing and only surfaced
; in a long-lived save (fresh-game testing worked, long-save testing failed: the
; classic Papyrus lifecycle trap). One cause explained all three 4c-demo symptoms:
; 0 muse seeds (None pool -> .Length reads 0 silently -> _DaemonScan returns 0 ->
; "scan empty" heartbeats with zero _DaemonScan stacks), T3 silence (the _OdCue
; indexing crash aborted _OverdriveTick BEFORE the silence-floor check could run),
; 0 T1 cues (every _OdCue call crashed). The guard is idempotent and tests ALL pool
; arrays the tick chain touches — a partial test invites a partial heal and a second
; chase. It is RETROACTIVE self-healing: every pre-Phase-4 save heals itself on its
; next touch of any guarded entry point, no quest reset or new game needed; after
; that first heal the instance carries the arrays in its own save state and the
; guard is a no-op thereafter (cost when healthy: six None-checks per tick).
Function _EnsurePools()
    If !_DaemonPool || !_OdVibeNames || !_OdVibeWeights || !_PoseActions || !_OdCues
        _InitDaemonPools()
        Debug.Trace("[SNAnimGS] lazy pool heal: stale quest instance (pre-Phase-4 save) re-initialized.")
    EndIf
    ; Phase 4e one-shot migration: the 4c debug window was consumed during the A5 outage
    ; (the entire Phase-4 pipeline was dead when the user consumed it — a demo against a
    ; broken system is void), so restore the instrumented window exactly once. Keyed on
    ; its OWN marker, deliberately OUTSIDE the heal branch: fresh games never trip the
    ; heal (arrays are live from OnInit), yet still need this exactly once — harmless
    ; there, as the window arms on the first Muse press as designed either way.
    If StorageUtil.GetIntValue(None, "GSAnim.ReArm4e", 0) == 0
        StorageUtil.SetIntValue(None, "GSAnim.MuseDebugDone", 0)
        StorageUtil.SetIntValue(None, "GSAnim.ReArm4e", 1)
        Debug.Trace("[SNAnimGS] 4e migration: debug window re-armed (prior consumption occurred during the A5 outage).")
    EndIf
EndFunction

; Shared candidate scan (PO3 level-0 = AI-processed loaded actors; Baka's shipped code uses
; exactly this for its scans). Fills the _DaemonPool member (64 slots, fixed-size — Papyrus
; requires literal array sizes) and returns the eligible count; callers index [0, count-1].
; Filters: not player, alive, female, within radius, not posing, not in combat.
; _IsBusyElsewhere is the busy backstop used everywhere else (Baka/Acheron/bleedout/sex-scene/
; sit); it also covers IsInCombat internally but the explicit check keeps the filter list
; honest and self-documenting.
Actor[] _DaemonPool

Int Function _DaemonScan(Bool bAllowMales = False)
    ;  3.1 GENDER-POLICY BLANKET (user ruling 2026-10-22, supersedes the 
    ; scope note): the GS pose gender-policy modes apply to ALL pose routes -- the Prisma
    ; crosshair, Sanguine (muse) and Sheogorath (overdrive/T3) all adopt the SAME policy
    ; the crosshair uses. The T3 female-only pool is RETIRED and the muse's mode-blind
    ; male admission is RETIRED: pool admission is now purely policy-driven -- mode 0 =
    ; female-only everywhere; mode 1 = males enter every pool (vibe curated at fire time
    ; by the existing _GenderAdmits legs in _PoseVibe / the muse fire veto); mode 2 =
    ; everyone. bAllowMales is kept for signature compatibility only (callers unchanged);
    ; it no longer gates anything. Unknown sex: blocked in modes 0/1, admitted in mode 2
    ; (never a silent behavior change on an unread value -- the 6a discipline).
    Int n = 0
    Actor[] akAll = PO3_SKSEFunctions.GetActorsByProcessingLevel(0)
    Int i = 0
    While i < akAll.Length && n < _DaemonPool.Length
        Actor ak = akAll[i]
        If ak && ak != PlayerRef && !ak.IsDead() \
           && (_SexOf(ak) == 1 || _GenderPolicy() >= 1) \
           && ak.GetDistance(PlayerRef) <= fDaemonRadius \
           && StorageUtil.GetStringValue(ak, "GSAnim.Pose", "") == "" \
           && !ak.IsInCombat() \
           && ak.GetSleepState() == 0 && !ak.IsSwimming() && !ak.IsOnMount() && !ak.IsSneaking()
           ;  3a/3b: sleeping candidates excluded at SCAN (confirmed live 09-18 10:24 —
           ; Hroki seeded while sleeping; _IsBusyElsewhere's GetSitState only sees furniture
           ; sits, a bare-floor sleeper reads 0), plus the 3b state sweep: swimming / mounted /
           ; sneaking — states a hold would visibly break or read wrong. The WALK re-checks all
           ; four below (race window between scan and tick) with reason-coded sentinels.
            _DaemonPool[n] = ak
            n += 1
        EndIf
        i += 1
    EndWhile
    Return n
EndFunction

; Muse nudge loop (v1.2 redesign — docs/MUSE_REDESIGN_DESIGN.md, user-authoritative spec).
; Every ~30s (GSAnim.NudgeInterval, default fMuseNudgeIntervalSec;  key of record) ONE consideration call: pull context -> present the 27
; pose categories -> WEIGHTED TOWARD YES — pick the best-fitting pose unless ALL are unsuited
; (a miss is the EXCEPTION, not the goal). The YES-output is a JOB, not a flag: the call
; returns WHICH pose fits + the grounded in-world thought; OnMuseConsideration seeds it via
; GenerateNPCThought, and the pose fires through the NPC's OWN action selection (cue-not-floor
; stands — the thought is the nudge, the NPC's evaluation is the trigger).
; HARD GUARDS are ACTOR-LOCAL (user spec, scoping confirmed): the selected NPC not in combat /
; not mid-animation / not busy (the queued-actions floor is _IsBusyElsewhere — no framework
; pending-read exists), checked here at selection AND again at seed time in the callback.
;  user ruling (b): the muse additionally SUSPENDS while the PLAYER is in combat —
; gate at the top of the tick (early return, global stamp not spent) + re-check at seed
; time in the callback; NPC-combat stays covered by the actor-local IsInCombat guards.
; The 15s poll re-register stays (the arbiter line is untouched); the interval clock inside
; gates the actual calls, so between nudges a tick is one timestamp compare.
; Phase 4c rider (unchanged): while the one-shot debug window is open, every nudge outcome
; notifies; after it closes, silence with no ceremony.
Function _MuseTick()
    _EnsurePools()   ; Phase 4d: stale-instance heal BEFORE _DaemonScan (a None pool made .Length read 0 silently -> "scan empty" heartbeats forever, 15/15 in the 4c demo)
    ;  ruling (b): player combat suspends the muse — early return, the interval
    ; clock does NOT tick (stamp not spent, this tick is not counted), so nudges resume
    ; cleanly at the interval cadence once the fight ends. Unconditional reason-coded
    ; sentinel (NOT gated on bDebug) so the ON session log confirms suspend + resume.
    If PlayerRef.IsInCombat()
        Debug.Trace("[SNAnimGS] SanguineSuspend-PlayerCombat: tick skipped (player in combat)")
        Return
    EndIf
    Float fNow = Utility.GetCurrentRealTime()
    Bool bDebug = _MuseDebugWindowOpen(fNow)
    ;  1a: cross-session stamp clamp on read. Utility.GetCurrentRealTime() is
    ; BOOT-relative but StorageUtil stamps persist in saves, so a stamp written during a
    ; LONGER prior session (the 09-14 ask sat at ~1531s+menu; the 09-15 boot never got
    ; past ~720s+menu) reads as "just asked" and gates every tick of the next boot —
    ; mathematically shut all session. No stamp can legitimately exceed the current boot
    ; clock, so stamp > fNow is definitionally stale: treat it as 0 and persist the
    ; correction (one rewrite, then the store is clean for the rest of the boot).
    Float fLastGlobal = StorageUtil.GetFloatValue(None, "GSAnim.MuseGlobal", 0.0)
    If fLastGlobal > fNow
        Debug.Trace("[SNAnimGS] sanguine mode interval stamp clamped: stale cross-session stamp " \
            + fLastGlobal + " > boot clock " + fNow + " - treating as 0")
        fLastGlobal = 0.0
        StorageUtil.SetFloatValue(None, "GSAnim.MuseGlobal", 0.0)
    EndIf
    ;  1b rider: one unconditional trace on the FIRST gated tick of each boot with
    ; the actual compare values, so a silent-muse session diagnoses itself from one grep —
    ; no re-arm dance needed, the sentinel rides along every session from now on.
    ;  3.2: the interval OF RECORD is the StorageUtil key GSAnim.NudgeInterval
    ; (default = the compiled member). The member alone was being shadowed on long-lived
    ; saves by a pre- save-resident value of 100.0 (the deployed [] pex
    ; hash-matched its dist yet the 10-22 dogfood log printed 100.000000s) -- a fresh key
    ; carries no such residue, so the ruled 30s cadence finally takes effect. First-read
    ; sentinel per ruleset 5 rides the first-gate trace below.
    Float fInterval = StorageUtil.GetFloatValue(None, "GSAnim.NudgeInterval", fMuseNudgeIntervalSec)
    If !_bMuseGateLogged
        _bMuseGateLogged = True
        Debug.Trace("[SNAnimGS] sanguine mode gate (first check this boot): fNow=" + fNow \
            + " stamp=" + fLastGlobal + " delta=" + (fNow - fLastGlobal) \
            + " interval=" + fInterval + " (key of record GSAnim.NudgeInterval, default " \
            + fMuseNudgeIntervalSec + "s;  save-residue member retired)")
    EndIf
    If fNow - fLastGlobal < fInterval
        ;  3.2 full-chain receipt (user ruling 2026-10-22): the tick-opportunity
        ; sentinel is now UNCONDITIONAL, not bDebug-gated -- the cadence itself must be
        ; readable from the log on every session.
        Debug.Trace("[SNAnimGS] sanguine mode tick: no opportunity (interval clock " + (fNow - fLastGlobal) \
            + "s < " + fInterval + "s)")
        If bDebug
            _MuseDebugHeartbeat(fNow, "interval clock")
        EndIf
        Return
    EndIf
    Int n = _DaemonScan(True)   ;  3.1: policy-blanket scan; bAllowMales is vestigial (see _DaemonScan)
    If n == 0
        ;  3.2 full-chain receipt: the pool-empty refusal is named and unconditional.
        Debug.Trace("[SNAnimGS] sanguine mode attempt REFUSED: candidate pool EMPTY (scan n=0; policy mode " \
            + _GenderPolicy() + ")")
        If bDebug
            _MuseDebugHeartbeat(fNow, "scan empty")
        EndIf
        Return
    EndIf
    ; Actor-local guard walk in random order (the walk order spaces NPCs between nudges).
    Int iStart = Utility.RandomInt(0, n - 1)
    Int i = iStart
    While True
        Actor ak = _DaemonPool[i]
        If !ak.IsInCombat() && !_IsBusyElsewhere(ak)   ; ACTOR-LOCAL hard guards (v1.2)
            ;  Task 3a: sleeping-NPC guard on the candidate walk — mirrors the seated
            ; exclusion but for GetSleepState (the 09-18 10:24 Hroki case: seeded while
            ; sleeping; _IsBusyElsewhere's GetSitState never sees a bare-floor sleeper).
            ; 3b state sweep while here: swimming / mounted / sneaking are the same class —
            ; states a hold would visibly break or read wrong; each is one guard, clearly
            ; right. Reason-coded sentinels, unconditional per . The scan filter above
            ; makes these near-silent in steady state; they fire in the scan->tick race.
            If ak.GetSleepState() != 0
                Debug.Trace("[SNAnimGS] sanguine mode state skip: " + ak.GetDisplayName() + " sleeping (state " + ak.GetSleepState() + ") - excluded, mirrors the seated exclusion")
            ElseIf ak.IsSwimming()
                Debug.Trace("[SNAnimGS] sanguine mode state skip: " + ak.GetDisplayName() + " swimming - excluded")
            ElseIf ak.IsOnMount()
                Debug.Trace("[SNAnimGS] sanguine mode state skip: " + ak.GetDisplayName() + " mounted - excluded")
            ElseIf ak.IsSneaking()
                Debug.Trace("[SNAnimGS] sanguine mode state skip: " + ak.GetDisplayName() + " sneaking - excluded")
            Else
            ;  Task 1: per-NPC floor (fMusePerNpcSec). Read LastMuse with the same
            ; stale-stamp clamp as MuseGlobal above (boot-relative clock, save-persisted
            ; stamp): stamp > fNow is definitionally stale -> 0, persisted. Floored
            ; candidate -> skip, walk continues; all-floored falls out the "nobody
            ; eligible" lap exit, no call spent. Unconditional sentinel per ruleset 5.
            Float fLastNpc = StorageUtil.GetFloatValue(ak, "GSAnim.LastMuse", 0.0)
            If fLastNpc > fNow
                Debug.Trace("[SNAnimGS] sanguine mode npc floor stamp clamped: stale cross-session " \
                    + fLastNpc + " > boot clock " + fNow + " for " + ak.GetDisplayName() \
                    + " - treating as 0")
                fLastNpc = 0.0
                StorageUtil.SetFloatValue(ak, "GSAnim.LastMuse", 0.0)
            EndIf
            If fNow - fLastNpc >= fMusePerNpcSec
                _musePendingActor = ak
                Int sent = SkyrimNetApi.SendCustomPromptToLLM("gsanim_muse_consideration", "", \
                    _MusePackContext(ak, n), Self as Quest, "SkyrimNet_AnimationsGS", "OnMuseConsideration")
                ; Stamped at CALL time: bounds spend even if the response never lands (one lost
                ; tick at worst — the same discipline the old rc!=0 path had, now on the clock).
                StorageUtil.SetFloatValue(None, "GSAnim.MuseGlobal", fNow)
                If sent == 1
                    Debug.Trace("[SNAnimGS] sanguine mode candidate selected: " + ak.GetDisplayName() \
                        + " (first eligible in random walk, pool n=" + n + ", policy mode " + _GenderPolicy() + ")")
                    Debug.Trace("[SNAnimGS] sanguine mode nudge asked: " + ak.GetDisplayName())
                Else
                    _musePendingActor = None
                    Debug.Trace("[SNAnimGS] sanguine mode nudge not queued (rc=" + sent + "): " + ak.GetDisplayName())
                    If bDebug
                        _MuseDebugHeartbeat(fNow, "nudge rc=" + sent)
                    EndIf
                EndIf
                Return
            Else
                Debug.Trace("[SNAnimGS] sanguine mode npc floor skip: " + ak.GetDisplayName() \
                    + " (last seed " + (fNow - fLastNpc) + "s ago < " + fMusePerNpcSec + "s)")
                ; Papyrus has no Continue — fall through to the shared advance below
                ; (the guard If ends, the loop tail moves to the next candidate).
            EndIf
            EndIf   ;  3a/3b state-guard Else
        Else
            ;  rider sentinel ( registration,  3.1; unconditional per ):
            ; this skip was SILENT — seated (and every other busy) candidates entered
            ; _DaemonScan, were excluded by the walk guard, and never appeared in the log
            ; (gs-poses.md  .4: idle-dense pool composition was unmeasurable).
            ; Reason-coded, so the combat and busy legs stay distinguishable.
            If ak.IsInCombat()
                Debug.Trace("[SNAnimGS] sanguine mode walk skip: " + ak.GetDisplayName() + " in combat at walk time - excluded")
            Else
                ; : sentinel class-tagged — with _IsBusyElsewhere class-aware,
                ; only non-interruptible busy legs reach this branch (interruptible
                ; idle classes are admitted as candidates and routed at fire time).
                Debug.Trace("[SNAnimGS] sanguine mode walk skip: " + ak.GetDisplayName() + " busy at walk time - excluded (formerly SILENT skip;  class-aware, idleclass=" + _IdleClass(ak) + ")")
            EndIf
        EndIf   ;  busy/combat walk-guard Else
        i = (i + 1) % n
        If i == iStart
            If bDebug
                _MuseDebugHeartbeat(fNow, "nobody eligible")
            EndIf
            Return    ; full lap, nobody eligible — try again next tick
        EndIf
    EndWhile
EndFunction

; Context pack for the nudge call — surroundings + arousal + time, everything Papyrus can
; verify at build time. Verified UNAVAILABLE for the custom-prompt channel and therefore
; dropped gracefully (per the design doc): memories (no memory decorator exists in the
; framework inventory — get_relevant_memories is not a renderable function); recent
; conversation / event history (the components\event_history_verbose include resolves
; nowhere on disk, and its only shipper — the creature escalation gate — has never rendered
; live); emotions/mood (UUID-scoped decorators the contextJson channel cannot feed).
; The grounding requirement binds on what IS delivered: the prompt instructs the model to
; root the thought in exactly these fields.
String Function _MusePackContext(Actor ak, Int anPool)
    String sLoc = ""
    If ak.GetParentCell()
        sLoc = ak.GetParentCell().GetName()
    EndIf
    If sLoc == ""
        sLoc = "the wilds"
    EndIf
    ; Nearby roll-up: the OTHER scanned names (first 5 — the same set the scan vetted).
    String sNear = ""
    Int j = 0
    Int k = 0
    While j < anPool && k < 5
        Actor other = _DaemonPool[j]
        If other && other != ak
            If k > 0
                sNear = sNear + ", "
            EndIf
            sNear = sNear + other.GetDisplayName()
            k += 1
        EndIf
        j += 1
    EndWhile
    If sNear == ""
        sNear = "nobody else in particular"
    EndIf
    ; Arousal ( aroused-lean leg 1, posing-gender.md ): the  tiering
    ; chain replaces the OStim-only read (which rendered "unknown" outside OStim
    ; scenes, leaving the muse arousal-blind — the bland-picks root cause). Primary
    ; Reborn GetArousalNoSideEffects gated on the plugin (side-effect-free at fire
    ; time by design), fallback sla_FrameworkScr.GetActorArousal, neutral "unknown".
    ; OStim excitement, when present, is MORE precise than the 0-100 tier — keep it
    ; as the first branch. Self-keyed: the candidate NPC's own arousal.
    String sArous = "unknown"
    If !_bMuseArousalResolved
        _kMuseArousalFaction = PO3_SKSEFunctions.GetFormFromEditorID("OStimExcitementFaction") as Faction
        _bMuseArousalResolved = True
    EndIf
    If _kMuseArousalFaction && ak.IsInFaction(_kMuseArousalFaction)
        sArous = "excitement rank " + ak.GetFactionRank(_kMuseArousalFaction)
    ElseIf SKSE.GetPluginVersion("OSLAroused") > 0
        Float fArous = OSLArousedNative.GetArousalNoSideEffects(ak)
        If fArous >= 75.0
            sArous = "high (arousal " + (fArous as Int) + ")"
        ElseIf fArous > 25.0
            sArous = "stirring (arousal " + (fArous as Int) + ")"
        Else
            sArous = "low (arousal " + (fArous as Int) + ")"
        EndIf
    Else
        slaFrameworkScr kNG = Quest.GetQuest("sla_Framework") as slaFrameworkScr
        If kNG
            Int iArous = kNG.GetActorArousal(ak)
            If iArous >= 75
                sArous = "high (arousal " + iArous + ")"
            ElseIf iArous > 25
                sArous = "stirring (arousal " + iArous + ")"
            Else
                sArous = "low (arousal " + iArous + ")"
            EndIf
        EndIf
    EndIf
    ; Time-of-day register from the game clock (Papyrus % is int-only — cast first).
    Int iHour = (Utility.GetCurrentGameTime() * 24.0) as Int % 24
    String sTod = "midday"
    If iHour < 5 || iHour >= 21
        sTod = "deep night"
    ElseIf iHour < 8
        sTod = "early morning"
    ElseIf iHour >= 17
        sTod = "evening"
    EndIf
    String sRace = ""
    If ak.GetLeveledActorBase() && ak.GetLeveledActorBase().GetRace()
        sRace = ak.GetLeveledActorBase().GetRace().GetName()
    EndIf
    ;  Task 2: npcName fallback chain. The 09-16 session produced one render with an
    ; EMPTY "## The NPC" header (17:54:40, Papyrus confirmed the pending actor was Frabbi) —
    ; GetDisplayName() can transiently return "" (name API edge). Fallback: display name ->
    ; actor base name -> race+role descriptor; an empty name still renders the header text
    ; itself, so the worst case is a descriptive label, never a blank. Unconditional
    ; sentinel per ruleset 5 (fires only when the fallback engaged).
    ;  Task 1c: sex field for the prompt's split guidance — the LLM must know it is
    ; picking for a man or a woman (the library line carries the male-safe half). Same
    ; _SexOf source as every gate (leveled-safe, 6a). Computed BEFORE the fallback chain
    ; so the race+role descriptor is gender-aware too ().
    String sSex = "woman"
    If _SexOf(ak) == 0
        sSex = "man"
    EndIf
    String sName = ak.GetDisplayName()
    If sName == ""
        If ak.GetLeveledActorBase()
            sName = ak.GetLeveledActorBase().GetName()
        EndIf
        If sName == ""
            If sRace != ""
                sName = "a " + sRace + " " + sSex
            Else
                sName = "a " + sSex + " nearby"
            EndIf
        EndIf
        Debug.Trace("[SNAnimGS] sanguine mode npcName fallback engaged: race=\"" + sRace \
            + "\" resolved=\"" + sName + "\" for actor " + ak)
    EndIf
    ;  aroused-lean: stash the tier for the fire-time [arousal lean] sentinel
    ; (single-in-flight member — cleared by the next pack, harmless when stale).
    _sMuseArous = sArous
    ;  Phase B: two new context fields for the prompt's Jinja gates. posePolicy:
    ; the scene's gender policy mode (female-only / curated / all-poses) — the male-safe
    ; split text and the all-poses override both key on it. arousalTier: the bare tier
    ; word (high/stirring/low) for the arousal-scoped preference weighting; "unknown"
    ; renders no weighting line (silence about the unknown).
    String sTier = "unknown"
    If StringUtil.Find(sArous, "high") != -1
        sTier = "high"
    ElseIf StringUtil.Find(sArous, "stirring") != -1
        sTier = "stirring"
    ElseIf StringUtil.Find(sArous, "low") != -1
        sTier = "low"
    ElseIf StringUtil.Find(sArous, "excitement") != -1
        sTier = "high"    ; an OStim scene IS the aroused context
    EndIf
    String sPolicy = "female-only"
    If _GenderPolicy() == 1
        sPolicy = "curated"
    ElseIf _GenderPolicy() == 2
        sPolicy = "all-poses"
    EndIf
    ;  (picker decommission): the itemized pose catalog rides the SAME
    ; consideration call -- warning + description + move list per category
    ; (_MusePoseCatalogText), so the model that already holds the full scene
    ; context also picks the exact move. Text carries no quotes/backslashes;
    ; line separators are JSON-escaped newlines, decoded at render.
    String sCatalog = _MusePoseCatalogText()
    Return "{\"npcName\":\"" + sName + "\",\"npcRace\":\"" + sRace \
        + "\",\"npcSex\":\"" + sSex \
        + "\",\"location\":\"" + sLoc + "\",\"nearby\":\"" + sNear \
        + "\",\"arousal\":\"" + sArous \
        + "\",\"arousalTier\":\"" + sTier + "\",\"posePolicy\":\"" + sPolicy \
        + "\",\"timeOfDay\":\"" + sTod \
        + "\",\"poseCatalog\":\"" + sCatalog + "\"" \
        + ",\"maxRecentEvents\":12}"
EndFunction

;  Task 1a (user ruling, approved split): MALE-OK vibe set — vibe-level split. The
; single _PoseVibe gender gate serves four callers (muse fire, T3, crosshair via its own
; validation, grid via _PoseDirect), so the vibe-level companion table is the small change:
; _PoseVibe now admits males ONLY for vibes in this set; the crosshair path is untouched
; (ruling: male refusal STAYS at the crosshair — the muse alone gains males) and T3 keeps
; female-only candidates (scan default), so no T3 behavior change.
;  (dogfood closure, curated-12 ruling): Plead joins the male-ok set — the begging
; register reads on any body (distress, not sensuality), closing the "curated no better
; than female-only" crosshair finding together with the sCat fix at the validation leg.
; Male-ok (12): the 8 approved neutrals (Stretch, Workout, Drink, ScratchHead, BraceArm,
; Meditate, HandOnChin, HandOnFace) + Dance (celebration register is genderless — the male
; vocabulary must express joy, user ruling) + Aroused (Baka's own BaboArousedMale01/02
; clips = authored male support) + GroundIdle (FULL 18-event pool, graded live — the two
; "(M ok)" poses.js events are known-good; the jank watch is the gate, narrow if needed)
; + Plead (, curated-12).
; Female-only (7): Seduce, SelfTouch, Present, DanceSexy, GroundSexy, Submission, Drool —
; the sensual set stays single-register by the settled principle.
Bool Function _VibeMaleOK(String vibe)
    If vibe == "stretch" || vibe == "workout" || vibe == "drink" \
       || vibe == "scratchhead" || vibe == "bracearm" || vibe == "meditate" \
       || vibe == "handonchin" || vibe == "handonface" \
       || vibe == "dance" || vibe == "aroused" || vibe == "ground_idle" \
       || vibe == "plead"
        Return True
    EndIf
    Return False
EndFunction

;  direct-fire allowlist (user-approved 09-16, docs/MUSE_DIRECT_FIRE_DESIGN.md +
; approval amendment): the muse's own SOLO-SAFE, VISIBLE picks only, mapped to _VibeCSV
; vibes for dispatch through _PoseVibe — the same GS hold machinery as the player path
; and T3 (GSAnim.Pose/Posing/Start/Timeout/Vibe keys, restrain, 3s sweep), so the grid
; Stop Pose button and the pose timeouts cover a muse-fired hold identically: no new
; hold machinery, no parallel stop path. PoseIdle is EXCLUDED by the approval amendment —
; still selectable and seedable as today (the seed text lands; the LLM's own action
; pipeline can still fire it, cue-not-floor), only the muse's DIRECT execution is
; excluded: a PoseIdle execution is an invisible state change (GSAnim.Pose set,
; DaemonScan exclusion, hold cleanup) with no visible payoff. Chin/Face/Aroused are
; single-actor Babo idle events under GS bookkeeping — never a Baka action call, never
; a two-actor path. Returns the vibe name, "" = seed-only (today's exact behavior).
String Function _MuseFireVibe(String sPose)
    If sPose == "PoseSeduce"
        Return "seduce"
    ElseIf sPose == "PoseDance"
        Return "dance"
    ElseIf sPose == "PoseDanceSexy"
        Return "dance_sexy"
    ElseIf sPose == "PoseHandOnChin"
        Return "handonchin"
    ElseIf sPose == "PoseHandOnFace"
        Return "handonface"
    ElseIf sPose == "PoseAroused"
        Return "aroused"
    ;  Task 3 (approved tiers): Tier 1 — Stretch/Workout reuse their existing GS CSV
    ; vibes (_VibeCSV "stretch"/"workout", same event pools as the grid + T3 pool; already
    ; stop-pose-compatible via the GS key set); ScratchHead/BraceArm/Meditate are the new
    ; single-actor Babo idle-event branches added to _VibeCSV this rev. Tier 2 — Drink: the
    ; NORMAL hold only (BaboDrinkNormal; the blackout branch + baka_opportunity remain
    ; Baka's exclusive path — see _VibeCSV's  block). Tier 3 was REJECTED by user
    ; ruling (Food/Sleep/Autograph/Pickpocket/Crouch/Drool/Kneel/Dogeza stay seed-only).
    ElseIf sPose == "PoseStretch"
        Return "stretch"
    ElseIf sPose == "PoseWorkout"
        Return "workout"
    ElseIf sPose == "PoseScratchHead"
        Return "scratchhead"
    ElseIf sPose == "PoseBraceArm"
        Return "bracearm"
    ElseIf sPose == "PoseMeditate"
        Return "meditate"
    ElseIf sPose == "PoseDrink"
        Return "drink"
    ;  Task 2a (user spec): VOCABULARY = FIREABLE SET — the prompt library and the fire
    ; allowlist are now ONE list; every muse decision ends in visible action. Dropped entirely
    ; from the muse vocabulary (still in the crosshair grid, unreachable by the muse): PoseIdle
    ; (no-op fire) and the hazard set (Food, Sleep, Autograph, Pickpocket, Crouch, Kneel,
    ; Dogeza). The seven entries below complete the vocabulary from poses that were previously
    ; seed-only: all reuse EXISTING GS CSV vibes (selftouch/present/ground_sexy/ground_idle/
    ; submission/plead — same event pools as the crosshair grid + T3), single-actor, no props.
    ; Drool (2c evaluation, user advocacy): BaboDroolingFace — see the _VibeCSV  block.
    ; PoseSubmission keeps its _PoseVibe AI-lock (a surrender hold) — deliberate: the grid
    ; fires it identically.
    ElseIf sPose == "PoseSelfTouch"
        Return "selftouch"
    ElseIf sPose == "PosePresent"
        Return "present"
    ElseIf sPose == "PoseGroundSexy"
        Return "ground_sexy"
    ElseIf sPose == "PoseGroundIdle"
        Return "ground_idle"
    ElseIf sPose == "PoseSubmission"
        Return "submission"
    ElseIf sPose == "PosePlead"
        Return "plead"
    ElseIf sPose == "PoseDrool"
        Return "drool"
    EndIf
    Return ""
EndFunction

;  4.4 (register entry 29, user's 2026-10-24 edit pass - pending text of
; record): the three REWORDED per-pose variants ship as FULL-SENTENCE event
; descs on the vibe route (the registered texts carry "<NPC>" inline - they
; are desc lines, not slot-in labels, so the "strikes <label>." frame does
; not fit them; every other vibe keeps the  Task 3.1 frame). The
; noun-phrase labels stay in GSAnim.Vibe / _MuseFireLabel so the shared
; STOP wording ("relaxes out of <label>.") stays grammatical - the variant
; replaces only the gsanim_npc_pose EVENT TEXT on this route.
String Function _PoseVibeDesc(String sVibe, String sLabel)
    If sVibe == "selftouch"
        Return " trails a slow line along their own skin - provocative and sensual."
    ElseIf sVibe == "ground_sexy"
        Return " stretches out along the ground in a wanton and obscene display of arousal."
    ElseIf sVibe == "present"
        Return " holds a presenting pose - deliberately trying to entice."
    EndIf
    Return " strikes " + sLabel + "."
EndFunction

; : event/stop-wording label for a direct-fired pose. The three GS-vibe picks reuse
; the exact distilled one-liners their Pose*_Execute wrappers already ship (an approved
; string class, Phase 4); the three Babo-event picks carry new one-liners in the same
; register (flagged for user text approval in the  build report, ruleset ).
String Function _MuseFireLabel(String sPose)
    If sPose == "PoseSeduce"
        Return "a seductive pose - weight on one hip, gaze holding the room"
    ElseIf sPose == "PoseDance"
        Return "a light, playful dance - feet answering the music"
    ElseIf sPose == "PoseDanceSexy"
        Return "a slow, provocative dance - a performance with a single intended victim"
    ElseIf sPose == "PoseHandOnChin"
        Return "a thoughtful pose - a hand resting on her chin"
    ElseIf sPose == "PoseHandOnFace"
        Return "a hand brought to her face, something to hold in"
    ElseIf sPose == "PoseAroused"
        Return "a restless, heated shift of weight - arousal worn openly"
    ;  Task 3: fire labels for the approved tiers. Stretch/Workout reuse their
    ; Pose*_Execute one-liner register; the four Babo-idle picks + Drink carry new lines
    ; in the same register (presented for retro-approval per ruleset ). Drink's wording
    ; deliberately claims only what BaboDrinkNormal does: a drink, never a stupor.
    ElseIf sPose == "PoseStretch"
        Return "a long, unhurried stretch - arms overhead, back arching"
    ElseIf sPose == "PoseWorkout"
        Return "a quick workout drill - keeping the body busy"
    ElseIf sPose == "PoseScratchHead"
        Return "a scratch at her head, faintly unsure of something"
    ElseIf sPose == "PoseBraceArm"
        Return "an arm braced, weight settling, tension held"
    ElseIf sPose == "PoseMeditate"
        Return "a quiet meditative seat - eyes closed, breath slowing"
    ElseIf sPose == "PoseDrink"
        Return "a slow pull from a tankard, throat working"
    ;  Task 2a/2c labels (retro-approval per , same register). Submission deliberately
    ; claims only the pose; Drool carries the user's "reduced to it" frame in-world.
    ElseIf sPose == "PoseSelfTouch"
        Return "a slow trail of her own fingers - touch with nowhere else to go"
    ElseIf sPose == "PosePresent"
        Return "a presenting pose - offered up, deliberately on display"
    ElseIf sPose == "PoseGroundSexy"
        Return "a stretch out along the ground - slow, and inviting about it"
    ElseIf sPose == "PoseGroundIdle"
        Return "a slide down to the floor - resting right where she stood"
    ElseIf sPose == "PoseSubmission"
        Return "a surrender pose - hands open, will set aside"
    ElseIf sPose == "PosePlead"
        Return "a pleading pose - hands clasped, eyes begging"
    ElseIf sPose == "PoseDrool"
        Return "a dazed stare, mouth gone slack - somewhere past words"
    EndIf
    Return "a pose"
EndFunction

; SendCustomPromptToLLM callback for the muse nudge (gsanim_muse_consideration.prompt).
; success 1 = real answer; 0 = render/network failure -> treated as MISS (no seed, logged).
; Output contract (): "POSE: <name> | CLIP: <move key> | THOUGHT: <one-sentence
; grounded in-world thought>" (CLIP optional — single-move / near-identical picks),
; "POSE: <name> | THOUGHT: <line>", or "MISS". Guards are RE-CHECKED here (seed
; time) — the moment between ask and answer can
; change everything; a failed guard is a dropped nudge, never a seed.
Function OnMuseConsideration(String response, Int success)
    Actor ak = _musePendingActor
    _musePendingActor = None
    Float fNow = Utility.GetCurrentRealTime()
    Bool bDebug = _MuseDebugWindowOpen(fNow)
    If !ak || ak.IsDead() || ak.IsInCombat() || _IsBusyElsewhere(ak)
        If ak
            Debug.Trace("[SNAnimGS] sanguine mode nudge dropped - actor-local guard failed at seed time: " + ak.GetDisplayName())
        Else
            Debug.Trace("[SNAnimGS] sanguine mode nudge dropped - pending actor vanished at seed time")
        EndIf
        If bDebug
            _MuseDebugHeartbeat(fNow, "guard failed at seed")
        EndIf
        Return
    EndIf
    ;  ruling (b) re-check: combat that began during the in-flight consideration —
    ; drop to no-op, no seed, no LastMuse stamp. Reason-coded sentinel, unconditional.
    If PlayerRef.IsInCombat()
        Debug.Trace("[SNAnimGS] SanguineSuspend-PlayerCombat: nudge dropped at seed time (player in combat): " + ak.GetDisplayName())
        Return
    EndIf
    If success != 1 || response == ""
        Debug.Trace("[SNAnimGS] sanguine mode nudge miss (success=" + success + "): " + ak.GetDisplayName())
        If bDebug
            _MuseDebugHeartbeat(fNow, "nudge success=" + success)
        EndIf
        Return
    EndIf
    ; Marker parse, whitespace-tolerant ( contract):
    ;   "POSE: <name> | CLIP: <move key> | THOUGHT: <line>"
    ;   "POSE: <name> | THOUGHT: <line>"  (single-move / near-identical picks, or a dropped CLIP)
    ;   "MISS"
    Int iPose = StringUtil.Find(response, "POSE:")
    Int iThought = StringUtil.Find(response, "| THOUGHT:")
    If iPose < 0 || iThought < 0 || iThought <= iPose
        Debug.Trace("[SNAnimGS] sanguine mode nudge miss (parse): " + ak.GetDisplayName() + " - " + response)
        If bDebug
            _MuseDebugHeartbeat(fNow, "miss (parse)")
        EndIf
        Return
    EndIf
    ;  (picker decommission): the CLIP field -- the exact move within
    ; the picked category, picked by the consideration model itself from the
    ; poseCatalog in its own context pack. Optional: single-move picks and the
    ; near-identical aroused pair carry no CLIP, and a dropped CLIP merely
    ; degrades to the pool's random draw (sentinel at fire time, never a miss).
    Int iClipMark = StringUtil.Find(response, "| CLIP:")
    String sClip = ""
    If iClipMark > iPose && iClipMark < iThought
        sClip = StringUtil.Substring(response, iClipMark + 7, iThought - iClipMark - 7)
        If StringUtil.GetNthChar(sClip, 0) == " "
            sClip = StringUtil.Substring(sClip, 1, StringUtil.GetLength(sClip) - 1)
        EndIf
        While StringUtil.GetLength(sClip) > 0 \
           && StringUtil.GetNthChar(sClip, StringUtil.GetLength(sClip) - 1) == " "
            sClip = StringUtil.Substring(sClip, 0, StringUtil.GetLength(sClip) - 1)
        EndWhile
    EndIf
    String sPose = ""
    If iClipMark > iPose && iClipMark < iThought
        sPose = StringUtil.Substring(response, iPose + 5, iClipMark - iPose - 5)
    Else
        sPose = StringUtil.Substring(response, iPose + 5, iThought - iPose - 5)
    EndIf
    Int iBar = StringUtil.Find(sPose, "|")
    If iBar >= 0
        sPose = StringUtil.Substring(sPose, 0, iBar)
    EndIf
    If StringUtil.GetNthChar(sPose, 0) == " "
        sPose = StringUtil.Substring(sPose, 1, StringUtil.GetLength(sPose) - 1)
    EndIf
    ;  bug fix ( defect): the LLM's POSE answer carries a TRAILING space
    ; ("PoseAroused ") — the leading-only trim above left it on, so the exact-match
    ; allowlist in _MuseFireVibe never hit and every fire degraded to seed-only with
    ; "not allowlisted" (first live evidence 09-17 08:29:28: PoseAroused skipped while
    ; allowlisted). Trim the tail the same way as the head.
    While StringUtil.GetLength(sPose) > 0 \
       && StringUtil.GetNthChar(sPose, StringUtil.GetLength(sPose) - 1) == " "
        sPose = StringUtil.Substring(sPose, 0, StringUtil.GetLength(sPose) - 1)
    EndWhile
    String sThought = StringUtil.Substring(response, iThought + 10, 700)
    If StringUtil.GetNthChar(sThought, 0) == " "
        sThought = StringUtil.Substring(sThought, 1, StringUtil.GetLength(sThought) - 1)
    EndIf
    If sPose == "" || sThought == ""
        Debug.Trace("[SNAnimGS] sanguine mode nudge miss (empty fields): " + ak.GetDisplayName())
        If bDebug
            _MuseDebugHeartbeat(fNow, "miss (empty fields)")
        EndIf
        Return
    EndIf
    Int rc = SkyrimNetApi.GenerateNPCThought(ak, sThought)
    If rc == 0
        ; : LastMuse is now READ (per-NPC floor, fMusePerNpcSec — the clamp lives at
        ; the read site in _MuseTick, same pattern as MuseGlobal). This write stamps the
        ; LANDED seed; stale cross-session values are cleaned at read time.
        StorageUtil.SetFloatValue(ak, "GSAnim.LastMuse", fNow)
        ; 's seed-time on-screen notification is MOVED ( Task 2e, user spec):
        ; on-screen notification fires ONLY on actual pose fires now — the fire branch
        ; below carries the paired message+pose notification; seed-only outcomes exist
        ; only in trace logs. The unconditional seed TRACE stays (screen and logs were
        ; parallel before; now the trace alone carries seed-only outcomes).
        String sLine = "Sanguine Mode: nudge -> " + ak.GetDisplayName() + " (" + sPose + ")"
        Debug.Trace("[SNAnimGS] " + sLine + " - thought: " + sThought)
        If bDebug
            Debug.Notification(sLine)
        EndIf
        ; ── : direct fire of the muse's own solo-safe pick (user-approved design,
        ; docs/MUSE_DIRECT_FIRE_DESIGN.md + approval amendment). A pure rider on the
        ; LANDED seed above: the thought already landed and stamped LastMuse (one write,
        ; both meanings — the  floor now spaces fires too). Guards re-checked at
        ; fire time: overdrive preemption (the arbiter's ElseIf discipline — an in-flight
        ; consideration can return after overdrive turned ON; overdrive wins) and busy
        ; (the moment between ask and answer). _PoseVibe re-runs its own female/busy
        ; guards live, defense in depth. Any miss -> seed-only, exactly today's behavior.
        ; Cue-not-floor is preserved everywhere EXCEPT this sanctioned path (user ruling
        ; 09-16): T1 cues, the T3 silence floor and NPC self-selection are untouched.
        ; Sentinels unconditional (ruleset ): fire + skip-with-reason, skip-reason
        ; distribution is the  headline funnel metric.
        String sFireVibe = _MuseFireVibe(sPose)
        If sFireVibe == ""
            Debug.Trace("[SNAnimGS] sanguine mode direct fire skipped: not allowlisted (" + sPose + ") - seed-only")
        ElseIf !_GenderAdmits(ak, sFireVibe)
            ;  Phase B: the fire-time veto is now policy-mode-aware (was the 
            ; flat male veto) — mode 0/1 constrain picks exactly as the prompt's split
            ; guidance does (mode 1: male picks to the male-ok table; mode 0: males out
            ; entirely); mode 2 admits everyone. _PoseVibe re-runs the gate live as the
            ; third layer. Sentinel per  so the veto rate stays measurable.
            Debug.Trace("[SNAnimGS] sanguine mode direct fire skipped: gender policy veto (" + sPose + " not admitted, mode " + _GenderPolicy() + ") - seed-only")
        ElseIf StorageUtil.GetIntValue(None, "GSAnim.Overdrive", 0) == 1
            Debug.Trace("[SNAnimGS] sanguine mode direct fire skipped: sheogorath mode running - seed-only")
        ElseIf _IsBusyElsewhere(ak)
            Debug.Trace("[SNAnimGS] sanguine mode direct fire skipped: busy at fire time - seed-only")
        Else
            ;  (picker decommission): the consideration answer's CLIP
            ; fires through the exact-pick plumbing (sForceEvent -- the proven
            ;  machinery, minus the decision call). Validation here +
            ; the _PoseVibe pool guard (defense in depth). An absent/invalid
            ; CLIP degrades to the pool's random draw, sentinel'd -- the only
            ; random lanes left are Sheogorath/T3, degenerate pools, and this
            ; ruled fallback.
            String sForceEvent = ""
            If sClip != ""
                String csvMuse = _VibeEventsFor(ak, sFireVibe)
                If StringUtil.Find("," + csvMuse + ",", "," + sClip + ",") != -1
                    sForceEvent = sClip
                    Debug.Trace("[SNAnimGS] sanguine mode direct fire: LLM move pick '" + sClip + "' (cat '" + sFireVibe + "')")
                Else
                    Debug.Trace("[SNAnimGS] sanguine mode direct fire: LLM move pick '" + sClip + "' NOT in pool '" + sFireVibe + "' - degrading to random draw")
                EndIf
            Else
                Debug.Trace("[SNAnimGS] sanguine mode direct fire: no CLIP in answer - random draw (single-move or near-identical category, or a dropped field)")
            EndIf
            If _PoseVibe(ak, sFireVibe, _MuseFireLabel(sPose), sForceEvent, 1)
                ;  2.3 (outcome-true,  finding 2.3): the fire sentinel
                ; fires ONLY on a True return from _PoseVibe (event actually sent).
                ; The success bookkeeping (_MuseFireSuccess) carries the exact
                ; sentinels, notification and interval re-arm on every fire path.
                _MuseFireSuccess(ak, sPose, fNow)
            Else
                Debug.Trace("[SNAnimGS] sanguine mode direct fire REFUSED (no event sent): " + ak.GetDisplayName() + " (" + sPose + ") -- reason per the refusal sentinel above")
            EndIf
        EndIf
    Else
        Debug.Trace("[SNAnimGS] sanguine mode nudge seed skipped (rc=" + rc + "): " + ak.GetDisplayName())
        If bDebug
            _MuseDebugHeartbeat(fNow, "seed rc=" + rc)
        EndIf
    EndIf
EndFunction

;  1c rider: shared "is the muse debug window open" read with a cross-boot clamp.
; MuseDebugEnd is an absolute BOOT-relative timestamp persisted in saves — a mid-window
; save loaded in a LATER boot would otherwise read as "window still open" for that boot's
; first minutes (the same residue class the 1a interval clamp fixes). No arm this boot can
; legitimately place the end-stamp more than fMuseDebugWindow ahead of the clock, so any
; end-stamp beyond that horizon is definitionally stale — treat the window as closed. The
; MuseDebugDone marker is left as-is (informational only; the per-boot arm uses its own
; in-memory flag).
Bool Function _MuseDebugWindowOpen(Float afNow)
    Float fEnd = StorageUtil.GetFloatValue(None, "GSAnim.MuseDebugEnd", 0.0)
    If fEnd > afNow + fMuseDebugWindow
        Return False
    EndIf
    Return StorageUtil.GetIntValue(None, "GSAnim.MuseDebugDone", 0) == 1 && afNow < fEnd
EndFunction

; ── Phase 4c rider helpers: one-shot muse debug window output ───────────────
; Rate-limited (~1/30s) "still stirring" beat for every no-seed exit while the window is
; open. The reason rides along in the trace only — the on-screen message stays the exact
; spec'd line so the demo session reads as one steady pulse, not a status dump. The
; rate clock is a member var: diagnostic-only precision, window BOUNDS are the persisted
; part (see the state block up top).
Function _MuseDebugHeartbeat(Float afNow, String asWhy)
    If afNow - _fMuseDebugBeat < 30.0
        Return
    EndIf
    _fMuseDebugBeat = afNow
    Debug.Notification("Sanguine Mode: stirring (no nudge this cycle)")
    Debug.Trace("[SNAnimGS] sanguine mode heartbeat (no nudge this cycle): " + asWhy)
EndFunction

; ── Phase 4d rider: muse debug window re-arm (the manual override) ─────────────────
; The 4c window is one-shot BY DESIGN (marker never cleared; a new game re-arms), and
; no console path reaches a StorageUtil key (verified back in 4b — vanilla console
; can't address one and MCP needs a public function to call). Since Phase 4e the
; re-test re-arm is AUTOMATIC (the one-shot GSAnim.ReArm4e migration in _EnsurePools),
; so THIS public function is a convenience override, no longer a protocol requirement
; — still callable from the SkyrimNet MCP dashboard via the execute_quest_function:
;   quest_editor_id = "SkyrimNet_AnimationsGS"   script_name = "SkyrimNet_AnimationsGS"
;   function_name   = "ReArmMuseDebug"           arguments   = []
; Clears marker + end-stamp together, so the next MUSE_TOGGLE ON re-arms a fresh
; 10-minute window exactly as a new game would. Harmless when the window was never
; consumed (the keys simply re-zero) and harmless mid-window (re-arms from the NEXT
; activation only).
Function ReArmMuseDebug()
    StorageUtil.SetIntValue(None, "GSAnim.MuseDebugDone", 0)
    StorageUtil.SetFloatValue(None, "GSAnim.MuseDebugEnd", 0.0)
    Debug.Notification("Sanguine Mode debug window re-armed (next activation).")
    Debug.Trace("[SNAnimGS] sanguine mode debug window re-armed via ReArmMuseDebug().")
EndFunction

; ──  S3: Baka-half presence probe ─────────────────────────────────────
; The 15 Baka-hosted pose executors (indices 12-26 of _PoseActions) live in the Baka
; integration's quest script; on a Baka-absent install those action names resolve to
; nothing and every SkyrimNetApi call naming one is a wasted call plus a not-found
; line. The Baka motherboard advertises its halves through the service registry
; (SNBaka.Svc.* keys on its own quest form, QUST 0xD62 of SkyrimNet_BakaIntegration.esp,
;  shape); the GS probe here is the soft-read mirror of the motherboard's own
; log-only GS presence probe (_ArmModules). Soft read, same class as the SNBaka.Locked /
; OnGround busy keys this script already reads: StorageUtil returns the default (0) when
; the host form or key is absent - no error, no hard dependency. Deliberately NOT cached:
; the arm pass re-asserts the registry entry on the motherboard heartbeat, so a mid-
; session change reads correctly at the next guard evaluation.
Bool Function _BakaPoseHalfPresent()
    Form kHost = Game.GetFormFromFile(0xD62, "SkyrimNet_BakaIntegration.esp")
    If !kHost
        Return False
    EndIf
    Return StorageUtil.GetIntValue(kHost, "SNBaka.Svc.pose.baka-half", 0) == 1
EndFunction

;  S2: the busy-state service probe — the same soft-read mirror as
; _BakaPoseHalfPresent above, on the "busy.baka-half" registry entry. The Baka
; motherboard owns the SNBaka.Locked/OnGround writers; absent module = absent
; registry entry = probe returns False = _IsBusyElsewhere skips those reads
; (their soft default of 0, made explicit — era doc 5.2 S2: key names are the
; wire format; this is the contract over the soft reads, not a new interface).
; Deliberately NOT cached, same reason as the pose probe: the arm pass
; re-asserts the entry on the motherboard heartbeat, so a mid-session change
; reads correctly at the next guard evaluation.
Bool Function _BakaBusyServicePresent()
    Form kHost = Game.GetFormFromFile(0xD62, "SkyrimNet_BakaIntegration.esp")
    If !kHost
        Return False
    EndIf
    Return StorageUtil.GetIntValue(kHost, "SNBaka.Svc.busy.baka-half", 0) == 1
EndFunction

;  S2 one-shot sentinels (the _bMuseDebugArmedThisBoot pattern): the busy
; queries are hot-path (daemon scans), so the "consulted" (probe state) and
; "result" (first busy-block via a Baka key) sentinels fire ONCE per game load —
; both observable in the Papyrus log without spam. The Baka-side counterpart is
; the registry's own arm-pass log line ("service-registry: 'busy.baka-half'").
Bool _bBusySvcProbeSentinel  = False
Bool _bBusySvcBlockSentinel = False

;  S3: the 15 Baka-hosted names of the 27-name dispatch (_PoseActions = 12
; GS-owned + 15 Baka-described). Exact-match list, not an index range, so the table
; stays reviewable against _PoseActions and the Gunslicer-Poses pack manifest (the
; GS-owned 12). The muse fire path needs NO guard (its vibes fire GS-bookkept Babo
; idle events, never a Baka action call) and T3 needs none (_OdVibeNames is GS-only
; by construction) - the T2 cooldown loops are the dispatch's only hard name-set.
Bool Function _IsBakaHostedPose(String sAction)
    Return sAction == "PoseAroused" || sAction == "PoseAutograph" \
        || sAction == "PoseBraceArm" || sAction == "PoseCrouch" \
        || sAction == "PoseDogeza" || sAction == "PoseDrink" \
        || sAction == "PoseDrool" || sAction == "PoseFood" \
        || sAction == "PoseHandOnChin" || sAction == "PoseHandOnFace" \
        || sAction == "PoseKneel" || sAction == "PoseMeditate" \
        || sAction == "PosePickpocket" || sAction == "PoseSleep" \
        || sAction == "PoseScratchHead"
EndFunction

; Performance Mode ON: flag up, T2 cooldowns set to the iOdCooldownFloor (Fix B/4f — the
; old 0-floor let the LLM chain poses back-to-back, live spam confirmed), expiry stamped, T3
; silence-floor clock stamped (an ON immediately after a quiet stretch must not instantly
; auto-fire), first T1 cue immediate, loop re-armed at the 10s overdrive interval.
Function _OverdriveOn()
    _EnsurePools()   ; Phase 4d: stale-instance heal — the T2 loop reads _PoseActions and _OdCue reads _OdCues
    StorageUtil.SetIntValue(None, "GSAnim.Overdrive", 1)
    Int i = 0
    Int iSkipped = 0
    Bool bBakaHalf = _BakaPoseHalfPresent()   ;  S3: one probe per pass, not per name
    While i < _PoseActions.Length
        If bBakaHalf || !_IsBakaHostedPose(_PoseActions[i])
            SkyrimNetApi.SetActionCooldown(_PoseActions[i], iOdCooldownFloor)
        Else
            iSkipped += 1   ; guarded skip - Baka half absent
        EndIf
        i += 1
    EndWhile
    If iSkipped > 0
        Debug.Trace("[SNAnimGS] sheogorath mode T2 floor: " + iSkipped + " Baka-hosted pose cooldowns skipped - Baka half absent (REV-103 S3 guard)")
    EndIf
    StorageUtil.SetFloatValue(None, "GSAnim.OverdriveExpire", Utility.GetCurrentRealTime() + fOdExpireSeconds)
    StorageUtil.SetFloatValue(None, "GSAnim.LastPoseFire", Utility.GetCurrentRealTime())  ; observability only since  3.3 (silence-floor reader retired)
    StorageUtil.SetFloatValue(None, "GSAnim.LastOdCue", 0.0)
    ;  3.2 ->  3.3 receipt: the ON state, its armed cadence parameters
    ; and the policy mode are trace-receipted. Census of the armed machinery
    ; (): poll 15s, T3 every-15s multi-poser (silence floor RETIRED), expire 300s.
    Debug.Trace("[SNAnimGS] sheogorath mode ON (REV-137f receipt): armed -- poll 15s, T3 multi-poser every " \
        + fOdT3IntervalSec + "s (one-at-a-time silence floor retired; overlapping lifetimes permitted), expire " + fOdExpireSeconds \
        + "s, T3 pool policy mode " + _GenderPolicy() + " (REV-137d 3.1 blanket)")
    Debug.Notification("Sheogorath Mode - the room is yours.")
    _OdCue()                 ; first ambience cue right away (sets GSAnim.LastOdCue)
    RegisterForSingleUpdate(15.0)
EndFunction

; Performance Mode OFF — the single exit path shared by 2nd-press (button branch) and
; time-expiry (_OverdriveTick); one path, one cleanup. Drops the T2 floor back to 0
; (re-zero — exact against live config, caveat documented; T3 auto-poses bypass cooldowns
; by design and never saw the floor anyway), clears flag + all clocks.
Function _OverdriveOff(String sNotify)
    _EnsurePools()   ; Phase 4d: cheap insurance — the restore loop reads _PoseActions, and a 2nd-press OFF can arrive in a never-healed stale instance
    Int i = 0
    Int iSkipped = 0
    Bool bBakaHalf = _BakaPoseHalfPresent()   ;  S3: one probe per pass, not per name
    While i < _PoseActions.Length
        If bBakaHalf || !_IsBakaHostedPose(_PoseActions[i])
            SkyrimNetApi.SetActionCooldown(_PoseActions[i], 0)
        Else
            iSkipped += 1   ; guarded skip - Baka half absent (nothing to restore)
        EndIf
        i += 1
    EndWhile
    If iSkipped > 0
        Debug.Trace("[SNAnimGS] sheogorath mode T2 restore: " + iSkipped + " Baka-hosted pose cooldowns skipped - Baka half absent (REV-103 S3 guard)")
    EndIf
    StorageUtil.SetIntValue(None, "GSAnim.Overdrive", 0)
    StorageUtil.SetFloatValue(None, "GSAnim.OverdriveExpire", 0.0)
    StorageUtil.SetFloatValue(None, "GSAnim.LastOdCue", 0.0)
    StorageUtil.SetFloatValue(None, "GSAnim.CombatSuspendStart", 0.0)
    Debug.Trace("[SNAnimGS] sheogorath mode OFF (REV-137d receipt): " + sNotify)   ; 3.2 receipt: 2nd-press and time-expiry both land here
    If sNotify != ""
        Debug.Notification(sNotify)
    EndIf
EndFunction

; T1: one short-lived ambience cue into scene context. Stable eventId + 75s TTL = the
; previous cue is always overwritten before it can stack; event TYPE is a stable string
; too, so there's never more than one gsanim_perf_ambience line in context (Baka's
; _CueOngoing precedent — RegisterShortLivedEvent with no schema call, proven live).
Function _OdCue()
    Float fNow = Utility.GetCurrentRealTime()
    If fNow - StorageUtil.GetFloatValue(None, "GSAnim.LastOdCue", 0.0) < fOdCueSeconds
        Return
    EndIf
    StorageUtil.SetFloatValue(None, "GSAnim.LastOdCue", fNow)
    SkyrimNetApi.RegisterShortLivedEvent("gsanim_perf_ambience", "gsanim_performance", \
        _OdCues[Utility.RandomInt(0, _OdCues.Length - 1)], "", 75000, PlayerRef, None)
EndFunction

; The 15s overdrive tick ( 3.3): expiry check (incl. combat-pause already applied
; upstream in OnUpdate), T1 cue if due, T3 every-interval multi-poser fire if due.
Function _OverdriveTick()
    _EnsurePools()   ; Phase 4d: heal BEFORE the body — in the stale instance the _OdCue crash aborted this tick before the T3 floor check could even run
    Float fNow = Utility.GetCurrentRealTime()
    If fNow >= StorageUtil.GetFloatValue(None, "GSAnim.OverdriveExpire", 0.0)
        _OverdriveOff("Sheogorath Mode ended (time).")
        Return
    EndIf
    _OdCue()
    ;  3.3 (user ruling 2026-10-22, "I want chaos -- multiple posers and poses
    ; at the same time"): the one-at-a-time silence floor is RETIRED -- a NEW candidate
    ; fires every fOdT3IntervalSec (15s, planner overdrive cadence) with overlapping pose
    ; lifetimes permitted; eligibility gates UNCHANGED (policy/loaded/near/not-posing/
    ; not-combat + busy backstop). Concurrency verified safe: all GSAnim bookkeeping is
    ; per-actor keyed (Pose/Start/Timeout/LockAI/Vibe/IdleHold/T3Mark), the posing list
    ; is a FormList append, and no global lock exists. The clock is a fresh key
    ; (GSAnim.LastT3Fire) so save-resident members can't shadow it; a faster live sweep
    ; (3s, posers up) cannot accelerate the 15s cadence. Census sentinels unconditional.
    Float fLastT3 = StorageUtil.GetFloatValue(None, "GSAnim.LastT3Fire", 0.0)
    If fLastT3 > fNow
        fLastT3 = 0.0   ; stale cross-session stamp -- house clamp class ( pattern)
    EndIf
    ;  5.2: the T3 cadence is now an MCM SLIDER value (15s-240s, the GS
    ; Poses page) carried on the fresh key GSAnim.T3Interval (default = the
    ; historic compiled member -- the 137f save-residue-safe pattern; existing
    ; installs keep 15s).
    Float fT3Interval = StorageUtil.GetFloatValue(None, "GSAnim.T3Interval", fOdT3IntervalSec)
    If fNow - fLastT3 >= fT3Interval
        StorageUtil.SetFloatValue(None, "GSAnim.LastT3Fire", fNow)
        Debug.Trace("[SNAnimGS] sheogorath mode tick: T3 multi-poser fire (clock " + (fNow - fLastT3) \
            + "s >= interval " + fT3Interval + "s; expire in " \
            + (StorageUtil.GetFloatValue(None, "GSAnim.OverdriveExpire", 0.0) - fNow) + "s; )")
        _OdAutoPose()
    Else
        Debug.Trace("[SNAnimGS] sheogorath mode tick: T3 window not yet due (clock " + (fNow - fLastT3) \
            + "s < interval " + fT3Interval + "s; )")
    EndIf
EndFunction

; T3 multi-poser ( 3.3): one random eligible NPC (policy-admitted,  3.1 blanket)
; strikes a weighted solo-safe GS vibe. ExecuteAction bypasses eligibility AND cooldowns
; by design — our guard chain is the ONLY protection, so it's strict: _DaemonScan
; (policy-admitted/loaded/near/not-posing/not-combat) + _IsBusyElsewhere backstop + not
; currently T3-posed. The Pose*_Execute wrappers re-run their own gender/busy guards at
; dispatch, defense in depth. GS VIBES ONLY — never Baka, never two-actor, never
; targeted. After the fire, a justification thought seed lands (rc checked, harmless if
; it fails) and the silence clock re-arms via _PoseVibe's stamp.
;  3.2: every attempt leg is receipted — pool-empty, candidate selection
; (who + why), every refusal named, dispatch rc, and the fire receipt lands via
; _PoseVibe's success leg (with the user-ruled on-screen Sheogorath notification, 4.1).
Function _OdAutoPose()
    Int n = _DaemonScan()
    If n == 0
        Debug.Trace("[SNAnimGS] sheogorath T3 attempt REFUSED: candidate pool EMPTY (scan n=0; filters: policy mode " \
            + _GenderPolicy() + ", radius " + fDaemonRadius + ", posing, combat, sleep, swim/mount/sneak)")
        Return
    EndIf
    Actor ak = _DaemonPool[Utility.RandomInt(0, n - 1)]
    If !ak
        Debug.Trace("[SNAnimGS] sheogorath T3 attempt REFUSED: random slot resolved None (pool n=" + n + ")")
        Return
    EndIf
    If _IsBusyElsewhere(ak)
        Debug.Trace("[SNAnimGS] sheogorath T3 attempt REFUSED: " + ak.GetDisplayName() \
            + " busy at pick time (backstop; pool n=" + n + ")")
        Return
    EndIf
    ; Weighted pick from the named constant pool (Edit 2 block — retune _OdVibeWeights).
    String sAction = _OdVibeNames[_OdVibeWeights.Length - 1]
    Int iRoll = Utility.RandomInt(1, _OdWeightTotal)
    Int iAcc = 0
    Int i = 0
    While i < _OdVibeWeights.Length
        iAcc += _OdVibeWeights[i]
        If iRoll <= iAcc
            sAction = _OdVibeNames[i]
            i = _OdVibeWeights.Length   ; break
        EndIf
        i += 1
    EndWhile
    Debug.Trace("[SNAnimGS] sheogorath T3 attempt: candidate " + ak.GetDisplayName() \
        + " selected (random draw from policy-admitted pool n=" + n + ", policy mode " + _GenderPolicy() \
        + ") -> vibe " + sAction + " (weighted pick)")
    ;  (idle-interrupt service, spec 1.4.4): T3 routes through the same
    ; primitive — interruptible idle classes exit->recheck (incl. the
    ; gender-policy admit, live) -> fire instead of being silently dropped.
    If !_IdleFirePath(ak, sAction)
        Debug.Trace("[SNAnimGS] sheogorath T3 attempt REFUSED: idle interrupt (exit/recheck refused -- reason per the idle-svc sentinel above): " + ak.GetDisplayName())
        Return
    EndIf
    Debug.Trace("[SNAnimGS] T3 multi-poser auto-pose: " + ak.GetDisplayName() + " -> " + sAction)
    ;  3.1: the receipt gate is a per-actor GSAnim.T3Mark timestamp set HERE at
    ; dispatch (cleared on a non-zero rc) and consumed by _PoseVibe's success leg within
    ; 30s -- the old _bT3InFlight member window closed at this function's synchronous
    ; return, before the async dispatch's fire reached the receipt block, so the
    ; user-ruled on-screen notification never printed (0/4 in the 10-22 dogfood log).
    StorageUtil.SetFloatValue(ak, "GSAnim.T3Mark", Utility.GetCurrentRealTime())
    Int rcOd = SkyrimNetApi.ExecuteAction(sAction, ak, "{}")
    If rcOd != 0
        StorageUtil.SetFloatValue(ak, "GSAnim.T3Mark", 0.0)   ; dispatch refused -- clear the mark (0.0 = none)
    EndIf
    Debug.Trace("[SNAnimGS] sheogorath T3 attempt dispatched (rc=" + rcOd + "): " + ak.GetDisplayName() \
        + " -> " + sAction + "; accept/refuse receipt per the pose fire sentinels below")
    ; Justification seed: the same thought registers that drive muse, at performance pitch.
    SkyrimNetApi.GenerateNPCThought(ak, \
        "The music and the crowd's eyes have gotten to you - you feel like dancing for them.")
EndFunction
; Phase 4 rider: labels below are the distilled Phase 3 one-liners — they flow into the
; gsanim_npc_pose event ("strikes <label>." since  Task 3.1 — the ", holding
; it in place" tail removed by user ruling 2026-10-23) AND into the per-actor
; GSAnim.Vibe key the stop paths read for named-pose stop wording.
Function PoseSeduce_Execute(Actor akInitiator)
    _PoseVibe(akInitiator, "seduce", "a seductive pose - weight on one hip, gaze holding the room", 2)
EndFunction
Function PoseSelftouch_Execute(Actor akInitiator)
    _PoseVibe(akInitiator, "selftouch", "a suggestive, self-touching pose - arousal worn openly", 2)
EndFunction
Function PosePresent_Execute(Actor akInitiator)
    _PoseVibe(akInitiator, "present", "a bent-forward presenting pose, deliberately offering the view", 2)
EndFunction
Function PoseDance_Execute(Actor akInitiator)
    _PoseVibe(akInitiator, "dance", "a light, playful dance - feet answering the music", 2)
EndFunction
Function PoseDanceSexy_Execute(Actor akInitiator)
    _PoseVibe(akInitiator, "dance_sexy", "a slow, provocative dance - a performance with a single intended victim", 2)
EndFunction
Function PoseGroundSexy_Execute(Actor akInitiator)
    _PoseVibe(akInitiator, "ground_sexy", "a sultry sprawl on the ground - low, languid, unhurried", 2)
EndFunction
Function PoseGroundIdle_Execute(Actor akInitiator)
    _PoseVibe(akInitiator, "ground_idle", "a spent, sprawling rest on the ground", 2)
EndFunction
Function PoseWorkout_Execute(Actor akInitiator)
    _PoseVibe(akInitiator, "workout", "a set of exercises - strength and stamina on display", 2)
EndFunction
Function PoseStretch_Execute(Actor akInitiator)
    _PoseVibe(akInitiator, "stretch", "a long, reaching stretch", 2)
EndFunction
Function PoseSubmission_Execute(Actor akInitiator)
    _PoseVibe(akInitiator, "submission", "a surrendered pose - body lowered, the shape of yielding", 2)
EndFunction
Function PosePlead_Execute(Actor akInitiator)
    _PoseVibe(akInitiator, "plead", "a kneeling plea - lowered before someone it matters to", 2)
EndFunction
Function PoseIdle_Execute(Actor akInitiator)
    _PoseVibe(akInitiator, "idle", "an easy stance - hip against the wall, nowhere to be", 2)
EndFunction

; Phase 4 rider: shared stop wording — names the held pose from GSAnim.Vibe when present,
; generic "the pose" fallback when the key is missing (crash-safety: any legacy pose or a
; stop arriving by a path that never stored a vibe still words cleanly).
String Function _StopWording(String sVibe)
    If sVibe != ""
        Return " relaxes out of " + sVibe + "."
    EndIf
    Return " relaxes out of the pose."
EndFunction

; LLM ends the pose. Behavior note: the stop itself stays unconditional (as before Phase 4 —
; _StopActorPose no-ops on null and simply resets anyone the LLM names); the Phase 4 rider
; only adds the named-pose stop EVENT, and only when the actor was actually on our posing list.
Function StopPosing_Execute(Actor akInitiator)
    If !akInitiator
        Return
    EndIf
    Bool bWas = StorageUtil.FormListHas(None, "GSAnim.Posing", akInitiator)
    String sVibe = StorageUtil.GetStringValue(akInitiator, "GSAnim.Vibe", "")
    _StopActorPose(akInitiator)
    If bWas
        SkyrimNetApi.RegisterEvent("gsanim_npc_pose", \
            akInitiator.GetDisplayName() + _StopWording(sVibe), akInitiator, None)
    EndIf
EndFunction

; One character tells another to stop posing (roleplay: "stop that"). Same rider as above:
; unconditional stop (unchanged), named-pose stop event when the target was posing.
Function CommandStopPose_Execute(Actor akInitiator, Actor akTarget)
    If !akInitiator || !akTarget
        Return
    EndIf
    Bool bWas = StorageUtil.FormListHas(None, "GSAnim.Posing", akTarget)
    String sVibe = StorageUtil.GetStringValue(akTarget, "GSAnim.Vibe", "")
    _StopActorPose(akTarget)
    If bWas
        SkyrimNetApi.RegisterEvent("gsanim_npc_pose", \
            akInitiator.GetDisplayName() + " tells " + akTarget.GetDisplayName() \
            + " that's enough; " + akTarget.GetDisplayName() + _StopWording(sVibe), akTarget, None)
    EndIf
EndFunction
