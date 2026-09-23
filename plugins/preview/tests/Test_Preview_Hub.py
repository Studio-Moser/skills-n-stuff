#!/usr/bin/env python3

import importlib.util
import os
import sys
import threading
import time
import unittest
import urllib.request
from http.server import ThreadingHTTPServer
from pathlib import Path


MODULE_PATH = (
    Path(__file__).parents[1]
    / "skills"
    / "serve-preview"
    / "assets"
    / "Preview_Hub"
    / "Preview_Hub.py"
)
STATIC_ROOT = MODULE_PATH.parent / "Static"
os.environ.setdefault("PREVIEW_HUB_TAILNET_SUFFIX", "example.ts.net")
os.environ.setdefault("PREVIEW_HUB_TAILNET_PROXY", "http://router:1055")
SPEC = importlib.util.spec_from_file_location("preview_hub", MODULE_PATH)
assert SPEC and SPEC.loader
HUB = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = HUB
SPEC.loader.exec_module(HUB)


def relative_luminance(rgb):
    channels = []
    for channel in rgb:
        channel /= 255
        channels.append(
            channel / 12.92
            if channel <= 0.04045
            else ((channel + 0.055) / 1.055) ** 2.4
        )
    return 0.2126 * channels[0] + 0.7152 * channels[1] + 0.0722 * channels[2]


def contrast_ratio(foreground, background):
    lighter, darker = sorted(
        (relative_luminance(foreground), relative_luminance(background)), reverse=True
    )
    return (lighter + 0.05) / (darker + 0.05)


class FakeCatalog(HUB.PreviewCatalog):
    def __init__(self):
        super().__init__()
        self.responses = {
            "/api/v2/tailnet/-/services": {
                "vipServices": [
                    {
                        "name": "svc:preview-client-site",
                        "comment": f"{HUB.OWNERSHIP_PREFIX}; project=Client%20Website; kind=app",
                        "tags": [HUB.PREVIEW_TAG],
                    },
                    {
                        "name": "svc:preview-saved",
                        "comment": HUB.OWNERSHIP_PREFIX,
                        "tags": [HUB.PREVIEW_TAG],
                    },
                    {
                        "name": HUB.HUB_SERVICE,
                        "comment": HUB.OWNERSHIP_PREFIX,
                        "tags": [HUB.PREVIEW_TAG],
                    },
                    {
                        "name": "svc:preview-foreign",
                        "comment": f"{HUB.OWNERSHIP_PREFIX}-not-owned",
                        "tags": [HUB.PREVIEW_TAG],
                    },
                ]
            },
            "/api/v2/tailnet/-/devices": {
                "devices": [
                    {
                        "nodeId": "node-live",
                        "hostname": "preview-router-studio-moser",
                        "connectedToControl": True,
                        "lastSeen": "2026-09-22T20:00:00Z",
                    },
                    {
                        "nodeId": "node-saved",
                        "hostname": "preview-router-macbook",
                        "connectedToControl": False,
                        "lastSeen": "2026-09-20T20:00:00Z",
                    },
                ]
            },
            "/api/v2/tailnet/-/services/svc%3Apreview-client-site/devices": {
                "hosts": [{"nodeId": "node-live"}]
            },
            "/api/v2/tailnet/-/services/svc%3Apreview-saved/devices": {
                "hosts": [{"nodeId": "node-saved"}]
            },
        }

    def _api_get(self, path):
        return self.responses[path]

    def _probe(self, service_name):
        return service_name == "svc:preview-client-site"


class PreviewHubTests(unittest.TestCase):
    def test_static_ui_reuses_the_harness_testing_tabler_system(self):
        html = (STATIC_ROOT / "Index.html").read_text()
        javascript = (STATIC_ROOT / "App.js").read_text()
        css = (STATIC_ROOT / "App.css").read_text()

        self.assertIn("@tabler/core@1.5.1/dist/css/tabler.min.css", html)
        self.assertIn("integrity=\"sha384-tLWyEXulonaekaXL6+fCZQJv/MujuGIpVTBzuVEpwSqFDEfLkPA/PAYGTSBBJO2X\"", html)
        for class_name in ("navbar", "container-xl", "card", "form-control", "nav-pills"):
            self.assertIn(class_name, html)
        for class_name in ("list-group", "badge bg-", "btn btn-primary"):
            self.assertIn(class_name, javascript)
        self.assertNotIn("--signal-white", css)

    def test_csp_allows_only_the_pinned_framework_stylesheet_origin(self):
        server = ThreadingHTTPServer(("127.0.0.1", 0), HUB.make_handler(FakeCatalog()))
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        try:
            with urllib.request.urlopen(f"http://127.0.0.1:{server.server_port}/") as response:
                policy = response.headers["Content-Security-Policy"]
            self.assertIn("style-src 'self' https://cdn.jsdelivr.net", policy)
            self.assertIn("font-src 'self' https://cdn.jsdelivr.net", policy)
            self.assertIn("script-src 'self'", policy)
            self.assertNotIn("script-src 'self' https://", policy)
        finally:
            server.shutdown()
            server.server_close()
            thread.join()

    def test_compact_badge_foregrounds_meet_wcag_aa_contrast(self):
        css = (STATIC_ROOT / "App.css").read_text()
        badge_colors = (
            ("#0f6b2f", (15, 107, 47), (234.2, 247.4, 236.3)),
            ("#7a4b00", (122, 75, 0), (254, 245.4, 229.5)),
            ("#475569", (71, 85, 105), (240.2, 240.9, 242.3)),
        )
        for hex_color, foreground, background in badge_colors:
            self.assertIn(f"color: {hex_color} !important", css)
            self.assertGreaterEqual(contrast_ratio(foreground, background), 4.5)

    def test_metadata_is_decoded(self):
        project, kind = HUB.service_metadata(
            f"{HUB.OWNERSHIP_PREFIX}; project=Design%20System; kind=static",
            "svc:preview-design-system",
        )
        self.assertEqual((project, kind), ("Design System", "static"))

    def test_inventory_filters_and_groups_services(self):
        inventory = FakeCatalog()._load()
        self.assertEqual(inventory["counts"], {"machines": 2, "services": 2, "live": 1})
        self.assertEqual(inventory["machines"][0]["name"], "Studio Moser")
        self.assertEqual(inventory["machines"][0]["previews"][0]["state"], "live")
        self.assertEqual(inventory["machines"][1]["name"], "Macbook")
        self.assertEqual(inventory["machines"][1]["previews"][0]["state"], "saved")

    def test_machine_prefix_is_removed(self):
        self.assertEqual(HUB.display_machine("preview-router-studio-moser"), "Studio Moser")

    def test_service_inventory_loads_concurrently(self):
        catalog = FakeCatalog()
        services = []
        for index in range(8):
            name = f"svc:preview-project-{index}"
            services.append(
                {
                    "name": name,
                    "comment": HUB.OWNERSHIP_PREFIX,
                    "tags": [HUB.PREVIEW_TAG],
                }
            )
            catalog.responses[
                f"/api/v2/tailnet/-/services/{name.replace(':', '%3A')}/devices"
            ] = {"hosts": [{"nodeId": "node-live"}]}
        catalog.responses["/api/v2/tailnet/-/services"] = {"vipServices": services}
        catalog._probe = lambda _service: (time.sleep(0.05) or True)

        started = time.monotonic()
        inventory = catalog._load()
        elapsed = time.monotonic() - started

        self.assertEqual(inventory["counts"]["services"], 8)
        self.assertLess(elapsed, 0.25)


if __name__ == "__main__":
    unittest.main()
