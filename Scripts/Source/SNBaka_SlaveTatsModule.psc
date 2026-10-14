Scriptname SNBaka_SlaveTatsModule
;  SlaveTats module (recordless observer/detection class — module contract point 3,
; fomod.md §architecture). NO SexLab/OStim/etc types here; the only foreign API surface is
; SlaveTats itself (compile-stubbed in tools\compile\local; runtime resolved from whichever
; SlaveTats install wins MO2 priority — currently SlaveTatsNG 0.8.2, a strict superset of
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
;   SNBaka.ST.Applied       StringList (actor-keyed) "section|name" entries this module applied
; ------------------------------------------------------------------

Bool Function Installed() Global
    ; Framework presence = the SlaveTats quest record loads from the esp (legacy SE esp, or
    ; the NG overwrite — NG's runtime SlaveTats.pex shadows SE's by MO2 priority, but both
    ; installs carry SlaveTats.esp; the record resolves either way).
    Return Game.GetFormFromFile(0x800, "SlaveTats.esp") != None
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
; Under MO2, a DISABLED pack is entirely absent from the virtual Data tree — so the
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
        Debug.Trace("[SNBaka.ST] RefreshPacks: rebuilt cache — " + sectionCount + " sections discovered")
    Else
        Debug.Trace("[SNBaka.ST] RefreshPacks: compile_cache() returned 0 — no packs visible (are any enabled in MO2?)")
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

; Apply one tattoo entry. Returns true if SlaveTats accepted the call.
; : aiColor < 0 = "not chosen" -> the module-wide default color (SNBaka.ST.DefaultColor,
; itself 0 = pack default / no recolor); aiColor 0 = pack default (explicit). The color is a
; 0xRRGGBB int; hex strings from the picker are parsed by _HexToInt.
Bool Function ApplyTattoo(Actor akTarget, String asSection, String asName, Int aiColor = -1, Bool abSilent = True, String asMode = "event") Global
    If !akTarget || !Installed()
        Return False
    EndIf
    If aiColor < 0
        aiColor = StorageUtil.GetIntValue(Game.GetPlayer(), "SNBaka.ST.DefaultColor", 0)
    EndIf
    Bool ok = SlaveTats.simple_add_tattoo(akTarget, asSection, asName, aiColor, True, abSilent, 1.0)
    If ok
        StorageUtil.StringListAdd(akTarget, "SNBaka.ST.Applied", sectionColorEntry(asSection, asName, aiColor), True)
        Debug.Trace("[SNBaka.ST] ApplyTattoo: applied '" + asName + "' (" + asSection + ") color=0x" + _IntToHex(aiColor) + " mode=" + asMode + " to " + akTarget.GetDisplayName())
        _FireEvent(True, akTarget, asSection, asName, aiColor, asMode)
    Else
        ; Failure logging (rider Task 2): SlaveTats rejected the call — the cache walk says
        ; the section/name pair exists, so a False here means the overlay add itself failed
        ; (missing texture files in the pack json is the usual cause). Surface it, don't swallow.
        Debug.Trace("[SNBaka.ST] ApplyTattoo: FAILED — SlaveTats rejected '" + asName + "' (" + asSection + ") on " + akTarget.GetDisplayName() + " (pack json missing entries?)")
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
        Debug.Trace("[SNBaka.ST] RemoveTattoo: FAILED — SlaveTats rejected '" + asName + "' (" + asSection + ") on " + akTarget.GetDisplayName())
    EndIf
    Return ok
EndFunction

; : applied-list entry now carries the color: "section|name|color" (old "section|name"
; entries from  saves remain readable — the color field simply parses as absent/0).
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

;  (rider 2): application-event triggers — fired from EVERY application path with the
; full payload the rider specifies (actor, section, name, location data, color, mode).
; Sentinel per fire is the  full-payload pattern: the event text itself carries the
; payload so the YAML cue can react to the SPECIFIC mark ({{ target }} etc. do the rest).
;  ( approved, ruling 3c): base text is OBSERVABLE-ONLY ("a fresh mark on their
; skin" — the  payload-reachability finding: response.content templates only player_name /
; event_json / time_desc / location / gameTimeStr and our 4-arg RegisterEvent fires no
; extraData, so section/name is NOT templateable in the YAML layer; the specific mark rides
; in THIS event text and the YAML points the LLM at it). The applied event appends an
; arousal-tier clause read on the MARKED ACTOR's own arousal (self-keyed ruling of record);
; neutral = SILENCE (base text alone, no invented state). The removed event ships base text
; only — the approved clause wording is application-reaction text; removal tiers are a v2
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
    ; Mode + color ride in the log for dogfood; the LLM cue stays source-agnostic ().
    Debug.Trace("[SNBaka.ST] _FireEvent: " + evName + " mode=" + asMode + " color=0x" + _IntToHex(aiColor))
EndFunction

;  (, Draft C approved): arousal tier for the applied-event clause, read on the
; MARKED ACTOR's own arousal (self-keyed interpretation of record — cumflation's matrix
; already conforms). Primary: OSL Aroused Reborn pure read via its SKSE plugin
; (GetArousal has time-update side effects — NEVER at fire time; the plugin-version gate
; keeps us off the native binding when the DLL is absent). Fallback: SLO Aroused NG via
; the "sla_Framework" quest (both NG and Reborn ship that quest/script pair; Reborn is
; caught by the primary, NG only by this). Neither readable -> "" (neutral = SILENCE,
; no invented state). Thresholds per the D&D Features Planner: >=75 / 25–75 / <=25.
; Clause wording standard OF RECORD (ratified , ): OBSERVABLE BEHAVIOR ONLY —
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
        Return    ; no set chosen yet — nothing to extend with
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
; FADING (NG-gated) — v1 SCOPE DECISION, RECORDED (user ruling, this rev):
; minimal-LLM-context v1 ships hard on/off for module-applied sets; the NG alpha-step
; fade curve (apply_overlay_ex) is deferred to the tweak pass/v2 with its own gate report.
; Rationale: the spank marks' own fade (FadeActorTats) is already NG-blind remove/re-add;
; a second fade path in v1 doubles the surface needing dogfood.
; ------------------------------------------------------------------

