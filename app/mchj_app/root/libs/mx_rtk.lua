--require('mobdebug').start()
local Buffer = require("buffer").Buffer
local net = require("net")
local timer = require("timer")
local ffi = require("ffi")
local JSON = require("json")
local miniz = require("miniz")
local nmea = require("nmea")
local coro_serial = require("coro-serial")
local log = require("log.lua")
-- local log = {print = print}
local t2n = require("t2n")
local router = require("router")
local scfg = require("server_cfg.lua")
local Emitter = require("core").Emitter
local emitter = Emitter:new()

ffi.cdef [[
  int open(const char *pathname, int flags);
  int close(int fd);
  int read(int fd, char *buf, size_t count);
  int write(int fd, char *buf, size_t count);
  int ioctl(int fd,unsigned long cmd,...);
  int lseek(int fd,int offset, int fromwhere);
  void msleep(int ms);
  int *__errno_location (void);
  char *strerror (int __errnum);

  void *malloc (size_t __size);
  void free (void *__ptr);
]]
local Fflg = {
  ---- open/fcntl - O_SYNC is only implemented on blocks devices and on files
  ---- located on an ext2 file system */
  O_ACCMODE = 0x0003,
  O_RDONLY = 0x0000,
  O_WRONLY = 0x0001,
  O_RDWR = 0x0002,
  O_APPEND = 0x0008,
  O_SYNC = 0x0010,
  O_NONBLOCK = 0x0800,
  O_NDELAY = 0x0800, ----O_NONBLOCK
  O_CREAT = 0x0100, ----/* not fcntl */
  O_TRUNC = 0x0200, ----/* not fcntl */
  O_EXCL = 0x0400, ----/* not fcntl */
  O_NOCTTY = 0x0800, ----/* not fcntl */
  O_FSYNC = 0x0010, ----O_SYNC
  O_ASYNC = 0x1000,
  ----/* Values for the second argument to `fcntl'.  */
  F_DUPFD = 0, ----	/* Duplicate file descriptor.  */
  F_GETFD = 1, ----	1	/* Get file descriptor flags.  */
  F_SETFD = 2, ----	2	/* Set file descriptor flags.  */
  F_GETFL = 3, ----	3	/* Get file status flags.  */
  F_SETFL = 4 ---- 4	/* Set file status flags.  */
}

local rtcm_outport
local gss_req = 0

function Buffer:write(offset, v, length)
  if type(offset) ~= "number" or offset < 1 or offset > self.length then
    log.error("Index out of bounds")
  end
  if type(v) == "string" then
    length = length or #v
    ffi.copy(self.ctype + offset - 1, v, length)
  elseif type(v) == "cdata" then
    if length > 0 then
      ffi.copy(self.ctype + offset - 1, v, length)
    else
      log.error("[Buffer:write] ctype must give length")
    end
  elseif v.ctype ~= nil and v.length ~= nil then --Buffer
    length = length or v.length
    ffi.copy(self.ctype + offset - 1, v.ctype, length)
  else
    log.error("[Buffer:write] Input must be a string or cdata or Buffer")
    return
  end
end

function Buffer:copy(target, targetStart, sourceStart, sourceEnd)
  ffi.copy(target.ctype + targetStart - 1, self.ctype + sourceStart - 1, sourceEnd - sourceStart + 1)
end

local gps_data = {gpstime = 0, lat = 0, lon = 0, alt = 0, status = 0, speed = 0, direction = 0, antenna = "unknown"}
local gnss_com =
  coro_serial:new(
  {port = ffi.os == "Windows" and "\\\\.\\COM15" or scfg.get_gps_dev_port(), baud = 115200, char_timeout = 10}
)

log.info("gnss_com start(" .. scfg.get_gps_dev_port() .. ")...")

local function get_line(pos, buf, end_pos)
  --local buf = Buffer:new(1024)
  local idx = 0
  local done = false
  local offset = pos
  while pos < end_pos do
    if buf[pos] ~= 0x0a then
      pos = pos + 1
    else
      return buf:toString(offset, pos), pos - offset + 1
    end
  end
  return
end

local rtcm_timeout = 25
local gga_req = 0
local gps_keep_run
local nmea_clients = {}

