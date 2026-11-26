// DeDDowned.dll -- the DeD Downed module's engine side (A3b leg 2, S339). Spec: docs/specs/ded-downed-a2-spec.md
// (sections 3, 4, 6, 10, 18). All state lives in DeDService (DeDDowned_API.h); this DLL only hooks the engine and
// writes through that API. With Acheron installed it waits until Acheron's own "Enabled" toggle is off (D-A58, S342;
// DeD_MCM reports it each reload); it disarms when DeDService is missing.
//   H1/H2  Actor::HandleHealthDamage (0x104, NPC + player vtables): it runs after the health change and before the
//          engine processes death / essential bleedout (A3a). A blow from an actor that leaves a humanoid at <= 0 health
//          is rolled (Player / Companions / NPCs); pass -> health back to 1, Downed. A blow on a Downed actor is the
//          second blow: absorbed in the grace window, when protected, or from a companion; otherwise it kills.
//   H3     Character::UpdateCombat (0xE4): a pacified actor drops combat; an actor whose target is pacified drops it.
//   H4     PlayerCharacter::Update (0xAD): drives DeDService's timers (pauses with the game).
//   H5     TESNPC::Activate (0x37): the player activating a Downed actor opens the DeD panel on them instead of talking.
//   H6     TESObjectLoadedEvent: a Downed actor's pose is re-applied when its 3D loads.
//   Poses: vanilla bleedout graph events WITHOUT the engine's bleedout state (D-A52: LoreRim's Press E to Heal
//   Followers only offers itself on IsBleedingOut, so it never doubles DeD's Help Up).
// Leg 3 (S340): the module's own DeD panel section (status + settings, saved per save in DeDService's DWND) and the
// one-shot Acheron migration (spec 14: player controls here, SNAcheron.* keys by DeD_MCM). Log: SKSE\DeDDowned.log.
// ASCII only.
#include "PCH.h"

#include <atomic>
#include <chrono>
#include <deque>
#include <fstream>
#include <cstring>
#include <mutex>
#include <random>
#include <unordered_map>
#include <unordered_set>

#include <nlohmann/json.hpp>
#include <spdlog/sinks/basic_file_sink.h>

#include "DeDDowned_API.h"
#include "DeDUI_API.h"
#include "PublicAPI.h"   // SkyrimNet public API (MIT, external/skyrimnet), S347: decisions + prompts

namespace
{
	constexpr auto kTag = "[DeDDowned]";

	// ---- settings (spec defaults: D-A28 chances, D-A17 grace, 6.1 durations, D-A44 companions) ----
	struct Settings
	{
		int   chancePlayer = 100;
		int   chanceCompanion = 100;
		int   chanceNPC = 50;
		float graceSeconds = 1.5f;
		bool  downedProtected = false;        // "Downed actors are protected"
		bool  companionsMayFinish = false;    // "Companions may finish downed enemies"
		float downedSeconds = 300.0f;
		float pacifiedSeconds = 300.0f;
	} g_set;

	const DeDDowned::Api1* g_api = nullptr;
	const DeDUI::Api2*     g_ui = nullptr;
	bool                   g_armed = false;
	RE::TESFaction*        g_slFaction = nullptr;
	RE::TESFaction*        g_osFaction = nullptr;
	RE::TESFaction*        g_followerFaction = nullptr;

	std::mutex                               g_mx;
	std::unordered_map<std::uint32_t, float> g_downAt;   // real seconds when the module downed it (second-blow grace)
	std::unordered_set<std::uint32_t>        g_posed;    // actors the module put in the downed pose
	std::unordered_set<std::uint32_t>        g_recovering;   // S343 (D-A59): Recovering NPCs held under 30% health
	std::unordered_map<std::uint32_t, float> g_downHp;       // S345 (D-A60): a Downed actor's health at the last check
	std::mt19937                             g_rng{ std::random_device{}() };
	thread_local bool                        t_inHook = false;
	bool                                     g_acheron = false;   // Acheron installed (S342)
	std::atomic<bool>                        g_encounter{ false }; // S346 (spec 19.2): victors interacting with a downed player

	// S342 (D-A58): the hooks act only while DeDService says so (Acheron absent, or installed with its toggle off).
	bool Active() { return g_armed && g_api && g_api->IsModuleActive(); }

	float Now()
	{
		static const auto start = std::chrono::steady_clock::now();
		return std::chrono::duration<float>(std::chrono::steady_clock::now() - start).count();
	}

	std::string Name(RE::TESObjectREFR* a_ref)
	{
		if (!a_ref) return "none";
		const char* n = a_ref->GetDisplayFullName();
		return std::format("{} ({:08X})", (n && *n) ? n : "?", a_ref->GetFormID());
	}

	float Health(RE::Actor* a_actor) { return a_actor->AsActorValueOwner()->GetActorValue(RE::ActorValue::kHealth); }

	bool IsHumanoid(RE::Actor* a_actor) { return a_actor && a_actor->HasKeywordString("ActorTypeNPC"); }

	bool InScene(RE::Actor* a_actor)
	{
		return (g_slFaction && a_actor->IsInFaction(g_slFaction)) || (g_osFaction && a_actor->IsInFaction(g_osFaction));
	}

	bool IsCompanion(RE::Actor* a_actor)
	{
		return a_actor && !a_actor->IsPlayerRef() &&
		       (a_actor->IsPlayerTeammate() || (g_followerFaction && a_actor->IsInFaction(g_followerFaction)));
	}

	void SendModEvent(const char* a_name, RE::TESForm* a_sender, const std::string& a_str)
	{
		if (auto* src = SKSE::GetModCallbackEventSource()) {
			SKSE::ModCallbackEvent ev{ RE::BSFixedString(a_name), RE::BSFixedString(a_str.c_str()), 0.0f, a_sender };
			src->SendEvent(&ev);
		}
	}

	void RestoreToFloor(RE::Actor* a_actor)
	{
		const float h = Health(a_actor);
		if (h < 1.0f) a_actor->AsActorValueOwner()->RestoreActorValue(RE::ActorValue::kHealth, 1.0f - h);
	}

	// ---- settings (leg 3): per save in DeDService; keys shared by the panel section ----
	struct SettingDef
	{
		const char* key;
		const char* group;
		const char* label;
		const char* desc;
		bool        toggle;
		float       min, max, step;
		const char* unit;
		float       def;
		bool        level = false;   // S351 (D-A65): a five-level outcome setting (Never .. Very often)
		int         need = 0;        // outcome owner: 0 DeD Downed, 1 Baka, 2 Baka + SexLab / OStim, 3 Baka + SlaveTats
		bool        info = false;    // shown only (greyed), never set
	};
	// Labels and descriptions are placeholders (register entry 74).
	const SettingDef kSettings[] = {
		{ "chance.player", "Downed instead of killed", "Player", "Chance that a killing blow from an enemy downs you instead. 0 = never, 100 = always.", false, 0, 100, 5, "%", 100 },
		{ "chance.companion", "Downed instead of killed", "Companions", "Chance for your companions.", false, 0, 100, 5, "%", 100 },
		{ "chance.npc", "Downed instead of killed", "Everyone else", "Chance for every other person.", false, 0, 100, 5, "%", 50 },
		{ "time.downed", "Timers", "Time downed", "How long a downed person stays on the ground before getting up (real seconds while the game runs).", false, 60, 600, 30, " s", 300 },   // S341 user: 1-10 min, default 5
		{ "time.pacified", "Timers", "Time unable to fight", "After getting up, how long they stay too hurt to fight.", false, 60, 600, 30, " s", 300 },   // S341 user: 1-10 min, no 0
		{ "time.grace", "Timers", "Second blow grace", "Right after someone goes down, hits on them are absorbed for this long.", false, 0, 60, 0.5f, " s", 1.5f },
		{ "combat.protected", "Combat", "Downed people are protected", "When on, no hit kills a downed person.", true, 0, 1, 1, "", 0 },
		{ "combat.companionsfinish", "Combat", "Companions may finish downed enemies", "When off, your companions' hits on downed enemies are absorbed.", true, 0, 1, 1, "", 0 },
		// S344 (A4 leg 3): read by DeDService's Help Up cost and kill-move pick (same DWND settings store)
		{ "helpup.custompotions", "Downed menu", "Use custom potions for Help Up", "In a fight, Help Up uses your weakest health potion. When on, potions you brewed yourself count too.", true, 0, 1, 1, "", 0 },
		{ "execute.anims", "Downed menu", "Execution animations", "Execute plays a kill move that fits your weapon when there is one; otherwise a plain killing blow.", true, 0, 1, 1, "", 1 },
		// S346 (spec 19.3): the encounter after the player goes down, and the "after"
		{ "encounter.radius", "When you are down", "Encounter radius", "How close enemies must be to take part when you are down (units; 1500 is about 20 m).", false, 500, 4000, 100, "", 1500 },
		{ "encounter.groupchance", "When you are down", "Group scene chance", "When two or more enemies want you, the chance they share one scene instead of taking turns.", false, 0, 100, 5, "%", 50 },
		{ "encounter.maxpartners", "When you are down", "Most partners in a group scene", "The largest group scene, you included. Lower it if your animation packs lack big group scenes.", false, 2, 5, 1, "", 3 },
		{ "encounter.turncap", "When you are down", "Turn time cap", "The longest one enemy's turn may last before the next one goes.", false, 60, 600, 30, " s", 180 },
		{ "after.hours", "When you are down", "Time passed afterwards", "How much time passes while you come to after it is over (not counted as sleep).", false, 0, 8, 1, " h", 1 },
		// S349 (A4 leg 4d, spec 9 / D-A39): robbery by victors
		{ "out.rob", "Robbery", "Robbery", "How often a victor also goes through the person's belongings (asked separately, before what they do; Never = never asked).", false, 0, 4, 1, "", 2, true, 0 },
		{ "robbery.gold", "Robbery", "Most gold taken", "The largest share of the purse a robber takes (they take between half of this and all of it).", false, 0, 100, 5, "%", 25 },
		{ "robbery.weapons", "Robbery", "Robbers take weapons", "A robber may take a weapon.", true, 0, 1, 1, "", 1 },
		{ "robbery.armour", "Robbery", "Robbers take armour", "A robber may take a piece of armour or clothing.", true, 0, 1, 1, "", 1 },
		{ "robbery.misc", "Robbery", "Robbers take other items", "A robber may take potions, gems, books and other valuables (never quest items or keys).", true, 0, 1, 1, "", 1 },
		{ "robbery.equipped", "Robbery", "Robbers may take equipped items", "A robber may take something you are wearing or holding.", true, 0, 1, 1, "", 0 },
		// S351 (spec 20, D-A65..D-A70): what victors may do
		{ "encounter.weighted", "What victors may do", "Weighted choices", "On: how often each outcome happens follows the levels below (the character still decides what they would never do). Off: the AI's first pick, the levels only allow or forbid.", true, 0, 1, 1, "", 1 },
		{ "out.sex", "What victors may do", "Sex scene", "A sexual scene through SexLab or OStim.", false, 0, 4, 1, "", 2, true, 2 },
		{ "out.threaten", "What victors may do", "Threaten and humiliate", "Threats, taunts and humiliation, then they leave.", false, 0, 4, 1, "", 2, true, 0 },
		{ "out.strip", "What victors may do", "Strip", "They strip the person; the clothes stay in the person's inventory.", false, 0, 4, 1, "", 1, true, 1 },
		{ "out.tattoo", "What victors may do", "Tattoo", "They mark the person with a tattoo.", false, 0, 4, 1, "", 1, true, 3 },
		{ "out.makeup", "What victors may do", "Force makeup", "They paint the person's face to humiliate them.", false, 0, 4, 1, "", 1, true, 3 },
		{ "out.execute", "What victors may do", "Execute", "They kill the person. On you this is death.", false, 0, 4, 1, "", 0, true, 1 },
		{ "out.tie", "What victors may do", "Tie up", "Coming later: it would leave you stranded with no way out yet.", false, 0, 0, 0, "", 0, false, 0, true },
		{ "out.leave", "What victors may do", "Leave", "They leave the person where they lie (always possible).", false, 1, 4, 1, "", 2, true, 0 },
		{ "encounter.keepgoing", "What victors may do", "Victors keep going until they lose interest", "Off: one thing per victor (plus a robbery). On: after each turn a victor may go on, until they have had enough.", true, 0, 1, 1, "", 0 },
		{ "encounter.maxturns", "What victors may do", "Most turns per victor", "With \"keep going\" on: the most turns one victor takes.", false, 1, 10, 1, "", 3 },
		// S352 (A4 leg 5, spec 15 / 7.1): companions and beaten enemies
		{ "companions.resist", "Companions", "Companions keep fighting", "When you go down, your companions fight on and may heal you back into the fight. Off: they give up and go down with you.", true, 0, 1, 1, "", 1 },
		{ "companions.advantage", "Companions", "Companions may take advantage", "After your side wins while you are down: off, a companion helps you up; on, each companion decides (helping you up is the likeliest; never an execution).", true, 0, 1, 1, "", 0 },
		{ "parley.on", "Beaten enemies", "Beaten enemies may stand down", "When an enemy you beat recovers, they decide (from what you said to them) whether to stop fighting you for good.", true, 0, 1, 1, "", 1 },
		{ "after.wounded", "When you are down", "Wounded until you sleep", "After it is over: less maximum health and stamina and slower regeneration until you next sleep.", true, 0, 1, 1, "", 1 },
	};

	float Setting(const char* a_key)
	{
		for (const auto& d : kSettings)
			if (!std::strcmp(d.key, a_key)) return std::clamp(g_api ? g_api->GetSetting(d.key, d.def) : d.def, d.min, d.max);   // S341: old saves pulled into range
		return 0.0f;
	}

	void LoadSettings(const char* a_why)
	{
		g_set.chancePlayer = static_cast<int>(Setting("chance.player"));
		g_set.chanceCompanion = static_cast<int>(Setting("chance.companion"));
		g_set.chanceNPC = static_cast<int>(Setting("chance.npc"));
		g_set.downedSeconds = Setting("time.downed");
		g_set.pacifiedSeconds = Setting("time.pacified");
		g_set.graceSeconds = Setting("time.grace");
		g_set.downedProtected = Setting("combat.protected") >= 0.5f;
		g_set.companionsMayFinish = Setting("combat.companionsfinish") >= 0.5f;
		if (g_api) g_api->SetDurations(g_set.downedSeconds, g_set.pacifiedSeconds);
		if (g_api && g_api->GetSetting("robbery.on", -1.0f) == 0.0f) {   // S351: S349's Robbery off -> Robbery = Never
			g_api->SetSetting("out.rob", 0.0f);
			g_api->SetSetting("robbery.on", 2.0f);
			SKSE::log::info("{} SETTINGS: Robbery off (S349) -> Robbery level Never.", kTag);
		}
		SKSE::log::info("{} SETTINGS ({}): chances {} / {} / {}, downed {:.0f} s, pacified {:.0f} s, grace {:.1f} s, protected={}, "
		                "companions may finish={}.", kTag, a_why, g_set.chancePlayer, g_set.chanceCompanion, g_set.chanceNPC,
			g_set.downedSeconds, g_set.pacifiedSeconds, g_set.graceSeconds, g_set.downedProtected, g_set.companionsMayFinish);
	}

