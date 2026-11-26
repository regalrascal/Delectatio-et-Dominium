#pragma once
// PanelHost -- the combined DeD panel's routing and page protocol (Magelight Phase 2 legs 1 + 3;
// spec docs/specs/magelight-phase2-spec.md sections 2-4, 13, 15). The panel view itself ("ded.panel")
// is created and shown by UIHost; PanelHost decides WHERE it opens (routing rules from the module
// descriptors over PanelFlags + native flags), speaks the page protocol, and hands each request/action/
// setting to the module that owns it. Holds no module logic (rule 16). ASCII only.

#include <cstdint>
#include <map>
#include <mutex>
#include <set>
#include <string>
#include <vector>

#include "DeDUI_API.h"

namespace RE { class Actor; }

namespace DeD
{
	class PanelHost
	{
	public:
		static PanelHost& GetSingleton();

		// Any thread. Crosshair actor, else the nearest living (bleedout counts) actor within range.
		static RE::Actor* PickTarget();

		// The DeD power / hotkey / a module asking for default routing.
		//   a_flags: DeDUI::kPanelSkipClaims (a module already did its own routing), DeDUI::kPanelTargetGiven
		//   (use a_target as is, None = no target, instead of picking one).
		// False = nothing opened (no panel page, UI busy/unavailable, refused, claimed).
		bool Open(RE::Actor* a_caster, RE::Actor* a_target = nullptr, std::uint32_t a_flags = 0);
		// A module opens the panel on its own section in a mode it decided (e.g. Baka's downed menu).
		bool OpenAt(const std::string& a_module, const std::string& a_tab, const std::string& a_mode,
			RE::Actor* a_caster, RE::Actor* a_target, bool a_pause);
		// A module ends the panel (e.g. the last step of a step flow). Other visited modules get "closed".
		bool Close(const char* a_module);
		bool IsOpen() const;

		// Api2 surface (any thread).
		bool SetHandler(const char* a_module, DeDUI::PanelFn a_fn, void* a_user);
		bool Push(const char* a_module, const char* a_json);
		bool SettingResult(const char* a_module, const char* a_json);

		// From UIHost: a message from the panel page (game thread).
		void OnPage(const std::string& a_listener, const std::string& a_payload);
		// From UIHost: the panel left UI mode without us closing it (Escape, toggle key, refusal).
		void OnClosed(int a_reason);

		static constexpr const char* kModule = "ded";
		static constexpr const char* kView   = "panel";
		static const std::vector<std::string>& Listeners();   // ded_req, ded_act, ded_set, ded_close

	private:
		struct Handler
		{
			DeDUI::PanelFn fn = nullptr;
			void*          user = nullptr;
		};
		struct Place
		{
			std::string module, tab;
		};

		bool Show(const std::string& a_module, const std::string& a_tab, const std::string& a_mode, bool a_pause,
			const std::string& a_why, RE::Actor* a_caster, RE::Actor* a_target);
		void Dispatch(const std::string& a_module, const std::string& a_kind, const std::string& a_dataJson);
		// Ends the session: hides the panel (unless the host already did) and tells every visited module
		// except a_except that the panel closed.
		void DispatchToMcm(const std::string& a_module, const std::string& a_kind, const std::string& a_key, const std::string& a_value);
		void EndSession(const char* a_why, const std::string& a_except, bool a_hide, const std::string& a_reasonJson);

		mutable std::recursive_mutex   m_mx;
		std::map<std::string, Handler> m_handlers;
		bool                           m_open = false;
		std::string                    m_module, m_tab, m_mode;   // the section showing now
		std::uint32_t                  m_target = 0;              // target FormID of this opening (0 = none)
		std::set<std::string>          m_visited;                 // modules whose section was shown this opening
		std::map<std::string, Place>   m_last;                    // "target" / "notarget" -> last place (D-P1, 3.3)
	};
}
