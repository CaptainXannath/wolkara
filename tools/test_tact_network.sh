#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build/emulation
xcrun clang -std=c11 -Wall -Wextra -Werror -O1 -g \
    -fsanitize=address,undefined -fno-omit-frame-pointer -Iruntime \
    runtime/GuestHTTPTrace.c tests/test_http_trace.c -o build/emulation/test_http_trace
build/emulation/test_http_trace
