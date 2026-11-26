#include <RE/Skyrim.h>
#include <SKSE/SKSE.h>
#include "DeDPanelClient.h"
#include "DeDUI_API.h"   // DeDService UI host contract (dll-source-ded/include)
#include <atomic>
#include <filesystem>
#include <fstream>
#include <string>
#include <chrono>
#include <thread>
#include <vector>

#include <nlohmann/json.hpp>   // vendored header-only, external/nlohmann (MIT)

static const DeDUI::Api1* s_ui = nullptr;
static std::atomic<bool>  s_handlerSet{ false };
static std::atomic<bool>  s_open{ false };
static std::atomic<bool>  s_watchMovement{ false };
static thread_local bool  t_inUICallback = false;   // true while a DeDService handler runs (game thread)

// ---- Magelight Phase 2 leg 4: the GS Poses section of the combined DeD panel ----
// (docs/specs/magelight-phase2-spec.md 5.3 and 16). With DeDService's panel available, the pose grid opens as
// the panel's GS section; picks reuse the grid's strings ("GS<n>|desc|category", STOP_POSE, OVERDRIVE_TOGGLE,
// MUSE_TOGGLE, "" = cancel) on the same SNAnimGS_PoseSelected ModEvent, so the controller is untouched.
static const DeDUI::Api2* s_ui2 = nullptr;
static std::atomic<bool>  s_panelHandlerSet{ false };
static bool               s_session = false;     // a GS section is (or was) showing in this panel opening
static std::string        s_lastTab;             // last pose category shown
struct PoseCat { std::string id, name; std::vector<nlohmann::json> poses; };
static std::vector<PoseCat> s_cats;              // from the grid's own poses.js (one source of truth)
static bool               s_catsLoaded = false;
// Leg 5: Sheogorath / Sanguine as on/off switches. The state lives in Papyrus (StorageUtil GSAnim.Overdrive /
// GSAnim.Muse, global); read back through a static VM call, and flipped optimistically on a switch.
static std::atomic<bool>  s_overdrive{ false };
static std::atomic<bool>  s_muse{ false };
static bool               s_showing = false;       // the GS section is the one on screen
static std::uint32_t      s_showTarget = 0;
void GSPanelRepush();                              // below; re-sends the section while it shows

// This module's descriptor (Magelight/DeD/modules/gs-poses.json) and view.
static constexpr const char* kModuleId = "gs-poses";
static constexpr const char* kGridView = "grid";
// Named SKSE mod events the controller listens for (no form lookup needed).
static constexpr const char* kPoseModEvent = "SNAnimGS_PoseSelected";
static constexpr const char* kStopModEvent = "SNAnimGS_StopPose";

// Inside a DeDService handler we are already on the game thread, and SKSE AddTask from there can
// hang on Skyrim VR (Magelight threading contract) - run inline. Elsewhere keep the AddTask hop.
template <class F>
static void RunGameTask(F&& f) {
    if (t_inUICallback) f();
    else SKSE::GetTaskInterface()->AddTask(std::forward<F>(f));
}

static void SendNamedModEvent(const char* name, const std::string& strArg) {
    auto* source = SKSE::GetModCallbackEventSource();
    if (!source) return;
    SKSE::ModCallbackEvent ev{};
    ev.eventName = RE::BSFixedString(name);
    ev.strArg    = RE::BSFixedString(strArg.c_str());
    ev.numArg    = 0.0f;
    ev.sender    = nullptr;
    source->SendEvent(&ev);
}

// Game thread (DeDService delivers picks via Magelight PostGameTask).
static void OnUIPick(const char*, const char*, const char*, const char* payload, void*) {
    t_inUICallback = true;
    DeDPanelClient::OnJSChoice(payload ? payload : "");
    t_inUICallback = false;
}

// Game thread. The player left the grid without a pick (Escape / toggle key / refusal / load failure).
static void OnUIClosed(const char*, const char*, DeDUI::CloseReason reason, void*) {
    SKSE::log::info("[SNAnimGS][UI] grid closed without a pick (reason {}) - cancel.", static_cast<int>(reason));
    t_inUICallback = true;
    DeDPanelClient::CancelMenu();
    t_inUICallback = false;
}

