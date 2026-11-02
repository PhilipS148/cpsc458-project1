/*
 * CPSC 458 - Malware Analysis
 * Project 1 starter program (Fall 2026)
 *
 * This file is harmless as supplied. It prints "Hello, world!" and provides
 * a fail-closed gate for laboratory-only behavior students may add later.
 *
 * Lab mode requires BOTH:
 *   1. Exactly one argument: --lab-run
 *   2. A regular file at C:\CPSC458-LAB\ENABLE
 *
 * Example build with MinGW-w64:
 *   x86_64-w64-mingw32-gcc -o cpsc458_starter.exe cpsc458_starter.c
 *
 * Never run modified versions containing malware outside an isolated VM.
 */

#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <stdio.h>
#include <string.h>

static int lab_enabled(int argc, char *argv[])
{
    DWORD attrs;

    if (argc != 2 || strcmp(argv[1], "--lab-run") != 0)
        return 0;

    attrs = GetFileAttributesA("C:\\CPSC458-LAB\\ENABLE");

    return attrs != INVALID_FILE_ATTRIBUTES &&
           (attrs & FILE_ATTRIBUTE_DIRECTORY) == 0;
}

int main(int argc, char *argv[])
{
    puts("Hello, world!");

    /* No laboratory-only action may occur before this check. */
    if (!lab_enabled(argc, argv))
        return 0;

    /* This message makes the gate testable, even in optimized builds. */
    puts("Lab mode enabled. No additional behavior is implemented.");

    /*
     * Add laboratory-only functionality here in Part 2.
     * Keep all related side effects below the lab_enabled() check.
     */

    return 0;
}
