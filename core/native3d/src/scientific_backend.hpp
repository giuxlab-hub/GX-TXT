/* SPDX-License-Identifier: GPL-3.0-or-later */
#ifndef GX3DE_SCIENTIFIC_BACKEND_HPP
#define GX3DE_SCIENTIFIC_BACKEND_HPP

#include "native_3d_engine_api_v1.h"
#include <vtkSmartPointer.h>
#include <cstdint>
#include <string>
#include <vector>

class vtkDataArray;
class vtkDataSet;

namespace gx3de_backend {

enum class ScientificFormat : uint32_t {
    Vtp=1, Vtu=2, Vti=3, DerivedIsosurface=4, InMemoryPolydata=5,
    InMemoryImage=6, InMemoryUnstructured=7
};

/* The dataset belongs to the object, not to a VTK pipeline or renderer.
 * Treat it as immutable after construction. A derived isosurface retains the
 * exact imported source digest, but has its own operation fingerprint. */
struct ScientificData {
    vtkSmartPointer<vtkDataSet> dataset;
    ScientificFormat format=ScientificFormat::Vtp;
    std::string source_sha256_hex;
    std::string fingerprint_sha256_hex;
    std::string selected_scalar;
    double isovalue=0;
    bool derived=false;
};

/* max_source_bytes=0 selects the 256 MiB default. The source is SHA-256
 * checked before and after the VTK read. On failure output is unchanged. */
bool import_scientific_file(const char* path_utf8, ScientificFormat format,
                            uint64_t max_source_bytes, ScientificData& output,
                            std::string& error);

/* Build an independent native polydata source from public size-tagged inputs.
 * Cell-associated tuples are remapped to VTK's vertices/lines/polygons order.
 * A bare point set with no cells is supported. On failure output is unchanged.
 */
bool create_scientific_polydata(const gx3de_scientific_polydata_spec& spec,
                               ScientificData& output, std::string& error);
bool create_scientific_image(const gx3de_scientific_image_spec& spec,
                             ScientificData& output, std::string& error);
bool create_scientific_unstructured(const gx3de_scientific_unstructured_spec& spec,
                                    ScientificData& output, std::string& error);

/* One immutable triangle surface per finite isovalue, including an explicit
 * empty object when the value is outside the source range. The input must be
 * a 3D VTI grid and scalar_name must identify a point scalar field. The
 * source's active-scalar metadata is never changed. On failure outputs are
 * unchanged. */
bool contour_isovalues(const ScientificData& source,
                       const std::string& scalar_name,
                       const std::vector<double>& isovalues,
                       std::vector<ScientificData>& outputs,
                       std::string& error);
std::string scientific_contour_fingerprint(const ScientificData& source,
                                            const std::string& scalar,double value);
bool scientific_surface_to_xml(const ScientificData& surface,std::string& xml,std::string& error);
bool scientific_surface_from_xml(const std::string& xml,const ScientificData& source,
    const std::string& scalar,double value,ScientificData& surface,std::string& error);

/* Numeric array lookup by association (1 point, 2 cell). Returns null for
 * absent arrays, invalid association/index, or non-numeric arrays. */
vtkDataArray* scientific_array(const ScientificData& data,
                               uint32_t association, const std::string& name);
vtkDataArray* scientific_array_at(const ScientificData& data,
                                  uint32_t association, uint64_t index);

} // namespace gx3de_backend
#endif
