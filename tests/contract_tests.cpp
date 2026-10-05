#include "zml_plugin.h"
#include "patch.hpp"
#include "model_asset.hpp"
#include "asset_hashes.hpp"
#include <Windows.h>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <iterator>
#include <stdexcept>
namespace {
ZmlLuaTransform registered{};
void* data{};
int registrations{},sinks{};
std::string output;
void expect(bool value,const char* name){if(!value)throw std::runtime_error(name);}
void log(void*,const char*){}
int registerLua(void*,const char* path,ZmlLuaTransform cb,void* userdata){
    expect(std::string_view(path)=="UI/Panels/BattleAction/BattleActionCtrl","canonical module");
    ++registrations;registered=cb;data=userdata;return 1;
}
void sink(void*,const char* bytes,size_t count){++sinks;output.assign(bytes,count);}
std::string read(const std::filesystem::path& path){
    std::ifstream file(path,std::ios::binary);expect(static_cast<bool>(file),"fixture input");
    return {std::istreambuf_iterator<char>(file),{}};
}
constexpr std::string_view fixture=R"(local uiCtrl = require_ex('UI/Panels/Base/UICtrl')
BattleActionCtrl = HL.Class('BattleActionCtrl', uiCtrl.UICtrl)
BattleActionCtrl.OnShow = HL.Override() << function(self)
    nativeShow(self)
end
BattleActionCtrl.OnHide = HL.Override() << function(self)
    nativeHide(self)
end
BattleActionCtrl.OnClose = HL.Override() << function(self)
    nativeClose(self)
end
HL.Commit(BattleActionCtrl)
return BattleActionCtrl
)";
}
int main(int argc,char** argv){
    try {
        expect(argc==2 || argc==4,"usage: ContractTests <DLL> [current-client.lua patched-output.lua]");
        auto dll=std::filesystem::absolute(argv[1]);
        auto module=LoadLibraryW(dll.c_str());expect(module!=nullptr,"actual DLL load");
        auto entry=reinterpret_cast<ZmlPluginEntry>(GetProcAddress(module,"ZML_PluginV1"));expect(entry!=nullptr,"ABI export");
        auto plugin=entry();expect(plugin && plugin->size==sizeof(ZmlPlugin) && plugin->abi==1 && std::string_view(plugin->id)=="motorcycle","plugin identity");
        auto directory=dll.parent_path().u8string();
        ZmlHost host{sizeof(ZmlHost),1,nullptr,reinterpret_cast<const char*>(directory.c_str()),"",log,registerLua};
        const auto asset=read(dll.parent_path()/L"assets/sidra-bike.zmlmesh");
        expect(motorcycle::validMesh(asset)&&motorcycle::sha256(asset)==motorcycle::meshHash,"actual asset integrity");
        for(auto n:{0u,8u,12u,80u,1000u})expect(!motorcycle::validMesh(std::string_view(asset).substr(0,n)),"truncated asset rejected");
        expect(!motorcycle::validMesh(asset+"x"),"trailing bytes rejected");
        auto bad=asset;bad[12]=char(9);expect(!motorcycle::validMesh(bad),"invalid part role rejected");
        bad=asset;memset(bad.data()+16,0,4);expect(!motorcycle::validMesh(bad),"zero vertices rejected");
        bad=asset;float nan=std::numeric_limits<float>::quiet_NaN();memcpy(bad.data()+28,&nan,4);expect(!motorcycle::validMesh(bad),"NaN pivot rejected");
        uint32_t nv{};memcpy(&nv,asset.data()+16,4);bad=asset;memset(bad.data()+96+size_t(nv)*12,255,2);expect(!motorcycle::validMesh(bad),"index out of bounds rejected");
        auto missingHost=host;missingHost.mod_directory="Z:/nonexistent-zml-test-directory";
        expect(plugin->start(&missingHost)==0&&registrations==0,"missing runtime assets refuse before registration");
        expect(plugin->start(nullptr)==0,"reject null host");auto wrong=host;wrong.abi=2;expect(plugin->start(&wrong)==0,"reject ABI drift");
        expect(plugin->start(&host)==1 && registrations==1 && registered,"actual plugin registration");
        auto temp=dll.parent_path().parent_path().parent_path()/L"asset-test-fixture";
        expect(!std::filesystem::exists(temp),"exclusive asset fixture");
        std::filesystem::create_directories(temp/L"assets");
        std::filesystem::copy_file(dll.parent_path()/L"motorcycle.lua",temp/L"motorcycle.lua");
        std::filesystem::copy_file(dll.parent_path()/L"assets/Textures.png",temp/L"assets/Textures.png");
        bad=asset;bad[96]^=1;expect(motorcycle::validMesh(bad),"structurally valid corrupted mesh fixture");
        {std::ofstream file(temp/L"assets/sidra-bike.zmlmesh",std::ios::binary);file.write(bad.data(),bad.size());}
        auto dir=temp.u8string();auto corruptedHost=host;corruptedHost.mod_directory=reinterpret_cast<const char*>(dir.c_str());
        expect(plugin->start(&corruptedHost)==0&&registrations==1,"hash mismatch rejects before registration");
        std::filesystem::remove(temp/L"assets/sidra-bike.zmlmesh");
        std::filesystem::remove(temp/L"assets/Textures.png");std::filesystem::remove(temp/L"assets");
        std::filesystem::remove(temp/L"motorcycle.lua");std::filesystem::remove(temp);
        const std::string source(fixture);
        sinks=0;expect(registered(data,source.data(),source.size(),sink,nullptr)==1 && sinks==1,"one atomic sink");
        expect(output.find("local ZMLMotorcycle")<output.find("BattleActionCtrl.OnShow"),"helper lexical scope");
        expect(output.size()<=768*1024&&output.find("local BIKE_MESH_BASE64=")!=output.npos,"assets fit unchanged public source cap");
        expect(output.find("nativeShow(self)")!=output.npos && output.find("nativeHide(self)")!=output.npos && output.find("nativeClose(self)")!=output.npos,"preserve native lifecycle");
        std::string untouched;
        expect(!motorcycle::patch(output,"return {}",untouched) && untouched.empty(),"idempotent contract");
        for (auto anchor : {"BattleActionCtrl.OnShow = HL.Override() << function(self)","BattleActionCtrl.OnHide = HL.Override() << function(self)","BattleActionCtrl.OnClose = HL.Override() << function(self)","HL.Commit(BattleActionCtrl)"}) {
            auto missing=source;missing.erase(missing.find(anchor),strlen(anchor));
            sinks=0;expect(registered(data,missing.data(),missing.size(),sink,nullptr)==0 && sinks==0,"missing anchor atomic refusal");
            auto duplicate=source+"\n"+anchor;
            sinks=0;expect(registered(data,duplicate.data(),duplicate.size(),sink,nullptr)==0 && sinks==0,"duplicate anchor atomic refusal");
        }
        sinks=0;expect(registered(data,nullptr,0,sink,nullptr)==0 && sinks==0,"null source");
        auto binary=source;binary[1]='\0';expect(registered(data,binary.data(),binary.size(),sink,nullptr)==0,"reject binary");
        if(argc==4){
            auto real=read(argv[2]);sinks=0;expect(registered(data,real.data(),real.size(),sink,nullptr)==1 && sinks==1,"actual current client patch");
            expect(!std::filesystem::exists(argv[3]),"do not overwrite research outputs");
            std::ofstream file(argv[3],std::ios::binary);file.write(output.data(),output.size());file.close();expect(static_cast<bool>(file),"write research output");
        }
        // The callback/host live for the process. Do not unload a registered plugin mid-test.
        std::cout<<"PASS: actual ABI1 DLL, lifecycle contract, atomic failure, lexical scope\n";
    } catch(const std::exception& e){std::cerr<<e.what()<<'\n';return 1;}
}
