#!/bin/sh
# compile.sh - POSIX sh MinGW-w64 build wrapper
# Examples:
#   ./compile.sh test.c
#   ./compile.sh --64 --dll mydll.c
#   ./compile.sh --c++ book-example.c
#   ./compile.sh --32 --windows --unicode test.c -- -D_DEBUG
#   ./compile.sh 'source with spaces.c' -- '-DNAME=two words'

set -eu

usage() {
    cat <<'USAGE'
Usage: compile.sh [--32|--64] [--c++] [--windows] [--unicode] [--dll] <source-file> [-- extra flags]

Defaults: 64-bit executable.
  --32       Build for 32-bit Windows.
  --64       Build for 64-bit Windows (default).
  --c++      Compile .c sources as C++ with G++ (also link the C++ runtime).
  --windows  Use the GUI subsystem for executables; ignored for DLLs.
  --unicode  Define UNICODE and _UNICODE; also use -municode for GUI executables.
  --dll      Build a DLL and an import library instead of an executable.
  --help     Display this help.

.c files use GCC; .cc, .cp, .cpp, .cxx, .c++, .C, and .CPP use G++.
Unrecognized options and arguments after the source file are passed to the compiler.
For example, use -- -fexceptions or -- -O2 to override default flags.
Use -- to separate compiler flags from wrapper options.
USAGE
}

error() {
    printf 'Error: %s\n' "$*" >&2
    exit 1
}

arch=64
force_cpp=0
windows=0
unicode=0
dll=0
src=''
after_separator=0

# POSIX sh has no arrays. Shift the original arguments off the front,
# appending compiler-only arguments to the end of the positional parameters.
# The counter ensures appended arguments are not processed again.
remaining=$#
while [ "$remaining" -gt 0 ]; do
    arg=$1
    shift
    remaining=$((remaining - 1))

    if [ "$after_separator" -eq 1 ]; then
        set -- "$@" "$arg"
        continue
    fi

    case "$arg" in
        --32)      arch=32 ;;
        --64)      arch=64 ;;
        --c++)     force_cpp=1 ;;
        --windows) windows=1 ;;
        --unicode) unicode=1 ;;
        --dll)     dll=1 ;;
        --help|-h) usage; exit 0 ;;
        --)        after_separator=1 ;;
        -*)        set -- "$@" "$arg" ;;
        *)
            if [ -z "$src" ]; then
                src=$arg
            else
                set -- "$@" "$arg"
            fi
            ;;
    esac
done

[ -n "$src" ] || { usage >&2; exit 1; }
[ -f "$src" ] || error "source file not found: $src"

case "$src" in
    *.c) compiler_suffix=gcc; language=c ;;
    *.cc|*.cp|*.cpp|*.cxx|*.c++|*.C|*.CPP)
         compiler_suffix=g++; language=c++ ;;
    *)   error "unsupported source file extension: $src" ;;
esac

# Some textbook examples use G++ even when the source is named *.c.
if [ "$force_cpp" -eq 1 ]; then
    compiler_suffix=g++
    language=c++
fi

if [ "$arch" -eq 64 ]; then
    compiler="x86_64-w64-mingw32-$compiler_suffix"
else
    compiler="i686-w64-mingw32-$compiler_suffix"
fi
command -v "$compiler" >/dev/null 2>&1 || error "missing $compiler in PATH"

base_name=${src##*/}
stem=${base_name%.*}
if [ "$dll" -eq 1 ]; then
    out="$stem.dll"
    implib="$stem.a"
else
    out="$stem.exe"
fi

# Check whether the selected compiler can compile AND link with LTO.
# A subshell confines cleanup traps to this probe. The temporary directory
# may be outside the (possibly read-only) current directory; if the system
# temporary location is unavailable, try the current directory instead.
supports_lto() (
    lto_dir=$(mktemp -d 2>/dev/null) ||
        lto_dir=$(mktemp -d './.compile-lto.XXXXXXXX' 2>/dev/null) ||
        exit 1
    trap 'rm -rf "$lto_dir"' 0
    trap 'exit 1' 1 2 3 15

    printf '%s\n' 'int main(void) { return 0; }' |
        "$compiler" -x "$language" -flto -o "$lto_dir/probe.exe" - \
            >/dev/null 2>&1
)

# At this point, "$@" contains only extra compiler flags. Prepend the
# remaining arguments in reverse groups to keep those user flags LAST,
# allowing them to override defaults (for example, -O0 overrides -O3).
if [ "$unicode" -eq 1 ]; then
    if [ "$dll" -eq 0 ] && [ "$windows" -eq 1 ]; then
        set -- -DUNICODE -D_UNICODE -municode "$@"
    else
        set -- -DUNICODE -D_UNICODE "$@"
    fi
fi

if [ "$dll" -eq 1 ]; then
    if [ "$arch" -eq 32 ]; then
        set -- -Wl,--add-stdcall-alias "$@"
    fi
    set -- -shared "-Wl,--out-implib,$implib" "$@"
elif [ "$windows" -eq 1 ]; then
    set -- -mwindows "$@"
fi

set -- \
    -lws2_32 -ladvapi32 -lcrypt32 -liphlpapi -lsecur32 \
    -lole32 -loleaut32 -lshell32 -lpathcch -lshlwapi \
    -luser32 -lurlmon -lbcrypt "$@"

# GCC supports these options for C as well as C++ (with some
# language-specific effects). Preserve the original book-style flags
# regardless of source language. Only the C++ runtime is C++-specific.
if [ "$language" = 'c++' ]; then
    set -- -static-libstdc++ "$@"
fi

# Test once per invocation. User-supplied flags still come last, so
# -- -fno-lto overrides the detected -flto default when requested.
if supports_lto; then
    set -- -flto "$@"
fi

set -- "$compiler" "$src" -o "$out" \
    -O3 -ffunction-sections -fdata-sections -fmerge-all-constants \
    -Wno-write-strings -Wint-to-pointer-cast \
    -fno-exceptions -fpermissive \
    -static-libgcc -s -Wl,--gc-sections -DSECURITY_WIN32 "$@"

# Print a command line that can be pasted back into a POSIX shell.
# Simple arguments are left bare; others are single-quoted, with embedded
# single quotes escaped. This is for display only; execution uses "$@".
print_shell_arg() {
    case $1 in
        '') printf "''" ;;
        *[!a-zA-Z0-9_./:@%+=,-]*)
            rest=$1
            printf "'"
            while :; do
                case $rest in
                    *"'"*)
                        printf '%s' "${rest%%"'"*}"
                        printf "'\\''"
                        rest=${rest#*"'"}
                        ;;
                    *)
                        printf '%s' "$rest"
                        break
                        ;;
                esac
            done
            printf "'"
            ;;
        *) printf '%s' "$1" ;;
    esac
}

separator=''
for arg do
    printf '%s' "$separator"
    print_shell_arg "$arg"
    separator=' '
done
printf '\n'

"$@"
