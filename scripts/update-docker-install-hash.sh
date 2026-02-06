#!/usr/bin/env bash
set -euo pipefail

TARGET_FILE="install-ss-docker.sh"
DOCKER_INSTALL_REPO="docker/docker-install"
URL_TEMPLATE='https://raw.githubusercontent.com/docker/docker-install/${DOCKER_INSTALL_VERSION}/install.sh'

if [[ ! -f "$TARGET_FILE" ]]; then
  echo "error: $TARGET_FILE not found" >&2
  exit 1
fi

latest_commit=$(curl -fsSL "https://api.github.com/repos/${DOCKER_INSTALL_REPO}/commits/master" | jq -r '.sha')
if [[ -z "$latest_commit" || "$latest_commit" == "null" ]]; then
  echo "error: unable to resolve latest commit from ${DOCKER_INSTALL_REPO}" >&2
  exit 1
fi

latest_url="https://raw.githubusercontent.com/${DOCKER_INSTALL_REPO}/${latest_commit}/install.sh"
latest_sha256=$(curl -fsSL "$latest_url" | sha256sum | awk '{print $1}')
if [[ -z "$latest_sha256" ]]; then
  echo "error: unable to calculate SHA256 for ${latest_url}" >&2
  exit 1
fi

python3 - "$TARGET_FILE" "$latest_commit" "$latest_sha256" "$URL_TEMPLATE" <<'PY'
from pathlib import Path
import re
import sys

path = Path(sys.argv[1])
version, sha256, url_template = sys.argv[2:]
text = path.read_text(encoding="utf-8")

updated = re.sub(r'^DOCKER_INSTALL_VERSION="[^"]+"$', f'DOCKER_INSTALL_VERSION="{version}"', text, count=1, flags=re.M)
updated = re.sub(r'^DOCKER_INSTALL_URL="[^"]+"$', f'DOCKER_INSTALL_URL="{url_template}"', updated, count=1, flags=re.M)
updated = re.sub(r'^EXPECTED_DOCKER_INSTALL_SHA256="[^"]+"$', f'EXPECTED_DOCKER_INSTALL_SHA256="{sha256}"', updated, count=1, flags=re.M)

if updated != text:
    path.write_text(updated, encoding="utf-8")
    print(f"updated {path}")
else:
    print(f"no changes in {path}")
PY

echo "Resolved docker-install commit: ${latest_commit}"
echo "Resolved docker-install sha256: ${latest_sha256}"
