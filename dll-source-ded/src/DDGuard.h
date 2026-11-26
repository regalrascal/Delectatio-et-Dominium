#pragma once

// REV-187 -- DDNG stale-strip guard, DLL side (spec of record:
// docs/specs/ddng-force-strip-after-redress-guard.md v1.2, Component 4).
//
// A TESEquipEvent sink (the SNEquipTrap pattern: TESEquipEvent dispatches
// synchronously inside the engine equip path, on the initiating caller's
// thread, so CaptureStackBackTrace in the sink names the initiator). On an
// UNEQUIP of armor where DeviousDevices.dll is on the initiating stack, the
// sink emits the ModEvent "dd_guard_strip" (EventPump; sender = the actor,
// strArg = the armor form's hex FormID) and returns kContinue — every equip
// passes through unchanged; nothing is blocked or reversed here.
//
// The DLL NEVER writes DD state and never re-equips (ruling of record #3):
// the redress window check (fDDGuardWindow, default 10s), the zero-device
// gate (GetDevices().Length == 0), and the single re-equip retry all live in
// the Papyrus hit handler (SkyrimNet_BakaIntegration.OnDDGuardStrip), which
// enforces the constraint of record at the identical point as Component 2.
//
// The sink is a no-op when the DDNG plugin is absent (version probe at
// kDataLoaded, Component 1's gate) — zero behavior change on non-DDNG lists.

#include <cstdint>

#include "RE/Skyrim.h"

namespace DeD
{
	class DDGuard
	{
	public:
		static DDGuard& GetSingleton()
		{
			static DDGuard instance;
			return instance;
		}

		// TESEquipEvent plumbing: called by the sink (Plugin.cpp registers it).
		// Returns true when this un-equip is armor + DeviousDevices.dll on the
		// initiating stack + DDNG present (the sink then emits the callback).
		bool OnUnequip(RE::Actor* a_actor, RE::FormID a_baseFormID);

		// Stack attribution: true when DeviousDevices.dll appears in the
		// current thread's stack (the SNEquipTrap technique, spec Component 4).
		static bool DeviousDevicesOnStack();

		// Component 1 presence probe; resolved once at kDataLoaded by Plugin.cpp.
		static bool DDNGPresent();

		// Marks presence (Plugin.cpp kDataLoaded). Idempotent.
		void SetDDNGPresent();

		static constexpr const char* kHitEvent = "dd_guard_strip";

	private:
		DDGuard() = default;

		bool m_ddng = false; // DDNG plugin presence, resolved at kDataLoaded
	};
}