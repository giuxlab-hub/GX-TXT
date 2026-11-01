// SPDX-License-Identifier: GPL-3.0-or-later
// Fixed target adapter; callbacks are selected by separately generated finite glue.
#include "gxtxt_acquisition_sdk_v1.hpp"
#include <cmath>
#include <cstring>
#include <iomanip>
#include <limits>
#include <sstream>
#include <stdexcept>
namespace gx {
AcquisitionValue acquisition_text(std::string s){AcquisitionValue v;v.kind=AcquisitionValue::Kind::text;v.text=std::move(s);return v;}
AcquisitionValue acquisition_integer(std::int64_t n){AcquisitionValue v;v.kind=AcquisitionValue::Kind::integer;v.integer=n;return v;}
AcquisitionValue acquisition_number(double n){if(!std::isfinite(n))throw std::runtime_error("Metadata must be finite");AcquisitionValue v;v.kind=AcquisitionValue::Kind::real;v.real=n;return v;}
AcquisitionValue acquisition_flag(bool n){AcquisitionValue v;v.kind=AcquisitionValue::Kind::boolean;v.integer=n;return v;}
AcquisitionValue acquisition_object(std::map<std::string,AcquisitionValue> m){AcquisitionValue v;v.kind=AcquisitionValue::Kind::object;v.fields=std::move(m);return v;}
AcquisitionValue acquisition_array(std::vector<AcquisitionValue> a){AcquisitionValue v;v.kind=AcquisitionValue::Kind::array;v.elements=std::move(a);return v;}
namespace {
using V=AcquisitionValue;
std::string quote(const std::string& s){std::ostringstream o;o<<'"';for(unsigned char c:s){if(c=='"'||c=='\\')o<<'\\'<<char(c);else if(c<32)o<<"\\u"<<std::hex<<std::setw(4)<<std::setfill('0')<<unsigned(c)<<std::dec;else o<<char(c);}o<<'"';return o.str();}
std::string encode(const V& v,unsigned d=0){if(d>24)throw std::runtime_error("Metadata nesting exceeds 24");std::string o;switch(v.kind){
case V::Kind::null:return "null";case V::Kind::text:if(v.text.size()>196608)throw std::runtime_error("Metadata text exceeds bound");return quote(v.text);
case V::Kind::integer:return std::to_string(v.integer);case V::Kind::boolean:return v.integer?"true":"false";
case V::Kind::real:{if(!std::isfinite(v.real))throw std::runtime_error("Metadata must be finite");std::ostringstream s;s<<std::setprecision(17)<<v.real;return s.str();}
case V::Kind::object:o="{";for(const auto& p:v.fields){if(o.size()>1)o+=',';o+=quote(p.first)+":"+encode(p.second,d+1);}o+='}';break;
case V::Kind::array:o="[";for(const auto& p:v.elements){if(o.size()>1)o+=',';o+=encode(p,d+1);}o+=']';break;}
if(o.size()>196608)throw std::runtime_error("Metadata exceeds control bound");return o;}
struct Parser {
    const std::string& s;std::size_t p=0;unsigned nodes=0;
    [[noreturn]] void bad(){throw std::runtime_error("Invalid bounded native metadata");}
    void space(){while(p<s.size()&&(s[p]==' '||s[p]=='\n'||s[p]=='\r'||s[p]=='\t'))++p;}
    bool take(char c){space();if(p<s.size()&&s[p]==c){++p;return true;}return false;}
    unsigned hex4(){unsigned n=0;for(unsigned i=0;i<4;++i){if(p>=s.size())bad();char c=s[p++];n<<=4;if(c>='0'&&c<='9')n+=c-'0';else if(c>='a'&&c<='f')n+=c-'a'+10;else if(c>='A'&&c<='F')n+=c-'A'+10;else bad();}return n;}
    void utf8(std::string& o,unsigned n){if(n<128)o+=char(n);else if(n<2048){o+=char(0xc0|(n>>6));o+=char(0x80|(n&63));}else if(n<65536){o+=char(0xe0|(n>>12));o+=char(0x80|((n>>6)&63));o+=char(0x80|(n&63));}else{o+=char(0xf0|(n>>18));o+=char(0x80|((n>>12)&63));o+=char(0x80|((n>>6)&63));o+=char(0x80|(n&63));}}
    std::string text(){if(!take('"'))bad();std::string o;while(p<s.size()){unsigned char c=s[p++];if(c=='"')return o;if(c<32)bad();if(c!='\\'){o+=char(c);continue;}if(p==s.size())bad();char e=s[p++];switch(e){case '"':case '\\':case '/':o+=e;break;case 'b':o+='\b';break;case 'f':o+='\f';break;case 'n':o+='\n';break;case 'r':o+='\r';break;case 't':o+='\t';break;case 'u':{unsigned n=hex4();if(n>=0xd800&&n<=0xdbff){if(p+2>s.size()||s[p++]!='\\'||s[p++]!='u')bad();unsigned low=hex4();if(low<0xdc00||low>0xdfff)bad();n=0x10000+((n-0xd800)<<10)+low-0xdc00;}else if(n>=0xdc00&&n<=0xdfff)bad();utf8(o,n);break;}default:bad();}}bad();}
    V value(unsigned d=0){space();if(d>24||++nodes>32768||p>=s.size())bad();if(s[p]=='"')return acquisition_text(text());
        if(take('{')){auto v=acquisition_object();if(take('}'))return v;do{auto k=text();if(!take(':')||v.fields.count(k))bad();v.fields.emplace(k,value(d+1));}while(take(','));if(!take('}'))bad();return v;}
        if(take('[')){auto v=acquisition_array();if(take(']'))return v;do{v.elements.push_back(value(d+1));}while(take(','));if(!take(']'))bad();return v;}
        for(const auto& literal:{std::string("true"),std::string("false"),std::string("null")})if(s.compare(p,literal.size(),literal)==0){p+=literal.size();return literal=="null"?V{}:acquisition_flag(literal=="true");}
        std::size_t start=p;if(s[p]=='-')++p;if(p>=s.size())bad();if(s[p]=='0')++p;else{if(s[p]<'1'||s[p]>'9')bad();while(p<s.size()&&s[p]>='0'&&s[p]<='9')++p;}
        bool real=false;if(p<s.size()&&s[p]=='.'){real=true;++p;auto old=p;while(p<s.size()&&s[p]>='0'&&s[p]<='9')++p;if(p==old)bad();}
        if(p<s.size()&&(s[p]=='e'||s[p]=='E')){real=true;++p;if(p<s.size()&&(s[p]=='+'||s[p]=='-'))++p;auto old=p;while(p<s.size()&&s[p]>='0'&&s[p]<='9')++p;if(p==old)bad();}
        auto token=s.substr(start,p-start);try{return real?acquisition_number(std::stod(token)):acquisition_integer(std::stoll(token));}catch(...){bad();}}
};
V decode(const std::string& s){if(s.size()>196608)throw std::runtime_error("Metadata exceeds control bound");Parser p{s};auto v=p.value();p.space();if(p.p!=s.size())p.bad();return v;}
const V& field(const V& v,const char* key){if(v.kind!=V::Kind::object||!v.fields.count(key))throw std::runtime_error("Missing native metadata field");return v.fields.at(key);}
std::string text(const V& v){if(v.kind!=V::Kind::text)throw std::runtime_error("Expected metadata text");return v.text;}
std::uint64_t integer(const V& v){if(v.kind!=V::Kind::integer||v.integer<0)throw std::runtime_error("Expected nonnegative metadata integer");return std::uint64_t(v.integer);}
bool flag(const V& v){if(v.kind!=V::Kind::boolean)throw std::runtime_error("Expected metadata flag");return v.integer!=0;}
V number(std::uint64_t n){if(n>std::uint64_t(std::numeric_limits<std::int64_t>::max()))throw std::runtime_error("Integer exceeds signed metadata range");return acquisition_integer(std::int64_t(n));}
SourceDescriptor descriptor(const V& v){SourceDescriptor d;auto index=integer(field(v,"source_index"));if(index>=64)throw std::runtime_error("Source index exceeds bound");d.source_index=unsigned(index);d.logical_name=text(field(v,"logical_name"));d.size=integer(field(v,"size"));auto& sha=field(v,"source_sha256");if(sha.kind!=V::Kind::null)d.source_sha256=text(sha);d.full_sha_reviewed=flag(field(v,"full_sha_reviewed"));return d;}
std::vector<std::uint8_t> unbase64(const std::string& s){if(s.size()>87384||s.size()%4)throw std::runtime_error("Invalid source chunk encoding");const std::string alphabet="ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";std::vector<std::uint8_t> out;for(std::size_t i=0;i<s.size();i+=4){unsigned n=0,pad=0;for(unsigned j=0;j<4;++j){char c=s[i+j];if(c=='='){if(j<2||i+4!=s.size())throw std::runtime_error("Invalid source chunk padding");++pad;n<<=6;}else{if(pad)throw std::runtime_error("Invalid source chunk padding");auto x=alphabet.find(c);if(x==std::string::npos)throw std::runtime_error("Invalid source chunk alphabet");n=(n<<6)|unsigned(x);}}if(pad>2||(pad==2&&(n&65535))||(pad==1&&(n&255)))throw std::runtime_error("Noncanonical source chunk padding");out.push_back((n>>16)&255);if(pad<2)out.push_back((n>>8)&255);if(!pad)out.push_back(n&255);}return out;}
}
AcquisitionValue AcquisitionHost::call(unsigned op,const V& args,const void* bytes,unsigned size) const {auto wire=encode(args);std::vector<char> response(196609);unsigned used=0;if(!dispatch_||dispatch_(context_,op,wire.c_str(),bytes,size,response.data(),unsigned(response.size()),&used)||used>=response.size())throw std::runtime_error("CORE Acquisition capability refused");return decode(std::string(response.data(),used));}
SourceDescriptor AcquisitionHost::source_info(unsigned index) const{return descriptor(call(1,acquisition_object({{"source_index",number(index)}})));}
SourceChunk AcquisitionHost::source_read(unsigned index,std::uint64_t offset,unsigned count) const{if(!count||count>65536)throw std::runtime_error("Source chunk requires 1..65536 bytes");auto v=call(2,acquisition_object({{"source_index",number(index)},{"offset",number(offset)},{"count",number(count)}}));SourceChunk c;c.offset=integer(field(v,"offset"));c.total_size=integer(field(v,"total_size"));c.eof=flag(field(v,"eof"));c.bytes=unbase64(text(field(v,"bytes_base64")));if(c.offset!=offset||c.bytes.size()!=integer(field(v,"byte_count"))||c.bytes.size()>count)throw std::runtime_error("Source chunk receipt differs");return c;}
bool AcquisitionHost::cancelled() const{return flag(field(call(4,acquisition_object()),"cancelled"));}
void AcquisitionHost::progress(const char* phase,const char* message) const{call(3,acquisition_object({{"phase",acquisition_text(phase?phase:"")},{"message",acquisition_text(message?message:"")}}));}
void AcquisitionHost::progress(const char* phase,const char* message,std::uint64_t current,std::uint64_t total) const{call(3,acquisition_object({{"phase",acquisition_text(phase?phase:"")},{"message",acquisition_text(message?message:"")},{"current",number(current)},{"total",number(total)}}));}
PreparedOutput AcquisitionHost::prepare_output(const V& definition,std::uint64_t rows,const V& variables) const{auto v=call(5,acquisition_object({{"definition",definition},{"row_count",number(rows)},{"variables",variables}}));PreparedOutput out;out.output_id=text(field(v,"output_id"));const auto& vars=field(v,"variables");if(vars.kind!=V::Kind::array)throw std::runtime_error("Invalid output variables");for(const auto& r:vars.elements)out.variables.push_back({text(field(r,"variable_id")),integer(field(r,"byte_count"))});return out;}
PreparedOutput AcquisitionHost::prepare_output(const V& definition,const V& dimensions,const V& variables) const{auto v=call(5,acquisition_object({{"definition",definition},{"dimensions",dimensions},{"variables",variables}}));PreparedOutput out;out.output_id=text(field(v,"output_id"));const auto& vars=field(v,"variables");if(vars.kind!=V::Kind::array)throw std::runtime_error("Invalid output variables");for(const auto& r:vars.elements)out.variables.push_back({text(field(r,"variable_id")),integer(field(r,"byte_count"))});return out;}
void AcquisitionHost::output_write(const PreparedOutput& out,const char* variable,std::uint64_t offset,const void* bytes,unsigned count) const{if(!count||count>65536||!bytes)throw std::runtime_error("Output chunk requires 1..65536 bytes");call(6,acquisition_object({{"output_id",acquisition_text(out.output_id)},{"variable_id",acquisition_text(variable?variable:"")},{"offset",number(offset)}}),bytes,count);}
PreparedReference AcquisitionHost::output_finish(const PreparedOutput& out) const{auto v=call(7,acquisition_object({{"output_id",acquisition_text(out.output_id)}}));return {text(field(v,"output_id"))};}
AcquisitionValue AcquisitionHost::helper_call(const char* id,const V& args) const{return call(8,acquisition_object({{"helper_id",acquisition_text(id?id:"")},{"args",args}}));}
AcquisitionValue AcquisitionHost::scientific_spectrum_parse(unsigned index,const char* format,const V& options) const{return call(9,acquisition_object({{"source_index",number(index)},{"format",acquisition_text(format?format:"")},{"options",options}}));}
AcquisitionValue AcquisitionHost::scientific_spectrum_read(const char* token,std::uint64_t offset,unsigned count) const{if(!count||count>2048)throw std::runtime_error("Scientific source page requires 1..2048 rows");return call(10,acquisition_object({{"parse_token",acquisition_text(token?token:"")},{"offset",number(offset)},{"count",number(count)}}));}
// Generated finite dispatch is compiled from the same admitted manifest snapshot.
AcquisitionResult acquisition_dispatch_v1(const std::string&,const std::string&,AcquisitionHost&,const AcquisitionRequest&);
struct AcquisitionHostAccess {static AcquisitionResult run(void* ctx,int (*cb)(void*,unsigned,const char*,const void*,unsigned,char*,unsigned,unsigned*),const std::string& profile,const std::string& phase,const V& value){AcquisitionHost host;host.context_=ctx;host.dispatch_=cb;AcquisitionRequest r;r.phase=phase;r.qualified_profile=profile;r.config=field(value,"config");r.mapping=field(value,"mapping");r.limits=field(value,"limits");const auto& rows=field(value,"source_descriptors");if(rows.kind!=V::Kind::array||rows.elements.size()>64)throw std::runtime_error("Invalid source descriptors");for(const auto& row:rows.elements)r.sources.push_back(descriptor(row));return acquisition_dispatch_v1(profile,phase,host,r);}};
}
extern "C" __attribute__((visibility("default"))) int gxtxt_acquisition_invoke_v1(void* context,int (*dispatch)(void*,unsigned,const char*,const void*,unsigned,char*,unsigned,unsigned*),const char* profile,const char* phase,const char* request,char* result,unsigned capacity,unsigned* used){
    if(!dispatch||!profile||!phase||!request||!result||!used)return 1;
    try{auto value=gx::decode(request);auto answer=gx::AcquisitionHostAccess::run(context,dispatch,profile,phase,value);if(answer.kind!=gx::AcquisitionValue::Kind::object)throw std::runtime_error("Acquisition callback must return an object");auto wire=gx::encode(answer);if(wire.size()>=capacity)throw std::runtime_error("Acquisition result exceeds bound");std::memcpy(result,wire.data(),wire.size());*used=unsigned(wire.size());return 0;}catch(const std::exception& e){auto wire=std::string(e.what());if(wire.size()>=capacity)wire="Native callback failed";if(wire.size()<capacity){std::memcpy(result,wire.data(),wire.size());*used=unsigned(wire.size());}return 1;}catch(...){*used=0;return 1;}}
