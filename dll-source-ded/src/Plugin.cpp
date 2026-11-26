#include "PCH.h"
#include "ServiceState.h"
#include "Scheduler.h"
#include "EventPump.h"
#include "ActorContextStore.h"
#include "DDGuard.h"
#include "ModuleRegistry.h"
#include "UIHost.h"
#include "PanelFlags.h"
#include "PanelHost.h"
#include "Preview.h"
#include "Downed.h"

#include <filesystem>

#include <spdlog/sinks/basic_file_sink.h>
#include <RE/B/BSInputDeviceManager.h>
#include <RE/I/InputEvent.h>

namespace DeD
{
	bool RegisterPapyrusFunctions(RE::BSScript::IVirtualMachine* a_vm);
}

// ---------------------------------------------------------------------------
// Scheduler drive: input-event sink as the main-thread frame callback (the
// dll-source-gs proven pattern). The device manager pumps this sink per
// frame (quiet frames arrive with an empty event list), which gives the
// scheduler a zero-thread, zero-hook frame drive; Drive() self-throttles to
// one evaluation pass per second. Input is untouched (always kContinue).
// ---------------------------------------------------------------------------
class ServiceDriveSink : public RE::BSTEventSink<RE::InputEvent*> {
public:
    static ServiceDriveSink* GetSingleton() {
        static ServiceDriveSink instance;
        return &instance;
    }

    RE::BSEventNotifyControl ProcessEvent(RE::InputEvent* const*,
                                          RE::BSTEventSource<RE::InputEvent*>*) override {
        DeD::Scheduler::GetSingleton().Drive();
        return RE::BSEventNotifyControl::kContinue;
    }
};

// ---------------------------------------------------------------------------
// REV-187 -- DDNG stale-strip guard sink (spec of record:
// docs/specs/ddng-force-strip-after-redress-guard.md v1.2, Component 4).
// TESEquipEvent dispatches synchronously inside the engine equip path, on
// the initiating caller's thread, so stack attribution in the sink names the
// initiator (the SNEquipTrap technique). Every event passes through kContinue
// — nothing is blocked or reversed here.
// ---------------------------------------------------------------------------
class DDGuardEquipSink : public RE::BSTEventSink<RE::TESEquipEvent> {
public:
    static DDGuardEquipSink* GetSingleton() {
        static DDGuardEquipSink instance;
        return &instance;
    }

    RE::BSEventNotifyControl ProcessEvent(const RE::TESEquipEvent* a_event,
                                          RE::BSTEventSource<RE::TESEquipEvent>*) override {
        if (a_event && a_event->actor && a_event->equipped == 0) { // unequip only
            const auto actor = skyrim_cast<RE::Actor*>(a_event->actor.get());
            if (actor && DeD::DDGuard::GetSingleton().OnUnequip(actor, a_event->baseObject)) {
                // Hit: DeviousDevices.dll-attributed armor unequip. The Papyrus
                // handler (SkyrimNet_BakaIntegration.OnDDGuardStrip) owns the
                // redress window / zero-device gate / single retry — this DLL stays
                // attribution-only and never touches DD state (ruling of record #3).
                DeD::EventPump::Emit(DeD::DDGuard::kHitEvent, actor,
                                     0.0f, fmt::format("{:08X}", a_event->baseObject));
            }
        }
        return RE::BSEventNotifyControl::kContinue;
    }
};

static void SetupLog() {
    auto logsFolder = SKSE::log::log_directory();
    if (!logsFolder) return;
    auto logPath = *logsFolder / "DeDService.log";
    auto sink = std::make_shared<spdlog::sinks::basic_file_sink_mt>(logPath.string(), true);
    auto logger = std::make_shared<spdlog::logger>("DeDService", std::move(sink));
    logger->set_level(spdlog::level::trace);
    logger->flush_on(spdlog::level::trace);
    spdlog::set_default_logger(std::move(logger));
}

