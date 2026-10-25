#include "PCH.h"
#include "EventPump.h"

#include "SKSE/SKSE.h"

#include <cctype>

namespace DeD
{
	static bool ValidEventName(const std::string& a_name)
	{
		if (a_name.empty() || a_name.size() > 128) return false;
		for (char c : a_name) {
			if (!(std::isalnum(static_cast<unsigned char>(c)) || c == '_' || c == '-')) return false;
		}
		return true;
	}

	bool EventPump::Push(const std::string& a_eventName, RE::TESForm* a_sender,
		std::int32_t a_iNumArg, float a_fFloatArg, const std::string& a_strArg,
		RE::TESForm* a_formArg)
	{
		if (!ValidEventName(a_eventName)) {
			SKSE::log::warn("[DeDService] PushEvent rejected (bad event name '{}')", a_eventName);
			return false;
		}
		// Argument packing onto the 2-slot ModEvent surface (documented in
		// service-dll.md build notes): numArg = iNumArg if nonzero else
		// fFloatArg; strArg = strArg; formArg rides sender only when the
		// caller passed no explicit sender (then the form's hex FormID also
		// rides strArg so both remain recoverable).
		float numArg = (a_iNumArg != 0) ? static_cast<float>(a_iNumArg) : a_fFloatArg;
		std::string strArg = a_strArg;
		RE::TESForm* sender = a_sender;
		if (!sender && a_formArg) {
			sender = a_formArg;
			if (strArg.empty()) strArg = fmt::format("{:08X}", a_formArg->GetFormID());
		}
		Emit(a_eventName, sender, numArg, strArg);
		return true;
	}

	void EventPump::Emit(const std::string& a_eventName, RE::TESForm* a_sender,
		float a_numArg, const std::string& a_strArg)
	{
		// dll-source-gs proven pattern (PrismaUIBridge.cpp): named ModEvent via
		// the SKSE mod-callback source, Papyrus receives it through
		// RegisterForModEvent(eventName, handler).
		auto* source = SKSE::GetModCallbackEventSource();
		if (!source) return;
		SKSE::ModCallbackEvent ev{};
		ev.eventName = RE::BSFixedString(a_eventName.c_str());
		ev.strArg = RE::BSFixedString(a_strArg.c_str());
		ev.numArg = a_numArg;
		ev.sender = a_sender;
		source->SendEvent(&ev);
		SKSE::log::debug("[DeDService] emitted '{}' num={} str='{}'", a_eventName, a_numArg, a_strArg);
	}
}
