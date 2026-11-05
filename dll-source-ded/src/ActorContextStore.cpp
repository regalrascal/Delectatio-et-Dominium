#include "PCH.h"
#include "ActorContextStore.h"

#include "RE/A/Actor.h"
#include "RE/T/TESForm.h"

namespace DeD
{
	double ActorContextStore::TTLSec(const std::string& a_factClass)
	{
		if (a_factClass == "vitals") return 60.0;
		if (a_factClass == "summary") return 1800.0;
		if (a_factClass == "relationships") return 1800.0;
		if (a_factClass == "background") return 1800.0; // fetchable later; TTL applies once fetched
		if (a_factClass == "uuidForm") return 0.0;      // no expiry
		return -1.0;                                    // unknown class
	}

	double ActorContextStore::NowSec() const
	{
		using namespace std::chrono;
		return duration_cast<duration<double>>(steady_clock::now().time_since_epoch()).count();
	}

	std::string ActorContextStore::EscapeJson(const std::string& a_s)
	{
		std::string out;
		out.reserve(a_s.size() + 8);
		for (char c : a_s) {
			switch (c) {
			case '"': out += "\\\""; break;
			case '\\': out += "\\\\"; break;
			case '\n': out += "\\n"; break;
			case '\r': out += "\\r"; break;
			case '\t': out += "\\t"; break;
			default:
				if (static_cast<unsigned char>(c) < 0x20) {
					char buf[8];
					std::snprintf(buf, sizeof(buf), "\\u%04x", c);
					out += buf;
				} else {
					out += c;
				}
			}
		}
		return out;
	}

	std::string ActorContextStore::Get(RE::Actor* a_actor, const std::string& a_factClass)
	{
		if (!a_actor) return "";
		const double ttl = TTLSec(a_factClass);
		if (ttl < 0.0) return ""; // unknown class

		const std::uint32_t formId = a_actor->GetFormID();
		if (!PublicFormIDToUUID) return ""; // SN API v3+ absent -> always-MISS
		const std::uint64_t uuid = PublicFormIDToUUID(formId);
		if (uuid == 0) return ""; // alien/unknown actor (the S203 u!=0 guard posture)

		std::lock_guard lock(m_mutex);

		// uuidForm: resolve-once, cache forever
		const std::string uuidDec = std::to_string(uuid);
		if (a_factClass == "uuidForm") {
			auto& facts = m_entries[uuidDec];
			auto it = facts.find(a_factClass);
			if (it != facts.end()) {
				const ActorFact& f = it->second;
				return "{\"value\":\"" + EscapeJson(f.value) + "\",\"source\":\"" + EscapeJson(f.source) +
					"\",\"freshAt\":" + std::to_string(f.freshAt) + "}";
			}
			char hex[16];
			std::snprintf(hex, sizeof(hex), "0x%08X", formId);
			ActorFact f;
			f.value = uuidDec + std::string(",") + hex;
			f.source = "native:uuid";
			f.freshAt = NowSec();
			facts[a_factClass] = f;
			SKSE::log::info("[DeDService] ActorContext uuidForm resolved {} -> {}.", hex, uuidDec);
			return "{\"value\":\"" + EscapeJson(f.value) + "\",\"source\":\"" + f.source +
				"\",\"freshAt\":" + std::to_string(f.freshAt) + "}";
		}

		const auto eIt = m_entries.find(uuidDec);
		if (eIt == m_entries.end()) return "";
		const auto fIt = eIt->second.find(a_factClass);
		if (fIt == eIt->second.end()) return "";
		const ActorFact& f = fIt->second;
		const double now = NowSec();
		if (f.cooldownUntil > now) return ""; // failure cooldown armed
		if (ttl > 0.0 && (now - f.freshAt) > ttl) return ""; // stale -> MISS so the resolver refreshes
		return "{\"value\":\"" + EscapeJson(f.value) + "\",\"source\":\"" + EscapeJson(f.source) +
			"\",\"freshAt\":" + std::to_string(f.freshAt) + "}";
	}

	bool ActorContextStore::Set(RE::Actor* a_actor, const std::string& a_factClass,
		const std::string& a_value, const std::string& a_source)
	{
		if (!a_actor || a_value.empty()) return false;
		if (TTLSec(a_factClass) < 0.0) return false;
		if (!PublicFormIDToUUID) return false;
		const std::uint64_t uuid = PublicFormIDToUUID(a_actor->GetFormID());
		if (uuid == 0) return false;

		std::lock_guard lock(m_mutex);
		ActorFact& f = m_entries[std::to_string(uuid)][a_factClass];
		f.value = a_value;
		f.source = a_source;
		f.freshAt = NowSec();
		f.cooldownUntil = 0.0; // successful commit clears any cooldown
		return true;
	}

	bool ActorContextStore::Invalidate(RE::Actor* a_actor)
	{
		if (!a_actor || !PublicFormIDToUUID) return false;
		const std::uint64_t uuid = PublicFormIDToUUID(a_actor->GetFormID());
		if (uuid == 0) return false;

		std::lock_guard lock(m_mutex);
		return m_entries.erase(std::to_string(uuid)) > 0;
	}

	void ActorContextStore::ArmCooldown(RE::Actor* a_actor, const std::string& a_factClass)
	{
		if (!a_actor || !PublicFormIDToUUID) return;
		if (TTLSec(a_factClass) < 0.0) return;
		const std::uint64_t uuid = PublicFormIDToUUID(a_actor->GetFormID());
		if (uuid == 0) return;

		std::lock_guard lock(m_mutex);
		auto eIt = m_entries.find(std::to_string(uuid));
		if (eIt == m_entries.end()) return;
		auto fIt = eIt->second.find(a_factClass);
		if (fIt == eIt->second.end()) return;
		fIt->second.cooldownUntil = NowSec() + kCooldownSec;
		SKSE::log::warn("[DeDService] ActorContext cooldown armed (uuid {}, fact {}, {}s).",
			uuid, a_factClass, kCooldownSec);
	}

	void ActorContextStore::Revert()
	{
		std::lock_guard lock(m_mutex);
		m_entries.clear();
	}
}
