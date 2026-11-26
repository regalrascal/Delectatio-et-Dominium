#include "PCH.h"
#include "UIHost.h"
#include "ModuleRegistry.h"
#include "PanelHost.h"
#include "PanelFlags.h"

#include <algorithm>

namespace ML = MAGELIGHT_API;

namespace DeD
{
	namespace
	{
		// Magelight 1.9.0+: PostGameTask, focus sharing, page thread; local install is 1.9.3.
		constexpr std::uint32_t kMinHost = ML::PackVersion(1, 9, 0);
		constexpr const char*   kModId   = "DeD";
		constexpr const char*   kModName = "Delectatio et Dominium";

		ML::Layer ToLayer(const std::string& a_layer)
		{
			if (a_layer == "hud") return ML::Layer::Hud;
			if (a_layer == "popup") return ML::Layer::Popup;
			if (a_layer == "system") return ML::Layer::System;
			return ML::Layer::Panel;
		}

		const char* Str(const char* a_s) { return a_s ? a_s : ""; }

		// ---- the exported C ABI (DeDUI_API.h) ----
		bool Api_IsAvailable() { return UIHost::GetSingleton().IsAvailable(); }
		bool Api_IsModuleInstalled(const char* a_module) { return a_module && ModuleRegistry::GetSingleton().IsInstalled(a_module); }
		bool Api_SetHandler(const char* m, DeDUI::PickFn p, DeDUI::ClosedFn c, void* u) { return UIHost::GetSingleton().SetHandler(m, p, c, u); }
		bool Api_OpenView(const char* m, const char* v, const char* js, std::uint32_t f) { return UIHost::GetSingleton().OpenView(m, v, js, f); }
		bool Api_InvokeView(const char* m, const char* v, const char* s) { return UIHost::GetSingleton().InvokeView(m, v, s); }
		bool Api_CloseView(const char* m, const char* v) { return UIHost::GetSingleton().CloseView(m, v); }
		bool Api_ShowView(const char* m, const char* v, bool s) { return UIHost::GetSingleton().ShowView(m, v, s); }

		const DeDUI::Api1 g_api1{
			DeDUI::kApiVersion1,
			&Api_IsAvailable,
			&Api_IsModuleInstalled,
			&Api_SetHandler,
			&Api_OpenView,
			&Api_InvokeView,
			&Api_CloseView,
			&Api_ShowView,
		};

		// ---- v2 (the combined panel) ----
		const DeDUI::Api2* Api2Table();
		bool Api_SetPanelHandler(const char* m, DeDUI::PanelFn f, void* u) { return PanelHost::GetSingleton().SetHandler(m, f, u); }
		bool Api_PanelPush(const char* m, const char* j) { return PanelHost::GetSingleton().Push(m, j); }
		bool Api_PanelSettingResult(const char* m, const char* j) { return PanelHost::GetSingleton().SettingResult(m, j); }
		bool Api_PanelSetFlag(std::uint32_t id, const char* m, const char* f, bool on)
		{
			return m && f && PanelFlags::GetSingleton().Set(id, m, f, on);
		}
		bool Api_OpenPanel(std::uint32_t casterId)
		{
			if (!UIHost::GetSingleton().HasView(PanelHost::kModule, PanelHost::kView)) return false;
			SKSE::GetTaskInterface()->AddTask([casterId]() {
				auto* caster = casterId ? RE::TESForm::LookupByID<RE::Actor>(casterId) : nullptr;
				PanelHost::GetSingleton().Open(caster);
			});
			return true;
		}
		std::uint32_t Api_PanelTarget()
		{
			auto* a = PanelHost::PickTarget();
			return a ? a->GetFormID() : 0;
		}
		bool Api_PanelAvailable() { return UIHost::GetSingleton().HasView(PanelHost::kModule, PanelHost::kView); }
		bool Api_OpenPanelEx(std::uint32_t casterId, std::uint32_t targetId, std::uint32_t flags)
		{
			auto* caster = casterId ? RE::TESForm::LookupByID<RE::Actor>(casterId) : nullptr;
			auto* target = targetId ? RE::TESForm::LookupByID<RE::Actor>(targetId) : nullptr;
			return PanelHost::GetSingleton().Open(caster, target, flags);
		}
		bool Api_OpenPanelAt(const char* m, const char* tab, const char* mode, std::uint32_t casterId, std::uint32_t targetId, bool pause)
		{
			if (!m) return false;
			auto* caster = casterId ? RE::TESForm::LookupByID<RE::Actor>(casterId) : nullptr;
			auto* target = targetId ? RE::TESForm::LookupByID<RE::Actor>(targetId) : nullptr;
			return PanelHost::GetSingleton().OpenAt(m, tab ? tab : "", mode ? mode : "", caster, target, pause);
		}
		bool Api_ClosePanel(const char* m) { return PanelHost::GetSingleton().Close(m); }

