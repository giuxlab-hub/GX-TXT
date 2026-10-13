// SPDX-License-Identifier: GPL-3.0-or-later
#include "step_mesh_backend.hpp"
#include <BRepBuilderAPI_Copy.hxx>
#include <BRepMesh_IncrementalMesh.hxx>
#include <BRep_Tool.hxx>
#include <Poly_Triangulation.hxx>
#include <TopAbs_Orientation.hxx>
#include <TopExp_Explorer.hxx>
#include <TopLoc_Location.hxx>
#include <TopoDS.hxx>
#include <TopoDS_Face.hxx>
#include <TopoDS_Shape.hxx>
#include <Standard_Failure.hxx>
#include <algorithm>
#include <cmath>
#include <limits>
#include <stdexcept>

namespace gx3de_backend {
bool tessellate_step_prototype(const TopoDS_Shape& source,double linear_deflection,
    double angular_deflection,double weld_tolerance,uint64_t max_triangles,uint64_t max_output_bytes,
    MeshData& output,std::string& error) {
    if(source.IsNull()||!std::isfinite(linear_deflection)||linear_deflection<=0||
       !std::isfinite(angular_deflection)||angular_deflection<=0||angular_deflection>3.141592653589793||
       !std::isfinite(weld_tolerance)||weld_tolerance<0||max_triangles==0||max_output_bytes==0) {
        error="invalid STEP tessellation parameters";return false;
    }
    try {
        TopoDS_Shape copy=BRepBuilderAPI_Copy(source,Standard_True,Standard_False).Shape();
        BRepMesh_IncrementalMesh mesher(copy,linear_deflection,Standard_False,angular_deflection,Standard_True);
        if(!mesher.IsDone()){error="STEP tessellation failed";return false;}
        MeshData raw;
        for(TopExp_Explorer explorer(copy,TopAbs_FACE);explorer.More();explorer.Next()) {
            const TopoDS_Face face=TopoDS::Face(explorer.Current());
            TopLoc_Location location;
            const Handle(Poly_Triangulation) triangulation=BRep_Tool::Triangulation(face,location);
            if(triangulation.IsNull())continue;
            const uint64_t face_points=static_cast<uint64_t>(triangulation->NbNodes());
            const uint64_t face_triangles=static_cast<uint64_t>(triangulation->NbTriangles());
            if(raw.triangles.size()/3+face_triangles>max_triangles||
               raw.vertices.size()+face_points>UINT32_MAX||
               (raw.vertices.size()+face_points)*sizeof(gx3de_vec3)+
               (raw.triangles.size()+face_triangles*3)*sizeof(uint32_t)>max_output_bytes){
                error="STEP tessellation exceeds mesh budget";return false;}
            const uint32_t base=static_cast<uint32_t>(raw.vertices.size());
            const gp_Trsf transform=location.Transformation();
            for(Standard_Integer node=1;node<=triangulation->NbNodes();++node){
                const gp_Pnt point=triangulation->Node(node).Transformed(transform);
                gx3de_vec3 p{point.X(),point.Y(),point.Z()};
                if(!std::isfinite(p.x)||!std::isfinite(p.y)||!std::isfinite(p.z)){
                    error="non-finite STEP tessellation point";return false;
                }
                raw.vertices.push_back(p);
            }
            for(Standard_Integer tri=1;tri<=triangulation->NbTriangles();++tri){
                Standard_Integer a,b,c;triangulation->Triangle(tri).Get(a,b,c);
                if(a<1||b<1||c<1||a>triangulation->NbNodes()||b>triangulation->NbNodes()||c>triangulation->NbNodes()){
                    error="invalid STEP triangulation index";return false;
                }
                if(face.Orientation()==TopAbs_REVERSED)std::swap(b,c);
                raw.triangles.insert(raw.triangles.end(),{base+uint32_t(a-1),base+uint32_t(b-1),base+uint32_t(c-1)});
            }
        }
        if(raw.triangles.empty()){error="STEP prototype has no tessellatable faces";return false;}
        MeshData prepared;
        if(!weld_mesh(raw,weld_tolerance,prepared,error))return false;
        if(prepared.triangles.empty()){error="STEP tessellation collapsed after welding";return false;}
        output=std::move(prepared);error.clear();return true;
    }catch(const std::bad_alloc&){error="out of memory during STEP tessellation";return false;
    }catch(const Standard_Failure&){error="OCCT failed during STEP tessellation";return false;
    }catch(const std::exception&){error="STEP tessellation failed";return false;}
}
}
