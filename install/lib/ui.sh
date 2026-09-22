# How the installer talks. Sourced by install/install.sh; not run on its own.
#
# Four verbs cover everything the installer says:
#
#   row     one line of progress: a mark, a label, a detail
#   note    a dim explanation of what is about to happen or why
#   ask     a free-text question with a default
#   choose  a numbered menu with a default
#
# Colour and glyphs are decided once, in ui_init, and every verb reads the
# result. Colour is on only when stdout is a terminal, NO_COLOR is unset and
# TERM is not dumb, so a transcript piped to a file is plain text. Glyphs
# follow the locale: a UTF-8 terminal gets ✓ and ›, anything else gets ASCII.
#
# Every question reads a whole line. Single-key input reads nicely but breaks
# the moment the answers arrive from a file or a pipe, and a scripted install
# is how this installer is tested.

ui_init() {
    if [ -t 1 ] && [ -z "${NO_COLOR:-}" ] && [ "${TERM:-dumb}" != dumb ] \
        && [ "${FLOW_NO_COLOR:-0}" != 1 ]; then
        C_BOLD=$'\033[1m'    C_DIM=$'\033[2m'     C_RESET=$'\033[0m'
        C_GREEN=$'\033[32m'  C_YELLOW=$'\033[33m' C_RED=$'\033[31m'
        C_CYAN=$'\033[36m'   C_MAGENTA=$'\033[35m'
    else
        C_BOLD='' C_DIM='' C_RESET='' C_GREEN='' C_YELLOW='' C_RED='' C_CYAN='' C_MAGENTA=''
    fi

    case "${LC_ALL:-${LC_CTYPE:-${LANG:-}}}" in
        *UTF-8*|*utf-8*|*UTF8*|*utf8*)
            G_OK='✓' G_WARN='!' G_FAIL='✗' G_SKIP='–' G_DOT='·' G_PROMPT='›' G_RULE='─'
            ;;
        *)
            G_OK='+' G_WARN='!' G_FAIL='x' G_SKIP='-' G_DOT='.' G_PROMPT='>' G_RULE='-'
            ;;
    esac

    COLS=$( { [ -t 1 ] && tput cols; } 2>/dev/null || printf '%s' "${COLUMNS:-80}")
    [ "$COLS" -ge 60 ] 2>/dev/null || COLS=80
    [ "$COLS" -le 100 ] 2>/dev/null || COLS=100

    # Answers arriving from a pipe are echoed after the prompt, so a scripted
    # run reads like an interactive one.
    ECHO_ANSWERS=no
    [ -t 0 ] || ECHO_ANSWERS=yes
}

# --- plain output -----------------------------------------------------------

say()   { printf '%s\n' "$*"; }
blank() { printf '\n'; }

# A dim paragraph, wrapped to the terminal and indented two spaces.
note() {
    local line
    while IFS= read -r line; do
        printf '  %s%s%s\n' "$C_DIM" "$line" "$C_RESET"
    done < <(printf '%s\n' "$*" | fold -s -w $((COLS - 4)) | sed 's/ *$//')
}

# A hint under a question: what the answer is for. Wrapped like a note.
hint() { note "$*"; }

# --- structure --------------------------------------------------------------

banner() {
    local title=$1 tagline=$2
    blank
    printf '  %s%s%s  %s%s%s\n' "$C_BOLD" "$title" "$C_RESET" "$C_DIM" "$tagline" "$C_RESET"
}

# A numbered section header with a rule out to the terminal edge.
section() {
    local num=$1 title=$2 rule_len i rule=''
    rule_len=$((COLS - 8 - ${#num} - ${#title}))
    i=0
    while [ "$i" -lt "$rule_len" ]; do rule="$rule$G_RULE"; i=$((i + 1)); done
    blank
    printf '  %s%s%s  %s%s%s  %s%s%s\n' \
        "$C_MAGENTA" "$num" "$C_RESET" "$C_BOLD" "$title" "$C_RESET" "$C_DIM" "$rule" "$C_RESET"
    blank
}

# One line of progress. The mark is ok, warn, fail, skip or info; the label is
# padded so the details line up down the section.
row() {
    local mark=$1 label=$2 detail=${3:-} glyph colour
    case $mark in
        ok)   glyph=$G_OK   colour=$C_GREEN  ;;
        warn) glyph=$G_WARN colour=$C_YELLOW ;;
        fail) glyph=$G_FAIL colour=$C_RED    ;;
        skip) glyph=$G_SKIP colour=$C_DIM    ;;
        *)    glyph=$G_DOT  colour=$C_DIM    ;;
    esac
    if [ -n "$detail" ]; then
        printf '  %s%s%s %-26s %s%s%s\n' "$colour" "$glyph" "$C_RESET" "$label" "$C_DIM" "$detail" "$C_RESET"
    else
        printf '  %s%s%s %s\n' "$colour" "$glyph" "$C_RESET" "$label"
    fi
}