		const DeDUI::Api2 g_api2{
			DeDUI::kApiVersion2,
			&Api_IsAvailable,
			&Api_IsModuleInstalled,
			&Api_SetHandler,
			&Api_OpenView,
			&Api_InvokeView,
			&Api_CloseView,
			&Api_ShowView,
			&Api_SetPanelHandler,
			&Api_PanelPush,
			&Api_PanelSettingResult,
			&Api_PanelSetFlag,
			&Api_OpenPanel,
			&Api_PanelTarget,
			&Api_PanelAvailable,
			&Api_OpenPanelEx,
			&Api_OpenPanelAt,
			&Api_ClosePanel,
		};
		const DeDUI::Api2* Api2Table() { return &g_api2; }

		// A pick copied off the render thread, delivered on the game thread.
		struct PickTask
		{
			std::string module, view, listener, payload;
		};
	}

	UIHost& UIHost::GetSingleton()
	{
		static UIHost s;
		return s;
	}

	const DeDUI::Api1* UIHost::Api() const { return &g_api1; }
	const DeDUI::Api2* UIHost::Api2() const { return Api2Table(); }

	bool UIHost::IsAvailable() const
	{
		std::lock_guard lk(m_mx);
		return m_available;
	}

	void UIHost::Init(const std::filesystem::path& a_dedRoot)
	{
		std::lock_guard lk(m_mx);
		if (m_mod) return;   // once per process
		const auto modules = ModuleRegistry::GetSingleton().Modules();
		if (modules.empty()) {
			SKSE::log::info("[DeDService][UI] no DeD module installed -- Magelight not acquired.");
			return;
		}
		m_ml = ML::RequestApi4();
		if (!m_ml) {
			SKSE::log::warn("[DeDService][UI] Magelight UI not found (or older than API v4) -- DeD menus unavailable.");
			return;
		}
		if (m_ml->hostVersionNumber < kMinHost) {
			SKSE::log::warn("[DeDService][UI] Magelight {} is older than the required 1.9.0 -- DeD menus unavailable.",
				Str(m_ml->hostVersion));
			return;
		}
		ML::ModDesc d{};
		d.size           = sizeof(d);
		d.modId          = kModId;
		d.displayName    = kModName;
		d.modVersion     = ML::PackVersion(1, 0, 0);
		d.minHostVersion = kMinHost;
		d.callbackThread = ML::CallbackThread::GameThread;
		d.onEvent        = &UIHost::OnEvent;
		d.onLog          = nullptr;
		d.user           = this;
		d.sessionName    = nullptr;
		if (const auto r = m_ml->RegisterMod(&d, &m_mod); r != ML::Result::Ok) {
			SKSE::log::error("[DeDService][UI] RegisterMod failed ({}): {}", static_cast<int>(r), Str(m_ml->GetLastErrorMessage(0)));
			m_mod = 0;
			return;
		}

		std::size_t created = 0;
		for (const auto& m : modules) {
			for (const auto& v : m.views) {
				if (CreateView(m.id, v, a_dedRoot)) ++created;
			}
		}
		// Phase 2: the Framework's combined panel, when its page is installed (leg 2 builds it).
		{
			ViewSpec panel;
			panel.name          = PanelHost::kView;
			panel.page          = "views/panel/index.html";
			panel.layer         = "panel";
			panel.captureEscape = true;   // the page steps back first; at the top level it sends ded_close
			panel.listeners     = PanelHost::Listeners();
			std::error_code ec;
			if (std::filesystem::is_regular_file(a_dedRoot / panel.page, ec)) {
				if (CreateView(PanelHost::kModule, panel, a_dedRoot)) ++created;
			} else {
				SKSE::log::info("[DeDService][PANEL] panel page not installed ({}) -- the combined panel is off; module views work as before.", panel.page);
			}
		}
		m_available = true;
		SKSE::log::info("[DeDService][UI] READY: Magelight {} acquired as '{}', {} view(s) for {} module(s).",
			Str(m_ml->hostVersion), kModId, created, modules.size());
	}

