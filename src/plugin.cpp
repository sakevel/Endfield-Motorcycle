#include "zml_plugin.h"
#include "patch.hpp"
#include "model_asset.hpp"
#include "asset_hashes.hpp"
#include <filesystem>
#include <fstream>
#include <iterator>
namespace {
const ZmlHost* hostApi{};
std::string helper;
int transform(void*,const char* source,size_t size,ZmlSink sink,void* writer) noexcept {
    try {
        if(!source || !sink || size>768*1024) return 0;
        std::string output;
        if(!motorcycle::patch(std::string_view(source,size),helper,output)) {
            hostApi->log(hostApi->owner,"BattleActionCtrl contract rejected/already modified; native source retained");
            return 0;
        }
        sink(writer,output.data(),output.size());return 1;
    } catch(...) {return 0;}
}
int start(const ZmlHost* host) noexcept {
    try {
        if(!host || host->size!=sizeof(ZmlHost) || host->abi!=1 || !host->mod_directory ||
           !host->transform_lua || !host->log) return 0;
        auto root=std::filesystem::path(std::u8string(reinterpret_cast<const char8_t*>(host->mod_directory)));
        const auto path=root/L"motorcycle.lua";
        if(std::filesystem::file_size(path)>96*1024) return 0;
        std::ifstream stream(path,std::ios::binary);
        std::string bytes{std::istreambuf_iterator<char>(stream),{}};
        if(!stream || bytes.empty() || bytes.find('\0')!=bytes.npos) return 0;
        auto mesh=motorcycle::readAsset(root/L"assets/sidra-bike.zmlmesh",512*1024);
        auto texture=motorcycle::readAsset(root/L"assets/Textures.png",64*1024);
        if(!motorcycle::validMesh(mesh)||motorcycle::sha256(mesh)!=motorcycle::meshHash||
           motorcycle::sha256(texture)!=motorcycle::textureHash)return 0;
        constexpr std::string_view token="-- ZML_ASSET_DATA";
        if(motorcycle::count(bytes,token)!=1)return 0;
        bytes.replace(bytes.find(token),token.size(),"local BIKE_MESH_BASE64=\""+motorcycle::base64(mesh)+"\"\nlocal BIKE_TEXTURE_BASE64=\""+motorcycle::base64(texture)+"\"");
        if(bytes.size()>720*1024)return 0;
        helper=std::move(bytes);hostApi=host;
        return host->transform_lua(host->owner,"UI/Panels/BattleAction/BattleActionCtrl",transform,nullptr);
    } catch(...) {return 0;}
}
const ZmlPlugin plugin{sizeof(ZmlPlugin),1,"motorcycle",start};
}
extern "C" __declspec(dllexport) const ZmlPlugin* ZML_PluginV1(){return &plugin;}
