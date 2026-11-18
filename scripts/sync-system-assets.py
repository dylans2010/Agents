#!/usr/bin/env python3
# NOTE: Agents-maintained copy. The files under Agents/Resources/SystemAssets
# were imported verbatim from dylans2010/Qwen-Code at the pinned revision
# below, then rebranded for Agents (product/path names, registry references;
# see Slices 16/18/19/23). Do NOT blindly re-run this sync: it would
# overwrite the Agents rebrand with upstream SwiftCode-era text. If upstream
# ever needs to be pulled in again, re-apply the rebrand afterwards.
import base64
import hashlib
import json
import os
import sys
import urllib.error
import urllib.request

sys.path.insert(0, "/opt/muse/skills/custom-connector-setup/bin")
from dynamic_credentials import add_surrogate_to_request, read_response_body

UPSTREAM_REPO = "dylans2010/Qwen-Code"
PINNED_REVISION = "ac20a141d3b001fcc6dba5062fb2b1aced846efa"
UPSTREAM_DIR = "Sources/QwenCode/Resources/SystemAssets"
API_BASE = "https://api.github.com"


def api_get(url):
    request = urllib.request.Request(
        url,
        headers={"Accept": "application/vnd.github+json", "User-Agent": "Agents-sync-system-assets"},
    )
    add_surrogate_to_request(
        request, "custom.github", entry_name="access_token", allowed_hosts=["api.github.com"]
    )
    try:
        with urllib.request.urlopen(request) as response:
            return json.loads(read_response_body(response))
    except urllib.error.HTTPError as error:
        detail = ""
        try:
            detail = read_response_body(error).decode("utf-8", "replace")
        except Exception:
            detail = ""
        raise SystemExit("sync-system-assets: GET %s failed: HTTP %s %s" % (url, error.code, detail))


def blob_sha(data):
    header = ("blob %d\0" % len(data)).encode("ascii")
    return hashlib.sha1(header + data).hexdigest()


def main():
    repo_root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    dest_dir = os.path.join(repo_root, "Agents", "Resources", "SystemAssets")
    print("sync-system-assets: upstream repo %s" % UPSTREAM_REPO)
    print("sync-system-assets: pinned revision %s" % PINNED_REVISION)
    print("sync-system-assets: upstream directory %s" % UPSTREAM_DIR)
    print("sync-system-assets: destination %s" % dest_dir)
    tree = api_get(
        "%s/repos/%s/git/trees/%s?recursive=1" % (API_BASE, UPSTREAM_REPO, PINNED_REVISION)
    )
    if tree.get("truncated"):
        raise SystemExit("sync-system-assets: upstream tree listing is truncated; refusing to sync")
    prefix = UPSTREAM_DIR + "/"
    expected = {}
    for entry in tree.get("tree", []):
        path = entry.get("path", "")
        if entry.get("type") == "blob" and path.startswith(prefix) and "/" not in path[len(prefix):]:
            name = path[len(prefix):]
            if not name.endswith(".md"):
                raise SystemExit("sync-system-assets: unexpected non-markdown entry %s" % path)
            expected[name] = entry["sha"]
    if not expected:
        raise SystemExit("sync-system-assets: no system assets found at %s@%s" % (UPSTREAM_DIR, PINNED_REVISION))
    os.makedirs(dest_dir, exist_ok=True)
    downloaded = {}
    for name in sorted(expected):
        blob = api_get("%s/repos/%s/git/blobs/%s" % (API_BASE, UPSTREAM_REPO, expected[name]))
        if blob.get("encoding") != "base64" or "content" not in blob:
            raise SystemExit("sync-system-assets: blob %s returned unexpected encoding" % name)
        data = base64.b64decode(blob["content"])
        actual = blob_sha(data)
        if actual != expected[name]:
            raise SystemExit(
                "sync-system-assets: blob SHA mismatch for %s: expected %s, got %s"
                % (name, expected[name], actual)
            )
        target = os.path.join(dest_dir, name)
        with open(target, "wb") as handle:
            handle.write(data)
        downloaded[name] = actual
    stale = [
        name
        for name in os.listdir(dest_dir)
        if name.endswith(".md") and name not in expected
    ]
    for name in stale:
        os.remove(os.path.join(dest_dir, name))
        print("sync-system-assets: removed stale file %s" % name)
    if set(downloaded) != set(expected):
        raise SystemExit("sync-system-assets: incomplete download: got %d of %d files" % (len(downloaded), len(expected)))
    total_bytes = sum(os.path.getsize(os.path.join(dest_dir, name)) for name in downloaded)
    print("sync-system-assets: verified %d files (%d bytes) at %s" % (len(downloaded), total_bytes, PINNED_REVISION))
    for name in sorted(downloaded):
        print("sync-system-assets: %s %s" % (downloaded[name], name))


if __name__ == "__main__":
    main()
