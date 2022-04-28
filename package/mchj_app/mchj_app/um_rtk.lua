--require('mobdebug').start()
local Buffer = require('buffer').Buffer
local timer = require('timer')
local net = require('net')
local ffi = require("ffi")
local dgram = require('dgram')
local crc16 = require("crc16")
local base64 = require('base64')
--local miniz = require("miniz")
local t2n_client = require('t2n_client')
local nmea = require('nmea')
local coro_serial = require("coro-serial")
local coro_tcpclient = require('coro-tcp')

local JSON = require('json')
local http = require("http")
local wss = require('websocketServer')
local static = require('static')
local router = require('router')
local cors = require('http-cors')
--local log = require "log"  
local log = {print = print}
local din = 0

local lon_sum = 0
local lat_sum = 0
local alt_sum = 0
local sum_cnt = 0

local remote = {ip='127.0.0.1',port=9999}
local t2n = t2n_client:new(remote)

 local rtcm_outport
 local led_data_queue = {}
 local temps = {0,0,0,0}
 
 
ffi.cdef[[
  int open(const char *pathname, int flags);
  int close(int fd);
  int read(int fd, void *buf, size_t count);
  int write(int fd, void *buf, size_t count);
  int ioctl(int fd,unsigned long cmd,...);
  int lseek(int fd,int offset, int fromwhere);
  int *__errno_location (void);
  char *strerror (int __errnum);

  void *malloc (size_t __size);
  void free (void *__ptr);
]]

local Fflg = 
{
    -- open/fcntl - O_SYNC is only implemented on blocks devices and on files
    -- located on an ext2 file system */
    O_ACCMODE   = 0x0003,
    O_RDONLY    = 0x0000,
    O_WRONLY    = 0x0001,
    O_RDWR	    = 0x0002,
    O_APPEND    = 0x0008,
    O_SYNC	    = 0x0010,
    O_NONBLOCK	= 0x0080,
    O_NDELAY	= 0x0080, --O_NONBLOCK
    O_CREAT		= 0x0100,	--/* not fcntl */
    O_TRUNC		= 0x0200,	--/* not fcntl */
    O_EXCL		= 0x0400,	--/* not fcntl */
    O_NOCTTY	= 0x0800,	--/* not fcntl */
    O_FSYNC		= 0x0010, --O_SYNC
    O_ASYNC		= 0x1000,
    --/* Values for the second argument to `fcntl'.  */
    F_DUPFD	= 0,    --	/* Duplicate file descriptor.  */
    F_GETFD	= 1,    --	1	/* Get file descriptor flags.  */
    F_SETFD	= 2,    --	2	/* Set file descriptor flags.  */
    F_GETFL	= 3,    --	3	/* Get file status flags.  */
    F_SETFL	= 4,	-- 4	/* Set file status flags.  */
}

 function Buffer:write(offset, v, length)
  if type(offset) ~= "number" or  offset < 1 or offset > self.length then error("Index out of bounds") end
  if type(v) == 'string' then
    length = length or #v
    ffi.copy(self.ctype+offset-1,v,length)
  elseif type(v) == 'cdata' then
    if length > 0 then
      ffi.copy(self.ctype+offset-1,v,length)
    else
      error("[Buffer:write] ctype must give length")
    end
  elseif v.ctype ~= nil and v.length ~= nil then  --Buffer
    length = length or v.length
    ffi.copy(self.ctype+offset-1,v.ctype,length)
  else
    error("[Buffer:write] Input must be a string or cdata or Buffer")
    return
  end
end

 function Buffer:copy(target,targetStart,sourceStart, sourceEnd)
  ffi.copy(target.ctype+targetStart-1,self.ctype+sourceStart-1,sourceEnd-sourceStart+1)
end

 local function ubx_ck(buf,length)
  local ck_a = 0
  local ck_b = 0
  for i=3,length do
    ck_a = ck_a + buf[i]
    ck_b = ck_b + ck_a
  end
  return bit.band(ck_a,255),bit.band(ck_b,255)
