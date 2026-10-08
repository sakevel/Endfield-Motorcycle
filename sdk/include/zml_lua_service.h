#pragma once
#include "zml_plugin.h"
// Public optional Loader extension; ABI1 ZmlHost stays unchanged.
// Register during start(), for ZML/Mod/<manifest id>/<relative path> only.
typedef int (*ZmlLuaSource)(void* userdata, const char* relative_path, ZmlSink sink, void* writer);
typedef struct ZmlLuaServicesV1 {
    uint32_t size, abi;
    int (*register_source)(void* host_owner, ZmlLuaSource provider, void* userdata);
} ZmlLuaServicesV1;
typedef const ZmlLuaServicesV1* (*ZmlLuaServicesEntry)(void);
