#include "PCH.h"
#include "ServiceState.h"

#include <algorithm>
#include <cctype>
#include <cstring>

namespace DeD
{
	// ---------- byte-buffer helpers ----------
	static void PutU32(std::vector<std::uint8_t>& b, std::uint32_t v)
	{
		b.push_back(static_cast<std::uint8_t>(v));
		b.push_back(static_cast<std::uint8_t>(v >> 8));
		b.push_back(static_cast<std::uint8_t>(v >> 16));
		b.push_back(static_cast<std::uint8_t>(v >> 24));
	}
	static void PutI64(std::vector<std::uint8_t>& b, std::int64_t v)
	{
		std::uint64_t u = static_cast<std::uint64_t>(v);
		for (int i = 0; i < 8; ++i) b.push_back(static_cast<std::uint8_t>(u >> (8 * i)));
	}
	static void PutF64(std::vector<std::uint8_t>& b, double v)
	{
		static_assert(sizeof(double) == 8);
		std::uint64_t u;
		std::memcpy(&u, &v, 8);
		for (int i = 0; i < 8; ++i) b.push_back(static_cast<std::uint8_t>(u >> (8 * i)));
	}
	static void PutStr(std::vector<std::uint8_t>& b, const std::string& s)
	{
		PutU32(b, static_cast<std::uint32_t>(s.size()));
		b.insert(b.end(), s.begin(), s.end());
	}

	static bool GetU32(const std::uint8_t*& p, const std::uint8_t* end, std::uint32_t& v)
	{
		if (end - p < 4) return false;
		v = p[0] | (p[1] << 8) | (p[2] << 16) | (std::uint32_t{ p[3] } << 24);
		p += 4;
		return true;
	}
	static bool GetI64(const std::uint8_t*& p, const std::uint8_t* end, std::int64_t& v)
	{
		if (end - p < 8) return false;
		std::uint64_t u = 0;
		for (int i = 0; i < 8; ++i) u |= static_cast<std::uint64_t>(p[i]) << (8 * i);
		p += 8;
		v = static_cast<std::int64_t>(u);
		return true;
	}
	static bool GetF64(const std::uint8_t*& p, const std::uint8_t* end, double& v)
	{
		if (end - p < 8) return false;
		std::uint64_t u = 0;
		for (int i = 0; i < 8; ++i) u |= static_cast<std::uint64_t>(p[i]) << (8 * i);
		std::memcpy(&v, &u, 8);
		p += 8;
		return true;
	}
	static bool GetStr(const std::uint8_t*& p, const std::uint8_t* end, std::string& s)
	{
		std::uint32_t len = 0;
		if (!GetU32(p, end, len) || static_cast<std::size_t>(end - p) < len) return false;
		s.assign(reinterpret_cast<const char*>(p), len);
		p += len;
		return true;
	}

	void SerializeValue(std::vector<std::uint8_t>& a_buf, const StateValue& a_v)
	{
		a_buf.push_back(static_cast<std::uint8_t>(a_v.type));
		switch (a_v.type) {
		case ValueType::Int:     PutI64(a_buf, a_v.i); break;
		case ValueType::Float:   PutF64(a_buf, a_v.f); break;
		case ValueType::String:  PutStr(a_buf, a_v.s); break;
		case ValueType::Bool:    a_buf.push_back(a_v.b ? 1 : 0); break;
		case ValueType::FormID:  PutU32(a_buf, a_v.form); break;
		}
	}

	bool DeserializeValue(const std::uint8_t*& a_p, const std::uint8_t* a_end, StateValue& a_v)
	{
		if (a_p >= a_end) return false;
		a_v.type = static_cast<ValueType>(*a_p++);
		std::uint8_t b8 = 0;
		switch (a_v.type) {
		case ValueType::Int:    return GetI64(a_p, a_end, a_v.i);
		case ValueType::Float:  return GetF64(a_p, a_end, a_v.f);
		case ValueType::String: return GetStr(a_p, a_end, a_v.s);
		case ValueType::Bool:
			if (a_p >= a_end) return false;
			b8 = *a_p++;
			a_v.b = (b8 != 0);
			return true;
		case ValueType::FormID: return GetU32(a_p, a_end, a_v.form);
		}
		return false;
	}

