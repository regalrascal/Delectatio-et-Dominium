// S316 native streamlining for the SlaveTats module (SNBakaUI natives; Papyrus declarations in SNBakaUI.psc).
// The module used to walk SlaveTats' JContainers cache from Papyrus on every listing (and in SE each walk
// re-read Data/slavetats_cache.json from disk after release_cache). This reads the pack files directly with
// SlaveTats' own rules (SlaveTats.psc compile_cache / is_tattoo / _cache_tattoo): every *.json at the top of
// Data/Textures/Actors/Character/slavetats/, holding one tattoo object or an array of them; a tattoo needs a
// name, a section, an area of Body / Face / Hands / Feet and a texture; only the "default" domain is listed.
// Also the REV-150.1 male-wearable screen and an ASCII lower-case, both formerly char-by-char Papyrus loops.
#include "PapyrusFunctions.h"

#include <algorithm>
#include <cctype>
#include <chrono>
#include <deque>
#include <filesystem>
#include <fstream>
#include <map>
#include <mutex>
#include <shared_mutex>
#include <string>
#include <vector>

#include <nlohmann/json.hpp>   // vendored header-only, external/nlohmann (MIT)

std::string TattooVisualFacts(const std::string& a_texture, const std::string& a_area, std::string& a_why);   // TattooVision.cpp (S329)

namespace
{
    struct Entry { std::string name, area, texture; };
    struct Index
    {
        std::vector<std::string>                          sections;   // case-insensitive order
        std::map<std::string, std::vector<Entry>>         bySection;
        bool                                              scanned = false;
        std::string                                       print;      // file names + sizes + write times
        std::map<std::string, std::string>                display;    // lower-case section -> its own spelling
    };
    Index             g_idx;
    std::shared_mutex g_mx;

    std::string Lower(std::string s)
    {
        for (auto& c : s) c = static_cast<char>(std::tolower(static_cast<unsigned char>(c)));
        return s;
    }

    std::string Str(const nlohmann::json& o, const char* k)
    {
        const auto it = o.find(k);
        return it != o.end() && it->is_string() ? it->get<std::string>() : std::string{};
    }

    void AddTattoo(Index& idx, const nlohmann::json& t)
    {
        if (!t.is_object()) return;
        const auto name = Str(t, "name"), section = Str(t, "section"), area = Str(t, "area"), texture = Str(t, "texture");
        if (name.empty() || section.empty() || texture.empty()) return;
        if (area != "Body" && area != "Face" && area != "Hands" && area != "Feet") return;
        const auto dIt = t.find("domain");
        const std::string domain = dIt != t.end() && dIt->is_string() ? dIt->get<std::string>() : "default";
        if (domain != "default") return;
        auto& list = idx.bySection[Lower(section)];
        if (list.empty()) idx.display[Lower(section)] = section;
        for (const auto& e : list) if (e.name == name) return;   // union across areas, first area kept
        list.push_back({ name, area, texture });
    }

    int Scan()
    {
        Index idx;
        const std::filesystem::path dir("Data/Textures/Actors/Character/slavetats");
        std::error_code ec;
        int files = 0, bad = 0;
        if (std::filesystem::is_directory(dir, ec)) {
            for (const auto& de : std::filesystem::directory_iterator(dir, ec)) {
                if (!de.is_regular_file(ec)) continue;
                if (Lower(de.path().extension().string()) != ".json") continue;
                ++files;
                {
                    const auto sz = de.file_size(ec);
                    const auto wt = de.last_write_time(ec).time_since_epoch().count();
                    idx.print += Lower(de.path().filename().string()) + ":" + std::to_string(sz) + ":" + std::to_string(wt) + ";";
                }
                std::ifstream in(de.path(), std::ios::binary);
                const std::string text((std::istreambuf_iterator<char>(in)), std::istreambuf_iterator<char>());
                const auto j = nlohmann::json::parse(text, nullptr, false, true);
                if (j.is_discarded()) { ++bad; SKSE::log::warn("[SNBaka.ST] native scan: unreadable pack file {}", de.path().filename().string()); continue; }
                if (j.is_array()) { for (const auto& t : j) AddTattoo(idx, t); }
                else AddTattoo(idx, j);
            }
        }
        for (const auto& [low, list] : idx.bySection) idx.sections.push_back(idx.display[low]);
        std::sort(idx.sections.begin(), idx.sections.end(), [](const std::string& a, const std::string& b) { return Lower(a) < Lower(b); });
        idx.scanned = true;
        const int n = static_cast<int>(idx.sections.size());
        {
            std::unique_lock lk(g_mx);
            g_idx = std::move(idx);
        }
        SKSE::log::info("[SNBaka.ST] native scan: {} pack files ({} unreadable), {} sections.", files, bad, n);
        return n;
    }

