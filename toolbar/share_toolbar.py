#!/usr/bin/env python3
import argparse
import ipaddress
import json
import os
import platform
import socket
import subprocess
import threading
import time
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path

import pystray
from PIL import Image, ImageDraw


def load_config(config_path: Path) -> dict:
    with config_path.open("r", encoding="utf-8") as f:
        return json.load(f)


def save_config(config_path: Path, config: dict) -> None:
    with config_path.open("w", encoding="utf-8") as f:
        json.dump(config, f, indent=2)
        f.write("\n")


def tcp_probe(host: str, port: int = 445, timeout: float = 0.8) -> bool:
    try:
        with socket.create_connection((host, port), timeout=timeout):
            return True
    except OSError:
        return False


def open_share_path(host: str, share: str) -> None:
    system = platform.system()
    if system == "Windows":
        os.startfile(rf"\\{host}\{share}")  # type: ignore[attr-defined]
        return
    if system == "Darwin":
        subprocess.Popen(["open", f"smb://{host}/{share}"])
        return
    subprocess.Popen(["xdg-open", f"smb://{host}/{share}"])


def open_path(path: Path) -> None:
    system = platform.system()
    if system == "Windows":
        os.startfile(str(path))  # type: ignore[attr-defined]
        return
    if system == "Darwin":
        subprocess.Popen(["open", str(path)])
        return
    subprocess.Popen(["xdg-open", str(path)])


def get_local_ipv4_addrs() -> list[str]:
    addrs: set[str] = set()
    try:
        for info in socket.getaddrinfo(socket.gethostname(), None, socket.AF_INET):
            ip = info[4][0]
            if not ip.startswith("127."):
                addrs.add(ip)
    except OSError:
        pass

    # Fallback: determine primary outbound IP.
    try:
        with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as s:
            s.connect(("8.8.8.8", 80))
            ip = s.getsockname()[0]
            if not ip.startswith("127."):
                addrs.add(ip)
    except OSError:
        pass

    return sorted(addrs)


def build_default_scan_targets(local_ips: list[str]) -> list[str]:
    targets: set[str] = set()
    for ip_str in local_ips:
        try:
            ip = ipaddress.IPv4Address(ip_str)
            network = ipaddress.IPv4Network(f"{ip}/24", strict=False)
            for host in network.hosts():
                host_str = str(host)
                if host_str != ip_str:
                    targets.add(host_str)
        except ipaddress.AddressValueError:
            continue
    return sorted(targets)


def create_icon_image(online_count: int, total_count: int) -> Image.Image:
    size = 64
    image = Image.new("RGB", (size, size), "#1e293b")
    draw = ImageDraw.Draw(image)
    draw.rounded_rectangle((6, 6, size - 6, size - 6), radius=12, fill="#0f172a", outline="#334155", width=2)

    status_color = "#22c55e" if online_count == total_count and total_count > 0 else "#f59e0b"
    if total_count == 0:
        status_color = "#94a3b8"
    draw.ellipse((22, 14, 42, 34), fill=status_color, outline="#0f172a")

    for i in range(3):
        y = 40 + (i * 6)
        draw.line((16, y, 48, y), fill="#94a3b8", width=2)

    return image


