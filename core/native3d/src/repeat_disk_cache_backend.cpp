// SPDX-License-Identifier: GPL-3.0-or-later
#include "repeat_disk_cache_backend.hpp"
#include <array>
#include <cmath>
#include <cstring>
#include <limits>
#include <stdexcept>
#include <string>
#include <unordered_set>

namespace gx3de_backend {
namespace {
constexpr char magic[8]={'G','X','3','D','R','P','T','1'};
constexpr uint32_t schema=1;
bool lower_hex(const std::string& value){
    if(value.size()!=64)return false;
    for(char c:value)if(!((c>='0'&&c<='9')||(c>='a'&&c<='f')))return false;
    return true;
}
void append_u32(std::string& out,uint32_t value){
    for(int i=0;i<4;++i)out.push_back(char(value>>(i*8)));
}
void append_u64(std::string& out,uint64_t value){
    for(int i=0;i<8;++i)out.push_back(char(value>>(i*8)));
}
void append_double(std::string& out,double value){
    if(!std::isfinite(value))throw std::invalid_argument("repeat cache contains non-finite value");
    uint64_t bits;std::memcpy(&bits,&value,8);append_u64(out,bits);
}
struct Reader {
    const std::string& bytes;size_t offset=0;
    void require(size_t n){if(n>bytes.size()-offset)throw std::invalid_argument("repeat cache payload is incomplete");}
    uint32_t u32(){require(4);uint32_t value=0;for(int i=0;i<4;++i)value|=uint32_t(uint8_t(bytes[offset++]))<<(8*i);return value;}
    uint64_t u64(){require(8);uint64_t value=0;for(int i=0;i<8;++i)value|=uint64_t(uint8_t(bytes[offset++]))<<(8*i);return value;}
    double real(){uint64_t bits=u64();double value;std::memcpy(&value,&bits,8);
        if(!std::isfinite(value))throw std::invalid_argument("repeat cache has non-finite coordinate");return value;}
    std::string text(size_t n){require(n);std::string result=bytes.substr(offset,n);offset+=n;return result;}
};
bool proper_rotation(const std::array<std::array<int,3>,3>& matrix){
    for(int row=0;row<3;++row){int nonzero=0;for(int col=0;col<3;++col){
        if(matrix[row][col]<-1||matrix[row][col]>1)return false;
        nonzero+=matrix[row][col]!=0;}
        if(nonzero!=1)return false;}
    for(int col=0;col<3;++col){int nonzero=0;for(int row=0;row<3;++row)
        nonzero+=matrix[row][col]!=0;if(nonzero!=1)return false;}
    const auto& m=matrix;
    int determinant=m[0][0]*(m[1][1]*m[2][2]-m[1][2]*m[2][1])-
        m[0][1]*(m[1][0]*m[2][2]-m[1][2]*m[2][0])+
        m[0][2]*(m[1][0]*m[2][1]-m[1][1]*m[2][0]);
    return determinant==1;
}
void validate_mesh(const MeshData& mesh,bool empty_allowed){
    if(mesh.vertices.size()>3000000||mesh.triangles.size()%3||
       mesh.triangles.size()/3>1000000||
       (mesh.triangles.empty()!=mesh.vertices.empty())||
       (!empty_allowed&&mesh.triangles.empty()))
        throw std::invalid_argument("repeat cache mesh counts are invalid");
    for(auto p:mesh.vertices)if(!std::isfinite(p.x)||!std::isfinite(p.y)||!std::isfinite(p.z))
        throw std::invalid_argument("repeat cache mesh point is non-finite");
    for(uint32_t id:mesh.triangles)if(id>=mesh.vertices.size())
        throw std::invalid_argument("repeat cache mesh triangle has invalid index");
}
void validate_result(const RepeatResult& data,const std::string& source,uint64_t selected){
    if(!lower_hex(source)||data.source_triangle!=selected||
       data.source_triangles==0||data.source_triangles>100000||
       data.matches.size()<2||data.matches.size()>1000000||
       !(data.tolerance>0)||!std::isfinite(data.tolerance))
        throw std::invalid_argument("repeat cache identity or component counts are invalid");
    validate_mesh(data.prototype,false);validate_mesh(data.remainder,true);
    if(data.prototype.triangles.size()/3!=data.source_triangles||
       data.prototype.vertices.size()!=data.source_triangles*3)
        throw std::invalid_argument("repeat cache prototype count mismatch");
    const uint64_t remainder_count=data.remainder.triangles.size()/3;
    if(data.matches.size()>UINT64_MAX/data.source_triangles||
       data.matches.size()*data.source_triangles>1000000-remainder_count)
        throw std::invalid_argument("repeat cache source triangle budget exceeded");
    const uint64_t total=data.matches.size()*data.source_triangles+remainder_count;
    if(selected>=total)throw std::invalid_argument("repeat cache selected triangle is outside source");
    std::unordered_set<uint32_t> assigned;
    bool selected_seen=false;
    for(const auto& match:data.matches){
        if(!proper_rotation(match.rotation)||match.triangles.size()!=data.source_triangles)
            throw std::invalid_argument("repeat cache placement topology is invalid");
        for(double value:match.center)if(!std::isfinite(value))
            throw std::invalid_argument("repeat cache placement is non-finite");
        for(uint32_t cell:match.triangles){
            if(cell>=total||!assigned.insert(cell).second)
                throw std::invalid_argument("repeat cache source component IDs are invalid");
            selected_seen|=cell==selected;
        }
    }
    if(!selected_seen)throw std::invalid_argument("repeat cache selected component is missing");
}
void write_mesh(std::string& payload,const MeshData& mesh){
    for(auto p:mesh.vertices){append_double(payload,p.x);append_double(payload,p.y);append_double(payload,p.z);}
    for(uint32_t id:mesh.triangles)append_u32(payload,id);
}
void read_mesh(Reader& reader,MeshData& mesh,uint64_t vertices,uint64_t triangles){
    if(vertices>3000000||triangles>1000000)
        throw std::invalid_argument("repeat cache mesh exceeds count limit");
    if(vertices>SIZE_MAX/24||triangles>SIZE_MAX/12||
       uint64_t(reader.bytes.size()-reader.offset)<vertices*24+triangles*12)
        throw std::invalid_argument("repeat cache mesh payload is incomplete");
    mesh.vertices.reserve(size_t(vertices));mesh.triangles.reserve(size_t(triangles)*3);
    for(uint64_t i=0;i<vertices;++i)mesh.vertices.push_back({reader.real(),reader.real(),reader.real()});
    for(uint64_t i=0;i<triangles*3;++i)mesh.triangles.push_back(reader.u32());
}
std::string encode(const std::string& source,const RepeatResult& data){
    validate_result(data,source,data.source_triangle);
    std::string payload;payload.reserve(128+
        data.prototype.vertices.size()*24+data.prototype.triangles.size()*4+
        data.remainder.vertices.size()*24+data.remainder.triangles.size()*4+
        data.matches.size()*68);
    payload.append(magic,sizeof(magic));append_u32(payload,schema);
    payload.append(source);append_u64(payload,data.source_triangle);
    append_u64(payload,data.source_triangles);append_double(payload,data.tolerance);
    append_u64(payload,data.prototype.vertices.size());append_u64(payload,data.prototype.triangles.size()/3);
    append_u64(payload,data.remainder.vertices.size());append_u64(payload,data.remainder.triangles.size()/3);
    append_u64(payload,data.matches.size());
    write_mesh(payload,data.prototype);write_mesh(payload,data.remainder);
    for(const auto& match:data.matches){
        for(double value:match.center)append_double(payload,value);
        for(const auto& row:match.rotation)for(int value:row)
            append_u32(payload,value<0?UINT32_MAX:uint32_t(value));
        append_u64(payload,match.triangles.size());
        for(uint32_t cell:match.triangles)append_u32(payload,cell);
    }
    return payload;
}
RepeatResult decode(const std::string& payload,const std::string& source,uint64_t selected){
    Reader reader{payload};
    if(reader.text(8)!=std::string(magic,sizeof(magic))||reader.u32()!=schema||
       reader.text(64)!=source)
        throw std::invalid_argument("repeat cache schema or source fingerprint mismatch");
    RepeatResult data;data.source_triangle=reader.u64();
    data.source_triangles=reader.u64();data.tolerance=reader.real();
    const uint64_t prototype_vertices=reader.u64(),prototype_triangles=reader.u64();
    const uint64_t remainder_vertices=reader.u64(),remainder_triangles=reader.u64();
    const uint64_t matches=reader.u64();
    if(matches>1000000)throw std::invalid_argument("repeat cache match count exceeds limit");
    read_mesh(reader,data.prototype,prototype_vertices,prototype_triangles);
    read_mesh(reader,data.remainder,remainder_vertices,remainder_triangles);
    data.matches.reserve(size_t(matches));
    for(uint64_t i=0;i<matches;++i){
        RepeatMatch match;
        for(double& value:match.center)value=reader.real();
        for(auto& row:match.rotation)for(int& value:row){
            auto encoded=reader.u32();
            if(encoded!=0&&encoded!=1&&encoded!=UINT32_MAX)
                throw std::invalid_argument("repeat cache rotation value is invalid");
            value=encoded==UINT32_MAX?-1:int(encoded);
        }
        const auto cells=reader.u64();
        if(cells>100000||cells>uint64_t(reader.bytes.size()-reader.offset)/4)
            throw std::invalid_argument("repeat cache component IDs are incomplete");
        match.triangles.reserve(size_t(cells));
        for(uint64_t j=0;j<cells;++j)match.triangles.push_back(reader.u32());
        data.matches.push_back(std::move(match));
    }
    if(reader.offset!=payload.size())throw std::invalid_argument("repeat cache has trailing bytes");
    validate_result(data,source,selected);return data;
}
std::string repeat_root(const char* root){
    if(!root||!*root)throw std::invalid_argument("empty repeat cache root");
    return std::string(root)+"/repeats";
}
}

MeshDiskCacheLoad repeat_disk_cache_load(const char* mesh_root,
    const std::string& namespace_utf8,const std::string& operation_sha256_hex,
    const std::string& source_fingerprint,uint64_t selected,
    RepeatResult& output,std::string& error){
    try{
        ScientificDiskCacheKey key{namespace_utf8,operation_sha256_hex};
        std::string payload;
        auto root=repeat_root(mesh_root);
        auto state=scientific_disk_cache_load(root.c_str(),key,payload,error);
        if(state!=MeshDiskCacheLoad::Hit)return state;
        auto decoded=decode(payload,source_fingerprint,selected);
        output=std::move(decoded);error.clear();return MeshDiskCacheLoad::Hit;
    }catch(const std::invalid_argument& e){error=e.what();return MeshDiskCacheLoad::Invalid;}
     catch(const std::bad_alloc&){error="out of memory reading repeat cache";return MeshDiskCacheLoad::IoError;}
     catch(const std::exception& e){error=e.what();return MeshDiskCacheLoad::IoError;}
}
bool repeat_disk_cache_store(const char* mesh_root,
    const std::string& namespace_utf8,const std::string& operation_sha256_hex,
    const std::string& source_fingerprint,const RepeatResult& data,
    std::string& error){
    try{
        auto payload=encode(source_fingerprint,data);
        ScientificDiskCacheKey key{namespace_utf8,operation_sha256_hex};
        auto root=repeat_root(mesh_root);
        return scientific_disk_cache_store(root.c_str(),key,payload,error);
    }catch(const std::exception& e){error=e.what();return false;}
}
}