# A follow-on line under a row, for the one or two things worth spelling out.
sub() { printf '      %s%s%s\n' "$C_DIM" "$*" "$C_RESET"; }

# A key and its value, for the summary table.
kv() {
    local key=$1 value=$2
    if [ -z "$value" ]; then
        printf '    %s%-26s%s %s(empty)%s\n' "$C_CYAN" "$key" "$C_RESET" "$C_DIM" "$C_RESET"
    else
        printf '    %s%-26s%s %s\n' "$C_CYAN" "$key" "$C_RESET" "$value"
    fi
}

# A failure the installer cannot continue past. The hint says what to do.
die() {
    local msg=$1 hint=${2:-}
    blank
    printf '  %s%s Stopped:%s %s\n' "$C_RED" "$G_FAIL" "$C_RESET" "$msg" >&2
    [ -z "$hint" ] || printf '    %s%s%s\n' "$C_DIM" "$hint" "$C_RESET" >&2
    blank
    exit 1
}

# --- questions --------------------------------------------------------------

# Read one line into the named variable. End of input is a failure, not an
# empty answer: a run whose input ran out has not answered the question. The
# locals carry a prefix because the caller passes the name of its own
# variable, and a plain name here would shadow it.
read_line() {
    local __rl_var=$1 __rl_reply
    printf '  %s%s%s ' "$C_CYAN" "$G_PROMPT" "$C_RESET"
    IFS= read -r __rl_reply || die "input ended before every question was answered" \
        "Run the installer again; nothing was written to the project."
    [ "$ECHO_ANSWERS" = no ] || printf '%s%s%s\n' "$C_DIM" "${__rl_reply:-(enter)}" "$C_RESET"
    printf -v "$__rl_var" '%s' "$__rl_reply"
}

# A free-text question. Enter takes the default, which may itself be empty
# when the question allows an empty answer.
#
#   ask VAR "question" "default" ["hint"]
ask() {
    local __var=$1 __question=$2 __default=$3 __hint=${4:-} __reply
    blank
    if [ -n "$__default" ]; then
        printf '  %s%s%s  %s[%s]%s\n' "$C_BOLD" "$__question" "$C_RESET" "$C_DIM" "$__default" "$C_RESET"
    else
        printf '  %s%s%s  %s[empty]%s\n' "$C_BOLD" "$__question" "$C_RESET" "$C_DIM" "$C_RESET"
    fi
    [ -z "$__hint" ] || hint "$__hint"
    read_line __reply
    [ -n "$__reply" ] || __reply=$__default
    printf -v "$__var" '%s' "$__reply"
}

# A numbered menu. Each option is "value|label"; the label may be empty. Enter
# takes the default, a number picks by position, and typing the value itself
# also works, so `squash` and `1` are the same answer. The hint may be empty.
#
#   choose VAR "question" default_value "hint" "value|label" "value|label" ...
choose() {
    local __var=$1 __question=$2 __default=$3 __hint=$4; shift 4
    local __opts=("$@") __i __value __label __reply __n=${#__opts[@]} __mark
    blank
    printf '  %s%s%s\n' "$C_BOLD" "$__question" "$C_RESET"
    [ -z "$__hint" ] || hint "$__hint"
    __i=0
    while [ "$__i" -lt "$__n" ]; do
        __value=${__opts[$__i]%%|*}
        __label=${__opts[$__i]#*|}
        [ "$__label" != "${__opts[$__i]}" ] || __label=''
        __mark='  '
        [ "$__value" != "$__default" ] || __mark="$G_DOT "
        printf '    %s%s%s%d  %s%-9s%s %s%s%s\n' \
            "$C_DIM" "$__mark" "$C_RESET" $((__i + 1)) "$C_BOLD" "$__value" "$C_RESET" \
            "$C_DIM" "$__label" "$C_RESET"
        __i=$((__i + 1))
    done
    while :; do
        read_line __reply
        if [ -z "$__reply" ]; then
            printf -v "$__var" '%s' "$__default"; return
        fi
        __i=0
        while [ "$__i" -lt "$__n" ]; do
            __value=${__opts[$__i]%%|*}
            if [ "$__reply" = "$((__i + 1))" ] || [ "$__reply" = "$__value" ]; then
                printf -v "$__var" '%s' "$__value"; return
            fi
            __i=$((__i + 1))
        done
        hint "type a number from 1 to $__n, or press Enter for the default"
    done
}
