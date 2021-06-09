local Buffer = require('buffer').Buffer
local timer = require('timer')
local net = require('net')
local ffi = require("ffi")
local dgram = require('dgram')
local base64 = require('./libs/base64.lua')

--local miniz = require("miniz")
local t2n_client = require('./src/t2n/t2n_client.lua')
local nmea = require('./src/nmea.lua')
local coro_serial = require("./src/sys/coro_serial.lua")
local coro_tcpclient = require('./libs/coro_tcp.lua')
--local log = require "log"  
local log = {print = print}

local lon_sum = 0
local lat_sum = 0
local alt_sum = 0
local sum_cnt = 0

local remote = {ip='127.0.0.1',port=9999}
local t2n = t2n_client:new(remote)

local cfg_prt1_out_none = "\xB5\x62\x06\x00\x14\x00\x01\x00\x00\x00\xD0\x08\x00\x00\x00\xC2\x01\x00\x23\x00\x00\x00\x00\x00\x00\x00\xD9\x4C"  --uart1 115200 out none
local cfg_prt1_out_all = "\xB5\x62\x06\x00\x14\x00\x01\x00\x00\x00\xD0\x08\x00\x00\x00\xC2\x01\x00\x23\x00\x23\x00\x00\x00\x00\x00\xFC\x1E"  --uart1 115200 out all

local cmd_prt1 = "\xB5\x62\x06\x00\x14\x00\x01\x00\x00\x00\xD0\x08\x00\x00\x00\xC2\x01\x00\x23\x00\x03\x00\x00\x00\x00\x00\xDC\x5E" --uart1 115200
local cmd_prt2 = "\xB5\x62\x06\x00\x14\x00\x02\x00\x00\x00\xD0\x08\x00\x00\x00\xC2\x01\x00\x20\x00\x20\x00\x00\x00\x00\x00\xF7\x08" --uart2 115200 RTCM3 in RTCM3 OUT 

local nmea_cfg = "\xB5\x62\x06\x17\x14\x00\x00\x41\x00\x0A\x00\x00\x00\x00\x00\x00\x00\x01\x00\x00\x00\x00\x00\x00\x00\x00\x7D\xDF" --high precision mode

 local rtcm_outport
 
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
  elseif v.ctype ~= nill and v.length ~= nil then  --Buffer
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

local function ubx_rtcm_cfg(id,rate,port)
  local buf = Buffer:new(16)
  buf[1] = 0xb5
  buf[2] = 0x62
  buf[3] = 0x06
  buf[4] = 0x01
  buf[5] = 0x08
  buf[6] = 0x00
  buf[7] = 0xf5
  buf[8] = id
  buf[9] = 0
  buf[10] = rate
  buf[11] = port
  buf[12] = 0
  buf[13] = 0
  buf[14] = 0
  local ck_a,ck_b = ubx_ck(buf,14)
  buf[15] = ck_a
  buf[16] = ck_b
  return buf
