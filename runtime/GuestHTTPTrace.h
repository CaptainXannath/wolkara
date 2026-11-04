#ifndef GUEST_HTTP_TRACE_H
#define GUEST_HTTP_TRACE_H
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

// HTTP/1 metadata only. Bodies and header values never reach the output.
// Unknown framing, HTTP/2, oversized headers and malformed messages stop
// parsing that direction rather than searching arbitrary payloads for HTTP.
typedef void (*GHTTPEmit)(const char *line, void *context);

#define GHTTP_TACT_OBJECT_PATH "/tpr/wow/data/46/c3/46c3d32d04ba185323ebea70f24ce282"
#define GHTTP_TACT_ENCODED_SIZE 35927u

typedef enum {
    GHTTP_OBJECT_REQUEST, GHTTP_OBJECT_RESPONSE, GHTTP_OBJECT_DATA,
    GHTTP_OBJECT_COMPLETE, GHTTP_OBJECT_ABORT, GHTTP_OBJECT_ERROR,
    GHTTP_OBJECT_UNSUPPORTED
} GHTTPObjectKind;
typedef struct {
    GHTTPObjectKind kind;
    uint64_t connection, request, declared_length, total;
    unsigned status;
    int code, error_number;
    bool has_length, eligible;
    const char *method, *url, *reason;
    const void *bytes;
    size_t length;
} GHTTPObjectEvent;
// Exact target entity bytes are transient callback input, never text output.
// Do not retain the pointer or reenter the parser from this callback.
typedef void (*GHTTPObjectObserve)(const GHTTPObjectEvent *event, void *context);
typedef struct {
    uint64_t id;
    bool head, get, target_object;
    char method[12], url[512];
} GHTTPPending;
typedef struct {
    unsigned state, status, header_bytes, chunk_crlf;
    size_t line_length;
    uint64_t remaining, declared_length;
    bool has_length, chunked, head, get, target_object, encoded_http_body;
    bool capture, object_terminal;
    uint64_t object_received;
    char line[2048], method[12], target[512], host[256];
} GHTTPStream;
typedef struct {
    uint64_t id, next_request;
    char peer[256];
    bool tls;
    unsigned queue_start, queue_count, reports, errors, object_requests;
    bool unsupported_notified;
    GHTTPPending queue[8];
    GHTTPObjectObserve observe;
    void *observe_context;
    GHTTPStream outbound, inbound;
} GHTTPTrace;

void gh_http_init(GHTTPTrace *trace, uint64_t id, bool tls);
void gh_http_peer(GHTTPTrace *trace, const char *peer, size_t length);
void gh_http_observe_object(GHTTPTrace *trace, GHTTPObjectObserve observe, void *context);
void gh_http_feed(GHTTPTrace *trace, bool outbound, const void *bytes, size_t length,
                  GHTTPEmit emit, void *context);
void gh_http_error(GHTTPTrace *trace, const char *operation, int code, int error_number,
                   GHTTPEmit emit, void *context);
// Call on actual EOF/transport retirement, not on retryable EAGAIN/WouldBlock.
// A close-delimited target can complete only at EOF; other unfinished target
// requests report ABORT. This function does not close or alter the transport.
void gh_http_finish(GHTTPTrace *trace, const char *reason, GHTTPEmit emit, void *context);
// Keeps public TACT object paths, strips user info, query and fragment values,
// and redacts all unrecognized paths (including token-bearing path segments).
void gh_http_url(const char *target, const char *peer, bool tls, char *out, size_t size);
#endif
