#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build/emulation
xcrun clang -fobjc-arc -Wall -Wextra -Werror -g -fsanitize=address,undefined \
    -Ilauncher/App -framework Foundation launcher/App/ExternalJITRequest.m \
    tests/test_external_jit_request.m -o build/emulation/test_external_jit_request
build/emulation/test_external_jit_request
xcrun clang -Wall -Wextra -Werror -g -fsanitize=address,undefined -Iruntime \
    runtime/ExternalJITProbe.c runtime/DebuggerArena.c runtime/NativeCodeMemory.c \
    runtime/HostDiagnostics.c runtime/HostExecutionProbe.c tests/test_external_jit_probe.c \
    -o build/emulation/test_external_jit_probe
build/emulation/test_external_jit_probe
