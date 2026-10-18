import json
from pathlib import Path

import pytest

from agentbench.cli import main

from conftest import MY_PID, cli_args, start_mock

SUITE_ARGS = {"gate": [], "m1": [], "m2": [], "m3": ["--spec-label", "off"], "m4": [], "m5": [],
              "m6": ["--minutes", "0.02", "--mem-interval", "0.5", "--server-pid", MY_PID], "m7": []}


def read(path: Path) -> list[dict]:
    return [json.loads(x) for x in path.read_text(encoding="utf-8").splitlines()]


@pytest.fixture(scope="module")
def generic(built):
    srv, resp = start_mock(built[0], "generic")
    yield srv, resp
    srv.stop()


@pytest.mark.parametrize("suite", list(SUITE_ARGS))
def test_each_suite_quick_end_to_end(built, generic, tmp_path, suite):
    root, _ = built
    srv, _ = generic
    assert main([suite] + cli_args(srv.url, root, tmp_path, "omlx", "omlx", *SUITE_ARGS[suite])) == 0
    files = list((tmp_path / "omlx" / "raw").glob(f"{suite}-t-*.jsonl"))
    assert len(files) == 1
    lines = read(files[0])
    h = lines[0]
    assert h["type"] == "header" and h["suite"] == suite and h["tag"] == "t" and h["mode"]["quick"]
    assert h["system"]["sw_vers"] and "xcodebuild" in h["system"] and "commit" in h["harness"]
    assert "/Users/" not in files[0].read_text(encoding="utf-8")
    reqs = [x for x in lines if x["type"] == "request"]
    expected_errors = ("G4.effort-high", "G4.effort-minimal")  # the template rejects these efforts; that is a finding
    checked = [r for r in reqs if r.get("probe") not in expected_errors]
    assert checked and all(r["metrics"]["ok"] for r in checked), [r["metrics"]["error"] for r in checked if not r["metrics"]["ok"]]
    summary = lines[-1]
    assert summary["type"] == "summary" and summary["suite"] == suite
    if suite == "gate":
        assert {k: v["result"] for k, v in summary["items"].items()} == {
            "G1": "PASS", "G2": "PASS", "G3": "PASS", "G4": "PASS", "G5": "INFO"}
        cap = (tmp_path / "omlx" / "capabilities.md").read_text()
        assert "<!-- agentbench:begin gate t -->" in cap and "| G2 |" in cap
        assert files[0].with_suffix(".md").exists()
    if suite == "m1":
        warm = [r["metrics"] for r in reqs if r["phase"] == "warm"]
        cold = [r["metrics"] for r in reqs if r["phase"] == "cold"]
        assert warm and cold and all(m["cached_tokens"] > 10_000 for m in warm) and cold[0]["cached_tokens"] == 0
        assert warm[0]["ttft_s"] < cold[0]["ttft_s"] and warm[0]["first_kind"]
        assert reqs[0]["phase"] == "warmup" and reqs[0]["prompt"]["n_images"] == 0
        assert all(r["prompt"]["n_images"] == 1 for r in reqs if r["phase"] in ("warm", "cold"))
        assert len({r["request_id"] for r in reqs if "request_id" in r}) == len(warm) + len(cold)
    if suite == "m2":
        t = [r for r in reqs if r["phase"] == "trial"]
        assert t[0]["derived"]["throughput_tps"] > 0 and t[0]["metrics"]["cached_tokens"] <= 5
    if suite == "m3":
        t = [r for r in reqs if r["phase"] == "trial"]
        assert {r["cell"]["thinking"] for r in t} == {False, True}
        assert all(r["derived"]["hit_cap"] and r["metrics"]["completion_tokens"] == r["cell"]["cap"] for r in t)
        assert all(r["metrics"]["decode_tps"] for r in t) and summary["spec"] == "off"
    if suite == "m4":
        steps = sorted(r["step"] for r in reqs)
        assert steps == [0, 1, 2, 3]
        by = {r["step"]: r["metrics"] for r in reqs}
        assert all(by[k]["cached_tokens"] >= by[k - 1]["prompt_tokens"] - 2 for k in (2, 3))
        assert [r["prompt"]["n_images"] for r in sorted(reqs, key=lambda r: r["step"])] == [0, 1, 2, 3]
        assert set(summary["per_step"]) == {"0", "1", "2", "3"}
    if suite == "m5":
        assert set(summary["cells"]) == {"0", "1", "2"}
        assert len([r for r in reqs if r.get("role", "").startswith("aux") and r["n_aux"] == 2]) == 2
    if suite == "m6":
        mem = [x for x in lines if x["type"] == "memory"]
        assert mem and summary["requests"] > 0 and summary["errors"] == 0
        assert summary["footprint"]["peak_tree_bytes"] and summary["memory"]["peak_tree_bytes"]
    if suite == "m7":
        assert summary["passed"] == summary["scored"] == 6


