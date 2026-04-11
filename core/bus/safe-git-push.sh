#!/usr/bin/env bash
# safe-git-push.sh — wrap `git push` so it never hangs an agent shell.
#
# Fixes the git-push-pipe-hang class:
#   - git invoking a pager (less) and blocking on TTY
#   - SSH/HTTPS credential prompts blocking on stdin
#   - pipe buffering + progress output deadlocking the parent process
#   - long network stalls with no hard ceiling
#
# Usage:
#   bash core/bus/safe-git-push.sh [push args...]
#   bash core/bus/safe-git-push.sh origin feature/foo
#   bash core/bus/safe-git-push.sh -u origin HEAD
#
# Behavior:
#   - timeout 90s hard ceiling (override via SAFE_GIT_PUSH_TIMEOUT)
#   - no pager, no progress bar, no credential prompts
#   - stdin closed, stderr merged into stdout
#   - no tail/head pipe — full output returned so you see real errors
#   - exit code: 0 on success, 124 on timeout, git's exit otherwise

set -uo pipefail

TIMEOUT_SECS="${SAFE_GIT_PUSH_TIMEOUT:-90}"

# Portable timeout:
#   - GNU coreutils `timeout` (Linux, macOS with coreutils)
#   - GNU `gtimeout` (macOS with `brew install coreutils`)
#   - perl alarm fallback (always present on macOS — no install needed)
run_with_timeout() {
    local secs="$1"; shift
    if command -v timeout >/dev/null 2>&1; then
        timeout "${secs}s" "$@"
    elif command -v gtimeout >/dev/null 2>&1; then
        gtimeout "${secs}s" "$@"
    else
        perl -e '
            use strict; use warnings;
            my $secs = shift @ARGV;
            my $pid = fork();
            die "fork failed: $!" unless defined $pid;
            if ($pid == 0) { exec { $ARGV[0] } @ARGV or die "exec: $!"; }
            local $SIG{ALRM} = sub {
                kill "TERM", $pid;
                sleep 2;
                kill "KILL", $pid;
                exit 124;
            };
            alarm $secs;
            waitpid $pid, 0;
            exit ($? >> 8);
        ' "$secs" "$@"
    fi
}

# Run the push with every known hang source disabled.
run_with_timeout "$TIMEOUT_SECS" \
    env \
        GIT_TERMINAL_PROMPT=0 \
        GIT_PAGER=cat \
        GIT_ASKPASS=/bin/echo \
        SSH_ASKPASS=/bin/echo \
    git -c core.pager=cat -c color.ui=never \
        push --no-progress "$@" \
    </dev/null 2>&1

EXIT=$?

if [[ $EXIT -eq 124 ]]; then
    echo "safe-git-push: TIMED OUT after ${TIMEOUT_SECS}s — push did not complete" >&2
fi

exit $EXIT
