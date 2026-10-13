// SPDX-License-Identifier: GPL-3.0-or-later
#include "mesh_import_backend.hpp"

#include <vtkCellArray.h>
#include <vtkOBJReader.h>
#include <vtkPolyData.h>
#include <vtkSTLReader.h>
#include <vtkSmartPointer.h>
#include <vtkTriangleFilter.h>
#include <openssl/evp.h>
#include <array>
#include <algorithm>
#include <charconv>
#include <cctype>
#include <cmath>
#include <cstring>
#include <filesystem>
#include <fstream>
#include <limits>
#include <memory>
#include <map>
#include <sstream>
#include <stdexcept>
#include <string>

namespace gx3de_backend {
namespace {
namespace fs = std::filesystem;
constexpr uint64_t default_max_source_bytes = 256ull * 1024 * 1024;
constexpr uint64_t default_max_memory_bytes = 4096ull * 1024 * 1024;
constexpr uint64_t minimum_memory_bytes = 32ull * 1024 * 1024;
constexpr uint64_t maximum_memory_bytes = 1048576ull * 1024 * 1024;
constexpr size_t max_obj_record = 8ull * 1024 * 1024;

void check_cancel(MeshImportCancel cancel, void* user) {
    if (cancel && cancel(user)) throw std::runtime_error("mesh import cancelled");
}

std::string sha256_file(const fs::path& path, MeshImportCancel cancel, void* user) {
    std::ifstream input(path, std::ios::binary);
    if (!input) throw std::runtime_error("cannot read mesh source");
    std::unique_ptr<EVP_MD_CTX, decltype(&EVP_MD_CTX_free)> ctx(EVP_MD_CTX_new(), EVP_MD_CTX_free);
    if (!ctx || EVP_DigestInit_ex(ctx.get(), EVP_sha256(), nullptr) != 1)
        throw std::runtime_error("cannot initialize source SHA-256");
    std::array<char, 65536> buffer{};
    while (input) {
        check_cancel(cancel, user);
        input.read(buffer.data(), buffer.size());
        const auto n = input.gcount();
        if (n > 0 && EVP_DigestUpdate(ctx.get(), buffer.data(), size_t(n)) != 1)
            throw std::runtime_error("cannot hash mesh source");
    }
    if (!input.eof()) throw std::runtime_error("mesh source read failed");
    unsigned char digest[EVP_MAX_MD_SIZE]{};
    unsigned int size=0;
    if (EVP_DigestFinal_ex(ctx.get(), digest, &size) != 1 || size != 32)
        throw std::runtime_error("mesh source SHA-256 failed");
    static constexpr char hex[]="0123456789abcdef";
    std::string out(64, '0');
    for (size_t i=0;i<32;++i) {out[i*2]=hex[digest[i]>>4];out[i*2+1]=hex[digest[i]&15];}
    return out;
}

/* Preserve the viewer's checked parsing of all indexed OBJ records. Its VTK
 * reader can terminate on an out-of-range face index, so this must run first. */
void validate_obj_indices(const fs::path& source, MeshImportCancel cancel, void* user) {
    std::ifstream input(source, std::ios::binary);
    if (!input) throw std::runtime_error("cannot open OBJ source for validation");
    std::string line, tag;
    std::array<uint64_t,3> preceding{};
    auto checked_index = [&](const std::string& field, size_t kind) {
        if (field.empty()) throw std::runtime_error("OBJ indexed record has an empty required index");
        int64_t index=0;
        const char* begin=field.data();
        const auto parsed=std::from_chars(begin,begin+field.size(),index);
        if (parsed.ec != std::errc{} || parsed.ptr != begin+field.size() || index==0)
            throw std::runtime_error("OBJ indexed record has an invalid index");
        if (index>0 && uint64_t(index)>preceding[kind])
            throw std::runtime_error("OBJ indexed record references a missing element");
        if (index<0 && uint64_t(-(index+1))+1>preceding[kind])
            throw std::runtime_error("OBJ relative index precedes available elements");
    };
    uint64_t line_number=0;
    while (std::getline(input,line)) {
        if ((++line_number & 1023u)==0) check_cancel(cancel,user);
        if (line.size()>max_obj_record) throw std::runtime_error("OBJ record exceeds safety limit");
        std::istringstream record(line);
        if (!(record>>tag)) continue;
        if (tag=="v") {++preceding[0];continue;}
        if (tag=="vt") {++preceding[1];continue;}
        if (tag=="vn") {++preceding[2];continue;}
        if (tag!="f" && tag!="l" && tag!="p") continue;
        size_t vertices=0;
        std::string token;
        while (record>>token) {
            if (token[0]=='#') break;
            const auto first=token.find('/');
            const auto second=first==std::string::npos?first:token.find('/',first+1);
            if (second!=std::string::npos && token.find('/',second+1)!=std::string::npos)
                throw std::runtime_error("OBJ indexed record has too many fields");
            checked_index(token.substr(0,first),0);
            if (first!=std::string::npos) {
                const auto texture=token.substr(first+1,second==std::string::npos?
                                               std::string::npos:second-first-1);
                if (!texture.empty()) checked_index(texture,1);
                if (second!=std::string::npos) checked_index(token.substr(second+1),2);
            }
            ++vertices;
        }
        const size_t minimum=tag=="f"?3:tag=="l"?2:1;
        if (vertices<minimum) throw std::runtime_error("OBJ indexed record has too few vertices");
    }
    if (!input.eof()) throw std::runtime_error("OBJ validation read failed");
    check_cancel(cancel,user);
}

uint32_t little_u32(const unsigned char* p) {
    return uint32_t(p[0]) | (uint32_t(p[1])<<8) | (uint32_t(p[2])<<16) | (uint32_t(p[3])<<24);
}

uint64_t memory_budget(uint64_t requested){
    if(!requested)return default_max_memory_bytes;
    if(requested<minimum_memory_bytes||requested>maximum_memory_bytes)
        throw std::out_of_range("mesh import memory budget must be 32..1048576 MiB");
    return requested;
}

uint32_t binary_stl_count(const fs::path& source,uint64_t bytes){
    if(bytes<84 || (bytes-84)%50)return 0;
    std::ifstream input(source,std::ios::binary);
    if(!input)throw std::runtime_error("cannot read STL source header");
    std::array<unsigned char,84> header{};
    input.read(reinterpret_cast<char*>(header.data()),header.size());
    if(!input)throw std::runtime_error("cannot read STL source header");
    const uint32_t count=little_u32(header.data()+80);
    return count && bytes==84ull+uint64_t(count)*50 ? count : 0;
}

char obj_kind(const std::string& line){
    const auto first=line.find_first_not_of(" \t");
    if(first==std::string::npos||first+1>=line.size()||
       (line[first+1]!=' '&&line[first+1]!='\t'))return '\0';
    return line[first];
}

MeshData streaming_stl_preview(const fs::path& source,uint32_t triangles,uint64_t budget,
                               MeshImportCancel cancel,void* user){
    const uint64_t target=std::min<uint64_t>(100000,
        std::min<uint64_t>(std::max<uint64_t>(64,triangles/100),budget/1024));
    const uint64_t stride=std::max<uint64_t>(1,(uint64_t(triangles)+target-1)/target);
    std::ifstream input(source,std::ios::binary);
    if(!input)throw std::runtime_error("cannot open binary STL preview source");
    input.seekg(84);
    MeshData result;result.vertices.reserve(size_t(std::min<uint64_t>(target,triangles))*3);
    result.triangles.reserve(size_t(std::min<uint64_t>(target,triangles))*3);
    std::array<unsigned char,50> record{};
    for(uint64_t i=0;i<triangles;++i){
        if((i&1023u)==0)check_cancel(cancel,user);
        input.read(reinterpret_cast<char*>(record.data()),record.size());
        if(!input)throw std::runtime_error("truncated binary STL during preview scan");
        if(i%stride)continue;
        for(int vertex=0;vertex<3;++vertex){
            double xyz[3]{};
            for(int axis=0;axis<3;++axis){
                uint32_t bits=little_u32(record.data()+12+vertex*12+axis*4);
                float coordinate;std::memcpy(&coordinate,&bits,4);
                if(!std::isfinite(coordinate))
                    throw std::runtime_error("non-finite binary STL preview vertex");
                xyz[axis]=coordinate;
            }
            result.triangles.push_back(uint32_t(result.vertices.size()));
            result.vertices.push_back({xyz[0],xyz[1],xyz[2]});
        }
    }
    if(result.triangles.empty())throw std::runtime_error("binary STL preview has no triangles");
    return result;
}

bool streaming_obj_preview(const fs::path& source,uint64_t budget,MeshData& result,
                           MeshImportCancel cancel,void* user){
    uint64_t faces=0,vertex_count=0,lines=0;
    std::string line;std::ifstream input(source,std::ios::binary);
    if(!input)throw std::runtime_error("cannot open OBJ preview source");
    while(std::getline(input,line)){
        if((++lines&16383u)==0)check_cancel(cancel,user);
        if(line.size()>1048576)return false;
        const char tag=obj_kind(line);
        if(tag=='f')++faces;else if(tag=='v')++vertex_count;
    }
    if(input.bad())throw std::runtime_error("OBJ preview source scan failed");
    if(!faces||!vertex_count)return false;
    const uint64_t target=std::min<uint64_t>({30000,
        std::max<uint64_t>(64,faces/100),std::max<uint64_t>(64,budget/4096)});
    const uint64_t stride=std::max<uint64_t>(1,(faces+target-1)/target);
    input.clear();input.seekg(0);
    std::map<uint64_t,uint32_t> selected_vertices;
    uint64_t face_index=0;
    while(std::getline(input,line)){
        if(obj_kind(line)!='f')continue;
        uint64_t mixed=face_index++ + 0x9e3779b97f4a7c15ull;
        mixed=(mixed^(mixed>>30))*0xbf58476d1ce4e5b9ull;
        mixed=(mixed^(mixed>>27))*0x94d049bb133111ebull;
        mixed^=mixed>>31;
        if(mixed%stride!=0)continue;
        if((face_index&4095u)==0)check_cancel(cancel,user);
        if(line.size()>1048576)return false;
        std::istringstream row(line);std::string token;row>>token;
        std::vector<uint32_t> polygon;
        while(row>>token){
            const auto slash=token.find('/');
            if(slash!=std::string::npos)token.resize(slash);
            if(token.empty()||token[0]=='-'||token[0]=='+')return false;
            uint64_t index=0;auto parsed=std::from_chars(token.data(),token.data()+token.size(),index);
            if(parsed.ec!=std::errc{}||parsed.ptr!=token.data()+token.size()||
               index==0||index>vertex_count)return false;
            auto [it,inserted]=selected_vertices.emplace(index,uint32_t(selected_vertices.size()));
            polygon.push_back(it->second);
            if(selected_vertices.size()>150000)return false;
        }
        if(polygon.size()<3)return false;
        for(size_t i=1;i+1<polygon.size();++i){
            if(result.triangles.size()/3>=50000)break;
            result.triangles.push_back(polygon[0]);
            result.triangles.push_back(polygon[i]);
            result.triangles.push_back(polygon[i+1]);
        }
        if(result.triangles.size()/3>=50000)break;
    }
    if(input.bad())throw std::runtime_error("OBJ preview face scan failed");
    if(result.triangles.empty())return false;
    result.vertices.resize(selected_vertices.size());
    input.clear();input.seekg(0);
    uint64_t vertex_index=0,found=0;
    while(std::getline(input,line)){
        if(obj_kind(line)!='v')continue;
        if((++vertex_index&16383u)==0)check_cancel(cancel,user);
        const auto selected=selected_vertices.find(vertex_index);
        if(selected==selected_vertices.end())continue;
        std::istringstream row(line);std::string tag;double xyz[3]{};
        if(!(row>>tag>>xyz[0]>>xyz[1]>>xyz[2])||
           !std::isfinite(xyz[0])||!std::isfinite(xyz[1])||!std::isfinite(xyz[2]))return false;
        result.vertices[selected->second]={xyz[0],xyz[1],xyz[2]};++found;
    }
    if(input.bad())throw std::runtime_error("OBJ preview vertex scan failed");
    return found==selected_vertices.size();
}

bool looks_like_ascii_stl(const fs::path& source, MeshImportCancel cancel, void* user) {
    std::ifstream input(source,std::ios::binary);
    if (!input) throw std::runtime_error("cannot inspect STL text header");
    char prefix[5]{};
    input.read(prefix,sizeof(prefix));
    if (input.gcount()!=sizeof(prefix)) return false;
    static constexpr char solid[]="solid";
    for (size_t i=0;i<sizeof(prefix);++i)
        if (std::tolower(static_cast<unsigned char>(prefix[i]))!=solid[i]) return false;
    std::array<char,65536> buffer{};
    while (input) {
        check_cancel(cancel,user);
        input.read(buffer.data(),buffer.size());
        for (std::streamsize i=0;i<input.gcount();++i) {
            const unsigned char c=static_cast<unsigned char>(buffer[size_t(i)]);
            if (c<32 && c!='\t' && c!='\r' && c!='\n') return false;
            if (c==127) return false;
        }
    }
    if (!input.eof()) throw std::runtime_error("STL text inspection failed");
    return true;
}

/* Validate binary STL length and finite vertex coordinates before VTK. ASCII
 * STL is delegated to VTK and all returned coordinates are checked below. */
void validate_binary_stl(const fs::path& source, uint64_t source_size,
                         MeshImportCancel cancel, void* user) {
    if (source_size<84) {
        if (!looks_like_ascii_stl(source,cancel,user))
            throw std::runtime_error("binary STL is truncated");
        return;
    }
    std::ifstream input(source,std::ios::binary);
    if (!input) throw std::runtime_error("cannot open STL source for validation");
    std::array<unsigned char,84> header{};
    input.read(reinterpret_cast<char*>(header.data()),header.size());
    if (!input) throw std::runtime_error("cannot read STL header");
    const uint32_t count=little_u32(header.data()+80);
    if (!count || source_size!=84ull+uint64_t(count)*50) {
        if (looks_like_ascii_stl(source,cancel,user)) return;
        throw std::runtime_error("binary STL length does not match triangle count");
    }
    if (!std::numeric_limits<float>::is_iec559)
        throw std::runtime_error("binary STL requires IEEE 754 floats");
    std::array<unsigned char,50> record{};
    for (uint32_t i=0;i<count;++i) {
        if ((i&1023u)==0) check_cancel(cancel,user);
        input.read(reinterpret_cast<char*>(record.data()),record.size());
        if (!input) throw std::runtime_error("truncated binary STL");
        for (int vertex=0;vertex<3;++vertex) for (int axis=0;axis<3;++axis) {
            const uint32_t bits=little_u32(record.data()+12+vertex*12+axis*4);
            float coordinate=0;
            std::memcpy(&coordinate,&bits,sizeof(coordinate));
            if (!std::isfinite(coordinate)) throw std::runtime_error("non-finite binary STL vertex");
        }
    }
}

MeshData triangle_mesh(vtkPolyData* poly) {
    if (!poly || !poly->GetPoints() || poly->GetNumberOfPoints()<=0)
        throw std::runtime_error("mesh source has no vertices");
    vtkNew<vtkTriangleFilter> triangulator;
    triangulator->SetInputData(poly);
    triangulator->PassLinesOff();
    triangulator->PassVertsOff();
    triangulator->Update();
    vtkPolyData* triangles=triangulator->GetOutput();
    if (!triangles || !triangles->GetPolys() || triangles->GetNumberOfPolys()<=0)
        throw std::runtime_error("mesh source has no triangles");
    const auto points=triangles->GetNumberOfPoints();
    const auto faces=triangles->GetNumberOfPolys();
    if (points>vtkIdType(UINT32_MAX) || uint64_t(faces)>SIZE_MAX/3)
        throw std::runtime_error("mesh source exceeds index range");
    MeshData result;
    result.vertices.reserve(size_t(points));
    result.triangles.reserve(size_t(faces)*3);
    for (vtkIdType i=0;i<points;++i) {
        double p[3]{};
        triangles->GetPoint(i,p);
        if (!std::isfinite(p[0]) || !std::isfinite(p[1]) || !std::isfinite(p[2]))
            throw std::runtime_error("non-finite mesh source vertex");
        result.vertices.push_back({p[0],p[1],p[2]});
    }
    vtkIdType n=0;const vtkIdType* ids=nullptr;
    auto* cells=triangles->GetPolys();
    cells->InitTraversal();
    while (cells->GetNextCell(n,ids)) {
        if (n!=3 || !ids) throw std::runtime_error("mesh triangulation returned a non-triangle");
        for (int i=0;i<3;++i) {
            if (ids[i]<0 || ids[i]>=points) throw std::runtime_error("mesh triangulation returned an invalid index");
            result.triangles.push_back(uint32_t(ids[i]));
        }
    }
    if (result.triangles.empty()) throw std::runtime_error("mesh source has no triangles");
    return result;
}
} // namespace

MeshSourceStatus mesh_source_preflight(const char* path_utf8,MeshImportFormat format,
    uint64_t max_source_bytes,uint64_t max_memory_bytes,bool full_import,
    std::string& error){
    try{
        if(!path_utf8||!*path_utf8||
           (format!=MeshImportFormat::Obj&&format!=MeshImportFormat::Stl)){
            error="invalid mesh source path or format";return MeshSourceStatus::Invalid;
        }
        const uint64_t budget=memory_budget(max_memory_bytes);
        const fs::path source=fs::u8path(path_utf8);
        std::error_code ec;
        if(!fs::is_regular_file(source,ec)||ec){error="mesh source is not a regular file";return MeshSourceStatus::NotFound;}
        const uint64_t bytes=fs::file_size(source,ec);
        if(ec){error="cannot inspect mesh source size";return MeshSourceStatus::Invalid;}
        const uint64_t limit=max_source_bytes?max_source_bytes:default_max_source_bytes;
        if(!bytes||bytes>limit){error="mesh source is empty or exceeds source-byte limit";return MeshSourceStatus::Range;}
        if(full_import){
            uint64_t estimate=0;
            if(bytes>UINT64_MAX/16){error="mesh memory estimate overflows";return MeshSourceStatus::Range;}
            if(format==MeshImportFormat::Stl){
                const uint32_t triangles=binary_stl_count(source,bytes);
                estimate=triangles?uint64_t(triangles)*640:bytes*16;
            }else{
                estimate=bytes*16;
            }
            if(estimate>budget){error="mesh source exceeds configured import memory budget";return MeshSourceStatus::Range;}
        }
        error.clear();return MeshSourceStatus::Ok;
    }catch(const std::out_of_range& e){error=e.what();return MeshSourceStatus::Range;}
    catch(const std::exception& e){error=e.what();return MeshSourceStatus::Invalid;}
}

bool import_mesh_file(const char* path_utf8, MeshImportFormat format,
                      uint64_t max_source_bytes,uint64_t max_memory_bytes,MeshData& output,
                      std::string& source_sha256_hex, std::string& error,
                      MeshImportCancel cancel, void* cancel_user,
                      MeshImportProgress progress, void* progress_user) {
    try {
        if (!path_utf8 || !*path_utf8 ||
            (format!=MeshImportFormat::Obj && format!=MeshImportFormat::Stl))
            throw std::runtime_error("invalid mesh import path or format");
        check_cancel(cancel,cancel_user);
        std::string limit_error;
        if(mesh_source_preflight(path_utf8,format,max_source_bytes,max_memory_bytes,
                                 true,limit_error)!=MeshSourceStatus::Ok)
            throw std::runtime_error(limit_error);
        const fs::path source=fs::u8path(path_utf8);
        std::error_code ec;
        if (!fs::is_regular_file(source,ec) || ec)
            throw std::runtime_error("mesh source is not a regular file");
        const uint64_t bytes=fs::file_size(source,ec);
        if (ec) throw std::runtime_error("cannot inspect mesh source size");
        const uint64_t limit=max_source_bytes?max_source_bytes:default_max_source_bytes;
        if (!bytes || bytes>limit) throw std::runtime_error("mesh source is empty or exceeds source-byte limit");
        if (progress) progress(progress_user,100);
        const std::string before=sha256_file(source,cancel,cancel_user);
        if (progress) progress(progress_user,300);
        if (format==MeshImportFormat::Obj) validate_obj_indices(source,cancel,cancel_user);
        else validate_binary_stl(source,bytes,cancel,cancel_user);
        check_cancel(cancel,cancel_user);
        if (progress) progress(progress_user,450);
        vtkSmartPointer<vtkPolyData> raw;
        if (format==MeshImportFormat::Obj) {
            vtkNew<vtkOBJReader> reader;
            reader->SetFileName(source.string().c_str());
            reader->Update();
            raw=reader->GetOutput();
        } else {
            vtkNew<vtkSTLReader> reader;
            reader->SetFileName(source.string().c_str());
            reader->Update();
            raw=reader->GetOutput();
        }
        check_cancel(cancel,cancel_user);
        if (progress) progress(progress_user,750);
        MeshData mesh=triangle_mesh(raw);
        if (progress) progress(progress_user,900);
        const std::string after=sha256_file(source,cancel,cancel_user);
        const uint64_t final_bytes=fs::file_size(source,ec);
        if (ec || final_bytes!=bytes || after!=before)
            throw std::runtime_error("mesh source changed during import");
        if (progress) progress(progress_user,990);
        output=std::move(mesh);
        source_sha256_hex=before;
        error.clear();
        return true;
    } catch (const std::bad_alloc&) {
        error="out of memory during mesh import";
    } catch (const std::exception& e) {
        error=e.what();
    }
    return false;
}

MeshPreviewStatus preview_mesh_file(const char* path_utf8,MeshImportFormat format,
    uint64_t max_source_bytes,uint64_t max_memory_bytes,MeshData& output,
    std::string& source_sha256_hex,std::string& error,
    MeshImportCancel cancel,void* cancel_user){
    try{
        check_cancel(cancel,cancel_user);
        if(mesh_source_preflight(path_utf8,format,max_source_bytes,max_memory_bytes,
                                 false,error)!=MeshSourceStatus::Ok)
            return MeshPreviewStatus::Invalid;
        const fs::path source=fs::u8path(path_utf8);
        const uint64_t budget=memory_budget(max_memory_bytes);
        const uint64_t bytes=fs::file_size(source);
        const auto before=sha256_file(source,cancel,cancel_user);
        MeshData result;
        if(format==MeshImportFormat::Stl){
            const uint32_t count=binary_stl_count(source,bytes);
            if(!count){
                if(looks_like_ascii_stl(source,cancel,cancel_user)){
                    error="streaming preview supports binary STL only";
                    return MeshPreviewStatus::Unsupported;
                }
                throw std::runtime_error("binary STL length does not match triangle count");
            }
            validate_binary_stl(source,bytes,cancel,cancel_user);
            result=streaming_stl_preview(source,count,budget,cancel,cancel_user);
        }else{
            validate_obj_indices(source,cancel,cancel_user);
            if(!streaming_obj_preview(source,budget,result,cancel,cancel_user)){
                error="OBJ preview requires bounded positive absolute face indices";
                return MeshPreviewStatus::Unsupported;
            }
        }
        check_cancel(cancel,cancel_user);
        const auto after=sha256_file(source,cancel,cancel_user);
        if(bytes!=fs::file_size(source)||before!=after)
            throw std::runtime_error("mesh source changed during preview");
        output=std::move(result);source_sha256_hex=before;error.clear();
        return MeshPreviewStatus::Success;
    }catch(const std::bad_alloc&){error="out of memory generating mesh preview";}
    catch(const std::exception& e){error=e.what();}
    return MeshPreviewStatus::Invalid;
}
} // namespace gx3de_backend
