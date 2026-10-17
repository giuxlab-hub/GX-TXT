// SPDX-License-Identifier: GPL-3.0-or-later
// Natural cubic smoothing: fixed-band LDL and differentiated selected inverse.
// The Q/R objective is the existing Numeric smoothing_spline contract.
#include <octave/oct.h>
#include <algorithm>
#include <cmath>
#include <limits>
#include <vector>

namespace {
using Real=long double;
struct Dual {Real v=0,d=0;Dual()=default;Dual(Real value,Real derivative=0):v(value),d(derivative){}};
Dual operator+(Dual a,Dual b){return {a.v+b.v,a.d+b.d};}
Dual operator-(Dual a,Dual b){return {a.v-b.v,a.d-b.d};}
Dual operator-(Dual a){return {-a.v,-a.d};}
Dual operator*(Dual a,Dual b){return {a.v*b.v,a.d*b.v+a.v*b.d};}
Dual operator/(Dual a,Dual b){Real value=a.v/b.v;return {value,(a.d-value*b.d)/b.v};}
double finite_double(Real value){double v=static_cast<double>(value);if(!std::isfinite(v))error("GXTXT:Numeric:Smoothing: result is outside finite binary64 range");return v;}
Real bounded(Real value,Real low,Real high,const char* label){
  Real tolerance=1e-10L*std::max(Real(1),high);
  if(!std::isfinite(value)||value<low-tolerance||value>high+tolerance)error("GXTXT:Numeric:Smoothing: unstable %s trace",label);
  return std::min(high,std::max(low,value));
}
}

