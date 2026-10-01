from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[1]
VARIANTS = {
    "WinApiMemoryLossFollow.mq5": ("WMLFC", "MemorySourceExists", 3, "WinApiMemoryNameHash"),
    "MemoryLossFollow.mq5": ("MLFC", "MemorySourceExists", 3, "LossFollowNameHash"),
    "FileLossFollow.mq5": ("FLFC", "FileSourceExists", 3, "LossFollowNameHash"),
    "LossFollowCopier.mq5": ("LFC", "LocalSourceExists", 2, "LossFollowNameHash"),
}


def function_body(source: str, signature: str) -> str:
    start = source.index(signature)
    brace = source.index("{", start)
    depth = 0
    for index in range(brace, len(source)):
        if source[index] == "{":
            depth += 1
        elif source[index] == "}":
            depth -= 1
            if depth == 0:
                return source[start:index + 1]
    raise AssertionError(f"unbalanced function: {signature}")


def code_only(source: str) -> str:
    """Remove comments and string/character literals for delimiter checks."""
    out = []
    i = 0
    state = "code"
    while i < len(source):
        ch = source[i]
        nxt = source[i + 1] if i + 1 < len(source) else ""
        if state == "code":
            if ch == "/" and nxt == "/":
                out.extend("  ")
                i += 2
                state = "line"
                continue
            if ch == "/" and nxt == "*":
                out.extend("  ")
                i += 2
                state = "block"
                continue
            if ch in ('"', "'"):
                out.append(" ")
                state = ch
                i += 1
                continue
            out.append(ch)
            i += 1
            continue
        if state == "line":
            if ch == "\n":
                out.append("\n")
                state = "code"
            else:
                out.append(" ")
            i += 1
            continue
        if state == "block":
            if ch == "*" and nxt == "/":
                out.extend("  ")
                i += 2
                state = "code"
            else:
                out.append("\n" if ch == "\n" else " ")
                i += 1
            continue
        # string or character literal
        if ch == "\\":
            out.extend("  ")
            i += 2
        elif ch == state:
            out.append(" ")
            i += 1
            state = "code"
        else:
            out.append("\n" if ch == "\n" else " ")
            i += 1
    return "".join(out)


