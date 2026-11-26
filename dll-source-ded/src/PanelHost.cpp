#include "PCH.h"
#include "PanelHost.h"
#include "ModuleRegistry.h"
#include "PanelFlags.h"
#include "EventPump.h"
#include "UIHost.h"
#include "Preview.h"

#include <algorithm>
#include <cctype>

#include <nlohmann/json.hpp>

namespace DeD
{
	namespace
	{
		using json = nlohmann::json;

		constexpr float kInteractRadius = 150.0f;   // same fallback range as the Baka DLL's pick (REV-61 tuning)
		constexpr int   kGenericMax     = 10;       // rules at or below this priority give way to the last place (3.3)

		RE::Actor* CrosshairActor()
		{
			auto* pick = RE::CrosshairPickData::GetSingleton();
			if (!pick) return nullptr;
			// VR fills a per-device array: read the headset slot. Flat uses index 0.
			const std::size_t idx = REL::Module::IsVR() ? static_cast<std::size_t>(RE::VR_DEVICE::kHeadset) : 0;
			if (auto ref = pick->targetActor[idx].get()) {
				if (auto* a = skyrim_cast<RE::Actor*>(ref.get())) return a;
			}
			if (auto ref = pick->target[idx].get()) {
				if (auto* a = skyrim_cast<RE::Actor*>(ref.get())) return a;
			}
			return nullptr;
		}

		// Nearest living non-player actor; bleedout counts as living (IsDead() is true for both).
		RE::Actor* NearestLivingActor(float a_radius)
		{
			auto* player = RE::PlayerCharacter::GetSingleton();
			auto* cell   = player ? player->GetParentCell() : nullptr;
			if (!player || !cell) return nullptr;
			const auto origin = player->GetPosition();
			RE::Actor* best   = nullptr;
			float      bestSq = a_radius * a_radius;
			cell->ForEachReferenceInRange(origin, a_radius, [&](RE::TESObjectREFR* refr) -> RE::BSContainer::ForEachResult {
				auto* a = skyrim_cast<RE::Actor*>(refr);
				if (!a || a->IsPlayerRef() || (a->IsDead() && !a->IsBleedingOut())) return RE::BSContainer::ForEachResult::kContinue;
				const auto  p  = a->GetPosition();
				const float dx = p.x - origin.x, dy = p.y - origin.y, dz = p.z - origin.z;
				const float sq = dx * dx + dy * dy + dz * dz;
				if (sq < bestSq) { bestSq = sq; best = a; }
				return RE::BSContainer::ForEachResult::kContinue;
			});
			return best;
		}

		std::string Hex(std::uint32_t a_id) { return fmt::format("0x{:08X}", a_id); }

		// PanelFlags + the flags DeDService reads natively.
		std::vector<std::string> FlagsFor(RE::Actor* a_actor)
		{
			if (!a_actor) return {};
			auto flags = PanelFlags::GetSingleton().FlagsOf(a_actor->GetFormID());
			if (!a_actor->HasKeywordString("ActorTypeNPC")) flags.emplace_back("creature");
			if (a_actor->IsInCombat()) flags.emplace_back("in_combat");
			std::sort(flags.begin(), flags.end());
			flags.erase(std::unique(flags.begin(), flags.end()), flags.end());
			return flags;
		}

		bool HasFlag(const std::vector<std::string>& a_flags, std::string_view a_flag)
		{
			return std::find(a_flags.begin(), a_flags.end(), a_flag) != a_flags.end();
		}

		json ActorJson(RE::Actor* a_actor, const std::vector<std::string>& a_flags)
		{
			if (!a_actor) return nullptr;
			return json{ { "formId", Hex(a_actor->GetFormID()) }, { "name", a_actor->GetDisplayFullName() }, { "flags", a_flags } };
		}

		json ModuleJson(const ModuleSpec& a_m)
		{
			return json{ { "id", a_m.id }, { "name", a_m.name }, { "tagline", a_m.tagline }, { "order", a_m.order } };
		}