// Lazy: DeDService builds its views at kDataLoaded, which may run after ours.
static bool EnsureUI() noexcept {
    if (!s_ui) s_ui = DeDUI::RequestApi1();
    if (!s_ui || !s_ui->IsAvailable()) return false;
    if (!s_handlerSet.load()) {
        if (!s_ui->SetHandler(kModuleId, &OnUIPick, &OnUIClosed, nullptr)) {
            SKSE::log::error("[SNAnimGS][UI] SetHandler refused - module '{}' not installed (descriptor missing?).", kModuleId);
            return false;
        }
        s_handlerSet = true;
        SKSE::log::info("[SNAnimGS][UI] DeDService UI ready - pick/close handlers registered.");
    }
    return true;
}

static RE::Actor* CrosshairActor() {
    auto* pick = RE::CrosshairPickData::GetSingleton();
    if (!pick) return nullptr;
    const std::size_t idx = REL::Module::IsVR() ? static_cast<std::size_t>(RE::VR_DEVICE::kHeadset) : 0;
    if (auto ref = pick->targetActor[idx].get()) { if (auto* a = skyrim_cast<RE::Actor*>(ref.get())) return a; }
    if (auto ref = pick->target[idx].get()) { if (auto* a = skyrim_cast<RE::Actor*>(ref.get())) return a; }
    return nullptr;
}

// The grid's poses.js ("window.GS_POSES = {...};", strict JSON inside) next to the old grid page.
static void LoadPoses() {
    if (s_catsLoaded) return;
    s_catsLoaded = true;
    wchar_t exe[MAX_PATH]{};
    ::GetModuleFileNameW(nullptr, exe, MAX_PATH);
    const auto path = std::filesystem::path(exe).parent_path() / L"Data" / L"Magelight" / L"DeD" / L"views" / L"gs-poses" / L"grid" / L"poses.js";
    try {
        std::ifstream in(path, std::ios::binary);
        const std::string t((std::istreambuf_iterator<char>(in)), std::istreambuf_iterator<char>());
        const auto at = t.find("GS_POSES");
        const auto a  = at == std::string::npos ? std::string::npos : t.find('{', at);
        const auto b  = t.rfind('}');
        if (a == std::string::npos || b == std::string::npos || b < a) throw std::runtime_error("no GS_POSES object");
        const auto j = nlohmann::json::parse(t.substr(a, b - a + 1));
        for (const auto& c : j.at("categories")) {
            PoseCat pc{ c.value("id", std::string{}), c.value("name", std::string{}), {} };
            for (const auto& p : c.value("poses", nlohmann::json::array())) pc.poses.push_back(p);
            if (!pc.id.empty()) s_cats.push_back(std::move(pc));
        }
        SKSE::log::info("[SNAnimGS][PANEL] poses loaded: {} categories from {}.", s_cats.size(), path.string());
    } catch (const std::exception& e) {
        SKSE::log::error("[SNAnimGS][PANEL] poses.js unreadable ({}): {}", path.string(), e.what());
    }
}

class IntReply final : public RE::BSScript::IStackCallbackFunctor {
public:
    explicit IntReply(std::atomic<bool>* a_flag) : flag(a_flag) {}
    void operator()(RE::BSScript::Variable a_result) override {
        const bool on = a_result.IsInt() && a_result.GetSInt() == 1;
        const bool was = flag->exchange(on);
        if (was != on) {
            SKSE::GetTaskInterface()->AddTask([]() { GSPanelRepush(); });
        }
    }
    void SetObject(const RE::BSTSmartPointer<RE::BSScript::Object>&) override {}
private:
    std::atomic<bool>* flag;
};

