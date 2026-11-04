#include "GuestHTTPTrace.h"
#include <assert.h>
#include <stdio.h>
#include <string.h>

static char captured[32768];
static void capture(const char *line,void *context) {
    (void)context;assert(strlen(captured)+strlen(line)<sizeof captured);strcat(captured,line);
}
static void feed(GHTTPTrace *trace,bool outgoing,const char *bytes,bool fragmented) {
    size_t length=strlen(bytes);
    if(fragmented) for(size_t i=0;i<length;i++)gh_http_feed(trace,outgoing,bytes+i,1,capture,NULL);
    else gh_http_feed(trace,outgoing,bytes,length,capture,NULL);
}
static unsigned occurrences(const char *needle) {
    unsigned n=0;const char *at=captured;
    while((at=strstr(at,needle))) {n++;at+=strlen(needle);}return n;
}
static const char *request="GET /tpr/wow/patch/46/c3/46c3d32d04ba185323ebea70f24ce282.index?token=SECRET#CREDENTIAL HTTP/1.1\r\nHost: wow.download.prd.cdn.blizzard.com\r\nAuthorization: Bearer SECRET\r\nCookie: session=CREDENTIAL\r\n\r\n";
static void reset(GHTTPTrace *trace) {captured[0]=0;gh_http_init(trace,42,true);}
static void no_secrets(void) {assert(!strstr(captured,"SECRET"));assert(!strstr(captured,"CREDENTIAL"));assert(!strstr(captured,"Authorization"));assert(!strstr(captured,"Cookie"));}
int main(void) {
    GHTTPTrace trace;
    char safe[1024];
    gh_http_url("https://user:CREDENTIAL@wow.download.prd.cdn.blizzard.com/tpr/wow/patch/46/c3/46c3d32d04ba185323ebea70f24ce282.index?token=SECRET#fragment",NULL,true,safe,sizeof safe);
    assert(strstr(safe,"https://wow.download.prd.cdn.blizzard.com/tpr/wow/patch/46/c3/46c3d32d04ba185323ebea70f24ce282.index?[redacted]"));
    assert(!strstr(safe,"CREDENTIAL"));assert(!strstr(safe,"SECRET"));
    gh_http_url("/tpr/wow/data/46/c3/46c3d32d04ba185323ebea70f24ce282","wow.download.prd.cdn.blizzard.com",true,safe,sizeof safe);
    assert(!strcmp(safe,"https://wow.download.prd.cdn.blizzard.com/tpr/wow/data/46/c3/46c3d32d04ba185323ebea70f24ce282"));
    gh_http_url("/session/SECRET/download",NULL,true,safe,sizeof safe);assert(strstr(safe,"[redacted-path]"));assert(!strstr(safe,"SECRET"));
    gh_http_url("https://bad\nhost/SECRET",NULL,true,safe,sizeof safe);assert(strstr(safe,"[redacted-host]"));
    gh_http_url("/tpr/wow/data/46/c3/46c3d32d04ba185323ebea70f24ce282",NULL,true,safe,1);assert(!safe[0]);
    gh_http_url("/tpr/wow/data/00/c3/46c3d32d04ba185323ebea70f24ce282",NULL,true,safe,sizeof safe);assert(strstr(safe,"[redacted-path]"));

    for(unsigned fragmented=0;fragmented<2;fragmented++) {
        reset(&trace);feed(&trace,true,request,fragmented);
        feed(&trace,false,"HTTP/1.1 403 Forbidden\r\nContent-Length: 27\r\nSet-Cookie: SECRET\r\n\r\nHTTP/1.1 200 SECRET\r\nABCDEF",fragmented);
        assert(strstr(captured,"connection=42 request=1 method=GET"));
        assert(strstr(captured,"https://wow.download.prd.cdn.blizzard.com/tpr/wow/patch/46/c3/46c3d32d04ba185323ebea70f24ce282.index?[redacted]"));
        assert(occurrences("status=")==1);assert(strstr(captured,"status=403"));no_secrets();
    }
    reset(&trace);feed(&trace,true,request,true);
    feed(&trace,false,"HTTP/1.1 100 Continue\r\n\r\nHTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n6;SECRET\r\nSECRET\r\n0\r\nCookie: SECRET\r\n\r\n",true);
    feed(&trace,true,request,true);feed(&trace,false,"HTTP/1.1 404 Missing\r\nContent-Length: 0\r\n\r\n",true);
    assert(strstr(captured,"request=1 status=100"));assert(strstr(captured,"request=1 status=200"));assert(strstr(captured,"request=2 status=404"));no_secrets();

    reset(&trace);gh_http_peer(&trace,"wow.download.prd.cdn.blizzard.com",strlen("wow.download.prd.cdn.blizzard.com"));
    feed(&trace,true,"HEAD /tpr/wow/patch/46/c3/46c3d32d04ba185323ebea70f24ce282.index HTTP/1.1\r\n\r\n",true);
    feed(&trace,true,request,true);
    feed(&trace,false,"HTTP/1.1 403 No\r\nContent-Length: 999999\r\n\r\nHTTP/1.1 204 No Content\r\n\r\n",true);
    assert(strstr(captured,"request=1 status=403"));assert(strstr(captured,"request=2 status=204"));no_secrets();

    reset(&trace);feed(&trace,true,"POST /session/SECRET HTTP/1.1\r\nContent-Length: 6\r\n\r\nSECRET",true);
    feed(&trace,true,request,true);assert(occurrences("method=")==2);no_secrets();
    gh_http_error(&trace,"SSLRead",-9807,0,capture,NULL);assert(strstr(captured,"operation=SSLRead code=-9807 errno=0"));

    reset(&trace);feed(&trace,true,request,false);
    feed(&trace,false,"HTTP/1.1 200 OK\r\n\r\nHTTP/1.1 403 SECRET\r\n\r\n",true);
    assert(occurrences("status=")==1);no_secrets();

    reset(&trace);feed(&trace,true,"GET /SECRET HTTP/1.1\r\nContent-Length: 1\r\nContent-Length: 2\r\n\r\n",true);assert(!captured[0]);
    reset(&trace);feed(&trace,true,"PRI * HTTP/2.0\r\n\r\nSM\r\n\r\n",true);assert(!captured[0]);
    reset(&trace);char too_long[4096];memset(too_long,'A',sizeof too_long);
    gh_http_feed(&trace,true,too_long,sizeof too_long,capture,NULL);feed(&trace,true,request,true);assert(!captured[0]);
    reset(&trace);feed(&trace,true,"GET /SECRET HTTP/1.1\nAuthorization: SECRET\n\n",true);assert(!captured[0]);
    reset(&trace);
    for(unsigned i=0;i<200;i++)gh_http_error(&trace,"read",-1,35,capture,NULL);
    feed(&trace,true,request,true);
    feed(&trace,false,"HTTP/1.1 200 OK\r\nContent-Length: 0\r\n\r\n",true);
    assert(occurrences("operation=read")==16);
    assert(strstr(captured,"request=1 method=GET"));assert(strstr(captured,"request=1 status=200"));no_secrets();
    puts("HTTP metadata redaction, fragmentation, framing and bounds passed");return 0;
}
