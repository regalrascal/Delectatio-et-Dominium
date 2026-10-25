#include "PCH.h"
#include "Scheduler.h"
#include "ServiceState.h"
#include "EventPump.h"

#include <chrono>
#include <cstring>

namespace DeD
{
	// ---------- byte helpers (same wire format as ServiceState) ----------
	static void PutU32(std::vector<std::uint8_t>& b, std::uint32_t v)
	{
		b.push_back(static_cast<std::uint8_t>(v));
		b.push_back(static_cast<std::uint8_t>(v >> 8));
		b.push_back(static_cast<std::uint8_t>(v >> 16));
		b.push_back(static_cast<std::uint8_t>(v >> 24));
	}
	static void PutF32(std::vector<std::uint8_t>& b, float v)
	{
		std::uint32_t u;
		std::memcpy(&u, &v, 4);
		PutU32(b, u);
	}
	static void PutU8(std::vector<std::uint8_t>& b, std::uint8_t v) { b.push_back(v); }
	static void PutStr(std::vector<std::uint8_t>& b, const std::string& s)
	{
		PutU32(b, static_cast<std::uint32_t>(s.size()));
		b.insert(b.end(), s.begin(), s.end());
	}
	static bool GetU32(const std::uint8_t*& p, const std::uint8_t* end, std::uint32_t& v)
	{
		if (end - p < 4) return false;
		v = p[0] | (p[1] << 8) | (p[2] << 16) | (std::uint32_t{ p[3] } << 24);
		p += 4;
		return true;
	}
	static bool GetF32(const std::uint8_t*& p, const std::uint8_t* end, float& v)
	{
		std::uint32_t u = 0;
		if (!GetU32(p, end, u)) return false;
		std::memcpy(&v, &u, 4);
		return true;
	}
	static bool GetStr(const std::uint8_t*& p, const std::uint8_t* end, std::string& s)
	{
		std::uint32_t len = 0;
		if (!GetU32(p, end, len) || static_cast<std::size_t>(end - p) < len) return false;
		s.assign(reinterpret_cast<const char*>(p), len);
		p += len;
		return true;
	}

	static std::string RuleMapKey(const std::string& m, const std::string& r) { return m + '\x1f' + r; }

	// ---------- rule lifecycle ----------
	bool Scheduler::AddRule(const std::string& a_moduleID, const std::string& a_ruleID, float a_cadenceSec,
		std::uint32_t a_predClass, const std::string& a_predKey, std::uint32_t a_predOwnerFormID,
		float a_failsafeSec, const std::string& a_callbackEvent)
	{
		std::lock_guard lock(m_mutex);
		if (a_moduleID.empty() || a_ruleID.empty() || a_cadenceSec <= 0.f) return false;
		if (a_predClass > static_cast<std::uint32_t>(PredicateClass::STATE_BOOL_CHANGED)) return false;
		if (a_callbackEvent.empty()) return false;
		const std::string mk = RuleMapKey(a_moduleID, a_ruleID);
		if (m_rules.count(mk) != 0) return false; // duplicate ruleID
		//  (ambient-chain, second silent link): the Papyrus-side rule arms
		// pass the predicate as the ALREADY-DOTTED family key ("cum.present"), but
		// Tick_Impl reads moduleID + "." + predKey -- the pre-124 read queried the
		// double-prefixed "cum.cum.present", which never matches a registration
		// (Register builds dotted = moduleID + "." + key, ServiceState.cpp L141),
		// so GetAnyTrue failed at its registration lookup and fire=false every
		// tick -- the  dogfood's ambient silence (PROJECT_STATE 136).
		// Canonical normalization HERE, at arm: strip the module prefix if the
		// caller passed a dotted key, so Tick_Impl's moduleID + "." + predKey
		// reconstructs the canonical dotted key on both caller shapes.
		std::string predKey(a_predKey);
		const std::string prefix = std::string(a_moduleID) + ".";
		if (predKey.rfind(prefix, 0) == 0) predKey = predKey.substr(prefix.size());
		TimerRule rule;
		rule.moduleID = a_moduleID;
		rule.ruleID = a_ruleID;
		rule.cadenceSec = a_cadenceSec;
		rule.predClass = static_cast<PredicateClass>(a_predClass);
		rule.predKey = predKey; // normalized (see REV-124 note above)
		rule.predOwnerFormID = a_predOwnerFormID;
		rule.failsafeSec = a_failsafeSec;
		rule.callbackEvent = a_callbackEvent;
		rule.nextDueAge = a_cadenceSec; // first fire one cadence after arm
		m_rules.emplace(mk, std::move(rule));
		return true;
	}