    void EnsureScanned()
    {
        {
            std::shared_lock lk(g_mx);
            if (g_idx.scanned) return;
        }
        Scan();
    }

    bool HitsFemaleAnatomy(const std::string& t)
    {
        static const char* kWords[] = { "pussy", "vagina", "cunt", "clit", "labia", "breast", "boob", "nipple", "womb", "cervix", "milf", "titty" };
        for (const auto* w : kWords) if (t.find(w) != std::string::npos) return true;
        const auto idx = t.find("tit");   // "tit" hits except the "tither" class
        return idx != std::string::npos && t.substr((std::min)(idx + 3, t.size()), 3) != "her";
    }

    constexpr const char* kPrintFile = "Data/SKSE/Plugins/DeD_SlaveTatsPrint.txt";

    std::string ReadPrintFile()
    {
        std::ifstream in(kPrintFile, std::ios::binary);
        return std::string((std::istreambuf_iterator<char>(in)), std::istreambuf_iterator<char>());
    }

    // ---- natives ----
    // True when SlaveTats' own cache needs a rebuild: the pack files changed since DeD last asked SlaveTats to
    // rebuild (marker file next to SKSE plugins), or SlaveTats' saved cache file is missing.
    bool STCacheStale(RE::StaticFunctionTag*)
    {
        EnsureScanned();
        std::error_code ec;
        std::string print;
        {
            std::shared_lock lk(g_mx);
            print = g_idx.print;
        }
        const bool stale = print != ReadPrintFile() || !std::filesystem::exists("Data/slavetats_cache.json", ec);
        SKSE::log::info("[SNBaka.ST] cache check: {}", stale ? "pack files changed (or no saved cache) - rebuild" : "unchanged - SlaveTats' saved cache is current");
        return stale;
    }

    void STCacheBuilt(RE::StaticFunctionTag*)
    {
        std::string print;
        {
            std::shared_lock lk(g_mx);
            print = g_idx.print;
        }
        std::ofstream out(kPrintFile, std::ios::binary | std::ios::trunc);
        out << print;
    }

    std::int32_t STScan(RE::StaticFunctionTag*) { return Scan(); }

    std::vector<std::string> STSections(RE::StaticFunctionTag*)
    {
        EnsureScanned();
        std::shared_lock lk(g_mx);
        return g_idx.sections;
    }

    std::vector<std::string> STNames(RE::StaticFunctionTag*, RE::BSFixedString a_section)
    {
        EnsureScanned();
        std::vector<std::string> out;
        std::shared_lock lk(g_mx);
        const auto it = g_idx.bySection.find(Lower(a_section.c_str()));
        if (it != g_idx.bySection.end()) for (const auto& e : it->second) out.push_back(e.name);
        return out;
    }

    std::string STArea(RE::StaticFunctionTag*, RE::BSFixedString a_section, RE::BSFixedString a_name)
    {
        EnsureScanned();
        std::shared_lock lk(g_mx);
        const auto it = g_idx.bySection.find(Lower(a_section.c_str()));
        const auto nm = Lower(a_name.c_str());
        if (it != g_idx.bySection.end()) for (const auto& e : it->second) if (Lower(e.name) == nm) return e.area;
        return {};
    }