	// Init only (lock held).
	bool UIHost::CreateView(const std::string& a_module, const ViewSpec& v, const std::filesystem::path& a_dedRoot)
	{
		const auto page    = (a_dedRoot / std::filesystem::path(v.page)).lexically_normal();
		const auto pageU8  = page.u8string();
		const std::string pageStr(pageU8.begin(), pageU8.end());
		const std::string mlName = a_module + "." + v.name;

		ML::ViewDesc vd{};
		vd.size         = sizeof(vd);
		vd.name         = mlName.c_str();
		vd.htmlPath     = pageStr.c_str();
		vd.anchor       = ML::Anchor::TopLeft;
		vd.x = vd.y = vd.w = vd.h = 0;
		vd.fullscreen   = true;
		vd.clickThrough = v.clickThrough;
		vd.startVisible = v.startVisible;
		vd.layer        = ToLayer(v.layer);
		vd.uiScale      = 0.0f;
		vd.onDomReady   = nullptr;

		ML::ViewId id = 0;
		if (const auto r = m_ml->CreateViewEx(m_mod, &vd, &id); r != ML::Result::Ok || !id) {
			SKSE::log::error("[DeDService][UI] view {} not created ({}): {} [page {}]", mlName, static_cast<int>(r),
				Str(m_ml->GetLastErrorMessage(m_mod)), pageStr);
			return false;
		}
		if (v.captureEscape) {
			if (const auto r = m_ml->SetEscapeCapture(id, true); r != ML::Result::Ok) {
				SKSE::log::warn("[DeDService][UI] view {}: escape capture not set ({}).", mlName, static_cast<int>(r));
			}
		}
		View& view   = m_views.emplace_back();
		view.module  = a_module;
		view.name    = v.name;
		view.id      = id;
		for (const auto& l : v.listeners) {
			auto& ctx = m_listeners.emplace_back(ListenerCtx{ a_module, v.name, l });
			if (const auto r = m_ml->RegisterJSListenerEx(id, l.c_str(), &UIHost::OnJs, &ctx); r != ML::Result::Ok) {
				SKSE::log::error("[DeDService][UI] listener {} on {} not registered ({}).", l, mlName, static_cast<int>(r));
			}
		}
		SKSE::log::info("[DeDService][UI] view {} created (id {}, layer {}, {} listener(s)).", mlName, id, v.layer, v.listeners.size());
		return true;
	}

	UIHost::View* UIHost::Find(std::string_view a_module, std::string_view a_view)
	{
		for (auto& v : m_views) {
			if (v.module == a_module && v.name == a_view) return &v;
		}
		return nullptr;
	}

	UIHost::View* UIHost::FindById(ML::ViewId a_id)
	{
		for (auto& v : m_views) {
			if (v.id == a_id) return &v;
		}
		return nullptr;
	}

	UIHost::Handler UIHost::HandlerFor(const std::string& a_module)
	{
		for (const auto& h : m_handlers) {
			if (h.module == a_module) return h;
		}
		return {};
	}

	bool UIHost::SetHandler(const char* a_module, DeDUI::PickFn a_pick, DeDUI::ClosedFn a_closed, void* a_user)
	{
		if (!a_module || !ModuleRegistry::GetSingleton().IsInstalled(a_module)) return false;
		std::lock_guard lk(m_mx);
		for (auto& h : m_handlers) {
			if (h.module == a_module) {
				h.pick = a_pick; h.closed = a_closed; h.user = a_user;
				return true;
			}
		}
		m_handlers.push_back(Handler{ a_module, a_pick, a_closed, a_user });
		SKSE::log::info("[DeDService][UI] handler set for module '{}'.", a_module);
		return true;
	}

	bool UIHost::OpenView(const char* a_module, const char* a_view, const char* a_jsCall, std::uint32_t a_flags)
	{
		std::lock_guard lk(m_mx);
		View* v = (a_module && a_view) ? Find(a_module, a_view) : nullptr;
		if (!m_available || !v) {
			SKSE::log::warn("[DeDService][UI] OpenView {}.{} refused -- {}.", Str(a_module), Str(a_view),
				m_available ? "unknown view" : "UI unavailable");
			return false;
		}
		m_ml->ShowView(v->id, true);
		if (a_jsCall && *a_jsCall) {
			if (v->domReady) m_ml->InvokeJS(v->id, a_jsCall);
			else v->pending.emplace_back(a_jsCall);
		}
		v->open    = true;
		v->focused = (a_flags & DeDUI::kOpenFocus) != 0;
		if (v->focused) {
			const std::uint32_t mlFlags = (a_flags & DeDUI::kOpenPause) ? ML::kUIModeFlagPause : ML::kUIModeFlagNone;
			if (const auto r = m_ml->RequestUIMode(v->id, mlFlags); r != ML::Result::Ok) {
				SKSE::log::warn("[DeDService][UI] OpenView {}.{}: UI mode not granted ({}): {} -- treated as cancel.",
					v->module, v->name, static_cast<int>(r), Str(m_ml->GetLastErrorMessage(m_mod)));
				v->open = v->focused = false;
				v->pending.clear();
				m_ml->ShowView(v->id, false);
				return false;
			}
		}
		SKSE::log::info("[DeDService][UI] OpenView {}.{} (focus {}, pause {}, page {}).", v->module, v->name,
			v->focused, (a_flags & DeDUI::kOpenPause) != 0, v->domReady ? "ready" : "loading");
		return true;
	}

