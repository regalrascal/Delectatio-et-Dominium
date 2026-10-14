Scriptname SkyrimNet_AcheronIntegration_MCM extends SKI_ConfigBase
; AMENDMENT 3 STUB (, user-ruled 2026-10-12) - acheron-fold.md, Amendment 3 (Option C).
; WHAT: this was the "Downed SkyrimNet (Acheron)" MCM menu. It is now a deliberate no-op
; stub: no OnConfigInit (no ModName, no pages), no OnPageReset, no SKI_* registration calls.
; The old OnConfigInit bridge nudge is DROPPED ENTIRELY, not retargeted (: redundant -
; Downed_SkyrimNet.RunConsequence re-arms the manager per defeat and
; SkyrimNet_BakaIntegration._ArmModules nudges per load; both now target the real manager
; host QUST 0x801).
; WHY: the menu duplicated SNBaka_MCM's "Downed State (Acheron bridge)" section (the 
; consolidation); quest 0x801 (legacy editor-ID SNAcheron_MCM - naming-debt annotation of
; record) is the bridge MANAGER's persistent host and must keep a resolvable script on its
; VMAD, so the class stays `extends SKI_ConfigBase` and the esp binding + save lineage
; resolve unchanged. The menu dies at the next MCM load-wave; ghost entries self-resolve
; ( precedent) - lingering "Downed SkyrimNet (Acheron)" entries are EXPECTED and
; vanish on their own.
; NO ESP BYTES: the esp ships byte-identical per the Option-C ruling; a VMAD property
; binding with no matching psc property is skipped silently by the engine.
