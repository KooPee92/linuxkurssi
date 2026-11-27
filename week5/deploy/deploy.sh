#!/bin/bash
set -Eeuo pipefail

# Week 5 - Automatic deployment
# CSC cPouta Linux server

umask 027

# Require root
if [ "$EUID" -ne 0 ]; then
    echo "ERROR: Root permissions required"
    exit 1
fi

# Validate commit SHA
SHA="${1:-}"

if [[ ! "$SHA" =~ ^[0-9a-f]{40}$ ]]; then
    echo "ERROR: Invalid commit SHA"
    exit 1
fi

# Directories
BASE="/var/lib/viikko5-verified"
SOURCE="$BASE/$SHA/week5"
BUILD="/var/lib/viikko5-build/$SHA"

APP="/opt/viikko5"
RELEASES="$APP/releases"
RELEASE="$RELEASES/$SHA"
CURRENT="$APP/current"

VERSION="/etc/viikko5/version.env"

NGINX="/etc/nginx/snippets/viikko5.conf"
LIMITS="/etc/nginx/conf.d/viikko5-limits.conf"
SERVICE="/etc/systemd/system/viikko5.service"

echo "Starting deployment: $SHA"

# Prevent simultaneous deployments
exec 9>/run/lock/viikko5-deploy.lock
flock -n 9 || {
    echo "ERROR: Another deployment is running"
    exit 1
}

# Check required files
echo "Checking source files..."

for file in \
    app.py \
    db.py \
    requirements.txt \
    templates/index.html \
    static/style.css \
    static/chat.js \
    deploy/viikko5.conf \
    deploy/viikko5-limits.conf \
    deploy/viikko5.service
do
    if [ ! -f "$SOURCE/$file" ] || \
       [ -L "$SOURCE/$file" ]; then
        echo "ERROR: Invalid or missing file: $file"
        exit 1
    fi
done

# Do not overwrite an existing release
if [ -e "$RELEASE" ]; then
    echo "ERROR: Release already exists"
    exit 1
fi

# Use a directory accessible to service accounts
cd /

# Prepare Python dependencies
echo "Preparing Python dependencies..."

if [ -e "$BUILD" ]; then
    echo "ERROR: Build directory already exists: $BUILD"
    exit 1
fi

install -d -m 700 \
    -o week5build -g week5build "$BUILD"

install -m 600 \
    -o week5build -g week5build \
    "$SOURCE/requirements.txt" \
    "$BUILD/requirements.txt"

# Create isolated virtual environment
runuser -u week5build -- \
    python3 -m venv "$BUILD/.venv"

# Install packages without root privileges
runuser -u week5build -- \
    "$BUILD/.venv/bin/python" -m pip install \
    --no-input \
    --disable-pip-version-check \
    --target "$BUILD/vendor" \
    -r "$BUILD/requirements.txt"

echo "Dependencies installed"

# Protect completed build from further modifications
chown -R root:root "$BUILD"
chmod -R go-w "$BUILD"

# Create application release
echo "Preparing application release..."

install -d -m 750 \
    -o root -g week5app "$RELEASES"

install -d -m 750 \
    -o root -g week5app \
    "$RELEASE" \
    "$RELEASE/templates" \
    "$RELEASE/static" \
    "$RELEASE/vendor"

# Install application files
install -m 640 -o root -g week5app \
    "$SOURCE/app.py" \
    "$SOURCE/db.py" \
    "$SOURCE/requirements.txt" \
    "$RELEASE/"

install -m 640 -o root -g week5app \
    "$SOURCE/templates/index.html" \
    "$RELEASE/templates/"

install -m 640 -o root -g week5app \
    "$SOURCE/static/style.css" \
    "$SOURCE/static/chat.js" \
    "$RELEASE/static/"

# Verify dependency files before installation
echo "Checking dependency files..."

if find "$BUILD/vendor" -type l | grep -q .; then
    echo "ERROR: Symbolic links found in dependencies"
    exit 1
fi

if find "$BUILD/vendor" ! -type f ! -type d | grep -q .; then
    echo "ERROR: Unsupported dependency file type"
    exit 1
fi

# Install prepared dependencies
cp -a "$BUILD/vendor/." "$RELEASE/vendor/"

chown -R root:week5app "$RELEASE"
chmod -R o-rwx "$RELEASE"

# Verify required Python packages
echo "Checking Python packages..."

