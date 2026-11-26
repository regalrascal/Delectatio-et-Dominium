#pragma once
// DeDUI_API.h -- the DeD UI host contract (DeDService.dll), protocol v1 + v2 (the combined panel).
//
// DeDService is the DeD "motherboard" (ruleset rule 16). It hosts every DeD
// Magelight view; module DLLs (Baka, GS, ...) keep all of their own logic and
// drive their views through this small C ABI. Header-only; nothing to link:
// a module resolves the API at runtime, so a module still loads (and falls
// back) when DeDService.dll or Magelight is absent.
//
//   const DeDUI::Api1* ui = DeDUI::RequestApi1();     // nullptr = DeDService absent/older
//   if (ui && ui->IsAvailable()) {
//       ui->SetHandler("baka", &OnPick, &OnClosed, nullptr);
//       ui->OpenView("baka", "menu", "window.snbaka_open_interact('{...}')", DeDUI::kOpenFocus | DeDUI::kOpenPause);
//   }
//
// Threading: every function may be called from any thread. Handlers
// (PickFn / ClosedFn) always run on the GAME thread, so RE:: state is safe
// there. Strings passed to a handler are valid only for that call.
//
// Views are declared by the module's descriptor, Data/Magelight/DeD/modules/<id>.json
// (installed by the module's own FOMOD option). A module whose descriptor is
// missing, or whose required plugin is not loaded, is "not installed": every
// call naming it returns false.
//
// ASCII only. Append-only: new functions go at the END of Api1 or in Api2.

#include <cstdint>

#ifndef DEDUI_API_NO_LOADER
#	include <windows.h>
#endif

namespace DeDUI
{
	inline constexpr std::uint32_t kApiVersion1 = 1;
	inline constexpr std::uint32_t kApiVersion2 = 2;

	// OpenView flags.
	inline constexpr std::uint32_t kOpenNone  = 0;
	inline constexpr std::uint32_t kOpenFocus = 1;  // take UI mode (cursor + keyboard); without it the view only shows
	inline constexpr std::uint32_t kOpenPause = 2;  // with kOpenFocus: pause the game while open

	// ClosedFn reasons: the view left UI mode without the module closing it.
	enum class CloseReason : std::uint32_t
	{
		Escape     = 0,  // the player left (Escape, Magelight toggle key, load boundary)
		Refused    = 1,  // UI mode was not granted after the request (host refused / lost race)
		LoadFailed = 2,  // the page failed to load
		RenderDead = 3,  // Magelight's renderer died this session
	};

	// payload: the string the page passed to window.<listener>(payload).
	using PickFn   = void (*)(const char* moduleId, const char* view, const char* listener, const char* payload, void* user);
	using ClosedFn = void (*)(const char* moduleId, const char* view, CloseReason reason, void* user);

	struct Api1
	{
		std::uint32_t apiVersion;   // = kApiVersion1

		// DeDService loaded, Magelight acquired, views created.
		bool (*IsAvailable)();
		// The module's descriptor was found and its required plugin is loaded.
		bool (*IsModuleInstalled)(const char* moduleId);
		// One pick handler + one close handler per module (replaces any earlier pair).
		bool (*SetHandler)(const char* moduleId, PickFn onPick, ClosedFn onClosed, void* user);
		// Show the view, run jsCall once its page is ready (nullptr/"" = none), and take
		// UI mode if kOpenFocus. False = not opened (unknown view, UI unavailable, or
		// another mod holds UI mode): treat it exactly like a cancel.
		bool (*OpenView)(const char* moduleId, const char* view, const char* jsCall, std::uint32_t flags);
		// Run a script on the view's page (fire and forget). Queued until the page is ready.
		bool (*InvokeView)(const char* moduleId, const char* view, const char* script);
		// Release UI mode (if this view holds it) and hide the view. No ClosedFn follows.
		bool (*CloseView)(const char* moduleId, const char* view);
		// Show or hide a view without touching UI mode (HUD widgets).
		bool (*ShowView)(const char* moduleId, const char* view, bool show);
	};