	// ---- H1 / H2: a lethal blow from an actor ----
	void OnLethal(RE::Actor* a_victim, RE::Actor* a_attacker, float a_hp)
	{
		const auto id = a_victim->GetFormID();
		const auto phase = g_api->GetPhase(id);
		if (phase == DeDDowned::Phase::Downed) {
			const char* src = a_attacker->IsPlayerRef() ? "player" : IsCompanion(a_attacker) ? "companion" : "npc";
			float since = 1.0e9f;
			{
				std::lock_guard lk(g_mx);
				if (const auto it = g_downAt.find(id); it != g_downAt.end()) since = Now() - it->second;
			}
			const char* result = nullptr;
			if (since < g_set.graceSeconds)
				result = "grace";
			else if (g_set.downedProtected)
				result = "protected";
			else if (!std::strcmp(src, "companion") && !g_set.companionsMayFinish)
				result = "absorbed";
			if (result) {
				RestoreToFloor(a_victim);
				SKSE::log::info("{} SECOND-BLOW victim={} source={} by={} result={} ({:.1f} s after the down)", kTag,
					Name(a_victim), src, Name(a_attacker), result, since);
			} else {
				SKSE::log::info("{} SECOND-BLOW victim={} source={} by={} result=kill hp={:.1f}", kTag, Name(a_victim), src,
					Name(a_attacker), a_hp);
				g_api->Release(id);   // the death follows on the engine's next pass
			}
			return;
		}
		if (InScene(a_victim)) {
			SKSE::log::info("{} ROLL skipped: {} is in a SexLab / OStim scene (vanilla blow).", kTag, Name(a_victim));
			return;
		}
		const bool player = a_victim->IsPlayerRef();
		const char* group = player ? "player" : IsCompanion(a_victim) ? "companion" : "npc";
		const int chance = player ? g_set.chancePlayer : !std::strcmp(group, "companion") ? g_set.chanceCompanion : g_set.chanceNPC;
		const int roll = std::uniform_int_distribution<int>(0, 99)(g_rng);
		const bool pass = roll < chance;
		SKSE::log::info("{} ROLL victim={} group={} chance={} roll={} -> {} (blow by {}, hp {:.1f})", kTag, Name(a_victim),
			group, chance, roll, pass ? "DOWN" : "kill", Name(a_attacker), a_hp);
		if (!pass) return;
		RestoreToFloor(a_victim);
		{
			std::lock_guard lk(g_mx);
			g_downAt[id] = Now();
		}
		g_api->DownActor(id, a_attacker->GetFormID(), "lethal");
	}

	void HandleDamage(RE::Actor* a_victim, RE::Actor* a_attacker)
	{
		if (!Active() || t_inHook || !a_victim || !a_attacker || a_attacker == a_victim) return;
		if (a_victim->IsDead() || !IsHumanoid(a_victim)) return;
		const float hp = Health(a_victim);
		if (hp > 0.0f) return;
		t_inHook = true;
		OnLethal(a_victim, a_attacker, hp);
		t_inHook = false;
	}

	struct HealthDamageNPC
	{
		static void thunk(RE::Actor* a_this, RE::Actor* a_attacker, float a_damage)
		{
			func(a_this, a_attacker, a_damage);
			HandleDamage(a_this, a_attacker);
		}
		static inline REL::Relocation<decltype(thunk)> func;
	};

	struct HealthDamagePlayer
	{
		static void thunk(RE::Actor* a_this, RE::Actor* a_attacker, float a_damage)
		{
			func(a_this, a_attacker, a_damage);
			HandleDamage(a_this, a_attacker);
		}
		static inline REL::Relocation<decltype(thunk)> func;
	};

	// ---- H3: pacify enforcement ----
	struct UpdateCombatNPC
	{
		static void thunk(RE::Actor* a_this)
		{
			if (Active() && a_this && a_this->IsInCombat()) {
				if (g_api->IsPacified(a_this->GetFormID())) {
					a_this->StopCombat();
					return;
				}
				auto target = a_this->GetActorRuntimeData().currentCombatTarget.get();
				if (target && g_api->IsPacified(target->GetFormID())) {
					a_this->StopCombat();   // it picks another target through detection if one is left
					return;
				}
			}
			func(a_this);
		}
		static inline REL::Relocation<decltype(thunk)> func;
	};

	// ---- S343 (D-A59): a Recovering NPC's health stays at 28% of its maximum, so injured-animation packs that trigger
	// under 30% health (Injured Animations Dynamic Replacer SE) show the injured look. No DeD animations, no OAR config.
	void HoldInjured()
	{
		std::vector<std::uint32_t> ids;
		{
			std::lock_guard lk(g_mx);
			ids.assign(g_recovering.begin(), g_recovering.end());
		}
		for (const auto id : ids) {
			auto* a = RE::TESForm::LookupByID<RE::Actor>(id);
			if (!a || a->IsDead() || !a->Is3DLoaded() || g_api->GetPhase(id) != DeDDowned::Phase::Recovering) continue;
			auto* av = a->AsActorValueOwner();
			const float max = av->GetPermanentActorValue(RE::ActorValue::kHealth);
			const float cur = av->GetActorValue(RE::ActorValue::kHealth);
			if (max > 0.0f && cur > max * 0.29f) av->DamageActorValue(RE::ActorValue::kHealth, cur - max * 0.28f);
		}
	}

	// ---- S345 (user, D-A60): healing a Downed actor above 30% health recovers them (a companion -> Recovering; the
	// player -> back in the fight, D-A38). Natural regeneration must not do it: each second a gain no bigger than twice
	// what the actor's own HealRate could give (+0.5% of max) is clamped back to the 1-point floor; a bigger gain is
	// a real heal (spell, potion) and is kept.
	void WatchDowned(float a_dt)
	{
		std::vector<std::uint32_t> ids;
		{
			std::lock_guard lk(g_mx);
			ids.assign(g_posed.begin(), g_posed.end());
		}
		for (const auto id : ids) {
			auto* a = RE::TESForm::LookupByID<RE::Actor>(id);
			if (!a || a->IsDead() || !a->Is3DLoaded() || g_api->GetPhase(id) != DeDDowned::Phase::Downed) continue;
			auto* av = a->AsActorValueOwner();
			const float max = av->GetPermanentActorValue(RE::ActorValue::kHealth);
			const float cur = av->GetActorValue(RE::ActorValue::kHealth);
			if (max <= 0.0f) continue;
			float prev = 1.0f;
			{
				std::lock_guard lk(g_mx);
				if (const auto it = g_downHp.find(id); it != g_downHp.end()) prev = it->second;
			}
			const float regen = av->GetActorValue(RE::ActorValue::kHealRate) / 100.0f * max * a_dt;
			const float gain = cur - prev;
			if (gain > regen * 2.0f + max * 0.005f) {
				if (cur >= max * 0.30f) {
					const bool party = a->IsPlayerRef() || IsCompanion(a);   // S346 (D-A62): companions too
					SKSE::log::info("{} HEALED {} to {:.0f} / {:.0f} health -> {}.", kTag, Name(a), cur, max,
						party ? "back in the fight" : "Recovering");
					{
						std::lock_guard lk(g_mx);
						g_downHp.erase(id);
					}
					g_api->Recover(id, party);
					continue;
				}
				std::lock_guard lk(g_mx);
				g_downHp[id] = cur;   // healed, not enough yet: keep it
			} else if (cur > prev + 0.01f) {
				av->DamageActorValue(RE::ActorValue::kHealth, cur - prev);   // natural regeneration: back down
			}
		}
	}



	// ---- S348 (A4 leg 4c, spec 19.4, D-A54 / D-A63): the player's "after" and "Wounded until you sleep" ----
	// The player's down ends here (no Recovering for the player): fade out; game time moves on by "Time passed
	// afterwards" (set on the calendar, not as sleep or wait); the player is moved back along their own recent path
	// to a spot away from the victors (ground they really stood on); a SkyrimNet direct narration (trigger
	// ded_downed_after) says what happened; the player is up (phase None, controls back); with "Wounded until you
	// sleep" on: -20% maximum health and stamina and half health / stamina regeneration until the next sleep
	// (permanent actor-value modifiers, the applied amounts kept in DeDService's save data so sleep removes exactly
	// them); fade in.
	struct TrailPoint
	{
		RE::NiPoint3 pos;
		RE::TESObjectCELL* cell = nullptr;
		RE::TESWorldSpace* world = nullptr;
	};
	std::deque<TrailPoint> g_trail;   // the player's position once a second while up (last 90 s)
	struct After
	{
		int   stage = 0;              // 0 idle, 1 faded out, 2 done (fade in sent)
		float started = 0.0f;
		bool  interacted = false;
		std::vector<std::uint32_t> victors;
	} g_after;

	void PapyrusFade(bool a_out)
	{
		auto* vm = RE::BSScript::Internal::VirtualMachine::GetSingleton();
		if (!vm) return;
		RE::BSTSmartPointer<RE::BSScript::IStackCallbackFunctor> cb;
		auto* args = RE::MakeFunctionArguments(std::move(a_out), true, 0.0f, a_out ? 1.0f : 1.5f);
		vm->DispatchStaticCall("Game", "FadeOutGame", args, cb);
		delete args;
	}

	void PapyrusNotify(const char* a_msg)
	{
		auto* vm = RE::BSScript::Internal::VirtualMachine::GetSingleton();
		if (!vm) return;
		RE::BSTSmartPointer<RE::BSScript::IStackCallbackFunctor> cb;
		auto* args = RE::MakeFunctionArguments(RE::BSFixedString(a_msg));
		vm->DispatchStaticCall("Debug", "Notification", args, cb);
		delete args;
	}

	void PassTime(float a_hours)
	{
		auto* cal = RE::Calendar::GetSingleton();
		if (!cal || a_hours <= 0.0f || !cal->gameHour || !cal->gameDaysPassed) return;
		float hour = cal->gameHour->value + a_hours;
		cal->gameDaysPassed->value += a_hours / 24.0f;
		while (hour >= 24.0f) {
			hour -= 24.0f;
			if (cal->gameDay) cal->gameDay->value += 1.0f;
		}
		cal->gameHour->value = hour;
	}

	// S351 (D-A69): the "Wounded" ability in DeD_Framework.esp (SPEL 0x805: HealRateMult / StaminaRateMult -50, shown in
	// Active Effects); the -20% maximum health / stamina stays an exact actor-value modifier applied with it.
	RE::SpellItem* WoundSpell()
	{
		auto* dh = RE::TESDataHandler::GetSingleton();
		return dh ? dh->LookupForm<RE::SpellItem>(0x805, "DeD_Framework.esp") : nullptr;
	}

	void ApplyWound(RE::PlayerCharacter* a_pc)
	{
		if (Setting("after.wounded") < 0.5f || g_api->GetSetting("wound.on", 0.0f) >= 0.5f) return;
		auto* av = a_pc->AsActorValueOwner();
		using AV = RE::ActorValue;
		using M = RE::ACTOR_VALUE_MODIFIER;
		const float hp = av->GetPermanentActorValue(AV::kHealth) * 0.2f;
		const float sp = av->GetPermanentActorValue(AV::kStamina) * 0.2f;
		av->ModActorValue(M::kPermanent, AV::kHealth, -hp);
		av->ModActorValue(M::kPermanent, AV::kStamina, -sp);
		g_api->SetSetting("wound.hp", hp);
		g_api->SetSetting("wound.sp", sp);
		g_api->SetSetting("wound.hr", 0.0f);
		g_api->SetSetting("wound.sr", 0.0f);
		g_api->SetSetting("wound.on", 1.0f);
		auto* spell = WoundSpell();
		if (spell) a_pc->AddSpell(spell);
		PapyrusNotify("You are badly hurt. Rest and sleep to recover.");
		SKSE::log::info("{} WOUNDED until you sleep: -{:.0f} max health, -{:.0f} max stamina, Wounded effect {}.", kTag, hp, sp,
			spell ? "added (regeneration halved)" : "MISSING (DeD_Framework.esp without SPEL 0x805)");
	}

	// on load: the spell matches the saved state; a S348 wound (regeneration as actor-value modifiers) moves to the spell
	void SyncWound(const char* a_why)
	{
		auto* pc = RE::PlayerCharacter::GetSingleton();
		auto* spell = WoundSpell();
		if (!pc || !g_api) return;
		const bool on = g_api->GetSetting("wound.on", 0.0f) >= 0.5f;
		if (on && spell && !pc->HasSpell(spell)) {
			auto* av = pc->AsActorValueOwner();
			using AV = RE::ActorValue;
			using M = RE::ACTOR_VALUE_MODIFIER;
			av->ModActorValue(M::kPermanent, AV::kHealRate, g_api->GetSetting("wound.hr", 0.0f));
			av->ModActorValue(M::kPermanent, AV::kStaminaRate, g_api->GetSetting("wound.sr", 0.0f));
			g_api->SetSetting("wound.hr", 0.0f);
			g_api->SetSetting("wound.sr", 0.0f);
			pc->AddSpell(spell);
			SKSE::log::info("{} WOUNDED ({}): the Wounded effect added to match the save.", kTag, a_why);
		} else if (!on && spell && pc->HasSpell(spell)) {
			pc->RemoveSpell(spell);
			SKSE::log::info("{} WOUNDED ({}): a leftover Wounded effect removed.", kTag, a_why);
		}
	}

	void ClearWound(const char* a_why)
	{
		if (!g_api || g_api->GetSetting("wound.on", 0.0f) < 0.5f) return;
		auto* pc = RE::PlayerCharacter::GetSingleton();
		if (!pc) return;
		auto* av = pc->AsActorValueOwner();
		using AV = RE::ActorValue;
		using M = RE::ACTOR_VALUE_MODIFIER;
		av->ModActorValue(M::kPermanent, AV::kHealth, g_api->GetSetting("wound.hp", 0.0f));
		av->ModActorValue(M::kPermanent, AV::kStamina, g_api->GetSetting("wound.sp", 0.0f));
		av->ModActorValue(M::kPermanent, AV::kHealRate, g_api->GetSetting("wound.hr", 0.0f));
		av->ModActorValue(M::kPermanent, AV::kStaminaRate, g_api->GetSetting("wound.sr", 0.0f));
		for (const char* k : { "wound.hp", "wound.sp", "wound.hr", "wound.sr", "wound.on" }) g_api->SetSetting(k, 0.0f);
		if (auto* spell = WoundSpell(); spell && pc->HasSpell(spell)) pc->RemoveSpell(spell);   // S351
		PapyrusNotify("You feel recovered.");
		SKSE::log::info("{} WOUNDED cleared ({}).", kTag, a_why);
	}