	bool Scheduler::RemoveRule(const std::string& a_moduleID, const std::string& a_ruleID)
	{
		std::lock_guard lock(m_mutex);
		return m_rules.erase(RuleMapKey(a_moduleID, a_ruleID)) > 0;
	}

	// ---------- drive / tick ----------
	// Drive() is called from the input-event sink (see Plugin.cpp): the device
	// manager pumps the sink per frame (quiet frames arrive with an empty
	// list), which gives a main-thread, zero-thread, zero-hook frame callback.
	// The 1/s evaluation throttle makes the exact frame cadence non-critical;
	// idle stalls only delay a due tick, never skip the failsafe bound.
	void Scheduler::Drive()
	{
		const auto now = std::chrono::steady_clock::now();
		if (!m_ticked) {
			m_lastTick = now;
			m_ticked = true;
			return;
		}
		const double dt = std::chrono::duration<double>(now - m_lastTick).count();
		if (dt < 1.0) return; // evaluation pass at most once per second
		m_lastTick = now;
		Tick_Impl(dt);
	}

	void Scheduler::Tick_Impl(double a_dtSec)
	{
		std::lock_guard lock(m_mutex);
		auto& state = ServiceState::GetSingleton();
		std::vector<std::string> expired; // rules to disarm at failsafe

		for (auto& [mk, rule] : m_rules) {
			// Presence gate (spec 1.1): absent-module rules are retained but
			// never age, never fire.
			if (!state.ModuleActive(rule.moduleID)) continue;
			rule.ageSec += a_dtSec;

			// Failsafe lifetime (rule property): at expiry clear the predicate
			// state, emit the expired marker (numArg 1), disarm the rule.
			if (rule.failsafeSec > 0.f && rule.ageSec >= rule.failsafeSec) {
				if (!rule.predKey.empty())
					state.ClearValue(rule.moduleID, rule.predKey, rule.predOwnerFormID);
				EventPump::Emit(rule.callbackEvent, nullptr, 1.f, "");
				SKSE::log::info("[DeDService] rule {}:{} failsafe expired ({} s) -- disarmed",
					rule.moduleID, rule.ruleID, rule.failsafeSec);
				expired.push_back(mk);
				continue;
			}

			// Predicate evaluation (classes 1/2 read the Bool entry).
			bool fire = true;
			if (rule.predClass == PredicateClass::STATE_BOOL_TRUE ||
				rule.predClass == PredicateClass::STATE_BOOL_CHANGED) {
				// : a rule armed with a None predicate owner (predOwnerFormID
				// 0 -- the only shape a boot-time arm can express; the wearer is
				// unknown at arm) reads the WILDCARD: TRUE when any owner's row is
				// Bool TRUE. The pre-123 read was a plain owner-0 lookup, which can
				// never see an actor-keyed write (stored under the actor's formID,
				// ServiceState.cpp Set L195) -- the ambient rule never fired on the
				//  dogfood for exactly this reason (first silent link,
				// PROJECT_STATE 135).
				bool isTrue = false;
				if (rule.predOwnerFormID == 0) {
					isTrue = state.GetAnyTrue(rule.moduleID + "." + rule.predKey);
				} else {
					StateValue v;
					const bool present = state.Get(rule.moduleID + "." + rule.predKey,
						rule.predOwnerFormID, v);
					isTrue = present && v.type == ValueType::Bool && v.b;
				}
				if (rule.predClass == PredicateClass::STATE_BOOL_TRUE) {
					fire = isTrue;
				} else { // CHANGED: edge-triggered False->True
					fire = isTrue && !rule.lastPred;
				}
				//  (ambient plumbing; 10-18 dogfood): APPLICATION-ANCHORED
				// PHASING. The pre-127 grid ran from the rule's ARM (nextDueAge =
				// cadenceSec at AddRule, L89) -- dues kept accruing while the
				// predicate was False, so an application landing mid-grid fired
				// ~instantly (10-18: arm 01:41:22, application 01:43:39 at rule-age
				// 137, dues 60 AND 120 already accrued -> first ambient fire 01:43:40,
				// ONE SECOND after application). Fix: the predicate's RISING EDGE
				// (False->True, both classes -- the class-1 rule previously never
				// latched) re-anchors the rule's whole time base: ageSec = 0,
				// nextDueAge = cadenceSec. First fire lands application + cadence;
				// the failsafe lifetime re-anchors too (a fresh application always
				// gets its full window).
				const bool rising = isTrue && !rule.lastPred;
				rule.lastPred = isTrue;
				if (rising) {
					rule.ageSec = 0.0;
					rule.nextDueAge = rule.cadenceSec;
					SKSE::log::info("[DeDService] rule {}:{} re-anchored on predicate rising edge (application-anchored; REV-127)",
						rule.moduleID, rule.ruleID);
				}
			}

			if (!fire) continue;
			if (rule.ageSec >= rule.nextDueAge) {
				EventPump::Emit(rule.callbackEvent, nullptr, 0.f, "");
				// : snap to the LAST ACTUAL FIRE. The pre-127
				// nextDueAge += cadence drained every MISSED due in consecutive
				// 1s-throttled ticks (the 10-18 paired ambient fires 01:43:40/41,
				// 01:45:33/34, 01:47:33/34 -- catch-up bursts, one due per tick
				// until the grid caught up). Missed dues are now SKIPPED, never
				// drained: one fire per cadence from the last actual fire.
				rule.nextDueAge = rule.ageSec + rule.cadenceSec;
			}
		}

		for (const auto& mk : expired) m_rules.erase(mk);
	}

