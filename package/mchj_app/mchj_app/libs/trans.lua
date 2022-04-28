local trans = {}

-- 七参数转换
-- 不同椭球参数下， 地心直角坐标系之间转换
-- dX, dY, dZ: 三个坐标方向的平移参数
-- wX, wY, wZ: 三个方向的旋转角参数(单位为弧度)
-- Kppm: 尺度参数， 单位是ppm，如果是以米为单位， 需要在传参前 除以1000000
function XYZ2XYZ(source, dX, dY, dZ, wX, wY, wZ, Kppm)
	local X = source.X
	local Y = source.Y
	local Z = source.Z
	wX = wX or 0
	wY = wY or 0
	wZ = wZ or 0
	Kppm = Kppm or 0
	Kppm = Kppm / 1000000
	wX = wX / 3600 / 180 * math.pi
	wY = wY / 3600 / 180 * math.pi
	wZ = wZ / 3600 / 180 * math.pi

	--   // wX = wX / math.PI * 3600 * 180
	--   // wY = wY / math.PI * 3600 * 180
	--   // wZ = wZ / math.PI * 3600 * 180
	--   // Kppm = Kppm - 1
	local destX = X + dX + Kppm * X - wY * Z + wZ * Y
	local destY = Y + dY + Kppm * Y + wX * Z - wZ * X
	local destZ = Z + dZ + Kppm * Z - wX * Y + wY * X

	return {
		X = destX,
		Y = destY,
		Z = destZ
	}
end

-- 地心大地坐标系 转换到 地心直角坐标系

function BLH2XYZ(pointBLH, datum)
	local a = datum.A
	local e12 = datum.E12
	local radB = pointBLH.B / 180 * math.pi
	local radL = pointBLH.L / 180 * math.pi
	local H = pointBLH.H

	local N = a / math.sqrt(1 - e12 * math.sin(radB) * math.sin(radB)) -- 卯酉圈半径

	local X = (N + H) * math.cos(radB) * math.cos(radL)
	local Y = (N + H) * math.cos(radB) * math.sin(radL)
	local Z = (N * (1 - e12) + H) * math.sin(radB)

	return {
		X = X,
		Y = Y,
		Z = Z
	}
end

-- /*
--   地心直角坐标系 转换到 地心大地坐标系
--   用直接法2
--   https://wenku.baidu.com/view/30a08f9ddd88d0d233d46a50.html
-- */
function XYZ2BLH(pointXYZ, datum)
	local X = pointXYZ.X
	local Y = pointXYZ.Y
	local Z = pointXYZ.Z

	local L = math.atan(Y / X)
	-- 弧度转角度
	local degL = L * 180 / math.pi
	-- Y值为正， 东半球， 否则西半球
	if (Y > 0) then
		while (degL < 0) do
			degL = degL + 180
		end
		while (degL > 180) do
			degL = degL - 180
		end
	else
		while (degL > 0) do
			degL = degL - 180
		end
		while (degL < -180) do
			degL = degL + 180
		end
	end

	local a = datum.A
	local b = datum.B
	local e12 = datum.E12
	local e22 = datum.E22

	local tgU = Z / (math.sqrt(X * X + Y * Y) * math.sqrt(1 - e12))
	local U = math.atan(tgU)

	local tgB = (Z + b * e22 * math.pow(math.sin(U), 3)) / (math.sqrt(X * X + Y * Y) - a * e12 * math.pow(math.cos(U), 3))
	local B = math.atan(tgB)
	local degB = B * 180 / math.pi -- 弧度转角度
	if (Z > 0) then -- Z值为正， 北半球， 否则南半球
		while (degB < 0) do
			degB = degB + 90
		end
		while (degB > 90) do
			degB = degB - 90
		end
	else
		while (degB > 0) do
			degB = degB - 90
		end
		while (degB < -90) do
			degB = degB + 90
		end
	end

	while (degB < 0) do
		degB = degB + 360
	end
	while (degB > 360) do
		degB = degB - 360
	end

	local N = a / math.sqrt(1 - e12 * math.sin(B) * math.sin(B)) -- 卯酉圈半径
	local H = 0
	-- B接近极区， 在±90°附近
	if (math.abs(degB) > 80) then
		H = Z / math.sin(B) - N * (1 - e12)
	else
		H = math.sqrt(X * X + Y * Y) / math.cos(B) - N
	end
	return {
		B = degB,
		L = degL,
		H = H
	}
