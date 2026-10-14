Scriptname SNAcheron_PlayerAlias extends ReferenceAlias
{ Attach to a PLAYER alias on the persistent controller quest.
  Re-registers the SkyrimNet decorator on load (runtime-only; does not persist). The bridge quest also
  self-heals its own registrations via a game-time heartbeat, so this is belt-and-suspenders. }

Event OnInit()
    _Register()
EndEvent

Event OnPlayerLoadGame()
    _Register()
EndEvent

Function _Register()
    SkyrimNetApi.RegisterDecorator("acheron_state", "SkyrimNet_AcheronIntegration", "GetAcheronState")
    SkyrimNet_AcheronIntegration bridge = GetOwningQuest() as SkyrimNet_AcheronIntegration
    If bridge
        bridge._Register()
    EndIf
EndFunction

; Yamete Redux's actual technique for "who is threatening this actor" — native combat resolution hands
; us the attacker directly on every hit (same idea as Yamete's "Lurking Threat" OnEffectStart hook), not
; a GetCombatTarget() snapshot taken later (which can already be None by the time a defeat consequence
; runs, since combat is often deliberately stopped before that point) or a cell scan (same-cell only,
; a confirmed source of false negatives all session). This works for a creature attacker exactly the
; same as a humanoid one — whatever hit the player last is what gets tracked, continuously updated
; through the fight, so by the time they actually go down the reference is already correct.
; Hostility-gated: an ally's stray AOE or an incidental non-hostile bump would otherwise overwrite a
; genuine threat with a harmless bystander, which could wrongly block recovery or wrongly deny a
; creature its escalation chance by making downstream checks think a friendly is "the danger" still
; standing there. abHitBlocked hits still count (a blocked swing is still an active threat engaging).
; Kick the bridge's poll the moment the player enters combat — the poll is fully dormant when idle
; (zero self-driven ticks), and the combat-scoped vanilla-bleedout net needs it running DURING the
; fight, not up to a keepalive-interval later (a vanilla bleedout self-recovers within seconds, so a
; late first scan misses it — the confirmed "downed NPC resurrected instantly" case).
Event OnCombatStateChanged(Actor akTarget, Int aeCombatState)
    If aeCombatState == 1
        SkyrimNet_AcheronIntegration bridge = GetOwningQuest() as SkyrimNet_AcheronIntegration
        If bridge
            bridge.EnsureAlive()
        EndIf
    EndIf
EndEvent

Event OnHit(ObjectReference akAggressor, Form akSource, Projectile akProjectile, Bool abPowerAttack, Bool abSneakAttack, Bool abBashAttack, Bool abHitBlocked)
    Actor victim    = GetReference() as Actor
    Actor aggressor = akAggressor as Actor
    If victim && aggressor && aggressor != victim && !aggressor.IsDead() && aggressor.IsHostileToActor(victim)
        StorageUtil.SetFormValue(victim, "SNBaka.GroundWindowAggressor", aggressor)
        StorageUtil.SetFloatValue(victim, "SNBaka.LastHitRT", Utility.GetCurrentRealTime())
    EndIf
EndEvent
