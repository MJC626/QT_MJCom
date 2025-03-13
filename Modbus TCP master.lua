-- 可用函数:
-- send(text) - 发送ASCII文本
-- sendHex(text) - 发送16进制数据
-- sleep(ms) - 等待毫秒
-- print(text) - 输出到控制台
-- getLastData() - 获取最后接收的数据，返回二进制数据
-- setResponseTimeout(ms) - 设置响应超时时间

-- Modbus TCP 01/02/03/04功能码轮询脚本
-- 功能：轮询Modbus TCP设备的线圈、离散输入、保持寄存器和输入寄存器

-- 全局设置
local settings = {
    pollInterval = 100,     -- 轮询间隔(毫秒)
    responseTimeout = 1000,  -- 响应超时时间(毫秒)
}

-- 参数设置，每组可独立配置从站 ID、功能码、地址和个数
local poll_config = {
    {unit_id = 1, func_code = 0x03, start_addr = 0x0000, quantity = 10}, -- 读取从站1 保持寄存器
    {unit_id = 1, func_code = 0x04, start_addr = 0x0000, quantity = 10}  -- 读取从站1 输入寄存器
}

-- 获取功能码对应的名称
function get_func_name(func_code)
    local names = {
        [0x01] = "线圈状态",
        [0x02] = "离散输入",
        [0x03] = "保持寄存器",
        [0x04] = "输入寄存器"
    }
    return names[func_code] or "未知功能码"
end

function modbus_request(transaction_id, unit_id, func_code, start_addr, quantity)
    local header = string.format("%04X00000006", transaction_id) -- MBAP 头
    local pdu = string.format("%02X%02X%04X%04X", unit_id, func_code, start_addr, quantity)
    return header .. pdu
end

-- 辅助函数：将字节串转换为字节数组表
function string_to_bytes(str)
    local bytes = {}
    for i = 1, #str do
        bytes[i] = str:byte(i)
    end
    return bytes
end

function parse_response(response, func_code, start_addr)
    local func_name = get_func_name(func_code)
    
    if not response or response == "" then 
        print(func_name .. " 起始地址:0x" .. string.format("%04X", start_addr) .. " 无响应数据")
        return 
    end
    
    -- 直接使用字节串转换为字节数组
    local bytes = string_to_bytes(response)
    
    -- 检查是否有足够的字节用于基本解析
    if #bytes < 8 then
        print(func_name .. " 起始地址:0x" .. string.format("%04X", start_addr) .. " 响应数据过短")
        return
    end
    
    -- 检查协议标识符和长度
    local protocol_id = (bytes[3] * 256) + bytes[4]
    local length = (bytes[5] * 256) + bytes[6]
    
    -- 验证单元标识符
    local unit_id = bytes[7]
    
    -- 检查功能码
    local resp_func_code = bytes[8]
    if resp_func_code ~= func_code then
        if resp_func_code == (func_code + 0x80) then
            -- 异常响应
            if #bytes >= 9 then
                print(func_name .. " 起始地址:0x" .. string.format("%04X", start_addr) .. " 异常:0x" .. string.format("%02X", bytes[9]))
            else
                print(func_name .. " 起始地址:0x" .. string.format("%04X", start_addr) .. " 异常响应")
            end
        else
            print(func_name .. " 起始地址:0x" .. string.format("%04X", start_addr) .. " 功能码不匹配")
        end
        return
    end
    
    -- 获取数据字节数
    if #bytes < 9 then
        print(func_name .. " 起始地址:0x" .. string.format("%04X", start_addr) .. " 响应数据不完整")
        return
    end
    
    local byte_count = bytes[9]
    
    -- 检查数据完整性
    if #bytes < 9 + byte_count then
        print(func_name .. " 起始地址:0x" .. string.format("%04X", start_addr) .. " 数据长度不匹配")
        return
    end
    
    -- 从这里开始解析数据
    local output = func_name .. " 起始地址:0x" .. string.format("%04X", start_addr) .. " 值:"
    
    if func_code == 0x01 or func_code == 0x02 then
        -- 解析线圈状态或输入状态
        local states = {}
        local point_count = math.min(byte_count * 8, 10) -- 限制为请求的数量
        
        for i = 0, point_count - 1 do
            local byte_index = math.floor(i / 8) + 1
            local bit_index = i % 8
            local byte_value = bytes[9 + byte_index]
            
            if byte_value then
                local bit_value = bit.band(bit.rshift(byte_value, bit_index), 1)
                table.insert(states, bit_value)
            end
        end
        
        output = output .. table.concat(states, ",")
        print(output)
        
    elseif func_code == 0x03 or func_code == 0x04 then
        -- 解析保持寄存器或输入寄存器
        local reg_count = byte_count / 2
        local values = {}
        
        for i = 0, reg_count - 1 do
            local high_byte = bytes[10 + i * 2]
            local low_byte = bytes[11 + i * 2]
            
            if high_byte and low_byte then
                local reg_value = (high_byte * 256) + low_byte
                table.insert(values, string.format("%d", reg_value))
            end
        end
        
        output = output .. table.concat(values, ",")
        print(output)
    end
end

-- 初始化函数
function init()
    print("初始化Modbus TCP轮询脚本...")
    print("轮询间隔: " .. settings.pollInterval .. "ms")
    print("响应超时: " .. settings.responseTimeout .. "ms")
    
    -- 设置响应超时时间
    setResponseTimeout(settings.responseTimeout)
    
    -- 显示轮询配置
    for i, cfg in ipairs(poll_config) do
        print(string.format("轮询配置 #%d: 从站ID=%d, 功能码=0x%02X(%s), 起始地址=0x%04X, 数量=%d", 
            i, cfg.unit_id, cfg.func_code, get_func_name(cfg.func_code), cfg.start_addr, cfg.quantity))
    end
end

-- ========== 主循环 ==========
-- 初始化
init()

local transaction_id = 1
while true do
    for _, cfg in ipairs(poll_config) do
        local request = modbus_request(transaction_id, cfg.unit_id, cfg.func_code, cfg.start_addr, cfg.quantity)
        sendHex(request)
        
        -- 使用设置中的超时时间
        sleep(settings.responseTimeout) 

        local response = getLastData() -- 获取响应数据
        parse_response(response, cfg.func_code, cfg.start_addr)

        transaction_id = (transaction_id + 1) % 65536 -- 事务 ID 递增
        sleep(settings.pollInterval) --轮询间隔
    end
end