end

-- /*
--   地心大地坐标系 转换到 大地平面坐标系
--   prjHeight: 投影面高程
--   http://www.cnblogs.com/imeiba/p/5696967.html
-- */
local function BL2xy(pointBLH, datum, prjHeight, L0, offsetX, offsetY)
	local a = datum.A
	local b = datum.B
	local e12 = datum.E12
	local e22 = datum.E22
	prjHeight = prjHeight or 0
	offsetX = offsetX or 0
	offsetY = offsetY or 500000
	-- local L0 = datum.L0
	if L0 == nil or L0 == 0 then
		local zoneNo = math.floor((pointBLH.L + 1.5) / 3)
		L0 = (zoneNo - 0.5) * datum.zoneWidth
	end
	local radL0 = L0 / 180 * math.pi

	local radB = pointBLH.B / 180 * math.pi
	local radL = pointBLH.L / 180 * math.pi

	local N = a / math.sqrt(1 - e12 * math.sin(radB) * math.sin(radB)) -- 卯酉圈半径
	local T = math.tan(radB) * math.tan(radB)
	local C = e22 * math.cos(radB) * math.cos(radB)
	local A = (radL - radL0) * math.cos(radB)
	local M =
		a *
		((1 - e12 / 4 - 3 * e12 * e12 / 64 - 5 * e12 * e12 * e12 / 256) * radB -
			(3 * e12 / 8 + 3 * e12 * e12 / 32 + 45 * e12 * e12 * e12 / 1024) * math.sin(2 * radB) +
			(15 * e12 * e12 / 256 + 45 * e12 * e12 * e12 / 1024) * math.sin(4 * radB) -
			(35 * e12 * e12 * e12 / 3072) * math.sin(6 * radB))

	--x,y的计算公式见孔祥元等主编武汉大学出版社2002年出版的《控制测量学》的第72页
	--书的的括号有问题，( 和 [ 应该交换

	local x =
		M +
		N * math.tan(radB) *
			(A * A / 2 + (5 - T + 9 * C + 4 * C * C) * A * A * A * A / 24 +
				(61 - 58 * T + T * T + 600 * C - 330 * e22) * A * A * A * A * A * A / 720)
	local y = N * (A + (1 - T + C) * A * A * A / 6 + (5 - 18 * T * T * T + 72 * C - 58 * e22) * A * A * A * A * A / 120)

	x = offsetX + x * (b + prjHeight) / b
	y = offsetY + y * (b + prjHeight) / b

	return {
		X = x,
		Y = y,
		H = pointBLH.H
	}
end

-- /*
--   大地平面坐标系 转换到 地心大地坐标系
--   prjHeight: 投影面高程
--   http://www.cnblogs.com/imeiba/p/5696967.html
-- */
local function xy2BL(pointxy, datum, prjHeight, L0, offsetX, offsetY)
	local a = datum.A
	local b = datum.B
	local e12 = datum.E12
	local e22 = datum.E22
	prjHeight = prjHeight or 0
	offsetX = offsetX or 0
	offsetY = offsetY or 500000
	local e1 = (1 - math.sqrt(1 - e12)) / (1 + math.sqrt(1 - e12))
	-- local L0 = datum.L0
	local radL0 = L0 / 180 * math.pi
	-- 带内大地坐标
	local Y = pointxy.Y % 1000000
	local x = (pointxy.X - offsetX) * b / (b + prjHeight)
	local y = (Y - offsetY) * b / (b + prjHeight)

	local u = x / (a * (1 - e12 / 4 - 3 * e12 * e12 / 64 - 5 * e12 * e12 * e12 / 256))
	local fai =
		u + (3 * e1 / 2 - 27 * e1 * e1 * e1 / 32) * math.sin(2 * u) +
		(21 * e1 * e1 / 16 - 55 * e1 * e1 * e1 * e1 / 32) * math.sin(4 * u) +
		(151 * e1 * e1 * e1 / 96) * math.sin(6 * u) +
		(1097 * e1 * e1 * e1 * e1 / 512) * math.sin(8 * u)
	local C = e22 * math.cos(fai) * math.cos(fai)
	local T = math.tan(fai) * math.tan(fai)
	local N = a / math.sqrt(1 - e12 * math.sin(fai) * math.sin(fai))
	local R =
		a * (1 - e12) /
		math.sqrt(
			(1 - e12 * math.sin(fai) * math.sin(fai)) * (1 - e12 * math.sin(fai) * math.sin(fai)) *
				(1 - e12 * math.sin(fai) * math.sin(fai))
		)
	local D = y / N

	local L =
		radL0 +
		(D - (1 + 2 * T + C) * D * D * D / 6 +
			(5 - 2 * C + 28 * T - 3 * C * C + 8 * e22 + 24 * T * T) * D * D * D * D * D / 120) /
			math.cos(fai)
	local B =
		fai -
		(N * math.tan(fai) / R) *
			(D * D / 2 - (5 + 3 * T + 10 * C - 4 * C * C - 9 * e22) * D * D * D * D / 24 +
				(61 + 90 * T + 298 * C + 45 * T * T - 256 * e22 - 3 * C * C) * D * D * D * D * D * D / 720)

	B = B * 180 / math.pi
	L = L * 180 / math.pi
	return {
		B = B,
		L = L,
		H = pointxy.H
	}
end

-- local BJ54 = new Datum(6378245, 1/298.3)
-- local XA80 = new Datum(6378140, 1/298.257)
-- local WGS84 = new Datum(6378137, 1/298.257223563)
-- local WGS2000 = new Datum(6378137, 1/298.257222101)
local function datum_new(a, f, L0)
	local self = {}
	local b = a - f * a
	local e12 = (a * a - b * b) / (a * a) --// 第一偏心率平方
	local e22 = (a * a - b * b) / (b * b) --// 第二偏心率平方
	self.A = a
	self.F = f
	self.B = b
	self.E12 = e12
	self.E22 = e22
	self.L0 = L0
	self.zoneWidth = 3
	return self
end
--输出平面坐标
function trans.d2p(blh, config)
	-- local zj = BLH2XYZ(p, WGS84)
	local zj = BLH2XYZ(blh, config.datum)
	-- p("BLH2XYZ",zj)
	local xzj = XYZ2XYZ(zj, config.dx, config.dy, config.dz, config.wx, config.wy, config.wz, config.k)
	-- p("XYZ2XYZ",xzj)
	local xdd = XYZ2BLH(xzj, config.datum)
	-- p("XYZ2BLH",xdd)
	local xpm = BL2xy(xdd, config.datum, config.height, config.L0)
	-- p("BL2xy",xpm)
	return xpm
end

--输出大地坐标
function trans.p2d(pointxy, config)
	local bl = xy2BL(pointxy, config.datum, config.height, config.L0)
	local zj = BLH2XYZ(bl, config.datum)
	local xzj = XYZ2XYZ(zj, -config.dx, -config.dy, -config.dz, -config.wx, -config.wy, -config.wz, -config.k)
	-- local xdd = XYZ2BLH(xzj, WGS84)
	local xdd = XYZ2BLH(xzj, config.datum)
	return xdd
end

--两点之间的距离公式
function trans.distance(p1, p2)
	local d = math.sqrt(math.pow((p2.X - p1.X), 2) + math.pow((p2.Y - p1.Y), 2))
	return d
end

--求坐标方位角
function trans.lineAngle(p1, p2)
	local dx = p2.X - p1.X
	local dy = p2.Y - p1.Y
	return math.atan2(dx, dy) * 180 / math.pi
end

trans.BJ54 = datum_new(6378245, 1 / 298.3)
trans.XA80 = datum_new(6378140, 1 / 298.257)
trans.WGS84 = datum_new(6378137, 1 / 298.257223563)
trans.WGS2000 = datum_new(6378137, 1 / 298.257222101)
return trans
