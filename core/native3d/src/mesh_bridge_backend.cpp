// SPDX-License-Identifier: GPL-3.0-or-later
#include "mesh_bridge_backend.hpp"
#include "mesh_self_intersection_backend.hpp"
#include <algorithm>
#include <cmath>
#include <cstdint>
#include <limits>
#include <stdexcept>
#include <vector>

namespace gx3de_backend {
namespace {
gx3de_vec3 difference(gx3de_vec3 a,gx3de_vec3 b){return {a.x-b.x,a.y-b.y,a.z-b.z};}
gx3de_vec3 cross(gx3de_vec3 a,gx3de_vec3 b){
    return {a.y*b.z-a.z*b.y,a.z*b.x-a.x*b.z,a.x*b.y-a.y*b.x};
}
long double squared(gx3de_vec3 a){return static_cast<long double>(a.x)*a.x+static_cast<long double>(a.y)*a.y+static_cast<long double>(a.z)*a.z;}
bool bridge_loops(const MeshData& input,const std::vector<uint32_t>& a,
    const std::vector<uint32_t>& b,double max_gap,MeshData& output,std::string& error){
    if(a.size()<3||a.size()!=b.size()){
        error="bridge boundaries have unequal or insufficient vertices";return false;
    }
    const size_t n=a.size();
    double lo[3]={INFINITY,INFINITY,INFINITY},hi[3]={-INFINITY,-INFINITY,-INFINITY};
    for(uint32_t id:a)for(int axis=0;axis<3;++axis){
        const auto& p=input.vertices[id];double value=axis==0?p.x:axis==1?p.y:p.z;
        lo[axis]=std::min(lo[axis],value);hi[axis]=std::max(hi[axis],value);}
    for(uint32_t id:b)for(int axis=0;axis<3;++axis){
        const auto& p=input.vertices[id];double value=axis==0?p.x:axis==1?p.y:p.z;
        lo[axis]=std::min(lo[axis],value);hi[axis]=std::max(hi[axis],value);}
    double span=std::max({hi[0]-lo[0],hi[1]-lo[1],hi[2]-lo[2]});
    if(!std::isfinite(span)||!(span>0)){
        error="bridge bounds are invalid";return false;
    }
    const long double min_gap=static_cast<long double>(span)*1e-12L;
    const long double max_gap2=static_cast<long double>(max_gap)*max_gap;
    long double best=INFINITY,second=INFINITY;size_t best_shift=0;
    for(size_t shift=0;shift<n;++shift){
        long double score=0;bool valid=true;
        for(size_t i=0;i<n;++i){
            const auto va=input.vertices[a[i]],vb=input.vertices[b[(shift+n-i)%n]];
            long double distance2=squared(difference(va,vb));
            if(!std::isfinite(distance2)||distance2>max_gap2||
               distance2<=min_gap*min_gap){valid=false;break;}
            score+=distance2;
        }
        if(!std::isfinite(score))valid=false;
        if(!valid)continue;
        if(score<best){second=best;best=score;best_shift=shift;}
        else if(score<second)second=score;
    }
    if(!std::isfinite(best)){
        error="no safe bridge correspondence within maximum gap";return false;
    }
    if(std::isfinite(second)&&second-best<=1e-12L*std::max(1.0L,best)){
        error="bridge boundary pairing is ambiguous";return false;
    }
    MeshData built=input;
    if(n>SIZE_MAX/6||built.triangles.size()>SIZE_MAX-6*n||
       built.triangles.size()/3+2*n>UINT32_MAX){error="bridge face count overflows";return false;}
    built.triangles.reserve(built.triangles.size()+6*n);
    const long double minimum_area2=static_cast<long double>(span)*span*1e-12L;
    for(size_t i=0;i<n;++i){
        uint32_t a0=a[i],a1=a[(i+1)%n];
        uint32_t b0=b[(best_shift+n-i)%n],b1=b[(best_shift+n-(i+1))%n];
        const uint32_t faces[6]={a0,b0,a1,a1,b0,b1};
        for(int face=0;face<2;++face){
            auto p=built.vertices[faces[face*3]],q=built.vertices[faces[face*3+1]],
                 r=built.vertices[faces[face*3+2]];
            if(std::sqrt(squared(cross(difference(q,p),difference(r,p))))<=minimum_area2){
                error="bridge would create a degenerate face";return false;
            }
        }
        built.triangles.insert(built.triangles.end(),faces,faces+6);
    }
    std::vector<std::vector<uint32_t>> remaining;
    if(!boundary_loops(built,remaining,error))return false;
    if(!remaining.empty()){
        error="bridge leaves unmatched boundary loops";return false;
    }
    MeshData oriented;
    MeshOrientationStats stats;
    if(!orient_normals(built,oriented,error,&stats))return false;
    if(stats.connected_components!=1||stats.closed_components!=1){
        error="bridge does not form one closed connected solid";return false;
    }
    uint64_t intersections=0;
    if(!mesh_self_intersections(oriented,0,intersections,error))return false;
    if(intersections){error="bridge self-intersects";return false;}
    output=std::move(oriented);error.clear();return true;
}
}

bool bridge_two_meshes(const MeshData& a,const MeshData& b,double max_gap,
                       MeshData& output,std::string& error){
    if(!std::isfinite(max_gap)||!(max_gap>0)){
        error="bridge maximum gap must be finite and positive";return false;
    }
    try{
        std::vector<std::vector<uint32_t>> loops_a,loops_b;
        if(!boundary_loops(a,loops_a,error)||!boundary_loops(b,loops_b,error))return false;
        if(loops_a.size()!=1||loops_b.size()!=1){
            error="bridge requires one simple boundary loop on each mesh";return false;
        }
        if(b.vertices.size()>UINT32_MAX||a.vertices.size()>UINT32_MAX-b.vertices.size()||
           a.triangles.size()>SIZE_MAX-b.triangles.size()){
            error="bridge mesh exceeds index or allocation capacity";return false;
        }
        MeshData joined=a;uint32_t offset=uint32_t(joined.vertices.size());
        joined.vertices.insert(joined.vertices.end(),b.vertices.begin(),b.vertices.end());
        joined.triangles.reserve(a.triangles.size()+b.triangles.size());
        for(uint32_t id:b.triangles)joined.triangles.push_back(offset+id);
        for(uint32_t& id:loops_b[0])id+=offset;
        return bridge_loops(joined,loops_a[0],loops_b[0],max_gap,output,error);
    }catch(const std::bad_alloc&){error="out of memory building bridge";}
     catch(const std::exception& e){error=e.what();}
    return false;
}
bool heal_one_mesh_seam(const MeshData& source,double max_gap,
                        MeshData& output,std::string& error){
    if(!std::isfinite(max_gap)||!(max_gap>0)){
        error="seam maximum gap must be finite and positive";return false;
    }
    try{
        std::vector<std::vector<uint32_t>> loops;
        if(!boundary_loops(source,loops,error))return false;
        if(loops.size()!=2){error="seam healing requires exactly two simple boundary loops";return false;}
        return bridge_loops(source,loops[0],loops[1],max_gap,output,error);
    }catch(const std::bad_alloc&){error="out of memory healing seam";}
     catch(const std::exception& e){error=e.what();}
    return false;
}
}
