#!/usr/bin/env bash

set -euo pipefail

readonly PROJECT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
readonly CONTROL="${PROJECT_DIR}/scripts/cn-inputctl"

test_root="$(mktemp -d)"
trap '[[ "$test_root" == /tmp/* ]] && rm -rf -- "$test_root"' EXIT

mock_bin="${test_root}/bin"
config_root="${test_root}/config"
data_root="${test_root}/data"
state_root="${test_root}/state"
shared_root="${test_root}/shared-rime"
mock_log="${test_root}/calls.log"
mkdir -p "$mock_bin" "$config_root/fcitx5" "$data_root" "$state_root" "$shared_root"
touch "$shared_root/rime_ice.schema.yaml" "$mock_log"

cat >"${mock_bin}/pacman" <<'MOCK'
#!/usr/bin/env bash
if [[ "${1:-}" == -Q ]]; then
  case "${2:-}" in
    fcitx5-rime) exit 0 ;;
    rime-ice-pinyin-git) [[ "${MOCK_RIME_INSTALLED:-1}" == 1 ]] ;;
    *) exit 1 ;;
  esac
fi
exit 1
MOCK

cat >"${mock_bin}/fcitx5-remote" <<'MOCK'
#!/usr/bin/env bash
case "${1:-}" in
  --check) exit 0 ;;
  -n) printf '%s\n' "${MOCK_IM:-keyboard-us}" ;;
  -s|-c|-o|-r) printf 'fcitx5-remote %s\n' "$*" >>"$MOCK_LOG" ;;
  '') printf '%s\n' "${MOCK_STATE:-1}" ;;
  *) exit 2 ;;
esac
MOCK

cat >"${mock_bin}/busctl" <<'MOCK'
#!/usr/bin/env bash
printf 'busctl %s\n' "$*" >>"$MOCK_LOG"
case " $* " in
  *' CurrentInputMethodGroup '*)
    printf '%s\n' '{"type":"s","data":["Default"]}'
    ;;
  *' InputMethodGroupInfo '*)
    if [[ "${MOCK_GROUP_HAS_RIME:-1}" == 1 ]]; then
      printf '%s\n' '{"type":"sa(ss)","data":["us",[["keyboard-us",""],["rime",""]]]}'
    else
      printf '%s\n' '{"type":"sa(ss)","data":["us",[["keyboard-us",""]]]}'
    fi
    ;;
esac
MOCK

cat >"${mock_bin}/rime_deployer" <<'MOCK'
#!/usr/bin/env bash
printf 'rime_deployer %s\n' "$*" >>"$MOCK_LOG"
mkdir -p -- "$4"
MOCK

cat >"${mock_bin}/omarchy" <<'MOCK'
#!/usr/bin/env bash
if [[ "${1:-}" == version ]]; then
  printf '4.0.0-1\n'
else
  printf 'omarchy %s\n' "$*" >>"$MOCK_LOG"
fi
MOCK

cat >"${mock_bin}/yay" <<'MOCK'
#!/usr/bin/env bash
printf 'yay %s\n' "$*" >>"$MOCK_LOG"
MOCK

cat >"${mock_bin}/systemctl" <<'MOCK'
#!/usr/bin/env bash
printf 'systemctl %s\n' "$*" >>"$MOCK_LOG"
MOCK

chmod +x "${mock_bin}/pacman" "${mock_bin}/fcitx5-remote" \
  "${mock_bin}/busctl" "${mock_bin}/rime_deployer" \
  "${mock_bin}/omarchy" "${mock_bin}/yay" "${mock_bin}/systemctl"

