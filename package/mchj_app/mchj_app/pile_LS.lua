local scfg = require("server_cfg.lua")
scfg._server_cfg_parse("./server.json")
local log = require("log.lua")
log.init()

local JSON = require("json")
local bl0939 = require("bl0939.lua")
local rtk_gps = require("mx_rtk.lua")
local t2n = require("t2n")
local trans = require("trans")
local Buffer = require("buffer").Buffer
local timer = require("timer")
local fs = require("fs")
local router = require("router")
local http = require("http")
local wss = require("websocketServer")

-- ========================================================================init start
bl0939.start()
log.info({info="start test"})
-- ========================================================================init end

local work_status = {
	idle = 0,
	start_work = 1,
	working = 2,
	end_work = 3,
	move = 4,
	sleep = 1
}

local function read_last_pile_id()
	local fd = fs.openSync("/root/last.txt", "r")
	if fd ~= nil then
		local s = fs.readSync(fd, 1024)
		if s ~= nil then
			local pile_id = string.match(s, "pile_id=(%d+)")
			log.info("last_pile_id", pile_id)
			return tonumber(pile_id)
		end
	end
end
-- function save_last(pile_id)
--   local fd = fs.openSync('/root/last.txt', 'w')
--   if fd ~= nil then
--     local s = fs.writeSync(fd,0,string.format("pile_id=%s",obj.pile_id))
--   end
-- end
local function save_last_pile_id(pile_id)
	local str = string.format("pile_id=%d", pile_id)
	fs.open(
		"/root/last.txt",
		"w",
		function(err, fd)
			if (err) then
				return err
			end
			fs.write(
				fd,
				0,
				str,
				function(err, bytes_written)
					if (err) then
						return err
					end
					fs.close(
						fd,
						function(err)
							if (err) then
								return err
							end
						end
					)
				end
			)
		end
	)
end

-- local  trans_param = {
--   dx= 484.3583,
--   dy= -1481.0470,
--   dz= -960.8897,
--   wx= -35.9495,
--   wy= 9.2898,
--   wz= 1501.7962,
--   k=274.3397,
--   datum = trans.WGS2000,
--   L0 = 105.4166,
--   height =1800
-- }
local trans_param = {
	dx = 0,
	dy = 0,
	dz = 0,
	wx = 0,
	wy = 0,
	wz = 0,
	k = 0,
	datum = trans.WGS2000,
	L0 = 105.416666667,
	height = 1600
}
local E_motor_config = {
	{start_value = 1000, stop_value = 200, debounce_threshold = 3}, --通道1填料
	{start_value = 1000, stop_value = 200, upper_value = 8000, normal_value = 5000, debounce_threshold = 3}, --通道2夯击
	{start_value = 1000, stop_value = 200, debounce_threshold = 2} --通道3行走
}
local E_motor_context = {
	{active_utc = 0, debounce_cnt = 0, state = 0, duration = 0, times = 0, on_time = 0, off_time = 0},
	{active_utc = 0, debounce_cnt = 0, state = 0, duration = 0, times = 0, upper_times = 0, on_time = 0, off_time = 0},
	{active_utc = 0, debounce_cnt = 0, state = 0, duration = 0, times = 0, on_time = 0, off_time = 0}
}

local machine_context = {
	pile_id = 0,
	depth = 0,
	start_time = os.time(),
	status = 0, --0 sleep 1 idle 2 start_work 3 working 4 end_work
	E_motor_move_times = 0 --电流符合行走条件次数
}

machine_context.pile_id = read_last_pile_id() or 0

local gps_contex = {
	left = {lat_sum = 0, lng_sum = 0, alt_sum = 0, lng = 0, lat = 0, alt = 0, sum_cnt = 0, fix_timeout = 0},
	right = {lat_sum = 0, lng_sum = 0, alt_sum = 0, lng = 0, lat = 0, alt = 0, sum_cnt = 0, fix_timeout = 0},
	other = {lat_sum = 0, lng_sum = 0, alt_sum = 0, lng = 0, lat = 0, alt = 0, sum_cnt = 0},
	pile = {lat = 0, lng = 0, alt = 0, status = 0, X = 0, Y = 0, H = 0, direction = 0},
	last_ant_chage_time = 0,
	gpstime = 0,
	lat = 0,
	lng = 0,
	alt = 0,
	status = 0,
	direction = 0,
	pile_location_req = 1,
	antenna = "none"
}

