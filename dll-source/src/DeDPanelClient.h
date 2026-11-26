#pragma once

#include <array>
#include <atomic>
#include <string>
#include <vector>

#include "DeDUI_API.h"   // DeDService UI host contract (dll-source-ded/include)

namespace RE { class Actor; }

class DeDPanelClient {
public:
    static void RequestAPI() noexcept;
    static void OnGameLoaded() noexcept;   // leg 5: SlaveTats panel handler + automatic pack rescan (kPostLoadGame / kNewGame)
    static void CreateMenuView() noexcept;
    static bool IsAvailable() noexcept;

    // Separate, always-on ambient overlay view (never Focus()'d/paused, unlike the modal wizard views
    // above) -- same pattern as Ostim_interactions' OII_Hud. Currently just the get-up-key charge bar,
    // but any future passive HUD element belongs here, not on s_view.
    static void CreateHudView() noexcept;
    // REV-72: dedicated SlaveTats set-picker view (modal, like s_view's wizards).
    static void CreateSlaveTatsView() noexcept;
    // Updates the get-up-key "charging toward 3s" bar. pct in [0,1]; negative hides it.
    static void SetGetUpCharge(float pct) noexcept;

    // REV-147 Feature B: pushes the ambient mode-button ON/OFF highlight state to the
    // SNBaka_Menu footer (Papyrus arbitrates the SNBaka.MephalaMode/MolagBalMode flags;
    // this relays them to JS - the SetGetUpCharge invoke pattern, on the menu view).
    // Called at panel open and after every toggle.
    static void SetModeStates(bool mephala, bool molagBal) noexcept;
    static bool IsMenuOpen() noexcept;
    static bool InUICallback() noexcept { return t_inUICallback; }
    static void CancelMenu() noexcept;
    static void ShowInteractMenu(RE::Actor* caster, RE::Actor* target) noexcept;
    static void ShowSexSpankMenu(const std::string& json) noexcept;

    // Multi-step SexLab encounter setup (Roles -> Intensity -> Flavor -> Type).
    // The player's picks come back as a "role;intensity;flavor;type" spec string
    // (or "cancel") and are dispatched to Papyrus _StartSexLabScene with these actors.
    static void ShowEncounterMenu(RE::Actor* aggressor, RE::Actor* victim) noexcept;

    // Downed-victim menu (Escalate / Investigate / Inspect / Stand Back / Help Up). The pick
    // comes back to Papyrus _DispatchDownedAction(choice, caster, victim).
    static void ShowDownedMenu(RE::Actor* caster, RE::Actor* victim) noexcept;

    // In-combat "Grapple" menu (Struggle, and eventually Grab Hold / Choke Behind) -- shown instead
    // of the normal interact menu when the target is hostile and actively fighting the caster. The
    // pick comes back to Papyrus _DispatchMidCombatAction(choice, caster, target).
    static void ShowMidCombatMenu(RE::Actor* caster, RE::Actor* target) noexcept;

    // REV-72 SlaveTats degradation-set picker (SNSlaveTats_Menu view). The player's pick comes
    // back as a "slot;section;name" spec string (or "cancel") and is dispatched to Papyrus
    // SkyrimNet_BakaIntegration._ST_MenuChoice with the three parsed strings.
    static void ShowSlaveTatsMenu(const std::string& json) noexcept;

    // REV-92 Execute-gate accept/decline popup (SNBaka_ExecuteConfirm view, ST-menu precedent).
    // Papyrus waits (world paused by Focus) for the pick; the answer comes back as
    // SNBaka_MenuChoice strArg="execconfirm": 0 = accept, -1 = decline (also the DLL-side
    // 20s auto-close / cancel token  -  Papyrus owns the authoritative 30s timeout + moot poll).
    static void ShowExecuteConfirm(RE::Actor* initiator, RE::Actor* target) noexcept;

    // Resolves the NPC the player is targeting (crosshair, then nearest-actor
    // fallback).  Returns nullptr if none / only the player.  Called from
    // OnEffectStart so Papyrus runs its sex/escalate/interact checks on the
    // real target even though the spell is self-delivered.
    static RE::Actor* GetInteractTarget() noexcept;

    // Restore original Havok bumper-capsule radius on every actor we previously shrank.
    // Called on game load to clean up anything left dangling after a crash/reload.
    static void RestoreTrackedCollision() noexcept;

    // Shrinks (disable=true) or restores (disable=false) an actor's Havok character-bumper
    // capsule -- the shape responsible for pushing other actors away when they get close.
    // Called per-animation from Papyrus for both participants so a paired sequence doesn't
    // shove them apart.
    static void SetActorCollision(RE::Actor* actor, bool disable) noexcept;