	// ---- v2: the combined DeD panel (Magelight Phase 2; docs/specs/magelight-phase2-spec.md) ----
	// The panel ("ded.panel") is the Framework's view. A module fills its own section: the page asks
	// for data and sends actions/settings; DeDService routes each to the module that owns it, through
	// the module's PanelFn when one is set, else as a ModEvent "DeD_Panel_<moduleId>" (strArg = the same
	// JSON, sender = the target actor) for Papyrus-only modules.
	// kind: "req" (page wants a section's data), "act" (an action was picked), "set" (a setting changed),
	//       "claim" (a routing rule handed the power press to the module; no panel opened),
	//       "closed" (the panel closed while this module's section was showing).
	// json: {"type":kind,"module":id,"target":"0x...","data":{...page payload...},"route":{...}}
	using PanelFn = void (*)(const char* moduleId, const char* kind, const char* json, std::uint32_t targetFormID, void* user);

	// OpenPanelEx flags.
	inline constexpr std::uint32_t kPanelSkipClaims  = 1;  // the caller already did its own routing: no claim rule fires
	inline constexpr std::uint32_t kPanelTargetGiven = 2;  // use targetFormID as is (0 = no target) instead of picking one

	// Api2 starts with Api1's members in the same order (apiVersion = 2), so an Api2 pointer also
	// serves Api1 callers.
	struct Api2
	{
		std::uint32_t apiVersion;   // = kApiVersion2
		bool (*IsAvailable)();
		bool (*IsModuleInstalled)(const char* moduleId);
		bool (*SetHandler)(const char* moduleId, PickFn onPick, ClosedFn onClosed, void* user);
		bool (*OpenView)(const char* moduleId, const char* view, const char* jsCall, std::uint32_t flags);
		bool (*InvokeView)(const char* moduleId, const char* view, const char* script);
		bool (*CloseView)(const char* moduleId, const char* view);
		bool (*ShowView)(const char* moduleId, const char* view, bool show);

		// One panel handler per module (replaces any earlier one). Runs on the game thread.
		bool (*SetPanelHandler)(const char* moduleId, PanelFn fn, void* user);
		// Section data for the page (a JSON object; "module" is filled in when missing).
		bool (*PanelPush)(const char* moduleId, const char* json);
		// Confirm a settings write: {"key":..,"value":..,"ok":true|false,"reason":".."}.
		bool (*PanelSettingResult)(const char* moduleId, const char* json);
		// Publish a routing flag for an actor ("downed", "in_scene", ...); on = false withdraws it.
		bool (*PanelSetFlag)(std::uint32_t actorFormID, const char* moduleId, const char* flag, bool on);
		// The DeD power's open request (casterFormID 0 = the player). Runs the routing rules.
		bool (*OpenPanel)(std::uint32_t casterFormID);
		// The interact target the panel would use now (crosshair, else nearest living actor in range); 0 = none.
		std::uint32_t (*PanelTarget)();

		// ---- appended in leg 3 (module-driven opening) ----
		// The panel page is installed and Magelight is up: a module may open the panel instead of its own view.
		bool (*PanelAvailable)();
		// Default routing with options (kPanelSkipClaims, kPanelTargetGiven). Synchronous; any thread.
		bool (*OpenPanelEx)(std::uint32_t casterFormID, std::uint32_t targetFormID, std::uint32_t flags);
		// Open the panel on this module's section in a mode the module decided. Synchronous; any thread.
		bool (*OpenPanelAt)(const char* moduleId, const char* tab, const char* mode, std::uint32_t casterFormID,
			std::uint32_t targetFormID, bool pause);
		// End the panel from the module (e.g. a step flow finished). Other visited modules get "closed".
		bool (*ClosePanel)(const char* moduleId);
	};

#ifndef DEDUI_API_NO_LOADER
	// Resolve the API exported by DeDService.dll. nullptr = DeDService absent or older.
	inline const Api1* RequestApi1()
	{
		using RequestFn = const void* (*)(std::uint32_t);
		const HMODULE mod = ::GetModuleHandleW(L"DeDService.dll");
		if (!mod) return nullptr;
		const auto fn = reinterpret_cast<RequestFn>(::GetProcAddress(mod, "DeDUI_RequestApi"));
		return fn ? static_cast<const Api1*>(fn(kApiVersion1)) : nullptr;
	}

	// nullptr = DeDService absent or older than protocol v2.
	inline const Api2* RequestApi2()
	{
		using RequestFn = const void* (*)(std::uint32_t);
		const HMODULE mod = ::GetModuleHandleW(L"DeDService.dll");
		if (!mod) return nullptr;
		const auto fn = reinterpret_cast<RequestFn>(::GetProcAddress(mod, "DeDUI_RequestApi"));
		return fn ? static_cast<const Api2*>(fn(kApiVersion2)) : nullptr;
	}
#endif
}
