#include "DeDPanelClient.h"

#include <algorithm>
#include <cstdlib>
#include <format>


// View names in this module's descriptor (Magelight/DeD/modules/baka.json). DeDService owns the views.
static constexpr const char* kMenuView = "menu";
static constexpr const char* kHudView  = "hud";
// The SlaveTats picker belongs to the SlaveTats module (ruleset rule 16): descriptor slavetats.json, view "picker".
// Baka drives it only when that module is installed (presence-gated cross-module feature).
static constexpr const char* kSTModule = "slavetats";
static constexpr const char* kSTView   = "picker";
static constexpr const char* kExecView = "execconfirm";
struct NoCollisionEntry { RE::FormID id; float radius; };
static std::vector<NoCollisionEntry> s_noCollisionActors;
static constexpr const char* kModEventName    = "SNBaka_MenuChoice";
static constexpr float       kSexScanRadius   = 300.0f;  // Skyrim units (~5 m)
static constexpr float       kInteractRadius  = 150.0f;  // fallback nearest-actor range when crosshair is empty (was 300 - grabbed distant NPCs)

// SexLab.esm raw FormID for SexLabAnimatingFaction (0x0400E50F → local 0xE50F).
// Used as a C++ fallback when the Papyrus IsInSexAnimation faction check races.
static constexpr RE::FormID  kSexLabAnimatingFactionID = 0xE50F;
static constexpr const char* kSexLabESM                = "SexLab.esm";

// Returns true if the player is currently in the SexLabAnimatingFaction.
static bool IsPlayerInSexAnimation() noexcept {
    auto* handler = RE::TESDataHandler::GetSingleton();
    auto* player  = RE::PlayerCharacter::GetSingleton();
    if (!handler || !player) return false;
    auto* faction = handler->LookupForm<RE::TESFaction>(kSexLabAnimatingFactionID, kSexLabESM);
    if (!faction) return false;
    return player->GetFactionRank(faction, true) >= 0;
}

// Returns the actor currently under the player's crosshair, or nullptr.
static RE::Actor* GetCrosshairActor() noexcept {
    auto* pick = RE::CrosshairPickData::GetSingleton();
    if (!pick) return nullptr;
    // VR fills a per-device target array  -  read the HEADSET slot. Flatscreen uses index 0.
    // (In VR, target[0] is empty, which is why the interact power "did nothing" there.)
    const std::size_t idx = REL::Module::IsVR()
        ? static_cast<std::size_t>(RE::VR_DEVICE::kHeadset) : 0;
    if (auto ref = pick->targetActor[idx].get()) {
        if (auto* a = skyrim_cast<RE::Actor*>(ref.get()))
            return a;
    }
    if (auto ref = pick->target[idx].get()) {
        if (auto* a = skyrim_cast<RE::Actor*>(ref.get()))
            return a;
    }
    return nullptr;
}

// Fallback when the crosshair is empty: nearest living non-player actor within radius.
// "Living" excludes truly-dead actors but NOT a bleeding-out/essential-down one -- Actor::IsDead()
// alone returns true for both (a long-standing Skyrim quirk: bleedout sets the same life-state family
// as true death), which was silently excluding a downed follower from this exact fallback -- precisely
// the moment the crosshair struggles most (a prone/ragdolled actor is hard to precisely target), and
// precisely the actor this mod most needs to reach (the whole point of the downed-menu feature).
static RE::Actor* FindNearestLivingActor(float radius) noexcept {
    auto* player = RE::PlayerCharacter::GetSingleton();
    auto* cell   = player ? player->GetParentCell() : nullptr;
    if (!player || !cell) return nullptr;
    const auto origin = player->GetPosition();
    RE::Actor* best   = nullptr;
    float      bestSq = radius * radius;
    cell->ForEachReferenceInRange(origin, radius,
        [&](RE::TESObjectREFR* refr) -> RE::BSContainer::ForEachResult {
            auto* a = skyrim_cast<RE::Actor*>(refr);
            if (!a || a->IsPlayerRef() || (a->IsDead() && !a->IsBleedingOut()))
                return RE::BSContainer::ForEachResult::kContinue;
            const auto  p  = a->GetPosition();
            const float dx = p.x - origin.x, dy = p.y - origin.y, dz = p.z - origin.z;
            const float sq = dx * dx + dy * dy + dz * dz;
            if (sq < bestSq) { bestSq = sq; best = a; }
            return RE::BSContainer::ForEachResult::kContinue;
        });
    return best;
}

// Plan A (player-teammate flag) is abandoned  -  see git history. It only ever disabled
// NPC<->player collision one-sidedly (via the third-party DisableFollowerCollision mod
// reading the teammate bit), never NPC<->NPC, and dragged the NPC into follower AI
// processing as a side effect. It was left as a pure no-op after that, meaning actual
// actor-vs-actor push-apart during paired animations was never fixed.
//
// Plan B (this one): shrink the actor's own Havok "character bumper" capsule directly --
// the hkpCapsuleShape (tagged with RE::MATERIAL_ID::kCharacterBumper) inside their character
// controller's collision shape tree that's responsible for pushing other actors away when
// they get close. This is the same primitive the (Papyrus-uncallable) mod
// VariadicCollisionDynamics uses (github.com/legendman89/VariadicCollisionDynamics, source
// read directly) -- only the shape-tree walk is reused here, not its convex-hull rebuild or
// per-race preset/pose system, since we only need a temporary full shrink for the duration
// of a paired animation, restored to the exact captured radius afterward. Works for the
// player too (VCD shrinks the player's own capsule on every sneak toggle) -- both
// participants of a pair get shrunk, unlike the old one-sided approach.

static RE::hkpShape* GetControllerRootShape(RE::bhkCharacterController* a_controller) noexcept {
    if (!a_controller) return nullptr;
    if (auto* proxy = skyrim_cast<RE::bhkCharProxyController*>(a_controller)) {
        auto* charProxy = proxy->GetCharacterProxy();
        if (!charProxy || !charProxy->shapePhantom) return nullptr;
        return const_cast<RE::hkpShape*>(charProxy->shapePhantom->collidable.shape);
    }
    if (auto* rigidCtrl = skyrim_cast<RE::bhkCharRigidBodyController*>(a_controller)) {
        auto* body = rigidCtrl->GetRigidBody();
        if (!body || !body->GetCollidable()) return nullptr;
        return const_cast<RE::hkpShape*>(body->GetCollidable()->GetShape());
    }
    return nullptr;
}

