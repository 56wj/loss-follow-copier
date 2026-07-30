# MT5 shared-memory bridge

`RlfcMemoryBridge.dll` lets two 64-bit MT5 terminal processes on the same
Windows login exchange complete copy-trading snapshots through a named shared
memory mapping.

## Design

- One `Local\\RLFC_MAP_<channel-hash>` mapping per channel.
- Two payload slots. The writer fills the inactive slot and atomically swaps it.
- Sequence guards plus CRC32 reject torn or inconsistent reads.
- A named writer mutex serializes accidental multiple senders.
- Readers receive only a new sequence and otherwise reuse the last valid MQL5
  snapshot while still checking prices on every tick.

## Build

Open x64 Native Tools PowerShell for Visual Studio 2022:

```powershell
cd memory-bridge
.\build.ps1
```

Output: `memory-bridge\dist\RlfcMemoryBridge.dll`.

## Install

1. Copy the same DLL to each terminal's `MQL5\Libraries` directory.
2. Copy and compile `MemoryLossFollow.mq5` in both terminals.
3. Enable **Allow DLL imports** for both EA instances.
4. Select `MEMORY_FOLLOW_RECEIVER` in the copy terminal and
   `MEMORY_FOLLOW_SENDER` in the source terminal.
5. Keep `InpChannelName` and `InpSharedMemoryCapacityKB` identical.
6. Sender and Receiver can be loaded in either order. The first side creates
   and initializes the named mapping; the other side opens the same mapping.

The mapping is page-file backed. It disappears automatically after all terminal
processes close their handles; no disk snapshot is created.

## Rollback

Remove both memory EAs from their charts, close the two terminals, and delete
`RlfcMemoryBridge.dll` from `MQL5\Libraries`. The named mapping and mutex then
disappear with the final process handle.