end

-- ==========================================================================ublox start

local gps_data = {gpstime=0,lat=0,lon=0, alt=0, status=0,speed=0,direction=0}

local ublox_com = coro_serial:new({port = ffi.os == "Windows" and "\\\\.\\COM15" or "/dev/ttyHS0",baud =115200,char_timeout=10})

function ubx_unpack(buf,length)
  
end

--function get_line(offset,buf1,buf2)
--  local buf = Buffer:new(1024)
--  local idx = 0
--  local done = false
--  local pos = offset
--  local buffers = {buf1,buf2}
--  for i,str in ipairs(buffers) do
--    while pos < #str do
--      local b = string.byte(str,pos)
--      if b ~= 0x0a and idx < 1024 then
--        idx = idx + 1
--        buf[idx] = b
--      elseif idx < 1024 then
--        done = true
--        break
--      else
--        break
--      end
--      pos = pos + 1
--    end
--    if done then
--      return buf:toString(1,idx),pos+1
--    end
--    pos = 1
--  end
--  if done then
--    return buf:toString(1,idx),pos
--  else
--    return nil,offset
--  end
--end

function get_line(pos,buf,end_pos)
  --local buf = Buffer:new(1024)
  local idx = 0
  local done = false
  local offset = pos
  while pos < end_pos do
    if buf[pos] ~= 0x0a then
      pos = pos + 1
    else
      return buf:toString(offset,pos),pos
--      if buf[pos-1] == 0x0d then
--        return buf:toString(offset,pos-2),pos
--      else
--        return buf:toString(offset,pos-1),pos
--      end
    end
  end
  return
end
--function getbitu(buff, pos, len)
--  local bits = 0
--  local byte_len = math.ceil(len/8)
--  local index = bit.lshift(pos,3)
--  local offset = bit.band(pos,7)
--  local byte = string.byte(buff,index+1)
--  bits = bit.band(byte,111)
--  for i=1,byte_len-1 do
--    bits = bit.lshift(bits,8)
--    byte = string.byte(index+i+1)
--    if byte ~= nil then
--      bits = bits + byte
--    else
--      return nil
--    end
--  end
--  return bit.rshift(bits,11)
--end


 
--function rtcm_header_parse(header)
--  if #header < 5 then
--   return
--  end
--  local a,b,c,d,e = string.byte(header,1,5)
--  local length = bit.band(b,0x03)*256 + c
--  local type = d*16 + bit.rshift(e,4)
--  return type,length + 6
--end
function rtcm_header_parse(buf,offset)
  local b = buf[offset+1]
  local c = buf[offset+2]
  local d = buf[offset+3]
  local e = buf[offset+4]
  local length = bit.band(b,0x03)*256 + c
  local type = d*16 + bit.rshift(e,4)
  return type,length + 6
end

local rtcm_timeout = 25
local gga_req = 0
 