static bool IsBumperMaterial(const RE::hkpShape* a_shape, RE::hkpShapeKey a_key) noexcept {
    if (!a_shape || !a_shape->userData) return false;
    if (a_shape->userData->materialID == RE::MATERIAL_ID::kCharacterBumper) return true;
    if (a_key != RE::HK_INVALID_SHAPE_KEY) {
        return a_shape->userData->GetMaterialID(a_key) == RE::MATERIAL_ID::kCharacterBumper;
    }
    return false;
}

// Recursively walks list-shape / generic-container children looking for the capsule tagged
// as the character bumper. Mirrors VCD's own walk (races/rigs vary in shape-tree layout, so
// this stays defensive rather than assuming a fixed child index).
static RE::hkpCapsuleShape* FindBumperCapsule(RE::hkpShape* a_shape, RE::hkpShapeKey a_key = RE::HK_INVALID_SHAPE_KEY) noexcept {
    if (!a_shape) return nullptr;
    if (a_shape->type == RE::hkpShapeType::kCapsule && IsBumperMaterial(a_shape, a_key)) {
        return skyrim_cast<RE::hkpCapsuleShape*>(a_shape);
    }
    if (a_shape->type == RE::hkpShapeType::kList) {
        auto* list = skyrim_cast<RE::hkpListShape*>(a_shape);
        if (!list) return nullptr;
        for (auto& child : list->childInfo) {
            auto* childShape = const_cast<RE::hkpShape*>(child.shape);
            if (childShape && childShape->type == RE::hkpShapeType::kCapsule &&
                IsBumperMaterial(childShape, RE::HK_INVALID_SHAPE_KEY)) {
                return skyrim_cast<RE::hkpCapsuleShape*>(childShape);
            }
            if (auto* found = FindBumperCapsule(childShape)) return found;
        }
        return nullptr;
    }
    const auto* container = a_shape->GetContainer();
    if (!container) return nullptr;
    for (auto key = container->GetFirstKey(); key != RE::HK_INVALID_SHAPE_KEY; key = container->GetNextKey(key)) {
        RE::hkpShapeBuffer buffer{};
        auto* childShape = const_cast<RE::hkpShape*>(container->GetChildShape(key, buffer));
        if (childShape && childShape->type == RE::hkpShapeType::kCapsule && IsBumperMaterial(a_shape, key)) {
            return skyrim_cast<RE::hkpCapsuleShape*>(childShape);
        }
        if (auto* found = FindBumperCapsule(childShape, key)) return found;
    }
    return nullptr;
}

static RE::hkpCapsuleShape* ResolveBumperCapsule(RE::Actor* a_actor) noexcept {
    if (!a_actor) return nullptr;
    auto* controller = a_actor->GetCharController();
    if (!controller) return nullptr;
    return FindBumperCapsule(GetControllerRootShape(controller));
}

// Fraction of the vanilla bumper radius left in place while "disabled" -- thin enough that
// two paired actors' capsules stop overlapping/pushing, but non-zero (a literal 0 radius is
// a degenerate Havok capsule). 0.15 still let paired actors nudge each other slightly
// (confirmed request: "we should shrink it further").
static constexpr float kBumperShrinkFactor = 0.05f;

// Shrinks (disable=true) or restores (disable=false) one actor's bumper capsule. Always
// caches the exact pre-shrink radius under the actor's FormID and restores that exact value
// -- never a relative shrink-of-a-shrink -- so repeat disable calls from overlapping call
// sites (confirmed to happen: e.g. PlayPairedSequence and _SetupPair can both fire for the
// same pair) can't compound, and repeat enable calls can't over-restore.
static void SetActorNoCharCollision(RE::Actor* actor, bool disable, bool a_log = true) noexcept {
    if (!actor) return;
    const auto id = actor->GetFormID();
    auto it = std::find_if(s_noCollisionActors.begin(), s_noCollisionActors.end(),
        [id](const NoCollisionEntry& e) { return e.id == id; });

    auto* cell  = actor->GetParentCell();
    auto* world = cell ? cell->GetbhkWorld() : nullptr;

    if (disable) {
        if (it != s_noCollisionActors.end()) return;  // already shrunk, no-op
        auto* capsule = ResolveBumperCapsule(actor);
        if (!capsule || !world) {
            if (a_log) {
                SKSE::log::warn("SetActorCollision: bumper capsule unavailable for '{}'", actor->GetDisplayFullName());
            }
            return;
        }
        const float original = capsule->radius;
        {
            RE::BSWriteLockGuard lock(world->worldLock);
            capsule->radius = original * kBumperShrinkFactor;
        }
        s_noCollisionActors.push_back({ id, original });
        if (a_log) {
            SKSE::log::info("SetActorCollision: '{}' bumper radius {} -> {} (tracked={})",
                actor->GetDisplayFullName(), original, capsule->radius, s_noCollisionActors.size());
        }
    } else {
        if (it == s_noCollisionActors.end()) return;  // wasn't shrunk, nothing to restore
        auto* capsule = ResolveBumperCapsule(actor);
        if (capsule && world) {
            RE::BSWriteLockGuard lock(world->worldLock);
            capsule->radius = it->radius;
        }
        if (a_log) {
            SKSE::log::info("SetActorCollision: '{}' bumper radius restored (tracked={})",
                actor->GetDisplayFullName(), s_noCollisionActors.size() - 1);
        }
        s_noCollisionActors.erase(it);
    }
}

// Restore original bumper-capsule radius on all actors we previously shrank.
void DeDPanelClient::RestoreTrackedCollision() noexcept {
    // Snapshot first: SetActorNoCharCollision erases from s_noCollisionActors as it restores,
    // so iterating the live vector directly would skip every other entry.
    auto pending = s_noCollisionActors;
    for (auto& entry : pending) {
        auto* actor = RE::TESForm::LookupByID<RE::Actor>(entry.id);
        SetActorNoCharCollision(actor, false);
    }
    s_noCollisionActors.clear();
    SKSE::log::info("RestoreTrackedCollision: done.");
}

// Per-actor collision toggle, exposed to Papyrus. Called for both participants
// at animation start (disable) and from _CleanupPair (restore).
void DeDPanelClient::SetActorCollision(RE::Actor* actor, bool disable) noexcept {
    SetActorNoCharCollision(actor, disable);
}

bool DeDPanelClient::IsAlchemyOrEnchantingFurniture(RE::TESObjectREFR* furniture) noexcept {
    if (!furniture) return false;
    auto* base = furniture->GetBaseObject();
    auto* furn = base ? base->As<RE::TESFurniture>() : nullptr;
    if (!furn) return false;
    using BT = RE::TESFurniture::WorkBenchData::BenchType;
    switch (furn->workBenchData.benchType.get()) {
    case BT::kAlchemy:
    case BT::kAlchemyExperiment:
    case BT::kEnchanting:
    case BT::kEnchantingExperiment:
        return true;
    default:
        return false;
    }
}

