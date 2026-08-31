#!/usr/bin/env bash
#
# install_jenkins_agent_service.sh
#
# Create (and enable) a systemd service that runs a Jenkins inbound (JNLP) agent.
#
# The agent is launched with the equivalent of:
#
#   curl -sO <JENKINS_URL>/jnlpJars/agent.jar
#   java -jar agent.jar \
#        -url <JENKINS_URL> \
#        -secret <SECRET> \
#        -name <NAME> \
#        -webSocket \
#        -workDir <WORKDIR>
#
set -euo pipefail

# --------------------------------------------------------------------------
# Defaults
# --------------------------------------------------------------------------
JENKINS_URL="http://hub.rebellions.dev/jenkins/"
SECRET=""
AGENT_NAME=""
RUN_USER="root"
WORKDIR=""                       # default computed later: <user-home>/.jenkins_work
SERVICE_NAME=""                  # default computed later: jenkins-agent-<name>
INSTALL_DIR=""                   # default computed later: <workdir>
ENABLE_NOW="yes"

# --------------------------------------------------------------------------
# Helpers
# --------------------------------------------------------------------------
PROG="$(basename "$0")"

usage() {
    cat <<EOF
Usage: $PROG -s <secret> -n <agent-name> [options]

Create a systemd service that runs a Jenkins inbound agent.

Required:
  -s, --secret <secret>     Jenkins agent secret.
  -n, --name <name>         Agent node name (e.g. "cowork.qc-node").

Options:
  -u, --url <url>           Jenkins URL.
                            (default: ${JENKINS_URL})
  -U, --user <username>     User to run the agent as.
                            (default: ${RUN_USER})
  -w, --workdir <dir>       Agent work directory.
                            (default: <user-home>/.jenkins_work)
  -d, --install-dir <dir>   Directory to download agent.jar into.
                            (default: same as workdir)
  -S, --service-name <name> systemd service unit name (without .service).
                            (default: jenkins-agent-<agent-name>)
      --no-start            Install the unit but do not enable/start it.
  -h, --help                Show this help and exit.

Example:
  sudo $PROG \\
       -s 39cb95455cde5869069c73f5243ff4634e3e306ba85e17ef9cfd676fa160588b \\
       -n "cowork.qc-node" \\
       -U cowork.qc
EOF
}

die() {
    echo "Error: $*" >&2
    exit 1
}

# --------------------------------------------------------------------------
# Parse arguments
# --------------------------------------------------------------------------
while [[ $# -gt 0 ]]; do
    case "$1" in
        -s|--secret)        SECRET="$2";        shift 2 ;;
        -n|--name)          AGENT_NAME="$2";    shift 2 ;;
        -u|--url)           JENKINS_URL="$2";   shift 2 ;;
        -U|--user)          RUN_USER="$2";      shift 2 ;;
        -w|--workdir)       WORKDIR="$2";       shift 2 ;;
        -d|--install-dir)   INSTALL_DIR="$2";   shift 2 ;;
        -S|--service-name)  SERVICE_NAME="$2";  shift 2 ;;
        --no-start)         ENABLE_NOW="no";    shift   ;;
        -h|--help)          usage; exit 0 ;;
        *)                  die "Unknown argument: $1 (use --help)" ;;
    esac
done

# --------------------------------------------------------------------------
# Validate
# --------------------------------------------------------------------------
[[ $EUID -eq 0 ]] || die "This script must be run as root (use sudo)."
[[ -n "$SECRET" ]]     || die "Missing --secret (see --help)."
[[ -n "$AGENT_NAME" ]] || die "Missing --name (see --help)."

command -v systemctl >/dev/null 2>&1 || die "systemctl not found; this system does not use systemd."

# The run user must exist so we can resolve its home directory and set ownership.
if ! id "$RUN_USER" >/dev/null 2>&1; then
    die "User '$RUN_USER' does not exist."
fi