// Ask Papyrus for the two mode flags; a reply that changes a flag re-pushes the section.
static void ReadModes() {
    auto* vm = RE::BSScript::Internal::VirtualMachine::GetSingleton();
    if (!vm) return;
    const std::pair<const char*, std::atomic<bool>*> keys[] = { { "GSAnim.Overdrive", &s_overdrive }, { "GSAnim.Muse", &s_muse } };
    for (const auto& [key, flag] : keys) {
        auto* args = RE::MakeFunctionArguments(static_cast<RE::TESForm*>(nullptr), RE::BSFixedString(key), static_cast<std::int32_t>(0));
        RE::BSTSmartPointer<RE::BSScript::IStackCallbackFunctor> cb(new IntReply(flag));
        vm->DispatchStaticCall(RE::BSFixedString("StorageUtil"), RE::BSFixedString("GetIntValue"), args, cb);
        delete args;
    }
}

static std::string SectionJson(std::uint32_t targetFormID) {
    LoadPoses();
    using nlohmann::json;
    const PoseCat* cur = nullptr;
    for (const auto& c : s_cats) { if (c.id == s_lastTab) cur = &c; }
    if (!cur && !s_cats.empty()) { cur = &s_cats.front(); s_lastTab = cur->id; }
    json tabs = json::array(), items = json::array();
    for (const auto& c : s_cats) tabs.push_back({ { "id", c.id }, { "label", c.name }, { "count", c.poses.size() } });
    if (cur) {
        for (const auto& p : cur->poses) {
            const auto e = p.value("e", std::string{});
            const auto d = p.value("d", std::string{});
            items.push_back({ { "id", e }, { "label", d.empty() ? e : d }, { "number", p.value("n", 0) },
                { "pick", e + (d.empty() ? "" : "|" + d) + "|" + cur->id } });
        }
    }
    auto* tgt = targetFormID ? RE::TESForm::LookupByID<RE::Actor>(targetFormID) : nullptr;
    json header{ { "eyebrow", "Pose" }, { "name", tgt ? tgt->GetDisplayFullName() : "Yourself" } };
    json footer = json::array({
        { { "id", "STOP_POSE" }, { "kind", "button" }, { "label", "Stop Pose" } },
        { { "id", "OVERDRIVE_SWITCH" }, { "kind", "toggle" }, { "label", "Sheogorath Mode" }, { "on", s_overdrive.load() }, { "stay", true } },
        { { "id", "MUSE_SWITCH" }, { "kind", "toggle" }, { "label", "Sanguine Mode" }, { "on", s_muse.load() }, { "stay", true } } });
    json out{ { "module", kModuleId }, { "section", "main" }, { "tab", s_lastTab }, { "layout", "plates" },
        { "tabs", tabs }, { "items", items }, { "header", header }, { "footer", footer } };
    if (s_cats.empty()) out["notice"] = { { "title", "No poses" }, { "text", "poses.js could not be read" } };
    return out.dump();
}

// Ask the controller to capture the panel's target the way OpenSelector captures the crosshair.
static void CaptureTarget(std::uint32_t targetFormID) {
    auto* vm      = RE::BSScript::Internal::VirtualMachine::GetSingleton();
    auto* handler = RE::TESDataHandler::GetSingleton();
    auto* quest   = handler ? handler->LookupForm<RE::TESQuest>(0x000D61, "SkyrimNet_AnimationsGS.esp") : nullptr;
    if (!vm || !quest) { SKSE::log::error("[SNAnimGS][PANEL] capture: VM or controller quest unavailable."); return; }
    auto* policy = vm->GetObjectHandlePolicy();
    const RE::VMHandle handle = policy->GetHandleForObject(RE::FormType::Quest, quest);
    if (handle == policy->EmptyHandle()) { SKSE::log::error("[SNAnimGS][PANEL] capture: VM handle invalid."); return; }
    auto* tgt  = targetFormID ? RE::TESForm::LookupByID<RE::Actor>(targetFormID) : nullptr;
    auto* args = RE::MakeFunctionArguments(static_cast<RE::Actor*>(tgt));
    RE::BSTSmartPointer<RE::BSScript::IStackCallbackFunctor> cb;
    vm->DispatchMethodCall(handle, RE::BSFixedString("SkyrimNet_AnimationsGS"), RE::BSFixedString("PanelSession"), args, cb);
    delete args;
}

