// Downed -- see Downed.h. DeD Downed A3b leg 1 (S338).
#include "PCH.h"
#include "Downed.h"

#include "EventPump.h"

#include <algorithm>
#include <string_view>
#include <cstring>

namespace DeD
{
	namespace
	{
		const char* PhaseName(DeDDowned::Phase a_p)
		{
			switch (a_p) {
			case DeDDowned::Phase::Downed:     return "Downed";
			case DeDDowned::Phase::Recovering: return "Recovering";
			default:                           return "None";
			}
		}

		std::string Who(std::uint32_t a_id)
		{
			auto* form = a_id ? RE::TESForm::LookupByID(a_id) : nullptr;
			auto* ref = form ? form->As<RE::TESObjectREFR>() : nullptr;
			const char* n = ref ? ref->GetDisplayFullName() : nullptr;
			return std::format("{} ({:08X})", (n && *n) ? n : "?", a_id);
		}

		// little-endian writer / reader for the DWND record
		template <class T>
		void Put(std::vector<std::uint8_t>& a_buf, T a_v)
		{
			const auto* p = reinterpret_cast<const std::uint8_t*>(&a_v);
			a_buf.insert(a_buf.end(), p, p + sizeof(T));
		}
		void PutStr(std::vector<std::uint8_t>& a_buf, const std::string& a_s)
		{
			const auto n = static_cast<std::uint16_t>(std::min<std::size_t>(a_s.size(), 0xFFFF));
			Put(a_buf, n);
			a_buf.insert(a_buf.end(), a_s.begin(), a_s.begin() + n);
		}
		template <class T>
		bool Get(const std::uint8_t*& a_p, const std::uint8_t* a_end, T& a_v)
		{
			if (a_end - a_p < static_cast<std::ptrdiff_t>(sizeof(T))) return false;
			std::memcpy(&a_v, a_p, sizeof(T));
			a_p += sizeof(T);
			return true;
		}
		bool GetStr(const std::uint8_t*& a_p, const std::uint8_t* a_end, std::string& a_s)
		{
			std::uint16_t n = 0;
			if (!Get(a_p, a_end, n) || a_end - a_p < n) return false;
			a_s.assign(reinterpret_cast<const char*>(a_p), n);
			a_p += n;
			return true;
		}
	}

	float DaysPassed()
	{
		auto* cal = RE::Calendar::GetSingleton();
		return (cal && cal->gameDaysPassed) ? cal->gameDaysPassed->value : 0.0f;
	}

	Downed& Downed::GetSingleton()
	{
		static Downed instance;
		return instance;
	}

	// ---------------------------------------------------------------- reads
	Downed::Phase Downed::GetPhase(std::uint32_t a_actor) const
	{
		std::lock_guard lk(m_mx);
		const auto it = m_rows.find(a_actor);
		return it == m_rows.end() ? Phase::None : it->second.phase;
	}

	bool Downed::IsDowned(std::uint32_t a_actor) const { return GetPhase(a_actor) == Phase::Downed; }

	bool Downed::IsPacified(std::uint32_t a_actor) const
	{
		std::lock_guard lk(m_mx);
		const auto it = m_rows.find(a_actor);
		if (it == m_rows.end()) return false;
		const auto& r = it->second;
		return r.phase != Phase::None || r.restrained || r.sceneRefs > 0;
	}

	float Downed::GetTimeLeft(std::uint32_t a_actor) const
	{
		std::lock_guard lk(m_mx);
		const auto it = m_rows.find(a_actor);
		return it == m_rows.end() || it->second.phase == Phase::None ? 0.0f : std::max(0.0f, it->second.left);
	}

	std::uint32_t Downed::GetAggressor(std::uint32_t a_actor) const
	{
		std::lock_guard lk(m_mx);
		const auto it = m_rows.find(a_actor);
		return it == m_rows.end() ? 0 : it->second.aggressor;
	}

	bool Downed::IsRestrained(std::uint32_t a_actor) const
	{
		std::lock_guard lk(m_mx);
		const auto it = m_rows.find(a_actor);
		return it != m_rows.end() && it->second.restrained;
	}

	bool Downed::IsNonViolent(std::uint32_t a_actor) const
	{
		std::lock_guard lk(m_mx);
		const auto it = m_rows.find(a_actor);
		return it != m_rows.end() && it->second.nonViolent;
	}

	std::vector<std::uint32_t> Downed::ListDowned() const
	{
		std::lock_guard lk(m_mx);
		std::vector<std::uint32_t> out;
		for (const auto& [id, r] : m_rows)
			if (r.phase == Phase::Downed) out.push_back(id);
		return out;
	}

	std::vector<std::uint32_t> Downed::ListPacified() const
	{
		std::lock_guard lk(m_mx);
		std::vector<std::uint32_t> out;
		for (const auto& [id, r] : m_rows)
			if (r.phase != Phase::None || r.restrained || r.sceneRefs > 0) out.push_back(id);
		return out;
	}