	bool UIHost::InvokeView(const char* a_module, const char* a_view, const char* a_script)
	{
		std::lock_guard lk(m_mx);
		View* v = (a_module && a_view) ? Find(a_module, a_view) : nullptr;
		if (!m_available || !v || !a_script || !*a_script) return false;
		if (v->domReady) m_ml->InvokeJS(v->id, a_script);
		else v->pending.emplace_back(a_script);
		return true;
	}

	bool UIHost::CloseView(const char* a_module, const char* a_view)
	{
		std::lock_guard lk(m_mx);
		View* v = (a_module && a_view) ? Find(a_module, a_view) : nullptr;
		if (!m_available || !v) return false;
		const bool wasFocused = v->focused;
		v->open = v->focused = false;
		if (wasFocused && m_ml->GetUIModeOwner() == m_mod) {
			++v->expectExit;   // the exit event this causes is ours, not the player's
			m_ml->ReleaseUIMode(m_mod);
		}
		m_ml->ShowView(v->id, false);
		SKSE::log::info("[DeDService][UI] CloseView {}.{} (by module).", v->module, v->name);
		return true;
	}

	bool UIHost::ShowView(const char* a_module, const char* a_view, bool a_show)
	{
		std::lock_guard lk(m_mx);
		View* v = (a_module && a_view) ? Find(a_module, a_view) : nullptr;
		if (!m_available || !v) return false;
		m_ml->ShowView(v->id, a_show);
		return true;
	}

	bool UIHost::HasView(const char* a_module, const char* a_view)
	{
		std::lock_guard lk(m_mx);
		return m_available && a_module && a_view && Find(a_module, a_view) != nullptr;
	}

	bool UIHost::Interop(const char* a_module, const char* a_view, const char* a_channel, const std::string& a_text)
	{
		std::lock_guard lk(m_mx);
		View* v = (a_module && a_view) ? Find(a_module, a_view) : nullptr;
		if (!m_available || !v || !a_channel || !*a_channel) return false;
		if (v->domReady) m_ml->InteropCall(v->id, a_channel, a_text.c_str());
		else v->pendingInterop.emplace_back(a_channel, a_text);
		return true;
	}

	bool UIHost::OpenPanelView(bool a_pause, const std::string& a_ctxJson)
	{
		std::lock_guard lk(m_mx);
		View* v = Find(PanelHost::kModule, PanelHost::kView);
		if (!m_available || !v) return false;
		m_ml->ShowView(v->id, true);
		const std::uint32_t mlFlags = a_pause ? ML::kUIModeFlagPause : ML::kUIModeFlagNone;
		if (const auto r = m_ml->RequestUIMode(v->id, mlFlags); r != ML::Result::Ok) {
			SKSE::log::warn("[DeDService][PANEL] UI mode not granted ({}): {}", static_cast<int>(r), Str(m_ml->GetLastErrorMessage(m_mod)));
			m_ml->ShowView(v->id, false);
			return false;
		}
		v->open = v->focused = true;
		if (v->domReady) m_ml->InteropCall(v->id, "dedOpen", a_ctxJson.c_str());
		else v->pendingInterop.emplace_back("dedOpen", a_ctxJson);
		return true;
	}

	void UIHost::NotifyClosed(const std::string& a_module, const std::string& a_view, DeDUI::CloseReason a_reason)
	{
		Handler h;
		{
			std::lock_guard lk(m_mx);
			h = HandlerFor(a_module);
		}
		SKSE::log::info("[DeDService][UI] view {}.{} closed by the player/host (reason {}) -> module notified: {}.",
			a_module, a_view, static_cast<int>(a_reason), h.closed ? "yes" : "no handler");
		if (h.closed) h.closed(a_module.c_str(), a_view.c_str(), a_reason, h.user);
	}

