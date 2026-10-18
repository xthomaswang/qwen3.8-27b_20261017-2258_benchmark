import pytest

from agentbench.cli import main
from agentbench.summarize import summarize
from agentbench.suites.common import upsert_section

from conftest import MY_PID, cli_args, start_mock


@pytest.fixture(scope="module")
def run_dir(built, tmp_path_factory):
    root, _ = built
    out = tmp_path_factory.mktemp("out")
    srv, _ = start_mock(root, "generic")
    try:
        rc = main(["run-all"] + cli_args(srv.url, root, out, "omlx", "omlx", "--suites", "gate,m1,m2,m3,m4,m5,m6,m7",
                                         "--spec-label", "off", "--minutes", "0.02", "--mem-interval", "0.5",
                                         "--server-pid", MY_PID))
    finally:
        srv.stop()
    assert rc == 0
    return out


def test_run_all_writes_summary_with_every_suite(run_dir):
    md = (run_dir / "omlx" / "summary.md").read_text()
    for title in ("Gate G1-G5", "M1 cached-prefix TTFT", "M2 cold prefill", "M3 short structured decode",
                  "M4 20-step trajectory", "M5 concurrency", "M6 memory and stability", "M7 tool-call correctness"):
        assert f"### {title}" in md, title
    assert md.count("<!-- agentbench:begin summary t -->") == 1


def test_tables_have_median_min_max_and_m4_per_step(run_dir):
    md = summarize(run_dir / "omlx", "t")
    assert "| warm | 2 | " in md and "| cold | 1 | " in md
    warm_row = next(line for line in md.splitlines() if line.startswith("| warm |"))
    assert "(" in warm_row and "-" in warm_row  # median (min-max)
    m4 = md[md.index("### M4"):md.index("### M5")]
    rows = [line for line in m4.splitlines() if line.startswith("| ") and line[2].isdigit()]
    assert [r.split("|")[1].strip().split()[0] for r in rows] == ["0", "1", "2", "3"]
    assert "TTFT slope" in m4
    assert "| 2,000 |" in md and "| off | off | 2,000 | 50 |" in md and "Passed 6/6." in md


def test_summarize_write_is_idempotent_and_keeps_other_text(run_dir, tmp_path):
    path = run_dir / "omlx" / "summary.md"
    path.write_text("# omlx: results\n\nHand-written notes stay.\n\n" + path.read_text().split("\n", 1)[1])
    assert main(["summarize", "--framework", "omlx", "--tag", "t", "--write", "--out-root", str(run_dir)]) == 0
    assert main(["summarize", "--framework", "omlx", "--write", "--out-root", str(run_dir)]) == 0
    text = path.read_text()
    assert "Hand-written notes stay." in text and text.count("<!-- agentbench:begin summary t -->") == 1


def test_upsert_section(tmp_path):
    p = tmp_path / "x.md"
    upsert_section(p, "gate a", "one", "Title")
    upsert_section(p, "gate b", "two", "Title")
    upsert_section(p, "gate a", "three", "Title")
    t = p.read_text()
    assert t.startswith("# Title") and "three" in t and "one" not in t and t.index("three") < t.index("two")


def test_summarize_all_runs_pools_files(run_dir):
    md = summarize(run_dir / "omlx", "t", all_runs=True)
    assert "### M1 cached-prefix TTFT" in md


def test_cap_truncated_streams_count_as_latency_samples():
    """oMLX ends a stream with `incomplete_tool_call` when the token cap cuts a tool call; its TTFT
    and e2e are still complete measurements (llama.cpp reports the same case as finish=length)."""
    from agentbench.summarize import cap_truncated, s_m4

    def line(step, ok, err=None, ttft=1.0, e2e=2.0):
        return {"type": "request", "phase": "start" if step == 0 else "step", "step": step, "run": 0,
                "metrics": {"ok": ok, "error": err, "ttft_s": ttft, "e2e_s": e2e, "cached_tokens": 90 if ok else None,
                            "prompt_tokens": 100 if ok else None, "prompt_tokens_local": 100}}

    trunc = ("stream_error: {'message': 'Model output contains an unrecoverable tool call.', "
             "'code': 'incomplete_tool_call'}")
    lines = [line(0, True), line(1, False, trunc, ttft=1.5), line(2, True, ttft=2.0),
             line(3, False, "HTTP 500: boom", ttft=None, e2e=None)]
    assert cap_truncated(lines[1]["metrics"]) and not cap_truncated(lines[3]["metrics"])
    md = s_m4([{"lines": lines + [{"type": "summary", "run_total_e2e_s": [6.0]}]}])
    rows = {r.split("|")[1].strip().split()[0]: r.split("|") for r in md.splitlines() if r.startswith("| ") and r[2].isdigit()}
    assert rows["1"][2].strip() == "1" and rows["1"][-2].strip() == "0"  # counted, not an error
    assert rows["3"][2].strip() == "0" and rows["3"][-2].strip() == "1"  # a real error stays an error
    assert "slope over steps 1-3: 0.5000 s/step" in md
    assert "1 of 4 requests ended at the token cap" in md
