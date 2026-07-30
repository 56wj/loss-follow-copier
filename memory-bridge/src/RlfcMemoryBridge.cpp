#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#ifndef NOMINMAX
#define NOMINMAX
#endif
#define RLFC_MEMORY_BRIDGE_EXPORTS

#include "RlfcMemoryBridge.h"

#include <cstddef>
#include <cstdint>
#include <cstring>
#include <cwchar>
#include <new>

namespace
{
constexpr std::uint32_t kMagic = 0x434D4C52U; // "RLMC" in little endian
constexpr std::uint32_t kVersion = 1;
constexpr int kMinCapacity = 64 * 1024;
constexpr int kMaxCapacity = 16 * 1024 * 1024;
constexpr int kMaxSessions = 64;
constexpr DWORD kWriterWaitMs = 100;

struct alignas(8) SharedHeader
{
   std::uint32_t magic;
   std::uint32_t version;
   std::uint32_t capacity;
   std::uint32_t header_size;
   volatile LONG active_slot;
   std::uint32_t reserved0;
   volatile LONG64 sequence;
   std::uint8_t reserved[32];
};

struct alignas(8) SlotHeader
{
   volatile LONG64 begin_sequence;
   volatile LONG64 end_sequence;
   std::uint32_t payload_size;
   std::uint32_t crc32;
   std::uint64_t publish_tick_ms;
   std::uint8_t reserved[32];
};

static_assert(sizeof(SharedHeader) == 64, "SharedHeader layout changed");
static_assert(sizeof(SlotHeader) == 64, "SlotHeader layout changed");

struct Session
{
   HANDLE mapping = nullptr;
   HANDLE writer_mutex = nullptr;
   std::uint8_t* view = nullptr;
   SharedHeader* header = nullptr;
   std::uint32_t capacity = 0;
   volatile LONG64 last_sequence = 0;
   volatile LONG last_error = 0;
};

SRWLOCK g_sessions_lock = SRWLOCK_INIT;
Session* g_sessions[kMaxSessions] = {};

std::uint64_t Fnv1a64(const wchar_t* value)
{
   constexpr std::uint64_t offset = 14695981039346656037ULL;
   constexpr std::uint64_t prime = 1099511628211ULL;
   std::uint64_t hash = offset;
   for(const wchar_t* p = value; *p != L'\0'; ++p)
   {
      const std::uint16_t code = static_cast<std::uint16_t>(*p);
      hash ^= static_cast<std::uint8_t>(code & 0xffU);
      hash *= prime;
      hash ^= static_cast<std::uint8_t>((code >> 8U) & 0xffU);
      hash *= prime;
   }
   return hash;
}

std::uint32_t Crc32(const unsigned char* data, std::size_t size)
{
   std::uint32_t crc = 0xffffffffU;
   for(std::size_t i = 0; i < size; ++i)
   {
      crc ^= data[i];
      for(int bit = 0; bit < 8; ++bit)
      {
         const std::uint32_t mask = 0U - (crc & 1U);
         crc = (crc >> 1U) ^ (0xedb88320U & mask);
      }
   }
   return ~crc;
}

std::uint64_t MappingSize(std::uint32_t capacity)
{
   return sizeof(SharedHeader) +
          2ULL * (sizeof(SlotHeader) + static_cast<std::uint64_t>(capacity));
}

SlotHeader* SlotAt(Session* session, int index)
{
   const std::size_t stride = sizeof(SlotHeader) + session->capacity;
   return reinterpret_cast<SlotHeader*>(session->view + sizeof(SharedHeader) +
                                        static_cast<std::size_t>(index) * stride);
}

unsigned char* SlotPayload(SlotHeader* slot)
{
   return reinterpret_cast<unsigned char*>(slot) + sizeof(SlotHeader);
}

void SetError(Session* session, int error)
{
   if(session != nullptr)
      InterlockedExchange(&session->last_error, error);
}

void DestroySession(Session* session)
{
   if(session == nullptr)
      return;
   if(session->view != nullptr)
      UnmapViewOfFile(session->view);
   if(session->mapping != nullptr)
      CloseHandle(session->mapping);
   if(session->writer_mutex != nullptr)
      CloseHandle(session->writer_mutex);
   delete session;
}

int RegisterSession(Session* session)
{
   AcquireSRWLockExclusive(&g_sessions_lock);
   int result = RLFC_ERROR_NO_SLOT;
   for(int i = 0; i < kMaxSessions; ++i)
   {
      if(g_sessions[i] == nullptr)
      {
         g_sessions[i] = session;
         result = i + 1;
         break;
      }
   }
   ReleaseSRWLockExclusive(&g_sessions_lock);
   return result;
}

Session* GetSessionLocked(int session_id)
{
   if(session_id <= 0 || session_id > kMaxSessions)
      return nullptr;
   return g_sessions[session_id - 1];
}

bool WaitForWriter(HANDLE mutex)
{
   const DWORD wait = WaitForSingleObject(mutex, kWriterWaitMs);
   return wait == WAIT_OBJECT_0 || wait == WAIT_ABANDONED;
}
} // namespace

