#include "PapyrusFunctions.h"
#include <SKSE/SKSE.h>
#include "DeDPanelClient.h"

// Must match Scriptname in SNAnimGSUI.psc.
static constexpr const char* kScriptName = "SNAnimGSUI";

static bool SNAnimGSUI_IsAvailable(RE::StaticFunctionTag*) {
    return DeDPanelClient::IsAvailable();
}

static void SNAnimGSUI_OpenPoseGrid(RE::StaticFunctionTag*) {
    DeDPanelClient::OpenPoseGrid();
}

static void SNAnimGSUI_ClosePoseGrid(RE::StaticFunctionTag*) {
    DeDPanelClient::ClosePoseGrid();
}

bool PapyrusFunctions::Register(RE::BSScript::IVirtualMachine* vm) {
    vm->RegisterFunction("IsAvailable",   kScriptName, SNAnimGSUI_IsAvailable);
    vm->RegisterFunction("OpenPoseGrid",  kScriptName, SNAnimGSUI_OpenPoseGrid);
    vm->RegisterFunction("ClosePoseGrid", kScriptName, SNAnimGSUI_ClosePoseGrid);
    SKSE::log::info("[SNAnimGS] Papyrus functions registered.");
    return true;
}
