#pragma once

//  -- DeDService single scheduler tick (spec section 1.3: ONE tick
// loop; rules are data, not processes). Divergence from the study subject
// (Papyrus chronometer pull chains) is deliberate -- see service-dll.md 0.2.
//
// DRIVE: the tick is driven from the input-event sink (one main-thread frame
// callback, the dll-source-gs proven pattern -- no DLL-side threads, no
// shutdown-order hazard). Drive() is called every frame; the evaluation pass
// runs at most once per second.
//
// PERSISTENCE: only rule PARAMETERS persist (cosave record 'TMRS' v1);
// runtime state (age, due bookkeeping, edge latch) re-arms fresh -- a
// save/load never resurrects half-fired timers. Absent-module rules are
// retained but gated on module presence (spec 1.1: rules do not fire).

#include <cstdint>
#include <mutex>
#include <string>
#include <unordered_map>
#include <vector>

#include "SKSE/SKSE.h"

namespace DeD
{
	enum class PredicateClass : std::uint8_t
	{
		ALWAYS = 0,
		STATE_BOOL_TRUE = 1,    // fires only while the named Bool state entry is True
		STATE_BOOL_CHANGED = 2  // fires once per False->True transition of the Bool entry
	};

	struct TimerRule
	{
		std::string moduleID;
		std::string ruleID;
		std::string predKey; // raw key; resolved as moduleID + "." + predKey
		std::string callbackEvent;
		float cadenceSec = 0.f;
		PredicateClass predClass = PredicateClass::ALWAYS;
		std::uint32_t predOwnerFormID = 0; // predicate entry owner (0 = module-global row)
		float failsafeSec = 0.f;           // <= 0 = none

		// runtime (never persisted)
		double ageSec = 0.0;
		double nextDueAge = 0.0;
		bool lastPred = false; // class-2 edge latch
	};

	class Scheduler
	{
	public:
		static Scheduler& GetSingleton()
		{
			static Scheduler instance;
			return instance;
		}

		bool AddRule(const std::string& a_moduleID, const std::string& a_ruleID, float a_cadenceSec,
			std::uint32_t a_predClass, const std::string& a_predKey, std::uint32_t a_predOwnerFormID,
			float a_failsafeSec, const std::string& a_callbackEvent);
		bool RemoveRule(const std::string& a_moduleID, const std::string& a_ruleID);

		// frame-driven (main thread): runs the evaluation pass at most 1/s
		void Drive();
		void Tick_Impl(double a_nowSec); // the single scheduler tick

		static constexpr std::uint32_t kRecordType = 'TMRS';
		static constexpr std::uint32_t kSchemaVersion = 1;
		std::vector<std::uint8_t> Save();
		bool Load(std::uint32_t a_length, const std::uint8_t* a_data);
		void Revert();

		mutable std::recursive_mutex m_mutex;

	private:
		Scheduler() = default;

		std::unordered_map<std::string, TimerRule> m_rules; // moduleID \x1f ruleID -> rule
		std::chrono::steady_clock::time_point m_lastTick{};
		bool m_ticked = false;
	};
}
