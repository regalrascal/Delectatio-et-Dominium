Scriptname DeDService Hidden

; REV-113 -- DeDService Papyrus surface (spec of record:
; docs/features/service-dll.md section 1). All functions are GLOBAL on this
; one script; the DLL binds the natives. Modules never hold service state.
; Keys in the access API are the fully-qualified dotted form ("cum.present").

; ---- 1.1 registration / presence (arm-time / disarm-time) ----
bool function RegisterState(string asModuleID, string asKey, int aiValueType, bool abActorKeyed, string asDefaultSerialized) global native
; aiValueType: 0=Int, 1=Float, 2=String, 3=Bool, 4=FormID
bool function RemoveState(string asModuleID, string asKey) global native
bool function RemoveTimerRule(string asModuleID, string asRuleID) global native

; ---- 1.2 state access (typed variants; akOwner=None = module-global row) ----
bool function SetStateInt(Actor akOwner, string asKey, int aiValue) global native
bool function SetStateFloat(Actor akOwner, string asKey, float afValue) global native
bool function SetStateString(Actor akOwner, string asKey, string asValue) global native
bool function SetStateBool(Actor akOwner, string asKey, bool abValue) global native
bool function SetStateFormID(Actor akOwner, string asKey, Form akValue) global native

int function GetStateInt(Actor akOwner, string asKey, int aiDefault) global native
float function GetStateFloat(Actor akOwner, string asKey, float afDefault) global native
string function GetStateString(Actor akOwner, string asKey, string asDefault) global native
bool function GetStateBool(Actor akOwner, string asKey, bool abDefault) global native
Form function GetStateFormID(Actor akOwner, string asKey, Form akDefault) global native

bool function HasState(Actor akOwner, string asKey) global native
bool function ClearActorState(Actor akOwner, string asModuleID) global native

; ---- 1.3 timer rules (ONE tick loop; rules are data) ----
; aiPredicateClass: 0=ALWAYS, 1=STATE_BOOL_TRUE, 2=STATE_BOOL_CHANGED
bool function AddTimerRule(string asModuleID, string asRuleID, float afCadenceSec, int aiPredicateClass, Actor akPredicateOwner, string asPredicateKey, float afFailsafeSec, string asCallbackEvent) global native

; ---- 1.4 event pump ----
bool function PushEvent(string asEventName, Form akSender, int aiNumArg, float afFloatArg, string asStrArg, Form akFormArg) global native

; ---- 1.5 actor context (REV-170 Leg 3; in-memory, per-fact TTL, Papyrus-driven resolve) ----
; asFactClass: "vitals"(60s) / "summary"(1800s) / "relationships"(1800s) / "background"(1800s, unfetched at launch) / "uuidForm"(no TTL)
; Returns {"value":...,"source":...,"freshAt":...} on HIT, "" on MISS (resolve then SetActorContext; on render failure ArmActorContextCooldown).
string function GetActorContext(Actor akOwner, string asFactClass) global native
bool function SetActorContext(Actor akOwner, string asFactClass, string asValue, string asSource) global native
bool function InvalidateActorContext(Actor akOwner) global native
function ArmActorContextCooldown(Actor akOwner, string asFactClass) global native

; ---- 1.6 DDNG stale-strip guard (REV-187; spec ddng-force-strip-guard v1.2, Component 1 gate) ----
; True when the DeviousDevices SKSE plugin is present (resolved once at kDataLoaded by the DLL).
; Every Papyrus-side DD guard call no-ops when this is false (honest degradation).
bool function DDNGPresent() global native

; ---- 1.7 UI host (Magelight workstream Phase 1; docs/workstreams/magelight-ui.md 6c) ----
; True when DeDService acquired Magelight UI and created the installed modules' views.
bool function PanelAvailable() global native
; True when the module's descriptor (Data/Magelight/DeD/modules/<id>.json) was found and its required plugin is loaded.
bool function PanelModuleInstalled(string asModuleID) global native

; ---- 1.8 runtime (VR workstream V1) ----
; True on Skyrim VR (D-V5: the scene framework "Auto" resolves to OStim in VR).
bool function IsVR() global native

; ---- 1.9 the combined panel (Magelight Phase 2; docs/specs/magelight-phase2-spec.md) ----
; The DeD power's open request (akCaster None = the player). True = queued; the descriptors' routing rules
; then open the panel, hand the press to a module (claim) or refuse it. False = no panel view.
bool function OpenPanel(Actor akCaster) global native
; A module's section data for the page (a JSON object; "module" is filled in when missing).
bool function PanelPush(string asModuleID, string asJson) global native
; Confirms a settings write: {"key":..,"value":..,"ok":true|false,"reason":".."}.
bool function PanelSettingResult(string asModuleID, string asJson) global native
; Publishes (abOn) or withdraws a routing flag for an actor: "downed", "in_scene", "locked_by_other",
; "grappling", ... Flags live in memory and drop on load: re-publish from your own state after a load.
bool function PanelSetFlag(Actor akActor, string asModuleID, string asFlag, bool abOn) global native
; The interact target the panel would use now (crosshair, else nearest living actor in range); None = none.
Actor function PanelTarget() global native

