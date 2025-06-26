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
              STORE = 3'b011, BRANCH = 3'b100, HALT = 3'b101, JUMP = 3'b110;

    // ----------------------------------------------------------------
    // Hazard detection signals: declare at module scope
    wire hazard_rs;
    wire hazard_rt;
    wire hazard_detected;

    // Combinational assignments for hazard detection
    // RAW hazard: check if ID stage sources match ID_EX destination
    assign hazard_rs = ((ID_EX_type == RR_ALU || ID_EX_type == RM_ALU || ID_EX_type == LOAD) &&
                        (IF_ID_IR[25:21] != 0) &&
                        ((IF_ID_IR[25:21] == ID_EX_IR[20:16]) ||
                         (IF_ID_IR[25:21] == ID_EX_IR[15:11])));
    assign hazard_rt = ((ID_EX_type == RR_ALU || ID_EX_type == RM_ALU || ID_EX_type == LOAD) &&
                        (IF_ID_IR[20:16] != 0) &&
                        ((IF_ID_IR[20:16] == ID_EX_IR[20:16]) ||
                         (IF_ID_IR[20:16] == ID_EX_IR[15:11])));
    assign hazard_detected = hazard_rs || hazard_rt;

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
            // Branch/jump taken check (as in your code)
            if (((EX_MEM_IR[31:26] == BEQZ) && EX_MEM_Cond == 1) ||
                ((EX_MEM_IR[31:26] == BNEQZ) && EX_MEM_Cond == 0) ||
                (EX_MEM_IR[31:26] == J) || (EX_MEM_IR[31:26] == JAL) ||
                (EX_MEM_IR[31:26] == JR)) begin
                IF_ID_IR <= 32'h00000000;  // Flush next instruction
                IF_ID_NPC <= EX_MEM_ALUOut + 4;
                PC <= EX_MEM_ALUOut;
                TAKEN_BRANCH <= 1;
            end else begin
                IF_ID_IR <= InstrMem[PC];
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
        ID_EX_type <= HALT;
  end else if (!HALTED) begin
            if (TAKEN_BRANCH || hazard_detected) begin
                // Stall/NOP: inject bubble
                ID_EX_IR   <= 32'h00000000;
                ID_EX_type <= HALT;  // or a dedicated NOP type if you have one
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
        EX_MEM_type <= HALT;
        EX_MEM_Cond <= 0;
   end else if (!HALTED) begin
            EX_MEM_IR <= ID_EX_IR;
            EX_MEM_B <= ID_EX_B;
            EX_MEM_type <= ID_EX_type;

            case (ID_EX_type)
                RR_ALU: begin
                    case (ID_EX_IR[31:26])
                        ADD: EX_MEM_ALUOut <= ID_EX_A + ID_EX_B;
                        SUB: EX_MEM_ALUOut <= ID_EX_A - ID_EX_B;
                        AND: EX_MEM_ALUOut <= ID_EX_A & ID_EX_B;
                        OR:  EX_MEM_ALUOut <= ID_EX_A | ID_EX_B;
                        SLT: EX_MEM_ALUOut <= (ID_EX_A < ID_EX_B);
                        MUL: EX_MEM_ALUOut <= ID_EX_A * ID_EX_B;
                        default: EX_MEM_ALUOut <= 32'b0;
                    endcase
                end
                RM_ALU: begin
                    case (ID_EX_IR[31:26])
                        ADDI: EX_MEM_ALUOut <= ID_EX_A + ID_EX_IMM;
                        SUBI: EX_MEM_ALUOut <= ID_EX_A - ID_EX_IMM;
                        SLTI: EX_MEM_ALUOut <= (ID_EX_A < ID_EX_IMM);
                        default: EX_MEM_ALUOut <= 32'hxxxxxxxx;
                    endcase
                end
                LOAD, STORE: begin
                    EX_MEM_ALUOut <= ID_EX_A + ID_EX_IMM;
                end
                BRANCH: begin
                    EX_MEM_ALUOut <= ID_EX_NPC + ID_EX_IMM;
                    EX_MEM_Cond <= (ID_EX_A == 0);
                end
                JUMP: begin
                    case (ID_EX_IR[31:26])
                        J, JAL: EX_MEM_ALUOut <= {ID_EX_NPC[31:28], ID_EX_IR[25:0], 2'b00};
                        JR:     EX_MEM_ALUOut <= ID_EX_A;
                        default: EX_MEM_ALUOut <= 32'hxxxxxxxx;
                    endcase
                    if (ID_EX_IR[31:26] == JAL) begin
                        EX_MEM_B <= ID_EX_NPC;  // return address
                    end
                end
                default: begin
                    // For HALT or others: you may choose to pass through or do nothing
                    EX_MEM_ALUOut <= 0;
                    EX_MEM_Cond <= 0;
                end
            endcase
        end
    end

    // MEMORY stage
    always @(posedge clk2) begin
      if (reset) begin
        MEM_WB_IR <= 0;
        MEM_WB_type <= HALT;
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
                    MEM_WB_LMD <= DataMem[EX_MEM_ALUOut];
                end
                STORE: begin
                    // Note: original code gated this by !TAKEN_BRANCH; consider removing that gating if you want correct stores.
                    if (!TAKEN_BRANCH) begin
                        DataMem[EX_MEM_ALUOut] <= EX_MEM_B;
                    end
                end
                default: begin
                    // Nothing for BRANCH/JUMP/HALT in MEM stage
                end
            endcase
        end
    end

   reg [4:0] dest;
    // WRITEBACK stage
    always @(posedge clk1) begin
        // Note: original code gated by !TAKEN_BRANCH; consider removing that gating for correctness.
            
            if (reset) begin
        HALTED <= 0;
    end else begin
            case (MEM_WB_type)
                RR_ALU: begin
                    dest <= MEM_WB_IR[15:11];
                     if (dest != 0)
                            Regbank[dest] <= MEM_WB_ALUOut;
                end
                RM_ALU: begin
                    dest <= MEM_WB_IR[20:16];
                    if (dest != 0)
                       Regbank[dest] <= MEM_WB_ALUOut;
                end
                LOAD: begin
                    dest <= MEM_WB_IR[20:16];
                    if (dest != 0)
                       Regbank[dest] <= MEM_WB_LMD;
                end
                JUMP: begin
                    if (MEM_WB_IR[31:26] == JAL) begin
                        Regbank[31] <= MEM_WB_B;
                    end
                end
                HALT: begin
                    HALTED <= 1'b1;
                end
                default: begin
                    // no writeback for BRANCH, etc.
                end
            endcase
    end end
    
    
    always @(posedge reset)
    HALTED <= 0;

endmodule