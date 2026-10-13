// SPDX-License-Identifier: GPL-3.0-or-later
#include "profile_backend.hpp"
#include <algorithm>
#include <cmath>
#include <cstdint>
#include <limits>
#include <map>
#include <set>
#include <tuple>
#include <utility>

namespace gx3de_backend {
namespace {
using Cell=std::tuple<int64_t,int64_t,int64_t>;
struct Node {gx3de_vec3 point;std::vector<size_t> edges;};
struct Edge {size_t a,b;};
struct Point2 {long double x,y;};
static bool finite(gx3de_vec3 p){return std::isfinite(p.x)&&std::isfinite(p.y)&&std::isfinite(p.z);}
static double distance(gx3de_vec3 a,gx3de_vec3 b){return std::hypot(a.x-b.x,a.y-b.y,a.z-b.z);}
static gx3de_vec3 minus(gx3de_vec3 a,gx3de_vec3 b){return {a.x-b.x,a.y-b.y,a.z-b.z};}
static double dot(gx3de_vec3 a,gx3de_vec3 b){return a.x*b.x+a.y*b.y+a.z*b.z;}
static bool less_point(gx3de_vec3 a,gx3de_vec3 b){
    if(a.x!=b.x)return a.x<b.x;if(a.y!=b.y)return a.y<b.y;return a.z<b.z;
}
static long double cross2(Point2 a,Point2 b,Point2 c){
    return (b.x-a.x)*(c.y-a.y)-(b.y-a.y)*(c.x-a.x);
}
static bool on_open_segment(Point2 p,Point2 a,Point2 b,long double tolerance){
    const long double dx=b.x-a.x,dy=b.y-a.y,den=dx*dx+dy*dy;
    if(!(den>0))return false;
    const long double t=((p.x-a.x)*dx+(p.y-a.y)*dy)/den;
    if(!(t>0&&t<1))return false;
    return std::hypot(p.x-(a.x+t*dx),p.y-(a.y+t*dy))<=tolerance;
}
static bool ambiguous_pair(const Edge& a,const Edge& b,const std::vector<Point2>& points,
                           long double tolerance){
    Point2 p=points[a.a],q=points[a.b],r=points[b.a],s=points[b.b];
    if(std::max(std::min(p.x,q.x),std::min(r.x,s.x))>
       std::min(std::max(p.x,q.x),std::max(r.x,s.x))+tolerance ||
       std::max(std::min(p.y,q.y),std::min(r.y,s.y))>
       std::min(std::max(p.y,q.y),std::max(r.y,s.y))+tolerance)return false;
    const long double scale=std::max({std::hypot(q.x-p.x,q.y-p.y),
                                     std::hypot(s.x-r.x,s.y-r.y),1.0L});
    const long double epsilon=std::numeric_limits<long double>::epsilon()*64*scale*scale;
    auto sign=[&](long double value){return value>epsilon?1:(value< -epsilon?-1:0);};
    const int a1=sign(cross2(p,q,r)),a2=sign(cross2(p,q,s));
    const int b1=sign(cross2(r,s,p)),b2=sign(cross2(r,s,q));
    if(a1*a2<0&&b1*b2<0)return true;
    if(a.a!=b.a&&a.a!=b.b&&on_open_segment(p,r,s,tolerance))return true;
    if(a.b!=b.a&&a.b!=b.b&&on_open_segment(q,r,s,tolerance))return true;
    if(b.a!=a.a&&b.a!=a.b&&on_open_segment(r,p,q,tolerance))return true;
    if(b.b!=a.a&&b.b!=a.b&&on_open_segment(s,p,q,tolerance))return true;
    return false;
}
static bool cell_for(gx3de_vec3 p,gx3de_vec3 base,double tolerance,Cell& out){
    constexpr long double limit=static_cast<long double>(INT64_MAX)/4;
    long double xyz[]={ (static_cast<long double>(p.x)-base.x)/tolerance,
                        (static_cast<long double>(p.y)-base.y)/tolerance,
                        (static_cast<long double>(p.z)-base.z)/tolerance };
    for(auto value:xyz)if(!std::isfinite(value)||std::abs(value)>limit)return false;
    out={static_cast<int64_t>(std::floor(xyz[0])),static_cast<int64_t>(std::floor(xyz[1])),static_cast<int64_t>(std::floor(xyz[2]))};return true;
}
}
bool chain_section(const std::vector<gx3de_segment3>& segments,
                   gx3de_vec3 origin,gx3de_vec3 u,gx3de_vec3 v,
                   double tolerance,std::vector<ProfileContour>& contours,
                   std::string& error){
    error.clear();contours.clear();
    if(!std::isfinite(tolerance)||tolerance<=0||!finite(origin)||!finite(u)||!finite(v)){
        error="invalid profile tolerance or plane";return false;
    }
    if(segments.empty())return true;
    std::vector<Node> nodes;nodes.reserve(segments.size()*2);
    std::vector<Edge> edges;edges.reserve(segments.size());
    std::map<Cell,std::vector<size_t>> grid;
    std::set<std::pair<size_t,size_t>> unique_edges;
    gx3de_vec3 base=segments[0].a;
    auto find_node=[&](gx3de_vec3 p)->size_t {
        Cell key{};bool indexed=cell_for(p,base,tolerance,key);
        if(indexed){auto [x,y,z]=key;
            for(int dx=-1;dx<=1;++dx)for(int dy=-1;dy<=1;++dy)for(int dz=-1;dz<=1;++dz){
                auto it=grid.find({x+dx,y+dy,z+dz});if(it==grid.end())continue;
                for(size_t i:it->second)if(distance(p,nodes[i].point)<=tolerance)return i;
            }
        }else for(size_t i=0;i<nodes.size();++i)if(distance(p,nodes[i].point)<=tolerance)return i;
        size_t id=nodes.size();nodes.push_back({p,{}});if(indexed)grid[key].push_back(id);return id;
    };
    for(const auto& seg:segments)if(!finite(seg.a)||!finite(seg.b)){
        error="non-finite section segment";return false;
    }
    std::vector<gx3de_segment3> ordered=segments;
    for(auto& seg:ordered)if(less_point(seg.b,seg.a))std::swap(seg.a,seg.b);
    std::sort(ordered.begin(),ordered.end(),[](const auto& a,const auto& b){
        if(less_point(a.a,b.a))return true;if(less_point(b.a,a.a))return false;
        return less_point(a.b,b.b);
    });
    for(auto seg:ordered){
        if(distance(seg.a,seg.b)<=tolerance){error="section segment collapses at join tolerance";return false;}
        size_t a=find_node(seg.a),b=find_node(seg.b);
        if(a==b){error="section segment collapses after endpoint clustering";return false;}
        auto key=std::minmax(a,b);if(!unique_edges.insert(key).second)continue;
        size_t index=edges.size();edges.push_back({a,b});nodes[a].edges.push_back(index);nodes[b].edges.push_back(index);
    }
    for(const auto& node:nodes)if(node.edges.size()>2){error="branched section contour";return false;}
    std::vector<Point2> projected;projected.reserve(nodes.size());
    for(const auto& node:nodes){auto p=minus(node.point,origin);
        projected.push_back({dot(p,u),dot(p,v)});}
    std::vector<size_t> sweep(edges.size());
    for(size_t i=0;i<edges.size();++i)sweep[i]=i;
    auto min_x=[&](size_t i){return std::min(projected[edges[i].a].x,projected[edges[i].b].x);};
    auto max_x=[&](size_t i){return std::max(projected[edges[i].a].x,projected[edges[i].b].x);};
    std::sort(sweep.begin(),sweep.end(),[&](size_t a,size_t b){
        if(min_x(a)!=min_x(b))return min_x(a)<min_x(b);return a<b;
    });
    std::vector<size_t> active;
    for(size_t i:sweep){
        const auto x=min_x(i);
        active.erase(std::remove_if(active.begin(),active.end(),
                     [&](size_t j){return max_x(j)+tolerance<x;}),active.end());
        for(size_t j:active)if(ambiguous_pair(edges[i],edges[j],projected,tolerance)){
            error="crossing or overlapping section segments";return false;
        }
        active.push_back(i);
    }
    std::vector<uint8_t> used(edges.size(),0);
    auto walk=[&](size_t start)->ProfileContour {
        ProfileContour contour;size_t current=start;
        for(;;){
            contour.points.push_back(nodes[current].point);
            size_t next_edge=edges.size();for(size_t e:nodes[current].edges)if(!used[e]){next_edge=e;break;}
            if(next_edge==edges.size())break;
            used[next_edge]=1;size_t next=edges[next_edge].a==current?edges[next_edge].b:edges[next_edge].a;
            contour.length+=distance(nodes[current].point,nodes[next].point);
            if(next==start){contour.closed=true;break;}current=next;
        }
        if(contour.closed&&contour.points.size()>=3){
            double twice_area=0;
            for(size_t i=0;i<contour.points.size();++i){
                auto a=minus(contour.points[i],origin),b=minus(contour.points[(i+1)%contour.points.size()],origin);
                twice_area+=dot(a,u)*dot(b,v)-dot(b,u)*dot(a,v);
            }
            contour.area=std::abs(twice_area)*0.5;
            if(!std::isfinite(contour.area)){
                error="closed section contour has non-finite area";return {};
            }
            if(!(contour.area>0)){error="closed section contour has zero area";return {};}
        }
        return contour;
    };
    for(size_t i=0;i<nodes.size();++i)if(nodes[i].edges.size()==1&&!used[nodes[i].edges[0]]){
        contours.push_back(walk(i));if(!error.empty()){contours.clear();return false;}}
    for(size_t i=0;i<edges.size();++i)if(!used[i]){
        contours.push_back(walk(edges[i].a));if(!error.empty()){contours.clear();return false;}}
    return true;
}
}