int __stdcall RLFC_Open(const wchar_t* channel, int capacity_bytes)
{
   if(channel == nullptr || channel[0] == L'\0')
      return RLFC_ERROR_ARGUMENT;
   if(capacity_bytes < kMinCapacity || capacity_bytes > kMaxCapacity)
      return RLFC_ERROR_CAPACITY;

   const std::uint64_t hash = Fnv1a64(channel);
   wchar_t mapping_name[64] = {};
   wchar_t mutex_name[64] = {};
   swprintf_s(mapping_name,
              _countof(mapping_name),
              L"Local\\RLFC_MAP_%016llX",
              static_cast<unsigned long long>(hash));
   swprintf_s(mutex_name,
              _countof(mutex_name),
              L"Local\\RLFC_MUTEX_%016llX",
              static_cast<unsigned long long>(hash));

   Session* session = new(std::nothrow) Session();
   if(session == nullptr)
      return RLFC_ERROR_MAPPING;

   session->capacity = static_cast<std::uint32_t>(capacity_bytes);
   session->writer_mutex = CreateMutexW(nullptr, FALSE, mutex_name);
   if(session->writer_mutex == nullptr)
   {
      DestroySession(session);
      return RLFC_ERROR_MUTEX;
   }

   const std::uint64_t total_size = MappingSize(session->capacity);
   session->mapping = CreateFileMappingW(INVALID_HANDLE_VALUE,
                                         nullptr,
                                         PAGE_READWRITE,
                                         static_cast<DWORD>(total_size >> 32U),
                                         static_cast<DWORD>(total_size & 0xffffffffULL),
                                         mapping_name);
   if(session->mapping == nullptr)
   {
      DestroySession(session);
      return RLFC_ERROR_MAPPING;
   }

   session->view = static_cast<std::uint8_t*>(
      MapViewOfFile(session->mapping,
                    FILE_MAP_ALL_ACCESS,
                    0,
                    0,
                    static_cast<SIZE_T>(total_size)));
   if(session->view == nullptr)
   {
      DestroySession(session);
      return RLFC_ERROR_MAPPING;
   }
   session->header = reinterpret_cast<SharedHeader*>(session->view);

   if(!WaitForWriter(session->writer_mutex))
   {
      DestroySession(session);
      return RLFC_ERROR_MUTEX;
   }

   bool valid = true;
   if(session->header->magic == 0)
   {
      std::memset(session->view, 0, static_cast<std::size_t>(total_size));
      session->header->version = kVersion;
      session->header->capacity = session->capacity;
      session->header->header_size = sizeof(SharedHeader);
      MemoryBarrier();
      session->header->magic = kMagic;
   }
   else if(session->header->magic != kMagic ||
           session->header->version != kVersion ||
           session->header->capacity != session->capacity ||
           session->header->header_size != sizeof(SharedHeader))
   {
      valid = false;
   }
   ReleaseMutex(session->writer_mutex);

   if(!valid)
   {
      DestroySession(session);
      return RLFC_ERROR_CAPACITY;
   }

   const int session_id = RegisterSession(session);
   if(session_id <= 0)
   {
      DestroySession(session);
      return session_id;
   }
   return session_id;
}

int __stdcall RLFC_Write(int session_id,
                         const unsigned char* payload,
                         int payload_size)
{
   if(payload == nullptr || payload_size <= 0)
      return RLFC_ERROR_ARGUMENT;

   AcquireSRWLockShared(&g_sessions_lock);
   Session* session = GetSessionLocked(session_id);
   if(session == nullptr)
   {
      ReleaseSRWLockShared(&g_sessions_lock);
      return RLFC_ERROR_SESSION;
   }
   if(static_cast<std::uint32_t>(payload_size) > session->capacity)
   {
      SetError(session, RLFC_ERROR_BUFFER_SMALL);
      ReleaseSRWLockShared(&g_sessions_lock);
      return RLFC_ERROR_BUFFER_SMALL;
   }
   if(!WaitForWriter(session->writer_mutex))
   {
      SetError(session, RLFC_ERROR_MUTEX);
      ReleaseSRWLockShared(&g_sessions_lock);
      return RLFC_ERROR_MUTEX;
   }

   const LONG active = InterlockedCompareExchange(&session->header->active_slot, 0, 0);
   const int target = active == 0 ? 1 : 0;
   const LONG64 current = InterlockedCompareExchange64(&session->header->sequence, 0, 0);
   LONG64 next = current + 1;
   if(next <= 0)
      next = 1;

   SlotHeader* slot = SlotAt(session, target);
   InterlockedExchange64(&slot->begin_sequence, -next);
   InterlockedExchange64(&slot->end_sequence, 0);
   slot->payload_size = static_cast<std::uint32_t>(payload_size);
   slot->crc32 = Crc32(payload, static_cast<std::size_t>(payload_size));
   slot->publish_tick_ms = GetTickCount64();
   std::memcpy(SlotPayload(slot), payload, static_cast<std::size_t>(payload_size));
   MemoryBarrier();
   InterlockedExchange64(&slot->end_sequence, next);
   MemoryBarrier();
   InterlockedExchange64(&slot->begin_sequence, next);
   MemoryBarrier();
   InterlockedExchange(&session->header->active_slot, target);
   MemoryBarrier();
   InterlockedExchange64(&session->header->sequence, next);

   ReleaseMutex(session->writer_mutex);
   SetError(session, 0);
   ReleaseSRWLockShared(&g_sessions_lock);
   return payload_size;
}

