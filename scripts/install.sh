#!/usr/bin/env bash
# Universal Agent Skills Installer
# Supports: Gemini / Antigravity, Claude Code, OpenCode, OpenAI Codex, and workspace .agents/skills
# Usage:
#   bash scripts/install.sh [skill_name|--all] [target] [--target target]
#   bash scripts/install.sh vps-proxy-deploy claude
#   bash scripts/install.sh --all --target claude
# Targets: all | gemini | antigravity | claude | opencode | codex
set -euo pipefail

REPO_URL="${REPO_URL:-https://github.com/lowtech81/agent-skills.git}"

usage() {
    cat <<'EOF'
Usage: bash scripts/install.sh [skill_name|--all] [target] [--target target]

Arguments:
  skill_name          Install a single skill from skills/<name>
  --all               Install every skill (default)
  target              all | gemini | antigravity | claude | opencode | codex (default: all)
  --target <target>   Same as the positional target argument
  -h, --help          Show this help

Examples:
  bash scripts/install.sh vps-proxy-deploy claude
  bash scripts/install.sh --all --target claude
EOF
}

SKILL_FILTER="--all"
TARGET_AGENT="all"
POSITIONAL_COUNT=0
while [ "$#" -gt 0 ]; do
    case "$1" in
        --all)
            SKILL_FILTER="--all"
            ;;
        --target)
            if [ "$#" -lt 2 ]; then
                echo "Error: --target requires a value" >&2
                usage >&2
                exit 2
            fi
            TARGET_AGENT="$2"
            shift
            ;;
        --target=*)
            TARGET_AGENT="${1#*=}"
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        -*)
            echo "Error: unknown option '$1'" >&2
            usage >&2
            exit 2
            ;;
        *)
            case "${POSITIONAL_COUNT}" in
                0) SKILL_FILTER="$1" ;;
                1) TARGET_AGENT="$1" ;;
                *)
                    echo "Error: unexpected argument '$1'" >&2
                    usage >&2
                    exit 2
                    ;;
            esac
            POSITIONAL_COUNT=$((POSITIONAL_COUNT + 1))
            ;;
    esac
    shift
done

# Backward compatibility: `install.sh all` means every skill.
if [ "${SKILL_FILTER}" = "all" ]; then
    SKILL_FILTER="--all"
fi

case "${TARGET_AGENT}" in
    all|gemini|antigravity|claude|opencode|codex) ;;
    *)
        echo "Error: unsupported target '${TARGET_AGENT}' (expected all|gemini|antigravity|claude|opencode|codex)" >&2
        exit 2
        ;;
esac

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd || pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." 2>/dev/null && pwd || pwd)"

# If executed via curl | bash without local repo checkout, clone to a temp dir
CLEANUP_TMP=""
if [ ! -d "${REPO_ROOT}/skills" ]; then
    CLEANUP_TMP="$(mktemp -d /tmp/agent-skills.XXXXXX)"
    trap 'rm -rf "${CLEANUP_TMP}"' EXIT
    echo "Cloning ${REPO_URL} ..."
    git clone --depth 1 "${REPO_URL}" "${CLEANUP_TMP}" >/dev/null 2>&1
    REPO_ROOT="${CLEANUP_TMP}"
fi

install_skill_to_dir() {
    local skill_src="$1"
    local dest_root="$2"
    local label="$3"
    local skill_name
    skill_name="$(basename "${skill_src}")"
    : "${skill_name:?skill directory name must not be empty}"

    mkdir -p "${dest_root}"
    rm -rf "${dest_root:?}/${skill_name}"
    cp -R "${skill_src}" "${dest_root}/${skill_name}"
    echo "  [OK] Installed '${skill_name}' -> ${dest_root}/${skill_name} (${label})"
}

install_single_skill() {
    local skill_src="$1"
    if [ ! -f "${skill_src}/SKILL.md" ]; then
        echo "Error: Skill not found at ${skill_src}"
        exit 1
    fi

    case "${TARGET_AGENT}" in
        gemini|antigravity)
            install_skill_to_dir "${skill_src}" "${HOME}/.gemini/config/skills" "Gemini / Antigravity"
            ;;
        claude)
            install_skill_to_dir "${skill_src}" "${HOME}/.claude/skills" "Claude Code"
            ;;
        opencode)
            install_skill_to_dir "${skill_src}" "${HOME}/.config/opencode/skills" "OpenCode"
            ;;
        codex)
            install_skill_to_dir "${skill_src}" "${HOME}/.codex/skills" "OpenAI Codex"
            ;;
        all)
            install_skill_to_dir "${skill_src}" "${HOME}/.gemini/config/skills" "Gemini / Antigravity"
            install_skill_to_dir "${skill_src}" "${HOME}/.claude/skills" "Claude Code"
            install_skill_to_dir "${skill_src}" "${HOME}/.config/opencode/skills" "OpenCode"
            install_skill_to_dir "${skill_src}" "${HOME}/.codex/skills" "OpenAI Codex"
            install_skill_to_dir "${skill_src}" "${HOME}/.agents/skills" "Universal .agents"
            ;;
    esac
}

echo "=================================================="
echo "Installing Agent Skills (Target: ${TARGET_AGENT})"
echo "=================================================="

if [ "${SKILL_FILTER}" = "--all" ] || [ "${SKILL_FILTER}" = "all" ]; then
    for skill_dir in "${REPO_ROOT}"/skills/*; do
        [ -d "${skill_dir}" ] && [ -f "${skill_dir}/SKILL.md" ] && install_single_skill "${skill_dir}"
    done
else
    install_single_skill "${REPO_ROOT}/skills/${SKILL_FILTER}"
fi

echo "=================================================="
echo "Done! Restart or start a new session in your agent."
echo "=================================================="
