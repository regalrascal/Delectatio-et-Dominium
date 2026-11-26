#include "PCH.h"
#include "Downed.h"
#include "ServiceState.h"
#include "Scheduler.h"
#include "EventPump.h"
#include "ActorContextStore.h"
#include "DDGuard.h"
#include "ModuleRegistry.h"
#include "UIHost.h"
#include "PanelHost.h"
#include "PanelFlags.h"
#include "Preview.h"

#include "RE/T/TESForm.h"

namespace DeD
{
	// Spec of record: docs/features/service-dll.md section 1 (script name
	// provisional "DeDService"). All functions GLOBAL; modules never hold
	// service state. Keys are the dotted fully-qualified form ("cum.present").
	static constexpr const char* kScriptName = "DeDService";

	// ---------- helpers ----------
	static std::uint32_t OwnerFormIDOf(RE::Actor* a_owner)
	{
		return a_owner ? a_owner->GetFormID() : 0; // 0 = module-global row
	}

	// ---------- 1.1 registration / presence ----------
	static bool DeD_RegisterState(RE::StaticFunctionTag*,
		std::string_view a_moduleID, std::string_view a_key,
		std::int32_t a_valueType, bool a_actorKeyed,
		std::string_view a_defaultSerialized)
	{
		return ServiceState::GetSingleton().Register(
			std::string(a_moduleID), std::string(a_key),
			static_cast<ValueType>(a_valueType), a_actorKeyed,
			std::string(a_defaultSerialized));
	}

	static bool DeD_RemoveState(RE::StaticFunctionTag*,
		std::string_view a_moduleID, std::string_view a_key)
	{
		return ServiceState::GetSingleton().RemoveState(
			std::string(a_moduleID), std::string(a_key));
	}

	static bool DeD_RemoveTimerRule(RE::StaticFunctionTag*,
		std::string_view a_moduleID, std::string_view a_ruleID)
	{
		return Scheduler::GetSingleton().RemoveRule(
			std::string(a_moduleID), std::string(a_ruleID));
	}

	// ---------- 1.3 timer rules ----------
	static bool DeD_AddTimerRule(RE::StaticFunctionTag*,
		std::string_view a_moduleID, std::string_view a_ruleID,
		float a_cadenceSec, std::int32_t a_predicateClass,
		RE::Actor* a_predicateOwner, std::string_view a_predicateKey,
		float a_failsafeSec, std::string_view a_callbackEvent)
	{
		return Scheduler::GetSingleton().AddRule(
			std::string(a_moduleID), std::string(a_ruleID), a_cadenceSec,
			a_predicateClass, std::string(a_predicateKey),
			OwnerFormIDOf(a_predicateOwner), a_failsafeSec,
			std::string(a_callbackEvent));
	}

	// ---------- 1.2 state access (typed variants) ----------
	// Keys are dotted ("cum.present"); a module reaches only its own family
	// by construction (its moduleID prefixes the key it passes).
	static bool DeD_SetStateInt(RE::StaticFunctionTag*, RE::Actor* a_owner,
		std::string_view a_key, std::int32_t a_value)
	{
		StateValue v;
		v.type = ValueType::Int;
		v.i = a_value;
		return ServiceState::GetSingleton().Set(std::string(a_key), OwnerFormIDOf(a_owner), v);
	}

	static bool DeD_SetStateFloat(RE::StaticFunctionTag*, RE::Actor* a_owner,
		std::string_view a_key, float a_value)
	{
		StateValue v;
		v.type = ValueType::Float;
		v.f = a_value;
		return ServiceState::GetSingleton().Set(std::string(a_key), OwnerFormIDOf(a_owner), v);
	}

	static bool DeD_SetStateString(RE::StaticFunctionTag*, RE::Actor* a_owner,
		std::string_view a_key, std::string_view a_value)
	{
		StateValue v;
		v.type = ValueType::String;
		v.s = std::string(a_value);
		return ServiceState::GetSingleton().Set(std::string(a_key), OwnerFormIDOf(a_owner), v);
	}

	static bool DeD_SetStateBool(RE::StaticFunctionTag*, RE::Actor* a_owner,
		std::string_view a_key, bool a_value)
	{
		StateValue v;
		v.type = ValueType::Bool;
		v.b = a_value;
		return ServiceState::GetSingleton().Set(std::string(a_key), OwnerFormIDOf(a_owner), v);
	}

