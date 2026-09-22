# The settings file and the questions that fill it. Sourced by
# install/install.sh; not run on its own.
#
# There is one list of keys, in `project/flow-factory.toml`, and the questions
# live in it beside the keys they set. This file reads that template and gives
# the installer the questions in order; nothing here knows a key by name.
#
# An annotation is a comment line `# <field>: <text>`, continued on any number
# of following lines beginning with a hash and three spaces. The fields are:
#
#   ask      the question, as the user reads it
#   hint     one paragraph under it, wrapped by the caller
#   group    core, optional or defaults: which part of the flow asks it
#   choice   `value | label`, repeated once per option, making it a menu
#   detect   the name of a detector below, minus its `detect_` prefix
#   verify   the name of a validator below, minus its `verify_` prefix
#
# The `unset:` tag is read the same way but is the project's, not the
# installer's: the settings contract gives it to every key, so it stays in the
# file the project gets. Its first word says what a skill does when the value
# is empty, and `stop` is the one the installer reports back at the end.
#
# Two things are deliberately not annotations. The kind of a value is read off
# the template's own value, because `[]` is a list and `true` is a boolean and
# nothing else can be meant. The fallback default is that same value, so a key
# cannot claim a default different from the one the file ships.
#
# The annotations are stripped when the file is written into a project. They
# are the installer's, and the project's copy is settings.
#
# The user types plain values and never TOML. Everything they answer goes
# through toml_value on the way in and toml_raw on the way out, so no answer
# can write a line a skill cannot read, and an existing file's answers come
# back as the plain defaults for the next install.

# --- TOML in and out --------------------------------------------------------

# Escape what TOML treats as special inside a quoted string. Backslash first,
# or the backslashes this adds get escaped a second time.
esc() {
    local v=$1
    v=${v//\\/\\\\}
    v=${v//\"/\\\"}
    printf '%s' "$v"
}

trim() {
    local v=$1
    v=${v#"${v%%[![:space:]]*}"}
    v=${v%"${v##*[![:space:]]}"}
    printf '%s' "$v"
}

# Plain answer to TOML. A list is comma separated on the way in.
toml_value() {
    local kind=$1 raw=$2 out i item
    case $kind in
        string) printf '"%s"' "$(esc "$raw")" ;;
        bool)
            case $raw in
                true|yes|y|1) printf 'true' ;;
                *)            printf 'false' ;;
            esac
            ;;
        list)
            if [ -z "$raw" ]; then printf '[]'; return; fi
            # read -a rather than word splitting, which would let a glob in an
            # answer match the disk.
            local parts=()
            IFS=, read -ra parts <<< "$raw"
            out="["
            for i in "${!parts[@]}"; do
                item=$(trim "${parts[$i]}")
                [ -n "$item" ] || continue
                [ "$out" = "[" ] || out="$out, "
                out="$out\"$(esc "$item")\""
            done
            printf '%s]' "$out"
            ;;
    esac
}

# TOML back to the plain form the user types: quotes stripped, a list joined
# with commas. Good enough for the flat, single-line values this file holds.
toml_raw() {
    local kind=$1 toml=$2 v
    case $kind in
        string)
            v=${toml#\"}; v=${v%\"}
            v=${v//\\\"/\"}; v=${v//\\\\/\\}
            printf '%s' "$v"
            ;;
        bool) printf '%s' "$toml" ;;
        list)
            v=${toml#[}; v=${v%]}
            v=$(printf '%s' "$v" | sed -e 's/", *"/, /g' -e 's/^ *"//' -e 's/" *$//' \
                                       -e 's/\\"/"/g' -e 's/\\\\/\\/g')
            printf '%s' "$v"
            ;;
    esac
}

# The kind of a key, read off the value the template ships for it.
toml_kind() {
    case $1 in
        \[*)        printf 'list' ;;
        true|false) printf 'bool' ;;
        *)          printf 'string' ;;
    esac
}