	// ---------------------------------------------------------------- helpers
	bool Downed::Empty(const Row& a_row) const
	{
		return a_row.phase == Phase::None && !a_row.restrained && !a_row.nonViolent && a_row.robbed.empty() &&
		       a_row.sceneRefs <= 0;
	}

	void Downed::EraseIfEmpty(std::uint32_t a_actor)
	{
		const auto it = m_rows.find(a_actor);
		if (it != m_rows.end() && Empty(it->second)) m_rows.erase(it);
	}

	void Downed::Send(const char* a_event, std::uint32_t a_actor, const std::string& a_str)
	{
		std::string name = a_event, str = a_str;
		SKSE::GetTaskInterface()->AddTask([name, a_actor, str]() {
			EventPump::Emit(name, RE::TESForm::LookupByID(a_actor), 0.0f, str);
		});
	}

	// A phase timer ran out (or a held expiry is applied). Caller holds m_mx; events are queued, sent after unlock.
	void Downed::Advance(std::uint32_t a_actor, Row& a_row, std::vector<std::pair<std::string, std::uint32_t>>& a_events)
	{
		if (a_row.sceneRefs > 0) {
			if (!a_row.expiryHeld) SKSE::log::info("[DeDService][DOWNED] {} timer ran out mid-scene -- held until the scene ends.", Who(a_actor));
			a_row.expiryHeld = true;
			a_row.left = 0.0f;
			return;
		}
		a_row.expiryHeld = false;
		if (a_row.phase == Phase::Downed) {
			a_row.phase = Phase::Recovering;
			a_row.left = m_pacifiedSeconds;
			SKSE::log::info("[DeDService][DOWNED] RECOVER {} -> Recovering (timer), pacified {:.0f} s.", Who(a_actor), a_row.left);
			a_events.emplace_back("DeD_Recovering|timer", a_actor);
		} else if (a_row.phase == Phase::Recovering) {
			a_row.phase = Phase::None;
			a_row.left = 0.0f;
			SKSE::log::info("[DeDService][DOWNED] PACIFY-END {} -> None (timer).", Who(a_actor));
			a_events.emplace_back("DeD_Recovered|timer", a_actor);
			a_events.emplace_back("DeD_PacifyEnded|timer", a_actor);
		}
	}

	// ---------------------------------------------------------------- writes
	bool Downed::DownActor(std::uint32_t a_victim, std::uint32_t a_aggressor, const std::string& a_reason)
	{
		auto* actor = a_victim ? RE::TESForm::LookupByID<RE::Actor>(a_victim) : nullptr;
		if (!actor || actor->IsDead()) {
			SKSE::log::info("[DeDService][DOWNED] DOWN refused: {} is {} (reason {}).", Who(a_victim), actor ? "dead" : "not an actor", a_reason);
			return false;
		}
		{
			std::lock_guard lk(m_mx);
			auto& r = m_rows[a_victim];
			const bool again = r.phase == Phase::Downed;
			r.phase = Phase::Downed;
			r.left = m_downedSeconds;
			r.expiryHeld = false;
			if (a_aggressor) r.aggressor = a_aggressor;
			SKSE::log::info("[DeDService][DOWNED] DOWN {} by {} reason={}{} -- {:.0f} s.", Who(a_victim), Who(a_aggressor), a_reason,
				again ? " (already downed: timer reset)" : "", r.left);
		}
		Send("DeD_Downed", a_victim, a_reason);
		return true;
	}

	bool Downed::Recover(std::uint32_t a_actor, bool a_fullRescue)
	{
		std::string ev;
		{
			std::lock_guard lk(m_mx);
			const auto it = m_rows.find(a_actor);
			if (it == m_rows.end() || it->second.phase == Phase::None) return false;
			auto& r = it->second;
			r.expiryHeld = false;
			if (a_fullRescue) {
				r.phase = Phase::None;
				r.left = 0.0f;
				ev = "DeD_Recovered";
				SKSE::log::info("[DeDService][DOWNED] RECOVER {} -> None (full rescue).", Who(a_actor));
				EraseIfEmpty(a_actor);
			} else if (r.phase == Phase::Downed) {
				r.phase = Phase::Recovering;
				r.left = m_pacifiedSeconds;
				ev = "DeD_Recovering";
				SKSE::log::info("[DeDService][DOWNED] RECOVER {} -> Recovering (helped up), pacified {:.0f} s.", Who(a_actor), r.left);
			} else {
				return false;   // already Recovering
			}
		}
		Send(ev.c_str(), a_actor, a_fullRescue ? "rescue" : "recover");
		return true;
	}