	void StartAfter(bool a_interacted, const std::vector<std::uint32_t>& a_victors)
	{
		if (g_after.stage == 1) return;
		g_after = { 1, Now(), a_interacted, a_victors };
		PapyrusFade(true);
		SKSE::log::info("{} AFTER: fade out ({}).", kTag, a_interacted ? "after the encounter" : "nobody stayed");
	}

	void FinishAfter()
	{
		auto* pc = RE::PlayerCharacter::GetSingleton();
		if (!pc) return;
		// move back along the trail to a spot away from every victor, in the same cell / worldspace
		std::vector<RE::Actor*> victors;
		for (const auto v : g_after.victors)
			if (auto* a = RE::TESForm::LookupByID<RE::Actor>(v)) victors.push_back(a);
		const auto here = pc->GetPosition();
		const TrailPoint* pick = nullptr;
		for (const auto& t : g_trail) {   // oldest first
			if (t.cell != pc->GetParentCell() && (!t.world || t.world != pc->GetWorldspace())) continue;
			bool clear = true;
			for (auto* a : victors)
				if (a->GetPosition().GetDistance(t.pos) < 800.0f) clear = false;
			if (clear && t.pos.GetDistance(here) > 300.0f) {
				pick = &t;
				break;
			}
		}
		if (pick) pc->SetPosition(pick->pos, true);
		const float hours = Setting("after.hours");
		PassTime(hours);
		const char* n = pc->GetDisplayFullName();
		const std::string name = (n && *n) ? n : "The player";
		std::string text = g_after.interacted ?
			std::format("Some time later {} comes to, alone, a short way from where they fell: bruised, aching and shaken. The ones who beat them are gone.", name) :
			std::format("{} drags themselves away while no one is watching and passes out in cover, coming to {} later, hurt but alive.", name,
				hours >= 1.5f ? std::format("about {:.0f} hours", hours) : std::string("about an hour"));
		if (PublicRegisterEvent) PublicRegisterEvent("ded_downed_after", text.c_str(), pc->GetFormID(), 0, nullptr, 0);
		g_api->Recover(pc->GetFormID(), true);
		ApplyWound(pc);
		g_after.stage = 2;
		PapyrusFade(false);
		SKSE::log::info("{} AFTER: moved {} ({:.0f} units), {:.0f} h passed, narration sent, up again.", kTag,
			pick ? "back along your path" : "nowhere (no clear spot)", pick ? pick->pos.GetDistance(here) : 0.0f, hours);
	}

	void UpdateAfter(RE::PlayerCharacter* a_pc)
	{
		if (g_after.stage == 1) {
			if (Now() - g_after.started >= 2.0f) FinishAfter();
			return;
		}
		// the trail: once a second while the player is up
		if (g_api->GetPhase(a_pc->GetFormID()) == DeDDowned::Phase::None && a_pc->GetParentCell()) {
			g_trail.push_back({ a_pc->GetPosition(), a_pc->GetParentCell(), a_pc->GetWorldspace() });
			while (g_trail.size() > 90) g_trail.pop_front();
		}
	}

	struct SleepSink : RE::BSTEventSink<RE::TESSleepStopEvent>
	{
		RE::BSEventNotifyControl ProcessEvent(const RE::TESSleepStopEvent*, RE::BSTEventSource<RE::TESSleepStopEvent>*) override
		{
			ClearWound("slept");
			return RE::BSEventNotifyControl::kContinue;
		}
	};
	SleepSink g_sleepSink;


	// ---- S349 (A4 leg 4d): robbery (spec 9), threats (7.2), restraints (spec 8), the assault reset (D-A53) ----
	std::string NameOf(RE::Actor* a)
	{
		const char* n = a ? a->GetDisplayFullName() : nullptr;
		return (n && *n) ? n : "someone";
	}

	void Narrate(const char* a_type, const std::string& a_text, RE::Actor* a_from, RE::Actor* a_to)
	{
		if (PublicRegisterEvent) PublicRegisterEvent(a_type, a_text.c_str(), a_from ? a_from->GetFormID() : 0, a_to ? a_to->GetFormID() : 0, nullptr, 0);
	}

	// restraint keywords: built-in defaults (Devious Devices heavy bondage) plus SKSE/Plugins/DeDDowned_RestraintKeywords.json
	struct Keywords
	{
		bool loaded = false;
		std::vector<RE::BGSKeyword*> restraint;   // worn -> Restrained
		std::vector<RE::BGSKeyword*> locked;      // Devious Devices: only their keys remove them
		std::vector<RE::BGSKeyword*> give;        // given through Give restraints -> equipped
	} g_kw;

	void LoadKeywords()
	{
		if (g_kw.loaded) return;
		g_kw.loaded = true;
		std::vector<std::string> res{ "zad_DeviousHeavyBondage", "zad_DeviousArmbinder", "zad_DeviousArmbinderElbow", "zad_DeviousYoke",
			"zad_DeviousYokeBB", "zad_DeviousStraitJacket", "zad_DeviousPetSuit" };
		std::vector<std::string> lock{ "zad_Lockable", "zad_InventoryDevice" };
		std::vector<std::string> give{ "zad_InventoryDevice" };
		std::ifstream f("Data/SKSE/Plugins/DeDDowned_RestraintKeywords.json");
		if (f) {
			const auto j = nlohmann::json::parse(f, nullptr, false);
			auto add = [&](const char* k, std::vector<std::string>& v) {
				if (j.is_object() && j.contains(k) && j[k].is_array())
					for (const auto& e : j[k]) if (e.is_string()) v.push_back(e.get<std::string>());
			};
			add("restraint", res);
			add("locked", lock);
			add("give", give);
		}
		auto resolve = [](const std::vector<std::string>& a_names, std::vector<RE::BGSKeyword*>& a_out) {
			for (const auto& n : a_names)
				if (auto* kw = RE::TESForm::LookupByEditorID<RE::BGSKeyword>(n); kw && std::find(a_out.begin(), a_out.end(), kw) == a_out.end()) a_out.push_back(kw);
		};
		resolve(res, g_kw.restraint);
		resolve(lock, g_kw.locked);
		resolve(give, g_kw.give);
		SKSE::log::info("{} RESTRAINT keywords: {} restraint, {} locked, {} give (data file {}).", kTag, g_kw.restraint.size(),
			g_kw.locked.size(), g_kw.give.size(), f ? "read" : "absent");
	}

	bool HasAny(RE::TESBoundObject* a_obj, const std::vector<RE::BGSKeyword*>& a_kws)
	{
		auto* kf = a_obj ? a_obj->As<RE::BGSKeywordForm>() : nullptr;
		if (!kf) return false;
		for (auto* k : a_kws) if (kf->HasKeyword(k)) return true;
		return false;
	}

	// worn restraint items -> Restrained (source "items"); none left -> freed (only the "items" source)
	void CheckRestraints(RE::Actor* a)
	{
		if (!a || a->IsDead()) return;
		LoadKeywords();
		bool worn = false;
		for (auto& [obj, data] : a->GetInventory())
			if (data.second && data.second->IsWorn() && HasAny(obj, g_kw.restraint)) worn = true;
		const auto id = a->GetFormID();
		char src[32]{};
		g_api->GetRestrainedSource(id, src, sizeof(src));
		if (worn && !g_api->IsRestrained(id)) {
			g_api->SetRestrained(id, true, "items", 0.0f);
			SKSE::log::info("{} RESTRAINED {}: wears a restraint (spec 8).", kTag, Name(a));
		} else if (!worn && g_api->IsRestrained(id) && std::string_view(src) == "items") {
			g_api->SetRestrained(id, false, "items", 0.0f);
			SKSE::log::info("{} FREED {}: no restraint worn any more.", kTag, Name(a));
		}
	}

	std::uint32_t g_giveTarget = 0;   // Give restraints: the container menu is open on this actor

	void OpenGive(RE::Actor* a)
	{
		auto* vm = RE::BSScript::Internal::VirtualMachine::GetSingleton();
		if (!vm || !a) return;
		auto* policy = vm->GetObjectHandlePolicy();
		const auto handle = policy ? policy->GetHandleForObject(static_cast<RE::VMTypeID>(RE::Actor::FORMTYPE), a) : 0;
		if (!handle) return;
		g_giveTarget = a->GetFormID();
		RE::BSTSmartPointer<RE::BSScript::IStackCallbackFunctor> cb;
		auto* args = RE::MakeFunctionArguments(true);
		vm->DispatchMethodCall2(handle, "Actor", "OpenInventory", args, cb);
		delete args;
		SKSE::log::info("{} GIVE restraints: inventory exchange opened on {}.", kTag, Name(a));
	}

	void AfterGive()
	{
		auto* a = RE::TESForm::LookupByID<RE::Actor>(g_giveTarget);
		g_giveTarget = 0;
		if (!a || a->IsDead()) return;
		LoadKeywords();
		std::vector<RE::TESBoundObject*> put;
		for (auto& [obj, data] : a->GetInventory())
			if (data.first > 0 && !(data.second && data.second->IsWorn()) && (HasAny(obj, g_kw.restraint) || HasAny(obj, g_kw.give))) put.push_back(obj);
		auto* em = RE::ActorEquipManager::GetSingleton();
		for (auto* o : put) em->EquipObject(a, o, nullptr, 1, nullptr, true, true);
		SKSE::log::info("{} GIVE restraints: {} restraint item(s) equipped on {}.", kTag, put.size(), Name(a));
		const auto id = a->GetFormID();
		SKSE::GetTaskInterface()->AddTask([id]() {
			if (auto* t = RE::TESForm::LookupByID<RE::Actor>(id)) CheckRestraints(t);
		});
	}

	void FreeRestraints(RE::Actor* a)
	{
		if (!a) return;
		LoadKeywords();
		char src[32]{};
		g_api->GetRestrainedSource(a->GetFormID(), src, sizeof(src));
		std::vector<RE::TESBoundObject*> off;
		int locked = 0;
		for (auto& [obj, data] : a->GetInventory()) {
			if (!(data.second && data.second->IsWorn()) || !HasAny(obj, g_kw.restraint)) continue;
			if (HasAny(obj, g_kw.locked)) ++locked;
			else off.push_back(obj);
		}
		auto* em = RE::ActorEquipManager::GetSingleton();
		for (auto* o : off) em->UnequipObject(a, o, nullptr, 1, nullptr, true, true);
		if (locked == 0) g_api->SetRestrained(a->GetFormID(), false, src, 0.0f);
		SKSE::log::info("{} FREE {} (source {}): {} restraint(s) taken off, {} locked device(s) stay on{}.", kTag, Name(a),
			src[0] ? src : "none", off.size(), locked, locked ? " (Devious Devices: their keys are needed; DD unlock comes later, D-A22)" : "");
		if (locked) PapyrusNotify(std::format("{} still wears locked devices. Only their keys open them.", NameOf(a)).c_str());
		if (!off.empty() || locked == 0)
			Narrate("ded_downed_freed", std::format("{} frees {} from their restraints.", NameOf(RE::PlayerCharacter::GetSingleton()), NameOf(a)),
				RE::PlayerCharacter::GetSingleton(), a);
	}

	// spec 9: gold (up to "Most gold taken", rolled between half and all of it) and one item, moved to the robber
	std::string Rob(RE::Actor* a_robber, RE::Actor* a_victim)
	{
		auto* gold = RE::TESForm::LookupByID<RE::TESBoundObject>(0xF);
		LoadKeywords();
		const bool takeEquipped = Setting("robbery.equipped") >= 0.5f;
		const bool weapons = Setting("robbery.weapons") >= 0.5f, armour = Setting("robbery.armour") >= 0.5f, misc = Setting("robbery.misc") >= 0.5f;
		std::int32_t have = 0;
		std::vector<std::pair<std::int32_t, RE::TESBoundObject*>> pool;
		for (auto& [obj, data] : a_victim->GetInventory()) {
			if (!obj || data.first <= 0) continue;
			if (obj == gold) {
				have = data.first;
				continue;
			}
			auto* e = data.second.get();
			if (!e || e->IsQuestObject() || !obj->GetPlayable() || obj->Is(RE::FormType::KeyMaster)) continue;
			if (e->IsWorn() && !takeEquipped) continue;
			if (HasAny(obj, g_kw.restraint) || HasAny(obj, g_kw.locked)) continue;
			const char* n = obj->GetName();
			if (!n || !*n) continue;
			const bool ok = (weapons && obj->IsWeapon()) || (armour && obj->IsArmor()) ||
			                (misc && obj->Is(RE::FormType::Misc, RE::FormType::SoulGem, RE::FormType::AlchemyItem, RE::FormType::Ingredient, RE::FormType::Book));
			if (ok) pool.emplace_back(obj->GetGoldValue(), obj);
		}
		std::int32_t took = 0;
		const float pct = Setting("robbery.gold") / 100.0f;
		if (gold && have > 0 && pct > 0.0f) {
			const auto cap = static_cast<std::int32_t>(have * pct);
			if (cap > 0) {
				took = std::uniform_int_distribution<std::int32_t>(std::max(1, cap / 2), cap)(g_rng);
				a_victim->RemoveItem(gold, took, RE::ITEM_REMOVE_REASON::kStoreInContainer, nullptr, a_robber);
			}
		}
		std::string item;
		if (!pool.empty()) {
			std::sort(pool.begin(), pool.end(), [](const auto& x, const auto& y) { return x.first > y.first; });
			const auto top = std::min<std::size_t>(pool.size(), 3);
			auto* obj = pool[std::uniform_int_distribution<std::size_t>(0, top - 1)(g_rng)].second;
			item = obj->GetName();
			a_victim->RemoveItem(obj, 1, RE::ITEM_REMOVE_REASON::kStoreInContainer, nullptr, a_robber);
		}
		const std::string r = NameOf(a_robber), v = NameOf(a_victim);
		std::string line;
		if (took > 0 && !item.empty()) line = std::format("{} took {} gold and {} from {}", r, took, item, v);
		else if (took > 0) line = std::format("{} took {} gold from {}", r, took, v);
		else if (!item.empty()) line = std::format("{} took {} from {}", r, item, v);
		else line = std::format("{} went through {}'s belongings and found nothing worth taking", r, v);
		if (took > 0 || !item.empty()) g_api->AddRobbed(a_victim->GetFormID(), line.c_str());
		SKSE::log::info("{} ROBBERY: {} (purse {}, {} item(s) eligible).", kTag, line, have, pool.size());
		return line + ".";
	}

