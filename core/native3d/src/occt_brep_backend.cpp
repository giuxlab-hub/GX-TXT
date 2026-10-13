/* SPDX-License-Identifier: GPL-3.0-or-later */
#include "occt_brep_backend.hpp"
#include "step_mesh_backend.hpp"
#include "profile_backend.hpp"

#include <BRepAdaptor_Curve.hxx>
#include <BRepAdaptor_Surface.hxx>
#include <BRepAlgoAPI_Common.hxx>
#include <BRepAlgoAPI_Cut.hxx>
#include <BRepAlgoAPI_Fuse.hxx>
#include <BRepAlgoAPI_Section.hxx>
#include <BRepBndLib.hxx>
#include <BRepBuilderAPI_MakeFace.hxx>
#include <BRepBuilderAPI_MakePolygon.hxx>
#include <BRepPrimAPI_MakePrism.hxx>
#include <BRep_Builder.hxx>
#include <TopoDS_Compound.hxx>
#include <TopoDS_Wire.hxx>
#include <STEPControl_Writer.hxx>
#include <StepData_StepModel.hxx>
#include <IFSelect_ReturnStatus.hxx>
#include <BRepBuilderAPI_Copy.hxx>
#include <BRepBuilderAPI_GTransform.hxx>
#include <BRepBuilderAPI_Transform.hxx>
#include <BRepClass_FaceClassifier.hxx>
#include <BRepCheck_Analyzer.hxx>
#include <BRepCheck_Shell.hxx>
#include <BRepGProp.hxx>
#include <BRepLProp_SLProps.hxx>
#include <BRepPrimAPI_MakeHalfSpace.hxx>
#include <BRepPrimAPI_MakeBox.hxx>
#include <BRepPrimAPI_MakeCylinder.hxx>
#include <BRepTools.hxx>
#include <BRep_Tool.hxx>
#include <Bnd_Box.hxx>
#include <GCPnts_QuasiUniformDeflection.hxx>
#include <GCPnts_AbscissaPoint.hxx>
#include <GeomAPI_ProjectPointOnSurf.hxx>
#include <GeomAbs_CurveType.hxx>
#include <GeomAbs_SurfaceType.hxx>
#include <GProp_GProps.hxx>
#include <Standard_Failure.hxx>
#include <Standard_Version.hxx>
#include <TopoDS.hxx>
#include <TopoDS_Shape.hxx>
#include <TopExp.hxx>
#include <TopExp_Explorer.hxx>
#include <TopAbs_ShapeEnum.hxx>
#include <TopAbs_State.hxx>
#include <TopTools_IndexedMapOfShape.hxx>
#include <gp_Dir.hxx>
#include <gp_GTrsf.hxx>
#include <gp_Pln.hxx>
#include <gp_Pnt.hxx>
#include <gp_Pnt2d.hxx>
#include <gp_Trsf.hxx>
#include <gp_Vec.hxx>
#include <ShapeFix_Shape.hxx>

#include <algorithm>
#include <array>
#include <cmath>
#include <exception>
#include <limits>
#include <openssl/evp.h>
#include <ostream>
#include <streambuf>

