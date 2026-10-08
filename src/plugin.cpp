#include "zml_plugin.h"
#include "zml_lua_service.h"
#include "patch.hpp"
#include "owned_lua.hpp"
#include "model_asset.hpp"
#include "asset_hashes.hpp"
#include <filesystem>
#include <fstream>
#include <iterator>
#include <Windows.h>
namespace {
const ZmlHost* hostApi{};
std::string helper,wheel,assets;
int provideAssets(void*,const char* path,ZmlSink sink,void* writer) noexcept {
    if(!path || !sink || std::string_view(path)!="assets" || assets.empty())return 0;
    sink(writer,assets.data(),assets.size());return 1;
}
int transformWheel(void*,const char* source,size_t size,ZmlSink sink,void* writer) noexcept {
    try {
        if(!source || !sink || size>768*1024)return 0;
        std::string output;
        if(!motorcycle::patchWheel(std::string_view(source,size),wheel,output)) {
            hostApi->log(hostApi->owner,"GeneralAbilityCtrl patch rejected");return 0;
        }
        sink(writer,output.data(),output.size());return 1;
    } catch(...) {return 0;}
}
int transform(void*,const char* source,size_t size,ZmlSink sink,void* writer) noexcept {
    try {
        if(!source || !sink || size>768*1024) return 0;
        std::string output;
        if(!motorcycle::patch(std::string_view(source,size),helper,output)) {
            hostApi->log(hostApi->owner,"BattleActionCtrl patch rejected");
            return 0;
        }
        sink(writer,output.data(),output.size());return 1;
    } catch(...) {return 0;}
}
int start(const ZmlHost* host) noexcept {
    try {
        if(!host || host->size!=sizeof(ZmlHost) || host->abi!=1 || !host->mod_directory ||
           !host->transform_lua || !host->log) return 0;
        auto runtime=GetModuleHandleW(L"ZMLRuntime.dll");
        auto get=runtime?reinterpret_cast<ZmlLuaServicesEntry>(GetProcAddress(runtime,"ZML_GetLuaServicesV1")):nullptr;
        auto services=get?get():nullptr;
        if(!services || services->abi!=1 || services->size!=sizeof(ZmlLuaServicesV1) || !services->register_source) {
            host->log(host->owner,"Motorcycle requires loader Mod source services");return 0;
        }
        auto root=std::filesystem::path(std::u8string(reinterpret_cast<const char8_t*>(host->mod_directory)));
        const auto path=root/L"motorcycle.lua";
        if(std::filesystem::file_size(path)>96*1024) return 0;
        std::ifstream stream(path,std::ios::binary);
        std::string bytes{std::istreambuf_iterator<char>(stream),{}};
        if(!stream || bytes.empty() || bytes.find('\0')!=bytes.npos) return 0;
        const std::string keyLine="local LEGACY_DISMOUNT=\"F7\" -- ZML_KEYBIND_DEFAULT";
        if(motorcycle::count(bytes,keyLine)!=1)return 0;
        std::string legacy="F7";
        if(host->state_directory) {
            auto state=std::filesystem::path(std::u8string(reinterpret_cast<const char8_t*>(host->state_directory)))/L"config.ini";
            std::error_code ec;auto size=std::filesystem::file_size(state,ec);
            if(!ec && size<=65536) {
                std::ifstream f(state,std::ios::binary);std::string line;
                while(std::getline(f,line)) {
                    if(!line.empty() && line.back()=='\r')line.pop_back();
                    if(line=="mount_key=F11")legacy="F11";
                }
            }
        }
        bytes.replace(bytes.find(keyLine),keyLine.size(),"local LEGACY_DISMOUNT=\""+legacy+"\"");
        auto mesh=motorcycle::readAsset(root/L"assets/sidra-bike.zmlmesh",512*1024);
        auto texture=motorcycle::readAsset(root/L"assets/Textures.png",64*1024);
        if(!motorcycle::validMesh(mesh)||motorcycle::sha256(mesh)!=motorcycle::meshHash||
           motorcycle::sha256(texture)!=motorcycle::textureHash)return 0;
        constexpr std::string_view token="-- ZML_ASSET_DATA";
        if(motorcycle::count(bytes,token)!=1)return 0;
        // Keep large licensed assets out of shared game-controller transforms.
        // The existing loader-owned module namespace enforces ownership and the same source cap.
        assets="return {mesh=\""+motorcycle::base64(mesh)+"\",texture=\""+motorcycle::base64(texture)+"\"}\n";
        if(assets.size()>768*1024)return 0;
        bytes.replace(bytes.find(token),token.size(),
            "local BIKE_ASSETS=assert(loadstring(LuaManagerInst:LoadLua(\"ZML/Mod/motorcycle/assets\"),\"@ZML/Mod/motorcycle/assets\"))()\n"
            "local BIKE_MESH_BASE64=BIKE_ASSETS.mesh\nlocal BIKE_TEXTURE_BASE64=BIKE_ASSETS.texture");
        auto readLua=[&](const wchar_t* filename) {
            auto path=root/filename;
            if(std::filesystem::file_size(path)>32*1024)throw std::runtime_error("native helper too large");
            std::ifstream file(path,std::ios::binary);
            std::string value{std::istreambuf_iterator<char>(file),{}};
            if(!file || value.empty() || value.find('\0')!=value.npos)throw std::runtime_error("invalid native helper");
            return value;
        };
        auto actions=readLua(L"native-actions.lua");
        constexpr std::string_view nativeToken="-- ZML_NATIVE_ACTIONS";
        if(motorcycle::count(bytes,nativeToken)!=1)return 0;
        bytes.replace(bytes.find(nativeToken),nativeToken.size(),actions);
        constexpr std::string_view flightToken="-- ZML_VEHICLE_FLIGHT";
        if(motorcycle::count(bytes,flightToken)!=1)return 0;
        bytes.replace(bytes.find(flightToken),flightToken.size(),readLua(L"flight.lua"));
        bytes=motorcycle::compactOwnedLua(bytes);
        wheel=readLua(L"wheel.lua");
        auto wheelIcon=motorcycle::readAsset(root/L"wheel-icon.png",16*1024);
        constexpr std::string_view wheelToken="-- ZML_WHEEL_ICON_DATA";
        if(motorcycle::count(wheel,wheelToken)!=1 || wheelIcon.substr(0,8)!=std::string("\x89PNG\r\n\x1a\n",8))return 0;
        wheel.replace(wheel.find(wheelToken),wheelToken.size(),"local WHEEL_ICON_BASE64=\""+motorcycle::base64(wheelIcon)+"\"");
        if(bytes.size()>744*1024 || wheel.size()>48*1024)return 0;
        helper=std::move(bytes);hostApi=host;
        if(!services->register_source(host->owner,provideAssets,nullptr)) {
            host->log(host->owner,"Motorcycle asset source registration rejected");return 0;
        }
        return host->transform_lua(host->owner,"UI/Panels/BattleAction/BattleActionCtrl",transform,nullptr) &&
            host->transform_lua(host->owner,"UI/Panels/GeneralAbility/GeneralAbilityCtrl",transformWheel,nullptr);
    } catch(...) {return 0;}
}
const ZmlPlugin plugin{sizeof(ZmlPlugin),1,"motorcycle",start};
}
extern "C" __declspec(dllexport) const ZmlPlugin* ZML_PluginV1(){return &plugin;}
