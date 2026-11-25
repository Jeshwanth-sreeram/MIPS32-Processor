`timescale 1ns / 1ps

module mips32_pipeline(
    input clk1, clk2, reset
);

    // Pipeline registers and state
    reg [31:0] PC, IF_ID_IR, IF_ID_NPC;
    reg [31:0] ID_EX_A, ID_EX_B, ID_EX_IR, ID_EX_NPC, ID_EX_IMM;
    reg [31:0] EX_MEM_IR, EX_MEM_B, EX_MEM_ALUOut;
    reg        EX_MEM_Cond;
    reg [2:0]  ID_EX_type, EX_MEM_type, MEM_WB_type;
    reg [31:0] MEM_WB_ALUOut, MEM_WB_IR, MEM_WB_LMD, MEM_WB_B;

    reg HALTED;
    reg TAKEN_BRANCH;

    reg [31:0] Regbank [0:31];
    reg [31:0] InstrMem [0:1023];
    reg [31:0] DataMem  [0:1023];

    // Opcodes
    parameter ADD   = 6'b000000, SUB   = 6'b000001, AND   = 6'b000010,
              OR    = 6'b000011, SLT   = 6'b000100, MUL   = 6'b000101,
              HLT   = 6'b111111, LW    = 6'b001000, SW    = 6'b001001,
              ADDI  = 6'b001010, SUBI  = 6'b001011, SLTI  = 6'b001100,
              BNEQZ = 6'b001101, BEQZ  = 6'b001110, J     = 6'b001111,
              JAL   = 6'b010000, JR    = 6'b010001;

    // Instruction Types
    parameter RR_ALU = 3'b000, RM_ALU = 3'b001, LOAD = 3'b010,
              STORE = 3'b011, BRANCH = 3'b100, HALT = 3'b101, JUMP = 3'b110,
              NOP = 3'b111; // Internal bubble, not an ISA opcode

    // ----------------------------------------------------------------
    // RAW dependency detector (diagnostic only: fixed-latency forwarding
    // resolves register RAW dependencies under the supplied clock schedule).
    wire [5:0] id_opcode = IF_ID_IR[31:26];
    wire uses_rs, uses_rt;
    wire [4:0] ex_dest, mem_dest, wb_dest;
    wire hazard_rs, hazard_rt, hazard_detected;

    assign uses_rs = (id_opcode == ADD) || (id_opcode == SUB) ||
                     (id_opcode == AND) || (id_opcode == OR) ||
                     (id_opcode == SLT) || (id_opcode == MUL) ||
                     (id_opcode == ADDI) || (id_opcode == SUBI) ||
                     (id_opcode == SLTI) || (id_opcode == LW) ||
                     (id_opcode == SW) || (id_opcode == BEQZ) ||
                     (id_opcode == BNEQZ) || (id_opcode == JR);
    assign uses_rt = (id_opcode == ADD) || (id_opcode == SUB) ||
                     (id_opcode == AND) || (id_opcode == OR) ||
                     (id_opcode == SLT) || (id_opcode == MUL) ||
                     (id_opcode == SW);

    // R-type writes rd; immediate and load write rt; JAL writes R31.
    // Zero denotes no writable destination (including writes to R0).
    assign ex_dest =
        (ID_EX_type == RR_ALU) ? ID_EX_IR[15:11] :
        ((ID_EX_type == RM_ALU) || (ID_EX_type == LOAD)) ? ID_EX_IR[20:16] :
        ((ID_EX_type == JUMP) && (ID_EX_IR[31:26] == JAL)) ? 5'd31 : 5'd0;
    assign mem_dest =
        (EX_MEM_type == RR_ALU) ? EX_MEM_IR[15:11] :
        ((EX_MEM_type == RM_ALU) || (EX_MEM_type == LOAD)) ? EX_MEM_IR[20:16] :
        ((EX_MEM_type == JUMP) && (EX_MEM_IR[31:26] == JAL)) ? 5'd31 : 5'd0;
    assign wb_dest =
        (MEM_WB_type == RR_ALU) ? MEM_WB_IR[15:11] :
        ((MEM_WB_type == RM_ALU) || (MEM_WB_type == LOAD)) ? MEM_WB_IR[20:16] :
        ((MEM_WB_type == JUMP) && (MEM_WB_IR[31:26] == JAL)) ? 5'd31 : 5'd0;

    assign hazard_rs = uses_rs && (ex_dest != 0) && (IF_ID_IR[25:21] == ex_dest);
    assign hazard_rt = uses_rt && (ex_dest != 0) && (IF_ID_IR[20:16] == ex_dest);
    assign hazard_detected = hazard_rs || hazard_rt;

    // ----------------------------------------------------------------
    // FORWARDING UNIT: both EX/MEM and MEM/WB paths retained.
    wire [4:0] ex_rs = ID_EX_IR[25:21];
    wire [4:0] ex_rt = ID_EX_IR[20:16];
    wire ex_uses_rs, ex_uses_rt;
    wire mem_forward_valid, wb_forward_valid;
    wire [31:0] mem_forward_data, wb_forward_data;
    wire [1:0] ForwardA, ForwardB;
    wire [31:0] forward_A, forward_B;

    assign ex_uses_rs = (ID_EX_type == RR_ALU) || (ID_EX_type == RM_ALU) ||
                        (ID_EX_type == LOAD) || (ID_EX_type == STORE) ||
                        (ID_EX_type == BRANCH) ||
                        ((ID_EX_type == JUMP) && (ID_EX_IR[31:26] == JR));
    assign ex_uses_rt = (ID_EX_type == RR_ALU) || (ID_EX_type == STORE);

    // A load's EX/MEM ALU result is an address, never forward it as data.
    assign mem_forward_valid = (mem_dest != 0) && (EX_MEM_type != LOAD);
    assign mem_forward_data = ((EX_MEM_type == JUMP) &&
                               (EX_MEM_IR[31:26] == JAL)) ? EX_MEM_B : EX_MEM_ALUOut;
    assign wb_forward_valid = (wb_dest != 0);
    assign wb_forward_data = (MEM_WB_type == LOAD) ? MEM_WB_LMD :
                             ((MEM_WB_type == JUMP) &&
                              (MEM_WB_IR[31:26] == JAL)) ? MEM_WB_B : MEM_WB_ALUOut;

    // 10: EX/MEM, 01: MEM/WB, 00: saved ID/EX operand.
    // With the original fixed phase relationship, at the EX capture edge
    // both older-stage registers describe the preceding instruction.
    // Thus an immediately preceding load is ready in MEM/WB at that edge.
    assign ForwardA = (ex_uses_rs && mem_forward_valid && (mem_dest == ex_rs)) ? 2'b10 :
                      (ex_uses_rs && wb_forward_valid && (wb_dest == ex_rs)) ? 2'b01 : 2'b00;
    assign ForwardB = (ex_uses_rt && mem_forward_valid && (mem_dest == ex_rt)) ? 2'b10 :
                      (ex_uses_rt && wb_forward_valid && (wb_dest == ex_rt)) ? 2'b01 : 2'b00;
    assign forward_A = (ForwardA == 2'b10) ? mem_forward_data :
                       (ForwardA == 2'b01) ? wb_forward_data : ID_EX_A;
    assign forward_B = (ForwardB == 2'b10) ? mem_forward_data :
                       (ForwardB == 2'b01) ? wb_forward_data : ID_EX_B;

    // Shared combinational redirect decision from EX/MEM.
    // Both IF and EX observe this decision at the same clk1 edge.
    wire redirect;
    assign redirect =
        ((EX_MEM_type == BRANCH) &&
         (((EX_MEM_IR[31:26] == BEQZ) && EX_MEM_Cond) ||
          ((EX_MEM_IR[31:26] == BNEQZ) && !EX_MEM_Cond))) ||
        ((EX_MEM_type == JUMP) &&
         ((EX_MEM_IR[31:26] == J) || (EX_MEM_IR[31:26] == JAL) ||
          (EX_MEM_IR[31:26] == JR)));

    // ----------------------------------------------------------------
    // FETCH stage
    always @(posedge clk1) begin
      if(reset)begin
         PC <= 0;
        IF_ID_IR <= 0;
        IF_ID_NPC <= 0;
        TAKEN_BRANCH <= 0;
      end
     else if (!HALTED) begin
            if (redirect) begin
                IF_ID_IR <= 32'h00000000;  // Flush next instruction
                IF_ID_NPC <= EX_MEM_ALUOut + 4;
                PC <= EX_MEM_ALUOut;
                TAKEN_BRANCH <= 1;
            end else begin
                IF_ID_IR <= InstrMem[PC >> 2];
                IF_ID_NPC <= PC + 4;
                PC <= PC + 4;
                TAKEN_BRANCH <= 0;
            end
        end
    end

    // DECODE stage
    always @(posedge clk2) begin
      if (reset) begin
        ID_EX_IR   <= 0;
        ID_EX_A    <= 0;
        ID_EX_B    <= 0;
        ID_EX_IMM  <= 0;
        ID_EX_NPC  <= 0;
        ID_EX_type <= NOP;
  end else if (!HALTED) begin
            if (TAKEN_BRANCH) begin
                // Flush only; ordinary RAW dependencies are forwarded in EX
                ID_EX_IR   <= 32'h00000000;
                ID_EX_type <= NOP;
                ID_EX_A    <= 0;
                ID_EX_B    <= 0;
                ID_EX_IMM  <= 0;
                ID_EX_NPC  <= 0;
            end else begin
                // Normal decode: latch IF/ID into ID/EX
                ID_EX_IR <= IF_ID_IR;
                ID_EX_NPC <= IF_ID_NPC;
                ID_EX_IMM <= {{16{IF_ID_IR[15]}}, IF_ID_IR[15:0]};

                // Read registers (with $zero protection on read)
                ID_EX_A <= (IF_ID_IR[25:21] == 0) ? 0 : Regbank[IF_ID_IR[25:21]];
                ID_EX_B <= (IF_ID_IR[20:16] == 0) ? 0 : Regbank[IF_ID_IR[20:16]];

                // Determine instruction type
                case (IF_ID_IR[31:26])
                    ADD, SUB, AND, OR, SLT, MUL: ID_EX_type <= RR_ALU;
                    ADDI, SUBI, SLTI:           ID_EX_type <= RM_ALU;
                    LW:                         ID_EX_type <= LOAD;
                    SW:                         ID_EX_type <= STORE;
                    BNEQZ, BEQZ:                ID_EX_type <= BRANCH;
                    J, JAL, JR:                 ID_EX_type <= JUMP;
                    HLT:                        ID_EX_type <= HALT;
                    default:                    ID_EX_type <= HALT;
                endcase
            end
        end
    end

    // EXECUTE stage
    always @(posedge clk1) begin
      if (reset) begin
        EX_MEM_IR <= 0;
        EX_MEM_B <= 0;
        EX_MEM_ALUOut <= 0;
        EX_MEM_type <= NOP;
        EX_MEM_Cond <= 0;
   end else if (!HALTED) begin
          if (redirect) begin
            // Kill the younger wrong-path instruction at the same edge
            // at which IF redirects the PC. Do not execute ID/EX.
            EX_MEM_IR <= 0;
            EX_MEM_B <= 0;
            EX_MEM_ALUOut <= 0;
            EX_MEM_type <= NOP;
            EX_MEM_Cond <= 0;
          end else begin
            EX_MEM_IR <= ID_EX_IR;
            EX_MEM_B <= forward_B;
            EX_MEM_type <= ID_EX_type;

            case (ID_EX_type)
                RR_ALU: begin
                    case (ID_EX_IR[31:26])
                        ADD: EX_MEM_ALUOut <= forward_A + forward_B;
                        SUB: EX_MEM_ALUOut <= forward_A - forward_B;
                        AND: EX_MEM_ALUOut <= forward_A & forward_B;
                        OR:  EX_MEM_ALUOut <= forward_A | forward_B;
                        SLT: EX_MEM_ALUOut <= ($signed(forward_A) < $signed(forward_B));
                        MUL: EX_MEM_ALUOut <= forward_A * forward_B;
                        default: EX_MEM_ALUOut <= 32'b0;
                    endcase
                end
                RM_ALU: begin
                    case (ID_EX_IR[31:26])
                        ADDI: EX_MEM_ALUOut <= forward_A + ID_EX_IMM;
                        SUBI: EX_MEM_ALUOut <= forward_A - ID_EX_IMM;
                        SLTI: EX_MEM_ALUOut <= ($signed(forward_A) < $signed(ID_EX_IMM));
                        default: EX_MEM_ALUOut <= 32'hxxxxxxxx;
                    endcase
                end
                LOAD, STORE: begin
                    EX_MEM_ALUOut <= forward_A + ID_EX_IMM;
                end
                BRANCH: begin
                    EX_MEM_ALUOut <= ID_EX_NPC + (ID_EX_IMM << 2);
                    EX_MEM_Cond <= (forward_A == 0);
                end
                JUMP: begin
                    case (ID_EX_IR[31:26])
                        J, JAL: EX_MEM_ALUOut <= {ID_EX_NPC[31:28], ID_EX_IR[25:0], 2'b00};
                        JR:     EX_MEM_ALUOut <= forward_A;
                        default: EX_MEM_ALUOut <= 32'hxxxxxxxx;
                    endcase
                    if (ID_EX_IR[31:26] == JAL) begin
                        EX_MEM_B <= ID_EX_NPC;  // return address
                    end
                end
                default: begin
                    // HALT, NOP or others: no ALU operation
                    EX_MEM_ALUOut <= 0;
                    EX_MEM_Cond <= 0;
                end
            endcase
          end
        end
    end

    // MEMORY stage
    always @(posedge clk2) begin
      if (reset) begin
        MEM_WB_IR <= 0;
        MEM_WB_type <= NOP;
        MEM_WB_B <= 0;
        MEM_WB_ALUOut <= 0;
        MEM_WB_LMD <= 0;
    end else if (!HALTED) begin
            MEM_WB_IR <= EX_MEM_IR;
            MEM_WB_type <= EX_MEM_type;
            MEM_WB_B <= EX_MEM_B;

            case (EX_MEM_type)
                RR_ALU, RM_ALU: begin
                    MEM_WB_ALUOut <= EX_MEM_ALUOut;
                end
                LOAD: begin
                    MEM_WB_LMD <= DataMem[EX_MEM_ALUOut >> 2];
                end
                STORE: begin
                    // Wrong-path instructions are already killed in EX.
                    DataMem[EX_MEM_ALUOut >> 2] <= EX_MEM_B;
                end
                default: begin
                    // Nothing for BRANCH/JUMP/HALT/NOP in MEM stage
                end
            endcase
        end
    end

    // WRITEBACK stage: use the current instruction's destination.
    // HALTED has one procedural driver (synchronous active-high reset).
    always @(posedge clk1) begin
        if (reset) begin
            HALTED <= 1'b0;
        end else if (!HALTED) begin
            case (MEM_WB_type)
                RR_ALU, RM_ALU, LOAD, JUMP: begin
                    if (wb_dest != 0)
                        Regbank[wb_dest] <= wb_forward_data;
                end
                HALT: HALTED <= 1'b1;
                default: begin
                    // BRANCH, STORE and NOP do not write registers.
                end
            endcase
        end
    end

endmodule
