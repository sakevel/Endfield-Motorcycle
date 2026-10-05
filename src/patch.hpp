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
        helper.size()>720*1024 || helper.find('\0')!=helper.npos || count(source,marker) ||
        count(source,show)!=1 || count(source,hide)!=1 || count(source,close)!=1 || count(source,commit)!=1 ||
        count(source,"BattleActionCtrl = HL.Class('BattleActionCtrl', uiCtrl.UICtrl)")!=1) return false;
    std::string result(source);
    // Helper must precede the function definitions: local lexical variable, not a global hook.
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
}