	static bool DeD_SetStateFormID(RE::StaticFunctionTag*, RE::Actor* a_owner,
		std::string_view a_key, RE::TESForm* a_value)
	{
		StateValue v;
		v.type = ValueType::FormID;
		v.form = a_value ? a_value->GetFormID() : 0;
		return ServiceState::GetSingleton().Set(std::string(a_key), OwnerFormIDOf(a_owner), v);
	}

	static std::int32_t DeD_GetStateInt(RE::StaticFunctionTag*, RE::Actor* a_owner,
		std::string_view a_key, std::int32_t a_default)
	{
		StateValue v;
		return ServiceState::GetSingleton().Get(std::string(a_key), OwnerFormIDOf(a_owner), v) ? static_cast<std::int32_t>(v.i) : a_default;
	}

	static float DeD_GetStateFloat(RE::StaticFunctionTag*, RE::Actor* a_owner,
		std::string_view a_key, float a_default)
	{
		StateValue v;
		return ServiceState::GetSingleton().Get(std::string(a_key), OwnerFormIDOf(a_owner), v) ? static_cast<float>(v.f) : a_default;
	}

	static std::string DeD_GetStateString(RE::StaticFunctionTag*, RE::Actor* a_owner,
		std::string_view a_key, std::string_view a_default)
	{
		StateValue v;
		return ServiceState::GetSingleton().Get(std::string(a_key), OwnerFormIDOf(a_owner), v) ? v.s : std::string(a_default);
	}

	static bool DeD_GetStateBool(RE::StaticFunctionTag*, RE::Actor* a_owner,
		std::string_view a_key, bool a_default)
	{
		StateValue v;
		return ServiceState::GetSingleton().Get(std::string(a_key), OwnerFormIDOf(a_owner), v) ? v.b : a_default;
	}

	static RE::TESForm* DeD_GetStateFormID(RE::StaticFunctionTag*, RE::Actor* a_owner,
		std::string_view a_key, RE::TESForm* a_default)
	{
		StateValue v;
		if (!ServiceState::GetSingleton().Get(std::string(a_key), OwnerFormIDOf(a_owner), v)) return a_default;
		return v.form ? RE::TESForm::LookupByID(v.form) : a_default;
	}

	static bool DeD_HasState(RE::StaticFunctionTag*, RE::Actor* a_owner, std::string_view a_key)
	{
		return ServiceState::GetSingleton().HasState(std::string(a_key), OwnerFormIDOf(a_owner));
	}

	static bool DeD_ClearActorState(RE::StaticFunctionTag*, RE::Actor* a_owner,
		std::string_view a_moduleID)
	{
		if (!a_owner) return false;
		return ServiceState::GetSingleton().ClearActorState(a_owner->GetFormID(), std::string(a_moduleID));
	}

	// ---------- 1.4 event pump ----------
	static bool DeD_PushEvent(RE::StaticFunctionTag*,
		std::string_view a_eventName, RE::TESForm* a_sender,
		std::int32_t a_iNumArg, float a_fFloatArg,
		std::string_view a_strArg, RE::TESForm* a_formArg)
	{
		return EventPump::Push(std::string(a_eventName), a_sender, a_iNumArg,
			a_fFloatArg, std::string(a_strArg), a_formArg);
	}

	// ---------- 1.5 actor context (REV-170 Leg 3; design of record:
	// docs/specs/native-optimization-lanes.md Lane 2 s"REV-170 Leg 2") ----------
	static std::string DeD_GetActorContext(RE::StaticFunctionTag*,
		RE::Actor* a_owner, std::string_view a_factClass)
	{
		return ActorContextStore::GetSingleton().Get(a_owner, std::string(a_factClass));
	}

	static bool DeD_SetActorContext(RE::StaticFunctionTag*,
		RE::Actor* a_owner, std::string_view a_factClass,
		std::string_view a_value, std::string_view a_source)
	{
		return ActorContextStore::GetSingleton().Set(
			a_owner, std::string(a_factClass), std::string(a_value), std::string(a_source));
	}

	static bool DeD_InvalidateActorContext(RE::StaticFunctionTag*, RE::Actor* a_owner)
	{
		return ActorContextStore::GetSingleton().Invalidate(a_owner);
	}

	static void DeD_ArmActorContextCooldown(RE::StaticFunctionTag*,
		RE::Actor* a_owner, std::string_view a_factClass)
	{
		ActorContextStore::GetSingleton().ArmCooldown(a_owner, std::string(a_factClass));
	}

