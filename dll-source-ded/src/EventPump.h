#pragma once

//  -- DeDService event pump (spec section 1.4): ModEvent emission with
// naming validation + debug tracing. Emissions ride the standard ModCallbackEvent
// source (eventName, strArg, numArg[float], sender); afFloatArg/akFormArg are
// accepted for API completeness -- the platform ModEvent carries no extra
// slots, so afFloatArg rides numArg when aiNumArg==0 and akFormArg rides
// sender when akSender is None (documented build note in service-dll.md).

#include <cstdint>
#include <string>

#include "RE/Skyrim.h"

namespace DeD
{
	class EventPump
	{
	public:
		// validated entry (Papyrus PushEvent): returns false on bad name.
		static bool Push(const std::string& a_eventName, RE::TESForm* a_sender,
			std::int32_t a_iNumArg, float a_fFloatArg, const std::string& a_strArg,
			RE::TESForm* a_formArg);

		// game-thread emission (also used by the scheduler tick).
		static void Emit(const std::string& a_eventName, RE::TESForm* a_sender,
			float a_numArg, const std::string& a_strArg);
	};
}
