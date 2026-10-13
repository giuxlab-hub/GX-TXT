// SPDX-License-Identifier: GPL-3.0-or-later
#include "scientific_backend.hpp"

#include <vtkCell.h>
#include <vtkCellArray.h>
#include <vtkCellData.h>
#include <vtkContourFilter.h>
#include <vtkDataArray.h>
#include <vtkDataObject.h>
#include <vtkDataSet.h>
#include <vtkDoubleArray.h>
#include <vtkFieldData.h>
#include <vtkImageData.h>
#include <vtkInformation.h>
#include <vtkMatrix3x3.h>
#include <vtkNew.h>
#include <vtkPointData.h>
#include <vtkPoints.h>
#include <vtkStreamingDemandDrivenPipeline.h>
#include <vtkPolyData.h>
#include <vtkTriangleFilter.h>
#include <vtkUnstructuredGrid.h>
#include <vtkVersion.h>
#include <vtkXMLImageDataReader.h>
#include <vtkXMLPolyDataReader.h>
#include <vtkXMLPolyDataWriter.h>
#include <vtkXMLUnstructuredDataReader.h>
#include <vtkXMLUnstructuredGridReader.h>
#include <vtkCellType.h>
#include <openssl/evp.h>

#include <array>
#include <cmath>
#include <cstring>
#include <filesystem>
#include <fstream>
#include <limits>
#include <memory>
#include <stdexcept>
#include <type_traits>
#include <string>
#include <unordered_set>
#include <vector>

