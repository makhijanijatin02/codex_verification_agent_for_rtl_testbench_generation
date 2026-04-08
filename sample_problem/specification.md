# 4-bit Up Counter with Enable and Synchronous Reset

## Module Name
`counter_4bit`

## Description
Design a 4-bit up counter with synchronous active-high reset and an enable signal.

## Ports
- `clk` (input, 1-bit): Clock signal, positive edge triggered
- `reset` (input, 1-bit): Synchronous active-high reset. When asserted on the rising edge of clk, the counter resets to 0.
- `enable` (input, 1-bit): When high, the counter increments by 1 on each rising clock edge. When low, the counter holds its value.
- `count` (output, 4-bit, registered): The current counter value.

## Behavior
- On the rising edge of `clk`:
  - If `reset` is high, `count` becomes 0, regardless of `enable`.
  - Else if `enable` is high, `count` increments by 1.
  - Else `count` holds its current value.
- The counter wraps around from 15 (4'b1111) to 0 (4'b0000) when it overflows.
- `reset` has higher priority than `enable`.