	bool Downed::Release(std::uint32_t a_actor)
	{
		bool was = false;
		{
			std::lock_guard lk(m_mx);
			const auto it = m_rows.find(a_actor);
			if (it == m_rows.end()) return false;
			auto& r = it->second;
			was = r.phase != Phase::None || r.sceneRefs > 0;
			r.phase = Phase::None;
			r.left = 0.0f;
			r.sceneRefs = 0;
			r.expiryHeld = false;
			SKSE::log::info("[DeDService][DOWNED] RELEASE {} (every temporary state cleared).", Who(a_actor));
			EraseIfEmpty(a_actor);
		}
		if (was) Send("DeD_Recovered", a_actor, "release");
		return was;
	}

	void Downed::ScenePacifyBegin(std::uint32_t a_actor)
	{
		std::lock_guard lk(m_mx);
		auto& r = m_rows[a_actor];
		++r.sceneRefs;
		SKSE::log::info("[DeDService][DOWNED] SCENE-PACIFY begin {} (refs {}).", Who(a_actor), r.sceneRefs);
	}

	void Downed::ScenePacifyEnd(std::uint32_t a_actor)
	{
		std::vector<std::pair<std::string, std::uint32_t>> events;
		{
			std::lock_guard lk(m_mx);
			const auto it = m_rows.find(a_actor);
			if (it == m_rows.end() || it->second.sceneRefs <= 0) return;
			auto& r = it->second;
			--r.sceneRefs;
			SKSE::log::info("[DeDService][DOWNED] SCENE-PACIFY end {} (refs {}{}).", Who(a_actor), r.sceneRefs,
				r.sceneRefs == 0 && r.expiryHeld ? ", applying the held expiry" : "");
			if (r.sceneRefs == 0 && r.expiryHeld) Advance(a_actor, r, events);
			EraseIfEmpty(a_actor);
		}
		for (const auto& [e, id] : events) {
			const auto bar = e.find('|');
			Send(e.substr(0, bar).c_str(), id, e.substr(bar + 1));
		}
	}

	void Downed::SetRestrained(std::uint32_t a_actor, bool a_on, const std::string& a_source, float a_gameHours)
	{
		std::string was;
		{
			std::lock_guard lk(m_mx);
			auto& r = m_rows[a_actor];
			if (r.restrained == a_on && (!a_on || r.restrainedSource == a_source)) {
				if (a_on && a_gameHours > 0.0f) r.restrainedUntil = DaysPassed() + a_gameHours / 24.0f;
				EraseIfEmpty(a_actor);
				return;
			}
			was = r.restrainedSource;
			r.restrained = a_on;
			r.restrainedSource = a_on ? a_source : "";
			r.restrainedUntil = (a_on && a_gameHours > 0.0f) ? DaysPassed() + a_gameHours / 24.0f : 0.0f;
			SKSE::log::info("[DeDService][DOWNED] {} {} (source {}{}).", a_on ? "RESTRAINED" : "FREED", Who(a_actor),
				a_on ? a_source : was, a_on && a_gameHours > 0.0f ? std::format(", {:.1f} game h", a_gameHours) : std::string());
			EraseIfEmpty(a_actor);
		}
		Send("DeD_RestraintChanged", a_actor, std::string(a_on ? "on:" : "off:") + (a_on ? a_source : (a_source.empty() ? was : a_source)));
	}

	std::string Downed::RestrainedSource(std::uint32_t a_actor) const
	{
		std::lock_guard lk(m_mx);
		const auto it = m_rows.find(a_actor);
		return (it != m_rows.end() && it->second.restrained) ? it->second.restrainedSource : std::string();
	}

	// S349 (D-A53): an assault on a downed / recovering actor puts them back at the start of Downed.
	bool Downed::ResetDowned(std::uint32_t a_actor, const std::string& a_why)
	{
		{
			std::lock_guard lk(m_mx);
			const auto it = m_rows.find(a_actor);
			if (it == m_rows.end() || it->second.phase == Phase::None) return false;
			auto& r = it->second;
			const bool wasRec = r.phase == Phase::Recovering;
			r.phase = Phase::Downed;
			r.left = m_downedSeconds;
			r.expiryHeld = false;
			SKSE::log::info("[DeDService][DOWNED] RESET {} -> Downed{} ({}), full timer {:.0f} s (D-A53).", Who(a_actor),
				wasRec ? " from Recovering" : "", a_why, r.left);
		}
		Send("DeD_Downed", a_actor, "reset:" + a_why);
		return true;
	}

	void Downed::AddRobbed(std::uint32_t a_actor, const std::string& a_line)
	{
		std::lock_guard lk(m_mx);
		auto& r = m_rows[a_actor];
		r.robbed.push_back(a_line);
		if (r.robbed.size() > 20) r.robbed.erase(r.robbed.begin());
		SKSE::log::info("[DeDService][DOWNED] ROBBED {}: {}", Who(a_actor), a_line);
	}