end
--mode 0 diable
--mode 2 fixmode ECEF x/y/z
--mode 1 Survey In 
--mode 3 fixmode lat/log/alt
local function ubx_cfg_tmode3(mode,XOrLat,YOrLon,ZOrAlt)
  local buf = Buffer:new(48)  
  local flags = 0
  local ecefXOrLat = 0
  local ecefXOrLatHP = 0
  local ecefYOrLon = 0
  local ecefYOrLonHP = 0
  local ecefZOrAlt = 0
  local ecefZOrAltHP = 0
  local MinDuration = 0
  local AccuracyLimit = 0
  mode = mode or 0
  if mode == 1 then
    MinDuration = XOrLat * 10000
    AccuracyLimit = YOrLon * 10000
    flags = 0x1
  elseif mode == 2 then --ECEF /x/x/z
    local value
    value = math.floor(XOrLat * 10000 + 0.5)
    ecefXOrLat = math.floor(value / 100)
    ecefXOrLatHP = value % 100
    value = math.floor(YOrLon * 10000 + 0.5)
    ecefYOrLon = math.floor(value / 100)
    ecefYOrLonHP = value % 100
    value = math.floor(ZOrAlt * 10000 + 0.5)
    ecefZOrAlt = math.floor(value / 100)
    ecefZOrAltHP = value % 100
    flags = 0x02
  elseif mode == 3 then --lat/lon/alt
    local value
    value = math.floor(XOrLat * 1000000000 + 0.5)
    ecefXOrLat = math.floor(value / 100)
    ecefXOrLatHP = value % 100
    value = math.floor(YOrLon * 1000000000 + 0.5)
    ecefYOrLon = math.floor(value / 100)
    ecefYOrLonHP = value % 100
    value = math.floor(ZOrAlt * 10000 + 0.5)
    ecefZOrAlt = math.floor(value / 100)
    ecefZOrAltHP = value % 100
    flags = 0x102
  end
 
  buf[1] = 0xb5
  buf[2] = 0x62
  buf[3] = 0x06
  buf[4] = 0x71
  buf:writeUInt16LE(5,40)
  
  buf[7] = 0x00 --Message version
  buf[8] = 0x00 --Reserved
  
  buf:writeUInt16LE(9,flags)
  buf:writeInt32LE(11,ecefXOrLat) --ecefXOrLa cm_or_deg*1e-7
  buf:writeInt32LE(15,ecefYOrLon) --ecefYOrLon cm_or_deg*1e-7
  buf:writeInt32LE(19,ecefZOrAlt) --ecefZOrAlt cm_or_deg*1e-7
  buf:writeInt8(23,ecefXOrLatHP) --ecefXOrLa cm_or_deg*1e-7
  buf:writeInt8(24,ecefYOrLonHP) --ecefYOrLon cm_or_deg*1e-7
  buf:writeInt8(25,ecefZOrAltHP) --ecefYOrLon cm_or_deg*1e-7
  buf:writeInt8(26,0) --Reserved
  buf:writeUInt32LE(27,250) --Fixed position 3D accuracy
  buf:writeUInt32LE(31,0) --Survey-in minimum duration
  buf:writeUInt32LE(35,0) --Survey-in position accuracy limit
  buf:writeUInt32LE(39,0) -- Reserved
  buf:writeUInt32LE(43,0) -- Reserved
  local ck_a,ck_b = ubx_ck(buf,46)
  buf[47] = ck_a
  buf[48] = ck_b
  return buf
end

local ub_cfg = { 
                  ubx_rtcm_cfg(0x05,0,0), --1005 Stationary RTK reference station ARP
                  ubx_rtcm_cfg(0x4a,0,0), --1074 GPS MSM4 
                  ubx_rtcm_cfg(0x4d,0,0), --1077 GPS MSM7
                  ubx_rtcm_cfg(0x54,0,0), --1084 GLONASS MSM4
                  ubx_rtcm_cfg(0x57,0,0), -- 1087 GLONASS MSM7
                  ubx_rtcm_cfg(0x5e,0,0), --1094 Galileo MSM4
                  ubx_rtcm_cfg(0x61,0,0), -- 1097 Galileo MSM7
                  ubx_rtcm_cfg(0x7c,0,0), --1124 BeiDou MSM4
                  ubx_rtcm_cfg(0x7f,0,0), --1127 BeiDou MSM7
                  ubx_rtcm_cfg(0xe6,0,0),  --1230 GLONASS code-phase biases
                  Buffer:new(nmea_cfg),
                  --ubx_cfg_tmode3(3,35.721332294,105.409090306,1899.8682),
                  ubx_cfg_tmode3(0),
                  Buffer:new(cfg_prt1_out_all),
              }
 
local gps_data = {gpstime=0,lat=0,lon=0, alt=0, status=0,speed=0,direction=0}

local ublox_com = coro_serial:new({port = ffi.os == "Windows" and "\\\\.\\COM31" or "/dev/ttyS2",baud =115200,char_timeout=10})

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
      return buf:toString(offset,pos),pos-offset+1
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

local gga=""

local gps_data = {gpstime=0,lat=0,lon=0, alt=0, status=0,speed=0,direction=0}

local udp_client = dgram.createSocket('udp4')
local rtcm_udp = {port=6051,ip="117.34.118.172"}
local udp_rtcm_age = 0
local rtcm_timeout = 25
local gga_req = 0
 
