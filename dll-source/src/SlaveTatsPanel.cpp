// Magelight Phase 2 leg 5 -- the SlaveTats section of the combined DeD panel
// (docs/specs/magelight-phase2-spec.md 5.4 and 17). The SlaveTats module is Papyrus only
// (SNBaka_SlaveTatsModule, recordless); this framework DLL holds its panel handler and hands every
// request / action / setting / close to the module's global PanelMsg, which answers through
// DeDService.PanelPush / PanelSettingResult. Also: the automatic pack scan on every game load
// (OnGameLoaded) and the Down-menu "Apply Tattoo" route opening the panel's tattoo section. ASCII only.
#include "DeDPanelClient.h"

#include <cstdlib>
#include <format>

#include <nlohmann/json.hpp>

bool SlaveTatsSetCustomDescription(const std::string& a_section, const std::string& a_name, const std::string& a_text);   // SlaveTatsNative.cpp

namespace
{
    constexpr const char* kST = "slavetats";
    // S316: the same bridge serves every Papyrus-only module section (SlaveTats, Fill Her Up).
    struct Bridge { const char* module; const char* script; std::atomic<bool> set{ false }; bool refusedLogged = false; };
    Bridge g_bridges[] = { { "slavetats", "SNBaka_SlaveTatsModule" }, { "fhu", "SNBaka_FHUInflationModule" },
        { "cum", "SNBaka_CumDetectionModule" } };   // S324: the Cum Management status page

    // First "key":"value" string (our own and DeDService's flat-enough messages; data sorts first).
    std::string Str(const std::string& j, const char* key)
    {
        const std::string pat = std::string("\"") + key + "\":\"";
        const auto at = j.find(pat);
        if (at == std::string::npos) return {};
        std::string out;
        for (std::size_t i = at + pat.size(); i < j.size(); ++i) {
            const char c = j[i];
            if (c == '\\' && i + 1 < j.size()) { out += j[++i]; continue; }
            if (c == '"') break;
            out += c;
        }
        return out;
    }

    // The raw JSON text of "key": a quoted string (quotes kept), or a bare token up to , } ].
    std::string Raw(const std::string& j, const char* key)
    {
        const std::string pat = std::string("\"") + key + "\":";
        const auto at = j.find(pat);
        if (at == std::string::npos) return {};
        std::size_t i = at + pat.size();
        if (i < j.size() && j[i] == '"') {
            std::size_t k = i + 1;
            for (; k < j.size(); ++k) {
                if (j[k] == '\\') { ++k; continue; }
                if (j[k] == '"') break;
            }
            return j.substr(i, k - i + 1);
        }
        std::size_t k = i;
        while (k < j.size() && j[k] != ',' && j[k] != '}' && j[k] != ']') ++k;
        return j.substr(i, k - i);
    }

    void CallModule(const char* fn, RE::BSScript::IFunctionArguments* args, const char* script = "SNBaka_SlaveTatsModule")
    {
        auto* vm = RE::BSScript::Internal::VirtualMachine::GetSingleton();
        if (!vm) { delete args; SKSE::log::error("[SNBaka][PANEL] {}.{}: VM unavailable.", script, fn); return; }
        RE::BSTSmartPointer<RE::BSScript::IStackCallbackFunctor> cb;
        vm->DispatchStaticCall(RE::BSFixedString(script), RE::BSFixedString(fn), args, cb);
        delete args;
    }
}

// Sets the panel handler of every Papyrus-only module section that is installed. True = SlaveTats' is set.
bool DeDPanelClient::STPanelInit() noexcept
{
    if (!EnsureUI()) return false;
    if (!s_ui2) s_ui2 = DeDUI::RequestApi2();
    if (!s_ui2 || !s_ui2->PanelAvailable()) return false;
    for (auto& b : g_bridges) {
        if (b.set.load()) continue;
        if (!s_ui2->SetPanelHandler(b.module, &DeDPanelClient::OnSTPanel, nullptr)) {
            if (!b.refusedLogged) {
                b.refusedLogged = true;
                SKSE::log::info("[SNBaka][PANEL] no '{}' section (module not installed) - handler not set.", b.module);
            }
            continue;
        }
        b.set = true;
        SKSE::log::info("[SNBaka][PANEL] '{}' section handler set (requests go to {}.PanelMsg).", b.module, b.script);
    }
    return g_bridges[0].set.load();
}

