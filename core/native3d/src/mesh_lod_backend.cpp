// SPDX-License-Identifier: GPL-3.0-or-later
#include "mesh_lod_backend.hpp"
#include <vtkCellArray.h>
#include <vtkFeatureEdges.h>
#include <vtkHausdorffDistancePointSetFilter.h>
#include <vtkNew.h>
#include <vtkPoints.h>
#include <vtkPolyData.h>
#include <vtkPolyDataConnectivityFilter.h>
#include <vtkDecimatePro.h>
#include <vtkQuadricDecimation.h>
#include <vtkSmartPointer.h>
#include <algorithm>
#include <array>
#include <cmath>
#include <limits>
#include <new>
#include <stdexcept>

namespace gx3de_backend {
namespace {
vtkSmartPointer<vtkPolyData> to_vtk(const MeshData& mesh) {
    if (mesh.vertices.empty() || mesh.triangles.empty() ||
        mesh.triangles.size()%3 ||
        mesh.vertices.size()>uint64_t(std::numeric_limits<vtkIdType>::max()) ||
        mesh.triangles.size()/3>uint64_t(std::numeric_limits<vtkIdType>::max()))
        throw std::runtime_error("LOD source exceeds VTK capacity or is empty");
    vtkNew<vtkPoints> points;
    points->SetDataTypeToDouble();
    points->Allocate(static_cast<vtkIdType>(mesh.vertices.size()));
    for (auto point: mesh.vertices) {
        if (!std::isfinite(point.x)||!std::isfinite(point.y)||!std::isfinite(point.z))
            throw std::runtime_error("LOD source has non-finite point");
        points->InsertNextPoint(point.x,point.y,point.z);
    }
    vtkNew<vtkCellArray> cells;
    cells->AllocateEstimate(static_cast<vtkIdType>(mesh.triangles.size()/3),3);
    for (size_t i=0;i<mesh.triangles.size();i+=3) {
        vtkIdType ids[3]{};
        for (int j=0;j<3;++j) {
            if (mesh.triangles[i+j]>=mesh.vertices.size())
                throw std::runtime_error("LOD source has invalid triangle index");
            ids[j]=static_cast<vtkIdType>(mesh.triangles[i+j]);
        }
        cells->InsertNextCell(3,ids);
    }
    auto poly=vtkSmartPointer<vtkPolyData>::New();
    poly->SetPoints(points);poly->SetPolys(cells);
    return poly;
}

MeshData from_vtk(vtkPolyData* poly) {
    if (!poly || !poly->GetPoints() || !poly->GetPolys() ||
        poly->GetNumberOfPoints()<=0 || poly->GetNumberOfPolys()<=0 ||
        uint64_t(poly->GetNumberOfPoints())>UINT32_MAX)
        throw std::runtime_error("LOD produced empty or oversized geometry");
    MeshData mesh;
    mesh.vertices.reserve(static_cast<size_t>(poly->GetNumberOfPoints()));
    mesh.triangles.reserve(static_cast<size_t>(poly->GetNumberOfPolys())*3);
    for (vtkIdType i=0;i<poly->GetNumberOfPoints();++i) {
        double p[3]{};poly->GetPoint(i,p);
        if (!std::isfinite(p[0])||!std::isfinite(p[1])||!std::isfinite(p[2]))
            throw std::runtime_error("LOD produced non-finite point");
        mesh.vertices.push_back({p[0],p[1],p[2]});
    }
    vtkIdType n=0;const vtkIdType* ids=nullptr;
    auto* polys=poly->GetPolys();polys->InitTraversal();
    while(polys->GetNextCell(n,ids)) {
        if (n!=3||!ids)throw std::runtime_error("LOD produced a non-triangle cell");
        for(int j=0;j<3;++j) {
            if(ids[j]<0||uint64_t(ids[j])>=mesh.vertices.size())
                throw std::runtime_error("LOD produced invalid triangle index");
            mesh.triangles.push_back(static_cast<uint32_t>(ids[j]));
        }
    }
    if(mesh.triangles.empty())throw std::runtime_error("LOD produced no triangles");
    return mesh;
}

bool envelope_safe(vtkPolyData* full,vtkPolyData* candidate) {
    if(!candidate||candidate->GetNumberOfPolys()<=0)return false;
    double source_bounds[6]{},result_bounds[6]{};
    full->GetBounds(source_bounds);candidate->GetBounds(result_bounds);
    for(int axis=0;axis<3;++axis){
        const double span=std::max(1e-9,source_bounds[2*axis+1]-source_bounds[2*axis]);
        if(std::max(std::abs(result_bounds[2*axis]-source_bounds[2*axis]),
                    std::abs(result_bounds[2*axis+1]-source_bounds[2*axis+1]))>span*0.02)
            return false;
    }
    return true;
}

struct SurfaceMeasures { double area=0,max_edge=0; };
SurfaceMeasures surface_measures(vtkPolyData* poly) {
    SurfaceMeasures result;
    vtkIdType n=0;const vtkIdType* ids=nullptr;
    auto* cells=poly->GetPolys();cells->InitTraversal();
    while(cells->GetNextCell(n,ids)){
        if(n!=3)continue;
        double p[3][3]{};
        for(int j=0;j<3;++j)poly->GetPoint(ids[j],p[j]);
        const double a[3]={p[1][0]-p[0][0],p[1][1]-p[0][1],p[1][2]-p[0][2]};
        const double b[3]={p[2][0]-p[0][0],p[2][1]-p[0][1],p[2][2]-p[0][2]};
        const double cross[3]={a[1]*b[2]-a[2]*b[1],a[2]*b[0]-a[0]*b[2],
                               a[0]*b[1]-a[1]*b[0]};
        result.area+=0.5*std::sqrt(cross[0]*cross[0]+cross[1]*cross[1]+cross[2]*cross[2]);
        for(int j=0;j<3;++j){
            const double dx=p[j][0]-p[(j+1)%3][0],dy=p[j][1]-p[(j+1)%3][1],
                         dz=p[j][2]-p[(j+1)%3][2];
            result.max_edge=std::max(result.max_edge,std::sqrt(dx*dx+dy*dy+dz*dz));
        }
    }
    return result;
}

vtkIdType component_count(vtkPolyData* poly) {
    vtkNew<vtkPolyDataConnectivityFilter> filter;
    filter->SetInputData(poly);filter->SetExtractionModeToAllRegions();filter->Update();
    return filter->GetNumberOfExtractedRegions();
}

vtkIdType irregular_edge_count(vtkPolyData* poly) {
    vtkNew<vtkFeatureEdges> edges;
    edges->SetInputData(poly);edges->FeatureEdgesOff();edges->ManifoldEdgesOff();
    edges->BoundaryEdgesOn();edges->NonManifoldEdgesOn();edges->Update();
    return edges->GetOutput()->GetNumberOfCells();
}

bool reduction_safe(vtkPolyData* full,vtkPolyData* candidate) {
    if(!envelope_safe(full,candidate)||
       component_count(candidate)!=component_count(full))return false;
    const auto source=surface_measures(full),reduced=surface_measures(candidate);
    if(!std::isfinite(reduced.area)||!std::isfinite(reduced.max_edge)||
       source.area<=0||reduced.area<source.area*0.5||reduced.area>source.area*1.2||
       reduced.max_edge>source.max_edge*1.5)return false;
    const auto extra=irregular_edge_count(candidate)-irregular_edge_count(full);
    if(extra>full->GetNumberOfPolys()*0.15)return false;
    double bounds[6];full->GetBounds(bounds);
    const double dx=bounds[1]-bounds[0],dy=bounds[3]-bounds[2],dz=bounds[5]-bounds[4];
    const double diagonal=std::sqrt(dx*dx+dy*dy+dz*dz);
    vtkNew<vtkHausdorffDistancePointSetFilter> distance;
    distance->SetInputData(0,full);distance->SetInputData(1,candidate);
    distance->SetTargetDistanceMethodToPointToCell();distance->Update();
    return std::isfinite(distance->GetHausdorffDistance())&&
           distance->GetHausdorffDistance()<=diagonal*0.005;
}

vtkSmartPointer<vtkPolyData> topology_safe_lod(vtkPolyData* full,double fraction,
                                                double fallback_fraction) {
    auto output=vtkSmartPointer<vtkPolyData>::New();
    if(fraction>=0.999){output->ShallowCopy(full);return output;}
    vtkNew<vtkDecimatePro> decimation;
    decimation->SetInputData(full);
    decimation->SetTargetReduction(std::clamp(1.0-fraction,0.0,0.999));
    decimation->PreserveTopologyOn();
    decimation->SplittingOff();
    decimation->BoundaryVertexDeletionOff();
    decimation->Update();
    output->ShallowCopy(decimation->GetOutput());
    if(!envelope_safe(full,output))output->ShallowCopy(full);
    // A highly perforated surface can have no topology-preserving edge
    // collapses left. Try a conservative quadric reduction only if it passes
    // independent geometry and topology checks; otherwise retain the intact
    // topology-preserving result.
    if(fallback_fraction>0&&full->GetNumberOfPolys()>=1000&&
       output->GetNumberOfPolys()>full->GetNumberOfPolys()*fraction*1.25){
        vtkNew<vtkQuadricDecimation> quadric;
        quadric->SetInputData(full);
        quadric->SetTargetReduction(1.0-fallback_fraction);
        quadric->VolumePreservationOn();quadric->Update();
        auto* candidate=quadric->GetOutput();
        if(candidate->GetNumberOfPolys()<output->GetNumberOfPolys()&&
           reduction_safe(full,candidate))output->ShallowCopy(candidate);
    }
    return output;
}
}

bool mesh_lod(const MeshData& source,uint32_t level,MeshData& output,std::string& error) {
    try {
        if(level<1||level>5)throw std::runtime_error("invalid LOD level");
        static constexpr double fractions[]={0,0.08,0.15,0.45,0.95,1.0};
        static constexpr double fallback_fractions[]={0,0.30,0.50,0.75,0,0};
        auto input=to_vtk(source);
        auto derived=topology_safe_lod(input,fractions[level],fallback_fractions[level]);
        auto result=from_vtk(derived);
        output=std::move(result);error.clear();return true;
    }catch(const std::bad_alloc&){error="out of memory generating LOD";}
    catch(const std::exception& e){error=e.what();}
    return false;
}
}
