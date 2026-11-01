// SPDX-License-Identifier: GPL-3.0-or-later
#ifndef GX3DE_PROJECTION_SNAPSHOT_V1_H
#define GX3DE_PROJECTION_SNAPSHOT_V1_H
#include <array>
#include <algorithm>
#include <cmath>
#include <stdexcept>
#include <string>
#include <cstdint>
#include <utility>
#include <limits>

// Evaluation of a bounded snapshot sampled through the existing public native
// projection API. No camera, FOV, renderer or scientific-figure formulas live
// here. The GUI never owns a native engine/view/viewport pointer.
namespace gx3de_projection_v1 {
struct Vec {
    double x=0,y=0,z=0;
    Vec operator+(Vec b)const{return {x+b.x,y+b.y,z+b.z};}
    Vec operator-(Vec b)const{return {x-b.x,y-b.y,z-b.z};}
    Vec operator*(double b)const{return {x*b,y*b,z*b};}
};
inline double dot(Vec a,Vec b){return a.x*b.x+a.y*b.y+a.z*b.z;}
inline Vec cross(Vec a,Vec b){return {a.y*b.z-a.z*b.y,a.z*b.x-a.x*b.z,a.x*b.y-a.y*b.x};}
inline double norm(Vec a){return std::hypot(a.x,a.y,a.z);}
inline bool finite(Vec a){return std::isfinite(a.x)&&std::isfinite(a.y)&&std::isfinite(a.z);}
struct Plane {Vec origin,u,v,normal;};
struct Snapshot {
    std::string frameId;
    uint64_t revision=0;
    uint32_t width=0,height=0;
    bool orthographic=false;
    Vec camera,origin1,dx1,dy1,origin2,dx2,dy2;
};
struct Point {bool valid=false;double x=0,y=0,depth=0;const char* reason="range";};
struct Scale {
    bool valid=false;
    const char* reason="range";
    double maximumPixelsPerUnit=0,minimumDepth=0;
    std::array<Point,4> polygon{};
    std::array<double,4> bounds{};
};
class Mapping {
    Snapshot snapshot_;
    Plane plane_;
    Vec inverse0_,inverse1_,inverse2_,third_;
public:
    Mapping(Snapshot snapshot,Plane plane):snapshot_(std::move(snapshot)),plane_(plane) {
        if(snapshot_.frameId.empty()||snapshot_.frameId.size()>256||snapshot_.frameId.find('\0')!=std::string::npos||!snapshot_.width||!snapshot_.height||snapshot_.width>16384||snapshot_.height>16384)
            throw std::runtime_error("Invalid projection frame identity or dimensions");
        if(std::any_of(snapshot_.frameId.begin(),snapshot_.frameId.end(),[](unsigned char c){return c<33||c>126;}))
            throw std::runtime_error("Native projection frame identities must be printable ASCII tokens");
        for(Vec v:{snapshot_.camera,snapshot_.origin1,snapshot_.dx1,snapshot_.dy1,snapshot_.origin2,snapshot_.dx2,snapshot_.dy2,plane.origin,plane.u,plane.v,plane.normal})
            if(!finite(v))throw std::runtime_error("Projection and plane vectors must be finite");
        if(std::abs(norm(plane.u)-1)>1e-8||std::abs(norm(plane.v)-1)>1e-8||std::abs(norm(plane.normal)-1)>1e-8||
           std::abs(dot(plane.u,plane.v))>1e-8||std::abs(dot(plane.u,plane.normal))>1e-8||std::abs(dot(plane.v,plane.normal))>1e-8||
           norm(cross(plane.u,plane.v)-plane.normal)>1e-8)
            throw std::runtime_error("Use the normalized oriented frame returned by the public plane authority");
        third_=snapshot_.orthographic?snapshot_.origin2-snapshot_.origin1:snapshot_.origin1-snapshot_.camera;
        const double scale=norm(snapshot_.dx1)*norm(snapshot_.dy1)*norm(third_);
        const double determinant=dot(snapshot_.dx1,cross(snapshot_.dy1,third_));
        if(!std::isfinite(scale)||scale<=0||!std::isfinite(determinant)||std::abs(determinant)<=scale*1e-12)
            throw std::runtime_error("Degenerate native projection basis");
        inverse0_=cross(snapshot_.dy1,third_)*(1/determinant);
        inverse1_=cross(third_,snapshot_.dx1)*(1/determinant);
        inverse2_=cross(snapshot_.dx1,snapshot_.dy1)*(1/determinant);
        const double factor=snapshot_.orthographic?1:2;
        const double tolerance=1e-8*std::max({1.0,norm(snapshot_.dx1),norm(snapshot_.dy1)});
        if(norm(snapshot_.dx2-snapshot_.dx1*factor)>tolerance||norm(snapshot_.dy2-snapshot_.dy1*factor)>tolerance)
            throw std::runtime_error("Inconsistent native depth samples");
    }
    const Snapshot& snapshot()const{return snapshot_;}
    const Plane& plane()const{return plane_;}
    Point project(double x,double y)const {
        const Vec world=plane_.origin+plane_.u*x+plane_.v*y;
        const Vec delta=world-(snapshot_.orthographic?snapshot_.origin1:snapshot_.camera);
        const double a=dot(inverse0_,delta),b=dot(inverse1_,delta),d=dot(inverse2_,delta);
        Point out;out.depth=snapshot_.orthographic?d+1:d;
        if(!std::isfinite(out.depth)||out.depth<=0){out.reason="behind_camera";return out;}
        out.x=snapshot_.orthographic?a:a/d;out.y=snapshot_.orthographic?b:b/d;
        if(!std::isfinite(out.x)||!std::isfinite(out.y))return out;
        out.valid=true;out.reason="";return out;
    }
    Point unproject(double x,double y)const {
        const Vec sampled=snapshot_.origin1+snapshot_.dx1*x+snapshot_.dy1*y;
        const Vec start=snapshot_.orthographic?sampled:snapshot_.camera;
        const Vec direction=snapshot_.orthographic?third_:sampled-snapshot_.camera;
        Point out;const double denominator=dot(direction,plane_.normal);
        if(!std::isfinite(denominator)||std::abs(denominator)<=1e-12*norm(direction)){out.reason="edge_on";return out;}
        const double t=dot(plane_.origin-start,plane_.normal)/denominator;
        out.depth=snapshot_.orthographic?t+1:t;
        if(!std::isfinite(out.depth)||out.depth<=0){out.reason="behind_camera";return out;}
        const Vec local=start+direction*t-plane_.origin;
        out.x=dot(local,plane_.u);out.y=dot(local,plane_.v);
        if(!std::isfinite(out.x)||!std::isfinite(out.y))return out;
        out.valid=true;out.reason="";return out;
    }
    Scale scale(std::array<double,4> rectangle)const {
        Scale out;
        const std::array<std::array<double,2>,4> corners{{{rectangle[0],rectangle[1]},{rectangle[2],rectangle[1]},{rectangle[2],rectangle[3]},{rectangle[0],rectangle[3]}}};
        const auto delta=plane_.origin-(snapshot_.orthographic?snapshot_.origin1:snapshot_.camera);
        const std::array<double,3> a{dot(inverse0_,plane_.u),dot(inverse0_,plane_.v),dot(inverse0_,delta)};
        const std::array<double,3> b{dot(inverse1_,plane_.u),dot(inverse1_,plane_.v),dot(inverse1_,delta)};
        const std::array<double,3> d=snapshot_.orthographic?std::array<double,3>{0,0,1}:std::array<double,3>{dot(inverse2_,plane_.u),dot(inverse2_,plane_.v),dot(inverse2_,delta)};
        std::array<double,4> numerators{};double minimum=0;
        for(size_t i=0;i<corners.size();++i){
            auto p=unproject(corners[i][0],corners[i][1]);out.polygon[i]=p;
            if(!p.valid){out.reason=p.reason;return out;}
            const double denominator=d[0]*p.x+d[1]*p.y+d[2];
            if(!std::isfinite(denominator)||denominator<=0){out.reason="horizon";return out;}
            const double nx=a[0]*p.x+a[1]*p.y+a[2],ny=b[0]*p.x+b[1]*p.y+b[2];
            const std::array<double,4> values{a[0]*denominator-nx*d[0],a[1]*denominator-nx*d[1],b[0]*denominator-ny*d[0],b[1]*denominator-ny*d[1]};
            if(!i){minimum=denominator;out.minimumDepth=p.depth;out.bounds={p.x,p.y,p.x,p.y};}
            else{minimum=std::min(minimum,denominator);out.minimumDepth=std::min(out.minimumDepth,p.depth);out.bounds[0]=std::min(out.bounds[0],p.x);out.bounds[1]=std::min(out.bounds[1],p.y);out.bounds[2]=std::max(out.bounds[2],p.x);out.bounds[3]=std::max(out.bounds[3],p.y);}
            for(size_t j=0;j<4;++j)numerators[j]=std::max(numerators[j],std::abs(values[j]));
        }
        // A projective Jacobian's four numerators are affine on the convex
        // visible quad; corner maxima and the minimum positive denominator
        // bound its Frobenius norm throughout that quad. This is not a claim
        // about the entire axis-aligned local bounding rectangle outside it.
        double squared=0;for(double value:numerators)squared+=value*value;
        out.maximumPixelsPerUnit=std::sqrt(squared)/(minimum*minimum)*(1+32*std::numeric_limits<double>::epsilon());
        if(!std::isfinite(out.maximumPixelsPerUnit)||out.maximumPixelsPerUnit<=0)return out;
        out.valid=true;out.reason="";return out;
    }
};
}
#endif