// ---------------------------------------------------------------------------
// Cosave handler (spec section 2.1/2.2 binding constraints; section 0.3
// adoptions: tag + version per record, receipt logging on Save/Load/Revert).
// ---------------------------------------------------------------------------
static void OnSaveCallback(SKSE::SerializationInterface* a_intfc)
{
    auto& state = DeD::ServiceState::GetSingleton();
    auto& sched = DeD::Scheduler::GetSingleton();
    {
        std::lock_guard lock(state.m_mutex);
        const auto buf = state.Save();
        if (!a_intfc->WriteRecord(DeD::ServiceState::kRecordType,
                                  DeD::ServiceState::kSchemaVersion,
                                  buf.data(), static_cast<std::uint32_t>(buf.size()))) {
            SKSE::log::error("[DeDService] STTE save failed.");
        } else {
            // REV-116: positive save receipt (spec §0.3 adoption -- receipt
            // logging on cosave ops; REV-115 shipped failures-only and the
            // dogfood had no way to see success from logs alone).
            SKSE::log::info("[DeDService] STTE record written ({} B, schema v{}).",
                            buf.size(), DeD::ServiceState::kSchemaVersion);
        }
    }
    {
        std::lock_guard lock(sched.m_mutex);
        const auto buf = sched.Save();
        if (!a_intfc->WriteRecord(DeD::Scheduler::kRecordType,
                                  DeD::Scheduler::kSchemaVersion,
                                  buf.data(), static_cast<std::uint32_t>(buf.size()))) {
            SKSE::log::error("[DeDService] TMRS save failed.");
        } else {
            // REV-116: positive save receipt (spec §0.3 adoption).
            SKSE::log::info("[DeDService] TMRS record written ({} B, schema v{}).",
                            buf.size(), DeD::Scheduler::kSchemaVersion);
        }
    }
    {
        // A3b leg 1 (S338): the DeD Downed state (DWND); Downed::Save takes its own lock.
        const auto buf = DeD::Downed::GetSingleton().Save();
        if (!a_intfc->WriteRecord(DeD::Downed::kRecordType, DeD::Downed::kSchemaVersion,
                                  buf.data(), static_cast<std::uint32_t>(buf.size()))) {
            SKSE::log::error("[DeDService] DWND save failed.");
        }
    }
}

static void OnLoadCallback(SKSE::SerializationInterface* a_intfc)
{
    std::uint32_t type, version, length;
    std::uint32_t loaded = 0, rejected = 0, malformed = 0, unknown = 0;
    while (a_intfc->GetNextRecordInfo(type, version, length)) {
        std::vector<std::uint8_t> data(length);
        if (length > 0 && a_intfc->ReadRecordData(data.data(), length) != length) {
            SKSE::log::warn("[DeDService] record {:08x} short read -- skipped.", type);
            continue;
        }
        if (type == DeD::ServiceState::kRecordType) {
            if (version != DeD::ServiceState::kSchemaVersion) {
                SKSE::log::warn("[DeDService] STTE version {} unsupported -- rejected.", version);
                ++rejected;
                continue;
            }
            if (!DeD::ServiceState::GetSingleton().Load(a_intfc, length, data.data())) {
                SKSE::log::warn("[DeDService] STTE malformed -- state reset.");
                ++malformed;
            } else {
                // REV-116: positive load receipt (spec §0.3 adoption).
                SKSE::log::info("[DeDService] STTE record read ({} B, schema v{}) -- loaded.",
                                length, version);
                ++loaded;
            }
        } else if (type == DeD::Scheduler::kRecordType) {
            if (version != DeD::Scheduler::kSchemaVersion) {
                SKSE::log::warn("[DeDService] TMRS version {} unsupported -- rejected.", version);
                ++rejected;
                continue;
            }
            if (!DeD::Scheduler::GetSingleton().Load(length, data.data())) {
                SKSE::log::warn("[DeDService] TMRS malformed -- rules reset.");
                ++malformed;
            } else {
                // REV-116: positive load receipt (spec §0.3 adoption).
                SKSE::log::info("[DeDService] TMRS record read ({} B, schema v{}) -- loaded.",
                                length, version);
                ++loaded;
            }
        } else if (type == DeD::Downed::kRecordType) {
            if (version != DeD::Downed::kSchemaVersion) {
                SKSE::log::warn("[DeDService] DWND version {} unsupported -- rejected.", version);
                ++rejected;
                continue;
            }
            if (!DeD::Downed::GetSingleton().Load(a_intfc, length, data.data())) {
                SKSE::log::warn("[DeDService] DWND malformed -- downed state reset.");
                DeD::Downed::GetSingleton().Revert();
                ++malformed;
            } else {
                ++loaded;
            }
        } else {
            // Unknown tags: skipped silently (standard SKSE shape; spec 0.1.3).
            ++unknown;
        }
    }
    // REV-116: load summary receipt (spec §0.3) -- makes the with-DLL
    // round-trip leg provable from DeDService.log alone, cross-checked by
    // the independent .skse block-walk.
    if (loaded + rejected + malformed + unknown > 0) {
        SKSE::log::info("[DeDService] cosave load complete: {} loaded, {} rejected, {} malformed, {} unknown.",
                        loaded, rejected, malformed, unknown);
    }
}