// Inside a DeDService UI handler we are already on the game thread, and SKSE AddTask from there can
// hang on Skyrim VR (Magelight threading contract) - run inline. Elsewhere (Papyrus natives, the input
// sink) keep the original AddTask hop.
template <class F>
static void RunGameTask(F&& f) {
    if (DeDPanelClient::InUICallback()) f();
    else SKSE::GetTaskInterface()->AddTask(std::forward<F>(f));
}

void DeDPanelClient::RequestAPI() noexcept {
    s_ui = DeDUI::RequestApi1();
    SKSE::log::info("[SNBaka][UI] DeDService UI API {}.", s_ui ? "found" : "NOT found (DeDService.dll absent or older) - menus fall back to vanilla messageboxes");
}

// Lazy: DeDService builds its views at kDataLoaded, which may run after ours.
bool DeDPanelClient::EnsureUI() noexcept {
    if (!s_ui) s_ui = DeDUI::RequestApi1();
    if (!s_ui || !s_ui->IsAvailable()) return false;
    if (!s_handlerSet.load()) {
        if (!s_ui->SetHandler(kModuleId, &DeDPanelClient::OnUIPick, &DeDPanelClient::OnUIClosed, nullptr)) {
            SKSE::log::error("[SNBaka][UI] SetHandler refused - module '{}' not installed (descriptor missing?).", kModuleId);
            return false;
        }
        // Optional: the SlaveTats module's picker. Absent module = no handler, and ShowSlaveTatsMenu cancels.
        const bool st = s_ui->IsModuleInstalled(kSTModule)
            && s_ui->SetHandler(kSTModule, &DeDPanelClient::OnUIPick, &DeDPanelClient::OnUIClosed, nullptr);
        s_handlerSet = true;
        SKSE::log::info("[SNBaka][UI] DeDService UI ready - pick/close handlers registered (slavetats picker: {}).", st ? "yes" : "module not installed");
    }
    return true;
}

// Show + JS call + UI mode in one request. False = not opened: the caller treats it as a cancel.
bool DeDPanelClient::OpenBakaView(const char* view, const std::string& script, bool pause, const char* module) noexcept {
    const std::uint32_t flags = DeDUI::kOpenFocus | (pause ? DeDUI::kOpenPause : DeDUI::kOpenNone);
    if (EnsureUI() && s_ui->OpenView(module, view, script.c_str(), flags)) return true;
    SKSE::log::warn("[SNBaka][UI] OpenView {}.{} failed (UI unavailable, module not installed, or another mod holds the cursor) - cancelling.", module, view);
    CancelMenu();
    return false;
}

// Game thread (DeDService delivers picks via Magelight PostGameTask).
void DeDPanelClient::OnUIPick(const char*, const char* view, const char*, const char* payload, void*) {
    SKSE::log::info("[SNBaka][UI] pick from view '{}': '{}'", view ? view : "", payload ? payload : "");
    t_inUICallback = true;
    OnJSChoice(payload ? payload : "");
    t_inUICallback = false;
}

// Game thread. The player left the view (Escape / toggle key / refusal / load failure): cancel it.
void DeDPanelClient::OnUIClosed(const char*, const char* view, DeDUI::CloseReason reason, void*) {
    SKSE::log::info("[SNBaka][UI] view '{}' closed without a pick (reason {}) - cancel.", view ? view : "", static_cast<int>(reason));
    t_inUICallback = true;
    CancelMenu();
    t_inUICallback = false;
}

void DeDPanelClient::CreateMenuView() noexcept {
    SKSE::log::info("[SNBaka][UI] menu view is hosted by DeDService ({}).", EnsureUI() ? "ready" : "not ready yet - resolved on first use");
}

bool DeDPanelClient::IsAvailable() noexcept {
    return EnsureUI();
}

void DeDPanelClient::CreateHudView() noexcept {
    // The HUD view starts visible from its descriptor (startVisible); nothing to create here.
}

void DeDPanelClient::CreateSlaveTatsView() noexcept {
    // Hosted by DeDService (descriptor view "slavetats").
}

void DeDPanelClient::CreateExecuteConfirmView() noexcept {
    // Hosted by DeDService (descriptor view "execconfirm").
}

void DeDPanelClient::SetGetUpCharge(float pct) noexcept {
    if (!EnsureUI()) {
        SKSE::log::warn("SetGetUpCharge: UI unavailable, dropping call (pct={}).", pct);
        return;
    }
    // Logged once per charge (on the first tick and on hide), not every ~50ms tick in between --
    // that would spam the log without adding anything a single "did this fire at all" line doesn't.
    static bool s_wasCharging = false;
    const bool isCharging = pct >= 0.0f;
    if (isCharging != s_wasCharging) {
        SKSE::log::info("SetGetUpCharge: {} (pct={}).", isCharging ? "charge started" : "charge ended/hidden", pct);
        s_wasCharging = isCharging;
    }
    const auto script = std::format("window.snbakaSetGetUpCharge({})", pct);
    s_ui->InvokeView(kModuleId, kHudView, script.c_str());
}

// REV-147 Feature B: pushes the ambient mode-button ON/OFF highlight to the open
// SNBaka_Menu footer. Papyrus arbitrates the SNBaka.MephalaMode / SNBaka.MolagBalMode
// flags and calls this at panel open and after every toggle; the DLL relays to JS via
// the proven Invoke/payload pattern (the SetGetUpCharge shape, on the MENU view).
// Safe when the panel is closed - the view exists from plugin init.
void DeDPanelClient::SetModeStates(bool mephala, bool molagBal) noexcept {
    s_mephala = mephala;
    s_molagBal = molagBal;
    if (PanelReady()) {
        PushSection();
        return;
    }
    if (!EnsureUI()) {
        SKSE::log::warn("SetModeStates: UI unavailable, dropping call (mephala={} molagbal={}).", mephala, molagBal);
        return;
    }
    const auto script = std::format("window.snbakaSetModeStates({}, {})",
        mephala ? "true" : "false", molagBal ? "true" : "false");
    s_ui->InvokeView(kModuleId, kMenuView, script.c_str());
    SKSE::log::info("SetModeStates: pushed mephala={} molagbal={}.", mephala, molagBal);
}

bool DeDPanelClient::IsMenuOpen() noexcept {
    return s_mode.load() != MenuMode::None;
}

