#!/usr/bin/env python3
"""Static regression checks for MT5 variants and the MT4 WinAPI peer."""

from __future__ import annotations

import re
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
FILES = {
    "dll_memory": ROOT / "MemoryLossFollow.mq5",
    "winapi_memory": ROOT / "WinApiMemoryLossFollow.mq5",
    "file_snapshot": ROOT / "FileLossFollow.mq5",
}
MT4_WINAPI = ROOT / "WinApiMemoryLossFollow.mq4"
ZERO_TRIGGER_FILES = {
    "mt4_winapi": MT4_WINAPI,
    "mt5_winapi": ROOT / "WinApiMemoryLossFollow.mq5",
    "dll_memory": ROOT / "MemoryLossFollow.mq5",
    "file_snapshot": ROOT / "FileLossFollow.mq5",
    "same_account": ROOT / "LossFollowCopier.mq5",
    "remote_receiver": ROOT / "RemoteLossFollowReceiver.mq5",
}

EVENTS = (
    "OnInit",
    "OnDeinit",
    "OnTick",
    "OnTimer",
    "OnChartEvent",
    "OnTradeTransaction",
)
CORE_FUNCTIONS = (
    "CheckPositions",
    "CheckGridActivationEntries",
    "CheckTotalLossActivationEntries",
    "ProcessGridGroup",
    "ProcessTotalLossGroup",
    "SourceTotalLossStats",
    "SourcePositionProfitMoney",
    "CopyTotalLossSources",
    "ProcessSourceLevel",
    "IsCopyDirectionAllowed",
    "OpenCopyTrade",
    "CloseCopiesWithoutSource",
    "DeletePendingsWithoutSource",
    "CheckMinuteProfitClose",
    "CheckBasketProfitClose",
    "ApplyFirstEntryTimeFilter",
    "ValidateBeijingFirstEntryTimeFilter",
    "ResetInactiveGridGroups",
    "CalculateCopyVolume",
    "MatchSourceProfile",
    "PanelInitialize",
    "PanelUpdate",
    "PanelCloseAllCopies",
    "PanelDeleteAllPendings",
    "PanelHandleChartEvent",
    "RoundKeyIndex",
    "AddRoundCopyCount",
    "ParseBasketKey",
    "TotalLossBasketKey",
    "RoundTrackingKey",
    "ParseRoundTrackingKey",
    "SourceRoundExists",
    "SourceTotalLossRoundExists",
    "StopActiveCopyRounds",
    "UpdateRoundCopyTracking",
    "TotalLossStatePrefix",
    "TotalLossGroupStateName",
    "IsTotalLossGroupActive",
    "IsTotalLossGroupStopped",
    "SetTotalLossGroupActive",
    "SetTotalLossGroupStopped",
    "ParseTotalLossStateName",
    "ResetInactiveTotalLossGroups",
)
PROTOCOL_SHARED_FUNCTIONS = (
    "WinApiMemoryCrc32",
    "WinApiMemoryNameHash",
    "WinApiMemoryObjectPart",
    "SenderBuildSnapshotText",
    "SenderWritePausedSnapshot",
    "SenderPublishPayload",
    "EscapeMemoryField",
    "ParseMemorySnapshot",
    "UnescapeMemoryField",
)


def fail(message: str) -> None:
    raise AssertionError(message)


