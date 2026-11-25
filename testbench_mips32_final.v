`timescale 1ns / 1ps

// Optional directed, self-checking testbench for the forwarding RTL.
module MIPS32_forwarding_tb;
    reg clk1, clk2, reset;
    integer i;
    mips32_pipeline uut (.clk1(clk1), .clk2(clk2), .reset(reset));

    initial begin
        clk1 = 0; clk2 = 0;
        forever begin
            #5 clk1 = ~clk1;
            #5 clk2 = ~clk2;
        end
    end

    function [31:0] R_TYPE;
        input [5:0] op;
        input [4:0] rs, rt, rd;
        R_TYPE = {op, rs, rt, rd, 11'b0};
    endfunction
    function [31:0] I_TYPE;
        input [5:0] op;
        input [4:0] rs, rt;
        input [15:0] imm;
        I_TYPE = {op, rs, rt, imm};
    endfunction
    function [31:0] J_TYPE;
        input [5:0] op;
        input [25:0] addr;
        J_TYPE = {op, addr};
    endfunction

    task check_reg;
        input integer r;
        input [31:0] expected;
        begin
            if (uut.Regbank[r] !== expected) begin
                $display("FAIL R%0d: got %h expected %h", r, uut.Regbank[r], expected);
                $finish;
            end
        end
    endtask

    initial begin
        reset = 1;
        for (i = 0; i < 32; i = i + 1) uut.Regbank[i] = 0;
        for (i = 0; i < 1024; i = i + 1) begin
            uut.InstrMem[i] = 0;
            uut.DataMem[i] = 0;
        end
        uut.Regbank[2] = 100;
        uut.Regbank[4] = 10;
        uut.DataMem[25] = 55;

        uut.InstrMem[0]  = I_TYPE(6'b001000, 5'd2, 5'd1, 16'd0); // LW R1,0(R2)
        uut.InstrMem[1]  = R_TYPE(6'b000000, 5'd1, 5'd4, 5'd3); // ADD R3,R1,R4
        uut.InstrMem[2]  = R_TYPE(6'b000000, 5'd3, 5'd3, 5'd5); // ADD R5,R3,R3
        uut.InstrMem[3]  = I_TYPE(6'b001001, 5'd2, 5'd5, 16'd4); // SW R5,4(R2)
        uut.InstrMem[4]  = I_TYPE(6'b001000, 5'd2, 5'd6, 16'd4); // LW R6,4(R2)
        uut.InstrMem[5]  = R_TYPE(6'b000001, 5'd6, 5'd5, 5'd7); // SUB R7,R6,R5
        uut.InstrMem[6]  = I_TYPE(6'b001110, 5'd7, 5'd0, 16'd2); // BEQZ R7,+2 -> index 9
        uut.InstrMem[7]  = J_TYPE(6'b001111, 26'd20); // Wrong-path J: must be killed
        uut.InstrMem[8]  = I_TYPE(6'b001001, 5'd2, 5'd3, 16'd8); // Skipped store
        uut.InstrMem[9]  = I_TYPE(6'b001010, 5'd0, 5'd8, 16'd9); // ADDI R8,R0,9
        uut.InstrMem[10] = I_TYPE(6'b001010, 5'd8, 5'd8, 16'd1); // ADDI R8,R8,1
        uut.InstrMem[11] = R_TYPE(6'b000000, 5'd8, 5'd8, 5'd9); // ADD R9,R8,R8
        uut.InstrMem[12] = J_TYPE(6'b010000, 26'd15); // JAL -> index 15, link=52
        uut.InstrMem[13] = I_TYPE(6'b001001, 5'd2, 5'd9, 16'd8); // Wrong-path store
        uut.InstrMem[14] = {6'b111111,26'd0}; // Skipped HLT
        uut.InstrMem[15] = R_TYPE(6'b000000, 5'd31, 5'd0, 5'd10); // ADD R10,R31,R0
        uut.InstrMem[16] = I_TYPE(6'b001010, 5'd0, 5'd11, 16'hFFFF); // ADDI R11,R0,-1
        uut.InstrMem[17] = I_TYPE(6'b001010, 5'd0, 5'd12, 16'd1); // ADDI R12,R0,1
        uut.InstrMem[18] = R_TYPE(6'b000100, 5'd11, 5'd12, 5'd13); // SLT R13,R11,R12 -> 1
        uut.InstrMem[19] = R_TYPE(6'b000100, 5'd12, 5'd11, 5'd14); // SLT R14,R12,R11 -> 0
        uut.InstrMem[20] = I_TYPE(6'b001100, 5'd11, 5'd15, 16'd1); // SLTI R15,R11,1 -> 1
        uut.InstrMem[21] = I_TYPE(6'b001100, 5'd12, 5'd16, 16'hFFFF); // SLTI R16,R12,-1 -> 0
        uut.InstrMem[22] = I_TYPE(6'b001100, 5'd11, 5'd17, 16'hFFFF); // SLTI R17,R11,-1 -> 0
        uut.InstrMem[23] = {6'b111111,26'd0}; // Actual HLT
        uut.InstrMem[24] = I_TYPE(6'b001001, 5'd2, 5'd9, 16'd8); // Must not commit after HLT

        #12 reset = 0; // Avoid racing either positive clock edge.
        #1000;
        check_reg(0, 0);
        check_reg(1, 55);
        check_reg(3, 65);
        check_reg(5, 130);
        check_reg(6, 130);
        check_reg(7, 0);
        check_reg(8, 10);
        check_reg(9, 20);
        check_reg(10, 52);
        check_reg(31, 52);
        check_reg(11, 32'hFFFFFFFF);
        check_reg(12, 1);
        check_reg(13, 1);
        check_reg(14, 0);
        check_reg(15, 1);
        check_reg(16, 0);
        check_reg(17, 0);
        if (uut.DataMem[26] !== 32'd130 || uut.DataMem[27] !== 32'd0 || uut.HALTED !== 1'b1) begin
            $display("FAIL: memory or halt state");
            $finish;
        end
        $display("PASS: forwarding, branch flush, JAL, halt, byte addressing and signed comparison checks");
        $finish;
    end
endmodule