void DeDPanelClient::CancelMenu() noexcept {
    if (!IsMenuOpen()) return;
    // The encounter wizard's cancel signal is the string "cancel"; the other
    // menus use "-1".  Sending the wrong token to _StartSexLabScene would start
    // an unintended default scene instead of aborting.
    if (s_mode.load() == MenuMode::Encounter)
        OnJSChoice("cancel");
    else
        OnJSChoice("-1");
}

RE::Actor* DeDPanelClient::GetInteractTarget() noexcept {
    auto* player = RE::PlayerCharacter::GetSingleton();
    RE::Actor* t = GetCrosshairActor();          // precise: what you're looking at
    if (!t || t == player)
        t = FindNearestLivingActor(kInteractRadius); // fallback: nearest in range
    if (t == player) t = nullptr;
    SKSE::log::info("GetInteractTarget -> {} (0x{:08X})",
        t ? t->GetDisplayFullName() : "(none)", t ? t->GetFormID() : 0);
    return t;
}

void DeDPanelClient::ShowInteractMenu(RE::Actor* caster, RE::Actor* target) noexcept {
    if (!IsAvailable()) {
        SKSE::log::error("ShowInteractMenu: UI unavailable, aborting.");
        return;
    }

    auto* player = RE::PlayerCharacter::GetSingleton();
    if (!caster) caster = player;

    // Sex check FIRST  -  works regardless of crosshair/target, so it's reliable
    // even though the spell is self-delivered (akTarget == player).
    if (IsPlayerInSexAnimation()) {
        SKSE::log::info("ShowInteractMenu: in sex animation -> spank menu.");
        ShowSexSpankMenu("{\"names\":[],\"playerInScene\":true}");
        return;
    }

    // Self-delivered spell hands us the player as 'target'.  Resolve the real
    // interact target from the crosshair, with a nearest-actor fallback.
    if (!target || target == player) {
        RE::Actor* resolved = GetCrosshairActor();
        if (!resolved || resolved == player)
            resolved = FindNearestLivingActor(kInteractRadius);
        if (resolved && resolved != player) {
            target = resolved;
        } else {
            // REV-147 Feature A (user ruling: a power press with no target OPENS the
            // panel - all target-actions greyed + a "no target selected" overlay; the
            // two ambient-mode buttons stay LIVE). The REV-61 abort becomes the
            // null-target panel-open path: render the view with an empty name payload
            // (the only target-context field the JS reads is the targetName string of
            // snbaka_open_interact, already null-guarded `targetName || ''`). 0 FormID
            // = no-target session; every target-action pick from it is refused
            // Papyrus-side with the reason-coded sentinel (_DispatchInteractAction).
            target = nullptr;
        }
    }

    if (!caster) {
        SKSE::log::error("ShowInteractMenu: null caster after resolve.");
        return;
    }

    // Capture the actors now, by FormID, so the dispatch uses these exact actors
    // regardless of what happens to Papyrus _pending* while the menu is open.
    // REV-147: s_interactTarget == 0 marks the no-target session.
    s_interactCaster = caster->GetFormID();
    s_interactTarget = target ? target->GetFormID() : 0;
    SKSE::log::info("ShowInteractMenu: caster='{}' (0x{:08X})  target='{}' (0x{:08X})",
        caster->GetDisplayFullName(), s_interactCaster,
        target ? target->GetDisplayFullName() : "(no target)", s_interactTarget);

    if (PanelReady()) {
        // Phase 2: Baka already routed (downed / grapple / busy were handled in Papyrus); DeDService's default
        // routing places an ordinary target on the player's last place (D-P1). The interact session starts when
        // the panel asks for the Baka section (OnPanel "req").
        s_tab.clear();
        const auto flags = DeDUI::kPanelSkipClaims | DeDUI::kPanelTargetGiven;
        if (!s_ui2->OpenPanelEx(s_interactCaster, s_interactTarget, flags))
            SKSE::log::warn("[SNBaka][PANEL] interact: the panel did not open (busy cursor or refused).");
        return;
    }

    std::string safe = target ? target->GetDisplayFullName() : "";
    for (auto& c : safe) if (c == '\'') c = '\x60';
    s_mode = MenuMode::Interact;
    const auto script = std::format("window.snbaka_open_interact('{}')", safe);
    // Pause while choosing so the target NPC can't wander off / combat can't move
    // things during the few seconds of selection.  Cursor still works with the
    // focus menu registered (disableFocusMenu=false).
    OpenBakaView(kMenuView, script, /*pause=*/true);
}

void DeDPanelClient::ShowEncounterMenu(RE::Actor* aggressor, RE::Actor* victim) noexcept {
    if (!IsAvailable()) {
        SKSE::log::error("ShowEncounterMenu: UI unavailable.");
        return;
    }
    if (!aggressor || !victim) {
        SKSE::log::error("ShowEncounterMenu: null aggressor/victim.");
        return;
    }

    s_encAggressor = aggressor->GetFormID();
    s_encVictim    = victim->GetFormID();
    SKSE::log::info("ShowEncounterMenu: aggressor='{}' (0x{:08X}) victim='{}' (0x{:08X})",
        aggressor->GetDisplayFullName(), s_encAggressor,
        victim->GetDisplayFullName(), s_encVictim);

    // Build {"aggressor":"..","victim":".."} for the wizard header (display only).
    std::string agg = aggressor->GetDisplayFullName();
    std::string vic = victim->GetDisplayFullName();
    for (auto& c : agg) if (c == '\'') c = '\x60';
    for (auto& c : vic) if (c == '\'') c = '\x60';
    const auto json   = std::format("{{\"aggressor\":\"{}\",\"victim\":\"{}\"}}", agg, vic);
    const auto script = std::format("window.snbaka_open_encounter('{}')", json);

    s_mode = MenuMode::Encounter;
    if (PanelReady()) {
        s_encStep = 0;
        s_encChoice = {};
        s_tab = "encounter";
        if (!s_ui2->OpenPanelAt(kModuleId, "encounter", "encounter", s_encAggressor, s_encVictim, true)) {
            SKSE::log::warn("[SNBaka][PANEL] encounter: the panel did not open - cancelling.");
            CancelMenu();
        }
        return;
    }
    // Pause during the multi-step wizard (no active SexLab scene yet - StartSex
    // runs only after the picks), so nothing drifts during the 3-4 clicks.
    OpenBakaView(kMenuView, script, /*pause=*/true);
}

