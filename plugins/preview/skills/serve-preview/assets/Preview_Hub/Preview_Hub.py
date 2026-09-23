#!/usr/bin/env python3
"""Tailnet-only directory for Studio Moser preview Services."""

from __future__ import annotations

import json
import os
import re
import stat
import threading
import time
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timezone
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any
from urllib.error import HTTPError, URLError
from urllib.parse import quote, unquote, urlencode, urlparse
from urllib.request import ProxyHandler, Request, build_opener


API_ORIGIN = "https://api.tailscale.com"
OWNERSHIP_PREFIX = "Managed by Studio Moser agent preview workflow"
PREVIEW_TAG = "tag:agent-preview"
SERVICE_PREFIX = "svc:preview-"
HUB_SERVICE = "svc:preview-hub"
STATIC_ROOT = Path(__file__).with_name("Static")
SECRET_ROOT = Path(os.environ.get("PREVIEW_HUB_SECRET_ROOT", "/run/secrets/hub"))
TAILNET_SUFFIX = os.environ.get("PREVIEW_HUB_TAILNET_SUFFIX", "").strip(".")
TAILNET_PROXY = os.environ.get("PREVIEW_HUB_TAILNET_PROXY", "").strip()
CACHE_SECONDS = 15


class HubError(RuntimeError):
    """An expected configuration or upstream failure safe to summarize."""


def read_credential(name: str) -> str:
    credential_file = SECRET_ROOT / name
    try:
        file_stat = credential_file.lstat()
    except OSError as error:
        raise HubError(f"credential unavailable: {name}") from error
    if stat.S_ISLNK(file_stat.st_mode) or not stat.S_ISREG(file_stat.st_mode):
        raise HubError(f"credential is not a regular file: {name}")
    if file_stat.st_mode & 0o077:
        raise HubError(f"credential permissions are too broad: {name}")
    value = credential_file.read_text(encoding="utf-8").strip()
    if not value:
        raise HubError(f"credential is empty: {name}")
    return value


def service_metadata(comment: str, service_name: str) -> tuple[str, str]:
    short_name = service_name.removeprefix(SERVICE_PREFIX)
    project = short_name.replace("-", " ").title()
    kind = "preview"
    if not comment.startswith(OWNERSHIP_PREFIX):
        return project, kind
    for field in comment.split("; ")[1:]:
        key, separator, value = field.partition("=")
        if not separator:
            continue
        if key == "project" and value:
            project = unquote(value)
        elif key == "kind" and value in {"app", "static", "hub"}:
            kind = value
    return project, kind


def display_machine(hostname: str) -> str:
    short_name = hostname.split(".", 1)[0]
    short_name = short_name.removeprefix("preview-router-")
    return short_name.replace("-", " ").title() or "Unknown machine"


class OAuthTokens:
    def __init__(self, direct_opener: Any) -> None:
        self._opener = direct_opener
        self._token = ""
        self._expires_at = 0.0
        self._lock = threading.Lock()

    def get(self) -> str:
        with self._lock:
            if self._token and time.monotonic() < self._expires_at - 60:
                return self._token
            body = urlencode(
                {
                    "grant_type": "client_credentials",
                    "client_id": read_credential("tailscale_hub_oauth_client_id"),
                    "client_secret": read_credential("tailscale_hub_oauth_client_secret"),
                }
            ).encode()
            request = Request(
                f"{API_ORIGIN}/api/v2/oauth/token",
                data=body,
                headers={"Content-Type": "application/x-www-form-urlencoded"},
            )
            try:
                with self._opener.open(request, timeout=10) as response:
                    payload = json.load(response)
            except (OSError, ValueError, HTTPError, URLError) as error:
                raise HubError("OAuth token request failed") from error
            token = payload.get("access_token")
            if not isinstance(token, str) or not token:
                raise HubError("OAuth token response was invalid")
            self._token = token
            self._expires_at = time.monotonic() + int(payload.get("expires_in", 3600))
            return token