	// Game thread (ModDesc.callbackThread = GameThread).
	void UIHost::OnEvent(const ML::EventData* a_ev, void* a_user)
	{
		auto* self = static_cast<UIHost*>(a_user);
		if (!self || !a_ev) return;
		std::string notifyModule, notifyView;
		DeDUI::CloseReason reason = DeDUI::CloseReason::Escape;
		{
			std::lock_guard lk(self->m_mx);
			if (a_ev->type == ML::Event::RenderDead) {
				SKSE::log::error("[DeDService][UI] Magelight renderer died -- DeD menus unavailable this session.");
				self->m_available = false;
				for (auto& v : self->m_views) {
					if (v.open) {
						v.open = v.focused = false;
						notifyModule = v.module; notifyView = v.name; reason = DeDUI::CloseReason::RenderDead;
					}
				}
			} else if (View* v = self->FindById(a_ev->view)) {
				switch (a_ev->type) {
				case ML::Event::ViewDomReady:
					v->domReady = true;
					for (const auto& s : v->pending) self->m_ml->InvokeJS(v->id, s.c_str());
					if (!v->pending.empty()) {
						SKSE::log::info("[DeDService][UI] view {}.{} ready -- {} queued call(s) run.", v->module, v->name, v->pending.size());
					}
					v->pending.clear();
					for (const auto& [ch, text] : v->pendingInterop) self->m_ml->InteropCall(v->id, ch.c_str(), text.c_str());
					v->pendingInterop.clear();
					break;
				case ML::Event::ViewReloaded:
				case ML::Event::ViewDestroyed:
					v->domReady = false;
					break;
				case ML::Event::UIModeExited:
				case ML::Event::UIModeRefused:
					if (v->expectExit > 0) {
						--v->expectExit;
					} else if (v->open && v->focused) {
						v->open = v->focused = false;
						self->m_ml->ShowView(v->id, false);
						notifyModule = v->module; notifyView = v->name;
						reason = (a_ev->type == ML::Event::UIModeRefused) ? DeDUI::CloseReason::Refused : DeDUI::CloseReason::Escape;
					}
					break;
				case ML::Event::ViewLoadFailed:
					SKSE::log::error("[DeDService][UI] view {}.{} failed to load: {}", v->module, v->name, Str(a_ev->detail));
					if (v->open) {
						v->open = v->focused = false;
						notifyModule = v->module; notifyView = v->name; reason = DeDUI::CloseReason::LoadFailed;
					}
					break;
				default:
					break;
				}
			}
		}
		if (notifyModule == PanelHost::kModule) PanelHost::GetSingleton().OnClosed(static_cast<int>(reason));
		else if (!notifyModule.empty()) self->NotifyClosed(notifyModule, notifyView, reason);
	}

	// RENDER thread (or Magelight's page thread): copy, then hand to the game thread.
	void UIHost::OnJs(ML::ViewId, const char* a_payload, void* a_user)
	{
		const auto* ctx  = static_cast<const ListenerCtx*>(a_user);
		auto&       self = GetSingleton();
		if (!ctx || !self.m_ml) return;
		auto* task = new PickTask{ ctx->module, ctx->view, ctx->listener, Str(a_payload) };
		const auto r = self.m_ml->PostGameTask(
			[](void* a_task) {
				std::unique_ptr<PickTask> t(static_cast<PickTask*>(a_task));
				if (t->module == PanelHost::kModule) {   // the combined panel's page protocol
					PanelHost::GetSingleton().OnPage(t->listener, t->payload);
					return;
				}
				auto& host = UIHost::GetSingleton();
				UIHost::Handler h;
				{
					std::lock_guard lk(host.m_mx);
					h = host.HandlerFor(t->module);
				}
				SKSE::log::info("[DeDService][UI] pick {}.{} {}('{}') -> module {}.", t->module, t->view, t->listener,
					t->payload.size() > 200 ? t->payload.substr(0, 200) + "..." : t->payload, h.pick ? "handler" : "NO HANDLER");
				if (h.pick) h.pick(t->module.c_str(), t->view.c_str(), t->listener.c_str(), t->payload.c_str(), h.user);
			},
			task);
		if (r != ML::Result::Ok) {
			delete task;   // the host refused the post (shutting down): the pick is dropped
		}
	}
}

// The DeDUI C ABI entry point (DeDUI_API.h: DeDUI::RequestApi1).
extern "C" __declspec(dllexport) const void* DeDUI_RequestApi(std::uint32_t a_version)
{
	if (a_version == DeDUI::kApiVersion1) return DeD::UIHost::GetSingleton().Api();
	if (a_version == DeDUI::kApiVersion2) return DeD::UIHost::GetSingleton().Api2();   // starts with Api1's members
	return nullptr;
}
