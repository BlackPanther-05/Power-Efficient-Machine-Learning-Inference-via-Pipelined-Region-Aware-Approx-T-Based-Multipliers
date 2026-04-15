//Date: 2024/5/29
//Description: Approx-T
//             Pipelined variant for RTL_proposed_2.
//             Stage 1: register normalized inputs and configuration.
//             Stage 2: compute region approximation and local corrections in parallel.
//             Stage 3: register the accumulated result.

module approx_t
#(parameter WIDTH = 8)
(
    input clk,
    input rst_n,
    input valid_in,
    input [WIDTH-2:0] x,
    input [WIDTH-2:0] y,
    input [3:0] Region_Enable,       // One bit per region (00,01,10,11) for power/clock gating
    // 4 bits per region: [1:0] select Level0/1 term, [3:2] select Level2 term
    // Layout: {R3[3:0], R2[3:0], R1[3:0], R0[3:0]}
    input [15:0] Region_Conf_Mask,
    output reg valid_out,
    output reg [2*WIDTH-1:0] f
);
    localparam [WIDTH-1:0] CENTER_LO  = 5  << (WIDTH-3);
    localparam [WIDTH-1:0] CENTER_HI  = 7  << (WIDTH-3);
    localparam [WIDTH-1:0] CENTER_X00 = 9  << (WIDTH-4);
    localparam [WIDTH-1:0] CENTER_X01 = 11 << (WIDTH-4);
    localparam [WIDTH-1:0] CENTER_X10 = 13 << (WIDTH-4);
    localparam [WIDTH-1:0] CENTER_X11 = 15 << (WIDTH-4);

    localparam [2*WIDTH-1:0] CONST_00 = 25 << (WIDTH-5);
    localparam [2*WIDTH-1:0] CONST_01 = 35 << (WIDTH-5);
    localparam [2*WIDTH-1:0] CONST_11 = 49 << (WIDTH-5);

    reg [WIDTH-2:0] x_s1;
    reg [WIDTH-2:0] y_s1;
    reg valid_s1;

    reg [2*WIDTH-1:0] t_f0_f1_s2;
    reg [2*WIDTH-1:0] t_level2_s2;
    reg valid_s2;

    wire [WIDTH-1:0] x_full_s1;
    wire [WIDTH-1:0] y_full_s1;
    assign x_full_s1 = {1'b1, x_s1};
    assign y_full_s1 = {1'b1, y_s1};

    wire [2*WIDTH-1:0] f0_region00;
    wire [2*WIDTH-1:0] f0_region01;
    wire [2*WIDTH-1:0] f0_region10;
    wire [2*WIDTH-1:0] f0_region11;
    wire [2*WIDTH-1:0] delta_f0;

    assign f0_region00 = (x_full_s1 + (x_full_s1 >> 2))
                       + (y_full_s1 + (y_full_s1 >> 2))
                       - CONST_00;

    assign f0_region01 = (x_full_s1 + (x_full_s1 >> 1) + (x_full_s1 >> 2))
                       + (y_full_s1 + (y_full_s1 >> 2))
                       - CONST_01;

    assign f0_region10 = (x_full_s1 + (x_full_s1 >> 2))
                       + (y_full_s1 + (y_full_s1 >> 1) + (y_full_s1 >> 2))
                       - CONST_01;

    assign f0_region11 = (x_full_s1 + (x_full_s1 >> 1) + (x_full_s1 >> 2))
                       + (y_full_s1 + (y_full_s1 >> 1) + (y_full_s1 >> 2))
                       - CONST_11;

    assign delta_f0 = ({x_s1[WIDTH-2], y_s1[WIDTH-2]} == 2'b00) ? f0_region00 :
                      ({x_s1[WIDTH-2], y_s1[WIDTH-2]} == 2'b01) ? f0_region01 :
                      ({x_s1[WIDTH-2], y_s1[WIDTH-2]} == 2'b10) ? f0_region10 :
                                                                  f0_region11;

    wire [WIDTH-1:0] b_l0_center;
    wire [WIDTH-1:0] a_l1_center;
    assign b_l0_center = y_s1[WIDTH-2] ? CENTER_HI : CENTER_LO;
    assign a_l1_center = (x_s1[WIDTH-2:WIDTH-3] == 2'b00) ? CENTER_X00 :
                         (x_s1[WIDTH-2:WIDTH-3] == 2'b01) ? CENTER_X01 :
                         (x_s1[WIDTH-2:WIDTH-3] == 2'b10) ? CENTER_X10 :
                                                            CENTER_X11;

    wire signed [WIDTH:0] y_offset_l0;
    wire signed [WIDTH:0] x_offset_l1;
    assign y_offset_l0 = $signed({1'b0, y_full_s1}) - $signed({1'b0, b_l0_center});
    assign x_offset_l1 = $signed({1'b0, x_full_s1}) - $signed({1'b0, a_l1_center});

    wire signed [WIDTH:0] delta_f1_signed;
    wire signed [WIDTH:0] delta_f2_signed;
    wire [2*WIDTH-1:0] delta_f1;
    wire [2*WIDTH-1:0] delta_f2;

    assign delta_f1_signed = x_s1[WIDTH-3] ? (y_offset_l0 >>> 3) : -(y_offset_l0 >>> 3);
    assign delta_f2_signed = y_s1[WIDTH-3] ? (x_offset_l1 >>> 3) : -(x_offset_l1 >>> 3);

    assign delta_f1 = {{(2*WIDTH-(WIDTH+1)){delta_f1_signed[WIDTH]}}, delta_f1_signed};
    assign delta_f2 = {{(2*WIDTH-(WIDTH+1)){delta_f2_signed[WIDTH]}}, delta_f2_signed};

    wire [1:0] region_sel_comb;
    assign region_sel_comb = {x[WIDTH-2], y[WIDTH-2]};

    wire [3:0] conf_region0 = Region_Conf_Mask[3:0];
    wire [3:0] conf_region1 = Region_Conf_Mask[7:4];
    wire [3:0] conf_region2 = Region_Conf_Mask[11:8];
    wire [3:0] conf_region3 = Region_Conf_Mask[15:12];

    wire [3:0] conf_sel_comb = (region_sel_comb == 2'b00) ? conf_region0 :
                               (region_sel_comb == 2'b01) ? conf_region1 :
                               (region_sel_comb == 2'b10) ? conf_region2 :
                                                           conf_region3;

    wire region_active_comb = Region_Enable[region_sel_comb];

    wire [2*WIDTH-1:0] t_f0_f1_comb_raw;
    wire [2*WIDTH-1:0] t_level2_comb_raw;

    bit_mask_sel #(WIDTH*2) bms0(
        .sel(conf_sel_comb[1:0]),
        .x(delta_f0),
        .y(delta_f1),
        .r(t_f0_f1_comb_raw)
    );

    bit_mask_sel #(WIDTH*2) bms1(
        .sel(conf_sel_comb[3:2]),
        .x(delta_f2),
        .y({WIDTH*2{1'b0}}),
        .r(t_level2_comb_raw)
    );

    wire [2*WIDTH-1:0] t_f0_f1_comb = region_active_comb ? t_f0_f1_comb_raw : {(2*WIDTH){1'b0}};
    wire [2*WIDTH-1:0] t_level2_comb = region_active_comb ? t_level2_comb_raw : {(2*WIDTH){1'b0}};

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            x_s1 <= {(WIDTH-1){1'b0}};
            y_s1 <= {(WIDTH-1){1'b0}};
            valid_s1 <= 1'b0;
            t_f0_f1_s2 <= {(2*WIDTH){1'b0}};
            t_level2_s2 <= {(2*WIDTH){1'b0}};
            valid_s2 <= 1'b0;
            f <= {(2*WIDTH){1'b0}};
            valid_out <= 1'b0;
        end else begin
            x_s1 <= x;
            y_s1 <= y;
            valid_s1 <= valid_in;

            t_f0_f1_s2 <= t_f0_f1_comb;
            t_level2_s2 <= t_level2_comb;
            valid_s2 <= valid_s1;

            f <= t_f0_f1_s2 + t_level2_s2;
            valid_out <= valid_s2;
        end
    end

endmodule
