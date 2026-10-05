#pragma once
#include <Windows.h>
#include <wincrypt.h>
#include <cmath>
#include <cstring>
#include <filesystem>
#include <fstream>
#include <iterator>
#include <stdexcept>
#include <string>
#include <string_view>
namespace motorcycle {
inline std::string readAsset(const std::filesystem::path& p,size_t cap) {
    if(std::filesystem::file_size(p)>cap)throw std::runtime_error("asset too large");
    std::ifstream f(p,std::ios::binary);std::string s{std::istreambuf_iterator<char>(f),{}};
    if(!f||s.empty()||s.size()>cap)throw std::runtime_error("asset unreadable");return s;
}
inline bool validMesh(std::string_view bytes) {
    size_t at=0;auto take=[&](void* out,size_t n){if(n>bytes.size()-at)return false;memcpy(out,bytes.data()+at,n);at+=n;return true;};
    char magic[8];uint32_t parts;
    if(!take(magic,8)||memcmp(magic,"ZMLBIKE1",8)||!take(&parts,4)||parts==0||parts>32)return false;
    size_t totalV=0,totalI=0;
    for(uint32_t p=0;p<parts;p++) {
        uint32_t h[4];float f[17];
        if(!take(h,sizeof h)||h[0]>4||h[1]==0||h[1]>65535||h[2]==0||h[2]>150000||h[2]%3||h[3]>1||!take(f,sizeof f))return false;
        for(float v:f)if(!std::isfinite(v)||std::abs(v)>100)return false;
        for(size_t i:{6,7,8,11,12})if(f[i]<=0)return false;
        for(size_t i:{13,14,15,16})if(f[i]<0||f[i]>1)return false;
        const size_t n=size_t(h[1])*12;if(n>bytes.size()-at)return false;at+=n;
        for(uint32_t j=0;j<h[2];j++){uint16_t index;if(!take(&index,2)||index>=h[1])return false;}
        totalV+=h[1];totalI+=h[2];if(totalV>60000||totalI>150000)return false;
    }
    return at==bytes.size();
}
inline std::string sha256(std::string_view s) {
    HCRYPTPROV provider{};HCRYPTHASH hash{};BYTE result[32];DWORD n=32;
    if(!CryptAcquireContextW(&provider,nullptr,nullptr,PROV_RSA_AES,CRYPT_VERIFYCONTEXT))throw std::runtime_error("hash provider");
    bool ok=CryptCreateHash(provider,CALG_SHA_256,0,0,&hash)&&CryptHashData(hash,reinterpret_cast<const BYTE*>(s.data()),DWORD(s.size()),0)&&CryptGetHashParam(hash,HP_HASHVAL,result,&n,0);
    if(hash)CryptDestroyHash(hash);CryptReleaseContext(provider,0);if(!ok||n!=32)throw std::runtime_error("asset hash");
    constexpr char hex[]="0123456789abcdef";std::string out;for(auto c:result){out+=hex[c>>4];out+=hex[c&15];}return out;
}
inline std::string base64(std::string_view s) {
    DWORD n{};auto ptr=reinterpret_cast<const BYTE*>(s.data());
    if(!CryptBinaryToStringA(ptr,DWORD(s.size()),CRYPT_STRING_BASE64|CRYPT_STRING_NOCRLF,nullptr,&n))throw std::runtime_error("base64 size");
    std::string out(n,'\0');if(!CryptBinaryToStringA(ptr,DWORD(s.size()),CRYPT_STRING_BASE64|CRYPT_STRING_NOCRLF,out.data(),&n))throw std::runtime_error("base64 encode");
    out.resize(n);while(!out.empty()&&out.back()=='\0')out.pop_back();return out;
}
}
