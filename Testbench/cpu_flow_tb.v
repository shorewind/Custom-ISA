`timescale 1ns/1ps
`include "defs.vh"

module tb_cpu_flow;

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
        clk   = 1'b0;
        reset = 1'b1;

        // ----------------------------------------------------
        // Unified memory:
        //   - Low addresses (e.g., 0..63) used for instructions
        //   - Higher addresses reserved for data
        // ----------------------------------------------------
        for (i = 0; i < 64; i = i + 1) begin
            uut.unified_mem.mem[i] = 16'h0000;
        end

        // Clear registers (r[])
        for (i = 0; i < 8; i = i + 1) begin
            uut.reg_file.r[i] = 16'h0000;
        end

        // ----------------------------------------------------
        // Program to exercise control structures:
        //   - if / else
        //   - while loop
        //   - for loop
        //   - function call / return (JL / JR)
        //
        // Registers used:
        //   r1, r2 : values / bounds (a, b, etc.)
        //   r3     : if-else result (c)
        //   r4     : accumulator (sum)
        //   r5     : while-loop index i
        //   r6     : for-loop index j
        //   r7     : link register ($ra) and branch temp
        // ----------------------------------------------------

        // ---------------------------------------------
        // C: int a = 2, b = 3;
        // ---------------------------------------------
        //  0: LDI r1, 2   ; a = 2
        uut.unified_mem.mem[0]  = enc_ij(`OP_LDI, 3'd1, 10'd2);
        //  1: LDI r2, 3   ; b = 3
        uut.unified_mem.mem[1]  = enc_ij(`OP_LDI, 3'd2, 10'd3);

        // ---------------------------------------------
        // C: if (a < b) { c = 1; } else { c = 2; }
        //    a in r1, b in r2, c in r3
        // ---------------------------------------------
        //  2: SLT r4, r1, r2    ; r4 = (a < b)
        uut.unified_mem.mem[2]  = enc_rtype(`OP_R, 3'd1, 3'd2, 3'd4, `F_SLT, 1'b0);
        //  3: BEZ r4, +2        ; if !cond -> jump to else at PC = 6
        //      PC_target = 3 + 1 + 2 = 6
        uut.unified_mem.mem[3]  = enc_ij(`OP_BEZ, 3'd4, 10'd2);
        //  4: LDI r3, 1         ; then: c = 1
        uut.unified_mem.mem[4]  = enc_ij(`OP_LDI, 3'd3, 10'd1);
        //  5: BNZ r4, +1        ; jump to after_if at PC = 7
        //      PC_target = 5 + 1 + 1 = 7
        uut.unified_mem.mem[5]  = enc_ij(`OP_BNZ, 3'd4, 10'd1);
        //  6: LDI r3, 2         ; else: c = 2
        uut.unified_mem.mem[6]  = enc_ij(`OP_LDI, 3'd3, 10'd2);
        //  7: after_if:

        // ---------------------------------------------
        // C: while (i < 2) { i++; }
        //    i in r5, bound 2 in r1
        // ---------------------------------------------
        //  7: LDI r5, 0         ; i = 0
        uut.unified_mem.mem[7]  = enc_ij(`OP_LDI, 3'd5, 10'd0);
        //  8: loop_top: SLT r6, r5, r1  ; r6 = (i < 3)
        uut.unified_mem.mem[8]  = enc_rtype(`OP_R, 3'd5, 3'd1, 3'd6, `F_SLT, 1'b0);
        //  9: BEZ r6, +2        ; if !(i < 3) -> loop_end at PC = 12
        //      PC_target = 9 + 1 + 2 = 12
        uut.unified_mem.mem[9]  = enc_ij(`OP_BEZ, 3'd6, 10'd2);
        // 10: ADDI r5, r5, +1   ; i++
        //      rs = 5, imm3 = 1, rd = 5
        uut.unified_mem.mem[10] = enc_rtype(`OP_R, 3'd5, 3'd1, 3'd5, `F_ADD, 1'b1);
        // 11: BNZ r6, -4        ; back to loop_top (PC = 8)
        //      offset = 8 - (11 + 1) = -4 -> 10-bit two's-comp = 1020
        uut.unified_mem.mem[11] = enc_ij(`OP_BNZ, 3'd6, 10'd1020);
        // 12: loop_end:

        // ---------------------------------------------
        // C: for (j = 0; j < b; j++) { sum += j; }
        //    j in r6, sum in r4, b in r2 (=3)
        // ---------------------------------------------
        // 12: LDI r6, 0         ; j = 0
        uut.unified_mem.mem[12] = enc_ij(`OP_LDI, 3'd6, 10'd0);
        // 13: LDI r4, 0         ; sum = 0
        uut.unified_mem.mem[13] = enc_ij(`OP_LDI, 3'd4, 10'd0);
        // 14: for_top: SLT r7, r6, r2  ; r7 = (j < b)
        uut.unified_mem.mem[14] = enc_rtype(`OP_R, 3'd6, 3'd2, 3'd7, `F_SLT, 1'b0);
        // 15: BEZ r7, +3        ; if !(j < b) -> for_end at PC = 19
        //      PC_target = 15 + 1 + 3 = 19
        uut.unified_mem.mem[15] = enc_ij(`OP_BEZ, 3'd7, 10'd3);
        // 16: ADD r4, r4, r6    ; sum += j
        uut.unified_mem.mem[16] = enc_rtype(`OP_R, 3'd4, 3'd6, 3'd4, `F_ADD, 1'b0);
        // 17: ADDI r6, r6, +1   ; j++
        uut.unified_mem.mem[17] = enc_rtype(`OP_R, 3'd6, 3'd1, 3'd6, `F_ADD, 1'b1);
        // 18: BNZ r7, -5        ; back to for_top (PC = 14)
        //      offset = 14 - (18 + 1) = -5 -> 10-bit two's-comp = 1019
        uut.unified_mem.mem[18] = enc_ij(`OP_BNZ, 3'd7, 10'd1019);
        // 19: for_end:

        // ---------------------------------------------
        // C: int inc(int x) { return x + 1; }
        //    r1 = inc(10);
        //    x in r1, return in r1, r7 as $ra
        // ---------------------------------------------
        // 20: LDI r1, 10        ; argument x = 10
        uut.unified_mem.mem[20] = enc_ij(`OP_LDI, 3'd1, 10'd10);
        // 21: JL 24             ; call inc at PC = 24, link in r7
        uut.unified_mem.mem[21] = enc_ij(`OP_JL, 3'd7, 10'd24);
        // 22: ADDI r1, r1, 0    ; no-op, should see r1 = 11 if call/ret worked
        //      rs = 1, imm3 = 0, rd = 1
        uut.unified_mem.mem[22] = enc_rtype(`OP_R, 3'd1, 3'd0, 3'd1, `F_ADD, 1'b1);
        // 23: HALT              ; end of main program
        uut.unified_mem.mem[23] = enc_rtype(`OP_R, 3'd0, 3'd0, 3'd0, `F_HALT, 1'b0);

        // Function inc: int inc(int x) { return x + 1; }
        // 24: ADDI r1, r1, +1   ; r1 = r1 + 1
        uut.unified_mem.mem[24] = enc_rtype(`OP_R, 3'd1, 3'd1, 3'd1, `F_ADD, 1'b1);
        // 25: JR r7             ; return to caller
        uut.unified_mem.mem[25] = enc_ij(`OP_JR, 3'd7, 10'd0);

        // Release reset after 20 time units (~2 cycles)
        #20;
        reset = 1'b0;

        // Run long enough to step through everything (loops + call)
        #430;

        $display("\n==== FINAL STATE ====");
        for (i = 0; i < 8; i = i + 1) begin
            $display("R%0d = 0x%04h (%0d)", i, uut.reg_file.r[i], uut.reg_file.r[i]);
        end

        // Show a slice of unified memory:
        $display("MEM[0..31]:");
        for (i = 0; i < 32; i = i + 1) begin
            $display("MEM[%0d] = 0x%04h (%0d)", i, uut.unified_mem.mem[i], uut.unified_mem.mem[i]);
        end

        $finish;
    end

    // ----------------------------------------------------
    // Cycle-by-cycle debug print with instruction labels
    // ----------------------------------------------------
    always @(negedge clk) begin
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

            // Label the current instruction and its intended C/RTL meaning
            case (uut.pc)
                0: begin
                    $display("INST   : [PC 0] LDI r1, 2");
                    $display("C      : int a = 2;");
                end
                1: begin
                    $display("INST   : [PC 1] LDI r2, 3");
                    $display("C      : int b = 3;");
                end
                2: begin
                    $display("INST   : [PC 2] SLT r4, r1, r2");
                    $display("C      : cond = (a < b);");
                    $display("RTL    : r4 = (r1 < r2) ? 1 : 0;");
                end
                3: begin
                    $display("INST   : [PC 3] BEZ r4, +2");
                    $display("C      : if (!cond) goto else;");
                end
                4: begin
                    $display("INST   : [PC 4] LDI r3, 1");
                    $display("C      : then: c = 1;");
                end
                5: begin
                    $display("INST   : [PC 5] BNZ r4, +1");
                    $display("C      : goto after_if;");
                end
                6: begin
                    $display("INST   : [PC 6] LDI r3, 2");
                    $display("C      : else: c = 2;");
                end
                7: begin
                    $display("INST   : [PC 7] LDI r5, 0");
                    $display("C      : int i = 0;  // while-loop init");
                end
                8: begin
                    $display("INST   : [PC 8] SLT r6, r5, r1");
                    $display("C      : while (i < 2) {");
                    $display("RTL    : r6 = (r5 < r1) ? 1 : 0;");
                end
                9: begin
                    $display("INST   : [PC 9] BEZ r6, +2");
                    $display("C      : if (!(i < 2)) break;");
                end
                10: begin
                    $display("INST   : [PC 10] ADDI r5, r5, +1");
                    $display("C      : i++;");
                end
                11: begin
                    $display("INST   : [PC 11] BNZ r6, -4");
                    $display("C      : loop back to while condition;");
                end
                12: begin
                    $display("INST   : [PC 12] LDI r6, 0");
                    $display("C      : int j = 0;  // for-loop init");
                end
                13: begin
                    $display("INST   : [PC 13] LDI r4, 0");
                    $display("C      : int sum = 0;");
                end
                14: begin
                    $display("INST   : [PC 14] SLT r7, r6, r2");
                    $display("C      : for (j < 3) {");
                    $display("RTL    : r7 = (r6 < r2) ? 1 : 0;");
                end
                15: begin
                    $display("INST   : [PC 15] BEZ r7, +3");
                    $display("C      : if (!(j < b)) break;");
                end
                16: begin
                    $display("INST   : [PC 16] ADD r4, r4, r6");
                    $display("C      : sum += j;");
                end
                17: begin
                    $display("INST   : [PC 17] ADDI r6, r6, +1");
                    $display("C      : j++;");
                end
                18: begin
                    $display("INST   : [PC 18] BNZ r7, -5");
                    $display("C      : loop back to for condition;");
                end
                19: begin
                    $display("INST   : [PC 19] NOP (for_end)");
                    $display("C      : end of for-loop;");
                end
                20: begin
                    $display("INST   : [PC 20] LDI r1, 10");
                    $display("C      : r1 = 10;  // argument x for inc(x)");
                end
                21: begin
                    $display("INST   : [PC 21] JL 24");
                    $display("C      : call inc;");
                    $display("RTL    : r7 = return_addr; PC = 24;");
                end
                22: begin
                    $display("INST   : [PC 22] ADDI r1, r1, 0");
                    $display("C      : // after return, r1 should be x+1 = 11;");
                end
                23: begin
                    $display("INST   : [PC 23] HALT");
                    $display("C      : end of main;");
                end
                24: begin
                    $display("INST   : [PC 24] ADDI r1, r1, +1");
                    $display("C      : int inc(int x) { return x + 1; }");
                end
                25: begin
                    $display("INST   : [PC 25] JR r7");
                    $display("C      : return from inc;");
                end
                default: begin
                    $display("INST   : [PC %0d] (no label defined)", uut.pc);
                end
            endcase

            // Normal signal trace
            $display("CONTROL: alu_op=%b reg_dst=%b alu_src=%b mem_to_reg=%b reg_write=%b mem_read=%b mem_write=%b branch_ez=%b branch_nz=%b imm_jump=%b reg_jump=%b return_link=%b halt=%b",
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

            $display("MEM    : M[0]=%0d M[1]=%0d M[2]=%0d M[3]=%0d",
                     uut.unified_mem.mem[0], uut.unified_mem.mem[1],
                     uut.unified_mem.mem[2], uut.unified_mem.mem[3]);
            $display("-----------------------------\n");
        end
    end

endmodule
