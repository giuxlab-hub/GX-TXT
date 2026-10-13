// SPDX-License-Identifier: GPL-3.0-or-later
#pragma once

#include <cstdint>
#include <string>

namespace gx3de_backend {
struct D3D11Probe {
    bool available=false;
    uint32_t feature_level=0;
    std::string adapter;
    std::string diagnostic;
};

// Device probing has no presentation side effects and releases every COM
// interface before returning. It never claims that the D3D renderer exists.
D3D11Probe probe_d3d11();
}
