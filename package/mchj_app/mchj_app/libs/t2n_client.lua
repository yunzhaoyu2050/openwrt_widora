local Buffer = require("buffer").Buffer
local ffi = require("ffi")
local bit = require("bit")
local uv = require("uv")
local timer = require("timer")
local core = require("core")

local C = ffi.os == "Windows" and ffi.load("msvcrt") or ffi.C
-- bit 15 1 ACK 0 REQ
-- bit 14,13,12

---   000 无需确认完整包
---   001 协商请求包
---   010 确认包需ACK为1
---   011 协商回应求包

---   100 中间包
---   101 首包
---   110 末包
---   111 需确认完整包

-----------------------------

local TCF_FLG_ACK = 0x08

local DRP_FIRST_PACK = 0x05
local DRP_MID_PACK = 0x04
local DRP_LAST_PACK = 0x06
local DRP_FULL_PACK = 0x07
local DRP_NOACK_PACK = 0x03
local DRP_REQ = 0x01

local DRP_STATE_IDLE = 1
local DRP_STATUS_WAIT_ACK = 2
local DRP_STATUS_ERROR = 2

local send_flg = 1

local function data_sum(buf, offset, length)
	local cksum = 0
	local data
	if length > buf.length then
		length = buf.length
	end
	-- uint8_t *buffer = (uint8_t *)buf;
	while (length > 1) do
		data = buf:readUInt16LE(offset)
		cksum = cksum + data
		offset = offset + 2
		length = length - 2
	end
	if length > 0 then
		data = buf:readUInt8(offset)
		cksum = cksum + data
	end
	-- 将32位数转换成16
	while bit.rshift(cksum, 16) ~= 0 do
		cksum = bit.rshift(cksum, 16) + bit.band(cksum, 0xffff)
	end
	return bit.bnot(cksum)
end

local function gen_tcf_len(length, tcf)
	length = bit.band(length, 0xfff)
	tcf = bit.band(bit.lshift(tcf, 12), 0xf000)
	return bit.bor(tcf, length)
end

function Buffer:write(offset, v, length)
	if type(offset) ~= "number" or offset < 1 or offset > self.length then
		error("Index out of bounds")
	end
	if type(v) == "string" then
		length = length or #v
		ffi.copy(self.ctype + offset - 1, v, length)
	elseif type(v) == "cdata" then
		if length > 0 then
			ffi.copy(self.ctype + offset - 1, v, length)
		else
			error("[Buffer:write] ctype must give length")
		end
	elseif v.ctype ~= nill and v.length ~= nil then -- Buffer
		length = length or v.length
		ffi.copy(self.ctype + offset - 1, v.ctype, length)
	else
		error("[Buffer:write] Input must be a string or cdata or Buffer")
		return
	end
end

function Buffer:write(offset, v, length)
	if type(offset) ~= "number" or offset < 1 or offset > self.length then
		error("Index out of bounds")
	end
	if type(v) == "string" then
		length = length or #v
		ffi.copy(self.ctype + offset - 1, v, length)
	elseif type(v) == "cdata" then
		if length > 0 then
			ffi.copy(self.ctype + offset - 1, v, length)
		else
			error("[Buffer:write] ctype must give length")
		end
	elseif v.ctype ~= nill and v.length ~= nil then -- Buffer
		length = length or v.length
		ffi.copy(self.ctype + offset - 1, v.ctype, length)
	else
		error("[Buffer:write] Input must be a string or cdata or Buffer")
		return
	end
end

function Buffer:write(offset, v, length)
	if type(offset) ~= "number" or offset < 1 or offset > self.length then
		error("Index out of bounds")
	end
	if type(v) == "string" then
		length = length or #v
		ffi.copy(self.ctype + offset - 1, v, length)
	elseif type(v) == "cdata" then
		if length > 0 then
			ffi.copy(self.ctype + offset - 1, v, length)
		else
			error("[Buffer:write] ctype must give length")
		end
	elseif v.ctype ~= nill and v.length ~= nil then -- Buffer
		length = length or v.length
		ffi.copy(self.ctype + offset - 1, v.ctype, length)
	else
		error("[Buffer:write] Input must be a string or cdata or Buffer")
		return
	end
end

function ip2int(ip)
	local s, e, a, b, c, d = string.find(ip, "(%d+).(%d+).(%d+).(%d+)")
	local ret = bit.bor(bit.lshift(a, 24), bit.lshift(b, 16), bit.lshift(c, 8), d)
	return ret
