// SPDX-License-Identifier: GPL-3.0-or-later
// Numerical CORE: exact cubic stationary points with conservative BVH pruning.
#include <octave/oct.h>
#include <algorithm>
#include <array>
#include <cmath>
#include <limits>
#include <numeric>
#include <vector>

namespace {
using Real = long double;
struct Segment { std::array<Real,4> x,y; Real t0,t1; };
struct Box { Real lo[2],hi[2]; };
struct Node { Box box; size_t begin,end,left=0,right=0; };
Real value(const std::vector<Real>& a, Real t) {
  Real out=0;for (Real c:a) out=out*t+c;return out;
}
std::vector<Real> roots01(std::vector<Real> a) {
  while(a.size()>1 && a.front()==0) a.erase(a.begin());
  Real scale=0;for(Real c:a) scale=std::max(scale,std::abs(c));
  if(scale==0 || a.size()<2) return {};
  for(Real& c:a)c/=scale;
  if(a.size()==2) {Real r=-a[1]/a[0];return r>=0&&r<=1?std::vector<Real>{r}:std::vector<Real>{};}
  std::vector<Real> derivative;
  for(size_t i=0;i+1<a.size();++i)derivative.push_back(a[i]*(a.size()-1-i));
  auto critical=roots01(derivative);
  std::vector<Real> boundaries{0};
  boundaries.insert(boundaries.end(),critical.begin(),critical.end());boundaries.push_back(1);
  std::sort(boundaries.begin(),boundaries.end());
  boundaries.erase(std::unique(boundaries.begin(),boundaries.end()),boundaries.end());
  std::vector<Real> result;
  const Real tolerance=128*std::numeric_limits<Real>::epsilon()*a.size();
  // Repeated roots are stationary points of the polynomial itself. Including
  // a numerically indistinguishable critical point cannot omit a curve point.
  for(Real t:boundaries) if(std::abs(value(a,t))<=tolerance) result.push_back(t);
  for(size_t i=1;i<boundaries.size();++i) {
    Real lo=boundaries[i-1],hi=boundaries[i];
    Real flo=value(a,lo),fhi=value(a,hi);
    if(flo==0 || fhi==0 || std::signbit(flo)==std::signbit(fhi))continue;
    for(int k=0;k<80;++k) {
      Real mid=(lo+hi)/2,fmid=value(a,mid);
      if(mid==lo || mid==hi || fmid==0) {lo=hi=mid;break;}
      if(std::signbit(fmid)==std::signbit(flo)) {lo=mid;flo=fmid;}else hi=mid;
    }
    result.push_back((lo+hi)/2);
  }
  std::sort(result.begin(),result.end());
  result.erase(std::unique(result.begin(),result.end()),result.end());return result;
}
Box hull(const Segment& s) {
  Box box;
  for(int axis=0;axis<2;++axis) {
    const auto& c=axis?s.y:s.x;
    std::array<Real,4> b{c[3],c[3]+c[2]/3,c[3]+2*c[2]/3+c[1]/3,c[0]+c[1]+c[2]+c[3]};
    Real scale=0;for(Real v:c)scale+=std::abs(v);
    Real slack=64*std::numeric_limits<Real>::epsilon()*scale;
    box.lo[axis]=*std::min_element(b.begin(),b.end())-slack;
    box.hi[axis]=*std::max_element(b.begin(),b.end())+slack;
  }
  return box;
}
Real bound(const Box& b,Real x,Real y) {
  Real dx=std::max(Real(0),std::max(b.lo[0]-x,x-b.hi[0]));
  Real dy=std::max(Real(0),std::max(b.lo[1]-y,y-b.hi[1]));return dx*dx+dy*dy;
}
struct Index {
  std::vector<Box> boxes;
  std::vector<size_t> order;
  std::vector<Node> nodes;
  explicit Index(const std::vector<Segment>& segments) {
    for(const auto& s:segments)boxes.push_back(hull(s));
    order.resize(segments.size());std::iota(order.begin(),order.end(),0);
    nodes.reserve(segments.size()/2+1);build(0,order.size());
  }
  size_t build(size_t begin,size_t end) {
    Box b=boxes[order[begin]];
    for(size_t i=begin+1;i<end;++i)for(int a=0;a<2;++a) {
      b.lo[a]=std::min(b.lo[a],boxes[order[i]].lo[a]);b.hi[a]=std::max(b.hi[a],boxes[order[i]].hi[a]);
    }
    size_t id=nodes.size();nodes.push_back(Node{b,begin,end,0,0});
    if(end-begin>4) {
      int axis=b.hi[0]-b.lo[0]>=b.hi[1]-b.lo[1]?0:1;
      size_t middle=begin+(end-begin)/2;
      std::nth_element(order.begin()+begin,order.begin()+middle,order.begin()+end,[&](size_t i,size_t j){
        Real ci=boxes[i].lo[axis]/2+boxes[i].hi[axis]/2,cj=boxes[j].lo[axis]/2+boxes[j].hi[axis]/2;
        return ci==cj?i<j:ci<cj;
      });
      size_t left=build(begin,middle),right=build(middle,end);
      nodes[id].left=left;nodes[id].right=right;
    }
    return id;
  }
};
struct Closest { Real d=std::numeric_limits<Real>::infinity(),x=0,y=0,t=0; };
void solve(const Segment& s,Real x,Real y,Closest& best,size_t& solves) {
  ++solves;
  auto a=s.x,b=s.y;a[3]-=x;b[3]-=y;
  std::vector<Real> stationary(6,0);
  for(size_t i=0;i<4;++i)for(size_t j=0;j<3;++j)stationary[i+j]+=a[i]*(3-j)*a[j]+b[i]*(3-j)*b[j];
  auto candidates=roots01(stationary);candidates.push_back(0);candidates.push_back(1);
  for(Real u:candidates) {
    Real px=((s.x[0]*u+s.x[1])*u+s.x[2])*u+s.x[3];
    Real py=((s.y[0]*u+s.y[1])*u+s.y[2])*u+s.y[3];
    Real d=(px-x)*(px-x)+(py-y)*(py-y),t=s.t0+u*(s.t1-s.t0);
    if(d<best.d || (d==best.d && t<best.t))best=Closest{d,px,py,t};
  }
}
}

