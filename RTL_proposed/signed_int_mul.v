//Date: 2024/5/29
//Description: signed integer multiplication
//Note:        1. This module performs SIGNED INTEGER MULTIPLICATION.

module signed_int_mul
#(parameter WIDTH=8) //Default WIDTH = 8
(
    input signed [WIDTH-1:0]A,
    input signed [WIDTH-1:0]B,
    
    input [WIDTH-3:0]Conf_Bit_Mask,  //Support for configurable procision
    
    output signed [2*WIDTH-1:0]R
 );
    wire  sign_R;
    assign sign_R = A[WIDTH-1] ^ B[WIDTH-1];
    
    wire [WIDTH-1:0]mag_A, mag_B;
    
    assign mag_A = A[WIDTH-1]? (~A[WIDTH-1:0]+1'b1) : A[WIDTH-2:0];
    assign mag_B = B[WIDTH-1]? (~B[WIDTH-1:0]+1'b1) : B[WIDTH-2:0];
    
    wire [WIDTH*2-1:0] mag_R;
    unsigned_int_mul m_unsigned_int_mul(.A(mag_A),.B(mag_B),.Conf_Bit_Mask(Conf_Bit_Mask),.R(mag_R));
    //assign mag_R = {1'b0,mag_A} * {1'b0,mag_B};  //for test
    
    assign R = (sign_R) ? (~mag_R + 1'b1) : mag_R;
    
endmodule
