Scriptname SNBaka_SlaveTatsModule
;  SlaveTats module (recordless observer/detection class ? module contract point 3,
; fomod.md ?architecture). NO SexLab/OStim/etc types here; the only foreign API surface is
; SlaveTats itself (compile-stubbed in tools\compile\local; runtime resolved from whichever
; SlaveTats install wins MO2 priority ? currently SlaveTatsNG 0.8.2, a strict superset of
; legacy SE per the  research, so this module's calls are safe under either).

; ------------------------------------------------------------------
; STATE (StorageUtil, "SNBaka.ST." prefix; player-keyed)
; ------------------------------------------------------------------
;   SNBaka.ST.Enabled        Int   1 = module active (default 1)
;   SNBaka.ST.ApplyOnSpank   Int   apply chosen set when spank heat rises (default 1)
;   SNBaka.ST.ApplyOnDefeat  Int   apply chosen set on defeat/downed (default 1)
;   SNBaka.ST.ApplyOnEscalation Int apply chosen set at escalation handoff (default 0)
;   SNBaka.ST.SpankSetSection / .SpankSetName   String  user-chosen degradation set (spank)
;   SNBaka.ST.DefeatSetSection / .DefeatSetName String  (defeat)
;   SNBaka.ST.EscalationSetSection / .EscalationSetName String (escalation)
;   SNBaka.ST.RefreshCount  Int   times RefreshPacks was invoked (diagnostic counter)
;   SNBaka.ST.SectionCount  Int   sections found in the last discovery pass (diagnostic)
;   SNBaka.ST.DiscoveredAt  Float game-time stamp of the last discovery pass
;   SNBaka.ST.Applied       StringList (actor-keyed) applied entries this module owns
;    v3 entry format: "section|name|color|mode|area|timestamp"
;     (timestamp = real-time seconds, Utility.GetCurrentRealTime(); mode = the
;     application origin - spank/defeat/escalation/picker/llm_action/downedmenu/
;     event/forced; area = the SlaveTats area the mark lives on, resolved from
;     the cache at apply time - Body/Face/Hands/Feet).  "section|name" and
;      "section|name|color" entries remain readable: fields parse
;     positionally, absent fields default (mode=event, area="", timestamp=0 ->
;     freshness band "unknown"); _DropAppliedEntry is field-count agnostic
;     (prefix match), so old and new entries remove identically.
;   SNBaka.ST.Observe       Int   : master gate of the AMBIENT
;     EXPOSURE PASS (folded from the retired v1 ObservationPass; default 1)
;   SNBaka.ST.AmbientPct    Int   fire chance per daemon tick, percent
;     (default 35; MCM slider "Ambient Exposure Chance")
;   SNBaka.ST.AmbientFloor  Float per-actor exposure cooldown, real-time
;     seconds (default 600.0; surfaced at the gate report)
;   SNBaka.ST.AmbientLast   Float (actor-keyed) last ambient exposure
;     fire stamp, real-time seconds (the muse-floor pattern)
;   SNBaka.ST.AmbientNarr   Int   optional direct-narration second surface
;     for the ambient cue (default 0 = OFF; MCM "Tattoo Ambient Narration")
; ------------------------------------------------------------------

Bool Function Installed() Global
    ; Framework presence = the SlaveTats quest record loads from the esp (legacy SE esp, or
    ; the NG overwrite ? NG's runtime SlaveTats.pex shadows SE's by MO2 priority, but both
    ; installs carry SlaveTats.esp; the record resolves either way).
    ;  F-3 (S181 finding): cached ABSENCE -- the uncached probe logged a hard
    ; Papyrus error on every caller (arm pass + the new 30s ambient cadence) when the
    ; esp is absent. esp load state cannot change within a session; the flag is set
    ; once on first failed probe and short-circuits every later call.
    If StorageUtil.GetIntValue(None, "SNBaka.ST.ProbeAbsent", 0) == 1
        Return False
    EndIf
    Bool bPresent = Game.GetFormFromFile(0x800, "SlaveTats.esp") != None
    If !bPresent
        StorageUtil.SetIntValue(None, "SNBaka.ST.ProbeAbsent", 1)
        Debug.Trace("[SNBaka.ST] Installed: SlaveTats.esp absent (cached absent from now on) -- REV-159 F-3")
    EndIf
    Return bPresent
EndFunction

; SlaveTatsNG detection ( research 1d): NG's runtime SlaveTats.VERSION() returns
; SlaveTatsNG.VERSION() (e.g. "0.8.2"); legacy SE returns "1.0.0" (data-structure version).
; Rather than parsing version strings, probe the NG SKSE plugin directly (zero => absent).
Bool Function NGDetected() Global
    Return SKSE.GetPluginVersion("SlaveTatsNG") > 0
EndFunction

; ------------------------------------------------------------------
; DISCOVERY ( research 1a/1c)
; ------------------------------------------------------------------
; SlaveTats discovers packs purely from the filesystem: compile_cache() JContainers-scans
; Data\Textures\Actors\Character\slavetats\*.json into the JDB cache at .SlaveTats.cache.
; Under MO2, a DISABLED pack is entirely absent from the virtual Data tree ? so the
; discovered list reflects MO2-ENABLED packs only. Enabling a pack in MO2 (with MO2 closed
; or before launch) + Refresh in the MCM picks it up WITHOUT a game restart.
; ------------------------------------------------------------------

; Rebuild the SlaveTats cache from disk. Picks up newly MO2-enabled packs mid-session.
; compile_cache() pools everything it allocates and stores the result in the JDB global;
; release_cache() drops the old in-memory copy first so no stale entries linger.
Function RefreshPacks() Global
    If !Installed()
        Return
    EndIf
    SlaveTats.release_cache()
    Int cache = SlaveTats.compile_cache()
    Actor p = Game.GetPlayer()
    StorageUtil.SetIntValue(p, "SNBaka.ST.RefreshCount", StorageUtil.GetIntValue(p, "SNBaka.ST.RefreshCount", 0) + 1)
    If cache != 0
        Int sectionCount = _EnumerateSections(cache)
        StorageUtil.SetIntValue(p, "SNBaka.ST.SectionCount", sectionCount)
        StorageUtil.SetFloatValue(p, "SNBaka.ST.DiscoveredAt", Utility.GetCurrentGameTime())
        Debug.Trace("[SNBaka.ST] RefreshPacks: rebuilt cache ? " + sectionCount + " sections discovered")
    Else
        Debug.Trace("[SNBaka.ST] RefreshPacks: compile_cache() returned 0 ? no packs visible (are any enabled in MO2?)")
    EndIf
EndFunction

; Walk cache -> domain "default" -> areas -> sections; return the number of sections.
; Read-only on the framework-owned cache; retains nothing.
Int Function _EnumerateSections(Int cache) Global
    If cache == 0
        Return 0
    EndIf
    Int dom = JMap.getObj(cache, "default")
    If dom == 0
        Return 0
    EndIf
    String[] areas = JMap.allKeysPArray(dom)
    Int n = 0
    Int i = 0
    While i < areas.Length
        Int area = JMap.getObj(dom, areas[i])
        If area != 0
            n += JMap.count(area)
        EndIf
        i += 1
    EndWhile
    Return n
EndFunction

; ------------------------------------------------------------------
; APPLY / REMOVE (Baka's exact call convention: cf. ApplySpankMark L9143)
; ------------------------------------------------------------------

; ------------------------------------------------------------------
; .1 (2026-10-24) ? MALE-CURATION SCREEN (user ruling of record,
; slavetats.md .1). SlaveTats application is gender-agnostic; the
;  3.4 [malebody] refuse-all model flips to a WHITELIST:
;   (1) all "Gay - *" and "Femboy" sections auto-whitelist (the
;       Slavetats-GayMisc pack class ? male-authored by construction);
;   (2) every other pack passes a female-anatomy keyword denylist
;       screened on section+name (wording-only screen; the UV-alignment
;       risk for female-UV packs that pass ? SSS especially ? is
;       ACCEPTED, dogfood-and-drop per section, no re-ruling needed).
; The screen is pack-agnostic (new installs need no code change); the
; denylist is additive at the user's pen. EVERY module avenue funnels
; through ApplyTattoo, so gating THERE covers spank/defeat/escalation
; sets, the picker, LLM actions, and the forced-tattoo service alike.
; ------------------------------------------------------------------

; ASCII lowercase (Papyrus has no ToLower; SKSE StringUtil AsOrd/AsChar loop).
String Function _ToLower(String asText) Global
    Int n = StringUtil.GetLength(asText)
    String result = ""
    Int i = 0
    While i < n
        Int c = StringUtil.AsOrd(StringUtil.GetNthChar(asText, i))
        If c >= 65 && c <= 90    ; A-Z
            c += 32
        EndIf
        result += StringUtil.AsChar(c)
        i += 1
    EndWhile
    Return result
EndFunction

; The female-anatomy keyword denylist (.1 ruling wording: pussy/
; vagina/cunt/clit/labia/breast/boob/tit/titty/nipple/womb/cervix/milf).
; True = hit = refuse the male apply. Additive at the user's pen: new
; words = one more ElseIf on the lowered text (ruling: wording-only).
Bool Function _HitsFemaleAnatomyKeywords(String asSection, String asName) Global
    String t = _ToLower(asSection + " " + asName)
    If StringUtil.Find(t, "pussy") >= 0
        Return True
    ElseIf StringUtil.Find(t, "vagina") >= 0
        Return True
    ElseIf StringUtil.Find(t, "cunt") >= 0
        Return True
    ElseIf StringUtil.Find(t, "clit") >= 0
        Return True
    ElseIf StringUtil.Find(t, "labia") >= 0
        Return True
    ElseIf StringUtil.Find(t, "breast") >= 0
        Return True
    ElseIf StringUtil.Find(t, "boob") >= 0
        Return True
    ElseIf StringUtil.Find(t, "nipple") >= 0
        Return True
    ElseIf StringUtil.Find(t, "womb") >= 0
        Return True
    ElseIf StringUtil.Find(t, "cervix") >= 0
        Return True
    ElseIf StringUtil.Find(t, "milf") >= 0
        Return True
    ElseIf StringUtil.Find(t, "titty") >= 0
        Return True
    EndIf
    ; "tit" hits EXCEPT the "tither"-class false positive.
    Int idx = StringUtil.Find(t, "tit")
    If idx >= 0 && StringUtil.Substring(t, idx + 3, 3) != "her"
        Return True
    EndIf
    Return False
EndFunction

; The whitelist verdict for one section/name pair: (1) the GayMisc class
; auto-whitelists; (2) everything else rides the keyword screen.
Bool Function MaleMayWear(String asSection, String asName) Global
    String sec = _ToLower(asSection)
    If StringUtil.Find(sec, "gay - ") == 0 || sec == "femboy"
        Return True
    EndIf
    Return !_HitsFemaleAnatomyKeywords(asSection, asName)
EndFunction

; Female-body class test for the module gate. Mirrors the motherboard's
; HasFemaleBody exactly (LeveledActorBase sex, editor-base fallback,
; sex 1 = female) so the two layers never disagree on the same actor.
Bool Function _IsFemaleClass(Actor akTarget) Global
    If !akTarget
        Return False
    EndIf
    ActorBase bse = akTarget.GetLeveledActorBase()
    If !bse
        bse = akTarget.GetActorBase()
    EndIf
    If !bse
        Return False
    EndIf
    Return bse.GetSex() == 1
EndFunction

; Apply one tattoo entry. Returns true if SlaveTats accepted the call.
; : aiColor < 0 = "not chosen" -> the module-wide default color (SNBaka.ST.DefaultColor,
; itself 0 = pack default / no recolor); aiColor 0 = pack default (explicit). The color is a
; 0xRRGGBB int; hex strings from the picker are parsed by _HexToInt.
Bool Function ApplyTattoo(Actor akTarget, String asSection, String asName, Int aiColor = -1, Bool abSilent = True, String asMode = "event") Global
    If !akTarget || !Installed()
        Return False
    EndIf
    ; .1 male-curation gate ? THE choke point for every module avenue
    ; (spank/defeat/escalation sets, picker, LLM actions, forced service).
    ; Female-class targets pass ungated; male-class targets must pass the
    ; whitelist screen (Gay - */Femboy auto-whitelist, else keyword denylist
    ; on section+name). Refusals are reason-coded, no cue fired.
    If !_IsFemaleClass(akTarget) && !MaleMayWear(asSection, asName)
        Debug.Trace("[SNBaka.ST] ApplyTattoo: REFUSED [male-not-curated] - '" + asName + "' (" + asSection + ") fails the REV-150.1 male whitelist on " + akTarget.GetDisplayName())
        Return False
    EndIf
    If aiColor < 0
        aiColor = StorageUtil.GetIntValue(Game.GetPlayer(), "SNBaka.ST.DefaultColor", 0)
    EndIf
    Bool ok = SlaveTats.simple_add_tattoo(akTarget, asSection, asName, aiColor, True, abSilent, 1.0)
    If ok
        ;  4.2: the v3 entry carries mode + area (cache-resolved) + the
        ; real-time apply stamp (the cum 0175 freshness-band precedent).
        StorageUtil.StringListAdd(akTarget, "SNBaka.ST.Applied", \
            asSection + "|" + asName + "|" + aiColor + "|" + asMode + "|" + _ResolveAreaFor(asSection, asName) + "|" + Utility.GetCurrentRealTime(), True)
        Debug.Trace("[SNBaka.ST] ApplyTattoo: applied '" + asName + "' (" + asSection + ") color=0x" + _IntToHex(aiColor) + " mode=" + asMode + " to " + akTarget.GetDisplayName())
        _FireEvent(True, akTarget, asSection, asName, aiColor, asMode)
    Else
        ; Failure logging (rider Task 2): SlaveTats rejected the call ? the cache walk says
        ; the section/name pair exists, so a False here means the overlay add itself failed
        ; (missing texture files in the pack json is the usual cause). Surface it, don't swallow.
        Debug.Trace("[SNBaka.ST] ApplyTattoo: FAILED ? SlaveTats rejected '" + asName + "' (" + asSection + ") on " + akTarget.GetDisplayName() + " (pack json missing entries?)")
    EndIf
    Return ok
EndFunction

; Remove one tattoo entry. : fires sdb_tattoo_removed on success (rider 2: EVERY removal
; path fires, picker/ambient/LLM action alike).
Bool Function RemoveTattoo(Actor akTarget, String asSection, String asName, Bool abSilent = True, String asMode = "event") Global
    If !akTarget || !Installed()
        Return False
    EndIf
    Bool ok = SlaveTats.simple_remove_tattoo(akTarget, asSection, asName, True, abSilent)
    If ok
        _DropAppliedEntry(akTarget, asSection, asName)
        Debug.Trace("[SNBaka.ST] RemoveTattoo: removed '" + asName + "' (" + asSection + ") from " + akTarget.GetDisplayName() + " mode=" + asMode)
        _FireEvent(False, akTarget, asSection, asName, 0, asMode)
    Else
        Debug.Trace("[SNBaka.ST] RemoveTattoo: FAILED ? SlaveTats rejected '" + asName + "' (" + asSection + ") on " + akTarget.GetDisplayName())
    EndIf
    Return ok
EndFunction

; : applied-list entry now carries the color: "section|name|color" (old "section|name"
; entries from  saves remain readable ? the color field simply parses as absent/0).
String Function sectionColorEntry(String asSection, String asName, Int aiColor) Global
    Return asSection + "|" + asName + "|" + aiColor
EndFunction

; : drop one section|name pair from the applied bookkeeping (color-insensitive).
Function _DropAppliedEntry(Actor akTarget, String asSection, String asName) Global
    Int cnt = StorageUtil.StringListCount(akTarget, "SNBaka.ST.Applied")
    Int i = cnt
    While i > 0
        i -= 1
        String entry = StorageUtil.StringListGet(akTarget, "SNBaka.ST.Applied", i)
        If entry == asSection + "|" + asName || StringUtil.Find(entry, asSection + "|" + asName + "|") == 0
            StorageUtil.StringListRemoveAt(akTarget, "SNBaka.ST.Applied", i)
            Return
        EndIf
    EndWhile
EndFunction

;  (rider 2): application-event triggers ? fired from EVERY application path with the
; full payload the rider specifies (actor, section, name, location data, color, mode).
; Sentinel per fire is the  full-payload pattern: the event text itself carries the
; payload so the YAML cue can react to the SPECIFIC mark ({{ target }} etc. do the rest).
;  (?7 approved, ruling 3c): base text is OBSERVABLE-ONLY ("a fresh mark on their
; skin" ? the ?7 payload-reachability finding: response.content templates only player_name /
; event_json / time_desc / location / gameTimeStr and our 4-arg RegisterEvent fires no
; extraData, so section/name is NOT templateable in the YAML layer; the specific mark rides
; in THIS event text and the YAML points the LLM at it). The applied event appends an
; arousal-tier clause read on the MARKED ACTOR's own arousal (self-keyed ruling of record);
; neutral = SILENCE (base text alone, no invented state). The removed event ships base text
; only ? the approved clause wording is application-reaction text; removal tiers are a v2
; item unless re-ruled.
Function _FireEvent(Bool abApplied, Actor akTarget, String asSection, String asName, Int aiColor, String asMode) Global
    If !akTarget
        Return
    EndIf
    String mark = asSection + " / " + asName
    String evName = "sdb_tattoo_removed"
    String evText = "The mark on " + akTarget.GetDisplayName() + "'s skin (" + mark + ") has been wiped away."
    If abApplied
        evName = "sdb_tattoo_applied"
        evText = akTarget.GetDisplayName() + " now wears a fresh mark on their skin (" + mark + "), freshly applied. Anyone who sees it reacts to the specific mark." + _ArousalClause(akTarget)
    EndIf
    SkyrimNetApi.RegisterEvent(evName, evText, akTarget, akTarget)
    ; Mode + color ride in the log for dogfood; the LLM cue stays source-agnostic (?7).
    Debug.Trace("[SNBaka.ST] _FireEvent: " + evName + " mode=" + asMode + " color=0x" + _IntToHex(aiColor))
EndFunction

;  (?7, Draft C approved): arousal tier for the applied-event clause, read on the
; MARKED ACTOR's own arousal (self-keyed interpretation of record ? cumflation's matrix
; already conforms). Primary: OSL Aroused Reborn pure read via its SKSE plugin
; (GetArousal has time-update side effects ? NEVER at fire time; the plugin-version gate
; keeps us off the native binding when the DLL is absent). Fallback: SLO Aroused NG via
; the "sla_Framework" quest (both NG and Reborn ship that quest/script pair; Reborn is
; caught by the primary, NG only by this). Neither readable -> "" (neutral = SILENCE,
; no invented state). Thresholds per the D&D Features Planner: >=75 / 25?75 / <=25.
; Clause wording standard OF RECORD (ratified ?7, ): OBSERVABLE BEHAVIOR ONLY ?
; describe what shows, never assert an internal state. This standard generalizes to
; every planner matrix implementation.
String Function _ArousalClause(Actor akTarget) Global
    Float arousal = -1.0
    If SKSE.GetPluginVersion("OSLAroused") > 0
        arousal = OSLArousedNative.GetArousalNoSideEffects(akTarget)
    Else
        slaFrameworkScr sla = Quest.GetQuest("sla_Framework") as slaFrameworkScr
        If sla
            arousal = sla.GetActorArousal(akTarget) as Float
        EndIf
    EndIf
    If arousal < 0.0
        Return ""
    EndIf
    If arousal >= 75.0
        Return " Their own reaction betrays them: skin flushing, breath quickening, a heat in their eyes that the fresh ink has stoked rather than shamed."
    ElseIf arousal > 25.0
        Return " Their own reaction is unsettled: a held breath, a glance down at the fresh ink, fascination and scandal warring plainly on their face."
    Else
        Return " Their own reaction is raw: a strangled sound, hands pressing over the mark, horror and disgust plain for anyone to see."
    EndIf
EndFunction

; : 0xRRGGBB int <-> "rrggbb" hex string for the picker payload.
Int Function _HexToInt(String asHex) Global
    Int v = 0
    Int i = 0
    While i < StringUtil.GetLength(asHex) && i < 6
        String c = StringUtil.GetNthChar(asHex, i)
        Int d = StringUtil.Find("0123456789abcdef", c)
        If d < 0
            d = StringUtil.Find("0123456789ABCDEF", c)
        EndIf
        If d < 0
            d = 0
        EndIf
        v = v * 16 + d
        i += 1
    EndWhile
    Return v
EndFunction

String Function _IntToHex(Int aiColor) Global
    String hex = ""
    Int v = aiColor
    If v < 0
        v = 0
    EndIf
    Int divisor = 1048576    ; 16^5
    While divisor > 0
        Int d = (v / divisor) % 16
        hex += StringUtil.GetNthChar("0123456789abcdef", d)
        divisor = divisor / 16
    EndWhile
    Return hex
EndFunction

; Remove every entry the module applied to this actor (own bookkeeping list; never touches
; the framework's "SkyrimNet Spank" section entries applied by Baka's spank system).
; : entries are "section|name|color" (legacy  entries "section|name"); each
; removal fires sdb_tattoo_removed via RemoveTattoo. asMode labels the calling surface.
Function RemoveAllFromActor(Actor akTarget, String asMode = "bulk") Global
    If !akTarget
        Return
    EndIf
    Int cnt = StorageUtil.StringListCount(akTarget, "SNBaka.ST.Applied")
    Int i = cnt
    While i > 0
        i -= 1
        String entry = StorageUtil.StringListGet(akTarget, "SNBaka.ST.Applied", i)
        String sec = ""
        String nm = ""
        Int sep = StringUtil.Find(entry, "|")
        If sep > 0
            sec = StringUtil.Substring(entry, 0, sep)
            String rest = StringUtil.Substring(entry, sep + 1)
            Int sep2 = StringUtil.Find(rest, "|")
            If sep2 >= 0
                nm = StringUtil.Substring(rest, 0, sep2)    ; strip the trailing color field
            Else
                nm = rest                                    ; legacy  entry
            EndIf
        EndIf
        If sec != "" && nm != ""
            RemoveTattoo(akTarget, sec, nm, True, asMode)
        EndIf
    EndWhile
    StorageUtil.StringListClear(akTarget, "SNBaka.ST.Applied")
EndFunction

; ------------------------------------------------------------------
; EVENT HOOKS (motherboard-called; per-event toggles gate them)
; ------------------------------------------------------------------
; These EXTEND Baka's spank-mark system (approved 2b design): the existing "SkyrimNet
; Spank" heat-stage marks are untouched; a user-chosen set from a discovered pack is
; applied ALONGSIDE when the event fires and the toggle is on.
; ------------------------------------------------------------------

; Spank-heat event: called from ApplySpankMark after Baka's own marks.
Function OnSpankHeat(Actor akTarget) Global
    Actor p = Game.GetPlayer()
    If !akTarget || StorageUtil.GetIntValue(p, "SNBaka.ST.Enabled", 1) != 1
        Return
    EndIf
    If StorageUtil.GetIntValue(p, "SNBaka.ST.ApplyOnSpank", 1) != 1
        Return
    EndIf
    String section = StorageUtil.GetStringValue(p, "SNBaka.ST.SpankSetSection", "")
    String name = StorageUtil.GetStringValue(p, "SNBaka.ST.SpankSetName", "")
    If section == "" || name == ""
        Return    ; no set chosen yet ? nothing to extend with
    EndIf
    If ApplyTattoo(akTarget, section, name, StorageUtil.GetIntValue(p, "SNBaka.ST.SpankSetColor", -1), True, "spank")
        Debug.Trace("[SNBaka.ST] OnSpankHeat: applied '" + name + "' (" + section + ") to " + akTarget.GetDisplayName())
    EndIf
EndFunction

; Defeat/downed event: called from the motherboard's defeat path.
Function OnDefeat(Actor akVictim) Global
    Actor p = Game.GetPlayer()
    If !akVictim || StorageUtil.GetIntValue(p, "SNBaka.ST.Enabled", 1) != 1
        Return
    EndIf
    If StorageUtil.GetIntValue(p, "SNBaka.ST.ApplyOnDefeat", 1) != 1
        Return
    EndIf
    String section = StorageUtil.GetStringValue(p, "SNBaka.ST.DefeatSetSection", "")
    String name = StorageUtil.GetStringValue(p, "SNBaka.ST.DefeatSetName", "")
    If section == "" || name == ""
        Return
    EndIf
    If ApplyTattoo(akVictim, section, name, StorageUtil.GetIntValue(p, "SNBaka.ST.DefeatSetColor", -1), True, "defeat")
        Debug.Trace("[SNBaka.ST] OnDefeat: applied '" + name + "' (" + section + ") to " + akVictim.GetDisplayName())
    EndIf
EndFunction

; Escalation handoff event: called from the motherboard's escalation path.
Function OnEscalation(Actor akVictim) Global
    Actor p = Game.GetPlayer()
    If !akVictim || StorageUtil.GetIntValue(p, "SNBaka.ST.Enabled", 1) != 1
        Return
    EndIf
    If StorageUtil.GetIntValue(p, "SNBaka.ST.ApplyOnEscalation", 0) != 1
        Return
    EndIf
    String section = StorageUtil.GetStringValue(p, "SNBaka.ST.EscalationSetSection", "")
    String name = StorageUtil.GetStringValue(p, "SNBaka.ST.EscalationSetName", "")
    If section == "" || name == ""
        Return
    EndIf
    If ApplyTattoo(akVictim, section, name, StorageUtil.GetIntValue(p, "SNBaka.ST.EscalationSetColor", -1), True, "escalation")
        Debug.Trace("[SNBaka.ST] OnEscalation: applied '" + name + "' (" + section + ") to " + akVictim.GetDisplayName())
    EndIf
EndFunction

; ------------------------------------------------------------------
; FADING (NG-gated) ? v1 SCOPE DECISION, RECORDED (user ruling, this rev):
; minimal-LLM-context v1 ships hard on/off for module-applied sets; the NG alpha-step
; fade curve (apply_overlay_ex) is deferred to the tweak pass/v2 with its own gate report.
; Rationale: the spank marks' own fade (FadeActorTats) is already NG-blind remove/re-add;
; a second fade path in v1 doubles the surface needing dogfood.
; ------------------------------------------------------------------

; ------------------------------------------------------------------
;  (2026-10-24) - TATTOO v2 SESSION 1: APPLIED-STATE MODEL (4.2)
; + VISIBILITY CASCADE (4.1) + FORCED-TATTOO SERVICE (4.3)
; Spec of record: slavetats.md  6.1-6.3 + the planner's Tattoo
; Application section. Batch mode: pure Papyrus + content; NO DLL/esp.
; ------------------------------------------------------------------

; 4.2 helper: resolve the SlaveTats AREA (Body/Face/Hands/Feet) a section/name
; pair lives on, by walking the NG/SE cache (same shape-tolerant walk as
; GetSetNames). Returns "" when not found (entry stores area "" -> layer-1
; reads it as Body-class torso coverage by default, honestly coarse).
String Function _ResolveAreaFor(String asSection, String asName) Global
    String result = ""
    If !Installed() || asSection == "" || asName == ""
        Return result
    EndIf
    Int cache = SlaveTats.acquire_cache()
    If cache == 0
        Return result
    EndIf
    Int dom = JMap.getObj(cache, "default")
    If dom != 0
        String[] areas = JMap.allKeysPArray(dom)
        Int a = 0
        While a < areas.Length && result == ""
            Int area = JMap.getObj(dom, areas[a])
            If area != 0
                Int sec = JMap.getObj(area, asSection)
                If sec != 0
                    If JValue.isArray(sec)
                        Int c = JArray.count(sec)
                        Int n = 0
                        While n < c && result == ""
                            If JMap.getStr(JArray.getObj(sec, n, 0), "name") == asName
                                result = areas[a]
                            EndIf
                            n += 1
                        EndWhile
                    Else
                        String[] names = JMap.allKeysPArray(sec)
                        Int n = 0
                        While n < names.Length && result == ""
                            If names[n] == asName
                                result = areas[a]
                            EndIf
                            n += 1
                        EndWhile
                    EndIf
                EndIf
            EndIf
            a += 1
        EndWhile
    EndIf
    SlaveTats.release_cache()
    Return result
EndFunction

; 4.2: freshness band for an apply timestamp (real-time seconds). Bands per
; the cum fragment precedent (0175: <600 fresh / <3600 drying / else faded);
; timestamp 0 = legacy entry (pre-) -> "unknown".
String Function FreshnessBand(Float afStamp, Float afNow = -1.0) Global
    If afStamp <= 0.0
        Return "unknown"
    EndIf
    If afNow < 0.0
        afNow = Utility.GetCurrentRealTime()
    EndIf
    Float age = afNow - afStamp
    If age < 0.0
        age = 0.0    ; clock reset / new session - never band-negative
    EndIf
    If age < 600.0
        Return "fresh"
    ElseIf age < 3600.0
        Return "drying"
    EndIf
    Return "faded"
EndFunction

; 4.2: parse an applied entry into its parts (positional; absent trailing
; fields default). [0]=section [1]=name [2]=color(-1 class) [3]=mode
; [4]=area [5]=timestamp.
String[] Function _EntryParts(String asEntry) Global
    String[] p = Utility.CreateStringArray(6, "")
    p[2] = "-1"
    If asEntry == ""
        Return p
    EndIf
    String[] f = StringUtil.Split(asEntry, "|")
    Int i = 0
    While i < f.Length && i < 6
        p[i] = f[i]
        i += 1
    EndWhile
    Return p
EndFunction

; 4.1 LAYER 1 - the coverage-default table (vanilla, always available).
; Maps a SlaveTats area to the armor slot whose worn form covers it:
;   Body -> slot 32 (body/cuirass)   Hands -> slot 33 (gloves)
;   Feet  -> slot 37 (boots)        Face  -> slot 30 (head/hair)
; Honest coarseness: the pack "Body" area spans torso/back/legs skin; a
; cuirass is the vanilla coverage proxy for the class. slot N = bit N-30.
Int Function _AreaSlotMask(String asArea) Global
    If asArea == "Hands"
        Return Math.LeftShift(1, 33 - 30)
    ElseIf asArea == "Feet"
        Return Math.LeftShift(1, 37 - 30)
    ElseIf asArea == "Face"
        Return Math.LeftShift(1, 30 - 30)
    EndIf
    Return Math.LeftShift(1, 32 - 30)    ; Body (and ""/unknown) -> body slot
EndFunction

; 4.1 LAYER 2 - revealing-armor keyword exceptions.  3.3 VERDICT:
; NOT BUILT - the installed packs' json metadata carries ONLY
; name/section/texture/area/credit (probed read-only, anal.json + Femboy.json
; cited); the "revealing" keyword class lives in the ARMOR mods' esps, and no
; source-resolvable keyword IDs exist in any readable tree. Per the spec'd
; fallback order the cascade runs layer 1 + layer 3; this stub keeps the
; layer-2 extension point named + sentinel'd, never silently true.
Bool Function _RevealingKeywordException(Actor akTarget, Int aiSlotMask) Global
    Return False
EndFunction

; 4.1 LAYER 3 - DD occlusion, presence-gated.  3.3/6.2 VERDICT: DD IS
; installed (DeviousDevices.dll, SexLab - Devious Devices NG folder cited)
; but the zad_ keyword FORM IDS are NOT source-resolvable (Devious Devices -
; BRRF.esp is fully compressed - zero plain-text zad_ strings; the SE patch
; esp carries zad_ strings in non-KEYM contexts only), so an occlusion read
; cannot be built pure-Papyrus this session. Presence is reported (probe
; pattern = NGDetected); occlusion stays not-blocking, sentinel'd - the gap
; is surfaced, not papered over. Needs DD form IDs (a source probe) or a DD
; script-surface bridge decision at a later session.
Bool Function _DDPresent() Global
    Return SKSE.GetPluginVersion("DeviousDevices") > 0
EndFunction

; 4.1: per-actor VISIBILITY resolution - which applied tattoos are
; observable. Read-only query surface (the LLM/cue consumers of later
; passes); ASCII sentinel per resolve. Returns one line per applied entry:
;   "section|name|area|band|0-or-1|reason"
; reason strings: layer1-covered / layer1-exposed /
; layer1-exposed-dd-occlusion-unresolved.
String[] Function ResolveVisibility(Actor akTarget) Global
    String[] noLines = Utility.CreateStringArray(0)
    If !akTarget
        Return noLines
    EndIf
    Int cnt = StorageUtil.StringListCount(akTarget, "SNBaka.ST.Applied")
    If cnt == 0
        Return noLines
    EndIf
    Bool dd = _DDPresent()
    Int exposed = 0
    String[] out = Utility.CreateStringArray(0)
    Int i = 0
    While i < cnt
        String[] p = _EntryParts(StorageUtil.StringListGet(akTarget, "SNBaka.ST.Applied", i))
        String area = p[4]
        If area == ""
            area = "Body"    ; unknown area (legacy entry) - body-class default, coarse
        EndIf
        Int mask = _AreaSlotMask(area)
        Bool covered = akTarget.GetWornForm(mask) != None
        If _RevealingKeywordException(akTarget, mask)
            covered = False    ; unreachable this session (layer-2 stub) - kept for the extension point
        EndIf
        Bool obs = !covered
        String reason = "layer1-covered"
        If obs
            reason = "layer1-exposed"
            If dd
                reason = "layer1-exposed-dd-occlusion-unresolved"    ; named gap: DD may occlude, unreadable this session
            EndIf
            exposed += 1
        EndIf
        out = PapyrusUtil.PushString(out, p[0] + "|" + p[1] + "|" + area + "|" + FreshnessBand(p[5] as Float) + "|" + (obs as Int) + "|" + reason)
        i += 1
    EndWhile
    Debug.Trace("[SNBaka.ST] ResolveVisibility: " + akTarget.GetDisplayName() + " entries=" + cnt + " exposed=" + exposed + " dd-present=" + dd + " (layer2=skip: no source-resolvable keyword IDs, REV-150 3.3 verdict)")
    Return out
EndFunction

; 4.3: the forced-tattoo SERVICE (the motherboard executor owns the gates,
; the downed-menu cue, and the body-compatibility verdict; this picks the set
; and applies). Set pick: the DEFEAT set first (the downed context), the
; spank set as fallback. Composes with Strip naturally (post-strip skin is
; the exposed canvas). Refusals are reason-coded traces (empty-state
; refusals per the ruling-2B service contract).
Bool Function ForcedTattoo(Actor akAggressor, Actor akVictim) Global
    If !akAggressor || !akVictim
        Debug.Trace("[SNBaka.ST] ForcedTattoo: REFUSED [null] - null actor leg")
        Return False
    EndIf
    If !Installed()
        Debug.Trace("[SNBaka.ST] ForcedTattoo: REFUSED [absent] - SlaveTats not installed")
        Return False
    EndIf
    Actor p = Game.GetPlayer()
    If StorageUtil.GetIntValue(p, "SNBaka.ST.Enabled", 1) != 1
        Debug.Trace("[SNBaka.ST] ForcedTattoo: REFUSED [disabled] - module master gate off")
        Return False
    EndIf
    String section = StorageUtil.GetStringValue(p, "SNBaka.ST.DefeatSetSection", "")
    String name = StorageUtil.GetStringValue(p, "SNBaka.ST.DefeatSetName", "")
    Int color = StorageUtil.GetIntValue(p, "SNBaka.ST.DefeatSetColor", -1)
    If section == "" || name == ""
        section = StorageUtil.GetStringValue(p, "SNBaka.ST.SpankSetSection", "")
        name = StorageUtil.GetStringValue(p, "SNBaka.ST.SpankSetName", "")
        color = StorageUtil.GetIntValue(p, "SNBaka.ST.SpankSetColor", -1)
        If section != "" && name != ""
            Debug.Trace("[SNBaka.ST] ForcedTattoo: defeat set unconfigured - spank set fallback")
        EndIf
    EndIf
    If section == "" || name == ""
        Debug.Trace("[SNBaka.ST] ForcedTattoo: REFUSED [noset] - no defeat or spank set configured (MCM / SlaveTats set menu)")
        Return False
    EndIf
    ; .1: a male-class victim whose configured set is NOT male-curated
    ; falls back to a random curated pick from the discovered packs (the
    ; Gay - */Femboy auto-whitelist class, then the keyword screen). No
    ; curated entry installed at all -> refuse [male-none-curated].
    If !_IsFemaleClass(akVictim) && !MaleMayWear(section, name)
        String[] pick = _PickCuratedForMale()
        If pick.Length < 2 || pick[0] == "" || pick[1] == ""
            Debug.Trace("[SNBaka.ST] ForcedTattoo: REFUSED [male-none-curated] - configured set '" + name + "' (" + section + ") fails the whitelist and no curated pack entry is installed (Gay - */Femboy or keyword-screen pass)")
            Return False
        EndIf
        Debug.Trace("[SNBaka.ST] ForcedTattoo: configured set not male-curated - curated fallback '" + pick[1] + "' (" + pick[0] + ")")
        section = pick[0]
        name = pick[1]
        color = -1    ; the curated pick rides its pack default
    EndIf
    Return ApplyTattoo(akVictim, section, name, color, True, "forced")
EndFunction

; .1: pick a random male-curated entry from the discovered cache.
; Pool pass = sections that pass MaleMayWear at section level (the
; Gay - */Femboy class auto-whitelists whole sections; other sections
; pass only when their own title text is anatomy-clean), then roll a
; section and screen its entries by name. Bounded at 8 section rolls ?
; this rides the forced path, not a hot loop.
String[] Function _PickCuratedForMale() Global
    String[] empty = Utility.CreateStringArray(2, "")
    If !Installed()
        Return empty
    EndIf
    String[] sections = GetSections()
    If sections.Length == 0
        Return empty
    EndIf
    String[] secPool = Utility.CreateStringArray(sections.Length, "")
    Int poolN = 0
    Int i = 0
    While i < sections.Length
        If MaleMayWear(sections[i], "")
            secPool[poolN] = sections[i]
            poolN += 1
        EndIf
        i += 1
    EndWhile
    If poolN == 0
        Return empty
    EndIf
    Int attempts = 0
    While attempts < 8
        String sec = secPool[Utility.RandomInt(0, poolN - 1)]
        String[] names = GetSetNames(sec)
        Int j = 0
        While j < names.Length
            If MaleMayWear(sec, names[j])
                String[] hit = Utility.CreateStringArray(2, "")
                hit[0] = sec
                hit[1] = names[j]
                Return hit
            EndIf
            j += 1
        EndWhile
        attempts += 1
    EndWhile
    Return empty
EndFunction

; ------------------------------------------------------------------
; LIFECYCLE (presence nudge from the motherboard, BakaSL pattern)
; ------------------------------------------------------------------

Function Arm() Global
    Debug.Trace("[SNBaka] module-arm: SlaveTats presence=" + Installed() + " NG=" + NGDetected())
    ; : the prompt-layer decorators (the 0175/132b registration
    ; class -- module-owned, idempotent every arm pass).
    Int rcFacts = SkyrimNetApi.RegisterDecorator("get_ded_marks", "SNBaka_SlaveTatsModule", "GetDedMarks")
    Int rcAny = SkyrimNetApi.RegisterDecorator("get_ded_marks_any", "SNBaka_SlaveTatsModule", "GetDedMarksAny")
    Debug.Trace("[SNBaka.ST] decorator register: get_ded_marks rc=" + rcFacts + " get_ded_marks_any rc=" + rcAny + " (REV-157)")
EndFunction

; ------------------------------------------------------------------
;  ? AMBIENT EXPOSURE PASS (daemon-tick consumer)
; ------------------------------------------------------------------
; *** RETIREMENT BANNER (, 2026-10-24): the v1 ObservationPass
; ( rider 3 ? player-only, ~4 game-hour cadence via
; SNBaka.ST.ObserveHours, heartbeat-dispatched from the motherboard's
; OnUpdateGameTime) is RETIRED. Superseded by THIS pass: visibility-gated
; (the  cascade's layer-1 truth), any nearby actor, any visible
; mark (foreign marks included ? the 3.3 verdict), daemon-tick cadence
; in both modes (the motherboard hook is _DaemonTick). History lives in
; git; the shipped tree carries exactly one ambient observation pass.
; The MCM "Ambient Observation Cues" toggle (SNBaka.ST.Observe) is
; FOLDED to this pass as its master gate. Records: slavetats.md  +
; PROJECT_STATE section 178.
;
; SHAPE (user rulings,  exchange):
;   - fires from the DAEMON TICK at ~35% likelihood when a tattoo is
;     VISIBLE (key SNBaka.ST.AmbientPct, default 35, MCM slider
;     "Ambient Exposure Chance"); fail = silent-with-sentinel.
;   - NO tattoos or none visible = skip the prompt entirely (sentinel
;     trace only ? no dead weight).
;   - per-actor exposure cooldown (the muse-floor pattern, real-time):
;     key SNBaka.ST.AmbientLast, floor SNBaka.ST.AmbientFloor
;     (default 600s; surfaced at the gate report).
;   - ANY visible mark counts (foreign-marks verdict: query_applied_tattoos
;     reads the framework's own applied bookkeeping, so marks applied by
;     other means ? SlaveTats-direct, other mods ? are reacted to too;
;     recommended + adopted, surfaced for confirmation).
;   - the cue branches on APPLICATION-SPECIFIC information: LOCATION
;     (v3 area), the SPECIFIC tattoo name, the wearer, and the wearer's
;     observable arousal tier (the  witness-chain clause wording
;     of record via _ArousalClause, self-keyed standard ? the reacting
;     NPC is unknown at fire time, so the wearer's observable state
;     carries the register; recorded interpretation, user-correctable).
;   - sdb_tattoo_observed_narr = the OPTIONAL direct-narration second
;     surface (MCM "Tattoo Ambient Narration", DEFAULT OFF, key
;     SNBaka.ST.AmbientNarr; eventType-only yaml
;     sdb_tattoo_observed_narr ? the 134f/153/154 pattern). Cue always;
;     narration the gated second surface.
; Receipt standard (4.8): every roll outcome, cooldown skip, fire, and
; narr fire/gated-skip is sentinel'd; ASCII throughout.
; ------------------------------------------------------------------
Function AmbientExposurePass() Global
    Actor p = Game.GetPlayer()
    If !p || !Installed()
        Return
    EndIf
    If StorageUtil.GetIntValue(p, "SNBaka.ST.Enabled", 1) != 1
        Return
    EndIf
    If StorageUtil.GetIntValue(p, "SNBaka.ST.Observe", 1) != 1
        Debug.Trace("[SNBaka.ST] ambient: master gate off (SNBaka.ST.Observe=0) - skip -- REV-156")
        Return
    EndIf
    ; --- the marked-population walk (pool-convention radius 2500, the
    ; daemon-scan class; children excluded like the pools; the dead and
    ; the too-far are walk-neutral). Up to 8 wearers recorded; the pick
    ; rotates by chance (the v1 recorded scope decision, generalized).
    Actor[] wearers = New Actor[8]
    Int nW = 0
    Actor[] all = PO3_SKSEFunctions.GetActorsByProcessingLevel(0)
    Int i = 0
    While i < all.Length && nW < 8
        Actor a = all[i]
        If a && !a.IsDead() && !a.IsChild() && a.GetDistance(p) <= 2500.0
            If _FirstVisibleMark(a) != ""
                wearers[nW] = a
                nW += 1
            EndIf
        EndIf
        i += 1
    EndWhile
    ; PO3's processing-level list does not reliably include the player ?
    ; the player's own visible marks count too (witness reactions key on
    ; the wearer's state; the wearer may be the player).
    If nW < 8 && _FirstVisibleMark(p) != ""
        wearers[nW] = p
        nW += 1
    EndIf
    If nW == 0
        Debug.Trace("[SNBaka.ST] ambient: no visible marks in radius - skip the prompt entirely (no dead weight) -- REV-156")
        Return
    EndIf
    Actor ak = wearers[Utility.RandomInt(0, nW - 1)]
    ; per-actor exposure cooldown (muse-floor pattern, real-time seconds)
    Float now = Utility.GetCurrentRealTime()
    Float floorS = StorageUtil.GetFloatValue(p, "SNBaka.ST.AmbientFloor", 600.0)
    If floorS > 0.0 && now - StorageUtil.GetFloatValue(ak, "SNBaka.ST.AmbientLast", -99999.0) < floorS
        Debug.Trace("[SNBaka.ST] ambient: cooldown skip - " + ak.GetDisplayName() + " was exposed recently (floor=" + floorS + "s) -- REV-156")
        Return
    EndIf
    Int pct = StorageUtil.GetIntValue(p, "SNBaka.ST.AmbientPct", 35)
    Int roll = Utility.RandomInt(1, 100)
    If roll > pct
        Debug.Trace("[SNBaka.ST] ambient: roll failed (" + roll + " > " + pct + "%) - silent-with-sentinel, no prompt -- REV-156")
        Return
    EndIf
    String[] m = StringUtil.Split(_FirstVisibleMark(ak), "|")
    String loc = "their exposed skin"
    If m.Length > 2 && m[2] == "Body"
        loc = "their exposed torso"
    ElseIf m.Length > 2 && m[2] == "Face"
        loc = "their face"
    ElseIf m.Length > 2 && m[2] == "Hands"
        loc = "their bare hands"
    ElseIf m.Length > 2 && m[2] == "Feet"
        loc = "their bare feet"
    EndIf
    StorageUtil.SetFloatValue(ak, "SNBaka.ST.AmbientLast", now)
    ; Cue (mandatory): branched on location + the specific mark + the
    ; wearer. Register entry 35 DRAFT (branch wordings at the user's pen).
    ;  SLIM (ruling (b), register entry 36): the cue drops to
    ; NUDGE-CLASS wording -- the standing facts (visible marks on self /
    ; others, section + name + location) now live in the get_ded_marks
    ; bio fragment (0177_ded_tattoos.prompt) and the application
    ; specifics stay in the APPLICATION events (sdb_tattoo_applied,
    ; ruling (a), untouched).
    ;  3.2 recast (register DRAFT): the observed cue drops the
    ; wearer's immediate-reaction clause (_ArousalClause -- the wearer's
    ; in-the-moment reaction is the APPLIED cue's territory only,
    ; sdb_tattoo_applied); the AMBIENT carries OTHERS noticing the mark,
    ; with the wearer optionally re-noticing it later (catching the
    ; looks). Narration-voice standard; others-first framing.
    SkyrimNetApi.RegisterEvent("sdb_tattoo_observed", \
        ak.GetDisplayName() + " has a tattoo showing on " + loc + ": '" + m[1] + "' (" + m[0] + "). Anyone close enough sees the mark; those who notice it react in their own way, and the wearer may catch their looks and grow newly aware of it too.", \
        ak, ak)
    Debug.Trace("[SNBaka.ST] ambient: FIRED sdb_tattoo_observed - wearer=" + ak.GetDisplayName() + " mark='" + m[1] + "' (" + m[0] + ") area=" + m[2] + " roll=" + roll + "/" + pct + "% -- REV-156")
    ; Narration (gated second surface, DEFAULT OFF).
    If StorageUtil.GetIntValue(p, "SNBaka.ST.AmbientNarr", 0) == 1
        SkyrimNetApi.RegisterEvent("sdb_tattoo_observed_narr", \
            "A visible tattoo on a nearby character has drawn attention.", \
            ak, ak)
        Debug.Trace("[SNBaka.ST] ambient: narr FIRED (sdb_tattoo_observed_narr, MCM Tattoo Ambient Narration ON) -- REV-156")
    Else
        Debug.Trace("[SNBaka.ST] ambient: narr GATED-SKIP (MCM Tattoo Ambient Narration OFF, default) -- REV-156")
    EndIf
EndFunction

; The first VISIBLE mark on an actor, any source (the 3.3 foreign-marks
; verdict): "section|name|area", or "" when nothing visible. Layer-1
; truth only (the coverage-default table; layers 2/3 stay named-gap per
; the  3.3 verdict ? no re-attempting). query_applied_tattoos
; reads the FRAMEWORK's own applied bookkeeping (JFormDB), so marks
; applied by any means are enumerated ? module-owned and foreign alike.
String Function _FirstVisibleMark(Actor akTarget) Global
    String empty = ""
    If !akTarget || !Installed()
        Return empty
    EndIf
    ; pool pattern (the installed SlaveTats source's own convention --
    ; has_applied_tattoos_with_attribute): one pooled query handle per
    ; call, released wholesale by cleanPool (no per-handle release).
    Int matches = JValue.addToPool(JArray.object(), "SNBaka-ST-AmbientQuery")
    String hit = ""
    Bool qErr = SlaveTats.query_applied_tattoos(akTarget, 0, matches)
    If qErr
        Debug.Trace("[SNBaka.ST] _FirstVisibleMark: query_applied_tattoos error on " + akTarget.GetDisplayName() + " -- REV-156")
    Else
        Int n = JArray.count(matches)
        Int i = 0
        While i < n && hit == ""
            Int e = JArray.getObj(matches, i)
            String area = JMap.getStr(e, "area")
            If area == ""
                area = "Body"    ; unknown area - body-class default, coarse (the ResolveVisibility convention)
            EndIf
            If akTarget.GetWornForm(_AreaSlotMask(area)) == None
                hit = JMap.getStr(e, "section") + "|" + JMap.getStr(e, "name") + "|" + area
            EndIf
            i += 1
        EndWhile
    EndIf
    JValue.cleanPool("SNBaka-ST-AmbientQuery")
    Return hit
EndFunction

;  4.5/4.6: validate an LLM-chosen (section, name) against the
; live pack cache. Returns "section|name" as a 2-slot array; "" on
; refuse. Invalid section -> random section; invalid name -> random
; name from the chosen section (bounded, sentinel'd fallbacks ? the LLM
; guidance points at the cache, the fallback keeps the lane functional
; on a stray pick). Body-compat is NOT screened here ? the ApplyTattoo
; choke point owns it ([male-not-curated], the .1 class).
String[] Function ValidatePick(String asSection, String asName) Global
    String[] out = Utility.CreateStringArray(2, "")
    String[] sections = GetSections()
    If sections.Length == 0
        Debug.Trace("[SNBaka.ST] ValidatePick: REFUSED [nopacks] - no sections discovered -- REV-156")
        Return out
    EndIf
    String sec = asSection
    If sections.Find(sec) < 0
        Debug.Trace("[SNBaka.ST] ValidatePick: section '" + asSection + "' not in cache - random fallback -- REV-156")
        sec = sections[Utility.RandomInt(0, sections.Length - 1)]
    EndIf
    String[] names = GetSetNames(sec)
    If names.Length == 0
        Debug.Trace("[SNBaka.ST] ValidatePick: REFUSED [emptyset] - section '" + sec + "' has no entries -- REV-156")
        Return out
    EndIf
    String nm = asName
    If names.Find(nm) < 0
        Debug.Trace("[SNBaka.ST] ValidatePick: name '" + asName + "' not in '" + sec + "' - random fallback -- REV-156")
        nm = names[Utility.RandomInt(0, names.Length - 1)]
    EndIf
    out[0] = sec
    out[1] = nm
    Return out
EndFunction

; ------------------------------------------------------------------
; SET PICKING (PrismaUI SNSlaveTats_Menu,  Task 3)
; ------------------------------------------------------------------
; The cache groups tattoos as cache -> domain("default") -> area -> section, and one
; section can span several areas (e.g. face + body entries of the same pack section).
; Enumeration therefore unions across areas.
;
; -b ? SECTION-NODE SHAPE (SE vs NG, the  discovery root cause):
;   SE 1.3.x: the section node is a JMap KEYED BY TATTOO NAME (names = map keys).
;   NG 0.8.x: the section node is a JArray OF ENTRY OBJECTS; each entry JMap carries
;   "name" (and "section") as values ? cf. NG's own SlaveTatsMCMMenu.psc _setup_sections.
;   GetSetNames dispatches on JValue.isArray/JValue.isMap so both frameworks enumerate
;   (the dual-flavor install is the worst case and must work). GetSections and
;   _EnumerateSections need no dispatch: they walk area-map KEYS only, identical shape
;   in both frameworks (proven by the healthy "18 sections discovered" count under NG).
; ------------------------------------------------------------------

; Unique section names discovered in the current cache (deduped across areas).
; Returns an empty array when SlaveTats is absent or the cache is empty.
String[] Function GetSections() Global
    String[] result = Utility.CreateStringArray(0)
    If !Installed()
        Return result
    EndIf
    Int cache = SlaveTats.acquire_cache()
    If cache == 0
        Return result
    EndIf
    Int dom = JMap.getObj(cache, "default")
    If dom != 0
        String[] areas = JMap.allKeysPArray(dom)
        Int a = 0
        While a < areas.Length
            Int area = JMap.getObj(dom, areas[a])
            If area != 0
                String[] secs = JMap.allKeysPArray(area)
                Int s = 0
                While s < secs.Length
                    If result.Find(secs[s]) < 0
                        result = PapyrusUtil.PushString(result, secs[s])
                    EndIf
                    s += 1
                EndWhile
            EndIf
            a += 1
        EndWhile
    EndIf
    SlaveTats.release_cache()
    ;  menu-path sentinel (?5): GetSections was one of the four silent functions
    ; on the picker path ? the ?80 diagnosis had to infer its health from side effects.
    Debug.Trace("[SNBaka.ST] GetSections: " + result.Length + " sections")
    Return result
EndFunction

; Build the SNSlaveTats_Menu JSON payload: current chosen sets + every discovered
; section with its tattoo names. Capped (60 sections / 30 names) so the JS payload
; stays sane for big installs; escaping is minimal (| and quotes are not expected in
; SlaveTats section/name keys). : payload carries "disc"/"emit" counts so the
; view's empty state can distinguish NOTHING-DISCOVERED from DISCOVERED-BUT-DROPPED
; (the ?80 UX lie), and the build itself traces the sections/listed/dropped triple.
String Function BuildMenuJSON() Global
    Actor p = Game.GetPlayer()
    String curSpank = StorageUtil.GetStringValue(p, "SNBaka.ST.SpankSetSection", "") + "|" + StorageUtil.GetStringValue(p, "SNBaka.ST.SpankSetName", "")
    String curDef   = StorageUtil.GetStringValue(p, "SNBaka.ST.DefeatSetSection", "") + "|" + StorageUtil.GetStringValue(p, "SNBaka.ST.DefeatSetName", "")
    String curEsc   = StorageUtil.GetStringValue(p, "SNBaka.ST.EscalationSetSection", "") + "|" + StorageUtil.GetStringValue(p, "SNBaka.ST.EscalationSetName", "")
    String json = "{\"spank\":\"" + curSpank + "\",\"defeat\":\"" + curDef + "\",\"escalation\":\"" + curEsc + "\",\"sections\":["
    String[] sections = GetSections()
    Int s = 0
    Int emitted = 0
    While s < sections.Length && emitted < 60
        String[] names = GetSetNames(sections[s])
        If names.Length > 0
            If emitted > 0
                json += ","
            EndIf
            json += "{\"n\":\"" + sections[s] + "\",\"t\":["
            Int n = 0
            Int nEmitted = 0
            While n < names.Length && nEmitted < 30
                If nEmitted > 0
                    json += ","
                EndIf
                json += "\"" + names[n] + "\""
                nEmitted += 1
                n += 1
            EndWhile
            json += "]}"
            emitted += 1
        EndIf
        s += 1
    EndWhile
    json += "]"
    ;  counted empty-state: the view gets discovery-vs-listed counts so it can
    ; tell "nothing discovered" from "discovered but dropped at render" (?80 UX lie).
    json += ",\"disc\":" + sections.Length + ",\"emit\":" + emitted + "}"
    Debug.Trace("[SNBaka.ST] BuildMenuJSON: sections=" + sections.Length + " listed=" + emitted + " dropped=" + (sections.Length - emitted))
    Return json
EndFunction

; Open the PrismaUI SlaveTats set-picker (SNSlaveTats_Menu view). The pick comes
; back through the DLL to the motherboard's _ST_MenuChoice(slot, section, name).
; Slot picks ("spank"/"defeat"/"escalation") land in SetChoice; the actor-bound picker
; mode (downed-menu Apply Tattoo) uses picker JSON and PickerChoice instead.
Function OpenSetMenu() Global
    If !Installed()
        Debug.Notification("SlaveTats is not installed - nothing to pick from.")
        Return
    EndIf
    If !SNBakaUI.IsAvailable()
        Debug.Notification("SlaveTats menu: PrismaUI / SNBaka DLL not ready.")
        Return
    EndIf
    RefreshPacks()
    ;  menu-path sentinel (?5): OpenSetMenu was silent on the MCM path.
    Debug.Trace("[SNBaka.ST] Picker: open path=MCM sections=" + StorageUtil.GetIntValue(Game.GetPlayer(), "SNBaka.ST.SectionCount", -1))
    SNBakaUI.ShowSlaveTatsMenu(BuildMenuJSON())
    ;  ?5 rider (picker defect, view-render class): the  sentinel fires
    ; BEFORE the show call, so the log could not distinguish "show issued" from
    ; "view actually became visible" ? a silently-dead view leg (the stale-DLL case)
    ; logs healthy. This POST-show trace is issued right after the bridge call; it
    ; proves the script leg ran to completion, and pairs with the DLL's own SKSE-log
    ; error line when the view cannot be created/shown (check skse64.log on defect).
    Debug.Trace("[SNBaka.ST] Picker: show issued path=MCM (post-call)")
EndFunction

; ------------------------------------------------------------------
;  rider 1 ? ACTOR-BOUND PICKER (service tattoo.picker)
; ------------------------------------------------------------------
; Service entry point the motherboard's downed menu calls (choice 8). Opens the SAME
; SNSlaveTats_Menu view in "picker" mode: the pick is applied immediately to the bound
; actor instead of stored in an MCM slot. Absence-handling is here, not in the host:
; no SlaveTats -> empty-state copy ("SlaveTats is not installed") with a Cancel button,
; per ruling ?B (the host's button is an unconditional affordance; the service owns the
; empty state).
; ------------------------------------------------------------------
; The actor the picker is currently bound to (None when no picker session is open).
; Stored player-keyed, NOT in script state ? the module is recordless/Globals-only.
Actor Function _PickerTarget() Global
    Return StorageUtil.GetFormValue(Game.GetPlayer(), "SNBaka.ST.PickerTarget", None) as Actor
EndFunction

Function OpenPickerFor(Actor akTarget, Actor akCaster = None) Global
    If !akTarget
        Return
    EndIf
    If !SNBakaUI.IsAvailable()
        Debug.Notification("SlaveTats menu: PrismaUI / SNBaka DLL not ready.")
        Return
    EndIf
    If !Installed()
        ; Empty-state picker (ruling ?B): open the view with zero sections so the
        ; player sees WHY there is nothing to pick, then cancel out. The ?7-gated copy
        ; lives in the view's no-sections branch.
        Debug.Notification("SlaveTats is not installed - nothing to pick from.")
        Return
    EndIf
    StorageUtil.SetFormValue(Game.GetPlayer(), "SNBaka.ST.PickerTarget", akTarget)
    RefreshPacks()
    ;  menu-path sentinel (?5): OpenPickerFor was silent on the event path.
    Debug.Trace("[SNBaka.ST] Picker: open path=event sections=" + StorageUtil.GetIntValue(Game.GetPlayer(), "SNBaka.ST.SectionCount", -1))
    SNBakaUI.ShowSlaveTatsMenu(BuildPickerJSON(akTarget))
    ;  ?5 rider (picker defect): POST-show trace, same as the MCM path ?
    ; proves the event leg ran to the bridge call (see OpenSetMenu note above).
    Debug.Trace("[SNBaka.ST] Picker: show issued path=event (post-call)")
EndFunction

; Picker-mode JSON: same section/name enumeration as BuildMenuJSON, plus the mode +
; bound-actor display name the JS uses to label the confirm row.
String Function BuildPickerJSON(Actor akTarget) Global
    String json = BuildMenuJSON()
    ; Splice "mode":"picker","target":"<name>" after the opening brace.
    Int openLen = 1
    json = "{\"mode\":\"picker\",\"target\":\"" + akTarget.GetDisplayName() + "\"," + StringUtil.Substring(json, openLen, StringUtil.GetLength(json) - openLen)
    Return json
EndFunction

; Picker-mode dispatch (motherboard _ST_MenuChoice slot=="picker"): asSection/asName are
; the picked pair ? asName may carry "|loc|color" subfields from the picker grid. Applies
; IMMEDIATELY to the bound actor, then clears the binding.
Function PickerChoice(String asSection, String asName) Global
    Actor target = _PickerTarget()
    StorageUtil.SetFormValue(Game.GetPlayer(), "SNBaka.ST.PickerTarget", None)
    If !target
        Return
    EndIf
    If asSection == "" || asName == ""
        Return    ; cancelled / cleared ? nothing applied
    EndIf
    String name = asName
    Int color = -1
    Int sep = StringUtil.Find(asName, "|")
    If sep > 0
        ; The JS appends the chosen swatch as ONE subfield: "name|hex" (pack default =
        ; no subfield). Location is pack-fixed and display-only (schema verdict ? we do
        ; not invent location options).
        name = StringUtil.Substring(asName, 0, sep)
        color = _HexToInt(StringUtil.Substring(asName, sep + 1))
    EndIf
    ApplyTattoo(target, asSection, name, color, True, "picker")
EndFunction

; Store one slot's pick ("spank"/"defeat"/"escalation"). Empty section/name clears
; the slot. Called from SkyrimNet_BakaIntegration._ST_MenuChoice (DLL dispatch).
; : the MCM-mode picker sends the chosen color as a "|hex" subfield on asName ?
; split it off: name is stored bare, the color lands in the per-channel color key
; (SNBaka.ST.<Slot>SetColor; -1 = "Default" -> module-wide DefaultColor at apply time).
Function SetChoice(String asSlot, String asSection, String asName) Global
    Actor p = Game.GetPlayer()
    Int color = -1
    Int sep = StringUtil.Find(asName, "|")
    If sep > 0
        color = _HexToInt(StringUtil.Substring(asName, sep + 1))
        asName = StringUtil.Substring(asName, 0, sep)
    EndIf
    If asSlot == "spank"
        StorageUtil.SetStringValue(p, "SNBaka.ST.SpankSetSection", asSection)
        StorageUtil.SetStringValue(p, "SNBaka.ST.SpankSetName", asName)
        StorageUtil.SetIntValue(p, "SNBaka.ST.SpankSetColor", color)
    ElseIf asSlot == "defeat"
        StorageUtil.SetStringValue(p, "SNBaka.ST.DefeatSetSection", asSection)
        StorageUtil.SetStringValue(p, "SNBaka.ST.DefeatSetName", asName)
        StorageUtil.SetIntValue(p, "SNBaka.ST.DefeatSetColor", color)
    ElseIf asSlot == "escalation"
        StorageUtil.SetStringValue(p, "SNBaka.ST.EscalationSetSection", asSection)
        StorageUtil.SetStringValue(p, "SNBaka.ST.EscalationSetName", asName)
        StorageUtil.SetIntValue(p, "SNBaka.ST.EscalationSetColor", color)
    Else
        Return
    EndIf
    If asSection == "" || asName == ""
        Debug.Notification("SlaveTats: " + asSlot + " set cleared.")
    Else
        Debug.Notification("SlaveTats: " + asSlot + " set = " + asSection + " | " + asName)
    EndIf
EndFunction

; Tattoo names inside one section (unioned across all areas that carry it).
String[] Function GetSetNames(String asSection) Global
    String[] result = Utility.CreateStringArray(0)
    ; : shape sentinel for the exit trace below -- "none" = section not found.
    String shp = "none"
    If !Installed() || asSection == ""
        Return result
    EndIf
    Int cache = SlaveTats.acquire_cache()
    If cache == 0
        Return result
    EndIf
    Int dom = JMap.getObj(cache, "default")
    If dom != 0
        String[] areas = JMap.allKeysPArray(dom)
        Int a = 0
        While a < areas.Length
            Int area = JMap.getObj(dom, areas[a])
            If area != 0
                Int sec = JMap.getObj(area, asSection)
                If sec != 0
                    shp = "map"
                    If JValue.isArray(sec)
                        shp = "array"
                        ; NG 0.8.x shape: JArray of entry objects; the name is a VALUE
                        ; ("name" key) on each entry, not a map key. getObj on a
                        ; non-container entry returns 0 -> getStr yields "" -> skipped.
                        Int c = JArray.count(sec)
                        Int n = 0
                        While n < c
                            ;  arity fix (?80 root cause): 3-arg call ? the installed
                            ; JContainers native is getObj(object, index, default=0); the old
                            ; 2-arg call aborted to None on every entry read (294 errors).
                            String nm = JMap.getStr(JArray.getObj(sec, n, 0), "name")
                            If nm != "" && result.Find(nm) < 0
                                result = PapyrusUtil.PushString(result, nm)
                            EndIf
                            n += 1
                        EndWhile
                    Else
                        ; SE 1.3.x shape: JMap keyed by tattoo name (legacy path).
                        String[] names = JMap.allKeysPArray(sec)
                        Int n = 0
                        While n < names.Length
                            If result.Find(names[n]) < 0
                                result = PapyrusUtil.PushString(result, names[n])
                            EndIf
                            n += 1
                        EndWhile
                    EndIf
                EndIf
            EndIf
            a += 1
        EndWhile
    EndIf
    SlaveTats.release_cache()
    ;  menu-path sentinel (?5, per ?80 spec): one line per section call ?
    ; shape names which enumeration branch ran; count is the unioned result.
    Debug.Trace("[SNBaka.ST] GetSetNames: " + asSection + " shape=" + shp + " count=" + result.Length)
    Return result
EndFunction
; ------------------------------------------------------------------
;  - PROMPT-LAYER EXTENSION (the cum-v2 mold applied to tattoos)
; ------------------------------------------------------------------
; Two module-owned decorators (registered at arm, the 0175/132b class):
;   get_ded_marks(actor)       bio-lane FACTS (the 0175 mold): visible
;                              marks ONLY (the  cascade layer-1
;                              truth, the user's visible-only ruling);
;                              the self/other split; location + section
;                              + name carried per visible mark. Covered
;                              marks render nothing.
;   get_ded_marks_any(actor)   disposition-lane eligibility (the 132b
;                              minimal any/nearest class).
; NULL CONTRACT (the  discipline): every absent-framework state
;                              returns well-formed JSON - SlaveTats
;                              absent, no marks anywhere, nothing
;                              visible, empty scan all read as
;                              {"present": false} / {"any": false}; no
;                              read can surface null.
; ------------------------------------------------------------------
; The first visible mark on an actor as a facts string
; "section|name|area", or "" when nothing visible (the _FirstVisibleMark
; truth, reused as the single-fact projection).
String Function _DedFirstVisibleMark(Actor akTarget) Global
    Return _FirstVisibleMark(akTarget)
EndFunction

; All visible marks on an actor, any source, as a facts string
; "section|name|area" joined by "~", or "" when nothing visible. Truth
; identical to _FirstVisibleMark (the  layer-1 cascade; layers
; 2/3 named-gap, no re-attempting): query_applied_tattoos enumerates
; module-owned AND foreign marks; an entry is visible when its area's
; coverage slot is unworn. Pool pattern per the installed-source
; convention (its own pool name, cleaned wholesale every call).
String Function _DedAllVisibleMarks(Actor akTarget) Global
    String out = ""
    If !akTarget || !Installed()
        Return out
    EndIf
    Int matches = JValue.addToPool(JArray.object(), "SNBaka-ST-DedMarksQuery")
    Bool qErr = SlaveTats.query_applied_tattoos(akTarget, 0, matches)
    If qErr
        Debug.Trace("[SNBaka.ST] _DedAllVisibleMarks: query_applied_tattoos error on " + akTarget.GetDisplayName() + " - treated as no marks (REV-157)")
    Else
        Int n = JArray.count(matches)
        Int i = 0
        Int nOut = 0
        While i < n
            Int e = JArray.getObj(matches, i)
            String area = JMap.getStr(e, "area")
            If area == ""
                area = "Body"    ; unknown area - body-class default, coarse (the _FirstVisibleMark convention)
            EndIf
            If akTarget.GetWornForm(_AreaSlotMask(area)) == None
                If nOut > 0
                    out = out + "~"
                EndIf
                out = out + JMap.getStr(e, "section") + "|" + JMap.getStr(e, "name") + "|" + area
                nOut += 1
            EndIf
            i += 1
        EndWhile
    EndIf
    JValue.cleanPool("SNBaka-ST-DedMarksQuery")
    Return out
EndFunction

; get_ded_marks: bio-lane facts for the subject. SELF branch: the
; subject's own visible marks. OTHER branch: visible marks on actors
; in the subject's cell. SlaveTats absent / nothing visible ->
; {"present": false}. Speaker/target rule compliant by construction
; (the subject is always the actor in scope).
String Function GetDedMarks(Actor akActor) Global
    If !akActor || !Installed()
        Return "{\"present\": false}"
    EndIf
    ; SELF: the subject's own visible marks
    String selfMarks = _DedAllVisibleMarks(akActor)
    If selfMarks != ""
        String[] sm = StringUtil.Split(selfMarks, "~")
        Int i = 0
        String out = "{\"present\": true, \"self\": true, \"marks\": ["
        While i < sm.Length
            String[] p = StringUtil.Split(sm[i], "|")
            out += "{\"section\": \"" + p[0] + "\", \"name\": \"" + p[1] + "\", \"area\": \"" + p[2] + "\"}"
            If i < sm.Length - 1
                out += ","
            EndIf
            i += 1
        EndWhile
        Return out + "]}"
    EndIf
    ; OTHER: visible marks on actors in the subject's cell
    If !akActor.GetParentCell()
        Return "{\"present\": false}"
    EndIf
    Actor[] all = PO3_SKSEFunctions.GetActorsByProcessingLevel(0)
    Int i = 0
    Int nAll = all.Length
    String out = "{\"present\": false}"
    While i < nAll
        Actor a = all[i]
        If a && a != akActor && !a.IsDead() && !a.IsChild() && a.GetParentCell() == akActor.GetParentCell()
            String m = _DedAllVisibleMarks(a)
            If m != ""
                String nm = a.GetDisplayName()
                If nm == ""
                    nm = "the marked person"
                EndIf
                String[] parts = StringUtil.Split(m, "~")
                Int j = 0
                out = "{\"present\": true, \"self\": false, \"wearer\": \"" + nm + "\", \"marks\": ["
                While j < parts.Length
                    String[] q = StringUtil.Split(parts[j], "|")
                    out += "{\"section\": \"" + q[0] + "\", \"name\": \"" + q[1] + "\", \"area\": \"" + q[2] + "\"}"
                    If j < parts.Length - 1
                        out += ","
                    EndIf
                    j += 1
                EndWhile
                Return out + "]}"
            EndIf
        EndIf
        i += 1
    EndWhile
    Return out
EndFunction

; get_ded_marks_any: the witness-eligibility read (the 132b minimal
; class). Any actor with a VISIBLE mark in the observer's cell (or the
; observer themself) -> {"any": true, "nearest": "<name>"}; else
; {"any": false}.
String Function GetDedMarksAny(Actor akObserver) Global
    If !akObserver || !Installed()
        Return "{\"any\": false}"
    EndIf
    If _DedFirstVisibleMark(akObserver) != ""
        String selfNm = akObserver.GetDisplayName()
        If selfNm == ""
            selfNm = "the marked person"
        EndIf
        Return "{\"any\": true, \"nearest\": \"" + selfNm + "\"}"
    EndIf
    If !akObserver.GetParentCell()
        Return "{\"any\": false}"
    EndIf
    Actor[] all = PO3_SKSEFunctions.GetActorsByProcessingLevel(0)
    Int i = 0
    While i < all.Length
        Actor a = all[i]
        If a && a != akObserver && !a.IsDead() && !a.IsChild() && a.GetParentCell() == akObserver.GetParentCell()
            If _DedFirstVisibleMark(a) != ""
                String nearest = a.GetDisplayName()
                If nearest == ""
                    nearest = "the marked person"
                EndIf
                Return "{\"any\": true, \"nearest\": \"" + nearest + "\"}"
            EndIf
        EndIf
        i += 1
    EndWhile
    Return "{\"any\": false}"
EndFunction