-- ==========================================================================bl0939 start

local function report_process_data(status, ctx)
	local xy = trans.d2p({B = gps_contex.lat, L = gps_contex.lng, H = gps_contex.alt}, trans_param)
	local process_data = {
		UTC = os.time(),
		X = xy.X,
		Y = xy.Y,
		Q = gps_contex.status,
		S = 0,
		pile_id = machine_context.pile_id,
		status = status, --事件ID 0空闲 2 开始填料 1 结束填料 4开始夯击，3结束夯击
		times = ctx.times, --同一根桩，相同事件第几次发生
		duration = ctx.duration, --单次持续时间单位20ms
		subtotal_time = 0,
		depth = machine_context.depth
	}

	if gps_contex.antenna == "left" then
		process_data.S = 1
	elseif gps_contex.antenna == "right" then
		process_data.S = 2
	end
	if ctx.state == 0 then
		process_data.subtotal_time = ctx.on_time * 0.02 --换成秒为单位
	else
		process_data.subtotal_time = ctx.off_time * 0.02 --换成秒为单位
	end
	if status == 5 or status == 6 then
		process_data.subtotal_time = process_data.subtotal_time * 10 --行走通道采集速度慢
		process_data.duration = process_data.duration * 10
	else
	end

	ws_send_broadcast(process_data)
	local unit_buf = Buffer:new(50)
	local offset = 1
	unit_buf:writeUInt32LE(offset, ctx.active_utc)
	offset = offset + 4
	unit_buf:writeUInt32LE(offset, process_data.X * 100)
	offset = offset + 4
	unit_buf:writeUInt32LE(offset, process_data.Y * 100)
	offset = offset + 4
	unit_buf:writeUInt8(offset, process_data.Q)
	offset = offset + 1

	unit_buf:writeUInt8(offset, process_data.S)
	offset = offset + 1
	unit_buf:writeUInt16LE(offset, process_data.pile_id)
	offset = offset + 2
	unit_buf:writeUInt8(offset, process_data.status)
	offset = offset + 1
	unit_buf:writeUInt8(offset, process_data.times)
	offset = offset + 1
	unit_buf:writeUInt16LE(offset, process_data.duration) --duration 0.02s
	offset = offset + 2
	unit_buf:writeUInt16LE(offset, process_data.subtotal_time)
	offset = offset + 2
	unit_buf:writeUInt16LE(offset, process_data.depth * 10)
	offset = offset + 2
	log.info("t2n:drp_write", offset - 1)
	t2n:drp_write(18, 2, unit_buf, offset - 1)
end

local function state_change_handle(ch, ctx, rms)
	log.info(string.format("ch %d", ch), ctx, rms)
	local now = os.time()
	-- report_process_data(ch,ctx)
	if ch == 3 then --行走电机状态变化，换桩判断---
		if ctx.state == 1 and ctx.duration > 40 then --情况1 行走电机连续运转超过4秒
			machine_context.E_motor_move_times = machine_context.E_motor_move_times + 1
		end
		report_process_data(5 + ctx.state, ctx)
	elseif ch == 2 then --夯击电机状态变化
		-- if ctx.state == 0 and  ctx.duration > 30*50 then   --停机超过30s
		-- elseif ctx.state == 1 and ctx.duration > 60*50 then   --停止,且连续运行超过1分钟
		-- end
		if ctx.duration > 10 * 50 then --连续运行超过10s 由于线路原因，行走电机运转时此通道也会有电流
			if machine_context.status ~= work_status.working then
				machine_context.status = work_status.working
				machine_context.start_time = os.time()
				gps_contex.pile_location_req = 1 --开始采集桩点位置
			end
			report_process_data(3 + ctx.state, ctx)
		end
	else --加料电机状态变化
		-- if ctx.state == 0 and  ctx.duration > 180*50 then   --停机且运行时间超过3分钟
		-- elseif ctx.state == 1 and ctx.duration > 60*50 then   --停止,且连续运行超过1分钟
		-- end
		if ctx.duration > 0.5 * 50 then --连续运行超过0.5s
			if machine_context.status ~= work_status.working then
				machine_context.status = work_status.working
				machine_context.start_time = os.time()
				gps_contex.pile_location_req = 1 --开始采集桩点位置
			end
			report_process_data(1 + ctx.state, ctx)
		end
	end
