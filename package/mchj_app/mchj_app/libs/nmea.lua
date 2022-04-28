--function string.split( str,reps )
--    local resultStrList = {}
--    string.gsub(str,'[^'..reps..']+',function ( w )
--        p(w)
--        table.insert(resultStrList,w)
--    end)
--    return resultStrList
--end
local log = require("log.lua")
local gns_info = {ESV = {}, GSV = {}, BSV = {}, RSV = {}}
local gngsv = {}
local gngsa = {{}, {}, {}, {}}
local sv_names = {"GSV", "RSV", "ESV", "BSV"}

local function indexOf(arr, value)
	for i, v in ipairs(arr) do
		if v == value then
			return i
		end
	end
	return -1
end

string.split = function(szFullString, szSeparator)
	local nFindStartIndex = 1
	local nSplitIndex = 1
	local nSplitArray = {}
	while true do
		local nFindLastIndex = string.find(szFullString, szSeparator, nFindStartIndex)
		if not nFindLastIndex then
			nSplitArray[nSplitIndex] = string.sub(szFullString, nFindStartIndex, string.len(szFullString))
			break
		end
		nSplitArray[nSplitIndex] = string.sub(szFullString, nFindStartIndex, nFindLastIndex - 1)
		nFindStartIndex = nFindLastIndex + string.len(szSeparator)
		nSplitIndex = nSplitIndex + 1
	end
	return nSplitArray
end

local function pos_convert(pos)
	local degree = 0
	local minute = 0
	if pos ~= nil and #pos > 0 then
		local minute_zero = 0
		local scale = 0
		local i = 1
		local n = 0
		while ((string.byte(pos, i) >= 48) and (string.byte(pos, i) <= 57)) do
			n = n * 10 + string.byte(pos, i) - 48
			i = i + 1
			if (string.byte(pos, i) == nil) then
				break
			end
		end
		degree = math.floor(n / 100)
		minute = n % 100

		if ((string.byte(pos, i) == 46) and (string.byte(pos, i + 1) >= 48) and (string.byte(pos, i + 1) <= 57)) then
			i = i + 1
			while ((string.byte(pos, i) >= 48) and (string.byte(pos, i) <= 57)) do
				minute_zero = minute_zero + (string.byte(pos, i) - 48) * math.pow(0.1, scale + 1)

				if (scale >= 9) then
					break
				end
				scale = scale + 1
				i = i + 1
				if (string.byte(pos, i) == nil) then
					break
				end
			end
		end

		minute = math.floor((minute + minute_zero) * 1000000000 / 60)
		-- return degree*1000000000 + minute;
		return (degree * 1000000000 + minute) / 1000000000
	end
end

