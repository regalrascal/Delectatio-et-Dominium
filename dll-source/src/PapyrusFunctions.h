#pragma once

namespace PapyrusFunctions {
    bool Register(RE::BSScript::IVirtualMachine* vm);
    void RegisterSlaveTatsNatives(RE::BSScript::IVirtualMachine* vm);   // SlaveTatsNative.cpp (S316)
}