	// D-A53: Baka marks an aggressive scene on a downed / recovering enemy; its end restarts their down
	struct AssaultWatch
	{
		float since = 0.0f;
		bool  seen = false;
	};
	std::unordered_map<std::uint32_t, AssaultWatch> g_assault;

	void UpdateAssaults()
	{
		for (auto it = g_assault.begin(); it != g_assault.end();) {
			auto* a = RE::TESForm::LookupByID<RE::Actor>(it->first);
			const float t = Now() - it->second.since;
			bool drop = !a || a->IsDead() || t > 900.0f;
			if (!drop) {
				if (InScene(a)) {
					it->second.seen = true;
				} else if (it->second.seen) {
					if (g_api->ResetDowned(it->first, "assault"))
						Narrate("ded_downed_assault_reset", std::format("{} is left where they were taken, beaten back down, whatever strength they had regained gone.", NameOf(a)), nullptr, a);
					SKSE::log::info("{} ASSAULT over on {}: back to the start of Downed (D-A53).", kTag, Name(a));
					drop = true;
				} else if (t > 20.0f) {
					SKSE::log::info("{} ASSAULT mark on {} dropped: no scene started.", kTag, Name(a));
					drop = true;
				}
			}
			it = drop ? g_assault.erase(it) : std::next(it);
		}
	}

	// ---- S347 (A4 leg 4b, spec 19.2): the encounter coordinator. When the player is Downed with victorious enemies
	// near, each victor decides (SkyrimNet decision template ded_downed/victor_choice, chat fallback
	// ded_downed_victor_choice) whom to turn to among the downed party and what to do; sexual choices become a group
	// scene (by chance, up to "Most partners") or single turns, run one after another through Baka's scene start
	// (ModEvents DeD_DownedVictorJoin x n + DeD_DownedVictorTurn); the player and the companions in range are scene-
	// pacified for the whole encounter (no timer ends mid-encounter, companions do not rejoin the fight). Robbery and
	// threats are logged and wait for leg 4d. At the end everyone is released; the player's "after" comes in 4c.
	// ---- S351 (spec 20, D-A65..D-A68): what victors may do. Each outcome has a level (Never .. Very often); an outcome
	// at Never or whose module is missing is never offered to the LLM. The decision model returns a probability per
	// offered outcome; "Weighted choices" multiplies them by the levels and rolls (off: the model's top pick). Robbery is
	// its own yes / no question, run before the outcome. "Keep going": after each turn a victor is asked again (with
	// what they already did) until they leave or reach "Most turns per victor".
	struct OutcomeDef
	{
		const char* key;
		const char* setting;
	};
	void HelpPlayerUp(RE::PlayerCharacter* a_pc, RE::Actor* a_helper, const char* a_how);   // S352, below

	const OutcomeDef kOutcomes[] = { { "sex", "out.sex" }, { "threaten", "out.threaten" }, { "strip", "out.strip" },
		{ "tattoo", "out.tattoo" }, { "makeup", "out.makeup" }, { "execute", "out.execute" }, { "leave", "out.leave" } };
	constexpr float kLevelMult[] = { 0.0f, 0.3f, 1.0f, 2.5f, 5.0f };
	const char* const kLevelName[] = { "Never", "Rarely", "Sometimes", "Often", "Very often" };

	bool HasPlugin(const char* a_name)
	{
		auto* dh = RE::TESDataHandler::GetSingleton();
		return dh && (dh->LookupLoadedModByName(a_name) || dh->LookupLoadedLightModByName(a_name));
	}

	bool NeedMet(int a_need)
	{
		const bool baka = HasPlugin("SkyrimNet_BakaIntegration.esp");
		switch (a_need) {
		case 1: return baka;
		case 2: return baka && (HasPlugin("SexLab.esm") || HasPlugin("OStim.esp"));
		case 3: return baka && HasPlugin("SlaveTats.esp");
		default: return true;
		}
	}

	int Level(const char* a_setting) { return std::clamp(static_cast<int>(Setting(a_setting) + 0.5f), 0, 4); }

	int NeedOf(const char* a_setting)
	{
		for (const auto& d : kSettings) if (!std::strcmp(d.key, a_setting)) return d.need;
		return 0;
	}

	std::vector<std::string> OfferedOutcomes()
	{
		std::vector<std::string> out;
		for (const auto& o : kOutcomes)
			if ((Level(o.setting) > 0 || !std::strcmp(o.key, "leave")) && NeedMet(NeedOf(o.setting))) out.emplace_back(o.key);
		return out;
	}

	struct VictorChoice
	{
		std::string target;
		std::string top;                                   // the model's own pick
		std::unordered_map<std::string, float> probs;      // per offered outcome (decision) or normalised scores (chat)
		float robP = -1.0f;                                // P(rob as well); -1 = not asked / not answered
		bool  done = false;
	};
	struct EncTurn
	{
		std::vector<std::uint32_t> victors;
		std::uint32_t              target = 0;
		std::string                action = "sex";   // sex, rob, threaten, strip, tattoo, makeup, execute
	};
	struct VictorState
	{
		int                               turns = 0;     // outcome turns taken (keep-going cap; robbery not counted)
		std::vector<std::string>          doneLines;     // what they did (keep-going context)
		std::unordered_set<std::uint32_t> robbed;        // targets they already robbed
		std::vector<std::string>          offered;       // the outcomes offered at their last ask
		bool                              robAsked = false;
		bool                              pending = false;   // a keep-going re-ask is out
		float                             askedAt = 0.0f;
		bool                              finished = false;
	};
	struct Encounter
	{
		enum class Stage { Idle, Deciding, Running } stage = Stage::Idle;
		bool                                     tried = false;   // once per player down
		std::vector<std::uint32_t>               victors;
		std::vector<std::pair<std::string, std::uint32_t>> targets;   // key -> FormID; the player first
		std::vector<std::uint32_t>               held;            // scene-pacified for the encounter
		std::unordered_map<std::uint32_t, VictorChoice> choices;   // written by SkyrimNet worker threads (g_mx)
		std::unordered_map<std::uint32_t, VictorState>  vs;        // game thread only
		nlohmann::json                           targetsJson = nlohmann::json::array();
		std::string                              location;
		float                                    decideStart = 0.0f;
		std::vector<EncTurn>                     turns;
		std::size_t                              turn = 0;
		float                                    turnStart = 0.0f;
		bool                                     sceneSeen = false;
		bool                                     running = false;   // a turn is in progress
		bool                                     friendly = false;  // S352 (spec 15): companions after a won fight
		std::uint32_t                            helper = 0;        // the companion who helps the player up
	} g_enc;
	bool g_skyrimNet = false;   // FindFunctions() resolved at data load

	std::string Lower(std::string a_s)
	{
		for (auto& c : a_s) c = static_cast<char>(std::tolower(static_cast<unsigned char>(c)));
		return a_s;
	}

	std::string Trim(const std::string& a_s)
	{
		const auto b = a_s.find_first_not_of(" \t\r\n\"'`");
		if (b == std::string::npos) return {};
		const auto e = a_s.find_last_not_of(" \t\r\n\"'`");
		return a_s.substr(b, e - b + 1);
	}

	// game thread: the context of one victor's ask (offered outcomes, robbery question, keep-going history)
	std::string VictorCtx(std::uint32_t a_victor, bool a_again)
	{
		auto& st = g_enc.vs[a_victor];
		st.offered = OfferedOutcomes();
		if (g_enc.friendly) {   // S352 (spec 15, D-A45): never Execute for a companion acting on the player; Help Up instead of Leave
			std::erase_if(st.offered, [](const std::string& k) { return k == "execute" || k == "leave"; });
			st.offered.insert(st.offered.begin(), "help_up");
		}
		nlohmann::json offer = nlohmann::json::object();
		for (const auto& k : st.offered) offer[k] = true;
		st.robAsked = !g_enc.friendly && Level("out.rob") > 0 && st.robbed.size() < g_enc.targets.size();
		offer["rob"] = st.robAsked;
		std::string done;
		for (const auto& l : st.doneLines) done += (done.empty() ? "" : "; ") + l;
		{
			std::lock_guard lk(g_mx);
			g_enc.choices.erase(a_victor);
		}
		return nlohmann::json{ { "victorId", a_victor }, { "targets", g_enc.targetsJson }, { "location", g_enc.location },
			{ "offer", offer }, { "again", a_again }, { "done", done } }.dump();
	}

	void StoreChoice(std::uint32_t a_victor, std::string a_target, std::string a_top, std::unordered_map<std::string, float> a_probs,
		float a_robP, const char* a_how)
	{
		a_target = Lower(Trim(a_target));   // hard rule 9: trim before matching
		a_top = Lower(Trim(a_top));
		std::unordered_map<std::string, float> probs;
		std::string list;
		for (auto& [k, v] : a_probs) {
			const auto key = Lower(Trim(k));
			probs[key] = v;
			list += std::format("{} {:.2f} ", key, v);
		}
		SKSE::log::info("{} ENCOUNTER answer {:08X}: target={} top={} probabilities [{}] rob={:.2f} ({}).", kTag, a_victor, a_target,
			a_top, list, a_robP, a_how);
		std::lock_guard lk(g_mx);
		g_enc.choices[a_victor] = { a_target, a_top, std::move(probs), a_robP, true };
	}

	void AskFallback(std::uint32_t a_victor, const std::string& a_ctx)
	{
		if (!PublicSendCustomPromptToLLM) {
			StoreChoice(a_victor, "", "leave", {}, -1.0f, "no SkyrimNet prompt API");
			return;
		}
		const bool queued = PublicSendCustomPromptToLLM(g_enc.friendly ? "ded_downed_companion_choice" : "ded_downed_victor_choice", "", a_ctx.c_str(),
			[a_victor](const char* a_response, int a_success) {
				std::string target, top;
				std::unordered_map<std::string, float> probs;
				float rob = -1.0f;
				if (a_success == 1 && a_response) {
					const std::string r = a_response;
					const auto b = r.find('{'), e = r.rfind('}');
					const auto j = (b != std::string::npos && e != std::string::npos && e > b) ?
					                   nlohmann::json::parse(r.substr(b, e - b + 1), nullptr, false) : nlohmann::json();
					if (j.is_object()) {
						target = j.value("target", std::string{});
						float sum = 0.0f, best = -1.0f;
						if (j.contains("scores") && j["scores"].is_object()) {
							for (auto& [k, v] : j["scores"].items()) {
								const float x = v.is_number() ? std::clamp(v.get<float>(), 0.0f, 10.0f) : 0.0f;
								probs[k] = x;
								sum += x;
								if (x > best) { best = x; top = k; }
							}
						}
						if (sum > 0.0f) for (auto& [k, v] : probs) v /= sum;
						if (top.empty()) top = j.value("action", std::string{});
						if (j.contains("rob") && j["rob"].is_number()) rob = std::clamp(j["rob"].get<float>() / 10.0f, 0.0f, 1.0f);
					}
				}
				StoreChoice(a_victor, target, top.empty() ? "leave" : top, std::move(probs), rob,
					a_success == 1 ? "chat fallback" : "chat fallback failed");
			});
		if (!queued) StoreChoice(a_victor, "", "leave", {}, -1.0f, "chat fallback not queued");
	}

	void AskVictor(std::uint32_t a_victor, const std::string& a_ctx)
	{
		if (!PublicSendCustomDecisionToLLM) {
			AskFallback(a_victor, a_ctx);
			return;
		}
		const bool queued = PublicSendCustomDecisionToLLM(g_enc.friendly ? "ded_downed/companion_choice" : "ded_downed/victor_choice", a_ctx.c_str(), 0,
			[a_victor, a_ctx](const char*, const char* a_json, int a_success) {
				if (a_success == 1 && a_json) {
					const auto j = nlohmann::json::parse(a_json, nullptr, false);
					std::string target, top;
					std::unordered_map<std::string, float> probs;
					float rob = -1.0f;
					if (j.is_object() && j.contains("answers")) {
						const auto& an = j["answers"];
						if (an.contains("target")) target = an["target"].value("choice", std::string{});
						if (an.contains("action")) {
							top = an["action"].value("choice", std::string{});
							if (an["action"].contains("probabilities") && an["action"]["probabilities"].is_object())
								for (auto& [k, v] : an["action"]["probabilities"].items())
									if (v.is_number()) probs[k] = v.get<float>();
						}
						if (an.contains("rob") && an["rob"].contains("noul") && an["rob"]["noul"].is_number()) rob = an["rob"]["noul"].get<float>();
					}
					StoreChoice(a_victor, target, top, std::move(probs), rob, "decision");
					return;
				}
				SKSE::log::info("{} ENCOUNTER decision failed for {:08X} ({}) -> chat fallback.", kTag, a_victor, a_json ? a_json : "");
				AskFallback(a_victor, a_ctx);
			});
		if (!queued) AskFallback(a_victor, a_ctx);
	}

	// game thread: D-A66 / D-A67 -> (target, outcome, rob as well)
	struct Pick
	{
		std::uint32_t target = 0;
		std::string   action = "leave";
		bool          rob = false;
	};
	Pick Roll(std::uint32_t a_victor, const VictorChoice& a_c)
	{
		auto& st = g_enc.vs[a_victor];
		Pick p;
		p.target = g_enc.targets.front().second;   // an unknown key falls back to the player
		for (const auto& [key, id] : g_enc.targets)
			if (key == a_c.target) p.target = id;
		const auto offered = [&](const std::string& k) { return std::find(st.offered.begin(), st.offered.end(), k) != st.offered.end(); };
		const bool weighted = Setting("encounter.weighted") >= 0.5f;
		std::string why;
		if (!weighted || a_c.probs.empty()) {
			p.action = offered(a_c.top) ? a_c.top : "leave";
			why = weighted ? "no probabilities: the AI's pick" : "unweighted: the AI's pick";
		} else {
			std::vector<std::pair<std::string, float>> w;
			float sum = 0.0f;
			for (const auto& k : st.offered) {
				const auto it = a_c.probs.find(k);
				const float pr = it != a_c.probs.end() ? it->second : 0.0f;
				const float m = k == "help_up" ? 3.0f : kLevelMult[Level(std::format("out.{}", k).c_str())];   // S352: Help Up x3 (D-A45)
				w.emplace_back(k, pr * m);
				sum += pr * m;
				why += std::format("{} {:.2f}x{} ", k, pr, m);
			}
			if (sum <= 0.0f) {
				p.action = offered(a_c.top) ? a_c.top : "leave";
				why += "-> all zero: the AI's pick";
			} else {
				float r = std::uniform_real_distribution<float>(0.0f, sum)(g_rng);
				for (const auto& [k, x] : w) {
					p.action = k;
					if ((r -= x) <= 0.0f) break;
				}
			}
		}
		if (g_enc.friendly && p.action == "execute") {   // S352 (D-A45): the hard blacklist
			SKSE::log::info("{} COMPANION {:08X} answered execute - never for a companion on the player -> help_up.", kTag, a_victor);
			p.action = "help_up";
		}
		if (g_enc.friendly && p.action == "leave") p.action = "help_up";
		std::string robWhy = "not asked";
		if (st.robAsked && a_c.robP >= 0.0f && !st.robbed.contains(p.target)) {
			float pr = a_c.robP;
			if (weighted) {
				const float m = kLevelMult[Level("out.rob")];
				pr = (pr * m) / (pr * m + (1.0f - pr) + 1.0e-6f);
				p.rob = std::uniform_real_distribution<float>(0.0f, 1.0f)(g_rng) < pr;
			} else {
				p.rob = pr >= 0.5f;
			}
			robWhy = std::format("{:.2f} -> {:.2f} -> {}", a_c.robP, pr, p.rob ? "yes" : "no");
		}
		SKSE::log::info("{} ENCOUNTER roll {:08X}: [{}] -> {} on {:08X}; rob {}.", kTag, a_victor, why, p.action, p.target, robWhy);
		return p;
	}