		// Parse a page payload; a non-object or unparsable payload becomes {} (logged by the caller).
		// S321 (REV-194 dogfood): Papyrus pools strings case-insensitively, so a JSON literal true / false built in
		// Papyrus can come back as True / False (a module's "main" arrived as "Main"). Outside string values,
		// lower-case the bare words true / false / null (None -> null) before parsing. Returns the repair count.
		int RepairBareWords(std::string& a_text)
		{
			int fixes = 0;
			bool inStr = false;
			for (std::size_t i = 0; i < a_text.size(); ++i) {
				const char c = a_text[i];
				if (inStr) {
					if (c == '\\') { ++i; continue; }
					if (c == '"') inStr = false;
					continue;
				}
				if (c == '"') { inStr = true; continue; }
				if (!std::isalpha(static_cast<unsigned char>(c))) continue;
				std::size_t k = i;
				while (k < a_text.size() && std::isalpha(static_cast<unsigned char>(a_text[k]))) ++k;
				std::string w = a_text.substr(i, k - i), low = w;
				for (auto& ch : low) ch = static_cast<char>(std::tolower(static_cast<unsigned char>(ch)));
				if (low == "none") low = "null";
				if ((low == "true" || low == "false" || low == "null") && w != low) {
					a_text.replace(i, k - i, low);
					++fixes;
					k = i + low.size();
				}
				i = k - 1;
			}
			return fixes;
		}

		json ParseObject(const std::string& a_text, bool& a_ok)
		{
			a_ok = false;
			std::string text = a_text;
			const int fixes = RepairBareWords(text);
			try {
				auto j = json::parse(text);
				if (j.is_object()) {
					a_ok = true;
					if (fixes) SKSE::log::info("[DeDService][PANEL] repaired {} Papyrus-cased true/false/null word(s) in a module message.", fixes);
					return j;
				}
				SKSE::log::warn("[DeDService][PANEL] JSON is valid but not an object.");
			} catch (const std::exception& e) {
				SKSE::log::warn("[DeDService][PANEL] JSON parse error: {}", e.what());
			}
			return json::object();
		}

		std::string Join(const std::vector<std::string>& a_v)
		{
			std::string out;
			for (const auto& x : a_v) { if (!out.empty()) out += ','; out += x; }
			return out;
		}

		std::string Short(const std::string& a_s) { return a_s.size() > 200 ? a_s.substr(0, 200) + "..." : a_s; }
	}

	PanelHost& PanelHost::GetSingleton()
	{
		static PanelHost s;
		return s;
	}

	const std::vector<std::string>& PanelHost::Listeners()
	{
		static const std::vector<std::string> l{ "ded_req", "ded_act", "ded_set", "ded_close", "ded_view" };
		return l;
	}

	RE::Actor* PanelHost::PickTarget()
	{
		auto*      player = RE::PlayerCharacter::GetSingleton();
		RE::Actor* t      = CrosshairActor();
		if (!t || t == player) t = NearestLivingActor(kInteractRadius);
		if (t == player) t = nullptr;
		return t;
	}

