-- Modbus TCP 01/02/03/04功能码轮询脚本
-- 功能：轮询Modbus TCP设备的线圈、离散输入、保持寄存器和输入寄存器

-- 可用函数:
-- send(text) - 发送ASCII文本
-- sendHex(text) - 发送16进制数据
-- sleep(ms) - 等待毫秒
-- print(text) - 输出到控制台
-- getLastData() - 获取最后接收的数据，返回二进制数据
-- setResponseTimeout(ms) - 设置响应超时时间

-- 数据格式类型定义
local DATA_FORMATS = {
    UINT16 = "UINT16",
    INT16 = "INT16", 
    HEX = "HEX",
    FLOAT_ABCD = "FLOAT_ABCD",
    FLOAT_BADC = "FLOAT_BADC",
    FLOAT_CDAB = "FLOAT_CDAB",
    FLOAT_DCBA = "FLOAT_DCBA",
    LONG_ABCD = "LONG_ABCD",
    LONG_BADC = "LONG_BADC",
    LONG_CDAB = "LONG_CDAB",
    LONG_DCBA = "LONG_DCBA"
}

-- 全局设置
local settings = {
    pollInterval = 100,     -- 轮询间隔(毫秒)
    responseTimeout = 100,  -- 响应超时时间(毫秒)
    decimalPlaces = 2       -- 浮点数小数位数
}

