#pragma once
#include <stdbool.h>
#include <stdio.h>
// Single page, only host-authored instructions. Consumes the JIT session.
bool da_synthetic_probe(FILE *log);
// The script resumes the process just before its detach flag becomes visible.
// Bounded wait, on the preparation worker only; never issues another detach.
bool da_external_wait_for_detachment(void);
