// Magelight Phase 2 leg 3 -- the Baka Interactions section of the combined DeD panel
// (docs/specs/magelight-phase2-spec.md sections 5.1 and 15). DeDService hosts the panel; this file
// builds Baka's section (tabs, actions, step flows) from the same tables and choice strings the Phase 1
// page used, and turns the panel's requests/actions/closes back into the existing OnJSChoice path, so
// every Papyrus dispatcher (_DispatchInteractActionWithActors, _DispatchDownedAction, ...) runs unchanged.
// Display text here is placeholder content (register before shipping). ASCII only.
#include "DeDPanelClient.h"
#include "DeDDowned_API.h"   // S344: DeD Downed state (dll-source-ded/include)

#include <algorithm>
#include <cstdlib>
#include <format>

namespace
{
    struct Act { int id; const char* label; bool qte; };

    // Old page BASE_ACTIONS (ids = Papyrus _DispatchInteractAction choices).
    constexpr Act kAffection[] = { {0,"Back Hug",false},{1,"Front Hug",false},{24,"Arm Hold",false},{2,"Kiss",false},{3,"Flirt",false},
        {16,"Caress Face",false},{17,"Tease Breasts",false},{18,"Tease Below",false},{12,"Ogle Body",false} };
    constexpr Act kForced[] = { {4,"Grab Hold",true},{5,"Struggle",true},{6,"Choke Behind",true},{7,"Womb Hit",false},{8,"Forced Kiss",false},
        {13,"Drunk Exploit",true},{14,"Drug Food",false} };
    constexpr Act kSexual[] = { {9,"Spank",false},{10,"Touch Chest",false},{11,"Examine",false},{19,"Suck Breasts",false},{20,"Suck Privates",false},
        {21,"Play Privates",false},{15,"Fondle",false},{22,"Investigate",false},{23,"Inspect",false} };
    // Old page DOWNED_ACTIONS (ids 0-11 = _DispatchDownedAction's own range; the other tabs ride +100).
    constexpr Act kDown[] = { {4,"Help Up",false},{12,"Talk",false},{3,"Stand Back",false},{1,"Investigate",false},{2,"Inspect",false},{0,"Choke Down",false},
        {6,"Tie Up",false},{7,"Untie",false},{10,"Strip",false},{11,"Allow to dress",false},{8,"Apply Tattoo",false},{13,"Force Makeup",false},{9,"Remove Tattoos",false},
        {5,"Execute",false} };
    // Old page MIDCOMBAT_ACTIONS.
    constexpr Act kGrapple[] = { {0,"Subdue",true},{1,"Choke Behind",true} };

    struct Opt { const char* v; const char* t; };
    struct Step { const char* label; const Opt* opts; int n; };
    constexpr Opt kRole[]  = { {"i_take_them","I take them"},{"they_take_me","They take me"},{"together","Together"} };
    constexpr Opt kInt[]   = { {"loving","Loving"},{"normal","Normal"},{"rough","Rough"},{"brutal","Brutal"} };
    constexpr Opt kFlav[]  = { {"none","(Nothing special)"},{"drugged","Drugged"},{"blackmail","Blackmail"},{"power","Abuse of power"},
        {"degrading","Degrading"},{"gagged","Gagged / silenced"},{"threatening","Threatening"} };
    constexpr Opt kType[]  = { {"vaginal","Vaginal"},{"anal","Anal"},{"oral","Oral"},{"painal","Painal"} };
    constexpr Step kEnc[]  = { {"Who takes whom?",kRole,3},{"How?",kInt,4},{"Circumstance",kFlav,7},{"Act",kType,4} };

    std::string Esc(std::string_view s)
    {
        std::string o;
        o.reserve(s.size() + 2);
        for (const char c : s) {
            switch (c) {
            case '"':  o += "\\\""; break;
            case '\\': o += "\\\\"; break;
            case '\n': o += "\\n"; break;
            case '\r': o += "\\r"; break;
            case '\t': o += "\\t"; break;
            default:
                if (static_cast<unsigned char>(c) < 0x20) o += std::format("\\u{:04x}", static_cast<int>(static_cast<unsigned char>(c)));
                else o += c;
            }
        }
        return o;
    }
    std::string Q(std::string_view s) { return "\"" + Esc(s) + "\""; }

    // First "key":"value" string in a flat-enough JSON text (our own and DeDService's messages only).
    std::string Field(const std::string& j, const char* key)
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