    bool STMaleMayWear(RE::StaticFunctionTag*, RE::BSFixedString a_section, RE::BSFixedString a_name)
    {
        const auto sec = Lower(a_section.c_str());
        if (sec.rfind("gay - ", 0) == 0 || sec == "femboy") return true;
        return !HitsFemaleAnatomy(sec + " " + Lower(a_name.c_str()));
    }

    std::string ToLowerAscii(RE::StaticFunctionTag*, RE::BSFixedString a_text) { return Lower(a_text.c_str()); }

    // ---- S326 (tattoo-overhaul 9, D-T9): the shared description store. One file across saves and new games,
    // Data/SKSE/Plugins/DeD/TattooDescriptions.json, keyed by lower-case "section|name":
    //   { "version": 1, "tattoos": { "<key>": { "section": .., "name": .., "custom": "..", "auto": ".." } } }
    // Resolution: custom > auto > "" (the caller falls back to the name). Edits from the panel are saved here directly
    // in C++ (never through Papyrus, which pools strings case-insensitively). ----
    constexpr const char* kDescFile = "Data/SKSE/Plugins/DeD/TattooDescriptions.json";
    nlohmann::json        g_desc;
    bool                  g_descLoaded = false;
    std::mutex            g_descMx;

    std::string Trim(std::string s)
    {
        const auto a = s.find_first_not_of(" \t\r\n");
        if (a == std::string::npos) return {};
        const auto b = s.find_last_not_of(" \t\r\n");
        return s.substr(a, b - a + 1);
    }
    std::string DescKey(const std::string& a_sec, const std::string& a_name) { return Lower(Trim(a_sec)) + "|" + Lower(Trim(a_name)); }

    void LoadDescUnsafe()
    {
        if (g_descLoaded) return;
        g_descLoaded = true;
        std::ifstream in(kDescFile, std::ios::binary);
        if (in) {
            const std::string text((std::istreambuf_iterator<char>(in)), std::istreambuf_iterator<char>());
            g_desc = nlohmann::json::parse(text, nullptr, false, true);
        }
        if (!g_desc.is_object()) g_desc = nlohmann::json::object();
        if (!g_desc.contains("tattoos") || !g_desc["tattoos"].is_object()) g_desc["tattoos"] = nlohmann::json::object();
        g_desc["version"] = 1;
        SKSE::log::info("[SNBaka.ST] descriptions: {} entr(ies) loaded from {}.", g_desc["tattoos"].size(), kDescFile);
    }

    bool SaveDescUnsafe()
    {
        std::error_code ec;
        std::filesystem::create_directories(std::filesystem::path(kDescFile).parent_path(), ec);
        std::ofstream out(kDescFile, std::ios::binary | std::ios::trunc);
        if (!out) { SKSE::log::error("[SNBaka.ST] descriptions: cannot write {}.", kDescFile); return false; }
        out << g_desc.dump(2);
        return true;
    }

    std::string GetDescription(const std::string& a_sec, const std::string& a_name)
    {
        std::lock_guard lk(g_descMx);
        LoadDescUnsafe();
        const auto& t = g_desc["tattoos"];
        const auto it = t.find(DescKey(a_sec, a_name));
        if (it == t.end() || !it->is_object()) return {};
        for (const char* f : { "custom", "auto" }) {
            const auto v = it->find(f);
            if (v != it->end() && v->is_string() && !Trim(v->get<std::string>()).empty()) return Trim(v->get<std::string>());
        }
        return {};
    }

    // field "custom" or "auto"; "" clears it. Section / name keep the pack's own spelling when the index knows them.
    bool SetDescriptionField(const std::string& a_sec, const std::string& a_name, const char* a_field, const std::string& a_text)
    {
        std::string sec = Trim(a_sec), nm = Trim(a_name);
        {
            std::shared_lock lk(g_mx);
            const auto d = g_idx.display.find(Lower(sec));
            if (d != g_idx.display.end()) sec = d->second;
            const auto s = g_idx.bySection.find(Lower(sec));
            if (s != g_idx.bySection.end()) for (const auto& e : s->second) if (Lower(e.name) == Lower(nm)) nm = e.name;
        }
        std::string text = Trim(a_text);
        for (auto& c : text) if (c == '\r' || c == '\n' || c == '\t') c = ' ';
        if (text.size() > 600) text.resize(600);
        std::lock_guard lk(g_descMx);
        LoadDescUnsafe();
        auto& entry = g_desc["tattoos"][DescKey(sec, nm)];
        if (!entry.is_object()) entry = nlohmann::json::object();
        entry["section"] = sec;
        entry["name"] = nm;
        if (text.empty()) entry.erase(a_field); else entry[a_field] = text;
        SKSE::log::info("[SNBaka.ST] description {} for '{}' ({}): {}", a_field, nm, sec, text.empty() ? "cleared" : text);
        return SaveDescUnsafe();
    }

