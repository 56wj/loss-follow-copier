#!/usr/bin/env python3
"""Static regression checks for the three unified copy-trading variants."""

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
    "ProcessGridGroup",
    "ProcessSourceLevel",
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
        if "PanelSetPaused(true);" not in extract_function(source, "PanelCloseAllCopies"):
            fail(f"{name}: panel close-all must pause new entries first")
        if "PanelSetPaused(true);" not in extract_function(source, "PanelDeleteAllPendings"):
            fail(f"{name}: panel delete-all must pause new entries first")
        if "PanelDestroy();" not in extract_function(source, "OnDeinit"):
            fail(f"{name}: panel objects are not removed on deinitialization")

    print("EA variant validation OK")
    for name in FILES:
        print(
            f"  {name}: functions={len(functions[name])} "
            f"magic={magics[name]} imports={imports(sources[name]) or ['none']}"
        )
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except AssertionError as error:
        print(f"EA variant validation FAILED: {error}", file=sys.stderr)
        sys.exit(1)