    std::string Name(RE::FormID id)
    {
        auto* a = id ? RE::TESForm::LookupByID<RE::Actor>(id) : nullptr;
        return a ? a->GetDisplayFullName() : std::string{};
    }

    template <std::size_t N>
    void Items(std::string& out, const Act (&list)[N], int offset, bool dimAll, bool slaveTats)
    {
        for (const auto& a : list) {
            if (offset == 0 && (a.id == 8 || a.id == 9 || a.id == 13) && &list[0] == &kDown[0] && !slaveTats) continue;   // tattoo / makeup tiles need SlaveTats (rule 16)
            // S344 (DeD Downed A4 leg 3): Talk needs the DeD Downed module (it lets one activation through to dialogue)
            const auto* dd = DeDDowned::RequestApi1();
            const bool ddActive = dd && dd->apiVersion >= DeDDowned::kApiVersion1 && dd->IsModuleActive && dd->IsModuleActive();
            if (&list[0] == &kDown[0] && a.id == 12 && !ddActive) continue;
            const int id = a.id + offset;
            if (out.back() != '[') out += ',';
            out += std::format("{{\"id\":\"{}\",\"label\":{}", id, Q(a.label));
            if (a.qte) out += ",\"badge\":\"QTE\"";
            if (dimAll) out += ",\"state\":\"dim\",\"reason\":\"no target\"";
            else if (&list[0] == &kDown[0] && a.id == 5) out += ",\"state\":\"danger\",\"badge\":\"confirm\"";
            // S344 (D-A46), S345 (D-A60): in a fight, Help Up needs a health potion
            else if (&list[0] == &kDown[0] && a.id == 4 && ddActive && dd->HelpUpHealing) {
                auto* pc = RE::PlayerCharacter::GetSingleton();
                if (pc && pc->IsInCombat() && dd->HelpUpHealing(0x14, false) == 0)
                    out += ",\"state\":\"dim\",\"reason\":\"needs a health potion (or heal them with a spell)\"";
            }
            out += '}';
        }
    }

    void Dispatch(const char* fn, RE::Actor* a1, RE::Actor* a2)
    {
        auto* vm      = RE::BSScript::Internal::VirtualMachine::GetSingleton();
        auto* handler = RE::TESDataHandler::GetSingleton();
        auto* quest   = handler ? handler->LookupForm<RE::TESQuest>(0x000D62, "SkyrimNet_BakaIntegration.esp") : nullptr;
        if (!vm || !quest) { SKSE::log::error("[SNBaka][PANEL] {}: VM or Baka quest unavailable.", fn); return; }
        auto* policy = vm->GetObjectHandlePolicy();
        const RE::VMHandle handle = policy->GetHandleForObject(RE::FormType::Quest, quest);
        if (handle == policy->EmptyHandle()) { SKSE::log::error("[SNBaka][PANEL] {}: VM handle invalid.", fn); return; }
        auto* args = RE::MakeFunctionArguments(static_cast<RE::Actor*>(a1), static_cast<RE::Actor*>(a2));
        RE::BSTSmartPointer<RE::BSScript::IStackCallbackFunctor> cb;
        vm->DispatchMethodCall(handle, RE::BSFixedString("SkyrimNet_BakaIntegration"), RE::BSFixedString(fn), args, cb);
        delete args;
    }
}

bool DeDPanelClient::PanelReady() noexcept
{
    if (!EnsureUI()) return false;
    if (!s_ui2) s_ui2 = DeDUI::RequestApi2();
    if (!s_ui2 || !s_ui2->PanelAvailable()) return false;
    if (!s_panelHandlerSet.load()) {
        if (!s_ui2->SetPanelHandler(kModuleId, &DeDPanelClient::OnPanel, nullptr)) return false;
        s_panelHandlerSet = true;
        SKSE::log::info("[SNBaka][PANEL] combined panel available - Baka menus open as the panel's Baka section.");
    }
    STPanelInit();   // leg 5: the SlaveTats section handler rides the same framework DLL
    return true;
}

