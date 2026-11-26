#pragma once
// Downed -- DeDService's DeD Downed state service (A3b leg 1; spec docs/specs/ded-downed-a2-spec.md sections 2, 5, 6).
// Per-actor phase (None / Downed / Recovering) + flags (Restrained, NonViolent, Robbed list), phase timers stored as
// seconds remaining, the aggressor, a ref-counted scene pacify (never saved). Cosave record DWND v1. Events go out as
// ModEvents on the game thread. Inert without the DeD Downed module: nothing ticks, no hooks (those live in
// DeDDowned.dll); Baka's own downs still write and read here. Exported to other DLLs through DeDDowned_API.h.
// ASCII only.

#include <cstdint>
#include <atomic>
#include <mutex>
#include <string>
#include <unordered_map>
#include <vector>

#include "DeDDowned_API.h"

namespace DeD
{
	class Downed
	{
	public:
		using Phase = DeDDowned::Phase;

		static Downed& GetSingleton();

		// reads
		Phase GetPhase(std::uint32_t a_actor) const;
		bool IsDowned(std::uint32_t a_actor) const;
		bool IsPacified(std::uint32_t a_actor) const;
		float GetTimeLeft(std::uint32_t a_actor) const;
		std::uint32_t GetAggressor(std::uint32_t a_actor) const;
		bool IsRestrained(std::uint32_t a_actor) const;
		bool IsNonViolent(std::uint32_t a_actor) const;
		std::vector<std::uint32_t> ListDowned() const;
		std::vector<std::uint32_t> ListPacified() const;
		// S342 (D-A58): hooks installed AND Acheron absent or switched off.
		bool ModuleArmed() const { return m_armed.load() && m_acheron.load() != kAcheronOn; }
		void SetAcheronPresent(bool a_present);
		void SetAcheronProcessing(bool a_processing);   // DeD_MCM, each reload

		// A4 leg 3 (S344): the downed menu's helpers (spec D-A46 / D-A47 / D-A50, section 10)
		int HelpUpHealing(std::uint32_t a_helper, bool a_consume, std::string* a_used = nullptr);
		std::string LastHealingUsed() const;
		RE::TESIdleForm* KillMoveFor(RE::Actor* a_caster);
		void AllowTalk(std::uint32_t a_actor);
		bool ConsumeTalkPass(std::uint32_t a_actor);

		// writes
		bool DownActor(std::uint32_t a_victim, std::uint32_t a_aggressor, const std::string& a_reason);
		bool Recover(std::uint32_t a_actor, bool a_fullRescue);
		bool Release(std::uint32_t a_actor);
		void ScenePacifyBegin(std::uint32_t a_actor);
		void ScenePacifyEnd(std::uint32_t a_actor);
		void SetRestrained(std::uint32_t a_actor, bool a_on, const std::string& a_source, float a_gameHours = 0.0f);
		std::string RestrainedSource(std::uint32_t a_actor) const;
		bool ResetDowned(std::uint32_t a_actor, const std::string& a_why);   // S349 (D-A53)
		void AddRobbed(std::uint32_t a_actor, const std::string& a_line);    // S349 (spec 9)
		void SetNonViolent(std::uint32_t a_actor, bool a_on);

		// module side
		void SetModuleArmed(bool a_armed);
		void Tick(float a_delta);
		void SetDurations(float a_downed, float a_pacified);
		void TimeSkipClear(const std::string& a_why);
		float GetSetting(const std::string& a_key, float a_default) const;
		void SetSetting(const std::string& a_key, float a_value);
		bool IsMigrated() const;
		void SetMigrated();

		// cosave (record DWND)
		static constexpr std::uint32_t kRecordType = 'DWND';
		static constexpr std::uint32_t kSchemaVersion = 1;
		std::vector<std::uint8_t> Save() const;
		bool Load(SKSE::SerializationInterface* a_intfc, std::uint32_t a_length, const std::uint8_t* a_data);
		void Revert();

		static const DeDDowned::Api1* Api();   // the C ABI table (DeDDowned_RequestApi)

	private:
		struct Row
		{
			Phase phase = Phase::None;
			float left = 0.0f;                 // seconds left in the phase
			std::uint32_t aggressor = 0;
			bool restrained = false;
			std::string restrainedSource;
			float restrainedUntil = 0.0f;      // S349: game days passed when the restraint ends (0 = until freed)
			bool nonViolent = false;
			float origAggression = -1.0f;      // NonViolent undo (spec 7.1); -1 = not stored
			std::int32_t origRelationship = -99;
			std::vector<std::string> robbed;   // player only (spec 9)
			std::int32_t sceneRefs = 0;        // scene pacify ref count; never saved
			bool expiryHeld = false;           // a timer ran out during a scene; applied at ScenePacifyEnd
		};

		bool Empty(const Row& a_row) const;
		void EraseIfEmpty(std::uint32_t a_actor);
		void Advance(std::uint32_t a_actor, Row& a_row, std::vector<std::pair<std::string, std::uint32_t>>& a_events);
		static void Send(const char* a_event, std::uint32_t a_actor, const std::string& a_str);

		mutable std::mutex m_mx;
		std::unordered_map<std::uint32_t, Row> m_rows;
		float m_downedSeconds = 300.0f;
		float m_pacifiedSeconds = 300.0f;
		static constexpr int kAcheronAbsent = 0, kAcheronOn = 1, kAcheronOff = 2;
		std::atomic<bool> m_armed{ false };              // the module's hooks are installed
		std::atomic<int>  m_acheron{ kAcheronAbsent };   // present = On until DeD_MCM reports its toggle
		std::unordered_map<std::string, float> m_settings;   // the module's settings (saved in DWND)
		bool m_migrated = false;                             // spec 14 one-shot (saved in DWND)
		std::string m_lastHealing;                           // S344: what the last Help Up used (for the notice)
		std::atomic<std::uint32_t> m_talkPass{ 0 };          // S344: one activation that opens dialogue
	};
}