    std::string STDescription(RE::StaticFunctionTag*, RE::BSFixedString a_section, RE::BSFixedString a_name)
    {
        return GetDescription(a_section.c_str(), a_name.c_str());
    }
    std::string STCustomDescription(RE::StaticFunctionTag*, RE::BSFixedString a_section, RE::BSFixedString a_name)
    {
        std::lock_guard lk(g_descMx);
        LoadDescUnsafe();
        const auto& t = g_desc["tattoos"];
        const auto it = t.find(DescKey(a_section.c_str(), a_name.c_str()));
        if (it == t.end() || !it->is_object()) return {};
        const auto v = it->find("custom");
        return v != it->end() && v->is_string() ? v->get<std::string>() : std::string{};
    }
    bool STSetDescription(RE::StaticFunctionTag*, RE::BSFixedString a_section, RE::BSFixedString a_name, RE::BSFixedString a_text)
    {
        return SetDescriptionField(a_section.c_str(), a_name.c_str(), "custom", a_text.c_str());
    }

    // S327 (step B, D-T8): a design still needs a description when it has no custom one and the player has not skipped it.
    bool STNeedsDescription(RE::StaticFunctionTag*, RE::BSFixedString a_section, RE::BSFixedString a_name)
    {
        std::lock_guard lk(g_descMx);
        LoadDescUnsafe();
        const auto& t = g_desc["tattoos"];
        const auto it = t.find(DescKey(a_section.c_str(), a_name.c_str()));
        if (it == t.end() || !it->is_object()) return true;
        const auto c = it->find("custom");
        if (c != it->end() && c->is_string() && !Trim(c->get<std::string>()).empty()) return false;
        const auto d = it->find("skipped");
        return !(d != it->end() && d->is_boolean() && d->get<bool>());
    }

    // The player skipped describing this design: never ask again (a later edit still works).
    bool STSkipDescription(RE::StaticFunctionTag*, RE::BSFixedString a_section, RE::BSFixedString a_name)
    {
        std::string sec = Trim(a_section.c_str()), nm = Trim(a_name.c_str());
        std::lock_guard lk(g_descMx);
        LoadDescUnsafe();
        auto& entry = g_desc["tattoos"][DescKey(sec, nm)];
        if (!entry.is_object()) entry = nlohmann::json::object();
        if (!entry.contains("section")) entry["section"] = sec;
        if (!entry.contains("name")) entry["name"] = nm;
        entry["skipped"] = true;
        SKSE::log::info("[SNBaka.ST] description request skipped for '{}' ({}).", nm, sec);
        return SaveDescUnsafe();
    }

    // ---- S329 (step D, D-T10): automatic descriptions. A design with no custom and no automatic description is queued
    // (natively, keyed case-exactly); Papyrus asks for the next one (STAutoDescribeNext: the context JSON for the
    // ded_tattoo_describe prompt, built from the pack entry and the texture measurements of TattooVision.cpp, cached in
    // the entry as "facts"), sends it to SkyrimNet, and hands the answer back (STAutoDescribeDone), which is saved as
    // "auto". One request in flight; a lost answer frees the slot after 90 s; a design that failed twice is not retried. ----
    std::deque<std::pair<std::string, std::string>> g_autoQ;
    bool                                            g_autoPending = false;
    std::pair<std::string, std::string>             g_autoKey;
    std::chrono::steady_clock::time_point           g_autoSent;