std::string DeDPanelClient::SectionJson()
{
    const MenuMode mode = s_mode.load();
    const bool st = s_ui && s_ui->IsModuleInstalled("slavetats");
    std::string tabs, items = "[", header, footer, steps;
    const auto modeFooter = std::format(
        "[{{\"id\":\"900\",\"kind\":\"toggle\",\"label\":\"Mephala Mode\",\"on\":{},\"stay\":true}},"
        "{{\"id\":\"901\",\"kind\":\"toggle\",\"label\":\"Molag Bal Mode\",\"on\":{},\"stay\":true}}]",
        s_mephala ? "true" : "false", s_molagBal ? "true" : "false");
    const char* base = "{\"id\":\"affection\",\"label\":\"Affection\"},{\"id\":\"forced\",\"label\":\"Forced\"},{\"id\":\"sexual\",\"label\":\"Sexual\"}";

    if (mode == MenuMode::Downed) {
        if (s_tab.empty()) s_tab = "down";
        tabs   = std::string("[{\"id\":\"down\",\"label\":\"Down\"},") + base + "]";
        header = std::format("{{\"eyebrow\":\"Downed\",\"name\":{}}}", Q(Name(s_downedVictim)));
        if (s_tab == "down") Items(items, kDown, 0, false, st);
        else if (s_tab == "forced") Items(items, kForced, 100, false, st);
        else if (s_tab == "sexual") Items(items, kSexual, 100, false, st);
        else Items(items, kAffection, 100, false, st);
        footer = modeFooter;
    } else if (mode == MenuMode::MidCombat) {
        s_tab  = "grapple";
        tabs   = "[{\"id\":\"grapple\",\"label\":\"Grapple\"}]";
        header = std::format("{{\"eyebrow\":\"Grapple\",\"name\":{}}}", Q(Name(s_midCombatTarget)));
        Items(items, kGrapple, 0, false, st);
        footer = modeFooter;
    } else if (mode == MenuMode::SexSpank) {
        s_tab  = "spank";
        tabs   = "[{\"id\":\"spank\",\"label\":\"Spank\"}]";
        const char* q = s_sexPhase == 0 ? "Spank who?" : "Spanked by who?";
        header = std::format("{{\"eyebrow\":\"During sex\",\"name\":{},\"status\":\"the game keeps running\"}}", Q(q));
        steps  = s_sexPhase == 0 ? "[\"Spank who?\"]" : "[\"Spank who?\",\"Spanked by who?\"]";
        for (std::size_t i = 0; i < s_sexNames.size() && i < 3; ++i) {
            if (items.back() != '[') items += ',';
            items += std::format("{{\"id\":\"{}\",\"label\":{}}}", s_sexPhase == 0 ? i : 10 + i, Q(s_sexNames[i]));
        }
        if (s_sexPhase == 0 && s_sexPlayerInScene) items += std::string(items.back() == '[' ? "" : ",") + "{\"id\":\"who:you\",\"label\":\"You (receive)\",\"stay\":true}";
        if (s_sexPhase == 1) items += std::string(items.back() == '[' ? "" : ",") + "{\"id\":\"13\",\"label\":\"Yourself\"}";
    } else if (mode == MenuMode::Encounter) {
        s_tab = "encounter";
        const int step = std::clamp(s_encStep, 0, 3);
        header = std::format("{{\"eyebrow\":\"Encounter\",\"name\":{},\"status\":{}}}",
            Q(Name(s_encAggressor) + " > " + Name(s_encVictim)), Q(kEnc[step].label));
        steps = "[";
        for (int i = 0; i <= step; ++i) steps += std::string(i ? "," : "") + Q(kEnc[i].label);
        steps += "]";
        for (int i = 0; i < kEnc[step].n; ++i) {
            if (items.back() != '[') items += ',';
            items += std::format("{{\"id\":\"enc:{}\",\"label\":{},\"stay\":true}}", kEnc[step].opts[i].v, Q(kEnc[step].opts[i].t));
        }
    } else {   // Interact (target or no-target session)
        if (s_tab != "affection" && s_tab != "forced" && s_tab != "sexual") s_tab = "affection";
        tabs = std::string("[") + base + "]";
        const bool none = s_interactTarget == 0;
        header = none ? "{\"eyebrow\":\"Interact\",\"name\":\"No one in reach\",\"status\":\"look at someone to act on them\"}"
                      : std::format("{{\"eyebrow\":\"Interact\",\"name\":{}}}", Q(Name(s_interactTarget)));
        if (s_tab == "forced") Items(items, kForced, 0, none, st);
        else if (s_tab == "sexual") Items(items, kSexual, 0, none, st);
        else Items(items, kAffection, 0, none, st);
        footer = modeFooter;
    }
    items += ']';
    std::string out = std::format("{{\"module\":\"baka\",\"section\":\"main\",\"tab\":{},\"header\":{},\"items\":{}", Q(s_tab), header, items);
    if (!tabs.empty()) out += ",\"tabs\":" + tabs;
    if (!footer.empty()) out += ",\"footer\":" + footer;
    if (!steps.empty()) out += ",\"steps\":" + steps;
    return out + "}";
}

