#pragma once
#include <string>
#include <string_view>
namespace motorcycle {
inline size_t count(std::string_view s, std::string_view needle) {
    size_t result=0, pos=0;
    while ((pos=s.find(needle,pos))!=s.npos) {++result;pos+=needle.size();}
    return result;
}
inline bool patch(std::string_view source, std::string_view helper, std::string& output) {
    constexpr std::string_view marker="-- ZML_MOTORCYCLE_V1";
    constexpr std::string_view show="BattleActionCtrl.OnShow = HL.Override() << function(self)";
    constexpr std::string_view hide="BattleActionCtrl.OnHide = HL.Override() << function(self)";
    constexpr std::string_view close="BattleActionCtrl.OnClose = HL.Override() << function(self)";
    constexpr std::string_view commit="HL.Commit(BattleActionCtrl)";
    if (source.empty() || source.find('\0')!=source.npos || helper.empty() ||
        helper.size()>744*1024 || helper.find('\0')!=helper.npos || count(source,marker) ||
        count(source,show)!=1 || count(source,hide)!=1 || count(source,close)!=1 || count(source,commit)!=1 ||
        count(source,"BattleActionCtrl = HL.Class('BattleActionCtrl', uiCtrl.UICtrl)")!=1) return false;
    std::string result(source);
    // Inject helper in local lexical scope before function definitions.
    const auto anchor=result.find(show);
    result.insert(anchor, std::string(marker)+"\nlocal ZMLMotorcycle = (function()\n"+std::string(helper)+"\nend)()\n\n");
    auto inject=[&](std::string_view key,std::string_view call) {
        result.insert(result.find(key)+key.size(), "\n    "+std::string(call));
    };
    inject(show,"ZMLMotorcycle.show(self)");
    inject(hide,"ZMLMotorcycle.hide(self)");
    inject(close,"ZMLMotorcycle.close(self)");
    if (result.size()>768*1024) return false;
    output=std::move(result);return true;
}
inline bool patchWheel(std::string_view source, std::string_view helper, std::string& output) {
    constexpr std::string_view marker="-- ZML_MOTORCYCLE_WHEEL_V1";
    if(source.empty() || source.find('\0')!=source.npos || helper.empty() || helper.size()>48*1024 ||
       helper.find('\0')!=helper.npos || count(source,marker) ||
       count(source,"GeneralAbilityCtrl = HL.Class('GeneralAbilityCtrl', uiCtrl.UICtrl)")!=1 ||
       count(source,"HL.Commit(GeneralAbilityCtrl)")!=1) return false;
    // Validate anchor uniqueness before applying patches.
    constexpr std::string_view normalEnd="\nGeneralAbilityCtrl._UpdateTempAbilityData = HL.Method() << function(self)";
    constexpr std::string_view normalTail="        self.m_abilityDataList[index].index = index  \n    end\n\nend";
    constexpr std::string_view cell="GeneralAbilityCtrl._UpdateSelectorCellInfo = HL.Method(HL.Any, HL.Number) << function(self, cell, luaIndex)";
    constexpr std::string_view select="GeneralAbilityCtrl._OnSelectByType = HL.Method(HL.Number) << function(self, type)";
    constexpr std::string_view selected="GeneralAbilityCtrl._SetSelectedType = HL.Method(HL.Number, HL.Boolean) << function(self, type, needSave)";
    constexpr std::string_view hover="GeneralAbilityCtrl._RefreshMidHoverInfo = HL.Method(HL.Number) << function(self, type)";
    constexpr std::string_view shown="GeneralAbilityCtrl._RefreshWheelShownState = HL.Method(HL.Boolean) << function(self, isShown)";
    constexpr std::string_view close="GeneralAbilityCtrl.OnClose = HL.Override() << function(self)";
    constexpr std::string_view reset="if data ~= nil and data.isForbidSelect == false then";
    // Normalize line endings for contract scanning while preserving original span bytes.
    std::string canonical;canonical.reserve(source.size());
    for(size_t i=0;i<source.size();++i) {
        if(source[i]=='\r' && i+1<source.size() && source[i+1]=='\n')continue;
        canonical+=source[i];
    }
    if(count(canonical,normalTail)!=1)return false;
    auto offset=[&](size_t normalized) {
        size_t n=0,i=0;
        while(i<source.size() && n<normalized) {
            if(!(source[i]=='\r' && i+1<source.size() && source[i+1]=='\n'))++n;
            ++i;
        }
        return i;
    };
    auto start=canonical.find(normalTail),originalStart=offset(start),originalEnd=offset(start+normalTail.size());
    const auto tail=std::string(source.substr(originalStart,originalEnd-originalStart));
    for(auto a:{normalEnd,cell,select,selected,hover,shown,close,reset}) if(count(source,a)!=1) return false;
    auto result=std::string(source);
    result.insert(result.find("GeneralAbilityCtrl = HL.Class"),std::string(marker)+"\nlocal ZMLBikeWheel = (function()\n"+std::string(helper)+"\nend)()\n");
    auto inject=[&](std::string_view key,std::string_view call){result.insert(result.find(key)+key.size(),"\n    "+std::string(call));};
    result.replace(result.find(tail),tail.size(),"        self.m_abilityDataList[index].index = index  \n    end\n    ZMLBikeWheel.register(self)\nend");
    inject(cell,"if ZMLBikeWheel.cell(self,cell,luaIndex) then return end");
    inject(select,"if ZMLBikeWheel.select(type) then return end");
    inject(selected,"if type == ZMLBikeWheel.id then return end");
    inject(hover,"if ZMLBikeWheel.hover(self,type) then return end");
    inject(shown,"if isShown then ZMLBikeWheel.refresh(self) end");
    inject(close,"ZMLBikeWheel.release(self)");
    result.replace(result.find(reset),reset.size(),"if data ~= nil and data.type ~= ZMLBikeWheel.id and data.isForbidSelect == false then");
    if(result.size()>768*1024)return false;
    output=std::move(result);return true;
}
}