	// S352 (spec 7.1, D-A20): Papyrus Actor.SetRelationshipRank(player, rank) (no C++ setter in CommonLib)
	void SetRankWithPlayer(RE::Actor* a_actor, std::int32_t a_rank)
	{
		auto* vm = RE::BSScript::Internal::VirtualMachine::GetSingleton();
		auto* pc = RE::PlayerCharacter::GetSingleton();
		if (!vm || !a_actor || !pc) return;
		auto* policy = vm->GetObjectHandlePolicy();
		const auto handle = policy ? policy->GetHandleForObject(static_cast<RE::VMTypeID>(RE::Actor::FORMTYPE), a_actor) : 0;
		if (!handle) return;
		RE::BSTSmartPointer<RE::BSScript::IStackCallbackFunctor> cb;
		auto* args = RE::MakeFunctionArguments(static_cast<RE::Actor*>(pc), std::move(a_rank));
		vm->DispatchMethodCall2(handle, "Actor", "SetRelationshipRank", args, cb);
		delete args;
	}

	// Papyrus rank of the actor toward the player (4 lover .. 0 acquaintance .. -4 archnemesis); 0 without a record
	std::int32_t RankWithPlayer(RE::Actor* a_actor)
	{
		auto* pc = RE::PlayerCharacter::GetSingleton();
		auto* a = a_actor ? a_actor->GetActorBase() : nullptr;
		auto* p = pc ? pc->GetActorBase() : nullptr;
		auto* rel = (a && p) ? RE::BGSRelationship::GetRelationship(a, p) : nullptr;
		return rel ? 4 - static_cast<std::int32_t>(rel->level.underlying()) : 0;
	}

	void Downed::SetNonViolent(std::uint32_t a_actor, bool a_on)
	{
		auto* actor = RE::TESForm::LookupByID<RE::Actor>(a_actor);
		float restoreAggr = -1.0f;
		std::int32_t restoreRank = -99;
		{
			std::lock_guard lk(m_mx);
			auto& r = m_rows[a_actor];
			if (r.nonViolent == a_on) {
				EraseIfEmpty(a_actor);
				return;
			}
			r.nonViolent = a_on;
			if (actor && a_on) {   // S352 (D-A20): stand down; the originals kept for the undo
				auto* av = actor->AsActorValueOwner();
				r.origAggression = av->GetBaseActorValue(RE::ActorValue::kAggression);
				r.origRelationship = RankWithPlayer(actor);
				av->SetBaseActorValue(RE::ActorValue::kAggression, 0.0f);
			} else if (!a_on) {
				restoreAggr = r.origAggression;
				restoreRank = r.origRelationship;
				r.origAggression = -1.0f;
				r.origRelationship = -99;
			}
			SKSE::log::info("[DeDService][DOWNED] NONVIOLENT {} = {}{}.", Who(a_actor), a_on,
				a_on ? std::format(" (aggression was {:.0f}, rank with the player {})", r.origAggression, r.origRelationship) : std::string());
			EraseIfEmpty(a_actor);
		}
		if (!actor) return;
		if (a_on) {
			if (RankWithPlayer(actor) < 0) SetRankWithPlayer(actor, 0);
			actor->StopCombat();
		} else {
			if (restoreAggr >= 0.0f) actor->AsActorValueOwner()->SetBaseActorValue(RE::ActorValue::kAggression, restoreAggr);
			if (restoreRank != -99 && restoreRank < 0) SetRankWithPlayer(actor, restoreRank);
		}
	}

	// ---------------------------------------------------------------- module side
	void Downed::SetModuleArmed(bool a_armed)
	{
		m_armed = a_armed;
		SKSE::log::info("[DeDService][DOWNED] module hooks {}.", a_armed ? "installed" : "absent");
	}

	void Downed::SetAcheronPresent(bool a_present)
	{
		m_acheron = a_present ? kAcheronOn : kAcheronAbsent;
		SKSE::log::info("[DeDService][DOWNED] Acheron {} -- DeD Downed {}.", a_present ? "installed" : "absent",
			a_present ? "waits for Acheron's Enabled toggle (reported by DeD_MCM each reload)" : "may act");
	}

	void Downed::SetAcheronProcessing(bool a_processing)
	{
		if (m_acheron.load() == kAcheronAbsent) return;
		m_acheron = a_processing ? kAcheronOn : kAcheronOff;
		SKSE::log::info("[DeDService][DOWNED] Acheron's Enabled toggle is {} -- DeD Downed {}.", a_processing ? "ON" : "OFF",
			ModuleArmed() ? "ACTIVE" : "off");
	}

