#!/usr/bin/env python3
"""Copy every secret from KWallet into a new gnome-keyring "login" keyring.

Run it from a KDE session, where KWallet answers the Secret Service API:

    ~/.setup/kwallet-to-keyring.py           dry run: show what would be copied
    ~/.setup/kwallet-to-keyring.py --write   copy (asks for your login password)

Secret values are never printed, only their size.

Most apps find their secret again by the same attributes, so those entries are
copied as they are. Three kinds are stored differently by gnome-keyring and are
rewritten into the shape their app looks up (checked against the sources):

  Chromium   KWallet "Chromium Keys"/"Chromium Safe Storage"
             -> application=chromium, xdg:schema=chrome_libsecret_os_crypt_password_v2
             (chromium components/os_crypt/async/browser/freedesktop_secret_key_provider.h)
  Electron   KWallet "<app> Keys"/"<app> Safe Storage" -> application=<app>, same schema
             (electron shell/browser/browser_process_impl.cc)
  Flatpak    KWallet portal "xdg-desktop-portal"/<app id>
             -> app_id=<app id>, xdg:schema=org.freedesktop.portal.Secret,
                label "Application key for <app id>"
             (gnome-keyring daemon/dbus/gkd-secret-portal.c)

The same secret value means the same encryption key, so Chromium and Electron
apps keep their cookies and logins.

The write runs against a private gnome-keyring on a private D-Bus, so it never
clashes with KWallet, and KWallet is left untouched as a backup. The keyring
password must be your login password, so the login screen unlocks it.
"""
import base64
import getpass
import json
import os
import shutil
import subprocess
import sys
import tempfile

from gi.repository import Gio, GLib

SECRETS = "org.freedesktop.secrets"
ROOT = "/org/freedesktop/secrets"
SERVICE_IF = "org.freedesktop.Secret.Service"
COLLECTION_IF = "org.freedesktop.Secret.Collection"
ITEM_IF = "org.freedesktop.Secret.Item"
OS_CRYPT_SCHEMA = "chrome_libsecret_os_crypt_password_v2"
PORTAL_SCHEMA = "org.freedesktop.portal.Secret"
GENERIC_SCHEMA = "org.freedesktop.Secret.Generic"
KEYRING_DIR = os.path.expanduser("~/.local/share/keyrings")
# Chromium-branded products use a fixed lowercase name; Electron apps use theirs as is.
CHROMIUM_APP_NAMES = {"Chromium": "chromium", "Chrome": "chrome"}


def call(bus, path, iface, method, args, reply):
    return bus.call_sync(SECRETS, path, iface, method, args,
                         GLib.VariantType(reply), Gio.DBusCallFlags.NONE, -1, None).unpack()


def prop(bus, path, iface, name):
    return call(bus, path, "org.freedesktop.DBus.Properties", "Get",
                GLib.Variant("(ss)", (iface, name)), "(v)")[0]


def open_session(bus):
    # "plain": the secret crosses the local session bus unencrypted, as Chromium does.
    return call(bus, ROOT, SERVICE_IF, "OpenSession",
                GLib.Variant("(sv)", ("plain", GLib.Variant("s", ""))), "(vo)")[1]


def owner(bus):
    try:
        pid = bus.call_sync("org.freedesktop.DBus", "/org/freedesktop/DBus", "org.freedesktop.DBus",
                            "GetConnectionUnixProcessID", GLib.Variant("(s)", (SECRETS,)),
                            GLib.VariantType("(u)"), Gio.DBusCallFlags.NONE, -1, None).unpack()[0]
        return open(f"/proc/{pid}/comm").read().strip()
    except GLib.Error:
        return None


def read_all():
    """Every item of every collection: label, attributes, content type, raw secret."""
    bus = Gio.bus_get_sync(Gio.BusType.SESSION, None)
    session = open_session(bus)
    items = []
    for col in prop(bus, ROOT, SERVICE_IF, "Collections"):
        paths = prop(bus, col, COLLECTION_IF, "Items")
        if prop(bus, col, COLLECTION_IF, "Locked"):
            call(bus, ROOT, SERVICE_IF, "Unlock", GLib.Variant("(ao)", (paths,)), "(aoo)")
            if prop(bus, col, COLLECTION_IF, "Locked"):
                sys.exit(f"!! {col} is locked: open KWallet (unlock it) and run again")
        secrets = call(bus, ROOT, SERVICE_IF, "GetSecrets",
                       GLib.Variant("(aoo)", (paths, session)), "(a{o(oayays)})")[0]
        for path in paths:
            _, _, value, ctype = secrets[path]
            items.append({
                "label": prop(bus, path, ITEM_IF, "Label"),
                "attrs": dict(prop(bus, path, ITEM_IF, "Attributes")),
                "ctype": ctype,
                "value": bytes(value),
            })
    return items


