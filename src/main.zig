const std = @import("std");

/// high range, low precision fixed point value between -2.000.000 and +2.000.000, with a precision of roughly 0.001
pub const i32p10 = FixedPoint(32, 1024);

/// medium range, medium precision fixed point value between -32000 and +32000, with a precision of roughly 0.000015
pub const i32p64 = FixedPoint(32, 65536);

/// high precision fixed point with i32 integer range and a precision of roughly 0.00000000025
pub const i64p32 = FixedPoint(64, 1 << 32);

/// Configurable fixed point implementation.
/// - `bits` is the total number of bits in the fixed point value
/// - `scaling` is a
pub fn FixedPoint(comptime bits: comptime_int, comptime scaling: comptime_int) type {
    if (scaling < 1)
        @compileError("scaling must be a positive, non-zero integer!");
    const BaseInt = @Type(.{
        .Int = .{ .bits = bits, .signedness = .signed },
    });
    const BaseIntUnsigned = @Type(.{
        .Int = .{ .bits = bits - 1, .signedness = .unsigned },
    });
    if (scaling > std.math.maxInt(BaseInt))
        @compileError(std.fmt.comptimePrint("scaling must be less than {}", .{std.math.maxInt(BaseInt)}));

    const scaling_bits_max: comptime_int = std.math.log2_int_ceil(BaseIntUnsigned, scaling);

    const significant_digits = std.math.ceil(std.math.log10(@as(comptime_float, scaling)));

    return struct {
        pub const Int = BaseInt;

        pub const Int2 = @Type(.{
            .Int = .{ .bits = 2 * bits, .signedness = .signed },
        });

        pub const IntPart = @Type(.{
            .Int = .{ .bits = bits - scaling_bits_max, .signedness = .signed },
        });

        pub const precision = 2.0 / @as(comptime_float, scaling);

        // comptime {
        //     @compileLog(bits, scaling, precision, Int, Int2, IntPart);
        // }

        const F = @This();

        raw: Int,

        // conversion operators

        pub fn fromFloat(v: f32) F {
            // std.debug.print("fromFloat({}, {d})\n", .{ Int, v });
            return .{ .raw = @floatToInt(Int, scaling * v) };
        }

        pub fn toFloat(v: F, comptime T: type) T {
            // std.debug.print("toFloat({}, {})\n", .{ Int, v.raw });
            _ = @typeInfo(T).Float;
            return @intToFloat(T, v.raw) / scaling;
        }

        pub fn fromInt(i: IntPart) F {
            return .{ .raw = scaling * @as(Int, i) };
        }

        pub fn toInt(f: F) IntPart {
            // std.debug.print("toInt({}, {})\n", .{ Int, f.raw });
            return @intCast(IntPart, @divTrunc(f.raw, scaling));
        }

        // arithmetic operators:

        pub fn add(a: F, b: F) F {
            return .{ .raw = a.raw + b.raw };
        }

        pub fn sub(a: F, b: F) F {
            return .{ .raw = a.raw - b.raw };
        }

        pub fn mul(a: F, b: F) F {
            return .{ .raw = @intCast(Int, scaleDown(@as(Int2, a.raw) * @as(Int2, b.raw))) };
        }

        pub fn div(a: F, b: F) F {
            return .{ .raw = @intCast(Int, @divTrunc(scaleUp(a.raw), b.raw)) };
        }

        pub fn mod(a: F, b: F) F {
            return .{ .raw = @mod(a.raw, b.raw) };
        }

        // relational operators:

        pub fn lessThan(a: F, b: F) bool {
            return a.raw < b.raw;
        }

        pub fn greaterThan(a: F, b: F) bool {
            return a.raw > b.raw;
        }

        pub fn lessOrEqual(a: F, b: F) bool {
            return a.raw <= b.raw;
        }

        pub fn greaterOrEqual(a: F, b: F) bool {
            return a.raw >= b.raw;
        }

        pub fn eql(a: F, b: F) bool {
            return a.raw == b.raw;
        }

        // format api

        pub fn format(f: F, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
            if (comptime (fmt.len == 0 or std.mem.eql(u8, fmt, "any") or std.mem.eql(u8, fmt, "d"))) {
                var copy_options = if (options.precision == null) blk: {
                    var copy = options;
                    copy.precision = significant_digits;
                    break :blk copy;
                } else options;

                try std.fmt.formatFloatDecimal(f.toFloat(f32), copy_options, writer);
            } else if (comptime std.mem.eql(u8, fmt, "x")) {
                try std.fmt.formatFloatHexadecimal(f.toFloat(f32), options, writer);
            } else if (comptime std.mem.eql(u8, fmt, "e")) {
                try std.fmt.formatFloatScientific(f.toFloat(f32), options, writer);
            } else {
                @compileError(comptime std.fmt.comptimePrint("Invalid fmt for FixedPoint({},{}): {{{s}}}", .{ bits, scaling, fmt }));
            }
        }

        // implement guaranteed shift semantics for POT scalings

        const is_pot = std.math.isPowerOfTwo(scaling);
        const precision_bits: comptime_int = if (is_pot)
            std.math.log2_int(u64, scaling)
        else
            @compileError("scaling is not a power a power of two.");
        fn scaleUp(in: Int) Int2 {
            return if (is_pot)
                return @as(Int2, in) << precision_bits
            else
                return @as(Int2, in) * scaling;
        }

        fn scaleDown(in: Int2) Int {
            return if (is_pot)
                @intCast(Int, in >> precision_bits)
            else
                @intCast(Int, @divTrunc(in, scaling));
        }
    };
}

