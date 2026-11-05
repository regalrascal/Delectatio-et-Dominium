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

; ── REV-85 Phase B: gender policy (posing-gender.md §2a/§2b, rulings A/B) ───
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

; REV-85 Phase B: the central admission question — "may THIS actor pose on a
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

; REV-85 Phase B: per-mode refusal strings (§7 ruling B). Mode 0 keeps the
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
;                             T3 silence-floor auto-pose; expires 1h (REV-169 leg 6); 2nd press = OFF)
;   GSAnim.Muse               1 = ambient thought-seeder running (throttled GenerateNPCThought)
;   GSAnim.LastPoseFire       global timestamp of the last pose fire — observability only
;                           since REV-137f 3.3 (the T3 silence-floor reader is retired)
;   GSAnim.LastT3Fire        REV-137f 3.3: T3 multi-poser fire clock — a NEW candidate every
;                           fOdT3IntervalSec; fresh key (absent from old saves, no residue)
;   GSAnim.T3Mark            REV-137f 3.1: per-actor timestamp of the latest T3 dispatch;
;                           consumed by _PoseVibe's success leg within 30s for the user-ruled
;                           on-screen Sheogorath receipt (replaces the _bT3InFlight window)
;   GSAnim.NudgeInterval     REV-137f 3.2: Sanguine nudge interval of record (StorageUtil;
;                           defaults to the fMuseNudgeIntervalSec compile-time value — a KEY,
;                           because the save-resident member value 100.0 was shadowing the
;                           compiled 30.0 on long-lived saves, the diagnosed ~100s gap source)
;   GSAnim.T3Interval        REV-159 5.2: Sheogorath T3 cadence (StorageUtil, default = the
;                           fOdT3IntervalSec compiled member 15.0; the GS Poses MCM slider
;                           writes it live, 15s-240s)
;   GSAnim.SanguineModeNarr / GSAnim.SheogorathModeNarr
;                           REV-159 5.1 -> [REV-174e Leg 4] ORPHANED (MCM rows/keys removed
;                           2026-10-31, no migration; zero live read sites since the REV-174a
;                           D3 lane fan-out -- GSAnim.<Mode>Lane_narr is the sole gate)
;   GSAnim.PoseNarrSanguine / GSAnim.PoseNarrEmergent / GSAnim.PoseNarrPlayer
;                           REV-159 5.3: the three per-route pose-cue narration toggles
;                           (DEFAULT 1 = ON, current behavior preserved; the GS Poses page
;                           owns them, user-authored titles)
;   GSAnim.LastOdCue          global timestamp of the last T1 ambience cue
;   GSAnim.OverdriveExpire    absolute real-time timestamp when performance mode auto-OFFs
;   GSAnim.CombatSuspendStart when the current player-combat suspend began (0 = not suspended;
;                             the expiry clock is extended by exactly the combat span on resume)
;   GSAnim.MuseGlobal        boot-relative timestamp (Utility.GetCurrentRealTime()) of the
;                           last muse nudge CALL (v1.2: stamped at call time, gates the
;                           ~100s interval — fMuseNudgeIntervalSec). REV-17 cross-session
;                           clamp: the stamp persists in saves but the clock is BOOT-
;                           relative, so a stamp from a longer prior session reads as
;                           "just asked" and gates every tick of a shorter next boot —
;                           _MuseTick clamps any stamp > fNow to 0 on read (the 09-15
;                           evening session's total muse silence was exactly this).
;   GSAnim.LastMuse  (actor) per-NPC timestamp of the last LANDED seed. REV-19: READ by the
;                           per-NPC floor (fMusePerNpcSec, 120s) in the _MuseTick candidate walk —
;                           a floored candidate is skipped and the walk continues; all-floored is
;                           the "nobody eligible" lap exit, no call spent. Stale-stamp clamp at
;                           read (stamp > fNow -> 0, persisted) per the rev-17 MuseGlobal pattern
;                           (boot-relative clock, save-persisted stamp). The seed-time write of
;                           fNow stays as-is.
;   GSAnim.MuseDebugEnd     boot-relative absolute timestamp the muse debug window closes
;                           (REV-17 1c: the window now re-arms per BOOT, not once per
;                           playthrough — first MUSE_TOGGLE ON of each game start; a
;                           stale cross-boot end-stamp is clamped closed on read by
;                           _MuseDebugWindowOpen)
;   GSAnim.MuseDebugDone    1 = a muse debug window is/has been armed (informational; the
;                           REV-17 per-boot arming is driven by an in-memory member flag,
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
    ; REV-105 S2: the two SNBaka.* busy reads are now gated on the busy-state
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
    ; REV-135 (idle-interrupt service, spec gs-poses.md REV-134e 1.4.3): the
    ; GetSitState leg is now CLASS-AWARE — interruptible idle classes (furniture
    ; sits + IdleMarker holds) no longer hard-exclude here; callers route those
    ; actors through _IdleFirePath (detect -> exit -> fire-time recheck -> fire)
    ; instead of silently dropping them. This is the REV-87 seated-exclusion
    ; strangling fix: the seated tavern population is REACHABLE now. Essential
    ; idle classes (sleep/downed/mounted/swimming/sneaking) stay
    ; hard-excluded via the callers' own state guards + _IdleClass in the service
    ; (REV-137: dialogue dropped from this list — no longer an ESSENTIAL class).
    If _IdleClass(ak) > 0
        Return False
    EndIf
    Return False
EndFunction

; ===================== REV-135: THE IDLE-INTERRUPT SERVICE =====================
; Spec of record: gs-poses.md REV-134e 1.4.1-1.4.3. Pure Papyrus, no DLL, no
; esp; no LLM strings anywhere in the service. The Baka motherboard inherits
; this at the daemon build by calling the two GLOBAL functions cross-script:
;   SkyrimNet_AnimationsGS._IdleClass(ak)
;   SkyrimNet_AnimationsGS._ExitIdle(ak, iClass)
; Idle classes (the taxonomy, 1.4.1):
;    0 = not idle-anchored;  1 = furniture sit (INTERRUPTIBLE);  2 = IdleMarker
;    hold (INTERRUPTIBLE);  -1 sleep, -2 bleedout/downed, -3 mounted, -4
;    swimming, -5 sneaking (all ESSENTIAL, never interrupted). REV-137: the
;    -6 mid-dialogue class is RETIRED (user ruling — dialogue guards removed).
; Carried rulings REV-136 (2026-10-22): sneaking ESSENTIAL (edge ruled);
;    REV-137 (2026-10-22) SUPERSEDES the REV-136 mid-dialogue narrowing —
;    dialogue is NO LONGER an ESSENTIAL class (guards removed; the
;    vanilla-Dialogue-Menu discriminator UI.IsMenuOpen is gone with it); the
;    REV-135 PathToReference stand shape RETIRED — stand-in-place
;    only (no pathing, no translation toward ANY reference, no teleports); AI
;    re-grab PREVENTED (hold at exit-issue, supersedes tolerate-and-skip).
; Scripted/quest idles have NO direct Papyrus native — covered ONLY by the
;    fire-time scene/combat guard in _IdleFirePath (surfaced in the REV-135
;    gate report); the REV-136 mid-dialogue approximation is retired with the
;    class (REV-137 user ruling — unguarded testing).
; Natives verified against installed source (REV-25 3b discipline):
; GetSleepState/GetSitState/IsBleedingOut/IsOnMount/IsSneaking (vanilla
; Actor.psc, Data\Source\Scripts), IsSwimming/GetFurnitureReference (SKSE64
; Actor.psc, installed mods tree), Debug.SendAnimationEvent (vanilla Debug.psc).
; (REV-137: UI.IsMenuOpen dropped from this list — no longer called.)

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
    ; REV-137 (user ruling, 2026-10-22 session): the dialogue guard is REMOVED
    ; — no dialogue class in the taxonomy at all. HONEST LIMIT, updated to
    ; record the ruling: the REV-136 vanilla-Dialogue-Menu discriminator
    ; (UI.IsMenuOpen) was ruled out by the user — poses are to be tested
    ; UNGUARDED against dialogue; guards removed pending live testing. The
    ; old -6 mid-dialogue class is retired; scripted/quest idles have no
    ; direct Papyrus native and are covered only by the fire-time
    ; scene/combat guard in _IdleFirePath (surfaced in the REV-135 gate
    ; report; unchanged by this removal).
    If ak.GetSitState() != 0
        Return 1
    EndIf
    If ak.GetFurnitureReference()
        Return 2
    EndIf
    Return 0
EndFunction

; The exit primitive (1.4.2, REV-136 2.1 ruling: STAND-IN-PLACE — no pathing,
; no translation toward ANY reference, no teleports; the REV-135
; PathToReference(player) shape is RETIRED as ruled wrong). ONE technique
; for BOTH interruptible classes: the proven Acheron-pair event
; IdleForceDefaultState (AcheronIntegration L211/L486/L529-531 precedent)
; breaks the furniture sit AND the marker hold; the actor stands where they
; are (pop-stand MVP — smooth-stand polish is OUT OF SCOPE this rev).
; Returns True ONLY when CONFIRMED: the actor is UP (SitState 0) within the
; 4.0s REAL-clock poll window (REV-137a 2.1: was 2.0s; the L6998 real-clock
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
    ak.SetDontMove(True)   ; REV-137a: stand-window hold -- blocks walk-away, not the stand
    ; REV-137b: the DontMove span WIDENED -- held through CONFIRM and the fire handoff
    ; (the [REV-138] dogfood evidence: 8/8 BACKSTOP re-anchors were class 2 -- the
    ; sandbox package walked freshly-standed actors to a nearby idle marker inside
    ; the confirm->recheck->fire window the moment DontMove cleared; sub-poll re-sits
    ; produced the exit-FAILED refusals). Released ONLY by the no-fire legs
    ; (_ReleaseIdleHold) and the pose-end machinery (_StopActorPose clears both
    ; restraints) -- a fired pose never strands the hold.
    Debug.SendAnimationEvent(ak, "IdleForceDefaultState")
    Float fStart = Utility.GetCurrentRealTime()
    While (Utility.GetCurrentRealTime() - fStart) < 4.0
        If ak.GetSitState() == 0
            ; REV-137b: NO SetDontMove(False) here -- the hold persists through fire
            If ak.GetFurnitureReference()
                Debug.Trace("[SNAnimGS] idle-svc exit confirmed: SitState clear, furniture-ref PERSISTED (named discriminator): " + ak.GetDisplayName() + " class=" + iClass)
            Else
                Debug.Trace("[SNAnimGS] idle-svc exit confirmed: both anchors clear: " + ak.GetDisplayName() + " class=" + iClass)
            EndIf
            Debug.Trace("[SNAnimGS] idle-svc exit confirmed: hold spans through fire handoff (REV-137b): " + ak.GetDisplayName() + " class=" + iClass)
            Return True
        EndIf
        Utility.Wait(0.1)   ; REV-137b: 0.25 -> 0.1 poll (sub-0.25s stand/resit races defeated the [REV-138] poll)
    EndWhile
    ; FAIL at 4.0s -- NAME the persisted anchor (the REV-137a hypothesis-pair discriminator)
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

; The fire-time pipeline (1.4.3, REV-136 2.2): class detect -> AI HOLD ->
; exit -> RECHECK -> caller fires. The RECHECK is the rev-20 revalidation
; precedent, as-built at the Execute kill-time recheck (motherboard
; L7467-7500): re-essential states, RE-ANCHOR (backstop ONLY while the AI
; hold is held — see 2.2 note), candidate validity (gender-policy admit
; live, no scene/combat/pose-active). §5 sentinels on EVERY leg, unconditional,
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
        ; REV-137a 2.2 (finding 2.1, the wander-while-posing defect): the
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
        _PkgHoldActorAI(ak, True)   ; REV-137c 3.1: in-flight pathing stop -- DontMove does not stop a travel procedure
        Return True
    EndIf
    ; REV-136 2.2 (user ruling, SUPERSEDES tolerate-and-skip): the AI hold is
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
    ; REV-137c 3.1: engage the DoNothing override BEFORE the stand event --
    ; the [REV-139] dogfood sitState-persistence refusals (Kleppr/Cosnach)
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
        ; REV-136 2.2: UNREACHABLE BACKSTOP ONLY — the AI hold is held from
        ; exit-issue through recheck, so a package re-anchor cannot happen;
        ; the REV-135 one-re-exit-then-skip path stays per ruling as the
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

; REV-137c 3.1 (verdict 2.1c): the Baka-grade package hold. The [REV-139]
; dogfood proved SetDontMove does NOT stop in-flight package pathing (5
; recheck BACKSTOPs + class-0 glides with the hold live throughout), and
; the in-repo proven comparison (BakaIntegration _HoldActorAI L1775-1799
; + its shipped comment: "SetRestrained/SetDontMove stop walking but NOT
; package re-evaluation") holds: the ONE missing primitive is the
; condition-free DoNothing package override at priority 100 + EvaluatePackage.
; Ported WITHOUT a hard script dependency (the era doctrine: no hard
; Baka dep): the Baka esp's own DoNothing package (PACK local 0xD6A
; (0x04000D6A), SkyrimNet_BakaIntegration.esp; REV-137e: the REV-137c
; literal 0x1E6 was a header misparse - the PACK record's DATA-SIZE
; field read as formID; corrected per the REV-137d-R rider hex receipt) is soft-read via GetFormFromFile, gated
; on the existing busy.baka-half service probe (REV-105 S2 class -- absent
; Baka = present behavior, DontMove/Sandbox hold only, miss sentinel once
; per load). Engaged with the AI hold at fire (class 0) and BEFORE the
; stand (class 1/2 exit-issue -- so the package cannot re-sit mid-stand:
; the [REV-139] sitState-persistence refusals class); released at every
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
            ; REV-137e: the UNAVAILABLE sentinel is SPLIT into two
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

; REV-136 2.2: the service AI-hold release — called ONLY on the no-fire paths
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
    _PkgHoldActorAI(ak, False)   ; REV-137c 3.1: package pin rides the no-fire legs too (never strand)
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
_StopActorPose(akStop, "player-stop")
            Debug.Notification(akStop.GetDisplayName() + " stops posing.")
            ; [REV-174g Leg 4.1] FACT-CUE FLOOR: the general pose cue fires
            ; UNCONDITIONALLY (outside every route/lane gate) with the same
            ; composed desc; the gated pair cue below is unchanged.
            SkyrimNetApi.RegisterEvent("gsanim_pose_general", \
                PlayerRef.GetDisplayName() + " gestures for " + akStop.GetDisplayName() \
                + " to stop posing; " + akStop.GetDisplayName() + _StopWording(sVibe), \
                akStop, None)
            ; REV-159 5.3: the stop gesture is a player-initiated pose event --
            ; gated by the player route toggle (DEFAULT ON), same as _PoseDirect.
            If StorageUtil.GetIntValue(None, "GSAnim.PoseNarrPlayer", 1) == 1
                SkyrimNetApi.RegisterEvent("gsanim_pose_player", \
                    PlayerRef.GetDisplayName() + " gestures for " + akStop.GetDisplayName() \
                    + " to stop posing; " + akStop.GetDisplayName() + _StopWording(sVibe), \
                    akStop, None)
            Else
                Debug.Trace("[SNAnimGS] gsanim_pose_player cue GATED-OFF (route 3 player stop, " + akStop.GetDisplayName() + ") -- REV-174f Leg 3")
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
            Debug.Trace("[SNAnimGS] sheogorath mode toggle: ON requested (grid footer)")   ; REV-137d 3.2 receipt
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
            Debug.Trace("[SNAnimGS] sanguine mode toggle: OFF (grid footer)")   ; REV-137d 3.2 receipt
            Debug.Notification("Sanguine Mode - quieted.")   ; REV-174a D5 " - " sweep (DRAFT wording)
        Else
            StorageUtil.SetIntValue(None, "GSAnim.Muse", 1)
            Debug.Trace("[SNAnimGS] sanguine mode toggle: ON (grid footer)")   ; REV-137d 3.2 receipt
            ; REV-24 Task 2: the session-scope reset now rides the ReferenceAlias load reset
            ; (SkyrimNet_AnimGS_LoadAlias / SNAnimGS_LoadAlias quest — rev-24 Option A ruling,
            ; the skynet_PlayerAlias production pattern). The rev-21 MuseSetAt stamp heuristic
            ; is RETIRED: no activation stamp is written, and the OnUpdate stale-stamp reset
            ; branch is deleted. Toggle-at-will within a session is untouched (the 09-16 UX
            ; ruling); the flag now agrees with the stateless grid label at every session
            ; start by construction, not by clock inference.
            ; ── Phase 4c rider (REV-17 1c re-arm semantics): arm the 10-min muse debug
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
            Debug.Notification("Sanguine Mode - stirring - thoughts turn warm.")   ; REV-174a D5 " - " sweep
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
            ; REV-90 rider sentinel (REV-89 registration, §94 3.1; unconditional per §5):
            ; the crosshair validation chain was Notification-only — admit/refuse was NOT
            ; log-distinguishable (posing-gender.md observability gap, closed here).
            Debug.Trace("[SNAnimGS] crosshair refuse: " + akTarget.GetDisplayName() + " dead")
            Return
        EndIf
        ; REV-85 Phase B: the L335 female test is replaced by the central policy
        ; admission (posing-gender.md §2c) — dead/busy legs unchanged above/below.
        ; Mode 2 loses the leg entirely; 0/1 keep per-mode refusal strings.
        ; REV-85b fix: pass sCat (the pick's category) — the shipped call passed an
        ; empty vibe, so curated mode refused EVERY male pick here regardless of pose
        ; (the "curated no better than female-only" dogfood finding; grid cats are
        ; the _VibeMaleOK vibe names).
        If _GenderPolicy() != 2 && !_GenderAdmits(akTarget, sCat)
            Debug.Notification(_GenderRefusal(akTarget, _GenderPolicy()))
            ; REV-90 rider sentinel (REV-89 registration, §94 3.1; unconditional per §5).
            Debug.Trace("[SNAnimGS] crosshair refuse: " + akTarget.GetDisplayName() \
                + " gender policy veto (cat '" + sCat + "', mode " + _GenderPolicy() + ")")
            Return
        EndIf
        If _IsBusyElsewhere(akTarget)   ; mid-scene/combat -- reason stays vague on purpose
            Debug.Notification(akTarget.GetDisplayName() + " can't pose right now.")
            ; REV-90 rider sentinel (REV-89 registration, §94 3.1; unconditional per §5).
            Debug.Trace("[SNAnimGS] crosshair refuse: " + akTarget.GetDisplayName() + " busy at pick time")
            Return
        EndIf
        ; REV-135 (idle-interrupt service, spec 1.4.4): the crosshair pick path
        ; routes through the service — interruptible idle classes (seated/
        ; marker-held) now EXIT -> RECHECK (incl. the gender-policy admit,
        ; re-checked live here per the fire-time contract) -> fire, instead of
        ; being hard-refused by the formerly class-blind sit leg.
        If !_IdleFirePath(akTarget, sCat)
            Debug.Notification(akTarget.GetDisplayName() + " can't pose right now.")
            Debug.Trace("[SNAnimGS] crosshair refuse: idle interrupt refused at pick time (" + akTarget.GetDisplayName() + ", class-aware)")
            Return
        EndIf
        ; REV-90 rider sentinel (REV-89 registration, §94 3.1; unconditional per §5): the
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
    ; REV-20 muse direct-fire additions: single-actor Babo idle EVENTS, fired only from
    ; the muse rider (_MuseFireVibe -> _PoseVibe) under full GS bookkeeping — never a
    ; Baka two-actor action or scene, never an LLM path (no Pose*_Execute wrapper maps
    ; to these vibes, so the action pipeline can't reach them). "aroused" returns the
    ; FEMALE pair as the pool DEFAULT; REV-85c A.3 sex-splits the draw at the single
    ; consumer (_VibeEventsFor, used by _PoseVibe): a male target draws
    ; BaboArousedMale01/02 — Baka's own sex-selecting exec path (BakaIntegration
    ; L8657-8663) is the precedent. Females unchanged.
    ElseIf vibe == "handonchin"
        Return "BaboHandonChin"
    ElseIf vibe == "handonface"
        Return "BaboHandonFace"
    ElseIf vibe == "aroused"
        ; REV-85c A.3: female pool default; the male draw is _VibeEventsFor's split.
        Return "BaboArousedFemale01,BaboArousedFemale02"
    ; REV-24 Task 3 (approved tiers: Tier 1 + Drink): four more single-actor Babo idle EVENTS
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
    ; REV-25 Task 2c (user advocacy ruling): DROOL joins the muse vocabulary — BaboDroolingFace,
    ; a single-actor facial/body idle via a bare _PlaySoloHold in Baka's own exec (no props, no
    ; furniture, no interaction branch — mechanically clean per the rev-20 evaluation pattern).
    ; Thematic frame ON RECORD (user): "reduced to it" — the defeat/lust register, alongside
    ; Aroused. YAML description reported to the user in the rev-25 gate for retro-review.
    ElseIf vibe == "drool"
        Return "BaboDroolingFace"
    EndIf
    Return ""
EndFunction

; REV-85c A.3 (user ruling 2026-10-07, posing-gender.md): aroused-pool sex-split.
; "aroused" is male-admitted (_VibeMaleOK) but its pool was female-only clips — a male
; admitted to the vibe drew female clips (the Addendum A gap). Split at the SINGLE
; consumer of vibe pools: _PoseVibe's draw (grid picks fire exact events via
; _PoseDirect and never map to "aroused"; the T-initiator legs fire no "aroused"
; vibe; the muse fire L1478 is the sole "aroused" supplier). Males draw
; BaboArousedMale01/02 — Baka's own exec (BakaIntegration L8657-8663) is the
; precedent; females (and unknown sex, already blocked at admission upstream) keep
; the female pair. Every other vibe passes through _VibeCSV unchanged. Sentinel per
; §5 so the split's live effect is greppable in the funnel.
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
; REV-163: THE POSE PICKER DECOMMISSION (user ruling 2026-10-25, the
; pose_picker_pipeline_descision.txt extract; supersedes the REV-152 build
; and the REV-134e spec's decision-model leg).
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
; The shape now: the consideration call (gsanim_sanguine_consideration) picks
; the category AND the exact move IN ONE PASS -- its context pack gains the
; itemized pose catalog (warning + description + move list per category,
; _MusePoseCatalogText below; the same payload the retired picker's options
; carried, _VibePoseOptions = poses.js catalog of record), and its output
; contract gains "CLIP: <move key>". The answer's CLIP fires through the
; REV-152 sForceEvent exact-pick plumbing (kept -- the machinery was proven;
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
; picks the member action from its yaml descriptions (the REV-161 4.3
; pool-move lines are the semantic-selection mechanism there).
; ═══════════════════════════════════════════════════════════════════════════

; A category's poses as a JSON array of "EVENTKEY: description" strings
; (per-pose descriptions straight from poses.js, the catalog of record --
; descriptions, not bare event keys, so "twerk for me" resolves to the
; twerk-bearing dance_sexy/ground_sexy moves). REV-163: with the picker's
; decision-model leg retired, this is the CATALOG SOURCE for the muse
; consideration prompt (via _MuseCatalogOptions/_MusePoseCatalogLine ->
; _MusePackContext's poseCatalog field) -- the same payload the retired
; picker carried, now surfaced to the model that already holds the scene
; context. Returns "" for vibes with no catalog descriptions (the Babo
; single-event vibes, the aroused pair). Sets are the _VibeCSV pools
; verbatim.
String Function _VibePoseOptions(String vibe)
    If vibe == "seduce"
        Return "[\"GS1: seducing - a seductive pose, a flirt and a tease to lure them in\",\"GS2: seducing forward - seductive and facing them, flirting head-on\",\"GS3: seducing, looking back - a seductive tease thrown over the shoulder\",\"GS17: flirting suggestively - a playful, coy and suggestive flirt\",\"GS25: seducing, moving butt (subtle) - a slow subtle sway, butt moving to seduce\",\"GS26: seducing, moving butt (subtle) - slow subtle sway, butt teasing to seduce (twin)\",\"GS31: hip heart, showing - hips shaping a heart, a seductive display\",\"GS36: butt-showing, seductive - ass and butt on show, a seductive display\",\"GS56: shy provoking, seducing - bashful but provoking, a shy seductive tease\",\"GS62: looking back suggestively - a suggestive look back over the shoulder\",\"GS63: moving body slowly down - a slow sensual move, body sinking down\",\"GS66: horny, side to side - aroused, hips swaying side to side\",\"GS70: shy, biting thumb - a nervous bite of the thumb, shy and coy\",\"GS80: slow hip, shy seducing - shy but sensual, hips swaying slow\",\"GS84: boob-carrying, seducing - breasts carried in the arms, a seductive display\",\"GS189: tying hair provocatively - hair tied up, a provocative seductive show\",\"GS198: slow, looking forward - a slow seductive gaze, looking straight ahead\"]"
    ElseIf vibe == "selftouch"
        Return "[\"GS6: touching self, horny - hands on her own body, aroused and horny\",\"GS7: touching self, very horny - desperate hands all over, very aroused\",\"GS18: spanking self provocatively - slapping her own ass, a provocative show\",\"GS46: touching tits suggestively - hands teasing her breasts, suggestive\",\"GS55: super horny, touching self - desperate arousal, hands touching everywhere\",\"GS60: touching self all over - hands roaming her body, horny and open\",\"GS69: horny, side to side - aroused swaying, hips moving side to side\",\"GS71: touching self all over - hands roaming her body, horny (twin)\",\"GS72: shyly touching tits - bashful hands on her breasts, a shy tease\",\"GS87: touching boobs, shy - a shy touch of her boobs, blushing bashful\"]"
    ElseIf vibe == "present"
        Return "[\"GS4: bent, showing ass - bent over, ass showing to present\",\"GS5: bent showing ass, looking forward - bent over ass out, gaze ahead\",\"GS11: bent, hands to knees, presenting - hands on knees, bent over offering\",\"GS37: bent over, showing butt (slow) - a slow bend, butt showing\",\"GS38: moving butt slow, looking back - butt swaying slow, a look back to tease\",\"GS43: round butt showing, sexy slow - a slow sexy bend, butt on display\",\"GS86: bend over shy, showing butt - a shy bend over, a bashful butt show\",\"GS88: hands to knees, presenting - hands to knees, offering the view\",\"GS99: bent, slutty slow butt - a slow slutty bend, butt presenting\",\"GS118: bend over, looking forward - bent over, eyes forward, offering\",\"GS130: bend over, showing butt shyly - a shy bend over, a bashful show\",\"GS162: bend over, showing butt shy - a shy bend over, a bashful show (twin)\",\"GS190: bending, concentrated (kinda sexy) - a focused bend, a bit sexy\",\"GS193: showing a bit of butt, seducing - a flash of butt, a seducing tease\",\"GS202: bending, concentrated (kinda sexy) - a focused bend, a bit sexy (twin)\"]"
    ElseIf vibe == "dance"
        Return "[\"GS21: skyrim arm dance - a native folk dance, arms up in joy\",\"GS27: mambo - playful mambo steps\",\"GS34: victory dance - dancing to celebrate a triumph\",\"GS42: good lateral dance - playful side steps, a lateral sway\",\"GS47: modest dance - a reserved, modest dance, tame\",\"GS48: long static dance - a long still dance, a static pose\",\"GS58: modest, no seducing - modest dancing, reserved, no seducing\",\"GS59: waiting, hips, no seducing - hips swaying while waiting, idle\",\"GS79: joyful, touching hips - a joyful dance, hands touching hips\",\"GS95: hip + funny hands - a funny hip dance, silly hands\",\"GS125: funny dance - a silly, funny dance\",\"GS132: cool, not only sexy - a cool stylish dance, not only sexy\",\"GS133: cool, not only sexy - cool and stylish (twin)\",\"GS154: valiant, girly - a proud, valiant girly dance\",\"GS209: funny, useful - a funny, playful dance\"]"
    ElseIf vibe == "dance_sexy"
        Return "[\"GS9: twerking, looking back - ass shaking twerk, looking back to show off\",\"GS10: sensual, semi-shy - a slow sensual dance, a semi-shy tease\",\"GS12: sensual hips, hands up - hands up, hips swaying sensual\",\"GS13: provocative - a lewd provocative dance, teasing\",\"GS14: sexy, in circles, bent - hips in circles, bent low, dancing\",\"GS15: distracted, hips moving - hips swaying, a distracted dance\",\"GS23: tik-tok hips - a hip sway in rhythm, a tik-tok dance\",\"GS29: hip dance, sensual slow - a slow sensual hip dance, swaying\",\"GS44: slow twerking, seducing - a slow twerk to seduce, ass shaking\",\"GS52: man, lewd suggestion - a man dancing a lewd suggestion, hips moving\",\"GS61: slow hips, hand on chin - slow hips, a thoughtful hand on chin\",\"GS83: heating up - intense dancing, heating up, aroused\",\"GS102: slutty, butt showing - a slutty dance, butt showing\",\"GS107: slutty, side to side - slutty hips swaying side to side\",\"GS144: sexy, not too slutty - a tease, sexy but balanced\",\"GS187: hands up, hips - hands up, hips dancing\"]"
    ElseIf vibe == "ground_sexy"
        Return "[\"GS253: all fours, suggestive - on all fours, suggestive and presenting\",\"GS257: laying, legs up, sexy - laying back, legs up, a sexy display\",\"GS261: on stomach, looking back, sexy - on her stomach, a sexy look back\",\"GS267: all fours, suggesting - all fours on the floor, a suggestive offer\",\"GS271: waiting, sexy, thinking - lounging, waiting, a sexy thought\",\"GS275: on stomach, sexy - laying on her stomach, sexy\",\"GS282: seated, sexy - seated on the floor, sexy lounging\",\"GS285: sexy, suggesting - a sexy display, suggesting\",\"GS305: twerking on ground - ass shaking twerk on the ground\",\"GS306: twerking on ground - a ground twerk, ass shaking (twin)\",\"GS311: all fours, provocative - all fours, a provocative display\",\"GS316: all fours, provocative - provocative on all fours (twin)\"]"
    ; REV-152 (cont.): the remaining six catalog-bearing vibes.
    ElseIf vibe == "ground_idle"
        Return "[\"GS128: squatting, looking at ground - squatting, eyes down\",\"GS256: sitting, playful - sitting on the floor, playful\",\"GS270: recovering, exhausted - spent and exhausted, recovering\",\"GS276: on stomach, bored - bored, laying on her stomach\",\"GS278: on stomach, moving legs, bored - bored on her stomach, legs fidgeting\",\"GS286: seated, exhausted - seated and spent, exhausted\",\"GS287: exhausted, trauma - collapsed, exhausted, spent\",\"GS289: on stomach, bored - bored laying, stomach down\",\"GS295: kneeled - kneeling on the ground, lowered\",\"GS296: exhausted, trauma - a spent collapse (twin)\",\"GS313: back resting - laying back, resting\",\"GS314: back resting - resting on her back (twin)\",\"GS317: laying laterally - laying on her side\",\"GS697: seated, dark-souls-by-fire (M ok) - seated brooding by the fire, male ok\",\"GS698: seated, hugging legs - seated hugging her legs, vulnerable\",\"GS699: hand on stomach (pregnant?) - seated, hand on her stomach\",\"GS706: looking down, thinking - seated quiet, thinking, eyes down\",\"GS712: resting, dark-souls (M ok) - a brooding rest, male ok\"]"
    ElseIf vibe == "workout"
        Return "[\"GS156: knees up (kinda sexy) - a knees-up exercise, kinda sexy\",\"GS182: jumping, training - jumping jacks, cardio training\",\"GS658: jumping warmup - a jumping warmup, cardio\",\"GS659: push-ups - push-ups, strength exercise\",\"GS660: deadlifts - deadlifts, a strength lift\",\"GS661: glute lateral raises - glute raises, a butt workout\",\"GS663: abs - abs and core, crunches\",\"GS664: glute bridge - a glute bridge, butt and hips workout\",\"GS665: static footing - a static stance, footing drill\",\"GS666: abs, legs up - legs-up abs, core work\",\"GS667: mountain climbers - mountain climbers, cardio\",\"GS672: lateral leg raises - lateral leg raises, legs workout\",\"GS676: squats - squats, legs and butt exercise\",\"GS681: leg up + abs - one leg up, abs and core\",\"GS683: glute bridge - a glute bridge, butt workout (twin)\",\"GS690: footing, hands on hips - a stance drill, hands on hips\"]"
    ElseIf vibe == "stretch"
        Return "[\"GS662: stretching - a long reach, stretching out\",\"GS668: dolphin stretch - a dolphin pose, yoga stretch\",\"GS669: leg stretch - a leg stretch, reaching\",\"GS670: back stretch - a back stretch, reaching\",\"GS671: wall stretch - leaning wall stretch\",\"GS673: all-fours stretch - all fours, a yoga stretch\",\"GS674: sun salute yoga - a sun salute, yoga flow\",\"GS678: leg-stride stretch - legs in stride, stretching\",\"GS679: hip stretch (ground) - a hip stretch on the ground\",\"GS680: butt-up stretch - butt up, a reaching stretch\",\"GS684: back/butt-up stretch - back arched, butt up, stretching\",\"GS686: standing back stretch - a standing back stretch\",\"GS689: legs-up yoga - legs up, a yoga stretch\",\"GS691: arms-up side stretch - arms up, a side stretch\"]"
    ElseIf vibe == "submission"
        Return "[\"GS51: cuffed, dancing (prisoner) - cuffed, a captive dance\",\"GS700: tied, kneeling, hands behind head - tied, kneeling, surrender\",\"GS705: surrendered, hands up - hands up, surrendered and yielding\",\"GS707: standing, hands tied back - standing, hands tied behind back\",\"GS708: standing, hands tied back - tied standing (twin)\",\"GS709: on ground, tied - tied on the ground, helpless\",\"GS710: on ground, tied, resting on side - tied, resting on side, bound\"]"
    ElseIf vibe == "plead"
        Return "[\"GS701: sorry (Japanese dogeza) - a dogeza apology, kneeling to grovel\",\"GS702: praying / sorry - hands clasped, praying, a plea\",\"GS703: begging for money - begging, a desperate plea for money\"]"
    ElseIf vibe == "idle"
        Return "[\"GS131: support / friendship gesture - a friendship gesture, reassuring\",\"GS135: shy, nervous, contained - shy and nervous, contained\",\"GS147: hands behind, slightly sexy - hands behind back, a slightly sexy stance\",\"GS177: arms crossed, suggesting - arms crossed, stern and suggesting\",\"GS196: victory pose (<=5s) - a victory pose, triumph\",\"GS624: idle - an idle waiting stance\",\"GS628: idle - an idle waiting stance (twin)\",\"GS629: fist battle prep - fists up, battle prep, ready\",\"GS632: mad, arms crossed - angry, arms crossed, stern\",\"GS639: shy waiting - shy and waiting, a nervous idle\"]"
    EndIf
    Return ""
EndFunction

; REV-163: _VibePoseOptions' JSON array flattened to plain prompt prose for
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

; REV-163: ONE library entry for the consideration prompt's pose catalog --
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

; ── REV-167b D-3 SHAPE 1 / D-4 / D-5: the dialogue lane's tier-3 variant ──────
; selection. Spec: docs/features/The Pose Pipeline - Full Audit & Improvement.md
; §5 D-3 (Shape 1), D-4 (dispatch plumbing), D-5 (fallback ladder), §12.6 verdicts.
; ALTITUDE DEVIATION (receipted in PROJECT_STATE S195): the variant-resolution
; step sits at the EXECUTOR WRAPPER, not inside _PoseVibe itself -- route 2 is
; shared by the Sheogorath consideration lane (OnSheoConsideration), which has
; already spent its Shape-2 one-pass call; putting the step inside _PoseVibe
; would double-spend that lane. The 5-arg _PoseVibe shape is preserved (C-4).
; D-1 verdicts: every catalog-bearing pool (the 12 GS pools) is TARGETED; the
; Babo single-event vibes + the aroused pair are DICE-BY-EXCEPTION (no call
; spendable) -- they skip straight to today's draw everywhere (D-5: no lane,
; no pool, no configuration ends up worse than shipped).
Bool Function _VibeIsTargeted(String vibe)
    Return _VibePoseOptions(vibe) != ""
EndFunction

Function _VariantPendingClear()
    _variantPendingActor = None
    _variantPendingVibe = ""
    _variantPendingLabel = ""
    _variantPendingStamp = 0.0
EndFunction

; D-5 leg 1: dispatch refused -> the shipped dice draw, byte-for-byte, same
; turn. D-5 leg 2 (lost callback) rides the 3s sweep via _VariantPendingSweep.
Function _PoseVibeVariant(Actor ak, String vibe, String label)
    If !_VibeIsTargeted(vibe)
        Debug.Trace("[SNAnimGS] variant pick skipped: dice-by-exception pool '" + vibe + "' (REV-167b D-1 verdict) -- shipped dice draw")
        _PoseVibe(ak, vibe, label, "", 2, None)
        Return
    EndIf
    _variantPendingActor = ak
    _variantPendingVibe = vibe
    _variantPendingLabel = label
    _variantPendingStamp = Utility.GetCurrentRealTime()
    String ctx = "{\"npcName\":\"" + ak.GetDisplayName() + "\",\"vibe\":\"" + vibe + "\",\"label\":\"" + label + "\",\"variants\":\"" + _MuseCatalogOptions(vibe) + "\"}"
    Int sent = SkyrimNetApi.SendCustomPromptToLLM("gsanim_variant_pick", "", ctx, Self as Quest, "SkyrimNet_AnimationsGS", "OnVariantPick")
    If sent != 1
        Debug.Trace("[SNAnimGS] variant pick dispatch refused (rc=" + sent + ", pool '" + vibe + "'): D-5 fallback -- shipped dice draw (shape-1 dialogue lane)")
        _VariantPendingClear()
        _PoseVibe(ak, vibe, label, "", 2, None)
    Else
        Debug.Trace("[SNAnimGS] variant pick dispatched (shape-1 dialogue lane): " + ak.GetDisplayName() + " -> pool '" + vibe + "'")
    EndIf
EndFunction

; D-5 leg 2: the answer never landed -> dice draw, never a silent no-op. The
; sweep polls this every pass while a pick is pending (20s grace).
Function _VariantPendingSweep(Float afNow)
    If _variantPendingActor && afNow - _variantPendingStamp > 20.0
        Actor ak = _variantPendingActor
        String vibe = _variantPendingVibe
        String label = _variantPendingLabel
        _VariantPendingClear()
        Debug.Trace("[SNAnimGS] variant pick timed out (no answer in 20s, pool '" + vibe + "'): D-5 fallback -- shipped dice draw")
        _PoseVibe(ak, vibe, label, "", 2, None)
    EndIf
EndFunction

; SendCustomPromptToLLM callback for gsanim_variant_pick.prompt (the REV-152
; machinery at its corrected altitude: fed the REAL tag-carrying corpus and
; the moment's pose label). Contract: "CLIP: <GS key>" (the exact move within
; the already-picked member pool); anything else degrades to the dice draw.
Function OnVariantPick(String response, Int success)
    Actor ak = _variantPendingActor
    String vibe = _variantPendingVibe
    String label = _variantPendingLabel
    _VariantPendingClear()
    If !ak || vibe == ""
        Debug.Trace("[SNAnimGS] variant pick answer with no pending fire -- dropped")
        Return
    EndIf
    If ak.IsDead() || ak.IsInCombat()
        Debug.Trace("[SNAnimGS] variant pick dropped - actor-local guard failed at fire time: " + ak.GetDisplayName())
        Return
    EndIf
    If success != 1 || response == ""
        Debug.Trace("[SNAnimGS] variant pick miss (success=" + success + ", pool '" + vibe + "'): D-5 fallback -- shipped dice draw")
        _PoseVibe(ak, vibe, label, "", 2, None)
        Return
    EndIf
    Int iClip = StringUtil.Find(response, "CLIP:")
    String sClip = ""
    If iClip >= 0
        sClip = _TrimTok(StringUtil.Substring(response, iClip + 5, StringUtil.GetLength(response) - iClip - 5))
    EndIf
    String sForceEvent = ""
    If sClip != ""
        String csvVar = _VibeEventsFor(ak, vibe)
        If StringUtil.Find("," + csvVar + ",", "," + sClip + ",") != -1
            sForceEvent = sClip
        Else
            Debug.Trace("[SNAnimGS] variant pick CLIP '" + sClip + "' NOT in pool '" + vibe + "' -- degrading to dice draw")
        EndIf
    Else
        Debug.Trace("[SNAnimGS] variant pick: no CLIP in answer -- dice draw within the pool")
    EndIf
    If _PoseVibe(ak, vibe, label, sForceEvent, 2, None)
        Debug.Trace("[SNAnimGS] variant pick FIRE: " + ak.GetDisplayName() + " -> pool '" + vibe + "' clip '" + sForceEvent + "' (shape-1 dialogue lane)")
    Else
        Debug.Trace("[SNAnimGS] variant pick REFUSED by the fire chain (reason per the refusal sentinel above): " + ak.GetDisplayName() + " -- D-5 does not force a refused fire")
    EndIf
EndFunction

; REV-163: the full pose catalog for the muse consideration context pack --
; every fireable library member, one entry per line. The separators are the
; two-character JSON escape \n (written \\n here; decoded to a real newline
; at render), and the text carries no quotes/backslashes, so the pack stays
; valid JSON. Order matches the prompt's library/male-safe split and the
; _MuseFireVibe allowlist -- the catalog and the fireable set are ONE list
; (the REV-25 2a discipline).
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

; The post-fire bookkeeping of the muse direct fire (extracted REV-152; REV-163
; note: the decision-callback path is retired with the picker, so this now
; serves the single consideration-fire path -- sentinels, notification and
; interval re-arm stay identical).
; [REV-174 D3 4.5] SIGNATURE EXTENSION: the success bookkeeping now also
; carries the composed desc + REACT pick + resolved target for the four-lane
; fan-out (reaction lanes replace the REV-159 narration trigger; the narr
; lane's RegisterEvent DESC is the composed sentence, intro drafts live
; yaml-side). sDesc/sReact may be empty (random legs) -- the fan-out handles
; the all-enabled random posture. akTarget may be None (desc composes without
; the target slot; open flag 3, descriptors-v2).
Function _MuseFireSuccess(Actor ak, String sPose, Float fStamp, String sDesc, String sReact, Actor akTarget)
    ; REV-26 Task 1b: male fires carry an explicit [male vocab] tag.
    If _SexOf(ak) == 0
        Debug.Trace("[SNAnimGS] sanguine mode direct fire: " + ak.GetDisplayName() + " (" + sPose + ") [male vocab]")
    Else
        Debug.Trace("[SNAnimGS] sanguine mode direct fire: " + ak.GetDisplayName() + " (" + sPose + ")")
    EndIf
    ; REV-85 aroused-lean leg 3: the [arousal lean] sentinel (unchanged).
    If StringUtil.Find(_sMuseArous, "high") != -1
        Debug.Trace("[SNAnimGS] sanguine mode direct fire: high-arousal seed - [arousal lean] applies")
    EndIf
    ; REV-25 Task 2e -> [REV-174a D4]: on-screen fire receipt, now gated by the
    ; global Debug Notifications toggle (Settings page, GSAnim.DebugNotify,
    ; DEFAULT OFF). ASCII-only.
    _GSDebugNotify("Sanguine Mode - " + ak.GetDisplayName() + " (" + sPose + ")")
    ; [REV-178d Leg 1] ARM-AT-DISPATCH (S244 verdict, 2026-11-04: armed-at-
    ; fire = a failed attempt burned a whole cadence slot, and the answer
    ; round-trip drifted the clock at every fire). The MuseGlobal write is
    ; REMOVED here: both _MuseTick dispatch branches already stamp MuseGlobal
    ; at CALL time ("Stamped at CALL time... bounds spend even if the response
    ; never lands"), so cadence = the configured interval, decoupled from the
    ; LLM failure rate and the answer latency. fStamp survives as a FIRE-TIME
    ; RECEIPT ONLY (a fresh observability key, never read as a gate).
    StorageUtil.SetFloatValue(None, "GSAnim.MuseLastFire", fStamp)
    Debug.Trace("[SNAnimGS] fire-time receipt stamp (observability only, no re-arm): " + ak.GetDisplayName() + " (REV-178d Leg 1)")
    ; [REV-174 D3 4.1/4.5] the REV-159 narration trigger is SUPERSEDED by the
    ; four-lane fan-out (gsanim_sanguine_mode_narr is now the NARR LANE's
    ; RegisterEvent with the composed DESC; the old GSAnim.SanguineModeNarr
    ; gate is superseded by GSAnim.SanguineLane_narr ([REV-174e Leg 4]: the
    ; legacy key + its MCM row are REMOVED, orphaned, no migration; the lane
    ; toggles are the sole gate).
    _GSLaneFire("Sanguine", ak, akTarget, sDesc, sReact, False)
    ; [REV-178b Leg 1] the moments ledger record (post-fire; the NEXT ask's
    ; pack renders the fact line from it).
    String sMomT = ""
    If akTarget
        sMomT = akTarget.GetDisplayName()
    EndIf
    _MomentsLedgerRecord(ak.GetDisplayName(), sMomT, sPose)
EndFunction

; ============================================================================
; [REV-174a D4/A38b] GLOBAL DEBUG NOTIFICATIONS gate: the Settings-page
; "Debug Notifications" toggle (GSAnim.DebugNotify, DEFAULT OFF -- additive
; registry: every fire/receipt corner message in this script routes through
; here, so later modules add calls without new plumbing). Dual purpose of
; record: debugging aid + optional who-is-doing-what awareness for players who
; want it; OFF preserves immersion. Mode ON/OFF activation feedback (the
; hotkey's own confirmation) stays ungated -- it answers a user action, not a
; background fire.
Function _GSDebugNotify(String msg)
    If StorageUtil.GetIntValue(None, "GSAnim.DebugNotify", 0) == 1
        Debug.Notification(msg)
    EndIf
EndFunction

; [REV-174 D3 leg 3] GS REACTION LANES + REACT ARBITRATION (design doc 4/6,
; the GS mirror of the Baka machinery). Lane bitmask: 1=narr 2=thought
; 4=pspeech 8=pthought; ALL FOUR ON by default (A15 / R-LANE-DEFAULTS).
; Toggles: GSAnim.ReactArbitration (master, default 1) +
; GSAnim.<Mode>Lane_{narr|thought|pspeech|pthought} (each default 1).
; ============================================================================

; [REV-174 D3 4.6] the enabled lane set, read FRESH per fire (no caching).
Int Function _GSLaneEnabledSet(String asMode)
    String sPfx = "GSAnim.SanguineLane_"
    If asMode == "Sheogorath"
        sPfx = "GSAnim.SheogorathLane_"
    ElseIf asMode == "Pose"
        ; [REV-178b Leg 2.3] the neutral pose fanned set (A15-mirror defaults,
        ; same defaults as the modes: narr/pspeech/pthought ON, thought OFF).
        sPfx = "GSAnim.PoseLane_"
    EndIf
    Int m = 0
    If StorageUtil.GetIntValue(None, sPfx + "narr", 1) == 1
        m = m + 1
    EndIf
    If StorageUtil.GetIntValue(None, sPfx + "thought", 0) == 1   ; [REV-174a D2e] NPC-thought lane DEFAULT OFF (user fallback ruling; toggle still available)
        m = m + 2
    EndIf
    If StorageUtil.GetIntValue(None, sPfx + "pspeech", 1) == 1
        m = m + 4
    EndIf
    If StorageUtil.GetIntValue(None, sPfx + "pthought", 1) == 1
        m = m + 8
    EndIf
    Return m
EndFunction

; leading/trailing trim (Papyrus has no Trim(); the REV-21 lesson).
String Function _GSTrim(String s)
    While StringUtil.GetLength(s) > 0 && StringUtil.GetNthChar(s, 0) == " "
        s = StringUtil.Substring(s, 1, StringUtil.GetLength(s) - 1)
    EndWhile
    While StringUtil.GetLength(s) > 0 && StringUtil.GetNthChar(s, StringUtil.GetLength(s) - 1) == " "
        s = StringUtil.Substring(s, 0, StringUtil.GetLength(s) - 1)
    EndWhile
    Return s
EndFunction

; ASCII lowercase (letters only; Papyrus has no ToLower).
String Function _GSLower(String asIn)
    String s = ""
    Int i = 0
    Int len = StringUtil.GetLength(asIn)
    While i < len
        String c = StringUtil.GetNthChar(asIn, i)
        Int code = StringUtil.AsOrd(c)
        If code >= 65 && code <= 90
            c = StringUtil.AsChar(code + 32)
        EndIf
        s = s + c
        i += 1
    EndWhile
    Return s
EndFunction

; manual str-replace (SKSE StringUtil has NO Replace; Find+Substring loop).
String Function _GSReplace(String asIn, String asFind, String asWith)
    If asFind == "" || asIn == ""
        Return asIn
    EndIf
    String s = asIn
    Int iPos = StringUtil.Find(s, asFind)
    While iPos != -1
        s = StringUtil.Substring(s, 0, iPos) + asWith + StringUtil.Substring(s, iPos + StringUtil.GetLength(asFind))
        iPos = StringUtil.Find(s, asFind, iPos + StringUtil.GetLength(asWith))
    EndWhile
    Return s
EndFunction

; [REV-174 D3 6.1/6.2] the REACT: parse -- the A13c keyword set (narr,
; thought, pspeech, pthought, all, none), comma/plus separated, case-blind
; (rev-22 rider). 0 = the none pick; -1 = unparseable/contradictory
; (fail-open). No bitwise ops in Papyrus -- additive disjoint powers of two.
Int Function _GSReactParseLanes(String asReact)
    If asReact == ""
        Return -1
    EndIf
    String s = _GSLower(_GSTrim(asReact))
    s = _GSReplace(s, "+", ",")
    String[] toks = StringUtil.Split(s, ",")
    Int mask = 0
    Bool bAnyTok = False
    Bool bAll = False
    Bool bNone = False
    Int i = 0
    While i < toks.Length
        String t = _GSTrim(toks[i])
        If t != ""
            bAnyTok = True
            If t == "all"
                bAll = True
            ElseIf t == "none"
                bNone = True
            ElseIf t == "narr"
                mask = mask + 1
            ElseIf t == "thought"
                mask = mask + 2
            ElseIf t == "pspeech"
                mask = mask + 4
            ElseIf t == "pthought"
                mask = mask + 8
            Else
                Return -1   ; unknown keyword -> fail-open (6.2)
            EndIf
        EndIf
        i += 1
    EndWhile
    If !bAnyTok
        Return -1
    EndIf
    If bAll
        mask = 15
    EndIf
    If bNone && mask == 0
        Return 0
    EndIf
    If bNone && mask != 0
        Return -1   ; 'none' mixed with lanes = contradictory -> fail-open
    EndIf
    Return mask
EndFunction

; [REV-174 D3 4.5/6.2 -> REV-174j] THE GS ARBITRATION + FAN-OUT (fully
; aligned with the Baka mirror): master GSAnim.ReactArbitration (default 1);
; the pose GENERAL cue fires unconditionally at the pose fire site (6.2
; fact-cue floor). REV-174j A37-v5 (user ruling 2026-11-01 v5): AT MOST ONE
; fanned lane per action -- never 3 rendered triggers. Arbitration ON: the
; answer's REACT: pick, intersected with enabled, trimmed to ONE lane
; (non-narr preferred -- the general cue already narrates; a lone narr pick
; still fires the fanned narr lane). Random legs / toggle OFF / missing or
; invalid REACT / EMPTY intersections / repeat picks -> the NO-REPEAT
; one-lane rotation (the 174g Baka fallback, mirrored here). A single
; enabled lane fires 100%. Every outcome sentinel'd (6.4).
Int _iGSLaneLastSanguine = 0
Int _iGSLaneLastSheogorath = 0
; [REV-178b Leg 2.3] the pose-lane rotation member (the 174f Action mirror).
Int _iGSLaneLastPose = 0

; [REV-178b Leg 1] THE MOMENTS LEDGER (user ruling 2026-11-0X "spread the
; love around when there is a crowded room"): in-memory per-session ring of
; the last N=5 Sanguine-mode fire records (subject + target display names),
; rendered as a plain pack fact -- NO mechanical exclusion, no forced
; rotation, no degrade (v1; the soft planner-staged ledger returns only on
; dogfood distribution evidence with fact+guidance live).
String[] _sMomSubj
String[] _sMomTarg
String[] _sMomPose
Int _iMomNext = 0
Int _iMomCount = 0

Function _MomentsLedgerRecord(String asSubj, String asTarg, String asPose = "")
    If _sMomSubj.Length == 0
        _sMomSubj = New String[5]
        _sMomTarg = New String[5]
        _sMomPose = New String[5]
    EndIf
    _sMomSubj[_iMomNext] = asSubj
    _sMomTarg[_iMomNext] = asTarg
    _sMomPose[_iMomNext] = asPose
    _iMomNext = (_iMomNext + 1) % 5
    If _iMomCount < 5
        _iMomCount += 1
    EndIf
    ; [REV-178d Leg 3.3] the pose ring rides the same record (the RecentPoses
    ; fact line for the S244 variety clause; fact + suggestion only).
    Debug.Trace("[SNAnimGS] moments ledger record: subj='" + asSubj + "' targ='" + asTarg + "' pose='" + asPose + "' (count " + _iMomCount + "/5) -- REV-178b Leg 1 / REV-178d Leg 3.3")
EndFunction

; [REV-178d Leg 3.3] RecentPoses text: the last N=5 fired pose labels,
; newest-first, "; "-joined; "" when empty (the momentsRecently pattern:
; the template gates on the field's truthiness).
String Function _MomentsPosesText()
    If _iMomCount == 0
        Return ""
    EndIf
    String sOut = ""
    Int i = 0
    Int idx = (_iMomNext - 1 + 5) % 5
    While i < _iMomCount
        If _sMomPose[idx] != ""
            If sOut != ""
                sOut = sOut + "; "
            EndIf
            sOut = sOut + _sMomPose[idx]
        EndIf
        idx = (idx - 1 + 5) % 5
        i += 1
    EndWhile
    Return sOut
EndFunction

; The rendered fact line: "Name (S<n>, T<m>); ..." newest-first, or "" when
; the ledger is empty (the prompt template gates on the field's truthiness).
String Function _MomentsLedgerText()
    If _iMomCount == 0
        Return ""
    EndIf
    String sOut = ""
    Int i = 0
    Int idx = (_iMomNext - 1 + 5) % 5
    While i < _iMomCount
        String sRec = _sMomSubj[idx]
        If _sMomTarg[idx] != ""
            sRec = sRec + " -> " + _sMomTarg[idx]
        EndIf
        sRec = sRec + "; "
        If i == 0
            sRec = "most recent: " + sRec
        EndIf
        sOut = sOut + sRec
        idx = (idx - 1 + 5) % 5
        i += 1
    EndWhile
    Return sOut
EndFunction

Int Function _GSLaneLastGet(String asMode)
    If asMode == "Sheogorath"
        Return _iGSLaneLastSheogorath
    ElseIf asMode == "Pose"
        Return _iGSLaneLastPose
    EndIf
    Return _iGSLaneLastSanguine
EndFunction

Function _GSLaneLastSet(String asMode, Int aiLane)
    If asMode == "Sheogorath"
        _iGSLaneLastSheogorath = aiLane
    ElseIf asMode == "Pose"
        _iGSLaneLastPose = aiLane
    Else
        _iGSLaneLastSanguine = aiLane
    EndIf
EndFunction

; [REV-178b Leg 2.3] returns the FIRED lane mask (0 = no lane; callers gate
; narr-sensitive secondary cues on the narr bit). Void callers ignore it.
Int Function _GSLaneFire(String asMode, Actor ak, Actor akTarget, String asDesc, String asReact, Bool abRandomLeg)
    String sPfx = "gsanim_sanguine_mode_"
    If asMode == "Sheogorath"
        sPfx = "gsanim_sheogorath_mode_"
    ElseIf asMode == "Pose"
        ; [REV-178b Leg 2.3] the neutral pose fanned set (no mode branding).
        sPfx = "gsanim_pose_lane_"
    EndIf
    Int iEnabled = _GSLaneEnabledSet(asMode)
    If iEnabled == 0
        Debug.Trace("[SNAnimGS] lane fan-out: NO LANES ENABLED (" + asMode + ") -- desc persists to trace only -- REV-174 D3 6.2")
        _GSGeneralAdjudicate(0)   ; [REV-178a Leg 6] all lanes off -> general alone
        Return 0
    EndIf
    Int iEnabledCount = 0
    Int v = 1
    While v <= 8
        If (iEnabled / v) % 2 == 1
            iEnabledCount += 1
        EndIf
        v = v * 2
    EndWhile
    Int iLastLane = _GSLaneLastGet(asMode)
    Int iFire = 0
    If iEnabledCount == 1
        iFire = iEnabled
        Debug.Trace("[SNAnimGS] lane arbitration: exactly ONE lane enabled (" + asMode + ") -- fires 100%, no-repeat SIDESTEPPED -- REV-174j A37")
    ElseIf !abRandomLeg && StorageUtil.GetIntValue(None, "GSAnim.ReactArbitration", 1) == 1
        Int iPicked = _GSReactParseLanes(asReact)
        If iPicked == -1
            Debug.Trace("[SNAnimGS] lane arbitration: REACT missing/invalid ('" + asReact + "') -- ROTATION FALLBACK -- REV-174j A37")
        ElseIf iPicked == 0
            Debug.Trace("[SNAnimGS] lane arbitration: REACT none pick -- no lanes fire (hollow-action watch item) -- REV-174 D3 6.2")
            _GSGeneralAdjudicate(0)   ; [REV-178a Leg 6] no lane fired -> general alone
            Return 0
        Else
            iFire = 0
            v = 1
            While v <= 8
                If (iPicked / v) % 2 == 1 && (iEnabled / v) % 2 == 1
                    iFire = iFire + v
                EndIf
                v = v * 2
            EndWhile
            If iFire == 0
                Debug.Trace("[SNAnimGS] lane arbitration: intersection EMPTY (picked lanes all disabled) -- ROTATION FALLBACK -- REV-174j A37")
            Else
                ; [REV-174j A37-v5] ONE-FANNED-LANE CAP: the pose general cue
                ; already narrates unconditionally; the pick is trimmed to
                ; EXACTLY ONE fanned lane (never 3 rendered triggers).
                ; Non-narr preferred on multi-lane picks; a lone narr pick
                ; still fires the fanned narr lane.
                Int iCapped = 0
                Int vC = 2
                While vC <= 8 && iCapped == 0
                    If (iFire / vC) % 2 == 1
                        iCapped = vC
                    EndIf
                    vC = vC * 2
                EndWhile
                If iCapped == 0 && (iFire % 2) == 1
                    iCapped = 1
                EndIf
                If iCapped != iFire
                    Debug.Trace("[SNAnimGS] lane arbitration: CAP-TRIM (ONE fanned lane only; fire " + iFire + " -> " + iCapped + ") -- REV-174j A37")
                    iFire = iCapped
                EndIf
                If iFire == iLastLane
                    Debug.Trace("[SNAnimGS] lane arbitration: NO-REPEAT guard (pick repeats last fire " + iLastLane + ") -- ROTATION FALLBACK -- REV-174j A37")
                    iFire = 0
                Else
                    Debug.Trace("[SNAnimGS] lane arbitration: REACT '" + asReact + "' picked=" + iPicked + " enabled=" + iEnabled + " -> fire=" + iFire + " -- REV-174j A37")
                EndIf
            EndIf
        EndIf
    ElseIf abRandomLeg
        Debug.Trace("[SNAnimGS] lane arbitration: random leg (no LLM in the loop) -- ROTATION FALLBACK -- REV-174j A37")
    Else
        Debug.Trace("[SNAnimGS] lane arbitration: REACT toggle OFF (manual) -- ROTATION FALLBACK -- REV-174j A37")
    EndIf
    If iFire == 0
        ; [REV-174g A37 -> REV-174j GS MIRROR] the NO-REPEAT ROTATION: start
        ; at the lane AFTER the last fired one, take the first enabled lane
        ; that is not the last fired (circular, guard 4); collapse to the
        ; last lane only when it is the ONLY enabled lane.
        Int vRot = 1
        If iLastLane == 2
            vRot = 4
        ElseIf iLastLane == 4
            vRot = 8
        ElseIf iLastLane == 8
            vRot = 1
        EndIf
        Int iGuard = 0
        While iGuard < 4 && iFire == 0
            If vRot != iLastLane && (iEnabled / vRot) % 2 == 1
                iFire = vRot
            EndIf
            vRot = vRot * 2
            If vRot > 8
                vRot = 1
            EndIf
            iGuard += 1
        EndWhile
        If iFire == 0
            iFire = iLastLane
            Debug.Trace("[SNAnimGS] lane arbitration: rotation collapsed to the last-fired lane (single-lane set) -- REV-174g A37")
        EndIf
        Debug.Trace("[SNAnimGS] lane arbitration: ONE-LANE ROTATION (REV-174g A37): mode=" + asMode + " enabled=" + iEnabled + " last=" + iLastLane + " -> fire=" + iFire)
    EndIf
    _GSLaneLastSet(asMode, iFire)
    _GSGeneralAdjudicate(iFire)   ; [REV-178a Leg 6] narr pick suppresses; non-narr rides alongside
    v = 1
    While v <= 8
        If (iFire / v) % 2 == 1
            String sLane = "narr"
            If v == 2
                sLane = "thought"
            ElseIf v == 4
                sLane = "pspeech"
            ElseIf v == 8
                sLane = "pthought"
            EndIf
            ; [REV-174a D1b] PLAYER-LANE BINDING: the pspeech/pthought events
            ; bind the PLAYER as the event's target actor (DevKit response
            ; tables pair player-voiced response types with player-bound
            ; events; the previous None binding left the event NPC-attached
            ; and the renderer never surfaced the player speech/thought).
            If v == 4 || v == 8
                SkyrimNetApi.RegisterEvent(sPfx + sLane, asDesc, ak, PlayerRef)
            Else
                SkyrimNetApi.RegisterEvent(sPfx + sLane, asDesc, ak, None)
            EndIf
            Debug.Trace("[SNAnimGS] lane FIRED: " + sPfx + sLane + " (" + asMode + ", " + ak.GetDisplayName() + ") -- REV-174 D3")
        EndIf
        v = v * 2
    EndWhile
    Return iFire   ; [REV-178b Leg 2.3] the fired-mask receipt (narr bit gate)
EndFunction

; [REV-174 D3 3.2 GS] THE GS TARGET ROSTER (the Baka _akLaneRoster mirror):
; proximity-to-subject order, cap 10, built FRESH at every consideration pack
; build (stage 1 = the tick's subject draw through the scan pool + walk
; guards -- _MuseTick/_OdAutoPose own that half; stage 2 = THIS roster). The
; scan pool is already policy-admitted (_DaemonScan); the roster adds only
; subject-proximity + not-subject + not-dead. Downed candidates stay in the
; scan pool's admission (the roster reports, the library constrains -- the
; Baka 3.2 frame). The player is appended last when within radius (the
; prompt's roster frames them as "nearest first, up to 10").
Actor[] _akMuseRoster = None
Int     _iMuseRosterN   = 0
Int     _iMuseRosterCap = 10
String  _sGSLastFiredEvent = ""   ; [A21] the clip key _PoseVibe actually sent

Function _GSMuseRosterInsert(Actor akSubject, Actor akC)
    Float fD = akSubject.GetDistance(akC)
    Int k = _iMuseRosterN
    While k > 0 && akSubject.GetDistance(_akMuseRoster[k - 1]) > fD
        _akMuseRoster[k] = _akMuseRoster[k - 1]
        k -= 1
    EndWhile
    _akMuseRoster[k] = akC
    _iMuseRosterN += 1
EndFunction

Int Function _GSMuseRosterBuild(Actor akSubject, Int aiPoolN)
    If !_akMuseRoster || _akMuseRoster.Length < _iMuseRosterCap
        _akMuseRoster = New Actor[20]   ; [REV-174a A46] buffer stays 20; the cap is
                                        ; the standing 10 (Wide retired)
    EndIf
    _iMuseRosterN = 0
    Int i = 0
    While i < aiPoolN && _iMuseRosterN < _iMuseRosterCap
        Actor akT = _DaemonPool[i]
        If akT && akT != akSubject && !akT.IsDead() && akSubject.GetDistance(akT) <= fDaemonRadius
            _GSMuseRosterInsert(akSubject, akT)
        EndIf
        i += 1
    EndWhile
    ; [REV-174a A34a] PLAYER-TARGETING: the player is appended ONLY when the GS
    ; module's "Player can be targeted" toggle is ON (GSAnim.PlayerTargetable,
    ; default 0 = OFF). With it OFF the roster contains NPCs only -- the LLM can
    ; no longer pick the player as TARGET, closing the D1a stall (every pick was
    ; Hadrian -> REV-166 guard -> refusal -> credits burned). The toggle lives on
    ; the GS Poses MCM page (A34b relocation; the old Settings-page location is
    ; superseded).
    If _iMuseRosterN < _iMuseRosterCap
        If StorageUtil.GetIntValue(None, "GSAnim.PlayerTargetable", 0) == 1 \
           && !PlayerRef.IsDead() && akSubject.GetDistance(PlayerRef) <= fDaemonRadius
            _GSMuseRosterInsert(akSubject, PlayerRef)
        EndIf
    EndIf
    Debug.Trace("[SNAnimGS] two-stage roster built: subject=" + akSubject.GetDisplayName() \
        + " n=" + _iMuseRosterN + " (cap " + _iMuseRosterCap + ", pool " + aiPoolN + ") -- REV-174 D3 3.2 GS")
    Return _iMuseRosterN
EndFunction

; [REV-174 D3 3.2 GS / A16] the candidates[] JSON -- keys matching the
; consideration prompts' {{ c.* }} placeholders EXACTLY (name/sex/uuid/state/
; relationshipGloss). GS lean pack: relationshipGloss is empty (no gloss
; machinery GS-side; the Sanguine template guards it with {% if %}). Names are
; JSON-escaped via _GSJsonEsc (names can carry quotes).
String Function _GSMuseRosterJson()
    String s = ""
    Int i = 0
    While i < _iMuseRosterN
        Actor akC = _akMuseRoster[i]
        If akC
            If i > 0
                s = s + ","
            EndIf
            String sSex = "male"
            If _SexOf(akC) == 1
                sSex = "female"
            EndIf
            s = s + "{\"name\":\"" + _GSJsonEsc(akC.GetDisplayName()) + "\",\"sex\":\"" + sSex \
                + "\",\"uuid\":" + _UuidJsonLiteralCtx(akC) \
                + ",\"state\":\"" + _GSMuseStateLine(akC) \
                + "\",\"relationshipGloss\":\"\"}"
        EndIf
        i += 1
    EndWhile
    Return s
EndFunction

String Function _GSMuseStateLine(Actor akC)
    String s = "standing nearby"
    If akC == PlayerRef
        s = "the player, watching"
    EndIf
    If _IsBusyElsewhere(akC)
        s = s + "; engaged"
    EndIf
    Return s
EndFunction

String Function _GSJsonEsc(String asIn)
    String s = _GSReplace(asIn, "\\", "\\\\")
    s = _GSReplace(s, "\"", "\\\"")
    Return s
EndFunction

; ============================================================================
; [REV-178 L4] NARRATIVE SELECTION -- the shared pool service (GS side).
; §6.1 mechanics: sticky 5 + conversation-priority (vanilla IsInDialogue()/
; GetDialogueTarget() pair-priority, §22 planner ruling; bark/menu noise
; accepted for ordering), proximity fill, churn recompute, player =
; TARGET-pool constant slot only (OR2 -- NO subject path for the player,
; no flag without a new ruling).
; ============================================================================
Actor[] _akNarrSubjectPool          ; the per-session sticky pool (in-memory, §6.1.7)
Int     _iNarrSubjectPoolN = 0
Actor   _akNarrLastSubject = None   ; stickiness: previous tick's SUBJECT
Actor   _akNarrLastTarget = None    ; stickiness: previous tick's TARGET
Bool    _bSAPresent = False         ; SA presence guard, resolved once
Int     _bSAResolved = 0            ; first-call sentinel state (0 unknown)

; [REV-178 L4] the SA presence guard (the OSLAroused REV-82 precedent
; generalized per §22): SKSE.GetPluginVersion BEFORE any SeverActionsNative
; call. Plugin-name string of record: "SeverActions" (the DLL ships as
; SeverActions.dll, SeverActions-4.5.0-FOMOD; dogfood verifies the sentinel).
Bool Function _GSSAPresent()
    If _bSAResolved == 0
        _bSAResolved = 1
        _bSAPresent = SKSE.GetPluginVersion("SeverActionsNative") > 0
        If _bSAPresent
            Debug.Trace("[SNAnimGS] SA presence guard: SeverActions PRESENT (first-call sentinel) -- REV-178 L4")
        Else
            Debug.Trace("[SNAnimGS] SA presence guard: SeverActions absent -- SA fields skipped every pack (V5 receipts live here) -- REV-178 L4")
        EndIf
    EndIf
    Return _bSAPresent
EndFunction

; [REV-178 L4] the SA candidate fragment (saManaged/saMood/saPlayerRapport
; per OR3; SA numbers serialize as STRINGS, matching the §6.5 example).
; Absent SA -> "" (fields omitted entirely, R13/R14). Unmanaged-actor fixed
; defaults (rapport 0 / mood 50) mark saManaged:false so the OR3 prompt
; gloss fires instead of a bare "50".
String Function _GSSAFieldsJson(Actor akC)
    If !akC || !_GSSAPresent()
        Return ""
    EndIf
    Float fMood = SeverActionsNative.Native_GetMood(akC)
    Float fRap = SeverActionsNative.Native_GetRapport(akC)
    Bool bManaged = !(fMood == 50.0 && fRap == 0.0)
    Return "\"saManaged\":" + bManaged as Int \
         + ",\"saMood\":\"" + (fMood as Int) + "\"" \
         + ",\"saPlayerRapport\":\"" + (fRap as Int) + "\""
EndFunction

; [REV-178 L4] numeric arousal (the A17 pair's raw half). -1 = unknown.
Int Function _GSArousalRawOf(Actor akC)
    If !akC
        Return -1
    EndIf
    If SKSE.GetPluginVersion("OSLAroused") > 0
        Return OSLArousedNative.GetArousalNoSideEffects(akC) as Int
    EndIf
    slaFrameworkScr kNG = Quest.GetQuest("sla_Framework") as slaFrameworkScr
    If kNG
        Return kNG.GetActorArousal(akC)
    EndIf
    Return -1
EndFunction

; [REV-178 L4] companion determination -- vanilla IsPlayerTeammate() (the
; same signal the Baka tree's pool filter reads; ONE companion notion).
Bool Function _GSNarrIsCompanion(Actor akC)
    Return akC && akC.IsPlayerTeammate()
EndFunction

; [REV-178 L4] does akC pass the mode's SUBJECT POOL filter?
; 0 Everyone / 1 Companions Only / 2 Non-Companion NPCs Only.
Bool Function _GSSubjectPoolAdmits(Actor akC, Int aiPool)
    If !akC
        Return False
    EndIf
    If aiPool == 1
        Return _GSNarrIsCompanion(akC)
    ElseIf aiPool == 2
        Return !_GSNarrIsCompanion(akC)
    EndIf
    Return True
EndFunction

; [REV-178 L4] STICKINESS remember (called at fire success).
Function _GSNarrStickyRemember(Actor akSubject, Actor akTarget)
    _akNarrLastSubject = akSubject
    _akNarrLastTarget = akTarget
EndFunction

; [REV-178 L4] the SUBJECT POOL build (§6.1): sticky first, then
; conversation-priority (dialogue participants pair-first), then proximity
; fill to 5; churn recompute -- full recomposition only when membership
; drops below 3 valid (§6.1.6: otherwise same five faces, no rotation
; quota -- the revolving-door trap is rejected design). Subject
; eligibility: NPC, alive, passes the pool filter; the PLAYER IS NEVER
; SUBJECT-ELIGIBLE (OR2 -- belt enforced at validation too).
Function _GSNarrSubjectPoolBuild(Actor akAnchor, Int aiPoolN, Int aiSubjectPoolSetting)
    If !_akNarrSubjectPool || _akNarrSubjectPool.Length < 5
        _akNarrSubjectPool = New Actor[5]
    EndIf
    ; Churn check first: how many of last tick's pool are still valid?
    Int iStillValid = 0
    Int i = 0
    While i < _iNarrSubjectPoolN
        Actor akM = _akNarrSubjectPool[i]
        If akM && !akM.IsDead() && akAnchor.GetDistance(akM) <= fDaemonRadius \
           && _GSSubjectPoolAdmits(akM, aiSubjectPoolSetting)
            iStillValid += 1
        EndIf
        i += 1
    EndWhile
    If iStillValid >= 3
        Return   ; §6.1.6: same five faces; no recompute, no rotation
    EndIf
    ; Full recomposition. Stage A: sticky (previous SUBJECT/TARGET).
    _iNarrSubjectPoolN = 0
    If _akNarrLastSubject && !_akNarrLastSubject.IsDead() \
       && _akNarrLastSubject != PlayerRef \
       && akAnchor.GetDistance(_akNarrLastSubject) <= fDaemonRadius \
       && _GSSubjectPoolAdmits(_akNarrLastSubject, aiSubjectPoolSetting)
        _akNarrSubjectPool[_iNarrSubjectPoolN] = _akNarrLastSubject
        _iNarrSubjectPoolN += 1
    EndIf
    If _akNarrLastTarget && _akNarrLastTarget != _akNarrLastSubject \
       && !_akNarrLastTarget.IsDead() && _akNarrLastTarget != PlayerRef \
       && akAnchor.GetDistance(_akNarrLastTarget) <= fDaemonRadius \
       && _GSSubjectPoolAdmits(_akNarrLastTarget, aiSubjectPoolSetting)
        _akNarrSubjectPool[_iNarrSubjectPoolN] = _akNarrLastTarget
        _iNarrSubjectPoolN += 1
    EndIf
    ; Stage B: conversation-priority -- in-dialogue actors first, their
    ; dialogue partners immediately after them (pair-priority; §6.1.2).
    i = 0
    While i < aiPoolN && _iNarrSubjectPoolN < 5
        Actor akT = _DaemonPool[i]
        If akT && akT != akAnchor && akT != PlayerRef && !akT.IsDead() \
           && akAnchor.GetDistance(akT) <= fDaemonRadius \
           && _GSSubjectPoolAdmits(akT, aiSubjectPoolSetting) \
           && akT.GetDialogueTarget() != None
            If !_GSNarrPoolHas(akT)
                _akNarrSubjectPool[_iNarrSubjectPoolN] = akT
                _iNarrSubjectPoolN += 1
            EndIf
            Actor akPartner = akT.GetDialogueTarget()
            If akPartner && akPartner != akAnchor && akPartner != PlayerRef \
               && !akPartner.IsDead() && _iNarrSubjectPoolN < 5 \
               && akAnchor.GetDistance(akPartner) <= fDaemonRadius \
               && _GSSubjectPoolAdmits(akPartner, aiSubjectPoolSetting) \
               && !_GSNarrPoolHas(akPartner)
                _akNarrSubjectPool[_iNarrSubjectPoolN] = akPartner
                _iNarrSubjectPoolN += 1
            EndIf
        EndIf
        i += 1
    EndWhile
    ; Stage C: proximity fill to 5 (the scan pool is proximity-ordered).
    i = 0
    While i < aiPoolN && _iNarrSubjectPoolN < 5
        Actor akT = _DaemonPool[i]
        If akT && akT != akAnchor && akT != PlayerRef && !akT.IsDead() \
           && akAnchor.GetDistance(akT) <= fDaemonRadius \
           && _GSSubjectPoolAdmits(akT, aiSubjectPoolSetting) \
           && !_GSNarrPoolHas(akT)
            _akNarrSubjectPool[_iNarrSubjectPoolN] = akT
            _iNarrSubjectPoolN += 1
        EndIf
        i += 1
    EndWhile
    ; §6.2 cum/inflation markers: OMITTED + debug note -- the state owners
    ; (SNBaka_CumDetectionModule / SNBaka_FHUInflationModule) live in the
    ; Baka tree; GS-side reachability gap of record (build report §).
    If _iNarrSubjectPoolN > 0
        Debug.Trace("[SNAnimGS] narrative subject pool built: n=" + _iNarrSubjectPoolN + " (sticky+dialogue+proximity; cum/inflation markers omitted GS-side -- Baka-tree modules, REV-178 L4)")
    EndIf
EndFunction

Bool Function _GSNarrPoolHas(Actor akC)
    Int j = 0
    While j < _iNarrSubjectPoolN
        If _akNarrSubjectPool[j] == akC
            Return True
        EndIf
        j += 1
    EndWhile
    Return False
EndFunction

; [REV-178 L4] the subjectPool[] JSON (§6.5 additive schema): name/uuid/
; sex/state/arousalBand/arousalRaw + SA fields under guard. cum/inflation
; omitted (see the build note above). Sequential accumulation (167e law).
; Adversarial names ride _GSJsonEsc (quotes/backslashes escaped).
String Function _GSNarrSubjectPoolJson()
    String s = ""
    Int i = 0
    While i < _iNarrSubjectPoolN
        Actor akC = _akNarrSubjectPool[i]
        If akC
            If i > 0
                s = s + ","
            EndIf
            String sSex = "male"
            If _SexOf(akC) == 1
                sSex = "female"
            EndIf
            Int iRaw = _GSArousalRawOf(akC)
            String sBand = "unknown"
            If iRaw >= 75
                sBand = "high"
            ElseIf iRaw >= 25
                sBand = "stirring"
            ElseIf iRaw >= 0
                sBand = "low"
            EndIf
            s = s + "{\"name\":\"" + _GSJsonEsc(akC.GetDisplayName()) + "\"" \
                + ",\"uuid\":" + _UuidJsonLiteralCtx(akC) \
                + ",\"sex\":\"" + sSex + "\"" \
                + ",\"state\":\"" + _GSJsonEsc(_GSLaneStateOf(akC)) + "\""
            If iRaw >= 0
                s = s + ",\"arousalBand\":\"" + sBand + "\",\"arousalRaw\":" + iRaw
            EndIf
            String sSA = _GSSAFieldsJson(akC)
            If sSA != ""
                s = s + "," + sSA
            EndIf
            s = s + "}"
        EndIf
        i += 1
    EndWhile
    Return s
EndFunction

; [REV-178 L4] the player field (§6.5): the player is a TARGET-pool
; constant ONLY (OR2) -- present when the module's player-target toggle
; admits them; omitted otherwise (never a subject candidate).
String Function _GSPlayerField()
    If StorageUtil.GetIntValue(None, "GSAnim.PlayerTargetable", 0) != 1
        Return ""
    EndIf
    Return "{\"name\":\"" + _GSJsonEsc(PlayerRef.GetDisplayName()) + "\"" \
         + ",\"uuid\":" + _UuidJsonLiteralCtx(PlayerRef) + "}"
EndFunction

; [REV-178 L4/V6] the cadence band selector: cadence read at DISPATCH;
; < 30s cadence = "lean" (summary profiles, R8), else "full".
String Function _GSCadenceBand(String asCadenceKey, Float afDefault)
    Float fInt = StorageUtil.GetFloatValue(None, asCadenceKey, afDefault)
    If fInt < 30.0
        Return "lean"
    EndIf
    Return "full"
EndFunction

; [REV-178 L4] the selection-method word ("narrative"/"random") from the
; v23 MCM key (default per mode, R1).
String Function _GSSelectionMethodWord(String asMethodKey, Int aiDefault)
    If StorageUtil.GetIntValue(None, asMethodKey, aiDefault) == 1
        Return "narrative"
    EndIf
    Return "random"
EndFunction

; [REV-178 L6/§7.3] SUBJECT resolution + validation (the R11 discipline,
; mirrored from target-pick): on subject-pool AND roster (union, §7.3.1);
; must pass the Subject Pool filter (§7.3.2); the PLAYER is NEVER a valid
; SUBJECT (OR2 belt at validation). Off-roster/filter-fail/player -> None
; (the caller degrades to the mechanical pick with a sentinel, §7.2).
Actor Function _GSNarrResolveSubject(String sName, Int aiSubjectPoolSetting)
    If sName == ""
        Return None
    EndIf
    Int i = 0
    While i < _iNarrSubjectPoolN
        Actor akC = _akNarrSubjectPool[i]
        If akC && akC.GetDisplayName() == sName
            Return akC   ; pool membership already implies filter-pass
        EndIf
        i += 1
    EndWhile
    ; roster union belt (§7.3.1 counts the target roster; filter applies)
    Int r = 0
    While r < _iMuseRosterN
        Actor akR = _akMuseRoster[r]
        If akR && akR.GetDisplayName() == sName
            If akR == PlayerRef
                Debug.Trace("[SNAnimGS] narrative SUBJECT '" + sName + "' = PLAYER -- refused (OR2: target-pool constant only) -- REV-178 L6")
                Return None
            EndIf
            If !_GSSubjectPoolAdmits(akR, aiSubjectPoolSetting)
                Debug.Trace("[SNAnimGS] narrative SUBJECT '" + sName + "' fails the Subject Pool filter -- named drop (§7.3.2) -- REV-178 L6")
                Return None
            EndIf
            Return akR
        EndIf
        r += 1
    EndWhile
    ; [REV-178a Leg 2] case-folded rung (exact first above; NOTHING else).
    String sLowS = _gsAsciiILower(sName)
    i = 0
    While i < _iNarrSubjectPoolN
        If _akNarrSubjectPool[i] && _gsAsciiILower(_akNarrSubjectPool[i].GetDisplayName()) == sLowS
            Return _akNarrSubjectPool[i]
        EndIf
        i += 1
    EndWhile
    r = 0
    While r < _iMuseRosterN
        Actor akF = _akMuseRoster[r]
        If akF && _gsAsciiILower(akF.GetDisplayName()) == sLowS
            If akF == PlayerRef
                Debug.Trace("[SNAnimGS] narrative SUBJECT '" + sName + "' = PLAYER -- refused (OR2: target-pool constant only) -- REV-178 L6")
                Return None
            EndIf
            If !_GSSubjectPoolAdmits(akF, aiSubjectPoolSetting)
                Debug.Trace("[SNAnimGS] narrative SUBJECT '" + sName + "' fails the Subject Pool filter -- named drop (§7.3.2) -- REV-178 L6")
                Return None
            EndIf
            Return akF
        EndIf
        r += 1
    EndWhile
    If _gsAsciiILower(PlayerRef.GetDisplayName()) == sLowS
        Debug.Trace("[SNAnimGS] narrative SUBJECT '" + sName + "' = PLAYER -- refused (OR2: target-pool constant only) -- REV-178 L6")
        Return None
    EndIf
    _i178aSubjectSkips += 1
    Debug.Trace("[SNAnimGS] unresolvable-subject: '" + sName + "' (skip-tally=" + _i178aSubjectSkips + ") -- REV-178a Leg 2")
    Return None
EndFunction

; [REV-178 L4/§6.5] the composition-level parse receipt: Papyrus has no
; in-tree JSON parser, so this is the STRUCTURAL lint (balanced braces/
; brackets, even quote count) -- the devkit-side parse is receipted at
; dogfood via the request-body capture (the standing 174h surface).
; Failure = loud sentinel; the pack ships (the lint names the composer so
; the log line is actionable).
Bool Function _GSJsonLintOK(String asJson, String asComposer)
    Int iDepthB = 0
    Int iDepthK = 0
    Int iQuotes = 0
    Int i = 0
    Int iLen = StringUtil.GetLength(asJson)
    While i < iLen
        String ch = StringUtil.GetNthChar(asJson, i)
        If ch == "\""
            iQuotes += 1
        ElseIf ch == "{"
            iDepthB += 1
        ElseIf ch == "}"
            iDepthB -= 1
        ElseIf ch == "["
            iDepthK += 1
        ElseIf ch == "]"
            iDepthK -= 1
        EndIf
        i += 1
    EndWhile
    Bool bOK = iDepthB == 0 && iDepthK == 0 && (iQuotes % 2) == 0
    If !bOK
        Debug.Trace("[SNAnimGS] JSON LINT FAIL (composer " + asComposer + "): braces " + iDepthB + " brackets " + iDepthK + " quotes " + iQuotes + " -- REV-178 L4 parse receipt")
    Else
        Debug.Trace("[SNAnimGS] JSON lint PASS (composer " + asComposer + ", " + iLen + " chars) -- REV-178 L4 parse receipt")
    EndIf
    Return bOK
EndFunction

; [REV-178 L4] the per-candidate state line source for subjectPool.state
; (the existing lane-state vocabulary; dead/downed/busy/dialogue triage).
String Function _GSLaneStateOf(Actor akC)
    If !akC
        Return ""
    EndIf
    If akC.IsDead()
        Return "dead"
    ElseIf akC.IsBleedingOut()
        Return "downed"
    ElseIf akC.IsInCombat()
        Return "in combat"
    ElseIf _IsBusyElsewhere(akC)
        Return "engaged"
    ElseIf akC.GetDialogueTarget() != None
        Return "in conversation"
    EndIf
    Return "idle"
EndFunction






; [REV-174 D3 3.4 GS] line parser for the TARGET:/POSE:/REACT: contract
; lines (the _MolagParseLine pattern: key Find + tail to EOL + trim).
String Function _GSParseLine(String asResp, String asKey)
    Int k = StringUtil.Find(asResp, asKey)
    If k < 0
        Return ""
    EndIf
    String s = StringUtil.Substring(asResp, k + StringUtil.GetLength(asKey), StringUtil.GetLength(asResp))
    Int e = StringUtil.Find(s, "\n")
    If e >= 0
        s = StringUtil.Substring(s, 0, e)
    EndIf
    Return _TrimTok(s)
EndFunction

; [REV-174 D3 4.3 GS] TARGET: resolution -- exact-name match against the GS
; roster FIRST (the 3.2 leg-3 remainder: the roster is real now), then the
; fire actor + player fallbacks. Unresolvable = None (callers treat as a
; named drop; desc degrades to no-target-slot, descriptors-v2 open flag 3).
Actor Function _GSResolveTarget(Actor ak, String sName)
    If sName == "" || ak == None
        Return None
    EndIf
    ; [REV-174a A34a] the player-target backstop: with GSAnim.PlayerTargetable
    ; OFF the player is not in the roster, but the fire actor/player fallbacks
    ; below could still hand back a player pick -- this guard converts that to a
    ; NAMED drop instead of a silent player fire. The roster is the primary
    ; exclusion; this is the belt-and-suspenders sentinel.
    Bool bPT = StorageUtil.GetIntValue(None, "GSAnim.PlayerTargetable", 0) == 1
    Int r = 0
    While r < _iMuseRosterN
        If _akMuseRoster[r] && _akMuseRoster[r].GetDisplayName() == sName
            If _akMuseRoster[r] == PlayerRef && !bPT
                Debug.Trace("[SNAnimGS] lane TARGET '" + sName + "' = PLAYER with PlayerTargetable OFF -- refused (backstop sentinel, A34a) -- REV-174a D1a")
                Return None
            EndIf
            Return _akMuseRoster[r]
        EndIf
        r += 1
    EndWhile
    ; [REV-178a Leg 2] CASE-FOLDED PASS ONLY (user ruling 2026-11-06): exact
    ; first (the loop above), then ONE folded roster re-walk. NOTHING else --
    ; no gloss, no role, no relationship inference script-side, ever.
    String sLowT = _gsAsciiILower(sName)
    r = 0
    While r < _iMuseRosterN
        If _akMuseRoster[r] && _gsAsciiILower(_akMuseRoster[r].GetDisplayName()) == sLowT
            If _akMuseRoster[r] == PlayerRef && !bPT
                Debug.Trace("[SNAnimGS] lane TARGET '" + sName + "' = PLAYER with PlayerTargetable OFF -- refused (backstop sentinel, A34a) -- REV-174a D1a")
                Return None
            EndIf
            Debug.Trace("[SNAnimGS] lane TARGET '" + sName + "' resolved by CASE-FOLD -> " + _akMuseRoster[r].GetDisplayName() + " -- REV-178a Leg 2")
            Return _akMuseRoster[r]
        EndIf
        r += 1
    EndWhile
    If _gsAsciiILower(PlayerRef.GetDisplayName()) == sLowT
        If !bPT
            Debug.Trace("[SNAnimGS] lane TARGET '" + sName + "' = PLAYER with PlayerTargetable OFF -- refused (backstop sentinel, A34a) -- REV-174a D1a")
            Return None
        EndIf
        Return PlayerRef
    EndIf
    If _gsAsciiILower(ak.GetDisplayName()) == sLowT
        Return ak
    EndIf
    _i178aTargetSkips += 1
    Debug.Trace("[SNAnimGS] unresolvable-target: '" + sName + "' (skip-tally=" + _i178aTargetSkips + ", roster n=" + _iMuseRosterN + ") -- REV-178a Leg 2; caller degrades one rung (subject-performed fire, 7.2)")
    Return None
EndFunction

; [REV-174 D3 4.3] the GS desc composition: `<Subject> <descriptor row
; verbatim> <Target>.` (design doc 4.3 -- the descriptors-v2 row IS the
; middle of the sentence). akTarget None -> no target slot. Missing row =
; named content gap + `<Subject> <pose label> <Target>.` degradation for
; THAT fire only (the standing gap list feeds the sitting text pass).
; [REV-178c Leg 3] THE REASONING LINE: the narrative consideration answer's
; CASE sentence composes into the fire-time cue desc. Desc shape becomes
; "<Actor> <action> <target> -- <CASE sentence> Those nearby see and react to
; what they've just witnessed." (the user's line of record rides verbatim
; after the CASE; the composed shape is engine-facing text derived from model
; output + the user's sentence -- register DRAFT at the pen). Narrative-path
; ONLY: mechanical/random fallback fires call this composer WITHOUT asCase
; (the reasoning line is never fabricated). ASCII separator " -- " by rule.
; Cap of record: 240 chars HARD CUT on the CASE fragment (covers the 178b
; Leg-0 harvest's longest observed CASE; no ellipsis -- nothing fabricated).
; [REV-178d Leg 2] BOUNDARY TRUNCATION (S244 Leg 3.1): a CASE line longer
; than the cap is cut at the LAST SENTENCE TERMINATOR (. ! ?) inside the
; window; if none, at the LAST SPACE; only a window with neither (a single
; uninterrupted token) falls to the hard cut. Never mid-word. Receipt'd.
String Function _GSTruncateCase(String asCase, Int aiMax)
    If StringUtil.GetLength(asCase) <= aiMax
        Return asCase
    EndIf
    Int iCut = -1
    Int iSpace = -1
    Int i = aiMax - 1
    While i >= 0
        String c = StringUtil.GetNthChar(asCase, i)
        If iCut == -1 && (c == "." || c == "!" || c == "?")
            iCut = i + 1
        EndIf
        If iSpace == -1 && c == " "
            iSpace = i
        EndIf
        If iCut != -1
            i = -1
        Else
            i -= 1
        EndIf
    EndWhile
    String sOut = ""
    If iCut > 0
        sOut = StringUtil.Substring(asCase, 0, iCut)
    ElseIf iSpace > 0
        sOut = StringUtil.Substring(asCase, 0, iSpace)
    Else
        sOut = StringUtil.Substring(asCase, 0, aiMax)
    EndIf
    Debug.Trace("[SNAnimGS] CASE boundary truncation: " + StringUtil.GetLength(asCase) + " -> " + StringUtil.GetLength(sOut) + " chars (cut mode " + iCut + "/" + iSpace + ") -- REV-178d Leg 2")
    Return sOut
EndFunction

; [REV-180 C1] the general-cue composer (spec 3.1): ALL general-cue sites
; route through this one function. Target present -> the targeted clip row in
; the mode-lane shape (R1: "<Actor> <row> <target>."). Target absent -> the
; SOLO row (R2: "<Actor> <solo row>."). Both maps miss (catalog-less vibe, or
; map gap) -> the A2 verb-phrase label degrade (the "just <label>." frame is
; RETIRED with the noun-phrase table) + the standing GAP sentinel. NO CASE
; parameter exists here at all (R1: the general cue is base-sentence only,
; forever). GSAnim.Vibe label storage + the stop wording are served by the
; same A2 table (_MuseFireLabel / _StopWording).
String Function _GSGeneralDesc(Actor ak, Actor akTarget, String sPoseId, String sLabel)
    String sRow = ""
    If akTarget
        sRow = _GSPoseDescriptor(sPoseId)
        If sRow != ""
            Debug.Trace("[SNAnimGS] general cue from clip row (C1): " + ak.GetDisplayName() + " -> " + sPoseId + " (targeted) -- REV-180")
            Return ak.GetDisplayName() + " " + sRow + " " + akTarget.GetDisplayName() + "."
        EndIf
    Else
        sRow = _GSPoseDescriptorSolo(sPoseId)
        If sRow != ""
            Debug.Trace("[SNAnimGS] general cue from clip row (C1): " + ak.GetDisplayName() + " -> " + sPoseId + " (solo) -- REV-180")
            Return ak.GetDisplayName() + " " + sRow + "."
        EndIf
    EndIf
    Debug.Trace("[SNAnimGS] desc content GAP: no descriptor row for clip '" + sPoseId + "' -- degrading to label form for THIS fire (standing gap list item) -- REV-174 D3 4.3")
    If akTarget
        Return ak.GetDisplayName() + " " + sLabel + " " + akTarget.GetDisplayName() + "."
    EndIf
    Return ak.GetDisplayName() + " " + sLabel + "."
EndFunction

; Sentinel: one trace per with-case fire (the adoption tally metric); the
; without-case shape is silent (the OR4 accept+sentinel already covers
; missing CASE at parse time).
String Function _GSComposeDesc(Actor ak, Actor akTarget, String sPoseId, String sPoseLabel, String asCase = "")
    String sRow = _GSPoseDescriptor(sPoseId)
    String sSolo = ""
    String sBase = ""
    If sRow == ""
        Debug.Trace("[SNAnimGS] desc content GAP: no descriptor row for clip '" + sPoseId + "' -- degrading to label form for THIS fire (standing gap list item) -- REV-174 D3 4.3")
        If akTarget
            sBase = ak.GetDisplayName() + " " + sPoseLabel + " " + akTarget.GetDisplayName() + "."
        Else
            sBase = ak.GetDisplayName() + " " + sPoseLabel + "."
        EndIf
    Else
        If akTarget
            sBase = ak.GetDisplayName() + " " + sRow + " " + akTarget.GetDisplayName() + "."
        Else
            ; [REV-180 C1 spec 2/3.3] targetless lane fires use the SOLO row --
            ; the targeted row ends on a connector (before/for/at/toward/beside)
            ; and rendered as a DANGLING-CONNECTOR sentence on live 179 whenever
            ; the muse fired akTarget=None (the latent defect this rev fixes).
            ; Solo miss (catalog-less vibe) falls to the label degrade below.
            sSolo = _GSPoseDescriptorSolo(sPoseId)
            If sSolo != ""
                sBase = ak.GetDisplayName() + " " + sSolo + "."
            Else
                sBase = ak.GetDisplayName() + " " + sPoseLabel + "."
            EndIf
        EndIf
    EndIf
    If asCase == ""
        Return sBase
    EndIf
    ; [REV-179 Leg 2] CASE COMPOSE-TIME TOGGLE (ruling of record (c), 178d
    ; dogfood): GSAnim.CaseInCue, None-keyed StorageUtil, DEFAULT ON (1).
    ; OFF = plain desc everywhere downstream -- this composer returns the base
    ; sentence ONLY (no CASE fragment, no closing sentence, no per-lane logic);
    ; read fresh per fire so the MCM toggle applies on the next compose.
    If StorageUtil.GetIntValue(None, "GSAnim.CaseInCue", 1) != 1
        Debug.Trace("[SNAnimGS] CASE cue append OFF (plain desc, case len=" + StringUtil.GetLength(asCase) + ") -- REV-179 Leg 2")
        Return sBase
    EndIf
    asCase = _GSTrim(asCase)
    ; [REV-178d Leg 2] S244 Leg 3.1: boundary truncation -- on overflow cut
    ; at the last sentence terminator, else the last space. NEVER mid-word.
    asCase = _GSTruncateCase(asCase, 240)
    If StringUtil.GetLength(asCase) > 0
        String c = StringUtil.GetNthChar(asCase, StringUtil.GetLength(asCase) - 1)
        If c != "." && c != "!" && c != "?"
            asCase = asCase + "."
        EndIf
    EndIf
    ; strip the base's trailing period, then append the reasoning tail
    String sHead = sBase
    If StringUtil.GetLength(sHead) > 0 && StringUtil.GetNthChar(sHead, StringUtil.GetLength(sHead) - 1) == "."
        sHead = StringUtil.Substring(sHead, 0, StringUtil.GetLength(sHead) - 1)
    EndIf
    Debug.Trace("[SNAnimGS] reasoning line appended (case len=" + StringUtil.GetLength(asCase) + ") -- with-CASE desc -- REV-178c Leg 3")
    Return sHead + " -- " + asCase + " Those nearby see and react to what they've just witnessed."
EndFunction

; ============================================================================
; [REV-174 D3 4.3] THE 153-ROW POSE DESCRIPTOR MAP -- gs-pose-descriptors-v2
; .md rows VERBATIM (the user-edited source of record; [PAIR] markers are
; catalog annotations, NOT desc text, and are dropped here). Keyed by the
; CLIP id (e.g. "GS21"); "" = named content gap (caller degrades per 4.3).
; Home-side reconciliation against pose_tag_corpus.tsv is flagged in the doc.
; ============================================================================
String Function _GSPoseDescriptor(String sPoseId)
    ; --- seduce (17) ---
    If sPoseId == "GS1"
        Return "flowed into a slow, deliberate seduction before"
    ElseIf sPoseId == "GS2"
        Return "drifted closer and offered a forward, unmistakable seduction to"
    ElseIf sPoseId == "GS3"
        Return "threw a slow, beckoning look back over the shoulder at"
    ElseIf sPoseId == "GS17"
        Return "let a suggestive flirtation hang in the air toward"
    ElseIf sPoseId == "GS25"
        Return "swayed their hips in a slow, subtle seduction before"
    ElseIf sPoseId == "GS26"
        Return "rolled their hips in a quiet, teasing seduction before"
    ElseIf sPoseId == "GS31"
        Return "Swayed their hips, holding up a heart sign with their hands towards"
    ElseIf sPoseId == "GS36"
        Return "turned and put their backside on slow, seductive display for"
    ElseIf sPoseId == "GS56"
        Return "provoked with a shy glance and a faltering, tempting sway before"
    ElseIf sPoseId == "GS62"
        Return "held a long, suggestive look back toward"
    ElseIf sPoseId == "GS63"
        Return "slid their body slowly downward in a slow-burning tease before"
    ElseIf sPoseId == "GS66"
        Return "swayed side to side with open, hungry want before"
    ElseIf sPoseId == "GS70"
        Return "bit their thumb with shy, flickering hunger at"
    ElseIf sPoseId == "GS80"
        Return "worked a slow hip circle, shy but unmistakably seducing, before"
    ElseIf sPoseId == "GS84"
        Return "cupped their own chest and carried the tease like an offering to"
    ElseIf sPoseId == "GS189"
        Return "gathered and tied their hair with slow, deliberate provocation before"
    ElseIf sPoseId == "GS198"
        Return "held a slow sway, eyes forward, letting the sight settle on"
    ; --- selftouch (10) ---
    ElseIf sPoseId == "GS6"
        Return "let their hands wander over their own body with open hunger before"
    ElseIf sPoseId == "GS7"
        Return "ran their hands over themselves with desperate, showy need before"
    ElseIf sPoseId == "GS18"
        Return "sparked their own backside with a provocative little slap for"
    ElseIf sPoseId == "GS46"
        Return "Played with their own chest in a lewd, suggestive display for"
    ElseIf sPoseId == "GS55"
        Return "could not keep their hands off themselves, touching boldly before"
    ElseIf sPoseId == "GS60"
        Return "roamed their hands all over their body in a shameless display for"
    ElseIf sPoseId == "GS69"
        Return "swayed side to side, hands restless on themselves, want on full display to"
    ElseIf sPoseId == "GS71"
        Return "traced every curve of themselves in a slow, total self-exploration before"
    ElseIf sPoseId == "GS72"
        Return "shyly, touched their chest in a faltering tease for"
    ElseIf sPoseId == "GS87"
        Return "cradled their own chest with shy, showy fingers before"
    ; --- present (15) ---
    ElseIf sPoseId == "GS4"
        Return "bent forward and offered their backside up in plain view to"
    ElseIf sPoseId == "GS5"
        Return "bent to show themselves while holding steady eye contact with"
    ElseIf sPoseId == "GS11"
        Return "folded down hands-to-knees in a frank, presenting display for"
    ElseIf sPoseId == "GS37"
        Return "bent over in a slow, deliberate showing for"
    ElseIf sPoseId == "GS38"
        Return "rolled their backside slowly while glancing back to check the effect on"
    ElseIf sPoseId == "GS43"
        Return "rounded their back out in a slow, lewd offering to"
    ElseIf sPoseId == "GS86"
        Return "bent over shyly, half-hiding while still showing themselves to"
    ElseIf sPoseId == "GS88"
        Return "dropped hands to knees and presented themselves plainly to"
    ElseIf sPoseId == "GS99"
        Return "bent low with a slow, brazen wiggle meant for"
    ElseIf sPoseId == "GS118"
        Return "bent over with their eyes fixed forward on"
    ElseIf sPoseId == "GS130"
        Return "folded forward with a shy, unmistakable showing for"
    ElseIf sPoseId == "GS162"
        Return "curved forward, cheeks coloring, still offering the sight of their rump to"
    ElseIf sPoseId == "GS190"
        Return "provocatively leaning over with furrowed, oddly captivating concentration before"
    ElseIf sPoseId == "GS193"
        Return "let just enough ass slip into view to seduce"
    ElseIf sPoseId == "GS202"
        Return "doubled down into the bent over display with an earnest, quietly sexy focus before"
    ; --- dance (15) ---
    ElseIf sPoseId == "GS21"
        Return "threw themselves into a wavy-armed, traditional Skyrim jig before"
    ElseIf sPoseId == "GS27"
        Return "spun through a quick mambo toward"
    ElseIf sPoseId == "GS34"
        Return "burst into a bright victory dance around"
    ElseIf sPoseId == "GS42"
        Return "swung through a slick sideways groove in front of"
    ElseIf sPoseId == "GS47"
        Return "kept a modest, well-mannered little dance for"
    ElseIf sPoseId == "GS48"
        Return "held a long, rooted dance, all arms and attitude, before"
    ElseIf sPoseId == "GS58"
        Return "danced modestly, keeping every inch of it innocent for"
    ElseIf sPoseId == "GS59"
        Return "idled their hips to the beat with no mischief in it near"
    ElseIf sPoseId == "GS79"
        Return "bounced through a joyful hip-touching jig beside"
    ElseIf sPoseId == "GS95"
        Return "waggled their hips and threw comical hands in the air at"
    ElseIf sPoseId == "GS125"
        Return "clowned through a ridiculous little dance meant to amuse"
    ElseIf sPoseId == "GS132"
        Return "danced with cool, easy swagger for"
    ElseIf sPoseId == "GS133"
        Return "moved with unhurried, confident cool before"
    ElseIf sPoseId == "GS154"
        Return "danced with a valiant, girly flourish toward"
    ElseIf sPoseId == "GS209"
        Return "did a goofy, surprisingly limber dance to entertain"
    ; --- dance_sexy (16) ---
    ElseIf sPoseId == "GS9"
        Return "twerked hard while looking back to watch it land on"
    ElseIf sPoseId == "GS10"
        Return "danced with a sensual sway held just shy of brazen before"
    ElseIf sPoseId == "GS12"
        Return "threw their hands up and rolled slow, sensual hips for"
    ElseIf sPoseId == "GS13"
        Return "danced purely to provoke"
    ElseIf sPoseId == "GS14"
        Return "circled and bent through a slow, sexy orbit around"
    ElseIf sPoseId == "GS15"
        Return "let their hips wander in a dreamy, distracting rhythm before"
    ElseIf sPoseId == "GS23"
        Return "snapped their hips in sharp little tik-tok beats for"
    ElseIf sPoseId == "GS29"
        Return "rolled a slow, sensual hip dance before"
    ElseIf sPoseId == "GS44"
        Return "twerked slow and deliberate, a seduction measured in inches, for"
    ElseIf sPoseId == "GS52"
        Return "danced with a blunt, lewd suggestion in every line of their body toward"
    ElseIf sPoseId == "GS61"
        Return "swayed slow hips with a hand cocked coyly on their chin before"
    ElseIf sPoseId == "GS83"
        Return "danced like something catching fire, each move hotter than the last before"
    ElseIf sPoseId == "GS102"
        Return "danced brazenly, backside leading the whole performance for"
    ElseIf sPoseId == "GS107"
        Return "swung side to side in a shameless, filthy little dance before"
    ElseIf sPoseId == "GS144"
        Return "kept it sexy but just this side of respectable for"
    ElseIf sPoseId == "GS187"
        Return "rode their hips in a slow grind with both hands thrown up before"
    ; --- ground_sexy (12) ---
    ElseIf sPoseId == "GS253"
        Return "dropped to all fours in a slow, suggestive prowl before"
    ElseIf sPoseId == "GS257"
        Return "laid back with their legs up in a lazy, lewd invitation toward"
    ElseIf sPoseId == "GS261"
        Return "lay on their stomach and looked back with open heat at"
    ElseIf sPoseId == "GS267"
        Return "rose onto all fours and let the posture say the rest to"
    ElseIf sPoseId == "GS271"
        Return "lounged in a sexy, thoughtful wait before"
    ElseIf sPoseId == "GS275"
        Return "stretched out on their stomach, all slow curves, before"
    ElseIf sPoseId == "GS282"
        Return "sat like a slow lesson in wanting, legs arranged just so, before"
    ElseIf sPoseId == "GS285"
        Return "arranged themselves into one long, suggesting line of want before"
    ElseIf sPoseId == "GS305"
        Return "twerked on the ground without an ounce of shame before"
    ElseIf sPoseId == "GS306"
        Return "ground out a twerk from the floor, low and relentless, before"
    ElseIf sPoseId == "GS311"
        Return "prowled to all fours, purely to provoke"
    ElseIf sPoseId == "GS316"
        Return "settled onto all fours with a slow, provocative arch before"
    ; --- ground_idle (18) ---
    ElseIf sPoseId == "GS128"
        Return "squatted low with their eyes fixed on the ground beside"
    ElseIf sPoseId == "GS256"
        Return "sat with a playful wiggle and a bright, teasing grin at"
    ElseIf sPoseId == "GS270"
        Return "sagged down, spent and panting, into the quiet beside"
    ElseIf sPoseId == "GS276"
        Return "lay on their stomach wearing their boredom openly near"
    ElseIf sPoseId == "GS278"
        Return "lay on their stomach kicking idle feet at the air near"
    ElseIf sPoseId == "GS286"
        Return "sat hollowed out and bone-tired beside"
    ElseIf sPoseId == "GS287"
        Return "crumpled down carrying the weight of something unspeakable beside"
    ElseIf sPoseId == "GS289"
        Return "dropped to their stomach and let the tedium pool around"
    ElseIf sPoseId == "GS295"
        Return "knelt with quiet, folded stillness before"
    ElseIf sPoseId == "GS296"
        Return "folded to the ground with a shattered, spent stillness beside"
    ElseIf sPoseId == "GS313"
        Return "reclined back on their hands in an easy rest beside"
    ElseIf sPoseId == "GS314"
        Return "leaned back into a slow, easy rest and let the moment drift past"
    ElseIf sPoseId == "GS317"
        Return "lay on their side in a long, lazy line beside"
    ElseIf sPoseId == "GS697"
        Return "sat hunched forward in a still and brooding rest beside"
    ElseIf sPoseId == "GS698"
        Return "sat hugging their knees to their chest beside"
    ElseIf sPoseId == "GS699"
        Return "rested with a hand laid soft over their stomach beside"
    ElseIf sPoseId == "GS706"
        Return "sat looking down into their own thoughts beside"
    ElseIf sPoseId == "GS712"
        Return "sat folded into a deep, unbothered rest beside"
    ; --- workout (16) ---
    ElseIf sPoseId == "GS156"
        Return "pumped their knees up high with an accidental flash of appeal before"
    ElseIf sPoseId == "GS182"
        Return "bounced through a jumping training drill before"
    ElseIf sPoseId == "GS658"
        Return "skipped through a light jumping warmup beside"
    ElseIf sPoseId == "GS659"
        Return "dropped and ground out a set of push-ups before"
    ElseIf sPoseId == "GS660"
        Return "mimed deadlifts with serious, braced effort before"
    ElseIf sPoseId == "GS661"
        Return "worked slow lateral leg lifts for the glutes before"
    ElseIf sPoseId == "GS663"
        Return "went through a sharp abdominal drill before"
    ElseIf sPoseId == "GS664"
        Return "dropped to their back and pumped slow glute bridges before"
    ElseIf sPoseId == "GS665"
        Return "held a braced, static training stance before"
    ElseIf sPoseId == "GS666"
        Return "crunched through leg-up ab work before"
    ElseIf sPoseId == "GS667"
        Return "drove through a fast mountain-climber drill before"
    ElseIf sPoseId == "GS672"
        Return "lifted slow lateral leg raises with neat, steady form before"
    ElseIf sPoseId == "GS676"
        Return "worked through deep, deliberate squats before"
    ElseIf sPoseId == "GS681"
        Return "folded into a leg-up core drill before"
    ElseIf sPoseId == "GS683"
        Return "pressed up into slow glute bridges, deliberate and unhurried, before"
    ElseIf sPoseId == "GS690"
        Return "stood in wide training stance, hands planted on hips, before"
    ; --- stretch (14) ---
    ElseIf sPoseId == "GS662"
        Return "reached through a long, plain stretch before"
    ElseIf sPoseId == "GS668"
        Return "folded into a slow dolphin stretch before"
    ElseIf sPoseId == "GS669"
        Return "opened into a deep leg stretch on the ground before"
    ElseIf sPoseId == "GS670"
        Return "arched through a slow back stretch before"
    ElseIf sPoseId == "GS671"
        Return "pressed into a long wall stretch beside"
    ElseIf sPoseId == "GS673"
        Return "sank onto all fours into a slow, rippling stretch before"
    ElseIf sPoseId == "GS674"
        Return "flowed through a full sun-salute sequence before"
    ElseIf sPoseId == "GS678"
        Return "dropped into a wide leg-stride stretch before"
    ElseIf sPoseId == "GS679"
        Return "sat into a deep ground hip stretch before"
    ElseIf sPoseId == "GS680"
        Return "pressed their backside high into a long floor stretch before"
    ElseIf sPoseId == "GS684"
        Return "folded into a high-hipped back stretch, spine long, before"
    ElseIf sPoseId == "GS686"
        Return "stood and arched back into a slow standing stretch before"
    ElseIf sPoseId == "GS689"
        Return "settled into a legs-up yoga hold before"
    ElseIf sPoseId == "GS691"
        Return "swept their arms up into a long side stretch before"
    ; --- submission (7) ---
    ElseIf sPoseId == "GS51"
        Return "danced in their cuffs like a prisoner performing for"
    ElseIf sPoseId == "GS700"
        Return "knelt bound with their hands laced behind their head before"
    ElseIf sPoseId == "GS705"
        Return "raised their hands high in open surrender to"
    ElseIf sPoseId == "GS707"
        Return "stood with their hands bound behind them, held out and given over to"
    ElseIf sPoseId == "GS708"
        Return "stood still with their hands tied back and their fate handed over to"
    ElseIf sPoseId == "GS709"
        Return "lay bound on the ground, wholly given over to"
    ElseIf sPoseId == "GS710"
        Return "lay bound on their side in a slack, exhausted surrender beside"
    ; --- plead (3) ---
    ElseIf sPoseId == "GS701"
        Return "dropped to their knees and pressed their forehead to the ground in abject apology before"
    ElseIf sPoseId == "GS702"
        Return "dropped to their knees with folded hands, begging for forgiveness from"
    ElseIf sPoseId == "GS703"
        Return "fell to begging with open hands and desperate eyes before"
    ; --- idle (10) ---
    ElseIf sPoseId == "GS131"
        Return "flashed a warm, encouraging, friendly gesture toward"
    ElseIf sPoseId == "GS135"
        Return "stood wrapped up in their own shyness, all nerves kept small, beside"
    ElseIf sPoseId == "GS147"
        Return "stood with their hands behind their back and just a hint of tease in it before"
    ElseIf sPoseId == "GS177"
        Return "stood arms crossed with a knowing little suggestion in the set of their shoulders toward"
    ElseIf sPoseId == "GS196"
        Return "flung their arms up in a bright triumph at"
    ElseIf sPoseId == "GS624"
        Return "stood at easy, unhurried idleness beside"
    ElseIf sPoseId == "GS628"
        Return "loitered with loose, waiting calm beside"
    ElseIf sPoseId == "GS629"
        Return "dropped into a fists-raised battle readiness before"
    ElseIf sPoseId == "GS632"
        Return "stood with their arms crossed and their temper worn plain toward"
    ElseIf sPoseId == "GS639"
        Return "waited in a small, shy huddle of themselves beside"
    EndIf
    Return ""
EndFunction
; ============================================================================
; [REV-180 Job B] GS POSE DESCRIPTOR TABLE - SOLO SET v1 (targetless compose).
; Embedded VERBATIM from docs\features\trigger-text-package\
; gs-pose-descriptors-solo-v1.md (user-APPROVED pen copy 2026-11-05; the
; user GS2 close edit carried). Same 153 ids/pools as _GSPoseDescriptor;
; every row is a COMPLETE narrative statement - no trailing connector,
; third-person plural throughout, B1 honest-steamy register. [PAIR] and
; [CROSS-PAIR] markers are catalog annotations, NOT desc text, and are
; dropped here (the v2 house rule). "" fallthrough = named content gap
; (the _GSGeneralDesc label degrade, C1 spec 3.1); catalog-less vibes have
; no solo rows by design - same gap discipline as v2. Serves the general-
; cue compose (_GSGeneralDesc, akTarget=None), the targetless LANE compose
; (_GSComposeDesc - the REV-179 dangling-connector defect fix, C1 spec 2/3.3)
; and the player-initiated lane (_PoseDirect, ruling spec 3.5).
; ============================================================================
String Function _GSPoseDescriptorSolo(String sPoseId)
    ; --- seduce ---
    If sPoseId == "GS1"
        Return "flowed into a slow, deliberate seduction, giving it all the time in the world"
    ElseIf sPoseId == "GS2"
        Return "drifted closer into a forward, unmistakable seduction"
    ElseIf sPoseId == "GS3"
        Return "threw a slow, beckoning look back over their shoulder - an invitation with no name on it"
    ElseIf sPoseId == "GS17"
        Return "let a suggestive flirtation hang in the air, shameless about being watched"
    ElseIf sPoseId == "GS25"
        Return "swayed their hips in a slow, subtle seduction, letting it work on whoever looked"
    ElseIf sPoseId == "GS26"
        Return "rolled their hips in a quiet, teasing seduction, patient as a slow promise"
    ElseIf sPoseId == "GS31"
        Return "swayed their hips, holding up a heart sign with their hands, offering it to the room"
    ElseIf sPoseId == "GS36"
        Return "turned and put their backside on slow, seductive display, past caring who looked"
    ElseIf sPoseId == "GS56"
        Return "provoked with a shy glance and a faltering, tempting sway - shy, but not that shy"
    ElseIf sPoseId == "GS62"
        Return "held a long, suggestive look back over their shoulder, letting it linger"
    ElseIf sPoseId == "GS63"
        Return "slid their body slowly downward in a slow-burning tease, all the way to the floor"
    ElseIf sPoseId == "GS66"
        Return "swayed side to side with open, hungry want, putting it on full display"
    ElseIf sPoseId == "GS70"
        Return "bit their thumb with shy, flickering hunger, eyes doing the asking"
    ElseIf sPoseId == "GS80"
        Return "worked a slow hip circle, shy but unmistakably seducing, cheeks and hips in on it together"
    ElseIf sPoseId == "GS84"
        Return "cupped their own chest and carried the tease like an offering, free for the taking"
    ElseIf sPoseId == "GS189"
        Return "gathered and tied their hair with slow, deliberate provocation - a show before the show"
    ElseIf sPoseId == "GS198"
        Return "held a slow sway, eyes forward, letting the sight of them settle over the room"
    ; --- selftouch ---
    ElseIf sPoseId == "GS6"
        Return "let their hands wander over their own body with open hunger, making no secret of it"
    ElseIf sPoseId == "GS7"
        Return "ran their hands over themselves with desperate, showy need, past all pretense"
    ElseIf sPoseId == "GS18"
        Return "sparked their own backside with a provocative little slap and a shameless grin"
    ElseIf sPoseId == "GS46"
        Return "played with their own chest in a lewd, suggestive display, entirely unbothered"
    ElseIf sPoseId == "GS55"
        Return "could not keep their hands off themselves, touching boldly where everyone could see"
    ElseIf sPoseId == "GS60"
        Return "roamed their hands all over their body in a shameless display"
    ElseIf sPoseId == "GS69"
        Return "swayed side to side, hands restless on themselves, want on full display"
    ElseIf sPoseId == "GS71"
        Return "traced every curve of themselves in a slow, total self-exploration, savoring their own hands"
    ElseIf sPoseId == "GS72"
        Return "shyly touched their chest in a faltering tease, shy and doing it anyway"
    ElseIf sPoseId == "GS87"
        Return "cradled their own chest with shy, showy fingers, half-hiding and half-showing"
    ; --- present ---
    ElseIf sPoseId == "GS4"
        Return "bent forward and offered their backside up in plain view, no mistaking the offer"
    ElseIf sPoseId == "GS5"
        Return "bent to show themselves while holding steady eye contact with the room"
    ElseIf sPoseId == "GS11"
        Return "folded down hands-to-knees in a frank, presenting display, holding nothing back"
    ElseIf sPoseId == "GS37"
        Return "bent over in a slow, deliberate showing, taking their time about it"
    ElseIf sPoseId == "GS38"
        Return "rolled their backside slowly, glancing back to check the effect - and finding one"
    ElseIf sPoseId == "GS43"
        Return "rounded their back out in a slow, lewd offering, arched and shameless"
    ElseIf sPoseId == "GS86"
        Return "bent over shyly, half-hiding while still showing themselves, shy about exactly how much"
    ElseIf sPoseId == "GS88"
        Return "dropped hands to knees and presented themselves plainly, offering without words"
    ElseIf sPoseId == "GS99"
        Return "bent low with a slow, brazen wiggle, putting on the whole show"
    ElseIf sPoseId == "GS118"
        Return "bent over with their eyes fixed forward, giving the view freely"
    ElseIf sPoseId == "GS130"
        Return "folded forward with a shy, unmistakable showing, blush and all"
    ElseIf sPoseId == "GS162"
        Return "curved forward, cheeks coloring, still offering the sight of their rump to any eye that wanted it"
    ElseIf sPoseId == "GS190"
        Return "leaned over provocatively with furrowed, oddly captivating concentration"
    ElseIf sPoseId == "GS193"
        Return "let just enough of their backside slip into view to seduce, measured to the inch"
    ElseIf sPoseId == "GS202"
        Return "doubled down into the bent-over display with an earnest, quietly sexy focus"
    ; --- dance ---
    ElseIf sPoseId == "GS21"
        Return "threw themselves into a wavy-armed, traditional Skyrim jig, careless and merry"
    ElseIf sPoseId == "GS27"
        Return "spun through a quick mambo, bright with the beat"
    ElseIf sPoseId == "GS34"
        Return "burst into a bright victory dance, riding the high out loud"
    ElseIf sPoseId == "GS42"
        Return "swung through a slick sideways groove, smooth as anything"
    ElseIf sPoseId == "GS47"
        Return "kept a modest, well-mannered little dance, light and easy"
    ElseIf sPoseId == "GS48"
        Return "held a long, rooted dance, all arms and attitude"
    ElseIf sPoseId == "GS58"
        Return "danced modestly, keeping every inch of it innocent"
    ElseIf sPoseId == "GS59"
        Return "idled their hips to the beat with no mischief in it"
    ElseIf sPoseId == "GS79"
        Return "bounced through a joyful hip-touching jig, grinning through it"
    ElseIf sPoseId == "GS95"
        Return "waggled their hips and threw comical hands in the air, milking the laugh"
    ElseIf sPoseId == "GS125"
        Return "clowned through a ridiculous little dance, plainly out to amuse"
    ElseIf sPoseId == "GS132"
        Return "danced with cool, easy swagger, unhurried about being watched"
    ElseIf sPoseId == "GS133"
        Return "moved with unhurried, confident cool, owning the floor they stood on"
    ElseIf sPoseId == "GS154"
        Return "danced with a valiant, girly flourish, throwing everything into it"
    ElseIf sPoseId == "GS209"
        Return "did a goofy, surprisingly limber dance, the kind that earns a laugh"
    ; --- dance_sexy ---
    ElseIf sPoseId == "GS9"
        Return "twerked hard, looking back over their shoulder to make sure it landed"
    ElseIf sPoseId == "GS10"
        Return "danced with a sensual sway held just shy of brazen - just shy"
    ElseIf sPoseId == "GS12"
        Return "threw their hands up and rolled slow, sensual hips, offering the rhythm to the room"
    ElseIf sPoseId == "GS13"
        Return "danced purely to provoke, and knew exactly what it was doing"
    ElseIf sPoseId == "GS14"
        Return "circled and bent through a slow, sexy orbit, drawing every eye through the arc"
    ElseIf sPoseId == "GS15"
        Return "let their hips wander in a dreamy, distracting rhythm, half-lost in it"
    ElseIf sPoseId == "GS23"
        Return "snapped their hips in sharp little beats, crisp and shameless"
    ElseIf sPoseId == "GS29"
        Return "rolled a slow, sensual hip dance, letting it smolder"
    ElseIf sPoseId == "GS44"
        Return "twerked slow and deliberate, a seduction measured in inches"
    ElseIf sPoseId == "GS52"
        Return "danced with a blunt, lewd suggestion in every line of their body"
    ElseIf sPoseId == "GS61"
        Return "swayed slow hips with a hand cocked coyly on their chin, playing it cool"
    ElseIf sPoseId == "GS83"
        Return "danced like something catching fire, each move hotter than the last"
    ElseIf sPoseId == "GS102"
        Return "danced brazenly, backside leading the whole performance"
    ElseIf sPoseId == "GS107"
        Return "swung side to side in a shameless, filthy little dance, filthy on purpose"
    ElseIf sPoseId == "GS144"
        Return "kept it sexy but just this side of respectable - just this side"
    ElseIf sPoseId == "GS187"
        Return "rode their hips in a slow grind with both hands thrown up, lost to it"
    ; --- ground_sexy ---
    ElseIf sPoseId == "GS253"
        Return "dropped to all fours in a slow, suggestive prowl, ready to stay a while"
    ElseIf sPoseId == "GS257"
        Return "laid back with their legs up in a lazy, lewd invitation, making no move to close them"
    ElseIf sPoseId == "GS261"
        Return "lay on their stomach and looked back with open heat in their eyes"
    ElseIf sPoseId == "GS267"
        Return "rose onto all fours and let the posture say the rest - and it said plenty"
    ElseIf sPoseId == "GS271"
        Return "lounged in a sexy, thoughtful wait, in no hurry at all"
    ElseIf sPoseId == "GS275"
        Return "stretched out on their stomach, all slow curves, taking their time"
    ElseIf sPoseId == "GS282"
        Return "sat like a slow lesson in wanting, legs arranged just so"
    ElseIf sPoseId == "GS285"
        Return "arranged themselves into one long, suggesting line of want"
    ElseIf sPoseId == "GS305"
        Return "twerked on the ground without an ounce of shame"
    ElseIf sPoseId == "GS306"
        Return "ground out a twerk from the floor, low and relentless"
    ElseIf sPoseId == "GS311"
        Return "prowled to all fours, purely to provoke - and provoked"
    ElseIf sPoseId == "GS316"
        Return "settled onto all fours with a slow, provocative arch, holding it"
    ; --- ground_idle ---
    ElseIf sPoseId == "GS128"
        Return "squatted low with their eyes fixed on the ground, lost in it"
    ElseIf sPoseId == "GS256"
        Return "sat with a playful wiggle and a bright, teasing grin"
    ElseIf sPoseId == "GS270"
        Return "sagged down, spent and panting, into the quiet"
    ElseIf sPoseId == "GS276"
        Return "lay on their stomach wearing their boredom openly"
    ElseIf sPoseId == "GS278"
        Return "lay on their stomach kicking idle feet at the air, bored to the bone"
    ElseIf sPoseId == "GS286"
        Return "sat hollowed out and bone-tired, done for the day"
    ElseIf sPoseId == "GS287"
        Return "crumpled down carrying the weight of something unspeakable"
    ElseIf sPoseId == "GS289"
        Return "dropped to their stomach and let the tedium pool around them"
    ElseIf sPoseId == "GS295"
        Return "knelt with quiet, folded stillness"
    ElseIf sPoseId == "GS296"
        Return "folded to the ground with a shattered, spent stillness"
    ElseIf sPoseId == "GS313"
        Return "reclined back on their hands in an easy rest"
    ElseIf sPoseId == "GS314"
        Return "leaned back into a slow, easy rest and let the moment drift past"
    ElseIf sPoseId == "GS317"
        Return "lay on their side in a long, lazy line"
    ElseIf sPoseId == "GS697"
        Return "sat hunched forward in a still and brooding rest"
    ElseIf sPoseId == "GS698"
        Return "sat hugging their knees to their chest, small and closed in"
    ElseIf sPoseId == "GS699"
        Return "rested with a hand laid soft over their stomach"
    ElseIf sPoseId == "GS706"
        Return "sat looking down into their own thoughts, far from the room"
    ElseIf sPoseId == "GS712"
        Return "sat folded into a deep, unbothered rest"
    ; --- workout ---
    ElseIf sPoseId == "GS156"
        Return "pumped their knees up high with an accidental flash of appeal - accidental"
    ElseIf sPoseId == "GS182"
        Return "bounced through a jumping training drill, working up a sweat"
    ElseIf sPoseId == "GS658"
        Return "skipped through a light jumping warmup, loose and easy"
    ElseIf sPoseId == "GS659"
        Return "dropped and ground out a set of push-ups, counting through them"
    ElseIf sPoseId == "GS660"
        Return "mimed deadlifts with serious, braced effort"
    ElseIf sPoseId == "GS661"
        Return "worked slow lateral leg lifts for the glutes, form first"
    ElseIf sPoseId == "GS663"
        Return "went through a sharp abdominal drill, all clean reps"
    ElseIf sPoseId == "GS664"
        Return "dropped to their back and pumped slow glute bridges"
    ElseIf sPoseId == "GS665"
        Return "held a braced, static training stance, steady as stone"
    ElseIf sPoseId == "GS666"
        Return "crunched through leg-up ab work, no shortcuts"
    ElseIf sPoseId == "GS667"
        Return "drove through a fast mountain-climber drill, feet blurring"
    ElseIf sPoseId == "GS672"
        Return "lifted slow lateral leg raises with neat, steady form"
    ElseIf sPoseId == "GS676"
        Return "worked through deep, deliberate squats, one rep at a time"
    ElseIf sPoseId == "GS681"
        Return "folded into a leg-up core drill, holding the burn"
    ElseIf sPoseId == "GS683"
        Return "pressed up into slow glute bridges, deliberate and unhurried"
    ElseIf sPoseId == "GS690"
        Return "stood in a wide training stance, hands planted on hips, all business"
    ; --- stretch ---
    ElseIf sPoseId == "GS662"
        Return "reached through a long, plain stretch, easing out every joint"
    ElseIf sPoseId == "GS668"
        Return "folded into a slow dolphin stretch and hung there"
    ElseIf sPoseId == "GS669"
        Return "opened into a deep leg stretch on the ground, breathing through it"
    ElseIf sPoseId == "GS670"
        Return "arched through a slow back stretch, vertebra by vertebra"
    ElseIf sPoseId == "GS671"
        Return "pressed into a long wall stretch, lengthening into it"
    ElseIf sPoseId == "GS673"
        Return "sank onto all fours into a slow, rippling stretch"
    ElseIf sPoseId == "GS674"
        Return "flowed through a full sun-salute sequence, breath and movement together"
    ElseIf sPoseId == "GS678"
        Return "dropped into a wide leg-stride stretch, settling deeper by degrees"
    ElseIf sPoseId == "GS679"
        Return "sat into a deep ground hip stretch and let it open"
    ElseIf sPoseId == "GS680"
        Return "pressed their backside high into a long floor stretch"
    ElseIf sPoseId == "GS684"
        Return "folded into a high-hipped back stretch, spine long"
    ElseIf sPoseId == "GS686"
        Return "stood and arched back into a slow standing stretch, reaching for the ceiling"
    ElseIf sPoseId == "GS689"
        Return "settled into a legs-up yoga hold and let the stillness do its work"
    ElseIf sPoseId == "GS691"
        Return "swept their arms up into a long side stretch, lengthening all the way through"
    ; --- submission ---
    ElseIf sPoseId == "GS51"
        Return "danced in their cuffs like a prisoner performing for whoever held the leash, making the best of it"
    ElseIf sPoseId == "GS700"
        Return "knelt bound with their hands laced behind their head, holding the pose they were left in"
    ElseIf sPoseId == "GS705"
        Return "raised their hands high in open surrender, giving it up"
    ElseIf sPoseId == "GS707"
        Return "stood with their hands bound behind them, held out and given over"
    ElseIf sPoseId == "GS708"
        Return "stood still with their hands tied back and their fate handed over, waiting on it"
    ElseIf sPoseId == "GS709"
        Return "lay bound on the ground, wholly given over, making no protest"
    ElseIf sPoseId == "GS710"
        Return "lay bound on their side in a slack, exhausted surrender, spent past resisting"
    ; --- plead ---
    ElseIf sPoseId == "GS701"
        Return "dropped to their knees and pressed their forehead to the ground in abject apology"
    ElseIf sPoseId == "GS702"
        Return "dropped to their knees with folded hands, begging for forgiveness aloud"
    ElseIf sPoseId == "GS703"
        Return "fell to begging with open hands and desperate eyes"
    ; --- idle ---
    ElseIf sPoseId == "GS131"
        Return "flashed a warm, encouraging, friendly gesture, bright enough to answer"
    ElseIf sPoseId == "GS135"
        Return "stood wrapped up in their own shyness, all nerves kept small"
    ElseIf sPoseId == "GS147"
        Return "stood with their hands behind their back and just a hint of tease in it"
    ElseIf sPoseId == "GS177"
        Return "stood arms crossed with a knowing little suggestion in the set of their shoulders"
    ElseIf sPoseId == "GS196"
        Return "flung their arms up in a bright triumph, riding the win"
    ElseIf sPoseId == "GS624"
        Return "stood at easy, unhurried idleness"
    ElseIf sPoseId == "GS628"
        Return "loitered with loose, waiting calm"
    ElseIf sPoseId == "GS629"
        Return "dropped into a fists-raised battle readiness, coiled to go"
    ElseIf sPoseId == "GS632"
        Return "stood with their arms crossed and their temper worn plain"
    ElseIf sPoseId == "GS639"
        Return "waited in a small, shy huddle of themselves"
    EndIf
    Return ""
EndFunction

; REV-163: OnPosePicked (the ded/pose_picker decision callback) is RETIRED
; with the picker lane -- the consideration call's own answer now carries the
; exact move (CLIP), parsed in OnMuseConsideration and fired through
; _PoseVibe's sForceEvent leg. No decision callback exists on this path.

Function _PacifyGS(Actor ak, Bool on)
    If !ak
        ; REV-167b finding 13 / C-5 (justified silence): every CALLER of this
        ; service is itself null-guarded and sentinel'd at its own altitude (the
        ; fire chain's null/player guard is the REV-166 sentinel); a trace here
        ; would double-report refusals already named one frame up the stack.
        Return
    EndIf
    If on
        ; [REV-161 PR#2 fold (2) - Oldcustard credit, by-concept] CLAIM-BEFORE-READ
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
        ; [REV-161 PR#2 fold (2)] release only when the LAST pacify owner goes.
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
; REV-137a 2.3 (outcome-true sentinel, §157 finding 2.3): _PoseVibe now
; RETURNS Bool — True only when a pose event was actually SENT. The old
; caller-side fire sentinel printed after an internal refusal (gender/busy/
; empty-pool early returns happen BEFORE SendAnimationEvent), misreporting
; fires. Refusal legs release any live idle hold (flag-guarded — the T3
; pre-fire path acquires the class-0 hold BEFORE this dispatch, so a
; refusal here must never strand it).
; REV-152/163: sForceEvent -- the exact-pick leg. The retired picker's
; plumbing, kept: the consideration call's CLIP answer (REV-163) fires
; through this same hardened chain (idle-interrupt + hold + recheck +
; guards) instead of the random draw; empty = the random draw (Sheogorath/T3,
; degenerate pools, and the ruled absent/invalid-CLIP fallback -- every
; pre-existing callsite unchanged). The forced event is validated against
; the pool at draw time (belt-and-suspenders; the caller validates before
; calling too).
; REV-159 5.3: aiRoute tags the fire lane for the per-route pose-narration
; toggles (user-authored titles, 137f rider): 1 = Sanguine mode fire
; (consideration picks + fallbacks), 2 = emergent autonomous fire (Sheogorath
; T3 + any LLM-chosen pose action via the Pose*_Execute executors),
; 3 = player-initiated (the grid/crosshair pick; also the stop gesture).
; 0/unknown = untagged -- the cue fires ungated (no behavior change).
; The gate reads StorageUtil keys GSAnim.PoseNarrSanguine/Emergent/Player
; (DEFAULT 1 = ON -- current behavior preserved; the MCM "GS Poses" page owns
; them, register entry 37 DRAFT tooltips).
; C-4 STANDING CONVENTION (REV-166/167b, ship-gate enforced; REV-180 six-arg
; extension): _PoseVibe takes EXACTLY six arguments -- (ak, vibe, label,
; sForceEvent, aiRoute, akDescTarget). Papyrus has no named arguments:
; positional callers MUST pass ALL 6 args; any append to this signature
; requires EVERY call-site update in the same rev. The standing gate greps
; every _PoseVibe( call site for the 6-arg shape (see gs-build/standing_gates.ps1).
; [REV-180 C1 spec 3.2 Option A] akDescTarget is the general-cue desc target
; (the "for" slot) computed at the CALL SITE -- route 1 passes the tick
; subject when the performer is not it, the Sheogorath wrapper passes its
; consideration subject likewise; the route-2 variant fallbacks pass None.
Bool Function _PoseVibe(Actor ak, String vibe, String label, String sForceEvent = "", Int aiRoute = 0, Actor akDescTarget = None)
    ; [REV-174a A34c] the REV-166 null/player guard is now TOGGLE-GATED, not
    ; unconditional: with the GS module's "Player can be targeted" toggle ON
    ; (GSAnim.PlayerTargetable, GS Poses MCM page) a player fire is PERMITTED
    ; (the future capability -- NPC poses directed at the player, reaction via
    ; the player lanes). OFF (default) keeps the REV-166 refusal exactly.
    If !ak
        Debug.Trace("[SNAnimGS] pose fire refused: null actor (defensive guard, REV-166)")
        Return False
    EndIf
    If ak == PlayerRef && StorageUtil.GetIntValue(None, "GSAnim.PlayerTargetable", 0) != 1
        ; REV-166 2.2 sentinel: this was the one genuinely SILENT return in the pose
        ; fire chain (no receipt of any class) -- it now names itself in Trace.
        Debug.Trace("[SNAnimGS] pose fire refused: player actor (defensive guard, REV-166; PlayerTargetable OFF per A34c)")
        Return False
    EndIf
    ; REV-85 Phase B: gender gate routes through _GenderAdmits (the rev-26 vibe-level
    ; split is now mode-aware: mode 0 keeps it exactly — females pass, males only via
    ; _VibeMaleOK, unknown sex stays blocked, never a silent change on an unread value;
    ; mode 1 is the same table as the crosshair admission; mode 2 drops the gate).
    If !_GenderAdmits(ak, vibe)
        ; REV-137d 3.2 full-chain receipt: the gender-policy refusal is named (was a
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
        ; REV-137d 3.2 full-chain receipt: the busy refusal is named (was silent).
        Debug.Trace("[SNAnimGS] pose fire refused: BUSY (" + ak.GetDisplayName() + " busy at exec time)")
        If StorageUtil.GetIntValue(ak, "GSAnim.IdleHold", 0) == 1
            _ReleaseIdleHold(ak)
        EndIf
        Return False
    EndIf
    ; REV-135 (idle-interrupt service, spec 1.4.4): the exec-time leg routes
    ; through the service — with _IsBusyElsewhere class-aware, seated/marker
    ; candidates reach here and must EXIT -> RECHECK -> fire (covers the muse
    ; direct-fire call and the T3 wrapper dispatch, both of which land in
    ; _PoseVibe); every refusal skips with a §5 sentinel inside the service.
    If !_IdleFirePath(ak, vibe)
        Return False   ; the service already released the hold + sentinel'd every refusal
    EndIf
    ; REV-85c A.3: the draw routes through _VibeEventsFor (the A.3 sex-split for
    ; "aroused"; every other vibe unchanged from _VibeCSV).
    String csv = _VibeEventsFor(ak, vibe)
    If csv == ""
        ; REV-137a 2.2 belt-and-suspenders: no fire — never strand the hold
        ; (the recheck PASS already handed restraint to this machinery).
        ak.SetRestrained(False)
        ak.SetDontMove(False)
        _PkgHoldActorAI(ak, False)   ; REV-137c 3.1: same belt-and-suspenders for the package pin
        StorageUtil.SetIntValue(ak, "GSAnim.IdleHold", 0)
        Debug.Trace("[SNAnimGS] pose fire refused: empty vibe event pool ('" + vibe + "', " + ak.GetDisplayName() + ")")
        ; REV-166 2.2 observability sentinel (the 0806/810 invisible-refusal class, third
        ; instance): a defect-class refusal that only ever printed to Debug.Trace on an
        ; unlogged install was invisible -- it now carries a user-visible notification
        ; receipt (register DRAFT). Gender/busy refusals stay Trace-only (legitimate
        ; high-traffic policy refusals; a toast per refusal would spam).
        Debug.Notification("DeD: " + ak.GetDisplayName() + " pose refused - empty event pool ('" + vibe + "').")
        Return False
    EndIf
    String[] list = StringUtil.Split(csv, ",")
    String ev = list[Utility.RandomInt(0, list.Length - 1)]
    If sForceEvent != ""
        ; REV-152: the decision callback's pick -- must be a member of the pool
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
            ; REV-166 2.2 observability sentinel: THIS is the refusal that ran dark for
            ; 36 hours on live 0.3.0 (the misbound route tag arriving here as "2"; no
            ; Papyrus log retained on the user install, so the named Trace was never
            ; seen). The notification receipt makes the class user-visible live.
            Debug.Notification("DeD: " + ak.GetDisplayName() + " pose refused - forced event '" + sForceEvent + "' not in pool (DeD bug report: share your logs).")
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
    ; [A21 REV-174 D3] the fired-event capture: ev is FINAL here (forced or
    ; random draw) -- stash it so the fire-site callers can compose the desc
    ; from the FIRED clip, not the LLM pick (a random draw below an absent or
    ; off-pool CLIP previously composed label-form descs systematically).
    _sGSLastFiredEvent = ev
    Debug.SendAnimationEvent(ak, ev)
    StorageUtil.SetStringValue(ak, "GSAnim.Pose",    ev)
    StorageUtil.SetFloatValue(ak,  "GSAnim.Start",   Utility.GetCurrentRealTime())
    StorageUtil.SetFloatValue(ak,  "GSAnim.Timeout", _VibeTimeout(vibe))
    StorageUtil.SetIntValue(ak,    "GSAnim.LockAI",  lockAI as Int)
    StorageUtil.FormListAdd(None,  "GSAnim.Posing", ak, False)
    StorageUtil.SetStringValue(ak,  "GSAnim.Vibe",   label)   ; Phase 4 rider: named-pose stop wording
    StorageUtil.SetFloatValue(None, "GSAnim.LastPoseFire", Utility.GetCurrentRealTime())  ; observability only since REV-137f (silence-floor reader retired)
    ; REV-159 5.3: the per-route pose-narration gate (DEFAULT ON -- the cue fires
    ; exactly as before unless the user turns a route's toggle off on the GS
    ; Poses page; silent-with-sentinel on the gated-skip leg, ruleset 5).
    ; [REV-174f Leg 3 -- GS POSE-PAIR, CORRECTED PARE] the bare gsanim_npc_pose
    ; type is DEAD everywhere (yaml deleted; entry 43 VOID): route 1 keeps the
    ; REV-174a D3 lanes-only retirement; route 2 now emits gsanim_pose_emergent
    ; (gate GSAnim.PoseNarrEmergent); route 3 now emits gsanim_pose_player (gate
    ; GSAnim.PoseNarrPlayer). ROUTE DISCIPLINE OF RECORD: mode-initiated poses
    ; NEVER emit these pair types (route 1 emits mode-lane cues only), and a
    ; mode-ACTIVE state does NOT suppress a genuine route-2/3 fire. Cue text =
    ; "<Actor> just <solo variant>." composed at the emission site per fire
    ; (Leg-2 register; the _MuseFireLabel one-liners ARE the variant supply).
    ; [REV-174g Leg 4.1] FACT-CUE FLOOR, superseded for MODE fires by
    ; [REV-178a Leg 6 -- S238 Leg 0 ruling, 2026-11-06]: route 1 (mode) poses
    ; STASH the general desc instead of registering it; _GSLaneFire
    ; adjudicates (narr-class pick suppresses the general; non-narr rides
    ; alongside; all-off = general alone). Routes 2/3 register directly (no
    ; lanes on those fires -- general alone by construction).
    If aiRoute == 1
        ; [REV-180 C1 R1] the general cue composes from the FIRED clip
        ; (_sGSLastFiredEvent is stashed above, before this compose) via the
        ; one composer -- targeted row + desc target when held, SOLO row when
        ; targetless, label degrade on gap. Base sentence only, never CASE.
        _sModeGeneralDesc = _GSGeneralDesc(ak, akDescTarget, _sGSLastFiredEvent, label)
        _akModeGeneralActor = ak
    ElseIf aiRoute == 2 || aiRoute == 3
        ; [REV-178b Leg 2.3] POSE REACTION LANES on the emergent + player
        ; routes (the 174f Baka Action-lane shape mirrored): the general cue
        ; STASHES and the lane fan adjudicates (narr pick suppresses the
        ; general; non-narr rides alongside; all-off = general alone -- the
        ; 178a Leg 6 supersede, now on pose fires too). No LLM REACT on these
        ; routes -> rotation fallback (random leg).
        ; [REV-180 C1 R2] targetless by construction on these routes (callers
        ; pass akDescTarget=None) -> the SOLO row compose.
        _sModeGeneralDesc = _GSGeneralDesc(ak, akDescTarget, _sGSLastFiredEvent, label)
        _akModeGeneralActor = ak
        _iPoseLaneFiredLast = _GSLaneFire("Pose", ak, None, _sModeGeneralDesc, "", True)
    Else
        ; [REV-180 C1 spec 3.6, user ruling] the pre-178a direct-register
        ; shape was DEAD CODE (every live caller passes an explicit nonzero
        ; route; the stash-adjudication design plugged the gaps it filled).
        ; REPURPOSED as a defensive UNEXPECTED-ROUTE tripwire: a wrong-route
        ; caller must never fire a mis-shaped cue -- skip the cue entirely,
        ; release the idle hold if taken, and name the defect in log behind
        ; the GSAnim.DebugNotify toggle (a live defect named without console
        ; spam). The branch stays as a tripwire; deletion was rejected.
        _ReleaseIdleHold(ak)
        If StorageUtil.GetIntValue(None, "GSAnim.DebugNotify", 0) == 1
            Debug.Trace("[SNAnimGS] pose cue DROPPED: unexpected route " + aiRoute + " (graceful drop guard) -- REV-180 C1 3.6")
        EndIf
    EndIf
    Int iNarrGate = 1
    String sPairType = "gsanim_pose_emergent"
    If aiRoute == 1
        iNarrGate = 0
        Debug.Trace("[SNAnimGS] pose-pair cue RETIRED (mode route 1, lanes-only narration) -- REV-174f Leg 3")
    ElseIf aiRoute == 2
        iNarrGate = StorageUtil.GetIntValue(None, "GSAnim.PoseNarrEmergent", 1)
    ElseIf aiRoute == 3
        iNarrGate = StorageUtil.GetIntValue(None, "GSAnim.PoseNarrPlayer", 1)
        sPairType = "gsanim_pose_player"
    EndIf
    If iNarrGate == 1 && (_iPoseLaneFiredLast % 2) == 0
        ; [REV-178b Leg 2.3] the pose-pair cue fires only when the fanned
        ; NARR lane did NOT take the narration (never 3 rendered triggers).
        SkyrimNetApi.RegisterEvent(sPairType, \
            ak.GetDisplayName() + _PoseVibeDesc(vibe, label), ak, None)
    Else
        Debug.Trace("[SNAnimGS] pose-pair cue GATED-OFF (" + sPairType + " route " + aiRoute + ", " + ak.GetDisplayName() + "; lane mask " + _iPoseLaneFiredLast + ") -- REV-178b Leg 2.3")
    EndIf
    ; REV-137d 4.1 (user ruling 2026-10-22, USER-AUTHORED per this ruling -- 17b
    ; precedent, register-cited in gs-poses.md REV-137d + posing-gender.md): every
    ; genuine Sheogorath/T3 fire carries an on-screen receipt mirroring the Sanguine
    ; notification format ("Sanguine Mode - <NPC> (<pose>)"). ASCII-only (4f rule).
    ; REV-137f 3.1 (gated-behind-a-branch verdict, 2.1): the old _bT3InFlight member
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
        _GSDebugNotify("Sheogorath Mode - " + ak.GetDisplayName() + " (" + vibe + ")")
        ; REV-159 5.1 -> [REV-174a D3 RETIRED]: the legacy Sheogorath mode
        ; direct-narration RegisterEvent is RETIRED -- the four-lane fan-out
        ; owns Sheogorath narration now (gsanim_sheogorath_mode_narr is the
        ; NARR lane's event; this legacy duplicate fired the OLD flat desc
        ; alongside the lanes). Entry-49 rider: absence proof = this comment +
        ; the dead-call sweep receipt at gate time.
        Debug.Trace("[SNAnimGS] sheogorath legacy mode narration RETIRED (lanes-only per REV-174a D3)")
    EndIf
    RegisterForSingleUpdate(3.0)
    Return True   ; REV-137a 2.3: outcome-true — the event WAS sent
EndFunction

; Phase 2: pose a specific NPC with a specific event — the player's explicit grid pick,
; aimed by crosshair at cast time. Mirrors _PoseVibe (restrain, pacify, anim event,
; GSAnim.* keys, posing list, update timer) but takes the event directly and never locks
; AI (LockAI = 0 — a player-directed pose is not a submission hold; combat still frees
; the NPC via OnUpdate). Validation + refusal notifications already happened in
; OnPoseSelected; on refusal nothing was posed and nothing falls back to the player.
Function _PoseDirect(Actor ak, String ev, String desc, String cat)
    ; [REV-180 C1 spec 3.5] the pick label: verb-phrase A2 shape ("poses -
    ; <grid desc>"); stored in GSAnim.Vibe so the NEW stop frame words
    ; grammatically (the grid desc alone is a fragment; see _StopWording).
    ; Papyrus declaration discipline: locals at function top.
    String sWhat = "poses"
    If desc != ""
        sWhat = "poses - " + desc
    EndIf
    ; REV-137a 2.2: _PoseDirect acquires the re-grab hold AT FIRE (finding
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
    StorageUtil.SetStringValue(ak,  "GSAnim.Vibe",   sWhat)   ; [REV-180 A2] the verb-phrase pick label (stop-frame feed; was the raw grid desc fragment)
    StorageUtil.SetFloatValue(None, "GSAnim.LastPoseFire", Utility.GetCurrentRealTime())  ; observability only since REV-137f (silence-floor reader retired)
    RegisterForSingleUpdate(3.0)
    ; [REV-180 C1 spec 3.5, user-ruled] the player-initiated lane routes
    ; through the SOLO PROSE: general stash + gsanim_pose_player BOTH compose
    ; via _GSGeneralDesc(ak, None, ev, ...) -> "<NPC> <solo row>." The grid
    ; menu's desc column REMAINS the pick-time UI text (what the player
    ; browsed). Catalog-less picks (Babo single-events, no solo rows) keep
    ; the grid-desc label shape as their GAP fallback: sWhat = "poses - <desc>"
    ; (computed at function top per the declaration discipline).
    ; [REV-174g Leg 4.1] FACT-CUE FLOOR (see _PoseVibe): the general pose cue
    ; fires UNCONDITIONALLY with the same composed desc; the gated pair cue
    ; below is unchanged.
    ; [REV-178b Leg 2.3] _PoseDirect is a PLAYER-INITIATED fire -- it now
    ; takes the pose reaction lanes (stash + adjudication; narr pick
    ; suppresses the general) exactly like _PoseVibe route 3.
    _sModeGeneralDesc = _GSGeneralDesc(ak, None, ev, sWhat)
    _akModeGeneralActor = ak
    _iPoseLaneFiredLast = _GSLaneFire("Pose", ak, None, _sModeGeneralDesc, "", True)
    ; REV-159 5.3: the player-initiated route's pose-narration gate (DEFAULT ON;
    ; GSAnim.PoseNarrPlayer, GS Poses page -- "Player Initiated Pose Reactions",
    ; relabeled REV-178b; user-authored title).
    ; [REV-180 A2/C1] the "just <label>." frame is retired; the pair cue
    ; composes from the same one-table label shape ("strikes a pose" class
    ; fallback for catalog-less picks).
    ; [REV-178b Leg 2.3] pair cue gated on the narr-bit (never 3 triggers).
    If StorageUtil.GetIntValue(None, "GSAnim.PoseNarrPlayer", 1) == 1 && (_iPoseLaneFiredLast % 2) == 0
        SkyrimNetApi.RegisterEvent("gsanim_pose_player", \
            ak.GetDisplayName() + _PoseVibeDesc(cat, sWhat), \
            ak, None)
    Else
        Debug.Trace("[SNAnimGS] gsanim_pose_player cue GATED-OFF (route 3 player, " + ak.GetDisplayName() + "; lane mask " + _iPoseLaneFiredLast + ") -- REV-178b Leg 2.3")
    EndIf
EndFunction

; REV-169 leg 5 (R-2(a), user ruling 2026-10-28: 10s minimum pose hold, combat/death
; exempt): returns Bool so the LLM stop-event wording callers can tell a real stop
; from a DEFERRED one. Defer leg: llm-stop/llm-command arriving <10s after pose
; start do NOT stop, do NOT consume, and return False — the 10-27 dogfood's
; Kleppr/Argis ~5s self-stops (S202 Leg 4: the narration response carries an
; LLM-chosen stop for the very actor it narrates). combat/dead/player-stop/timeout
; stay IMMEDIATE (unchanged behavior); after 10s the LLM paths proceed as today.
; Defer sentinel + the existing release sentinel cover every defer AND every
; post-10s proceed (Trace-class, no user-facing strings).
Bool Function _StopActorPose(Actor ak, String asReason = "other")
    If !ak
        ; REV-167b finding 13 / C-5 (justified silence): a null actor here is a
        ; no-op SUCCESS, not a refusal -- there is nothing to release and nothing
        ; went wrong on any fire path; the OnUpdate sweep calls this routinely for
        ; list entries whose actor form already unloaded. A sentinel would spam the
        ; 3s loop; no user-visible receipt is warranted.
        Return True
    EndIf
    ; REV-167e D.2: release-reason sentinel (the 10-27 Gwilym ~6s clear; the
    ; 3s sweep's combat/dead reads were the only un-sentinel'd branches).
    ; Every release path names itself: sweep passes combat/dead/timeout, the
    ; player stop passes player-stop, the LLM paths llm-stop/llm-command.
    Float fHeld = Utility.GetCurrentRealTime() - StorageUtil.GetFloatValue(ak, "GSAnim.Start", 0.0)
    If (asReason == "llm-stop" || asReason == "llm-command") && fHeld < 10.0
        Debug.Trace("[SNAnimGS] pose hold deferred (" + ak.GetDisplayName() + ", " + asReason + ", " + fHeld + "s) -- REV-169 R-2(a)")
        Return False
    EndIf
    Debug.Trace("[SNAnimGS] pose released (" + asReason + "): " + ak.GetDisplayName() + " (vibe=" + StorageUtil.GetStringValue(ak, "GSAnim.Vibe", "") + ", held=" + fHeld + "s) -- REV-167e")
    Debug.SendAnimationEvent(ak, "IdleForceDefaultState")
    ak.SetRestrained(False)
    ak.SetDontMove(False)
    StorageUtil.SetIntValue(ak, "GSAnim.IdleHold", 0)   ; REV-136 2.2 belt-and-suspenders: never strand the idle hold
    _PkgHoldActorAI(ak, False)   ; REV-137c 3.1: pose end -- return the actor to their package naturally
    _PacifyGS(ak, False)
    StorageUtil.SetStringValue(ak, "GSAnim.Pose", "")
    StorageUtil.SetStringValue(ak, "GSAnim.Vibe", "")   ; Phase 4 rider: consumed by whichever stop path ran
    Return True
EndFunction

; Monitor: free casual posers who entered combat / timed out; submission stays unless dead.
Event OnUpdate()
    _VariantPendingSweep(Utility.GetCurrentRealTime())   ; REV-167b D-5 leg 2: lost variant-pick answers fall to dice
    Int i = StorageUtil.FormListCount(None, "GSAnim.Posing") - 1
    Bool anyLeft = False
    While i >= 0
        Actor ak = StorageUtil.FormListGet(None, "GSAnim.Posing", i) as Actor
        If !ak || StorageUtil.GetStringValue(ak, "GSAnim.Pose", "") == ""
            ; REV-167b finding 13 / C-5 (justified silence): this is list HYGIENE,
            ; not a fire-path refusal -- a null form or an already-cleared GSAnim.Pose
            ; key just means the entry is stale; removing it is the sweep's whole job.
            StorageUtil.FormListRemoveAt(None, "GSAnim.Posing", i)
        Else
            Bool  lockAI  = StorageUtil.GetIntValue(ak, "GSAnim.LockAI", 0) == 1
            Float elapsed = Utility.GetCurrentRealTime() - StorageUtil.GetFloatValue(ak, "GSAnim.Start", 0.0)
            Float timeout = StorageUtil.GetFloatValue(ak, "GSAnim.Timeout", fPoseTimeoutDefault)
            String sWhy = ""
            If !lockAI && ak.IsInCombat()
                sWhy = "combat"
            ElseIf ak.IsDead()
                sWhy = "dead"
            ElseIf elapsed > timeout
                sWhy = "timeout"
            EndIf
            If sWhy != ""
                _StopActorPose(ak, sWhy)
                StorageUtil.FormListRemoveAt(None, "GSAnim.Posing", i)
            Else
                anyLeft = True
            EndIf
        EndIf
        i -= 1
    EndWhile
    ; ── REV-24 Task 2: the rev-21 session-scope stamp heuristic's reset branch is RETIRED ──
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
        ; Rev-9 user ruling (b) SUPERSEDES the v1.2 muse decouple: no posing during combat,
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
    ; tick can't accelerate them; REV-137f 3.3); muse
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

; [REV-174d Leg 2 / item 11] fOdExpireSeconds MEMBER REMOVED: quest-script members are
;   save-persisted, so the old save's 300.0 beat the compiled 3600.0 initializer (REV-174c
;   Leg 3 root cause). Now a function-local literal in _OverdriveOn -- 3600.0 on any save.
Int   iOdCooldownFloor   = 10        ; T2 (Fix B, 4f): floor ON applies to all 27 pose cooldowns instead
                                     ;   of 0 — zero-cooldown let the LLM chain poses back-to-back (live
                                     ;   spam confirmed in the 4e re-test). USER TASTE CALL 2026-09-10:
                                     ;   10s; retune here, recompile. OFF restores 0 (live-config parity).
                                     ;   Int — SetActionCooldown takes cooldownTimeSeconds as int.
Float fOdT3IntervalSec  = 15.0      ; T3 (REV-137f 3.3, user ruling 2026-10-22 "I want chaos --
                                     ;   multiple posers and poses at the same time"): a NEW candidate
                                     ;   fires every interval with overlapping pose lifetimes permitted
                                     ;   (planner overdrive cadence 15s; the 40s silence floor is RETIRED —
                                     ;   the one-at-a-time constraint it enforced is the subdued feel)
Float fOdCueSeconds      = 20.0      ; T1: ambience cue cadence
Float fMuseNudgeIntervalSec = 30.0   ; muse (v1.2 redesign, docs/MUSE_REDESIGN_DESIGN.md): nudge loop — ONE
                                     ;   consideration call per interval. REV-25 Task 2b (user tempo ruling,
                                     ;   formally accepted + recorded): 100s -> 30s. BUDGET RULING RECORDED
                                     ;   (user decision, standing): ~120 calls/hr is the accepted standing
                                     ;   cost while ON — the cadence itself bounds spend. Replaces the old
                                     ;   120s-global / 300s-per-NPC throttle pair (user spec); REV-19's
                                     ;   100.0->60.0 hold is superseded by this ruling.
                                     ; REV-137f 3.2: this member is NO LONGER the interval of record on
                                     ;   long-lived saves — save state restores a pre-rev-25 member value
                                     ;   (100.0) over this compiled 30.0 initializer (the deployed [REV-142]
                                     ;   pex hash-matched the dist yet the 10-22 dogfood log printed
                                     ;   100.000000s — the diagnosed ~100s-gap source). The live interval
                                     ;   now reads the StorageUtil key GSAnim.NudgeInterval with THIS
                                     ;   value as default (fresh key, absent from old saves -> 30.0).
Float fMusePerNpcSec     = 60.0       ; REV-25 Task 2b (user tempo ruling): per-NPC floor 120s -> 60s — a
                                     ;   candidate whose LastMuse seed is younger than this is skipped in
                                     ;   the walk (seed-time write of GSAnim.LastMuse unchanged; the READ
                                     ;   clamps stale stamps > fNow to 0 first, same pattern as the
                                     ;   MuseGlobal clamp). The global interval remains the spend bound;
                                     ;   the floor only redistributes targets between NPCs. Sentinel:
                                     ;   "muse npc floor skip". REV-19 original: (user ruling 09-16,
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

; [REV-178a Leg 2] the unresolvable-target/subject SKIP TALLY (first-class
; runbook metric, user ruling 2026-11-06; read from the log sentinel lines).
Int _i178aTargetSkips = 0
Int _i178aSubjectSkips = 0
; [REV-178a Leg 6] the mode general-cue stash (S238 Leg 0 supersede): route-1
; _PoseVibe fires stash the desc; _GSLaneFire adjudicates (a narr-class pick
; suppresses the general; non-narr rides alongside; none fired = general alone).
String _sModeGeneralDesc = ""
Actor _akModeGeneralActor = None
; [REV-178b Leg 2.3] the last pose-fire lane mask (narr-bit gate for the
; pose-pair cue; 0 = no lane fired).
Int _iPoseLaneFiredLast = 0
; [REV-178a Leg 7] ask-time stamp for the _musePendingActor single-in-flight
; (>30s real-time = lost callback; reclaim sentinel at the next ask site).
Float _fMusePendingStamp = 0.0
Actor   _sheoPendingActor = None   ; REV-167 (entry 44, §7.4): Sheogorath perverse-fit
Actor   _variantPendingActor = None   ; REV-167b D-4: dialogue-lane variant pick
String  _variantPendingVibe = ""
String  _variantPendingLabel = ""
Float   _variantPendingStamp = 0.0
                                   ; consideration bridge (single-in-flight, the
                                   ; _musePendingActor pattern)
; REV-137d 4.1 -> REV-137f 3.1: the _bT3InFlight member is RETIRED (save-member of no
; further use; Papyrus silently skips absent names on load). The T3 receipt gate is now
; the per-actor StorageUtil stamp GSAnim.T3Mark, set at dispatch and consumed within 30s
; by _PoseVibe's success leg — see the receipt block there for the async-window evidence.
; OStimExcitementFaction, resolved once via PO3 editor-ID lookup (arousal context for the
; nudge pack); None when OStim is absent — arousal then drops out of the pack gracefully.
Faction _kMuseArousalFaction = None
Bool    _bMuseArousalResolved = False
; REV-85 aroused-lean: the tier label of the CURRENT in-flight consideration
; (set in _MusePackContext at ask time, read at fire time for the [arousal lean]
; sentinel) — the single-in-flight pattern of _musePendingActor (one ask, one
; callback; never multi-set).
String  _sMuseArous = ""
; REV-163 (picker decommission, user ruling 2026-10-25): the _posePick*
; decision-call pending state (Actor/_posePickVibe/_posePickPose, REV-152)
; is RETIRED -- no decision call exists on the muse path anymore; the exact
; move rides the consideration answer itself (OnMuseConsideration's CLIP
; parse), so _musePendingActor is once again the only in-flight state.
; Phase 4c rider: heartbeat rate-limit clock for the one-shot muse debug window. Member,
; not StorageUtil: diagnostic-only precision — a script reload mid-window at worst resets
; the 30s beat spacing; the window BOUNDS are StorageUtil so saves keep them.
Float   _fMuseDebugBeat = 0.0
; REV-17 1b/1c riders (boot-scoped member vars — they reset at every game start, unlike the
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
    ; REV-137d 3.1 GENDER-POLICY BLANKET (user ruling 2026-10-22, supersedes the REV-26
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
           ; REV-25 3a/3b: sleeping candidates excluded at SCAN (confirmed live 09-18 10:24 —
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

; ============================================================================
; REV-167 t3 (entry 44, §5/2.3 GS leg): THE GS SELECTION MODES. The GS modes
; own their draws (baka-daemon REV-167 banner: "GS-side modes carry their own
; GSAnim.* keys; the GS script owns its draw"). Keys (None-keyed StorageUtil,
; soft-read class -- same class as the SNBaka.Svc.* probes):
; [REV-174a A35] the UNIFORM selection vocabularies (parity table of record,
; REV-174a_A35_PARITY.md). Subject: 0 Random / 1 Companions Only /
; 2 Arousal Based (NEW). Target: 0 Random / 1 Bio Led / 2 Relationship
; Priority / 3 Player Only / 4 Companions Only / 5 Non-Companion
; NPCs Only ("Companions & Player" RETIRED, A34d -- GSAnim.PlayerTargetable
; governs the player). Bio Led + RP are PROMPT-SIDE (A36a: the pack carries a
; targetSteer field; the roster is NOT filtered). [REV-174a A46] "Wide"
; (v21 slot 3; muse-roster cap 10->20) is RETIRED pre-ship -- never a
; user-facing surface, no shipped text; the cap is the standing 10.
; [REV-174a A36c] the mechanical two-tier bio-link
; draws + the shared link-weight slider are RETIRED (the SNBaka.BioNames
; mirror read cold since REV-173 Path A -- the D2 no-op named).

Int Function _gsSelSubject(String asMode)
    Int v = StorageUtil.GetIntValue(None, "GSAnim." + asMode + "Subject", 0)
    If v < 0 || v > 2
        Return 0
    EndIf
    Return v
EndFunction

Int Function _gsSelTarget(String asMode)
    Int v = StorageUtil.GetIntValue(None, "GSAnim." + asMode + "Target", 0)
    ; [REV-174a A46] clamp 0-5 (Wide retired; the MCM v22 migration remaps
    ; stored values, out-of-range clamps Random).
    If v < 0 || v > 5
        Return 0
    EndIf
    Return v
EndFunction

; [REV-174a A36c] the link-weight read RETIRED (fixed 70% arousal-tier ratio;
; no MCM surface remains).
Float Function _gsLinkWeightPct()
    Return 70.0
EndFunction
; The shared weight slider key SNBaka.TargetLinkWeight (MCM: Baka
; Interactions, "Target Link Weight", default 70) is read SOFT here (the Baka
; half absent = default 70, no error -- the §15.12 degrade). The bio link
; reads the SNBaka.BioNames cache string the Baka motherboard's relationship
; sync keeps warm; absent/empty = all-unlinked = Relationship Priority
; degrades to Random-equivalent for that fire, sentinel'd, never an error.
; SUBJECT = the posed actor (the muse walk / T3 pick). TARGET = the AUDIENCE
; (§15.11 Sanguine framing): it steers the consideration pack only; empty
; audience pool = skip tick, never a degraded pick (§15.12 honesty rule).
; Semantics mirror BakaIntegration's _ResolveSubjectSelection /
; _ResolveTargetSelection (two-tier weighted draw, tier A = bio-linked,
; weight = the slider pct; empty-pool skip; empty tier A = tier B fallthrough
; = Random-equivalent, sentinel'd). GS-local helpers, no cross-script wiring
; (a BakaIntegration property reference would add a hard dependency the
; GS-only install class forbids, §15.9).

; [REV-174a A35] the original _gsSelSubject/_gsSelTarget/_gsLinkWeightPct
; bodies are SUPERSEDED by the uniform-vocab versions above (removed here to
; keep one definition per function -- the compile gate's duplicate check).

Bool Function _gsIsCompanion(Actor ak)
    ; Companion = the player's teammate -- the exact check the Baka motherboard
    ; uses (_ExecuteIsCompanion, cited precedent; GS-local per the banner above).
    ; The player counts as companion-class for the audience filters.
    If !ak
        Return False
    EndIf
    If ak == PlayerRef
        Return True
    EndIf
    Return ak.IsPlayerTeammate()
EndFunction

String Function _gsSubjectSelName(Int aiV)
    If aiV == 1
        Return "Companions Only"
    ElseIf aiV == 2
        Return "Arousal Based"   ; [REV-174a A35] user wording of record
    EndIf
    Return "Random"
EndFunction

String Function _gsTargetSelName(Int aiV)
    If aiV == 1
        Return "Bio Led"
    ElseIf aiV == 2
        Return "Relationship Priority"
    ElseIf aiV == 3
        Return "Player Only"
    ElseIf aiV == 4
        Return "Companions Only"
    ElseIf aiV == 5
        Return "Non-Companion NPCs Only"
    EndIf
    Return "Random"
EndFunction

; [REV-174a A35] arousal int read for the Arousal Based subject draw (the
; muse chain's tier ladder, int form; neutral 0 when no framework answers).
Int Function _gsArousalInt(Actor ak)
    If !ak
        Return 0
    EndIf
    If SKSE.GetPluginVersion("OSLAroused") > 0
        Return OSLArousedNative.GetArousalNoSideEffects(ak) as Int
    EndIf
    slaFrameworkScr kNG = Quest.GetQuest("sla_Framework") as slaFrameworkScr
    If kNG
        Return kNG.GetActorArousal(ak)
    EndIf
    Return 0
EndFunction

; [REV-174a A36] the CONDITIONAL PROMPT SECTION text (DRAFT at the user's
; pen): Bio Led (1) / Relationship Priority (2) only; empty otherwise.
String Function _gsTargetSteerText(Int aiSel)
    If aiSel == 1
        Return "bio-led: read the subject's own Relationships in their bio and favor a target they already know - an existing relationship suits this moment"
    ElseIf aiSel == 2
        Return "relationship-priority: favor someone from the subject's own Relationships, and let WHY steer the pick - a disliked rival suits a hostile act, an intimate friend a warm one"
    EndIf
    Return ""
EndFunction

; [REV-178a Leg 1, user ruling 2026-11-06] targetSteer = the PLAYER-TARGET
; RULE SIGN ONLY (it does not and must not resolve relationship naming):
; policy text per ACTUAL config, Mephala-construction (mirrors the Baka
; playerTargetPolicy strings byte-for-byte). "The pool admits" = the roster
; admission in _GSMuseRosterBuild (the player is appended to the roster the
; model sees under exactly this condition -- the roster-walk rides the steer).
String Function _gsPlayerRuleSteerText()
    If StorageUtil.GetIntValue(None, "GSAnim.PlayerTargetable", 0) == 1
        Return "NPCs may target the player"
    EndIf
    Return "NPCs may not target the player"
EndFunction

; [REV-178a Leg 7] stamp + wedge reclaim: a pending actor older than 30s
; real-time is a lost callback -- named sentinel (mode + actor), then the new
; ask proceeds (the overwrite behavior itself is unchanged; no new refusal
; gate is invented -- none existed; the S238 census stands).
Function _GSMusePendingStamp()
    If _musePendingActor && Utility.GetCurrentRealTime() - _fMusePendingStamp > 30.0
        Debug.Trace("[SNAnimGS] pending-gate RECLAIM (>30s real-time, mode=Sanguine, actor=" + _musePendingActor.GetDisplayName() + ") -- REV-178a Leg 7")
    EndIf
    _fMusePendingStamp = Utility.GetCurrentRealTime()
EndFunction

; [REV-178a Leg 6 -- S238 Leg 0 SUPERSEDE] the mode general-cue adjudication:
; a narr-class lane pick suppresses the general direct-narration cue (sentinel
; "general suppressed -- narr lane"); a non-narr pick rides alongside it; no
; lanes fired = the general fires alone. One-lane cap unchanged.
Function _GSGeneralAdjudicate(Int aiFire)
    If _sModeGeneralDesc == ""
        Return   ; no stash = no mode general pending (routes 2/3 register directly)
    EndIf
    String sDesc = _sModeGeneralDesc
    Actor akG = _akModeGeneralActor
    _sModeGeneralDesc = ""
    _akModeGeneralActor = None
    If (aiFire % 2) == 1
        Debug.Trace("[SNAnimGS] general suppressed -- narr lane (REV-178a Leg 6 supersede, mode general)")
        Return
    EndIf
    If aiFire == 0
        Debug.Trace("[SNAnimGS] general cue FIRED ALONE (no lane fired) -- REV-178a Leg 6")
    Else
        Debug.Trace("[SNAnimGS] general cue FIRED alongside non-narr lane -- REV-178a Leg 6")
    EndIf
    SkyrimNetApi.RegisterEvent("gsanim_pose_general", sDesc, akG, None)
EndFunction

; ASCII case fold (mirror of the Baka motherboard's fold; StringUtil has no
; native fold -- table-driven; both sides pass through the same fold so the
; name-set equality is well-formed regardless of display-name casing).
String Function _gsAsciiILower(String sText)
    String sUp = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
    String sLo = "abcdefghijklmnopqrstuvwxyz"
    String sOut = ""
    Int i = 0
    Int n = StringUtil.GetLength(sText)
    While i < n
        String sCh = StringUtil.GetNthChar(sText, i)
        Int k = StringUtil.Find(sUp, sCh)
        If k >= 0
            sCh = StringUtil.GetNthChar(sLo, k)
        EndIf
        sOut += sCh
        i += 1
    EndWhile
    Return sOut
EndFunction

; [REV-173 Path A NOTE: the Baka relationship sync this mirror reads is
; RETIRED (typed-binding finding; snbaka_* templates deleted) -- the
; SNBaka.BioNames cache is now never warmed, so this mirror reads empty
; and Relationship Priority degrades to Random-equivalent, sentinel'd,
; exactly the documented degrade. Rehome is a planner/user decision.]
; REV-167 §15.4 GS soft-read mirror: is akOther's name in akSubject's bio
; name-set? Tier A vs Tier B for the weighted draws. Reads the SNBaka.BioNames
; cache string (kept warm by the Baka motherboard's relationship sync;
; "|"-delimited, case-insensitive full-entry match -- the Baka _BioLinkedTo
; contract). Absent or empty set = False; the once-per-boot degrade sentinel
; below logs the class once so a Baka-half-absent install never spams.
Bool _bGsBioDegradeSentinel = False
Bool Function _gsBioLinkedTo(Actor akSubject, Actor akOther)
    If !akSubject || !akOther
        Return False
    EndIf
    String sSet = StorageUtil.GetStringValue(akSubject, "SNBaka.BioNames", "")
    If sSet == ""
        If !_bGsBioDegradeSentinel
            _bGsBioDegradeSentinel = True
            Debug.Trace("[SNAnimGS] selection bio-link degrade: SNBaka.BioNames absent/empty for " \
                + akSubject.GetDisplayName() + " (Baka relationship sync not warm) - all-actors-unlinked; Relationship Priority degrades to Random-equivalent for this fire -- REV-167 t3")
        EndIf
        Return False
    EndIf
    String sName = _gsAsciiILower(akOther.GetDisplayName())
    If sName == ""
        Return False
    EndIf
    Int iPos = 0
    Int iLen = StringUtil.GetLength(sSet)
    While iPos < iLen
        Int iBar = StringUtil.Find(sSet, "|", iPos)
        If iBar < 0
            iBar = iLen
        EndIf
        If iBar > iPos
            If _gsAsciiILower(StringUtil.Substring(sSet, iPos, iBar - iPos)) == sName
                Return True
            EndIf
        EndIf
        iPos = iBar + 1
    EndWhile
    Return False
EndFunction

; The shipped walk guards, factored for the resolvers (§15.2: the dropdowns
; choose among the ELIGIBLE -- the walk guards run first, always; the scan
; filter makes these near-silent in steady state, same as the walk's own
; re-checks). NOT applied to the player-as-audience (see _gsResolveAudience).
Bool Function _gsSubjectEligible(Actor ak)
    If !ak
        Return False
    EndIf
    If ak.IsInCombat()
        Return False
    EndIf
    If _IsBusyElsewhere(ak)
        Return False
    EndIf
    If ak.GetSleepState() != 0
        Return False
    EndIf
    If ak.IsSwimming()
        Return False
    EndIf
    If ak.IsOnMount()
        Return False
    EndIf
    If ak.IsSneaking()
        Return False
    EndIf
    Return True
EndFunction

; Nth index of a given tier (or 0 when the roll overshoots -- cannot happen
; with callers that pass the census counts, but Papyrus floors gracefully).
Int Function _gsNthOfTier(Int[] aiTier, Int anCand, Int aiWantTier, Int aiNth)
    Int iSeen = 0
    Int m = 0
    While m < anCand
        If aiTier[m] == aiWantTier
            iSeen += 1
            If iSeen == aiNth
                Return m
            EndIf
        EndIf
        m += 1
    EndWhile
    Return 0
EndFunction

; The two-tier weighted draw (§15.3): one coin vs the slider pct picks the
; TIER, then a uniform draw within it. One-tier pool (nA == 0 or nA == n) =
; plain uniform (weight 0 = always tier B = Random-equivalent, §15.12;
; weight 100 = always tier A -- both honest, both receipted by the census).
Int Function _gsTwoTierPick(Int[] aiTier, Int anCand, Int anA)
    Int iPick = Utility.RandomInt(0, anCand - 1)
    If anA <= 0 || anA >= anCand
        Return iPick
    EndIf
    If Utility.RandomFloat(0.0, 100.0) < _gsLinkWeightPct()
        Return _gsNthOfTier(aiTier, anCand, 1, Utility.RandomInt(1, anA))
    EndIf
    Return _gsNthOfTier(aiTier, anCand, 0, Utility.RandomInt(1, anCand - anA))
EndFunction

; REV-167 t3 §15.3: subject resolution over the scanned pool (n candidates,
; dynamically sized -- the pool itself is _DaemonPool.Length-bounded).
; Returns the pick, or None on empty pool (skip tick, sentinel inside --
; never fall through to a degraded pick, §15.12).
Actor Function _gsResolveSubject(String asMode, Int aiSel, Int aiN)
    ; Papyrus New[] takes a literal size -- fixed 64 = the _DaemonPool cap
    ; (aiN is _DaemonPool.Length-bounded at the scan, so 64 is always enough).
    Actor[] akCand = New Actor[64]
    Int[] iTier = New Int[64]
    Int nCand = 0
    Int i = 0
    While i < aiN
        Actor akC = _DaemonPool[i]
        If _gsSubjectEligible(akC)
            If aiSel == 1 && !_gsIsCompanion(akC)
                ; Companions Only filter -- stranger skipped (not an error,
                ; the setting is the point).
            Else
                akCand[nCand] = akC
                nCand += 1
            EndIf
        EndIf
        i += 1
    EndWhile
    If nCand == 0
        String sWhy = "; nobody past the walk guards"
        If aiSel == 1
            sWhy = "; no companions in the scanned pool"
        EndIf
        Debug.Trace("[SNAnimGS] selection refuse: subject pool EMPTY (mode=" + asMode \
            + ", setting=" + _gsSubjectSelName(aiSel) + sWhy \
            + ") - skip tick, never fall through -- REV-167 t3")
        Return None
    EndIf
    Int nA = 0
    If aiSel == 2
        Int j = 0
        While j < nCand
            ; [REV-174a A35] Arousal Based: tier A = arousal >= 50 (the
            ; bio-link tier is RETIRED, A36c).
            If _gsArousalInt(akCand[j]) >= 50
                iTier[j] = 1
                nA += 1
            EndIf
            j += 1
        EndWhile
        If nA == 0
            Debug.Trace("[SNAnimGS] selection subject tierA empty - Tier B draw (Random-equivalent, fixed 70% ratio inert this fire) -- REV-174a A35")
        EndIf
    EndIf
    Int iPick = _gsTwoTierPick(iTier, nCand, nA)
    Debug.Trace("[SNAnimGS] selection subject census: mode=" + asMode + " setting=" \
        + _gsSubjectSelName(aiSel) + " pool=" + nCand + " tierA=" + nA + " -> " \
        + akCand[iPick].GetDisplayName() + " (tier " + iTier[iPick] + ") -- REV-167 t3")
    Return akCand[iPick]
EndFunction

; REV-167 t3 §15.4: audience resolution (the GS TARGET = the audience, §15.11
; Sanguine framing). 0 = Random = NO audience line (the shipped pack,
; byte-for-byte). Pool: the scanned actors minus the subject (NPCs keep the
; walk guards -- a sleeping audience is a wrong pose read) + the player for
; the settings that admit them (the audience is passive -- the pose plays AT
; them; no busy guard applies to the player, they may watch seated).
; Empty pool after filter = skip tick, sentinel inside (§15.12).
Actor Function _gsResolveAudience(String asMode, Int aiSel, Actor akSubject, Int aiN)
    Actor p = PlayerRef
    ; [REV-174a A35] Player Only is value 3 now ([REV-174a A46] was 4 under
    ; the retired 7-slot vocab; was 2 in the legacy space).
    If aiSel == 3
        If !p
            Debug.Trace("[SNAnimGS] selection refuse: audience pool EMPTY (mode=" + asMode \
                + ", setting=Player Only; no player) - skip tick -- REV-167 t3")
            Return None
        EndIf
        Debug.Trace("[SNAnimGS] selection audience drawn: the player (mode=" + asMode \
            + ", setting=Player Only) -- REV-167 t3")
        Return p
    EndIf
    ; [REV-174a A35] the audience admission remap: 1 (Bio Led) / 2 (RP)
    ; admit EVERYONE (prompt-side steering; the tier block below is
    ; RETIRED with the cold BioNames mirror, A36c); 4 Companions Only /
    ; 5 Non-Companions filter; 3 Player Only early-returns above; the player
    ; append for the retired combo legs is GONE (A34d -- the toggle governs).
    ; Fixed 65 = 64 pool slots + the player slot (Papyrus: literal sizes only).
    Actor[] akCand = New Actor[65]
    Int[] iTier = New Int[65]
    Int nCand = 0
    Int i = 0
    While i < aiN
        Actor akC = _DaemonPool[i]
        If akC && akC != akSubject && _gsSubjectEligible(akC)
            Bool bComp = _gsIsCompanion(akC)
            If aiSel == 4
                If bComp
                    akCand[nCand] = akC
                    nCand += 1
                EndIf
            ElseIf aiSel == 5
                If !bComp
                    akCand[nCand] = akC
                    nCand += 1
                EndIf
            Else
                akCand[nCand] = akC
                nCand += 1
            EndIf
        EndIf
        i += 1
    EndWhile
    If nCand == 0
        Debug.Trace("[SNAnimGS] selection refuse: audience pool EMPTY (mode=" + asMode \
            + ", setting=" + _gsTargetSelName(aiSel) + ") - skip tick, never fall through -- REV-167 t3")
        Return None
    EndIf
    Int nA = 0
    ; [REV-174a A36c] the legacy aiSel==1 two-tier bio-link audience draw is
    ; RETIRED (Bio Led/RP are prompt-side, A36a) -- uniform draw below; nA
    ; stays 0 so _gsTwoTierPick is a plain uniform pick.
    Int iPick = _gsTwoTierPick(iTier, nCand, nA)
    String sKind = ""
    If akCand[iPick] == p
        sKind = " (the player)"
    EndIf
    Debug.Trace("[SNAnimGS] selection audience census: mode=" + asMode + " setting=" \
        + _gsTargetSelName(aiSel) + " pool=" + nCand + " tierA=" + nA + " -> " \
        + akCand[iPick].GetDisplayName() + sKind + " (tier " + iTier[iPick] + ") -- REV-167 t3")
    Return akCand[iPick]
EndFunction

; Muse nudge loop (v1.2 redesign — docs/MUSE_REDESIGN_DESIGN.md, user-authoritative spec).
; Every ~30s (GSAnim.NudgeInterval, default fMuseNudgeIntervalSec; REV-137f key of record) ONE consideration call: pull context -> present the 27
; pose categories -> WEIGHTED TOWARD YES — pick the best-fitting pose unless ALL are unsuited
; (a miss is the EXCEPTION, not the goal). The YES-output is a JOB, not a flag: the call
; returns WHICH pose fits + the grounded in-world thought; OnMuseConsideration seeds it via
; GenerateNPCThought, and the pose fires through the NPC's OWN action selection (cue-not-floor
; stands — the thought is the nudge, the NPC's evaluation is the trigger).
; HARD GUARDS are ACTOR-LOCAL (user spec, scoping confirmed): the selected NPC not in combat /
; not mid-animation / not busy (the queued-actions floor is _IsBusyElsewhere — no framework
; pending-read exists), checked here at selection AND again at seed time in the callback.
; Rev-9 user ruling (b): the muse additionally SUSPENDS while the PLAYER is in combat —
; gate at the top of the tick (early return, global stamp not spent) + re-check at seed
; time in the callback; NPC-combat stays covered by the actor-local IsInCombat guards.
; The 15s poll re-register stays (the arbiter line is untouched); the interval clock inside
; gates the actual calls, so between nudges a tick is one timestamp compare.
; Phase 4c rider (unchanged): while the one-shot debug window is open, every nudge outcome
; notifies; after it closes, silence with no ceremony.
Function _MuseTick()
    _EnsurePools()   ; Phase 4d: stale-instance heal BEFORE _DaemonScan (a None pool made .Length read 0 silently -> "scan empty" heartbeats forever, 15/15 in the 4c demo)
    ; Rev-9 ruling (b): player combat suspends the muse — early return, the interval
    ; clock does NOT tick (stamp not spent, this tick is not counted), so nudges resume
    ; cleanly at the interval cadence once the fight ends. Unconditional reason-coded
    ; sentinel (NOT gated on bDebug) so the ON session log confirms suspend + resume.
    If PlayerRef.IsInCombat()
        Debug.Trace("[SNAnimGS] SanguineSuspend-PlayerCombat: tick skipped (player in combat)")
        Return
    EndIf
    Float fNow = Utility.GetCurrentRealTime()
    Bool bDebug = _MuseDebugWindowOpen(fNow)
    ; REV-17 1a: cross-session stamp clamp on read. Utility.GetCurrentRealTime() is
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
    ; REV-17 1b rider: one unconditional trace on the FIRST gated tick of each boot with
    ; the actual compare values, so a silent-muse session diagnoses itself from one grep —
    ; no re-arm dance needed, the sentinel rides along every session from now on.
    ; REV-137f 3.2: the interval OF RECORD is the StorageUtil key GSAnim.NudgeInterval
    ; (default = the compiled member). The member alone was being shadowed on long-lived
    ; saves by a pre-rev-25 save-resident value of 100.0 (the deployed [REV-142] pex
    ; hash-matched its dist yet the 10-22 dogfood log printed 100.000000s) -- a fresh key
    ; carries no such residue, so the ruled 30s cadence finally takes effect. First-read
    ; sentinel per ruleset 5 rides the first-gate trace below.
    Float fInterval = StorageUtil.GetFloatValue(None, "GSAnim.NudgeInterval", fMuseNudgeIntervalSec)
    If !_bMuseGateLogged
        _bMuseGateLogged = True
        Debug.Trace("[SNAnimGS] sanguine mode gate (first check this boot): fNow=" + fNow \
            + " stamp=" + fLastGlobal + " delta=" + (fNow - fLastGlobal) \
            + " interval=" + fInterval + " (key of record GSAnim.NudgeInterval, default " \
            + fMuseNudgeIntervalSec + "s; REV-137f save-residue member retired)")
    EndIf
    If fNow - fLastGlobal < fInterval
        ; REV-137d 3.2 full-chain receipt (user ruling 2026-10-22): the tick-opportunity
        ; sentinel is now UNCONDITIONAL, not bDebug-gated -- the cadence itself must be
        ; readable from the log on every session.
        Debug.Trace("[SNAnimGS] sanguine mode tick: no opportunity (interval clock " + (fNow - fLastGlobal) \
            + "s < " + fInterval + "s)")
        If bDebug
            _MuseDebugHeartbeat(fNow, "interval clock")
        EndIf
        Return
    EndIf
    Int n = _DaemonScan(True)   ; REV-137d 3.1: policy-blanket scan; bAllowMales is vestigial (see _DaemonScan)
    If n == 0
        ; REV-137d 3.2 full-chain receipt: the pool-empty refusal is named and unconditional.
        Debug.Trace("[SNAnimGS] sanguine mode attempt REFUSED: candidate pool EMPTY (scan n=0; policy mode " \
            + _GenderPolicy() + ")")
        If bDebug
            _MuseDebugHeartbeat(fNow, "scan empty")
        EndIf
        Return
    EndIf
    ; REV-167 t3 (entry 44, §5/2.3 GS leg): the Sanguine SELECTION-MODE READS
    ; (§15.9: 0/0 defaults = the shipped walk + pack below, byte-for-byte --
    ; the reads are conditional-receipted so a default install logs nothing new).
    Int iSangSub = _gsSelSubject("Sanguine")
    Int iSangTgt = _gsSelTarget("Sanguine")
    ; [REV-174a A35/A36] the per-fire selection shape: targetSteer text (Bio
    ; Led 1 / RP 2 -- the conditional prompt section). [REV-174a A46] the
    ; Wide roster-cap branch (10 -> 20 for target 3) is RETIRED with the
    ; option -- the cap is the standing 10, reset every tick.
    ; [REV-178a Leg 1] targetSteer = the PLAYER-TARGET RULE SIGN ONLY (user
    ; ruling 2026-11-06): bound ALWAYS (the prompt's {{ targetSteer }} is the
    ; rule sign; the A36 Bio Led/RP steer text no longer rides this slot --
    ; _gsTargetSteerText retained for the MCM read receipts above). This bind
    ; closes the 0/5 killer: every Sanguine answer targeted Hadrian (the
    ; player) with no rule sign in the pack and no player in the roster.
    String sSangSteer = _gsPlayerRuleSteerText()
    _iMuseRosterCap = 10
    If iSangSub != 0 || iSangTgt != 0
        Debug.Trace("[SNAnimGS] sanguine selection read: subject=" + iSangSub + " (" \
            + _gsSubjectSelName(iSangSub) + ") target=" + iSangTgt + " (" \
            + _gsTargetSelName(iSangTgt) + ") -- REV-174a A35")
    EndIf
    If iSangSub != 0
        ; Subject-resolver path: the resolver owns the pick (walk guards inside,
        ; §15.2); the per-NPC floor is re-checked HERE on the resolver's pick --
        ; floored = skip tick (the resolver's pick is the tick's candidate, §15.12;
        ; the walk below does NOT also run, one candidate per tick either way).
        Actor akRes = _gsResolveSubject("Sanguine", iSangSub, n)
        If !akRes
            Return   ; skip tick + sentinel inside the resolver
        EndIf
        Actor akAudRes = None
        If iSangTgt != 0
            akAudRes = _gsResolveAudience("Sanguine", iSangTgt, akRes, n)
            If !akAudRes
                Return   ; skip tick + sentinel inside the resolver
            EndIf
        EndIf
        Float fLastRes = StorageUtil.GetFloatValue(akRes, "GSAnim.LastMuse", 0.0)
        If fLastRes > fNow
            Debug.Trace("[SNAnimGS] sanguine mode npc floor stamp clamped: stale cross-session " \
                + fLastRes + " > boot clock " + fNow + " for " + akRes.GetDisplayName() \
                + " - treating as 0")
            fLastRes = 0.0
            StorageUtil.SetFloatValue(akRes, "GSAnim.LastMuse", 0.0)
        EndIf
        If fNow - fLastRes < fMusePerNpcSec
            Debug.Trace("[SNAnimGS] sanguine selection subject floor skip: " + akRes.GetDisplayName() \
                + " (last seed " + (fNow - fLastRes) + "s ago < " + fMusePerNpcSec \
                + "s) - skip tick, the resolver owns the pick -- REV-167 t3")
            Return
        EndIf
        _GSMusePendingStamp()   ; [REV-178a Leg 7] ask-time stamp + >30s reclaim sentinel
        _musePendingActor = akRes
        Int sentRes = SkyrimNetApi.SendCustomPromptToLLM("gsanim_sanguine_consideration", "", \
            _MusePackContext(akRes, n, akAudRes, sSangSteer), Self as Quest, "SkyrimNet_AnimationsGS", "OnMuseConsideration")
        StorageUtil.SetFloatValue(None, "GSAnim.MuseGlobal", fNow)
        If sentRes == 1
            Debug.Trace("[SNAnimGS] sanguine mode candidate selected: " + akRes.GetDisplayName() \
                + " (REV-167 selection subject=" + _gsSubjectSelName(iSangSub) + ", pool n=" + n \
                + ", policy mode " + _GenderPolicy() + ")")
            Debug.Trace("[SNAnimGS] sanguine mode nudge asked: " + akRes.GetDisplayName())
        Else
            _musePendingActor = None
            Debug.Trace("[SNAnimGS] sanguine mode nudge not queued (rc=" + sentRes + "): " + akRes.GetDisplayName())
            If bDebug
                _MuseDebugHeartbeat(fNow, "nudge rc=" + sentRes)
            EndIf
        EndIf
        Return
    EndIf
    ; Actor-local guard walk in random order (the walk order spaces NPCs between nudges).
    Int iStart = Utility.RandomInt(0, n - 1)
    Int i = iStart
    While True
        Actor ak = _DaemonPool[i]
        If !ak.IsInCombat() && !_IsBusyElsewhere(ak)   ; ACTOR-LOCAL hard guards (v1.2)
            ; REV-25 Task 3a: sleeping-NPC guard on the candidate walk — mirrors the seated
            ; exclusion but for GetSleepState (the 09-18 10:24 Hroki case: seeded while
            ; sleeping; _IsBusyElsewhere's GetSitState never sees a bare-floor sleeper).
            ; 3b state sweep while here: swimming / mounted / sneaking are the same class —
            ; states a hold would visibly break or read wrong; each is one guard, clearly
            ; right. Reason-coded sentinels, unconditional per §5. The scan filter above
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
            ; REV-19 Task 1: per-NPC floor (fMusePerNpcSec). Read LastMuse with the same
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
                _GSMusePendingStamp()   ; [REV-178a Leg 7] ask-time stamp + >30s reclaim sentinel
                _musePendingActor = ak
                ; REV-167 t3 (§5/2.3 GS leg): the audience draw rides the walk's
                ; candidate too (subject=Random + target=non-Random): target
                ; resolution runs AFTER the subject exists (§15.2 order). Empty
                ; audience pool = skip tick BEFORE the call is spent (§15.12).
                Actor akAud = None
                If iSangTgt != 0
                    akAud = _gsResolveAudience("Sanguine", iSangTgt, ak, n)
                    If !akAud
                        _musePendingActor = None
                        Return   ; skip tick + sentinel inside the resolver
                    EndIf
                EndIf
                ; REV-167 (entry 44, §7.2): the ambient Sanguine MODE lane names its
                ; own prompt file -- gsanim_sanguine_consideration (the muse-era
                ; dialogue prompt file is RETIRED, S196 defunct-prompts\; the
                ; Sanguine premise never leaks into ordinary conversation selection).
                ; Output contract UNCHANGED (POSE|CLIP|THOUGHT / POSE|THOUGHT / MISS),
                ; so the callback stays OnMuseConsideration byte-for-byte; only the
                ; context pack grows (npcUUID, via _MusePackContext below).
                Int sent = SkyrimNetApi.SendCustomPromptToLLM("gsanim_sanguine_consideration", "", \
                    _MusePackContext(ak, n, akAud, sSangSteer), Self as Quest, "SkyrimNet_AnimationsGS", "OnMuseConsideration")
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
            EndIf   ; REV-25 3a/3b state-guard Else
        Else
            ; REV-90 rider sentinel (REV-89 registration, §94 3.1; unconditional per §5):
            ; this skip was SILENT — seated (and every other busy) candidates entered
            ; _DaemonScan, were excluded by the walk guard, and never appeared in the log
            ; (gs-poses.md REV-87 §1.4: idle-dense pool composition was unmeasurable).
            ; Reason-coded, so the combat and busy legs stay distinguishable.
            If ak.IsInCombat()
                Debug.Trace("[SNAnimGS] sanguine mode walk skip: " + ak.GetDisplayName() + " in combat at walk time - excluded")
            Else
                ; REV-135: sentinel class-tagged — with _IsBusyElsewhere class-aware,
                ; only non-interruptible busy legs reach this branch (interruptible
                ; idle classes are admitted as candidates and routed at fire time).
                Debug.Trace("[SNAnimGS] sanguine mode walk skip: " + ak.GetDisplayName() + " busy at walk time - excluded (formerly SILENT skip; REV-135 class-aware, idleclass=" + _IdleClass(ak) + ")")
            EndIf
        EndIf   ; REV-90 busy/combat walk-guard Else
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
; REV-167 t3 (§5/2.3 GS leg, §15.11): the audience field -- additive JSON,
; rendered only when a selection mode drew one (target=Random = absent field
; = the shipped pack byte-for-byte). No fallback chain needed: an audience
; that cannot be named is skipped upstream, never mislabeled.
String Function _MusePackAudienceField(Actor akAudience)
    If !akAudience
        Return ""
    EndIf
    String sAud = akAudience.GetDisplayName()
    If sAud == ""
        sAud = "a nearby onlooker"
    EndIf
    Return ",\"audience\":\"" + sAud + "\""
EndFunction

; REV-173 Path A: the REV-167e bio-selector guard is RETIRED (probe + pack
; bioAbsent flag; see the _gsBioProbeOK retirement banner below). The
; consideration templates render bios unconditionally in-template from
; this pack's npcUUID (number-typed at parse). What remains here is the
; UUID literal helper.
; REV-167e D.1b: hex -> DECIMAL string math for the 64-bit entity UUID.
; uuid_mappings.uuid is a 64-bit INTEGER and the render contract matches the
; decimal digits (JSON number); Papyrus Int is 32-bit, so the conversion is
; pure string arithmetic (dec = dec*16 + digit, carry loop). Returns "" on
; any non-hex input -- callers fall back to the 167d quoted-hex form.
String Function _UuidDecimal(String asHex)
    If asHex == ""
        Return ""
    EndIf
    Int n = StringUtil.GetLength(asHex)
    String sHex = ""
    Int i = 0
    Bool bLead = True
    While i < n
        String c = StringUtil.GetNthChar(asHex, i)
        If bLead && c == "0"
            ; skip leading zeros
        Else
            bLead = False
            sHex = sHex + c
        EndIf
        i += 1
    EndWhile
    If sHex == ""
        Return "0"
    EndIf
    String sDec = "0"
    i = 0
    n = StringUtil.GetLength(sHex)
    While i < n
        Int dv = _HexDigitVal(StringUtil.GetNthChar(sHex, i))
        If dv < 0
            Return ""
        EndIf
        sDec = _DecMulAdd(sDec, 16, dv)
        i += 1
    EndWhile
    Return sDec
EndFunction

Int Function _HexDigitVal(String asChar)
    Int k = StringUtil.Find("0123456789ABCDEF", asChar)
    If k >= 0
        Return k
    EndIf
    k = StringUtil.Find("0123456789abcdef", asChar)
    If k >= 0
        Return k
    EndIf
    Return -1
EndFunction

String Function _DecMulAdd(String asDec, Int aiMul, Int aiAdd)
    ; asDec * aiMul + aiAdd in decimal string arithmetic (19 digits max)
    Int i = StringUtil.GetLength(asDec) - 1
    String sOut = ""
    Int iCarry = aiAdd
    While i >= 0
        Int d = _HexDigitVal(StringUtil.GetNthChar(asDec, i))
        Int v = d * aiMul + iCarry
        sOut = StringUtil.GetNthChar("0123456789", v % 10) + sOut
        iCarry = v / 10
        i -= 1
    EndWhile
    While iCarry > 0
        sOut = StringUtil.GetNthChar("0123456789", iCarry % 10) + sOut
        iCarry = iCarry / 10
    EndWhile
    Return sOut
EndFunction

; ---- REV-170 Leg 4: the Actor Context consumer rung ----
; DeDService presence cache (one SKSE.GetPluginVersion probe, the [REV-169]
; C5 posture: no new knob). The Actor Context natives are called ONLY when the
; DeDService plugin is loaded; absent -> every rung falls to the [REV-169]
; MISS tail verbatim (the ladder tail never changes).
Int _iDeDServiceCtx = -1
Bool Function _bDeDServiceCtx()
    If _iDeDServiceCtx < 0
        If SKSE.GetPluginVersion("DeDService") > 0
            _iDeDServiceCtx = 1
        Else
            _iDeDServiceCtx = 0
            Debug.Trace("[SNAnimGS] actor-context DeDService absent -> [REV-169] tails only -- REV-170")
        EndIf
    EndIf
    Return _iDeDServiceCtx == 1
EndFunction

; REV-170 Leg 4: the uuidForm fact is the FIRST rung of the UUID ladder.
; DeDService.GetActorContext(ak, "uuidForm") HIT returns
; {"value":"<dec>,0xHEX","source":"native:uuid",...}; the decimal prefix is
; the ready JSON literal (the same contract as _UuidDecimal: bare, unquoted,
; the DB 64-bit INTEGER form). MISS tail = the [REV-169] path VERBATIM
; (GetEntityUUID + _UuidDecimal + quoted-hex fallback); "" = no uuid at all.
; Sentinels fire on every HIT and every MISS-tail per actor -- the
; duplicate-resolve watch (leg 4b) is countable from the log alone.
String Function _UuidJsonLiteralCtx(Actor akActor)
    If akActor && _bDeDServiceCtx()
        String sCtx = DeDService.GetActorContext(akActor, "uuidForm")
        If sCtx != ""
            Int iV = StringUtil.Find(sCtx, "\"value\":\"")
            If iV >= 0
                Int iS = iV + 9
                Int iE = StringUtil.Find(sCtx, ",", iS)
                If iE < 0 || iE <= iS
                    iE = StringUtil.Find(sCtx, "\"", iS)
                EndIf
                If iE > iS
                    Debug.Trace("[SNAnimGS] actor-context uuidForm HIT (" + akActor.GetDisplayName() + ") -- REV-170")
                    Return StringUtil.Substring(sCtx, iS, iE - iS)
                EndIf
            EndIf
        EndIf
        Debug.Trace("[SNAnimGS] actor-context uuidForm MISS -> [REV-169] tail (" + akActor.GetDisplayName() + ") -- REV-170")
    EndIf
    String sUuid = SkyrimNetApi.GetEntityUUID(akActor)
    If sUuid == ""
        Return ""
    EndIf
    String sVal = _UuidDecimal(sUuid)
    If sVal == ""
        sVal = "\"" + sUuid + "\""
    EndIf
    Return sVal
EndFunction

; REV-173 Path A (user ruling): the bio probe is RETIRED. The probe used the
; Papyrus RenderTemplate single-arg channel, which binds its value STRING-typed
; at the API boundary -- the bio selector requires number (type_error.302,
; REV-172 S208: 230 historical errors / 9 uuids, 0 successes ever). Bios now
; render IN-TEMPLATE in the consideration prompts from pack-sourced uuid
; literals (the JSON-document channel, typed at parse). The GSAnim.BioProbeOK.169
; key is orphaned per the no-migration ruling (stale values simply ignored).

String Function _MusePackContext(Actor ak, Int anPool, Actor akAudience = None, String asSteer = "", \
                                 String asCadenceKey = "GSAnim.NudgeInterval", \
                                 String asMethodKey = "GSAnim.SanguineSelectionMethod", \
                                 Int aiMethodDefault = 1, \
                                 String asSubjectPoolKey = "GSAnim.SanguineSubject")
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
    ; Arousal (REV-85 aroused-lean leg 1, posing-gender.md §2d): the REV-82 tiering
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
    ; REV-19 Task 2: npcName fallback chain. The 09-16 session produced one render with an
    ; EMPTY "## The NPC" header (17:54:40, Papyrus confirmed the pending actor was Frabbi) —
    ; GetDisplayName() can transiently return "" (name API edge). Fallback: display name ->
    ; actor base name -> race+role descriptor; an empty name still renders the header text
    ; itself, so the worst case is a descriptive label, never a blank. Unconditional
    ; sentinel per ruleset 5 (fires only when the fallback engaged).
    ; REV-26 Task 1c: sex field for the prompt's split guidance — the LLM must know it is
    ; picking for a man or a woman (the library line carries the male-safe half). Same
    ; _SexOf source as every gate (leveled-safe, 6a). Computed BEFORE the fallback chain
    ; so the race+role descriptor is gender-aware too (rev-26).
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
    ; REV-85 aroused-lean: stash the tier for the fire-time [arousal lean] sentinel
    ; (single-in-flight member — cleared by the next pack, harmless when stale).
    _sMuseArous = sArous
    ; REV-85 Phase B: two new context fields for the prompt's Jinja gates. posePolicy:
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
    ; REV-163 (picker decommission): the itemized pose catalog rides the SAME
    ; consideration call -- warning + description + move list per category
    ; (_MusePoseCatalogText), so the model that already holds the full scene
    ; context also picks the exact move. Text carries no quotes/backslashes;
    ; line separators are JSON-escaped newlines, decoded at render.
    ; REV-173 Path A: the bioAbsent flag is retired with the probe (see the
    ; _gsBioProbeOK retirement banner above; the consideration templates
    ; render bios unconditionally from this pack's npcUUID).
    String sCatalog = _MusePoseCatalogText()
    ; REV-167e D.1a: built by SEQUENTIAL accumulation, never one giant Return
    ; expression. The 10-27 trace (5/5 contextJson parse errors, columns 67/68/
    ; 70/73 = the npcUUID->npcSex join, missing comma) proved the single-
    ; expression build drops runtime pairs even though both the .psc and the
    ; PEX string table carry every literal correctly -- the Papyrus long-
    ; expression temp-overflow class (function temp-vars past ::temp320).
    ; Each statement below is small; output shape is byte-identical to the
    ; 167d template. Gate-side parse check receipt: rev167e_sim.
    ; REV-169 leg 2 (S202 Leg 3 hex-source map): the consideration pack's npcUUID
    ; still carried the QUOTED HEX form -- the 25-error source (the four
    ; consideration prompts forward it into render_character_profile and the
    ; selector's number contract rejects the string). Same form as the three
    ; 167e RenderTemplate sites: _UuidDecimal, bare/unquoted; malformed hex
    ; falls back to the 167d quoted-hex string (degradation-safe underneath).
    ; REV-170 Leg 4: ctx-first UUID literal (the uuidForm fact; MISS tail =
    ; the [REV-169] decimal/quoted-hex path verbatim, inside the helper).
    String sUuidVal = _UuidJsonLiteralCtx(ak)
    ; [REV-174 D3 3.1/3.2 GS] THE TWO-STAGE PACK GROWTH: the subject block
    ; (subjectName/subjectSex/subjectArousal/subjectUUID -- the A10 NAMED
    ; arousal field; A17) + candidates[] (the proximity roster, built FRESH
    ; here so the roster the prompt sees is the roster _GSResolveTarget
    ; matches against at answer time -- the SAME member array, no re-derive
    ; drift). The legacy npc* keys stay (bio_probe-era templates still read
    ; them). Sequential accumulation per REV-167e D.1a (no giant expression).
    _GSMuseRosterBuild(ak, anPool)
    String s = "{\"npcName\":\"" + _GSJsonEsc(sName) + "\",\"npcRace\":\"" + sRace + "\""
    s = s + ",\"npcUUID\":" + sUuidVal
    s = s + ",\"npcSex\":\"" + sSex + "\""
    s = s + ",\"location\":\"" + _GSJsonEsc(sLoc) + "\",\"nearby\":\"" + _GSJsonEsc(sNear) + "\""
    s = s + ",\"arousal\":\"" + sArous + "\""
    s = s + ",\"arousalTier\":\"" + sTier + "\",\"posePolicy\":\"" + sPolicy + "\""
    s = s + ",\"timeOfDay\":\"" + sTod + "\""
    s = s + ",\"poseCatalog\":\"" + sCatalog + "\""
    s = s + ",\"subjectName\":\"" + _GSJsonEsc(sName) + "\""
    s = s + ",\"subjectSex\":\"" + sSex + "\""
    s = s + ",\"subjectArousal\":\"" + sArous + "\""
    s = s + ",\"subjectUUID\":" + sUuidVal
    s = s + ",\"candidates\":[" + _GSMuseRosterJson() + "]"
    s = s + _MusePackAudienceField(akAudience)
    ; [REV-178 L4] THE §6.5 ADDITIVE GROWTH: subjectPool (sticky-5 +
    ; dialogue-priority + proximity, built fresh here), player (TARGET-pool
    ; constant only, OR2), cadenceBand (V6: read at dispatch), and
    ; selectionMethod. Existing fields byte-stable above.
    _GSNarrSubjectPoolBuild(ak, anPool, StorageUtil.GetIntValue(None, asSubjectPoolKey, 0))
    s = s + ",\"subjectPool\":[" + _GSNarrSubjectPoolJson() + "]"
    String sPlayerF = _GSPlayerField()
    If sPlayerF != ""
        s = s + ",\"player\":" + sPlayerF
    EndIf
    s = s + ",\"cadenceBand\":\"" + _GSCadenceBand(asCadenceKey, fMuseNudgeIntervalSec) + "\""
    s = s + ",\"selectionMethod\":\"" + _GSSelectionMethodWord(asMethodKey, aiMethodDefault) + "\""
    ; [REV-178b Leg 1] the moments fact line (recent-fire ledger, plain facts
    ; only -- the spread GUIDANCE lives in the prompt task text, ruled): rides
    ; every pack (empty = no line rendered; the template gates on truthiness).
    String sMoments = _MomentsLedgerText()
    s = s + ",\"momentsRecently\":\"" + _GSJsonEsc(sMoments) + "\""
    Debug.Trace("[SNAnimGS] moments fact line rendered (len " + StringUtil.GetLength(sMoments) + ", ledger " + _iMomCount + "/5) -- REV-178b Leg 1 sentinel")
    ; [REV-178d Leg 3.3] RecentPoses (S244 variety): the last 5 fired pose
    ; labels, newest-first -- FACT + the prompt-side encouragement clause
    ; ONLY, no mechanical exclusion (the 178b Leg 1 discipline). Sentinel'd
    ; render; empty ledger = empty field (the template gates on truthiness).
    String sPoses = _MomentsPosesText()
    s = s + ",\"recentPoses\":\"" + _GSJsonEsc(sPoses) + "\""
    Debug.Trace("[SNAnimGS] recentPoses fact line rendered (len " + StringUtil.GetLength(sPoses) + ", ledger " + _iMomCount + "/5) -- REV-178d Leg 3.3 sentinel")
    ; [REV-174a A36] the CONDITIONAL PROMPT SECTION field: targetSteer rides
    ; the pack only when the mode's Target Selection is Bio Led (1) or
    ; Relationship Priority (2) -- facts in, trust the LLM; roster unfiltered.
    If asSteer != ""
        s = s + ",\"targetSteer\":\"" + _GSJsonEsc(asSteer) + "\""
    EndIf
    s = s + ",\"maxRecentEvents\":12}"
    ; [REV-178 L4/§6.5] the composition-level parse receipt (structural
    ; lint, run on the FINAL string; the devkit-side parse receipts at
    ; dogfood via request bodies).
    _GSJsonLintOK(s, "_MusePackContext")
    Return s
EndFunction

; REV-26 Task 1a (user ruling, approved split): MALE-OK vibe set — vibe-level split. The
; single _PoseVibe gender gate serves four callers (muse fire, T3, crosshair via its own
; validation, grid via _PoseDirect), so the vibe-level companion table is the small change:
; _PoseVibe now admits males ONLY for vibes in this set; the crosshair path is untouched
; (ruling: male refusal STAYS at the crosshair — the muse alone gains males) and T3 keeps
; female-only candidates (scan default), so no T3 behavior change.
; REV-85b (dogfood closure, curated-12 ruling): Plead joins the male-ok set — the begging
; register reads on any body (distress, not sensuality), closing the "curated no better
; than female-only" crosshair finding together with the sCat fix at the validation leg.
; Male-ok (12): the 8 approved neutrals (Stretch, Workout, Drink, ScratchHead, BraceArm,
; Meditate, HandOnChin, HandOnFace) + Dance (celebration register is genderless — the male
; vocabulary must express joy, user ruling) + Aroused (Baka's own BaboArousedMale01/02
; clips = authored male support) + GroundIdle (FULL 18-event pool, graded live — the two
; "(M ok)" poses.js events are known-good; the jank watch is the gate, narrow if needed)
; + Plead (REV-85b, curated-12).
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

; REV-20 direct-fire allowlist (user-approved 09-16, docs/MUSE_DIRECT_FIRE_DESIGN.md +
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
    ; REV-24 Task 3 (approved tiers): Tier 1 — Stretch/Workout reuse their existing GS CSV
    ; vibes (_VibeCSV "stretch"/"workout", same event pools as the grid + T3 pool; already
    ; stop-pose-compatible via the GS key set); ScratchHead/BraceArm/Meditate are the new
    ; single-actor Babo idle-event branches added to _VibeCSV this rev. Tier 2 — Drink: the
    ; NORMAL hold only (BaboDrinkNormal; the blackout branch + baka_opportunity remain
    ; Baka's exclusive path — see _VibeCSV's rev-24 block). Tier 3 was REJECTED by user
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
    ; REV-25 Task 2a (user spec): VOCABULARY = FIREABLE SET — the prompt library and the fire
    ; allowlist are now ONE list; every muse decision ends in visible action. Dropped entirely
    ; from the muse vocabulary (still in the crosshair grid, unreachable by the muse): PoseIdle
    ; (no-op fire) and the hazard set (Food, Sleep, Autograph, Pickpocket, Crouch, Kneel,
    ; Dogeza). The seven entries below complete the vocabulary from poses that were previously
    ; seed-only: all reuse EXISTING GS CSV vibes (selftouch/present/ground_sexy/ground_idle/
    ; submission/plead — same event pools as the crosshair grid + T3), single-actor, no props.
    ; Drool (2c evaluation, user advocacy): BaboDroolingFace — see the _VibeCSV rev-25 block.
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

; [REV-174h Fix 1] CLIP -> pose-key reverse lookup (companion to _MuseFireVibe
; directly above). The two-stage contract asks the LLM for the EXACT move
; ("POSE: <pose name> | CLIP: <exact move key>", REV-163's one-pass ruling),
; and the LLM reliably names the MOVE LABEL in POSE:, not the category key
; (174f dogfood: 8/8 label answers, 7/8 valid CLIPs, 8/8 dropped at the old
; key-only gate). This resolves the category from POOL MEMBERSHIP -- the vibe
; whose _VibeEventsFor csv contains the CLIP -- and returns the canonical
; POSE KEY so every downstream use (_MuseFireLabel, _MuseFireSuccess, desc
; composition) reads canonical. The EXACT CLIP still fires via the REV-152
; sForceEvent plumbing at the fire site; random selection stays confined to
; absent/off-pool CLIPs (REV-163's ruled degenerate cases only) -- NO
; category-random regression.
String Function _MuseFirePoseKeyFromClip(Actor akPerf, String sClip)
    If sClip == "" || !akPerf
        Return ""
    EndIf
    String[] sPoseKeys = New String[19]
    sPoseKeys[0] = "PoseSeduce"
    sPoseKeys[1] = "PoseDance"
    sPoseKeys[2] = "PoseDanceSexy"
    sPoseKeys[3] = "PoseHandOnChin"
    sPoseKeys[4] = "PoseHandOnFace"
    sPoseKeys[5] = "PoseAroused"
    sPoseKeys[6] = "PoseStretch"
    sPoseKeys[7] = "PoseWorkout"
    sPoseKeys[8] = "PoseScratchHead"
    sPoseKeys[9] = "PoseBraceArm"
    sPoseKeys[10] = "PoseMeditate"
    sPoseKeys[11] = "PoseDrink"
    sPoseKeys[12] = "PoseSelfTouch"
    sPoseKeys[13] = "PosePresent"
    sPoseKeys[14] = "PoseGroundSexy"
    sPoseKeys[15] = "PoseGroundIdle"
    sPoseKeys[16] = "PoseSubmission"
    sPoseKeys[17] = "PosePlead"
    sPoseKeys[18] = "PoseDrool"
    String[] sVibes = New String[19]
    sVibes[0] = "seduce"
    sVibes[1] = "dance"
    sVibes[2] = "dance_sexy"
    sVibes[3] = "handonchin"
    sVibes[4] = "handonface"
    sVibes[5] = "aroused"
    sVibes[6] = "stretch"
    sVibes[7] = "workout"
    sVibes[8] = "scratchhead"
    sVibes[9] = "bracearm"
    sVibes[10] = "meditate"
    sVibes[11] = "drink"
    sVibes[12] = "selftouch"
    sVibes[13] = "present"
    sVibes[14] = "ground_sexy"
    sVibes[15] = "ground_idle"
    sVibes[16] = "submission"
    sVibes[17] = "plead"
    sVibes[18] = "drool"
    Int i = 0
    While i < 19
        String csv = _VibeEventsFor(akPerf, sVibes[i])
        If csv != "" && StringUtil.Find("," + csv + ",", "," + sClip + ",") != -1
            Return sPoseKeys[i]
        EndIf
        i += 1
    EndWhile
    Return ""
EndFunction

; REV-150 4.4 (register entry 29, user's 2026-10-24 edit pass - pending text of
; record): the three REWORDED per-pose variants ship as FULL-SENTENCE event
; descs on the vibe route (the registered texts carry "<NPC>" inline - they
; are desc lines, not slot-in labels, so the "strikes <label>." frame does
; not fit them; every other vibe keeps the REV-146a Task 3.1 frame). The
; noun-phrase labels stay in GSAnim.Vibe / _MuseFireLabel so the shared
; STOP wording ("relaxes out of <label>.") stays grammatical - the variant
; replaces only the pose-pair EVENT TEXT on this route.
String Function _PoseVibeDesc(String sVibe, String sLabel)
    ; [REV-180 A2/C1] the "just <label>." frame is RETIRED with the noun-phrase
    ;   table (wording 8, Call A = A2): labels are verb phrases now, so the
    ;   cue composes bare. The general-cue stash sites route through
    ;   _GSGeneralDesc (C1 spec 3.1); this helper remains for the pose-pair
    ;   cue text at the _PoseVibe emission site.
    Return " " + sLabel + "."
EndFunction

; REV-20: event/stop-wording label for a direct-fired pose. The three GS-vibe picks reuse
; the exact distilled one-liners their Pose*_Execute wrappers already ship (an approved
; string class, Phase 4); the three Babo-event picks carry new one-liners in the same
; register (flagged for user text approval in the rev-20 build report, ruleset §7).
String Function _MuseFireLabel(String sPose)
    ; [REV-180 A2/B1/D1, Entry 57.2 user-approved] the ONE verb-phrase label
    ; table: every row is a third-person-singular PRESENT-TENSE verb phrase,
    ; gender-neutral (third-person plural possessives), honest-steamy
    ; register. The one table serves the fire cue (via _GSGeneralDesc's
    ; label degrade + the pose-pair cue), the STOP wording ("no longer
    ; <label>." -- _StopWording), and the LLM-facing catalog cue. The
    ; noun-phrase rows are RETIRED (wording doc 8, Call A = A2).
    If sPose == "PoseSeduce"
        Return "settles into a wanton lean - weight on one hip, gaze holding the room"
    ElseIf sPose == "PoseDance"
        Return "breaks into a dance - light on the feet, playful, carefree, or triumphant"
    ElseIf sPose == "PoseDanceSexy"
        Return "dances slow and dirty - a sultry, enticing performance"
    ElseIf sPose == "PoseHandOnChin"
        Return "turns a thought over, chin in hand"
    ElseIf sPose == "PoseHandOnFace"
        Return "brings a hand to their face - holding something in"
    ElseIf sPose == "PoseAroused"
        Return "shifts their weight, restless and heated - arousal worn where everyone can see it"
    ElseIf sPose == "PoseStretch"
        Return "stretches long and unhurried - loosening tight muscles, athletic, a little showy"
    ElseIf sPose == "PoseWorkout"
        Return "runs a quick drill - keeping the body busy"
    ElseIf sPose == "PoseScratchHead"
        Return "scratches at their head, faintly unsure"
    ElseIf sPose == "PoseBraceArm"
        Return "braces an arm, weight settling, tension held"
    ElseIf sPose == "PoseMeditate"
        Return "settles into a quiet seat - eyes closed, breath slowing"
    ElseIf sPose == "PoseDrink"
        Return "takes a slow pull from a tankard, throat working"
    ElseIf sPose == "PoseSelfTouch"
        Return "slides a hand down their own body - touching themselves, unhurried, past caring who notices"
    ElseIf sPose == "PosePresent"
        Return "bends and offers - everything on display, nothing left to guess at"
    ElseIf sPose == "PoseGroundSexy"
        Return "stretches out on the ground, hips rolling slowly - an open invitation"
    ElseIf sPose == "PoseGroundIdle"
        Return "sinks to the floor right where they stood - spent, or saving themselves"
    ElseIf sPose == "PoseSubmission"
        Return "drops to their knees, hands open - surrendering, offered up, waiting to be used"
    ElseIf sPose == "PosePlead"
        Return "begs with their whole body - hands clasped, eyes pleading"
    ElseIf sPose == "PoseDrool"
        Return "stares dazed, mouth gone slack - somewhere past words"
    EndIf
    Return "strikes a pose"
EndFunction

; SendCustomPromptToLLM callback for the Sanguine mode nudge (gsanim_sanguine_consideration.prompt).
; success 1 = real answer; 0 = render/network failure -> treated as MISS (no seed, logged).
; Output contract (REV-163): "POSE: <name> | CLIP: <move key> | THOUGHT: <one-sentence
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
    ; Rev-9 ruling (b) re-check: combat that began during the in-flight consideration —
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
    ; [REV-174 D3 3.4 GS] THE TWO-STAGE ANSWER (the leg-2 prompt contract):
    ;   "TARGET: <exact roster name>" / "POSE: <name> | CLIP: <key>" /
    ;   "REACT: <lanes>" / "MISS" (the THOUGHT: field RETIRES with
    ;   R-SEEDED-THOUGHTS-RETIRED -- the thought LANE replaces seeded
    ;   thoughts; the LastMuse floor stamp moves to the landed answer below).
    If StringUtil.Find(response, "MISS") >= 0
        Debug.Trace("[SNAnimGS] sanguine mode two-stage answer: LLM MISS -- named drop, skip tick -- REV-174 D3 3.4 GS")
        If bDebug
            _MuseDebugHeartbeat(fNow, "miss (MISS)")
        EndIf
        Return
    EndIf
    String sTgt = _GSParseLine(response, "TARGET:")
    String sPose = _GSParseLine(response, "POSE:")
    String sReact = _GSParseLine(response, "REACT:")
    ; [REV-178 L5/L6] the narrative contract lines: SUBJECT (validated,
    ; may override the mechanical subject) + CASE (log-only, R10 phase 1;
    ; OR4: missing CASE = accept + sentinel, never degrade).
    String sSubj = _GSParseLine(response, "SUBJECT:")
    String sCase = _GSParseLine(response, "CASE:")
    If sCase == ""
        Debug.Trace("[SNAnimGS] narrative answer CASE missing -- pick accepted (OR4 accept+sentinel) -- REV-178 L6")
    Else
        Debug.Trace("[SNAnimGS] narrative CASE: " + sCase + " -- REV-178")
    EndIf
    If sSubj != "" && _GSSelectionMethodWord("GSAnim.SanguineSelectionMethod", 1) == "narrative"
        Actor akNarr = _GSNarrResolveSubject(sSubj, StorageUtil.GetIntValue(None, "GSAnim.SanguineSubject", 0))
        If akNarr && !akNarr.IsDead() && !akNarr.IsInCombat() && !_IsBusyElsewhere(akNarr)
            Debug.Trace("[SNAnimGS] narrative SUBJECT override: '" + sSubj + "' replaces mechanical pick " + ak.GetDisplayName() + " -- REV-178 L6")
            ak = akNarr
        ElseIf akNarr
            Debug.Trace("[SNAnimGS] narrative SUBJECT '" + sSubj + "' resolved but guard-failed at seed time -- degrading to mechanical pick (§7.2) -- REV-178 L6")
        Else
            Debug.Trace("[SNAnimGS] narrative SUBJECT invalid -- degrading to mechanical pick (§7.2) -- REV-178 L6")
        EndIf
    EndIf
    If sTgt == "" || sPose == ""
        Debug.Trace("[SNAnimGS] sanguine mode two-stage answer: parse miss (TARGET/POSE absent): " + ak.GetDisplayName() + " - " + response + " -- REV-174 D3 3.4 GS")
        If bDebug
            _MuseDebugHeartbeat(fNow, "miss (parse)")
        EndIf
        Return
    EndIf
    ; CLIP rides the POSE line's tail ("POSE: <name> | CLIP: <key>"); the
    ; _GSParseLine trim already handles the REV-21 trailing-space defect class.
    String sClip = ""
    Int iBar = StringUtil.Find(sPose, "|")
    If iBar >= 0
        sClip = _TrimTok(StringUtil.Substring(sPose, iBar + 1, StringUtil.GetLength(sPose)))
        sPose = _TrimTok(StringUtil.Substring(sPose, 0, iBar))
        If StringUtil.Find(sClip, "CLIP:") == 0
            sClip = _TrimTok(StringUtil.Substring(sClip, 5, StringUtil.GetLength(sClip)))
        Else
            sClip = ""
        EndIf
    EndIf
    If sPose == ""
        Debug.Trace("[SNAnimGS] sanguine mode two-stage answer: empty POSE field: " + ak.GetDisplayName() + " -- named drop -- REV-174 D3 3.4 GS")
        If bDebug
            _MuseDebugHeartbeat(fNow, "miss (empty fields)")
        EndIf
        Return
    EndIf
    ; ---- STAGE 2a: TARGET resolve -- exact-name roster match at fire time.
    ; The prompt's TARGET is who the pose is given TO (the performer); the
    ; tick's subject (ak) becomes the desc's audience when they differ.
    Actor akPerf = _GSResolveTarget(ak, sTgt)
    If !akPerf
        Debug.Trace("[SNAnimGS] sanguine mode two-stage answer: off-roster target '" + sTgt + "' -- named drop (no substitute pick, no dice) -- REV-174 D3 3.4 GS")
        If bDebug
            _MuseDebugHeartbeat(fNow, "off-roster target")
        EndIf
        Return
    EndIf
    ; fire-time gate re-run on the PERFORMER (the moment between ask and
    ; answer; the ak-subject guards above already ran). _PoseVibe re-runs its
    ; own gender/busy gates live as the defense-in-depth layer.
    If akPerf.IsDead() || akPerf.IsInCombat() || _IsBusyElsewhere(akPerf)
        Debug.Trace("[SNAnimGS] sanguine mode two-stage answer: performer guard failed at fire time: " + akPerf.GetDisplayName() + " -- named drop -- REV-174 D3 3.4 GS")
        Return
    EndIf
    If StorageUtil.GetIntValue(None, "GSAnim.Overdrive", 0) == 1
        Debug.Trace("[SNAnimGS] sanguine mode two-stage answer: sheogorath overdrive preempted the fire - named drop -- REV-174 D3 3.4 GS")
        Return
    EndIf
    ; the landed answer stamps the per-NPC floor (one write, both meanings --
    ; the REV-19 discipline, moved off the retired seed leg; the clamp stays
    ; at the read sites).
    StorageUtil.SetFloatValue(akPerf, "GSAnim.LastMuse", fNow)
    Debug.Trace("[SNAnimGS] sanguine mode two-stage answer: subject " + ak.GetDisplayName() + " -> TARGET " + akPerf.GetDisplayName() + ", POSE " + sPose + ", CLIP '" + sClip + "', REACT '" + sReact + "' -- REV-174 D3 3.4 GS")
    String sFireVibe = _MuseFireVibe(sPose)
    If sFireVibe == "" && sClip != ""
        ; [REV-174h Fix 1] The LLM answered the MOVE LABEL in POSE: (the
        ; prompt's "exact move" ask -- 8/8 dogfood ticks in 174f) while the
        ; CLIP arrived valid 7/8. Reverse-resolve the category from the
        ; CLIP's pool membership and CANONIZE the pose key: the exact CLIP
        ; still fires via sForceEvent below (the REV-152 plumbing); random
        ; draws stay confined to absent/off-pool CLIPs (REV-163 preserved).
        String sPoseKey = _MuseFirePoseKeyFromClip(akPerf, sClip)
        If sPoseKey != ""
            Debug.Trace("[SNAnimGS] sanguine mode two-stage answer: pose-key miss ('" + sPose + "') -- CLIP '" + sClip + "' resolved category '" + sPoseKey + "' -- REV-174h")
            sPose = sPoseKey
            sFireVibe = _MuseFireVibe(sPose)
        EndIf
    EndIf
    If sFireVibe == ""
        Debug.Trace("[SNAnimGS] sanguine mode two-stage answer: not allowlisted (" + sPose + ") -- named drop -- REV-174 D3 3.4 GS")
        Return
    EndIf
    If !_GenderAdmits(akPerf, sFireVibe)
        Debug.Trace("[SNAnimGS] sanguine mode two-stage answer: gender policy veto (" + sPose + " not admitted for " + akPerf.GetDisplayName() + ", mode " + _GenderPolicy() + ") -- named drop -- REV-174 D3 3.4 GS")
        Return
    EndIf
    ; CLIP validation (the proven REV-163 leg): member of the fired pool or
    ; degrade to the pool's random draw (sentinel at fire time, never a miss).
    String sForceEvent = ""
    If sClip != ""
        String csvMuse = _VibeEventsFor(akPerf, sFireVibe)
        If StringUtil.Find("," + csvMuse + ",", "," + sClip + ",") != -1
            sForceEvent = sClip
            Debug.Trace("[SNAnimGS] sanguine mode two-stage fire: LLM move pick '" + sClip + "' (cat '" + sFireVibe + "')")
        Else
            Debug.Trace("[SNAnimGS] sanguine mode two-stage fire: LLM move pick '" + sClip + "' NOT in pool '" + sFireVibe + "' - degrading to random draw")
        EndIf
    Else
        Debug.Trace("[SNAnimGS] sanguine mode two-stage fire: no CLIP in answer - random draw within the category")
    EndIf
    ; [REV-180 C1 spec 3.2 Option A] the general-cue desc target (the "for"
    ; slot) is computed BEFORE the fire so _PoseVibe composes the general
    ; cue from it (the 6th C-4 argument); same logic as the lane call below.
    Actor akDescTgt = None
    If akPerf != ak
        akDescTgt = ak      ; the tick's subject takes the desc's "for" slot
    EndIf
    If _PoseVibe(akPerf, sFireVibe, _MuseFireLabel(sPose), sForceEvent, 1, akDescTgt)
        ; [A21] the desc composes from the FIRED clip (the _PoseVibe capture)
        ; -- a random draw below an absent/off-pool CLIP still resolves a
        ; descriptor row instead of degrading to label form.
        String sFired = _sGSLastFiredEvent
        If sFired == ""
            sFired = sClip
        EndIf
        ; [REV-178c Leg 3] the CASE sentence rides the composed desc (the
        ; reasoning line; narrative path only -- this is the with-case call).
        _MuseFireSuccess(akPerf, sPose, fNow, _GSComposeDesc(akPerf, akDescTgt, sFired, _MuseFireLabel(sPose), sCase), sReact, akDescTgt)
        ; [REV-178 L4] stickiness: this fire's performer + desc target are
        ; next tick's sticky pair (§6.1.4).
        _GSNarrStickyRemember(akPerf, akDescTgt)
    Else
        Debug.Trace("[SNAnimGS] sanguine mode two-stage fire REFUSED (no event sent): " + akPerf.GetDisplayName() + " (" + sPose + ") -- reason per the refusal sentinel above -- REV-174 D3 3.4 GS")
    EndIf
EndFunction

; REV-167 (entry 44, §7.4) — SendCustomPromptToLLM callback for the Sheogorath
; perverse-fit consideration (gsanim_sheogorath_consideration.prompt). Output
; contract: "POSE: <pose name> | CLIP: <exact move key>" / "POSE: <pose name>"
; / "MISS" (no THOUGHT — Sheogorath stays thoughtless, the §11.4 lean).
; Guards are RE-CHECKED here (fire time) — the moment between ask and answer.
; The POSE is validated against the T3 vibe pool (_OdVibeNames); an off-pool
; answer degrades to the shipped weighted dice draw (sentinel'd), never a
; miss and never a fall-through. Fire routes through _PoseVibe with route tag
; 2 (the emergent lane, the same tag the shipped T3 fire carries) so the CLIP
; rides the REV-163 exact-pick plumbing; the GSAnim.T3Mark receipt gate is set
; at dispatch and cleared on refusal (the shipped 3.1 pattern).
; No justification seed on this path — Sheogorath is thoughtless by design.
String Function _TrimTok(String asIn)
    While StringUtil.GetLength(asIn) > 0 && StringUtil.GetNthChar(asIn, 0) == " "
        asIn = StringUtil.Substring(asIn, 1, StringUtil.GetLength(asIn) - 1)
    EndWhile
    While StringUtil.GetLength(asIn) > 0 && StringUtil.GetNthChar(asIn, StringUtil.GetLength(asIn) - 1) == " "
        asIn = StringUtil.Substring(asIn, 0, StringUtil.GetLength(asIn) - 1)
    EndWhile
    Return asIn
EndFunction

Function OnSheoConsideration(String response, Int success)
    Actor ak = _sheoPendingActor
    _sheoPendingActor = None
    If !ak || ak.IsDead() || ak.IsInCombat() || _IsBusyElsewhere(ak)
        If ak
            Debug.Trace("[SNAnimGS] sheogorath perverse-fit dropped - actor-local guard failed at fire time: " + ak.GetDisplayName())
        Else
            Debug.Trace("[SNAnimGS] sheogorath perverse-fit dropped - pending actor vanished at fire time")
        EndIf
        Return
    EndIf
    If success != 1 || response == ""
        Debug.Trace("[SNAnimGS] sheogorath perverse-fit miss (success=" + success + "): " + ak.GetDisplayName())
        Return
    EndIf
    ; [REV-174 D3 3.4 GS] the leg-2 two-stage contract rides here too:
    ; TARGET:/POSE:(| CLIP:)/REACT: or MISS (no THOUGHT -- §11.4 lean kept).
    If StringUtil.Find(response, "MISS") >= 0
        Debug.Trace("[SNAnimGS] sheogorath two-stage answer: LLM MISS -- named drop -- REV-174 D3 3.4 GS")
        Return
    EndIf
    String sTgtSheo = _GSParseLine(response, "TARGET:")
    String sReactSheo = _GSParseLine(response, "REACT:")
    ; [REV-178 L5/L6] the narrative contract lines ride here too (Sheo
    ; defaults RANDOM per R1; the SUBJECT override applies only when the
    ; user flips the mode to Narrative). OR4: CASE missing = accept +
    ; sentinel.
    String sSubjSheo = _GSParseLine(response, "SUBJECT:")
    String sCaseSheo = _GSParseLine(response, "CASE:")
    If sCaseSheo == ""
        Debug.Trace("[SNAnimGS] sheogorath narrative CASE missing -- pick accepted (OR4 accept+sentinel) -- REV-178 L6")
    Else
        Debug.Trace("[SNAnimGS] sheogorath narrative CASE: " + sCaseSheo + " -- REV-178")
    EndIf
    If sSubjSheo != "" && _GSSelectionMethodWord("GSAnim.SheogorathSelectionMethod", 0) == "narrative"
        Actor akNarrSheo = _GSNarrResolveSubject(sSubjSheo, StorageUtil.GetIntValue(None, "GSAnim.SheogorathSubject", 0))
        If akNarrSheo && !akNarrSheo.IsDead() && !akNarrSheo.IsInCombat() && !_IsBusyElsewhere(akNarrSheo)
            Debug.Trace("[SNAnimGS] sheogorath narrative SUBJECT override: '" + sSubjSheo + "' replaces mechanical pick " + ak.GetDisplayName() + " -- REV-178 L6")
            ak = akNarrSheo
        ElseIf akNarrSheo
            Debug.Trace("[SNAnimGS] sheogorath narrative SUBJECT '" + sSubjSheo + "' resolved but guard-failed -- degrading to mechanical pick (§7.2) -- REV-178 L6")
        Else
            Debug.Trace("[SNAnimGS] sheogorath narrative SUBJECT invalid -- degrading to mechanical pick (§7.2) -- REV-178 L6")
        EndIf
    EndIf
    Int iPose = StringUtil.Find(response, "POSE:")
    If iPose < 0
        Debug.Trace("[SNAnimGS] sheogorath perverse-fit miss (parse): " + ak.GetDisplayName() + " - " + response)
        Return
    EndIf
    ; STAGE 2a: TARGET resolve -- the wrongness lands on the named roster
    ; actor; off-roster TARGET = named drop (no substitute, no dice); an
    ; absent TARGET line degrades to the pending subject, sentinel'd.
    Actor akPerf = ak
    If sTgtSheo != ""
        akPerf = _GSResolveTarget(ak, sTgtSheo)
        If !akPerf
            Debug.Trace("[SNAnimGS] sheogorath two-stage answer: off-roster target '" + sTgtSheo + "' -- named drop (no substitute pick, no dice) -- REV-174 D3 3.4 GS")
            Return
        EndIf
    Else
        Debug.Trace("[SNAnimGS] sheogorath two-stage answer: no TARGET line -- firing on the pending subject (degrade, sentinel'd) -- REV-174 D3 3.4 GS")
    EndIf
    If akPerf.IsDead() || akPerf.IsInCombat() || _IsBusyElsewhere(akPerf)
        Debug.Trace("[SNAnimGS] sheogorath two-stage answer: performer guard failed at fire time: " + akPerf.GetDisplayName() + " -- named drop -- REV-174 D3 3.4 GS")
        Return
    EndIf
    Int iClipMark = StringUtil.Find(response, "| CLIP:")
    String sClip = ""
    String sPose = ""
    If iClipMark > iPose
        String sClipRaw = StringUtil.Substring(response, iClipMark + 7, StringUtil.GetLength(response))
        Int iNlC = StringUtil.Find(sClipRaw, "\n")
        If iNlC >= 0
            sClipRaw = StringUtil.Substring(sClipRaw, 0, iNlC)
        EndIf
        sClip = _TrimTok(sClipRaw)
        sPose = StringUtil.Substring(response, iPose + 5, iClipMark - iPose - 5)
    Else
        sPose = StringUtil.Substring(response, iPose + 5, StringUtil.GetLength(response))
    EndIf
    Int iBar = StringUtil.Find(sPose, "|")
    If iBar >= 0
        sPose = StringUtil.Substring(sPose, 0, iBar)
    EndIf
    Int iNlP = StringUtil.Find(sPose, "\n")
    If iNlP >= 0
        sPose = StringUtil.Substring(sPose, 0, iNlP)
    EndIf
    sPose = _TrimTok(sPose)
    ; Validate against the T3 vibe pool (exact keys only — the pool IS the
    ; admitted action set; a stray POSE name degrades to the shipped dice).
    String sAction = ""
    Int i = 0
    While i < _OdVibeWeights.Length
        If sPose == _OdVibeNames[i]
            sAction = _OdVibeNames[i]
            i = _OdVibeWeights.Length
        EndIf
        i += 1
    EndWhile
    If sAction == ""
        sAction = _OdVibeNames[_OdVibeWeights.Length - 1]
        Int iRoll = Utility.RandomInt(1, _OdWeightTotal)
        Int iAcc = 0
        i = 0
        While i < _OdVibeWeights.Length
            iAcc += _OdVibeWeights[i]
            If iRoll <= iAcc
                sAction = _OdVibeNames[i]
                i = _OdVibeWeights.Length
            EndIf
            i += 1
        EndWhile
        Debug.Trace("[SNAnimGS] sheogorath perverse-fit: POSE '" + sPose + "' not in T3 vibe pool - degrading to shipped weighted dice (" + sAction + ")")
    Else
        Debug.Trace("[SNAnimGS] sheogorath perverse-fit answer: " + ak.GetDisplayName() + " -> " + sAction + " (clip '" + sClip + "')")
    EndIf
    ; REV-169 leg 1 (S202 Leg 5 root cause): _OdVibeNames are POSE names
    ; ("PoseWorkout"); _VibeEventsFor/_VibeCSV key on VIBE names ("workout").
    ; The 10-28 dogfood: _VibeCSV("PoseWorkout") = "" BY CONSTRUCTION -> every
    ; Sheo fire refused with "empty vibe event pool". Port the Sanguine lane's
    ; _MuseFireVibe translation here so the pool lookups receive vibe keys. All
    ; five _OdVibeNames entries map (PoseDance/PoseDanceSexy/PoseStretch/
    ; PoseWorkout/PoseSeduce); a miss is a DEFECT, sentinel'd as EMPTY and
    ; refusing (never a silent random draw across a broken pool).
    String sFireVibe = _MuseFireVibe(sAction)
    If sFireVibe == ""
        Debug.Trace("[SNAnimGS] sheogorath perverse-fit REFUSED (EMPTY pool path: pose '" + sAction + "' has no vibe translation) -- REV-169")
        Return
    EndIf
    ; REV-169 leg 1 sentinel: fired pool name + event count on EVERY Sheo fire
    ; attempt (the REFUSED-vs-EMPTY split lives above and inside _PoseVibe).
    String csvSheo = _VibeEventsFor(ak, sFireVibe)
    Int iEvents = 0
    Int iCsv = 0
    Int iCsvLen = StringUtil.GetLength(csvSheo)
    While iCsv < iCsvLen
        If StringUtil.GetNthChar(csvSheo, iCsv) == ","
            iEvents += 1
        EndIf
        iCsv += 1
    EndWhile
    If csvSheo != ""
        iEvents += 1
    EndIf
    Debug.Trace("[SNAnimGS] sheogorath fire pool: vibe='" + sFireVibe + "' (pose '" + sAction + "'), events=" + iEvents + " -- REV-169")
    ; CLIP validation (defense in depth — the caller validates, the pool guards).
    String sForceEvent = ""
    If sClip != ""
        If StringUtil.Find("," + csvSheo + ",", "," + sClip + ",") != -1
            sForceEvent = sClip
        Else
            Debug.Trace("[SNAnimGS] sheogorath perverse-fit: CLIP '" + sClip + "' NOT in pool '" + sFireVibe + "' - degrading to random draw")
        EndIf
    Else
        Debug.Trace("[SNAnimGS] sheogorath perverse-fit: no CLIP in answer - random draw within the category")
    EndIf
    StorageUtil.SetFloatValue(akPerf, "GSAnim.T3Mark", Utility.GetCurrentRealTime())
    ; [REV-180 C1 spec 3.2 Option A] the desc target computed BEFORE the fire
    ; so _PoseVibe composes the general cue from it (6th C-4 argument).
    Actor akDescTgtSheo = None
    If akPerf != ak
        akDescTgtSheo = ak
    EndIf
    If _PoseVibe(akPerf, sFireVibe, _MuseFireLabel(sAction), sForceEvent, 2, akDescTgtSheo)
        Debug.Trace("[SNAnimGS] sheogorath T3 perverse-fit FIRE: " + akPerf.GetDisplayName() + " -> " + sFireVibe + " (pose '" + sAction + "')")
        ; [REV-174 D3 4.5 GS] the four-lane fan-out with the answer's REACT
        ; (the Sheogorath lanes own their fire here -- no _MuseFireSuccess on
        ; this path). [A21] desc composes from the FIRED clip when captured,
        ; the LLM CLIP otherwise.
        String sFiredSheo = _sGSLastFiredEvent
        If sFiredSheo == ""
            sFiredSheo = sClip
        EndIf
        _GSLaneFire("Sheogorath", akPerf, akDescTgtSheo, _GSComposeDesc(akPerf, akDescTgtSheo, sFiredSheo, _MuseFireLabel(sAction), sCaseSheo), sReactSheo, False) ; [REV-178c Leg 3] with-CASE desc (reasoning line)
    Else
        StorageUtil.SetFloatValue(akPerf, "GSAnim.T3Mark", 0.0)   ; no event sent — clear the mark (0.0 = none)
        Debug.Trace("[SNAnimGS] sheogorath T3 perverse-fit REFUSED (no event sent): " + akPerf.GetDisplayName() + " (" + sFireVibe + ") -- reason per the refusal sentinel above")
    EndIf
EndFunction

; REV-17 1c rider: shared "is the muse debug window open" read with a cross-boot clamp.
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
    Debug.Notification("Sanguine Mode - stirring (no nudge this cycle)")   ; REV-174a D5 " - " sweep
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
    Debug.Notification("Sanguine Mode - debug window re-armed (next activation).")   ; REV-174a D5 " - " sweep
    Debug.Trace("[SNAnimGS] sanguine mode debug window re-armed via ReArmMuseDebug().")
EndFunction

; ── REV-103 S3: Baka-half presence probe ─────────────────────────────────────
; The 15 Baka-hosted pose executors (indices 12-26 of _PoseActions) live in the Baka
; integration's quest script; on a Baka-absent install those action names resolve to
; nothing and every SkyrimNetApi call naming one is a wasted call plus a not-found
; line. The Baka motherboard advertises its halves through the service registry
; (SNBaka.Svc.* keys on its own quest form, QUST 0xD62 of SkyrimNet_BakaIntegration.esp,
; REV-74 shape); the GS probe here is the soft-read mirror of the motherboard's own
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

; REV-105 S2: the busy-state service probe — the same soft-read mirror as
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

; REV-105 S2 one-shot sentinels (the _bMuseDebugArmedThisBoot pattern): the busy
; queries are hot-path (daemon scans), so the "consulted" (probe state) and
; "result" (first busy-block via a Baka key) sentinels fire ONCE per game load —
; both observable in the Papyrus log without spam. The Baka-side counterpart is
; the registry's own arm-pass log line ("service-registry: 'busy.baka-half'").
Bool _bBusySvcProbeSentinel  = False
Bool _bBusySvcBlockSentinel = False

; REV-103 S3: the 15 Baka-hosted names of the 27-name dispatch (_PoseActions = 12
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
    ; [REV-174d Leg 2 / item 11] fOdExpireSeconds is a FUNCTION-LOCAL literal (user ruling
    ;   2026-10-31): the former quest-script MEMBER was save-persisted -- the dogfood save's
    ;   serialized 300.0 (pre-REV-169-6) overrode the compiled 3600.0 initializer on load
    ;   (REV-174c Leg 3 root cause). Local literal = 3600.0 on ANY save age.
    Float fOdExpireSeconds = 3600.0
    _EnsurePools()   ; Phase 4d: stale-instance heal — the T2 loop reads _PoseActions and _OdCue reads _OdCues
    StorageUtil.SetIntValue(None, "GSAnim.Overdrive", 1)
    Int i = 0
    Int iSkipped = 0
    Bool bBakaHalf = _BakaPoseHalfPresent()   ; REV-103 S3: one probe per pass, not per name
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
    StorageUtil.SetFloatValue(None, "GSAnim.LastPoseFire", Utility.GetCurrentRealTime())  ; observability only since REV-137f 3.3 (silence-floor reader retired)
    StorageUtil.SetFloatValue(None, "GSAnim.LastOdCue", 0.0)
    ; REV-137d 3.2 -> REV-137f 3.3 receipt: the ON state, its armed cadence parameters
    ; and the policy mode are trace-receipted. Census of the armed machinery
    ; (REV-137f): poll 15s, T3 every-15s multi-poser (silence floor RETIRED), expire 3600s (REV-169 leg 6).
    Debug.Trace("[SNAnimGS] sheogorath mode ON (REV-137f receipt): armed -- poll 15s, T3 multi-poser every " \
        + fOdT3IntervalSec + "s (one-at-a-time silence floor retired; overlapping lifetimes permitted), expire " + fOdExpireSeconds \
        + "s, T3 pool policy mode " + _GenderPolicy() + " (REV-137d 3.1 blanket)")
    Debug.Notification("Sheogorath Mode - A haze of madness shimmers in the air.")   ; REV-174a D5 USER-VERBATIM
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
    Bool bBakaHalf = _BakaPoseHalfPresent()   ; REV-103 S3: one probe per pass, not per name
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

; The 15s overdrive tick (REV-137f 3.3): expiry check (incl. combat-pause already applied
; upstream in OnUpdate), T1 cue if due, T3 every-interval multi-poser fire if due.
Function _OverdriveTick()
    _EnsurePools()   ; Phase 4d: heal BEFORE the body — in the stale instance the _OdCue crash aborted this tick before the T3 floor check could even run
    Float fNow = Utility.GetCurrentRealTime()
    If fNow >= StorageUtil.GetFloatValue(None, "GSAnim.OverdriveExpire", 0.0)
        _OverdriveOff("Sheogorath Mode ended (time).")
        Return
    EndIf
    _OdCue()
    ; REV-137f 3.3 (user ruling 2026-10-22, "I want chaos -- multiple posers and poses
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
        fLastT3 = 0.0   ; stale cross-session stamp -- house clamp class (REV-17 pattern)
    EndIf
    ; REV-159 5.2: the T3 cadence is now an MCM SLIDER value (15s-240s, the GS
    ; Poses page) carried on the fresh key GSAnim.T3Interval (default = the
    ; historic compiled member -- the 137f save-residue-safe pattern; existing
    ; installs keep 15s).
    Float fT3Interval = StorageUtil.GetFloatValue(None, "GSAnim.T3Interval", fOdT3IntervalSec)
    If fNow - fLastT3 >= fT3Interval
        StorageUtil.SetFloatValue(None, "GSAnim.LastT3Fire", fNow)
        Debug.Trace("[SNAnimGS] sheogorath mode tick: T3 multi-poser fire (clock " + (fNow - fLastT3) \
            + "s >= interval " + fT3Interval + "s; expire in " \
            + (StorageUtil.GetFloatValue(None, "GSAnim.OverdriveExpire", 0.0) - fNow) + "s; REV-137f)")
        _OdAutoPose()
    Else
        Debug.Trace("[SNAnimGS] sheogorath mode tick: T3 window not yet due (clock " + (fNow - fLastT3) \
            + "s < interval " + fT3Interval + "s; REV-137f)")
    EndIf
EndFunction

; T3 multi-poser (REV-137f 3.3): one random eligible NPC (policy-admitted, REV-137d 3.1 blanket)
; strikes a weighted solo-safe GS vibe. ExecuteAction bypasses eligibility AND cooldowns
; by design — our guard chain is the ONLY protection, so it's strict: _DaemonScan
; (policy-admitted/loaded/near/not-posing/not-combat) + _IsBusyElsewhere backstop + not
; currently T3-posed. The Pose*_Execute wrappers re-run their own gender/busy guards at
; dispatch, defense in depth. GS VIBES ONLY — never Baka, never two-actor, never
; targeted. After the fire, a justification thought seed lands (rc checked, harmless if
; it fails) and the silence clock re-arms via _PoseVibe's stamp.
; REV-137d 3.2: every attempt leg is receipted — pool-empty, candidate selection
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
    ; REV-167 t3 (entry 44, §5/2.3 GS leg): the Sheogorath SELECTION-MODE READS
    ; (§15.9: 0/0 defaults = the shipped dice pick above, byte-for-byte). The
    ; subject resolver owns the pick when set (walk guards inside, §15.2);
    ; empty filtered pool = skip tick, sentinel inside (§15.12) -- the dice
    ; pick above is NOT re-run (the resolver's pick is the tick's candidate).
    Int iSheoSub = _gsSelSubject("Sheogorath")
    Int iSheoTgt = _gsSelTarget("Sheogorath")
    ; [REV-174a A35/A36] per-fire shape (parity with the Sanguine tick):
    ; targetSteer text. [REV-174a A46] the Wide roster-cap branch is RETIRED
    ; with the option -- the cap is the standing 10, reset every tick.
    String sSheoSteer = _gsPlayerRuleSteerText()   ; [REV-178a Leg 1] player-rule sign (shared dispatch family; see the Sanguine bind)
    _iMuseRosterCap = 10
    If iSheoSub != 0 || iSheoTgt != 0
        Debug.Trace("[SNAnimGS] sheogorath selection read: subject=" + iSheoSub + " (" \
            + _gsSubjectSelName(iSheoSub) + ") target=" + iSheoTgt + " (" \
            + _gsTargetSelName(iSheoTgt) + ") -- REV-174a A35")
    EndIf
    If iSheoSub != 0
        Actor akRes = _gsResolveSubject("Sheogorath", iSheoSub, n)
        If !akRes
            Return   ; skip tick + sentinel inside the resolver
        EndIf
        If _IsBusyElsewhere(akRes)   ; re-run the backstop on the resolver's pick
            Debug.Trace("[SNAnimGS] sheogorath T3 attempt REFUSED: " + akRes.GetDisplayName() \
                + " busy at pick time (resolver pick backstop; pool n=" + n + ")")
            Return
        EndIf
        ak = akRes
        Debug.Trace("[SNAnimGS] sheogorath T3 candidate: " + ak.GetDisplayName() \
            + " (REV-167 selection subject=" + _gsSubjectSelName(iSheoSub) \
            + " replaces the random draw) -- REV-167 t3")
    EndIf
    ; REV-167 (entry 44, §7.4/§15.8): Sheogorath perverse-fit — the MCM default.
    ; Toggle GSAnim.SheoSelection (GS Poses page, "Sheogorath Selection"):
    ; 1/absent = Perverse Fit (the consideration call below); 0 = Random
    ; (the shipped dice path, byte-for-byte). Single-in-flight pending actor
    ; bridges to OnSheoConsideration; every guard re-checked at fire time
    ; there. A dispatch refusal degrades to the shipped weighted dice draw
    ; (never a silent no-op — the empty-pool honesty rule, §15.12).
    If StorageUtil.GetIntValue(None, "GSAnim.SheoSelection", 1) == 1
        ; REV-167 t3 (§5/2.3 GS leg): the audience draw rides the consideration
        ; pack (target=Random = no audience field, the shipped pack). Empty
        ; audience pool = skip tick BEFORE the call is spent (§15.12).
        Actor akAudSheo = None
        If iSheoTgt != 0
            akAudSheo = _gsResolveAudience("Sheogorath", iSheoTgt, ak, n)
            If !akAudSheo
                Return   ; skip tick + sentinel inside the resolver
            EndIf
        EndIf
        _sheoPendingActor = ak
        Int sentSheo = SkyrimNetApi.SendCustomPromptToLLM("gsanim_sheogorath_consideration", "", \
            _MusePackContext(ak, n, akAudSheo, sSheoSteer, "GSAnim.T3Interval", "GSAnim.SheogorathSelectionMethod", 0, "GSAnim.SheogorathSubject"), Self as Quest, "SkyrimNet_AnimationsGS", "OnSheoConsideration")
        If sentSheo == 1
            Debug.Trace("[SNAnimGS] sheogorath T3 perverse-fit consideration dispatched: " + ak.GetDisplayName() \
                + " (pool n=" + n + ", policy mode " + _GenderPolicy() + "); answer receipt per OnSheoConsideration")
            Return
        Else
            _sheoPendingActor = None
            Debug.Trace("[SNAnimGS] sheogorath T3 perverse-fit dispatch refused (rc=" + sentSheo + "): " \
                + ak.GetDisplayName() + " - degrading to the shipped weighted dice draw")
        EndIf
    EndIf
    If iSheoTgt != 0
        ; REV-167 t3: audience INERT on the dice path -- no consideration pack to
        ; steer, so no audience draw and no skip (the §15.12 skip binds where the
        ; audience is consumed; the receipt keeps the read honest).
        Debug.Trace("[SNAnimGS] sheogorath selection audience INERT on the dice path (setting=" \
            + _gsTargetSelName(iSheoTgt) + "; no consideration pack to steer) -- REV-167 t3")
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
    ; REV-135 (idle-interrupt service, spec 1.4.4): T3 routes through the same
    ; primitive — interruptible idle classes exit->recheck (incl. the
    ; gender-policy admit, live) -> fire instead of being silently dropped.
    If !_IdleFirePath(ak, sAction)
        Debug.Trace("[SNAnimGS] sheogorath T3 attempt REFUSED: idle interrupt (exit/recheck refused -- reason per the idle-svc sentinel above): " + ak.GetDisplayName())
        Return
    EndIf
    Debug.Trace("[SNAnimGS] T3 multi-poser auto-pose: " + ak.GetDisplayName() + " -> " + sAction)
    ; REV-137f 3.1: the receipt gate is a per-actor GSAnim.T3Mark timestamp set HERE at
    ; dispatch (cleared on a non-zero rc) and consumed by _PoseVibe's success leg within
    ; 30s -- the old _bT3InFlight member window closed at this function's synchronous
    ; return, before the async dispatch's fire reached the receipt block, so the
    ; user-ruled on-screen notification never printed (0/4 in the 10-22 dogfood log).
    StorageUtil.SetFloatValue(ak, "GSAnim.T3Mark", Utility.GetCurrentRealTime())
    Int rcOd = SkyrimNetApi.ExecuteAction(sAction, ak, "{}")
    If rcOd != 0
        StorageUtil.SetFloatValue(ak, "GSAnim.T3Mark", 0.0)   ; dispatch refused -- clear the mark (0.0 = none)
    Else
        ; [REV-174 D3 4.5 GS / A21b NOTE OF RECORD] the dice path's random-leg
        ; lane fire: NO LLM in the loop -> REACT "" -> all-enabled fan-out
        ; (random-leg semantics). The desc is the LABEL form here by design:
        ; the dispatch is async (ExecuteAction -> Pose*_Execute), so the
        ; fired clip is not knowable at this point -- the known interim
        ; degrade the dogfood sequencing note records (NOT a descriptors
        ; failure; end-to-end desc lands only on the consideration path).
        _GSLaneFire("Sheogorath", ak, None, ak.GetDisplayName() + " " + _MuseFireLabel(sAction) + ".", "", True)
    EndIf
    Debug.Trace("[SNAnimGS] sheogorath T3 attempt dispatched (rc=" + rcOd + "): " + ak.GetDisplayName() \
        + " -> " + sAction + "; accept/refuse receipt per the pose fire sentinels below")
    ; Justification seed: the same thought registers that drive muse, at performance pitch.
    SkyrimNetApi.GenerateNPCThought(ak, \
        "The music and the crowd's eyes have gotten to you - you feel like dancing for them.")
EndFunction
; Phase 4 rider: labels below are the distilled Phase 3 one-liners — they flow into the
; pose-pair events ("just <label>." since REV-174d Leg 3.1, emitted as
; gsanim_pose_emergent/_player since REV-174f Leg 3 — the ", holding
; it in place" tail removed by user ruling 2026-10-23) AND into the per-actor
; GSAnim.Vibe key the stop paths read for named-pose stop wording.
;
; REV-166 (the pose-vibe misbinding cure, post-release hot-fix class): every
; executor below passed its route tag (2) as the FOURTH positional argument —
; Papyrus has no named arguments, so the 2 bound to sForceEvent as the string
; "2", hit the REV-152 stray-key guard ("forced event '2' not in pool") and
; returned False silently on EVERY LLM-lane pose action since the REV-159
; caller rewrite (36-hour live window, 10-25 01:53 onward). The muse call site
; (route 1) was never affected — it passes all five arguments. The empty
; sForceEvent is now passed EXPLICITLY at every site so aiRoute receives the
; route tag; confirm-by-grep: no 4-argument _PoseVibe call remains anywhere.
Function PoseSeduce_Execute(Actor akInitiator)
    _PoseVibeVariant(akInitiator, "seduce", "a seductive pose - weight on one hip, gaze holding the room")
EndFunction
Function PoseSelftouch_Execute(Actor akInitiator)
    _PoseVibeVariant(akInitiator, "selftouch", "a suggestive, self-touching pose - arousal worn openly")
EndFunction
Function PosePresent_Execute(Actor akInitiator)
    _PoseVibeVariant(akInitiator, "present", "a bent-forward presenting pose, deliberately offering the view")
EndFunction
Function PoseDance_Execute(Actor akInitiator)
    _PoseVibeVariant(akInitiator, "dance", "a light, playful dance - feet answering the music")
EndFunction
Function PoseDanceSexy_Execute(Actor akInitiator)
    _PoseVibeVariant(akInitiator, "dance_sexy", "a slow, provocative dance - a performance with a single intended victim")
EndFunction
Function PoseGroundSexy_Execute(Actor akInitiator)
    _PoseVibeVariant(akInitiator, "ground_sexy", "a sultry sprawl on the ground - low, languid, unhurried")
EndFunction
Function PoseGroundIdle_Execute(Actor akInitiator)
    _PoseVibeVariant(akInitiator, "ground_idle", "a spent, sprawling rest on the ground")
EndFunction
Function PoseWorkout_Execute(Actor akInitiator)
    _PoseVibeVariant(akInitiator, "workout", "a set of exercises - strength and stamina on display")
EndFunction
Function PoseStretch_Execute(Actor akInitiator)
    _PoseVibeVariant(akInitiator, "stretch", "a long, reaching stretch")
EndFunction
Function PoseSubmission_Execute(Actor akInitiator)
    _PoseVibeVariant(akInitiator, "submission", "a surrendered pose - body lowered, the shape of yielding")
EndFunction
Function PosePlead_Execute(Actor akInitiator)
    _PoseVibeVariant(akInitiator, "plead", "a kneeling plea - lowered before someone it matters to")
EndFunction
Function PoseIdle_Execute(Actor akInitiator)
    _PoseVibeVariant(akInitiator, "idle", "an easy stance - hip against the wall, nowhere to be")
EndFunction

; Phase 4 rider: shared stop wording — names the held pose from GSAnim.Vibe when present,
; generic "the pose" fallback when the key is missing (crash-safety: any legacy pose or a
; stop arriving by a path that never stored a vibe still words cleanly).
; [REV-180 A2, Entry 57.3] NEW STOP FRAME: the "relaxes out of <label>." noun
; frame is RETIRED with the noun-phrase table (Call A = A2). The stored vibe
; label is now a PRESENT-TENSE verb phrase (_MuseFireLabel / the _PoseDirect
; pick label), so the stop composes from it directly: "<Actor> no longer
; <label>." — grammatical for every row of the one table by construction.
String Function _StopWording(String sVibe)
    If sVibe != ""
        Return " no longer " + sVibe + "."
    EndIf
    Return " no longer holds the pose."
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
    ; REV-169 leg 5: a DEFERRED stop (R-2(a) 10s hold) must not register the
    ; "relaxes out of" event either -- the actor is still posing. The stop-event
    ; wording now fires only on a real stop.
    Bool bStopped = _StopActorPose(akInitiator, "llm-stop")
    ; [REV-174f Leg 3] conversation-LLM stop event = route-2 (emergent) class:
    ; emits gsanim_pose_emergent (gate GSAnim.PoseNarrEmergent, DEFAULT ON --
    ; the previously ungated cue is now behind the route-2 toggle).
    If bWas && bStopped
        ; [REV-174g Leg 4.1] FACT-CUE FLOOR (see _PoseVibe): the general pose
        ; cue fires UNCONDITIONALLY with the same composed desc; the gated
        ; pair cue below is unchanged.
        SkyrimNetApi.RegisterEvent("gsanim_pose_general", \
            akInitiator.GetDisplayName() + _StopWording(sVibe), akInitiator, None)
        If StorageUtil.GetIntValue(None, "GSAnim.PoseNarrEmergent", 1) == 1
            SkyrimNetApi.RegisterEvent("gsanim_pose_emergent", \
                akInitiator.GetDisplayName() + _StopWording(sVibe), akInitiator, None)
        Else
            Debug.Trace("[SNAnimGS] gsanim_pose_emergent cue GATED-OFF (route 2 llm-stop, " + akInitiator.GetDisplayName() + ") -- REV-174f Leg 3")
        EndIf
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
    ; REV-169 leg 5: same R-2(a) defer gating as StopPosing_Execute.
    Bool bStopped = _StopActorPose(akTarget, "llm-command")
    ; [REV-174f Leg 3] conversation-LLM directed stop = route-2 (emergent) class
    ;   (see StopPosing_Execute): gsanim_pose_emergent, PoseNarrEmergent gate.
    If bWas && bStopped
        ; [REV-174g Leg 4.1] FACT-CUE FLOOR (see _PoseVibe): the general pose
        ; cue fires UNCONDITIONALLY with the same composed desc; the gated
        ; pair cue below is unchanged.
        SkyrimNetApi.RegisterEvent("gsanim_pose_general", \
            akInitiator.GetDisplayName() + " tells " + akTarget.GetDisplayName() \
            + " that's enough; " + akTarget.GetDisplayName() + _StopWording(sVibe), akTarget, None)
        If StorageUtil.GetIntValue(None, "GSAnim.PoseNarrEmergent", 1) == 1
            SkyrimNetApi.RegisterEvent("gsanim_pose_emergent", \
                akInitiator.GetDisplayName() + " tells " + akTarget.GetDisplayName() \
                + " that's enough; " + akTarget.GetDisplayName() + _StopWording(sVibe), akTarget, None)
        Else
            Debug.Trace("[SNAnimGS] gsanim_pose_emergent cue GATED-OFF (route 2 llm-command, " + akTarget.GetDisplayName() + ") -- REV-174f Leg 3")
        EndIf
    EndIf
EndFunction
