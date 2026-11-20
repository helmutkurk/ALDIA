#!/usr/bin/env bash
# PreToolUse(Bash): second line of defence behind permissions.deny.
# Every check runs (no first-match), so chained commands are fully inspected.
# Exit 2 = block; the reason on stderr is shown to Claude. Reads stdin directly (no subshell).
command -v jq >/dev/null || { echo "guard-bash: jq is required (see CONTRIBUTING.md)." >&2; exit 2; }
cmd=$(jq -r '.tool_input.command // ""')

# Heredoc bodies are data (scripts, docs), not commands: drop them before pattern checks so
# a script that merely mentions ".env.example" or "git push --force" is not mistaken for one.
cmd=$(printf '%s' "$cmd" | python3 -c '
import re, sys
out, delims = [], []
for line in sys.stdin.read().split("\n"):
    if delims:
        if line.strip() == delims[0]:
            delims.pop(0)
        continue
    out.append(line)
    for m in re.finditer(r"<<-?\s*[\x27\"]?([A-Za-z_][A-Za-z0-9_]*)[\x27\"]?", line):
        delims.append(m.group(1))
print("\n".join(out))
')

block() { echo "Blocked by project policy: $1. See AGENTS.md > Never do." >&2; exit 2; }
# Softer than block: collected here, emitted only after every block check passed.
ask_reason=""

# A tool invoked in command position: start, or after ; & | ( && || $( and optional sudo/env.
cmd_re() { echo "(^|[;&|(]|\\\$\\()[[:space:]]*((sudo|env|command)[[:space:]]+)*([^[:space:]]*/)?$1([[:space:]]|$)"; }

# 1. Publishing and repository-wide GitHub changes are human-only
if [[ "$cmd" =~ $(cmd_re gh) ]]; then
  [[ "$cmd" =~ gh[[:space:]]+repo[[:space:]]+(delete|edit|create|archive) ]] && block "no gh repo changes (visibility, delete, create); a human does this, see docs/public-release.md"
  [[ "$cmd" =~ gh[[:space:]]+pr[[:space:]]+merge[^\;\&\|]*--admin ]] && block "no admin merge from the agent; Helmut only, for the emergency exception (docs/adr/0006)"
  [[ "$cmd" =~ gh[[:space:]]+(secret|variable)[[:space:]] ]] && block "no gh secrets or variables from the agent"
  [[ "$cmd" =~ gh[[:space:]]+api[^\;\&\|]*(-X|--method)[[:space:]]*(DELETE|PUT|PATCH) ]] && block "no mutating gh api calls"
fi
if [[ "$cmd" =~ (npm|pnpm|yarn)[[:space:]]+publish ]] || [[ "$cmd" =~ $(cmd_re npx)[^\;\&\|]*(vercel|netlify|wrangler|firebase)[^\;\&\|]*deploy ]]; then
  block "no publishing or deploying from the agent"
fi

# 3. Pipe-to-shell installs
if [[ "$cmd" =~ (curl|wget)[^\;\&]*\|[[:space:]]*(sudo[[:space:]]+)?(ba|z|da)?sh([[:space:]]|$) ]]; then
  block "no piping downloads into a shell"
fi

# 4. Skipping hooks
if [[ "$cmd" =~ git[[:space:]]+(commit|push|merge|rebase)[^\;\&\|]*--no-verify ]]; then
  block "no --no-verify; fix the hook failure instead"
fi

# 5. Any token starting with .env (incl. globs like .env*), except .env.example / .env.sample / .env.*.example
set -f # inspect tokens as typed: no pathname expansion of globs like .* in the loops below
for tok in $cmd; do
  tok=${tok//[\'\"<>]/}; tok=${tok#*=}
  base=${tok##*/}
  if [[ "$base" == .env* && "$base" != ".env.example" && "$base" != ".env.sample" && "$base" != .env.*.example ]]; then
    block "do not read, write or create .env files; use .env.example"
  fi
  # Globs that expand to a .env file (.[e]nv, .e*, .*, [.]env). A leading * or ? never matches
  # dotfiles in bash, so apps/* is fine. $base stays unquoted: it is the pattern.
  if [[ "$base" == *[\*\?\[]* && "$base" != [\*\?]* ]]; then
    for env_file in .env .env.local .env.production; do
      # shellcheck disable=SC2053
      [[ "$env_file" == $base ]] && block "glob '$base' would match $env_file; name the file explicitly"
    done
  fi
  # Key material and the personal invoice folder
  case "$base" in
    *.skey|*.pem|*.p12|*.pfx|*mnemonic*.txt|*seed-phrase*) block "key material must not be read or moved by the agent" ;;
  esac
  case "$tok" in
    invoice|invoice/*|*/invoice|*/invoice/*) block "invoice/ holds Helmut's personal receipts; never touch it" ;;
  esac
done

# 6. New npm dependencies need a reason in the commit message -> ask (bare install / ci is fine)
if [[ "$cmd" =~ (npm|pnpm|yarn)[[:space:]]+(install|i|add)[[:space:]]+[^-\;\&\|] ]]; then
  ask_reason="new dependency: pinned versions only, one-line reason in the commit message (AGENTS.md > Dependencies)"
fi

# 7. git push: develop is allowed (explicit or implicit), never main/master, never forced
if [[ "$cmd" =~ git[[:space:]]+push ]]; then
  push_args=${cmd#*git push}
  push_args=${push_args%%[;&|]*}
  positional=0; lease=0
  for arg in $push_args; do
    case "$arg" in
      --force-with-lease*) lease=1; continue ;;
      --force|-f|--force=*|--mirror|--delete|-d) block "no force push, mirror or delete; never rewrite shared history (develop/main)" ;;
      --all) block "no push --all; push develop or one named branch" ;;
      -*) continue ;;
    esac
    positional=$((positional + 1))
    [[ $positional -eq 1 ]] && continue # remote name
    dest=${arg##*:}; dest=${dest#+}; dest=${dest#refs/heads/}
    if [[ "$dest" == "HEAD" ]]; then
      dest=$(git -C "${CLAUDE_PROJECT_DIR:-.}" branch --show-current 2>/dev/null)
    fi
    [[ "$dest" == "main" || "$dest" == "master" ]] \
      && block "main only via the release PR develop -> main; push to develop instead"
    [[ $lease -eq 1 && "$dest" == "develop" ]] && block "never force-push develop; fix forward with a new commit"
  done
  if [[ $positional -le 1 ]]; then
    cur=$(git -C "${CLAUDE_PROJECT_DIR:-.}" branch --show-current 2>/dev/null)
    [[ "$cur" == "main" || "$cur" == "master" ]] \
      && block "you are on $cur; main only via the release PR develop -> main. Switch to develop"
    [[ $lease -eq 1 && "$cur" == "develop" ]] && block "never force-push develop; fix forward with a new commit"
  fi
fi

if [[ -n "$ask_reason" ]]; then
  jq -n --arg r "Project policy: $ask_reason" \
    '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "ask", permissionDecisionReason: $r}}'
fi
exit 0