static void OnRevertCallback(SKSE::SerializationInterface*)
{
    DeD::ServiceState::GetSingleton().Revert();
    DeD::Scheduler::GetSingleton().Revert();
    DeD::ActorContextStore::GetSingleton().Revert(); // REV-170 Leg 3: in-memory only, dropped wholesale
    DeD::PanelFlags::GetSingleton().Revert();
    DeD::Downed::GetSingleton().Revert();            // A3b leg 1: DWND rows reload from the cosave        // Phase 2: modules re-publish their flags after load
    SKSE::log::info("[DeDService] reverted (new game / cosave discard).");
}

// Magelight Phase 2 leg 6: the one DeD power (DeD_Framework.esp SPEL 0x802, effect script DeD_PanelPowerEffect ->
// DeDService.OpenPanel). On every load: with the panel available, the player holds the DeD power and the two old
// powers (Baka "DeD: Interact" 0x80E, GS pose selector 0xD63) are removed - Baka / GS no longer grant them while the
// panel is available. Without the panel (Magelight UI or the page missing) the DeD power is withheld and the old
// powers stay with their Phase 1 menus. Idempotent; unconditional log line.
static void SyncPanelPower()
{
    auto* player = RE::PlayerCharacter::GetSingleton();
    auto* dh     = RE::TESDataHandler::GetSingleton();
    if (!player || !dh) return;
    auto* power = dh->LookupForm<RE::SpellItem>(0x802, "DeD_Framework.esp");
    const bool panel = DeD::UIHost::GetSingleton().HasView(DeD::PanelHost::kModule, DeD::PanelHost::kView);
    int removed = 0;
    if (panel && power) {
        if (!player->HasSpell(power)) player->AddSpell(power);
        const std::pair<RE::FormID, const char*> old[] = { { 0x80E, "SkyrimNet_BakaIntegration.esp" }, { 0xD63, "SkyrimNet_AnimationsGS.esp" } };
        for (const auto& [id, file] : old) {
            auto* sp = dh->LookupForm<RE::SpellItem>(id, file);
            if (sp && player->HasSpell(sp)) { player->RemoveSpell(sp); ++removed; }
        }
    } else if (power && player->HasSpell(power)) {
        player->RemoveSpell(power);
    }
    SKSE::log::info("[DeDService][PANEL] power sync: panel {}, DeD power {} ({}), old powers removed {}.",
        panel ? "available" : "absent", power ? "found" : "MISSING from DeD_Framework.esp",
        panel && power ? "granted" : "withheld", removed);
}

