// SPDX-License-Identifier: GPL-3.0-or-later
// Interpreter-owned RAII documents; opaque node IDs never expose native pointers.
#include "render.h"
#include "source_capture.h"
#include <libxml/parser.h>
#include <libxml/tree.h>
#include <algorithm>
#include <cctype>
#include <cstring>
#include <map>
#include <memory>
#include <set>
#include <stdexcept>
#include <string>
#include <vector>
using std::string;
static string utf8(Tcl_Obj*obj){int n=0;const char*raw=Tcl_GetStringFromObj(obj,&n);Tcl_DString d;Tcl_Encoding e=Tcl_GetEncoding(nullptr,"utf-8");Tcl_UtfToExternalDString(e,raw,n,&d);string result(Tcl_DStringValue(&d),Tcl_DStringLength(&d));Tcl_DStringFree(&d);Tcl_FreeEncoding(e);return result;}
static Tcl_Obj *str(const string&s){Tcl_DString d;Tcl_Encoding e=Tcl_GetEncoding(nullptr,"utf-8");Tcl_ExternalToUtfDString(e,s.data(),(int)s.size(),&d);Tcl_Obj*result=Tcl_NewStringObj(Tcl_DStringValue(&d),Tcl_DStringLength(&d));Tcl_DStringFree(&d);Tcl_FreeEncoding(e);return result;}
static void put(Tcl_Interp*i,Tcl_Obj*d,const char*k,Tcl_Obj*v){Tcl_DictObjPut(i,d,Tcl_NewStringObj(k,-1),v);}
static void add(Tcl_Interp*i,Tcl_Obj*l,Tcl_Obj*v){Tcl_ListObjAppendElement(i,l,v);}
struct Doc {
    xmlDoc *doc;unsigned next=0;std::map<string,xmlNode*> nodes;
    explicit Doc(xmlDoc*d):doc(d){}~Doc(){xmlFreeDoc(doc);}
    string handle(xmlNode*n){for(auto &p:nodes)if(p.second==n)return p.first;string id="n"+std::to_string(++next);nodes[id]=n;return id;}
    xmlNode *node(const string&id){auto p=nodes.find(id);if(p==nodes.end())throw std::runtime_error("Stale or cross-document XML node handle");return p->second;}
    void invalidate(xmlNode*n){for(auto it=nodes.begin();it!=nodes.end();){bool child=false;for(xmlNode*x=it->second;x;x=x->parent)if(x==n)child=true;if(child)it=nodes.erase(it);else ++it;}}
};
struct Owner {unsigned next=0;std::map<string,std::unique_ptr<Doc>> docs;};
static void dispose(ClientData p,Tcl_Interp*){delete static_cast<Owner*>(p);}
static void budget(xmlNode*n,unsigned depth,unsigned &count){if(depth>64)throw std::runtime_error("XML depth exceeds 64");for(;n;n=n->next){if(++count>50000)throw std::runtime_error("XML node budget exceeds 50000");if(n->type==XML_ENTITY_REF_NODE)throw std::runtime_error("XML entity references are forbidden");budget(n->children,depth+1,count);}}
static xmlNode *named(Doc&d,xmlNode*parent,const string&name){
    if(xmlValidateQName(BAD_CAST name.c_str(),0))throw std::runtime_error("Invalid XML qualified name");
    auto colon=name.find(':');xmlNs*ns=nullptr;string local=name;
    if(colon!=string::npos){string prefix=name.substr(0,colon);local=name.substr(colon+1);ns=xmlSearchNs(d.doc,parent,BAD_CAST prefix.c_str());if(!ns)throw std::runtime_error("Namespace prefix is not declared on the parent");}
    else ns=xmlSearchNs(d.doc,parent,nullptr);
    xmlNode*n=xmlNewNode(ns,BAD_CAST local.c_str());if(!n)throw std::bad_alloc();return n;
}
static int xmlcmd(ClientData data,Tcl_Interp*ip,int objc,Tcl_Obj *const objv[]){
    auto&o=*static_cast<Owner*>(data);
    try {
        if(objc<2)throw std::runtime_error("xml operation ?document? ?arguments?");
        string op=Tcl_GetString(objv[1]);auto arg=[&](int n)->string{if(n>=objc)throw std::runtime_error("Missing XML argument");return utf8(objv[n]);};
        if(op=="create"||op=="parse") {
            if(objc!=3)throw std::runtime_error("create/parse requires root name or XML text");
            string input=arg(2);xmlDoc*raw=nullptr;
            if(op=="parse") {
                if(input.size()>4194304)throw std::runtime_error("XML parse limit is 4 MiB");
                xmlParserCtxt*ctxt=xmlNewParserCtxt();if(!ctxt)throw std::bad_alloc();
                // These documents are editable. libxml2 explicitly forbids
                // modifying trees parsed with XML_PARSE_COMPACT.
                raw=xmlCtxtReadMemory(ctxt,input.data(),(int)input.size(),nullptr,"UTF-8",XML_PARSE_NONET|XML_PARSE_NOERROR|XML_PARSE_NOWARNING);
                if(!raw){const xmlError*e=xmlCtxtGetLastError(ctxt);string message="XML parse error at line "+std::to_string(e?e->line:0)+" column "+std::to_string(e?e->int2:0)+": "+(e&&e->message?e->message:"Invalid XML");xmlFreeParserCtxt(ctxt);throw std::runtime_error(message);}
                xmlFreeParserCtxt(ctxt);
            } else {if(xmlValidateName(BAD_CAST input.c_str(),0)||input.find(':')!=string::npos)throw std::runtime_error("Root must be an unqualified XML name; declare namespaces explicitly");raw=xmlNewDoc(BAD_CAST "1.0");xmlDocSetRootElement(raw,xmlNewNode(nullptr,BAD_CAST input.c_str()));}
            std::unique_ptr<Doc>d(new Doc(raw));
            if(raw->intSubset||raw->extSubset)throw std::runtime_error("XML DTD/entity declarations are forbidden");
            unsigned count=0;budget(xmlDocGetRootElement(raw),0,count);
            if(o.docs.size()>=64)throw std::runtime_error("Release an XML document before allocating more than 64");
            string id="doc"+std::to_string(++o.next);o.docs[id]=std::move(d);Tcl_SetObjResult(ip,str(id));return TCL_OK;
        }
        string id=arg(2);auto it=o.docs.find(id);if(it==o.docs.end())throw std::runtime_error("Unknown or released XML document");Doc&d=*it->second;
        Tcl_Obj*result=Tcl_NewObj();
        if(op=="release"){if(objc!=3)throw std::runtime_error("release requires document only");o.docs.erase(it);}
        else if(op=="root"){result=str(d.handle(xmlDocGetRootElement(d.doc)));}
        else if(op=="serialize"){
            xmlChar*bytes=nullptr;int n=0;xmlDocDumpFormatMemoryEnc(d.doc,&bytes,&n,"UTF-8",objc>3&&arg(3)=="1");
            if(n>8388608){xmlFree(bytes);throw std::runtime_error("XML serialization exceeds 8 MiB");}result=str(string((const char*)bytes,n));xmlFree(bytes);
        } else {
            xmlNode*n=d.node(arg(3));
            if(op=="describe"){
                result=Tcl_NewDictObj();put(ip,result,"id",str(arg(3)));put(ip,result,"name",str((const char*)n->name));
                put(ip,result,"namespace",str(n->ns&&n->ns->href?(const char*)n->ns->href:""));put(ip,result,"prefix",str(n->ns&&n->ns->prefix?(const char*)n->ns->prefix:""));
                xmlChar*t=xmlNodeGetContent(n);put(ip,result,"text",str(t?(const char*)t:""));xmlFree(t);
                Tcl_Obj*children=Tcl_NewListObj(0,nullptr),*attrs=Tcl_NewDictObj();for(xmlNode*c=n->children;c;c=c->next)add(ip,children,str(d.handle(c)));
                // Only elements have an attribute list. Compact parsed text
                // may use this storage for content; never walk it as xmlAttr.
                for(xmlAttr*a=n->type==XML_ELEMENT_NODE?n->properties:nullptr;a;a=a->next){xmlChar*v=xmlNodeListGetString(d.doc,a->children,1);string key=a->ns&&a->ns->prefix?string((const char*)a->ns->prefix)+":"+(const char*)a->name:(const char*)a->name;Tcl_DictObjPut(ip,attrs,str(key),str(v?(const char*)v:""));xmlFree(v);}
                put(ip,result,"children",children);put(ip,result,"attributes",attrs);put(ip,result,"node_type",Tcl_NewIntObj(n->type));
            } else if(op=="append"||op=="insert"){
                xmlNode*parent=op=="append"?n:n->parent;if(!parent||parent->type!=XML_ELEMENT_NODE)throw std::runtime_error("XML element parent required");
                xmlNode*c=named(d,parent,arg(4));if(objc>5){xmlNode*t=xmlNewText(BAD_CAST arg(5).c_str());xmlAddChild(c,t);}
                if(op=="append")xmlAddChild(n,c);else xmlAddPrevSibling(n,c);unsigned count=0;
                try {budget(xmlDocGetRootElement(d.doc),0,count);}catch(...){xmlUnlinkNode(c);xmlFreeNode(c);throw;}
                result=str(d.handle(c));
            } else if(op=="text"){
                if(objc==4){xmlChar*t=xmlNodeGetContent(n);result=str(t?(const char*)t:"");xmlFree(t);}else{
                    string value=arg(4);if(value.size()>4194304)throw std::runtime_error("XML text exceeds 4 MiB");
                    for(xmlNode*c=n->children;c;c=c->next)d.invalidate(c);
                    xmlNodeSetContent(n,nullptr);xmlAddChild(n,xmlNewText(BAD_CAST value.c_str()));
                }
            } else if(op=="add_text"){
                string value=arg(4);if(value.size()>4194304)throw std::runtime_error("XML text exceeds 4 MiB");xmlNode*c=xmlNewText(BAD_CAST value.c_str());xmlNode*actual=xmlAddChild(n,c);result=str(d.handle(actual));
            } else if(op=="attribute"){
                string key=arg(4);if(xmlValidateQName(BAD_CAST key.c_str(),0))throw std::runtime_error("Invalid XML attribute name");
                if(key=="xmlns"||key.rfind("xmlns:",0)==0){if(objc!=6)throw std::runtime_error("Namespace declarations require a URI");string prefix=key=="xmlns"?"":key.substr(6);if(xmlSearchNs(d.doc,n,prefix.empty()?nullptr:BAD_CAST prefix.c_str()))throw std::runtime_error("Namespace prefix already declared");xmlNs*ns=xmlNewNs(n,BAD_CAST arg(5).c_str(),prefix.empty()?nullptr:BAD_CAST prefix.c_str());if(prefix.empty())xmlSetNs(n,ns);}
                else{
                    xmlNs*ns=nullptr;string local=key;auto colon=key.find(':');if(colon!=string::npos){string prefix=key.substr(0,colon);local=key.substr(colon+1);ns=xmlSearchNs(d.doc,n,BAD_CAST prefix.c_str());if(!ns)throw std::runtime_error("Undeclared attribute namespace prefix");}
                    if(objc==5){xmlChar*v=xmlGetNsProp(n,BAD_CAST local.c_str(),ns?ns->href:nullptr);result=str(v?(const char*)v:"");xmlFree(v);}
                    else if(arg(5)=="--remove"){if(ns)xmlUnsetNsProp(n,ns,BAD_CAST local.c_str());else xmlUnsetProp(n,BAD_CAST local.c_str());}
                    else {string value=arg(5);if(value.size()>1048576)throw std::runtime_error("XML attribute exceeds 1 MiB");xmlSetNsProp(n,ns,BAD_CAST local.c_str(),BAD_CAST value.c_str());}
                }
            } else if(op=="remove"){
                if(n==xmlDocGetRootElement(d.doc))throw std::runtime_error("Cannot remove document root");
                d.invalidate(n);xmlUnlinkNode(n);xmlFreeNode(n);
            } else if(op=="move"){
                xmlNode*parent=d.node(arg(4));
                if(n==xmlDocGetRootElement(d.doc)||parent->type!=XML_ELEMENT_NODE)throw std::runtime_error("Invalid move destination");
                unsigned depth=0;
                for(xmlNode*p=parent;p;p=p->parent){
                    if(p==n)throw std::runtime_error("XML move would create a cycle");
                    if(p->parent&&p->parent->type!=XML_DOCUMENT_NODE)++depth;
                }
                // Moving within this document cannot increase its node count.
                // Check the new subtree depth before libxml2 can merge/free text:
                // rollback through the original pointer would then be unsafe.
                if(depth+1>64)throw std::runtime_error("XML depth exceeds 64");
                unsigned count=1;budget(n->children,depth+2,count);
                xmlNode*old=n->parent,*next=n->next;
                xmlUnlinkNode(n);
                xmlNode*actual=xmlAddChild(parent,n);
                if(!actual){
                    if(next)xmlAddPrevSibling(next,n);else xmlAddChild(old,n);
                    throw std::runtime_error("Unable to attach XML node");
                }
                // xmlAddChild consumes a text node when it joins existing text.
                // Remove its opaque handle without dereferencing the freed node.
                if(actual!=n)d.nodes.erase(arg(3));
                if(actual->type==XML_ELEMENT_NODE)xmlReconciliateNs(d.doc,actual);
            } else if(op=="query"){
                string name=arg(4);result=Tcl_NewListObj(0,nullptr);std::vector<xmlNode*> todo{n};while(!todo.empty()){xmlNode*x=todo.back();todo.pop_back();if(x->type==XML_ELEMENT_NODE&&(name=="*"||name==(const char*)x->name))add(ip,result,str(d.handle(x)));std::vector<xmlNode*> children;for(xmlNode*c=x->children;c;c=c->next)children.push_back(c);for(auto c=children.rbegin();c!=children.rend();++c)todo.push_back(*c);}
            } else throw std::runtime_error("Unknown public XML operation");
        }
        Tcl_SetObjResult(ip,result);return TCL_OK;
    }catch(const std::exception&e){Tcl_SetErrorCode(ip,"GXTXT","XML","INVALID",nullptr);Tcl_SetObjResult(ip,str(e.what()));return TCL_ERROR;}
}
static int rendercmd(ClientData,Tcl_Interp*ip,int objc,Tcl_Obj *const objv[]){if(objc!=3){Tcl_WrongNumArgs(ip,1,objv,"html|xml source");return TCL_ERROR;}string source=utf8(objv[2]);int len=(int)source.size();const char*s=source.data();string kind=Tcl_GetString(objv[1]);if(kind!="html"&&kind!="xml"){Tcl_SetObjResult(ip,str("Renderer must be html or xml"));return TCL_ERROR;}return GXDocumentRender(ip,s,len,kind=="html");}
// UTF-8 byte offsets are mapped once to Unicode/Tk character coordinates.
static int scancmd(ClientData,Tcl_Interp*ip,int objc,Tcl_Obj *const objv[]){
    if(objc!=3){Tcl_WrongNumArgs(ip,1,objv,"language source");return TCL_ERROR;}
    string lang=Tcl_GetString(objv[1]);string s=utf8(objv[2]);int length=(int)s.size();
    if(s.size()>4194304){Tcl_SetObjResult(ip,str("Source model exceeds 4 MiB; open a bounded excerpt"));return TCL_ERROR;}
    std::vector<int> chars(s.size()+1),lines(s.size()+1),cols(s.size()+1);int ch=0,line=1,col=0;
    for(size_t i=0;i<s.size();){unsigned char c=s[i];size_t n=c<128?1:(c<224?2:(c<240?3:4));n=std::min(n,s.size()-i);for(size_t k=0;k<n;k++){chars[i+k]=ch;lines[i+k]=line;cols[i+k]=col;}i+=n;ch+=(n==4?2:1);if(c=='\n'){line++;col=0;}else col+=(n==4?2:1);chars[i]=ch;lines[i]=line;cols[i]=col;}
    Tcl_Obj*result=Tcl_NewDictObj(),*tokens=Tcl_NewListObj(0,nullptr),*folds=Tcl_NewListObj(0,nullptr);unsigned count=0;
    const std::set<string> keys={"def","async","await","class","if","elif","else","for","while","try","except","finally","with","as","return","yield","raise","pass","break","continue","import","from","global","nonlocal","lambda","and","or","not","in","is","del","assert","function","endfunction","endif","endfor","endwhile","switch","case","otherwise","endswitch","catch","end_try_catch","end","classdef","properties","methods","endclassdef","sub","my","use","package","proc","namespace","foreach","then","elseif","set","variable","public","private","protected","int","void","char","double","float","const","struct","typedef","enum","static","extern","include","define","do","select","program","module","implicit","none","contains","call","enddo","endprogram","endselect","endclass","endmethods","endproperties"};
    const std::set<string> builtins={"print","len","range","str","dict","list","set","tuple","int","float","bool","sum","min","max","enumerate","zip","open","isinstance","super","self","disp","printf","fprintf","size","length","zeros","ones","sin","cos","sqrt","plot","puts","format","expr","lindex","lappend","array","string"};
    auto emit=[&](const char*kind,size_t a,size_t b){if(++count>200000)return;Tcl_Obj*t=Tcl_NewDictObj();put(ip,t,"category",str(kind));put(ip,t,"start",Tcl_NewIntObj(chars[a]));put(ip,t,"end",Tcl_NewIntObj(chars[b]));put(ip,t,"line",Tcl_NewIntObj(lines[a]));put(ip,t,"column",Tcl_NewIntObj(cols[a]));put(ip,t,"end_line",Tcl_NewIntObj(lines[b]));put(ip,t,"end_column",Tcl_NewIntObj(cols[b]));put(ip,t,"byte_start",Tcl_NewWideIntObj(a));put(ip,t,"byte_end",Tcl_NewWideIntObj(b));add(ip,tokens,t);};
    auto starts=[&](size_t i,const char*x){return s.compare(i,strlen(x),x)==0;};
    bool octave=lang=="octave"||lang=="matlab"||lang=="matlab-octave";bool python=lang=="python";bool markup=lang=="xml"||lang=="html";bool cstyle=lang=="c"||lang=="cpp"||lang=="javascript";bool tex=lang=="tex"||lang=="latex";
    bool definition=false,inTag=false;int grouping=0;size_t definition_target=string::npos;std::vector<std::pair<int,int>> structure;
    for(size_t i=0;i<s.size()&&count<200000;){size_t a=i;unsigned char c=s[i];
        if(tex) {
            // Lexical presentation only: TeX expansion and math remain the
            // configured compiler's authority. Quotes are ordinary prose.
            if(c=='%'){auto e=s.find('\n',i);i=e==string::npos?s.size():e;emit("comment",a,i);continue;}
            if(c=='\\') {
                i++;
                if(i<s.size()&&std::isalpha(static_cast<unsigned char>(s[i]))) {
                    while(i<s.size()&&std::isalpha(static_cast<unsigned char>(s[i])))i++;
                    string command=s.substr(a+1,i-a-1);
                    if(i<s.size()&&s[i]=='*')i++;
                    if(command=="verb"&&i<s.size()&&s[i]!='\n'&&s[i]!='\r') {
                        char delimiter=s[i++];while(i<s.size()&&s[i]!=delimiter&&s[i]!='\n'&&s[i]!='\r')i++;
                        if(i<s.size()&&s[i]==delimiter)i++;
                        emit("string",a,i);continue;
                    }
                    if(command=="begin") {
                        for(const char*environment:{"verbatim","verbatim*","lstlisting"}) {
                            string begin="{"+string(environment)+"}";
                            if(s.compare(i,begin.size(),begin)==0) {
                                string end="\\end{"+string(environment)+"}";
                                auto last=s.find(end,i+begin.size());i=last==string::npos?s.size():last+end.size();
                                emit("string",a,i);break;
                            }
                        }
                        if(i>a+command.size()+2)continue;
                    }
                    emit("keyword",a,i);
                } else {if(i<s.size())i++;emit("escape",a,i);}
                continue;
            }
            if(c=='$'){i++;if(i<s.size()&&s[i]=='$')i++;emit("constant",a,i);continue;}
            if(c=='{'||c=='}'){i++;emit("tag",a,i);continue;}
            if(c=='^'||c=='_'){i++;emit("attribute",a,i);continue;}
            i++;continue;
        }
        if(markup&&starts(i,"<!--")){auto e=s.find("-->",i+4);i=e==string::npos?s.size():e+3;emit("comment",a,i);continue;}
        if((cstyle&&starts(i,"/*"))||(octave&&starts(i,"%{"))){const char*end=octave?"%}":"*/";auto e=s.find(end,i+2);i=e==string::npos?s.size():e+2;emit("comment",a,i);continue;}
        bool comment=(cstyle&&starts(i,"//"))||((python||lang=="perl"||lang=="tcl"||lang=="tk")&&c=='#')||(octave&&(c=='%'||c=='#'))||(lang=="fortran"&&c=='!');
        if(comment){auto e=s.find('\n',i);i=e==string::npos?s.size():e;emit("comment",a,i);continue;}
        if(lang=="cpp") {
            size_t raw=string::npos;
            for(const char*prefix:{"R\"","u8R\"","uR\"","UR\"","LR\""}) {
                if(starts(i,prefix)){raw=i+strlen(prefix);break;}
            }
            if(raw!=string::npos) {
                auto open=s.find('(',raw);
                if(open!=string::npos&&open-raw<=16&&s.substr(raw,open-raw).find_first_of(" ()\\\t\r\n")==string::npos) {
                    string end=")"+s.substr(raw,open-raw)+"\"";
                    auto close=s.find(end,open+1);i=close==string::npos?s.size():close+end.size();emit("string",a,i);continue;
                }
            }
        }
        bool transpose=octave&&c=='\''&&i>0&&(isalnum((unsigned char)s[i-1])||s[i-1]==')'||s[i-1]==']'||s[i-1]=='.');
        if((c=='\''||c=='"'||(lang=="javascript"&&c=='`'))&&!transpose){char q=c;bool triple=python&&i+2<s.size()&&s[i+1]==q&&s[i+2]==q;i+=triple?3:1;while(i<s.size()){
            if(s[i]=='\\'){size_t e=std::min(s.size(),i+2);emit("escape",i,e);i=e;continue;}
            if(s[i]==q){if(triple){if(i+2<s.size()&&s[i+1]==q&&s[i+2]==q){i+=3;break;}}else {if(octave&&i+1<s.size()&&s[i+1]==q){i+=2;continue;}i++;break;}}
            if(!triple&&q!='`'&&s[i]=='\n'&&!octave)break;
            i++;
        }emit("string",a,i);continue;}
        if(markup&&c=='<'){inTag=true;i++;emit("tag",a,i);continue;}if(markup&&c=='>'){inTag=false;i++;emit("tag",a,i);continue;}
        if(isdigit(c)&&(i==0||!isalnum((unsigned char)s[i-1]))){i++;while(i<s.size()&&(isalnum((unsigned char)s[i])||s[i]=='.'||s[i]=='_'))i++;emit("number",a,i);continue;}
        if(isalpha(c)||c=='_'||c>=128){i++;while(i<s.size()&&(isalnum((unsigned char)s[i])||s[i]=='_'||(unsigned char)s[i]>=128))i++;string word=s.substr(a,i-a);string lower=word;if(lang=="fortran")std::transform(lower.begin(),lower.end(),lower.begin(),[](unsigned char x){return std::tolower(x);});
            const char*kind=(definition||a==definition_target)?"definition":(keys.count(lower)?"keyword":(builtins.count(lower)?"builtin":((word=="True"||word=="False"||word=="None"||word=="true"||word=="false"||word=="null")?"constant":"identifier")));
            if(word.rfind("gxtxt",0)==0||word=="GX")kind="bridge";
            if(markup&&inTag)kind=(a>0&&s[a-1]=='<')?"tag":"attribute";
            if(python&&a>0&&s[a-1]=='@')kind="decorator";
            emit(kind,a,i);definition=(lower=="def"||lower=="class"||lower=="proc"||lower=="sub");
            if(octave&&lower=="function"){
                size_t e=s.find('\n',i),equals=s.find('=',i),at=(equals!=string::npos&&(e==string::npos||equals<e))?equals+1:i;
                while(at<s.size()&&isspace((unsigned char)s[at]))at++;
                definition_target=at;
            }
            if(octave){static const std::set<string> opens={"function","classdef","if","for","while","switch","try","unwind_protect","methods","properties","parfor"};if(grouping==0&&opens.count(lower))structure.emplace_back(lines[a],cols[a]);else if(grouping==0&&(lower=="end"||lower.rfind("end",0)==0)){if(!structure.empty()){auto top=structure.back();structure.pop_back();if(lines[a]>top.first){Tcl_Obj*f=Tcl_NewListObj(0,nullptr);add(ip,f,Tcl_NewIntObj(top.first));add(ip,f,Tcl_NewIntObj(lines[a]));add(ip,folds,f);}}}}
            continue;
        }
        if(c=='('||c=='[')grouping++;else if((c==')'||c==']')&&grouping>0)grouping--;
        if(lang=="c"||lang=="cpp") {
            if(c=='{')structure.emplace_back(lines[a],cols[a]);
            else if(c=='}'&&!structure.empty()) {
                auto top=structure.back();structure.pop_back();
                if(lines[a]>top.first){Tcl_Obj*f=Tcl_NewListObj(0,nullptr);add(ip,f,Tcl_NewIntObj(top.first));add(ip,f,Tcl_NewIntObj(lines[a]));add(ip,folds,f);}
            }
        }
        i++;
    }
    put(ip,result,"tokens",tokens);put(ip,result,"folds",folds);put(ip,result,"line_count",Tcl_NewIntObj(line));put(ip,result,"characters",Tcl_NewIntObj(ch));put(ip,result,"bytes",Tcl_NewIntObj(length));put(ip,result,"truncated",Tcl_NewBooleanObj(count>=200000));put(ip,result,"engine",str("gxtxt.native_source.v1"));Tcl_SetObjResult(ip,result);return TCL_OK;
}
extern "C" int Gxtxtdocument_Init(Tcl_Interp*ip){if(!Tcl_InitStubs(ip,"8.6",0))return TCL_ERROR;Tcl_CreateNamespace(ip,"::GX::NativeDocument",nullptr,nullptr);auto*owner=new Owner;Tcl_SetAssocData(ip,"gxtxt.document.v1",dispose,owner);Tcl_CreateObjCommand(ip,"::GX::NativeDocument::xml",xmlcmd,owner,nullptr);Tcl_CreateObjCommand(ip,"::GX::NativeDocument::render",rendercmd,nullptr,nullptr);Tcl_CreateObjCommand(ip,"::GX::NativeDocument::scan",scancmd,nullptr,nullptr);GXDocumentSourceCaptureInit(ip);return Tcl_PkgProvide(ip,"gxtxt_document","1.0");}
