Scriptname SkyrimNet_AcheronIntegration extends Quest
; ============================================================================================
; ACHERON <-> SKYRIMNET BRIDGE — persistent manager for the DOWNED STATE.
; ============================================================================================
; We are a proper Acheron PLUGIN: the consequence worker quest (Downed_SkyrimNet), selected by Acheron
; via SKSE/Acheron/Consequences/*.yaml (Teleport:false), marks a defeated victim "held" and fires the
; first cue. THIS persistent quest then owns the ongoing hold: it polls Acheron.GetDefeated() and, for
; each HELD actor (NPC or player; never creatures), keeps them down until the get-up key, HelpUp,
; Release, winning a struggle, or a hard auto-get-up timer (fAutoGetUpSeconds) frees them -- NOT
; proximity (explicit design change: standing up "because nobody's near" felt arbitrary and fought
; those other systems, so it was removed). A separate, narrower proximity check
; (fProximityCheckSeconds) still runs purely to give Baka's creature-escalation pipeline a shot at a
; nearby creature; it never grants or blocks recovery. Also repeats "X is downed" every
; fCueIntervalSeconds. Recovery also happens the instant something rescues them (help-up), or the
; instant a Baka action resolves the encounter (Release, or winning a QTE). An earlier version of this
; file tried to revive out of Acheron immediately on detection and hand off to a Baka-local hold instead
; of ever letting Acheron keep tracking the defeat -- reverted: it broke follower downing and added more
; failure modes (a control-disable/enable pair split across event handlers) than it removed. Acheron's
; own DefeatActor() collapse replaying on a premature-rescue redown is the accepted tradeoff now.
;
; Because we ride Acheron's own consequence selection (priority/weight) we COEXIST with YameteKudasai and
; any other Acheron mod — no global DisableConsequence, no teleport of our own. Acheron's Teleport:false
; on our consequence is what stops the "left for dead" teleport.
; Requires Acheron + SkyrimNet at runtime ONLY. Baka NOT required.

; ── MCM-tunable (stored in StorageUtil by the MCM; read each tick) ──
Bool  Property bEnabled             = True   Auto
Float Property fProximityCheckSeconds = 10.0  Auto  ; how often we check for a nearby creature (engagement roll only, not recovery)
Float Property fCueIntervalSeconds  = 30.0   Auto  ; narrative "still downed" reminder cadence
; Hard ceiling on how long an abandoned, unattended down lasts -- the ONLY way a victim recovers on
; their own now besides the get-up key, HelpUp, or winning a struggle. Set on every fresh down and
; reset to the full duration whenever a paired animation involving them ends, or they lose a struggle/
; get-up-key QTE -- being actively engaged with (win or lose) means the clock isn't why they're still
; down, so it doesn't get to expire under them mid-scene. Default 600s (10 min).
Float Property fAutoGetUpSeconds    = 600.0  Auto
Float Property fNearbyRadius        = 700.0  Auto  ; "near" = an actual threat/witness in the room (~10m), NOT distant townsfolk
Bool Property bCreatureHandoff = True Auto  ; give Baka's creature-escalation pipeline one shot at a lone downed actor before freeing them (see _TickActor); Baka's own bCreatureEscalation/bCreatureOnPlayer still gate whether anything actually happens
; Rolled EVERY confirm cycle (not one-shot) once nobody able is around — controls how often a nearby
; creature even bothers trying, independent of Baka's own success-roll for the encounter itself. Can
; repeat indefinitely as long as the creature keeps re-engaging after each scene ends; at 100% this is a
; genuine infinite loop by design, not a bug — see _TickActor.
Float Property fCreatureEngageChance = 50.0 Auto
; A creature struggle starting WHILE an actor is still in the middle of the down-transition (the
; bleedout/collapse animation hasn't settled yet) can break the animation state and leave them stuck
; perpetually "downing" -- confirmed real bug from testing, chained off the get-up-race above: a struggle
; that grabbed the player mid-recovery-animation cascaded into a broken QTE (MakeGame stopped returning
; a real UI for the rest of the session) and a stuck bleeding loop. Nobody gets engaged (on-hit roll,
; downed-victim scan, OR this periodic re-engagement roll) until this many seconds after SNAcheron.FreshDownRT
; (stamped at the moment of a genuinely fresh down -- see _CueDowned and Downed_SkyrimNet.RunConsequence).
Float Property fFreshDownGraceDuration = 3.0 Auto
; Player self-recovery: hold the configured key for 3s while downed (by ANY means — Acheron hold OR
; Baka's own local ground window) to attempt a struggle QTE and stand up on your own, independent of
; any NPC/LLM ever calling HelpUp/Release. Player-only — NPCs have no keyboard to hold.
Int   Property iGetUpKey      = 51   Auto  ; DIK scancode, default comma (0x33)
Float Property fGetUpDifficulty = 70.0 Auto

Actor   _player
Keyword _kwNPC     ; ActorTypeNPC — humanoid filter, used by _IsCreature
Bool    _bGetUpQTERunning
Bool    _bGetUpQTEComplete
Bool    _bGetUpQTEWon
Bool    _bGetUpKeyHeld   ; drives _RunGetUpChargeHud's poll loop -- see OnKeyDown/OnKeyUp
Bool    _bDebugLog = True    ; mirrors SNAcheron.DebugLog (MCM) -- gates _Trace
Float   _fLastCombatRT       ; last time the player was seen in combat -- scopes the bleedout net

; ===================== registration + self-heal =====================

Event OnInit()
    _player = Game.GetPlayer()
    _Register()
    RegisterForSingleUpdate(10.0)          ; persistent hold-poll (idles slow until something is held)
    RegisterForSingleUpdateGameTime(0.2)   ; registration self-heal (Quest gets no OnPlayerLoadGame)
EndEvent

; Re-assert runtime-only registrations. Also called by the player alias on every load.
Function _Register()
    If !_player
        _player = Game.GetPlayer()
    EndIf
    If !_kwNPC
        _kwNPC = Game.GetFormFromFile(0x00013794, "Skyrim.esm") as Keyword   ; ActorTypeNPC
    EndIf
    Acheron.RegisterForActorRescued(Self)   ; so help-up / external rescue clears our hold immediately
    ; Ground truth for WHICH actor Downed_SkyrimNet.RunConsequence() is actually about -- see
    ; OnActorDefeated below and _ResolveVictim's use of the stash it leaves.
    Acheron.RegisterForActorDefeated(Self)
    SkyrimNetApi.RegisterDecorator("acheron_state", "SkyrimNet_AcheronIntegration", "GetAcheronState")
    ; Advertise to Baka (and anything else) that the integration is alive, and listen for down requests —
    ; other mods hand us a victim and WE do the defeat + hold, so downing is centralised here.
    StorageUtil.SetIntValue(_player, "SNAcheron.Present", 1)
    RegisterForModEvent("SNBaka_RequestAcheronDown", "OnDownRequest")
    RegisterForModEvent("SNBaka_RequestAcheronRelease", "OnReleaseRequest")
    ; Always listening for the get-up key, downed or not — cheap (pure event, no polling), and simpler
    ; than trying to register/unregister exactly at every down/recover call site across two mods.
    ; OnKeyUp checks live downed state itself, so listening while not downed is a harmless no-op.
    RegisterForKey(iGetUpKey)
    _RegisterHunterPrideOptions()
    ; RegisterForSingleUpdate only ever got its FIRST kick from OnInit(), which fires exactly once
    ; per quest instance, ever — never again after a script update. On any save where this quest was
    ; first initialized before the hold-poll loop existed (or under any older version of this script),
    ; OnUpdate() never ran even once, silently, for the rest of that save's life: no periodic re-cue,
    ; no proximity recovery, no debug trace, nothing — regardless of bDebugLog. _Register() is the one
    ; thing guaranteed to run on EVERY load (via SNAcheron_PlayerAlias.OnPlayerLoadGame), so arm the
    ; poll here too; OnUpdate() re-arms itself every tick afterward, so this only needs to fire once
    ; per load and is a harmless no-op restart if the loop was already running.
    RegisterForSingleUpdate(1.0)
    _Trace("registered rescue hook + decorator + down/release listeners + hold-poll")
EndFunction

; ===================== AcheronNG "Hunter's Pride" native option menu =====================
; AcheronNG has its own on-screen option menu shown when the player activates (vanilla E) a defeated
; actor -- other mods (e.g. OSimpleAssault) register into it via Acheron.AddOption/
; RegisterForHunterPrideSelect rather than building a separate UI. We had a completely separate
; PrismaUI-based path (the lesser power) and never plugged into this native one at all, so pressing E
; on a downed actor never showed any of our actions. This registers the same downed-victim actions
; Baka's own PrismaUI menu offers, so they show up on plain E/activate too.
; Registered here (not in Baka) because Acheron Integration already has a real, intentional hard
; dependency on Acheron.psc (Baka deliberately doesn't, to stay standalone) -- if Baka isn't installed,
; nothing would be listening for the dispatch below, so skip registering dead options entirely.
Function _RegisterHunterPrideOptions()
    If StorageUtil.GetIntValue(_player, "SNBaka.Present", 0) != 1
        Return
    EndIf
    If !Acheron.HasOption("snbaka_hp_escalate")
        Acheron.AddOption("snbaka_hp_escalate",    "Escalate",   "Interface\\Acheron\\SNBaka\\action_icon.swf")
    EndIf
    If !Acheron.HasOption("snbaka_hp_investigate")
        Acheron.AddOption("snbaka_hp_investigate", "Investigate", "Interface\\Acheron\\SNBaka\\action_icon.swf")
    EndIf
    If !Acheron.HasOption("snbaka_hp_inspect")
        Acheron.AddOption("snbaka_hp_inspect",     "Inspect",    "Interface\\Acheron\\SNBaka\\action_icon.swf")
    EndIf
    If !Acheron.HasOption("snbaka_hp_standback")
        Acheron.AddOption("snbaka_hp_standback",   "Stand Back", "Interface\\Acheron\\SNBaka\\action_icon.swf")
    EndIf
    If !Acheron.HasOption("snbaka_hp_helpup")
        Acheron.AddOption("snbaka_hp_helpup",      "Help Up",    "Interface\\Acheron\\SNBaka\\action_icon.swf")
    EndIf
    Acheron.RegisterForHunterPrideSelect(Self)
EndFunction

; Fires when the player picks ANY registered Hunter's Pride option on ANY defeated actor -- not just
; ours, so the ID check below is required (ignore anything that isn't one of our five). We don't call
; Baka's action functions directly (no hard script reference, by design); instead we hand off through
; the same "stash the actor, fire a mod event" pattern used everywhere else in this mod pair. Investigate
; and Inspect require a female target and Escalate/HelpUp have their own eligibility checks -- those are
; enforced inside Baka's own Execute functions exactly as they already are for the PrismaUI menu, not
; duplicated here.
Event OnHunterPrideSelect(int aiOptionID, Actor akTarget)
    If !akTarget
        Return
    EndIf
    String choice = ""
    If aiOptionID == Acheron.GetOptionID("snbaka_hp_escalate")
        choice = "escalate"
    ElseIf aiOptionID == Acheron.GetOptionID("snbaka_hp_investigate")
        choice = "investigate"
    ElseIf aiOptionID == Acheron.GetOptionID("snbaka_hp_inspect")
        choice = "inspect"
    ElseIf aiOptionID == Acheron.GetOptionID("snbaka_hp_standback")
        choice = "standback"
    ElseIf aiOptionID == Acheron.GetOptionID("snbaka_hp_helpup")
        choice = "helpup"
    Else
        Return   ; some other mod's option, not ours
    EndIf
    StorageUtil.SetFormValue(_player, "SNAcheron.HunterPrideTarget", akTarget)
    SendModEvent("SNAcheron_HunterPrideChoice", choice)
    _Trace("Hunter's Pride: " + choice + " selected on " + akTarget)
EndEvent

; Called externally (Downed_SkyrimNet on every combat defeat, the MCM on every open) to self-heal two
; distinct failure modes seen in testing: (1) this quest's "Start Game Enabled" never actually fired, so
; OnInit/_Register never ran at all — Start() catches that; (2) the harder case — it DID start and ran
; fine for a while (one successful recovery observed), then its self-renewing OnUpdate chain silently
; died mid-session. A runtime error partway through a tick can abort before OnUpdate reaches its own
; tail-end RegisterForSingleUpdate call, and nothing else re-arms it until the next OnUpdateGameTime
; (~12 game-minutes away) or save reload. IsRunning() stays TRUE in that case, so a Start()-only check
; would miss it entirely. Re-registering here unconditionally covers both: RegisterForSingleUpdate on an
; already-pending timer just reschedules it, it never stacks duplicate ticks.
Function EnsureAlive()
    If !IsRunning()
        Start()
    EndIf
    _Register()
    RegisterForSingleUpdate(1.0)
EndFunction

; Another mod (Baka) asked us to RELEASE actors it queued — e.g. a downed victim who won a struggle and
; overpowered their attacker. They are fit to continue, so we drop the hold and rescue them out of Acheron.
Event OnReleaseRequest(String eventName, String strArg, Float numArg, Form sender)
    Int cnt = StorageUtil.FormListCount(_player, "SNBaka.AcheronReleaseQueue")
    Int i = 0
    While i < cnt
        Actor a = StorageUtil.FormListGet(_player, "SNBaka.AcheronReleaseQueue", i) as Actor
        If a
            ; Held cleared FIRST, before RescueActor fires OnActorRescued -- same sanctioning rule as
            ; _Recover. (Restored revert-casualty: this handler's whole job is ending the Held state
            ; Baka's _OnVictimWon can't reach -- it only clears Baka-side flags -- and the line was lost
            ; during the reverted local-down experiment.)
            StorageUtil.SetIntValue(a, "SNAcheron.Held", 0)
            If Acheron.IsDefeated(a)
                Acheron.RescueActor(a, true)
                ; OSimpleDefeat (a sibling mod doing the same Acheron+OStim flow) always pairs RescueActor
                ; with an explicit ReleaseActor call — RescueActor is documented as queued/async,
                ; ReleaseActor removes pacify immediately.
                Acheron.ReleaseActor(a)
            EndIf
            ; Same fix as _Recover(): force the actual stand-up, don't rely on RescueActor alone to end
            ; the visual pose and resume AI.
            Debug.SendAnimationEvent(a, "IdleForceDefaultState")
            a.EvaluatePackage()
            SkyrimNetApi.RegisterEvent("acheron_recovered", \
                a.GetDisplayName() + " shakes off the attack and gets back on their feet, ready to keep fighting.", \
                a, None)
            _Trace("released on request (won struggle): " + a)
        EndIf
        i += 1
    EndWhile
    StorageUtil.FormListClear(_player, "SNBaka.AcheronReleaseQueue")
EndEvent

; Another mod (Baka) asked us to defeat + hold one or more actors it queued. WE own the defeat.
Event OnDownRequest(String eventName, String strArg, Float numArg, Form sender)
    If !bEnabled
        Return
    EndIf
    Int cnt = StorageUtil.FormListCount(_player, "SNBaka.AcheronDownQueue")
    Int i = 0
    While i < cnt
        Actor a = StorageUtil.FormListGet(_player, "SNBaka.AcheronDownQueue", i) as Actor
        If a && !a.IsDead() && !_IsCreature(a)
            _DownActor(a)
        EndIf
        i += 1
    EndWhile
    StorageUtil.FormListClear(_player, "SNBaka.AcheronDownQueue")
    RegisterForSingleUpdate(1.0)   ; kick the hold-poll so management starts promptly
EndEvent

; Defeat an actor via Acheron and take ownership of the downed state (hold + first cue). Also the
; premature-rescue redown: OnActorRescued calls this every time Acheron's OWN clock retries and finds a
; threat still nearby.
Function _DownActor(Actor a)
    ; Redowning someone ALREADY held used to replay the FULL cue every single time -- re-queuing into
    ; Baka's creature-pounce check, re-firing the SkyrimNet "acheron_downed" narration, re-tracking the
    ; aggressor -- even though the victim never actually got up in between. Confirmed in testing as a
    ; player repeatedly "going down" over and over while a creature loitered nearby. Only replay the
    ; full cue on a genuinely FRESH down; a re-assert just keeps Acheron's own state/timer refreshed
    ; (still needed, or its clock tries to rescue again almost immediately) without repeating everything
    ; downstream of it.
    Bool alreadyHeld = StorageUtil.GetIntValue(a, "SNAcheron.Held", 0) == 1
    ; Only call DefeatActor when Acheron does NOT already track them as defeated. Re-asserting the
    ; native defeat on an already-defeated actor was our default (every premature-rescue redown, every
    ; park re-assert — 2-4 per cycle in the logs) while recovery only ever calls RescueActor ONCE. If
    ; Acheron's native player lockdown counts defeats, that imbalance leaves lock debt no recovery can
    ; pay off — the best match for "pressed the get-up key, stood, but still can't attack or interact"
    ; surviving every Papyrus-side sanitizer. Skipping the redundant call also stops the collapse
    ; animation replaying on re-asserts. Held/deadline bookkeeping below still refreshes either way;
    ; if Acheron's own clock DID rescue them (IsDefeated false), this is a genuine re-down and runs.
    If !Acheron.IsDefeated(a)
        Acheron.DefeatActor(a)
        _Trace("_DownActor: DefeatActor called on " + a + " (was not tracked as defeated)")
    Else
        _Trace("_DownActor: " + a + " already defeated in Acheron -- refreshing bookkeeping only, no native re-assert")
    EndIf
    StorageUtil.SetIntValue(a, "SNAcheron.Held", 1)
    ; Acheron's defeat immunity blocks the damage, but attackers with an ALREADY-locked combat target
    ; keep swinging at the body (confirmed live: giants wailing on a downed player, every hit whiffing).
    ; Its pacify only blocks NEW acquisition — clear the stale locks ourselves on every down/re-assert.
    ; Only actors currently targeting THIS victim are touched; anyone fighting someone else keeps their
    ; fight, and the player's own combat state is never poked.
    Actor[] loadedAtk = PO3_SKSEFunctions.GetActorsByProcessingLevel(0)
    Int ai = 0
    While ai < loadedAtk.Length
        Actor atk = loadedAtk[ai]
        If atk && atk != a && atk != _player && !atk.IsDead() && atk.GetCombatTarget() == a
            atk.StopCombat()
            atk.EvaluatePackage()
            _Trace("cleared stale combat lock: " + atk + " was still targeting downed " + a)
        EndIf
        ai += 1
    EndWhile
    ; Reset the NPC auto-get-up ceiling on EVERY down/redown through here, including re-asserts --
    ; explicit spec: any interaction (a scene ending re-downs through this path, a premature-rescue
    ; catch, a struggle loss) restarts the clock at the full duration. The re-assert branch used to
    ; return before any reset, so a victim re-downed after a long scene could have their timer expire
    ; almost immediately afterward. (_CueDowned resets it too on the fresh branch; double-set is
    ; harmless and keeps both paths self-sufficient.)
    StorageUtil.SetFloatValue(a, "SNBaka.AutoGetUpDeadlineRT", Utility.GetCurrentRealTime() + fAutoGetUpSeconds)
    If alreadyHeld
        _Trace("re-asserted hold on " + a + " (already down -- skipping the down cue replay)")
        Return
    EndIf
    _CueDowned(a)   ; fires the full "you can Escalate / help up / struggle" cue AND starts the check clock
    _Trace("downed on request: " + a)
EndFunction

Event OnUpdateGameTime()
    _Register()
    RegisterForSingleUpdate(10.0)           ; make sure the hold-poll stays armed across loads
    RegisterForSingleUpdateGameTime(0.2)
EndEvent

; Settings live in StorageUtil (player-keyed) so the MCM writes them with no CK property link.
Function _LoadSettings()
    If !_player
        _player = Game.GetPlayer()
    EndIf
    bEnabled             = StorageUtil.GetIntValue(_player,   "SNAcheron.Enabled",      1) == 1
    fCueIntervalSeconds  = StorageUtil.GetFloatValue(_player, "SNAcheron.CueInterval",  30.0)
    fProximityCheckSeconds = StorageUtil.GetFloatValue(_player, "SNAcheron.ProxInterval", 10.0)
    fAutoGetUpSeconds    = StorageUtil.GetFloatValue(_player, "SNAcheron.AutoGetUpSeconds", 600.0)
    fNearbyRadius        = StorageUtil.GetFloatValue(_player, "SNAcheron.Radius",       700.0)
    bCreatureHandoff     = StorageUtil.GetIntValue(_player, "SNAcheron.CreatureHandoff", 1) == 1
    fCreatureEngageChance = StorageUtil.GetFloatValue(_player, "SNAcheron.CreatureEngageChance", 50.0)
    fGetUpDifficulty     = StorageUtil.GetFloatValue(_player, "SNAcheron.GetUpDifficulty", 70.0)
    _bDebugLog           = StorageUtil.GetIntValue(_player, "SNAcheron.DebugLog", 1) == 1
    Int newKey = StorageUtil.GetIntValue(_player, "SNAcheron.GetUpKey", 51)
    If newKey != iGetUpKey
        UnregisterForKey(iGetUpKey)
        iGetUpKey = newKey
        RegisterForKey(iGetUpKey)
        _Trace("get-up key rebound to " + iGetUpKey)
    EndIf
EndFunction

; ===================== player self-recovery (hold key -> QTE) =====================

; True if the player is downed by ANY means — Acheron's own hold OR Baka's local ground window OR
; plain vanilla bleedout. Reads Baka's flag directly (no hard dependency, same pattern as
; _IsDownedElsewhere) so this works whether or not Baka Integration is even installed.
Bool Function _PlayerIsDownedAny()
    If !_player
        Return False
    EndIf
    Return StorageUtil.GetIntValue(_player, "SNBaka.OnGround", 0) == 1 \
        || StorageUtil.GetIntValue(_player, "SNAcheron.Held",  0) == 1 \
        || _player.IsBleedingOut()
EndFunction

; Fires the instant the key goes down. Only starts the charge-bar poll if the player is actually
; downed right now -- an idle press of this key (not downed) should do nothing at all, same as it
; always has; OnKeyUp's own downed-state check is still the real gate for the QTE itself, this just
; adds visual feedback for the 3s you'd otherwise be holding blind.
Event OnKeyDown(Int KeyCode)
    If KeyCode != iGetUpKey
        Return
    EndIf
    If _bGetUpQTERunning || Utility.IsInMenuMode() || !_PlayerIsDownedAny()
        _Trace("get-up key DOWN: not starting charge HUD -- qteRunning=" + _bGetUpQTERunning + " inMenu=" + Utility.IsInMenuMode() + " downed=" + _PlayerIsDownedAny())
        Return
    EndIf
    If StorageUtil.GetIntValue(_player, "SNBaka.Locked", 0) == 1
        _Trace("get-up key DOWN: ignored -- player is Baka-locked mid-interaction (the struggle's own QTE is the escape route)")
        Return
    EndIf
    _Trace("get-up key DOWN: starting charge HUD")
    _bGetUpKeyHeld = True
    _RunGetUpChargeHud()
EndEvent

; Blocking poll loop (same pattern _RunGetUpQTE already uses) that pushes charge progress to the
; PrismaUI HUD bar every tick until release, a QTE actually starts, or the player stops being downed by
; some other means mid-hold. _bGetUpKeyHeld is cleared by OnKeyUp the instant the key comes back up, so
; this notices within one tick and hides the bar itself -- OnKeyUp doesn't need to touch the HUD at all.
Function _RunGetUpChargeHud()
    Float startRT = Utility.GetCurrentRealTime()
    Int ticks = 0
    While _bGetUpKeyHeld && !_bGetUpQTERunning && _PlayerIsDownedAny() && !Utility.IsInMenuMode()
        Float heldFor = Utility.GetCurrentRealTime() - startRT
        SNBakaUI.SetGetUpCharge(heldFor / 3.0)
        ticks += 1
        If heldFor >= 3.5
            ; Safety cap -- holding well past the 3.0s threshold with no OnKeyUp yet (stuck key event,
            ; alt-tab, whatever) shouldn't spin this forever.
            _bGetUpKeyHeld = False
        Else
            Utility.Wait(0.05)
        EndIf
    EndWhile
    SNBakaUI.SetGetUpCharge(-1.0)
    _Trace("get-up key charge HUD ended after " + ticks + " ticks (held=" + _bGetUpKeyHeld + " qteRunning=" + _bGetUpQTERunning + " downed=" + _PlayerIsDownedAny() + " inMenu=" + Utility.IsInMenuMode() + ")")
EndFunction

; Hold the configured key for 3s while downed to attempt a self-recovery struggle QTE. Registered
; unconditionally in _Register() (cheap, event-driven, no polling cost while not downed) — the actual
; "are you even downed" check happens here, at release time, using live state.
Event OnKeyUp(Int KeyCode, Float HoldTime)
    If KeyCode != iGetUpKey
        Return   ; not our key — silent, this fires for every key on the keyboard being registered would be spam, but we only register our own key so this branch should never actually hit
    EndIf
    _bGetUpKeyHeld = False   ; stops _RunGetUpChargeHud's loop (and hides the HUD bar) on its next tick
    _Trace("get-up key released: holdTime=" + HoldTime + " (need >= 3.0) qteRunning=" + _bGetUpQTERunning + " inMenu=" + Utility.IsInMenuMode())
    If HoldTime < 3.0 || _bGetUpQTERunning || Utility.IsInMenuMode()
        Return
    EndIf
    Bool onGround = StorageUtil.GetIntValue(_player, "SNBaka.OnGround", 0) == 1
    Bool held     = StorageUtil.GetIntValue(_player, "SNAcheron.Held",  0) == 1
    Bool bleeding = _player.IsBleedingOut()
    _Trace("get-up key: downed-state check — SNBaka.OnGround=" + onGround + " SNAcheron.Held=" + held + " IsBleedingOut=" + bleeding)
    If !onGround && !held && !bleeding
        _Trace("get-up key: not currently downed by any known means — ignoring")
        Return
    EndIf
    ; SPEC CHANGE with the park design: the old "wildcard escape valve, deliberately not gated on
    ; SNBaka.Locked" rule existed when Locked-while-downed could mean a stuck state. Now the player
    ; stays Held/Locked straight THROUGH a healthy struggle/scene, so the key firing there
    ; interrupted live animations (confirmed report). While Baka has the player Locked, the
    ; interaction owns them — its own QTE is the escape route. Still NOT gated on _NearbyThreat:
    ; outside interactions this remains the deliberate way past "nobody recovers with a threat around".
    If StorageUtil.GetIntValue(_player, "SNBaka.Locked", 0) == 1
        _Trace("get-up key: ignored -- player is Baka-locked mid-interaction (the struggle's own QTE is the escape route)")
        Return
    EndIf
    _Trace("get-up key: all checks passed — starting QTE")
    _RunGetUpQTE()
EndEvent

Event OnGetUpQTEEnd(string asEventName, string asStringArg, float afNumArg, form akSender)
    _bGetUpQTEWon      = afNumArg > 0
    _bGetUpQTEComplete = True
EndEvent

; Runs the same context-free struggle minigame used everywhere else in this mod family (Flash Games —
; Struggling QTE), with proper animation on all three outcomes instead of a bare minigame call:
;   - during: the victim-side pose from the Sabrecat creature struggle (Babo_SabrecatQTE_S01_A01) —
;     the actor is down on the ground fighting to get up, which fits holding a key to stand back up far
;     better than the choke/escalate-resist pose used before. Played solo, no attacker needed.
;   - win: a real stand-up transition (reusing the DownPose -> get-up mapping already used by _Recover)
;     before freeing them, covering BOTH an Acheron hold (_Recover) and a Baka local ground window (asks
;     Baka to _ForceRecover itself via mod event, since we can't reach its instance fields directly).
;   - lose: reverts to the stored down pose and fires a distinct failure cue.
;   - interrupted (something else grabs the player mid-QTE, e.g. SNBaka.Locked flips to 1): force-closes
;     the QTE menu and drops out silently — no cue, they're just still down, per spec.
Function _RunGetUpQTE()
    _bGetUpQTERunning  = True
    _bGetUpQTEComplete = False
    _bGetUpQTEWon      = False
    Debug.SendAnimationEvent(_player, "Babo_SabrecatQTE_S01_A01")
    RegisterForModEvent("AEL_GameEnd", "OnGetUpQTEEnd")
    Bool started = AELStruggle.MakeGame(fGetUpDifficulty)
    If !started
        UnregisterForModEvent("AEL_GameEnd")
        _bGetUpQTERunning = False
        _RestoreDownPoseAnim()
        Return
    EndIf
    _Trace("get-up QTE started for player")
    Float elapsed = 0.0
    Bool interrupted = False
    While !_bGetUpQTEComplete && elapsed < 30.0 && !interrupted
        Utility.Wait(0.1)
        elapsed += 0.1
        If StorageUtil.GetIntValue(_player, "SNBaka.Locked", 0) == 1
            interrupted = True
        EndIf
    EndWhile
    UnregisterForModEvent("AEL_GameEnd")
    ; _bGetUpQTERunning deliberately stays TRUE through the whole win/lose resolution below (animation +
    ; recovery), not just the minigame itself -- confirmed real race from testing: clearing it here left
    ; a ~1s window (the win branch's own stand-up animation wait) where _TickActor's periodic creature-
    ; engagement roll could fire and grab the player straight back into a NEW forced struggle before
    ; _Recover() had even run. From the player's perspective that reads as "won the QTE, got grappled
    ; mid-animation." Cleared at every exit point below instead of once up front.
    If interrupted
        _bGetUpQTERunning = False
        SPE_Interface.CloseCustomMenu()
        _RestoreDownPoseAnim()
        _Trace("get-up QTE interrupted by another interaction — dropped silently")
        Return
    EndIf
    If !_PlayerIsDownedAny()
        _bGetUpQTERunning = False
        Return   ; recovered some other way (HelpUp/Release/timeout) while the QTE was running
    EndIf
    If _bGetUpQTEWon
        _Trace("get-up QTE won by player")
        String downPose  = StorageUtil.GetStringValue(_player, "SNBaka.DownPose", "")
        String getUpAnim = ""
        If downPose == "Babo_DefeatTraumaLie"
            getUpAnim = "Babo_DefeatTraumaStand"
        Else
            getUpAnim = "staggerStart"   ; generic fallback — same event Baka's own "Stand Back" uses
        EndIf
        Debug.SendAnimationEvent(_player, getUpAnim)
        Utility.Wait(1.0)
        _Recover(_player)   ; no-op if the player wasn't Acheron-held
        ; Ask Baka to force-recover too, in case it's the one holding the player locally — harmless
        ; no-op if Baka isn't installed or wasn't the one holding them (nobody's listening either way).
        StorageUtil.FormListAdd(_player, "SNAcheron.ForceRecoverQueue", _player)
        SendModEvent("SNAcheron_RequestForceRecover")
        ; Post-escape grace, same as Baka's struggle wins: a player who just fought their way up should
        ; not be instantly re-attacked the frame they stand. Reads the StorageUtil mirror Baka's MCM
        ; writes (shared key, no hard dependency; default matches Baka's own default). Deliberately
        ; inside the QTE-running window so _TickActor keeps deferring until the grace ends too.
        Float grace = StorageUtil.GetFloatValue(_player, "SNBaka.EscapeGraceDuration", 4.0)
        If grace > 0.0
            _player.SetGhost(True)
            _Trace("get-up QTE won: player untouchable for " + grace + "s post-escape grace")
            Utility.Wait(grace)
            _player.SetGhost(False)
            _Trace("get-up QTE post-escape grace ended")
        EndIf
        _bGetUpQTERunning = False
    Else
        _Trace("get-up QTE failed for player")
        _RestoreDownPoseAnim()
        ; Trying and failing isn't "sitting abandoned" -- reset the hard auto-get-up ceiling back to the
        ; full duration, same as any other lost struggle already does via _CleanupPair (this QTE has no
        ; paired animation to route through that, so it needs its own reset here).
        StorageUtil.SetFloatValue(_player, "SNBaka.AutoGetUpDeadlineRT", Utility.GetCurrentRealTime() + fAutoGetUpSeconds)
        SkyrimNetApi.RegisterEvent("acheron_getup_failed", \
            _player.GetDisplayName() + " strains against the pain and tries to stand, but collapses back down, still too weak to break free.", \
            _player, None)
        _bGetUpQTERunning = False
    EndIf
EndFunction

; Undoes the temporary struggle pose (_RunGetUpQTE plays Babo_SabrecatQTE_S01_A01 while the QTE runs)
; by re-asserting whatever down pose Baka had already picked for this actor. Confirmed real bug from
; testing: with NO stored pose -- the NORMAL case for a plain combat defeat, where no Baka QTE ever
; ran -- this was a silent no-op, leaving the player permanently wedged in the struggle pose after a
; failed get-up attempt. Force the graph back to default state instead, so Acheron's own native
; bleedout/downed idle can re-assert itself.
Function _RestoreDownPoseAnim()
    String downPose = StorageUtil.GetStringValue(_player, "SNBaka.DownPose", "")
    If downPose != ""
        Debug.SendAnimationEvent(_player, downPose)
    Else
        Debug.SendAnimationEvent(_player, "IdleForceDefaultState")
    EndIf
EndFunction

; ===================== Acheron defeat hook =====================

; Fires with the EXACT victim reference, right around when AcheronNG picks a consequence for that same
; defeat. Downed_SkyrimNet.RunConsequence() (a CK-wired quest-stage fragment, so it can't receive the
; victim as a parameter) used to GUESS who it was for -- "is the player currently defeated-and-unheld?
; assume it's them" -- which is wrong the instant more than one actor is ambiguously in that state at
; once. Confirmed real bug from testing: Joylie was defeated and our consequence quest genuinely started
; for her, but the player ALSO happened to still read Acheron.IsDefeated()=true (mid her own separate
; cycle) with SNAcheron.Held=0 at that exact moment, so the resolver grabbed the player instead --
; Joylie's actual defeat event was silently dropped, every time this collision happened. Stash the real
; reference here so _ResolveVictim can just use it directly instead of guessing.
Event OnActorDefeated(Actor akVictim)
    If !akVictim
        Return
    EndIf
    StorageUtil.SetFormValue(_player,  "SNAcheron.LastDefeatedActor", akVictim)
    StorageUtil.SetFloatValue(_player, "SNAcheron.LastDefeatedRT", Utility.GetCurrentRealTime())
    ; Adoption net for defeats AcheronNG never routes to our consequence at all -- confirmed real case
    ; from testing (its log: "Looking up quest of type 7 ... No event quest found"): the player was
    ; natively defeated, no consequence quest started, so NOTHING managed that down -- and Acheron's own
    ; clock later stood them up on its own, which the spec forbids. Give RunConsequence a few seconds to
    ; claim the victim the normal way first; if nobody has, adopt them into our management here.
    ; ALL humanoids now, not just player/teammates -- confirmed gap from testing: a random (non-follower)
    ; NPC downed this way got no "X is downed" cue at all, so the LLM never knew. Accepted coexistence
    ; tradeoff: if some OTHER Acheron consequence mod claimed this same defeat, we can't detect that
    ; (only our own claims set SNAcheron.Held) and will manage them on top of it -- a mod that teleports
    ; its victims away moves them out of reach anyway, which bounds the damage.
    If bEnabled && !_IsCreature(akVictim)
        Utility.Wait(3.0)
        If StorageUtil.GetIntValue(akVictim, "SNAcheron.Held", 0) != 1 \
                && StorageUtil.GetIntValue(akVictim, "SNBaka.Locked", 0) != 1 \
                && Acheron.IsDefeated(akVictim) && !akVictim.IsDead()
            _Trace("defeat of " + akVictim + " was never claimed by our consequence (none selected?) -- adopting")
            StorageUtil.SetIntValue(akVictim, "SNAcheron.Held", 1)
            _CueDowned(akVictim)
            RegisterForSingleUpdate(1.0)   ; kick the hold-poll so management starts promptly
        EndIf
    EndIf
EndEvent

; ===================== Acheron rescue hook =====================

Event OnActorRescued(Actor akVictim)
    If !akVictim
        Return
    EndIf
    ; Explicit spec: NOBODY recovers on their own. The only sanctioned ways up are the get-up key,
    ; being helped (HelpUp/Release/Stand Back), winning a struggle QTE, or (NPCs only) the auto-get-up
    ; timer in _TickActor. Every one of those clears SNAcheron.Held BEFORE its RescueActor call reaches
    ; this event -- so a rescue arriving while Held (or Baka's Captive flag) is still set can only be
    ; AcheronNG's own internal defeat-duration clock cutting someone loose out from under us. Redown,
    ; unconditionally -- the old "let it stand if nobody's near" branch here was itself an unsanctioned
    ; auto-recovery and is gone. (Yes, the redown replays the collapse animation; accepted tradeoff, the
    ; manual-hold alternative caused three separate control-lock bugs.)
    If StorageUtil.GetIntValue(akVictim, "SNAcheron.Held", 0) == 1 || StorageUtil.GetIntValue(akVictim, "SNBaka.Captive", 0) == 1
        ; PLAYER ONLY: AcheronNG's own defeat-duration clock retries its rescue on a cadence we don't
        ; control, and every redown replays the collapse — fighting it forever produced a visible
        ; endless down/up/down loop on the player (confirmed report). Redown ONCE to catch a stray
        ; early rescue; a SECOND premature rescue in the same down cycle means Acheron insists —
        ; accept it and recover the player properly instead of loop-fighting a clock we can't beat.
        ; NPCs keep the strict unconditional redown: their auto-get-up ceiling bounds the worst case,
        ; and their redowns are load-bearing during scene transitions. Skip the give-up while the
        ; player is Locked (mid-struggle/scene) — rescues arriving there are interaction machinery,
        ; not Acheron's clock, and the hold must survive them.
        If akVictim == _player && StorageUtil.GetIntValue(akVictim, "SNBaka.Locked", 0) != 1
            Int fights = StorageUtil.GetIntValue(akVictim, "SNAcheron.PrematureRescues", 0) + 1
            StorageUtil.SetIntValue(akVictim, "SNAcheron.PrematureRescues", fights)
            If fights >= 2
                _Trace("premature rescue x" + fights + " for the player in one down cycle -- Acheron insists, accepting recovery instead of loop-fighting it")
                StorageUtil.SetIntValue(akVictim, "SNBaka.Captive", 0)
                StorageUtil.SetIntValue(akVictim, "SNAcheron.PrematureRescues", 0)
                _Recover(akVictim)   ; clears Held first (sanctioning), stand-up + control restore + cleanup
                Return
            EndIf
        EndIf
        _Trace("rescue for " + akVictim + " was premature (still Held/Captive by us) -- redowning")
        _DownActor(akVictim)
        Return
    EndIf
    StorageUtil.SetIntValue(akVictim, "SNAcheron.PrematureRescues", 0)   ; clean exit -> fresh budget next cycle
    _Trace("rescue for " + akVictim + " -- sanctioned (Held already cleared by whichever of our recovery paths did it), letting it stand")
EndEvent

; ===================== persistent hold-poll =====================

Event OnUpdate()
    _LoadSettings()
    Float now = Utility.GetCurrentRealTime()
    Bool anyHeld = False

    If bEnabled
        ; Vanilla-bleedout net, REINSTATED but combat-scoped. The permanent version was deleted after
        ; an empty empirical test — and one session later the case it guarded appeared: a civilian
        ; NPC (Lani) whose defeat Acheron's kill-hook never sees (essentials never take the killing
        ; blow) entered VANILLA bleedout, invisible to both mods, and vanilla stood her back up in
        ; seconds ("resurrected instantly"). Bleedouts can only BEGIN during a fight, so the net now
        ; runs only while combat is live or within 15s of it ending — idle cost stays zero, and the
        ; player alias kicks this poll the instant combat starts so the first scan isn't late.
        If _player.IsInCombat()
            _fLastCombatRT = now
        EndIf
        If _player.IsInCombat() || (now - _fLastCombatRT) < 15.0
            _ScanForUntrackedBleedout()
        EndIf
        ; Player can be held too (GetDefeated may not list them).
        If _player && Acheron.IsDefeated(_player) && StorageUtil.GetIntValue(_player, "SNAcheron.Held", 0) == 1
            anyHeld = True
            _TickActor(_player, now)
        ElseIf _player && StorageUtil.GetIntValue(_player, "SNAcheron.Held", 0) == 1 \
                && !_player.IsBleedingOut() \
                && StorageUtil.GetIntValue(_player, "SNBaka.OnGround", 0) != 1 \
                && StorageUtil.GetIntValue(_player, "SNBaka.Locked",   0) != 1 \
                && !_bGetUpQTERunning
            ; Stale-state self-heal: Held says down, but NO real downed signal agrees (not Acheron-
            ; defeated, not bleeding out, no Baka ground flag, not mid-scene, no QTE running). This is
            ; the exact residue a recovery on the broken pre-fix build left behind (Held/Ghost never
            ; cleared): the player walks around flagged as downed -- invulnerable (stuck Ghost), unable
            ; to use downed-gated actions ("initiator is downed"), and unkillable-combat-locking every
            ; enemy that swings at them. Clear it all here so an affected SAVE heals itself within one
            ; poll tick instead of carrying the corruption forever.
            _Trace("SELF-HEAL: player flagged Held with no real downed signal agreeing -- clearing stale Held/Essential/Ghost")
            StorageUtil.SetIntValue(_player, "SNAcheron.Held", 0)
            _ForceEssentialForDown(_player, False)
        EndIf
        Actor[] downed = Acheron.GetDefeated(true)
        Int i = 0
        While i < downed.Length
            Actor a = downed[i]
            If a && a != _player && !a.IsDead() && !_IsCreature(a) && StorageUtil.GetIntValue(a, "SNAcheron.Held", 0) == 1
                anyHeld = True
                _TickActor(a, now)
            EndIf
            i += 1
        EndWhile
    EndIf

    ; Self-arm while managing someone OR while the combat-scoped bleedout net is active. When truly
    ; idle, DON'T re-arm at all — down-event kicks, the player alias's combat-start kick, and
    ; OnUpdateGameTime's keepalive own liveness. Idle cost: zero self-driven ticks.
    If anyHeld || _player.IsInCombat() || (now - _fLastCombatRT) < 15.0
        RegisterForSingleUpdate(5.0)
    EndIf
EndEvent

; Vanilla bleedout (an essential/civilian NPC hit to 0 HP — the engine diverts them to bleedout
; BEFORE any killing blow, so Acheron's kill-intercept never fires and neither mod ever hears about
; it) — sweep the loaded area for anyone bleeding out that nobody tracks and fold them into Acheron,
; so the same hold/recovery/witness rules cover them too. Runs only during/just after combat.
Function _ScanForUntrackedBleedout()
    Actor[] loaded = PO3_SKSEFunctions.GetActorsByProcessingLevel(0)
    Int i = 0
    While i < loaded.Length
        Actor a = loaded[i]
        ; !Acheron.IsDefeated: an actor Acheron already tracks is NOT untracked — keeps our own
        ; async handoffs and Acheron's fresh defeats from being double-claimed mid-transition.
        If a && a != _player && !a.IsDead() && !_IsCreature(a) && a.IsBleedingOut() \
                && !Acheron.IsDefeated(a) \
                && StorageUtil.GetIntValue(a, "SNAcheron.Held",  0) != 1 \
                && StorageUtil.GetIntValue(a, "SNBaka.OnGround", 0) != 1 \
                && StorageUtil.GetIntValue(a, "SNBaka.Locked",   0) != 1 \
                && a.GetDistance(_player) < 4000.0
            _Trace("UNTRACKED BLEEDOUT CAUGHT: " + a + " (essential=" + a.GetActorBase().IsEssential() + ") — vanilla bleedout invisible to Acheron; adopting so they stay down under our rules")
            Acheron.DefeatActor(a)
            StorageUtil.SetIntValue(a, "SNAcheron.Held", 1)
            _CueDowned(a)
        EndIf
        i += 1
    EndWhile
EndFunction

; Recovery model, per downed actor -- proximity no longer gates recovery at all (explicit design
; change: standing up because "nobody's near" felt arbitrary and fought the get-up key/HelpUp/struggle
; systems that already exist for exactly this). Three independent things now:
;   • Every fProximityCheckSeconds (~10s): check for a nearby CREATURE specifically, purely to give
;     Baka's creature-escalation pipeline a shot -- this never grants or blocks recovery by itself.
;   • fAutoGetUpSeconds (MCM, default 600s) hard timer: the ONLY way an abandoned victim eventually
;     recovers on their own without the get-up key, HelpUp, or winning a struggle. Set on every fresh
;     down (_CueDowned / Downed_SkyrimNet.RunConsequence) and reset to the full duration whenever a
;     paired animation involving them ends (Baka's _CleanupPair) or they lose a struggle/get-up-key QTE
;     -- being actively engaged with (win or lose) means the clock isn't the reason they're still down,
;     so it doesn't get to expire under them mid-scene. See SNBaka.AutoGetUpDeadlineRT.
;   • Every fCueIntervalSeconds (~30s, separate clock): send a SHORT "still down" reminder. Purely
;     narrative — never gates recovery, never touches the timer above.
Function _TickActor(Actor a, Float now)
    ; Player-only self-recovery QTE in progress — defer entirely. Confirmed bug from testing: without
    ; this, the independent auto-get-up timer could recover the player mid-QTE, before it even resolved.
    ; Same "pause the check clock" treatment as the Baka-lock defer right below.
    If a == _player && _bGetUpQTERunning
        StorageUtil.SetFloatValue(a, "SNAcheron.LastCheckRT",  now)
        Return
    EndIf
    ; Baka owns them while locked in one of its scenes/animations — defer. This INCLUDES the sex scene
    ; started by Escalate: SNBaka.Locked stays 1 through the whole SexLab/OStim scene, and calm/hold
    ; must persist through it (we never rescue/un-hold a victim mid-sex). Safety: if a lock somehow
    ; sticks (Baka scene aborted without clearing it), don't wedge them down forever — after 20 minutes
    ; of continuous lock we ignore it so recovery can still fire. That's well past any real scene length,
    ; so it only ever catches a genuinely abandoned lock, not an in-progress one.
    If StorageUtil.GetIntValue(a, "SNBaka.Locked", 0) == 1
        Float lockSeen = StorageUtil.GetFloatValue(a, "SNAcheron.LockSeenRT", 0.0)
        If lockSeen == 0.0
            StorageUtil.SetFloatValue(a, "SNAcheron.LockSeenRT", now)
            lockSeen = now
            _Trace("deferring to Baka lock on " + a + " (SNBaka.Locked=1) — poll paused until unlocked or 1200s")
        EndIf
        If (now - lockSeen) < 1200.0
            StorageUtil.SetFloatValue(a, "SNAcheron.LastCheckRT",  now)   ; pause the check clock
            Return
        EndIf
        _Trace("stuck lock on " + a + " ignored after " + (now - lockSeen) + "s — allowing recovery")
    Else
        StorageUtil.SetFloatValue(a, "SNAcheron.LockSeenRT", 0.0)
    EndIf

    ; --- Pose-reassertion net: reported cause is "Too Tired To Move", which forces its own animation
    ; onto a downed actor for a while right after an OStim scene ends, silently overwriting our down/
    ; tied pose the instant SNBaka.Locked clears. Resend the SAME pose every ~15s so it wins the fight
    ; back instead of the actor visibly drifting into someone else's forced animation. Cheap: same
    ; event we already sent once, just repeated -- and it's a no-op once nothing else is stomping it. ---
    String pose = StorageUtil.GetStringValue(a, "SNBaka.DownPose", "")
    If pose != ""
        Float lastPoseSent = StorageUtil.GetFloatValue(a, "SNAcheron.LastPoseSentRT", 0.0)
        If (now - lastPoseSent) >= 15.0
            StorageUtil.SetFloatValue(a, "SNAcheron.LastPoseSentRT", now)
            Debug.SendAnimationEvent(a, pose)
        EndIf
    EndIf

    ; --- Creature engagement: periodic roll giving Baka's creature pipeline a shot. Does NOT gate
    ; recovery. This no longer pre-checks the SINGLE tracked threat for creature-ness -- confirmed
    ; blind spot (the old trace even documented it): with a HUMAN as the tracked reference, a creature
    ; standing right next to the same victim never got its periodic shot at all. Baka's own
    ; _TryCreatureEscalateOnDowned does the real work anyway -- a proper creature scan (same-cell +
    ; cross-cell), the humanoid-witness rule, per-victim throttle, scene/lock guards -- and bails
    ; cleanly when no creature is actually around, so the roll here is purely a frequency throttle. ---
    Float lastProx = StorageUtil.GetFloatValue(a, "SNAcheron.LastProxRT", 0.0)
    If (now - lastProx) >= fProximityCheckSeconds
        StorageUtil.SetFloatValue(a, "SNAcheron.LastProxRT", now)
        Float sinceDown = now - StorageUtil.GetFloatValue(a, "SNAcheron.FreshDownRT", 0.0)
        If !bCreatureHandoff
            ; MCM toggle off — no creature hand-off attempts at all.
        ElseIf StorageUtil.GetIntValue(_player, "SNBaka.Present", 0) != 1
            ; Nobody's listening for SNBaka_TryCreatureOnDowned — Baka isn't installed.
        ElseIf sinceDown < fFreshDownGraceDuration
            _Trace(a + " — only " + sinceDown + "s since fresh down, need " + fFreshDownGraceDuration + "s to settle before any creature engagement")
        Else
            Int roll = Utility.RandomInt(1, 100)
            If roll <= fCreatureEngageChance
                StorageUtil.FormListAdd(_player, "SNBaka.CreaturePounceQueue", a)
                SendModEvent("SNBaka_TryCreatureOnDowned", "loop")
                _Trace(a + " — engagement roll " + roll + " <= " + fCreatureEngageChance + ", giving Baka's creature pipeline a shot (its own scan decides if a creature is actually near)")
            EndIf
        EndIf
    EndIf

    ; --- Hard auto-get-up timer: the only unattended recovery path left, and NPC-ONLY. Explicit spec:
    ; the PLAYER never recovers on their own, full stop -- they have the get-up key, HelpUp, and
    ; struggle QTEs; an NPC has no keyboard, so the timer stands in for the key for them. ---
    If a != _player
        Float deadline = StorageUtil.GetFloatValue(a, "SNBaka.AutoGetUpDeadlineRT", 0.0)
        If deadline > 0.0 && now >= deadline
            ; TIED prisoners never auto-recover — the tie runs on its own GAME-hours clock (Baka's
            ; TieUp action sets SNBaka.Tied/TiedUntilGT). While bound: keep re-checking quietly.
            ; Once it lapses: the bindings loosen back to a NORMAL down with a fresh full timer.
            If StorageUtil.GetIntValue(a, "SNBaka.Tied", 0) == 1
                If Utility.GetCurrentGameTime() < StorageUtil.GetFloatValue(a, "SNBaka.TiedUntilGT", 0.0)
                    StorageUtil.SetFloatValue(a, "SNBaka.AutoGetUpDeadlineRT", now + 60.0)
                    Return
                EndIf
                StorageUtil.SetIntValue(a, "SNBaka.Tied", 0)
                StorageUtil.SetFloatValue(a, "SNBaka.TiedUntilGT", 0.0)
                StorageUtil.SetStringValue(a, "SNBaka.DownPose", "")
                Debug.SendAnimationEvent(a, "BleedoutStart")
                StorageUtil.SetFloatValue(a, "SNBaka.AutoGetUpDeadlineRT", now + fAutoGetUpSeconds)
                _Trace(a + " tie lapsed on its own — bindings loosen, back to a normal down with a fresh timer")
                Return
            EndIf
            ; WITNESS GATE (explicit spec: "they should not be able to get up if somebody able is
            ; around"): the unattended-recovery timer only fires when nobody able is nearby. Any
            ; live, standing actor within ~700 units — the player very much included — postpones it
            ; a minute at a time.
            Actor[] loadedW = PO3_SKSEFunctions.GetActorsByProcessingLevel(0)
            Int wi = 0
            While wi < loadedW.Length
                Actor w = loadedW[wi]
                If w && w != a && !w.IsDead() && !w.IsBleedingOut() \
                        && StorageUtil.GetIntValue(w, "SNAcheron.Held", 0) != 1 && w.GetDistance(a) < 700.0
                    StorageUtil.SetFloatValue(a, "SNBaka.AutoGetUpDeadlineRT", now + 60.0)
                    _Trace(a + " auto-get-up postponed — " + w + " is able and nearby")
                    Return
                EndIf
                wi += 1
            EndWhile
            _Trace(a + " auto-get-up timer expired — forcing recovery")
            _Recover(a)
            ; Hand off to Baka's own _ForceRecover -- the single reliable recovery path that actually
            ; clears SNBaka.OnGround/restraint/controls, same mod-event pattern the get-up key's own win
            ; branch already uses.
            StorageUtil.FormListAdd(_player, "SNAcheron.ForceRecoverQueue", a)
            SendModEvent("SNAcheron_RequestForceRecover")
            Return   ; freed — no need to also fire the reminder below
        EndIf
    EndIf

    ; --- Narrative "still downed" reminder: slower cadence, purely informational. ---
    Float lastCheck = StorageUtil.GetFloatValue(a, "SNAcheron.LastCheckRT", 0.0)
    If (now - lastCheck) >= fCueIntervalSeconds
        StorageUtil.SetFloatValue(a, "SNAcheron.LastCheckRT", now)
        _CueStillDowned(a)
    EndIf
EndFunction

; Get a held actor up and out of Acheron. Called from _TickActor's confirm-clear path AND from
; _RunGetUpQTE's win branch -- each of those already traces its OWN reason right before calling this,
; so this function's own trace (at the end) just confirms the outcome, not why.
Function _Recover(Actor a)
    _Trace("_Recover ENTER: " + a)
    ; Held MUST be cleared BEFORE the RescueActor call below fires Acheron's own OnActorRescued event --
    ; that handler now treats "rescued while still Held" as Acheron's own clock cutting someone loose
    ; out from under us and REDOWNS them (see OnActorRescued). Clearing first is what marks this rescue
    ; as sanctioned. (Also a restored revert-casualty: this line was lost during the reverted local-down
    ; experiment, which left every timer/QTE recovery still reading as down forever.)
    StorageUtil.SetIntValue(a,   "SNAcheron.Held",        0)
    StorageUtil.SetFloatValue(a, "SNAcheron.LastCheckRT",  0.0)
    ; The victim is actually being freed now — if Baka pacified the tracked aggressor for an escalation
    ; scene (held pacified on purpose since _EscalationCleanup, so it wouldn't re-engage the still-
    ; subdued victim), restore its aggression here. No hard Baka reference needed: same shared
    ; StorageUtil keys Baka's own _PacifyActor(ak, False) uses, so this works even with Baka installed
    ; but Acheron owning the actual recovery (e.g. the nobody-around timeout).
    Actor trackedThreat = StorageUtil.GetFormValue(a, "SNBaka.GroundWindowAggressor") as Actor
    If trackedThreat && StorageUtil.GetIntValue(trackedThreat, "SNBaka.Pacified", 0) == 1
        trackedThreat.SetActorValue("Aggression", StorageUtil.GetFloatValue(trackedThreat, "SNBaka.OrigAggr", 1.0))
        StorageUtil.SetIntValue(trackedThreat, "SNBaka.Pacified", 0)
    EndIf
    StorageUtil.SetFormValue(a,  "SNBaka.GroundWindowAggressor", None)
    ; Only call Acheron's own rescue/release if Acheron still THINKS this actor is defeated. We revive
    ; out of Acheron immediately at detection time now (RunConsequence/_DownActor), so by the time an
    ; actor is genuinely freed here Acheron usually doesn't consider them defeated at all anymore --
    ; calling RescueActor/ReleaseActor on an actor it doesn't track as defeated is a call its native code
    ; was never meant to receive, and previously left the player unable to move despite
    ; Game.EnablePlayerControls() having run. Kept as a defensive guard for the rare case Acheron still
    ; thinks otherwise (e.g. a defeat we haven't handed off yet).
    If Acheron.IsDefeated(a)
        Acheron.RescueActor(a, true)
        ; OSimpleDefeat (a sibling mod doing the same Acheron+OStim flow) always pairs RescueActor with
        ; an explicit ReleaseActor call — RescueActor is documented as queued/async, ReleaseActor removes
        ; pacify immediately, so this closes the gap while the queued rescue task hasn't run yet.
        Acheron.ReleaseActor(a)
    Else
        _Trace("_Recover(" + a + "): Acheron no longer considers them defeated -- skipping RescueActor/ReleaseActor")
    EndIf
    ; Only clear our forced-Essential flag (if we set one) AFTER Acheron's own rescue has already
    ; restored them to a safe state — clearing it first, while still at defeat-low health, could let
    ; them actually die the instant the protection lifts.
    _ForceEssentialForDown(a, False)
    ; Play a stand-up transition — matching clip if Baka put them in a known down pose (SNBaka.DownPose,
    ; shared StorageUtil key, no hard Baka reference needed), otherwise "staggerStart" (the same generic
    ; get-up event Baka's own "Stand Back" outcome uses). A pure Acheron-native combat defeat never gets
    ; a Baka down pose set at all — that used to mean this whole step was skipped, which is why recovery
    ; after a plain combat defeat had no animation. Now it always plays something.
    String downPose  = StorageUtil.GetStringValue(a, "SNBaka.DownPose", "")
    String getUpAnim = "staggerStart"
    If downPose == "Babo_DefeatTraumaLie"
        getUpAnim = "Babo_DefeatTraumaStand"
    EndIf
    Debug.SendAnimationEvent(a, getUpAnim)
    Utility.Wait(1.0)
    StorageUtil.SetStringValue(a, "SNBaka.DownPose", "")
    ; Force the actual stand-up, same as every OTHER recovery path in Baka/Acheron does (_ForceRecover,
    ; Baka's own _Recover, _CleanupPair, _EscalationCleanup all pair RescueActor/ClearAcheronHold with
    ; this) — this was the one path that relied on RescueActor alone to end the visual pose and resume
    ; AI. If that native call doesn't reliably force the animation graph out of its current down pose,
    ; the actor stays looking exactly as downed as before even though Held is now correctly cleared.
    Debug.SendAnimationEvent(a, "IdleForceDefaultState")
    a.EvaluatePackage()
    If a == Game.GetPlayer()
        ; Belt-and-suspenders control restore — confirmed report: recovering via the get-up key or a
        ; follower HelpUp sometimes left the player unable to attack with a sluggish camera. This path
        ; previously restored NOTHING itself (it relied on Acheron's RescueActor, which is even skipped
        ; above when Acheron no longer tracks the defeat). Each symptom maps to a state someone set and
        ; never cleared: Baka's struggle DisablePlayerControls (fighting flag), OStim's SetPlayerAIDriven
        ; on a scene that got force-stopped, a leftover restraint/pin. All idempotent when already clean.
        _Trace("_Recover(player): sanitize pass -- Acheron.IsDefeated now=" + Acheron.IsDefeated(a) + " (queued rescue may still be in flight if TRUE)")
        Game.EnablePlayerControls()
        Game.SetPlayerAIDriven(False)
        a.SetRestrained(False)
        a.SetDontMove(False)
        ; Lingering Acheron PACIFY on the player is the one state none of the calls above can touch —
        ; earlier builds pacified the player directly, it persists in the save until released, and its
        ; native player handling blocks attack/sprint. The defeat case was already rescued+released
        ; above; this strips the pacify-without-defeat residue. No-op on a clean player.
        Acheron.ReleaseActor(a)
        ; Player controls are REFCOUNTED PER SCRIPT: if BAKA disabled fighting for a struggle and its
        ; own enable never ran (aborted path, refused scene, error mid-cleanup), NOTHING this script
        ; calls can clear it — confirmed live: fresh pre-interaction save, one down/struggle cycle,
        ; get-up-key recovery, attack+sprint dead. Hand the player through Baka's _ForceRecover (the
        ; same queue the NPC auto-timer already uses) so EnablePlayerControls also runs under BAKA's
        ; identity. No-op when Baka isn't installed.
        If StorageUtil.GetIntValue(_player, "SNBaka.Present", 0) == 1
            StorageUtil.FormListAdd(_player, "SNAcheron.ForceRecoverQueue", a)
            SendModEvent("SNAcheron_RequestForceRecover")
        EndIf
    EndIf
    SkyrimNetApi.RegisterEvent("acheron_recovered", \
        a.GetDisplayName() + " comes to and struggles back to their feet.", a, None)
    _Trace("_Recover DONE: " + a + " is up")
EndFunction

; Shared "X is down[, beaten by Y]" text — Global so Downed_SkyrimNet (the combat-defeat entry point)
; can call it too instead of carrying its own copy that has to be kept in sync by hand. GetCombatTarget()
; can be None (victim's no longer flagged in combat by the time a later reminder fires), so the attacker
; clause is left out rather than rendering an empty name.
; Deliberately just the bare fact, no action list: this is the RegisterEvent "content" arg, which
; SkyrimNet displays as its own narrator line independent of whatever trigger YAML also matches the
; eventType. acheron_downed.yaml's own content template already names the actions (PinHelpless,
; ChokeHelpless, HelpUp, Release) plus the talk/demand framing — repeating that list here just produced
; two different-looking lines for the same moment (confirmed from a screenshot of doubled narrator text).
String Function _DownedMsg(Actor a) Global
    Actor atk = a.GetCombatTarget()
    String msg = a.GetDisplayName() + " is down"
    If atk
        msg += ", beaten by " + atk.GetDisplayName()
    EndIf
    Return msg
EndFunction

; SHORT periodic reminder (every fCueIntervalSeconds, ~30s) that keeps the downed actor in the LLM's
; awareness. The concrete follow-up actions were already spelled out in the first cue (_CueDowned) and
; are surfaced by the get_baka_state decorator; this just keeps them present without a wall of text.
Function _CueStillDowned(Actor a)
    SkyrimNetApi.RegisterEvent("acheron_downed", _DownedMsg(a), a.GetCombatTarget(), a)
EndFunction

; ===================== helpers =====================

; Creatures (no ActorTypeNPC keyword) are aggressors, never held. If the keyword failed to resolve we
; err on the side of "humanoid" so we don't silently stop holding everyone.
; The keyword alone is NOT reliable: Falmer and Draugr are creature-behaving races Bethesda still tags
; with ActorTypeNPC (the same keyword every human uses) -- confirmed real bug from testing: every
; Falmer silently read as "not a creature" here, which meant _TickActor's periodic creature-engagement
; roll (the thing that gives Baka's pipeline a repeated shot at a downed victim) never even considered
; one, ever. Race-name match catches these vanilla exceptions first, same technique Baka's own
; _CreatureAnimKey uses for the identical problem, without a hard dependency on Baka's full table.
Bool Function _IsCreature(Actor a)
    If !a
        Return False
    EndIf
    String dispName = a.GetDisplayName()
    If StringUtil.Find(dispName, "Falmer") >= 0 || StringUtil.Find(dispName, "Draugr") >= 0
        Return True
    EndIf
    If _kwNPC
        Return !a.HasKeyword(_kwNPC)
    EndIf
    Return False
EndFunction

; Mirrors SkyrimNet_BakaIntegration._IsDownedAny without requiring Baka to be installed — same flags,
; read directly since they're plain StorageUtil keys, not a hard script dependency (this bridge's own
; header says "Baka NOT required"). Without this, an actor downed via Baka's own ground-window (e.g. a
; QTE-defeated player, which never delegates to Acheron) wasn't recognised as "downed" here at all, so
; they could incorrectly count as a live witness blocking someone else's recovery.
Bool Function _IsDownedElsewhere(Actor a) Global
    Return StorageUtil.GetIntValue(a, "SNBaka.OnGround", 0) == 1 \
        || StorageUtil.GetIntValue(a, "SNAcheron.Held",  0) == 1 \
        || Acheron.IsDefeated(a) \
        || a.IsBleedingOut()
EndFunction

; The tracked reference for whoever/whatever downed this actor (SNBaka.GroundWindowAggressor — shared
; with Baka, set at down-time by Downed_SkyrimNet/_CueDowned/Baka's own ground window, cleared on
; recovery), if it's still alive, not downed itself, and within radius — else fall back to a real scan.
; (_NearbyThreat/_ScanNearbyThreat deleted — audit-confirmed dead since the strict three-condition
; recovery rework removed the "nobody around" auto-release they served; recovery is HelpUp / key /
; QTE win / NPC timer now, none of which ask who's nearby.)

; Borrowed from the Surrender mod's own proven technique (DBSurrenderActive.psc), same shared
; SNBaka.EssentialForcedByUs key Baka's own copy of this uses — whichever mod's _Recover actually runs
; is the one that clears it, regardless of which mod applied it. Confirmed real gap otherwise: nothing
; stopped a downed/held victim from just dying to a stray follow-up hit while helpless.
; Also Ghosts them for the SAME duration -- confirmed from testing: Essential alone stops death but
; not damage, so a downed victim could still be visibly attacked (and staggered/hurt) by anyone whose
; AI wasn't actively held for an in-progress paired animation (Baka's own aggro-cloak only runs DURING
; a struggle/scene, not through the whole "downed and waiting to be picked up" window this covers).
; We can't make other actors stop CHOOSING to swing at a downed victim without touching their own AI
; state persistently (a bigger, separate change) -- Ghost at least means those swings can't actually
; hurt them in the meantime. Never applied to the player during active paired-animation positioning
; (_SetupPair deliberately skips it there, for camera/ragdoll reasons) -- this is a different, simpler
; context (lying in a down pose, not being repositioned), so it's safe here even for the player.
Function _ForceEssentialForDown(Actor ak, Bool abForce)
    If !ak
        Return
    EndIf
    ActorBase bse = ak.GetActorBase()
    If !bse
        Return
    EndIf
    If abForce
        ; NO forced protection anymore -- explicit spec change (mirrors Baka's copy): a downed actor
        ; lives or dies by their own BASE flags. Base Essential/Protected keep vanilla immunities;
        ; everyone else can be finished while down by accumulated damage from anything, and a single
        ; PLAYER hit executes them outright (Baka's OnPlayerHitActor). Call sites kept as the policy
        ; point in case this changes again.
    Else
        If StorageUtil.GetIntValue(ak, "SNBaka.ProtectForcedByUs", 0) == 1
            bse.SetProtected(False)
            StorageUtil.SetIntValue(ak, "SNBaka.ProtectForcedByUs", 0)
        EndIf
        ; Backward-compat restores for state left by earlier builds (Essential-forcing version, and
        ; the down-state Ghost) so an in-flight save heals on its next recovery.
        If StorageUtil.GetIntValue(ak, "SNBaka.EssentialForcedByUs", 0) == 1
            bse.SetEssential(False)
            StorageUtil.SetIntValue(ak, "SNBaka.EssentialForcedByUs", 0)
        EndIf
        If StorageUtil.GetIntValue(ak, "SNAcheron.GhostForcedByUs", 0) == 1
            ak.SetGhost(False)
            StorageUtil.SetIntValue(ak, "SNAcheron.GhostForcedByUs", 0)
        EndIf
    EndIf
EndFunction

Function _CueDowned(Actor a)
    ; Start both clocks here so the first proximity check waits fProximityCheckSeconds and the first
    ; reminder waits fCueIntervalSeconds, rather than firing on the very next poll tick (an unset
    ; timestamp defaults to 0.0, which always looks overdue).
    Float now = Utility.GetCurrentRealTime()
    StorageUtil.SetFloatValue(a, "SNAcheron.LastCheckRT",  now)
    StorageUtil.SetFloatValue(a, "SNAcheron.LastProxRT",   now)
    ; Hard auto-get-up ceiling for this fresh down -- see fAutoGetUpSeconds and _TickActor.
    StorageUtil.SetFloatValue(a, "SNBaka.AutoGetUpDeadlineRT", now + fAutoGetUpSeconds)
    ; Marks the moment of a genuinely FRESH down -- see fFreshDownGraceDuration. Read by both this
    ; script's own _TickActor and Baka's _TryCreatureEscalateOnDowned (shared key, no hard dependency).
    StorageUtil.SetFloatValue(a, "SNAcheron.FreshDownRT", now)
    ; Track whoever/whatever downed them — same shared key Baka's own ground window sets for its
    ; aggressor (SNBaka.GroundWindowAggressor). Lets the proximity/creature checks below do a plain
    ; GetDistance() against one known reference instead of scanning (Yamete Redux's approach).
    ; PREFER the already-tracked reference over a fresh lookup. Only fall back when nothing's tracked
    ; yet, the tracked actor died, or the tracked hit is stale (60s+ old — an ancient, unrelated scuffle
    ; shouldn't outrank a fresh combat target if one's actually available).
    Actor atk = StorageUtil.GetFormValue(a, "SNBaka.GroundWindowAggressor") as Actor
    Float lastHit = StorageUtil.GetFloatValue(a, "SNBaka.LastHitRT", 0.0)
    Bool trackedFresh = atk && !atk.IsDead() && (now - lastHit) < 60.0
    If !trackedFresh
        ; SNBakaUI.GetLastHitAggressor is the native TESHitEvent cache -- ground truth for a follower
        ; too, not just the player. Confirmed real bug from testing (see Downed_SkyrimNet.RunConsequence
        ; for the fuller story): GetCombatTarget() can read None for a follower at the exact moment
        ; Acheron's own defeat-interception fires, even though a creature visibly just hit them (native
        ; log confirms it). Try the cache first; only fall back to GetCombatTarget() if nothing's cached.
        Actor cached = SNBakaUI.GetLastHitAggressor(a)
        If cached && !cached.IsDead()
            atk = cached
            StorageUtil.SetFormValue(a, "SNBaka.GroundWindowAggressor", atk)
        Else
            Actor freshAtk = a.GetCombatTarget()
            If freshAtk
                atk = freshAtk
                StorageUtil.SetFormValue(a, "SNBaka.GroundWindowAggressor", atk)
            EndIf
        EndIf
    EndIf
    ; Vanilla Activate (E) refuses to prompt on any actor still flagged IsInCombat() —
    ; an actor downed BY combat is still flagged that way the instant they hit the ground,
    ; which silently blocks the Hunter's Pride perk fragment from ever firing. Must run
    ; after the GetCombatTarget() capture above (StopCombat clears it, so aggressor tracking
    ; would lose the reference if this ran first).
    If a.IsInCombat()
        _Trace(a + " is IsInCombat()=True at down-time, calling StopCombat()")
        a.StopCombat()
        _Trace(a + " after StopCombat(): IsInCombat()=" + a.IsInCombat())
    Else
        _Trace(a + " already IsInCombat()=False at down-time, no StopCombat needed")
    EndIf
    _ForceEssentialForDown(a, True)
    ; Give a nearby beast (Baka's creature-pounce logic — creatures have no LLM brain to pick actions
    ; themselves) the chance to act on this fresh down. Queued (not a hardcoded PlayerRef) so this works
    ; for NPC victims too, matching the SNBaka.AcheronDownQueue pattern Baka itself uses.
    If _player
        StorageUtil.FormListAdd(_player, "SNBaka.CreaturePounceQueue", a)
        SendModEvent("SNBaka_TryCreatureOnDowned")
    EndIf
    ; Name the concrete follow-up ACTIONS so the LLM actually picks one instead of just narrating. Kept
    ; to just the action names (no prose) — Escalate is deliberately NOT offered here: it only becomes an
    ; option once PinHelpless/ChokeHelpless resolves in the aggressor's favor (Baka's own follow-up cue).
    SkyrimNetApi.RegisterEvent("acheron_downed", _DownedMsg(a), atk, a)
EndFunction

; SkyrimNet decorator: exposes Acheron defeat state so the LLM knows the actor is helpless.
String Function GetAcheronState(Actor akActor) Global
    If !akActor
        Return "{}"
    EndIf
    String d = "false"
    If Acheron.IsDefeated(akActor)
        d = "true"
    EndIf
    Return "{\"defeated_and_helpless\":" + d + "}"
EndFunction

; ponytail: hardcoded on, no MCM toggle — the toggle was a source of confusion (two similarly-named
; Acheron MCM pages, easy to flip the wrong one) and every test session this far showed zero trace
; output despite being told it was enabled. Always-on removes that variable entirely.
Function _Trace(String s)
    ; Gated on the MCM "Enable Debug Logging" toggle (SNAcheron.DebugLog, read each _LoadSettings) —
    ; the synchronized log-file write is the expensive part on a starved VM; skip it when off.
    If _bDebugLog
        Debug.Trace("[SNAcheron] " + s)
    EndIf
EndFunction
