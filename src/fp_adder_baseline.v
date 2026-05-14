`timescale 1ns / 1ps

module fp_adder_baseline (
    input  wire [31:0] A,
    input  wire [31:0] B,
    output wire [31:0] RESULT
);

// 1. Unpack 
wire signA = A[31];
wire signB = B[31];
wire [7:0] expA = A[30:23];
wire [7:0] expB = B[30:23];
wire [23:0] manA = (expA == 0) ? 24'd0 : {1'b1, A[22:0]};
wire [23:0] manB = (expB == 0) ? 24'd0 : {1'b1, B[22:0]};

// 2. Magnitude Compare (Always toggles)
wire a_gt_b = ({expA, manA} >= {expB, manB});
wire [7:0]  expBig   = a_gt_b ? expA : expB;
wire [7:0]  expSmall = a_gt_b ? expB : expA;
wire [23:0] manBig   = a_gt_b ? manA : manB;
wire [23:0] manSmall = a_gt_b ? manB : manA;
wire        signBig  = a_gt_b ? signA : signB;

// 3. Alignment (Always shifts)
wire [7:0] expDiff = expBig - expSmall;
wire [49:0] align_shifter = {manSmall, 26'd0} >> (expDiff > 26 ? 26 : expDiff);
wire [26:0] manSmall_ext = align_shifter[49:23]; 
wire [26:0] manBig_ext   = {manBig, 3'b000};

// 4. Addition / Subtraction (Always adds)
wire op_sub = (signA ^ signB);
wire [27:0] manSum = op_sub ? (manBig_ext - manSmall_ext) : (manBig_ext + manSmall_ext);

// 5. Normalization (Iterative 'for' loop - Creates a massive delay bottleneck)
reg [27:0] manNorm_reg;
reg [7:0]  expNorm_reg;
integer i;

always @(*) begin
    manNorm_reg = manSum;
    expNorm_reg = expBig;
    
    if (manSum[27]) begin
        manNorm_reg = manSum >> 1;
        expNorm_reg = expBig + 1;
    end else begin
        for (i = 0; i < 27; i = i + 1) begin
            if (manNorm_reg[26] == 0 && manNorm_reg != 0) begin
                manNorm_reg = manNorm_reg << 1;
                expNorm_reg = expNorm_reg - 1;
            end
        end
    end
end

// 6. Rounding
wire round_up = manNorm_reg[2] & (manNorm_reg[1] | manNorm_reg[0] | manNorm_reg[3]);
wire [24:0] manRounded = {1'b0, manNorm_reg[26:3]} + round_up;
wire [7:0]  expFinal = manRounded[24] ? (expNorm_reg + 1) : expNorm_reg;
wire [22:0] fracFinal = manRounded[24] ? manRounded[23:1] : manRounded[22:0];

// 7. Output Pack
assign RESULT = (expFinal == 8'hFF) ? {signBig, 8'hFF, 23'd0} : 
                (expFinal == 0)     ? 32'd0 : 
                                      {signBig, expFinal, fracFinal};

endmodule