local function ublox_coro_body(dev)
  rtcm_outport = nil
  
	local err = dev:open()
	if err ~= nil then print(err) else
		print(string.format("open %s ok fd=%d",dev.name,dev.fd))
	end
  -- local ret,resp = dev:read()
  -- --p('read',resp)
  -- -- dev:write(cfg_prt1_out_none)    --set baud 115200
  -- timer.sleep(1000)
  -- --ret,resp = dev:read()
  -- dev:close()
  -- dev.baud = 115200
  -- err = dev:open()
	-- if err ~= nil then print(err) else
	-- 	print(string.format("open %s ok fd=%d",dev.name,dev.fd))
	-- end
  -- dev:write(cfg_prt1_out_none)  
  -- timer.sleep(1000)
  -- for k,v in pairs(ub_cfg) do
  --   p(k,v:inspect())
  --   dev:write(v)
  --   ret,resp = dev:read(4096)
  --   if ret > 0 then
  --     local rxbuf = Buffer:new(resp)
  --     p('cfg rx',rxbuf:inspect())
  --   else
  --     p('cfg rxtimeout')
  --   end
    
  -- end
  rtcm_outport = dev
  local rxbuf = Buffer:new(8192)
  local pos = 1
  local end_pos = 1
  local last_msg_type
  local rtcm_buf = Buffer:new(4096)
  local rtcm_idx = 1
  local nmea_buf = {}
  local nmea_idx = 1
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
      while pos < end_pos-1 do
        --local sync_a,sync_b = rxbuf[pos]
        if rxbuf[pos] == 0x24 and rxbuf[pos+1] == 0x47 then -- $G nema ??
          local line,len = get_line(pos,rxbuf,end_pos)
          if line == nil then
            break
          else
            ---p(line)
            if last_msg_type ~= "nema" then
              last_msg_type = "nema"
              if rtcm_idx > 1 then
                write_rtcm(rtcm_buf:toString(1,rtcm_idx))
                --local deflator = miniz.new_deflator(9)
                --local deflated, err, part = deflator:deflate(rtcm_buf:toString(1,rtcm_idx), "finish")
                --p("Compressed", rtcm_idx,#(deflated or part or ""))
                --local zrtcm = miniz.miniz_deflator()(rtcm_buf:toString(1,rtcm_idx),'finish')
                --write2clients(deflated)
                rtcm_idx = 1
              end
            end
            pos = pos + len
            
            nmea.parse(line,gps_data)
            if string.find(line,"$GNRMC",1,7) == 1 or string.find(line,"$GNGGA",1,7) == 1 then
              nmea_buf[nmea_idx] = line
              nmea_idx = nmea_idx + 1
              if nmea_idx > 2 then
                nmea_idx = 1
                local nmea = table.concat(nmea_buf)
                write_nmea(nmea)
              end
            end
            if string.find(line,"$GNGGA",1,7) == 1 and gps_data.lat ~= 0 and gps_data.lon ~= 0 then --last gps out
              gps_gpgga = line
              local data_buf = Buffer:new(24)
              -- data_buf:writeUInt32LE(1,gps_data.gpstime)
              -- data_buf:writeUInt32LE(5,gps_data.lat)
              -- data_buf:writeUInt8(9,gps_data.lat/0x100000000)
              -- data_buf:writeUInt32LE(10,gps_data.lon)
              -- data_buf:writeUInt8(14,gps_data.lon/0x100000000)
              -- data_buf:writeUInt32LE(15,gps_data.alt)
              -- data_buf:writeUInt8(18,gps_data.status)
              -- data_buf:writeUInt16LE(19,gps_data.speed)
              -- data_buf:writeUInt16LE(21,gps_data.direction)
              -- data_buf:writeUInt16LE(23,temp)
              --p(data_buf:inspect())
              t2n:drp_write(11,2,data_buf,data_buf.length)
              p(gps_data)
              rtcm_timeout = rtcm_timeout + 1
              -- if rtcm_timeout > 30 or gga_req ~= 0 then
              --   t2n:drp_write(10,0,line,#line)
              --   rtcm_timeout = 0
              --   gga_req = 0
              -- end
              -- local speed = gps_data.speed/6
              -- if speed < 30 then
              --   speed = 0
              -- end
              -- table.insert(led_data_queue,{slave=1,addr=15,value={speed,0}})   
              -- if #led_data_queue > 2 then
              --   table.remove(led_data_queue,1)
              -- end
              -- lon_sum = lon_sum + gps_data.lon
              -- lat_sum = lat_sum + gps_data.lat
              -- alt_sum = alt_sum + gps_data.alt
              -- sum_cnt = sum_cnt + 1
              -- local k = sum_cnt*1000000000
              -- p(string.format("lon=%.9f,lat=%.9f,alt=%.4f time=%d",lon_sum/k,lat_sum/k,alt_sum/(sum_cnt*1000),sum_cnt))
            elseif(string.find(line,"$GNGLL",1,6) == 1) then
              --local s = JSON.stringify(nmea.gns_info)
             -- local deflator = miniz.new_deflator(9)
              --local deflated, err, part = deflator:deflate(s, "finish")
              --p("Compressed   ddddddddddddddddddddddddddddd", rtcm_idx,#(deflated or part or ""))
                --local zrtcm = miniz.miniz_deflator()(rtcm_buf:toString(1,rtcm_idx),'finish')
                --write2clients(deflated)
              --t2n:drp_write(9,2,deflated,#deflated)
              --local ws_publish = {"GNSInfo",nmea.gns_info}
              --local msg = JSON.stringify(ws_publish)
              --signal.GNGSV = nmea.gns_info.view
              --signal.GNGSA = nmea.gns_info.use
              --signal.Gstatus = nmea.gns_info.status
              --ws_send_broadcast(msg)
              
              --p(nmea.gns_info.sview)
              --print(s)
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
--        elseif rxbuf[pos] == 0xb5 and rxbuf[pos+1] == 0x62 then --ublox ??
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
local cors = 
{
    host= "203.107.45.154",
    --host = 'rtk.ntrip.qxwz.com',
    port= 8002,
    ntrip= true,
    -- mode = 'rover',
    -- host = "11.5.1.21",
    -- port = 6060,
 
    mountpoint="RTCM32_GGB",
    user= "qxphvy001",
    password= "3b1add8",
    --user = "qxphvy001",
    --password = "3b1add8" ,
    timeout = 15000
}

--local rtcm_option = {host="203.107.45.154",port=8002,timeout=15000}
local rtcm_option = {host="192.168.11.2",port=8002,timeout=15000}
local rtcm_client = coro_tcpclient:new(cors)

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
    if (cors.ntrip == true) then
      local headers = {}
      table.insert(headers, 'GET '..cors.mountpoint..' HTTP/1.1')
      table.insert(headers, 'Host: '..cors.host)
      table.insert(headers, 'Ntrip-Version: Ntrip/2.0')
      table.insert(headers, 'User-Agent: NTRIP u-blox')
      table.insert(headers, 'Accept: */*')
      local user_pwd = cors.user..':'..cors.password
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

local rtcm_co = coroutine.create(rtcm_coro_body)
local ret,msg = coroutine.resume(rtcm_co,rtcm_client)
if(ret ~= true) then log.print(msg) end


local rtcm_clients = {}

local rtcm_server = net.createServer(function(client)
  local addr = client:address()
  log.print(string.format("Client connected %s:%d" ,addr.ip ,addr.port))
  table.insert(rtcm_clients,client)
  -- Add some listenners for incoming connection
  client:on("error",function(err)
    log.print("Client read error: " .. err)
    for i, c in ipairs( rtcm_clients ) do
      if c == client then
        table.remove(rtcm_clients, i)
        break
      end
    end
  end)

  client:on("data",function(data)
    --client:write(data)
  end)

  client:on("end",function()
    for i, c in ipairs( rtcm_clients ) do
      if c == client then
        table.remove(rtcm_clients, i)
        break
      end
    end
    local addr = client:address()
    log.print(string.format("Client disconnected %s:%d" ,addr.ip ,addr.port))
  end)
end)

 
rtcm_server:on('error',function(err)
  if err then error(err) end
end)

rtcm_server:listen(6060)  

function write_rtcm(data)
  for i, c in ipairs(rtcm_clients) do
--    local addr = c:address()
--     p(addr)
    if c ~= nil then
      c:write(data)
    end
  end
end


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
        table.remove(clients, i)
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


udp_client:bind(0,"0.0.0.0")
udp_client:on("message",function(msg,rinfo) 
  print ("from " .. rinfo.ip .. ":" .. rinfo.port)
  if rtcm_outport ~= nil then
    local len = rtcm_outport:write(msg,#msg)
    p('rtcm revice',#msg)
  end
  udp_rtcm_age = 0;
end)

local dns = require('dns')
dns.setServers({{host='180.76.76.76',port=53,tcp=false},{host='114.114.114.114',port=53,tcp=false}})
dns.setTimeout(10000)
local count = 0
timer.setInterval(60000,function()
  if coroutine.status(ublox_coro) == 'dead' then
    ublox_coro = coroutine.create(ublox_coro_body)
    local ret,msg = coroutine.resume(ublox_coro)
    if(ret ~= true) then log.print(msg) end
  end
  dns.resolve4("www.baidu.com",function(msg,obj)
    if obj ~= nil and #obj > 0 then
        count = 0
    end
  end)
  count = count + 1
  if count > 3 then
    os.execute("reboot")
  end
end)