export XDG_CONFIG_HOME="$config_root"
export XDG_DATA_HOME="$data_root"
export XDG_STATE_HOME="$state_root"
export CN_INPUT_PACMAN="${mock_bin}/pacman"
export CN_INPUT_FCITX_REMOTE="${mock_bin}/fcitx5-remote"
export CN_INPUT_BUSCTL="${mock_bin}/busctl"
export CN_INPUT_RIME_DEPLOYER="${mock_bin}/rime_deployer"
export CN_INPUT_RIME_SHARED_DIR="$shared_root"
export CN_INPUT_OMARCHY="${mock_bin}/omarchy"
export CN_INPUT_YAY="${mock_bin}/yay"
export CN_INPUT_SYSTEMCTL="${mock_bin}/systemctl"
export MOCK_LOG="$mock_log"
export MOCK_STATE=2
export MOCK_IM=rime
export MOCK_GROUP_HAS_RIME=1

tests_run=0

pass() {
  tests_run=$((tests_run + 1))
  printf 'ok %d - %s\n' "$tests_run" "$1"
}

fail() {
  printf 'not ok - %s\n' "$1" >&2
  exit 1
}

assert_file_contains() {
  local file="$1" pattern="$2" message="$3"
  grep -Fq -- "$pattern" "$file" || fail "$message"
}

assert_file_not_contains() {
  local file="$1" pattern="$2" message="$3"
  if grep -Fq -- "$pattern" "$file"; then fail "$message"; fi
}

assert_equal() {
  local expected="$1" actual="$2" message="$3"
  [[ "$expected" == "$actual" ]] || fail "$message (expected '$expected', got '$actual')"
}

cat >"${config_root}/fcitx5/config" <<'CFG'
# Keep this comment.
[Behavior]
ActiveByDefault=True

[Hotkey/TriggerKeys]
0=Control+space
CFG

status_json="$($CONTROL status)"
assert_equal true "$(jq -r .ready <<<"$status_json")" "status reports a ready installation"
assert_equal cn "$(jq -r .mode <<<"$status_json")" "status reports active Rime as Chinese"
assert_equal cn "$(jq -r .startupLanguage <<<"$status_json")" "status reads the startup preference"
pass "status exposes ready, current, and startup state"

: >"$mock_log"
"$CONTROL" toggle
assert_file_contains "$mock_log" 'fcitx5-remote -c' "toggle did not close active Rime"
pass "toggle changes active Chinese input to English"

: >"$mock_log"
"$CONTROL" set-startup en
assert_file_contains "${config_root}/fcitx5/config" '# Keep this comment.' "startup edit removed unrelated content"
assert_file_contains "${config_root}/fcitx5/config" 'ActiveByDefault=False' "startup edit did not save English"
assert_file_contains "$mock_log" 'ReloadConfig' "startup edit did not reload Fcitx5"
backup_count="$(find "${state_root}/community.cn-input/backups" -type f -name 'config.*.bak' | wc -l)"
assert_equal 1 "$backup_count" "startup edit did not create one backup"
pass "startup preference is edited atomically with a backup"

cat >"${config_root}/fcitx5/config" <<'CFG'
[Behavior]
ShareInputState=No

[Hotkey/TriggerKeys]
0=Alt+space

[Addon]
Emoji=True
CFG
mkdir -p "${data_root}/fcitx5/rime"
cat >"${data_root}/fcitx5/rime/default.custom.yaml" <<'YAML'
patch:
  schema_list:
    - schema: terra_pinyin
  menu/page_size: 7
YAML
: >"$mock_log"
export MOCK_STATE=1
export MOCK_IM=keyboard-us
export MOCK_GROUP_HAS_RIME=0

"$CONTROL" configure
assert_file_contains "${data_root}/fcitx5/rime/default.custom.yaml" 'menu/page_size: 7' "Rime customization was overwritten"
assert_file_contains "${data_root}/fcitx5/rime/default.custom.yaml" 'schema: terra_pinyin' "existing Rime schema was overwritten"
assert_file_contains "${data_root}/fcitx5/rime/default.custom.yaml" 'schema: rime_ice' "Rime Ice schema was not added"
assert_file_contains "${config_root}/fcitx5/config" '0=Alt+space' "existing Fcitx hotkey was overwritten"
assert_file_contains "${config_root}/fcitx5/config" '1=Control+space' "Ctrl+Space was not appended"
assert_file_contains "${config_root}/fcitx5/config" 'ActiveByDefault=False' "first setup did not default to English"
assert_file_contains "$mock_log" 'SetInputMethodGroupInfo ssa(ss) Default us 2 keyboard-us  rime ' "Rime was not appended to the existing group"
assert_file_contains "$mock_log" 'fcitx5-remote -c' "configure did not restore the inactive state"
pass "configure preserves Fcitx and Rime settings while adding full pinyin"