class PreviewCatalog:
    def __init__(self) -> None:
        if not TAILNET_SUFFIX or not re.fullmatch(r"[a-z0-9.-]+\.ts\.net", TAILNET_SUFFIX):
            raise HubError("PREVIEW_HUB_TAILNET_SUFFIX is invalid")
        if not TAILNET_PROXY:
            raise HubError("PREVIEW_HUB_TAILNET_PROXY is required")
        proxy_url = urlparse(TAILNET_PROXY)
        if proxy_url.scheme != "http" or not proxy_url.hostname or proxy_url.username:
            raise HubError("PREVIEW_HUB_TAILNET_PROXY must be an unauthenticated HTTP proxy")
        self._direct_opener = build_opener(ProxyHandler({}))
        self._tailnet_opener = build_opener(
            ProxyHandler({"http": TAILNET_PROXY, "https": TAILNET_PROXY})
        )
        self._tokens = OAuthTokens(self._direct_opener)
        self._cache: dict[str, Any] | None = None
        self._cache_until = 0.0
        self._refreshing = False
        self._lock = threading.Lock()

    def _api_get(self, path: str) -> dict[str, Any]:
        request = Request(
            f"{API_ORIGIN}{path}",
            headers={"Authorization": f"Bearer {self._tokens.get()}"},
        )
        try:
            with self._direct_opener.open(request, timeout=10) as response:
                payload = json.load(response)
        except (OSError, ValueError, HTTPError, URLError) as error:
            raise HubError("Tailscale inventory request failed") from error
        if not isinstance(payload, dict):
            raise HubError("Tailscale inventory response was invalid")
        return payload

    def _probe(self, service_name: str) -> bool:
        dns_label = service_name.removeprefix("svc:")
        if not re.fullmatch(r"preview-[a-z0-9-]+", dns_label):
            return False
        request = Request(
            f"https://{dns_label}.{TAILNET_SUFFIX}/",
            headers={"Range": "bytes=0-0", "User-Agent": "Studio-Moser-Preview-Hub/1"},
        )
        try:
            with self._tailnet_opener.open(request, timeout=4) as response:
                response.read(1)
                return 200 <= response.status < 400
        except (OSError, HTTPError, URLError):
            return False

    def _load_service(
        self, service: dict[str, Any], devices: dict[str, dict[str, Any]]
    ) -> tuple[dict[str, Any], list[dict[str, Any]], bool]:
        name = service["name"]
        project, kind = service_metadata(service["comment"], name)
        dns_label = name.removeprefix("svc:")
        reachable = self._probe(name)
        host_payload = self._api_get(
            f"/api/v2/tailnet/-/services/{quote(name, safe='')}/devices"
        )
        hosts = [host for host in host_payload.get("hosts", []) if isinstance(host, dict)]
        if not hosts:
            hosts = [{"nodeId": ""}]
        preview = {
            "service": dns_label,
            "project": project,
            "kind": kind,
            "url": f"https://{dns_label}.{TAILNET_SUFFIX}",
            "sharedHosts": len(hosts),
        }
        entries = []
        for host in hosts:
            device = devices.get(host.get("nodeId"), {})
            connected = bool(device.get("connectedToControl"))
            entries.append(
                {
                    "hostname": str(device.get("hostname") or "unassigned"),
                    "connected": connected,
                    "lastSeen": device.get("lastSeen"),
                    "preview": {
                        **preview,
                        "state": "live" if reachable else ("unavailable" if connected else "saved"),
                    },
                }
            )
        return service, entries, reachable

    def _load(self) -> dict[str, Any]:
        service_payload = self._api_get("/api/v2/tailnet/-/services")
        device_payload = self._api_get("/api/v2/tailnet/-/devices")
        devices = {
            device.get("nodeId"): device
            for device in device_payload.get("devices", [])
            if isinstance(device, dict) and isinstance(device.get("nodeId"), str)
        }
        groups: dict[str, dict[str, Any]] = {}
        services = []
        for service in service_payload.get("vipServices", []):
            if not isinstance(service, dict):
                continue
            name = service.get("name", "")
            tags = service.get("tags", [])
            comment = service.get("comment", "")
            owned = comment == OWNERSHIP_PREFIX or comment.startswith(OWNERSHIP_PREFIX + "; ")
            if (
                isinstance(name, str)
                and name != HUB_SERVICE
                and name.startswith(SERVICE_PREFIX)
                and PREVIEW_TAG in tags
                and isinstance(comment, str)
                and owned
            ):
                services.append(service)

        loaded_services = []
        if services:
            with ThreadPoolExecutor(max_workers=min(8, len(services))) as executor:
                loaded_services = list(
                    executor.map(lambda service: self._load_service(service, devices), services)
                )

        live_services = 0
        for _, entries, reachable in loaded_services:
            live_services += int(reachable)
            for entry in entries:
                hostname = entry["hostname"]
                group = groups.setdefault(
                    hostname,
                    {
                        "id": hostname,
                        "name": display_machine(hostname),
                        "connected": entry["connected"],
                        "lastSeen": entry["lastSeen"],
                        "previews": [],
                    },
                )
                group["connected"] = bool(group["connected"] or entry["connected"])
                group["previews"].append(entry["preview"])

        machines = sorted(
            groups.values(),
            key=lambda machine: (not machine["connected"], machine["name"].lower()),
        )
        for machine in machines:
            machine["previews"].sort(key=lambda preview: preview["project"].lower())
        return {
            "updatedAt": datetime.now(timezone.utc).isoformat(),
            "counts": {
                "machines": len(machines),
                "services": len(loaded_services),
                "live": live_services,
            },
            "machines": machines,
        }

    def _refresh(self) -> None:
        try:
            loaded = self._load()
        except HubError as error:
            print(f"background inventory refresh failed: {error}", flush=True)
            loaded = None
        with self._lock:
            if loaded is not None:
                self._cache = loaded
                self._cache_until = time.monotonic() + CACHE_SECONDS
            self._refreshing = False

    def get(self) -> dict[str, Any]:
        with self._lock:
            if self._cache is not None:
                if time.monotonic() >= self._cache_until and not self._refreshing:
                    self._refreshing = True
                    threading.Thread(target=self._refresh, daemon=True).start()
                return self._cache
            self._cache = self._load()
            self._cache_until = time.monotonic() + CACHE_SECONDS
            return self._cache