# --- the questions ----------------------------------------------------------

Q_KEYS=() Q_VALUE=() Q_ASK=() Q_HINT=() Q_GROUP=() Q_DETECT=() Q_VERIFY=() Q_CHOICES=() Q_UNSET=()

# Read the template into the arrays above, in the order the file lists the
# keys. That order is the order the questions are asked, so moving a key in
# the template moves its question.
load_questions() {
    local template=$1 key field value last='' i=-1 v l
    while IFS=$'\t' read -r key field value; do
        if [ "$key" != "$last" ]; then
            i=$((i + 1)); last=$key
            Q_KEYS[$i]=$key Q_VALUE[$i]='' Q_ASK[$i]='' Q_HINT[$i]=''
            Q_GROUP[$i]='' Q_DETECT[$i]='' Q_VERIFY[$i]='' Q_CHOICES[$i]='' Q_UNSET[$i]=''
        fi
        case $field in
            value)  Q_VALUE[$i]=$value  ;;
            unset)  Q_UNSET[$i]=${value%% *} ;;
            ask)    Q_ASK[$i]=$value    ;;
            hint)   Q_HINT[$i]=$value   ;;
            group)  Q_GROUP[$i]=$value  ;;
            detect) Q_DETECT[$i]=$value ;;
            verify) Q_VERIFY[$i]=$value ;;
            choice)
                v=$(trim "${value%%|*}"); l=$(trim "${value#*|}")
                Q_CHOICES[$i]="${Q_CHOICES[$i]:+${Q_CHOICES[$i]}$'\n'}$v|$l"
                ;;
        esac
    done < <(awk '
        /^# (ask|hint|group|detect|verify|choice|unset): / {
            line = $0; sub(/^# /, "", line)
            f = line; sub(/:.*$/, "", f)
            v = line; sub(/^[a-z]+: /, "", v)
            if (f == "choice") { choices[++nc] = v; cur = "choice"; curi = nc }
            else               { fields[f] = v;     cur = f }
            next
        }
        # A continuation of the annotation above, joined with one space.
        /^#   / {
            if (cur != "") {
                line = $0; sub(/^#   /, "", line)
                if (cur == "choice") choices[curi] = choices[curi] " " line
                else                 fields[cur]   = fields[cur] " " line
                next
            }
        }
        /^[a-z][a-z_.]* = / {
            key = $0; sub(/ = .*$/, "", key)
            val = $0; sub(/^[^=]*= /, "", val)
            printf "%s\tvalue\t%s\n", key, val
            for (f in fields) printf "%s\t%s\t%s\n", key, f, fields[f]
            for (j = 1; j <= nc; j++) printf "%s\tchoice\t%s\n", key, choices[j]
            split("", fields); split("", choices); nc = 0; cur = ""
            next
        }
        { cur = "" }
    ' "$template")
    [ "$i" -ge 0 ] || die "no keys found in $template" \
        "The settings template in this checkout is empty or unreadable."
}

# The position of a key in the arrays. Every caller has the key from the
# template, so a miss is a programming error rather than bad input.
q_find() {
    local key=$1 i
    for i in "${!Q_KEYS[@]}"; do
        [ "${Q_KEYS[$i]}" = "$key" ] || continue
        printf '%s' "$i"; return 0
    done
    die "no such settings key: $key"
}

# Every key in one group, one per line, in template order.
q_group() {
    local want=$1 i
    for i in "${!Q_KEYS[@]}"; do
        [ "${Q_GROUP[$i]}" = "$want" ] && printf '%s\n' "${Q_KEYS[$i]}"
    done
    return 0
}

# grep -c prints 0 and exits 1 when a group is empty, which pipefail would
# turn into a failed install rather than a count of none.
q_count() {
    local n
    n=$(q_group "$1" | grep -c . || true)
    printf '%s' "${n//[^0-9]/}"
}

