```
KCPU ISA Specification
========================

Architecture:
    32-bit

Byte order:
    Little endian

Addressing:
    Byte addressable

Registers:
    R0-R15 : u32
    PC      : u32
    SP      : u32
    FLAGS   : u8

Instruction width:
    32 bits

Instruction Formats:

R-type
31       24 23 20 19 16 15 12 11           0
+----------+-----+-----+-----+---------------+
| opcode   | rd  | rs1 | rs2 |    unused     |
+----------+-----+-----+-----+---------------+

I-type
31       24 23 20 19 16 15                 0
+----------+-----+-----+---------------------+
| opcode   | rd  | rs1 | immediate           |
+----------+-----+-----+---------------------+
```

```
ADD rd, rs1, rs2

Semantics:
    R[rd] ← R[rs1] + R[rs2]

Flags:
    Z ← result == 0
    N ← result[31]

PC:
    PC ← PC + 4
```

PS: I don't know what these are fully, I have just a glimpse at how they work. 
Once I dig deeper I might change or expand this, but this is the roadmap gpt gave me.