class LossFollowVariantTests(unittest.TestCase):
    def test_each_variant_has_separate_trade_outcome_policies(self):
        for filename in VARIANTS:
            source = (ROOT / filename).read_text()
            self.assertNotIn("IsSuccessRetcode", source, filename)
            self.assertIn("bool IsPendingPlacementRetcode", source, filename)
            self.assertIn("bool IsDealCompleteRetcode", source, filename)
            self.assertIn("bool IsRemoveCompleteRetcode", source, filename)
            pending = function_body(source, "bool PlaceCopyPending(")
            self.assertIn("request.type_filling = ORDER_FILLING_RETURN", pending, filename)
            self.assertIn("IsPendingPlacementRetcode(result.retcode)", pending, filename)
            self.assertIn("RememberCopyPositionMappingByIdentifier", pending, filename)
            close = function_body(source, "bool CloseCopyPosition(")
            self.assertIn("TRADE_RETCODE_DONE_PARTIAL", close, filename)
            self.assertIn("IsDealCompleteRetcode(result.retcode)", close, filename)

    def test_each_variant_retries_partial_open_and_cleans_it(self):
        for filename, (_, _, minimum_calls, _) in VARIANTS.items():
            source = (ROOT / filename).read_text()
            self.assertIn("string PartialCopyGlobalName", source, filename)
            self.assertIn("double PartialRetryVolume", source, filename)
            self.assertGreaterEqual(source.count("PartialRetryVolume("), minimum_calls + 1, filename)
            opening = function_body(source, "bool OpenCopyTrade(")
            self.assertIn("result.retcode == TRADE_RETCODE_DONE_PARTIAL", opening, filename)
            self.assertIn("GlobalVariableSet(PartialCopyGlobalName", opening, filename)
            self.assertIn("GlobalVariableDel(PartialCopyGlobalName", opening, filename)
            already = function_body(source, "bool IsAlreadyCopied(")
            self.assertIn("GlobalVariableCheck(PartialCopyGlobalName", already, filename)

    def test_each_variant_has_bounded_namespace_and_lifecycle_cleanup(self):
        for filename, (prefix, source_exists, _, hash_name) in VARIANTS.items():
            source = (ROOT / filename).read_text()
            self.assertIn(hash_name, source, filename)
            self.assertIn(f'"{prefix}_"', source, filename)
            self.assertNotIn('g_prefix + "CLOSING_" + IntegerToString((long)InpCopyMagic)', source, filename)
            self.assertNotIn('g_prefix + IntegerToString((long)InpCopyMagic)', source, filename)
            cleanup = function_body(source, "void CleanupFinishedCopyState(")
            self.assertIn(source_exists + "(source_ticket)", cleanup, filename)
            self.assertIn("HasLiveCopyOrPendingForSourceLevel", cleanup, filename)
            self.assertIn("GlobalVariableDel(name)", cleanup, filename)
            self.assertIn("CleanupFinishedCopyState();", function_body(source, "void CheckPositions("), filename)

    def test_seed_first_mode_is_wired_in_all_variants(self):
        for filename in VARIANTS:
            source = (ROOT / filename).read_text()
            self.assertIn("ENTRY_GRID_SEED_FIRST", source, filename)
            self.assertIn("double grid_seed_percent;", source, filename)
            self.assertIn("InpEA1GridSeedPercent = 20.0", source, filename)
            self.assertIn("InpEA2GridSeedPercent = 20.0", source, filename)
            self.assertIn("profile.grid_seed_percent = InpEA1GridSeedPercent", source, filename)
            self.assertIn("profile.grid_seed_percent = InpEA2GridSeedPercent", source, filename)
            self.assertIn("grid_seed_percent <= 0.0 || profile.grid_seed_percent > 100.0", source, filename)
            self.assertIn("void ProcessGridSeedFirstGroup(", source, filename)
            self.assertIn("double CopyVolumeForSourceLevel(", source, filename)
            self.assertIn("ulong GridSeedSource(", source, filename)
            self.assertIn("void ResetInactiveGridSeedSources()", source, filename)
            check = function_body(source, "void CheckPositions(")
            self.assertIn("ResetInactiveGridSeedSources();", check, filename)

            # The defaults mean every source magic is accepted unless the user narrows it.
            self.assertRegex(source, r"InpEA1Magic\s*=\s*-1\s*;", filename)
            self.assertRegex(source, r"InpEA2Magic\s*=\s*-1\s*;", filename)

            grid = function_body(source, "void ProcessGridSeedFirstGroup(")
            self.assertIn("target_volume = triggered", grid, filename)
            self.assertIn("full_volume * profile.grid_seed_percent / 100.0", grid, filename)
            self.assertIn("double delta = target_volume - copied_volume", grid, filename)
            self.assertIn("if(IsAlreadyCopied(source", grid, filename)
            self.assertIn("CalculateCopyVolume", grid, filename)
            self.assertIn("IsGridGroupStopped(profile.profile_index, symbol, position_type)", grid, filename)

            process_grid = function_body(source, "void ProcessGridGroup(")
            self.assertIn("ProcessGridSeedFirstGroup(profile, symbol, position_type);", process_grid, filename)

    def test_source_text_is_balanced_and_functions_are_unique(self):
        signatures = [
            r"\b(?:bool|void|double|string|uint)\s+(?:OpenCopyTrade|CloseCopyPosition|IsAlreadyCopied|CleanupFinishedCopyState|PartialRetryVolume|LossFollowNameHash)\s*\(",
        ]
        for filename in VARIANTS:
            source = (ROOT / filename).read_text()
            stripped = code_only(source)
            self.assertEqual(stripped.count("{"), stripped.count("}"), filename)
            self.assertEqual(stripped.count("("), stripped.count(")"), filename)
            for pattern in signatures:
                matches = re.findall(pattern, source)
                self.assertEqual(len(matches), len(set(matches)), filename)

    def test_packaged_mirrors_match_the_edited_sources(self):
        mirror_root = ROOT / "upload-repo"
        if not mirror_root.is_dir():
            return
        for filename in VARIANTS:
            self.assertEqual(
                (ROOT / filename).read_bytes(),
                (mirror_root / filename).read_bytes(),
                filename,
            )


if __name__ == "__main__":
    unittest.main()
