// SPDX-License-Identifier: GPL-3.0-or-later
// Local application presentation only. CORE retains archive, I/O and lifecycle.
#include <string>
#include <vector>
#include <deque>
#include <map>
#include <algorithm>
#include <cstdint>
#include <stdexcept>

namespace diagnostic {
constexpr unsigned FORM=24, STATUS=25, CACHE_STATUS=26;
constexpr unsigned RECORDS=27, LOG=28, SEARCH=7, ORDER=8;
constexpr unsigned SEVERITY=9, PAUSE=10, AUTOSCROLL=11;
constexpr unsigned REFRESH=14, NEXT=15, PREVIOUS=16, LATEST=17;
constexpr unsigned STATUS_REFRESH=18, COPY=19, EXPORT_SELECTED=20;
constexpr unsigned EXPORT_INTERVAL=21, CANCEL=22;
const unsigned filterComponents[]={2,3,4,5,6};
const char* const filterKeys[]={"module_id","api_id","viewer_id","job_id","process_id"};

struct Json {
    enum Kind {Null,Boolean,Number,String,Array,Object} kind=Null;
    std::string text;
    std::vector<Json> items;
    std::map<std::string,Json> members;
    const Json& get(const std::string& key) const {
        static const Json absent;
        auto at=members.find(key);return at==members.end()?absent:at->second;
    }
    std::string str(const std::string& fallback="") const {
        return kind==String || kind==Number || kind==Boolean ? text:fallback;
    }
    bool boolean(bool fallback=false) const {return kind==Boolean?text=="true":fallback;}
};

void utf8(std::string& out,unsigned point) {
    if(point<=0x7f)out+=char(point);
    else if(point<=0x7ff){out+=char(0xc0|(point>>6));out+=char(0x80|(point&63));}
    else if(point<=0xffff){out+=char(0xe0|(point>>12));out+=char(0x80|((point>>6)&63));out+=char(0x80|(point&63));}
    else {out+=char(0xf0|(point>>18));out+=char(0x80|((point>>12)&63));out+=char(0x80|((point>>6)&63));out+=char(0x80|(point&63));}
}
class JsonParser {
    const std::string& source;std::size_t pos=0;
    [[noreturn]] void fail() const {throw std::runtime_error("Invalid bounded CORE JSON data");}
    void space(){while(pos<source.size()&&(source[pos]==' '||source[pos]=='\n'||source[pos]=='\r'||source[pos]=='\t'))++pos;}
    unsigned hex4(){unsigned value=0;for(int i=0;i<4;++i){if(pos>=source.size())fail();char c=source[pos++];unsigned n=c>='0'&&c<='9'?c-'0':c>='a'&&c<='f'?c-'a'+10:c>='A'&&c<='F'?c-'A'+10:16;if(n>15)fail();value=(value<<4)|n;}return value;}
    std::string string(){
        if(pos>=source.size()||source[pos++]!='"')fail();std::string value;
        while(pos<source.size()) {
            unsigned char c=source[pos++];if(c=='"')return value;if(c<32)fail();
            if(c!='\\'){value+=char(c);continue;}
            if(pos>=source.size())fail();char e=source[pos++];
            switch(e){case '"':value+='"';break;case '\\':value+='\\';break;case '/':value+='/';break;
            case 'b':value+='\b';break;case 'f':value+='\f';break;case 'n':value+='\n';break;case 'r':value+='\r';break;case 't':value+='\t';break;
            case 'u': {unsigned n=hex4();if(n>=0xd800&&n<=0xdbff){if(pos+2>source.size()||source[pos++]!='\\'||source[pos++]!='u')fail();unsigned low=hex4();if(low<0xdc00||low>0xdfff)fail();n=0x10000+((n-0xd800)<<10)+(low-0xdc00);}else if(n>=0xdc00&&n<=0xdfff)fail();utf8(value,n);break;}
            default:fail();}
        }fail();
    }
    Json value(unsigned depth){
        if(depth>32)fail();space();if(pos>=source.size())fail();Json node;char c=source[pos];
        if(c=='"'){node.kind=Json::String;node.text=string();return node;}
        if(c=='{'||c=='['){
            bool object=c=='{';node.kind=object?Json::Object:Json::Array;++pos;space();char end=object?'}':']';
            if(pos<source.size()&&source[pos]==end){++pos;return node;}
            for(unsigned count=0;count<65536;++count){space();std::string key;if(object){key=string();space();if(pos>=source.size()||source[pos++]!=':')fail();}
                Json child=value(depth+1);if(object){if(node.members.count(key))fail();node.members.emplace(key,std::move(child));}else node.items.push_back(std::move(child));
                space();if(pos>=source.size())fail();char sep=source[pos++];if(sep==end)return node;if(sep!=',')fail();
            }fail();
        }
        for(const auto& token: {std::string("true"),std::string("false"),std::string("null")}){
            if(source.compare(pos,token.size(),token)==0){pos+=token.size();node.kind=token=="null"?Json::Null:Json::Boolean;node.text=token;return node;}}
        node.kind=Json::Number;std::size_t first=pos;if(source[pos]=='-')++pos;
        if(pos>=source.size())fail();if(source[pos]=='0')++pos;else {if(source[pos]<'1'||source[pos]>'9')fail();while(pos<source.size()&&source[pos]>='0'&&source[pos]<='9')++pos;}
        if(pos<source.size()&&source[pos]=='.'){++pos;std::size_t start=pos;while(pos<source.size()&&source[pos]>='0'&&source[pos]<='9')++pos;if(start==pos)fail();}
        if(pos<source.size()&&(source[pos]=='e'||source[pos]=='E')){++pos;if(pos<source.size()&&(source[pos]=='+'||source[pos]=='-'))++pos;std::size_t start=pos;while(pos<source.size()&&source[pos]>='0'&&source[pos]<='9')++pos;if(start==pos)fail();}
        node.text=source.substr(first,pos-first);return node;
    }
public:
    explicit JsonParser(const std::string& input):source(input){}
    Json parse(){if(source.size()>2097152)fail();auto result=value(0);space();if(pos!=source.size())fail();return result;}
};

std::string quote(const std::string& text){
    const char* hex="0123456789abcdef";std::string out="\"";
    for(unsigned char c:text){switch(c){case '"':out+="\\\"";break;case '\\':out+="\\\\";break;case '\n':out+="\\n";break;case '\r':out+="\\r";break;case '\t':out+="\\t";break;default:if(c<32){out+="\\u00";out+=hex[c>>4];out+=hex[c&15];}else out+=char(c);}}
    out+='"';return out;
}
std::string lower(std::string text){for(char& c:text)if(c>='A'&&c<='Z')c+=char('a'-'A');return text;}
std::uint64_t integer(const std::string& text){
    if(text.empty()||text.size()>20)throw std::runtime_error("Invalid exact integer metadata");
    std::uint64_t out=0;for(char c:text){if(c<'0'||c>'9'||out>(UINT64_MAX-unsigned(c-'0'))/10)throw std::runtime_error("Invalid exact integer metadata");out=out*10+unsigned(c-'0');}return out;
}
std::string decode64(const std::string& source){
    const std::string alphabet="ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
    if(source.size()>45000||source.size()%4)throw std::runtime_error("Invalid bounded base64 payload");
    std::string out;unsigned accumulator=0,bits=0;bool padded=false;unsigned padding=0;
    for(char c:source){if(c=='='){padded=true;++padding;if(padding>2)throw std::runtime_error("Invalid base64 padding");continue;}
        auto at=alphabet.find(c);if(padded||at==std::string::npos)throw std::runtime_error("Invalid base64 payload");
        accumulator=(accumulator<<6)|unsigned(at);bits+=6;if(bits>=8){bits-=8;out+=char((accumulator>>bits)&255);}}
    if((padding==0&&bits!=0)||(padding==1&&bits!=2)||(padding==2&&bits!=4)||(bits&&((accumulator&((1u<<bits)-1))!=0)))throw std::runtime_error("Invalid base64 terminal bits");
    if(out.size()>32768)throw std::runtime_error("Payload exceeds collector bound");return out;
}
std::string printable(const std::string& raw){
    const char* hex="0123456789abcdef";std::string out;
    for(std::size_t i=0;i<raw.size();){unsigned char c=raw[i];
        if((c>=32&&c<127)||c=='\n'||c=='\r'||c=='\t'){out+=char(c);++i;continue;}
        unsigned count=c>=0xc2&&c<=0xdf?2:c>=0xe0&&c<=0xef?3:c>=0xf0&&c<=0xf4?4:0;
        bool valid=count&&i+count<=raw.size();unsigned point=count==2?c&31:count==3?c&15:c&7;
        for(unsigned j=1;valid&&j<count;++j){unsigned char tail=raw[i+j];valid=(tail&0xc0)==0x80;point=(point<<6)|(tail&63);}
        if(valid&&((count==3&&point<0x800)||(count==4&&point<0x10000)||point>0x10ffff||(point>=0xd800&&point<=0xdfff)))valid=false;
        if(valid){out.append(raw,i,count);i+=count;}else{out+="\\x";out+=hex[c>>4];out+=hex[c&15];++i;}
    }return out;
}
std::string prefix(const std::string& text,std::size_t maximum){
    if(text.size()<=maximum)return text;std::size_t end=maximum;
    while(end>0&&(static_cast<unsigned char>(text[end])&0xc0)==0x80)--end;
    return text.substr(0,end);
}

struct Record {
    std::string id,timestamp,capture,source,stream,severity,payload64,display;
    std::map<std::string,std::string> origin;
    std::uint64_t time=0;
    static Record from(const Json& value){
        if(value.kind!=Json::Object||value.get("schema").str()!="gxtxt.stderr_record.v1")throw std::runtime_error("Unsupported diagnostic record schema");
        Record r;r.id=value.get("record_id").str();if(r.id.empty()||r.id.size()>128)throw std::runtime_error("Missing stable record ID");
        r.timestamp=value.get("timestamp_us").str();r.time=integer(r.timestamp);r.capture=value.get("capture_pid").str("unknown");
        const Json& origin=value.get("origin");
        for(const auto& entry:origin.members)if(entry.second.kind==Json::String)r.origin[entry.first]=entry.second.text;
        for(const char* key:filterKeys)if(!r.origin.count(key))r.origin[key]="unknown";
        r.source=origin.get("source").str("unknown");r.stream=origin.get("stream").str("unknown");r.severity=origin.get("severity").str("unknown");
        r.payload64=value.get("payload_base64").str();std::string bytes=decode64(r.payload64);
        if(integer(value.get("payload_bytes").str())!=bytes.size())throw std::runtime_error("Diagnostic payload length mismatch");
        r.display=printable(bytes);return r;
    }
    std::string classification() const {auto s=lower(severity);if(s=="error"||s=="fatal"||s=="critical")return "Error";if(s=="warning"||s=="warn")return "Warning";if(s=="info"||s=="debug"||s=="trace")return "Info";return "Other";}
    std::string style() const {auto s=classification();return s=="Error"?"error":s=="Warning"?"warning":s=="Info"?"info":"normal";}
};
struct Page {std::string cursor,next;bool eof=false;std::size_t bytes=0;std::vector<Record> records;};

class Controller final {
    std::deque<Page> pages;
    std::size_t active=0;
    std::vector<const Record*> visible;
    std::vector<std::string> selected;
    std::string nextCursor,pendingCursor,pendingId,pendingOperation,lastWritten,notice,captureStatus="Capture status pending.";
    unsigned requestCounter=0;
    bool pending=false,pendingFollow=false,backlog=false,paused=false,autoscroll=true,descending=false;
    std::string search,severity="All",filters[5];
    std::string requestId(){return "viewer-"+std::to_string(++requestCounter);}
    static std::string safeInput(const gx::Host& host,unsigned component){const char* value=host.input(component);return value?value:"";}
    void status(const gx::Host& host){host.text(STATUS,prefix(captureStatus,252).c_str());}
    void read(const gx::Host& host,const std::string& cursor,bool follow=false){
        if(pending){notice="An archive request is pending; cancel it or wait.";return;}
        pendingCursor=cursor;pendingId=requestId();pending=true;pendingFollow=follow;pendingOperation="read";
        // A follow read consumes the known notification, not future changes
        // delivered while this request is pending. Those remain a separate tail.
        if(follow)backlog=false;
        const std::string request="{\"cursor\":"+quote(cursor)+",\"limit\":256,\"max_bytes\":524288,\"request_id\":"+quote(pendingId)+"}";
        host.diagnostics_command(FORM,"read",request.c_str());
    }
    void resumeFollow(const gx::Host& host){if(backlog&&!paused&&!pending)read(host,nextCursor,true);}
    void updateInputs(const gx::Host& host){
        for(unsigned i=0;i<5;++i)filters[i]=safeInput(host,filterComponents[i]);
        search=safeInput(host,SEARCH);severity=safeInput(host,SEVERITY);
        descending=safeInput(host,ORDER)=="Newest first";paused=safeInput(host,PAUSE)=="1";autoscroll=safeInput(host,AUTOSCROLL)!="0";
    }
    bool matches(const Record& r) const {
        for(unsigned i=0;i<5;++i){auto at=r.origin.find(filterKeys[i]);if(!filters[i].empty()&&(at==r.origin.end()||at->second.find(filters[i])==std::string::npos))return false;}
        return (severity=="All"||severity.empty()||r.classification()==severity)&&(search.empty()||lower(r.display).find(lower(search))!=std::string::npos);
    }
    void selection(const gx::Host& host){
        selected.clear();const std::string indices=safeInput(host,RECORDS);
        std::size_t pos=0;while(pos<indices.size()){
            while(pos<indices.size()&&(indices[pos]==' '||indices[pos]==','||indices[pos]=='['||indices[pos]==']'||indices[pos]=='\t'||indices[pos]=='\n'))++pos;
            if(pos==indices.size())break;std::size_t start=pos;while(pos<indices.size()&&indices[pos]>='0'&&indices[pos]<='9')++pos;
            if(start==pos)break;auto index=integer(indices.substr(start,pos-start));if(index<visible.size())selected.push_back(visible[std::size_t(index)]->id);
            if(selected.size()>=256)break;
        }
    }
    static void run(std::string& out,const std::string& text,const std::string& style,unsigned& count){
        if(text.empty()||count>=500||out.size()>119000)return;
        std::string shown=text,encoded=quote(shown);
        if(out.size()+encoded.size()+100>120000){
            const std::size_t budget=120000-out.size()-200;
            shown=prefix(text,budget/6)+"\n[Display truncated; copy/export preserves original bytes.]\n";
            encoded=quote(shown);
        }
        if(count++)out+=',';out+="{\"text\":"+encoded+",\"style\":"+quote(style)+"}";
    }
    void payloadRuns(std::string& out,const std::string& text,const std::string& style,unsigned& count) const {
        if(search.empty()){run(out,text,style,count);return;}
        auto lowered=lower(text),needle=lower(search);std::size_t begin=0;
        for(unsigned matches=0;matches<64&&count<495;++matches){auto at=lowered.find(needle,begin);if(at==std::string::npos)break;
            run(out,text.substr(begin,at-begin),style,count);run(out,text.substr(at,search.size()),"match",count);begin=at+search.size();}
        run(out,text.substr(begin),style,count);
    }
    void details(const gx::Host& host){
        std::string runs="{\"replace\":true,\"autoscroll\":"+std::string(autoscroll?"true":"false")+",\"runs\":[";unsigned count=0;std::size_t remaining=32768;unsigned shown=0;
        for(const auto* r:visible){if(std::find(selected.begin(),selected.end(),r->id)==selected.end())continue;
            if(++shown>16){run(runs,"\nAdditional selected records omitted from this bounded view.\n","muted",count);break;}
            run(runs,"Record "+r->id+" · "+r->timestamp+" µs · "+r->severity+"\n","heading",count);
            std::string origins="Source: "+r->source+" · Stream: "+r->stream+" · Capture PID: "+r->capture+"\n";
            for(const auto& entry:r->origin)origins+=entry.first+": "+entry.second+"\n";
            run(runs,origins,"muted",count);
            std::string text=prefix(r->display,std::min<std::size_t>(remaining,32768));remaining-=text.size();payloadRuns(runs,text,r->style(),count);
            if(text.size()<r->display.size())run(runs,"\n[Display truncated; copy/export preserves original record bytes.]\n","warning",count);
            run(runs,"\n","normal",count);if(!remaining)break;
        }
        if(!shown)run(runs,"Select one or more table records to inspect their original multiline payloads.\n","muted",count);
        runs+="]}";host.text_runs(LOG,runs.c_str());
    }
    void present(const gx::Host& host,bool rebuild=true,bool preserveSelection=false){
        if(rebuild){visible.clear();if(!pages.empty()){for(const auto& r:pages[active].records)if(matches(r))visible.push_back(&r);}
            std::stable_sort(visible.begin(),visible.end(),[this](const Record* a,const Record* b){if(a->time!=b->time)return descending?a->time>b->time:a->time<b->time;return descending?a->id>b->id:a->id<b->id;});
            std::string rows="[";std::size_t shown=0;for(const auto* r:visible){
                std::vector<std::string> columns={r->id,r->timestamp,r->severity,r->origin.at("module_id"),r->origin.at("api_id"),r->origin.at("viewer_id"),r->origin.at("job_id"),r->origin.at("process_id"),r->display};
                std::string row="[";for(std::size_t i=0;i<columns.size();++i){if(i)row+=',';row+=quote(i==0?columns[i]:prefix(columns[i],160));}row+=']';
                if(rows.size()+row.size()+2>120000){notice="Table presentation budget reached; original cache retained.";break;}
                if(shown++)rows+=',';rows+=row;}
            visible.resize(shown);
            rows+=']';host.table(RECORDS,rows.c_str());
            if(!preserveSelection)selected.clear();
            else selected.erase(std::remove_if(selected.begin(),selected.end(),[this](const std::string& id){return std::none_of(visible.begin(),visible.end(),[&id](const Record* r){return r->id==id;});}),selected.end());}
        std::size_t total=0,bytes=0;for(const auto& p:pages){total+=p.records.size();bytes+=p.bytes;}
        std::string summary="Cached "+std::to_string(total)+"/1024 records, "+std::to_string(bytes)+"/4194304 bytes; page "+std::to_string(pages.empty()?0:active+1)+"/"+std::to_string(pages.size())+", "+std::to_string(visible.size())+" matches. "+(pending?"Request pending. ":"")+notice;
        host.text(CACHE_STATUS,prefix(summary,252).c_str());status(host);details(host);
    }
    std::string selectionJson(){
        std::string json="{\"record_ids\":[";for(std::size_t i=0;i<selected.size();++i){if(i)json+=',';json+=quote(selected[i]);}
        json+="],\"request_id\":"+quote(pendingId)+"}";return json;
    }
    void ingest(const Json& envelope){
        std::string operation=envelope.get("operation").str();const Json& result=envelope.get("result");
        std::string correlation=envelope.get("request_id").str();
        if(result.get("status").str()=="cancelled"&&correlation==pendingId){pending=false;pendingFollow=false;pendingOperation.clear();notice="Archive request cancelled.";return;}
        if(operation=="read"){
            if(!pending||correlation!=pendingId)return;
            const bool followed=pendingFollow;
            pending=false;pendingFollow=false;pendingOperation.clear();Page page;page.cursor=pendingCursor;page.next=result.get("cursor").str();page.eof=result.get("eof").boolean(result.get("eof").str()=="1");page.bytes=std::size_t(integer(result.get("bytes").str("0")));
            const auto& records=result.get("records");if(records.kind!=Json::Array||records.items.size()>256||page.bytes>1048576)throw std::runtime_error("CORE page exceeded declared bounds");
            std::map<std::string,bool> known;
            for(const auto& cached:pages)for(const auto& r:cached.records)known.emplace(r.id,true);
            for(const auto& value:records.items){auto r=Record::from(value);if(known.emplace(r.id,true).second)page.records.push_back(std::move(r));}
            nextCursor=page.next;notice=page.eof?"End of retained snapshot.":"More archive records available.";
            if(!page.eof&&page.next==pendingCursor){backlog=false;notice="Cursor did not advance; automatic follow stopped.";}
            else if(followed&&!page.eof)backlog=true;
            if(!page.records.empty()||pages.empty()){pages.push_back(std::move(page));if(selected.empty()||!followed)active=pages.size()-1;}
            std::size_t total=0,bytes=0;for(const auto& p:pages){total+=p.records.size();bytes+=p.bytes;}
            while(pages.size()>4||total>1024||bytes>4194304){total-=pages.front().records.size();bytes-=pages.front().bytes;pages.pop_front();if(active)--active;}
        }else if(operation=="status"||operation=="changed"){
            const Json& counters=result.get("counters");
            auto counter=[&](const char* key){return result.get(key).str(counters.get(key).str("unknown"));};
            std::string state=result.get("state").str("unknown");
            captureStatus="Capture "+std::string(state=="running"?"ON":state=="off"?"OFF":state)+" | accepted "+counter("accepted_records")+" written "+counter("written_records")+" dropped "+counter("dropped_records")+" queue "+counter("queue_bytes")+" B";
            std::string error=result.get("last_error").str(result.get("error").str());if(error.empty())error=result.get("configuration_error").str();if(!error.empty())captureStatus+=" | "+error;
            std::string written=counter("written_records");bool newRecords=!lastWritten.empty()&&written!=lastWritten&&written!="unknown";lastWritten=written;
            if(newRecords)backlog=true;
        }else if(operation=="export"||operation=="copy"){
            if(correlation!=pendingId)return;pending=false;pendingFollow=false;pendingOperation.clear();
            notice=operation=="copy"?"Selected payload text copied by CORE.":"Original records exported by CORE.";
            if(!result.get("record_count").str().empty())notice+=" Records: "+result.get("record_count").str();
        }else if(operation=="cancelled"||operation=="cancel"){
            if(correlation==pendingId){pending=false;pendingFollow=false;pendingOperation.clear();notice="Archive request cancelled.";}
        }else if(operation=="error"){
            if(correlation.empty()||correlation==pendingId){
                // An invalid/expired read needs an explicit user restart, not
                // a recurring retry of the same cursor. Other terminal tasks
                // can release a separately queued live-read backlog.
                if(pendingOperation=="read")backlog=false;
                pending=false;pendingFollow=false;pendingOperation.clear();
            }
            notice="CORE: "+result.get("error_code").str(result.get("code").str())+" "+result.get("message").str(result.get("error").str("Diagnostic request failed"));
        }
    }
public:
    void event(const gx::Host& host,gx::State&,const gx::Event& event){
        updateInputs(host);
        if(event.kind==gx::EventKind::close){host.diagnostics_command(FORM,"unsubscribe");if(pending){const std::string request="{\"request_id\":"+quote(pendingId)+"}";host.diagnostics_command(FORM,"cancel",request.c_str());}return;}
        if(event.kind==gx::EventKind::open){
            host.diagnostics_command(FORM,"subscribe");host.diagnostics_command(FORM,"status");read(host,"");present(host);return;
        }
        const char* raw=host.data();if(raw&&*raw){
            auto envelope=JsonParser(std::string(raw)).parse();
            bool rebuild=envelope.get("operation").str()=="read"&&pending&&envelope.get("request_id").str()==pendingId&&envelope.get("result").get("records").kind==Json::Array;
            ingest(envelope);resumeFollow(host);present(host,rebuild,true);return;
        }
        const unsigned component=event.component;
        if(component==RECORDS){selection(host);present(host,false);return;}
        if(component==REFRESH){if(!pending){pages.clear();active=0;visible.clear();selected.clear();nextCursor.clear();backlog=false;notice.clear();read(host,"");}else notice="Cancel the pending request before restarting.";}
        else if(component==NEXT){if(active+1<pages.size())++active;else read(host,nextCursor);}
        else if(component==PREVIOUS){if(active)--active;else notice="Oldest locally retained page; earlier cache pages were evicted.";}
        else if(component==LATEST){if(!pages.empty())active=pages.size()-1;notice="Newest cached page. Use Next page to read more.";}
        else if(component==STATUS_REFRESH){host.diagnostics_command(FORM,"status");}
        else if(component==COPY||component==EXPORT_SELECTED){
            selection(host);if(selected.empty()){notice="Select retained records first.";present(host,false);return;}
            if(pending){notice="Wait for the pending request or cancel it.";present(host,false);return;}
            pendingId=requestId();pending=true;pendingFollow=false;pendingOperation=component==COPY?"copy":"export";const auto request=selectionJson();host.diagnostics_command(FORM,component==COPY?"copy":"export",request.c_str());present(host,false);return;
        }else if(component==EXPORT_INTERVAL){
            if(!pending&&!pages.empty()){pendingId=requestId();pending=true;pendingFollow=false;pendingOperation="export";const std::string request="{\"cursor\":"+quote(pages[active].cursor)+",\"limit\":4096,\"max_bytes\":8388608,\"request_id\":"+quote(pendingId)+"}";host.diagnostics_command(FORM,"export",request.c_str());}
            else notice="An existing retained page and no pending request are required.";
        }else if(component==CANCEL&&pending){const std::string request="{\"request_id\":"+quote(pendingId)+"}";host.diagnostics_command(FORM,"cancel",request.c_str());notice="Cancellation requested; waiting for CORE completion.";}
        resumeFollow(host);
        present(host,component!=AUTOSCROLL&&component!=PAUSE&&component!=STATUS_REFRESH&&component!=CANCEL);
    }
    void failure(const gx::Host& host,const std::exception& error){pending=false;pendingFollow=false;pendingOperation.clear();backlog=false;notice=error.what();present(host,false);}
};
}
void on_event(gx::Host& host,gx::State& state,const gx::Event& event){
    // One managed compiled worker per Viewer lifetime. This cache is disposable;
    // original retained records and request cleanup remain owned by CORE.
    static diagnostic::Controller controller;
    try{controller.event(host,state,event);}catch(const std::exception& error){controller.failure(host,error);}
}
