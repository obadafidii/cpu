#ifndef CPU_CPU_H
#define CPU_CPU_H
#include <cstddef>

#include "control_unit.h"
#include "memory.h"
#include "processing_unit.h"

#include <any>

class CPU {
public:
  explicit CPU(const ProcessingUnit &pu, const ControlUnit &cu)
      : processing_unit_(pu), control_unit_(cu) {}

  // CPU operation
  void run() {
    while (!stopped()) {
      const auto data = fetch();
      const Instruction instr = decode(data);
      auto address = evaluateAddress();
      const auto result  = execute(instr);
      store(result);
    }
  }

  char * fetch() const {
    return "allow";
  }

  Instruction decode(char* value) const {
    return Instruction{};
  }

  char* evaluateAddress() const {
    return "0x190u093u90920";
  }

  char* execute(Instruction instruction) {
    return data;
  }

  void store(char* result) {

  }

  // this method tracks the 'halt' signal, i prefer calling it stop
  bool stopped() {
    return false;
  }

private:
  Memory<static_cast<std::size_t>(64 * 1024)> memory_; // 64 bytes memory
  ProcessingUnit processing_unit_;
  ControlUnit control_unit_;
};

#endif