# Resolve the run user's home directory.
USER_HOME="$(getent passwd "$RUN_USER" | cut -d: -f6)"
[[ -n "$USER_HOME" ]] || die "Could not determine home directory for user '$RUN_USER'."

# Compute defaults that depend on other values.
[[ -n "$WORKDIR" ]]      || WORKDIR="${USER_HOME}/.jenkins_work"
[[ -n "$INSTALL_DIR" ]]  || INSTALL_DIR="$WORKDIR"
[[ -n "$SERVICE_NAME" ]] || SERVICE_NAME="jenkins-agent-${AGENT_NAME}"

# systemd unit names must not contain '/'; sanitize the agent name.
SERVICE_NAME="${SERVICE_NAME//\//-}"
UNIT_PATH="/etc/systemd/system/${SERVICE_NAME}.service"

# java is required at runtime; warn early if it is missing.
if ! command -v java >/dev/null 2>&1; then
    echo "Warning: 'java' was not found in PATH. Install a JRE before starting the service." >&2
fi

# Normalise the Jenkins URL (strip trailing slash for building the jar URL).
JENKINS_URL_NOSLASH="${JENKINS_URL%/}"
AGENT_JAR="${INSTALL_DIR}/agent.jar"

# --------------------------------------------------------------------------
# Download agent.jar
# --------------------------------------------------------------------------
echo ">> Creating directories..."
install -d -o "$RUN_USER" -m 0755 "$INSTALL_DIR"
install -d -o "$RUN_USER" -m 0755 "$WORKDIR"

JAR_URL="${JENKINS_URL_NOSLASH}/jnlpJars/agent.jar"
echo ">> Downloading agent.jar from ${JAR_URL} ..."
if ! curl -fsSL -o "$AGENT_JAR" "$JAR_URL"; then
    # Some deployments (e.g. nginx behind TLS) 301-redirect the http URL back to
    # itself, causing an infinite redirect loop over plain http. Retry over https.
    if [[ "$JAR_URL" == http://* ]]; then
        JAR_URL_HTTPS="https://${JAR_URL#http://}"
        echo ">> http download failed; retrying over https: ${JAR_URL_HTTPS} ..."
        curl -fsSL -o "$AGENT_JAR" "$JAR_URL_HTTPS" \
            || die "Failed to download agent.jar (tried http and https)."
    else
        die "Failed to download agent.jar."
    fi
fi
chown "$RUN_USER" "$AGENT_JAR"

# --------------------------------------------------------------------------
# Write the systemd unit
# --------------------------------------------------------------------------
JAVA_BIN="$(command -v java || echo /usr/bin/java)"

echo ">> Writing systemd unit ${UNIT_PATH} ..."
cat > "$UNIT_PATH" <<EOF
[Unit]
Description=Jenkins Agent (${AGENT_NAME})
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=${RUN_USER}
WorkingDirectory=${INSTALL_DIR}
ExecStart=${JAVA_BIN} -jar ${AGENT_JAR} \\
    -url ${JENKINS_URL} \\
    -secret ${SECRET} \\
    -name ${AGENT_NAME} \\
    -webSocket \\
    -workDir ${WORKDIR}
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

chmod 0644 "$UNIT_PATH"

# --------------------------------------------------------------------------
# Enable / start
# --------------------------------------------------------------------------
echo ">> Reloading systemd..."
systemctl daemon-reload

if [[ "$ENABLE_NOW" == "yes" ]]; then
    echo ">> Enabling and starting ${SERVICE_NAME}.service ..."
    systemctl enable --now "${SERVICE_NAME}.service"
    echo
    echo "Done. Check status with:"
    echo "    systemctl status ${SERVICE_NAME}.service"
    echo "    journalctl -u ${SERVICE_NAME}.service -f"
else
    echo
    echo "Unit installed but not started (--no-start). To start it later:"
    echo "    systemctl enable --now ${SERVICE_NAME}.service"
fi
