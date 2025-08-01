`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 27.06.2025 12:17:46
// Design Name: 
// Module Name: MIPS32_tb
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


module MIPS32_tb();
reg clk1, clk2, reset;
    integer i;

    // Instantiate the processor
    MIPS32 uut (
        .clk1(clk1),
        .clk2(clk2),
        .reset(reset)
    );

    // Clock generation
    initial begin
        clk1 = 0; clk2 = 0;
        forever begin
            #5 clk1 = ~clk1;
            #5 clk2 = ~clk2;
        end
    end

    // Instruction encoding helper macros
    function [31:0] R_TYPE;
        input [5:0] opcode;
        input [4:0] rs, rt, rd;
        R_TYPE = {opcode, rs, rt, rd, 5'b00000, 6'b000000};
    endfunction

    function [31:0] I_TYPE;
        input [5:0] opcode;
        input [4:0] rs, rt;
        input [15:0] imm;
        I_TYPE = {opcode, rs, rt, imm};
    endfunction

    function [31:0] J_TYPE;
        input [5:0] opcode;
        input [25:0] address;
        J_TYPE = {opcode, address};
    endfunction

    // Simulation sequence
    initial begin
        reset = 1;

        // Clear memory and registers
        for (i = 0; i < 32; i = i + 1) begin
            uut.Regbank[i] = 0;
        end
        for (i = 0; i < 1024; i = i + 1) begin
            uut.InstrMem[i] = 32'h0;
            uut.DataMem[i] = 32'h0;
        end

        // Wait a little and deassert reset
        #10 reset = 0;

        // -------------------------
        // Sample Program:
        // -------------------------
        // Regbank[2] = 100
        // DataMem[100] = 55
        // LW R1, 0(R2)
        // ADD R3, R1, R4
        // ADD R5, R3, R6
        // SUB R7, R5, R1
        // BEQZ R7, +2
        // SW R3, 4(R2)
        // JAL to 0x20
        // HLT

        uut.Regbank[2] = 100;     // Base for LW/SW
        uut.Regbank[4] = 10;      // R4
        uut.Regbank[6] = 20;      // R6
        uut.DataMem[100] = 55;    // Data to load

        uut.InstrMem[0] = I_TYPE(6'b001000, 5'd2, 5'd1, 16'd0);     // LW R1, 0(R2)
        uut.InstrMem[1] = R_TYPE(6'b000000, 5'd1, 5'd4, 5'd3);      // ADD R3, R1, R4
        uut.InstrMem[2] = R_TYPE(6'b000000, 5'd3, 5'd6, 5'd5);      // ADD R5, R3, R6
        uut.InstrMem[3] = R_TYPE(6'b000001, 5'd5, 5'd1, 5'd7);      // SUB R7, R5, R1
        uut.InstrMem[4] = I_TYPE(6'b001110, 5'd7, 5'd0, 16'd2);     // BEQZ R7, +2
        uut.InstrMem[5] = I_TYPE(6'b001001, 5'd2, 5'd3, 16'd4);     // SW R3, 4(R2)
        uut.InstrMem[6] = J_TYPE(6'b010000, 26'd8);                 // JAL to address 8 (word-aligned = 32)
        uut.InstrMem[7] = {6'b111111, 26'd0};                       // HLT

        // Set instruction at address 32 for JAL target
        uut.InstrMem[8] = R_TYPE(6'b000000, 5'd0, 5'd0, 5'd10);     // ADD R10, R0, R0 (NOP)

        // Run simulation for enough time
        #500;

        // Display final register values
        $display("Final Register State:");
        for (i = 0; i < 32; i = i + 1)
            $display("R[%0d] = %0d", i, uut.Regbank[i]);

        $finish;
    end

endmodule
