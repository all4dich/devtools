# =============================================================================
# Git-aware Bash Prompt
# =============================================================================
# Displays: user@host:current_dir (branch@commit status)
#
# Color/symbol legend:
#   Branch name color reflects overall repo state:
#     GREEN   - clean working tree
#     YELLOW  - staged changes only (ready to commit)
#     RED     - unstaged changes or untracked files (dirty)
#
#   Inline status indicators (with counts):
#     ●N (yellow) - N staged changes
#     ✚N (red)    - N unstaged modifications/deletions
#     …N (blue)   - N untracked files
#     ✓  (green)  - clean
#
# Installation:
#   1. Save this file (e.g. ~/.git-prompt.sh)
#   2. Add to ~/.bashrc:   source ~/.git-prompt.sh
#   3. Open a new terminal or run:  source ~/.bashrc
# =============================================================================

__set_git_prompt() {
    # Capture exit status of last command first (in case you want to display it)
    local last_status=$?

    # ANSI colors wrapped in \001/\002 so bash measures line width correctly.
    # These are the dynamic-PS1 equivalent of the \[ \] markers.
    local RESET=$'\001\e[0m\002'
    local RED=$'\001\e[31m\002'
    local GREEN=$'\001\e[32m\002'
    local YELLOW=$'\001\e[33m\002'
    local BLUE=$'\001\e[34m\002'
    local MAGENTA=$'\001\e[35m\002'
    local CYAN=$'\001\e[36m\002'
    local BOLD=$'\001\e[1m\002'

    # ---- User/host and working directory ------------------------------------
    local user_host="${BOLD}${MAGENTA}\u@\h${RESET}"
    local cwd="${BLUE}\w${RESET}"

    # ---- Git info (only if inside a repo) -----------------------------------
    local git_info=""
    local branch
    branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)

    if [ -n "$branch" ]; then
        local commit
        commit=$(git rev-parse --short HEAD 2>/dev/null)

        # Handle detached HEAD (e.g. after `git checkout <sha>`)
        if [ "$branch" = "HEAD" ]; then
            branch="detached"
        fi

        # Parse `git status --porcelain` to count change categories.
        #   Column 1 = index (staged)  |  Column 2 = worktree (unstaged)
        #   ?? in both columns = untracked
        local status_output
        status_output=$(git status --porcelain 2>/dev/null)

        local staged=0 unstaged=0 untracked=0
        if [ -n "$status_output" ]; then
            staged=$(   echo "$status_output" | grep -c '^[MADRC]')
            unstaged=$( echo "$status_output" | grep -c '^.[MD]')
            untracked=$(echo "$status_output" | grep -c '^??')
        fi

        # Build inline indicator string
        local indicators=""
        if [ "$staged" -eq 0 ] && [ "$unstaged" -eq 0 ] && [ "$untracked" -eq 0 ]; then
            indicators="${GREEN}✓${RESET}"
        else
            [ "$staged"    -gt 0 ] && indicators+="${YELLOW}●${staged}${RESET}"
            [ "$unstaged"  -gt 0 ] && indicators+=" ${RED}✚${unstaged}${RESET}"
            [ "$untracked" -gt 0 ] && indicators+=" ${BLUE}…${untracked}${RESET}"
            # Trim leading space if present
            indicators="${indicators# }"
        fi

        # Pick branch color: red > yellow > green
        local branch_color="${GREEN}"
        if [ "$unstaged" -gt 0 ] || [ "$untracked" -gt 0 ]; then
            branch_color="${RED}"
        elif [ "$staged" -gt 0 ]; then
            branch_color="${YELLOW}"
        fi

        git_info=" (${branch_color}${branch}${RESET}@${CYAN}${commit}${RESET} ${indicators})"
    fi

    # ---- Exit-status indicator for previous command -------------------------
    local status_marker=""
    if [ $last_status -ne 0 ]; then
        status_marker=" ${RED}[exit ${last_status}]${RESET}"
    fi

    # ---- Final assembly -----------------------------------------------------
    # Newline before $ makes long paths/git info readable.
    PS1="${user_host}:${cwd}${git_info}${status_marker}\n\$ "
}

# Re-evaluate the prompt before every prompt draw so git info stays fresh.
PROMPT_COMMAND=__set_git_prompt
