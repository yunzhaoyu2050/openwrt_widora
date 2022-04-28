local fs = require("fs")
local json = require("json")

local _config_file_info = {
  server = {
    addr = nil,
    static_path = nil,
    port = nil
  },
  system = {
    cloud_ser_port = nil,
    log_level = nil,
    cloud_ser_addr = nil,
    log_path = nil,
    log_out_type = nil,
    cfg_file_path = nil,
    nmea_remote_port = nil,
    rtcm_remote_port = nil
  },
  dev = {
    gps_dev = nil,
    quectel_dev = nil,
    right_ant = nil,
    left_ant = nil
  },
  gps = {
    right_ant_avr_count = nil,
    left_ant_avr_count = nil
  }
}

local function _set_config_file(tcfg)
  if tcfg == nil then
    return -1
  end
  _config_file_info.server.addr = tcfg.server.addr or "127.0.0.1"
  _config_file_info.server.port = tcfg.server.port or 80
  _config_file_info.server.static_path = tcfg.server.static_path
  _config_file_info.system.cloud_ser_port = tcfg.system.cloud_ser_port
  _config_file_info.system.cloud_ser_addr = tcfg.system.cloud_ser_addr
  _config_file_info.system.log_level = tcfg.system.log_level or "error"
  _config_file_info.system.log_path = tcfg.system.log_path
  _config_file_info.system.log_out_type = tcfg.system.log_out_type or "terminal"
  _config_file_info.system.cfg_file_path = tcfg.system.cfg_file_path
  _config_file_info.system.nmea_remote_port = tcfg.system.nmea_remote_port or 6061
  _config_file_info.system.rtcm_remote_port = tcfg.system.rtcm_remote_port or 6060
  _config_file_info.dev.gps_dev = tcfg.dev.gps_dev or "/dev/ttyS1"
  _config_file_info.dev.quectel_dev = tcfg.dev.quectel_dev or "/dev/ttyUSB1"
  _config_file_info.dev.right_ant = tcfg.dev.right_ant or 19
  _config_file_info.dev.left_ant = tcfg.dev.left_ant or 18
  _config_file_info.gps.right_ant_avr_count = tcfg.gps.right_ant_avr_count or 6
  _config_file_info.gps.left_ant_avr_count = tcfg.gps.left_ant_avr_count or 6
  p(_config_file_info)
  return 0
end

-- 程序配置文件解析
-- @param ser_cfg_path 程序配置文件路径
-- @return 成功：0 失败：-1
local function _server_cfg_parse(ser_cfg_path)
  if ser_cfg_path == nil then
    return -1
  end
  local chunk, err = fs.readFileSync(ser_cfg_path)
  if err ~= nil or chunk == nil then
    return -1
  end
  local tmp = json.parse(chunk)
  local ret = _set_config_file(tmp)
  if ret < 0 then
    return -1
  end
  return 0
end

local function _get_config_file()
  return _config_file_info
end

function _get_server_ip()
  return _config_file_info.server.addr
end

function _get_server_port()
  return _config_file_info.server.port
end

function _get_static_path()
  return _config_file_info.server.static_path
end

function _get_cloud_ser_port()
  return _config_file_info.system.cloud_ser_port
end

function _get_cloud_ser_ip()
  return _config_file_info.system.cloud_ser_addr
end

function _get_log_level()
  return _config_file_info.system.log_level
end

function _get_log_path()
  return _config_file_info.system.log_path
end

function _get_log_out_type()
  return _config_file_info.system.log_out_type
end

function _get_cfg_file_path()
  return _config_file_info.system.cfg_file_path
end

function _get_nmea_remote_port()
  return _config_file_info.system.nmea_remote_port
end

function _get_rtcm_remote_port()
  return _config_file_info.system.rtcm_remote_port
end

function _get_gps_dev_port()
  return _config_file_info.dev.gps_dev
end

function _get_quectel_dev_port()
  return _config_file_info.dev.quectel_dev
end

function _get_right_ant_gpio()
  return _config_file_info.dev.right_ant
end

function _get_left_ant_gpio()
  return _config_file_info.dev.left_ant
end

function _get_right_ant_avr_count()
  return _config_file_info.gps.right_ant_avr_count
end

function _get_left_ant_avr_count()
  return _config_file_info.gps.left_ant_avr_count
end

return {
  _config_file_info = _config_file_info,
  _set_config_file = _set_config_file,
  _get_config_file = _get_config_file,
  _server_cfg_parse = _server_cfg_parse,
  get_server_ip = _get_server_ip,
  get_server_port = _get_server_port,
  get_static_path = _get_static_path,
  get_cloud_ser_port = _get_cloud_ser_port,
  get_cloud_ser_ip = _get_cloud_ser_ip,
  get_log_level = _get_log_level,
  get_log_path = _get_log_path,
  get_log_out_type = _get_log_out_type,
  get_cfg_file_path = _get_cfg_file_path,
  get_nmea_remote_port = _get_nmea_remote_port,
  get_rtcm_remote_port = _get_rtcm_remote_port,
  get_gps_dev_port = _get_gps_dev_port,
  get_quectel_dev_port = _get_quectel_dev_port,
  get_right_ant_gpio = _get_right_ant_gpio,
  get_left_ant_gpio = _get_left_ant_gpio,
  get_right_ant_avr_count = _get_right_ant_avr_count,
  get_left_ant_avr_count = _get_left_ant_avr_count
}