def mask_comments_and_strings(source: str) -> str:
    """Replace comments/string contents while preserving offsets and newlines."""
    chars = list(source)
    i = 0
    state = "code"
    while i < len(chars):
        current = chars[i]
        following = chars[i + 1] if i + 1 < len(chars) else ""
        if state == "code":
            if current == "/" and following == "/":
                chars[i] = chars[i + 1] = " "
                state = "line_comment"
                i += 2
                continue
            if current == "/" and following == "*":
                chars[i] = chars[i + 1] = " "
                state = "block_comment"
                i += 2
                continue
            if current == '"':
                state = "string"
                i += 1
                continue
        elif state == "line_comment":
            if current == "\n":
                state = "code"
            else:
                chars[i] = " "
        elif state == "block_comment":
            if current == "*" and following == "/":
                chars[i] = chars[i + 1] = " "
                state = "code"
                i += 2
                continue
            if current != "\n":
                chars[i] = " "
        else:
            if current == "\\" and i + 1 < len(chars):
                chars[i] = chars[i + 1] = " "
                i += 2
                continue
            if current == '"':
                state = "code"
            else:
                if current != "\n":
                    chars[i] = " "
        i += 1
    if state in {"block_comment", "string"}:
        fail(f"unterminated {state}")
    return "".join(chars)


def check_delimiters(name: str, source: str) -> None:
    masked = mask_comments_and_strings(source)
    expected = {")": "(", "]": "[", "}": "{"}
    stack: list[tuple[str, int]] = []
    line = 1
    for char in masked:
        if char == "\n":
            line += 1
        elif char in "([{":
            stack.append((char, line))
        elif char in ")]}":
            if not stack or stack[-1][0] != expected[char]:
                fail(f"{name}: mismatched {char!r} at line {line}")
            stack.pop()
    if stack:
        fail(f"{name}: unclosed delimiter {stack[-1]}")


def function_names(source: str) -> set[str]:
    masked = mask_comments_and_strings(source)
    pattern = re.compile(
        r"(?m)^(?:bool|void|int|long|ulong|uint|double|string|datetime)\s+"
        r"([A-Za-z_]\w*)\s*\([^;{}]*\)\s*\{"
    )
    return set(pattern.findall(masked))


def extract_function(source: str, function_name: str) -> str:
    masked = mask_comments_and_strings(source)
    pattern = re.compile(
        rf"(?m)^(?:bool|void|int|long|ulong|uint|double|string|datetime)\s+"
        rf"{re.escape(function_name)}\s*\([^;{{}}]*\)\s*\{{"
    )
    match = pattern.search(masked)
    if not match:
        fail(f"missing function {function_name}")
    start = match.start()
    opening = masked.find("{", match.start())
    depth = 0
    for position in range(opening, len(masked)):
        char = masked[position]
        if char == "{":
            depth += 1
        elif char == "}":
            depth -= 1
            if depth == 0:
                return source[start : position + 1]
    fail(f"unterminated function {function_name}")
    return ""


def normalize_core(source: str) -> str:
    replacements = (
        ("FileSourcePosition", "MemorySourcePosition"),
        ("FileSourceById", "MemorySourceById"),
        ("FileSourceExists", "MemorySourceExists"),
        ("LoadFileSnapshot", "LoadMemorySnapshot"),
        ("UpdateFileSnapshotFreshness", "UpdateMemorySnapshotFreshness"),
        ("PrintFileSnapshotReadError", "PrintMemoryReadError"),
        ("WMLFC_", "MLFC_"),
        ("WMLFC:", "MLFC:"),
        ("FLFC_", "MLFC_"),
        ("FLFC:", "MLFC:"),
    )
    normalized = source
    for old, new in replacements:
        normalized = normalized.replace(old, new)
    normalized = mask_comments_and_strings(normalized)
    return re.sub(r"\s+", "", normalized)


def normalize_mt4_core(source: str) -> str:
    replacements = (
        ("M4PositionsTotal", "PositionsTotal"),
        ("M4PositionGetTicket", "PositionGetTicket"),
        ("M4PositionSelectByTicket", "PositionSelectByTicket"),
        ("M4PositionGetInteger", "PositionGetInteger"),
        ("M4PositionGetDouble", "PositionGetDouble"),
        ("M4PositionGetString", "PositionGetString"),
        ("M4PendingOrdersTotal", "OrdersTotal"),
        ("M4PendingOrderGetTicket", "OrderGetTicket"),
        ("M4PendingOrderSelectByTicket", "OrderSelect"),
        ("M4PendingOrderGetInteger", "OrderGetInteger"),
        ("M4PendingOrderGetString", "OrderGetString"),
        ("ENUM_M4_POSITION_TYPE", "ENUM_POSITION_TYPE"),
        ("M4_POSITION_", "POSITION_"),
        ("M4_ORDER_", "ORDER_"),
    )
    normalized = source
    for old, new in replacements:
        normalized = normalized.replace(old, new)
    normalized = mask_comments_and_strings(normalized)
    return re.sub(r"\s+", "", normalized)


