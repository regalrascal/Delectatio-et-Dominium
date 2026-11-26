#pragma once
// Preview -- DeDService's Phantasm client (tattoo-overhaul T2, rulings D-T4: Phantasm optional, client in DeDService).
// Shows a live picture of an actor in the combined panel. Phantasm (MIT, external/phantasm/Phantasm_API.h) is a soft
// dependency: with Phantasm.dll absent or too old there is no picture and nothing else changes (rule 16).
// One slot ("figure") for the panel. The page asks with ded_view {op: open|close|orbit|zoom}; the view's state goes back
// as dedView {view, state: shown|waiting|ended|absent, url, reason}. The view is closed before the panel goes away
// (Phantasm: drawing into a torn-down page has crashed the driver). ASCII only.

#include <cstdint>
#include <mutex>
#include <string>
#include <vector>

namespace DeD
{
	class Preview
	{
	public:
		static Preview& GetSingleton();

		void Init();              // kDataLoaded: resolve Phantasm, register client "ded"
		bool Available() const;   // Phantasm present and the client registered

		void OnPage(const std::string& a_payload);   // ded_view from the panel page (game thread)
		void CloseAll(const char* a_why);            // before the panel hides, and when it has closed
		void Refresh(std::uint32_t a_formId);        // the actor's look changed (0 = whatever the view shows)
		void OnGameLoad();                           // views end themselves on a load; forget ours
		// S331: take items off (a_on false) or put them back on (true) AT ONCE, menu open or not, then rebuild the
		// actor's 3D through Phantasm. Papyrus UnequipItem waits in the equip queue, which does not run while the
		// panel pauses the game (REV-198 test: armour stayed on in the picture, flashed off when the menu closed).
		void Dress(std::uint32_t a_actor, std::vector<std::uint32_t> a_items, bool a_on);

		static void OnEvent(const void* a_event, void* a_user);   // Phantasm's game-thread event (a PHANTASM_API::Event)

	private:
		void Send(const std::string& a_json);

		mutable std::mutex m_mx;
		const void*        m_api = nullptr;   // const PHANTASM_API::Interface1*
		std::uint32_t      m_client = 0;
		std::uint32_t      m_view = 0;
		std::uint32_t      m_actor = 0;
	};
}