static bool module_is_slavetats(const char* a_module) { return a_module && std::string_view(a_module) == "slavetats"; }

// Game thread (DeDService PanelFn). The module answers asynchronously (Papyrus) through PanelPush.
void DeDPanelClient::OnSTPanel(const char* moduleId, const char* kind, const char* json, std::uint32_t targetFormID, void*)
{
    const char* script = "SNBaka_SlaveTatsModule";
    for (const auto& b : g_bridges) if (moduleId && std::string_view(moduleId) == b.module) script = b.script;
    const std::string k = kind ? kind : "";
    const std::string j = json ? json : "";
    std::string section = Str(j, "section");
    if (section.empty()) section = "main";
    const auto tab   = Str(j, "tab");
    const auto pick  = Str(j, "pick");
    const auto key   = Str(j, "key");
    const auto value = k == "set" ? Raw(j, "value") : std::string{};
    // S326: "desc|<section>|<name>" + text = a tattoo description edit; saved here, then the module re-pushes.
    if (module_is_slavetats(moduleId) && k == "act" && pick.rfind("desc|", 0) == 0) {
        const auto a = pick.find('|', 5);
        if (a != std::string::npos) {
            const auto parsed = nlohmann::json::parse(j, nullptr, false);
            std::string text;
            if (!parsed.is_discarded() && parsed.contains("data") && parsed["data"].is_object()) text = parsed["data"].value("text", std::string{});
            SlaveTatsSetCustomDescription(pick.substr(5, a - 5), pick.substr(a + 1), text);
        }
    }
    auto* target = targetFormID ? RE::TESForm::LookupByID<RE::Actor>(targetFormID) : nullptr;
    SKSE::log::info("[SNBaka][PANEL] {} {} section={} tab={} pick={} key={} target 0x{:08X} -> {}.PanelMsg.", moduleId ? moduleId : "?", k, section, tab, pick, key, targetFormID, script);
    auto* args = RE::MakeFunctionArguments(RE::BSFixedString(k.c_str()), RE::BSFixedString(section.c_str()), RE::BSFixedString(tab.c_str()),
        RE::BSFixedString(pick.c_str()), RE::BSFixedString(key.c_str()), RE::BSFixedString(value.c_str()), static_cast<RE::Actor*>(target));
    CallModule("PanelMsg", args, script);
}

// kPostLoadGame / kNewGame: the panel handler, then the automatic pack scan (SlaveTats' cache rides the
// save, so every load rescans; the module logs added / removed packs).
void DeDPanelClient::OnGameLoaded() noexcept
{
    // S320 fix (REV-193 dogfood): Baka's own panel handler must exist BEFORE the first DeD Interact press -
    // DeDService hands the press to Baka as a claim, and with no handler it fell back to a ModEvent nobody
    // listens to (the power did nothing). PanelReady sets Baka's handler and then the SlaveTats / FHU ones.
    if (!PanelReady()) {
        SKSE::log::warn("[SNBaka][PANEL] game loaded: the combined panel is not available - Baka handler not set (Phase 1 menus stay).");
        STPanelInit();
    }
    SKSE::log::info("[SNBaka.ST] game loaded - asking the SlaveTats module to rescan packs.");
    CallModule("OnGameLoaded", RE::MakeFunctionArguments());
}

// The actor-bound picker (Down-menu Apply Tattoo, player-initiated CommandTattoo) on the panel: opens the
// SlaveTats section on that actor. False = no panel; the caller opens the Phase 1 picker view.
bool DeDPanelClient::OpenSTPanelPicker(const std::string& json) noexcept
{
    if (json.find("\"mode\":\"picker\"") == std::string::npos) return false;
    if (!PanelReady() || !STPanelInit()) return false;
    const auto at = json.find("\"tid\":");
    if (at == std::string::npos) return false;
    const auto tid = static_cast<std::uint32_t>(std::strtoll(json.c_str() + at + 6, nullptr, 10));
    auto* player = RE::PlayerCharacter::GetSingleton();
    SKSE::log::info("[SNBaka.ST][PANEL] picker -> the panel's SlaveTats section (target 0x{:08X}).", tid);
    if (!s_ui2->OpenPanelAt(kST, "tattoo", "picker", player ? player->GetFormID() : 0, tid, true)) {
        SKSE::log::warn("[SNBaka.ST][PANEL] the panel did not open - falling back to the picker view.");
        return false;
    }
    return true;
}