void DeDPanelClient::ShowDownedMenu(RE::Actor* caster, RE::Actor* victim) noexcept {
    if (!IsAvailable()) {
        SKSE::log::error("ShowDownedMenu: UI unavailable.");
        return;
    }
    if (!caster || !victim) {
        SKSE::log::error("ShowDownedMenu: null caster/victim.");
        return;
    }

    s_downedCaster = caster->GetFormID();
    s_downedVictim = victim->GetFormID();
    SKSE::log::info("ShowDownedMenu: caster='{}' (0x{:08X}) victim='{}' (0x{:08X})",
        caster->GetDisplayFullName(), s_downedCaster,
        victim->GetDisplayFullName(), s_downedVictim);

    std::string safe = victim->GetDisplayFullName();
    for (auto& c : safe) if (c == '\'') c = '\x60';
    const auto script = std::format("window.snbaka_open_downed('{}')", safe);

    s_mode = MenuMode::Downed;
    if (PanelReady()) {
        s_tab = "down";
        if (!s_ui2->OpenPanelAt(kModuleId, "down", "downed", s_downedCaster, s_downedVictim, true)) {
            SKSE::log::warn("[SNBaka][PANEL] downed: the panel did not open - cancelling.");
            CancelMenu();
        }
        return;
    }
    OpenBakaView(kMenuView, script, /*pause=*/true);
}

void DeDPanelClient::ShowMidCombatMenu(RE::Actor* caster, RE::Actor* target) noexcept {
    if (!IsAvailable()) {
        SKSE::log::error("ShowMidCombatMenu: UI unavailable.");
        return;
    }
    if (!caster || !target) {
        SKSE::log::error("ShowMidCombatMenu: null caster/target.");
        return;
    }

    s_midCombatCaster = caster->GetFormID();
    s_midCombatTarget = target->GetFormID();
    SKSE::log::info("ShowMidCombatMenu: caster='{}' (0x{:08X}) target='{}' (0x{:08X})",
        caster->GetDisplayFullName(), s_midCombatCaster,
        target->GetDisplayFullName(), s_midCombatTarget);

    std::string safe = target->GetDisplayFullName();
    for (auto& c : safe) if (c == '\'') c = '\x60';
    const auto script = std::format("window.snbaka_open_midcombat('{}')", safe);

    s_mode = MenuMode::MidCombat;
    if (PanelReady()) {
        s_tab = "grapple";
        if (!s_ui2->OpenPanelAt(kModuleId, "grapple", "grapple", s_midCombatCaster, s_midCombatTarget, true)) {
            SKSE::log::warn("[SNBaka][PANEL] grapple: the panel did not open - cancelling.");
            CancelMenu();
        }
        return;
    }
    OpenBakaView(kMenuView, script, /*pause=*/true);
}

// REV-72: SlaveTats degradation-set picker. Dedicated view (SNSlaveTats_Menu/index.html); the
// pick comes back on the same "snbaka_chose" JS listener, with a "slot;section;name" spec
// (or "cancel") which OnJSChoice parses and dispatches to _ST_MenuChoice.
void DeDPanelClient::ShowSlaveTatsMenu(const std::string& json) noexcept {
    if (!IsAvailable()) {
        SKSE::log::error("ShowSlaveTatsMenu: UI unavailable.");
        return;
    }

    // Leg 5: the actor-bound picker opens the combined panel's SlaveTats section when the panel is there.
    if (OpenSTPanelPicker(json)) return;
    s_mode = MenuMode::SlaveTats;
    // Escape single-quotes in section/name keys before embedding into the JS call.
    std::string effective = json;
    for (auto& c : effective) if (c == '\'') c = '\x60';
    const auto script = std::format("window.snbaka_open_slavetats('{}')", effective);
    // Pause while picking (like the encounter wizard): the choice changes set
    // state that later events read, and nothing in-world needs to run meanwhile.
    OpenBakaView(kSTView, script, /*pause=*/true, kSTModule);
}

// REV-92: Execute-gate accept/decline popup. Same shape as ShowSlaveTatsView, but the
// payload carries BOTH actor names (initiator + target) and a 20s JS auto-close (the
// player who walked away gets a deterministic decline rather than a stuck paused menu;
// Papyrus still owns the authoritative 30s timeout + moot polling). Accept = "0",
// decline/cancel/timeout = "-1"  -  both ride the normal-path SendEvent as
// strArg="execconfirm" and land in OnSNBakaMenuChoice.
void DeDPanelClient::ShowExecuteConfirm(RE::Actor* initiator, RE::Actor* target) noexcept {
    if (!IsAvailable()) {
        SKSE::log::error("ShowExecuteConfirm: UI unavailable.");
        return;
    }
    if (!initiator || !target) {
        SKSE::log::error("ShowExecuteConfirm: null initiator/target.");
        return;
    }
    SKSE::log::info("ShowExecuteConfirm: initiator='{}' target='{}'",
        initiator->GetDisplayFullName(), target->GetDisplayFullName());

    std::string ini = initiator->GetDisplayFullName();
    std::string tgt = target->GetDisplayFullName();
    for (auto& c : ini) if (c == '\'') c = '\x60';
    for (auto& c : tgt) if (c == '\'') c = '\x60';
    s_mode = MenuMode::ExecuteConfirm;
    const auto script = std::format("window.snbaka_open_execconfirm('{}','{}')", ini, tgt);
    // A killing blow must not land mid-menu  -  pause while the player decides.
    OpenBakaView(kExecView, script, /*pause=*/true);
}

