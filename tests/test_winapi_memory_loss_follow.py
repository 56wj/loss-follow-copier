import re
import unittest
from pathlib import Path


SOURCE = Path(__file__).resolve().parents[1] / "WinApiMemoryLossFollow.mq5"


def section(source: str, start: str, end: str) -> str:
    start_at = source.index(start)
    end_at = source.index(end, start_at)
    return source[start_at:end_at]


class WinApiMemoryLossFollowSourceTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.source = SOURCE.read_text(encoding="utf-8-sig")

    def test_pending_orders_force_return_filling(self):
        pending = section(self.source, "request.action = TRADE_ACTION_PENDING;", "ApplyStops(request")
        self.assertIn("request.type_filling = ORDER_FILLING_RETURN;", pending)
        self.assertNotIn("request.type_filling = GetFillingType(symbol);", pending)

    def test_trade_actions_have_separate_retcode_policies(self):
        self.assertNotIn("IsSuccessRetcode", self.source)
        pending = section(self.source, "bool sent = OrderSend(request, result);", "ulong position_identifier",)
        self.assertIn("IsPendingPlacementRetcode(result.retcode)", pending)

        opening = section(self.source, "bool OpenCopyTrade(", "bool DeleteCopyPending(")
        closing = section(self.source, "bool CloseCopyPosition(", "bool IsCloseRetryCoolingDown(")
        removing = section(self.source, "bool DeleteCopyPending(", "bool CloseCopyPosition(")
        self.assertIn("IsDealCompleteRetcode(result.retcode)", opening)
        self.assertIn("IsDealCompleteRetcode(result.retcode)", closing)
        self.assertIn("IsRemoveCompleteRetcode(result.retcode)", removing)

    def test_partial_market_fill_records_residual_and_retries(self):
        opening = section(self.source, "bool OpenCopyTrade(", "bool DeleteCopyPending(")
        self.assertIn("result.retcode == TRADE_RETCODE_DONE_PARTIAL", opening)
        self.assertIn("GlobalVariableSet(PartialCopyGlobalName(source_ticket, level_index), retry_volume)", opening)
        self.assertIn("PartialRetryVolume(symbol, source_ticket, level_index, volume)", self.source)
        already = section(self.source, "bool IsAlreadyCopied(", "void MarkCopied(")
        self.assertIn("PartialCopyGlobalName(source_ticket, level_index)", already)
        self.assertIn("return false;", already)

    def test_partial_close_is_failure_and_keeps_retry_marker(self):
        closing = section(self.source, "bool CloseCopyPosition(", "bool IsCloseRetryCoolingDown(")
        partial = closing.index("result.retcode == TRADE_RETCODE_DONE_PARTIAL")
        self.assertIn("return false;", closing[partial:])
        success = closing.index("IsDealCompleteRetcode(result.retcode)")
        self.assertIn("GlobalVariableDel(CloseAttemptGlobalName(copy_ticket));", closing[success:])

    def test_state_prefix_is_hash_scoped_and_bounded(self):
        init = section(self.source, "g_prefix =", "ENUM_ACCOUNT_MARGIN_MODE")
        self.assertIn("WinApiMemoryNameHash", init)
        self.assertNotIn("SanitizeNamePart(InpChannelName)", init)

        # Model the longest ordinary MT5 identifiers used by the state keys.
        prefix = "WMLFC_" + str(0xFFFFFFFF) + "_"
        max_ticket = "18446744073709551615"
        self.assertLessEqual(len(prefix + "PARTIAL_" + max_ticket + "_L3"), 63)
        self.assertLessEqual(len(prefix + "P_SRC_" + max_ticket), 63)
        self.assertLessEqual(len(prefix + "CLOSING_" + max_ticket), 63)

    def test_finished_state_cleanup_is_called_and_removes_markers(self):
        check = section(self.source, "void CheckPositions()", "void CheckGridActivationEntries()")
        self.assertIn("CleanupFinishedCopyState();", check)
        cleanup = section(self.source, "void CleanupFinishedCopyState()", "bool IsStringInArray(")
        self.assertIn("GlobalVariableDel(name);", cleanup)
        self.assertIn("MemorySourceExists(source_ticket)", cleanup)
        self.assertIn("HasLiveCopyOrPendingForSourceLevel", cleanup)

    def test_source_balances_and_no_duplicate_function_definitions(self):
        self.assertEqual(self.source.count("{"), self.source.count("}"))
        self.assertEqual(self.source.count("("), self.source.count(")"))
        definitions = re.findall(
            r"(?m)^\s*(?:bool|void|int|uint|long|ulong|double|string|datetime|ENUM_[A-Z0-9_]+)\s+([A-Za-z_]\w*)\s*\(",
            self.source,
        )
        duplicates = {name for name in definitions if definitions.count(name) > 1}
        self.assertEqual(duplicates, set())


if __name__ == "__main__":
    unittest.main()
