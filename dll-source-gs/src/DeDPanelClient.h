#pragma once

// Bridge between Papyrus / the game and the GS pose-grid view. Since Magelight workstream
// Phase 1 (docs/workstreams/magelight-ui.md 6c) the view is hosted by DeDService (module
// "gs-poses", view "grid"); this DLL only drives it through the DeDUI C ABI (DeDUI_API.h).
namespace DeDPanelClient {
    // kPostLoad: resolve the DeDUI API (DeDService.dll); kept for the old call site.
    void RequestAPI() noexcept;
    // kDataLoaded: nothing to create (DeDService owns the view); logs readiness.
    void CreatePoseView() noexcept;
    // S320: set the GS section's panel handler on every game load (kPostLoadGame / kNewGame).
    void PanelInit() noexcept;

    // True when DeDService hosts the pose grid (Magelight acquired, module installed).
    bool IsAvailable() noexcept;
    // True while the grid is on screen (used by the Esc/Tab input sink).
    bool IsMenuOpen() noexcept;

    // Show the grid + pause the game (called from the SNAnimGSUI.OpenPoseGrid native).
    void OpenPoseGrid() noexcept;
    // Hide the grid without a selection (script-initiated).
    void ClosePoseGrid() noexcept;
    // Esc / Tab / the player leaving the view -> cancel: closes and reports an empty pick.
    void CancelMenu() noexcept;

    // Page pick (window.gsanim_chose). value = "GS123" or "" on cancel.
    void OnJSChoice(const char* value) noexcept;

    // After the PLAYER picks a pose we watch for movement keys (WASD / jump). The input sink
    // calls these: while IsWatchingMovement() is true, any movement key fires the
    // "SNAnimGS_StopPose" mod event (-> controller forces IdleForceDefaultState) since GS poses
    // are designed to hold in place. Cleared once stopped or when the grid reopens.
    bool IsWatchingMovement() noexcept;
    void StopPoseFromMovement() noexcept;
}