	void EndEncounter(const char* a_why)
	{
		auto* pc = RE::PlayerCharacter::GetSingleton();
		const bool playerDown = pc && !pc->IsDead() && g_api->GetPhase(pc->GetFormID()) == DeDDowned::Phase::Downed;
		if (playerDown && g_enc.friendly) {   // S352 (spec 15): a companion helps the player up, no fade
			auto* h = RE::TESForm::LookupByID<RE::Actor>(g_enc.helper ? g_enc.helper : (g_enc.victors.empty() ? 0 : g_enc.victors.front()));
			g_api->ScenePacifyEnd(pc->GetFormID());
			HelpPlayerUp(pc, h, "after a won fight");
			g_enc.held.clear();
		} else if (playerDown) StartAfter(!g_enc.turns.empty(), g_enc.victors);   // S348: before the holds end (no early stand-up)
		for (const auto id : g_enc.held) g_api->ScenePacifyEnd(id);
		for (const auto& [key, id] : g_enc.targets) {
			auto* a = RE::TESForm::LookupByID<RE::Actor>(id);
			if (a && a != pc && !a->IsDead() && g_api->GetPhase(id) != DeDDowned::Phase::None) g_api->Recover(id, true);
		}
		SKSE::log::info("{} ENCOUNTER-END ({}): {} turn(s), {} held released, the downed companions are up{}.", kTag, a_why,
			g_enc.turns.size(), g_enc.held.size(), playerDown ? ", the player's \"after\" runs" : "");
		g_encounter = false;
		g_enc.stage = Encounter::Stage::Idle;
		g_enc.victors.clear();
		g_enc.targets.clear();
		g_enc.held.clear();
		g_enc.turns.clear();
		g_enc.vs.clear();
		g_enc.running = false;
		g_enc.friendly = false;
		g_enc.helper = 0;
		{
			std::lock_guard lk(g_mx);
			g_enc.choices.clear();
		}
	}

	float TurnLength(const std::string& a_act)
	{
		if (a_act == "rob") return 12.0f;
		if (a_act == "strip" || a_act == "execute") return 15.0f;
		if (a_act == "tattoo" || a_act == "makeup") return 25.0f;
		return 20.0f;   // threaten
	}

	void StartTurn()
	{
		auto* player = RE::PlayerCharacter::GetSingleton();
		const float radius = Setting("encounter.radius");
		while (g_enc.turn < g_enc.turns.size()) {
			auto& t = g_enc.turns[g_enc.turn];
			auto* target = RE::TESForm::LookupByID<RE::Actor>(t.target);
			std::vector<RE::Actor*> ok;
			for (const auto v : t.victors) {
				auto* a = RE::TESForm::LookupByID<RE::Actor>(v);
				if (a && !a->IsDead() && !a->IsInCombat() && target && a->GetDistance(target) <= radius * 1.5f) ok.push_back(a);
			}
			if (!target || target->IsDead() || g_api->GetPhase(t.target) != DeDDowned::Phase::Downed || ok.empty()) {
				SKSE::log::info("{} ENCOUNTER turn {} skipped (target or victors gone).", kTag, g_enc.turn + 1);
				++g_enc.turn;
				continue;
			}
			g_enc.turnStart = Now();
			g_enc.sceneSeen = false;
			g_enc.running = true;
			const std::string tn = NameOf(target);
			for (auto* a : ok) {
				auto& st = g_enc.vs[a->GetFormID()];
				if (t.action == "rob") {
					st.robbed.insert(t.target);
					st.doneLines.push_back("robbed " + tn);
				} else {
					++st.turns;
					st.doneLines.push_back(t.action == "sex" ? "taken " + tn + " sexually" : t.action + " (" + tn + ")");
				}
			}
			SKSE::log::info("{} ENCOUNTER turn {} / {}: {} victor(s) -> {} on {}{}.", kTag, g_enc.turn + 1, g_enc.turns.size(),
				ok.size(), t.action, Name(target), target == player ? " (the player)" : "");
			if (t.action == "sex") {
				for (auto* a : ok) SendModEvent("DeD_DownedVictorJoin", a, "");
				SendModEvent("DeD_DownedVictorTurn", target, std::format("sex|{}", ok.size()));
			} else if (t.action == "rob") {
				Narrate("ded_downed_robbed", Rob(ok.front(), target), ok.front(), target);
			} else if (t.action == "threaten") {
				Narrate("ded_downed_threat", std::format("{} stands over the beaten {}, threatening, taunting and humiliating them.",
					NameOf(ok.front()), tn), ok.front(), target);
			} else {   // S351: Baka's outcomes (strip, tattoo, makeup, execute)
				SendModEvent("DeD_DownedVictorJoin", ok.front(), "");
				SendModEvent("DeD_DownedVictorAct", target, t.action);
			}
			return;
		}
	}

	// keep-going (D-A68): ask a victor again after their outcome turn
	void AskAgain(std::uint32_t a_victor)
	{
		auto& st = g_enc.vs[a_victor];
		auto* a = RE::TESForm::LookupByID<RE::Actor>(a_victor);
		const int cap = static_cast<int>(Setting("encounter.maxturns"));
		if (st.finished || st.pending) return;
		if (!a || a->IsDead() || a->IsInCombat() || st.turns >= cap) {
			st.finished = true;
			SKSE::log::info("{} ENCOUNTER {:08X} is done ({}).", kTag, a_victor, st.turns >= cap ? "most turns reached" : "gone or fighting");
			return;
		}
		st.pending = true;
		st.askedAt = Now();
		SKSE::log::info("{} ENCOUNTER {:08X} asked again (turn {} of at most {}).", kTag, a_victor, st.turns + 1, cap);
		AskVictor(a_victor, VictorCtx(a_victor, true));
	}

	void QueuePick(std::uint32_t a_victor, const Pick& a_p, std::vector<EncTurn>& a_rob, std::vector<EncTurn>& a_other,
		std::unordered_map<std::uint32_t, std::vector<std::uint32_t>>* a_sexBy)
	{
		if (a_p.rob) a_rob.push_back({ { a_victor }, a_p.target, "rob" });
		if (a_p.action == "help_up") {   // S352: a companion helps the player up (at the encounter's end)
			g_enc.vs[a_victor].finished = true;
			if (!g_enc.helper) g_enc.helper = a_victor;
			SKSE::log::info("{} COMPANION-RESCUE choice=help_up ({:08X}).", kTag, a_victor);
		} else if (a_p.action == "leave") {
			g_enc.vs[a_victor].finished = true;
		} else if (a_p.action == "sex" && a_sexBy) {
			(*a_sexBy)[a_p.target].push_back(a_victor);
		} else {
			a_other.push_back({ { a_victor }, a_p.target, a_p.action });
		}
	}

	void PlanTurns()
	{
		std::unordered_map<std::uint32_t, VictorChoice> choices;
		{
			std::lock_guard lk(g_mx);
			choices = g_enc.choices;
		}
		const int maxPartners = static_cast<int>(Setting("encounter.maxpartners"));
		const int groupChance = static_cast<int>(Setting("encounter.groupchance"));
		std::unordered_map<std::uint32_t, std::vector<std::uint32_t>> sexBy;
		std::vector<EncTurn> robs, other;
		for (const auto v : g_enc.victors) {
			const auto it = choices.find(v);
			if (it == choices.end() || !it->second.done) {
				SKSE::log::info("{} ENCOUNTER {:08X}: no answer in time -> leave.", kTag, v);
				g_enc.vs[v].finished = true;
				continue;
			}
			QueuePick(v, Roll(v, it->second), robs, other, &sexBy);
		}
		g_enc.turns.clear();
		g_enc.turns.insert(g_enc.turns.end(), robs.begin(), robs.end());   // robbery first, then what they do
		g_enc.turns.insert(g_enc.turns.end(), other.begin(), other.end());
		for (auto& [target, vs] : sexBy) {
			std::size_t i = 0;
			if (vs.size() >= 2 && maxPartners >= 3) {
				const int roll = std::uniform_int_distribution<int>(0, 99)(g_rng);
				const bool group = roll < groupChance;
				SKSE::log::info("{} ENCOUNTER group roll for {:08X}: {} want them, chance {} roll {} -> {}.", kTag, target,
					vs.size(), groupChance, roll, group ? "group scene" : "turns");
				if (group) {
					EncTurn t{ {}, target, "sex" };
					for (; i < vs.size() && static_cast<int>(t.victors.size()) < maxPartners - 1; ++i) t.victors.push_back(vs[i]);
					g_enc.turns.push_back(t);
				}
			}
			for (; i < vs.size(); ++i) g_enc.turns.push_back({ { vs[i] }, target, "sex" });
		}
		g_enc.stage = Encounter::Stage::Running;
		g_enc.turn = 0;
		SKSE::log::info("{} ENCOUNTER plan: {} turn(s){}.", kTag, g_enc.turns.size(),
			Setting("encounter.keepgoing") >= 0.5f ? std::format(", keep going on (at most {} per victor)", static_cast<int>(Setting("encounter.maxturns"))) : std::string());
		StartTurn();
	}

	// keep-going answers that came back: their next turns go to the end of the queue
	void TakeAgainAnswers()
	{
		for (auto& [v, st] : g_enc.vs) {
			if (!st.pending) continue;
			VictorChoice c;
			{
				std::lock_guard lk(g_mx);
				if (const auto it = g_enc.choices.find(v); it != g_enc.choices.end() && it->second.done) c = it->second;
			}
			if (!c.done) {
				if (Now() - st.askedAt > 25.0f) {
					st.pending = false;
					st.finished = true;
					SKSE::log::info("{} ENCOUNTER {:08X}: no answer in time -> done.", kTag, v);
				}
				continue;
			}
			st.pending = false;
			std::vector<EncTurn> robs, other;
			QueuePick(v, Roll(v, c), robs, other, nullptr);
			if (st.finished) SKSE::log::info("{} ENCOUNTER {:08X} has had enough.", kTag, v);
			g_enc.turns.insert(g_enc.turns.end(), robs.begin(), robs.end());
			g_enc.turns.insert(g_enc.turns.end(), other.begin(), other.end());
		}
	}

	bool AnyPending()
	{
		for (const auto& [v, st] : g_enc.vs) if (st.pending) return true;
		return false;
	}

	void StartEncounter(RE::PlayerCharacter* a_player)
	{
		const float radius = Setting("encounter.radius");
		std::vector<std::pair<float, RE::Actor*>> victors;
		std::vector<RE::Actor*> companions;
		if (auto* pl = RE::ProcessLists::GetSingleton()) {
			pl->ForEachHighActor([&](RE::Actor* a) {
				if (!a || a == a_player || a->IsDead()) return RE::BSContainer::ForEachResult::kContinue;
				const float d = a->GetDistance(a_player);
				if (d > radius) return RE::BSContainer::ForEachResult::kContinue;
				if (IsCompanion(a)) {
					companions.push_back(a);
				} else if (IsHumanoid(a) && g_api->GetPhase(a->GetFormID()) == DeDDowned::Phase::None && a->IsHostileToActor(a_player)) {
					victors.emplace_back(d, a);
				}
				return RE::BSContainer::ForEachResult::kContinue;
			});
		}
		if (victors.empty()) {
			SKSE::log::info("{} ENCOUNTER: no victor within {:.0f} units - you stay down until your timer.", kTag, radius);
			return;
		}
		std::sort(victors.begin(), victors.end(), [](const auto& x, const auto& y) { return x.first < y.first; });
		if (victors.size() > 6) victors.resize(6);
		g_encounter = true;
		g_enc.stage = Encounter::Stage::Deciding;
		g_enc.targets.clear();
		g_enc.targets.emplace_back("t0", a_player->GetFormID());
		for (auto* c : companions)
			if (g_api->GetPhase(c->GetFormID()) == DeDDowned::Phase::Downed)
				g_enc.targets.emplace_back(std::format("t{}", g_enc.targets.size()), c->GetFormID());
		g_enc.held.push_back(a_player->GetFormID());
		for (auto* c : companions) g_enc.held.push_back(c->GetFormID());
		for (const auto id : g_enc.held) g_api->ScenePacifyBegin(id);
		nlohmann::json targets = nlohmann::json::array();
		for (const auto& [key, id] : g_enc.targets) {
			auto* a = RE::TESForm::LookupByID<RE::Actor>(id);
			const char* n = a ? a->GetDisplayFullName() : nullptr;
			targets.push_back({ { "key", key }, { "id", id }, { "name", (n && *n) ? n : "?" }, { "player", a == a_player } });
		}
		std::string location;
		if (auto* loc = a_player->GetCurrentLocation(); loc && loc->GetName()) location = loc->GetName();
		{
			std::lock_guard lk(g_mx);
			g_enc.choices.clear();
		}
		g_enc.victors.clear();
		for (auto& [d, a] : victors) {
			a->StopCombat();
			g_enc.victors.push_back(a->GetFormID());
		}
		g_enc.decideStart = Now();
		SKSE::log::info("{} ENCOUNTER-START: {} victor(s), {} downed target(s), {} held (you + companions in {:.0f} units); "
		                "decisions via {}.", kTag, g_enc.victors.size(), g_enc.targets.size(), g_enc.held.size(), radius,
			PublicSendCustomDecisionToLLM ? "the decision model" : "the chat fallback");
		g_enc.targetsJson = targets;
		g_enc.location = location;
		for (const auto v : g_enc.victors) AskVictor(v, VictorCtx(v, false));
	}