end

local count = 0

bl0939:on(
	"data",
	function(ac_rms)
		-- p("ac_rms:", ac_rms)
		local now = os.time()
		for ch, rms in ipairs(ac_rms) do
			local cfg = E_motor_config[ch]
			local ctx = E_motor_context[ch]
			for index, value in ipairs(rms) do
				if ctx.state == 0 then
					ctx.duration = ctx.duration + 1
					ctx.off_time = ctx.off_time + 1
					if value > cfg.start_value then
						ctx.debounce_cnt = ctx.debounce_cnt + 1
						if ctx.debounce_cnt >= cfg.debounce_threshold then
							state_change_handle(ch, ctx, rms)
							ctx.debounce_cnt = 0
							ctx.duration = 0
							ctx.active_utc = now
							ctx.state = 1
							ctx.times = ctx.times + 1
							if ctx.upper_value ~= nil then
								ctx.upper_times = 0
							end
						end
					else
						ctx.debounce_cnt = 0
					end
				elseif ctx.state == 1 then
					ctx.duration = ctx.duration + 1
					ctx.on_time = ctx.on_time + 1
					if value < cfg.stop_value then
						ctx.debounce_cnt = ctx.debounce_cnt + 1
						if ctx.debounce_cnt >= cfg.debounce_threshold then
							state_change_handle(ch, ctx, rms)
							ctx.debounce_cnt = 0
							ctx.duration = 0
							ctx.active_utc = now
							ctx.state = 0
						-- ctx.times = ctx.times +1
						end
					else
						if cfg.upper_value == nil then
							ctx.debounce_cnt = 0
						else
							if value > cfg.upper_value then
								ctx.debounce_cnt = ctx.debounce_cnt + 1
								if ctx.debounce_cnt >= cfg.debounce_threshold then
									ctx.debounce_cnt = 0
									ctx.active_utc = now
									ctx.state = 2
									ctx.upper_times = ctx.upper_times + 1
								end
							else
								ctx.debounce_cnt = 0
							end
						end
					end
				elseif ctx.state == 2 then
					ctx.duration = ctx.duration + 1
					ctx.on_time = ctx.on_time + 1
					if cfg.normal_value == nil then
						ctx.state = 1
					else
						if value < cfg.normal_value then
							ctx.debounce_cnt = ctx.debounce_cnt + 1
							if ctx.debounce_cnt >= cfg.debounce_threshold then
								ctx.debounce_cnt = 0
								ctx.active_utc = now
								ctx.state = 1
							end
						else
							ctx.debounce_cnt = 0
						end
					end
				else
					ctx.state = 0
					ctx.debounce_cnt = 0
				end
			end
		end
		count = count + 1
		if count > 5 then
			--  p(run_context)
			--  p(ac_rms)
			count = 0
		end
	end
)

-- ==========================================================================bl0939 end

-- ==========================================================================gps start

local function pile_location_calculate(gps_ctx)
	local left_BLH = gps_ctx.left
	local letf_xy = trans.d2p({B = left_BLH.lat, L = left_BLH.lng, H = left_BLH.alt}, trans_param)
	local right_BLH = gps_ctx.right
	local right_xy = trans.d2p({B = right_BLH.lat, L = right_BLH.lng, H = right_BLH.alt}, trans_param)
	local pile_xy = {
		X = (letf_xy.X + right_xy.X) / 2,
		Y = (letf_xy.Y + right_xy.Y) / 2,
		H = (letf_xy.H + right_xy.H) / 2
	}
	gps_ctx.pile.X = pile_xy.X
	gps_ctx.pile.Y = pile_xy.Y
	gps_ctx.pile.H = pile_xy.H
	local pile_BLH = trans.p2d(pile_xy, trans_param)
	local lineAngle = trans.lineAngle(letf_xy, right_xy) --直角坐标系和地理坐标系相差90度，方向相反
	gps_ctx.pile.direction = -lineAngle
	gps_ctx.pile.lng = pile_BLH.L
	gps_ctx.pile.lat = pile_BLH.B
	gps_ctx.pile.alt = pile_BLH.H
	p(gps_ctx.pile)
end

