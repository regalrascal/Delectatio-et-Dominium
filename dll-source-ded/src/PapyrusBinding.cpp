#include "PCH.h"
#include "ServiceState.h"
#include "Scheduler.h"
#include "EventPump.h"

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
		SKSE::log::info("[DeDService] Papyrus functions registered (17).");
		return true;
	}
}
