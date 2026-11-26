#pragma once
// DeDDowned_API.h -- the DeD Downed state contract (DeDService.dll), v1. Spec: docs/specs/ded-downed-a2-spec.md
// sections 2 and 5. DeDService (the motherboard, ruleset rule 16) owns the per-actor downed state: phase, timers,
// aggressor, flags, the DWND cosave record and the events. The DeD Downed module DLL (DeDDowned.dll) holds the engine
// hooks and writes state only through this API; the Baka DLL reads it. Header-only; nothing to link:
//
//   const DeDDowned::Api1* d = DeDDowned::RequestApi1();   // nullptr = DeDService absent / older
//   if (d && d->IsDowned(actor->GetFormID())) { ... }
//
// Threading: every function may be called from any thread; events are sent on the game thread.
// ASCII only. Append-only: new functions go at the END of Api1.

#include <cstdint>

#ifndef DEDDOWNED_API_NO_LOADER
#	include <windows.h>
#endif

namespace DeDDowned
{
	inline constexpr std::uint32_t kApiVersion1 = 1;

	enum class Phase : std::uint32_t
	{
		None       = 0,  // normal
		Downed     = 1,  // on the ground, cannot act, pacified both ways
		Recovering = 2,  // standing, pacified: can move and talk, cannot fight
	};

	struct Api1
	{
		std::uint32_t apiVersion;   // = kApiVersion1

		// ---- reads ----
		Phase (*GetPhase)(std::uint32_t actorFormId);
		bool (*IsDowned)(std::uint32_t actorFormId);                // phase Downed
		bool (*IsPacified)(std::uint32_t actorFormId);              // Downed, Recovering, Restrained or scene pacify
		float (*GetTimeLeft)(std::uint32_t actorFormId);            // seconds left in the current phase (0 = none)
		std::uint32_t (*GetAggressor)(std::uint32_t actorFormId);   // FormID, 0 = none

		// ---- writes (each emits its ModEvent and a [DeDService][DOWNED] trace line) ----
		// reason: "lethal", "surrender", "stamina" or "api:<caller reason>".
		bool (*DownActor)(std::uint32_t victimFormId, std::uint32_t aggressorFormId, const char* reason);
		bool (*Recover)(std::uint32_t actorFormId, bool fullRescue);   // Downed -> Recovering (fullRescue: -> None)
		bool (*Release)(std::uint32_t actorFormId);                     // every temporary state -> None now
		void (*ScenePacifyBegin)(std::uint32_t actorFormId);            // ref-counted; holds expiry until the scene ends
		void (*ScenePacifyEnd)(std::uint32_t actorFormId);

		// ---- module side (DeDDowned.dll) ----
		// The module is loaded and armed (hooks installed, Acheron absent). Papyrus reads it as IsDownedModuleActive.
		void (*SetModuleArmed)(bool armed);
		// Real-time seconds while the game runs (the module's PlayerCharacter::Update). Without the module nothing ticks:
		// downs written by Baka stay until Baka recovers or releases them, as today.
		void (*Tick)(float deltaSeconds);
		// Phase lengths in seconds (spec 6.1 defaults 300 / 300); the module pushes its settings.
		void (*SetDurations)(float downedSeconds, float pacifiedSeconds);
		// Wait / sleep / fast travel / jail: every Downed and Recovering actor -> None (spec 6.3).
		void (*TimeSkipClear)(const char* why);

		// ---- A3b leg 3 (S340): the module's settings, saved per save game in the DWND record ----
		float (*GetSetting)(const char* key, float defaultValue);
		void (*SetSetting)(const char* key, float value);
		// One-shot Acheron migration (spec 14): false until the module ran it on this save.
		bool (*IsMigrated)();
		void (*SetMigrated)();

		// ---- A4 leg 1 (S342, D-A58): Acheron may stay installed but switched off ----
		// The module reports whether Acheron is installed (0 = absent, 1 = present). While it is present, the module
		// acts only after DeD_MCM reports (each reload) that Acheron's own "Enabled" toggle is off.
		void (*SetAcheronPresent)(bool present);
		// Hooks installed AND Acheron absent or switched off: the module's hooks may act.
		bool (*IsModuleActive)();

		// ---- A4 leg 3 (S344): the downed menu ----
		// Help Up in combat costs a health potion (D-A46 / D-A50): 0 = none, 1 = the weakest health potion (lowest gold
		// value; player-made ones only with the "custom potions" setting). consume = true removes it (game thread).
		// S345 (D-A60): healing spells are no Help Up cost; healing a downed actor above 30% health recovers them.
		int (*HelpUpHealing)(std::uint32_t helperFormId, bool consume);
		// Talk (D-A47): the next activation of this downed actor by the player opens dialogue instead of the panel.
		void (*AllowTalk)(std::uint32_t actorFormId);
		bool (*ConsumeTalkPass)(std::uint32_t actorFormId);

		// ---- A4 leg 4d (S349): assault reset, restraints, robbery (spec D-A53, sections 8 and 9) ----
		// D-A53: a Downed or Recovering actor goes back to the start of Downed (full downed timer, a held expiry
		// dropped); emits DeD_Downed with strArg "reset:<why>". false when the actor is in neither phase.
		bool (*ResetDowned)(std::uint32_t actorFormId, const char* why);
		// Restrained = pacified until freed (spec 8). gameHours > 0: freed by itself after that much game time
		// (DeD_RestraintChanged "off:expired:<source>"). A Downed actor restrained with source "baka_tie" keeps its
		// downed timer held (tied on the ground). Source "" when not restrained; buffer gets a NUL-terminated copy.
		void (*SetRestrained)(std::uint32_t actorFormId, bool on, const char* source, float gameHours);
		bool (*IsRestrained)(std::uint32_t actorFormId);
		void (*GetRestrainedSource)(std::uint32_t actorFormId, char* buffer, std::uint32_t size);
		// Robbery (spec 9): one line per robbery ("Bandit took 120 gold and a Steel Sword"), saved with the actor.
		void (*AddRobbed)(std::uint32_t actorFormId, const char* line);

		// ---- A4 leg 5 (S352): the talk-down parley (spec 7.1, D-A20 / D-A32) ----
		// on: the actor stands down toward the player: aggression Unaggressive, relationship to the player raised to
		// Acquaintance when lower; the originals are kept in the DWND row. off: both restored. Game thread.
		void (*SetNonViolent)(std::uint32_t actorFormId, bool on);
		bool (*IsNonViolent)(std::uint32_t actorFormId);
	};

#ifndef DEDDOWNED_API_NO_LOADER
	// nullptr when DeDService.dll is not loaded or is older than the requested version.
	inline const Api1* RequestApi1()
	{
		using Fn = const void* (*)(std::uint32_t);
		const HMODULE mod = ::GetModuleHandleW(L"DeDService.dll");
		const auto fn = mod ? reinterpret_cast<Fn>(::GetProcAddress(mod, "DeDDowned_RequestApi")) : nullptr;
		return fn ? static_cast<const Api1*>(fn(kApiVersion1)) : nullptr;
	}
#endif
}