	// ---------- 1.6 DDNG stale-strip guard (REV-187; spec of record:
	// docs/specs/ddng-force-strip-after-redress-guard.md v1.2, Component 1
	// Papyrus-side gate) ----------
	static bool DeD_DDNGPresent(RE::StaticFunctionTag*)
	{
		return DDGuard::DDNGPresent();
	}

	// ---------- 1.7 UI host (Magelight workstream Phase 1; docs/workstreams/magelight-ui.md 6c) ----------
	// True when DeDService acquired Magelight and created the installed modules' views.
	static bool DeD_PanelAvailable(RE::StaticFunctionTag*)
	{
		return UIHost::GetSingleton().IsAvailable();
	}

	// True when the module's descriptor was found and its required plugin is loaded.
	static bool DeD_PanelModuleInstalled(RE::StaticFunctionTag*, std::string_view a_moduleID)
	{
		return ModuleRegistry::GetSingleton().IsInstalled(a_moduleID);
	}

	// ---------- 1.8 runtime (VR workstream V1) ----------
	// True on Skyrim VR. Lets scripts take VR-only paths (e.g. D-V5: the scene framework "Auto"
	// resolves to OStim in VR). Declared in DeDService.psc with the next script compile.
	static bool DeD_IsVR(RE::StaticFunctionTag*)
	{
		return REL::Module::IsVR();
	}

	// ---------- 1.9 the combined panel (Magelight Phase 2; docs/specs/magelight-phase2-spec.md) ----------
	// The DeD power's open request: runs the routing rules on the game thread. True = queued (the panel
	// view exists); the rules may still open, claim or refuse (DeDService.log [PANEL]).
	static bool DeD_OpenPanel(RE::StaticFunctionTag*, RE::Actor* a_caster)
	{
		if (!UIHost::GetSingleton().HasView(PanelHost::kModule, PanelHost::kView)) {
			SKSE::log::info("[DeDService][PANEL] OpenPanel: the panel view is not available.");
			return false;
		}
		const std::uint32_t casterId = a_caster ? a_caster->GetFormID() : 0;
		SKSE::GetTaskInterface()->AddTask([casterId]() {
			auto* caster = casterId ? RE::TESForm::LookupByID<RE::Actor>(casterId) : nullptr;
			PanelHost::GetSingleton().Open(caster);
		});
		return true;
	}

	// A module's section data for the page (JSON object).
	// T2 (S330): live preview (Phantasm). True when Phantasm is installed and DeDService's client registered.
	static bool DeD_PreviewAvailable(RE::StaticFunctionTag*)
	{
		return Preview::GetSingleton().Available();
	}

	// The actor's look changed (a tattoo put on or taken off): the open preview of them redraws. None = any.
	static void DeD_PreviewRefresh(RE::StaticFunctionTag*, RE::Actor* a_actor)
	{
		Preview::GetSingleton().Refresh(a_actor ? a_actor->GetFormID() : 0);
	}

	// S331: items off (abOn false) or back on (true) at once, menu open or not; the open picture of the actor rebuilds.
	static void DeD_PreviewDress(RE::StaticFunctionTag*, RE::Actor* a_actor, std::vector<RE::TESForm*> a_items, bool a_on)
	{
		if (!a_actor) return;
		std::vector<std::uint32_t> ids;
		for (auto* f : a_items) {
			if (f) ids.push_back(f->GetFormID());
		}
		Preview::GetSingleton().Dress(a_actor->GetFormID(), std::move(ids), a_on);
	}

