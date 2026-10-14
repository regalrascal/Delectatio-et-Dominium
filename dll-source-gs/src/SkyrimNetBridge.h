#pragma once

#include "SkyrimNet_PublicAPI.h"

//  (S1 pack-split): fallback bridge to SkyrimNet's native C++ API, carried from
// the Baka DLL (dll-source/src/SkyrimNetBridge.{h,cpp} + include/SkyrimNet_PublicAPI.h -
// the header ships here because this DLL never bridged SkyrimNet's C++ API before).
// Semantics differ from the Baka side by design (P2 single-owner pattern): this DLL
// registers SNGS_Pose ONLY when the Baka integration's esp is ABSENT from the load
// order (esp probe), so a GS-only install still gets the category def its moved pose
// YAMLs (Gunslicer-Poses pack) reference via customCategory: SNGS_Pose. When both mods
// are installed the Baka DLL is the unconditional owner; this fallback stays silent.
// Call Init() once, at SKSE kDataLoaded (the API doc requires resolution there).
namespace SkyrimNetBridge {
    void Init();
}