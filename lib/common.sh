# a2a-check reference package for claude-code: shared functions (R-37, R-38, R-05,
# R-08, R-44; MVP-R-23, decision 0048). POSIX sh and curl only; sourced by
# bin/a2a-check and hooks/a2a-check-hook.
#
# Environment:
#   A2A_CHECK_URL     base URL of the service, e.g. https://check.example
#   A2A_AGENT_TOKEN   the agent's token; read from here only, never written to a
#                     file or printed, and handed to curl on stdin, not argv
#   A2A_CHECK_MODE    beobachten (default) or senden; anything else is refused
#   A2A_CHECK_DIR     local directory for everything the package writes
#                     (default: $CLAUDE_PROJECT_DIR/.a2a-check)
#   A2A_CHECK_NOW     fixed time for the report's occurred_at (tests only)

# shellcheck shell=sh

a2a_say() { printf '%s\n' "$*"; }
a2a_err() { printf 'a2a-check: %s\n' "$*" >&2; }

# Sets MODE, A2A_PROJECT, A2A_DIR. Exit code 2 on a mode that is not one of the
# two (R-38: exactly two modes).
a2a_init() {
  case "${A2A_CHECK_MODE:-}" in
    ''|beobachten) MODE=beobachten ;;
    senden) MODE=senden ;;
    *) a2a_err "unknown mode '${A2A_CHECK_MODE}': use beobachten or senden"; return 2 ;;
  esac
  A2A_PROJECT=${CLAUDE_PROJECT_DIR:-.}
  A2A_DIR=${A2A_CHECK_DIR:-$A2A_PROJECT/.a2a-check}
  A2A_BODY="$A2A_DIR/.response"
  A2A_PATTERNS="$A2A_LIB/sensitive-patterns.ere"
  return 0
}

a2a_now() {
  if [ -n "${A2A_CHECK_NOW:-}" ]; then printf '%s\n' "$A2A_CHECK_NOW"
  else date -u '+%Y-%m-%dT%H:%M:%SZ'; fi
}

# One request to the service with the agent token as bearer. The token goes to
# curl on stdin (-K -), so it is in no process listing. Prints the HTTP status;
# the body is left in $A2A_BODY. Returns 1 without a request when URL or token
# is missing. A2A_MAX_TIME (seconds, default 30) is the request's time limit.
a2a_api() {
  _method=$1; _path=$2; shift 2
  [ -n "${A2A_CHECK_URL:-}" ] && [ -n "${A2A_AGENT_TOKEN:-}" ] || return 1
  mkdir -p "$A2A_DIR"
  printf 'header = "Authorization: Bearer %s"\n' "$A2A_AGENT_TOKEN" |
    curl -sS -K - -X "$_method" --max-time "${A2A_MAX_TIME:-30}" -o "$A2A_BODY" -w '%{http_code}' \
      "$@" "${A2A_CHECK_URL%/}$_path" 2>/dev/null
}

# R-05: the agent reads its own release rule. Writes policy.json (the five
# values, no secret) and returns 0 on a 200, 1 otherwise.
a2a_read_policy() {
  _code=$(a2a_api GET /v1/agent/sharing-policy) || return 1
  [ "$_code" = 200 ] || { rm -f "$A2A_BODY"; return 1; }
  tr -d '\n' < "$A2A_BODY" > "$A2A_DIR/policy.json"
  rm -f "$A2A_BODY"
  return 0
}

# allowed only when the rule says so; a missing or unreadable rule is blocked.
a2a_policy_value() {
  _v=$(sed -n "s/.*\"$1\"[[:space:]]*:[[:space:]]*\"\\([a-z]*\\)\".*/\\1/p" \
    "$A2A_DIR/policy.json" 2>/dev/null)
  if [ "$_v" = allowed ]; then a2a_say allowed; else a2a_say blocked; fi
}

# ---------------------------------------------------------------- selection

