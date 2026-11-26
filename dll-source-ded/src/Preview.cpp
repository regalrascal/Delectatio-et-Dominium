// Preview -- see Preview.h. Tattoo-overhaul T2 leg 1 (S330).
#include "PCH.h"
#include "Preview.h"

#include <algorithm>
#include <cmath>
#include <nlohmann/json.hpp>

#include "Phantasm_API.h"
#include "PanelHost.h"
#include "UIHost.h"

namespace DeD
{
	namespace
	{
		using json = nlohmann::json;
		namespace PA = PHANTASM_API;

		const PA::Interface1* Api(const void* a_p) { return static_cast<const PA::Interface1*>(a_p); }

		const char* KindName(PA::EventKind k)
		{
			switch (k) {
			case PA::EventKind::Shown:   return "shown";
			case PA::EventKind::Waiting: return "waiting";
			case PA::EventKind::Ended:   return "ended";
			default:                     return "reply";
			}
		}

		std::uint32_t ParseForm(const json& a_j)
		{
			// the page passes the module's actor id as a string: decimal (Papyrus GetFormID, may be negative for 0xFE..)
			// or 0x-hex
			if (!a_j.contains("actor")) return 0;
			const auto& v = a_j["actor"];
			try {
				if (v.is_number_integer()) return static_cast<std::uint32_t>(v.get<long long>());
				if (v.is_string()) {
					const auto s = v.get<std::string>();
					if (s.rfind("0x", 0) == 0 || s.rfind("0X", 0) == 0) return static_cast<std::uint32_t>(std::stoull(s.substr(2), nullptr, 16));
					return static_cast<std::uint32_t>(std::stoll(s));
				}
			} catch (...) {}
			return 0;
		}

		float Num(const json& a_j, const char* a_k, float a_def)
		{
			const auto it = a_j.find(a_k);
			if (it == a_j.end() || !it->is_number()) return a_def;
			const float f = it->get<float>();
			return std::isfinite(f) ? f : a_def;
		}
	}

	Preview& Preview::GetSingleton()
	{
		static Preview s;
		return s;
	}

	void Preview::Init()
	{
		auto* mod = ::GetModuleHandleW(L"Phantasm.dll");
		auto* get = mod ? reinterpret_cast<PA::RequestPluginAPIFn>(::GetProcAddress(mod, "RequestPluginAPI")) : nullptr;
		auto* api = get ? static_cast<const PA::Interface1*>(get(PA::kInterface1)) : nullptr;
		if (!api) {
			SKSE::log::info("[DeDService][PREVIEW] Phantasm {} -- no live preview this session.", mod ? "too old (no Interface1)" : "not installed");
			return;
		}
		PA::ClientId me = 0;
		const auto r = api->RegisterClient("ded", [](const PA::Event* e, void* u) { Preview::OnEvent(e, u); }, this, &me);
		if (r != PA::Result::Ok) {
			SKSE::log::warn("[DeDService][PREVIEW] Phantasm RegisterClient('ded') failed ({}) -- no live preview.", static_cast<int>(r));
			return;
		}
		std::lock_guard lk(m_mx);
		m_api = api;
		m_client = me;
		SKSE::log::info("[DeDService][PREVIEW] Phantasm {}.{}.{} found -- live preview available (client 'ded').",
			api->pluginVersion / 10000, (api->pluginVersion / 100) % 100, api->pluginVersion % 100);
	}

	bool Preview::Available() const
	{
		std::lock_guard lk(m_mx);
		return m_api != nullptr;
	}

	void Preview::Send(const std::string& a_json)
	{
		UIHost::GetSingleton().Interop(PanelHost::kModule, PanelHost::kView, "dedView", a_json);
	}

	void Preview::OnPage(const std::string& a_payload)
	{
		const auto p = json::parse(a_payload, nullptr, false);
		if (!p.is_object()) { SKSE::log::warn("[DeDService][PREVIEW] ded_view ignored -- not a JSON object."); return; }
		const auto op = p.value("op", std::string{});
		std::unique_lock lk(m_mx);
		const auto* api = Api(m_api);
		if (!api) {
			lk.unlock();
			if (op == "open") Send(json{ { "state", "absent" }, { "reason", "phantasm" } }.dump());
			return;
		}
		if (op == "open") {
			const auto actor = ParseForm(p);
			const auto w = static_cast<std::uint32_t>((std::max)(4.0f, Num(p, "w", 320.0f)));
			const auto h = static_cast<std::uint32_t>((std::max)(4.0f, Num(p, "h", 480.0f)));
			if (!actor) { lk.unlock(); Send(json{ { "state", "ended" }, { "reason", "missing" } }.dump()); return; }
			PA::ViewId v = 0;
			const auto r = api->OpenView(m_client, "figure", actor, w, h, PA::Framing::Figure, &v);
			if (r != PA::Result::Ok) {
				SKSE::log::warn("[DeDService][PREVIEW] OpenView {:08X} {}x{} refused ({}).", actor, w, h, static_cast<int>(r));
				lk.unlock();
				Send(json{ { "state", "ended" }, { "reason", "refused" } }.dump());
				return;
			}
			m_view = v;
			m_actor = actor;
			SKSE::log::info("[DeDService][PREVIEW] view {} opened on {:08X} at {}x{} (waiting for its first frame).", v, actor, w, h);
		} else if (op == "close") {
			if (m_view) {
				api->CloseView(m_view);
				SKSE::log::info("[DeDService][PREVIEW] view {} closed (page).", m_view);
			}
			m_view = 0;
			m_actor = 0;
		} else if (op == "orbit" && m_view) {
			api->Orbit(m_view, Num(p, "dx", 0.0f), Num(p, "dy", 0.0f));
		} else if (op == "zoom" && m_view) {
			api->Zoom(m_view, Num(p, "dz", 0.0f), Num(p, "u", 0.5f), Num(p, "v", 0.5f));
		} else if (op == "resize" && m_view) {
			api->ResizeView(m_view, static_cast<std::uint32_t>((std::max)(4.0f, Num(p, "w", 320.0f))),
				static_cast<std::uint32_t>((std::max)(4.0f, Num(p, "h", 480.0f))));
		}
	}

