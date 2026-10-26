# Shared settings for the 2.6 orchestration scripts (sourced). See docs/p26/ORCHESTRATION.md §7.
WS=/home/killerhis/Projects/flappyspikes
REPO=$WS/.worktrees/p26                 # feat/2.6 checkout the orchestrator merges in
ORCH=${ORCH:-$WS/.worktrees/briefs26}   # briefs, STATE.md, RUNLOG.md, workers/, lease (outside git)
W=$ORCH/workers
IDLE_MIN=${IDLE_MIN:-20}                # no log output for this long = stalled
LEASE_STALE_MIN=${LEASE_STALE_MIN:-45}  # orchestrator silent this long = the external tick takes over
export PATH="$HOME/flutter/bin:$HOME/Android/Sdk/platform-tools:$HOME/.local/share/mise/installs/node/26.7.0/bin:$HOME/.local/bin:$PATH"
export ANDROID_HOME="$HOME/Android/Sdk" JAVA_HOME="$(ls -d $HOME/opt/jdk-17* 2>/dev/null | head -1)"
mkdir -p "$W"
