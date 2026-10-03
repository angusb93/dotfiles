"""Enforce Kodi's remote-control and audio settings before the session starts.

Kodi owns guisettings.xml and rewrites it on exit, so these cannot simply be
placed in the flake. This runs before display-manager, while Kodi is not
running, and re-asserts them every boot.
"""
import os, re, sys

path = "/var/lib/kiosk/.kodi/userdata/guisettings.xml"
pw_file = "/var/lib/morty-backup/kodi-web.password"

if not os.path.exists(path):
    print("guisettings.xml not written yet; kodi has not run. nothing to do")
    sys.exit(0)

password = ""
if os.path.exists(pw_file):
    password = open(pw_file).read().strip()
else:
    print(f"WARNING: {pw_file} missing - leaving the password alone", file=sys.stderr)

wanted = {
    # Kodi's default web server port is 8080, which on this host is DNATed
    # into the VPN namespace for SABnzbd. 8081 avoids the collision.
    "services.webserver": "true",
    "services.webserverport": "8081",
    "services.webserverauthentication": "true",
    "services.webserverusername": "kodi",
    # Without esallinterfaces Kodi binds JSON-RPC on 9090 to localhost only.
    # Kore then connects for commands but never receives updates, which looks
    # like a half-working remote rather than a setting.
    "services.esallinterfaces": "true",
    "services.esenabled": "true",
    "services.zeroconf": "true",

    # "Keep audio device alive: Always" (153722867 is Kodi's own magic value
    # for it). The default is 1 minute, which means Kodi tears its sink down
    # after a minute of silence and has to rebuild it from cold on the next
    # play. Not the cause of the silent evenings - see the root cause in
    # tv.nix - but it removes a whole class of cold reopen while the TV is on.
    #
    # Note what is deliberately *not* pinned here: audiooutput.audiodevice.
    # Kodi validates that setting against the live device list at startup and
    # rewrites it to "Default" whenever the named device is missing, which it
    # always is while the TV is in standby. Pinning it would erase itself.
    "audiooutput.streamsilence": "153722867",
}
if password:
    wanted["services.webserverpassword"] = password

s = open(path).read()
changed = []
for sid, val in wanted.items():
    pat = re.compile(rf'<setting id="{re.escape(sid)}"[^>]*?(?:/>|>.*?</setting>)', re.S)
    new = f'<setting id="{sid}" default="false">{val}</setting>'
    if not pat.search(s):
        print(f"WARNING: {sid} not present in guisettings.xml", file=sys.stderr)
        continue
    if pat.search(s).group(0) != new:
        s = pat.sub(new, s, count=1)
        changed.append(sid)

if changed:
    open(path, "w").write(s)
    os.chown(path, __import__("pwd").getpwnam("kiosk").pw_uid,
             __import__("grp").getgrnam("users").gr_gid)
    print("re-asserted: " + ", ".join(changed))
else:
    print("already correct")
