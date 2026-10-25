#include "SkyrimNetBridge.h"

namespace {
    // --- Sex-scene factions (resolved lazily; null when the framework isn't installed) ---
    // Mirrors the Papyrus gating: SexLabAnimatingFaction (SexLab.esm 0xE50F) and
    // OStimActorCountFaction (OStim.esp 0xECA) = "currently in an active sex scene".
    RE::TESFaction* g_sexlabAnimating  = nullptr;
    RE::TESFaction* g_ostimActorCount  = nullptr;
    bool            g_factionsResolved = false;

    void ResolveFactions() {
        if (g_factionsResolved) {
            return;
        }
        g_factionsResolved = true;
        if (auto* dh = RE::TESDataHandler::GetSingleton()) {
            g_sexlabAnimating = dh->LookupForm<RE::TESFaction>(0x00E50F, "SexLab.esm");
            g_ostimActorCount = dh->LookupForm<RE::TESFaction>(0x000ECA, "OStim.esp");
        }
    }

    bool InSexScene(RE::Actor* a) {
        ResolveFactions();
        if (g_sexlabAnimating && a->IsInFaction(g_sexlabAnimating)) {
            return true;
        }
        if (g_ostimActorCount && a->IsInFaction(g_ostimActorCount)) {
            return true;
        }
        return false;
    }

    // Eligibility predicates (visibility gates). NOTE: SkyrimNet may invoke these off the
    // main thread, so they only do cheap, read-only actor queries.
    bool NotInCombat(RE::Actor* a)   { return a && !a->IsInCombat(); }
    bool PreSexContact(RE::Actor* a) { return a && !a->IsInCombat() && !InSexScene(a); }