	void Downed::Tick(float a_delta)
	{
		if (a_delta <= 0.0f) return;
		std::vector<std::pair<std::string, std::uint32_t>> events;
		{
			std::lock_guard lk(m_mx);
			std::vector<std::uint32_t> empty;
			const float days = DaysPassed();
			for (auto& [id, r] : m_rows) {
				if (r.restrained && r.restrainedUntil > 0.0f && days >= r.restrainedUntil) {   // S349
					SKSE::log::info("[DeDService][DOWNED] FREED {} (restraint time over, source {}).", Who(id), r.restrainedSource);
					events.emplace_back("DeD_RestraintChanged|off:expired:" + r.restrainedSource, id);
					r.restrained = false;
					r.restrainedSource.clear();
					r.restrainedUntil = 0.0f;
				}
				if (r.phase == Phase::None || r.expiryHeld) {
					if (Empty(r)) empty.push_back(id);
					continue;
				}
				if (r.restrained && r.restrainedSource == "baka_tie" && r.phase == Phase::Downed) continue;   // S349: tied down
				r.left -= a_delta;
				if (r.left <= 0.0f) Advance(id, r, events);
				if (Empty(r)) empty.push_back(id);
			}
			for (const auto id : empty) m_rows.erase(id);
		}
		for (const auto& [e, id] : events) {
			const auto bar = e.find('|');
			Send(e.substr(0, bar).c_str(), id, e.substr(bar + 1));
		}
	}

	void Downed::SetDurations(float a_downed, float a_pacified)
	{
		std::lock_guard lk(m_mx);
		m_downedSeconds = std::max(1.0f, a_downed);
		m_pacifiedSeconds = std::max(0.0f, a_pacified);
		SKSE::log::info("[DeDService][DOWNED] durations: downed {:.0f} s, pacified {:.0f} s.", m_downedSeconds, m_pacifiedSeconds);
	}

	void Downed::TimeSkipClear(const std::string& a_why)
	{
		std::vector<std::uint32_t> cleared;
		{
			std::lock_guard lk(m_mx);
			for (auto& [id, r] : m_rows) {
				if (r.phase == Phase::None) continue;
				if (r.restrained && r.restrainedSource == "baka_tie") continue;   // S349: a tie ends by its own game time
				r.phase = Phase::None;
				r.left = 0.0f;
				r.expiryHeld = false;
				cleared.push_back(id);
			}
			for (const auto id : cleared) EraseIfEmpty(id);
		}
		SKSE::log::info("[DeDService][DOWNED] TIMESKIP-CLEAR ({}): {} actor(s) back to normal.", a_why, cleared.size());
		for (const auto id : cleared) Send("DeD_TimeSkipCleared", id, a_why);
	}

	float Downed::GetSetting(const std::string& a_key, float a_default) const
	{
		std::lock_guard lk(m_mx);
		const auto it = m_settings.find(a_key);
		return it == m_settings.end() ? a_default : it->second;
	}

	void Downed::SetSetting(const std::string& a_key, float a_value)
	{
		std::lock_guard lk(m_mx);
		m_settings[a_key] = a_value;
		SKSE::log::info("[DeDService][DOWNED] setting {} = {}.", a_key, a_value);
	}

	bool Downed::IsMigrated() const
	{
		std::lock_guard lk(m_mx);
		return m_migrated;
	}

	void Downed::SetMigrated()
	{
		std::lock_guard lk(m_mx);
		m_migrated = true;
	}

	// ---------------------------------------------------------------- A4 leg 3 (S344): the downed menu
	// Help Up in combat (D-A46): the weakest health potion (D-A50: lowest gold value with a Restore Health effect, never
	// food or poison; player-made potions only with "helpup.custompotions"). Healing spells are not a Help Up cost
	// (S345, D-A60): casting one on the downed actor heals them, and DeDDowned.dll recovers them above 30% health.
	int Downed::HelpUpHealing(std::uint32_t a_helper, bool a_consume, std::string* a_used)
	{
		auto* actor = a_helper ? RE::TESForm::LookupByID<RE::Actor>(a_helper) : nullptr;
		if (!actor) return 0;
		const bool allowCustom = GetSetting("helpup.custompotions", 0.0f) >= 0.5f;
		RE::AlchemyItem* best = nullptr;
		std::int32_t bestValue = 0;
		const auto inv = actor->GetInventoryCounts([](RE::TESBoundObject& a_obj) { return a_obj.GetFormType() == RE::FormType::AlchemyItem; });
		for (const auto& [obj, count] : inv) {
			auto* alch = obj ? obj->As<RE::AlchemyItem>() : nullptr;
			if (!alch || count <= 0 || alch->IsFood() || alch->IsPoison()) continue;
			if (!allowCustom && (alch->GetFormID() >> 24) == 0xFF) continue;
			bool heals = false;
			for (auto* e : alch->effects)
				if (e && e->baseEffect && e->baseEffect->HasKeywordString("MagicAlchRestoreHealth")) heals = true;
			if (!heals) continue;
			const auto value = alch->GetGoldValue();
			if (!best || value < bestValue) {
				best = alch;
				bestValue = value;
			}
		}
		if (best) {
			const std::string name = best->GetName();
			if (a_used) *a_used = name;
			if (a_consume) {
				{
					std::lock_guard lk(m_mx);
					m_lastHealing = name;
				}
				const auto actorId = a_helper;
				const auto itemId = best->GetFormID();
				SKSE::GetTaskInterface()->AddTask([actorId, itemId]() {
					auto* a = RE::TESForm::LookupByID<RE::Actor>(actorId);
					auto* item = RE::TESForm::LookupByID<RE::AlchemyItem>(itemId);
					if (a && item) a->RemoveItem(item, 1, RE::ITEM_REMOVE_REASON::kRemove, nullptr, nullptr);
				});
				SKSE::log::info("[DeDService][DOWNED] HELPUP-COST {} used the potion '{}' (value {}).", Who(a_helper), name, bestValue);
			}
			return 1;
		}
		// S345 (user, D-A60): no spell path here. A healing spell heals the downed actor for real; DeDDowned.dll
		// recovers them once their health passes 30%.
		return 0;
	}

