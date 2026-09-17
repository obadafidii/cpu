#ifndef CPU_MEMORY_H
#define CPU_MEMORY_H
#include <array>

template <std::size_t Size> class Memory {
public:
  Memory() = default;

private:
  std::array<uint32_t, Size> space_{};
};

#endif
