#!/bin/sh
# Shared body of the Bash PreToolUse guards in hooks.json:
#
#   sh git-guard.sh commit|merge|push|gh-api   (hook JSON on stdin)
#
# Claude Code's `if` filter is best-effort. A guard also runs when only one
# part of a compound command matches (`npm test && git push`), and on commands
# it can't take apart at all ($(...), heredocs, loops, several lines). Either
# way the guard sees the whole command string. So each guard first finds the
# parts of the command that really invoke its subcommand, and decides from
# those parts' arguments only. No such part -> no decision at all: the call
# goes through the normal permission flow, as if this hook didn't exist.
#
# If the command can't be read (no jq/python3/node, empty payload), the guard
# behaves as it did before it read commands: it assumes a matching part
# exists, so it may ask more often but never lets through what it used to stop.
#
# How a command is taken apart (find_parts below):
#   - heredoc bodies are dropped, from a `<<[-]['"]WORD` marker to the line
#     equal to WORD;
#   - quote characters are dropped, and whatever was inside quotes stays in
#     one word, so `echo "git push origin main"` is one echo with one argument;
#   - the rest is split on && || ; | & ( ) ` and newlines;
#   - a part matches when it reads `git [global options] <sub>` (after leading
#     VAR=value assignments and shell keywords such as `then`/`do`), where the
#     global options covered are -C, -c, --git-dir, --work-tree, --namespace,
#     --config-env and any single-word option.
#
# Deliberately not handled — these run git without the guard seeing it:
#   eval, sh -c '...', bash -c '...', xargs git ..., git aliases, a git binary
#   called by full path, $(...) written inside double quotes, functions,
#   a here-string (<<<) or a heredoc marker inside quotes, two heredocs
#   started on one line. And the guards check the repository the hook runs
#   in: `cd other && git commit` or `git -C other push` are parsed, but the
#   branch and the diff are read from the current repository.
# The guards are a confirmation layer for honest agent commands, not a
# security boundary; permissions.deny is that.

mode=$1
input=$(cat)

# json_get <dotted.path> [file]: print a string field from JSON on stdin or
# from a file; empty when no parser is available or the field is absent.
json_get() {
  if command -v jq >/dev/null 2>&1; then
    jq -r ".$1 // empty" ${2:+"$2"} 2>/dev/null
  elif command -v python3 >/dev/null 2>&1; then
    python3 -c 'import json,sys
f=open(sys.argv[2]) if len(sys.argv)>2 else sys.stdin
try: d=json.load(f)
except Exception: d={}
for k in sys.argv[1].split("."): d=d.get(k) if isinstance(d,dict) else None
print(d if isinstance(d,str) else "")' "$1" ${2:+"$2"} 2>/dev/null
  elif command -v node >/dev/null 2>&1; then
    node -e 'const fs=require("fs");let d={};try{d=JSON.parse(fs.readFileSync(process.argv[2]||0,"utf8"))}catch(e){}for(const k of process.argv[1].split("."))d=d&&typeof d==="object"?d[k]:undefined;process.stdout.write(typeof d==="string"?d:"")' "$1" ${2:+"$2"} 2>/dev/null
  fi
}

cmd=$(printf '%s' "$input" | json_get tool_input.command)