	std::string Downed::LastHealingUsed() const
	{
		std::lock_guard lk(m_mx);
		return m_lastHealing;
	}

	// Execute (spec 10): a vanilla kill move on a target on the ground that fits the caster's weapon (A3a list); none for
	// bows, staffs, magic and fists (a plain kill), or when the "execute.anims" setting is off.
	RE::TESIdleForm* Downed::KillMoveFor(RE::Actor* a_caster)
	{
		if (!a_caster || GetSetting("execute.anims", 1.0f) < 0.5f) return nullptr;
		auto* weap = a_caster->GetEquippedObject(false);
		auto* w = weap ? weap->As<RE::TESObjectWEAP>() : nullptr;
		if (!w) return nullptr;
		const char* want = nullptr;
		switch (w->GetWeaponType()) {
		case RE::WEAPON_TYPE::kOneHandSword:
		case RE::WEAPON_TYPE::kOneHandAxe:    want = "1HMKillingBlowBleedOutDecap"; break;
		case RE::WEAPON_TYPE::kOneHandDagger:
		case RE::WEAPON_TYPE::kOneHandMace:   want = "1HMKillingBlowBleedOut"; break;
		case RE::WEAPON_TYPE::kTwoHandSword:  want = "KillMove2HMDecapBleedOut"; break;
		case RE::WEAPON_TYPE::kTwoHandAxe:    want = "KillMove2HWDecapBleedOut"; break;
		default: return nullptr;
		}
		static std::unordered_map<std::string, RE::TESIdleForm*> cache;
		static std::mutex cacheMx;
		std::lock_guard lk(cacheMx);
		if (cache.empty()) {
			const auto& [map, lock] = RE::TESForm::GetAllForms();
			[[maybe_unused]] const RE::BSReadLockGuard guard{ lock };
			if (map) {
				for (auto& [id, form] : *map) {
					if (!form || form->GetFormType() != RE::FormType::Idle) continue;
					auto* idle = static_cast<RE::TESIdleForm*>(form);
					const char* ed = idle->formEditorID.c_str();
					if (!ed) continue;
					const std::string_view e = ed;
					if (e == "1HMKillingBlowBleedOutDecap" || e == "1HMKillingBlowBleedOut" || e == "KillMove2HMDecapBleedOut" ||
						e == "KillMove2HWDecapBleedOut")
						cache.emplace(std::string(e), idle);
				}
			}
			SKSE::log::info("[DeDService][DOWNED] kill moves found: {} of 4.", cache.size());
		}
		const auto it = cache.find(want);
		return it == cache.end() ? nullptr : it->second;
	}

	void Downed::AllowTalk(std::uint32_t a_actor)
	{
		m_talkPass = a_actor;
		SKSE::log::info("[DeDService][DOWNED] TALK pass for {}.", Who(a_actor));
	}

	bool Downed::ConsumeTalkPass(std::uint32_t a_actor)
	{
		std::uint32_t expected = a_actor;
		return a_actor && m_talkPass.compare_exchange_strong(expected, 0);
	}

	// ---------------------------------------------------------------- cosave (DWND v1)
	// u8 reserved; u32 count; per row: u32 formId, u8 phase, f32 left, u32 aggressor, u8 flags (1 restrained,
	// 2 nonViolent), str restrainedSource, f32 origAggression, i32 origRelationship, u16 robbedCount, str robbed[].
	std::vector<std::uint8_t> Downed::Save() const
	{
		std::lock_guard lk(m_mx);
		std::vector<std::uint8_t> buf;
		Put<std::uint8_t>(buf, m_migrated ? 1 : 0);   // flags: bit 0 = Acheron migration done (spec 14)
		std::uint32_t count = 0;
		for (const auto& [id, r] : m_rows)
			if (!Empty(r) || r.phase != Phase::None) ++count;
		Put(buf, count);
		for (const auto& [id, r] : m_rows) {
			if (Empty(r) && r.phase == Phase::None) continue;
			Put(buf, id);
			Put(buf, static_cast<std::uint8_t>(r.phase));
			Put(buf, r.left);
			Put(buf, r.aggressor);
			Put(buf, static_cast<std::uint8_t>((r.restrained ? 1 : 0) | (r.nonViolent ? 2 : 0)));
			PutStr(buf, r.restrainedSource);
			Put(buf, r.origAggression);
			Put(buf, r.origRelationship);
			Put(buf, static_cast<std::uint16_t>(r.robbed.size()));
			for (const auto& s : r.robbed) PutStr(buf, s);
		}
		// leg 3 (S340): the module's settings, appended (u16 count, then str key + f32 value)
		Put(buf, static_cast<std::uint16_t>(m_settings.size()));
		for (const auto& [k, v] : m_settings) {
			PutStr(buf, k);
			Put(buf, v);
		}
		// S349: restraint end times (u16 count, then u32 formId + f32 game days)
		std::vector<std::pair<std::uint32_t, float>> ends;
		for (const auto& [id, r] : m_rows)
			if (r.restrained && r.restrainedUntil > 0.0f) ends.emplace_back(id, r.restrainedUntil);
		Put(buf, static_cast<std::uint16_t>(ends.size()));
		for (const auto& [id, d] : ends) {
			Put(buf, id);
			Put(buf, d);
		}
		SKSE::log::info("[DeDService][DOWNED] DWND save: {} row(s).", count);
		return buf;
	}