DEFUN_DLD(gxtxt_numeric_smoothing_native,args,,"Numeric-owned natural cubic smoother and exact trace diagnostics") {
  if(args.length()!=3||args(0).iscomplex()||args(1).iscomplex()||args(2).iscomplex())error("GXTXT:Numeric:Smoothing: real X, Y and lambda required");
  ColumnVector x=args(0).column_vector_value(),y=args(1).column_vector_value();
  if(args(2).numel()!=1)error("GXTXT:Numeric:Smoothing: lambda must be scalar");
  Real lambda=args(2).double_value();const octave_idx_type n=x.numel(),m=n-2;
  if(n<3||n>1000000||y.numel()!=n||!std::isfinite(lambda)||lambda<0)error("GXTXT:Numeric:Smoothing: 3..1000000 observations and finite nonnegative lambda required");
  std::vector<Real> h(n-1),qa(m),qb(m),qc(m),r0(m),r1(m),b0(m),b1(m),b2(m),rhs(m),coef(m);
  for(octave_idx_type i=0;i<n;++i){
    if(!std::isfinite(x(i))||!std::isfinite(y(i)))error("GXTXT:Numeric:Smoothing: finite observations required");
    if(i){h[i-1]=Real(x(i))-Real(x(i-1));if(h[i-1]<=0)error("GXTXT:Numeric:Smoothing: distinct increasing X required");}
  }
  for(octave_idx_type i=0;i<m;++i){
    qa[i]=1/h[i];qc[i]=1/h[i+1];qb[i]=-qa[i]-qc[i];
    r0[i]=(h[i]+h[i+1])/3;if(i+1<m)r1[i]=h[i+1]/6;
    b0[i]=qa[i]*qa[i]+qb[i]*qb[i]+qc[i]*qc[i];
    // Difference of adjacent slopes avoids cancellation of a large response offset.
    rhs[i]=(Real(y(i+2))-Real(y(i+1)))/h[i+1]-(Real(y(i+1))-Real(y(i)))/h[i];
  }
  for(octave_idx_type i=0;i<m;++i){
    if(i+1<m)b1[i]=qb[i]*qa[i+1]+qc[i]*qb[i+1];
    if(i+2<m)b2[i]=qc[i]*qa[i+2];
  }
  std::vector<Dual> diagonal(m),l1(m),l2(m),z0(m),z1(m),z2(m);
  for(octave_idx_type i=0;i<m;++i){
    if((i&4095)==0)OCTAVE_QUIT;
    Dual diagonal_value(r0[i]+lambda*b0[i],b0[i]);
    if(i>=2)l2[i]=Dual(lambda*b2[i-2],b2[i-2])/diagonal[i-2];
    if(i>=1){
      Dual off(r1[i-1]+lambda*b1[i-1],b1[i-1]);
      if(i>=2)off=off-l2[i]*diagonal[i-2]*l1[i-1];
      l1[i]=off/diagonal[i-1];diagonal_value=diagonal_value-l1[i]*l1[i]*diagonal[i-1];
    }
    if(i>=2)diagonal_value=diagonal_value-l2[i]*l2[i]*diagonal[i-2];
    if(!std::isfinite(diagonal_value.v)||diagonal_value.v<=0||!std::isfinite(diagonal_value.d))error("GXTXT:Numeric:Smoothing: banded factorization is numerically singular");
    diagonal[i]=diagonal_value;
    if(i>=1)rhs[i]-=l1[i].v*rhs[i-1];if(i>=2)rhs[i]-=l2[i].v*rhs[i-2];
  }
  for(octave_idx_type i=m;i-->0;){
    if((i&4095)==0)OCTAVE_QUIT;
    coef[i]=rhs[i]/diagonal[i].v;
    if(i+1<m)coef[i]-=l1[i+1].v*coef[i+1];if(i+2<m)coef[i]-=l2[i+2].v*coef[i+2];
    if(i+2<m)z2[i]=-l1[i+1]*z1[i+1]-l2[i+2]*z0[i+2];
    if(i+1<m){z1[i]=-l1[i+1]*z0[i+1];if(i+2<m)z1[i]=z1[i]-l2[i+2]*z1[i+1];}
    z0[i]=Dual(1)/diagonal[i];
    if(i+1<m)z0[i]=z0[i]-l1[i+1]*z1[i];if(i+2<m)z0[i]=z0[i]-l2[i+2]*z2[i];
  }
  Dual trace_b,trace_r;
  for(octave_idx_type i=0;i<m;++i){
    trace_b=trace_b+z0[i]*Dual(b0[i]);trace_r=trace_r+z0[i]*Dual(r0[i]);
    if(i+1<m){trace_b=trace_b+Dual(2*b1[i])*z1[i];trace_r=trace_r+Dual(2*r1[i])*z1[i];}
    if(i+2<m)trace_b=trace_b+Dual(2*b2[i])*z2[i];
  }
  Real edf=n,mean_df=0,variance_df=0;
  if(lambda>0){
    edf=bounded(2+trace_r.v,2,n,"EDF");
    mean_df=bounded(edf>Real(n)/2?lambda*trace_b.v:Real(n)-edf,0,n-2,"residual mean");
    if(edf>Real(n)/2)edf=Real(n)-mean_df;
    variance_df=bounded(-lambda*(lambda*trace_b.d),0,n-2,"residual variance");
  }
  ColumnVector smoothed(n),second(n);second(0)=0;second(n-1)=0;
  for(octave_idx_type i=0;i<m;++i)second(i+1)=finite_double(coef[i]);
  Real rss=0;
  for(octave_idx_type i=0;i<n;++i){
    Real qc_value=0;if(i<m)qc_value+=qa[i]*coef[i];if(i>=1&&i-1<m)qc_value+=qb[i-1]*coef[i-1];if(i>=2)qc_value+=qc[i-2]*coef[i-2];
    Real residual=lambda*qc_value;rss+=residual*residual;smoothed(i)=finite_double(Real(y(i))-residual);
  }
  octave_scalar_map out;
  out.assign("smoothed_y",smoothed);out.assign("second_derivatives",second);
  out.assign("n",double(n));out.assign("edf",finite_double(edf));out.assign("residual_mean_dof",finite_double(mean_df));
  out.assign("residual_variance_dof",finite_double(variance_df));out.assign("smoother_trace_squared",finite_double(Real(n)-2*mean_df+variance_df));
  out.assign("sse",finite_double(rss));out.assign("smoothing_lambda",double(lambda));
  bool available=lambda>0&&mean_df>0;out.assign("gcv_available",available);
  if(available)out.assign("gcv_score",finite_double((rss/mean_df)/mean_df*Real(n)));else out.assign("gcv_score",Matrix());
  out.assign("solver","native_banded_ldl_selected_inverse");out.assign("trace_method","analytic_differentiated_selected_inverse");
  out.assign("workspace_bytes_bound",480.0*double(n));out.assign("precision","long_double_internal_binary64_result");
  octave_value_list result;result(0)=out;return result;
}
