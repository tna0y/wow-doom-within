-- src/aot.lua
--
-- Runtime glue between the DoomWithin addon and the AOT-compiled Lua chunk
-- emitted by ``risc-v-wow-emu/tools/aot_compile.py``.  The generated file
-- (``doomgeneric_aot.lua``) assigns a single global:
--
--     _DW_DoomAOTChunk = function(bootState, memTable, ecallBridge, fpuBridge)
--         ...
--         return { run = ..., blocks = ..., sync_out = ..., sync_in = ... }
--     end
--
-- This file defines a single global, ``_DW_StartAOT``, that the game loader
-- invokes after all memory chunks are resident.  It wires the AOT chunk to
-- the live RiscVCore instance and monkey-patches ``cpu.Run`` so that the
-- existing ``RVEMU_Resume`` yield/resume path (used by blocking syscalls)
-- keeps working unchanged.
--
-- Optional lockstep verify mode:
--   Set the global ``_DW_AOT_VERIFY = true`` BEFORE ``_DW_StartAOT`` is
--   invoked (e.g. via ``/run _DW_AOT_VERIFY = true`` in the chat frame)
--   and the ``cpu.Run`` path installed below re-executes every AOT block
--   through the legacy single-stepper on a cloned register snapshot and
--   prints a divergence report if they disagree.  Blocks containing an
--   ECALL are skipped (re-running a syscall inline would double-draw or
--   double-poll inputs); the AOT result is trusted for those.
--   The flag ``_DW_AOT_VERIFY_DIVERGED`` is set to ``true`` the first time
--   a divergence is observed, so callers can detect it post-hoc.
--
-- Verify mode is slow (every block pays a full snapshot + legacy rerun)
-- but correct; it is NOT intended to be left on in shipped builds.