; ------------------------------------------------------------------
; LIFECYCLE (presence nudge from the motherboard, BakaSL pattern)
; ------------------------------------------------------------------

Function Arm() Global
    Debug.Trace("[SNBaka] module-arm: SlaveTats presence=" + Installed() + " NG=" + NGDetected())
EndFunction

; ------------------------------------------------------------------
;  rider 3 — AMBIENT OBSERVATION PASS
; ------------------------------------------------------------------
; Called from the motherboard heartbeat (its ~0.5-game-hour ground floor); throttled
; HERE to the module's own cadence (SNBaka.ST.ObserveHours, default 4 game hours) via a
; game-time stamp, so the heartbeat caller needs no state of its own. Idempotent,
; recordless-safe (Global call, player-keyed stamp only).
;
; v1 surface (recorded scope decision): the module has no global actor registry (the
; applied list is actor-keyed StorageUtil), so v1 observes the PLAYER's own module-
; applied marks — the one actor the module can always find for free. Firing a generic
; sdb_tattoo_observed cue lets nearby NPC personas notice the marks without the LLM
; polling overlays. Extending to arbitrary marked NPCs (an loaded-actor scan) is a v2
; candidate with its own cost report — noted for the tweak pass.
; ------------------------------------------------------------------
Function ObservationPass() Global
    Actor p = Game.GetPlayer()
    If !p || StorageUtil.GetIntValue(p, "SNBaka.ST.Enabled", 1) != 1
        Return
    EndIf
    ; MCM "Ambient Observation Cues" master gate (default ON); ObserveHours is the cadence.
    If StorageUtil.GetIntValue(p, "SNBaka.ST.Observe", 1) != 1
        Return
    EndIf
    Float now = Utility.GetCurrentGameTime()
    Float cadence = StorageUtil.GetFloatValue(p, "SNBaka.ST.ObserveHours", 4.0)
    If cadence <= 0.0
        Return    ; observation disabled via cadence 0 (belt-and-braces)
    EndIf
    Float last = StorageUtil.GetFloatValue(p, "SNBaka.ST.LastObserve", -999.0)
    If now - last < cadence && now - last >= 0.0
        Return    ; not yet due (the >= 0 guard survives game-time resets/new games)
    EndIf
    StorageUtil.SetFloatValue(p, "SNBaka.ST.LastObserve", now)
    ; Observe the player's own module-applied marks (first entry is enough for v1 —
    ; the cue text names the specific mark, and repeated passes rotate by chance).
    Int cnt = StorageUtil.StringListCount(p, "SNBaka.ST.Applied")
    If cnt == 0
        Return
    EndIf
    Int idx = Utility.RandomInt(0, cnt - 1)
    String entry = StorageUtil.StringListGet(p, "SNBaka.ST.Applied", idx)
    String sec = ""
    String nm = ""
    Int sep = StringUtil.Find(entry, "|")
    If sep > 0
        sec = StringUtil.Substring(entry, 0, sep)
        String rest = StringUtil.Substring(entry, sep + 1)
        Int sep2 = StringUtil.Find(rest, "|")
        nm = StringUtil.Substring(rest, 0, sep2)    ; sep2 < 0 (legacy entry) => whole rest
    EndIf
    If sec == "" || nm == ""
        Return
    EndIf
    SkyrimNetApi.RegisterEvent("sdb_tattoo_observed", \
        p.GetDisplayName() + " still visibly wears the degrading tattoo (" + sec + " / " + nm + "). Anyone around who notices it reacts to the specific mark.", \
        p, p)
