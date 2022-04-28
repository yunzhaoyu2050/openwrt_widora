local log = require("log.lua")
local process = require("childprocess")
local JSON = require("json")
local Emitter = require("core").Emitter
local emitter = Emitter:new()
local child

emitter.start = function()
	child = process.spawn("/root/spidev_bl0939", {}, {})
	local function onStdout(data)
		log.debug("bl0939 recv data:", data)
		local raw_data = JSON.parse(data)
		local rms_cha = {}
		for index, value in ipairs(raw_data[1]) do
			rms_cha[index] = math.floor(value * 1.218 / 228422 * 2000)
		end
		local rms_chb = {}
		for index, value in ipairs(raw_data[2]) do
			rms_chb[index] = math.floor(value * 1.218 / 228422 * 2000)
		end
		local rms_chc = {}
		rms_chc[1] = math.floor(raw_data[3] * 1.218 / 162002 * 2000)
		emitter:emit("data", {rms_cha, rms_chb, rms_chc})
	end
	local function onExit(code, signal)
		emitter:emit("exit", code, signal)
	end
	local function onEnd()
		child.stdin:destroy()
		emitter:emit("end")
	end
	local function onError(err)
		assert(err)
		emitter:emit("err", err)
	end
	child.stdout:once("end", onEnd)
	child.stdout:on("data", onStdout)
	child.stdout:on("error", onError)
	child.stderr:once("end", onEnd)
	child.stderr:on("error", onError)
	child.stderr:on("data", onStdout)
	child:on("exit", onExit)
	child:on("close", onExit)
	log.info("bl0939 start...")
end

emitter.stop = function()
	child.stdin:write("\17")
	process.kill(child.pid)
end

return emitter