-- local function pile_location_req()
--   local clear = {"left","right","float","single"}
--   for _, value in ipairs(clear) do
--     local ctx = gps_contex[value]
--     for k, _ in pairs(ctx) do
--       ctx[k] = 0
--     end
--   end
--   gps_contex.pile_location_req = 0
-- end

rtk_gps:on(
	"data",
	function(gps_data)
		if gps_data.status == 4 and gps_contex.pile_location_req > 0 then
			local ctx = gps_contex[gps_data.antenna]
			--  p("gps_data",ctx)
			if ctx ~= nil then
				if gps_contex.antenna ~= gps_data.antenna then --切换了天线，重新开始计算平均值
					for k, _ in pairs(ctx) do
						ctx[k] = 0
					end
					gps_contex.antenna = gps_data.antenna
				end
				if gps_contex.pile_location_req == 1 then --请求获取桩点位置
					local clear = {"left", "right", "other"}
					for _, ant_key in ipairs(clear) do
						local ant_ctx = gps_contex[ant_key]
						for k, _ in pairs(ant_ctx) do --清空当前天线的所有值
							ant_ctx[k] = 0
						end
					end
					gps_contex.pile_location_req = 2
				end
				ctx.lat_sum = ctx.lat_sum + gps_data.lat
				ctx.lng_sum = ctx.lng_sum + gps_data.lng
				ctx.alt_sum = ctx.alt_sum + gps_data.alt
				ctx.sum_cnt = ctx.sum_cnt + 1
				if ctx.sum_cnt >= 10 then
					ctx.lng = ctx.lng_sum / ctx.sum_cnt
					ctx.lat = ctx.lat_sum / ctx.sum_cnt
					ctx.alt = ctx.alt_sum / ctx.sum_cnt
					if gps_contex.pile_location_req == 2 then --当前天线值采集完成
						rtk_gps.ant_change() --切换另一天线
						gps_contex.last_ant_chage_time = os.time()
						gps_contex.pile_location_req = 3
					elseif gps_contex.pile_location_req == 3 then --另一天线值采集完成
						pile_location_calculate(gps_contex) --计算桩点位置
						gps_contex.pile_location_req = 0 --桩点采集完成
					end
				end
			else
				rtk_gps.ant_change()
				gps_contex.last_ant_chage_time = os.time()
			end
		else
			local ctx = gps_contex.other
			ctx.lat_sum = ctx.lat_sum + gps_data.lat
			ctx.lng_sum = ctx.lng_sum + gps_data.lng
			ctx.alt_sum = ctx.alt_sum + gps_data.alt
			ctx.sum_cnt = ctx.sum_cnt + 1
			ctx.lng = ctx.lng_sum / ctx.sum_cnt
			ctx.lat = ctx.lat_sum / ctx.sum_cnt
			ctx.alt = ctx.alt_sum / ctx.sum_cnt
		end
		gps_contex.lat = gps_data.lat
		gps_contex.lng = gps_data.lng
		gps_contex.alt = gps_data.alt
		gps_contex.status = gps_data.status
		gps_contex.antenna = gps_data.antenna
		gps_contex.gpstime = gps_data.gpstime
		-- local blh = {B=gps_contex.lat,L=gps_contex.lng,H=gps_contex.alt}
		-- local xy = trans.d2p(blh,trans_param)
		-- p('xxxxxxxxxxxxxxxxxxyyyyyyyyyyyyyyyyyyyyyyyy',gps_data,blh,xy)
	end
)
rtk_gps:on(
	"timeout",
	function()
		log.warn("gps timeout")
		rtk_gps.ant_change()
		gps_contex.pile_location_req = 0
	end
)
-- ==========================================================================gps end