    // Register one top-level category (customParentCategory = "" => top level). The YAML
    // actions nest into it by setting `customCategory: <id>` to the same id string.
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
        SKSE::log::info("RegisterSubCategory '{}' -> {}", id, ok);
    }

    void RegisterCategories() {
        RegisterOne("SNBaka_Spank",
            "Open-handed strikes and blows for impact, punishment, or dominance: spank or smack the butt, "
            "slap the face/cheek, slap or strike the breasts/chest, strike the belly. Bare-hand impact, not weapon combat.",
            [](RE::Actor* a) { return NotInCombat(a); });

        RegisterOne("SNBaka_Grab",
            "Seizing, restraining, choking, and subduing BEFORE any sex scene: hug/embrace from front or behind, "
            "grab or grope from behind against their will, choke/strangle/throttle by the throat, wrestle/struggle/pin, "
            "spike a drink or drug their food, exploit a drunk or incapacitated target.",
            [](RE::Actor* a) { return PreSexContact(a); });

        RegisterOne("SNBaka_Intimate",
            "Sexual touching, kissing, and oral contact short of a full sex scene: kiss (forced or loving), "
            "touch/grope/fondle breasts, suck breasts, touch or play with the genitals/privates, examine the intimate "
            "lower body, kneel and perform oral.",
            [](RE::Actor* a) { return PreSexContact(a); });

        //  (Issue #2, the description-misroute class): the old wording told the
        // LLM to "show off your body for them" - so a "dance for me" request routed HERE,
        // where the members actually make the TARGET perform. Rewritten to name the
        // direction of performance, and (user note, ) to carry the full member
        // list so the drilldown can see inside the category.
        RegisterOne("SNBaka_Display",
            "Command or savor a display FROM the target  -  they perform, you watch and react. "
            "Flirt to make them put on a teasing display for you, or have them show off their body "
            "(ShowOffBody); or sit yourself down on their lap (SitOnLap). Also the tattoo-marking "
            "members: ApplyTattoo (brand a DOWNED target), CommandTattoo (a standing target you "
            "dominate takes your chosen mark), MarkPlayer (an NPC marks the player as owned), "
            "RemoveTattoos (strip the marks you applied). Always a target being addressed, "
            "commanded, or marked. If YOU are the one showing your body or dancing, that is the "
            "Pose category (SNGS_Pose), not this one. THIS NAME IS A CATEGORY, NOT A CALLABLE "
            "ACTION: never emit SNBaka_Display itself  -  always call the specific member action "
            "that fits the moment (Flirt, ShowOffBody, SitOnLap, ApplyTattoo, CommandTattoo, "
            "MarkPlayer, RemoveTattoos).",
            [](RE::Actor* a) { return NotInCombat(a); });

        // Confirmed live bug: this description used to also claim "escalate on a downed victim,
        // release/free the victim, inspect a captive or investigate a restrained target" -- but none
        // of those actions were ever actually members of THIS category (customCategory: SNBaka_Scene).
        // They all live in SNBaka_Downed (cat_snbaka_downed.yaml), which was split out specifically
        // because ITS category has no combat gate. Nobody updated this category's own description
        // when that split happened, so the LLM kept picking Scene expecting Escalate/HelpUp/etc. to
        // be there and found only these two -- "none of the actions are actually available." Fixed to
        // describe only what's actually here, and points at Down for everything else.
        RegisterOne("SNBaka_Scene",
            "Stop an ongoing Baka Motion animation: the initiator voluntarily calling it off themselves "
            "(CallOff), or a third party forcing it to stop (InterruptScene). For anything about a downed/"
            "defeated character instead -- escalate, help up, release, inspect, investigate -- use the "
            "Down category, not this one.",
            [](RE::Actor* a) { return NotInCombat(a); });

        RegisterOne("SNBaka_Expression",
            "Make the speaker's FACE show an emotion for a few seconds (facial expression only, no body action): "
            "happy, angry, afraid, sad, pained, surprised, or confused. Use to react emotionally to what was said or done.",
            [](RE::Actor* a) { return NotInCombat(a); });

        //  (S1 pack-split, P2 single-owner pattern): SNGS_Pose was a YAML-defined
        // category def (regalrascal.baka-gs-integration/actions/pose.yaml - DELETED at the
        // split); THIS DLL is now its unconditional single owner. Description = the
        // pose.yaml wording of record, ported faithfully (em-dashes rendered "  -  " per
        // the  DLL ASCII sweep). No visibility gate: the YAML def had none - member
        // actions (now the GS-owned Gunslicer-Poses pack) carry their own eligibility
        // rules; a != nullptr is the API header's canonical no-op gate. The GS DLL
        // (SNAnimGS_UI.dll) carries an esp-probe fallback for GS-only installs - with
        // both mods installed, this registration is the only one that fires.
        //  (Task 3, itemization audit): the member list extended from the 8
        // glossed names to the full 27-member enumeration (15 baka-pack + 12 gs-poses
        // customCategory: SNGS_Pose yamls); every callable pose now visible by name.
        //  (Issue #2, the description-misroute class): "for no one in particular"
        // REPELLED audience-driven dances - a "dance for me" request misrouted to
        // SNBaka_Display (whose members make the TARGET perform). Rewritten: posing on
        // your own OR on request - they watch, you dance (PoseDance, PoseDanceSexy). The
        // 27-member enumeration stays (user note, : category descriptions carry
        // their member lists so the drilldown can see inside).
        RegisterOne("SNGS_Pose",
            "Pose, dance, stretch, show off  -  express a mood through your body, on your own OR because "
            "someone asked to watch: they watch, you dance (PoseDance, PoseDanceSexy for dancing, twerking, "
            "or any lewd hip/backside show performed for a watcher). A held pose or performance by YOU, "
            "no physical contact (unlike SNBaka_Display, where the TARGET performs the display for you). "
            "Use when the moment invites it: music playing "
            "and you feel like dancing, celebrating a win, flirting or being teased, freshly complimented, "
            "dared, flushed with wine, relaxing or bored, praying or meditating, pleading or surrendering to "
            "someone of higher status, training, stretching, or simply striking an attitude as you speak  -  "
            "a pose pairs naturally with a line of dialogue. Held until you stop it, combat starts, or it "
            "times out on its own. Skip it entirely in combat, danger, or mid-scene  -  nothing inside is "
            "available then. THIS NAME IS A CATEGORY, NOT A CALLABLE ACTION: never emit SNGS_Pose itself  -  "
            "always call the specific member action that fits the moment (PoseDanceSexy for dancing, "
            "twerking or any lewd hip/backside show, PoseSeduce to lure, PosePresent to offer, "
            "PoseGroundSexy for floor poses, PoseStretch, PoseWorkout, PoseSubmission, PosePlead, and "
            "the rest by name: PoseAroused, PoseAutograph, PoseBraceArm, PoseCrouch, PoseDance, "
            "PoseDogeza, PoseDrink, PoseDrool, PoseFood, PoseGroundIdle, PoseHandOnChin, "
            "PoseHandOnFace, PoseIdle, PoseKneel, PoseMeditate, PosePickpocket, PoseScratchHead, "
            "PoseSelfTouch, PoseSleep). The member's own description says who may use it and when.",
            [](RE::Actor* a) { return a != nullptr; });

    }
}

void SkyrimNetBridge::Init() {
    if (!FindFunctions()) {
        SKSE::log::warn("SkyrimNet.dll not found - action categories not registered.");
        return;
    }
    const int ver = PublicGetVersion ? PublicGetVersion() : 0;
    SKSE::log::info("SkyrimNet C++ API v{} detected.", ver);

    if (!PublicRegisterCPPSubCategory) {
        SKSE::log::warn("PublicRegisterCPPSubCategory unavailable (needs SkyrimNet API v2+); skipping categories.");
        return;
    }
    RegisterCategories();
    SKSE::log::info("Category registration complete.");
}
