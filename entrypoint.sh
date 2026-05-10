#!/bin/bash
set -e

# Run firewall setup as root
/usr/local/bin/init-firewall.sh

# Remove suid/sgid binaries so claude user can't escalate
echo "Stripping suid/sgid bits..."
find /usr /bin /sbin -perm /6000 -type f -exec chmod a-s {} + 2>/dev/null || true

# Align claude user's UID/GID to the host user's so bind-mounted files
# (~/.claude, /workspace) are naturally accessible. This avoids an
# unconditional recursive chown of the bind mount, which would propagate
# to the host on Linux/WSL and leave the host user unable to write its
# own ~/.claude (F2). macOS Docker Desktop hides the propagation but the
# UID-matching path is harmless there too.
#
# When HOST_UID/HOST_GID aren't passed (older callers, manual `docker run`),
# fall back to the legacy recursive chown.
if [ -n "${HOST_UID:-}" ] && [ -n "${HOST_GID:-}" ]; then
  CURRENT_UID=$(id -u claude)
  CURRENT_GID=$(id -g claude)
  if [ "$HOST_UID" != "$CURRENT_UID" ] || [ "$HOST_GID" != "$CURRENT_GID" ]; then
    # Edit /etc/passwd and /etc/group directly rather than calling
    # `usermod -u`. usermod's documented behavior is to auto-chown files
    # in the user's home directory owned by the old UID — and on a
    # bind-mounted /home/claude/.claude that walk propagates back to the
    # host, exactly the behavior F2 is meant to prevent.
    sed -i "s/^claude:x:[0-9]*:[0-9]*:/claude:x:$HOST_UID:$HOST_GID:/" /etc/passwd
    sed -i "s/^claude:x:[0-9]*:/claude:x:$HOST_GID:/" /etc/group
    # Re-own build-time artifacts created at the original claude UID.
    # Explicitly skip the bind-mounted .claude/.workspace — that's the point.
    chown -R "$HOST_UID:$HOST_GID" /home/claude/.local 2>/dev/null || true
  fi
else
  # Legacy fallback: recursive chown of bind mounts. Propagates ownership
  # changes back to the host on Linux/WSL — see F2.
  chown -R claude:claude /home/claude/.claude 2>/dev/null || true
  chown -R claude:claude /workspace 2>/dev/null || true
fi

# Symlink host user's home path so plugin absolute paths resolve inside container.
# Marketplace configs store the host's absolute path (e.g. /Users/cdowin/.claude/...)
# which doesn't exist in the container where ~/.claude is at /home/claude/.claude.
HOST_HOME="${HOST_HOME:-}"
if [ -n "$HOST_HOME" ] && [ "$HOST_HOME" != "/home/claude" ]; then
  mkdir -p "$(dirname "$HOST_HOME")"
  ln -sfn /home/claude "$HOST_HOME"
fi

# Copy credentials extracted from host keychain (overwrites mounted version).
# Defensive: skip the cp when source and dest are the same inode. run-claude.sh
# already avoids the dual-mount config that would cause this, but guard here
# too so a misconfigured caller doesn't fail with "are the same file" (F1).
CREDS_DEST=/home/claude/.claude/.credentials.json
if [ -f /mnt/host-credentials.json ]; then
  if [ ! /mnt/host-credentials.json -ef "$CREDS_DEST" ]; then
    cp /mnt/host-credentials.json "$CREDS_DEST"
  fi
  chmod 600 "$CREDS_DEST"
  chown claude:claude "$CREDS_DEST"
fi

# Generate minimal .claude.json to skip onboarding wizard
# Claude Code requires this file with hasCompletedOnboarding to skip first-run setup
echo '{"hasCompletedOnboarding":true,"installMethod":"native"}' > /home/claude/.claude/.claude.json
ln -sf /home/claude/.claude/.claude.json /home/claude/.claude.json
chown claude:claude /home/claude/.claude/.claude.json /home/claude/.claude.json

# Set up SSH based on method passed via environment
SSH_METHOD="${SSH_METHOD:-none}"
if [ "$SSH_METHOD" != "none" ]; then
  echo "Configuring SSH ($SSH_METHOD)..."
  mkdir -p /home/claude/.ssh

  case "$SSH_METHOD" in
    key-file)
      # Copy the read-only mounted key so we can set ownership and permissions
      cp /home/claude/.ssh/user_key /home/claude/.ssh/id_key
      chmod 600 /home/claude/.ssh/id_key
      cat > /home/claude/.ssh/config <<'SSHEOF'
Host *
    User git
    IdentityFile /home/claude/.ssh/id_key
    StrictHostKeyChecking accept-new
SSHEOF
      ;;
    agent)
      cat > /home/claude/.ssh/config <<'SSHEOF'
Host *
    User git
    StrictHostKeyChecking accept-new
SSHEOF
      ;;
  esac

  chmod 700 /home/claude/.ssh
  chmod 600 /home/claude/.ssh/config
  # chown only the files we own — skip read-only mounted user_key
  chown claude:claude /home/claude/.ssh /home/claude/.ssh/config
  [ -f /home/claude/.ssh/id_key ] && chown claude:claude /home/claude/.ssh/id_key
fi

# Signal that setup is complete
touch /tmp/.claude-ready

# Keep container alive — Claude runs via `docker exec`
echo "Container ready. Waiting for connections..."
exec sleep infinity