	bool Downed::Load(SKSE::SerializationInterface* a_intfc, std::uint32_t a_length, const std::uint8_t* a_data)
	{
		std::lock_guard lk(m_mx);
		m_rows.clear();
		const std::uint8_t* p = a_data;
		const std::uint8_t* end = a_data + a_length;
		std::uint8_t reserved = 0;
		std::uint32_t count = 0;
		if (!Get(p, end, reserved) || !Get(p, end, count)) return false;
		m_migrated = (reserved & 1) != 0;
		m_settings.clear();
		std::uint32_t kept = 0, dropped = 0;
		for (std::uint32_t i = 0; i < count; ++i) {
			std::uint32_t id = 0, aggr = 0;
			std::uint8_t phase = 0, flags = 0;
			Row r;
			std::uint16_t nRob = 0;
			if (!Get(p, end, id) || !Get(p, end, phase) || !Get(p, end, r.left) || !Get(p, end, aggr) || !Get(p, end, flags) ||
				!GetStr(p, end, r.restrainedSource) || !Get(p, end, r.origAggression) || !Get(p, end, r.origRelationship) ||
				!Get(p, end, nRob))
				return false;
			for (std::uint16_t k = 0; k < nRob; ++k) {
				std::string s;
				if (!GetStr(p, end, s)) return false;
				r.robbed.push_back(std::move(s));
			}
			r.phase = phase <= 2 ? static_cast<Phase>(phase) : Phase::None;
			r.restrained = (flags & 1) != 0;
			r.nonViolent = (flags & 2) != 0;
			std::uint32_t newId = 0, newAggr = 0;
			if (!a_intfc->ResolveFormID(id, newId)) {
				SKSE::log::info("[DeDService][DOWNED] LOAD-DROP {:08X}: its plugin is gone.", id);
				++dropped;
				continue;
			}
			if (aggr && a_intfc->ResolveFormID(aggr, newAggr)) r.aggressor = newAggr;
			auto* actor = RE::TESForm::LookupByID<RE::Actor>(newId);
			if (!actor || actor->IsDead()) {
				SKSE::log::info("[DeDService][DOWNED] LOAD-DROP {}: {}.", Who(newId), actor ? "dead" : "not an actor");
				++dropped;
				continue;
			}
			SKSE::log::info("[DeDService][DOWNED] LOAD-RESTORE {}: {} {:.0f} s left{}{}.", Who(newId), PhaseName(r.phase), r.left,
				r.restrained ? ", restrained" : "", r.nonViolent ? ", non-violent" : "");
			m_rows[newId] = std::move(r);
			++kept;
		}
		std::uint16_t nSet = 0;
		if (p < end && Get(p, end, nSet)) {
			for (std::uint16_t k = 0; k < nSet; ++k) {
				std::string key;
				float v = 0.0f;
				if (!GetStr(p, end, key) || !Get(p, end, v)) return false;
				m_settings[key] = v;
			}
		}
		std::uint16_t nEnd = 0;
		if (p < end && Get(p, end, nEnd)) {   // S349
			for (std::uint16_t k = 0; k < nEnd; ++k) {
				std::uint32_t id = 0, newId = 0;
				float d = 0.0f;
				if (!Get(p, end, id) || !Get(p, end, d)) return false;
				if (a_intfc->ResolveFormID(id, newId))
					if (const auto it = m_rows.find(newId); it != m_rows.end()) it->second.restrainedUntil = d;
			}
		}
		SKSE::log::info("[DeDService][DOWNED] DWND load: {} restored, {} dropped, {} setting(s), migrated={}.", kept, dropped,
			m_settings.size(), m_migrated);
		return true;
	}

	void Downed::Revert()
	{
		std::lock_guard lk(m_mx);
		m_rows.clear();
		m_settings.clear();
		m_migrated = false;
	}

