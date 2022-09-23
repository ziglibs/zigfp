# ZigFP - Fixed Point Arithmetic

```zig
const Meter = zigfp.FixedPoint(32, 1000); // millimeter precision meter units, using 32 bits

const position_1 = Meter.fromFloat(10); // 10m
const position_2 = position_1.add(Meter.fromFloat(0.01)); // add 1cm
const position_3 = position_2.add(Meter.fromFloat(0.09)); // add 9cm
const distance = position_3.sub(position_1);

std.debug.print("Distance = {}\n", .{ distance });
```
