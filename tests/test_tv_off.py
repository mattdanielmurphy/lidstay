"""Headless check of tv.py turn_off logic with a fake TV (no network)."""
import os, sys
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.realpath(__file__))))
import tv

class Fake(tv.TV):
    def __init__(self, power, inp, key=True):
        self.ip, self.port, self.key = "x", 3, "k" if key else None
        self._p, self._i, self.sent = power, inp, []
    def power(self): return self._p
    def current_input(self): return self._i, "playing"
    def call(self, service, method, params=None, **k):
        self.sent.append((method, params)); return {"result": [0]}

cases = [
    (("standby", "off"), False, (True, "already standby"), False),
    (("active", "other"), True, (True, "left on (showing other, playing)"), False),
    (("active", "mac"), True, (True, "turned off"), True),
    (("active", "other"), False, (True, "turned off"), True),
]
for (p, i), only, want, sent in cases:
    f = Fake(p, i)
    got = f.turn_off(only)
    assert got == want, (p, i, only, got)
    assert bool(f.sent) == sent and (not sent or f.sent[0] == ("setPowerStatus", [{"status": False}])), f.sent
f = Fake("active", "mac", key=False)
assert f.turn_off(True) == (False, "needs BRAVIA_PSK to turn off")
print("tv off: all passed")