-- ==========================================================================check start
local function report_pile_data()
	local pile_data = {
		start_time = machine_context.start_time,
		end_time = os.time(),
		LNG = gps_contex.pile.lng,
		LAT = gps_contex.pile.lat,
		height = gps_contex.pile.alt,
		direction = gps_contex.pile.direction,
		gps_status = gps_contex.status,
		pile_id = machine_context.pile_id,
		depth = machine_context.depth,
		fill_on_time = E_motor_context[1].on_time,
		fill_off_time = E_motor_context[1].off_time,
		fill_cnt = E_motor_context[1].times,
		ram_time = E_motor_context[2].on_time,
		ram_cnt = E_motor_context[2].upper_times
	}

	if pile_data.LAT == 0 then
		pile_data.LAT = gps_contex.lat
		pile_data.LNG = gps_contex.lng
		pile_data.height = gps_contex.alt
	end
	ws_send_broadcast(pile_data)
	local buffer = Buffer:new(50)
	local offset = 1
	buffer:writeUInt32LE(offset, pile_data.start_time)
	offset = offset + 4
	buffer:writeUInt32LE(offset, pile_data.end_time)
	offset = offset + 4
	buffer:writeUInt32LE(offset, pile_data.LAT * 1000000000)
	offset = offset + 4
	buffer:writeUInt8(offset, pile_data.LAT * 1000000000 / 0x100000000)
	offset = offset + 1
	buffer:writeUInt32LE(offset, pile_data.LNG * 1000000000)
	offset = offset + 4
	buffer:writeUInt8(offset, pile_data.LNG * 1000000000 / 0x100000000)
	offset = offset + 1
	buffer:writeUInt32LE(offset, pile_data.height * 1000) --高度占3字节
	offset = offset + 3
	log.info(pile_data.height)
	-- buffer:writeUInt8(offset,pile_data.height*1000/0x10000)
	-- offset = offset+1
	buffer:writeUInt8(offset, pile_data.gps_status)
	offset = offset + 1
	buffer:writeInt16LE(offset, pile_data.direction * 10)
	offset = offset + 2
	buffer:writeUInt16LE(offset, pile_data.pile_id)
	offset = offset + 2
	buffer:writeUInt16LE(offset, pile_data.fill_on_time)
	offset = offset + 2
	buffer:writeUInt16LE(offset, pile_data.fill_off_time)
	offset = offset + 2
	buffer:writeUInt16LE(offset, pile_data.fill_cnt)
	offset = offset + 2
	buffer:writeUInt16LE(offset, pile_data.ram_time)
	offset = offset + 2
	buffer:writeUInt16LE(offset, pile_data.ram_cnt)
	offset = offset + 2
	buffer:writeUInt16LE(offset, pile_data.depth * 10)
	offset = offset + 2
	log.info("drp_write", offset - 1)
	t2n:drp_write(19, 2, buffer, offset - 1)
end
local function pile_work_done_check()
	if machine_context.status ~= work_status.working or (os.time() - machine_context.start_time) < 60 then --处于工作状态大于60秒
		return 0
	end
	report_pile_data()
	machine_context.status = work_status.idle
	machine_context.pile_id = machine_context.pile_id + 1
	save_last_pile_id(machine_context.pile_id)
	for ch, ctx in ipairs(E_motor_context) do
		ctx.active_utc = 0
		ctx.debounce_cnt = 0
		ctx.state = 0
		ctx.duration = 0
		ctx.times = 0
		ctx.on_time = 0
		ctx.off_time = 0
		if ch == 2 then
			ctx.upper_times = 0
		end
	end
end
local interval =
	timer.setInterval(
	1000,
	function()
		-- p(gps_contex.pile)
		ws_send_broadcast(gps_contex)
		-- local now = os.time()
		-- if(gps_contex.gpstime - now > 60) then --系统时间不准
		-- end
		if gps_contex.status == 4 then --若果定位正常，位置移动超过1M判定为上一个桩完成
			if gps_contex.pile.X ~= 0 and gps_contex.pile.Y ~= 0 then
				local xy = trans.d2p({B = gps_contex.lat, L = gps_contex.lng, H = gps_contex.alt}, trans_param)
				local distence = trans.distance(xy, gps_contex.pile)
				if distence > 1 then --位置发生变化超过1m
					if machine_context.E_motor_move_times > 0 then --并且行走电机有动作过
						pile_work_done_check()
					else
						local ramm_ctx = E_motor_context[2]
						local fill_ctx = E_motor_context[1]
						if ramm_ctx.state == 0 then --夯击电机出于停止状态 大概率判定换桩
							pile_work_done_check()
						else
							if fill_ctx.state == 0 and fill_ctx.duration > 20 * 50 then --填料电机20秒未填料
								pile_work_done_check()
							end
						end
					end
				end
			else
				gps_contex.pile_location_req = 1
			end
		else --gps 不正常情况
			if gps_contex.last_ant_chage_time > 0 and os.time() - gps_contex.last_ant_chage_time > 90 then --90秒未固定切换天线
				rtk_gps.ant_change()
				gps_contex.last_ant_chage_time = os.time()
			end
			if machine_context.E_motor_move_times > 0 then --并且行走电机有动作过
				local ramm_ctx = E_motor_context[2]
				local fill_ctx = E_motor_context[1]
				if fill_ctx.state == 0 and fill_ctx.duration > 20 * 50 then --填料电机20秒未填料
					pile_work_done()
				end
			end
		end
	end
)
log.info("timer check start...")
-- ==========================================================================check end

