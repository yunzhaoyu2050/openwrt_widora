local netmod = luci.model.network
local interface = luci.model.network.interface
local proto = netmod:register_protocol("t2n")

function proto.get_i18n(self)
	return luci.i18n.translate("T2N VPN")
end

function proto.ifname(self)
	return "t2n-" .. self.sid
end

function proto.opkg_package(self)
	return "t2n-edge"
end

function proto.is_installed(self)
	return nixio.fs.access("/lib/netifd/proto/t2n.sh")
end

function proto.is_floating(self)
	return true
end

function proto.is_virtual(self)
	return true
end

function proto.get_interfaces(self)
	return nil
end

function proto.contains_interface(self, ifc)
	 return (netmod:ifnameof(ifc) == self:ifname())
end

netmod:register_pattern_virtual("^t2n-%w")