# Project-relative paths of the configuration files, sorted. The package's own
# skills are not part of the agent's configuration. The project's shared settings
# (.claude/settings.json: permissions, hooks) and its MCP servers (.mcp.json) are:
# the Netzwerk, Autorität and Loop rules read them (decision 0075). The personal
# .claude/settings.local.json is never selected: it is per machine and per person.
a2a_select_configuration() {
  ( cd "$A2A_PROJECT" 2>/dev/null || exit 0
    for _f in CLAUDE.md .claude/CLAUDE.md .claude/settings.json .mcp.json \
        .claude/agents/*.md .claude/commands/*.md \
        .claude/rules/*.md .claude/skills/*/SKILL.md; do
      [ -f "$_f" ] || continue
      case $_f in .claude/skills/a2a-check/*|.claude/skills/a2a-check-apply/*) continue ;; esac
      printf '%s\n' "$_f"
    done | sort -u )
}

# Loop definitions are named by the operator, one project-relative path per line
# in $A2A_DIR/loop-files; an absolute path or a path with '..' is ignored.
a2a_select_loop() {
  [ -f "$A2A_DIR/loop-files" ] || return 0
  while IFS= read -r _p || [ -n "$_p" ]; do
    case $_p in ''|'#'*|/*|*..*) continue ;; esac
    [ -f "$A2A_PROJECT/$_p" ] && printf '%s\n' "$_p"
  done < "$A2A_DIR/loop-files" | sort -u
}

# Copies what the release rule allows into $A2A_DIR/submission/<class>/ and
# writes the manifest. Blocked data classes are never read, let alone copied.
a2a_assemble() {
  rm -rf "$A2A_DIR/submission"
  mkdir -p "$A2A_DIR/submission"
  : > "$A2A_DIR/submission/manifest.txt"
  for _class in configuration loop; do
    [ "$(a2a_policy_value "$_class")" = allowed ] || continue
    "a2a_select_$_class" > "$A2A_DIR/.selected"
    while IFS= read -r _rel; do
      mkdir -p "$A2A_DIR/submission/$_class/$(dirname "$_rel")"
      cp "$A2A_PROJECT/$_rel" "$A2A_DIR/submission/$_class/$_rel"
      printf '%s\t%s\t%s\n' "$_class" "$_rel" "$(wc -c < "$A2A_PROJECT/$_rel" | tr -d ' ')" \
        >> "$A2A_DIR/submission/manifest.txt"
    done < "$A2A_DIR/.selected"
  done
  rm -f "$A2A_DIR/.selected"
}

# ----------------------------------------------------------- local detection

# Pattern hits as "file:line ID", never the matched text (R-44). Patterns are
# the credential and personal data shapes of catalog/patterns, written as POSIX
# extended expressions: ID, TAB, flag (i or -), TAB, expression.
a2a_scan_file() {
  _file=$1; _label=$2
  _tab=$(printf '\t')
  while IFS="$_tab" read -r _id _flag _ere; do
    case $_id in ''|'#'*) continue ;; esac
    _opt=-E; [ "$_flag" = i ] && _opt=-Ei
    grep -n $_opt -e "$_ere" "$_file" 2>/dev/null | cut -d: -f1 | sort -n -u |
      while read -r _line; do printf '%s:%s %s\n' "$_label" "$_line" "$_id"; done
  done < "$A2A_PATTERNS"
}

a2a_scan_submission() {
  [ -s "$A2A_DIR/submission/manifest.txt" ] || return 0
  while IFS="$(printf '\t')" read -r _class _rel _bytes; do
    a2a_scan_file "$A2A_DIR/submission/$_class/$_rel" "$_rel"
  done < "$A2A_DIR/submission/manifest.txt"
}

# ------------------------------------------------------------------- preview

a2a_german_class() {
  case $1 in configuration) a2a_say konfiguration ;; *) a2a_say "$1" ;; esac
}

# R-44: the selected files, the data classes and the sensitive content found
# locally, before anything is sent. Written to preview.txt and printed.
a2a_preview() {
  {
    a2a_say "a2a-check Vorschau (Betriebsart: $MODE)"
    a2a_say "Freigaberegel: configuration=$(a2a_policy_value configuration)" \
      "loop=$(a2a_policy_value loop)"
    for _class in configuration loop; do
      if [ "$(a2a_policy_value "$_class")" != allowed ]; then
        a2a_say "Datenklasse $(a2a_german_class "$_class"): gesperrt, nichts ausgewählt"
        continue
      fi
      _n=$(awk -F '\t' -v c="$_class" '$1 == c' "$A2A_DIR/submission/manifest.txt" | wc -l | tr -d ' ')
      a2a_say "Datenklasse $(a2a_german_class "$_class"): $_n Dateien"
      awk -F '\t' -v c="$_class" '$1 == c { print "  " $2 }' "$A2A_DIR/submission/manifest.txt"
      # The content, not only the names, is what a confirmation covers.
      [ "$_n" -gt 0 ] && a2a_say "  Prüfsumme: $(a2a_class_digest "$_class")"
    done
    a2a_say "Lokal erkannte sensible Inhalte (Fundstelle und Muster, ohne Inhalt):"
    a2a_scan_submission > "$A2A_DIR/.hits"
    if [ -s "$A2A_DIR/.hits" ]; then sed 's/^/  /' "$A2A_DIR/.hits"; else a2a_say "  keine"; fi
    rm -f "$A2A_DIR/.hits"
    a2a_say "Die lokale Prüfung ersetzt die Filter des Dienstes nicht und erkennt nicht alles."
  } > "$A2A_DIR/preview.txt"
  cat "$A2A_DIR/preview.txt"
}

# Checksum of one assembled data class: file names and contents, sorted.
a2a_class_digest() {
  ( cd "$A2A_DIR/submission/$1" 2>/dev/null && find . -type f | sort |
    while IFS= read -r _f; do printf '%s\n' "$_f"; cat "$_f"; done | cksum | cut -d' ' -f1 )
}

a2a_preview_digest() { cksum < "$A2A_DIR/preview.txt" | cut -d' ' -f1,2; }

# ------------------------------------------------------------------- reports

# What the package says about a run: fixed sentences, never a line of tool
# output, never a conversation excerpt (R-08, N-03).
a2a_impact() {
  case $1 in
    abort) a2a_say "The run was aborted before it finished." ;;
    budget_exceeded) a2a_say "The run stopped because its budget was used up." ;;
    tool_failed) a2a_say "A tool call failed during the run." ;;
    timeout) a2a_say "The run stopped because it took too long." ;;
    *) a2a_say "The run was reported by hand." ;;
  esac
}

a2a_rule_class() {
  case $1 in budget_exceeded) a2a_say authority ;; *) a2a_say exceptions ;; esac
}

# One report per trigger and component until `a2a-check reset`. Writes
# reports/<time>-<trigger>.json according to catalog/schema/failure-report-1.0.0.json
# and, in the mode senden, sends it when the release rule allows failure_report.
a2a_emit_report() {
  _trigger=$1; _component=$2
  _marker="$A2A_DIR/reported/$_trigger-$_component"
  [ -e "$_marker" ] && return 0
  mkdir -p "$A2A_DIR/reports" "$A2A_DIR/reported"
  _at=$(a2a_now)
  # Trigger and component are in the name: two reports of different components
  # in the same second are two files (and, in senden, two sends).
  _file="$A2A_DIR/reports/$(printf '%s' "$_at" | tr ':' '-')-$_trigger-$_component.json"
  {
    printf '{\n'
    printf '  "schema_version": "1.0.0",\n'
    printf '  "rule_class": "%s",\n' "$(a2a_rule_class "$_trigger")"
    printf '  "trigger": "%s",\n' "$_trigger"
    printf '  "observed_impact": "%s",\n' "$(a2a_impact "$_trigger")"
    printf '  "affected_components": [{"component": "%s"}],\n' "$_component"
    printf '  "occurred_at": "%s",\n' "$_at"
    printf '  "harness": "claude-code"\n'
    printf '}\n'
  } > "$_file"
  : > "$_marker"
  a2a_say "a2a-check: report written: $_file" >&2
  [ "$MODE" = senden ] && a2a_send_report "$_file"
  return 0
}

# R-37: nothing is sent that the release rule blocks. The rule is read fresh; a
# rule that cannot be read counts as blocked.
a2a_send_report() {
  _file=$1
  mkdir -p "$A2A_DIR/sent"
  _sent="$A2A_DIR/sent/$(basename "$_file")"
  [ -e "$_sent" ] && return 0
  a2a_read_policy || { a2a_err "release rule not readable, report stays local"; return 0; }
  [ "$(a2a_policy_value failure_report)" = allowed ] || {
    a2a_err "failure_report is blocked by the release rule, report stays local"; return 0; }
  _code=$(a2a_api POST /v1/submissions -F data_class=failure_report \
    -F "files=@$_file;type=application/json;filename=report.json") || return 0
  rm -f "$A2A_BODY"
  if [ "$_code" = 200 ]; then : > "$_sent"; a2a_err "report sent"
  else a2a_err "report not accepted (HTTP $_code), stays local"; fi
  return 0
}

# ----------------------------------------------------------------- hook input

# First value of a top-level string field of the hook's JSON input (the common
# fields and `tool_name` come before the tool's input in the payload, so text in
# a tool's input cannot stand in for them).
a2a_json_first() {
  printf '%s' "$1" | grep -o "\"$2\"[[:space:]]*:[[:space:]]*\"[^\"]*\"" | head -n 1 |
    sed 's/^[^:]*:[[:space:]]*"\(.*\)"$/\1/'
}

# Whether the payload of PostToolUseFailure says the user interrupted the call
# (`is_interrupt`). Only the flag is read; the `error` text is never kept.
a2a_is_interrupt() {
  printf '%s' "$1" | grep -Eq '"is_interrupt"[[:space:]]*:[[:space:]]*true'
}

a2a_tool_component() {
  case $1 in
    mcp__*) a2a_say connection_config ;;
    Bash) a2a_say command ;;
    *) a2a_say system_instructions ;;
  esac
}

# StopFailure: the turn ended because of an API error; `error` is one of the
# documented values. A used-up limit, quota or balance is a budget; every other
# error ended the run (abort). The error text itself is never kept.
a2a_stop_failure_trigger() {
  case $1 in
    rate_limit|billing_error|account_on_hold|max_output_tokens) a2a_say budget_exceeded ;;
    overloaded|authentication_failed|oauth_org_not_allowed|invalid_request|model_not_found|\
server_error|cloud_credential_error|unknown) a2a_say abort ;;
    *) : ;;
  esac
}