end

local t2n_client = core.Object:extend()

function t2n_client:initialize(option)
	option = option or {}
	self.rcp_handles = {}
	self.drp_session = {}
	self.drp_queue = {}
	self.drp_status = DRP_STATE_IDLE
	self.drp_timer = uv.new_timer()
	self.drp_mtu = 1400
	self.drp_win = 5
	self.drp_wack = 0
	self.drp_timeout = 3000
	self.remote_port = option.port or 9999
	self.remote_ip = option.ip or "127.0.0.1"
	self.utp_pcbs = {}
	self.udp_handle = uv.new_udp()
	uv.udp_bind(self.udp_handle, "127.0.0.1", 0)
	uv.udp_recv_start(
		self.udp_handle,
		function(err, msg, rinfo, flags)
			if err then
				print(err)
			else
				if msg then
					local msg_type = string.sub(msg, 1, 4)
					if msg_type == "RDRP" then
						self:handle_drp(msg)
					elseif msg_type == "RRCP" then
						self:handle_utp(msg)
					else
						self:handle_other(msg, rinfo, flags)
					end
				end
			end
		end
	)
	self.drp_send_async =
		uv.new_async(
		function()
			self:drp_send_check()
		end
	)

	self.udp_handle:send(
		"LOGIN",
		self.remote_ip,
		self.remote_port,
		function()
			if err ~= nil then
				print(err)
			-- client.close()
			end
		end
	)

	self.drp_timer:start(
		500,
		500,
		function()
			local change = 0
			for i = 1, #self.drp_queue do
				local v = self.drp_queue[i]
				if v.timeout_cnt > 0 then
					v.timeout_cnt = v.timeout_cnt - 1
				else
					if v.timeout_cnt < 0 then -- 此包还未发送，后面也未发送
						break
					else
						change = change + 1
					end
				end
			end
			if change > 0 then
				print("change", change)
				self.drp_status = DRP_STATE_IDLE
				self:drp_send_check()
			end
		end
	)
end

function t2n_client:handle_drp(msg)
	local offset = 7
	while offset < #msg do
		local endpoint = string.byte(msg, offset + 1)
		local pkt_id = string.byte(msg, offset + 2) * 0x100 + string.byte(msg, offset + 3)
		local tcf_len = string.byte(msg, offset + 4) * 0x100 + string.byte(msg, offset + 5)
		local length = bit.band(tcf_len, 0xfff)
		local tcf = bit.rshift(tcf_len, 12)
		-- p(endpoint, tcf)
		if tcf == DRP_REQ then
			local drp_cntx = self.drp_session[endpoint]
			if drp_cntx ~= nil and drp_cntx.req_cb ~= nil then
				--    if drp_cntx.is_b ~= nil
				drp_cntx.req_cb(string.sub(msg, 13), endpoint)
			--        else
			--          Buffer
			--          drp_cntx.req_cb(data,endpoint)
			--        end
			end
		end
		if bit.band(tcf, TCF_FLG_ACK) then
			for i, v in ipairs(self.drp_queue) do
				if v.endpoint == endpoint and v.id == pkt_id then
					local drp_cntx = self.drp_session[endpoint]
					if drp_cntx ~= nil then
						drp_cntx.ack_id = pkt_id
						self.drp_wack = self.drp_wack - 1
					end
					table.remove(self.drp_queue, i)
					break
				end
			end
		else
		end
		offset = offset + 5 + length
	end
	self.drp_send_async:send()
end

function readUInt32BE(str, offset)
	local a, b, c, d = string.byte(str, offset, offset + 4)
	return bit.lshift(a, 24) + bit.lshift(b, 16) + bit.lshift(c, 8) + d
end

function readUInt32LE(str, offset)
	local a, b, c, d = string.byte(str, offset, offset + 4)
	return bit.lshift(d, 24) + bit.lshift(c, 16) + bit.lshift(b, 8) + a
end

function readInt32BE(str, offset)
	return bit.tobit(readUInt32BE(str, offset))
end

function readInt32LE(str, offset)
	return bit.tobit(readUInt32LE(str, offset))
end

function readUInt16BE(str, offset)
	local a, b = string.byte(str, offset, offset + 2)
	return bit.lshift(a, 8) + b
end

function readUInt16LE(str, offset)
	local a, b = string.byte(str, offset, offset + 2)
	return bit.lshift(b, 8) + a