	bool ParseDefault(ValueType a_type, const std::string& a_serialized, StateValue& a_out)
	{
		a_out = StateValue{};
		a_out.type = a_type;
		try {
			switch (a_type) {
			case ValueType::Int:
				a_out.i = a_serialized.empty() ? 0 : std::stoll(a_serialized);
				return true;
			case ValueType::Float:
				a_out.f = a_serialized.empty() ? 0.0 : std::stod(a_serialized);
				return true;
			case ValueType::Bool: {
				std::string t = a_serialized;
				std::transform(t.begin(), t.end(), t.begin(),
					[](unsigned char c) { return static_cast<char>(std::tolower(c)); });
				a_out.b = (t == "true" || t == "1" || t == "yes");
				return true;
			}
			case ValueType::String:
				a_out.s = a_serialized;
				return true;
			case ValueType::FormID: {
				std::uint64_t raw = a_serialized.empty() ? 0 : std::stoull(a_serialized, nullptr, 0);
				a_out.form = static_cast<std::uint32_t>(raw);
				return true;
			}
			}
		} catch (const std::exception&) {
			return false;
		}
		return false;
	}

	// ---------- registration / presence (section 1.1) ----------
	bool ServiceState::Register(const std::string& a_moduleID, const std::string& a_key,
		ValueType a_type, bool a_actorKeyed, const std::string& a_defaultSerialized)
	{
		std::lock_guard lock(m_mutex);
		if (a_moduleID.empty() || a_key.empty() || a_key.find('.') != std::string::npos) return false;
		const std::string dotted = a_moduleID + "." + a_key;
		if (m_registrations.count(dotted) != 0) return false; // duplicate registration
		Registration reg;
		reg.moduleID = a_moduleID;
		reg.key = a_key;
		reg.dotted = dotted;
		reg.type = a_type;
		reg.actorKeyed = a_actorKeyed;
		if (!a_defaultSerialized.empty()) {
			if (!ParseDefault(a_type, a_defaultSerialized, reg.defaultValue)) return false;
			reg.hasDefault = true;
		}
		m_registrations.emplace(dotted, std::move(reg));
		m_activeModules.insert(a_moduleID);
		// Cosave adoption: activate pending (dormant) rows for this key.
		for (auto pit = m_pending.begin(); pit != m_pending.end();) {
			if (pit->dotted == dotted) {
				m_values[dotted][pit->ownerFormID] = pit->value;
				pit = m_pending.erase(pit);
			} else {
				++pit;
			}
		}
		return true;
	}

	bool ServiceState::RemoveState(const std::string& a_moduleID, const std::string& a_key)
	{
		std::lock_guard lock(m_mutex);
		const std::string dotted = a_moduleID + "." + a_key;
		if (m_registrations.erase(dotted) == 0) return false;
		m_values.erase(dotted);
		return true;
	}

	bool ServiceState::ModuleActive(const std::string& a_moduleID) const
	{
		std::lock_guard lock(m_mutex);
		return m_activeModules.count(a_moduleID) != 0;
	}

	// ---------- state access (section 1.2) ----------
	const Registration* ServiceState::FindRegistration(const std::string& a_dotted) const
	{
		std::lock_guard lock(m_mutex);
		auto it = m_registrations.find(a_dotted);
		return it == m_registrations.end() ? nullptr : &it->second;
	}

	bool ServiceState::Set(const std::string& a_dotted, std::uint32_t a_ownerFormID, const StateValue& a_value)
	{
		std::lock_guard lock(m_mutex);
		auto it = m_registrations.find(a_dotted);
		if (it == m_registrations.end() || it->second.type != a_value.type) return false;
		if (!it->second.actorKeyed) a_ownerFormID = 0;
		m_values[a_dotted][a_ownerFormID] = a_value;
		return true;
	}

	bool ServiceState::Get(const std::string& a_dotted, std::uint32_t a_ownerFormID, StateValue& a_out) const
	{
		std::lock_guard lock(m_mutex);
		auto rit = m_registrations.find(a_dotted);
		if (rit == m_registrations.end()) return false;
		if (!rit->second.actorKeyed) a_ownerFormID = 0;
		auto vit = m_values.find(a_dotted);
		if (vit == m_values.end()) return false;
		auto oit = vit->second.find(a_ownerFormID);
		if (oit == vit->second.end()) return false;
		a_out = oit->second;
		return true;
	}

	bool ServiceState::GetAnyTrue(const std::string& a_dotted) const
	{
		//  (ambient-chain diagnosis, first silent link): rule predicates
		// armed with a None owner read owner-formID 0, but actor-keyed keys store
		// their rows under the actor's formID -- a plain Get(dotted, 0) can never
		// see the write and the rule never fires. This read is the fix's read
		// shape: TRUE when any owner's row is a Bool TRUE (owner-0 row for
		// non-actor-keyed keys).
		std::lock_guard lock(m_mutex);
		auto rit = m_registrations.find(a_dotted);
		if (rit == m_registrations.end()) return false;
		auto vit = m_values.find(a_dotted);
		if (vit == m_values.end()) return false;
		if (!rit->second.actorKeyed) {
			auto oit = vit->second.find(0);
			return oit != vit->second.end() && oit->second.type == ValueType::Bool && oit->second.b;
		}
		for (const auto& [owner, v] : vit->second) {
			if (v.type == ValueType::Bool && v.b) return true;
		}
		return false;
	}