// Game thread (DeDService PanelFn).
static void OnPanel(const char*, const char* kind, const char* json, std::uint32_t targetFormID, void*) {
    const std::string k = kind ? kind : "";
    nlohmann::json msg = nlohmann::json::parse(json ? json : "{}", nullptr, false);
    if (msg.is_discarded()) msg = nlohmann::json::object();
    const auto data = msg.value("data", nlohmann::json::object());
    t_inUICallback = true;
    if (k == "req") {
        if (data.value("section", std::string{ "main" }) == "settings") {
            s_ui2->PanelPush(kModuleId, R"({"module":"gs-poses","section":"settings","settings":[]})");   // Phase 3 fills this
        } else {
            if (!s_session) {
                // Opened by DeDService's routing, not the GS power: capture the panel's target first.
                s_session = true;
                SKSE::log::info("[SNAnimGS][PANEL] GS section opened by the panel (target 0x{:08X}) - capturing.", targetFormID);
                CaptureTarget(targetFormID);
            }
            const auto tab = data.value("tab", std::string{});
            if (!tab.empty()) s_lastTab = tab;
            s_showing = true;
            s_showTarget = targetFormID;
            const auto j = SectionJson(targetFormID);
            s_ui2->PanelPush(kModuleId, j.c_str());
            ReadModes();   // the switches show Papyrus' real state (a change re-pushes)
        }
    } else if (k == "act") {
        const auto pick = data.value("pick", std::string{});
        if (pick == "OVERDRIVE_SWITCH" || pick == "MUSE_SWITCH") {
            // Stay-open switch: flip at once, tell the controller, then confirm from Papyrus a moment later.
            auto& flag = pick == "OVERDRIVE_SWITCH" ? s_overdrive : s_muse;
            flag = !flag.load();
            SKSE::log::info("[SNAnimGS][PANEL] switch '{}' -> {} (panel stays open).", pick, flag.load() ? "on" : "off");
            SendNamedModEvent(kPoseModEvent, pick);
            GSPanelRepush();
            std::thread([]() {
                std::this_thread::sleep_for(std::chrono::milliseconds(1500));
                SKSE::GetTaskInterface()->AddTask([]() { if (s_showing) ReadModes(); });
            }).detach();
            t_inUICallback = false;
            return;
        }
        SKSE::log::info("[SNAnimGS][PANEL] pick '{}'.", pick);
        s_showing = false;
        s_session = false;
        s_watchMovement = !pick.empty();
        SendNamedModEvent(kPoseModEvent, pick);
    } else if (k == "closed") {
        s_showing = false;
        if (s_session) {
            SKSE::log::info("[SNAnimGS][PANEL] panel closed without a pose - cancel (clears the capture).");
            s_session = false;
            SendNamedModEvent(kPoseModEvent, "");
        }
    }
    t_inUICallback = false;
}

// Re-send the GS section while it is on screen (switch flipped, or Papyrus' state differed). Game thread.
void GSPanelRepush() {
    if (!s_showing || !s_ui2) return;
    const auto j = SectionJson(s_showTarget);
    s_ui2->PanelPush(kModuleId, j.c_str());
}

static bool PanelReady() noexcept {
    if (!EnsureUI()) return false;
    if (!s_ui2) s_ui2 = DeDUI::RequestApi2();
    if (!s_ui2 || !s_ui2->PanelAvailable()) return false;
    if (!s_panelHandlerSet.load()) {
        if (!s_ui2->SetPanelHandler(kModuleId, &OnPanel, nullptr)) return false;
        s_panelHandlerSet = true;
        SKSE::log::info("[SNAnimGS][PANEL] combined panel available - the pose grid opens as the panel's GS section.");
    }
    return true;
}

// S320 fix (REV-193 dogfood): the GS handler used to be set only when the old pose power opened the grid; the
// panel can route to GS (rail, last place, GS-only installs) before that ever happens, so set it on every load.
void DeDPanelClient::PanelInit() noexcept {
    if (!PanelReady()) SKSE::log::warn("[SNAnimGS][PANEL] game loaded: the combined panel is not available - GS handler not set.");
}