end

function readInt16BE(str, offset)
	local value = readUInt16BE(str, offset)
	return value < 0x8000 and value or value - 0x10000
end

function readInt16LE(str, offset)
	local value = readUInt16LE(str, offset)
	return value < 0x8000 and value or value - 0x10000
end

function readUInt8(str, offset)
	return string.byte(str, offset)
end

function readInt8(str, offset)
	local value = string.byte(str, offset)
	return value < 0x80 and value or value - 0x100
end

function t2n_client:handle_utp(msg, rinfo, flags)
	-- local buf = Buffer:new(msg)
	-- p(buf:inspect())
	local src_ip = readUInt32BE(msg, 5)
	local src_ep = readUInt8(msg, 11)
	local dst_ep = readUInt8(msg, 12)
	local pkt_id = readUInt16BE(msg, 13)
	local tcf_len = readUInt16BE(msg, 15)
	local length = bit.band(tcf_len, 0xfff)
	local tcf = bit.rshift(tcf_len, 12)
	local data = string.sub(msg, 17, 17 + length)
	local utp_pcb = self.utp_pcbs[dst_ep]
	if utp_pcb ~= nil then
		utp_pcb.cb(
			data,
			{
				ip = src_ip,
				ep = src_ep
			}
		)
	end
end

function t2n_client:utp_bind(ep, cb)
	self.utp_pcbs[ep] = {
		ep = ep,
		cb = cb
	}
end

local pack_id = 1
local flags = DRP_FULL_PACK

function t2n_client:rcp_send(data, offset, length, ip, dest_ep)
	local src_ep = 32
	local txbuf = Buffer:new(length + 16)
	local chk_sum = 0
	txbuf:write(1, "TRCP")
	local idx = 5
	local dest = ip2int(ip)
	txbuf:writeUInt32BE(idx, dest)
	idx = idx + 4
	txbuf:writeUInt16BE(idx, chk_sum)
	idx = idx + 2
	txbuf:writeUInt8(idx, src_ep)
	idx = idx + 1
	txbuf:writeUInt8(idx, dest_ep)
	idx = idx + 1
	pack_id = pack_id + 1
	txbuf:writeUInt16BE(idx, pack_id)
	idx = idx + 2
	local tcf_len = gen_tcf_len(length, 0)
	txbuf:writeUInt16BE(idx, tcf_len)
	idx = idx + 2
	txbuf:write(idx, data, length)
	idx = idx + length
	chk_sum = data_sum(txbuf, 9, idx - 9)
	txbuf:writeUInt16LE(9, chk_sum)
	self.udp_handle:send(
		txbuf:toString(1, idx - 1),
		self.remote_ip,
		self.remote_port,
		function()
			if err ~= nil then
				print(err)
			-- client.close()
			end
		end
	)
end

function t2n_client:handle_other(msg, rinfo, flags)
	if send_flg == 0 then
		send_flg = 1
	else
		send_flg = 0
	end
	print(msg, send_flg)
end

local function data_copy(msg, offset, length)
	offset = offset or 1
	if type(offset) ~= "number" or offset < 1 then
		error("offset out of bounds")
	end

	if type(msg) == "cdata" then
		assert(type(length) == "number", "length must a number")
		local data = ffi.cast("char *", msg)
		return ffi.string(data + offset - 1, length)
	elseif type(msg) == "string" then
		return string.sub(msg, offset, offset + length)
	elseif msg.ctype ~= nill and msg.length ~= nil then -- Buffer
		length = length or msg.length
		return ffi.string(msg.ctype + offset - 1, length)
	else
		error("[data_copy] Input must be a string or cdata or Buffer")
		return tostring(msg)
	end
end