    bool NeedsAutoUnsafe(const std::string& a_sec, const std::string& a_name)
    {
        const auto& t = g_desc["tattoos"];
        const auto it = t.find(DescKey(a_sec, a_name));
        if (it == t.end() || !it->is_object()) return true;
        for (const char* f : { "custom", "auto" }) {
            const auto v = it->find(f);
            if (v != it->end() && v->is_string() && !Trim(v->get<std::string>()).empty()) return false;
        }
        const auto n = it->find("autoTries");
        return !(n != it->end() && n->is_number_integer() && n->get<int>() >= 2);
    }

    bool FindEntry(const std::string& a_sec, const std::string& a_name, std::string& a_secOut, Entry& a_out)
    {
        EnsureScanned();
        std::shared_lock lk(g_mx);
        const auto s = g_idx.bySection.find(Lower(Trim(a_sec)));
        if (s == g_idx.bySection.end()) return false;
        const auto d = g_idx.display.find(Lower(Trim(a_sec)));
        a_secOut = d != g_idx.display.end() ? d->second : Trim(a_sec);
        const auto nm = Lower(Trim(a_name));
        for (const auto& e : s->second) if (Lower(e.name) == nm) { a_out = e; return true; }
        return false;
    }

    bool STAutoDescribeQueue(RE::StaticFunctionTag*, RE::BSFixedString a_section, RE::BSFixedString a_name)
    {
        std::string sec;
        Entry e;
        if (!FindEntry(a_section.c_str(), a_name.c_str(), sec, e)) return false;
        std::lock_guard lk(g_descMx);
        LoadDescUnsafe();
        if (!NeedsAutoUnsafe(sec, e.name)) return false;
        const auto key = DescKey(sec, e.name);
        if (g_autoPending && DescKey(g_autoKey.first, g_autoKey.second) == key) return false;
        for (const auto& q : g_autoQ) if (DescKey(q.first, q.second) == key) return false;
        g_autoQ.push_back({ sec, e.name });
        SKSE::log::info("[SNBaka.ST] auto description queued: '{}' ({}), {} waiting.", e.name, sec, g_autoQ.size());
        return true;
    }

    std::string STAutoDescribeNext(RE::StaticFunctionTag*)
    {
        std::pair<std::string, std::string> next;
        {
            std::lock_guard lk(g_descMx);
            LoadDescUnsafe();
            const auto now = std::chrono::steady_clock::now();
            if (g_autoPending && now - g_autoSent < std::chrono::seconds(90)) return {};
            if (g_autoPending) SKSE::log::warn("[SNBaka.ST] auto description: no answer for '{}' in 90 s - slot freed.", g_autoKey.second);
            g_autoPending = false;
            while (!g_autoQ.empty() && !NeedsAutoUnsafe(g_autoQ.front().first, g_autoQ.front().second)) g_autoQ.pop_front();
            if (g_autoQ.empty()) return {};
            next = g_autoQ.front();
            g_autoQ.pop_front();
            g_autoPending = true;
            g_autoKey = next;
            g_autoSent = now;
        }
        std::string sec;
        Entry e;
        FindEntry(next.first, next.second, sec, e);
        std::string facts, why;
        {
            std::lock_guard lk(g_descMx);
            const auto& t = g_desc["tattoos"];
            const auto it = t.find(DescKey(next.first, next.second));
            if (it != t.end() && it->is_object()) {
                const auto f = it->find("facts");
                if (f != it->end() && f->is_string()) facts = f->get<std::string>();
            }
        }
        if (facts.empty() && !e.texture.empty()) {
            facts = TattooVisualFacts(e.texture, e.area, why);
            if (facts.empty()) facts = "no image measurements (" + why + ")";
            std::lock_guard lk(g_descMx);
            auto& entry = g_desc["tattoos"][DescKey(next.first, next.second)];
            if (!entry.is_object()) entry = nlohmann::json::object();
            if (!entry.contains("section")) entry["section"] = next.first;
            if (!entry.contains("name")) entry["name"] = next.second;
            entry["facts"] = facts;
            SaveDescUnsafe();
        }
        if (facts.empty()) facts = "no image measurements";
        const std::string kind = Lower(next.first).find("makeup") != std::string::npos ? "makeup" : "tattoo";
        SKSE::log::info("[SNBaka.ST] auto description asked for '{}' ({}): {}", next.second, next.first, facts);
        return nlohmann::json{ { "section", next.first }, { "name", next.second }, { "area", e.area.empty() ? "Body" : e.area },
            { "kind", kind }, { "facts", facts } }.dump();
    }