EndFunction

; ------------------------------------------------------------------
; SET PICKING (PrismaUI SNSlaveTats_Menu,  Task 3)
; ------------------------------------------------------------------
; The cache groups tattoos as cache -> domain("default") -> area -> section, and one
; section can span several areas (e.g. face + body entries of the same pack section).
; Enumeration therefore unions across areas.
;
; -b — SECTION-NODE SHAPE (SE vs NG, the  discovery root cause):
;   SE 1.3.x: the section node is a JMap KEYED BY TATTOO NAME (names = map keys).
;   NG 0.8.x: the section node is a JArray OF ENTRY OBJECTS; each entry JMap carries
;   "name" (and "section") as values — cf. NG's own SlaveTatsMCMMenu.psc _setup_sections.
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
    ;  menu-path sentinel (): GetSections was one of the four silent functions
    ; on the picker path — the  diagnosis had to infer its health from side effects.
    Debug.Trace("[SNBaka.ST] GetSections: " + result.Length + " sections")
    Return result
EndFunction

; Build the SNSlaveTats_Menu JSON payload: current chosen sets + every discovered
; section with its tattoo names. Capped (60 sections / 30 names) so the JS payload
; stays sane for big installs; escaping is minimal (| and quotes are not expected in
; SlaveTats section/name keys). : payload carries "disc"/"emit" counts so the
; view's empty state can distinguish NOTHING-DISCOVERED from DISCOVERED-BUT-DROPPED
; (the  UX lie), and the build itself traces the sections/listed/dropped triple.
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
    ; tell "nothing discovered" from "discovered but dropped at render" ( UX lie).
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
    ;  menu-path sentinel (): OpenSetMenu was silent on the MCM path.
    Debug.Trace("[SNBaka.ST] Picker: open path=MCM sections=" + StorageUtil.GetIntValue(Game.GetPlayer(), "SNBaka.ST.SectionCount", -1))
    SNBakaUI.ShowSlaveTatsMenu(BuildMenuJSON())
    ;   rider (picker defect, view-render class): the  sentinel fires
    ; BEFORE the show call, so the log could not distinguish "show issued" from
    ; "view actually became visible" — a silently-dead view leg (the stale-DLL case)
    ; logs healthy. This POST-show trace is issued right after the bridge call; it
    ; proves the script leg ran to completion, and pairs with the DLL's own SKSE-log
    ; error line when the view cannot be created/shown (check skse64.log on defect).
    Debug.Trace("[SNBaka.ST] Picker: show issued path=MCM (post-call)")