	// ---- DeD Downed state (A3b leg 1, S338; spec docs/specs/ded-downed-a2-spec.md section 5) ----
	static std::uint32_t Id(RE::Actor* a) { return a ? a->GetFormID() : 0; }
	static std::vector<RE::Actor*> Actors(const std::vector<std::uint32_t>& a_ids)
	{
		std::vector<RE::Actor*> out;
		for (const auto id : a_ids) {
			if (auto* a = RE::TESForm::LookupByID<RE::Actor>(id)) out.push_back(a);
		}
		return out;
	}
	static bool DeD_IsDowned(RE::StaticFunctionTag*, RE::Actor* a) { return DeD::Downed::GetSingleton().IsDowned(Id(a)); }
	static bool DeD_IsPacified(RE::StaticFunctionTag*, RE::Actor* a) { return DeD::Downed::GetSingleton().IsPacified(Id(a)); }
	static std::int32_t DeD_GetDownedPhase(RE::StaticFunctionTag*, RE::Actor* a) { return static_cast<std::int32_t>(DeD::Downed::GetSingleton().GetPhase(Id(a))); }
	static std::vector<RE::Actor*> DeD_GetDownedActors(RE::StaticFunctionTag*) { return Actors(DeD::Downed::GetSingleton().ListDowned()); }
	static std::vector<RE::Actor*> DeD_GetPacifiedActors(RE::StaticFunctionTag*) { return Actors(DeD::Downed::GetSingleton().ListPacified()); }
	static bool DeD_DownActor(RE::StaticFunctionTag*, RE::Actor* v, RE::Actor* g, std::string a_reason)
	{
		return DeD::Downed::GetSingleton().DownActor(Id(v), Id(g), "api:" + a_reason);
	}
	static bool DeD_RecoverActor(RE::StaticFunctionTag*, RE::Actor* a, bool full) { return DeD::Downed::GetSingleton().Recover(Id(a), full); }
	static bool DeD_ReleaseActor(RE::StaticFunctionTag*, RE::Actor* a) { return DeD::Downed::GetSingleton().Release(Id(a)); }
	static void DeD_ScenePacifyBegin(RE::StaticFunctionTag*, RE::Actor* a) { if (a) DeD::Downed::GetSingleton().ScenePacifyBegin(Id(a)); }
	static void DeD_ScenePacifyEnd(RE::StaticFunctionTag*, RE::Actor* a) { if (a) DeD::Downed::GetSingleton().ScenePacifyEnd(Id(a)); }
	static void DeD_SetRestrained(RE::StaticFunctionTag*, RE::Actor* a, bool on, std::string src) { if (a) DeD::Downed::GetSingleton().SetRestrained(Id(a), on, src); }
	static bool DeD_IsRestrained(RE::StaticFunctionTag*, RE::Actor* a) { return DeD::Downed::GetSingleton().IsRestrained(Id(a)); }
	static void DeD_SetNonViolent(RE::StaticFunctionTag*, RE::Actor* a, bool on) { if (a) DeD::Downed::GetSingleton().SetNonViolent(Id(a), on); }
	static bool DeD_IsNonViolent(RE::StaticFunctionTag*, RE::Actor* a) { return DeD::Downed::GetSingleton().IsNonViolent(Id(a)); }
	static float DeD_GetDownedTimeLeft(RE::StaticFunctionTag*, RE::Actor* a) { return DeD::Downed::GetSingleton().GetTimeLeft(Id(a)); }
	static RE::Actor* DeD_GetDownedAggressor(RE::StaticFunctionTag*, RE::Actor* a)
	{
		const auto id = DeD::Downed::GetSingleton().GetAggressor(Id(a));
		return id ? RE::TESForm::LookupByID<RE::Actor>(id) : nullptr;
	}
	static bool DeD_IsDownedModuleActive(RE::StaticFunctionTag*) { return DeD::Downed::GetSingleton().ModuleArmed(); }
	// A3b leg 3 (S340): the one-shot Acheron migration (spec 14), run by DeD_MCM on a reload.
	static bool DeD_IsDownedMigrated(RE::StaticFunctionTag*) { return DeD::Downed::GetSingleton().IsMigrated(); }
	static void DeD_SetDownedMigrated(RE::StaticFunctionTag*) { DeD::Downed::GetSingleton().SetMigrated(); }
	// A4 leg 1 (S342, D-A58): DeD_MCM reports Acheron's own Enabled toggle each reload.
	static void DeD_SetAcheronProcessing(RE::StaticFunctionTag*, bool on) { DeD::Downed::GetSingleton().SetAcheronProcessing(on); }
	// A4 leg 3 (S344): the downed menu
	static std::int32_t DeD_UseHelpUpHealing(RE::StaticFunctionTag*, RE::Actor* a) { return DeD::Downed::GetSingleton().HelpUpHealing(Id(a), true); }
	static std::int32_t DeD_HasHelpUpHealing(RE::StaticFunctionTag*, RE::Actor* a) { return DeD::Downed::GetSingleton().HelpUpHealing(Id(a), false); }
	static std::string DeD_GetHelpUpHealingName(RE::StaticFunctionTag*) { return DeD::Downed::GetSingleton().LastHealingUsed(); }
	static RE::TESIdleForm* DeD_DownedKillMove(RE::StaticFunctionTag*, RE::Actor* a) { return DeD::Downed::GetSingleton().KillMoveFor(a); }
	static void DeD_AllowDownedTalk(RE::StaticFunctionTag*, RE::Actor* a) { if (a) DeD::Downed::GetSingleton().AllowTalk(Id(a)); }
	// A4 leg 4d (S349): restraints with an end (Baka Tie Up's hours), the assault reset (D-A53)
	static void DeD_RestrainFor(RE::StaticFunctionTag*, RE::Actor* a, float hours, std::string src) { if (a) DeD::Downed::GetSingleton().SetRestrained(Id(a), true, src, hours); }
	static bool DeD_ResetDowned(RE::StaticFunctionTag*, RE::Actor* a, std::string why) { return a && DeD::Downed::GetSingleton().ResetDowned(Id(a), why); }