	bool PanelHost::Open(RE::Actor* a_caster, RE::Actor* a_target, std::uint32_t a_flags)
	{
		if (!UIHost::GetSingleton().HasView(kModule, kView)) {
			SKSE::log::warn("[DeDService][PANEL] open refused -- the panel view is not available (page missing or Magelight unavailable).");
			return false;
		}
		auto* player = RE::PlayerCharacter::GetSingleton();
		RE::Actor* caster = a_caster ? a_caster : player;
		RE::Actor* target = (a_flags & DeDUI::kPanelTargetGiven) ? a_target : PickTarget();
		const bool skipClaims = (a_flags & DeDUI::kPanelSkipClaims) != 0;
		const auto tFlags = FlagsFor(target);
		const auto cFlags = FlagsFor(caster);

		// Every installed module's rules, highest priority first (ties: rail order).
		struct Cand { const ModuleSpec* m; const PanelRule* r; };
		const auto& reg = ModuleRegistry::GetSingleton();
		const auto  mods = reg.Modules();   // copy; pointers below point into it
		std::vector<Cand> cands;
		for (const auto& m : mods) {
			if (!m.hasPanel) continue;
			for (const auto& r : m.rules) {
				if (skipClaims && r.action == "claim") continue;
				cands.push_back({ &m, &r });
			}
		}
		std::stable_sort(cands.begin(), cands.end(), [](const Cand& a, const Cand& b) { return a.r->priority > b.r->priority; });

		const Cand* hit = nullptr;
		for (const auto& c : cands) {
			const auto& r = *c.r;
			if (r.target == "any" && !target) continue;
			if (r.target == "none" && target) continue;
			bool ok = true;
			for (const auto& [key, want] : r.conds) {
				const bool isTarget = key.rfind("target.", 0) == 0;
				const auto flag     = key.substr(7);
				const bool have     = isTarget ? (target && HasFlag(tFlags, flag)) : HasFlag(cFlags, flag);
				if (have != want) { ok = false; break; }
			}
			if (ok) { hit = &c; break; }
		}

		const std::string cls = target ? "target" : "notarget";
		std::string module, tab, mode, ruleDesc;
		bool pause = true;
		if (hit) {
			const auto& r = *hit->r;
			ruleDesc = fmt::format("{} rule {} ({})", hit->m->id, r.priority, r.action);
			if (r.action == "claim") {
				SKSE::log::info("[DeDService][PANEL] open: {} -> CLAIM '{}' (target {}).", ruleDesc, r.event, target ? Hex(target->GetFormID()) : "none");
				{
					std::lock_guard lk(m_mx);
					m_target = target ? target->GetFormID() : 0;
					m_tab.clear(); m_mode = "claim";
				}
				Dispatch(hit->m->id, "claim", json{ { "event", r.event }, { "caster", Hex(caster->GetFormID()) } }.dump());
				return false;
			}
			if (r.action == "refuse") {
				SKSE::log::info("[DeDService][PANEL] open: {} -> REFUSED '{}' (target {}, flags [{}]).", ruleDesc, r.event,
					target ? Hex(target->GetFormID()) : "none", Join(tFlags));
				return false;
			}
			module = hit->m->id; tab = r.tab; mode = r.mode; pause = r.pause;
			if (r.priority <= kGenericMax) {
				std::lock_guard lk(m_mx);
				const auto it = m_last.find(cls);
				if (it != m_last.end() && reg.IsInstalled(it->second.module)) {
					if (it->second.module != module || !it->second.tab.empty()) tab = it->second.tab;
					module = it->second.module;
					ruleDesc += fmt::format(" -> last place {}/{}", module, tab);
				}
			}
		} else {
			// No rule matched: the last place for this context class (D-P1), else the first module in the rail.
			std::lock_guard lk(m_mx);
			const auto it = m_last.find(cls);
			if (it != m_last.end() && reg.IsInstalled(it->second.module)) {
				module = it->second.module; tab = it->second.tab; ruleDesc = "no rule -> last place";
			} else {
				for (const auto& m : mods) {
					if (m.hasPanel) { module = m.id; break; }
				}
				ruleDesc = "no rule -> first module";
			}
			mode = target ? "interact" : "notarget";
		}
		if (module.empty()) {
			SKSE::log::warn("[DeDService][PANEL] open refused -- no installed module has a panel section.");
			return false;
		}
		if (skipClaims) ruleDesc += " (claims skipped)";
		return Show(module, tab, mode, pause, ruleDesc, caster, target);
	}

