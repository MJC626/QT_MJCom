-- Modbus RTU 01/02/03/04功能码轮询脚本
-- 功能：轮询Modbus RTU设备的线圈、离散输入、保持寄存器和输入寄存器

-- 可用函数:
-- send(text) - 发送ASCII文本
-- sendHex(text) - 发送16进制数据
-- sleep(ms) - 等待毫秒
-- print(text) - 输出到控制台
-- getLastData() - 获取最后接收的数据，返回二进制数据
-- setResponseTimeout(ms) - 设置响应超时时间

-- 参数设置，每组可独立配置从站 ID、功能码、地址和个数
local poll_config = {
    {unit_id = 1, func_code = 0x03, start_addr = 0x0000, quantity = 10}, -- 读取从站1 保持寄存器
    {unit_id = 1, func_code = 0x04, start_addr = 0x0000, quantity = 10}  -- 读取从站1 输入寄存器
}

-- 全局设置
local settings = {
    pollInterval = 100,     -- 轮询间隔(毫秒)
    responseTimeout = 1000  -- 响应超时时间(毫秒)
}

-- CRC16校验码计算
function calculateCRC16(data)
    local crc = 0xFFFF
    for i = 1, #data do
        crc = crc ~ data:byte(i)
        for j = 1, 8 do
            if (crc & 0x0001) ~= 0 then
                crc = crc >> 1
                crc = crc ~ 0xA001
            else
                crc = crc >> 1
            end
        end
    end
    -- 先返回低字节，再返回高字节
    return string.char(crc & 0xFF, (crc >> 8) & 0xFF)
end

-- 将十进制转换为16进制字符串显示
function toHexString(data)
    local result = ""
    for i = 1, #data do
        result = result .. string.format("%02X ", data:byte(i))
    end
    return result
end

-- 将十进制转换为16进制格式显示地址
function toHexAddr(value)
    return string.format("0x%04X", value)
end

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

-- 创建Modbus RTU请求
function modbus_request(unit_id, func_code, start_addr, quantity)
    -- 验证功能码
    if func_code < 1 or func_code > 4 then
        print("错误: 无效的功能码，必须是1、2、3或4")
        return nil
    end
    
    -- 构建请求(从站ID + 功能码 + 地址 + 数量)
    local request = string.char(unit_id, func_code)
    -- 添加地址(2字节，大端序)
    request = request .. string.char((start_addr >> 8) & 0xFF, start_addr & 0xFF)
    -- 添加数量(2字节，大端序)
    request = request .. string.char((quantity >> 8) & 0xFF, quantity & 0xFF)
    -- 添加CRC(2字节)
    request = request .. calculateCRC16(request)
    
    return request
end

-- 辅助函数：将字节串转换为字节数组表
function string_to_bytes(str)
    local bytes = {}
    for i = 1, #str do
        bytes[i] = str:byte(i)
    end
    return bytes
end

-- 解析Modbus RTU响应
function parse_response(response, func_code, start_addr)
    local func_name = get_func_name(func_code)
    
    if not response or response == "" then
        print(func_name .. " 起始地址:" .. toHexAddr(start_addr) .. " 无响应数据")
        return
    end
    
    -- 直接使用字节串转换为字节数组
    local bytes = string_to_bytes(response)
    
    -- 检查是否有足够的字节用于基本解析
    if #bytes < 3 then
        print(func_name .. " 起始地址:" .. toHexAddr(start_addr) .. " 响应数据过短")
        return
    end
    
    -- 检查功能码
    local resp_func_code = bytes[2]
    if resp_func_code ~= func_code then
        if resp_func_code == (func_code + 0x80) then
            -- 异常响应
            if #bytes >= 3 then
                print(func_name .. " 起始地址:" .. toHexAddr(start_addr) .. " 异常:0x" .. string.format("%02X", bytes[3]))
            else
                print(func_name .. " 起始地址:" .. toHexAddr(start_addr) .. " 异常响应")
            end
        else
            print(func_name .. " 起始地址:" .. toHexAddr(start_addr) .. " 功能码不匹配")
        end
        return
    end
    
    -- 获取数据字节数
    local byte_count = bytes[3]
    
    -- 检查数据完整性
    if #bytes < 3 + byte_count then
        print(func_name .. " 起始地址:" .. toHexAddr(start_addr) .. " 数据长度不匹配")
        return
    end
    
    -- 从这里开始解析数据
    local output = func_name .. " 起始地址:" .. toHexAddr(start_addr) .. " 值:"
    
    if func_code == 0x01 or func_code == 0x02 then
        -- 解析线圈状态或输入状态
        local states = {}
        for i = 4, 3 + byte_count do
            local byte = bytes[i]
            for bit = 0, 7 do
                table.insert(states, (byte & (1 << bit)) ~= 0 and "1" or "0")
            end
        end
        output = output .. table.concat(states, ",")
        print(output)
        
    elseif func_code == 0x03 or func_code == 0x04 then
        -- 解析保持寄存器或输入寄存器
        local values = {}
        for i = 4, 3 + byte_count, 2 do
            if i + 1 <= 3 + byte_count then
                local high = bytes[i]
                local low = bytes[i + 1]
                local value = (high << 8) | low
                table.insert(values, string.format("%d", value))
            end
        end
        output = output .. table.concat(values, ",")
        print(output)
    end
end

-- 轮询一个配置
function poll_modbus_config(config)
    -- 创建请求
    local request = modbus_request(
        config.unit_id,
        config.func_code,
        config.start_addr,
        config.quantity
    )
    
    if request == nil then
        return
    end
    
    -- 发送请求
    sendHex(toHexString(request))
    
    -- 等待响应
    sleep(settings.responseTimeout)
    
    -- 获取响应
    local response = getLastData()
    
    -- 解析响应
    parse_response(response, config.func_code, config.start_addr)
end

-- 初始化函数
function init()
    print("初始化Modbus RTU轮询脚本...")
    print("轮询间隔: " .. settings.pollInterval .. "ms")
    print("响应超时: " .. settings.responseTimeout .. "ms")
    
    -- 设置响应超时时间
    setResponseTimeout(settings.responseTimeout)
    
    -- 显示轮询配置
    for i, cfg in ipairs(poll_config) do
        print(string.format("轮询配置 #%d: 从站ID=%d, 功能码=0x%02X(%s), 起始地址=%s, 数量=%d", 
            i, cfg.unit_id, cfg.func_code, get_func_name(cfg.func_code), toHexAddr(cfg.start_addr), cfg.quantity))
    end
end

-- ========== 主循环 ==========
-- 初始化
init()

while true do
    for _, cfg in ipairs(poll_config) do
        poll_modbus_config(cfg)
        sleep(settings.pollInterval) -- 轮询间隔
    end
end