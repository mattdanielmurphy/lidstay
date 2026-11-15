#!/usr/bin/python3
"""tv.py: talk to a Sony Bravia TV over the network (its built-in REST API).

Used by Hammerspoon's TV Follow module (~/.hammerspoon/modules/tv_follow.lua), and handy
on its own:

  tv.py status            {"power": "active|standby|unreachable", "input": "mac|other|unknown", ...}
  tv.py mac               turn the TV on if needed and switch it to the Mac's HDMI input
  tv.py on                turn the TV on (Wake-on-LAN, then the API)
  tv.py input 2           switch to HDMI 2
  tv.py check             say whether the pre-shared key works
  tv.py serve             local server for Hammerspoon on 127.0.0.1:47613 (GET /status, POST /mac)

Why a server: macOS's Local Network privacy blocks Hammerspoon (and Homebrew's Python) from
the TV, while a LaunchAgent running Apple's /usr/bin/python3 is allowed. install.sh runs
`tv.py serve` as the user LaunchAgent local.lidstay.tv; Hammerspoon only talks to localhost.

Options: --ip 192.168.40.57 (TV address), --port 3 (the Mac's HDMI port).

Reading power and inputs needs nothing. Turning the TV on through the API, switching inputs
and reading the exact current input need the TV's pre-shared key (PSK): set one on the TV
(Settings → Network & Internet → Home network setup → IP control → Authentication →
"Normal and Pre-Shared Key", then Pre-Shared Key) and put the same value in this folder's
.env as BRAVIA_PSK=... . Wake-on-LAN power-on needs "Remote start" on in the same menu.
Only the standard library is used; the key is read into memory and never printed.
"""
import argparse
import json
import os
import socket
import sys
import time
import urllib.error
import urllib.request

HERE = os.path.dirname(os.path.realpath(__file__))
DEFAULT_IP = "192.168.40.57"
DEFAULT_PORT = 3


def psk():
    if os.environ.get("BRAVIA_PSK"):
        return os.environ["BRAVIA_PSK"].strip()
    try:
        with open(os.path.join(HERE, ".env")) as f:
            for line in f:
                k, _, v = line.strip().partition("=")
                if k.strip() == "BRAVIA_PSK":
                    v = v.strip().strip('"').strip("'")
                    # aios-env placeholders hold a link, not a key
                    return None if (not v or v.startswith("http")) else v
    except OSError:
        pass
    return None


class TV:
    def __init__(self, ip, port):
        self.ip, self.port, self.key = ip, port, psk()

    def call(self, service, method, params=None, version="1.0", timeout=2.5):
        body = json.dumps({"method": method, "id": 1, "params": params or [], "version": version}).encode()
        req = urllib.request.Request(f"http://{self.ip}/sony/{service}", data=body,
                                     headers={"Content-Type": "application/json"})
        if self.key:
            req.add_header("X-Auth-PSK", self.key)
        try:
            with urllib.request.urlopen(req, timeout=timeout) as r:
                return json.loads(r.read() or b"{}")
        except urllib.error.HTTPError as e:  # 403 comes back as an HTTP error with a JSON body
            try:
                return json.loads(e.read() or b"{}")
            except ValueError:
                return {"error": [e.code, str(e)]}

    def power(self):
        try:
            return self.call("system", "getPowerStatus")["result"][0]["status"]
        except (OSError, KeyError, IndexError, TypeError, ValueError):
            return "unreachable"

    def mac_address(self):
        try:
            r = self.call("system", "getSystemSupportedFunction")["result"][0]
            return next(f["value"] for f in r if f.get("option") == "WOL")
        except (OSError, KeyError, IndexError, StopIteration, TypeError, ValueError):
            return None

    def current_input(self):
        """('mac'|'other'|'unknown', how). Exact with the PSK; a best guess without it."""
        want = f"extInput:hdmi?port={self.port}"
        if self.key:
            try:
                r = self.call("avContent", "getPlayingContentInfo")
            except (OSError, ValueError):
                return "unknown", "unreachable"
            if "result" in r:
                return ("mac" if r["result"][0].get("uri") == want else "other"), "playing"
            err = (r.get("error") or [0])[0]
            if err == 7:  # "Illegal State": an app or the home screen is showing
                return "other", "playing"
            if err not in (403, 401):
                return "unknown", f"error {err}"
        # No key (or it was refused): the inputs list marks the active input with status "true".
        try:
            r = self.call("avContent", "getCurrentExternalInputsStatus", version="1.1")["result"][0]
        except (OSError, KeyError, IndexError, TypeError, ValueError):
            return "unknown", "unreachable"
        for i in r:
            if i.get("uri") == want:
                s = i.get("status")
                if s == "true":
                    return "mac", "inputs-list"
                if s == "false":
                    return "other", "inputs-list"
        return "unknown", "inputs-list"

    def status(self):
        p = self.power()
        out = {"power": p, "input": "unknown", "how": "", "port": self.port, "auth": bool(self.key)}
        if p == "active":
            out["input"], out["how"] = self.current_input()
        elif p == "standby":
            out["input"] = "off"
        return out

    def wol(self):
        mac = self.mac_address() or load_cached_mac()
        if not mac:
            return False
        save_cached_mac(mac)
        pkt = b"\xff" * 6 + bytes.fromhex(mac.replace(":", "")) * 16
        with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as s:
            s.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)
            for addr in ("255.255.255.255", self.ip.rsplit(".", 1)[0] + ".255"):
                try:
                    s.sendto(pkt, (addr, 9))
                except OSError:
                    pass
        return True

    def ok(self, r):
        return isinstance(r, dict) and "result" in r

    def turn_on(self, wait=12.0):
        if self.power() == "active":
            return True, "already on"
        sent = self.wol()
        if self.key:
            try:
                self.call("system", "setPowerStatus", [{"status": True}])
            except OSError:
                pass  # standby TVs sometimes only answer after the WoL packet lands
        end = time.time() + wait
        while time.time() < end:
            if self.power() == "active":
                return True, "turned on"
            time.sleep(0.7)
            if self.key:
                try:
                    self.call("system", "setPowerStatus", [{"status": True}], timeout=1.5)
                except OSError:
                    pass
        return False, ("no answer after Wake-on-LAN" if sent else "TV unreachable")

    def switch(self, port):
        if not self.key:
            return False, "needs BRAVIA_PSK to switch inputs"
        r = self.call("avContent", "setPlayContent", [{"uri": f"extInput:hdmi?port={port}"}])
        return (True, f"HDMI {port}") if self.ok(r) else (False, f"refused: {r.get('error')}")


