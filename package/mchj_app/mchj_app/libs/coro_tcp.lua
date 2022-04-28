local Object = require('core').Object
local bit = require "bit"
local uv = require("uv")
local ffi = require("ffi")
local dns = require('dns')

dns.setServers({{host='180.76.76.76',port=53,tcp=false},{host='114.114.114.114',port=53,tcp=false}})
dns.setTimeout(10000)

local coro_tcpclient  = Object:extend()

function coro_tcpclient:initialize(option)
  if option.host == nil then
      local err = "option.host is nil"
      return err
  end
 if option.port == nil then
      local err = "option.port is nil"
      return err
  end
  self.host = option.host
  self.port = option.port
  self.timeout = option.timeout or 5000
  self.timer = uv.new_timer()
  self.name = string.format("%s:%d",self.host,self.port)
  self.client = nil
end

function coro_tcpclient:open()
  local co = coroutine.running()
  local client = uv.new_tcp()
  dns.resolve4(self.host,function(msg,obj)
    if obj ~= nil and #obj > 0 then 
      p(obj,msg) 
      --return assert(coroutine.resume(co))
      self.address = obj[1].address
      client:connect(self.address, self.port, function(err)
        if err then 
          return assert(coroutine.resume(co,err))
        end
        self.client = client
        return assert(coroutine.resume(co))
      end)
      uv.timer_start(self.timer, self.timeout, 0, function ()
          --self.client:close()
          --p(self.client)
          return assert(coroutine.resume(co,0))
      end)
    else
      return assert(coroutine.resume(co,err))
    end
  end)
 -- return coroutine.yield()

  return coroutine.yield()
end

function coro_tcpclient:write(txdata,offset,len)
  if self.client == nul then
    print("coro_tcpclient:write not connected")
    return -2
  end
  local txbuf
 -- p(type(txdata))
--  if type(txdata) == 'string' then
--    --len = len or #txdata
--    txbuf = txdata --ffi.gc(ffi.cast("unsigned char*", C.malloc(len)), C.free)
--    --ffi.copy(buf,txdata,len)
--  elseif type(txdata) == 'cdata' then
--    txbuf = ffi.string(txdata, offset)
--  elseif txdata.cdata ~= nil then
--    txbuf = txdata:toString(offset or 0,len)
--  else
--    print("Input must be a string or cdata or Buffer")
--    return -1jk
--  end

    if type(txdata) == 'cdata' then
      txbuf = ffi.string(txdata, length)
    elseif type(txdata) == 'table' and txdata.ctype ~= nil then
      --txbuf = ffi.string(txdata.ctype, length)
      txbuf = txdata:toString()
    elseif type(txdata) == 'string' then
      txbuf = txdata
    else
      print("coro_tcpclient:write Input must be a string or cdata or Buffer")
      return -1
    end
 -- p(txbuf)
  local ret = self.client:write(txbuf)
  return ret
end

function coro_tcpclient:read(want_len,min_len)
  if self.client == nul then
    print("coro_tcpclient:read not connected")
    return -2
  end
  local co = coroutine.running()
  self.client:read_start(function(err,data)
      uv.timer_stop(self.timer)
    -- If error, print and close connectio
    if err then
      --print("Client read error: " .. err)
      self.client:close()
      self.client = nil
      return assert(coroutine.resume(co,-2))
    end
    -- If data is set the server has relaid data, if unset the client has disconnected
    if data then
      self.client:read_stop()
      return assert(coroutine.resume(co,#data,data))
    else
      self.client:close()
      self.client = nil
      return assert(coroutine.resume(co,-3))
    end
  end)
  uv.timer_start(self.timer, self.timeout, 0, function ()
      self.client:read_stop()
      return assert(coroutine.resume(co,0))
  end)
  return coroutine.yield()
end

function coro_tcpclient:close()
  if self.client  ~= nil then
    self.client:close()
    self.client = nil
  end
end

--local option = {host="127.0.0.1",port=502,timeout=10000}
--local coro_modebus = coro_tcpclient:new(option)

return coro_tcpclient