export MOCK_GROUP_HAS_RIME=1
"$CONTROL" configure
schema_count="$(grep -c 'schema: rime_ice' "${data_root}/fcitx5/rime/default.custom.yaml")"
hotkey_count="$(grep -c 'Control+space' "${config_root}/fcitx5/config")"
assert_equal 1 "$schema_count" "configure duplicated the Rime schema"
assert_equal 1 "$hotkey_count" "configure duplicated Ctrl+Space"
pass "configure is idempotent"

cat >"${config_root}/fcitx5/config" <<'CFG'
[Behavior]
ShareInputState=No

[Hotkey/TriggerKeys]
0=Control+space
CFG
backup_count_before="$(find "${state_root}/community.cn-input/backups" -type f -name 'config.*.bak' | wc -l)"
"$CONTROL" configure
backup_count_after="$(find "${state_root}/community.cn-input/backups" -type f -name 'config.*.bak' | wc -l)"
assert_equal "$((backup_count_before + 1))" "$backup_count_after" "adding the startup default did not back up the existing config"
assert_file_contains "${config_root}/fcitx5/config" 'ActiveByDefault=False' "configure did not add the startup default"
pass "configure backs up an existing config before adding the startup default"

: >"$mock_log"
export MOCK_STATE=2
export MOCK_IM=mozc
export MOCK_GROUP_HAS_RIME=1
"$CONTROL" configure
last_selected="$(awk '$1 == "fcitx5-remote" && $2 == "-s" { value = $3 } END { print value }' "$mock_log")"
assert_equal mozc "$last_selected" "configure did not restore the active input method"
assert_file_contains "$mock_log" 'fcitx5-remote -o' "configure did not restore the active state"
pass "configure restores the active input method after selecting Rime"

export MOCK_STATE=1
export MOCK_IM=keyboard-us

cat >"${data_root}/fcitx5/rime/default.custom.yaml" <<'YAML'
patch: {}
YAML
before="$(sha256sum "${data_root}/fcitx5/rime/default.custom.yaml")"
if "$CONTROL" configure >/dev/null 2>&1; then
  fail "unsupported inline Rime patch should require manual resolution"
fi
after="$(sha256sum "${data_root}/fcitx5/rime/default.custom.yaml")"
assert_equal "$before" "$after" "unsupported Rime file was changed"
pass "ambiguous Rime configuration fails without modifying the file"

# UI architecture checks: the bar owns status; the panel consumes it.
assert_file_contains "${PROJECT_DIR}/BarWidget.qml" 'id: statusProc' "BarWidget should own the status process"
assert_file_not_contains "${PROJECT_DIR}/Panel.qml" 'id: statusProc' "Panel should not own a duplicate status process"
assert_file_not_contains "${PROJECT_DIR}/Panel.qml" 'pendingStartupLanguage' "Panel should not keep optimistic startup state"
assert_file_contains "${PROJECT_DIR}/Panel.qml" 'readonly property var status: hostWidget ? hostWidget.status' "Panel should read status from the host widget"
assert_file_contains "${PROJECT_DIR}/Panel.qml" 'root.refreshStatus()' "Panel mutations should reconcile from backend status"
assert_file_contains "${PROJECT_DIR}/Panel.qml" 'language === "cn" && root.status.ready !== true' "Panel keyboard actions should not bypass the disabled Chinese option"
pass "QML keeps a single frontend status owner and reconciles after mutations"

printf '1..%d\n' "$tests_run"