void DeDPanelClient::ShowSexSpankMenu(const std::string& json) noexcept {
    if (!IsAvailable()) {
        SKSE::log::error("ShowSexSpankMenu: UI unavailable.");
        return;
    }

    SKSE::log::info("ShowSexSpankMenu: papyrus json='{}'", json);

    // Reset C++ actor state for this menu open.
    s_usingCppSexActors = false;
    s_sexActorCount     = 0;
    s_sexActorIds.fill(0);

    // Detect whether Papyrus found any NPCs: names array is non-empty if it
    // contains at least one quoted name, i.e. `"names":["`.
    const bool papyrusHasActors = json.find("\"names\":[\"") != std::string::npos;
    SKSE::log::info("ShowSexSpankMenu: papyrusHasActors={}", papyrusHasActors);

    std::string effectiveJson = json;

    if (!papyrusHasActors) {
        // Papyrus-side detection (faction-based) found no actors.  Fall back to
        // a proximity scan  -  during a sex animation participants are always within
        // a few metres of the player.
        SKSE::log::info("ShowSexSpankMenu: no Papyrus actors  -  proximity scan (r={})", kSexScanRadius);

        auto* player = RE::PlayerCharacter::GetSingleton();
        auto* cell   = player ? player->GetParentCell() : nullptr;

        if (player && cell) {
            const auto origin = player->GetPosition();
            cell->ForEachReferenceInRange(origin, kSexScanRadius,
                [&](RE::TESObjectREFR* refr) -> RE::BSContainer::ForEachResult {
                    if (s_sexActorCount >= 3)
                        return RE::BSContainer::ForEachResult::kStop;
                    auto* actor = skyrim_cast<RE::Actor*>(refr);
                    if (!actor || actor->IsPlayerRef() || actor->IsDead())
                        return RE::BSContainer::ForEachResult::kContinue;
                    s_sexActorIds[s_sexActorCount] = actor->GetFormID();
                    SKSE::log::info("  scanned[{}] = '{}' (0x{:08X})",
                        s_sexActorCount,
                        actor->GetDisplayFullName(),
                        actor->GetFormID());
                    ++s_sexActorCount;
                    return RE::BSContainer::ForEachResult::kContinue;
                });
        }

        if (s_sexActorCount > 0) {
            s_usingCppSexActors = true;

            // Rebuild JSON from scanned actors.
            const bool playerInScene = json.find("\"playerInScene\":true") != std::string::npos;
            std::string names;
            for (std::uint8_t i = 0; i < s_sexActorCount; ++i) {
                auto* a = RE::TESForm::LookupByID<RE::Actor>(s_sexActorIds[i]);
                if (i > 0) names += ",";
                names += "\"";
                names += a ? a->GetDisplayFullName() : "???";
                names += "\"";
            }
            effectiveJson = std::format(
                "{{\"names\":[{}],\"playerInScene\":{}}}",
                names, playerInScene ? "true" : "false");
            SKSE::log::info("ShowSexSpankMenu: rebuilt json='{}'", effectiveJson);
        } else {
            SKSE::log::warn("ShowSexSpankMenu: no actors within {}u  -  menu will be empty", kSexScanRadius);
        }
    }

    s_mode = MenuMode::SexSpank;
    if (PanelReady()) {
        // names from the same json the old page read: {"names":["A","B"],"playerInScene":true}
        s_sexNames.clear();
        const auto at = effectiveJson.find("\"names\":[");
        if (at != std::string::npos) {
            std::size_t i = at + 9;
            while (i < effectiveJson.size() && effectiveJson[i] != ']') {
                if (effectiveJson[i] == '"') {
                    std::string n;
                    for (++i; i < effectiveJson.size() && effectiveJson[i] != '"'; ++i) {
                        if (effectiveJson[i] == '\\' && i + 1 < effectiveJson.size()) ++i;
                        n += effectiveJson[i];
                    }
                    s_sexNames.push_back(n);
                }
                ++i;
            }
        }
        s_sexPlayerInScene = effectiveJson.find("\"playerInScene\":true") != std::string::npos;
        s_sexPhase = 0;
        s_tab = "spank";
        auto* player = RE::PlayerCharacter::GetSingleton();
        if (!s_ui2->OpenPanelAt(kModuleId, "spank", "spank", player ? player->GetFormID() : 0, 0, false)) {
            SKSE::log::warn("[SNBaka][PANEL] spank: the panel did not open - cancelling.");
            CancelMenu();
        }
        return;
    }
    // Escape single-quotes in NPC names before embedding into the JS call.
    for (auto& c : effectiveJson) if (c == '\'') c = '\x60';
    const auto script = std::format("window.snbaka_open_sexspank('{}')", effectiveJson);
    OpenBakaView(kMenuView, script, /*pause=*/false);
}

