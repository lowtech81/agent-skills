#!/usr/bin/env bash
# Universal Agent Skills Installer
# Supports: Gemini / Antigravity, Claude Code, OpenCode, OpenAI Codex, and workspace .agents/skills
# Usage:
#   bash scripts/install.sh [skill_name|--all] [--target all|gemini|claude|opencode|codex]
set -euo pipefail

REPO_URL="${REPO_URL:-https://github.com/lowtech81/agent-skills.git}"
SKILL_FILTER="${1:---all}"
TARGET_AGENT="${2:-all}"

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

    mkdir -p "${dest_root}"
    rm -rf "${dest_root}/${skill_name}"
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
        all|*)
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