class ToolbarApp:
    def __init__(self, config_path: Path):
        self.config_path = config_path
        self.config = load_config(config_path)
        self.icon = pystray.Icon("wtl_share_toolbar")
        self._stop = threading.Event()
        self._lock = threading.Lock()
        self.state = {
            "devices": [],
            "online_count": 0,
            "last_scan": "never",
        }

    def run_auto_discovery(self) -> int:
        discovery_cfg = self.config.get("auto_discovery", {})
        if not discovery_cfg.get("enabled", True):
            return 0

        targets = discovery_cfg.get("targets", [])
        if not targets:
            targets = build_default_scan_targets(get_local_ipv4_addrs())
        if not targets:
            return 0

        timeout = float(discovery_cfg.get("timeout_seconds", 0.35))
        max_workers = int(discovery_cfg.get("max_workers", 128))
        max_workers = max(16, min(512, max_workers))

        discovered: list[str] = []
        with ThreadPoolExecutor(max_workers=max_workers) as pool:
            futures = {pool.submit(tcp_probe, host, 445, timeout): host for host in targets}
            for future in as_completed(futures):
                host = futures[future]
                try:
                    if future.result():
                        discovered.append(host)
                except OSError:
                    continue

        existing_hosts = {d.get("host") for d in self.config.get("devices", [])}
        default_shares = self.config.get(
            "default_shares",
            ["Share-Windows", "Share-Ubuntu", "Share-macOS"],
        )
        added = 0
        for host in sorted(set(discovered)):
            if host in existing_hosts:
                continue
            self.config.setdefault("devices", []).append(
                {
                    "name": f"Discovered {host}",
                    "host": host,
                    "shares": default_shares,
                }
            )
            added += 1

        discovery_cfg["last_run"] = time.strftime("%Y-%m-%d %H:%M:%S")
        self.config["auto_discovery"] = discovery_cfg
        save_config(self.config_path, self.config)
        return added

    def scan(self) -> None:
        devices = self.config.get("devices", [])
        status_devices = []
        online_count = 0

        for device in devices:
            host = device.get("host", "")
            online = bool(host) and tcp_probe(host, port=445)
            if online:
                online_count += 1
            status_devices.append(
                {
                    "name": device.get("name", host),
                    "host": host,
                    "shares": device.get("shares", []),
                    "online": online,
                }
            )

        with self._lock:
            self.state = {
                "devices": status_devices,
                "online_count": online_count,
                "last_scan": time.strftime("%Y-%m-%d %H:%M:%S"),
            }

    def _device_submenu(self, device: dict) -> pystray.Menu:
        items = []
        for share in device.get("shares", []):
            label = f"Open {share}"
            if not device.get("online", False):
                label = f"{label} (offline)"
            items.append(
                pystray.MenuItem(
                    label,
                    (lambda icon, item, host=device["host"], share_name=share: open_share_path(host, share_name)),
                    enabled=device.get("online", False),
                )
            )

        if not items:
            items.append(pystray.MenuItem("No shares configured", None, enabled=False))
        return pystray.Menu(*items)

    def build_menu(self) -> pystray.Menu:
        with self._lock:
            state = dict(self.state)

        items = []
        for device in state.get("devices", []):
            prefix = "online" if device.get("online", False) else "offline"
            text = f"{device['name']} [{prefix}]"
            items.append(pystray.MenuItem(text, self._device_submenu(device)))

        if not items:
            items.append(pystray.MenuItem("No devices configured", None, enabled=False))

        items.extend(
            [
                pystray.Menu.SEPARATOR,
                pystray.MenuItem(
                    f"Last scan: {state.get('last_scan', 'never')}",
                    None,
                    enabled=False,
                ),
                pystray.MenuItem("Rescan now", self.on_rescan),
                pystray.MenuItem("Run auto-discovery", self.on_discover),
                pystray.MenuItem("Open config", self.on_open_config),
                pystray.MenuItem("Quit", self.on_quit),
            ]
        )
        return pystray.Menu(*items)

    def refresh_icon(self) -> None:
        with self._lock:
            total = len(self.state.get("devices", []))
            online = self.state.get("online_count", 0)
        self.icon.icon = create_icon_image(online, total)
        self.icon.title = f"WTL Share Toolbar: {online}/{total} online"
        self.icon.menu = self.build_menu()
        self.icon.update_menu()

    def worker(self) -> None:
        interval = int(self.config.get("scan_interval_seconds", 20))
        interval = max(5, interval)
        while not self._stop.is_set():
            self.scan()
            self.refresh_icon()
            self._stop.wait(interval)

    def on_rescan(self, icon: pystray.Icon, item: pystray.MenuItem) -> None:
        self.scan()
        self.refresh_icon()

    def on_open_config(self, icon: pystray.Icon, item: pystray.MenuItem) -> None:
        open_path(self.config_path)

    def on_discover(self, icon: pystray.Icon, item: pystray.MenuItem) -> None:
        self.run_auto_discovery()
        self.scan()
        self.refresh_icon()

    def on_quit(self, icon: pystray.Icon, item: pystray.MenuItem) -> None:
        self._stop.set()
        icon.stop()

    def run(self) -> None:
        discovery_cfg = self.config.get("auto_discovery", {})
        if discovery_cfg.get("enabled", True) and not discovery_cfg.get("completed", False):
            self.run_auto_discovery()
            discovery_cfg["completed"] = True
            self.config["auto_discovery"] = discovery_cfg
            save_config(self.config_path, self.config)

        self.scan()
        self.refresh_icon()
        t = threading.Thread(target=self.worker, daemon=True)
        t.start()
        self.icon.run()


def main() -> None:
    parser = argparse.ArgumentParser(description="WTL Share Toolbar")
    parser.add_argument("--config", required=True, help="Path to toolbar config.json")
    args = parser.parse_args()

    config_path = Path(args.config).expanduser().resolve()
    app = ToolbarApp(config_path)
    app.run()


if __name__ == "__main__":
    main()