	static bool DeD_PanelPush(RE::StaticFunctionTag*, std::string_view a_moduleID, std::string_view a_json)
	{
		const std::string m(a_moduleID), j(a_json);
		return PanelHost::GetSingleton().Push(m.c_str(), j.c_str());
	}

	// Confirms a settings write to the page: {"key":..,"value":..,"ok":..,"reason":..}.
	static bool DeD_PanelSettingResult(RE::StaticFunctionTag*, std::string_view a_moduleID, std::string_view a_json)
	{
		const std::string m(a_moduleID), j(a_json);
		return PanelHost::GetSingleton().SettingResult(m.c_str(), j.c_str());
	}

	// Publishes (abOn) or withdraws a routing flag for an actor ("downed", "in_scene", ...).
	static bool DeD_PanelSetFlag(RE::StaticFunctionTag*, RE::Actor* a_actor, std::string_view a_moduleID,
		std::string_view a_flag, bool a_on)
	{
		return a_actor && PanelFlags::GetSingleton().Set(a_actor->GetFormID(), std::string(a_moduleID), std::string(a_flag), a_on);
	}

	// The interact target the panel would use now (crosshair, else nearest living actor in range); None = none.
	static RE::Actor* DeD_PanelTarget(RE::StaticFunctionTag*)
	{
		return PanelHost::PickTarget();
	}