void DeDPanelClient::PushSection() noexcept
{
    if (!s_ui2 || s_mode.load() == MenuMode::None) return;
    const auto j = SectionJson();
    if (!s_ui2->PanelPush(kModuleId, j.c_str())) SKSE::log::warn("[SNBaka][PANEL] push refused.");
}

// Game thread (DeDService PanelFn).
void DeDPanelClient::OnPanel(const char*, const char* kind, const char* json, std::uint32_t targetFormID, void*)
{
    const std::string k = kind ? kind : "";
    const std::string j = json ? json : "";
    t_inUICallback = true;
    if (k == "req") {
        if (Field(j, "section") == "settings") {
            s_ui2->PanelPush(kModuleId, "{\"module\":\"baka\",\"section\":\"settings\",\"settings\":[]}");   // Phase 3 fills this
        } else {
            if (s_mode.load() == MenuMode::None) {
                // Opened by DeDService's default routing (an ordinary target or no target): an interact session.
                auto* player = RE::PlayerCharacter::GetSingleton();
                if (s_interactTarget != targetFormID || !s_interactCaster) s_interactCaster = player ? player->GetFormID() : 0;
                s_interactTarget = targetFormID;
                s_mode = MenuMode::Interact;
                SKSE::log::info("[SNBaka][PANEL] interact session from the panel (target 0x{:08X}).", targetFormID);
            }
            const auto tab = Field(j, "tab");
            if (!tab.empty()) s_tab = tab;
            PushSection();
        }
    } else if (k == "act") {
        const auto pick = Field(j, "pick");
        SKSE::log::info("[SNBaka][PANEL] act '{}' (mode {}).", pick, static_cast<int>(s_mode.load()));
        const MenuMode mode = s_mode.load();
        if (pick == "who:you" && mode == MenuMode::SexSpank) {
            s_sexPhase = 1; PushSection();
        } else if (pick == "__back") {
            if (mode == MenuMode::Encounter && s_encStep > 0) { --s_encStep; PushSection(); }
            else if (mode == MenuMode::SexSpank && s_sexPhase == 1) { s_sexPhase = 0; PushSection(); }
            else { s_ui2->ClosePanel(kModuleId); CancelMenu(); }
        } else if (pick.rfind("enc:", 0) == 0 && mode == MenuMode::Encounter) {
            s_encChoice[std::clamp(s_encStep, 0, 3)] = pick.substr(4);
            if (s_encStep < 3) { ++s_encStep; PushSection(); }
            else {
                const auto spec = s_encChoice[0] + ";" + s_encChoice[1] + ";" + s_encChoice[2] + ";" + s_encChoice[3];
                s_ui2->ClosePanel(kModuleId);
                OnJSChoice(spec.c_str());
            }
        } else if (!pick.empty()) {
            OnJSChoice(pick.c_str());   // "900"/"901" keep the panel open (stay); other picks were closed by DeDService
        }
    } else if (k == "closed") {
        if (s_mode.load() != MenuMode::None) {
            SKSE::log::info("[SNBaka][PANEL] panel closed without a Baka pick - cancel (mode {}).", static_cast<int>(s_mode.load()));
            CancelMenu();
        }
    } else if (k == "claim") {
        // The DeD power, routed to Baka: Baka's own Papyrus routing decides (scene spank, busy, creature,
        // downed, grapple, interact) exactly as the old DeD: Interact power did.
        const auto casterHex = Field(j, "caster");
        auto* caster = RE::TESForm::LookupByID<RE::Actor>(casterHex.empty() ? 0 : static_cast<RE::FormID>(std::strtoul(casterHex.c_str(), nullptr, 16)));
        if (!caster) caster = RE::PlayerCharacter::GetSingleton();
        auto* target = targetFormID ? RE::TESForm::LookupByID<RE::Actor>(targetFormID) : nullptr;
        SKSE::log::info("[SNBaka][PANEL] claim -> PowerPressed (target 0x{:08X}).", targetFormID);
        Dispatch("PowerPressed", caster, target);
    }
    t_inUICallback = false;
}
