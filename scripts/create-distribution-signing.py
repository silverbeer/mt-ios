# /// script
# requires-python = ">=3.11"
# dependencies = ["pyjwt[crypto]", "requests"]
# ///
"""Create the App Store signing identity used by .github/workflows/testflight.yml.

Creates an Apple Distribution certificate and an App Store provisioning profile
("mt-ios AppStore") through the App Store Connect API, then stores them as the
repo's DIST_CERT_P12, DIST_CERT_PASSWORD and APPSTORE_PROFILE Actions secrets.
Nothing secret is printed; the private key exists only in a temp dir and in the
p12 secret. Rerun to renew (the profile expires after a year); it replaces the
profile of the same name.

Needs the mt-ios-asc 1Password item (see set-release-secrets.sh) and `gh`.

    uv run scripts/create-distribution-signing.py
"""
import base64
import os
import secrets
import subprocess
import sys
import tempfile
import time

import jwt
import requests

BUNDLE_ID = "com.missingtable"
PROFILE_NAME = "mt-ios AppStore"
REPO = os.environ.get("GH_REPO", "silverbeer/mt-ios")
ITEM = f"op://{os.environ.get('OP_VAULT', 'agents')}/{os.environ.get('OP_ITEM', 'mt-ios-asc')}"


def op(field: str) -> str:
    return subprocess.run(["op", "read", f"{ITEM}/{field}"], capture_output=True, text=True,
                          check=True).stdout.strip()


KEY_ID, ISSUER, PRIVATE_KEY = op("key_id"), op("issuer_id"), op("private_key")


def api(method: str, path: str, body: dict | None = None) -> dict:
    now = int(time.time())
    token = jwt.encode({"iss": ISSUER, "iat": now, "exp": now + 900, "aud": "appstoreconnect-v1"},
                       PRIVATE_KEY, algorithm="ES256", headers={"kid": KEY_ID, "typ": "JWT"})
    r = requests.request(method, f"https://api.appstoreconnect.apple.com{path}",
                         headers={"Authorization": f"Bearer {token}"}, json=body, timeout=60)
    if r.status_code >= 300:
        sys.exit(f"{method} {path} -> {r.status_code}: {r.text[:800]}")
    return r.json() if r.text else {}


def gh_secret(name: str, value: str) -> None:
    subprocess.run(["gh", "secret", "set", name, "--repo", REPO], input=value, text=True,
                   check=True, capture_output=True)
    print(f"set {name}")


def main() -> None:
    bundle = api("GET", f"/v1/bundleIds?filter[identifier]={BUNDLE_ID}")["data"]
    if not bundle:
        sys.exit(f"no App ID {BUNDLE_ID} registered")

    with tempfile.TemporaryDirectory() as tmp:
        os.chmod(tmp, 0o700)
        key, csr, cer, p12 = (os.path.join(tmp, n) for n in ("dist.key", "dist.csr", "dist.cer", "dist.p12"))
        subprocess.run(["openssl", "req", "-new", "-newkey", "rsa:2048", "-nodes", "-keyout", key,
                        "-out", csr, "-subj", "/CN=mt-ios CI/C=US"], check=True, capture_output=True)

        cert = api("POST", "/v1/certificates", {"data": {"type": "certificates", "attributes": {
            "certificateType": "DISTRIBUTION", "csrContent": open(csr).read()}}})["data"]
        with open(cer, "wb") as f:
            f.write(base64.b64decode(cert["attributes"]["certificateContent"]))
        print(f"certificate {cert['attributes']['displayName']}, expires {cert['attributes']['expirationDate']}")

        for old in api("GET", f"/v1/profiles?filter[name]={PROFILE_NAME}")["data"]:
            api("DELETE", f"/v1/profiles/{old['id']}")
        profile = api("POST", "/v1/profiles", {"data": {"type": "profiles",
            "attributes": {"name": PROFILE_NAME, "profileType": "IOS_APP_STORE"},
            "relationships": {
                "bundleId": {"data": {"type": "bundleIds", "id": bundle[0]["id"]}},
                "certificates": {"data": [{"type": "certificates", "id": cert["id"]}]}}}})["data"]
        print(f"profile {PROFILE_NAME}, expires {profile['attributes']['expirationDate']}")

        password = secrets.token_urlsafe(24)
        pem = subprocess.run(["openssl", "x509", "-inform", "DER", "-in", cer], check=True,
                             capture_output=True).stdout
        # -legacy: macOS `security import` can't read OpenSSL 3's default p12 ciphers.
        subprocess.run(["openssl", "pkcs12", "-export", "-legacy", "-inkey", key, "-in", "/dev/stdin",
                        "-name", "mt-ios Apple Distribution", "-passout", "env:P12_PASS", "-out", p12],
                       input=pem, check=True, capture_output=True, env={**os.environ, "P12_PASS": password})

        gh_secret("DIST_CERT_P12", base64.b64encode(open(p12, "rb").read()).decode())
        gh_secret("DIST_CERT_PASSWORD", password)
        gh_secret("APPSTORE_PROFILE", profile["attributes"]["profileContent"])


if __name__ == "__main__":
    main()
