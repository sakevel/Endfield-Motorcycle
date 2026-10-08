#include "zml_lua_service.h"
#include <Windows.h>
#include <set>
namespace {
ZmlLuaSource source{};
void* userdata{};
std::set<void*> owners;
int add(void* owner,ZmlLuaSource fn,void* data) {
    if(!fn || !owners.insert(owner).second)return 0;
    source=fn;userdata=data;return 1;
}
const ZmlLuaServicesV1 services{sizeof(ZmlLuaServicesV1),1,add};
}
extern "C" __declspec(dllexport) const ZmlLuaServicesV1* ZML_GetLuaServicesV1(){return &services;}
extern "C" __declspec(dllexport) ZmlLuaSource ZML_TestSource(void** data) {
    *data=userdata;return source;
}
