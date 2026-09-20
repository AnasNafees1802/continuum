#!/usr/bin/env python3
"""Register (or refresh) the Continuum MCP server in ONE client config file. Install-time helper,
called by both installers so the merge logic lives in one place.

Handles the two config shapes clients use:
  * JSON  (Claude Code ~/.claude.json, Cursor mcp.json, Windsurf mcp_config.json, Gemini settings.json)
          - servers under a top-level "mcpServers" object.
  * TOML  (Codex ~/.codex/config.toml) - servers under [mcp_servers.<name>] tables.

Reads from the environment (keeps paths with spaces intact, no shell quoting games):
  CONT_FILE   the client config file to edit (extension decides JSON vs TOML)
  CONT_SRV    absolute path to continuum-mcp.py
  CONT_PY     python executable to launch it (absolute path preferred)
  CONT_PYPRE  optional pre-arg before the script (e.g. "-3" for the Windows `py` launcher)

Safe by construction: preserves every other key, tolerates a UTF-8 BOM, backs the file up once to
<file>.continuum.bak, writes atomically, and FAILS CLOSED - it refuses to overwrite a config it
cannot parse rather than risk wiping it.
"""
import json, os, sys, shutil

f = os.environ["CONT_FILE"]
srv_path = os.environ["CONT_SRV"]
pyexe = os.environ["CONT_PY"]
pre = os.environ.get("CONT_PYPRE", "").strip()
args = ([pre] if pre else []) + [srv_path]


def backup_and_write(path, text):
    if os.path.exists(path):
        try:
            shutil.copyfile(path, path + ".continuum.bak")
        except Exception:
            pass
    os.makedirs(os.path.dirname(path) or ".", exist_ok=True)
    tmp = path + ".continuum.tmp." + str(os.getpid())
    with open(tmp, "w", encoding="utf-8") as fh:
        fh.write(text)
    os.replace(tmp, path)


def write_json():
    d = {}
    if os.path.exists(f):
        try:
            with open(f, encoding="utf-8-sig") as fh:  # utf-8-sig: a BOM must not reset the file
                d = json.load(fh)
        except Exception as e:
            sys.stderr.write("register-mcp: refusing to overwrite unparseable %s (%s)\n" % (f, e))
            sys.exit(2)
    if not isinstance(d, dict):
        sys.stderr.write("register-mcp: refusing to overwrite non-object JSON in %s\n" % f)
        sys.exit(2)
    servers = d.setdefault("mcpServers", {})
    if not isinstance(servers, dict):
        servers = {}
        d["mcpServers"] = servers
    servers["continuum"] = {"type": "stdio", "command": pyexe, "args": args, "env": {}}
    backup_and_write(f, json.dumps(d, indent=2) + "\n")


def write_toml():
    # Codex: [mcp_servers.continuum]. No stdlib TOML writer, so merge by text: drop any existing
    # continuum table(s), keep everything else verbatim, append a fresh block. Literal (single-quoted)
    # TOML strings take the value as-is, so Windows paths with backslashes need no escaping.
    text = ""
    if os.path.exists(f):
        try:
            with open(f, encoding="utf-8-sig") as fh:
                text = fh.read()
        except Exception as e:
            sys.stderr.write("register-mcp: refusing to overwrite unreadable %s (%s)\n" % (f, e))
            sys.exit(2)
    kept, skip = [], False
    for ln in text.splitlines():
        s = ln.strip()
        if s.startswith("[mcp_servers.continuum]") or s.startswith("[mcp_servers.continuum."):
            skip = True
            continue
        if skip and s.startswith("["):  # next table starts -> stop skipping (and keep this header)
            skip = False
        if not skip:
            kept.append(ln)

    def lit(s):
        return "'" + s + "'"  # TOML literal string (no escapes) - safe for backslash paths

    block = ["[mcp_servers.continuum]", "command = " + lit(pyexe),
             "args = [" + ", ".join(lit(a) for a in args) + "]"]
    body = "\n".join(kept).rstrip()
    out = (body + "\n\n" if body else "") + "\n".join(block) + "\n"
    backup_and_write(f, out)


if f.lower().endswith(".toml"):
    write_toml()
else:
    write_json()
print("OK")
