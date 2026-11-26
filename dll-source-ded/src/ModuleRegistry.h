#pragma once
// ModuleRegistry -- DeD module descriptors (Magelight workstream, Phase 1).
// Reads Data/Magelight/DeD/modules/*.json at kDataLoaded and keeps a module only
// when its required plugin is loaded (ruleset rule 16: a module the player did
// not install contributes nothing). Descriptor schema v1:
//   {
//     "schema": 1,
//     "id": "baka",                                   // [a-z0-9_-], unique
//     "name": "Baka Interactions",                    // display name (logs; UI text later)
//     "requires": "SkyrimNet_BakaIntegration.esp",    // plugin that must be loaded ("" = none)
//     "views": [
//       { "name": "menu", "page": "views/baka/menu/index.html",   // relative to Data/Magelight/DeD/
//         "layer": "panel",                                         // hud | panel | popup | system
//         "listeners": ["snbaka_chose"],                            // window.<name>(payload) -> PickFn
//         "clickThrough": false, "startVisible": false,             // views are fullscreen in Phase 1
//         "captureEscape": true }   // Escape goes to the page; Magelight's toggle key still closes the view
//     ]
//   }
// Schema 2 (Magelight Phase 2, spec docs/specs/magelight-phase2-spec.md 3.2) = schema 1 plus
// an optional "panel" block; a module without it has no rail entry:
//   "panel": {
//     "tagline": "touch, force, take",   // rail sub-line (placeholder text until registered)
//     "order": 10,                        // rail order, ascending (D-P5)
//     "rules": [                          // routing when the DeD power opens the panel; highest priority wins
//       { "priority": 70, "when": { "target": "any", "target.downed": true },
//         "open": { "tab": "down", "mode": "downed", "pause": true } },
//       { "priority": 80, "when": { "target.creature": true }, "claim": "creature_escalate" },
//       { "priority": 90, "when": { "target.in_scene": true }, "refuse": "target_busy" }
//     ]
//   }
// "when": "target" is "any" | "none"; "target.<flag>" / "caster.<flag>" are booleans over PanelFlags
// plus the native flags creature / in_combat. A descriptor whose plugin is not loaded is kept as
// "absent" (id, name, tagline, order) so the rail can grey it.
// ASCII only.

#include <cstdint>
#include <filesystem>
#include <mutex>
#include <string>
#include <vector>

namespace DeD
{
	struct ViewSpec
	{
		std::string              name;
		std::string              page;          // relative to Data/Magelight/DeD/
		std::string              layer = "panel";
		std::vector<std::string> listeners;
		bool                     clickThrough = false;
		bool                     startVisible = false;
		bool                     captureEscape = false;   // the page handles Escape itself (e.g. wizard Back)
	};

	struct PanelRule
	{
		int                                       priority = 0;
		std::string                               target;      // "", "any" or "none"
		std::vector<std::pair<std::string, bool>> conds;       // "target.downed" -> true
		std::string                               action;      // "open" | "claim" | "refuse"
		std::string                               tab, mode, event;
		bool                                      pause = true;
	};

	struct ModuleSpec
	{
		std::string           id;
		std::string           name;
		std::string           requiredPlugin;
		std::filesystem::path file;             // descriptor path (logs)
		std::vector<ViewSpec> views;
		// schema 2 panel block
		bool                   hasPanel = false;
		std::string            tagline;
		std::string            settingsVia;   // S323: "mcm" = the panel's Settings for this module are served by DeD_MCM (Phase 3)
		int                    order = 100;
		std::vector<PanelRule> rules;
	};

	class ModuleRegistry
	{
	public:
		static ModuleRegistry& GetSingleton();

		// kDataLoaded, game thread. Returns the number of installed modules.
		std::size_t Load(const std::filesystem::path& a_dedRoot);

		bool                    IsInstalled(std::string_view a_id) const;
		std::vector<ModuleSpec> Modules() const;   // copy (thread-safe)
		std::vector<ModuleSpec> Absent() const;    // descriptors whose plugin is not loaded (rail greys them)
		const ModuleSpec*       FindUnsafe(std::string_view a_id) const;   // caller holds no lock; data is fixed after Load

	private:
		mutable std::mutex      m_mx;
		std::vector<ModuleSpec> m_modules;
		std::vector<ModuleSpec> m_absent;
	};
}
