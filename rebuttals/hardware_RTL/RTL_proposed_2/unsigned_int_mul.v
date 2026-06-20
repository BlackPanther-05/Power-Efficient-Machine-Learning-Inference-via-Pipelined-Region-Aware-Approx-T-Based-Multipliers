//Date: 2024/5/29
//Description: unsigned integer multiplication
//Note:        Pipelined RTL_proposed_2 variant.
//             The datapath is partitioned into normalization, Approx-T core,
//             and final scaling/output stages to support a 1 GHz testbench.

module unsigned_int_mul
#(parameter WIDTH = 8)
(
    input clk,
    input rst_n,
    input valid_in,
    input [WIDTH-1:0] A,
    input [WIDTH-1:0] B,
    input [3:0] Region_Enable,
    input [15:0] Region_Conf_Mask,
    output valid_out,
    output [2*WIDTH-1:0] R
);
    function [2*WIDTH-1:0] scale_result;
        input [2*WIDTH-1:0] f_in;
        input [$clog2(WIDTH):0] ab_pos_in;
        input non_zero_in;
        begin
            if (!non_zero_in) begin
                scale_result = {(2*WIDTH){1'b0}};
            end else if (ab_pos_in[$clog2(WIDTH)]) begin
                scale_result = ({f_in, 1'b0} << ab_pos_in[$clog2(WIDTH)-1:0]);
            end else begin
                scale_result = (f_in >> ~ab_pos_in[$clog2(WIDTH)-1:0]);
            end
        end
    endfunction

    wire [$clog2(WIDTH)-1:0] a_ho_pos;
    wire [$clog2(WIDTH)-1:0] b_ho_pos;
    wire [$clog2(WIDTH):0] ab_ho_pos_comb;
    wire [WIDTH-2:0] w_A_comb;
    wire [WIDTH-2:0] w_B_comb;
    wire non_zero_comb;

    leading_one_detector #(WIDTH) lod_a(.num(A), .position(a_ho_pos));
    leading_one_detector #(WIDTH) lod_b(.num(B), .position(b_ho_pos));

    assign ab_ho_pos_comb = a_ho_pos + b_ho_pos;
    assign w_A_comb = A << ~a_ho_pos;
    assign w_B_comb = B << ~b_ho_pos;
    assign non_zero_comb = (|A) & (|B);

    reg [$clog2(WIDTH):0] ab_pos_pipe0;
    reg [$clog2(WIDTH):0] ab_pos_pipe1;
    reg [$clog2(WIDTH):0] ab_pos_pipe2;
    reg non_zero_pipe0;
    reg non_zero_pipe1;
    reg non_zero_pipe2;

    wire approx_valid_out;
    wire [2*WIDTH-1:0] approx_f;

    approx_t #(WIDTH) m_approx_t(
        .clk(clk),
        .rst_n(rst_n),
        .valid_in(valid_in),
        .x(w_A_comb),
        .y(w_B_comb),
        .Region_Enable(Region_Enable),
        .Region_Conf_Mask(Region_Conf_Mask),
        .valid_out(approx_valid_out),
        .f(approx_f)
    );

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ab_pos_pipe0 <= {($clog2(WIDTH)+1){1'b0}};
            ab_pos_pipe1 <= {($clog2(WIDTH)+1){1'b0}};
            ab_pos_pipe2 <= {($clog2(WIDTH)+1){1'b0}};
            non_zero_pipe0 <= 1'b0;
            non_zero_pipe1 <= 1'b0;
            non_zero_pipe2 <= 1'b0;
        end else begin
            ab_pos_pipe0 <= ab_ho_pos_comb;
            ab_pos_pipe1 <= ab_pos_pipe0;
            ab_pos_pipe2 <= ab_pos_pipe1;

            non_zero_pipe0 <= non_zero_comb;
            non_zero_pipe1 <= non_zero_pipe0;
            non_zero_pipe2 <= non_zero_pipe1;
        end
    end

    assign R = scale_result(approx_f, ab_pos_pipe2, non_zero_pipe2);
    assign valid_out = approx_valid_out;

endmodule
