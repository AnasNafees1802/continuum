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

Preserves unrelated keys, tolerates a UTF-8 BOM, backs the previous file up to
<file>.continuum.bak, writes atomically, and FAILS CLOSED - it refuses to overwrite a config it
cannot parse rather than risk wiping it.
"""
import json, os, sys, shutil, copy, re, datetime

f = os.environ["CONT_FILE"]
srv_path = os.environ["CONT_SRV"]
pyexe = os.environ["CONT_PY"]
pre = os.environ.get("CONT_PYPRE", "").strip()
args = ([pre] if pre else []) + [srv_path]


def backup_and_write(path, text):
    if os.path.exists(path):
        shutil.copy2(path, path + ".continuum.bak")
    os.makedirs(os.path.dirname(path) or ".", exist_ok=True)
    tmp = path + ".continuum.tmp." + str(os.getpid())
    try:
        with open(tmp, "w", encoding="utf-8") as fh:
            fh.write(text)
        os.replace(tmp, path)
    finally:
        if os.path.exists(tmp): os.unlink(tmp)


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
        raise ValueError("mcpServers must be an object")
    server = servers.setdefault("continuum", {})
    if not isinstance(server, dict): raise ValueError("continuum server must be an object")
    server.update(type="stdio", command=pyexe, args=args)
    server.setdefault("env", {})
    backup_and_write(f, json.dumps(d, indent=2) + "\n")


def write_toml():
    # Preserve other tables verbatim, then validate semantic equality before touching disk.
    # Unusual unsupported layouts fail closed instead of risking another client's settings.
    try:
        import tomllib
    except ImportError:
        raise ValueError("Python 3.11+ is required for safe TOML registration")
    text = ""
    if os.path.exists(f):
        try:
            with open(f, encoding="utf-8-sig") as fh:
                text = fh.read()
        except Exception as e:
            sys.stderr.write("register-mcp: refusing to overwrite unreadable %s (%s)\n" % (f, e))
            sys.exit(2)
    original = tomllib.loads(text)
    expected = copy.deepcopy(original)
    servers = expected.setdefault("mcp_servers", {})
    if not isinstance(servers, dict): raise ValueError("mcp_servers must be a table")
    server = servers.setdefault("continuum", {})
    if not isinstance(server, dict): raise ValueError("continuum must be a table")
    server.update(command=pyexe, args=args)
    kept, skip = [], False
    for ln in text.splitlines():
        s = ln.strip()
        if re.match(r"^\[.*\]\s*(?:#.*)?$", s):
            try:
                node = tomllib.loads(s)
                path = []
                while isinstance(node, dict) and len(node) == 1:
                    key, node = next(iter(node.items()))
                    path.append(key)
                skip = path[:2] == ["mcp_servers", "continuum"]
            except tomllib.TOMLDecodeError:
                # May be a line within a multiline value; final semantic validation protects it.
                pass
        if not skip:
            kept.append(ln)

    def value(v):
        if isinstance(v, str): return json.dumps(v, ensure_ascii=False)
        if isinstance(v, bool): return "true" if v else "false"
        if isinstance(v, (int, float)): return repr(v)
        if isinstance(v, (datetime.datetime, datetime.date, datetime.time)): return v.isoformat()
        if isinstance(v, list): return "[" + ", ".join(value(x) for x in v) + "]"
        if isinstance(v, dict):
            return "{ " + ", ".join(json.dumps(k) + " = " + value(x) for k, x in v.items()) + " }"
        raise ValueError("unsupported TOML value")

    block = ["[mcp_servers.continuum]"] + [json.dumps(k) + " = " + value(v) for k, v in server.items()]
    body = "\n".join(kept).rstrip()
    out = (body + "\n\n" if body else "") + "\n".join(block) + "\n"
    if tomllib.loads(out) != expected:
        raise ValueError("cannot safely merge this TOML layout; original left unchanged")
    backup_and_write(f, out)


try:
    if f.lower().endswith(".toml"):
        write_toml()
    else:
        write_json()
except (OSError, ValueError) as exc:
    sys.stderr.write("register-mcp: refusing unsafe update: %s\n" % exc)
    sys.exit(2)
print("OK")