namespace gx3de_backend {
namespace {
namespace fs=std::filesystem;
constexpr uint64_t default_max_source_bytes=256ull*1024*1024;
constexpr uint64_t default_max_decoded_bytes=256ull*1024*1024;
constexpr uint64_t max_points=10000000;
constexpr uint64_t max_cells=10000000;
constexpr uint64_t max_cell_references=30000000;
constexpr uint64_t max_arrays=256;
constexpr int max_components=16;

using DigestContext=std::unique_ptr<EVP_MD_CTX,decltype(&EVP_MD_CTX_free)>;

DigestContext new_digest() {
    DigestContext ctx(EVP_MD_CTX_new(),EVP_MD_CTX_free);
    if (!ctx || EVP_DigestInit_ex(ctx.get(),EVP_sha256(),nullptr)!=1)
        throw std::runtime_error("cannot initialize scientific SHA-256");
    return ctx;
}
void digest_add(EVP_MD_CTX* ctx,const void* bytes,size_t count) {
    if (count && EVP_DigestUpdate(ctx,bytes,count)!=1)
        throw std::runtime_error("cannot update scientific SHA-256");
}
void digest_u64(EVP_MD_CTX* ctx,uint64_t value) {
    unsigned char bytes[8]{};
    for (int i=0;i<8;++i) bytes[i]=static_cast<unsigned char>(value>>(i*8));
    digest_add(ctx,bytes,8);
}
void digest_double(EVP_MD_CTX* ctx,double value) {
    static_assert(sizeof(double)==sizeof(uint64_t),"binary64 required");
    uint64_t bits=0;
    std::memcpy(&bits,&value,sizeof(bits));
    digest_u64(ctx,bits);
}
void digest_string(EVP_MD_CTX* ctx,const std::string& value) {
    digest_u64(ctx,value.size());
    digest_add(ctx,value.data(),value.size());
}
std::string digest_finish(EVP_MD_CTX* ctx) {
    unsigned char digest[EVP_MAX_MD_SIZE]{};
    unsigned int count=0;
    if (EVP_DigestFinal_ex(ctx,digest,&count)!=1 || count!=32)
        throw std::runtime_error("scientific SHA-256 failed");
    constexpr char hex[]="0123456789abcdef";
    std::string result(64,'0');
    for (size_t i=0;i<32;++i) {
        result[i*2]=hex[digest[i]>>4];
        result[i*2+1]=hex[digest[i]&15];
    }
    return result;
}
std::string sha256_file(const fs::path& path) {
    std::ifstream input(path,std::ios::binary);
    if (!input) throw std::runtime_error("cannot read scientific source");
    auto ctx=new_digest();
    std::array<char,65536> buffer{};
    while (input) {
        input.read(buffer.data(),buffer.size());
        digest_add(ctx.get(),buffer.data(),size_t(input.gcount()));
    }
    if (!input.eof()) throw std::runtime_error("scientific source read failed");
    return digest_finish(ctx.get());
}

bool valid_utf8(const char* text,size_t size) {
    for(size_t i=0;i<size;){
        const auto first=static_cast<unsigned char>(text[i]);
        size_t count=0;
        if(first<0x80){if(first<0x20)return false;++i;continue;}
        if(first>=0xc2&&first<=0xdf)count=2;
        else if(first>=0xe0&&first<=0xef)count=3;
        else if(first>=0xf0&&first<=0xf4)count=4;
        else return false;
        if(i+count>size)return false;
        for(size_t j=1;j<count;++j)
            if((static_cast<unsigned char>(text[i+j])&0xc0)!=0x80)return false;
        const auto second=static_cast<unsigned char>(text[i+1]);
        if((first==0xe0&&second<0xa0)||(first==0xed&&second>=0xa0)||
           (first==0xf0&&second<0x90)||(first==0xf4&&second>=0x90))return false;
        i+=count;
    }
    return true;
}

std::string checked_name(const char* name) {
    if (!name) throw std::runtime_error("scientific array name is null");
    size_t count=0;
    while (count<=255 && name[count]) ++count;
    if (!count || count>255 || !valid_utf8(name,count))
        throw std::runtime_error("scientific array name is not valid UTF-8 or its length is invalid");
    return std::string(name,count);
}

void validate_arrays(vtkFieldData* fields,vtkIdType expected,const char* association) {
    if (!fields) return;
    if (fields->GetNumberOfArrays()<0 || fields->GetNumberOfArrays()>int(max_arrays))
        throw std::runtime_error("scientific array count exceeds limit");
    std::unordered_set<std::string> names;
    for (int i=0;i<fields->GetNumberOfArrays();++i) {
        vtkDataArray* array=fields->GetArray(i);
        if (!array) continue; // Non-numeric VTK metadata is not a numeric field.
        const char* name=array->GetName();
        if (!name || !*name || std::strlen(name)>255 ||
            !valid_utf8(name,std::strlen(name)) || !names.emplace(name).second)
            throw std::runtime_error(std::string(association)+" numeric array has missing or duplicate name");
        const int components=array->GetNumberOfComponents();
        if (components<1 || components>max_components || array->GetNumberOfTuples()!=expected)
            throw std::runtime_error(std::string(association)+" numeric array has invalid component or tuple count");
        for (vtkIdType t=0;t<expected;++t) for (int c=0;c<components;++c)
            if (!std::isfinite(array->GetComponent(t,c)))
                throw std::runtime_error(std::string(association)+" numeric array contains a non-finite value");
    }
}

void validate_dataset(vtkDataSet* data,bool allow_empty) {
    if (!data) throw std::runtime_error("scientific reader produced no dataset");
    const vtkIdType point_count=data->GetNumberOfPoints();
    const vtkIdType cell_count=data->GetNumberOfCells();
    if (point_count<0 || cell_count<0 || uint64_t(point_count)>max_points || uint64_t(cell_count)>max_cells)
        throw std::runtime_error("scientific dataset exceeds point/cell limit");
    if (!allow_empty && !point_count)
        throw std::runtime_error("scientific source has no points");
    if (allow_empty && !point_count && cell_count)
        throw std::runtime_error("scientific empty result contains cells");
    for (vtkIdType i=0;i<point_count;++i) {
        double point[3]{};
        data->GetPoint(i,point);
        if (!std::isfinite(point[0]) || !std::isfinite(point[1]) || !std::isfinite(point[2]))
            throw std::runtime_error("scientific dataset contains non-finite coordinates");
    }
    uint64_t references=0;
    for (vtkIdType i=0;i<cell_count;++i) {
        vtkCell* cell=data->GetCell(i);
        if (!cell || cell->GetNumberOfPoints()<1)
            throw std::runtime_error("scientific dataset contains an invalid cell");
        references+=uint64_t(cell->GetNumberOfPoints());
        if (references>max_cell_references)
            throw std::runtime_error("scientific dataset exceeds cell-reference limit");
        for (vtkIdType j=0;j<cell->GetNumberOfPoints();++j) {
            const vtkIdType id=cell->GetPointId(j);
            if (id<0 || id>=point_count)
                throw std::runtime_error("scientific cell references an invalid point");
        }
    }
    validate_arrays(data->GetPointData(),point_count,"point");
    validate_arrays(data->GetCellData(),cell_count,"cell");
}

template<class Reader>
vtkSmartPointer<vtkDataSet> read_xml(const fs::path& path,bool implicit_points) {
    vtkNew<Reader> reader;
    const std::string filename=path.u8string();
    if (!reader->CanReadFile(filename.c_str()))
        throw std::runtime_error("scientific source is not a supported VTK XML dataset of the requested type");
    reader->SetFileName(filename.c_str());
    reader->UpdateInformation();
    if constexpr(std::is_base_of_v<vtkXMLUnstructuredDataReader,Reader>)
        reader->SetupUpdateExtent(0,1,0);
    vtkIdType before_points=reader->GetNumberOfPoints();
    vtkIdType before_cells=reader->GetNumberOfCells();
    if(implicit_points){
        auto* info=reader->GetOutputInformation(0);
        if(!info||!info->Has(vtkStreamingDemandDrivenPipeline::WHOLE_EXTENT()))
            throw std::runtime_error("scientific image XML has no whole extent");
        int extent[6]{};
        vtkStreamingDemandDrivenPipeline::GetWholeExtent(info,extent);
        uint64_t point_product=1,cell_product=1;
        for(int axis=0;axis<3;++axis){
            const int64_t dimension=int64_t(extent[2*axis+1])-extent[2*axis]+1;
            if(dimension<1||uint64_t(dimension)>max_points/point_product)
                throw std::runtime_error("scientific XML metadata exceeds point/cell limits");
            point_product*=uint64_t(dimension);
            cell_product*=uint64_t(std::max<int64_t>(dimension-1,1));
        }
        before_points=vtkIdType(point_product);
        before_cells=vtkIdType(cell_product);
    }
    if(before_points<1 || before_cells<0 || uint64_t(before_points)>max_points ||
       uint64_t(before_cells)>max_cells)
        throw std::runtime_error("scientific XML metadata exceeds point/cell limits");
    const int point_arrays=reader->GetNumberOfPointArrays();
    const int cell_arrays=reader->GetNumberOfCellArrays();
    if(point_arrays<0||cell_arrays<0||point_arrays>int(max_arrays)||cell_arrays>int(max_arrays))
        throw std::runtime_error("scientific XML metadata exceeds array limits");
    /* VTI coordinates/cells are implicit. Polydata/VTU have at least three
     * doubles per point and one connectivity ID per cell. Each numeric field
     * needs at least one byte per tuple. This conservative lower bound can
     * reject a compressed oversized source before VTK decompresses arrays. */
    uint64_t minimum_bytes=0;
    auto add_minimum=[&](uint64_t count,uint64_t bytes_per_tuple){
        if(bytes_per_tuple && count>(default_max_decoded_bytes-minimum_bytes)/bytes_per_tuple)
            throw std::runtime_error("scientific XML exceeds 256 MiB decoded-data budget");
        minimum_bytes+=count*bytes_per_tuple;
    };
    if(!implicit_points){
        add_minimum(uint64_t(before_points),24);
        add_minimum(uint64_t(before_cells),8);
    }
    add_minimum(uint64_t(before_points),uint64_t(point_arrays));
    add_minimum(uint64_t(before_cells),uint64_t(cell_arrays));
    if(minimum_bytes>default_max_decoded_bytes)
        throw std::runtime_error("scientific XML exceeds 256 MiB decoded-data budget");
    reader->Update();
    auto* raw=reader->GetOutput();
    if (!raw) throw std::runtime_error("scientific VTK XML reader returned no data");
    if(uint64_t(raw->GetActualMemorySize())>
       (default_max_decoded_bytes+1023)/1024)
        throw std::runtime_error("scientific XML exceeds 256 MiB decoded-data budget");
    validate_dataset(raw,false);
    vtkSmartPointer<vtkDataSet> data;
    data.TakeReference(raw->NewInstance());
    data->DeepCopy(raw); // Result lifetime is independent of the reader/pipeline.
    if(uint64_t(data->GetActualMemorySize())>
       (default_max_decoded_bytes+1023)/1024)
        throw std::runtime_error("scientific XML exceeds 256 MiB decoded-data budget");
    return data;
}

std::string memory_fingerprint(const gx3de_scientific_polydata_spec& spec) {
    auto ctx=new_digest();
    digest_string(ctx.get(),"GX3DE_SCIPOLY_v1");
    digest_u64(ctx.get(),spec.point_count);
    for (uint64_t i=0;i<spec.point_count;++i) {
        digest_double(ctx.get(),spec.points[i].x);
        digest_double(ctx.get(),spec.points[i].y);
        digest_double(ctx.get(),spec.points[i].z);
    }
    digest_u64(ctx.get(),spec.cell_count);
    for (uint64_t i=0;i<spec.cell_count;++i) {
        const auto& cell=spec.cells[i];
        digest_u64(ctx.get(),cell.type);
        digest_u64(ctx.get(),cell.point_count);
        for (uint64_t j=0;j<cell.point_count;++j) digest_u64(ctx.get(),cell.point_ids[j]);
    }
    digest_u64(ctx.get(),spec.array_count);
    for (uint64_t i=0;i<spec.array_count;++i) {
        const auto& array=spec.arrays[i];
        digest_string(ctx.get(),checked_name(array.name_utf8));
        digest_u64(ctx.get(),array.association);
        digest_u64(ctx.get(),array.components);
        digest_u64(ctx.get(),array.tuple_count);
        for (uint64_t j=0;j<array.tuple_count*array.components;++j)
            digest_double(ctx.get(),array.values[j]);
    }
    return digest_finish(ctx.get());
}

std::string contour_fingerprint(const ScientificData& source,
                                const std::string& scalar,double isovalue) {
    auto ctx=new_digest();
    digest_string(ctx.get(),"GX3DE_VTK_CONTOUR_TRIANGLES_v1");
    digest_string(ctx.get(),vtkVersion::GetVTKVersion());
    digest_string(ctx.get(),source.fingerprint_sha256_hex);
    digest_string(ctx.get(),scalar);
    digest_double(ctx.get(),isovalue);
    return digest_finish(ctx.get());
}

void require_input_size(uint32_t given,size_t expected,const char* kind) {
    if (given<expected) throw std::runtime_error(std::string(kind)+" descriptor is too small");
}

} // namespace

bool import_scientific_file(const char* path_utf8,ScientificFormat format,
                            uint64_t max_source_bytes,ScientificData& output,
                            std::string& error) {
    try {
        if (!path_utf8 || !*path_utf8 ||
            (format!=ScientificFormat::Vtp && format!=ScientificFormat::Vtu && format!=ScientificFormat::Vti))
            throw std::runtime_error("invalid scientific import path or format");
        const fs::path path=fs::u8path(path_utf8);
        const char* expected=format==ScientificFormat::Vtp?".vtp":format==ScientificFormat::Vtu?".vtu":".vti";
        if (path.extension()!=expected)
            throw std::runtime_error("scientific source extension does not match requested format");
        std::error_code ec;
        if (!fs::is_regular_file(path,ec) || ec)
            throw std::runtime_error("scientific source is not a regular file");
        const uint64_t bytes=fs::file_size(path,ec);
        const uint64_t limit=max_source_bytes?max_source_bytes:default_max_source_bytes;
        if (ec || !bytes || bytes>limit)
            throw std::runtime_error("scientific source is empty or exceeds source-byte limit");
        const std::string before=sha256_file(path);
        vtkSmartPointer<vtkDataSet> data;
        if (format==ScientificFormat::Vtp) data=read_xml<vtkXMLPolyDataReader>(path,false);
        else if (format==ScientificFormat::Vtu) data=read_xml<vtkXMLUnstructuredGridReader>(path,false);
        else data=read_xml<vtkXMLImageDataReader>(path,true);
        validate_dataset(data,false);
        const std::string after=sha256_file(path);
        const uint64_t final_bytes=fs::file_size(path,ec);
        if (ec || final_bytes!=bytes || before!=after)
            throw std::runtime_error("scientific source changed during import");
        ScientificData result;
        result.dataset=std::move(data);
        result.format=format;
        result.source_sha256_hex=before;
        result.fingerprint_sha256_hex=before;
        output=std::move(result);
        error.clear();
        return true;
    } catch (const std::bad_alloc&) {
        error="out of memory during scientific import";
    } catch (const std::exception& e) {
        error=e.what();
    }
    return false;
}

bool create_scientific_polydata(const gx3de_scientific_polydata_spec& spec,
                               ScientificData& output,std::string& error) {
    try {
        require_input_size(spec.struct_size,sizeof(spec),"scientific polydata");
        if (!spec.point_count || spec.point_count>max_points || spec.cell_count>max_cells ||
            spec.array_count>max_arrays || !spec.points ||
            (spec.cell_count && !spec.cells) || (spec.array_count && !spec.arrays))
            throw std::runtime_error("scientific polydata count or pointer is invalid");
        uint64_t input_bytes=spec.point_count*3*sizeof(double);
        if (input_bytes>default_max_source_bytes)
            throw std::runtime_error("scientific polydata exceeds 256 MiB input-data budget");
        uint64_t planned_bytes=input_bytes;
        for (uint64_t i=0;i<spec.cell_count;++i) {
            const auto& cell=spec.cells[i];
            require_input_size(cell.struct_size,sizeof(cell),"scientific cell");
            if (cell.point_count>(default_max_source_bytes-planned_bytes)/sizeof(uint64_t))
                throw std::runtime_error("scientific polydata exceeds 256 MiB input-data budget");
            planned_bytes+=cell.point_count*sizeof(uint64_t);
        }
        for (uint64_t i=0;i<spec.array_count;++i) {
            const auto& array=spec.arrays[i];
            require_input_size(array.struct_size,sizeof(array),"scientific array");
            if (array.components<1 || array.components>max_components ||
                array.tuple_count>(default_max_source_bytes-planned_bytes)/
                    (sizeof(double)*array.components))
                throw std::runtime_error("scientific polydata exceeds 256 MiB input-data budget");
            planned_bytes+=array.tuple_count*array.components*sizeof(double);
        }
        vtkNew<vtkPoints> points;
        points->SetDataTypeToDouble();
        for (uint64_t i=0;i<spec.point_count;++i) {
            const auto& p=spec.points[i];
            if (!std::isfinite(p.x) || !std::isfinite(p.y) || !std::isfinite(p.z))
                throw std::runtime_error("scientific polydata contains a non-finite point");
            points->InsertNextPoint(p.x,p.y,p.z);
        }
        vtkNew<vtkCellArray> verts,lines,polys;
        std::vector<uint64_t> vert_order,line_order,poly_order;
        uint64_t references=0;
        for (uint64_t i=0;i<spec.cell_count;++i) {
            const auto& cell=spec.cells[i];
            require_input_size(cell.struct_size,sizeof(cell),"scientific cell");
            const uint64_t n=cell.point_count;
            if (!cell.point_ids || n>max_cell_references-references ||
                ((cell.type==GX3DE_SCI_CELL_VERTEX && n!=1) ||
                 (cell.type==GX3DE_SCI_CELL_LINE && n!=2) ||
                 (cell.type==GX3DE_SCI_CELL_POLYLINE && n<2) ||
                 (cell.type==GX3DE_SCI_CELL_TRIANGLE && n!=3) ||
                 (cell.type==GX3DE_SCI_CELL_POLYGON && n<3)))
                throw std::runtime_error("scientific cell type or point count is invalid");
            if (cell.type<GX3DE_SCI_CELL_VERTEX || cell.type>GX3DE_SCI_CELL_POLYGON)
                throw std::runtime_error("unsupported scientific cell type");
            if (n>(default_max_source_bytes-input_bytes)/sizeof(uint64_t))
                throw std::runtime_error("scientific polydata exceeds 256 MiB input-data budget");
            input_bytes+=n*sizeof(uint64_t);
            references+=n;
            std::vector<vtkIdType> ids;
            ids.reserve(size_t(n));
            std::unordered_set<uint64_t> seen;
            for (uint64_t j=0;j<n;++j) {
                const uint64_t id=cell.point_ids[j];
                if (id>=spec.point_count || !seen.emplace(id).second)
                    throw std::runtime_error("scientific cell contains an invalid or repeated point index");
                ids.push_back(vtkIdType(id));
            }
            if (cell.type==GX3DE_SCI_CELL_VERTEX) {
                verts->InsertNextCell(vtkIdType(n),ids.data());
                vert_order.push_back(i);
            } else if (cell.type==GX3DE_SCI_CELL_LINE || cell.type==GX3DE_SCI_CELL_POLYLINE) {
                lines->InsertNextCell(vtkIdType(n),ids.data());
                line_order.push_back(i);
            } else {
                polys->InsertNextCell(vtkIdType(n),ids.data());
                poly_order.push_back(i);
            }
        }
        std::vector<uint64_t> vtk_cell_order;
        vtk_cell_order.reserve(size_t(spec.cell_count));
        vtk_cell_order.insert(vtk_cell_order.end(),vert_order.begin(),vert_order.end());
        vtk_cell_order.insert(vtk_cell_order.end(),line_order.begin(),line_order.end());
        vtk_cell_order.insert(vtk_cell_order.end(),poly_order.begin(),poly_order.end());
        vtkNew<vtkPolyData> poly;
        poly->SetPoints(points);
        poly->SetVerts(verts);
        poly->SetLines(lines);
        poly->SetPolys(polys);
        std::unordered_set<std::string> point_names,cell_names;
        for (uint64_t a=0;a<spec.array_count;++a) {
            const auto& source=spec.arrays[a];
            require_input_size(source.struct_size,sizeof(source),"scientific array");
            const std::string name=checked_name(source.name_utf8);
            const bool point=source.association==GX3DE_SCI_ASSOC_POINT;
            if ((!point && source.association!=GX3DE_SCI_ASSOC_CELL) ||
                source.components<1 || source.components>max_components ||
                source.tuple_count!=(point?spec.point_count:spec.cell_count) ||
                (source.tuple_count && !source.values) ||
                !(point?point_names:cell_names).emplace(name).second)
                throw std::runtime_error("scientific array association, component or tuple definition is invalid");
            const uint64_t input_values=source.tuple_count*source.components;
            if (input_values>(default_max_source_bytes-input_bytes)/sizeof(double))
                throw std::runtime_error("scientific polydata exceeds 256 MiB input-data budget");
            input_bytes+=input_values*sizeof(double);
            vtkNew<vtkDoubleArray> values;
            values->SetName(name.c_str());
            values->SetNumberOfComponents(int(source.components));
            values->SetNumberOfTuples(vtkIdType(source.tuple_count));
            for (uint64_t t=0;t<source.tuple_count;++t) {
                const uint64_t source_tuple=point?t:vtk_cell_order[size_t(t)];
                for (uint32_t c=0;c<source.components;++c) {
                    const double value=source.values[source_tuple*source.components+c];
                    if (!std::isfinite(value))
                        throw std::runtime_error("scientific array contains a non-finite value");
                    values->SetComponent(vtkIdType(t),int(c),value);
                }
            }
            if (point) poly->GetPointData()->AddArray(values);
            else poly->GetCellData()->AddArray(values);
        }
        validate_dataset(poly,false);
        ScientificData result;
        result.dataset=poly;
        result.format=ScientificFormat::InMemoryPolydata;
        result.fingerprint_sha256_hex=memory_fingerprint(spec);
        output=std::move(result);
        error.clear();
        return true;
    } catch (const std::bad_alloc&) {
        error="out of memory while creating scientific polydata";
    } catch (const std::exception& e) {
        error=e.what();
    }
    return false;
}

bool create_scientific_image(const gx3de_scientific_image_spec& spec,
                             ScientificData& output,std::string& error) {
    try {
        require_input_size(spec.struct_size,sizeof(spec),"scientific image");
        if (spec.array_count>max_arrays || (spec.array_count && !spec.arrays))
            throw std::runtime_error("scientific image array count or pointer is invalid");
        uint64_t point_count=1;
        for (int axis=0;axis<3;++axis) {
            const int64_t dimension=int64_t(spec.extent[axis*2+1])-spec.extent[axis*2]+1;
            if (dimension<1 || uint64_t(dimension)>max_points/point_count)
                throw std::runtime_error("scientific image extent exceeds point budget");
            point_count*=uint64_t(dimension);
        }
        for (double value:{spec.origin.x,spec.origin.y,spec.origin.z,
                           spec.spacing.x,spec.spacing.y,spec.spacing.z})
            if (!std::isfinite(value))
                throw std::runtime_error("scientific image origin or spacing is non-finite");
        if (!spec.spacing.x || !spec.spacing.y || !spec.spacing.z)
            throw std::runtime_error("scientific image spacing must be nonzero");
        for (double value:spec.direction) if (!std::isfinite(value))
            throw std::runtime_error("scientific image direction is non-finite");
        const double* d=spec.direction;
        const double determinant=d[0]*(d[4]*d[8]-d[5]*d[7])-
                                 d[1]*(d[3]*d[8]-d[5]*d[6])+
                                 d[2]*(d[3]*d[7]-d[4]*d[6]);
        if (!std::isfinite(determinant) || std::abs(determinant)<=1e-12)
            throw std::runtime_error("scientific image direction is singular");
        vtkNew<vtkImageData> grid;
        grid->SetExtent(spec.extent[0],spec.extent[1],spec.extent[2],
                        spec.extent[3],spec.extent[4],spec.extent[5]);
        grid->SetOrigin(spec.origin.x,spec.origin.y,spec.origin.z);
        grid->SetSpacing(spec.spacing.x,spec.spacing.y,spec.spacing.z);
        vtkNew<vtkMatrix3x3> direction;
        for (int row=0;row<3;++row) for (int col=0;col<3;++col)
            direction->SetElement(row,col,d[row*3+col]);
        grid->SetDirectionMatrix(direction);
        const uint64_t cell_count=uint64_t(grid->GetNumberOfCells());
        if (cell_count>max_cells || uint64_t(grid->GetNumberOfPoints())!=point_count)
            throw std::runtime_error("scientific image geometry exceeds limits");
        const uint64_t byte_limit=spec.max_data_bytes?spec.max_data_bytes:default_max_source_bytes;
        uint64_t bytes=point_count*3*sizeof(double);
        if (bytes>byte_limit) throw std::runtime_error("scientific image exceeds data-byte budget");
        std::unordered_set<std::string> point_names,cell_names;
        auto ctx=new_digest();
        digest_string(ctx.get(),"GX3DE_SCIIMAGE_v1");
        for (int value:spec.extent) digest_u64(ctx.get(),uint32_t(value));
        for (double value:{spec.origin.x,spec.origin.y,spec.origin.z,
                           spec.spacing.x,spec.spacing.y,spec.spacing.z})digest_double(ctx.get(),value);
        for (double value:spec.direction)digest_double(ctx.get(),value);
        digest_u64(ctx.get(),spec.array_count);
        for (uint64_t a=0;a<spec.array_count;++a) {
            const auto& source=spec.arrays[a];
            require_input_size(source.struct_size,sizeof(source),"scientific array");
            const bool point=source.association==GX3DE_SCI_ASSOC_POINT;
            if (!point && source.association!=GX3DE_SCI_ASSOC_CELL)
                throw std::runtime_error("scientific image array association is invalid");
            const std::string name=checked_name(source.name_utf8);
            const uint64_t tuples=point?point_count:cell_count;
            if (source.components<1 || source.components>max_components ||
                source.tuple_count!=tuples || (tuples && !source.values) ||
                !(point?point_names:cell_names).emplace(name).second)
                throw std::runtime_error("scientific image array definition is invalid");
            const uint64_t values=tuples*source.components;
            if (values>(byte_limit-bytes)/sizeof(double))
                throw std::runtime_error("scientific image exceeds data-byte budget");
            bytes+=values*sizeof(double);
            digest_string(ctx.get(),name);
            digest_u64(ctx.get(),source.association);
            digest_u64(ctx.get(),source.components);
            digest_u64(ctx.get(),tuples);
            vtkNew<vtkDoubleArray> array;
            array->SetName(name.c_str());
            array->SetNumberOfComponents(int(source.components));
            array->SetNumberOfTuples(vtkIdType(tuples));
            for (uint64_t t=0;t<tuples;++t) for (uint32_t c=0;c<source.components;++c) {
                const double value=source.values[t*source.components+c];
                if (!std::isfinite(value))
                    throw std::runtime_error("scientific image array contains a non-finite value");
                array->SetComponent(vtkIdType(t),int(c),value);
                digest_double(ctx.get(),value);
            }
            if (point)grid->GetPointData()->AddArray(array);
            else grid->GetCellData()->AddArray(array);
        }
        validate_dataset(grid,false);
        ScientificData result;
        result.dataset=grid;
        result.format=ScientificFormat::InMemoryImage;
        result.fingerprint_sha256_hex=digest_finish(ctx.get());
        output=std::move(result);
        error.clear();
        return true;
    } catch (const std::bad_alloc&) {
        error="out of memory while creating scientific image";
    } catch (const std::exception& e) {
        error=e.what();
    }
    return false;
}

bool create_scientific_unstructured(const gx3de_scientific_unstructured_spec& spec,
                                    ScientificData& output,std::string& error) {
    try {
        require_input_size(spec.struct_size,sizeof(spec),"scientific unstructured grid");
        if (!spec.point_count || spec.point_count>max_points ||
            spec.cell_count>max_cells || spec.array_count>max_arrays || !spec.points ||
            (spec.cell_count && !spec.cells) || (spec.array_count && !spec.arrays))
            throw std::runtime_error("scientific unstructured count or pointer is invalid");
        const uint64_t byte_limit=spec.max_data_bytes?spec.max_data_bytes:default_max_source_bytes;
        uint64_t bytes=spec.point_count*3*sizeof(double);
        if (bytes>byte_limit)
            throw std::runtime_error("scientific unstructured grid exceeds data-byte budget");
        auto ctx=new_digest();
        digest_string(ctx.get(),"GX3DE_SCIUNSTRUCT_v1");
        digest_u64(ctx.get(),spec.point_count);
        vtkNew<vtkPoints> points;
        points->SetDataTypeToDouble();
        for (uint64_t i=0;i<spec.point_count;++i) {
            const auto p=spec.points[i];
            if (!std::isfinite(p.x) || !std::isfinite(p.y) || !std::isfinite(p.z))
                throw std::runtime_error("scientific unstructured point is non-finite");
            points->InsertNextPoint(p.x,p.y,p.z);
            digest_double(ctx.get(),p.x);digest_double(ctx.get(),p.y);digest_double(ctx.get(),p.z);
        }
        vtkNew<vtkUnstructuredGrid> grid;
        grid->SetPoints(points);
        digest_u64(ctx.get(),spec.cell_count);
        uint64_t references=0;
        for (uint64_t i=0;i<spec.cell_count;++i) {
            const auto& cell=spec.cells[i];
            require_input_size(cell.struct_size,sizeof(cell),"scientific cell");
            const uint64_t n=cell.point_count;
            int vtk_type=0;
            switch (cell.type) {
            case GX3DE_SCI_CELL_VERTEX:if(n==1)vtk_type=VTK_VERTEX;break;
            case GX3DE_SCI_CELL_LINE:if(n==2)vtk_type=VTK_LINE;break;
            case GX3DE_SCI_CELL_POLYLINE:if(n>=2)vtk_type=VTK_POLY_LINE;break;
            case GX3DE_SCI_CELL_TRIANGLE:if(n==3)vtk_type=VTK_TRIANGLE;break;
            case GX3DE_SCI_CELL_POLYGON:if(n>=3)vtk_type=VTK_POLYGON;break;
            case GX3DE_SCI_CELL_TETRA:if(n==4)vtk_type=VTK_TETRA;break;
            case GX3DE_SCI_CELL_HEXAHEDRON:if(n==8)vtk_type=VTK_HEXAHEDRON;break;
            default:break;
            }
            if (!vtk_type || !cell.point_ids || n>max_cell_references-references ||
                n>(byte_limit-bytes)/sizeof(uint64_t))
                throw std::runtime_error("scientific unstructured cell is invalid or over budget");
            references+=n;bytes+=n*sizeof(uint64_t);
            digest_u64(ctx.get(),cell.type);digest_u64(ctx.get(),n);
            std::vector<vtkIdType> ids;
            ids.reserve(size_t(n));
            std::unordered_set<uint64_t> seen;
            for (uint64_t j=0;j<n;++j) {
                const uint64_t id=cell.point_ids[j];
                if (id>=spec.point_count || !seen.emplace(id).second)
                    throw std::runtime_error("scientific unstructured cell has invalid or repeated point ID");
                ids.push_back(vtkIdType(id));
                digest_u64(ctx.get(),id);
            }
            grid->InsertNextCell(vtk_type,vtkIdType(n),ids.data());
        }
        std::unordered_set<std::string> point_names,cell_names;
        digest_u64(ctx.get(),spec.array_count);
        for (uint64_t a=0;a<spec.array_count;++a) {
            const auto& source=spec.arrays[a];
            require_input_size(source.struct_size,sizeof(source),"scientific array");
            const bool point=source.association==GX3DE_SCI_ASSOC_POINT;
            if (!point && source.association!=GX3DE_SCI_ASSOC_CELL)
                throw std::runtime_error("scientific unstructured array association is invalid");
            const std::string name=checked_name(source.name_utf8);
            const uint64_t tuples=point?spec.point_count:spec.cell_count;
            if (source.components<1 || source.components>max_components ||
                source.tuple_count!=tuples || (tuples && !source.values) ||
                !(point?point_names:cell_names).emplace(name).second)
                throw std::runtime_error("scientific unstructured array definition is invalid");
            const uint64_t values=tuples*source.components;
            if (values>(byte_limit-bytes)/sizeof(double))
                throw std::runtime_error("scientific unstructured grid exceeds data-byte budget");
            bytes+=values*sizeof(double);
            digest_string(ctx.get(),name);
            digest_u64(ctx.get(),source.association);
            digest_u64(ctx.get(),source.components);
            digest_u64(ctx.get(),tuples);
            vtkNew<vtkDoubleArray> array;
            array->SetName(name.c_str());
            array->SetNumberOfComponents(int(source.components));
            array->SetNumberOfTuples(vtkIdType(tuples));
            for (uint64_t t=0;t<tuples;++t) for (uint32_t c=0;c<source.components;++c) {
                const double value=source.values[t*source.components+c];
                if (!std::isfinite(value))
                    throw std::runtime_error("scientific unstructured array contains non-finite value");
                array->SetComponent(vtkIdType(t),int(c),value);
                digest_double(ctx.get(),value);
            }
            if (point)grid->GetPointData()->AddArray(array);
            else grid->GetCellData()->AddArray(array);
        }
        validate_dataset(grid,false);
        ScientificData result;
        result.dataset=grid;
        result.format=ScientificFormat::InMemoryUnstructured;
        result.fingerprint_sha256_hex=digest_finish(ctx.get());
        output=std::move(result);
        error.clear();
        return true;
    } catch (const std::bad_alloc&) {
        error="out of memory while creating scientific unstructured grid";
    } catch (const std::exception& e) {
        error=e.what();
    }
    return false;
}

bool contour_isovalues(const ScientificData& source,const std::string& scalar_name,
                       const std::vector<double>& isovalues,
                       std::vector<ScientificData>& outputs,std::string& error) {
    try {
        auto* grid=(source.format==ScientificFormat::Vti || source.format==ScientificFormat::InMemoryImage)?
            vtkImageData::SafeDownCast(source.dataset.GetPointer()):nullptr;
        if (!grid) throw std::runtime_error("isosurface source must be a VTI scalar grid");
        int dims[3]{};
        grid->GetDimensions(dims);
        if (dims[0]<2 || dims[1]<2 || dims[2]<2)
            throw std::runtime_error("isosurface source must be a 3D structured grid");
        if (scalar_name.empty() || scalar_name.size()>255)
            throw std::runtime_error("isosurface scalar array name is invalid");
        auto* scalars=scientific_array(source,GX3DE_SCI_ASSOC_POINT,scalar_name);
        if (!scalars || scalars->GetNumberOfComponents()!=1 ||
            scalars->GetNumberOfTuples()!=grid->GetNumberOfPoints())
            throw std::runtime_error("requested point scalar array is missing or not scalar");
        if (isovalues.empty() || isovalues.size()>32)
            throw std::runtime_error("isosurface requires 1..32 explicit values");
        std::vector<ScientificData> result;
        result.reserve(isovalues.size());
        for (double value:isovalues) {
            if (!std::isfinite(value))
                throw std::runtime_error("isosurface values must be finite");
            vtkNew<vtkContourFilter> contour;
            contour->SetInputData(grid);
            contour->SetInputArrayToProcess(0,0,0,
                vtkDataObject::FIELD_ASSOCIATION_POINTS,scalar_name.c_str());
            contour->SetValue(0,value);
            contour->ComputeNormalsOff();
            contour->Update();
            vtkNew<vtkTriangleFilter> triangulate;
            triangulate->SetInputConnection(contour->GetOutputPort());
            triangulate->PassVertsOff();
            triangulate->PassLinesOff();
            triangulate->Update();
            vtkNew<vtkPolyData> surface;
            surface->DeepCopy(triangulate->GetOutput());
            // A level touching only a point or line has no surface cells.
            // Return a canonical empty triangle surface in that case.
            if (!surface->GetNumberOfCells()) surface->Initialize();
            validate_dataset(surface,true);
            for (vtkIdType c=0;c<surface->GetNumberOfCells();++c) {
                auto* cell=surface->GetCell(c);
                if (!cell || cell->GetCellType()!=VTK_TRIANGLE || cell->GetNumberOfPoints()!=3)
                    throw std::runtime_error("isosurface output contains a non-triangle cell");
                double a[3]{},b[3]{},d[3]{};
                surface->GetPoint(cell->GetPointId(0),a);
                surface->GetPoint(cell->GetPointId(1),b);
                surface->GetPoint(cell->GetPointId(2),d);
                const double ux=b[0]-a[0],uy=b[1]-a[1],uz=b[2]-a[2];
                const double vx=d[0]-a[0],vy=d[1]-a[1],vz=d[2]-a[2];
                const double cx=uy*vz-uz*vy,cy=uz*vx-ux*vz,cz=ux*vy-uy*vx;
                if (!(std::hypot(std::hypot(cx,cy),cz)>0))
                    throw std::runtime_error("isosurface output contains a degenerate triangle");
            }
            ScientificData derived;
            derived.dataset=surface;
            derived.format=ScientificFormat::DerivedIsosurface;
            derived.source_sha256_hex=source.source_sha256_hex;
            derived.fingerprint_sha256_hex=contour_fingerprint(source,scalar_name,value);
            derived.selected_scalar=scalar_name;
            derived.isovalue=value;
            derived.derived=true;
            result.push_back(std::move(derived));
        }
        outputs=std::move(result);
        error.clear();
        return true;
    } catch (const std::bad_alloc&) {
        error="out of memory during isosurface extraction";
    } catch (const std::exception& e) {
        error=e.what();
    }
    return false;
}

std::string scientific_contour_fingerprint(const ScientificData& source,
                                            const std::string& scalar,double value) {
    return contour_fingerprint(source,scalar,value);
}

bool scientific_surface_to_xml(const ScientificData& surface,std::string& xml,std::string& error) {
    try {
        auto* poly=vtkPolyData::SafeDownCast(surface.dataset.GetPointer());
        if(!poly || surface.format!=ScientificFormat::DerivedIsosurface ||
           !poly->GetNumberOfCells())
            throw std::runtime_error("scientific cache requires a nonempty derived polydata surface");
        vtkNew<vtkXMLPolyDataWriter> writer;
        writer->SetInputData(poly);
        writer->SetDataModeToBinary();
        writer->WriteToOutputStringOn();
        if(!writer->Write())throw std::runtime_error("scientific surface XML write failed");
        std::string serialized=writer->GetOutputString();
        if(serialized.empty()||serialized.size()>default_max_source_bytes)
            throw std::runtime_error("scientific surface XML exceeds 256 MiB cache budget");
        xml=std::move(serialized);
        error.clear();return true;
    }catch(const std::bad_alloc&){error="out of memory serializing scientific surface";}
     catch(const std::exception& e){error=e.what();}
    return false;
}

bool scientific_surface_from_xml(const std::string& xml,const ScientificData& source,
    const std::string& scalar,double value,ScientificData& surface,std::string& error) {
    try {
        if(xml.empty()||xml.size()>default_max_source_bytes || !std::isfinite(value))
            throw std::runtime_error("scientific cached surface XML is invalid or over budget");
        vtkNew<vtkXMLPolyDataReader> reader;
        reader->ReadFromInputStringOn();
        reader->SetInputString(xml);
        reader->Update();
        auto* raw=reader->GetOutput();
        if(!raw||!raw->GetNumberOfCells())
            throw std::runtime_error("scientific cached surface is empty");
        vtkNew<vtkPolyData> poly;
        poly->DeepCopy(raw);
        validate_dataset(poly,false);
        for(vtkIdType i=0;i<poly->GetNumberOfCells();++i){
            auto* cell=poly->GetCell(i);
            if(!cell||cell->GetCellType()!=VTK_TRIANGLE||cell->GetNumberOfPoints()!=3)
                throw std::runtime_error("scientific cached surface contains a non-triangle cell");
        }
        ScientificData result;
        result.dataset=poly;
        result.format=ScientificFormat::DerivedIsosurface;
        result.source_sha256_hex=source.source_sha256_hex;
        result.fingerprint_sha256_hex=contour_fingerprint(source,scalar,value);
        result.selected_scalar=scalar;
        result.isovalue=value;
        result.derived=true;
        surface=std::move(result);
        error.clear();return true;
    }catch(const std::bad_alloc&){error="out of memory reading scientific cached surface";}
     catch(const std::exception& e){error=e.what();}
    return false;
}

vtkDataArray* scientific_array(const ScientificData& data,uint32_t association,
                               const std::string& name) {
    if (!data.dataset || name.empty()) return nullptr;
    vtkFieldData* fields=nullptr;
    if (association==GX3DE_SCI_ASSOC_POINT) fields=data.dataset->GetPointData();
    else if (association==GX3DE_SCI_ASSOC_CELL) fields=data.dataset->GetCellData();
    return fields?fields->GetArray(name.c_str()):nullptr;
}

vtkDataArray* scientific_array_at(const ScientificData& data,uint32_t association,
                                  uint64_t index) {
    if (!data.dataset) return nullptr;
    vtkFieldData* fields=nullptr;
    if (association==GX3DE_SCI_ASSOC_POINT) fields=data.dataset->GetPointData();
    else if (association==GX3DE_SCI_ASSOC_CELL) fields=data.dataset->GetCellData();
    if (!fields) return nullptr;
    uint64_t ordinal=0;
    for (int i=0;i<fields->GetNumberOfArrays();++i) {
        vtkDataArray* array=fields->GetArray(i);
        if (!array) continue;
        if (ordinal++==index) return array;
    }
    return nullptr;
}

} // namespace gx3de_backend