	// ---------- registration ----------
	bool RegisterPapyrusFunctions(RE::BSScript::IVirtualMachine* a_vm)
	{
		a_vm->RegisterFunction("RegisterState", kScriptName, DeD_RegisterState);
		a_vm->RegisterFunction("RemoveState", kScriptName, DeD_RemoveState);
		a_vm->RegisterFunction("RemoveTimerRule", kScriptName, DeD_RemoveTimerRule);
		a_vm->RegisterFunction("AddTimerRule", kScriptName, DeD_AddTimerRule);
		a_vm->RegisterFunction("SetStateInt", kScriptName, DeD_SetStateInt);
		a_vm->RegisterFunction("SetStateFloat", kScriptName, DeD_SetStateFloat);
		a_vm->RegisterFunction("SetStateString", kScriptName, DeD_SetStateString);
		a_vm->RegisterFunction("SetStateBool", kScriptName, DeD_SetStateBool);
		a_vm->RegisterFunction("SetStateFormID", kScriptName, DeD_SetStateFormID);
		a_vm->RegisterFunction("GetStateInt", kScriptName, DeD_GetStateInt);
		a_vm->RegisterFunction("GetStateFloat", kScriptName, DeD_GetStateFloat);
		a_vm->RegisterFunction("GetStateString", kScriptName, DeD_GetStateString);
		a_vm->RegisterFunction("GetStateBool", kScriptName, DeD_GetStateBool);
		a_vm->RegisterFunction("GetStateFormID", kScriptName, DeD_GetStateFormID);
		a_vm->RegisterFunction("HasState", kScriptName, DeD_HasState);
		a_vm->RegisterFunction("ClearActorState", kScriptName, DeD_ClearActorState);
		a_vm->RegisterFunction("PushEvent", kScriptName, DeD_PushEvent);
		a_vm->RegisterFunction("GetActorContext", kScriptName, DeD_GetActorContext);
		a_vm->RegisterFunction("SetActorContext", kScriptName, DeD_SetActorContext);
		a_vm->RegisterFunction("InvalidateActorContext", kScriptName, DeD_InvalidateActorContext);
		a_vm->RegisterFunction("ArmActorContextCooldown", kScriptName, DeD_ArmActorContextCooldown);
		a_vm->RegisterFunction("DDNGPresent", kScriptName, DeD_DDNGPresent);
		a_vm->RegisterFunction("PanelAvailable", kScriptName, DeD_PanelAvailable);
		a_vm->RegisterFunction("PanelModuleInstalled", kScriptName, DeD_PanelModuleInstalled);
		a_vm->RegisterFunction("IsVR", kScriptName, DeD_IsVR);
		a_vm->RegisterFunction("OpenPanel", kScriptName, DeD_OpenPanel);
		a_vm->RegisterFunction("PanelPush", kScriptName, DeD_PanelPush);
		a_vm->RegisterFunction("PanelSettingResult", kScriptName, DeD_PanelSettingResult);
		a_vm->RegisterFunction("PanelSetFlag", kScriptName, DeD_PanelSetFlag);
		a_vm->RegisterFunction("PanelTarget", kScriptName, DeD_PanelTarget);
		a_vm->RegisterFunction("PreviewAvailable", kScriptName, DeD_PreviewAvailable);
		a_vm->RegisterFunction("PreviewRefresh", kScriptName, DeD_PreviewRefresh);
		a_vm->RegisterFunction("PreviewDress", kScriptName, DeD_PreviewDress);   // S331
		// A3b leg 1 (S338): the DeD Downed state
		a_vm->RegisterFunction("IsDowned", kScriptName, DeD_IsDowned);
		a_vm->RegisterFunction("IsPacified", kScriptName, DeD_IsPacified);
		a_vm->RegisterFunction("GetDownedPhase", kScriptName, DeD_GetDownedPhase);
		a_vm->RegisterFunction("GetDownedActors", kScriptName, DeD_GetDownedActors);
		a_vm->RegisterFunction("GetPacifiedActors", kScriptName, DeD_GetPacifiedActors);
		a_vm->RegisterFunction("DownActor", kScriptName, DeD_DownActor);
		a_vm->RegisterFunction("RecoverActor", kScriptName, DeD_RecoverActor);
		a_vm->RegisterFunction("ReleaseActor", kScriptName, DeD_ReleaseActor);
		a_vm->RegisterFunction("ScenePacifyBegin", kScriptName, DeD_ScenePacifyBegin);
		a_vm->RegisterFunction("ScenePacifyEnd", kScriptName, DeD_ScenePacifyEnd);
		a_vm->RegisterFunction("SetRestrained", kScriptName, DeD_SetRestrained);
		a_vm->RegisterFunction("IsRestrained", kScriptName, DeD_IsRestrained);
		a_vm->RegisterFunction("SetNonViolent", kScriptName, DeD_SetNonViolent);
		a_vm->RegisterFunction("IsNonViolent", kScriptName, DeD_IsNonViolent);
		a_vm->RegisterFunction("GetDownedTimeLeft", kScriptName, DeD_GetDownedTimeLeft);
		a_vm->RegisterFunction("GetDownedAggressor", kScriptName, DeD_GetDownedAggressor);
		a_vm->RegisterFunction("IsDownedModuleActive", kScriptName, DeD_IsDownedModuleActive);
		a_vm->RegisterFunction("IsDownedMigrated", kScriptName, DeD_IsDownedMigrated);
		a_vm->RegisterFunction("SetDownedMigrated", kScriptName, DeD_SetDownedMigrated);
		a_vm->RegisterFunction("SetAcheronProcessing", kScriptName, DeD_SetAcheronProcessing);
		a_vm->RegisterFunction("UseHelpUpHealing", kScriptName, DeD_UseHelpUpHealing);
		a_vm->RegisterFunction("HasHelpUpHealing", kScriptName, DeD_HasHelpUpHealing);
		a_vm->RegisterFunction("GetHelpUpHealingName", kScriptName, DeD_GetHelpUpHealingName);
		a_vm->RegisterFunction("DownedKillMove", kScriptName, DeD_DownedKillMove);
		a_vm->RegisterFunction("AllowDownedTalk", kScriptName, DeD_AllowDownedTalk);
		a_vm->RegisterFunction("RestrainFor", kScriptName, DeD_RestrainFor);
		a_vm->RegisterFunction("ResetDowned", kScriptName, DeD_ResetDowned);
		SKSE::log::info("[DeDService] Papyrus functions registered (60).");
		return true;
	}
}
