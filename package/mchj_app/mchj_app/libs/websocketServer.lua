local Emitter = require("core").Emitter
local codec = require("websocket-codec")

local id = 0
local Client = Emitter:extend()

function Client:initialize(socket)
  self.socket = socket
  id = id + 1
  self.id = id
  socket:once(
    "timeout",
    function()
      self.socket:_end()
    end
  )
  -- set socket timeout
  socket:setTimeout(120000)
  socket:on(
    "data",
    function(chunk)
      local msg, offset = codec.decode(chunk, 1)
      if (msg.opcode == 1 or msg.opcode == 2) then
        self:emit("message", msg.payload, offset)
      elseif msg.opcode == 9 then
        self.socket:_end()
      elseif msg.opcode == 8 then
        self.socket:_end()
      end
    end
  )
  socket:on(
    "end",
    function()
      self:emit("close")
    end
  )
end

function Client:send(msg)
  local data = codec.encode(msg)
  self.socket:write(
    data,
    function(err)
      if (err ~= nil) then
        self:emit("error", err)
      end
    end
  )
end

local function Handshake(req, res, onConnection)
  local client = Client:new(req.socket)
  local resp = codec.handleHandshake(req.headers)
  for k, v in pairs(resp) do
    if type(v) == "table" then
      res:setHeader(v[1], v[2])
    end
  end
  res.statusCode = resp.code
  res.sendDate = false
  res:write("")
  if type(onConnection) == "function" then
    onConnection(client)
  end
end

local function createServer(options, connectionListener)
  local server = Server:new()
  server:init(options, connectionListener)
  return server
end

return {
  Client = Client,
  Handshake = Handshake
}
