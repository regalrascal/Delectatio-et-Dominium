#include "SkyrimNetBridge.h"

namespace {
    //  (S1 pack-split, P2 single-owner pattern): this DLL registers SNGS_Pose
    // ONLY as the esp-probe FALLBACK - the Baka DLL (SkyrimNet_BakaIntegration.dll) is
    // the def's unconditional owner. Probe = resolving the Baka motherboard quest
    // (QUST 0xD62); null exactly when SkyrimNet_BakaIntegration.esp is absent from the
    // load order (same lookup shape as PrismaUIBridge.cpp's BakaIntegration quest
    // resolve). Rationale: the 12 GS-owned pose YAMLs (Gunslicer-Poses pack) reference
    // customCategory: SNGS_Pose; a GS-only install has no Baka DLL, so without this
    // fallback their category def would be an orphan (the vanish-from-menu prediction,
    // R2/FILE_STRUCTURE).
    bool BakaIntegrationPresent() {
        auto* dh = RE::TESDataHandler::GetSingleton();
        return dh && dh->LookupForm<RE::TESQuest>(0x000D62, "SkyrimNet_BakaIntegration.esp") != nullptr;
    }

    // Same shape as the Baka DLL's RegisterOne (dll-source/src/SkyrimNetBridge.cpp) -
    // kept local so this bridge carries no Baka-side state (factions, predicates).
    void RegisterOne(const char* id, const char* description, std::function<bool(RE::Actor*)> elig) {
        const bool ok = PublicRegisterCPPSubCategory(
            id,                 // name (unique identifier)
            description,        // shown to the LLM at category-selection time
            std::move(elig),    // visibility gate
            "",                 // triggeringEventTypesCSV
            50,                 // priority
            "{}",               // parameterSchemaJSON (reserved)
            id,                 // customCategory (what YAML actions reference)
            "",                 // customParentCategory ("" = top level)
            "");                // tagsCSV
        SKSE::log::info("[SNAnimGS] RegisterSubCategory '{}' -> {}", id, ok);
    }
}

void SkyrimNetBridge::Init() {
    if (BakaIntegrationPresent()) {
        // Per-reason sentinel: the common case on a unified install - stay silent, the
        // owner DLL has the def.
        SKSE::log::info("[SNAnimGS] REV-103: Baka integration present - SNGS_Pose owned by "
                        "SkyrimNet_BakaIntegration.dll; GS fallback stays silent.");
        return;
    }
    if (!FindFunctions()) {
        SKSE::log::warn("[SNAnimGS] SkyrimNet.dll not found - SNGS_Pose fallback not registered "
                        "(GS-owned pose YAMLs will orphan; check the SkyrimNet install).");
        return;
    }
    const int ver = PublicGetVersion ? PublicGetVersion() : 0;
    if (!PublicRegisterCPPSubCategory) {
        SKSE::log::warn("[SNAnimGS] PublicRegisterCPPSubCategory unavailable (needs SkyrimNet API v2+) - "
                        "SNGS_Pose fallback not registered.");
        return;
    }
    SKSE::log::info("[SNAnimGS] SkyrimNet C++ API v{} detected (Baka integration absent - GS fallback path, REV-103).", ver);
    // Description = the deleted pose.yaml wording of record (regalrascal.baka-gs-integration
    // pack;  ruling (b): ported faithfully; em-dashes rendered "  -  " per the
    //  DLL ASCII sweep). No visibility gate: the YAML def had none (member actions
    // carry their own eligibility rules) - a != nullptr is the API header's canonical no-op.
    RegisterOne("SNGS_Pose",
        "Pose, dance, stretch, show off  -  express a mood through your body, on your own, for no one in "
        "particular: a SOLO held pose or gesture, no target, no physical contact (unlike SNBaka_Display, "
        "which is a brief beat performed FOR someone else). Use when the moment invites it: music playing "
        "and you feel like dancing, celebrating a win, flirting or being teased, freshly complimented, "
        "dared, flushed with wine, relaxing or bored, praying or meditating, pleading or surrendering to "
        "someone of higher status, training, stretching, or simply striking an attitude as you speak  -  "
        "a pose pairs naturally with a line of dialogue. Held until you stop it, combat starts, or it "
        "times out on its own. Skip it entirely in combat, danger, or mid-scene  -  nothing inside is "
        "available then.",
        [](RE::Actor* a) { return a != nullptr; });
    SKSE::log::info("[SNAnimGS] REV-103: SNGS_Pose registered by GS fallback (GS-only install).");
}