int __stdcall RLFC_Read(int session_id,
                        unsigned char* payload,
                        int payload_capacity)
{
   if(payload == nullptr || payload_capacity <= 0)
      return RLFC_ERROR_ARGUMENT;

   AcquireSRWLockShared(&g_sessions_lock);
   Session* session = GetSessionLocked(session_id);
   if(session == nullptr)
   {
      ReleaseSRWLockShared(&g_sessions_lock);
      return RLFC_ERROR_SESSION;
   }

   for(int attempt = 0; attempt < 4; ++attempt)
   {
      const LONG64 sequence1 = InterlockedCompareExchange64(&session->header->sequence, 0, 0);
      const LONG64 last = InterlockedCompareExchange64(&session->last_sequence, 0, 0);
      if(sequence1 <= 0 || sequence1 == last)
      {
         SetError(session, 0);
         ReleaseSRWLockShared(&g_sessions_lock);
         return 0;
      }

      const LONG active1 = InterlockedCompareExchange(&session->header->active_slot, 0, 0);
      if(active1 != 0 && active1 != 1)
         continue;
      SlotHeader* slot = SlotAt(session, active1);
      const LONG64 begin1 = InterlockedCompareExchange64(&slot->begin_sequence, 0, 0);
      const LONG64 end1 = InterlockedCompareExchange64(&slot->end_sequence, 0, 0);
      const std::uint32_t size = slot->payload_size;
      const std::uint32_t expected_crc = slot->crc32;

      if(begin1 != sequence1 || end1 != sequence1 || size == 0 || size > session->capacity)
         continue;
      if(size > static_cast<std::uint32_t>(payload_capacity))
      {
         SetError(session, RLFC_ERROR_BUFFER_SMALL);
         ReleaseSRWLockShared(&g_sessions_lock);
         return RLFC_ERROR_BUFFER_SMALL;
      }

      std::memcpy(payload, SlotPayload(slot), size);
      MemoryBarrier();

      const LONG64 sequence2 = InterlockedCompareExchange64(&session->header->sequence, 0, 0);
      const LONG active2 = InterlockedCompareExchange(&session->header->active_slot, 0, 0);
      const LONG64 begin2 = InterlockedCompareExchange64(&slot->begin_sequence, 0, 0);
      const LONG64 end2 = InterlockedCompareExchange64(&slot->end_sequence, 0, 0);
      if(sequence1 != sequence2 || active1 != active2 ||
         begin1 != begin2 || end1 != end2)
         continue;

      if(Crc32(payload, size) != expected_crc)
      {
         SetError(session, RLFC_ERROR_CHECKSUM);
         continue;
      }

      InterlockedExchange64(&session->last_sequence, sequence1);
      SetError(session, 0);
      ReleaseSRWLockShared(&g_sessions_lock);
      return static_cast<int>(size);
   }

   SetError(session, RLFC_ERROR_INCONSISTENT);
   ReleaseSRWLockShared(&g_sessions_lock);
   return RLFC_ERROR_INCONSISTENT;
}

int __stdcall RLFC_LastError(int session_id)
{
   AcquireSRWLockShared(&g_sessions_lock);
   Session* session = GetSessionLocked(session_id);
   const int result = session == nullptr
                         ? RLFC_ERROR_SESSION
                         : static_cast<int>(InterlockedCompareExchange(&session->last_error, 0, 0));
   ReleaseSRWLockShared(&g_sessions_lock);
   return result;
}

void __stdcall RLFC_Close(int session_id)
{
   if(session_id <= 0 || session_id > kMaxSessions)
      return;

   AcquireSRWLockExclusive(&g_sessions_lock);
   Session* session = g_sessions[session_id - 1];
   g_sessions[session_id - 1] = nullptr;
   ReleaseSRWLockExclusive(&g_sessions_lock);
   DestroySession(session);
}

BOOL WINAPI DllMain(HINSTANCE, DWORD, LPVOID)
{
   return TRUE;
}