	bool PanelHost::OpenAt(const std::string& a_module, const std::string& a_tab, const std::string& a_mode,
		RE::Actor* a_caster, RE::Actor* a_target, bool a_pause)
	{
		if (!UIHost::GetSingleton().HasView(kModule, kView) || !ModuleRegistry::GetSingleton().IsInstalled(a_module)) {
			SKSE::log::warn("[DeDService][PANEL] open-at {}/{} refused -- panel or module unavailable.", a_module, a_mode);
			return false;
		}
		auto* caster = a_caster ? a_caster : RE::PlayerCharacter::GetSingleton();
		return Show(a_module, a_tab, a_mode, a_pause, "opened by " + a_module, caster, a_target);
	}

	bool PanelHost::Show(const std::string& a_module, const std::string& a_tab, const std::string& a_mode, bool a_pause,
		const std::string& a_why, RE::Actor* a_caster, RE::Actor* a_target)
	{
		const auto& reg  = ModuleRegistry::GetSingleton();
		const auto  mods = reg.Modules();
		const auto tFlags = FlagsFor(a_target);
		const auto cFlags = FlagsFor(a_caster);
		json ctx;
		ctx["v"]      = 1;
		ctx["route"]  = { { "module", a_module }, { "tab", a_tab }, { "mode", a_mode }, { "pause", a_pause }, { "why", a_why } };
		ctx["target"] = ActorJson(a_target, tFlags);
		ctx["caster"] = ActorJson(a_caster, cFlags);
		ctx["isVR"]   = REL::Module::IsVR();
		json installed = json::array(), absent = json::array();
		for (const auto& m : mods) {
			if (m.hasPanel) installed.push_back(ModuleJson(m));
		}
		for (const auto& m : reg.Absent()) absent.push_back(ModuleJson(m));
		ctx["modules"] = installed;
		ctx["absent"]  = absent;

		{
			std::lock_guard lk(m_mx);
			if (m_open) SKSE::log::info("[DeDService][PANEL] re-open while open -- the page takes the new context.");
			m_module = a_module; m_tab = a_tab; m_mode = a_mode;
			m_target = a_target ? a_target->GetFormID() : 0;
			m_visited.clear();
		}
		if (!UIHost::GetSingleton().OpenPanelView(a_pause, ctx.dump())) {
			SKSE::log::warn("[DeDService][PANEL] open: {} -> UI mode not granted (another menu holds the cursor) -- nothing opened.", a_why);
			std::lock_guard lk(m_mx);
			m_open = false;
			return false;
		}
		{
			std::lock_guard lk(m_mx);
			m_open = true;
		}
		SKSE::log::info("[DeDService][PANEL] OPEN {}/{} mode {} pause {} -- {}; target {} [{}], caster [{}].", a_module, a_tab, a_mode, a_pause,
			a_why, a_target ? fmt::format("{} {}", a_target->GetDisplayFullName(), Hex(a_target->GetFormID())) : "none",
			Join(tFlags), Join(cFlags));
		return true;
	}

	bool PanelHost::IsOpen() const
	{
		std::lock_guard lk(m_mx);
		return m_open;
	}

	bool PanelHost::Close(const char* a_module)
	{
		if (!a_module || !IsOpen()) return false;
		EndSession("closed by module", a_module, true, json{ { "reason", "module" } }.dump());
		return true;
	}

	bool PanelHost::SetHandler(const char* a_module, DeDUI::PanelFn a_fn, void* a_user)
	{
		if (!a_module || !ModuleRegistry::GetSingleton().IsInstalled(a_module)) return false;
		std::lock_guard lk(m_mx);
		m_handlers[a_module] = Handler{ a_fn, a_user };
		SKSE::log::info("[DeDService][PANEL] panel handler set for module '{}'.", a_module);
		return true;
	}

	bool PanelHost::Push(const char* a_module, const char* a_json)
	{
		if (!a_module || !a_json || !ModuleRegistry::GetSingleton().IsInstalled(a_module)) return false;
		bool ok = false;
		auto j = ParseObject(a_json, ok);
		if (!ok) {
			SKSE::log::warn("[DeDService][PANEL] push from '{}' refused -- not a JSON object: {}", a_module, Short(a_json));
			return false;
		}
		if (!j.contains("module")) j["module"] = a_module;
		SKSE::log::info("[DeDService][PANEL] push {} -> page ({} B).", a_module, std::string(a_json).size());
		return UIHost::GetSingleton().Interop(kModule, kView, "dedData", j.dump());
	}