-- 参数设置，每组可独立配置从站 ID、功能码、地址和个数和数据格式
local poll_config = {
    {unit_id = 1, func_code = 0x03, start_addr = 0x0000, quantity = 10, format = DATA_FORMATS.UINT16},
    {unit_id = 1, func_code = 0x04, start_addr = 0x0000, quantity = 10, format = DATA_FORMATS.FLOAT_ABCD}
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

-- 解析UINT16
function parse_uint16(high_byte, low_byte)
    return (high_byte * 256) + low_byte
end

-- 解析INT16
function parse_int16(high_byte, low_byte)
    local value = (high_byte * 256) + low_byte
    if value >= 32768 then
        value = value - 65536
    end
    return value
end

-- 解析HEX
function parse_hex(high_byte, low_byte)
    return string.format("0x%02X%02X", high_byte, low_byte)
end

-- 解析浮点数
function parse_float(bytes, format)
    local b = {}
    if format == DATA_FORMATS.FLOAT_ABCD then
        b = {bytes[1], bytes[2], bytes[3], bytes[4]}
    elseif format == DATA_FORMATS.FLOAT_BADC then
        b = {bytes[2], bytes[1], bytes[4], bytes[3]}
    elseif format == DATA_FORMATS.FLOAT_CDAB then
        b = {bytes[3], bytes[4], bytes[1], bytes[2]}
    elseif format == DATA_FORMATS.FLOAT_DCBA then
        b = {bytes[4], bytes[3], bytes[2], bytes[1]}
    end
    
    local bits = b[1]*16777216 + b[2]*65536 + b[3]*256 + b[4]
    local sign = (bits & 0x80000000) ~= 0
    local exp = (bits >> 23) & 0xFF
    local frac = bits & 0x7FFFFF
    
    if exp == 0 then
        if frac == 0 then
            return sign and -0 or 0
        else
            exp = -126
        end
    elseif exp == 0xFF then
        if frac == 0 then
            return sign and -math.huge or math.huge
        else
            return 0/0
        end
    else
        exp = exp - 127
        frac = 1
    end
    
    for i = 22, 0, -1 do
        if (bits & (1 << i)) ~= 0 then
            frac = frac + 2^(i-23)
        end
    end
    
    local value = frac * 2^exp
    if sign then value = -value end
    return string.format("%." .. settings.decimalPlaces .. "f", value)
end

-- 解析长整型
function parse_long(bytes, format)
    local b = {}
    if format == DATA_FORMATS.LONG_ABCD then
        b = {bytes[1], bytes[2], bytes[3], bytes[4]}
    elseif format == DATA_FORMATS.LONG_BADC then
        b = {bytes[2], bytes[1], bytes[4], bytes[3]}
    elseif format == DATA_FORMATS.LONG_CDAB then
        b = {bytes[3], bytes[4], bytes[1], bytes[2]}
    elseif format == DATA_FORMATS.LONG_DCBA then
        b = {bytes[4], bytes[3], bytes[2], bytes[1]}
    end
    
    local value = b[1]*16777216 + b[2]*65536 + b[3]*256 + b[4]
    if value >= 2147483648 then
        value = value - 4294967296
    end
    return value
end

function parse_response(response, func_code, start_addr, format)
    local func_name = get_func_name(func_code)
    
    if not response or response == "" then 
        print(func_name .. " 起始地址:0x" .. string.format("%04X", start_addr) .. " 无响应数据")
        return 
    end
    
    local bytes = string_to_bytes(response)
    
    if #bytes < 8 then
        print(func_name .. " 起始地址:0x" .. string.format("%04X", start_addr) .. " 响应数据过短")
        return
    end
    
    local protocol_id = (bytes[3] * 256) + bytes[4]
    local length = (bytes[5] * 256) + bytes[6]
    local unit_id = bytes[7]
    local resp_func_code = bytes[8]
    
    if resp_func_code ~= func_code then
        if resp_func_code == (func_code + 0x80) then
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
    
    if #bytes < 9 then
        print(func_name .. " 起始地址:0x" .. string.format("%04X", start_addr) .. " 响应数据不完整")
        return
    end
    
    local byte_count = bytes[9]
    
    if #bytes < 9 + byte_count then
        print(func_name .. " 起始地址:0x" .. string.format("%04X", start_addr) .. " 数据长度不匹配")
        return
    end
    
    local output =func_name .. " 起始地址:0x" .. string.format("%04X", start_addr)
    
    if func_code == 0x01 or func_code == 0x02 then
        local states = {}
        local point_count = math.min(byte_count * 8, 10)
        
        for i = 0, point_count - 1 do
            local byte_index = math.floor(i / 8) + 1
            local bit_index = i % 8
            local byte_value = bytes[9 + byte_index]
            
            if byte_value then
                local bit_value = (byte_value >> bit_index) & 1
                table.insert(states, bit_value)
            end
        end
        
        output = output .. " 值:" .. table.concat(states, ",")
        print(output)
        
    elseif func_code == 0x03 or func_code == 0x04 then
        local values = {}
        local format_desc = ""
        
        if format == DATA_FORMATS.UINT16 then
            format_desc = "格式:16位无符号整数"
            for i = 0, (byte_count / 2) - 1 do
                local high_byte = bytes[10 + i * 2]
                local low_byte = bytes[11 + i * 2]
                if high_byte and low_byte then
                    table.insert(values, parse_uint16(high_byte, low_byte))
                end
            end
        elseif format == DATA_FORMATS.INT16 then
            format_desc = "格式:16位有符号整数"
            for i = 0, (byte_count / 2) - 1 do
                local high_byte = bytes[10 + i * 2]
                local low_byte = bytes[11 + i * 2]
                if high_byte and low_byte then
                    table.insert(values, parse_int16(high_byte, low_byte))
                end
            end
        elseif format == DATA_FORMATS.HEX then
            format_desc = "格式:16进制"
            for i = 0, (byte_count / 2) - 1 do
                local high_byte = bytes[10 + i * 2]
                local low_byte = bytes[11 + i * 2]
                if high_byte and low_byte then
                    table.insert(values, parse_hex(high_byte, low_byte))
                end
            end
        elseif format:find("FLOAT_") == 1 then
            format_desc = "格式:32位浮点数(" .. format:sub(7) .. ")"
            for i = 0, (byte_count / 4) - 1 do
                local float_bytes = {
                    bytes[10 + i * 4],
                    bytes[11 + i * 4],
                    bytes[12 + i * 4],
                    bytes[13 + i * 4]
                }
                if float_bytes[1] and float_bytes[2] and float_bytes[3] and float_bytes[4] then
                    table.insert(values, parse_float(float_bytes, format))
                end
            end
        elseif format:find("LONG_") == 1 then
            format_desc = "格式:32位长整数(" .. format:sub(6) .. ")"
            for i = 0, (byte_count / 4) - 1 do
                local long_bytes = {
                    bytes[10 + i * 4],
                    bytes[11 + i * 4],
                    bytes[12 + i * 4],
                    bytes[13 + i * 4]
                }
                if long_bytes[1] and long_bytes[2] and long_bytes[3] and long_bytes[4] then
                    table.insert(values, parse_long(long_bytes, format))
                end
            end
        end
        
        output = output .. " " .. format_desc .. " 值:" .. table.concat(values, ",")
        print(output)
    end
end

-- 初始化函数
function init()
    print("初始化Modbus TCP轮询脚本...")
    print("轮询间隔: " .. settings.pollInterval .. "ms")
    print("响应超时: " .. settings.responseTimeout .. "ms")
    print("浮点数小数位数: " .. settings.decimalPlaces)
    
    setResponseTimeout(settings.responseTimeout)
    
    for i, cfg in ipairs(poll_config) do
        print(string.format("轮询配置 #%d: 从站ID=%d, 功能码=0x%02X(%s), 起始地址=0x%04X, 数量=%d, 格式=%s", 
            i, cfg.unit_id, cfg.func_code, get_func_name(cfg.func_code), cfg.start_addr, cfg.quantity, cfg.format))
    end
end

-- 初始化
init()

local transaction_id = 1
while true do
    for _, cfg in ipairs(poll_config) do
        local request = modbus_request(transaction_id, cfg.unit_id, cfg.func_code, cfg.start_addr, cfg.quantity)
        sendHex(request)
        
        sleep(settings.responseTimeout) 

        local response = getLastData()
        parse_response(response, cfg.func_code, cfg.start_addr, cfg.format)

        transaction_id = (transaction_id + 1) % 65536
        sleep(settings.pollInterval)
    end
end
