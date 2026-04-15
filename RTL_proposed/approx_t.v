//Date: 2024/5/29
//Description: Approx-T
//             This variant uses four equal Level-0 subregions over [1,2) x [1,2)
//             and then applies two additional region-local compensation levels.

module approx_t
#(parameter WIDTH=8)
(
    input [WIDTH-2:0]x,
    input [WIDTH-2:0]y,

    input [WIDTH-3:0]Conf_Bit_Mask,  //Support for configurable procision

    output [2*WIDTH-1:0]f
);
    localparam integer SCALE_SHIFT = WIDTH - 1;

    // Q1.(WIDTH-1) representations of the normalized inputs in [1, 2).
    wire [WIDTH-1:0] x_full;
    wire [WIDTH-1:0] y_full;
    assign x_full = {1'b1, x};
    assign y_full = {1'b1, y};

    // Region centers:
    // coarse centers  = {1.25, 1.75}  = {5/4, 7/4}
    // refined x centers = {1.125, 1.375, 1.625, 1.875} = {9/8, 11/8, 13/8, 15/8}
    localparam [WIDTH-1:0] CENTER_LO   = 5  << (WIDTH-3);
    localparam [WIDTH-1:0] CENTER_HI   = 7  << (WIDTH-3);
    localparam [WIDTH-1:0] CENTER_X00  = 9  << (WIDTH-4);
    localparam [WIDTH-1:0] CENTER_X01  = 11 << (WIDTH-4);
    localparam [WIDTH-1:0] CENTER_X10  = 13 << (WIDTH-4);
    localparam [WIDTH-1:0] CENTER_X11  = 15 << (WIDTH-4);

    // Constants for ay + bx - ab in the same Q1.(WIDTH-1) scale.
    localparam [2*WIDTH-1:0] CONST_00  = 25 << (WIDTH-5);  // 25/16
    localparam [2*WIDTH-1:0] CONST_01  = 35 << (WIDTH-5);  // 35/16
    localparam [2*WIDTH-1:0] CONST_11  = 49 << (WIDTH-5);  // 49/16

    //=====LEVEL 0: FOUR-REGION PIECEWISE FIRST-ORDER TAYLOR APPROXIMATION=====
    // For each region we use f(x, y) ~= b*x + a*y - a*b at the region center (a, b).
    wire [2*WIDTH-1:0] delta_f0;
    wire [2*WIDTH-1:0] f0_region00, f0_region01, f0_region10, f0_region11;

    // Region 00: center (1.25, 1.25)
    assign f0_region00 = (x_full + (x_full >> 2))
                       + (y_full + (y_full >> 2))
                       - CONST_00;

    // Region 01: center (1.25, 1.75)
    assign f0_region01 = (x_full + (x_full >> 1) + (x_full >> 2))
                       + (y_full + (y_full >> 2))
                       - CONST_01;

    // Region 10: center (1.75, 1.25)
    assign f0_region10 = (x_full + (x_full >> 2))
                       + (y_full + (y_full >> 1) + (y_full >> 2))
                       - CONST_01;

    // Region 11: center (1.75, 1.75)
    assign f0_region11 = (x_full + (x_full >> 1) + (x_full >> 2))
                       + (y_full + (y_full >> 1) + (y_full >> 2))
                       - CONST_11;

    assign delta_f0 = ({x[WIDTH-2], y[WIDTH-2]} == 2'b00) ? f0_region00 :
                      ({x[WIDTH-2], y[WIDTH-2]} == 2'b01) ? f0_region01 :
                      ({x[WIDTH-2], y[WIDTH-2]} == 2'b10) ? f0_region10 :
                                                            f0_region11;

    //=====LEVEL 1-2: REGION-LOCAL RECURSIVE PARTITIONING=====
    // Starting from each coarse Level-0 region:
    // Level 1 splits along x, so Delta_f1 depends on (y - b0).
    // Level 2 splits along y inside the selected Level-1 x-subregion, so Delta_f2 depends on (x - a1).
    wire [WIDTH-1:0] b_l0_center;
    wire [WIDTH-1:0] a_l1_center;

    assign b_l0_center = y[WIDTH-2] ? CENTER_HI : CENTER_LO;
    assign a_l1_center = (x[WIDTH-2:WIDTH-3] == 2'b00) ? CENTER_X00 :
                         (x[WIDTH-2:WIDTH-3] == 2'b01) ? CENTER_X01 :
                         (x[WIDTH-2:WIDTH-3] == 2'b10) ? CENTER_X10 :
                                                          CENTER_X11;

    wire signed [WIDTH:0] y_offset_l0;
    wire signed [WIDTH:0] x_offset_l1;
    assign y_offset_l0 = $signed({1'b0, y_full}) - $signed({1'b0, b_l0_center});
    assign x_offset_l1 = $signed({1'b0, x_full}) - $signed({1'b0, a_l1_center});

    ////delta_f(1)////
    // Local Level-1 correction: +/- (y - b0) / 8, sign selected by the x split.
    wire signed [WIDTH:0] delta_f1_signed;
    wire [2*WIDTH-1:0] delta_f1;
    assign delta_f1_signed = x[WIDTH-3] ? (y_offset_l0 >>> 3) : -(y_offset_l0 >>> 3);
    assign delta_f1 = {{(2*WIDTH-(WIDTH+1)){delta_f1_signed[WIDTH]}}, delta_f1_signed};

    ////delta_f(2)////
    // Local Level-2 correction: +/- (x - a1) / 8, sign selected by the y split.
    wire signed [WIDTH:0] delta_f2_signed;
    wire [2*WIDTH-1:0] delta_f2;
    assign delta_f2_signed = y[WIDTH-3] ? (x_offset_l1 >>> 3) : -(x_offset_l1 >>> 3);
    assign delta_f2 = {{(2*WIDTH-(WIDTH+1)){delta_f2_signed[WIDTH]}}, delta_f2_signed};

    // Sigma delta_f(n) based on input Conf_Bit_Mask.
    wire [2*WIDTH-1:0] t_f0_f1, t_level2;

    bit_mask_sel #(WIDTH*2) bms0(.sel(Conf_Bit_Mask[1:0]), .x(delta_f0), .y(delta_f1), .r(t_f0_f1));
    bit_mask_sel #(WIDTH*2) bms1(.sel(Conf_Bit_Mask[3:2]), .x(delta_f2), .y({WIDTH*2{1'b0}}), .r(t_level2));

    assign f = t_f0_f1 + t_level2;

endmodule