void DeDPanelClient::OnJSChoice(const char* value) noexcept {

    SKSE::log::info("OnJSChoice: value='{}'", value ? value : "(null)");

    // REV-147 Feature B: reserved footer mode-button ids ("900"/"901") KEEP THE
    // PANEL OPEN - no mode exchange, no Unfocus/Hide (the REV-146a JS design intent:
    // "both modes can be toggled in one visit"; until now the bridge still closed the
    // view on every pick, so a toggle also dismissed the panel). The toggle is
    // dispatched to Papyrus _MenuModeButton, which arbitrates and pushes the new
    // button states back via SetModeStates. Cuts across every panel mode (the footer
    // is panel-wide), so it precedes the per-mode dispatch below.
    if (value && value[0] == '9' && value[1] == '0'
        && (value[2] == '0' || value[2] == '1') && value[3] == '\0') {
        const int which = (value[2] == '0') ? 900 : 901;
        SKSE::log::info("OnJSChoice: mode button {} - panel stays open (REV-147).", which);
        RunGameTask([which]() {
            auto* vm      = RE::BSScript::Internal::VirtualMachine::GetSingleton();
            auto* handler = RE::TESDataHandler::GetSingleton();
            if (!vm || !handler) {
                SKSE::log::error("Task: VM or DataHandler unavailable (mode button).");
                return;
            }
            auto* quest = handler->LookupForm<RE::TESQuest>(0x000D62, "SkyrimNet_BakaIntegration.esp");
            if (!quest) {
                SKSE::log::error("Task: BakaIntegration quest not found (mode button).");
                return;
            }
            auto* policy = vm->GetObjectHandlePolicy();
            RE::VMHandle handle = policy->GetHandleForObject(RE::FormType::Quest, quest);
            if (handle == policy->EmptyHandle()) {
                SKSE::log::error("Task: VMHandle invalid (mode button).");
                return;
            }
            auto* args = RE::MakeFunctionArguments(std::int32_t{which});
            RE::BSTSmartPointer<RE::BSScript::IStackCallbackFunctor> cb;
            vm->DispatchMethodCall(handle,
                RE::BSFixedString("SkyrimNet_BakaIntegration"),
                RE::BSFixedString("_MenuModeButton"),
                args, cb);
            delete args;
            SKSE::log::info("Task: _MenuModeButton dispatched ({}).", which);
        });
        return;
    }

    // Read the mode FIRST so we unfocus the view this pick actually came from
    // (REV-72: the SlaveTats picker lives on its own s_stView, not s_view;
    //  REV-92: the Execute-confirm popup likewise lives on s_execView).
    const MenuMode mode = s_mode.exchange(MenuMode::None);
    // A pick with no menu open is a late duplicate (e.g. the page's own Escape cancel racing a
    // host-side close that already cancelled). Dispatching it would run choice atoi(value) as a
    // fresh "interact" action, so drop it.
    if (mode == MenuMode::None) {
        SKSE::log::info("[SNBaka][UI] late pick '{}' ignored - no menu open.", value ? value : "");
        return;
    }
    const char* view = (mode == MenuMode::SlaveTats)      ? kSTView
                     : (mode == MenuMode::ExecuteConfirm) ? kExecView
                     : kMenuView;
    const char* module = (mode == MenuMode::SlaveTats) ? kSTModule : kModuleId;
    if (s_ui) s_ui->CloseView(module, view);   // releases UI mode + hides; no close callback follows
    const int      choice    = value ? std::atoi(value) : -1;
    const float    numArg    = static_cast<float>(choice);
    const char*    strArg    = (mode == MenuMode::SexSpank)       ? "sexspank"  :
                                (mode == MenuMode::Downed)        ? "downed"    :
                                (mode == MenuMode::MidCombat)     ? "midcombat" :
                                (mode == MenuMode::SlaveTats)     ? "slavetats" :
                                (mode == MenuMode::ExecuteConfirm) ? "execconfirm" : "interact";

    // Snapshot C++ actor state so the lambda doesn't race with a future ShowSexSpankMenu.
    const bool                      useCpp  = s_usingCppSexActors;
    const std::array<RE::FormID, 3> actIds  = s_sexActorIds;
    const std::uint8_t              actCnt  = s_sexActorCount;
    const RE::FormID                iCaster = s_interactCaster;
    const RE::FormID                iTarget = s_interactTarget;
    const RE::FormID                eAgg    = s_encAggressor;
    const RE::FormID                eVic    = s_encVictim;
    const RE::FormID                dCaster = s_downedCaster;
    const RE::FormID                dVictim = s_downedVictim;
    const RE::FormID                mCaster = s_midCombatCaster;
    const RE::FormID                mTarget = s_midCombatTarget;
    const std::string               spec    = value ? value : "";   // encounter: "role;intensity;flavor;type" or "cancel"

    SKSE::log::info("OnJSChoice: mode={} choice={} useCpp={} spec='{}'",
        strArg, choice, useCpp, spec);

    RunGameTask([numArg, strArg, mode, choice, useCpp, actIds, actCnt, iCaster, iTarget, eAgg, eVic, dCaster, dVictim, mCaster, mTarget, spec]() {
        auto* vm      = RE::BSScript::Internal::VirtualMachine::GetSingleton();
        auto* handler = RE::TESDataHandler::GetSingleton();
        if (!vm || !handler) {
            SKSE::log::error("Task: VM or DataHandler unavailable.");
            return;
        }

        auto* quest = handler->LookupForm<RE::TESQuest>(0x000D62, "SkyrimNet_BakaIntegration.esp");
        if (!quest) {
            SKSE::log::error("Task: BakaIntegration quest not found.");
            return;
        }

        auto* policy = vm->GetObjectHandlePolicy();
        RE::VMHandle handle = policy->GetHandleForObject(RE::FormType::Quest, quest);
        if (handle == policy->EmptyHandle()) {
            SKSE::log::error("Task: VMHandle invalid.");
            return;
        }

        // Collision is now disabled per-pair from Papyrus (SetNoCollision) inside
        // the paired-animation functions, so it covers NPC-NPC too and restores
        // cleanly in _CleanupPair.

        // ── Encounter: split spec "role;intensity;flavor;type" → 4 strings ──────
        if (mode == MenuMode::Encounter) {
            auto* agg = RE::TESForm::LookupByID<RE::Actor>(eAgg);
            auto* vic = RE::TESForm::LookupByID<RE::Actor>(eVic);
            SKSE::log::info("Task: encounter spec='{}' aggressor='{}' victim='{}'",
                spec,
                agg ? agg->GetDisplayFullName() : "(null)",
                vic ? vic->GetDisplayFullName() : "(null)");
            if (!agg || !vic) {
                SKSE::log::error("Task: encounter  -  actor lookup failed.");
                return;
            }
            // Default role "cancel" so an empty/short spec is treated as a cancel.
            std::string parts[4] = { "cancel", "", "", "" };
            {
                std::size_t start = 0;
                int idx = 0;
                while (idx < 4) {
                    const std::size_t sep = spec.find(';', start);
                    parts[idx++] = (sep == std::string::npos) ? spec.substr(start)
                                                              : spec.substr(start, sep - start);
                    if (sep == std::string::npos) break;
                    start = sep + 1;
                }
            }
            auto* args = RE::MakeFunctionArguments(
                RE::BSFixedString(parts[0].c_str()),
                RE::BSFixedString(parts[1].c_str()),
                RE::BSFixedString(parts[2].c_str()),
                RE::BSFixedString(parts[3].c_str()),
                static_cast<RE::Actor*>(agg),
                static_cast<RE::Actor*>(vic));
            RE::BSTSmartPointer<RE::BSScript::IStackCallbackFunctor> cb;
            vm->DispatchMethodCall(handle,
                RE::BSFixedString("SkyrimNet_BakaIntegration"),
                RE::BSFixedString("_StartSexLabScene"),
                args, cb);
            delete args;
            SKSE::log::info("Task: _StartSexLabScene dispatched (role='{}').", parts[0]);
            return;
        }

        // ── Interact: dispatch with the actors captured at menu-open ────────────
        // Bypasses Papyrus _pendingTarget/_pendingCaster entirely so the open
        // (unpaused) menu can't leave us with stale/clobbered actors.
        if (mode == MenuMode::Interact) {
            if (choice < 0) {
                SKSE::log::info("Task: interact cancelled.");
                return;
            }
            auto* cst = RE::TESForm::LookupByID<RE::Actor>(iCaster);
            auto* tgt = RE::TESForm::LookupByID<RE::Actor>(iTarget);
            SKSE::log::info("Task: interact dispatch  -  caster='{}' (0x{:08X}) target='{}' (0x{:08X}) choice={}",
                cst ? cst->GetDisplayFullName() : "(null)", iCaster,
                tgt ? tgt->GetDisplayFullName() : "(null)", iTarget, choice);
            if (!cst) {
                SKSE::log::error("Task: interact  -  caster lookup failed.");
                return;
            }
            if (!tgt) {
                // REV-147 Feature A: no-target session (iTarget == 0 from the null-target
                // panel open). The footer mode ids never reach here (intercepted above,
                // panel stays open); every target-action choice still dispatches so
                // Papyrus refuses it with the reason-coded sentinel - defense-in-depth
                // under the JS grey-out, which normally makes these clicks impossible.
                SKSE::log::warn("Task: interact  -  no target captured; dispatching for Papyrus-side refusal (choice={}).", choice);
            }
            auto* args = RE::MakeFunctionArguments(
                std::int32_t{choice},
                static_cast<RE::Actor*>(cst),
                static_cast<RE::Actor*>(tgt));
            RE::BSTSmartPointer<RE::BSScript::IStackCallbackFunctor> cb;
            vm->DispatchMethodCall(handle,
                RE::BSFixedString("SkyrimNet_BakaIntegration"),
                RE::BSFixedString("_DispatchInteractActionWithActors"),
                args, cb);
            delete args;
            SKSE::log::info("Task: _DispatchInteractActionWithActors dispatched.");
            return;
        }

        // ── Downed: dispatch with the actors captured at menu-open ──────────────
        if (mode == MenuMode::Downed) {
            auto* cst = RE::TESForm::LookupByID<RE::Actor>(dCaster);
            auto* vic = RE::TESForm::LookupByID<RE::Actor>(dVictim);
            SKSE::log::info("Task: downed dispatch  -  caster='{}' (0x{:08X}) victim='{}' (0x{:08X}) choice={}",
                cst ? cst->GetDisplayFullName() : "(null)", dCaster,
                vic ? vic->GetDisplayFullName() : "(null)", dVictim, choice);
            if (!cst || !vic) {
                SKSE::log::error("Task: downed  -  actor lookup failed.");
                return;
            }
            auto* args = RE::MakeFunctionArguments(
                std::int32_t{choice},
                static_cast<RE::Actor*>(cst),
                static_cast<RE::Actor*>(vic));
            RE::BSTSmartPointer<RE::BSScript::IStackCallbackFunctor> cb;
            vm->DispatchMethodCall(handle,
                RE::BSFixedString("SkyrimNet_BakaIntegration"),
                RE::BSFixedString("_DispatchDownedAction"),
                args, cb);
            delete args;
            SKSE::log::info("Task: _DispatchDownedAction dispatched.");
            return;
        }

        // ── MidCombat: dispatch with the actors captured at menu-open ───────────
        if (mode == MenuMode::MidCombat) {
            auto* cst = RE::TESForm::LookupByID<RE::Actor>(mCaster);
            auto* tgt = RE::TESForm::LookupByID<RE::Actor>(mTarget);
            SKSE::log::info("Task: midcombat dispatch  -  caster='{}' (0x{:08X}) target='{}' (0x{:08X}) choice={}",
                cst ? cst->GetDisplayFullName() : "(null)", mCaster,
                tgt ? tgt->GetDisplayFullName() : "(null)", mTarget, choice);
            if (!cst || !tgt) {
                SKSE::log::error("Task: midcombat  -  actor lookup failed.");
                return;
            }
            auto* args = RE::MakeFunctionArguments(
                std::int32_t{choice},
                static_cast<RE::Actor*>(cst),
                static_cast<RE::Actor*>(tgt));
            RE::BSTSmartPointer<RE::BSScript::IStackCallbackFunctor> cb;
            vm->DispatchMethodCall(handle,
                RE::BSFixedString("SkyrimNet_BakaIntegration"),
                RE::BSFixedString("_DispatchMidCombatAction"),
                args, cb);
            delete args;
            SKSE::log::info("Task: _DispatchMidCombatAction dispatched.");
            return;
        }

        // ── SlaveTats: parse "slot;section;name" → 3 strings ─────────────────────
        if (mode == MenuMode::SlaveTats) {
            SKSE::log::info("Task: slavetats spec='{}'", spec);
            // "cancel" (or anything without the two separators) = no change.
            if (spec == "cancel" || spec.find(';') == std::string::npos) {
                SKSE::log::info("Task: slavetats  -  cancelled/no-op.");
                return;
            }
            std::string parts[3] = { "", "", "" };
            {
                std::size_t start = 0;
                int idx = 0;
                while (idx < 3) {
                    const std::size_t sep = spec.find(';', start);
                    parts[idx++] = (sep == std::string::npos) ? spec.substr(start)
                                                              : spec.substr(start, sep - start);
                    if (sep == std::string::npos) break;
                    start = sep + 1;
                }
            }
            auto* args = RE::MakeFunctionArguments(
                RE::BSFixedString(parts[0].c_str()),
                RE::BSFixedString(parts[1].c_str()),
                RE::BSFixedString(parts[2].c_str()));
            RE::BSTSmartPointer<RE::BSScript::IStackCallbackFunctor> cb;
            vm->DispatchMethodCall(handle,
                RE::BSFixedString("SkyrimNet_BakaIntegration"),
                RE::BSFixedString("_ST_MenuChoice"),
                args, cb);
            delete args;
            SKSE::log::info("Task: _ST_MenuChoice dispatched (slot='{}' section='{}').", parts[0], parts[1]);
            return;
        }

        // ── SexSpank with C++ scanned actors ────────────────────────────────────
        if (mode == MenuMode::SexSpank && useCpp) {
            if (choice < 0) {
                SKSE::log::info("Task: SexSpank CPP  -  cancelled.");
                return;
            }

            auto* player = RE::PlayerCharacter::GetSingleton();
            RE::Actor* spanker = nullptr;
            RE::Actor* spankee = nullptr;

            if (choice <= 2) {
                // Player spanks scanned NPC[choice]
                spanker = player;
                if (choice < actCnt)
                    spankee = RE::TESForm::LookupByID<RE::Actor>(actIds[choice]);
            } else if (choice >= 10 && choice <= 12) {
                // Scanned NPC[choice-10] spanks player
                const int idx = choice - 10;
                if (idx < actCnt)
                    spanker = RE::TESForm::LookupByID<RE::Actor>(actIds[idx]);
                spankee = player;
            } else if (choice == 13) {
                spanker = spankee = player;
            }

            SKSE::log::info("Task: SexSpank CPP  -  spanker='{}' spankee='{}'",
                spanker ? spanker->GetDisplayFullName() : "(null)",
                spankee ? spankee->GetDisplayFullName() : "(null)");

            if (!spanker || !spankee) {
                SKSE::log::warn("Task: SexSpank CPP  -  missing actor for choice {}", choice);
                return;
            }

            auto* args = RE::MakeFunctionArguments(
                static_cast<RE::Actor*>(spanker),
                static_cast<RE::Actor*>(spankee));
            RE::BSTSmartPointer<RE::BSScript::IStackCallbackFunctor> cb;
            vm->DispatchMethodCall(handle,
                RE::BSFixedString("SkyrimNet_BakaIntegration"),
                RE::BSFixedString("_SexSpank_Execute"),
                args, cb);
            delete args;
            SKSE::log::info("Task: _SexSpank_Execute dispatched.");
            return;
        }

        // ── Normal path: interact or SexSpank with Papyrus-detected actors ──────
        SKSE::log::info("Task: dispatching OnSNBakaMenuChoice  -  strArg='{}' numArg={}", strArg, numArg);
        auto* args = RE::MakeFunctionArguments(
            RE::BSFixedString(kModEventName),
            RE::BSFixedString(strArg),
            float{numArg},
            static_cast<RE::TESForm*>(nullptr));
        vm->SendEvent(handle, RE::BSFixedString("OnSNBakaMenuChoice"), args);
        delete args;
        SKSE::log::info("Task: SendEvent complete.");
    });
}
