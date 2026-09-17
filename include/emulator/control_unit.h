//
// Created by David Dada on 17/09/2026.
//

#ifndef CPU_CONTROL_UNIT_H
#define CPU_CONTROL_UNIT_H
#include "instruction.h"

class ControlUnit {
public:
  explicit ControlUnit() = default;

  void setCurrentExecInstruction(const Instruction &inc) {
    instructionRegister_ = inc;
  }

  void incrementPc() {
    programCounter_++;
  }

  void decrementPc() {
    programCounter_--;
  }

private:
  // or also called instruction pointer, this tracks currently executing function
  int programCounter_{0}; // PC

  // stores the currently executing instruction.
  Instruction instructionRegister_; // IR
};

#endif // CPU_CONTROL_UNIT_H