local nmea_server =
  net.createServer(
  function(client)
    local addr = client:address()
    log.info(string.format("Client connected %s:%d", addr.ip, addr.port))
    table.insert(nmea_clients, client)
    -- Add some listenners for incoming connection
    client:on(
      "error",
      function(err)
        log.error("Client read error: " .. err)
        for i, c in ipairs(nmea_clients) do
          if c == client then
            table.remove(nmea_clients, i)
            break
          end
        end
      end
    )
    client:on(
      "data",
      function(data)
        --client:write(data)
      end
    )
    client:on(
      "end",
      function()
        for i, c in ipairs(nmea_clients) do
          if c == client then
            table.remove(nmea_clients, i)
            break
          end
        end
        local addr = client:address()
        log.info(string.format("Client disconnected %s:%d", addr.ip, addr.port))
      end
    )
  end
)
nmea_server:on(
  "error",
  function(err)
    if err then
      error(err)
    end
  end
)
nmea_server:listen(scfg.get_nmea_remote_port())
log.info("nmea_server start(localhost:" .. scfg.get_nmea_remote_port() .. ")...")

local function write_nmea(data)
  for i, c in ipairs(nmea_clients) do
    if c ~= nil then
      c:write(data)
    end
  end
end

t2n:drp_on_req(
  10,
  function(msg)
    -- p('drp rtcm revice',#msg)
    rtcm_timeout = 0
    if rtcm_outport ~= nil then
      rtcm_outport:write(msg, #msg)
    end
  end
)

t2n:drp_on_req(
  11,
  function(msg)
    if msg == "GGA_REQ" then
      gga_req = 1
    end
  end
)
local gps_timeout = 0

local function gnss_coro_body(dev)
  rtcm_outport = nil
  local err = dev:open()
  if err ~= nil then
    log.error(err)
  else
    log.info(string.format("open %s ok fd=%d", dev.name, dev.fd))
  end
  rtcm_outport = dev
  while true do
    local rxbuf = Buffer:new(8192)
    local pos = 1
    local end_pos = 1
    local last_msg_type
    local rtcm_buf = Buffer:new(4096)
    local rtcm_idx = 1
    local nmea_buf = {}
    local nmea_idx = 1
    gps_keep_run = true
    while gps_keep_run do
      len, resp = dev:read(4096)
      --local rxbuf = Buffer:new(resp)
      --print("rx pack",rxbuf:inspect())
      -- p(resp)
      if len > 0 then
        if end_pos + len > rxbuf.length then
          end_pos = 1
        end
        rxbuf:write(end_pos, resp, len)
        end_pos = end_pos + len
        pos = 1
        while pos < end_pos - 1 do
          --local sync_a,sync_b = rxbuf[pos]
          if rxbuf[pos] == 0x24 and (rxbuf[pos + 1] == 0x47 or rxbuf[pos + 1] == 0x42) then -- $G || $B nema ??
            local line, len = get_line(pos, rxbuf, end_pos)
            if line == nil then
              break
            else
              -- p(line)
              if last_msg_type ~= "nema" then
                last_msg_type = "nema"
                if rtcm_idx > 1 then
                  write_rtcm(rtcm_buf:toString(1, rtcm_idx))
                  rtcm_idx = 1
                end
              end
              pos = pos + len

              nmea.parse(line, gps_data)
              if string.find(line, "$GNRMC", 1, 7) == 1 or string.find(line, "$GNGGA", 1, 7) == 1 then
                nmea_buf[nmea_idx] = line
                nmea_idx = nmea_idx + 1
                if nmea_idx > 2 then
                  nmea_idx = 1
                  local nmea = table.concat(nmea_buf)
                  write_nmea(nmea)
                end
              end
              if string.find(line, "$GNGGA", 1, 7) == 1 and gps_data.lat ~= 0 and gps_data.lng ~= 0 then --last gps out
                --p(string.format("lon=%.9f,lat=%.9f,alt=%.4f time=%d",lon_sum/k,lat_sum/k,alt_sum/(sum_cnt*1000),sum_cnt))
                gps_timeout = 0
                rtcm_timeout = rtcm_timeout + 1
                if rtcm_timeout > 30 or gga_req ~= 0 then
                  t2n:drp_write(10, 0, line, #line)
                  p(rtcm_timeout)
                  rtcm_timeout = 0
                  gga_req = 0
                end

                -- p("data", gps_data)
                emitter:emit("data", gps_data)
              elseif (string.find(line, "$GNGLL", 1, 6) == 1) then
                if gss_req > 0 then
                  if gss_req % 2 == 0 then
                    local s = JSON.stringify(nmea.gns_info)
                    local deflator = miniz.new_deflator(9)
                    local deflated, err, part = deflator:deflate(s, "finish")
                    t2n:drp_write(9, 0, deflated, #deflated)
                  end
                  gss_req = gss_req - 1
                end
                gps_timeout = gps_timeout + 1
                if gps_timeout > 60 then
                  emitter:emit("timeout")
                  gps_timeout = 0
                end
                local ws_publish = {"GNSInfo", nmea.gns_info}
                local msg = JSON.stringify(ws_publish)
              end
            end
          else
            log.info(
              string.format(
                "no sync pos=%d,end_pos=%d,sync_a=%02x,sync_b=%02x",
                pos,
                end_pos,
                rxbuf[pos],
                rxbuf[pos + 1]
              )
            )
            pos = pos + 1
          end
        end
      else
        log.warn("read timeout")
      end
      if pos < end_pos then
        rxbuf:copy(rxbuf, 1, pos, end_pos)
        end_pos = end_pos - pos + 1
      else
        end_pos = 1
      end
    end
    --timer.sleep(20)
  end
end

local gnss_coro = coroutine.create(gnss_coro_body)
local ret, msg = coroutine.resume(gnss_coro, gnss_com)
if (ret ~= true) then
  log.print(msg)
end
log.info("creat gnss_coro_body coroutine start...")

local ant_gpios = {scfg.get_right_ant_gpio(), scfg.get_left_ant_gpio()} -- ant gpio

local c_str = ffi.gc(ffi.cast("unsigned char*", ffi.C.malloc(3)), ffi.C.free)
emitter.ant_change = function(ant)
  if ant == gps_data.antenna then
    return 0
  end
  if ant == nil then
    if gps_data.antenna == "left" then
      ant = "right"
    else
      ant = "left"
    end
  end
  local io_idx = ant == "left" and 2 or 1
  local fd = ffi.C.open(string.format("/sys/class/gpio/gpio%d/value", ant_gpios[io_idx]), Fflg.O_WRONLY)
  if fd > 0 then
    ffi.copy(c_str, "0")
    ffi.C.write(fd, c_str, 1)
    ffi.C.close(fd)
    gps_data.antenna = "none"
  else
    log.error(string.format("open gpio%d error\r\n", ant_gpios[io_idx]))
  end
  timer.setTimeout(
    500,
    function()
      io_idx = ant == "left" and 1 or 2
      fd = ffi.C.open(string.format("/sys/class/gpio/gpio%d/value", ant_gpios[io_idx]), Fflg.O_WRONLY)
      if fd > 0 then
        ffi.copy(c_str, "1")
        local ret = ffi.C.write(fd, c_str, 1)
        if ret < 0 then
          emitter.get_ant()
        end
        ffi.C.close(fd)
        gps_data.antenna = ant
      else
        log.error(string.format("open gpio%d error\r\n", ant_gpios[io_idx]))
      end
    end
  )
  return 1
end
emitter.get_ant = function()
  local left = 0
  local right = 0
  local result = {0, 0}
  for index, value in ipairs(ant_gpios) do
    local fd = ffi.C.open(string.format("/sys/class/gpio/gpio%d/value", value), Fflg.O_RDONLY)
    if fd < 0 then
      fd = ffi.C.open(string.format("/sys/class/gpio/export"), Fflg.O_WRONLY)
      local lua_str = tostring(value)
      ffi.copy(c_str, lua_str)
      ffi.C.write(fd, c_str, #lua_str)

      fd = ffi.C.open(string.format("/sys/class/gpio/gpio%d/direction", value), Fflg.O_WRONLY)
      if fd < 0 then
        ffi.C.msleep(10)
        fd = ffi.C.open(string.format("/sys/class/gpio/gpio%d/direction", value), Fflg.O_WRONLY)
      end
      if fd > 0 then
        ffi.copy(c_str, "out")
        ffi.C.write(fd, c_str, 3)
      else
        log.error(string.format("set gpio%d output error"))
      end
    end
    fd = ffi.C.open(string.format("/sys/class/gpio/gpio%d/value", value), Fflg.O_RDONLY)
    if fd > 0 then
      ffi.C.lseek(fd, 0, 0)
      local len = ffi.C.read(fd, c_str, 3)
      if len > 1 and c_str[0] > 0x30 then
        result[index] = 1
      end
    end
  end
  if result[1] == 1 and result[2] == 0 then
    gps_data.antenna = "left"
  elseif result[1] == 0 and result[2] == 1 then
    gps_data.antenna = "right"
  else
    --emitter.ant_change('left')
    gps_data.antenna = "none"
  end
  log.info("get_ant", result, gps_data.antenna)
  return gps_data.antenna
end
-- p("load mx_base")
emitter.get_ant()
log.info("get l/r ant start...")

return emitter, router