    bool STAutoDescribeDone(RE::StaticFunctionTag*, RE::BSFixedString a_response, std::int32_t a_success)
    {
        std::pair<std::string, std::string> key;
        {
            std::lock_guard lk(g_descMx);
            if (!g_autoPending) { SKSE::log::warn("[SNBaka.ST] auto description answer with no request in flight - ignored."); return false; }
            g_autoPending = false;
            key = g_autoKey;
        }
        std::string text = Trim(a_response.c_str());
        while (!text.empty() && (text.front() == '"' || text.front() == '\'')) text.erase(0, 1);
        while (!text.empty() && (text.back() == '"' || text.back() == '\'')) text.pop_back();
        text = Trim(text);
        const auto low = Lower(text);
        if (a_success == 1 && text.size() >= 8 && low.rfind("none", 0) != 0) {
            if (text.size() > 300) text.resize(300);
            return SetDescriptionField(key.first, key.second, "auto", text);
        }
        std::lock_guard lk(g_descMx);
        auto& entry = g_desc["tattoos"][DescKey(key.first, key.second)];
        if (!entry.is_object()) entry = nlohmann::json::object();
        if (!entry.contains("section")) entry["section"] = key.first;
        if (!entry.contains("name")) entry["name"] = key.second;
        const int tries = entry.contains("autoTries") && entry["autoTries"].is_number_integer() ? entry["autoTries"].get<int>() : 0;
        entry["autoTries"] = tries + 1;
        SKSE::log::warn("[SNBaka.ST] auto description failed for '{}' ({}), success={}, answer '{}' (try {}).", key.second, key.first, a_success, text, tries + 1);
        SaveDescUnsafe();
        return false;
    }

    // ---- S321: the panel's pack JSON built natively (REV-194 dogfood: Papyrus-built JSON came back with True /
    // False, Papyrus pools strings case-insensitively, and the settings answer took 3.5 s). ----
    bool InList(const std::vector<std::string>& a_list, const std::string& a_sec)
    {
        const auto low = Lower(a_sec);
        for (const auto& x : a_list) if (Lower(x) == low) return true;
        return false;
    }
    bool IsBakaPack(const std::string& a_sec)
    {
        const auto low = Lower(a_sec);
        return low == "skyrimnet spank" || low == "spank that ass";
    }
    std::string StyleOf(const std::string& a_sec, const std::vector<std::string>& a_mk, const std::vector<std::string>& a_tt)
    {
        if (InList(a_mk, a_sec)) return "makeup";
        if (InList(a_tt, a_sec)) return "tattoo";
        return Lower(a_sec).find("makeup") != std::string::npos ? "makeup" : "tattoo";
    }