function t2n_client:drp_write(endpoint, flags, msg, length)
	local drp_cntx = self.drp_session[endpoint]
	if drp_cntx == nil then
		drp_cntx = {
			new_id = 0,
			ack_id = 0
		}
		self.drp_session[endpoint] = drp_cntx
	end
	if length > self.drp_mtu then
		local n = math.ceil(length / self.drp_mtu)
		if #self.drp_queue + n > 128 then
			return -3
		end
		for i = 1, n do
			drp_cntx.new_id = drp_cntx.new_id + 1
			if drp_cntx.new_id > 65535 then
				drp_cntx.new_id = 0
			end
			local offset = (i - 1) * self.drp_mtu + 1
			local tcf
			local len
			if i == 1 then
				tcf = DRP_FIRST_PACK
				len = self.drp_mtu
			elseif i == n then
				tcf = DRP_LAST_PACK
				len = length - self.drp_mtu * (n - 1)
			else
				tcf = DRP_MID_PACK
				len = self.drp_mtu
			end
			local drp_pack = {
				endpoint = endpoint,
				id = drp_cntx.new_id,
				tcf = tcf,
				length = len,
				data = data_copy(msg, offset, len),
				try_times = 5,
				timeout_cnt = -1
			}
			table.insert(self.drp_queue, drp_pack)
		end
	else
		if #self.drp_queue > 128 then
			return -2
		end
		drp_cntx.new_id = drp_cntx.new_id + 1
		if drp_cntx.new_id > 65535 then
			drp_cntx.new_id = 0
		end
		local tcp
		local try_times = 1
		if flags == 0 then
			tcf = DRP_NOACK_PACK
		else
			tcf = DRP_FULL_PACK
			try_times = 5
		end
		local drp_pack = {
			endpoint = endpoint,
			id = drp_cntx.new_id,
			tcf = tcf,
			length = length,
			data = data_copy(msg, 1, length),
			try_times = try_times,
			timeout_cnt = -1
		}
		table.insert(self.drp_queue, drp_pack)
	end
	uv.async_send(self.drp_send_async)
	return drp_cntx.new_id
end

function t2n_client:drp_on_req(ep, cb, is_b)
	local drp_cntx = self.drp_session[ep]
	if drp_cntx == nil then
		drp_cntx = {
			new_id = 0,
			ack_id = 0
		}
		self.drp_session[ep] = drp_cntx
	end
	if is_b ~= nil then
		drp_cntx.is_b = 1
	end
	drp_cntx.req_cb = cb
end

local cnt1 = 0

function t2n_client:drp_send_check()
	local cnt2 = 0
	if #self.drp_queue == 0 then
		return
	end
	local txbuf = Buffer:new(self.drp_mtu + 12)
	txbuf:write(1, "TDRP")
	local offset = 8
	local i = 1
	while (i <= #self.drp_queue) do
		v = self.drp_queue[i]
		if v.try_times > 0 then --
			if v.timeout_cnt > 0 then
				break
			end
			if (v.length + offset) > self.drp_mtu + 8 then
				if offset == 8 then
					table.remove(self.drp_queue)
					error("length to long drop it!!!")
				end
				break
			end
			txbuf:writeUInt8(offset, v.endpoint)
			offset = offset + 1
			txbuf:writeUInt16BE(offset, v.id)
			offset = offset + 2
			local tcf_len = gen_tcf_len(v.length, v.tcf)
			txbuf:writeUInt16BE(offset, tcf_len)
			offset = offset + 2
			txbuf:write(offset, v.data, v.length)
			offset = offset + v.length
			v.timeout_cnt = 6
			v.try_times = v.try_times - 1
			i = i + 1
			if v.tcf ~= DRP_FULL_PACK then
				break
			end
		else
			if v.tcf == DRP_FULL_PACK or v.tcf == DRP_NOACK_PACK then -- 如果是完整包
				table.remove(self.drp_queue, i) -- 删除当前值后面的会前移，下标不能增加
				print("remove DRP_SINGLE_PACK", i)
			else
				while v and v.tcf ~= DRP_FULL_PACK do
					table.remove(self.drp_queue, i)
					print("remove DRP_MUT_PACK", i)
					v = self.drp_queue[i]
				end
			end
		end
	end
	-- print("cnt2",i)
	if offset <= 8 then
		return
	end
	local data_sum = data_sum(txbuf, 9, offset - 9)
	txbuf:writeUInt16LE(5, data_sum)
	self.udp_handle:send(
		txbuf:toString(1, offset - 1),
		self.remote_ip,
		self.remote_port,
		function()
			if err ~= nil then
				print(err)
			-- client.close()
			end
		end
	)

	-- self.drp_wack = self.drp_wack + 1
	-- if self.drp_wack >= self.drp_win then
	self.drp_status = DRP_STATE_WAIT_ACK
	-- end
end

function t2n_client.ip2int(ip)
	local s, e, a, b, c, d = string.find(ip, "(%d+).(%d+).(%d+).(%d+)")
	local ret = bit.bor(bit.lshift(a, 24), bit.lshift(b, 16), bit.lshift(c, 8), d)
	return ret
end

return t2n_client