	// ---- S352 (A4 leg 5, spec 15 / 7.1): companions and beaten enemies ----
	void HelpPlayerUp(RE::PlayerCharacter* a_pc, RE::Actor* a_helper, const char* a_how)
	{
		auto* av = a_pc->AsActorValueOwner();
		const float max = av->GetPermanentActorValue(RE::ActorValue::kHealth);
		const float cur = av->GetActorValue(RE::ActorValue::kHealth);
		if (cur < max * 0.35f) av->RestoreActorValue(RE::ActorValue::kHealth, max * 0.35f - cur);
		g_api->Recover(a_pc->GetFormID(), true);
		if (a_helper) Narrate("ded_companion_rescue", std::format("{} helps {} back to their feet.", NameOf(a_helper), NameOf(a_pc)), a_helper, a_pc);
		SKSE::log::info("{} COMPANION-RESCUE helpup: {} helps the player up ({}).", kTag, a_helper ? Name(a_helper) : std::string("nobody"), a_how);
	}

	struct FightState
	{
		std::vector<RE::Actor*> companionsUp;   // companions near, alive, not down
		std::vector<RE::Actor*> hostiles;       // anyone hostile to the player near, alive, not down
	};
	FightState Fight(RE::PlayerCharacter* a_pc)
	{
		FightState f;
		const float radius = Setting("encounter.radius");
		if (auto* pl = RE::ProcessLists::GetSingleton()) {
			pl->ForEachHighActor([&](RE::Actor* a) {
				if (!a || a == a_pc || a->IsDead() || a->GetDistance(a_pc) > radius) return RE::BSContainer::ForEachResult::kContinue;
				if (g_api->GetPhase(a->GetFormID()) != DeDDowned::Phase::None) return RE::BSContainer::ForEachResult::kContinue;
				if (IsCompanion(a)) f.companionsUp.push_back(a);
				else if (a->IsHostileToActor(a_pc) && !g_api->IsNonViolent(a->GetFormID())) f.hostiles.push_back(a);
				return RE::BSContainer::ForEachResult::kContinue;
			});
		}
		return f;
	}

	// a restoration spell that heals someone else (not self-only, not hostile), known to the companion
	RE::SpellItem* HealSpell(RE::Actor* a_c)
	{
		auto ok = [](RE::SpellItem* sp) {
			if (!sp || sp->GetSpellType() != RE::MagicSystem::SpellType::kSpell || sp->GetDelivery() == RE::MagicSystem::Delivery::kSelf) return false;
			for (auto* e : sp->effects)
				if (e && e->baseEffect && !e->baseEffect->IsHostile() && !e->baseEffect->IsDetrimental() &&
					(e->baseEffect->GetArchetype() == RE::EffectSetting::Archetype::kValueModifier ||
						e->baseEffect->GetArchetype() == RE::EffectSetting::Archetype::kPeakValueModifier) &&
					e->baseEffect->data.primaryAV == RE::ActorValue::kHealth)
					return true;
			return false;
		};
		for (auto* sp : a_c->GetActorRuntimeData().addedSpells) if (ok(sp)) return sp;
		if (auto* npc = a_c->GetActorBase(); npc && npc->GetSpellList() && npc->GetSpellList()->spells)
			for (std::uint32_t i = 0; i < npc->GetSpellList()->numSpells; ++i)
				if (ok(npc->GetSpellList()->spells[i])) return npc->GetSpellList()->spells[i];
		return nullptr;
	}

	std::unordered_map<std::uint32_t, float> g_healNext;   // companion -> earliest next heal try

	// the fight goes on around the downed player: companions may heal them back into it (spec 15, D-A38)
	void RescueTick(RE::PlayerCharacter* a_pc, const FightState& a_f)
	{
		for (auto* c : a_f.companionsUp) {
			const auto id = c->GetFormID();
			if (Now() < g_healNext[id] || c->GetDistance(a_pc) > 2500.0f) continue;
			if (std::uniform_int_distribution<int>(0, 99)(g_rng) >= 8) continue;   // about one try per 12 s per companion
			g_healNext[id] = Now() + 20.0f;
			std::string how;
			if (auto* sp = HealSpell(c)) {
				if (auto* mc = c->GetMagicCaster(RE::MagicSystem::CastingSource::kInstant))
					mc->CastSpellImmediate(sp, false, a_pc, 1.0f, false, 0.0f, c);
				how = std::format("casts {} on", sp->GetName());
			} else if (g_api->HelpUpHealing(id, true) == 1) {
				how = "gives a healing draught to";
			} else {
				g_healNext[id] = Now() + 30.0f;
				SKSE::log::info("{} COMPANION-RESCUE {}: no healing spell or potion.", kTag, Name(c));
				continue;
			}
			SKSE::log::info("{} COMPANION-RESCUE heal: {} {} the player -> back in the fight.", kTag, Name(c), how);
			Narrate("ded_companion_rescue", std::format("In the middle of the fight {} {} the fallen {} and pulls them back into it.", NameOf(c), how, NameOf(a_pc)), c, a_pc);
			auto* av = a_pc->AsActorValueOwner();
			const float max = av->GetPermanentActorValue(RE::ActorValue::kHealth);
			const float cur = av->GetActorValue(RE::ActorValue::kHealth);
			if (cur < max * 0.35f) av->RestoreActorValue(RE::ActorValue::kHealth, max * 0.35f - cur);
			g_api->Recover(a_pc->GetFormID(), true);
			return;
		}
	}

	// spec 15 "Off": the party gives up with the player
	void PartySurrender(RE::PlayerCharacter* a_pc, std::uint32_t a_aggressor)
	{
		const auto f = Fight(a_pc);
		int n = 0;
		for (auto* c : f.companionsUp)
			if (g_api->DownActor(c->GetFormID(), a_aggressor, "surrender")) ++n;
		if (n > 0) Narrate("ded_party_surrender", std::format("With {} down, {} gives up the fight and goes down too.", NameOf(a_pc),
			n == 1 ? NameOf(f.companionsUp.front()) : std::string("the rest of the party")), a_pc, nullptr);
		SKSE::log::info("{} PARTY-SURRENDER count={}.", kTag, n);
	}

	// spec 7.1: a beaten enemy (hostile to the player when downed) decides at the end of Recovering
	std::unordered_set<std::uint32_t>        g_hostileAtDown;
	std::unordered_map<std::uint32_t, float> g_parley;   // asked -> when (game thread)

	void ParleyAnswer(std::uint32_t a_id, std::string a_decision, std::string a_reason)
	{
		if (!g_parley.erase(a_id)) return;   // timed out already
		g_api->ScenePacifyEnd(a_id);
		a_decision = Lower(Trim(a_decision));   // hard rule 9
		auto* a = RE::TESForm::LookupByID<RE::Actor>(a_id);
		const bool stand = a_decision == "stand_down" && a && !a->IsDead();
		SKSE::log::info("{} PARLEY {}: {} ({}).", kTag, a ? Name(a) : std::string("?"), stand ? "stand_down" : std::format("hostile [{}]", a_decision), a_reason);
		if (!stand) return;
		g_api->SetNonViolent(a_id, true);
		if (auto* pl = RE::ProcessLists::GetSingleton()) {
			pl->ForEachHighActor([&](RE::Actor* x) {
				if (x && (x->IsPlayerRef() || IsCompanion(x)) && x->GetActorRuntimeData().currentCombatTarget.get().get() == a) x->StopCombat();
				return RE::BSContainer::ForEachResult::kContinue;
			});
		}
		auto* pc = RE::PlayerCharacter::GetSingleton();
		if (PublicRegisterEvent && pc)
			PublicRegisterEvent("ded_downed_parley", std::format("{} has decided not to fight {} again{}.", NameOf(a), NameOf(pc),
				a_reason.empty() ? "" : " (" + a_reason + ")").c_str(), a_id, pc->GetFormID(), nullptr, 0);
	}

	void AskParley(RE::Actor* a)
	{
		const auto id = a->GetFormID();
		auto* pc = RE::PlayerCharacter::GetSingleton();
		std::string dialogue = PublicGetRecentDialogue ? PublicGetRecentDialogue(id, 8) : std::string();
		std::string location;
		if (auto* loc = pc ? pc->GetCurrentLocation() : nullptr; loc && loc->GetName()) location = loc->GetName();
		const nlohmann::json ctx{ { "npcId", id }, { "dialogue", dialogue }, { "location", location } };
		g_api->ScenePacifyBegin(id);   // no attack while they decide
		g_parley[id] = Now();
		SKSE::log::info("{} PARLEY asked for {} ({} chars of recent dialogue).", kTag, Name(a), dialogue.size());
		const bool queued = PublicSendCustomPromptToLLM && PublicSendCustomPromptToLLM("ded_downed_parley", "", ctx.dump().c_str(),
			[id](const char* a_response, int a_success) {
				std::string decision, reason;
				if (a_success == 1 && a_response) {
					const std::string r = a_response;
					const auto b = r.find('{'), e = r.rfind('}');
					const auto j = (b != std::string::npos && e != std::string::npos && e > b) ?
					                   nlohmann::json::parse(r.substr(b, e - b + 1), nullptr, false) : nlohmann::json();
					if (j.is_object()) {
						decision = j.value("decision", std::string{});
						reason = j.value("reason", std::string{});
					}
				}
				SKSE::GetTaskInterface()->AddTask([id, decision, reason]() { ParleyAnswer(id, decision, reason); });
			});
		if (!queued) ParleyAnswer(id, "hostile", "no SkyrimNet prompt API");
	}

	void UpdateParleys()
	{
		std::vector<std::uint32_t> late;
		for (const auto& [id, t] : g_parley) if (Now() - t > 20.0f) late.push_back(id);
		for (const auto id : late) ParleyAnswer(id, "hostile", "no answer in 20 s");
	}

	// D-A32: attacking someone who stood down makes them an enemy again
	struct HitSink : RE::BSTEventSink<RE::TESHitEvent>
	{
		RE::BSEventNotifyControl ProcessEvent(const RE::TESHitEvent* a_ev, RE::BSTEventSource<RE::TESHitEvent>*) override
		{
			if (!a_ev || !a_ev->target || !a_ev->cause || !Active()) return RE::BSEventNotifyControl::kContinue;
			auto* t = a_ev->target->As<RE::Actor>();
			auto* c = a_ev->cause->As<RE::Actor>();
			if (!t || !c || !(c->IsPlayerRef() || IsCompanion(c)) || !g_api->IsNonViolent(t->GetFormID())) return RE::BSEventNotifyControl::kContinue;
			const auto id = t->GetFormID();
			SKSE::GetTaskInterface()->AddTask([id]() {
				g_api->SetNonViolent(id, false);
				SKSE::log::info("{} PARLEY undone: {:08X} was attacked by your side (D-A32).", kTag, id);
			});
			return RE::BSEventNotifyControl::kContinue;
		}
	};
	HitSink g_hitSink;

	void StartCompanions(RE::PlayerCharacter* a_pc, std::vector<RE::Actor*> a_comps)
	{
		std::sort(a_comps.begin(), a_comps.end(), [&](RE::Actor* x, RE::Actor* y) { return x->GetDistance(a_pc) < y->GetDistance(a_pc); });
		if (Setting("companions.advantage") < 0.5f || !g_skyrimNet || (!PublicSendCustomDecisionToLLM && !PublicSendCustomPromptToLLM)) {
			HelpPlayerUp(a_pc, a_comps.front(), "your side won");
			return;
		}
		if (a_comps.size() > 4) a_comps.resize(4);
		g_encounter = true;
		g_enc.friendly = true;
		g_enc.helper = 0;
		g_enc.stage = Encounter::Stage::Deciding;
		g_enc.targets.clear();
		g_enc.targets.emplace_back("t0", a_pc->GetFormID());
		g_enc.held = { a_pc->GetFormID() };
		g_api->ScenePacifyBegin(a_pc->GetFormID());
		const char* n = a_pc->GetDisplayFullName();
		g_enc.targetsJson = nlohmann::json::array({ { { "key", "t0" }, { "id", a_pc->GetFormID() }, { "name", (n && *n) ? n : "?" }, { "player", true } } });
		g_enc.location.clear();
		if (auto* loc = a_pc->GetCurrentLocation(); loc && loc->GetName()) g_enc.location = loc->GetName();
		g_enc.victors.clear();
		for (auto* c : a_comps) g_enc.victors.push_back(c->GetFormID());
		g_enc.decideStart = Now();
		SKSE::log::info("{} COMPANIONS after a won fight: {} companion(s) decide (Companions may take advantage).", kTag, g_enc.victors.size());
		for (const auto v : g_enc.victors) AskVictor(v, VictorCtx(v, false));
	}

	void UpdateEncounter()
	{
		auto* player = RE::PlayerCharacter::GetSingleton();
		if (!player) return;
		const bool down = g_api->GetPhase(player->GetFormID()) == DeDDowned::Phase::Downed && !player->IsDead();
		if (g_enc.stage == Encounter::Stage::Idle) {
			if (!down) {
				g_enc.tried = false;
				return;
			}
			float since = 0.0f;
			{
				std::lock_guard lk(g_mx);
				if (const auto it = g_downAt.find(player->GetFormID()); it != g_downAt.end()) since = Now() - it->second;
				else since = 99.0f;
			}
			if (!g_enc.tried && since >= 3.0f) {
				// S352 (spec 15): the encounter waits until the fight is lost; companions still up may heal the player
				const auto f = Fight(player);
				const bool resist = Setting("companions.resist") >= 0.5f;
				if (!f.hostiles.empty() && !f.companionsUp.empty() && resist) {
					RescueTick(player, f);
					return;
				}
				g_enc.tried = true;
				if (!f.hostiles.empty()) {
					if (g_skyrimNet) StartEncounter(player);
				} else if (!f.companionsUp.empty()) {
					StartCompanions(player, f.companionsUp);
				} else {
					SKSE::log::info("{} DOWNED: nobody near - you stay down until your timer.", kTag);
				}
			}
			return;
		}
		if (!down) {
			EndEncounter(player->IsDead() ? "the player died" : "the player is no longer down");
			return;
		}
		if (g_enc.stage == Encounter::Stage::Deciding) {
			std::size_t answered = 0;
			{
				std::lock_guard lk(g_mx);
				for (const auto& [v, c] : g_enc.choices)
					if (c.done) ++answered;
			}
			if (answered >= g_enc.victors.size() || Now() - g_enc.decideStart > 25.0f) PlanTurns();
			return;
		}
		TakeAgainAnswers();
		// Running: no turn in progress -> the next queued one, else wait for keep-going answers, else the end
		if (!g_enc.running) {
			if (g_enc.turn < g_enc.turns.size()) StartTurn();
			if (!g_enc.running && !AnyPending()) EndEncounter("every turn done");
			return;
		}
		const auto& cur = g_enc.turns[g_enc.turn];
		auto* target = RE::TESForm::LookupByID<RE::Actor>(cur.target);
		const bool inScene = target && InScene(target);
		if (inScene) g_enc.sceneSeen = true;
		const float t = Now() - g_enc.turnStart;
		const char* why = nullptr;
		if (cur.action != "sex") {   // S349 / S351: timed turns
			if (t > TurnLength(cur.action)) why = "done";
		} else if (g_enc.sceneSeen && !inScene) why = "scene over";
		else if (!g_enc.sceneSeen && t > 15.0f) why = "no scene started";
		else if (t > Setting("encounter.turncap")) why = "turn time cap";
		if (why) {
			SKSE::log::info("{} ENCOUNTER turn {} ({}) ends ({}, {:.0f} s).", kTag, g_enc.turn + 1, cur.action, why, t);
			const auto ended = cur;
			g_enc.running = false;
			++g_enc.turn;
			if (Setting("encounter.keepgoing") >= 0.5f && ended.action != "rob")
				for (const auto v : ended.victors) AskAgain(v);
			if (g_enc.turn < g_enc.turns.size()) StartTurn();
		}
	}