    // Settings answer of the SlaveTats section (same keys the Papyrus setter reads).
    std::string STSettingsJson(RE::StaticFunctionTag*, std::vector<std::string> a_offForced, std::vector<std::string> a_offVol,
        std::vector<std::string> a_mk, std::vector<std::string> a_tt, bool a_observe, std::int32_t a_pct, bool a_narr,
        bool a_enabled, std::int32_t a_colorIndex, bool a_release, float a_ambFloor, bool a_askDesc, bool a_autoDesc)
    {
        using nlohmann::json;
        EnsureScanned();
        std::vector<std::string> secs;
        {
            std::shared_lock lk(g_mx);
            secs = g_idx.sections;
        }
        json forced = json::array(), vol = json::array(), style = json::array();
        int shown = 0;
        for (const auto& s : secs) {
            if (IsBakaPack(s)) continue;
            ++shown;
            forced.push_back({ { "key", "on.forced." + s }, { "type", "toggle" }, { "label", s }, { "value", !InList(a_offForced, s) } });
            vol.push_back({ { "key", "on.voluntary." + s }, { "type", "toggle" }, { "label", s }, { "value", !InList(a_offVol, s) } });
            style.push_back({ { "key", "style." + s }, { "type", "choice" }, { "label", s }, { "value", StyleOf(s, a_mk, a_tt) },
                { "options", json::array({ { { "value", "tattoo" }, { "label", "Tattoo" } }, { { "value", "makeup" }, { "label", "Makeup" } } }) } });
        }
        // S322 (dogfood): the short groups first; the three per-pack lists last and folded.
        // Phase 3 leg 2 (S324): the MCM SlaveTats page's remaining rows (same keys, ranges and texts as the MCM).
        static const char* kColors[] = { "Pack Default", "Black", "Red", "Crimson", "Dark Red", "Blue", "Green", "Purple", "Pink" };
        json colorOpts = json::array();
        for (int i = 0; i < 9; ++i) colorOpts.push_back({ { "value", std::to_string(i) }, { "label", kColors[i] } });
        json out{ { "module", "slavetats" }, { "section", "settings" }, { "settings", json::array({
            { { "group", "Module" }, { "settings", json::array({
                { { "key", "mod.enabled" }, { "type", "toggle" }, { "label", "Module Enabled" }, { "value", a_enabled },
                    { "desc", "Master switch for the SlaveTats degradation-set module. When off, no event applies any set. The spank-heat marks Baka itself applies are separate and unaffected." } },
                { { "key", "mod.color" }, { "type", "choice" }, { "label", "Default Mark Color" }, { "value", std::to_string(a_colorIndex < 0 ? 0 : a_colorIndex) }, { "options", colorOpts },
                    { "desc", "Module-wide default color for applied marks. Used when a path doesn't specify a color (LLM actions, event hooks without a per-channel color). The picker's per-pick colors override it. 'Pack Default' = no recolor." } },
                { { "key", "mod.release" }, { "type", "toggle" }, { "label", "Remove Marks On Release" }, { "value", a_release },
                    { "desc", "Strip the module's degradation marks when a captive is genuinely released (the Release action). Only marks THIS module applied - Baka's own spank heat marks are untouched. Default ON." } },
                { { "key", "mod.askdesc" }, { "type", "toggle" }, { "label", "Ask for Descriptions" }, { "value", a_askDesc },
                    { "desc", "When a tattoo or makeup design is applied for the first time and has no description of your own, ask for one: right away for marks you apply in this menu, queued in the Describe tab for marks applied any other way. Default OFF." } },
                { { "key", "mod.autodesc" }, { "type", "toggle" }, { "label", "Automatic Descriptions" }, { "value", a_autoDesc },
                    { "desc", "When a design without a description is applied or seen, look at its texture (where it sits, how big, its colours) and have SkyrimNet write a short description from that and its name, once per design. Your own descriptions always win. Default ON." } } }) } },
            { { "group", "Packs" }, { "settings", json::array({ { { "key", "scan.info" }, { "type", "text" }, { "label", "Packs found" },
                { "desc", "Rescanned on every game load and when this menu opens." }, { "value", std::to_string(shown) } } }) } },
            { { "group", "Exposure" }, { "settings", json::array({
                { { "key", "ambient.on" }, { "type", "toggle" }, { "label", "Ambient Observation Cues" }, { "value", a_observe },
                    { "desc", "Master gate for ambient tattoo reaction cues: while a Baka daemon mode is on, every daemon tick rolls a chance for nearby personas to notice any VISIBLE tattoo - covered marks are not reacted to, marks applied by any means are. Default ON." } },
                { { "key", "ambient.pct" }, { "type", "slider" }, { "label", "Ambient Exposure Chance" }, { "value", a_pct }, { "min", 0 }, { "max", 100 }, { "step", 5 }, { "unit", "%" },
                    { "desc", "Chance each daemon-tick ambient pass fires a visible-tattoo reaction cue when someone nearby has an exposed mark (default 35%). Failing rolls are silent." } },
                { { "key", "ambient.narr" }, { "type", "toggle" }, { "label", "Tattoo Ambient Narration" }, { "value", a_narr },
                    { "desc", "Additional direct narration for ambient tattoo reaction cues (a second prompt surface on top of the mandatory cue). Default OFF." } },
                { { "key", "ambient.floor" }, { "type", "slider" }, { "label", "Ambient Cue Interval" }, { "value", a_ambFloor }, { "min", 60 }, { "max", 1800 }, { "step", 30 }, { "unit", "s" } } }) } },
            { { "group", "Forced (downed) packs" }, { "collapsible", true }, { "collapsed", true }, { "settings", forced } },
            { { "group", "Voluntary packs" }, { "collapsible", true }, { "collapsed", true }, { "settings", vol } },
            { { "group", "Tattoo or makeup" }, { "collapsible", true }, { "collapsed", true }, { "settings", style } } }) } };
        return out.dump();
    }

