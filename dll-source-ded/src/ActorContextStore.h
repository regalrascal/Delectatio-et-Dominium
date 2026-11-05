#pragma once

// REV-170 Leg 3 -- Actor Context store (design of record:
// docs/specs/native-optimization-lanes.md Lane 2 "REV-170 Leg 2" section;
// schema of record: docs/features/INSTRUCTION SET REV-170 -- Native.md s4).
//
// In-memory ONLY (no cosave -- the design of record's explicit ruling; the
// resolve loop is Papyrus-driven because the native layer cannot render
// Jinja, census P4). One entry per actor keyed by SN uuid (decimal string),
// per-fact {value, source, freshAt} with PER-FACT TTLs (not blob expiry) and
// a per-fact failure cooldown (600s, the REV-169 retry shape -- never a
// permanent gate).
//
// Fact classes and TTLs of record:
//   vitals        60s    (decnpc-sourced via a DeD template; no native accessor)
//   summary      1800s   (render_character_profile("bio_summary", u))
//   background   --      (resolvable-but-UNFETCHED at launch; block mode exists)
//   relationships 1800s  (bio_relationships + native PublicGetRelatedActors)
//   uuidForm      none   (native PublicFormIDToUUID; decimal+hex stored once)
//
// uuidForm is the ONE fact the native layer can resolve itself (census P3);
// GetActorContext resolves and caches it on demand. All other facts return
// MISS ("") and the Papyrus resolver renders + commits via SetActorContext.

#include <cstdint>
#include <mutex>
#include <string>
#include <unordered_map>

namespace DeD
{
	struct ActorFact
	{
		std::string value;   // fact payload (fact-class defined shape)
		std::string source;  // provenance tag, e.g. "native:uuid", "tpl:bio_summary"
		double freshAt = 0.0; // seconds, game-frame clock (steady)

		// failure cooldown (per-fact; 0 = none armed)
		double cooldownUntil = 0.0;
	};

	class ActorContextStore
	{
	public:
		static ActorContextStore& GetSingleton()
		{
			static ActorContextStore instance;
			return instance;
		}

		// TTL seconds for a fact class; 0 = no expiry. -1 = unknown class.
		static double TTLSec(const std::string& a_factClass);
		static constexpr double kCooldownSec = 600.0;

		// a_actor may be null (guarded; returns ""). Returns JSON
		// {"value":...,"source":...,"freshAt":...} on HIT (fresh), "" on MISS /
		// stale / cooldown-armed / unknown class. uuidForm self-resolves
		// natively (census P3; SN API v3+).
		std::string Get(RE::Actor* a_actor, const std::string& a_factClass);

		// Resolve-commit surface for the Papyrus resolver. Returns false on
		// guard failure (null actor, unknown class, empty value).
		bool Set(RE::Actor* a_actor, const std::string& a_factClass,
			const std::string& a_value, const std::string& a_source);

		// Drops every fact for the actor (uuidForm too -- full re-probe path).
		bool Invalidate(RE::Actor* a_actor);

		// Arms the failure cooldown for one fact (the resolver's retry shape).
		void ArmCooldown(RE::Actor* a_actor, const std::string& a_factClass);

		// SN API surface (resolved at kDataLoaded by Plugin.cpp; v3+ required
		// for FormIDToUUID -- the store degrades to always-MISS uuidForm if
		// the installed SkyrimNet is older, per DevKit contract).
		std::uint64_t (*PublicFormIDToUUID)(std::uint32_t) = nullptr;

		void Revert(); // new game / cosave discard: drop everything

		mutable std::mutex m_mutex;

	private:
		ActorContextStore() = default;

		// SN uuid (decimal string) -> fact class -> fact
		std::unordered_map<std::string, std::unordered_map<std::string, ActorFact>> m_entries;

		double NowSec() const;
		static std::string EscapeJson(const std::string& a_s);
	};
}
