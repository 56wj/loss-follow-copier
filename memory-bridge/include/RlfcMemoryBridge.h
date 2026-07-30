#pragma once

#include <windows.h>

#ifdef RLFC_MEMORY_BRIDGE_EXPORTS
#define RLFC_API extern "C" __declspec(dllexport)
#else
#define RLFC_API extern "C" __declspec(dllimport)
#endif

// Return codes used by RLFC_Open/RLFC_Read/RLFC_Write.
enum RlfcResult
{
   RLFC_ERROR_ARGUMENT       = -1,
   RLFC_ERROR_SESSION        = -2,
   RLFC_ERROR_CAPACITY       = -3,
   RLFC_ERROR_MAPPING        = -4,
   RLFC_ERROR_MUTEX          = -5,
   RLFC_ERROR_BUFFER_SMALL   = -6,
   RLFC_ERROR_INCONSISTENT   = -7,
   RLFC_ERROR_CHECKSUM       = -8,
   RLFC_ERROR_NO_SLOT        = -9
};

// Opens or creates one Local\\ named-memory channel. Capacity must match in
// both MT5 terminals. Returns a positive session id or a negative RlfcResult.
RLFC_API int __stdcall RLFC_Open(const wchar_t* channel, int capacity_bytes);

// Publishes one complete payload into the inactive slot, then atomically swaps
// the active slot. Returns payload_size or a negative RlfcResult.
RLFC_API int __stdcall RLFC_Write(int session_id,
                                  const unsigned char* payload,
                                  int payload_size);

// Copies only a newly published payload. Returns bytes copied, 0 when the
// session has already consumed the current sequence, or a negative RlfcResult.
RLFC_API int __stdcall RLFC_Read(int session_id,
                                 unsigned char* payload,
                                 int payload_capacity);

RLFC_API int __stdcall RLFC_LastError(int session_id);
RLFC_API void __stdcall RLFC_Close(int session_id);
