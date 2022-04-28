local log = require("log.lua")
local t2n_client = require('t2n_client')
local remote = {ip='127.0.0.1',port=9999}
local t2n = t2n_client:new(remote)
log.info("t2n start...")
return t2n