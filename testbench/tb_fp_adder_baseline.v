`timescale 1ns / 1ps

module tb_fp_adder_baseline;

reg  [31:0] A, B;
wire [31:0] RESULT;

// Choose which DUT to test
// Uncomment ONE at a time

fp_adder_baseline uut (.A(A), .B(B), .RESULT(RESULT));
//fp_dual_path_adder uut (.A(A), .B(B), .RESULT(RESULT));

integer i;

initial begin
    // =========================
    // VCD DUMP (IMPORTANT)
    // =========================
    $dumpfile("activity_profile.vcd");
    $dumpvars(0, tb_fp_adder_baseline);

    // =========================
    // RANDOM TESTING LOOP
    // =========================
    for (i = 0; i < 1000; i = i + 1) begin
        A = $random;
        B = $random;
        #10;
    end

    // =========================
    // EDGE CASES (IMPORTANT)
    // =========================
    A = 32'h00000000; B = 32'h3F800000; #10; // 0 + 1
    A = 32'h3F800000; B = 32'h00000000; #10; // 1 + 0
    A = 32'h7F800000; B = 32'h3F800000; #10; // Inf
    A = 32'h3F800000; B = 32'hBF800000; #10; // 1 + (-1)

    $finish;
end

endmodule
