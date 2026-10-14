Scriptname Downed_SkyrimNet extends Quest
; ============================================================================================
; ACHERON CONSEQUENCE WORKER  (the "plugin" entry point)
; ============================================================================================
; Acheron STARTS this quest when OUR consequence is SELECTED for a defeat — see the YAMLs in
; SKSE/Acheron/Consequences/*/DownedSkyrimNet.yaml (Teleport:false). Being a real, registered Acheron
; consequence (chosen by Acheron's own priority/weight) is what makes us a proper plugin that COEXISTS
; with YameteKudasai and any other Acheron mod — instead of globally suppressing consequences.
;
; We do the light part here (mark the victim held + fire the first cue) and hand the ongoing hold /
; recovery / repeat cues to the persistent bridge (SkyrimNet_AcheronIntegration), which polls for held
; actors. Then we STOP so Acheron can select us again on the next defeat.
;
; CK WIRING: Quest = Start Game Disabled ON, Run Once OFF. Start-up stage fragment = one line:
;     (GetOwningQuest() as Downed_SkyrimNet).RunConsequence()

Function RunConsequence()
    ; This whole file had ZERO trace lines -- confirmed real diagnostic gap: AcheronNG's own log clearly
    ; shows it selecting and running our consequence, but nothing downstream (no creature hand-off, no
    ; cue, no hold) ever showed up anywhere, with no way to tell WHERE in here it was silently bailing.
    Debug.Trace("[SNAcheron:Downed] RunConsequence ENTER")
    ; The bridge's own master switch (OnUpdate/OnDownRequest both gate on this) — this entry point was
    ; the one path that DIDN'T check it: with the toggle off, a combat-defeated actor still got marked
    ; held and cued here, then was never managed again (OnUpdate's poll skips everyone while disabled),
    ; so they'd stay "down" forever with no reminder and no recovery. Bail out before taking ownership.
    If StorageUtil.GetIntValue(Game.GetPlayer(), "SNAcheron.Enabled", 1) != 1
        Debug.Trace("[SNAcheron:Downed] RunConsequence: blocked -- SNAcheron.Enabled is OFF")
        Stop()
        Return
    EndIf
    Actor v = _ResolveVictim()
    Debug.Trace("[SNAcheron:Downed] RunConsequence: _ResolveVictim returned " + v)
    ; Defensive: Acheron's own defeat-instead-of-death interception can race an ACTUAL death (confirmed
    ; in logs — a third-party death-tracker fired "Detected death" the same instant Acheron selected us).
    ; If the victim is genuinely dead by the time we get here, every call below (GetDisplayName, etc.)
    ; throws "Mismatched types" errors against a torn-down actor reference. Bail out clean instead.
    If !v || v.IsDead() || v.IsDisabled()
        Debug.Trace("[SNAcheron:Downed] RunConsequence: blocked -- victim none/dead/disabled (v=" + v + ")")
        Stop()
        Return
    EndIf
    ; Baka owns this actor mid-interaction (struggle or scene, SNBaka.Locked=1): a native Acheron
    ; defeat landing NOW is a stray hit intercepted mid-scene, not a fresh down for us to manage.
    ; Confirmed crash chain from testing: a second falmer re-aggroed the player during scene start,
    ; Acheron intercepted the hit as a new defeat, and this consequence piled a full down cycle
    ; (StopCombat/hold/cue) onto an OStim thread mid-spin-up. Revive them out of Acheron silently and
    ; step aside -- the scene's own abort/cleanup and post-scene re-down handle everything else.
    If StorageUtil.GetIntValue(v, "SNBaka.Locked", 0) == 1
        ; TWO different ways a defeat lands on a Baka-locked victim, told apart by SNAcheron.Held:
        ; Held==1  -> DELIBERATE PARK: Baka delegated this down itself (QTE-loss park -- the victim
        ;             rides Acheron's defeat through scene prep AND the scene, OSimpleDefeat-style).
        ;             The defeat must STAND; we just don't pile a consequence cycle on top of it.
        ; Held==0  -> stray native interception (second attacker's hit mid-scene-start) -- the old
        ;             confirmed crash chain; revive them out silently, the scene owns them.
        If StorageUtil.GetIntValue(v, "SNAcheron.Held", 0) == 1
            Debug.Trace("[SNAcheron:Downed] RunConsequence: victim " + v + " is Baka-locked AND Held -- deliberate park, stepping aside WITHOUT rescuing")
            Stop()
            Return
        EndIf
        Debug.Trace("[SNAcheron:Downed] RunConsequence: victim " + v + " is Baka-locked mid-interaction -- reviving out of Acheron silently, not taking this down")
        Acheron.RescueActor(v, true)
        Acheron.ReleaseActor(v)
        Stop()
        Return
    EndIf
    ; Safety net for the confirmed bug where the persistent bridge quest (SkyrimNet_AcheronIntegration)
    ; sometimes goes dark — either never starting at all, or starting fine and dying silently partway
    ; through a session (one successful recovery observed, then nothing). Without it alive, nobody held
    ; here ever gets a recovery check — they stay down forever. EnsureAlive() re-arms its poll loop
    ; unconditionally, which is a harmless no-op if it's already ticking.
    ;  Amendment 3 (Option C, user-ruled 2026-10-12): the manager is esp-attached at QUST
    ; 0x801 (second script, 0 props, DNAM 11 start-game-enabled) — clean-save instantiation intact
    ; since the  fold; 's "no esp host form" finding is WITHDRAWN (objectFormat-2
    ; decode error — the prior hand-decode misread property values as script names; enumeration
    ; receipts in PROJECT_STATE ). 0x800 is the author-designed Downed WORKER transient
    ; (Stop() on all six exits) — the old 0x800 cast here was a wrong-form cast, effectively a
    ; no-op; every prior "manager instance ABSENT" log line was true about the wrong form.
    ; Retargeted to 0x801 (the un-cast 0x800 PRESENCE probes elsewhere stay — presence and
    ; manager are different questions at different forms).
    ; (bridge declared at function scope, not inside the If: Papyrus block-scopes local
    ; variables, and the ForceEssential borrow below (the `If bridge` further down) needs it
    ; after this probe block closes —  compile-0/0 lesson.)
    SkyrimNet_AcheronIntegration bridge = None
    If Game.GetFormFromFile(0x000801, "SkyrimNet_AcheronIntegration.esp")
        bridge = Game.GetFormFromFile(0x000801, "SkyrimNet_AcheronIntegration.esp") as SkyrimNet_AcheronIntegration
        If bridge
            bridge.EnsureAlive()
        Else
            Debug.Trace("[SNAcheron:Downed] RunConsequence: manager host 0x801 loaded but manager instance ABSENT (unexpected outside mid-load races) — EnsureAlive() nudge skipped (no-op sentinel)")
        EndIf
    EndIf
    Float now = Utility.GetCurrentRealTime()
    ; Both clocks need seeding here (LastProxRT too, not just LastCheckRT) or the bridge's very first
    ; proximity check fires on its next poll tick instead of waiting fProximityCheckSeconds.
    StorageUtil.SetIntValue(v,   "SNAcheron.Held",         1)
    StorageUtil.SetFloatValue(v, "SNAcheron.LastCheckRT",  now)
    StorageUtil.SetFloatValue(v, "SNAcheron.LastProxRT",   now)
    ; Hard auto-get-up ceiling for this fresh down -- see fAutoGetUpSeconds and _TickActor on the bridge.
    StorageUtil.SetFloatValue(v, "SNBaka.AutoGetUpDeadlineRT", now + StorageUtil.GetFloatValue(Game.GetPlayer(), "SNAcheron.AutoGetUpSeconds", 600.0))
    ; Marks the moment of a genuinely FRESH down (same shared key the bridge's own _CueDowned sets) --
    ; see fFreshDownGraceDuration on the bridge script. Nobody engages this victim in a struggle for a
    ; few seconds after this, giving the down-transition animation time to actually settle.
    StorageUtil.SetFloatValue(v, "SNAcheron.FreshDownRT", now)
    ; Track whoever/whatever downed them — same key Baka's own ground window uses for its aggressor
    ; (SNBaka.GroundWindowAggressor). Reused here (not a new key) so _NearbyThreat/
    ; _TryCreatureEscalateOnDowned can do a plain GetDistance() against one known reference instead of
    ; scanning — same technique Yamete Redux uses via its alias roster.
    ; PREFER the already-tracked reference (for the player, SNAcheron_PlayerAlias's OnHit hook — an
    ; actual confirmed hit) over a fresh lookup. Only fall back when nothing's tracked yet, the tracked
    ; actor died, or the tracked hit is stale (60s+ old).
    Actor atk = StorageUtil.GetFormValue(v, "SNBaka.GroundWindowAggressor") as Actor
    Float lastHit = StorageUtil.GetFloatValue(v, "SNBaka.LastHitRT", 0.0)
    Bool trackedFresh = atk && !atk.IsDead() && (now - lastHit) < 60.0
    If !trackedFresh
        ; SNBakaUI.GetLastHitAggressor is the native TESHitEvent cache -- ground truth for a follower
        ; too, not just the player (HitEventSink caches any player-teammate). Confirmed real bug from
        ; testing: a Draugr visibly hit Joylie (native log shows it) the same instant Acheron defeated
        ; her, but v.GetCombatTarget() still came back None here -- Acheron's own defeat-interception
        ; appears to clear combat state before this fragment runs, so the OLD "GetCombatTarget is
        ; reliable enough for a follower" assumption doesn't hold at THIS exact moment. With no aggressor
        ; tracked, _NearbyThreat had nothing to anchor on and lost the creature within one proximity
        ; check -- the escalation opportunity was gone before the 3s fresh-down grace even expired. Try
        ; the native cache first; only fall back to GetCombatTarget() if nothing was ever cached.
        Actor cached = SNBakaUI.GetLastHitAggressor(v)
        If cached && !cached.IsDead()
            atk = cached
            StorageUtil.SetFormValue(v, "SNBaka.GroundWindowAggressor", atk)
        Else
            Actor freshAtk = v.GetCombatTarget()
            If freshAtk
                atk = freshAtk
                StorageUtil.SetFormValue(v, "SNBaka.GroundWindowAggressor", atk)
            EndIf
        EndIf
    EndIf
    ; Borrowed from the Surrender mod's own proven technique: force Essential for the duration of the
    ; hold so a stray follow-up hit while helpless doesn't actually kill them. Reuses the bridge's own
    ; copy of this (same shared SNBaka.EssentialForcedByUs key its _Recover already knows how to clear).
    ; : with the 0x801 retarget this borrow is LIVE for the first time (the old 0x800
    ; wrong-form cast made it a silent no-op on every path).  sentinel ( observability
    ; rider): unexpected victim behavior = REPORT, don't tune.
    If bridge
        bridge._ForceEssentialForDown(v, True)
        Debug.Trace("[SNAcheron:Downed] §5 sentinel: essential-for-down armed on " + v)
    EndIf
    Debug.Trace("[SNAcheron:Downed] RunConsequence: taking " + v + ", tracked aggressor=" + atk)
    ; Give a nearby beast (Baka's creature-pounce logic) the chance to act on this fresh combat-defeat
    ; down too — not just the Baka-QTE-delegated path handled by the bridge's own _CueDowned.
    Actor pl = Game.GetPlayer()
    If pl
        StorageUtil.FormListAdd(pl, "SNBaka.CreaturePounceQueue", v)
        SendModEvent("SNBaka_TryCreatureOnDowned")
        Debug.Trace("[SNAcheron:Downed] RunConsequence: queued " + v + " and sent SNBaka_TryCreatureOnDowned")
    EndIf
    ; Fire the first "X is downed" cue immediately, naming the concrete follow-up ACTIONS. Reuses the
    ; SAME Global helper as SkyrimNet_AcheronIntegration._CueDowned (the Baka-delegated entry point) so
    ; the two entry points can never drift apart in wording.
    SkyrimNetApi.RegisterEvent("acheron_downed", SkyrimNet_AcheronIntegration._DownedMsg(v), atk, v)
    Debug.Trace("[SNAcheron:Downed] RunConsequence: done, stopping")
    ; A start-disabled consequence quest must END STOPPED so Acheron can select us again next time.
    Stop()
EndFunction

; Acheron doesn't pass the victim to the fragment, so resolve it. Ground truth first: SkyrimNet_
; AcheronIntegration.OnActorDefeated stashes the EXACT victim for every defeat, timestamped -- if it's
; fresh and not already held, trust it completely instead of guessing. This is the actual fix for the
; confirmed "Joylie never selected" bug: the old guess ("is the player currently defeated-and-unheld?
; assume it's them") grabbed the wrong actor whenever both were ambiguously eligible at the same moment,
; silently dropping the OTHER actor's real defeat event every time that collision happened.
Actor Function _ResolveVictim()
    Actor p = Game.GetPlayer()
    If p
        Actor stashed = StorageUtil.GetFormValue(p, "SNAcheron.LastDefeatedActor") as Actor
        Float age = Utility.GetCurrentRealTime() - StorageUtil.GetFloatValue(p, "SNAcheron.LastDefeatedRT", 0.0)
        Debug.Trace("[SNAcheron:Downed] _ResolveVictim: stashed=" + stashed + " age=" + age)
        If stashed && !stashed.IsDead() && !stashed.IsDisabled() && age < 3.0 && StorageUtil.GetIntValue(stashed, "SNAcheron.Held", 0) == 0
            Return stashed
        EndIf
    EndIf
    ; Fallback heuristic below, only reached if the stash is missing/stale (e.g. OnActorDefeated somehow
    ; didn't fire in time) -- same as before, but no longer the ONLY path.
    ; NOTE: the NPC branch below already checks !a.IsDead() — this one didn't, which is the actual gap
    ; that let a genuinely-dead player through when Acheron's defeat flag raced an actual death.
    If p
        Debug.Trace("[SNAcheron:Downed] _ResolveVictim: player dead=" + p.IsDead() + " Acheron.IsDefeated=" + Acheron.IsDefeated(p) + " SNAcheron.Held=" + StorageUtil.GetIntValue(p, "SNAcheron.Held", 0))
    EndIf
    If p && !p.IsDead() && Acheron.IsDefeated(p) && StorageUtil.GetIntValue(p, "SNAcheron.Held", 0) == 0
        Return p
    EndIf
    Actor[] d = Acheron.GetDefeated(true)
    Debug.Trace("[SNAcheron:Downed] _ResolveVictim: player not eligible, scanning Acheron.GetDefeated() -- count=" + d.Length)
    Actor best     = None
    Float bestDist = 999999.0
    Int i = 0
    While i < d.Length
        Actor a = d[i]
        If a
            Debug.Trace("[SNAcheron:Downed] _ResolveVictim: candidate " + a.GetDisplayName() + " dead=" + a.IsDead() + " SNAcheron.Held=" + StorageUtil.GetIntValue(a, "SNAcheron.Held", 0))
        EndIf
        If a && a != p && !a.IsDead() && StorageUtil.GetIntValue(a, "SNAcheron.Held", 0) == 0
            Float dist = 0.0
            If p
                dist = p.GetDistance(a)
            EndIf
            If dist < bestDist
                bestDist = dist
                best = a
            EndIf
        EndIf
        i += 1
    EndWhile
    Return best
EndFunction
