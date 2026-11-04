#ifndef GUEST_HTTP_TRACE_H
#define GUEST_HTTP_TRACE_H
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

// HTTP/1 metadata only. Bodies and header values never reach the output.
// Unknown framing, HTTP/2, oversized headers and malformed messages stop
// parsing that direction rather than searching arbitrary payloads for HTTP.
typedef void (*GHTTPEmit)(const char *line, void *context);
typedef struct {
    unsigned state, status, header_bytes, chunk_crlf;
    size_t line_length;
    uint64_t remaining;
    bool has_length, chunked, head;
    char line[2048], method[12], target[512], host[256];
} GHTTPStream;
typedef struct {
    uint64_t id, next_request;
    char peer[256];
    bool tls;
    unsigned queue_start, queue_count, reports, errors;
    struct { uint64_t id; bool head; } queue[8];
    GHTTPStream outbound, inbound;
} GHTTPTrace;

void gh_http_init(GHTTPTrace *trace, uint64_t id, bool tls);
void gh_http_peer(GHTTPTrace *trace, const char *peer, size_t length);
void gh_http_feed(GHTTPTrace *trace, bool outbound, const void *bytes, size_t length,
                  GHTTPEmit emit, void *context);
void gh_http_error(GHTTPTrace *trace, const char *operation, int code, int error_number,
                   GHTTPEmit emit, void *context);
// Keeps public TACT object paths, strips user info, query and fragment values,
// and redacts all unrecognized paths (including token-bearing path segments).
void gh_http_url(const char *target, const char *peer, bool tls, char *out, size_t size);
#endif
