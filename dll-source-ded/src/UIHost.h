#pragma once
// UIHost -- DeDService's Magelight host (Magelight workstream, Phase 1; spec:
// docs/workstreams/magelight-ui.md section 6c). Owns the Magelight mod "DeD",
// creates every installed module's views at kDataLoaded, owns UI mode, and
// routes page picks / closes back to the owning module through DeDUI_API.h.
// Holds no module logic (ruleset rule 16). ASCII only.

#include <cstdint>
#include <deque>
#include <filesystem>
#include <mutex>
#include <string>
#include <vector>

#include "DeDUI_API.h"
#include "MagelightUI_API.h"
#include "ModuleRegistry.h"

namespace DeD
{
	class UIHost
	{
	public:
		static UIHost& GetSingleton();

		// kDataLoaded, game thread, after ModuleRegistry::Load.
		void Init(const std::filesystem::path& a_dedRoot);

		bool IsAvailable() const;
		const DeDUI::Api1* Api() const;
		const DeDUI::Api2* Api2() const;

		// DeDUI::Api1 implementation (any thread).
		bool SetHandler(const char* a_module, DeDUI::PickFn a_pick, DeDUI::ClosedFn a_closed, void* a_user);
		bool OpenView(const char* a_module, const char* a_view, const char* a_jsCall, std::uint32_t a_flags);
		bool InvokeView(const char* a_module, const char* a_view, const char* a_script);
		bool CloseView(const char* a_module, const char* a_view);
		bool ShowView(const char* a_module, const char* a_view, bool a_show);

		// Phase 2 (PanelHost). Any thread.
		bool HasView(const char* a_module, const char* a_view);
		// Show the Framework panel, hand the page its open context ("dedOpen"), take UI mode.
		bool OpenPanelView(bool a_pause, const std::string& a_ctxJson);
		// window.<channel>(text) or the SDK channel of that name; queued until the page is ready.
		bool Interop(const char* a_module, const char* a_view, const char* a_channel, const std::string& a_text);

	private:
		struct View
		{
			std::string              module;
			std::string              name;
			MAGELIGHT_API::ViewId    id = 0;
			bool                     domReady = false;
			bool                     open = false;      // opened by OpenView, not yet closed
			bool                     focused = false;   // holds (or requested) UI mode
			std::uint32_t            expectExit = 0;    // UI-mode exits we caused (CloseView) and must ignore
			std::vector<std::string> pending;           // scripts waiting for DOM ready
			std::vector<std::pair<std::string, std::string>> pendingInterop;   // (channel, text) waiting for DOM ready
		};
		struct Handler
		{
			std::string     module;
			DeDUI::PickFn   pick = nullptr;
			DeDUI::ClosedFn closed = nullptr;
			void*           user = nullptr;
		};
		struct ListenerCtx   // lives for the whole process (the host may call late)
		{
			std::string module;
			std::string view;
			std::string listener;
		};

		View*    Find(std::string_view a_module, std::string_view a_view);
		View*    FindById(MAGELIGHT_API::ViewId a_id);
		Handler  HandlerFor(const std::string& a_module);
		void     NotifyClosed(const std::string& a_module, const std::string& a_view, DeDUI::CloseReason a_reason);
		bool     CreateView(const std::string& a_module, const ViewSpec& a_spec, const std::filesystem::path& a_dedRoot);

		static void OnEvent(const MAGELIGHT_API::EventData* a_ev, void* a_user);
		static void OnJs(MAGELIGHT_API::ViewId a_view, const char* a_payload, void* a_user);

		mutable std::recursive_mutex     m_mx;
		const MAGELIGHT_API::MagelightApi4* m_ml = nullptr;
		MAGELIGHT_API::ModId             m_mod = 0;
		bool                             m_available = false;
		std::deque<View>                 m_views;      // deque: stable addresses
		std::vector<Handler>             m_handlers;
		std::deque<ListenerCtx>          m_listeners;  // never shrinks
	};
}
