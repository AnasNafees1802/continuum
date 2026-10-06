#!/usr/bin/env python3
"""Boundary regressions. All mutations stay in temporary homes and repositories.

Run: python test/regression.py (Python 3.11+, Git, Bash; PowerShell when available).
"""
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import time
import tomllib
import unittest

REPO = Path(__file__).resolve().parents[1]
BASH = os.environ.get("CONTINUUM_TEST_BASH") or (
    "C:/Program Files/Git/bin/bash.exe" if os.name == "nt" and Path("C:/Program Files/Git/bin/bash.exe").exists()
    else shutil.which("bash"))
PS = (shutil.which("powershell") or shutil.which("pwsh")) if os.name == "nt" else None


class Sandbox(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="continuum-test-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.env = dict(os.environ, CONTINUUM_HOME=str(self.root), CONTINUUM_NO_AUTOUPDATE="1")
        # Prevent developer Git configuration from changing fixture behavior.
        self.env.update(GIT_CONFIG_NOSYSTEM="1", GIT_CONFIG_GLOBAL=os.devnull)

    def run_cmd(self, cmd, data=None, check=True):
        p = subprocess.run(cmd, cwd=self.root, env=self.env, input=data,
                           capture_output=True, text=True, encoding="utf-8", errors="replace", timeout=90)
        if check:
            self.assertEqual(p.returncode, 0, p.stdout + p.stderr)
        return p

    def ledger(self):
        shutil.copytree(REPO / "templates/aicontext", self.root / ".aicontext")
        (self.root / ".gitignore").write_text(".aicontext/\n", encoding="utf-8")
        (self.root / "work.txt").write_text("initial\n", encoding="utf-8")
        self.run_cmd(["git", "init", "-q"])
        self.run_cmd(["git", "config", "user.name", "Continuum test"])
        self.run_cmd(["git", "config", "user.email", "test@example.invalid"])
        self.run_cmd(["git", "add", "."])
        self.run_cmd(["git", "commit", "-qm", "fixture"])


class Registration(Sandbox):
    def register(self, body, suffix="toml", srv="C:/Users/O'Brien/server.py", check=True):
        f = self.root / ("config." + suffix)
        f.write_text(body, encoding="utf-8")
        self.env.update(CONT_FILE=str(f), CONT_SRV=srv, CONT_PY=sys.executable, CONT_PYPRE="")
        result = self.run_cmd([sys.executable, str(REPO / "bin/register-mcp.py")], check=check)
        return f, result

    def test_quoted_toml_and_apostrophe_path_preserve_custom_options(self):
        body = '# preserve comment\nmodel="test"\n[mcp_servers."continuum"]\ncommand="old"\nenabled=false\n[mcp_servers."continuum".env]\nA="b"\n[mcp_servers.other]\ncommand="other"\n'
        f, _ = self.register(body)
        d = tomllib.loads(f.read_text(encoding="utf-8"))
        self.assertFalse(d["mcp_servers"]["continuum"]["enabled"])
        self.assertEqual(d["mcp_servers"]["continuum"]["env"], {"A": "b"})
        self.assertIn("O'Brien", d["mcp_servers"]["continuum"]["args"][0])
        self.assertEqual(d["mcp_servers"]["other"]["command"], "other")
        self.assertIn("# preserve comment", f.read_text())
        self.assertEqual(Path(str(f) + ".continuum.bak").read_text(), body)
        before = f.read_bytes()
        self.run_cmd([sys.executable, str(REPO / "bin/register-mcp.py")])
        self.assertEqual(f.read_bytes(), before)

    def test_invalid_toml_unchanged(self):
        f, result = self.register("broken = [\n", check=False)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(f.read_text(), "broken = [\n")

    def test_unsupported_inline_toml_fails_closed(self):
        body = 'mcp_servers = {continuum = {command="old"}}\n'
        f, result = self.register(body, check=False)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(f.read_text(), body)

    def test_json_preserves_server_customization_and_bom(self):
        f, _ = self.register('\ufeff' + json.dumps({"other": 1, "mcpServers": {"continuum": {"env": {"A": "B"}, "disabled": True}}}), "json")
        d = json.loads(f.read_text())
        self.assertEqual(d["other"], 1)
        self.assertEqual(d["mcpServers"]["continuum"]["env"], {"A": "B"})
        self.assertTrue(d["mcpServers"]["continuum"]["disabled"])

    def test_invalid_json_shape_unchanged(self):
        for body in ('{"mcpServers": []}', '{"broken":', '[]', ''):
            with self.subTest(body=body):
                f, result = self.register(body, "json", check=False)
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(f.read_text(), body)


class MCP(Sandbox):
    def rpc(self, method, params):
        req = {"jsonrpc": "2.0", "id": 1, "method": method, "params": params}
        r = self.run_cmd([sys.executable, str(REPO / "bin/continuum-mcp.py")], json.dumps(req) + "\n")
        return json.loads(r.stdout)

    def call(self, name, args):
        return self.rpc("tools/call", {"name": name, "arguments": args})["result"]

    def test_spec_names_cannot_escape(self):
        self.ledger()
        (self.root / ".aicontext/spec").mkdir()
        (self.root / "outside.md").write_text("PRIVATE SENTINEL")
        for name in ("../../outside", "../STATE", str(self.root / "outside"), "..\\..\\outside"):
            with self.subTest(name=name):
                r = self.call("continuum_spec", {"name": name})
                self.assertTrue(r["isError"])
                self.assertNotIn("PRIVATE SENTINEL", str(r))

    def test_spec_valid_and_missing(self):
        self.ledger()
        folder = self.root / ".aicontext/spec"
        folder.mkdir()
        (folder / "features.md").write_text("Features sentinel")
        r = self.call("continuum_spec", {"name": "features"})
        self.assertFalse(r["isError"])
        self.assertEqual(r["content"][0]["text"], "Features sentinel")
        self.assertTrue(self.call("continuum_spec", {"name": "test-cases"})["isError"])

    def test_bad_arguments_and_unknown_tools_are_errors(self):
        for name, args in [("continuum_remember", {}), ("continuum_remember", {"text": " "}),
                           ("continuum_remember", {"text": 5}), ("continuum_remember", []),
                           ("continuum_import", {"from": "invalid"}), ("unknown", {})]:
            with self.subTest(name=name, args=args):
                self.assertTrue(self.call(name, args)["isError"])

    def test_missing_project_and_resources_are_errors(self):
        self.assertTrue(self.call("continuum_status", {})["isError"])
        self.assertIn("error", self.rpc("resources/read", {"uri": "continuum://unknown"}))

    def test_server_survives_invalid_requests(self):
        data = 'null\n{broken\n' + json.dumps({"jsonrpc": "2.0", "id": 3, "method": "ping"}) + '\n'
        r = self.run_cmd([sys.executable, str(REPO / "bin/continuum-mcp.py")], data)
        replies = [json.loads(line) for line in r.stdout.splitlines()]
        self.assertEqual([r.get("error", {}).get("code") for r in replies[:2]], [-32600, -32700])
        self.assertEqual(replies[2]["result"], {})

    def test_symlink_spec_cannot_escape(self):
        self.ledger()
        outside = self.root / 'elsewhere'
        outside.mkdir()
        (outside / 'features.md').write_text('OUTSIDE')
        try:
            (self.root / '.aicontext/spec').symlink_to(outside, target_is_directory=True)
        except OSError:
            self.skipTest('symlinks unavailable to this user')
        self.assertTrue(self.call('continuum_spec', {'name': 'features'})['isError'])
        self.assertTrue(self.call('continuum_spec', {})['isError'])
        self.assertIn('error', self.rpc('resources/read', {'uri': 'continuum://spec/features'}))

    def test_resource_size_is_bounded(self):
        self.ledger()
        (self.root / '.aicontext/STATE.md').write_text('x' * (1024 * 1024 + 1))
        self.assertIn('error', self.rpc('resources/read', {'uri': 'continuum://state'}))


class InstallerChecks:
    def install(self, project=False, check=True):
        script = "install" if project else "install-global"
        if self.platform == "bash":
            cmd = [BASH, str(REPO / (script + ".sh"))]
            if project: cmd.append(str(self.root))
        else:
            cmd = [PS, "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", str(REPO / (script + ".ps1"))]
            if project: cmd += ["-Target", str(self.root)]
        return self.run_cmd(cmd, check=check)

    def test_bom_and_mixed_hooks_preserved_idempotently(self):
        for project in (False, True):
            with self.subTest(project=project):
                f = self.root / ".claude" / ("settings.local.json" if project else "settings.json")
                f.parent.mkdir(exist_ok=True)
                body = {"unrelated": {"value": 7}, "hooks": {"SessionStart": [{"matcher": "startup", "hooks": [
                    {"type": "command", "command": "echo KEEP"}, {"type": "command", "command": "bash continuum.sh catch-up"}]}]}}
                deep = {'leaf': 'preserve'}
                for _ in range(32): deep = {'nested': deep}
                body['deep'] = deep
                f.write_text(json.dumps(body), encoding="utf-8-sig")
                self.install(project)
                d = json.loads(f.read_text(encoding="utf-8-sig"))
                self.assertEqual(d["unrelated"], body["unrelated"])
                self.assertEqual(d['deep'], body['deep'])
                commands = [h["command"] for g in d["hooks"]["SessionStart"] for h in g["hooks"]]
                self.assertEqual(commands.count("echo KEEP"), 1)
                self.assertEqual(len(commands), 2)
                self.assertTrue(Path(str(f) + ".continuum.bak").exists())
                self.install(project)
                self.assertEqual(json.loads(f.read_text(encoding="utf-8-sig")), d)

    def test_invalid_settings_untouched(self):
        for project in (False, True):
            f = self.root / ".claude" / ("settings.local.json" if project else "settings.json")
            f.parent.mkdir(exist_ok=True)
            for body in ('{"broken":', '[]', '{"hooks": []}', '{"hooks":{"Stop":{}}}'):
                with self.subTest(project=project, body=body):
                    f.write_text(body)
                    result = self.install(project, check=False)
                    self.assertNotEqual(result.returncode, 0)
                    self.assertEqual(f.read_text(), body)


class HelperChecks:
    def command(self):
        return ([BASH, str(REPO / "bin/continuum.sh")] if self.platform == "bash" else
                [PS, "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", str(REPO / "bin/continuum.ps1")])

    def helper(self, *args, data=None, check=True):
        return self.run_cmd(self.command() + list(args), data=data, check=check)

    def test_verify_failure_and_save_verify_propagate(self):
        self.ledger()
        bad = "exit 7" if self.platform == "bash" or os.name != "nt" else "exit /b 7"
        self.helper("verify", "--set", bad)
        self.assertNotEqual(self.helper("verify", check=False).returncode, 0)
        f = self.root / ".aicontext/manifest.json"
        self.assertFalse(json.loads(f.read_text())["continuum"]["verifiedOk"])
        before = json.loads(f.read_text())["continuum"].get("sessionCount")
        self.assertNotEqual(self.helper("save", "--verify", check=False).returncode, 0)
        self.assertEqual(json.loads(f.read_text())["continuum"].get("sessionCount"), before)

    def test_guard_detects_new_content_in_dirty_file(self):
        self.ledger()
        f = self.root / "work.txt"
        f.write_text("dirty at start")
        self.helper("catch-up", data='{"session_id":"dirty"}')
        os.utime(self.root / ".aicontext/STATE.md", (time.time() - 3600,) * 2)
        f.write_text("more work after catch-up")
        result = self.helper("guard", data='{"session_id":"dirty"}')
        self.assertEqual(json.loads(result.stdout)["decision"], "block")

    def test_guard_silent_after_save_but_detects_later_work(self):
        self.ledger()
        self.helper("catch-up", data='{"session_id":"saved"}')
        f = self.root / "work.txt"
        f.write_text("work before save")
        os.utime(self.root / ".aicontext/STATE.md", (time.time() + 1,) * 2)
        self.helper("save", "--agent", "test")
        self.assertEqual(self.helper("guard", data='{"session_id":"saved"}').stdout, "")
        f.write_text("new work after save")
        self.assertEqual(json.loads(self.helper("guard", data='{"session_id":"saved"}').stdout)["decision"], "block")

    def test_memory_prefix_is_distinct(self):
        self.helper("remember", "Use pnpm for frontend projects")
        self.helper("remember", "Use pnpm")
        self.helper("remember", "Use pnpm")
        memory = (self.root / ".continuum/memory/MEMORY.md").read_text(encoding="utf-8")
        self.assertEqual(sum(line.startswith("- ") for line in memory.splitlines()), 2)

    def test_reverting_to_session_start_after_save_still_needs_handoff(self):
        self.ledger()
        self.helper('catch-up', data='{"session_id":"revert"}')
        f = self.root / 'work.txt'
        f.write_text('saved intermediate work')
        os.utime(self.root / '.aicontext/STATE.md', (time.time() + 1,) * 2)
        self.helper('save')
        f.write_text('initial\n')
        result = self.helper('guard', data='{"session_id":"revert"}')
        self.assertEqual(json.loads(result.stdout)['decision'], 'block')

    def test_concurrent_memories_are_not_lost(self):
        processes = [subprocess.Popen(self.command() + ['remember', 'preference-%d' % i], cwd=self.root,
                        env=self.env, stdout=subprocess.PIPE, stderr=subprocess.PIPE) for i in range(8)]
        results = [(process, process.communicate(timeout=60)) for process in processes]
        for process, (out, err) in results:
            self.assertEqual(process.returncode, 0, (out, err))
        lines = (self.root / '.continuum/memory/MEMORY.md').read_text(encoding='utf-8').splitlines()
        self.assertEqual(sum(line.startswith('- ') for line in lines), 8)
        self.assertFalse((self.root / '.continuum/memory/.write-lock').exists())

    def test_context_budget_preserves_tasks_and_truncation_notice(self):
        self.ledger()
        (self.root / '.aicontext/STATE.md').write_text('State line ' + ('x' * 180 + '\n') * 300)
        (self.root / '.aicontext/JOURNAL.md').write_text('## Recent\n' + ('j' * 180 + '\n') * 300)
        (self.root / '.aicontext/TASKS.md').write_text('## In progress\n- TASK_SENTINEL\n')
        result = self.helper('context')
        self.assertLess(len(result.stdout), 24000)
        self.assertIn('Context truncated', result.stdout)
        self.assertIn('TASK_SENTINEL', result.stdout)

    def test_untracked_content_change_detected(self):
        self.ledger()
        f = self.root / 'new file.txt'
        f.write_text('before')
        self.helper('catch-up', data='{"session_id":"untracked"}')
        os.utime(self.root / '.aicontext/STATE.md', (time.time() - 3600,) * 2)
        f.write_text('after')
        self.assertEqual(json.loads(self.helper('guard', data='{"session_id":"untracked"}').stdout)['decision'], 'block')

    def test_corrupt_manifest_save_is_failure(self):
        self.ledger()
        f = self.root / '.aicontext/manifest.json'
        f.write_text('{bad')
        result = self.helper('save', check=False)
        self.assertNotEqual(result.returncode, 0)
        self.assertNotIn('handoff saved', result.stdout)
        self.assertEqual(f.read_text(), '{bad')
        self.assertFalse((self.root / '.aicontext/.write-lock').exists())

    def test_git_line_ending_warnings_do_not_fail_save(self):
        self.ledger()
        self.run_cmd(['git', 'config', 'core.autocrlf', 'true'])
        self.run_cmd(['git', 'config', 'core.safecrlf', 'warn'])
        (self.root / 'work.txt').write_bytes(b'new LF-only work\n')
        self.assertIn('handoff saved', self.helper('save').stdout)
        d = json.loads((self.root / '.aicontext/manifest.json').read_text(encoding='utf-8'))['continuum']
        self.assertEqual(d['sessionCount'], 1)

    def test_session_identifier_cannot_write_outside_marker_directory(self):
        self.ledger()
        self.helper('catch-up', data='{"session_id":"../../escaped"}')
        self.assertFalse((self.root / 'escaped.env').exists())
        markers = list((self.root / '.aicontext/.session').glob('*.env'))
        self.assertEqual(len(markers), 1)
        self.assertEqual(len(markers[0].stem), 64)

    def test_concurrent_saves_preserve_session_count(self):
        self.ledger()
        processes = [subprocess.Popen(self.command() + ['save', '--agent', 'writer-%d' % i], cwd=self.root,
                        env=self.env, stdout=subprocess.PIPE, stderr=subprocess.PIPE) for i in range(3)]
        results = [(process, process.communicate(timeout=60)) for process in processes]
        for process, (out, err) in results:
            self.assertEqual(process.returncode, 0, (out, err))
        d = json.loads((self.root / '.aicontext/manifest.json').read_text(encoding='utf-8'))['continuum']
        self.assertEqual(d['sessionCount'], 3)
        self.assertTrue(all('writer-%d' % i in d['agentsSeen'] for i in range(3)))


@unittest.skipUnless(PS and BASH, 'requires Windows PowerShell and Git Bash')
class CrossHelper(Sandbox):
    def test_handoff_fingerprint_is_shared_between_helpers(self):
        self.ledger()
        bash = [BASH, str(REPO / 'bin/continuum.sh')]
        ps = [PS, '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', str(REPO / 'bin/continuum.ps1')]
        for first, second in ((bash, ps), (ps, bash)):
            with self.subTest(first=first[0]):
                self.run_cmd(first + ['catch-up'], '{"session_id":"shared"}')
                (self.root / 'work.txt').write_text('changed-' + first[0])
                (self.root / 'untracked.txt').write_text('new-' + first[0])
                self.run_cmd(second + ['save', '--agent', 'other-helper'])
                self.assertEqual(self.run_cmd(first + ['guard'], '{"session_id":"shared"}').stdout, '')

    def test_concurrent_memory_writes_share_one_lock(self):
        commands = [[BASH, str(REPO / 'bin/continuum.sh')],
                    [PS, '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', str(REPO / 'bin/continuum.ps1')]]
        processes = [subprocess.Popen(commands[i % 2] + ['remember', 'shared-%d' % i], cwd=self.root,
                        env=self.env, stdout=subprocess.PIPE, stderr=subprocess.PIPE) for i in range(8)]
        results = [(process, process.communicate(timeout=60)) for process in processes]
        for process, (out, err) in results:
            self.assertEqual(process.returncode, 0, (out, err))
        lines = (self.root / '.continuum/memory/MEMORY.md').read_text(encoding='utf-8').splitlines()
        self.assertEqual(sum(line.startswith('- ') for line in lines), 8)


@unittest.skipUnless(BASH, "Bash not installed")
class BashInstaller(InstallerChecks, Sandbox):
    platform = "bash"


@unittest.skipUnless(PS, "PowerShell not installed")
class PowerShellInstaller(InstallerChecks, Sandbox):
    platform = "powershell"


@unittest.skipUnless(BASH, "Bash not installed")
class BashHelper(HelperChecks, Sandbox):
    platform = "bash"


@unittest.skipUnless(PS, "PowerShell not installed")
class PowerShellHelper(HelperChecks, Sandbox):
    platform = "powershell"


if __name__ == "__main__":
    unittest.main(verbosity=2)
