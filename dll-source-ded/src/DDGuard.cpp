#include "PCH.h"
#include "DDGuard.h"

#include <Windows.h>
#include <psapi.h>

namespace DeD
{
	// ------------------------------------------------------------------
	// Stack attribution (the SNEquipTrap technique): CaptureStackBackTrace
	// walks the CURRENT thread's stack; TESEquipEvent dispatches synchronously
	// from inside the engine equip path on the initiating caller's thread, so
	// the initiator's frames are right above the engine dispatch frames.
	// ------------------------------------------------------------------

	bool DDGuard::DeviousDevicesOnStack()
	{
		constexpr std::size_t kMaxFrames = 64;
		void* frames[kMaxFrames] = {};
		const auto count = CaptureStackBackTrace(0, kMaxFrames, frames, nullptr);

		for (std::size_t i = 0; i < count; ++i) {
			const auto addr = reinterpret_cast<std::uintptr_t>(frames[i]);

			HMODULE module = nullptr;
			if (!GetModuleHandleExW(
					GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS | GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT,
					reinterpret_cast<LPCWSTR>(addr), &module)) {
				continue;
			}

			wchar_t wpath[MAX_PATH]{};
			GetModuleFileNameW(module, wpath, MAX_PATH);
			const auto name = std::filesystem::path(wpath).filename().string();

			// Case-insensitive module match (the ISSUE-6 stacks: DeviousDevices.dll).
			if (_stricmp(name.c_str(), "DeviousDevices.dll") == 0) {
				return true;
			}
		}
		return false;
	}

	bool DDGuard::DDNGPresent()
	{
		return GetSingleton().m_ddng;
	}

	void DDGuard::SetDDNGPresent()
	{
		GetSingleton().m_ddng = true;
	}

	bool DDGuard::OnUnequip(RE::Actor* a_actor, RE::FormID a_baseFormID)
	{
		if (!m_ddng || !a_actor) {
			return false;
		}
		// Armor only — weapons/torch/quest-item noise passes through silently.
		const auto* base = RE::TESForm::LookupByID(a_baseFormID);
		if (!base || !base->Is(RE::FormType::Armor)) {
			return false;
		}
		if (!DeviousDevicesOnStack()) {
			return false;
		}
		// Hit: the Papyrus handler does the window/de device/retry logic —
		// this DLL stays attribution-only (ruling of record #3).
		return true;
	}
}