def make_handler(catalog: PreviewCatalog) -> type[BaseHTTPRequestHandler]:
    class PreviewHubHandler(BaseHTTPRequestHandler):
        server_version = "PreviewHub/1"

        def _security_headers(self) -> None:
            self.send_header(
                "Content-Security-Policy",
                "default-src 'self'; connect-src 'self'; img-src 'self' data:; "
                "script-src 'self'; style-src 'self' https://cdn.jsdelivr.net; "
                "font-src 'self' https://cdn.jsdelivr.net; base-uri 'none'; "
                "frame-ancestors 'none'; form-action 'none'",
            )
            self.send_header("Referrer-Policy", "no-referrer")
            self.send_header("X-Content-Type-Options", "nosniff")
            self.send_header("X-Frame-Options", "DENY")
            self.send_header("Permissions-Policy", "camera=(), microphone=(), geolocation=()")

        def _send(self, status: int, content_type: str, body: bytes) -> None:
            self.send_response(status)
            self._security_headers()
            self.send_header("Content-Type", content_type)
            self.send_header("Content-Length", str(len(body)))
            self.send_header("Cache-Control", "no-store")
            self.end_headers()
            if self.command != "HEAD":
                self.wfile.write(body)

        def do_HEAD(self) -> None:  # noqa: N802
            self.do_GET()

        def do_GET(self) -> None:  # noqa: N802
            if self.path == "/healthz":
                self._send(HTTPStatus.OK, "text/plain; charset=utf-8", b"ok\n")
                return
            if self.path == "/api/previews":
                try:
                    body = json.dumps(catalog.get(), separators=(",", ":")).encode()
                    self._send(HTTPStatus.OK, "application/json; charset=utf-8", body)
                except HubError as error:
                    print(f"inventory unavailable: {error}", flush=True)
                    body = json.dumps(
                        {"error": "Preview inventory is temporarily unavailable."}
                    ).encode()
                    self._send(
                        HTTPStatus.SERVICE_UNAVAILABLE,
                        "application/json; charset=utf-8",
                        body,
                    )
                return

            static_files = {
                "/": ("Index.html", "text/html; charset=utf-8"),
                "/App.css": ("App.css", "text/css; charset=utf-8"),
                "/App.js": ("App.js", "text/javascript; charset=utf-8"),
            }
            static_file = static_files.get(self.path)
            if static_file is None:
                self._send(HTTPStatus.NOT_FOUND, "text/plain; charset=utf-8", b"Not found\n")
                return
            filename, content_type = static_file
            self._send(HTTPStatus.OK, content_type, (STATIC_ROOT / filename).read_bytes())

        def log_message(self, format_string: str, *arguments: Any) -> None:
            print(f"{self.address_string()} {format_string % arguments}", flush=True)

    return PreviewHubHandler


def main() -> None:
    catalog = PreviewCatalog()
    server = ThreadingHTTPServer(("0.0.0.0", 8080), make_handler(catalog))
    print("Preview Hub listening on :8080", flush=True)
    server.serve_forever()


if __name__ == "__main__":
    main()
