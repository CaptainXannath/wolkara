#include "GuestHTTPTrace.h"
#include <ctype.h>
#include <inttypes.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

enum { FIRST, HEADERS, BODY, CHUNK_SIZE, CHUNK_DATA, CHUNK_CRLF, TRAILERS, STOP, CLOSE_BODY };
static bool equal(const char *a, const char *b) {
    while (*a && *b) if (tolower((unsigned char)*a++)!=tolower((unsigned char)*b++)) return false;
    return !*a && !*b;
}
static bool safe_host(const char *host, size_t length) {
    if (!length || length>=256) return false;
    size_t end=0;
    while(end<length && host[end]!=':')end++;
    if(!end || end>253)return false;
    size_t label=0;
    for(size_t i=0;i<end;i++) {
        unsigned char c=(unsigned char)host[i];
        if(c=='.') {
            if(!label || host[i-1]=='-')return false;
            label=0;
        } else {
            bool alphanumeric=(c>='a' && c<='z') || (c>='A' && c<='Z') || (c>='0' && c<='9');
            if((!alphanumeric && c!='-') || (!label && c=='-') || ++label>63)return false;
        }
    }
    if(!label || host[end-1]=='-')return false;
    if(end<length) {
        unsigned port=0;
        if(end+1==length)return false;
        for(size_t i=end+1;i<length;i++) {
            unsigned char c=(unsigned char)host[i];
            if(c<'0' || c>'9')return false;
            port=port*10+(unsigned)(c-'0');
            if(port>65535)return false;
        }
        if(!port)return false;
    }
    return true;
}
static bool public_host(const char *host) {
    char domain[256];size_t n=strcspn(host,":");
    if(n>=sizeof domain)return false;
    for(size_t i=0;i<n;i++)domain[i]=(char)tolower((unsigned char)host[i]);
    domain[n]=0;
    static const char *suffixes[]={".blizzard.com",".battle.net",".akamaihd.net",".edgesuite.net",".battle.net.cn",".battlenet.com.cn"};
    for(size_t i=0;i<sizeof suffixes/sizeof suffixes[0];i++) {
        size_t size=strlen(suffixes[i]);
        if(n>size && !strcmp(domain+n-size,suffixes[i]))return true;
    }
    return false;
}
static bool hexpart(const char *p,size_t length) {
    for (size_t i=0;i<length;i++) if (!isxdigit((unsigned char)p[i])) return false;
    return true;
}
static bool public_path(const char *path) {
    if (strncmp(path,"/tpr/wow/",9)) return false;
    const char *p=path+9;
    if (!strncmp(p,"data/",5)) p+=5;
    else if (!strncmp(p,"patch/",6)) p+=6;
    else if (!strncmp(p,"config/",7)) p+=7;
    else return false;
    size_t length=strlen(p);
    if (length!=38 && length!=44) return false;
    return p[2]=='/' && p[5]=='/' && hexpart(p,2) && hexpart(p+3,2) &&
        hexpart(p+6,32) && !strncmp(p,p+6,2) && !strncmp(p+3,p+8,2) &&
        (length==38 || !strcmp(p+38,".index"));
}
void gh_http_url(const char *target,const char *peer,bool tls,char *out,size_t size) {
    if (!size) return;
    char host[256]="[unavailable]",path[512]="[redacted-path]";
    const char *at=target?target:"",*scheme=tls?"https":"http";
    if (peer && safe_host(peer,strlen(peer)) && public_host(peer)) snprintf(host,sizeof host,"%s",peer);
    if (!strncmp(at,"https://",8) || !strncmp(at,"http://",7)) {
        bool secure=at[4]=='s';scheme=secure?"https":"http";at+=secure?8:7;
        const char *end=at+strcspn(at,"/?#"),*authority=at;
        for (const char *p=at;p<end;p++) if (*p=='@') authority=p+1;
        if (safe_host(authority,(size_t)(end-authority))) {
            memcpy(host,authority,(size_t)(end-authority));host[end-authority]=0;
            if(!public_host(host))snprintf(host,sizeof host,"[redacted-host]");
        } else snprintf(host,sizeof host,"[redacted-host]");
        at=end;
    }
    size_t n=strcspn(at,"?#");
    if (n<sizeof path) {
        char candidate[512];memcpy(candidate,at,n);candidate[n]=0;
        if (public_path(candidate)) snprintf(path,sizeof path,"%s",candidate);
    }
    snprintf(out,size,"%s://%s%s%s%s",scheme,host,path[0]=='/'?"":"/",path,
        at[n]?"?[redacted]":"");
}
void gh_http_init(GHTTPTrace *trace,uint64_t id,bool tls) {
    memset(trace,0,sizeof *trace);trace->id=id;trace->tls=tls;
}
void gh_http_observe_object(GHTTPTrace *trace,GHTTPObjectObserve observe,void *context) {
    trace->observe=observe;trace->observe_context=context;
}
void gh_http_peer(GHTTPTrace *trace,const char *peer,size_t length) {
    if (peer && safe_host(peer,length)) {
        memcpy(trace->peer,peer,length);trace->peer[length]=0;
        if(!public_host(trace->peer))snprintf(trace->peer,sizeof trace->peer,"[redacted-host]");
    } else snprintf(trace->peer,sizeof trace->peer,"[redacted-host]");
}
static void output(GHTTPTrace *trace,const char *line,GHTTPEmit emit,void *context) {
    if (emit && trace->reports<128) {trace->reports++;emit(line,context);}
}
static void reset_stream(GHTTPStream *stream) { memset(stream,0,sizeof *stream); }
static GHTTPPending *active(GHTTPTrace *trace) {
    return trace->queue_count?&trace->queue[trace->queue_start]:NULL;
}
static void object_event(GHTTPTrace *trace,const GHTTPPending *request,const GHTTPStream *stream,
                         GHTTPObjectKind kind,const char *reason,const void *bytes,size_t length,
                         int code,int error_number) {
    if (!trace->observe || (kind!=GHTTP_OBJECT_UNSUPPORTED && (!request || !request->target_object))) return;
    GHTTPObjectEvent event={.kind=kind,.connection=trace->id,.request=request?request->id:0,
        .declared_length=stream?stream->declared_length:0,.total=stream?stream->object_received:0,
        .status=stream?stream->status:0,.code=code,.error_number=error_number,
        .has_length=stream && stream->has_length,.eligible=stream && stream->capture,
        .method=request?request->method:NULL,.url=request?request->url:NULL,
        .reason=reason,.bytes=bytes,.length=length};
    trace->observe(&event,trace->observe_context);
}
static void unsupported(GHTTPTrace *trace,const char *reason) {
    if (!trace->unsupported_notified) {
        trace->unsupported_notified=true;
        object_event(trace,active(trace),&trace->inbound,GHTTP_OBJECT_UNSUPPORTED,reason,NULL,0,0,0);
    }
}
static void stop_stream(GHTTPTrace *trace,GHTTPStream *stream,bool outbound,const char *reason) {
    GHTTPPending *request=active(trace);
    if (!outbound && request && request->target_object && !stream->object_terminal) {
        object_event(trace,request,stream,GHTTP_OBJECT_ABORT,reason,NULL,0,0,0);
        stream->object_terminal=true;
    } else if (outbound && stream->target_object && trace->object_requests<8) {
        GHTTPPending pending={.id=trace->next_request+1,.target_object=true};
        snprintf(pending.method,sizeof pending.method,"%s",stream->method);
        snprintf(pending.url,sizeof pending.url,"%s",stream->target);
        object_event(trace,&pending,stream,GHTTP_OBJECT_ABORT,reason,NULL,0,0,0);
    }
    stream->capture=false;stream->state=STOP;
    memset(stream->line,0,sizeof stream->line);stream->line_length=0;
    unsupported(trace,reason);
}
static bool exact_object_target(const char *target) {
    const char *path=target;
    if (!strncmp(path,"https://",8) || !strncmp(path,"http://",7)) {
        path+=path[4]=='s'?8:7;path+=strcspn(path,"/?#");
    }
    size_t n=strcspn(path,"?#");
    return n==sizeof(GHTTP_TACT_OBJECT_PATH)-1 && !memcmp(path,GHTTP_TACT_OBJECT_PATH,n);
}
static bool number(const char *value,uint64_t *result,unsigned base) {
    if (!*value) return false;
    uint64_t n=0;
    for (;*value;value++) {
        unsigned digit=(unsigned char)*value;
        if (digit>='0' && digit<='9') digit-='0';
        else if (base==16 && digit>='a' && digit<='f') digit=digit-'a'+10;
        else if (base==16 && digit>='A' && digit<='F') digit=digit-'A'+10;
        else return false;
        if (digit>=base || n>(UINT64_MAX-digit)/base) return false;
        n=n*base+digit;
    }
    *result=n;return true;
}
static bool first_line(GHTTPTrace *trace,GHTTPStream *s,bool outbound) {
    if (outbound) {
        char *space=strchr(s->line,' ');if (!space) return false;*space++=0;
        static const char *methods[]={"GET","HEAD","POST","PUT","DELETE","OPTIONS","PATCH","CONNECT","TRACE"};
        bool method=false;
        for(size_t i=0;i<sizeof methods/sizeof methods[0];i++) if (!strcmp(s->line,methods[i])) method=true;
        if (!method) return false;
        snprintf(s->method,sizeof s->method,"%s",s->line);s->head=!strcmp(s->method,"HEAD");
        s->get=!strcmp(s->method,"GET");
        char *version=strchr(space,' ');if (!version) return false;*version++=0;
        if (strcmp(version,"HTTP/1.1") && strcmp(version,"HTTP/1.0")) return false;
        s->target_object=exact_object_target(space);
        // Sanitize before retaining request metadata; credentials never persist.
        gh_http_url(space,trace->peer,trace->tls,s->target,sizeof s->target);
    } else {
        if (strncmp(s->line,"HTTP/1.1 ",9) && strncmp(s->line,"HTTP/1.0 ",9)) return false;
        if (strlen(s->line)<12 || s->line[9]<'1' || s->line[9]>'5' ||
            !isdigit((unsigned char)s->line[10]) || !isdigit((unsigned char)s->line[11]) ||
            (s->line[12] && s->line[12]!=' ')) return false;
        s->status=(unsigned)(s->line[9]-'0')*100+(unsigned)(s->line[10]-'0')*10+(unsigned)(s->line[11]-'0');
    }
    s->state=HEADERS;return true;
}
static bool header(GHTTPStream *s) {
    char *colon=strchr(s->line,':');if (!colon) return false;*colon++=0;
    while (*colon==' ' || *colon=='\t') colon++;
    char *end=colon+strlen(colon);while(end>colon && (end[-1]==' ' || end[-1]=='\t')) *--end=0;
    if (equal(s->line,"Content-Length")) {
        uint64_t length=0;
        if (!number(colon,&length,10) || (s->has_length && s->remaining!=length)) return false;
        s->remaining=length;s->declared_length=length;s->has_length=true;
    } else if (equal(s->line,"Transfer-Encoding")) {
        if (!equal(colon,"chunked")) return false;
        s->chunked=true;
    } else if (equal(s->line,"Content-Encoding")) {
        if (!equal(colon,"identity")) s->encoded_http_body=true;
    } else if (equal(s->line,"Host") && safe_host(colon,strlen(colon)) && public_host(colon)) {
        snprintf(s->host,sizeof s->host,"%s",colon);
    }
    return true;
}
static void complete_response(GHTTPTrace *trace,GHTTPStream *s) {
    if (s->status>=200 && trace->queue_count) {
        if (!s->object_terminal) {
            if (s->capture && s->object_received!=GHTTP_TACT_ENCODED_SIZE) {
                s->capture=false;
                object_event(trace,active(trace),s,GHTTP_OBJECT_ABORT,"encoded-size-mismatch",NULL,0,0,0);
            } else object_event(trace,active(trace),s,GHTTP_OBJECT_COMPLETE,
                s->capture?"entity-complete":"response-not-eligible",NULL,0,0,0);
        }
        trace->queue_start=(trace->queue_start+1)%8;trace->queue_count--;
    }
    reset_stream(s);
}
static void headers_done(GHTTPTrace *trace,GHTTPStream *s,bool outbound,GHTTPEmit emit,void *context) {
    char line[1024];
    if (outbound) {
        if (trace->queue_count==8) {
            stop_stream(trace,&trace->inbound,false,"request-queue-limit");
            stop_stream(trace,s,true,"request-queue-limit");return;
        }
        uint64_t request=++trace->next_request;
        unsigned tail=(trace->queue_start+trace->queue_count)%8;
        GHTTPPending *pending=&trace->queue[tail];memset(pending,0,sizeof *pending);
        pending->id=request;pending->head=s->head;pending->get=s->get;
        pending->target_object=s->target_object && trace->object_requests<8;
        if (pending->target_object)trace->object_requests++;
        trace->queue_count++;
        // A Host header supplies the authority for origin-form requests. Its
        // validated value replaces only the explicit unavailable placeholder.
        if (s->host[0] && strstr(s->target,"://[unavailable]")) {
            char *authority=strstr(s->target,"://");
            char *path=authority?strchr(authority+3,'/'):NULL;
            if (path) {
                char target[512];snprintf(target,sizeof target,"%s",path);
                snprintf(s->target,sizeof s->target,"%s://%s%s",trace->tls?"https":"http",s->host,target);
            }
        }
        snprintf(line,sizeof line,"[tact-http] connection=%" PRIu64 " request=%" PRIu64 " method=%s url=%s\n",trace->id,request,s->method,s->target);
        output(trace,line,emit,context);
        snprintf(pending->method,sizeof pending->method,"%s",s->method);
        snprintf(pending->url,sizeof pending->url,"%s",s->target);
        object_event(trace,pending,s,GHTTP_OBJECT_REQUEST,"request-observed",NULL,0,0,0);
    } else {
        GHTTPPending *pending=active(trace);
        uint64_t request=pending?pending->id:0;
        s->head=pending && pending->head;
        snprintf(line,sizeof line,"[tact-http] connection=%" PRIu64 " request=%" PRIu64 " status=%u\n",trace->id,request,s->status);
        output(trace,line,emit,context);
        if (s->status>=200 && pending && pending->target_object) {
            const char *reason="entity-candidate";
            s->capture=pending->get && s->status==200 && !s->encoded_http_body &&
                !(s->chunked && s->has_length) &&
                (!s->has_length || s->declared_length==GHTTP_TACT_ENCODED_SIZE);
            if (!pending->get)reason="non-get-request";
            else if(s->status!=200)reason="http-status";
            else if(s->encoded_http_body)reason="http-content-encoding";
            else if(s->chunked && s->has_length)reason="ambiguous-framing";
            else if(s->has_length && s->declared_length!=GHTTP_TACT_ENCODED_SIZE)reason="encoded-size-mismatch";
            object_event(trace,pending,s,GHTTP_OBJECT_RESPONSE,reason,NULL,0,0,0);
        }
        if (s->status==101) {stop_stream(trace,s,false,"protocol-upgrade");return;}
        if (s->head || s->status<200 || s->status==204 || s->status==304) {complete_response(trace,s);return;}
    }
    if (s->chunked && s->has_length) {stop_stream(trace,s,outbound,"ambiguous-framing");return;}
    if (s->chunked) s->state=CHUNK_SIZE;
    else if (s->has_length && s->remaining) s->state=BODY;
    else if (outbound || s->has_length) {
        if (outbound) reset_stream(s);else complete_response(trace,s);
    } else if (!outbound && s->capture) s->state=CLOSE_BODY;
    else s->state=STOP; // unknown close-delimited body: never interpret as headers
}
static void line_done(GHTTPTrace *trace,GHTTPStream *s,bool outbound,GHTTPEmit emit,void *context) {
    if (s->state==FIRST) {
        if (!first_line(trace,s,outbound))stop_stream(trace,s,outbound,
            !strncmp(s->line,"PRI * HTTP/2",12)?"http2-not-observable":"malformed-http1-first-line");
    }
    else if (s->state==HEADERS) {
        if (!s->line[0]) headers_done(trace,s,outbound,emit,context);
        else if (!header(s))stop_stream(trace,s,outbound,"malformed-http1-header");
    } else if (s->state==CHUNK_SIZE) {
        char *extension=strchr(s->line,';');if(extension)*extension=0;
        if (!number(s->line,&s->remaining,16))stop_stream(trace,s,outbound,"malformed-chunk-size");
        else s->state=s->remaining?CHUNK_DATA:TRAILERS;
    } else if (s->state==TRAILERS && !s->line[0]) {
        if(outbound)reset_stream(s);else complete_response(trace,s);
    } else if (s->state==TRAILERS && !strchr(s->line,':')) {
        stop_stream(trace,s,outbound,"malformed-http1-trailer");
    }
    memset(s->line,0,sizeof s->line);s->line_length=0;
}
static void object_data(GHTTPTrace *trace,GHTTPStream *s,const void *bytes,size_t length) {
    if (!s->capture || !length)return;
    if (s->object_received>GHTTP_TACT_ENCODED_SIZE ||
        length>GHTTP_TACT_ENCODED_SIZE-s->object_received) {
        stop_stream(trace,s,false,"encoded-body-limit");return;
    }
    s->object_received+=length;
    object_event(trace,active(trace),s,GHTTP_OBJECT_DATA,"entity-bytes",bytes,length,0,0);
}
void gh_http_feed(GHTTPTrace *trace,bool outbound,const void *raw,size_t length,GHTTPEmit emit,void *context) {
    GHTTPStream *s=outbound?&trace->outbound:&trace->inbound;
    const unsigned char *bytes=raw;
    if (!bytes) return;
    while (length && s->state!=STOP) {
        if(s->state==CLOSE_BODY) {
            object_data(trace,s,bytes,length);return;
        }
        if (s->state==BODY || s->state==CHUNK_DATA) {
            size_t skip=s->remaining<length?(size_t)s->remaining:length;
            if(!outbound)object_data(trace,s,bytes,skip);
            if(s->state==STOP)break;
            bytes+=skip;length-=skip;s->remaining-=skip;
            if (!s->remaining) {
                if (s->state==CHUNK_DATA) {s->state=CHUNK_CRLF;s->chunk_crlf=0;}
                else if (outbound) reset_stream(s);else complete_response(trace,s);
            }
            continue;
        }
        unsigned char c=*bytes++;length--;
        if (s->state==CHUNK_CRLF) {
            if (c!=(s->chunk_crlf?'\n':'\r')) {stop_stream(trace,s,outbound,"malformed-chunk-terminator");continue;}
            if (++s->chunk_crlf==2) {s->state=CHUNK_SIZE;s->header_bytes=0;}
            continue;
        }
        if (++s->header_bytes>16384 || s->line_length+1>=sizeof s->line ||
            (!c || (c<32 && c!='\r' && c!='\n' && c!='\t') || c>126)) {
            stop_stream(trace,s,outbound,"unsupported-or-oversized-http1-line");continue;
        }
        if (c=='\n') {
            if (!s->line_length || s->line[s->line_length-1]!='\r') {stop_stream(trace,s,outbound,"malformed-http1-line-ending");continue;}
            s->line[--s->line_length]=0;line_done(trace,s,outbound,emit,context);
        } else s->line[s->line_length++]=(char)c;
    }
}
void gh_http_error(GHTTPTrace *trace,const char *operation,int code,int error_number,GHTTPEmit emit,void *context) {
    // Repeated EAGAIN on a nonblocking socket must not consume the request
    // and response budget before the first HTTP line arrives.
    if (trace->errors>=16) return;
    trace->errors++;
    object_event(trace,active(trace),&trace->inbound,GHTTP_OBJECT_ERROR,operation,NULL,0,code,error_number);
    char line[1024];
    if(trace->outbound.state==HEADERS && trace->outbound.method[0]) {
        snprintf(line,sizeof line,"[tact-http] connection=%" PRIu64 " pending-request=%" PRIu64 " method=%s url=%s operation=%s code=%d errno=%d\n",
            trace->id,trace->next_request+1,trace->outbound.method,trace->outbound.target,operation,code,error_number);
        output(trace,line,emit,context);return;
    }
    snprintf(line,sizeof line,"[tact-http] connection=%" PRIu64 " request=%" PRIu64 " operation=%s code=%d errno=%d\n",
        trace->id,trace->queue_count?trace->queue[trace->queue_start].id:0,operation,code,error_number);
    output(trace,line,emit,context);
}
void gh_http_finish(GHTTPTrace *trace,const char *reason,GHTTPEmit emit,void *context) {
    (void)emit;(void)context;
    GHTTPStream *s=&trace->inbound;
    // A complete close-delimited entity is established only by actual EOF.
    // Retirement/cancellation must never turn a buffered prefix into success.
    if(s->state==CLOSE_BODY && reason && !strcmp(reason,"eof"))complete_response(trace,s);
    while(trace->queue_count) {
        if(!s->object_terminal)object_event(trace,active(trace),s,GHTTP_OBJECT_ABORT,
            reason?reason:"transport-retired",NULL,0,0,0);
        trace->queue_start=(trace->queue_start+1)%8;trace->queue_count--;
        reset_stream(s);
    }
    // A partially transmitted target request can fail before headers complete.
    if(trace->outbound.target_object && trace->outbound.state==HEADERS)
        stop_stream(trace,&trace->outbound,true,reason?reason:"transport-retired");
    trace->inbound.state=STOP;trace->outbound.state=STOP;
}
