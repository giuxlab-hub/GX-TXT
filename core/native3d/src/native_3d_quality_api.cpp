// SPDX-License-Identifier: GPL-3.0-or-later
// Requested-resolution deterministic supersampling through the public C API.
#include "native_3d_engine_api_v1.h"
#include <cstdint>
#include <limits>
#include <new>
#include <vector>

extern "C" gx3de_result gx3de_view_render_rgba_supersampled(
    gx3de_view *view,uint32_t width,uint32_t height,uint32_t factor,
    uint8_t *pixels,uint64_t capacity,uint64_t *required_bytes) {
    if(!view||!required_bytes||(!pixels&&capacity)||!width||!height||
       factor<1||factor>4)return GX3DE_INVALID_ARGUMENT;
    constexpr uint64_t budget=256ull*1024ull*1024ull;
    const uint64_t high_width=uint64_t(width)*factor;
    const uint64_t high_height=uint64_t(height)*factor;
    if(high_width>16384||high_height>16384||
       high_width*high_height*4>budget)return GX3DE_RANGE;
    const uint64_t output_bytes=uint64_t(width)*height*4;
    *required_bytes=output_bytes;
    if(capacity==0)return GX3DE_OK;
    if(capacity<output_bytes)return GX3DE_RANGE;
    if(factor==1)return gx3de_view_render_rgba(view,width,height,pixels,capacity,
                                                required_bytes);
    try {
        std::vector<uint8_t> high(static_cast<size_t>(high_width*high_height*4));
        uint64_t produced=0;
        const auto status=gx3de_view_render_rgba(view,static_cast<uint32_t>(high_width),
            static_cast<uint32_t>(high_height),high.data(),high.size(),&produced);
        if(status!=GX3DE_OK)return status;
        if(produced!=high.size())return GX3DE_DEGENERATE;
        const uint32_t samples=factor*factor;
        for(uint32_t y=0;y<height;++y)for(uint32_t x=0;x<width;++x){
            uint32_t sums[4]={};
            for(uint32_t fy=0;fy<factor;++fy)for(uint32_t fx=0;fx<factor;++fx){
                const auto offset=4*((uint64_t(y)*factor+fy)*high_width+
                                     uint64_t(x)*factor+fx);
                for(unsigned channel=0;channel<4;++channel)
                    sums[channel]+=high[static_cast<size_t>(offset+channel)];
            }
            const auto output=4*(uint64_t(y)*width+x);
            for(unsigned channel=0;channel<4;++channel)
                pixels[static_cast<size_t>(output+channel)]=
                    static_cast<uint8_t>((sums[channel]+samples/2)/samples);
        }
        return GX3DE_OK;
    }catch(const std::bad_alloc&) {return GX3DE_OUT_OF_MEMORY;}
}
