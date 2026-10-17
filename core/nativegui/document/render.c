/* Bounded inert presentation model. No Tk, filesystem, network or script engine.
 * SPDX-License-Identifier: GPL-3.0-or-later */
#include "render.h"
#include <libxml/HTMLparser.h>
#include <libxml/parser.h>
#include <libxml/tree.h>
#include <string.h>
#include <ctype.h>
typedef struct {Tcl_Interp *ip; Tcl_Obj *runs; unsigned nodes; int html; int failed;} Render;
static void run(Render *r,const char *tag,const char *s,int len) {
    if(r->failed||!s||!len)return;
    Tcl_Obj *pair=Tcl_NewListObj(0,NULL);
    Tcl_ListObjAppendElement(r->ip,pair,Tcl_NewStringObj(tag,-1));
    Tcl_DString converted;Tcl_Encoding encoding=Tcl_GetEncoding(r->ip,"utf-8");
    Tcl_ExternalToUtfDString(encoding,s,len,&converted);
    Tcl_ListObjAppendElement(r->ip,pair,Tcl_NewStringObj(Tcl_DStringValue(&converted),Tcl_DStringLength(&converted)));
    Tcl_DStringFree(&converted);Tcl_FreeEncoding(encoding);
    Tcl_ListObjAppendElement(r->ip,r->runs,pair);
}
static int block(const char *n) {return !strcmp(n,"p")||!strcmp(n,"div")||!strcmp(n,"section")||!strcmp(n,"blockquote")||!strcmp(n,"tr")||!strcmp(n,"ul")||!strcmp(n,"ol")||!strcmp(n,"table")||!strcmp(n,"article");}
static void walk(Render *r,xmlNode *node,unsigned depth,const char *style,int pre) {
    if(depth>64){r->failed=1;return;}
    for(xmlNode *n=node;n;n=n->next) {
        if(++r->nodes>50000){r->failed=1;return;}
        if(n->type==XML_TEXT_NODE||n->type==XML_CDATA_SECTION_NODE) {
            const char *s=(const char *)n->content;if(!s)continue;
            if(pre||!r->html)run(r,style,s,(int)strlen(s));
            else {
                Tcl_DString out;Tcl_DStringInit(&out);int space=0;
                for(const unsigned char *p=(const unsigned char *)s;*p;p++) {
                    if(*p<128&&isspace(*p)){if(!space)Tcl_DStringAppend(&out," ",1);space=1;}
                    else {Tcl_DStringAppend(&out,(const char *)p,1);space=0;}
                }
                run(r,style,Tcl_DStringValue(&out),Tcl_DStringLength(&out));Tcl_DStringFree(&out);
            }
            continue;
        }
        if(!r->html && n->type==XML_COMMENT_NODE){run(r,"comment","<!--",-1);run(r,"comment",(const char*)n->content,-1);run(r,"comment","-->\n",-1);continue;}
        if(n->type!=XML_ELEMENT_NODE)continue;
        const char *name=(const char *)n->name;
        if(r->html) {
            if(!strcmp(name,"script")||!strcmp(name,"style")||!strcmp(name,"iframe")||!strcmp(name,"object")||!strcmp(name,"head"))continue;
            const char *tag=style;
            if(name[0]=='h'&&name[1]>='1'&&name[1]<='6'&&!name[2]){tag="heading";run(r,"body","\n",1);}
            else if(!strcmp(name,"strong")||!strcmp(name,"b")||!strcmp(name,"th"))tag="bold";
            else if(!strcmp(name,"em")||!strcmp(name,"i"))tag="italic";
            else if(!strcmp(name,"pre")||!strcmp(name,"code"))tag="code";
            else if(!strcmp(name,"a"))tag="link";
            if(block(name))run(r,"body","\n",1);
            if(!strcmp(name,"br"))run(r,"body","\n",1);
            if(!strcmp(name,"li"))run(r,"body","\n• ",-1);
            if(!strcmp(name,"img")){xmlChar *alt=xmlGetProp(n,BAD_CAST "alt");run(r,"body","[image omitted] ",-1);if(alt){run(r,"body",(const char*)alt,-1);xmlFree(alt);}}
            walk(r,n->children,depth+1,tag,pre||!strcmp(name,"pre"));
            if(!strcmp(name,"td")||!strcmp(name,"th"))run(r,"body","\t",1);
            if(!strcmp(name,"li")||block(name)||!strcmp(tag,"heading"))run(r,"body","\n",1);
        } else {
            for(unsigned i=0;i<depth;i++)run(r,"body","  ",2);
            run(r,"tag","<",1);
            if(n->ns&&n->ns->prefix){run(r,"tag",(const char*)n->ns->prefix,-1);run(r,"tag",":",1);}
            run(r,"tag",name,-1);
            for(xmlNs *ns=n->nsDef;ns;ns=ns->next){run(r,"attribute"," xmlns",-1);if(ns->prefix){run(r,"attribute",":",1);run(r,"attribute",(const char*)ns->prefix,-1);}run(r,"attribute","=\"",-1);run(r,"string",(const char*)ns->href,-1);run(r,"attribute","\"",1);}
            for(xmlAttr *a=n->properties;a;a=a->next) {
                run(r,"attribute"," ",1);if(a->ns&&a->ns->prefix){run(r,"attribute",(const char*)a->ns->prefix,-1);run(r,"attribute",":",1);}run(r,"attribute",(const char*)a->name,-1);
                run(r,"attribute","=\"",-1);xmlChar *v=xmlNodeListGetString(n->doc,a->children,1);xmlChar *escaped=xmlEncodeSpecialChars(n->doc,v);if(escaped){run(r,"string",(const char*)escaped,-1);xmlFree(escaped);}xmlFree(v);run(r,"attribute","\"",1);
            }
            if(!n->children){run(r,"tag","/>\n",-1);continue;}
            run(r,"tag",">",1);
            int nested=0;for(xmlNode *c=n->children;c;c=c->next)if(c->type==XML_ELEMENT_NODE)nested=1;
            if(nested)run(r,"body","\n",1);
            walk(r,n->children,depth+1,"body",1);
            if(nested)for(unsigned i=0;i<depth;i++)run(r,"body","  ",2);
            run(r,"tag","</",2);if(n->ns&&n->ns->prefix){run(r,"tag",(const char*)n->ns->prefix,-1);run(r,"tag",":",1);}run(r,"tag",name,-1);run(r,"tag",">\n",2);
        }
    }
}
int GXDocumentRender(Tcl_Interp *ip,const char *source,int len,int html) {
    if(len>4194304){Tcl_SetObjResult(ip,Tcl_NewStringObj("Document exceeds the 4 MiB rendering limit",-1));return TCL_ERROR;}
    xmlDoc *doc=NULL;xmlParserCtxt *ctxt=NULL;
    if(html)doc=htmlReadMemory(source,len,NULL,"UTF-8",HTML_PARSE_NONET|HTML_PARSE_NOERROR|HTML_PARSE_NOWARNING|HTML_PARSE_COMPACT);
    else {ctxt=xmlNewParserCtxt();if(ctxt)doc=xmlCtxtReadMemory(ctxt,source,len,NULL,"UTF-8",XML_PARSE_NONET|XML_PARSE_NOERROR|XML_PARSE_NOWARNING|XML_PARSE_COMPACT);}
    if(!doc){const xmlError *e=ctxt?xmlCtxtGetLastError(ctxt):NULL;Tcl_SetObjResult(ip,Tcl_ObjPrintf("%s parse error at line %d column %d: %s",html?"HTML":"XML",e?e->line:0,e?e->int2:0,e&&e->message?e->message:"Invalid document"));if(ctxt)xmlFreeParserCtxt(ctxt);return TCL_ERROR;}
    if(!html&&(doc->intSubset||doc->extSubset)){xmlFreeDoc(doc);if(ctxt)xmlFreeParserCtxt(ctxt);Tcl_SetObjResult(ip,Tcl_NewStringObj("XML DTD/entity declarations are forbidden",-1));return TCL_ERROR;}
    Render r={ip,Tcl_NewListObj(0,NULL),0,html,0};Tcl_IncrRefCount(r.runs);
    walk(&r,xmlDocGetRootElement(doc),0,"body",0);xmlFreeDoc(doc);if(ctxt)xmlFreeParserCtxt(ctxt);
    if(r.failed){Tcl_SetObjResult(ip,Tcl_NewStringObj("Document exceeds 64 nesting levels or 50000 nodes",-1));Tcl_DecrRefCount(r.runs);return TCL_ERROR;}
    Tcl_SetObjResult(ip,r.runs);Tcl_DecrRefCount(r.runs);return TCL_OK;
}