def test_text_only_mode_sends_no_images(built, generic, tmp_path):
    root, _ = built
    srv, resp = generic
    before = len(resp.requests)
    assert main(["m4"] + cli_args(srv.url, root, tmp_path, "omlx", "omlx", "--text-only", "--steps", "2")) == 0
    assert all(r["n_images"] == 0 for r in resp.requests[before:])
    lines = read(next((tmp_path / "omlx" / "raw").glob("m4-*.jsonl")))
    assert lines[0]["mode"]["text_only"]
    # same token count as the image run, by construction
    assert all(x["prompt"]["local_tokens"] for x in lines if x["type"] == "request")


def test_m7_scores_a_wrong_answer(built, tmp_path):
    root, _ = built
    srv, resp = start_mock(root, "generic")
    case = next(t for t in resp.answers if t.startswith("Close browser tabs"))
    resp.answers[case] = [{"name": "browser_close_tabs", "arguments": {"tab_ids": ["2", "5"]}}]
    try:
        assert main(["m7"] + cli_args(srv.url, root, tmp_path, "vllm", "vllm-metal", "--cases", "m7-06,m7-21")) == 0
    finally:
        srv.stop()
    s = read(next((tmp_path / "vllm-metal" / "raw").glob("m7-*.jsonl")))[-1]
    assert s["passed"] == 1 and s["scored"] == 2
    reasons = " ".join(s["failures"][0]["reasons"])
    assert "schema" in reasons and "expected the items" in reasons


def test_run_all_lithos_records_429_and_na(built, tmp_path):
    root, _ = built
    log = tmp_path / "lithos.log"
    srv, resp = start_mock(root, "lithos", log_path=str(log), token_delay=0.002)
    try:
        rc = main(["run-all"] + cli_args(srv.url, root, tmp_path, "lithos", "lithos-metal", "--server-log", str(log),
                                         "--suites", "gate,m1,m3,m5,m7", "--spec-label", "on", "--aux-lead", "0"))
    finally:
        srv.stop()
    assert rc == 0
    raw = tmp_path / "lithos-metal" / "raw"
    m5 = read(next(raw.glob("m5-*.jsonl")))
    trial = [x for x in m5 if x["type"] == "request" and x.get("phase") == "trial" and x["n_aux"] > 0]
    assert any(x["metrics"]["http_status"] == 429 for x in trial)  # concurrent requests rejected, recorded
    assert m5[0]["mode"]["text_only"] and "auto: G2 failed" in m5[0]["mode"]["text_only_reason"]
    m1 = read(next(raw.glob("m1-*.jsonl")))
    warm = [x["metrics"] for x in m1 if x.get("phase") == "warm"]
    assert all(m["cached_source"] == "server-log" and m["cached_tokens"] > 0 for m in warm)
    m3 = read(next(raw.glob("m3-*.jsonl")))
    assert any(x["type"] == "skip" and "thinking cannot be enabled" in x["reason"] for x in m3)
    m7 = read(next(raw.glob("m7-*.jsonl")))
    assert m7[-1]["na"] == 1 and m7[-1]["passed"] == m7[-1]["scored"]
    summary = (tmp_path / "lithos-metal" / "summary.md").read_text()
    assert "<!-- agentbench:begin summary t -->" in summary and "### M5 concurrency" in summary
    assert "| G4 |" in (tmp_path / "lithos-metal" / "capabilities.md").read_text()


