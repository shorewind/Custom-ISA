`timescale 1ns/1ps
`include "defs.vh"

module tb_cpu;

    reg clk;
    reg reset;

    // Unit under test
    cpu uut (
        .clk  (clk),
        .reset(reset)
    );

    // clock: 10ns period
    always #5 clk = ~clk;

    // ------------------------------
    // Encoding helpers (match ISA)
    // ------------------------------

    // R-Type:
    // [15:13] op
    // [12:10] rs
    // [ 9:7 ] rt_or_imm
    // [ 6:4 ] rd
    // [ 3:1 ] funct
    // [ 0   ] iflag
    function [15:0] enc_rtype;
        input [2:0] op;
        input [2:0] rs;
        input [2:0] rt_or_imm;
        input [2:0] rd;
        input [2:0] funct;
        input       iflag;
        begin
            enc_rtype = {op, rs, rt_or_imm, rd, funct, iflag};
        end
    endfunction

    // LS-Type:
    // [15:13] op
    // [12:10] rs   (base)
    // [ 9:7 ] rt   (reg)
    // [ 6:0 ] imm7 (offset)
    function [15:0] enc_ls;
        input [2:0] op;
        input [2:0] rs;
        input [2:0] rt;
        input [6:0] imm7;
        begin
            enc_ls = {op, rs, rt, imm7};
        end
    endfunction

    // IJ-Type:
    // [15:13] op
    // [12:10] rd_or_rs
    // [ 9:0 ] imm10
    function [15:0] enc_ij;
        input [2:0] op;
        input [2:0] rd;
        input [9:0] imm10;
        begin
            enc_ij = {op, rd, imm10};
        end
    endfunction

    integer i;

    initial begin
        clk   = 1'b1;
        reset = 1'b1;

        // Clear instruction & data memory
        for (i = 0; i < 64; i = i + 1) begin
            uut.unified_mem.mem[i] = 16'h0000;
        end

        // Clear registers (r[])
        for (i = 0; i < 8; i = i + 1) begin
            uut.reg_file.r[i] = 16'h0000;
        end

        // ----------------------------------------------------
        // Program to exercise all instructions
        // ----------------------------------------------------
        //  0: LDI r1, 10
        uut.unified_mem.mem[0]  = enc_ij(`OP_LDI, 3'd1, 10'd10);

        //  1: LDI r2, 3
        uut.unified_mem.mem[1]  = enc_ij(`OP_LDI, 3'd2, 10'd3);

        //  2: ADD  r3 = r1 + r2    (10 + 3 = 13)
        uut.unified_mem.mem[2]  = enc_rtype(`OP_R, 3'd1, 3'd2, 3'd3, `F_ADD, 1'b0);

        //  3: SUB  r4 = r1 - r2    (10 - 3 = 7)
        uut.unified_mem.mem[3]  = enc_rtype(`OP_R, 3'd1, 3'd2, 3'd4, `F_SUB, 1'b0);

        //  4: AND  r5 = r1 & r2    (10 & 3 = 2)
        uut.unified_mem.mem[4]  = enc_rtype(`OP_R, 3'd1, 3'd2, 3'd5, `F_AND, 1'b0);

        //  5: OR   r6 = r1 | r2    (10 | 3 = 11)
        uut.unified_mem.mem[5]  = enc_rtype(`OP_R, 3'd1, 3'd2, 3'd6, `F_OR, 1'b0);

        //  6: SLT  r7 = (r2 < r1) ? 1 : 0   (3 < 10 → 1)
        uut.unified_mem.mem[6]  = enc_rtype(`OP_R, 3'd2, 3'd1, 3'd7, `F_SLT, 1'b0);

        //  7: ADDI r1 = r1 + 1     (iflag=1, imm3=1)
        uut.unified_mem.mem[7]  = enc_rtype(`OP_R, 3'd1, 3'd1, 3'd1, `F_ADD, 1'b1);

        //  8: SLL  r2 << 1         (3 << 1 = 6)
        uut.unified_mem.mem[8]  = enc_rtype(`OP_R, 3'd2, 3'd1, 3'd2, `F_SLL, 1'b1);

        //  9: SRL  r2 >> 1         (6 >> 1 = 3)
        uut.unified_mem.mem[9]  = enc_rtype(`OP_R, 3'd2, 3'd1, 3'd2, `F_SRL, 1'b1);

        // 10: ST   M[r0 + 31] <- r3 (addr = 31)
        uut.unified_mem.mem[10] = enc_ls(`OP_ST, 3'd0, 3'd3, 7'd31);

        // 11: LD   r4 <- M[r0 + 31] (=> 13)
        uut.unified_mem.mem[11] = enc_ls(`OP_LD, 3'd0, 3'd4, 7'd31);

        // 12: BEZ  r4, +1          (r4 != 0 so NOT taken; executes at 13)
        uut.unified_mem.mem[12] = enc_ij(`OP_BEZ, 3'd4, 10'd1);

        // 13: BNZ  r4, +1          (r4 != 0 so taken; skips 14)
        uut.unified_mem.mem[13] = enc_ij(`OP_BNZ, 3'd4, 10'd1);

        // 14: LDI  r5, 99          (should be skipped if BNZ works)
        uut.unified_mem.mem[14] = enc_ij(`OP_LDI, 3'd5, 10'd99);

        // 15: JL   18          (jump to PC = 18, link in r7)
        uut.unified_mem.mem[15] = enc_ij(`OP_JL, 3'd7, 10'd18);

        // 16: HALT (END)
        uut.unified_mem.mem[16] = enc_rtype(`OP_R, 3'd0, 3'd0, 3'd0, `F_HALT, 1'b0);

        // 17: NOP (0)
        uut.unified_mem.mem[17] = 16'h0000;

        // 18: LDI  r1, 42          (function body)
        uut.unified_mem.mem[18] = enc_ij(`OP_LDI, 3'd1, 10'd42);

        // 19: JR   r7              (return to whatever JL stored)
        uut.unified_mem.mem[19] = enc_ij(`OP_JR, 3'd7, 10'd0);

        // 20: ADDI r1 = r1 + 1     (should not execute after JR if link worked)
        uut.unified_mem.mem[20] = enc_rtype(`OP_R, 3'd1, 3'd1, 3'd1, `F_ADD, 1'b1);
        
	// Release reset after 20 time units (~2 cycles)
        #20;
        reset = 1'b0;

        // Run long enough to step through everything
        #190;

        reset = 1'b1;
	#20;
        reset = 1'b0;
	#20;

        $display("\n==== FINAL STATE ====");
        for (i = 0; i < 8; i = i + 1) begin
            $display("R%0d = 0x%04h (%0d)", i, uut.reg_file.r[i], uut.reg_file.r[i]);
        end

        $display("MEM[0..31]:");
        for (i = 0; i < 32; i = i + 1) begin
            $display("MEM[%0d] = 0x%04h (%0d)", i, uut.unified_mem.mem[i], uut.unified_mem.mem[i]);
        end

        $finish;
    end

    // ----------------------------------------------------
    // Cycle-by-cycle debug print with instruction labels
    // ----------------------------------------------------
    always @(posedge clk) begin
        if (reset) begin
            $display("----- t=%0t (RESET ACTIVE) -----", $time);
            $display("PC = %0d", uut.pc);
            $display("-----------------------------\n");
        end else begin
            $display("----- t=%0t -----", $time);
            $display("PC     = %0d", uut.pc);
            $display("INSTR  = 0x%04h", uut.instr);
            $display("DECODE : opcode=%b rs=%0d rt=%0d rd=%0d funct=%b iflag=%b",
                     uut.instr[15:13], uut.instr[12:10],
                     uut.instr[9:7],   uut.instr[6:4],
                     uut.instr[3:1],   uut.instr[0]);

            // Label the current instruction and its intended RTL
            case (uut.pc)
                0: begin
                    $display("INST   : [PC 0] LDI r1, 10");
                    $display("RTL    : r1 = 10");
                end
                1: begin
                    $display("INST   : [PC 1] LDI r2, 3");
                    $display("RTL    : r2 = 3");
                end
                2: begin
                    $display("INST   : [PC 2] ADD r3, r1, r2");
                    $display("RTL    : r3 = r1 + r2 = 10 + 3 = 13");
                end
                3: begin
                    $display("INST   : [PC 3] SUB r4, r1, r2");
                    $display("RTL    : r4 = r1 - r2 = 10 - 3 = 7 (later overwritten by LD)");
                end
                4: begin
                    $display("INST   : [PC 4] AND r5, r1, r2");
                    $display("RTL    : r5 = r1 & r2 = 10 & 3 = 2");
                end
                5: begin
                    $display("INST   : [PC 5] OR r6, r1, r2");
                    $display("RTL    : r6 = r1 | r2 = 10 | 3 = 11");
                end
                6: begin
                    $display("INST   : [PC 6] SLT r7, r2, r1");
                    $display("RTL    : r7 = (r2 < r1) ? 1 : 0 = (3 < 10) ? 1 : 0 = 1");
                end
                7: begin
                    $display("INST   : [PC 7] ADDI r1, r1, +1");
                    $display("RTL    : r1 = r1 + 1  (11 after this if it was 10)");
                end
                8: begin
                    $display("INST   : [PC 8] SLL r2, r2, 1");
                    $display("RTL    : r2 = r2 << 1  (3 << 1 = 6)");
                end
                9: begin
                    $display("INST   : [PC 9] SRL r2, r2, 1");
                    $display("RTL    : r2 = r2 >> 1  (6 >> 1 = 3)");
                end
                10: begin
                    $display("INST   : [PC 10] ST [r0 + 31] <- r3");
                    $display("RTL    : MEM[31] = r3 = 13");
                end
                11: begin
                    $display("INST   : [PC 11] LD r4 <- [r0 + 31]");
                    $display("RTL    : r4 = MEM[31] = 13");
                end
                12: begin
                    $display("INST   : [PC 12] BEZ r4, +1");
                    $display("RTL    : if (r4 == 0) PC += offset; here r4 != 0 so NOT taken");
                end
                13: begin
                    $display("INST   : [PC 13] BNZ r4, +1");
                    $display("RTL    : if (r4 != 0) PC += offset; here r4 != 0 so TAKEN (skip PC 14)");
                end
                14: begin
                    $display("INST   : [PC 14] LDI r5, 99");
                    $display("RTL    : r5 = 99 (should be skipped if BNZ at PC 13 worked)");
                end
                15: begin
                    $display("INST   : [PC 15] JL 18");
                    $display("RTL    : r7 = return_addr; PC jumps to 18");
                end
                16: begin
                    $display("INST   : [PC 16] HALT (end of program)");
                    $display("RTL    : Stop execution");
                end
                17: begin
                    $display("INST   : [PC 17] NOP (0)");
                    $display("RTL    : No operation");
                end
                18: begin
                    $display("INST   : [PC 18] LDI r1, 42");
                    $display("RTL    : r1 = 42 (function body after JL)");
                end
                19: begin
                    $display("INST   : [PC 19] JR r7");
                    $display("RTL    : PC = r7 (return to caller)");
                end
                20: begin
                    $display("INST   : [PC 20] ADDI r1, r1, +1");
                    $display("RTL    : r1 = r1 + 1  (42 + 1 = 43 not executed if JR returned correctly)");
                end
                default: begin
                    $display("INST   : [PC %0d] (no label defined)", uut.pc);
                end
            endcase

            // Normal signal trace
            $display("CONTROL: alu_op=%b reg_dst=%b reg_write=%b mem_read=%b mem_write=%b branch_ez=%b branch_nz=%b imm_jump=%b reg_jump=%b return_link=%b halt=%b",
                     uut.alu_op, uut.reg_dst, uut.alu_src,
                     uut.mem_to_reg, uut.reg_write,
                     uut.mem_read, uut.mem_write,
                     uut.branch_eq, uut.branch_ne, uut.imm_jump, uut.reg_jump, uut.return_link, uut.halt);

            $display("ALU    : vrs(a)=%0d  alu_b(b)=%0d  -> y=%0d  zero=%b",
                     uut.vrs, uut.alu_b, uut.alu_y, uut.alu_zero);

            $display("WB     : write_reg=%0d  wb_data=%0d  reg_write=%b",
                     uut.write_reg, uut.wb_data, uut.reg_write);

            $display("REGS   : r0=%0d r1=%0d r2=%0d r3=%0d r4=%0d r5=%0d r6=%0d r7=%0d",
                     uut.reg_file.r[0], uut.reg_file.r[1], uut.reg_file.r[2], uut.reg_file.r[3],
                     uut.reg_file.r[4], uut.reg_file.r[5], uut.reg_file.r[6], uut.reg_file.r[7]);

            $display("MEM    : M[31]=%0d M[30]=%0d M[1]=%0d M[0]=%0d",
                     uut.unified_mem.mem[31], uut.unified_mem.mem[30],
                     uut.unified_mem.mem[1], uut.unified_mem.mem[0]);
            $display("-----------------------------\n");
        end
    end

endmodule
