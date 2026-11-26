#include "PCH.h"
#include "ModuleRegistry.h"

#include <algorithm>
#include <fstream>

#include <nlohmann/json.hpp>

namespace DeD
{
	namespace
	{
		bool ValidId(const std::string& a_id)
		{
			if (a_id.empty() || a_id.size() > 32) return false;
			return std::all_of(a_id.begin(), a_id.end(), [](char c) {
				return (c >= 'a' && c <= 'z') || (c >= '0' && c <= '9') || c == '_' || c == '-';
			});
		}

		bool ValidLayer(const std::string& a_layer)
		{
			return a_layer == "hud" || a_layer == "panel" || a_layer == "popup" || a_layer == "system";
		}

		// Schema 2 "panel" block. Bad rules are skipped with a log line; the module still loads.
		void ReadPanel(const nlohmann::json& a_j, ModuleSpec& a_m)
		{
			const auto it = a_j.find("panel");
			if (it == a_j.end() || !it->is_object()) return;
			const auto& p = *it;
			a_m.hasPanel = true;
			a_m.tagline  = p.value("tagline", std::string{});
			a_m.settingsVia = p.value("settingsVia", std::string{});
			a_m.order    = p.value("order", 100);
			for (const auto& r : p.value("rules", nlohmann::json::array())) {
				if (!r.is_object()) continue;
				PanelRule rule;
				rule.priority = r.value("priority", 0);
				for (const auto& [k, v] : r.value("when", nlohmann::json::object()).items()) {
					if (k == "target" && v.is_string()) rule.target = v.get<std::string>();
					else if (v.is_boolean() && (k.rfind("target.", 0) == 0 || k.rfind("caster.", 0) == 0)) rule.conds.emplace_back(k, v.get<bool>());
					else SKSE::log::warn("[DeDService][PANEL] registry: module '{}' rule {}: unknown condition '{}' ignored.", a_m.id, rule.priority, k);
				}
				if (r.contains("open") && r["open"].is_object()) {
					rule.action = "open";
					rule.tab    = r["open"].value("tab", std::string{});
					rule.mode   = r["open"].value("mode", std::string{});
					rule.pause  = r["open"].value("pause", true);
				} else if (r.contains("claim") && r["claim"].is_string()) {
					rule.action = "claim";
					rule.event  = r["claim"].get<std::string>();
				} else if (r.contains("refuse") && r["refuse"].is_string()) {
					rule.action = "refuse";
					rule.event  = r["refuse"].get<std::string>();
				} else {
					SKSE::log::warn("[DeDService][PANEL] registry: module '{}' rule {} skipped -- no open/claim/refuse.", a_m.id, rule.priority);
					continue;
				}
				if (!rule.target.empty() && rule.target != "any" && rule.target != "none") {
					SKSE::log::warn("[DeDService][PANEL] registry: module '{}' rule {} skipped -- target must be any/none.", a_m.id, rule.priority);
					continue;
				}
				a_m.rules.push_back(std::move(rule));
			}
		}

		// S340: a module that ships a DLL and no plugin (DeD Downed) names its DLL in "requiresDll".
		bool DllLoaded(const std::string& a_dll)
		{
			return a_dll.empty() || ::GetModuleHandleA(a_dll.c_str()) != nullptr;
		}

		bool PluginLoaded(const std::string& a_plugin)
		{
			if (a_plugin.empty()) return true;
			auto* dh = RE::TESDataHandler::GetSingleton();
			// Full and light (ESL-flagged) plugins live in separate lists.
			return dh && (dh->LookupLoadedModByName(a_plugin) != nullptr || dh->LookupLoadedLightModByName(a_plugin) != nullptr);
		}
	}

	ModuleRegistry& ModuleRegistry::GetSingleton()
	{
		static ModuleRegistry s;
		return s;
	}