EndFunction

; ------------------------------------------------------------------
;  rider 1 — ACTOR-BOUND PICKER (service tattoo.picker)
; ------------------------------------------------------------------
; Service entry point the motherboard's downed menu calls (choice 8). Opens the SAME
; SNSlaveTats_Menu view in "picker" mode: the pick is applied immediately to the bound
; actor instead of stored in an MCM slot. Absence-handling is here, not in the host:
; no SlaveTats -> empty-state copy ("SlaveTats is not installed") with a Cancel button,
; per ruling ②B (the host's button is an unconditional affordance; the service owns the
; empty state).
; ------------------------------------------------------------------
; The actor the picker is currently bound to (None when no picker session is open).
; Stored player-keyed, NOT in script state — the module is recordless/Globals-only.
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
        ; Empty-state picker (ruling ②B): open the view with zero sections so the
        ; player sees WHY there is nothing to pick, then cancel out. The -gated copy
        ; lives in the view's no-sections branch.
        Debug.Notification("SlaveTats is not installed - nothing to pick from.")
        Return
    EndIf
    StorageUtil.SetFormValue(Game.GetPlayer(), "SNBaka.ST.PickerTarget", akTarget)
    RefreshPacks()
    ;  menu-path sentinel (): OpenPickerFor was silent on the event path.
    Debug.Trace("[SNBaka.ST] Picker: open path=event sections=" + StorageUtil.GetIntValue(Game.GetPlayer(), "SNBaka.ST.SectionCount", -1))
    SNBakaUI.ShowSlaveTatsMenu(BuildPickerJSON(akTarget))
    ;   rider (picker defect): POST-show trace, same as the MCM path —
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
; the picked pair — asName may carry "|loc|color" subfields from the picker grid. Applies
; IMMEDIATELY to the bound actor, then clears the binding.
Function PickerChoice(String asSection, String asName) Global
    Actor target = _PickerTarget()
    StorageUtil.SetFormValue(Game.GetPlayer(), "SNBaka.ST.PickerTarget", None)
    If !target
        Return
    EndIf
    If asSection == "" || asName == ""
        Return    ; cancelled / cleared — nothing applied
    EndIf
    String name = asName
    Int color = -1
    Int sep = StringUtil.Find(asName, "|")
    If sep > 0
        ; The JS appends the chosen swatch as ONE subfield: "name|hex" (pack default =
        ; no subfield). Location is pack-fixed and display-only (schema verdict — we do
        ; not invent location options).
        name = StringUtil.Substring(asName, 0, sep)
        color = _HexToInt(StringUtil.Substring(asName, sep + 1))
    EndIf
    ApplyTattoo(target, asSection, name, color, True, "picker")
EndFunction

; Store one slot's pick ("spank"/"defeat"/"escalation"). Empty section/name clears
; the slot. Called from SkyrimNet_BakaIntegration._ST_MenuChoice (DLL dispatch).
; : the MCM-mode picker sends the chosen color as a "|hex" subfield on asName —
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
                            ;  arity fix ( root cause): 3-arg call — the installed
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
    ;  menu-path sentinel (, per  spec): one line per section call —
    ; shape names which enumeration branch ran; count is the unioned result.
    Debug.Trace("[SNBaka.ST] GetSetNames: " + asSection + " shape=" + shp + " count=" + result.Length)
    Return result
EndFunction