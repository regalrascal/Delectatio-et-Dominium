#include "PCH.h"
#include "ServiceState.h"
#include "Scheduler.h"
#include "EventPump.h"
#include "ActorContextStore.h"

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
    SKSE::log::info("[DeDService] reverted (new game / cosave discard).");
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
            break;
        }
    });

    SKSE::GetPapyrusInterface()->Register(
        [](RE::BSScript::IVirtualMachine* vm) { return DeD::RegisterPapyrusFunctions(vm); });
    SKSE::log::info("[DeDService] boot complete.");
    return true;
}