	std::size_t ModuleRegistry::Load(const std::filesystem::path& a_dedRoot)
	{
		std::vector<ModuleSpec> found, absent;
		const auto dir = a_dedRoot / "modules";
		std::error_code ec;
		if (!std::filesystem::is_directory(dir, ec)) {
			SKSE::log::info("[DeDService][UI] registry: no modules folder at {} -- 0 modules.", dir.string());
		} else {
			for (const auto& entry : std::filesystem::directory_iterator(dir, ec)) {
				if (!entry.is_regular_file() || entry.path().extension() != ".json") continue;
				try {
					std::ifstream in(entry.path(), std::ios::binary);
					const auto j = nlohmann::json::parse(in);
					const int schema = j.value("schema", 0);
					if (schema != 1 && schema != 2) {
						SKSE::log::warn("[DeDService][UI] registry: {} skipped -- schema is not 1 or 2.", entry.path().filename().string());
						continue;
					}
					ModuleSpec m;
					m.id       = j.value("id", std::string{});
					m.name     = j.value("name", m.id);
					m.requiredPlugin = j.value("requires", std::string{});
					const auto requiredDll = j.value("requiresDll", std::string{});
					m.file     = entry.path();
					if (!ValidId(m.id)) {
						SKSE::log::warn("[DeDService][UI] registry: {} skipped -- bad id '{}'.", entry.path().filename().string(), m.id);
						continue;
					}
					if (std::any_of(found.begin(), found.end(), [&](const ModuleSpec& o) { return o.id == m.id; })) {
						SKSE::log::warn("[DeDService][UI] registry: {} skipped -- duplicate id '{}'.", entry.path().filename().string(), m.id);
						continue;
					}
					if (schema == 2) ReadPanel(j, m);
					// S328: a descriptor with no rail entry (no "panel" block) may still serve Settings through DeD_MCM
					// ("framework": the global DeD settings of the rail-foot Settings).
					if (m.settingsVia.empty()) m.settingsVia = j.value("settingsVia", std::string{});
					if (!DllLoaded(requiredDll)) {
						SKSE::log::info("[DeDService][UI] registry: module '{}' not installed -- '{}' is not loaded.", m.id, requiredDll);
						if (m.hasPanel) absent.push_back(std::move(m));
						continue;
					}
					if (!PluginLoaded(m.requiredPlugin)) {
						SKSE::log::info("[DeDService][UI] registry: module '{}' not installed -- '{}' is not loaded.", m.id, m.requiredPlugin);
						if (m.hasPanel) absent.push_back(std::move(m));
						continue;
					}
					for (const auto& v : j.value("views", nlohmann::json::array())) {
						ViewSpec vs;
						vs.name         = v.value("name", std::string{});
						vs.page         = v.value("page", std::string{});
						vs.layer        = v.value("layer", std::string{ "panel" });
						vs.clickThrough = v.value("clickThrough", false);
						vs.startVisible = v.value("startVisible", false);
						vs.captureEscape = v.value("captureEscape", false);
						for (const auto& l : v.value("listeners", nlohmann::json::array())) {
							if (l.is_string()) vs.listeners.push_back(l.get<std::string>());
						}
						if (!ValidId(vs.name) || vs.page.empty() || vs.page.find("..") != std::string::npos || !ValidLayer(vs.layer)) {
							SKSE::log::warn("[DeDService][UI] registry: module '{}' view '{}' skipped -- bad name, page or layer.", m.id, vs.name);
							continue;
						}
						m.views.push_back(std::move(vs));
					}
					SKSE::log::info("[DeDService][UI] registry: module '{}' installed ({} view(s){}).", m.id, m.views.size(),
						m.hasPanel ? fmt::format(", panel order {}, {} rule(s)", m.order, m.rules.size()) : std::string{});
					found.push_back(std::move(m));
				} catch (const std::exception& e) {
					SKSE::log::error("[DeDService][UI] registry: {} unreadable -- {}", entry.path().filename().string(), e.what());
				}
			}
		}
		std::lock_guard lk(m_mx);
		const auto byOrder = [](const ModuleSpec& a, const ModuleSpec& b) { return a.order < b.order || (a.order == b.order && a.id < b.id); };
		std::sort(found.begin(), found.end(), byOrder);
		std::sort(absent.begin(), absent.end(), byOrder);
		m_modules = std::move(found);
		m_absent  = std::move(absent);
		SKSE::log::info("[DeDService][UI] registry: {} module(s) installed.", m_modules.size());
		return m_modules.size();
	}

	bool ModuleRegistry::IsInstalled(std::string_view a_id) const
	{
		std::lock_guard lk(m_mx);
		return std::any_of(m_modules.begin(), m_modules.end(), [&](const ModuleSpec& m) { return m.id == a_id; });
	}

	std::vector<ModuleSpec> ModuleRegistry::Modules() const
	{
		std::lock_guard lk(m_mx);
		return m_modules;
	}

	std::vector<ModuleSpec> ModuleRegistry::Absent() const
	{
		std::lock_guard lk(m_mx);
		return m_absent;
	}

	const ModuleSpec* ModuleRegistry::FindUnsafe(std::string_view a_id) const
	{
		for (const auto& m : m_modules) {
			if (m.id == a_id) return &m;
		}
		return nullptr;
	}
}