; ---- 1.10 live preview (tattoo-overhaul T2; Phantasm, optional) ----
; True when Phantasm is installed: a module may then ask the panel page for a live picture of an actor (its section
; JSON's "preview":{"actor":"<FormID>"}). PreviewRefresh redraws the open picture after the actor's look changed.
bool function PreviewAvailable() global native
function PreviewRefresh(Actor akActor) global native
; S331: take akItems off (abOn false) or put them back on (true) at once, also while the panel pauses the game
; (Papyrus UnequipItem waits until the menu closes); the open picture of akActor rebuilds.
function PreviewDress(Actor akActor, Form[] akItems, bool abOn) global native
; Requests, actions and settings from the page reach a Papyrus-only module as ModEvent "DeD_Panel_<moduleID>":
; strArg = {"type":"req|act|set|claim|closed","module":..,"target":"0x..","data":{..},"route":{..}}, sender = the target.

; ---- DeD Downed state (A3b leg 1, S338; spec docs/specs/ded-downed-a2-spec.md section 5) ----
; DeDService owns every actor's downed state; the DeD Downed module (DeDDowned.dll) writes it from its hooks, Baka's
; own downs write it through DownActor. Without the module nothing ticks (Baka recovers / releases its own downs).
; Phase: 0 None, 1 Downed (on the ground, pacified), 2 Recovering (standing, pacified). Events (ModEvents, sender =
; the actor, strArg = detail): DeD_Downed, DeD_Recovering, DeD_Recovered, DeD_PacifyEnded, DeD_TimeSkipCleared,
; DeD_RestraintChanged.
bool function IsDowned(Actor akActor) global native
bool function IsPacified(Actor akActor) global native
int function GetDownedPhase(Actor akActor) global native
Actor[] function GetDownedActors() global native
Actor[] function GetPacifiedActors() global native
bool function DownActor(Actor akVictim, Actor akAggressor, string asReason) global native
bool function RecoverActor(Actor akActor, bool abFullRescue) global native
bool function ReleaseActor(Actor akActor) global native
function ScenePacifyBegin(Actor akActor) global native
function ScenePacifyEnd(Actor akActor) global native
function SetRestrained(Actor akActor, bool abOn, string asSource) global native
bool function IsRestrained(Actor akActor) global native
function SetNonViolent(Actor akActor, bool abOn) global native
bool function IsNonViolent(Actor akActor) global native
float function GetDownedTimeLeft(Actor akActor) global native
Actor function GetDownedAggressor(Actor akActor) global native
bool function IsDownedModuleActive() global native
; A3b leg 3 (S340): the one-shot Acheron migration (spec 14): DeD_MCM clears the old bridge's SNAcheron.* keys
; on the first reload with the DeD Downed module armed, then marks it done for this save.
bool function IsDownedMigrated() global native
function SetDownedMigrated() global native
; A4 leg 1 (S342, spec D-A58): with Acheron installed, DeD Downed acts only while Acheron's own "Enabled" toggle is
; off. DeD_MCM reports it on every reload (Acheron.IsProcessingDisabled).
function SetAcheronProcessing(bool abProcessing) global native
; A4 leg 3 (S344): the downed menu. Help Up in combat costs a health potion (spec D-A46 / D-A50): Use / Has return
; 0 = none, 1 = the weakest health potion (Use removes it); GetHelpUpHealingName = what the last Use spent. S345
; (D-A60): healing spells are no Help Up cost; healing a downed actor above 30% health recovers them.
; DownedKillMove: the vanilla kill move for the caster's weapon on a target on the ground (None = a plain kill).
; AllowDownedTalk: the player's next activation of that downed actor opens dialogue instead of the DeD panel (D-A47).
int function UseHelpUpHealing(Actor akHelper) global native
int function HasHelpUpHealing(Actor akHelper) global native
string function GetHelpUpHealingName() global native
Idle function DownedKillMove(Actor akCaster) global native
function AllowDownedTalk(Actor akActor) global native
; A4 leg 4d (S349): RestrainFor = SetRestrained on, freed by itself after afGameHours of game time (Baka Tie Up; a
; Downed actor tied with asSource "baka_tie" keeps its downed timer held). ResetDowned (spec D-A53): a Downed or
; Recovering actor back to the start of Downed with a full timer (DeD_Downed strArg "reset:<asWhy>").
function RestrainFor(Actor akActor, float afGameHours, string asSource) global native
bool function ResetDowned(Actor akActor, string asWhy) global native
