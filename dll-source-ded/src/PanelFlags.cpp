#include "PCH.h"
#include "PanelFlags.h"

#include <algorithm>

namespace DeD
{
	namespace
	{
		bool ValidName(const std::string& a_s)
		{
			if (a_s.empty() || a_s.size() > 32) return false;
			return std::all_of(a_s.begin(), a_s.end(), [](char c) {
				return (c >= 'a' && c <= 'z') || (c >= '0' && c <= '9') || c == '_' || c == '-';
			});
		}
	}

	PanelFlags& PanelFlags::GetSingleton()
	{
		static PanelFlags s;
		return s;
	}

	bool PanelFlags::Set(std::uint32_t a_formID, const std::string& a_module, const std::string& a_flag, bool a_on)
	{
		if (!a_formID || !ValidName(a_module) || !ValidName(a_flag)) {
			SKSE::log::warn("[DeDService][PANEL] flag refused: actor {:08X} module '{}' flag '{}'.", a_formID, a_module, a_flag);
			return false;
		}
		std::lock_guard lk(m_mx);
		auto& byFlag = m_flags[a_formID];
		auto& mods   = byFlag[a_flag];
		const bool before = !mods.empty();
		if (a_on) mods.insert(a_module); else mods.erase(a_module);
		const bool after = !mods.empty();
		if (mods.empty()) byFlag.erase(a_flag);
		if (byFlag.empty()) m_flags.erase(a_formID);
		if (before != after) {
			SKSE::log::info("[DeDService][PANEL] flag {:08X}.{} {} (by {}).", a_formID, a_flag, after ? "ON" : "OFF", a_module);
		}
		return true;
	}

	bool PanelFlags::Has(std::uint32_t a_formID, const std::string& a_flag) const
	{
		std::lock_guard lk(m_mx);
		const auto it = m_flags.find(a_formID);
		if (it == m_flags.end()) return false;
		const auto f = it->second.find(a_flag);
		return f != it->second.end() && !f->second.empty();
	}

	std::vector<std::string> PanelFlags::FlagsOf(std::uint32_t a_formID) const
	{
		std::vector<std::string> out;
		std::lock_guard lk(m_mx);
		const auto it = m_flags.find(a_formID);
		if (it == m_flags.end()) return out;
		for (const auto& [flag, mods] : it->second) {
			if (!mods.empty()) out.push_back(flag);
		}
		return out;
	}

	void PanelFlags::Revert()
	{
		std::lock_guard lk(m_mx);
		const auto n = m_flags.size();
		m_flags.clear();
		if (n) SKSE::log::info("[DeDService][PANEL] flags dropped on load/new game ({} actor(s)).", n);
	}
}