    // True if the furniture is an alchemy lab or enchanting table (incl. experiment
    // variants).  Used to bias the SkyrimNet spank action toward those stations.
    static bool IsAlchemyOrEnchantingFurniture(RE::TESObjectREFR* furniture) noexcept;

private:
    static void OnJSChoice(const char* value) noexcept;

    // Magelight workstream Phase 1 (docs/workstreams/magelight-ui.md 6c): DeDService hosts the
    // views; this module only drives them. Resolves the DeDUI API lazily (DeDService may finish
    // kDataLoaded after us) and registers the pick/close handlers once.
    static bool EnsureUI() noexcept;
    static bool OpenBakaView(const char* view, const std::string& script, bool pause, const char* module = kModuleId) noexcept;
    static void OnUIPick(const char* moduleId, const char* view, const char* listener, const char* payload, void* user);
    static void OnUIClosed(const char* moduleId, const char* view, DeDUI::CloseReason reason, void* user);
    // True while a DeDService handler runs (game thread): OnJSChoice runs its dispatch inline
    // instead of SKSE AddTask (Magelight: never AddTask from inside a host callback; VR can hang).
    static inline thread_local bool t_inUICallback = false;

    // REV-92: creates the SNBaka_ExecuteConfirm view (idempotent, like CreateSlaveTatsView).
    static void CreateExecuteConfirmView() noexcept;

    enum class MenuMode { None, Interact, SexSpank, Encounter, Downed, MidCombat, SlaveTats, ExecuteConfirm };

    static constexpr const char*              kModuleId = "baka";   // descriptor id (Magelight/DeD/modules/baka.json)
    static inline const DeDUI::Api1*          s_ui      = nullptr;
    static inline std::atomic<bool>           s_handlerSet = false;
    static inline std::atomic<MenuMode>       s_mode   = MenuMode::None;

    // When Papyrus-side sex scene detection returns no NPCs we fall back to a
    // C++ proximity scan.  We store FormIDs (not raw pointers) so they remain
    // valid across frame boundaries.  s_usingCppSexActors gates the alternate
    // dispatch path in OnJSChoice.
    static inline bool                      s_usingCppSexActors = false;
    static inline std::array<RE::FormID, 3> s_sexActorIds       = {};
    static inline std::uint8_t              s_sexActorCount     = 0;

    // Interact actors captured at menu-open, dispatched back when the player
    // picks an action.  Held as FormIDs so they survive the open-menu gap and
    // can't be clobbered by Papyrus re-entry (the game runs unpaused).
    static inline RE::FormID s_interactCaster = 0;
    static inline RE::FormID s_interactTarget = 0;

    // Encounter actors captured at menu-open, used when the spec comes back.
    static inline RE::FormID s_encAggressor = 0;
    static inline RE::FormID s_encVictim    = 0;

    // Downed-menu actors captured at menu-open, used when the choice comes back.
    static inline RE::FormID s_downedCaster = 0;
    static inline RE::FormID s_downedVictim = 0;

    // Mid-combat "Grapple" menu actors captured at menu-open, used when the choice comes back. Kept
    // separate from s_interactCaster/Target (not reused) so an in-flight normal interact menu and
    // this one can never cross-contaminate each other's captured actors.
    static inline RE::FormID s_midCombatCaster = 0;
    static inline RE::FormID s_midCombatTarget = 0;

    // ---- Magelight Phase 2 leg 3: the Baka section of the combined DeD panel (BakaPanel.cpp) ----
    // When DeDService's panel is available, the Show*Menu entry points open the panel on the Baka
    // section instead of the Phase 1 "baka.menu" view; picks come back through OnPanel and reuse the
    // same choice strings, so OnJSChoice and every Papyrus dispatcher run unchanged.
    static bool PanelReady() noexcept;
    static void OnPanel(const char* moduleId, const char* kind, const char* json, std::uint32_t targetFormID, void* user);
    static void PushSection() noexcept;
    static std::string SectionJson();
    static inline const DeDUI::Api2*          s_ui2 = nullptr;
    static inline std::atomic<bool>           s_panelHandlerSet = false;
    static inline std::string                 s_tab;             // the Baka tab showing
    static inline std::vector<std::string>    s_sexNames;        // spank menu names (Papyrus json or C++ scan)
    static inline bool                        s_sexPlayerInScene = false;
    static inline int                         s_sexPhase = 0;    // 0 who, 1 by whom
    static inline int                         s_encStep = 0;     // encounter step 0..3
    static inline std::array<std::string, 4>  s_encChoice = {};
    static inline bool                        s_mephala = false, s_molagBal = false;

    // Leg 5: the SlaveTats section (SlaveTatsPanel.cpp). The Papyrus-only module answers via DeDService natives.
    static bool STPanelInit() noexcept;
    static void OnSTPanel(const char* moduleId, const char* kind, const char* json, std::uint32_t targetFormID, void* user);
    static bool OpenSTPanelPicker(const std::string& json) noexcept;
};
