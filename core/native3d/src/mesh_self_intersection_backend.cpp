// SPDX-License-Identifier: GPL-3.0-or-later
#include "mesh_self_intersection_backend.hpp"

#include <algorithm>
#include <array>
#include <cmath>
#include <limits>
#include <new>
#include <numeric>
#include <stdexcept>
#include <utility>
#include <vector>

namespace gx3de_backend {
namespace {

struct Vec { long double x, y, z; };
Vec as_vec(const gx3de_vec3& p) { return {p.x, p.y, p.z}; }
Vec operator+(Vec a, Vec b) { return {a.x+b.x, a.y+b.y, a.z+b.z}; }
Vec operator-(Vec a, Vec b) { return {a.x-b.x, a.y-b.y, a.z-b.z}; }
Vec operator*(Vec a, long double s) { return {a.x*s, a.y*s, a.z*s}; }
long double dot(Vec a, Vec b) { return a.x*b.x+a.y*b.y+a.z*b.z; }
Vec cross(Vec a, Vec b) { return {a.y*b.z-a.z*b.y,a.z*b.x-a.x*b.z,a.x*b.y-a.y*b.x}; }
long double norm2(Vec a) { return dot(a,a); }
long double clamp01(long double x) { return std::max(0.0L,std::min(1.0L,x)); }

struct Triangle {
    std::array<uint32_t,3> ids;
    std::array<Vec,3> p;
    Vec normal;
    long double normal2;
    Vec low, high;
};

bool make_triangles(const MeshData& input, std::vector<Triangle>& out, std::string& error) {
    if (input.vertices.size() > UINT32_MAX || input.triangles.size() % 3 != 0) {
        error = "invalid triangle mesh dimensions";
        return false;
    }
    for (const auto& v : input.vertices) {
        if (!std::isfinite(v.x) || !std::isfinite(v.y) || !std::isfinite(v.z)) {
            error = "mesh contains a non-finite vertex";
            return false;
        }
    }
    out.reserve(input.triangles.size()/3);
    for (size_t i=0;i<input.triangles.size();i+=3) {
        Triangle t{};
        for (size_t j=0;j<3;++j) {
            t.ids[j]=input.triangles[i+j];
            if (t.ids[j]>=input.vertices.size()) {
                error = "triangle index is outside the vertex array";
                return false;
            }
            t.p[j]=as_vec(input.vertices[t.ids[j]]);
        }
        if (t.ids[0]==t.ids[1] || t.ids[1]==t.ids[2] || t.ids[2]==t.ids[0]) {
            error = "mesh contains a collapsed triangle";
            return false;
        }
        t.normal=cross(t.p[1]-t.p[0],t.p[2]-t.p[0]);
        t.normal2=norm2(t.normal);
        if (!(t.normal2>0) || !std::isfinite(t.normal2)) {
            error = "mesh contains a zero-area or out-of-range triangle";
            return false;
        }
        t.low=t.high=t.p[0];
        for (size_t j=1;j<3;++j) {
            t.low.x=std::min(t.low.x,t.p[j].x);t.low.y=std::min(t.low.y,t.p[j].y);t.low.z=std::min(t.low.z,t.p[j].z);
            t.high.x=std::max(t.high.x,t.p[j].x);t.high.y=std::max(t.high.y,t.p[j].y);t.high.z=std::max(t.high.z,t.p[j].z);
        }
        out.push_back(t);
    }
    return true;
}

bool adjacent(const Triangle& a,const Triangle& b) {
    for (uint32_t i:a.ids) for(uint32_t j:b.ids) if(i==j)return true;
    return false;
}

bool boxes_near(const Triangle& a,const Triangle& b,long double tolerance) {
    return a.low.x<=b.high.x+tolerance && b.low.x<=a.high.x+tolerance &&
           a.low.y<=b.high.y+tolerance && b.low.y<=a.high.y+tolerance &&
           a.low.z<=b.high.z+tolerance && b.low.z<=a.high.z+tolerance;
}

struct Vec2 {long double x,y;};
Vec2 projected(Vec v,int dropped) {
    if(dropped==0)return {v.y,v.z};
    if(dropped==1)return {v.x,v.z};
    return {v.x,v.y};
}
long double orient2(Vec2 a,Vec2 b,Vec2 c) {
    return (b.x-a.x)*(c.y-a.y)-(b.y-a.y)*(c.x-a.x);
}
bool on_segment2(Vec2 a,Vec2 b,Vec2 p) {
    return orient2(a,b,p)==0 && p.x>=std::min(a.x,b.x) && p.x<=std::max(a.x,b.x) &&
           p.y>=std::min(a.y,b.y) && p.y<=std::max(a.y,b.y);
}
bool segments_overlap2(Vec2 a,Vec2 b,Vec2 c,Vec2 d,long double* fraction) {
    long double ab_c=orient2(a,b,c),ab_d=orient2(a,b,d);
    long double cd_a=orient2(c,d,a),cd_b=orient2(c,d,b);
    if (((ab_c>0&&ab_d<0) || (ab_c<0&&ab_d>0)) &&
        ((cd_a>0&&cd_b<0) || (cd_a<0&&cd_b>0))) {
        *fraction=ab_c/(ab_c-ab_d); return true;
    }
    const long double dx=b.x-a.x,dy=b.y-a.y,len2=dx*dx+dy*dy;
    if(ab_c==0&&on_segment2(a,b,c)) {*fraction=((c.x-a.x)*dx+(c.y-a.y)*dy)/len2;return true;}
    if(ab_d==0&&on_segment2(a,b,d)) {*fraction=((d.x-a.x)*dx+(d.y-a.y)*dy)/len2;return true;}
    if(cd_a==0&&on_segment2(c,d,a)) {*fraction=0;return true;}
    if(cd_b==0&&on_segment2(c,d,b)) {*fraction=1;return true;}
    return false;
}
bool point_inside2(const std::array<Vec2,3>& t,Vec2 p) {
    long double a=orient2(t[0],t[1],p),b=orient2(t[1],t[2],p),c=orient2(t[2],t[0],p);
    return (a>=0&&b>=0&&c>=0)||(a<=0&&b<=0&&c<=0);
}
bool coplanar_overlap(const Triangle& a,const Triangle& b,Vec* witness) {
    Vec n=a.normal;
    int axis=(std::abs(n.x)>=std::abs(n.y)&&std::abs(n.x)>=std::abs(n.z))?0:
             (std::abs(n.y)>=std::abs(n.z)?1:2);
    std::array<Vec2,3> pa,pb;
    for(size_t i=0;i<3;++i){pa[i]=projected(a.p[i],axis);pb[i]=projected(b.p[i],axis);}
    for(size_t i=0;i<3;++i)if(point_inside2(pb,pa[i])){if(witness)*witness=a.p[i];return true;}
    for(size_t i=0;i<3;++i)if(point_inside2(pa,pb[i])){if(witness)*witness=b.p[i];return true;}
    for(size_t i=0;i<3;++i)for(size_t j=0;j<3;++j)
        {long double fraction=0;
         if(segments_overlap2(pa[i],pa[(i+1)%3],pb[j],pb[(j+1)%3],&fraction)) {
             if(witness)*witness=a.p[i]+(a.p[(i+1)%3]-a.p[i])*fraction;
             return true;
         }}
    return false;
}

bool point_inside_projected(const Triangle& t,Vec p) {
    long double signed_distance=dot(p-t.p[0],t.normal);
    Vec q=p-t.normal*(signed_distance/t.normal2);
    long double slack=64*std::numeric_limits<long double>::epsilon()*t.normal2;
    for(size_t i=0;i<3;++i)
        if(dot(cross(t.p[(i+1)%3]-t.p[i],q-t.p[i]),t.normal)<-slack)return false;
    return true;
}

bool edge_pierces_triangle(Vec start,Vec end,const Triangle& t,Vec* witness) {
    long double d0=dot(start-t.p[0],t.normal),d1=dot(end-t.p[0],t.normal);
    if ((d0>0&&d1>0)||(d0<0&&d1<0)||d0==d1)return false;
    long double ratio=d0/(d0-d1);
    if(ratio<0||ratio>1)return false;
    Vec point=start+(end-start)*ratio;
    if(!point_inside_projected(t,point))return false;
    if(witness)*witness=point;
    return true;
}

long double point_segment_distance2(Vec p,Vec a,Vec b,Vec* nearest=nullptr) {
    Vec direction=b-a;
    long double length2=norm2(direction);
    long double t=length2>0?clamp01(dot(p-a,direction)/length2):0;
    Vec q=a+direction*t;
    if(nearest)*nearest=q;
    return norm2(p-q);
}

long double point_triangle_distance2(Vec p,const Triangle& t,Vec* nearest=nullptr) {
    long double distance=dot(p-t.p[0],t.normal);
    if(point_inside_projected(t,p)){
        if(nearest)*nearest=p-t.normal*(distance/t.normal2);
        return distance*distance/t.normal2;
    }
    long double best=std::numeric_limits<long double>::infinity();
    for(size_t i=0;i<3;++i){
        Vec q{};long double d=point_segment_distance2(p,t.p[i],t.p[(i+1)%3],&q);
        if(d<best){best=d;if(nearest)*nearest=q;}
    }
    return best;
}

long double segment_segment_distance2(Vec a,Vec b,Vec c,Vec d,Vec* midpoint=nullptr) {
    Vec u=b-a,v=d-c,w=a-c;
    long double aa=norm2(u),bb=dot(u,v),cc=norm2(v),dd=dot(u,w),ee=dot(v,w);
    long double denominator=aa*cc-bb*bb;
    long double s=denominator>0?clamp01((bb*ee-cc*dd)/denominator):0;
    long double t=clamp01((bb*s+ee)/cc);
    if(t==0)s=clamp01(-dd/aa);
    else if(t==1)s=clamp01((bb-dd)/aa);
    Vec pa=a+u*s,pb=c+v*t;
    if(midpoint)*midpoint=(pa+pb)*0.5L;
    return norm2(pa-pb);
}

bool touching(const Triangle& a,const Triangle& b,long double tolerance2,Vec* witness) {
    bool coplanar=true;
    for(Vec p:b.p)if(dot(p-a.p[0],a.normal)!=0){coplanar=false;break;}
    if(coplanar&&coplanar_overlap(a,b,witness))return true;
    for(size_t i=0;i<3;++i) {
        if(edge_pierces_triangle(a.p[i],a.p[(i+1)%3],b,witness) ||
           edge_pierces_triangle(b.p[i],b.p[(i+1)%3],a,witness))return true;
    }
    for(Vec p:a.p){Vec q{};if(point_triangle_distance2(p,b,&q)<=tolerance2){if(witness)*witness=(p+q)*0.5L;return true;}}
    for(Vec p:b.p){Vec q{};if(point_triangle_distance2(p,a,&q)<=tolerance2){if(witness)*witness=(p+q)*0.5L;return true;}}
    for(size_t i=0;i<3;++i)for(size_t j=0;j<3;++j)
        {Vec q{};if(segment_segment_distance2(a.p[i],a.p[(i+1)%3],b.p[j],b.p[(j+1)%3],&q)<=tolerance2){if(witness)*witness=q;return true;}}
    return false;
}

} // namespace

bool mesh_self_intersections(const MeshData& input,double tolerance,
                             uint64_t& count,std::string& error) {
    std::vector<MeshIntersectionHit> ignored;
    return mesh_self_intersection_details(input,tolerance,0,ignored,count,error);
}

bool mesh_self_intersection_details(const MeshData& input,double tolerance,
                                    uint64_t capacity,
                                    std::vector<MeshIntersectionHit>& hits,
                                    uint64_t& count,std::string& error) {
    if(!std::isfinite(tolerance)||tolerance<0){error="self-intersection tolerance must be finite and non-negative";return false;}
    try {
        std::vector<Triangle> faces;
        if(!make_triangles(input,faces,error))return false;
        uint64_t result=0;
        std::vector<MeshIntersectionHit> captured;
        captured.reserve(static_cast<size_t>(std::min<uint64_t>(capacity,1024)));
        const long double tol=static_cast<long double>(tolerance),tol2=tol*tol;
        std::vector<size_t> order(faces.size());
        std::iota(order.begin(),order.end(),size_t{0});
        std::sort(order.begin(),order.end(),[&](size_t a,size_t b) {
            return faces[a].low.x<faces[b].low.x ||
                   (faces[a].low.x==faces[b].low.x && a<b);
        });
        for(size_t i=0;i<order.size();++i)for(size_t j=i+1;j<order.size();++j) {
            const Triangle& a=faces[order[i]],&b=faces[order[j]];
            if(b.low.x>a.high.x+tol)break;
            if(adjacent(a,b)||!boxes_near(a,b,tol))continue;
            Vec witness{};
            if(touching(a,b,tol2,capacity?&witness:nullptr)) {
                if(result==UINT64_MAX){error="intersection pair count overflow";return false;}
                ++result;
                if(captured.size()<capacity) {
                    const auto first=std::min(order[i],order[j]),second=std::max(order[i],order[j]);
                    gx3de_vec3 point{static_cast<double>(witness.x),static_cast<double>(witness.y),static_cast<double>(witness.z)};
                    if(!std::isfinite(point.x)||!std::isfinite(point.y)||!std::isfinite(point.z)) {
                        error="intersection witness is outside finite range";return false;
                    }
                    captured.push_back({first,second,point});
                }
            }
        }
        count=result;hits=std::move(captured);error.clear();return true;
    }catch(const std::bad_alloc&){error="self-intersection diagnosis exhausted memory";}
    catch(const std::length_error&){error="self-intersection diagnosis exceeded container capacity";}
    return false;
}

} // namespace gx3de_backend
