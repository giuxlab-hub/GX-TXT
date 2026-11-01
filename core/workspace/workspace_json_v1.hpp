// SPDX-License-Identifier: GPL-3.0-or-later
#pragma once
#include "workspace_v1.hpp"
#include <charconv>
#include <cmath>
#include <iomanip>
#include <locale>
#include <sstream>
#include <string_view>

namespace gx::workspace::v1 {
// JSON is an explicitly typed client transport. It is decoded into native
// graph nodes before validation/persistence; no JSON/Tcl body is a stored blob.
// This is a new-writer boundary, never an obsolete Workspace importer.
namespace json_detail {
[[noreturn]] inline void invalid(const char* reason) {throw Error("JSON",reason);}
class Reader {
    std::string_view input;
    std::size_t position=0,nodes=0;
    void space(){while(position<input.size()&&(input[position]==' '||input[position]=='\t'||input[position]=='\r'||input[position]=='\n'))++position;}
    bool take(char c){if(position<input.size()&&input[position]==c){++position;return true;}return false;}
    unsigned hex4(){unsigned code=0;for(unsigned i=0;i<4;++i){if(position==input.size())invalid("Truncated JSON Unicode escape");char c=input[position++];unsigned n;if(c>='0'&&c<='9')n=c-'0';else if(c>='a'&&c<='f')n=c-'a'+10;else if(c>='A'&&c<='F')n=c-'A'+10;else invalid("Invalid JSON Unicode escape");code=code*16+n;}return code;}
    static void utf8(std::string& out,unsigned code){
        if(code<0x80)out+=static_cast<char>(code);
        else if(code<0x800){out+=static_cast<char>(0xc0|(code>>6));out+=static_cast<char>(0x80|(code&63));}
        else if(code<0x10000){out+=static_cast<char>(0xe0|(code>>12));out+=static_cast<char>(0x80|((code>>6)&63));out+=static_cast<char>(0x80|(code&63));}
        else{out+=static_cast<char>(0xf0|(code>>18));out+=static_cast<char>(0x80|((code>>12)&63));out+=static_cast<char>(0x80|((code>>6)&63));out+=static_cast<char>(0x80|(code&63));}
    }
    std::string string(){
        if(!take('"'))invalid("JSON object keys and strings require quotes");
        std::string out;
        while(position<input.size()){
            unsigned char c=input[position++];
            if(c=='"')return out;
            if(c<32)invalid("Unescaped control character in JSON string");
            if(c=='\\'){
                if(position==input.size())invalid("Truncated JSON escape");
                switch(input[position++]){
                    case '"':out+='"';break;case '\\':out+='\\';break;case '/':out+='/';break;
                    case 'b':out+='\b';break;case 'f':out+='\f';break;case 'n':out+='\n';break;case 'r':out+='\r';break;case 't':out+='\t';break;
                    case 'u':{unsigned code=hex4();if(code>=0xd800&&code<=0xdbff){if(!take('\\')||!take('u'))invalid("JSON high surrogate requires a low surrogate");unsigned low=hex4();if(low<0xdc00||low>0xdfff)invalid("Invalid JSON low surrogate");code=0x10000+((code-0xd800)<<10)+(low-0xdc00);}else if(code>=0xdc00&&code<=0xdfff)invalid("Unpaired JSON low surrogate");utf8(out,code);break;}
                    default:invalid("Unknown JSON escape");
                }
            }else if(c<0x80)out+=static_cast<char>(c);
            else{
                unsigned count,code,minimum;
                if(c>=0xc2&&c<=0xdf){count=1;code=c&31;minimum=0x80;}
                else if(c>=0xe0&&c<=0xef){count=2;code=c&15;minimum=0x800;}
                else if(c>=0xf0&&c<=0xf4){count=3;code=c&7;minimum=0x10000;}
                else invalid("Invalid UTF-8 in JSON string");
                for(unsigned i=0;i<count;++i){if(position==input.size())invalid("Truncated UTF-8 in JSON string");unsigned char next=input[position++];if((next&0xc0)!=0x80)invalid("Invalid UTF-8 continuation in JSON string");code=(code<<6)|(next&63);}
                if(code<minimum||code>0x10ffff||(code>=0xd800&&code<=0xdfff))invalid("Invalid UTF-8 code point in JSON string");
                utf8(out,code);
            }
        }
        invalid("Unterminated JSON string");
    }
    Value number(){
        auto start=position;take('-');
        if(!take('0')){if(position==input.size()||input[position]<'1'||input[position]>'9')invalid("Invalid JSON number");while(position<input.size()&&input[position]>='0'&&input[position]<='9')++position;}
        bool real=false;
        if(take('.')){real=true;auto first=position;while(position<input.size()&&input[position]>='0'&&input[position]<='9')++position;if(position==first)invalid("JSON fraction needs digits");}
        if(position<input.size()&&(input[position]=='e'||input[position]=='E')){++position;real=true;if(!take('+'))take('-');auto first=position;while(position<input.size()&&input[position]>='0'&&input[position]<='9')++position;if(first==position)invalid("JSON exponent needs digits");}
        auto spelling=input.substr(start,position-start);Value result;
        if(!real&&spelling!="-0"){
            std::int64_t integer=0;auto parsed=std::from_chars(spelling.data(),spelling.data()+spelling.size(),integer);
            if(parsed.ec!=std::errc()||parsed.ptr!=spelling.data()+spelling.size())invalid("JSON integer exceeds native signed 64-bit range; use an explicit scientific descriptor");
            result=Value::number(integer);
        }else{
            double scalar=0;auto parsed=std::from_chars(spelling.data(),spelling.data()+spelling.size(),scalar,std::chars_format::general);
            if(parsed.ec!=std::errc()||parsed.ptr!=spelling.data()+spelling.size()||!std::isfinite(scalar))invalid("JSON real is outside the finite native range");
            result=Value::floating(scalar);
        }
        // Tcl classifies integer-style -0 through integer zero. At this
        // explicit JSON boundary use its equivalent decimal spelling so the
        // typed real preserves the native IEEE sign through the Tcl transport.
        result.text=spelling=="-0"?"-0.0":std::string(spelling);return result;
    }
    Value value(unsigned depth){
        if(depth>64||++nodes>262144)invalid("JSON graph exceeds native depth/node bound");
        space();if(position==input.size())invalid("Missing JSON value");
        if(input[position]=='"')return Value::string(string());
        if(take('{')){Value result=Value::object();space();if(take('}'))return result;for(;;){space();auto key=string();space();if(!take(':'))invalid("Missing JSON object colon");auto child=value(depth+1);if(!result.fields.emplace(key,std::move(child)).second)invalid("Duplicate JSON object key");result.field_order.push_back(std::move(key));space();if(take('}'))return result;if(!take(','))invalid("Missing JSON object comma");}}
        if(take('[')){std::vector<Value> result;space();if(take(']'))return Value::array();for(;;){result.push_back(value(depth+1));space();if(take(']'))return Value::array(std::move(result));if(!take(','))invalid("Missing JSON array comma");}}
        for(auto token:{std::string_view("true"),std::string_view("false"),std::string_view("null")})if(input.substr(position,token.size())==token){position+=token.size();if(token=="null")return Value{};auto result=Value::boolean(token=="true");result.text=std::string(token);return result;}
        return number();
    }
public:
    explicit Reader(std::string_view source):input(source){if(input.size()>16777216)invalid("JSON transport exceeds 16 MiB");}
    Value read(){auto result=value(0);space();if(position!=input.size())invalid("Trailing input after JSON value");return result;}
};
inline void quoted(std::string& output,const std::string& text){
    static constexpr char hex[]="0123456789abcdef";output+='"';
    for(unsigned char c:text){switch(c){case '"':output+="\\\"";break;case '\\':output+="\\\\";break;case '\b':output+="\\b";break;case '\f':output+="\\f";break;case '\n':output+="\\n";break;case '\r':output+="\\r";break;case '\t':output+="\\t";break;default:if(c<32){output+="\\u00";output+=hex[c>>4];output+=hex[c&15];}else output+=static_cast<char>(c);}}
    output+='"';
}
inline void write(std::string& output,const Value& value,unsigned depth,std::size_t& nodes,bool lexical=false){
    if(depth>64||++nodes>262144||output.size()>16777216)invalid("JSON output exceeds native bounds");
    switch(value.kind){
        case Kind::null:output+="null";break;
        case Kind::text:quoted(output,value.text);break;
        case Kind::boolean:output+=value.integer?"true":"false";break;
        case Kind::integer:{bool emitted=false;if(lexical&&!value.text.empty()){try{auto scalar=Reader(value.text).read();if(scalar.kind==Kind::integer&&scalar.integer==value.integer){output+=value.text;emitted=true;}}catch(const Error&){}}if(!emitted)output+=std::to_string(value.integer);break;}
        case Kind::real:{if(lexical&&!value.text.empty()){try{auto scalar=Reader(value.text).read();if(scalar.kind==Kind::real&&scalar.real==value.real&&(scalar.real!=0||std::signbit(scalar.real)==std::signbit(value.real))){output+=value.text;break;}}catch(const Error&){}}if(!std::isfinite(value.real))invalid("JSON requires an explicit descriptor for nonfinite scientific values");std::ostringstream stream;stream.imbue(std::locale::classic());stream<<std::setprecision(17)<<value.real;auto scalar=stream.str();if(scalar.find_first_of(".eE")==std::string::npos)scalar+=".0";output+=scalar;break;}
        case Kind::array:{output+='[';bool first=true;for(const auto& child:value.elements){if(!first)output+=',';first=false;write(output,child,depth+1,nodes,lexical);}output+=']';break;}
        case Kind::object:{output+='{';bool first=true;auto field=[&](const auto& key){if(!first)output+=',';first=false;quoted(output,key);output+=':';write(output,value.fields.at(key),depth+1,nodes,lexical);};if(value.field_order.empty()){for(const auto& child:value.fields)field(child.first);}else for(const auto& key:value.field_order)field(key);output+='}';break;}
        case Kind::resource:invalid("JSON client transport cannot erase a managed reference kind; use the typed Workspace API");
    }
}
}
inline Value workspace_json_decode(std::string_view input){return json_detail::Reader(input).read();}
inline std::string workspace_json_encode(const Value& value,bool lexical=false){std::string result;std::size_t nodes=0;json_detail::write(result,value,0,nodes,lexical);if(result.size()>16777216)json_detail::invalid("JSON output exceeds 16 MiB");return result;}
}
