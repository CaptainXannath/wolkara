#include "GuestHTTPTrace.h"
#include <assert.h>
#include <errno.h>
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
static struct {
    unsigned events[GHTTP_OBJECT_UNSUPPORTED+1], complete_candidates;
    size_t bytes;
    uint64_t request;
    unsigned status;
    int code, error_number;
    bool response_eligible;
    char response_reason[80], last_reason[80], method[12], url[512];
} observed;
static unsigned char entity[GHTTP_TACT_ENCODED_SIZE+1];
static void observe_object(const GHTTPObjectEvent *event,void *context) {
    assert(context==&observed);assert(event->connection==42);
    observed.events[event->kind]++;observed.request=event->request;
    if(event->method)snprintf(observed.method,sizeof observed.method,"%s",event->method);
    if(event->url) {
        snprintf(observed.url,sizeof observed.url,"%s",event->url);
        assert(!strstr(event->url,"SECRET"));assert(!strstr(event->url,"CREDENTIAL"));
    }
    snprintf(observed.last_reason,sizeof observed.last_reason,"%s",event->reason?event->reason:"");
    if(event->kind==GHTTP_OBJECT_RESPONSE) {
        observed.status=event->status;observed.response_eligible=event->eligible;
        snprintf(observed.response_reason,sizeof observed.response_reason,"%s",event->reason);
        if(event->has_length && event->eligible)assert(event->declared_length==GHTTP_TACT_ENCODED_SIZE);
    }
    if(event->kind==GHTTP_OBJECT_DATA) {
        assert(event->eligible && event->status==200 && event->bytes && event->length);
        assert(event->length<=GHTTP_TACT_ENCODED_SIZE-observed.bytes);
        assert(!memcmp(event->bytes,entity+observed.bytes,event->length));
        observed.bytes+=event->length;assert(event->total==observed.bytes);
    }
    if(event->kind==GHTTP_OBJECT_COMPLETE && event->eligible) {
        observed.complete_candidates++;assert(event->total==GHTTP_TACT_ENCODED_SIZE);
    }
    if(event->kind==GHTTP_OBJECT_ERROR) {observed.code=event->code;observed.error_number=event->error_number;}
}
static void reset_object(GHTTPTrace *trace) {
    reset(trace);memset(&observed,0,sizeof observed);
    gh_http_observe_object(trace,observe_object,&observed);
}
static const char *object_request="GET " GHTTP_TACT_OBJECT_PATH "?token=SECRET HTTP/1.1\r\nHost: level3.ssl.blizzard.com\r\nAuthorization: Bearer CREDENTIAL\r\n\r\n";
static const char *object_response="HTTP/1.1 200 OK\r\nContent-Length: 35927\r\n\r\n";
static void feed_entity(GHTTPTrace *trace,size_t count,bool fragmented) {
    if(fragmented)for(size_t i=0;i<count;i++)gh_http_feed(trace,false,entity+i,1,capture,NULL);
    else gh_http_feed(trace,false,entity,count,capture,NULL);
}
static void test_object_observation(void) {
    GHTTPTrace trace;
    // Synthetic HTTP-looking entity content must never become a text log.
    const char *pattern="HTTP/1.1 403 SECRET\r\nCookie: CREDENTIAL\r\n\r\n";
    for(size_t i=0;i<sizeof entity;i++)entity[i]=(unsigned char)pattern[i%strlen(pattern)];
    for(unsigned fragmented=0;fragmented<2;fragmented++) {
        reset_object(&trace);feed(&trace,true,object_request,fragmented);
        feed(&trace,false,object_response,fragmented);feed_entity(&trace,GHTTP_TACT_ENCODED_SIZE,fragmented);
        assert(observed.events[GHTTP_OBJECT_REQUEST]==1 && observed.events[GHTTP_OBJECT_RESPONSE]==1);
        assert(observed.events[GHTTP_OBJECT_COMPLETE]==1 && observed.complete_candidates==1);
        assert(observed.bytes==GHTTP_TACT_ENCODED_SIZE && !observed.events[GHTTP_OBJECT_ABORT]);
        assert(observed.request==1 && observed.status==200 && !strcmp(observed.method,"GET"));
        assert(strstr(observed.url,GHTTP_TACT_OBJECT_PATH "?[redacted]"));
        assert(occurrences("status=")==1);no_secrets();
    }
    reset_object(&trace);feed(&trace,true,request,true);feed(&trace,false,object_response,true);
    feed_entity(&trace,GHTTP_TACT_ENCODED_SIZE,true);
    assert(!observed.events[GHTTP_OBJECT_REQUEST] && !observed.bytes && !observed.events[GHTTP_OBJECT_COMPLETE]);no_secrets();

    reset_object(&trace);feed(&trace,true,object_request,true);
    feed(&trace,false,"HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n40\r\n",true);
    gh_http_feed(&trace,false,entity,64,capture,NULL);
    char chunk[64];snprintf(chunk,sizeof chunk,"\r\n%zx\r\n",(size_t)GHTTP_TACT_ENCODED_SIZE-64);
    feed(&trace,false,chunk,true);gh_http_feed(&trace,false,entity+64,GHTTP_TACT_ENCODED_SIZE-64,capture,NULL);
    feed(&trace,false,"\r\n0\r\nCookie: SECRET\r\n\r\n",true);
    assert(observed.bytes==GHTTP_TACT_ENCODED_SIZE && observed.complete_candidates==1);no_secrets();

    reset_object(&trace);feed(&trace,true,object_request,true);feed(&trace,false,object_response,true);
    feed_entity(&trace,17,true);gh_http_finish(&trace,"eof",capture,NULL);
    assert(observed.bytes==17 && observed.events[GHTTP_OBJECT_ABORT]==1 && !observed.events[GHTTP_OBJECT_COMPLETE]);
    assert(!strcmp(observed.last_reason,"eof"));gh_http_finish(&trace,"eof",capture,NULL);
    assert(observed.events[GHTTP_OBJECT_ABORT]==1);no_secrets();

    reset_object(&trace);feed(&trace,true,object_request,true);
    feed(&trace,false,"HTTP/1.1 200 OK\r\n\r\n",true);feed_entity(&trace,GHTTP_TACT_ENCODED_SIZE,true);
    assert(!observed.events[GHTTP_OBJECT_COMPLETE]);gh_http_finish(&trace,"eof",capture,NULL);
    assert(observed.complete_candidates==1);no_secrets();
    reset_object(&trace);feed(&trace,true,object_request,true);
    feed(&trace,false,"HTTP/1.1 200 OK\r\n\r\n",true);feed_entity(&trace,GHTTP_TACT_ENCODED_SIZE,true);
    gh_http_finish(&trace,"cancelled",capture,NULL);
    assert(observed.events[GHTTP_OBJECT_ABORT]==1 && !observed.events[GHTTP_OBJECT_COMPLETE]);no_secrets();

    reset_object(&trace);feed(&trace,true,object_request,true);
    feed(&trace,false,"HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n8c58\r\n",true);
    // Advertised chunk is deliberately too large, and entity callbacks stay bounded.
    feed_entity(&trace,GHTTP_TACT_ENCODED_SIZE,true);
    gh_http_feed(&trace,false,entity+GHTTP_TACT_ENCODED_SIZE,1,capture,NULL);
    assert(observed.bytes==GHTTP_TACT_ENCODED_SIZE && observed.events[GHTTP_OBJECT_ABORT]==1);
    assert(!observed.events[GHTTP_OBJECT_COMPLETE] && !strcmp(observed.last_reason,"encoded-body-limit"));no_secrets();

    reset_object(&trace);feed(&trace,true,object_request,true);
    feed(&trace,false,"HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n1\r\n",true);
    gh_http_feed(&trace,false,entity,1,capture,NULL);feed(&trace,false,"\r\n0\r\n\r\n",true);
    assert(observed.bytes==1 && observed.events[GHTTP_OBJECT_ABORT]==1 && !observed.complete_candidates);no_secrets();

    reset_object(&trace);feed(&trace,true,object_request,true);
    feed(&trace,false,"HTTP/1.1 200 OK\r\nContent-Length: 35928\r\n\r\n",true);
    feed_entity(&trace,sizeof entity,true);
    assert(!observed.response_eligible && !strcmp(observed.response_reason,"encoded-size-mismatch"));
    assert(!observed.bytes && !observed.complete_candidates);no_secrets();
    reset_object(&trace);feed(&trace,true,object_request,true);
    feed(&trace,false,"HTTP/1.1 206 Partial\r\nContent-Length: 1\r\n\r\nX",true);
    assert(observed.status==206 && !observed.response_eligible && !observed.bytes && !observed.complete_candidates);no_secrets();
    reset_object(&trace);feed(&trace,true,object_request,true);
    feed(&trace,false,"HTTP/1.1 200 OK\r\nContent-Encoding: gzip\r\nContent-Length: 35927\r\n\r\n",true);
    feed_entity(&trace,GHTTP_TACT_ENCODED_SIZE,true);
    assert(!observed.response_eligible && !strcmp(observed.response_reason,"http-content-encoding"));
    assert(!observed.bytes && !observed.complete_candidates);no_secrets();

    reset_object(&trace);
    feed(&trace,true,"HEAD " GHTTP_TACT_OBJECT_PATH " HTTP/1.1\r\nHost: level3.ssl.blizzard.com\r\n\r\n",true);
    feed(&trace,true,object_request,true);feed(&trace,false,object_response,true);feed(&trace,false,object_response,true);
    feed_entity(&trace,GHTTP_TACT_ENCODED_SIZE,true);
    assert(observed.events[GHTTP_OBJECT_REQUEST]==2 && observed.events[GHTTP_OBJECT_COMPLETE]==2);
    assert(observed.request==2 && observed.complete_candidates==1 && observed.bytes==GHTTP_TACT_ENCODED_SIZE);no_secrets();
    reset_object(&trace);feed(&trace,true,request,true);feed(&trace,true,object_request,true);
    feed(&trace,false,"HTTP/1.1 200 OK\r\nContent-Length: 1\r\n\r\nX",true);
    feed(&trace,false,object_response,true);feed_entity(&trace,GHTTP_TACT_ENCODED_SIZE,true);
    assert(observed.events[GHTTP_OBJECT_REQUEST]==1 && observed.request==2 && observed.complete_candidates==1);no_secrets();

    reset_object(&trace);feed(&trace,true,object_request,true);
    gh_http_error(&trace,"SSLRead",-9807,0,capture,NULL);
    assert(observed.events[GHTTP_OBJECT_ERROR]==1 && observed.code==-9807 && !observed.error_number);
    gh_http_finish(&trace,"cancelled",capture,NULL);assert(observed.events[GHTTP_OBJECT_ABORT]==1);no_secrets();
    reset_object(&trace);feed(&trace,true,"PRI * HTTP/2.0\r\n\r\nSM\r\n\r\n",true);
    assert(observed.events[GHTTP_OBJECT_UNSUPPORTED]==1 && !observed.bytes);
    assert(!strcmp(observed.last_reason,"http2-not-observable"));no_secrets();
    reset_object(&trace);
    for(unsigned i=0;i<12;i++) {
        feed(&trace,true,object_request,true);feed(&trace,false,"HTTP/1.1 403 No\r\nContent-Length: 0\r\n\r\n",true);
    }
    assert(observed.events[GHTTP_OBJECT_REQUEST]==12 && observed.events[GHTTP_OBJECT_RESPONSE]==12);
    assert(observed.events[GHTTP_OBJECT_COMPLETE]==12 && observed.status==403);
    // The first successful body may arrive after many rejected retries on
    // the same keep-alive connection. It must still reach verification.
    feed(&trace,true,object_request,true);feed(&trace,false,object_response,true);
    feed_entity(&trace,GHTTP_TACT_ENCODED_SIZE,true);
    assert(observed.events[GHTTP_OBJECT_REQUEST]==13 && observed.events[GHTTP_OBJECT_RESPONSE]==13);
    assert(observed.events[GHTTP_OBJECT_COMPLETE]==13 && observed.complete_candidates==1);
    assert(observed.request==13 && observed.status==200 && observed.bytes==GHTTP_TACT_ENCODED_SIZE);
    no_secrets();
}
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
    gh_http_url("https://SECRET.blizzard.com" GHTTP_TACT_OBJECT_PATH,NULL,true,safe,sizeof safe);
    assert(strstr(safe,"[redacted-host]"));assert(strstr(safe,GHTTP_TACT_OBJECT_PATH));assert(!strstr(safe,"SECRET"));
    gh_http_url(GHTTP_TACT_OBJECT_PATH,"CREDENTIAL.battle.net",true,safe,sizeof safe);
    assert(strstr(safe,"[unavailable]"));assert(!strstr(safe,"CREDENTIAL"));
    static const char *invalid_authorities[]={
        "wow.download.prd.cdn.blizzard.com:SECRET","wow.download.prd.cdn.blizzard.com:CREDENTIAL",
        "wow.download.prd.cdn.blizzard.com:443:SECRET","wow.download.prd.cdn.blizzard.com:",
        "wow.download.prd.cdn.blizzard.com:0","wow.download.prd.cdn.blizzard.com:65536",
        "wow.download.prd.cdn.blizzard.com:00000000123",
        "wow.download.prd.cdn.blizzard.com:+443","wow..blizzard.com","-wow.blizzard.com",
        "wow-.blizzard.com","[wow.blizzard.com]"
    };
    for(size_t i=0;i<sizeof invalid_authorities/sizeof invalid_authorities[0];i++) {
        char url[1024];
        snprintf(url,sizeof url,"https://%s/tpr/wow/data/46/c3/46c3d32d04ba185323ebea70f24ce282",invalid_authorities[i]);
        gh_http_url(url,NULL,true,safe,sizeof safe);
        assert(strstr(safe,"[redacted-host]"));assert(!strstr(safe,"SECRET"));assert(!strstr(safe,"CREDENTIAL"));
    }
    gh_http_url("https://wow.download.prd.cdn.blizzard.com:443/tpr/wow/data/46/c3/46c3d32d04ba185323ebea70f24ce282",NULL,true,safe,sizeof safe);
    assert(strstr(safe,"https://wow.download.prd.cdn.blizzard.com:443/tpr/wow/data/"));
    reset(&trace);
    feed(&trace,true,"GET /tpr/wow/data/46/c3/46c3d32d04ba185323ebea70f24ce282 HTTP/1.1\r\nHost: wow.download.prd.cdn.blizzard.com:CREDENTIAL\r\n\r\n",true);
    assert(strstr(captured,"method=GET"));assert(strstr(captured,"[unavailable]"));no_secrets();
    gh_http_url("/tpr/wow/data/46/c3/46c3d32d04ba185323ebea70f24ce282",NULL,true,safe,1);assert(!safe[0]);
    gh_http_url("/tpr/wow/data/00/c3/46c3d32d04ba185323ebea70f24ce282",NULL,true,safe,sizeof safe);assert(strstr(safe,"[redacted-path]"));

    reset(&trace);
    for(unsigned i=0;i<70;i++) {
        feed(&trace,true,"GET /x HTTP/1.1\r\nHost: level3.ssl.blizzard.com\r\n\r\n",false);
        feed(&trace,false,"HTTP/1.1 204 No Content\r\n\r\n",false);
    }
    assert(occurrences("text-report-limit=128 reached")==1);
    no_secrets();

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
    for(unsigned i=0;i<200;i++)gh_http_error(&trace,"read",-1,EAGAIN,capture,NULL);
    gh_http_error(&trace,"read",-1,ECONNRESET,capture,NULL);
    feed(&trace,true,request,true);
    feed(&trace,false,"HTTP/1.1 200 OK\r\nContent-Length: 0\r\n\r\n",true);
    assert(occurrences("operation=read")==3);
    char terminal[32];snprintf(terminal,sizeof terminal,"errno=%d",ECONNRESET);
    assert(strstr(captured,terminal));
    assert(strstr(captured,"request=1 method=GET"));assert(strstr(captured,"request=1 status=200"));no_secrets();
    test_object_observation();
    puts("HTTP metadata redaction, target entity observation, fragmentation, framing and bounds passed");return 0;
}