	bool ServiceState::HasState(const std::string& a_dotted, std::uint32_t a_ownerFormID) const
	{
		StateValue v;
		return Get(a_dotted, a_ownerFormID, v);
	}

	bool ServiceState::ClearActorState(std::uint32_t a_actorFormID, const std::string& a_moduleID)
	{
		std::lock_guard lock(m_mutex);
		bool any = false;
		const std::string prefix = a_moduleID + ".";
		for (auto& [dotted, owners] : m_values) {
			if (dotted.rfind(prefix, 0) != 0) continue;
			if (owners.erase(a_actorFormID) > 0) any = true;
		}
		return any;
	}

	void ServiceState::ClearValue(const std::string& a_moduleID, const std::string& a_key, std::uint32_t a_ownerFormID)
	{
		std::lock_guard lock(m_mutex);
		auto vit = m_values.find(a_moduleID + "." + a_key);
		if (vit != m_values.end()) vit->second.erase(a_ownerFormID);
	}

	// ---------- cosave (section 0.3 adoptions: 4-char tag + version int;
	// migration hook is a named logged stage; reject-with-log on mismatch) ----------
	std::vector<std::uint8_t> ServiceState::Save()
	{
		std::lock_guard lock(m_mutex);
		std::vector<std::uint8_t> buf;
		PutU32(buf, static_cast<std::uint32_t>(m_activeModules.size()));
		for (const auto& m : m_activeModules) PutStr(buf, m);
		std::size_t rows = m_pending.size();
		for (const auto& [dotted, owners] : m_values) rows += owners.size();
		PutU32(buf, static_cast<std::uint32_t>(rows));
		for (const auto& [dotted, owners] : m_values) {
			for (const auto& [owner, v] : owners) {
				PutStr(buf, dotted);
				PutU32(buf, owner);
				SerializeValue(buf, v);
			}
		}
		for (const auto& p : m_pending) {
			PutStr(buf, p.dotted);
			PutU32(buf, p.ownerFormID);
			SerializeValue(buf, p.value);
		}
		return buf;
	}

	bool ServiceState::Load(SKSE::SerializationInterface* a_intfc, std::uint32_t a_length, const std::uint8_t* a_data)
	{
		std::lock_guard lock(m_mutex);
		m_registrations.clear();
		m_values.clear();
		m_activeModules.clear();
		m_pending.clear();

		const std::uint8_t* p = a_data;
		const std::uint8_t* end = a_data + a_length;
		std::uint32_t modCount = 0, rowCount = 0;
		if (!GetU32(p, end, modCount)) return false;
		for (std::uint32_t i = 0; i < modCount; ++i) {
			std::string m;
			if (!GetStr(p, end, m)) return false;
			m_activeModules.insert(m);
		}
		if (!GetU32(p, end, rowCount)) return false;
		for (std::uint32_t i = 0; i < rowCount; ++i) {
			std::string dotted;
			std::uint32_t owner = 0;
			StateValue v;
			if (!GetStr(p, end, dotted) || !GetU32(p, end, owner) || !DeserializeValue(p, end, v)) return false;
			// FormIDs are save-relative: resolve through SKSE, drop unresolvable.
			if (owner != 0) {
				RE::FormID resolved = owner;
				if (!a_intfc || !a_intfc->ResolveFormID(owner, resolved)) resolved = 0;
				owner = resolved;
			}
			if (v.type == ValueType::FormID && v.form != 0) {
				RE::FormID resolved = v.form;
				if (!a_intfc || !a_intfc->ResolveFormID(v.form, resolved)) resolved = 0;
				v.form = resolved;
			}
			const auto dot = dotted.find('.');
			if (dot == std::string::npos) continue;
			const std::string mod = dotted.substr(0, dot);
			const std::string key = dotted.substr(dot + 1);
			if (m_activeModules.count(mod) == 0) {
				m_pending.push_back(PendingRow{ mod, key, dotted, owner, v }); // dormant retention
			} else {
				m_values[dotted][owner] = v;
			}
		}
		return p == end;
	}

	void ServiceState::Revert()
	{
		std::lock_guard lock(m_mutex);
		m_registrations.clear();
		m_values.clear();
		m_activeModules.clear();
		m_pending.clear();
	}
}
