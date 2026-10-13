/* SPDX-License-Identifier: GPL-3.0-or-later */
#include "vtk_mesh_backend.hpp"

#include <vtkCellArray.h>
#include <vtkClipPolyData.h>
#include <vtkCutter.h>
#include <vtkGenericCell.h>
#include <vtkType.h>
#include <vtkNew.h>
#include <vtkPlane.h>
#include <vtkPoints.h>
#include <vtkPolyData.h>
#include <vtkStaticCellLocator.h>
#include <vtkTriangleFilter.h>

#include <algorithm>
#include <array>
#include <cmath>
#include <cstdint>
#include <limits>
#include <map>
#include <new>
#include <set>
#include <stdexcept>
#include <utility>

namespace gx3de_backend {
namespace {

bool finite(gx3de_vec3 p) {
    return std::isfinite(p.x) && std::isfinite(p.y) && std::isfinite(p.z);
}

bool less_point(gx3de_vec3 a, gx3de_vec3 b) {
    if (a.x != b.x) return a.x < b.x;
    if (a.y != b.y) return a.y < b.y;
    return a.z < b.z;
}

bool equal_point(gx3de_vec3 a, gx3de_vec3 b) {
    return a.x == b.x && a.y == b.y && a.z == b.z;
}

bool less_segment(const Segment& a, const Segment& b) {
    if (!equal_point(a.a, b.a)) return less_point(a.a, b.a);
    return less_point(a.b, b.b);
}

struct SegmentLess {
    bool operator()(const Segment& a, const Segment& b) const {
        return less_segment(a, b);
    }
};

struct PointLess {
    bool operator()(gx3de_vec3 a, gx3de_vec3 b) const {
        return less_point(a, b);
    }
};

Segment ordered_segment(gx3de_vec3 a, gx3de_vec3 b) {
    if (less_point(b, a)) std::swap(a, b);
    return {a, b};
}

double plane_distance(gx3de_vec3 p, gx3de_vec3 origin, gx3de_vec3 normal) {
    return (p.x-origin.x)*normal.x +
           (p.y-origin.y)*normal.y +
           (p.z-origin.z)*normal.z;
}

gx3de_vec3 intersect_edge(gx3de_vec3 a, gx3de_vec3 b,
                          double da, double db) {
    // Consistent edge order gives bit-identical shared-edge intersections.
    if (less_point(b, a)) {
        std::swap(a, b);
        std::swap(da, db);
    }
    const double t = da / (da-db);
    return {a.x+t*(b.x-a.x), a.y+t*(b.y-a.y), a.z+t*(b.z-a.z)};
}

bool validate_mesh(const std::vector<gx3de_vec3>& world_vertices,
                   const std::vector<uint32_t>& triangles,
                   std::string& error) {
    if (triangles.size() % 3 != 0) {
        error = "triangle index array is not a sequence of triples";
        return false;
    }
    const auto id_max = static_cast<size_t>(std::numeric_limits<vtkIdType>::max());
    if (world_vertices.size() > id_max || triangles.size() / 3 > id_max) {
        error = "mesh exceeds VTK index capacity";
        return false;
    }
    for (const auto& p : world_vertices) {
        if (!finite(p)) {
            error = "mesh contains a non-finite vertex";
            return false;
        }
    }
    for (const uint32_t index : triangles) {
        if (static_cast<size_t>(index) >= world_vertices.size()) {
            error = "mesh triangle references a missing vertex";
            return false;
        }
    }
    return true;
}

void fill_mesh(const std::vector<gx3de_vec3>& world_vertices,
               const std::vector<uint32_t>& triangles,
               vtkPolyData* mesh) {
    vtkNew<vtkPoints> points;
    points->SetDataTypeToDouble();
    points->Allocate(static_cast<vtkIdType>(world_vertices.size()));
    for (const auto& p : world_vertices) points->InsertNextPoint(p.x, p.y, p.z);

    vtkNew<vtkCellArray> cells;
    cells->AllocateEstimate(static_cast<vtkIdType>(triangles.size() / 3), 3);
    for (size_t i = 0; i < triangles.size(); i += 3) {
        const vtkIdType ids[3] = {
            static_cast<vtkIdType>(triangles[i]),
            static_cast<vtkIdType>(triangles[i + 1]),
            static_cast<vtkIdType>(triangles[i + 2])
        };
        cells->InsertNextCell(3, ids);
    }
    mesh->SetPoints(points);
    mesh->SetPolys(cells);
}

// A planar arrangement is necessary here: counting whole triangle edges leaves
// T junctions and the internal edges of partly overlapping faces in a section.
struct SectionPoint2 { long double x, y; };

SectionPoint2 section_project(gx3de_vec3 p, unsigned drop) {
    if (drop == 0) return {p.y,p.z};
    if (drop == 1) return {p.x,p.z};
    return {p.x,p.y};
}

long double section_cross(SectionPoint2 a, SectionPoint2 b,
                          SectionPoint2 c) {
    return (b.x-a.x)*(c.y-a.y)-(b.y-a.y)*(c.x-a.x);
}

long double section_parameter(SectionPoint2 a, SectionPoint2 b,
                              SectionPoint2 p) {
    const auto dx=b.x-a.x, dy=b.y-a.y;
    return std::abs(dx) >= std::abs(dy) ? (p.x-a.x)/dx : (p.y-a.y)/dy;
}

gx3de_vec3 section_lerp(gx3de_vec3 a, gx3de_vec3 b, long double t) {
    if (t <= 0) return a;
    if (t >= 1) return b;
    return {static_cast<double>(a.x+t*(b.x-a.x)),
            static_cast<double>(a.y+t*(b.y-a.y)),
            static_cast<double>(a.z+t*(b.z-a.z))};
}

struct SectionEdge {
    gx3de_vec3 a,b;
    std::vector<std::pair<long double,gx3de_vec3>> cuts;
    bool coplanar;
};

// All intersections are inserted in both participating edges. The same 3D
// point is used on both edges so the resulting topological vertices agree.
bool section_split_edges(std::vector<SectionEdge>& edges, unsigned drop,
                         std::string& error) {
    constexpr long double eps=128*std::numeric_limits<long double>::epsilon();
    for (auto& e:edges) {
        e.cuts.emplace_back(0,e.a);
        e.cuts.emplace_back(1,e.b);
    }
    for (size_t i=0;i<edges.size();++i) {
        const auto a=section_project(edges[i].a,drop);
        const auto b=section_project(edges[i].b,drop);
        for (size_t j=i+1;j<edges.size();++j) {
            const auto c=section_project(edges[j].a,drop);
            const auto d=section_project(edges[j].b,drop);
            const auto rx=b.x-a.x, ry=b.y-a.y;
            const auto sx=d.x-c.x, sy=d.y-c.y;
            const auto den=rx*sy-ry*sx;
            const auto qx=c.x-a.x, qy=c.y-a.y;
            if (den == 0) {
                if (section_cross(a,b,c) != 0 ||
                    section_cross(a,b,d) != 0) continue;
                const SectionPoint2 ends[4]={a,b,c,d};
                for (int k=0;k<4;++k) {
                    const auto ti=section_parameter(a,b,ends[k]);
                    const auto tj=section_parameter(c,d,ends[k]);
                    if (ti < 0 || ti > 1 || tj < 0 || tj > 1) continue;
                    const auto point=k==0?edges[i].a:k==1?edges[i].b:
                                     k==2?edges[j].a:edges[j].b;
                    edges[i].cuts.emplace_back(ti,point);
                    edges[j].cuts.emplace_back(tj,point);
                }
                continue;
            }
            const auto ti=(qx*sy-qy*sx)/den;
            const auto tj=(qx*ry-qy*rx)/den;
            if (ti < -eps || ti > 1+eps || tj < -eps || tj > 1+eps)
                continue;
            if (ti < 0 || ti > 1 || tj < 0 || tj > 1) {
                error="section has numerically ambiguous coplanar edge contact";
                return false;
            }
            gx3de_vec3 point;
            if (ti == 0) point=edges[i].a;
            else if (ti == 1) point=edges[i].b;
            else if (tj == 0) point=edges[j].a;
            else if (tj == 1) point=edges[j].b;
            else point=section_lerp(edges[i].a,edges[i].b,ti);
            if (!finite(point)) {
                error="section edge intersection is not finite";
                return false;
            }
            edges[i].cuts.emplace_back(ti,point);
            edges[j].cuts.emplace_back(tj,point);
        }
    }
    for (auto& e:edges) {
        std::sort(e.cuts.begin(),e.cuts.end(),[](const auto& a,const auto& b) {
            return a.first<b.first;
        });
        std::vector<std::pair<long double,gx3de_vec3>> unique;
        for (const auto& cut:e.cuts) {
            if (unique.empty() || cut.first != unique.back().first)
                unique.push_back(cut);
            else if (!equal_point(cut.second,unique.back().second)) {
                // Distinct constructions at one parameter must agree to input
                // precision; otherwise there is no safe topology to publish.
                const auto p=cut.second,q=unique.back().second;
                const auto scale=std::max({1.,std::abs(p.x),std::abs(p.y),
                    std::abs(p.z),std::abs(q.x),std::abs(q.y),std::abs(q.z)});
                const auto tol=64*std::numeric_limits<double>::epsilon()*scale;
                if (std::hypot(p.x-q.x,p.y-q.y,p.z-q.z)>tol) {
                    error="section has inconsistent coplanar intersection";
                    return false;
                }
                if (equal_point(cut.second,e.a) || equal_point(cut.second,e.b))
                    unique.back().second=cut.second;
            }
        }
        e.cuts=std::move(unique);
    }
    return true;
}

// Return occupancy on the left and right of an atomic edge. Triangles that
// contain its midpoint strictly fill both sides; triangles whose boundary
// contains the midpoint fill the side of their opposite vertex.
bool section_edge_occupancy(const Segment& segment,
        const std::vector<std::array<gx3de_vec3,3>>& faces,
        unsigned drop, bool& left, bool& right, std::string& error) {
    left=right=false;
    const auto a=section_project(segment.a,drop);
    const auto b=section_project(segment.b,drop);
    const SectionPoint2 m{(a.x+b.x)/2,(a.y+b.y)/2};
    for (const auto& face:faces) {
        SectionPoint2 p[3]={section_project(face[0],drop),
                            section_project(face[1],drop),
                            section_project(face[2],drop)};
        const auto coordinate_scale=std::max({std::abs(a.x),std::abs(a.y),
            std::abs(b.x),std::abs(b.y),std::abs(p[0].x),std::abs(p[0].y),
            std::abs(p[1].x),std::abs(p[1].y),std::abs(p[2].x),
            std::abs(p[2].y)});
        const auto edge_scale=std::max({std::hypot(a.x-b.x,a.y-b.y),
            std::hypot(p[0].x-p[1].x,p[0].y-p[1].y),
            std::hypot(p[1].x-p[2].x,p[1].y-p[2].y),
            std::hypot(p[2].x-p[0].x,p[2].y-p[0].y)});
        // Roundoff comes from stored double coordinates and intersections;
        // scale by coordinate magnitude and local edge length so a small
        // valid patch near the origin is not treated as degenerate.
        const auto tol=64*std::numeric_limits<double>::epsilon()*
                       coordinate_scale*edge_scale;
        const auto sign=section_cross(p[0],p[1],p[2])>0 ? 1 : -1;
        int boundary=-1;
        bool inside=true;
        for (int k=0;k<3;++k) {
            const auto value=sign*section_cross(p[k],p[(k+1)%3],m);
            if (value< -tol) {inside=false;break;}
            if (std::abs(value)<=tol) {
                if (boundary!=-1) {
                    error="section has ambiguous coplanar vertex contact";
                    return false;
                }
                boundary=k;
            }
        }
        if (!inside) continue;
        if (boundary<0) {left=right=true;continue;}
        const auto side=section_cross(a,b,p[(boundary+2)%3]);
        if (side>tol) left=true;
        else if (side< -tol) right=true;
        else {
            error="section has degenerate coplanar face contact";
            return false;
        }
    }
    return true;
}

} // namespace

bool vtk_section(const std::vector<gx3de_vec3>& world_vertices,
                 const std::vector<uint32_t>& triangles,
                 gx3de_vec3 origin,
                 gx3de_vec3 normal,
                 std::vector<Segment>& out,
                 std::string& error) {
    out.clear();
    error.clear();
    if (!finite(origin) || !finite(normal)) {
        error = "section plane contains a non-finite coordinate";
        return false;
    }
    const double length = std::hypot(normal.x, normal.y, normal.z);
    if (!(length > 0.0) || !std::isfinite(length)) {
        error = "section plane normal is degenerate";
        return false;
    }
    if (!validate_mesh(world_vertices,triangles,error)) return false;
    if (triangles.empty()) return true;

    try {
        const gx3de_vec3 unit_normal{normal.x/length, normal.y/length,
                                      normal.z/length};
        bool has_plane_vertex = false;
        for (size_t i=0; i<triangles.size(); ++i) {
            const double distance = plane_distance(world_vertices[triangles[i]],
                                                   origin, unit_normal);
            if (!std::isfinite(distance)) {
                error = "section plane distance is not finite";
                return false;
            }
            if (distance == 0.0) has_plane_vertex = true;
        }
        if (!has_plane_vertex) {
            // Preserve VTK's established path for strictly transverse cuts.
            // No triangle can be coplanar or touch the plane at a vertex here.
            vtkNew<vtkPolyData> mesh;
            fill_mesh(world_vertices, triangles, mesh);
            vtkNew<vtkPlane> plane;
            plane->SetOrigin(origin.x, origin.y, origin.z);
            plane->SetNormal(unit_normal.x, unit_normal.y, unit_normal.z);
            vtkNew<vtkCutter> cutter;
            cutter->SetInputData(mesh);
            cutter->SetCutFunction(plane);
            cutter->SetValue(0, 0.0);
            cutter->Update();
            vtkPolyData* cut = cutter->GetOutput();
            if (!cut || !cut->GetPoints() || !cut->GetLines()) return true;
            vtkCellArray* lines = cut->GetLines();
            vtkIdType size = 0;
            const vtkIdType* ids = nullptr;
            lines->InitTraversal();
            while (lines->GetNextCell(size, ids)) {
                for (vtkIdType i=1; i<size; ++i) {
                    if (ids[i-1] < 0 || ids[i] < 0 ||
                        ids[i-1] >= cut->GetNumberOfPoints() ||
                        ids[i] >= cut->GetNumberOfPoints()) {
                        error = "VTK section returned an invalid point index";
                        out.clear();
                        return false;
                    }
                    double a[3], b[3];
                    cut->GetPoint(ids[i-1], a);
                    cut->GetPoint(ids[i], b);
                    Segment edge = ordered_segment({a[0],a[1],a[2]},
                                                   {b[0],b[1],b[2]});
                    if (!finite(edge.a) || !finite(edge.b)) {
                        error = "VTK section returned a non-finite point";
                        out.clear();
                        return false;
                    }
                    if (!equal_point(edge.a, edge.b)) out.push_back(edge);
                }
            }
            std::sort(out.begin(), out.end(), less_segment);
            out.erase(std::unique(out.begin(), out.end(),
                                  [](const Segment& a, const Segment& b) {
                                      return equal_point(a.a,b.a) &&
                                             equal_point(a.b,b.b);
                                  }), out.end());
            return true;
        }

        // Build the arrangement of planar face edges, including T junctions
        // and overlap intersections. A whole-edge incidence count cannot
        // recover the geometric boundary of a partly overlapping patch.
        std::map<Segment, unsigned, SegmentLess> coplanar_edges;
        std::set<Segment, SegmentLess> crossing_edges;
        std::vector<std::array<gx3de_vec3,3>> coplanar_triangles;
        std::set<std::array<gx3de_vec3, 3>,
                 bool (*)(const std::array<gx3de_vec3, 3>&,
                          const std::array<gx3de_vec3, 3>&)> coplanar_faces(
            [](const auto& a, const auto& b) {
                return std::lexicographical_compare(a.begin(), a.end(),
                    b.begin(), b.end(), PointLess{});
            });
        for (size_t i = 0; i < triangles.size(); i += 3) {
            const gx3de_vec3 p[3] = {world_vertices[triangles[i]],
                                     world_vertices[triangles[i+1]],
                                     world_vertices[triangles[i+2]]};
            const double d[3] = {plane_distance(p[0], origin, unit_normal),
                                 plane_distance(p[1], origin, unit_normal),
                                 plane_distance(p[2], origin, unit_normal)};
            if (!std::isfinite(d[0]) || !std::isfinite(d[1]) ||
                !std::isfinite(d[2])) {
                error = "section plane distance is not finite";
                return false;
            }
            if (d[0] == 0.0 && d[1] == 0.0 && d[2] == 0.0) {
                std::array<gx3de_vec3, 3> face{p[0], p[1], p[2]};
                std::sort(face.begin(), face.end(), PointLess{});
                const gx3de_vec3 ab{p[1].x-p[0].x,p[1].y-p[0].y,p[1].z-p[0].z};
                const gx3de_vec3 ac{p[2].x-p[0].x,p[2].y-p[0].y,p[2].z-p[0].z};
                const double area2=std::hypot(ab.y*ac.z-ab.z*ac.y,
                                               ab.z*ac.x-ab.x*ac.z,
                                               ab.x*ac.y-ab.y*ac.x);
                if (equal_point(face[0], face[1]) ||
                    equal_point(face[1], face[2]) ||
                    !(area2 > 0.0) || !std::isfinite(area2) ||
                    !coplanar_faces.insert(face).second) {
                    error = "section has a degenerate or duplicate coplanar face";
                    return false;
                }
                coplanar_triangles.push_back({p[0],p[1],p[2]});
                for (int j=0; j<3; ++j) {
                    auto edge = ordered_segment(p[j], p[(j+1)%3]);
                    if (++coplanar_edges[edge] > 2) {
                        error = "section has a non-manifold coplanar edge";
                        return false;
                    }
                }
                continue;
            }
            std::vector<gx3de_vec3> intersections;
            for (int j=0; j<3; ++j) {
                const int k=(j+1)%3;
                if (d[j] == 0.0) intersections.push_back(p[j]);
                if ((d[j] < 0.0 && d[k] > 0.0) ||
                    (d[j] > 0.0 && d[k] < 0.0))
                    intersections.push_back(intersect_edge(p[j], p[k], d[j], d[k]));
            }
            if (intersections.size() == 2) {
                auto edge = ordered_segment(intersections[0], intersections[1]);
                if (!finite(edge.a) || !finite(edge.b)) {
                    error = "section intersection is not finite";
                    return false;
                }
                if (!equal_point(edge.a, edge.b)) crossing_edges.insert(edge);
            }
        }

        if (coplanar_triangles.empty()) {
            out.assign(crossing_edges.begin(),crossing_edges.end());
            return true;
        }
        const double ax=std::abs(unit_normal.x),ay=std::abs(unit_normal.y),
                     az=std::abs(unit_normal.z);
        const unsigned drop=ax>=ay && ax>=az ? 0 : ay>=az ? 1 : 2;
        std::vector<SectionEdge> arrangement;
        arrangement.reserve(coplanar_edges.size()+crossing_edges.size());
        for (const auto& edge:coplanar_edges)
            arrangement.push_back({edge.first.a,edge.first.b,{},true});
        for (const auto& edge:crossing_edges)
            arrangement.push_back({edge.a,edge.b,{},false});
        if (!section_split_edges(arrangement,drop,error)) return false;
        std::set<Segment,SegmentLess> boundary, transverse;
        for (const auto& edge:arrangement) {
            for (size_t j=1;j<edge.cuts.size();++j) {
                const auto atom=ordered_segment(edge.cuts[j-1].second,
                                                edge.cuts[j].second);
                if (equal_point(atom.a,atom.b)) continue;
                bool left=false,right=false;
                if (!section_edge_occupancy(atom,coplanar_triangles,drop,
                                            left,right,error)) return false;
                if (edge.coplanar) {
                    if (left != right) boundary.insert(atom);
                } else {
                    if (left && right) {
                        error="section has a non-manifold edge inside a coplanar face";
                        return false;
                    }
                    transverse.insert(atom);
                }
            }
        }
        std::map<gx3de_vec3,unsigned,PointLess> patch_degree;
        for (const auto& atom:boundary) {
            ++patch_degree[atom.a];
            ++patch_degree[atom.b];
        }
        for (const auto& item:patch_degree) {
            if (item.second != 2) {
                error="section has open, branched or ambiguous coplanar boundary";
                return false;
            }
        }
        boundary.insert(transverse.begin(),transverse.end());
        std::map<gx3de_vec3,unsigned,PointLess> degree;
        for (const auto& atom:boundary) {
            if (++degree[atom.a]>2 || ++degree[atom.b]>2) {
                error="section has branched or non-manifold coplanar topology";
                return false;
            }
        }
        out.assign(boundary.begin(),boundary.end());
        return true;
    } catch (const std::bad_alloc&) {
        error = "insufficient memory for VTK mesh section";
    } catch (const std::exception& ex) {
        error = std::string("VTK mesh section failed: ") + ex.what();
    }
    out.clear();
    return false;
}

bool vtk_point_surface_distance(const std::vector<gx3de_vec3>& world_vertices,
                                const std::vector<uint32_t>& triangles,
                                gx3de_vec3 point,
                                double& distance,
                                std::string& error,
                                gx3de_vec3* closest_world_point) {
    error.clear();
    if (!finite(point)) {
        error = "surface query point contains a non-finite coordinate";
        return false;
    }
    if (!validate_mesh(world_vertices,triangles,error)) return false;
    if (triangles.empty()) {
        error = "surface mesh has no triangles";
        return false;
    }
    for (size_t i = 0; i < triangles.size(); i += 3) {
        const auto a = world_vertices[triangles[i]];
        const auto b = world_vertices[triangles[i + 1]];
        const auto c = world_vertices[triangles[i + 2]];
        const double ux=b.x-a.x, uy=b.y-a.y, uz=b.z-a.z;
        const double vx=c.x-a.x, vy=c.y-a.y, vz=c.z-a.z;
        const double area2=std::hypot(uy*vz-uz*vy,
                                      uz*vx-ux*vz,
                                      ux*vy-uy*vx);
        if (!(area2 > 0.0) || !std::isfinite(area2)) {
            error = "surface mesh contains a degenerate triangle";
            return false;
        }
    }
    try {
        vtkNew<vtkPolyData> mesh;
        fill_mesh(world_vertices,triangles,mesh);
        vtkNew<vtkStaticCellLocator> locator;
        locator->SetDataSet(mesh);
        locator->BuildLocator();
        vtkNew<vtkGenericCell> cell;
        const double query[3] = {point.x,point.y,point.z};
        double closest[3] = {};
        vtkIdType cell_id = -1;
        int sub_id = -1;
        double squared_distance = std::numeric_limits<double>::quiet_NaN();
        locator->FindClosestPoint(query,closest,cell,cell_id,sub_id,squared_distance);
        if (cell_id < 0 || cell_id >= mesh->GetNumberOfCells() ||
            !std::isfinite(squared_distance) || squared_distance < 0.0 ||
            !std::isfinite(closest[0]) || !std::isfinite(closest[1]) ||
            !std::isfinite(closest[2])) {
            error = "VTK surface locator returned no finite closest point";
            return false;
        }
        distance = std::sqrt(squared_distance);
        if(closest_world_point)*closest_world_point={closest[0],closest[1],closest[2]};
        return true;
    } catch (const std::bad_alloc&) {
        error = "insufficient memory for VTK surface distance";
    } catch (const std::exception& ex) {
        error = std::string("VTK surface distance failed: ") + ex.what();
    }
    return false;
}

bool vtk_surface_query_batch(const std::vector<gx3de_vec3>& vertices,
                             const std::vector<uint32_t>& triangles,
                             const std::vector<gx3de_vec3>& queries,
                             std::vector<double>& distances,
                             std::vector<gx3de_vec3>& closest,
                             std::string& error) {
    error.clear();
    if(queries.empty()||queries.size()>4096||triangles.empty()||!validate_mesh(vertices,triangles,error)) {
        if(error.empty())error="Surface queries require a nonempty mesh and1..4096 points";
        return false;
    }
    for(auto point:queries)if(!finite(point)){error="Nonfinite surface query";return false;}
    for(size_t i=0;i<triangles.size();i+=3) {
        auto a=vertices[triangles[i]],b=vertices[triangles[i+1]],c=vertices[triangles[i+2]];
        double ux=b.x-a.x,uy=b.y-a.y,uz=b.z-a.z,vx=c.x-a.x,vy=c.y-a.y,vz=c.z-a.z;
        double area=std::hypot(uy*vz-uz*vy,uz*vx-ux*vz,ux*vy-uy*vx);
        if(!(area>0)||!std::isfinite(area)){error="Surface contains a degenerate triangle";return false;}
    }
    try {
        vtkNew<vtkPolyData> mesh;fill_mesh(vertices,triangles,mesh);
        vtkNew<vtkStaticCellLocator> locator;locator->SetDataSet(mesh);locator->BuildLocator();
        vtkNew<vtkGenericCell> cell;std::vector<double> output;std::vector<gx3de_vec3> witnesses;
        output.reserve(queries.size());witnesses.reserve(queries.size());
        for(auto point:queries) {
            const double query[3]={point.x,point.y,point.z};double projected[3]={};
            vtkIdType cell_id=-1;int sub_id=-1;double squared=std::numeric_limits<double>::quiet_NaN();
            locator->FindClosestPoint(query,projected,cell,cell_id,sub_id,squared);
            if(cell_id<0||cell_id>=mesh->GetNumberOfCells()||!std::isfinite(squared)||squared<0||
               !std::isfinite(projected[0])||!std::isfinite(projected[1])||!std::isfinite(projected[2])) {
                error="Surface locator returned no finite witness";return false;
            }
            output.push_back(std::sqrt(squared));witnesses.push_back({projected[0],projected[1],projected[2]});
        }
        distances=std::move(output);closest=std::move(witnesses);return true;
    } catch(const std::bad_alloc&) {error="Insufficient memory for scientific surface comparison";}
      catch(const std::exception& ex) {error=std::string("Surface comparison failed: ")+ex.what();}
    return false;
}

bool vtk_clip_mesh(const std::vector<gx3de_vec3>& world_vertices,
                   const std::vector<uint32_t>& triangles,
                   gx3de_vec3 origin,
                   gx3de_vec3 normal,
                   bool keep_positive,
                   MeshData& output,
                   std::string& error) {
    error.clear();
    if (!finite(origin) || !finite(normal)) {
        error = "clip plane contains a non-finite coordinate";
        return false;
    }
    const double normal_length = std::hypot(normal.x,normal.y,normal.z);
    if (!(normal_length > 0.0) || !std::isfinite(normal_length)) {
        error = "clip plane normal is degenerate";
        return false;
    }
    if (!validate_mesh(world_vertices,triangles,error)) return false;
    if (triangles.empty()) {
        output = {};
        return true;
    }
    try {
        vtkNew<vtkPolyData> mesh;
        fill_mesh(world_vertices,triangles,mesh);
        vtkNew<vtkPlane> plane;
        plane->SetOrigin(origin.x,origin.y,origin.z);
        plane->SetNormal(normal.x/normal_length,
                         normal.y/normal_length,
                         normal.z/normal_length);

        vtkNew<vtkClipPolyData> clip;
        clip->SetInputData(mesh);
        clip->SetClipFunction(plane);
        clip->SetValue(0.0);
        clip->GenerateClipScalarsOn();
        clip->SetInsideOut(keep_positive ? 0 : 1);

        vtkNew<vtkTriangleFilter> triangulate;
        triangulate->SetInputConnection(clip->GetOutputPort());
        triangulate->PassVertsOff();
        triangulate->PassLinesOff();
        triangulate->Update();
        vtkPolyData* clipped = triangulate->GetOutput();
        MeshData candidate;
        if (!clipped || !clipped->GetPolys() || !clipped->GetPoints()) {
            output = std::move(candidate);
            return true;
        }
        const vtkIdType point_count = clipped->GetNumberOfPoints();
        if (point_count < 0 ||
            static_cast<uint64_t>(point_count) > std::numeric_limits<uint32_t>::max()) {
            error = "clipped mesh exceeds 32-bit public index capacity";
            return false;
        }
        std::vector<uint32_t> remap(static_cast<size_t>(point_count),
                                    std::numeric_limits<uint32_t>::max());
        vtkCellArray* polys = clipped->GetPolys();
        vtkIdType size = 0;
        const vtkIdType* ids = nullptr;
        polys->InitTraversal();
        while (polys->GetNextCell(size,ids)) {
            if (size != 3) {
                error = "VTK clip triangulation returned a non-triangle face";
                return false;
            }
            gx3de_vec3 corners[3];
            for (int j=0;j<3;++j) {
                if (ids[j] < 0 || ids[j] >= point_count) {
                    error = "VTK clip returned an invalid point index";
                    return false;
                }
                double p[3];
                clipped->GetPoint(ids[j],p);
                corners[j] = {p[0],p[1],p[2]};
                if (!finite(corners[j])) {
                    error = "VTK clip returned a non-finite point";
                    return false;
                }
            }
            const auto a=corners[0],b=corners[1],c=corners[2];
            const double ux=b.x-a.x,uy=b.y-a.y,uz=b.z-a.z;
            const double vx=c.x-a.x,vy=c.y-a.y,vz=c.z-a.z;
            const double area2=std::hypot(uy*vz-uz*vy,
                                          uz*vx-ux*vz,
                                          ux*vy-uy*vx);
            if (!std::isfinite(area2)) {
                error = "VTK clip returned an unbounded triangle";
                return false;
            }
            if (!(area2 > 0.0)) continue;
            for (int j=0;j<3;++j) {
                const auto index=static_cast<size_t>(ids[j]);
                if (remap[index] == std::numeric_limits<uint32_t>::max()) {
                    remap[index]=static_cast<uint32_t>(candidate.vertices.size());
                    candidate.vertices.push_back(corners[j]);
                }
                candidate.triangles.push_back(remap[index]);
            }
        }
        output = std::move(candidate);
        return true;
    } catch (const std::bad_alloc&) {
        error = "insufficient memory for VTK mesh clip";
    } catch (const std::exception& ex) {
        error = std::string("VTK mesh clip failed: ") + ex.what();
    }
    return false;
}

} // namespace gx3de_backend