DEFUN_DLD(gxtxt_numeric_cubic_project_native,args, ,
          "Numerical CORE exact cubic BVH projection; called by curve_model_project.") {
  if(args.length()!=5)print_usage();
  Matrix cx=args(0).matrix_value(),cy=args(1).matrix_value();
  ColumnVector knots=args(2).column_vector_value(),x=args(3).column_vector_value(),y=args(4).column_vector_value();
  if(cx.columns()!=4 || cy.columns()!=4 || cx.rows()<1 || cy.rows()!=cx.rows() || knots.numel()!=cx.rows()+1 || x.numel()!=y.numel())error("GXTXT:Numeric: invalid cubic projection shape");
  std::vector<Segment> segments;segments.reserve(cx.rows());
  for(octave_idx_type i=0;i<cx.rows();++i) {
    Segment s;s.t0=knots(i);s.t1=knots(i+1);
    if(!std::isfinite(s.t0)||!std::isfinite(s.t1)||s.t1<=s.t0)error("GXTXT:Numeric: cubic knots must be finite and strictly increasing");
    for(int k=0;k<4;++k) {
      s.x[k]=cx(i,k);s.y[k]=cy(i,k);
      if(!std::isfinite(s.x[k])||!std::isfinite(s.y[k]))error("GXTXT:Numeric: cubic coefficients must be finite");
    }
    segments.push_back(s);
  }
  Index index(segments);Matrix result(x.numel(),4);size_t solves=0,visited=0;
  std::vector<size_t> stack;stack.reserve(64);
  for(octave_idx_type q=0;q<x.numel();++q) {
    OCTAVE_QUIT;
    if(!std::isfinite(x(q))||!std::isfinite(y(q)))error("GXTXT:Numeric: projection queries must be finite");
    Closest best;stack.clear();stack.push_back(0);
    while(!stack.empty()) {
      size_t id=stack.back();stack.pop_back();++visited;const auto& node=index.nodes[id];
      Real slack=64*std::numeric_limits<Real>::epsilon()*best.d;
      if(std::isfinite(best.d)&&bound(node.box,x(q),y(q))>best.d+slack)continue;
      if(node.end-node.begin<=4) {
        for(size_t j=node.begin;j<node.end;++j) {
          size_t s=index.order[j];
          if(bound(index.boxes[s],x(q),y(q))<=best.d+slack)solve(segments[s],x(q),y(q),best,solves);
        }
      } else {
        size_t near=node.left,far=node.right;
        if(bound(index.nodes[far].box,x(q),y(q))<bound(index.nodes[near].box,x(q),y(q)))std::swap(near,far);
        stack.push_back(far);stack.push_back(near);
      }
    }
    result(q,0)=double(best.x);result(q,1)=double(best.y);result(q,2)=double(best.t);result(q,3)=double(std::sqrt(best.d));
  }
  octave_scalar_map diagnostics;
  diagnostics.assign("segments",double(segments.size()));diagnostics.assign("queries",double(x.numel()));
  diagnostics.assign("stationary_solves",double(solves));diagnostics.assign("visited_nodes",double(visited));
  diagnostics.assign("index_nodes",double(index.nodes.size()));
  octave_value_list out;out(0)=result;out(1)=diagnostics;return out;
}