runuser -u week5app -- \
    env PYTHONPATH="$RELEASE/vendor" \
    /usr/bin/python3 -c \
    'import flask, gunicorn, pymysql, requests'

echo "Application release ready"

# Back up current configuration
echo "Backing up configuration..."

BACKUP=$(mktemp -d)

cp -p "$NGINX" "$BACKUP/nginx.conf"
cp -p "$LIMITS" "$BACKUP/limits.conf"
cp -p "$SERVICE" "$BACKUP/service.conf"

if [ -f "$VERSION" ]; then
    cp -p "$VERSION" "$BACKUP/version.env"
fi

PREVIOUS=""

if [ -L "$CURRENT" ]; then
    PREVIOUS=$(readlink "$CURRENT")
fi

ACTIVATED=0

# Restore previous deployment on failure
rollback() {
    trap - ERR
    set +e

    echo "ERROR: Deployment failed"
    echo "Restoring previous configuration..."

    if [ "$ACTIVATED" -eq 1 ]; then

        if [ -n "$PREVIOUS" ]; then
            ln -s "$PREVIOUS" "$CURRENT.rollback.$$"
            mv -Tf "$CURRENT.rollback.$$" "$CURRENT"
        else
            rm -f "$CURRENT"
        fi

        cp -p "$BACKUP/nginx.conf" "$NGINX"
        cp -p "$BACKUP/limits.conf" "$LIMITS"
        cp -p "$BACKUP/service.conf" "$SERVICE"

        if [ -f "$BACKUP/version.env" ]; then
            cp -p "$BACKUP/version.env" "$VERSION"
        else
            rm -f "$VERSION"
        fi

        systemctl daemon-reload
        systemctl restart viikko5

        if nginx -t; then
            systemctl reload nginx
        fi
    fi

    echo "Rollback attempted"
    exit 1
}

trap rollback ERR

# Update Nginx configuration
echo "Updating Nginx..."

ACTIVATED=1

install -m 644 -o root -g root \
    "$SOURCE/deploy/viikko5.conf" "$NGINX"

install -m 644 -o root -g root \
    "$SOURCE/deploy/viikko5-limits.conf" "$LIMITS"

nginx -t

# Install systemd service
echo "Updating systemd service..."

cat > "$SERVICE" <<'EOF'
[Unit]
Description=Week 5 Flask AI Chat Application
After=network.target mariadb.service ollama.service
Wants=mariadb.service ollama.service

[Service]
User=week5app
Group=week5app

WorkingDirectory=/opt/viikko5/current

EnvironmentFile=/etc/viikko5/viikko5.env
EnvironmentFile=-/etc/viikko5/version.env
Environment=PYTHONPATH=/opt/viikko5/current/vendor

ExecStart=/usr/bin/python3 -m gunicorn --workers 1 --threads 1 --timeout 240 --bind 127.0.0.1:8002 app:app

Restart=on-failure
RestartSec=5

NoNewPrivileges=true
PrivateTmp=true
UMask=0027

[Install]
WantedBy=multi-user.target
EOF

chown root:root "$SERVICE"
chmod 644 "$SERVICE"

# Activate release
echo "Activating release..."

ln -s "$RELEASE" "$CURRENT.new.$$"
mv -Tf "$CURRENT.new.$$" "$CURRENT"

# Store deployed commit
printf 'DEPLOY_SHA=%s\n' "$SHA" \
    > "$VERSION.new"

chown root:week5app "$VERSION.new"
chmod 640 "$VERSION.new"

mv -f "$VERSION.new" "$VERSION"

# Restart application
echo "Restarting application..."

systemctl daemon-reload
systemctl restart viikko5
systemctl reload nginx

# Verify deployment
echo "Checking application health..."

HEALTH=$(curl -fsS \
    --retry 8 \
    --retry-all-errors \
    --retry-delay 2 \
    --retry-connrefused \
    http://127.0.0.1/viikko5/health)

EXPECTED_SHA="$SHA" HEALTH_JSON="$HEALTH" \
python3 - <<'PY'
import json
import os

data = json.loads(os.environ["HEALTH_JSON"])

assert data["status"] == "ok"
assert data["commit"] == os.environ["EXPECTED_SHA"]

print("Health check passed!")
print("Deployed commit:", data["commit"])
PY

# Deployment completed
trap - ERR
rm -rf "$BACKUP"

echo "----------------------------------------"
echo "Week 5 deployment successful!"
echo "Commit: $SHA"
echo "Website: /viikko5/"
echo "----------------------------------------"