    // The pack tiles of one tab (style) for one method: comma-joined item objects, "" when none.
    std::string STPackItemsJson(RE::StaticFunctionTag*, RE::BSFixedString a_style, std::vector<std::string> a_off,
        std::vector<std::string> a_mk, std::vector<std::string> a_tt)
    {
        EnsureScanned();
        std::vector<std::string> secs;
        {
            std::shared_lock lk(g_mx);
            secs = g_idx.sections;
        }
        const auto style = Lower(a_style.c_str());
        std::string out;
        for (const auto& s : secs) {
            if (IsBakaPack(s) || InList(a_off, s) || StyleOf(s, a_mk, a_tt) != style) continue;
            if (!out.empty()) out += ',';
            out += nlohmann::json{ { "id", "pack:" + s }, { "label", s }, { "stay", true } }.dump();
        }
        return out;
    }
}

// S326: the panel bridge saves edited descriptions directly (SlaveTatsPanel.cpp).
bool SlaveTatsSetCustomDescription(const std::string& a_section, const std::string& a_name, const std::string& a_text)
{
    return SetDescriptionField(a_section, a_name, "custom", a_text);
}

void PapyrusFunctions::RegisterSlaveTatsNatives(RE::BSScript::IVirtualMachine* vm)
{
    vm->RegisterFunction("STScan",        "SNBakaUI", STScan);
    vm->RegisterFunction("STSections",    "SNBakaUI", STSections);
    vm->RegisterFunction("STNames",       "SNBakaUI", STNames);
    vm->RegisterFunction("STArea",        "SNBakaUI", STArea);
    vm->RegisterFunction("STMaleMayWear", "SNBakaUI", STMaleMayWear);
    vm->RegisterFunction("ToLowerAscii",  "SNBakaUI", ToLowerAscii);
    vm->RegisterFunction("STCacheStale",  "SNBakaUI", STCacheStale);
    vm->RegisterFunction("STCacheBuilt",  "SNBakaUI", STCacheBuilt);
    vm->RegisterFunction("STSettingsJson",  "SNBakaUI", STSettingsJson);
    vm->RegisterFunction("STPackItemsJson", "SNBakaUI", STPackItemsJson);
    vm->RegisterFunction("STDescription",       "SNBakaUI", STDescription);
    vm->RegisterFunction("STCustomDescription", "SNBakaUI", STCustomDescription);
    vm->RegisterFunction("STSetDescription",    "SNBakaUI", STSetDescription);
    vm->RegisterFunction("STNeedsDescription",  "SNBakaUI", STNeedsDescription);
    vm->RegisterFunction("STSkipDescription",   "SNBakaUI", STSkipDescription);
    vm->RegisterFunction("STAutoDescribeQueue", "SNBakaUI", STAutoDescribeQueue);
    vm->RegisterFunction("STAutoDescribeNext",  "SNBakaUI", STAutoDescribeNext);
    vm->RegisterFunction("STAutoDescribeDone",  "SNBakaUI", STAutoDescribeDone);
}