	bool PanelHost::SettingResult(const char* a_module, const char* a_json)
	{
		if (!a_module || !a_json || !ModuleRegistry::GetSingleton().IsInstalled(a_module)) return false;
		bool ok = false;
		auto j = ParseObject(a_json, ok);
		if (!ok) {
			SKSE::log::warn("[DeDService][PANEL] setting result from '{}' refused -- not a JSON object.", a_module);
			return false;
		}
		if (!j.contains("module")) j["module"] = a_module;
		SKSE::log::info("[DeDService][PANEL] setting result {} key {} ok {}.", a_module, j.value("key", std::string{ "?" }), j.value("ok", false));
		return UIHost::GetSingleton().Interop(kModule, kView, "dedSetting", j.dump());
	}

	void PanelHost::Dispatch(const std::string& a_module, const std::string& a_kind, const std::string& a_dataJson)
	{
		Handler h;
		std::uint32_t target = 0;
		json route;
		{
			std::lock_guard lk(m_mx);
			const auto it = m_handlers.find(a_module);
			if (it != m_handlers.end()) h = it->second;
			target = m_target;
			route  = { { "tab", m_tab }, { "mode", m_mode } };
		}
		bool ok = false;
		json data = ParseObject(a_dataJson, ok);
		json msg{ { "type", a_kind }, { "module", a_module }, { "target", Hex(target) }, { "data", data }, { "route", route } };
		const auto text = msg.dump();
		if (h.fn) {
			SKSE::log::info("[DeDService][PANEL] {} -> {} (handler): {}", a_kind, a_module, Short(text));
			h.fn(a_module.c_str(), a_kind.c_str(), text.c_str(), target, h.user);
			return;
		}
		RE::TESForm* sender = target ? RE::TESForm::LookupByID(target) : nullptr;
		const auto   event  = "DeD_Panel_" + a_module;
		SKSE::log::info("[DeDService][PANEL] {} -> {} (ModEvent {}): {}", a_kind, a_module, event, Short(text));
		if (a_kind == "claim" || a_kind == "req") {
			// S320 (REV-193 dogfood): a module with no panel handler gets a ModEvent; if nothing in that module
			// listens, the press is silently lost. Say so, so the next silent failure is one grep away.
			SKSE::log::warn("[DeDService][PANEL] no panel handler is set for '{}' - the {} went out as a ModEvent only; if "
				"nothing happens, that module never registered its handler.", a_module, a_kind);
		}
		EventPump::Emit(event, sender, 0.0f, text);
	}

	// Phase 3 (S323): DeD_MCM.PanelSettingsMsg(kind, module, key, value) on the MCM quest (DeD_Framework.esp 0x800).
	// value is the raw JSON text of the setting's new value ("" for a request). Answers come back through the
	// DeDService.PanelPush / PanelSettingResult natives.
	void PanelHost::DispatchToMcm(const std::string& a_module, const std::string& a_kind, const std::string& key, const std::string& value)
	{
		auto* vm   = RE::BSScript::Internal::VirtualMachine::GetSingleton();
		auto* dh   = RE::TESDataHandler::GetSingleton();
		auto* mcm  = dh ? dh->LookupForm<RE::TESQuest>(0x800, "DeD_Framework.esp") : nullptr;
		SKSE::log::info("[DeDService][PANEL] settings {} -> {} (DeD_MCM) key '{}'.", a_kind, a_module, key);
		if (!vm || !mcm) { SKSE::log::error("[DeDService][PANEL] settings: VM or DeD_MCM quest unavailable."); return; }
		auto* policy = vm->GetObjectHandlePolicy();
		const RE::VMHandle handle = policy->GetHandleForObject(RE::FormType::Quest, mcm);
		if (handle == policy->EmptyHandle()) { SKSE::log::error("[DeDService][PANEL] settings: DeD_MCM handle invalid."); return; }
		auto* args = RE::MakeFunctionArguments(RE::BSFixedString(a_kind.c_str()), RE::BSFixedString(a_module.c_str()),
			RE::BSFixedString(key.c_str()), RE::BSFixedString(value.c_str()));
		RE::BSTSmartPointer<RE::BSScript::IStackCallbackFunctor> cb;
		vm->DispatchMethodCall(handle, RE::BSFixedString("DeD_MCM"), RE::BSFixedString("PanelSettingsMsg"), args, cb);
		delete args;
	}