-- timer.setTimeout(3000, function ()
--   ws_send_broadcast("report_pile_data")
-- -- report_pile_data()
-- end)

-- ==========================================================================httpserver start
local app = router.newRouter()
log.info("router start...")
local ws_clients = {}
function ws_send_broadcast(msg)
	local str
	local msg_type = type(msg)

	if msg_type == "table" then
		str = JSON.stringify(msg)
	elseif msg_type == "string" then
		str = msg
	else
		str = msg.tostring()
	end
	for i, v in ipairs(ws_clients) do
		v:send(str)
	end
end
local function onRequest(req, res)
	if req.is_upgraded then
		wss.Handshake(
			req,
			res,
			function(ws)
				local addr = ws.socket:address()
				log.info(string.format("Client %d connected %s:%d", ws.id, addr.ip, addr.port))
				table.insert(ws_clients, ws)
				ws:on(
					"message",
					function(msg)
						p(msg)
						ws:send(msg)
					end
				)
				ws:on(
					"close",
					function()
						for i, v in ipairs(ws_clients) do
							if ws == v then
								table.remove(ws_clients, i)
								break
							end
						end
						log.info(string.format("Client %d closed", ws.id))
					end
				)
				ws:on(
					"error",
					function(err)
						for i, v in ipairs(ws_clients) do
							if ws == v then
								table.remove(ws_clients, i)
								break
							end
						end
						log.error(string.format("Client %d error msm=%s", ws.id, err.message))
					end
				)
			end
		)
	else
		req.path = req.url
		log.info(req.url)
		app.run(
			req,
			res,
			function()
				local body = "Not fund\n"
				res.statusCode = 404
				res:setHeader("Content-Type", "text/plain")
				res:setHeader("Content-Length", #body)
				res:finish(body)
			end
		)
	end
end

app.route(
	{
		method = "GET",
		path = "/trans_param"
	},
	function(req, res)
		local body = JSON.stringify(trans_param)
		res:setHeader("Content-Type", "application/json")
		res:setHeader("Content-Length", #body)
		res:finish(body)
	end
)
app.route(
	{
		method = "GET",
		path = "/motor_cfg"
	},
	function(req, res)
		local body = JSON.stringify(E_motor_config)
		res:setHeader("Content-Type", "application/json")
		res:setHeader("Content-Length", #body)
		res:finish(body)
	end
)

app.route(
	{
		method = "GET",
		path = "/motor_ctx"
	},
	function(req, res)
		if req.query ~= nil and req.query.report_process_data ~= nil then
			local status = tonumber(req.query.report_process_data) or 0
			report_process_data(status, E_motor_context[math.floor(status / 2) + 1])
		end
		local body = JSON.stringify(E_motor_context)
		res:setHeader("Content-Type", "application/json")
		res:setHeader("Content-Length", #body)
		res:finish(body)
	end
)

app.route(
	{
		method = "GET",
		path = "/machine_ctx"
	},
	function(req, res)
		if req.query ~= nil and req.query.report_pile_data ~= nil then
			machine_context.start_time = os.time()
			report_pile_data()
		end
		local body = JSON.stringify(machine_context)
		res:setHeader("Content-Type", "application/json")
		res:setHeader("Content-Length", #body)
		res:finish(body)
	end
)

app.route(
	{
		method = "GET",
		path = "/gps_ctx"
	},
	function(req, res)
		if req.query ~= nil and req.query.pile_location_req ~= nil then
			local value = req.query.pile_location_req
			gps_contex.pile_location_req = tonumber(value)
		end
		local body = JSON.stringify(gps_contex)
		res:setHeader("Content-Type", "application/json")
		res:setHeader("Content-Length", #body)
		res:finish(body)
	end
)

http.createServer(onRequest):listen(88)
-- ==========================================================================httpserver end
-- local timer = time.settim
