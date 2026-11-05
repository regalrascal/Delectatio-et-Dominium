; REV-24 Task 2 (user ruling: OPTION A, ReferenceAlias load reset — replaces the rev-21 4a
; stamp heuristic): a tiny load-reset alias. Attached (via the modified SkyrimNet_AnimationsGS.esp,
; quest SNAnimGS_LoadAlias, player ReferenceAlias — the exact skynet_PlayerAlias production pattern
; from SkyrimNet.esp quest 0x802) so it receives OnPlayerLoadGame, which Quest scripts do NOT
; (proven twice: GS OnUpdate heuristic + Baka's own dead OnPlayerLoadGame at BakaIntegration.psc:379).
; The muse toggle is SESSION-SCOPED by standing ruling; this makes the flag agree with the stateless
; grid button at EVERY load by construction — no clock inference, no staleness window.
; Doubles as the rev-24 2a probe: the unconditional boot sentinel below proves the alias fires.
Scriptname SkyrimNet_AnimGS_LoadAlias extends ReferenceAlias

Event OnPlayerLoadGame()
    ; Unconditional probe sentinel (ruleset §5) — fires on EVERY load, so the next session's
    ; log read settles "does the alias fire reliably across save-load and cold boot" with one grep.
    Debug.Trace("[SNAnimGS] load alias: OnPlayerLoadGame fired (probe, rev-24 2a)")
    If StorageUtil.GetIntValue(None, "GSAnim.Muse", 0) == 1
        StorageUtil.SetIntValue(None, "GSAnim.Muse", 0)
        Debug.Trace("[SNAnimGS] muse session scope: reset to OFF on load (alias) — toggle is session-scoped (rev-24 Option A ruling)")
    EndIf
EndEvent