# Every key carries a question and a group, and the group is one the installer
# asks. A key added to the template without them would otherwise be written
# with its default and never put to the user, which is the drift this layout
# exists to prevent.
check_questions() {
    local i key
    for i in "${!Q_KEYS[@]}"; do
        key=${Q_KEYS[$i]}
        [ -n "${Q_ASK[$i]}" ] \
            || die "the settings template has no 'ask:' line for $key" \
                   "Every key needs a question beside it. This is a factory bug."
        [ -n "${Q_UNSET[$i]}" ] \
            || die "the settings template has no 'unset:' tag for $key" \
                   "The settings contract gives every key one. This is a factory bug."
        case ${Q_GROUP[$i]} in
            core|app|optional|defaults) ;;
            '') die "the settings template has no 'group:' line for $key" \
                    "Every key needs core, app, optional or defaults. This is a factory bug." ;;
            *)  die "$key has group '${Q_GROUP[$i]}', which the installer does not ask" \
                    "Use core, app, optional or defaults. This is a factory bug." ;;
        esac
    done
}

# --- the answers ------------------------------------------------------------

ANSWER_KEYS=() ANSWER_VALUES=() ANSWER_KINDS=()

# Record one answer. A key answered twice keeps the later answer.
answer() {
    local key=$1 kind=$2 raw=$3 i
    for i in "${!ANSWER_KEYS[@]}"; do
        if [ "${ANSWER_KEYS[$i]}" = "$key" ]; then
            ANSWER_VALUES[$i]=$(toml_value "$kind" "$raw")
            return
        fi
    done
    ANSWER_KEYS+=("$key")
    ANSWER_KINDS+=("$kind")
    ANSWER_VALUES+=("$(toml_value "$kind" "$raw")")
}

# Record an answer already in TOML form.
answer_toml() {
    local key=$1 kind=$2 toml=$3 i
    for i in "${!ANSWER_KEYS[@]}"; do
        if [ "${ANSWER_KEYS[$i]}" = "$key" ]; then
            ANSWER_VALUES[$i]=$toml
            return
        fi
    done
    ANSWER_KEYS+=("$key")
    ANSWER_KINDS+=("$kind")
    ANSWER_VALUES+=("$toml")
}

# Record a list from items given one at a time. Every other list is typed as
# one comma-separated line, which cannot carry an item containing a comma, and
# a start command frequently does.
answer_items() {
    local key=$1; shift
    local out='' item
    for item in "$@"; do
        [ -n "$out" ] && out="$out, " || out="["
        out="$out\"$(esc "$item")\""
    done
    [ -n "$out" ] && out="$out]" || out='[]'
    answer_toml "$key" list "$out"
}

# The plain form of a recorded answer, for the summary.
answered() {
    local key=$1 i
    for i in "${!ANSWER_KEYS[@]}"; do
        if [ "${ANSWER_KEYS[$i]}" = "$key" ]; then
            toml_raw "${ANSWER_KINDS[$i]}" "${ANSWER_VALUES[$i]}"
            return
        fi
    done
}

# The value a key already has in the project's settings file, in plain form.
# Prints nothing and fails when the file or the key is absent, which is not
# the same as a key whose value is empty: that one succeeds and prints
# nothing, because an empty value is an answer.
existing_toml_value() {
    local key=$1 raw
    [ -f "$EXISTING_SETTINGS" ] || return 1
    raw=$(grep -E "^$key = " "$EXISTING_SETTINGS" 2>/dev/null | head -1 \
        | sed -e "s/^$key = //" -e 's/ *$//')
    [ -n "$raw" ] || return 1
    printf '%s' "$raw"
}

existing_answer() {
    local key=$1 kind=$2 raw
    raw=$(existing_toml_value "$key") || return 1
    toml_raw "$kind" "$raw"
}

