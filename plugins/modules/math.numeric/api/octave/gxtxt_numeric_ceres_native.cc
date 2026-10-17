// SPDX-License-Identifier: GPL-3.0-or-later
// Internal NUMERIC_API_v1 backend. The public provider compiles the existing
// CORE expression grammar into bounded data-only programs; no source eval.
#include <octave/oct.h>
#include <octave/quit.h>
#include <octave/lo-specfun.h>
#include <ceres/ceres.h>
#include <ceres/dynamic_autodiff_cost_function.h>
#include <array>
#include <cmath>
#include <cstdlib>
#include <locale.h>
#include <memory>
#include <limits>
#include <string>
#include <vector>

namespace {
// Saved Numeric model JSON is binary64 data, not a generic integer Dataset
// interchange. Keep strings/syntax intact and replace number tokens by exact
// small indices before Octave's JSON structure parser sees them.
octave_scalar_map model_json_tokens(const octave_value& input) {
  constexpr size_t max_bytes=128ULL*1024*1024, max_numbers=16ULL*1024*1024;
  const octave_idx_type size=input.numel();
  if(size<1 || static_cast<size_t>(size)>max_bytes || input.ndims()!=2 ||
     (input.rows()!=1 && input.columns()!=1))
    error("GXTXT:Numeric:ModelState: saved JSON needs a byte vector of at most128 MiB");
  std::string text;
  if(input.is_string()) {
    if(input.rows()!=1) error("GXTXT:Numeric:ModelState: JSON text must be one character row");
    text=input.string_value();
  }
  else if(input.is_uint8_type()) {
    uint8NDArray bytes=input.uint8_array_value();text.resize(size);
    for(octave_idx_type i=0;i<size;++i) {
      if((i&65535)==0) OCTAVE_QUIT;
      text[i]=static_cast<char>(bytes(i).value());
    }
  } else error("GXTXT:Numeric:ModelState: saved JSON requires text or exact uint8 bytes");
  struct Locale {
    locale_t value;
    Locale():value(newlocale(LC_NUMERIC_MASK,"C",nullptr)) {
      if(!value) error("GXTXT:Numeric:ModelState: cannot create numeric C locale");
    }
    ~Locale() {if(value) freelocale(value);}
  } locale;
  std::string syntax;syntax.reserve(text.size());std::vector<double> numbers;
  numbers.reserve(std::min(text.size()/8,max_numbers));
  size_t i=0,objects=0,arrays=0;int depth=0;
  const auto digit=[](char c){return c>='0'&&c<='9';};
  while(i<text.size()) {
    if((i&4095)==0) OCTAVE_QUIT;
    const char c=text[i];const size_t start=i;
    if(c=='"') {
      ++i;bool closed=false;
      while(i<text.size()) {
        if((i&65535)==0) OCTAVE_QUIT;
        if(text[i]=='\\') {i+=2;continue;}
        if(text[i++]=='"') {closed=true;break;}
      }
      if(!closed || i>text.size()) error("GXTXT:Numeric:ModelState: unterminated JSON string");
      syntax.append(text,start,i-start);
    } else if(c=='-' || digit(c)) {
      if(c=='-') ++i;
      if(i>=text.size() || !digit(text[i])) error("GXTXT:Numeric:ModelState: malformed JSON number");
      if(text[i]=='0') {
        ++i;
        if(i<text.size() && digit(text[i])) error("GXTXT:Numeric:ModelState: leading zero in JSON number");
      } else while(i<text.size() && digit(text[i])) ++i;
      if(i<text.size() && text[i]=='.') {
        ++i;const size_t first=i;while(i<text.size() && digit(text[i])) ++i;
        if(i==first) error("GXTXT:Numeric:ModelState: missing decimal digits");
      }
      if(i<text.size() && (text[i]=='e'||text[i]=='E')) {
        ++i;if(i<text.size() && (text[i]=='+'||text[i]=='-')) ++i;
        const size_t first=i;while(i<text.size() && digit(text[i])) ++i;
        if(i==first) error("GXTXT:Numeric:ModelState: missing exponent digits");
      }
      if(i-start>512 || numbers.size()>=max_numbers)
        error("GXTXT:Numeric:ModelState: saved JSON numeric budget exceeded");
      std::string token=text.substr(start,i-start);char *end=nullptr;
      const double value=strtod_l(token.c_str(),&end,locale.value);
      if(end!=token.c_str()+token.size() || !std::isfinite(value))
        error("GXTXT:Numeric:ModelState: saved JSON number is outside binary64");
      numbers.push_back(value);syntax+=std::to_string(numbers.size());
    } else if(c=='t'||c=='f'||c=='n') {
      const char *word=c=='t'?"true":c=='f'?"false":"null";
      const size_t count=c=='f'?5:4;
      if(text.compare(i,count,word)!=0) error("GXTXT:Numeric:ModelState: invalid JSON literal");
      syntax.append(word,count);i+=count;
    } else if(c=='{'||c=='[') {
      if(c=='{') ++objects;else ++arrays;
      if(++depth>16 || objects>65536 || arrays>2ULL*1024*1024)
        error("GXTXT:Numeric:ModelState: saved JSON structure budget exceeded");
      syntax+=c;++i;
    } else if(c=='}'||c==']') {
      if(--depth<0) error("GXTXT:Numeric:ModelState: unmatched JSON close");
      syntax+=c;++i;
    } else if(c==','||c==':'||c==' '||c=='\t'||c=='\r'||c=='\n') {syntax+=c;++i;}
    else error("GXTXT:Numeric:ModelState: malformed saved JSON token");
    if(syntax.size()>max_bytes) error("GXTXT:Numeric:ModelState: indexed JSON exceeds128 MiB");
  }
  if(depth!=0) error("GXTXT:Numeric:ModelState: unterminated JSON container");
  RowVector values(numbers.size());
  for(size_t k=0;k<numbers.size();++k) {if((k&65535)==0) OCTAVE_QUIT;values(k)=numbers[k];}
  octave_scalar_map out;out.assign("syntax",syntax);out.assign("numbers",values);
  out.assign("input_bytes",static_cast<double>(text.size()));return out;
}

struct VoigtParts { double value, dx, dsigma, dgamma; };
VoigtParts voigt_parts(double x,double sigma,double gamma) {
  const double nan=std::numeric_limits<double>::quiet_NaN();
  if(!std::isfinite(x)||!std::isfinite(sigma)||!std::isfinite(gamma)||sigma<=0||gamma<0)
    return {nan,nan,nan,nan};
  const double sqrt_pi=std::sqrt(std::acos(-1.0));
  const double scale=std::sqrt(2.0)*sigma;
  const Complex z(x/scale,gamma/scale);
  if(!std::isfinite(z.real())||!std::isfinite(z.imag()))return {nan,nan,nan,nan};
  const Complex imaginary(0,1);
  const Complex w=octave::math::erfcx(-imaginary*z);
  Complex derivative, width_combination;
  if(std::abs(z)>32) {
    // Differentiate the asymptotic series directly. The recurrence w'=-2zw+
    // 2i/sqrt(pi) and w+zw' cancel leading terms in the far wings.
    const Complex inverse=1.0/z, inverse2=inverse*inverse;
    Complex term=inverse,sum_derivative=-inverse2,sum_width(0,0);
    for(int k=1;k<=12;++k) {
      term*=((2.0*k-1)/2.0)*inverse2;
      sum_derivative-=(2.0*k+1)*term*inverse;
      sum_width-=2.0*k*term;
    }
    derivative=imaginary*sum_derivative/sqrt_pi;
    width_combination=imaginary*sum_width/sqrt_pi;
    if(gamma==0) {
      // Retain the exact Gaussian contribution on the real axis.
      derivative.real(-2*z.real()*w.real());
      width_combination.real((1-2*z.real()*z.real())*w.real());
    }
  } else {
    derivative=-2.0*z*w+2.0*imaginary/sqrt_pi;
    width_combination=w+z*derivative;
  }
  const double normalization=std::sqrt(2.0)*sqrt_pi*sigma;
  return {w.real()/normalization,
          derivative.real()/normalization/scale,
          -width_combination.real()/normalization/sigma,
          -derivative.imag()/normalization/scale};
}
double voigt_value(double x,double sigma,double gamma) {return voigt_parts(x,sigma,gamma).value;}
template<int N> ceres::Jet<double,N> voigt_value(const ceres::Jet<double,N>& x,
    const ceres::Jet<double,N>& sigma,const ceres::Jet<double,N>& gamma) {
  const auto p=voigt_parts(x.a,sigma.a,gamma.a);
  ceres::Jet<double,N> result(p.value);
  result.v=p.dx*x.v+p.dsigma*sigma.v+p.dgamma*gamma.v;
  return result;
}
double scalar_part(double value) {return value;}
template<int N> double scalar_part(const ceres::Jet<double,N>& value) {return value.a;}
template<class T> T logistic_value(const T& value) {
  using std::exp;
  if(scalar_part(value)>=0)return T(1)/(T(1)+exp(-value));
  T e=exp(value);return e/(T(1)+e);
}
struct ShockleyParts {double value, voltage, saturation, thermal, resistance;};
ShockleyParts shockley_parts(double voltage,double saturation,double thermal,double resistance) {
  const double nan=std::numeric_limits<double>::quiet_NaN();
  if(!std::isfinite(voltage)||!std::isfinite(saturation)||!std::isfinite(thermal)||!std::isfinite(resistance)||
      saturation<=0||thermal<=0||resistance<0)return {nan,nan,nan,nan,nan};
  // u is the junction voltage divided by the effective thermal voltage.
  // Solve the monotone scalar identity u+z*expm1(u)=b. This is model evaluation,
  // not another fitting optimizer. Long-double intermediates cover ratios of
  // finite double parameters; expm1 retains the current near zero voltage.
  const long double is=saturation,vt=thermal,rs=resistance;
  const long double b=static_cast<long double>(voltage)/vt,z=rs*is/vt;
  long double u=b;
  if(rs>0&&b!=0) {
    long double low=std::min(b,0.L),high=std::max(b,0.L);
    if(b>0)high=std::min(b,std::log1p(b/z));
    else high=std::min(0.L,b+z);
    u=b>0?high:std::min(high,b/(1+z));
    bool converged=false;
    for(int iteration=0;iteration<4096;++iteration) {
      // In reverse saturation, expm1(u) rounds to -1 before its derivative
      // vanishes. Subtract b+z first so the derivative root remains accurate.
      const long double term=u<-.5L?z*std::exp(u):z*std::expm1(u);
      const long double rhs=u<-.5L?b+z:b,f=u+term-rhs;
      const long double scale=std::max(std::abs(rhs),std::max(std::abs(u),std::abs(term)));
      if(std::abs(f)<=8*std::numeric_limits<long double>::epsilon()*scale) {converged=true;break;}
      if(f>0)high=u;else low=u;
      long double next=u-f/(1+z*std::exp(u));
      if(next==u) {converged=true;break;}
      if(!(next>low&&next<high))next=low+(high-low)/2;
      if(next==u) {converged=true;break;}
      u=next;
    }
    if(!converged)return {nan,nan,nan,nan,nan};
  }
  const long double current=is*std::expm1(u),g=is*std::exp(u)/vt,d=1+rs*g;
  return {static_cast<double>(current),static_cast<double>(g/d),
    static_cast<double>(std::expm1(u)/d),static_cast<double>(-g*u/d),static_cast<double>(-g*current/d)};
}
double shockley_value(double voltage,double saturation,double thermal,double resistance) {
  return shockley_parts(voltage,saturation,thermal,resistance).value;
}
template<int N> ceres::Jet<double,N> shockley_value(const ceres::Jet<double,N>& voltage,
    const ceres::Jet<double,N>& saturation,const ceres::Jet<double,N>& thermal,const ceres::Jet<double,N>& resistance) {
  const auto p=shockley_parts(voltage.a,saturation.a,thermal.a,resistance.a);
  ceres::Jet<double,N> result(p.value);
  result.v=p.voltage*voltage.v+p.saturation*saturation.v+p.thermal*thermal.v+p.resistance*resistance.v;
  return result;
}
struct Instruction { int op; double value; };
struct ExprelParts {double value, derivative;};
ExprelParts exprel_parts(double argument) {
  if(!std::isfinite(argument)) {
    const double nan=std::numeric_limits<double>::quiet_NaN();return {nan,nan};
  }
  const long double z=argument;
  if(std::abs(z)<.01L) {
    // Sum f(z)=sum z^k/(k+1)! and f'(z) directly at the removable
    // singularity. No subtraction of near-equal exponentials or 0/0 AD.
    long double value=1,derivative=.5L,power=1,coefficient=.5L;
    for(int k=1;k<=16;++k) {
      power*=z;value+=coefficient*power;
      coefficient/=k+2;derivative+=(k+1)*coefficient*power;
    }
    return {static_cast<double>(value),static_cast<double>(derivative)};
  }
  const long double numerator=std::expm1(z);
  return {static_cast<double>(numerator/z),
          static_cast<double>((z*std::exp(z)-numerator)/z/z)};
}
double exprel_value(double value) {return exprel_parts(value).value;}
template<int N> ceres::Jet<double,N> exprel_value(const ceres::Jet<double,N>& value) {
  const auto parts=exprel_parts(value.a);ceres::Jet<double,N> result(parts.value);
  result.v=parts.derivative*value.v;return result;
}
// Infinitesimal branch selection is used only by predictor differentiation.
// Ordinary fit/predict/parameter-Jacobian evaluations keep side=0.
inline double first_direction(double) { return 0.0; }
template<class T,int N> double first_direction(const ceres::Jet<T,N>& v) { return scalar_part(v.v[0]); }
struct Model {
  std::vector<std::vector<Instruction>> programs;
  const double* predictors;
  octave_idx_type rows;
  int columns, parameters;
  bool positive_predictor_domain=false;
  std::vector<double> scales;
  std::vector<double> fixed_values;
  template<class T> T physical_parameter(int k, const T* q) const {
    // A fixed physical value must survive normalization bit for bit. Keeping
    // the zero displacement also retains its physical AD derivative; the
    // Ceres subset manifold alone decides which parameters may move.
    if(std::isfinite(fixed_values[k]))
      return T(fixed_values[k])+(q[k]-T(fixed_values[k]/scales[k]))*T(scales[k]);
    return q[k]*T(scales[k]);
  }
  template<class T> T evaluate(octave_idx_type row, int response, const T* q, const T* adjusted_x=nullptr, int side=0) const {
    using std::exp;using std::log;using std::sqrt;using std::sin;using std::cos;
    using std::tan;using std::sinh;using std::cosh;using std::tanh;using std::abs;
    using std::atan;using std::erf;using std::pow;
    std::array<T,128> stack;int n=0;
    for(const auto& instruction:programs[response]) {
      int op=instruction.op;double v=instruction.value;
      if(op==0) {stack[n++]=T(v);continue;}
      if(op==1) {
        T x=(adjusted_x&&v==0)?*adjusted_x:T(predictors[row+rows*static_cast<int>(v)]);
        if(positive_predictor_domain&&scalar_part(x)<=0)return T(std::numeric_limits<double>::quiet_NaN());
        stack[n++]=x;continue;
      }
      if(op==2) {int k=static_cast<int>(v);stack[n++]=physical_parameter(k,q);continue;}
      if(op==24) {
        T gamma=stack[--n],sigma=stack[--n];stack[n-1]=voigt_value(stack[n-1],sigma,gamma);
        if(!ceres::isfinite(stack[n-1]))return T(std::numeric_limits<double>::quiet_NaN());
        continue;
      }
      if(op==26) {
        T resistance=stack[--n],thermal=stack[--n],saturation=stack[--n];
        stack[n-1]=shockley_value(stack[n-1],saturation,thermal,resistance);
        if(!ceres::isfinite(stack[n-1]))return T(std::numeric_limits<double>::quiet_NaN());
        continue;
      }
      if((op>=3 && op<=7)||op==29) {
        T b=stack[--n],a=stack[n-1];
        switch(op) {case 3:stack[n-1]=a+b;break;case 4:stack[n-1]=a-b;break;
          case 5:stack[n-1]=a*b;break;case 6:stack[n-1]=a/b;break;case 7:stack[n-1]=pow(a,b);break;
          case 29:stack[n-1]=(scalar_part(a)<scalar_part(b)||(side&&scalar_part(a)==scalar_part(b)&&side*first_direction(a)<side*first_direction(b)))?a:b;break;}
        if(!ceres::isfinite(stack[n-1])) return T(std::numeric_limits<double>::quiet_NaN());
        continue;
      }
      T a=stack[n-1];
      switch(op) {
        case 8:stack[n-1]=-a;break;case 9:break;
        case 10:stack[n-1]=exp(a);break;case 11:stack[n-1]=log(a);break;
        case 12:stack[n-1]=sqrt(a);break;case 13:stack[n-1]=sin(a);break;
        case 14:stack[n-1]=cos(a);break;case 15:stack[n-1]=tan(a);break;
        case 16:stack[n-1]=sinh(a);break;case 17:stack[n-1]=cosh(a);break;
        case 18:stack[n-1]=tanh(a);break;case 19:stack[n-1]=(side&&scalar_part(a)==0)?(side*first_direction(a)>=0?a:-a):abs(a);break;
        case 20:stack[n-1]=atan(a);break;case 21:stack[n-1]=erf(a);break;
        case 22:stack[n-1]=log(a)/T(std::log(10.0));break;
        // Constant powers zero/one have exact derivatives at x=0. The generic
        // Jet power rule would form 0*pow(0,-1) for the constant basis term.
        case 23:stack[n-1]=(v==0?T(1):(v==1?a:pow(a,v)));break;
        case 25:stack[n-1]=logistic_value(a);break;
        case 27:stack[n-1]=(scalar_part(a)>0||(scalar_part(a)==0&&(!side||side*first_direction(a)>=0)))?a:T(0);break;
        case 28:stack[n-1]=exprel_value(a);break;
      }
      if(!ceres::isfinite(stack[n-1])) return T(std::numeric_limits<double>::quiet_NaN());
    }
    return stack[0];
  }
};
struct ResidualBlock {
  const Model& model;const double* observed;const double* square_root_weights;
  octave_idx_type start;int count;
  template<class T> bool operator()(T const* const* parameters,T* residuals) const {
    for(int i=0;i<count;++i) {
      octave_idx_type index=start+i;auto row=index%model.rows;int response=index/model.rows;
      residuals[i]=(model.evaluate(row,response,parameters[0])-T(observed[index]))*T(square_root_weights[index]);
      if(!ceres::isfinite(residuals[i])) return false;
    }
    return true;
  }
};
struct Interrupt : ceres::IterationCallback {
  ceres::CallbackReturnType operator()(const ceres::IterationSummary&) override {
    OCTAVE_QUIT;return ceres::SOLVER_CONTINUE;
  }
};
struct OdrResidualBlock {
  const Model& model;const double* observed;const double* sigma;octave_idx_type row;
  template<class T> bool operator()(T const* const* parameters,T* residuals) const {
    // The latent parameter is an X correction divided by its own sigma.
    T x=T(model.predictors[row])+T(sigma[row])*parameters[1][0];
    residuals[0]=parameters[1][0];
    residuals[1]=(model.evaluate(row,0,parameters[0],&x)-T(observed[row]))/T(sigma[row+model.rows]);
    return ceres::isfinite(residuals[0])&&ceres::isfinite(residuals[1]);
  }
};
double number(const octave_scalar_map& opts,const std::string& name,double fallback) {
  if(!opts.contains(name)) return fallback;
  auto value=opts.getfield(name);
  if(!value.is_real_scalar()) error("GXTXT:Numeric:Ceres: %s requires a real scalar",name.c_str());
  double result=value.double_value();
  if(!std::isfinite(result)) error("GXTXT:Numeric:Ceres: %s must be finite",name.c_str());
  return result;
}
int integer(const octave_scalar_map& opts,const std::string& name,int fallback,int lo,int hi) {
  double value=number(opts,name,fallback);
  if(value!=std::floor(value)||value<lo||value>hi) error("GXTXT:Numeric:Ceres: invalid %s",name.c_str());
  return static_cast<int>(value);
}
std::string text(const octave_scalar_map& opts,const std::string& key,const std::string& fallback) {
  return opts.contains(key)?opts.getfield(key).string_value():fallback;
}
ColumnVector parameter_vector(const octave_scalar_map& opts,const std::string& key,int size,double fallback) {
  ColumnVector out(size,fallback);
  if(opts.contains(key)) {
    out=opts.getfield(key).column_vector_value();
    if(out.numel()!=size) error("GXTXT:Numeric:Ceres: %s parameter count mismatch",key.c_str());
  }
  return out;
}
}

