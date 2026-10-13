// SPDX-License-Identifier: GPL-3.0-or-later
#include "mesh_repeat_backend.hpp"
#include <algorithm>
#include <array>
#include <cmath>
#include <cstdint>
#include <limits>
#include <map>
#include <numeric>
#include <stdexcept>
#include <tuple>

namespace gx3de_backend {
namespace {
using Matrix=std::array<std::array<int,3>,3>;
using Triangle=std::array<int64_t,9>;
std::vector<Matrix> rotations() {
    std::vector<Matrix> result;
    std::array<int,3> permutation{0,1,2};
    do {
        const int parity=((permutation[0]>permutation[1])+
            (permutation[0]>permutation[2])+(permutation[1]>permutation[2]))%2?-1:1;
        for(int sx:{-1,1})for(int sy:{-1,1})for(int sz:{-1,1}){
            if(parity*sx*sy*sz!=1)continue;
            Matrix rotation{};
            rotation[0][permutation[0]]=sx;
            rotation[1][permutation[1]]=sy;
            rotation[2][permutation[2]]=sz;
            result.push_back(rotation);
        }
    }while(std::next_permutation(permutation.begin(),permutation.end()));
    return result;
}
std::array<double,3> position(const gx3de_vec3& p){return {p.x,p.y,p.z};}
std::array<double,3> centroid(const MeshData& mesh,const std::vector<uint32_t>& cells){
    std::array<double,3> center{};
    for(uint32_t cell:cells)for(int vertex=0;vertex<3;++vertex){
        auto p=position(mesh.vertices[mesh.triangles[size_t(cell)*3+vertex]]);
        for(int axis=0;axis<3;++axis)center[axis]+=p[axis];
    }
    const double divisor=double(cells.size())*3.0;
    for(double& value:center)value/=divisor;
    return center;
}
std::vector<Triangle> signature(const MeshData& mesh,
    const std::vector<uint32_t>& cells,const std::array<double,3>& center,
    const Matrix& rotation,double tolerance){
    std::vector<Triangle> triangles;triangles.reserve(cells.size());
    for(uint32_t cell:cells){
        std::array<std::array<int64_t,3>,3> vertices{};
        for(int vertex=0;vertex<3;++vertex){
            auto p=position(mesh.vertices[mesh.triangles[size_t(cell)*3+vertex]]);
            for(int axis=0;axis<3;++axis){
                double coordinate=0;
                for(int source=0;source<3;++source)
                    coordinate+=rotation[source][axis]*(p[source]-center[source]);
                if(!std::isfinite(coordinate)||std::abs(coordinate/tolerance)>1e15)
                    throw std::runtime_error("repeat geometry is outside supported precision range");
                vertices[vertex][axis]=static_cast<int64_t>(std::llround(coordinate/tolerance));
            }
        }
        std::sort(vertices.begin(),vertices.end());
        Triangle flattened{};
        for(int vertex=0;vertex<3;++vertex)for(int axis=0;axis<3;++axis)
            flattened[vertex*3+axis]=vertices[vertex][axis];
        triangles.push_back(flattened);
    }
    std::sort(triangles.begin(),triangles.end());return triangles;
}
size_t root(std::vector<size_t>& parents,size_t cell){
    while(parents[cell]!=cell){parents[cell]=parents[parents[cell]];cell=parents[cell];}
    return cell;
}
void join(std::vector<size_t>& parents,size_t a,size_t b){parents[root(parents,a)]=root(parents,b);}
}

bool discover_repeats(const MeshData& source,uint64_t selected,
                      RepeatResult& output,std::string& error){
    try{
        const size_t cell_count=source.triangles.size()/3;
        if(source.triangles.size()%3||selected>=cell_count||cell_count>1000000||
           source.vertices.size()>3000000||cell_count==0)
            throw std::runtime_error("repeat matching exceeds bounded scan or selected triangle is invalid");
        for(const auto p:source.vertices)if(!std::isfinite(p.x)||!std::isfinite(p.y)||!std::isfinite(p.z))
            throw std::runtime_error("repeat source contains non-finite point");
        std::vector<size_t> parents(cell_count);std::iota(parents.begin(),parents.end(),size_t{0});
        /* vtkCleanPolyData in the frozen worker unifies coincident input points
         * before matching. Exact-coordinate keys provide that same connectivity
         * without changing source triangle IDs exposed through this API. */
        std::map<std::array<double,3>,size_t> first;
        for(size_t cell=0;cell<cell_count;++cell)for(int vertex=0;vertex<3;++vertex){
            uint32_t index=source.triangles[cell*3+vertex];
            if(index>=source.vertices.size())throw std::runtime_error("repeat source has invalid index");
            auto key=position(source.vertices[index]);
            auto [it,inserted]=first.emplace(key,cell);
            if(!inserted)join(parents,cell,it->second);
        }
        std::map<size_t,std::vector<uint32_t>> groups;
        for(size_t cell=0;cell<cell_count;++cell)
            groups[root(parents,cell)].push_back(static_cast<uint32_t>(cell));
        const auto chosen=groups.find(root(parents,size_t(selected)));
        if(chosen==groups.end()||chosen->second.empty()||chosen->second.size()>100000)
            throw std::runtime_error("selected component is empty or over repeat limit");
        auto source_center=centroid(source,chosen->second);
        std::array<double,3> lo{INFINITY,INFINITY,INFINITY},hi{-INFINITY,-INFINITY,-INFINITY};
        for(uint32_t index:source.triangles){auto xyz=position(source.vertices[index]);for(int axis=0;axis<3;++axis){
            lo[axis]=std::min(lo[axis],xyz[axis]);hi[axis]=std::max(hi[axis],xyz[axis]);}}
        const double span=std::max({hi[0]-lo[0],hi[1]-lo[1],hi[2]-lo[2]});
        if(!std::isfinite(span))throw std::runtime_error("repeat source bounds exceed supported range");
        const double tolerance=std::max(1e-6,span*1e-5);
        const Matrix identity{{{{1,0,0}},{{0,1,0}},{{0,0,1}}}};
        const auto reference=signature(source,chosen->second,source_center,identity,tolerance);
        RepeatResult result;result.source_triangle=selected;
        result.source_triangles=chosen->second.size();result.tolerance=tolerance;
        std::vector<uint8_t> matched(cell_count,0);
        const auto orientations=rotations();
        for(const auto& entry:groups){
            if(entry.second.size()!=chosen->second.size())continue;
            auto center=centroid(source,entry.second);
            for(const auto& rotation:orientations){
                if(signature(source,entry.second,center,rotation,tolerance)!=reference)continue;
                RepeatMatch match;match.center=center;match.rotation=rotation;
                match.triangles=entry.second;
                for(uint32_t cell:match.triangles)matched[cell]=1;
                result.matches.push_back(std::move(match));break;
            }
        }
        if(result.matches.size()<2)
            throw std::runtime_error("no matching disconnected components found");
        for(uint32_t cell:chosen->second)for(int vertex=0;vertex<3;++vertex){
            auto p=source.vertices[source.triangles[size_t(cell)*3+vertex]];
            result.prototype.vertices.push_back({p.x-source_center[0],p.y-source_center[1],p.z-source_center[2]});
            result.prototype.triangles.push_back(uint32_t(result.prototype.triangles.size()));
        }
        std::map<uint32_t,uint32_t> remap;
        for(size_t cell=0;cell<cell_count;++cell){
            if(matched[cell])continue;
            for(int vertex=0;vertex<3;++vertex){
                uint32_t source_id=source.triangles[cell*3+vertex];
                auto [it,inserted]=remap.emplace(source_id,uint32_t(result.remainder.vertices.size()));
                if(inserted)result.remainder.vertices.push_back(source.vertices[source_id]);
                result.remainder.triangles.push_back(it->second);
            }
        }
        output=std::move(result);error.clear();return true;
    }catch(const std::bad_alloc&){error="out of memory detecting repeats";}
    catch(const std::exception& e){error=e.what();}
    return false;
}
}