	void PanelHost::EndSession(const char* a_why, const std::string& a_except, bool a_hide, const std::string& a_reasonJson)
	{
		std::set<std::string> visited;
		{
			std::lock_guard lk(m_mx);
			if (!m_open) return;
			m_open  = false;
			visited = m_visited;
			m_visited.clear();
		}
		Preview::GetSingleton().CloseAll(a_why);   // T2: a live view is closed before its page goes away
		if (a_hide) UIHost::GetSingleton().CloseView(kModule, kView);
		SKSE::log::info("[DeDService][PANEL] closed ({}); visited [{}].", a_why, Join(std::vector<std::string>(visited.begin(), visited.end())));
		for (const auto& m : visited) {
			if (m != a_except) Dispatch(m, "closed", a_reasonJson);
		}
	}

	void PanelHost::OnPage(const std::string& a_listener, const std::string& a_payload)
	{
		if (a_listener == "ded_view") {   // T2 (S330): the live preview pane talks to the Phantasm client directly
			Preview::GetSingleton().OnPage(a_payload);
			return;
		}
		bool ok = false;
		const auto p = ParseObject(a_payload, ok);
		if (!ok && a_listener != "ded_close") {
			SKSE::log::warn("[DeDService][PANEL] page {} ignored -- payload is not a JSON object: {}", a_listener, Short(a_payload));
			return;
		}
		if (a_listener == "ded_close") {
			EndSession("page", std::string{}, true, json{ { "reason", "page" } }.dump());
			return;
		}
		const auto module = p.value("module", std::string{});
		if (module.empty() || !ModuleRegistry::GetSingleton().IsInstalled(module)) {
			SKSE::log::warn("[DeDService][PANEL] page {} ignored -- unknown module '{}'.", a_listener, module);
			return;
		}
		if (a_listener == "ded_req" && p.value("section", std::string{ "main" }) != "settings") {
			std::lock_guard lk(m_mx);
			m_module = module;
			m_tab    = p.value("tab", std::string{});
			m_visited.insert(module);
			m_last[m_target ? "target" : "notarget"] = Place{ m_module, m_tab };
		}
		const std::string kind = a_listener == "ded_req" ? "req" : a_listener == "ded_act" ? "act" : "set";
		// Phase 3 (S323): a module whose descriptor says "settingsVia": "mcm" has its Settings served by the framework's
		// DeD_MCM script (the MCM rows' own keys, ranges and side effects), not by the module's handler.
		const bool settingsMsg = (kind == "req" && p.value("section", std::string{}) == "settings") || kind == "set";
		if (settingsMsg) {
			const auto* spec = ModuleRegistry::GetSingleton().FindUnsafe(module);
			if (spec && spec->settingsVia == "mcm") {
				DispatchToMcm(module, kind, p.value("key", std::string{}), p.contains("value") ? p["value"].dump() : std::string{});
				return;
			}
		}
		// An action that ends the panel: every OTHER visited module hears "closed" first, then the owner gets the act.
		if (a_listener == "ded_act" && !p.value("stay", false)) {
			EndSession("action", module, true, json{ { "reason", "other_module_action" } }.dump());
		}
		Dispatch(module, kind, a_payload);
	}

	void PanelHost::OnClosed(int a_reason)
	{
		EndSession("player/host", std::string{}, false, json{ { "reason", a_reason } }.dump());
	}
}