# find_parts <sub>...: one line per matching part, "<sub> <args>". A quoted
# string keeps its spaces as \037 so it stays one word; callers that need the
# real text back translate it.
find_parts() {
  printf '%s\n' "$cmd" | awk -v want=" $* " '
    function emit(seg,   t, n, k, off) {
      n = split(seg, t, /[ \t]+/)
      k = 1
      while (k <= n && t[k] == "") k++
      # HUSKY=0 before git, or git -c core.hooksPath=..., skips the git hooks
      # just as --no-verify does, so the part carries that flag for the guards.
      while (k <= n && (t[k] ~ /^[A-Za-z_][A-Za-z0-9_]*=/ || t[k] ~ /^(!|\{|if|then|elif|else|do|while|until|time)$/)) {
        if (t[k] == "HUSKY=0") off = 1
        k++
      }
      if (want == " gh-api ") {
        if (t[k] != "gh" || t[k + 1] != "api") return
        out = "gh-api"; k += 2
      } else {
        if (t[k] != "git") return
        k++
        while (k <= n && t[k] ~ /^-/) {
          if (t[k] ~ /^(-C|-c|--git-dir|--work-tree|--namespace|--config-env)$/) {
            if (t[k] == "-c" && tolower(t[k + 1]) ~ /^core\.hookspath=/) off = 1
            k++
          }
          k++
        }
        if (k > n || index(want, " " t[k] " ") == 0) return
        out = t[k]; k++
      }
      for (; k <= n; k++) if (t[k] != "") out = out " " t[k]
      if (off) out = out " --no-verify"
      print out
    }
    {
      if (hd != "") {                      # inside a heredoc body
        line = $0
        if (hdtab) sub(/^\t+/, "", line)
        if (line == hd) hd = ""
        next
      }
      line = $0; rest = ""
      # Find a heredoc marker, skipping here-strings (<<<).
      while (match(line, /<<-?[ \t]*["\047]?[A-Za-z_][A-Za-z0-9_]*["\047]?/)) {
        m = substr(line, RSTART, RLENGTH)
        before = substr(line, 1, RSTART - 1)
        if (before ~ /<$/) { rest = rest before m; line = substr(line, RSTART + RLENGTH); continue }
        hdtab = (m ~ /^<<-/)
        hd = m; sub(/^<<-?[ \t]*["\047]?/, "", hd); sub(/["\047]$/, "", hd)
        line = before substr(line, RSTART + RLENGTH)
        break
      }
      text = text rest line "\n"
    }
    END {
      n = length(text); q = ""; seg = ""
      for (i = 1; i <= n; i++) {
        c = substr(text, i, 1)
        if (q != "") {                      # inside quotes: one word, no splits
          if (c == q) q = ""
          else if (q == "\"" && c == "\\" && i < n) { i++; seg = seg substr(text, i, 1) }
          else seg = seg (c ~ /[ \t\n]/ ? "\037" : c)
          continue
        }
        if (c == "\\" && i < n) { i++; c = substr(text, i, 1); seg = seg (c == "\n" ? " " : c); continue }
        if (c == "\047" || c == "\"") { q = c; continue }
        if (c ~ /[;&|()`\n]/) { emit(seg); seg = ""; continue }
        seg = seg c
      }
      emit(seg)
    }'
}

decide() { # decide ask|allow [reason]
  if [ "$1" = allow ]; then
    echo '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow"}}'
  else
    printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"ask","permissionDecisionReason":"%s"}}\n' "$2"
  fi
  exit 0
}

# ask_if_unsafe_branch <verb>: the protected-branch and detached-HEAD asks
# every git guard shares.
ask_if_unsafe_branch() {
  [ -z "$branch" ] && decide ask "Detached HEAD: cannot verify this is not the protected branch, confirm before $1."
  if [ "$branch" = "$protected" ] || { [ -z "$default" ] && [ "$branch" = master ]; }; then
    case "$1" in
      committing) decide ask "Committing directly on $branch requires confirmation." ;;
      merging) decide ask "Merging into $branch requires confirmation." ;;
      pushing) decide ask "Pushing while on $branch requires confirmation." ;;
    esac
  fi
}

# words <lines>: one argument per line, the subcommand name itself dropped.
words() { printf '%s\n' "$1" | awk '{ for (i = 2; i <= NF; i++) print $i }'; }

set -f   # arguments are split into words below, never glob-expanded

if [ "$mode" = gh-api ]; then
  # A write to git/refs or git/commits creates history without any local
  # hook seeing it. Fields (-f/-F) mean POST unless a method says otherwise.
  find_parts gh-api | while IFS= read -r part; do
    method=''; fields=''; target=''; prev=''
    for w in $part; do
      case "$prev" in -X|--method) method=$w ;; esac
      case "$w" in
        -X?*) method=${w#-X} ;;
        --method=*) method=${w#--method=} ;;
        -f|-F|--field|--raw-field|--input|--field=*|--raw-field=*|--input=*) fields=1 ;;
        *git/refs*|*git/commits*) target=1 ;;
      esac
      prev=$w
    done
    method=$(printf '%s' "${method:-${fields:+POST}}" | tr '[:lower:]' '[:upper:]')
    case "$method" in POST|PATCH|PUT|DELETE)
      [ -n "$target" ] && decide ask "Creating commits/refs through the GitHub API bypasses local git hooks; confirm." ;;
    esac
  done
  exit 0
fi

parts=$(find_parts "$mode" add)
mine=$(printf '%s\n' "$parts" | awk -v m="$mode" '$1 == m')
[ -n "$cmd" ] && [ -z "$mine" ] && exit 0

default=$(git symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null | sed 's@^origin/@@')
branch=$(git symbolic-ref --short -q HEAD 2>/dev/null)
protected="${default:-main}"

case "$mode" in
merge)
  ask_if_unsafe_branch merging
  decide allow
  ;;

push)
  ask_if_unsafe_branch pushing
  args=$(words "$mine")
  if printf '%s\n' "$args" | grep -qE -- '^(--force|--force-with-lease(=.*)?|\+.+|-[a-zA-Z]*f[a-zA-Z]*)$'; then
    decide ask "Force-push requires confirmation."
  fi
  # Skipping .husky/pre-push skips its tests, services check and audit; the
  # harness forbids it (opsx-apply-git references/ci-probes.md).
  if printf '%s\n' "$args" | grep -qxF -- --no-verify; then
    decide ask "This push skips .husky/pre-push (--no-verify, HUSKY=0 or core.hooksPath): its tests and audit won't run. Confirm."
  fi
  # Destination of each refspec: drop a leading +, everything up to the last
  # colon, and refs/heads/. Options and their values never equal a branch.
  refs=$(printf '%s\n' "$args" | grep -v '^-' | sed -e 's@^+@@' -e 's@^.*:@@' -e 's@^refs/heads/@@')
  if printf '%s\n' "$refs" | grep -qxF -- "$protected" || { [ -z "$default" ] && printf '%s\n' "$refs" | grep -qxF master; }; then
    decide ask "Push command references the protected branch by name; confirm target."
  fi
  decide allow
  ;;

commit)
  ask_if_unsafe_branch committing
  # The hook runs before the command, so a `git add` earlier in the same
  # command hasn't touched the index yet. Replay those adds on a throwaway
  # copy of the index and measure that: it is what the commit will contain,
  # renames included. A replay that fails (paths relative to a `cd` earlier
  # in the command, say) leaves the copy as the index is now, which still
  # never measures the whole dirty tree.
  # Known gap: `git commit <pathspec>` commits those paths' working-tree
  # state; it is measured as the staged diff.
  adds=$(printf '%s\n' "$parts" | awk '$1 == "commit" { exit } $1 == "add"')
  if [ -n "$adds" ] && idx=$(git rev-parse --git-path index 2>/dev/null) && [ -f "$idx" ]; then
    tmp=$(mktemp) && cp "$idx" "$tmp" && GIT_INDEX_FILE=$tmp && export GIT_INDEX_FILE
    trap 'rm -f "$tmp"' EXIT
    printf '%s\n' "$adds" | while IFS= read -r part; do
      set --
      for w in $part; do set -- "$@" "$(printf '%s' "$w" | tr '\037' ' ')"; done
      shift
      git add "$@" >/dev/null 2>&1
    done
  fi
  # -a / --all / a combined short flag with `a` before any value-taking
  # letter (-am yes, -mall no) commits tracked changes, staged or not; `n`
  # the same way (-n, -nm) is --no-verify.
  against=--cached
  no_verify=
  for w in $(words "$mine"); do
    case "$w" in
      --all) against=HEAD ;;
      --no-verify) no_verify=1 ;;
      --*) ;;
      -*) f=${w#-}
          while [ -n "$f" ]; do
            case "$f" in
              a*) against=HEAD ;;
              n*) no_verify=1 ;;
              [mFCctuS]*) break ;;
            esac
            f=${f#?}
          done ;;
    esac
  done
  # Skipping .husky/pre-commit skips its typecheck and lint; the harness
  # forbids it (opsx-apply-git references/ci-probes.md).
  [ -n "$no_verify" ] && decide ask "This commit skips .husky/pre-commit (--no-verify, -n, HUSKY=0 or core.hooksPath): typecheck and lint won't run. Confirm."
  diff=$(git diff $against)
  # Unreadable command: keep the old fallback to the whole tree when nothing
  # is staged, rather than allow what used to be asked about.
  if [ -z "$cmd" ] && [ -z "$diff" ]; then against=HEAD; diff=$(git diff HEAD); fi
  scan=$(printf '%s\n' "$diff" | grep -vE 'process\.env|import\.meta\.env|os\.environ|ENV\[')
  if printf '%s' "$scan" | grep -qEi -- '-----BEGIN [A-Z ]*PRIVATE KEY-----|AKIA[0-9A-Z]{16}|(secret|api)_?key[[:space:]]*[:=][[:space:]]*["'"'"']?[A-Za-z0-9/+_.-]{16,}|password[[:space:]]*[:=][[:space:]]*[^[:space:]]{8,}'; then
    decide ask "Staged diff matches a secret-like pattern (API key, private key block, or hardcoded password). Confirm before committing."
  fi
  # The size threshold is about what a person reviews line by line, so the
  # manifest's lockfile (generated, never read that way) is left out of the
  # count. It stays in the secret scan above.
  lock=$(json_get lockfile .claude/harness.json </dev/null)
  stat=$(git diff $against -M --shortstat -- ':/' ${lock:+":(top,exclude)$lock"})
  ins=$(printf '%s' "$stat" | grep -oE '[0-9]+ insertion' | grep -oE '[0-9]+')
  del=$(printf '%s' "$stat" | grep -oE '[0-9]+ deletion' | grep -oE '[0-9]+')
  lines=$(( ${ins:-0} + ${del:-0} ))
  [ "$lines" -gt 500 ] && decide ask "Large commit ($lines changed lines) - confirm this is intentional."
  decide allow
  ;;
esac
