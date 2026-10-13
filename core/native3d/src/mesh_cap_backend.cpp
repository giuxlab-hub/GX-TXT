// SPDX-License-Identifier: GPL-3.0-or-later
#include "mesh_cap_backend.hpp"
#include "profile_backend.hpp"
#include "vtk_mesh_backend.hpp"
#include "mesh_self_intersection_backend.hpp"
#include <vtkCellArray.h>
#include <vtkContourTriangulator.h>
#include <vtkNew.h>
#include <vtkPoints.h>
#include <vtkPolyData.h>
#include <algorithm>
#include <cmath>
#include <cstdint>
#include <limits>
#include <new>
#include <vector>

namespace gx3de_backend {
namespace {
struct Point2 {double x,y;};
static gx3de_vec3 sub(gx3de_vec3 a,gx3de_vec3 b){return {a.x-b.x,a.y-b.y,a.z-b.z};}
static double dot(gx3de_vec3 a,gx3de_vec3 b){return a.x*b.x+a.y*b.y+a.z*b.z;}
static double distance(gx3de_vec3 a,gx3de_vec3 b){return std::hypot(a.x-b.x,a.y-b.y,a.z-b.z);}
static Point2 project(gx3de_vec3 p,gx3de_vec3 origin,gx3de_vec3 u,gx3de_vec3 v){
    auto delta=sub(p,origin);return {dot(delta,u),dot(delta,v)};
}
static double cross(Point2 a,Point2 b,Point2 c){
    return (b.x-a.x)*(c.y-a.y)-(b.y-a.y)*(c.x-a.x);
}
static double length(Point2 a,Point2 b){return std::hypot(a.x-b.x,a.y-b.y);}
static double area2(const std::vector<Point2>& polygon){
    double sum=0;
    for(size_t i=0;i<polygon.size();++i){auto a=polygon[i],b=polygon[(i+1)%polygon.size()];
        sum+=a.x*b.y-a.y*b.x;}
    return sum;
}
static bool on_segment(Point2 p,Point2 a,Point2 b,double tolerance){
    const double edge=length(a,b);
    return edge>tolerance&&std::abs(cross(a,b,p))<=tolerance*edge&&
           p.x>=std::min(a.x,b.x)-tolerance&&p.x<=std::max(a.x,b.x)+tolerance&&
           p.y>=std::min(a.y,b.y)-tolerance&&p.y<=std::max(a.y,b.y)+tolerance;
}
static int side(Point2 a,Point2 b,Point2 p,double tolerance){
    const double value=cross(a,b,p),eps=tolerance*length(a,b);
    return value>eps?1:(value<-eps?-1:0);
}
static bool edges_intersect(Point2 a,Point2 b,Point2 c,Point2 d,double tolerance){
    if(on_segment(a,c,d,tolerance)||on_segment(b,c,d,tolerance)||
       on_segment(c,a,b,tolerance)||on_segment(d,a,b,tolerance))return true;
    const int ab_c=side(a,b,c,tolerance),ab_d=side(a,b,d,tolerance);
    const int cd_a=side(c,d,a,tolerance),cd_b=side(c,d,b,tolerance);
    return ab_c*ab_d<0&&cd_a*cd_b<0;
}
static bool simple_polygon(const std::vector<Point2>& polygon,double tolerance){
    if(polygon.size()<3||!std::isfinite(area2(polygon))||
       std::abs(area2(polygon))<=2*tolerance*tolerance)return false;
    const size_t n=polygon.size();
    for(size_t i=0;i<n;++i){
        const size_t next=(i+1)%n;
        if(!(length(polygon[i],polygon[next])>tolerance))return false;
        for(size_t j=i+1;j<n;++j){
            if(j==next||(j+1)%n==i)continue;
            if(edges_intersect(polygon[i],polygon[next],polygon[j],polygon[(j+1)%n],tolerance))return false;
        }
    }
    return true;
}
static bool contains_or_touches(const std::vector<Point2>& polygon,Point2 point,double tolerance){
    bool inside=false;
    for(size_t i=0,j=polygon.size()-1;i<polygon.size();j=i++){
        const auto a=polygon[j],b=polygon[i];
        if(on_segment(point,a,b,tolerance))return true;
        if((a.y>point.y)!=(b.y>point.y)){
            const double x=a.x+(point.y-a.y)*(b.x-a.x)/(b.y-a.y);
            if(x>point.x)inside=!inside;
        }
    }
    return inside;
}
static bool boundaries_intersect(const std::vector<Point2>& a,const std::vector<Point2>& b,double tolerance){
    for(size_t i=0;i<a.size();++i)for(size_t j=0;j<b.size();++j)
        if(edges_intersect(a[i],a[(i+1)%a.size()],b[j],b[(j+1)%b.size()],tolerance))return true;
    return false;
}
static bool point_in_triangle_or_edge(Point2 point,Point2 a,Point2 b,Point2 c,
                                      int winding,double tolerance){
    return winding*cross(a,b,point)>=-tolerance*length(a,b)&&
           winding*cross(b,c,point)>=-tolerance*length(b,c)&&
           winding*cross(c,a,point)>=-tolerance*length(c,a);
}
// Ear removal uses the clipped mesh's own ordered boundary vertices. Every
// emitted cap face reverses the boundary winding, so the final edge check can
// prove that all side/cap edges pair with opposite orientation.
static bool triangulate_loop(const std::vector<uint32_t>& loop,const MeshData& mesh,
                             gx3de_vec3 origin,gx3de_vec3 u,gx3de_vec3 v,
                             double tolerance,std::vector<uint32_t>& triangles){
    std::vector<Point2> polygon;polygon.reserve(loop.size());
    for(uint32_t index:loop)polygon.push_back(project(mesh.vertices[index],origin,u,v));
    if(!simple_polygon(polygon,tolerance))return false;
    const int winding=area2(polygon)>0?1:-1;
    const double target_area=std::abs(area2(polygon))*0.5;
    std::vector<size_t> active(loop.size());
    for(size_t i=0;i<loop.size();++i)active[i]=i;
    double triangle_area=0;
    while(active.size()>3){
        bool found=false;
        for(size_t at=0;at<active.size();++at){
            const size_t prev=active[(at+active.size()-1)%active.size()];
            const size_t cur=active[at];
            const size_t next=active[(at+1)%active.size()];
            const double turn=winding*cross(polygon[prev],polygon[cur],polygon[next]);
            const double scale=std::max(length(polygon[prev],polygon[cur]),
                                        length(polygon[cur],polygon[next]));
            if(!(turn>tolerance*scale))continue;
            bool blocked=false;
            for(size_t other:active){
                if(other==prev||other==cur||other==next)continue;
                if(point_in_triangle_or_edge(polygon[other],polygon[prev],polygon[cur],polygon[next],winding,tolerance)){
                    blocked=true;break;
                }
            }
            if(blocked)continue;
            triangles.insert(triangles.end(),{loop[next],loop[cur],loop[prev]});
            triangle_area+=turn*0.5;
            active.erase(active.begin()+at);
            found=true;break;
        }
        if(!found)return false;
    }
    const double final_turn=winding*cross(polygon[active[0]],polygon[active[1]],polygon[active[2]]);
    const double scale=std::max(length(polygon[active[0]],polygon[active[1]]),
                                length(polygon[active[1]],polygon[active[2]]));
    if(!(final_turn>tolerance*scale))return false;
    triangles.insert(triangles.end(),{loop[active[2]],loop[active[1]],loop[active[0]]});
    triangle_area+=final_turn*0.5;
    return std::abs(triangle_area-target_area)<=
           std::max(tolerance*tolerance*loop.size(),target_area*1e-10);
}
static bool same_cycle(const ProfileContour& contour,const std::vector<uint32_t>& loop,
                       const MeshData& clipped,double tolerance){
    const size_t n=loop.size();if(contour.points.size()!=n)return false;
    for(size_t start=0;start<n;++start){
        if(distance(contour.points[0],clipped.vertices[loop[start]])>tolerance)continue;
        for(int direction:{1,-1}){
            bool matches=true;
            for(size_t i=1;i<n;++i){
                size_t j=direction>0?(start+i)%n:(start+n-(i%n))%n;
                if(distance(contour.points[i],clipped.vertices[loop[j]])>tolerance){matches=false;break;}
            }
            if(matches)return true;
        }
    }
    return false;
}
// vtkContourTriangulator uses the winding of the supplied contours to leave
// holes empty. Input points are the clipped mesh's actual boundary vertices;
// no new seam coordinates are allowed. The caller then checks area, topology
// and nonadjacent triangle intersections before publication.
static bool triangulate_nested(const std::vector<std::vector<uint32_t>>& loops,
                               const std::vector<std::vector<Point2>>& polygons,
                               const std::vector<unsigned>& depths,
                               const MeshData& clipped,gx3de_vec3 origin,
                               gx3de_vec3 u,gx3de_vec3 v,gx3de_vec3 normal,
                               double tolerance,int outer_sign,
                               std::vector<uint32_t>& output,std::string& error){
    size_t edge_count=0;
    for(const auto& loop:loops)edge_count+=loop.size();
    if(edge_count>10000||loops.size()>64){error="nested cap exceeds triangulation budget";return false;}
    vtkNew<vtkPoints> points;points->SetDataTypeToDouble();
    points->SetNumberOfPoints(static_cast<vtkIdType>(clipped.vertices.size()));
    for(size_t i=0;i<clipped.vertices.size();++i){auto p=clipped.vertices[i];
        points->SetPoint(static_cast<vtkIdType>(i),p.x,p.y,p.z);}
    vtkNew<vtkCellArray> lines;
    for(const auto& loop:loops)for(size_t i=0;i<loop.size();++i){
        vtkIdType edge[2]={static_cast<vtkIdType>(loop[i]),
                           static_cast<vtkIdType>(loop[(i+1)%loop.size()])};
        lines->InsertNextCell(2,edge);
    }
    vtkNew<vtkPolyData> contours;
    contours->SetPoints(points);contours->SetLines(lines);
    vtkNew<vtkCellArray> triangles;
    const double winding_normal[3]={outer_sign*normal.x,outer_sign*normal.y,
                                    outer_sign*normal.z};
    if(!vtkContourTriangulator::TriangulateContours(contours,0,
            static_cast<vtkIdType>(edge_count),triangles,winding_normal)){
        error="VTK could not triangulate nested cap contours";return false;
    }
    double expected=0,actual=0;
    for(size_t i=0;i<polygons.size();++i)
        expected+=(depths[i]%2?-1.0:1.0)*std::abs(area2(polygons[i]))*0.5;
    if(!(expected>tolerance*tolerance)){
        error="nested cap has no positive planar area";return false;
    }
    vtkIdType count=0;const vtkIdType* ids=nullptr;
    triangles->InitTraversal();
    while(triangles->GetNextCell(count,ids)){
        if(count!=3){error="nested cap contains a nontriangle";return false;}
        uint32_t index[3]{};
        for(int i=0;i<3;++i){
            if(ids[i]<0||static_cast<uint64_t>(ids[i])>=clipped.vertices.size()){
                error="nested cap references a point outside clipped geometry";return false;
            }
            index[i]=static_cast<uint32_t>(ids[i]);
        }
        if(index[0]==index[1]||index[1]==index[2]||index[2]==index[0]){
            error="nested cap contains a collapsed triangle";return false;
        }
        Point2 p[3]{};
        for(int i=0;i<3;++i)p[i]=project(clipped.vertices[index[i]],origin,u,v);
        const double signed_twice=cross(p[0],p[1],p[2]);
        if(!std::isfinite(signed_twice)||std::abs(signed_twice)<=tolerance*tolerance){
            error="nested cap contains a zero-area triangle";return false;
        }
        Point2 centroid{(p[0].x+p[1].x+p[2].x)/3,(p[0].y+p[1].y+p[2].y)/3};
        unsigned contained=0;
        for(const auto& polygon:polygons)
            if(contains_or_touches(polygon,centroid,tolerance))++contained;
        if(!(contained%2)){
            error="nested cap triangle enters a hole or exterior";return false;
        }
        actual+=std::abs(signed_twice)*0.5;
        if((signed_twice>0?1:-1)==outer_sign)std::swap(index[0],index[2]);
        output.insert(output.end(),{index[0],index[1],index[2]});
    }
    if(output.empty()||std::abs(actual-expected)>
            std::max(tolerance*tolerance*edge_count,expected*1e-8)){
        error="nested cap area differs from contour area";return false;
    }
    return true;
}
}

gx3de_result capped_clip_mesh(const MeshData& input,gx3de_vec3 origin,
                              gx3de_vec3 normal,gx3de_vec3 u,gx3de_vec3 v,
                              bool keep_positive,double tolerance,
                              MeshData& output,std::string& error){
    error.clear();
    if(!std::isfinite(tolerance)||tolerance<=0){error="invalid cap tolerance";return GX3DE_INVALID_ARGUMENT;}
    try {
        std::vector<std::vector<uint32_t>> source_loops;
        if(!boundary_loops(input,source_loops,error))return GX3DE_DEGENERATE;
        if(!source_loops.empty()){
            error="capping requires a closed input mesh";return GX3DE_UNSUPPORTED;
        }
        uint64_t source_intersections=0;
        if(!mesh_self_intersections(input,0,source_intersections,error))return GX3DE_DEGENERATE;
        if(source_intersections){
            error="capping requires a source mesh without self-intersections";
            return GX3DE_UNSUPPORTED;
        }
        // A tangent or coincident plane with no material on the discarded side
        // has an exact result: the original closed mesh or an empty solid.
        // No new cap topology is needed in either case.
        double minimum=std::numeric_limits<double>::infinity();
        double maximum=-std::numeric_limits<double>::infinity();
        for(auto point:input.vertices){const double d=dot(sub(point,origin),normal);
            minimum=std::min(minimum,d);maximum=std::max(maximum,d);}
        if(minimum==0&&maximum==0){error="coplanar zero-volume mesh cannot be capped";return GX3DE_UNSUPPORTED;}
        if(keep_positive){
            if(minimum>=0&&maximum>0){output=input;return GX3DE_OK;}
            if(maximum<=0)return GX3DE_NOT_FOUND;
        }else{
            if(maximum<=0&&minimum<0){output=input;return GX3DE_OK;}
            if(minimum>=0)return GX3DE_NOT_FOUND;
        }
        // A plane through input vertices while also crossing material needs a
        // separate topology policy; transverse cuts avoid that ambiguity.
        for(auto point:input.vertices)if(std::abs(dot(sub(point,origin),normal))<=tolerance){
            error="capping a plane through an input vertex is unsupported";
            return GX3DE_UNSUPPORTED;
        }
        std::vector<Segment> segments;
        if(!vtk_section(input.vertices,input.triangles,origin,normal,segments,error))return GX3DE_DEGENERATE;
        std::vector<gx3de_segment3> section;section.reserve(segments.size());
        for(auto segment:segments)section.push_back({segment.a,segment.b});
        std::vector<ProfileContour> contours;
        if(!chain_section(section,origin,u,v,tolerance,contours,error))return GX3DE_UNSUPPORTED;
        std::vector<std::vector<Point2>> polygons(contours.size());
        for(size_t i=0;i<contours.size();++i){
            for(auto point:contours[i].points)
                polygons[i].push_back(project(point,origin,u,v));
            if(!contours[i].closed||!simple_polygon(polygons[i],tolerance)){
                error="capping requires simple closed nondegenerate contours";
                return GX3DE_UNSUPPORTED;
            }
        }
        for(size_t i=0;i<polygons.size();++i)for(size_t j=i+1;j<polygons.size();++j){
            if(boundaries_intersect(polygons[i],polygons[j],tolerance)){
                error="touching or intersecting cap contours are unsupported";
                return GX3DE_UNSUPPORTED;
            }
        }
        std::vector<int> parents(polygons.size(),-1);
        std::vector<unsigned> depths(polygons.size(),0);
        for(size_t i=0;i<polygons.size();++i){
            double parent_area=std::numeric_limits<double>::infinity();
            const double own_area=std::abs(area2(polygons[i]));
            for(size_t j=0;j<polygons.size();++j)if(j!=i&&
                    contains_or_touches(polygons[j],polygons[i][0],tolerance)){
                const double area=std::abs(area2(polygons[j]));
                if(area<=own_area+tolerance*tolerance){
                    error="ambiguous nested cap contour ordering";return GX3DE_UNSUPPORTED;
                }
                if(area<parent_area){parent_area=area;parents[i]=static_cast<int>(j);}
            }
        }
        bool nested=false;
        for(size_t i=0;i<polygons.size();++i){
            int parent=parents[i];
            while(parent>=0){
                if(++depths[i]>polygons.size()){
                    error="cyclic nested cap contours";return GX3DE_UNSUPPORTED;
                }
                parent=parents[static_cast<size_t>(parent)];
            }
            nested|=depths[i]>0;
        }
        MeshData clipped;
        if(!vtk_clip_mesh(input.vertices,input.triangles,origin,normal,keep_positive,clipped,error))
            return GX3DE_DEGENERATE;
        if(clipped.triangles.empty())return GX3DE_NOT_FOUND;
        std::vector<std::vector<uint32_t>> loops;
        if(!boundary_loops(clipped,loops,error))return GX3DE_DEGENERATE;
        if(loops.size()!=contours.size()){
            error="clipped boundary does not match section contour count";
            return GX3DE_UNSUPPORTED;
        }
        std::vector<bool> matched(loops.size(),false);
        std::vector<std::vector<uint32_t>> ordered_loops(contours.size());
        for(size_t contour_index=0;contour_index<contours.size();++contour_index){
            const auto& contour=contours[contour_index];
            size_t selected=loops.size();
            for(size_t i=0;i<loops.size();++i)if(!matched[i]&&same_cycle(contour,loops[i],clipped,tolerance)){
                if(selected!=loops.size()){
                    error="ambiguous clipped boundary contour match";return GX3DE_UNSUPPORTED;
                }
                selected=i;
            }
            if(selected==loops.size()){
                error="clipped boundary differs from actual section contour";return GX3DE_UNSUPPORTED;
            }
            matched[selected]=true;
            const auto& loop=loops[selected];
            for(uint32_t index:loop){auto p=clipped.vertices[index];
                if(std::abs(dot(sub(p,origin),normal))>tolerance){
                    error="clipped boundary is not on the section plane";return GX3DE_UNSUPPORTED;
                }
            }
            ordered_loops[contour_index]=loop;
        }
        if(nested){
            std::vector<std::vector<Point2>> loop_polygons(ordered_loops.size());
            int outer_sign=0;
            for(size_t i=0;i<ordered_loops.size();++i){
                for(uint32_t index:ordered_loops[i])
                    loop_polygons[i].push_back(project(clipped.vertices[index],origin,u,v));
                const int sign=area2(loop_polygons[i])>0?1:-1;
                if(parents[i]>=0){
                    const auto& parent=ordered_loops[static_cast<size_t>(parents[i])];
                    std::vector<Point2> parent_polygon;parent_polygon.reserve(parent.size());
                    for(uint32_t index:parent)
                        parent_polygon.push_back(project(clipped.vertices[index],origin,u,v));
                    if(sign==(area2(parent_polygon)>0?1:-1)){
                        error="nested cap hole and parent have equal winding";
                        return GX3DE_UNSUPPORTED;
                    }
                }else if(outer_sign==0)outer_sign=sign;
                else if(sign!=outer_sign){
                    error="nested cap outer contours have inconsistent winding";
                    return GX3DE_UNSUPPORTED;
                }
            }
            if(!triangulate_nested(ordered_loops,loop_polygons,depths,clipped,
                    origin,u,v,normal,tolerance,outer_sign,clipped.triangles,error))
                return GX3DE_UNSUPPORTED;
        }else for(const auto& loop:ordered_loops){
            if(!triangulate_loop(loop,clipped,origin,u,v,tolerance,clipped.triangles)){
                error="clipped boundary cannot be triangulated safely";
                return GX3DE_UNSUPPORTED;
            }
        }
        std::vector<std::vector<uint32_t>> remaining;
        if(!boundary_loops(clipped,remaining,error)||!remaining.empty()){
            if(error.empty())error="cap did not close every mesh boundary";
            return GX3DE_DEGENERATE;
        }
        uint64_t result_intersections=0;
        if(!mesh_self_intersections(clipped,0,result_intersections,error))return GX3DE_DEGENERATE;
        if(result_intersections){
            error="capped mesh contains self-intersecting faces";
            return GX3DE_UNSUPPORTED;
        }
        output=std::move(clipped);
        return GX3DE_OK;
    }catch(const std::bad_alloc&){error="insufficient memory for capped mesh clip";return GX3DE_OUT_OF_MEMORY;}
}
}