local function ublox_coro_body(dev)
  rtcm_outport = nil
	local err = dev:open()
	if err ~= nil then print(err) else
		print(string.format("open %s ok fd=%d",dev.name,dev.fd))
  end
  -- dev:write("RESET\r\n") 
  -- local ret,resp = dev:read() 
   while true do
     dev:write("version\r\n")
     ret,resp = dev:read()
     p('version',resp)
     if resp ~= nil then break end
     timer.sleep(1000)
   end
  dev:write("gprmc com1 0.2\r\n") 
  ret,resp = dev:read()
   dev:write("gpgga com1 0.2\r\n") 
   ret,resp = dev:read()


  -- dev:write("gphdt com1 0.2\r\n") 
  -- ret,resp = dev:read()
  dev:write("LOG HEADINGA ONTIME 0.2\r\n") 
  ret,resp = dev:read()

  rtcm_outport = dev
  local rxbuf = Buffer:new(8192)
  local pos = 1
  local end_pos = 1
  local last_msg_type 
  local rtcm_buf = Buffer:new(4096)
  local rtcm_idx = 1
  local nmea_buf = {}
  udp_sendtime = 0
	while true do
		len,resp = dev:read(4096)
    --local rxbuf = Buffer:new(resp)
    --print("rx pack",rxbuf:inspect())
    --p(resp) 
    if len > 0 then
      if end_pos + len > rxbuf.length then
        --p("out of rxbuf dddddddddddddddddddddddddddddddddddddddddddddddd")
        end_pos = 1
      end
      rxbuf:write(end_pos,resp,len)
      end_pos = end_pos + len
      pos = 1
      while pos < end_pos do
        --local sync_a,sync_b = rxbuf[pos]
        if rxbuf[pos] == 0x24 and rxbuf[pos+1] == 0x47 then -- $G nema ??
          local line,idx = get_line(pos,rxbuf,end_pos)
          if line == nil then
            break
          else
            -- p(line)
            -- if last_msg_type ~= "nema" then
            --   last_msg_type = "nema"
            --   if rtcm_idx > 1 then
            --     write_rtcm(rtcm_buf:toString(1,rtcm_idx))
            --     --local deflator = miniz.new_deflator(9)
            --     --local deflated, err, part = deflator:deflate(rtcm_buf:toString(1,rtcm_idx), "finish")
            --     --p("Compressed", rtcm_idx,#(deflated or part or ""))
            --     --local zrtcm = miniz.miniz_deflator()(rtcm_buf:toString(1,rtcm_idx),'finish')
            --     --write2clients(deflated)
            --     rtcm_idx = 1
            --   end
            -- end
            pos = idx + 1
            
            nmea.parse(line,gps_data)
            if string.find(line,"$GPRMC",1,7) == 1 or string.find(line,"$GPGGA",1,7) == 1 then
              table.insert(nmea_buf,line)
              if #nmea_buf >= 2 then
                local nmea = table.concat(nmea_buf)
                table.remove(nmea_buf,1)
                table.remove(nmea_buf,1)
               -- nmea_buf = {}
                write_nmea(nmea)
                --print(nmea)
              end
            end
            if string.find(line,"$GPGGA",1,7) == 1 and gps_data.lat ~= 0 and gps_data.lon ~= 0 then --last gps out
              --table.insert(nmea_buf,line)
              gps_gpgga = line
               local data_buf = Buffer:new(34)
              data_buf:writeUInt32LE(1,gps_data.gpstime)
              data_buf:writeUInt32LE(5,gps_data.lat)
              data_buf:writeUInt8(9,gps_data.lat/0x100000000)
              data_buf:writeUInt32LE(10,gps_data.lon)
              data_buf:writeUInt8(14,gps_data.lon/0x100000000)
              data_buf:writeUInt32LE(15,gps_data.alt)
              data_buf:writeUInt16LE(17,din)
              data_buf:writeUInt8(18,gps_data.status)
              data_buf:writeUInt16LE(19,gps_data.speed)
              data_buf:writeUInt16LE(21,gps_data.heading*100)
              data_buf:writeUInt16LE(23,gps_data.pitch*100)
              data_buf:writeUInt16LE(25,gps_data.length*1000)
              data_buf:writeUInt16LE(27,temps[1])
              data_buf:writeUInt16LE(29,temps[2])
              data_buf:writeUInt16LE(31,temps[3])
              data_buf:writeUInt16LE(33,temps[4])
              --p(data_buf:inspect())
              t2n:drp_write(12,2,data_buf,data_buf.length)
              p(gps_data)
              local obj = {
                lat = gps_data.lat/1000000000,
                lon = gps_data.lon/1000000000,
                hgt = gps_data.alt/1000,
                length = gps_data.length,
                heading = gps_data.heading,
                pitch = gps_data.pitch,
                status = gps_data.status
              }
              ws_send_broadcast({"GNS_DATA",obj})
              rtcm_timeout = rtcm_timeout + 1
              if rtcm_timeout > 30 or gga_req ~= 0 then
                t2n:drp_write(10,0,line,#line)
                rtcm_timeout = 0
                gga_req = 0
              end
              local speed = gps_data.speed/6
              if speed < 30 then
                speed = 0
              end
              table.insert(led_data_queue,{slave=1,addr=15,value={speed,0}})   
              if #led_data_queue > 2 then
                table.remove(led_data_queue,1)
              end
              lon_sum = lon_sum + gps_data.lon
              lat_sum = lat_sum + gps_data.lat
              alt_sum = alt_sum + gps_data.alt
              sum_cnt = sum_cnt + 1
              local k = sum_cnt*1000000000
              
              --p(string.format("lon=%.9f,lat=%.9f,alt=%.4f time=%d",lon_sum/k,lat_sum/k,alt_sum/(sum_cnt*1000),sum_cnt))
            end
          end
        elseif rxbuf[pos] == 0xd3 and bit.band(rxbuf[pos+1],0xfc) == 0 then  -- rtcm ??
          if end_pos-pos < 5 then
              break
          end
          local type,length = rtcm_header_parse(rxbuf,pos) 
          if end_pos-pos < length then
            break
          else
            if last_msg_type ~= "rtcm" then
              last_msg_type = "rtcm"
              rtcm_idx = 1
            end
            local end_idx = rtcm_idx + length
            if end_idx < rtcm_buf.length then
              rxbuf:copy(rtcm_buf,rtcm_idx,pos,pos+length)
              rtcm_idx = end_idx
            end
            pos = pos + length
            log.print(string.format("rtcm type=%d,length=%d",type,length))
--            if type == 1230 then  --last rtcm
--              if rtcm_idx > 1 then
--                write2clients(rtcm_buf:toString(1,rtcm_idx))
--                rtcm_idx = 1
--              end
--            end
          end
          elseif rxbuf[pos] == 0x23 and rxbuf[pos+1] == 0x48 then
            local line,idx = get_line(pos,rxbuf,end_pos)
            if line == nil then
              break
            else
              --p(line)
              local a,b,c = string.match(line,"SOL_COMPUTED,%w+_%w+,([+-]?%d+.%d+),([+-]?%d+.%d+),([+-]?%d+.%d+)")
              p(a,b,c)
              gps_data.length = tonumber(a) or 0
              gps_data.heading = tonumber(b) or 0
              gps_data.pitch = tonumber(c) or 0
              pos = idx + 1
            end
--          local packet, pos = ubx_unpack(pos,resp)
--          if packet == nil then
--            local ret1,resp1 = dev:read(4096)
--            packet, pos = ublox_parse(pos,resp,resp1)
--          end
--          if packet ~= nil then
--            p('ublox packet',packe:inspect())
--          end
--          local rxbuf = Buffer:new(string.sub(resp,pos,-1))
--          p('ublox frame',rxbuf:inspect())
        else
          p(string.format("no sync pos=%d,end_pos=%d,sync_a=%02x,sync_b=%02x",pos,end_pos,rxbuf[pos],rxbuf[pos+1]))
          pos = pos+1
        end
      end
    else
      p('read timeout')
    end
    if pos < end_pos then
      rxbuf:copy(rxbuf,1,pos,end_pos)
      end_pos = end_pos - pos + 1
    else
      end_pos = 1
    end
		--timer.sleep(20)
	end
end

local ublox_coro = coroutine.create(ublox_coro_body)
local ret,msg = coroutine.resume(ublox_coro,ublox_com)
if(ret ~= true) then log.print(msg) end
-- ==========================================================================ublox end

-- ==========================================================================modbus start
local temp_ids = {1,2}

function calc_sum(buf,length)
  local sum = 0
  for i= 1,length do
    sum = sum + buf[i]
  end
  return bit.band(sum,255)
end
function modbus_rtu_req(slave,regaddr,length)
  local txbuf = Buffer:new(8)
  txbuf:writeUInt8(1,slave)
  txbuf:writeUInt8(2,3)
  txbuf:writeUInt16BE(3,regaddr)
  txbuf:writeUInt16BE(5,length)
  local crc = crc16(txbuf,6)
  txbuf:writeUInt16BE(7,crc)
  return txbuf
end

function modbus_rtu_write(slave,addr,value)

  if type(value) == 'number' then
    local txbuf = Buffer:new(8)
    txbuf:writeUInt8(1,slave)
    txbuf:writeUInt8(2,6)
    txbuf:writeUInt16BE(3,addr)
    txbuf:writeUInt16BE(5,value)
    local crc = crc16(txbuf,6)
    txbuf:writeUInt16BE(7,crc)
    return txbuf
  elseif type(value) == 'table' then
      local buf_size = #value * 2 + 9
      local idx = 1
      local txbuf = Buffer:new(buf_size)
      txbuf:writeUInt8(1,slave)
      txbuf:writeUInt8(2,16)
      txbuf:writeUInt16BE(3,addr)
      txbuf:writeUInt16BE(5,#value)
      txbuf:writeUInt8(7,#value*2)
      idx = 8
      for i= 1,#value do
        txbuf:writeUInt16BE(idx,value[i])
        idx = idx + 2
      end
      local crc = crc16(txbuf,idx-1)
      txbuf:writeUInt16BE(idx,crc)
      return txbuf
  else
    log.print("value type err")
  end
end

function modbus_read_regs(dev,slave,addr,length)

  local txbuf = modbus_rtu_req(slave,addr,length)
  --log.print(txbuf:inspect())
  dev:write(txbuf)
  local ret,rxbuf = dev:read()
  if ret > 0 then
    --local resp2 = Buffer:new(rxbuf)
    --log.print('rx',#rxbuf,resp2:inspect())
    local low,hi = string.byte(rxbuf,#rxbuf-1,#rxbuf)
    local crc1 = crc16(rxbuf,ret-2)
    local crc2 = low * 256 + hi
    --log.print(crc1,crc1)
    if crc2 == crc1 then
      local regs = Buffer:new(length*2)
      for i=1,length*2,2 do
        hi,low = string.byte(rxbuf,i+3,i+4)
        --log.print(string.format("low=%02x,hi=%02x",low,hi))
        regs:writeUInt8(i,low)
        regs:writeUInt8(i+1,hi)
      end
      return length,regs
    else
      log.print(string.format("bad crc %04x,%04x",crc1,crc2))
      --p('bad crc',crc1,crc2)
      return -10
    end
  else
    return ret
  end
end
local led_card_option = {baud=9600,parity='N',timeout=500}
led_card_option.port = ffi.os == "Windows" and "COM6" or "/dev/ttyHSL1"
local led_comm = coro_serial:new(led_card_option)

local led_value = {0,0}
function led_coro_body(dev)
  local seq = 1
  local slave = 1
  local addr = 0
  local length = 10
  local is_ok
  local timeout_cnt = 0 
  local w_k= nil
  local step = 0
  p("sssssssssssssssssssssssssssssss")
  while true do
    log.print("start")
    os.execute("echo 1 > /sys/kernel/debug/regulator/ext_5v/enable")
    local cnt = 0
    local err = dev:open()
    if err ~= nil then
      log.print(err)
      is_ok = false
    else
      log.print(string.format("open %s ok",dev.name))
      is_ok = true
    end
    timeout_cnt = 0
    local has_init = true
    --local txbuf = Buffer:new(12)
    while is_ok do
      if has_init  then
        has_init = false
      end
      if #led_data_queue > 0 then
        local write = led_data_queue[1]
        --p(write)
        local txbuf = modbus_rtu_write(write.slave,write.addr,write.value,seq)
        --p(txbuf:inspect())
        dev:write(txbuf)
        local ret,rxbuf = dev:read()
        if ret < 0 then  --timeout
          --is_ok = false
        elseif ret == 0 then
          timeout_cnt = timeout_cnt + 1
          if timeout_cnt >= 20 then
            timeout_cnt = 0
            --is_ok = false
          end
        else
          timeout_cnt = 0
          local resp = Buffer:new(rxbuf)
          --log.print('rx',resp:inspect())
          table.remove(led_data_queue,1)
        end
      else
        timer.sleep(20)
      end
      timer.sleep(100)
      local txbuf = Buffer:new(5)
      for i = 1, #temp_ids do
        txbuf[1] = 0x54
        txbuf[2] = 0x50
        txbuf[3] = temp_ids[i]
        txbuf[4] = 0xF1
        txbuf[5] = calc_sum(txbuf,4)
        dev:write(txbuf)
        p("txbuf",txbuf:inspect())
        local len,rxbuf = dev:read(256)
        if len > 0 then
          timeout_cnt = 0
          local resp = Buffer:new(rxbuf)
          log.print('rssssssssssssx',resp:inspect())
          if resp[1] == 0x54 and resp[2] == 0x50 then
            local sum = calc_sum(resp,6)
            if sum == resp[7] then
              temp = bit.lshift(resp[5],8) + resp[6]
              --signal.tp1 = temp/10
              temps[i] = temp
              --p("temp",temp)
            end
          end
        end
        timer.sleep(100)
      end
      p("temps",temps)
    end

    log.print("close")
    dev:close()
    os.execute("echo 0 > /sys/kernel/debug/regulator/ext_5v/enable")
    timer.sleep(5000)
    log.print("restart")
  end
end

local led_coro = coroutine.create(led_coro_body)
local ret,msg = coroutine.resume(led_coro,led_comm)
if(ret ~= true) then log.print(msg) end


-- ==========================================================================modbus end

-- ==========================================================================nmea start
local nmea_clients = {}

local nmea_server = net.createServer(function(client)
  local addr = client:address()
  log.print(string.format("Client connected %s:%d" ,addr.ip ,addr.port))
  table.insert(nmea_clients,client)
  -- Add some listenners for incoming connection
  client:on("error",function(err)
    log.print("Client read error: " .. err)
    for i, c in ipairs(nmea_clients ) do
      if c == client then
        table.remove(nmea_clients, i)
        break
      end
    end
  end)

  client:on("data",function(data)
    --client:write(data)
  end)

  client:on("end",function()
    for i, c in ipairs( nmea_clients ) do
      if c == client then
        table.remove(nmea_clients, i)
        break
      end
    end
    local addr = client:address()
    log.print(string.format("Client disconnected %s:%d" ,addr.ip ,addr.port))
  end)
end)

 
nmea_server:on('error',function(err)
  if err then error(err) end
end)

nmea_server:listen(6061)  

function write_nmea(data)
  for i, c in ipairs(nmea_clients) do
--    local addr = c:address()
--     p(addr)
    if c ~= nil then
      c:write(data)
    end
  end
end
-- ==========================================================================nmea end

-- ==========================================================================rtcm start
t2n:drp_on_req(10,function(msg)
  p('drp rtcm revice',#msg)
  rtcm_timeout = 0
  if rtcm_outport ~= nil then
    rtcm_outport:write(msg,#msg)
  end
  --write_rtcm(msg)
end)

t2n:drp_on_req(11,function(msg)
  if msg == 'GGA_REQ' then
    gga_req = 1
  end
end)
local cors_cfg = 
{
    host= "203.107.45.154",
    --host = 'rtk.ntrip.qxwz.com',
    port= 8002,
    ntrip= true,
    mode = 'rover',
    --host = "192.168.11.2",
    --port = 6020,
 
    mountpoint="RTCM32_GGB",
    user= "qxphvy002",
    password= "2b26ade",
    --user = "qxphvy001",
    --password = "3b1add8" ,
    timeout = 15000
}

--local rtcm_option = {host="203.107.45.154",port=8002,timeout=15000}
local rtcm_option = {host="192.168.11.2",port=8002,timeout=15000}
local rtcm_client = coro_tcpclient:new(cors_cfg)

function rtcm_coro_body(dev)
  local seq = 1
  local slave = 1
  local addr = 0
  local length = 10
  local is_ok
  local timeout_cnt = 0
  local w_k= nil
  while gps_gpgga == nil do
    timer.sleep(1000)
    p('wait for gga')
  end
  while true do
    log.print("start rtcm_tcp_coro")
    local cnt = 0
    local err = dev:open()
    if err ~= nil then
      log.print(err)
      is_ok = false
    else
      log.print(string.format("open %s ok",dev.name))
      is_ok = true
    end
    if (cors_cfg.ntrip == true) then
      local headers = {}
      table.insert(headers, 'GET '..cors_cfg.mountpoint..' HTTP/1.1')
      table.insert(headers, 'Host: '..cors_cfg.host)
      table.insert(headers, 'Ntrip-Version: Ntrip/2.0')
      table.insert(headers, 'User-Agent: NTRIP u-blox')
      table.insert(headers, 'Accept: */*')
      local user_pwd = cors_cfg.user..':'..cors_cfg.password
      local basic = base64.encode(user_pwd)
      p(user_pwd,basic)
      table.insert(headers, 'Authorization: Basic '..basic)
      table.insert(headers, 'Connection: close')
      table.insert(headers, '\r\n')
      local req_str = table.concat( headers, "\r\n")
      print(req_str)
      dev:write(req_str)
      local ret,rxbuf = dev:read()
      if ret > 0 then
        p(rxbuf)
        if string.find(rxbuf,'200 OK') ~= nil then
            dev:write(gps_gpgga)
        else
          p(rxbuf)
        end
      else
        p('cros timeout')
      end

    end
    timeout_cnt = 0
    
    while is_ok do
      local ret,rxbuf = dev:read()
      --local buf = Buffer:new(rxbuf)
      --log.print(ret,buf:inspect())
      if ret < 0 then  --timeout
        is_ok = false
      elseif ret == 0 then
        timeout_cnt = timeout_cnt + 1 
        if timeout_cnt >= 3 then
          is_ok = false
        end
      else
        timeout_cnt = 0
        
        if rtcm_outport ~= nil then
          local len = rtcm_outport:write(rxbuf,ret)
          p('rtcm revice',ret,len)
        end
      end
    end
    log.print("rtcm_tcp close")
    dev:close()
    timer.sleep(5000)
    log.print("rtcm_tcp restart")
  end
end

-- local rtcm_co = coroutine.create(rtcm_coro_body)
-- local ret,msg = coroutine.resume(rtcm_co,rtcm_client)
-- if(ret ~= true) then log.print(msg) end

-- ==========================================================================rtcm end

local app = router.newRouter()
local ws_clients = {}
local function onRequest(req, res)
  if req.is_upgraded then
    wss.Handshake(req, res, function(ws)
        local addr = ws.socket:address()
        print(string.format("Client %d connected %s:%d" ,ws.id,addr.ip ,addr.port))
        table.insert(ws_clients,ws)
        ws:on("message",function(msg)
            p(msg)
            ws:send(msg);
        end)
        ws:on("close", function()
            for i,v in ipairs(ws_clients) do
              if ws == v then
                table.remove(ws_clients,i)
                break
              end
            end
            print(string.format("Client %d closed" ,ws.id))
        end)
        ws:on("error",function(err)
          for i,v in ipairs(ws_clients) do
              if ws == v then
                table.remove(ws_clients,i)
                break
              end
            end
            print(string.format("Client %d error msm=%s" ,ws.id,err.message))
        end)
    end)
  else
    req.path = req.url
    p(req.path)
    app.run(req,res,function()
      local body = "Not fund\n"
      res.statusCode = 404
      res:setHeader("Content-Type", "text/plain")
      res:setHeader("Content-Length", #body)
      res:finish(body)
    end)
  end
end
local server = http.createServer(onRequest):listen(80)

function ws_send_broadcast(msg)
  if type(msg) == 'table' then
    msg = JSON.stringify(msg)
  end
  for i,v in ipairs(ws_clients) do
    v:send(msg)
  end
end
app.use('static',static.root("/usrdata/public"))
app.use(cors)

app.route({
  method = "GET",
  path = "/"
},function(req,res,go)
  static.run(req,res,go)
end)

app.route({
  method = "GET",
  path = "/gns_info"
},function(req,res)
  local body = JSON.stringify(nmea.gns_info)
  res:setHeader("Content-Type", "application/json")
  res:setHeader("Content-Length", #body)
  res:finish(body)
end)

app.route({
  method = "GET",
  path = "/signal"
},function(req,res)
  local body = JSON.stringify(signal)
  res:setHeader("Content-Type", "application/json")
  res:setHeader("Content-Length", #body)
  res:finish(body)
end)

app.route({
  method = "GET",
  path = "/sys_info"
},function(req,res)
  local body = JSON.stringify(signal)
  res:setHeader("Content-Type", "application/json")
  res:setHeader("Content-Length", #body)
  res:finish(body)
end)

app.route({
  method = "GET",
  path = "/gns_status"
},function(req,res)
  if req.query ~= nil then
    local action = req.query.action 
    if action == 'reset_avg' then
      lon_sum = 0
      lat_sum = 0
      alt_sum = 0
      sum_cnt = 0
    end
  end
  local obj = {
    time = gps_data.gpstime,
    status = gps_data.status,
    lat = gps_data.lat/1000000000,
    lon = gps_data.lon/1000000000,
    hgt = gps_data.alt/1000,
    avg_lat = gps_data.avg_lat,
    avg_lon = gps_data.avg_lon,
    avg_hgt = math.ceil(gps_data.avg_hgt*1000)/1000,
    avg_time = gps_data.avg_time,
    mode = gns_cfg.mode,
    net_status = "NO connect"
  }
  local body = JSON.stringify(obj)
  res:setHeader("Content-Type", "application/json")
  res:setHeader("Content-Length", #body)
  res:finish(body)
end)

app.route({
  method = "POST",
  path = "/gns_cfg"
},function(req,res)
  gns_cfg = req.query
  local status = save_cfg("gns_cfg.json",gns_cfg)
  local body = JSON.stringify({status=status})
  res:setHeader("Content-Type", "application/json")
  res:setHeader("Content-Length", #body)
  res:finish(body)
end)

app.route({
  method = "GET",
  path = "/gns_cfg"
},function(req,res)
  local body = JSON.stringify(gns_cfg)
  res:setHeader("Content-Type", "application/json")
  res:setHeader("Content-Length", #body)
  res:finish(body)
end)



local fd_di = {-1,-1,-1}
  fd_di[1] = ffi.C.open("/sys/class/gpio/gpio26/value", bit.bor(Fflg.O_RDONLY,Fflg.O_NDELAY))
  fd_di[2] = ffi.C.open("/sys/class/gpio/gpio75/value",bit.bor(Fflg.O_RDONLY,Fflg.O_NDELAY))
  fd_di[3] = ffi.C.open("/sys/class/gpio/gpio2/value", bit.bor(Fflg.O_RDONLY,Fflg.O_NDELAY))
  local di_str = ffi.gc(ffi.cast("unsigned char*", ffi.C.malloc(3)), ffi.C.free)
  local di_value = {0,0,0}    -- di is pwm out
  timer.setInterval(100,function()
      local len
      local value
      for i,fd in ipairs(fd_di) do
        local ret = ffi.C.lseek(fd,0,0)
        if ret ~= 0 then
          p(ret,fd,ffi.string(ffi.C.strerror(ffi.errno())))
        end
        len = ffi.C.read(fd,di_str,3)
        if len > 1 and di_str[0] > 0x30  then
          di_value[i] = 1--di_value[i] + 1
        else 
          di_value[i] = 0
        end
      end
      --p(di_value)
  end)