	// ---- H4: timers ----
	struct PlayerUpdate
	{
		static void thunk(RE::PlayerCharacter* a_this, float a_delta)
		{
			func(a_this, a_delta);
			if (!Active()) return;
			g_api->Tick(a_delta);
			static float acc = 0.0f;
			acc += a_delta;
			if (acc >= 1.0f) {
				const float dt = acc;
				acc = 0.0f;
				HoldInjured();
				WatchDowned(dt);   // S345 (D-A60)
				UpdateEncounter();   // S347 (spec 19.2)
				UpdateAssaults();    // S349 (D-A53)
				UpdateParleys();     // S352 (spec 7.1)
				if (auto* pc = RE::PlayerCharacter::GetSingleton()) UpdateAfter(pc);   // S348 (spec 19.4)
			}
		}
		static inline REL::Relocation<decltype(thunk)> func;
	};

	// ---- H5: activation on a Downed actor opens the DeD panel on them ----
	struct ActivateNPC
	{
		static bool thunk(RE::TESNPC* a_this, RE::TESObjectREFR* a_target, RE::TESObjectREFR* a_activator,
			std::uint8_t a_arg3, RE::TESBoundObject* a_object, std::int32_t a_count)
		{
			auto* actor = a_target ? a_target->As<RE::Actor>() : nullptr;
			if (Active() && actor && a_activator && a_activator->IsPlayerRef() && !actor->IsDead() &&
				g_api->IsDowned(actor->GetFormID())) {
				if (g_api->ConsumeTalkPass(actor->GetFormID())) {   // S344 (D-A47): the downed menu's Talk
					SKSE::log::info("{} ACTIVATE downed {} -> Talk (dialogue).", kTag, Name(actor));
					return func(a_this, a_target, a_activator, a_arg3, a_object, a_count);
				}
				const bool opened = g_ui && g_ui->OpenPanelEx(0x14, actor->GetFormID(), DeDUI::kPanelTargetGiven);
				SKSE::log::info("{} ACTIVATE downed {} -> DeD panel {}.", kTag, Name(actor), opened ? "opened" : "NOT available");
				SendModEvent("DeD_DownedActivate", actor, "player");
				return true;
			}
			return func(a_this, a_target, a_activator, a_arg3, a_object, a_count);
		}
		static inline REL::Relocation<decltype(thunk)> func;
	};

	// ---- poses and the player's controls (game thread, from DeDService's events) ----
	void PlayerControls(bool a_downed, bool a_fighting)
	{
		auto* map = RE::ControlMap::GetSingleton();
		if (!map) return;
		using F = RE::UserEvents::USER_EVENT_FLAG;
		for (const auto f : { F::kMovement, F::kActivate, F::kJumping, F::kSneaking })
			map->ToggleControls(f, !a_downed, false);
		map->ToggleControls(F::kFighting, a_fighting, false);
	}

	void PoseDown(RE::Actor* a_actor)
	{
		{
			std::lock_guard lk(g_mx);
			g_downHp[a_actor->GetFormID()] = 1.0f;   // S345: heal watch starts at the floor
		}
		a_actor->StopCombat();
		a_actor->NotifyAnimationGraph("BleedOutStart");
		if (a_actor->IsPlayerRef()) PlayerControls(true, false);
		std::lock_guard lk(g_mx);
		g_posed.insert(a_actor->GetFormID());
	}

	void PoseUp(RE::Actor* a_actor, bool a_pacified)
	{
		bool posed = false;
		{
			std::lock_guard lk(g_mx);
			posed = g_posed.erase(a_actor->GetFormID()) > 0;
			g_downHp.erase(a_actor->GetFormID());
			if (!a_pacified) g_downAt.erase(a_actor->GetFormID());
		}
		if (posed) a_actor->NotifyAnimationGraph("BleedOutStop");
		if (a_actor->IsPlayerRef()) PlayerControls(false, !a_pacified);
		if (!a_actor->IsPlayerRef()) a_actor->EvaluatePackage();
	}

	struct ModEventSink : RE::BSTEventSink<SKSE::ModCallbackEvent>
	{
		RE::BSEventNotifyControl ProcessEvent(const SKSE::ModCallbackEvent* a_ev, RE::BSTEventSource<SKSE::ModCallbackEvent>*) override
		{
			if (!a_ev || !Active()) return RE::BSEventNotifyControl::kContinue;
			auto* actor = a_ev->sender ? a_ev->sender->As<RE::Actor>() : nullptr;
			if (!actor) return RE::BSEventNotifyControl::kContinue;
			const std::string_view name = a_ev->eventName.c_str() ? a_ev->eventName.c_str() : "";
			const std::string_view str = a_ev->strArg.c_str() ? a_ev->strArg.c_str() : "";
			if (name == "DeD_DownedAssault") {   // S349 (D-A53): from Baka's aggressive scene start
				if (g_api->GetPhase(actor->GetFormID()) != DeDDowned::Phase::None && !actor->IsPlayerRef() && !IsCompanion(actor)) {
					g_assault[actor->GetFormID()] = { Now(), false };
					SKSE::log::info("{} ASSAULT marked on {} ({}): watching the scene (D-A53).", kTag, Name(actor), str);
				}
				return RE::BSEventNotifyControl::kContinue;
			}
			if (name == "DeD_RestraintChanged") {   // S349: log only (Baka handles its own ties)
				SKSE::log::info("{} RESTRAINT {} {}.", kTag, Name(actor), str);
				return RE::BSEventNotifyControl::kContinue;
			}
			if (name == "DeD_Downed" && str.rfind("reset:", 0) == 0) {   // S349 (D-A53): back on the ground
				{
					std::lock_guard lk(g_mx);
					g_recovering.erase(actor->GetFormID());
				}
				PoseDown(actor);
				SKSE::log::info("{} DOWN again {} ({}): pose on.", kTag, Name(actor), str);
				return RE::BSEventNotifyControl::kContinue;
			}
			if (name == "DeD_PacifyEnded") {   // S352 (spec 7.1): Recovering -> None by its timer
				const auto id = actor->GetFormID();
				if (g_hostileAtDown.erase(id) && Setting("parley.on") >= 0.5f && !actor->IsDead()) AskParley(actor);
				return RE::BSEventNotifyControl::kContinue;
			}
			if (name == "DeD_Downed") {
				if (auto* pc = RE::PlayerCharacter::GetSingleton(); pc && !actor->IsPlayerRef() && !IsCompanion(actor) && actor->IsHostileToActor(pc))
					g_hostileAtDown.insert(actor->GetFormID());   // S352: only enemies of the player get the parley
				if (actor->IsPlayerRef() && (str == "lethal" || str == "stamina") && Setting("companions.resist") < 0.5f)
					PartySurrender(actor->As<RE::PlayerCharacter>(), g_api->GetAggressor(actor->GetFormID()));   // S352 (spec 15 Off)
			}
			if (name == "DeD_Downed") {
				// the module's own downs get its pose; Baka's API downs keep Baka's own poses until A4
				// S343: Baka's hand-offs ("api:baka") too: Baka clears its own ground hold when it hands a down over
				if (str == "lethal" || str == "surrender" || str == "stamina" || str == "api:baka") {
					PoseDown(actor);
					SKSE::log::info("{} DOWN {} ({}): pose on, combat stopped{}.", kTag, Name(actor), str,
						actor->IsPlayerRef() ? ", controls off" : "");
				}
			} else if (name == "DeD_Recovering") {
				// S346 (D-A62 / D-A63, spec 19.1): no Recovering for the player or companions (companions stay pacified
				// only inside an encounter window). Until the "after" transition exists (4c) the player simply stands.
				const bool player = actor->IsPlayerRef();
				if (player && g_after.stage == 1) return RE::BSEventNotifyControl::kContinue;   // S348: the "after" stands them up
				if (player && !g_encounter.load()) {   // S348 (spec 19.4): the timer ran out with nobody staying -> the "after"
					StartAfter(false, {});
					return RE::BSEventNotifyControl::kContinue;
				}
				if (player || (IsCompanion(actor) && !g_encounter.load())) {
					SKSE::log::info("{} RECOVERING skipped for {} ({}): {} -> back to normal (spec 19.1).", kTag, Name(actor), str,
						player ? "the player" : "a companion");
					g_api->Recover(actor->GetFormID(), true);
					return RE::BSEventNotifyControl::kContinue;
				}
				PoseUp(actor, true);
				if (!actor->IsPlayerRef()) {
					std::lock_guard lk(g_mx);
					g_recovering.insert(actor->GetFormID());
				}
				SKSE::log::info("{} RECOVERING {} ({}): standing, pacified.", kTag, Name(actor), str);
			} else if (name == "DeD_Recovered" || name == "DeD_TimeSkipCleared") {
				PoseUp(actor, false);
				{
					std::lock_guard lk(g_mx);
					g_recovering.erase(actor->GetFormID());
				}
				SKSE::log::info("{} RECOVERED {} ({} {}): back to normal.", kTag, Name(actor), name, str);
			}
			return RE::BSEventNotifyControl::kContinue;
		}
	};

	// ---- H6 + death + wait / sleep ----
	struct LoadedSink : RE::BSTEventSink<RE::TESObjectLoadedEvent>
	{
		RE::BSEventNotifyControl ProcessEvent(const RE::TESObjectLoadedEvent* a_ev, RE::BSTEventSource<RE::TESObjectLoadedEvent>*) override
		{
			if (!a_ev || !a_ev->loaded || !Active() || !g_api->IsDowned(a_ev->formID)) return RE::BSEventNotifyControl::kContinue;
			const auto id = a_ev->formID;
			SKSE::GetTaskInterface()->AddTask([id]() {
				if (auto* a = RE::TESForm::LookupByID<RE::Actor>(id); a && !a->IsDead()) {
					PoseDown(a);
					SKSE::log::info("{} 3D loaded: downed pose re-applied on {}.", kTag, Name(a));
				}
			});
			return RE::BSEventNotifyControl::kContinue;
		}
	};

	struct DeathSink : RE::BSTEventSink<RE::TESDeathEvent>
	{
		RE::BSEventNotifyControl ProcessEvent(const RE::TESDeathEvent* a_ev, RE::BSTEventSource<RE::TESDeathEvent>*) override
		{
			if (!a_ev || !a_ev->dead || !a_ev->actorDying || !Active()) return RE::BSEventNotifyControl::kContinue;
			const auto id = a_ev->actorDying->GetFormID();
			if (g_api->GetPhase(id) != DeDDowned::Phase::None) {
				g_api->Release(id);
				SKSE::log::info("{} DEATH {}: downed state released.", kTag, Name(a_ev->actorDying.get()));
			}
			std::lock_guard lk(g_mx);
			g_downAt.erase(id);
			g_posed.erase(id);
			g_recovering.erase(id);
			g_downHp.erase(id);
			g_hostileAtDown.erase(id);
			g_healNext.erase(id);
			return RE::BSEventNotifyControl::kContinue;
		}
	};

	struct EquipSink : RE::BSTEventSink<RE::TESEquipEvent>
	{
		RE::BSEventNotifyControl ProcessEvent(const RE::TESEquipEvent* a_ev, RE::BSTEventSource<RE::TESEquipEvent>*) override
		{
			if (!a_ev || !a_ev->actor || !Active()) return RE::BSEventNotifyControl::kContinue;
			auto* a = a_ev->actor->As<RE::Actor>();
			if (!a || a->IsPlayerRef()) return RE::BSEventNotifyControl::kContinue;
			const auto id = a->GetFormID();
			if (g_api->GetPhase(id) == DeDDowned::Phase::None && !g_api->IsRestrained(id)) return RE::BSEventNotifyControl::kContinue;
			SKSE::GetTaskInterface()->AddTask([id]() {
				if (auto* t = RE::TESForm::LookupByID<RE::Actor>(id)) CheckRestraints(t);   // S349 (spec 8)
			});
			return RE::BSEventNotifyControl::kContinue;
		}
	};
	EquipSink g_equipSink;

	struct MenuSink : RE::BSTEventSink<RE::MenuOpenCloseEvent>
	{
		float hoursAtOpen = -1.0f;
		RE::BSEventNotifyControl ProcessEvent(const RE::MenuOpenCloseEvent* a_ev, RE::BSTEventSource<RE::MenuOpenCloseEvent>*) override
		{
			if (a_ev && !a_ev->opening && g_giveTarget && a_ev->menuName == RE::ContainerMenu::MENU_NAME) {   // S349: Give restraints
				SKSE::GetTaskInterface()->AddTask([]() { AfterGive(); });
				return RE::BSEventNotifyControl::kContinue;
			}
			if (!a_ev || !Active() || a_ev->menuName != RE::SleepWaitMenu::MENU_NAME) return RE::BSEventNotifyControl::kContinue;
			auto* cal = RE::Calendar::GetSingleton();
			if (!cal) return RE::BSEventNotifyControl::kContinue;
			if (a_ev->opening) {
				hoursAtOpen = cal->GetHoursPassed();
			} else if (hoursAtOpen >= 0.0f) {
				const float passed = cal->GetHoursPassed() - hoursAtOpen;
				hoursAtOpen = -1.0f;
				if (passed > 0.01f) g_api->TimeSkipClear(std::format("wait/sleep {:.1f} h", passed).c_str());
			}
			return RE::BSEventNotifyControl::kContinue;
		}
	};

