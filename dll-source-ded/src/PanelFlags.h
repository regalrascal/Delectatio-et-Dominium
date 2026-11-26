#pragma once
// PanelFlags -- per-actor context flags for the DeD panel's routing (Magelight Phase 2,
// spec docs/specs/magelight-phase2-spec.md section 3.1). Modules publish what they know
// ("downed", "in_scene", "locked_by_other", "grappling", ...) when their state changes;
// DeDService reads them when the panel opens. A flag is ON while at least one module
// asserts it. Keyed by actor FormID, in memory only, no expiry, dropped on load/new game
// (modules re-publish from their own persisted state). Not ActorContextStore: that one
// caches SkyrimNet bio facts by SkyrimNet uuid with fixed fact classes and TTLs.
// ASCII only.

#include <cstdint>
#include <map>
#include <mutex>
#include <set>
#include <string>
#include <vector>

namespace DeD
{
	class PanelFlags
	{
	public:
		static PanelFlags& GetSingleton();

		// a_on = false withdraws this module's assertion. False on bad input.
		bool Set(std::uint32_t a_formID, const std::string& a_module, const std::string& a_flag, bool a_on);
		bool Has(std::uint32_t a_formID, const std::string& a_flag) const;
		std::vector<std::string> FlagsOf(std::uint32_t a_formID) const;   // sorted, ON flags only
		void Revert();

	private:
		mutable std::mutex m_mx;
		// formID -> flag -> modules asserting it
		std::map<std::uint32_t, std::map<std::string, std::set<std::string>>> m_flags;
	};
}
