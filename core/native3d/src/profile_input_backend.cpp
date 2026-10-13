// SPDX-License-Identifier: GPL-3.0-or-later
#include "profile_backend.hpp"
#include <cmath>
#include <algorithm>
namespace gx3de_backend {
namespace {
double distance(gx3de_vec3 a,gx3de_vec3 b){return std::hypot(a.x-b.x,a.y-b.y,a.z-b.z);}
gx3de_vec3 placed(gx3de_point2 p,gx3de_vec3 o,gx3de_vec3 u,gx3de_vec3 v){
    return {o.x+u.x*p.u+v.x*p.v,o.y+u.y*p.u+v.y*p.v,o.z+u.z*p.u+v.z*p.v};
}
}
bool input_contours(const gx3de_profile_contour_spec *inputs,uint64_t count,
    gx3de_vec3 origin,gx3de_vec3 u,gx3de_vec3 v,double tolerance,
    std::vector<ProfileContour>& contours,std::string& error){
    contours.clear();error.clear();
    if(!inputs||!count||count>4096||!std::isfinite(tolerance)||tolerance<=0){error="invalid contour count or join tolerance";return false;}
    std::vector<gx3de_segment3> segments;uint64_t total=0;
    for(uint64_t k=0;k<count;++k){
        const auto& in=inputs[k];
        if(in.struct_size<sizeof(in)||in.closed>1||!in.points||in.point_count<2||in.point_count>1000000-total){error="invalid or excessive contour points";return false;}
        total+=in.point_count;ProfileContour c;c.closed=in.closed!=0;
        for(uint64_t j=0;j<in.point_count;++j){
            const auto p=in.points[j];auto q=placed(p,origin,u,v);
            if(!std::isfinite(p.u)||!std::isfinite(p.v)||!std::isfinite(q.x)||!std::isfinite(q.y)||!std::isfinite(q.z)){error="nonfinite contour coordinate";return false;}
            c.points.push_back(q);
        }
        if(c.closed&&distance(c.points.front(),c.points.back())<=tolerance)c.points.pop_back();
        if(c.points.size()<(c.closed?3u:2u)){error="contour has too few distinct points";return false;}
        const auto n=c.points.size();const auto edge_count=c.closed?n:n-1;
        long double twice_area=0;
        // Translate before area products to avoid cancellation at large origins.
        const auto base=in.points[0];
        for(size_t j=0;j<edge_count;++j){
            const auto a=c.points[j],b=c.points[(j+1)%n];const auto length=distance(a,b);
            if(!std::isfinite(length)||length<=tolerance){error="contour edge collapses at join tolerance";return false;}
            c.length+=length;segments.push_back({a,b});
            if(c.closed){const auto pa=in.points[j],pb=in.points[(j+1)%n];twice_area+=(static_cast<long double>(pa.u)-base.u)*(static_cast<long double>(pb.v)-base.v)-(static_cast<long double>(pb.u)-base.u)*(static_cast<long double>(pa.v)-base.v);}
        }
        c.area=c.closed?static_cast<double>(std::abs(twice_area)/2):0;
        if(!std::isfinite(c.length)||!std::isfinite(c.area)||(c.closed&&c.area<=tolerance*tolerance)){error="contour area or length is degenerate";return false;}
        contours.push_back(std::move(c));
    }
    std::vector<ProfileContour> checked;
    if(!chain_section(segments,origin,u,v,tolerance,checked,error)){contours.clear();return false;}
    if(checked.size()!=contours.size()){error="contours touch or join ambiguously";contours.clear();return false;}
    // Preserve the submitted ordering/winding; chaining is validation only.
    for(size_t i=0;i<contours.size();++i){
        const auto& original=contours[i];bool found=false;
        for(const auto& c:checked)if(c.closed==original.closed&&c.points.size()==original.points.size()&&std::abs(c.length-original.length)<=tolerance*original.points.size()){found=true;break;}
        if(!found){error="contour topology changes at join tolerance";contours.clear();return false;}
    }
    return true;
}
}