SKSEPluginLoad(const SKSE::LoadInterface* skse) {
    SKSE::Init(skse);
    SetupLog();
    SKSE::log::info("[DeDService] Plugin loaded.");

    auto* serialization = SKSE::GetSerializationInterface();
    // REV-116: the serialization UID is a BUILD REQUIREMENT (service-dll.md §2
    // constraint 5, amended this rev; the REV-115 dogfood gap of record).
    // skse64's save-callback gate is `info->save && info->hadUID`
    // (skse64 Serialization.cpp L372) -- without SetUniqueID the save
    // callback is silently skipped and STTE/TMRS never reach the cosave.
    // UID of record: 'DSED' (0x44455344), ruled REV-116 by OUR collision
    // check (skse64's own check is warn-only): 0 hits in both byte orders
    // against all 47 plugin UIDs in dogfood saves Save516/Save517 (receipt
    // rev116-uidcheck.txt; re-run when the load order gains a serialization
    // plugin).
    serialization->SetUniqueID('DSED');
    serialization->SetSaveCallback(OnSaveCallback);
    serialization->SetLoadCallback(OnLoadCallback);
    serialization->SetRevertCallback(OnRevertCallback);

    SKSE::GetMessagingInterface()->RegisterListener([](SKSE::MessagingInterface::Message* msg) {
        switch (msg->type) {
        case SKSE::MessagingInterface::kDataLoaded:
            RE::BSInputDeviceManager::GetSingleton()->AddEventSink(ServiceDriveSink::GetSingleton());
            SKSE::log::info("[DeDService] scheduler drive registered (input sink).");
            {
                // REV-187 / spec Component 1 gate: resolve DDNG presence once, at
                // kDataLoaded. Absent -> the guard sink is never armed (zero behavior
                // change on non-DDNG lists) and every Papyrus guard no-ops.
                if (SKSE::GetPluginInfo("DeviousDevices")) {
                    DeD::DDGuard::GetSingleton().SetDDNGPresent();
                    SKSE::log::info("[DeDService] DDNG present -- DDGuard equip sink armed.");
                    RE::ScriptEventSourceHolder::GetSingleton()->AddEventSink<RE::TESEquipEvent>(
                        DDGuardEquipSink::GetSingleton());
                } else {
                    SKSE::log::info("[DeDService] DDNG absent -- DDGuard stays inert this load.");
                }
            }
            {
                // REV-170 Leg 3: resolve the SkyrimNet C++ surface (DevKit
                // CppAPI contract: LoadLibraryA("SkyrimNet") + GetProcAddress;
                // v3+ gates FormIDToUUID; older installs degrade the Actor
                // Context store to always-MISS, never crash).
                auto hSN = LoadLibraryA("SkyrimNet");
                if (hSN) {
                    auto ver = reinterpret_cast<int (*)()>(GetProcAddress(hSN, "PublicGetVersion"));
                    const int snVer = ver ? ver() : 0;
                    if (snVer >= 3) {
                        DeD::ActorContextStore::GetSingleton().PublicFormIDToUUID =
                            reinterpret_cast<std::uint64_t (*)(std::uint32_t)>(
                                GetProcAddress(hSN, "PublicFormIDToUUID"));
                    }
                    SKSE::log::info("[DeDService] SkyrimNet C++ surface {} (api v{}; ActorContext {}).",
                        DeD::ActorContextStore::GetSingleton().PublicFormIDToUUID ? "resolved" : "absent",
                        snVer,
                        DeD::ActorContextStore::GetSingleton().PublicFormIDToUUID ? "LIVE" : "MISS-only");
                } else {
                    SKSE::log::info("[DeDService] SkyrimNet not loaded -- ActorContext MISS-only.");
                }
            }
            {
                // Magelight workstream Phase 1 (docs/workstreams/magelight-ui.md 6c): read the
                // installed modules' descriptors, then host their views. Modules talk to the
                // host through the DeDUI C ABI (include/DeDUI_API.h); nothing here knows a module.
                wchar_t exe[MAX_PATH]{};
                ::GetModuleFileNameW(nullptr, exe, MAX_PATH);
                const auto dedRoot = std::filesystem::path(exe).parent_path() / L"Data" / L"Magelight" / L"DeD";
                DeD::ModuleRegistry::GetSingleton().Load(dedRoot);
                DeD::UIHost::GetSingleton().Init(dedRoot);
            }
            // Tattoo-overhaul T2 (S330): the Phantasm client for live previews (soft dependency, D-T4).
            DeD::Preview::GetSingleton().Init();
            break;
        case SKSE::MessagingInterface::kPostLoadGame:
        case SKSE::MessagingInterface::kNewGame:
            DeD::Preview::GetSingleton().OnGameLoad();
            SyncPanelPower();
            break;
        }
    });

    SKSE::GetPapyrusInterface()->Register(
        [](RE::BSScript::IVirtualMachine* vm) { return DeD::RegisterPapyrusFunctions(vm); });
    SKSE::log::info("[DeDService] runtime: Skyrim {} {} (one DLL for SE/AE/VR).", (REL::Module::IsVR() ? "VR" : (REL::Module::IsAE() ? "AE" : "SE")), REL::Module::get().version().string());
    SKSE::log::info("[DeDService] boot complete.");
    return true;
}
