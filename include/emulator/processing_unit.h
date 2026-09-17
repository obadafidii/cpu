

#ifndef CPU_PROCESSING_UNIT_H
#define CPU_PROCESSING_UNIT_H
#include <array>

#include "alu.h"

// performs computations
class ProcessingUnit {
public:
  constexpr explicit ProcessingUnit(const std::array<int, 32> &registers,
                                    const ArithemeticLogicUnit alu)
      : registers_(registers), alu_(alu) {}

private:
  std::array<int, 32> registers_;
  ArithemeticLogicUnit alu_;
};

#endif // CPU_PROCESSING_UNIT_H