void DeDPanelClient::RequestAPI() noexcept {
    s_ui = DeDUI::RequestApi1();
    SKSE::log::info("[SNAnimGS][UI] DeDService UI API {}.", s_ui ? "found" : "NOT found (DeDService.dll absent or older) - pose grid unavailable");
}

void DeDPanelClient::CreatePoseView() noexcept {
    SKSE::log::info("[SNAnimGS][UI] pose grid is hosted by DeDService ({}).", EnsureUI() ? "ready" : "not ready yet - resolved on first use");
}

bool DeDPanelClient::IsAvailable() noexcept { return EnsureUI(); }
bool DeDPanelClient::IsMenuOpen() noexcept  { return s_open.load(); }

void DeDPanelClient::OpenPoseGrid() noexcept {
    if (!EnsureUI()) {
        SKSE::log::error("[SNAnimGS] OpenPoseGrid: UI unavailable.");
        return;
    }
    if (PanelReady()) {
        // The GS power: the controller already captured the crosshair NPC (OpenSelector).
        s_session = true;
        s_watchMovement = false;
        auto* player = RE::PlayerCharacter::GetSingleton();
        auto* tgt = CrosshairActor();
        if (tgt == player) tgt = nullptr;
        if (!s_ui2->OpenPanelAt(kModuleId, s_lastTab.c_str(), "interact", player ? player->GetFormID() : 0, tgt ? tgt->GetFormID() : 0, true)) {
            SKSE::log::warn("[SNAnimGS][PANEL] the panel did not open (busy cursor?) - cancelling.");
            s_session = false;
            SendNamedModEvent(kPoseModEvent, "");
        }
        return;
    }
    s_open = true;
    s_watchMovement = false;   // browsing the grid, not posing yet
    // Pause while choosing.
    if (!s_ui->OpenView(kModuleId, kGridView, "window.gsanim_open()", DeDUI::kOpenFocus | DeDUI::kOpenPause)) {
        SKSE::log::warn("[SNAnimGS][UI] OpenPoseGrid: not opened (another mod holds the cursor?) - cancelling.");
        CancelMenu();
        return;
    }
    SKSE::log::info("[SNAnimGS] Pose grid opened.");
}

void DeDPanelClient::ClosePoseGrid() noexcept {
    if (!s_open.load()) return;
    s_open = false;
    if (s_ui) s_ui->CloseView(kModuleId, kGridView);
}

void DeDPanelClient::CancelMenu() noexcept {
    if (!s_open.load()) return;
    OnJSChoice("");  // cancel -> empty selection
}

void DeDPanelClient::OnJSChoice(const char* value) noexcept {
    // A pick with the grid already closed is a late duplicate (the page's Escape cancel racing a
    // host-side close that already cancelled): drop it rather than send a second pose event.
    if (!s_open.load()) {
        SKSE::log::info("[SNAnimGS][UI] late pick '{}' ignored - grid not open.", value ? value : "");
        return;
    }
    if (s_ui) s_ui->CloseView(kModuleId, kGridView);   // releases UI mode + hides; no close callback follows
    s_open = false;

    const std::string pose = value ? value : "";
    s_watchMovement = !pose.empty();   // a real pose was picked -> watch for movement to end it
    SKSE::log::info("[SNAnimGS] OnJSChoice: pose='{}'", pose);

    // Fire the named ModEvent on the main thread. The controller's
    // RegisterForModEvent("SNAnimGS_PoseSelected", "OnPoseSelected") receives it.
    RunGameTask([pose]() { SendNamedModEvent(kPoseModEvent, pose); });
}

bool DeDPanelClient::IsWatchingMovement() noexcept { return s_watchMovement.load(); }

void DeDPanelClient::StopPoseFromMovement() noexcept {
    if (!s_watchMovement.exchange(false)) return;   // fire once
    SKSE::log::info("[SNAnimGS] player moved -> stopping pose");
    SKSE::GetTaskInterface()->AddTask([]() { SendNamedModEvent(kStopModEvent, ""); });
}
