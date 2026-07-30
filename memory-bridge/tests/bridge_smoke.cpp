#include "RlfcMemoryBridge.h"

#include <array>
#include <cstdio>
#include <cstring>

int main()
{
   wchar_t channel[96] = {};
   swprintf_s(channel,
              _countof(channel),
              L"rflc_smoke_%lu_%llu",
              static_cast<unsigned long>(GetCurrentProcessId()),
              static_cast<unsigned long long>(GetTickCount64()));

   constexpr int capacity = 64 * 1024;
   // Open the reader first to verify there is no role/load-order dependency.
   const int reader = RLFC_Open(channel, capacity);
   int writer = RLFC_Open(channel, capacity);
   if(writer <= 0 || reader <= 0)
   {
      std::fprintf(stderr, "open failed: writer=%d reader=%d\n", writer, reader);
      return 1;
   }

   const char first[] = "META\tRLMC1\ttest\nEND\t0\n";
   const int written = RLFC_Write(writer,
                                  reinterpret_cast<const unsigned char*>(first),
                                  static_cast<int>(sizeof(first) - 1));
   if(written != static_cast<int>(sizeof(first) - 1))
   {
      std::fprintf(stderr, "write failed: %d\n", written);
      return 2;
   }

   std::array<unsigned char, capacity> buffer{};
   const int read = RLFC_Read(reader, buffer.data(), static_cast<int>(buffer.size()));
   if(read != written || std::memcmp(buffer.data(), first, static_cast<std::size_t>(written)) != 0)
   {
      std::fprintf(stderr, "read mismatch: read=%d written=%d\n", read, written);
      return 3;
   }

   if(RLFC_Read(reader, buffer.data(), static_cast<int>(buffer.size())) != 0)
   {
      std::fprintf(stderr, "duplicate sequence was returned\n");
      return 4;
   }

   const char second[] = "META\tRLMC1\ttest\tsecond\nEND\t0\n";
   if(RLFC_Write(writer,
                 reinterpret_cast<const unsigned char*>(second),
                 static_cast<int>(sizeof(second) - 1)) <= 0)
      return 5;

   std::array<unsigned char, 8> small_buffer{};
   if(RLFC_Read(reader,
                small_buffer.data(),
                static_cast<int>(small_buffer.size())) != RLFC_ERROR_BUFFER_SMALL ||
      RLFC_LastError(reader) != RLFC_ERROR_BUFFER_SMALL)
   {
      std::fprintf(stderr, "small-buffer guard failed\n");
      return 6;
   }

   const int second_read = RLFC_Read(reader, buffer.data(), static_cast<int>(buffer.size()));
   if(second_read != static_cast<int>(sizeof(second) - 1) ||
      std::memcmp(buffer.data(), second, sizeof(second) - 1) != 0)
      return 7;

   // Keep the reader alive, restart the writer and verify the named mapping
   // plus sequence state continue to work.
   RLFC_Close(writer);
   writer = RLFC_Open(channel, capacity);
   if(writer <= 0)
      return 8;

   const char third[] = "META\tRLMC1\ttest\trestarted\nEND\t0\n";
   if(RLFC_Write(writer,
                 reinterpret_cast<const unsigned char*>(third),
                 static_cast<int>(sizeof(third) - 1)) <= 0)
      return 9;
   const int third_read = RLFC_Read(reader, buffer.data(), static_cast<int>(buffer.size()));
   if(third_read != static_cast<int>(sizeof(third) - 1) ||
      std::memcmp(buffer.data(), third, sizeof(third) - 1) != 0)
      return 10;

   // A different capacity on the same channel must be rejected.
   const int mismatch = RLFC_Open(channel, capacity * 2);
   if(mismatch > 0)
   {
      RLFC_Close(mismatch);
      std::fprintf(stderr, "capacity mismatch was accepted\n");
      return 11;
   }

   RLFC_Close(reader);
   RLFC_Close(writer);
   std::puts("RlfcMemoryBridgeSmoke OK");
   return 0;
}