def imports(source: str) -> list[str]:
    return re.findall(r'#import\s+"([^"]+)"', source)


def copy_magic(source: str) -> int:
    match = re.search(r"InpCopyMagic\s*=\s*(\d+)", source)
    if not match:
        fail("InpCopyMagic default is missing")
    return int(match.group(1))


def main() -> int:
    sources: dict[str, str] = {}
    functions: dict[str, set[str]] = {}
    for name, path in FILES.items():
        if not path.is_file():
            fail(f"{name}: missing {path.name}")
        sources[name] = path.read_text(encoding="utf-8-sig")
        check_delimiters(name, sources[name])
        functions[name] = function_names(sources[name])
        missing = sorted(set(EVENTS + CORE_FUNCTIONS) - functions[name])
        if missing:
            fail(f"{name}: missing functions: {', '.join(missing)}")
        for event in EVENTS:
            count = len(re.findall(rf"(?m)^\s*\w[\w\s&<>]*\b{event}\s*\(", sources[name]))
            if count != 1:
                fail(f"{name}: expected one {event}, found {count}")

    dll = sources["dll_memory"]
    winapi = sources["winapi_memory"]
    file_snapshot = sources["file_snapshot"]

    if imports(dll) != ["RlfcMemoryBridge.dll"]:
        fail("dll_memory: unexpected imports")
    for token in ("RLFC_Open", "RLFC_Read", "RLFC_Write", "RLMC1"):
        if token not in dll:
            fail(f"dll_memory: missing {token}")
    if "FILE_COMMON" in dll or "kernel32.dll" in dll:
        fail("dll_memory: transport layers are mixed")

    if imports(winapi) != ["kernel32.dll"]:
        fail("winapi_memory: unexpected imports")
    for token in (
        "CreateFileMappingW",
        "MapViewOfFile",
        "CreateMutexW",
        "ReadProcessMemory",
        "WriteProcessMemory",
        "g_winapi_writer_guard_handle",
        "g_winapi_receiver_guard_handle",
        "another Sender already owns this channel",
        "another Receiver already owns this channel/account/magic",
        "WinApiMemoryNameHash",
        "InpSenderExcludeOwnCopies",
        "WINAPI_MEMORY_HEADER_SIZE   64",
        "sizeof(WinApiMemoryHeader) != WINAPI_MEMORY_HEADER_SIZE",
        "RLMC1",
    ):
        if token not in winapi:
            fail(f"winapi_memory: missing {token}")
    for token in ("RlfcMemoryBridge", "RLFC_Open", "FILE_COMMON", "FileOpen", "FileMove"):
        if token in winapi:
            fail(f"winapi_memory: unexpected transport token {token}")

    winapi_open = extract_function(winapi, "WinApiMemoryOpen")
    mapping_index = winapi_open.find("CreateFileMappingW")
    for role in ("writer", "receiver"):
        guard_index = winapi_open.find(f"WinApiMemoryAcquireGuard({role}_guard_name")
        if guard_index < 0 or mapping_index < 0 or guard_index > mapping_index:
            fail(f"winapi_memory: {role} guard must be acquired before opening the mapping")
    mapping_failure = re.search(
        r"if\s*\(g_winapi_mapping_handle\s*==\s*0\)\s*\{([^{}]*)\}",
        winapi_open,
        re.DOTALL,
    )
    if not mapping_failure or "WinApiMemoryClose();" not in mapping_failure.group(1):
        fail("winapi_memory: mapping-open failure must release the role guard")

    winapi_close = extract_function(winapi, "WinApiMemoryClose")
    for token in (
        "ReleaseMutex(g_winapi_writer_guard_handle)",
        "ReleaseMutex(g_winapi_receiver_guard_handle)",
        "CloseHandle(g_winapi_writer_guard_handle)",
        "CloseHandle(g_winapi_receiver_guard_handle)",
    ):
        if token not in winapi_close:
            fail(f"winapi_memory: role guard cleanup missing: {token}")

    for init_name in ("InitMemorySender", "InitMemoryReceiver"):
        init_body = extract_function(winapi, init_name)
        if "if(!EventSetMillisecondTimer" not in init_body or "WinApiMemoryClose();" not in init_body:
            fail(f"winapi_memory: {init_name} must fail closed when the timer cannot start")

    sender_snapshot = extract_function(winapi, "SenderBuildSnapshotText")
    if "InpSenderExcludeOwnCopies" not in sender_snapshot or 'StringFind(position_comment, "WMLFC:")' not in sender_snapshot:
        fail("winapi_memory: Sender must suppress WinAPI copy positions for two-way loop prevention")

    if imports(file_snapshot):
        fail("file_snapshot: DLL import found")
    for token in ("FILE_COMMON", "FileOpen", "FileMove", "RLFC2"):
        if token not in file_snapshot:
            fail(f"file_snapshot: missing {token}")
    for token in ("RlfcMemoryBridge", "kernel32.dll", "CreateFileMappingW"):
        if token in file_snapshot:
            fail(f"file_snapshot: unexpected memory transport token {token}")
    file_trade_event = extract_function(file_snapshot, "OnTradeTransaction")
    if "InpFileRole == FILE_FOLLOW_SENDER" not in file_trade_event:
        fail("file_snapshot: OnTradeTransaction must use the file-role selector")
    for token in ("InpMemoryRole", "MEMORY_FOLLOW_SENDER", "LoadMemorySnapshot"):
        if token in file_trade_event:
            fail(f"file_snapshot: OnTradeTransaction contains memory-role token {token}")

    magics = {name: copy_magic(source) for name, source in sources.items()}
    if len(set(magics.values())) != len(magics):
        fail(f"InpCopyMagic defaults are not isolated: {magics}")

    for function_name in CORE_FUNCTIONS:
        bodies = {
            name: normalize_core(extract_function(source, function_name))
            for name, source in sources.items()
        }
        if len(set(bodies.values())) != 1:
            fail(f"business logic drift in {function_name}")

    if (ROOT / "LossFollowPanel.mq5").exists():
        fail("panel must stay embedded; standalone LossFollowPanel.mq5 found")
    for name, source in sources.items():
        for token in ("InpShowPanel", "OBJ_RECTANGLE_LABEL", "OBJ_BUTTON", "PanelEntriesPaused"):
            if token not in source:
                fail(f"{name}: embedded panel token missing: {token}")
        check_positions = extract_function(source, "CheckPositions")
        close_index = check_positions.find("CheckMinuteProfitClose()")
        pause_index = check_positions.find("if(PanelEntriesPaused())")
        entry_index = check_positions.find("CheckGridActivationEntries()")
        if not (0 <= close_index < pause_index < entry_index):
            fail(f"{name}: pause gate must keep close logic active and precede new entries")
        panel_close_all = extract_function(source, "PanelCloseAllCopies")
        if "StopActiveCopyRounds();" not in panel_close_all:
            fail(f"{name}: panel close-all must stop the active source round before closing")
        if "PanelSetPaused(true);" not in extract_function(source, "PanelDeleteAllPendings"):
            fail(f"{name}: panel delete-all must pause new entries first")
        if "InpStopRoundAfterAllCopiesClosed" not in source:
            fail(f"{name}: round-stop input is missing")
        if "InpCopyDirection = COPY_DIRECTION_BOTH" not in source:
            fail(f"{name}: direction filter must default to buy and sell")
        for token in (
            "ENTRY_TOTAL_FLOATING_LOSS = 3",
            "InpEA1TotalLossMoney",
            "InpEA2TotalLossMoney",
            "profile.total_loss_money",
        ):
            if token not in source:
                fail(f"{name}: total floating loss mode is incomplete: {token}")
        load_profile = extract_function(source, "LoadProfile")
        for token in (
            "profile.total_loss_money = InpEA1TotalLossMoney",
            "profile.total_loss_money = InpEA2TotalLossMoney",
        ):
            if token not in load_profile:
                fail(f"{name}: total-loss profile loading is incomplete: {token}")
        validate_profile = extract_function(source, "ValidateProfile")
        if "profile.entry_mode == ENTRY_TOTAL_FLOATING_LOSS && profile.total_loss_money < 0.0" not in validate_profile:
            fail(f"{name}: negative total-loss thresholds are not rejected")
        process_source = extract_function(source, "ProcessSourceLevel")
        if "IsCopyDirectionAllowed(source.position_type)" not in process_source:
            fail(f"{name}: normal entries do not honor the direction filter")
        if "IsGridGroupStopped(profile.profile_index, source.symbol, source.position_type)" not in process_source:
            fail(f"{name}: non-grid entries do not honor the stopped source round")
        grid_entries = extract_function(source, "CheckGridActivationEntries")
        if "IsCopyDirectionAllowed(position_type)" not in grid_entries:
            fail(f"{name}: grid entries do not honor the direction filter")
        total_entries = extract_function(source, "CheckTotalLossActivationEntries")
        if "ProcessTotalLossGroup(profile, source.symbol)" not in total_entries:
            fail(f"{name}: total-loss groups are not processed")
        total_group = extract_function(source, "ProcessTotalLossGroup")
        for token in (
            "MathMax(0.0, -total_profit_money)",
            "profile.total_loss_money",
            "SetTotalLossGroupActive",
            "CopyTotalLossSources",
        ):
            if token not in total_group:
                fail(f"{name}: total-loss activation is incomplete: {token}")
        total_copy = extract_function(source, "CopyTotalLossSources")
        for token in (
            "IsCopyDirectionAllowed",
            "IsAlreadyCopied",
            "OpenCopyTrade",
            "MarkCopied",
        ):
            if token not in total_copy:
                fail(f"{name}: total-loss copy-all is incomplete: {token}")
        if "grid_initial_max_copies" in total_copy:
            fail(f"{name}: total-loss activation must copy all current source positions")
        direction_filter = extract_function(source, "IsCopyDirectionAllowed")
        for token in ("COPY_DIRECTION_BUY_ONLY", "COPY_DIRECTION_SELL_ONLY", "POSITION_TYPE_BUY", "POSITION_TYPE_SELL"):
            if token not in direction_filter:
                fail(f"{name}: incomplete direction filter: {token}")
        check_positions = extract_function(source, "CheckPositions")
        if check_positions.count("UpdateRoundCopyTracking();") != 2:
            fail(f"{name}: copy-round tracking must run before and after entry processing")
        if "CheckTotalLossActivationEntries();" not in check_positions:
            fail(f"{name}: total-loss activation is not wired into receiver processing")
        if "ResetInactiveTotalLossGroups();" not in check_positions:
            fail(f"{name}: total-loss rounds are not reset")
        reset_groups = extract_function(source, "ResetInactiveGridGroups")
        if "profile.entry_mode == ENTRY_GRID_ACTIVATION" in reset_groups:
            fail(f"{name}: stopped rounds would reset outside grid-activation mode")
        if "PanelDestroy();" not in extract_function(source, "OnDeinit"):
            fail(f"{name}: panel objects are not removed on deinitialization")

    if not MT4_WINAPI.is_file():
        fail(f"mt4_winapi: missing {MT4_WINAPI.name}")
    mt4 = MT4_WINAPI.read_text(encoding="utf-8-sig")
    check_delimiters("mt4_winapi", mt4)
    mt4_functions = function_names(mt4)
    mt4_required = set(EVENTS + CORE_FUNCTIONS) - {"OnTradeTransaction"}
    missing = sorted(mt4_required - mt4_functions)
    if missing:
        fail(f"mt4_winapi: missing functions: {', '.join(missing)}")
    for event in set(EVENTS) - {"OnTradeTransaction"}:
        count = len(re.findall(rf"(?m)^\s*\w[\w\s&<>]*\b{event}\s*\(", mt4))
        if count != 1:
            fail(f"mt4_winapi: expected one {event}, found {count}")

    if imports(mt4) != ["kernel32.dll"]:
        fail("mt4_winapi: unexpected imports")
    for token in (
        "WINAPI_MEMORY_HEADER_SIZE   64",
        "WinApiHeaderPutLong",
        "WinApiHeaderGetLong",
        "GetTickCount64",
        'Local\\\\MQL5_WMLF_MAP_',
        'Local\\\\MQL5_WMLF_MUTEX_',
        "RLMC1",
        "M4PositionsTotal",
        "M4PendingOrdersTotal",
        "M4RefreshTradeCache",
        "M4InvalidateTradeCache",
        "OrderSend(symbol",
        "OrderClose((int)copy_ticket",
        "OrderDelete((int)order_ticket",
        "InpSenderExcludeOwnCopies",
    ):
        if token not in mt4:
            fail(f"mt4_winapi: missing {token}")
    for token in (
        "MqlTradeRequest",
        "MqlTradeResult",
        "OnTradeTransaction",
        "StructToCharArray",
        "CharArrayToStruct",
        "_IsX64",
        "FILE_COMMON",
        "input group",
    ):
        if token in mt4:
            fail(f"mt4_winapi: MQL5-only or mixed transport token found: {token}")

    if copy_magic(mt4) != copy_magic(winapi):
        fail("mt4_winapi: copy magic must match MT5 WinAPI for loop suppression")

    mt4_open = extract_function(mt4, "WinApiMemoryOpen")
    mt4_mapping_index = mt4_open.find("CreateFileMappingW")
    for role in ("writer", "receiver"):
        guard_index = mt4_open.find(f"WinApiMemoryAcquireGuard({role}_guard_name")
        if guard_index < 0 or mt4_mapping_index < 0 or guard_index > mt4_mapping_index:
            fail(f"mt4_winapi: {role} guard must be acquired before opening the mapping")

    mt4_close = extract_function(mt4, "WinApiMemoryClose")
    for token in (
        "ReleaseMutex(g_winapi_writer_guard_handle)",
        "ReleaseMutex(g_winapi_receiver_guard_handle)",
        "CloseHandle(g_winapi_writer_guard_handle)",
        "CloseHandle(g_winapi_receiver_guard_handle)",
    ):
        if token not in mt4_close:
            fail(f"mt4_winapi: role guard cleanup missing: {token}")

    for init_name in ("InitMemorySender", "InitMemoryReceiver"):
        init_body = extract_function(mt4, init_name)
        if "if(!EventSetMillisecondTimer" not in init_body or "WinApiMemoryClose();" not in init_body:
            fail(f"mt4_winapi: {init_name} must fail closed when the timer cannot start")

    header_offsets = {
        "magic": 0,
        "version": 8,
        "sequence": 16,
        "publish_tick_ms": 24,
        "payload_size": 32,
        "payload_crc32": 40,
        "capacity_bytes": 48,
        "reserved": 56,
    }
    mt5_header_match = re.search(r"struct\s+WinApiMemoryHeader\s*\{([^}]*)\}", winapi, re.DOTALL)
    if not mt5_header_match:
        fail("winapi_memory: WinApiMemoryHeader definition missing")
    mt5_header_fields = re.findall(r"\blong\s+(\w+)\s*;", mt5_header_match.group(1))
    if mt5_header_fields != list(header_offsets):
        fail(f"winapi_memory: shared header field order changed: {mt5_header_fields}")
    mt4_write_header = extract_function(mt4, "WinApiWriteHeader")
    mt4_read_header = extract_function(mt4, "WinApiReadHeader")
    for field, offset in header_offsets.items():
        if f"WinApiHeaderPutLong(bytes, {offset}, header.{field})" not in mt4_write_header:
            fail(f"mt4_winapi: header write offset mismatch for {field}")
        if f"header.{field} = WinApiHeaderGetLong(bytes, {offset})" not in mt4_read_header:
            fail(f"mt4_winapi: header read offset mismatch for {field}")

    for function_name in set(CORE_FUNCTIONS) - {"OpenCopyTrade", "SourcePositionProfitMoney"}:
        mt4_body = normalize_mt4_core(extract_function(mt4, function_name))
        mt5_body = normalize_core(extract_function(winapi, function_name))
        if mt4_body != mt5_body:
            fail(f"MT4/MT5 business logic drift in {function_name}")

    mt4_total_money = extract_function(mt4, "SourcePositionProfitMoney")
    for token in ("SYMBOL_TRADE_TICK_SIZE", "SYMBOL_TRADE_TICK_VALUE", "M4_POSITION_TYPE_BUY"):
        if token not in mt4_total_money:
            fail(f"mt4_winapi: total floating loss money calculation missing {token}")

    for function_name in PROTOCOL_SHARED_FUNCTIONS:
        mt4_body = normalize_mt4_core(extract_function(mt4, function_name))
        mt5_body = normalize_core(extract_function(winapi, function_name))
        if mt4_body != mt5_body:
            fail(f"MT4/MT5 protocol drift in {function_name}")

    negative_trigger_checks = (
        "profile.loss_trigger_points < 0.0",
        "profile.loss_trigger_price < 0.0",
        "profile.level2_loss_trigger_points < 0.0",
        "profile.level2_loss_trigger_price < 0.0",
        "profile.level3_loss_trigger_points < 0.0",
        "profile.level3_loss_trigger_price < 0.0",
    )
    forbidden_zero_checks = tuple(check.replace(" < ", " <= ") for check in negative_trigger_checks)
    for name, path in ZERO_TRIGGER_FILES.items():
        source = path.read_text(encoding="utf-8-sig")
        validate_profile = extract_function(source, "ValidateProfile")
        for token in negative_trigger_checks:
            if token not in validate_profile:
                fail(f"{name}: zero loss trigger is not accepted: {token}")
        for token in forbidden_zero_checks:
            if token in validate_profile:
                fail(f"{name}: zero loss trigger is still rejected: {token}")

        loss_trigger = extract_function(source, "IsLossTriggered")
        for token in ("loss_price >= LevelLossPrice", "loss_points >= LevelLossPoints"):
            if token not in loss_trigger:
                fail(f"{name}: immediate market/grid trigger behavior missing: {token}")

        pending = extract_function(source, "PlaceCopyPending")
        zero_index = pending.find("if(trigger_distance == 0.0)")
        price_index = pending.find("double trigger_price")
        if not (0 <= zero_index < price_index):
            fail(f"{name}: zero pending distance must switch to market before price placement")
        for token in (
            "immediate_loss_points",
            "if(!OpenCopyTrade",
            "MarkCopied(source_ticket, level_index);",
        ):
            if token not in pending[zero_index:price_index]:
                fail(f"{name}: zero pending market path missing: {token}")

    print("EA variant validation OK")
    for name in FILES:
        print(
            f"  {name}: functions={len(functions[name])} "
            f"magic={magics[name]} imports={imports(sources[name]) or ['none']}"
        )
    print(
        f"  mt4_winapi: functions={len(mt4_functions)} "
        f"magic={copy_magic(mt4)} imports={imports(mt4)}"
    )
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except AssertionError as error:
        print(f"EA variant validation FAILED: {error}", file=sys.stderr)
        sys.exit(1)