	// ---------------------------------------------------------------- C ABI
	namespace
	{
		DeDDowned::Phase A_GetPhase(std::uint32_t a) { return Downed::GetSingleton().GetPhase(a); }
		bool A_IsDowned(std::uint32_t a) { return Downed::GetSingleton().IsDowned(a); }
		bool A_IsPacified(std::uint32_t a) { return Downed::GetSingleton().IsPacified(a); }
		float A_GetTimeLeft(std::uint32_t a) { return Downed::GetSingleton().GetTimeLeft(a); }
		std::uint32_t A_GetAggressor(std::uint32_t a) { return Downed::GetSingleton().GetAggressor(a); }
		bool A_DownActor(std::uint32_t v, std::uint32_t g, const char* r) { return Downed::GetSingleton().DownActor(v, g, r ? r : "api"); }
		bool A_Recover(std::uint32_t a, bool f) { return Downed::GetSingleton().Recover(a, f); }
		bool A_Release(std::uint32_t a) { return Downed::GetSingleton().Release(a); }
		void A_SceneBegin(std::uint32_t a) { Downed::GetSingleton().ScenePacifyBegin(a); }
		void A_SceneEnd(std::uint32_t a) { Downed::GetSingleton().ScenePacifyEnd(a); }
		void A_SetArmed(bool b) { Downed::GetSingleton().SetModuleArmed(b); }
		void A_Tick(float d) { Downed::GetSingleton().Tick(d); }
		void A_SetDurations(float d, float p) { Downed::GetSingleton().SetDurations(d, p); }
		void A_TimeSkip(const char* w) { Downed::GetSingleton().TimeSkipClear(w ? w : "time skip"); }
		float A_GetSetting(const char* k, float d) { return k ? Downed::GetSingleton().GetSetting(k, d) : d; }
		void A_SetSetting(const char* k, float v) { if (k) Downed::GetSingleton().SetSetting(k, v); }
		bool A_IsMigrated() { return Downed::GetSingleton().IsMigrated(); }
		void A_SetMigrated() { Downed::GetSingleton().SetMigrated(); }
		void A_SetAcheronPresent(bool p) { Downed::GetSingleton().SetAcheronPresent(p); }
		bool A_IsModuleActive() { return Downed::GetSingleton().ModuleArmed(); }
		int A_HelpUpHealing(std::uint32_t h, bool c) { return Downed::GetSingleton().HelpUpHealing(h, c); }
		void A_AllowTalk(std::uint32_t a) { Downed::GetSingleton().AllowTalk(a); }
		bool A_ConsumeTalkPass(std::uint32_t a) { return Downed::GetSingleton().ConsumeTalkPass(a); }
		bool A_ResetDowned(std::uint32_t a, const char* w) { return Downed::GetSingleton().ResetDowned(a, w ? w : "api"); }
		void A_SetRestrained(std::uint32_t a, bool on, const char* src, float h) { Downed::GetSingleton().SetRestrained(a, on, src ? src : "", h); }
		bool A_IsRestrained(std::uint32_t a) { return Downed::GetSingleton().IsRestrained(a); }
		void A_GetRestrainedSource(std::uint32_t a, char* buf, std::uint32_t n)
		{
			if (!buf || !n) return;
			const auto s = Downed::GetSingleton().RestrainedSource(a);
			const auto c = std::min<std::size_t>(s.size(), n - 1);
			std::memcpy(buf, s.data(), c);
			buf[c] = 0;
		}
		void A_AddRobbed(std::uint32_t a, const char* l) { if (l) Downed::GetSingleton().AddRobbed(a, l); }
		void A_SetNonViolent(std::uint32_t a, bool on) { Downed::GetSingleton().SetNonViolent(a, on); }
		bool A_IsNonViolent(std::uint32_t a) { return Downed::GetSingleton().IsNonViolent(a); }

		const DeDDowned::Api1 kApi1{
			DeDDowned::kApiVersion1,
			A_GetPhase, A_IsDowned, A_IsPacified, A_GetTimeLeft, A_GetAggressor,
			A_DownActor, A_Recover, A_Release, A_SceneBegin, A_SceneEnd,
			A_SetArmed, A_Tick, A_SetDurations, A_TimeSkip,
			A_GetSetting, A_SetSetting, A_IsMigrated, A_SetMigrated,
			A_SetAcheronPresent, A_IsModuleActive,
			A_HelpUpHealing, A_AllowTalk, A_ConsumeTalkPass,
			A_ResetDowned, A_SetRestrained, A_IsRestrained, A_GetRestrainedSource, A_AddRobbed,
			A_SetNonViolent, A_IsNonViolent
		};
	}

	const DeDDowned::Api1* Downed::Api() { return &kApi1; }
}

extern "C" __declspec(dllexport) const void* DeDDowned_RequestApi(std::uint32_t a_version)
{
	return a_version <= DeDDowned::kApiVersion1 ? DeD::Downed::Api() : nullptr;
}
