// SPDX-License-Identifier: GPL-3.0-or-later
#include "native_3d_d3d11_probe.hpp"

#ifdef _WIN32
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <d3d11.h>
#include <dxgi.h>
#include <cstdio>

namespace {
std::string hresult_text(HRESULT code) {
    char buffer[32]{};
    std::snprintf(buffer,sizeof buffer,"HRESULT 0x%08lX",
                  static_cast<unsigned long>(code));
    return buffer;
}
std::string utf8(const wchar_t *text) {
    if(!text||!*text)return {};
    const int needed=WideCharToMultiByte(CP_UTF8,0,text,-1,nullptr,0,nullptr,nullptr);
    if(needed<=1)return {};
    std::string result(static_cast<size_t>(needed), '\0');
    if(!WideCharToMultiByte(CP_UTF8,0,text,-1,result.data(),needed,nullptr,nullptr))return {};
    result.resize(static_cast<size_t>(needed-1));
    return result;
}
}

gx3de_backend::D3D11Probe gx3de_backend::probe_d3d11() {
    D3D11Probe result{};
    ID3D11Device *device=nullptr;
    ID3D11DeviceContext *context=nullptr;
    D3D_FEATURE_LEVEL feature=D3D_FEATURE_LEVEL_9_1;
    const D3D_FEATURE_LEVEL levels[]={D3D_FEATURE_LEVEL_11_0,
        D3D_FEATURE_LEVEL_10_1,D3D_FEATURE_LEVEL_10_0};
    HRESULT status=D3D11CreateDevice(nullptr,D3D_DRIVER_TYPE_HARDWARE,nullptr,0,
        levels,static_cast<UINT>(sizeof(levels)/sizeof(levels[0])),D3D11_SDK_VERSION,
        &device,&feature,&context);
    if(FAILED(status)) {
        result.diagnostic="D3D11 hardware device creation failed: "+hresult_text(status);
        return result;
    }
    result.feature_level=static_cast<uint32_t>(feature);
    IDXGIDevice *dxgi_device=nullptr;
    IDXGIAdapter *adapter=nullptr;
    if(SUCCEEDED(device->QueryInterface(IID_IDXGIDevice,
            reinterpret_cast<void**>(&dxgi_device)))&&dxgi_device) {
        if(SUCCEEDED(dxgi_device->GetAdapter(&adapter))&&adapter) {
            DXGI_ADAPTER_DESC description{};
            if(SUCCEEDED(adapter->GetDesc(&description)))
                result.adapter=utf8(description.Description);
        }
    }
    if(adapter)adapter->Release();
    if(dxgi_device)dxgi_device->Release();
    if(context)context->Release();
    if(device)device->Release();
    if(feature<D3D_FEATURE_LEVEL_11_0) {
        result.diagnostic="D3D11 feature level 11.0 is unavailable on the default hardware adapter";
        return result;
    }
    result.available=true;
    result.diagnostic="D3D11 hardware device and feature level 11.0 or newer are available";
    return result;
}
#else
gx3de_backend::D3D11Probe gx3de_backend::probe_d3d11() {
    return {false,0,{},"D3D11 is only available on Windows"};
}
#endif