local function data_time_utc(date_str, time_str)
	if (date_str ~= nil and #date_str >= 6) and (time_str ~= nil and #time_str >= 6) then
		local gps_time = {}
		gps_time.hour = string.sub(time_str, 1, 2) * 1
		gps_time.min = string.sub(time_str, 3, 4) * 1
		gps_time.sec = string.sub(time_str, 5, 6) * 1
		gps_time.year = string.sub(date_str, 5, 6) * 1 + 2000
		gps_time.month = string.sub(date_str, 3, 4) * 1
		gps_time.day = string.sub(date_str, 1, 2) * 1
		local gps_utc = os.time(gps_time)
		return gps_utc
	end
end
local function hex2byte(ch)
	if ch >= 48 and ch <= 57 then
		return ch - 48
	elseif ch >= 65 and ch <= 70 then
		return ch - 48 - 7
	else
		return 0
	end
end

local function gps_check(str)
	local end_pos = string.find(str, "*")
	if end_pos ~= nil then
		local m = bit.bxor(string.byte(str, 2, end_pos - 1))
		local n = hex2byte(string.byte(str, end_pos + 1)) * 16 + hex2byte(string.byte(str, end_pos + 2))
		if m == n then
			return 0
		else
			log.info(string.format("calc:%02x,read:%02x", m, n))
		end
	end
	log.error("check error!")
	return -1
end

local function get_gps(gps_str, gps_data)
	local gps = {}
	if gps_check(gps_str) ~= 0 then
		return -2
	end
	--print(gps_str)
	local list = string.split(gps_str, ",")
	if gps_data.last_g == list[1] then
		gps_data.repeat_cnt = gps_data.repeat_cnt + 1
	else
		gps_data.last_g = list[1]
		gps_data.repeat_cnt = 0
	end

	if (list[1] == "$GNRMC" or list[1] == "$GPRMC") then --建议使用最小GPS数据格式s
		gps_data.time = list[2]
		gps_data.available = list[3]
		gps_data.lat = list[4]
		gps_data.n_s = list[5]
		gps_data.lng = list[6]
		gps_data.e_w = list[7]
		gps_data.speed = list[8]
		gps_data.course = list[9]
		gps_data.date = list[10]
		return 1
	elseif (list[1] == "$GNGGA" or list[1] == "$GPGGA") then --GPS固定数据输出语句
		gps_data.status = list[7]
		gps_data.sv_in_use = list[8]
		gps_data.hdop = list[9]
		gps_data.alt = list[10]
		gps_data.undulation = list[12]
		return 2
	elseif (list[1] == "$GNGSA" or list[1] == "$GPGSA") then
		local sa = {}
		--p(list)
		for i = 4, #list - 4 do
			if list[i] == "" then
				break
			end
			sa[i - 3] = tonumber(list[i] or 0)
		end
		gngsa[gps_data.repeat_cnt + 1] = sa
	elseif (list[1] == "$GPGSV") then
		if gps_data.repeat_cnt == 0 then
			gngsv[1] = {}
		end
		local gsv = gngsv[1]
		local total = tonumber(list[2])
		local page = tonumber(list[3])
		for i = 5, #list - 4, 4 do
			local sn = tonumber(list[i])
			local idx = (page - 1) * 4 + (i - 5) / 4 + 1
			if gps_data.repeat_cnt < total then
				gsv[idx] = {
					SN = sn,
					EA = tonumber(list[i + 1]) or 0,
					AA = tonumber(list[i + 2]) or 0,
					L1 = tonumber(list[i + 3]) or 0
				}
			else
				if gsv[idx] ~= nil then
					gsv[idx].L2 = tonumber(list[i + 3]) or 0
				else
					gsv[idx] = {
						SN = sn,
						ea = tonumber(list[i + 1]) or 0,
						AA = tonumber(list[i + 2]) or 0,
						L1 = 0,
						L2 = tonumber(list[i + 3]) or 0
					}
				end
			end
		end
	elseif (list[1] == "$GNHDT") then
		gps_data.heading = list[2]
	elseif (list[1] == "$GLGSV") then
		if gps_data.repeat_cnt == 0 then
			gngsv[2] = {}
		end
		local rsv = gngsv[2]
		local total = tonumber(list[2])
		local page = tonumber(list[3])
		for i = 5, #list - 4, 4 do
			local sn = tonumber(list[i])
			local idx = (page - 1) * 4 + (i - 5) / 4 + 1
			if gps_data.repeat_cnt < total then
				rsv[idx] = {
					SN = sn,
					EA = tonumber(list[i + 1]) or 0,
					AA = tonumber(list[i + 2]) or 0,
					L1 = tonumber(list[i + 3]) or 0
				}
			else
				if rsv[idx] ~= nil then
					rsv[idx].L2 = tonumber(list[i + 3]) or 0
				else
					rsv[idx] = {
						SN = sn,
						EA = tonumber(list[i + 1]) or 0,
						AA = tonumber(list[i + 2]) or 0,
						L1 = 0,
						L2 = tonumber(list[i + 3]) or 0
					}
				end
			end
		end
	elseif (list[1] == "$GAGSV") then
		if gps_data.repeat_cnt == 0 then
			gngsv[3] = {}
		end
		local esv = gngsv[3]
		local total = tonumber(list[2])
		local page = tonumber(list[3])
		for i = 5, #list - 4, 4 do
			local sn = tonumber(list[i])
			local idx = (page - 1) * 4 + (i - 5) / 4 + 1
			if gps_data.repeat_cnt < total then
				esv[idx] = {
					SN = sn,
					EA = tonumber(list[i + 1]) or 0,
					AA = tonumber(list[i + 2]) or 0,
					L1 = tonumber(list[i + 3]) or 0
				}
			else
				if esv[idx] ~= nil then
					esv[idx].L2 = tonumber(list[i + 3]) or 0
				else
					esv[idx] = {
						SN = sn,
						EA = tonumber(list[i + 1]) or 0,
						AA = tonumber(list[i + 2]) or 0,
						L1 = 0,
						L2 = tonumber(list[i + 3]) or 0
					}
				end
			end
		end
	elseif (list[1] == "$GBGSV") then
		if gps_data.repeat_cnt == 0 then
			gngsv[4] = {}
		end
		local bsv = gngsv[4]
		local total = tonumber(list[2])
		local page = tonumber(list[3])
		for i = 5, #list - 4, 4 do
			local sn = tonumber(list[i])
			local idx = (page - 1) * 4 + (i - 5) / 4 + 1
			if gps_data.repeat_cnt < total then
				bsv[idx] = {
					SN = sn,
					EA = tonumber(list[i + 1]) or 0,
					AA = tonumber(list[i + 2]) or 0,
					L1 = tonumber(list[i + 3]) or 0
				}
			else
				if bsv[idx] ~= nil then
					bsv[idx].L2 = tonumber(list[i + 3]) or 0
				else
					bsv[idx] = {
						SN = sn,
						EA = tonumber(list[i + 1]) or 0,
						AA = tonumber(list[i + 2]) or 0,
						L1 = 0,
						L2 = tonumber(list[i + 3]) or 0
					}
				end
			end
		end
	elseif (list[1] == "$GNGLL") then --ublox last nmea
		for i, sv in ipairs(gngsv) do
			local index = 1
			local name = sv_names[i]
			for _, v in ipairs(sv) do
				if v.L1 and v.L1 > 0 or v.L2 and v.L2 > 0 then
					v.use = indexOf(gngsa[i], v.SN) > 0 and 1 or 0
					gns_info[name][index] = v
					index = index + 1
				end
			end
			while #gns_info[name] > index do
				table.remove(gns_info[name], #gns_info[name])
			end
		end
	end

	return 0
end

local gps_raw = {last_g = "", repeat_cnt = 0, sv = {}}

local function parse_nmea(nmea_msg, gps_data)
	-- local lines = string.split(nmea_msg,'\r\n')
	-- for n = 1,#lines do
	--print(lines[n])
	--   get_gps(lines[n],gps_raw)
	-- end
	--p(gps_raw)
	if get_gps(nmea_msg, gps_raw) <= 0 then
		return 0
	end
	if (gps_raw.n_s == "N") then
		gps_data.lat = pos_convert(gps_raw.lat) or 0
	elseif (gps_raw.n_s == "S") then
		gps_data.lat = (pos_convert(gps_raw.lat) or 0) * -1
	else
		gps_data.lat = 0
	end
	if (gps_raw.e_w == "E") then
		gps_data.lng = pos_convert(gps_raw.lng) or 0
	elseif (gps_raw.e_w == "W") then
		gps_data.lng = (pos_convert(gps_raw.lng) or 0) * -1
	else
		gps_data.lng = 0
	end
	gps_data.alt = ((tonumber(gps_raw.alt) or 0) + (tonumber(gps_raw.undulation) or 0))
	gps_data.gpstime = data_time_utc(gps_raw.date, gps_raw.time) or 0
	gps_data.direction = math.ceil(tonumber(gps_raw.course) or 0)
	if gps_raw.heading ~= nil then
	end
	gps_data.speed = math.ceil((tonumber(gps_raw.speed) or 0) * 1852) / 1000
	gps_data.status = tonumber(gps_raw.status) or 0
	gps_data.hdop = tonumber(gps_raw.hdop) or 999
	gps_data.sv_in_use = tonumber(gps_raw.sv_in_use) or 0
	gns_info.lat = gps_data.lat
	gns_info.lng = gps_data.lng
	gns_info.alt = gps_data.alt
	gns_info.time = gps_data.gpstime
	gns_info.direction = gps_data.direction
	gns_info.speed = gps_data.speed
	gns_info.status = gps_data.status
	gns_info.hdop = gps_data.hdop
	gns_info.use = #gngsa[1] + #gngsa[2] + #gngsa[3] + #gngsa[4]
	gns_info.view = #gns_info.GSV + #gns_info.RSV + #gns_info.ESV + #gns_info.BSV
	return gps_data
end

return {
	parse = parse_nmea,
	raw_data = gps_raw,
	gns_info = gns_info
}