DEFUN_DLD(gxtxt_numeric_ceres_native,args,nargout,
          "Internal compiled backend; invoke NUMERIC_API_v1, not this adapter.") {
  if(args.length()<1) print_usage();
  std::string action=args(0).string_value();
  if(action=="model_json_tokens") {
    if(args.length()!=2) print_usage();
    return ovl(model_json_tokens(args(1)));
  }
  if(args.length()!=7) print_usage();
  if(action!="fit" && action!="evaluate" && action!="predict" && action!="fit_odr" && action!="differentiate") error("GXTXT:Numeric:Ceres: unsupported action");
  const bool odr=action=="fit_odr",fitting=action=="fit"||odr;
  const bool predictor_derivative=action=="differentiate";
  const bool prediction_only=action=="predict"||predictor_derivative;
  Cell programs=args(1).cell_value();
  if(programs.numel()<1||programs.numel()>32) error("GXTXT:Numeric:Ceres: need 1..32 model responses");
  // Octave Matrix retains its immutable reference-counted array when already
  // double. No fortran_vec() on input, which would request a mutable copy.
  for(int i=2;i<=4;++i) if(!args(i).is_double_type()||!args(i).isreal()||args(i).ndims()!=2)
    error("GXTXT:Numeric:Ceres: provider must explicitly prepare real double inputs");
  const Matrix X=args(2).matrix_value(),Y=args(3).matrix_value(),W=args(4).matrix_value();
  ColumnVector initial=args(5).column_vector_value();octave_scalar_map opts=args(6).scalar_map_value();
  if(initial.numel()<1||initial.numel()>128) error("GXTXT:Numeric:Ceres: need 1..128 parameters");
  int p=initial.numel();octave_idx_type n=X.rows(),m=programs.numel();
  if(n<1||X.columns()<1||X.columns()>32||(!prediction_only&&(Y.rows()!=n||Y.columns()!=m||(!odr&&W.dims()!=Y.dims())))||(prediction_only&&(Y.numel()||W.numel())))
    error("GXTXT:Numeric:Ceres: incompatible observation/model dimensions");
  if(odr&&(X.columns()!=1||m!=1||W.rows()!=n||W.columns()!=2||n>200000))
    error("GXTXT:Numeric:Ceres: explicit ODR requires one predictor/response, two sigma columns and at most 200000 rows");
  if(n>67108864/X.columns()) error("GXTXT:Numeric:Ceres: predictors exceed the 512 MiB per-buffer budget");
  if(n>67108864/m) error("GXTXT:Numeric:Ceres: prediction exceeds the 512 MiB per-buffer budget");
  octave_idx_type total=n*m;
  if(!prediction_only && static_cast<double>(total)*p*8>512.*1024*1024)
    error("GXTXT:Numeric:Ceres: requested Jacobian exceeds the 512 MiB per-buffer budget");
  for(octave_idx_type i=0;i<X.numel();++i) if(!std::isfinite(X.data()[i])) error("GXTXT:Numeric:Ceres: nonfinite predictor");
  for(octave_idx_type i=0;i<Y.numel();++i) if(!std::isfinite(Y.data()[i])) error("GXTXT:Numeric:Ceres: invalid observation");
  for(octave_idx_type i=0;i<W.numel();++i) if(!std::isfinite(W.data()[i])||(odr?W.data()[i]<=0:W.data()[i]<0))
    error("GXTXT:Numeric:Ceres: invalid square-root weight or positive ODR sigma");
  Model model;model.predictors=X.data();model.rows=n;model.columns=X.columns();model.parameters=p;
  model.positive_predictor_domain=integer(opts,"positive_predictor_domain",0,0,1);
  if(model.positive_predictor_domain)
    for(octave_idx_type i=0;i<X.numel();++i) if(X.data()[i]<=0) error("GXTXT:Numeric:Ceres: model predictor domain requires positive values");
  auto scales=parameter_vector(opts,"parameter_scales",p,1.0);
  auto lower=parameter_vector(opts,"lower_bounds",p,-std::numeric_limits<double>::infinity());
  auto upper=parameter_vector(opts,"upper_bounds",p,std::numeric_limits<double>::infinity());
  std::vector<double> q(p);std::vector<int> fixed;
  auto fixed_mask=parameter_vector(opts,"fixed_mask",p,0);
  for(int k=0;k<p;++k) {
    if(!std::isfinite(initial(k))||!std::isfinite(scales(k))||scales(k)<=0||std::isnan(lower(k))||std::isnan(upper(k))||lower(k)>upper(k)||initial(k)<lower(k)||initial(k)>upper(k))
      error("GXTXT:Numeric:Ceres: invalid initial value, scale or bounds");
    if(fixed_mask(k)!=0&&fixed_mask(k)!=1) error("GXTXT:Numeric:Ceres: fixed mask must be boolean");
    if(fixed_mask(k)||lower(k)==upper(k)) fixed.push_back(k);
    model.fixed_values.push_back((fixed_mask(k)||lower(k)==upper(k))?initial(k):std::numeric_limits<double>::quiet_NaN());
    model.scales.push_back(scales(k));q[k]=initial(k)/scales(k);
    if(!std::isfinite(q[k])||(std::isfinite(lower(k))&&!std::isfinite(lower(k)/scales(k)))||(std::isfinite(upper(k))&&!std::isfinite(upper(k)/scales(k))))
      error("GXTXT:Numeric:Ceres: parameter scale overflows a value or bound");
  }
  for(octave_idx_type response=0;response<m;++response) {
    Matrix program=programs(response).matrix_value();
    if(program.columns()!=2||program.rows()<1||program.rows()>4096) error("GXTXT:Numeric:Ceres: invalid compiled program");
    int depth=0;std::vector<Instruction> instructions;
    for(octave_idx_type k=0;k<program.rows();++k) {
      double raw=program(k,0),value=program(k,1);
      if(!std::isfinite(raw)||raw!=std::floor(raw)||raw<0||raw>29||!std::isfinite(value)) error("GXTXT:Numeric:Ceres: invalid instruction");
      int op=static_cast<int>(raw);
      if(op<=2) {
        if(op && (value!=std::floor(value)||value<0||value>=(op==1?model.columns:p))) error("GXTXT:Numeric:Ceres: operand index out of range");
        if(++depth>128) error("GXTXT:Numeric:Ceres: expression nesting exceeds 128");
      } else if(op<=7||op==29) {if(depth<2) error("GXTXT:Numeric:Ceres: binary operand missing");--depth;}
      else if(op==24) {if(depth<3) error("GXTXT:Numeric:Ceres: Voigt needs three operands");depth-=2;}
      else if(op==26) {if(depth<4) error("GXTXT:Numeric:Ceres: Shockley needs four operands");depth-=3;}
      else if(depth<1) error("GXTXT:Numeric:Ceres: unary operand missing");
      instructions.push_back({op,value});
    }
    if(depth!=1) error("GXTXT:Numeric:Ceres: expression must produce exactly one value");
    model.programs.push_back(std::move(instructions));
  }
  if(predictor_derivative) {
    if(X.columns()!=1||total>22369621) error("GXTXT:Numeric:Ceres: predictor derivative requires one predictor and at most512MiB output");
    Matrix predicted(n,m),derivative(n,m),valid(n,m);
    std::vector<ceres::Jet<double,1>> parameters(p);
    for(int k=0;k<p;++k) parameters[k]=ceres::Jet<double,1>(q[k]);
    for(octave_idx_type response=0;response<m;++response) {
      for(octave_idx_type row=0;row<n;++row) {
        if((row&1023)==0) OCTAVE_QUIT;
        const double value=model.evaluate(row,response,q.data());
        if(!std::isfinite(value)) error("GXTXT:Numeric:Ceres: nonfinite prediction");
        ceres::Jet<double,1> x(X(row,0));x.v[0]=1.0;
        auto left=model.evaluate(row,response,parameters.data(),&x,-1);
        auto right=model.evaluate(row,response,parameters.data(),&x,1);
        const double dl=left.v[0],dr=right.v[0];
        const double tolerance=64*std::numeric_limits<double>::epsilon()*std::max(std::abs(dl),std::abs(dr));
        const bool available=std::isfinite(left.a)&&std::isfinite(right.a)&&std::isfinite(dl)&&std::isfinite(dr)&&std::abs(dl-dr)<=tolerance;
        predicted(row,response)=value;valid(row,response)=available?1:0;
        derivative(row,response)=available?dl:std::numeric_limits<double>::quiet_NaN();
      }
    }
    octave_scalar_map result;result.assign("predicted",predicted);result.assign("parameters",initial);
    result.assign("predictor_derivative",derivative);result.assign("derivative_valid",valid);
    result.assign("backend","numeric_ceres_expression_vm");result.assign("backend_version",CERES_VERSION_STRING);
    result.assign("evaluation_only",true);result.assign("derivative_method","two_sided_automatic_differentiation");
    result.assign("adapter_dataset_copy_bytes",0.0);result.assign("adapter_dataset_view_bytes",static_cast<double>(X.numel())*sizeof(double));
    result.assign("prediction_bytes",static_cast<double>(total)*sizeof(double));result.assign("derivative_bytes",static_cast<double>(total)*2*sizeof(double));
    return ovl(result);
  }
  if(prediction_only) {
    // Reuse the validated expression VM directly. Prediction owns one output
    // matrix; it allocates no observation, weight, residual or Jacobian arrays.
    Matrix predicted(n,m);
    for(octave_idx_type response=0;response<m;++response) {
      for(octave_idx_type row=0;row<n;++row) {
        if((row&1023)==0) OCTAVE_QUIT;
        double value=model.evaluate(row,response,q.data());
        if(!std::isfinite(value)) error("GXTXT:Numeric:Ceres: nonfinite prediction");
        predicted(row,response)=value;
      }
    }
    octave_scalar_map result;
    result.assign("predicted",predicted);result.assign("parameters",initial);
    result.assign("backend","numeric_ceres_expression_vm");result.assign("backend_version",CERES_VERSION_STRING);
    result.assign("evaluation_only",true);result.assign("derivative_method","not_requested");
    result.assign("adapter_dataset_copy_bytes",0.0);result.assign("adapter_dataset_view_bytes",static_cast<double>(X.numel())*sizeof(double));
    result.assign("prediction_bytes",static_cast<double>(total)*sizeof(double));result.assign("jacobian_bytes",0.0);
    return ovl(result);
  }
  ceres::Problem problem;problem.AddParameterBlock(q.data(),p);
  for(int k=0;k<p;++k) {
    if(lower(k)<upper(k)) {
      if(std::isfinite(lower(k))) problem.SetParameterLowerBound(q.data(),k,lower(k)/scales(k));
      if(std::isfinite(upper(k))) problem.SetParameterUpperBound(q.data(),k,upper(k)/scales(k));
    }
  }
  if(static_cast<int>(fixed.size())==p) problem.SetParameterBlockConstant(q.data());
  else if(!fixed.empty()) problem.SetManifold(q.data(),new ceres::SubsetManifold(p,fixed));
  std::string loss=text(opts,"loss","linear");double loss_scale=number(opts,"loss_scale",1.0);
  if(odr&&loss!="linear") error("GXTXT:Numeric:Ceres: ODR currently requires a quadratic normalized XY objective");
  if(loss_scale<=0) error("GXTXT:Numeric:Ceres: loss scale must be positive");
  ceres::LossFunction* loss_function=nullptr;
  if(loss=="huber") loss_function=new ceres::HuberLoss(loss_scale);
  else if(loss=="cauchy") loss_function=new ceres::CauchyLoss(loss_scale);
  else if(loss=="soft_l1") loss_function=new ceres::SoftLOneLoss(loss_scale);
  else if(loss=="arctan") loss_function=new ceres::ArctanLoss(loss_scale);
  else if(loss=="tukey") loss_function=new ceres::TukeyLoss(loss_scale);
  else if(loss!="linear") error("GXTXT:Numeric:Ceres: unknown loss");
  // Robust loss applies separately to each whitened residual component.
  // Ordinary least squares uses bounded batches, avoiding per-row objects.
  int batch=loss_function?1:256;
  using Cost=ceres::DynamicAutoDiffCostFunction<ResidualBlock,4>;
  std::vector<Cost*> blocks;
  using OdrCost=ceres::DynamicAutoDiffCostFunction<OdrResidualBlock,4>;
  std::vector<OdrCost*> odr_blocks;std::vector<double> latent(odr?n:0,0.0);
  for(octave_idx_type start=0;!odr&&start<total;start+=batch) {
    auto* cost=new Cost(new ResidualBlock{model,Y.data(),W.data(),start,static_cast<int>(std::min<octave_idx_type>(batch,total-start))});
    cost->AddParameterBlock(p);cost->SetNumResiduals(std::min<octave_idx_type>(batch,total-start));
    problem.AddResidualBlock(cost,loss_function,q.data());blocks.push_back(cost);
  }
  if(odr) for(octave_idx_type row=0;row<n;++row) {
    if((row&1023)==0) OCTAVE_QUIT;
    auto* cost=new OdrCost(new OdrResidualBlock{model,Y.data(),W.data(),row});
    cost->AddParameterBlock(p);cost->AddParameterBlock(1);cost->SetNumResiduals(2);
    problem.AddResidualBlock(cost,nullptr,q.data(),&latent[row]);odr_blocks.push_back(cost);
  }
  ceres::Solver::Options options;
  options.linear_solver_type=ceres::DENSE_QR;options.minimizer_progress_to_stdout=false;options.logging_type=ceres::SILENT;
  // Small ODR systems retain QR's conditioning. Large systems eliminate the
  // independent per-row latent blocks, keeping the reduced matrix P by P.
  if(odr&&n>2048) {
    options.linear_solver_type=ceres::DENSE_SCHUR;
    options.linear_solver_ordering=std::make_shared<ceres::ParameterBlockOrdering>();
    for(octave_idx_type row=0;row<n;++row) options.linear_solver_ordering->AddElementToGroup(&latent[row],0);
    options.linear_solver_ordering->AddElementToGroup(q.data(),1);
  }
  options.max_num_iterations=integer(opts,"max_iterations",400,1,100000);
  int budget=1;const char* env=std::getenv("GXTXT_JOB_INTERNAL_THREADS");if(env) budget=std::max(1,std::atoi(env));
  options.num_threads=integer(opts,"threads",budget,1,budget);
  options.function_tolerance=number(opts,"function_tolerance",1e-12);
  options.gradient_tolerance=number(opts,"gradient_tolerance",1e-12);
  options.parameter_tolerance=number(opts,"parameter_tolerance",1e-12);
  options.max_solver_time_in_seconds=number(opts,"max_seconds",3600);
  options.jacobi_scaling=true;
  std::string strategy=text(opts,"strategy","levenberg_marquardt");
  if(strategy=="dogleg") options.trust_region_strategy_type=ceres::DOGLEG;
  else if(strategy!="levenberg_marquardt") error("GXTXT:Numeric:Ceres: unknown trust-region strategy");
  std::string reason;if(!options.IsValid(&reason)) error("GXTXT:Numeric:Ceres: %s",reason.c_str());
  Interrupt interrupt;options.callbacks.push_back(&interrupt);
  ceres::Solver::Summary summary;
  if(fitting) ceres::Solve(options,&problem,&summary);
  Matrix predicted(n,m),jacobian(total,p);ColumnVector parameters(p);
  Matrix odr_adjusted_x(odr?n:0,1),odr_corrections(odr?n:0,2),odr_normalized(odr?n:0,2);
  for(int k=0;k<p;++k) parameters(k)=model.physical_parameter(k,q.data());
  octave_idx_type offset=0;
  for(auto* block:blocks) {
    OCTAVE_QUIT;int count=block->num_residuals();
    std::vector<double> residuals(count),derivatives(static_cast<size_t>(count)*p);
    double* jac=derivatives.data();const double* parameter=q.data();
    if(!block->Evaluate(&parameter,residuals.data(),&jac)) error("GXTXT:Numeric:Ceres: model or Jacobian is nonfinite at returned parameters");
    for(int i=0;i<count;++i) {
      auto index=offset+i;auto row=index%n;int response=index/n;
      predicted(row,response)=model.evaluate(row,response,q.data());
      if(!std::isfinite(predicted(row,response))) error("GXTXT:Numeric:Ceres: nonfinite returned prediction");
      for(int k=0;k<p;++k) {
        jacobian(index,k)=derivatives[i*p+k]/scales(k);
        if(!std::isfinite(jacobian(index,k))) error("GXTXT:Numeric:Ceres: nonfinite returned physical Jacobian");
      }
    }
    offset+=count;
  }
  if(odr) for(octave_idx_type row=0;row<n;++row) {
    if((row&1023)==0) OCTAVE_QUIT;
    double residuals[2],dlatent[2];std::vector<double> derivatives(2*p);
    const double* values[]={q.data(),&latent[row]};double* derivative_blocks[]={derivatives.data(),dlatent};
    if(!odr_blocks[row]->Evaluate(values,residuals,derivative_blocks)) error("GXTXT:Numeric:Ceres: nonfinite final ODR model or derivative");
    double adjusted=X(row,0)+W(row,0)*latent[row];
    odr_adjusted_x(row,0)=adjusted;predicted(row,0)=model.evaluate(row,0,q.data(),&adjusted);
    odr_corrections(row,0)=W(row,0)*latent[row];odr_corrections(row,1)=predicted(row,0)-Y(row,0);
    odr_normalized(row,0)=residuals[0];odr_normalized(row,1)=residuals[1];
    // Orthogonal elimination of the one-dimensional nuisance tangent yields
    // the model-parameter Jacobian used by the shared QR/SVD covariance owner.
    // No normal-matrix subtraction or inverse is used for this covariance.
    double norm=std::hypot(dlatent[0],dlatent[1]);
    if(!std::isfinite(norm)||norm<=0||!std::isfinite(adjusted)||!std::isfinite(predicted(row,0))||!std::isfinite(odr_corrections(row,0))||!std::isfinite(odr_corrections(row,1)))
      error("GXTXT:Numeric:Ceres: nonfinite physical ODR correction or nuisance derivative");
    for(int k=0;k<p;++k) {
      jacobian(row,k)=(derivatives[p+k]/norm)/scales(k);
      if(!std::isfinite(jacobian(row,k))) error("GXTXT:Numeric:Ceres: nonfinite projected ODR Jacobian");
    }
  }
  octave_scalar_map result;
  result.assign("parameters",parameters);result.assign("predicted",predicted);result.assign("jacobian",jacobian);
  result.assign("converged",fitting&&(summary.termination_type==ceres::CONVERGENCE||summary.termination_type==ceres::USER_SUCCESS));
  result.assign("termination",fitting?ceres::TerminationTypeToString(summary.termination_type):"EVALUATED");
  result.assign("solver_message",summary.message);result.assign("iterations",static_cast<double>(summary.iterations.size()));
  result.assign("function_evaluations",summary.num_residual_evaluations);result.assign("jacobian_evaluations",summary.num_jacobian_evaluations);
  result.assign("solver_seconds",summary.total_time_in_seconds);result.assign("solver_objective",fitting?2*summary.final_cost:octave_NaN);
  result.assign("solver","ceres");result.assign("backend_version",CERES_VERSION_STRING);
  result.assign("derivative_method","automatic_differentiation");result.assign("parameter_scales",scales);
  result.assign("free_parameter_count",p-static_cast<int>(fixed.size()));result.assign("threads_used",options.num_threads);
  result.assign("adapter_dataset_copy_bytes",0.0);result.assign("adapter_dataset_view_bytes",static_cast<double>((X.numel()+Y.numel()+W.numel())*sizeof(double)));
  result.assign("jacobian_bytes",static_cast<double>(total)*p*sizeof(double));result.assign("loss",loss);
  if(odr) {
    result.assign("adjusted_x",odr_adjusted_x);result.assign("coordinate_corrections",odr_corrections);result.assign("normalized_corrections",odr_normalized);
    result.assign("linear_solver",n>2048?"dense_schur":"dense_qr");result.assign("nuisance_parameter_count",static_cast<double>(n));
    result.assign("jacobian_convention","projected_model_parameter_tangent_after_independent_latent_x_elimination");
  }
  return ovl(result);
}
