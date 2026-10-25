#include "PrismaUIBridge.h"

#include <algorithm>
#include <cstdlib>
#include <format>


static constexpr const char* kMenuHTMLPath    = "SNBaka_Menu/index.html";
static constexpr const char* kHudHTMLPath     = "SNBaka_Hud/index.html";
static constexpr const char* kSTMenuHTMLPath   = "SNSlaveTats_Menu/index.html";
static constexpr const char* kExecHTMLPath     = "SNBaka_ExecuteConfirm/index.html";
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
void PrismaUIBridge::RestoreTrackedCollision() noexcept {
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
void PrismaUIBridge::SetActorCollision(RE::Actor* actor, bool disable) noexcept {
    SetActorNoCharCollision(actor, disable);
}

bool PrismaUIBridge::IsAlchemyOrEnchantingFurniture(RE::TESObjectREFR* furniture) noexcept {
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

void PrismaUIBridge::RequestAPI() noexcept {
    s_prisma = static_cast<PRISMA_UI_API::IVPrismaUI1*>(
        PRISMA_UI_API::RequestPluginAPI(PRISMA_UI_API::InterfaceVersion::V1));
    if (s_prisma) {
        SKSE::log::info("PrismaUI API acquired.");
        s_prismav2 = PRISMA_UI_API::RequestPluginAPI<PRISMA_UI_API::IVPrismaUI2>();
    }
    else {
        SKSE::log::warn("PrismaUI not found - menus will fall back to vanilla messageboxes.");
    }    
}

void PrismaUIBridge::CreateMenuView() noexcept {
    if (!s_prisma) return;
    if (s_view && s_prisma->IsValid(s_view)) return; // already valid
    s_view = s_prisma->CreateView(kMenuHTMLPath);
    if (!s_prisma->IsValid(s_view)) {
        SKSE::log::error("Failed to create SNBaka_Menu view at '{}'.", kMenuHTMLPath);
        return;
    }
    s_prisma->Hide(s_view);
    s_prisma->RegisterJSListener(s_view, "snbaka_chose", OnJSChoice);
    SKSE::log::info("SNBaka_Menu view created and JS listener registered.");

    if (s_prismav2) {
        SKSE::log::info("PrismaUI v2 found: registering Javascript logging callback.");
        s_prismav2->RegisterConsoleCallback(
            s_view, [](PrismaView, PRISMA_UI_API::ConsoleMessageLevel level, const char* message) {
                const char* safeMsg = message ? message : "(null)";
                switch (level) {
                    // TODO - have config for INFO or remove after testing.
                    case PRISMA_UI_API::ConsoleMessageLevel::Log: //INFO
                    case PRISMA_UI_API::ConsoleMessageLevel::Info: //INFO
                        SKSE::log::info("[JS] {}", safeMsg);
                        break;
                    case PRISMA_UI_API::ConsoleMessageLevel::Warning:
                        SKSE::log::warn("[JS] {}", safeMsg);
                        break;
                    case PRISMA_UI_API::ConsoleMessageLevel::Error:
                        SKSE::log::error("[JS] {}", safeMsg);
                        break;
                    case PRISMA_UI_API::ConsoleMessageLevel::Debug: //DEBUG
                    default: //DEBUG
                        SKSE::log::debug("[JS] {}", safeMsg);
                        break;
                }
            });
    }
}

bool PrismaUIBridge::IsAvailable() noexcept {
    return s_prisma && s_prisma->IsValid(s_view);
}

void PrismaUIBridge::CreateHudView() noexcept {
    if (!s_prisma) return;
    if (s_hudView && s_prisma->IsValid(s_hudView)) return; // already valid
    s_hudView = s_prisma->CreateView(kHudHTMLPath);
    if (!s_prisma->IsValid(s_hudView)) {
        SKSE::log::error("Failed to create SNBaka_Hud view at '{}'.", kHudHTMLPath);
        return;
    }
    // Always "shown" -- unlike s_view's modal wizards, this overlay is never paused/focused. The HTML
    // itself starts invisible (opacity 0) and only fades in while charging; Show() just means it's
    // present in the render list, matching Ostim_interactions' OII_Hud pattern.
    s_prisma->Show(s_hudView);
    SKSE::log::info("SNBaka_Hud view created.");
}

// : dedicated SlaveTats set-picker view. Modal like s_view's wizards (created hidden,
// Show+Focus happen per open in ShowSlaveTatsView). Same "snbaka_chose" listener name  - 
// PrismaUI dispatches listeners per-view, so only the focused view's pick reaches OnJSChoice.
void PrismaUIBridge::CreateSlaveTatsView() noexcept {
    if (!s_prisma) return;
    if (s_stView && s_prisma->IsValid(s_stView)) return; // already valid
    s_stView = s_prisma->CreateView(kSTMenuHTMLPath);
    if (!s_prisma->IsValid(s_stView)) {
        SKSE::log::error("Failed to create SNSlaveTats_Menu view at '{}'.", kSTMenuHTMLPath);
        return;
    }
    s_prisma->Hide(s_stView);
    s_prisma->RegisterJSListener(s_stView, "snbaka_chose", OnJSChoice);
    SKSE::log::info("SNSlaveTats_Menu view created and JS listener registered.");
}

// : Execute-gate accept/decline view  -  same pattern as the ST picker (dedicated view,
// modal, hidden until shown per open, "snbaka_chose" listener).
void PrismaUIBridge::CreateExecuteConfirmView() noexcept {
    if (!s_prisma) return;
    if (s_execView && s_prisma->IsValid(s_execView)) return; // already valid
    s_execView = s_prisma->CreateView(kExecHTMLPath);
    if (!s_prisma->IsValid(s_execView)) {
        SKSE::log::error("Failed to create SNBaka_ExecuteConfirm view at '{}'.", kExecHTMLPath);
        return;
    }
    s_prisma->Hide(s_execView);
    s_prisma->RegisterJSListener(s_execView, "snbaka_chose", OnJSChoice);
    SKSE::log::info("SNBaka_ExecuteConfirm view created and JS listener registered.");
}

void PrismaUIBridge::SetGetUpCharge(float pct) noexcept {
    if (!s_prisma || !s_prisma->IsValid(s_hudView)) {
        SKSE::log::warn("SetGetUpCharge: HUD view unavailable, attempting recovery (pct={}).", pct);
        CreateHudView();
        if (!s_prisma || !s_prisma->IsValid(s_hudView)) {
            SKSE::log::error("SetGetUpCharge: recovery failed, dropping call.");
            return;
        }
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
    s_prisma->Invoke(s_hudView, script.c_str());
}

//  Feature B: pushes the ambient mode-button ON/OFF highlight to the open
// SNBaka_Menu footer. Papyrus arbitrates the SNBaka.MephalaMode / SNBaka.MolagBalMode
// flags and calls this at panel open and after every toggle; the DLL relays to JS via
// the proven Invoke/payload pattern (the SetGetUpCharge shape, on the MENU view).
// Safe when the panel is closed - the view exists from plugin init.
void PrismaUIBridge::SetModeStates(bool mephala, bool molagBal) noexcept {
    if (!s_prisma || !s_prisma->IsValid(s_view)) {
        SKSE::log::warn("SetModeStates: menu view unavailable, attempting recovery (mephala={} molagbal={}).", mephala, molagBal);
        CreateMenuView();
        if (!s_prisma || !s_prisma->IsValid(s_view)) {
            SKSE::log::error("SetModeStates: recovery failed, dropping call.");
            return;
        }
    }
    const auto script = std::format("window.snbakaSetModeStates({}, {})",
        mephala ? "true" : "false", molagBal ? "true" : "false");
    s_prisma->Invoke(s_view, script.c_str());
    SKSE::log::info("SetModeStates: pushed mephala={} molagbal={}.", mephala, molagBal);
}

bool PrismaUIBridge::IsMenuOpen() noexcept {
    return s_mode.load() != MenuMode::None;
}

void PrismaUIBridge::CancelMenu() noexcept {
    if (!IsMenuOpen()) return;
    // The encounter wizard's cancel signal is the string "cancel"; the other
    // menus use "-1".  Sending the wrong token to _StartSexLabScene would start
    // an unintended default scene instead of aborting.
    if (s_mode.load() == MenuMode::Encounter)
        OnJSChoice("cancel");
    else
        OnJSChoice("-1");
}

RE::Actor* PrismaUIBridge::GetInteractTarget() noexcept {
    auto* player = RE::PlayerCharacter::GetSingleton();
    RE::Actor* t = GetCrosshairActor();          // precise: what you're looking at
    if (!t || t == player)
        t = FindNearestLivingActor(kInteractRadius); // fallback: nearest in range
    if (t == player) t = nullptr;
    SKSE::log::info("GetInteractTarget -> {} (0x{:08X})",
        t ? t->GetDisplayFullName() : "(none)", t ? t->GetFormID() : 0);
    return t;
}

void PrismaUIBridge::ShowInteractMenu(RE::Actor* caster, RE::Actor* target) noexcept {
    if (!IsAvailable()) {
        // View was invalidated (PrismaUI reset after save load)  -  try to recreate.
        SKSE::log::warn("ShowInteractMenu: view invalid, attempting recovery.");
        CreateMenuView();
        if (!IsAvailable()) {
            SKSE::log::error("ShowInteractMenu: recovery failed, aborting.");
            return;
        }
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
            //  Feature A (user ruling: a power press with no target OPENS the
            // panel - all target-actions greyed + a "no target selected" overlay; the
            // two ambient-mode buttons stay LIVE). The  abort becomes the
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
    // : s_interactTarget == 0 marks the no-target session.
    s_interactCaster = caster->GetFormID();
    s_interactTarget = target ? target->GetFormID() : 0;
    SKSE::log::info("ShowInteractMenu: caster='{}' (0x{:08X})  target='{}' (0x{:08X})",
        caster->GetDisplayFullName(), s_interactCaster,
        target ? target->GetDisplayFullName() : "(no target)", s_interactTarget);

    std::string safe = target ? target->GetDisplayFullName() : "";
    for (auto& c : safe) if (c == '\'') c = '\x60';
    s_mode = MenuMode::Interact;
    const auto script = std::format("window.snbaka_open_interact('{}')", safe);
    s_prisma->Show(s_view);
    s_prisma->Invoke(s_view, script.c_str());
    // Pause while choosing so the target NPC can't wander off / combat can't move
    // things during the few seconds of selection.  Cursor still works with the
    // focus menu registered (disableFocusMenu=false).
    s_prisma->Focus(s_view, /*pauseGame=*/true, /*disableFocusMenu=*/false);
}

void PrismaUIBridge::ShowEncounterMenu(RE::Actor* aggressor, RE::Actor* victim) noexcept {
    if (!IsAvailable()) {
        CreateMenuView();
        if (!IsAvailable()) {
            SKSE::log::error("ShowEncounterMenu: view unavailable.");
            return;
        }
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
    s_prisma->Show(s_view);
    s_prisma->Invoke(s_view, script.c_str());
    // Pause during the multi-step wizard (no active SexLab scene yet - StartSex
    // runs only after the picks), so nothing drifts during the 3-4 clicks.
    s_prisma->Focus(s_view, /*pauseGame=*/true, /*disableFocusMenu=*/false);
}

void PrismaUIBridge::ShowDownedMenu(RE::Actor* caster, RE::Actor* victim) noexcept {
    if (!IsAvailable()) {
        CreateMenuView();
        if (!IsAvailable()) {
            SKSE::log::error("ShowDownedMenu: view unavailable.");
            return;
        }
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
    s_prisma->Show(s_view);
    s_prisma->Invoke(s_view, script.c_str());
    s_prisma->Focus(s_view, /*pauseGame=*/true, /*disableFocusMenu=*/false);
}

void PrismaUIBridge::ShowMidCombatMenu(RE::Actor* caster, RE::Actor* target) noexcept {
    if (!IsAvailable()) {
        CreateMenuView();
        if (!IsAvailable()) {
            SKSE::log::error("ShowMidCombatMenu: view unavailable.");
            return;
        }
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
    s_prisma->Show(s_view);
    s_prisma->Invoke(s_view, script.c_str());
    s_prisma->Focus(s_view, /*pauseGame=*/true, /*disableFocusMenu=*/false);
}

// : SlaveTats degradation-set picker. Dedicated view (SNSlaveTats_Menu/index.html); the
// pick comes back on the same "snbaka_chose" JS listener, with a "slot;section;name" spec
// (or "cancel") which OnJSChoice parses and dispatches to _ST_MenuChoice.
void PrismaUIBridge::ShowSlaveTatsMenu(const std::string& json) noexcept {
    if (!s_prisma) return;
    if (!(s_stView && s_prisma->IsValid(s_stView))) {
        CreateSlaveTatsView();
        if (!(s_stView && s_prisma->IsValid(s_stView))) {
            SKSE::log::error("ShowSlaveTatsMenu: view unavailable.");
            return;
        }
    }

    s_mode = MenuMode::SlaveTats;
    // Escape single-quotes in section/name keys before embedding into the JS call.
    std::string effective = json;
    for (auto& c : effective) if (c == '\'') c = '\x60';
    const auto script = std::format("window.snbaka_open_slavetats('{}')", effective);
    s_prisma->Show(s_stView);
    s_prisma->Invoke(s_stView, script.c_str());
    // Pause while picking (like the encounter wizard): the choice changes set
    // state that later events read, and nothing in-world needs to run meanwhile.
    s_prisma->Focus(s_stView, /*pauseGame=*/true, /*disableFocusMenu=*/false);
}

// : Execute-gate accept/decline popup. Same shape as ShowSlaveTatsView, but the
// payload carries BOTH actor names (initiator + target) and a 20s JS auto-close (the
// player who walked away gets a deterministic decline rather than a stuck paused menu;
// Papyrus still owns the authoritative 30s timeout + moot polling). Accept = "0",
// decline/cancel/timeout = "-1"  -  both ride the normal-path SendEvent as
// strArg="execconfirm" and land in OnSNBakaMenuChoice.
void PrismaUIBridge::ShowExecuteConfirm(RE::Actor* initiator, RE::Actor* target) noexcept {
    if (!s_prisma) return;
    if (!(s_execView && s_prisma->IsValid(s_execView))) {
        CreateExecuteConfirmView();
        if (!(s_execView && s_prisma->IsValid(s_execView))) {
            SKSE::log::error("ShowExecuteConfirm: view unavailable.");
            return;
        }
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
    s_prisma->Show(s_execView);
    s_prisma->Invoke(s_execView, script.c_str());
    // A killing blow must not land mid-menu  -  pause while the player decides.
    s_prisma->Focus(s_execView, /*pauseGame=*/true, /*disableFocusMenu=*/false);
}

void PrismaUIBridge::ShowSexSpankMenu(const std::string& json) noexcept {
    if (!IsAvailable()) {
        CreateMenuView();
        if (!IsAvailable()) {
            SKSE::log::error("ShowSexSpankMenu: view unavailable.");
            return;
        }
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
    // Escape single-quotes in NPC names before embedding into the JS call.
    for (auto& c : effectiveJson) if (c == '\'') c = '\x60';
    const auto script = std::format("window.snbaka_open_sexspank('{}')", effectiveJson);
    s_prisma->Show(s_view);
    s_prisma->Invoke(s_view, script.c_str());
    s_prisma->Focus(s_view, /*pauseGame=*/false, /*disableFocusMenu=*/false);
}

void PrismaUIBridge::OnJSChoice(const char* value) noexcept {
    if (!s_prisma) return;

    SKSE::log::info("OnJSChoice: value='{}'", value ? value : "(null)");

    //  Feature B: reserved footer mode-button ids ("900"/"901") KEEP THE
    // PANEL OPEN - no mode exchange, no Unfocus/Hide (the  JS design intent:
    // "both modes can be toggled in one visit"; until now the bridge still closed the
    // view on every pick, so a toggle also dismissed the panel). The toggle is
    // dispatched to Papyrus _MenuModeButton, which arbitrates and pushes the new
    // button states back via SetModeStates. Cuts across every panel mode (the footer
    // is panel-wide), so it precedes the per-mode dispatch below.
    if (value && value[0] == '9' && value[1] == '0'
        && (value[2] == '0' || value[2] == '1') && value[3] == '\0') {
        const int which = (value[2] == '0') ? 900 : 901;
        SKSE::log::info("OnJSChoice: mode button {} - panel stays open (REV-147).", which);
        SKSE::GetTaskInterface()->AddTask([which]() {
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
    // (: the SlaveTats picker lives on its own s_stView, not s_view;
    //  : the Execute-confirm popup likewise lives on s_execView).
    const MenuMode mode = s_mode.exchange(MenuMode::None);
    const PrismaView view = (mode == MenuMode::SlaveTats)      ? s_stView
                          : (mode == MenuMode::ExecuteConfirm) ? s_execView
                          : s_view;
    s_prisma->Unfocus(view);
    s_prisma->Hide(view);
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

    SKSE::GetTaskInterface()->AddTask([numArg, strArg, mode, choice, useCpp, actIds, actCnt, iCaster, iTarget, eAgg, eVic, dCaster, dVictim, mCaster, mTarget, spec]() {
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
                //  Feature A: no-target session (iTarget == 0 from the null-target
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
