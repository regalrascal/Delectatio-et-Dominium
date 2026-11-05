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
