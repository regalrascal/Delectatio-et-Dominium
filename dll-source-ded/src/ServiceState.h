#pragma once

//  -- DeDService state store + cosave handler (spec of record:
// GS docs/features/service-dll.md; design calibrated per its section 0
// SeverActionsNative study -- 4-char record tag + version int, reject-with-log
// on unsupported version, migration hook as a named logged stage).
//
// KEY CONVENTION: state keys are addressed in their FULLY-QUALIFIED dotted
// form "moduleID.key" (e.g. "cum.present" per spec section 3). Registration
// builds the dotted key from (moduleID, key); accessors take it as-is.
//
// PRESENCE (section 1.1): a module is ACTIVE from RegisterState until
// RemoveState / session end. Absent-module entries loaded from a cosave are
// RETAINED as pending rows (dormant: reads fall back to the Papyrus default)
// and are ADOPTED (re-activated) if the module re-registers the same key.
// Retained rows persist back out on save -- the study's retention shape.
// NOTE (v1 build decision, flagged in the spec doc's build notes): the
// spec's "registering FORM" tracking is approximated by session
// registration; the section 1.1 Papyrus signature carries no FormID, so a
// stopped-quest mid-session is covered by the disarm-time contract
// (RemoveState/RemoveTimerRule), not by form polling.

#include <cstdint>
#include <mutex>
#include <string>
#include <unordered_map>
#include <unordered_set>
#include <vector>

#include "SKSE/SKSE.h"

namespace DeD
{
	enum class ValueType : std::uint8_t
	{
		Int = 0,
		Float = 1,
		String = 2,
		Bool = 3,
		FormID = 4
	};

	// Typed payload. One struct for both defaults and live values.
	struct StateValue
	{
		ValueType type = ValueType::Int;
		std::int64_t i = 0;    // Int
		double f = 0.0;         // Float
		std::string s;          // String
		bool b = false;         // Bool
		std::uint32_t form = 0; // FormID
	};

	struct Registration
	{
		std::string moduleID;
		std::string key;
		std::string dotted; // moduleID + "." + key
		ValueType type = ValueType::Int;
		bool actorKeyed = false;
		bool hasDefault = false;
		StateValue defaultValue{};
	};

	// Cosave row: (moduleID, key, ownerFormID, value). Owner 0 = module-global.
	struct PendingRow
	{
		std::string moduleID;
		std::string key;
		std::string dotted;
		std::uint32_t ownerFormID = 0;
		StateValue value{};
	};

	class ServiceState
	{
	public:
		static ServiceState& GetSingleton()
		{
			static ServiceState instance;
			return instance;
		}

		// ---- registration / presence lifecycle (section 1.1) ----
		bool Register(const std::string& a_moduleID, const std::string& a_key,
			ValueType a_type, bool a_actorKeyed, const std::string& a_defaultSerialized);
		bool RemoveState(const std::string& a_moduleID, const std::string& a_key);
		bool ModuleActive(const std::string& a_moduleID) const;

		// ---- state access (section 1.2) ----
		// a_dotted is the fully-qualified key. Returns nullptr when unregistered.
		const Registration* FindRegistration(const std::string& a_dotted) const;
		bool Set(const std::string& a_dotted, std::uint32_t a_ownerFormID, const StateValue& a_value);
		bool Get(const std::string& a_dotted, std::uint32_t a_ownerFormID, StateValue& a_out) const;
		// : wildcard read for timer-rule predicates armed with a None owner
		// (predOwnerFormID 0). For non-actor-keyed keys this is the plain owner-0
		// row read; for actor-keyed keys it is TRUE when ANY owner's row is a
		// Bool TRUE -- the only read shape a boot-time-armed rule can express
		// against actor-keyed state (the wearer is unknown at arm time).
		bool GetAnyTrue(const std::string& a_dotted) const;
		bool HasState(const std::string& a_dotted, std::uint32_t a_ownerFormID) const;
		bool ClearActorState(std::uint32_t a_actorFormID, const std::string& a_moduleID);
		// Predicate-state clear at timer failsafe expiry (spec section 1.3).
		void ClearValue(const std::string& a_moduleID, const std::string& a_key, std::uint32_t a_ownerFormID);

		// ---- cosave (record tag 'STTE', schema v1) ----
		static constexpr std::uint32_t kRecordType = 'STTE';
		static constexpr std::uint32_t kSchemaVersion = 1;
		std::vector<std::uint8_t> Save(); // caller holds m_mutex
		bool Load(SKSE::SerializationInterface* a_intfc, std::uint32_t a_length, const std::uint8_t* a_data);
		void Revert();

		mutable std::recursive_mutex m_mutex;

	private:
		ServiceState() = default;

		std::unordered_map<std::string, Registration> m_registrations; // dotted -> reg
		std::unordered_map<std::string, std::unordered_map<std::uint32_t, StateValue>> m_values; // dotted -> owner -> value
		std::vector<PendingRow> m_pending; // dormant retained rows (cosave adoption path)
		std::unordered_set<std::string> m_activeModules;
	};

	// serialization helpers (shared by Save/Load and the default parser)
	void SerializeValue(std::vector<std::uint8_t>& a_buf, const StateValue& a_v);
	bool DeserializeValue(const std::uint8_t*& a_p, const std::uint8_t* a_end, StateValue& a_v);
	bool ParseDefault(ValueType a_type, const std::string& a_serialized, StateValue& a_out);
}
