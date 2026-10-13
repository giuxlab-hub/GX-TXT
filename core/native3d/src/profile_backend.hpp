// SPDX-License-Identifier: GPL-3.0-or-later
#ifndef GX3DE_PROFILE_BACKEND_HPP
#define GX3DE_PROFILE_BACKEND_HPP
#include "native_3d_engine_api_v1.h"
#include <string>
#include <vector>
namespace gx3de_backend {
struct ProfileContour {
    std::vector<gx3de_vec3> points; // a closed contour omits the repeated start
    bool closed=false;
    double length=0,area=0;
};
bool input_contours(const gx3de_profile_contour_spec *inputs,uint64_t count,
    gx3de_vec3 origin,gx3de_vec3 u,gx3de_vec3 v,double tolerance,
    std::vector<ProfileContour>& contours,std::string& error);
bool chain_section(const std::vector<gx3de_segment3>& segments,
                   gx3de_vec3 origin,gx3de_vec3 u,gx3de_vec3 v,
                   double tolerance,std::vector<ProfileContour>& contours,
                   std::string& error);
}
#endif