# The default to offer for a key: the project's current answer, then what the
# repository suggests, then the value the template ships.
#
# It sets two variables rather than printing, because a caller writing
# `x=$(key_default k)` runs it in a subshell, and the second answer, the file
# a suggestion came from, would be lost there with nothing to show for it. The
# first version of this did exactly that, and every question quietly stopped
# saying where its guess was from.
# KEY_DEFAULT_TOML carries the value in TOML as well, whenever the default came
# from a file rather than a detector. A list taken back unchanged has to be
# recorded from that, not from the plain form: the plain form is one comma
# separated line, and an app's start command carries commas of its own. Round
# tripping one through it split `run -x, -y` into two services' worth of list.
KEY_DEFAULT=''
KEY_DEFAULT_SOURCE=''
KEY_DEFAULT_TOML=''
key_default() {
    local key=$1 i kind raw have
    i=$(q_find "$key")
    kind=$(toml_kind "${Q_VALUE[$i]}")
    KEY_DEFAULT='' KEY_DEFAULT_SOURCE='' KEY_DEFAULT_TOML=''
    if have=$(existing_toml_value "$key"); then
        KEY_DEFAULT_TOML=$have
        KEY_DEFAULT=$(toml_raw "$kind" "$have")
        return
    fi
    if [ -n "${Q_DETECT[$i]}" ]; then
        raw=$("detect_${Q_DETECT[$i]}" "$PROJECT_ROOT")
        if [ -n "$raw" ]; then
            KEY_DEFAULT=${raw%%|*}
            KEY_DEFAULT_SOURCE=${raw#*|}
            [ "$KEY_DEFAULT_SOURCE" != "$raw" ] || KEY_DEFAULT_SOURCE=''
            return
        fi
    fi
    KEY_DEFAULT_TOML=${Q_VALUE[$i]}
    KEY_DEFAULT=$(toml_raw "$kind" "${Q_VALUE[$i]}")
}

# Write one key's value over the template's line for it.
set_key() {
    local file=$1 key=$2 value=$3 tmp
    tmp=$(mktemp)
    KEY="$key" VALUE="$value" awk '
        BEGIN { key = ENVIRON["KEY"]; value = ENVIRON["VALUE"]; done = 0 }
        $0 ~ "^" key " = " && !done { print key " = " value; done = 1; next }
        { print }
        END { if (!done) exit 1 }
    ' "$file" > "$tmp" || { rm -f -- "$tmp"; die "the settings template has no line for '$key'"; }
    mv -- "$tmp" "$file"
}

# Build the project's settings file: the template, which carries the comments
# and the `unset:` tag for every key, with every recorded answer written over
# its value and the installer's own annotations dropped. The same rule that
# parses an annotation drops it, so the two cannot disagree about what one is.
write_settings() {
    local template=$1 out=$2 i tmp tags_in tags_out
    tmp=$(mktemp)
    # The installer's fields go; `unset:` stays, because it is the project's.
    # The contract gives an unset tag to every key, and the project's copy is
    # what a reader of that project gets.
    awk '
        /^# (ask|hint|group|detect|verify|choice): / { skip = 1; next }
        /^#   / { if (skip) next }
        { skip = 0; print }
    ' "$template" > "$tmp"
    # Measured rather than trusted. An edit to the pattern above once took the
    # unset tags with it, and the file it produced looked entirely normal.
    tags_in=$(grep -c '^# unset: ' "$template" || true)
    tags_out=$(grep -c '^# unset: ' "$tmp" || true)
    [ "$tags_in" = "$tags_out" ] \
        || { rm -f -- "$tmp"; die "writing the settings file dropped $((tags_in - tags_out)) unset tags" \
                "The strip pattern in write_settings is taking more than the installer's own lines."; }
    for i in "${!ANSWER_KEYS[@]}"; do
        set_key "$tmp" "${ANSWER_KEYS[$i]}" "${ANSWER_VALUES[$i]}"
    done
    mv -- "$tmp" "$out"
}

# --- what the project can tell us -------------------------------------------
#
# A detector prints a suggestion, or a suggestion and the file it came from
# separated by a pipe, or nothing. A suggestion is a default the user
# confirms, never an answer written on its own: a repository showing one thing
# is the repository answering, not the project.

detect_default_branch() {
    local root=$1 ref
    # origin/HEAD is the remote's own answer, and beats whatever branch
    # happens to be checked out right now.
    ref=$(git -C "$root" symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null || true)
    if [ -n "$ref" ]; then printf '%s' "${ref#origin/}"; return; fi
    ref=$(git -C "$root" rev-parse --abbrev-ref HEAD 2>/dev/null || true)
    [ "$ref" = HEAD ] || printf '%s' "$ref"
}

detect_test_command() {
    local root=$1
    if [ -f "$root/package.json" ] && grep -q '"test"' "$root/package.json"; then
        if   [ -f "$root/pnpm-lock.yaml" ]; then printf 'pnpm test|package.json'
        elif [ -f "$root/yarn.lock" ];      then printf 'yarn test|package.json'
        elif [ -f "$root/bun.lockb" ] || [ -f "$root/bun.lock" ]; then printf 'bun test|package.json'
        else                                     printf 'npm test|package.json'
        fi
        return
    fi
    if [ -f "$root/pyproject.toml" ] || [ -f "$root/pytest.ini" ] || [ -f "$root/conftest.py" ] \
        || { [ -f "$root/setup.cfg" ] && grep -q pytest "$root/setup.cfg"; }; then
        if   [ -f "$root/uv.lock" ];     then printf 'uv run pytest|pyproject.toml'
        elif [ -f "$root/poetry.lock" ]; then printf 'poetry run pytest|pyproject.toml'
        else                                  printf 'pytest|pyproject.toml'
        fi
        return
    fi
    [ -f "$root/Cargo.toml" ] && { printf 'cargo test|Cargo.toml'; return; }
    [ -f "$root/go.mod" ]     && { printf 'go test ./...|go.mod'; return; }
    [ -f "$root/mix.exs" ]    && { printf 'mix test|mix.exs'; return; }
    [ -f "$root/Gemfile" ]    && { printf 'bundle exec rake test|Gemfile'; return; }
    [ -f "$root/pom.xml" ]    && { printf 'mvn test|pom.xml'; return; }
    [ -f "$root/gradlew" ]    && { printf './gradlew test|gradlew'; return; }
    if [ -f "$root/Makefile" ] && grep -qE '^test:' "$root/Makefile"; then
        printf 'make test|Makefile'; return
    fi
    return 0
}

detect_test_dir() {
    local root=$1 d
    for d in tests test spec __tests__; do
        [ -d "$root/$d" ] && { printf '%s' "$d"; return; }
    done
    return 0
}

detect_glossary() {
    local root=$1 f
    for f in docs/glossary.md docs/GLOSSARY.md GLOSSARY.md glossary.md; do
        [ -f "$root/$f" ] && { printf '%s' "$f"; return; }
    done
    return 0
}

# A validator prints why an answer will not do, and fails. Silence and success
# mean the answer stands.

verify_port() {
    local root=$1 value=$2
    [ -n "$value" ] || { printf 'a service needs a port'; return 1; }
    # Digits with at most one {NN}. Anything else becomes a listener pattern
    # that never matches, and the skill then waits on a port it thinks free.
    printf '%s' "$value" | grep -qE '^[0-9]*(\{NN\})?[0-9]*$' \
        || { printf 'digits, with {NN} for the suffix, as in 80{NN}'; return 1; }
}

verify_branch() {
    local root=$1 value=$2
    if [ -z "$value" ]; then
        printf 'this one cannot be empty'; return 1
    fi
    git -C "$root" show-ref --quiet --verify "refs/heads/$value" \
        || git -C "$root" show-ref --quiet --verify "refs/remotes/origin/$value" \
        || { printf "this repository has no branch '%s'" "$value"; return 1; }
}
