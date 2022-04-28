-- require('mobdebug').start()
local Object = require('core').Object
local ffi = require("ffi")
local uv = require("uv")
local serial = require 'serial'
local SerialPort = Object:extend()
-- local C = ffi.C

function SerialPort:initialize(option)
    if option.port == nil then
        local err = "option.port is nil"
        return err
    end
    self.port = option.port
    self.baud = option.baud or 9600
    self.parity = option.parity or 'N'
    self.data_bits = option.data_bits or 8
    self.stop_bits = option.stop_bits or 1
    self.timeout = option.timeout or 1000
    self.char_timeout = option.char_timeout or 10
    self.is_rs485 = option.is_rs485 or 0
    self.parity = string.upper(self.parity)
    self.min_char_timeout = option.min_char_timeout or 10
    self.timer = uv.new_timer()
    self.name = string.format("%s:%d,%s,%d,%d", self.port, self.baud, self.parity, self.data_bits, self.stop_bits)
    -- self.protocol = option.protocol or "ModBus" --协议名称
    -- self.pro_att = {} --协议具体
end

function SerialPort:open()
    self.name = string.format("%s:%d,%s,%d,%d", self.port, self.baud, self.parity, self.data_bits, self.stop_bits)
    local fd = serial.open(self.port, self.baud, self.parity, self.data_bits, self.stop_bits)
    if fd <= 0 then
        local err = serial.strerror(fd)
        return string.format("open %s err:%s", self.port, err)
    end
    -- serial.setTimeOuts(fd,self.char_timeout,1,self.timeout,1,1)
    self.fd = fd
    self.poll = uv.new_poll(fd) -- 非阻塞式
end

function SerialPort:write(txdata, len)
    local buf, length
    if type(txdata) == 'cdata' then
        length = len
        buf = ffi.string(txdata, length)
    elseif type(txdata) == 'table' and txdata.ctype ~= nil then
        length = len or txdata.length
        buf = ffi.string(txdata.ctype, length)
    elseif type(txdata) == 'string' then
        length = len or #txdata
        buf = txdata
    else
        print("Input must be a string or cdata")
        return -1
    end
    local ret = serial.write(self.fd, buf, length)
    --  local co = coroutine.running()
    --  uv.poll_start(self.poll, 'w', function()
    --      uv.timer_stop(self.timer)
    --      uv.poll_stop(self.poll)
    --	    return assert(coroutine.resume(co,ret))
    --  end)
    --  uv.timer_start(self.timer, self.timeout, 0, function ()
    --    uv.poll_stop(self.poll)
    --    uv.timer_stop(self.timer)
    --    return assert(coroutine.resume(co, -1))
    --  end)
    --  return coroutine.yield()
    return ret
end

function SerialPort:read(want_len, min_len)
    if type(want_len) ~= 'number' then
        want_len = 256
    end
    if type(min_len) ~= 'number' then
        min_len = 0
    end
    local co = coroutine.running()
    local chunk = {}
    local count = 1
    local rx_len = 0
    local char_timeout_cnt = 0
    uv.poll_start(self.poll, 'r', function()
        uv.timer_stop(self.timer)
        local ret, data = serial.read(self.fd, want_len)
        if ret > 0 then
            chunk[count] = data
            rx_len = rx_len + ret
            count = count + 1
        else
            return assert(coroutine.resume(co, ret))
        end
        if rx_len == want_len then
            uv.poll_stop(self.poll)
            return assert(coroutine.resume(co, rx_len, table.concat(chunk)))
        end
        uv.timer_again(self.timer)
    end)

    uv.timer_start(self.timer, self.timeout, self.char_timeout, function()
        uv.timer_stop(self.timer)
        if rx_len == 0 then
            uv.poll_stop(self.poll)
            return assert(coroutine.resume(co, -1))
        elseif rx_len < min_len and char_timeout_cnt < self.min_char_timeout then
            char_timeout_cnt = char_timeout_cnt + 1
            uv.timer_again(self.timer)
        else
            uv.poll_stop(self.poll)
            return assert(coroutine.resume(co, rx_len, table.concat(chunk)))
        end
    end)

    return coroutine.yield()
end

function SerialPort:close()
    serial.close(self.fd)
    self.fd = -1
end

return SerialPort
