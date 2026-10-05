#pragma once
#include <string>
#include <string_view>
#include <stdexcept>
namespace motorcycle {
// Minify Lua payload while preserving strings and newlines.
inline std::string compactOwnedLua(std::string_view s) {
    std::string out;out.reserve(s.size());
    auto longEnd=[&](size_t begin) {
        size_t j=begin+1;while(j<s.size() && s[j]=='=')++j;
        if(j>=s.size() || s[j]!='[')return size_t(0);
        const auto close="]"+std::string(j-begin-1,'=')+"]";
        auto end=s.find(close,j+1);
        if(end==s.npos)throw std::runtime_error("unterminated owned Lua long block");
        return end+close.size();
    };
    for(size_t i=0;i<s.size();) {
        if(s[i]=='\'' || s[i]=='"') {
            const auto start=i++;const auto quote=s[start];bool closed=false;
            while(i<s.size()) {
                if(s[i]=='\\'){i+=2;continue;}
                if(s[i++]==quote){closed=true;break;}
            }
            if(!closed)throw std::runtime_error("unterminated owned Lua string");
            out.append(s.substr(start,i-start));continue;
        }
        if(s[i]=='[')if(auto end=longEnd(i)){out.append(s.substr(i,end-i));i=end;continue;}
        if(s[i]=='-' && i+1<s.size() && s[i+1]=='-') {
            const auto start=i;i+=2;size_t end=0;
            if(i<s.size() && s[i]=='[')end=longEnd(i);
            if(!end){end=s.find('\n',i);if(end==s.npos)end=s.size();}
            out+=' ';
            for(size_t j=start;j<end;++j)if(s[j]=='\n')out+='\n';
            i=end;continue;
        }
        out+=s[i++];
    }
    return out;
}
}