CACHE = os.path.expanduser("~/.cache/lidstay-tv-mac")


def load_cached_mac():
    try:
        return open(CACHE).read().strip() or None
    except OSError:
        return None


def save_cached_mac(mac):
    try:
        os.makedirs(os.path.dirname(CACHE), exist_ok=True)
        with open(CACHE, "w") as f:
            f.write(mac)
    except OSError:
        pass


SERVE_PORT = 47613


def serve(ip, port):
    import threading
    from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

    lock = threading.Lock()  # one TV command at a time
    last = {"busy": False, "result": None}

    def run_mac():
        with lock:
            last["busy"] = True
            try:
                last["result"] = do_mac(TV(ip, port))
            finally:
                last["busy"] = False
            print("mac:", json.dumps(last["result"]), flush=True)

    class H(BaseHTTPRequestHandler):
        def send(self, obj, code=200):
            b = json.dumps(obj).encode()
            self.send_response(code)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(b)))
            self.end_headers()
            self.wfile.write(b)

        def do_GET(self):
            if self.path.startswith("/status"):
                st = TV(ip, port).status()  # fresh TV() so a new key in .env is picked up
                st["busy"] = last["busy"]
                self.send(st)
            elif self.path.startswith("/last"):
                self.send(last)
            else:
                self.send({"error": "not found"}, 404)

        def do_POST(self):
            if self.path.startswith("/mac"):
                if last["busy"]:
                    return self.send({"ok": True, "did": "already switching"})
                threading.Thread(target=run_mac, daemon=True).start()
                self.send({"ok": True, "did": "started"})
            else:
                self.send({"error": "not found"}, 404)

        def log_message(self, *a):
            pass

    srv = ThreadingHTTPServer(("127.0.0.1", SERVE_PORT), H)
    print(f"tv.py serving on 127.0.0.1:{SERVE_PORT} for {ip}, Mac on HDMI {port}", flush=True)
    srv.serve_forever()


def do_mac(tv):
    before = tv.status()  # "unreachable" may be a deep standby: still try Wake-on-LAN
    ok, why = tv.turn_on()
    did = [why]
    if ok and tv.status()["input"] != "mac":
        time.sleep(0.5 if why == "already on" else 2.0)  # a just-woken TV ignores inputs briefly
        ok, w2 = tv.switch(tv.port)
        did.append(w2)
    return {"ok": ok, "did": ", ".join(did), "before": before}


def main():
    ap = argparse.ArgumentParser(description="Control a Sony Bravia TV")
    ap.add_argument("cmd", choices=["status", "mac", "on", "input", "check", "serve"])
    ap.add_argument("n", nargs="?", type=int)
    ap.add_argument("--ip", default=os.environ.get("BRAVIA_IP", DEFAULT_IP))
    ap.add_argument("--port", type=int, default=int(os.environ.get("BRAVIA_MAC_PORT", DEFAULT_PORT)))
    a = ap.parse_args()
    tv = TV(a.ip, a.port)
    if a.cmd == "status":
        out = tv.status()
    elif a.cmd == "on":
        ok, why = tv.turn_on()
        out = {"ok": ok, "did": why}
    elif a.cmd == "input":
        if not a.n:
            ap.error("input needs an HDMI number")
        ok, why = tv.switch(a.n)
        out = {"ok": ok, "did": why}
    elif a.cmd == "mac":
        out = do_mac(tv)
    elif a.cmd == "serve":
        serve(a.ip, a.port)
        return 0
    else:  # check
        if not tv.key:
            out = {"ok": False, "did": "no BRAVIA_PSK in .env"}
        else:
            r = tv.call("avContent", "getPlayingContentInfo")
            bad = (r.get("error") or [0])[0] in (401, 403)
            out = {"ok": not bad, "did": "key refused by the TV" if bad else "key works"}
    print(json.dumps(out))
    return 0 if out.get("ok", True) else 1


if __name__ == "__main__":
    sys.exit(main())