	void Preview::CloseAll(const char* a_why)
	{
		std::lock_guard lk(m_mx);
		if (!m_api || !m_view) return;
		Api(m_api)->CloseView(m_view);
		SKSE::log::info("[DeDService][PREVIEW] view {} closed ({}).", m_view, a_why);
		m_view = 0;
		m_actor = 0;
	}

	void Preview::Refresh(std::uint32_t a_formId)
	{
		std::lock_guard lk(m_mx);
		if (!m_api || !m_view || (a_formId && a_formId != m_actor)) return;
		Api(m_api)->Refresh(m_view);
		SKSE::log::info("[DeDService][PREVIEW] view {} refreshed (look changed).", m_view);
	}

	void Preview::Dress(std::uint32_t a_actor, std::vector<std::uint32_t> a_items, bool a_on)
	{
		// AddUITask: the main thread, also while a menu pauses the game, and the queue Phantasm names for
		// RebuildActor3D (never the AddTask drain, where RaceMenu's armor hook can deadlock it).
		SKSE::GetTaskInterface()->AddUITask([this, a_actor, items = std::move(a_items), a_on]() {
			auto* actor = RE::TESForm::LookupByID<RE::Actor>(a_actor);
			auto* mgr = RE::ActorEquipManager::GetSingleton();
			if (!actor || !mgr) {
				SKSE::log::warn("[DeDService][PREVIEW] dress: actor {:08X} not found -- S331", a_actor);
				return;
			}
			int done = 0;
			for (const auto id : items) {
				auto* obj = RE::TESForm::LookupByID<RE::TESBoundObject>(id);
				if (!obj) continue;
				// queueEquip false + applyNow true: no equip queue, the 3D changes now
				if (a_on) mgr->EquipObject(actor, obj, nullptr, 1, nullptr, false, true, false, true);
				else      mgr->UnequipObject(actor, obj, nullptr, 1, nullptr, false, true, false, true, nullptr);
				++done;
			}
			const void* api = nullptr;
			bool shown = false;
			{
				std::lock_guard lk(m_mx);
				api = m_api;
				shown = m_view && m_actor == a_actor;
			}
			const char* how = "no view";
			if (api && shown) {
				const auto* a = Api(api);
				const bool hasRebuild = a->size >= offsetof(PA::Interface1, RebuildActor3D) + sizeof(a->RebuildActor3D) && a->RebuildActor3D;
				if (hasRebuild && a->RebuildActor3D(a_actor, "ded") == PA::Result::Ok) {
					how = "rebuilt";
				} else {
					std::lock_guard lk(m_mx);
					if (m_view) a->Refresh(m_view);
					how = "refreshed";
				}
			}
			SKSE::log::info("[DeDService][PREVIEW] {} {} item(s) {} {:08X} at once; view {} -- S331",
				a_on ? "put" : "took", done, a_on ? "back on" : "off", a_actor, how);
		});
	}

	void Preview::OnGameLoad()
	{
		std::lock_guard lk(m_mx);
		m_view = 0;   // Phantasm ends every view with "game-load" itself
		m_actor = 0;
	}

	void Preview::OnEvent(const void* a_event, void* a_user)
	{
		const auto* e = static_cast<const PA::Event*>(a_event);
		auto* self = static_cast<Preview*>(a_user);
		if (!e || !self || e->kind == PA::EventKind::Reply) return;
		{
			std::lock_guard lk(self->m_mx);
			if (e->view != self->m_view) return;   // match by view id, never by slot
			if (e->kind == PA::EventKind::Ended) { self->m_view = 0; self->m_actor = 0; }
		}
		json j{ { "view", e->view }, { "state", KindName(e->kind) }, { "reason", e->reason ? e->reason : "" } };
		if (e->kind == PA::EventKind::Shown) {
			j["url"] = e->imageUrl ? e->imageUrl : "";
			j["lastSeen"] = e->lastSeen;
		}
		SKSE::log::info("[DeDService][PREVIEW] view {} {} {}", e->view, KindName(e->kind), e->reason ? e->reason : "");
		self->Send(j.dump());
	}
}
