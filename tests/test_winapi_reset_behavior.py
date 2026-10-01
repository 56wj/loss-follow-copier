"""Run the actual MQL reset/selection function bodies against a small C++ terminal fake.

This verifies state transitions, not MT4/MT5 compilation or broker execution.
"""
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

from test_loss_follow_variants import function_body


ROOT = Path(__file__).resolve().parents[1]
FUNCTIONS = [
    "uint WinApiMemoryNameHash(",
    "string CopyGlobalName(",
    "void MarkCopied(",
    "string GridStatePrefix(",
    "string GridGroupStateName(",
    "string TotalLossStatePrefix(",
    "string TotalLossGroupStateName(",
    "string ResetBlockGlobalName(",
    "bool BlockEntriesForStateChange(",
    "bool IsNumericStateId(",
    "bool IsCopyLevelStateTail(",
    "bool IsReceiverCycleState(",
    "bool ResetHasCopyExposure(",
    "void PanelResetFollowing(",
    "string GridInitialSourceName(",
    "bool IsGridInitialSourceSkipped(",
    "bool PrepareGridInitialSources(",
    "void CopyGridSources(",
    "void CheckPositions(",
]


class WinApiResetBehaviorTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        compiler = shutil.which("clang++") or shutil.which("g++")
        if not compiler:
            raise unittest.SkipTest("C++ compiler needed for MQL function-body harness")
        cls.temp = tempfile.TemporaryDirectory(prefix="winapi-reset-tests-")
        cls.addClassCleanup(cls.temp.cleanup)
        fixture = (ROOT / "tests/winapi_reset_harness.cpp").read_text()
        cls.executables = []
        for extension in ("mq5", "mq4"):
            source = (ROOT / f"WinApiMemoryLossFollow.{extension}").read_text()
            functions = list(FUNCTIONS)
            if extension == "mq5":
                functions.insert(0, "string GridSeedStatePrefix(")
            bodies = "\n\n".join(function_body(source, f) for f in functions)
            cpp = Path(cls.temp.name) / f"{extension}.cpp"
            exe = Path(cls.temp.name) / extension
            cpp.write_text(fixture.replace("// EA_FUNCTIONS", bodies))
            result = subprocess.run(
                [compiler, "-std=c++17", f"-D{extension.upper()}", str(cpp), "-o", str(exe)],
                capture_output=True, text=True,
            )
            if result.returncode:
                raise AssertionError(result.stderr)
            cls.executables.append(exe)

    def test_reset_and_grid_state_transitions(self):
        for exe in self.executables:
            for scenario in (
                "reset", "paused", "stale", "disconnected", "exposure", "scope",
                "delete_failure", "lock_failure", "unlock_failure", "recheck_failure",
                "grid_limit", "grid_retry", "grid_unlimited", "grid_write_failure", "entry_gates",
            ):
                with self.subTest(platform=exe.name, scenario=scenario):
                    result = subprocess.run([str(exe), scenario], capture_output=True, text=True)
                    self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_entry_gates_and_mirrors(self):
        for extension in ("mq5", "mq4"):
            filename = f"WinApiMemoryLossFollow.{extension}"
            source = (ROOT / filename).read_text()
            check = function_body(source, "void CheckPositions(")
            self.assertIn("g_snapshot_sequence != g_reset_snapshot_sequence", check)
            gate = "if(g_reset_blocked || g_reset_waiting_snapshot || PanelEntriesPaused())"
            self.assertLess(check.index(gate), check.index("CheckGridActivationEntries();"))
            self.assertIn("CheckGridActivationEntries();\n   if(g_reset_blocked)\n      return;", check)
            init = function_body(source, "int InitMemoryReceiver(")
            self.assertIn("g_reset_blocked = GlobalVariableCheck(ResetBlockGlobalName())", init)
            grid = function_body(source, "void ProcessGridGroup(")
            self.assertLess(grid.index("PrepareGridInitialSources("), grid.index("SetGridGroupActive("))
            event = function_body(source, "void PanelHandleChartEvent(")
            self.assertIn('if(PanelConfirmAction("RESET"))\n         PanelResetFollowing();', event)
            mirror = ROOT / "upload-repo" / filename
            if mirror.is_file():
                self.assertEqual((ROOT / filename).read_bytes(), mirror.read_bytes())


if __name__ == "__main__":
    unittest.main()
