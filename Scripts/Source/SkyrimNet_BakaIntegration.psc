Scriptname SkyrimNet_BakaIntegration extends Quest

; ============================================================
; Settings — wired via MCM or CK defaults
; ============================================================
Bool  Property bEnabled              = True  Auto
Bool  Property bPlayerCanBeTarget    = True  Auto
; iTargetSex restricts which target sex ALL actions allow: 0 = both/any, 1 = female only, 2 = male only.
; Anatomically-specific actions (breasts, privates) are always female-only regardless of this.
Int   Property iTargetSex            = 0 Auto
Float Property fHugLoopDuration      = 8.0   Auto
Float Property fMolestLoopDuration   = 8.0   Auto
Float Property fKissLoopDuration     = 6.0   Auto
Float Property fTouchLoopDuration    = 6.0   Auto
Float Property fSequenceStageTimer   = 4.0   Auto
Float Property fSoloPoseDuration     = 30.0  Auto  ; how long an LLM-driven solo pose (SNBaka_Pose) holds
Int   Property iDrinkBlackoutChance  = 30    Auto  ; % chance PoseDrink ends in a passed-out-drunk blackout
Float Property fPlayerCooldown       = 0.5   Auto  ; cooldown after player-initiated actions
Float Property fNPCCooldown          = 8.0   Auto  ; per-NPC cooldown after NPC-initiated actions (was 20)
; After any NPC-initiated action completes, all further NPC actions are blocked for this
; long. Prevents the AI from chaining multiple NPCs in rapid succession.
Float Property fNPCGlobalCooldown    = 20.0  Auto  ; global anti-spam (was 60 — blocked interactions too much)
; Maximum distance (Skyrim units) between initiator and target for an animation to start.
; ~150 = conversation range, ~300 = same small room, ~600 = large hall.
; This value applies when the PLAYER is involved (crosshair-range targeting).
Float Property fMaxInteractionDistance = 500.0 Auto
; NPC-vs-NPC reach. Much larger than the player gate: two NPCs can drift apart between the LLM
; deciding to act and the action actually firing, so a tight gate makes ~half of them fail.
Float Property fNPCInteractionDistance = 1000.0 Auto
; When False, only the player can trigger Escalate. True (default) allows NPCs to chain
; a defeat into escalation. The 60s global cooldown (fNPCGlobalCooldown) is the primary
; spam guard — set this False only if you want to disable NPC escalation entirely.
Bool  Property bNPCCanEscalate       = True  Auto

; ╔══════════════════════════════════════════════════════════════════════════╗
; ║  POSITIONING TUNING — every paired-animation spacing offset is HERE.       ║
; ║  Edit these to change how far apart the two actors stand in each scene.    ║
; ║  (Also editable on the quest's script in the Creation Kit — no recompile.) ║
; ╠══════════════════════════════════════════════════════════════════════════╣
; ║  HOW TO READ A VALUE                                                       ║
; ║    • Units  : Skyrim units (~1.4 cm each), measured along the victim's     ║
; ║               facing direction.                                            ║
; ║    • Sign   : +value = partner placed IN FRONT,  -value = placed BEHIND.   ║
; ║    • Size   : bigger magnitude = farther apart;  0 = co-located (let the   ║
; ║               animation position them — best for Babo paired anims).       ║
; ╠══════════════════════════════════════════════════════════════════════════╣
; ║  NAME SUFFIX = which actor is the player (separate so one never affects    ║
; ║  another):                                                                 ║
; ║    _NPC   = NPC on NPC            _PC    = player involved (either role)    ║
; ║    _PCAtk = player is attacker    _PCVic = player is the victim            ║
; ╠══════════════════════════════════════════════════════════════════════════╣
; ║  WHICH ACTION EACH GROUP DRIVES                                            ║
; ║    fStruggleSep_*  Struggle grapple   (victim stands ahead of attacker)    ║
; ║    fBackHugSep_*   Back-hug molest    (attacker stands behind victim)      ║
; ║    fEscalDist_*    Choke escalation   (attacker over the downed victim)    ║
; ║    fFondleSep_*    Fondle privates    (attacker behind, victim facing away)║
; ║    fChokeHugSep_*  Back choke / hug   (attacker directly behind victim)    ║
; ╚══════════════════════════════════════════════════════════════════════════╝
; NOTE (2026-06-10 model change): every paired anim now uses _SetupPair — the attacker is the
; origin (0,0,0), the NPC attacker teleports onto the victim, and the VICTIM is placed at
; xLocal=RIGHT(+)/LEFT(-), yLocal=FRONT(+)/BACK(-). Most anims are CO-LOCATED (0,0) and the Babo
; clip self-separates; tune any of them straight off the "[Baka] ... victim vs attacker(0,0,0)" log.
; Struggle (PlayPairedSequence) — victim sits FRONT-LEFT of the attacker.
Float Property fStruggleSep_NPC   = 20.0  Auto  ; NPC vs NPC      — how far in FRONT of the attacker
Float Property fStruggleSep_PCAtk = 20.0  Auto  ; player attacker — how far in FRONT
Float Property fStruggleSep_PCVic = 20.0  Auto  ; player victim   — how far in FRONT
Float Property fStruggleLeft      = -15.0 Auto  ; all cases — how far to the attacker's LEFT (negative = left)
; Back-hug molest (PlayPairedLoopAnim) — how far BEHIND (negative) the attacker stands.
Float Property fBackHugSep_NPC    = -50.0 Auto  ; NPC vs NPC (targets ~50 dist)
Float Property fBackHugSep_PC     = -50.0 Auto  ; player involved (now -50)
; Choke escalation (_DoEscalation MoveTo) — attacker's gap in front of the victim.
Float Property fEscalDist_NPC     = 0.0   Auto  ; NPC victim — co-located; the Babo defeat anim
                                                ; spaces the pair itself (5 double-spaced -> too far)
Float Property fEscalDist_PCVic   = 4.0   Auto  ; player victim (A1 placed 4 units in front)
; Fondle privates (PlayPairedSimpleAnim) — attacker directly BEHIND the victim, same facing
; (victim's back to the attacker). More-negative = further behind.
Float Property fFondleSep_NPC     = -40.0 Auto  ; NPC vs NPC (was -20 — read weird/too close)
Float Property fFondleSep_PC      = -20.0 Auto  ; player involved (unchanged)
; Choke-hug / back choke (PlayPairedSequence) — attacker stands BEHIND the victim, one directly
; behind the other (no lateral shift). More-negative = victim further ahead (avoids clipping).
Float Property fChokeHugSep_NPC   = -8.0  Auto  ; NPC vs NPC (0 -> -8: victim was clipping in)
Float Property fChokeHugSep_PCVic = -15.0 Auto  ; player victim — push the attacker further back
; Forced kiss (PlayPairedLoopAnim, face-to-face) — 0 = the anim's own spacing; negative pulls the
; pair closer (the SLAP kiss anim leaves a person-width gap).
Float Property fForcedKissSep_NPC = 0.0   Auto  ; NPC vs NPC      (X axis = front-to-back gap)
Float Property fForcedKissSep_PC  = 10.0  Auto  ; player involved (X axis ~15cm gap, face-to-face; flip sign if back-to-back)
; Base Flirt (Babo_Flirt paired) — the anim leaves the partner too far back; pull them forward
; along the X axis (front-to-back for this anim family) so the victim lines up with the arm.
Float Property fFlirtSep_NPC       = -20.0 Auto  ; NPC vs NPC      (flip sign if it goes the wrong way)
Float Property fFlirtSep_PC        = 0.0   Auto  ; player involved (0 = the spacing that already worked; tune if needed)
; DEBUG: position tuning — on-screen offsets + final coords per scene. OFF by default now that
; spacing is mostly dialed in; flip True (or tick in the CK) when you need to retune positions.
Bool  Property bDebugPositions    = True  Auto
; DEBUG: action/power logging — a concise on-screen line + a detailed log line for each action
; (interaction name, aggressor, target) and each interact-power press (target, or "no target on
; crosshair"). Left ON so you can see what's firing; untick to silence.
Bool  Property bDebugLog          = True  Auto

; === Resist minigame (powered by Flash Games - Struggling QTE) ===
Bool  Property bResistEnabled    = True Auto
; Escape difficulty 0–100. Higher = easier for victim to escape. Default 70.
; Keys are configured in AEL's own Settings.json (WASD / gamepad d-pad by default).
; NOTE: this is the PLAYER's QTE difficulty only. NPC-vs-NPC fights auto-resolve with
; fNPCEscapeChance below (kept separate so tuning one never changes the other).
Float Property fResistDifficulty    = 70.0 Auto
; NPC-vs-NPC struggle: the victim's % chance to break free (no QTE — it's auto-rolled).
; Lower = the attacker wins more often (which leads into the overpower/escalation content).
Float Property fNPCEscapeChance     = 35.0 Auto
; The MERCY window: a few extra seconds of untouchability (ghost held) whenever a victim exits the
; protected interaction pipeline -- a won struggle (player QTE, NPC escape roll, the bridge's get-up
; key) or the end of a sex scene -- so nobody gets spawn-killed the exact frame the protection drops.
; Confirmed from testing: the ghost used to drop the instant cleanup ran, and a third falmer attacked
; the player literally that moment. 0 disables.
Float Property fEscapeGraceDuration = 2.0 Auto
; NPC-vs-NPC forced anims: how long each stage is held before advancing. The fight plays its
; shared middle stages at this rate, then the deciding stage (attacker-victor or break-free).
Float Property fNPCStageTime        = 5.0 Auto
; Seconds of animation to play before the QTE overlay appears. Lets the start
; animation finish and the actors settle before the minigame is shown.
Float Property fQTEStartDelay       = 4.0  Auto
; Escalation window and QTE difficulty after QTE defeat
Float Property fEscalationWindow     = 20.0 Auto  ; how long the downed victim waits for escalate before recovering
Float Property fDownedSilenceSec     = 25.0 Auto  ; REV-17 Task 2: silence-watch length for an ABANDONED delegated hold (20-30s band)
Float Property fEscalationDifficulty = 70.0 Auto
; SexLab is now reached ONLY through the SkyrimNet_BakaSL bridge (global funcs), so this script holds
; no SexLab script types and the mod loads/runs without SexLab installed.
; Which sex framework to drive escalation scenes: 0 = auto (SexLab if installed, else OStim),
; 1 = SexLab, 2 = OStim.  Set in MCM.  SexLab is resolved at runtime so SexLab.esm need not be a master.
Int Property iSexBackend = 0 Auto
; ── Creature escalation (OPT-IN bestiality content — every toggle defaults OFF/restrictive) ──
Bool Property bCreatureEscalation  = False Auto  ; master switch: creatures may escalate on humans
Bool Property bCreatureOnPlayer    = False Auto  ; allow creatures to escalate on the PLAYER
; Struggle vs escalate split (explicit spec): the STRUGGLE (pin/QTE — "a wolf mauling a person")
; can be enabled on its own; the sex SCENE that follows a creature win is the separate, kinkier
; step. OFF = a creature win just leaves the victim downed, no scene ever starts.
Bool Property bCreatureSceneAllowed = True Auto
; Ask SkyrimNet's LLM a one-word YES/NO before a downed-victim creature escalation commits (the
; proximity pipeline only — on-hit mid-combat grapples stay instant, an LLM round-trip is too slow
; for a live melee exchange). Fail-open on any LLM error. See snbaka_escalation_gate.prompt.
Bool Property bLLMGateEscalation   = False Auto
; [REV-178e rider 4 / S250] LLM tattoo-selection ask: ON (default, A/B
; dogfood) = the auto-apply tattoo lanes (downed ApplyTattoo, NPC-initiated
; CommandTattoo, MarkPlayer) fire a snbaka_tattoo_select ask so the director
; picks a real design from the target's installed non-event body-compat
; packs; OFF = rider-2 behavior exactly (local pick/validate, no ask). The
; player-initiated CommandTattoo picker lane (rider 3) is never LLM'd.
; Applies are always color 0x000000 (user ruling 3).
Bool Property bTattooSelectAsk    = True Auto
; Corner-message master switch: all player-facing Debug.Notification messages route through _Notify,
; so turning this off gives a clean HUD. Papyrus log traces are unaffected.
Bool Property bShowNotifications   = True Auto
Bool Property bCreatureCombatAllowed = True Auto ; True = also mid-combat; False = only once the victim is downed
; A creature's own melee hit on a follower can attempt escalation directly, without waiting for the
; follower to go down first (see HitEventSink.cpp / OnCreatureHitFollower below). AND-gated with
; bCreatureCombatAllowed above (both must be on) plus the existing master switch/sex filter that
; _DoCreatureEscalation already enforces -- turn any one of them off and this simply never fires.
Bool Property bCreatureEscalateFollowersOnHit = False Auto
; A hit landing doesn't mean the creature actually TRIES -- confirmed feedback from testing: with no
; gate here, almost every melee hit guaranteed a struggle attempt, which gets old fast. Rolled once per
; hit (after the 3s per-victim throttle already in OnCreatureHitFollower), independent of the outcome
; roll below (iCreatureSuccessPct decides who WINS an attempt that's already happening; this decides
; whether the creature even bothers this time).
Int  Property iCreatureHitEngageChance = 25 Auto
; ===== Humanoid mid-combat escalation (on-hit) =====
; Same idea as the creature pair above, for HUMANOID aggressors: an enemy human who just landed a melee
; hit on a follower/the player can attempt a Struggle right there mid-combat. Routed through the same
; native hit event and the same per-victim throttle as the creature path; dispatches to the ordinary
; Struggle action (QTE for the player, timed roll for NPCs), so every existing Struggle gate (master
; switch, sex filter, player-target permission, locks) still applies on top of these two.
Bool Property bHumanEscalateOnHit = False Auto  ; opt-in, default OFF like the creature version
Int  Property iHumanHitEngageChance = 25 Auto   ; chance per (throttled) hit that the humanoid bothers
Int  Property iCreatureVictimSex   = 0     Auto  ; allowed victim sex (same scheme as iTargetSex): 0=both, 1=female, 2=male
Bool Property bSellToSlavery       = True  Auto  ; allow the Sell-to-Slavery action (no-ops unless Simple Slavery Plus Plus is installed)
; NPCs may enslave a DOWNED FOLLOWER via Follower Slavery Mod — deliberately separate from
; bSellToSlavery (that one auctions the PLAYER via SS++); the two actions have disjoint targets so
; the LLM can't confuse them. Default OFF: it permanently removes a follower from the party.
Bool  Property bFollowerSlavery       = False  Auto
Float Property fSlaveryPlayerDistance = 1500.0 Auto  ; player must be at least this far (or downed too) for EnslaveFollower to fire
; ===== Plugin: Immersive Lap Sitting (less dialogue) =====
; Soft integration (autodetected, MCM > Lap Sitting page): lets the LLM have a speaker settle onto the lap of
; a currently-SEATED actor (player or NPC) by driving that mod's own quest/spell machinery.
Bool Property bLapSitEnabled = True Auto
; TIED prisoners: a tied victim stays down in the captured pose for this many GAME hours — the
; auto-get-up timer is suspended for the duration, so interrogations get all the time they need.
; They cannot get up unless helped (HelpUp unties + lifts) or the binding lapses on its own.
Float Property fTiedHours             = 12.0   Auto
Int  Property iCreatureBackend     = 0     Auto  ; creature sex backend: 0=auto, 1=SexLab, 2=OStim
Int  Property iCreatureSuccessPct  = 50    Auto  ; NPC-victim escape chance, both while not yet downed AND already downed
; How long a not-yet-downed NPC struggle holds the shared pose before rolling the outcome -- confirmed
; feedback from testing: the old 2-stage x1.5s (3s total) read as far too quick to be a real struggle.
; Not used for the player (real interactive QTE) or an already-downed victim (a quick roll, no drawn-out
; struggle to hold a pose through).
Float Property fCreatureStruggleDuration = 12.0 Auto
; A struggle LOSS (victim defeated, by a creature or a human) starts this grace window on the victim:
; no new passive creature attempt (on-hit roll or the downed-victim scan) will pick them again until it
; expires, UNLESS they end up back in real combat first (a live combat target ends the grace early) --
; confirmed feedback: back-to-back struggles on the same victim the instant one ends "grows old fast."
Float Property fPostDefeatGraceDuration = 100.0 Auto
; Nobody gets pulled into a struggle for this many seconds after a genuinely fresh down (see
; SNAcheron.FreshDownRT) -- lets the bleedout/collapse animation actually settle first. Confirmed real
; bug from testing: engaging too early can break the down animation and leave the victim stuck
; perpetually "downing" instead of settling into a normal held/bleedout state.
Float Property fFreshDownGraceDuration = 3.0 Auto
; Once a victim is confirmed down and the scene is actually about to start, look for up to this many
; OTHER creatures of the SAME type nearby to join in (a 2v1/3v1 group scene) -- computed only at that
; point, never earlier, so a struggle that fails or a combat-not-clear outcome never wastes the scan.
; 1 = current single-creature behavior; 3 is the practical ceiling most animation packs support.
Int Property iCreatureGroupMaxSize = 3 Auto
; ===== Spank system =====
Bool  Property bPlayerCanBeSpanked     = True Auto
Bool  Property bSpankFurnitureTriggers = True Auto
Bool  Property bSpankMaleTargets       = False Auto
Float Property fSpankCooldown          = 0.5  Auto
Float Property fSpankCooldownSex       = 0.3  Auto
Int   Property SpankTatIntensity       = 2    Auto
Int   Property SpankHealFactor         = 2    Auto
Float Property SpankTatFadeRate        = 2.0  Auto Hidden
Float Property _lastSpankFadeTime      = 0.0  Auto Hidden
Sound Property SpankImpactSound        Auto
Sound Property SpankBreastSlapSound    Auto
Sound Property SpankFaceSlapSound      Auto
Sound Property SpankMoanSound          Auto
Spell Property SpankPartnerPower       Auto
Spell Property ButtReactionSpell       Auto
Spell Property BreastReactionSpell     Auto
Spell Property TearSpell               Auto
Bool  Property bAnimatedTearsEnabled   = True  Auto
Bool  Property bExpressionsEnabled      = True  Auto  ; master toggle for facial expressions
Float Property fExpressionIntensity     = 0.50  Auto  ; 0.0-1.0 scale on all expression morphs (lower = subtler)
Bool  Property bMatchHeight             = True  Auto  ; height-match paired-anim actors (DOM ScaleActorToOther) so tall/short pairs align
; ===== REV-63: detection + inflation triggers (cum detection / FHU inflation) =====
; Soft-optional guards: OCum / SL proxy / FHU each carry a toggle; all presence-gated
; (listeners idle with the source mod absent -- no error spam; see the DETECTION
; TRIGGERS section near the tail for the full design notes).
Bool  Property bCumDetectionEnabled = True Auto  ; master: OCum + SL-proxy cum cues (sdb_cum_applied)
Bool  Property bSLProxyEnabled      = True Auto  ; SexLab orgasm-hook proxy share of the cum cue
; REV-133c Task 2.2 (register 24, ruled text): "When enabled, sex scenes will
; generate cum decals on additional body parts." Throat finishes also apply
; face+chest; vaginal/anal finishes also apply thighs. Driven in
; SNBaka_CumDetectionModule._WriteCumState (per-scene-source appliance).
Bool  Property bMoreCumEnabled     = False Auto  ; More Cum: additional cum decals on additional body parts (REV-134c: default flipped to OFF by user ruling; was True at REV-133c)
; REV-134f (user-ruled dogfood 2026-10-21): Follow-up Prompt -- the OPTIONAL
; direct narration for the ambient cum cue. OFF by default (the REV-134d
; cue-only anatomy verdict stays the default); ON restores the register
; entry-22 narration as a gated second surface via the sdb_cum_ambient_narr
; event type (SNBaka_CumDetectionModule.HandleCumAmbientDue emits it only
; when this is ON; the yaml sdb_cum_ambient_narr.yaml matches that event type
; ONLY, so cue and narration are fully separable surfaces).
Bool  Property bCumFollowUpNarration = False Auto
; REV-134d (R2, user-ruled 2026-10-21): Decal Source Selection -- which cum decal
; source this module applies and tracks. 0=OCum (default, user-ruled), 1=SexLab,
; 2=P+, 3=SLACS-2+SCO. Retires the bSLProxyEnabled MCM toggle (that property stays,
; dormant, for save compatibility -- its detection gate keeps its last value; the
; UI surface is gone). KEY MIGRATION (flagged, default-fresh): a fresh selection
; starts at 0/OCum on every save; the old toggle's state is NOT migrated.
Int   Property iDecalSource        = 0    Auto
Bool  Property bFHUInflationEnabled = True Auto  ; FHU inflation level awareness (sdb_fhu_inflate/deflate)
; REV-153 (Follow-up Prompt pattern, REV-134f precedent applied to FHU;
; user-ruled 2026-10-24): optional direct narration for the inflation cue as a
; gated second surface via the sdb_fhu_inflate_narr event type
; (SNBaka_FHUInflationModule._FireChange emits it immediately after the
; sdb_fhu_inflate cue only when this is ON; the yaml sdb_fhu_inflate_narr.yaml
; matches that event type ONLY, so cue and narration are fully separable).
; Default OFF = cue-only, per the 134f anatomy verdict.
Bool  Property bFHUInflateNarration = False Auto
; REV-154 (FHU ambient bystander reaction cue -- the planner's 30%/60% expose
; bands, the cum-ambient pattern applied to FHU; the user's 2026-10-24 shape):
; bFHUAmbientNarration = the gated direct-narration second surface for the
; AMBIENT cue (Fill Her Up MCM "Ambient Narration"; the yaml
; sdb_fhu_ambient_narr.yaml matches the sdb_fhu_ambient_narr event type ONLY,
; so ambient cue and narration are fully separable -- the 153/134f pattern).
; REV-164 (Issue #4, user ruling): DEFAULT FLIPPED OFF -> ON (the 163 dogfood
; ran ambient-narration dark because nobody had found the toggle; defaults now
; match the intended out-of-box experience). A user who turned it off in the
; MCM keeps their off (the key is read live per fire).
; iFHUAmbientNoticeBand / iFHUAmbientHeavyBand = the band floor percents of
; FHU maxInflation (planner defaults 30/60; the MCM sliders are the user valve
; per the C5 ruling). The ambient cue itself (sdb_fhu_ambient) rides the
; 10s level poll with a per-actor 60s cadence, anchored at first band
; crossing, no catch-up, 7200s-RT lifetime guard (module detail in
; SNBaka_FHUInflationModule._CheckAmbientExpose). REV-164: the FIRST ambient
; now fires AT BAND ENTRY (first-fire acceleration, module-side).
Bool  Property bFHUAmbientNarration = True Auto
Int   Property iFHUAmbientNoticeBand = 30 Auto
Int   Property iFHUAmbientHeavyBand  = 60 Auto
; [REV-174 D3 LEG 4 RETIREMENT 2026-10-30] bMephalaModeNarration /
; bMolagBalModeNarration REMOVED with _DaemonModeNarration -- the reaction
; lanes (per-lane toggles + bReactArbitration master) are the live surface.
; ============================================================================
; [REV-174 D3 LEG 3 / A15] REACTION LANES + REACT ARBITRATION MCM surface.
; ALL FOUR lanes ON by default (user ruling of record 2026-10-30, A15 --
; supersedes every earlier player-lanes-OFF posture). Per-lane toggles per
; mode (narr / thought / pspeech / pthought, design doc 4.2/4.6); the master
; bReactArbitration toggle is the "LLM decides reactions" switch (6.2: OFF =
; manual mode -- every enabled lane fires; ON = the answer's REACT: field
; arbitrates, fail-open on missing/invalid). Labels/tooltips = register
; DRAFTs (entry-class 4.6; the user's pen at the sitting). The Sanguine /
; Sheogorath lane toggles live GS-side as GSAnim.* StorageUtil keys (the
; established GS MCM pattern); these motherboard properties cover Mephala +
; MolagBal only.
; ============================================================================
Bool  Property bReactArbitration   = True Auto
Bool  Property bMephalaLaneNarr    = True Auto
Bool  Property bMephalaLaneThought = False Auto   ; [REV-174a D2e] default OFF (user fallback ruling; toggle still on the MCM surface)
Bool  Property bMephalaLanePSpeech = True Auto
Bool  Property bMephalaLanePThought = True Auto
Bool  Property bMolagBalLaneNarr    = True Auto
Bool  Property bMolagBalLaneThought = False Auto   ; [REV-174a D2e] default OFF (user fallback ruling; toggle still on the MCM surface)
Bool  Property bMolagBalLanePSpeech = True Auto
Bool  Property bMolagBalLanePThought = True Auto
; Per-source vs unified cum-cue shaping (amendment 2b): 0 = unified (framework-neutral,
; default -- the proposal awaiting §7 ruling), 1 = per-source wording.
Int   Property iCumCueMode          = 0    Auto

; === Sounds (assign in CK to Baka sound descriptors) ===
Sound Property PanicSoundF  Auto
Sound Property SmackSound   Auto

; === Sex framework soft deps (assign factions in CK, leave None if unused) ===
Faction Property SexLabAnimatingFaction Auto
Faction Property OStimExcitementFaction Auto

; A condition-free "do nothing" AI package, force-applied to scene NPCs so their AI
; can't re-evaluate and yank them out of the held animation (SexLab's LockActor trick).
; Assign in CK to a package with NO conditions (e.g. duplicate SexLab's DoNothing and
; delete its faction condition).  If left None, _HoldActorAI is a safe no-op.
Package Property SNBakaDoNothing Auto

; === Player powers (assign in CK) ===
Spell Property EscalatePower Auto
Spell Property InteractPower  Auto

; Escalation (forced sex) is the ONLY combat-gated action: it won't start while any actor within this
; radius of the victim is still in combat. MCM-tunable.
Float Property fCombatOverRadius = 3000.0 Auto

; OPTIONAL robust combat-stop. Assign in CK to a Calm-archetype spell (high magnitude, long
; duration) in the Baka ESP. When set, pacify casts it on the captor's side so combat truly ends
; instead of relying on aggression-0 alone. Left as None -> we fall back to the aggression/rank path.
Spell Property SNBakaCalm Auto

; === Interact menu messages (assign in CK to SNBaka_InteractMenu* records) ===
Message Property InteractMenuMain         Auto
Message Property InteractMenuAffectionate Auto
Message Property InteractMenuAggressive   Auto
Message Property InteractMenuAggPhysical  Auto
Message Property InteractMenuAggSexual    Auto

; === Sex-spank menus (create in CK, assign here) ===
; SNBaka_SexSpankWho:    5 buttons — "Person 1" | "Person 2" | "Person 3" | "You" | "Cancel"
; SNBaka_SexSpankByWhom: 5 buttons — "Person 1" | "Person 2" | "Person 3" | "Yourself" | "Cancel"
; Button indices are fixed; the notification shown just before the menu maps numbers to names.
Message Property SexSpankWhoMenu    Auto
Message Property SexSpankByWhomMenu Auto

; === Internal ===
Actor Property PlayerRef    Auto Hidden
Form  Property XMarkerBase  Auto Hidden

; === AEL QTE state (never saved — safe to reset on load) ===
Bool _bAELStruggleComplete  = False
Bool _bAELVictimEscaped     = False
Bool _bCooldownActive       = False
; Set by Play* helpers when a QTE completes with the attacker winning (victim dominated).
; Cleared by LockBoth at the start of every new animation.
Bool _bQTEDefeated          = False
; In-combat "grapple takedown" (interact power, aggressive-menu path): True for the duration of a
; paired animation the PLAYER started against a target they're still actively fighting. Consumed by
; _SetupPair (skip ghosting the player) and _ShouldAbort (abort if the player takes a fresh hit).
; Set right after LockBoth succeeds in the relevant *_Execute function; always reset in _CleanupPair,
; the single guaranteed choke point every paired interaction ends at.
Bool  _bMidCombatGrappleActive = False
Float _fMidCombatHitBaselineRT = 0.0
; Timestamp of the last time the PLAYER took a physical hit, stamped unconditionally (before any MCM
; gate) at the top of OnCreatureHitFollower -- the existing native hit pipeline already fires that
; event synchronously on every such hit, so this needed no new native plumbing. Compared against
; _fMidCombatHitBaselineRT by _ShouldAbort to detect "a NEW hit landed since this grapple started".
Float _fLastPlayerHitRT        = 0.0
; Optional Babo down-pose anim event for the NEXT NPC defeat (e.g. "BaboFaintF" after a choke).
; Read + cleared by _Bleedout. Empty => default Babo_DefeatTraumaLie.
String _sDownPose           = ""
; Set by Escalate_Execute during the ground window to signal _DefeatGroundWindow.
Bool _bEscalateRequested    = False
; Set by Release_Execute during the ground window to free the victim early without escalating.
Bool _bReleaseRequested     = False
; --- Escalate lock-race retry window (docs/LOCKRACE_FIX_DESIGN.md, variant (c), user-approved) ---
; The 03:38:25 specimen: the forced-choice Escalate call landed while the initiator was still
; SNBaka.Locked from the preceding struggle/QTE; _CleanupPair cleared the lock the SAME SECOND,
; but the call had already read InitLocked=1 and silently dropped -- the model was never told
; its decision failed. Same disease class as the bleedout settle wait in _DispatchDownedAction
; (state-landing lag eating a legitimate call), so same cure: a bounded inline settle window,
; then a FRESH full-gate revalidation. Single-entry by construction (the window IS the entry);
; a second drop while a window is active is superseded (logged with who/why, silent). Absolute
; revalidation: the retry fires only if _EscalateValidate returns "" at fire time -- permanent
; gate failure is the slipped-cue path, never a retry loop.
Bool  _bEscalateRetryActive  = False
; Named constants (retune by edit if the re-test suggests different values -- no MCM surface
; for a race-window patch):
Float fEscalateRetryWindowSec = 10.0    ; cap: the specimen cleared in <1s; two full QTE cycles fit inside 10s
Float fEscalateRetryPollSec   = 0.5     ; poll cadence, same as the bleedout settle wait
; Debounce so the "escalate or back down" decision cue isn't fired twice for one action (e.g. by both
; _RecoveryPeriod and UnlockBoth). Real-time seconds of the last baka_opportunity we fired.
Float _fLastOpportunityRT   = 0.0
; Downed-victim menu requests, polled by _DefeatGroundWindow's wait loop:
;   _iDownedReplay 1 = Investigate, 2 = Inspect — play the inspection anim, then re-down + reset timer.
;   _bStandBack = the player chose "Stand Back" — exit the window into the normal stand-up/recover path.
Int  _iDownedReplay         = 0
Bool _bStandBack            = False
; Set by LLM-driven aggressive actions (inspect/escalate/etc.) when they act on a DOWNED victim, so
; the _DefeatGroundWindow loop resets its countdown — the victim stays protected/down while the
; aggressor keeps interacting, and only recovers once interactions STOP.
Bool _bResetDownWindow      = False
; True when player is A2 (victim) for the current QTE — determines how afNumArg maps to escape.
Bool _bPlayerIsVictim       = False
; --- LLM escalation gate (bLLMGateEscalation) transient state: one ask in flight at a time ---
Bool  _bGatePending  = False
Float _fGateSentRT   = 0.0
Actor _gateCreature  = None
Actor _gateVictim    = None
; --- [REV-178e rider 4 / S250] tattoo-selection ask transient state: one ask
; in flight at a time (the escalation-gate precedent), 30s expiry on a stale
; pending slot, duplicate lanes degrade immediately instead of queueing ---
Bool   _bTattooAskPending     = False
Float  _fTattooAskSentRT      = 0.0
Actor  _akTattooAskInitiator  = None
Actor  _akTattooAskTarget     = None
String _sTattooAskLane        = ""     ; "llm_action" | "dialogue" | "ownership"
String _sTattooAskHintSection = ""
String _sTattooAskHintName    = ""

; Corner-message wrapper — every player-facing Debug.Notification in this script routes through here
; so the MCM "Show Notifications" toggle can silence the lot for a clean HUD. Traces are unaffected.
Function _Notify(String msg)
    If bShowNotifications
        Debug.Notification(msg)
    EndIf
EndFunction

; Trace wrapper — every Debug.Trace in this script routes through here, gated on the bDebugLog MCM
; toggle. The string concatenation at each call site still runs (Papyrus evaluates arguments first),
; but the synchronized log-file WRITE — the expensive part on a starved VM — is skipped when off.
; Keep it ON while actively debugging/stabilizing; turn OFF for clean high-performance play.
Function _Log(String msg)
    If bDebugLog
        Debug.Trace(msg)
    EndIf
EndFunction
; Set by DrugFood_Execute before calling _DefeatGroundWindow so _DoEscalation
; can trigger an unconscious-victim SexLab scene instead of a generic rape scene.
; Cleared by _DoEscalation after the scene is started.
Bool _bDruggedEscalation    = False
; Game time of the last completed NPC-initiated action.  Compared against
; fNPCGlobalCooldown in IsEligible to throttle AI-driven action frequency.
Float _fLastNPCActionTime   = 0.0
; Per-action extra Z nudge for the PLAYER's pin-marker (on top of the global -2 vehicle-lift fix).
; Set by an Execute fn before PlayPairedSequence when a specific anim seats the player too high/low,
; then reset to 0. Negative = lower the player.
Float _fPlayerZAdjust       = 0.0
; Tracked for periodic tear re-application inside _WaitOrAbort.
Actor _TearVictim           = None

; PrismaUI async menu state — set before showing the HTML panel,
; read back in OnSNBakaMenuChoice when the player picks an option.
Actor _pendingTarget   = None
Actor _pendingCaster   = None
Actor _pendingSexCaster = None
Actor _pendingSexNPC0  = None
Actor _pendingSexNPC1  = None
Actor _pendingSexNPC2  = None

; ============================================================
; Init
; ============================================================
Bool _bFreshBoot = False  ; REV-144 4.2: True only when OnInit (a new game, or this module's
                          ; first boot inside an ongoing save) started this instance -- NOT set
                          ; when a save restores the script and Setup() runs via the MCM reload
                          ; chain. Drives the player-target policy migration seed.

Event OnInit()
    _bFreshBoot = True    ; REV-144 4.2: fresh-boot marker (see _SeedPlayerTargetPolicy)
    PlayerRef   = Game.GetPlayer()
    XMarkerBase = Game.GetFormFromFile(0x0E, "Skyrim.esm")
    Setup()
EndEvent

Event OnPlayerLoadGame()
    PlayerRef      = Game.GetPlayer()
    XMarkerBase    = Game.GetFormFromFile(0x0E, "Skyrim.esm")
    _bAELStruggleComplete = False
    _bAELVictimEscaped    = False
    _bCooldownActive      = False
    _bQTEDefeated         = False
    _bEscalateRequested   = False
    _bReleaseRequested    = False
    _bPlayerIsVictim      = False
    _bDruggedEscalation   = False
    _fLastNPCActionTime   = 0.0
    ; REV-123: the D5 clamp call that lived HERE (OnPlayerLoadGame) is DEAD CODE on
    ; this quest -- this script extends Quest and the quest's OnPlayerLoadGame never
    ; fires (this repo's own receipts: L8992/L9229 comments; the 10-17 session proves
    ; it -- no clamp sentinel at the 01:59:31 load while the stale cosave stamp
    ; suppressed the 02:05:45 P+ cue). The clamp now runs from Setup() -- the proven
    ; load path (OnInit + the MCM OnGameReload chain, "MCM canary reload" sentinel).
    ; Any in-progress animation is gone after a load — always safe to clear player locks.
    If PlayerRef
        StorageUtil.SetIntValue(PlayerRef, "SNBaka.Locked",        0)
        StorageUtil.SetIntValue(PlayerRef, "SNBaka.StopRequested", 0)
        StorageUtil.SetIntValue(PlayerRef, "SNBaka.OnGround",      0)
        Game.EnablePlayerControls()
    EndIf
    Setup()
EndEvent

Function Setup()
    ; REV-123: the D5 stale-cosave-stamp clamp moved HERE from the quest's
    ; OnPlayerLoadGame (dead site -- a Quest script never receives that event;
    ; see the REV-123 receipts: no clamp sentinel at the 10-17 01:59:31 load
    ; while the stale LastCumCueRT stamp suppressed the 02:05:45 P+ cue).
    ; Setup() is the PROVEN load path (OnInit + SkyrimNet_BakaIntegration_MCM's
    ; OnGameReload on every single load -- see L418's own receipt comment), and
    ; the clamp must run BEFORE anything arms so no arming path can consume a
    ; stale stamp. Boot (new game) is a no-op pass: stamps are fresh.
    SNBaka_CumDetectionModule.ClampStaleRTStamps(Self)
    ; REV-144 4.2: player-target policy migration seed (the bPlayerCanBeSpanked fold-in).
    ; One-shot; see _SeedPlayerTargetPolicy for the continuity-vs-default decision.
    _SeedPlayerTargetPolicy()
    _SeedTargetSexLevel()
    _DaemonArm()   ; REV-145: re-arm the ambient daemon tick from save-persisted mode flags (idempotent when both off)
    ; Confirmed real bug from testing: THIS is the actual primary re-registration path (called from
    ; SkyrimNet_BakaIntegration_MCM's OnGameReload on every single load -- see that script's own comment;
    ; the OnUpdateGameTime heartbeat in this quest is only a secondary backup), yet it never refreshed
    ; PlayerRef before calling _RegisterModEvents(), which only sets SNBaka.Present behind an "If
    ; PlayerRef" guard. If PlayerRef was stale/None at this exact point, the flag silently never got set
    ; -- Acheron's own creature-handoff check reads that flag and skips every roll forever, even though
    ; Baka was actually alive and listening (its own SNBaka_TryCreatureOnDowned handler fired fine).
    If !PlayerRef
        PlayerRef = Game.GetPlayer()
    EndIf
    ; REV-24 1a: clear stale PendingScene latches BEFORE anything re-registers — every
    ; surviving latch at this point is prior-session residue (the owning VM thread is gone).
    _SweepStaleSceneLatches()
    UnregisterForAllModEvents()
    _RegisterDecorators()
    ; Acheron-downed handoff (creature pounce) + AEL/menu events. Re-asserted from OnUpdateGameTime too,
    ; as a backup in case this path is ever skipped.
    _RegisterModEvents()
    ; REV-68 (Phase B, §67 module contract): module lifecycle arm pass — runs right
    ; after the forwarding-event surface so every module is armed/handshaken on the
    ; same paths that re-assert the listeners (Setup + heartbeat, both idempotent).
    _ArmModules()
    ; REV-63: FHU inflation level poll (soft-optional: armed only when FHU is
    ; actually installed and the toggle is on; multiplexed onto the shared
    ; real-time update slot -- see _ArmRealtimeTimer).
    If bFHUInflationEnabled && SNBaka_FHUInflationModule.Installed()   ; REV-96 Task 2: probe moved to the module (call shape only)
        _FHUStartPoll()
    Else
        _FHUStopPoll()
    EndIf
    _STAmbientStart()   ; REV-159 (dogfood 2.2): decoupled ST ambient exposure cadence (mode-agnostic)
    ; Re-read SNBaka_Offsets.ini so edits to the offsets file apply on game load (no restart needed).
    SNBakaUI.ReloadOffsets()
    ; Persist the "Sell to Slavery disabled" choice across loads: the YAML re-registers the action every
    ; game load, so if the player has it switched off we pull it back out of the action menu here. (The
    ; exec also no-ops when off, so it's functionally disabled regardless of registration timing.)
    If !bSellToSlavery
        SkyrimNetApi.UnregisterAction("SellToSlavery")
    EndIf
    If !bFollowerSlavery || !IsFollowerSlaveryInstalled()
        SkyrimNetApi.UnregisterAction("EnslaveFollower")
    EndIf
    _Log("[SNBaka] Setup: SexLab installed=" + SkyrimNet_BakaSL.Installed())
    ; Spank system
    SpankTatFadeRate = SpankHealFactor as Float
    If SpankTatFadeRate < 0.1
        SpankTatFadeRate = 0.1
    EndIf
    If _lastSpankFadeTime <= 0.0
        _lastSpankFadeTime = Utility.GetCurrentGameTime()
    EndIf
    RegisterForSingleUpdateGameTime(SpankTatFadeRate)
    If fSpankCooldownSex <= 0.0 || fSpankCooldownSex > 5.0
        fSpankCooldownSex = 1.0
    EndIf
    ; Force-resolve all properties every Setup() call.
    ; This clears zombie references left by ESL FormID compaction — zombie forms are
    ; non-None in Papyrus so a plain !Property guard would miss them.
    Spell  _sp
    Message _m
    If !EscalatePower
        EscalatePower = Game.GetFormFromFile(0x000D69, "SkyrimNet_BakaIntegration.esp") as Spell
    EndIf
    _sp = Game.GetFormFromFile(0x00080E, "SkyrimNet_BakaIntegration.esp") as Spell
    If _sp
        InteractPower = _sp
    EndIf
    _m = Game.GetFormFromFile(0x00080A, "SkyrimNet_BakaIntegration.esp") as Message
    If _m
        InteractMenuMain = _m
    EndIf
    _m = Game.GetFormFromFile(0x00080B, "SkyrimNet_BakaIntegration.esp") as Message
    If _m
        InteractMenuAffectionate = _m
    EndIf
    _m = Game.GetFormFromFile(0x00080C, "SkyrimNet_BakaIntegration.esp") as Message
    If _m
        InteractMenuAggressive = _m
    EndIf
    _m = Game.GetFormFromFile(0x000803, "SkyrimNet_BakaIntegration.esp") as Message
    If _m
        InteractMenuAggPhysical = _m
    EndIf
    _m = Game.GetFormFromFile(0x000804, "SkyrimNet_BakaIntegration.esp") as Message
    If _m
        InteractMenuAggSexual = _m
    EndIf
    _Log("[SNBaka] Setup: InteractMenuMain=" + InteractMenuMain + " InteractPower=" + InteractPower)

    ; Emotional Tears Effect SE — optional soft dependency, no master needed.
    ; Resolved at runtime; no-ops silently if EmoTears4NPCs.esp is not installed.
    If bAnimatedTearsEnabled
        ; STABLE: keep whatever valid spell is already set (from the CK property or a
        ; previous good load).  ONLY re-resolve when it has been lost (None) — that
        ; recovers the saved-None left by an older build, without ever clobbering a
        ; working value.  This is why tears kept breaking: prior code re-resolved
        ; (and sometimes nulled) the spell every single load.
        ; zzNPCTearsTestApplySelf = local 0x000802 in EmoTears4NPCs.esp (CK 03000802).
        If !TearSpell
            TearSpell = Game.GetFormFromFile(0x000802, "EmoTears4NPCs.esp") as Spell
        EndIf
        _Log("[SNBaka] Setup: TearSpell using=" + TearSpell)
    Else
        TearSpell = None
        _Log("[SNBaka] Setup: TearSpell cleared (disabled)")
    EndIf

    ; EscalatePower is no longer added to the player — Interact_ShowMenu handles escalation
    ; automatically when the target is on the ground (SNBaka.OnGround=1). The spell record
    ; is kept in the ESP so existing saves aren't broken, but it is no longer granted.
    If InteractPower && !PlayerRef.HasSpell(InteractPower)
        PlayerRef.AddSpell(InteractPower)
    EndIf

    ; Sell-to-Slavery availability, resolved at every load (Setup runs per-load via the MCM's
    ; OnGameReload): the YAML re-registers the action on load, so pull it back OUT of the LLM's menu
    ; whenever it can't actually work -- Simple Slavery++ missing, or the user's MCM toggle off (the
    ; toggle's own handler already does this live; this covers the re-registration on the NEXT load).
    ; Execute() carries the same plugin check as a belt-and-suspenders for direct calls.
    If !IsSimpleSlaveryInstalled()
        SkyrimNetApi.UnregisterAction("SellToSlavery")
        _Log("[SNBaka] Setup: SimpleSlavery.esp not installed — SellToSlavery action unregistered")
    ElseIf !bSellToSlavery
        SkyrimNetApi.UnregisterAction("SellToSlavery")
        _Log("[SNBaka] Setup: bSellToSlavery is OFF — SellToSlavery action unregistered")
    EndIf
    ; Same gate for the FOLLOWER slavery action (Follower Slavery Mod) — unregistered when the mod
    ; isn't ready or the toggle is off, so the LLM never even sees it. Keeping the two slavery
    ; actions' availability independent is what stops wrong-target calls breaking roleplay.
    If !IsFollowerSlaveryInstalled()
        SkyrimNetApi.UnregisterAction("EnslaveFollower")
        _Log("[SNBaka] Setup: Follower Slavery Mod not installed/initialized — EnslaveFollower action unregistered")
    ElseIf !bFollowerSlavery
        SkyrimNetApi.UnregisterAction("EnslaveFollower")
        _Log("[SNBaka] Setup: bFollowerSlavery is OFF — EnslaveFollower action unregistered")
    EndIf
    ; Same gate for the Immersive Lap Sitting plugin action (MCM > Lap Sitting).
    If !IsLapSitInstalled()
        SkyrimNetApi.UnregisterAction("SitOnLap")
        _Log("[SNBaka] Setup: Lap Sitting.esp not installed — SitOnLap action unregistered")
    ElseIf !bLapSitEnabled
        SkyrimNetApi.UnregisterAction("SitOnLap")
        _Log("[SNBaka] Setup: bLapSitEnabled is OFF — SitOnLap action unregistered")
    EndIf
EndFunction

; Plugin-presence probe for Immersive Lap Sitting (less dialogue) — same GetFormFromFile pattern as
; the SS++ probe below. 0x80A = its own HSF_LapSitQuest record, read directly from the plugin binary.
; Shared by Setup(), LapSit_Execute and the MCM.
Bool Function IsLapSitInstalled()
    Return Game.GetFormFromFile(0x00080A, "Lap Sitting.esp") != None
EndFunction

; Plugin-presence probe for Simple Slavery Plus Plus -- GetFormFromFile is the only detection primitive
; this compile environment's Game.psc has (no SKSE GetModByName here), and it's the same pattern this
; file already uses for EmoTears4NPCs. 0x00492E = SS++'s own main QUST record, read directly from the
; plugin binary (not guessed). Returns None (with a harmless engine log line) when the esp is absent.
; Shared by Setup(), SellToSlavery_Execute, and the MCM (via the Main property).
Bool Function IsSimpleSlaveryInstalled()
    Return Game.GetFormFromFile(0x00492E, "SimpleSlavery.esp") != None
EndFunction

; Follower Slavery Mod readiness probe — FSM's own documented gate: this global StorageUtil flag is
; set only once the player has opened FSM's MCM and clicked Install (before that its quests aren't
; running and its enslave queue isn't listening). Shared by Setup(), EnslaveFollower_Execute and the MCM.
Bool Function IsFollowerSlaveryInstalled()
    Return StorageUtil.GetIntValue(None, "fsm_bIsMCMInstalled", 0) == 1
EndFunction

; Plugin-presence probe for the Acheron bridge (REV-68 MCM "Downed State" section) —
; reads the bridge's own quest form (SNAcheron_Quest 0x800) exactly like the liveness
; probes in _DelegateDownToAcheron and _RegisterModEvents. Returns None (with a harmless
; engine log line) when the bridge esp is absent. Shared by the Acheron MCM page and
; _ArmModules' nudge path.
Bool Function IsAcheronBridgeInstalled()
    Return _AcheronBridgePresent()
EndFunction

; ============================================================
; Guards
; ============================================================
; ============================================================
; REV-146a — THE CHILD BOUNDARY (user ruling, SAFETY PRIORITY)
; ============================================================
; No Baka-module action of ANY kind may touch an NPC the engine marks
; as a child. Engine-true check of record: Actor.IsChild() — vanilla
; Papyrus native ("Is this actor a child?", installed Actor.psc L355,
; D:\Steam\...\Data\Source\Scripts\Actor.psc). NO heuristics: no name
; lists, no height checks, no race-keyword guesses — the native flag
; alone. Applied at every entry point: IsEligible (which re-gates the
; daemon fire recheck and every paired executor), both daemon pools,
; strip/restore, downed dispatch, spank/slap, escalation, and the
; creature lanes. ASCII throughout.
Bool Function _ChildBoundaryRefused(Actor akA1, Actor akA2, String asSite)
    If (akA1 && akA1.IsChild()) || (akA2 && akA2.IsChild())
        String sWho = "actor"
        If akA1 && akA1.IsChild()
            sWho = akA1.GetDisplayName()
        ElseIf akA2
            sWho = akA2.GetDisplayName()
        EndIf
        _Log("[SNBaka] child-boundary REFUSE [" + asSite + "]: " + sWho + " is engine-marked child - no module action (REV-146a)")
        Return True
    EndIf
    Return False
EndFunction

; abAllowMidCombat: relaxes ONLY the attacker-in-combat gate below -- used by the on-hit humanoid
; escalation path (see Struggle_Execute's abFromHit), where the attacker being in combat is the whole
; premise. Every other gate (enabled, dead, downed initiator, creatures, distance, player-target
; permission, sex filter) still applies unconditionally.
Bool Function IsEligible(Actor akA1, Actor akA2, Bool abAllowMidCombat = False)
    If !bEnabled
        _Log("[SNBaka] IsEligible: blocked — master switch off")
        Return False
    EndIf
    If !akA1 || !akA2
        _Log("[SNBaka] IsEligible: blocked — null actor")
        Return False
    EndIf
    ; REV-146a child boundary: FIRST substantive gate (safety priority) — no
    ; module action of any kind on an engine-marked child, at any site.
    If _ChildBoundaryRefused(akA1, akA2, "IsEligible")
        Return False
    EndIf
    If akA1.IsDead() || akA2.IsDead()
        _Log("[SNBaka] IsEligible: blocked — actor dead (" + akA1.GetDisplayName() + " -> " + akA2.GetDisplayName() + ")")
        Return False
    EndIf
    ; A downed/defeated actor can only be acted ON (akA2), never act themselves (akA1).
    If _IsDownedAny(akA1)
        _Log("[SNBaka] IsEligible: blocked — initiator is downed, can only be acted ON (" + akA1.GetDisplayName() + ")")
        Return False
    EndIf
    ; Creatures (Draugr, Falmer, Giant, wolves, etc.) get ONLY CreatureEscalate — never the human action
    ; set (Struggle, ChokeHug, Escalate, HelpUp, etc.), which plays human Babo animations and narrates them
    ; as a person. CreatureEscalate_Execute has its own separate gate and never calls IsEligible, so this
    ; doesn't affect it. BOTH tests are required: _IsCreatureActor alone let falmers/giants/draugr
    ; through (Bethesda tags those races ActorTypeNPC, the same keyword humans carry — confirmed
    ; report: falmers and giants picking Inspect and other humanoid animations their skeletons can't
    ; play). _CreatureAnimKey matches by actual race and isn't fooled by the keyword.
    If _IsCreatureActor(akA1) || _IsCreatureActor(akA2) || _CreatureAnimKey(akA1) != "" || _CreatureAnimKey(akA2) != ""
        _Log("[SNBaka] IsEligible: blocked — creature-skeleton actor in a humanoid action (" + akA1.GetDisplayName() + " -> " + akA2.GetDisplayName() + ")")
        Return False
    EndIf
    ; An actor mid SEX SCENE (OStim/SexLab — ours OR another mod's; SNBaka.Locked only covers ours)
    ; is never a valid paired-animation participant — yanking them out of a running thread breaks
    ; both systems (explicit spec).
    If IsInSexAnimation(akA1) || IsInSexAnimation(akA2)
        _Log("[SNBaka] IsEligible: blocked — an actor is mid sex scene (" + akA1.GetDisplayName() + " -> " + akA2.GetDisplayName() + ")")
        Return False
    EndIf
    ; Pending-scene latch (rev-22): an escalation is mid-dispatch for this pair — the
    ; wizard is open or the thread is still in setup, so IsInSexAnimation reads False
    ; for both even though they are committed to a scene. This is the guard that
    ; refuses the would-be interleave the 09-17 session raced through.
    If _IsScenePending(akA1) || _IsScenePending(akA2)
        _Log("[SNBaka] IsEligible: blocked — scene latch held, pair already escalating (" + akA1.GetDisplayName() + " -> " + akA2.GetDisplayName() + ")")
        Return False
    EndIf
    ; Player-involved uses the crosshair-range gate; NPC-vs-NPC gets the larger reach.
    ; REV-146a Task 7 (manual out-of-range pairs): a PLAYER-initiated pair may
    ; now come from up to the walk ceiling (fApproachWalkCeiling) away -- the
    ; approach window walks the NPC into snap range before setup, with the
    ; teleport as the bounded fallback. NPC-vs-NPC reach is unchanged.
    Float maxDist = fMaxInteractionDistance
    If akA1 != PlayerRef && akA2 != PlayerRef
        maxDist = fNPCInteractionDistance
    ElseIf akA1 == PlayerRef && fApproachWalkCeiling > maxDist
        maxDist = fApproachWalkCeiling
    EndIf
    If maxDist > 0.0 && akA1.GetDistance(akA2) > maxDist
        _Log("[SNBaka] IsEligible: blocked — distance " + akA1.GetDistance(akA2) + " > " + maxDist)
        Return False
    EndIf
    ; Attacker-in-combat normally blocks an action — EXCEPT against a downed/bleeding-out victim. That
    ; is the defeat case: the fight may still be live around them, but the target is already beaten and
    ; helpless, so choke/pin/grope/escalate/etc. are valid. LockBoth then Calms the attacker out of
    ; combat so the held anim plays, and _ShouldAbort re-breaks it only if the attacker is actually hit.
    If akA1.IsInCombat() && !_IsDownedAny(akA2) && !abAllowMidCombat
        _Log("[SNBaka] IsEligible: blocked — attacker in combat, target not downed (" + akA1.GetDisplayName() + " -> " + akA2.GetDisplayName() + ")")
        Return False
    EndIf
    ; REV-144 4.2: central player-target admission (rev-55a blanket). The retired
    ; bPlayerCanBeTarget property FOLDED IN here -- one policy, StorageUtil class
    ; SNBaka.PlayerTargetPolicy (player-keyed, default OFF), consulted for every
    ; NPC-initiated player-target site. Player-own initiations (akA1 == player)
    ; pass ungated (the Execute pattern). Gates only akA2 == player, never akA1.
    If !_PlayerTargetAdmitted(akA1, akA2, "IsEligible")
        Return False
    EndIf
    ; Content-preference filter (what the LLM/an NPC should be allowed to pick), not a technical
    ; constraint -- only gates a non-player initiator, same as bNPCCanEscalate/_DoEscalation. The
    ; player targeting whoever they want, via any action, is their own deliberate choice.
    If akA1 != PlayerRef && !_TargetSexAllowed(akA2)
        _Log("[SNBaka] IsEligible: blocked — target sex not allowed by content filter (" + akA1.GetDisplayName() + " -> " + akA2.GetDisplayName() + ")")
        Return False
    EndIf
    If IsActorLocked(akA1) || IsActorLocked(akA2)
        _Log("[SNBaka] IsEligible: blocked — actor locked/busy (" + akA1.GetDisplayName() + " locked=" + IsActorLocked(akA1) + ", " + akA2.GetDisplayName() + " locked=" + IsActorLocked(akA2) + ")")
        Return False
    EndIf
    If _bCooldownActive && akA1 == PlayerRef
        _Log("[SNBaka] IsEligible: blocked — player action cooldown active")
        Return False
    EndIf
    If akA1 != PlayerRef
        Float now = Utility.GetCurrentGameTime()
        ; Per-initiator cooldown — same NPC can't act again too soon.
        Float lastTime = StorageUtil.GetFloatValue(akA1, "SNBaka.LastActionTime", 0.0)
        If now - lastTime < (fNPCCooldown / 86400.0)
            _Log("[SNBaka] IsEligible: blocked — initiator per-NPC cooldown (" + akA1.GetDisplayName() + ")")
            Return False
        EndIf
        ; Global NPC cooldown — blocks all NPC actions for fNPCGlobalCooldown seconds
        ; after any NPC-initiated action. Prevents AI from chaining multiple actors.
        If now - _fLastNPCActionTime < (fNPCGlobalCooldown / 86400.0)
            _Log("[SNBaka] IsEligible: blocked — global NPC cooldown")
            Return False
        EndIf
    EndIf
    If IsInSexAnimation(akA1) || IsInSexAnimation(akA2)
        _Log("[SNBaka] IsEligible: blocked — late re-check: mid sex scene (" + akA1.GetDisplayName() + " -> " + akA2.GetDisplayName() + ")")
        Return False
    EndIf
    ; Pending-scene latch (rev-22) — see the main guard above. Belt-and-braces second
    ; site, same as the doubled IsInSexAnimation check.
    If _IsScenePending(akA1) || _IsScenePending(akA2)
        _Log("[SNBaka] IsEligible: blocked — late re-check: scene latch held (" + akA1.GetDisplayName() + " -> " + akA2.GetDisplayName() + ")")
        Return False
    EndIf
    Return True
EndFunction

; ---------------------------------------------------------------------------------------------
; Sex lookup that works on LEVELED actors.
;
; Actor.GetActorBase() returns the EDITOR base object. For the generic leveled NPCs that make up
; most of the world (bandits, forsworn, vampires, most guards) that editor base is a TEMPLATE
; SHELL -- e.g. dunPOILvlBanditMissileAggro1536 (07F89F:Skyrim.esm) -- which carries a Template
; (TPLT) pointing at a leveled character list plus TemplateFlags including Traits. Because sex
; lives in the Traits flag, the shell's own ACBS sex field is an unused placeholder that reads
; MALE, and its Race field is likewise junk (FoxRace on that record). The real sex only exists on
; the game-generated base created when the leveled list resolves at spawn time.
;
; Actor.GetLeveledActorBase() (SKSE) returns exactly that generated base. Per SKSE's own Actor.psc:
;   "Obtains a leveled actor's 'fake' base (the one generated by the game when the actor is
;    leveled. This differs from GetActorBase which will return the editor base object)"
;
; Symptom of getting this wrong: a visibly female bandit reads as male, so every anatomically
; gated action hits a bare Return -- no animation, no log, no notification. Unique named NPCs
; (no template) work fine, which makes the failure look intermittent rather than systematic.
;
; Returns 0 male, 1 female, -1 unknown/none.
Int Function _SexOf(Actor akActor) Global
    If !akActor
        Return -1
    EndIf
    ActorBase bse = akActor.GetLeveledActorBase()
    If !bse
        ; Non-leveled actors (uniques, the player) can return None here -- fall back to the editor
        ; base, which for them IS the real record.
        bse = akActor.GetActorBase()
    EndIf
    If !bse
        Return -1
    EndIf
    Return bse.GetSex()
EndFunction

; Returns True if the actor has a female body (sex == 1).
; Used to gate anatomically-specific actions at the function level.
Bool Function HasFemaleBody(Actor akActor)
    If !akActor
        Return False
    EndIf
    Return _SexOf(akActor) == 1
EndFunction

; iTargetSex gate, shared by IsEligible (the ~24 "initiate an interaction" actions) AND Escalate_Execute
; directly — Escalate doesn't call IsEligible (it acts on an already-downed victim, not a fresh
; interaction, so the distance/combat/cooldown checks don't apply), so without this call it was NOT
; sex-gated at all: iTargetSex had zero effect on who Escalate could target, regardless of the setting.
; HelpUp/Release deliberately do NOT call this — recovering or releasing a downed victim should never be
; blocked by target sex.
; REV-145 3.3 (ruling (c), the baka-daemon.md REV-144 SS-C gate map): the three-level
; target-sex dropdown FOLDS this gate under SNBaka.TargetSexLevel. The retired
; iTargetSex property stays declared for save-member/VMAD compatibility but no
; longer gates anything; existing saves seed the level once from it
; (_SeedTargetSexLevel, the REV-144 bPlayerCanBeSpanked fold-in precedent).
;   Level 1 "Only female targets"                 -> female targets only (the old iTargetSex=1)
;   Level 2 "Male and female targets, male aggr." -> any target, MALE aggressors only
;   Level 3 "Anything goes"                       -> any target, any aggressor
Bool Function _TargetSexAllowed(Actor akTarget)
    If _TargetSexLevel() == 1 && !HasFemaleBody(akTarget)
        Return False
    EndIf
    Return True
EndFunction

; REV-145 3.3: the level of record (StorageUtil on None, save-persisted).
; Unknown/clamped values read as 1 -- never a silent behavior change on an
; unread value (the 6a discipline; conservative default = female-only).
Int Function _TargetSexLevel()
    Int iLevel = StorageUtil.GetIntValue(None, "SNBaka.TargetSexLevel", 1)
    If iLevel < 1 || iLevel > 3
        Return 1
    EndIf
    Return iLevel
EndFunction

; REV-145 3.3 one-shot seed from the retired keys (guarded, logged; the REV-144
; fold-in precedent). Existing saves: iTargetSex 1 -> L1 (female-only, behavior-
; preserving); 0 or 2 -> L3 (both/male-only target admission preserved; no level
; covers male-only targets, the closest target-admission-preserving level is L3).
; Fresh boots: L1 (female-only, the conservative reading -- same default class
; as the PlayerTargetPolicy DEFAULT OFF ruling).
Function _SeedTargetSexLevel()
    If StorageUtil.GetIntValue(None, "SNBaka.TargetSexLevel.Seeded", 0) == 1
        Return
    EndIf
    Int v = 1
    If !_bFreshBoot && iTargetSex != 1
        v = 3
    EndIf
    StorageUtil.SetIntValue(None, "SNBaka.TargetSexLevel", v)
    StorageUtil.SetIntValue(None, "SNBaka.TargetSexLevel.Seeded", 1)
    If _bFreshBoot
        _Log("[SNBaka] target-sex level SEEDED: L" + v + " (fresh boot -- female-only default, REV-145)")
    Else
        _Log("[SNBaka] target-sex level SEEDED: L" + v + " (existing save -- seeded from retired iTargetSex=" + iTargetSex + ", REV-145)")
    EndIf
EndFunction

; REV-145 3.3: LEVEL-2 AGGRESSOR-SEX HELPER (the REV-144 SS-C surfaced conflict:
; level-2's male-aggressor constraint had no aggressor-side sex check). First
; consumer = the daemon's pair selection; the escalation funnel sites adopt it
; as they are touched. Level 1: no aggressor constraint (targets are female-only
; at the target gate). Level 2: the initiator must be male. Level 3: no
; constraint. Reason-coded sentinel on the refuse leg only (the admit is the
; common path; the SS-C receipt rides the daemon pair log).
Bool Function _AggressorSexAllowed(Actor akInitiator, String asSite)
    If _TargetSexLevel() != 2
        Return True
    EndIf
    If _SexOf(akInitiator) == 0
        Return True
    EndIf
    _Log("[SNBaka] aggressor-sex REFUSED: L2 requires male aggressors (site=" + asSite + ", initiator=" + akInitiator.GetDisplayName() + ") -- REV-145")
    Return False
EndFunction

; ============================================================
; REV-144 4.2 — CENTRAL PLAYER-TARGET POLICY (rev-55a required deliverable)
; ============================================================
; User ruling: ONE central admission function, blanket across the ENTIRE Baka
; module (fresh interactions, the escalation funnel, spank/slap lanes, every
; creature lane, and -- at the daemon build -- both ambient modes: Mephala and
; Molag-Bal consult this same policy at candidate selection). StorageUtil class
; SNBaka.PlayerTargetPolicy, PLAYER-KEYED, DEFAULT OFF (0 = refuse NPC-initiated
; player-targeting). MCM-controlled -- the toggle builds with the baka-daemon MCM
; session; its label/tooltip is a pending-approvals DRAFT (gated, §7).
;
; MIGRATION (the bPlayerCanBeSpanked fold-in; DECIDED + SURFACED at REV-144):
; RETIRED AT REV-159 (dogfood 2.5 verdict). The v1 continuity read seeded the
; policy from the retired spank property's save value -- but that property's
; compile-time default is TRUE, so a save that NEVER WROTE the property reads
; TRUE and is indistinguishable from a save that deliberately set it TRUE
; (dogfood receipt: "[SNBaka] player-target policy SEEDED: ON (1) (existing
; save -- seeded from retired bPlayerCanBeSpanked=TRUE, REV-144)" while the
; user's old spank setting was OFF). The inheritance claim is also retired
; from the MCM tooltip (register entry 30a already dropped the sentence; the
; seed now matches the tooltip's promise). The corrected rule: the policy
; seeds OFF in BOTH branches (fresh boot AND existing save); a one-shot v2
; correction pass (Seeded2 key) resets the wrongly-inherited ON values that
; the v1 seed produced, then never runs again. The retired properties
; (bPlayerCanBeSpanked / bPlayerCanBeTarget) stay declared for save-member +
; esp-VMAD compatibility; they no longer gate anything and are no longer read.
Int Function _PlayerTargetPolicy()
    Return StorageUtil.GetIntValue(PlayerRef, "SNBaka.PlayerTargetPolicy", 0)
EndFunction

Function _SeedPlayerTargetPolicy()
    If !PlayerRef
        Return
    EndIf
    If StorageUtil.GetIntValue(PlayerRef, "SNBaka.PlayerTargetPolicy.Seeded2", 0) == 1
        Return
    EndIf
    Int iPrior  = StorageUtil.GetIntValue(PlayerRef, "SNBaka.PlayerTargetPolicy", 0)
    Int iV1Ran  = StorageUtil.GetIntValue(PlayerRef, "SNBaka.PlayerTargetPolicy.Seeded", 0)
    If iV1Ran == 1 && iPrior == 1
        ; the v1 unreliable-inheritance seed produced this ON value -- correct
        ; it to the ruled default (the user's authority: the boot value is OFF).
        _Log("[SNBaka] player-target policy CORRECTED: ON (1) -> OFF (0) (the REV-144 continuity seed inherited from retired bPlayerCanBeSpanked, whose TRUE default cannot distinguish set-TRUE from never-written -- inheritance retired, DEFAULT OFF, REV-159)")
    ElseIf iV1Ran == 0
        _Log("[SNBaka] player-target policy SEEDED: OFF (0) (DEFAULT OFF, no inheritance -- REV-159)")
    Else
        _Log("[SNBaka] player-target policy seed v2 pass: already OFF (0) -- no change (REV-159)")
    EndIf
    StorageUtil.SetIntValue(PlayerRef, "SNBaka.PlayerTargetPolicy", 0)
    StorageUtil.SetIntValue(PlayerRef, "SNBaka.PlayerTargetPolicy.Seeded", 1)
    StorageUtil.SetIntValue(PlayerRef, "SNBaka.PlayerTargetPolicy.Seeded2", 1)
EndFunction

; The central admission check. Returns True = this action MAY target the player.
; Unconditional passes: target is not the player; PLAYER-OWN action (initiator ==
; PlayerRef -- the Execute pattern: buttons/power/crosshair initiations stay
; ungated, the user's deliberate choice is never second-guessed). Otherwise the
; central policy is consulted, with a per-site reason code on the §5 sentinel
; (unconditional trace on BOTH admit and refuse).
; Consumers: IsEligible (paired executors), the daemon scan sites
; (mode.scan / mode.downed), and since REV-156 the NPC-on-player tattoo
; action lane (site "MarkPlayer", MarkPlayer_Execute — the action-lane
; consumer per the 3.5 pre-check; the player's own dialogue-commanded
; application stays ungated per the Execute pattern).
Bool Function _PlayerTargetAdmitted(Actor akInitiator, Actor akTarget, String asSite)
    If !akTarget || akTarget != PlayerRef
        Return True
    EndIf
    If akInitiator == PlayerRef
        Return True
    EndIf
    String sWho = "None"
    If akInitiator
        sWho = akInitiator.GetDisplayName()
    EndIf
    If _PlayerTargetPolicy() == 1
        _Log("[SNBaka] player-target ADMITTED: policy ON (site=" + asSite + ", initiator=" + sWho + ") -- REV-144 central gate")
        Return True
    EndIf
    _Log("[SNBaka] player-target REFUSED: policy OFF (site=" + asSite + ", initiator=" + sWho + ") -- REV-144 central gate")
    Return False
EndFunction

; ============================================================
; REV-145 — THE BAKA AMBIENT DAEMON (Mephala Mode / Molag Bal Mode)
; ============================================================
; Spec of record: baka-daemon.md REV-144 SS-A..SS-D + the REV-134e design pass
; (planner text verbatim). ONE daemon, two vocabularies (the module boundary
; respected): Baka = SECOND CONSUMER of the GS service class -- the arbiter/
; scan/floor patterns are copied shape, never merged scripts.
;   StorageUtil class SNBaka (on None, save-persisted, the GSAnim.Muse pattern):
;     SNBaka.MephalaMode   1 = ambient thought-seeding mode ON (45s tick since REV-146a, 60s per-actor)
;     SNBaka.MolagBalMode  1 = ambient overdrive ON (15s tick, 30s per-actor, no LLM, no thoughts)
;   Mode names = USER-AUTHORED, register-cited (17b precedent; entry 30/REV-134e (e)).
; Session-scoped by StorageUtil save-persistence exactly like GSAnim.Muse (the
; GS toggle-scope precedent -- SURFACED: same behavior, flags persist in saves).
; TIMER ANCHOR: the scan clock re-stamps at tick time (the GS interval-clock
; pattern); the per-actor action clock stamps at ACTION START (137f generalized
; at REV-144 SS-B(f)) -- SNBaka.DaemonLast, GAME-time, per-actor.
; Molag-Bal preempts Mephala when both ON (the GS overdrive-preempts-muse
; arbiter precedent). Multi-actor: Molag-Bal permitted (137f precedent,
; per-actor bookkeeping, no single-flight gate); Mephala ONE pending action
; at a time.

Actor[] _daemonPool
Actor[] _daemonDownedPool           ; REV-146a Task 8: downed actors stay POOL-ELIGIBLE as targets
Int _iDaemonDownedCount   = 0      ; REV-146a Task 8: valid entries in _daemonDownedPool
; [REV-174 D3 LEG 4] the Mephala pending-pair state (_akMephalaInitiator/
; _akMephalaTarget/_iMephalaBand/_bMephalaPending) REMOVED with
; _DaemonMuseAsk; single-in-flight lives on _bLanePending.

; REV-145 3.6: the two mode toggles (Prisma footer buttons + MCM both route here).
; Names/notifications USER-AUTHORED (register-cited); ASCII throughout.
Function _MephalaToggle()
    Int v = 1 - StorageUtil.GetIntValue(None, "SNBaka.MephalaMode", 0)
    StorageUtil.SetIntValue(None, "SNBaka.MephalaMode", v)
    If v == 1
        ; REV-169 leg 6 (user ruling 2026-10-28: all four DeD modes expire at
        ; 3600s -- the "forgot-it-is-on" residue guard): Mephala had NO
        ; auto-expire (manual toggle only). Stamp the 1h guard; the tick checks it.
        StorageUtil.SetFloatValue(None, "SNBaka.MephalaExpireAt", Utility.GetCurrentRealTime() + 3600.0)
        Debug.Notification("Mephala Mode - on. The web of whispers stirs.")   ; REV-174a D5 " - " sweep
        _Log("[SNBaka] daemon mode ON: Mephala (45s/60s) -- REV-146a cadence")
    Else
        _bLanePending = False
        _akLaneSubject = None
        _sLaneMode = ""
        StorageUtil.SetFloatValue(None, "SNBaka.MephalaExpireAt", 0.0)
        Debug.Notification("Mephala Mode - off.")   ; REV-174a D5 " - " sweep
        _Log("[SNBaka] daemon mode OFF: Mephala -- REV-145")
    EndIf
    _DaemonArm()
    _PushModeStates()
EndFunction

Function _MolagBalToggle()
    Int v = 1 - StorageUtil.GetIntValue(None, "SNBaka.MolagBalMode", 0)
    StorageUtil.SetIntValue(None, "SNBaka.MolagBalMode", v)
    If v == 1
        ; REV-169 leg 6: the 1h guard, same as Mephala above.
        StorageUtil.SetFloatValue(None, "SNBaka.MolagBalExpireAt", Utility.GetCurrentRealTime() + 3600.0)
        Debug.Notification("Molag Bal Mode - on. The ball begins.")   ; REV-174a D5 " - " sweep
        _Log("[SNBaka] daemon mode ON: Molag Bal (15s/30s, no thoughts) -- REV-145")
    Else
        StorageUtil.SetFloatValue(None, "SNBaka.MolagBalExpireAt", 0.0)
        Debug.Notification("Molag Bal Mode - off.")   ; REV-174a D5 " - " sweep
        _Log("[SNBaka] daemon mode OFF: Molag Bal -- REV-145")
    EndIf
    _DaemonArm()
    _PushModeStates()
EndFunction

; REV-147 Feature B: push the live mode-button ON/OFF highlight to the open panel.
; Papyrus is the arbiter (the flags above); the DLL relays the payload to JS. Called
; at panel open and after every toggle, so the footer buttons always mirror the flags.
Function _PushModeStates()
    Int iMeph  = StorageUtil.GetIntValue(None, "SNBaka.MephalaMode", 0)
    Int iMolag = StorageUtil.GetIntValue(None, "SNBaka.MolagBalMode", 0)
    SNBakaUI.SetModeStates(iMeph == 1, iMolag == 1)
    _Log("[SNBaka][PANEL] mode states pushed: Mephala=" + iMeph + " MolagBal=" + iMolag)
EndFunction

; REV-147 Feature B: the footer mode buttons (numeric 900/901) now arrive on their own
; DLL dispatch that KEEPS THE PANEL OPEN (the bridge intercepts the ids before the
; modal unfocus/hide path -- the REV-146a JS design intent "both modes toggled in one
; visit" is now actually true bridge-side). Papyrus arbitrates exactly as before; the
; toggles push the new highlight state back through _PushModeStates.
Function _MenuModeButton(Int aiWhich)
    If aiWhich == 900
        _Log("[SNBaka][PANEL] mode button 900 (Mephala) - panel stays open")
        _MephalaToggle()
    ElseIf aiWhich == 901
        _Log("[SNBaka][PANEL] mode button 901 (Molag Bal) - panel stays open")
        _MolagBalToggle()
    Else
        _Log("[SNBaka][PANEL] mode button: unknown id " + aiWhich + " - ignored")
    EndIf
EndFunction

; Arm/disarm the shared tick: Molag-Bal cadence (15s) preempts Mephala (30s)
; when both ON (the GS arbiter ElseIf discipline). Both off = disarmed (the
; multiplexer drops the daemon leg; zero cost, same as GS flags-off idle).
Function _DaemonArm()
    Int iMolag = StorageUtil.GetIntValue(None, "SNBaka.MolagBalMode", 0)
    Int iMeph  = StorageUtil.GetIntValue(None, "SNBaka.MephalaMode", 0)
    If iMolag == 1
        _fBakaDaemonNextRT = Utility.GetCurrentRealTime() + StorageUtil.GetFloatValue(None, "SNBaka.MolagBalCadence", 15.0)
    ElseIf iMeph == 1
        _fBakaDaemonNextRT = Utility.GetCurrentRealTime() + StorageUtil.GetFloatValue(None, "SNBaka.MephalaCadence", 45.0)
    Else
        _fBakaDaemonNextRT = 0.0
    EndIf
    _ArmRealtimeTimer()
EndFunction

; The tick (receipt standard: EVERY leg sentinel'd, ASCII, unconditional -- the
; 137f precedent template). Combat suspend: player in combat = early return,
; scan clock NOT re-stamped (resumes cleanly at cadence; the GS MuseTick
; pattern, ruling rev-9 (b)). 1h expiry guard since REV-169 leg 6 (SNBaka.MephalaExpireAt / MolagBalExpireAt, checked in _DaemonTick);
; so the GS expiry clock-pause leg has no equivalent here -- SURFACED, not
; silently dropped.
Function _DaemonTick()
    ; REV-167c 2.2 (community performance fold, the lazy-string shape): the
    ; tick-opportunity concatenation (two StorageUtil reads + _TargetSexLevel()
    ; + the string build) ran every cadence BEFORE the bDebugLog check --
    ; Papyrus evaluates arguments first, so the construction cost was paid
    ; even with logging off. Construction now gated behind the flag; the
    ; trace string itself is unchanged.
    If bDebugLog
        _Log("[SNBaka] daemon tick opportunity (Mephala=" + StorageUtil.GetIntValue(None, "SNBaka.MephalaMode", 0) + " MolagBal=" + StorageUtil.GetIntValue(None, "SNBaka.MolagBalMode", 0) + ", level L" + _TargetSexLevel() + ") -- REV-145")
    EndIf
    If PlayerRef.IsInCombat()
        ; REV-167c 2.1 (community performance fold, by-concept): the
        ; overdue-deadline re-request loop. This early Return left
        ; _fBakaDaemonNextRT in the past (overdue); _ArmRealtimeTimer clamps
        ; registration to RegisterForSingleUpdate(0.1) when the next deadline
        ; is <= now -- so every 0.1s OnUpdate re-fires _DaemonTick, which hits
        ; this same combat early-return, forever: the spin loop (the finder's
        ; "repeated 0.1-second update requests" headline). Fix per their
        ; shape: advance the deadline by 5s on the blocked leg -- an idle
        ; re-check cadence during combat, never a spin. DIVERGENCE FROM
        ; REV-145 NAMED: the old receipt said "clock unspent -- resumes
        ; cleanly at cadence"; the +5s advances ARE spent, so post-combat the
        ; next tick lands within <=5s of combat end (a bounded, receipted
        ; drift from the instant-resume intent -- not silently dropped).
        _fBakaDaemonNextRT = _fBakaDaemonNextRT + 5.0
        _Log("[SNBaka] daemon suspend-player-combat: tick skipped, deadline +5s (idle re-check, no spin) -- REV-167c 2.1")
        Return
    EndIf
    Int iMolag = StorageUtil.GetIntValue(None, "SNBaka.MolagBalMode", 0)
    Int iMeph  = StorageUtil.GetIntValue(None, "SNBaka.MephalaMode", 0)
    ; REV-169 leg 6 (user ruling 2026-10-28): the 1h "forgot-it-is-on" guard.
    ; Mephala/Molag Bal had NO auto-expire (manual toggles only). The tick is
    ; the guard point: expired = call the user's own toggle (reuses the shipped
    ; OFF notification verbatim -- no new user-facing string), sentinel first.
    ; Molag-Bal checked first (it preempts); each leg Returns -- the disarmed
    ; re-arm inside the toggle sets the next deadline correctly.
    Float fNowRT = Utility.GetCurrentRealTime()
    Float fExpMolag = StorageUtil.GetFloatValue(None, "SNBaka.MolagBalExpireAt", 0.0)
    Float fExpMeph  = StorageUtil.GetFloatValue(None, "SNBaka.MephalaExpireAt", 0.0)
    If iMolag == 1 && fExpMolag > 0.0 && fNowRT >= fExpMolag
        _Log("[SNBaka] daemon mode auto-expire (1h guard): Molag Bal -- REV-169")
        _MolagBalToggle()
        Return
    EndIf
    If iMeph == 1 && fExpMeph > 0.0 && fNowRT >= fExpMeph
        _Log("[SNBaka] daemon mode auto-expire (1h guard): Mephala -- REV-169")
        _MephalaToggle()
        Return
    EndIf
    Int iMode = 0   ; 2 = Molag-Bal (preempts), 1 = Mephala
    If iMolag == 1
        iMode = 2
    ElseIf iMeph == 1
        iMode = 1
    EndIf
    If iMode == 0
        _fBakaDaemonNextRT = 0.0
        _Log("[SNBaka] daemon refuse: both modes off at tick -- disarmed")
        Return
    EndIf
    ; [REV-178d Leg 1] the tick-entry re-stamp is REMOVED (S244 verdict,
    ; 2026-11-04: armed-at-tick = every pending-blocked tick burned a full
    ; cadence slot of pure waiting -- the 65s-ask starvation case, 4-5 lost
    ; Molag slots per in-flight answer). A cadence slot is consumed only when
    ; an ask actually DISPATCHES (_DaemonTwoStageAsk arms there now); ticks
    ; that dispatch nothing fall to the 5s idle re-arm at the tail of this
    ; tick. Cadence keys unchanged (SNBaka.MolagBalCadence 15s /
    ; SNBaka.MephalaCadence 45s defaults, MCM sliders per REV-159 5.2).
    ; REV-159 (dogfood 2.2): the tattoo ambient exposure roll is DECOUPLED from
    ; the daemon tick -- it now rides its own multiplexer cadence
    ; (_STAmbientStart, 30s) so the observed-cue rolls with the modes OFF
    ; (the dogfood finding: modes-off = silence). Roll chance + cooldown are
    ; unchanged (module-owned). This call site is RETIRED; banner per the
    ; ruleset. The v1 heartbeat ObservationPass remains RETIRED (REV-156).
    ; SNBaka_SlaveTatsModule.AmbientExposurePass()   ; RETIRED at REV-159
    If _bLanePending
        ; [REV-178a Leg 7] AGE-STAMP RECLAIM: a pending ask older than 30s
        ; real-time is a lost callback (wedge), never a live ask -- named
        ; sentinel (mode + actor), reclaim, let the tick proceed.
        If Utility.GetCurrentRealTime() - _fLanePendingStamp > 30.0
            String sRe = _sLaneMode
            If _akLaneSubject
                sRe = sRe + ", actor=" + _akLaneSubject.GetDisplayName()
            EndIf
            _Log("[SNBaka] pending-gate RECLAIM (>30s real-time, " + sRe + ") -- REV-178a Leg 7")
            _bLanePending = False
            _akLaneSubject = None
            _sLaneMode = ""
        Else
            _Log("[SNBaka] daemon refuse: busy (two-stage ask pending) -- one pending ask at a time -- REV-174 D3")
            Return
        EndIf
    EndIf
    _DaemonAttempt(iMode)
    ; [REV-178d Leg 1] IDLE-DEADLINE GUARD: with arming moved to the dispatch
    ; site, a tick that dispatched nothing leaves the deadline in the past;
    ; the multiplexer would clamp registration to 0.1s and spin (the
    ; REV-167c 2.1 class). Advance by a 5s idle re-check instead -- bounded,
    ; sentinel'd, and pending-blocked ticks cost 5s, never a cadence slot.
    If _fBakaDaemonNextRT > 0.0 && _fBakaDaemonNextRT <= Utility.GetCurrentRealTime()
        _fBakaDaemonNextRT = Utility.GetCurrentRealTime() + 5.0
        _Log("[SNBaka] daemon idle re-arm (+5s, no ask dispatched this tick) -- REV-178d Leg 1")
    EndIf
EndFunction

; REV-145 3.2: THE CANDIDATE POOL (paired-action _DaemonScan; the GS service-class
; pattern, Baka-side filters). Radius 2500 (fDaemonRadius precedent), loaded/alive/
; not-combat, plus the Baka busy guards (SNBaka.Locked, downed, mid sex scene,
; creature skeleton). Seated/idle candidates are ADMITTED as candidates when the
; REV-135/136/137 idle-interrupt service is present (the REV-87/88/89 seated-
; candidate question resolved interrupt-then-fire per the 2026-10-20 ruling (d)):
; class 1/2 (furniture sit / idle-marker hold) enter the pool and are exited at
; fire time; essential classes (-1 sleep, -2 downed, -3 mounted, -4 swimming,
; -5 sneaking) never enter. Without the GS esp there is no class read and no
; interrupt: seated candidates are refused reason-coded (the old exclusion, now
; named instead of silent -- the REV-90 rider class).
; REV-146a Task 2: the child boundary gates the POOL itself (belt-and-braces
; with IsEligible's own gate; the pool refuse is named).
; REV-146a Task 8 (user ruling: downed follow-up "should happen sometimes"):
; DOWNED actors are NO LONGER pool-refused — they enter the separate
; _daemonDownedPool and stay eligible as TARGETS with a downed-family action
; subset at fire time (_DaemonDownedAction below). Downed actors still never
; INITIATE (IsEligible's downed-initiator gate). Children are refused at BOTH
; pools (Task 2). Executor class per ruling: forced/intimate/strip/tattoo;
; NEVER Execute; player-target policy + target-sex gates unchanged (they run
; at target selection AND the fire-time IsEligible recheck).
Int Function _DaemonScan()
    If !_daemonPool || _daemonPool.Length < 64
        _daemonPool = New Actor[64]
    EndIf
    If !_daemonDownedPool || _daemonDownedPool.Length < 32
        _daemonDownedPool = New Actor[32]
    EndIf
    Int n = 0
    Int nd = 0
    Bool bGSPresent = _GSPresent()
    Actor[] akAll = PO3_SKSEFunctions.GetActorsByProcessingLevel(0)
    Int i = 0
    While i < akAll.Length && (n < 64 || nd < 32)
        Actor ak = akAll[i]
        If !ak || ak == PlayerRef || ak.IsDead() || ak.IsInCombat() || ak.GetDistance(PlayerRef) > 2500.0
            ; walk-neutral: never-candidates, no sentinel (the pool census logs n)
        ElseIf ak.IsChild()
            ; REV-146a Task 2: the child boundary gates the pool itself.
            _Log("[SNBaka] daemon pool refuse: child-boundary (" + ak.GetDisplayName() + ") -- REV-146a")
        ElseIf _IsCreatureActor(ak)
            _Log("[SNBaka] daemon pool refuse: creature-skeleton (" + ak.GetDisplayName() + ") -- REV-145")
        ElseIf IsInSexAnimation(ak) || StorageUtil.GetIntValue(ak, "SNBaka.Locked", 0) == 1
            _Log("[SNBaka] daemon pool refuse: busy (in-scene/locked) (" + ak.GetDisplayName() + ") -- REV-145")
        ElseIf _IsDownedAny(ak)
            ; REV-146a Task 8: downed actors are DOWNED-POOL candidates (targets
            ; only; the downed-family subset draws at fire). Named admission.
            _daemonDownedPool[nd] = ak
            nd += 1
            _Log("[SNBaka] daemon downed-pool admit: " + ak.GetDisplayName() + " (downed target candidate) -- REV-146a")
        ElseIf StorageUtil.GetStringValue(ak, "GSAnim.Pose", "") != ""
            _Log("[SNBaka] daemon pool refuse: busy (GS pose active) (" + ak.GetDisplayName() + ") -- REV-145")
        ElseIf !bGSPresent && ak.GetSitState() != 0
            _Log("[SNBaka] daemon pool refuse: busy (seated, no idle-svc) (" + ak.GetDisplayName() + ") -- REV-145")
        ElseIf bGSPresent && SkyrimNet_AnimationsGS._IdleClass(ak) < 0
            _Log("[SNBaka] daemon pool refuse: busy (essential idle class) (" + ak.GetDisplayName() + ") -- REV-145")
        Else
            _daemonPool[n] = ak
            n += 1
        EndIf
        i += 1
    EndWhile
    _iDaemonDownedCount = nd
    _Log("[SNBaka] daemon pool census: standing=" + n + " downed=" + nd + " -- REV-146a")
    Return n
EndFunction

; REV-146a Task 8: the DOWNED-FAMILY ACTION SUBSET (user ruling: forced/
; intimate/strip/tattoo executor class; NEVER Execute). Drawn only when the
; selected target is downed. Player-target policy + target-sex gates run at
; target selection and the fire-time IsEligible recheck (unchanged).
;   ForcedKiss, BackHugMolest, TouchBreasts, SuckBreasts, FondlePussy,
;   OralOnTarget, CapturedInspect, Strip, ApplyTattoo
String[] Function _DaemonDownedActionPool()
    String[] d = New String[9]
    d[0] = "ForcedKiss"
    d[1] = "BackHugMolest"
    d[2] = "TouchBreasts"
    d[3] = "SuckBreasts"
    d[4] = "FondlePussy"
    d[5] = "OralOnTarget"
    d[6] = "CapturedInspect"
    d[7] = "Strip"
    d[8] = "ApplyTattoo"
    Return d
EndFunction

; REV-145 3.4: arousal band on the INITIATOR (the REV-82 tiering chain read:
; band -> action-class subset). Same framework reads as GetDedArousal; no
; framework = tier 1 (mild -- never a silent extremity unlock).
Int Function _DaemonArousalTier(Actor ak)
    Int arousal = -1
    If SKSE.GetPluginVersion("OSLAroused") > 0
        arousal = OSLArousedNative.GetArousalNoSideEffects(ak) as Int
    Else
        slaFrameworkScr kNG = Quest.GetQuest("sla_Framework") as slaFrameworkScr
        If kNG
            arousal = kNG.GetActorArousal(ak)
        EndIf
    EndIf
    If arousal < 0
        Return 1
    EndIf
    If arousal >= 75
        Return 3
    ElseIf arousal <= 25
        Return 1
    EndIf
    Return 2
EndFunction

; ============================================================================
; REV-167 TRANCHE 3 (entry 44) -- THE UNIFIED SELECTION LADDER (consolidated
; spec "Ambient Modes -- Unified Selection Architecture" 3.1/3.3; rulings
; R-1..R-6). Defaults preserve R-1 (targeted Molag) + R-3 (unbanded default):
; both toggles read live, default OFF, keys on None (global).
; ============================================================================

; [REV-174 A3] RETIRED: the Madness toggle read. The R-2 dice-torrent shape is
; gone with randomization (A1); extremity is now the mode's default character.
; [REV-174 D1] Madness now also removed from the MCM surface entirely (user
; ruling 2026-10-30: redundant beside the dropdown's random options).

; [REV-174 A3] RETIRED: the Banded Actions toggle read. The lockout ladder's
; purpose died with the trust-the-LLM arc (banding retired, Molag
; de-randomized, idles re-admitted); the full pool ships premise-steered.

; R-5 (helper, inlined in _DaemonOptionsPool): WombHit leaves Mephala's options
; set ENTIRELY (not banded out -- absent, in every tier/toggle state). Band-3
; membership unchanged; mode membership is Molag-only. Papyrus array `New`
; sizes must be literals, so the strip is the band-3 set's fixed 29 -> 28 copy
; (the ONLY pool carrying WombHit -- verified against the band table above).

; 3.1/3.2: THE OPTIONS RENDER -- one tier read per consideration (the caller
; reads once, passes it; the same read feeds the pack context AND the ladder,
; no double reads). Banded OFF = base band 3 = the full set (R-3); Banded ON =
; base band = the initiator's tier (bands below LOCKED OUT -- lockout, not
; unlock). The mode filter then applies (R-5). Receipts: tier x lockout per
; consideration (8's "ladder receipts" gate) + the render's action count (8's
; "options completeness" gate).
String[] Function _DaemonOptionsPool(String asMode, Actor akInitiator, Int aiTier)
    ; [REV-174 A3] Banded RETIRED: base band is ALWAYS 3 (the full set,
    ; premise-steered -- the R-3 default made permanent). The tier rides as
    ; context only (the pack's arousalBand field).
    Int iBase = 3
    _Log("[SNBaka] ladder receipt: mode=" + asMode + " initiator=" + akInitiator.GetDisplayName() + " tier=" + aiTier + " banded=RETIRED -> full set offered (tier rides as context) -- REV-174 A3")
    String[] pool = _DaemonActionPool(iBase)
    If asMode == "Mephala"
        If pool.Length == 29
            ; the band-3 full set: strip WombHit (fixed 29 -> 28 copy)
            String[] m28 = New String[28]
            Int mi = 0
            Int mx = 0
            While mi < 29
                If pool[mi] != "WombHit"
                    m28[mx] = pool[mi]
                    mx += 1
                EndIf
                mi += 1
            EndWhile
            pool = m28
        EndIf
        _Log("[SNBaka] wombhit mode-scope: WombHit absent from Mephala's options render (R-5, every state) -- REV-167 t3")
    EndIf
    _Log("[SNBaka] options render: mode=" + asMode + " count=" + pool.Length + " -- REV-167 t3")
    Return pool
EndFunction

; ----------------------------------------------------------------------------
; REV-167 t3 2.4 -- THE 15.5 LOCK AUDIT (both trees, receipts):
;  * ADMISSION EXCLUSION (Baka): _DaemonScan refuses SNBaka.Locked=1,
;    in-scene, and GSAnim.Pose!="" actors at BOTH pools (the subject walk and
;    the target walk draw only from _daemonPool/_daemonDownedPool, which
;    exclude them) -- no mid-action actor can be selected on either side.
;  * ADMISSION EXCLUSION (GS): the GS-side candidate gates refuse posed actors
;    (the GSAnim.Pose check) and the seed/fire guards re-run _IsBusyElsewhere,
;    which consumes SNBaka.Locked + SNBaka.OnGround + SNAcheron.Held +
;    bleedout + foreign sex scenes + combat + furniture.
;  * FIRE-TIME RECHECK (Baka): OnBakaMuseConsideration + OnMolagConsideration
;    both re-verify SNBaka.Locked on BOTH actors between answer and dispatch
;    (the named "ongoing-action lock" sentinel) -- the race window is closed.
;  * FIRE-TIME RECHECK (GS): OnMuseConsideration (seed) + OnSheoConsideration
;    (fire) re-run _IsBusyElsewhere on the pending actor (named sentinels).
;  * BUSY-FLAG SET/CLEAR: SNBaka.Locked is set on every Baka action start and
;    cleared on every end path (the shipped busy flag the audit consumes; no
;    new state added); GSAnim.Pose is set at pose fire and cleared at pose end
;    (the 3s sweep backstops). The lock CONSUMES these flags -- this audit is
;    the receipt the spec asked for.
;  * MADNESS MULTI-PENDING (enumerated): the torrent is single-SLOT as built
;    (one _bMolagPending pair in flight at a time); its multi-actor character
;    is the dice casting ACROSS ticks at the 15s-class cadence, and the 15.5
;    lock serializes every in-flight pair so nothing stacks -- the 15.7
;    mitigation, load-bearing exactly as specced for Companions Only + 15s.
; ----------------------------------------------------------------------------

; REV-145 3.4: the ACTION -> CLASS -> EXTREMITY-BAND table of record (ruling (a):
; ALL module actions in the pool; Mephala subsets by band, Molag-Bal draws the
; full set; asset-guards stay UNCONDITIONAL in the executors (rev-55b) -- the
; pool never pre-clears them).
;   Band 1 (mild / social-affection):  Flirt, FlirtFace, FlirtBreast, FlirtPussy,
;     BackHug, FrontHug, KissLove, ArmHold, ShowingOffBody
;   Band 2 (mid / intimate-touch, tier 2+): ForcedKiss, TouchBreasts, SuckBreasts,
;     ExaminePrivates, PlayPrivates, FondlePussy, Spanking, DrunkExploit,
;     DrugFood, OralOnTarget, Investigate, CapturedInspect, Strip
;   Band 3 (aggressive/overpower, tier 3 only): Struggle, ChokeHug, ChokeHelpless,
;     WombHit, PinHelpless, Subdue, BackHugMolest
; STRUGGLE-CHAIN (ruling): forced/choke/wombhit-class REQUIRE the struggle first
; (see _DaemonIsStruggleChain). Strip is in the pool from day one (REV-144 6.x
; build, SS-B(a)); the player-side downed-menu tile stays its manual surface.
String[] Function _DaemonActionPool(Int aiBand)
    If aiBand < 1
        aiBand = 1
    ElseIf aiBand > 3
        aiBand = 3
    EndIf
    If aiBand == 1
        String[] pool1 = New String[9]
        pool1[0] = "Flirt"
        pool1[1] = "FlirtFace"
        pool1[2] = "FlirtBreast"
        pool1[3] = "FlirtPussy"
        pool1[4] = "BackHug"
        pool1[5] = "FrontHug"
        pool1[6] = "KissLove"
        pool1[7] = "ArmHold"
        pool1[8] = "ShowingOffBody"
        Return pool1
    ElseIf aiBand == 2
        String[] pool2 = New String[22]
        pool2[0] = "Flirt"
        pool2[1] = "FlirtFace"
        pool2[2] = "FlirtBreast"
        pool2[3] = "FlirtPussy"
        pool2[4] = "BackHug"
        pool2[5] = "FrontHug"
        pool2[6] = "KissLove"
        pool2[7] = "ArmHold"
        pool2[8] = "ShowingOffBody"
        pool2[9]  = "ForcedKiss"
        pool2[10] = "TouchBreasts"
        pool2[11] = "SuckBreasts"
        pool2[12] = "ExaminePrivates"
        pool2[13] = "PlayPrivates"
        pool2[14] = "FondlePussy"
        pool2[15] = "Spanking"
        pool2[16] = "DrunkExploit"
        pool2[17] = "DrugFood"
        pool2[18] = "OralOnTarget"
        pool2[19] = "Investigate"
        pool2[20] = "CapturedInspect"
        pool2[21] = "Strip"
        Return pool2
    EndIf
    String[] pool3 = New String[29]
    pool3[0] = "Flirt"
    pool3[1] = "FlirtFace"
    pool3[2] = "FlirtBreast"
    pool3[3] = "FlirtPussy"
    pool3[4] = "BackHug"
    pool3[5] = "FrontHug"
    pool3[6] = "KissLove"
    pool3[7] = "ArmHold"
    pool3[8] = "ShowingOffBody"
    pool3[9]  = "ForcedKiss"
    pool3[10] = "TouchBreasts"
    pool3[11] = "SuckBreasts"
    pool3[12] = "ExaminePrivates"
    pool3[13] = "PlayPrivates"
    pool3[14] = "FondlePussy"
    pool3[15] = "Spanking"
    pool3[16] = "DrunkExploit"
    pool3[17] = "DrugFood"
    pool3[18] = "OralOnTarget"
    pool3[19] = "Investigate"
    pool3[20] = "CapturedInspect"
    pool3[21] = "Strip"
    pool3[22] = "Struggle"
    pool3[23] = "ChokeHug"
    pool3[24] = "ChokeHelpless"
    pool3[25] = "WombHit"
    pool3[26] = "PinHelpless"
    pool3[27] = "Subdue"
    pool3[28] = "BackHugMolest"
    Return pool3
EndFunction

; REV-145 3.4: the struggle-chain class (ruling: forced/choke/wombhit-class
; REQUIRE the struggle first -- the ambient seeds the INTENTION, the actor
; initiates, the follow-up rides the outcome through the existing struggle/
; escalation machinery (Struggle_Execute's _DefeatGroundWindow -> baka_escalate
; funnel, and _CueDecisionIfDowned's ground-window keep-alive).
Bool Function _DaemonIsStruggleChain(String sAction)
    Return sAction == "ChokeHug" || sAction == "ChokeHelpless" || sAction == "WombHit" \
        || sAction == "PinHelpless" || sAction == "Subdue" || sAction == "ForcedKiss" \
        || sAction == "BackHugMolest"
EndFunction

; REV-145 3.7: the drunk/tavern variant (planner: "struggle action picks should
; do the drunk struggle action when in taverns or if the target is drunk").
; Tavern-class read: the player's current location carries LocTypeInn.
Bool Function _DaemonIsTavernClass()
    If !PlayerRef || !PlayerRef.GetCurrentLocation()
        Return False
    EndIf
    Return PlayerRef.GetCurrentLocation().HasKeyword(Keyword.GetKeyword("LocTypeInn"))
EndFunction

; REV-145 3.7: drunk-target read. The tree has NO dedicated drunk-state query
; (SURFACED -- the REV-134e "Baka drunk-state queries" pointer was design-
; inferred, not site-verified; not a spec-vs-tree conflict: the variant is fully
; deliverable on tree-true signals); the two signals used: the PoseDrink
; blackout stamp (written at the blackout site, cleared at its recovery leg) and
; the LastAnim=="DrunkExploit" trace (a just-exploited impaired victim).
Bool Function _DaemonIsDrunkTarget(Actor akTarget)
    If !akTarget
        Return False
    EndIf
    If StorageUtil.GetIntValue(akTarget, "SNBaka.DrunkBlackout", 0) == 1
        Return True
    EndIf
    Return StorageUtil.GetStringValue(akTarget, "SNBaka.LastAnim", "") == "DrunkExploit"
EndFunction

; ============================================================================
; REV-167 t3 (entry 44, §5/2.3): THE SELECTION MODES (subject + target, per
; Baka mode). Dropdown keys SNBaka.<Mode>Subject / SNBaka.<Mode>Target
; (None-keyed StorageUtil ints; 0 = the shipped Random draw = byte-equivalent
; behavior -- no filter, no weighting). The Target Link Weight slider key is
; [REV-174a A35] the UNIFORM selection vocabularies (parity table of record,
; REV-174a_A35_PARITY.md; both modules).
; Subject: 0 Random / 1 Companions Only / 2 Arousal Based (NEW -- weighted
; toward the most aroused candidates, tier A = arousal >= 50, ratio 70%).
; Target: 0 Random / 1 Bio Led / 2 Relationship Priority / 3 Player
; Only / 4 Companions Only / 5 Non-Companion NPCs Only. Bio Led + RP are
; PROMPT-SIDE steering (A36a: facts in, trust the LLM -- the pack carries a
; targetSteer field; the roster is NOT filtered). [REV-174a A46] the "Wide"
; option (v21 slot 3; roster cap 10->20) is RETIRED pre-ship -- never a
; user-facing surface, no shipped text; the cap is the standing 10.
; [REV-174a A36c] the mechanical two-tier bio-link draws
; + the Target Link Weight slider are RETIRED (the SNBaka.BioNames cache was
; cold since REV-173 Path A -- the no-op D2 named); the stored
; SNBaka.TargetLinkWeight key is no longer read.
; Every non-Random draw is receipted; empty pool = skip tick, never
; fall-through (§15.12).
; ============================================================================
Int Function _SelectionSubject(String asMode)
    Int v = StorageUtil.GetIntValue(None, "SNBaka." + asMode + "Subject", 0)
    ; [REV-174a A35] clamp 0-2 (legacy 2 RP / 3 Bio Led retired subject-side;
    ; the MCM v21 migration remaps stored values, out-of-range clamps Random).
    If v < 0 || v > 2
        Return 0
    EndIf
    Return v
EndFunction

Int Function _SelectionTarget(String asMode)
    Int v = StorageUtil.GetIntValue(None, "SNBaka." + asMode + "Target", 0)
    ; [REV-178 L3] clamp 0-3 (the v23 POOL space: Everyone/Player Only/
    ; Companions/Non-Companions; the MCM v23 migration _SelVocabMigrate5
    ; remaps stored values, out-of-range clamps Everyone).
    If v < 0 || v > 3
        Return 0
    EndIf
    Return v
EndFunction

; ============================================================================
; [REV-178 L4] NARRATIVE SELECTION -- the shared pool service (Baka side;
; the GS tree carries the mirror). §6.1: sticky 5 + conversation-priority
; (vanilla IsInDialogue()/GetDialogueTarget() pair-priority, §22 ruling),
; proximity fill, churn recompute, player = TARGET-pool constant only
; (OR2 -- never a subject). SA guard + getters per §6.2/§22.
; ============================================================================
Actor[] _akNarrSubPool
Int     _iNarrSubPoolN = 0
Actor   _akNarrLastSubj = None
Actor   _akNarrLastTgt = None
Int     _iNarrSAResolved = 0
Bool    _bNarrSAPresent = False

Bool Function _NarrSAPresent()
    If _iNarrSAResolved == 0
        _iNarrSAResolved = 1
        _bNarrSAPresent = SKSE.GetPluginVersion("SeverActionsNative") > 0
        If _bNarrSAPresent
            Debug.Trace("[SNBaka] SA presence guard: SeverActions PRESENT (first-call sentinel) -- REV-178 L4")
        Else
            Debug.Trace("[SNBaka] SA presence guard: SeverActions absent -- SA fields skipped every pack (V5 receipts live here) -- REV-178 L4")
        EndIf
    EndIf
    Return _bNarrSAPresent
EndFunction

; [REV-178 L4] SA candidate fragment (saManaged/saMood/saPlayerRapport,
; OR3; SA numbers as STRINGS per the §6.5 example).
String Function _NarrSAFieldsJson(Actor akC)
    If !akC || !_NarrSAPresent()
        Return ""
    EndIf
    Float fMood = SeverActionsNative.Native_GetMood(akC)
    Float fRap = SeverActionsNative.Native_GetRapport(akC)
    Bool bManaged = !(fMood == 50.0 && fRap == 0.0)
    Return "\"saManaged\":" + bManaged as Int \
         + ",\"saMood\":\"" + (fMood as Int) + "\"" \
         + ",\"saPlayerRapport\":\"" + (fRap as Int) + "\""
EndFunction

; [REV-178 L4] does akC pass the mode's SUBJECT POOL filter?
; v23 space: 0 Everyone / 1 Companions Only / 2 Non-Companion NPCs Only.
Bool Function _NarrSubjectPoolAdmits(Actor akC, Int aiPool)
    If !akC || akC == PlayerRef
        Return False
    EndIf
    If aiPool == 1
        Return _SelectionIsCompanion(akC)
    ElseIf aiPool == 2
        Return !_SelectionIsCompanion(akC)
    EndIf
    Return True
EndFunction

Function _NarrStickyRemember(Actor akSubj, Actor akTgt)
    _akNarrLastSubj = akSubj
    _akNarrLastTgt = akTgt
EndFunction

Bool Function _NarrSubPoolHas(Actor akC)
    Int j = 0
    While j < _iNarrSubPoolN
        If _akNarrSubPool[j] == akC
            Return True
        EndIf
        j += 1
    EndWhile
    Return False
EndFunction

; [REV-178 L4] the SUBJECT POOL build: sticky first, dialogue-priority
; pair-next, proximity fill to 5; churn recompute (full recomposition only
; below 3 valid -- §6.1.6, no rotation quota). Anchor = the tick's subject.
Function _NarrSubjectPoolBuild(Actor akAnchor, Int aiPoolN, Int aiSubjectPoolSetting)
    If !_akNarrSubPool || _akNarrSubPool.Length < 5
        _akNarrSubPool = New Actor[5]
    EndIf
    Int iStillValid = 0
    Int i = 0
    While i < _iNarrSubPoolN
        Actor akM = _akNarrSubPool[i]
        If akM && !akM.IsDead() && akAnchor.GetDistance(akM) <= 2500.0 \
           && _NarrSubjectPoolAdmits(akM, aiSubjectPoolSetting)
            iStillValid += 1
        EndIf
        i += 1
    EndWhile
    If iStillValid >= 3
        Return
    EndIf
    _iNarrSubPoolN = 0
    If _akNarrLastSubj && !_akNarrLastSubj.IsDead() && _akNarrLastSubj != PlayerRef \
       && akAnchor.GetDistance(_akNarrLastSubj) <= 2500.0 \
       && _NarrSubjectPoolAdmits(_akNarrLastSubj, aiSubjectPoolSetting)
        _akNarrSubPool[_iNarrSubPoolN] = _akNarrLastSubj
        _iNarrSubPoolN += 1
    EndIf
    If _akNarrLastTgt && _akNarrLastTgt != _akNarrLastSubj && !_akNarrLastTgt.IsDead() \
       && _akNarrLastTgt != PlayerRef \
       && akAnchor.GetDistance(_akNarrLastTgt) <= 2500.0 \
       && _NarrSubjectPoolAdmits(_akNarrLastTgt, aiSubjectPoolSetting)
        _akNarrSubPool[_iNarrSubPoolN] = _akNarrLastTgt
        _iNarrSubPoolN += 1
    EndIf
    i = 0
    While i < aiPoolN && _iNarrSubPoolN < 5
        Actor akT = _daemonPool[i]
        If akT && akT != akAnchor && _NarrSubjectPoolAdmits(akT, aiSubjectPoolSetting) \
           && akT.GetDialogueTarget() != None && !_NarrSubPoolHas(akT) && !akT.IsDead() \
           && akAnchor.GetDistance(akT) <= 2500.0
            _akNarrSubPool[_iNarrSubPoolN] = akT
            _iNarrSubPoolN += 1
            Actor akP = akT.GetDialogueTarget()
            If akP && akP != akAnchor && akP != PlayerRef && !akP.IsDead() \
               && _iNarrSubPoolN < 5 \
               && akAnchor.GetDistance(akP) <= 2500.0 \
               && _NarrSubjectPoolAdmits(akP, aiSubjectPoolSetting) && !_NarrSubPoolHas(akP)
                _akNarrSubPool[_iNarrSubPoolN] = akP
                _iNarrSubPoolN += 1
            EndIf
        EndIf
        i += 1
    EndWhile
    i = 0
    While i < aiPoolN && _iNarrSubPoolN < 5
        Actor akT = _daemonPool[i]
        If akT && akT != akAnchor && !akT.IsDead() \
           && akAnchor.GetDistance(akT) <= 2500.0 \
           && _NarrSubjectPoolAdmits(akT, aiSubjectPoolSetting) && !_NarrSubPoolHas(akT)
            _akNarrSubPool[_iNarrSubPoolN] = akT
            _iNarrSubPoolN += 1
        EndIf
        i += 1
    EndWhile
    If _iNarrSubPoolN > 0
        Debug.Trace("[SNBaka] narrative subject pool built: n=" + _iNarrSubPoolN + " (sticky+dialogue+proximity) -- REV-178 L4")
    EndIf
EndFunction

; [REV-178 L4] the subjectPool[] JSON (§6.5): name/uuid/sex/state/
; arousalBand/arousalRaw + inflation marker (FHU module, when installed)
; + SA fields under guard. CUM markers OMITTED + debug note -- the cum
; state layer (SNBaka_CumDetectionModule) exposes no read accessor
; in-tree (_WriteCumState is write-only); §6.2: markers absent = omit,
; never an error. Adversarial names ride _JsonEsc.
String Function _NarrSubjectPoolJson()
    String s = ""
    Int i = 0
    While i < _iNarrSubPoolN
        Actor akC = _akNarrSubPool[i]
        If akC
            If i > 0
                s = s + ","
            EndIf
            String sSex = "male"
            If _SexOf(akC) == 1
                sSex = "female"
            EndIf
            Int iTier = _DaemonArousalTier(akC)
            s = s + "{\"name\":\"" + _JsonEsc(akC.GetDisplayName()) + "\"" \
                + ",\"uuid\":" + _UuidJsonLiteralCtx(akC) \
                + ",\"sex\":\"" + sSex + "\"" \
                + ",\"state\":\"" + _JsonEsc(_DaemonLaneStateLine(akC)) + "\"" \
                + ",\"arousalBand\":\"" + _DaemonArousalBandRaw(akC, iTier) + "\""
            Int iRaw = _DaemonArousalRawOf(akC)
            If iRaw >= 0
                s = s + ",\"arousalRaw\":" + iRaw
            EndIf
            If SNBaka_FHUInflationModule.Installed()
                String sInfl = SNBaka_FHUInflationModule.GetDedInflation(akC)
                If sInfl != ""
                    s = s + ",\"inflation\":\"" + _JsonEsc(sInfl) + "\""
                EndIf
            EndIf
            String sSA = _NarrSAFieldsJson(akC)
            If sSA != ""
                s = s + "," + sSA
            EndIf
            s = s + "}"
        EndIf
        i += 1
    EndWhile
    Debug.Trace("[SNBaka] subjectPool composed: cum markers omitted (no in-tree read accessor -- §6.2 omit note) -- REV-178 L4")
    Return s
EndFunction

; [REV-178 L4] numeric arousal (the A17 raw half). -1 = unknown.
Int Function _DaemonArousalRawOf(Actor akC)
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

; [REV-178 L4] the player field (§6.5): TARGET-pool constant only (OR2);
; present when the Baka player-target policy admits the player.
String Function _NarrPlayerField()
    If _PlayerTargetPolicy() != 1
        Return ""
    EndIf
    Return "{\"name\":\"" + _JsonEsc(PlayerRef.GetDisplayName()) + "\"" \
         + ",\"uuid\":" + _UuidJsonLiteralCtx(PlayerRef) + "}"
EndFunction

; [REV-178 L4/V6] the cadence band: read at dispatch; < 30s = "lean".
String Function _NarrCadenceBand(String asMode)
    Float fInt = StorageUtil.GetFloatValue(None, "SNBaka." + asMode + "Cadence", 60.0)
    If fInt < 30.0
        Return "lean"
    EndIf
    Return "full"
EndFunction

; [REV-178 L4] the selection-method word (v23 key; R1 default Narrative).
String Function _NarrSelectionMethodWord(String asMode)
    If StorageUtil.GetIntValue(None, "SNBaka." + asMode + "SelectionMethod", 1) == 1
        Return "narrative"
    EndIf
    Return "random"
EndFunction

; [REV-178 L6/§7.3] SUBJECT resolution + validation: on subject-pool and
; lane-roster union (§7.3.1); Subject Pool filter (§7.3.2); the PLAYER is
; NEVER a valid SUBJECT (OR2 belt). Invalid -> None (caller degrades).
Actor Function _NarrResolveSubject(String asMode, String sName)
    If sName == ""
        Return None
    EndIf
    Int iS = _SelectionSubject(asMode)
    Int i = 0
    While i < _iNarrSubPoolN
        Actor akC = _akNarrSubPool[i]
        If akC && akC.GetDisplayName() == sName
            Return akC
        EndIf
        i += 1
    EndWhile
    Int r = 0
    While r < _iLaneRosterN
        Actor akR = _akLaneRoster[r]
        If akR && akR.GetDisplayName() == sName
            If akR == PlayerRef
                Debug.Trace("[SNBaka] narrative SUBJECT '" + sName + "' = PLAYER -- refused (OR2) -- REV-178 L6")
                Return None
            EndIf
            If !_NarrSubjectPoolAdmits(akR, iS)
                Debug.Trace("[SNBaka] narrative SUBJECT '" + sName + "' fails the Subject Pool filter -- named drop (§7.3.2) -- REV-178 L6")
                Return None
            EndIf
            Return akR
        EndIf
        r += 1
    EndWhile
    ; [REV-178a Leg 2] case-folded rung (exact first above; NOTHING else).
    String sLowS = _AsciiILower(sName)
    i = 0
    While i < _iNarrSubPoolN
        If _akNarrSubPool[i] && _AsciiILower(_akNarrSubPool[i].GetDisplayName()) == sLowS
            Return _akNarrSubPool[i]
        EndIf
        i += 1
    EndWhile
    r = 0
    While r < _iLaneRosterN
        Actor akF = _akLaneRoster[r]
        If akF && _AsciiILower(akF.GetDisplayName()) == sLowS
            If akF == PlayerRef
                Debug.Trace("[SNBaka] narrative SUBJECT '" + sName + "' = PLAYER -- refused (OR2) -- REV-178 L6")
                Return None
            EndIf
            If !_NarrSubjectPoolAdmits(akF, iS)
                Debug.Trace("[SNBaka] narrative SUBJECT '" + sName + "' fails the Subject Pool filter -- named drop (§7.3.2) -- REV-178 L6")
                Return None
            EndIf
            Return akF
        EndIf
        r += 1
    EndWhile
    If _AsciiILower(PlayerRef.GetDisplayName()) == sLowS
        Debug.Trace("[SNBaka] narrative SUBJECT '" + sName + "' = PLAYER -- refused (OR2) -- REV-178 L6")
        Return None
    EndIf
    _i178aSubjectSkips += 1
    Debug.Trace("[SNBaka] unresolvable-subject: '" + sName + "' (skip-tally=" + _i178aSubjectSkips + ") -- degrade to mechanical pick (§7.2) -- REV-178a Leg 2")
    Return None
EndFunction

; [REV-178 L4/§6.5] the composition-level parse receipt (structural lint;
; devkit-side parse receipts at dogfood via request bodies). Mirrors the
; GS _GSJsonLintOK.
Bool Function _JsonLintOK(String asJson, String asComposer)
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
        Debug.Trace("[SNBaka] JSON LINT FAIL (composer " + asComposer + "): braces " + iDepthB + " brackets " + iDepthK + " quotes " + iQuotes + " -- REV-178 L4 parse receipt")
    Else
        Debug.Trace("[SNBaka] JSON lint PASS (composer " + asComposer + ", " + iLen + " chars) -- REV-178 L4 parse receipt")
    EndIf
    Return bOK
EndFunction




; [REV-174a A36c] _LinkWeightPct RETIRED with the slider (kept compiled as a
; 70.0 constant return -- the arousal draw's fixed ratio; no MCM surface).
Float Function _LinkWeightPct()
    Return 70.0
EndFunction

String Function _SubjectSelName(Int aiV)
    If aiV == 1
        Return "Companions Only"
    ElseIf aiV == 2
        Return "Arousal Based"   ; [REV-174a A35] user wording of record
    EndIf
    Return "Random"
EndFunction

String Function _TargetSelName(Int aiV)
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

; The companion pool (§5/2.3): IsPlayerTeammate is the exact check this file
; already uses for followers (the FollowerSlavery gate, formerly L6555) --
; the cited precedent, consumed via the shipped _ExecuteIsCompanion.
Bool Function _SelectionIsCompanion(Actor ak)
    Return _ExecuteIsCompanion(ak)
EndFunction

; Subject Tier A: the candidate is bio-linked (either direction) to ANY other
; standing-pool actor -- the room pool. Tier B = the unlinked strangers.
Bool Function _SelectionSubjectTierA(Actor akCandidate, Int aiN)
    Int j = 0
    While j < aiN
        Actor akOther = _daemonPool[j]
        If akOther && akOther != akCandidate
            If _BioLinkedTo(akCandidate, akOther) || _BioLinkedTo(akOther, akCandidate)
                Return True
            EndIf
        EndIf
        j += 1
    EndWhile
    Return False
EndFunction

; Target Tier A: the pool actor is bio-linked (either direction -- beloveds
; and rivals both) to the SELECTED SUBJECT.
Bool Function _SelectionTargetTierA(Actor akSubject, Actor akCandidate)
    If !akSubject || !akCandidate
        Return False
    EndIf
    Return _BioLinkedTo(akSubject, akCandidate) || _BioLinkedTo(akCandidate, akSubject)
EndFunction

; SUBJECT RESOLUTION (non-Random only): collect the gate-admitted candidates
; (the SAME gates the shipped walk applies -- per-actor cooldown floor +
; aggressor-sex), then the companion filter or the two-tier weighted draw at
; the Link Weight ratio. Empty pool = skip tick + sentinel, never
; fall-through (§15.12).
Actor Function _ResolveSubjectSelection(String asMode, Int aiSel, Int aiN, Float afFloorDays)
    Actor[] akCand = New Actor[64]
    Int[] iTier = New Int[64]
    Int nC = 0
    Int nA = 0
    Int i = 0
    While i < aiN
        Actor akC = _daemonPool[i]
        If akC
            If Utility.GetCurrentGameTime() - StorageUtil.GetFloatValue(akC, "SNBaka.DaemonLast", 0.0) < afFloorDays
                _Log("[SNBaka] daemon floor skip: " + akC.GetDisplayName() + " (per-actor cooldown, mode=" + asMode + ") -- REV-145")
            ElseIf !_AggressorSexAllowed(akC, asMode + ".scan")
                ; aggressor-sex refused (sentinel inside the helper)
            ElseIf aiSel == 1 && !_SelectionIsCompanion(akC)
                ; companions-only filter: ambient strangers never initiate
                ; (the census receipt below names the count, not per-actor noise)
            Else
                ; [REV-174a A35] Arousal Based (subject 2): tier A = arousal
                ; >= 50 (the _DaemonArousalRaw read; the old bio-link tier is
                ; RETIRED -- A36c).
                If aiSel == 2 && _DaemonArousalRaw(akC) >= 50
                    iTier[nC] = 1
                    nA += 1
                Else
                    iTier[nC] = 0
                EndIf
                akCand[nC] = akC
                nC += 1
            EndIf
        EndIf
        i += 1
    EndWhile
    _Log("[SNBaka] selection subject census: mode=" + asMode + " setting=" + _SubjectSelName(aiSel) + " eligible=" + nC + " tierA=" + nA + " -- REV-167 t3")
    If nC == 0
        _Log("[SNBaka] selection refuse: subject pool EMPTY (mode=" + asMode + ", setting=" + _SubjectSelName(aiSel) + ") -- skip tick, never fall through -- REV-167 t3")
        Return None
    EndIf
    Int iPick = Utility.RandomInt(0, nC - 1)
    If aiSel == 2
        ; [REV-174a A35] Arousal Based: 70% of draws from the aroused tier
        ; (fixed ratio -- the slider is retired, A36c); degrades receipted.
        Float w = _LinkWeightPct()
        Bool bWantA = Utility.RandomFloat(0.0, 100.0) <= w
        If bWantA && nA == 0
            bWantA = False
            _Log("[SNBaka] subject draw degrade: tier A EMPTY this tick (no bio-linked candidate) -- falling to tier B, weight=" + w + "% -- REV-167 t3")
        ElseIf !bWantA && nA == nC
            bWantA = True
            _Log("[SNBaka] subject draw degrade: tier B EMPTY this tick (every candidate bio-linked) -- falling to tier A, weight=" + w + "% -- REV-167 t3")
        EndIf
        Int iSteps = 0
        While iSteps < nC && ((bWantA && iTier[iPick] != 1) || (!bWantA && iTier[iPick] != 0))
            iPick = (iPick + 1) % nC
            iSteps += 1
        EndWhile
        String sTier = "B (unlinked stranger)"
        If bWantA
            sTier = "A (bio-linked to someone present)"
        EndIf
        _Log("[SNBaka] subject draw: mode=" + asMode + " tier=" + sTier + " linkweight=" + w + "% -- REV-167 t3")
    EndIf
    _Log("[SNBaka] selection subject drawn: " + akCand[iPick].GetDisplayName() + " (mode=" + asMode + ", setting=" + _SubjectSelName(aiSel) + ") -- REV-167 t3")
    Return akCand[iPick]
EndFunction

; TARGET RESOLUTION (non-Random only): the candidate set = standing pool +
; player + downed pool, each admitting through the SAME gates the shipped
; target legs apply (reach, target-sex level, the central player-target
; policy, the child boundary), then the population filter or the two-tier
; subject-link weighting. Downed members carry their kind so the fire-time
; downed-family subset machinery sees them (REV-146a Task 8 class).
Actor[] _selTargetCand = None
Int[] _selTargetTier = None
Int[] _selTargetKind = None
Int _iSelTargetCount = 0

Int Function _SelTargetAdd(Actor akT, Int aiKind, Int aiTier)
    _selTargetCand[_iSelTargetCount] = akT
    _selTargetKind[_iSelTargetCount] = aiKind
    _selTargetTier[_iSelTargetCount] = aiTier
    _iSelTargetCount += 1
    Return _iSelTargetCount
EndFunction

; [REV-174a A35] aiSel 3/4/5 population filters (Player Only / Companions
; Only / Non-Companion NPCs Only); 1/2 (Bio Led / RP) skip this pass
; (prompt-side); compacts in place and returns the surviving count.
Int Function _SelTargetFilter(Int aiSel)
    Int m = 0
    Int i = 0
    While i < _iSelTargetCount
        Bool bKeep = True
        If aiSel == 3
            bKeep = (_selTargetKind[i] == 2)
        ElseIf aiSel == 4
            bKeep = (_selTargetKind[i] != 2) && _SelectionIsCompanion(_selTargetCand[i])
        ElseIf aiSel == 5
            bKeep = (_selTargetKind[i] != 2) && !_SelectionIsCompanion(_selTargetCand[i])
        EndIf
        If bKeep
            _selTargetCand[m] = _selTargetCand[i]
            _selTargetKind[m] = _selTargetKind[i]
            _selTargetTier[m] = _selTargetTier[i]
            m += 1
        EndIf
        i += 1
    EndWhile
    Return m
EndFunction

; The weighted target draw: compacts to the drawn tier (slot 0 = the pick)
; and returns 1, or -1 for an EMPTY pool. The tier roll and its degradations
; are receipted.
Int Function _SelTargetWeightDraw(String asMode, Int aiNA)
    Float w = _LinkWeightPct()
    Bool bWantA = Utility.RandomFloat(0.0, 100.0) <= w
    If bWantA && aiNA == 0
        bWantA = False
        _Log("[SNBaka] target draw degrade: tier A EMPTY this tick (no bio-linked candidate) -- falling to tier B, weight=" + w + "% -- REV-167 t3")
    ElseIf !bWantA && aiNA == _iSelTargetCount
        bWantA = True
        _Log("[SNBaka] target draw degrade: tier B EMPTY this tick (every candidate bio-linked) -- falling to tier A, weight=" + w + "% -- REV-167 t3")
    EndIf
    Int i = 0
    While i < _iSelTargetCount
        If (bWantA && _selTargetTier[i] == 1) || (!bWantA && _selTargetTier[i] == 0)
            _selTargetCand[0] = _selTargetCand[i]
            _selTargetTier[0] = _selTargetTier[i]
            _selTargetKind[0] = _selTargetKind[i]
            String sTier = "B (unlinked)"
            If bWantA
                sTier = "A (bio-linked to the subject)"
            EndIf
            _Log("[SNBaka] target draw: mode=" + asMode + " tier=" + sTier + " linkweight=" + w + "% -- REV-167 t3")
            Return 1
        EndIf
        i += 1
    EndWhile
    _Log("[SNBaka] selection refuse: target pool EMPTY after the tier draw (mode=" + asMode + ") -- REV-167 t3")
    Return -1
EndFunction

Actor Function _ResolveTargetSelection(String asMode, Int aiSel, Actor akInitiator, Int aiN)
    _selTargetCand = New Actor[128]
    _selTargetTier = New Int[128]
    _selTargetKind = New Int[128]
    _iSelTargetCount = 0
    Int i = 0
    While i < aiN
        Actor akT = _daemonPool[i]
        If akT && akT != akInitiator && akInitiator.GetDistance(akT) <= fNPCInteractionDistance
            If !_TargetSexAllowed(akT)
                _Log("[SNBaka] daemon refuse: target-sex-refused (" + akT.GetDisplayName() + ", level L" + _TargetSexLevel() + ", mode=" + asMode + ") -- REV-145")
            ElseIf !_PlayerTargetAdmitted(akInitiator, akT, asMode + ".scan")
                ; policy-refused (sentinel inside the central gate)
            ElseIf _ChildBoundaryRefused(akInitiator, akT, asMode + ".scan")
                ; child-boundary (sentinel inside the helper)
            Else
                _SelTargetAdd(akT, 0, 0)
            EndIf
        EndIf
        i += 1
    EndWhile
    ; the player (the shipped fallback leg's gates, the same class)
    If akInitiator.GetDistance(PlayerRef) <= fNPCInteractionDistance
        If _TargetSexAllowed(PlayerRef) && _PlayerTargetAdmitted(akInitiator, PlayerRef, asMode + ".scan")
            _SelTargetAdd(PlayerRef, 2, 0)
        EndIf
    EndIf
    ; the downed pool (targets only; the downed-family subset draws at fire)
    If _iDaemonDownedCount > 0
        Int k = 0
        While k < _iDaemonDownedCount
            Actor akD = _daemonDownedPool[k]
            If akD && akD != akInitiator && akInitiator.GetDistance(akD) <= fNPCInteractionDistance
                If !_TargetSexAllowed(akD)
                    _Log("[SNBaka] daemon refuse: target-sex-refused (downed " + akD.GetDisplayName() + ", level L" + _TargetSexLevel() + ", mode=" + asMode + ") -- REV-146a")
                ElseIf !_PlayerTargetAdmitted(akInitiator, akD, asMode + ".downed")
                    ; policy-refused (sentinel inside the central gate)
                ElseIf _ChildBoundaryRefused(akInitiator, akD, asMode + ".downed")
                    ; child-boundary (sentinel inside the helper)
                Else
                    _SelTargetAdd(akD, 1, 0)
                EndIf
            EndIf
            k += 1
        EndWhile
    EndIf
    ; [REV-174a A35/A36] Bio Led (1) and Relationship Priority (2) are
    ; PROMPT-SIDE: NO mechanical filter or weighted draw here (the old
    ; two-tier bio-link draw -- legacy aiSel == 1 -- is RETIRED with the
    ; cold BioNames cache, A36c; the pack's targetSteer field does the
    ; steering). [REV-174a A46] Wide is RETIRED; the cap is the standing 10.
    ; They fall through to the uniform draw below with the full admitted pool.
    _iSelTargetCount = _SelTargetFilter(aiSel)
    _Log("[SNBaka] selection target census: mode=" + asMode + " setting=" + _TargetSelName(aiSel) + " pool=" + _iSelTargetCount + " -- REV-167 t3")
    If _iSelTargetCount == 0
        _Log("[SNBaka] selection refuse: target pool EMPTY (mode=" + asMode + ", setting=" + _TargetSelName(aiSel) + "; Player Only needs NPCs May Target You on) -- skip tick, never fall through -- REV-167 t3")
        Return None
    EndIf
    Int iPick = Utility.RandomInt(0, _iSelTargetCount - 1)
    If _selTargetKind[iPick] == 1
        _Log("[SNBaka] daemon downed-target selected: " + akInitiator.GetDisplayName() + " -> " + _selTargetCand[iPick].GetDisplayName() + " (mode=" + asMode + ", downed-family subset at fire) -- REV-146a")
    EndIf
    String sKind = ""
    If _selTargetKind[iPick] == 2
        sKind = " (the player)"
    EndIf
    _Log("[SNBaka] selection target drawn: " + akInitiator.GetDisplayName() + " -> " + _selTargetCand[iPick].GetDisplayName() + sKind + " (mode=" + asMode + ", setting=" + _TargetSelName(aiSel) + ") -- REV-167 t3")
    Return _selTargetCand[iPick]
EndFunction

; REV-145 3.2/3.4: ONE attempt = scan -> initiator -> target -> select -> fire.
; Every refusal NAMED (toggle/pool-empty/policy-refused/target-sex-refused/
; aggressor-sex-refused/busy/anim-reject). Player-target consults the ONE central
; gate (rev-55a blanket; site codes mephala.scan / molagbal.scan).
Function _DaemonAttempt(Int aiMode)
    String sMode = "Mephala"
    If aiMode == 2
        sMode = "MolagBal"
    EndIf
    Int n = _DaemonScan()
    If n < 2
        _Log("[SNBaka] daemon refuse: pool-empty (n=" + n + ", mode=" + sMode + ") -- REV-145")
        Return
    EndIf
    ; REV-167 t3 2.3 (§5/2.3): the SELECTION-MODE READS. The subject/target
    ; dropdowns are consumed by BOTH Baka modes' DEFAULT paths (Mephala and
    ; targeted Molag, R-1). [REV-174 D1] the Madness bypass is RETIRED with the
    ; toggle (A1/A3); the dropdowns now always steer. Subject value 3 (Bio Led,
    ; MolagBal only this build) routes the Bio Led roster ask below.
    Int iSubSel = 0
    Int iTgtSel = 0
    iSubSel = _SelectionSubject(sMode)
    iTgtSel = _SelectionTarget(sMode)
    ; [REV-174a A46] the Wide roster-cap branch (10 -> 20 for target 3) is
    ; RETIRED with the option -- the cap is the standing 10, set once here.
    _iLaneRosterCap = 10
    _Log("[SNBaka] selection read: mode=" + sMode + " subject=" + iSubSel + " (" + _SubjectSelName(iSubSel) + ") target=" + iTgtSel + " (" + _TargetSelName(iTgtSel) + ") -- REV-174a A35")
    ; [REV-174 D3 LEG 3] The D1 Bio Led branch (MolagBal, subject dropdown
    ; value 3) is SUPERSEDED by the universal two-stage below -- value 3 now
    ; falls through the generic subject resolution (one-lineage supersession;
    ; the _DaemonMolagBioLedAsk family is dead code pending the leg-4
    ; retirement sweep + D4 MCM relabel).
    _Log("[SNBaka] daemon shape: TWO-STAGE (subject + roster consideration, de-randomized) -- REV-174 D3")
    ; initiator: random-walk first-eligible (the GS muse walk pattern); the
    ; walk is the SHIPPED Random path (subject=Random; [REV-174] the Madness
    ; bypass is retired); every other subject setting routes through the
    ; resolution helper.
    Float fFloor = 60.0
    If aiMode == 2
        fFloor = 30.0
    EndIf
    Float fFloorDays = fFloor / (24.0 * 60.0 * 60.0)
    Actor akInitiator = None
    If iSubSel == 0
    Int i = Utility.RandomInt(0, n - 1)
    Int steps = 0
    While steps < n && !akInitiator
        Actor akC = _daemonPool[i]
        If Utility.GetCurrentGameTime() - StorageUtil.GetFloatValue(akC, "SNBaka.DaemonLast", 0.0) < fFloorDays
            _Log("[SNBaka] daemon floor skip: " + akC.GetDisplayName() + " (per-actor cooldown, mode=" + sMode + ") -- REV-145")
        ElseIf !_AggressorSexAllowed(akC, sMode + ".scan")
            ; aggressor-sex refused (sentinel inside the helper); walk continues
        Else
            akInitiator = akC
        EndIf
        If !akInitiator
            i = (i + 1) % n
            steps += 1
        EndIf
    EndWhile
    If !akInitiator
        _Log("[SNBaka] daemon refuse: pool-empty (no initiator past floor/gates, n=" + n + ", mode=" + sMode + ") -- REV-145")
        Return
    EndIf
    Else
        akInitiator = _ResolveSubjectSelection(sMode, iSubSel, n, fFloorDays)
        If !akInitiator
            Return   ; skip tick + sentinel inside the resolver (§15.12)
        EndIf
    EndIf
    ; [REV-174 D3 LEG 3] TWO-STAGE (3.5: BOTH Baka modes): the subject is the
    ; resolved candidate; the TARGET resolves at answer time from the roster
    ; (3.2/3.4). The pre-picked target walks below are DEAD on this path
    ; (leg-4 retirement sweep); the roster re-applies every gate per candidate.
    Int nRoster = _DaemonLaneRosterBuild(akInitiator, n)
    If nRoster <= 0
        _Log("[SNBaka] daemon two-stage refuse: roster EMPTY (subject " + akInitiator.GetDisplayName() + ", mode=" + sMode + ", pool n=" + n + ") -- skip tick, never fall through -- REV-174 D3")
        Return
    EndIf
    _Log("[SNBaka] daemon two-stage roster census: subject=" + akInitiator.GetDisplayName() + " mode=" + sMode + " roster=" + nRoster + " of pool=" + n + " -- REV-174 D3")
    _DaemonTwoStageAsk(sMode, akInitiator, nRoster)
    Return
    ; [REV-174 D3 LEG 4 RETIREMENT 2026-10-30] the pre-picked-pair tail
    ; (target walks + the aiMode==2 _DaemonMolagPick/_DaemonMuseAsk split)
    ; REMOVED -- unreachable since the two-stage early Return above.
    ; Absence proof: rev174d3_leg4_absence.ps1.
EndFunction

; REV-145 3.5: MOLAG-BAL PICK -- random from the FULL pool (ruling (a): all
; actions, no arousal gating, no thoughts, no LLM call).
; REV-146a Task 8 (user ruling: downed follow-up "should happen sometimes"):
; when the selected target is DOWNED, the random draw admits the downed-family
; subset at a SURFACED probability of 35% (the recommended 30-40% band's
; midpoint; surfaced here + in the gate report + baka-daemon.md as-built).
; The remaining 65% draws the normal full pool exactly as before. Receipt
; sentinel carries the surfaced number on every downed-target draw.
Float _fDaemonDownedPct = 0.35   ; REV-146a Task 8: surfaced Molag downed-draw probability
; REV-167 (entry 44, §7.3) ROLL-THEN-CONSIDER pending pair: the dice pre-select
; ONE candidate pair per tick exactly as shipped (_DaemonAttempt, all gates);
; then a SINGLE consideration call contextualizes the pick per fire. The pair
; is held through the async answer (the _bMephalaPending pattern), every gate
; re-verified at fire time; a refused/failed/off-pool answer degrades to the
; shipped dice draw with a named sentinel -- never a silent fall-through (§15.12).
; [REV-174 D1] the pending-pair state now lives with _DaemonMolagPick below
; (Madness member retired with the toggle; Bio Led member added).

; [REV-174 A1] DE-RANDOMIZED DEGRADE: the dice fire is RETIRED (no random
; picks, ruling of record 2026-10-30). Every refuse/off-pool/prompt-miss leg
; is now a NAMED DROP -- skip tick, sentinel, never a random fire. The
; downed-draw probability (_fDaemonDownedPct) is retained above as a record
; of the REV-146a as-built; it has no live consumer under REV-174.
; [REV-174 D3 LEG 4] _DaemonMolagDrop REMOVED -- its named-drop calls all
; lived on the retired lineages; the two-stage answer owns its own drops.

; [REV-174 D3 LEG 4 RETIREMENT 2026-10-30] the Bio Led family REMOVED
; (_DaemonMolagBioLedAsk, _DaemonBioLedPack, _MolagBioNearestTarget,
; _akMolagBioRoster/_iMolagBioRosterN/_iMolagBioPoolN) -- superseded by
; the universal two-stage (subject dropdown value 3 falls through the
; generic subject resolution). Absence proof: rev174d3_leg4_absence.ps1.

; ============================================================================
; [REV-174 D3 LEG 3] TWO-STAGE SELECTION (design doc 3.1/3.2) + REACTION
; LANES (4/6). Supersedes the D1 interim Bio Led roster-ask above (one-lineage,
; pre-release, clean) and the pre-picked-pair asks; the old _DaemonMolagPick /
; _DaemonMolagBioLedAsk / _DaemonMuseAsk paths are dead code pending the leg-4
; retirement sweep (absence proofs there).
; ============================================================================

Int   _iLaneRosterCap  = 10      ; 3.2: named build constant, NOT an MCM surface
                                 ; [REV-174a A46] fixed at 10 (the Wide 20-per-fire
                                 ; inflation retired with the option)
Actor[] _akLaneRoster  = None    ; the in-flight target roster (proximity order)
Int   _iLaneRosterN    = 0
Bool  _bLanePending    = False   ; single-in-flight (the retired REV-145 Mephala-pending pattern's discipline)
Float _fLanePendingStamp = 0.0   ; [REV-178a Leg 7] ask-time stamp (>30s real-time = lost callback -> reclaim)
Int _i178aTargetSkips = 0   ; [REV-178a Leg 2] unresolvable-target skip tally (runbook metric)
Int _i178aSubjectSkips = 0   ; [REV-178a Leg 2] unresolvable-subject skip tally (runbook metric)
Actor _akLaneSubject   = None
String _sLaneMode      = ""
; [REV-174 D3 4.5] REACT pass-through: the unified answer sets these JUST
; before _DaemonDispatchAction so the dispatch-side lane fan-out (which also
; serves the random legs, all-enabled) can arbitrate on the LLM's REACT pick.
String _sLaneReact     = ""
Bool   _bLaneLLM       = False   ; True = this fire carries an LLM REACT pick
String _sLaneDescPass  = ""      ; desc pre-composed by the LLM path (4.5.5)

; [REV-174 D3 / A17] raw arousal read (mirrors _DaemonArousalTier's chain;
; -1 = no framework read). A17: the subject block renders band + RAW VALUE
; side by side -- the band reads fast, the value disambiguates band edges.
Int Function _DaemonArousalRaw(Actor ak)
    Int arousal = -1
    If SKSE.GetPluginVersion("OSLAroused") > 0
        arousal = OSLArousedNative.GetArousalNoSideEffects(ak) as Int
    Else
        slaFrameworkScr kNG = Quest.GetQuest("sla_Framework") as slaFrameworkScr
        If kNG
            arousal = kNG.GetActorArousal(ak)
        EndIf
    EndIf
    Return arousal
EndFunction

; [REV-174 D3 / A17] band word for a tier (1/2/3 -> mild/warm/burning; the
; 3.3 prompt legend words). FACTS ONLY (A17b) -- no disposition steering.
String Function _DaemonArousalBandWord(Int aiTier)
    If aiTier == 3
        Return "burning"
    ElseIf aiTier == 2
        Return "warm"
    EndIf
    Return "mild"
EndFunction

; [REV-174 D3 / A17] the A17 side-by-side subject-arousal render value:
; "warm (band 2), 58". Unknown raw degrades to the bare band form (never a
; silent empty render -- the S199/S200 lesson).
String Function _DaemonArousalBandRaw(Actor ak, Int aiTier)
    Int iRaw = _DaemonArousalRaw(ak)
    If iRaw < 0
        Return _DaemonArousalBandWord(aiTier) + " (band " + aiTier + ")"
    EndIf
    Return _DaemonArousalBandWord(aiTier) + " (band " + aiTier + "), " + iRaw
EndFunction

; [REV-174 D3] relationship-rank gloss to the SUBJECT (3.2: "where the
; existing gloss machinery supplies one" -- GetRelationshipRank is the only
; in-tree gloss source). Register DRAFT (facts-only wording; the user's pen).
; Empty when no meaningful rank.
String Function _DaemonRelGloss(Actor akSubject, Actor akC)
    Int iRank = akC.GetRelationshipRank(akSubject)
    If iRank >= 4
        Return "lover of " + akSubject.GetDisplayName()
    ElseIf iRank == 3
        Return "holds " + akSubject.GetDisplayName() + " dear"
    ElseIf iRank == 2
        Return "a friend of " + akSubject.GetDisplayName()
    ElseIf iRank == 1
        Return "a passing acquaintance of " + akSubject.GetDisplayName()
    EndIf
    Return ""
EndFunction

; [REV-174 D3 / A17] the roster entry STATE line -- one-line facts (arousal
; band + raw per A17's roster-consistency flag, downed, drunk). The roster
; reports; the library constrains (3.2: downed targets stay eligible).
String Function _DaemonLaneStateLine(Actor akC)
    Int iTier = _DaemonArousalTier(akC)
    String s = "arousal " + _DaemonArousalBandRaw(akC, iTier)
    If _IsDownedAny(akC)
        s = s + "; downed"
    EndIf
    If _DaemonIsDrunkTarget(akC)
        s = s + "; drunk"
    EndIf
    Return s
EndFunction

; [REV-174 D3] proximity-ordered insertion into the roster (nearest first --
; the 3.2 narrative frame: "who is within this person's reach").
Function _LaneRosterInsert(Actor akSubject, Actor akC)
    Float fD = akSubject.GetDistance(akC)
    Int k = _iLaneRosterN
    While k > 0 && akSubject.GetDistance(_akLaneRoster[k - 1]) > fD
        _akLaneRoster[k] = _akLaneRoster[k - 1]
        k -= 1
    EndWhile
    _akLaneRoster[k] = akC
    _iLaneRosterN += 1
EndFunction

; [REV-174 D3 3.2] THE TARGET ROSTER: potential targets for THIS subject,
; proximity-to-subject order, cap 10. Gates: target-sex level, central
; player-target policy, child boundary, NPC reach from the SUBJECT; downed
; targets admitted + flagged (the roster reports, the library constrains);
; the subject themself excluded; the player admitted via the central policy
; gates only. Returns the roster count (0 = skip tick, sentinel'd by caller).
Int Function _DaemonLaneRosterBuild(Actor akSubject, Int aiPoolN)
    If !_akLaneRoster || _akLaneRoster.Length < _iLaneRosterCap
        _akLaneRoster = New Actor[20]   ; [REV-174a A46] buffer stays 20; the cap is
                                        ; the standing 10 (Wide retired)
    EndIf
    _iLaneRosterN = 0
    Int i = 0
    While i < aiPoolN && _iLaneRosterN < _iLaneRosterCap
        Actor akT = _daemonPool[i]
        If akT && akT != akSubject && akSubject.GetDistance(akT) <= fNPCInteractionDistance
            If _TargetSexAllowed(akT) && _PlayerTargetAdmitted(akSubject, akT, "lane.roster") && !_ChildBoundaryRefused(akSubject, akT, "lane.roster")
                _LaneRosterInsert(akSubject, akT)
            EndIf
        EndIf
        i += 1
    EndWhile
    Int d = 0
    While d < _iDaemonDownedCount && _iLaneRosterN < _iLaneRosterCap
        Actor akD = _daemonDownedPool[d]
        If akD && akD != akSubject && akSubject.GetDistance(akD) <= fNPCInteractionDistance
            Bool bDup = False
            Int q = 0
            While q < _iLaneRosterN && !bDup
                If _akLaneRoster[q] == akD
                    bDup = True
                EndIf
                q += 1
            EndWhile
            If !bDup && _TargetSexAllowed(akD) && _PlayerTargetAdmitted(akSubject, akD, "lane.roster.downed") && !_ChildBoundaryRefused(akSubject, akD, "lane.roster.downed")
                _LaneRosterInsert(akSubject, akD)
            EndIf
        EndIf
        d += 1
    EndWhile
    If _iLaneRosterN < _iLaneRosterCap
        If _TargetSexAllowed(PlayerRef) && _PlayerTargetAdmitted(akSubject, PlayerRef, "lane.roster") && akSubject.GetDistance(PlayerRef) <= fNPCInteractionDistance
            _LaneRosterInsert(akSubject, PlayerRef)
        EndIf
    EndIf
    Return _iLaneRosterN
EndFunction

; [REV-174 D3] the candidates[] JSON -- one entry per roster slot, keys
; matching the consideration prompts' {{ c.* }} placeholders exactly (the
; A16 pack-template contract: name/sex/uuid/state/relationshipGloss; the
; summary bio renders IN-TEMPLATE from c.uuid via render_character_profile).
String Function _DaemonLaneRosterJson()
    String s = ""
    Int i = 0
    While i < _iLaneRosterN
        Actor akC = _akLaneRoster[i]
        If akC
            If i > 0
                s = s + ","
            EndIf
            String sSex = "male"
            If _SexOf(akC) == 1
                sSex = "female"
            EndIf
            s = s + "{\"name\":\"" + _JsonEsc(akC.GetDisplayName()) + "\",\"sex\":\"" + sSex \
                + "\",\"uuid\":" + _UuidJsonLiteralCtx(akC) \
                + ",\"state\":\"" + _JsonEsc(_DaemonLaneStateLine(akC)) + "\"" \
                + ",\"relationshipGloss\":\"" + _JsonEsc(_DaemonRelGloss(_akLaneSubject, akC)) + "\"}"
        EndIf
        i += 1
    EndWhile
    Return s
EndFunction

; [REV-174 D3 3.1/3.3 / A16/A17] THE TWO-STAGE PACK: subject block (name/
; sex/UUID/band+raw arousal -- A17) + the moment (location/tavern/timeOfDay/
; targetSexLevel/playerTargetPolicy) + candidates[] + actionLibrary. The
; prompt renders the subject's FULL bio and each candidate's SUMMARY bio
; in-template from the UUIDs (Path A). Every field the templates reference is
; supplied here -- the A16 shipped-bytes contract receipt asserts this offline.
; JSON string values are JSON-escaped via _JsonEsc (names/glosses can carry
; quotes); the escape helper is shared with the lane composer below.
String Function _JsonEsc(String asIn)
    String s = _StrReplace(asIn, "\\", "\\\\")
    s = _StrReplace(s, "\"", "\\\"")
    Return s
EndFunction

; manual str-replace (SKSE StringUtil has NO Replace; Find+Substring loop).
String Function _StrReplace(String asIn, String asFind, String asWith)
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

String Function _DaemonTwoStagePack(Actor akSubject, Int aiRosterN, String asMode)
    String sSex = "unknown"
    Int iSex = _SexOf(akSubject)
    If iSex == 0
        sSex = "male"
    ElseIf iSex == 1
        sSex = "female"
    EndIf
    String sLoc = "unknown"
    If PlayerRef.GetCurrentLocation()
        sLoc = PlayerRef.GetCurrentLocation().GetName()
    EndIf
    String sPolicy = "NPCs may not target the player"
    If _PlayerTargetPolicy() == 1
        sPolicy = "NPCs may target the player"
    EndIf
    String sTavern = "no"
    If _DaemonIsTavernClass()
        sTavern = "yes"
    EndIf
    Int iHour = (Utility.GetCurrentGameTime() * 24.0) as Int % 24
    String sTod = "midday"
    If iHour < 5 || iHour >= 21
        sTod = "deep night"
    ElseIf iHour < 8
        sTod = "early morning"
    ElseIf iHour >= 17
        sTod = "evening"
    EndIf
    ; the action library: the mode pool (band-3 full set, premise-steered;
    ; WombHit stays mode-stripped per R-5) + the downed-family subset
    ; appended when ANY roster entry is downed (3.2: the roster reports,
    ; the library constrains).
    String sLib = ""
    String[] pool = _DaemonOptionsPool(asMode, akSubject, 3)
    Int a = 0
    While a < pool.Length
        If a > 0
            sLib = sLib + ", "
        EndIf
        sLib = sLib + pool[a]
        a += 1
    EndWhile
    Bool bAnyDowned = False
    Int r = 0
    While r < aiRosterN && !bAnyDowned
        If _akLaneRoster[r] && _IsDownedAny(_akLaneRoster[r])
            bAnyDowned = True
        EndIf
        r += 1
    EndWhile
    If bAnyDowned
        String[] dpool = _DaemonDownedActionPool()
        Int d2 = 0
        While d2 < dpool.Length
            sLib = sLib + ", " + dpool[d2]
            d2 += 1
        EndWhile
    EndIf
    Int iTier = _DaemonArousalTier(akSubject)
    ; [REV-174a A36] the CONDITIONAL PROMPT SECTION (target-side steering,
    ; DRAFT wording at the user's pen): Bio Led (1) / Relationship Priority
    ; (2) add a targetSteer field to the pack -- facts in, trust the LLM;
    ; the roster itself is NEVER filtered for these (A36a doctrine).
    ; [REV-174a A43/A46 GUARD OF RECORD] targetSteer renders ONLY on the
    ; single-target modes (sel 1/2); with Wide retired no other value can
    ; carry it -- Random and the population filters emit no steer.
    String sSteer = ""
    Int iTgt = _SelectionTarget(asMode)
    If iTgt == 1
        sSteer = "bio-led: read the subject's own Relationships in their bio and favor a target they already know - an existing relationship suits this moment"
    ElseIf iTgt == 2
        sSteer = "relationship-priority: favor someone from the subject's own Relationships, and let WHY steer the pick - a disliked rival suits a hostile act, an intimate friend a warm one"
    EndIf
    ; [REV-178a Leg 1.2, user ruling 2026-11-06] the v23 target space has no
    ; Bio Led/RP values, so the steer fell through EMPTY while the prompt
    ; still guards {{ targetSteer }} -- bind the PLAYER-TARGET RULE SIGN
    ; (mirror of playerTargetPolicy, Mephala-construction; scoped to the rule
    ; sign: it does not and must not resolve relationship naming).
    If sSteer == ""
        sSteer = sPolicy
    EndIf
    String sSteerJson = ""
    If sSteer != ""
        sSteerJson = ",\"targetSteer\":\"" + _JsonEsc(sSteer) + "\""
    EndIf
    ; [REV-174c T2 Leg 1 / dogfood items 12+13] GS-SHAPE PARITY (the tranche-1
    ; first-silent-link differential: the working GS pack vs the never-bound
    ; Baka pack): (a) the LEGACY npc* KEYS return (npcName/npcUUID/npcSex --
    ; the working GS pack carries BOTH vocabularies; if the engine's pack->
    ; context binding is keyed/gated on the legacy vocabulary, this rebinds it)
    ; + maxRecentEvents; (b) SEQUENTIAL ACCUMULATION per REV-167e D.1a -- the
    ; GS 10-27 trace proved single giant Return expressions can drop runtime
    ; pairs (Papyrus temp-overflow class); this builder WAS one giant Return;
    ; (c) DEFENSIVE ESCAPES: actionLibrary is _JsonEsc'd (the action-pool join
    ; is the widest free-text surface -- a runtime quote/backslash anywhere in
    ; it would invalidate the pack JSON and silently drop the whole context,
    ; the exact observed symptom). Roster escapes (name/state/gloss) ride the
    ; candidates[] builder.
    String s = "{\"npcName\":\"" + _JsonEsc(akSubject.GetDisplayName()) \
        + "\",\"npcUUID\":" + _UuidJsonLiteralCtx(akSubject) \
        + ",\"npcSex\":\"" + sSex + "\""
    s = s + ",\"subjectName\":\"" + _JsonEsc(akSubject.GetDisplayName()) \
        + "\",\"subjectSex\":\"" + sSex + "\""
    s = s + ",\"subjectUUID\":" + _UuidJsonLiteralCtx(akSubject)
    s = s + ",\"subjectArousalBand\":\"" + _DaemonArousalBandRaw(akSubject, iTier) + "\""
    s = s + ",\"candidates\":[" + _DaemonLaneRosterJson() + "]"
    s = s + ",\"location\":\"" + _JsonEsc(sLoc) + "\",\"tavern\":\"" + sTavern + "\""
    s = s + ",\"timeOfDay\":\"" + sTod + "\",\"targetSexLevel\":\"" + _TargetSexLevel() + "\""
    s = s + ",\"playerTargetPolicy\":\"" + sPolicy + "\"" + sSteerJson
    s = s + ",\"actionLibrary\":\"" + _JsonEsc(sLib) + "\",\"maxRecentEvents\":12}"
    ; [REV-178 L4] THE §6.5 ADDITIVE GROWTH: subjectPool (sticky-5 +
    ; dialogue-priority + proximity), player (TARGET-pool constant only,
    ; OR2), cadenceBand (V6: read at dispatch), selectionMethod. Existing
    ; fields byte-stable above; the steer stays per A36/A43 (v23 target
    ; space has no Bio Led/RP values, so sSteerJson is empty in practice --
    ; kept for the transition window).
    _NarrSubjectPoolBuild(akSubject, aiRosterN, _SelectionSubject(asMode))
    s = StringUtil.Substring(s, 0, StringUtil.GetLength(s) - 1)   ; drop the closing brace
    s = s + ",\"subjectPool\":[" + _NarrSubjectPoolJson() + "]"
    String sPlayerF = _NarrPlayerField()
    If sPlayerF != ""
        s = s + ",\"player\":" + sPlayerF
    EndIf
    s = s + ",\"cadenceBand\":\"" + _NarrCadenceBand(asMode) + "\""
    s = s + ",\"selectionMethod\":\"" + _NarrSelectionMethodWord(asMode) + "\""
    s = s + "}"
    ; [REV-178 L4/§6.5] the composition-level parse receipt (structural
    ; lint on the FINAL string; devkit-side parse receipts at dogfood).
    _JsonLintOK(s, "_DaemonTwoStagePack")
    Return s
EndFunction

; [REV-174 D3 3.1/3.4] THE ASK: one consideration per tick on the subject +
; roster; the answer's TARGET: resolves the pair at fire time. Callbacks stay
; OnBakaMuseConsideration / OnMolagConsideration (both now share the unified
; two-stage answer path). Returns False on dispatch refusal (named drop
; sentinel, skip tick -- A1 de-randomized, no fallbacks).
Bool Function _DaemonTwoStageAsk(String asMode, Actor akSubject, Int aiRosterN)
    _bLanePending = True
    _fLanePendingStamp = Utility.GetCurrentRealTime()   ; [REV-178a Leg 7]
    _akLaneSubject = akSubject
    _sLaneMode = asMode
    String sPrompt = "snbaka_mephala_consideration"
    String sCb = "OnBakaMuseConsideration"
    If asMode == "MolagBal"
        sPrompt = "snbaka_molagbal_consideration"
        sCb = "OnMolagConsideration"
    EndIf
    String sPack = _DaemonTwoStagePack(akSubject, aiRosterN, asMode)
    Int sent = SkyrimNetApi.SendCustomPromptToLLM(sPrompt, "", sPack, Self as Quest, "SkyrimNet_BakaIntegration", sCb)
    ; [REV-178d Leg 1] ARM-AT-DISPATCH: the cadence slot is consumed HERE,
    ; when an ask actually leaves. A refused dispatch (rc != 1, an API-level
    ; failure, not an answer) arms nothing -- the tick's 5s idle re-arm
    ; retries instead. Refused/empty ANSWERS re-arm normally: the attempt
    ; cost its interval at dispatch (S244 ruling 1.3).
    If sent == 1
        If asMode == "MolagBal"
            _fBakaDaemonNextRT = Utility.GetCurrentRealTime() + StorageUtil.GetFloatValue(None, "SNBaka.MolagBalCadence", 15.0)
        Else
            _fBakaDaemonNextRT = Utility.GetCurrentRealTime() + StorageUtil.GetFloatValue(None, "SNBaka.MephalaCadence", 45.0)
        EndIf
        _Log("[SNBaka] daemon cadence armed at dispatch (" + asMode + ", next in " + (_fBakaDaemonNextRT - Utility.GetCurrentRealTime()) + "s) -- REV-178d Leg 1")
    EndIf
    If sent != 1
        _bLanePending = False
        _akLaneSubject = None
        _sLaneMode = ""
        _iLaneRosterN = 0
        _Log("[SNBaka] daemon two-stage dispatch refused (rc=" + sent + ", " + sPrompt + ") -- named drop, skip tick -- REV-174 D3")
        Return False
    EndIf
    Return True
EndFunction

; [REV-178d Leg 2] BOUNDARY TRUNCATION (S244 Leg 3.1, the _GSTruncateCase
; mirror): overflow cuts at the LAST SENTENCE TERMINATOR (. ! ?) inside the
; window; else the LAST SPACE; only a window with neither (one uninterrupted
; token) falls to the hard cut. Never mid-word. Receipt'd per cut.
String Function _DaemonTruncateCase(String asCase, Int aiMax)
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
    _Log("[SNBaka] CASE boundary truncation: " + StringUtil.GetLength(asCase) + " -> " + StringUtil.GetLength(sOut) + " chars (cut mode " + iCut + "/" + iSpace + ") -- REV-178d Leg 2")
    Return sOut
EndFunction

; ============================================================================
; [REV-174 D3 4.3] THE DESC COMPOSITION ENGINE -- Papyrus pragmatic split
; (design doc 5.2's expected fallback; no DevKit/DeDService native surface on
; this machine -- the native-composition discovery leg stays flagged for the
; DLL session). Verb phrases = desc-sentence-templates.md sec.5a/5b rows
; VERBATIM (the user-edited source of record; fixes + the four per-mode
; variants applied). A missing verb = named content gap sentinel + the
; `<Subject> <action label> <Target>.` degradation for THAT fire only (4.3).
; ============================================================================
String Function _DaemonVerbPhrase(String asAction, String asMode)
    ; per-mode variants first (sec.5b -- one phrase cannot serve all four)
    If asMode == "MolagBal"
        If asAction == "FlirtFace"
            Return "lifted the chin of"
        ElseIf asAction == "FrontHug"
            Return "drew in and held in a hard, owning embrace with"
        ElseIf asAction == "KissLove"
            Return "pressed a claiming kiss onto the lips of"
        EndIf
    ElseIf asMode == "Mephala"
        If asAction == "ForcedKiss"
            Return "stole a kiss that was never offered from"
        EndIf
    EndIf
    ; the base map (sec.5a fixes applied verbatim)
    If asAction == "Flirt"
        Return "let a deliberate flirtation slip toward"
    ElseIf asAction == "FlirtFace"
        Return "leaned in to admire the face of"
    ElseIf asAction == "FlirtBreast"
        Return "let their gaze and fingers drift across the chest of"
    ElseIf asAction == "FlirtPussy"
        Return "brushed a bold hand between the legs of"
    ElseIf asAction == "BackHug"
        Return "came up behind and wrapped both arms around"
    ElseIf asAction == "FrontHug"
        Return "drew into a close, holding embrace with"
    ElseIf asAction == "KissLove"
        Return "pressed a lingering kiss on the lips of"
    ElseIf asAction == "ArmHold"
        Return "took firm hold of the arm of"
    ElseIf asAction == "ShowingOffBody"
        Return "put their body shamelessly on display for"
    ElseIf asAction == "TouchBreasts"
        Return "reached out and cupped the breasts of"
    ElseIf asAction == "SuckBreasts"
        Return "lowered their mouth to the bared chest of"
    ElseIf asAction == "ExaminePrivates"
        Return "made a slow show of examining the bareness of"
    ElseIf asAction == "PlayPrivates"
        Return "toyed freely and openly with the privates of"
    ElseIf asAction == "FondlePussy"
        Return "lasciviously fondled the most private of places on"
    ElseIf asAction == "Spanking"
        Return "dealt a stinging slap to the backside of"
    ElseIf asAction == "DrunkExploit"
        Return "took shameless advantage of the drunken state of"
    ElseIf asAction == "DrugFood"
        Return "slipped something into the cup of"
    ElseIf asAction == "OralOnTarget"
        Return "on their knees, set to giving oral pleasure to"
    ElseIf asAction == "Investigate"
        Return "performed a searching, lingering inspection of"
    ElseIf asAction == "CapturedInspect"
        Return "held in place and inspected every inch of"
    ElseIf asAction == "Strip"
        Return "stripped the clothes from"
    ElseIf asAction == "Struggle"
        Return "groped and grappled bodily with"
    ElseIf asAction == "ChokeHug"
        Return "closed around in a crushing embrace, squeezing the breath out of"
    ElseIf asAction == "ChokeHelpless"
        Return "closed their hands on the helpless throat of"
    ElseIf asAction == "WombHit"
        Return "drove a rough blow into the lower abdomen of"
    ElseIf asAction == "PinHelpless"
        Return "pinned the helpless body of"
    ElseIf asAction == "Subdue"
        Return "broke the resistance of and forced submission from"
    ElseIf asAction == "BackHugMolest"
        Return "came up behind, wrapped close, and roamed the body of"
    ElseIf asAction == "ApplyTattoo"
        Return "inked a fresh tattoo onto the bare skin of"
    ; [REV-174f Leg 4.1 -- NEUTRAL ACTION SET] base-map additions so the neutral
    ; fanned lanes (and any random leg that fires these) compose instead of
    ; degrading. Neutral register; NO daedric allusion (5a/5b class, DRAFT).
    ElseIf asAction == "ForcedKiss"
        Return "kissed without asking, taking it from"
    ElseIf asAction == "SpankTarget"
        Return "landed a hard slap on the backside of"
    ElseIf asAction == "SlapFace"
        Return "cracked an open hand across the face of"
    ElseIf asAction == "BreastSlap"
        Return "slapped the bared breast of"
    ElseIf asAction == "SexSpank"
        Return "dealt a mid-act spank to the backside of"
    ElseIf asAction == "ForcedTattoo"
        Return "held down and inked a tattoo onto the skin of"
    ElseIf asAction == "RemoveTattoos"
        Return "removed the tattoos from the skin of"
    ElseIf asAction == "CommandTattoo"
        Return "directed a fresh marking onto the skin of"
    ElseIf asAction == "TieUp"
        Return "bound the hands of"
    ElseIf asAction == "Untie"
        Return "unbound the hands of"
    ElseIf asAction == "Release"
        Return "released the hold on"
    ElseIf asAction == "HelpUp"
        Return "offered a helping hand to"
    ElseIf asAction == "LapSit"
        Return "settled into the lap of"
    ElseIf asAction == "Capture"
        Return "seized and carried off"
    ElseIf asAction == "SellToSlavery"
        Return "sold the freedom of"
    ElseIf asAction == "EnslaveFollower"
        Return "forced the collar of servitude onto"
    ElseIf asAction == "Execute"
        Return "ended the life of"
    ElseIf asAction == "Escalate"
        Return "took by force the body of"
    ElseIf asAction == "InterruptScene"
        Return "interrupted, stepping in on"
    ElseIf asAction == "CallOff"
        Return "called off the attack on"
    ElseIf asAction == "CreatureEscalate"
        Return "closed in on the helpless body of"
    ElseIf asAction == "StripRestore"
        Return "handed the clothes back to"
    ElseIf asAction == "Express"
        Return "let an unguarded expression slip in front of"
    EndIf
    Return ""   ; the named-gap degradation path (4.3)
EndFunction

; [REV-174 D3 4.3] the composed DESC sentence -- subject name -> semantic
; middle -> target name, per-mode frame sentences (4.3 DRAFT register class;
; names are composed text, NEVER template variables -- R-D8/sec.137). ASCII.
; [REV-178c Leg 3] THE REASONING LINE (Baka mirror of the GS _GSComposeDesc
; rider): the two-stage consideration answer's CASE sentence composes into
; the fire-time cue desc. Desc shape becomes "<S> <phrase> <T> -- <CASE
; sentence> Those nearby see and react to what they've just witnessed."
; (the user's line of record rides verbatim after the CASE; composed shape
; is engine-facing text derived from model output + the user's sentence --
; register DRAFT at the pen). Narrative path ONLY: the neutral Action lane,
; random legs, and mechanical fallbacks call this composer WITHOUT asCase
; (the reasoning line is never fabricated). ASCII " -- " separator by rule.
; Cap of record: 240 chars HARD CUT on the CASE fragment (matches the GS
; composer cap; no ellipsis). Sentinel: one log line per with-case fire (the
; adoption tally metric).
String Function _DaemonComposeDesc(String asMode, Actor akInitiator, Actor akTarget, String asAction, String asCase = "")
    String sS = akInitiator.GetDisplayName()
    String sT = akTarget.GetDisplayName()
    String sPhrase = _DaemonVerbPhrase(asAction, asMode)
    String sBase = ""
    If sPhrase == ""
        _Log("[SNBaka] desc content GAP: no verb phrase for action '" + asAction + "' (" + asMode + ") -- degrading to label form for THIS fire (standing gap list item) -- REV-174 D3 4.3")
        sBase = sS + " " + asAction + " " + sT + "."
    ElseIf asMode == "Action"
        ; [REV-174f Leg 4.1] the NEUTRAL frame -- no daedric allusion, no mode
        ; framing: "<Subject> <verb phrase> <Target>." (5a class, DRAFT).
        sBase = sS + " " + sPhrase + " " + sT + "."
    ElseIf asMode == "MolagBal"
        sBase = sS + " took what this moment offered and " + sPhrase + " " + sT + "."
    ElseIf asMode == "Sanguine"
        sBase = sS + " gave themselves over to the revel and " + sPhrase + " " + sT + "."
    ElseIf asMode == "Sheogorath"
        sBase = sS + ", on a whim, " + sPhrase + " " + sT + "."
    Else
        sBase = sS + " gave in to their secretly held desires and " + sPhrase + " " + sT + "."
    EndIf
    If asCase == ""
        Return sBase
    EndIf
    ; [REV-179 Leg 2] CASE COMPOSE-TIME TOGGLE (ruling of record (c), 178d
    ; dogfood; Baka mirror of the GS GSAnim.CaseInCue gate): SNBaka.CaseInCue,
    ; None-keyed StorageUtil, DEFAULT ON (1). OFF = plain desc everywhere
    ; downstream -- base sentence ONLY (no CASE fragment, no closing sentence,
    ; no per-lane logic); read fresh per fire.
    If StorageUtil.GetIntValue(None, "SNBaka.CaseInCue", 1) != 1
        _Log("[SNBaka] CASE cue append OFF (plain desc, case len=" + StringUtil.GetLength(asCase) + ") -- REV-179 Leg 2")
        Return sBase
    EndIf
    asCase = _DaemonTrimSpaces(asCase)
    ; [REV-178d Leg 2] S244 Leg 3.1 (Baka mirror): boundary truncation --
    ; last sentence terminator, else last space, NEVER mid-word.
    asCase = _DaemonTruncateCase(asCase, 240)
    If StringUtil.GetLength(asCase) > 0
        String c = StringUtil.GetNthChar(asCase, StringUtil.GetLength(asCase) - 1)
        If c != "." && c != "!" && c != "?"
            asCase = asCase + "."
        EndIf
    EndIf
    String sHead = sBase
    If StringUtil.GetLength(sHead) > 0 && StringUtil.GetNthChar(sHead, StringUtil.GetLength(sHead) - 1) == "."
        sHead = StringUtil.Substring(sHead, 0, StringUtil.GetLength(sHead) - 1)
    EndIf
    _Log("[SNBaka] reasoning line appended (case len=" + StringUtil.GetLength(asCase) + ") -- with-CASE desc -- REV-178c Leg 3")
    Return sHead + " -- " + asCase + " Those nearby see and react to what they've just witnessed."
EndFunction

; ============================================================================
; [REV-174 D3 4/6] REACTION LANES + REACT ARBITRATION (the emission pass,
; 4.5 steps 2-5; fire-side, all modes incl. random legs). Lane bitmask:
; 1=narr 2=thought 4=pspeech 8=pthought. All four lanes ON by default (A15).
; ============================================================================

; [REV-174 D3 4.6] the enabled lane set, read FRESH per fire (no caching) --
; Baka modes read the motherboard properties; GS modes read GSAnim.* keys.
Int Function _LaneEnabledSet(String asMode)
    If asMode == "Action"
        ; [REV-174f Leg 4.4] the NEW mode-agnostic keys (SNBaka.Action.Lane_*),
        ; read FRESH per fire. Defaults mirror A15: narr/pspeech/pthought ON,
        ; thought OFF. MCM toggles live on the Baka Interactions page (DRAFT).
        Int m = 0
        If StorageUtil.GetIntValue(None, "SNBaka.Action.Lane_narr", 1) == 1
            m = m + 1
        EndIf
        If StorageUtil.GetIntValue(None, "SNBaka.Action.Lane_thought", 0) == 1
            m = m + 2
        EndIf
        If StorageUtil.GetIntValue(None, "SNBaka.Action.Lane_pspeech", 1) == 1
            m = m + 4
        EndIf
        If StorageUtil.GetIntValue(None, "SNBaka.Action.Lane_pthought", 1) == 1
            m = m + 8
        EndIf
        Return m
    ElseIf asMode == "Mephala"
        Int m = 0
        If bMephalaLaneNarr
            m = m + 1
        EndIf
        If bMephalaLaneThought
            m = m + 2
        EndIf
        If bMephalaLanePSpeech
            m = m + 4
        EndIf
        If bMephalaLanePThought
            m = m + 8
        EndIf
        Return m
    ElseIf asMode == "MolagBal"
        Int m = 0
        If bMolagBalLaneNarr
            m = m + 1
        EndIf
        If bMolagBalLaneThought
            m = m + 2
        EndIf
        If bMolagBalLanePSpeech
            m = m + 4
        EndIf
        If bMolagBalLanePThought
            m = m + 8
        EndIf
        Return m
    ElseIf asMode == "Sanguine" || asMode == "Sheogorath"
        String sPfx = "GSAnim.SanguineLane_"
        If asMode == "Sheogorath"
            sPfx = "GSAnim.SheogorathLane_"
        EndIf
        Int m = 0
        If StorageUtil.GetIntValue(None, sPfx + "narr", 1) == 1
            m = m + 1
        EndIf
        If StorageUtil.GetIntValue(None, sPfx + "thought", 1) == 1
            m = m + 2
        EndIf
        If StorageUtil.GetIntValue(None, sPfx + "pspeech", 1) == 1
            m = m + 4
        EndIf
        If StorageUtil.GetIntValue(None, sPfx + "pthought", 1) == 1
            m = m + 8
        EndIf
        Return m
    EndIf
    Return 1
EndFunction

; [REV-174g A37] per-mode last-fired-lane state for the NO-REPEAT ROTATION
; (the lane BIT last fired per mode: 1=narr 2=thought 4=pspeech 8=pthought;
; 0 = none yet). Script-local member state; rotation never repeats the same
; lane back-to-back within a mode while another lane is enabled.
Int _iLastLaneMephala = 0
Int _iLastLaneMolagBal = 0
Int _iLastLaneSanguine = 0
Int _iLastLaneSheogorath = 0
Int _iLastLaneAction = 0

Int Function _LaneLastGet(String asMode)
    If asMode == "MolagBal"
        Return _iLastLaneMolagBal
    ElseIf asMode == "Sanguine"
        Return _iLastLaneSanguine
    ElseIf asMode == "Sheogorath"
        Return _iLastLaneSheogorath
    ElseIf asMode == "Action"
        Return _iLastLaneAction
    EndIf
    Return _iLastLaneMephala
EndFunction

Function _LaneLastSet(String asMode, Int iLane)
    If asMode == "MolagBal"
        _iLastLaneMolagBal = iLane
    ElseIf asMode == "Sanguine"
        _iLastLaneSanguine = iLane
    ElseIf asMode == "Sheogorath"
        _iLastLaneSheogorath = iLane
    ElseIf asMode == "Action"
        _iLastLaneAction = iLane
    Else
        _iLastLaneMephala = iLane
    EndIf
EndFunction

; [REV-174 D3 6.1] the REACT: field parse -- whitespace-normalized,
; case-insensitive (rev-22 rider), comma/plus separated keywords from the
; A13c four-lane set: narr, pspeech, pthought, thought, all, none.
; Returns the picked lane bitmask (0 = the none pick -- a legitimate pick,
; distinct from -1), or -1 for unparseable/empty/contradictory (fail-open).
; NOTE: Papyrus has no bitwise ops -- the mask is additive with disjoint
; powers of two; Bool params are by-value so the none pick is the 0 return.
Int Function _ReactParseLanes(String asReact)
    If asReact == ""
        Return -1
    EndIf
    String s = _DaemonTrimSpaces(asReact)
    s = _LowerAscii(s)
    s = _StrReplace(s, "+", ",")
    String[] toks = StringUtil.Split(s, ",")
    Int mask = 0
    Bool bAnyTok = False
    Bool bAll = False
    Bool bNone = False
    Int i = 0
    While i < toks.Length
        String t = _DaemonTrimSpaces(toks[i])
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
                Return -1   ; unknown keyword = unparseable -> fail-open (6.2)
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
        Return -1   ; 'none' mixed with lane keywords = contradictory -> fail-open
    EndIf
    Return mask
EndFunction

; ASCII lowercase (Papyrus's StringUtil has no ToLower; letters only).
String Function _LowerAscii(String asIn)
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

; [REV-174f Leg 4.2] THE NEUTRAL FANNED ACTION LANES -- LLM- and player-initiated
; fires ONLY. Daemon/mode-initiated interactions NEVER fan here: the daemon
; dispatch sets SNBaka.DaemonFire around its executor chain and this helper
; no-ops under it, so NO single fire ever double-fans (receipt of record). Uses
; the SAME arbitration/cap machinery via _DaemonLaneFire("Action") with
; abRandomLeg=True (no LLM REACT in the loop on menu/hotkey/LLM fires ->
; all-enabled fan-out, the random-leg rule). Desc = neutral frame composed by
; _DaemonComposeDesc("Action"). Re-entrancy/funnel dedup: same pair inside 2s =
; one fan per fire (executor chains like Spanking -> SpankTarget).
Int _iActFanInit = 0
Int _iActFanTgt = 0
Float _fActFanAt = 0.0

Function _ActionLaneFire(Actor akInitiator, Actor akTarget, String asAction)
    If !akInitiator || !akTarget || akInitiator == akTarget
        Return
    EndIf
    If StorageUtil.GetIntValue(None, "SNBaka.DaemonFire", 0) == 1
        Debug.Trace("[SNBaka] action-lane fan SUPPRESSED (daemon/mode fire -- mode-branded lanes exclusively): " + asAction)
        Return
    EndIf
    Float fNow = Utility.GetCurrentRealTime()
    If _iActFanInit == akInitiator.GetFormID() && _iActFanTgt == akTarget.GetFormID() \
        && (fNow - _fActFanAt) < 2.0
        Debug.Trace("[SNBaka] action-lane fan DEDUP (executor funnel, same fire): " + asAction)
        Return
    EndIf
    _iActFanInit = akInitiator.GetFormID()
    _iActFanTgt = akTarget.GetFormID()
    _fActFanAt = fNow
    String sDesc = _DaemonComposeDesc("Action", akInitiator, akTarget, asAction)
    _Log("[SNBaka] neutral action-lane fan: " + asAction + " (" + akInitiator.GetDisplayName() + " -> " + akTarget.GetDisplayName() + ") -- REV-174f Leg 4")
    _DaemonLaneFire("Action", akInitiator, akTarget, sDesc, "", True)
EndFunction

; [REV-174 D3 4.5/6.2 -> REV-174g -> REV-174i -> REV-174j] THE ARBITRATION +
; FAN-OUT: read the enabled set FRESH; the GENERAL cue fires unconditionally
; first (REV-174g fact-cue floor); then AT MOST ONE fanned lane per fire.
; REV-174i A37-v4 (user ruling 2026-11-01 v4) RESTORES LLM ARBITRATION: with
; the master bReactArbitration toggle ON (MCM "LLM Reaction Arbitration",
; default True) the answer's REACT: field picks the lane (intersected with
; enabled). REV-174j A37-v5 (user ruling 2026-11-01 v5, ONE-FANNED-LANE
; CAP): the pick is trimmed to EXACTLY ONE fanned lane -- general cue + one
; fanned lane MAX, never 3 rendered triggers (non-narr preferred on
; multi-lane picks; a lone narr pick still fires the fanned narr lane); the
; NO-REPEAT rotation of REV-174g is demoted to GUARD + FALLBACK (random
; legs, toggle OFF, invalid/off-enabled picks, and exact-mask repeats of the
; last fire). A single-lane enabled set fires 100% in every mode (no-repeat
; sidestepped -- user edge-case ruling).
; Desc identical across the general cue and the fired lane; events registered
; in the SAME tick (4.5.5).
Function _DaemonLaneFire(String asMode, Actor akInitiator, Actor akTarget, String asDesc, String asReact, Bool abRandomLeg)
    String sPfx = "sdb_mephala_mode_"
    If asMode == "MolagBal"
        sPfx = "sdb_molagbal_mode_"
    ElseIf asMode == "Sanguine"
        sPfx = "gsanim_sanguine_mode_"
    ElseIf asMode == "Sheogorath"
        sPfx = "gsanim_sheogorath_mode_"
    ElseIf asMode == "Action"
        ; [REV-174f Leg 4.3] the NEUTRAL fanned set (no mode branding)
        sPfx = "sdb_baka_action_lane_"
    EndIf
    ; [REV-174g Leg 3, user ruling 2026-11-01 v3 -- FACT-CUE FLOOR] the
    ; GENERAL narration cue: registered UNCONDITIONALLY on every action/mode
    ; fire (outside the REACT mask and every lane toggle, BEFORE the
    ; no-lanes early return below) with the full composed desc. The yaml
    ; (sdb_baka_action_general.yaml: prob 1 / cd 0 / prio 5 / interrupt
    ; false) renders it politely every time -- the narration floor that
    ; survives any arbitration outcome.
    ; [REV-178a Leg 6 -- S238 Leg 0 SUPERSEDE, user ruling 2026-11-06] the
    ; general direct-narration cue now registers AFTER arbitration: a
    ; narr-class lane pick SUPPRESSES the general (sentinel below); a non-narr
    ; pick rides alongside it; all lanes off / none fired = the general alone.
    ; The REV-174g "unconditional floor" is superseded for narr fires only.
    Int iEnabled = _LaneEnabledSet(asMode)
    If iEnabled == 0
        SkyrimNetApi.RegisterEvent("sdb_baka_action_general", asDesc, akInitiator, None)
        _Log("[SNBaka] general cue FIRED ALONE (no lanes enabled): sdb_baka_action_general (" + asMode + ", " + akInitiator.GetDisplayName() + ") -- REV-178a Leg 6")
        _Log("[SNBaka] lane fan-out: NO LANES ENABLED (" + asMode + ") -- desc persists to the GM log + the general cue only -- REV-174 D3 6.2 / REV-174g")
        Return
    EndIf
    ; [REV-174i A37-v4, user ruling 2026-11-01 v4] LLM ARBITRATION RESTORED,
    ; NO-REPEAT DEMOTED TO GUARD: the answer's REACT: field arbitrates again
    ; when the master bReactArbitration toggle is ON (MCM "LLM Reaction
    ; Arbitration", default True) -- the 174g v3 ruling had demoted the pick
    ; to evidence-only after the 174f dogfood showed the model mimicking
    ; rendered pthought cues 53 consecutive fires; the user re-ruled for the
    ; LLM pick. The NO-REPEAT rotation survives as FALLBACK + GUARD:
    ; (a) random legs / toggle OFF / missing/invalid/off-enabled REACT ->
    ; rotation (one lane per action stands, the 174g floor); (b) a pick that
    ; exact-masks the last-fired fire rotates instead (never the same lane
    ; twice in a row while another is enabled); (c) SINGLE-LANE ENABLED SET:
    ; fires 100%, no-repeat SIDESTEPPED, arbitration on or off (the 6.2 rule,
    ; user edge-case ruling 2026-11-01 v4). The general cue above is the
    ; unconditional narration floor. (d) [REV-174j A37-v5, user ruling
    ; 2026-11-01 v5] ONE-FANNED-LANE CAP: the pick is trimmed to EXACTLY ONE
    ; fanned lane -- the general cue already narrates, so narr + one other
    ; (3 rendered triggers) is NOT allowed; non-narr preferred on multi-lane
    ; picks, a lone narr pick still fires the fanned narr lane.
    Int iLastLane = _LaneLastGet(asMode)
    Int iFire = 0
    Int iEnabledCount = 0
    Int vCnt = 1
    While vCnt <= 8
        If (iEnabled / vCnt) % 2 == 1
            iEnabledCount += 1
        EndIf
        vCnt = vCnt * 2
    EndWhile
    If iEnabledCount == 1
        iFire = iEnabled
        _Log("[SNBaka] lane arbitration: exactly ONE lane enabled (" + asMode + ") -- fires 100%, no-repeat SIDESTEPPED -- REV-174i A37")
    ElseIf bReactArbitration && !abRandomLeg
        Int iPicked = _ReactParseLanes(asReact)
        If iPicked == -1
            _Log("[SNBaka] lane arbitration: REACT missing/invalid ('" + asReact + "') -- ROTATION FALLBACK -- REV-174i A37")
        ElseIf iPicked == 0
            _Log("[SNBaka] lane arbitration: REACT none pick -- no lanes fire (hollow-action watch item) -- REV-174i A37")
            SkyrimNetApi.RegisterEvent("sdb_baka_action_general", asDesc, akInitiator, None)
            _Log("[SNBaka] general cue FIRED ALONE (no lane fired): sdb_baka_action_general (" + asMode + ") -- REV-178a Leg 6")
            Return
        Else
            Int vI = 1
            While vI <= 8
                If (iPicked / vI) % 2 == 1 && (iEnabled / vI) % 2 == 1
                    iFire = iFire + vI
                EndIf
                vI = vI * 2
            EndWhile
            If iFire == 0
                _Log("[SNBaka] lane arbitration: intersection EMPTY (picked lanes all disabled) -- ROTATION FALLBACK -- REV-174i A37")
            Else
                ; [REV-174j A37-v5, user ruling 2026-11-01 v5] ONE-FANNED-LANE
                ; CAP: the general cue already narrates unconditionally; the
                ; pick is trimmed to EXACTLY ONE fanned lane (never 3 rendered
                ; triggers). A non-narr lane is preferred when the model names
                ; several; a lone narr pick still fires the fanned narr lane.
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
                    _Log("[SNBaka] lane arbitration: CAP-TRIM (ONE fanned lane only; fire " + iFire + " -> " + iCapped + ") -- REV-174j A37")
                    iFire = iCapped
                EndIf
                If iFire == iLastLane
                    _Log("[SNBaka] lane arbitration: NO-REPEAT guard (pick repeats last fire " + iLastLane + ") -- ROTATION FALLBACK -- REV-174i A37")
                    iFire = 0
                Else
                    _Log("[SNBaka] lane arbitration: REACT '" + asReact + "' picked=" + iPicked + " enabled=" + iEnabled + " -> fire=" + iFire + " -- REV-174i A37")
                EndIf
            EndIf
        EndIf
    ElseIf abRandomLeg
        _Log("[SNBaka] lane arbitration: random leg (no LLM in the loop) -- ROTATION FALLBACK -- REV-174g A37 / REV-174i")
    Else
        _Log("[SNBaka] lane arbitration: LLM arbitration OFF (manual) -- ROTATION FALLBACK -- REV-174g A37 / REV-174i")
    EndIf
    If iFire == 0
        ; [REV-174g A37] the NO-REPEAT ROTATION (fallback master since
        ; REV-174i): the first enabled lane after this mode's last-fired
        ; lane, circular, never the same lane twice in a row while another
        ; is available.
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
            ; single-lane set (or only the last lane enabled) -- the
            ; last-fired lane fires; a single enabled lane fires 100% (the
            ; 6.2 rule, preserved).
            iFire = iLastLane
            _Log("[SNBaka] lane arbitration: rotation collapsed to the last-fired lane (" + asMode + ", single-lane set) -- REV-174g A37")
        EndIf
        If iFire == 0
            iFire = 1   ; belt-and-braces (unreachable: iEnabled != 0 above)
        EndIf
        _Log("[SNBaka] lane arbitration: ONE-LANE ROTATION (REV-174g A37): mode=" + asMode + " enabled=" + iEnabled + " last=" + iLastLane + " -> fire=" + iFire)
    EndIf
    _LaneLastSet(asMode, iFire)
    ; [REV-178a Leg 6] the supersede adjudication (S238 Leg 0): narr-class
    ; pick suppresses the general; non-narr rides alongside.
    If (iFire % 2) == 1
        _Log("[SNBaka] general suppressed -- narr lane (" + asMode + ") -- REV-178a Leg 6")
    Else
        SkyrimNetApi.RegisterEvent("sdb_baka_action_general", asDesc, akInitiator, None)
        _Log("[SNBaka] general cue FIRED alongside non-narr lane: sdb_baka_action_general (" + asMode + ", " + akInitiator.GetDisplayName() + ") -- REV-178a Leg 6")
    EndIf
    ; [REV-174a A38a/A38b] the FIRE RECEIPT: none existed on the REV-174
    ; two-stage path (the old notification did not survive the rebuild --
    ; build-fresh, not gating-surviving-code; audit receipt 2026-10-30: zero
    ; _Notify calls on _DaemonLaneFire/_DaemonLaneAnswer fire legs). Now built
    ; ONCE per fire (not per lane), gated by the GLOBAL Debug Notifications
    ; toggle (Settings page, GSAnim.DebugNotify shared key, DEFAULT OFF).
    String sModeLine = asMode
    If asMode == "MolagBal"
        sModeLine = "Molag Bal"
    ElseIf asMode == "Sheogorath"
        sModeLine = "Sheogorath"
    ElseIf asMode == "Action"
        sModeLine = "Action lane"
    EndIf
    If StorageUtil.GetIntValue(None, "GSAnim.DebugNotify", 0) == 1
        String sFireLine = sModeLine + " Mode - " + akInitiator.GetDisplayName()
        If akTarget
            sFireLine = sFireLine + " -> " + akTarget.GetDisplayName()
        EndIf
        Debug.Notification(sFireLine)
    EndIf
    ; the fan-out -- same tick, desc identical across lanes (4.5.5); exactly
    ; ONE lane per fire (REV-174i LLM arbitration+cap, REV-174g rotation
    ; fallback -- both single-fire by construction)
    Int v = 1
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
            ; [REV-174a D1b] PLAYER-LANE BINDING: pspeech/pthought bind the
            ; PLAYER as the event's target actor (DevKit pairs player-voiced
            ; response types with player-bound events; the prior None binding
            ; left the event NPC-attached and the renderer never surfaced it).
            If v == 4 || v == 8
                SkyrimNetApi.RegisterEvent(sPfx + sLane, asDesc, akInitiator, Game.GetPlayer())
            Else
                SkyrimNetApi.RegisterEvent(sPfx + sLane, asDesc, akInitiator, None)
            EndIf
            _Log("[SNBaka] lane FIRED: " + sPfx + sLane + " (" + asMode + ", " + akInitiator.GetDisplayName() + " -> " + akTarget.GetDisplayName() + ") -- REV-174 D3")
        EndIf
        v = v * 2
    EndWhile
EndFunction

; [REV-174 D3 3.4] THE UNIFIED TWO-STAGE ANSWER PATH -- one lineage serving
; both Baka modes (Mephala/MolagBal) and, via the same contract, the GS
; callbacks pass through their own shims. Seed-time gates re-run at fire
; time (the OnBakaMuseConsideration standard); every refusal a NAMED drop
; (A1 de-randomized -- no dice, no silent fallback).
Function _DaemonLaneAnswer(String response, Int success)
    String sMode = _sLaneMode
    Actor akSubject = _akLaneSubject
    _bLanePending = False
    _akLaneSubject = None
    _sLaneMode = ""
    If success != 1 || response == ""
        _Log("[SNBaka] daemon two-stage answer: prompt-miss success=" + success + " (" + sMode + ") -- named drop, skip tick -- REV-174 D3 3.4")
        _iLaneRosterN = 0
        Return
    EndIf
    If StringUtil.Find(response, "REFUSE:") >= 0
        _Log("[SNBaka] daemon two-stage answer: LLM REFUSE ('" + _MolagParseLine(response, "REFUSE:") + "') -- named drop -- REV-174 D3 3.4")
        _iLaneRosterN = 0
        Return
    EndIf
    If StringUtil.Find(response, "MISS") >= 0
        _Log("[SNBaka] daemon two-stage answer: LLM MISS -- named drop, skip tick -- REV-174 D3 3.4")
        _iLaneRosterN = 0
        Return
    EndIf
    If !akSubject
        _Log("[SNBaka] daemon two-stage answer: subject vanished -- named drop -- REV-174 D3 3.4")
        _iLaneRosterN = 0
        Return
    EndIf
    ; [REV-178 L5/L6] the narrative contract lines: SUBJECT (validated,
    ; may override the mechanical subject when the mode runs Narrative) +
    ; CASE (log-only, R10 phase 1; OR4: missing = accept + sentinel).
    String sSubjNarr = _MolagParseLine(response, "SUBJECT:")
    String sCaseNarr = _MolagParseLine(response, "CASE:")
    If sCaseNarr == ""
        _Log("[SNBaka] narrative answer CASE missing -- pick accepted (OR4 accept+sentinel) -- REV-178 L6")
    Else
        _Log("[SNBaka] narrative CASE: " + sCaseNarr + " -- REV-178")
    EndIf
    If sSubjNarr != "" && _NarrSelectionMethodWord(sMode) == "narrative"
        Actor akNarr = _NarrResolveSubject(sMode, sSubjNarr)
        If akNarr && !akNarr.IsDead() && !akNarr.IsInCombat()
            _Log("[SNBaka] narrative SUBJECT override: '" + sSubjNarr + "' replaces mechanical pick " + akSubject.GetDisplayName() + " -- REV-178 L6")
            akSubject = akNarr
        ElseIf akNarr
            _Log("[SNBaka] narrative SUBJECT '" + sSubjNarr + "' resolved but guard-failed at fire time -- degrading to mechanical pick (§7.2) -- REV-178 L6")
        Else
            _Log("[SNBaka] narrative SUBJECT invalid -- degrading to mechanical pick (§7.2) -- REV-178 L6")
        EndIf
    EndIf
    ; [REV-178 L4] stickiness (§6.1.4): recorded after the pair resolves
    ; below (subject + target) at the fire site.
    ; ---- STAGE 2a: TARGET resolve -- exact-name roster match at fire time
    String sTgt = _MolagParseLine(response, "TARGET:")
    Actor akTarget = None
    Int r = 0
    While r < _iLaneRosterN && !akTarget
        If _akLaneRoster[r] && _akLaneRoster[r].GetDisplayName() == sTgt
            akTarget = _akLaneRoster[r]
        EndIf
        r += 1
    EndWhile
    ; [REV-178a Leg 2] CASE-FOLDED PASS ONLY (user ruling 2026-11-06): exact
    ; first (the loop above), then ONE folded roster re-walk. NOTHING else --
    ; no gloss, no role, no relationship inference script-side, ever.
    If !akTarget && sTgt != ""
        String sLowT = _AsciiILower(sTgt)
        r = 0
        While r < _iLaneRosterN && !akTarget
            If _akLaneRoster[r] && _AsciiILower(_akLaneRoster[r].GetDisplayName()) == sLowT
                akTarget = _akLaneRoster[r]
                _Log("[SNBaka] daemon two-stage answer: TARGET '" + sTgt + "' resolved by CASE-FOLD -> " + akTarget.GetDisplayName() + " -- REV-178a Leg 2")
            EndIf
            r += 1
        EndWhile
    EndIf
    String sTgtRes = "OFF-ROSTER"
    If akTarget
        sTgtRes = akTarget.GetDisplayName()
    EndIf
    _Log("[SNBaka] daemon two-stage answer: TARGET '" + sTgt + "' -> " + sTgtRes + " (roster n=" + _iLaneRosterN + ") -- REV-174 D3 3.4")
    If !akTarget
        ; [REV-178a Leg 2] UNRESOLVABLE = skip-with-receipt (a paired action
        ; cannot fire targetless in these modes; the skip tally is a
        ; first-class runbook metric). NEVER a guess, never silent.
        _i178aTargetSkips += 1
        _Log("[SNBaka] unresolvable-target: '" + sTgt + "' (skip-tally=" + _i178aTargetSkips + ") -- skip, no dice, no gloss -- REV-178a Leg 2")
        _iLaneRosterN = 0
        Return
    EndIf
    _iLaneRosterN = 0
    ; [REV-178 L4] stickiness (§6.1.4): the resolved pair is next tick's
    ; sticky pair (recorded once the pair passes the fire-time gates).
    _NarrStickyRemember(akSubject, akTarget)
    ; ---- fire-time gate re-run (subject level: standard guard set)
    If PlayerRef.IsInCombat()
        _Log("[SNBaka] daemon suspend-player-combat: two-stage pick dropped at fire time (" + sMode + ") -- REV-174 D3")
        Return
    EndIf
    If akSubject.IsDead() || akSubject.IsInCombat() || akTarget.IsDead() || akTarget.IsInCombat()
        _Log("[SNBaka] daemon refuse: busy (combat/death at fire time, " + akSubject.GetDisplayName() + " -> " + akTarget.GetDisplayName() + ") -- REV-174 D3 3.4")
        Return
    EndIf
    If StorageUtil.GetIntValue(akSubject, "SNBaka.Locked", 0) == 1 || StorageUtil.GetIntValue(akTarget, "SNBaka.Locked", 0) == 1
        _Log("[SNBaka] daemon refuse: ongoing-action lock (locked at fire time, " + akSubject.GetDisplayName() + " -> " + akTarget.GetDisplayName() + ") -- REV-174 D3 3.4")
        Return
    EndIf
    If !_TargetSexAllowed(akTarget) || !_PlayerTargetAdmitted(akSubject, akTarget, "twostage." + sMode) || _ChildBoundaryRefused(akSubject, akTarget, "twostage." + sMode)
        _Log("[SNBaka] daemon refuse: gate refused at fire time (" + akSubject.GetDisplayName() + " -> " + akTarget.GetDisplayName() + ", " + sMode + ") -- REV-174 D3 3.4")
        Return
    EndIf
    ; ---- STAGE 2b: ACTION resolve -- exact allowlist (fire-time pool + downed)
    String sAction = _MolagParseLine(response, "ACTION:")
    Int iTierFire = _DaemonArousalTier(akSubject)
    String[] pool = _DaemonOptionsPool(sMode, akSubject, iTierFire)
    Bool bInPool = False
    Int a = 0
    While a < pool.Length && !bInPool
        If pool[a] == sAction
            bInPool = True
        EndIf
        a += 1
    EndWhile
    If !bInPool && _IsDownedAny(akTarget)
        String[] dpool = _DaemonDownedActionPool()
        Int d = 0
        While d < dpool.Length && !bInPool
            If dpool[d] == sAction
                bInPool = True
            EndIf
            d += 1
        EndWhile
    EndIf
    ; [REV-178a Leg 4] ACTION CANONICALIZATION (the 0/11 killer; user ruling
    ; 2026-11-06): exact allowlist first (unchanged above), then ONE
    ; case-folded pass, then a containment rung (the folded answer containing
    ; a folded pool entry of >= 6 chars). Every mapping sentinels
    ; ("ACTION '<answer>' -> <id>"); below both rungs = today's degrade
    ; (named drop). POSE/CLIP untouched -- exact picks still fire exact.
    If !bInPool && sAction != ""
        String sLowA = _AsciiILower(sAction)
        a = 0
        While a < pool.Length && !bInPool
            If _AsciiILower(pool[a]) == sLowA
                _Log("[SNBaka] ACTION '" + sAction + "' -> '" + pool[a] + "' (case-fold) -- REV-178a Leg 4")
                sAction = pool[a]
                bInPool = True
            EndIf
            a += 1
        EndWhile
        If !bInPool
            a = 0
            While a < pool.Length && !bInPool
                String sLowP = _AsciiILower(pool[a])
                If StringUtil.GetLength(sLowP) >= 6 && StringUtil.Find(sLowA, sLowP) >= 0
                    _Log("[SNBaka] ACTION '" + sAction + "' -> '" + pool[a] + "' (fuzzy containment) -- REV-178a Leg 4")
                    sAction = pool[a]
                    bInPool = True
                EndIf
                a += 1
            EndWhile
        EndIf
    EndIf
    ; [REV-178c-hotfix Leg 1, user ruling 2026-11-0X -- the Mephala/Molag
    ; 0-fire killer; S242 Leg 4 verdict] ONE-RUNG DEGRADE below both mapping
    ; rungs: an off-pool paraphrase that no mapping clears degrades to a
    ; POOL-LEGAL random draw (the GS dice-draw precedent, D-5/4.3 family),
    ; sentinel'd -- the fire happens, the LLM narrative intent survives as
    ; the REACT/CASE lines, and the paraphrase ledger stays countable.
    ; EMPTY answers (contract-legal MISS) keep today's named drop.
    If !bInPool && sAction != ""
        Int iDraw = Utility.RandomInt(0, pool.Length - 1)
        _Log("[SNBaka] ACTION '" + sAction + "' -> '" + pool[iDraw] + "' (one-rung degrade, pool draw " + (iDraw + 1) + "/" + pool.Length + ") -- REV-178c-hotfix Leg 1")
        sAction = pool[iDraw]
        bInPool = True
    EndIf
    If !bInPool || sAction == ""
        _Log("[SNBaka] daemon two-stage answer: off-pool action '" + sAction + "' (" + sMode + ", tier re-read=" + iTierFire + ") -- named drop -- REV-174 D3 3.4")
        Return
    EndIf
    ; ---- the fire: dispatch (the dispatch-side fan-out carries the REACT)
    String sReact = _MolagParseLine(response, "REACT:")
    _bLaneLLM = True
    _sLaneReact = sReact
    String sDesc = _DaemonComposeDesc(sMode, akSubject, akTarget, sAction, sCaseNarr) ; [REV-178c Leg 3] with-CASE desc (the reasoning line rides the cue)
    _sLaneDescPass = sDesc   ; composed ONCE, identical across lanes (4.5.5)
    _Log("[SNBaka] daemon two-stage FIRE: " + sAction + " (" + akSubject.GetDisplayName() + " -> " + akTarget.GetDisplayName() + ", " + sMode + ", REACT='" + sReact + "') -- REV-174 D3 3.4")
    _DaemonDispatchAction(akSubject, akTarget, sAction, sMode)
EndFunction

; [REV-174 D3 LEG 4 RETIREMENT 2026-10-30] _DaemonMolagPick + the
; _bMolagPending/_bMolagPendingBioLed/_akMolagInitiator/_akMolagTarget
; pair state REMOVED -- superseded by _DaemonTwoStageAsk/_bLanePending.
; Absence proof: rev174d3_leg4_absence.ps1.

; REV-167 (entry 44, §7.3) the consideration callback. Output contract: the
; action name ALONE (the §7.3 prompt). Armed -> answered -> dispatched (or
; refused with reason) chain sentinel'd end to end; every seed-time gate
; re-verified (the OnBakaMuseConsideration standard), plus the §15.5
; ongoing-action lock leg on BOTH actors (SNBaka.Locked -- the shipped busy
; flag, set on every action path, cleared on every end path).
; [REV-174 D1] line parser for the AGGRESSOR/ACTION contract lines.
String Function _MolagParseLine(String asResp, String asKey)
    Int k = StringUtil.Find(asResp, asKey)
    If k < 0
        Return ""
    EndIf
    String s = StringUtil.Substring(asResp, k + StringUtil.GetLength(asKey))
    Int e = StringUtil.Find(s, "\n")
    If e >= 0
        s = StringUtil.Substring(s, 0, e)
    EndIf
    Return _DaemonTrimSpaces(s)
EndFunction

; [REV-174 D3 LEG 4] _MolagBioNearestTarget REMOVED with the Bio Led family.

Function OnMolagConsideration(String response, Int success)
    ; [REV-174 D3 3.4] the unified two-stage answer router -- the two-stage
    ; ask shares this callback; one lineage, both modes.
    If _bLanePending
        _DaemonLaneAnswer(response, success)
        Return
    EndIf
    ; [REV-174 D3 LEG 4] the pre-picked-pair + Bio Led lineages are RETIRED
    ; (_DaemonMolagPick / _DaemonMolagBioLedAsk removed) -- no ask arms this
    ; callback outside _bLanePending; a stray answer is a NAMED DROP.
    _Log("[SNBaka] daemon MolagBal answer dropped: no pending lineage (stale ask) -- REV-174 D3 leg 4")
EndFunction

; [REV-174 D3 LEG 4 RETIREMENT 2026-10-30] _DaemonMuseAsk REMOVED (the
; pre-picked-pair Mephala ask) -- superseded by _DaemonTwoStageAsk (both
; Baka modes, one lineage). Absence proof: rev174d3_leg4_absence.ps1.

; [REV-174 D3 LEG 4 RETIREMENT 2026-10-30] _DaemonPackContext REMOVED --
; the pre-picked-pair context pack; the two-stage pack is
; _DaemonTwoStagePack (both modes). Only retiring callers remained.
; Absence proof: rev174d3_leg4_absence.ps1.
; REV-167e D.1b: hex -> DECIMAL string math for the 64-bit entity UUID
; (mirror of SkyrimNet_AnimationsGS._UuidDecimal). uuid_mappings.uuid is a
; 64-bit INTEGER and the render contract matches the decimal digits (JSON
; number); Papyrus Int is 32-bit, so pure string arithmetic. Returns "" on
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
            _Log("[SNBaka] actor-context DeDService absent -> [REV-169] tails only -- REV-170")
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
                    _Log("[SNBaka] actor-context uuidForm HIT (" + akActor.GetDisplayName() + ") -- REV-170")
                    Return StringUtil.Substring(sCtx, iS, iE - iS)
                EndIf
            EndIf
        EndIf
        _Log("[SNBaka] actor-context uuidForm MISS -> [REV-169] tail (" + akActor.GetDisplayName() + ") -- REV-170")
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

; REV-145 3.5: the SendCustomPromptToLLM callback (the OnMuseConsideration
; template; guards RE-CHECKED at seed time -- the moment between ask and answer
; can change everything; a failed guard is a dropped pick, never a fire).
; Output contract: "ACTION: <name> | THOUGHT: <one-sentence grounded thought>",
; "REFUSE: <reason>", or "MISS".
Function OnBakaMuseConsideration(String response, Int success)
    ; [REV-174 D3 3.4] the unified two-stage answer router (see OnMolagConsideration)
    If _bLanePending
        _DaemonLaneAnswer(response, success)
        Return
    EndIf
    ; [REV-174 D3 LEG 4] the pre-picked-pair lineage (_DaemonMuseAsk) is
    ; RETIRED -- no ask arms this callback outside _bLanePending; a stray
    ; answer (stale dispatch across a save/reload) is a NAMED DROP.
    _Log("[SNBaka] daemon Mephala answer dropped: no pending lineage (stale ask) -- REV-174 D3 leg 4")
EndFunction

; Leading/trailing space trim (the REV-21 trailing-space lesson; Papyrus has no Trim()).
String Function _DaemonTrimSpaces(String s)
    While StringUtil.GetLength(s) > 0 && StringUtil.GetNthChar(s, 0) == " "
        s = StringUtil.Substring(s, 1, StringUtil.GetLength(s) - 1)
    EndWhile
    While StringUtil.GetLength(s) > 0 && StringUtil.GetNthChar(s, StringUtil.GetLength(s) - 1) == " "
        s = StringUtil.Substring(s, 0, StringUtil.GetLength(s) - 1)
    EndWhile
    Return s
EndFunction

; [REV-174 D3 LEG 4 RETIREMENT 2026-10-30] _DaemonModeNarration REMOVED --
; superseded by the four-lane fan-out (REV-174 D3 4.1/4.5; the narr-lane
; RegisterEvent descs are the composed sentence, yamls sdb_*_mode_narr*).
; The bMephalaModeNarration / bMolagBalModeNarration properties and their
; MCM toggles retired with it (the lane masters + per-lane toggles are the
; live surface). Absence proof: rev174d3_leg4_absence.ps1.

; REV-145 3.2/3.4: THE DISPATCH. Idle-interrupt exit first (class-aware exit ->
; recheck -> the action's own hold machinery, Baka _HoldActorAI order per
; SS161 R.2; the REV-136 2.2 hold acquired at exit-issue), then IsEligible
; recheck, then the per-actor ACTION-START stamp (137f anchor), then the
; executor. Struggle-chain: the ambient seeds the INTENTION (GenerateNPCThought
; names the intent), the actor initiates via Struggle_Execute, the follow-up
; rides the outcome (the existing _DefeatGroundWindow / baka_escalate funnel).
; Drunk/tavern variant: a struggle-class pick becomes DrunkExploit when in a
; tavern-class location OR the target is drunk (planner verbatim).
Function _DaemonDispatchAction(Actor akInitiator, Actor akTarget, String sAction, String asMode)
    If !akInitiator || !akTarget
        Return
    EndIf
    ; [REV-174 D3 4.5] snapshot + CLEAR the lane pass-through state up front:
    ; if any refusal below aborts the fire, the LLM REACT/desc never leaks
    ; into the next (random-leg) fire.
    String sReactPass = _sLaneReact
    Bool bLLMPass = _bLaneLLM
    String sDescPass = _sLaneDescPass
    _sLaneReact = ""
    _bLaneLLM = False
    _sLaneDescPass = ""
    ; [REV-174f Leg 4.2 -- FIRE-PATH GATING] mark this fire DAEMON-side for the
    ; duration: every executor hooked below no-ops its NEUTRAL fan
    ; (_ActionLaneFire) so a daemon/mode fire never double-fans (mode-branded
    ; lanes are the ONLY fan on daemon fires -- receipt of record). Cleared at
    ; every exit of this function.
    StorageUtil.SetIntValue(None, "SNBaka.DaemonFire", 1)
    ; idle-interrupt: seated/marker-held initiators exit first (REV-135/136/137
    ; service via the GS module-neutral globals; the GS presence probe gates).
    Bool bGSPresent = _GSPresent()
    If bGSPresent
        Int iIdle = SkyrimNet_AnimationsGS._IdleClass(akInitiator)
        If iIdle == 1 || iIdle == 2
            _Log("[SNBaka] daemon idle-svc exit: " + akInitiator.GetDisplayName() + " class=" + iIdle + " (interrupt-then-fire, ruling (d)) -- REV-145")
            If !SkyrimNet_AnimationsGS._ExitIdle(akInitiator, iIdle)
                _Log("[SNBaka] daemon refuse: busy (idle exit FAILED, " + akInitiator.GetDisplayName() + " class=" + iIdle + ") -- REV-145")
                StorageUtil.UnsetIntValue(None, "SNBaka.DaemonFire")
                Return
            EndIf
        EndIf
    EndIf
    ; the eligibility recheck (rev-20 revalidation precedent): everything can
    ; have changed between selection and fire
    If !IsEligible(akInitiator, akTarget)
        _Log("[SNBaka] daemon refuse: anim-reject (IsEligible failed at fire, " + akInitiator.GetDisplayName() + " -> " + akTarget.GetDisplayName() + ", action " + sAction + ") -- REV-145")
        StorageUtil.UnsetIntValue(None, "SNBaka.DaemonFire")
        Return
    EndIf
    ; 137f TIMER ANCHOR: the per-actor action clock starts when the ACTION fires
    StorageUtil.SetFloatValue(akInitiator, "SNBaka.DaemonLast", Utility.GetCurrentGameTime())
    ; [REV-174 D3 4.1/4.5] the REV-159 _DaemonModeNarration trigger is
    ; SUPERSEDED by the four-lane fan-out (the narr-lane RegisterEvent DESCs
    ; are the composed sentence; the intro drafts live yaml-side). The call is
    ; retired HERE (dead-code sweep at leg 4). Random legs fan out all-enabled
    ; (no LLM in the loop); the two-stage pass passes its REACT through
    ; _sLaneReact/_bLaneLLM/_sLaneDescPass (single-in-flight, same-tick).
    String sDescF = sDescPass
    If sDescF == ""
        sDescF = _DaemonComposeDesc(asMode, akInitiator, akTarget, sAction)
    EndIf
    _DaemonLaneFire(asMode, akInitiator, akTarget, sDescF, sReactPass, !bLLMPass)
    ; struggle-chain: seed the INTENTION, fire the struggle (or its drunk
    ; variant), the follow-up rides the outcome
    If _DaemonIsStruggleChain(sAction)
        Bool bDrunkVariant = _DaemonIsTavernClass() || _DaemonIsDrunkTarget(akTarget)
        If bDrunkVariant
            _Log("[SNBaka] daemon fire: " + sAction + " -> drunk variant (DrunkExploit; tavern=" + _DaemonIsTavernClass() + " drunk=" + _DaemonIsDrunkTarget(akTarget) + ") -- " + akInitiator.GetDisplayName() + " -> " + akTarget.GetDisplayName() + " -- REV-145")
            DrunkExploit_Execute(akInitiator, akTarget)
        Else
            _Log("[SNBaka] daemon fire: " + sAction + " -> struggle-chain (intention seeded, actor initiates, follow-up rides the outcome) -- " + akInitiator.GetDisplayName() + " -> " + akTarget.GetDisplayName() + " -- REV-145")
            Struggle_Execute(akInitiator, akTarget)
        EndIf
        StorageUtil.UnsetIntValue(None, "SNBaka.DaemonFire")
        Return
    EndIf
    _Log("[SNBaka] daemon fire: " + sAction + " (" + asMode + ") -- " + akInitiator.GetDisplayName() + " -> " + akTarget.GetDisplayName() + " -- REV-145")
    If sAction == "Flirt"
        Flirt_Execute(akInitiator, akTarget)
    ElseIf sAction == "FlirtFace"
        FlirtFace_Execute(akInitiator, akTarget)
    ElseIf sAction == "FlirtBreast"
        FlirtBreast_Execute(akInitiator, akTarget)
    ElseIf sAction == "FlirtPussy"
        FlirtPussy_Execute(akInitiator, akTarget)
    ElseIf sAction == "BackHug"
        BackHug_Execute(akInitiator, akTarget)
    ElseIf sAction == "FrontHug"
        FrontHug_Execute(akInitiator, akTarget)
    ElseIf sAction == "KissLove"
        KissLove_Execute(akInitiator, akTarget)
    ElseIf sAction == "ArmHold"
        ArmHold_Execute(akInitiator, akTarget)
    ElseIf sAction == "ShowingOffBody"
        ShowingOffBody_Execute(akInitiator, akTarget)
    ElseIf sAction == "TouchBreasts"
        TouchBreasts_Execute(akInitiator, akTarget)
    ElseIf sAction == "SuckBreasts"
        SuckBreasts_Execute(akInitiator, akTarget)
    ElseIf sAction == "ExaminePrivates"
        ExaminePrivates_Execute(akInitiator, akTarget)
    ElseIf sAction == "PlayPrivates"
        PlayPrivates_Execute(akInitiator, akTarget)
    ElseIf sAction == "FondlePussy"
        FondlePussy_Execute(akInitiator, akTarget)
    ElseIf sAction == "Spanking"
        Spanking_Execute(akInitiator, akTarget)
    ElseIf sAction == "DrunkExploit"
        DrunkExploit_Execute(akInitiator, akTarget)
    ElseIf sAction == "DrugFood"
        DrugFood_Execute(akInitiator, akTarget)
    ElseIf sAction == "OralOnTarget"
        OralOnTarget_Execute(akInitiator, akTarget)
    ElseIf sAction == "Investigate"
        Investigate_Execute(akInitiator, akTarget)
    ElseIf sAction == "CapturedInspect"
        CapturedInspect_Execute(akInitiator, akTarget)
    ElseIf sAction == "Strip"
        _Strip_Execute(akInitiator, akTarget)
    ElseIf sAction == "ForcedTattoo"
        ; REV-150 4.3: forced-tattoo joins the daemon dispatch (downed-family
        ; subset). The AI-AGGRESSOR lane is gated by the Execute-gate 3-level
        ; consent class (SNBaka.ForcedTattooGateLevel, default 0 = Unlimited;
        ; the player's own downed-menu tile choice 12 is NEVER gated - the
        ; Execute pattern). The "ask" tier of the class is refuse/deferred this
        ; session: the popup needs a DLL confirm-mode surface (JS/CSS-only stop
        ; condition) - surfaced gap, queued to a DLL session.
        If !_ForcedTattooGateCheck(akInitiator, akTarget)
            StorageUtil.UnsetIntValue(None, "SNBaka.DaemonFire")
            Return
        EndIf
        _Log("[SNBaka] daemon fire: ForcedTattoo (downed-family subset) -- " + akInitiator.GetDisplayName() + " -> " + akTarget.GetDisplayName() + " -- REV-150")
        _ForcedTattoo_Execute(akInitiator, akTarget)
    ElseIf sAction == "ApplyTattoo"
        ; REV-146a Task 8: tattoo executor class joins the daemon dispatch
        ; (downed-family subset; the executor is presence-gated on SlaveTats).
        _Log("[SNBaka] daemon fire: ApplyTattoo (downed-family subset) -- " + akInitiator.GetDisplayName() + " -> " + akTarget.GetDisplayName() + " -- REV-146a")
        ApplyTattoo_Execute(akInitiator, akTarget)
    ElseIf sAction == "Struggle"
        If _DaemonIsTavernClass() || _DaemonIsDrunkTarget(akTarget)
            _Log("[SNBaka] daemon fire: Struggle -> drunk variant (DrunkExploit; tavern/drunk) -- " + akInitiator.GetDisplayName() + " -> " + akTarget.GetDisplayName() + " -- REV-145")
            DrunkExploit_Execute(akInitiator, akTarget)
        Else
            Struggle_Execute(akInitiator, akTarget)
        EndIf
    Else
        _Log("[SNBaka] daemon refuse: anim-reject (unknown action '" + sAction + "') -- REV-145")
    EndIf
    StorageUtil.UnsetIntValue(None, "SNBaka.DaemonFire")
EndFunction

; Same technique AcheronIntegration already uses to tell creatures (Draugr, Falmer, Giant, wolves,
; trolls, etc.) apart from humanoid actors: the ActorTypeNPC keyword is on every human/humanoid race,
; not on creature races. Cached like _OStimSceneFaction below — resolved once, reused after. If the
; keyword somehow fails to resolve, fail OPEN (treat as humanoid) so a lookup hiccup can't silently
; disable every human action instead of just skipping the (rarer) creature-exclusion check.
Keyword _kwActorTypeNPC
Bool Function _IsCreatureActor(Actor ak)
    If !ak
        Return False
    EndIf
    ; Race-name match first — Falmer and Draugr are creature-behaving races that Bethesda still tags
    ; with ActorTypeNPC (the same keyword every human uses), so the keyword check below alone
    ; misclassifies them as humanoid. That let them slip through IsEligible into human-only actions
    ; (Struggle, ChokeHug, Escalate, HelpUp, Capture — anything gated by IsEligible or this function
    ; directly) using human Babo animations their skeleton can't actually play. Any actor _CreatureAnimKey
    ; recognizes is unambiguously a creature for our purposes, whatever keyword it happens to carry.
    If _CreatureAnimKey(ak) != ""
        Return True
    EndIf
    If !_kwActorTypeNPC
        _kwActorTypeNPC = Game.GetFormFromFile(0x00013794, "Skyrim.esm") as Keyword
    EndIf
    If !_kwActorTypeNPC
        Return False
    EndIf
    Return !ak.HasKeyword(_kwActorTypeNPC)
EndFunction

; OStim "in a scene" faction = OStimActorCountFaction (OStim.esp 0xECA), resolved at runtime so OStim
; stays optional (no master).  This is membership in an active OStim thread — NOT OStimExcitementFaction
; (that's arousal, lingers outside scenes, and was never assigned since OStim isn't a master).
Faction _ostimFac
Faction Function _OStimSceneFaction()
    If !_ostimFac
        _ostimFac = Game.GetFormFromFile(0x000ECA, "OStim.esp") as Faction
    EndIf
    Return _ostimFac
EndFunction

Bool Function IsInSexAnimation(Actor akActor)
    If SexLabAnimatingFaction && akActor.GetFactionRank(SexLabAnimatingFaction) >= 0
        Return True
    EndIf
    Faction osFac = _OStimSceneFaction()
    If osFac && akActor.GetFactionRank(osFac) >= 0
        Return True
    EndIf
    ; Fallback: neither faction assigned in CK — get SexLab's animating faction via the bridge.
    Faction slf = SkyrimNet_BakaSL.AnimFaction()
    If slf && akActor.GetFactionRank(slf) >= 0
        Return True
    EndIf
    Return False
EndFunction

; ============================================================
; Pending-scene latch (rev-22) — closes the check-to-act race between the
; escalation decision and SexLab's thread reaching AnimationStart (~16s window
; observed 09-17: run 3's Struggle passed IsEligible while run 2's PrismaUI
; wizard was pending; IsInSexAnimation reads False until the thread adds both
; actors to the SexLab faction). The latch marks the pair busy from
; wizard-open/scene-start until _EscalationCleanup confirms the scene has
; ended. All escalation exits (cancel, automatic, wizard paths, hard-cap
; fallthrough, invalid-actor abort) run through _EscalationCleanup, so the
; release cannot be stranded.
; ============================================================
Function _SetSceneLatch(Actor akA1, Actor akA2)
    StorageUtil.SetIntValue(akA1, "SNBaka.PendingScene", 1)
    StorageUtil.SetIntValue(akA2, "SNBaka.PendingScene", 1)
    ; REV-24 1a: registry for the startup sweep — the latch ints persist in the cosave but
    ; the escalation VM thread that owns them does NOT survive a save-load (proven 09-17:
    ; a quit during the pinned 15-min poll left SNBaka.PendingScene stranded on both actors
    ; with no code path left to clear it). Every set is registered here so _SweepStaleSceneLatches
    ; can enumerate and clear stale residue at boot/load. FormList on Self (the quest) persists too.
    StorageUtil.FormListAdd(Self, "SNBaka.LatchReg", akA1, False)
    StorageUtil.FormListAdd(Self, "SNBaka.LatchReg", akA2, False)
    _Log("[SNBaka] scene latch: SET — " + akA1.GetDisplayName() + " <-> " + akA2.GetDisplayName() + " (escalation pending; closes the IsInSexAnimation gap until the thread spins up)")
EndFunction

Function _ClearSceneLatch(Actor akA1, Actor akA2)
    If akA1
        StorageUtil.UnsetIntValue(akA1, "SNBaka.PendingScene")
        StorageUtil.FormListRemove(Self, "SNBaka.LatchReg", akA1)
    EndIf
    If akA2
        StorageUtil.UnsetIntValue(akA2, "SNBaka.PendingScene")
        StorageUtil.FormListRemove(Self, "SNBaka.LatchReg", akA2)
    EndIf
    _Log("[SNBaka] scene latch: RELEASED — " + akA1.GetDisplayName() + " <-> " + akA2.GetDisplayName())
EndFunction

; REV-24 Task 1a (user-approved rev-24 scope): startup sweep of stale scene latches.
; Runs from Setup() — the proven load path for this quest (MCM OnGameReload calls it on
; every single load; OnInit covers the cold boot). At that moment ANY surviving
; SNBaka.PendingScene is definitionally stale: the escalation VM thread that would have
; released it does not survive a save-load (the 09-17 stranding mechanism). Follows the
; clamp-pattern lineage (stamp clamps, session-scope reset): a persisted residue read at
; session scope is cleared with an unconditional SENTINEL, never a silent mutation.
; One deliberate exception: an actor who is LIVE in a sex animation right now is skipped —
; that is a save loaded mid-scene (the thread is gone but the scene is real); the race the
; latch guards still applies until the scene ends, and clearing it would reopen the
; check-to-act window mid-scene. Rare, and self-resolving at the scene's end (the actors
; leave the animating faction and any later load sweeps it).
Function _SweepStaleSceneLatches()
    Int i = StorageUtil.FormListCount(Self, "SNBaka.LatchReg") - 1
    While i >= 0
        Actor ak = StorageUtil.FormListGet(Self, "SNBaka.LatchReg", i) as Actor
        If ak && StorageUtil.GetIntValue(ak, "SNBaka.PendingScene", 0) == 1
            If IsInSexAnimation(ak)
                _Log("[SNBaka] scene latch sweep: KEEP — " + ak.GetDisplayName() + " is live in a sex animation (save loaded mid-scene); latch stays until the scene ends")
            Else
                StorageUtil.UnsetIntValue(ak, "SNBaka.PendingScene")
                _Log("[SNBaka] scene latch sweep: CLEARED stale latch on " + ak.GetDisplayName() + " (escalation thread did not survive the load — residue from a prior session)")
            EndIf
        EndIf
        StorageUtil.FormListRemoveAt(Self, "SNBaka.LatchReg", i)
        i -= 1
    EndWhile
    ; REV-25 Task 1b gap fix (found in the 09-18 log read): the registry only contains latches
    ; SET after rev-24 — a stranded latch from a PRE-rev-24 save (the 09-17 quit-during-pinned-
    ; wait pair) has no registry entry, so the pass above is structurally blind to it (Papyrus
    ; cannot enumerate StorageUtil key owners). Legacy pass: scan loaded actors directly —
    ; the same PO3 scan the GS daemon uses. Same KEEP rule (a live scene is real). Limitation
    ; (accepted): only LOADED actors are reachable at sweep time; an unloaded stranded pair
    ; sweeps on a later load once its cell loads. The 09-18 session printed zero sweep lines
    ; while a pre-registry latch plausibly sat in the save lineage — this pass closes that.
    Actor[] akAll = PO3_SKSEFunctions.GetActorsByProcessingLevel(0)
    Int j = 0
    While j < akAll.Length
        Actor la = akAll[j]
        If la && la != PlayerRef && StorageUtil.GetIntValue(la, "SNBaka.PendingScene", 0) == 1
            If IsInSexAnimation(la)
                _Log("[SNBaka] scene latch sweep: KEEP — " + la.GetDisplayName() + " is live in a sex animation (save loaded mid-scene); latch stays until the scene ends")
            Else
                StorageUtil.UnsetIntValue(la, "SNBaka.PendingScene")
                _Log("[SNBaka] scene latch sweep: CLEARED legacy latch on " + la.GetDisplayName() + " (pre-rev-24 stranding — no registry entry; swept by full scan)")
            EndIf
        EndIf
        j += 1
    EndWhile
EndFunction

Bool Function _IsScenePending(Actor akActor)
    Return akActor && StorageUtil.GetIntValue(akActor, "SNBaka.PendingScene", 0) == 1
EndFunction

; ============================================================
; Actor locking — prevents double-triggering on busy actors
; ============================================================
Bool Function IsActorLocked(Actor akActor)
    Return StorageUtil.GetIntValue(akActor, "SNBaka.Locked", 0) == 1
EndFunction

; True if akA1/akA2 are the exact aggressor+victim pair of a currently-open Baka ground window — i.e.
; the SAME aggressor who owns this victim's window trying a follow-up action (PinHelpless, GropeHelpless,
; etc.) on them. The victim is deliberately kept locked for the whole window (see _UnlockAttackerOnly's
; own comment: "the victim remains locked during the ground window") to stop unrelated third parties
; grabbing them mid-window — but that same lock was silently blocking the window's OWN aggressor from
; ever using those actions on their own victim, since LockBoth refused unconditionally. This carve-out
; only ever matches the specific pair that opened the window, so a third party still gets refused.
Bool Function _IsGroundWindowOwner(Actor akA1, Actor akA2)
    If (StorageUtil.GetFormValue(akA2, "SNBaka.GroundWindowAggressor") as Actor) == akA1
        Return True
    EndIf
    If (StorageUtil.GetFormValue(akA1, "SNBaka.GroundWindowAggressor") as Actor) == akA2
        Return True
    EndIf
    Return False
EndFunction

Bool Function LockBoth(Actor akA1, Actor akA2)
    Bool alreadyLocked = IsActorLocked(akA1) || IsActorLocked(akA2)
    Bool windowOwner    = alreadyLocked && _IsGroundWindowOwner(akA1, akA2)
    If alreadyLocked && !windowOwner
        _Log("[SNBaka] LockBoth: refused — " + akA1 + "/" + akA2 + " already locked (A1=" + IsActorLocked(akA1) + " A2=" + IsActorLocked(akA2) + "), not the ground-window owner pair")
        Return False
    EndIf
    If windowOwner
        _Log("[SNBaka] LockBoth: ground-window-owner carve-out used for " + akA1 + " -> " + akA2)
    EndIf
    StorageUtil.SetIntValue(akA1, "SNBaka.Locked", 1)
    StorageUtil.SetIntValue(akA2, "SNBaka.Locked", 1)
    _bQTEDefeated      = False
    _bAELVictimEscaped = False
    ; Locking onto a DOWNED actor = an interaction with them. Reset _bResetDownWindow so Baka's own
    ; ground window (when it's the one holding them) keeps them down while the aggressor keeps engaging.
    ; Acheron's hold is unaffected by this — it tracks presence independently (_AnyLiveActorNear), not
    ; a Baka interaction timestamp.
    _MarkDownInteractionIfDowned(akA1)
    _MarkDownInteractionIfDowned(akA2)
    ; If we're locking mid-fight (a defeat/escalation while combat is still live), drop the participants
    ; out of combat NOW so the held anim can play — otherwise _ShouldAbort sees the attacker already
    ; IsInCombat and breaks the scene on the very first poll. We use ONLY the Calm spell here (it self-
    ; expires and breaks the instant the actor is actually hit), so there's no permanent aggression flag
    ; to leak and no restore to manage: after this, _ShouldAbort trips only on a genuine hit. Gated on
    ; IsInCombat so every out-of-combat interaction behaves exactly as before.
    If akA1.IsInCombat() || (akA2 && akA2.IsInCombat())
        _CalmForAnim(akA1, akA2)
    EndIf
    Return True
EndFunction

; Calm-spell-only combat drop for an in-combat defeat anim (see LockBoth). No-op without the spell or
; out of combat. Skips the player (controlled by DisablePlayerControls, not calm).
Function _CalmForAnim(Actor akA1, Actor akA2)
    If !SNBakaCalm
        Return
    EndIf
    If akA1 && akA1 != PlayerRef && akA1.IsInCombat()
        akA1.StopCombat()
        SNBakaCalm.Cast(akA1, akA1)
    EndIf
    If akA2 && akA2 != PlayerRef && akA2.IsInCombat()
        akA2.StopCombat()
        SNBakaCalm.Cast(akA2, akA2)
    EndIf
    ; Let StopCombat + Calm settle so the first _ShouldAbort poll doesn't catch a stale combat flag.
    Utility.Wait(0.3)
EndFunction

Function _MarkDownInteractionIfDowned(Actor ak)
    If ak && _IsDownedAny(ak)
        _bResetDownWindow = True
        _Log("[SNBaka] _MarkDownInteractionIfDowned: " + ak + " is downed — _bResetDownWindow=True")
    EndIf
EndFunction

Function UnlockBoth(Actor akA1, Actor akA2)
    StorageUtil.SetIntValue(akA1, "SNBaka.Locked",        0)
    StorageUtil.SetIntValue(akA2, "SNBaka.Locked",        0)
    StorageUtil.SetIntValue(akA1, "SNBaka.StopRequested", 0)
    StorageUtil.SetIntValue(akA2, "SNBaka.StopRequested", 0)
    If akA1 == PlayerRef || akA2 == PlayerRef
        Game.EnablePlayerControls()
    EndIf
    _StartCooldown(akA1)
    ; After an INTERMEDIATE action (grope/choke/pin/fondle/kiss) the victim is still downed — re-prompt
    ; the aggressor with the escalate-or-back-down decision, mirroring Baka's own post-takedown window.
    ; RESOLVING actions (Escalate/Capture/HelpUp/Release/SellToSlavery) clear the down state before they
    ; unlock, so this gate (victim still downed) skips them automatically and won't loop a resolution.
    _CueDecisionIfDowned(akA1, akA2)
EndFunction

; Fire the "escalate / help / release" decision cue when, after an action, the VICTIM is still downed —
; i.e. the aggressor did something that didn't resolve the encounter. Debounced so it can't double-fire
; with _RecoveryPeriod, and it pushes the down window so the victim stays put for the decision. Fires
; regardless of who owns the hold (Baka window or Acheron): this is the IMMEDIATE per-action nudge,
; separate from Acheron's slower ~20s ambient "still down" reminder — the two serve different moments
; (right after an action vs. nothing has happened in a while) and both are wanted.
; abResetWindow: True (default) for a REAL interaction (via UnlockBoth) — the aggressor just acted on
; the victim, so keep them down for the decision. False for a PASSIVE periodic reminder (the
; _DefeatGroundWindow "don't go silent" re-cue) — nobody actually did anything, so this must NOT reset
; the recovery clock, or "nobody's around -> recover after fEscalationWindow" could never fire; only
; the 240s hard cap would ever save a truly abandoned victim. Found this the hard way: the periodic
; re-cue was unconditionally resetting the window every ~15s regardless of presence.
Function _CueDecisionIfDowned(Actor akInitiator, Actor akVictim, Bool abResetWindow = True)
    If !akVictim || !akInitiator || akVictim == akInitiator
        Return
    EndIf
    If !_IsDownedAny(akVictim)
        Return
    EndIf
    Float now = Utility.GetCurrentRealTime()
    If now - _fLastOpportunityRT < 5.0
        _Log("[SNBaka] _CueDecisionIfDowned: skipped — debounced (" + (now - _fLastOpportunityRT) + "s since last, need 5.0s), abResetWindow=" + abResetWindow + " still applied" )
        If abResetWindow
            _bResetDownWindow = True   ; the window-keep-alive effect still applies even when the cue itself is debounced
        EndIf
        Return
    EndIf
    _fLastOpportunityRT = now
    If abResetWindow
        _bResetDownWindow = True   ; keep them down for the decision — Baka's own ground window keys off this
    EndIf
    _Log("[SNBaka] _CueDecisionIfDowned: firing baka_opportunity for " + akInitiator + " -> " + akVictim + " (abResetWindow=" + abResetWindow + ")")
    ; REV-146a Task 11 (finding 16283: the opportunity rendered in the
    ; PLAYER'S conversation; user ruling: the player is NEVER the opportunity
    ; audience -- their manual path is the lesser power). The originator arg
    ; routes through _OpportunityAudience (below): an NPC initiator binds as
    ; before; a PLAYER initiator re-binds to the nearest eligible adult NPC
    ; witness (or the event is refused sentinel'd when none is around --
    ; "take advantage of it" is what the lesser power is for).
    ; Bare fact only (no action list) — this "content" arg is SkyrimNet's own narrator/history line,
    ; separate from whatever the baka_opportunity.yaml trigger renders for the same eventType. The YAML's
    ; content already names Escalate/HelpUp/Release plus the talk/demand framing; repeating it here just
    ; produced two different-looking lines for the same moment (confirmed via a screenshot of doubled text).
    Actor akAudience = _OpportunityAudience(akInitiator, akVictim)
    If akAudience
        SkyrimNetApi.RegisterEvent("baka_opportunity", \
            akVictim.GetDisplayName() + " is still down in front of " + akInitiator.GetDisplayName() + ".", \
            akAudience, akVictim)
    EndIf
EndFunction

; REV-146a Task 11 - the baka_opportunity audience router. D8 conversation-
; binding anatomy of record: the RegisterEvent actor args bind WHICH
; conversations the event renders in, and the trigger yaml's audience field
; (baka_opportunity.yaml: "nearby_npcs") filters WHO responds. Finding 16283's
; render reached the player's conversation because the PLAYER was one of the
; bound args (initiator); the fix binds an NPC conversation instead when the
; initiator is the player. Children are never picked as the witness (Task 2).
Actor Function _OpportunityAudience(Actor akInitiator, Actor akVictim)
    If akInitiator && akInitiator != PlayerRef
        Return akInitiator
    EndIf
    Actor akWitness = None
    Float bestDist = 600.0   ; conversation range (the ~600 = same large-hall class)
    Actor[] akAll = PO3_SKSEFunctions.GetActorsByProcessingLevel(0)
    Int i = 0
    While i < akAll.Length
        Actor ak = akAll[i]
        If ak && ak != PlayerRef && ak != akVictim && !ak.IsDead() && !ak.IsInCombat() \
           && !ak.IsChild() && !IsActorLocked(ak) && !IsInSexAnimation(ak)
            Float d = ak.GetDistance(akVictim)
            If d < bestDist
                akWitness = ak
                bestDist = d
            EndIf
        EndIf
        i += 1
    EndWhile
    If akWitness
        _Log("[SNBaka] opportunity audience routed: player-initiator re-bound to NPC witness " + akWitness.GetDisplayName() + " (player never the opportunity audience) -- REV-146a")
        Return akWitness
    EndIf
    _Log("[SNBaka] opportunity audience REFUSE [no-witness]: player-initiator with no eligible NPC nearby - event suppressed (the lesser power is the player's path) -- REV-146a")
    Return None
EndFunction

Function _StartCooldown(Actor akInitiator = None)
    If akInitiator && akInitiator == PlayerRef
        _bCooldownActive = True
        _fCooldownExpiresAtRT = Utility.GetCurrentRealTime() + fPlayerCooldown
        _ArmRealtimeTimer()
    ElseIf akInitiator
        Float now = Utility.GetCurrentGameTime()
        StorageUtil.SetFloatValue(akInitiator, "SNBaka.LastActionTime", now)
        _fLastNPCActionTime = now
    EndIf
EndFunction

; REV-63: the quest's single real-time update slot is now SHARED between the
; player action-cooldown and the FHU inflation level poll. RegisterForSingleUpdate
; REPLACES a pending timer, so two independent chains on one script would silently
; starve each other (the poll re-arming every 10s would eat a pending cooldown and
; vice versa — a regression risk on the guarded struggle pipeline). Instead both
; call sites go through this multiplexer: it fires OnUpdate soon enough for the
; EARLIEST pending consumer, and OnUpdate re-arms only while something is pending.
; Cooldown logic itself is unchanged (same expiry duration, same _bCooldownActive
; handling); only the timer mechanics differ.
; REV-133c Task 1.2 (ruled, rider 2.5b): the aftermath hold chain is RETIRED
; whole (decl/mux leg/fire leg/_ArmCumAftermathHold + the OnSLAnimationEnd
; listener + the RegisterForModEvent arm + sdb_cum_aftermath.yaml). The
; two-moment structure of record STANDS: application cue at climax + ambient
; at +60s; nothing else fires.
Float _fCooldownExpiresAtRT = 0.0   ; 0 = no cooldown pending
Float _fFHUNextPollRT      = 0.0   ; 0 = poll not running
Float _RT_POLL_INTERVAL    = 10.0  ; FHU level-poll cadence, real seconds
Float _fBakaDaemonNextRT   = 0.0   ; REV-145: 0 = daemon tick not armed (both ambient modes off)
Float _fStripHoldNextRT    = 0.0   ; REV-146a Task 9: strip re-equip block watch (0.5s cadence since REV-162, ruling 4.1-b)
Float _fSTAmbientNextRT    = 0.0   ; REV-159 (dogfood 2.2): SlaveTats ambient exposure pass cadence
Float _ST_AMBIENT_INTERVAL = 30.0  ; REV-159: DECOUPLED from the daemon ticks -- modes off no longer
                                   ; silences the tattoo observation roll (the design fix confirmed at
                                   ; the dogfood: 35% roll + per-actor cooldown unchanged, mode-agnostic)

; REV-159 F-3 (S181 finding): cached presence probes for the GS + Acheron esps.
; The uncached GetFormFromFile sites logged a hard Papyrus error once per
; arm-pass/dispatch/delegate on the absent esp (log noise only; the
; cached-absence pattern applied uniformly). esp load state cannot change
; within a session, so first read wins and is cached in both directions.
Bool _bGSPresentCached      = False
Bool _bGSPresentResolved    = False
Bool _bAcheronPresentCached    = False
Bool _bAcheronPresentResolved  = False

Bool Function _GSPresent()
    If !_bGSPresentResolved
        _bGSPresentCached   = Game.GetFormFromFile(0xD61, "SkyrimNet_AnimationsGS.esp") != None
        _bGSPresentResolved = True
        _Log("[SNBaka] presence probe (cached, REV-159 F-3): SkyrimNet_AnimationsGS.esp present=" + _bGSPresentCached)
    EndIf
    Return _bGSPresentCached
EndFunction

Bool Function _AcheronBridgePresent()
    If !_bAcheronPresentResolved
        _bAcheronPresentCached   = Game.GetFormFromFile(0x800, "SkyrimNet_AcheronIntegration.esp") != None
        _bAcheronPresentResolved = True
        _Log("[SNBaka] presence probe (cached, REV-159 F-3): SkyrimNet_AcheronIntegration.esp present=" + _bAcheronPresentCached)
    EndIf
    Return _bAcheronPresentCached
EndFunction


Function _ArmRealtimeTimer()
    Float now  = Utility.GetCurrentRealTime()
    Float next = 999999.0
    If _bCooldownActive && _fCooldownExpiresAtRT > now && _fCooldownExpiresAtRT < next
        next = _fCooldownExpiresAtRT
    EndIf
    If _fFHUNextPollRT > 0.0 && _fFHUNextPollRT < next
        next = _fFHUNextPollRT
    EndIf
    If _fBakaDaemonNextRT > 0.0 && _fBakaDaemonNextRT < next
        next = _fBakaDaemonNextRT
    EndIf
    If _fSTAmbientNextRT > 0.0 && _fSTAmbientNextRT < next   ; REV-159 (dogfood 2.2)
        next = _fSTAmbientNextRT
    EndIf
    ; REV-146a Task 9: the strip re-equip block watch arms on the multiplexer
    ; whenever a tracked strip queue exists (0.5s cadence since REV-162, ruling
    ; 4.1-b: the engine re-dress window closes before the pop renders -- the
    ; defense wins invisibly).
    If _bStripHoldActive
        If _fStripHoldNextRT <= now + 0.05
            _fStripHoldNextRT = now + 0.5
        EndIf
        If _fStripHoldNextRT < next
            next = _fStripHoldNextRT
        EndIf
    EndIf
    If next < 999998.0
        If next <= now
            RegisterForSingleUpdate(0.1)
        Else
            RegisterForSingleUpdate(next - now)
        EndIf
    EndIf
EndFunction

Event OnUpdate()
    ; REV-63 multiplexed real-time tick: cooldown expiry + FHU level poll.
    Float now = Utility.GetCurrentRealTime()
    If _bCooldownActive && _fCooldownExpiresAtRT > 0.0 && now >= _fCooldownExpiresAtRT
        _bCooldownActive = False
        _fCooldownExpiresAtRT = 0.0
    EndIf
    If _fFHUNextPollRT > 0.0 && now >= _fFHUNextPollRT
        ; REV-96 Task 2: poll body extracted to SNBaka_FHUInflationModule.PollLevels
        ; (behavior-preserving move; this multiplexed tick chain stays on the quest).
        SNBaka_FHUInflationModule.PollLevels(Self)
        _fFHUNextPollRT = now + _RT_POLL_INTERVAL
    EndIf
    ; REV-145 3.1: the Baka ambient daemon tick (Mephala 45s since REV-146a / Molag-Bal 15s cadences,
    ; the GS arbiter pattern; combat-suspend inside the tick, stamp unspent). The tick
    ; re-stamps its own next-fire (the ACTION START anchor is separate -- per-actor
    ; SNBaka.DaemonLast stamps written at FIRE, per 137f generalized at REV-144).
    If _fBakaDaemonNextRT > 0.0 && now >= _fBakaDaemonNextRT
        _DaemonTick()
    EndIf
    ; REV-159 (dogfood 2.2): the DECOUPLED SlaveTats ambient exposure pass. The
    ; roll used to ride _DaemonTick (both modes off = never called = the
    ; observed-cue never fired -- the dogfood finding). Dispatch-side silent
    ; gates (module master + observe keys, player-keyed like the module's own
    ; reads) keep the pass from logging every 30s when observation is off; the
    ; module's internal gates/receipts are unchanged. Sentinel per ruleset 5.
    If _fSTAmbientNextRT > 0.0 && now >= _fSTAmbientNextRT
        _fSTAmbientNextRT = now + _ST_AMBIENT_INTERVAL
        If PlayerRef && StorageUtil.GetIntValue(PlayerRef, "SNBaka.ST.Enabled", 1) == 1 \
           && StorageUtil.GetIntValue(PlayerRef, "SNBaka.ST.Observe", 1) == 1
            SNBaka_SlaveTatsModule.AmbientExposurePass()
        EndIf
    EndIf
    ; REV-146a Task 9: the strip re-equip block watch leg (reverts engine-side
    ; re-equips of tracked queue items while any queue lives; 0.5s cadence
    ; since REV-162, ruling 4.1-b).
    If _bStripHoldActive && _fStripHoldNextRT > 0.0 && now >= _fStripHoldNextRT
        _fStripHoldNextRT = now + 0.5
        _StripHoldWatch()
    EndIf
    _ArmRealtimeTimer()
EndEvent

; REV-63: start/stop the FHU level poll chain (multiplexed, see _ArmRealtimeTimer).
; REV-65: idempotent arming -- called from Setup() (primary) AND the
; OnUpdateGameTime heartbeat (self-heal). REV-64 evidence of record: Setup()
; never executed at save-load (the MCM OnGameReload chain was stale), so the
; poll never armed; the heartbeat demonstrably executes every ~3.3 min. A
; redundant call while a poll is already pending is a no-op.

Function _FHUStartPoll()
    Float nowRT = Utility.GetCurrentRealTime()
    ; Idempotent guard: a VALID pending poll is always within one interval of
    ; now (OnUpdate re-arms to now+interval every tick). A pending time that
    ; is FARTHER out is stale save residue (quest variables persist, but
    ; real time resets every game launch) -- treat as not armed.
    If _fFHUNextPollRT > 0.0 && _fFHUNextPollRT > nowRT && (_fFHUNextPollRT - nowRT) <= _RT_POLL_INTERVAL
        Return  ; already armed, poll pending
    EndIf
    SNBaka_FHUInflationModule.PollLevels(Self, True)   ; seed pass: records current amounts, fires no cue (REV-96 Task 2: body moved to the module; REV-159: abSeedPass keeps the arm-time pass baseline-only while LIVE ticks gained the first-sighting fire)
    _fFHUNextPollRT = nowRT + _RT_POLL_INTERVAL
    _ArmRealtimeTimer()
    _Log("[SNBaka] _FHUStartPoll: level poll armed (" + _RT_POLL_INTERVAL + "s, registered-actors only)")
EndFunction

; REV-159 (dogfood 2.2): start the DECOUPLED SlaveTats ambient exposure cadence.
; Same idempotent/self-heal posture as _FHUStartPoll: called from Setup()
; (primary) and the OnUpdateGameTime heartbeat (self-heal); a stale save
; residue next-time farther out than one interval is treated as not armed
; (real time resets every game launch).
Function _STAmbientStart()
    Float nowRT = Utility.GetCurrentRealTime()
    If _fSTAmbientNextRT > 0.0 && _fSTAmbientNextRT > nowRT && (_fSTAmbientNextRT - nowRT) <= _ST_AMBIENT_INTERVAL
        Return  ; already armed, tick pending
    EndIf
    _fSTAmbientNextRT = nowRT + _ST_AMBIENT_INTERVAL
    _ArmRealtimeTimer()
    _Log("[SNBaka] ST ambient exposure cadence armed (" + _ST_AMBIENT_INTERVAL + "s, decoupled from the daemon modes -- REV-159)")
EndFunction

Function _FHUStopPoll()
    If _fFHUNextPollRT == 0.0
        Return  ; REV-65: idempotent -- not armed, nothing to do (no log spam)
    EndIf
    _fFHUNextPollRT = 0.0
    _Log("[SNBaka] _FHUStopPoll: level poll disarmed")
EndFunction

; Console/MCM safety valve: clears player locks and cooldown when an animation
; gets stuck and leaves the player unable to trigger new actions.
; Usage: CGF "SkyrimNet_BakaIntegration.EmergencyReset" 0
Function EmergencyReset()
    If PlayerRef
        StorageUtil.SetIntValue(PlayerRef, "SNBaka.Locked",        0)
        StorageUtil.SetIntValue(PlayerRef, "SNBaka.StopRequested", 0)
        StorageUtil.SetIntValue(PlayerRef, "SNBaka.OnGround",      0)
    EndIf
    _bCooldownActive      = False
    _bQTEDefeated         = False
    _bEscalateRequested   = False
    _bReleaseRequested    = False
    _bAELStruggleComplete = False
    _bAELVictimEscaped    = False
    _bPlayerIsVictim      = False
    _bDruggedEscalation   = False
    _fLastNPCActionTime   = 0.0
    ; Undo any leftover height-match scaling (e.g. an NPC stuck resized after a bad exit).
    _RestoreAllScaledActors()
    PlayerRef.SetDontMove(False)   ; safety: release any leftover player pin
    UnregisterForAllModEvents()
    RegisterForModEvent("AEL_GameEnd", "OnAELGameEnd")
    Game.EnablePlayerControls()
EndFunction

; Signal any ongoing animation involving akTarget to stop cleanly.
; Safe to call even if the actor is not currently in an animation.
Function RequestStop(Actor akTarget)
    If akTarget
        StorageUtil.SetIntValue(akTarget, "SNBaka.StopRequested", 1)
    EndIf
EndFunction

Bool Function _StopRequested(Actor akA1, Actor akA2)
    Return StorageUtil.GetIntValue(akA1, "SNBaka.StopRequested", 0) == 1 \
        || StorageUtil.GetIntValue(akA2, "SNBaka.StopRequested", 0) == 1
EndFunction

; ============================================================
; Sounds
; ============================================================
Function PlayPanicSound(Actor akTarget)
    If PanicSoundF && akTarget && HasFemaleBody(akTarget)
        PanicSoundF.Play(akTarget)
    EndIf
EndFunction

Function PlaySmackSound(Actor akTarget)
    If SmackSound && akTarget
        SmackSound.Play(akTarget)
    EndIf
EndFunction

; ============================================================
; Animation state tracking / SkyrimNet decorator
; ============================================================
Function RecordAnimation(Actor akActor, String animTag, String partnerName)
    If !akActor
        Return
    EndIf
    StorageUtil.SetStringValue(akActor, "SNBaka.LastAnim",    animTag)
    StorageUtil.SetStringValue(akActor, "SNBaka.LastPartner", partnerName)
EndFunction

; Global — called by SkyrimNet to decorate actor context.
; Must be Global because SkyrimNet calls it by name reflection.
SkyrimNet_BakaIntegration Function GetMain() Global
    Return Game.GetFormFromFile(0x000D62, "SkyrimNet_BakaIntegration.esp") as SkyrimNet_BakaIntegration
EndFunction

String Function GetBakaState(Actor akActor) Global
    If !akActor
        Return "{}"
    EndIf
    Bool   locked   = StorageUtil.GetIntValue(akActor,    "SNBaka.Locked",      0) == 1
    ; Downed = our own defeat OR any external bleedout (Surrender, combat defeat) OR the Acheron bridge
    ; holding them down. The Acheron case is CRUCIAL: when the integration owns the down we clear
    ; SNBaka.OnGround, so without this the decorator would report the held victim as NOT downed and the
    ; LLM would never surface Escalate/HelpUp/etc. This is how the LLM learns a held actor is helpless.
    Bool   downed   = _IsDownedAny(akActor)
    String lastAnim    = StorageUtil.GetStringValue(akActor, "SNBaka.LastAnim",    "")
    String lastPartner = StorageUtil.GetStringValue(akActor, "SNBaka.LastPartner", "")
    String lockedStr   = "false"
    String groundStr   = "false"
    If locked
        lockedStr = "true"
    EndIf
    If downed
        groundStr = "true"
    EndIf
    String json = "{"
    json += "\"in_baka_animation\":"      + lockedStr   + ","
    json += "\"on_ground\":"              + groundStr   + ","
    json += "\"downed_and_vulnerable\":"  + groundStr   + ","
    json += "\"last_baka_animation\":\""  + lastAnim    + "\","
    json += "\"last_baka_partner\":\""    + lastPartner + "\""
    json += "}"
    Return json
EndFunction

; Global — simple bool decorator: is this actor currently in a Baka animation?
; Returns "true" / "false" string for SkyrimNet decorator injection.
String Function IsInBakaAnimation(Actor akActor) Global
    If !akActor
        Return "false"
    EndIf
    If StorageUtil.GetIntValue(akActor, "SNBaka.Locked", 0) == 1
        Return "true"
    EndIf
    Return "false"
EndFunction

; ============================================================
; Resist minigame
;
; Key registration and polling are split:
;   _PollResist  — self-contained wait loop used by PlayPairedLoopAnim
;                  and PlayPairedSimpleAnim. Registers the key, polls,
;                  and cleans up. Returns True if the player escaped.
;
;   PlayPairedSequence inlines its own polling so it can interleave
;   animation stage events between ticks without a nested Wait.
;
; Both paths write to the same _iResistPresses / _bResistActive
; instance variables. OnKeyDown increments _iResistPresses while
; _bResistActive is True.
; ============================================================
; Fired by AEL MakeGame() when the flash minigame ends.
; afNumArg > 0 = player won. _bPlayerIsVictim determines what "player won" means.
Event OnAELGameEnd(string asEventName, string asStringArg, float afNumArg, form akSender)
    Bool playerWon = afNumArg > 0
    If _bPlayerIsVictim
        _bAELVictimEscaped = playerWon
    Else
        _bAELVictimEscaped = !playerWon
    EndIf
    _bAELStruggleComplete = True
    _Log("[SNBaka] OnAELGameEnd: afNumArg=" + afNumArg + " playerIsVictim=" + _bPlayerIsVictim + " victimEscaped=" + _bAELVictimEscaped)
    SPE_Interface.CloseCustomMenu()
EndEvent

; Handles the resist window for one animation segment.
; NPC-NPC (or bResistEnabled off, or AEL not installed): waits out duration.
; Player involved: launches AEL QTE via MakeAnimation, polls until done or duration expires.
;
; akA2 = victim (plays sResistA2), akA1 = aggressor (plays sResistA1).
; Returns True if the victim escaped. Sets _bQTEDefeated = True when attacker wins.
; sHoldA1/sHoldA2 = the anim each actor should be holding during the QTE — re-asserted on a tick so a
; PC-NPC actor can't drift off / stop animating mid-minigame (was the "NPC freezes during PC-NPC" bug).
Bool Function _PollResist(Actor akA1, Actor akA2, Float duration, \
        String sResistA1 = "Babo_DefeatResist_A1_S1", \
        String sResistA2 = "Babo_DefeatResist_A2_S1", \
        String sHoldA1 = "", String sHoldA2 = "")
    Bool a1IsPlayer = (akA1 == PlayerRef)
    Bool a2IsPlayer = (akA2 == PlayerRef)
    If (!a1IsPlayer && !a2IsPlayer) || !bResistEnabled
        Return _HoldAnim(akA1, akA2, sHoldA1, sHoldA2, duration)
    EndIf

    ; Let the animation play for fQTEStartDelay seconds before the QTE overlay appears.
    ; Subtract from duration so total animation time stays constant.
    ; In-combat grapple takedown: fQTEStartDelay exists to give AEL Struggle's OWN overlay time to
    ; open cleanly after the PrismaUI menu closes -- dead weight for the (confirmed live: far more
    ; common) case where AEL isn't installed at all, and directly at odds with "a decisive mid-fight
    ; takedown" reading as fast. Use a much shorter fixed delay for this specific transient mode
    ; instead of the tunable global default, which stays untouched for every other action.
    Float qteStartDelay = fQTEStartDelay
    If _bMidCombatGrappleActive
        qteStartDelay = 0.3
    EndIf
    If qteStartDelay > 0.0
        Float delay = qteStartDelay
        If delay >= duration - 1.0
            delay = duration - 1.0  ; always leave at least 1s for the QTE
        EndIf
        If delay > 0.0
            _Log("[SNBaka] _PollResist: pre-QTE delay " + delay + "s")
            If _HoldAnim(akA1, akA2, sHoldA1, sHoldA2, delay)
                Return False
            EndIf
            duration = duration - delay
        EndIf
    EndIf

    _Log("[SNBaka] _PollResist: starting QTE. A1=" + akA1.GetDisplayName() + " A2=" + akA2.GetDisplayName() + " diff=" + fResistDifficulty + " window=" + duration + "s")
    _bAELStruggleComplete = False
    _bAELVictimEscaped    = False
    _bPlayerIsVictim      = a2IsPlayer
    RegisterForModEvent("AEL_GameEnd", "OnAELGameEnd")

    Bool ael_ok = AELStruggle.MakeGame(fResistDifficulty)
    _Log("[SNBaka] _PollResist: MakeGame returned " + ael_ok)
    If !ael_ok
        _Log("[SNBaka] _PollResist: MakeGame failed — timed wait")
        UnregisterForModEvent("AEL_GameEnd")
        ; No QTE addon installed: _HoldAnim just runs the timed hold. It returns True only if
        ; something ABORTED it (death/combat break/distance/stop-request) -- that's neither a win
        ; nor an escape, so leave _bQTEDefeated alone, same as an interrupted real QTE would. If it
        ; ran the full duration uninterrupted, the attacker held them the whole time -- that's a
        ; genuine defeat and _bQTEDefeated must say so, or every caller's "did the victim actually
        ; get overpowered" check silently stays False forever without the addon installed (the
        ; victim always reads as having resisted, regardless of what actually happened).
        Bool timedAborted = _HoldAnim(akA1, akA2, sHoldA1, sHoldA2, duration)
        If !timedAborted
            _bQTEDefeated = True
        EndIf
        Return False   ; never "escaped" via this fallback -- no real QTE ran, so no win condition
    EndIf

    ; Real-clock elapsed, not a naive tick counter -- see _WaitOrAbort's comment. Confirmed live: this
    ; exact loop logged window=2.2s but ran 9 real seconds under concurrent VM load.
    ;
    ; While the AEL Flash minigame is running, IT owns the pacing -- `duration` (the anim-hold time)
    ; is deliberately NOT the cap here. Confirmed live regression after the real-clock fix: a 4s
    ; window force-closed the still-running minigame mid-game ("QTE stopped abruptly in half of it").
    ; Pre-fix, VM lag stretched the tick-counted window enough that the game always got to finish --
    ; that accident was the only thing making it work. The +30s is purely a hang-safety net for the
    ; case where AEL never fires GameEnd at all.
    Float startRT  = Utility.GetCurrentRealTime()
    Float qteCap   = duration + 30.0
    Float tick     = 0.1
    Float sinceRe  = 0.0
    While (Utility.GetCurrentRealTime() - startRT) < qteCap && !_bAELStruggleComplete && !_ShouldAbort(akA1, akA2)
        Utility.Wait(tick)
        sinceRe += tick
        ; Re-assert the held pose ~every 2s so the actors don't drift off-anim during the QTE.
        If sinceRe >= 2.0
            sinceRe = 0.0
            If sHoldA1 != ""
                Debug.SendAnimationEvent(akA1, sHoldA1)
            EndIf
            If sHoldA2 != ""
                Debug.SendAnimationEvent(akA2, sHoldA2)
            EndIf
        EndIf
    EndWhile
    ; If the Flash QTE is still running (poll timed out), force-close the menu so
    ; the player is not left stuck. Wait briefly in case the close triggers AEL_GameEnd.
    If !_bAELStruggleComplete
        SPE_Interface.CloseCustomMenu()
        Utility.Wait(0.3)
    EndIf
    UnregisterForModEvent("AEL_GameEnd")

    Bool victimEscaped = _bAELStruggleComplete && _bAELVictimEscaped
    _Log("[SNBaka] _PollResist: complete=" + _bAELStruggleComplete + " escaped=" + victimEscaped)
    If _bAELStruggleComplete && !victimEscaped
        _bQTEDefeated = True
    EndIf
    Return victimEscaped
EndFunction

; ============================================================
; Core animation helpers
;
; All-All design:
;   A1 always receives the "M" / "A01" / "A1" role animation (initiator).
;   A2 always receives the "F" / "A02" / "A2" role animation (target).
;   The M/F suffix in Baka's naming is ROLE-based, not sex-based.
;   Any gender combination works for the base animations.
;
;   Anatomically-specific actions (breasts, privates) gate on
;   HasFemaleBody(akA2) inside their Execute functions, NOT here.
;
; Positioning formula (Baka FNIS local-space → world):
;   worldX = refX + (yLocal * Sin(angZ)) + (xLocal * Cos(angZ))
;   worldY = refY + (yLocal * Cos(angZ)) - (xLocal * Sin(angZ))
;   a1AngZ = angZ + rotOffset  (0 = same dir as A2, 180 = facing A2)
; ============================================================

; Returns True if the animation should be cut short.
Bool Function _ShouldAbort(Actor akA1, Actor akA2)
    ; NO per-tick protection re-assert here anymore — under the park design the victim is either
    ; Acheron-DEFEATED (native protection, nothing to re-assert) or keep-pacified, and the sweep +
    ; pacify + traces every poll measurably clogged the starved Nolvus Papyrus VM (confirmed report:
    ; "many seconds between the teleport and the struggle beginning"). Protection is applied once at
    ; each transition (_SetupPair / scene start); that's where it belongs now.
    ; A2 entering combat is expected (victim wants to fight back) — do not abort for that.
    ; Only abort if either actor dies/disabled, attacker enters combat,
    ; actors are too far apart (cell leave / teleport), or stop requested.
    If akA1.IsDead() || akA2.IsDead()
        _Log("[SNBaka] _ShouldAbort: dead actor — breaking scene")
        Return True
    EndIf
    If akA1.IsDisabled() || akA2.IsDisabled()
        _Log("[SNBaka] _ShouldAbort: disabled actor — breaking scene")
        Return True
    EndIf
    If akA1.IsInCombat()
        ; Combat state alone is NOT enough to break the animation anymore -- confirmed from testing:
        ; a faction ally attacking the pair's own victim (second falmer vs the player mid-struggle)
        ; flips the pacified aggressor's IsInCombat via the faction alarm, which aborted every struggle
        ; ~3s in, three times in one session, without anything ever touching the aggressor itself.
        ; Only a live fight against someone OTHER than this pair's own victim counts -- that's what a
        ; real hit on the aggressor produces (its combat target switches to whoever hit it), which
        ; preserves the "a hit to the aggressor stops the aggression" rule this check exists for.
        Actor a1t = akA1.GetCombatTarget()
        If a1t && a1t != akA2 && !a1t.IsDead() && !a1t.IsDisabled() && !_IsDownedAny(a1t)
            _Log("[SNBaka] _ShouldAbort: " + akA1.GetDisplayName() + " in combat against " + a1t.GetDisplayName() + " — breaking scene")
            Return True
        EndIf
        ; else: alarm-only combat state (target is the pair's own victim, downed, dead, or nobody) —
        ; not an interruption, the struggle continues.
    EndIf
    If akA1.GetDistance(akA2) > 1500.0
        _Log("[SNBaka] _ShouldAbort: actors too far apart — breaking scene")
        Return True
    EndIf
    ; In-combat grapple takedown: the player is deliberately NOT ghosted for this mode (see
    ; _SetupPair), so a third party's hit actually lands -- abort the instant it does. Can't reuse
    ; the akA1.GetCombatTarget() check above for this: the player doesn't run AI combat packages the
    ; way an NPC does, so GetCombatTarget() isn't a reliable "who's fighting the player" signal
    ; (confirmed elsewhere in this file, see OnCreatureHitFollower's own aggressor-resolution
    ; comments) -- the native hit-event timestamp is the real signal here.
    If _bMidCombatGrappleActive && _fLastPlayerHitRT > _fMidCombatHitBaselineRT
        _Log("[SNBaka] _ShouldAbort: player was hit mid-grapple — breaking scene")
        Return True
    EndIf
    Return _StopRequested(akA1, akA2)
EndFunction

; Waits duration seconds in tick-sized steps.
; Returns True if aborted early due to combat or death.
; Measures against the REAL clock, not a naive tick counter -- confirmed live (Subdue QTE log,
; window=2.2s actually ran 9 real seconds): under heavy concurrent Papyrus VM load (this modlist's
; SkyrimNet eligibility-check spam alone logged dozens of calls during one QTE), a single
; Utility.Wait(tick) routinely takes several times longer than its nominal tick value in real time.
; Counting "elapsed += tick" assumes each Wait call actually took `tick` seconds, so every caller's
; requested duration silently balloons under load. GetCurrentRealTime() makes the loop exit at the
; REAL time the caller asked for regardless of how throttled each individual Wait call was.
Bool Function _WaitOrAbort(Actor akA1, Actor akA2, Float duration, Float tick = 0.5)
    Float startRT = Utility.GetCurrentRealTime()
    While (Utility.GetCurrentRealTime() - startRT) < duration
        Utility.Wait(tick)
        If _ShouldAbort(akA1, akA2)
            Return True
        EndIf
    EndWhile
    Return False
EndFunction

; Holds both actors FROZEN on the given pose for `duration`: waits in ticks and RE-SENDS the pose
; anim every tick, so a one-shot/short Babo clip that ends — or an idle/OAR replacer — can't make
; them drift into another animation mid-scene. Re-sending the event an actor is already looping is a
; no-op, but it snaps a drifted actor straight back. Returns True if the scene aborted.
Bool Function _HoldAnim(Actor akA1, Actor akA2, String animA1, String animA2, Float duration, Float tick = 2.0)
    Float elapsed = 0.0
    While elapsed < duration
        ; (Re-)assert the pose at the start of every tick, then wait. Sending an event an actor is
        ; already in is a no-op; sending it to a drifted actor snaps them back onto the scene anim.
        If animA1 != ""
            Debug.SendAnimationEvent(akA1, animA1)
        EndIf
        If animA2 != ""
            Debug.SendAnimationEvent(akA2, animA2)
        EndIf
        ; Clamp the final step to land EXACTLY on duration (no overshoot — that was the extra ~2s hold).
        Float step = tick
        If elapsed + step > duration
            step = duration - elapsed
        EndIf
        If _WaitOrAbort(akA1, akA2, step)
            Return True
        EndIf
        elapsed += step
    EndWhile
    Return False
EndFunction

; True if the aggressor who owns this ground window is still within `radius` of the victim. Drives the
; presence-based hold in _DefeatGroundWindow: while they're around, the victim stays down; they only
; recover once the aggressor has truly left.
; Pure Yamete Redux style: GetDistance() against the ONE known reference (SNBaka.GroundWindowAggressor,
; set right before the wait loop starts — the only caller of this function), no scanning for unknowns.
; An unrelated bystander who isn't the tracked aggressor is an accepted blind spot of going this simple
; — matches Acheron's _NearbyThreat, same trade-off on both sides.
Bool Function _AnyActorNear(Actor akVictim, Float radius)
    If !akVictim
        Return False
    EndIf
    Actor aggressor = StorageUtil.GetFormValue(akVictim, "SNBaka.GroundWindowAggressor") as Actor
    ; A DOWNED aggressor doesn't count as "still here" — they can't threaten or witness anything.
    If !aggressor || aggressor == akVictim || aggressor.IsDead() || aggressor.IsDisabled() || _IsDownedAny(aggressor)
        Return False
    EndIf
    Return akVictim.GetDistance(aggressor) < radius
EndFunction

; True if a fight is still going on near the victim — the victim themselves, or any actor within
; `radius`, is in combat. Gates escalation (the only combat-gated step): no forced sex until this is
; false. Cell sweep covers the usual same-cell/nearby combatants.
Bool Function _CombatNear(Actor akCenter, Float radius)
    If !akCenter
        Return False
    EndIf
    If _HasLiveCombatTarget(akCenter)
        Return True
    EndIf
    Cell c = akCenter.GetParentCell()
    If c
        Int n = c.GetNumRefs(62)   ; 62 = kCharacter
        Int i = 0
        While i < n
            Actor a = c.GetNthRef(i, 62) as Actor
            If a && a != akCenter && !a.IsDead() && _HasLiveCombatTarget(a) && akCenter.GetDistance(a) < radius
                Return True
            EndIf
            i += 1
        EndWhile
    EndIf
    Return False
EndFunction

; IsInCombat() alone is known to linger stale with no live target (confirmed repeatedly in this file —
; see the creature-escalation "succeed but combatNear stuck true, scene never starts, QTE anim just
; re-plays on every retry" bug this was written to fix). A genuine ongoing fight has an actual live
; target; a stale flag with nothing to point at doesn't. Deliberately NOT a blanket StopCombat here —
; that would also pull the actor out of a fight with someone else entirely unrelated to this check.
Bool Function _HasLiveCombatTarget(Actor a) Global
    If !a.IsInCombat()
        Return False
    EndIf
    Actor target = a.GetCombatTarget()
    ; A DOWNED combat target doesn't count as a live fight -- confirmed real deadlock from testing:
    ; a falmer whose only remaining "combat target" was an already-downed victim kept reading as
    ; "still actively fighting someone else" on every single engagement attempt, blocking escalation
    ; on every downed victim around it indefinitely (combat state never resolves against a target
    ; that's helpless/ghosted and can neither die nor fight back).
    Return target && !target.IsDead() && !target.IsDisabled() && !_IsDownedAny(target)
EndFunction

; Called the instant a struggle resolves with the victim defeated (creature OR human attacker) --
; starts the post-defeat grace window (fPostDefeatGraceDuration) so passive creature paths leave this
; specific victim alone for a while instead of re-picking them the moment they're vulnerable again.
Function _StampDefeatGrace(Actor akVictim)
    If !akVictim
        Return
    EndIf
    StorageUtil.SetFloatValue(akVictim, "SNBaka.DefeatGraceUntilRT", Utility.GetCurrentRealTime() + fPostDefeatGraceDuration)
EndFunction

; True while akVictim is still within their post-defeat grace window AND hasn't already been dragged
; back into a real fight -- a live combat target means "some of them attacked somebody", which ends the
; grace early by design (see the property comment on fPostDefeatGraceDuration).
Bool Function _InDefeatGrace(Actor akVictim)
    If !akVictim || _HasLiveCombatTarget(akVictim)
        Return False
    EndIf
    ; [REV-161 PR#2 fold (1)] relaunch clamp: a pre-relaunch stamp never expires on its own.
    Float graceUntil = StorageUtil.GetFloatValue(akVictim, "SNBaka.DefeatGraceUntilRT", 0.0)
    If _RTStampStale(graceUntil, Utility.GetCurrentRealTime())
        Return False
    EndIf
    Return Utility.GetCurrentRealTime() < graceUntil
EndFunction

; Delegate a down to Acheron if it's installed. No plugin probe needed: DefeatActor takes (IsDefeated
; becomes true) when Acheron is present, and is a harmless no-op when it isn't — so a false return means
; "Acheron absent, use Baka's own fallback window". Returns True if Acheron took ownership of the down.
; Ask the SkyrimNet Acheron INTEGRATION to defeat + hold this actor. We do NOT call Acheron ourselves —
; the integration owns downing (it defeats via Acheron, marks the hold, and fires the cue), exactly like
; a combat defeat flows through it. Returns True if the integration is present (so we skip Baka's own
; window); False when it isn't installed, so the caller runs Baka's fallback _DefeatGroundWindow.
Bool Function _DelegateDownToAcheron(Actor akVictim)
    If !akVictim || !PlayerRef
        Return False
    EndIf
    ; REV-61 1a — bridge liveness handshake: SNAcheron.Present/Enabled are StorageUtil keys
    ; that persist in the cosave, so they can be STALE from an install where the bridge was
    ; loaded/enabled but is now disabled/absent (the 09-30 Frabbi incident: delegation sent
    ; SNBaka_RequestAcheronDown into a void — no listener, victim never downed, nobody owned
    ; recovery). Probe the bridge's own quest form (SNAcheron_Quest 0x800) directly: None
    ; means the bridge esp is NOT in the load order right now, so we route to the local
    ; fallback window exactly like an absent bridge — no matter what the flags say.
    If !_AcheronBridgePresent()
        _Log("[SNBaka] _DelegateDownToAcheron: bridge liveness probe FAILED (SNAcheron_Quest 0x800 not loaded) — stale SNAcheron.Present=" + StorageUtil.GetIntValue(PlayerRef, "SNAcheron.Present", 0) + "; routing to local fallback window, victim=" + akVictim.GetDisplayName())
        ; Kill the stale flag so no other Present-reading path is fooled this session —
        ; the bridge re-stamps it on its own init if it ever loads again.
        StorageUtil.SetIntValue(PlayerRef, "SNAcheron.Present", 0)
        Return False
    EndIf
    ; The integration stamps this flag on init + every self-heal; absent == integration not installed.
    If StorageUtil.GetIntValue(PlayerRef, "SNAcheron.Present", 0) != 1
        Return False
    EndIf
    ; Present means INSTALLED, not enabled -- the bridge's OnDownRequest gates on its own MCM master
    ; switch and silently DROPS queued victims while disabled. Delegating into that void cleared our
    ; local flags with nobody ever actually downing the victim (they'd just stand there). Check the
    ; same shared StorageUtil key its own MCM writes, so a disabled bridge routes us to the local
    ; fallback window instead, exactly like an absent one.
    If StorageUtil.GetIntValue(PlayerRef, "SNAcheron.Enabled", 1) != 1
        Return False
    EndIf
    ; Already held (e.g. Acheron's own combat-defeat consequence already picked this same takedown up)?
    ; Don't re-queue/re-cue — that fired a second, redundant "is down" narration for one event.
    If StorageUtil.GetIntValue(akVictim, "SNAcheron.Held", 0) == 1
        Return True
    EndIf
    StorageUtil.FormListAdd(PlayerRef, "SNBaka.AcheronDownQueue", akVictim)
    SendModEvent("SNBaka_RequestAcheronDown")
    Return True
EndFunction

; Single source of truth for "is this actor currently downed", covering all three ways a victim can
; be helpless: our own ground window (SNBaka.OnGround), a vanilla bleedout, OR a PURE Acheron hold
; (SNAcheron.Held) with neither of the other two flags set — e.g. a victim delegated to Acheron via
; _DelegateDownToAcheron never gets SNBaka.OnGround, and Acheron.DefeatActor does not reliably flip
; the vanilla IsBleedingOut() state either. Every action that gates on "is the target downed" (Escalate,
; Release, HelpUp, Capture, CreatureEscalate) must use this — a bare OnGround/IsBleedingOut check silently
; rejects a target the acheron_downed/acheron_opportunity cues just told the LLM to act on.
; Global (no instance state used) so GetBakaState — itself Global, called by reflection from SkyrimNet —
; can share this exact same check instead of carrying its own copy.
Bool Function _IsDownedAny(Actor ak) Global
    If !ak
        Return False
    EndIf
    Return StorageUtil.GetIntValue(ak, "SNBaka.OnGround", 0) == 1 \
        || ak.IsBleedingOut() \
        || StorageUtil.GetIntValue(ak, "SNAcheron.Held", 0) == 1
EndFunction

; Clears an external Acheron hold (bleedout AND/OR our own SNAcheron.Held flag) so a resolving action
; (HelpUp/Release/Capture/SellToSlavery/CreatureEscalate) can take the victim over cleanly. Safe to call
; on an actor Acheron never held (no-op). Deliberately NOT called by the human Escalate path — the calm/
; pacify hold must persist THROUGH the sex scene; _EscalationCleanup re-delegates back to Acheron after.
; abFullRescue=False skips Acheron's own RescueActor call (the dramatic "saved" event/stat-reset) and
; only clears the pacify hold via ReleaseActor -- used by Stand Back, which should let the victim get
; up locally without Acheron treating it as a full rescue (that's what "help up" is for).
Function _ClearAcheronHold(Actor ak, Bool abFullRescue = True, Bool abKeepPacified = False)
    If !ak
        Return
    EndIf
    If ak.IsBleedingOut() || StorageUtil.GetIntValue(ak, "SNAcheron.Held", 0) == 1
        ; Held cleared FIRST -- the Acheron bridge's OnActorRescued now redowns anyone rescued while
        ; still flagged Held (its "nobody recovers on their own" rule); clearing before RescueActor is
        ; what marks this rescue as sanctioned. RescueActor is documented as queued/async, so the event
        ; fires well after this line, but don't rely on that ordering by accident -- make it explicit.
        StorageUtil.SetIntValue(ak, "SNAcheron.Held", 0)
        ; Only touch Acheron's own rescue/release if Acheron still THINKS this actor is defeated --
        ; calling RescueActor/ReleaseActor on an actor it doesn't track as defeated is a call its native
        ; code was never meant to receive. Shared native API, no hard reference needed.
        If Acheron.IsDefeated(ak)
            If abKeepPacified
                ; INTERACTION TAKEOVER (a struggle/scene is about to own this actor): end the defeat
                ; but keep Acheron's native pacify ON through the handoff. Rescuing with abRelease=true
                ; + ReleaseActor (below) fully strips the protection, and every attempt to rebuild it by
                ; hand afterward lost a race with the QUEUED rescue task — confirmed live, repeatedly:
                ; "EVERY time somebody gets escalated, during the period we free from acheron, enemies
                ; aggro." abRelease=false is Acheron's own primitive for exactly this.
                Acheron.RescueActor(ak, false)
            Else
                If abFullRescue
                    Acheron.RescueActor(ak, true)
                EndIf
                ; OSimpleDefeat (a sibling mod doing the same Acheron+OStim defeat/release flow) always pairs
                ; RescueActor with an explicit ReleaseActor call. RescueActor is documented as QUEUED/async;
                ; ReleaseActor removes the pacify state immediately — belt-and-suspenders so pacify doesn't
                ; linger until Acheron's queued task gets around to it.
                Acheron.ReleaseActor(ak)
            EndIf
        Else
            _Log("[SNBaka] _ClearAcheronHold: Acheron no longer considers " + ak.GetDisplayName() + " defeated -- skipping RescueActor/ReleaseActor")
            ; We were called because the actor still reads held/bleeding, yet Acheron's tracking has
            ; already disowned them -- the redown-vs-queued-rescue race (AcheronNG's async rescue task
            ; un-tracks a defeat the bridge just re-applied) leaves the actor VISUALLY stuck in the
            ; defeat pose with no native state left for anyone to rescue them out of. Confirmed live:
            ; follower stuck in the defeated animation after HelpUp, unrescuable (every downed-check
            ; reads False). RescueActor is what normally ends the pose natively; with it skipped,
            ; force the graph out ourselves. Both events are harmless no-ops on a clean actor.
            If ak != PlayerRef
                ak.RestoreActorValue("Health", 1000.0)   ; a bleedout-threshold HP level would re-drop them instantly
            EndIf
            Debug.SendAnimationEvent(ak, "BleedoutStop")
            Debug.SendAnimationEvent(ak, "IdleForceDefaultState")
        EndIf
        _Log("[SNBaka] _ClearAcheronHold: cleared Acheron hold on " + ak.GetDisplayName() + " (abFullRescue=" + abFullRescue + " keepPacified=" + abKeepPacified + ")")
    EndIf
EndFunction

; The victim WON the struggle/QTE — they overpowered the attacker and are NOT downed. Clear any downed
; state and, if they were being held by Acheron (e.g. they struggled up from a prior down), ask the
; integration to RELEASE them so they leave Acheron and recover. They are fit to keep fighting — no calm,
; no pacify, no further handling.
Function _OnVictimWon(Actor akWinner, Actor akLoser)
    If !akWinner
        Return
    EndIf
    StorageUtil.SetIntValue(akWinner,    "SNBaka.Locked",   0)
    StorageUtil.SetIntValue(akWinner,    "SNBaka.OnGround", 0)
    StorageUtil.SetStringValue(akWinner, "SNBaka.DownPose", "")
    StorageUtil.SetIntValue(akWinner,    "SNBaka.Captive",  0)
    ; Hand the release to the integration (it owns the Acheron hold), same as we hand it the down.
    If StorageUtil.GetIntValue(PlayerRef, "SNAcheron.Present", 0) == 1 && Acheron.IsDefeated(akWinner)
        StorageUtil.FormListAdd(PlayerRef, "SNBaka.AcheronReleaseQueue", akWinner)
        SendModEvent("SNBaka_RequestAcheronRelease")
    EndIf
EndFunction

; Suppress an NPC's AI for the duration of a scene — this is how SexLab keeps actors
; from breaking out of a held pose (LockActor → AddPackageOverride DoNothing).  We were
; missing this: SetRestrained/SetDontMove stop walking but NOT package re-evaluation, so
; the NPC's AI reverted its animation after a few seconds.  Force a condition-free
; DoNothing package at high priority; remove it at cleanup.  Player is skipped (it uses
; DisablePlayerControls instead).  No-op if SNBakaDoNothing isn't assigned yet.
Function _HoldActorAI(Actor akActor, Bool hold)
    If !akActor || akActor == PlayerRef
        Return
    EndIf
    If !SNBakaDoNothing
        ; Loud on purpose: if this fires, the CK property isn't set and the SexLab-style
        ; hold can't work — explains an NPC dropping its pose.
        _Log("[SNBaka] _HoldActorAI: SNBakaDoNothing package is NONE — AI NOT suppressed for " + akActor.GetDisplayName() + " (set the property in CK)")
        Return
    EndIf
    If hold
        ActorUtil.AddPackageOverride(akActor, SNBakaDoNothing, 100, 1)
    Else
        ActorUtil.RemovePackageOverride(akActor, SNBakaDoNothing)
    EndIf
    akActor.EvaluatePackage()
    _Log("[SNBaka] _HoldActorAI: " + akActor.GetDisplayName() + " hold=" + hold + " (DoNothing override)")
EndFunction

; Pacify an NPC for the duration of an interaction so it can't enter/initiate combat (which
; broke the scene mid-animation). Sets Aggression 0 + stops combat; stores the original once
; (guarded by the SNBaka.Pacified flag so double-calls during the active anim AND the down
; window don't lose it). Never touches the player.
Function _PacifyActor(Actor ak, Bool on)
    If !ak || ak == PlayerRef
        Return
    EndIf
    If on
        ; [REV-161 PR#2 fold (2) - Oldcustard credit, by-concept] CLAIM-BEFORE-READ
        ; + CROSS-TREE ORIGINAL REUSE: check the GS-side flag BEFORE storing an
        ; original. If the GS tree already holds the pacify, its stored original
        ; (shared key SNBaka.OrigAggr) is the true pre-pacify aggression --
        ; storing a fresh one here would capture the already-zeroed value and
        ; the release would restore 0 (pacify perpetuated). We still track our
        ; own on/off pairing, but never touch the original while GS holds.
        If StorageUtil.GetIntValue(ak, "SNBaka.Pacified", 0) == 0 && StorageUtil.GetIntValue(ak, "GSAnim.Pacified", 0) == 0
            StorageUtil.SetFloatValue(ak, "SNBaka.OrigAggr", ak.GetActorValue("Aggression"))
            StorageUtil.SetIntValue(ak, "SNBaka.Pacified", 1)
        ElseIf StorageUtil.GetIntValue(ak, "SNBaka.Pacified", 0) == 0
            StorageUtil.SetIntValue(ak, "SNBaka.Pacified", 1)   ; GS owns the original; we ride it
        EndIf
        ak.SetActorValue("Aggression", 0.0)
        ak.StopCombatAlarm()
        ak.StopCombat()
        ; Robust combat-stop (Surrender's trick): a Calm-archetype spell reliably drops the actor out
        ; of combat where aggression-0 alone can be re-triggered by faction hostility. No-op if unset.
        If SNBakaCalm
            SNBakaCalm.Cast(ak, ak)
        EndIf
        _Log("[SNBaka] _PacifyActor: calmed " + ak.GetDisplayName() + " (aggr->0, StopCombat, Calm cast; wasInCombat now=" + ak.IsInCombat() + ")")
    ElseIf StorageUtil.GetIntValue(ak, "SNBaka.Pacified", 0) == 1
        ; [REV-161 PR#2 fold (2)] release only when the LAST pacify owner goes:
        ; the GS tree still holding means the aggression restore belongs to ITS
        ; release, not ours.
        If StorageUtil.GetIntValue(ak, "GSAnim.Pacified", 0) == 0
            ak.SetActorValue("Aggression", StorageUtil.GetFloatValue(ak, "SNBaka.OrigAggr", 1.0))
        EndIf
        StorageUtil.SetIntValue(ak, "SNBaka.Pacified", 0)
        ; The Calm EFFECT cast on pacify does NOT end with the aggression restore — with any real
        ; duration it kept "liberated" aggressors becalmed and passive long after the struggle
        ; (confirmed: the giant Joylie broke free from attacked nobody). Dispel it explicitly.
        If SNBakaCalm
            ak.DispelSpell(SNBakaCalm)
        EndIf
        _Log("[SNBaka] _PacifyActor: restored " + ak.GetDisplayName() + " (aggr back to " + StorageUtil.GetFloatValue(ak, "SNBaka.OrigAggr", 1.0) + ", Calm dispelled)")
    EndIf
EndFunction

; Two-way "combat drops the victim" protection, with one critical exception: NEVER Acheron-pacify the
; PLAYER. Acheron's pacify on the player is native lockdown we can't partially undo from Papyrus, and
; it shipped a locked/stiff camera during struggles the build it was introduced (confirmed report).
; The player gets the stale-lock sweep only: hits whiff on ghost, and the struggle tick (_ShouldAbort)
; plus the scene wait loop re-clear any re-acquired lock every second.
Function _ProtectVictimTargeting(Actor akVictim)
    If akVictim == PlayerRef
        ; Surrender and SL Defeat both protect a fallen PLAYER the same way (confirmed by reading
        ; their sources): the Calm-archetype state goes ON THE VICTIM — combat AI treats a calmed
        ; actor as an invalid target and drops them, per-victim, without touching anyone else's
        ; fights. Magic-effect archetypes only drive AI, so the player's camera/controls are
        ; untouched — unlike Acheron's native player pacify (locked camera). Re-cast every tick by
        ; the struggle/scene polls, so duration doesn't matter.
        If SNBakaCalm
            SNBakaCalm.Cast(PlayerRef, PlayerRef)
            PlayerRef.StopCombatAlarm()
            _Log("[SNBaka] _ProtectVictimTargeting: Calm state cast on the player-victim (SL Defeat pattern)")
        Else
            _Log("[SNBaka] _ProtectVictimTargeting: WARNING — SNBakaCalm spell property is EMPTY, player-victim has no drop-target protection")
        EndIf
    ElseIf StorageUtil.GetIntValue(PlayerRef, "SNAcheron.Present", 0) == 1
        Acheron.PacifyActor(akVictim)
    EndIf
    _ClearStaleCombatLocks(akVictim)
EndFunction

; Acheron's pacify/defeat blocks NEW target acquisition but does NOT make attackers drop an
; already-locked combat target (confirmed live: giants kept swinging at an Acheron-defeated player;
; "after StopCombat(): IsInCombat()=TRUE" — the victim's own flag can't clear while others hold locks
; on them; the ATTACKERS' locks are what this clears). Only actors whose current combat target IS the
; victim are touched — an intercessor fighting the AGGRESSOR keeps its fight untouched.
Function _ClearStaleCombatLocks(Actor akVictim)
    Actor[] loaded = PO3_SKSEFunctions.GetActorsByProcessingLevel(0)
    Int i = 0
    While i < loaded.Length
        Actor atk = loaded[i]
        If atk && atk != akVictim && atk != PlayerRef && !atk.IsDead() && atk.GetCombatTarget() == akVictim
            atk.StopCombat()
            atk.EvaluatePackage()
            _Log("[SNBaka] _ClearStaleCombatLocks: " + atk.GetDisplayName() + " was still locked onto " + akVictim.GetDisplayName() + " — combat stopped")
        EndIf
        i += 1
    EndWhile
EndFunction

; End every "lover"-rank (4) anti-re-aggro link between this victim and any loaded CREATURE — our
; escalations always use rank 4 with a supported creature, so this signature can't hit a real spouse.
; Runs on every genuine liberation: repairs the CURRENT pair even if the caller lost track of it, and
; self-heals stale links baked into saves by builds that never reverted them (confirmed symptom: a
; giant that had previously beaten Joylie would never attack her again).
Function _ClearAggressorBonds(Actor akVictim)
    Actor[] loaded = PO3_SKSEFunctions.GetActorsByProcessingLevel(0)
    Int i = 0
    While i < loaded.Length
        Actor a = loaded[i]
        If a && a != akVictim && a != PlayerRef && !a.IsDead() && a.GetRelationshipRank(akVictim) == 4
            Bool isCreatureLink = _CreatureAnimKey(a) != ""
            ; _PacifyNearbyHostiles (Capture_Execute) ALSO stamps rank 4 on every nearby HUMANOID
            ; hostile to keep a captor's whole camp from re-opening fire -- but nothing ever reverted
            ; that for non-creatures, only this creature-only sweep. Confirmed root cause of "enemies/
            ; followers revive but never re-engage that one actor again": every bandit who was ever
            ; nearby during a capture stayed permanently "allied" (rank 4) to the victim. Can't just
            ; widen the creature check to every actor -- rank 4 is vanilla's "Lover"/spouse rank too,
            ; and blindly clearing it on a humanoid risks breaking a real marriage. SNBaka.Pacified==1
            ; is the safe tell instead: _PacifyNearbyHostiles only ever pacifies actors who were
            ; HOSTILE to the victim at the time, and a genuine spouse is never hostile to their own
            ; spouse, so a real Lover-rank humanoid could never end up flagged pacified this way.
            Bool isStaleHumanoidAllyLink = !isCreatureLink && StorageUtil.GetIntValue(a, "SNBaka.Pacified", 0) == 1
            If isCreatureLink || isStaleHumanoidAllyLink
                a.SetRelationshipRank(akVictim, 0)
                If akVictim != PlayerRef
                    akVictim.SetRelationshipRank(a, 0)
                EndIf
                _Log("[SNBaka] _ClearAggressorBonds: cleared lover-rank link " + a.GetDisplayName() + " <-> " + akVictim.GetDisplayName())
            EndIf
            If isStaleHumanoidAllyLink
                ; _PacifyNearbyHostiles pacifies the captor's WHOLE nearby group, but only the one
                ; tracked aggressor ever got un-pacified on release -- every other swept bystander
                ; stayed calmed/aggression-0 forever. Release them too, now that the rank-4 tell above
                ; has identified them as one of that sweep.
                _PacifyActor(a, False)
                a.EvaluatePackage()
            EndIf
        EndIf
        ; Stray-Calm sweep (same loop, essentially free): an actor still carrying our Calm effect
        ; while NOT flagged pacified is a leftover from an interrupted cycle — reported as actors
        ; "calmed even when they should not be anymore". Dispels only OUR spell; no-op otherwise.
        If a && a != PlayerRef && SNBakaCalm && StorageUtil.GetIntValue(a, "SNBaka.Pacified", 0) == 0
            a.DispelSpell(SNBakaCalm)
        EndIf
        i += 1
    EndWhile
EndFunction

; Aggression + Calm-dispel alone doesn't reliably make the AI resume a fight on its own once our own
; suppression lifts -- confirmed for the mid-combat grapple's own release-on-break path (see
; Subdue_Execute), where nothing but an explicit StartCombat got a freshly-freed hostile target to
; actually re-engage. Same gap applies anywhere else Baka un-suppresses a pair: if they're STILL
; genuinely hostile to each other per the game's own faction/relationship state (not because of
; anything WE were holding, which is already cleared by the time this runs), force it explicitly
; instead of hoping the engine notices on its own. No-op for any pair that was never actually
; hostile — a normal social Struggle/Intimate partner correctly does nothing here.
Function _RestoreHostility(Actor akA, Actor akB)
    If !akA || !akB || akA.IsDead() || akB.IsDead()
        Return
    EndIf
    If akA.IsHostileToActor(akB)
        akA.StartCombat(akB)
    EndIf
    If akB.IsHostileToActor(akA)
        akB.StartCombat(akA)
    EndIf
EndFunction

; Pacify EVERYONE near the victim who is hostile to them (the captor's whole group), so a capture
; isn't instantly broken by other bandits in the camp re-opening fire. Reversible (each gets the
; standard SNBaka.Pacified flag, so a future release restores their aggression).
Function _PacifyNearbyHostiles(Actor akVictim, Float radius = 3000.0)
    If !akVictim
        Return
    EndIf
    Cell c = akVictim.GetParentCell()
    If !c
        Return
    EndIf
    Int total = c.GetNumRefs(62)
    Int i = 0
    Int pacified = 0
    While i < total
        Actor a = c.GetNthRef(i, 62) as Actor
        If a && a != akVictim && a != PlayerRef && !a.IsDead() && a.GetDistance(akVictim) < radius
            ; We do NOT try to identify "the captor's faction" — in a multi-faction brawl (bandits +
            ; Stormcloaks + whoever) that's unknowable. Instead we stand down everyone HOSTILE TO THE
            ; CAPTIVE: those are the only ones who threaten them. Anyone fighting a different enemy
            ; (other factions brawling each other) is left alone to keep fighting. IsHostileToActor is
            ; the precise test; "currently swinging at the captive" (GetCombatTarget) catches anyone
            ; attacking them for non-faction reasons (crime/assault). We deliberately do NOT calm on
            ; bare IsInCombat — that would silence unrelated factions fighting each other.
            If a.IsHostileToActor(akVictim) || a.GetCombatTarget() == akVictim
                _PacifyActor(a, True)
                a.StopCombat()
                a.StopCombatAlarm()
                a.SetRelationshipRank(akVictim, 4)   ; ally-level so they don't re-aggro the prisoner
                a.EvaluatePackage()
                pacified += 1
            EndIf
        EndIf
        i += 1
    EndWhile
    _Log("[SNBaka] _PacifyNearbyHostiles: pacified " + pacified + " hostile(s) near " + akVictim.GetDisplayName())
EndFunction

; Keeps the victim downed for duration seconds after a violent action.
; Fires baka_opportunity so nearby NPCs (and SkyrimNet) can react and escalate.
; Recovery is skipped if combat starts or a stop is requested.
Function _RecoveryPeriod(Actor akVictim, Actor akWitness, Float duration)
    If !akVictim || akVictim.IsDead() || akVictim.IsInCombat()
        _Log("[SNBaka] _RecoveryPeriod: skipped for " + akVictim.GetDisplayName() + " (dead=" + akVictim.IsDead() + " inCombat=" + akVictim.IsInCombat() + ")")
        Return
    EndIf
    Bool victimIsPlayer = (akVictim == PlayerRef)
    _Log("[SNBaka] _RecoveryPeriod: victim=" + akVictim.GetDisplayName() + " isPlayer=" + victimIsPlayer + " duration=" + duration)
    If victimIsPlayer
        Game.DisablePlayerControls(True, True, False, False, True, False, False, False)
        ; (No SetDontMove on the player — it locked the camera. The NPC is ghosted so it can't
        ; shove the player, and the player isn't ghosted so they won't fall; no pin needed.)
    EndIf
    StorageUtil.SetStringValue(akVictim, "SNBaka.DownPose", "")   ; fresh down -> re-roll the pose
    _Bleedout(akVictim, akWitness)
    Utility.Wait(0.5)
    If !victimIsPlayer
        akVictim.SetRestrained(True)
        akVictim.SetDontMove(True)
        _Log("[SNBaka] _RecoveryPeriod: Restrained+DontMove set on NPC")
    EndIf
    Utility.Wait(0.3)
    If !victimIsPlayer
        ; REV-146a Task 11: the passive down-cue routes through the same
        ; audience router (the player is never the opportunity audience).
        Actor akOppAudience = _OpportunityAudience(akWitness, akVictim)
        If akOppAudience
            SkyrimNetApi.RegisterEvent("baka_opportunity", \
                akVictim.GetDisplayName() + " is helpless on the ground.", \
                akOppAudience, akVictim)
        EndIf
    EndIf
    ; Victim is in bleedout so IsDead()=True — _WaitOrAbort would abort on tick 1.
    ; Per design, the bleedout is the ONE thing that PERSISTS through combat: the downed
    ; loser stays helpless on the ground for the full window even if a fight breaks out
    ; around them (unlike the paired anim, which combat breaks).  So: plain timed wait,
    ; no combat early-exit.
    ; Real-clock elapsed, not a naive tick counter -- see _WaitOrAbort's comment. Without this, a
    ; "10 second" recovery hold (this is the path a player-as-victim struggle falls into when there's
    ; no real QTE contest to resolve it) could balloon under VM load the same way the QTE loops did.
    Float recStartRT = Utility.GetCurrentRealTime()
    Float recTick    = 0.5
    Float recDur     = duration - 0.5
    Float recHold    = 0.0
    While (Utility.GetCurrentRealTime() - recStartRT) < recDur
        Utility.Wait(recTick)
        recHold += recTick
        If recHold >= 3.0
            recHold = 0.0
            String rdp = StorageUtil.GetStringValue(akVictim, "SNBaka.DownPose", "")
            If rdp != "" && !victimIsPlayer
                Debug.SendAnimationEvent(akVictim, rdp)   ; hold the cached down pose
            EndIf
        EndIf
    EndWhile
    akVictim.SetRestrained(False)
    akVictim.SetDontMove(False)
    _Recover(akVictim)
    If victimIsPlayer
        Game.EnablePlayerControls()
        Debug.SendAnimationEvent(akVictim, "IdleForceDefaultState")
        _Log("[SNBaka] _RecoveryPeriod: player controls re-enabled")
    EndIf
    _Log("[SNBaka] _RecoveryPeriod: done for " + akVictim.GetDisplayName())
EndFunction

; Puts akVictim into the defeat down-pose. PURE ANIMATION — no Kill(), no vanilla bleedout,
; no Acheron, no HP manipulation, for EITHER player or NPC.
;
; The victim is held in place by the caller: DisablePlayerControls for the player (camera stays
; free — looking is left enabled), or SetRestrained+SetDontMove+pacify for NPCs. The Babo down
; idle is a cyclic 'b' animation, so it loops and holds the pose until _Recover stands them up
; with IdleForceDefaultState. With no AI/agency on the victim, escalation can still run on them.
; Weighted-random downed pose, for variety when no caller set _sDownPose. All options read as a
; collapse on the ground so they fit the pinned/restrained down state. KnockOut is a sequence whose
; Start transitions into a looping knocked-out pose; FaintF is female-only. Add Panting/Surrender to
; the pools if they read as ground poses in-game. (Outcome-specific poses: set _sDownPose before the
; ground window to force one — e.g. a brutal KO -> "BaboDefeatKnockOutStart".)
String Function _PickDownPose(Actor akVictim)
    Bool female = akVictim && _SexOf(akVictim) == 1
    ; Wire the pose to WHY they went down (their last Baka action). Unmapped motives -> random variety.
    ; (Choke already forces BaboFaintF via _sDownPose, which overrides this entirely.)
    String motive = StorageUtil.GetStringValue(akVictim, "SNBaka.LastAnim", "")
    If motive == "Struggle" || motive == "BackHugMolest" || motive == "ChokeHug"
        If female && motive == "ChokeHug"
            Return "BaboFaintF"               ; choked out -> faint
        EndIf
        Return "Babo_DefeatTraumaLie"         ; overpowered/grappled -> limp on the ground (STATIC: re-asserts cleanly, unlike the KnockOut sequence which restarts every re-assert and looks like it "rotates")
    ElseIf motive == "DrunkExploit" || motive == "DrugFood"
        Return "Babo_DefeatTraumaLie"         ; drunk/drugged -> limp on the ground
    EndIf
    Int r = Utility.RandomInt(1, 100)
    ; NOTE: only STATIC ground idles here. BaboDefeatKnockOutStart is a SEQUENCE — re-asserting it
    ; every few seconds restarts the sequence, which looks like the pose "rotating"/never settling.
    If female   ; female pool
        If r <= 40
            Return "BaboFaintF"
        EndIf
        Return "Babo_DefeatTraumaLie"
    EndIf
    ; male / other pool
    Return "Babo_DefeatTraumaLie"
EndFunction

Function _Bleedout(Actor akVictim, Actor akWitness)
    _Log("[SNBaka] _Bleedout: victim=" + akVictim.GetDisplayName() + " isPlayer=" + (akVictim == PlayerRef))
    ; Clear any looping paired animation still playing on the victim first.
    ; Without this, BaboBackHugMolestLoopF / Struggle loops etc. block the KnockDown event.
    Debug.SendAnimationEvent(akVictim, "IdleForceDefaultState")
    Utility.Wait(0.2)
    ; Same Babo down idle for BOTH player and NPC.
    String downAnim = _sDownPose
    If downAnim == ""
        ; Roll the random pose ONCE per down and cache it on the actor, so it can't visibly change
        ; if _Bleedout runs again (re-assert, or an Investigate/Inspect re-down) — it sticks for the
        ; whole downed state. The cache is cleared at the start of a fresh down (see below).
        downAnim = StorageUtil.GetStringValue(akVictim, "SNBaka.DownPose", "")
        If downAnim == ""
            downAnim = _PickDownPose(akVictim)   ; weighted variety; _sDownPose still overrides
        EndIf
    EndIf
    StorageUtil.SetStringValue(akVictim, "SNBaka.DownPose", downAnim)
    Debug.SendAnimationEvent(akVictim, downAnim)
    _Log("[SNBaka] _Bleedout: down pose = " + downAnim + " on " + akVictim.GetDisplayName())
    _sDownPose = ""
    _Log("[SNBaka] _Bleedout: bleedout triggered on " + akVictim.GetDisplayName())
    If bExpressionsEnabled
        _ApplyMoodExpression(akVictim, "pained")
    EndIf
EndFunction

; Recovers akVictim from the defeat down-pose placed by _Bleedout.
; Stands both player and NPC up with IdleForceDefaultState (no vanilla BleedoutStop, no Acheron).
; Only restores HP on an Essential NPC that was ever killed into bleedout (legacy guard).
; Caller must EnablePlayerControls after this for the player.
; Matching "stand up" transition for a known down pose, or "" if the pose is unrecognized/empty — the
; latter happens for a PURE Acheron-native combat defeat (no Baka QTE ever ran, so SNBaka.DownPose was
; never set), which is common and not an error. Global so Acheron's own _Recover can reuse the same
; mapping without a hard script reference (StorageUtil key only).
String Function _GetUpAnimFor(String downPose) Global
    If downPose == "Babo_DefeatTraumaLie"
        Return "Babo_DefeatTraumaStand"
    EndIf
    Return ""
EndFunction

; Borrowed from the Surrender mod's own proven technique (DBSurrenderActive.psc): while an actor is in
; OUR downed state, force them Essential — but ONLY if they weren't already Essential or Protected, and
; track that WE were the ones who did it, so recovery only ever undoes our own change, never someone
; else's existing protection. Confirmed real gap otherwise: nothing currently stops a downed/pinned
; victim from just dying to a stray follow-up hit while helpless, since restraining them (SetRestrained/
; SetDontMove) does nothing about incoming damage.
Function _ForceEssentialForDown(Actor ak, Bool abForce)
    If !ak
        Return
    EndIf
    ActorBase bse = ak.GetActorBase()
    If !bse
        Return
    EndIf
    If abForce
        ; NO forced protection anymore -- explicit spec change: a downed actor lives or dies by their
        ; own BASE flags. Base Essential/Protected keep their vanilla immunities; everyone else can be
        ; finished off while down by accumulated damage from anything (stray hits, fire, an NPC that
        ; keeps swinging), and a single PLAYER hit executes them outright (see OnPlayerHitActor).
        ; "It's life." The call sites are kept as the single policy point in case this changes again.
    Else
        If StorageUtil.GetIntValue(ak, "SNBaka.ProtectForcedByUs", 0) == 1
            bse.SetProtected(False)
            StorageUtil.SetIntValue(ak, "SNBaka.ProtectForcedByUs", 0)
            _Log("[SNBaka] _ForceEssentialForDown: restored non-Protected on " + ak.GetDisplayName())
        EndIf
        ; Backward-compat restores for state left by earlier builds of this guard: the brief
        ; Essential-forcing version, and the Ghost the bridge used to apply at down-time (the Ghost
        ; leak was a confirmed bug: permanently invulnerable player, unresolvable enemy combat).
        If StorageUtil.GetIntValue(ak, "SNBaka.EssentialForcedByUs", 0) == 1
            bse.SetEssential(False)
            StorageUtil.SetIntValue(ak, "SNBaka.EssentialForcedByUs", 0)
            _Log("[SNBaka] _ForceEssentialForDown: restored non-Essential on " + ak.GetDisplayName() + " (legacy build residue)")
        EndIf
        If StorageUtil.GetIntValue(ak, "SNAcheron.GhostForcedByUs", 0) == 1
            ak.SetGhost(False)
            StorageUtil.SetIntValue(ak, "SNAcheron.GhostForcedByUs", 0)
            _Log("[SNBaka] _ForceEssentialForDown: cleared legacy down-state Ghost on " + ak.GetDisplayName())
        EndIf
    EndIf
EndFunction

Function _Recover(Actor akVictim, Bool abFullRescue = True)
    _Log("[SNBaka] _Recover: victim=" + akVictim.GetDisplayName() + " isPlayer=" + (akVictim == PlayerRef))
    ; Force Essential FIRST, unconditionally, before checking/restoring health below. Every entry point
    ; we control (our own ground window, _CueDowned, RunConsequence) already forces this the moment
    ; something goes down — but _DispatchDownedAction's "external" branch (Stand Back / HelpUp / Escalate
    ; on a victim downed by something else entirely — SeverActions, vanilla combat, a mod with no Baka
    ; involvement) reaches this same function WITHOUT ever having forced it, on the assumption the actor
    ; was already protected somehow. A generic recruited follower usually isn't Essential by default, so
    ; that assumption killed one (confirmed: acting on a bleeding-out, non-Essential follower here left
    ; her with no safety net at all). _ForceEssentialForDown no-ops if already Essential/Protected, so
    ; this is safe to call unconditionally regardless of which path got here.
    _ForceEssentialForDown(akVictim, True)
    ; Restore health FIRST, while still Essential (ours or their own) — only THEN clear our forced flag.
    ; Reversing this order would mean an actor we made Essential, sitting at ~0 health from being down,
    ; could actually die the instant we un-flag them, before ever getting the health restored below.
    If akVictim.IsEssential() && akVictim.IsDead()
        ; (NPC only) restore HP if an Essential NPC was ever killed into bleedout.
        akVictim.RestoreActorValue("Health", 1000.0)
        Utility.Wait(0.1)
    EndIf
    _ForceEssentialForDown(akVictim, False)
    ; Play a stand-up transition first — IdleForceDefaultState alone just snaps the animation graph to
    ; idle with no visible transition, which is what made every recovery look instant/wrong. Use the
    ; exact matching clip when we know the down pose (Babo_DefeatTraumaLie -> ...Stand); otherwise fall
    ; back to "staggerStart" (the same generic get-up-with-a-stagger event already used by the "Stand
    ; Back" outcome elsewhere in this file) rather than nothing at all — this covers a pure Acheron-
    ; native combat defeat, where SNBaka.DownPose was never set because no Baka QTE ever ran. Still send
    ; IdleForceDefaultState afterward regardless, as the final safety net guaranteeing a clean state even
    ; if the transition doesn't fully resolve on its own.
    String downPose  = StorageUtil.GetStringValue(akVictim, "SNBaka.DownPose", "")
    String getUpAnim = _GetUpAnimFor(downPose)
    If getUpAnim == ""
        getUpAnim = "staggerStart"
    EndIf
    Debug.SendAnimationEvent(akVictim, getUpAnim)
    Utility.Wait(1.0)
    _Log("[SNBaka] _Recover: played get-up transition " + getUpAnim + " for down pose '" + downPose + "'")
    StorageUtil.SetStringValue(akVictim, "SNBaka.DownPose", "")
    ; Stand back up — same for player and NPC now (no vanilla BleedoutStop, no Acheron).
    Debug.SendAnimationEvent(akVictim, "IdleForceDefaultState")
    _Log("[SNBaka] _Recover: stand-up sent to " + akVictim.GetDisplayName())
    If bExpressionsEnabled
        _ClearExpression(akVictim)
    EndIf
    ; This is the ONLY stand-up path that didn't also clear Acheron's hold flag — every other
    ; resolution (Escalate, HelpUp, Release, SellToSlavery) does. Without this, an Acheron-initiated
    ; combat defeat that resolves via passive window-timeout (nobody escalated/helped in time)
    ; left SNAcheron.Held stuck at 1 forever: the victim visibly stands up, but every downed-state
    ; check (_IsDownedAny, eligibility, etc.) kept reading them as still down, since the bridge's
    ; own polling loop is what would normally clear it on an existing save it may never run again.
    _ClearAcheronHold(akVictim, abFullRescue)
EndFunction

Function _StartTears(Actor akVictim)
    If !bAnimatedTearsEnabled || !akVictim
        _Log("[SNBaka] _StartTears: GATED — enabled=" + bAnimatedTearsEnabled + " victim=" + akVictim)
        Return
    EndIf
    ; Setup() does NOT run on every load (its OnPlayerLoadGame doesn't fire on a Quest
    ; script), so TearSpell can be None here.  Resolve it LAZILY, where it's actually
    ; used, with the CONFIRMED-correct id 0x802 = zzNPCTearsTestApplySelf in
    ; EmoTears4NPCs.esp.  (The old wrong 0x322E was a visual-frame effect, not a spell.)
    If !TearSpell
        TearSpell = Game.GetFormFromFile(0x000802, "EmoTears4NPCs.esp") as Spell
        _Log("[SNBaka] _StartTears: lazy-resolved TearSpell=" + TearSpell)
    EndIf
    If !TearSpell || _SexOf(akVictim) != 1
        _Log("[SNBaka] _StartTears: GATED — TearSpell=" + TearSpell + " female=" + (_SexOf(akVictim) == 1) + " for " + akVictim.GetDisplayName())
        Return
    EndIf
    ; The EmoTears apply spell TOGGLES the tear ability, and _StartTears is called
    ; ~23 times across a scene — casting it an even number of times toggles tears
    ; back OFF ("works sometimes").  So cast ONLY when tears aren't already on, and
    ; cast one-arg exactly like the proven ExtraActions implementation.
    ; (No GetFormFromFile here — that wrong-ID lookup is what kept nulling the spell.)
    Int tearsOn = StorageUtil.GetIntValue(akVictim, "SNBaka.TearsOn", 0)
    If tearsOn == 0
        _TearVictim = akVictim
        TearSpell.Cast(akVictim)
        StorageUtil.SetIntValue(akVictim, "SNBaka.TearsOn", 1)
        _Log("[SNBaka] _StartTears: CAST tears on " + akVictim.GetDisplayName())
    Else
        _Log("[SNBaka] _StartTears: SKIPPED " + akVictim.GetDisplayName() + " — SNBaka.TearsOn already 1 (stuck flag? prior scene didn't _StopTears)")
    EndIf
    ; Out-of-sex crying shows a sad face; during sex the afraid/pained/angry cycle owns the face.
    If bExpressionsEnabled && !IsInSexAnimation(akVictim)
        _ApplyMoodExpression(akVictim, "sad")
    EndIf
EndFunction

Function _StopTears(Actor akVictim)
    If _TearVictim == akVictim
        _TearVictim = None
    EndIf
    ; Toggle the tears back off if we turned them on, so each scene starts clean.
    If akVictim && TearSpell && StorageUtil.GetIntValue(akVictim, "SNBaka.TearsOn", 0) == 1
        TearSpell.Cast(akVictim)
        StorageUtil.SetIntValue(akVictim, "SNBaka.TearsOn", 0)
    EndIf
    If bExpressionsEnabled && akVictim
        _ClearExpression(akVictim)
    EndIf
EndFunction

; Affectionate interactions must never show a partner still crying from an earlier forced/sex
; scene. Wipe BOTH tear systems on each actor: the EmoTears spell + expression (_StopTears) AND
; the durable SlaveTats face overlay (zero the heat so the fade timer can't re-apply, then
; ClearFaceMarks). Female-only guards inside the callees make this a no-op on males.
Function _ClearTearsForAffection(Actor akA, Actor akB)
    _ClearActorTears(akA)
    _ClearActorTears(akB)
EndFunction

Function _ClearActorTears(Actor ak)
    If !ak
        Return
    EndIf
    _StopTears(ak)
    StorageUtil.SetIntValue(ak, "SkyrimNetSDB.TearHeat", 0)
    ClearFaceMarks(ak)
EndFunction

; Second tears method — the one that actually survives a SexLab scene.
; _StartTears uses the EmoTears apply-spell, an MFG/animated facial effect that
; SexLab's per-stage expression system resets mid-scene (why tears "don't show"
; during sex).  A SlaveTats Face overlay is a NiOverride SKIN TEXTURE, not an MFG
; morph, so it rides on top of whatever expression SexLab forces and stays visible
; for the whole scene.  Reuses the existing face-mark assets + fade/cleanup
; (SpankedActors formlist, SpankTatFadeRate), and floors TearHeat at one intensity
; step so the streak is visible even with no prior spanks.
Function _ApplySexTears(Actor akVictim)
    If !bAnimatedTearsEnabled || !akVictim || _SexOf(akVictim) != 1
        Return
    EndIf
    Int heat = StorageUtil.GetIntValue(akVictim, "SkyrimNetSDB.TearHeat", 0)
    If heat < SpankTatIntensity
        heat = SpankTatIntensity
        StorageUtil.SetIntValue(akVictim, "SkyrimNetSDB.TearHeat", heat)
    EndIf
    UpdateFaceMarks(akVictim, heat)
    StorageUtil.FormListAdd(Self, "SkyrimNetSDB.SpankedActors", akVictim, True)
    _Log("[SNBaka] _ApplySexTears: SlaveTats tear overlay (heat=" + heat + ") on " + akVictim.GetDisplayName())
    ; NOTE: facial expressions during sex are left to SexLab's own per-stage expression system —
    ; we don't fight it.  Only the tear OVERLAY (above) is ours during sex.
EndFunction

; ===================== Facial expressions =====================
; Morph presets baked from "Additional Expressions Project" (PoserHotKeys FaceData), applied through
; MfgFix's MfgConsoleFunc.  Modes: 0=phoneme, 1=modifier, 2=expression(id,strength), -1=reset phon/mod.
; ResetPhonemeModifier does NOT clear the expression channel, so _ClearExpression also zeroes expression.
; Moods: happy, angry, afraid, sad, pained, surprised, confused.
; Apply one MFG value scaled by fExpressionIntensity (0.0-1.0).  Keeps the AEP proportions but
; dials the whole face down so it isn't maxed/exaggerated.  Clamped to 0-100.
Function _mfgX(Actor akActor, Int mode, Int id, Int base)
    Float s = fExpressionIntensity
    If s < 0.0
        s = 0.0
    ElseIf s > 1.0
        s = 1.0
    EndIf
    Int v = (base * s) as Int
    MfgConsoleFunc.SetPhonemeModifier(akActor, mode, id, v)
EndFunction

Function _ApplyMoodExpression(Actor akActor, String mood)
    If !akActor
        Return
    EndIf
    ; MFG face-morph expressions only work on humanoid face rigs — creatures (wolves, trolls, spiders,
    ; etc.) don't have MFG-compatible faces at all. Fixed here rather than only in Express_Execute since
    ; this is called directly from several narrative beats too (_Bleedout, Struggle_Execute) that could
    ; target a downed/struggling creature victim.
    If _IsCreatureActor(akActor)
        Return
    EndIf
    MfgConsoleFunc.ResetPhonemeModifier(akActor)
    If mood == "happy"
        _mfgX(akActor, 2, 2, 40)
        _mfgX(akActor, 1, 3, 50)
    ElseIf mood == "angry"
        _mfgX(akActor, 2, 0, 100)
        _mfgX(akActor, 1, 5, 50)
        _mfgX(akActor, 1, 6, 40)
    ElseIf mood == "afraid"
        _mfgX(akActor, 2, 1, 100)
        _mfgX(akActor, 0, 6, 100)
        _mfgX(akActor, 0, 7, 100)
        _mfgX(akActor, 0, 14, 70)
    ElseIf mood == "sad"
        _mfgX(akActor, 2, 11, 100)
        _mfgX(akActor, 0, 2, 50)
        _mfgX(akActor, 0, 3, 30)
        _mfgX(akActor, 0, 4, 50)
        _mfgX(akActor, 0, 5, 50)
        _mfgX(akActor, 0, 8, 90)
    ElseIf mood == "pained"
        _mfgX(akActor, 2, 8, 100)
        _mfgX(akActor, 0, 0, 50)
        _mfgX(akActor, 0, 1, 50)
        _mfgX(akActor, 0, 2, 100)
        _mfgX(akActor, 0, 3, 100)
        _mfgX(akActor, 0, 4, 100)
        _mfgX(akActor, 0, 5, 100)
        _mfgX(akActor, 0, 15, 60)
        _mfgX(akActor, 1, 0, 70)
        _mfgX(akActor, 1, 1, 70)
    ElseIf mood == "surprised"
        _mfgX(akActor, 2, 4, 100)
        _mfgX(akActor, 0, 14, 100)
        _mfgX(akActor, 0, 15, 50)
    ElseIf mood == "confused"
        _mfgX(akActor, 2, 5, 100)
    Else
        _Log("[SNBaka] _ApplyMoodExpression: unknown mood '" + mood + "'")
        Return
    EndIf
    _Log("[SNBaka] _ApplyMoodExpression: " + mood + " on " + akActor.GetDisplayName() + " (intensity " + fExpressionIntensity + ")")
EndFunction

Function _ClearExpression(Actor akActor)
    If !akActor
        Return
    EndIf
    MfgConsoleFunc.ResetPhonemeModifier(akActor)   ; clears phonemes + modifiers
    MfgConsoleFunc.SetPhonemeModifier(akActor, 2, 0, 0)  ; expression channel off
EndFunction

; LLM-triggered: apply a mood, hold ~6s, then clear.  A per-actor sequence counter means a newer
; expression (or a fresh trigger) won't be wiped early by an older hold's timer.
Function _HoldMoodExpression(Actor akActor, String mood)
    If !bExpressionsEnabled || !akActor
        Return
    EndIf
    _ApplyMoodExpression(akActor, mood)
    Int seq = StorageUtil.GetIntValue(akActor, "SNBaka.ExprSeq", 0) + 1
    StorageUtil.SetIntValue(akActor, "SNBaka.ExprSeq", seq)
    Utility.Wait(6.0)
    If StorageUtil.GetIntValue(akActor, "SNBaka.ExprSeq", 0) == seq
        _ClearExpression(akActor)
    EndIf
EndFunction

; --- SkyrimNet expression action (speaker emotes; target is ignored) ---
; Single parameterized action replacing the old one-yaml-per-mood set (happy/angry/afraid/sad/
; pained/surprised/confused). _ApplyMoodExpression silently no-ops on an unrecognized mood string.
Function Express_Execute(Actor akInitiator, Actor akTarget, String mood)
    _ActionLaneFire(akInitiator, akTarget, "Express") ; [REV-174f Leg 4.2] neutral fanned lane (LLM/player-initiated; daemon fires suppressed)
    _Log("[SNBakaACT] Express ENTER mood=" + mood)
    ; Same class of gap fixed in _PlaySoloHold: a bare facial expression is otherwise LLM-invisible --
    ; nothing ever told SkyrimNet this happened. Solo (matches the doc comment: "target is ignored").
    If akInitiator && bExpressionsEnabled
        SkyrimNetApi.RegisterEvent("baka_pose", \
            akInitiator.GetDisplayName() + "'s face shows " + mood + ".", akInitiator, None)
    EndIf
    _HoldMoodExpression(akInitiator, mood)
EndFunction


; --- PlayPairedLoopAnim ---
; Start → Loop → Cleanup. A1 is the initiator, A2 is the target.
;
; sResistA1/A2 : animation played on A1/A2 during the resist window.
;   Defaults to the generic Babo_DefeatResist struggle loop.
;   Pass action-specific resist anims (e.g. SLAPForcedKiss01_A1_Resist)
;   when the animation set has its own resist pair.
; sStopA1/A2   : animation played when the player successfully escapes.
;   Defaults to Babo_DefeatResist_A1/A2_S2 (the break-free animation).
Function PlayPairedLoopAnim(Actor akA1, Actor akA2, \
        Float xLocal, Float yLocal, Float rotOffset, \
        String startA1, String startA2, \
        String loopA1,  String loopA2, \
        Float startWait, Float loopDur, \
        Bool bResistable = False, \
        String sResistA1 = "Babo_DefeatResist_A1_S1", \
        String sResistA2 = "Babo_DefeatResist_A2_S1", \
        String sStopA1   = "Babo_DefeatResist_A1_S2", \
        String sStopA2   = "Babo_DefeatResist_A2_S2", \
        Actor akImpactActor = None, \
        Bool bDisableCollision = True, \
        Bool bRefreshLoop = False)

    Bool a1IsPlayer = (akA1 == PlayerRef)
    Bool a2IsPlayer = (akA2 == PlayerRef)

    If a1IsPlayer || a2IsPlayer
        Game.DisablePlayerControls(True, True, False, False, True, False, False, False)
        ; (No SetDontMove on the player — it locked the camera. The NPC is ghosted so it can't
        ; shove the player, and the player isn't ghosted so they won't fall; no pin needed.)
    EndIf

    ObjectReference marker1 = None
    ObjectReference marker2 = None
    If XMarkerBase
        marker1 = akA2.PlaceAtMe(XMarkerBase, 1, False, False)
        marker2 = akA2.PlaceAtMe(XMarkerBase, 1, False, False)
    EndIf

    ; New model: attacker is the origin, NPC attacker teleports onto the victim, victim placed at the
    ; (xLocal=R/L, yLocal=F/B, rotOffset) offset; player never teleported; hard AI stop + pin. See _SetupPair.
    ; sFn = the start-anim name; it is ALSO the SNBaka_Offsets.ini key for this anim's offsets.
    _SetupPair(akA1, akA2, xLocal, yLocal, rotOffset, bDisableCollision, marker1, marker2, startA1)
    Debug.SendAnimationEvent(akA1, startA1)
    Debug.SendAnimationEvent(akA2, startA2)
    Bool aborted = _WaitOrAbort(akA1, akA2, startWait, 0.25)

    If !aborted && akImpactActor != None
        PlaySmackSound(akImpactActor)
    EndIf

    If !aborted
        If loopA1 != ""
            Debug.SendAnimationEvent(akA1, loopA1)
        EndIf
        If loopA2 != ""
            Debug.SendAnimationEvent(akA2, loopA2)
        EndIf

        ; The pose to RE-ASSERT during waits/QTE so an actor that drifts off snaps back: the loop anim
        ; if there is one, else the START anim. Grab-hold (BackHugMolest) passes EMPTY loops — it's a
        ; FNIS sequence that auto-chains from its START, so we must re-assert the START (re-sending the
        ; loop event kicks it out). Without this, grab-hold had nothing to re-assert and the NPC froze.
        String holdA1 = loopA1
        If holdA1 == ""
            holdA1 = startA1
        EndIf
        String holdA2 = loopA2
        If holdA2 == ""
            holdA2 = startA2
        EndIf

        If bResistable && bResistEnabled && (a1IsPlayer || a2IsPlayer)
            SkyrimNetApi.RegisterEvent("baka_resist_start", \
                akA2.GetDisplayName() + " struggles to break free from " + akA1.GetDisplayName() + ".", \
                akA1, akA2)

            Bool escaped = _PollResist(akA1, akA2, loopDur, sResistA1, sResistA2, holdA1, holdA2)
            _Log("[SNBaka] LoopAnim: _PollResist done. escaped=" + escaped + " _bQTEDefeated=" + _bQTEDefeated)

            If escaped
                Debug.SendAnimationEvent(akA1, sStopA1)
                Debug.SendAnimationEvent(akA2, sStopA2)
                SkyrimNetApi.RegisterEvent("baka_resist_success", \
                    akA2.GetDisplayName() + " breaks free from " + akA1.GetDisplayName() + ".", \
                    akA1, akA2)
                _OnVictimWon(akA2, akA1)
                Utility.Wait(1.5)
            ElseIf !_bQTEDefeated && !_ShouldAbort(akA1, akA2)
                _WaitOrAbort(akA1, akA2, loopDur * 0.4)
            EndIf
        ElseIf bResistable
            ; NPC-vs-NPC resistable loop (e.g. BackHugMolest): play the loop out, THEN resolve like
            ; the staged scenes — so it never just ends with no finish. Victim escapes -> break-free
            ; anim; attacker wins -> flag defeat so the caller runs the ground/escalation window.
            _bAELVictimEscaped = (Utility.RandomFloat(0.0, 99.9) < fNPCEscapeChance)
            _HoldAnim(akA1, akA2, holdA1, holdA2, loopDur)
            If !_ShouldAbort(akA1, akA2)
                If _bAELVictimEscaped
                    Debug.SendAnimationEvent(akA1, sStopA1)
                    Debug.SendAnimationEvent(akA2, sStopA2)
                    _WaitOrAbort(akA1, akA2, 1.5)
                Else
                    _bQTEDefeated = True   ; caller's If _bQTEDefeated -> DefeatGroundWindow
                EndIf
            EndIf
        Else
            ; Non-resistable: FREEZE both actors on the pose for the full duration — re-asserted each
            ; tick so a short/one-shot clip or an idle replacer can't drop them out. (Re-assert is now
            ; the default; the bRefreshLoop flag is kept only for call-site compatibility.)
            _HoldAnim(akA1, akA2, holdA1, holdA2, loopDur)
        EndIf
    EndIf

    _CleanupPair(akA1, akA2, marker1, marker2, a1IsPlayer || a2IsPlayer, _bQTEDefeated)
EndFunction

; --- PlayPairedSimpleAnim ---
; Single animation with no explicit loop event. Duration is the total hold time.
; If bResistable, substitutes Babo_DefeatResist_A1/A2_S1 for the resist window.
; On escape → S2 cleanup. On fail → plays original anim for remaining time.
Function PlayPairedSimpleAnim(Actor akA1, Actor akA2, \
        Float xLocal, Float yLocal, Float rotOffset, \
        String animA1, String animA2, Float duration, \
        Bool bResistable = False, \
        Bool bDisableCollision = True, \
        Bool abMoanAtMid = False)

    Bool a1IsPlayer = (akA1 == PlayerRef)
    Bool a2IsPlayer = (akA2 == PlayerRef)

    If a1IsPlayer || a2IsPlayer
        Game.DisablePlayerControls(True, True, False, False, True, False, False, False)
        ; (No SetDontMove on the player — it locked the camera. The NPC is ghosted so it can't
        ; shove the player, and the player isn't ghosted so they won't fall; no pin needed.)
    EndIf

    ObjectReference marker1 = None
    ObjectReference marker2 = None
    If XMarkerBase
        marker1 = akA2.PlaceAtMe(XMarkerBase, 1, False, False)
        marker2 = akA2.PlaceAtMe(XMarkerBase, 1, False, False)
    EndIf

    ; New attacker-anchored placement + hard AI stop + pin (see _SetupPair). animA1 = the SNBaka_Offsets.ini key.
    _SetupPair(akA1, akA2, xLocal, yLocal, rotOffset, bDisableCollision, marker1, marker2, animA1)
    Debug.SendAnimationEvent(akA1, animA1)
    Debug.SendAnimationEvent(akA2, animA2)

    If bResistable && bResistEnabled && (a1IsPlayer || a2IsPlayer)
        SkyrimNetApi.RegisterEvent("baka_resist_start", \
            akA2.GetDisplayName() + " struggles to break free from " + akA1.GetDisplayName() + ".", \
            akA1, akA2)

        Bool escaped = _PollResist(akA1, akA2, duration, "Babo_DefeatResist_A1_S1", "Babo_DefeatResist_A2_S1", animA1, animA2)
        _Log("[SNBaka] SimpleAnim: _PollResist done. escaped=" + escaped + " _bQTEDefeated=" + _bQTEDefeated)

        If escaped
            Debug.SendAnimationEvent(akA1, "Babo_DefeatResist_A1_S2")
            Debug.SendAnimationEvent(akA2, "Babo_DefeatResist_A2_S2")
            SkyrimNetApi.RegisterEvent("baka_resist_success", \
                akA2.GetDisplayName() + " breaks free from " + akA1.GetDisplayName() + ".", \
                akA1, akA2)
            _OnVictimWon(akA2, akA1)
            Utility.Wait(1.0)
        ElseIf !_bQTEDefeated && !_ShouldAbort(akA1, akA2)
            _WaitOrAbort(akA1, akA2, duration * 0.5)
        EndIf
    ElseIf abMoanAtMid
        ; Play the moan ~halfway through (near the Babo impact); freeze the pose either side.
        Float half = duration * 0.5
        If !_HoldAnim(akA1, akA2, animA1, animA2, half)
            _PlaySpankMoanOnly(akA2)
            _HoldAnim(akA1, akA2, animA1, animA2, duration - half)
        EndIf
    ElseIf bResistable
        ; The resistable branch above is skipped whenever bResistEnabled is off (or neither actor is
        ; the player) -- confirmed live gap: Subdue used this path with bResistEnabled off and just
        ; held the pose, leaving _bQTEDefeated/_bAELVictimEscaped BOTH False forever, so no caller's
        ; win/lose check ever fired either way. PlayPairedSequence's own no-QTE fallback already
        ; resolves a winner via fNPCEscapeChance instead of leaving it ambiguous -- mirror that here.
        If !_HoldAnim(akA1, akA2, animA1, animA2, duration)
            If Utility.RandomFloat(0.0, 99.9) < fNPCEscapeChance
                ; Set the escape flag too (PlayPairedSequence's fallback already does) -- without it
                ; the caller's outcome branch reads this break-free as "attacker won" and runs
                ; _RecoveryPeriod on the escapee, and the escape tail below never releases them.
                _bAELVictimEscaped = True
                Debug.SendAnimationEvent(akA1, "Babo_DefeatResist_A1_S2")
                Debug.SendAnimationEvent(akA2, "Babo_DefeatResist_A2_S2")
                SkyrimNetApi.RegisterEvent("baka_resist_success", \
                    akA2.GetDisplayName() + " breaks free from " + akA1.GetDisplayName() + ".", \
                    akA1, akA2)
                _OnVictimWon(akA2, akA1)
            Else
                _bQTEDefeated = True
            EndIf
        EndIf
    Else
        ; Freeze both actors on the pose for the whole duration (re-asserted each tick).
        _HoldAnim(akA1, akA2, animA1, animA2, duration)
    EndIf

    ; _CleanupPair clears _bMidCombatGrappleActive -- capture it first for the escape tail below.
    Bool simpleWasMidCombat = _bMidCombatGrappleActive
    _CleanupPair(akA1, akA2, marker1, marker2, a1IsPlayer || a2IsPlayer, _bQTEDefeated)
    ; MISSING ESCAPE TAIL (confirmed live: "actor stuck non-aggressive and nothing targeted her") --
    ; PlayPairedSequence ends a victim escape with _PostEscapeGrace, the ONE place the Acheron
    ; native two-way pacify _SetupPair put on an NPC victim (keyword-backed state only Acheron's own
    ; API can remove) is released for a winner. This runner never did, so every simple-anim escapee
    ; (Subdue) kept "ignoring & ignored by combat" FOREVER. Mid-combat grapple: skip the mercy
    ; window (an escaped enemy resumes the fight immediately, no 5s untouchable beat) but the pacify
    ; still must end -- release it directly.
    If _bAELVictimEscaped
        If simpleWasMidCombat
            _ReleaseAcheronPacify(akA2)
        Else
            _PostEscapeGrace(akA2)
        EndIf
    EndIf
EndFunction

; --- PlayPairedSequence ---
; Multi-stage: animsA1[i] / animsA2[i] in order, each held stageTimer seconds.
;
; If bResistable and player is A2:
;   A2 holds Babo_DefeatResist_A2_S1 throughout (the struggle loop).
;   A1 still advances through each stage animation normally.
;   Player can escape at any point during any stage.
;   This allows the NPC to visually escalate while the player fights back.
; Confirmed in live testing: a completely unrelated mod (SkyrimNet_PairedAnimations) can have the
; player's OWN follower "ExecuteTarget" (a scripted kill-move) the player mid-struggle, because that
; mod's eligibility check never considers allegiance at all — any actor is "eligible" against any
; target. We can't fix another mod's code from here, but AddPackageOverride's priority-100 hold already
; blocks every OTHER package/AI-driven behavior from being assigned to an actor while it's active — so
; forcing that same hold onto nearby teammates for the duration of OUR OWN scenes should keep them from
; being hijacked into a kill-scene package by anything else, regardless of what that other mod's
; eligibility logic does or doesn't check.
; akAggressor: the OTHER member of THIS pair (the attacker/creature) — excluded from the sweep below
; (it's handled separately by _SetupPair), never touched otherwise.
; Every OTHER nearby actor (any NPC or creature, ally or hostile, human or beast) is held off combat
; for the duration -- a "cloak of calm" so the pair is effectively ignored by anyone not actually
; involved, without literally turning them invisible. The player is the sole exception: never held,
; always free to interject or be interjected upon. Any hit that DOES land despite this (the player,
; or anything that slips past) still aborts the struggle/scene as normal -- this only stops OTHER
; actors from choosing to start something, it doesn't make the pair invulnerable.
; [REV-161 PR#2 fold (6) - Oldcustard credit, by-concept] THREATS-ONLY MODE:
; abFull=True (the default, the historic behavior) freezes every bystander in
; range; abFull=False holds ONLY actors actually hostile to the pair -- the
; full freeze stopped unrelated NPCs mid-life across the loaded area in
; NPC-grapples and creature struggles. Threaded threats-only through the
; struggle/QTE hold sites; release calls are unaffected (releasing a
; never-held actor is a no-op).
; [REV-177 item 3 - Oldcustard credit, issue #2: targeted-threat hold]
; True only for an actor that is an actual threat TO THE VICTIM (akCenter):
; locked onto them, or hostile with no current target (lock just cleared).
; Player teammates are never threats here -- the old fold's "hostile to the
; aggressor" half matched EVERY follower fighting the aggressor (the abFull=False
; fold diverged from the PR's intent: whole-party DoNothing freeze on every
; NPC-only grab). A teammate flag alone is unreliable (SeverActions-managed
; followers), so the combat-target test carries the decision instead.
Bool Function _IsTargetedThreat(Actor a, Actor akCenter)
    If a.IsPlayerTeammate()
        Return False
    EndIf
    Actor tgt = a.GetCombatTarget()
    Return tgt == akCenter || (!tgt && a.IsHostileToActor(akCenter))   ; locked on, or lock just cleared
EndFunction

Function _ProtectNearbyAllies(Actor akCenter, Actor akAggressor, Bool abHold, Bool abFull = True)
    If !akCenter
        Return
    EndIf
    ; LOADED-AREA enumeration (po3), same fix as the creature/companion scans: the old single-cell
    ; sweep + single-closest supplement missed everything registered in a linked cell — confirmed
    ; live yet again with giants aggroing straight through a "protected" QTE from the next cell over.
    ; Hold is radius-capped so a whole loaded exterior doesn't get frozen; RELEASE is uncapped so a
    ; held actor can never be stranded in DoNothing by positional drift (releasing a never-held actor
    ; is a no-op).
    Actor[] loaded = PO3_SKSEFunctions.GetActorsByProcessingLevel(0)
    Int held = 0
    Int i = 0
    While i < loaded.Length
        Actor a = loaded[i]
        If a && a != akCenter && a != akAggressor && a != PlayerRef && !a.IsDead() && (!abHold || a.GetDistance(akCenter) <= 3000.0) && (!abHold || abFull || _IsTargetedThreat(a, akCenter))
            _HoldActorAI(a, abHold)
            ; Deliberately NO calm/pacify on bystanders — a cloak here stopped UNRELATED fights nearby
            ; (correct objection from testing). The victim-side calm in _ProtectVictimTargeting is what
            ; makes attackers drop the pair (SL Defeat / Surrender pattern: the calm goes ON the fallen
            ; actor, and combat AI treats a calmed actor as an invalid target). Once an attacker loses
            ; its only target and exits combat, THIS hold is what keeps it from wandering back in
            ; (package overrides can't grip an actor still in combat — combat AI outranks packages).
            If abHold
                held += 1
                ; (No per-actor trace — a den's worth of Debug.Trace lines per hold, each recomputing
                ; hostility/distance just for the log, was real VM load on an already-starved setup.
                ; The summary below says how many; _PacifyActor still traces the transitions.)
            EndIf
        EndIf
        i += 1
    EndWhile
    If abHold
        _Log("[SNBaka] _ProtectNearbyAllies: " + held + " actor(s) held+calmed around " + akCenter.GetDisplayName())
    Else
        _Log("[SNBaka] _ProtectNearbyAllies: released holds/calms around " + akCenter.GetDisplayName())
    EndIf
EndFunction

Function PlayPairedSequence(Actor akA1, Actor akA2, \
        Float xLocal, Float yLocal, Float rotOffset, \
        String[] animsA1, String[] animsA2, Float stageTimer, \
        Bool bResistable = False, \
        Bool bDisableCollision = True, \
        Float afA1Stage0Rot = 0.0)

    Bool a1IsPlayer = (akA1 == PlayerRef)
    Bool a2IsPlayer = (akA2 == PlayerRef)

    If a1IsPlayer || a2IsPlayer
        Game.DisablePlayerControls(True, True, False, False, True, False, False, False)
        ; (No SetDontMove on the player — it locked the camera. The NPC is ghosted so it can't
        ; shove the player, and the player isn't ghosted so they won't fall; no pin needed.)
    EndIf
    ; Not gated on player involvement — a nearby teammate can be hijacked into attacking whoever's
    ; downed regardless of whether the player is one of the two actors in THIS pairing.
    _ProtectNearbyAllies(akA2, akA1, True, False)
    ; Reset the escape flag unconditionally, not just inside the resistable branch below -- a
    ; NON-resistable sequence used to leave whatever value the PREVIOUS struggle set, and the
    ; post-escape grace at the bottom of this function keys off it.
    _bAELVictimEscaped = False

    ; In-combat grapple takedown: fSequenceStageTimer (4.0s default) times how long EACH of a
    ; multi-stage sequence's stages holds -- fine pacing for a leisurely non-combat struggle, but a
    ; 5-stage sequence at the default pays up to 20s of sequential holds with no way for the fallback
    ; (no-AEL-addon) path to resolve any faster, confirmed live as "takes far too long" for a mode
    ; whose whole point is a fast, decisive mid-fight takedown. Every stageTimer use below reads this
    ; local instead of the raw parameter; untouched for every other (non-mid-combat) caller.
    Float effStageTimer = stageTimer
    If _bMidCombatGrappleActive
        effStageTimer = 1.0
    EndIf

    ObjectReference marker1 = None
    ObjectReference marker2 = None
    If XMarkerBase
        marker1 = akA2.PlaceAtMe(XMarkerBase, 1, False, False)
        marker2 = akA2.PlaceAtMe(XMarkerBase, 1, False, False)
    EndIf

    ; New attacker-anchored placement + hard AI stop + pin (see _SetupPair). animsA1[0] = the SNBaka_Offsets.ini key.
    _SetupPair(akA1, akA2, xLocal, yLocal, rotOffset, bDisableCollision, marker1, marker2, animsA1[0])
    If bResistable && bResistEnabled && (a1IsPlayer || a2IsPlayer)
        SkyrimNetApi.RegisterEvent("baka_resist_start", \
            akA2.GetDisplayName() + " struggles to break free from " + akA1.GetDisplayName() + ".", \
            akA1, akA2)

        _bAELStruggleComplete = False
        _bAELVictimEscaped    = False
        _bPlayerIsVictim      = a2IsPlayer
        RegisterForModEvent("AEL_GameEnd", "OnAELGameEnd")

        ; Both actors start at stage 0. A1 and A2 advance in sync while QTE runs.
        Debug.SendAnimationEvent(akA1, animsA1[0])
        Debug.SendAnimationEvent(akA2, animsA2[0])

        Bool escaped = False
        Bool aborted = False

        ; fQTEStartDelay: lets stage 0 settle visually and — critically — gives Skyrim's
        ; UI time to finish closing the Interact message box. SPE_Interface.OpenCustomMenu
        ; (used inside MakeGame) returns False if called while the UI is still transitioning
        ; after Message.Show(), which is why Struggle/ChokeHug showed no QTE overlay. Same
        ; mid-combat-grapple override as _PollResist -- see that function's own comment.
        Float effQTEStartDelay = fQTEStartDelay
        If _bMidCombatGrappleActive
            effQTEStartDelay = 0.3
        EndIf
        If effQTEStartDelay > 0.0
            aborted = _WaitOrAbort(akA1, akA2, effQTEStartDelay)
        EndIf

        Bool ael_ok = False
        If !aborted
            _Log("[SNBaka] PlayPairedSequence: starting QTE. A1=" + akA1.GetDisplayName() + " A2=" + akA2.GetDisplayName())
            ael_ok = AELStruggle.MakeGame(fResistDifficulty)
            _Log("[SNBaka] PlayPairedSequence: MakeGame returned " + ael_ok)
        EndIf

        If ael_ok
            Float stageElapsed = 0.0
            Float sinceRe = 0.0
            Float tick = 0.1
            ; +40 not +10: while the AEL minigame runs it owns the pacing (see _PollResist's
            ; identical fix) -- the stage-time budget alone cut the still-running Flash game off
            ; mid-QTE once the real-clock fix made this cap actually accurate.
            Float maxWait = effStageTimer * animsA1.Length + 40.0
            Int stageIdx = 0
            ; Hold stage 0 for the ENTIRE QTE — no longer advances stages on stageTimer while the
            ; struggle is still undecided. That used to let the visible pose drift completely out of
            ; sync with the actual QTE outcome (the animation could already be 2-3 stages further along
            ; than what the minigame had actually resolved). Stages now only ever advance AFTER the QTE
            ; completes, branching into the win/lose resolution below — the same pattern the timed
            ; (non-QTE) fallback further down already uses for NPC-vs-NPC.
            ; Real-clock elapsed, not a naive tick counter -- see _WaitOrAbort's comment (confirmed
            ; live: an identical loop in _PollResist logged a 2.2s window that actually ran 9s under
            ; concurrent VM load).
            Float startRT = Utility.GetCurrentRealTime()
            While !_bAELStruggleComplete && !aborted && (Utility.GetCurrentRealTime() - startRT) < maxWait
                Utility.Wait(tick)
                stageElapsed += tick
                sinceRe      += tick
                If _ShouldAbort(akA1, akA2)
                    aborted = True
                EndIf
                If !aborted && sinceRe >= 2.0
                    ; Re-assert stage 0 ~every 2s so PC-NPC actors can't drift/freeze mid-QTE.
                    sinceRe = 0.0
                    Debug.SendAnimationEvent(akA1, animsA1[stageIdx])
                    Debug.SendAnimationEvent(akA2, animsA2[stageIdx])
                EndIf
            EndWhile
            ; If poll timed out while Flash QTE is still open, force-close the menu.
            If !_bAELStruggleComplete
                SPE_Interface.CloseCustomMenu()
                Utility.Wait(0.3)
            EndIf
            escaped = _bAELStruggleComplete && _bAELVictimEscaped
            _Log("[SNBaka] PlayPairedSequence: QTE done. complete=" + _bAELStruggleComplete + " escaped=" + escaped)
            If _bAELStruggleComplete && !escaped
                _bQTEDefeated = True
                ; Finish remaining time in the current stage first.
                Float stageRemain = effStageTimer - stageElapsed
                If stageRemain > 0.05 && !_ShouldAbort(akA1, akA2)
                    _WaitOrAbort(akA1, akA2, stageRemain)
                EndIf
                Int lastIdx = animsA1.Length - 1
                Int starIdx = lastIdx - 1
                If starIdx > 0 && stageIdx < starIdx && !_ShouldAbort(akA1, akA2)
                    stageIdx = starIdx
                    Debug.SendAnimationEvent(akA1, animsA1[stageIdx])
                    Debug.SendAnimationEvent(akA2, animsA2[stageIdx])
                    _WaitOrAbort(akA1, akA2, effStageTimer)
                EndIf
            EndIf
        Else
            ; Timed sequence. Random outcome only when NEITHER actor is the player —
            ; player-involved cases rely on the QTE; if MakeGame failed, play all stages
            ; with no forced outcome (interaction just ends cleanly).
            Bool npcEscaped = bResistable && !aborted && !a1IsPlayer && !a2IsPlayer \
                && (Utility.RandomFloat(0.0, 99.9) < fResistDifficulty)
            Int stagesPlay = animsA1.Length
            If npcEscaped && animsA1.Length > 1
                stagesPlay = animsA1.Length / 2 + 1  ; roughly first half before break-free
            EndIf
            Int fi = 0
            While fi < stagesPlay && !aborted
                Debug.SendAnimationEvent(akA1, animsA1[fi])
                Debug.SendAnimationEvent(akA2, animsA2[fi])
                If _WaitOrAbort(akA1, akA2, effStageTimer)
                    aborted = True
                EndIf
                fi += 1
            EndWhile
            If !aborted
                If npcEscaped
                    _Log("[SNBaka] PlayPairedSequence: NPC random — victim escapes")
                    _bAELVictimEscaped = True
                    Debug.SendAnimationEvent(akA1, "Babo_DefeatResist_A1_S2")
                    Debug.SendAnimationEvent(akA2, "Babo_DefeatResist_A2_S2")
                    Utility.Wait(1.5)
                ElseIf bResistable
                    _Log("[SNBaka] PlayPairedSequence: NPC random — attacker wins")
                    _bQTEDefeated = True
                EndIf
            EndIf
        EndIf

        UnregisterForModEvent("AEL_GameEnd")

        If escaped
            ; Play the anim's OWN final stage (its break-free), then free the actors quickly — 1.5s is
            ; enough for the break-free to read; 3.5 left them frozen ~2s too long after it ended.
            Int li2 = animsA1.Length - 1
            Debug.SendAnimationEvent(akA1, animsA1[li2])
            Debug.SendAnimationEvent(akA2, animsA2[li2])
            SkyrimNetApi.RegisterEvent("baka_resist_success", \
                akA2.GetDisplayName() + " breaks free from " + akA1.GetDisplayName() + ".", \
                akA1, akA2)
            _OnVictimWon(akA2, akA1)
            _WaitOrAbort(akA1, akA2, 1.5)
        EndIf
    Else
        ; Normal sequence — NPC-NPC (no QTE).
        If !bResistable
            ; Non-resistable paired sequence: just play every stage straight through.
            Float a1BaseAng = akA1.GetAngleZ()   ; base facing from _SetupPair, for the optional stage-0 flip
            Int i = 0
            While i < animsA1.Length && !_ShouldAbort(akA1, akA2)
                ; Some clips author stage 0 with the ATTACKER turned (Investigation): force akA1
                ; +afA1Stage0Rot on stage 0 only, restore base facing from stage 1 onward.
                If afA1Stage0Rot != 0.0
                    If i == 0
                        akA1.SetAngle(0.0, 0.0, a1BaseAng + afA1Stage0Rot)
                    ElseIf i == 1
                        akA1.SetAngle(0.0, 0.0, a1BaseAng)
                    EndIf
                    _HoldPinned(akA1)
                EndIf
                ; Freeze the actors on this stage for its whole duration (re-asserted each tick).
                _HoldAnim(akA1, akA2, animsA1[i], animsA2[i], effStageTimer)
                i += 1
            EndWhile
        Else
            ; FORCED anim rule (Struggle, ChokeHug, any resistable staged anim). The clip has
            ; several stages: the LAST is the victim breaking free, the LAST-MINUS-ONE is the
            ; attacker's victory pose. Play the shared middle stages (everything before the
            ; deciding stage) at fNPCStageTime each, then show the deciding stage:
            ;   attacker win -> last-minus-one (victor),   victim win -> last (break-free).
            Bool npcEscaped = (Utility.RandomFloat(0.0, 99.9) < fNPCEscapeChance)
            Int lastIdx = animsA1.Length - 1
            Int penult  = lastIdx - 1
            If penult < 0
                penult = 0
            EndIf
            ; Shared middle stages 0 .. penult-1 (stop before the deciding stage).
            Int i = 0
            While i < penult && !_ShouldAbort(akA1, akA2)
                _HoldAnim(akA1, akA2, animsA1[i], animsA2[i], fNPCStageTime)
                i += 1
            EndWhile
            ; [REV-161 PR#2 fold (7) - Oldcustard credit, by-concept] INTERRUPTED
            ; STRUGGLE = VICTIM FREED: an abort before the deciding stage used to
            ; leave BOTH outcome flags unset, and every reader defaulted to
            ; attacker-win (the interruption miscued as an overpowered defeat).
            ; An aborted grip means the victim got away.
            If _ShouldAbort(akA1, akA2)
                _bAELVictimEscaped = True
                _Log("[SNBaka] PlayPairedSequence: NPC-resistable struggle aborted mid-sequence -- victim-freed (REV-161 PR#2 fold 7)")
            EndIf
            If !_ShouldAbort(akA1, akA2)
                If npcEscaped && animsA1.Length > 1
                    ; Victim wins: skip the victor stage, play the break-free LAST stage directly.
                    _HoldAnim(akA1, akA2, animsA1[lastIdx], animsA2[lastIdx], fNPCStageTime)
                    _bAELVictimEscaped = True
                    SkyrimNetApi.RegisterEvent("baka_resist_success", \
                        akA2.GetDisplayName() + " breaks free from " + akA1.GetDisplayName() + ".", \
                        akA1, akA2)
                    _OnVictimWon(akA2, akA1)
                Else
                    ; Attacker wins: play the LAST-MINUS-ONE (victor) stage, then flag defeat.
                    _HoldAnim(akA1, akA2, animsA1[penult], animsA2[penult], fNPCStageTime)
                    _bQTEDefeated = True   ; -> DefeatGroundWindow / escalation
                EndIf
            EndIf
        EndIf
    EndIf

    _ProtectNearbyAllies(akA2, akA1, False)
    ; _CleanupPair clears _bMidCombatGrappleActive -- capture it first for the escape tail below.
    Bool seqWasMidCombat = _bMidCombatGrappleActive
    _CleanupPair(akA1, akA2, marker1, marker2, a1IsPlayer || a2IsPlayer, _bQTEDefeated)
    ; The victim WON -- keep them untouchable a while longer (see _PostEscapeGrace). Must run AFTER
    ; _CleanupPair, whose unconditional SetGhost(False) would wipe it. Mid-combat grapple: no mercy
    ; window (the escaped enemy resumes the fight immediately), but the Acheron pacify from
    ; _SetupPair still must end -- release it directly.
    If _bAELVictimEscaped
        If seqWasMidCombat
            _ReleaseAcheronPacify(akA2)
        Else
            _PostEscapeGrace(akA2)
        EndIf
    EndIf
EndFunction

; --- _CleanupPair ---
; Resets both actors: removes vehicles, restrained/ghost flags,
; re-enables player controls if involved, evaluates packages,
; and deletes position markers.
; bSkipA2Reset: when True, omits IdleForceDefaultState and EvaluatePackage on A2.
; Pass True when A2 is about to enter bleedout — keeps them in their final pose
; until KnockDown fires so they never briefly "stand up" before collapsing.
; ---- Keep-alive pin (DOM Snap) --------------------------------------------------------
; A near-zero, very-slow TranslateTo holds the actor at its current spot + facing for ~100s,
; so animation root-motion or a shove can't drift it off its fixed marker. Each actor is
; pinned to its OWN marker (we can't share one — our Baka Motion anims are authored for an
; offset layout, not co-origin), so neither can push the other. StopTranslation in
; _CleanupPair / _EscalationCleanup ends the hold. Never the player (never force-move them).
Function _HoldPinned(Actor ak)
    If ak && ak != PlayerRef
        ak.TranslateTo(ak.GetPositionX(), ak.GetPositionY(), ak.GetPositionZ(), \
                       0.0, 0.0, ak.GetAngleZ() + 0.01, 500.0, 0.0001)
    EndIf
EndFunction

; ---- Height-matching (DOM ScaleActorToOther) ------------------------------------------
; Paired anims align best when both actors are the same height. We scale the NON-player
; actor to its partner's scale for the duration, storing the original so _CleanupPair /
; _EscalationCleanup can restore it. Tracked in the SNBaka.ScaledActors formlist so the
; game-time heartbeat can sweep up any actor left resized by a save-mid-animation reload.
; Never scales the player. Only acts on a meaningful (>2%) difference.
Function _MatchPairHeight(Actor akA1, Actor akA2)
    If !bMatchHeight
        Return
    EndIf
    Actor scaleMe = None
    Actor refActor = None
    If akA1 != PlayerRef
        scaleMe  = akA1
        refActor = akA2
    ElseIf akA2 != PlayerRef
        scaleMe  = akA2
        refActor = akA1
    EndIf
    If !scaleMe || !refActor
        Return
    EndIf
    ; Only scale when both actors are fully loaded — SetScale on an unloaded actor can fault.
    If !scaleMe.Is3DLoaded() || !refActor.Is3DLoaded()
        Return
    EndIf
    ; If a previous run left this actor scaled (unclean exit), restore before re-measuring.
    _RestoreActorScale(scaleMe)
    Float cur = scaleMe.GetScale()
    Float ref = refActor.GetScale()
    If ref <= 0.0 || cur <= 0.0
        Return
    EndIf
    Float ratio = ref / cur
    If ratio > 1.02 || ratio < 0.98
        StorageUtil.SetFloatValue(scaleMe, "SNBaka.OrigScale", cur)
        StorageUtil.FormListAdd(Self, "SNBaka.ScaledActors", scaleMe, False)
        scaleMe.SetScale(ref)
        _Log("[SNBaka] HeightMatch: " + scaleMe.GetDisplayName() + " " + cur + " -> " + ref)
    EndIf
EndFunction

Function _RestoreActorScale(Actor akActor)
    If !akActor
        Return
    EndIf
    Float orig = StorageUtil.GetFloatValue(akActor, "SNBaka.OrigScale", 0.0)
    If orig > 0.0
        akActor.SetScale(orig)
        StorageUtil.SetFloatValue(akActor, "SNBaka.OrigScale", 0.0)   ; mark restored
    EndIf
EndFunction

; Bulk-restore every actor flagged as height-matched and empty the tracking list.
; Wired into EmergencyReset as a manual recovery valve (CGF "...EmergencyReset" 0) in
; case a save made mid-animation left an NPC resized. Not run periodically so it can
; never un-scale an actor that is mid-animation right now.
Function _RestoreAllScaledActors()
    Int i = StorageUtil.FormListCount(Self, "SNBaka.ScaledActors")
    While i > 0
        i -= 1
        Actor a = StorageUtil.FormListGet(Self, "SNBaka.ScaledActors", i) as Actor
        If a
            _RestoreActorScale(a)
        EndIf
        StorageUtil.FormListRemoveAt(Self, "SNBaka.ScaledActors", i)
    EndWhile
EndFunction

Function _CleanupPair(Actor akA1, Actor akA2, \
        ObjectReference marker1, ObjectReference marker2, Bool hadPlayer, Bool bSkipA2Reset = False)
    _Log("[SNBaka] CleanupPair: A1=" + akA1.GetDisplayName() + " A2=" + akA2.GetDisplayName() + " hadPlayer=" + hadPlayer)
    ; Single guaranteed choke point every paired interaction ends at -- reset the in-combat grapple
    ; mode flag here unconditionally, regardless of which exit path got us here (win/lose/abort).
    _bMidCombatGrappleActive = False
    akA1.SetVehicle(None)
    akA2.SetVehicle(None)
    ; Reset the pose FIRST, while STILL ghosted/restrained/pacified/AI-held -- confirmed real bug from
    ; testing (a creature "fell and got stuck" mid-combat, not tied to timing since a prior scene): the
    ; OLD order restored vulnerability (Ghost/AI/aggression/movement) BEFORE sending IdleForceDefaultState,
    ; leaving a window where the actor could get hit and staggered while still visually mid-struggle-pose.
    ; A stagger outranks a plain idle-force event and nothing ever re-sent it once the stagger cleared,
    ; so it just stuck there. A direct SendAnimationEvent isn't gated by the AI package, so it still
    ; reaches the behavior graph with DoNothing/pacify/ghost all still active -- nothing can interrupt it.
    Debug.SendAnimationEvent(akA1, "IdleForceDefaultState")
    If !bSkipA2Reset
        Debug.SendAnimationEvent(akA2, "IdleForceDefaultState")
    EndIf
    Utility.Wait(0.3)
    akA1.EvaluatePackage()
    If !bSkipA2Reset
        akA2.EvaluatePackage()
    EndIf
    ; Only NOW restore vulnerability/AI/aggression -- the pose is already clean, so nothing they get hit
    ; with from this point on can interrupt a reset that's already finished.
    akA1.SetGhost(False)
    akA2.SetGhost(False)
    ; These unconditional SetGhost(False) calls also wipe the DOWN-state ghost the Acheron bridge
    ; applies (its _ForceEssentialForDown), whose bookkeeping flag lives on the actor -- clear the flag
    ; to match, or a victim re-downed right after this paired animation can never be re-ghosted (the
    ; force function sees the stale flag==1 and skips SetGhost, leaving them hittable while helpless).
    ; Confirmed as the most plausible chain behind a follower dying while downed: struggle ends ->
    ; un-ghosted here with stale flag -> redown never re-ghosts -> stray hit lands for real.
    StorageUtil.SetIntValue(akA1, "SNAcheron.GhostForcedByUs", 0)
    StorageUtil.SetIntValue(akA2, "SNAcheron.GhostForcedByUs", 0)
    ; Restore collision (teammate flag) and remove the DoNothing AI override.
    SNBakaUI.SetNoCollision(akA1, False)
    SNBakaUI.SetNoCollision(akA2, False)
    _HoldActorAI(akA1, False)
    _HoldActorAI(akA2, False)
    ; Restore any height-match scaling applied for this pair.
    _RestoreActorScale(akA1)
    _RestoreActorScale(akA2)
    ; Un-pacify (restore original aggression) both.
    _PacifyActor(akA1, False)
    _PacifyActor(akA2, False)
    ; Deliberately NO Acheron.ReleaseActor here. Releasing the victim's two-way pacify at pair-cleanup
    ; opened a real window (confirmed live, 15:40 session): QTE lost -> cleanup released the player ->
    ; all three falmers re-targeted them during the struggle->scene transition -> the scene CTD guard
    ; refused the scene. The victim's untargetable state must survive every internal transition
    ; (downed -> struggle -> scene -> re-down); it ends ONLY at the genuine exits: _PostEscapeGrace
    ; (escape/scene end, which releases after the mercy window) or recovery via _ClearAcheronHold.
    akA1.StopTranslation()
    akA2.StopTranslation()
    akA1.SetRestrained(False)
    akA1.SetDontMove(False)
    akA2.SetRestrained(False)
    akA2.SetDontMove(False)
    If hadPlayer
        Game.ForceThirdPerson()
        PlayerRef.SetDontMove(False)   ; release the player pin (we pinned instead of ghosting)
        PlayerRef.SetRestrained(False)
        ; OStim sets this for player scenes; a scene that got force-stopped mid-thread (or refused)
        ; strands it, and nothing else clears it — the reported "can't attack + camera off" combo.
        Game.SetPlayerAIDriven(False)
    EndIf
    Game.EnablePlayerControls()
    _Log("[SNBaka] CleanupPair: player controls re-enabled (bSkipA2Reset=" + bSkipA2Reset + ")")

    _StopTears(akA2)

    ; Reset the hard auto-get-up ceiling to the full duration for whichever of the pair is STILL down
    ; once this paired animation ends -- being actively engaged with (win or lose, Struggle/ChokeHug/
    ; Inspect/Escalate/CreatureEscalate, all of them route through here) means the clock isn't why
    ; they're still down, so it shouldn't get to expire out from under them mid-scene. Single, central
    ; hook: every paired interaction in this file ends at _CleanupPair, so nothing needs its own
    ; special-cased reset call. _IsDownedAny, not a bare OnGround check -- an Acheron-held victim has
    ; SNAcheron.Held=1 with OnGround=0, and the OnGround-only version of this check silently skipped
    ; exactly the actors the reset exists for.
    ;
    ; LIMBO FIX (confirmed live bug): everything above this point -- ghost, pacify, restrain, AI-hold,
    ; player-control-enable, pose reset to IdleForceDefaultState -- runs UNCONDITIONALLY for whichever
    ; side ISN'T covered by bSkipA2Reset, even when that actor was already downed independent of THIS
    ; action's own outcome (e.g. WombHit downs a victim, then Kiss is run on the same still-downed
    ; victim -- Kiss never sets bSkipA2Reset, so cleanup strips every downed protection and nothing
    ; ever re-applies them). Left alone, the victim reads as downed (OnGround/Held still 1) yet is
    ; fully free to move -- a dead-end state nothing can recover from. !bSkipA2Reset here means "the
    ; caller is NOT about to run its own fresh-defeat setup right after this returns" (that path,
    ; _DefeatGroundWindow, already reapplies everything itself a few lines later) -- so only re-glue
    ; protections back on for a still-downed actor when nothing else is about to do it.
    If _IsDownedAny(akA1)
        StorageUtil.SetFloatValue(akA1, "SNBaka.AutoGetUpDeadlineRT", Utility.GetCurrentRealTime() + StorageUtil.GetFloatValue(PlayerRef, "SNAcheron.AutoGetUpSeconds", 600.0))
        If !bSkipA2Reset
            _ReassertDownedProtection(akA1)
        EndIf
    EndIf
    If _IsDownedAny(akA2)
        StorageUtil.SetFloatValue(akA2, "SNBaka.AutoGetUpDeadlineRT", Utility.GetCurrentRealTime() + StorageUtil.GetFloatValue(PlayerRef, "SNAcheron.AutoGetUpSeconds", 600.0))
        If !bSkipA2Reset
            _ReassertDownedProtection(akA2)
        EndIf
    EndIf
    ; Both actually up (not left down for some other reason) and not about to be immediately
    ; re-suppressed by a fresh defeat setup a few lines later in the caller (bSkipA2Reset) -- see
    ; _RestoreHostility's own comment for why this needs to be explicit rather than assumed.
    If !bSkipA2Reset && !_IsDownedAny(akA1) && !_IsDownedAny(akA2)
        _RestoreHostility(akA1, akA2)
    EndIf

    If marker1
        marker1.Delete()
    EndIf
    If marker2
        marker2.Delete()
    EndIf
EndFunction

; Re-glues an already-downed actor's protections back on after _CleanupPair stripped them for a
; paired action that wasn't itself a fresh defeat (see the LIMBO FIX comment above). Same setup
; _DefeatGroundWindow uses for a brand-new down, just without restarting its window/timer/narration
; -- the ground window this actor is already in keeps running untouched.
Function _ReassertDownedProtection(Actor ak)
    If ak == PlayerRef
        Game.DisablePlayerControls(True, True, False, False, True, False, False, False)
    Else
        ak.SetRestrained(True)
        ak.SetDontMove(True)
        _PacifyActor(ak, True)
        _HoldActorAI(ak, True)
    EndIf
    _ForceEssentialForDown(ak, True)
    String dp = StorageUtil.GetStringValue(ak, "SNBaka.DownPose", "")
    If dp != ""
        Debug.SendAnimationEvent(ak, dp)
    EndIf
EndFunction

; [REV-161 PR#2 fold (1) - Oldcustard credit: fix/creature-struggle-bugs, by-concept]
; [REV-177 item 1 - Oldcustard credit, issue #2: threshold re-based 1.0 -> 600.0]
; RT-STAMP RELAUNCH GUARD: Utility.GetCurrentRealTime() RESETS at every game
; launch, but StorageUtil stamps persist across sessions -- a backoff/deadline
; stamp written last session reads as "far future" after relaunch and NEVER
; expires (the creature backoff + defeat grace went permanent after every
; game restart). Readers clamp: a stamp that sits in the future of the current
; session clock is pre-relaunch and counts as long-expired.
; THRESHOLD ENUMERATION OF RECORD (REV-177): the deliberate future-dated
; writes read through THIS guard are DefeatGraceUntilRT (now + up to 300 --
; fPostDefeatGraceDuration slider 0..300, default 100) and
; LastCreatureAttemptRT (now + 300 no-scene backoff / now + 27 LLM-gate NO).
; Max deliberate horizon = 300s, so a 600s threshold clears every active
; stamp with margin while still catching pre-relaunch leftovers (typically
; thousands of seconds ahead; anything under 600 simply expires on its own).
; NOT read through this guard (out of threshold scope, verified REV-177):
; SNBaka.AutoGetUpDeadlineRT (now + 60..3600, compared directly, not via
; _RTStampStale) and the GS module's own stamps (OverdriveExpire/MuseDebugEnd
; have their own readers). Had any _RTStampStale-guarded write exceeded 600,
; the build would have STOPPED for re-ruling per the instruction set.
Bool Function _RTStampStale(Float afStamp, Float afNow)
    Return afStamp > afNow + 600.0
EndFunction

; The MERCY window: hold (or re-apply) the victim's ghost for fEscapeGraceDuration seconds at every
; exit from the protected interaction pipeline -- a won struggle OR the end of a sex scene -- so
; nobody gets spawn-killed the exact frame the protection drops (confirmed from testing: a third
; falmer attacked the player the second their won struggle finished). Deliberately BLOCKING -- the
; calling thread is this encounter's own worker, and holding it here also keeps whatever locks/
; cooldowns/re-downs follow from firing until the mercy ends. Ghost blocks incoming hits only; the
; victim can still fight, flee, or loot during the window.
Function _PostEscapeGrace(Actor akWinner)
    If !akWinner
        Return
    EndIf
    If fEscapeGraceDuration <= 0.0
        akWinner.SetGhost(False)   ; callers rely on this function ending the ghost either way
        _ReleaseAcheronPacify(akWinner)
        Return
    EndIf
    akWinner.SetGhost(True)
    _Log("[SNBaka] _PostEscapeGrace: " + akWinner.GetDisplayName() + " untouchable for " + fEscapeGraceDuration + "s of mercy")
    Utility.Wait(fEscapeGraceDuration)
    akWinner.SetGhost(False)
    ; [REV-161 PR#2 fold (5) - Oldcustard credit, by-concept] FREED-VICTIM
    ; MOVEMENT PERSISTENCE: _ReassertDownedProtection can re-apply the movement
    ; trio (SetRestrained/SetDontMove/_HoldActorAI) to an actor Acheron still
    ; holds; an escape that walks free through here used to lift only the
    ; ghost + pacify, leaving the freed victim rubber-pinned in place. Lift the
    ; trio for NPC winners (the player never gets SetDontMove -- camera lock --
    ; and the 2441 sweep covers its leftovers).
    If akWinner != PlayerRef
        akWinner.SetRestrained(False)
        akWinner.SetDontMove(False)
        _HoldActorAI(akWinner, False)
    EndIf
    ; This is the ONE place the struggle/scene-scoped two-way pacify (_SetupPair / the scene paths)
    ; ends for a victim who walks free — after the mercy window, never mid-transition. A victim who is
    ; re-downed instead never comes through here un-defeated, so their pacify carries straight into
    ; Acheron's own defeat state with no targetable gap (the "3 falmers re-targeted the player between
    ; struggle and scene" report). Recovery paths end it via _ClearAcheronHold instead.
    _ReleaseAcheronPacify(akWinner)
    _Log("[SNBaka] _PostEscapeGrace: ended for " + akWinner.GetDisplayName())
EndFunction

; Release Acheron's two-way pacify, but never strip it from an actor Acheron currently holds
; DEFEATED (a defeated actor is always pacified — that protection belongs to the down state).
Function _ReleaseAcheronPacify(Actor ak)
    If ak && StorageUtil.GetIntValue(PlayerRef, "SNAcheron.Present", 0) == 1 && !Acheron.IsDefeated(ak)
        Acheron.ReleaseActor(ak)
    EndIf
EndFunction

; Clears only akA1's lock/stop flags without starting the cooldown timer.
; Used after a QTE defeat so the attacker is free to trigger Escalate_Execute
; while the victim remains locked during the ground window.
Function _UnlockAttackerOnly(Actor akA1)
    StorageUtil.SetIntValue(akA1, "SNBaka.Locked",        0)
    StorageUtil.SetIntValue(akA1, "SNBaka.StopRequested", 0)
EndFunction

; ── REV-17 Task 2: downed-state silence early-exit for the ABANDONED delegated hold ──
; The 09-14 recorded ruling ("a defeated player must stay down until the get-up key, help,
; or a won QTE — no unsanctioned self-recovery") left a hole its authors didn't see: an
; ABANDONED hold. When nobody escalates, nobody helps, and the aggressor has simply walked
; away, the victim lingers in the Acheron hold indefinitely (09-15: player downed 3m42s+,
; unresolved at session end). The ruling survives for the ACTIVE cases — get-up key, help
; actions, won QTEs, and any hold a follow-up could still use — but the ABANDONED case now
; resolves through the sanctioned recovery chain once silence holds for fDownedSilenceSec:
;   (a) the aggressor has disengaged (dead, or farther than fCombatOverRadius — the same
;       radius the stand-down gate below uses);
;   (b) nothing is pending — no SexLab/OStim thread on the victim, no follow-up lock
;       (SNBaka.Locked), not still queued for the Acheron bridge;
;   (c) no combat near the victim (any nearby fighting keeps the hold — _WaitOrAbort
;       suspends recovery while combat runs, and recovering mid-fight would stand the
;       player up into a live brawl).
; Bounded: single fixed watch, hard-capped at 240s like the fallback window — it resets on
; every condition failure and never fires under an active follow-up. Runs only on the
; delegated path; the fallback window already recovers on its own timer.
Function _AbandonedHoldWatch(Actor akAggressor, Actor akVictim)
    If !akVictim
        Return
    EndIf
    _Log("[SNBaka] silence watch armed for " + akVictim.GetDisplayName() + " (" + fDownedSilenceSec + "s)")
    Float silence  = 0.0
    Float total    = 0.0
    ; REV-61 1b — observed-downed state: the "no longer downed (sanctioned exit)" stand-down
    ; is only valid if this watch actually SAW the victim downed first. The 09-30 Frabbi
    ; incident stood down 1s after arming because a dead delegation never set any downed flag
    ; — absence-of-flags was misread as a sanctioned exit and the abandoned-hold recovery
    ; never ran (victim stuck in the struggle-lost anim). Without observed-downed-before,
    ; absence is AMBIGUOUS: keep watching and let the expiry paths below decide.
    Bool bObservedDowned = False
    While silence < fDownedSilenceSec && total < 240.0
        Utility.Wait(1.0)
        total += 1.0
        If akVictim.IsDead()
            _Log("[SNBaka] silence watch: " + akVictim.GetDisplayName() + " died — watch standing down")
            Return
        EndIf
        If !_IsDownedAny(akVictim)
            If bObservedDowned
                _Log("[SNBaka] silence watch: " + akVictim.GetDisplayName() + " no longer downed (resolved by a sanctioned exit) — watch standing down")
                Return
            EndIf
            ; Never observed downed — absence is ambiguous (possible dead delegation). Keep watching.
        Else
            bObservedDowned = True
        EndIf
        If IsInSexAnimation(akVictim)
            _Log("[SNBaka] silence watch: scene took over " + akVictim.GetDisplayName() + " — standing down WITHOUT recovery")
            Return
        EndIf
        If StorageUtil.GetIntValue(akVictim, "SNBaka.Locked", 0) == 1
            _Log("[SNBaka] silence watch: " + akVictim.GetDisplayName() + " locked by a follow-up action — standing down (that action owns resolution)")
            Return
        EndIf
        If StorageUtil.FormListFind(PlayerRef, "SNBaka.AcheronDownQueue", akVictim) >= 0
            _Log("[SNBaka] silence watch: " + akVictim.GetDisplayName() + " still queued for the Acheron bridge — standing down")
            Return
        EndIf
        If akVictim.IsInCombat() \
                || (akAggressor && !akAggressor.IsDead() && akAggressor.GetDistance(akVictim) <= fCombatOverRadius)
            silence = 0.0
        Else
            silence += 1.0
        EndIf
    EndWhile
    If silence < fDownedSilenceSec
        If bObservedDowned
            _Log("[SNBaka] silence watch: capped after " + total + "s without " + fDownedSilenceSec + "s of straight silence — standing down WITHOUT recovery, hold persists")
        Else
            ; REV-61 1b: the watch ran its full course WITHOUT ever seeing the victim downed —
            ; that is the dead-delegation signature (09-30 Frabbi class). Do NOT stand down
            ; silently: log it and fire the recovery chain (safe no-op on a clean state).
            _Log("[SNBaka] silence watch: EXPIRED without observed downed state — possible dead delegation; actor: " + akVictim.GetDisplayName() + " — firing recovery chain")
            Debug.SendAnimationEvent(akVictim, "IdleForceDefaultState")
            _ForceRecover(akVictim)
        EndIf
        Return
    EndIf
    ; Unconditional reason-coded sentinel (2c): the next session's log confirms the fix
    ; from one grep — victim named, plus the three condition states. REV-61 1b: the reason
    ; string now distinguishes a genuine silence-timeout from one where the victim was
    ; never observed downed at all (dead-delegation class).
    String sReason = "silence-timeout (" + fDownedSilenceSec + "s)"
    If !bObservedDowned
        sReason = "silence-timeout WITHOUT observed downed state — possible dead delegation"
    EndIf
    _Log("[SNBaka] silence watch FIRED for " + akVictim.GetDisplayName() + " — reason: " + sReason + " | aggressor-disengaged=true combat-near=" + akVictim.IsInCombat() \
        + " locked=" + StorageUtil.GetIntValue(akVictim, "SNBaka.Locked", 0) \
        + " sexthread=" + IsInSexAnimation(akVictim) \
        + " queued=" + (StorageUtil.FormListFind(PlayerRef, "SNBaka.AcheronDownQueue", akVictim) >= 0) \
        + " | firing recovery chain")
    ; REV-17 Task 4 rider: stop any stale victim-side struggle loop before recovering.
    ; _CleanupPair skips the victim's IdleForceDefaultState when bSkipA2Reset=True (the
    ; defeat paths pass it), so the paired struggle loop's victim half is never stopped on
    ; this path (09-15: the player's half lingered ~15s until a jump interrupted it). This
    ; is the exact stop call _Bleedout already uses to clear looping paired anims — a
    ; harmless no-op on a clean graph, stops a stale loop in place.
    Debug.SendAnimationEvent(akVictim, "IdleForceDefaultState")
    ; Sanctioned recovery chain — HelpUp's own (HelpUp → _ForceRecover): get-up transition
    ; first, then the Acheron hold clear + essential-HP guard underneath it.
    _ForceRecover(akVictim)
EndFunction

; Called after a QTE defeat. Victim drops to the ground for fEscalationWindow
; seconds. During that window the attacker is free; if Escalate_Execute fires,
; _DoEscalation runs. Otherwise the victim is released and a cooldown starts.
Function _DefeatGroundWindow(Actor akA1, Actor akA2)
    _Log("[SNBaka] _DefeatGroundWindow: attacker=" + akA1.GetDisplayName() + " victim=" + akA2.GetDisplayName() + " window=" + fEscalationWindow)
    If !akA2 || akA2.IsDead()
        _Log("[SNBaka] _DefeatGroundWindow: victim already dead/None — aborting")
        StorageUtil.SetIntValue(akA2, "SNBaka.Locked",        0)
        StorageUtil.SetIntValue(akA2, "SNBaka.StopRequested", 0)
        _StartCooldown(akA1)
        Return
    EndIf

    ; DELEGATE to Acheron when present: it OWNS the downed state (hold + calm + recover + "X is downed"
    ; cues), so we just hand the victim over and step out. The acheron_downed cue then drives the next
    ; action (Rescue / Escalate-when-clear / etc.). This now includes the PLAYER -- explicit spec: a
    ; defeated player must stay down until the get-up key, help, or a won QTE, exactly like a combat
    ; defeat; the old player-only local window below auto-released them after fEscalationWindow, which
    ; is an unsanctioned self-recovery. The fallback window below only runs when Acheron is absent
    ; (Baka standalone), where the timed release is BY DESIGN the only recovery system there is.
    If _DelegateDownToAcheron(akA2)
        _UnlockAttackerOnly(akA1)
        StorageUtil.SetIntValue(akA2, "SNBaka.Locked",        0)
        StorageUtil.SetIntValue(akA2, "SNBaka.OnGround",      0)
        StorageUtil.SetStringValue(akA2, "SNBaka.DownPose",   "")
        StorageUtil.SetFormValue(akA2, "SNBaka.GroundWindowAggressor", None)
        ; REV-17 Task 3: delegated victims never received the downed DECISION event — this
        ; branch returns below, before the fallback window's baka_defeat registration
        ; (the two RegisterEvent calls further down), so on Acheron-held victims the
        ; Escalate / HelpUp / Release trio was only ever reachable through Acheron's own
        ; (much sparser) acheron_downed cue — the LLM had no Baka-side prompt inviting a
        ; disposition at all (09-15 session: victim downed 3m42s, unresolved at session
        ; end). Register our decision cue here, adapted to the delegated state (down and
        ; helpless, not PINNED — Acheron owns the hold; the fallback text's "pinned" framing
        ; would be false). Double-registration guard is structural: this branch and the
        ; fallback window are mutually exclusive arms of this same If — a non-delegated
        ; victim keeps the fallback registration only, a delegated one gets this one only.
        SkyrimNetApi.RegisterEvent("baka_defeat", \
            akA2.GetDisplayName() + " is beaten down and helpless at " + akA1.GetDisplayName() + "'s feet. " + \
            akA1.GetDisplayName() + " can talk to them — interrogate, threaten, mock, demand their surrender " + \
            "or belongings — but the choice is on them right now, and it lands through action " + \
            "— exactly ONE of: Escalate (force them into sex; use the Escalate action — never StartNewSex), " + \
            "HelpUp (show mercy, stand them up), or Release (step back, let the moment pass). " + \
            "The decision lands through the action itself. " + akA2.GetDisplayName() + " reacts. One beat.", \
            akA1, akA2)
        _Log("[SNBaka] _DefeatGroundWindow: baka_defeat registered for delegated victim " + akA2.GetDisplayName() + " (aggressor " + akA1.GetDisplayName() + ")")
        _StartCooldown(akA1)
        ; REV-17 Task 2: this branch previously returned straight into Acheron's hold with
        ; no bounded exit of its own — the 09-15 session's abandoned hold. Run the silence
        ; watch here: it resolves the delegated hold through the sanctioned recovery chain
        ; when the aggressor has disengaged and no action claimed the victim.
        _AbandonedHoldWatch(akA1, akA2)
        _Log("[SNBaka] _DefeatGroundWindow: delegated downed state to Acheron for " + akA2.GetDisplayName())
        Return
    EndIf

    Bool a2IsPlayer = (akA2 == PlayerRef)
    _Log("[SNBaka] _DefeatGroundWindow: victim isPlayer=" + a2IsPlayer)
    If a2IsPlayer
        Game.DisablePlayerControls(True, True, False, False, True, False, False, False)
        ; (No SetDontMove on the player — it locked the camera. The NPC is ghosted so it can't
        ; shove the player, and the player isn't ghosted so they won't fall; no pin needed.)
    EndIf
    ; Clear every downed-menu request flag BEFORE OnGround=1 (OnGround=1 is when the downed
    ; menu becomes openable). Any pick made from here on survives into the wait loop — this
    ; fixes the menu choice sometimes doing nothing because the old post-settle reset flushed
    ; a quick pick made during the ~1.5s settle.
    _bEscalateRequested = False
    _bReleaseRequested  = False
    _iDownedReplay      = 0
    _bStandBack         = False
    _bResetDownWindow   = False
    StorageUtil.SetIntValue(akA2, "SNBaka.InspectCount", 0)   ; fresh down -> reset the inspect-loop guard
    StorageUtil.SetStringValue(akA2, "SNBaka.DownPose", "")   ; fresh down -> re-roll the pose (then it sticks)
    ; Set OnGround=1 immediately so Interact_ShowMenu's downed-menu shortcut can detect
    ; the downed victim as soon as the attacker's lock is released (before _Bleedout).
    StorageUtil.SetIntValue(akA2, "SNBaka.OnGround", 1)
    ; Records WHO owns this window, so LockBoth can let THIS SAME aggressor's follow-up actions
    ; (PinHelpless/GropeHelpless/etc. — see LockBoth) through despite the victim being locked for the
    ; window's duration, instead of silently bouncing off IsActorLocked like every other caller.
    StorageUtil.SetFormValue(akA2, "SNBaka.GroundWindowAggressor", akA1)
    _ForceEssentialForDown(akA2, True)
    _Log("[SNBaka] _DefeatGroundWindow: OnGround=1 (early — downed menu ready)")
    _Bleedout(akA2, akA1)
    _Log("[SNBaka] _DefeatGroundWindow: bleedout on " + akA2.GetDisplayName())
    _StartTears(akA2)
    Utility.Wait(0.5)
    If !a2IsPlayer
        akA2.SetRestrained(True)
        akA2.SetDontMove(True)
        ; The reworked down pose is a plain idle (not vanilla bleedout), so the NPC could
        ; re-enter/initiate combat and break the scene. Pacify (Aggression 0) + stop combat +
        ; DoNothing AI for the duration; original aggression restored on release.
        _PacifyActor(akA2, True)
        _HoldActorAI(akA2, True)
        _Log("[SNBaka] _DefeatGroundWindow: Restrained+DontMove+pacified on NPC victim")
    EndIf
    If _bDruggedEscalation
        _Notify(akA2.GetDisplayName() + " collapses, unconscious.")
    ElseIf akA1 == PlayerRef
        ; Player is the one standing over the defeated NPC — the decision is theirs.
        _Notify("What will you do to " + akA2.GetDisplayName() + "?")
    ElseIf akA2 == PlayerRef
        ; NPC is standing over the player.
        _Notify(akA1.GetDisplayName() + " stands over you. What will they do?")
    Else
        ; NPC over NPC — the player is just witnessing.
        _Notify(akA1.GetDisplayName() + " stands over " + akA2.GetDisplayName() + ".")
    EndIf

    ; 1-second settle: lets the down pose stabilise and flushes any stale Escalate_Execute
    ; calls that may have arrived before the window opened.
    Utility.Wait(1.0)
    ; (Flags were already cleared at the top, before OnGround=1 — do NOT clear them again here,
    ; or a downed-menu pick made during this settle would be lost.)
    _Log("[SNBaka] _DefeatGroundWindow: escalate window open (" + fEscalationWindow + "s)")
    ; REV-72 SlaveTats module: user-chosen degradation set rides the defeat/downed event
    ; (module checks its own Enabled/ApplyOnDefeat/set-config gates; extend-not-duplicate).
    SNBaka_SlaveTatsModule.OnDefeat(akA2)
    If _bDruggedEscalation
        SkyrimNetApi.RegisterEvent("baka_defeat", \
            akA2.GetDisplayName() + " is unconscious — drugged by " + akA1.GetDisplayName() + ". " + \
            "They are completely unaware of what is happening and cannot resist in any way. " + \
            "Roleplay them as limp, unresponsive, breathing slowly. " + \
            akA1.GetDisplayName() + " must now decide what to do with the helpless " + akA2.GetDisplayName() + ".", \
            akA1, akA2)
    Else
        ; This is the LOCKED ground window: the victim is pinned, so aggressive acts like grope/choke/
        ; struggle (which call LockBoth) would silently fail here — don't offer them. Escalate and HelpUp
        ; both work (HelpUp calls _ForceRecover directly, no lock needed), same as Release.
        SkyrimNetApi.RegisterEvent("baka_defeat", \
            akA2.GetDisplayName() + " is beaten down and pinned, helpless at " + akA1.GetDisplayName() + "'s feet. " + \
            akA1.GetDisplayName() + " can talk to them — interrogate, threaten, mock, demand their surrender " + \
            "or belongings — but the choice is on them right now, and it lands through action " + \
            "— exactly ONE of: Escalate (force them into sex; use the Escalate action — never StartNewSex), " + \
            "HelpUp (show mercy, stand them up), or Release (step back, let the moment pass). " + \
            "The decision lands through the action itself. " + akA2.GetDisplayName() + " reacts. One beat.", \
            akA1, akA2)
    EndIf

    Float elapsed = 0.0
    Float tick    = 0.2
    Float sinceHold = 0.0
    Float sinceCue  = 0.0
    Bool escalated = False
    Bool sceneTookOver = False
    Bool agedOut = False
    ; Presence-based hold below resets `elapsed` while anyone's nearby, so an untied victim in this
    ; Acheron-absent fallback (this whole block only runs when Acheron didn't pick them up — see the
    ; delegate-and-return above) could stay down indefinitely in practice: the player who just defeated
    ; them is almost always within 700 units of their own victim. Confirmed live report: "downed actors
    ; cannot move or get up again" with Acheron not installed. startDownRT + fEscalationWindow is a hard
    ; ceiling on top of the presence-reset countdown -- still real-clock (not a naive tick count, same
    ; reasoning as _WaitOrAbort) so it isn't itself inflated by VM load. Tied victims are excluded:
    ; TieUp_Execute is its own explicit, opt-in "keep them down" mechanic with its own duration.
    Float startDownRT = Utility.GetCurrentRealTime()
    ; LATENCY (confirmed live: "why does it sometimes take so long from power press to execution on a
    ; downed target"): menu/LLM picks used to be consumed at the TAIL of each tick, behind a full po3
    ; loaded-actor presence scan that ran EVERY 0.2s tick. Under a congested VM each "0.2s" tick
    ; really takes 0.5-2s of work, so a click waited out the whole heavy tick body -- sometimes
    ; several real seconds -- just to be NOTICED. Two fixes: picks are consumed FIRST each tick, and
    ; the expensive presence scan runs on its own ~1.5s cadence (it guards a 20-second countdown; 5Hz
    ; bought nothing but VM load).
    Float sinceScan = 99.0   ; force a scan on the first tick
    While elapsed < fEscalationWindow && !escalated && !sceneTookOver && !_bReleaseRequested && !_bStandBack && !agedOut
        Utility.Wait(tick)
        elapsed += tick
        sinceHold += tick
        sinceCue  += tick
        sinceScan += tick
        If _bResetDownWindow
            ; An aggressor just interacted with the downed victim (LLM inspect/etc.) — keep them down
            ; and protected.
            _bResetDownWindow = False
            elapsed = 0.0
            _Log("[SNBaka] _DefeatGroundWindow: down timer reset by interaction")
        EndIf
        If _bEscalateRequested
            _bEscalateRequested = False
            ; _DoEscalation itself also gates on this (every escalation path funnels through it), but by
            ; the time it runs here the victim has ALREADY been unconditionally _Recover()'d a few lines
            ; below (stood up) regardless of what _DoEscalation decides — so its own "victim stays down"
            ; comment was being silently broken: a combat-blocked escalate stood the victim up with no
            ; way to retry (Escalate_Execute requires OnGround, which _Recover just cleared). Confirmed
            ; from a live log: Escalate accepted -> _Recover -> _DoEscalation blocked (combat near) ->
            ; retry a few seconds later rejected with "target not downed". Check here, BEFORE recovering,
            ; so a blocked escalate leaves the victim down and the window still running, exactly like the
            ; request was never made — same as _DoEscalation's other two callers, which never recover
            ; the victim ahead of time and simply hit the same gate the moment they call it.
            If _CombatNear(akA2, fCombatOverRadius)
                _Log("[SNBaka] _DefeatGroundWindow: escalate requested but combat still near — victim stays down, window keeps running")
                SkyrimNetApi.RegisterEvent("baka_escalate", \
                    akA1.GetDisplayName() + " stands over the beaten " + akA2.GetDisplayName() + " — but the fight is not over yet. Finish it first, then they can be taken.", \
                    akA1, akA2)
            Else
                escalated = True
                _Log("[SNBaka] _DefeatGroundWindow: escalate requested at t=" + elapsed)
            EndIf
        ElseIf _iDownedReplay > 0
            ; Downed-menu Investigate/Inspect: play the inspection anim through (no QTE),
            ; re-down the victim, and reset the window timer so they stay defeated.
            Int replayWhich = _iDownedReplay
            _iDownedReplay = 0
            _Log("[SNBaka] _DefeatGroundWindow: downed replay " + replayWhich + " at t=" + elapsed)
            _DownedReplay(akA1, akA2, replayWhich)
            ; Only NPC victims get the window timer reset here. The PLAYER isn't reset by the replay
            ; itself, but an aggressor close enough to inspect them is also close enough to trip the
            ; _AnyActorNear check above on the very same tick, which resets elapsed anyway — so this
            ; doesn't leave the player any less protected, it just avoids a redundant reset.
            If !a2IsPlayer
                elapsed = 0.0
                _Log("[SNBaka] _DefeatGroundWindow: replay done — window timer reset, NPC victim still down")
            Else
                _Log("[SNBaka] _DefeatGroundWindow: replay done — PLAYER victim")
            EndIf
        EndIf
        If sinceScan >= 1.5
            sinceScan = 0.0
            ; A sex scene has taken the victim — started by Baka's Escalate OR by ANOTHER mod (OStimNet /
            ; SexLab) that we don't drive. Stop managing them immediately so we never recover or re-pose
            ; them mid-scene (that yanks the body out of the running animation).
            If IsInSexAnimation(akA2)
                sceneTookOver = True
            EndIf
            ; PRESENCE-BASED HOLD (same model as Downed_SkyrimNet — same ~10m/700-unit radius): while ANY
            ; actor is near the victim, keep them down — reset the recover countdown (elapsed). They only
            ; stand up once the area has cleared for fEscalationWindow seconds, or via Escalate / Release /
            ; HelpUp. This is what stops an attacker "backing up" and the victim popping up mid-sequence.
            If !sceneTookOver && _AnyActorNear(akA2, 700.0)
                elapsed = 0.0
            EndIf
        EndIf
        If !sceneTookOver && StorageUtil.GetIntValue(akA2, "SNBaka.Tied", 0) != 1 \
                && (Utility.GetCurrentRealTime() - startDownRT) >= fEscalationWindow
            agedOut = True
            _Log("[SNBaka] _DefeatGroundWindow: aged out after " + fEscalationWindow + "s (Acheron absent, not tied) — recovering regardless of nearby presence")
        EndIf
        If sinceHold >= 3.0 && !sceneTookOver
            ; Re-assert the SAME cached down pose so the engine/AI can't reclaim the actor and
            ; visibly swap the pose. Static pose -> safe to re-assert for the player too (it's only
            ; an anim event, not SetDontMove, so it won't lock the camera). NEVER re-pose once a sex
            ; scene has taken over, or the down pose fights the running sex animation.
            sinceHold = 0.0
            String dp = StorageUtil.GetStringValue(akA2, "SNBaka.DownPose", "")
            If dp != ""
                Debug.SendAnimationEvent(akA2, dp)
            EndIf
        EndIf
        ; Nothing decided yet — the initial baka_defeat cue fired once and the attacker may just sit on
        ; it (an LLM turn can easily miss a one-shot cue). Re-cue every ~15s so "the attacker overpowered
        ; them and just stands there" doesn't go silent — same idea as Acheron's periodic reminder, kept
        ; here too since this window runs standalone (no Acheron involved).
        If sinceCue >= 15.0 && !sceneTookOver
            sinceCue = 0.0
            _CueDecisionIfDowned(akA1, akA2, False)   ; passive reminder — do NOT reset the recovery clock
        EndIf
    EndWhile

    If sceneTookOver
        ; A sex scene (Baka or another mod, e.g. OStimNet) owns the victim now. Do NOT _Recover or send a
        ; stand-up — that pulls them out of the running animation. Just drop our down flags and let the
        ; scene recover them when it ends.
        StorageUtil.SetIntValue(akA2, "SNBaka.OnGround",      0)
        StorageUtil.SetStringValue(akA2, "SNBaka.DownPose",   "")
        StorageUtil.SetIntValue(akA2, "SNBaka.StopRequested", 0)
        StorageUtil.SetIntValue(akA2, "SNBaka.Locked",        0)
        StorageUtil.SetFormValue(akA2, "SNBaka.GroundWindowAggressor", None)
        If !a2IsPlayer
            _HoldActorAI(akA2, False)
        EndIf
        _bEscalateRequested = False
        _bReleaseRequested  = False
        _bStandBack         = False
        _Log("[SNBaka] _DefeatGroundWindow: a sex scene took over -> standing down WITHOUT recovery")
        _StartCooldown(akA1)
        Return
    EndIf

    Bool standBack = _bStandBack
    _bStandBack    = False
    Bool released = _bReleaseRequested
    If released
        _Log("[SNBaka] _DefeatGroundWindow: release requested at t=" + elapsed + " — freeing victim early")
    EndIf
    _bEscalateRequested = False
    _bReleaseRequested  = False

    If escalated
        _Notify(akA1.GetDisplayName() + " makes their move.")
    ElseIf standBack
        _Notify(akA1.GetDisplayName() + " stands back; " + akA2.GetDisplayName() + " staggers to their feet.")
    ElseIf released
        _Notify(akA1.GetDisplayName() + " steps back and lets you go.")
    Else
        _Notify(akA1.GetDisplayName() + " backs away.")
    EndIf
    StorageUtil.SetIntValue(akA2, "SNBaka.OnGround", 0)
    StorageUtil.SetFormValue(akA2, "SNBaka.GroundWindowAggressor", None)
    akA2.SetRestrained(False)
    akA2.SetDontMove(False)
    If !a2IsPlayer
        _PacifyActor(akA2, False)
        _HoldActorAI(akA2, False)
    EndIf
    _Log("[SNBaka] _DefeatGroundWindow: OnGround=0. escalated=" + escalated)

    If standBack
        ; Stand Back: a visible stagger as they scramble up, then the normal recover/stand.
        Debug.SendAnimationEvent(akA2, "staggerStart")
        Utility.Wait(0.3)
    EndIf
    _Recover(akA2)
    ; Only stand the player up if we are NOT about to chain into escalation.
    ; If escalated, _DoEscalation will handle controls and positioning directly.
    If a2IsPlayer && !escalated
        Game.EnablePlayerControls()
        Debug.SendAnimationEvent(akA2, "IdleForceDefaultState")
        _Log("[SNBaka] _DefeatGroundWindow: player controls re-enabled")
    EndIf

    If escalated
        _Log("[SNBaka] _DefeatGroundWindow: escalating to _DoEscalation")
        _DoEscalation(akA1, akA2)
    Else
        _Log("[SNBaka] _DefeatGroundWindow: window expired without escalation")
        StorageUtil.SetIntValue(akA2, "SNBaka.Locked",        0)
        StorageUtil.SetIntValue(akA2, "SNBaka.StopRequested", 0)
        _CueOutcome("baka_forced", \
            akA2.GetDisplayName() + " was left defeated on the ground by " + akA1.GetDisplayName() + ", and slowly recovers.", \
            akA1, akA2)
        If akA1 == PlayerRef || akA2 == PlayerRef
            Game.EnablePlayerControls()
        EndIf
        ; See _RestoreHostility's own comment: restoring aggression alone doesn't reliably make a
        ; genuinely hostile pair resume fighting once they're both back up.
        _RestoreHostility(akA1, akA2)
        _StartCooldown(akA1)
    EndIf
EndFunction

; ── Sex-scene backend dispatch ───────────────────────────────────────────────
; iSexBackend: 0 = auto (SexLab if present, else OStim), 1 = SexLab, 2 = OStim.
; SexLab is resolved at runtime (GetFormFromFile in Setup) so SexLab.esm need NOT be a master.
; OStim runs a normal scene (OThread.QuickStart); it has no built-in aggressive system and we
; don't need one — the aggressive framing is narrative (RegisterEvent narration + expressions).
Int Function _ResolveSexBackend(Int aiPref = -1)
    Int b = aiPref
    If b < 0
        b = iSexBackend       ; -1 = use the normal-sex backend setting
    EndIf
    Bool hasSL = SkyrimNet_BakaSL.Installed()
    If b == 0
        If hasSL
            b = 1
        Else
            b = 2
        EndIf
    EndIf
    If b == 1 && !hasSL
        _Log("[SNBaka] _ResolveSexBackend: SexLab selected but not installed — falling back to OStim")
        b = 2
    EndIf
    Return b
EndFunction

; Starts a 2-actor scene on the configured framework and applies the tear overlay to the victim.
; ── SexLab tag matching ──────────────────────────────────────────────────────
; SexLab packs tag their anims very differently (Leito / Anubis / Billyy / ZaZ / FunnyBizness /
; Nibbles all use different words). Filtering on ONE canonical tag (e.g. "Aggressive") with
; requireAll often returns NOTHING, so the scene fails or picks at random. Instead we OR a wide
; synonym set per selection, suppress the opposite tone + the non-chosen positions, and fall back
; broader if needed — so a fitting scene is almost always found.
;   position  = "vaginal" / "anal" / "oral" / ""   intensity = "aggressive" / "loving" / ""
; (SexLab tag-matching + anim resolution moved to the SkyrimNet_BakaSL bridge — see StartScene there.)

; Callers pass a position + intensity selector; we build the OR tag filter (above). OStim ignores
; tags and picks its own scene.
Int Function _StartSexScene(Actor[] akActors, Actor akVictim, Actor akAggressor, String position, String intensity, Int aiBackend = -1)
    Int backend = _ResolveSexBackend(aiBackend)
    Int tid = -1
    ; FINAL combat gate, at the single choke point every scene start funnels through: if the PLAYER is
    ; among the actors and any combat is still live on or near them, REFUSE to start -- OStim CTDs
    ; (confirmed repeatedly) when its thread spins up while the player is in combat, and every earlier
    ; gate leaves a prep window where a fight can re-flare after the check. Over-blocking is the safe
    ; direction here: a refused scene falls through to each caller's existing no-scene handling (their
    ; wait loops see no animation and re-down the victim), and the retry pipeline gets another shot
    ; once things settle. IsInCombat() alone can be a stale alarm flag, but for a CTD guard a false
    ; positive just means "try again later" -- acceptable.
    Int gi = 0
    While gi < akActors.Length
        ; _CombatNear only — deliberately NOT PlayerRef.IsInCombat(): the player's own combat flag
        ; reflects OTHERS holding them in a combat list and lingers long after every attacker has been
        ; AI-held/lock-cleared ("after StopCombat(): IsInCombat()=TRUE" in the log). Gating on it
        ; refused every post-QTE scene — the reported escalate/refuse/re-down loop. Real combatants
        ; actively fighting near the player (the actual OStim hazard) is what _CombatNear measures.
        If akActors[gi] == PlayerRef && _CombatNear(PlayerRef, fCombatOverRadius)
            _Log("[SNBaka] _StartSexScene: REFUSED — player is in the scene with combat still live (CTD guard)")
            Return -1
        EndIf
        gi += 1
    EndWhile
    ; A defeat/aggressive scene runs far longer than the down/grab anims, so a calm cast earlier in the
    ; encounter may have lapsed — re-cast it for a fresh full duration so combat can't re-ignite under the
    ; scene. ONLY for participants who are actually IN COMBAT: a peaceful/consensual scene (e.g. two NPCs
    ; in a tavern) has no fight to suppress, so we don't needlessly Calm them.
    If SNBakaCalm
        Int ci = 0
        While ci < akActors.Length
            If akActors[ci] && akActors[ci] != PlayerRef && akActors[ci].IsInCombat()
                SNBakaCalm.Cast(akActors[ci], akActors[ci])
            EndIf
            ci += 1
        EndWhile
    EndIf
    If backend == 1
        tid = SkyrimNet_BakaSL.StartScene(akActors, akVictim, akAggressor, position, intensity)
        _Log("[SNBaka] _StartSexScene: SexLab tid=" + tid + " pos='" + position + "' int='" + intensity + "'")
    ElseIf backend == 2
        ; OStim. Instead of relying on OStim's default pick, we ask OStim's library for a scene that
        ; fits these actors and pin it as the starting animation. For aggressive escalation that pulls
        ; the forced/choke BakaFactory "Babo" scenes; the SAME query resolves CREATURE scenes when the
        ; actor array is [creature, victim]. Aggressor = dominant so OStim assigns roles correctly.
        Int bid = OThreadBuilder.Create(akActors)
        If bid < 0
            _Log("[SNBaka] _StartSexScene: OStim Create failed (invalid actor)")
            Return -1
        EndIf
        OThreadBuilder.NoFurniture(bid)
        If akAggressor && intensity == "aggressive"
            Actor[] doms = new Actor[1]
            doms[0] = akAggressor
            OThreadBuilder.SetDominantActors(bid, doms)
        EndIf
        String sceneId = _PickOStimScene(akActors, intensity)
        If sceneId == ""
            ; CREATURE scenes only start when we can PIN a matching animation — OStim's default pick
            ; can't resolve creature combos, so an empty pick means "no animation installed for this
            ; pairing" (confirmed live: giant scenes started with scene='' and died instantly, burning
            ; the whole prep cycle and exposing the AlignMenu null-thread crash). Refuse instead; the
            ; caller's no-scene unwind re-downs the victim and resets the creature cleanly. Human
            ; scenes keep OStim's default pick.
            Int ci = 0
            While ci < akActors.Length
                If akActors[ci] && _CreatureAnimKey(akActors[ci]) != ""
                    _Log("[SNBaka] _StartSexScene: REFUSED — no OStim animation found for this creature combination (an animation pack covering it, e.g. Billyy's, is not installed)")
                    OThreadBuilder.Cancel(bid)
                    Return -1
                EndIf
                ci += 1
            EndWhile
        Else
            OThreadBuilder.SetStartingAnimation(bid, sceneId)
        EndIf
        String meta = position
        If intensity != ""
            If meta != ""
                meta += ","
            EndIf
            meta += intensity
        EndIf
        If meta != ""
            OThreadBuilder.SetMetadataCSV(bid, meta)
        EndIf
        tid = OThreadBuilder.Start(bid)
        If tid < 0
            OThreadBuilder.Cancel(bid)        ; start failed — free the builder id so it isn't leaked
        EndIf
        _Log("[SNBaka] _StartSexScene: OStim tid=" + tid + " scene='" + sceneId + "' pos='" + position + "' int='" + intensity + "'")
    Else
        _Log("[SNBaka] _StartSexScene: no sex framework available — scene skipped.")
    EndIf
    If tid >= 0 && akVictim
        _ApplySexTears(akVictim)
        ; Stashed so a later hit/combat check (see the scene-wait loops in _EscalationCleanup and
        ; _DoCreatureEscalation) can force-stop THIS specific running scene without needing every
        ; caller to thread tid/backend through as extra parameters.
        StorageUtil.SetIntValue(akVictim, "SNBaka.SceneTid", tid)
        StorageUtil.SetIntValue(akVictim, "SNBaka.SceneBackend", backend)
    EndIf
    Return tid
EndFunction

; A hit on either animating actor (accidental or not) must stop the scene right now, not just wait for
; it to end -- OStim in particular crashes (confirmed via CrashLoggerSSE, null actor alignment inside
; OStim's AlignMenu) if combat resettles while its own thread is still running. Reads the tid/backend
; _StartSexScene stashed on the victim; no-op if none is running.
Function _StopSexScene(Actor akVictim)
    If !akVictim
        Return
    EndIf
    Int tid = StorageUtil.GetIntValue(akVictim, "SNBaka.SceneTid", -1)
    If tid < 0
        Return
    EndIf
    Int backend = StorageUtil.GetIntValue(akVictim, "SNBaka.SceneBackend", 0)
    _Log("[SNBaka] _StopSexScene: force-stopping tid=" + tid + " backend=" + backend + " for " + akVictim.GetDisplayName())
    If backend == 1
        SkyrimNet_BakaSL.StopScene(tid)
    ElseIf backend == 2
        OThread.Stop(tid)
    EndIf
    StorageUtil.SetIntValue(akVictim, "SNBaka.SceneTid", -1)
EndFunction

; Ask OStim's library for a scene that fits these actors. For aggressive escalation we first try
; forced/aggressive-tagged scenes (this is what pulls in the BakaFactory Babo "ChokeRape/Conquering/
; ThreateningMMF" scenes); we then fall back to any valid scene. Returns "" to mean "let OStim pick /
; no specific match".
String Function _PickOStimScene(Actor[] akActors, String intensity)
    String s = ""
    If _AnyCreatureIn(akActors)
        ; Creature packs are tagged by species, not "forced/aggressive/rape" like human packs — the
        ; human tag query below silently finds nothing for a creature pair. Superload is OStim's
        ; broader, untagged-friendly lookup; same technique Yamete Redux uses for its own creature
        ; scenes. No positive tag requirement — creature packs are sparse enough that adding one on
        ; top risks finding nothing at all, so just exclude the obviously-wrong "idle" scenes.
        s = OLibrary.GetRandomSceneSuperloadCSV(akActors, SceneTagBlacklist = "idle")
    ElseIf intensity == "aggressive"
        s = OLibrary.GetRandomSceneWithAnySceneTagCSV(akActors, "forced,aggressive,rape,choke,rough,dirty")
    EndIf
    If s == ""
        s = OLibrary.GetRandomScene(akActors)
    EndIf
    Return s
EndFunction

; Shared by both sex backends: does this actor array include a creature? Both _PickOStimScene (below)
; and SkyrimNet_BakaSL.StartScene (a separate script, hence Global + self-contained keyword lookup
; rather than reusing the instance-cached _kwActorTypeNPC/_IsCreatureActor) need this to route to the
; creature-aware animation lookup instead of the human one, which silently returns nothing usable for
; a creature actor.
Bool Function _AnyCreatureIn(Actor[] akActors) Global
    Keyword kwNPC = Game.GetFormFromFile(0x00013794, "Skyrim.esm") as Keyword
    If !kwNPC
        Return False
    EndIf
    Int i = 0
    While i < akActors.Length
        If akActors[i] && !akActors[i].HasKeyword(kwNPC)
            Return True
        EndIf
        i += 1
    EndWhile
    Return False
EndFunction

; Plays the strangle animation on the downed victim, then starts an aggressive scene.
; No second QTE — escalation goes directly to the configured sex framework.
Function _DoEscalation(Actor akA1, Actor akA2)
    ; REV-146a Task 2: child boundary - the shared human-escalation gate.
    If _ChildBoundaryRefused(akA1, akA2, "DoEscalation")
        Return
    EndIf
    ; Every HUMAN escalation path funnels here -- Escalate_Execute's "ours" branch (via the ground
    ; window's own loop), its "external" branch, and _DispatchDownedAction's external branch (the
    ; PrismaUI downed-menu AND AcheronNG's native Hunter's Pride menu both call that) -- so this one
    ; function is the actual shared gate for all of them. (Creature escalation does NOT go through
    ; here -- _DoCreatureEscalation calls _StartSexScene directly.)
    If _IsCreatureActor(akA1) || _IsCreatureActor(akA2)
        _Log("[SNBaka] _DoEscalation: blocked — creature actor")
        Return
    EndIf
    ; REV-144 4.2: central player-target admission -- this funnel carries EVERY human
    ; escalation lane (Escalate_Execute's ours/external branches + _DispatchDownedAction's
    ; external branch), so the policy is consulted once here and the downed-player case
    ; (which bypasses IsEligible by design) is finally gated by it. Player-own escalations
    ; pass ungated (the Execute pattern).
    If !_PlayerTargetAdmitted(akA1, akA2, "EscalateFunnel")
        Return
    EndIf
    ; _TargetSexAllowed is a content-PREFERENCE filter (what should the LLM/an NPC be allowed to pick),
    ; not a technical constraint -- so, same precedent as bNPCCanEscalate below, it only gates a
    ; non-player initiator. The player pressing Hunter's Pride (or the PrismaUI menu) on a specific
    ; target, including a male one with iTargetSex set to female-only, is their own deliberate choice
    ; and shouldn't be second-guessed here.
    If akA1 != PlayerRef && !_TargetSexAllowed(akA2)
        _Log("[SNBaka] _DoEscalation: blocked — target sex not allowed by MCM")
        Return
    EndIf
    ; ESCALATION IS THE ONLY COMBAT-GATED STEP. Forced sex (the OStim scene) is unstable mid-combat, so
    ; we NEVER start it while a fight is still going on near the victim. The victim stays down; the LLM is
    ; told to finish the fight first, and can escalate once it's over.
    If _CombatNear(akA2, fCombatOverRadius)
        _Log("[SNBaka] _DoEscalation: blocked — combat still ongoing nearby; deferring sex")
        SkyrimNetApi.RegisterEvent("baka_escalate", \
            akA1.GetDisplayName() + " stands over the beaten " + akA2.GetDisplayName() + " — but the fight is not over yet. Finish it first, then they can be taken.", \
            akA1, akA2)
        Return
    EndIf
    _Log("[SNBaka] _DoEscalation: A1=" + akA1.GetDisplayName() + " A2=" + akA2.GetDisplayName())
    ; REV-72 SlaveTats module: user-chosen degradation set rides the escalation handoff
    ; (module checks its own Enabled/ApplyOnEscalation/set-config gates; default OFF).
    SNBaka_SlaveTatsModule.OnEscalation(akA2)
    ; Lock BOTH — not just the attacker. The victim must be Locked too, or (when the victim is the
    ; player) Downed_SkyrimNet keeps running its hold/recovery/creature-retry THROUGH the sex scene and
    ; fires the down pose into it, breaking the animation.
    StorageUtil.SetIntValue(akA1, "SNBaka.Locked", 1)
    StorageUtil.SetIntValue(akA2, "SNBaka.Locked", 1)

    Bool a1IsPlayer = (akA1 == PlayerRef)
    Bool a2IsPlayer = (akA2 == PlayerRef)

    If a1IsPlayer || a2IsPlayer
        Game.DisablePlayerControls(True, True, False, False, True, False, False, False)
        ; (No SetDontMove on the player — it locked the camera. The NPC is ghosted so it can't
        ; shove the player, and the player isn't ghosted so they won't fall; no pin needed.)
    EndIf

    akA1.StopCombat()
    akA1.StopCombatAlarm()
    akA2.StopCombat()
    akA2.StopCombatAlarm()

    ; Recover A2 from bleedout before positioning — SetAngle has no effect while
    ; the bleedout animation controls the actor's root bone.
    _Recover(akA2)
    Utility.Wait(0.3)

    ; Disable NPC↔player collision (teammate flag) + suppress AI (DoNothing package) so
    ; the choke pose holds.  Restored in _EscalationCleanup.
    SNBakaUI.SetNoCollision(akA1, True)
    SNBakaUI.SetNoCollision(akA2, True)
    _HoldActorAI(akA1, True)
    _HoldActorAI(akA2, True)
    ; Pacify both NPCs so the victim can't draw a weapon / fight back mid-animation. Restored in cleanup.
    _PacifyActor(akA1, True)
    _PacifyActor(akA2, True)
    ; Same two-way protection _SetupPair gives its victims — this inline setup predates that upgrade:
    ; _PacifyActor only stops the VICTIM fighting; Acheron's pacify stops everyone else TARGETING them
    ; ("ignoring & ignored"). Ends via _PostEscapeGrace or a real recovery, same lifecycle as everywhere.
    _ProtectVictimTargeting(akA2)
    ; Height-matching via Actor.SetScale was REMOVED — it caused runaway scaling (refActor's
    ; scale was never restored, so actors snowballed bigger) and a CTD scare, for marginal gain.
    ; Offsets are what looks best. If revisited, use a controlled NiOverride node-scale, not SetScale.

    ; A1 starts ~5 units in front of A2 (very close — 14 read too far apart).  z-offset 0
    ; places A1 at A2's EXACT Z so they're at the same height on stairs/slopes.
    Float angZ = akA2.GetAngleZ()
    ; Escalation is VICTIM-anchored (the victim is DOWNED in place), so this is the one case where the
    ; offset positions the ATTACKER relative to the (downed) victim. Tunable via SNBaka_Offsets.ini key
    ; "Escalation": x=right/left, y=front/back, z=up/down of the attacker vs the victim, rot=attacker
    ; facing (180 = facing the victim). Defaults fall back to fEscalDist_* / 180 so no .ini = old behavior.
    Float defDist = fEscalDist_NPC
    If akA2 == PlayerRef
        defDist = fEscalDist_PCVic
    EndIf
    Float ox   = SNBakaUI.GetOffset("Escalation", "x", 0.0)
    Float oy   = SNBakaUI.GetOffset("Escalation", "y", defDist)
    Float oz   = SNBakaUI.GetOffset("Escalation", "z", 0.0)
    Float orot = SNBakaUI.GetOffset("Escalation", "rot", 180.0)
    Float offX = (oy * Math.Sin(angZ)) + (ox * Math.Cos(angZ))
    Float offY = (oy * Math.Cos(angZ)) - (ox * Math.Sin(angZ))

    akA1.MoveTo(akA2, offX, offY, 0.0, False)
    Utility.Wait(0.1)
    ; Snap A1 to A2's Z (+ z offset), in case the navmesh nudged it off on a slope.
    akA1.SetPosition(akA1.GetPositionX(), akA1.GetPositionY(), akA2.GetPositionZ() + oz)
    akA1.SetAngle(0.0, 0.0, angZ + orot)
    akA2.SetAngle(0.0, 0.0, angZ)
    _Log("[SNBaka] _DoEscalation: A1 snapped to (" + akA1.GetPositionX() + "," + akA1.GetPositionY() + ") angle=" + (angZ + orot))
    _LogPair("Escalation", akA1, akA2, ox, oy, orot, angZ + orot)

    ; Roles: A1 (attacker) plays A2_S1 (crouching straddler), A2 (victim) plays A1_S1 (downed).
    Debug.SendAnimationEvent(akA1, "Babo_DefeatResist_A2_S1")
    Debug.SendAnimationEvent(akA2, "Babo_DefeatResist_A1_S1")
    _StartTears(akA2)
    _WaitOrAbort(akA1, akA2, 8.0)

    ; Transition directly to SexLab aggressive scene.
    Debug.SendAnimationEvent(akA1, "IdleForceDefaultState")
    Debug.SendAnimationEvent(akA2, "IdleForceDefaultState")
    Utility.Wait(0.5)

    _StartTears(akA2)

    _Log("[SNBaka] _DoEscalation: SexLab installed=" + SkyrimNet_BakaSL.Installed() + " drugged=" + _bDruggedEscalation)

    ; Pending-scene latch (rev-22): from here until _EscalationCleanup confirms scene
    ; end, this pair is busy even though IsInSexAnimation still reads False (wizard
    ; open / thread in setup). Both dispatch paths below run through a cleanup that
    ; releases it.
    _SetSceneLatch(akA1, akA2)

    ; ── Player involved: open our PrismaUI encounter wizard (async).  The scene
    ; is started in _StartSexLabScene when the player finishes; cleanup happens
    ; there too.  No SkyrimNet_SexLab dependency. ─────────────────────────────
    If (a1IsPlayer || a2IsPlayer) && SNBakaUI.IsAvailable()
        _Log("[SNBaka] _DoEscalation: opening PrismaUI encounter wizard")
        ; The Interact menu pauses correctly because it opens from normal gameplay.
        ; Here the player is still under DisablePlayerControls from the choke, which
        ; stops PrismaUI's menu-pause from engaging.  Return control to a clean state
        ; first; the wizard's pauseGame=true then freezes everything during the picks.
        Game.EnablePlayerControls()
        SNBakaUI.ShowEncounterMenu(akA1, akA2)
        Return
    EndIf

    ; ── Automatic path (NPC-NPC, or no PrismaUI): aggressive scene ────────────
    Actor[] sexActors = new Actor[2]
    sexActors[0] = akA1
    sexActors[1] = akA2
    ; Escalation is always a non-consensual overpower -> aggressive tone, any position.
    Int sceneTid = _StartSexScene(sexActors, akA2, akA1, "", "aggressive")
    If sceneTid < 0
        _Log("[SNBaka] _DoEscalation: WARNING — scene failed to start (tid=" + sceneTid + "); narrating anyway, cleanup will run immediately (IsInSexAnimation will read false)")
    EndIf
    String npcNarr = akA1.GetDisplayName() + " overpowers " + akA2.GetDisplayName() + "."
    If _bDruggedEscalation
        npcNarr = akA1.GetDisplayName() + " takes advantage of the unconscious " + akA2.GetDisplayName() + ". " + \
            akA2.GetDisplayName() + " is unaware of what is being done to them — roleplay them as completely passive, limp, unresponsive."
        _bDruggedEscalation = False
    EndIf
    ; NPC-NPC scene: tell the LLM and show the player what's happening to whom.
    SkyrimNetApi.RegisterEvent("baka_sexlab_trigger", npcNarr, akA1, akA2)
    _Notify(npcNarr)
    _EscalationCleanup(akA1, akA2)
EndFunction

; Restores controls / locks / cooldown after an escalation.  Shared by the
; automatic path above and the async PrismaUI path in _StartSexLabScene.
Function _EscalationCleanup(Actor akA1, Actor akA2)
    ; This used to run immediately when the sex scene STARTED (called right after _StartSexScene, not
    ; after it ends) — meaning IdleForceDefaultState/EvaluatePackage/SetRestrained(False) fired on BOTH
    ; actors, and SNBaka.Locked was cleared, WHILE SexLab/OStim was actively mid-animation. Clearing the
    ; lock is what mattered most: it's the one signal that makes Acheron's poll defer, so clearing it
    ; early let Acheron start trying to manage/recover the same actor SexLab/OStim was still animating —
    ; two systems fighting over one actor mid-scene, a classic crash vector. Wait for the scene to
    ; actually be over (poll the same faction check IsEligible/etc. already use) before touching anything.
    _Log("[SNBaka] _EscalationCleanup: waiting for scene to end. A1=" + akA1.GetDisplayName() + " A2=" + akA2.GetDisplayName())
    ; Same nearby-teammate protection as PlayPairedSequence's own struggle phase, extended through the
    ; actual sex scene too — a downed/occupied actor is vulnerable to being "executed" by an unrelated
    ; mod's own AI-driven action for this whole window, not just during the preceding struggle.
    _ProtectNearbyAllies(akA2, akA1, True, False)
    ; The VICTIM is untouchable for the scene's whole duration, same rule as the struggle phase
    ; (_SetupPair now ghosts both participants): the aggressor's own faction allies won't kill its
    ; prey — a stray ally hit whiffs instead of staggering the animation or feeding OStim a combat
    ; transition mid-thread. The AGGRESSOR stays hittable on purpose: a genuine hit on IT (a rescuer
    ; interceding) is exactly what's allowed to break the scene, per the abort rule below.
    akA2.SetGhost(True)
    ; Ghost stops hits LANDING; Acheron's pacify makes combat IGNORE her outright (same mechanism its
    ; own defeat state uses — "the others stop attacking downed characters"), so attackers drop her as
    ; a target instead of whiffing at her for the whole scene. Scene-scoped: released after the loop.
    _ProtectVictimTargeting(akA2)
    Utility.Wait(2.0)   ; grace period: SexLab/OStim need a moment to add the actors to the scene faction
    Int waited = 0
    Bool sceneCut = False
    ; Force-stop the scene only when a REAL fight reaches the aggressor -- OStim crashes (confirmed
    ; CrashLoggerSSE, null actor alignment inside OStim's AlignMenu) if combat resettles while its own
    ; thread is running. Same refined rule as _ShouldAbort: combat STATE alone (the aggressor's faction
    ; alarm reacting to its ally attacking this very victim) doesn't count; only a live, non-downed
    ; combat target OTHER than the scene's own victim does -- that's what a genuine interceding hit
    ; produces (the aggressor's target switches to whoever hit it). The victim side isn't checked at
    ; all anymore: they're ghosted above, nothing can land on them.
    While IsInSexAnimation(akA2) && waited < 900 && !sceneCut   ; 15min hard cap (audit: a stuck faction flag pinned a VM thread for up to an hour)
        Actor a1t = akA1.GetCombatTarget()
        If akA1.IsInCombat() && a1t && a1t != akA2 && !a1t.IsDead() && !a1t.IsDisabled() && !_IsDownedAny(a1t)
            _Log("[SNBaka] _EscalationCleanup: " + akA1.GetDisplayName() + " is in a real fight against " + a1t.GetDisplayName() + " mid-scene — force-stopping")
            _StopSexScene(akA2)
            sceneCut = True
        Else
            Utility.Wait(1.0)
            waited += 1
        EndIf
    EndWhile
    _ProtectNearbyAllies(akA2, akA1, False)
    If akA2
        ; Scene over: hold the ghost a few MERCY seconds more before dropping it (no spawn-kills the
        ; frame the protection ends), THEN release the scene-scoped pacify.
        _PostEscapeGrace(akA2)
        If StorageUtil.GetIntValue(PlayerRef, "SNAcheron.Present", 0) == 1
            Acheron.ReleaseActor(akA2)   ; end the scene-scoped pacify; the captive re-down re-pacifies via DefeatActor
        EndIf
    EndIf
    If waited >= 900
        _Log("[SNBaka] _EscalationCleanup: WARNING — hit the 15min hard cap still IsInSexAnimation=true; proceeding anyway (stuck scene faction?)")
    Else
        _Log("[SNBaka] _EscalationCleanup: scene ended after " + waited + "s — proceeding with cleanup")
    EndIf
    ; [L2 — docs\MALE_VICTIM_L2_TREATASSEX.md] Scene-end rollback of the TreatAsFemale override
    ; SkyrimNet_BakaSL.StartScene may have applied to the victim at handoff. Flag-gated inside
    ; (SNBakaSL.L2Override): a no-op on female scenes — the female path is byte-identical. Placed
    ; BEFORE the invalid-actor guard so the override never outlives the scene even if the rest of
    ; the cleanup aborts; the guard's early-exit below therefore cannot strand it.
    SkyrimNet_BakaSL.ClearVictimOverride(akA2)
    ; Pending-scene latch (rev-22): scene over (or fell through) — release the pair.
    ; Placed BEFORE the invalid-actor guard so the latch never outlives the
    ; escalation even if the rest of the cleanup aborts (_ClearSceneLatch tolerates
    ; None/disabled actors itself).
    _ClearSceneLatch(akA1, akA2)
    ; Defensive: a long wait is exactly where an actor could go invalid (unloaded, killed, deleted) out
    ; from under us. Every call below assumes both are live; without this guard a None here would throw
    ; the same "call X on a None object" error on every single line for the rest of the function.
    If !akA1 || !akA2 || akA1.IsDisabled() || akA2.IsDisabled()
        _Log("[SNBaka] _EscalationCleanup: ABORTING — an actor went invalid while waiting for the scene to end (A1=" + akA1 + " A2=" + akA2 + ")")
        Return
    EndIf
    ; Restore collision (teammate flag). Cosmetic — order doesn't matter for these two.
    SNBakaUI.SetNoCollision(akA1, False)
    SNBakaUI.SetNoCollision(akA2, False)
    ; Restore any height-match scaling applied for this pair. Also cosmetic.
    _RestoreActorScale(akA1)
    _RestoreActorScale(akA2)
    ; Establish the "don't re-fight this person" relationship BEFORE anything below gives the attacker
    ; back the means to act on hostility (AI control, aggression). Confirmed bug: this used to run AFTER
    ; _HoldActorAI(akA1, False) and _PacifyActor(akA1, False) — a real timing window where the attacker's
    ; AI could re-evaluate combat with its normal aggression already restored and nothing yet telling it
    ; the player/victim was an ally, so it went straight back into combat seconds after the scene ended
    ; (confirmed in logs — Combat_pace, a third-party combat-AI mod, showed the attacker actively pacing
    ; through the entire window right after cleanup). The attacker returns to normal; the DEFEATED victim
    ; stays SUBDUED — "at the attacker's mercy": aggression is NOT restored and they're allied to the
    ; captor so neither re-aggros, until Release or HelpUp frees them.
    akA1.SetRelationshipRank(akA2, 4)
    ; SNBaka.Captive used to be set only in this NPC-only branch (SetRelationshipRank on an NPC's OWN
    ; faction/AI disposition is what actually needs the != PlayerRef guard -- the player has no AI to
    ; read it). That bundled the tracking flag in with it by accident: SNBaka.Captive is a plain
    ; narrative/state flag, "is this actor currently a subdued captive", which applies exactly the same
    ; whether the victim is the player or an NPC -- and Acheron's OnActorRescued now depends on it being
    ; accurate for BOTH. Confirmed bug: the player never got flagged, so the premature-AcheronNG-rescue
    ; fix silently didn't apply to the exact player scenario it was built for.
    StorageUtil.SetIntValue(akA2, "SNBaka.Captive", 1)
    If akA2 != PlayerRef
        akA2.SetRelationshipRank(akA1, 4)
    EndIf
    _Log("[SNBaka] _EscalationCleanup: relationship rank set (ally) BEFORE releasing AI/aggression — " + akA1 + " <-> " + akA2)
    ; Give the attacker back its AI package (so it resumes normal behavior instead of standing frozen),
    ; but NOT its aggression yet — confirmed in live testing that relationship rank alone isn't reliably
    ; enough to stop the attacker re-engaging (its underlying faction disposition can still read as
    ; hostile). The victim goes right back to being tracked as downed below, so the attacker stays
    ; pacified for exactly as long as the victim stays subdued — _ForceRecover/Acheron's own _Recover
    ; un-pacify the tracked SNBaka.GroundWindowAggressor when the victim is actually freed (HelpUp,
    ; Release, get-up QTE win, or the nobody-around timeout), not here.
    _HoldActorAI(akA1, False)
    _HoldActorAI(akA2, False)
    If akA2 == PlayerRef
        _PacifyActor(akA2, False)
    EndIf
    _Log("[SNBaka] _EscalationCleanup: AI released for " + akA1 + " — aggression stays held until the victim is actually freed")
    If akA1 == PlayerRef || akA2 == PlayerRef
        Game.EnablePlayerControls()
    EndIf
    akA1.SetRestrained(False)
    akA1.SetDontMove(False)
    akA2.SetRestrained(False)
    akA2.SetDontMove(False)
    StorageUtil.SetIntValue(akA1, "SNBaka.Locked",        0)
    StorageUtil.SetIntValue(akA2, "SNBaka.Locked",        0)
    StorageUtil.SetIntValue(akA1, "SNBaka.StopRequested", 0)
    StorageUtil.SetIntValue(akA2, "SNBaka.StopRequested", 0)
    ; Guarantee neither actor is left stuck in a down pose / ground flag after the scene ends.
    StorageUtil.SetIntValue(akA1, "SNBaka.OnGround", 0)
    StorageUtil.SetIntValue(akA2, "SNBaka.OnGround", 0)
    StorageUtil.SetStringValue(akA1, "SNBaka.DownPose", "")
    StorageUtil.SetStringValue(akA2, "SNBaka.DownPose", "")
    Debug.SendAnimationEvent(akA1, "IdleForceDefaultState")
    Debug.SendAnimationEvent(akA2, "IdleForceDefaultState")
    akA1.EvaluatePackage()
    akA2.EvaluatePackage()
    ; RE-DOWN after a defeat-sex scene: the victim (player or NPC) is still a defeated captive, so hand
    ; them back to Acheron (it re-holds + keeps them out of combat, freed only via HelpUp/Release or the
    ; bridge's nobody-around timeout). If Acheron isn't present this no-ops and the pre-existing subdue
    ; state stands. Previously skipped for the player, which is why the PC fully recovered right after sex.
    ; Re-track akA1 as the aggressor for this renewed down cycle — combat was stopped above, so a fresh
    ; GetCombatTarget() capture on Acheron's side would find nothing; set it directly instead, same as
    ; _DefeatGroundWindow does for an initial down. This is also what lets _ForceRecover/_Recover find
    ; akA1 again to finally un-pacify it once the victim is actually freed.
    StorageUtil.SetFormValue(akA2, "SNBaka.GroundWindowAggressor", akA1)
    ; Clean graph reset BEFORE the re-down (same fix as the creature path): OStim's post-scene reset
    ; is async and expression addons fight the skeleton right now — a collapse launched from a dirty
    ; graph intermittently fails to play ("did not animate correctly after the scene").
    Debug.SendAnimationEvent(akA2, "IdleForceDefaultState")
    Utility.Wait(0.5)
    _DelegateDownToAcheron(akA2)
    ; POSE ENFORCEMENT, same as the creature path: force the vanilla bleedout once the async defeat
    ; lands — post-scene graphs regularly eat the native collapse, leaving the victim standing frozen.
    If akA2 != PlayerRef
        Utility.Wait(1.5)
        If !akA2.IsDead()
            ; Respect a stored down pose (TIED victims return to the captured pose, not bleedout).
            String rdPose2 = StorageUtil.GetStringValue(akA2, "SNBaka.DownPose", "")
            If rdPose2 == ""
                rdPose2 = "BleedoutStart"
            EndIf
            Debug.SendAnimationEvent(akA2, rdPose2)
            _Log("[SNBaka] post-scene re-down: pose '" + rdPose2 + "' enforced on " + akA2.GetDisplayName())
        EndIf
    EndIf
    ; Immediate "still down" nudge — same one every other intermediate action gets via UnlockBoth.
    ; Without this, coming back from a sex scene left the LLM waiting on Acheron's own up-to-30s poll
    ; to find out the victim is still down. _CueDecisionIfDowned already no-ops if the victim ISN'T
    ; down (HelpUp/Release already cleared it), so this only fires when there's actually a reason to.
    _CueDecisionIfDowned(akA1, akA2)
    _StartCooldown(akA1)
EndFunction

; Called by SkyrimNet_BakaIntegration.dll when the player finishes the encounter wizard.
; The DLL splits the player's picks into these strings (or role="cancel").
; akAggressor/akVictim are the escalation pair (one is the player).
Function _StartSexLabScene(String role, String intensity, String flavor, String actType, Actor akAggressor, Actor akVictim)
    _Log("[SNBaka] _StartSexLabScene: role=" + role + " intensity=" + intensity + " flavor=" + flavor + " act=" + actType)
    Bool wasDrugged = _bDruggedEscalation
    _bDruggedEscalation = False

    ; ── Cancel: the aggressor changed their mind ─────────────────────────────
    If role == "cancel" || role == ""
        SkyrimNetApi.RegisterEvent("baka_release", \
            akAggressor.GetDisplayName() + " looms over " + akVictim.GetDisplayName() + \
            ", then stops — deciding against it and stepping back.", \
            akAggressor, akVictim)
        _EscalationCleanup(akAggressor, akVictim)
        Return
    EndIf

    ; ── Resolve roles relative to the player ─────────────────────────────────
    Actor npc = akAggressor
    If akAggressor == PlayerRef
        npc = akVictim
    EndIf
    Actor agg = PlayerRef
    Actor vic = npc
    Bool consensual = False
    If role == "they_take_me"
        agg = npc
        vic = PlayerRef
    ElseIf role == "together"
        agg = akAggressor
        vic = None
        consensual = True
    EndIf

    ; ── Normalize the action's act-type + intensity into our SexLab selectors ──
    String sexPos = ""
    If actType == "vaginal"
        sexPos = "vaginal"
    ElseIf actType == "anal" || actType == "painal"
        sexPos = "anal"
    ElseIf actType == "oral"
        sexPos = "oral"
    EndIf
    String sexInt = ""
    If intensity == "rough" || intensity == "brutal"
        sexInt = "aggressive"
    ElseIf intensity == "loving"
        sexInt = "loving"
    EndIf

    ; ── Start the scene (dispatched to the configured framework) ──────────────
    Actor[] sexActors = new Actor[2]
    If consensual
        sexActors[0] = akAggressor
        sexActors[1] = akVictim
    Else
        sexActors[0] = agg
        sexActors[1] = vic
    EndIf
    _StartSexScene(sexActors, vic, agg, sexPos, sexInt)

    ; ── Compose the roleplay narrative for SkyrimNet ─────────────────────────
    String aggName = agg.GetDisplayName()
    String vicName = akVictim.GetDisplayName()
    If !consensual
        vicName = vic.GetDisplayName()
    ElseIf agg == akVictim
        vicName = akAggressor.GetDisplayName()
    EndIf

    ; Present-continuous: the scene is UNFOLDING NOW with these parameters (not a
    ; past/finished statement), so the LLM roleplays it as it happens.
    String verb = " is now having sex with "
    If consensual
        If intensity == "loving"
            verb = " is now tenderly making love to "
        ElseIf intensity == "rough" || intensity == "brutal"
            verb = " is now having rough, eager sex with "
        EndIf
    Else
        If intensity == "brutal"
            verb = " is now violently raping "
        ElseIf intensity == "rough"
            verb = " is now roughly forcing themselves on "
        ElseIf intensity == "loving"
            verb = " is now taking "
        Else
            verb = " is now forcing themselves on "
        EndIf
    EndIf

    String typePhrase = ""
    If actType == "anal"
        typePhrase = ", anal"
    ElseIf actType == "painal"
        typePhrase = ", rough painful anal"
    ElseIf actType == "oral"
        typePhrase = ", oral"
    ElseIf actType == "vaginal"
        typePhrase = ", vaginal"
    EndIf

    String flavorPhrase = ""
    If flavor == "drugged" || wasDrugged
        flavorPhrase = ". " + vicName + " is drugged and unaware — roleplay them as limp and unresponsive"
    ElseIf flavor == "blackmail"
        flavorPhrase = ", coercing them through blackmail"
    ElseIf flavor == "power"
        flavorPhrase = ", abusing a position of power over them"
    ElseIf flavor == "degrading"
        flavorPhrase = ", degrading and humiliating them"
    ElseIf flavor == "gagged"
        flavorPhrase = ", a hand clamped over their mouth to keep them quiet"
    ElseIf flavor == "threatening"
        flavorPhrase = ", threatening them throughout"
    EndIf

    String narrative = aggName + verb + vicName + typePhrase + flavorPhrase + "."
    SkyrimNetApi.RegisterEvent("baka_sexlab_trigger", narrative, agg, akVictim)
    _Notify(narrative)

    _EscalationCleanup(akAggressor, akVictim)
EndFunction

; ============================================================
; Action execute functions — called by SkyrimNet YAML actions
;
; All-All notes:
;   • M/F-named and A01/A02-named animations are role-based.
;     Any initiator gender / target gender combination works.
;   • Actions marked [FEMALE TARGET REQUIRED] gate on HasFemaleBody(akTarget)
;     and return silently if the target has a male body.
;     This is an engine-level gate — bFemaleTargetOnly does not control it.
;
; bResistable = True on all panic actions.
; ============================================================

; ╔══════════════════════════════════════════════════════════════════════════╗
; ║  SCENE CUES TO SKYRIMNET — how every action tells the LLM what's going on. ║
; ║  Two cues per scene so the LLM both REACTS live and REMEMBERS it:          ║
; ║   _CueOngoing : a short-lived event that sits in the live SCENE CONTEXT    ║
; ║      for the scene's length, so the victim + nearby NPCs can react WHILE   ║
; ║      it happens. Phrase it present-tense, name who does what to whom, and   ║
; ║      (for forced acts) say the victim is held/helpless so the reaction      ║
; ║      lands. Keyed per-aggressor so it refreshes, not stacks.               ║
; ║   _CueOutcome : ONE persistent event for memory/history, past-tense, with  ║
; ║      the final result. Replaces the old deflating "X lets go" lines.       ║
; ║  sType is the tag the Director keys reactions off:                         ║
; ║   "baka_forced"  = non-consensual (fear/anger expected)                    ║
; ║   "baka_intimate"= consensual (warm/playful expected)                      ║
; ║  Always originator = aggressor, target = victim.                          ║
; ╚══════════════════════════════════════════════════════════════════════════╝
; Roleplay direction appended to every live scene cue: restate WHO is doing it to WHOM, and describe
; each actor's likely emotional state so the LLM voices whichever one it's generating correctly (the
; victim reacts, the aggressor stays in character). Reads in their NAMES so it's unambiguous.
String Function _RoleplayHint(String sType, Actor akAtk, Actor akVic)
    String a = akAtk.GetDisplayName()
    String v = akVic.GetDisplayName()
    If sType == "baka_forced"
        Return " " + a + " is the aggressor forcing this on " + v + ", who is held and cannot get away. " \
            + v + " would likely be anxious, panicking, frightened, angry, or pleading — whatever fits " + v \
            + "'s personality and this moment; " + a + " is in control and acting with intent."
    ElseIf sType == "baka_intimate"
        Return " " + a + " is being affectionate toward " + v + ". " + v + " might respond shyly, warmly, with surprise, flustered, or playfully — depending on how close the two of them are."
    EndIf
    Return ""
EndFunction

Function _CueOngoing(String sType, String sDesc, Actor akAtk, Actor akVic, Float afSeconds = 25.0)
    If akAtk && akVic
        SkyrimNetApi.RegisterShortLivedEvent("baka_scene_" + akAtk.GetFormID(), \
            sType, sDesc + _RoleplayHint(sType, akAtk, akVic), "", (afSeconds * 1000.0) as Int, akAtk, akVic)
        If bDebugLog
            ; RecordAnimation (called just before this) stored the formal interaction name on the aggressor.
            String act = StorageUtil.GetStringValue(akAtk, "SNBaka.LastAnim", "?")
            _Notify("[Baka] " + act + ": " + akAtk.GetDisplayName() + " -> " + akVic.GetDisplayName())
            _Log("[SNBaka][ACTION] interaction=" + act + " type=" + sType \
                + " aggressor=" + akAtk.GetDisplayName() + " target=" + akVic.GetDisplayName() + " | " + sDesc)
        EndIf
    EndIf
EndFunction

Function _CueOutcome(String sType, String sSummary, Actor akAtk, Actor akVic)
    If akAtk && akVic
        SkyrimNetApi.RegisterEvent(sType, sSummary, akAtk, akVic)
    EndIf
EndFunction

; Resolves a resistable scene to ONE short outcome line: who won. The attacker-win path runs the
; defeat window (its own cue), so this is mostly the victim-escaped case. Third person, no detail —
; the live cue already said what was happening; here we only state the result.
Function _CueResistOutcome(String sType, Actor akAtk, Actor akVic)
    If !akAtk || !akVic
        Return
    EndIf
    String s
    If _bAELVictimEscaped
        s = akVic.GetDisplayName() + " broke free. It is over."
    Else
        s = akAtk.GetDisplayName() + " overpowered " + akVic.GetDisplayName() + ". It is over."
    EndIf
    _CueOutcome(sType, s, akAtk, akVic)
EndFunction

; Prints where a paired scene actually placed the actors (on-screen + log), so positioning can be
; reported precisely. Gated by bDebugPositions. asAnim = the playing event; afX/afY = requested offsets.
; Clear paired-anim position log. Reports the VICTIM's offset relative to the ATTACKER, with the
; attacker as the origin (0,0,0) facing forward: L/R (left-right), F/B (front-back), U (up), and the
; straight-line distance — plus the offset we ASKED for. This is the only positional log you need to
; tune from: e.g. "R12 F40 U-3 dist 42" = victim is 12 right, 40 in front, 3 below the attacker.
Function _LogPair(String sFn, Actor akAtk, Actor akVic, Float wantX, Float wantY, Float rotOffset, Float aAng)
    If !bDebugPositions || !akAtk || !akVic
        Return
    EndIf
    Float wdx = akVic.GetPositionX() - akAtk.GetPositionX()
    Float wdy = akVic.GetPositionY() - akAtk.GetPositionY()
    Int   dz  = (akVic.GetPositionZ() - akAtk.GetPositionZ()) as Int
    ; rotate the world delta back into the attacker's local frame
    Float lr  = (wdx * Math.Cos(aAng)) - (wdy * Math.Sin(aAng))   ; +right / -left
    Float fb  = (wdx * Math.Sin(aAng)) + (wdy * Math.Cos(aAng))   ; +front / -back
    Int   dist = akAtk.GetDistance(akVic) as Int
    String sLR = "R"
    If lr < 0.0
        sLR = "L"
    EndIf
    String sFB = "F"
    If fb < 0.0
        sFB = "B"
    EndIf
    String msg = sFn + ": victim vs attacker(0,0,0) = " \
        + sLR + (Math.Abs(lr) as Int) + " " + sFB + (Math.Abs(fb) as Int) + " U" + dz \
        + "  dist=" + dist + " rot=" + (rotOffset as Int) \
        + "  [asked R/L=" + (wantX as Int) + " F/B=" + (wantY as Int) + "]"
    ; File log only -- the on-screen _Notify version outlived its usefulness (positions are tuned
    ; now, and the corner message fired on every single paired anim).
    _Log("[SNBaka][POS] " + msg + "  aAng=" + (aAng as Int) \
        + "  ATK=" + akAtk.GetDisplayName() + "  VIC=" + akVic.GetDisplayName())
EndFunction

; REV-146a Task 7 — THE APPROACH WINDOW (user ruling 2026-10-23: "walk, not
; teleport; timeout safety; teleport as backup"). Pair-action positioning
; gains the SitOnLap-precedent pattern BEFORE _SetupPair's snap: the NPC
; actor PATHS toward its partner when out of snap range, arrival is polled,
; and a bounded ~8s real-time budget expires into the EXISTING teleport
; (unchanged fallback of record). The player is never walked (never moved
; by us at all, same rule as _SetupPair). Sentinels per leg: walk issued /
; arrived / timeout->teleport fallback.
Float fApproachSnapDist   = 300.0   ; inside this, the snap teleport is invisible (a step, not a jump)
Float fApproachWalkRadius = 150.0   ; PathToReference stop radius
Float fApproachTimeout    = 8.0     ; real-time budget before the teleport fallback
Float fApproachWalkCeiling = 2000.0 ; REV-146a Task 7: manual (player-initiated) pairs admitted from this far
Function _ApproachWindow(Actor akAtk, Actor akVic, String sFn)
    If !akAtk || !akVic || akAtk == PlayerRef || akVic == PlayerRef
        Return
    EndIf
    Float dist = akAtk.GetDistance(akVic)
    If dist <= fApproachSnapDist
        Return   ; already in snap range -- nothing to walk
    EndIf
    _Log("[SNBaka] walk-approach issued: " + akAtk.GetDisplayName() + " -> " + akVic.GetDisplayName() + " (dist=" + dist as Int + ", timeout=" + fApproachTimeout as Int + "s) [" + sFn + "] -- REV-146a")
    Bool bIssued = akAtk.PathToReference(akVic, fApproachWalkRadius)
    If !bIssued
        _Log("[SNBaka] walk-approach issue FAILED (PathToReference false) -> teleport fallback [" + sFn + "] -- REV-146a")
        Return
    EndIf
    Float deadline = Utility.GetCurrentRealTime() + fApproachTimeout
    Bool bArrived = False
    Bool bAbort = False
    While Utility.GetCurrentRealTime() < deadline && !bArrived && !bAbort
        Utility.Wait(0.25)
        If akAtk.GetDistance(akVic) <= fApproachSnapDist
            bArrived = True
        ElseIf akAtk.IsInCombat() || akVic.IsInCombat() || akAtk.IsDead() || akVic.IsDead()
            bAbort = True   ; safety: any interruption hands straight to the fallback
        EndIf
    EndWhile
    akAtk.PathToReference(akAtk, 10.0)   ; cancel any residual path (self-target = stop)
    If bArrived
        _Log("[SNBaka] walk-approach arrived: " + akAtk.GetDisplayName() + " (dist=" + akAtk.GetDistance(akVic) as Int + ") [" + sFn + "] -- REV-146a")
    Else
        _Log("[SNBaka] walk-approach timeout/interrupt (" + fApproachTimeout as Int + "s) -> teleport fallback [" + sFn + "] -- REV-146a")
    EndIf
EndFunction

; ── Shared paired-anim setup ──────────────────────────────────────────────────────────────────
; ONE model for every paired animation:
;   * The ATTACKER (akAtk) is the origin (0,0,0). An NPC attacker is TELEPORTED onto the victim, so
;     the scene always happens where the victim was standing.
;   * The VICTIM (akVic) is then placed relative to the attacker:
;         xLocal = victim RIGHT(+) / LEFT(-)      yLocal = victim FRONT(+) / BACK(-)
;         rotOffset = victim facing minus attacker facing (180 = facing each other)
;   * The PLAYER is NEVER teleported: as the attacker they stay put and the victim comes to them; as
;     the victim they stay put and the attacker is placed so the victim still lands at the offset.
;   * Hard AI stop: DoNothing package + pacify + restrain + SetDontMove + ghost + vehicle-pin, so no
;     other mod / idle replacer can animate them until the scene ends (undone in _CleanupPair).
; mk1/mk2 are pre-placed XMarkers used to vehicle-pin the attacker/victim. sFn = label for the log.
Function _SetupPair(Actor akAtk, Actor akVic, Float xLocal, Float yLocal, Float rotOffset, \
        Bool bDisableCollision, ObjectReference mk1, ObjectReference mk2, String sFn)
    ; REV-146a Task 7: the approach window runs BEFORE the hard AI stop -- an
    ; NPC actor out of snap range WALKS to its partner first (bounded ~8s real-
    ; time, arrival polled), and the unchanged MoveTo snap below is then a short
    ; final step, not a cross-room jump; on timeout/failure the snap is also
    ; the teleport fallback of record. Applies to daemon pairs and any manual
    ; pair that reaches setup (the player is never walked, never moved).
    _ApproachWindow(akAtk, akVic, sFn)
    Bool atkPlayer = (akAtk == PlayerRef)
    Bool vicPlayer = (akVic == PlayerRef)

    akAtk.StopCombat()
    akAtk.StopCombatAlarm()
    akVic.StopCombat()
    akVic.StopCombatAlarm()
    akAtk.StopTranslation()
    akVic.StopTranslation()
    If !atkPlayer
        akAtk.SetVehicle(None)
    EndIf
    If !vicPlayer
        akVic.SetVehicle(None)
    EndIf
    akAtk.EvaluatePackage()
    akVic.EvaluatePackage()
    Utility.Wait(0.1)

    ; HARD AI STOP first, so nothing else drives them while we position. Fixed order, in order:
    ; calm (StopCombat above + pacify here) -> shrink/remove collision -> ghost + AI-hold + restrain/
    ; DontMove -> THEN reposition -> THEN animate (caller starts the anim after this returns). Ghost/
    ; Restrained/DontMove used to be applied AFTER the MoveTo/SetPosition block below, which left a
    ; ~0.2-0.4s window where a freshly-teleported actor was neither ghosted nor movement-locked yet --
    ; exactly the kind of window where residual AI/physics could nudge them before the pose locks in.
    SNBakaUI.SetNoCollision(akAtk, True)
    SNBakaUI.SetNoCollision(akVic, True)
    _HoldActorAI(akAtk, True)
    _HoldActorAI(akVic, True)
    _PacifyActor(akAtk, True)
    _PacifyActor(akVic, True)
    ; _PacifyActor is ONE-WAY: the actor itself stops fighting, but nothing above stops OTHERS from
    ; still TARGETING the victim mid-struggle (ghost only makes their hits whiff — they keep swinging,
    ; confirmed report). Acheron's native pacify is the two-way state the ground phase already enjoys
    ; ("ignoring & ignored by combat" — enemies drop them as a target entirely), and it's list-based
    ; native state, not a spell that wears off, so one call holds until released in _CleanupPair.
    ; VICTIM only: the AGGRESSOR must stay targetable so a genuinely hostile intercessor can still
    ; break the struggle by hitting IT (same rule as the scene paths). The player variant clears
    ; stale locks instead of pacifying — see _ProtectVictimTargeting.
    _ProtectVictimTargeting(akVic)
    If bDisableCollision
        ; BOTH actors, player included -- the player-victim exception here left them the one attackable
        ; participant in any struggle: confirmed from testing, a second falmer attacked the player
        ; mid-struggle and the hit/stagger broke the animation, three times in one session. Explicit
        ; spec: nobody attacks the victim of an aggression in progress. (The old "player isn't ghosted
        ; so they won't fall" concern predates SetNoCollision being applied unconditionally above --
        ; ghost only gates combat hit processing, not world collision, so there's nothing to fall
        ; through.) _CleanupPair already un-ghosts both actors unconditionally on every exit path.
        ;
        ; EXCEPTION: the in-combat grapple takedown deliberately leaves the player vulnerable -- the
        ; whole point is a real risk/reward mid-fight, not another safe struggle. The TARGET still
        ; always gets ghosted (they're the one being grappled into submission); only the player's own
        ; ghost is skipped, and only for this specific mode.
        If !(_bMidCombatGrappleActive && atkPlayer)
            akAtk.SetGhost(True)
        EndIf
        akVic.SetGhost(True)
    EndIf
    ; Re-stamp the mid-combat hit baseline HERE, not just once back in Subdue/ChokeHug_Execute's own
    ; entry. The caller's stamp happens right after LockBoth, before the target is actually ghosted --
    ; LockBoth's own _CalmForAnim wait plus this function's setup take roughly a real second combined,
    ; during which the target (not yet ghosted) can still land one last swing. That swing then tripped
    ; _ShouldAbort's hit-check the instant the QTE poll started, so the grapple "broke" almost the
    ; moment it began, essentially every time. The target is genuinely locked down as of this line, so
    ; only a hit landing from THIS point on (a real mid-grapple interruption) should count.
    If _bMidCombatGrappleActive && atkPlayer
        _fMidCombatHitBaselineRT = _fLastPlayerHitRT
    EndIf
    If !atkPlayer
        akAtk.SetRestrained(True)
        akAtk.SetDontMove(True)
    EndIf
    If !vicPlayer
        akVic.SetRestrained(True)
        akVic.SetDontMove(True)
    EndIf

    ; --- editable offsets (SNBaka_Offsets.ini, key = sFn). Missing file/key falls back to the passed
    ; defaults, so no .ini == co-located + the action's own facing. x=R/L, y=F/B, z=up/down, rot=facing. ---
    Float ox   = SNBakaUI.GetOffset(sFn, "x",   xLocal)
    Float oy   = SNBakaUI.GetOffset(sFn, "y",   yLocal)
    Float oz   = SNBakaUI.GetOffset(sFn, "z",   0.0)
    Float orot = SNBakaUI.GetOffset(sFn, "rot", rotOffset)
    ; NPC -> PLAYER (player is the victim) can need different alignment than player -> NPC. Prefer a
    ; direction-specific "<sFn>_pcvic" key, falling back to the plain key's value above when it's not
    ; in the .ini — so existing tuning keeps working until a _pcvic override is added.
    If vicPlayer
        String kvic = sFn + "_pcvic"
        ox   = SNBakaUI.GetOffset(kvic, "x",   ox)
        oy   = SNBakaUI.GetOffset(kvic, "y",   oy)
        oz   = SNBakaUI.GetOffset(kvic, "z",   oz)
        orot = SNBakaUI.GetOffset(kvic, "rot", orot)
    EndIf
    ; PLAYER -> NPC (player is the attacker) never had the same per-direction override the victim
    ; case got above — it silently fell back to the plain/NPC-vs-NPC key. Player anchor geometry
    ; (vehicle marker, camera pivot) isn't identical to an NPC attacker's, so give it the same
    ; "<sFn>_pcatk" override lever, symmetric with _pcvic.
    If atkPlayer
        String katk = sFn + "_pcatk"
        ox   = SNBakaUI.GetOffset(katk, "x",   ox)
        oy   = SNBakaUI.GetOffset(katk, "y",   oy)
        oz   = SNBakaUI.GetOffset(katk, "z",   oz)
        orot = SNBakaUI.GetOffset(katk, "rot", orot)
    EndIf

    ; --- anchor on the ATTACKER ---
    Float aAng
    If atkPlayer
        aAng = akAtk.GetAngleZ()                       ; player attacker stays put
    ElseIf !vicPlayer
        akAtk.MoveTo(akVic)                            ; NPC attacker teleports ONTO the victim
        Utility.Wait(0.2)
        aAng = akAtk.GetAngleZ()
    Else
        aAng = akVic.GetAngleZ() - orot                ; player victim: keep the player's facing
    EndIf
    Float vAng = aAng + orot
    Float wdx  = (ox * Math.Cos(aAng)) + (oy * Math.Sin(aAng))
    Float wdy  = (oy * Math.Cos(aAng)) - (ox * Math.Sin(aAng))

    If vicPlayer
        ; never move the player — place the ATTACKER at (victim - offset) so victim ends at +offset.
        ; z: victim is +oz above the attacker, so the attacker sits oz BELOW the (fixed) player.
        akAtk.MoveTo(akVic, -wdx, -wdy, 0.0, False)
        Utility.Wait(0.2)                              ; let havok settle before the final snap
        ; Re-anchor off the PLAYER'S current position (not the just-settled attacker): if the
        ; attacker drifted during the settle wait, re-applying its own (drifted) X/Y here — as a
        ; prior version did — baked that drift in permanently once frozen below. Recomputing from
        ; the fixed player + offset guarantees an exact placement regardless of drift.
        akAtk.SetPosition(akVic.GetPositionX() - wdx, akVic.GetPositionY() - wdy, akVic.GetPositionZ() - oz)
        akAtk.SetAngle(0.0, 0.0, aAng)
    Else
        akAtk.SetAngle(0.0, 0.0, aAng)
        akVic.MoveTo(akAtk, wdx, wdy, 0.0, False)       ; victim to attacker + offset
        Utility.Wait(0.2)                              ; let havok settle before the final snap
        ; Re-anchor off the ATTACKER'S settled position (read fresh, not cached before the wait):
        ; either actor can drift a little during the settle, and the old code only re-snapped Z,
        ; leaving X/Y wherever havok left them — that's the "offset looks off" misalignment.
        akVic.SetPosition(akAtk.GetPositionX() + wdx, akAtk.GetPositionY() + wdy, akAtk.GetPositionZ() + oz)
        akVic.SetAngle(0.0, 0.0, vAng)
    EndIf

    ; --- vehicle-pin BOTH (ghost/restrain/DontMove already applied above, before repositioning) ---
    If mk1
        mk1.MoveTo(akAtk)
        If atkPlayer
            mk1.SetPosition(mk1.GetPositionX(), mk1.GetPositionY(), mk1.GetPositionZ() - 2.0 + _fPlayerZAdjust)
        EndIf
        akAtk.SetVehicle(mk1)
    EndIf
    If mk2
        mk2.MoveTo(akVic)
        If vicPlayer
            mk2.SetPosition(mk2.GetPositionX(), mk2.GetPositionY(), mk2.GetPositionZ() - 2.0 + _fPlayerZAdjust)
        EndIf
        akVic.SetVehicle(mk2)
    EndIf
    _HoldPinned(akAtk)
    _HoldPinned(akVic)
    _LogPair(sFn, akAtk, akVic, ox, oy, orot, aAng)
EndFunction

; --- BackHug ---
; Role anims: A1=BaboBackHugStartM/LoopM, A2=BaboBackHugStartF/LoopF
; Works on any gender combination.
Function BackHug_Execute(Actor akInitiator, Actor akTarget)
    _ActionLaneFire(akInitiator, akTarget, "BackHug") ; [REV-174f Leg 4.2] neutral fanned lane (LLM/player-initiated; daemon fires suppressed)
    _Log("[SNBakaACT] BackHug ENTER")
    If !IsEligible(akInitiator, akTarget)
        Return
    EndIf
    If !LockBoth(akInitiator, akTarget)
        Return
    EndIf
    RecordAnimation(akInitiator, "BackHug", akTarget.GetDisplayName())
    RecordAnimation(akTarget,    "BackHug", akInitiator.GetDisplayName())
    _CueOngoing("baka_intimate", \
        akInitiator.GetDisplayName() + " holds " + akTarget.GetDisplayName() + " from behind.", \
        akInitiator, akTarget)

    _ClearTearsForAffection(akInitiator, akTarget)
    PlayPairedLoopAnim(akInitiator, akTarget, \
        0.0, 0.0, 0.0, \
        "BaboBackHugStartM",    "BaboBackHugStartF", \
        "BaboBackHugLoopM",     "BaboBackHugLoopF", \
        2.0, fHugLoopDuration)

    _CueOutcome("baka_intimate", \
        akInitiator.GetDisplayName() + " held " + akTarget.GetDisplayName() + " from behind.", \
        akInitiator, akTarget)
    UnlockBoth(akInitiator, akTarget)
EndFunction

; --- BackHugMolest --- [bResistable]
; A1=BaboBackHugMolestStartM/LoopM, A2=BaboBackHugMolestStartF/LoopF
; Works on any gender combination.
Function BackHugMolest_Execute(Actor akInitiator, Actor akTarget)
    _ActionLaneFire(akInitiator, akTarget, "BackHugMolest") ; [REV-174f Leg 4.2] neutral fanned lane (LLM/player-initiated; daemon fires suppressed)
    _Log("[SNBakaACT] BackHugMolest ENTER")
    If !IsEligible(akInitiator, akTarget)
        Return
    EndIf
    If !LockBoth(akInitiator, akTarget)
        Return
    EndIf
    RecordAnimation(akInitiator, "BackHugMolest", akTarget.GetDisplayName())
    RecordAnimation(akTarget,    "BackHugMolest", akInitiator.GetDisplayName())
    ; REV-150 4.4: register entry 31 reworded line of record (user's 2026-10-24 pen)
    _CueOngoing("baka_forced", \
        akInitiator.GetDisplayName() + " wrapped " + akTarget.GetDisplayName() + " from behind and helped themselves - roaming hands, no invitation offered.", \
        akInitiator, akTarget)
    PlayPanicSound(akTarget)
    _StartTears(akTarget)

    ; xLocal 4 nudges the attacker laterally; yLocal -55 (behind) is tuned for NPC-NPC. NPC-PC
    ; reads too close, so push the attacker ~8 further back whenever the player is involved.
    Float yMolest = fBackHugSep_NPC        ; see POSITIONING TUNING block at top
    If akInitiator == PlayerRef || akTarget == PlayerRef
        yMolest = fBackHugSep_PC
    EndIf
    ; NOTE: BaboBackHugMolest is authored as a FNIS *sequence* (s -a Start + cyclic Loop), not
    ; basic anims like Struggle/ChokeHug. A FNIS sequence is triggered by the START event ONLY —
    ; FNIS auto-chains to the looping continuation. Sending the Loop event ourselves yanked the
    ; actor out of the running sequence (back to default) — which is why it failed every time.
    ; So pass empty loop names: only Start fires, and the cyclic Loop plays on its own.
    PlayPairedLoopAnim(akInitiator, akTarget, \
        0.0, 0.0, 0.0, \
        "BaboBackHugMolestStartM",  "BaboBackHugMolestStartF", \
        "", "", \
        2.5, fMolestLoopDuration, True)

    ; Respect the QTE: only down the victim if they were actually defeated.  If they
    ; broke free (or weren't pinned), release them — no ground window.
    If _bQTEDefeated
        _bQTEDefeated = False
        _UnlockAttackerOnly(akInitiator)
        _DefeatGroundWindow(akInitiator, akTarget)
    Else
        _CueResistOutcome("baka_forced", akInitiator, akTarget)
        UnlockBoth(akInitiator, akTarget)
    EndIf
EndFunction

; --- FrontHug ---
; A1=BaboFrontHugStartM/LoopM, A2=BaboFrontHugStartF/LoopF
; Works on any gender combination.
Function FrontHug_Execute(Actor akInitiator, Actor akTarget)
    _ActionLaneFire(akInitiator, akTarget, "FrontHug") ; [REV-174f Leg 4.2] neutral fanned lane (LLM/player-initiated; daemon fires suppressed)
    _Log("[SNBakaACT] FrontHug ENTER")
    If !IsEligible(akInitiator, akTarget)
        Return
    EndIf
    If !LockBoth(akInitiator, akTarget)
        Return
    EndIf
    RecordAnimation(akInitiator, "FrontHug", akTarget.GetDisplayName())
    RecordAnimation(akTarget,    "FrontHug", akInitiator.GetDisplayName())
    _CueOngoing("baka_intimate", \
        akInitiator.GetDisplayName() + " embraces " + akTarget.GetDisplayName() + ".", \
        akInitiator, akTarget)

    _ClearTearsForAffection(akInitiator, akTarget)
    PlayPairedLoopAnim(akInitiator, akTarget, \
        0.0, 0.0, 180.0, \
        "BaboFrontHugStartM",   "BaboFrontHugStartF", \
        "BaboFrontHugLoopM",    "BaboFrontHugLoopF", \
        2.0, fHugLoopDuration)

    _CueOutcome("baka_intimate", \
        akInitiator.GetDisplayName() + " and " + akTarget.GetDisplayName() + " shared a close embrace.", \
        akInitiator, akTarget)
    UnlockBoth(akInitiator, akTarget)
EndFunction

; --- ArmHold ---
; Affectionate: the initiator takes the target by the arm and holds them close. Gendered M/F
; parts like the hugs (M = initiator, F = target). Single loopable clip — no separate start/loop.
Function ArmHold_Execute(Actor akInitiator, Actor akTarget)
    _ActionLaneFire(akInitiator, akTarget, "ArmHold") ; [REV-174f Leg 4.2] neutral fanned lane (LLM/player-initiated; daemon fires suppressed)
    _Log("[SNBakaACT] ArmHold ENTER")
    If !IsEligible(akInitiator, akTarget)
        Return
    EndIf
    If !LockBoth(akInitiator, akTarget)
        Return
    EndIf
    RecordAnimation(akInitiator, "ArmHold", akTarget.GetDisplayName())
    RecordAnimation(akTarget,    "ArmHold", akInitiator.GetDisplayName())
    _CueOngoing("baka_intimate", \
        akInitiator.GetDisplayName() + " takes " + akTarget.GetDisplayName() + " gently by the arm and holds them close.", \
        akInitiator, akTarget)
    _ClearTearsForAffection(akInitiator, akTarget)
    PlayPairedSimpleAnim(akInitiator, akTarget, \
        0.0, 0.0, 0.0, \
        "BaboHoldArmM", "BaboHoldArmF", \
        fHugLoopDuration)
    _CueOutcome("baka_intimate", \
        akInitiator.GetDisplayName() + " held " + akTarget.GetDisplayName() + " close by the arm.", \
        akInitiator, akTarget)
    UnlockBoth(akInitiator, akTarget)
EndFunction

; --- KissLove ---
; A1=BaboKissLoveS01/S02_A1, A2=BaboKissLoveS01/S02_A2
; Works on any gender combination.
Function KissLove_Execute(Actor akInitiator, Actor akTarget)
    _ActionLaneFire(akInitiator, akTarget, "KissLove") ; [REV-174f Leg 4.2] neutral fanned lane (LLM/player-initiated; daemon fires suppressed)
    _Log("[SNBakaACT] KissLove ENTER")
    If !IsEligible(akInitiator, akTarget)
        Return
    EndIf
    If !LockBoth(akInitiator, akTarget)
        Return
    EndIf
    RecordAnimation(akInitiator, "KissLove", akTarget.GetDisplayName())
    RecordAnimation(akTarget,    "KissLove", akInitiator.GetDisplayName())
    _CueOngoing("baka_intimate", \
        akInitiator.GetDisplayName() + " kisses " + akTarget.GetDisplayName() + " tenderly.", \
        akInitiator, akTarget)

    String[] a1 = new String[2]
    String[] a2 = new String[2]
    ; A1 animations = female role. Swap when male initiator kisses female target.
    Bool kissSwap = (_SexOf(akInitiator) == 0) && (_SexOf(akTarget) == 1)
    If kissSwap
        a1[0] = "BaboKissLoveS01_A2"
        a1[1] = "BaboKissLoveS02_A2"
        a2[0] = "BaboKissLoveS01_A1"
        a2[1] = "BaboKissLoveS02_A1"
    Else
        a1[0] = "BaboKissLoveS01_A1"
        a1[1] = "BaboKissLoveS02_A1"
        a2[0] = "BaboKissLoveS01_A2"
        a2[1] = "BaboKissLoveS02_A2"
    EndIf

    _ClearTearsForAffection(akInitiator, akTarget)
    PlayPairedSequence(akInitiator, akTarget, 0.0, 0.0, 180.0, a1, a2, fKissLoopDuration)

    _CueOutcome("baka_intimate", \
        akInitiator.GetDisplayName() + " and " + akTarget.GetDisplayName() + " shared a kiss.", \
        akInitiator, akTarget)
    UnlockBoth(akInitiator, akTarget)
EndFunction

; --- ForcedKiss --- [bResistable]
; Uses action-specific resist/stop anims: SLAPForcedKiss01_A1/A2_Resist and _Stop.
; Works on any gender combination.
Function ForcedKiss_Execute(Actor akInitiator, Actor akTarget)
    _ActionLaneFire(akInitiator, akTarget, "ForcedKiss") ; [REV-174f Leg 4.2] neutral fanned lane (LLM/player-initiated; daemon fires suppressed)
    _Log("[SNBakaACT] ForcedKiss ENTER")
    If !IsEligible(akInitiator, akTarget)
        Return
    EndIf
    If !LockBoth(akInitiator, akTarget)
        Return
    EndIf
    RecordAnimation(akInitiator, "ForcedKiss", akTarget.GetDisplayName())
    RecordAnimation(akTarget,    "ForcedKiss", akInitiator.GetDisplayName())
    ; REV-150 4.4: register entry 31 reworded line of record (user's 2026-10-24 pen)
    _CueOngoing("baka_forced", \
        akInitiator.GetDisplayName() + " pressed their lips to " + akTarget.GetDisplayName() + "'s mouth mid-word - the kiss taken, not offered.", \
        akInitiator, akTarget)
    PlayPanicSound(akTarget)
    _StartTears(akTarget)

    ; A2_* = aggressor role, A1_* = passive/victim role (SLAP convention).
    ; Initiator is always the aggressor — always plays A2_*. No QTE.
    ; Face-to-face, very close (kiss).
    Float xKiss = fForcedKissSep_NPC
    If akInitiator == PlayerRef || akTarget == PlayerRef
        xKiss = fForcedKissSep_PC
    EndIf
    ; X axis = front-to-back gap for this SLAP kiss anim (its Y reads as lateral, which put them
    ; side-by-side). Keep yLocal 0 so they stay one directly in front of the other.
    ; bRefreshLoop=True: the SLAP kiss loop exits after one cycle, so re-fire it on a tick to keep
    ; the victim in the pose for the full duration (defaults spelled out to reach the trailing flag).
    PlayPairedLoopAnim(akInitiator, akTarget, \
        0.0, 0.0, 180.0, \
        "SLAPForcedKiss01_A2_S01",    "SLAPForcedKiss01_A1_S01", \
        "SLAPForcedKiss01_A2_Loop",   "SLAPForcedKiss01_A1_Loop", \
        2.0, fKissLoopDuration, \
        False, \
        "Babo_DefeatResist_A1_S1", "Babo_DefeatResist_A2_S1", \
        "Babo_DefeatResist_A1_S2", "Babo_DefeatResist_A2_S2", \
        None, True, True)

    _CueOutcome("baka_forced", \
        akInitiator.GetDisplayName() + " forced a kiss on " + akTarget.GetDisplayName() + " against their will.", \
        akInitiator, akTarget)
    UnlockBoth(akInitiator, akTarget)
EndFunction

; --- TouchBreasts --- [FEMALE TARGET REQUIRED]
; A1=Babo_TouchingBreasts_A01, A2=Babo_TouchingBreasts_A02
Function TouchBreasts_Execute(Actor akInitiator, Actor akTarget)
    _ActionLaneFire(akInitiator, akTarget, "TouchBreasts") ; [REV-174f Leg 4.2] neutral fanned lane (LLM/player-initiated; daemon fires suppressed)
    _Log("[SNBakaACT] TouchBreasts ENTER")
    If !IsEligible(akInitiator, akTarget)
        Return
    EndIf
    If !HasFemaleBody(akTarget)
        Return
    EndIf
    If !LockBoth(akInitiator, akTarget)
        Return
    EndIf
    RecordAnimation(akInitiator, "TouchBreasts", akTarget.GetDisplayName())
    RecordAnimation(akTarget,    "TouchBreasts", akInitiator.GetDisplayName())
    _CueOngoing("baka_forced", \
        akInitiator.GetDisplayName() + " gropes " + akTarget.GetDisplayName() + "'s breasts; " + akTarget.GetDisplayName() + " struggles.", \
        akInitiator, akTarget)

    _StartTears(akTarget)
    PlayPairedSimpleAnim(akInitiator, akTarget, \
        0.0, 0.0, 180.0, \
        "Babo_TouchingBreasts_A02", "Babo_TouchingBreasts_A01", \
        fTouchLoopDuration)

    _CueOutcome("baka_forced", \
        akInitiator.GetDisplayName() + " groped " + akTarget.GetDisplayName() + "'s breasts.", \
        akInitiator, akTarget)
    UnlockBoth(akInitiator, akTarget)
EndFunction

; --- SuckBreasts --- [FEMALE TARGET REQUIRED]
; A1=Babo_SuckingBreasts_A01, A2=Babo_SuckingBreasts_A02
Function SuckBreasts_Execute(Actor akInitiator, Actor akTarget)
    _ActionLaneFire(akInitiator, akTarget, "SuckBreasts") ; [REV-174f Leg 4.2] neutral fanned lane (LLM/player-initiated; daemon fires suppressed)
    _Log("[SNBakaACT] SuckBreasts ENTER")
    If !IsEligible(akInitiator, akTarget)
        Return
    EndIf
    If !HasFemaleBody(akTarget)
        Return
    EndIf
    If !LockBoth(akInitiator, akTarget)
        Return
    EndIf
    RecordAnimation(akInitiator, "SuckBreasts", akTarget.GetDisplayName())
    RecordAnimation(akTarget,    "SuckBreasts", akInitiator.GetDisplayName())
    ; REV-150 4.4: register entry 31 reworded line of record (user's 2026-10-24 pen)
    _CueOngoing("baka_forced", \
        akInitiator.GetDisplayName() + " bent to " + akTarget.GetDisplayName() + "'s chest, licking and suck at their breasts.", \
        akInitiator, akTarget)

    _StartTears(akTarget)
    PlayPairedSimpleAnim(akInitiator, akTarget, \
        0.0, 0.0, 180.0, \
        "Babo_SuckingBreasts_A02", "Babo_SuckingBreasts_A01", \
        fTouchLoopDuration)

    _CueOutcome("baka_forced", \
        akInitiator.GetDisplayName() + " forced their mouth on " + akTarget.GetDisplayName() + "'s breasts.", \
        akInitiator, akTarget)
    UnlockBoth(akInitiator, akTarget)
EndFunction

; --- ExaminePrivates --- [FEMALE TARGET REQUIRED] [bResistable]
; A1=BaboExaminePussyA1, A2=BaboExaminePussyA2
Function ExaminePrivates_Execute(Actor akInitiator, Actor akTarget)
    _ActionLaneFire(akInitiator, akTarget, "ExaminePrivates") ; [REV-174f Leg 4.2] neutral fanned lane (LLM/player-initiated; daemon fires suppressed)
    _Log("[SNBakaACT] ExaminePrivates ENTER")
    If !IsEligible(akInitiator, akTarget)
        Return
    EndIf
    If !HasFemaleBody(akTarget)
        Return
    EndIf
    If !LockBoth(akInitiator, akTarget)
        Return
    EndIf
    RecordAnimation(akInitiator, "ExaminePrivates", akTarget.GetDisplayName())
    RecordAnimation(akTarget,    "ExaminePrivates", akInitiator.GetDisplayName())
    _CueOngoing("baka_forced", \
        akInitiator.GetDisplayName() + " forces " + akTarget.GetDisplayName() + " open and examines them; " + akTarget.GetDisplayName() + " struggles.", \
        akInitiator, akTarget)
    PlayPanicSound(akTarget)
    _StartTears(akTarget)

    PlayPairedSimpleAnim(akInitiator, akTarget, \
        0.0, 0.0, 180.0, \
        "BaboExaminePussyA2", "BaboExaminePussyA1", \
        fTouchLoopDuration)

    If _bQTEDefeated
        _Log("[SNBaka] Execute: QTE defeated — calling DefeatGroundWindow. attacker=" + akInitiator.GetDisplayName() + " victim=" + akTarget.GetDisplayName())
        _bQTEDefeated = False
        _UnlockAttackerOnly(akInitiator)
        _DefeatGroundWindow(akInitiator, akTarget)
    Else
        _CueResistOutcome("baka_forced", akInitiator, akTarget)
        UnlockBoth(akInitiator, akTarget)
    EndIf
EndFunction

; --- PlayPrivates --- [FEMALE TARGET REQUIRED] [bResistable]
; A1=BaboPlayingPussyA1, A2=BaboPlayingPussyA2
Function PlayPrivates_Execute(Actor akInitiator, Actor akTarget)
    _ActionLaneFire(akInitiator, akTarget, "PlayPrivates") ; [REV-174f Leg 4.2] neutral fanned lane (LLM/player-initiated; daemon fires suppressed)
    _Log("[SNBakaACT] PlayPrivates ENTER")
    If !IsEligible(akInitiator, akTarget)
        Return
    EndIf
    If !HasFemaleBody(akTarget)
        Return
    EndIf
    If !LockBoth(akInitiator, akTarget)
        Return
    EndIf
    RecordAnimation(akInitiator, "PlayPrivates", akTarget.GetDisplayName())
    RecordAnimation(akTarget,    "PlayPrivates", akInitiator.GetDisplayName())
    _CueOngoing("baka_forced", \
        akInitiator.GetDisplayName() + " gropes " + akTarget.GetDisplayName() + " between the legs; " + akTarget.GetDisplayName() + " struggles.", \
        akInitiator, akTarget)
    PlayPanicSound(akTarget)
    _StartTears(akTarget)

    ; No QTE — Play Privates just plays the loop, then releases (no knockdown).
    PlayPairedSimpleAnim(akInitiator, akTarget, \
        0.0, 0.0, 180.0, \
        "BaboPlayingPussyA2", "BaboPlayingPussyA1", \
        fTouchLoopDuration, False)
    _CueResistOutcome("baka_forced", akInitiator, akTarget)
    UnlockBoth(akInitiator, akTarget)
EndFunction

; --- OralOnTarget --- [FEMALE TARGET REQUIRED]
; A1=BaboSuckingPussyA01, A2=BaboSuckingPussyA02
Function OralOnTarget_Execute(Actor akInitiator, Actor akTarget)
    _ActionLaneFire(akInitiator, akTarget, "OralOnTarget") ; [REV-174f Leg 4.2] neutral fanned lane (LLM/player-initiated; daemon fires suppressed)
    _Log("[SNBakaACT] OralOnTarget ENTER")
    If !IsEligible(akInitiator, akTarget)
        Return
    EndIf
    If !HasFemaleBody(akTarget)
        Return
    EndIf
    If !LockBoth(akInitiator, akTarget)
        Return
    EndIf
    RecordAnimation(akInitiator, "OralOnTarget", akTarget.GetDisplayName())
    RecordAnimation(akTarget,    "OralOnTarget", akInitiator.GetDisplayName())
    ; REV-150 4.4: register entry 31 reworded line of record (user's 2026-10-24 pen)
    _CueOngoing("baka_forced", \
        akInitiator.GetDisplayName() + " dropped to their knees for " + akTarget.GetDisplayName() + " - sucking at their privates.", \
        akInitiator, akTarget)

    _StartTears(akTarget)
    PlayPairedSimpleAnim(akInitiator, akTarget, \
        0.0, 0.0, 180.0, \
        "BaboSuckingPussyA02", "BaboSuckingPussyA01", \
        fTouchLoopDuration)

    _CueOutcome("baka_forced", \
        akInitiator.GetDisplayName() + " forced oral on " + akTarget.GetDisplayName() + ".", \
        akInitiator, akTarget)
    UnlockBoth(akInitiator, akTarget)
EndFunction

; --- Spanking ---
; A1=BaboSpankingM, A2=BaboSpankingF
; Works on any gender combination.
Function Spanking_Execute(Actor akInitiator, Actor akTarget)
    _ActionLaneFire(akInitiator, akTarget, "Spanking") ; [REV-174f Leg 4.2] neutral fanned lane (LLM/player-initiated; daemon fires suppressed)
    _Log("[SNBakaACT] Spanking ENTER")
    If IsInSexAnimation(akInitiator) || IsInSexAnimation(akTarget)
        SpankTarget_Execute(akInitiator, akTarget, True)
        Return
    EndIf
    If !IsEligible(akInitiator, akTarget)
        Return
    EndIf
    If !LockBoth(akInitiator, akTarget)
        Return
    EndIf
    RecordAnimation(akInitiator, "Spanking", akTarget.GetDisplayName())
    RecordAnimation(akTarget,    "Spanking", akInitiator.GetDisplayName())
    _CueOngoing("baka_forced", \
        akInitiator.GetDisplayName() + " spanks " + akTarget.GetDisplayName() + ".", \
        akInitiator, akTarget)
    ; No slap here — the Babo spanking anim plays its own impact, so ours would
    ; double it.  abMoanAtMid=True plays the MOAN ~halfway through (near the impact).
    PlayPairedSimpleAnim(akInitiator, akTarget, \
        0.0, 0.0, 0.0, \
        "BaboSpankingM", "BaboSpankingF", \
        1.0, False, False, True)

    ApplySpankMark(akTarget)
    ApplyFaceMarks(akTarget)
    _StartTears(akTarget)
    ; Every DIRECT spank path (SpankTarget/SlapFace/SlapBreast) records this, but the paired-anim
    ; path never did -- confirmed live: get_spank_state kept reporting has_been_spanked=False (with
    ; the mark overlay applied!) minutes after two of these spanks, so the decorator's "was just
    ; spanked, sting is immediate, reaction unresolved" prompt block -- the dedicated signal that
    ; makes the LLM actually react to a spank -- never activated for menu/LLM spanks.
    RecordSpank(akTarget, akInitiator.GetDisplayName())

    _CueOutcome("baka_forced", \
        akInitiator.GetDisplayName() + " spanked " + akTarget.GetDisplayName() + ".", \
        akInitiator, akTarget)
    UnlockBoth(akInitiator, akTarget)
EndFunction

; --- WombHit --- [bResistable]
; A1=BaboWombHitM (single shot), A2=BaboWombHit (start) + BaboWombHitLoop
; Works on any gender combination.
Function WombHit_Execute(Actor akInitiator, Actor akTarget)
    _ActionLaneFire(akInitiator, akTarget, "WombHit") ; [REV-174f Leg 4.2] neutral fanned lane (LLM/player-initiated; daemon fires suppressed)
    _Log("[SNBakaACT] WombHit ENTER")
    If !IsEligible(akInitiator, akTarget)
        Return
    EndIf
    If !LockBoth(akInitiator, akTarget)
        Return
    EndIf
    RecordAnimation(akInitiator, "WombHit", akTarget.GetDisplayName())
    RecordAnimation(akTarget,    "WombHit", akInitiator.GetDisplayName())
    ; REV-150 4.4: register entry 31 reworded line of record (user's 2026-10-24 pen)
    _CueOngoing("baka_forced", \
        akInitiator.GetDisplayName() + " drove a low, punishing blow into " + akTarget.GetDisplayName() + "'s lower belly - they double over in pain.", \
        akInitiator, akTarget)
    _StartTears(akTarget)
    ; _bQTEDefeated=True so _CleanupPair (inside PlayPairedLoopAnim) skips standing the victim
    ; back up — otherwise the womb-hit victim won't stay down for _DefeatGroundWindow/_Bleedout.
    _bQTEDefeated = True
    ; Sound plays at impact moment (when loop phase starts), not before wind-up.
    PlayPairedLoopAnim(akInitiator, akTarget, \
        0.0, 0.0, 180.0, \
        "BaboWombHitM", "BaboWombHit", \
        "BaboWombHitM", "BaboWombHitLoop", \
        1.0, 0.5, False, \
        "Babo_DefeatResist_A1_S1", "Babo_DefeatResist_A2_S1", \
        "Babo_DefeatResist_A1_S2", "Babo_DefeatResist_A2_S2", \
        akTarget)

    _bQTEDefeated = False
    _UnlockAttackerOnly(akInitiator)
    _DefeatGroundWindow(akInitiator, akTarget)
EndFunction

; --- Flirt ---
; A1=Babo_Flirt_A02/A02D (performer — the one flirting), A2=Babo_Flirt_A01 (observer)
; Works on any gender combination.
Function Flirt_Execute(Actor akInitiator, Actor akTarget)
    _ActionLaneFire(akInitiator, akTarget, "Flirt") ; [REV-174f Leg 4.2] neutral fanned lane (LLM/player-initiated; daemon fires suppressed)
    _Log("[SNBakaACT] Flirt ENTER")
    If !IsEligible(akInitiator, akTarget)
        Return
    EndIf
    If !LockBoth(akInitiator, akTarget)
        Return
    EndIf
    RecordAnimation(akInitiator, "Flirt", akTarget.GetDisplayName())
    RecordAnimation(akTarget,    "Flirt", akInitiator.GetDisplayName())
    _ClearTearsForAffection(akInitiator, akTarget)
    _CueOngoing("baka_intimate", \
        akInitiator.GetDisplayName() + " flirts with " + akTarget.GetDisplayName() + ".", \
        akInitiator, akTarget)

    String[] a1 = new String[2]
    String[] a2 = new String[2]
    a1[0] = "Babo_Flirt_A02D"
    a1[1] = "Babo_Flirt_A02"
    a2[0] = "Babo_Flirt_A01"
    a2[1] = "Babo_Flirt_A01"

    ; X axis = front-to-back for this anim family (its baked root rotation makes marker-X read as
    ; forward). Negative pulls the flirted partner up to match the performer's arm. The player path
    ; (anchorOnPlayer) already looked right, so it keeps its own value (fFlirtSep_PC, default 0).
    Float xFlirt = fFlirtSep_NPC
    If akInitiator == PlayerRef || akTarget == PlayerRef
        xFlirt = fFlirtSep_PC
    EndIf
    PlayPairedSequence(akInitiator, akTarget, 0.0, 0.0, 0.0, a1, a2, fTouchLoopDuration)
    ; Mark that this actor flirted — unlocks the flirt escalations (face/breast/pussy) for a while.
    StorageUtil.SetFloatValue(akInitiator, "SNBaka.LastFlirt", Utility.GetCurrentGameTime())

    _CueOutcome("baka_intimate", \
        akInitiator.GetDisplayName() + " flirted with " + akTarget.GetDisplayName() + ".", \
        akInitiator, akTarget)
    UnlockBoth(akInitiator, akTarget)
EndFunction

; ── Flirt escalations ────────────────────────────────────────────────────────
; Unlocked only AFTER a base Flirt (gated by the baka_flirted decorator on the speaker).
; The speaker is the active toucher (A01); the target is touched (A02); face-to-face (rot 180).
String Function GetFlirted(Actor akActor)
    If !akActor
        Return "false"
    EndIf
    Float last = StorageUtil.GetFloatValue(akActor, "SNBaka.LastFlirt", 0.0)
    ; ~2 game-hours window so the escalation stays available through the conversation.
    If last > 0.0 && (Utility.GetCurrentGameTime() - last) < 0.0833
        Return "true"
    EndIf
    Return "false"
EndFunction

Function _FlirtEscalate(Actor akInitiator, Actor akTarget, String animA1, String animA2, String what, Float rotOffset = 180.0)
    If !IsEligible(akInitiator, akTarget)
        Return
    EndIf
    If !LockBoth(akInitiator, akTarget)
        Return
    EndIf
    RecordAnimation(akInitiator, "Flirt", akTarget.GetDisplayName())
    _CueOngoing("baka_intimate", \
        akInitiator.GetDisplayName() + " " + what + " " + akTarget.GetDisplayName() + ".", \
        akInitiator, akTarget)
    _ClearTearsForAffection(akInitiator, akTarget)
    ; animA1 is played by the INITIATOR (the toucher); pass the toucher-role anim there.
    PlayPairedSimpleAnim(akInitiator, akTarget, 0.0, 0.0, rotOffset, animA1, animA2, fTouchLoopDuration)
    ; Keep the escalation window alive so the chain can continue.
    StorageUtil.SetFloatValue(akInitiator, "SNBaka.LastFlirt", Utility.GetCurrentGameTime())
    _CueOutcome("baka_intimate", \
        akInitiator.GetDisplayName() + " and " + akTarget.GetDisplayName() + " shared a charged, intimate moment.", \
        akInitiator, akTarget)
    UnlockBoth(akInitiator, akTarget)
EndFunction

; Initiator plays the _A02 (toucher) role; target plays _A01. Caress = face-to-face (rot 180);
; tease breasts/below = same direction (rot 0), with the initiator behind for "below".
Function FlirtFace_Execute(Actor akInitiator, Actor akTarget)
    _ActionLaneFire(akInitiator, akTarget, "FlirtFace") ; [REV-174f Leg 4.2] neutral fanned lane (LLM/player-initiated; daemon fires suppressed)
    _Log("[SNBakaACT] FlirtFace ENTER")
    _FlirtEscalate(akInitiator, akTarget, "Babo_FlirtFace_A02", "Babo_FlirtFace_A01", "tenderly caresses the face of", 180.0)
EndFunction

Function FlirtBreast_Execute(Actor akInitiator, Actor akTarget)
    _ActionLaneFire(akInitiator, akTarget, "FlirtBreast") ; [REV-174f Leg 4.2] neutral fanned lane (LLM/player-initiated; daemon fires suppressed)
    _Log("[SNBakaACT] FlirtBreast ENTER")
    _FlirtEscalate(akInitiator, akTarget, "Babo_FlirtBreast_A02", "Babo_FlirtBreast_A01", "playfully fondles the breasts of", 0.0)
EndFunction

Function FlirtPussy_Execute(Actor akInitiator, Actor akTarget)
    _ActionLaneFire(akInitiator, akTarget, "FlirtPussy") ; [REV-174f Leg 4.2] neutral fanned lane (LLM/player-initiated; daemon fires suppressed)
    _Log("[SNBakaACT] FlirtPussy ENTER")
    _FlirtEscalate(akInitiator, akTarget, "Babo_FlirtPussy_A02", "Babo_FlirtPussy_A01", "slips a hand between the legs of", 0.0)
EndFunction

; Stops the LLM from looping "inspect" forever on a downed victim. Returns False if the inspect
; should be SKIPPED (already inspected enough this down) — and nudges the aggressor to do something
; else. When it proceeds on a downed victim it bumps the count AND keeps their down-timer alive
; (so they stay protected while real interactions happen).
Bool Function _InspectGuard(Actor akInitiator, Actor akTarget)
    If !_IsDownedAny(akTarget)
        Return True
    EndIf
    Int ic = StorageUtil.GetIntValue(akTarget, "SNBaka.InspectCount", 0)
    If ic >= 2
        SkyrimNetApi.RegisterEvent("baka_forced", \
            akInitiator.GetDisplayName() + " has already looked " + akTarget.GetDisplayName() + " over thoroughly — there is nothing more to learn from inspecting again. Time to escalate, take what is wanted, or move on.", \
            akInitiator, akTarget)
        _Log("[SNBaka] _InspectGuard: inspect loop capped on " + akTarget.GetDisplayName())
        Return False
    EndIf
    StorageUtil.SetIntValue(akTarget, "SNBaka.InspectCount", ic + 1)
    _bResetDownWindow = True
    Return True
EndFunction

; --- CapturedInspect --- [FEMALE TARGET REQUIRED] [bResistable]
; Sequence includes CapturedBoob and CapturedPussy stages — requires female A2.
Function CapturedInspect_Execute(Actor akInitiator, Actor akTarget)
    _ActionLaneFire(akInitiator, akTarget, "CapturedInspect") ; [REV-174f Leg 4.2] neutral fanned lane (LLM/player-initiated; daemon fires suppressed)
    _Log("[SNBakaACT] CapturedInspect ENTER")
    If !IsEligible(akInitiator, akTarget)
        Return
    EndIf
    If !HasFemaleBody(akTarget)
        Return
    EndIf
    If !_InspectGuard(akInitiator, akTarget)
        Return
    EndIf
    If !LockBoth(akInitiator, akTarget)
        Return
    EndIf
    RecordAnimation(akInitiator, "CapturedInspect", akTarget.GetDisplayName())
    RecordAnimation(akTarget,    "CapturedInspect", akInitiator.GetDisplayName())
    _CueOngoing("baka_forced", \
        akInitiator.GetDisplayName() + " inspects captured " + akTarget.GetDisplayName() + "'s body; " + akTarget.GetDisplayName() + " struggles.", \
        akInitiator, akTarget)
    PlayPanicSound(akTarget)
    _StartTears(akTarget)

    String[] a1 = new String[3]
    String[] a2 = new String[3]
    a1[0] = "Babo_Captured_A2"
    a1[1] = "Babo_CapturedBoob_A2"
    a1[2] = "Babo_CapturedPussy_A2"
    a2[0] = "Babo_Captured_A1"
    a2[1] = "Babo_CapturedBoob_A1"
    a2[2] = "Babo_CapturedPussy_A1"

    ; No QTE and no knockdown from the menu — play the sequence through, then release.
    ; (The downed-victim re-down version is _DownedReplay, used by the second menu.)
    PlayPairedSequence(akInitiator, akTarget, 0.0, 0.0, 180.0, a1, a2, fSequenceStageTimer, False)
    _CueResistOutcome("baka_forced", akInitiator, akTarget)
    UnlockBoth(akInitiator, akTarget)
EndFunction

; --- Investigate --- [FEMALE TARGET REQUIRED] [bResistable]
; Thorough 3-stage inspection — requires female A2.
Function Investigate_Execute(Actor akInitiator, Actor akTarget)
    _ActionLaneFire(akInitiator, akTarget, "Investigate") ; [REV-174f Leg 4.2] neutral fanned lane (LLM/player-initiated; daemon fires suppressed)
    _Log("[SNBakaACT] Investigate ENTER")
    If !IsEligible(akInitiator, akTarget)
        Return
    EndIf
    If !HasFemaleBody(akTarget)
        Return
    EndIf
    If !_InspectGuard(akInitiator, akTarget)
        Return
    EndIf
    If !LockBoth(akInitiator, akTarget)
        Return
    EndIf
    RecordAnimation(akInitiator, "Investigate", akTarget.GetDisplayName())
    RecordAnimation(akTarget,    "Investigate", akInitiator.GetDisplayName())
    _CueOngoing("baka_forced", \
        akInitiator.GetDisplayName() + " inspects " + akTarget.GetDisplayName() + "'s body; " + akTarget.GetDisplayName() + " struggles.", \
        akInitiator, akTarget)
    PlayPanicSound(akTarget)
    _StartTears(akTarget)

    String[] a1 = new String[3]
    String[] a2 = new String[3]
    a1[0] = "Babo_Investigation_S01_A02"
    a1[1] = "Babo_Investigation_S02_A02"
    a1[2] = "Babo_Investigation_S03_A02"
    a2[0] = "Babo_Investigation_S01_A01"
    a2[1] = "Babo_Investigation_S02_A01"
    a2[2] = "Babo_Investigation_S03_A01"

    ; No QTE and no knockdown from the menu — play the sequence through, then release.
    ; (The downed-victim re-down version is _DownedReplay, used by the second menu.)
    ; Investigation stage 0 is authored with the aggressor turned 180; force only akA1 flipped
    ; on stage 0 (afA1Stage0Rot=180), restored from stage 1 on. Stages 2-3 already look right.
    PlayPairedSequence(akInitiator, akTarget, 0.0, 0.0, 180.0, a1, a2, fSequenceStageTimer, False, True, 180.0)
    _CueResistOutcome("baka_forced", akInitiator, akTarget)
    UnlockBoth(akInitiator, akTarget)
EndFunction

; SkyrimNet's PapyrusQuestAction dispatch validates parameterMapping count against the TARGET
; function's own parameter count -- Papyrus default values (abFromHit below) don't exempt a trailing
; parameter from that check the way a direct Papyrus-to-Papyrus call would. Confirmed live error:
; "Parameter mapping count (2) doesn't match function parameter count (3) for action 'PinHelpless'"
; -- both down_pin.yaml (PinHelpless) and struggle.yaml (Struggle) declare only 2 mapped parameters
; against Struggle_Execute's 3, silently failing to dispatch for every LLM/NPC-initiated call. Two-
; parameter wrapper gives both YAML actions an exact signature match instead.
Function PinHelpless_Execute(Actor akInitiator, Actor akTarget)
    _ActionLaneFire(akInitiator, akTarget, "PinHelpless") ; [REV-174f Leg 4.2] neutral fanned lane (LLM/player-initiated; daemon fires suppressed)
    Struggle_Execute(akInitiator, akTarget, False)
EndFunction

; --- Subdue --- [bResistable] -- in-combat grapple takedown menu only, not LLM/YAML-facing.
; Same "Babo_DefeatResist_A1_S1"/"A2_S1" crouching-straddler/pinned-down pose _DoEscalation already
; uses to force a DOWNED victim onto the ground before a scene -- reused here as the takedown itself,
; made resistable (the target isn't already beaten in this context, so they get a real chance to
; fight it off). One static hold via PlayPairedSimpleAnim, not a 5-stage sequence -- both faster on
; its own merits and immune to PlayPairedSequence's per-stage pacing entirely.
Function Subdue_Execute(Actor akInitiator, Actor akTarget, Bool abFromHit = False)
    _ActionLaneFire(akInitiator, akTarget, "Subdue") ; [REV-174f Leg 4.2] neutral fanned lane (LLM/player-initiated; daemon fires suppressed)
    _Log("[SNBakaACT] Subdue ENTER")
    If !IsEligible(akInitiator, akTarget, abFromHit)
        Return
    EndIf
    If !LockBoth(akInitiator, akTarget)
        Return
    EndIf
    ; Cache locally: _CleanupPair (run inside PlayPairedSimpleAnim, below) already clears
    ; _bMidCombatGrappleActive before control returns here, so the module var can't be trusted
    ; for the post-anim outcome branch — only this local snapshot can.
    Bool wasMidCombat = False
    If abFromHit && akInitiator == PlayerRef
        _bMidCombatGrappleActive = True
        _fMidCombatHitBaselineRT = _fLastPlayerHitRT
        wasMidCombat = True
    EndIf
    RecordAnimation(akInitiator, "Subdue", akTarget.GetDisplayName())
    RecordAnimation(akTarget,    "Subdue", akInitiator.GetDisplayName())
    ; REV-150 4.4: register entry 31 reworded line of record (user's 2026-10-24 pen)
    _CueOngoing("baka_forced", \
        akInitiator.GetDisplayName() + " pinned " + akTarget.GetDisplayName() + " flat and kept them there - not allowing them to rise.", \
        akInitiator, akTarget)
    _StartTears(akTarget)
    If bExpressionsEnabled
        _ApplyMoodExpression(akTarget, "afraid")
    EndIf

    ; A decisive mid-fight takedown reads as fast, not a leisurely molest hold — fMolestLoopDuration
    ; (8s, tuned for the non-combat context) stays untouched for every other caller. 2.5 (2.2s of
    ; actual AEL window after the 0.3s pre-QTE delay) was cut too far: confirmed live, the AEL Flash
    ; QTE never once completed in that window -- every attempt timed out before the overlay could
    ; register a result (compare Choke Behind's PlayPairedSequence maxWait, ~15s, never touched).
    ; 5.0 (4.7s of real QTE window) still lands far under the original 8s while giving AEL room to
    ; actually resolve a genuine win or loss instead of always timing out to "escaped".
    Float subdueDuration = fMolestLoopDuration
    If wasMidCombat
        subdueDuration = 5.0
    EndIf

    ; rotOffset=0 (not 180): per _SetupPair's own convention ("0 = same dir as A2, 180 = facing A2"),
    ; this is a from-behind/on-top takedown pose, not a face-to-face one. The 180 default previously
    ; here was copied blind from _DoEscalation's OWN inline positioning math, which anchors off the
    ; VICTIM (already downed, stationary) — a different coordinate convention than _SetupPair's
    ; attacker-anchored one used here. Confirmed wrong live (victim faced 180 off).
    PlayPairedSimpleAnim(akInitiator, akTarget, \
        0.0, 0.0, 0.0, \
        "Babo_DefeatResist_A2_S1", "Babo_DefeatResist_A1_S1", \
        subdueDuration, True)

    If _bQTEDefeated
        _Log("[SNBaka] Subdue: QTE defeated — calling DefeatGroundWindow. attacker=" + akInitiator.GetDisplayName() + " victim=" + akTarget.GetDisplayName())
        _bQTEDefeated = False
        _UnlockAttackerOnly(akInitiator)
        _DefeatGroundWindow(akInitiator, akTarget)
    Else
        If wasMidCombat
            ; The target broke free of a live grapple attempt — not a "loser recovering from a struggle"
            ; (_RecoveryPeriod would shove them into ANOTHER ~10s restrained/bleedout hold, reading as
            ; "calm"/helpless). Dispel the Calm LockBoth/_SetupPair applied and force them straight back
            ; into combat — a hostile target that resisted should still be fighting, not standing dazed.
            _Log("[SNBaka] Subdue outcome: mid-combat grapple broken — releasing " + akTarget.GetDisplayName() + " back to combat (not a defeat)")
            If SNBakaCalm
                akTarget.DispelSpell(SNBakaCalm)
            EndIf
            akTarget.StartCombat(akInitiator)
        ElseIf !_bAELVictimEscaped
            _Log("[SNBaka] Subdue outcome: attacker won the exchange (not a fresh QTE-defeat) — _RecoveryPeriod on " + akTarget)
            _RecoveryPeriod(akTarget, akInitiator, 10.0)
        ElseIf _IsDownedAny(akTarget)
            _Log("[SNBaka] Subdue outcome: victim escaped AND was already downed — _ForceRecover on " + akTarget)
            _ForceRecover(akTarget)
        Else
            _Log("[SNBaka] Subdue outcome: victim escaped, was not downed to begin with — no recovery action needed")
        EndIf
        _CueResistOutcome("baka_forced", akInitiator, akTarget)
        If bExpressionsEnabled
            _ClearExpression(akTarget)
        EndIf
        UnlockBoth(akInitiator, akTarget)
    EndIf
EndFunction

; --- Struggle --- [bResistable]
; 5-stage grapple. Works on any gender combination.
; abFromHit: set ONLY by the on-hit mid-combat path (OnCreatureHitFollower's humanoid branch) --
; relaxes IsEligible's attacker-in-combat gate for exactly that call, since a struggle triggered BY a
; combat hit is mid-combat by definition. YAML invocations go through PinHelpless_Execute above
; instead (SkyrimNet's own dispatcher needs an exact parameter-count match, see that function).
Function Struggle_Execute(Actor akInitiator, Actor akTarget, Bool abFromHit = False)
    _ActionLaneFire(akInitiator, akTarget, "Struggle") ; [REV-174f Leg 4.2] neutral fanned lane (LLM/player-initiated; daemon fires suppressed)
    _Log("[SNBakaACT] Struggle ENTER")
    If !IsEligible(akInitiator, akTarget, abFromHit)
        Return
    EndIf
    If !LockBoth(akInitiator, akTarget)
        Return
    EndIf
    ; In-combat grapple takedown (interact power's Grapple menu, NOT the reactive on-hit pipeline
    ; where an NPC/creature aggressor is the one passing abFromHit=True): only the player initiating
    ; while abFromHit is set means this specific call is that path. Drives _SetupPair's ghost
    ; exemption and _ShouldAbort's new hit-abort check for the duration of this one animation.
    If abFromHit && akInitiator == PlayerRef
        _bMidCombatGrappleActive = True
        _fMidCombatHitBaselineRT = _fLastPlayerHitRT
    EndIf
    RecordAnimation(akInitiator, "Struggle", akTarget.GetDisplayName())
    RecordAnimation(akTarget,    "Struggle", akInitiator.GetDisplayName())
    ; REV-150 4.4: register entry 31 reworded line of record (user's 2026-10-24 pen)
    _CueOngoing("baka_forced", \
        akInitiator.GetDisplayName() + " grappled " + akTarget.GetDisplayName() + " into a struggle - the stronger will decides the terms.", \
        akInitiator, akTarget)
    _StartTears(akTarget)
    If bExpressionsEnabled
        _ApplyMoodExpression(akTarget, "afraid")
    EndIf

    String[] a1 = new String[5]
    String[] a2 = new String[5]
    a1[0] = "Babo_Struggle_S01_A02"
    a1[1] = "Babo_Struggle_S02_A02"
    a1[2] = "Babo_Struggle_S03_A02"
    a1[3] = "Babo_Struggle_S04_A02"
    a1[4] = "Babo_Struggle_S05_A02"
    a2[0] = "Babo_Struggle_S01_A01"
    a2[1] = "Babo_Struggle_S02_A01"
    a2[2] = "Babo_Struggle_S03_A01"
    a2[3] = "Babo_Struggle_S04_A01"
    a2[4] = "Babo_Struggle_S05_A01"

    ; New convention: the victim sits FRONT-LEFT of the attacker. fStruggleSep_* = how far in FRONT
    ; (yLocal +), fStruggleLeft = how far to the LEFT (xLocal -). Co-located is 0,0; tune from the
    ; "[Baka] Sequence ...: victim vs attacker(0,0,0) = L.. F.." log line.
    Float yFront = fStruggleSep_NPC
    If akInitiator == PlayerRef            ; player is the attacker
        yFront = fStruggleSep_PCAtk
    ElseIf akTarget == PlayerRef           ; player is the victim
        yFront = fStruggleSep_PCVic
    EndIf
    PlayPairedSequence(akInitiator, akTarget, fStruggleLeft, yFront, 0.0, a1, a2, fSequenceStageTimer, True)

    If _bQTEDefeated
        _Log("[SNBaka] Execute: QTE defeated — calling DefeatGroundWindow. attacker=" + akInitiator.GetDisplayName() + " victim=" + akTarget.GetDisplayName())
        _bQTEDefeated = False
        _UnlockAttackerOnly(akInitiator)
        _DefeatGroundWindow(akInitiator, akTarget)
    Else
        If !_bAELVictimEscaped
            _Log("[SNBaka] struggle outcome: attacker won the exchange (not a fresh QTE-defeat) — _RecoveryPeriod on " + akTarget)
            _RecoveryPeriod(akTarget, akInitiator, 10.0)
        ElseIf _IsDownedAny(akTarget)
            ; Three ways up, full stop: HelpUp, nobody around, or winning the QTE. This is #3 — the
            ; victim beat a PinHelpless/ChokeHelpless attempt made against them while already downed, so
            ; they're up, period. _ForceRecover clears the hold AND stands them up; _CleanupPair (already
            ; run by PlayPairedSequence) separately restores the attacker's normal aggression/AI, which is
            ; correct here since the victim is genuinely no longer downed — the fight can resume for real.
            _Log("[SNBaka] struggle outcome: victim escaped AND was already downed — _ForceRecover (condition #3) on " + akTarget)
            _ForceRecover(akTarget)
        Else
            _Log("[SNBaka] struggle outcome: victim escaped, was not downed to begin with — no recovery action needed")
        EndIf
        _CueResistOutcome("baka_forced", akInitiator, akTarget)
        If bExpressionsEnabled
            _ClearExpression(akTarget)
        EndIf
        UnlockBoth(akInitiator, akTarget)
    EndIf
EndFunction

; SkyrimNet's dispatcher needs an exact parameterMapping-count match against the target function --
; adding abFromHit to ChokeHug_Execute (for the in-combat grapple menu) would otherwise silently
; break both choke_hug.yaml (ChokeHug) and down_choke.yaml (ChokeHelpless), the same class of bug
; already fixed once this session for PinHelpless/Struggle (see that wrapper's own comment). Both
; YAMLs now point here instead.
Function ChokeHelpless_Execute(Actor akInitiator, Actor akTarget)
    _ActionLaneFire(akInitiator, akTarget, "ChokeHelpless") ; [REV-174f Leg 4.2] neutral fanned lane (LLM/player-initiated; daemon fires suppressed)
    ChokeHug_Execute(akInitiator, akTarget, False)
EndFunction

; --- ChokeHug --- [bResistable]
; 5-stage chokehold. Works on any gender combination.
Function ChokeHug_Execute(Actor akInitiator, Actor akTarget, Bool abFromHit = False)
    _ActionLaneFire(akInitiator, akTarget, "ChokeHug") ; [REV-174f Leg 4.2] neutral fanned lane (LLM/player-initiated; daemon fires suppressed)
    _Log("[SNBakaACT] ChokeHug ENTER")
    If !IsEligible(akInitiator, akTarget, abFromHit)
        Return
    EndIf
    If !LockBoth(akInitiator, akTarget)
        Return
    EndIf
    ; In-combat grapple takedown (see Struggle_Execute's identical comment) -- only the player
    ; initiating with abFromHit set means this specific call is the mid-combat menu path.
    ; Cached locally: _CleanupPair (run inside PlayPairedSequence, below) already clears
    ; _bMidCombatGrappleActive before control returns here.
    Bool wasMidCombat = False
    If abFromHit && akInitiator == PlayerRef
        _bMidCombatGrappleActive = True
        _fMidCombatHitBaselineRT = _fLastPlayerHitRT
        wasMidCombat = True
    EndIf
    RecordAnimation(akInitiator, "ChokeHug", akTarget.GetDisplayName())
    RecordAnimation(akTarget,    "ChokeHug", akInitiator.GetDisplayName())
    ; REV-150 4.4: register entry 31 reworded line of record (user's 2026-10-24 pen)
    _CueOngoing("baka_forced", \
        akInitiator.GetDisplayName() + " caught " + akTarget.GetDisplayName() + " in a choke-held embrace - possessively holing them much too tightly for comfort.", \
        akInitiator, akTarget)
    PlayPanicSound(akTarget)
    _StartTears(akTarget)
    If bExpressionsEnabled
        _ApplyMoodExpression(akTarget, "pained")
    EndIf

    String[] a1 = new String[5]
    String[] a2 = new String[5]
    a1[0] = "Babo_ChokeHug_S01_A02"
    a1[1] = "Babo_ChokeHug_S02_A02"
    a1[2] = "Babo_ChokeHug_S03_A02"
    a1[3] = "Babo_ChokeHug_S04_A02"
    a1[4] = "Babo_ChokeHug_S05_A02"
    a2[0] = "Babo_ChokeHug_S01_A01"
    a2[1] = "Babo_ChokeHug_S02_A01"
    a2[2] = "Babo_ChokeHug_S03_A01"
    a2[3] = "Babo_ChokeHug_S04_A01"
    a2[4] = "Babo_ChokeHug_S05_A01"

    ; ChokeHug action ONLY (not the escalate-defeat choke in _DoEscalation). xLocal=0 (no lateral
    ; shift — that put the attacker off to the side); the choke anim seats the attacker directly
    ; behind the victim. NPC-NPC self-seats ~15 apart (offset 0); when the player is the victim it
    ; reads too close, so push the attacker further back. See POSITIONING TUNING block at top.
    Float yChoke = fChokeHugSep_NPC
    If akTarget == PlayerRef
        yChoke = fChokeHugSep_PCVic
    EndIf
    PlayPairedSequence(akInitiator, akTarget, 0.0, 0.0, 0.0, a1, a2, fSequenceStageTimer, True)

    If _bQTEDefeated
        _Log("[SNBaka] Execute: QTE defeated — calling DefeatGroundWindow. attacker=" + akInitiator.GetDisplayName() + " victim=" + akTarget.GetDisplayName())
        _bQTEDefeated = False
        _UnlockAttackerOnly(akInitiator)
        ; Choke knocks the victim out — female victims faint (BaboFaintF). No male faint anim exists,
        ; so males fall through to the default trauma down-pose.
        If _SexOf(akTarget) == 1
            _sDownPose = "BaboFaintF"
        EndIf
        _DefeatGroundWindow(akInitiator, akTarget)
    Else
        If wasMidCombat
            ; See Subdue_Execute's identical branch: a broken-free grapple target must go straight
            ; back to combat, not into _RecoveryPeriod's ~10s restrained/bleedout "recovering" hold
            ; (which reads as calm/helpless, not liberated).
            _Log("[SNBaka] ChokeHug outcome: mid-combat grapple broken — releasing " + akTarget.GetDisplayName() + " back to combat (not a defeat)")
            If SNBakaCalm
                akTarget.DispelSpell(SNBakaCalm)
            EndIf
            akTarget.StartCombat(akInitiator)
        ElseIf !_bAELVictimEscaped
            _Log("[SNBaka] struggle outcome: attacker won the exchange (not a fresh QTE-defeat) — _RecoveryPeriod on " + akTarget)
            _RecoveryPeriod(akTarget, akInitiator, 10.0)
        ElseIf _IsDownedAny(akTarget)
            ; Three ways up, full stop: HelpUp, nobody around, or winning the QTE. This is #3 — the
            ; victim beat a PinHelpless/ChokeHelpless attempt made against them while already downed, so
            ; they're up, period. _ForceRecover clears the hold AND stands them up; _CleanupPair (already
            ; run by PlayPairedSequence) separately restores the attacker's normal aggression/AI, which is
            ; correct here since the victim is genuinely no longer downed — the fight can resume for real.
            _Log("[SNBaka] struggle outcome: victim escaped AND was already downed — _ForceRecover (condition #3) on " + akTarget)
            _ForceRecover(akTarget)
        Else
            _Log("[SNBaka] struggle outcome: victim escaped, was not downed to begin with — no recovery action needed")
        EndIf
        _CueResistOutcome("baka_forced", akInitiator, akTarget)
        If bExpressionsEnabled
            _ClearExpression(akTarget)
        EndIf
        UnlockBoth(akInitiator, akTarget)
    EndIf
EndFunction

; --- DrunkExploit --- [bResistable]
; 5-stage. S05 = liberation (star pattern). Attacker behind victim, same facing direction.
; Works on any gender combination.
Function DrunkExploit_Execute(Actor akInitiator, Actor akTarget)
    _ActionLaneFire(akInitiator, akTarget, "DrunkExploit") ; [REV-174f Leg 4.2] neutral fanned lane (LLM/player-initiated; daemon fires suppressed)
    _Log("[SNBakaACT] DrunkExploit ENTER")
    If !IsEligible(akInitiator, akTarget)
        Return
    EndIf
    If !LockBoth(akInitiator, akTarget)
        Return
    EndIf
    RecordAnimation(akInitiator, "DrunkExploit", akTarget.GetDisplayName())
    RecordAnimation(akTarget,    "DrunkExploit", akInitiator.GetDisplayName())
    _CueOngoing("baka_forced", \
        akInitiator.GetDisplayName() + " gropes " + akTarget.GetDisplayName() + ", drunk and defenseless.", \
        akInitiator, akTarget)

    String[] a1 = new String[5]
    String[] a2 = new String[5]
    a1[0] = "Babo_Drunk_S01_A02"
    a1[1] = "Babo_Drunk_S02_A02"
    a1[2] = "Babo_Drunk_S03_A02"
    a1[3] = "Babo_Drunk_S04_A02"
    a1[4] = "Babo_Drunk_S05_A02"
    a2[0] = "Babo_Drunk_S01_A01"
    a2[1] = "Babo_Drunk_S02_A01"
    a2[2] = "Babo_Drunk_S03_A01"
    a2[3] = "Babo_Drunk_S04_A01"
    a2[4] = "Babo_Drunk_S05_A01"

    ; Resistable (bResistable=True): the final Drunk stage is the victim shaking off the stupor
    ; and breaking away. Attacker wins -> victim collapses (DefeatGroundWindow). Victim "escapes"
    ; -> break-free stage plays and they recover. Player path = QTE; NPC-NPC = random outcome.
    ; Player-as-attacker sits ~1 unit too high in this anim — drop the player's pin-marker 1 more.
    If akInitiator == PlayerRef
        _fPlayerZAdjust = -1.0
    EndIf
    PlayPairedSequence(akInitiator, akTarget, 0.0, 0.0, 0.0, a1, a2, fSequenceStageTimer, True)   ; co-located base; tune from the [Baka] log
    _fPlayerZAdjust = 0.0
    If _bQTEDefeated
        _bQTEDefeated = False
        _UnlockAttackerOnly(akInitiator)
        _DefeatGroundWindow(akInitiator, akTarget)
    Else
        If !_bAELVictimEscaped
            _RecoveryPeriod(akTarget, akInitiator, 8.0)
        EndIf
        _CueResistOutcome("baka_forced", akInitiator, akTarget)
        UnlockBoth(akInitiator, akTarget)   ; <-- was missing: left the power soft-locked on a drunk-exploit escape
    EndIf
EndFunction

; --- DrugFood ---
; A1=Babo_DruggedFoodConsumptionM (the one administering the drugged food),
; A2=Babo_DruggedFoodConsumptionF (the one consuming it).
; No QTE — the drug does the work. Victim collapses into a full ground window identical
; to a QTE defeat, giving the initiator the escalation window with unconscious-victim
; context passed to SkyrimNet and SexLab.
; Works on any gender combination.
Function DrugFood_Execute(Actor akInitiator, Actor akTarget)
    _ActionLaneFire(akInitiator, akTarget, "DrugFood") ; [REV-174f Leg 4.2] neutral fanned lane (LLM/player-initiated; daemon fires suppressed)
    _Log("[SNBakaACT] DrugFood ENTER")
    If !IsEligible(akInitiator, akTarget)
        Return
    EndIf
    If !LockBoth(akInitiator, akTarget)
        Return
    EndIf
    RecordAnimation(akInitiator, "DrugFood", akTarget.GetDisplayName())
    RecordAnimation(akTarget,    "DrugFood", akInitiator.GetDisplayName())
    _CueOngoing("baka_forced", \
        akInitiator.GetDisplayName() + " offers " + akTarget.GetDisplayName() + " food secretly spiked with something.", \
        akInitiator, akTarget)

    ; _bQTEDefeated=True so _CleanupPair skips standing the victim up + re-evaluating their
    ; AI — without it the AI recovers and the bleedout never sticks (the reported bug).
    _bQTEDefeated = True
    PlayPairedSimpleAnim(akInitiator, akTarget, \
        0.0, 0.0, 0.0, \
        "Babo_DruggedFoodConsumptionM", "Babo_DruggedFoodConsumptionF", \
        fMolestLoopDuration)
    _bQTEDefeated = False

    ; Animation done — victim collapses unconscious. No QTE; the drug does the work.
    ; Set flag so _DefeatGroundWindow and _DoEscalation use unconscious-victim context.
    _Log("[SNBaka] DrugFood_Execute: animation complete — collapsing victim into ground window (drugged)")
    _bDruggedEscalation = True
    _UnlockAttackerOnly(akInitiator)
    _DefeatGroundWindow(akInitiator, akTarget)
EndFunction

; --- ShowingOffBody ---  [REV-84 UI label: "Ogle Body"; YAML name/id unchanged]
; OBSERVED BEHAVIOR (dogfood-verified REV-84): the INITIATOR ogles; the TARGET poses
; ostentatiously and the beat ends with a slap. Anim names are doubly role-inverted
; (Babo A1/A2 naming vs. who performs): the initiator (first arg) plays
; BaboShowingOffBodyA2 = the OGLER; the target (second arg) plays BaboShowingOffBodyA1
; = the POSER. Do not "fix" the pairing — it renders correctly as shipped.
; No body-sex gate — Baka uses role-based A1/A2 naming so any character can perform
; either side.
; (HasFemaleBody on the player is unreliable with RaceMenu presets — male base, female appearance.)
Function ShowingOffBody_Execute(Actor akInitiator, Actor akTarget)
    _ActionLaneFire(akInitiator, akTarget, "ShowingOffBody") ; [REV-174f Leg 4.2] neutral fanned lane (LLM/player-initiated; daemon fires suppressed)
    _Log("[SNBakaACT] ShowingOffBody ENTER")
    If !IsEligible(akInitiator, akTarget)
        Return
    EndIf
    If !LockBoth(akInitiator, akTarget)
        Return
    EndIf
    RecordAnimation(akInitiator, "ShowingOffBody", akTarget.GetDisplayName())
    RecordAnimation(akTarget,    "ShowingOffBody", akInitiator.GetDisplayName())
    _CueOngoing("baka_intimate", \
        akInitiator.GetDisplayName() + " ogles " + akTarget.GetDisplayName() + " while they pose ostentatiously.", \
        akInitiator, akTarget)

    _ClearTearsForAffection(akInitiator, akTarget)
    PlayPairedSimpleAnim(akInitiator, akTarget, \
        0.0, 0.0, 180.0, \
        "BaboShowingOffBodyA2", "BaboShowingOffBodyA1", \
        fMolestLoopDuration)

    _CueOutcome("baka_intimate", \
        akInitiator.GetDisplayName() + " ogled " + akTarget.GetDisplayName() + "'s ostentatious posing; it ended with a slap.", \
        akInitiator, akTarget)
    UnlockBoth(akInitiator, akTarget)
EndFunction

; --- FondlePussy --- [FEMALE TARGET REQUIRED]
; A1=BaboPlayingPussyA2, A2=BaboPlayingPussyA1 (inverted naming).
; Non-resistable variant — used for consensual or subdued contexts.
; Use PlayPrivates_Execute for the resistable version.
Function FondlePussy_Execute(Actor akInitiator, Actor akTarget)
    _ActionLaneFire(akInitiator, akTarget, "FondlePussy") ; [REV-174f Leg 4.2] neutral fanned lane (LLM/player-initiated; daemon fires suppressed)
    _Log("[SNBakaACT] FondlePussy ENTER")
    If !IsEligible(akInitiator, akTarget)
        Return
    EndIf
    If !HasFemaleBody(akTarget)
        Return
    EndIf
    If !LockBoth(akInitiator, akTarget)
        Return
    EndIf
    RecordAnimation(akInitiator, "FondlePussy", akTarget.GetDisplayName())
    RecordAnimation(akTarget,    "FondlePussy", akInitiator.GetDisplayName())
    ; REV-150 4.4: register entry 31 reworded line of record (user's 2026-10-24 pen)
    _CueOngoing("baka_forced", \
        akInitiator.GetDisplayName() + "'s hand reached between " + akTarget.GetDisplayName() + "'s legs, fondling their privates.", \
        akInitiator, akTarget)
    _StartTears(akTarget)

    ; Attacker directly behind the victim, in line (no lateral shift, same facing -> victim's
    ; back to the attacker). See POSITIONING TUNING block at top.
    Float yFondle = fFondleSep_NPC
    If akInitiator == PlayerRef || akTarget == PlayerRef
        yFondle = fFondleSep_PC
    EndIf
    PlayPairedSimpleAnim(akInitiator, akTarget, \
        0.0, 0.0, 180.0, \
        "BaboPlayingPussyA2", "BaboPlayingPussyA1", \
        fTouchLoopDuration)

    _CueOutcome("baka_forced", \
        akInitiator.GetDisplayName() + " fondled " + akTarget.GetDisplayName() + " between the legs.", \
        akInitiator, akTarget)
    UnlockBoth(akInitiator, akTarget)
EndFunction

; --- InterruptScene ---
; A guard, bystander, or player forces an ongoing Baka scene to stop.
; akTarget is any actor currently in an active animation (victim or initiator).
; If they are not in a scene, does nothing.
Function InterruptScene_Execute(Actor akIntervenor, Actor akTarget)
    _ActionLaneFire(akIntervenor, akTarget, "InterruptScene") ; [REV-174f Leg 4.2] neutral fanned lane (LLM/player-initiated; daemon fires suppressed)
    _Log("[SNBakaACT] InterruptScene ENTER")
    If !akIntervenor || !akTarget
        Return
    EndIf
    If !IsActorLocked(akTarget)
        Return
    EndIf
    RequestStop(akTarget)
    SkyrimNetApi.RegisterEvent("baka_intervention", \
        akIntervenor.GetDisplayName() + " forces the scene involving " + akTarget.GetDisplayName() + " to stop.", \
        akIntervenor, akTarget)
EndFunction

; --- CallOff ---
; The scene initiator voluntarily ends their own ongoing animation.
; akInitiator must currently be locked (in an active animation).
Function CallOff_Execute(Actor akInitiator, Actor akTarget)
    _ActionLaneFire(akInitiator, akTarget, "CallOff") ; [REV-174f Leg 4.2] neutral fanned lane (LLM/player-initiated; daemon fires suppressed)
    _Log("[SNBakaACT] CallOff ENTER")
    If !akInitiator
        Return
    EndIf
    If !IsActorLocked(akInitiator)
        Return
    EndIf
    RequestStop(akInitiator)
    SkyrimNetApi.RegisterEvent("baka_calloff", \
        akInitiator.GetDisplayName() + " calls off the interaction with " + akTarget.GetDisplayName() + ".", \
        akInitiator, akTarget)
EndFunction

; --- Interact ---
; Called by SNBaka_InteractPower when player casts on an NPC.
; Two-level native message box — four top-level categories, each with a submenu.
; All button indices follow CK Message record button order (0-based, Cancel is last).
;
;   InteractMenuMain         : 0=Affectionate  1=Aggressive  2=Sexual  3=Devious  4=Cancel
;   InteractMenuAffectionate : 0=Back Hug  1=Front Hug  2=Kiss  3=Flirt  4=Cancel
;   InteractMenuAggressive   : 0=Grab Hold  1=Struggle  2=Choke  3=Womb Hit  4=Cancel
;   InteractMenuAggPhysical  : [Sexual submenu]   0=Forced Kiss  1=Spank  2=Touch Breasts  3=Examine  4=Cancel
;   InteractMenuAggSexual    : [Devious submenu]  0=Ogle Body  1=Drunk Exploit  2=Drug Food  3=Fondle  4=Cancel
;
;   CK records to update (button text only — FormIDs unchanged):
;     SNBaka_InteractMenuMain:       was 3 buttons, now 5: Affectionate/Aggressive/Sexual/Devious/Cancel
;     SNBaka_InteractMenuAggressive: was Physical/Sexual/Cancel, now: Grab Hold/Struggle/Choke/Womb Hit/Cancel
;     SNBaka_InteractMenuAggPhysical: relabel to Sexual actions: Forced Kiss/Spank/Touch Breasts/Examine/Cancel
;     SNBaka_InteractMenuAggSexual:   relabel to Devious actions: Ogle Body/Drunk Exploit/Drug Food/Fondle/Cancel
;     SNBaka_InteractMenuAffectionate: NO CHANGE
; REV-147 Feature A: the no-target panel open. The interact power with nobody on
; the crosshair routes here (the REV-61 blocked sentinel becomes the panel-open
; path - user ruling). The bridge re-resolves the crosshair itself; when it also
; finds nobody it opens the panel with the "no target selected" overlay: all
; target-actions greyed, the two ambient-mode footer buttons live, their state
; pushed right after. Every target-action pick from a null-target session is
; refused with the reason-coded sentinel in _DispatchInteractAction.
Function Interact_NoTargetPanel(Actor akCaster)
    _Log("[SNBaka][PANEL] no-target panel open (REV-147)")
    SNBakaUI.ShowInteractMenu(akCaster, None)
    _PushModeStates()   ; REV-147 Feature B: initial button state at panel open
EndFunction

Function Interact_ShowMenu(Actor akTarget, Actor akCaster)
    If !akTarget || !akCaster
        _Log("[SNBaka] interact menu: blocked — null target/caster")
        Return
    EndIf

    ; REV-147 Feature A: the no-target panel open lives in Interact_NoTargetPanel
    ; (below) - the user ruling that a power press with nobody on the crosshair opens
    ; the panel instead of doing nothing. The REV-61 blocked sentinel path in
    ; SkyrimNet_BakaInteractEffect routes there. This function keeps its null guard:
    ; it requires a real target; the null-target session is the separate entry point.

    ; If the target is downed — either by US (SNBaka.OnGround, from a QTE defeat/drug), by an external
    ; mod/cause (any bleedout, e.g. Surrender), or held purely by Acheron (SNAcheron.Held) — open the
    ; downed-victim menu instead of the normal interact menu. This must come before the IsActorLocked
    ; guard below.
    ; Always attempt the real menu now, unconditionally — this used to gate on SNBakaUI.IsAvailable()
    ; here in Papyrus first, silently auto-escalating instead whenever that read false even briefly
    ; (e.g. right after a save load, before the view finished recreating). ShowDownedMenu already does
    ; its own IsAvailable()+CreateMenuView() recovery internally on the C++ side — that retry never got
    ; a chance to run when the Papyrus-side pre-check alone decided to skip straight to auto-escalate.
    ; PrismaUI is a hard requirement for this mod now, so there's no real vanilla-fallback case left to
    ; preserve here.
    If _IsDownedAny(akTarget)
        _Log("[SNBaka] interact menu: " + akTarget.GetDisplayName() + " is downed (_IsDownedAny) — routing to downed menu")
        _pendingCaster = akCaster
        _pendingTarget = akTarget
        SNBakaUI.ShowDownedMenu(akCaster, akTarget)
        _PushModeStates()   ; REV-147 Feature B: initial button state at panel open
        Return
    EndIf

    If IsActorLocked(akCaster) || IsActorLocked(akTarget)
        _Log("[SNBaka] interact blocked: already in an interaction.")
        Return
    EndIf
    If _bCooldownActive
        _Log("[SNBaka] interact blocked: still on cooldown.")
        Return
    EndIf

    ; Target is hostile and actively fighting the caster: open the small, curated in-combat "Grapple"
    ; menu instead of the normal one. Must come BEFORE the IsEligible check below -- IsEligible's own
    ; combat gate would otherwise silently reject a mid-fight target right here before this branch
    ; ever got a look. Creatures are explicitly excluded -- they keep their own separate
    ; CreatureEscalate pipeline, same creature-guard pattern IsEligible itself uses. No further
    ; eligibility pre-check here, matching the downed branch above: the real enforcement (distance,
    ; sex-scene, locks, cooldown) happens inside whichever *_Execute function the menu dispatches to,
    ; same as it always does.
    If akTarget.IsHostileToActor(akCaster) && akTarget.IsInCombat() \
            && !_IsCreatureActor(akTarget) && _CreatureAnimKey(akTarget) == ""
        _Log("[SNBaka] interact menu: " + akTarget.GetDisplayName() + " hostile+in-combat — routing to grapple menu")
        _pendingCaster = akCaster
        _pendingTarget = akTarget
        SNBakaUI.ShowMidCombatMenu(akCaster, akTarget)
        _PushModeStates()   ; REV-147 Feature B: initial button state at panel open
        Return
    EndIf

    If !IsEligible(akCaster, akTarget)
        _Log("[SNBaka] interact menu: blocked — IsEligible refused (gate logged above; target=" + akTarget.GetDisplayName() + ")")
        Return
    EndIf

    ; ── PrismaUI path (async) ────────────────────────────────────────────────
    If SNBakaUI.IsAvailable()
        _pendingTarget = akTarget
        _pendingCaster = akCaster
        ; Actors are passed into the DLL and handed straight back on dispatch,
        ; so _pending* is only a fallback — the menu being open (unpaused) can no
        ; longer leave us with the wrong actors.
        _Log("[SNBaka] interact menu: opening PrismaUI interact menu (" + akCaster.GetDisplayName() + " -> " + akTarget.GetDisplayName() + ")")
        SNBakaUI.ShowInteractMenu(akCaster, akTarget)
        _PushModeStates()   ; REV-147 Feature B: initial button state at panel open
        Return  ; result arrives via _DispatchInteractActionWithActors
    EndIf

    ; ── Vanilla fallback (synchronous) ───────────────────────────────────────
    _Log("[SNBaka] interact menu: PrismaUI unavailable — falling back to vanilla Message menus")
    ; Resolve menus fresh each call — VMAD properties may be zombie refs after ESL compaction.
    Message _mmMain    = Game.GetFormFromFile(0x00080A, "SkyrimNet_BakaIntegration.esp") as Message
    Message _mmAff     = Game.GetFormFromFile(0x00080B, "SkyrimNet_BakaIntegration.esp") as Message
    Message _mmAgg     = Game.GetFormFromFile(0x00080C, "SkyrimNet_BakaIntegration.esp") as Message
    Message _mmAggPhys = Game.GetFormFromFile(0x000803, "SkyrimNet_BakaIntegration.esp") as Message
    Message _mmAggSex  = Game.GetFormFromFile(0x000804, "SkyrimNet_BakaIntegration.esp") as Message
    If !_mmMain
        _Log("[SNBaka] ERROR: InteractMenuMain not found at 0x00080A - ESL FormID mismatch?")
        Return
    EndIf

    Int choice = _mmMain.Show()

    ; 0 = Affectionate
    If choice == 0 && _mmAff
        Int sub = _mmAff.Show()
        If sub == 0
            BackHug_Execute(akCaster, akTarget)
        ElseIf sub == 1
            FrontHug_Execute(akCaster, akTarget)
        ElseIf sub == 2
            KissLove_Execute(akCaster, akTarget)
        ElseIf sub == 3
            Flirt_Execute(akCaster, akTarget)
        EndIf

    ; 1 = Aggressive
    ElseIf choice == 1 && _mmAgg
        Int sub = _mmAgg.Show()
        If sub == 0
            BackHugMolest_Execute(akCaster, akTarget)
        ElseIf sub == 1
            Struggle_Execute(akCaster, akTarget)
        ElseIf sub == 2
            ChokeHug_Execute(akCaster, akTarget)
        ElseIf sub == 3
            WombHit_Execute(akCaster, akTarget)
        EndIf

    ; 2 = Sexual (uses InteractMenuAggPhysical record — relabelled in CK)
    ElseIf choice == 2 && _mmAggPhys
        Int sub = _mmAggPhys.Show()
        If sub == 0
            ForcedKiss_Execute(akCaster, akTarget)
        ElseIf sub == 1
            Spanking_Execute(akCaster, akTarget)
        ElseIf sub == 2
            TouchBreasts_Execute(akCaster, akTarget)
        ElseIf sub == 3
            ExaminePrivates_Execute(akCaster, akTarget)
        EndIf

    ; 3 = Devious (uses InteractMenuAggSexual record — relabelled in CK)
    ElseIf choice == 3 && _mmAggSex
        Int sub = _mmAggSex.Show()
        If sub == 0
            ShowingOffBody_Execute(akCaster, akTarget)
        ElseIf sub == 1
            DrunkExploit_Execute(akCaster, akTarget)
        ElseIf sub == 2
            DrugFood_Execute(akCaster, akTarget)
        ElseIf sub == 3
            FondlePussy_Execute(akCaster, akTarget)
        EndIf
    EndIf
EndFunction


; ── PrismaUI async dispatch ──────────────────────────────────────────────────

Event OnSNBakaMenuChoice(String eventName, String strArg, Float numArg, Form sender)
    Int choice = numArg as Int
    If strArg == "execconfirm"
        ; REV-92 Task 2.3: Execute-gate popup answer (DLL ExecuteConfirm mode -> normal-path
        ; SendEvent). 0 = accept, -1 = decline/timeout/moot close.
        _ExecuteGateAnswer(choice == 0, "popup")
    ElseIf strArg == "sexspank"
        _DispatchSexSpankAction(choice)
    ElseIf strArg == "mephalatoggle"
        ; REV-145 3.6: the SNBaka_Menu footer mode button (GS footer-button
        ; pattern -> SNBaka.* keys; Papyrus arbitrates).
        _MephalaToggle()
    ElseIf strArg == "molagbaltoggle"
        _MolagBalToggle()
    Else
        _DispatchInteractAction(choice)
    EndIf
EndEvent

; Called by SkyrimNet_BakaIntegration.dll with the actors captured when the menu opened.
; Sets _pending* and runs the normal dispatch synchronously — no open-menu gap
; for the values to be clobbered in.
Function _DispatchInteractActionWithActors(Int choice, Actor cst, Actor tgt)
    _pendingCaster = cst
    _pendingTarget = tgt
    _DispatchInteractAction(choice)
EndFunction

Function _DispatchInteractAction(Int choice)
    Actor tgt = _pendingTarget
    Actor cst = _pendingCaster
    _pendingTarget = None
    _pendingCaster = None
    ; REV-147 2.3: the reserved mode ids route FIRST, unconditionally - a no-target
    ; panel session keeps the footer mode buttons live, so 900/901 must not fall
    ; through the null-target refusal below. (The live path is the DLL's own
    ; keep-open _MenuModeButton dispatch; this ordering is the defense-in-depth
    ; leg, unchanged for the MCM routing precedent.)
    If choice == 900
        _MephalaToggle()
        Return
    ElseIf choice == 901
        _MolagBalToggle()
        Return
    EndIf
    If choice < 0
        Return
    EndIf
    ; REV-147 2.3: every target-action choice from a null-target session refuses
    ; with a reason-coded sentinel (the user ruling: such a panel is ambient-only -
    ; the JS grey-out makes this unreachable by pointer events, so reaching here
    ; means a keyboard/bypass path; the refusal is explicit and logged).
    If !tgt
        _Log("[SNBaka][PANEL] REFUSED - no target selected (choice=" + choice + ") - REV-147 no-target session")
        Return
    EndIf
    If !cst
        _Log("[SNBaka][PANEL] REFUSED - no caster (choice=" + choice + ")")
        Return
    EndIf
    If choice == 0
        BackHug_Execute(cst, tgt)
    ElseIf choice == 1
        FrontHug_Execute(cst, tgt)
    ElseIf choice == 2
        KissLove_Execute(cst, tgt)
    ElseIf choice == 3
        Flirt_Execute(cst, tgt)
    ElseIf choice == 4
        BackHugMolest_Execute(cst, tgt)
    ElseIf choice == 5
        Struggle_Execute(cst, tgt)
    ElseIf choice == 6
        ChokeHug_Execute(cst, tgt)
    ElseIf choice == 7
        WombHit_Execute(cst, tgt)
    ElseIf choice == 8
        ForcedKiss_Execute(cst, tgt)
    ElseIf choice == 9
        Spanking_Execute(cst, tgt)
    ElseIf choice == 10
        TouchBreasts_Execute(cst, tgt)
    ElseIf choice == 11
        ExaminePrivates_Execute(cst, tgt)
    ElseIf choice == 12
        ShowingOffBody_Execute(cst, tgt)
    ElseIf choice == 13
        DrunkExploit_Execute(cst, tgt)
    ElseIf choice == 14
        DrugFood_Execute(cst, tgt)
    ElseIf choice == 15
        FondlePussy_Execute(cst, tgt)
    ; --- new player-accessible NPC actions (no QTE) ---
    ElseIf choice == 16
        FlirtFace_Execute(cst, tgt)        ; Caress Face
    ElseIf choice == 17
        FlirtBreast_Execute(cst, tgt)      ; Tease Breasts
    ElseIf choice == 18
        FlirtPussy_Execute(cst, tgt)       ; Tease Below
    ElseIf choice == 19
        SuckBreasts_Execute(cst, tgt)      ; Suck Breasts
    ElseIf choice == 20
        OralOnTarget_Execute(cst, tgt)     ; Suck Privates
    ElseIf choice == 21
        PlayPrivates_Execute(cst, tgt)     ; Play Privates
    ElseIf choice == 22
        Investigate_Execute(cst, tgt)      ; Investigate
    ElseIf choice == 23
        CapturedInspect_Execute(cst, tgt)  ; Inspect (captured)
    ElseIf choice == 24
        ArmHold_Execute(cst, tgt)          ; Arm Hold (affectionate)
    ElseIf choice == 25
        LapSitPlayer_Execute(cst, tgt)     ; Sit on Lap (plugin: Immersive Lap Sitting; validates + notifies)
    EndIf
EndFunction

Function _DispatchSexSpankAction(Int choice)
    Actor caster = _pendingSexCaster
    Actor npc0   = _pendingSexNPC0
    Actor npc1   = _pendingSexNPC1
    Actor npc2   = _pendingSexNPC2
    _pendingSexCaster = None
    _pendingSexNPC0 = None
    _pendingSexNPC1 = None
    _pendingSexNPC2 = None
    If choice < 0 || !caster
        Return
    EndIf
    ; REV-146a 4.2: Prisma mode buttons (900/901) also arrive here when the
    ; sex-spank panel is open -- same routing as the interact dispatcher.
    If choice == 900
        _MephalaToggle()
        Return
    ElseIf choice == 901
        _MolagBalToggle()
        Return
    EndIf
    If choice == 0 && npc0
        _SexSpank_Execute(caster, npc0)
    ElseIf choice == 1 && npc1
        _SexSpank_Execute(caster, npc1)
    ElseIf choice == 2 && npc2
        _SexSpank_Execute(caster, npc2)
    ElseIf choice == 10 && npc0
        _SexSpank_Execute(npc0, PlayerRef)
    ElseIf choice == 11 && npc1
        _SexSpank_Execute(npc1, PlayerRef)
    ElseIf choice == 12 && npc2
        _SexSpank_Execute(npc2, PlayerRef)
    ElseIf choice == 13
        _SexSpank_Execute(PlayerRef, PlayerRef)
    EndIf
EndFunction

; [REV-177b item 7 / R-177b — Oldcustard shape (issue #2 item 7, credit
; Oldcustard)]: spared enemies used to re-engage the instant recovery stood them
; up. DECIDE the spare BEFORE recovery (was the victim an enemy of the initiator
; or the player?), then immediately AFTER recovery force them to stand down:
; Aggression 0 + Confidence 0 + StopCombatAlarm + StopCombat +
; _ClearStaleCombatLocks. User framing of record: too injured to flee, forced to
; face you — stays present as scene material. NO wait-for-standup anywhere on
; these synchronous paths (the victims are already recovered when these run).
; FUTURE ITEM, deliberately NOT built here: wary-enemy ~10-min optional hostility
; restore (original Aggression/Confidence on a timestamp, narrated as strength
; returning) — revisit after this easy fix lands.
Bool Function _SpareEnemyDecided(Actor akInitiator, Actor akVictim)
    If !akVictim
        Return False
    EndIf
    Bool enemy = False
    If akInitiator && akInitiator != akVictim
        enemy = akVictim.IsHostileToActor(akInitiator)
    EndIf
    If !enemy && PlayerRef
        enemy = akVictim.IsHostileToActor(PlayerRef)
    EndIf
    _Log("[SNBaka] spare-enemy decision (R-177b): " + akVictim.GetDisplayName() + " hostile=" + enemy)
    Return enemy
EndFunction

Function _SparePacifyEnemy(Actor akVictim)
    If !akVictim || akVictim == PlayerRef
        Return
    EndIf
    akVictim.SetActorValue("Aggression", 0.0)
    akVictim.SetActorValue("Confidence", 0.0)
    akVictim.StopCombatAlarm()
    akVictim.StopCombat()
    _ClearStaleCombatLocks(akVictim)
    _Log("[SNBaka] spare-enemy pacify applied (R-177b): " + akVictim.GetDisplayName() + " Aggression/Confidence 0, combat stopped, stale locks cleared")
EndFunction

; --- Release ---
; Called during the ground window to free the downed victim immediately without escalating.
; The attacker steps back — the moment passes. Works for both NPC and player initiators.
Function Release_Execute(Actor akInitiator, Actor akTarget)
    _ActionLaneFire(akInitiator, akTarget, "Release") ; [REV-174f Leg 4.2] neutral fanned lane (LLM/player-initiated; daemon fires suppressed)
    _Log("[SNBakaACT] Release ENTER")
    If !akTarget || !akInitiator
        Return
    EndIf
    If _IsCreatureActor(akInitiator) || _IsCreatureActor(akTarget)
        _Log("[SNBaka] Release_Execute: blocked — creature actor (use CreatureEscalate)")
        Return
    EndIf
    If _IsDownedAny(akInitiator)
        _Log("[SNBaka] Release_Execute: blocked — initiator is downed")
        Return
    EndIf
    Bool ours = StorageUtil.GetIntValue(akTarget, "SNBaka.OnGround", 0) == 1
    Bool external = !ours && _IsDownedAny(akTarget)
    If !ours && !external
        Return
    EndIf
    _bReleaseRequested = True
    _Log("[SNBaka] Release_Execute: " + akInitiator.GetDisplayName() + " releases " + akTarget.GetDisplayName())
    ; REV-74 Task 4 — removal-on-release (MCM "Remove Marks On Release", default ON): strip the
    ; module's degradation marks when a captive is genuinely freed. Service-delegated, one line,
    ; absence-safe (module no-ops without SlaveTats / without marks applied).
    If StorageUtil.GetIntValue(Game.GetPlayer(), "SNBaka.ST.RemoveOnRelease", 1) == 1
        SNBaka_SlaveTatsModule.RemoveAllFromActor(akTarget, "release")
    EndIf
    ; If they were defeated by something other than our ground window (Acheron combat bleedout), free
    ; them directly — the ground-window flag alone won't be read by anyone.
    ; [REV-177b item 7 / R-177b] spare decision BEFORE recovery; enemy victims are
    ; stood down immediately after (Oldcustard shape) — no wait-for-standup.
    Bool spareEnemy = _SpareEnemyDecided(akInitiator, akTarget)
    If external
        _ForceRecover(akTarget)
        If spareEnemy
            _SparePacifyEnemy(akTarget)
        EndIf
    EndIf
    SkyrimNetApi.RegisterEvent("baka_release", \
        akInitiator.GetDisplayName() + " steps back, letting " + akTarget.GetDisplayName() + " go free.", \
        akInitiator, akTarget)
EndFunction

; Idempotent "get this actor off the ground NOW", callable from ANY state — our ground window, an
; external Acheron/other bleedout, or a stuck leftover after a scene. Safe to call repeatedly. This
; is the single reliable recovery path; everything that frees a downed actor should funnel here.
; abFullRescue=False (Stand Back only) skips Acheron's own dramatic RescueActor call -- see
; _ClearAcheronHold. Every other caller keeps the default (True), unchanged.
Function _ForceRecover(Actor akActor, Bool abFullRescue = True)
    If !akActor
        Return
    EndIf
    Bool isPlayer = (akActor == PlayerRef)
    _Log("[SNBaka] _ForceRecover ENTER: " + akActor.GetDisplayName() + " isPlayer=" + isPlayer + " abFullRescue=" + abFullRescue)
    ; If our ground window is currently running, make it exit cleanly instead of fighting us.
    _bReleaseRequested = True
    _bStandBack        = False
    StorageUtil.SetIntValue(akActor,    "SNBaka.OnGround",      0)
    StorageUtil.SetStringValue(akActor, "SNBaka.DownPose",      "")
    StorageUtil.SetIntValue(akActor,    "SNBaka.Locked",        0)
    StorageUtil.SetIntValue(akActor,    "SNBaka.StopRequested", 0)
    ; Being helped up IS the untie — a tied prisoner's one recovery path besides the tie lapsing.
    StorageUtil.SetIntValue(akActor,    "SNBaka.Tied",          0)
    StorageUtil.SetFloatValue(akActor,  "SNBaka.TiedUntilGT",   0.0)
    ; This used to be left set — only _OnVictimWon (a genuine struggle-escape) ever cleared it, so
    ; Release/HelpUp/Stand Back (everything routing through here) never actually ended the "captive"
    ; relationship this flag represents. Harmless on its own, but it's about to become load-bearing:
    ; Acheron's OnActorRescued checks this exact flag to tell "we legitimately freed them" apart from
    ; "AcheronNG's own defeat-duration timer rescued them out from under an intended captivity" — if
    ; this stayed 1 through a real release, that check couldn't tell the two apart.
    StorageUtil.SetIntValue(akActor,    "SNBaka.Captive",       0)
    ; The victim is actually being freed now — this is where the tracked aggressor (held pacified since
    ; _EscalationCleanup, if a scene happened) finally gets its aggression back, not immediately after
    ; the scene ends. Read it before clearing the reference.
    Actor trackedThreat = StorageUtil.GetFormValue(akActor, "SNBaka.GroundWindowAggressor") as Actor
    If trackedThreat
        _PacifyActor(trackedThreat, False)
        ; End the "lover"-rank anti-re-aggro link from the escalation that downed them (humanoid
        ; aggressors too — the creature-wide sweep below only covers supported creatures).
        trackedThreat.SetRelationshipRank(akActor, 0)
        If akActor != PlayerRef
            akActor.SetRelationshipRank(trackedThreat, 0)
        EndIf
    EndIf
    ; Also sweep stale creature links from past cycles (never reverted by older builds — confirmed:
    ; a giant that had previously beaten this victim would never attack them again).
    _ClearAggressorBonds(akActor)
    StorageUtil.SetFormValue(akActor,   "SNBaka.GroundWindowAggressor", None)
    akActor.SetRestrained(False)
    akActor.SetDontMove(False)
    If !isPlayer
        _PacifyActor(akActor, False)
        _HoldActorAI(akActor, False)
    EndIf
    ; Acheron's own RescueActor (inside _ClearAcheronHold) pops a bled-out actor upright natively,
    ; the instant it's called -- no animation, just "up". Calling it HERE, before _Recover gets a
    ; chance to play its own get-up transition, left nothing down to visibly transition out of: the
    ; actor was already standing by the time our SendAnimationEvent fired. Confirmed real bug from
    ; testing: HelpUp on the player looked like they "just became up" with no stand-up animation at
    ; all. _Recover already clears the Acheron hold itself, in the right order (animate first, then
    ; clear) -- let it do that instead of racing it here. Only the abFullRescue flag needs threading
    ; through so Stand Back's "skip the dramatic rescue" intent still reaches it.
    If _IsDownedAny(akActor)
        _Recover(akActor, abFullRescue)   ; get-up transition first, THEN Acheron hold clear + essential-HP guard
    Else
        ; Already standing — e.g. the bridge's cross-script control-restore handoff fires this AFTER
        ; its own recovery ritual finished. Re-running the get-up staggered the player repeatedly and
        ; raced a second queued RescueActor (confirmed report: "after using the KEY to stand, I
        ; staggered several times and cannot attack"). Skip the ritual; everything below is the
        ; idempotent sanitize half, which is the only part the handoff needs.
        _Log("[SNBaka] _ForceRecover: " + akActor.GetDisplayName() + " is already up — sanitize only, skipping the get-up ritual")
    EndIf
    ; See _RestoreHostility's own comment: restoring aggression alone doesn't reliably make a
    ; genuinely hostile pair resume fighting once they're both back up. trackedThreat is the one
    ; actor we actually know was adversarial here (whoever downed akActor in the first place).
    _RestoreHostility(trackedThreat, akActor)
    ; Stale Acheron pacify release for NPCs too -- this existed only for the player below, so an NPC
    ; who "got up" through here could keep the native keyword-backed "ignoring & ignored by combat"
    ; state forever (confirmed live report: stuck non-aggressive AND untargetable, with nothing in
    ; Papyrus able to remove the keyword). _ReleaseAcheronPacify already refuses to touch an actor
    ; Acheron currently holds genuinely DEFEATED, so a legit down state is never stripped here.
    If !isPlayer
        _ReleaseAcheronPacify(akActor)
    EndIf
    If isPlayer
        Game.EnablePlayerControls()
        ; OStim sets this for player scenes and a force-stopped/refused scene can strand it — nothing
        ; else in either mod ever cleared it. Confirmed symptom pair: can't attack + sluggish camera
        ; after recovery. Idempotent when already clean.
        Game.SetPlayerAIDriven(False)
        ; Lingering Acheron PACIFY on the player (applied by earlier builds, save-persistent, native
        ; handling blocks attack/sprint) — strip it at every recovery. No-op on a clean player; the
        ; !IsDefeated guard keeps an active defeat's own pacify untouched.
        If StorageUtil.GetIntValue(PlayerRef, "SNAcheron.Present", 0) == 1 && !Acheron.IsDefeated(PlayerRef)
            Acheron.ReleaseActor(PlayerRef)
        EndIf
    EndIf
    akActor.EvaluatePackage()
    _Log("[SNBaka] _ForceRecover: stood up " + akActor.GetDisplayName() + " (player=" + isPlayer + ")")
EndFunction

; EMERGENCY panic button (MCM > General > Maintenance), for when a liberation path went wrong and
; left an actor stuck -- non-aggressive, untargetable, frozen, ghosted, whatever. Sweeps every
; loaded actor and force-clears every hold Baka could have left: pacify/aggression, our Calm spell,
; the DoNothing AI override, restrain/DontMove/ghost/vehicle-pin/collision, lock flags, and any
; stale Acheron native pacify (the keyword-backed "ignoring & ignored by combat" state ONLY
; Acheron's own ReleaseActor can remove -- no Papyrus keyword-stripping exists, which is why stuck
; actors looked irreversible from the console). Deliberately does NOT touch an actor Acheron
; currently holds DEFEATED: that state is legitimate and owned by the down pipeline -- HelpUp or
; the get-up key is the correct way out of it, not this. Returns how many actors had a stuck state.
Int Function PanicReset()
    _Log("[SNBaka] PanicReset: EMERGENCY sweep requested from MCM")
    ; Pop any stuck ground-window loop on its next tick, and drop any half-open transient mode.
    _bReleaseRequested       = True
    _bMidCombatGrappleActive = False
    ; Immersive Lap Sitting plugin: SitOnLap's own function can die mid-flight (confirmed live --
    ; the Papyrus stack for the whole attempt went silent right after the forced chair Activate, no
    ; error, no verdict logged, while the rest of the game kept running normally) before it ever
    ; reaches its own alias-clearing rollback. Since "one lap-sit at a time" is enforced purely by
    ; checking whether these three aliases are still filled, a death like that leaves every future
    ; attempt silently refused as "already in progress" forever. Clear them here unconditionally --
    ; harmless no-op if nothing was stuck, since ForceRefTo'ing None-filled aliases is a no-op too.
    If IsLapSitInstalled()
        Quest lapQuestReset = Game.GetFormFromFile(0x00080A, "Lap Sitting.esp") as Quest
        If lapQuestReset
            ReferenceAlias lapA0 = lapQuestReset.GetAlias(0) as ReferenceAlias
            ReferenceAlias lapA1 = lapQuestReset.GetAlias(1) as ReferenceAlias
            ReferenceAlias lapA2 = lapQuestReset.GetAlias(2) as ReferenceAlias
            ObjectReference staleChair = lapA2.GetReference()
            If lapA0
                lapA0.Clear()
            EndIf
            If lapA1
                lapA1.Clear()
            EndIf
            If lapA2
                lapA2.Clear()
            EndIf
            If staleChair
                staleChair.Disable()
                staleChair.Delete()
                _Log("[SNBaka] PanicReset: cleared a stale Lap Sitting chair/aliases")
            EndIf
        EndIf
    EndIf
    Bool acheronPresent = StorageUtil.GetIntValue(PlayerRef, "SNAcheron.Present", 0) == 1
    Actor[] loaded = PO3_SKSEFunctions.GetActorsByProcessingLevel(0)
    Int cleaned = 0
    Int i = 0
    While i < loaded.Length
        Actor a = loaded[i]
        If a && a != PlayerRef && !a.IsDead()
            Bool stalePacify = acheronPresent && !Acheron.IsDefeated(a) && Acheron.IsPacified(a)
            Bool wasStuck = stalePacify \
                || StorageUtil.GetIntValue(a, "SNBaka.Locked",   0) == 1 \
                || StorageUtil.GetIntValue(a, "SNBaka.Pacified", 0) == 1
            _PacifyActor(a, False)             ; restores original aggression (no-op if never pacified)
            If SNBakaCalm
                a.DispelSpell(SNBakaCalm)
            EndIf
            _HoldActorAI(a, False)
            SNBakaUI.SetNoCollision(a, False)
            _RestoreActorScale(a)
            a.SetGhost(False)
            a.SetRestrained(False)
            a.SetDontMove(False)
            a.SetVehicle(None)
            StorageUtil.SetIntValue(a, "SNBaka.Locked",        0)
            StorageUtil.SetIntValue(a, "SNBaka.StopRequested", 0)
            ; (SNBaka.OnGround/DownPose/Tied are deliberately left alone -- a genuinely downed actor
            ; is recovered by the released ground window / HelpUp, not blind-flag-wiped from here.)
            If stalePacify
                Acheron.ReleaseActor(a)        ; strips the native pacify AND its keyword
                _Log("[SNBaka] PanicReset: released stale Acheron pacify on " + a.GetDisplayName())
            EndIf
            ; Pose rescue: an actor can be stuck in the defeat/bleedout ANIMATION with every flag
            ; already clean (the redown-vs-queued-rescue race, see _ClearAcheronHold) -- flag sweeps
            ; alone can't see or fix that, and HelpUp refuses ("target not downed"). Force the graph
            ; back to default for anyone NOT genuinely downed; no-op on actors standing normally.
            If !_IsDownedAny(a) && !(acheronPresent && Acheron.IsDefeated(a))
                Debug.SendAnimationEvent(a, "BleedoutStop")
                Debug.SendAnimationEvent(a, "IdleForceDefaultState")
            EndIf
            a.EvaluatePackage()
            If wasStuck
                cleaned += 1
            EndIf
        EndIf
        i += 1
    EndWhile
    ; The player, explicitly (same treatment, plus controls/camera).
    If SNBakaCalm
        PlayerRef.DispelSpell(SNBakaCalm)
    EndIf
    SNBakaUI.SetNoCollision(PlayerRef, False)
    PlayerRef.SetGhost(False)
    PlayerRef.SetRestrained(False)
    PlayerRef.SetDontMove(False)
    PlayerRef.SetVehicle(None)
    StorageUtil.SetIntValue(PlayerRef, "SNBaka.Locked",        0)
    StorageUtil.SetIntValue(PlayerRef, "SNBaka.StopRequested", 0)
    Game.EnablePlayerControls()
    Game.SetPlayerAIDriven(False)
    If acheronPresent && !Acheron.IsDefeated(PlayerRef) && Acheron.IsPacified(PlayerRef)
        Acheron.ReleaseActor(PlayerRef)
    EndIf
    ; Same pose rescue the NPC sweep gets -- the redown-vs-rescue race can leave the PLAYER visually
    ; collapsed with clean flags too. No-op when standing normally.
    If !_IsDownedAny(PlayerRef) && !(acheronPresent && Acheron.IsDefeated(PlayerRef))
        Debug.SendAnimationEvent(PlayerRef, "BleedoutStop")
        Debug.SendAnimationEvent(PlayerRef, "IdleForceDefaultState")
    EndIf
    _Log("[SNBaka] PanicReset: done -- " + cleaned + " actor(s) had a stuck state")
    Return cleaned
EndFunction

; --- Help Up ---
; An NPC (or the player) helps a downed actor back to their feet. Unlike Release (which only works
; inside our brief ground window), this works whenever the target reads as downed — our OnGround
; OR an external Acheron bleedout — so it ALSO rescues a player who got stuck on the ground after a
; scene. The helper briefly crouches over the victim ("check downed") before lifting them.
Function HelpUp_Execute(Actor akInitiator, Actor akTarget)
    _ActionLaneFire(akInitiator, akTarget, "HelpUp") ; [REV-174f Leg 4.2] neutral fanned lane (LLM/player-initiated; daemon fires suppressed)
    _Log("[SNBakaACT] HelpUp ENTER")
    If !akInitiator || !akTarget
        Return
    EndIf
    If _IsCreatureActor(akInitiator) || _IsCreatureActor(akTarget)
        _Log("[SNBaka] HelpUp_Execute: blocked — creature actor (use CreatureEscalate)")
        Return
    EndIf
    If _IsDownedAny(akInitiator)
        _Log("[SNBaka] HelpUp_Execute: blocked — initiator is downed")
        Return
    EndIf
    Bool helpUpPierce = False   ; [REV-181 fix 1] gate-pierce receipt flag (function-level: Papyrus block scoping)
    If !_IsDownedAny(akTarget)
        ; Two confirmed races land a HelpUp on a victim who is "down" to the eye but not to _IsDownedAny:
        ; (a) native bleedout whose Acheron defeat/adoption hasn't finished landing yet, and (b) a
        ; creature pin in progress — the grab temporarily rescues the victim out of Acheron to animate,
        ; so mid-pin she reads as recovered (10:52:50 log: LLM HelpUp during Joylie's falmer pin no-oped).
        ; The helper's intent is unambiguous, so wait out the transition and help once she's back down.
        Float settle = 0.0
        While settle < 15.0 && !_IsDownedAny(akTarget) && (IsActorLocked(akTarget) || akTarget.IsBleedingOut()) && !akTarget.IsDead()
            Utility.Wait(0.5)
            settle += 0.5
        EndWhile
        If !_IsDownedAny(akTarget)
            ; [REV-181 Leg 2 — FIX 1, HELUP FULL CIRCUMVENTION] The always-available release
            ; valve (user ruling of record, S255): if Acheron still tracks the target as
            ; DEFEATED, the helper's intent pierces the downed gate regardless of whether our
            ; local flags agree — the orphan-defeat class (Acheron defeated, but Held/adoption
            ; never landed on our side) used to no-op here, leaving an actor no local recovery
            ; path could unlock. The initiator requirement above is unchanged (a standing NPC
            ; or the player — the designed lanes), and this circumvention is HELUP ONLY: every
            ; other action's gates stand exactly as they were.
            If StorageUtil.GetIntValue(PlayerRef, "SNAcheron.Present", 0) == 1 && Acheron.IsDefeated(akTarget)
                helpUpPierce = True
                _Log("[SNBaka] HelpUp_Execute: target not downed locally but Acheron-defeated — piercing the downed gate (fix 1 circumvention)")
            Else
                _Log("[SNBaka] HelpUp_Execute: target not downed (waited " + settle + "s) — nothing to do")
                Return
            EndIf
        Else
            _Log("[SNBaka] HelpUp_Execute: down state landed after " + settle + "s — proceeding")
        EndIf
    EndIf
    _Log("[SNBaka] HelpUp_Execute: " + akInitiator.GetDisplayName() + " helps up " + akTarget.GetDisplayName())
    SkyrimNetApi.RegisterEvent("baka_release", \
        akInitiator.GetDisplayName() + " crouches beside " + akTarget.GetDisplayName() + " and pulls them back to their feet. " + \
        akTarget.GetDisplayName() + " is up again now — shaken and worse for wear, but no longer down.", \
        akInitiator, akTarget)
    _ClearActorTears(akTarget)
    ; Brief "check downed" before lifting. NPCs get Babo_Kneel (the same pose PoseKneel uses) — it's a
    ; custom third-person-only pose, so never sent to the player. The player instead gets the vanilla
    ; IdleTake (pick-up-object idle, has proper first-person data, already used elsewhere on the player
    ; for the same "reach down" beat) — no explicit reset after, it's a self-resetting vanilla idle.
    If akInitiator == PlayerRef
        ; No combat gate for the player: helping someone up mid-fight is a deliberate button press,
        ; and skipping the beat here is exactly what read as "I did no action" in testing. Sheathe
        ; first — the graph rejects idle events while a weapon is drawn (same fix as Tie/Untie).
        akInitiator.SheatheWeapon()
        Utility.Wait(0.8)
        Game.ForceThirdPerson()   ; idles are invisible in first person
        Debug.SendAnimationEvent(akInitiator, "IdleTake")
        Utility.Wait(2.0)
        ; NOT self-resetting after all -- confirmed live: the player's upper body stayed stuck in the
        ; take pose afterward. Same explicit reset the NPC branch always had.
        Debug.SendAnimationEvent(akInitiator, "IdleForceDefaultState")
    ElseIf !akInitiator.IsInCombat()
        Debug.SendAnimationEvent(akInitiator, "Babo_Kneel")
        Utility.Wait(2.0)
        Debug.SendAnimationEvent(akInitiator, "IdleForceDefaultState")
    EndIf
    ; [REV-177b item 7 / R-177b] spare decision BEFORE recovery; enemy victims are
    ; stood down immediately after (Oldcustard shape) — no wait-for-standup.
    Bool spareEnemy = _SpareEnemyDecided(akInitiator, akTarget)
    _ForceRecover(akTarget)
    ; [REV-181 Leg 2 item 2 — FIX 1] THE FULL FUNERAL, the SAME shared helper every bridge-side
    ; recovery path runs (one helper, both paths — the bridge global _AcheronHoldFuneral).
    ; Clearing the complete hold-state table (deadline, re-down arm, cue clocks, soft keys)
    ; means nothing on the Acheron-bridge side can re-hold or re-down this actor after a
    ; deliberate HelpUp. First deliberate Baka->bridge global call: both scripts ship in the
    ; same package, the function is Global + StorageUtil-only (no quest-instance dependency),
    ; and the presence gate keeps it a no-op when the Acheron integration is absent.
    If StorageUtil.GetIntValue(PlayerRef, "SNAcheron.Present", 0) == 1
        SkyrimNet_AcheronIntegration._AcheronHoldFuneral(akTarget)
        _Log("[SNBaka] HelpUp_Execute: hold funeral complete — gate pierced (helpUpPierce=" + helpUpPierce + "), hold fully cleared (fix 1)")
    EndIf
    If spareEnemy
        _SparePacifyEnemy(akTarget)
    EndIf
    ; Help Up is a deliberate caring act — Calm the target so they don't immediately re-enter combat
    ; the moment they're back on their feet (same Calm-archetype pattern used elsewhere in this file,
    ; e.g. _CalmForAnim/_PacifyActor). No-op if SNBakaCalm was never assigned, or target isn't fighting.
    If SNBakaCalm && akTarget.IsInCombat()
        akTarget.StopCombat()
        SNBakaCalm.Cast(akTarget, akTarget)
        _Log("[SNBaka] HelpUp_Execute: cast SNBakaCalm on " + akTarget.GetDisplayName())
    EndIf
EndFunction

; REV-90 (roadmap item 3 / INDEX row 14): EXECUTE — the LLM-facing killing blow on a downed
; victim. A pure delegation to _DispatchDownedAction's choice-5 leg (the same guaranteed-
; alternative execute the interact menu offers): no gate-stack rewrite, the dispatch's own
; ours/external bookkeeping + release-then-Kill sequence runs unmodified. The downed recheck
; lives HERE (LLM decisions are a snapshot; the state can change before this runs) — same
; settle-wait pattern as HelpUp_Execute for the two late-landing races. Target-down is
; deliberately NOT an eligibilityRules decorator — same ruling as HelpUp (helpup.yaml): the
; executor is the enforcement point. §5 sentinels: the _Log lines below fire unconditionally.
Function Execute_Execute(Actor akInitiator, Actor akTarget)
    _ActionLaneFire(akInitiator, akTarget, "Execute") ; [REV-174f Leg 4.2] neutral fanned lane (LLM/player-initiated; daemon fires suppressed)
    _Log("[SNBakaACT] Execute ENTER")
    If !akInitiator || !akTarget
        Return
    EndIf
    If _IsCreatureActor(akInitiator) || _IsCreatureActor(akTarget)
        _Log("[SNBaka] Execute_Execute: blocked — creature actor (use CreatureEscalate)")
        Return
    EndIf
    ; [REV-177b item 8 / R-177c — Oldcustard issue #2 item 8] TIED self-execution
    ; guard: self-execution is otherwise a deliberate, legal, rare choice (defeat
    ; over capture — "takes their own life rather than be taken"), but a TIED
    ; actor physically cannot (bound hands don't swing the blade). Allowed except
    ; when tied. (akInitiator == akTarget is the self-variant; other-execute by a
    ; tied prisoner stays blocked by the downed checks below as before.)
    If akInitiator == akTarget && StorageUtil.GetIntValue(akInitiator, "SNBaka.Tied", 0) == 1
        _Log("[SNBakaEXEC] Execute refused: self-execution while TIED — bound prisoners cannot take their own life (R-177c)")
        Return
    EndIf
    If _IsDownedAny(akInitiator)
        ; REV-94 Task 1.1 (user-approved 2026-10-11; scoping of record: LENIENT
        ; initiator, STRICT target): an Acheron-DEFEATED initiator is pacified,
        ; not helpless - when the ONLY "downed" signal is the Acheron hold (no
        ; local SNBaka.OnGround window, no vanilla bleedout), the initiator may
        ; execute (the REV-93 J'zargo dogfood block, class (ii)). A genuinely
        ; locally-downed initiator (OnGround/bleedout) stays blocked. Presence-
        ; gated like _DelegateDownToAcheron (bridge quest 0x800 probe): inert
        ; without Acheron, per the planner's without-Acheron requirement.
        ; _IsDownedAny itself is UNTOUCHED - this is a widening, not a removal.
        If IsAcheronBridgeInstalled() \
            && Acheron.IsDefeated(akInitiator) \
            && StorageUtil.GetIntValue(akInitiator, "SNBaka.OnGround", 0) != 1 \
            && !akInitiator.IsBleedingOut()
            _Log("[SNBakaEXEC] Execute_Execute: initiator Acheron-defeated but standing/pacified - ACCEPTED (REV-94 lenient-initiator widening)")
        Else
            _Log("[SNBaka] Execute_Execute: blocked — initiator is downed")
            Return
        EndIf
    EndIf
    If akTarget == PlayerRef
        ; Never the player — the player's defeat IS the death alternative (choice-5 rule).
        _Log("[SNBaka] Execute_Execute: blocked — the player is never the execute target")
        Return
    EndIf
    ; REV-100 fix (a): SCENE-ACTIVE GUARD — the REV-99 incident (2026-10-09 19:36:58,
    ; PROJECT_STATE §105) proved this lane inherited NONE of IsEligible's IsInSexAnimation
    ; class (psc L628/L694; ~20 other lanes carry it). BOTH frameworks, ONE refusal
    ; semantics: IsInSexAnimation reads SexLab AnimatingFaction + the OStim scene faction
    ; (OStimActorCountFaction) + the BakaSL bridge fallback, ours OR another mod's scene.
    ; Either actor mid-scene is the crash hazard — the incident kill fired on a target
    ; bound inside SexLab thread 0 and the session died one second later.
    If IsInSexAnimation(akInitiator) || IsInSexAnimation(akTarget)
        _Log("[SNBakaEXEC] Execute refused: scene active — initiator or target is mid SexLab/OStim scene (refusing before settle)")
        _ExecuteSceneRefuse(akInitiator, akTarget)
        Return
    EndIf
    If !_IsDownedAny(akTarget)
        ; Same two late-landing races as HelpUp_Execute: native bleedout not yet adopted by
        ; the Acheron bridge, or a creature pin temporarily rescuing the victim out of Acheron.
        Float settle = 0.0
        While settle < 15.0 && !_IsDownedAny(akTarget) && (IsActorLocked(akTarget) || akTarget.IsBleedingOut()) && !akTarget.IsDead()
            Utility.Wait(0.5)
            settle += 0.5
        EndWhile
        If !_IsDownedAny(akTarget)
            _Log("[SNBaka] Execute_Execute: target not downed (waited " + settle + "s) — refusing")
            Return
        EndIf
        _Log("[SNBaka] Execute_Execute: down state landed after " + settle + "s — proceeding")
    EndIf
    ; REV-92 Task 2.2: execution gate - MCM "Execution Action Use" levels checked BEFORE the
    ; dispatch (the LLM path's only entry point; the player's own downed-menu choice-5 leg is
    ; never gated). All refusal narration + sentinels fire inside _ExecuteGateCheck.
    If !_ExecuteGateCheck(akInitiator, akTarget)
        Return
    EndIf
    If _IsDownedAny(akTarget)
        _Log("[SNBaka] Execute_Execute: " + akInitiator.GetDisplayName() + " executes " + akTarget.GetDisplayName() + " - delegating to dispatch choice 5")
        _DispatchDownedAction(5, akInitiator, akTarget)
    Else
        _Log("[SNBaka] Execute_Execute: target not downed after settle - refusing")
    EndIf
EndFunction

; REV-92 Task 2.2/2.3 - EXECUTION GATE (state + helpers). The gate runs INSIDE Execute_Execute
; for every LLM-originated fire, before the dispatch. Levels (MCM "Execution Action Use", key
; SNBaka.ExecuteGateLevel, default 0 = Unlimited): level 2 refuses ALL LLM fires outright;
; level 1 refuses NON-companion fires outright and asks the player (popup) for companion fires -
; INCLUDING commanded companions (user ruling 2026-10-10: an order is intent, consent is the
; player's). The player's own downed-menu choice-5 leg is NEVER gated (it already IS the
; player's decision).
Int _execGatePending = 0          ; 0 = idle, 1 = popup open, 2 = answered-accept, -1 = answered-deny
Actor _execGateInitiator = None
Actor _execGateTarget = None

; Sync/async determination of record (REV-92 Task 2.3a): the framework CANNOT hold a YAML
; action result open - the fire is a one-way Papyrus call from SkyrimNet's pipeline with no
; return channel the executor could block on. Designed as PAUSE-AND-WAIT instead (rev-77/78
; menu precedent): the popup Focus()-pauses the world, the executor polls for the answer with
; a hard 30s timeout -> deny-on-timeout is the fallback shape; never a hang. MOOT (target
; recovered/died) auto-closes as moot.
Bool Function _ExecuteGateCheck(Actor akInitiator, Actor akTarget)
    Int level = _ExecuteGateLevel()
    If level == 0
        Return True    ; Level 1 (Unlimited): no check.
    EndIf
    Bool isCompanion = _ExecuteIsCompanion(akInitiator)
    If level == 2
        _Log("[SNBaka] Execute_Execute: gate level 3 (Always ask) - asking player")
    ElseIf isCompanion
        _Log("[SNBaka] Execute_Execute: gate level 2 (Companions ask) - companion fire, asking player (commanded companions included, user ruling)")
    Else
        _Log("[SNBaka] Execute_Execute: gate level 2 - non-companion fire refused (reason=Companions Ask, non-companion)")
        _ExecuteGateRefuse(akInitiator, akTarget, "not one of the player's companions - the kill is not theirs to take")
        Return False
    EndIf
    If _execGatePending != 0
        _Log("[SNBaka] Execute_Execute: gate popup already open - refusing re-entrant fire")
        Return False
    EndIf
    _execGatePending = 1
    _execGateInitiator = akInitiator
    _execGateTarget = akTarget
    _Log("[SNBakaEXEC] Execute gate: POPUP-OPEN - " + akInitiator.GetDisplayName() + " vs " + akTarget.GetDisplayName())
    If SNBakaUI.IsAvailable()
        SNBakaUI.ShowExecuteConfirm(akInitiator, akTarget)
    Else
        _Log("[SNBaka] Execute_Execute: SNBakaUI unavailable - popup impossible, denying")
        _ExecuteGateAnswer(False, "popup unavailable")
        Return False
    EndIf
    ; Bounded wait: answer arrives via OnSNBakaMenuChoice ("execconfirm"); moot when the target
    ; recovers or dies; 30s timeout -> deny. The world is paused by the popup Focus(), so the
    ; poll costs nothing; the wait is always bounded - never a hang.
    String reason = "the player declined"
    Float waited = 0.0
    While _execGatePending == 1 && waited < 30.0
        Utility.Wait(0.25)
        waited += 0.25
        If _execGateTarget && (_execGateTarget.IsDead() || !_IsDownedAny(_execGateTarget))
            _Log("[SNBakaEXEC] Execute gate: MOOT - target recovered or died while waiting")
            _ExecuteGateAnswer(False, "moot")
            reason = "the moment passed - the victim is no longer helpless"
        EndIf
    EndWhile
    If _execGatePending == 1
        _Log("[SNBakaEXEC] Execute gate: TIMEOUT after " + waited + "s - denying (deny-on-timeout)")
        _ExecuteGateAnswer(False, "timeout")
        reason = "the player did not answer in time"
    EndIf
    Bool accepted = (_execGatePending == 2)
    _execGatePending = 0
    _execGateInitiator = None
    _execGateTarget = None
    If accepted
        _Log("[SNBakaEXEC] Execute gate: ACCEPT - proceeding")
    Else
        _ExecuteGateRefuse(akInitiator, akTarget, reason)
    EndIf
    Return accepted
EndFunction

; Popup answer path: DLL ExecuteConfirm mode falls through OnJSChoice's normal path as
; SNBaka_MenuChoice strArg="execconfirm", numArg 0 = accept / -1 = decline (also the DLL's
; timeout/moot auto-close token). Sentinel prefix [SNBakaEXEC].
Function _ExecuteGateAnswer(Bool abAccept, String asSource)
    If _execGatePending != 1
        Return    ; already answered or abandoned - spurious close is a no-op
    EndIf
    If abAccept
        _execGatePending = 2
        _Log("[SNBakaEXEC] Execute gate: ACCEPT (" + asSource + ")")
    Else
        _execGatePending = -1
        _Log("[SNBakaEXEC] Execute gate: DENY (" + asSource + ")")
    EndIf
EndFunction

; Refusal narration (decline/timeout/moot/non-companion): registered as a SkyrimNet event so
; the LLM sees the attempt failed and never claims the kill landed. Same cue shape as
; baka_release/baka_capture.
Function _ExecuteGateRefuse(Actor akInitiator, Actor akTarget, String asWhy)
    _Log("[SNBakaEXEC] Execute gate REFUSE - " + akInitiator.GetDisplayName() + " -> " + akTarget.GetDisplayName() + " (" + asWhy + ")")
    SkyrimNetApi.RegisterEvent("baka_execute_refused", \
        akInitiator.GetDisplayName() + " moves to finish " + akTarget.GetDisplayName() + " - but the killing blow does not land. " + asWhy + ". " + \
        "The moment passes without a death; keep roleplaying accordingly (do not claim the kill happened).", \
        akInitiator, akTarget)
EndFunction

; REV-100 fix (a): scene-active refusal narration (register entry 12a - user-edited
; wording of record, REV-101): same baka_execute_refused cue shape as _ExecuteGateRefuse
; so the LLM never claims a kill that was refused because either actor was mid
; SexLab/OStim scene. ASCII-only per the v8 checklist rider.
Function _ExecuteSceneRefuse(Actor akInitiator, Actor akTarget)
    _Log("[SNBakaEXEC] Execute refused: scene active - " + akInitiator.GetDisplayName() + " holds off from finishing " + akTarget.GetDisplayName() + " mid-scene")
    SkyrimNetApi.RegisterEvent("baka_execute_refused", \
        akInitiator.GetDisplayName() + " holds off - killing someone mid-act would end the fun, and the moment doesn't call for it. " + \
        "The killing blow does not land; keep roleplaying accordingly (do not claim the kill happened).", \
        akInitiator, akTarget)
EndFunction

Int Function _ExecuteGateLevel()
    Actor p = PlayerRef
    If !p
        p = Game.GetPlayer()
    EndIf
    Return StorageUtil.GetIntValue(p, "SNBaka.ExecuteGateLevel", 0)
EndFunction

Bool Function _ExecuteIsCompanion(Actor akActor)
    ; Companion = the player's teammate. IsPlayerTeammate() is the exact check this file already
    ; uses for followers (the FollowerSlavery gate, formerly L6555).
    If !akActor
        Return False
    EndIf
    If akActor == PlayerRef
        Return True
    EndIf
    Return akActor.IsPlayerTeammate()
EndFunction

; --- Capture ---
; The captor takes a DOWNED victim prisoner instead of killing/looting/leaving. This RESOLVES the
; encounter: the captor stops fighting (so combat does NOT resume), the victim is brought out of the
; down/bleedout state, and a captive relationship is recorded for SkyrimNet to roleplay (captor =
; master, victim = prisoner/slave). Works for both a Baka ground-window down AND an Acheron bleedout.
Function Capture_Execute(Actor akCaptor, Actor akVictim)
    _ActionLaneFire(akCaptor, akVictim, "Capture") ; [REV-174f Leg 4.2] neutral fanned lane (LLM/player-initiated; daemon fires suppressed)
    _Log("[SNBakaACT] Capture ENTER")
    If !akCaptor || !akVictim
        Return
    EndIf
    If _IsCreatureActor(akCaptor) || _IsCreatureActor(akVictim)
        _Log("[SNBaka] Capture: blocked — creature actor")
        Return
    EndIf
    If _IsDownedAny(akCaptor)
        _Log("[SNBaka] Capture: blocked — captor is downed")
        Return
    EndIf
    If !_IsDownedAny(akVictim)
        _Log("[SNBaka] Capture: target not downed — ignored")
        Return
    EndIf
    ; NPC-vs-NPC is now supported: the Calm spell + "stand down everyone hostile to the CAPTIVE"
    ; detection works regardless of who the captor is, so we no longer gate this to the player.
    _Log("[SNBaka] Capture: " + akCaptor.GetDisplayName() + " captures " + akVictim.GetDisplayName())
    Bool isPlayer = (akVictim == PlayerRef)

    ; ---- PLAYER hybrid: a brief HELD-CAPTIVE beat on the ground first, THEN freed as captive. ----
    ; The player stays down (bleedout/Acheron hold, untouched) while the captor claims them out loud —
    ; "you've been taken" — then we pull them up and hand off to the ally-faction captive state below.
    If isPlayer
        _bResetDownWindow = True
        SkyrimNetApi.RegisterEvent("baka_capture", \
            akCaptor.GetDisplayName() + " pins the beaten " + akVictim.GetDisplayName() + " down and claims them as a prisoner — the fight is over. " + \
            "Have " + akCaptor.GetDisplayName() + " SAY something RIGHT NOW while " + akVictim.GetDisplayName() + " is still held helpless on the ground — assert ownership, threaten, gloat, or give an order.", \
            akCaptor, akVictim)
        Utility.Wait(6.0)   ; the captive beat — player remains downed/held
    EndIf

    ; ---- Free the victim out of the down/bleedout state (player AFTER the beat; NPCs immediately). ----
    _bReleaseRequested = True                                  ; ends any running Baka ground window
    StorageUtil.SetIntValue(akVictim, "SNBaka.OnGround", 0)
    StorageUtil.SetStringValue(akVictim, "SNBaka.DownPose", "")
    _ClearAcheronHold(akVictim)   ; clear Acheron defeat/hold -> Downed_SkyrimNet + the bridge stand down

    ; VISUAL: the captor SEIZES the victim by the arm (reusing the arm-hold paired animation) — for the
    ; player this reads as being hauled up and led away; for NPCs it's the grab/lead-away.
    If LockBoth(akCaptor, akVictim)
        PlayPairedSimpleAnim(akCaptor, akVictim, 0.0, 0.0, 0.0, "BaboHoldArmM", "BaboHoldArmF", 4.0)
        UnlockBoth(akCaptor, akVictim)
    EndIf

    ; End the fight LAST, so the pacify isn't undone by the animation above. Captor + whole nearby
    ; group go ALLY rank so faction hostility can't re-open the fight on the new prisoner.
    _PacifyActor(akCaptor, True)
    akCaptor.StopCombat()
    akCaptor.StopCombatAlarm()
    akCaptor.SetRelationshipRank(akVictim, 4)
    akCaptor.EvaluatePackage()
    _PacifyNearbyHostiles(akVictim, 3000.0)
    If !isPlayer
        _PacifyActor(akVictim, True)
        akVictim.SetRelationshipRank(akCaptor, 4)
    EndIf
    If isPlayer
        Game.EnablePlayerControls()
    EndIf

    ; Captive state + the final "now you're my captive" cue (the held beat already prompted the claim).
    StorageUtil.SetIntValue(akVictim, "SNBaka.Captive", 1)
    If isPlayer
        SkyrimNetApi.RegisterEvent("baka_capture", \
            akCaptor.GetDisplayName() + " hauls " + akVictim.GetDisplayName() + " up by the arm — now " + akCaptor.GetDisplayName() + "'s captive, no longer enemies. Keep roleplaying as captor and prisoner.", \
            akCaptor, akVictim)
    Else
        SkyrimNetApi.RegisterEvent("baka_capture", \
            akCaptor.GetDisplayName() + " seizes " + akVictim.GetDisplayName() + " by the arm and claims them as a prisoner — the fight is over, they are no longer enemies. " + \
            akVictim.GetDisplayName() + " is now " + akCaptor.GetDisplayName() + "'s captive. " + \
            "Have " + akCaptor.GetDisplayName() + " SAY something to their new captive right now — assert ownership, threaten, gloat, or give an order — then keep roleplaying as captor/master.", \
            akCaptor, akVictim)
    EndIf
EndFunction

; --- Sell to Slavery ---
; The captor hauls the defeated PLAYER off to a slave auction, handing them to Simple Slavery Plus
; Plus (the "SSLV Entry" mod event). OPTIONAL: no-ops cleanly if Simple Slavery isn't installed or the
; MCM toggle is off. NPC victims just get a narrative beat (Simple Slavery only auctions the player).
Function SellToSlavery_Execute(Actor akSeller, Actor akVictim)
    _ActionLaneFire(akSeller, akVictim, "SellToSlavery") ; [REV-174f Leg 4.2] neutral fanned lane (LLM/player-initiated; daemon fires suppressed)
    _Log("[SNBakaACT] SellToSlavery ENTER")
    If !akSeller || !akVictim
        Return
    EndIf
    ; Real plugin-presence check (same pattern Ostim_interactions uses for Stage Flow) -- the "SSLV
    ; Entry" mod event no-ops harmlessly without SS++, but everything BEFORE it (clearing the defeat
    ; state, re-enabling player controls, the capture narration) very much doesn't: without the actual
    ; auction to hand off to, this action just silently freed the victim.
    If !IsSimpleSlaveryInstalled()
        _Log("[SNBaka] SellToSlavery: blocked — SimpleSlavery.esp not installed")
        Return
    EndIf
    If _IsCreatureActor(akSeller) || _IsCreatureActor(akVictim)
        _Log("[SNBaka] SellToSlavery: blocked — creature actor")
        Return
    EndIf
    If _IsDownedAny(akSeller)
        _Log("[SNBaka] SellToSlavery: blocked — seller is downed")
        Return
    EndIf
    ; Every other SNBaka_Downed sibling (HelpUp, Capture, ...) checks the target is actually downed
    ; before doing anything -- this one didn't, so nothing stopped it firing on a fully healthy,
    ; standing victim (the player included) and sending them straight to auction with no precondition.
    If !_IsDownedAny(akVictim)
        _Log("[SNBaka] SellToSlavery: blocked — victim not downed")
        Return
    EndIf
    If akVictim != PlayerRef
        ; Simple Slavery auctions the player only — narrate the rest.
        SkyrimNetApi.RegisterEvent("baka_capture", \
            akSeller.GetDisplayName() + " hauls the defeated " + akVictim.GetDisplayName() + " away to be sold into slavery.", \
            akSeller, akVictim)
        Return
    EndIf
    If !bSellToSlavery
        _Log("[SNBaka] SellToSlavery: disabled in MCM — skipped")
        Return
    EndIf
    ; Clean the defeat state before the hand-off so the player isn't bleeding out/Acheron-held at the
    ; auction. _bReleaseRequested only helps if a _DefeatGroundWindow loop happens to be actively
    ; polling it right now (e.g. victim came from a plain vanilla bleedout or a standalone Acheron
    ; hold, neither of which has one running) -- UnlockBoth explicitly clears SNBaka.Locked on both
    ; actors regardless, the same guarantee Capture_Execute gets from its own LockBoth/UnlockBoth
    ; cycle. Without it, a player sent to auction from one of those states would stay SNBaka.Locked=1
    ; forever, locked out of every Baka interaction after returning from the auction.
    _ClearAcheronHold(akVictim)
    _bReleaseRequested = True
    StorageUtil.SetIntValue(akVictim, "SNBaka.OnGround", 0)
    UnlockBoth(akSeller, akVictim)
    SkyrimNetApi.RegisterEvent("baka_capture", \
        akSeller.GetDisplayName() + " drags " + akVictim.GetDisplayName() + " off to be sold at a slave auction.", \
        akSeller, akVictim)
    Utility.Wait(1.0)
    ; Hand off to Simple Slavery Plus Plus via its "SSLV Entry" mod event. If SS++ isn't installed,
    ; nothing is listening and this is a harmless no-op (so it's a soft dependency).
    SendModEvent("SSLV Entry")
    _Log("[SNBaka] SellToSlavery: sent SSLV Entry")
EndFunction

; --- EnslaveFollower ---
; An NPC hauls the player's DOWNED follower off into slavery via the Follower Slavery Mod (FSM).
; Deliberately narrow so the LLM can never confuse it with SellToSlavery (which auctions the PLAYER
; via Simple Slavery++): the captor must be a living, non-creature NPC; the target must be a downed
; player-TEAMMATE (never the player); and the player must be either downed themselves or farther
; than fSlaveryPlayerDistance — you only lose a follower you couldn't defend.
Function EnslaveFollower_Execute(Actor akCaptor, Actor akFollower)
    _ActionLaneFire(akCaptor, akFollower, "EnslaveFollower") ; [REV-174f Leg 4.2] neutral fanned lane (LLM/player-initiated; daemon fires suppressed)
    _Log("[SNBakaACT] EnslaveFollower ENTER")
    If !bEnabled || !bFollowerSlavery || !akCaptor || !akFollower
        Return
    EndIf
    If !IsFollowerSlaveryInstalled()
        _Log("[SNBaka] EnslaveFollower: blocked — Follower Slavery Mod not installed/initialized (open its MCM and Install)")
        Return
    EndIf
    If akFollower == PlayerRef || akCaptor == PlayerRef
        _Log("[SNBaka] EnslaveFollower: blocked — player involved (SellToSlavery is the player path)")
        Return
    EndIf
    If _IsCreatureActor(akCaptor) || _CreatureAnimKey(akCaptor) != "" || akCaptor.IsDead() || _IsDownedAny(akCaptor)
        _Log("[SNBaka] EnslaveFollower: blocked — captor is a creature, dead, or downed")
        Return
    EndIf
    If !akFollower.IsPlayerTeammate()
        _Log("[SNBaka] EnslaveFollower: blocked — " + akFollower.GetDisplayName() + " is not a follower of the player")
        Return
    EndIf
    If !_IsDownedAny(akFollower)
        _Log("[SNBaka] EnslaveFollower: blocked — follower is not downed")
        Return
    EndIf
    If IsActorLocked(akFollower) || IsInSexAnimation(akFollower)
        _Log("[SNBaka] EnslaveFollower: blocked — follower is mid-interaction/scene")
        Return
    EndIf
    If !_IsDownedAny(PlayerRef) && PlayerRef.GetDistance(akFollower) < fSlaveryPlayerDistance
        _Log("[SNBaka] EnslaveFollower: blocked — player is up and close enough to intervene (" + PlayerRef.GetDistance(akFollower) + " < " + fSlaveryPlayerDistance + ")")
        Return
    EndIf
    _Log("[SNBaka] EnslaveFollower: " + akCaptor.GetDisplayName() + " enslaves the downed " + akFollower.GetDisplayName())
    ; Visual cue: the captor kneels over the follower, binding them for the road (captor is always
    ; an NPC here, so the third-person-only Babo_Kneel is safe — same beat HelpUp/TieUp use).
    Debug.SendAnimationEvent(akCaptor, "Babo_Kneel")
    Utility.Wait(2.0)
    Debug.SendAnimationEvent(akCaptor, "IdleForceDefaultState")
    ; Clean OUR entire state off the follower first (Acheron hold, locks, pacify, bonds, ghost) —
    ; FSM force-moves and re-manages them from here on; two systems must never co-own the actor.
    _ForceRecover(akFollower)
    ; Narrate BEFORE the handoff so the LLM knows exactly what happened, to whom, by whom.
    SkyrimNetApi.RegisterEvent("baka_enslaved", \
        akCaptor.GetDisplayName() + " binds the beaten " + akFollower.GetDisplayName() + " and drags them away into slavery — they are no longer part of the player's party.", \
        akCaptor, akFollower)
    _Notify(akFollower.GetDisplayName() + " has been taken into slavery!")
    ; FSM's documented external API (fsm_utilityscript.psc): offer the captor as the master, with
    ; fallback allowed so FSM picks a valid one if the captor doesn't qualify as a master.
    Int hEnslave = ModEvent.Create("fsm_enslavefollower")
    If hEnslave
        ModEvent.PushForm(hEnslave, akFollower)
        ModEvent.PushForm(hEnslave, akCaptor)
        ModEvent.PushString(hEnslave, "")
        ModEvent.PushBool(hEnslave, True)
        ModEvent.Send(hEnslave)
        _Log("[SNBaka] EnslaveFollower: fsm_enslavefollower sent (follower=" + akFollower.GetDisplayName() + " master=" + akCaptor.GetDisplayName() + ", fallback allowed)")
    Else
        _Log("[SNBaka] EnslaveFollower: ERROR — ModEvent.Create failed, FSM handoff not sent")
    EndIf
EndFunction

; --- SitOnLap (plugin: Immersive Lap Sitting) ---
; The speaker settles onto the lap of a currently-SEATED actor (player or NPC), by driving that
; mod's own machinery exactly the way its "sit on my lap" dialogue fragment does (read from its
; compiled TIF): fill quest alias 0 (LapSitNPC) with the sitter, self-cast HSF_LapSitSpell on the
; lap OWNER (whose position the invisible chair is aligned to), start its hold-still scene. The
; mod's own chair script handles the entire lifecycle from there, including cleanup when the
; player walks away. Soft dependency -- every form is resolved per-call via GetFormFromFile, and
; Setup()/the MCM keep the action out of the LLM's menu when the esp is absent or the toggle off.
; LLM-facing entry (YAML lap_sit.yaml — exact 2-param arity match for SkyrimNet's dispatcher).
; Player-as-sitter is blocked on this path; the interact menu's own entry goes through
; LapSitPlayer_Execute below instead.
Function LapSit_Execute(Actor akSitter, Actor akSeated)
    _ActionLaneFire(akSitter, akSeated, "LapSit") ; [REV-174f Leg 4.2] neutral fanned lane (LLM/player-initiated; daemon fires suppressed)
    _DoLapSit(akSitter, akSeated, False)
EndFunction

; Interact-menu entry (menu id 25, "Sit on Lap"): the PLAYER sits on the seated target's lap.
; Menu path notifies on failure -- a clicked button that silently does nothing reads as broken.
Function LapSitPlayer_Execute(Actor akCaster, Actor akTarget)
    _ActionLaneFire(akCaster, akTarget, "LapSit") ; [REV-174f Leg 4.2] neutral fanned lane (LLM/player-initiated; daemon fires suppressed)
    If akCaster != PlayerRef
        Return
    EndIf
    _DoLapSit(PlayerRef, akTarget, True)
EndFunction

Function _DoLapSit(Actor akSitter, Actor akSeated, Bool abPlayerSitter)
    _Log("[SNBakaACT] SitOnLap ENTER (playerSitter=" + abPlayerSitter + ")")
    If !bEnabled || !bLapSitEnabled || !akSitter || !akSeated || akSitter == akSeated
        If abPlayerSitter && !bLapSitEnabled
            _Notify("Lap Sitting is disabled in the Baka MCM (Lap Sitting page).")
        EndIf
        Return
    EndIf
    If akSitter == PlayerRef && !abPlayerSitter
        ; The LLM never drives the player onto a lap -- the player does that themselves via the
        ; interact menu (LapSitPlayer_Execute) or the mod's own dialogue.
        _Log("[SNBaka] SitOnLap: blocked — player as sitter on the LLM path")
        Return
    EndIf
    Quest lapQuest = Game.GetFormFromFile(0x00080A, "Lap Sitting.esp") as Quest
    Spell lapSpell = Game.GetFormFromFile(0x000802, "Lap Sitting.esp") as Spell
    Scene lapScene = Game.GetFormFromFile(0x00080F, "Lap Sitting.esp") as Scene
    If !lapQuest || !lapSpell
        _Log("[SNBaka] SitOnLap: blocked — Lap Sitting.esp not installed")
        If abPlayerSitter
            _Notify("Sit on Lap requires the Immersive Lap Sitting mod.")
        EndIf
        Return
    EndIf
    If _IsCreatureActor(akSitter) || _CreatureAnimKey(akSitter) != "" || _IsCreatureActor(akSeated) || _CreatureAnimKey(akSeated) != ""
        _Log("[SNBaka] SitOnLap: blocked — creature actor")
        Return
    EndIf
    If akSitter.IsInCombat() || akSeated.IsInCombat()
        _Log("[SNBaka] SitOnLap: blocked — combat")
        Return
    EndIf
    If akSeated.GetSitState() != 3
        _Log("[SNBaka] SitOnLap: blocked — " + akSeated.GetDisplayName() + " is not actually seated (sitState=" + akSeated.GetSitState() + ")")
        If abPlayerSitter
            _Notify(akSeated.GetDisplayName() + " is not sitting on anything.")
        EndIf
        Return
    EndIf
    If akSitter.GetSitState() != 0
        _Log("[SNBaka] SitOnLap: blocked — sitter is themselves sitting/transitioning")
        Return
    EndIf
    If akSitter.GetDistance(akSeated) > 600.0
        _Log("[SNBaka] SitOnLap: blocked — too far apart (" + akSitter.GetDistance(akSeated) + ")")
        Return
    EndIf
    If _IsDownedAny(akSitter) || _IsDownedAny(akSeated) || IsActorLocked(akSitter) || IsActorLocked(akSeated) \
            || IsInSexAnimation(akSitter) || IsInSexAnimation(akSeated)
        _Log("[SNBaka] SitOnLap: blocked — an actor is downed/locked/mid-scene")
        Return
    EndIf
    ; ONE lap-sit at a time, globally -- the mod has a single alias + chair flow. Either alias
    ; occupied (its NPC-on-lap alias 0 OR its player-sits alias 1) means a sit is already running.
    ReferenceAlias sitterAlias = lapQuest.GetAlias(0) as ReferenceAlias   ; LapSitNPC
    ReferenceAlias lapOwnerAlias = lapQuest.GetAlias(1) as ReferenceAlias ; SitonLapNPC (the mod's player-sits flow)
    If !sitterAlias
        _Log("[SNBaka] SitOnLap: blocked — could not resolve the LapSitNPC alias")
        Return
    EndIf
    If sitterAlias.GetReference() != None || (lapOwnerAlias && lapOwnerAlias.GetReference() != None)
        _Log("[SNBaka] SitOnLap: blocked — a lap-sit is already in progress (mod supports one at a time)")
        If abPlayerSitter
            _Notify("Someone is already sitting on a lap - one at a time.")
        EndIf
        Return
    EndIf
    ; A start-game-enabled quest can still be found stopped (mod added mid-save, or its RunOnce flag
    ; after a stop) -- ForceRefTo on a stopped quest silently no-ops, which reads as "did nothing".
    If !lapQuest.IsRunning()
        lapQuest.Start()
        Utility.Wait(0.2)
        _Log("[SNBaka] SitOnLap: HSF_LapSitQuest was not running — Start() called (running now=" + lapQuest.IsRunning() + ")")
    EndIf
    _Log("[SNBaka] SitOnLap: " + akSitter.GetDisplayName() + " sits on " + akSeated.GetDisplayName() + "'s lap (playerSitter=" + abPlayerSitter + ")")

    ; EXACT replication of the mod's two flows, from its DECOMPILED sources (Champollion) -- the
    ; string-level reverse-engineering had the two flows INVERTED, which is why every earlier attempt
    ; failed. Ground truth:
    ;   * Alias 0 (LapSitNPC)   = the NPC whose lap the PLAYER sits on (flow 805, spell/MGEF). The
    ;     DoNothing scene (0x80F) holds THIS actor still.
    ;   * Alias 1 (SitonLapNPC) = the NPC who sits on the SEATED PLAYER's lap (flow 807) -- driven by
    ;     an AI PACKAGE attached to the alias (HSF_SitonLapPkg -> sits in the LapChair alias), never
    ;     by Activate.
    ;   * Alias 2 (LapChair)    = the placed invisible chair (the package's sit target).
    ; The chair script (on the FURN base) owns cleanup for every placed instance: once the player is
    ; >100 units away it clears all three aliases and deletes itself.
    Furniture chairBase = Game.GetFormFromFile(0x000803, "Lap Sitting.esp") as Furniture
    If !chairBase
        _Log("[SNBaka] SitOnLap: could not resolve the NPCChair furniture — aborting")
        Return
    EndIf
    ReferenceAlias chairAlias = lapQuest.GetAlias(2) as ReferenceAlias   ; LapChair
    ObjectReference chair = akSeated.PlaceAtMe(chairBase)
    If !chair
        _Log("[SNBaka] SitOnLap: PlaceAtMe returned None — aborting")
        Return
    EndIf
    Float ownerZ = akSeated.GetAngleZ()
    Float ownerY = akSeated.GetAngleY()

    If abPlayerSitter
        ; Flow 805 replica (player sits on the seated NPC's lap), minus the spell wrapper -- its
        ; magic effect's entire body is this placement + Activate, and skipping the cast avoids the
        ; casting-animation problems Spell.Cast caused from script. Constants verbatim from the MGEF.
        chair.MoveTo(akSeated, 40.0 * Math.Sin(ownerZ + 27.0), 40.0 * Math.Cos(ownerZ + 27.0), 0.0, True)
        chair.SetAngle(0.0, ownerY, ownerZ - 50.0)
        chair.SetPosition(chair.GetPositionX(), chair.GetPositionY(), chair.GetPositionZ() + 5.0)
        If sitterAlias
            sitterAlias.ForceRefTo(akSeated)   ; alias 0: the lap owner, held by the DoNothing scene
        EndIf
        Utility.Wait(0.2)
        chair.Activate(akSitter)
        If lapScene
            lapScene.Start()                   ; holds the owner NPC still while the player sits
        EndIf
    Else
        ; Flow 807 replica (NPC sits on the seated owner's lap). Constants verbatim from the TIF.
        ; No Activate -- filling alias 1 hands the NPC to the mod's own sit package.
        If chairAlias
            chairAlias.ForceRefTo(chair)       ; must be filled BEFORE the sitter alias (package target)
        EndIf
        chair.MoveTo(akSeated, 35.0 * Math.Sin(ownerZ + 44.0), 35.0 * Math.Cos(ownerZ + 44.0), 0.0, True)
        chair.SetAngle(0.0, ownerY, ownerZ - 75.0)
        chair.SetPosition(chair.GetPositionX(), chair.GetPositionY(), chair.GetPositionZ() + 6.0)
        If lapOwnerAlias
            lapOwnerAlias.ForceRefTo(akSitter) ; alias 1 (SitonLapNPC): the package-driven sitter
        EndIf
        akSitter.EvaluatePackage()             ; kick the sit package immediately
        _Log("[SNBaka] SitOnLap: chair placed at " + chair.GetPositionX() + "," + chair.GetPositionY() + "," + chair.GetPositionZ() \
            + "  sitterAliasTook=" + (lapOwnerAlias && lapOwnerAlias.GetReference() == akSitter) \
            + "  chairAliasTook=" + (chairAlias && chairAlias.GetReference() == chair))
        ; NPC-NPC only: the mod's flow assumes a player owner (who holds still by themselves) --
        ; an NPC owner needs the same scene hold flow 805 gives, or their AI may stand them up.
        If akSeated != PlayerRef
            If sitterAlias
                sitterAlias.ForceRefTo(akSeated)
            EndIf
            If lapScene
                lapScene.Start()
            EndIf
        EndIf
    EndIf

    ; Verify the sitter actually engages the chair. Package-driven sitters WALK there, so allow a
    ; real approach window; sitState leaves 0 as soon as the furniture grabs them. FOLLOWER
    ; LIMITATION (suspected live with Ashe, a custom-framework follower): a follower's own
    ; high-priority follow package can outrank the mod's alias sit package, leaving the sitter
    ; standing forever -- so if the package hasn't engaged them after a few seconds, force the sit
    ; with a direct chair Activate (reliable for NPCs on an ACCESSIBLE chair -- the one earlier
    ; Activate failure was a mis-placed overlapping chair, not the mechanism).
    ; Real-clock elapsed, NOT a naive tick counter -- same class of bug already found and fixed
    ; elsewhere this session (_WaitOrAbort, _PollResist, _RecoveryPeriod): under VM load a
    ; Utility.Wait(0.5) can genuinely take several times longer than 0.5 real seconds, so counting
    ; "sitWait += 0.5" per iteration silently let this loop's real duration balloon far past its
    ; nominal 12s cap -- plausibly for minutes, which is long enough to explain a Papyrus call that
    ; never returns and, if SkyrimNet's action dispatcher processes one call at a time, would
    ; silence every OTHER actor's actions behind it too (confirmed live: nothing executed for
    ; anyone for 6+ minutes after one SitOnLap call).
    Float sitCap = 3.0
    If !abPlayerSitter
        sitCap = 12.0
    EndIf
    Bool forcedSit = False
    Float sitStartRT = Utility.GetCurrentRealTime()
    While (Utility.GetCurrentRealTime() - sitStartRT) < sitCap && akSitter.GetSitState() == 0
        Utility.Wait(0.5)
        If !abPlayerSitter && !forcedSit && (Utility.GetCurrentRealTime() - sitStartRT) >= 3.0
            forcedSit = True
            ; Confirmed live: a direct chair Activate() ALONE still wasn't enough for a follower --
            ; her framework's own AI kept reasserting and cancelling the sit transition before it
            ; could stick, same as the alias package losing to it. _HoldActorAI is the SAME priority-
            ; 100 DoNothing override every other paired interaction in this file already uses to
            ; strip exactly this kind of AI interference -- apply it now (not from the start, so the
            ; mod's own package gets its normal first shot without us fighting it) to give the forced
            ; Activate a real, uncontested chance to land.
            _Log("[SNBaka] SitOnLap: package hasn't engaged the sitter after 3s (follower package priority?) — holding their AI and forcing the sit via chair Activate")
            _HoldActorAI(akSitter, True)
            chair.Activate(akSitter)
        EndIf
    EndWhile
    If akSitter.GetSitState() == 0
        _Log("[SNBaka] SitOnLap: sitter never engaged the chair after " + sitCap + "s — rolling back")
        If forcedSit
            _HoldActorAI(akSitter, False)
        EndIf
        If chairAlias
            chairAlias.Clear()
        EndIf
        If lapOwnerAlias
            lapOwnerAlias.Clear()
        EndIf
        If sitterAlias
            sitterAlias.Clear()
        EndIf
        If lapScene && lapScene.IsPlaying()
            lapScene.Stop()
        EndIf
        chair.Disable()
        chair.Delete()
        If abPlayerSitter
            _Notify("Couldn't sit - try standing right in front of " + akSeated.GetDisplayName() + " and using it again.")
        EndIf
        Return
    EndIf
    ; Sit confirmed -- release the AI hold now that the furniture state itself is holding them (the
    ; contested moment was the transition INTO the sit, not staying in it). Leaving the DoNothing
    ; override on would also block the mod's own chair script from ever getting a package tick to
    ; notice the player walking away and clean up.
    If forcedSit
        _HoldActorAI(akSitter, False)
    EndIf
    _Log("[SNBaka] SitOnLap: sitter engaged the chair (sitState=" + akSitter.GetSitState() + ") — mod's chair script owns cleanup from here")

    _CueOutcome("baka_intimate", \
        akSitter.GetDisplayName() + " settles onto " + akSeated.GetDisplayName() + "'s lap, making themselves comfortable there.", \
        akSitter, akSeated)
EndFunction

; --- TieUp / Untie ---
; A TIED victim is a downed actor held in the captured pose whose auto-get-up timer is suspended for
; fTiedHours GAME hours (the bridge's tick honors SNBaka.Tied/TiedUntilGT): they cannot get up unless
; helped (HelpUp unties and lifts them) or until the binding lapses, at which point they fall back to
; a NORMAL down with a fresh timer. Built for keeping prisoners around to interrogate.
Function TieUp_Execute(Actor akBinder, Actor akTarget)
    _ActionLaneFire(akBinder, akTarget, "TieUp") ; [REV-174f Leg 4.2] neutral fanned lane (LLM/player-initiated; daemon fires suppressed)
    _Log("[SNBakaACT] TieUp ENTER")
    If !bEnabled || !akBinder || !akTarget
        Return
    EndIf
    If akTarget == PlayerRef
        _Log("[SNBaka] TieUp: blocked — never the player (their downed state already has its own rules)")
        Return
    EndIf
    If _IsCreatureActor(akBinder) || _CreatureAnimKey(akBinder) != "" || _IsCreatureActor(akTarget) || _CreatureAnimKey(akTarget) != ""
        _Log("[SNBaka] TieUp: blocked — creature involved")
        Return
    EndIf
    If _IsDownedAny(akBinder) || akBinder.IsDead() || akTarget.IsDead()
        _Log("[SNBaka] TieUp: blocked — binder downed/dead or target dead")
        Return
    EndIf
    If !_IsDownedAny(akTarget)
        _Log("[SNBaka] TieUp: blocked — target is not downed")
        Return
    EndIf
    If IsActorLocked(akTarget) || IsInSexAnimation(akTarget)
        _Log("[SNBaka] TieUp: blocked — target mid-interaction/scene")
        Return
    EndIf
    If StorageUtil.GetIntValue(akTarget, "SNBaka.Tied", 0) == 1
        _Log("[SNBaka] TieUp: already tied")
        Return
    EndIf
    ; The binder crouches over them while tying the knots — same proven anim pair HelpUp uses:
    ; IdleTake for the PLAYER (vanilla pick-up idle, has first-person data), Babo_Kneel for NPCs
    ; (custom third-person-only kneel, never sent to the player). SHEATHE FIRST — the animation
    ; graph silently rejects idle events while a weapon is drawn, which is exactly the reported
    ; "no animation played" (a beat right after combat almost always has weapons out).
    akBinder.SheatheWeapon()
    Utility.Wait(0.8)
    If akBinder == PlayerRef
        Game.ForceThirdPerson()   ; idles are invisible in first person — the other "no animation" case
        Debug.SendAnimationEvent(akBinder, "IdleTake")
        Utility.Wait(2.0)
        Debug.SendAnimationEvent(akBinder, "IdleForceDefaultState")   ; IdleTake doesn't reliably self-reset (see HelpUp)
    Else
        Debug.SendAnimationEvent(akBinder, "Babo_Kneel")
        Utility.Wait(2.0)
        Debug.SendAnimationEvent(akBinder, "IdleForceDefaultState")
    EndIf
    ; TIED POSE: Babo's captured pose, full stop. The ZaZ pose pool was REMOVED after a confirmed
    ; T-pose — a mod folder being present doesn't mean its animations were built into the behavior
    ; graphs, and an unbuilt event T-poses the actor. Rule going forward: only base-game events and
    ; the Baka Motion Data Pack (a hard requirement, always built) are ever sent. The pose is stored
    ; as the actor's down pose so every restore path re-asserts it.
    String tiedPose = "Babo_Captured_A1"
    StorageUtil.SetIntValue(akTarget, "SNBaka.Tied", 1)
    StorageUtil.SetFloatValue(akTarget, "SNBaka.TiedUntilGT", Utility.GetCurrentGameTime() + (fTiedHours / 24.0))
    StorageUtil.SetStringValue(akTarget, "SNBaka.DownPose", tiedPose)
    Debug.SendAnimationEvent(akTarget, tiedPose)
    SkyrimNetApi.RegisterEvent("baka_tied", \
        akBinder.GetDisplayName() + " binds the beaten " + akTarget.GetDisplayName() + " hand and foot — tied on the ground, going nowhere until someone cuts them loose.", \
        akBinder, akTarget)
    _Notify(akTarget.GetDisplayName() + " has been tied up.")
    _Log("[SNBaka] TieUp: " + akTarget.GetDisplayName() + " tied for " + fTiedHours + " game hours")
EndFunction

Function Untie_Execute(Actor akCutter, Actor akTarget)
    _ActionLaneFire(akCutter, akTarget, "Untie") ; [REV-174f Leg 4.2] neutral fanned lane (LLM/player-initiated; daemon fires suppressed)
    _Log("[SNBakaACT] Untie ENTER")
    If !bEnabled || !akCutter || !akTarget
        Return
    EndIf
    If StorageUtil.GetIntValue(akTarget, "SNBaka.Tied", 0) != 1
        _Log("[SNBaka] Untie: target is not tied — nothing to cut")
        Return
    EndIf
    If _IsDownedAny(akCutter) || akCutter.IsDead()
        _Log("[SNBaka] Untie: blocked — cutter downed/dead")
        Return
    EndIf
    ; Same crouch beat as TieUp/HelpUp — kneeling over them, cutting the bindings. Sheathe first:
    ; the graph rejects idle events with a weapon drawn (the reported "untie has no animation").
    akCutter.SheatheWeapon()
    Utility.Wait(0.8)
    If akCutter == PlayerRef
        Game.ForceThirdPerson()   ; idles are invisible in first person
        Debug.SendAnimationEvent(akCutter, "IdleTake")
        Utility.Wait(2.0)
        Debug.SendAnimationEvent(akCutter, "IdleForceDefaultState")   ; IdleTake doesn't reliably self-reset (see HelpUp)
    Else
        Debug.SendAnimationEvent(akCutter, "Babo_Kneel")
        Utility.Wait(2.0)
        Debug.SendAnimationEvent(akCutter, "IdleForceDefaultState")
    EndIf
    StorageUtil.SetIntValue(akTarget, "SNBaka.Tied", 0)
    StorageUtil.SetFloatValue(akTarget, "SNBaka.TiedUntilGT", 0.0)
    StorageUtil.SetStringValue(akTarget, "SNBaka.DownPose", "")
    ; Untied is NOT freed — they drop back to a NORMAL down: fresh full timer, normal recovery rules.
    Debug.SendAnimationEvent(akTarget, "BleedoutStart")
    StorageUtil.SetFloatValue(akTarget, "SNBaka.AutoGetUpDeadlineRT", Utility.GetCurrentRealTime() + StorageUtil.GetFloatValue(PlayerRef, "SNAcheron.AutoGetUpSeconds", 600.0))
    SkyrimNetApi.RegisterEvent("baka_untied", \
        akCutter.GetDisplayName() + " cuts " + akTarget.GetDisplayName() + " loose — still beaten and down, but no longer bound.", \
        akCutter, akTarget)
    _Log("[SNBaka] Untie: " + akTarget.GetDisplayName() + " untied (still downed, fresh timer)")
EndFunction

; --- Escalate ---
; Entry for BOTH the LLM action path (DLL action execution) AND the PrismaUI downed-menu's
; choice 0 (line ~6649 dispatch) -- both land here and both are covered by the retry window.
; AcheronNG's native Hunter's Pride menu calls _DoEscalation directly and is NOT covered.
; akTarget must be on the ground (SNBaka.OnGround = 1) or externally downed (Acheron).
; akInitiator must be free (not locked). Sets _bEscalateRequested so
; _DefeatGroundWindow proceeds to _DoEscalation.
; v2.0.10 lock-race fix (docs/LOCKRACE_FIX_DESIGN.md, variant (c)): the initiator-locked
; block no longer silently drops the call -- it enters _EscalateRetryWindow (bounded
; settle, one fresh full-gate revalidation, slipped cue on expiry/permanent failure).
Function Escalate_Execute(Actor akInitiator, Actor akTarget)
    _ActionLaneFire(akInitiator, akTarget, "Escalate") ; [REV-174f Leg 4.2] neutral fanned lane (LLM/player-initiated; daemon fires suppressed)
    _Log("[SNBakaACT] Escalate ENTER")
    ; REV-146a Task 2: child boundary - escalation entry point.
    If _ChildBoundaryRefused(akInitiator, akTarget, "Escalate")
        Return
    EndIf
    _Log("[SNBaka] Escalate_Execute: initiator=" + akInitiator.GetDisplayName() + " target=" + akTarget.GetDisplayName() + " OnGround=" + StorageUtil.GetIntValue(akTarget, "SNBaka.OnGround", 0) + " InitLocked=" + StorageUtil.GetIntValue(akInitiator, "SNBaka.Locked", 0) + " bNPCCanEscalate=" + bNPCCanEscalate)
    String blockReason = _EscalateValidate(akInitiator, akTarget)
    If blockReason == "initiator locked"
        If _bEscalateRetryActive
            ; Supersede (single-entry policy): an earlier dropped call already owns the retry
            ; window. Record WHO was superseded and WHY the window was still live, so a wild
            ; supersede tells its story in the log without a new investigation.
            _Log("[SNBaka] EscalateRetry: superseded — initiator=" + akInitiator.GetDisplayName() + " target=" + akTarget.GetDisplayName() + " — dropped again while an earlier dropped call's window was still active (single-entry policy; this call is not queued)")
            Return
        EndIf
        _Log("[SNBaka] Escalate_Execute: blocked — initiator locked (entering retry window)")
        _EscalateRetryWindow(akInitiator, akTarget)
        Return
    ElseIf blockReason != ""
        Return
    EndIf
    _EscalateAccept(akInitiator, akTarget)
EndFunction

; The full Escalate gate chain, extracted so the retry window revalidates with the EXACT
; same code (absolute revalidation -- zero stale-state assumptions; the same standard as
; the T3 floor's self-guard discipline). Returns "" when every gate passes, otherwise the
; block reason. Trace strings are identical to the pre-refactor blocks so standing
; forensic greps keep working. The initiator-locked case returns WITHOUT tracing here --
; its handling IS the retry logic, and the caller (dispatcher / retry fire path) narrates.
String Function _EscalateValidate(Actor akInitiator, Actor akTarget)
    If !akTarget || !akInitiator
        _Log("[SNBaka] Escalate_Execute: blocked — None actor")
        Return "none actor"
    EndIf
    If _IsCreatureActor(akInitiator) || _IsCreatureActor(akTarget)
        _Log("[SNBaka] Escalate_Execute: blocked — creature actor (use CreatureEscalate instead)")
        Return "creature actor"
    EndIf
    ; REV-144 4.2: central player-target admission rides the shared Escalate gate chain so
    ; the retry window revalidates it identically (absolute revalidation discipline).
    If !_PlayerTargetAdmitted(akInitiator, akTarget, "EscalateValidate")
        Return "player-target policy off"
    EndIf
    ; Content-preference filter, not a technical constraint -- same precedent as bNPCCanEscalate below,
    ; only gates a non-player initiator. The player targeting whoever they want is their own choice.
    If akInitiator != PlayerRef && !_TargetSexAllowed(akTarget)
        _Log("[SNBaka] Escalate_Execute: blocked — target sex not allowed by MCM (iTargetSex=" + iTargetSex + ")")
        Return "target sex not allowed"
    EndIf
    Bool ours = StorageUtil.GetIntValue(akTarget, "SNBaka.OnGround", 0) == 1
    Bool external = !ours && _IsDownedAny(akTarget)
    If !ours && !external
        _Log("[SNBaka] Escalate_Execute: blocked — target not downed")
        Return "target not downed"
    EndIf
    If StorageUtil.GetIntValue(akInitiator, "SNBaka.Locked", 0) == 1
        Return "initiator locked"
    EndIf
    If _IsDownedAny(akInitiator)
        _Log("[SNBaka] Escalate_Execute: blocked — initiator is downed")
        Return "initiator downed"
    EndIf
    If akInitiator != PlayerRef && !bNPCCanEscalate
        _Log("[SNBaka] Escalate_Execute: blocked — NPC escalation disabled (bNPCCanEscalate=False)")
        Return "npc escalation disabled"
    EndIf
    Return ""
EndFunction

; Post-gate body, extracted so the original call and the retry's fire path run the
; IDENTICAL accept sequence (tears, the baka_escalate event, ours/external dispatch).
; ours is recomputed here -- by design: the accept path re-reads the ground state fresh
; rather than trusting anything the validation pass saw.
Function _EscalateAccept(Actor akInitiator, Actor akTarget)
    Bool ours = StorageUtil.GetIntValue(akTarget, "SNBaka.OnGround", 0) == 1
    _StartTears(akTarget)
    SkyrimNetApi.RegisterEvent("baka_escalate", \
        akInitiator.GetDisplayName() + " moves in on the helpless " + akTarget.GetDisplayName() + ".", \
        akInitiator, akTarget)
    If ours
        _Log("[SNBaka] Escalate_Execute: accepted — signalling the ground window")
        _bEscalateRequested = True       ; our ground window picks this up
    Else
        _Log("[SNBaka] Escalate_Execute: accepted — external down, escalating directly")
        _DoEscalation(akInitiator, akTarget)   ; no window of ours -> run it now
    EndIf
EndFunction

; The settle window itself (inline, house style -- cf. the bleedout settle wait in
; _DispatchDownedAction, added for the same disease class). Utility.Wait yields this
; stack, so _CleanupPair (the lock clearer, running on the QTE-resolution stack)
; proceeds fine while we wait -- no self-deadlock. On lock clear: ONE fresh full-gate
; validation via _EscalateValidate; pass -> _EscalateAccept (no recursion, no second
; window); relock-at-fire / permanent block / initiator death / cap expiry ->
; _EscalateSlippedCue. Single-shot: the wait never restarts once the lock has been
; seen clear (a re-acquired lock at fire time counts as expiry, per the design doc).
Function _EscalateRetryWindow(Actor akInitiator, Actor akTarget)
    _bEscalateRetryActive = True
    Float startRT = Utility.GetCurrentRealTime()
    _Log("[SNBaka] EscalateRetry: queued — initiator=" + akInitiator.GetDisplayName() + " target=" + akTarget.GetDisplayName() + " window=" + fEscalateRetryWindowSec + "s")
    String verdict = ""
    Bool lockSeenClear = False
    Bool done = False
    While !done && (Utility.GetCurrentRealTime() - startRT) < fEscalateRetryWindowSec
        If !akInitiator || akInitiator.IsDead()
            verdict = "initiator dead"
            done = True
        ElseIf !lockSeenClear
            If StorageUtil.GetIntValue(akInitiator, "SNBaka.Locked", 0) == 0
                lockSeenClear = True
            Else
                Utility.Wait(fEscalateRetryPollSec)
            EndIf
        Else
            ; Lock has cleared -- validate ONCE, fresh, every gate.
            String reblock = _EscalateValidate(akInitiator, akTarget)
            If reblock == ""
                verdict = "accepted"
            ElseIf reblock == "initiator locked"
                verdict = "relocked during fire"    ; single-shot: the wait never restarts
            Else
                verdict = "blocked at fire: " + reblock
            EndIf
            done = True
        EndIf
    EndWhile
    _bEscalateRetryActive = False
    Float waited = Utility.GetCurrentRealTime() - startRT
    If verdict == "accepted"
        _Log("[SNBaka] EscalateRetry: fired -> accepted after " + waited + "s")
        _EscalateAccept(akInitiator, akTarget)
    ElseIf verdict == ""
        _Log("[SNBaka] EscalateRetry: expired — still locked after " + waited + "s (window cap)")
        _EscalateSlippedCue(akInitiator, akTarget, "expired")
    Else
        _Log("[SNBaka] EscalateRetry: " + verdict + " (" + waited + "s)")
        _EscalateSlippedCue(akInitiator, akTarget, verdict)
    EndIf
EndFunction

; The surface-the-failure half of variant (c). Rides the EXISTING event channel the
; model demonstrably reads and obeys (the same SkyrimNetApi.RegisterEvent path as
; baka_escalate / baka_opportunity / acheron_downed) -- no new notification plumbing.
; ROLEPLAY-FRAMED, interruption not error: the model gets a beat to play (frustration,
; a redirected threat), never an instruction. Wording is the user-approved draft text
; (batch-1 conventions). NOTE: the paired trigger YAML (baka_escalate_slipped.yaml)
; MUST stay probability: 1.0 -- a probabilistic gate on the failure cue would
; reintroduce the silent drop in the notification path (the bug being fixed, wearing
; a different hat). The retry-window-expiry condition is the cue's only gate.
Function _EscalateSlippedCue(Actor akInitiator, Actor akTarget, String why)
    If !akInitiator || !akTarget
        Return
    EndIf
    _Log("[SNBaka] EscalateRetry: slipped cue — initiator=" + akInitiator.GetDisplayName() + " target=" + akTarget.GetDisplayName() + " why=" + why)
    SkyrimNetApi.RegisterEvent("baka_escalate_slipped", \
        akInitiator.GetDisplayName() + " moves in — and the moment slips away. A heartbeat too slow, and the opening is gone; whatever " + akInitiator.GetDisplayName() + " meant to do has not happened.", \
        akInitiator, akTarget)
EndFunction

; --- In-combat "Grapple" menu dispatch ---
; Called by the DLL (MenuMode::MidCombat) when the player picks an option from the small curated
; menu shown by pressing the power on a target who's hostile and actively fighting them. Local id
; space, no relation to the normal interact menu's ids (this dispatcher never sees those). abFromHit=
; True on every branch relaxes IsEligible's attacker-in-combat gate for exactly this call (each
; *_Execute function stamps _bMidCombatGrappleActive when it sees this combination of flag + player
; initiator -- see Struggle_Execute's own comment, the pattern every one of these mirrors).
; Struggle was dropped after live feedback: too slow (5-stage PlayPairedSequence) and visually wrong
; for "defeat an aggressor to the ground" -- replaced by Subdue, which reuses the exact
; crouching-straddler/pinned-down pose _DoEscalation already uses for taking a victim to the ground,
; just made resistable.
; choice: 0 = Subdue, 1 = Choke Behind
Function _DispatchMidCombatAction(Int choice, Actor akCaster, Actor akTarget)
    _Log("[SNBaka] _DispatchMidCombatAction: choice=" + choice + " caster=" + akCaster + " target=" + akTarget)
    If !akCaster || !akTarget
        Return
    EndIf
    If choice == 0
        Subdue_Execute(akCaster, akTarget, True)
    ElseIf choice == 1
        ChokeHug_Execute(akCaster, akTarget, True)
    EndIf
EndFunction

; --- REV-72 SlaveTats set-picker dispatch ---
; Called by the DLL (SlaveTats menu mode) when the player picks a degradation set in the
; SNSlaveTats_Menu PrismaUI view. asSlot = "spank"/"defeat"/"escalation"; empty section/name
; clears the slot. Thin dispatcher only — all state lives in SNBaka_SlaveTatsModule.
Function _ST_MenuChoice(String asSlot, String asSection, String asName)
    _Log("[SNBaka] _ST_MenuChoice: slot=" + asSlot + " section=" + asSection + " name=" + asName)
    ; REV-74 Task 3 — the picker's name subfields ride here untouched (name|loc|color); the
    ; module owns the parsing. Slot "picker" routes the pick to the actor-bound picker flow
    ; (downed-menu Apply Tattoo), not the MCM set-slot flow.
    If asSlot == "picker"
        SNBaka_SlaveTatsModule.PickerChoice(asSection, asName)
    Else
        SNBaka_SlaveTatsModule.SetChoice(asSlot, asSection, asName)
    EndIf
EndFunction

; --- REV-72 SlaveTats LLM actions (external YAML: apply_tattoo / remove_tattoos) ---
; Thin executors — the module owns all state/gating. RemoveTattoos strips everything
; the MODULE applied (never Baka's own "SkyrimNet Spank" heat marks). REV-74: bookkeeping
; and the sdb_tattoo_applied/removed event fires now live INSIDE the module
; (single-entry rule — these thin calls no longer duplicate the bookkeeping here).
;
; REV-164 (Issue #3, user ruling + why-trace verdict): the LLM apply lane gains the
; DOWNED-GATE (target must be downed; the standing-NPC lane is CommandTattoo per
; REV-156 4.5), and is DECOUPLED from the MCM spank-set requirement. WHY-TRACE: the
; retired Force Tattoo tile's executor (SNBaka_SlaveTatsModule.ForcedTattoo) refuses
; [noset] when neither Defeat nor Spank set is configured (module L716-718), and this
; executor's own SpankSet read was the same configured-set coupling as a SILENT no-op —
; the invisible refuser behind the tile failures (and behind any LLM apply attempt
; with no set configured). Per the 156 spec the lane selects from the TARGET's
; available set; the spank-set requirement scopes to the spank-HOOK path only.
;
; [REV-178e] user ruling (SUPERSEDES the REV-164 configured-spank-set preference):
; the spank set is EVENT MAKEUP — the spank-hook lane's escalating redness — and an
; agent-initiated "brand them with a tattoo" resolving to a slightly-red bum is a
; narration/visual mismatch. The configured-set preference is removed outright:
; pick order is now module curated pick from the target's available packs with
; EVENT SECTIONS EXCLUDED (Baka's hardcoded "SkyrimNet Spank" + the three MCM
; degradation-set slots, CuratedLLMPick) -> reason-coded refuse [nopacks]/
; [noeligible] when nothing non-event exists.
Function ApplyTattoo_Execute(Actor akInitiator, Actor akTarget)
    _ActionLaneFire(akInitiator, akTarget, "ApplyTattoo") ; [REV-174f Leg 4.2] neutral fanned lane (LLM/player-initiated; daemon fires suppressed)
    If !akTarget || !SNBaka_SlaveTatsModule.Installed()
        Return
    EndIf
    ; REV-164 downed-gate (user ruling): the LLM apply lane requires the target
    ; to be downed.
    If !_IsDownedAny(akTarget)
        _Log("[SNBaka] ApplyTattoo REFUSE [notdowned]: " + akTarget.GetDisplayName() + " is not downed -- LLM apply lane gated (REV-164)")
        Return
    EndIf
    If _ChildBoundaryRefused(akInitiator, akTarget, "ApplyTattoo")
        Return
    EndIf
    ; [REV-178e] event-makeup exclusion (see header): pack-curated pick only.
    ; [REV-178e rider 2] body-compat (male whitelist) pre-screened in the pick.
    ; [REV-178e rider 4 / S250] SELECTION ASK (default ON): instead of picking
    ; locally, the director LLM is shown the target's real curated roster
    ; (CuratedPackText) + scene context and CHOOSES. Params are none here
    ; (llm_action). Fail paths all fail-open (ruling 1: random curated pick,
    ; never a silent no-op). OFF = the rider-2 local pick below verbatim.
    If bTattooSelectAsk
        If _TattooSelectAsk(akInitiator, akTarget, "llm_action", "", "")
            Return    ; dispatched - the callback owns apply/degrade
        EndIf
        _Log("[SNBaka] ApplyTattoo ask DISPATCH-REFUSED - fail-open degrade (ruling 1) -- REV-178e rider 4")
        _TattooAskDegrade(akTarget, "llm_action", "", "")
        Return
    EndIf
    String[] pick = SNBaka_SlaveTatsModule.CuratedLLMPick(akTarget)
    If pick.Length < 2 || pick[0] == "" || pick[1] == ""
        _Log("[SNBaka] ApplyTattoo REFUSE [nopacks/noeligible]: no usable non-event body-compatible pack entry (SkyrimNet Spank + configured degradation sets excluded) -- REV-178e")
        Return
    EndIf
    _Log("[SNBaka] ApplyTattoo APPLY (lane=llm_action, who picked: module curated pick '" + pick[1] + "' (" + pick[0] + ")) on " + akTarget.GetDisplayName() + " -- REV-178e")
    SNBaka_SlaveTatsModule.ApplyTattoo(akTarget, pick[0], pick[1], -1, True, "llm_action")
EndFunction

Function RemoveTattoos_Execute(Actor akInitiator, Actor akTarget)
    _ActionLaneFire(akInitiator, akTarget, "RemoveTattoos") ; [REV-174f Leg 4.2] neutral fanned lane (LLM/player-initiated; daemon fires suppressed)
    If !akTarget || !SNBaka_SlaveTatsModule.Installed()
        Return
    EndIf
    SNBaka_SlaveTatsModule.RemoveAllFromActor(akTarget, "llm_action")
EndFunction

; --- [REV-156 4.5] DIALOGUE-INITIATED APPLICATION (planner: "apply a
; tattoo to an NPC who you have a dominant relationship with... they
; would need to feel intimidated and/or submissive toward you") ---
; STANDING-NPC lane (NOT the downed tile — _ForcedTattoo owns downed).
; Gates, reason-coded (receipt standard 4.8): [null] / [child-boundary]
; / [downed] / [dialogue-gate-refused] — the 3.4 implementable observable:
; relationship rank toward the initiator >= 1 ("submissive toward you")
; OR Confidence AV <= 1 ("intimidated"; 0=cowardly, 1=cautious) — both
; vanilla-cheap natives (rank precedent L~2996 rank==4; AV precedent
; L~2916 Aggression read). Body-compat rides the module's ApplyTattoo
; choke point ([male-not-curated], the REV-150.1 class) — the 3.4-class
; guard. The LLM picks section/name/color from the target's available
; set (the pack cache); invalid picks fall back in-cache
; (ValidatePickCurated since REV-178e rider 2: event-makeup sections
; excluded + body-compat pre-screened at the pick). Player-initiated via
; dialogue = the player
; commands it — NOT gated by the player-target policy (the Execute
; pattern). Cue: sdb_tattoo_applied fires from the module on EVERY
; application path (the REV-82 design). Mode = "dialogue".
Function CommandTattoo_Execute(Actor akInitiator, Actor akTarget, String asSection, String asName, String asColor)
    _ActionLaneFire(akInitiator, akTarget, "CommandTattoo") ; [REV-174f Leg 4.2] neutral fanned lane (LLM/player-initiated; daemon fires suppressed)
    _Log("[SNBaka] CommandTattoo ENTER: initiator=" + akInitiator + " target=" + akTarget + " pick=" + asSection + "/" + asName + " color=" + asColor + " -- REV-156")
    If !akInitiator || !akTarget || !SNBaka_SlaveTatsModule.Installed()
        _Log("[SNBaka] CommandTattoo REFUSE [null]: null actor or SlaveTats absent -- REV-156")
        Return
    EndIf
    If _ChildBoundaryRefused(akInitiator, akTarget, "CommandTattoo")
        _Log("[SNBaka] CommandTattoo REFUSE [child-boundary] -- REV-156")
        Return
    EndIf
    If _IsDownedAny(akTarget)
        _Log("[SNBaka] CommandTattoo REFUSE [downed]: " + akTarget.GetDisplayName() + " is downed - the forced lane owns downed targets -- REV-156")
        Return
    EndIf
    Int iRank = akTarget.GetRelationshipRank(akInitiator)
    Float fConf = akTarget.GetActorValue("Confidence")
    If iRank < 1 && fConf > 1.0
        _Log("[SNBaka] CommandTattoo REFUSE [dialogue-gate-refused]: " + akTarget.GetDisplayName() + " is neither submissive toward (rank=" + iRank + ") nor intimidated by (confidence=" + fConf + ") " + akInitiator.GetDisplayName() + " -- REV-156 3.4 gate")
        Return
    EndIf
    ; [REV-178e rider 3 / S249] PLAYER-SUGGESTS PANEL ROUTE (user ruling):
    ; when the player is the initiator, the dominance gate passing = the target
    ; "agrees" (submissive or cowed) -- hand the actual design choice to the
    ; PLAYER: open the actor-bound picker (the downed-menu Apply Tattoo flow;
    ; the pick applies via PickerChoice, mode "picker"). NPC-initiated keeps
    ; the auto-apply leg. Degrade: picker unavailable -> fall through to the
    ; LLM-parameter auto-apply below.
    If akInitiator == PlayerRef && SNBaka_SlaveTatsModule.PickerAvailable()
        _Log("[SNBaka] CommandTattoo PANEL (lane=dialogue, player-initiated): dominance gate passed by " + akTarget.GetDisplayName() + " - opening actor-bound picker (player picks the design) -- REV-178e rider 3")
        SNBaka_SlaveTatsModule.OpenPickerFor(akTarget, akInitiator)
        Return
    EndIf
    ; [REV-178e rider 4 / S250] SELECTION ASK on the AUTO-APPLY leg (NPC
    ; commands a design, or player-initiated but the picker was unavailable):
    ; the action's (section, name) params become HINTS surfaced to the
    ; director ask instead of being applied directly; the director picks a
    ; real design from the target's installed curated roster. Degrades keep
    ; the rider-2 shape (ValidatePickCurated on the hints). The
    ; player-initiated PICKER route above is untouched (no LLM in that lane).
    If bTattooSelectAsk
        If _TattooSelectAsk(akInitiator, akTarget, "dialogue", asSection, asName)
            Return    ; dispatched - the callback owns apply/degrade
        EndIf
        _Log("[SNbaka] CommandTattoo ask DISPATCH-REFUSED - rider-2 degrade -- REV-178e rider 4")
        _TattooAskDegrade(akTarget, "dialogue", asSection, asName)
        Return
    EndIf
    ; [REV-178e rider 2] curated validation replaces raw ValidatePick: event
    ; sections (SkyrimNet Spank + configured degradation sets) are excluded and
    ; body-compat is pre-screened (curate-before-pick; the choke point remains).
    String[] pick = SNBaka_SlaveTatsModule.ValidatePickCurated(akTarget, asSection, asName)
    If pick.Length < 2 || pick[0] == "" || pick[1] == ""
        _Log("[SNBaka] CommandTattoo REFUSE [nopacks/noeligible]: no usable non-event body-compatible pack entry -- REV-178e")
        Return
    EndIf
    Int iColor = -1
    If asColor != ""
        iColor = SNBaka_SlaveTatsModule._HexToInt(asColor)
    EndIf
    _Log("[SNBaka] CommandTattoo APPLY (lane=dialogue, who picked: LLM pick " + asSection + "/" + asName + " color=" + asColor + " -> resolved '" + pick[1] + "' (" + pick[0] + ") on " + akTarget.GetDisplayName() + ") -- REV-156")
    SNBaka_SlaveTatsModule.ApplyTattoo(akTarget, pick[0], pick[1], iColor, True, "dialogue")
EndFunction

; --- [REV-156 4.6] NPC-ON-PLAYER APPLICATION (the planner ownership/
; humiliation row: "if the NPC feels like humiliating or marking
; ownership of the player") ---
; Target = the PLAYER, always. The central player-target policy IS the
; gate (blanket MCM, DEFAULT OFF — site "MarkPlayer"; the consumer list
; extended per the 3.5 pre-check). Child boundary N/A on the player
; target (kept belt-and-braces on the initiator). Body-compat rides the
; ApplyTattoo choke point (the 3.4-class guard). The LLM picks
; location/color/name filtered by ITS arousal/mood/character — the
; selection guidance rides the action yaml description (register entry
; 35 DRAFT); the executor validates the pick in-cache. Cue:
; sdb_tattoo_applied fires ON THE PLAYER from the module (witness
; reactions already key on the wearer's state). Mode = "ownership".
Function MarkPlayer_Execute(Actor akInitiator, String asSection, String asName, String asColor)
    _Log("[SNBaka] MarkPlayer ENTER: initiator=" + akInitiator + " pick=" + asSection + "/" + asName + " color=" + asColor + " -- REV-156")
    If !akInitiator || !SNBaka_SlaveTatsModule.Installed()
        _Log("[SNBaka] MarkPlayer REFUSE [null]: null initiator or SlaveTats absent -- REV-156")
        Return
    EndIf
    If !PlayerRef
        _Log("[SNBaka] MarkPlayer REFUSE [null]: PlayerRef unset -- REV-156")
        Return
    EndIf
    If _ChildBoundaryRefused(akInitiator, PlayerRef, "MarkPlayer")
        _Log("[SNBaka] MarkPlayer REFUSE [child-boundary] -- REV-156")
        Return
    EndIf
    If !_TargetSexAllowed(PlayerRef)
        _Log("[SNBaka] MarkPlayer REFUSE [target-sex-refused] (level L" + _TargetSexLevel() + ") -- REV-156")
        Return
    EndIf
    If !_PlayerTargetAdmitted(akInitiator, PlayerRef, "MarkPlayer")
        _Log("[SNBaka] MarkPlayer REFUSE [policy-refused]: central player-target policy OFF (the L~1452 daemon precedent class) -- REV-156")
        Return
    EndIf
    ; [REV-178e rider 4 / S250] SELECTION ASK on the ownership lane: the
    ; NPC's (section, name) params become HINTS to the director ask; the
    ; director picks a real design from the player's installed curated roster
    ; (event-makeup + body-compat excluded by the packList builder). Degrade
    ; = rider-2 ValidatePickCurated on the hints. OFF = rider-2 below verbatim.
    If bTattooSelectAsk
        If _TattooSelectAsk(akInitiator, PlayerRef, "ownership", asSection, asName)
            Return    ; dispatched - the callback owns apply/degrade
        EndIf
        _Log("[SNbaka] MarkPlayer ask DISPATCH-REFUSED - rider-2 degrade -- REV-178e rider 4")
        _TattooAskDegrade(PlayerRef, "ownership", asSection, asName)
        Return
    EndIf
    ; [REV-178e rider 2] curated validation replaces raw ValidatePick: event
    ; sections excluded + body-compat pre-screened (curate-before-pick).
    String[] pick = SNBaka_SlaveTatsModule.ValidatePickCurated(PlayerRef, asSection, asName)
    If pick.Length < 2 || pick[0] == "" || pick[1] == ""
        _Log("[SNBaka] MarkPlayer REFUSE [nopacks/noeligible]: no usable non-event body-compatible pack entry -- REV-178e")
        Return
    EndIf
    Int iColor = -1
    If asColor != ""
        iColor = SNBaka_SlaveTatsModule._HexToInt(asColor)
    EndIf
    _Log("[SNBaka] MarkPlayer APPLY (lane=ownership, who picked: NPC LLM pick " + asSection + "/" + asName + " color=" + asColor + " -> resolved '" + pick[1] + "' (" + pick[0] + ") on the player) -- REV-156")
    SNBaka_SlaveTatsModule.ApplyTattoo(PlayerRef, pick[0], pick[1], iColor, True, "ownership")
EndFunction

; --- [REV-178e rider 4 / S250] THE TATTOO SELECTION ASK ---------------------
; One SendCustomPromptToLLM round-trip (the snbaka_escalation_gate precedent,
; ~L12900; the muse two-stage precedent ~L2728): the director LLM sees the
; scene (Situation + recent events) + the target's REAL curated roster
; (CuratedPackText: names-only compact, rider-2 curation rides in) and picks
; the design. The answer is STILL LLM output: ValidatePickCurated re-checks
; it in-cache (the belt stays), the moment is re-checked in the callback
; (dead/downed-change/lock - the gate precedent), and every fail path
; degrades per-lane instead of refusing (rulings 1/3/4). Color is NEVER the
; LLM's: applies on these lanes are the BLACK constant 0x000000 (ruling 3).
; One pending slot, 30s expiry, duplicates degrade immediately.
; ----------------------------------------------------------------------------

; Per-lane degrade (ruling 1: llm_action FAILS OPEN RANDOM via CuratedLLMPick;
; dialogue/ownership keep the rider-2 named-hint shape via ValidatePickCurated;
; [nopacks]/[noeligible] still refuses - nothing installed IS nothing).
Function _TattooAskDegrade(Actor akTarget, String asLane, String asHintSection, String asHintName)
    String[] pick
    If asLane == "llm_action"
        pick = SNBaka_SlaveTatsModule.CuratedLLMPick(akTarget)
    Else
        pick = SNBaka_SlaveTatsModule.ValidatePickCurated(akTarget, asHintSection, asHintName)
    EndIf
    If pick.Length < 2 || pick[0] == "" || pick[1] == ""
        _Log("[SNbaka] tattoo-select degrade REFUSE [nopacks/noeligible] (lane=" + asLane + ") -- REV-178e rider 4")
        Return
    EndIf
    _Log("[SNbaka] tattoo-select DEGRADE APPLY (lane=" + asLane + ", who picked: fallback '" + pick[1] + "' (" + pick[0] + "), color=black 0x000000) on " + akTarget.GetDisplayName() + " -- REV-178e rider 4")
    SNBaka_SlaveTatsModule.ApplyTattoo(akTarget, pick[0], pick[1], 0x000000, True, asLane)
EndFunction

; Dispatch. Returns True when the ask is in flight (caller Returns; the
; callback owns the lane); False when it could not be sent (caller degrades
; inline). Duplicates (pending slot live) degrade the NEW lane immediately -
; no queueing (the gate precedent).
Bool Function _TattooSelectAsk(Actor akInitiator, Actor akTarget, String asLane, String asHintSection, String asHintName)
    If !akTarget
        Return False
    EndIf
    Float now = Utility.GetCurrentRealTime()
    If _bTattooAskPending && (now - _fTattooAskSentRT) < 30.0
        _Log("[SNbaka] tattoo-select ask already PENDING (lane=" + _sTattooAskLane + ") - duplicate lane=" + asLane + " degrades immediately -- REV-178e rider 4")
        Return False
    EndIf
    _bTattooAskPending = False    ; stale slot (>=30s, callback lost): reclaim
    String sWhy = "forced onto a downed, helpless character"
    If asLane == "dialogue"
        sWhy = "commanded in conversation on a submissive or cowed character"
    ElseIf asLane == "ownership"
        sWhy = "an NPC asserting ownership by marking the player"
    EndIf
    String sHint = "none"
    If asHintSection != ""
        sHint = asHintSection + " / " + asHintName
    EndIf
    String sSex = "female"
    If akTarget.GetActorBase().GetSex() == 0
        sSex = "male"
    EndIf
    String sWear = SNBaka_SlaveTatsModule.CuratedAppliedText(akTarget)
    If sWear == ""
        sWear = "nothing (this module)"
    EndIf
    String sPack = SNBaka_SlaveTatsModule.CuratedPackText(akTarget)
    If sPack == ""
        _Log("[SNbaka] tattoo-select ask REFUSED [nopacks]: CuratedPackText empty - nothing to show the director -- REV-178e rider 4")
        Return False
    EndIf
    String ctx = "{\"initiatorName\":\"" + akInitiator.GetDisplayName() + "\",\"targetName\":\"" + akTarget.GetDisplayName() + "\",\"targetSex\":\"" + sSex + "\",\"why\":\"" + sWhy + "\",\"hint\":\"" + sHint + "\",\"currentlyWearing\":\"" + sWear + "\",\"packList\":\"" + sPack + "\",\"maxRecentEvents\":20}"
    _JsonLintOK(ctx, "_TattooSelectAsk ctx")
    _bTattooAskPending = True
    _fTattooAskSentRT = now
    _akTattooAskInitiator = akInitiator
    _akTattooAskTarget = akTarget
    _sTattooAskLane = asLane
    _sTattooAskHintSection = asHintSection
    _sTattooAskHintName = asHintName
    Int sent = SkyrimNetApi.SendCustomPromptToLLM("snbaka_tattoo_select", "", ctx, Self as Quest, "SkyrimNet_BakaIntegration", "OnTattooSelectResponse")
    _Log("[SNbaka] tattoo-select ASK SENT (lane=" + asLane + ", target=" + akTarget.GetDisplayName() + ", hint=" + sHint + ", packLen=" + StringUtil.GetLength(sPack) + ", sent=" + sent + ") -- REV-178e rider 4")
    If sent != 1
        _bTattooAskPending = False
        _akTattooAskInitiator = None
        _akTattooAskTarget = None
        _sTattooAskLane = ""
        Return False
    EndIf
    Return True
EndFunction

; Trim ASCII spaces from both ends (the answer-parse helper).
String Function _TrimSP(String asS)
    Int a = 0
    Int b = StringUtil.GetLength(asS) - 1
    While a <= b && StringUtil.GetNthChar(asS, a) == " "
        a += 1
    EndWhile
    While b >= a && StringUtil.GetNthChar(asS, b) == " "
        b -= 1
    EndWhile
    If b < a
        Return ""
    EndIf
    Return StringUtil.Substring(asS, a, b - a + 1)
EndFunction

; The callback (the escalation-gate OnEscalationGateResponse shape). Parses
; "SECTION | NAME" / "NONE", re-validates via ValidatePickCurated (the belt
; stays), moment-rechecks, applies BLACK (ruling 3). Every fail path
; degrades per-lane; a junk-bearing name simply misses the cache and takes
; ValidatePickCurated's in-section wearable degrade (never a silent no-op).
Function OnTattooSelectResponse(String response, Int success)
    Actor akTarget = _akTattooAskTarget
    String sLane = _sTattooAskLane
    String sHintS = _sTattooAskHintSection
    String sHintN = _sTattooAskHintName
    _bTattooAskPending = False
    _fTattooAskSentRT = 0.0
    _akTattooAskInitiator = None
    _akTattooAskTarget = None
    _sTattooAskLane = ""
    _sTattooAskHintSection = ""
    _sTattooAskHintName = ""
    If !akTarget
        _Log("[SNbaka] tattoo-select callback DROP: no stashed target -- REV-178e rider 4")
        Return
    EndIf
    ; MOMENT-RECHECK (the gate precedent): the answer took real seconds.
    If akTarget.IsDead()
        _Log("[SNbaka] tattoo-select callback DROP [dead]: " + akTarget.GetDisplayName() + " -- REV-178e rider 4")
        Return
    EndIf
    If IsActorLocked(akTarget)
        _Log("[SNbaka] tattoo-select callback DROP [locked]: " + akTarget.GetDisplayName() + " -- REV-178e rider 4")
        Return
    EndIf
    If sLane == "llm_action" && !_IsDownedAny(akTarget)
        _Log("[SNbaka] tattoo-select callback DROP [notdowned]: " + akTarget.GetDisplayName() + " recovered while the ask was in flight -- REV-178e rider 4")
        Return
    EndIf
    If success == 1 && StringUtil.Find(response, "NONE") < 0
        Int sep = StringUtil.Find(response, "|")
        If sep > 0
            String sSec = _TrimSP(StringUtil.Substring(response, 0, sep))
            String sName = _TrimSP(StringUtil.Substring(response, sep + 1, StringUtil.GetLength(response) - sep - 1))
            If sSec != "" && sName != ""
                String[] pick = SNBaka_SlaveTatsModule.ValidatePickCurated(akTarget, sSec, sName)
                If pick.Length >= 2 && pick[0] != "" && pick[1] != ""
                    _Log("[SNbaka] tattoo-select APPLY (lane=" + sLane + ", who picked: director '" + sName + "' (" + sSec + ") -> resolved '" + pick[1] + "' (" + pick[0] + "), color=black 0x000000) on " + akTarget.GetDisplayName() + " -- REV-178e rider 4")
                    SNBaka_SlaveTatsModule.ApplyTattoo(akTarget, pick[0], pick[1], 0x000000, True, sLane)
                    Return
                EndIf
            EndIf
        EndIf
    EndIf
    _Log("[SNbaka] tattoo-select callback UNUSABLE (success=" + success + ", answer='" + response + "') - per-lane degrade -- REV-178e rider 4")
    _TattooAskDegrade(akTarget, sLane, sHintS, sHintN)
EndFunction

; --- Downed-victim menu dispatch ---
; [REV-144 Strip] ============================================================
; The Strip action (baka-module.md REV-134e spec; rulings (i)(a) own-inventory,
; (ii)(b) stays-off + "All to Dress" restore tile, (iii) SexLab-primary undress,
; all ruled REV-136). Gear is NEVER removed from the actor: SexLab StripActor
; keeps it in the victim's own inventory (tracked re-equip context); the vanilla
; fallback unequips per worn slot (inventory stays theirs either way). OUR OWN
; queue (StorageUtil FormList "SNBaka.StripQueue" keyed on the victim) is the
; ONLY thing the restore tile touches -- it never equips anything we did not
; take off ourselves, so SeverActions' outfit lock / re-dress can't be fought:
; when SeverActions holds a lock on the victim (SeverOutfit_LockActive) our
; restore STAYS OUT entirely and says why (reason-coded). SeverActions itself
; treats a full lock-strip as a bulk event and yields (SA SeverActions_Outfit.psc
; L1462-1479 "Bulk strip detected... Yielding"), so the strip side coexists too.
; Player-clicked, UNGATED (player-initiated, the Execute pattern); the downed
; gate in _DispatchDownedAction is the only day-one gate.
; ============================================================================

; --- [REV-150 4.3] Forced-tattoo action (slavetats.md REV-134e 6.3) ---------
; Downed-menu tile (choice 12, beside Strip 10 / Allow to Dress 11) + the
; gated AI-aggressor daemon lane. The cue is CUE-ONLY (the REV-134d anatomy:
; RegisterEvent desc only, NO response.content YAML) with register entry
; 28's USER-APPROVED wording of record, actor names interpolated at fire
; time (the D8/137 lesson). Body-compatibility gate = REV-150.1 FLIP of the
; 3.4 verdict: male-class victims no longer refuse-all; they ride the
; module's curation screen (pack sections carry NO body/race metadata -
; probed read-only, anal.json + Femboy.json field sets cited - so the
; whitelist is wording-based: Gay - */Femboy sections auto-whitelist,
; everything else passes the female-anatomy keyword denylist).
; Composes with Strip: post-strip skin is the exposed canvas.

Function _ForcedTattoo_Execute(Actor akCaster, Actor akVictim)
    _ActionLaneFire(akCaster, akVictim, "ForcedTattoo") ; [REV-174f Leg 4.2] neutral fanned lane (LLM/player-initiated; daemon fires suppressed)
    _Log("[SNBaka] ForcedTattoo: caster=" + akCaster + " victim=" + akVictim)
    If !akCaster || !akVictim
        _Log("[SNBaka] ForcedTattoo REFUSE [null]: null actor leg")
        Return
    EndIf
    ; Child boundary (the REV-146a Task 2 class - gates every module action).
    If _ChildBoundaryRefused(akCaster, akVictim, "ForcedTattoo")
        Return
    EndIf
    ; Body-compatibility gate — REV-150.1 FLIP: the [malebody] refuse-all
    ; (REV-150 3.4 verdict) is RETIRED. Male-class victims now ride the
    ; module's curation screen (Gay - */Femboy auto-whitelist + the
    ; female-anatomy keyword denylist on section+name), applied at the
    ; ApplyTattoo choke point for EVERY module avenue. The service layer
    ; falls a non-curated configured set back to a curated pick, and
    ; refuses [male-none-curated] when nothing curated is installed.
    If !HasFemaleBody(akVictim)
        _Log("[SNBaka] ForcedTattoo: male-class victim " + akVictim.GetDisplayName() + " - proceeding via the REV-150.1 curated whitelist (module gates/refuses at apply)")
    EndIf
    ; Downed re-check: the daemon lane arrives here WITHOUT the dispatch's
    ; downed gate, so the executor enforces its own (the Execute recheck
    ; precedent); the player tile already passed the dispatch's gate.
    If !_IsDownedAny(akVictim)
        _Log("[SNBaka] ForcedTattoo REFUSE [notdowned]: " + akVictim.GetDisplayName() + " is not downed (executor recheck)")
        Return
    EndIf
    If SNBaka_SlaveTatsModule.ForcedTattoo(akCaster, akVictim)
        ; Register entry 28 wording of record (USER-APPROVED 2026-10-22,
        ; REV-136 instruction set 4.4; registered REV-134e; slavetats.md
        ; REV-136 subsection holds the verbatim text), names interpolated:
        SkyrimNetApi.RegisterEvent("sdb_forced_tattoo", \
            akCaster.GetDisplayName() + " forces a tattoo onto the downed " + akVictim.GetDisplayName() + ", marking their skin where everyone can see.", \
            akCaster, akVictim)
        _Log("[SNBaka] ForcedTattoo: APPLIED -> sdb_forced_tattoo cue fired (entry-28 wording of record)")
    Else
        _Log("[SNBaka] ForcedTattoo: service refused (reason-coded trace above)")
    EndIf
EndFunction

; [REV-150 4.3] The Execute-gate 3-level MCM consent class as the ruling
; template for AI-AGGRESSOR forced-inking (SNBaka.ForcedTattooGateLevel,
; player-keyed, default 0):
;   0 = Unlimited - every daemon fire proceeds.
;   1 = Companions-only (the "Companions ask" class): non-companion fires
;       refused; companion fires PROCEED without the popup (the ask-tier
;       needs a DLL confirm-mode - the JS/CSS-only stop condition; interim
;       lenient reading FLAGGED here + at the gate report).
;   2 = Always-refuse (the "Always ask" class): ALL daemon fires refused.
; The player's own downed-menu tile NEVER passes through this gate.
; Refusals are §5 trace sentinels only - refusal NARRATION would be new
; section-7 text (STOP condition: new cue wording = register draft).
Bool Function _ForcedTattooGateCheck(Actor akInitiator, Actor akTarget)
    Int level = StorageUtil.GetIntValue(PlayerRef, "SNBaka.ForcedTattooGateLevel", 0)
    If level <= 0
        Return True
    EndIf
    If level >= 2
        _Log("[SNBaka] ForcedTattoo gate REFUSE [alwayson]: level 2 - AI forced-inking refused (" + akInitiator.GetDisplayName() + " -> " + akTarget.GetDisplayName() + ")")
        Return False
    EndIf
    If !_ExecuteIsCompanion(akInitiator)
        _Log("[SNBaka] ForcedTattoo gate REFUSE [noncompanion]: level 1 - non-companion AI fire refused (" + akInitiator.GetDisplayName() + " -> " + akTarget.GetDisplayName() + ")")
        Return False
    EndIf
    _Log("[SNBaka] ForcedTattoo gate: level 1 companion fire PROCEEDS without popup (ask-tier = DLL surface, surfaced gap - REV-150)")
    Return True
EndFunction

Function _Strip_Execute(Actor akCaster, Actor akVictim)
    _ActionLaneFire(akCaster, akVictim, "Strip") ; [REV-174f Leg 4.2] neutral fanned lane (LLM/player-initiated; daemon fires suppressed)
    _Log("[SNBaka] Strip: caster=" + akCaster + " victim=" + akVictim)
    If !akCaster || !akVictim
        _Log("[SNBaka] Strip REFUSE [null]: null actor leg")
        Return
    EndIf
    ; REV-146a Task 2: child boundary (engine-true IsChild) - no module action.
    If _ChildBoundaryRefused(akCaster, akVictim, "Strip")
        Return
    EndIf
    If StorageUtil.FormListCount(akVictim, "SNBaka.StripQueue") > 0
        _Log("[SNBaka] Strip REFUSE [already]: " + akVictim.GetDisplayName() + " already stripped by us - Allow to Dress first")
        _Notify(akVictim.GetDisplayName() + " is already stripped - use Allow to Dress first.")
        Return
    EndIf
    Int nTaken = 0
    If SkyrimNet_BakaSL.Installed()
        ; (iii) PRIMARY: SexLab StripActor -- tracked re-equip context, worn-slot
        ; aware, animate. Gear lands in the victim's OWN inventory (ruling (i)(a)).
        Form[] akStripped = SkyrimNet_BakaSL.StripActor(akVictim, True)
        Int i = 0
        While akStripped && i < akStripped.Length
            If akStripped[i]
                StorageUtil.FormListAdd(akVictim, "SNBaka.StripQueue", akStripped[i], False)
                nTaken += 1
            EndIf
            i += 1
        EndWhile
        _Log("[SNBaka] Strip: SexLab StripActor took " + nTaken + " item(s)")
    Else
        ; (iii) FALLBACK (presence-gated, honest degradation): vanilla per-slot
        ; unequip over the 32 armor slots (30-61). NO SexLab re-equip context --
        ; restore is our own FormList queue only. Weapons untouched (no SexLab).
        Int k = 0
        While k < 32
            Int iMask = Math.LeftShift(1, k)
            Form akWorn = akVictim.GetWornForm(iMask)
            If akWorn
                StorageUtil.FormListAdd(akVictim, "SNBaka.StripQueue", akWorn, False)
                akVictim.UnequipItem(akWorn)
                nTaken += 1
            EndIf
            k += 1
        EndWhile
        _Log("[SNBaka] Strip: vanilla fallback unequip took " + nTaken + " item(s) (no SexLab restore context)")
    EndIf
    If nTaken == 0
        _Log("[SNBaka] Strip REFUSE [bare]: " + akVictim.GetDisplayName() + " has nothing strippable")
        _Notify(akVictim.GetDisplayName() + " has nothing left to strip.")
        Return
    EndIf
    ; (ii)(b): restore stays OFF here -- nothing re-equips until the All to Dress
    ; tile (id 11) is clicked. Cue-only event per the REV-134d applied pattern
    ; (RegisterEvent desc only, NO response.content yaml); entry-27 wording of
    ; record, actor names interpolated at fire time (D8/137 lesson).
    String sDesc = akCaster.GetDisplayName() + " strips the downed " + akVictim.GetDisplayName() + " of their clothes and armor, leaving them exposed and helpless on the ground."
    SkyrimNetApi.RegisterEvent("sdb_stripped", sDesc, akCaster, akVictim)
    _Log("[SNBaka] Strip: APPLIED " + nTaken + " item(s) -> sdb_stripped cue fired")
    ; REV-146a Task 9.3: the RE-EQUIP BLOCK WINDOW (the 9.1 verdict: the re-equip
    ; is engine-side AI outfit re-evaluation, traceless in Papyrus/native logs).
    ; Keyed to OUR tracked queue: every 0.5s (the OnUpdate multiplexer; REV-162
    ; ruling 4.1-b) the watch
    ; re-unequips any queued item the engine put back on, sentinel'd, until the
    ; queue is cleared by Allow to Dress (id 11) or the victim's down-window
    ; ends. SeverActions' lock semantics are respected READ-ONLY (a locked
    ; victim is skipped entirely - their system owns re-dress).
    _bStripHoldActive = True
    _ArmRealtimeTimer()
    _Log("[SNBaka] strip-hold armed: " + akVictim.GetDisplayName() + " (re-equip block window, queue=" + nTaken + "; 0.5s watch since REV-162 4.1-b) -- REV-146a")
EndFunction

; REV-146a Task 9 - THE STRIP RE-EQUIP BLOCK WATCH (multiplexer leg, 0.5s cadence since REV-162 4.1-b).
; 9.1 VERDICT (dogfood Papyrus.0.log 10-23 13:22:51-55, Vorstag): our Strip
; fired at 13:22:51-52 (SexLab StripActorImpl took 3 items); NO Papyrus or DLL
; line re-equipped the items (Papyrus.0.log lines 6364-6534 hold zero equip
; traces; SeverActionsNative.log empty for the window) - the re-equip is
; ENGINE-SIDE AI outfit re-evaluation, the same force the ecosystem defends
; against (9.2 study): SexLab keeps actors stripped by holding the stripped
; set inside the scene thread's lifecycle (sslActorLibrary.psc L125-128 +
; UnstripActor L144-156; restore happens when the THREAD ends, never before);
; SeverActions yields to bulk strips under its lock (SA SeverActions_Outfit.psc
; L1462-1479) and owns re-dress while SeverOutfit_LockActive=1; Devious
; Devices slot-locks keep devices on by re-locking slots on every removal
; attempt. OUR mechanism (the queue-keyed block window): while our tracked
; SNBaka.StripQueue on a victim is non-empty, any engine re-equip of a QUEUED
; item is reverted (unequipped again) with a receipt sentinel - the same
; keep-stripped guarantee, held by OUR queue instead of a scene thread.
; SeverActions victims are SKIPPED entirely (their lock, their rules - the
; 6.0 pre-check, read-only). The watch disarms itself when no queues remain.
Bool _bStripHoldActive = False   ; REV-146a Task 9: at least one tracked strip queue exists
Function _StripHoldWatch()
    Actor[] akHeld = PO3_SKSEFunctions.GetActorsByProcessingLevel(0)
    Int i = 0
    Int nHeld = 0
    While i < akHeld.Length
        Actor akV = akHeld[i]
        If akV && akV != PlayerRef && StorageUtil.FormListCount(akV, "SNBaka.StripQueue") > 0
            If StorageUtil.GetIntValue(akV, "SeverOutfit_LockActive", 0) == 1
                ; their lock, their rules - never fight a SeverActions lock
            Else
                Form[] akQ = StorageUtil.FormListToArray(akV, "SNBaka.StripQueue")
                Int q = 0
                While q < akQ.Length
                    If akQ[q] && akV.IsEquipped(akQ[q])
                        akV.UnequipItem(akQ[q])
                        _Log("[SNBaka] strip-hold re-unequip: " + akV.GetDisplayName() + " re-equipped " + akQ[q].GetName() + " (engine re-equip reverted, queue held) -- REV-146a")
                    EndIf
                    q += 1
                EndWhile
                nHeld += 1
            EndIf
        EndIf
        i += 1
    EndWhile
    If nHeld == 0 && _bStripHoldActive
        _bStripHoldActive = False
        _Log("[SNBaka] strip-hold disarmed: no tracked strip queues remain -- REV-146a")
    EndIf
EndFunction

; Called by the DLL (SNBaka_MenuChoice "downed" mode) when the player picks an option from
; the menu shown by pressing the power on a downed victim. Runs on its own stack; the actual
; work for Investigate/Inspect/Stand Back is handed to the running _DefeatGroundWindow loop
; via flags so the victim stays owned by one place. choice:
;   0 = Escalate (straight to the choke/sex escalation, as before)
;   1 = Investigate    2 = Inspect (play the anim through, no QTE, then re-down + reset timer)
;   3 = Stand Back     (exit the window: stagger -> stand up -> regain control)
;  <0 = cancel (victim stays downed; window keeps running)
Function _DispatchDownedAction(Int choice, Actor akCaster, Actor akVictim)
    _Log("[SNBaka] _DispatchDownedAction: choice=" + choice + " caster=" + akCaster + " victim=" + akVictim)
    If !akCaster || !akVictim
        Return
    EndIf
    ; REV-146a Task 2: child boundary gates EVERY downed-menu dispatch (all
    ; tiles: Down-tab, Strip/restore, and the +100 paired tabs).
    If _ChildBoundaryRefused(akCaster, akVictim, "DownedDispatch")
        Return
    EndIf
    ; REV-146a 4.2: Prisma mode buttons (numeric ids 900/901) arrive on the
    ; downed dispatcher too -- handle them BEFORE the +100 paired-tab reroute
    ; (900-100=800 would otherwise collide in the interact dispatcher).
    If choice == 900
        _MephalaToggle()
        Return
    ElseIf choice == 901
        _MolagBalToggle()
        Return
    EndIf
    ; MERGED MENU: the downed-victim panel now also shows every regular paired-animation tab
    ; alongside the Down-only actions (see PrismaUI's snbaka_open_downed) -- "from any downed actor
    ; we can do any action." Those regular picks arrive offset by +100 so they can never collide
    ; with the Down tab's own 0-7 ids; route them straight to the normal interact dispatcher and
    ; skip all the ground-window bookkeeping below entirely (that's Down-tab-only territory). No
    ; extra eligibility gate needed here -- LockBoth's own ground-window-owner carve-out already
    ; lets this same aggressor act on their own downed/pinned victim.
    If choice >= 100
        _DispatchInteractActionWithActors(choice - 100, akCaster, akVictim)
        Return
    EndIf
    Bool ours = StorageUtil.GetIntValue(akVictim, "SNBaka.OnGround", 0) == 1
    Bool external = !ours && _IsDownedAny(akVictim)
    If !ours && !external && akVictim.IsBleedingOut()
        ; The power's menu opens on native BLEEDOUT, but the Acheron defeat + our adoption net lag it
        ; by several seconds (confirmed live: HelpUp dispatched at 11:13:09 was ignored as "no longer
        ; downed" while the bridge only adopted the defeat at 11:13:14 — the player's help did nothing).
        ; Bridge that gap: the player is pointing at someone visibly on the ground, so wait for the
        ; down state to actually land before judging whether they're downed.
        Float settle = 0.0
        While settle < 8.0 && !_IsDownedAny(akVictim) && akVictim.IsBleedingOut() && !akVictim.IsDead()
            Utility.Wait(0.5)
            settle += 0.5
        EndWhile
        ours = StorageUtil.GetIntValue(akVictim, "SNBaka.OnGround", 0) == 1
        external = !ours && _IsDownedAny(akVictim)
        _Log("[SNBaka] _DispatchDownedAction: bleedout settle wait " + settle + "s -> ours=" + ours + " external=" + external)
    EndIf
    If !ours && !external
        If choice == 4
            ; HelpUp owns its own settle logic (mid-pin lock gap, late-landing bleedout) and re-checks
            ; everything itself — let it decide instead of silently eating the player's click here.
            HelpUp_Execute(akCaster, akVictim)
            Return
        EndIf
        _Log("[SNBaka] _DispatchDownedAction: victim no longer downed — ignoring")
        Return
    EndIf
    If choice == 5
        ; EXECUTE — a deliberate killing blow on the downed victim, the guaranteed alternative to the
        ; hit-based execution (which depends on hit events surviving Acheron's hooks). Same rules:
        ; essential/protected actors survive Actor.Kill; our claim is released first so nothing
        ; fights the corpse. Never the player (their defeat IS the death alternative).
        If akVictim == PlayerRef || akVictim.IsDead()
            Return
        EndIf
        ; REV-100 fix (a): SCENE-ACTIVE GUARD at the convergence point — choice-5 serves BOTH
        ; the LLM lane (Execute_Execute delegates here) and the player's own downed-menu click,
        ; so the REV-99 hazard is guarded here too, not just upstream. Same one-refusal-semantics
        ; check as Execute_Execute: either actor mid SexLab/OStim scene refuses the kill.
        If IsInSexAnimation(akCaster) || IsInSexAnimation(akVictim)
            _Log("[SNBakaEXEC] Execute refused: scene active — " + akCaster.GetDisplayName() + " / " + akVictim.GetDisplayName() + " mid SexLab/OStim scene (choice-5 convergence guard)")
            _ExecuteSceneRefuse(akCaster, akVictim)
            Return
        EndIf
        _Log("[SNBaka] _DispatchDownedAction: EXECUTE — " + akCaster.GetDisplayName() + " finishes " + akVictim.GetDisplayName())
        ; Visual cue: the executor swings their equipped weapon at the body before it dies —
        ; attackStart drives a real attack animation for player and NPC alike; if the graph
        ; rejects it in some stance, the kill still lands, just without the flourish.
        Debug.SendAnimationEvent(akCaster, "attackStart")
        Utility.Wait(0.6)
        ; REV-100 fix (b): KILL-TIME RECHECK — the 0.6s flourish wait above is a real race
        ; window (the REV-99 incident chain: fire -> flourish -> state changed underneath).
        ; Rev-20 recheck precedent, extended: re-validate BOTH actor refs and every state
        ; assumption IMMEDIATELY before Actor.Kill. Each refusal reason gets its own §5
        ; sentinel; the success narration is registered only AFTER the recheck passes so
        ; a refused kill never narrates as landed.
        If !akCaster || !akVictim
            _Log("[SNBakaEXEC] Execute refused: kill-time recheck — actor reference lost (initiator or target invalid)")
            Return
        EndIf
        If akVictim == PlayerRef
            _Log("[SNBakaEXEC] Execute refused: kill-time recheck — target is the player")
            Return
        EndIf
        If akVictim.IsDead()
            _Log("[SNBakaEXEC] Execute refused: kill-time recheck — target already dead")
            Return
        EndIf
        If IsInSexAnimation(akCaster) || IsInSexAnimation(akVictim)
            _Log("[SNBakaEXEC] Execute refused: kill-time recheck — scene went active during the flourish window (refused: scene active)")
            _ExecuteSceneRefuse(akCaster, akVictim)
            Return
        EndIf
        If !_IsDownedAny(akVictim)
            _Log("[SNBakaEXEC] Execute refused: kill-time recheck — target no longer downed")
            _ExecuteGateRefuse(akCaster, akVictim, "the moment passed - the victim is no longer helpless")
            Return
        EndIf
        ; [REV-177b item 8 / R-177c] self-variant narration: a self-execution reads
        ; "takes their own life rather than be taken" (defeat over capture), not
        ; "finishes the helpless X" (which would require a second actor).
        If akCaster == akVictim
            SkyrimNetApi.RegisterEvent("baka_execution", \
                akVictim.GetDisplayName() + " takes their own life rather than be taken.", \
                akCaster, akVictim)
        Else
            SkyrimNetApi.RegisterEvent("baka_execution", \
                akCaster.GetDisplayName() + " finishes the helpless " + akVictim.GetDisplayName() + " with a deliberate killing blow.", \
                akCaster, akVictim)
        EndIf
        StorageUtil.SetIntValue(akVictim, "SNAcheron.Held", 0)
        StorageUtil.SetIntValue(akVictim, "SNBaka.OnGround", 0)
        ; [REV-161 fix 2.1] Post-execution lock release: a downed victim stays
        ; SNBaka.Locked=1 for the entire ground window (SNBakaInteractEffect
        ; exception). The kill closes that window for good, but the lock was
        ; never cleared here -- it lingered on the corpse and, worse, survived
        ; essential-blocked kills (Actor.Kill refused, victim alive but locked
        ; with no ground window left to clear it), leaving the downed panel
        ; dead until the power was re-toggled. Clear it with the rest of the
        ; window state, unconditionally, dead or alive.
        StorageUtil.SetIntValue(akVictim, "SNBaka.Locked", 0)
        akVictim.Kill(akCaster)
        Utility.Wait(0.5)
        _Log("[SNBaka] _DispatchDownedAction: post-execute IsDead=" + akVictim.IsDead() + " (False = an essential flag blocked it)")
        Return
    ElseIf choice == 6
        TieUp_Execute(akCaster, akVictim)
        Return
    ElseIf choice == 7
        Untie_Execute(akCaster, akVictim)
        Return
    ElseIf choice == 8
        ; REV-74 rider 1 — "Apply Tattoo" button on the downed menu. Unconditional affordance
        ; (ruling ②B, recorded as ARCHITECTURE): the DLL-built button list is host surface and
        ; stays module-ignorant; absence-handling is the SERVICE's job. The call below is a pure
        ; service delegation — zero tattoo logic lives in this quest (presence-gated via the
        ; service registry; the module no-ops gracefully when SlaveTats itself is absent).
        SNBaka_SlaveTatsModule.OpenPickerFor(akVictim, akCaster)
        Return
    ElseIf choice == 9
        ; REV-74 rider 1 — "Remove Tattoos" on the downed menu, same service-delegation contract.
        SNBaka_SlaveTatsModule.RemoveAllFromActor(akVictim, "downedmenu")
        Return
    ElseIf choice == 10
        ; [REV-144 Strip] Down-tab "Strip" tile (baka-module.md REV-134e + REV-136 rulings
        ; (i)(a)/(ii)(b)/(iii)). Player-clicked, UNGATED (player-initiated, the Execute pattern):
        ; the downed-gate above is the only day-one gate. Runs for BOTH ours/external lanes
        ; (top-level Return, same shape as choices 6-9).
        _Strip_Execute(akCaster, akVictim)
        Return
    ElseIf choice == 11
        ; [REV-144 Strip] "All to Dress" restore tile (ruling (ii)(b): restore is OFF by default
        ; after a strip; only this tile activates it; restores ONLY our tracked queue).
        _StripRestore_Execute(akCaster, akVictim)
        Return
    ; REV-164 (Issue #3, user ruling): the "Force Tattoo" tile (choice 12) is
    ; RETIRED from the downed panel + this dispatcher -- the LLM lane
    ; (ApplyTattoo, now downed-gated + decoupled per the why-trace verdict)
    ; and the gated AI-aggressor daemon lane (_ForcedTattoo_Execute via
    ; _ForcedTattooGateCheck) cover both remaining surfaces; the tile was the
    ; silent-[noset] failure surface. ids 8 (Apply Tattoo picker), 9 (Remove
    ; Tattoos), 10/11 (Strip/restore) are untouched; id 12 is now dead space
    ; below the +100 offset.
    ElseIf choice == 3 && StorageUtil.GetIntValue(akVictim, "SNBaka.Tied", 0) == 1
        ; Stand Back must not quietly free a TIED prisoner — the bindings are the point.
        _Log("[SNBaka] _DispatchDownedAction: Stand Back refused — " + akVictim.GetDisplayName() + " is TIED (untie them first)")
        _Notify(akVictim.GetDisplayName() + " is tied - cut them loose first.")
        Return
    EndIf
    If ours
        ; OUR ground window owns this victim — signal it via flags (it polls them).
        If choice == 0
            Escalate_Execute(akCaster, akVictim)
        ElseIf choice == 1
            _iDownedReplay = 1
        ElseIf choice == 2
            _iDownedReplay = 2
        ElseIf choice == 3
            _bStandBack = True
        ElseIf choice == 4
            HelpUp_Execute(akCaster, akVictim)   ; _ForceRecover sets _bReleaseRequested, same exit path as Stand Back
        Else
            _Log("[SNBaka] _DispatchDownedAction: cancel — victim stays downed")
        EndIf
    Else
        ; Downed by an external mod/cause (e.g. Surrender, or Acheron) — no window of ours is running, so
        ; run the action directly with the caster as the actor. (Same functions the window would have called.)
        _Log("[SNBaka] _DispatchDownedAction: external down — running choice " + choice + " directly")
        If choice == 0
            _DoEscalation(akCaster, akVictim)            ; choke-down -> sex
        ElseIf choice == 1
            _DownedReplay(akCaster, akVictim, 1)         ; investigate
        ElseIf choice == 2
            _DownedReplay(akCaster, akVictim, 2)         ; inspect
        ElseIf choice == 3
            ; Was a silent no-op here — "leaving victim to the other mod" never actually freed them,
            ; since nothing was listening for that comment. Recover them locally, but abFullRescue=False:
            ; Stand Back is "we step back and let them get up," not "we rescued them" — the earlier fix
            ; called the same full-rescue path as Help Up, which made Stand Back visibly/mechanically
            ; indistinguishable from it (Acheron's own RescueActor "saved" treatment firing either way).
            ; [REV-177b item 7 / R-177b] spare decision BEFORE recovery; enemy victims are
            ; stood down immediately after (Oldcustard shape) — no wait-for-standup.
            Bool spareEnemy = _SpareEnemyDecided(akCaster, akVictim)
            _ForceRecover(akVictim, False)
            If spareEnemy
                _SparePacifyEnemy(akVictim)
            EndIf
            _Log("[SNBaka] _DispatchDownedAction: external stand-back — recovered directly (no Acheron rescue)")
        ElseIf choice == 4
            HelpUp_Execute(akCaster, akVictim)
        Else
            _Log("[SNBaka] _DispatchDownedAction: external cancel — victim stays downed")
        EndIf
    EndIf
EndFunction

; [REV-144 Strip] "All to Dress" (id 11) -- the ONLY restore surface (ruling
; (ii)(b): stays off after strip until this tile). Restores ONLY our tracked
; queue; when SexLab is present its UnstripActor handles the re-equip (silently,
; worn-slot aware); the vanilla fallback is a plain EquipItem loop. Never touches
; SeverActions' locks or re-dress: presence-gated out (reason-coded) whenever
; SeverOutfit_LockActive says the victim's outfit is under their lock system.

Function _StripRestore_Execute(Actor akCaster, Actor akVictim)
    _ActionLaneFire(akCaster, akVictim, "StripRestore") ; [REV-174f Leg 4.2] neutral fanned lane (LLM/player-initiated; daemon fires suppressed)
    _Log("[SNBaka] Allow to Dress: caster=" + akCaster + " victim=" + akVictim)
    If !akCaster || !akVictim
        _Log("[SNBaka] All to Dress REFUSE [null]: null actor leg")
        Return
    EndIf
    ; REV-146a Task 2: child boundary - no module action on children, restore
    ; included (the tile would hand a child actor's outfit back; same boundary).
    If _ChildBoundaryRefused(akCaster, akVictim, "StripRestore")
        Return
    EndIf
    Int nQueued = StorageUtil.FormListCount(akVictim, "SNBaka.StripQueue")
    If nQueued == 0
        _Log("[SNBaka] All to Dress REFUSE [bare]: no tracked strip queue on " + akVictim.GetDisplayName())
        _Notify("No strip in progress on " + akVictim.GetDisplayName() + ".")
        Return
    EndIf
    ; Presence-gate: their lock, their rules -- we never fight a SeverActions lock.
    If StorageUtil.GetIntValue(akVictim, "SeverOutfit_LockActive", 0) == 1
        _Log("[SNBaka] All to Dress REFUSE [severlock]: " + akVictim.GetDisplayName() + " is under a SeverActions outfit lock - their re-dress owns it")
        _Notify(akVictim.GetDisplayName() + " is under a SeverActions outfit lock - their system owns re-dressing.")
        Return
    EndIf
    Form[] akRestore = StorageUtil.FormListToArray(akVictim, "SNBaka.StripQueue")
    Int i = 0
    Int nRestored = 0
    If SkyrimNet_BakaSL.Installed()
        ; Primary: SexLab UnstripActor over our queue (signature-true to installed
        ; P+ source L144); still only OUR tracked forms -- never a foreign set.
        SkyrimNet_BakaSL.UnstripActor(akVictim, akRestore)
        While akRestore && i < akRestore.Length
            If akRestore[i] && akVictim.IsEquipped(akRestore[i])
                nRestored += 1
            EndIf
            i += 1
        EndWhile
        _Log("[SNBaka] All to Dress: SexLab UnstripActor restored " + nRestored + "/" + akRestore.Length)
    Else
        ; Vanilla fallback: equip what we tracked, skip anything no longer present.
        While akRestore && i < akRestore.Length
            If akRestore[i] && akVictim.GetItemCount(akRestore[i]) > 0 && !akVictim.IsEquipped(akRestore[i])
                akVictim.EquipItem(akRestore[i], True)
                nRestored += 1
            EndIf
            i += 1
        EndWhile
        _Log("[SNBaka] All to Dress: vanilla re-equip restored " + nRestored + "/" + akRestore.Length)
    EndIf
    StorageUtil.FormListClear(akVictim, "SNBaka.StripQueue")
    _Log("[SNBaka] All to Dress: APPLIED " + nRestored + "/" + akRestore.Length + " back on " + akVictim.GetDisplayName() + " (queue cleared)")
EndFunction


; --- Downed replay (Investigate / Inspect on an already-downed victim) ---
; Plays the inspection sequence to completion with NO QTE, then drops the victim back to the
; ground. Called from inside _DefeatGroundWindow's wait loop; the loop resets its timer after.
; which: 1 = Investigate (Babo_Investigation), 2 = Inspect (Babo_Captured).
Function _DownedReplay(Actor akA1, Actor akA2, Int which)
    _Log("[SNBaka] _DownedReplay: A1=" + akA1.GetDisplayName() + " A2=" + akA2.GetDisplayName() + " which=" + which)
    If !akA1 || !akA2 || akA2.IsDead()
        Return
    EndIf
    ; Investigate_Execute/CapturedInspect_Execute (the direct-call entry points for these same two
    ; actions) both check HasFemaleBody before doing anything -- this replay path, reached from the
    ; downed-menu's Investigate/Inspect picks (both the "ours" ground-window loop and the "external"/
    ; Hunter's Pride dispatch), had no such check at all, so it would happily play CapturedBoob/
    ; CapturedPussy female-specific animation stages on a male victim.
    ; Same creature-skeleton guard as IsEligible: a falmer/giant aggressor reaching this replay
    ; (via the downed menu or Hunter's Pride) would play humanoid inspection anims it can't skeleton.
    If _IsCreatureActor(akA1) || _CreatureAnimKey(akA1) != ""
        _Log("[SNBaka] _DownedReplay: blocked — creature-skeleton initiator " + akA1.GetDisplayName() + " (humanoid anims only)")
        Return
    EndIf
    If !HasFemaleBody(akA2)
        _Log("[SNBaka] _DownedReplay: blocked — target is not female")
        Return
    EndIf

    String[] a1 = new String[3]
    String[] a2 = new String[3]
    String what = "investigates "
    Float s0rot = 0.0   ; Investigation flips the aggressor on stage 0 (see PlayPairedSequence)
    If which == 2
        a1[0] = "Babo_Captured_A2"
        a1[1] = "Babo_CapturedBoob_A2"
        a1[2] = "Babo_CapturedPussy_A2"
        a2[0] = "Babo_Captured_A1"
        a2[1] = "Babo_CapturedBoob_A1"
        a2[2] = "Babo_CapturedPussy_A1"
        what = "inspects the captured "
        RecordAnimation(akA1, "CapturedInspect", akA2.GetDisplayName())
    Else
        a1[0] = "Babo_Investigation_S01_A02"
        a1[1] = "Babo_Investigation_S02_A02"
        a1[2] = "Babo_Investigation_S03_A02"
        a2[0] = "Babo_Investigation_S01_A01"
        a2[1] = "Babo_Investigation_S02_A01"
        a2[2] = "Babo_Investigation_S03_A01"
        RecordAnimation(akA1, "Investigate", akA2.GetDisplayName())
        s0rot = 180.0
    EndIf

    _CueOngoing("baka_forced", \
        akA1.GetDisplayName() + " " + what + "the helpless " + akA2.GetDisplayName() + "'s body as they lie defeated.", \
        akA1, akA2)
    PlayPanicSound(akA2)
    _StartTears(akA2)

    ; Re-lock the (currently free) attacker; the victim is still owned by the ground window.
    StorageUtil.SetIntValue(akA1, "SNBaka.Locked", 1)
    ; Bring the victim up out of bleedout + clear the ground-hold flags so _SetupPair (inside
    ; PlayPairedSequence) can position and drive their skeleton cleanly.
    akA2.SetRestrained(False)
    akA2.SetDontMove(False)
    _Recover(akA2)
    Utility.Wait(0.3)

    ; Full inspection sequence, NO QTE — it runs every stage through, then _CleanupPair resets.
    PlayPairedSequence(akA1, akA2, 0.0, 0.0, 180.0, a1, a2, fSequenceStageTimer, False, True, s0rot)

    ; Drop the victim straight back down; the ground window resets its timer on return.
    _Bleedout(akA2, akA1)
    Utility.Wait(0.3)
    If akA2 != PlayerRef
        akA2.SetRestrained(True)
        akA2.SetDontMove(True)
        _PacifyActor(akA2, True)
        _HoldActorAI(akA2, True)
    EndIf
    ; Free the attacker again so they stand back over the downed victim.
    _UnlockAttackerOnly(akA1)
    _Log("[SNBaka] _DownedReplay: complete — victim re-downed")
EndFunction

; ============================================================
; CREATURE ESCALATION (opt-in; bestiality content — gated behind bCreatureEscalation, default OFF)
; ============================================================
; Maps a live creature to its Baka paired-QTE animation base by RACE NAME (best-effort, no SexLab/
; OStim needed to identify or play — those are only the optional sex backend). dog == wolf (canine).
; Returns "" for unsupported races. Order matters: more specific names first (Werewolf before Wolf,
; Chaurus Hunter/Reaper before Chaurus, Dwarven Spider before Spider, Giant after Spider).
String Function _CreatureAnimKey(Actor akCreature)
    If !akCreature
        Return ""
    EndIf
    ; Race EditorID first — tied to the actual skeleton, so a renamed/reskinned creature (e.g. a mod's
    ; "Sewer Troll" that's still TrollRace underneath) matches correctly even though its display name
    ; has nothing to do with "troll". Display name stays in the same check as a fallback, for the
    ; reverse case: a wholly custom race whose EditorID doesn't mention a supported type but whose
    ; display name does.
    String n = MiscUtil.GetActorRaceEditorID(akCreature) + "|" + akCreature.GetDisplayName()   ; "TrollRace|Frost Troll"...
    If n == "|"
        Return ""
    EndIf
    If StringUtil.Find(n, "Werewolf") >= 0
        Return "Babo_WerewolfQTE"
    ElseIf StringUtil.Find(n, "Wolf") >= 0 || StringUtil.Find(n, "Dog") >= 0 || StringUtil.Find(n, "Husky") >= 0 || StringUtil.Find(n, "Fox") >= 0 || StringUtil.Find(n, "Hound") >= 0
        ; "Hound": Death Hounds (DLC1DeathHoundRace) run on the canine skeleton, whose Baka Motion
        ; animation list registers the Wolf QTE events -- they were undetected before despite the
        ; animations genuinely supporting them (neither "Wolf" nor "Dog" appears in their race/name).
        Return "Babo_WolfQTE"
    ElseIf StringUtil.Find(n, "Chaurus Hunter") >= 0 || StringUtil.Find(n, "ChaurusHunter") >= 0
        ; Every no-space variant below mirrors the race EditorID convention ("ChaurusHunterRace",
        ; "DwarvenSpiderRace", "DLC2AshHopperRace"...) -- the spaced form only matches the display
        ; name, so a RENAMED creature of these types silently fell through to a more generic match
        ; (or none): a renamed Dwarven Spider hit the plain "Spider" branch and got sent animation
        ; events its skeleton doesn't even have, which plays nothing on the creature at all.
        Return "Babo_ChaurusHunterQTE"
    ElseIf StringUtil.Find(n, "Chaurus Reaper") >= 0 || StringUtil.Find(n, "ChaurusReaper") >= 0
        Return "Babo_ChaurusReaperQTE"
    ElseIf StringUtil.Find(n, "Chaurus") >= 0
        Return "Babo_ChaurusQTE"
    ElseIf StringUtil.Find(n, "Dwarven Spider") >= 0 || StringUtil.Find(n, "DwarvenSpider") >= 0
        Return "Babo_DwarvenSpiderQTE"
    ElseIf StringUtil.Find(n, "Centurion") >= 0
        Return "Babo_DwarvenCenturionQTE"
    ElseIf StringUtil.Find(n, "Spider") >= 0
        ; The Baka Motion pack ships three distinct frostbite-spider QTE sets on the same skeleton --
        ; route the giant and large variants to their own clips instead of always using the base one.
        ; Checked INSIDE the spider branch so "Giant Frostbite Spider" can never leak into the plain
        ; "Giant" (humanoid giant) branch below regardless of check order.
        If StringUtil.Find(n, "Giant") >= 0
            Return "Babo_GiantSpiderQTE"
        ElseIf StringUtil.Find(n, "Large") >= 0
            Return "Babo_LSpiderQTE"
        EndIf
        Return "Babo_SpiderQTE"
    ElseIf StringUtil.Find(n, "Sabre") >= 0
        Return "Babo_SabrecatQTE"
    ElseIf StringUtil.Find(n, "Troll") >= 0
        Return "Babo_TrollQTE"
    ElseIf StringUtil.Find(n, "Bear") >= 0
        Return "Babo_BearQTE"
    ElseIf StringUtil.Find(n, "Falmer") >= 0
        Return "Babo_FalmerQTE"
    ElseIf StringUtil.Find(n, "Draugr") >= 0
        Return "Babo_DraugrQTE"
    ElseIf StringUtil.Find(n, "Skeever") >= 0
        Return "Babo_SkeeverQTE"
    ElseIf StringUtil.Find(n, "Riekling") >= 0
        Return "Babo_RieklingQTE"
    ElseIf StringUtil.Find(n, "Netch") >= 0
        Return "Babo_NetchQTE"
    ElseIf StringUtil.Find(n, "Gargoyle") >= 0
        Return "Babo_GargoyleQTE"
    ElseIf StringUtil.Find(n, "Boar") >= 0
        Return "Babo_BoarQTE"
    ElseIf StringUtil.Find(n, "Ash Hopper") >= 0 || StringUtil.Find(n, "AshHopper") >= 0
        Return "Babo_AshHopperQTE"
    ElseIf StringUtil.Find(n, "Giant") >= 0
        Return "Babo_GiantQTE"
    EndIf
    Return ""
EndFunction

; SkyrimNet entry: the LLM (or the player's power) invokes this with the creature + the victim in
; either order. We sort out which is the creature and escalate. Creatures are ESCALATE-ONLY.
Function CreatureEscalate_Execute(Actor akInitiator, Actor akTarget)
    _ActionLaneFire(akInitiator, akTarget, "CreatureEscalate") ; [REV-174f Leg 4.2] neutral fanned lane (LLM/player-initiated; daemon fires suppressed)
    _Log("[SNBakaACT] CreatureEscalate ENTER")
    If !bCreatureEscalation || !akInitiator || !akTarget
        Return
    EndIf
    ; REV-146a Task 2: child boundary - creature lane (a child victim is
    ; never a valid creature-escalation target).
    If _ChildBoundaryRefused(akInitiator, akTarget, "CreatureEscalate")
        Return
    EndIf
    Actor creature = akInitiator
    Actor victim   = akTarget
    ; [REV-177b / R-177d] NoAnim fallback accepted at entry (NPC-only enforced inside
    ; _DoCreatureEscalation via _CreatureStruggleKey's victim check).
    If _CreatureStruggleKey(creature, True) == ""
        If _CreatureStruggleKey(akTarget, True) != ""
            creature = akTarget
            victim   = akInitiator
        Else
            _Log("[SNBaka] CreatureEscalate: neither actor is a supported creature")
            Return
        EndIf
    EndIf
    _DoCreatureEscalation(creature, victim)
EndFunction

; Extended NOT-YET-DOWNED NPC struggle: PlayPairedSequence's own "just play every stage straight
; through" branch (bResistable=False) was only ever ~3s (2 stages x 1.5s) with zero connection to the
; outcome rolled afterward -- confirmed feedback from testing: reads as far too quick to be a real
; struggle, and a non-player victim never got a distinct win/lose animation at all. This holds the
; shared struggle pose (stage 0) for fCreatureStruggleDuration seconds FIRST, THEN rolls, THEN — only
; if the victim actually wins — plays the clip's own stage 1 ("break free") briefly before releasing.
; A creature win has no separate victory stage to show for a 2-stage clip, so it just stays on the
; struggle pose, which flows straight into _StartSexScene right after this returns.
; Bypasses PlayPairedSequence entirely (rather than adding a 3rd branch to it) so human-vs-human
; Struggle, which shares that function, is untouched. Reuses the exact same setup/protection/cleanup
; calls PlayPairedSequence itself uses (_SetupPair already does StopCombat + Ghost + Pacify + AI-hold +
; Restrained on both actors, which is the same "ignore outside combat" protection any other paired
; scene gets — nothing extra needed there for the longer hold).
; Returns True if the victim escaped.
Bool Function _PlayCreatureStruggleNPC(Actor akCreature, Actor akVictim, String[] animsA1, String[] animsA2)
    ObjectReference marker1 = None
    ObjectReference marker2 = None
    If XMarkerBase
        marker1 = akVictim.PlaceAtMe(XMarkerBase, 1, False, False)
        marker2 = akVictim.PlaceAtMe(XMarkerBase, 1, False, False)
    EndIf
    _ProtectNearbyAllies(akVictim, akCreature, True, False)
    _SetupPair(akCreature, akVictim, 0.0, 0.0, 0.0, True, marker1, marker2, animsA1[0])

    Bool aborted = _HoldAnim(akCreature, akVictim, animsA1[0], animsA2[0], fCreatureStruggleDuration)

    ; Same rule as the top-level comment on _DoCreatureEscalation: a hit/death/distance-break mid-hold
    ; frees the victim and resumes the fight, same as it always has -- treat that as an escape rather
    ; than rolling for an outcome the interruption already decided.
    Bool escaped = True
    If aborted
        _Log("[SNBaka] _PlayCreatureStruggleNPC: aborted mid-struggle (hit/death/distance) -- counts as escaped")
    Else
        escaped = Utility.RandomInt(1, 100) > iCreatureSuccessPct
        _Log("[SNBaka] _PlayCreatureStruggleNPC: struggle held " + fCreatureStruggleDuration + "s, escaped=" + escaped)
        If escaped
            Debug.SendAnimationEvent(akCreature, animsA1[1])
            Debug.SendAnimationEvent(akVictim, animsA2[1])
            Utility.Wait(1.5)
        EndIf
    EndIf

    _ProtectNearbyAllies(akVictim, akCreature, False)
    _CleanupPair(akCreature, akVictim, marker1, marker2, False, False)
    ; Same post-escape grace the player QTE path gets (see PlayPairedSequence) -- an NPC victim who
    ; broke free was equally getting instantly re-hit the moment the cleanup un-ghosted her.
    If escaped
        _PostEscapeGrace(akVictim)
    EndIf
    Return escaped
EndFunction

; [REV-177b / R-177d — Oldcustard issue #2 feature, credit Oldcustard]
; NoAnim_<creature> placeholder registry for SCENE-ONLY creatures: races with
; OStim scenes but no dedicated struggle clip (Dwarven Sphere: 27 scenes, zero
; struggle anims — the motivating report). The placeholder key lets the
; escalation pipeline run its normal gates while the struggle itself is ANIMLESS
; (see _PlayCreatureStruggleAnimless). NPC VICTIMS ONLY — every caller passes
; abAllowNoAnim=False when the victim is the player, so the placeholder never
; widens the player lane.
; RETIREMENT LEDGER (first customer of the retirement-checklist rider, register
; entry 49.4): each placeholder below RETIRES when a dedicated struggle animation
; lands for that creature — remove the entry here, verify _PlayCreatureStruggleAnimless
; no longer fires for the race (§5 sentinel), and receipt the funeral in the rev's
; PROJECT_STATE section. First entry: NoAnim_Sphere (Dwarven Sphere). Expansion
; may never come; the ledger is cheap intent.
String Function _CreatureNoAnimKey(Actor akCreature)
    If !akCreature
        Return ""
    EndIf
    String n = MiscUtil.GetActorRaceEditorID(akCreature) + "|" + akCreature.GetDisplayName()
    If n == "|"
        Return ""
    EndIf
    ; Dwarven Sphere (DwarvenSphereRace) — Centurions are explicitly excluded (they
    ; have their own real QTE key in _CreatureAnimKey; match order there catches them).
    If (StringUtil.Find(n, "Sphere") >= 0) && (StringUtil.Find(n, "Centurion") < 0)
        Return "NoAnim_Sphere"
    EndIf
    Return ""
EndFunction

; Unified struggle eligibility key: the real anim key when one exists; the NoAnim
; placeholder when the creature is scene-only AND animless struggle is allowed for
; this victim (NPC victims only, enforced by every caller via abAllowNoAnim).
String Function _CreatureStruggleKey(Actor akCreature, Bool abAllowNoAnim)
    String k = _CreatureAnimKey(akCreature)
    If k == "" && abAllowNoAnim
        Return _CreatureNoAnimKey(akCreature)
    EndIf
    Return k
EndFunction

; [REV-177b / R-177d] ANIMLESS struggle: GENERIC fallback for scene-only
; creatures (NoAnim_<creature> placeholders). Same hold/duration/abort/roll rules
; as _PlayCreatureStruggleNPC, but NO _SetupPair repositioning and NO animation
; events — nobody teleports, no markers spawn; the creature is pacified + AI-held
; where it stands over the victim for fCreatureStruggleDuration, then the SAME
; escape roll (iCreatureSuccessPct) decides. Aborts (creature death, victim death,
; pair separated > 600 units — no anim events exist to signal the mid-hold breaks
; _HoldAnim relies on) count as escapes, same rule as the paired path. NPC
; VICTIMS ONLY (callers enforce). No group companions in this lane
; (_FindGroupCompanions matches on the real key only) — recorded honestly in S216.
Bool Function _PlayCreatureStruggleAnimless(Actor akCreature, Actor akVictim)
    _Log("[SNBaka] _PlayCreatureStruggleAnimless: " + akCreature.GetDisplayName() + " holds " + akVictim.GetDisplayName() + " in place (NoAnim fallback, R-177d)")
    _ProtectNearbyAllies(akVictim, akCreature, True, False)
    _PacifyActor(akCreature, True)
    _HoldActorAI(akCreature, True)
    Bool aborted = False
    Float held = 0.0
    While held < fCreatureStruggleDuration && !aborted
        Utility.Wait(0.5)
        held += 0.5
        If !akCreature || akCreature.IsDead() || !akVictim || akVictim.IsDead() || akCreature.GetDistance(akVictim) > 600.0
            aborted = True
        EndIf
    EndWhile
    Bool escaped = True
    If aborted
        _Log("[SNBaka] _PlayCreatureStruggleAnimless: aborted mid-hold (death/distance) -- counts as escaped")
    Else
        escaped = Utility.RandomInt(1, 100) > iCreatureSuccessPct
        _Log("[SNBaka] _PlayCreatureStruggleAnimless: struggle held " + fCreatureStruggleDuration + "s, escaped=" + escaped)
    EndIf
    _HoldActorAI(akCreature, False)
    _ProtectNearbyAllies(akVictim, akCreature, False, False)
    If escaped
        _PostEscapeGrace(akVictim)
    EndIf
    Return escaped
EndFunction

; Group escalation (2v1/3v1): finds up to (iCreatureGroupMaxSize - 1) OTHER actors of the SAME
; creature type as akAnchor, near akVictim, to join the scene. akAnchor works as the anchor whether it
; just WON its own 1v1 struggle or was simply the single candidate _TryCreatureEscalateOnDowned found
; for a victim already downed by plain combat (no struggle happened) -- either way, this only asks
; "who else of its kind is nearby to join", which is the same question regardless of how the anchor
; itself got here.
; One scan (not separate "try 3, try 2, try 1" passes) collecting whatever's available and capping at
; the max -- functionally the same "biggest available group, gracefully smaller if not" result without
; wastefully re-scanning per size tier. Plus a single cross-cell supplement (same FindClosestActorFromRef
; technique used everywhere else this blind spot shows up) if the same-cell sweep didn't fill both
; slots -- confirmed in testing that group scenes never formed at all, always landing on the same-cell-
; only limitation this function originally shipped with (dungeon dens are almost always split across
; linked cells, same as every other search in this file that had to learn this the hard way).
; Papyrus array sizes must be compile-time literals (no "new Actor[count]") -- always returns a fixed
; 2-slot array, unused slots left None, instead of a dynamically-sized result. Callers check each slot.
Actor[] Function _FindGroupCompanions(Actor akAnchor, Actor akVictim)
    Actor[] slots = new Actor[2]
    Int wanted = iCreatureGroupMaxSize - 1
    If wanted <= 0 || !akAnchor || !akVictim
        Return slots
    EndIf
    String animKey = _CreatureAnimKey(akAnchor)
    Int count = 0
    ; LOADED-AREA enumeration (po3 Papyrus Extender), same as _TryCreatureEscalateOnDowned's scan and
    ; for the same confirmed reason: cell sweeps miss packmates registered in linked cells, which is
    ; why every group scene came out 1v1. Every same-type creature logs its rejection reason so the
    ; log always explains why a group did or didn't form.
    If animKey != ""
        Actor[] loaded = PO3_SKSEFunctions.GetActorsByProcessingLevel(0)
        Int n = loaded.Length
        Int i = 0
        While i < n && count < wanted && count < 2
            Actor a = loaded[i]
            If a && a != akAnchor && a != akVictim && a != slots[0] && !a.IsDead() && _CreatureAnimKey(a) == animKey
                ; !_HasLiveCombatTarget: same rule the ANCHOR gets ("don't pull it out of a real
                ; fight"); a target that's downed/dead doesn't count as a real fight anymore.
                If IsActorLocked(a)
                    _Log("[SNBaka] _FindGroupCompanions: skipping " + a.GetDisplayName() + " — locked (mid-interaction)")
                ElseIf _IsDownedAny(a)
                    _Log("[SNBaka] _FindGroupCompanions: skipping " + a.GetDisplayName() + " — downed")
                ElseIf _HasLiveCombatTarget(a)
                    _Log("[SNBaka] _FindGroupCompanions: skipping " + a.GetDisplayName() + " — still fighting " + a.GetCombatTarget().GetDisplayName())
                ElseIf a.GetDistance(akVictim) > 1500.0
                    _Log("[SNBaka] _FindGroupCompanions: skipping " + a.GetDisplayName() + " — too far (" + a.GetDistance(akVictim) + ")")
                Else
                    slots[count] = a
                    _Log("[SNBaka] _FindGroupCompanions: found companion " + a.GetDisplayName())
                    count += 1
                EndIf
            EndIf
            i += 1
        EndWhile
    EndIf
    _Log("[SNBaka] _FindGroupCompanions: " + count + " companion(s) found (wanted " + wanted + ", key=" + animKey + ")")
    Return slots
EndFunction

; Setup/teardown for a GROUP companion (not the anchor -- that already gets the full _SetupPair
; treatment). Same ghost/restrained/dontmove/AI-hold profile so it can't wander off, get hurt, or
; interfere, but no positioning: OStim/SexLab's own scene engine places every actor once handed a
; scene ID that actually supports this many participants.
Function _PrepGroupCompanion(Actor a, Bool abPrep)
    If !a
        Return
    EndIf
    If abPrep
        a.StopCombat()
        a.StopCombatAlarm()
        SNBakaUI.SetNoCollision(a, True)
        a.SetGhost(True)
        _HoldActorAI(a, True)
        a.SetRestrained(True)
        a.SetDontMove(True)
        _Log("[SNBaka] _PrepGroupCompanion: prepped " + a.GetDisplayName())
    Else
        a.SetRestrained(False)
        a.SetDontMove(False)
        a.SetGhost(False)
        SNBakaUI.SetNoCollision(a, False)
        _HoldActorAI(a, False)
        a.EvaluatePackage()
        _Log("[SNBaka] _PrepGroupCompanion: released " + a.GetDisplayName())
    EndIf
EndFunction

; The engine: play the creature-matched paired anim, decide the outcome, then start the creature sex
; scene on the chosen backend. PC victim -> QTE; NPC -> iCreatureSuccessPct roll either way (downed or not).
; A hit puts an actor back in combat, which aborts the paired anim (existing _ShouldAbort) AND blocks
; the scene below — so getting hit frees the victim and resumes the fight.
Function _DoCreatureEscalation(Actor akCreature, Actor akVictim)
    _Log("[SNBaka] _DoCreatureEscalation ENTER: creature=" + akCreature + " victim=" + akVictim)
    If !bCreatureEscalation || !akCreature || !akVictim
        _Log("[SNBaka] CreatureEscalate: blocked — escOff/none (esc=" + bCreatureEscalation + ")")
        Return
    EndIf
    ; REV-146a Task 2: child boundary - creature lane.
    If _ChildBoundaryRefused(akCreature, akVictim, "DoCreatureEscalation")
        Return
    EndIf
    ; REV-144 4.2: central player-target policy consulted ALONGSIDE the creature-specific
    ; bCreatureOnPlayer toggle (AND -- the toggle stays live; the policy blankets the module).
    If akVictim == PlayerRef && (!bCreatureOnPlayer || !_PlayerTargetAdmitted(akCreature, akVictim, "CreatureEscalate"))
        _Log("[SNBaka] CreatureEscalate: blocked — player victim, bCreatureOnPlayer OFF or REV-144 policy OFF")
        Return
    EndIf
    Bool vFemale = _SexOf(akVictim) == 1
    ; iCreatureVictimSex: 0 = Both (allow all), 1 = Female only, 2 = Male only (same scheme as iTargetSex).
    If (iCreatureVictimSex == 1 && !vFemale) || (iCreatureVictimSex == 2 && vFemale)
        _Log("[SNBaka] CreatureEscalate: blocked — victim sex not allowed by MCM (iCreatureVictimSex=" + iCreatureVictimSex + " victimFemale=" + vFemale + ")")
        Return
    EndIf
    String base = _CreatureStruggleKey(akCreature, akVictim != PlayerRef)
    Bool noAnim = base != "" && _CreatureAnimKey(akCreature) == ""
    If base == ""
        _Log("[SNBaka] CreatureEscalate: blocked — no creature anim key (and no NoAnim fallback, or player victim) for " + akCreature.GetDisplayName())
        Return
    EndIf
    ; Mid-sex-scene actors are untouchable for paired animations — OStim/SexLab threads from ANY mod
    ; (our own Locked flag only marks ours). Same explicit spec as IsEligible's twin check.
    If IsInSexAnimation(akVictim) || IsInSexAnimation(akCreature)
        _Log("[SNBaka] CreatureEscalate: blocked — a participant is mid sex scene (" + akCreature.GetDisplayName() + " -> " + akVictim.GetDisplayName() + ")")
        Return
    EndIf
    Bool downed = _IsDownedAny(akVictim)
    If !downed && !bCreatureCombatAllowed
        _Log("[SNBaka] CreatureEscalate: blocked — victim not downed and mid-combat escalation disabled")
        Return
    EndIf
    If IsActorLocked(akCreature) || IsActorLocked(akVictim)
        _Log("[SNBaka] CreatureEscalate: blocked — actor already locked (creature=" + IsActorLocked(akCreature) + " victim=" + IsActorLocked(akVictim) + ")")
        Return
    EndIf
    If !LockBoth(akCreature, akVictim)
        _Log("[SNBaka] CreatureEscalate: blocked — LockBoth failed")
        Return
    EndIf
    ; Only now, with the pairing actually committed (every rejection gate above already passed), clear
    ; the Acheron hold/OnGround so the creature anim can position the victim properly. Used to happen in
    ; the CALLER (_TryCreatureEscalateOnDowned) before any of these gates ran, which meant a candidate
    ; rejected by one of them (wrong sex, no anim key, already locked, etc.) still had their downed state
    ; silently wiped for nothing — neither still tracked as down nor actually recovered/stood up.
    ; USER-SPEC (the OSimpleDefeat pattern, extended to struggles): a downed victim is NOT lifted out
    ; of Acheron for the pin/QTE — they stay defeated straight through grab -> struggle -> scene ->
    ; re-down, one unbroken protection. Acheron's defeat is the one state that never leaked; every
    ; rescue-to-animate variant opened the exact window enemies kept aggroing through. Acheron lifts
    ; ONLY when the victim genuinely stands — QTE win / HelpUp / the get-up key — each already wrapped
    ; in the mercy grace (fEscapeGraceDuration) against spawn-kills. The paired anim events drive the
    ; graph over the down pose directly; not-downed victims (mid-combat grapples) are unaffected.
    _ProtectVictimTargeting(akVictim)
    StorageUtil.SetIntValue(akVictim, "SNBaka.OnGround", 0)
    _Log("[SNBaka] CreatureEscalate(" + akVictim.GetDisplayName() + "): locked + starting anim, base=" + base + " downed=" + downed)
    RecordAnimation(akVictim, "CreatureEscalate", akCreature.GetDisplayName())
    _CueOngoing("baka_forced", \
        akCreature.GetDisplayName() + " pins " + akVictim.GetDisplayName() + " down and forces itself on them.", \
        akCreature, akVictim)
    PlayPanicSound(akVictim)
    _StartTears(akVictim)

    ; 2-stage pair: creature plays the _A02 events, the human victim plays _A01. Co-located base
    ; (offset key = a1[0]); tune per creature in SNBaka_Offsets.ini since sizes differ.
    String[] a1 = new String[2]
    String[] a2 = new String[2]
    a1[0] = base + "_S01_A02"
    a1[1] = base + "_S02_A02"
    a2[0] = base + "_S01_A01"
    a2[1] = base + "_S02_A01"

    Bool succeed = False
    If akVictim == PlayerRef
        ; FREEZE BYSTANDERS for the whole QTE, not just the scene prep afterwards. The player victim
        ; isn't Acheron-pacified (native player lockdown — camera), so the OTHER giants re-aggroed the
        ; instant the rescue freed them and kept the combat flag live through the QTE — which then made
        ; the scene gate refuse, re-down, re-escalate: the reported infinite loop. Holding every nearby
        ; actor's AI is what actually eliminates combat toward the pair; the scene path re-holds
        ; idempotently, and every exit (scene end, no-scene, refusal) releases.
        _ProtectNearbyAllies(akVictim, akCreature, True, False)
        ; Real interactive QTE -- unchanged.
        _bQTEDefeated = False
        ; A dedicated, shorter stage timer here (not fSequenceStageTimer) — that 4.0s default is tuned
        ; for the 5-stage human Struggle sequence, where finishing out the current stage after a QTE
        ; resolves is a small fraction of the whole. This creature sequence only has 2 stages, so the
        ; same 4.0s trailing wait after the outcome is already known is most of the sequence's total
        ; length — confirmed in testing as a visible "still animating" hang after the QTE clearly ended.
        PlayPairedSequence(akCreature, akVictim, 0.0, 0.0, 0.0, a1, a2, 1.5, True)
        succeed = _bQTEDefeated             ; creature won the QTE
        _bQTEDefeated = False
        If succeed
            ; USER-SPEC redesign (every hand-rolled protection kept losing to combat AI): the instant
            ; the QTE is lost, hand the victim STRAIGHT to Acheron — its native defeat is the one
            ; state that provably stops all targeting ("downed victims are never attacked"). The
            ; entire scene prep below now runs with the victim safely parked down; they're rescued
            ; back out at the last possible moment, directly into the scene.
            StorageUtil.SetFormValue(akVictim, "SNBaka.GroundWindowAggressor", akCreature)
            _DelegateDownToAcheron(akVictim)
            _Log("[SNBaka] CreatureEscalate(" + akVictim.GetDisplayName() + "): QTE lost — victim parked in Acheron for the prep window")
        EndIf
    Else
        ; NPC victim, downed or mid-combat: a REAL drawn-out struggle either way — _PlayCreatureStruggleNPC
        ; holds the pin pose fCreatureStruggleDuration seconds (MCM-tunable), THEN rolls
        ; iCreatureSuccessPct, THEN plays the break-free stage only on an actual escape. The
        ; already-downed case used to skip this for an instant roll + one ~1.5s stage — explicit
        ; feedback: "gets decided within seconds", hold the struggle 10-20s like the mid-combat case
        ; before deciding. Same roll odds as the old quick path (escaped = roll > pct ≡ succeed = roll <= pct).
        Bool escaped
        If noAnim
            ; [REV-177b / R-177d] scene-only creature: animless hold (no repositioning).
            escaped = _PlayCreatureStruggleAnimless(akCreature, akVictim)
        Else
            escaped = _PlayCreatureStruggleNPC(akCreature, akVictim, a1, a2)
        EndIf
        ; A TIED victim cannot break free — bound hands don't win struggles. The pin plays out the
        ; same, but the outcome is always a claim (this was the one path that could "suddenly free"
        ; a tied prisoner: winning an escape roll they physically shouldn't be able to attempt).
        If escaped && StorageUtil.GetIntValue(akVictim, "SNBaka.Tied", 0) == 1
            _Log("[SNBaka] CreatureEscalate(" + akVictim.GetDisplayName() + "): escape roll won but victim is TIED — bound victims cannot break free, treating as claimed")
            escaped = False
        EndIf
        succeed = !escaped
    EndIf

    ; Establish the anti-re-aggro relationship (same fix as the bandit re-aggro bug) as soon as we know
    ; the outcome, regardless of whether a scene actually starts right away.
    If succeed
        ; Re-calm the WINNER in the same beat — _CleanupPair (inside the paired sequence that just
        ; ended) restored its aggression, and the scene path's own re-pacify is seconds away. That gap
        ; is exactly when "the giant that escalated on me attacked me while going to OStim" (confirmed
        ; report). Idempotent with the scene path's later call; every no-scene exit re-downs the victim
        ; with GroundWindowAggressor tracked, so recovery restores the creature's aggression properly.
        _PacifyActor(akCreature, True)
        akCreature.SetRelationshipRank(akVictim, 4)
        If akVictim != PlayerRef
            akVictim.SetRelationshipRank(akCreature, 4)
        EndIf
        _StampDefeatGrace(akVictim)
        Utility.Wait(0.3)
    EndIf

    ; CRE-3: the creature STRUGGLE (above) can bring a victim down mid-combat, but the creature SEX only
    ; waits for the fight to clear when the victim is the PLAYER (same gate as human Escalate) -- the
    ; player has their own agency in an ongoing fight, so starting a scene on them mid-chaos is the one
    ; case actually worth holding off on. An NPC victim (e.g. Joylie) gets claimed the instant the
    ; creature wins, exactly like the falmer case that already worked this way -- explicit call: don't
    ; leave her tracked-down-and-waiting through however long the rest of the fight takes just because
    ; OTHER combatants are still swinging at each other nearby. If the scene starts into active combat
    ; and something hits either participant, the existing mid-scene abort (_HasLiveCombatTarget below)
    ; already force-stops it cleanly -- that's the accepted tradeoff for not waiting.
    If succeed && akVictim == PlayerRef
        ; Victim is parked in Acheron (QTE-loss delegate above) — give the pack a beat to natively
        ; disengage from the downed body BEFORE judging whether combat blocks the scene. Trimmed from
        ; 3.0s: post-QTE pacing read as "very long to decide next steps" (confirmed feedback), and the
        ; park means a slightly-early judgment just re-tries rather than exposing anyone.
        Utility.Wait(1.5)
    EndIf
    Bool combatGateBlocks = akVictim == PlayerRef && _CombatNear(akVictim, fCombatOverRadius)
    _Log("[SNBaka] CreatureEscalate(" + akVictim.GetDisplayName() + "): outcome succeed=" + succeed + " combatGateBlocks=" + combatGateBlocks + " sceneAllowed=" + bCreatureSceneAllowed)
    If succeed && !combatGateBlocks && bCreatureSceneAllowed
        ; PlayPairedSequence's own cleanup (CleanupPair) already un-pacified the creature and gave its
        ; aggression back the moment the struggle ended -- only re-pacify it (which is what actually
        ; calls StopCombat, only on the creature) NOW, immediately before actually claiming the victim
        ; for a scene, not the instant the struggle resolved. Confirmed real bug from testing ("draugr
        ; stuck" mid-fight, generalizes to every creature type since this code path is shared): pacifying
        ; unconditionally on any win left the creature frozen -- unable to fight ANYONE, not just the
        ; victim -- for however long it took the victim's OWN recovery cycle to happen to un-pacify it
        ; as a side effect, whenever the fight wasn't actually over yet (the "NO scene" branch below).
        ; That could be a long, open-ended wait in an active multi-enemy fight. _ForceRecover/Acheron's
        ; _Recover un-pacify whatever's tracked as SNBaka.GroundWindowAggressor on real recovery, so this
        ; still gets undone properly once the scene (and thus the victim's hold) actually ends.
        _PacifyActor(akCreature, True)
        ; FREEZE BYSTANDERS FIRST, before anything else on the scene path -- this used to run only
        ; AFTER _StartSexScene returned, which left the whole prep window (group scan, companion prep,
        ; OStim thread spin-up) open for a nearby enemy to re-aggro and hit the victim. Confirmed real
        ; CRASH from testing: a second falmer re-aggroed the player exactly in that window, re-downing
        ; them WHILE OStim was starting its thread -- OStim is unstable with a player actor entering
        ; combat mid-start. Holding every nearby actor's AI before the prep even begins closes the
        ; window at its source.
        _ProtectNearbyAllies(akVictim, akCreature, True, False)
        ; Group size decided HERE, only once we know we actually need a scene -- a struggle that fails
        ; or a combat-not-clear outcome above never wastes this scan. Papyrus array sizes must be
        ; compile-time literals, so build one of exactly three fixed shapes instead of a dynamic size.
        Actor[] companions = _FindGroupCompanions(akCreature, akVictim)
        Actor comp1 = companions[0]
        Actor comp2 = companions[1]
        If comp1
            _PrepGroupCompanion(comp1, True)
        EndIf
        If comp2
            _PrepGroupCompanion(comp2, True)
        EndIf
        ; LAST-MOMENT re-check, after the prep and with bystanders held: did combat re-flare on the
        ; victim during the gap between the outcome trace above and here? The AI-hold above can't stop
        ; a hit that already landed mid-prep (or an actor outside the hold's reach), and starting the
        ; OStim thread anyway in that state is the confirmed crash. Bail to the same "leave them
        ; downed" outcome the combat-gate branch below already uses -- the retry pipeline picks the
        ; victim up again once things settle.
        If _HasLiveCombatTarget(akVictim) || (akVictim == PlayerRef && _CombatNear(akVictim, fCombatOverRadius))
            _Log("[SNBaka] CreatureEscalate(" + akVictim.GetDisplayName() + "): combat re-flared during scene prep — aborting scene start, leaving victim downed")
            _ProtectNearbyAllies(akVictim, akCreature, False)
            If comp1
                _PrepGroupCompanion(comp1, False)
            EndIf
            If comp2
                _PrepGroupCompanion(comp2, False)
            EndIf
            StorageUtil.SetFormValue(akVictim, "SNBaka.GroundWindowAggressor", akCreature)
            _DelegateDownToAcheron(akVictim)
            UnlockBoth(akCreature, akVictim)
            Return
        EndIf
        Actor[] sexActors
        If comp1 && comp2
            sexActors = new Actor[4]
            sexActors[2] = comp1
            sexActors[3] = comp2
        ElseIf comp1
            sexActors = new Actor[3]
            sexActors[2] = comp1
        Else
            sexActors = new Actor[2]
        EndIf
        sexActors[0] = akCreature
        sexActors[1] = akVictim
        ; GROUP-SIZE FALLBACK (explicit spec: "first 3 creatures, if not found 2, then 1"): animation
        ; packs often ship PAIR scenes for a creature type but nothing bigger — confirmed live with
        ; rieklings: the 4-actor pick found nothing, the scene was refused, and the retry pipeline
        ; re-grabbed the same victims every ~20s forever. Shrink until a scene exists.
        ; [REV-161 PR#2 fold (3) - Oldcustard credit, by-concept] GROUP-FALLBACK
        ; BACKEND GATE: resolve the backend first -- the raw iCreatureBackend == 2
        ; test never ran the shrink on the default 0 (auto -> OStim), so the
        ; 4->3->2 fallback + the permanent-gap backoff were dead code on auto.
        If _ResolveSexBackend(iCreatureBackend) == 2
            String pickTest = _PickOStimScene(sexActors, "aggressive")
            While pickTest == "" && sexActors.Length > 2
                Actor droppedComp
                If sexActors.Length == 4
                    droppedComp = comp2
                    comp2 = None
                    sexActors = new Actor[3]
                    sexActors[2] = comp1
                Else
                    droppedComp = comp1
                    comp1 = None
                    sexActors = new Actor[2]
                EndIf
                sexActors[0] = akCreature
                sexActors[1] = akVictim
                If droppedComp
                    _PrepGroupCompanion(droppedComp, False)
                EndIf
                _Log("[SNBaka] CreatureEscalate(" + akVictim.GetDisplayName() + "): no animation at that group size — retrying with " + sexActors.Length + " actors")
                pickTest = _PickOStimScene(sexActors, "aggressive")
            EndWhile
            If pickTest == ""
                ; Not even a PAIR animation exists for this creature type — a permanent content gap.
                ; Unwind like the refused-scene branch AND back this victim's pipeline off hard, or the
                ; grab->refuse->re-down loop hammers them every throttle window (the riekling report).
                _Log("[SNBaka] CreatureEscalate(" + akVictim.GetDisplayName() + "): NO OStim animation exists even for a pair with " + akCreature.GetDisplayName() + " — unwinding, 5-minute creature backoff for this victim")
                StorageUtil.SetFloatValue(akVictim, "SNBaka.LastCreatureAttemptRT", Utility.GetCurrentRealTime() + 300.0)
                _ProtectNearbyAllies(akVictim, akCreature, False)
                If comp1
                    _PrepGroupCompanion(comp1, False)
                EndIf
                Debug.SendAnimationEvent(akCreature, "staggerStart")
                Utility.Wait(0.3)
                Debug.SendAnimationEvent(akCreature, "IdleForceDefaultState")
                akCreature.EvaluatePackage()
                akVictim.SetGhost(False)
                StorageUtil.SetFormValue(akVictim, "SNBaka.GroundWindowAggressor", akCreature)
                _DelegateDownToAcheron(akVictim)
                UnlockBoth(akCreature, akVictim)
                Return
            EndIf
        EndIf
        ; The VICTIM is untouchable for the scene's whole duration, same rule as the struggle phase
        ; (_SetupPair) and the human scene path (_EscalationCleanup): the aggressor's own faction
        ; allies won't kill its prey — a stray ally hit whiffs instead of staggering the animation or
        ; feeding OStim a combat transition mid-thread. The CREATURE stays hittable on purpose: a
        ; genuine hit on IT (a rescuer interceding) is what's allowed to break the scene below.
        akVictim.SetGhost(True)
        ; Ghost stops the hits LANDING, but attackers still kept swinging at her for the whole scene
        ; (confirmed report). Acheron's pacify makes combat IGNORE her outright ("ignoring & ignored
        ; by combat" per its API) — they drop her as a target instead of whiffing forever. Scene-scoped:
        ; released right after the wait loop; the post-scene re-down (DefeatActor) re-pacifies her
        ; through Acheron's own defeat state anyway.
        _ProtectVictimTargeting(akVictim)
        ; PLAYER scenes: let the animation graph + control restore from the paired QTE finish settling
        ; before OStim builds its player thread. Confirmed CTD (11:15:03 crash log): OStim's AlignMenu
        ; dereferenced a null thread during scene start exactly 1s after CleanupPair re-enabled player
        ; controls — an OStim-internal race we can only starve, not fix. The final combat CTD guard
        ; inside _StartSexScene runs AFTER this wait, so nothing sneaks past it during the pause.
        If akVictim == PlayerRef
            Utility.Wait(1.0)   ; trimmed from 2.0 — the park makes scene-start state far more stable than the AlignMenu-crash era
        EndIf
        ; The PLAYER stays Acheron-defeated straight through the scene (OSimpleDefeat pattern —
        ; confirmed working live: 'BillyyGiantStandingService-4' ran with victimStillDowned=TRUE).
        ; A defeated NPC is a different story: OStim REJECTS them at thread start (confirmed live:
        ; Joylie's thread got 'actors array was None' and died within the same second — the giant
        ; just walked off). NPCs get the KEEP-PACIFIED rescue instead: the defeat ends, Acheron's
        ; pacify carries over seamlessly (RescueActor abRelease=false), zero targetable gap.
        If akVictim != PlayerRef && _IsDownedAny(akVictim)
            _ClearAcheronHold(akVictim, True, True)
            Utility.Wait(0.3)
        EndIf
        ; The SCENE ACTORS themselves get Acheron's two-way pacify for the scene's duration —
        ; "aggressors mid-animation must be pacified against ANYONE" (confirmed report: the giant on
        ; Claudia acquired the freshly-liberated Joylie as a combat target mid-scene, which tripped
        ; the abort rule and killed the animation). Ignoring & ignored: they can't acquire targets and
        ; nobody targets them. Released right after the wait loop. Known trade-off, per explicit
        ; direction: intercession-by-hit won't break a creature scene anymore (a pacified creature
        ; never re-targets its attacker, so the abort rule can't see the fight).
        If StorageUtil.GetIntValue(PlayerRef, "SNAcheron.Present", 0) == 1
            Acheron.PacifyActor(akCreature)
            If comp1
                Acheron.PacifyActor(comp1)
            EndIf
            If comp2
                Acheron.PacifyActor(comp2)
            EndIf
        EndIf
        _Log("[SNBaka] CreatureEscalate(" + akVictim.GetDisplayName() + "): STARTING creature sex scene (backend=" + iCreatureBackend + ", group size=" + sexActors.Length + ", victimStillDowned=" + _IsDownedAny(akVictim) + ")")
        ; Narrative parity for NPC victims (confirmed feedback: "for other npcs, llm do not get as many
        ; cues as with the player... sometimes it's a bit lost"): the LLM heard the pin start but NOT
        ; that the claim actually proceeded to a scene. Same eventType the pin cue used. Sent only once
        ; the scene has really started (below) -- sent before, a refused scene still told the LLM it
        ; happened. [REV-177 item 5 - Oldcustard credit, issue #2 / GS Poses fork PR fa1fcdb shape:
        ; truth standard of record -- no event before the fact.]
        Int stid = _StartSexScene(sexActors, akVictim, akCreature, "", "aggressive", iCreatureBackend)
        If stid < 0
            ; Scene never started (CTD-guard refusal or OStim failure). This return value used to be
            ; ignored: we fell into the wait loop for a scene that didn't exist and left the creature
            ; looping its pin animation FOREVER (confirmed 15:40:44 log — "REFUSED" then "entering wait
            ; loop"). Unwind like the combat-re-flare bail above, plus the explicit creature pose
            ; liberation the escape branch uses (IdleForceDefaultState alone doesn't reliably break a
            ; creature out of a paired pose). The victim stays Acheron-pacified into the re-down, so
            ; there's no targetable gap; ghost comes off because downed = vanilla mortality by design.
            _Log("[SNBaka] CreatureEscalate(" + akVictim.GetDisplayName() + "): scene never started (tid=" + stid + ") — unwinding, victim re-downed, creature pose reset")
            _ProtectNearbyAllies(akVictim, akCreature, False)
            If comp1
                _PrepGroupCompanion(comp1, False)
            EndIf
            If comp2
                _PrepGroupCompanion(comp2, False)
            EndIf
            Debug.SendAnimationEvent(akCreature, "staggerStart")
            Utility.Wait(0.3)
            Debug.SendAnimationEvent(akCreature, "IdleForceDefaultState")
            akCreature.EvaluatePackage()
            akVictim.SetGhost(False)
            StorageUtil.SetFormValue(akVictim, "SNBaka.GroundWindowAggressor", akCreature)
            _DelegateDownToAcheron(akVictim)
            UnlockBoth(akCreature, akVictim)
            Return
        EndIf
        ; [REV-177 item 5 - Oldcustard credit: the claims event now fires AFTER the
        ; refuse-guard above -- only a scene that actually started gets narrated.]
        SkyrimNetApi.RegisterEvent("baka_forced", \
            akCreature.GetDisplayName() + " overpowers the helpless " + akVictim.GetDisplayName() + " completely and claims them right there on the ground.", \
            akCreature, akVictim)
        _Log("[SNBaka] CreatureEscalate(" + akVictim.GetDisplayName() + "): _StartSexScene returned, entering wait loop")
        ; Wait for the scene to actually END before touching anything — this used to fall straight
        ; through to UnlockBoth the instant the scene was merely KICKED OFF, releasing the lock while
        ; OStim/SexLab was still mid-animation (the same "two systems fighting over one actor mid-scene"
        ; hazard _EscalationCleanup's own wait exists to avoid, on the human Escalate path).
        Utility.Wait(2.0)
        Int waited = 0
        Bool sceneCut = False
        ; Force-stop only when a REAL fight reaches the creature -- same refined rule as _ShouldAbort
        ; and the human scene path: combat STATE alone (its own faction alarm reacting to an ally
        ; attacking this very victim) doesn't count; only a live, non-downed combat target OTHER than
        ; the scene's own victim does -- that's what a genuine interceding hit produces (the creature's
        ; target switches to whoever hit it). A falmer does not kill another falmer's prey; an
        ; adventurer attacking the falmer very much still breaks the scene. The victim side isn't
        ; checked at all: they're ghosted above, nothing can land on them.
        While IsInSexAnimation(akVictim) && waited < 900 && !sceneCut   ; 15min hard cap, same as the human path
            Actor crT = akCreature.GetCombatTarget()
            If akCreature.IsInCombat() && crT && crT != akVictim && !crT.IsDead() && !crT.IsDisabled() && !_IsDownedAny(crT)
                _Log("[SNBaka] CreatureEscalate: " + akCreature.GetDisplayName() + " is in a real fight against " + crT.GetDisplayName() + " mid-scene — force-stopping")
                _StopSexScene(akVictim)
                sceneCut = True
            Else
                Utility.Wait(1.0)
                waited += 1
            EndIf
        EndWhile
        ; [L2 — docs\MALE_VICTIM_L2_TREATASSEX.md] Scene-end rollback, creature path: the creature
        ; escalation funnels through the same SkyrimNet_BakaSL.StartScene choke point, so the same
        ; TreatAsFemale override may be pending on akVictim here. Same flag-gated no-op on female
        ; scenes; same self-healing if a rollback is ever missed.
        SkyrimNet_BakaSL.ClearVictimOverride(akVictim)
        _ProtectNearbyAllies(akVictim, akCreature, False)
        ; End the scene-scoped two-way pacify on the scene actors (mirrors the PacifyActor calls at
        ; scene start). The aggressor's ONE-WAY pacify (_PacifyActor: aggression 0) stays until the
        ; victim's recovery un-pacifies the tracked threat, same as always.
        If StorageUtil.GetIntValue(PlayerRef, "SNAcheron.Present", 0) == 1
            Acheron.ReleaseActor(akCreature)
            If comp1
                Acheron.ReleaseActor(comp1)
            EndIf
            If comp2
                Acheron.ReleaseActor(comp2)
            EndIf
        EndIf
        ; Scene over: hold the ghost a few MERCY seconds more before dropping it (no spawn-kills the
        ; frame the protection ends), THEN release the scene-scoped pacify. The downed state that
        ; follows has no protection of its own by design -- vanilla mortality.
        _PostEscapeGrace(akVictim)   ; also ends the scene-scoped pacify; the re-down below re-pacifies via DefeatActor
        If comp1
            _PrepGroupCompanion(comp1, False)
        EndIf
        If comp2
            _PrepGroupCompanion(comp2, False)
        EndIf
        ; RE-DOWN after the creature scene, same as the human Escalate flow's _EscalationCleanup —
        ; missing here entirely before, which is why a victim just stood back up the moment a creature
        ; scene ended, with the creature possibly still standing right there and nothing checking for it.
        ; Re-track the creature as the aggressor for the renewed down cycle (GetCombatTarget() would find
        ; nothing, combat's long since stopped).
        If akVictim && !akVictim.IsDisabled()
            ; Clean graph reset BEFORE the re-down — OStim's own post-scene reset is async, and the
            ; expression addons fight the skeleton at this exact moment (OSED's broken node cleanup,
            ; see the error storm in the log). DefeatActor's collapse starting from a dirty graph is
            ; the intermittent "did not animate correctly after the scene" (frozen/odd pose instead
            ; of a collapse). Reset first, give the graph a beat, THEN hand them down.
            Debug.SendAnimationEvent(akVictim, "IdleForceDefaultState")
            Utility.Wait(0.5)
            StorageUtil.SetFormValue(akVictim, "SNBaka.GroundWindowAggressor", akCreature)
            _DelegateDownToAcheron(akVictim)
            ; POSE ENFORCEMENT: the delegate is async, and a graph fresh out of OStim regularly eats
            ; the native collapse — "defeated but just standing there, not moving" (confirmed report,
            ; still occurring after the pre-delegate reset alone). Give the defeat a beat to land,
            ; then force the vanilla bleedout pose; redundant when the native collapse took.
            If akVictim != PlayerRef
                Utility.Wait(1.5)
                If !akVictim.IsDead()
                    ; Respect a stored down pose (a TIED victim goes back into the captured pose,
                    ; not generic bleedout) — falls back to vanilla bleedout when none is stored.
                    String rdPose = StorageUtil.GetStringValue(akVictim, "SNBaka.DownPose", "")
                    If rdPose == ""
                        rdPose = "BleedoutStart"
                    EndIf
                    Debug.SendAnimationEvent(akVictim, rdPose)
                    _Log("[SNBaka] post-scene re-down: pose '" + rdPose + "' enforced on " + akVictim.GetDisplayName())
                EndIf
            EndIf
        EndIf
    Else
        _Log("[SNBaka] CreatureEscalate(" + akVictim.GetDisplayName() + "): NO scene — succeed/combat gate failed (see outcome line above)")
        _ProtectNearbyAllies(akVictim, akCreature, False)   ; QTE-phase bystander hold ends here on the no-scene path
        ; Struggle WON but the fight's still on: leave her DOWNED (Acheron) so a beast can finish once
        ; combat ends, instead of starting sex mid-combat. If she escaped (not succeed), normal outcome.
        ; Applies to the player too now — skipping it there was the exact bug that let a struggled-down
        ; PC just stand back up mid-combat instead of staying tracked as downed.
        If succeed
            StorageUtil.SetFormValue(akVictim, "SNBaka.GroundWindowAggressor", akCreature)
            _DelegateDownToAcheron(akVictim)
        Else
            ; Victim BROKE FREE — winning the struggle is a genuine LIBERATION for everyone (updated
            ; spec: "Joylie won and she should have been liberated from all states and be free to
            ; attack back, and the giant should aggro her again after a few seconds"). Lift Acheron,
            ; end the one-way pacify, clear the tracked aggressor; the mercy ghost (_PostEscapeGrace,
            ; already run inside the struggle/QTE helper) covers the first seconds, then hostility
            ; resumes naturally — the aggressor's aggression came back in _CleanupPair, so the fight
            ; is back on shortly after the grace.
            If downed && _IsDownedAny(akVictim)
                _ClearAcheronHold(akVictim)
            EndIf
            ; [REV-177 item 2 - Oldcustard credit, issue #2 / GS Poses fork PR f0698a3
            ; (fold-regression class: the piece was in the PR but lost in the fold)]
            ; A DOWNED victim's struggle cleanup ran _ReassertDownedProtection (still
            ; Acheron-held at that point) -- restrain + DontMove + AI hold. Release them
            ; like _ForceRecover does, or the freed victim plays her walk cycle stuck in
            ; place forever (confirmed: Jordis/Mjoll after escaping downed chaurus
            ; struggles; DontMove persists in the save). ALREADY-BROKEN SAVES keep the
            ; frozen state (no migration by design) -- the MCM panic button remains the
            ; documented workaround for saves already carrying the stuck flag.
            If akVictim != PlayerRef
                akVictim.SetRestrained(False)
                akVictim.SetDontMove(False)
                _HoldActorAI(akVictim, False)
            EndIf
            _PacifyActor(akVictim, False)
            ; Revert every "lover"-rank anti-re-aggro link touching this victim — the current pair's
            ; AND stale ones left by past cycles (they were never reverted anywhere, so past victims
            ; stayed permanently non-hostile to their aggressors: part of why the liberated Joylie
            ; stood there doing nothing, and why the giant she broke free from attacked nobody).
            _ClearAggressorBonds(akVictim)
            StorageUtil.SetFormValue(akVictim, "SNBaka.GroundWindowAggressor", None)
            akVictim.EvaluatePackage()
            ; Narrative parity: without this the LLM never learned an NPC broke free — it last heard
            ; "X pins Y down" and then silence (the "it's a bit lost" report). baka_release is the
            ; existing freed-victim eventType (HelpUp/Release use it).
            SkyrimNetApi.RegisterEvent("baka_release", \
                akVictim.GetDisplayName() + " breaks free of " + akCreature.GetDisplayName() + "'s grip and struggles back to their feet — shaken, but free and ready to fight.", \
                akVictim, akCreature)
            ; [REV-177 item 6 (minor) - Oldcustard credit, GS Poses fork PR fa1fcdb
            ; shape: escape-cue overwrite.] The live "pins ... cannot get away" scene
            ; cue (same per-aggressor ID, 25s TTL) stays live after baka_release
            ; otherwise -- for ~10s the LLM sees both. Overwrite the SAME event ID
            ; with a short break-free cue so there is no dual-cue window.
            SkyrimNetApi.RegisterShortLivedEvent("baka_scene_" + akCreature.GetFormID(), "baka_release", \
                akVictim.GetDisplayName() + " has broken free of " + akCreature.GetDisplayName() + " and is no longer held.", \
                "", 10000, akVictim, akCreature)
            _Log("[SNBaka] CreatureEscalate(" + akVictim.GetDisplayName() + "): victim broke free — fully liberated, fight may resume after the grace window")
            ; Creature LOST the struggle (victim broke free) -- explicitly make sure it's actually back
            ; on its feet and free to act, rather than just trusting PlayPairedSequence's own _CleanupPair
            ; reset to have fully taken. Belt-and-suspenders for the exact "falmer fell and got stuck"
            ; symptom reported in testing: it's the aggressor here, nothing else in this whole flow ever
            ; checks on IT specifically once it's lost, unlike the victim (who gets _DelegateDownToAcheron/
            ; Acheron's own recovery loop either way).
            ; A short beat first, per explicit feedback: firing this the SAME instant the victim's own
            ; concurrent _CleanupPair is still resolving (both threads unwind right on top of each other)
            ; is exactly the kind of race a stray stagger from still-active nearby combat can land in.
            ; Let things settle for a beat before re-asserting the pose (trimmed from 3.0s — "after
            ; winning ending, it's too long, 2 seconds are plenty" — combined with the mercy grace
            ; this keeps the whole win exit around the requested 2s).
            Utility.Wait(1.0)
            _HoldActorAI(akCreature, False)
            ; IdleForceDefaultState alone still left some creatures visibly stuck in the paired
            ; sequence's final frame (confirmed still happening in testing) -- staggerStart is the
            ; same trick _DefeatGroundWindow already relies on to force a real animation-state
            ; transition out of a held pose (see its "Stand Back" branch above), so borrow it here
            ; too instead of trusting the idle reset alone to break the graph out of it.
            Debug.SendAnimationEvent(akCreature, "staggerStart")
            Utility.Wait(0.3)
            Debug.SendAnimationEvent(akCreature, "IdleForceDefaultState")
            akCreature.EvaluatePackage()
            _Log("[SNBaka] CreatureEscalate(" + akVictim.GetDisplayName() + "): " + akCreature.GetDisplayName() + " lost the struggle -- explicit liberation (stagger + AI released, pose reset)")
        EndIf
        ; [REV-161 PR#2 fold (4) - Oldcustard credit, by-concept] ESCAPE NOT
        ; OVERPOWERED: the overpowered cue used to fire unconditionally after
        ; the If/Else, so a victim who BROKE FREE also got "X overpowered Y" --
        ; the escape branch already emits baka_release. Gate the overpowered
        ; beat on the creature actually winning the struggle.
        If succeed
            _CueResistOutcome("baka_forced", akCreature, akVictim)
        EndIf
    EndIf
    UnlockBoth(akCreature, akVictim)
EndFunction

; Player trigger: aim the interact power at a BEAST and it escalates on the nearest valid victim.
; Returns True if akCreature was a supported creature (i.e. we handled the power press), so the
; effect script knows to stop and not fall through to the normal interact menu.
Bool Function TryCreatureEscalateFromPower(Actor akCreature)
    ; [REV-177b / R-177d] NoAnim fallback accepted here; NPC-victim-only is enforced
    ; inside _DoCreatureEscalation (player victims with a placeholder key are refused there).
    If !bCreatureEscalation || !akCreature || _CreatureStruggleKey(akCreature, True) == ""
        Return False
    EndIf
    Actor victim = _FindCreatureVictim(akCreature)
    If victim
        _DoCreatureEscalation(akCreature, victim)
    Else
        _Notify("No valid victim near " + akCreature.GetDisplayName() + ".")
    EndIf
    Return True
EndFunction

; Mod-event hook from Downed SkyrimNet (Acheron path): the player just went down in combat — give a
; nearby beast the chance to pounce, since creatures have no LLM brain to choose CreatureEscalate.
; Queued (AcheronIntegration/Downed_SkyrimNet FormListAdd the fresh victim to SNBaka.CreaturePounceQueue
; before sending this event) rather than hardcoded to PlayerRef, so an NPC victim gets the same chance
; for a nearby beast to pounce that the player does — same queue-drain pattern as OnDownRequest.
Event OnTryCreatureOnDowned(String eventName, String strArg, Float numArg, Form sender)
    _Log("[SNBaka] OnTryCreatureOnDowned fired (bCreatureEscalation=" + bCreatureEscalation + " bCreatureOnPlayer=" + bCreatureOnPlayer + " strArg=" + strArg + ")")
    Int cnt = StorageUtil.FormListCount(PlayerRef, "SNBaka.CreaturePounceQueue")
    Int i = 0
    While i < cnt
        Actor v = StorageUtil.FormListGet(PlayerRef, "SNBaka.CreaturePounceQueue", i) as Actor
        If v
            _TryCreatureEscalateOnDowned(v)
        EndIf
        i += 1
    EndWhile
    StorageUtil.FormListClear(PlayerRef, "SNBaka.CreaturePounceQueue")
EndEvent

; Passive creature initiator: a human is DOWN — if the creature opt-in is on, a supported creature is
; nearby, and the chance roll passes, it takes the opportunity. Clears an Acheron bleedout first so the
; paired creature animation positions correctly.
; Combat-gated up front now (see _CombatNear check below) -- confirmed in testing that letting the
; struggle happen mid-combat and only gating the SEX portion on _CombatNear (in _DoCreatureEscalation)
; wasn't just a pacing issue: starting the OStim scene right as combat state is still settling crashed
; the game inside OStim's own AlignMenu code (null actor alignment). Waiting for combat to actually clear
; before even attempting the struggle gives the engine breathing room before OStim's thread is touched.
; The retry mechanisms already in place (Baka's own re-trigger, Acheron's periodic re-roll) mean this
; just quietly waits and tries again later instead of failing outright.
Function _TryCreatureEscalateOnDowned(Actor akVictim)
    _Log("[SNBaka] _TryCreatureEscalateOnDowned ENTER: victim=" + akVictim + " escOn=" + bCreatureEscalation + " onPlayer=" + bCreatureOnPlayer)
    If !bCreatureEscalation
        _Log("[SNBaka] creature: master switch (bCreatureEscalation) is OFF — enable it in the MCM")
        Return
    EndIf
    If !akVictim || akVictim.IsDead() || IsActorLocked(akVictim)
        _Log("[SNBaka] creature: victim none/dead/locked (locked=" + IsActorLocked(akVictim) + ")")
        Return
    EndIf
    ; REV-146a Task 2: child boundary - creature on-downed lane.
    If _ChildBoundaryRefused(None, akVictim, "CreatureOnDowned")
        Return
    EndIf
    ; SNBaka.Locked (checked above) covers scenes WE started, but a victim can be in an OStim/SexLab
    ; scene some other mod started (never Locked by us) -- explicit spec: a downed actor mid-scene is
    ; never a pounce candidate, whoever owns the scene.
    If IsInSexAnimation(akVictim)
        _Log("[SNBaka] creature: victim is in a sex scene — never a pounce candidate mid-scene")
        Return
    EndIf
    ; REV-144 4.2: central player-target policy blankets the creature pounce lane too;
    ; the aggressor is not resolved at this scan stage, so the initiator slot is None
    ; (any NPC/creature source -- the function only exempts the player as initiator).
    If akVictim == PlayerRef && (!bCreatureOnPlayer || !_PlayerTargetAdmitted(None, akVictim, "CreatureOnDowned"))
        _Log("[SNBaka] creature: player victim but bCreatureOnPlayer is OFF (or REV-144 policy OFF)")
        Return
    EndIf
    If !_IsDownedAny(akVictim)
        _Log("[SNBaka] creature: victim not downed (OnGround=" + StorageUtil.GetIntValue(akVictim, "SNBaka.OnGround", 0) + " bleeding=" + akVictim.IsBleedingOut() + " acheronHeld=" + StorageUtil.GetIntValue(akVictim, "SNAcheron.Held", 0) + ")")
        Return
    EndIf
    ; Confirmed real bug from testing: a struggle grabbing someone WHILE they're still mid down-transition
    ; (the bleedout/collapse animation hasn't settled) can break the animation state and leave them stuck
    ; perpetually "downing". SNAcheron.FreshDownRT is the shared stamp Acheron's own _CueDowned/
    ; Downed_SkyrimNet.RunConsequence set at the exact moment of a genuinely fresh down (0.0 default if
    ; Acheron isn't installed or this is a pure Baka-native down, which trivially passes this check).
    Float sinceFreshDown = Utility.GetCurrentRealTime() - StorageUtil.GetFloatValue(akVictim, "SNAcheron.FreshDownRT", 0.0)
    If sinceFreshDown < fFreshDownGraceDuration
        _Log("[SNBaka] creature: blocked — " + akVictim.GetDisplayName() + " only " + sinceFreshDown + "s since fresh down, need " + fFreshDownGraceDuration + "s to settle first")
        Return
    EndIf
    ; NOTE: deliberately NOT checking _InDefeatGrace here. That grace window exists to stop a fresh
    ; mid-combat on-hit spam from chaining a second struggle onto the first with zero breathing room
    ; (see OnCreatureHitFollower) -- it is NOT meant to also block the separate, explicitly-requested
    ; "once on the ground, still fair game to nearby proximity actors" behavior this function provides.
    ; Confirmed in testing: applying it here silently ate every downed re-consideration attempt for
    ; the whole 100s window right after a fresh takedown, exactly when a downed victim should still be
    ; up for grabs.
    ; Only the VICTIM's own live combat state gates the struggle attempt now -- an unrelated fight
    ; happening elsewhere in the cell used to block this outright (_CombatNear scanned the whole cell
    ; out to 3000 units), which meant a creature standing right next to an already-downed, defenseless
    ; victim could never even consider her while allies were still busy with a DIFFERENT enemy nearby.
    ; The actual OStim-mid-combat crash this was guarding against is a SCENE-START hazard, not a
    ; struggle hazard -- that gate still exists further down (see the _CombatNear call before
    ; _StartSexScene). The chosen candidate's own combat state is re-checked once "best" is found below.
    If _HasLiveCombatTarget(akVictim)
        _Log("[SNBaka] creature: blocked — " + akVictim.GetDisplayName() + " still has a live combat target, waiting for it to clear before even attempting")
        Return
    EndIf
    ; A beat between attempts — confirmed in testing that a "succeed but combat still near" outcome
    ; re-downs the victim, which immediately re-fires this same event with zero delay, chaining a second
    ; full struggle QTE onto the first with no breathing room at all. This throttles ANY re-entry
    ; (initial pounce, the "loop" re-check, or this kind of immediate re-trigger) to once per few seconds.
    Float now = Utility.GetCurrentRealTime()
    Float lastAttempt = StorageUtil.GetFloatValue(akVictim, "SNBaka.LastCreatureAttemptRT", 0.0)
    If _RTStampStale(lastAttempt, now)      ; [REV-161 PR#2 fold (1)] pre-relaunch stamp = expired
        lastAttempt = 0.0
    EndIf
    If (now - lastAttempt) < 3.0
        _Log("[SNBaka] creature: skipped — only " + (now - lastAttempt) + "s since last attempt, need 3.0s")
        Return
    EndIf
    StorageUtil.SetFloatValue(akVictim, "SNBaka.LastCreatureAttemptRT", now)
    Actor best        = None
    Float bestDist    = 1500.0
    ; Fast path, Yamete Redux style: whoever/whatever downed this victim is already a known reference
    ; (SNBaka.GroundWindowAggressor, set at down-time) — check it directly with GetDistance() before
    ; falling back to the cell sweep below for a DIFFERENT creature that merely wandered up afterward.
    ; Used to lead with Game.FindClosestActorFromRef for cross-cell reach, but that proved unreliable
    ; in testing (same false negative that hit _AnyActorNear).
    Actor threat = StorageUtil.GetFormValue(akVictim, "SNBaka.GroundWindowAggressor") as Actor
    ; Distance check added here — this used to accept the tracked reference unconditionally regardless
    ; of how far away it actually was, letting a creature that had wandered far off still win the "best"
    ; slot (nothing else would beat its huge bestDist unless something closer also happened to be found).
    If threat && threat != akVictim && !threat.IsDead() && !_IsDownedAny(threat) && akVictim.GetDistance(threat) < bestDist
        _Log("[SNBaka] tracked threat: '" + threat.GetDisplayName() + "' key='" + _CreatureAnimKey(threat) + "' locked=" + IsActorLocked(threat) + " dist=" + akVictim.GetDistance(threat))
        ; Check _CreatureAnimKey FIRST, not _IsCreatureActor — Falmer and Draugr are creature-behaving
        ; races that Bethesda still tags with the ActorTypeNPC keyword (the same one every human uses),
        ; so _IsCreatureActor(falmer) reads False. _CreatureAnimKey matches by actual race name and isn't
        ; fooled by that; a race-name match here means it's a supported creature no matter what keyword
        ; it carries.
        If _CreatureStruggleKey(threat, akVictim != PlayerRef) != ""
            If threat != PlayerRef && !IsActorLocked(threat)
                best     = threat
                bestDist = akVictim.GetDistance(threat)
            EndIf
        EndIf
        ; A tracked HUMANOID here is deliberately NOT a blocker anymore -- see the witness-rule removal
        ; note on the sweep below.
    EndIf
    ; LOADED-AREA enumeration (po3 Papyrus Extender), not a single-cell sweep: dens and camps span
    ; linked cells, and the victim's own parent cell repeatedly turned up empty of creatures standing
    ; right next to them (confirmed 16:03 session: every player-victim scan logged "no supported
    ; creature near Claudia" while a falmer stood in grabbing range — it was registered in a different
    ; cell, and only Joylie's tracked-aggressor fast path ever found it). Processing level 0 = every
    ; AI-active actor currently loaded, no cell dependence. The old single-closest-actor cross-cell
    ; supplement is gone with it — it only ever sampled ONE actor, usually the other downed follower.
    Actor[] loaded = PO3_SKSEFunctions.GetActorsByProcessingLevel(0)
    Int total = loaded.Length
    Int i = 0
    While i < total
        Actor a = loaded[i]
        If a && a != akVictim && a != PlayerRef && !a.IsDead()
            String ck = _CreatureStruggleKey(a, akVictim != PlayerRef)
            If ck != ""
                ; Log every nearby beast we recognise, so we can see what's around when testing.
                _Log("[SNBaka] nearby creature: '" + a.GetDisplayName() + "' key=" + ck + " inCombat=" + a.IsInCombat() + " locked=" + IsActorLocked(a) + " dist=" + a.GetDistance(akVictim))
                If !IsActorLocked(a) && a.GetDistance(akVictim) < bestDist
                    bestDist = a.GetDistance(akVictim)
                    best = a
                EndIf
            EndIf
            ; The humanoid-WITNESS rule that used to live here (any live, non-downed humanoid within
            ; 1500u blocked the attempt entirely) stays REMOVED per explicit spec — the MCM engagement
            ; chance is the only frequency throttle.
        EndIf
        i += 1
    EndWhile
    If !best
        _Log("[SNBaka] _TryCreatureEscalateOnDowned: no supported creature near " + akVictim.GetDisplayName())
        Return
    EndIf
    ; The candidate itself might still be genuinely mid-fight with someone else even though the victim
    ; (checked above) isn't -- don't pull it out of a real fight to do this.
    If _HasLiveCombatTarget(best)
        _Log("[SNBaka] _TryCreatureEscalateOnDowned: found " + best.GetDisplayName() + " but it's still actively fighting someone else")
        Return
    EndIf
    ; No success roll here anymore -- iCreatureSuccessPct is _DoCreatureEscalation's OWN roll (used for
    ; both the not-yet-downed struggle AND, now, the already-downed claim). Rolling a SEPARATE "does the
    ; creature even bother" gate here would double up with that AND with Acheron's own
    ; fCreatureEngageChance roll (the actual, correct throttle on how often this pipeline gets a shot at
    ; all) -- confirmed in testing as a victim left downed for a long time
    ; with nearby creatures repeatedly declining her purely on this redundant coin flip. A creature that
    ; actually finds and commits to an already-downed victim now always takes her, same as the guaranteed
    ; branch _DoCreatureEscalation already has for this exact case.
    ; The downed/hold state is cleared inside _DoCreatureEscalation itself, only once every one of its
    ; own gates (sex restriction, anim key, lock race, etc.) has actually passed — see its comment.
    ; LLM ESCALATION GATE (MCM opt-in): instead of committing automatically, describe the moment to
    ; SkyrimNet and let the LLM answer YES/NO from context (pacing, who's present, what just happened).
    ; Async: stash the pair, fire the prompt, continue in OnEscalationGateResponse. Fail-OPEN — an LLM
    ; outage or template failure behaves like the gate is off; it's advisory, not a kill-switch.
    If bLLMGateEscalation
        Float nowG = Utility.GetCurrentRealTime()
        If _bGatePending && (nowG - _fGateSentRT) < 30.0
            _Log("[SNBaka] _TryCreatureEscalateOnDowned: LLM gate already pending — skipping duplicate ask")
            Return
        EndIf
        _bGatePending = True
        _fGateSentRT  = nowG
        _gateCreature = best
        _gateVictim   = akVictim
        String ctx = "{\"creatureName\":\"" + best.GetDisplayName() + "\",\"victimName\":\"" + akVictim.GetDisplayName() + "\",\"maxRecentEvents\":20}"
        Int sent = SkyrimNetApi.SendCustomPromptToLLM("snbaka_escalation_gate", "", ctx, Self as Quest, "SkyrimNet_BakaIntegration", "OnEscalationGateResponse")
        _Log("[SNBaka] _TryCreatureEscalateOnDowned: LLM gate asked (" + best.GetDisplayName() + " -> " + akVictim.GetDisplayName() + "), sent=" + sent)
        If sent != 1
            _bGatePending = False
            _DoCreatureEscalation(best, akVictim)   ; couldn't even queue the ask — fail open
        EndIf
        Return
    EndIf
    _Log("[SNBaka] _TryCreatureEscalateOnDowned: " + best.GetDisplayName() + " attempts downed " + akVictim.GetDisplayName())
    _DoCreatureEscalation(best, akVictim)
EndFunction

; SendCustomPromptToLLM callback for the escalation gate (snbaka_escalation_gate.prompt asks for a
; single-word YES/NO). success 1 = real answer; 0 = render/network failure, which fails OPEN.
Function OnEscalationGateResponse(String response, Int success)
    Actor c = _gateCreature
    Actor v = _gateVictim
    _gateCreature = None
    _gateVictim   = None
    _bGatePending = False
    If !c || !v
        Return
    EndIf
    Bool allow = True
    If success == 1
        allow = StringUtil.Find(response, "YES") >= 0 || StringUtil.Find(response, "Yes") >= 0 || StringUtil.Find(response, "yes") >= 0
        _Log("[SNBaka] OnEscalationGateResponse: LLM said '" + response + "' -> allow=" + allow)
    Else
        _Log("[SNBaka] OnEscalationGateResponse: gate errored ('" + response + "') — failing OPEN")
    EndIf
    If !allow
        ; A NO backs this victim's pipeline off ~30s (vs the usual 3s retry) so the same question isn't
        ; peppered at the LLM every engagement roll. Stamping the last-attempt clock into the future
        ; extends the existing throttle without a new key.
        StorageUtil.SetFloatValue(v, "SNBaka.LastCreatureAttemptRT", Utility.GetCurrentRealTime() + 27.0)
        Return
    EndIf
    ; The answer took real seconds — re-validate the moment before committing.
    If v.IsDead() || c.IsDead() || !_IsDownedAny(v) || IsActorLocked(c) || IsActorLocked(v)
        _Log("[SNBaka] OnEscalationGateResponse: situation changed while the LLM was thinking — dropping")
        Return
    EndIf
    _DoCreatureEscalation(c, v)
EndFunction

; Native hit-event hook (HitEventSink.cpp): a creature just landed a melee hit on a player-teammate
; (follower) OR the player themselves. Unlike _TryCreatureEscalateOnDowned, this fires straight off
; the hit -- no need for the victim to be downed first, which is the whole point (mid-combat
; escalation). Aggressor resolution differs by victim: a follower has real AI combat targeting, so
; GetCombatTarget() is reliable; the player doesn't necessarily, so SNBakaUI.GetLastHitAggressor asks
; the native side for the actual hit-event cause instead (cached at the exact moment it fired).
; AND-gated: bCreatureEscalateFollowersOnHit AND bCreatureCombatAllowed here, plus bCreatureOnPlayer
; when the victim is the player, then _DoCreatureEscalation's own master switch/sex filter/lock checks
; -- every one of them has to agree, turn any single one off and this never fires. The 3s throttle is
; shared with _TryCreatureEscalateOnDowned's own (same victim, same purpose: don't chain a second full
; struggle onto the first with zero breathing room).
Event OnCreatureHitFollower(string eventName, string strArg, float numArg, Form sender)
    _Log("[SNBaka] OnCreatureHitFollower ENTER: sender=" + sender + " followerToggle=" + bCreatureEscalateFollowersOnHit + " combatAllowed=" + bCreatureCombatAllowed)
    ; Unconditional, ahead of every gate below: this native event already fires synchronously on
    ; every physical hit landing on the player, regardless of whether the creature/on-hit-escalation
    ; feature itself is even enabled. Reused as the zero-lag "player was just struck" signal the
    ; in-combat grapple takedown's abort check (_ShouldAbort) depends on -- must stamp even when the
    ; rest of this handler is about to bail on an MCM toggle below.
    If sender as Actor == PlayerRef
        _fLastPlayerHitRT = Utility.GetCurrentRealTime()
    EndIf
    If !bCreatureEscalateFollowersOnHit || !bCreatureCombatAllowed
        _Log("[SNBaka] OnCreatureHitFollower: blocked — bCreatureEscalateFollowersOnHit or bCreatureCombatAllowed is off in MCM")
        Return
    EndIf
    Actor victim = sender as Actor
    If !victim
        _Log("[SNBaka] OnCreatureHitFollower: blocked — sender wasn't an Actor")
        Return
    EndIf
    If victim.IsDead() || IsActorLocked(victim)
        _Log("[SNBaka] OnCreatureHitFollower: blocked — victim=" + victim.GetDisplayName() + " dead=" + victim.IsDead() + " locked=" + IsActorLocked(victim))
        Return
    EndIf
    If IsInSexAnimation(victim)
        _Log("[SNBaka] OnCreatureHitFollower: blocked — " + victim.GetDisplayName() + " is mid sex scene (any framework/any mod)")
        Return
    EndIf
    Bool victimIsPlayer = (victim == PlayerRef)
    ; REV-144 4.2: central policy consulted alongside the creature toggle; the aggressor
    ; is resolved later in this handler, so the initiator slot is None at this check.
    If victimIsPlayer && (!bCreatureOnPlayer || !_PlayerTargetAdmitted(None, victim, "CreatureHitFollower"))
        _Log("[SNBaka] OnCreatureHitFollower: blocked — player victim, bCreatureOnPlayer OFF or REV-144 policy OFF")
        Return
    EndIf
    If _InDefeatGrace(victim)
        _Log("[SNBaka] OnCreatureHitFollower: blocked — " + victim.GetDisplayName() + " is still in their post-defeat grace window")
        Return
    EndIf
    ; GetCombatTarget() first for a follower (usually right, no native round-trip needed) but fall back
    ; to the native hit-cache either way -- confirmed in testing that a follower JUST released from a
    ; struggle/pairing can read a stale/empty GetCombatTarget() for a beat even though a fresh hit just
    ; landed (StopCombat()-heavy cleanup a moment earlier hadn't been re-acquired by AI yet). The native
    ; cache is ground truth from the actual hit event regardless of victim type.
    Actor aggressor = None
    If !victimIsPlayer
        aggressor = victim.GetCombatTarget()
    EndIf
    If !aggressor
        aggressor = SNBakaUI.GetLastHitAggressor(victim)
    EndIf
    If !aggressor
        _Log("[SNBaka] OnCreatureHitFollower: blocked — could not resolve an aggressor for " + victim.GetDisplayName())
        Return
    EndIf
    If aggressor.IsDead()
        _Log("[SNBaka] OnCreatureHitFollower: blocked — aggressor=" + aggressor.GetDisplayName() + " is dead")
        Return
    EndIf
    ; Which pipeline handles this aggressor? A supported creature takes the creature path below; a
    ; HUMANOID takes the human on-hit path (own MCM toggle/chance, dispatches to the ordinary Struggle
    ; action); an unsupported creature type (horker, rabbit...) takes neither.
    String aggKey = _CreatureStruggleKey(aggressor, victim != PlayerRef)
    Bool humanPath = False
    If aggKey == ""
        If !bHumanEscalateOnHit || _IsCreatureActor(aggressor)
            _Log("[SNBaka] OnCreatureHitFollower: blocked — aggressor=" + aggressor.GetDisplayName() + " not a supported creature (humanOnHit=" + bHumanEscalateOnHit + " isCreature=" + _IsCreatureActor(aggressor) + ")")
            Return
        EndIf
        If _IsDownedAny(aggressor) || IsActorLocked(aggressor)
            _Log("[SNBaka] OnCreatureHitFollower: blocked — humanoid aggressor " + aggressor.GetDisplayName() + " is downed/locked")
            Return
        EndIf
        ; Friendly-fire guard, humanoid path only -- the native hit sink fires for ANY non-player
        ; aggressor, and the log shows followers landing stray hits on each other mid-melee (Joylie
        ; showing up as "aggressor" against Claudia). A creature reaching this handler is essentially
        ; always a real enemy; a humanoid needs the actual hostility check or allies would grapple
        ; each other off accidental hits.
        If !aggressor.IsHostileToActor(victim)
            _Log("[SNBaka] OnCreatureHitFollower: blocked — humanoid " + aggressor.GetDisplayName() + " is not hostile to " + victim.GetDisplayName() + " (stray/friendly hit)")
            Return
        EndIf
        humanPath = True
    EndIf
    ; Player + OStim-buggy-combat carve-out: OStim can crash if combat resettles while its own thread
    ; is running (confirmed via CrashLoggerSSE earlier), so for the player specifically, when OStim
    ; would be the resolved backend, don't even ATTEMPT the struggle while combat is still live for
    ; them -- wait for it to clear first. NPCs, and player+SexLab, keep the existing behavior: the
    ; struggle can start mid-combat, only the SCENE itself waits for combat to clear (_CombatNear
    ; before _StartSexScene). Creature-path only: a human struggle never chains straight into a scene
    ; (a lost struggle ends in the ground window; the scene needs a separate, already combat-gated
    ; Escalate), so there's no OStim thread at risk on that path.
    If !humanPath && victimIsPlayer && _ResolveSexBackend(iCreatureBackend) == 2 && _HasLiveCombatTarget(victim)
        _Log("[SNBaka] OnCreatureHitFollower: blocked — player + OStim backend, waiting for combat to clear first")
        Return
    EndIf
    ; Shared per-victim throttle across BOTH paths (same key), so a creature and a human can't chain
    ; grabs on the same victim back-to-back.
    Float now = Utility.GetCurrentRealTime()
    Float lastAttempt = StorageUtil.GetFloatValue(victim, "SNBaka.LastCreatureAttemptRT", 0.0)
    If _RTStampStale(lastAttempt, now)      ; [REV-161 PR#2 fold (1)] pre-relaunch stamp = expired
        lastAttempt = 0.0
    EndIf
    If (now - lastAttempt) < 3.0
        _Log("[SNBaka] OnCreatureHitFollower: blocked — only " + (now - lastAttempt) + "s since last attempt on " + victim.GetDisplayName() + ", need 3.0s")
        Return
    EndIf
    StorageUtil.SetFloatValue(victim, "SNBaka.LastCreatureAttemptRT", now)
    Int need = iCreatureHitEngageChance
    If humanPath
        need = iHumanHitEngageChance
    EndIf
    Int roll = Utility.RandomInt(1, 100)
    If roll > need
        _Log("[SNBaka] OnCreatureHitFollower: skipped by chance roll — rolled " + roll + ", need <= " + need + " (humanPath=" + humanPath + ")")
        Return
    EndIf
    If humanPath
        _Log("[SNBaka] OnCreatureHitFollower: humanoid " + aggressor.GetDisplayName() + " hit " + victim.GetDisplayName() + " -- attempting mid-combat Struggle (rolled " + roll + ")")
        ; The ordinary Struggle action: QTE for a player victim, timed roll for NPCs, ground window on
        ; a loss -- every existing Struggle gate (IsEligible: master switch, sex filter, player-target
        ; permission, locks) still applies and traces its own rejection if it blocks. abFromHit=True
        ; relaxes only IsEligible's attacker-in-combat gate, which would otherwise reject every on-hit
        ; attempt by definition (the attacker just landed a combat hit).
        Struggle_Execute(aggressor, victim, True)
    Else
        _Log("[SNBaka] OnCreatureHitFollower: " + aggressor.GetDisplayName() + " hit " + victim.GetDisplayName() + " -- attempting mid-combat escalation (rolled " + roll + ")")
        _DoCreatureEscalation(aggressor, victim)
    EndIf
EndEvent

; Nearest valid human near the creature: not a creature, alive, victim-sex allowed, player only if
; permitted, and (when combat escalation is off) already downed/bleeding out.
Actor Function _FindCreatureVictim(Actor akCreature)
    Cell c = akCreature.GetParentCell()
    If !c
        Return None
    EndIf
    Bool needDowned = !bCreatureCombatAllowed
    Actor best     = None
    Float bestDist = 99999.0
    Int total = c.GetNumRefs(62)
    Int i = 0
    While i < total
        Actor a = c.GetNthRef(i, 62) as Actor
        If a && a != akCreature && !a.IsDead() && _CreatureAnimKey(a) == ""
            Bool ok = True
            ; REV-144 4.2: the candidate scan consults the central policy alongside the
            ; creature toggle (the policy blankets every player-target admission site).
            If a == PlayerRef && (!bCreatureOnPlayer || !_PlayerTargetAdmitted(akCreature, a, "FindCreatureVictim"))
                ok = False
            EndIf
            If ok
                Bool female = _SexOf(a) == 1
                ; 0 = Both, 1 = Female only, 2 = Male only (same scheme as iTargetSex).
                If (iCreatureVictimSex == 1 && !female) || (iCreatureVictimSex == 2 && female)
                    ok = False
                EndIf
            EndIf
            If ok && needDowned
                If !_IsDownedAny(a)
                    ok = False
                EndIf
            EndIf
            If ok
                Float d = akCreature.GetDistance(a)
                If d < bestDist
                    bestDist = d
                    best = a
                EndIf
            EndIf
        EndIf
        i += 1
    EndWhile
    Return best
EndFunction

; ============================================================
; SOLO POSES (SNBaka_Pose) — single-actor, LLM-driven idle / gesture / submission
; ============================================================
; Play one anim event on an NPC and hold it (re-asserted each tick) for fSoloPoseDuration, ending
; early on combat or death. Mirrors the paired-hold approach but for a single actor, no positioning.
; bLockMove = SetDontMove (for kneel/grovel a bump shouldn't break). Never the player.
; cueDesc: confirmed live gap -- EVERY solo pose (Kneel/Dogeza/Meditate/.../Aroused/Drink/Food, 14 of
; the 15 total pose variants) funnels through this one function, and it never told SkyrimNet/the LLM
; anything -- pure animation, no narration, ever. An LLM only knows what it's told; a silent pose is
; invisible to it. Fixed once here instead of in each of the ~15 callers. "" (default) skips the cue
; for any future caller that genuinely wants a silent hold.
Function _PlaySoloHold(Actor ak, String animEvent, Bool bLockMove = False, String cueDesc = "")
    If !ak || ak == PlayerRef || ak.IsDead() || ak.IsInCombat()
        Return
    EndIf
    If cueDesc != ""
        SkyrimNetApi.RegisterEvent("baka_pose", cueDesc, ak, None)
    EndIf
    _HoldActorAI(ak, True)
    _PacifyActor(ak, True)
    ak.SetRestrained(True)
    If bLockMove
        ak.SetDontMove(True)
    EndIf
    Debug.SendAnimationEvent(ak, "IdleForceDefaultState")
    Utility.Wait(0.15)
    Float elapsed = 0.0
    Float tick    = 2.0
    Bool aborted  = False
    While elapsed < fSoloPoseDuration && !aborted
        Debug.SendAnimationEvent(ak, animEvent)              ; re-assert so nothing drifts them off it
        Float step = tick
        If elapsed + step > fSoloPoseDuration
            step = fSoloPoseDuration - elapsed
        EndIf
        ; _WaitOrAbort polls _ShouldAbort every 0.5s: death, disabled, combat (attacked), teleport, stop.
        aborted = _WaitOrAbort(ak, ak, step)
        elapsed += step
    EndWhile
    ; Cleanup ALWAYS runs (incl. on abort/death) so the actor is never left restrained/pacified/ghosted.
    ak.SetRestrained(False)
    If bLockMove
        ak.SetDontMove(False)
    EndIf
    _PacifyActor(ak, False)
    _HoldActorAI(ak, False)
    Debug.SendAnimationEvent(ak, "IdleForceDefaultState")
    ak.EvaluatePackage()
EndFunction

; --- SkyrimNet pose actions ---
; Split from the old single-YAML "Pose(poseName)" dispatcher into one action per pose (matching
; AnimationsGS's own per-pose YAML structure) so each can carry its OWN eligibilityRules instead of
; all 15 being forced to share one block -- e.g. gating Aroused behind an arousal check without
; touching Meditate. Each YAML's executionFunctionName points directly at one of these.
Function PoseKneel_Execute(Actor akInitiator)
    _Log("[SNBakaACT] PoseKneel ENTER")
    RecordAnimation(akInitiator, "PoseKneel", "")
    _PlaySoloHold(akInitiator, "Babo_Kneel", True, akInitiator.GetDisplayName() + " kneels.")
EndFunction

Function PoseDogeza_Execute(Actor akInitiator)
    _Log("[SNBakaACT] PoseDogeza ENTER")
    RecordAnimation(akInitiator, "PoseDogeza", "")
    _PlaySoloHold(akInitiator, "Babo_Dogeja", True, akInitiator.GetDisplayName() + " drops into a full grovelling bow, forehead to the floor.")
EndFunction

Function PoseMeditate_Execute(Actor akInitiator)
    _Log("[SNBakaACT] PoseMeditate ENTER")
    RecordAnimation(akInitiator, "PoseMeditate", "")
    _PlaySoloHold(akInitiator, "BaboMeditate", False, akInitiator.GetDisplayName() + " settles into a quiet, meditative pose.")
EndFunction

Function PoseCrouch_Execute(Actor akInitiator)
    _Log("[SNBakaACT] PoseCrouch ENTER")
    RecordAnimation(akInitiator, "PoseCrouch", "")
    _PlaySoloHold(akInitiator, "BaboCrouchM", False, akInitiator.GetDisplayName() + " crouches low.")
EndFunction

Function PoseSleep_Execute(Actor akInitiator)
    _Log("[SNBakaACT] PoseSleep ENTER")
    RecordAnimation(akInitiator, "PoseSleep", "")
    _PlaySoloHold(akInitiator, "BaboSleeponBedRoll", True, akInitiator.GetDisplayName() + " beds down to sleep.")
EndFunction

Function PoseScratchHead_Execute(Actor akInitiator)
    _Log("[SNBakaACT] PoseScratchHead ENTER")
    RecordAnimation(akInitiator, "PoseScratchHead", "")
    _PlaySoloHold(akInitiator, "BaboIdleScratchingHead", False, akInitiator.GetDisplayName() + " scratches at their head, looking unsure.")
EndFunction

Function PoseBraceArm_Execute(Actor akInitiator)
    _Log("[SNBakaACT] PoseBraceArm ENTER")
    RecordAnimation(akInitiator, "PoseBraceArm", "")
    _PlaySoloHold(akInitiator, "BaboIdleHoldon", False, akInitiator.GetDisplayName() + " braces an arm, tense and uneasy.")
EndFunction

Function PoseHandOnFace_Execute(Actor akInitiator)
    _Log("[SNBakaACT] PoseHandOnFace ENTER")
    RecordAnimation(akInitiator, "PoseHandOnFace", "")
    _PlaySoloHold(akInitiator, "BaboHandonFace", False, akInitiator.GetDisplayName() + " brings a hand to their face, overwhelmed.")
EndFunction

Function PoseHandOnChin_Execute(Actor akInitiator)
    _Log("[SNBakaACT] PoseHandOnChin ENTER")
    RecordAnimation(akInitiator, "PoseHandOnChin", "")
    _PlaySoloHold(akInitiator, "BaboHandonChin", False, akInitiator.GetDisplayName() + " rests a hand on their chin, thinking it over.")
EndFunction

Function PoseDrool_Execute(Actor akInitiator)
    _Log("[SNBakaACT] PoseDrool ENTER")
    RecordAnimation(akInitiator, "PoseDrool", "")
    _PlaySoloHold(akInitiator, "BaboDroolingFace", False, akInitiator.GetDisplayName() + " stares off, slack-jawed and dazed.")
EndFunction

Function PoseAutograph_Execute(Actor akInitiator)
    _Log("[SNBakaACT] PoseAutograph ENTER")
    RecordAnimation(akInitiator, "PoseAutograph", "")
    _PlaySoloHold(akInitiator, "BaboAutograph", False, akInitiator.GetDisplayName() + " mimes signing an autograph.")
EndFunction

Function PosePickpocket_Execute(Actor akInitiator)
    _Log("[SNBakaACT] PosePickpocket ENTER")
    RecordAnimation(akInitiator, "PosePickpocket", "")
    _PlaySoloHold(akInitiator, "BaboExPocketPullout", False, akInitiator.GetDisplayName() + " slips a hand toward a pocket or pouch.")
EndFunction

; Arousal idle — gendered clip (male/female variants), random of two.
Function PoseAroused_Execute(Actor akInitiator)
    _Log("[SNBakaACT] PoseAroused ENTER")
    RecordAnimation(akInitiator, "PoseAroused", "")
    String ev
    If _SexOf(akInitiator) == 1   ; female
        If Utility.RandomInt(1, 2) == 1
            ev = "BaboArousedFemale01"
        Else
            ev = "BaboArousedFemale02"
        EndIf
    Else
        If Utility.RandomInt(1, 2) == 1
            ev = "BaboArousedMale01"
        Else
            ev = "BaboArousedMale02"
        EndIf
    EndIf
    _PlaySoloHold(akInitiator, ev, False, akInitiator.GetDisplayName() + " shifts restlessly, visibly aroused.")
EndFunction

; Drink (female): normally just a drinking idle, but with iDrinkBlackoutChance% she drinks herself
; into a stupor and slumps unconscious — pacified + held, and a baka_opportunity cue invites a nearby
; malicious NPC's DrunkExploit / the player's power. (Blackout is a Start->Loop sequence, so it is sent
; ONCE and held without re-asserting — _PlaySoloHold's per-tick re-assert would restart the intro.)
Function PoseDrink_Execute(Actor akInitiator)
    _Log("[SNBakaACT] PoseDrink ENTER")
    If !akInitiator || !HasFemaleBody(akInitiator) || akInitiator == PlayerRef
        Return
    EndIf
    RecordAnimation(akInitiator, "PoseDrink", "")
    If Utility.RandomInt(1, 100) <= iDrinkBlackoutChance
        SkyrimNetApi.RegisterEvent("baka_opportunity", \
            akInitiator.GetDisplayName() + " has drunk herself into a stupor and slumped down — helpless, defenseless and unaware.", \
            akInitiator, None)
        _HoldActorAI(akInitiator, True)
        _PacifyActor(akInitiator, True)
        akInitiator.SetRestrained(True)
        akInitiator.SetDontMove(True)
        Debug.SendAnimationEvent(akInitiator, "IdleForceDefaultState")
        Utility.Wait(0.15)
        ; REV-145 3.7: the drunk-state stamp of record (write at the blackout site,
        ; clear at the recovery leg below) -- the daemon drunk read rides this key.
        StorageUtil.SetIntValue(akInitiator, "SNBaka.DrunkBlackout", 1)
        Debug.SendAnimationEvent(akInitiator, "BaboDrinkBlackOut")   ; Start -> BlackOutLoop; held, not re-asserted
        _WaitOrAbort(akInitiator, akInitiator, fSoloPoseDuration)
        akInitiator.SetRestrained(False)
        akInitiator.SetDontMove(False)
        _PacifyActor(akInitiator, False)
        _HoldActorAI(akInitiator, False)
        Debug.SendAnimationEvent(akInitiator, "IdleForceDefaultState")
        StorageUtil.SetIntValue(akInitiator, "SNBaka.DrunkBlackout", 0)   ; REV-145 3.7: recovery leg clears the stamp
        akInitiator.EvaluatePackage()
    Else
        _PlaySoloHold(akInitiator, "BaboDrinkNormal", False, akInitiator.GetDisplayName() + " takes a drink.")
    EndIf
EndFunction

; Food (female): a reaction idle — eats anyway, or recoils in disgust (random). Pure flavor.
Function PoseFood_Execute(Actor akInitiator)
    _Log("[SNBakaACT] PoseFood ENTER")
    If !akInitiator || !HasFemaleBody(akInitiator)
        Return
    EndIf
    RecordAnimation(akInitiator, "PoseFood", "")
    String ev = "Babo_FoodEatAnyway"
    String desc = akInitiator.GetDisplayName() + " eats what's put in front of them despite themselves."
    If Utility.RandomInt(1, 2) == 2
        ev = "Babo_FoodDisgusting"
        desc = akInitiator.GetDisplayName() + " recoils from the food in disgust."
    EndIf
    _PlaySoloHold(akInitiator, ev, False, desc)
EndFunction

; ============================================================
; SPANK SYSTEM (merged from SkyrimNet_SlapDaButt)
; ============================================================

; ---- Tat fade timer ----
; Decorators live in SkyrimNet's runtime memory and are NOT saved with the game, so they
; must be re-asserted on every load. The quest's OnPlayerLoadGame never fires (Quest scripts
; don't receive it), so we re-register here from the persistent game-time heartbeat below as
; well as on first init. RegisterDecorator is idempotent, so re-calling is harmless.
; Mod-event listeners (RegisterForModEvent) do NOT persist across save/load and Setup()'s
; OnPlayerLoadGame doesn't fire on a Quest — so, like the decorators, they must be re-asserted from the
; persistent game-time self-heal (OnUpdateGameTime). Without this the creature hand-off (and AEL/menu
; events) silently stop working after the first reload. Idempotent, so re-calling is harmless.
Function _RegisterModEvents()
    RegisterForModEvent("AEL_GameEnd",                "OnAELGameEnd")
    RegisterForModEvent("SNBaka_MenuChoice",          "OnSNBakaMenuChoice")
    RegisterForModEvent("SNBaka_TryCreatureOnDowned", "OnTryCreatureOnDowned")
    RegisterForModEvent("SNBaka_CreatureHitFollower", "OnCreatureHitFollower")
    RegisterForModEvent("SNAcheron_RequestForceRecover", "OnAcheronForceRecoverRequest")
    RegisterForModEvent("SNBaka_DefeatedExecuted",       "OnDefeatedExecuted")
    ; Mirrors SNAcheron.Present (set by the Acheron bridge) — lets Acheron's standalone install detect
    ; whether we're actually here to answer SNBaka_TryCreatureOnDowned before it bothers waiting on us.
    If PlayerRef
        StorageUtil.SetIntValue(PlayerRef, "SNBaka.Present", 1)
        _Log("[SNBaka] _RegisterModEvents: SNBaka.Present set to 1 on " + PlayerRef + " (readback=" + StorageUtil.GetIntValue(PlayerRef, "SNBaka.Present", -99) + ")")
    Else
        _Log("[SNBaka] _RegisterModEvents: PlayerRef is None -- SNBaka.Present NOT set this call")
    EndIf
    ; REV-61 1a — Acheron bridge liveness re-stamp (per load + heartbeat): SNAcheron.Present
    ; is written by the BRIDGE and persists in the cosave, so it can outlive the bridge mod
    ; being disabled (09-30 Frabbi incident root cause). _RegisterModEvents is re-run from
    ; Setup() on every OnInit/OnPlayerLoadGame/MCM reload + the OnUpdateGameTime heartbeat,
    ; so this is the per-load re-stamp surface: if the bridge esp is not in the load order
    ; NOW, clear the stale flag. We only ever CLEAR — setting it is the bridge's job when it
    ; is actually loaded. _DelegateDownToAcheron carries an independent runtime probe as
    ; belt-and-braces, so a stale value can never route a delegation into the void.
    If PlayerRef && StorageUtil.GetIntValue(PlayerRef, "SNAcheron.Present", 0) == 1 \
            && !_AcheronBridgePresent()
        StorageUtil.SetIntValue(PlayerRef, "SNAcheron.Present", 0)
        _Log("[SNBaka] Acheron bridge: esp probe failed at re-registration — stale SNAcheron.Present cleared to 0 (local downed fallback owns this session)")
    EndIf
    ; REV-63 detection + inflation triggers (see the DETECTION TRIGGERS section
    ; near the tail of this file). Registered unconditionally; every handler is
    ; presence- and toggle-gated, and registering for an event nobody sends is
    ; harmless (OCum/FHU/SexLab all optional — listeners idle, no error spam).
    RegisterForModEvent("ocum_applied_cum",           "OnOCumApplied")
    RegisterForModEvent("ocum_applied_cum_npc_scene", "OnOCumAppliedNPCScene")
    RegisterForModEvent("HookStageEnd",               "OnSLStageEnd")
    ; REV-133c: HookAnimationEnd arm RETIRED (aftermath rider 2.5b).
    ; REV-149: HookAnimationStart + HookAnimationEnd RE-ARMED for the FHU v2
    ; entry-capture bracket (capture at AnimationStart, stash clear at
    ; AnimationEnd -- user-ruled mid-REV-149; distinct purpose from the retired
    ; aftermath arm, whose handler name is NOT reused).
    RegisterForModEvent("HookAnimationStart",         "OnSLAnimationStart")
    RegisterForModEvent("HookAnimationEnd",           "OnSLAnimationEnd")
    RegisterForModEvent("sr.inflater.start",          "OnFHUStartSignal")
    ; REV-117 cum-v2: the P+ push-time location signal (SexLabApplyCumFX,
    ; 3-push ModEvent: TargetRef, SourceRef, aiType) and the DLL's ambient
    ; timer callback (4-slot service shape). Both idled harmlessly when absent
    ; (vanilla SL never sends the former; the DLL absent = no timer emission).
    RegisterForModEvent("SexLabApplyCumFX",           "OnSLApplyCumFX")
    RegisterForModEvent("sdb_cum_ambient_due",        "OnCumAmbientDue")
    ; REV-133c Task 2.3: the bath-completion surface -- SLACS-2's
    ; Dirty_BathingQuest fires DnB_CleanActorDirt with the bathing actor as
    ; the single Form push (source-verified: SLACS_2_SCO_v079_5
    ; Scripts\Source\Dirty_BathingQuest.psc L140-145). Presence-gated (the
    ; 0171 Game.IsPluginInstalled convention); absent plugin = never fires.
    If Game.IsPluginInstalled("SLACS_2_Plus_SCO.esp")
        RegisterForModEvent("DnB_CleanActorDirt", "OnDnBCleanActorDirt")
    EndIf
    ; REV-155: the OStim climax lane -- OStim's native per-orgasm broadcast
    ; ("ostim_actor_orgasm", 4-slot payload: eventName, SceneID:String,
    ; ThreadID:Float, OrgasmedActor:Form). Presence-gated per the 0171
    ; convention (OStim.esp absent = event never sent = listener idle); the
    ; driver body is module-owned (SNBaka_FHUInflationModule.HandleOStimOrgasm,
    ; which carries its own FHU presence + ocummale double-fire guards).
    If Game.IsPluginInstalled("OStim.esp")
        RegisterForModEvent("ostim_actor_orgasm", "OnOStimActorOrgasm")
    EndIf
    _Log("[SNBaka] _RegisterModEvents: REV-65 detection triggers armed (OCum x2 [5-arg + 6-arg npc_scene], SL HookStageEnd [2-arg], FHU start [0-arg]) + REV-117 cum-v2 (P+ ApplyCumFX [3-arg], ambient due [4-slot]) + REV-149 FHU entry-capture (AnimationStart/End [2-arg]) + REV-155 OStim climax (ostim_actor_orgasm [4-slot, presence-gated])")
    ; REV-116 instrumentation (report-only; PROJECT_STATE 125 open item): the
    ; arm-time gate ECHO -- what the detection gates are RIGHT NOW, so MCM
    ; user-values vs ModEvent-delivery becomes distinguishable from logs.
    ; Log-only; zero behavior change.
    _Log("[SNBaka] detection gates at arm (REV-116 instrument): bEnabled=" + bEnabled + " bCumDetectionEnabled=" + bCumDetectionEnabled + " bSLProxyEnabled=" + bSLProxyEnabled + " bFHUInflationEnabled=" + bFHUInflationEnabled + " BakaSL.Installed=" + SkyrimNet_BakaSL.Installed())
EndFunction

; ============================================================
; MODULE LIFECYCLE SURFACE (REV-68, Phase B — §67 module contract of record)
; ============================================================
; The motherboard owns the arm/disarm/handshake sequence for the unified
; integration's modules. Under the Option-B amendment (fomod.md contract
; section): BakaSL is a recordless module and gets its handshake here (it
; registers nothing); the Acheron bridge KEEPS its quest Form + own esp (its raw
; down/release listeners at bridge L91-92 are a recorded deviation) and receives
; a presence-gated EnsureAlive() nudge — the bridge's own documented no-op when
; already ticking; GS Poses self-registers only its own INTERNAL events (not
; foreign events), so it gets a log-only presence probe. Armed from Setup()
; right after _RegisterModEvents() and re-asserted from the OnUpdateGameTime
; heartbeat — the same self-heal cadence that keeps the listeners alive across
; loads. Idempotent: safe to call as often as the listeners re-register.
Function _ArmModules()
    _Log("[SNBaka] module-arm: SexLab handshake — installed=" + SkyrimNet_BakaSL.Installed())
    ; REV-98b Amendment 3 (Option C, user-ruled 2026-10-12): presence and manager are DIFFERENT
    ; questions at DIFFERENT forms. Presence = the esp's 0x800 Downed worker quest resolving
    ; (un-cast probe via IsAcheronBridgeInstalled(), unchanged — 0x800 binds the Acheron
    ; consequence YAMLs and stays exactly as-is). Manager = the esp-attached manager script
    ; on QUST 0x801 (second script entry, 0 props, DNAM 11 start-game-enabled; attached since
    ; the REV-62 fold). REV-96's "manager has no esp host form" finding is WITHDRAWN
    ; (objectFormat-2 decode error; enumeration receipts in PROJECT_STATE §104); the old
    ; 0x800 cast here was a wrong-form cast — effectively a no-op. Retargeted to 0x801,
    ; EnsureAlive() is functional (the bridge's documented idempotent no-op when ticking).
    If !IsAcheronBridgeInstalled()
        _Log("[SNBaka] module-arm: Acheron bridge NOT installed (esp absent from load order — Option-B clause: keeps own Form/esp until the scheduled esp-unification phase)")
    Else
        SkyrimNet_AcheronIntegration bridge = Game.GetFormFromFile(0x801, "SkyrimNet_AcheronIntegration.esp") as SkyrimNet_AcheronIntegration
        If bridge
            _Log("[SNBaka] module-arm: Acheron bridge installed + manager instance live (host 0x801) — nudging EnsureAlive()")
            bridge.EnsureAlive()
        Else
            _Log("[SNBaka] module-arm: Acheron bridge INSTALLED but manager instance ABSENT at host 0x801 (unexpected — esp attaches the manager there since the REV-62 fold; report if seen) — EnsureAlive() nudge skipped (no-op sentinel)")
        EndIf
    EndIf
    _Log("[SNBaka] module-arm: GS Poses presence=" + _GSPresent())
    SNBaka_SlaveTatsModule.Arm()
    ; REV-74 rider 1 — motherboard service registry (first service: tattoo.picker). Hosts
    ; (this quest, the downed menu) presence-probe the registry and CALL the service; the
    ; module owns all logic. Entry-point services are presence-gated; hosts never contain
    ; guest logic (module-contract clause, recorded in fomod.md at ship).
    _RegisterService("tattoo.picker", SNBaka_SlaveTatsModule.Installed())
    ; REV-103 S3: the pose.baka-half advertisement — the GS psc's T2 loops probe this
    ; before touching the 15 Baka-hosted pose actions (the 27-name dispatch guard).
    ; Present = unconditional True: the motherboard quest hosting this code IS the Baka
    ; half. Re-asserted every arm pass (Setup + heartbeat), same as every registry entry.
    _RegisterService("pose.baka-half", True)
    ; REV-105 S2: the busy-state advertisement — GS's _IsBusyElsewhere probes this
    ; before consulting the SNBaka.Locked/OnGround keys (era doc 5.2 S2: the key
    ; names stay the wire format — zero save migration; a contract over the existing
    ; soft reads, not a new interface). Present = unconditional True for the same
    ; reason as the pose entry: the motherboard hosting this code IS the Baka half
    ; that writes those keys. Re-asserted every arm pass (Setup + heartbeat).
    _RegisterService("busy.baka-half", True)
    ; REV-117 cum-v2: state-layer arm (DeDService cum.* family + ambient timer
    ; rule). Self-gating (inert + logged when the DLL is absent); idempotent.
    SNBaka_CumDetectionModule.ArmStateLayer(Self)
    ; REV-157: the FHU prompt-layer decorators (get_ded_inflation +
    ; get_ded_inflation_any, the 0175/132b registration class) -- module-
    ; owned, idempotent every arm pass, host pointer cached so the band
    ; floors read the MCM sliders.
    SNBaka_FHUInflationModule.ArmDecorators(Self)
    _Log("[SNBaka] module-arm: arm pass complete")
EndFunction

; --- REV-74 rider 1: minimal service registry (register / probe / call) -------------------
; Contract-shaped and deliberately tiny — this is the mechanism, not a framework: a service
; id maps to a presence flag on this quest's StorageUtil namespace. The CALL leg stays a
; direct Papyrus call at the host site (the module's Globals); the registry answers only
; "is this service present right now?" so hosts never embed guest knowledge. Re-registered
; on every _ArmModules pass (Setup + heartbeat self-heal) — presence is never stale.
Function _RegisterService(String asServiceId, Bool abPresent)
    StorageUtil.SetIntValue(Self, "SNBaka.Svc." + asServiceId, abPresent as Int)
    _Log("[SNBaka] service-registry: '" + asServiceId + "' present=" + abPresent)
EndFunction

Bool Function _ProbeService(String asServiceId)
    Return StorageUtil.GetIntValue(Self, "SNBaka.Svc." + asServiceId, 0) == 1
EndFunction

; Disarm counterpart (REV-68), reserved by the module contract so later modules
; never grow ad-hoc teardown elsewhere. Advisory-only at this rev: no Phase-B
; module requires hard teardown (the bridge's registrations live and die with
; its own quest Form; BakaSL holds none). NOT wired into Setup()/heartbeat —
; call sites arrive with the first module that actually needs teardown (e.g. the
; MCM panic path in a later phase).
Function _DisarmModules()
    _Log("[SNBaka] module-disarm: advisory only at REV-68 (no module requires hard teardown)")
EndFunction

; Acheron's player self-recovery QTE (hold-key) asks us to force-recover an actor it can't fully clean
; up itself (e.g. it was Baka's own local ground window holding them, not an Acheron hold) — same
; queue-drain pattern as every other cross-mod request here. _ForceRecover is a no-op if the actor
; wasn't downed by us in the first place, so this is safe to call regardless of who actually held them.
; Native hit sink (HitEventSink.cpp): a PHYSICAL hit landed on an Acheron-DEFEATED non-player actor.
; Vanilla-mortality spec for the helpless — a deliberate strike on a defeated body kills it. The kill
; is applied HERE (not natively) so the remaining protections still count: essential/protected actors
; survive (Actor.Kill respects the essential flag), and anyone locked in one of our interactions or a
; sex scene is exempt (their ghost normally stops the hit ever registering; belt and suspenders).
Event OnDefeatedExecuted(String eventName, String strArg, Float numArg, Form sender)
    Actor victim = sender as Actor
    If !victim || victim.IsDead() || victim == PlayerRef
        Return
    EndIf
    If IsActorLocked(victim) || IsInSexAnimation(victim)
        Return
    EndIf
    _Log("[SNBaka] OnDefeatedExecuted: " + victim.GetDisplayName() + " takes a killing blow while defeated")
    SkyrimNetApi.RegisterEvent("baka_execution", \
        victim.GetDisplayName() + " is struck while lying defeated on the ground — the blow is final.", \
        None, victim)
    StorageUtil.SetIntValue(victim, "SNAcheron.Held", 0)   ; release our claim so nothing fights the corpse
    victim.Kill(None)
    Utility.Wait(0.5)
    _Log("[SNBaka] OnDefeatedExecuted: post-kill IsDead=" + victim.IsDead() + " (False here = something blocks Kill, e.g. an essential flag)")
EndEvent

Event OnAcheronForceRecoverRequest(String eventName, String strArg, Float numArg, Form sender)
    Int cnt = StorageUtil.FormListCount(PlayerRef, "SNAcheron.ForceRecoverQueue")
    Int i = 0
    While i < cnt
        Actor a = StorageUtil.FormListGet(PlayerRef, "SNAcheron.ForceRecoverQueue", i) as Actor
        If a
            _ForceRecover(a)
        EndIf
        i += 1
    EndWhile
    StorageUtil.FormListClear(PlayerRef, "SNAcheron.ForceRecoverQueue")
EndEvent

; REMOVED: the OnHunterPrideChoice listener for Acheron Integration's custom "Hunter's Pride" options
; (Escalate/Investigate/Inspect/Stand Back/Help Up added to Acheron's own native E/activate menu) —
; that registration was removed on the Acheron side after it was traced as the likely cause of
; Acheron's own native activate-menu (Heal/Loot/Kill/Vampire Feed) going completely unresponsive once
; this integration was installed. Fully redundant anyway: every one of those five actions, plus more
; (Execute, Tie Up, Untie), is already reachable through Baka's own interact-power menu.

Function _RegisterDecorators()
    ; Phase 6a.1 instrument: unconditional raw return-code trace per decorator (rc = 0 registered
    ; OK; nonzero = the DLL refused the registration). Deliberately NOT behind the bDebugLog MCM
    ; gate -- this is the diagnostic that settles 6b's decorator verdict, and a gated instrument
    ; can go dark exactly when the flag is off. Registration is idempotent and re-asserted on the
    ; heartbeat, so traces repeat at that cadence; the FIRST line after launch/load is the verdict
    ; line. Retire or re-gate after the 6a session.
    Int rc = SkyrimNetApi.RegisterDecorator("get_baka_state",              "SkyrimNet_BakaIntegration", "GetBakaState")
    Debug.Trace("[SNBaka] decorator register: get_baka_state rc=" + rc)
    rc = SkyrimNetApi.RegisterDecorator("is_in_baka_animation",        "SkyrimNet_BakaIntegration", "IsInBakaAnimation")
    Debug.Trace("[SNBaka] decorator register: is_in_baka_animation rc=" + rc)
    rc = SkyrimNetApi.RegisterDecorator("get_spank_state",             "SkyrimNet_BakaIntegration", "GetSpankState")
    Debug.Trace("[SNBaka] decorator register: get_spank_state rc=" + rc)
    rc = SkyrimNetApi.RegisterDecorator("get_nearby_furniture_actors", "SkyrimNet_BakaIntegration", "GetNearbyFurnitureActors")
    Debug.Trace("[SNBaka] decorator register: get_nearby_furniture_actors rc=" + rc)
    ; REV-129: get_ded_arousal -- FRAMEWORK-CLASS, MOTHERBOARD-owned (the §82/§138
    ; ownership rule's first live application: the arousal chain is shared
    ; substrate, not cum-specific). Same rc-instrument class as above.
    rc = SkyrimNetApi.RegisterDecorator("get_ded_arousal", "SkyrimNet_BakaIntegration", "GetDedArousal")
    Debug.Trace("[SNBaka] decorator register: get_ded_arousal rc=" + rc + " (REV-129)")
    ; REV-167 §5.3 (register entry 44, spec: mode-personality-enrichment.md):
    ; get_severactions_mood -- motherboard-owned, presence-gated, READ-ONLY
    ; (the 144 compatibility doctrine: we never write their state). Same
    ; rc-instrument class as above.
    rc = SkyrimNetApi.RegisterDecorator("get_severactions_mood", "SkyrimNet_BakaIntegration", "GetSeverActionsMood")
    Debug.Trace("[SNBaka] decorator register: get_severactions_mood rc=" + rc + " (REV-167)")
    ; baka_flirted decorator removed — the flirt escalations self-gate via their descriptions now.
    ; (GetFlirted is kept below, unused, so any stale SkyrimNet registration still resolves cleanly.)
EndFunction

Event OnUpdateGameTime()
    _Log("[SNBaka] OnUpdateGameTime ENTER: PlayerRef=" + PlayerRef + " gameTime=" + Utility.GetCurrentGameTime())
    UnregisterForUpdateGameTime()
    ; PlayerRef must be refreshed BEFORE _RegisterModEvents() -- confirmed bug from testing:
    ; _RegisterModEvents() only sets SNBaka.Present behind an "If PlayerRef" guard, but doesn't
    ; check RegisterForModEvent's listeners (which don't need PlayerRef at all). If PlayerRef had
    ; gone stale/None across a reload, the listeners kept registering fine every heartbeat while
    ; the Present flag silently never got set again -- Acheron's own creature-handoff check reads
    ; that flag and would skip every roll forever, even though Baka was actually alive and
    ; listening (its own SNBaka_TryCreatureOnDowned handler could still fire directly).
    If !PlayerRef
        PlayerRef = Game.GetPlayer()
    EndIf
    ; Re-assert decorators AND mod-event listeners after a save load (neither persists; Setup doesn't
    ; run on reload). This is what keeps the creature hand-off (and AEL/menu events) alive across loads.
    _RegisterDecorators()
    _RegisterModEvents()
    ; REV-68 (Phase B): module lifecycle re-assert — same self-heal cadence as the
    ; listeners above (handshakes re-log; EnsureAlive is a no-op when the bridge is
    ; already ticking).
    _ArmModules()
    ; REV-156 RETIREMENT BANNER: the v1 SlaveTats ambient observation
    ; pass (REV-74 rider 3 — ObservationPass, heartbeat-dispatched,
    ; player-only ~4h cadence) is RETIRED. Superseded by the daemon-tick
    ; AMBIENT EXPOSURE PASS (SNBaka_SlaveTatsModule.AmbientExposurePass,
    ; hooked in _DaemonTick, both modes; visibility-gated; the MCM
    ; "Ambient Observation Cues" toggle folded to it). Records:
    ; slavetats.md REV-156 + PROJECT_STATE section 178.
    ; REV-65: FHU poll self-healing arming. REV-64 defect of record: the poll
    ; armed ONLY from Setup(), whose MCM OnGameReload chain never executed at
    ; save-load (stale save-bound SKI config instance) -- the poll was dead
    ; every load. This heartbeat demonstrably executes (~3.3 min cadence in
    ; the rev-64 log), so arming here too makes the poll self-heal within one
    ; heartbeat even when the MCM reload path is stale. _FHUStartPoll() is
    ; idempotent (no-op while a poll is pending); arming remains
    ; toggle-gated + install-gated. Arming points: Setup() (primary) + here.
    If bFHUInflationEnabled && SNBaka_FHUInflationModule.Installed()   ; REV-96 Task 2: probe moved to the module (call shape only)
        _FHUStartPoll()
    EndIf
    _STAmbientStart()   ; REV-159 (dogfood 2.2): the decoupled ST ambient cadence re-asserts from the heartbeat too (self-heal posture)
    Float currentTime = Utility.GetCurrentGameTime()
    If _lastSpankFadeTime <= 0.0
        _lastSpankFadeTime = currentTime
    EndIf
    ; Only do the (slow) spank-tattoo fade pass when SpankTatFadeRate hours have actually elapsed. The
    ; registration above runs on the faster heartbeat below, so listeners self-heal within ~seconds of a
    ; load instead of waiting a full fade interval (GetCurrentGameTime is in DAYS; rate is in HOURS).
    If (currentTime - _lastSpankFadeTime) >= (SpankTatFadeRate / 24.0)
        _lastSpankFadeTime = currentTime
        Int fi = 0
        Int fcount = StorageUtil.FormListCount(Self, "SkyrimNetSDB.SpankedActors")
        While fi < fcount
            Actor fa = StorageUtil.FormListGet(Self, "SkyrimNetSDB.SpankedActors", fi) as Actor
            If fa
                FadeActorTats(fa)
                Int remainHeat = StorageUtil.GetIntValue(fa, "SkyrimNetSDB.SpankHeat", 0)
                Int remainTear = StorageUtil.GetIntValue(fa, "SkyrimNetSDB.TearHeat",  0)
                If remainHeat <= 0 && remainTear <= 0
                    StorageUtil.FormListRemoveAt(Self, "SkyrimNetSDB.SpankedActors", fi)
                    fcount -= 1
                Else
                    fi += 1
                EndIf
            Else
                StorageUtil.FormListRemoveAt(Self, "SkyrimNetSDB.SpankedActors", fi)
                fcount -= 1
            EndIf
        EndWhile
    EndIf
    ; Heartbeat slowed 5x (audit finding: this was one of two perpetual self-renewing update chains,
    ; re-running 6 RegisterForModEvent calls every ~18s real-time forever). OnPlayerLoadGame/Setup
    ; cover the normal re-registration cases; this is only the belt-and-suspenders fallback.
    _Log("[SNBaka] OnUpdateGameTime: reached tail, re-arming for +0.5 game-hours")
    RegisterForSingleUpdateGameTime(0.5)
EndEvent

; Called by MCM when HealFactor changes — restarts the fade timer at the new rate.
Function ApplyFadeSettings()
    SpankTatFadeRate = SpankHealFactor as Float
    If SpankTatFadeRate < 0.1
        SpankTatFadeRate = 0.1
    EndIf
    UnregisterForUpdateGameTime()
    RegisterForSingleUpdateGameTime(SpankTatFadeRate)
EndFunction

; ---- Main spank dispatch ----
Function SpankTarget_Execute(Actor akSpanker, Actor akTarget, Bool akForceButt = False)
    _ActionLaneFire(akSpanker, akTarget, "SpankTarget") ; [REV-174f Leg 4.2] neutral fanned lane (LLM/player-initiated; daemon fires suppressed)
    _Log("[SNBakaACT] SpankTarget ENTER")
    _Log("[SNBaka] SpankTarget_Execute: spanker=" + akSpanker.GetDisplayName() + " target=" + akTarget.GetDisplayName())
    If !bEnabled || !akSpanker || !akTarget || akTarget.IsDead() || akSpanker.IsDead()
        _Log("[SNBaka] SpankTarget: disabled or dead actor.")
        Return
    EndIf
    ; REV-146a Task 2: child boundary - spank lane entry point.
    If _ChildBoundaryRefused(akSpanker, akTarget, "SpankTarget")
        Return
    EndIf
    ; REV-144 4.2: bPlayerCanBeSpanked FOLDS INTO the central player-target policy --
    ; the spank-scoped gate is retired as an admission gate (existing saves seeded from
    ; its old value; see _SeedPlayerTargetPolicy). Player-own spanks pass ungated.
    If !_PlayerTargetAdmitted(akSpanker, akTarget, "SpankTarget")
        Return
    EndIf
    If !bSpankMaleTargets && _SexOf(akTarget) == 0
        _Log("[SNBaka] SpankTarget: target is male — toggle 'Allow Male Targets' in MCM.")
        Return
    EndIf
    Float lastSpank = StorageUtil.GetFloatValue(None, "SkyrimNetSDB.LastSpankTime", 0.0)
    Float nowTime   = Utility.GetCurrentGameTime()
    Bool duringSex  = IsInSexAnimation(akTarget) || IsInSexAnimation(akSpanker)
    Float cooldown  = fSpankCooldown
    If duringSex
        cooldown = fSpankCooldownSex
    EndIf
    If nowTime - lastSpank < (cooldown / 86400.0)
        _Log("[SNBaka] SpankTarget: cooldown active (" + (nowTime - lastSpank) * 86400.0 + "s < " + cooldown + "s)")
        Return
    EndIf
    _Log("[SNBaka] SpankTarget: proceeding — duringSex=" + duringSex)
    StorageUtil.SetFloatValue(None, "SkyrimNetSDB.LastSpankTime", nowTime)
    If !duringSex
        If LockBoth(akSpanker, akTarget)
            ; Babo anim plays its own impact slap — suppress ours; moan at mid-anim.
            PlayPairedSimpleAnim(akSpanker, akTarget, \
                0.0, 0.0, 0.0, \
                "BaboSpankingM", "BaboSpankingF", \
                0.3, False, False, True)   ; was 1.0 — trimmed the post-slap hold (~1s too long)
            ApplyButtReaction(akTarget)
            UnlockBoth(akSpanker, akTarget)
        Else
            ; No paired anim (couldn't lock) — our slap IS the only sound here.
            _DoSpank(akSpanker, akTarget, SpankImpactSound, True)
            ApplyButtReaction(akTarget)
        EndIf
    Else
        ; During sex there's no Babo paired anim, so play our slap+moan directly.
        _PlaySpankSound(akTarget, SpankImpactSound)
    EndIf
    ApplySpankMark(akTarget)
    ApplyFaceMarks(akTarget)
    _StartTears(akTarget)
    RecordSpank(akTarget, akSpanker.GetDisplayName())
    Bool atFurniture = bSpankFurnitureTriggers && akTarget.GetFurnitureReference() != None
    String desc
    If atFurniture
        desc = akSpanker.GetDisplayName() + " slapped " + akTarget.GetDisplayName() + "'s ass while they were bent over."
    Else
        desc = akSpanker.GetDisplayName() + " spanked " + akTarget.GetDisplayName() + "."
    EndIf
    SkyrimNetApi.RegisterEvent("sdb_spanked", desc, akSpanker, akTarget)
EndFunction

Function SlapFace_Execute(Actor akSlapper, Actor akTarget)
    _ActionLaneFire(akSlapper, akTarget, "SlapFace") ; [REV-174f Leg 4.2] neutral fanned lane (LLM/player-initiated; daemon fires suppressed)
    _Log("[SNBakaACT] SlapFace ENTER")
    _Log("[SNBaka] SlapFace_Execute: slapper=" + akSlapper.GetDisplayName() + " target=" + akTarget.GetDisplayName())
    If !bEnabled || !akSlapper || !akTarget || akTarget.IsDead() || akSlapper.IsDead()
        _Log("[SNBaka] SlapFace_Execute: early exit — bEnabled=" + bEnabled + " dead/None check")
        Return
    EndIf
    ; REV-146a Task 2: child boundary - slap lane entry point.
    If _ChildBoundaryRefused(akSlapper, akTarget, "SlapFace")
        Return
    EndIf
    ; REV-144 4.2: bPlayerCanBeSpanked FOLDS INTO the central player-target policy
    ; (same fold-in as SpankTarget above). Player-own slaps pass ungated.
    If !_PlayerTargetAdmitted(akSlapper, akTarget, "SlapFace")
        Return
    EndIf
    Float lastSpank = StorageUtil.GetFloatValue(None, "SkyrimNetSDB.LastSpankTime", 0.0)
    Float nowTime   = Utility.GetCurrentGameTime()
    Bool duringSex  = IsInSexAnimation(akTarget) || IsInSexAnimation(akSlapper)
    Float cooldown  = fSpankCooldown
    If duringSex
        cooldown = fSpankCooldownSex
    EndIf
    If nowTime - lastSpank < (cooldown / 86400.0)
        Return
    EndIf
    StorageUtil.SetFloatValue(None, "SkyrimNetSDB.LastSpankTime", nowTime)
    If !duringSex
        _DoSpank(akSlapper, akTarget, SpankFaceSlapSound, False)
    Else
        PlaySmackSound(akTarget)
    EndIf
    ApplyFaceMarks(akTarget)
    _StartTears(akTarget)
    RecordSpank(akTarget, akSlapper.GetDisplayName())
    String desc = akSlapper.GetDisplayName() + " slapped " + akTarget.GetDisplayName() + " across the face."
    SkyrimNetApi.RegisterEvent("sdb_slapped", desc, akSlapper, akTarget)
EndFunction

Function BreastSlap_Execute(Actor akSpanker, Actor akTarget)
    _ActionLaneFire(akSpanker, akTarget, "BreastSlap") ; [REV-174f Leg 4.2] neutral fanned lane (LLM/player-initiated; daemon fires suppressed)
    _Log("[SNBakaACT] BreastSlap ENTER")
    If !bEnabled || !akSpanker || !akTarget || akTarget.IsDead() || akSpanker.IsDead()
        Return
    EndIf
    ; Breast slap targets NPCs only — never the player.
    If akTarget == PlayerRef
        _Log("[SNBaka] BreastSlap_Execute: player-as-target is not allowed.")
        Return
    EndIf
    If _SexOf(akTarget) != 1
        Return
    EndIf
    Float lastSpank = StorageUtil.GetFloatValue(None, "SkyrimNetSDB.LastSpankTime", 0.0)
    Float nowTime   = Utility.GetCurrentGameTime()
    Bool duringSex  = IsInSexAnimation(akTarget) || IsInSexAnimation(akSpanker)
    Float cooldown  = fSpankCooldown
    If duringSex
        cooldown = fSpankCooldownSex
    EndIf
    If nowTime - lastSpank < (cooldown / 86400.0)
        Return
    EndIf
    StorageUtil.SetFloatValue(None, "SkyrimNetSDB.LastSpankTime", nowTime)
    If !duringSex
        _DoSpank(akSpanker, akTarget, SpankBreastSlapSound, False)
        ApplyBreastReaction(akTarget)
    Else
        PlaySmackSound(akTarget)
        If _SexOf(akTarget) == 1 && SpankMoanSound
            ; 0.5s so the smack finishes first (shared output model steals the voice otherwise).
            Utility.Wait(0.5)
            SpankMoanSound.Play(akTarget)
        EndIf
    EndIf
    ApplyBreastMark(akTarget)
    ApplyFaceMarks(akTarget)
    _StartTears(akTarget)
    RecordSpank(akTarget, akSpanker.GetDisplayName())
    String desc = akSpanker.GetDisplayName() + " slapped " + akTarget.GetDisplayName() + " across the chest."
    SkyrimNetApi.RegisterEvent("sdb_spanked", desc, akSpanker, akTarget)
EndFunction

; ---- Animation dispatch ----
Function _DoSpank(Actor akSpanker, Actor akTarget, Sound akImpact = None, Bool bForwardReact = True)
    Bool atFurniture = akTarget.GetFurnitureReference() != None
    If bForwardReact && akSpanker == PlayerRef
        Debug.SendAnimationEvent(akSpanker, "SMplayerslaps")
    Else
        Debug.SendAnimationEvent(akSpanker, "IdleTake")
    EndIf
    Utility.Wait(0.15)
    _PlaySpankSound(akTarget, akImpact)
    If akTarget == PlayerRef
        If _SexOf(akTarget) == 1
            If bForwardReact
                Debug.SendAnimationEvent(akTarget, "Sta_slap_forward")
            Else
                Debug.SendAnimationEvent(akTarget, "Sta_slap_backward")
            EndIf
        ElseIf !atFurniture
            Debug.SendAnimationEvent(akTarget, "staggerStart")
        EndIf
    ElseIf !atFurniture
        Debug.SendAnimationEvent(akTarget, "staggerStart")
    EndIf
    Utility.Wait(0.4)
    Debug.SendAnimationEvent(akSpanker, "idleforcedefaultstate")
EndFunction

Function _PlaySpankSound(Actor akTarget, Sound akImpact = None)
    Sound impact = akImpact
    If !impact
        impact = SpankImpactSound
    EndIf

    ; Diagnostics: is the target the one we expect, loaded, and near the camera?
    Bool  loaded = akTarget.Is3DLoaded()
    Float dist   = akTarget.GetDistance(PlayerRef)
    _Log("[SNBaka] _PlaySpankSound: target=" + akTarget.GetDisplayName() + \
        " 3DLoaded=" + loaded + " distToPlayer=" + dist + \
        " impactForm=" + impact + " moanForm=" + SpankMoanSound)

    ; Force the instance to FULL volume after Play — this is what the proven-loud
    ; SkyrimNet_SlapDaButt does (Sound.SetInstanceVolume(handle, 1.0)) and it's how
    ; it stays audible DURING sex: SexLab ducks the SFX category, but pinning this
    ; instance to 1.0 overrides the duck for our slap/moan.  Guard handle > 0.
    ; (Earlier I removed this entirely, and once wrongly used 0.5 — half volume.)
    If impact
        Int handle = impact.Play(akTarget)
        If handle > 0
            Sound.SetInstanceVolume(handle, 1.0)
        EndIf
        _Log("[SNBaka] _PlaySpankSound: impact handle=" + handle)
    Else
        _Log("[SNBaka] _PlaySpankSound: SpankImpactSound is NONE")
    EndIf

    Bool isFemale = _SexOf(akTarget) == 1
    If isFemale && SpankMoanSound
        Utility.Wait(0.1)
        Int moan = SpankMoanSound.Play(akTarget)
        If moan > 0
            Sound.SetInstanceVolume(moan, 1.0)
        EndIf
        _Log("[SNBaka] _PlaySpankSound: moan handle=" + moan)
    ElseIf !isFemale
        _Log("[SNBaka] _PlaySpankSound: no moan — target not female")
    ElseIf !SpankMoanSound
        _Log("[SNBaka] _PlaySpankSound: no moan — SpankMoanSound is NONE")
    EndIf
EndFunction

; Moan only — no impact slap.  Used for the OUT-OF-SEX paired spank, where the
; Babo spanking animation plays its OWN impact slap ~1.5 s in.  Playing our slap
; too made a double sound, so out of sex we suppress our slap and call this right
; after the paired anim returns (~when the Babo impact lands) for just the moan.
Function _PlaySpankMoanOnly(Actor akTarget)
    If !akTarget || _SexOf(akTarget) != 1 || !SpankMoanSound
        Return
    EndIf
    Int moan = SpankMoanSound.Play(akTarget)
    If moan > 0
        Sound.SetInstanceVolume(moan, 1.0)
    EndIf
    _Log("[SNBaka] _PlaySpankMoanOnly: target=" + akTarget.GetDisplayName() + " moan handle=" + moan)
EndFunction

; ---- Reaction spells ----
Function ApplyButtReaction(Actor akTarget)
    If !ButtReactionSpell || !akTarget || _SexOf(akTarget) != 1
        Return
    EndIf
    If akTarget.IsInCombat() || akTarget.IsDead()
        Return
    EndIf
    akTarget.RemoveSpell(ButtReactionSpell)
    akTarget.AddSpell(ButtReactionSpell, False)
EndFunction

Function ApplyBreastReaction(Actor akTarget)
    If !BreastReactionSpell || !akTarget || _SexOf(akTarget) != 1
        Return
    EndIf
    If akTarget.IsInCombat() || akTarget.IsDead()
        Return
    EndIf
    akTarget.RemoveSpell(BreastReactionSpell)
    akTarget.AddSpell(BreastReactionSpell, False)
EndFunction

; ---- Tattoo system ----
Function ApplySpankMark(Actor akTarget)
    If !akTarget || _SexOf(akTarget) != 1
        Return
    EndIf
    Int maxHeat = SpankTatIntensity * 4
    Int heat    = StorageUtil.GetIntValue(akTarget, "SkyrimNetSDB.SpankHeat", 0) + 1
    If heat > maxHeat
        heat = maxHeat
    EndIf
    StorageUtil.SetIntValue(akTarget, "SkyrimNetSDB.SpankHeat", heat)
    Int oldStage = StorageUtil.GetIntValue(akTarget, "SkyrimNetSDB.AssTatStage", 0)
    Int newStage = GetHeatStage(heat, SpankTatIntensity)
    If newStage != oldStage
        If oldStage > 0
            SlaveTats.simple_remove_tattoo(akTarget, "SkyrimNet Spank", GetAssTatNameForStage(oldStage), True, False)
        EndIf
        SlaveTats.simple_add_tattoo(akTarget, "SkyrimNet Spank", GetAssTatNameForStage(newStage), 0, True, True, 1.0)
        StorageUtil.SetIntValue(akTarget, "SkyrimNetSDB.AssTatStage", newStage)
    EndIf
    StorageUtil.FormListAdd(Self, "SkyrimNetSDB.SpankedActors", akTarget, True)
    ; REV-72 SlaveTats module: user-chosen degradation set rides alongside the heat marks
    ; (extend-not-duplicate; module checks its own Enabled/ApplyOnSpank/set-config gates).
    SNBaka_SlaveTatsModule.OnSpankHeat(akTarget)
EndFunction

Function ApplyBreastMark(Actor akTarget)
    If !akTarget || _SexOf(akTarget) != 1
        Return
    EndIf
    StorageUtil.SetIntValue(akTarget, "SkyrimNetSDB.HasBreastTat", 1)
    SlaveTats.simple_remove_tattoo(akTarget, "SkyrimNet Spank", "spank_breasts", True, False)
    SlaveTats.simple_add_tattoo(akTarget, "SkyrimNet Spank", "spank_breasts", 0, True, True, 1.0)
    StorageUtil.FormListAdd(Self, "SkyrimNetSDB.SpankedActors", akTarget, True)
EndFunction

Function ApplyFaceMarks(Actor akTarget)
    If !akTarget || _SexOf(akTarget) != 1
        Return
    EndIf
    Int maxTear  = SpankTatIntensity * 4
    Int tearHeat = StorageUtil.GetIntValue(akTarget, "SkyrimNetSDB.TearHeat", 0) + 1
    If tearHeat > maxTear
        tearHeat = maxTear
    EndIf
    StorageUtil.SetIntValue(akTarget, "SkyrimNetSDB.TearHeat", tearHeat)
    UpdateFaceMarks(akTarget, tearHeat)
    StorageUtil.FormListAdd(Self, "SkyrimNetSDB.SpankedActors", akTarget, True)
EndFunction

Function UpdateFaceMarks(Actor akTarget, Int tearHeat)
    If !akTarget || _SexOf(akTarget) != 1
        Return
    EndIf
    ClearFaceMarks(akTarget)
    If tearHeat >= SpankTatIntensity * 3
        SlaveTats.simple_add_tattoo(akTarget, "SkyrimNet Spank", "tears3", 0, True, False, 1.0)
        SlaveTats.simple_add_tattoo(akTarget, "SkyrimNet Spank", "sob2",   0, True, False, 1.0)
        SlaveTats.simple_add_tattoo(akTarget, "SkyrimNet Spank", "drool1", 0, True, True,  1.0)
    ElseIf tearHeat >= SpankTatIntensity * 2
        SlaveTats.simple_add_tattoo(akTarget, "SkyrimNet Spank", "tears2", 0, True, False, 1.0)
        SlaveTats.simple_add_tattoo(akTarget, "SkyrimNet Spank", "sob1",   0, True, True,  1.0)
    ElseIf tearHeat >= SpankTatIntensity
        SlaveTats.simple_add_tattoo(akTarget, "SkyrimNet Spank", "tears1", 0, True, True, 1.0)
    Else
        SlaveTats.simple_add_tattoo(akTarget, "SkyrimNet Spank", "tears1", 0, True, True, 0.0)
    EndIf
EndFunction

Function ClearFaceMarks(Actor akTarget)
    If !akTarget || _SexOf(akTarget) != 1
        Return
    EndIf
    SlaveTats.simple_remove_tattoo(akTarget, "SkyrimNet Spank", "tears1", True, False)
    SlaveTats.simple_remove_tattoo(akTarget, "SkyrimNet Spank", "tears2", True, False)
    SlaveTats.simple_remove_tattoo(akTarget, "SkyrimNet Spank", "tears3", True, False)
    SlaveTats.simple_remove_tattoo(akTarget, "SkyrimNet Spank", "sob1",   True, False)
    SlaveTats.simple_remove_tattoo(akTarget, "SkyrimNet Spank", "sob2",   True, False)
    SlaveTats.simple_remove_tattoo(akTarget, "SkyrimNet Spank", "drool1", True, False)
EndFunction

Function FadeActorTats(Actor akTarget)
    If !akTarget || _SexOf(akTarget) != 1
        Return
    EndIf
    Int tearHeat    = StorageUtil.GetIntValue(akTarget, "SkyrimNetSDB.TearHeat", 0)
    Int newTearHeat = tearHeat - SpankTatIntensity
    If newTearHeat < 0
        newTearHeat = 0
    EndIf
    If newTearHeat != tearHeat
        StorageUtil.SetIntValue(akTarget, "SkyrimNetSDB.TearHeat", newTearHeat)
        UpdateFaceMarks(akTarget, newTearHeat)
    EndIf
    Int heat = StorageUtil.GetIntValue(akTarget, "SkyrimNetSDB.SpankHeat", 0)
    If heat <= 0
        Int hasBreast = StorageUtil.GetIntValue(akTarget, "SkyrimNetSDB.HasBreastTat", 0)
        If hasBreast > 0 && newTearHeat <= 0
            SlaveTats.simple_remove_tattoo(akTarget, "SkyrimNet Spank", "spank_breasts", True, False)
            SlaveTats.simple_add_tattoo(akTarget, "SkyrimNet Spank", "spank_breasts", 0, True, True, 0.0)
            StorageUtil.SetIntValue(akTarget, "SkyrimNetSDB.HasBreastTat", 0)
        EndIf
        Return
    EndIf
    Int newHeat  = heat - SpankTatIntensity
    If newHeat < 0
        newHeat = 0
    EndIf
    StorageUtil.SetIntValue(akTarget, "SkyrimNetSDB.SpankHeat", newHeat)
    Int oldStage = StorageUtil.GetIntValue(akTarget, "SkyrimNetSDB.AssTatStage", 0)
    Int newStage = GetHeatStage(newHeat, SpankTatIntensity)
    If newStage != oldStage && oldStage > 0
        If newStage > 0
            SlaveTats.simple_remove_tattoo(akTarget, "SkyrimNet Spank", GetAssTatNameForStage(oldStage), True, False)
            SlaveTats.simple_add_tattoo(akTarget, "SkyrimNet Spank", GetAssTatNameForStage(newStage), 0, True, True, 1.0)
        Else
            SlaveTats.simple_remove_tattoo(akTarget, "SkyrimNet Spank", GetAssTatNameForStage(oldStage), True, False)
            SlaveTats.simple_add_tattoo(akTarget, "SkyrimNet Spank", GetAssTatNameForStage(oldStage), 0, True, True, 0.0)
        EndIf
        StorageUtil.SetIntValue(akTarget, "SkyrimNetSDB.AssTatStage", newStage)
    EndIf
    Int hasBreast = StorageUtil.GetIntValue(akTarget, "SkyrimNetSDB.HasBreastTat", 0)
    If hasBreast > 0 && newHeat <= 0
        SlaveTats.simple_remove_tattoo(akTarget, "SkyrimNet Spank", "spank_breasts", True, False)
        SlaveTats.simple_add_tattoo(akTarget, "SkyrimNet Spank", "spank_breasts", 0, True, True, 0.0)
        StorageUtil.SetIntValue(akTarget, "SkyrimNetSDB.HasBreastTat", 0)
    EndIf
EndFunction

; ---- Tracking ----
Function RecordSpank(Actor akTarget, String spankerName)
    If !akTarget
        Return
    EndIf
    Int count = StorageUtil.GetIntValue(akTarget, "SkyrimNetSDB.SpankCount", 0) + 1
    StorageUtil.SetIntValue(akTarget,    "SkyrimNetSDB.SpankCount",    count)
    StorageUtil.SetFloatValue(akTarget,  "SkyrimNetSDB.LastSpankTime", Utility.GetCurrentGameTime())
    StorageUtil.SetStringValue(akTarget, "SkyrimNetSDB.LastSpanker",   spankerName)
EndFunction

; ---- Sex / actor helpers ----
Actor Function FindSexPartner(Actor akCaster)
    ; Use cell iteration — does not depend on SexLab thread API.
    ; Finds the nearest actor in the same cell that is in a sex animation.
    If !akCaster
        Return None
    EndIf
    Cell c = akCaster.GetParentCell()
    If !c
        Return None
    EndIf
    Actor nearest = None
    Float nearestDist = 99999.0
    Int count = c.GetNumRefs(62)
    Int i = 0
    While i < count
        Actor candidate = c.GetNthRef(i, 62) as Actor
        If candidate && candidate != akCaster && !candidate.IsDead()
            If IsInSexAnimation(candidate)
                Float d = akCaster.GetDistance(candidate)
                If d < 400.0 && d < nearestDist
                    nearestDist = d
                    nearest = candidate
                EndIf
            EndIf
        EndIf
        i += 1
    EndWhile
    _Log("[SNBaka] FindSexPartner: result=" + nearest)
    Return nearest
EndFunction

; ============================================================
; Sex spank — menu-driven partner selection during sex scenes
; ============================================================

; Fills result[0..2] with up to 3 non-player actors currently in a sex animation
; in the same cell as akCaster. result must be a pre-allocated Actor[3].
; Checks SexLab AnimatingFaction AND OStim ExcitementFaction so the menu
; is populated regardless of which sex framework is running the scene.
Function _GetSexSceneNPCs(Actor akCaster, Actor[] result)
    ; OStim SA fast path: OThread already tracks exactly who's in the scene (the thread roster), so
    ; ask it directly instead of scanning the cell and checking faction membership — no guessing, no
    ; radius, no false negatives. Falls through to the scan below for SexLab scenes (no thread concept)
    ; or if OStim isn't installed / the caster isn't currently in a thread.
    Faction osStimFaction = _OStimSceneFaction()
    If osStimFaction
        Int threadID = OActor.GetThreadID(akCaster)
        If threadID >= 0
            Actor[] threadActors = OThread.GetActors(threadID)
            Int slot = 0
            Int t = 0
            While t < threadActors.Length && slot < 3
                Actor candidate = threadActors[t]
                If candidate && candidate != PlayerRef && candidate != akCaster && !candidate.IsDead()
                    result[slot] = candidate
                    slot += 1
                EndIf
                t += 1
            EndWhile
            If slot > 0
                _Log("[SNBaka] _GetSexSceneNPCs: found " + slot + " NPC(s) via OStim thread " + threadID)
                Return
            EndIf
        EndIf
    EndIf

    ; Resolve SexLab faction
    Faction slFaction = SexLabAnimatingFaction
    If !slFaction
        slFaction = SkyrimNet_BakaSL.AnimFaction()
    EndIf

    ; Need at least one faction to detect anything
    If !slFaction && !osStimFaction
        _Log("[SNBaka] _GetSexSceneNPCs: no sex faction resolved (no SexLab faction and OStim not installed)")
        Return
    EndIf

    Cell c = akCaster.GetParentCell()
    If !c
        Return
    EndIf

    Int slot  = 0
    Int total = c.GetNumRefs(62)
    Int i     = 0
    While i < total && slot < 3
        Actor candidate = c.GetNthRef(i, 62) as Actor
        If candidate && candidate != PlayerRef && !candidate.IsDead()
            Bool inScene = False
            If slFaction && candidate.GetFactionRank(slFaction) >= 0
                inScene = True
            EndIf
            If !inScene && osStimFaction && candidate.GetFactionRank(osStimFaction) >= 0
                inScene = True
            EndIf
            If inScene
                result[slot] = candidate
                slot += 1
            EndIf
        EndIf
        i += 1
    EndWhile
    _Log("[SNBaka] _GetSexSceneNPCs: found " + slot + " NPC(s) in scene")
EndFunction

; Applies a full sex-safe spank: impact + moan + tats + face marks + tears.
; akSpanker may be None (self-spank). No paired animation — safe inside sex scenes.
Function _SexSpank_Execute(Actor akSpanker, Actor akTarget)
    _ActionLaneFire(akSpanker, akTarget, "SexSpank") ; [REV-174f Leg 4.2] neutral fanned lane (LLM/player-initiated; daemon fires suppressed)
    _Log("[SNBakaACT] _SexSpank ENTER")
    If !akTarget
        Return
    EndIf
    _PlaySpankSound(akTarget, SpankImpactSound)
    ApplySpankMark(akTarget)
    ApplyFaceMarks(akTarget)
    _StartTears(akTarget)
    String spankerName = "You"
    If akSpanker
        spankerName = akSpanker.GetDisplayName()
    EndIf
    Actor actor1 = akTarget
    If akSpanker
        actor1 = akSpanker
    EndIf
    SkyrimNetApi.RegisterEvent("baka_sex_spank", \
        spankerName + " spanks " + akTarget.GetDisplayName() + " during sex.", \
        actor1, akTarget)
    StorageUtil.SetFloatValue(None, "SkyrimNetSDB.LastSpankTime", Utility.GetCurrentGameTime())
EndFunction

; Secondary menu: who spanks the player?
Function _SexSpank_ShowByWhom(Actor[] sceneNPCs, Int npcCount)
    String info = "Spanked by: "
    If sceneNPCs[0]
        info += "1=" + sceneNPCs[0].GetDisplayName() + "  "
    EndIf
    If sceneNPCs[1]
        info += "2=" + sceneNPCs[1].GetDisplayName() + "  "
    EndIf
    If sceneNPCs[2]
        info += "3=" + sceneNPCs[2].GetDisplayName() + "  "
    EndIf
    info += "4=Yourself"
    _Notify(info)
    If !SexSpankByWhomMenu
        _SexSpank_Execute(None, PlayerRef)
        Return
    EndIf
    Int choice = SexSpankByWhomMenu.Show()
    If choice == 4
        Return  ; Cancel
    EndIf
    If choice == 3
        _SexSpank_Execute(None, PlayerRef)
        Return
    EndIf
    If choice < npcCount && sceneNPCs[choice]
        _SexSpank_Execute(sceneNPCs[choice], PlayerRef)
    EndIf
EndFunction

; Primary menu shown when the interact power fires during a sex scene.
; Collects all scene participants, shows a notification mapping numbers → names,
; then shows a menu (Person 1 / Person 2 / Person 3 / You / Cancel).
; Selecting "You" opens a second menu for who does the spanking.
Function SexSpank_ShowMenu(Actor akCaster)
    ; Cooldown check
    Float nowTime = Utility.GetCurrentGameTime()
    Float lastSpank = StorageUtil.GetFloatValue(None, "SkyrimNetSDB.LastSpankTime", 0.0)
    If nowTime - lastSpank < (fSpankCooldownSex / 86400.0)
        Return
    EndIf

    ; Collect NPCs in the sex scene
    Actor[] sceneNPCs = new Actor[3]
    _GetSexSceneNPCs(akCaster, sceneNPCs)

    ; Is the player also in the sex animation? Use the SAME both-framework check the power used to
    ; get here (SexLab AND OStim) — the old SexLab-only check made this False in OStim scenes.
    Bool playerInScene = IsInSexAnimation(PlayerRef)

    ; Count valid NPCs
    Int npcCount = 0
    If sceneNPCs[0]
        npcCount += 1
    EndIf
    If sceneNPCs[1]
        npcCount += 1
    EndIf
    If sceneNPCs[2]
        npcCount += 1
    EndIf

    If npcCount == 0 && !playerInScene
        Return
    EndIf

    ; ── PrismaUI path (async) ─────────────────────────────────────────────────
    If SNBakaUI.IsAvailable()
        _pendingSexCaster = akCaster
        _pendingSexNPC0   = sceneNPCs[0]
        _pendingSexNPC1   = sceneNPCs[1]
        _pendingSexNPC2   = sceneNPCs[2]
        _pendingTarget    = None  ; signals _DispatchSexSpankAction not interact

        ; Build JSON: {"names":["Lydia","Serana"],"playerInScene":true}
        String json = "{\"names\":["
        Bool first = True
        If sceneNPCs[0]
            json += "\"" + sceneNPCs[0].GetDisplayName() + "\""
            first = False
        EndIf
        If sceneNPCs[1]
            If !first
                json += ","
            EndIf
            json += "\"" + sceneNPCs[1].GetDisplayName() + "\""
            first = False
        EndIf
        If sceneNPCs[2]
            If !first
                json += ","
            EndIf
            json += "\"" + sceneNPCs[2].GetDisplayName() + "\""
        EndIf
        If playerInScene
            json += "],\"playerInScene\":true}"
        Else
            json += "],\"playerInScene\":false}"
        EndIf
        SNBakaUI.ShowSexSpankMenu(json)
        _PushModeStates()   ; REV-147 Feature B: initial button state at panel open
        Return  ; result arrives via OnSNBakaMenuChoice
    EndIf

    ; ── Vanilla fallback ──────────────────────────────────────────────────────
    If !SexSpankWhoMenu
        Actor sexTarget = FindSexPartner(akCaster)
        If sexTarget && sexTarget != akCaster
            _SexSpank_Execute(akCaster, sexTarget)
        EndIf
        Return
    EndIf

    String info = "Spank: "
    If sceneNPCs[0]
        info += "1=" + sceneNPCs[0].GetDisplayName() + "  "
    EndIf
    If sceneNPCs[1]
        info += "2=" + sceneNPCs[1].GetDisplayName() + "  "
    EndIf
    If sceneNPCs[2]
        info += "3=" + sceneNPCs[2].GetDisplayName() + "  "
    EndIf
    If playerInScene
        info += "4=You"
    EndIf
    _Notify(info)

    Int choice = SexSpankWhoMenu.Show()

    If choice == 4
        Return
    EndIf
    If choice == 3
        If playerInScene
            _SexSpank_ShowByWhom(sceneNPCs, npcCount)
        EndIf
        Return
    EndIf
    If choice < npcCount && sceneNPCs[choice]
        _SexSpank_Execute(akCaster, sceneNPCs[choice])
    EndIf
EndFunction

; ---- LLM action callbacks (called from YAML via quest instance) ----
Function SpankButt_Action(Actor akInitiator, Actor akTarget)
    If akTarget
        SpankTarget_Execute(akInitiator, akTarget, True)
    EndIf
EndFunction

Function SpankBreast_Action(Actor akInitiator, Actor akTarget)
    If akTarget
        BreastSlap_Execute(akInitiator, akTarget)
    EndIf
EndFunction

Function SlapFace_Action(Actor akInitiator, Actor akTarget)
    If akTarget
        SlapFace_Execute(akInitiator, akTarget)
    EndIf
EndFunction

; ---- Decorators (Global) ----
String Function GetSpankState(Actor akActor) Global
    If !akActor
        Return "{}"
    EndIf
    Int    count       = StorageUtil.GetIntValue(akActor,   "SkyrimNetSDB.SpankCount",    0)
    Float  lastTime    = StorageUtil.GetFloatValue(akActor,  "SkyrimNetSDB.LastSpankTime", 0.0)
    String lastSpanker = StorageUtil.GetStringValue(akActor, "SkyrimNetSDB.LastSpanker",   "")
    String recency = "none"
    If lastTime > 0.0
        Float hoursSince = (Utility.GetCurrentGameTime() - lastTime) * 24.0
        If hoursSince < 0.5
            recency = "just now"
        ElseIf hoursSince < 2.0
            recency = "very recent"
        ElseIf hoursSince < 8.0
            recency = "recent"
        ElseIf hoursSince < 24.0
            recency = "hours ago"
        Else
            recency = "distant"
        EndIf
    EndIf
    Int heat = StorageUtil.GetIntValue(akActor, "SkyrimNetSDB.SpankHeat", 0)
    SkyrimNet_BakaIntegration q = SkyrimNet_BakaIntegration.GetMain()
    Int factor = 2
    If q
        factor = q.SpankTatIntensity
    EndIf
    String markLevel = "none"
    If heat >= factor * 3
        markLevel = "heavy"
    ElseIf heat >= factor * 2
        markLevel = "medium"
    ElseIf heat >= factor
        markLevel = "light"
    EndIf
    String json = "{"
    json += "\"has_been_spanked\":"     + (count > 0)   + ","
    json += "\"spank_count\":"          + count          + ","
    json += "\"last_spanker\":\""       + lastSpanker    + "\","
    json += "\"recency\":\""            + recency        + "\","
    json += "\"mark_level\":\""         + markLevel      + "\","
    json += "\"available_during_sex\":true"
    json += "}"
    Return json
EndFunction

String Function GetNearbyFurnitureActors(Actor akActor) Global
    Actor akPlayer = Game.GetPlayer()
    If !akPlayer
        Return "[]"
    EndIf
    Cell currentCell = akPlayer.GetParentCell()
    If !currentCell
        Return "[]"
    EndIf
    String result = "["
    Bool first = True
    Int count = currentCell.GetNumRefs(62)
    Int i = 0
    While i < count
        Actor target = currentCell.GetNthRef(i, 62) as Actor
        ; Include the player (so a crafting player is a valid spank target); only exclude
        ; the speaker NPC.  Only surface alchemy labs / enchanting tables — chairs, beds,
        ; forges, etc. are not spank furniture.
        If target && target != akActor && !target.IsDead()
            ObjectReference furnRef = target.GetFurnitureReference()
            If furnRef != None && target.GetDistance(akPlayer) < 1500.0 && SNBakaUI.IsCraftingTemptation(furnRef)
                Bool isFemale  = _SexOf(target) == 1
                Bool tempting  = isFemale
                String sexStr  = "male"
                If isFemale
                    sexStr = "female"
                EndIf
                String poseStr = "standing at an alchemy lab or enchanting table"
                If tempting
                    ; Female bent over an alchemy lab / enchanting table - hips raised,
                    ; backside presented. Strongly nudges the LLM toward spank_butt.
                    poseStr = "bent over an alchemy lab or enchanting table, hips raised and backside presented - a near-irresistible invitation to be spanked"
                EndIf
                If !first
                    result += ","
                EndIf
                result += "{\"name\":\"" + target.GetDisplayName() + "\",\"sex\":\"" + sexStr + "\",\"state\":\"" + poseStr + "\""
                If tempting
                    result += ",\"spank_temptation\":\"very_high\""
                EndIf
                result += "}"
                first = False
            EndIf
        EndIf
        i += 1
    EndWhile
    result += "]"
    Return result
EndFunction

; ---- Heat/stage helpers (Global) ----
Int Function GetHeatStage(Int heat, Int factor = 2) Global
    If factor <= 0
        Return 0
    EndIf
    If heat >= factor * 4
        Return 4
    ElseIf heat >= factor * 3
        Return 3
    ElseIf heat >= factor * 2
        Return 2
    ElseIf heat >= factor
        Return 1
    EndIf
    Return 0
EndFunction

String Function GetAssTatNameForStage(Int stage) Global
    If stage == 1
        Return "spank03"
    ElseIf stage == 2
        Return "spank01"
    ElseIf stage == 3
        Return "spank02"
    ElseIf stage == 4
        Return "spank_ass"
    EndIf
    Return ""
EndFunction

; ============================================================
; REV-63: DETECTION TRIGGERS (cum detection + FHU inflation)
; ============================================================
; PATTERN SOURCE (Task 1): the sdb_spanked/sdb_slapped path -- our own action
; scripts build a desc string and call SkyrimNetApi.RegisterEvent(eventType,
; desc, originator, target); the YAML trigger keys on eventType only. Here the
; SOURCE is a third-party ModEvent instead of our own code, so the inbound leg
; is RegisterForModEvent handlers (armed in _RegisterModEvents, re-armed from
; Setup()/OnUpdateGameTime like every other listener -- mod-event registrations
; do NOT survive save/load) and the outbound leg is the same RegisterEvent call.
;
; DEVIATION FLAGGED (Papyrus-only scope): the original build plan placed these in
; a NEW quest script (SkyrimNet_BakaDetection.psc) -- but a new script needs a
; new quest record in the esp to ever instantiate, which violates the
; no-esp-change rule. So the listeners live HERE, on the already-running main
; quest, per the spank-system precedent (folded into this same script). A
; future FOMOD module split is preserved by the docs/features/ membership map.
;
; DUAL-FRAMEWORK POSTURE (amendment 3b-ii): FHU awareness reads FHU's OWN state
; (StorageUtil sr.inflater.* keys) and does not care which framework fed FHU.
; FHU cues never assert WHY a level changed -- only WHAT the state shows.
; Cum cues: unified wording (iCumCueMode=0, default) never names a framework.

; ---- Presence probes (cached: GetFormFromFile on an ABSENT esp logs a hard
; Papyrus error, not a silent None -- the SNBakaSL.Absent-cache lesson,
; SkyrimNet_BakaSL.psc L7-14). Absence is cached on the None key once. ----
; REV-96 Task 2: both probes' bodies MOVED VERBATIM to the module scripts (the §64
; class -- cached absence semantics identical); these are the motherboard's forwarding
; wrappers, so every existing caller (MCM reads Main._OCumInstalled() /
; Main._FHUInstalled(), Setup(), heartbeat) keeps its call shape unchanged.
Bool Function _OCumInstalled()
    Return SNBaka_CumDetectionModule.Installed()
EndFunction

Bool Function _FHUInstalled()
    Return SNBaka_FHUInflationModule.Installed()
EndFunction

; ---- CUM DETECTION (OCum / OStim side) ----
; REV-65: handler signatures derived from the senders' ACTUAL ModEvent push
; sequences (statically re-confirmed this session from the installed trees,
; per the rev-64 root cause of record):
;   ocum_applied_cum (OCumMaleScript.psc L689-695, [035.00002] tree):
;     PushForm(Orgasmer), PushForm(Target), PushFloat(AmountML),
;     PushString(Area), PushString(SceneID)                 -- 5 args
;   ocum_applied_cum_npc_scene (same file, L697-704):
;     Form Orgasmer, Form Target, Int ThreadID, Float AmountML,
;     String Area, String SceneID                           -- 6 args
; The rev-63 4-slot (eventName, strArg, numArg, sender) shape was the
; SendModEvent convention and is RETIRED: a ModEvent.Create/Push* handler
; receives exactly the pushed values as typed parameters, and the VM
; rejects the dispatch on mismatch (the 44 "Incorrect number of arguments"
; log errors of the rev-64 dogfood).
; REV-65 bonus (user ruling): the TARGET (second Form push) is now
; recoverable -- named-partner cue wording is PRIMARY; the rev-63 unnamed
; wording is the fallback only (Target == None guard).
Event OnOCumApplied(Form akOrgasmer, Form akTarget, Float afAmountML, String asArea, String asSceneID)
    ; REV-96 Task 2: body MOVED VERBATIM to SNBaka_CumDetectionModule.HandleOCumApplied
    ; (the §64 class; ModEvents are Form-members, so the declaration stays on the quest).
    SNBaka_CumDetectionModule.HandleOCumApplied(Self, akOrgasmer, akTarget, afAmountML, asArea, asSceneID)
EndEvent

; REV-65: the npc_scene variant carries ThreadID as a 3rd (Int) push, so it
; needs its own 6-arg handler. Identical gating/cue logic; thread id is
; logged in the sentinel (positions still resolve via the SL thread surface
; only in the SL proxy below -- OCum scenes do not use it).
Event OnOCumAppliedNPCScene(Form akOrgasmer, Form akTarget, Int aiThreadID, Float afAmountML, String asArea, String asSceneID)
    ; REV-96 Task 2: body MOVED VERBATIM to SNBaka_CumDetectionModule.HandleOCumAppliedNPCScene.
    SNBaka_CumDetectionModule.HandleOCumAppliedNPCScene(Self, akOrgasmer, akTarget, aiThreadID, afAmountML, asArea, asSceneID)
EndEvent

; REV-96 Task 2: _FireCumCue MOVED VERBATIM to SNBaka_CumDetectionModule._FireCumCue
; (both OCum event bodies forward to the module now; the shared 15s cooldown key
; SNBaka.LastCumCueRT is unchanged, so the cooldown still spans OCum + SL proxy).

; ---- SEXLAB ORGASM-HOOK PROXY (amendment 2a-ii; verdict of record: PROXY) ----
; SexLab has NO dedicated cum-state API (no event/faction/spell surface; its
; cum overlays are mesh/particle only). sslThreadModel.SendThreadEvent
; (L2256-2273) broadcasts "Hook<Name>" ModEvents carrying (thread_id, HasPlayer)
; for the stage/animation lifecycle; StageEnd covers stage completions
; including the orgasm stage. Evidence supports the PROXY case: the cue rides
; "a SexLab scene reached release" and NEVER claims overlay application.
; numArg = thread_id (first numeric push, sslThreadModel L2266-2270).
; REV-65: signature derived from the sender's ACTUAL pushes (sslThreadModel
; PPLUS V2.18.1, SetupThreadEvent L2261-2268: PushInt(thread_id),
; PushBool(HasPlayer) -- 2 args). The rev-63 4-slot shape is retired.
; REV-133c Task 1.2 (ruled): the OnSLAnimationEnd listener is RETIRED with
; the whole aftermath chain (rider 2.5b; the motherboard recompile is the
; declared, receipted scope -- clean removal beats archaeology-dust).
Event OnSLStageEnd(Int aiThreadID, Bool abHasPlayer)
    ; REV-96 Task 2: body MOVED VERBATIM to SNBaka_CumDetectionModule.HandleSLStageEnd.
    SNBaka_CumDetectionModule.HandleSLStageEnd(Self, aiThreadID, abHasPlayer)
EndEvent

; ---- REV-149: FHU v2 ENTRY-AROUSAL CAPTURE bracket (user rulings a/b + the
; mid-REV-149 hook-choice ruling) ----
; HookAnimationStart / HookAnimationEnd: SexLab non-blocking hook ModEvents
; (SexLabFramework.psc doc block L163-164, PPLUS V2.18.1), same 2-push payload
; as the proven HookStageEnd binding (sslThreadModel SetupThreadEvent:
; PushInt(thread_id), PushBool(HasPlayer)). CAPTURE-ONLY: these handlers never
; drive FHU inflation (the OStim parity ruling -- capture-only, no fill-driving).
Event OnSLAnimationStart(Int aiThreadID, Bool abHasPlayer)
    SNBaka_FHUInflationModule.HandleSceneStartSL(Self, aiThreadID)
EndEvent

Event OnSLAnimationEnd(Int aiThreadID, Bool abHasPlayer)
    SNBaka_FHUInflationModule.HandleSceneEndSL(Self, aiThreadID)
EndEvent

; ---- REV-129: get_ded_arousal DECORATOR (FRAMEWORK-CLASS, motherboard-owned; ----
; the §82/§138 ownership rule's FIRST LIVE APPLICATION). Reads the WITNESS
; (the passed actor = the reacting NPC's own arousal), NOT the wearer. Chain:
; OSL Aroused Reborn (side-effect-free read) -> SL Aroused NG -> none.
; Tier matrix (planner-ratified 3-band, cum-effects.md REV-128 1.1(b)):
; 0 = no framework (neutral silence), 1 = LOW (<= 25), 2 = MID, 3 = HIGH (>= 75).
String Function GetDedArousal(Actor akActor) Global
    Int arousal = -1
    String fw = "none"
    If SKSE.GetPluginVersion("OSLAroused") > 0
        arousal = OSLArousedNative.GetArousalNoSideEffects(akActor) as Int
        fw = "reborn"
    Else
        slaFrameworkScr kNG = Quest.GetQuest("sla_Framework") as slaFrameworkScr
        If kNG
            arousal = kNG.GetActorArousal(akActor)
            fw = "sl_aroused_ng"
        EndIf
    EndIf
    If arousal < 0
        Return "{\"arousal\": 0, \"tier\": 0, \"framework\": \"none\"}"
    EndIf
    Int tier = 2
    If arousal >= 75
        tier = 3
    ElseIf arousal <= 25
        tier = 1
    EndIf
    Return "{\"arousal\": " + arousal + ", \"tier\": " + tier + ", \"framework\": \"" + fw + "\"}"
EndFunction

; ---- REV-167 §5.3: get_severactions_mood DECORATOR (register entry 44; ----
; motherboard-owned, presence-gated, READ-ONLY). Reads SeverActions' mood
; native (SeverActionsNative.psc 4.5.0: Native_GetMood, "50.0 when unset",
; range -100..100); DeD supplies the tokenization (we gloss the number
; into a story-voice mood word -- never their tokens, never written back;
; the 144 compatibility doctrine). Null contract: plugin absent OR the
; unset sentinel (exactly 50.0) -> {"present": false} and the prompt
; template omits the block entirely; never "unknown".
String Function GetSeverActionsMood(Actor akActor) Global
    If !akActor
        Return "{\"present\": false}"
    EndIf
    If SKSE.GetPluginVersion("SeverActionsNative") <= 0 && SKSE.GetPluginVersion("SeverActionsNative") <= 0
        Return "{\"present\": false}"
    EndIf
    Float fMood = SeverActionsNative.Native_GetMood(akActor)
    If fMood == 50.0
        ; their documented unset sentinel -- presence-gated out
        Return "{\"present\": false}"
    EndIf
    String sMood = "neutral"
    If fMood <= -60.0
        sMood = "furious"
    ElseIf fMood <= -20.0
        sMood = "hostile"
    ElseIf fMood < 20.0
        sMood = "sullen"
    ElseIf fMood < 80.0
        sMood = "content"
    Else
        sMood = "joyful"
    EndIf
    Return "{\"present\": true, \"mood\": \"" + sMood + "\"}"
EndFunction


; REV-173 Path A (user ruling): the relationship-sync string-arg render is
; RETIRED -- same typed-binding finding as the probe (RenderTemplate binds
; STRING; selector requires number; the harvest NEVER functioned in any
; shipped build -- 100% degrade to Random + sentinel since birth, so this
; retirement changes no lived behavior). The relationship context reaches
; the LLM through the consideration prompts' in-template
; render_character_profile("full", initiatorUUID) renders (pack-sourced,
; number-typed at parse; the Relationships section rides the full render).
; The store's "relationships" lane retires with it (Path A store scope:
; vitals/uuidForm/gloss); snbaka_actorctx_relationships.prompt and
; snbaka_relationship_sync.prompt are deleted (one-lineage).
; _BioLinkedTo keeps its degrade-to-Random shape below. The Relationship
; Priority option is thus INERT pending a planner-ruled rehome (flagged
; for the user's pen at the REV-173 report).
String Function _DaemonRelationshipNameSet(Actor akActor)
    ; REV-173: retired -- see banner above. Empty set = the caller's
    ; documented degrade-to-Random path (unchanged lived behavior).
    Return ""
EndFunction


; REV-167 §15.4: the link test -- does the SUBJECT's bio name-set name the
; other actor (Tier A vs Tier B for the two-tier draw). Case-insensitive
; token match over the "|"-delimited set; compound entries ("Farkas and
; Vilkas") match as the FULL entry only -- documented behavior, not a
; heuristic. Empty/degraded set -> False (caller degrades to Random).
Bool Function _BioLinkedTo(Actor akSubject, Actor akOther)
    If !akSubject || !akOther
        Return False
    EndIf
    String sSet = _DaemonRelationshipNameSet(akSubject)
    If sSet == ""
        Return False
    EndIf
    String sName = _AsciiILower(akOther.GetDisplayName())
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
            If _AsciiILower(StringUtil.Substring(sSet, iPos, iBar - iPos)) == sName
                Return True
            EndIf
        EndIf
        iPos = iBar + 1
    EndWhile
    Return False
EndFunction

; REV-167 helper: ASCII case fold (StringUtil has no case fold; both sides
; pass through the same fold so equality is well-formed).
String Function _AsciiILower(String sText) Global
    Int i = 0
    Int iLen = StringUtil.GetLength(sText)
    String sOut = ""
    While i < iLen
        Int iCh = StringUtil.AsOrd(StringUtil.GetNthChar(sText, i))
        If iCh >= 65 && iCh <= 90    ; A-Z
            iCh += 32
        EndIf
        sOut = sOut + StringUtil.AsChar(iCh)
        i += 1
    EndWhile
    Return sOut
EndFunction

; REV-117 cum-v2: P+ push-time location signal. Sender's pushes (sslThreadModel
; PPLUS V2.18.1 L2234-2238): PushForm(TargetRef), PushForm(SourceRef), PushInt(aiType).
Event OnSLApplyCumFX(Form akTarget, Form akSource, Int aiType)
    SNBaka_CumDetectionModule.HandleSLApplyCumFX(Self, akTarget, akSource, aiType)
EndEvent

; REV-117 cum-v2: DeDService ambient timer callback (4-slot service ModEvent
; shape from EventPump.cpp: eventName, strArg, numArg, sender).
Event OnCumAmbientDue(String eventName, String strArg, Float numArg, Form sender)
    SNBaka_CumDetectionModule.HandleCumAmbientDue(Self, numArg, sender)
EndEvent

; REV-133c Task 2.3: bath-completion handler (presence-gated registration --
; see _RegisterModEvents); body module-owned (the wearer-only clear).
Event OnDnBCleanActorDirt(Form akActor)
    SNBaka_CumDetectionModule.HandleBathClean(Self, akActor)
EndEvent

; ---- FHU INFLATION AWARENESS (Task 3b: fallback poll design) ----
; What FHU's external stack actually exposes (as-read): sr_InfEventManager's
; broadcast system (fhu.EventRegister / fhu.ForceEventRegister) exists to
; register REFERENCE-ALIAS event scripts (sr_InfEventBase extends
; ReferenceAlias; RegisterSelf L34-42) -- joining needs esp records in
; sr_FillHerUp.esp, which is out of the Papyrus-only scope of this rev, so the
; formal handshake is NOT joined this session (flagged, not improvised).
; FHU's ModEvents carry no per-actor level payload (sr.inflater.start/.absorb
; are parameterless broadcasts; fhu.playerInflated / fhu.playerCumUpdate are
; player-only). The per-actor level surface is StorageUtil:
;   sr.inflater.amount (float, per actor) -- the level scale behind the 10 stage armors
;   sr.inflater.Actors (formlist, keyed on the sr_inflateQuest form 0x000D63)
; Level changes forward as sdb_fhu_inflate (increase) / sdb_fhu_deflate
; (decrease). Deflation detection = amount decreasing in the poll (the SpermOut
; ability path exposes no event). sr.inflater.start is used ONLY as an
; immediate-poll nudge on top of the interval.
Event OnFHUStartSignal()
    ; REV-65: zero-arg handler -- sr.inflater.start is a parameterless
    ; broadcast (sr_inflateQuest.InflateQueued(), Beta 2.11 tree: ModEvent.Create
    ; + Send, no Push calls). The rev-63 4-slot shape is retired (rev-64 evidence).
    ; REV-96 Task 2: body MOVED VERBATIM to SNBaka_FHUInflationModule.HandleFHUStartSignal.
    SNBaka_FHUInflationModule.HandleFHUStartSignal(Self)
EndEvent

Function _PollFHULevels()
    ; REV-96 Task 2: body MOVED VERBATIM to SNBaka_FHUInflationModule.PollLevels.
    SNBaka_FHUInflationModule.PollLevels(Self)
EndFunction

; REV-155: OStim climax -> FHU inflation driver. OStim broadcasts
; "ostim_actor_orgasm" per orgasming actor (4-slot service ModEvent shape:
; eventName, SceneID:String, ThreadID:Float, OrgasmedActor:Form -- the
; orgasming actor is the cum SOURCE). Registered presence-gated above
; (OStim.esp); the body is module-owned (SNBaka_FHUInflationModule.
; HandleOStimOrgasm -- the 0.18 bridge's orgasm logic replicated self-owned,
; with the ocummale double-fire guard demoting the 0.18 patch to
; reference-only). NO MCM/yaml surface this rev.
Event OnOStimActorOrgasm(String eventName, String SceneID, Float OrgasmThreadID, Form OrgasmedActor)
    SNBaka_FHUInflationModule.HandleOStimOrgasm(Self, eventName, SceneID, OrgasmThreadID, OrgasmedActor)
EndEvent