def plan(item):
    """(action, label, attributes, note) for one KWallet item."""
    a, label = item["attrs"], item["label"]
    server, user = a.get("server", ""), a.get("user", "")
    if not item["value"]:
        return "skip", label, a, "empty secret"
    if server == "xdg-desktop-portal":
        if not user:
            return "skip", label, a, "portal entry without an app id"
        return ("convert", f"Application key for {user}",
                {"app_id": user, "xdg:schema": PORTAL_SCHEMA}, "Flatpak secret portal")
    if server.endswith(" Keys") and user == server[:-5] + " Safe Storage":
        product = server[:-5]
        app = CHROMIUM_APP_NAMES.get(product, product)
        kind = "Chromium" if product in CHROMIUM_APP_NAMES else "Electron app"
        return ("convert", user, {"application": app, "xdg:schema": OS_CRYPT_SCHEMA},
                f"{kind} cookie/password key")
    attrs = dict(a)
    note = "same attributes"
    if label == GENERIC_SCHEMA and "xdg:schema" not in attrs:
        # Written by libsecret with this schema; libsecret lookups match on it.
        attrs["xdg:schema"] = GENERIC_SCHEMA
        note = "same attributes + xdg:schema"
    return "copy", label, attrs, note


def show(entries):
    print(f"{'#':>2}  {'action':8} {'size':>9}  entry")
    for i, (item, (action, label, attrs, note)) in enumerate(entries, 1):
        size = f"{len(item['value'])} B"
        print(f"{i:>2}  {action:8} {size:>9}  {item['label']}")
        if action == "skip":
            print(f"{'':24}skipped: {note}")
            continue
        if label != item["label"]:
            print(f"{'':24}-> label: {label}")
        pretty = ", ".join(f"{k}={v}" for k, v in sorted(attrs.items()))
        print(f"{'':24}-> {pretty}  ({note})")


def writer():
    """Runs inside dbus-run-session: start a private gnome-keyring and fill it."""
    job = json.load(sys.stdin)
    control = tempfile.mkdtemp(prefix="keyring-migrate-")
    try:
        daemon = subprocess.run(
            ["gnome-keyring-daemon", "--unlock", "--components=secrets",
             f"--control-directory={control}"],
            input=job["password"].encode(), capture_output=True)
        if daemon.returncode != 0:
            sys.exit(f"!! gnome-keyring-daemon failed: {daemon.stderr.decode().strip()}")
        bus = Gio.bus_get_sync(Gio.BusType.SESSION, None)
        login = f"{ROOT}/collection/login"
        if prop(bus, login, COLLECTION_IF, "Locked"):
            sys.exit("!! the login keyring did not unlock: the password does not match it")
        call(bus, ROOT, SERVICE_IF, "SetAlias", GLib.Variant("(so)", ("default", login)), "()")
        session = open_session(bus)
        failed = 0
        for e in job["entries"]:
            value = base64.b64decode(e["value"])
            props = {f"{ITEM_IF}.Label": GLib.Variant("s", e["label"]),
                     f"{ITEM_IF}.Attributes": GLib.Variant("a{ss}", e["attrs"])}
            path, prompt = call(bus, login, COLLECTION_IF, "CreateItem", GLib.Variant(
                "(a{sv}(oayays)b)", (props, (session, b"", value, e["ctype"]), True)), "(oo)")
            got = call(bus, path, ITEM_IF, "GetSecret", GLib.Variant("(o)", (session,)),
                       "((oayays))")[0][2]
            ok = prompt == "/" and bytes(got) == value
            failed += not ok
            print(f"  {'ok  ' if ok else 'FAIL'}  {e['label']}")
        sys.exit(1 if failed else 0)
    finally:
        shutil.rmtree(control, ignore_errors=True)


def main():
    write = "--write" in sys.argv
    who = owner(Gio.bus_get_sync(Gio.BusType.SESSION, None))
    if who is None:
        sys.exit("!! nothing provides the Secret Service on this session")
    if who.startswith("gnome-keyring"):
        sys.exit("!! gnome-keyring is already serving secrets here: run this from Plasma")
    print(f"source: {who} (KWallet)\n")

    items = read_all()
    entries = [(item, plan(item)) for item in items]
    show(entries)
    todo = [(i, p) for i, p in entries if p[0] != "skip"]
    print(f"\n{len(todo)} to write, {len(entries) - len(todo)} skipped, "
          f"into {KEYRING_DIR}/login.keyring")

    if not write:
        print("\ndry run: nothing was written. Run again with --write to copy.")
        return
    if not shutil.which("gnome-keyring-daemon"):
        sys.exit("!! install gnome-keyring first: sudo pacman -S gnome-keyring")
    if os.path.exists(os.path.join(KEYRING_DIR, "login.keyring")):
        print("note: login.keyring exists; entries with the same attributes are replaced")

    pw = getpass.getpass("\nYour LOGIN password (becomes the keyring password): ")
    if not pw or pw != getpass.getpass("Again: "):
        sys.exit("!! passwords empty or different, nothing written")
    job = {"password": pw, "entries": [
        {"label": label, "attrs": attrs, "ctype": item["ctype"] or "text/plain",
         "value": base64.b64encode(item["value"]).decode()}
        for item, (_, label, attrs, _) in todo]}
    print("\nwriting into a private gnome-keyring:")
    r = subprocess.run(["dbus-run-session", "--", sys.executable, "-I",
                        os.path.abspath(__file__), "--writer"], input=json.dumps(job).encode())
    print("\ndone: every entry was read back and matches." if r.returncode == 0
          else "\n!! some entries failed (see above). KWallet is unchanged.")
    sys.exit(r.returncode)


if __name__ == "__main__":
    writer() if "--writer" in sys.argv else main()