namespace gx3de_backend {

struct BrepShape { explicit BrepShape(TopoDS_Shape s) : shape(std::move(s)) {} TopoDS_Shape shape; };
bool tessellate_for_render(const BrepShape& source,MeshData& output,std::string& error) {
    return tessellate_step_prototype(source.shape,0.05,0.4,1e-9,2000000,
                                     256ull*1024*1024,output,error);
}
bool tessellate_brep(const BrepShape& source,double linear_deflection,
    double angular_deflection,double weld_tolerance,uint64_t max_triangles,
    uint64_t max_output_bytes,MeshData& output,std::string& error) {
    return tessellate_step_prototype(source.shape,linear_deflection,angular_deflection,
        weld_tolerance,max_triangles,max_output_bytes,output,error);
}

namespace {
bool finite(gx3de_vec3 p) {
    return std::isfinite(p.x) && std::isfinite(p.y) && std::isfinite(p.z);
}
gx3de_vec3 vec(const gp_Pnt& p) { return {p.X(), p.Y(), p.Z()}; }
double distance2(gx3de_vec3 a, gx3de_vec3 b) {
    const double x=a.x-b.x, y=a.y-b.y, z=a.z-b.z;
    return x*x+y*y+z*z;
}
void failure(std::string& error, const Standard_Failure& e) {
    error = e.GetMessageString() ? e.GetMessageString() : "OpenCASCADE operation failed";
}
bool valid_shape(const BrepShape& s) { return !s.shape.IsNull(); }
bool valid_fraction(double x) { return std::isfinite(x) && x>=0.0 && x<=1.0; }
bool index_in_map(uint64_t index, const TopTools_IndexedMapOfShape& map) {
    return index>0 && index<=static_cast<uint64_t>(map.Extent());
}
/* OCCT's general analyzer checks topology, but the clip contract requires
 * closed volumes. Reject open shells and stray faces even when a compound also
 * contains a valid solid. This check is deliberately conservative for STEP
 * shapes that mix solids with surface-only geometry. */
bool closed_solids_only(const TopoDS_Shape& shape, std::string& error) {
    TopTools_IndexedMapOfShape all_faces, solid_faces;
    TopExp::MapShapes(shape, TopAbs_FACE, all_faces);
    bool has_solid=false;
    for (TopExp_Explorer solids(shape,TopAbs_SOLID); solids.More(); solids.Next()) {
        has_solid=true;
        const TopoDS_Shape& solid=solids.Current();
        if (!BRepCheck_Analyzer(solid,Standard_True).IsValid()) {
            error="B-Rep contains an invalid solid"; return false;
        }
        bool has_shell=false;
        for (TopExp_Explorer shells(solid,TopAbs_SHELL); shells.More(); shells.Next()) {
            has_shell=true;
            BRepCheck_Shell check(TopoDS::Shell(shells.Current()));
            if (check.Closed()!=BRepCheck_NoError ||
                check.Orientation()!=BRepCheck_NoError) {
                error="B-Rep contains an open or unoriented shell"; return false;
            }
        }
        if (!has_shell) { error="B-Rep solid has no shell"; return false; }
        GProp_GProps mass;
        BRepGProp::VolumeProperties(solid,mass,Standard_True);
        if (!std::isfinite(mass.Mass()) || mass.Mass()==0.0) {
            error="B-Rep solid has no finite enclosed volume"; return false;
        }
        TopTools_IndexedMapOfShape faces;
        TopExp::MapShapes(solid,TopAbs_FACE,faces);
        for (int i=1; i<=faces.Extent(); ++i) solid_faces.Add(faces.FindKey(i));
    }
    if (!has_solid) { error="B-Rep half-space clipping requires a closed solid"; return false; }
    for (int i=1; i<=all_faces.Extent(); ++i) {
        if (!solid_faces.Contains(all_faces.FindKey(i))) {
            error="B-Rep contains a face outside its closed solids"; return false;
        }
    }
    if (!BRepCheck_Analyzer(shape,Standard_True).IsValid()) {
        error="B-Rep contains invalid topology"; return false;
    }
    return true;
}
} // namespace

bool create_box(double x, double y, double z,
                std::shared_ptr<BrepShape>& out, std::string& error) {
    out.reset(); error.clear();
    if (!std::isfinite(x) || !std::isfinite(y) || !std::isfinite(z) ||
        x <= 0 || y <= 0 || z <= 0) {
        error = "box dimensions must be finite and positive";
        return false;
    }
    try {
        BRepPrimAPI_MakeBox make(x,y,z);
        make.Build();
        if (!make.IsDone() || make.Shape().IsNull()) {
            error = "OpenCASCADE could not construct box";
            return false;
        }
        out = std::make_shared<BrepShape>(make.Shape());
        return true;
    } catch (const Standard_Failure& e) { failure(error,e); }
      catch (const std::exception& e) { error=e.what(); }
    return false;
}

bool create_cylinder(double radius,double height,
                     std::shared_ptr<BrepShape>& out,std::string& error) {
    out.reset();error.clear();
    if(!std::isfinite(radius)||!std::isfinite(height)||radius<=0||height<=0){
        error="cylinder radius and height must be finite and positive";return false;
    }
    try {
        BRepPrimAPI_MakeCylinder make(radius,height);
        make.Build();
        if(!make.IsDone()||make.Shape().IsNull()){
            error="OpenCASCADE could not construct cylinder";return false;
        }
        out=std::make_shared<BrepShape>(make.Shape());return true;
    }catch(const Standard_Failure& e){failure(error,e);}
     catch(const std::exception& e){error=e.what();}
    return false;
}

bool adopt_step_shape(const TopoDS_Shape& native,
                      std::shared_ptr<BrepShape>& out, std::string& error) {
    out.reset(); error.clear();
    if (native.IsNull()) {
        error="STEP part definition has no B-Rep shape";
        return false;
    }
    try {
        // TopoDS_Shape retains its TShape independently of the XDE document.
        // Keep the exact imported topology rather than rebuilding or flattening
        // it; a single adopted definition can back many occurrence objects.
        out=std::make_shared<BrepShape>(native);
        return true;
    } catch (const Standard_Failure& e) { failure(error,e); }
      catch (const std::exception& e) { error=e.what(); }
    return false;
}

bool bounds(const BrepShape& shape, gx3de_bounds& out) {
    if (!valid_shape(shape)) return false;
    try {
        Bnd_Box box;
        BRepBndLib::AddOptimal(shape.shape, box, Standard_False, Standard_False);
        if (box.IsVoid()) return false;
        Standard_Real xmin,ymin,zmin,xmax,ymax,zmax;
        box.Get(xmin,ymin,zmin,xmax,ymax,zmax);
        out={{xmin,ymin,zmin},{xmax,ymax,zmax}};
        return finite(out.min) && finite(out.max);
    } catch (const Standard_Failure&) { return false; }
}

bool section(const BrepShape& shape, gx3de_vec3 origin, gx3de_vec3 normal,
             std::vector<BrepSegment>& out, std::string& error) {
    out.clear(); error.clear();
    if (!valid_shape(shape) || !finite(origin) || !finite(normal) ||
        std::hypot(normal.x,normal.y,normal.z) <= 1e-15) {
        error = "invalid B-Rep section shape or plane";
        return false;
    }
    try {
        gp_Pln plane(gp_Pnt(origin.x,origin.y,origin.z),
                     gp_Dir(normal.x,normal.y,normal.z));
        BRepAlgoAPI_Section cut(shape.shape,plane,Standard_False);
        cut.Approximation(Standard_True);
        cut.Build();
        if (!cut.IsDone() || cut.HasErrors()) {
            error = "OpenCASCADE B-Rep section failed";
            return false;
        }
        gx3de_bounds bbox{};
        double deflection=1e-7;
        if (bounds(shape,bbox)) {
            const double dx=bbox.max.x-bbox.min.x, dy=bbox.max.y-bbox.min.y,
                         dz=bbox.max.z-bbox.min.z;
            deflection=std::max(deflection,1e-5*std::hypot(dx,dy,dz));
        }
        constexpr std::size_t max_segments=1000000;
        for (TopExp_Explorer it(cut.Shape(),TopAbs_EDGE); it.More(); it.Next()) {
            BRepAdaptor_Curve curve(TopoDS::Edge(it.Current()));
            const double first=curve.FirstParameter(), last=curve.LastParameter();
            if (!std::isfinite(first) || !std::isfinite(last)) {
                error="unbounded B-Rep section edge"; out.clear(); return false;
            }
            if (curve.GetType()==GeomAbs_Line) {
                auto a=vec(curve.Value(first)), b=vec(curve.Value(last));
                if (distance2(a,b)>1e-24) out.push_back({a,b});
            } else {
                GCPnts_QuasiUniformDeflection samples(curve,deflection);
                if (!samples.IsDone() || samples.NbPoints()<2) {
                    error="could not sample curved B-Rep section edge";
                    out.clear(); return false;
                }
                gx3de_vec3 prev=vec(curve.Value(samples.Parameter(1)));
                for (int i=2; i<=samples.NbPoints(); ++i) {
                    gx3de_vec3 next=vec(curve.Value(samples.Parameter(i)));
                    if (distance2(prev,next)>1e-24) out.push_back({prev,next});
                    if (out.size()>max_segments) {
                        error="B-Rep section exceeds segment budget";
                        out.clear(); return false;
                    }
                    prev=next;
                }
            }
            if (out.size()>max_segments) {
                error="B-Rep section exceeds segment budget";
                out.clear(); return false;
            }
        }
        return true;
    } catch (const Standard_Failure& e) { failure(error,e); }
      catch (const std::exception& e) { error=e.what(); }
    out.clear(); return false;
}

bool boolean_op(const BrepShape& a, const BrepShape& b, int op,
                std::shared_ptr<BrepShape>& out, std::string& error) {
    out.reset(); error.clear();
    if (!valid_shape(a) || !valid_shape(b) || op<1 || op>3) {
        error="invalid B-Rep shape or boolean operation";
        return false;
    }
    try {
        TopoDS_Shape result;
        // Boolean algorithms may update tolerances/p-curves on their inputs.
        // Independent geometry copies preserve authoritative source topology.
        const auto left=BRepBuilderAPI_Copy(a.shape,Standard_True,Standard_False).Shape();
        const auto right=BRepBuilderAPI_Copy(b.shape,Standard_True,Standard_False).Shape();
        if (op==1) {
            BRepAlgoAPI_Fuse algo(left,right);
            algo.SetRunParallel(Standard_False);
            algo.Build();
            if (!algo.IsDone() || algo.HasErrors()) { error="B-Rep union failed"; return false; }
            result=algo.Shape();
        } else if (op==2) {
            BRepAlgoAPI_Common algo(left,right);
            algo.SetRunParallel(Standard_False);
            algo.Build();
            if (!algo.IsDone() || algo.HasErrors()) { error="B-Rep intersection failed"; return false; }
            result=algo.Shape();
        } else {
            BRepAlgoAPI_Cut algo(left,right);
            algo.SetRunParallel(Standard_False);
            algo.Build();
            if (!algo.IsDone() || algo.HasErrors()) { error="B-Rep difference failed"; return false; }
            result=algo.Shape();
        }
        if (result.IsNull()) { error="B-Rep boolean returned null shape"; return false; }
        if (!BRepCheck_Analyzer(result, Standard_True).IsValid()) {
            error="OpenCASCADE B-Rep boolean returned invalid topology";
            return false;
        }
        out=std::make_shared<BrepShape>(std::move(result));
        return true;
    } catch (const Standard_Failure& e) { failure(error,e); }
      catch (const std::exception& e) { error=e.what(); }
    return false;
}

bool clip_halfspace(const BrepShape& shape, gx3de_vec3 origin,
                    gx3de_vec3 normal, bool keep_positive,
                    std::shared_ptr<BrepShape>& out, std::string& error) {
    out.reset(); error.clear();
    const double magnitude=std::hypot(normal.x,normal.y,normal.z);
    if (!valid_shape(shape) || !finite(origin) || !finite(normal) ||
        !std::isfinite(magnitude) || magnitude<=1e-15) {
        error="invalid B-Rep clipping shape or plane"; return false;
    }
    try {
        if (!closed_solids_only(shape.shape,error)) return false;
        const gp_Dir direction(normal.x,normal.y,normal.z);
        const gp_Pnt plane_origin(origin.x,origin.y,origin.z);
        const gp_Pln plane(plane_origin,direction);
        BRepBuilderAPI_MakeFace make_face(plane);
        if (!make_face.IsDone() || make_face.Face().IsNull()) {
            error="could not construct B-Rep clipping plane"; return false;
        }
        // OCCT determines which side to retain from the reference point.
        // A unit offset avoids tolerance ambiguity at the plane itself.
        const double sign=keep_positive ? 1.0 : -1.0;
        const gp_Pnt reference(origin.x+sign*direction.X(),
                               origin.y+sign*direction.Y(),
                               origin.z+sign*direction.Z());
        BRepPrimAPI_MakeHalfSpace halfspace(make_face.Face(),reference);
        halfspace.Build();
        if (!halfspace.IsDone() || halfspace.Shape().IsNull()) {
            error="could not construct B-Rep half-space"; return false;
        }
        BRepAlgoAPI_Common cut(shape.shape,halfspace.Shape());
        cut.SetRunParallel(Standard_False);
        cut.Build();
        if (!cut.IsDone() || cut.HasErrors()) {
            error="OpenCASCADE B-Rep half-space clip failed"; return false;
        }
        TopoDS_Shape result=cut.Shape();
        if (result.IsNull()) return true;
        bool has_result_solid=false;
        for (TopExp_Explorer it(result,TopAbs_SOLID);it.More();it.Next()) {
            has_result_solid=true; break;
        }
        if (!has_result_solid) return true;
        if (!closed_solids_only(result,error)) {
            error="OpenCASCADE B-Rep clip returned " + error;
            return false;
        }
        out=std::make_shared<BrepShape>(std::move(result));
        return true;
    } catch (const Standard_Failure& e) { failure(error,e); }
      catch (const std::exception& e) { error=e.what(); }
    out.reset(); return false;
}

bool topology_counts(const BrepShape& shape, BrepTopologyCounts& out) {
    out={0,0,0};
    if (!valid_shape(shape)) return false;
    try {
        TopTools_IndexedMapOfShape vertices,edges,faces;
        TopExp::MapShapes(shape.shape,TopAbs_VERTEX,vertices);
        TopExp::MapShapes(shape.shape,TopAbs_EDGE,edges);
        TopExp::MapShapes(shape.shape,TopAbs_FACE,faces);
        out={static_cast<uint64_t>(vertices.Extent()),
             static_cast<uint64_t>(edges.Extent()),
             static_cast<uint64_t>(faces.Extent())};
        return true;
    } catch (const Standard_Failure&) { return false; }
}

bool validate(const BrepShape& shape, BrepValidation& out, std::string& error) {
    if(!valid_shape(shape)){error="null B-Rep shape";return false;}
    try {
        BrepValidation result{};
        for(TopExp_Explorer it(shape.shape,TopAbs_SOLID);it.More();it.Next())++result.solids;
        for(TopExp_Explorer it(shape.shape,TopAbs_SHELL);it.More();it.Next())++result.shells;
        TopTools_IndexedMapOfShape faces;
        TopExp::MapShapes(shape.shape,TopAbs_FACE,faces);
        result.faces=static_cast<uint64_t>(faces.Extent());
        result.topology_valid=BRepCheck_Analyzer(shape.shape,Standard_True).IsValid();
        std::string closed_error;
        result.closed_oriented_solids=result.topology_valid&&closed_solids_only(shape.shape,closed_error);
        out=result;error.clear();return true;
    }catch(const Standard_Failure& e){failure(error,e);}
     catch(const std::exception& e){error=e.what();}
    return false;
}

bool heal_solid(const BrepShape& source,double tolerance,
                std::shared_ptr<BrepShape>& out,std::string& error) {
    out.reset();error.clear();
    if(!valid_shape(source)||!std::isfinite(tolerance)||tolerance<=0){
        error="B-Rep healing needs a shape and positive finite tolerance";
        return false;
    }
    try {
        std::string valid_error;
        if(closed_solids_only(source.shape,valid_error)){
            out=std::make_shared<BrepShape>(source.shape);
            return true;
        }
        uint64_t source_solids=0;
        for(TopExp_Explorer it(source.shape,TopAbs_SOLID);it.More();it.Next())++source_solids;
        if(!source_solids){error="healing supports solid B-Reps only";return false;}
        gx3de_bounds before{};
        if(!bounds(source,before)){error="cannot bound damaged B-Rep";return false;}
        double before_area=0,before_volume=0;
        if(!properties(source,before_area,before_volume)||
           !std::isfinite(before_area)||!std::isfinite(before_volume)||
           !(before_area>0)||!(std::abs(before_volume)>tolerance*tolerance*tolerance)){
            error="damaged B-Rep has no reliable finite solid properties";
            return false;
        }
        BRepBuilderAPI_Copy copy(source.shape,Standard_True,Standard_False);
        if(!copy.IsDone()||copy.Shape().IsNull()){
            error="could not deep-copy damaged B-Rep";return false;
        }
        ShapeFix_Shape fixer(copy.Shape());
        fixer.SetPrecision(tolerance);
        fixer.SetMinTolerance(std::min(tolerance,1e-7));
        fixer.SetMaxTolerance(tolerance);
        fixer.Perform();
        TopoDS_Shape healed=fixer.Shape();
        if(healed.IsNull()||!closed_solids_only(healed,valid_error)){
            error="ShapeFix did not produce valid closed oriented solids";
            return false;
        }
        uint64_t healed_solids=0;
        for(TopExp_Explorer it(healed,TopAbs_SOLID);it.More();it.Next())++healed_solids;
        if(healed_solids!=source_solids){
            error="ShapeFix changed the number of solids";return false;
        }
        BrepShape checked(healed);
        gx3de_bounds after{};double after_area=0,after_volume=0;
        if(!bounds(checked,after)||!properties(checked,after_area,after_volume)||
           !std::isfinite(after_area)||!std::isfinite(after_volume)){
            error="healed B-Rep has non-finite geometry";return false;
        }
        const double span=std::max({before.max.x-before.min.x,
            before.max.y-before.min.y,before.max.z-before.min.z,1.0});
        const double bound_limit=std::max(10*tolerance,1e-7*span);
        const double coordinates[]={before.min.x,before.min.y,before.min.z,
            before.max.x,before.max.y,before.max.z};
        const double healed_coordinates[]={after.min.x,after.min.y,after.min.z,
            after.max.x,after.max.y,after.max.z};
        for(int i=0;i<6;++i)if(std::abs(coordinates[i]-healed_coordinates[i])>bound_limit){
            error="ShapeFix changed B-Rep bounds beyond tolerance";return false;
        }
        if(std::abs(after_area-before_area)>
              std::max(10*tolerance*span,1e-6*before_area)||
           std::abs(std::abs(after_volume)-std::abs(before_volume))>
              std::max(10*tolerance*before_area,1e-6*std::abs(before_volume))){
            error="ShapeFix changed B-Rep area or volume beyond tolerance";
            return false;
        }
        out=std::make_shared<BrepShape>(std::move(healed));
        return true;
    }catch(const Standard_Failure& e){failure(error,e);}
     catch(const std::exception& e){error=e.what();}
    out.reset();return false;
}

bool vertex_anchor(const BrepShape& shape, uint64_t vertex_index,
                   gx3de_vec3& point, std::string& error) {
    point={}; error.clear();
    if (!valid_shape(shape)) { error="invalid B-Rep shape"; return false; }
    try {
        TopTools_IndexedMapOfShape vertices;
        TopExp::MapShapes(shape.shape,TopAbs_VERTEX,vertices);
        if (!index_in_map(vertex_index,vertices)) {
            error="B-Rep vertex index out of range"; return false;
        }
        point=vec(BRep_Tool::Pnt(TopoDS::Vertex(vertices.FindKey(static_cast<int>(vertex_index)))));
        return finite(point);
    } catch (const Standard_Failure& e) { failure(error,e); }
      catch (const std::exception& e) { error=e.what(); }
    return false;
}

bool edge_anchor(const BrepShape& shape, uint64_t edge_index, double edge_fraction,
                 gx3de_vec3& point, gx3de_vec3& tangent, std::string& error) {
    point={}; tangent={}; error.clear();
    if (!valid_shape(shape) || !valid_fraction(edge_fraction)) {
        error="invalid B-Rep shape or edge fraction"; return false;
    }
    try {
        TopTools_IndexedMapOfShape edges;
        TopExp::MapShapes(shape.shape,TopAbs_EDGE,edges);
        if (!index_in_map(edge_index,edges)) {
            error="B-Rep edge index out of range"; return false;
        }
        BRepAdaptor_Curve curve(TopoDS::Edge(edges.FindKey(static_cast<int>(edge_index))));
        const double first=curve.FirstParameter(), last=curve.LastParameter();
        if (!std::isfinite(first) || !std::isfinite(last) || !(last>first)) {
            error="B-Rep edge has no finite parameter range"; return false;
        }
        const double parameter=first+(last-first)*edge_fraction;
        gp_Pnt p; gp_Vec derivative;
        curve.D1(parameter,p,derivative);
        if (derivative.SquareMagnitude()<=1e-30) {
            error="B-Rep edge tangent is undefined"; return false;
        }
        derivative.Normalize();
        point=vec(p);
        tangent={derivative.X(),derivative.Y(),derivative.Z()};
        return finite(point) && finite(tangent);
    } catch (const Standard_Failure& e) { failure(error,e); }
      catch (const std::exception& e) { error=e.what(); }
    return false;
}

bool face_anchor(const BrepShape& shape, uint64_t face_index,
                 double face_u_fraction, double face_v_fraction,
                 BrepFaceAnchor& out, std::string& error) {
    out={}; error.clear();
    if (!valid_shape(shape) || !valid_fraction(face_u_fraction) ||
        !valid_fraction(face_v_fraction)) {
        error="invalid B-Rep shape or face coordinates"; return false;
    }
    try {
        TopTools_IndexedMapOfShape faces;
        TopExp::MapShapes(shape.shape,TopAbs_FACE,faces);
        if (!index_in_map(face_index,faces)) {
            error="B-Rep face index out of range"; return false;
        }
        const TopoDS_Face face=TopoDS::Face(faces.FindKey(static_cast<int>(face_index)));
        Standard_Real umin,umax,vmin,vmax;
        BRepTools::UVBounds(face,umin,umax,vmin,vmax);
        if (!std::isfinite(umin) || !std::isfinite(umax) ||
            !std::isfinite(vmin) || !std::isfinite(vmax) ||
            !(umax>umin) || !(vmax>vmin)) {
            error="B-Rep face has no finite parameter bounds"; return false;
        }
        const double u=umin+(umax-umin)*face_u_fraction;
        const double v=vmin+(vmax-vmin)*face_v_fraction;
        BRepClass_FaceClassifier classifier(face,gp_Pnt2d(u,v),1e-9);
        if (classifier.State()!=TopAbs_IN && classifier.State()!=TopAbs_ON) {
            error="B-Rep face coordinates lie outside trimmed face"; return false;
        }
        BRepAdaptor_Surface surface(face,Standard_True);
        BRepLProp_SLProps properties(surface,u,v,1,1e-12);
        if (!properties.IsNormalDefined()) {
            error="B-Rep face normal is undefined"; return false;
        }
        const gp_Pnt p=surface.Value(u,v);
        gp_Dir normal=properties.Normal();
        if (face.Orientation()==TopAbs_REVERSED) normal.Reverse();
        out={vec(p),{normal.X(),normal.Y(),normal.Z()}};
        return finite(out.point) && finite(out.normal);
    } catch (const Standard_Failure& e) { failure(error,e); }
      catch (const std::exception& e) { error=e.what(); }
    out={}; return false;
}

bool closest_face_fraction(const BrepShape& shape,gx3de_vec3 point,double tolerance,
    uint64_t& face_index,double& u_fraction,double& v_fraction,std::string& error) {
    error.clear();if(!valid_shape(shape)||!finite(point)||!std::isfinite(tolerance)||
        tolerance<=0){error="invalid B-Rep display hit";return false;}
    try{
        TopTools_IndexedMapOfShape faces;TopExp::MapShapes(shape.shape,TopAbs_FACE,faces);
        if(faces.Extent()>10000){error="B-Rep face pick budget exceeded";return false;}
        const gp_Pnt query(point.x,point.y,point.z);
        double best=std::numeric_limits<double>::infinity();int best_index=0;
        double best_u=0,best_v=0;bool ambiguous=false;
        for(int index=1;index<=faces.Extent();++index){
            const TopoDS_Face face=TopoDS::Face(faces.FindKey(index));
            Standard_Real umin,umax,vmin,vmax;BRepTools::UVBounds(face,umin,umax,vmin,vmax);
            if(!std::isfinite(umin)||!std::isfinite(umax)||!std::isfinite(vmin)||
               !std::isfinite(vmax)||!(umax>umin)||!(vmax>vmin))continue;
            Handle(Geom_Surface) surface=BRep_Tool::Surface(face);
            if(surface.IsNull())continue;
            GeomAPI_ProjectPointOnSurf project(query,surface,umin,umax,vmin,vmax);
            if(project.NbPoints()<1)continue;
            const double distance=project.LowerDistance();
            if(!std::isfinite(distance)||distance>tolerance)continue;
            Standard_Real u,v;project.LowerDistanceParameters(u,v);
            BRepClass_FaceClassifier classifier(face,gp_Pnt2d(u,v),1e-8);
            if(classifier.State()!=TopAbs_IN&&classifier.State()!=TopAbs_ON)continue;
            if(distance<best-1e-6){best=distance;best_index=index;
                best_u=std::clamp((u-umin)/(umax-umin),0.0,1.0);
                best_v=std::clamp((v-vmin)/(vmax-vmin),0.0,1.0);ambiguous=false;}
            else if(std::abs(distance-best)<=1e-6)ambiguous=true;
        }
        if(best_index==0||ambiguous){error=best_index==0?"no close trimmed face":
            "B-Rep display hit lies on ambiguous shared topology";return false;}
        face_index=uint64_t(best_index-1);u_fraction=best_u;v_fraction=best_v;return true;
    }catch(const Standard_Failure& e){failure(error,e);return false;
    }catch(const std::exception& e){error=e.what();return false;}
}

bool edge_geometry(const BrepShape& shape,uint64_t edge_index,double tolerance,
                   gx3de_brep_edge_geometry& out,std::string& error) {
    out={};error.clear();
    if(!valid_shape(shape)||!std::isfinite(tolerance)||tolerance<=0){
        error="invalid B-Rep shape or edge length tolerance";return false;
    }
    try {
        TopTools_IndexedMapOfShape edges;
        TopExp::MapShapes(shape.shape,TopAbs_EDGE,edges);
        if(!index_in_map(edge_index,edges)){
            error="B-Rep edge index out of range";return false;
        }
        BRepAdaptor_Curve curve(TopoDS::Edge(edges.FindKey(static_cast<int>(edge_index))));
        const double first=curve.FirstParameter(),last=curve.LastParameter();
        if(!std::isfinite(first)||!std::isfinite(last)||!(last>first)){
            error="B-Rep edge has no finite parameter range";return false;
        }
        gp_Pnt first_point,last_point;gp_Vec first_derivative,last_derivative;
        curve.D1(first,first_point,first_derivative);
        curve.D1(last,last_point,last_derivative);
        if(first_derivative.SquareMagnitude()<=1e-30||
           last_derivative.SquareMagnitude()<=1e-30){
            error="B-Rep edge endpoint tangent is undefined";return false;
        }
        first_derivative.Normalize();last_derivative.Normalize();
        const double arc_length=GCPnts_AbscissaPoint::Length(curve,first,last,tolerance);
        if(!std::isfinite(arc_length)||arc_length<=0){
            error="B-Rep edge has no finite positive length";return false;
        }
        uint32_t type=GX3DE_BREP_CURVE_OTHER;
        switch(curve.GetType()){
        case GeomAbs_Line:type=GX3DE_BREP_CURVE_LINE;break;
        case GeomAbs_Circle:type=GX3DE_BREP_CURVE_CIRCLE;break;
        case GeomAbs_Ellipse:type=GX3DE_BREP_CURVE_ELLIPSE;break;
        case GeomAbs_Hyperbola:type=GX3DE_BREP_CURVE_HYPERBOLA;break;
        case GeomAbs_Parabola:type=GX3DE_BREP_CURVE_PARABOLA;break;
        case GeomAbs_BezierCurve:type=GX3DE_BREP_CURVE_BEZIER;break;
        case GeomAbs_BSplineCurve:type=GX3DE_BREP_CURVE_BSPLINE;break;
        case GeomAbs_OffsetCurve:type=GX3DE_BREP_CURVE_OFFSET;break;
        default:break;
        }
        gx3de_brep_edge_geometry result{};
        result.struct_size=sizeof(result);
        result.curve_type=type;
        result.first_parameter=first;result.last_parameter=last;
        result.length=arc_length;
        result.start=vec(first_point);result.end=vec(last_point);
        result.start_tangent={first_derivative.X(),first_derivative.Y(),first_derivative.Z()};
        result.end_tangent={last_derivative.X(),last_derivative.Y(),last_derivative.Z()};
        result.closed=uint32_t(distance2(result.start,result.end)<=tolerance*tolerance);
        if(!finite(result.start)||!finite(result.end)||
           !finite(result.start_tangent)||!finite(result.end_tangent)){
            error="B-Rep edge query returned non-finite geometry";return false;
        }
        out=result;return true;
    }catch(const Standard_Failure& e){failure(error,e);}
     catch(const std::exception& e){error=e.what();}
    out={};return false;
}

bool face_geometry(const BrepShape& shape,uint64_t face_index,
                   gx3de_brep_face_geometry& out,std::string& error) {
    out={};error.clear();
    if(!valid_shape(shape)){error="invalid B-Rep shape";return false;}
    try {
        TopTools_IndexedMapOfShape faces;
        TopExp::MapShapes(shape.shape,TopAbs_FACE,faces);
        if(!index_in_map(face_index,faces)){
            error="B-Rep face index out of range";return false;
        }
        const TopoDS_Face face=TopoDS::Face(faces.FindKey(static_cast<int>(face_index)));
        Standard_Real umin,umax,vmin,vmax;
        BRepTools::UVBounds(face,umin,umax,vmin,vmax);
        if(!std::isfinite(umin)||!std::isfinite(umax)||
           !std::isfinite(vmin)||!std::isfinite(vmax)||
           !(umax>umin)||!(vmax>vmin)){
            error="B-Rep face has no finite UV bounds";return false;
        }
        BRepAdaptor_Surface surface(face,Standard_True);
        uint32_t type=GX3DE_BREP_SURFACE_OTHER;
        switch(surface.GetType()){
        case GeomAbs_Plane:type=GX3DE_BREP_SURFACE_PLANE;break;
        case GeomAbs_Cylinder:type=GX3DE_BREP_SURFACE_CYLINDER;break;
        case GeomAbs_Cone:type=GX3DE_BREP_SURFACE_CONE;break;
        case GeomAbs_Sphere:type=GX3DE_BREP_SURFACE_SPHERE;break;
        case GeomAbs_Torus:type=GX3DE_BREP_SURFACE_TORUS;break;
        case GeomAbs_BezierSurface:type=GX3DE_BREP_SURFACE_BEZIER;break;
        case GeomAbs_BSplineSurface:type=GX3DE_BREP_SURFACE_BSPLINE;break;
        case GeomAbs_SurfaceOfRevolution:type=GX3DE_BREP_SURFACE_REVOLUTION;break;
        case GeomAbs_SurfaceOfExtrusion:type=GX3DE_BREP_SURFACE_EXTRUSION;break;
        case GeomAbs_OffsetSurface:type=GX3DE_BREP_SURFACE_OFFSET;break;
        default:break;
        }
        out={sizeof(out),type,uint32_t(surface.IsUClosed()),uint32_t(surface.IsVClosed()),
             umin,umax,vmin,vmax,{}};
        return true;
    }catch(const Standard_Failure& e){failure(error,e);}
     catch(const std::exception& e){error=e.what();}
    out={};return false;
}

bool transformed(const BrepShape& shape, const gx3de_mat4& matrix,
                 std::shared_ptr<BrepShape>& out, std::string& error) {
    out.reset(); error.clear();
    if (!valid_shape(shape)) { error="invalid B-Rep shape"; return false; }
    for (double value : matrix.m) if (!std::isfinite(value)) {
        error="B-Rep transform contains non-finite value"; return false;
    }
    if (std::abs(matrix.m[3])>1e-12 || std::abs(matrix.m[7])>1e-12 ||
        std::abs(matrix.m[11])>1e-12 || std::abs(matrix.m[15]-1)>1e-12) {
        error="B-Rep transform must be affine"; return false;
    }
    const double a=matrix.m[0], b=matrix.m[4], c=matrix.m[8];
    const double d=matrix.m[1], e=matrix.m[5], f=matrix.m[9];
    const double g=matrix.m[2], h=matrix.m[6], i=matrix.m[10];
    const double det=a*(e*i-f*h)-b*(d*i-f*g)+c*(d*h-e*g);
    const double scale=std::max({std::abs(a),std::abs(b),std::abs(c),
                                 std::abs(d),std::abs(e),std::abs(f),
                                 std::abs(g),std::abs(h),std::abs(i)});
    if (!(scale>0) || !std::isfinite(det) ||
        std::abs(det) <= 1e-14*scale*scale*scale) {
        error="B-Rep transform is singular or ill-conditioned"; return false;
    }
    try {
        const gx3de_mat4 identity{{1,0,0,0, 0,1,0,0, 0,0,1,0, 0,0,0,1}};
        bool is_identity=true;
        for (int k=0;k<16;++k) if (matrix.m[k]!=identity.m[k]) { is_identity=false; break; }
        if (is_identity) {
            out=std::make_shared<BrepShape>(shape.shape);
            return true;
        }
        const double n0=a*a+d*d+g*g, n1=b*b+e*e+h*h, n2=c*c+f*f+i*i;
        const double max_n=std::max({n0,n1,n2});
        const bool uniform=std::abs(n0-n1)<=1e-12*max_n &&
                           std::abs(n0-n2)<=1e-12*max_n &&
                           std::abs(a*b+d*e+g*h)<=1e-12*max_n &&
                           std::abs(a*c+d*f+g*i)<=1e-12*max_n &&
                           std::abs(b*c+e*f+h*i)<=1e-12*max_n;
        if (uniform) {
            // gp_Trsf keeps planes, lines and circles analytic. Its general
            // counterpart may turn even a translated box into B-splines,
            // which makes subsequent OCCT boolean operations unreliable.
            gp_Trsf affine;
            affine.SetValues(a,b,c,matrix.m[12], d,e,f,matrix.m[13],
                             g,h,i,matrix.m[14]);
            BRepBuilderAPI_Transform build(shape.shape,affine,Standard_True);
            if (!build.IsDone() || build.Shape().IsNull()) {
                error="OpenCASCADE B-Rep transform failed"; return false;
            }
            out=std::make_shared<BrepShape>(build.Shape());
            return true;
        }
        gp_GTrsf affine;
        for (int row=0;row<3;++row)
            for (int col=0;col<4;++col)
                affine.SetValue(row+1,col+1,matrix.m[col*4+row]);
        affine.SetForm();
        BRepBuilderAPI_GTransform build(shape.shape,affine,Standard_True);
        if (!build.IsDone() || build.Shape().IsNull()) {
            error="OpenCASCADE B-Rep transform failed"; return false;
        }
        out=std::make_shared<BrepShape>(build.Shape());
        return true;
    } catch (const Standard_Failure& e) { failure(error,e); }
      catch (const std::exception& e) { error=e.what(); }
    return false;
}

bool properties(const BrepShape& shape, double& area, double& volume) {
    area=std::numeric_limits<double>::quiet_NaN();
    volume=std::numeric_limits<double>::quiet_NaN();
    if (!valid_shape(shape)) return false;
    try {
        GProp_GProps surface;
        BRepGProp::SurfaceProperties(shape.shape,surface);
        area=surface.Mass();
        if (!std::isfinite(area)) return false;
        for (TopExp_Explorer it(shape.shape,TopAbs_SOLID);it.More();it.Next()) {
            GProp_GProps solid;
            BRepGProp::VolumeProperties(shape.shape,solid,Standard_True);
            volume=solid.Mass();
            return std::isfinite(volume);
        }
        return true;
    } catch (const Standard_Failure&) { return false; }
}

bool shape_fingerprint(const BrepShape& shape,const std::string& namespace_utf8,
                       std::string& out,std::string& error) {
    out.clear();error.clear();
    if(!valid_shape(shape)){error="invalid B-Rep shape";return false;}
    struct DigestBuffer final : std::streambuf {
        EVP_MD_CTX* ctx;
        uint64_t size=0;
        bool failed=false,over_limit=false;
        explicit DigestBuffer(EVP_MD_CTX* value):ctx(value){}
        std::streamsize xsputn(const char* data,std::streamsize count) override {
            if(count<0||uint64_t(count)>256ull*1024*1024-size){failed=over_limit=true;return 0;}
            if(EVP_DigestUpdate(ctx,data,size_t(count))!=1){failed=true;return 0;}
            size+=uint64_t(count);return count;
        }
        int overflow(int value) override {
            if(value==traits_type::eof())return traits_type::not_eof(value);
            const char c=char(value);
            return xsputn(&c,1)==1?value:traits_type::eof();
        }
    };
    try {
        std::unique_ptr<EVP_MD_CTX,decltype(&EVP_MD_CTX_free)> ctx(EVP_MD_CTX_new(),EVP_MD_CTX_free);
        if(!ctx||EVP_DigestInit_ex(ctx.get(),EVP_sha256(),nullptr)!=1){error="SHA-256 initialization failed";return false;}
        const std::string prefix=std::string("GX3DE_BREP_v1|OCCT=")+OCC_VERSION_COMPLETE+"|"+namespace_utf8+"|";
        if(EVP_DigestUpdate(ctx.get(),prefix.data(),prefix.size())!=1){error="SHA-256 update failed";return false;}
        DigestBuffer buffer(ctx.get());std::ostream stream(&buffer);
        BRepTools::Write(shape.shape,stream,Standard_False,Standard_False,TopTools_FormatVersion_CURRENT);
        if(buffer.failed||!stream.good()||buffer.size==0){
            error=buffer.over_limit?"B-Rep serialization exceeded 256 MiB":"B-Rep serialization failed";return false;}
        std::array<unsigned char,32> digest{};unsigned int count=0;
        if(EVP_DigestFinal_ex(ctx.get(),digest.data(),&count)!=1||count!=32){error="SHA-256 finalization failed";return false;}
        static constexpr char hex[]="0123456789abcdef";out.resize(64);
        for(size_t i=0;i<digest.size();++i){out[2*i]=hex[digest[i]>>4];out[2*i+1]=hex[digest[i]&15];}
        return true;
    } catch(const Standard_Failure& e){failure(error,e);}
      catch(const std::exception& e){error=e.what();}
    return false;
}

bool extrude_profile(const std::vector<ProfileContour>& contours,
    gx3de_vec3 origin,gx3de_vec3 u,gx3de_vec3 v,double height,
    std::shared_ptr<BrepShape>& out,std::string& error){
    out.reset();error.clear();
    if(contours.empty()||!finite(origin)||!finite(u)||!finite(v)||!std::isfinite(height)||height==0){error="invalid profile or signed extrusion distance";return false;}
    struct UV {long double x,y;};
    std::vector<std::vector<UV>> points;std::vector<long double> areas;
    for(const auto& c:contours){
        if(!c.closed||c.points.size()<3){error="extrusion requires closed contours";return false;}
        std::vector<UV> xy;
        for(auto p:c.points){auto q=gx3de_vec3{p.x-origin.x,p.y-origin.y,p.z-origin.z};xy.push_back({q.x*u.x+q.y*u.y+q.z*u.z,q.x*v.x+q.y*v.y+q.z*v.z});}
        long double area=0;auto base=xy.front();
        for(size_t j=0;j<xy.size();++j){auto a=xy[j],b=xy[(j+1)%xy.size()];area+=(a.x-base.x)*(b.y-base.y)-(b.x-base.x)*(a.y-base.y);}
        if(!std::isfinite(area)||area==0){error="extrusion contour has zero area";return false;}
        areas.push_back(area);points.push_back(std::move(xy));
    }
    auto contains=[](const std::vector<UV>& polygon,UV p){
        bool in=false;
        for(size_t j=0,k=polygon.size()-1;j<polygon.size();k=j++){
            auto a=polygon[j],b=polygon[k];
            if((a.y>p.y)!=(b.y>p.y)&&p.x<(b.x-a.x)*(p.y-a.y)/(b.y-a.y)+a.x)in=!in;
        }
        return in;
    };
    std::vector<int> depth(contours.size(),0),parent(contours.size(),-1);
    for(size_t i=0;i<contours.size();++i){
        long double parent_area=std::numeric_limits<long double>::infinity();
        for(size_t j=0;j<contours.size();++j)if(i!=j&&contains(points[j],points[i][0])){
            ++depth[i];if(std::abs(areas[j])<parent_area){parent_area=std::abs(areas[j]);parent[i]=static_cast<int>(j);}
        }
    }
    try {
        auto wire=[&](size_t i,bool outer){
            BRepBuilderAPI_MakePolygon polygon;
            const auto& c=contours[i];bool forward=(areas[i]>0)==outer;
            for(size_t j=0;j<c.points.size();++j){auto p=c.points[forward?j:c.points.size()-1-j];polygon.Add(gp_Pnt(p.x,p.y,p.z));}
            polygon.Close();return polygon.Wire();
        };
        gx3de_vec3 normal{u.y*v.z-u.z*v.y,u.z*v.x-u.x*v.z,u.x*v.y-u.y*v.x};
        gp_Dir direction(normal.x,normal.y,normal.z);
        gp_Pln plane(gp_Pnt(origin.x,origin.y,origin.z),direction);
        BRep_Builder builder;TopoDS_Compound compound;builder.MakeCompound(compound);
        size_t solids=0;
        for(size_t i=0;i<contours.size();++i)if(depth[i]%2==0){
            BRepBuilderAPI_MakeFace face(plane,wire(i,true),Standard_True);
            for(size_t j=0;j<contours.size();++j)if(parent[j]==static_cast<int>(i)&&depth[j]==depth[i]+1)face.Add(wire(j,false));
            face.Build();
            if(!face.IsDone()||!BRepCheck_Analyzer(face.Face(),Standard_True).IsValid()){error="profile face or hole topology is invalid";return false;}
            BRepPrimAPI_MakePrism prism(face.Face(),gp_Vec(direction)*height,Standard_True,Standard_True);
            prism.Build();
            if(!prism.IsDone()||prism.Shape().IsNull()){error="OpenCASCADE profile prism failed";return false;}
            builder.Add(compound,prism.Shape());++solids;
        }
        if(!solids||!closed_solids_only(compound,error))return false;
        out=std::make_shared<BrepShape>(compound);return true;
    }catch(const Standard_Failure& e){failure(error,e);}
     catch(const std::exception& e){error=e.what();}
    return false;
}
bool write_step(const BrepShape& shape,const std::string& path,double millimeters_per_unit,std::string& error){
    error.clear();
    if(!valid_shape(shape)||path.empty()||!std::isfinite(millimeters_per_unit)||millimeters_per_unit<=0){error="invalid STEP export shape, path or asserted coordinate unit";return false;}
    try {
        STEPControl_Writer writer;
        // Per-writer model state; do not change process-global Interface_Static
        // or reinterpret metre coordinates as millimetres in the output file.
        writer.Model()->SetLocalLengthUnit(millimeters_per_unit);
        writer.Model()->SetWriteLengthUnit(1.0);
        const auto copy=BRepBuilderAPI_Copy(shape.shape,Standard_True,Standard_False).Shape();
        if(writer.Transfer(copy,STEPControl_AsIs)!=IFSelect_RetDone||writer.Write(path.c_str())!=IFSelect_RetDone){error="OpenCASCADE STEP export failed";return false;}
        return true;
    }catch(const Standard_Failure& e){failure(error,e);}
     catch(const std::exception& e){error=e.what();}
    return false;
}
} // namespace gx3de_backend