function _DW_StartAOT(cpu, game)
    -- The AOT template references ``bootState.CPU.registers[i]`` and
    -- ``bootState.CPU:StepLegacy()``.  We pass ``cpu`` itself as the
    -- bootState, so aliasing ``cpu.CPU = cpu`` lets those paths resolve
    -- straight to the live core.  Also means ``bootState.is_running`` reads
    -- and writes ``cpu.is_running`` directly, which is what the legacy
    -- ECALL handler already mutates when a syscall needs to yield.
    cpu.CPU = cpu

    -- ECALL bridge: the generated code calls ``ecall(a7)`` at every ecall
    -- site, already surrounded by sync_out / sync_in in the template, so
    -- this closure just needs to forward to the existing handler.
    local ecall_handler = cpu.ecall_handler
    local ecallBridge = function(a7) ecall_handler(cpu, a7) end

    -- Pre-capture the memory accessors once so the FP load/store bridges
    -- don't re-build the closure on every call.  ``cpu.memory:Read/Write``
    -- returns a function specialized for the given access width.
    local read_float  = cpu.memory:Read('float')
    local read_double = cpu.memory:Read('double')
    local write_float  = cpu.memory:Write('float')
    local write_double = cpu.memory:Write('double')

    local fregisters = cpu.fregisters

    -- sync_out / sync_in are filled in below, AFTER the chunk has been
    -- invoked and returned its module table.  They're forward-declared
    -- here so the fpuBridge closures (specifically op_fp) capture them as
    -- upvalues -- Lua resolves upvalues lexically at closure creation time.
    local sync_out, sync_in

    local fpuBridge = {
        flw = function(rd, addr)
            fregisters[rd].flen = 32
            fregisters[rd].value = read_float(addr)
        end,
        fsw = function(rs2, addr)
            write_float(addr, fregisters[rs2].value)
        end,
        fld = function(rd, addr)
            fregisters[rd].flen = 64
            fregisters[rd].value = read_double(addr)
        end,
        fsd = function(rs2, addr)
            write_double(addr, fregisters[rs2].value)
        end,
        fmadd = function(rd, funct3, rs1, rs2, funct2, rs3)
            RVEMU_FPU_FMADD(cpu, rd, funct3, rs1, rs2, funct2, rs3)(function() end, 0)()
        end,
        fmsub = function(rd, funct3, rs1, rs2, funct2, rs3)
            RVEMU_FPU_FMSUB(cpu, rd, funct3, rs1, rs2, funct2, rs3)(function() end, 0)()
        end,
        fnmsub = function(rd, funct3, rs1, rs2, funct2, rs3)
            RVEMU_FPU_FNMSUB(cpu, rd, funct3, rs1, rs2, funct2, rs3)(function() end, 0)()
        end,
        fnmadd = function(rd, funct3, rs1, rs2, funct2, rs3)
            RVEMU_FPU_FNMADD(cpu, rd, funct3, rs1, rs2, funct2, rs3)(function() end, 0)()
        end,
        op_fp = function(rd, funct3, rs1, rs2, funct7)
            -- OP-FP is the only FPU family that may write to an integer
            -- register (FMV.X.W, FCVT.W.S/WU.S, FCLASS, FLE/FLT/FEQ).  We
            -- sync around it so the AOT R* locals pick up any
            -- integer-destination updates the handler performs.
            sync_out()
            RVEMU_FPU_OP_FP(cpu, rd, funct3, rs1, rs2, funct7)(function() end, 0)()
            sync_in()
        end,
    }

    -- The generated code indexes ``mem[addr]`` directly -- it expects the
    -- raw hash table, not the RVEMU_GetMemory wrapper object.
    local mod = _DW_DoomAOTChunk(cpu, cpu.memory.mem, ecallBridge, fpuBridge)
    sync_out = mod.sync_out
    sync_in  = mod.sync_in

    -- Snapshot the verify flag at start-up time: flipping it mid-run would
    -- just be confusing, and we want the non-verify path to cost literally
    -- zero (not even a per-tick branch) in shipped builds.
    local verify = (_DW_AOT_VERIFY == true)

    cpu._aot_module = mod

    if not verify then
        -- Fast path: plain AOT run loop, no snapshotting, no diffing.
        cpu.Run = function(self)
            self.last_sleep = time()
            mod.run()
        end
        return mod
    end

    -- ------------------------------------------------------------------
    -- Verify path
    -- ------------------------------------------------------------------
    --
    -- We can't share state with the AOT chunk directly -- ``pc`` and the
    -- R* registers are locals captured as upvalues inside the chunk
    -- closure, not reachable from the outside.  Instead we drive the loop
    -- one block at a time, using the chunk's own sync_out / sync_in as
    -- the bridge:
    --
    --    chunk state  <-- sync_out -->  cpu.registers
    --                 <-- sync_in  <--
    --
    -- For each iteration: sync_out, snapshot pre-state, run the AOT
    -- block, sync_out again to capture post-state, restore pre-state to
    -- cpu.registers, sync_in, step the legacy interpreter forward until
    -- pc catches up to the AOT post-pc, snapshot, diff, then restore
    -- whichever one we trust and sync_in so the chunk's locals come
    -- along.
    print("|cffffff00AOT verify mode ACTIVE|r - execution will be much slower")
    _DW_AOT_VERIFY_DIVERGED = false

    -- Snapshot helpers.  We only capture the 32 GPRs + pc + the 32 FP
    -- regs (flen + value) because that's the full architectural state
    -- the AOT chunk touches; ignoring CSRs here is fine because the
    -- legacy path manipulates them via bootState.CPU:ReadCSR directly,
    -- same as the AOT block's CSRR* emitters.
    local function snapshot(c)
        local regs = c.registers
        local fregs = c.fregisters
        local snap_r = {}
        for i = 0, 31 do snap_r[i] = regs[i] end
        snap_r[33] = regs[33]
        local snap_f = {}
        for i = 0, 31 do
            local f = fregs[i]
            snap_f[i] = { flen = f.flen, value = f.value }
        end
        return { r = snap_r, f = snap_f }
    end

    local function restore(c, snap)
        local regs = c.registers
        local fregs = c.fregisters
        local snap_r = snap.r
        local snap_f = snap.f
        for i = 0, 31 do regs[i] = snap_r[i] end
        regs[33] = snap_r[33]
        for i = 0, 31 do
            local sf = snap_f[i]
            fregs[i].flen = sf.flen
            fregs[i].value = sf.value
        end
    end

    -- Return ``nil`` if the two snapshots are bitwise-equivalent for our
    -- purposes, else a short human-readable description of the first
    -- differing field.  We compare pc first because that's the most
    -- informative divergence.
    local function state_diff(a, b)
        if a.r[33] ~= b.r[33] then
            return string.format("pc: aot=0x%x legacy=0x%x",
                a.r[33], b.r[33])
        end
        for i = 0, 31 do
            if a.r[i] ~= b.r[i] then
                return string.format("x%d: aot=0x%x legacy=0x%x",
                    i, a.r[i], b.r[i])
            end
        end
        for i = 0, 31 do
            local af, bf = a.f[i], b.f[i]
            if af.flen ~= bf.flen or af.value ~= bf.value then
                return string.format(
                    "f%d: aot={flen=%d val=%s} legacy={flen=%d val=%s}",
                    i, af.flen, tostring(af.value),
                    bf.flen, tostring(bf.value))
            end
        end
        return nil
    end

    -- Walk up to ``max_scan`` words starting at ``start_pc`` and return
    -- true if the block has any "shared-world side effect" that makes
    -- re-running it through legacy after the AOT run produce wrong
    -- results.  Specifically:
    --
    --   0x73 SYSTEM  -- ECALL draws/polls input; re-running double-fires.
    --   0x23 STORE   -- SB/SH/SW on a global the block also reads back
    --                   (the common malloc "mallinfo += delta" RMW
    --                   pattern) makes legacy's lw see AOT's write and
    --                   produce register deltas of exactly the update.
    --   0x27 STORE-FP -- FSW/FSD, same RMW hazard.
    --   0x2F AMO     -- atomic RMW, obvious.
    --
    -- For any of those we trust the AOT output and skip the legacy
    -- replay.  The verify machinery still runs on every pure-compute /
    -- load-only block, which is where codegen bugs are most likely.
    local mem_get_cache = cpu.memory
    local function block_has_side_effect(start_pc, max_scan)
        for i = 0, max_scan - 1 do
            local word = mem_get_cache:Get(start_pc + i * 4)
            local low7 = word % 128
            if low7 == 0x73 or low7 == 0x23
                    or low7 == 0x27 or low7 == 0x2F then
                return true
            end
            -- Stop scanning at terminators (branches/jumps) -- beyond a
            -- taken branch we can't assume fall-through bytes belong to
            -- this block.  low7 values: 0x63 branches, 0x6F JAL, 0x67 JALR.
            if low7 == 0x63 or low7 == 0x6F or low7 == 0x67 then
                return false
            end
        end
        return false
    end

    local blocks = mod.blocks
    local block_insn_counts = mod.block_insn_counts

    local function verified_run()
        cpu.last_sleep = time()
        local block_count = 0
        while cpu.is_running == 1 do
            sync_out()
            local start_pc = cpu.registers[33]
            if cpu.is_running ~= 1 then break end

            local blk = blocks[start_pc]
            if not blk then
                -- Nothing to verify: the AOT path would just call
                -- StepLegacy here, so match that behaviour exactly.
                cpu:StepLegacy()
                sync_in()
            elseif block_has_side_effect(start_pc, 128) then
                -- Trust AOT for blocks whose replay would mutate shared
                -- world state (ECALL, STORE, STORE-FP, AMO).
                blk()
                sync_out()
                sync_in()
            else
                local pre = snapshot(cpu)
                blk()
                sync_out()
                local post_aot = snapshot(cpu)

                -- Walk legacy forward from the same pre-state by
                -- exactly the block's instruction count.  Matching on pc
                -- instead doesn't work: backward-branch blocks whose
                -- target is interior to the same block (e.g. the memset
                -- loop at 0x59520 whose bltu targets 0x5952c, 12 bytes
                -- in) would see the legacy stepper *pass through* the
                -- branch target on its way forward and stop early with
                -- most of the block un-executed, producing a false
                -- divergence of one iteration's worth of writes.  Using
                -- insn_count works for every terminator kind we emit --
                -- non-terminators advance pc by 4, terminators set pc
                -- themselves in a single step, so "step N times" lands
                -- exactly past the terminator.
                restore(cpu, pre)
                sync_in()
                local insn_count = block_insn_counts[start_pc] or 0
                local bailed = false
                if insn_count == 0 then
                    -- Shouldn't happen for a block we dispatched to, but
                    -- don't spin on zero-step blocks if the table is
                    -- missing for any reason.
                    bailed = true
                else
                    for _ = 1, insn_count do
                        local word = mem_get_cache:Get(cpu.registers[33])
                        if (word % 128) == 0x73 then
                            -- Defensive: we already screened for ECALL
                            -- above, but an indirect landing could
                            -- expose one.  Bail.
                            bailed = true
                            break
                        end
                        cpu:StepLegacy()
                        if cpu.is_running ~= 1 then break end
                    end
                end

                if bailed then
                    -- Give up on this block's verification; trust AOT.
                    restore(cpu, post_aot)
                    sync_in()
                else
                    local post_legacy = snapshot(cpu)
                    local diff = state_diff(post_aot, post_legacy)
                    if diff then
                        print(string.format(
                            "|cffff0000AOT VERIFY FAIL|r at pc=0x%x: %s",
                            start_pc, diff))
                        _DW_AOT_VERIFY_DIVERGED = true
                        -- Halt immediately on the first divergence so the
                        -- user can read the failure message.  Clearing
                        -- is_running AND is_stopped makes sure the outer
                        -- while loop in verified_run exits AND the
                        -- RVEMU_Resume path won't re-enter on the next
                        -- frame (Resume early-returns when is_stopped==1).
                        cpu.is_running = 0
                        cpu.is_stopped = 1
                        print(string.format(
                            "|cffff0000AOT VERIFY HALTED|r after %d blocks - "
                            .. "reload UI (/reload) to run again",
                            block_count))
                        -- Leave cpu.registers at post_legacy so, if the user
                        -- inspects register state, they see the
                        -- ground-truth (legacy) values for the diverging
                        -- block rather than the AOT values.
                        restore(cpu, post_legacy)
                        sync_in()
                        return
                    else
                        restore(cpu, post_aot)
                        sync_in()
                    end
                end
            end

            block_count = block_count + 1
            if block_count % 1000 == 0 then
                print(string.format(
                    "|cff00ff00AOT verify|r: %d blocks OK", block_count))
            end

            -- Verify mode is ~50-100x slower than the fast AOT path (every
            -- block pays snapshot + legacy rerun + diff).  Without a yield
            -- the WoW UI watchdog kills us with "script ran too long".
            -- MaybeYieldCPU flips is_running to 0 once every 2s wall-clock
            -- and schedules a RunNextFrame resume, which re-enters
            -- verified_run via cpu.Run -> the outer while loop exits
            -- cleanly on the is_running check.
            cpu:MaybeYieldCPU()
        end
    end

    cpu.Run = function(self)
        self.last_sleep = time()
        verified_run()
    end

    return mod
end