	// ---- leg 3: the module's DeD panel section ("downed": a status page and its settings) ----
	std::string SettingsJson()
	{
		using nlohmann::json;
		json groups = json::array();
		for (const auto& d : kSettings) {
			if (groups.empty() || groups.back()["group"] != d.group) groups.push_back({ { "group", d.group }, { "settings", json::array() } });
			const float v = Setting(d.key);
			json row{ { "key", d.key }, { "label", d.label }, { "desc", d.desc } };
			if (d.toggle) {
				row["type"] = "toggle";
				row["value"] = v >= 0.5f;
			} else {
				row["type"] = "slider";
				row["value"] = v;
				row["min"] = d.min;
				row["max"] = d.max;
				row["step"] = d.step;
				row["unit"] = d.unit;
			}
			groups.back()["settings"].push_back(row);
		}
		return json{ { "module", "downed" }, { "section", "settings" }, { "settings", groups } }.dump();
	}

	std::string MainJson(std::uint32_t a_target = 0)
	{
		using nlohmann::json;
		json items = json::array();
		// S349 (spec 8): the panel opened on a downed / too-hurt / restrained person
		if (auto* t = (g_api && Active() && a_target) ? RE::TESForm::LookupByID<RE::Actor>(a_target) : nullptr;
			t && !t->IsPlayerRef() && !t->IsDead() && (g_api->GetPhase(a_target) != DeDDowned::Phase::None || g_api->IsRestrained(a_target))) {
			items.push_back({ { "id", "act:give" }, { "label", std::format("Give restraints to {}", NameOf(t)) } });
			if (g_api->IsRestrained(a_target)) items.push_back({ { "id", "act:free" }, { "label", std::format("Free {} from restraints", NameOf(t)) } });
		}
		if (g_api) {
			auto* player = RE::PlayerCharacter::GetSingleton();
			const auto& [map, lock] = RE::TESForm::GetAllForms();
			std::vector<RE::Actor*> rows;
			{
				[[maybe_unused]] const RE::BSReadLockGuard guard{ lock };
				if (map) {
					for (auto& [id, form] : *map) {
						if (!form || form->GetFormType() != RE::FormType::ActorCharacter) continue;
						if (g_api->GetPhase(id) != DeDDowned::Phase::None) rows.push_back(static_cast<RE::Actor*>(form));
					}
				}
			}
			for (auto* a : rows) {
				const bool down = g_api->GetPhase(a->GetFormID()) == DeDDowned::Phase::Downed;
				const int left = static_cast<int>(g_api->GetTimeLeft(a->GetFormID()));
				const char* n = a->GetDisplayFullName();
				std::string label = std::format("{} - {}, {} s left{}", (a == player) ? "You" : (n && *n ? n : "?"),
					down ? "down" : "too hurt to fight", left, g_api->IsRestrained(a->GetFormID()) ? ", restrained" : "");
				items.push_back({ { "id", std::format("who:{:08X}", a->GetFormID()) }, { "label", label }, { "stay", true } });
			}
		}
		json out{ { "module", "downed" }, { "section", "main" }, { "tab", "status" }, { "layout", "list" },
			{ "tabs", json::array({ { { "id", "status" }, { "label", "Downed now" } } }) },
			{ "header", { { "eyebrow", "DeD Downed" }, { "name", Active() ? "Active" : "Off" } } }, { "items", items } };
		if (!Active() && g_acheron)
			out["notice"] = { { "title", "DeD Downed is off" }, { "text", "Acheron is switched on. Turn off Acheron's Enabled option in its MCM, then save and reload; or remove Acheron after the Prepare to Remove Acheron button in the DeD MCM." } };
		else if (!Active())
			out["notice"] = { { "title", "DeD Downed is off" }, { "text", "DeD Downed could not start (see DeDDowned.log)." } };
		else if (items.empty())
			out["notice"] = { { "title", "Nobody is down" }, { "text", "People you or others beat are listed here while they are down or too hurt to fight." } };
		return out.dump();
	}

	void OnPanel(const char* a_module, const char* a_kind, const char* a_json, std::uint32_t a_target, void*)
	{
		if (!g_ui) return;
		const std::string kind = a_kind ? a_kind : "";
		const auto j = nlohmann::json::parse(a_json ? a_json : "{}", nullptr, false);
		const auto data = (!j.is_discarded() && j.contains("data") && j["data"].is_object()) ? j["data"] : nlohmann::json::object();
		const std::string section = data.value("section", std::string{ "main" });
		if (kind == "set") {
			const std::string key = data.value("key", std::string{});
			float v = 0.0f;
			bool ok = false;
			if (data.contains("value")) {
				const auto& val = data["value"];
				if (val.is_boolean()) { v = val.get<bool>() ? 1.0f : 0.0f; ok = true; }
				else if (val.is_number()) { v = val.get<float>(); ok = true; }
				else if (val.is_string()) { try { v = std::stof(val.get<std::string>()); ok = true; } catch (...) {} }
			}
			const SettingDef* def = nullptr;
			for (const auto& d : kSettings) if (key == d.key) def = &d;
			if (def && ok && g_api) {
				v = std::clamp(v, def->min, def->max);
				g_api->SetSetting(def->key, v);
				LoadSettings("panel");
			}
			nlohmann::json res{ { "key", key }, { "value", data.contains("value") ? data["value"] : nlohmann::json() }, { "ok", def && ok && g_api } };
			if (!(def && ok && g_api)) res["reason"] = "unknown setting";
			g_ui->PanelSettingResult(a_module ? a_module : "downed", res.dump().c_str());
			return;
		}
		if (kind == "act") {   // S349: restraint actions (the panel closes on a pick without "stay")
			const std::string pick = (!j.is_discarded() && j.contains("pick") && j["pick"].is_string()) ? j["pick"].get<std::string>() :
			                         data.value("pick", std::string{});
			auto* t = a_target ? RE::TESForm::LookupByID<RE::Actor>(a_target) : nullptr;
			SKSE::log::info("{} PANEL act '{}' on {}.", kTag, pick, t ? Name(t) : std::string("nobody"));
			if (t && pick == "act:give") {
				const auto id = a_target;
				SKSE::GetTaskInterface()->AddTask([id]() {
					if (auto* a = RE::TESForm::LookupByID<RE::Actor>(id)) OpenGive(a);
				});
				return;
			}
			if (t && pick == "act:free") {
				FreeRestraints(t);
				return;
			}
		}
		if (kind == "req" || kind == "act") {
			g_ui->PanelPush("downed", section == "settings" ? SettingsJson().c_str() : MainJson(a_target).c_str());
		}
	}

	ModEventSink g_modSink;
	LoadedSink   g_loadedSink;
	DeathSink    g_deathSink;
	MenuSink     g_menuSink;

	template <class T>
	void Hook(const char* a_name, REL::VariantID a_vtbl, std::size_t a_index)
	{
		REL::Relocation<std::uintptr_t> vtbl{ a_vtbl };
		T::func = vtbl.write_vfunc(a_index, T::thunk);
		SKSE::log::info("{} HOOK {} installed (vtable index 0x{:X}).", kTag, a_name, a_index);
	}

	// vanilla wounded idles for the injured look (D-A51): listed once so the pick can be made from real names
	void ListWoundedIdles()
	{
		std::uint32_t n = 0;
		const auto& [map, lock] = RE::TESForm::GetAllForms();
		[[maybe_unused]] const RE::BSReadLockGuard guard{ lock };
		if (!map) return;
		for (auto& [id, form] : *map) {
			if (!form || form->GetFormType() != RE::FormType::Idle) continue;
			auto* idle = static_cast<RE::TESIdleForm*>(form);
			std::string low = idle->formEditorID.c_str() ? idle->formEditorID.c_str() : "";
			for (auto& c : low) c = static_cast<char>(std::tolower(static_cast<unsigned char>(c)));
			if (low.find("wound") == std::string::npos && low.find("injur") == std::string::npos && low.find("hurt") == std::string::npos) continue;
			const auto* file = idle->GetFile(0);
			SKSE::log::info("{} WOUNDED-IDLE {} event='{}' plugin={}", kTag, idle->formEditorID.c_str(),
				idle->animEventName.c_str(), file ? file->fileName : "?");
			++n;
		}
		SKSE::log::info("{} WOUNDED-IDLE list: {} idle(s).", kTag, n);
	}

	void Arm()
	{
		auto* data = RE::TESDataHandler::GetSingleton();
		g_api = DeDDowned::RequestApi1();
		g_ui = DeDUI::RequestApi2();
		if (!g_api) {
			SKSE::log::warn("{} DISARMED: DeDService is missing or too old (no DeDDowned_RequestApi).", kTag);
			return;
		}
		const bool acheron = (data && (data->LookupModByName("Acheron.esm") || data->LookupModByName("Acheron.esp"))) ||
		                     ::GetModuleHandleW(L"Acheron.dll") != nullptr;
		if (g_ui) g_ui->SetPanelHandler("downed", &OnPanel, nullptr);   // also when disarmed: the section says why
		g_acheron = acheron;
		g_api->SetAcheronPresent(acheron);
		if (acheron)
			SKSE::log::warn("{} Acheron is installed: DeD Downed stays off while Acheron's own Enabled toggle is on (D-A58; "
			                "DeD_MCM reports the toggle each reload).", kTag);
		if (REL::Module::IsVR()) {
			g_api->SetModuleArmed(false);
			SKSE::log::warn("{} VR: hooks unavailable (indexes unverified), lethal-blow conversion off.", kTag);
			return;
		}
		g_slFaction = RE::TESForm::LookupByEditorID<RE::TESFaction>("SexLabAnimatingFaction");
		g_osFaction = data ? data->LookupForm<RE::TESFaction>(0xECA, "OStim.esp") : nullptr;
		g_followerFaction = RE::TESForm::LookupByID<RE::TESFaction>(0x0005C84E);   // CurrentFollowerFaction
		SKSE::log::info("{} scene factions: SexLab={} OStim={}; follower faction={}.", kTag, g_slFaction != nullptr,
			g_osFaction != nullptr, g_followerFaction != nullptr);

		Hook<HealthDamageNPC>("H1/H2 Character::HandleHealthDamage", RE::VTABLE_Character[0], 0x104);
		Hook<HealthDamagePlayer>("H1/H2 PlayerCharacter::HandleHealthDamage", RE::VTABLE_PlayerCharacter[0], 0x104);
		Hook<UpdateCombatNPC>("H3 Character::UpdateCombat", RE::VTABLE_Character[0], 0xE4);
		Hook<PlayerUpdate>("H4 PlayerCharacter::Update", RE::VTABLE_PlayerCharacter[0], 0xAD);
		Hook<ActivateNPC>("H5 TESNPC::Activate", RE::VTABLE_TESNPC[0], 0x37);

		auto* events = RE::ScriptEventSourceHolder::GetSingleton();
		events->AddEventSink<RE::TESObjectLoadedEvent>(&g_loadedSink);
		events->AddEventSink<RE::TESDeathEvent>(&g_deathSink);
		events->AddEventSink<RE::TESSleepStopEvent>(&g_sleepSink);
		events->AddEventSink<RE::TESEquipEvent>(&g_equipSink);   // S349: restraints (spec 8)
		events->AddEventSink<RE::TESHitEvent>(&g_hitSink);       // S352: D-A32   // S348: sleep clears "Wounded"
		if (auto* ui = RE::UI::GetSingleton()) ui->AddEventSink<RE::MenuOpenCloseEvent>(&g_menuSink);
		if (auto* mods = SKSE::GetModCallbackEventSource()) mods->AddEventSink(&g_modSink);

		LoadSettings("data loaded");
		g_skyrimNet = FindFunctions();   // S347: SkyrimNet public API (decisions need v12)
		SKSE::log::info("{} SkyrimNet API: {} (v{}), decisions {}.", kTag, g_skyrimNet ? "found" : "MISSING",
			g_skyrimNet && PublicGetVersion ? PublicGetVersion() : 0, PublicSendCustomDecisionToLLM ? "available" : "not available (chat fallback)");
		g_api->SetModuleArmed(true);
		g_armed = true;
		SKSE::log::info("{} ARMED: chances player {} / companions {} / NPCs {}, grace {:.1f} s, protected={}, companions may "
		                "finish={}, panel={}.", kTag, g_set.chancePlayer, g_set.chanceCompanion, g_set.chanceNPC,
			g_set.graceSeconds, g_set.downedProtected, g_set.companionsMayFinish, g_ui != nullptr);
		ListWoundedIdles();
	}

	void SetupLog()
	{
		auto dir = SKSE::log::log_directory();
		if (!dir) return;
		auto sink = std::make_shared<spdlog::sinks::basic_file_sink_mt>((*dir / "DeDDowned.log").string(), true);
		auto logger = std::make_shared<spdlog::logger>("DeDDowned", std::move(sink));
		logger->set_level(spdlog::level::trace);
		logger->flush_on(spdlog::level::trace);
		spdlog::set_default_logger(std::move(logger));
	}
}

SKSEPluginLoad(const SKSE::LoadInterface* a_skse)
{
	SKSE::Init(a_skse);
	SetupLog();
	const auto ver = REL::Module::get().version();
	SKSE::log::info("{} loaded on runtime {}.{}.{}{} (A3b leg 2 build).", kTag, ver.major(), ver.minor(), ver.patch(),
		REL::Module::IsVR() ? " VR" : "");
	SKSE::GetMessagingInterface()->RegisterListener([](SKSE::MessagingInterface::Message* a_msg) {
		if (a_msg->type == SKSE::MessagingInterface::kDataLoaded) Arm();
		if ((a_msg->type == SKSE::MessagingInterface::kPostLoadGame || a_msg->type == SKSE::MessagingInterface::kNewGame) && g_api) {
			if (g_ui) g_ui->SetPanelHandler("downed", &OnPanel, nullptr);   // lesson 50: before the first press
			if (!g_armed) return;
			LoadSettings(a_msg->type == SKSE::MessagingInterface::kNewGame ? "new game" : "save loaded");
			SyncWound("load");   // S351 (D-A69)
			if (a_msg->type == SKSE::MessagingInterface::kNewGame) {
				g_api->SetMigrated();
			} else if (Active() && !g_api->IsMigrated()) {
				// spec 14: the first armed load of a save that ran Acheron. Controls back here; DeD_MCM clears the
				// bridge's SNAcheron.* keys on its reload and marks the save migrated.
				PlayerControls(false, true);
				SKSE::log::info("{} MIGRATE: first load with DeD Downed armed - player controls restored; DeD_MCM clears the "
				                "old bridge state.", kTag);
			}
		}
	});
	return true;
}