def test_run_all_validates_arguments_first(built, generic, tmp_path):
    root, _ = built
    srv, _ = generic
    with pytest.raises(SystemExit):
        main(["run-all"] + cli_args(srv.url, root, tmp_path, "omlx", "omlx", "--suites", "m3,m6"))
    assert not (tmp_path / "omlx").exists()


def test_reserved_ports_are_refused(built, tmp_path):
    root, _ = built
    with pytest.raises(SystemExit):
        main(["m1"] + cli_args("http://127.0.0.1:8500", root, tmp_path, "omlx", "omlx"))
    assert main(["mock-server", "--port", "8703"]) == 2


def test_screenshot_inside_tool_message(built, generic, tmp_path):
    root, _ = built
    srv, _ = generic
    assert main(["m1"] + cli_args(srv.url, root, tmp_path, "omlx", "omlx", "--screenshot-placement", "tool")) == 0
    lines = read(next((tmp_path / "omlx" / "raw").glob("m1-*.jsonl")))
    trials = [x for x in lines if x.get("phase") in ("warm", "cold")]
    assert trials and all(x["prompt"]["n_messages"] == 4 and x["prompt"]["n_images"] == 1 for x in trials)
    assert lines[0]["mode"]["screenshot_placement"] == "tool"


def test_m6_without_server_pid_samples_system_memory(built, generic, tmp_path):
    root, _ = built
    srv, _ = generic
    assert main(["m6"] + cli_args(srv.url, root, tmp_path, "omlx", "omlx", "--minutes", "0.01", "--mem-interval", "0.5")) == 0
    s = read(next((tmp_path / "omlx" / "raw").glob("m6-*.jsonl")))[-1]
    assert s["footprint"]["peak_tree_bytes"] is None and s["footprint"]["peak_system_used_bytes"]
    assert s["memory"]["start_system_used_bytes"] and s["requests"] > 0


def test_run_all_defaults_spec_label_and_keeps_images_when_misread(built, tmp_path):
    root, _ = built
    srv, resp = start_mock(root, "generic")
    resp.code = None  # images are accepted but the code is never read back
    try:
        assert main(["run-all"] + cli_args(srv.url, root, tmp_path, "omlx", "omlx", "--suites", "gate,m1,m3")) == 0
    finally:
        srv.stop()
    raw = tmp_path / "omlx" / "raw"
    gate = read(next(raw.glob("gate-*.jsonl")))[-1]
    assert gate["items"]["G2"]["result"] == "FAIL" and not gate["items"]["G2"]["rejected"]
    m1 = read(next(raw.glob("m1-*.jsonl")))
    assert not m1[0]["mode"]["text_only"]  # still measured with images
    m3 = read(next(raw.glob("m3-*.jsonl")))
    assert m3[0]["args"]["spec_label"] == "off" and m3[-1]["spec"] == "off"


def test_preflight_failure_routes_to_unverified(built, generic, tmp_path):
    root, _ = built
    srv, _ = generic
    fake = tmp_path / "quiet_check.sh"
    fake.write_text("#!/bin/sh\necho 'quiet_check: test'\necho \"args: $*\"\necho 'verdict: NOT QUIET'\nexit 1\n")
    fake.chmod(0o755)
    assert main(["m2"] + cli_args(srv.url, root, tmp_path, "omlx", "omlx", "--preflight-cmd", str(fake))) == 0
    assert not list((tmp_path / "omlx" / "raw").glob("*.jsonl"))
    f = next((tmp_path / "omlx" / "raw" / "_unverified").glob("m2-*.jsonl"))
    h = read(f)[0]
    assert h["unverified"] and h["preflight"]["exit_code"] == 1 and "NOT QUIET" in h["preflight"]["output"]
    assert "--allow-pid" in h["preflight"]["output"]
    ok = tmp_path / "ok.sh"
    ok.write_text("#!/bin/sh\necho 'verdict: QUIET'\n")
    ok.chmod(0o755)
    assert main(["m2"] + cli_args(srv.url, root, tmp_path, "omlx", "omlx", "--preflight-cmd", str(ok))) == 0
    h = read(next((tmp_path / "omlx" / "raw").glob("m2-*.jsonl")))[0]
    assert not h["unverified"] and h["preflight"]["exit_code"] == 0
