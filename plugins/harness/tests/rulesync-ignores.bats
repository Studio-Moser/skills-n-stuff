#!/usr/bin/env bats

@test "the generated skills ignore block keeps CRLF, user lines, and dropped skills until their folder is gone" {
  run python3 - "${BATS_TEST_DIRNAME}/../scripts/sync" "$BATS_TEST_TMPDIR/repo" <<'PY'
import importlib.machinery, importlib.util, pathlib, subprocess, sys
loader = importlib.machinery.SourceFileLoader("sync", sys.argv[1])
spec = importlib.util.spec_from_loader("sync", loader); m = importlib.util.module_from_spec(spec); loader.exec_module(m)
r = pathlib.Path(sys.argv[2]); r.mkdir(); subprocess.run(["git", "init", "-q", str(r)], check=True)
(r/".rulesync/skills/mine").mkdir(parents=True); (r/".rulesync/skills/.curated/alpha").mkdir(parents=True)
(r/"skills/alpha").mkdir(parents=True); (r/"skills/old").mkdir()
(r/".gitignore").write_bytes(("user1\r\n" + m.SKILLS_BLOCK[0] + "\r\n/skills/old/\r\n" + m.SKILLS_BLOCK[1] + "\r\nuser2\r\n").encode())
m.ensure_rulesync_ignores(r); first = (r/".gitignore").read_bytes()
m.ensure_rulesync_ignores(r); assert first == (r/".gitignore").read_bytes(), "not idempotent"
text = first.decode(); assert "\n" not in text.replace("\r\n", ""), "CRLF lost"
assert all(x in text for x in ("/skills/old/", "/skills/alpha/", "/skills/mine/", "user1", "user2")), text
(r/"skills/old").rmdir(); m.ensure_rulesync_ignores(r); assert "/skills/old/" not in (r/".gitignore").read_text()
(r/".gitignore").write_text("u1\n" + m.SKILLS_BLOCK[0] + "\nu2\nu3\n")  # end marker deleted by hand
m.ensure_rulesync_ignores(r); m.ensure_rulesync_ignores(r); g = (r/".gitignore").read_text()
assert all(x in g.splitlines() for x in ("u1", "u2", "u3")) and g.count(m.SKILLS_BLOCK[0]) == 1, g
PY
  [ "$status" -eq 0 ]
}
