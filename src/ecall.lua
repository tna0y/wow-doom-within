function _DW_HandleEcall(game)
    return function(CPU, syscall_num)
        local registers = CPU.registers
        if syscall_num == 93 then -- exit
            CPU.is_running = 0
            CPU.exit_code = registers[10]
            print(string.format("Got EXIT(%d)", CPU.exit_code))
        elseif syscall_num == 64 then -- write
            local s = ""
            local fd = registers[10]
            local buf = registers[11]
            local count = registers[12]
            for i = 0, count-1 do
                s = s .. string.char(CPU.memory:Read(1)(buf + i))
            end
            if fd == 1 then -- stdout
                print(s)
            elseif fd == 2 then -- stderr
                print("\124cffff0000" .. s .. "\124r")
            else
                --assert(false, "Unsupported fd")
            end
            CPU:StoreRegister(10, count)
            CPU.is_running = 0
            RunNextFrame(function() RVEMU_Resume(CPU) end)
        elseif syscall_num == 101 then -- togglewindow
            -- noop
            
        elseif syscall_num == 102 then -- render_framebuffer
            game.frame:RenderFrame(game.framebuffer)
            
            game.frame_cnt = game.frame_cnt + 1
            if game.frame_cnt >= 50 then
                local t = GetTime()
                print(string.format("Rendered 50 frames. Average FPS: %f", game.frame_cnt/(t - game.frame_start_time) ))
                game.frame_cnt = 0
                game.frame_start_time = t
            end

            CPU.is_running = 0
            RunNextFrame(function() RVEMU_Resume(CPU) end)
        elseif syscall_num == 103 then -- get_key_state
            -- print("get_key_state was called")
            local key = registers[10]
            if game.pressed_keys[key] or game.sticky_keys[key] then
                game.sticky_keys[key] = false
                CPU:StoreRegister(10, 1)
            else
                CPU:StoreRegister(10, 0)
            end
        elseif syscall_num == 104 then -- sleep
            local msec = registers[10]
            CPU.is_running = 0
            C_Timer.After(msec / 1000, function() RVEMU_Resume(CPU) end)
        elseif syscall_num == 105 then -- draw_column
            -- void DG_DrawColumn(uint8_t* dest, uint8_t* dc_colormap, uint8_t* dc_source, int frac, int frac_step, int count) {
            local dest = registers[10]
            local dc_colormap = registers[11]
            local dc_source = registers[12]
            local frac = registers[13]
            local frac_step = registers[14]
            local count = registers[15]
            local framebuffer_base = registers[16]
            
            local framebuffer = game.framebuffer
            local write1 = CPU.memory:Write(1)
            local read1 = CPU.memory:Read(1)
            --do { ... } while (count--);
            for i=count,0,-1 do
            -- *dest = dc_colormap[dc_source[(frac>>FRACBITS)&127]];
                local source_idx = bit.rshift(frac, 16) % 0x80
                local colormap_idx =  read1(dc_source + source_idx)
                local pixel_value = read1(dc_colormap + colormap_idx)
                -- write1(dest, pixel_value)
                framebuffer[dest - framebuffer_base] = pixel_value
                dest = dest + 320;
                frac = frac + frac_step
            end

        elseif syscall_num == 106 then -- draw_span
            local dest = registers[10]
            local ds_colormap = registers[11]
            local ds_source = registers[12]
            local position = registers[13]
            local step = registers[14]
            local count = registers[15]
            local framebuffer_base = registers[16]

            local framebuffer = game.framebuffer
            local write1 = CPU.memory:Write(1)
            local read1 = CPU.memory:Read(1)
            
            for i = 0, count do
                local ytemp = bit.band(bit.rshift(position, 4), 0x0fc0)
                local xtemp = bit.rshift(position, 26)
                local spot = bit.bor(xtemp, ytemp)

                local source_val = read1(ds_source + spot)
                local val = read1(ds_colormap + source_val)
                -- write1(dest, val)
                framebuffer[dest - framebuffer_base] = val
                dest = dest + 1
                position = position + step
            end
        elseif syscall_num == 107 then -- draw_patch
            local col = registers[10]
            local is_screen_buffer = registers[11]
            local x = registers[12]
            local desttop = registers[13]
            local source = registers[14]
            local m_col = registers[15]
            local m_patch = registers[16]

            local framebuffer_base = registers[31] -- t6

            local framebuffer = game.framebuffer
            local write1 = CPU.memory:Write(1)
            local read1 = CPU.memory:Read(1)
            local read2 = CPU.memory:Read(2)
            local read4 = CPU.memory:Read(4)

            local w = read2(m_patch)
            local count
            local dest
            -- assert(w == read2(m_patch), "w is not equal to read2(m_patch)")
            while col < w do
                m_col = m_patch + read4(m_patch + 8 + col * 4)
                while read1(m_col) ~= 0xff do
                    source = m_col + 3
                    dest = desttop + read1(m_col) * 320
                    count = read1(m_col + 1)
                    while count > 0 do
                        -- cant use direct framebuffer access here
                        -- because temporary framebuffer is sometimes as dest
                        if is_screen_buffer == 1 then
                            framebuffer[dest - framebuffer_base] = read1(source)
                        else
                            write1(dest, read1(source))
                        end

                        dest = dest + 320
                        source = source + 1
                        count = count - 1
                    end
                    m_col = m_col + read1(m_col + 1) + 4
                end
                col = col + 1
                x = x + 1
                desttop = desttop + 1
            end
        
        elseif syscall_num == 108 then -- copy_rect
            -- void DG_CopyRect(int srcx, int srcy, uint8_t *source, int width, int height, int destx, int desty) {
            --     #ifdef ENABLE_WOW_API
            --         asm volatile (
            --             "mv a0, %0\n"  
            --             "mv a1, %1\n"  
            --             "mv a2, %2\n"  
            --             "mv a3, %3\n"  
            --             "mv a4, %4\n"  
            --             "mv a5, %5\n"  
            --             "mv a6, %6\n"  
            --             "li a7, %7\n"  
            --             "ecall\n"      
            --             : 
            --             : "r" (srcx), "r" (srcy), "r" (source), "r" (width), "r" (height), "r" (destx), "r" (desty), "i" (SYS_WOW_copy_rect)  
            --             : "a0", "a1", "a2", "a3", "a4", "a5", "a6", "a7"  
            --         );
            --     #else
            --         src = source + SCREENWIDTH * srcy + srcx; 
            --         dest = dest_screen + SCREENWIDTH * desty + destx; 
            --         for ( ; height>0 ; height--) 
            --         { 
                        
            --             DG_memcpy(dest, src, width); 
            --             src += SCREENWIDTH; 
            --             dest += SCREENWIDTH; 
            --         }
            --     #endif
            --     }
            local srcx = registers[10]
            local srcy = registers[11]
            local source = registers[12]
            local width = registers[13]
            local height = registers[14]
            local destx = registers[15]
            local desty = registers[16]
            
            local framebuffer = game.framebuffer
            
            local src = source + 320 * srcy + srcx
            local dest = 320 * desty + destx
            local write1 = CPU.memory:Write(1)
            local read1 = CPU.memory:Read(1)
            for i = 0, height-1 do
                for j = 0, width-1 do
                    -- write1(dest + j, read1(src + j))
                    framebuffer[dest + j] = read1(src + j)
                end
                src = src + 320
                dest = dest + 320
            end



        elseif syscall_num == 109 then -- memcpy
            -- aligned writes are much faster
            -- implementing https://github.com/nxp-mcuxpresso/mcux-sdk/blob/675a70e9b9ea5de2177f8881c31f464e0cb30528/utilities/misc_utilities/fsl_memcpy.S
            local write1 = CPU.memory:Write(1)
            local write2 = CPU.memory:Write(2)
            local write4 = CPU.memory:Write(4)
            
            local read1 = CPU.memory:Read(1)
            local read2 = CPU.memory:Read(2)
            local read4 = CPU.memory:Read(4)

            local dst = registers[10]
            local src = registers[11]
            local n = registers[12]
            
            registers[10] = dst -- retval is always the same

            local tmp = 0

            if n == 0 then return end
            while src % 4 ~= 0 do
                write1(dst, read1(src))
                dst = dst + 1
                src = src + 1
                n = n - 1
                if n == 0 then return end
            end
            if dst % 4 == 0 then
                while n >= 16 do
                    write4(dst, read4(src))
                    write4(dst + 4, read4(src + 4))
                    write4(dst + 8, read4(src + 8))
                    write4(dst + 12, read4(src + 12))
                    dst = dst + 16
                    src = src + 16
                    n = n - 16
                end
                if n >= 8 then
                    write4(dst, read4(src))
                    write4(dst + 4, read4(src + 4))
                    dst = dst + 8
                    src = src + 8
                    n = n - 8
                end
                if n >= 4 then
                    write4(dst, read4(src))
                    dst = dst + 4
                    src = src + 4
                    n = n - 4
                end
                if n >= 2 then
                    write2(dst, read2(src))
                    dst = dst + 2
                    src = src + 2
                    n = n - 2
                end
                if n >= 1 then
                    write1(dst, read1(src))
                    dst = dst + 1
                    src = src + 1
                    n = n - 1
                end
            else
                if dst % 2 == 0 then
                    while n >= 4 do
                        tmp = read4(src)
                        src = src + 4
                        write2(dst, tmp % 0x10000)
                        dst = dst + 2
                        write2(dst, bit.rshift(tmp, 16))
                        dst = dst + 2
                        n = n - 4
                    end
                else
                    while n >= 4 do
                        tmp = read4(src)
                        src = src + 4
                        write1(dst, tmp % 0x100)
                        dst = dst + 1
                        write2(dst, bit.rshift(tmp, 8) % 0x10000)
                        dst = dst + 2
                        write1(dst, bit.rshift(tmp, 24))
                        dst = dst + 1
                        n = n - 4
                    end
                end
                while n > 0 do
                    write1(dst, read1(src))
                    dst = dst + 1
                    src = src + 1
                    n = n - 1
                end
            end

        elseif syscall_num == 80 then -- newfstat
            -- local stat_addr = registers[10]
            -- CPU.memory:Write(stat_addr + 32, 512, 4) -- stat.st_blksize = 512
        elseif syscall_num == 57 then -- fclose
            -- 
        elseif syscall_num == 214 then -- brk
            local addr = registers[10]
            if addr == 0 then
                CPU:StoreRegister(10, CPU.heap_start)
            else
                for x = CPU.heap_start, addr, 4 do
                    CPU.memory:Set(x, 0)
                end
                CPU:StoreRegister(10, addr)
                CPU.heap_start = addr
            end
        elseif syscall_num == 403 then -- clock_gettime
            local clock_id = registers[10]
            local struct_addr = registers[11]
            -- print("clock_gettime", clock_id)
            local dtime = debugprofilestop()
            local seconds = math.floor(dtime / 1000)
            local nanoseconds = math.floor((dtime % seconds) * 1000000)

            CPU.memory:Write(4)(struct_addr, seconds)
            CPU.memory:Write(4)(struct_addr + 8, bit.band(nanoseconds, 0xffffffff))
        else
            --assert(false, "syscall " .. tostring(syscall_num) .. " is not implemented")
        end
    end
end