test {
    _ = TestSuite(i32p10);
    _ = TestSuite(i32p64);
    _ = TestSuite(i64p32);
    _ = TestSuite(FixedPoint(32, 1000));
    _ = TestSuite(FixedPoint(64, 1000));
}

fn TestSuite(comptime FP: type) type {
    return struct {
        const float_test_vals = [_]f32{
            0.0,
            1.0,
            std.math.e,
            std.math.pi,
            42.0,
            42.1337,
            21.0,
            13.37,
            100.0,
            -100.0,
            // limit is roughly 100, as we're doing a val*val*2.5 and will get a overflow otherwise for a i32p16
        };
        test "float conversion" {
            for (float_test_vals) |val| {
                const fp = FP.fromFloat(val);
                const f = fp.toFloat(f32);
                try std.testing.expectApproxEqAbs(val, f, FP.precision);
            }
        }

        test "int conversion" {
            const test_vals = [_]FP.IntPart{
                0, 1,  2,  3,  4,  5,  6,  7,  2000,  20_000,  30_000,  std.math.maxInt(i16), std.math.maxInt(FP.IntPart),
                0, -1, -2, -3, -4, -5, -6, -7, -2000, -20_000, -30_000, std.math.minInt(i16), std.math.minInt(FP.IntPart),
            };

            for (test_vals) |val| {
                const fp = FP.fromInt(val);
                const f = fp.toInt();
                try std.testing.expectEqual(val, f);
            }
        }

        test "add arithmetic" {
            for (float_test_vals) |val| {
                const fp = FP.fromFloat(val);
                const f = fp.add(fp).add(FP.fromFloat(10)).toFloat(f32);
                try std.testing.expectApproxEqAbs(2.0 * val + 10, f, FP.precision);
            }
        }

        test "sub arithmetic" {
            for (float_test_vals) |val| {
                const fp = FP.fromFloat(val);
                const f = fp.sub(FP.fromFloat(10)).toFloat(f32);
                try std.testing.expectApproxEqAbs(val - 10, f, FP.precision);
            }
        }

        test "mul arithmetic" {
            for (float_test_vals) |val| {
                const fp = FP.fromFloat(val);
                const f = fp.mul(fp).mul(FP.fromFloat(2.5)).toFloat(f32);
                try std.testing.expectApproxEqRel(val * val * 2.5, f, @sqrt(FP.precision));
            }
        }

        test "div arithmetic" {
            for (float_test_vals) |val| {
                const fp = FP.fromFloat(val);
                const f = fp.div(FP.fromFloat(2.5)).toFloat(f32);
                try std.testing.expectApproxEqRel(val / 2.5, f, @sqrt(FP.precision));
            }
        }

        test "mod arithmetic" {
            const test_vals = [_]f32{
                0.0,
                1.0,
                std.math.e,
                std.math.pi,
            };

            for (test_vals) |val| {
                const fp = FP.fromFloat(val);
                const f = fp.mod(FP.fromFloat(2.5)).toFloat(f32);
                try std.testing.expectApproxEqRel(@mod(val, 2.5), f, @sqrt(FP.precision));
            }
        }
    };
}

test "basic printing" {
    const Meter = FixedPoint(32, 1000); // millimeter precision meter units, using 32 bits

    const position_1 = Meter.fromFloat(10); // 10m
    const position_2 = position_1.add(Meter.fromFloat(0.01)); // add 1cm
    const position_3 = position_2.add(Meter.fromFloat(0.09)); // add 9cm
    const distance = position_3.sub(position_1);

    var buffer: [64]u8 = undefined;

    try std.testing.expectEqualStrings("Distance = 0.100m", try std.fmt.bufPrint(&buffer, "Distance = {}m", .{distance}));
    try std.testing.expectEqualStrings("Distance = 0.10m", try std.fmt.bufPrint(&buffer, "Distance = {d:0.2}m", .{distance}));
    try std.testing.expectEqualStrings("Distance = 0.1m", try std.fmt.bufPrint(&buffer, "Distance = {d:0.1}m", .{distance}));
}
