"""Synthetic report checks; these fixtures are not performance measurements."""
import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location("report", Path(__file__).parents[1] / "tools/checkpoint_report.py")
report = importlib.util.module_from_spec(spec)
spec.loader.exec_module(report)


class ReportTest(unittest.TestCase):
    def fixture(self):
        return {"environment": {}, "shutdown": {"passed": True},
                "network": {"socket_dropped_frames": 0},
                "process": {"sample_window_seconds": 60, "sample_window_raw_seconds": 60},
                "server": {"passed": True, "minimum_roster": 10, "elapsed_seconds": 60,
                           "system_elapsed_seconds": 60, "session_tick_us": {}, "persistence_us": {},
                           "simultaneous_extras": [{"checkpoints": 10}],
                           "skylab": {str(i): {"before_at": 0, "after_at": 60,
                                      "before_inventory": {}, "after_inventory": {"ore": 1}} for i in range(10)},
                           "persistence_events": [{"kind": kind, "succeeded": True,
                                                   "stages_us": dict.fromkeys(report.STAGES, 1)}
                                                  for kind in ("replace_backup", "replace_primary", "replace_journal")]}}

    def test_nearest_rank_including_max_and_empty(self):
        self.assertEqual(report.distribution(range(1, 101)), {"count": 100, "p95": 95, "p99": 99, "max": 100})
        self.assertIsNone(report.distribution([])["p99"])

    def test_complete_activity_is_explicitly_source_only(self):
        result = report.summarize(self.fixture())
        self.assertTrue(result["activity_and_capture_checks_passed"])
        self.assertIn("not exported", result["runtime_scope"])

    def test_diagnostic_inputs_are_rejected(self):
        for mutation in (lambda r: r["server"].update(passed=False),
                         lambda r: r["server"].update(simultaneous_extras=[]),
                         lambda r: r["server"].update(persistence_events=[]),
                         lambda r: r["server"].update(skylab={}),
                         lambda r: r["network"].update(socket_dropped_frames=1),
                         lambda r: r["server"]["persistence_events"][0].update(succeeded=False)):
            fixture = self.fixture()
            mutation(fixture)
            self.assertFalse(report.summarize(fixture)["activity_and_capture_checks_passed"])


if __name__ == "__main__":
    unittest.main()
