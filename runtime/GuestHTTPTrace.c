#include "GuestHTTPTrace.h"
#include <ctype.h>
#include <inttypes.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

enum { FIRST, HEADERS, BODY, CHUNK_SIZE, CHUNK_DATA, CHUNK_CRLF, TRAILERS, STOP };
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
void gh_http_peer(GHTTPTrace *trace,const char *peer,size_t length) {
    if (peer && safe_host(peer,length)) {
        memcpy(trace->peer,peer,length);trace->peer[length]=0;
        if(!public_host(trace->peer))snprintf(trace->peer,sizeof trace->peer,"[redacted-host]");
    } else snprintf(trace->peer,sizeof trace->peer,"[redacted-host]");
}
static void output(GHTTPTrace *trace,const char *line,GHTTPEmit emit,void *context) {
    if (emit && trace->reports++<128) emit(line,context);
}
static void reset_stream(GHTTPStream *stream) { memset(stream,0,sizeof *stream); }
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
        char *version=strchr(space,' ');if (!version) return false;*version++=0;
        if (strcmp(version,"HTTP/1.1") && strcmp(version,"HTTP/1.0")) return false;
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
        s->remaining=length;s->has_length=true;
    } else if (equal(s->line,"Transfer-Encoding")) {
        if (!equal(colon,"chunked")) return false;
        s->chunked=true;
    } else if (equal(s->line,"Host") && safe_host(colon,strlen(colon)) && public_host(colon)) {
        snprintf(s->host,sizeof s->host,"%s",colon);
    }
    return true;
}
static void complete_response(GHTTPTrace *trace,GHTTPStream *s) {
    if (s->status>=200 && trace->queue_count) {
        trace->queue_start=(trace->queue_start+1)%8;trace->queue_count--;
    }
    reset_stream(s);
}
static void headers_done(GHTTPTrace *trace,GHTTPStream *s,bool outbound,GHTTPEmit emit,void *context) {
    char line[1024];
    if (outbound) {
        if (trace->queue_count==8) {s->state=STOP;trace->inbound.state=STOP;return;}
        uint64_t request=++trace->next_request;
        unsigned tail=(trace->queue_start+trace->queue_count)%8;
        trace->queue[tail].id=request;trace->queue[tail].head=s->head;trace->queue_count++;
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
    } else {
        uint64_t request=trace->queue_count?trace->queue[trace->queue_start].id:0;
        s->head=trace->queue_count && trace->queue[trace->queue_start].head;
        snprintf(line,sizeof line,"[tact-http] connection=%" PRIu64 " request=%" PRIu64 " status=%u\n",trace->id,request,s->status);
        output(trace,line,emit,context);
        if (s->status==101) {s->state=STOP;return;} // protocol upgrade is opaque
        if (s->head || s->status<200 || s->status==204 || s->status==304) {complete_response(trace,s);return;}
    }
    if (s->chunked && s->has_length) {s->state=STOP;return;}
    if (s->chunked) s->state=CHUNK_SIZE;
    else if (s->has_length && s->remaining) s->state=BODY;
    else if (outbound || s->has_length) {
        if (outbound) reset_stream(s);else complete_response(trace,s);
    } else s->state=STOP; // close-delimited body: never interpret it as headers
}
static void line_done(GHTTPTrace *trace,GHTTPStream *s,bool outbound,GHTTPEmit emit,void *context) {
    if (s->state==FIRST) {if (!first_line(trace,s,outbound)) s->state=STOP;}
    else if (s->state==HEADERS) {
        if (!s->line[0]) headers_done(trace,s,outbound,emit,context);
        else if (!header(s)) s->state=STOP;
    } else if (s->state==CHUNK_SIZE) {
        char *extension=strchr(s->line,';');if(extension)*extension=0;
        if (!number(s->line,&s->remaining,16)) s->state=STOP;
        else s->state=s->remaining?CHUNK_DATA:TRAILERS;
    } else if (s->state==TRAILERS && !s->line[0]) {
        if(outbound)reset_stream(s);else complete_response(trace,s);
    }
    memset(s->line,0,sizeof s->line);s->line_length=0;
}
void gh_http_feed(GHTTPTrace *trace,bool outbound,const void *raw,size_t length,GHTTPEmit emit,void *context) {
    GHTTPStream *s=outbound?&trace->outbound:&trace->inbound;
    const unsigned char *bytes=raw;
    if (!bytes) return;
    while (length && s->state!=STOP) {
        if (s->state==BODY || s->state==CHUNK_DATA) {
            size_t skip=s->remaining<length?(size_t)s->remaining:length;
            bytes+=skip;length-=skip;s->remaining-=skip;
            if (!s->remaining) {
                if (s->state==CHUNK_DATA) {s->state=CHUNK_CRLF;s->chunk_crlf=0;}
                else if (outbound) reset_stream(s);else complete_response(trace,s);
            }
            continue;
        }
        unsigned char c=*bytes++;length--;
        if (s->state==CHUNK_CRLF) {
            if (c!=(s->chunk_crlf?'\n':'\r')) {s->state=STOP;continue;}
            if (++s->chunk_crlf==2) {s->state=CHUNK_SIZE;s->header_bytes=0;}
            continue;
        }
        if (++s->header_bytes>16384 || s->line_length+1>=sizeof s->line ||
            (!c || (c<32 && c!='\r' && c!='\n' && c!='\t') || c>126)) {s->state=STOP;continue;}
        if (c=='\n') {
            if (!s->line_length || s->line[s->line_length-1]!='\r') {s->state=STOP;continue;}
            s->line[--s->line_length]=0;line_done(trace,s,outbound,emit,context);
        } else s->line[s->line_length++]=(char)c;
    }
}
void gh_http_error(GHTTPTrace *trace,const char *operation,int code,int error_number,GHTTPEmit emit,void *context) {
    // Repeated EAGAIN on a nonblocking socket must not consume the request
    // and response budget before the first HTTP line arrives.
    if (trace->errors>=16) return;
    trace->errors++;
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
