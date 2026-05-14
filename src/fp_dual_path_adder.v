`timescale 1ns / 1ps

module fp_dual_path_adder (
    input  wire [31:0] A,
    input  wire [31:0] B,
    output wire [31:0] RESULT
);

// ============================================================================
// 1. UNPACK & EXCEPTION BYPASS
// ============================================================================
wire signA = A[31];
wire signB = B[31];
wire [7:0] expA = A[30:23];
wire [7:0] expB = B[30:23];
wire [22:0] fracA = A[22:0];
wire [22:0] fracB = B[22:0];

wire a_is_zero = (expA == 8'd0);
wire b_is_zero = (expB == 8'd0);
wire early_bypass = a_is_zero | b_is_zero | (expA == 8'd255) | (expB == 8'd255);

wire [31:0] bypass_result = (expA == 8'd255) ? A :
                            (expB == 8'd255) ? B :
                            a_is_zero ? B : A;

// ============================================================================
// 2. MAGNITUDE COMPARE & PATH DECISION
// ============================================================================
wire [23:0] manA_full = { ~a_is_zero, fracA };
wire [23:0] manB_full = { ~b_is_zero, fracB };

wire a_gt_b = ({expA, manA_full} >= {expB, manB_full});
wire [7:0]  expBig   = a_gt_b ? expA : expB;
wire [7:0]  expSmall = a_gt_b ? expB : expA;
wire [23:0] manBig   = a_gt_b ? manA_full : manB_full;
wire [23:0] manSmall = a_gt_b ? manB_full : manA_full;
wire        signBig  = a_gt_b ? signA : signB;
wire        eff_sub  = signA ^ signB;

wire [7:0] expDiff = expBig - expSmall;

// CLOSE PATH: Active ONLY for subtraction where expDiff is 0 or 1
wire is_close_path = eff_sub & (expDiff <= 8'd1) & ~early_bypass;
wire is_far_path   = ~is_close_path & ~early_bypass;

// ============================================================================
// 3. FAR PATH (Power-Gated if Close Path is active)
// ============================================================================
wire [23:0] far_manBig   = is_far_path ? manBig   : 24'd0;
wire [23:0] far_manSmall = is_far_path ? manSmall : 24'd0;

wire [49:0] far_align = {far_manSmall, 26'd0} >> (expDiff > 8'd26 ? 8'd26 : expDiff);
wire [26:0] far_manSmall_ext = {far_align[49:26], far_align[25], far_align[24], |far_align[23:0]};
wire [26:0] far_manBig_ext   = {far_manBig, 3'b000};

wire [27:0] far_sum = eff_sub ? (far_manBig_ext - far_manSmall_ext) 
                              : (far_manBig_ext + far_manSmall_ext);

// Trivial Normalization
wire [26:0] far_norm;
wire [7:0]  far_exp;
assign far_norm = far_sum[27] ? far_sum[27:1] : 
                  far_sum[26] ? far_sum[26:0] : 
                                {far_sum[25:0], 1'b0};
assign far_exp  = far_sum[27] ? (expBig + 1'b1) :
                  far_sum[26] ? expBig : (expBig - 1'b1);

// ============================================================================
// 4. CLOSE PATH (Power-Gated if Far Path is active)
// ============================================================================
wire [23:0] close_manBig   = is_close_path ? manBig   : 24'd0;
wire [23:0] close_manSmall = is_close_path ? manSmall : 24'd0;

wire [24:0] close_manSmall_ext = (expDiff == 8'd1) ? {close_manSmall, 1'b0} >> 1 : {close_manSmall, 1'b0};
wire [24:0] close_manBig_ext   = {close_manBig, 1'b0};

wire [24:0] close_sum = close_manBig_ext - close_manSmall_ext; 

// Massive Parallel LZD
reg [4:0] close_lzd;
always @(*) begin
    if      (close_sum[24]) close_lzd = 5'd0;
    else if (close_sum[23]) close_lzd = 5'd1;
    else if (close_sum[22]) close_lzd = 5'd2;
    else if (close_sum[21]) close_lzd = 5'd3;
    else if (close_sum[20]) close_lzd = 5'd4;
    else if (close_sum[19]) close_lzd = 5'd5;
    else if (close_sum[18]) close_lzd = 5'd6;
    else if (close_sum[17]) close_lzd = 5'd7;
    else if (close_sum[16]) close_lzd = 5'd8;
    else if (close_sum[15]) close_lzd = 5'd9;
    else if (close_sum[14]) close_lzd = 5'd10;
    else if (close_sum[13]) close_lzd = 5'd11;
    else if (close_sum[12]) close_lzd = 5'd12;
    else if (close_sum[11]) close_lzd = 5'd13;
    else if (close_sum[10]) close_lzd = 5'd14;
    else if (close_sum[9])  close_lzd = 5'd15;
    else if (close_sum[8])  close_lzd = 5'd16;
    else if (close_sum[7])  close_lzd = 5'd17;
    else if (close_sum[6])  close_lzd = 5'd18;
    else if (close_sum[5])  close_lzd = 5'd19;
    else if (close_sum[4])  close_lzd = 5'd20;
    else if (close_sum[3])  close_lzd = 5'd21;
    else if (close_sum[2])  close_lzd = 5'd22;
    else if (close_sum[1])  close_lzd = 5'd23;
    else if (close_sum[0])  close_lzd = 5'd24;
    else                    close_lzd = 5'd25;
end

wire [24:0] close_norm = close_sum << close_lzd;
wire [7:0]  close_exp  = expBig - close_lzd;

// ============================================================================
// 5. PATH RECOMBINATION & ROUNDING
// ============================================================================
wire [26:0] final_man = is_far_path ? far_norm : {close_norm, 2'b00};
wire [7:0]  final_exp = is_far_path ? far_exp  : close_exp;

wire norm_G = final_man[2];
wire norm_R = final_man[1];
wire norm_S = final_man[0];
wire round_up = norm_G & (norm_R | norm_S | final_man[3]);

wire [24:0] rounded_man = {1'b0, final_man[26:3]} + round_up;
wire [7:0]  out_exp = rounded_man[24] ? (final_exp + 1'b1) : final_exp;
wire [22:0] out_frac = rounded_man[24] ? rounded_man[23:1] : rounded_man[22:0];

wire [31:0] computed_result = (out_exp == 8'd0) ? 32'd0 : {signBig, out_exp, out_frac};

assign RESULT = early_bypass ? bypass_result : computed_result;

endmodule