	// ---------- cosave (rule PARAMETERS only; runtime re-arms fresh) ----------
	std::vector<std::uint8_t> Scheduler::Save()
	{
		std::lock_guard lock(m_mutex);
		std::vector<std::uint8_t> buf;
		PutU32(buf, static_cast<std::uint32_t>(m_rules.size()));
		for (const auto& [mk, r] : m_rules) {
			PutStr(buf, r.moduleID);
			PutStr(buf, r.ruleID);
			PutF32(buf, r.cadenceSec);
			PutU8(buf, static_cast<std::uint8_t>(r.predClass));
			PutStr(buf, r.predKey);
			PutU32(buf, r.predOwnerFormID);
			PutF32(buf, r.failsafeSec);
			PutStr(buf, r.callbackEvent);
		}
		return buf;
	}

	bool Scheduler::Load(std::uint32_t a_length, const std::uint8_t* a_data)
	{
		std::lock_guard lock(m_mutex);
		m_rules.clear();
		const std::uint8_t* p = a_data;
		const std::uint8_t* end = a_data + a_length;
		std::uint32_t count = 0;
		if (!GetU32(p, end, count)) return false;
		for (std::uint32_t i = 0; i < count; ++i) {
			TimerRule r;
			std::uint8_t pc = 0;
			if (!GetStr(p, end, r.moduleID) || !GetStr(p, end, r.ruleID) ||
				!GetF32(p, end, r.cadenceSec) || p >= end)
				return false;
			pc = *p++; // predClass byte (Save writes it right after cadence)
			if (!GetStr(p, end, r.predKey) || !GetU32(p, end, r.predOwnerFormID) ||
				!GetF32(p, end, r.failsafeSec) || !GetStr(p, end, r.callbackEvent))
				return false;
			if (pc > static_cast<std::uint8_t>(PredicateClass::STATE_BOOL_CHANGED)) return false;
			r.predClass = static_cast<PredicateClass>(pc);
			r.nextDueAge = r.cadenceSec; // re-arm fresh
			if (r.moduleID.empty() || r.ruleID.empty() || r.cadenceSec <= 0.f || r.callbackEvent.empty())
				continue; // tolerate junk rows, never drop the whole record
			m_rules.emplace(RuleMapKey(r.moduleID, r.ruleID), std::move(r));
		}
		return p == end;
	}

	void Scheduler::Revert()
	{
		std::lock_guard lock(m_mutex);
		m_rules.clear();
		m_ticked = false;
	}
}
