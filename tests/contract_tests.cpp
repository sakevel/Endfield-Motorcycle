#include "zml_plugin.h"
#include "patch.hpp"
#include "owned_lua.hpp"
#include "model_asset.hpp"
#include "asset_hashes.hpp"
#include <Windows.h>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <iterator>
#include <stdexcept>
namespace {
ZmlLuaTransform registered{},wheelRegistered{};
void* data{};
int registrations{},sinks{};
std::string output;
void expect(bool value,const char* name){if(!value)throw std::runtime_error(name);}
void log(void*,const char*){}
int registerLua(void*,const char* path,ZmlLuaTransform cb,void* userdata){
    auto name=std::string_view(path);
    expect(name=="UI/Panels/BattleAction/BattleActionCtrl" || name=="UI/Panels/GeneralAbility/GeneralAbilityCtrl","canonical module");
    ++registrations;if(name=="UI/Panels/BattleAction/BattleActionCtrl")registered=cb;else wheelRegistered=cb;
    data=userdata;return 1;
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
        expect(motorcycle::compactOwnedLua("local x='--ok' --gone\nlocal y=[=[--preserve\n]=] --tail\n") ==
            "local x='--ok'  \nlocal y=[=[--preserve\n]=]  \n", "compact preserves quoted/long strings and lines");
        expect(motorcycle::compactOwnedLua("return 1--[=[hidden\ntext]=]+2") == "return 1 \n+2", "compact separates long comment tokens");
        expect(argc==2 || argc==4 || argc==6,"usage: ContractTests <DLL> [battle.lua battle-output.lua [ability.lua ability-output.lua]]");
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
        expect(plugin->start(&host)==1 && registrations==2 && registered && wheelRegistered,"actual plugin registration");
        auto temp=dll.parent_path().parent_path().parent_path()/L"asset-test-fixture";
        expect(!std::filesystem::exists(temp),"exclusive asset fixture");
        std::filesystem::create_directories(temp/L"assets");
        std::filesystem::copy_file(dll.parent_path()/L"motorcycle.lua",temp/L"motorcycle.lua");
        std::filesystem::copy_file(dll.parent_path()/L"assets/Textures.png",temp/L"assets/Textures.png");
        bad=asset;bad[96]^=1;expect(motorcycle::validMesh(bad),"structurally valid corrupted mesh fixture");
        {std::ofstream file(temp/L"assets/sidra-bike.zmlmesh",std::ios::binary);file.write(bad.data(),bad.size());}
        auto dir=temp.u8string();auto corruptedHost=host;corruptedHost.mod_directory=reinterpret_cast<const char*>(dir.c_str());
        expect(plugin->start(&corruptedHost)==0&&registrations==2,"hash mismatch rejects before registration");
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
        if(argc>=4){
            auto real=read(argv[2]);sinks=0;expect(registered(data,real.data(),real.size(),sink,nullptr)==1 && sinks==1,"actual current client patch");
            expect(!std::filesystem::exists(argv[3]),"do not overwrite research outputs");
            std::ofstream file(argv[3],std::ios::binary);file.write(output.data(),output.size());file.close();expect(static_cast<bool>(file),"write research output");
        }
        const std::string wheelSource=R"(GeneralAbilityCtrl = HL.Class('GeneralAbilityCtrl', uiCtrl.UICtrl)
GeneralAbilityCtrl._UpdateNormalAbilityData = HL.Method() << function(self)
    for index=1,5 do
        self.m_abilityDataList[index].index = index)" "  \n" R"(    end

end
GeneralAbilityCtrl._UpdateTempAbilityData = HL.Method() << function(self)
end
GeneralAbilityCtrl._UpdateSelectorCellInfo = HL.Method(HL.Any, HL.Number) << function(self, cell, luaIndex)
end
GeneralAbilityCtrl._OnSelectByType = HL.Method(HL.Number) << function(self, type)
end
GeneralAbilityCtrl._SetSelectedType = HL.Method(HL.Number, HL.Boolean) << function(self, type, needSave)
end
GeneralAbilityCtrl._RefreshMidHoverInfo = HL.Method(HL.Number) << function(self, type)
end
GeneralAbilityCtrl._RefreshWheelShownState = HL.Method(HL.Boolean) << function(self, isShown)
end
GeneralAbilityCtrl.OnClose = HL.Override() << function(self)
end
if data ~= nil and data.isForbidSelect == false then
end
HL.Commit(GeneralAbilityCtrl)
)";
        sinks=0;expect(wheelRegistered(data,wheelSource.data(),wheelSource.size(),sink,nullptr)==1 && sinks==1,"atomic native wheel transform");
        expect(output.find("local WHEEL_ICON_BASE64=")!=output.npos && output.find("ZMLBikeWheel.register(self)")!=output.npos,"wheel packaged icon and registration");
        expect(!motorcycle::patchWheel(output,"return {}",untouched),"wheel idempotence");
        auto mixed=wheelSource;
        for(size_t p=0;(p=mixed.find('\n',p))!=mixed.npos;p+=2)mixed.insert(p,"\r");
        auto comment=mixed.find("index  \r\n");mixed.erase(comment+7,1);
        sinks=0;expect(wheelRegistered(data,mixed.data(),mixed.size(),sink,nullptr)==1 && sinks==1,"mixed LF/CRLF native wheel source");
        for(auto anchor:{"HL.Commit(GeneralAbilityCtrl)","GeneralAbilityCtrl._OnSelectByType = HL.Method(HL.Number) << function(self, type)",
            "GeneralAbilityCtrl.OnClose = HL.Override() << function(self)","if data ~= nil and data.isForbidSelect == false then",
            "        self.m_abilityDataList[index].index = index  \n    end\n\nend"}) {
            auto missing=wheelSource;missing.erase(missing.find(anchor),strlen(anchor));
            sinks=0;expect(wheelRegistered(data,missing.data(),missing.size(),sink,nullptr)==0 && sinks==0,"wheel missing anchor atomic refusal");
            auto duplicate=wheelSource+"\n"+anchor;
            expect(wheelRegistered(data,duplicate.data(),duplicate.size(),sink,nullptr)==0 && sinks==0,"wheel duplicate anchor atomic refusal");
        }
        if(argc==6){
            auto real=read(argv[4]);sinks=0;expect(wheelRegistered(data,real.data(),real.size(),sink,nullptr)==1 && sinks==1,"actual current native R wheel patch");
            expect(!std::filesystem::exists(argv[5]),"exclusive wheel output");
            std::ofstream file(argv[5],std::ios::binary);file.write(output.data(),output.size());file.close();expect(static_cast<bool>(file),"write wheel output");
        }
        // Retain registered plugin for test lifetime
        std::cout<<"PASS: actual ABI1 DLL, lifecycle contract, atomic failure, lexical scope\n";
    } catch(const std::exception& e){std::cerr<<e.what()<<'\n';return 1;}
}
