module("L_RGBController1", package.seeall)

-- Imports
local json = require("dkjson")
if (type(json) == "string") then
	json = require("json")
end

-------------------------------------------
-- Constants
-------------------------------------------

local DID = {
	ARDUINO = "urn:schemas-arduino-cc:device:arduino:1",
	RGB_CONTROLLER = "urn:schemas-upnp-org:device:RGBController:1"
}

local SID = {
	SWITCH = "urn:upnp-org:serviceId:SwitchPower1",
	DIMMER = "urn:upnp-org:serviceId:Dimming1",
	ZWAVE_NETWORK = "urn:micasaverde-com:serviceId:ZWaveNetwork1",
	ARDUINO = "urn:upnp-arduino-cc:serviceId:arduino1",
	RGB_CONTROLLER = "urn:upnp-org:serviceId:RGBController1"
}

-------------------------------------------
-- Plugin constants
-------------------------------------------

_NAME = "RGBController"
_DESCRIPTION = ""
_VERSION = "1.34"

-------------------------------------------
-- Plugin variables
-------------------------------------------

local _params = {}

-------------------------------------------
-- UI compatibility
-------------------------------------------

-- Update static JSON file
local function _updateStaticJSONFile (lul_device, pluginName)
	local isUpdated = false
	if (luup.version_branch ~= 1) then
		luup.log("ERROR - Plugin '" .. pluginName .. "' - checkStaticJSONFile : don't know how to do with this version branch " .. tostring(luup.version_branch), 1)
	elseif (luup.version_major > 5) then
		local currentStaticJsonFile = luup.attr_get("device_json", lul_device)
		local expectedStaticJsonFile = "D_" .. pluginName .. "_UI" .. tostring(luup.version_major) .. ".json"
		if (currentStaticJsonFile ~= expectedStaticJsonFile) then
			luup.attr_set("device_json", expectedStaticJsonFile, lul_device)
			isUpdated = true
		end
	end
	return isUpdated
end

-------------------------------------------
-- Tool functions
-------------------------------------------

-- Get variable value and init if value is nil
local function _getVariableOrInit (lul_device, serviceId, variableName, defaultValue)
	local value = luup.variable_get(serviceId, variableName, lul_device)
	if (value == nil) then
		luup.variable_set(serviceId, variableName, defaultValue, lul_device)
		value = defaultValue
	end
	return value
end

local function log(object, methodName, text, level)
	if (type(object) == "table") then
		methodName = tostring(object._name) .. "::" .. tostring(methodName)
	else
		text = methodName
		methodName = object
	end
	luup.log("(" .. _NAME .. "::" .. tostring(methodName) .. ") " .. tostring(text), (level or 50))
end

local function error(object, methodName, text)
	log(object, methodName, "ERROR: " .. tostring(text), 1)
end

local function warning(object, methodName, text)
	log(object, methodName, "WARNING: " .. tostring(text), 2)
end

local function debug(lul_device, object, methodName, text)
	if (_params[lul_device].debugMode) then
		if (type(object) == "table") then
			methodName = methodName .. "#" .. tostring(lul_device)
		end
		log(object, methodName, "DEBUG: " .. tostring(text))
	end
end

-- Convert num to hex
local function toHex(num)
	if (num == nil) then
		return nil
	end
	local hexstr = '0123456789ABCDEF'
	local s = ''
	while num > 0 do
		local mod = math.fmod(num, 16)
		s = string.sub(hexstr, (mod + 1), (mod + 1)) .. s
		num = math.floor(num / 16)
	end
	if (s == '') then
		s = '0'
	end
	if (string.len(s) == 1) then
		s = '0' .. s
	end
	return s
end

local function formatToHex(dataBuf)
	local resultstr = ""
	if (dataBuf ~= nil) then
		for idx = 1, string.len(dataBuf) do
			resultstr = resultstr .. string.format("%02X ", string.byte(dataBuf, idx) )
		end
	end
	return resultstr
end

-------------------------------------------
-- Color manipulation
-- Inspired from https://github.com/EmmanuelOga/columns/blob/master/utils/color.lua
-------------------------------------------

-- Converts an RGB color value to HSL
local function rgbToHsl(rgb)
	local r, g, b = rgb[1] / 255, rgb[2] / 255, rgb[3] / 255

	local max, min = math.max(r, g, b), math.min(r, g, b)
	local h, s, l

	l = (max + min) / 2

	if max == min then
		h, s = 0, 0 -- achromatic
	else
		local d = max - min
		--local s
		if l > 0.5 then s = d / (2 - max - min) else s = d / (max + min) end
		if max == r then
			h = (g - b) / d
			if g < b then h = h + 6 end
		elseif max == g then h = (b - r) / d + 2
		elseif max == b then h = (r - g) / d + 4
		end
		h = h / 6
	end

	return { h, s, l }
end

-- Converts an HSL color value to RGB
local function hslToRgb(hsl)
	local h, s, l = hsl[1], hsl[2], hsl[3]
	local r, g, b

	if s == 0 then
		r, g, b = l, l, l -- achromatic
	else
		function hue2rgb(p, q, t)
			if t < 0   then t = t + 1 end
			if t > 1   then t = t - 1 end
			if t < 1/6 then return p + (q - p) * 6 * t end
			if t < 1/2 then return q end
			if t < 2/3 then return p + (q - p) * (2/3 - t) * 6 end
			return p
		end

		local q
		if l < 0.5 then q = l * (1 + s) else q = l + s - l * s end
		local p = 2 * l - q

		r = hue2rgb(p, q, h + 1/3)
		g = hue2rgb(p, q, h)
		b = hue2rgb(p, q, h - 1/3)
	end

	return { math.floor(r * 255 + 0.5), math.floor(g * 255 + 0.5), math.floor(b * 255 + 0.5) }
end

-------------------------------------------
-- Plugin functions
-------------------------------------------

-- Show message on UI
local function _showMessageOnUI (lul_device, message)
	luup.variable_set(SID.RGB_CONTROLLER, "Message", tostring(message), lul_device)
end
-- Show error on UI
local function _showErrorOnUI (object, methodName, lul_device, message)
	error(object, methodName, message)
	_showMessageOnUI(lul_device, "<font color=\"red\">" .. tostring(message) .. "</font>")
end

local _primaryColors = { "red", "green", "blue", "warmWhite", "coolWhite" }

-------------------------------------------
-- Component color management
-------------------------------------------

local _primaryColorPos = {
	["red"]   = { 1, 2 },
	["green"] = { 3, 4 },
	["blue"]  = { 5, 6 },
	["warmWhite"] = { 7, 8 },
	["coolWhite"] = { 9, 10 }
}
local function _getComponentColor(color, colorName)
	local componentColor = color:sub(_primaryColorPos[colorName][1], _primaryColorPos[colorName][2])
	if (componentColor == "") then
		componentColor = "00"
	end
	return componentColor
end
local function _getComponentColorLevel(color, colorName)
	local hexLevel = _getComponentColor(color, colorName)
	return math.floor(tonumber("0x" .. hexLevel))
end
local function _getComponentColorLevels(color, colorNames)
	local componentColorLevels = {}
	for _, colorName in ipairs(colorNames) do
		table.insert(componentColorLevels, _getComponentColorLevel(color, colorName))
	end
	return componentColorLevels
end

-------------------------------------------
-- External event management
-------------------------------------------

-- Changes debug level log
local function _onDebugValueIsUpdated (lul_device, lul_service, lul_variable, lul_value_old, lul_value_new)
	if (lul_value_new == "1") then
		log("onDebugValueIsUpdated", "Enable debug mode for device #" .. tostring(lul_device))
		_params[lul_device].debugMode = true
	else
		log("onDebugValueIsUpdated", "Disable debug mode")
		_params[lul_device].debugMode = false
	end
end

local _indexWatchedDevices = {}
-- Sets RGB Controller status according to RGB device status
local function _onRGBDeviceStatusChange (lul_device, lul_service, lul_variable, lul_value_old, lul_value_new)
	if (_indexWatchedDevices[lul_device] == nil) then
		return
	end
	for rgbControllerDeviceId, _ in pairs(_indexWatchedDevices[lul_device]) do
		local formerStatus = luup.variable_get(SID.SWITCH, "Status", rgbControllerDeviceId)
		if ((lul_value_new == "1") and (formerStatus == "0")) then
			log("onRGBDeviceStatusChange", "RGB device has just switch on")
			luup.variable_set(SID.SWITCH, "Status", "1", rgbControllerDeviceId)
		elseif ((lul_value_new == "0") and (formerStatus == "1")) then
			log("onRGBDeviceStatusChange", "RGB device has just switch off")
			luup.variable_set(SID.SWITCH, "Status", "0", rgbControllerDeviceId)
		end
	end
end

-------------------------------------------
-- Dimmers management
-------------------------------------------

-- Get child device for given color name
local function getRGBChildDeviceId(lul_device, colorName)
	local rgbChildDeviceId = _params[lul_device].rgbChildDeviceIds[colorName]
	--[[
	if ((rgbChildDeviceId == nil) or (rgbChildDeviceId == 0)) then
		warning("getRGBChildDeviceId", "Child not found for device " .. tostring(lul_device) .. " - color " .. tostring(colorName))
	end
	--]]
	return rgbChildDeviceId
end

-- Get level for a specified color
local function getColorDimmerLevel(lul_device, colorName)
	local colorLevel = nil
	local rgbChildDeviceId = getRGBChildDeviceId(lul_device, colorName)
	if (rgbChildDeviceId ~= nil) then
		local colorLoadLevel = luup.variable_get(SID.DIMMER, "LoadLevelStatus", rgbChildDeviceId) or 0
		colorLevel = math.ceil(tonumber(colorLoadLevel) * 2.55)
	end
	return colorLevel
end

-- Set load level for a specified color and a hex value
local function setLoadLevelFromHexColor(lul_device, colorName, hexColor)
	debug(lul_device, "setLoadLevelFromHexColor", "Device: " .. tostring(lul_device) .. ", colorName: " .. tostring(colorName) .. ", hexColor: " .. tostring(hexColor))
	local rgbChildDeviceId = getRGBChildDeviceId(lul_device, colorName)
	if (rgbChildDeviceId ~= nil) then
		local loadLevel = math.floor(tonumber("0x" .. hexColor) * 100/255)
		luup.call_action(SID.DIMMER, "SetLoadLevelTarget", {newLoadlevelTarget = loadLevel}, rgbChildDeviceId)
	else
		return false
	end
	return true
end

-- Retrieves status from controlled rgb device
local function initStatusFromRGBDevice (lul_device)
	local status = "0"
	if (_params[lul_device].rgbDeviceId ~= nil) then
		status = luup.variable_get(SID.SWITCH, "Status", _params[lul_device].rgbDeviceId)
		debug(lul_device, "initStatusFromRGBDevice", "Get current status of the controlled RGBW device : " .. tostring(status))
	elseif (luup.variable_get(SID.RGB_CONTROLLER, "Color", lul_device) ~= "#0000000000") then
		status = "1"
	end
	if (status == "1") then
		luup.variable_set(SID.SWITCH, "Status", "1", lul_device)
	else
		luup.variable_set(SID.SWITCH, "Status", "0", lul_device)
	end
end

-- Retrieves colors from controlled dimmers
local function initColorFromDimmerDevices (lul_device)
	-- Set color from color levels of the slave device
	local formerColor = luup.variable_get(SID.RGB_CONTROLLER, "Color", lul_device)
	formerColor = formerColor:gsub("#","")
	local red       = toHex(getColorDimmerLevel(lul_device, "red"))       or _getComponentColor(formerColor, "red")
	local green     = toHex(getColorDimmerLevel(lul_device, "green"))     or _getComponentColor(formerColor, "green")
	local blue      = toHex(getColorDimmerLevel(lul_device, "blue"))      or _getComponentColor(formerColor, "blue")
	local warmWhite = toHex(getColorDimmerLevel(lul_device, "warmWhite")) or _getComponentColor(formerColor, "warmWhite")
	local coolWhite = toHex(getColorDimmerLevel(lul_device, "coolWhite")) or _getComponentColor(formerColor, "coolWhite")
	local color = red .. green .. blue .. warmWhite .. coolWhite
	debug(lul_device, "initColorFromDimmerDevices", "Get current color of the controlled dimmers : #" .. color)
	if (formerColor ~= color) then
		luup.variable_set(SID.RGB_CONTROLLER, "Color", "#" .. color, lul_device)
	end
end

-------------------------------------------
-- Z-Wave
-------------------------------------------

-- Set load level for a specified color and a hex value
local aliasToColor = {
	["e2"] = "red",
	["e3"] = "green",
	["e4"] = "blue",
	["e5"] = "warmWhite",
	["e6"] = "coolWhite"
}
local colorToCommand = {
	["warmWhite"] = "0x00",
	["coolWhite"] = "0x01",
	["red"]   = "0x02",
	["green"] = "0x03",
	["blue"]  = "0x04"
}
local function getZWaveDataToSendFromHexColor(lul_device, colorName, hexColor)
	if (_params[lul_device].colorAliases ~= nil) then
		if (_params[lul_device].colorAliases[colorName] ~= nil) then
			-- translation
			colorName = aliasToColor[ _params[lul_device].colorAliases[colorName] ]
		else
			return ""
		end
	end
	return (colorToCommand[colorName] or "0x00") .. " 0x" .. hexColor
end

-------------------------------------------
-- RGB device types
-------------------------------------------

local RGBDeviceTypes = { }
--[[
setmetatable(RGBDeviceTypes,{
	__index = function(t, deviceTypeName)
		return RGBDeviceTypes["ZWaveColorDevice"]
	end
})
--]]

-- Device that implements Z-Wave Color Command Class
RGBDeviceTypes["ZWaveColorDevice"] = {

	_name = "ZWaveColorDevice",

	getParameters = function (self, lul_device)
		return {
			name = "Generic Z-Wave color device",
			settings = {
				{ variable = "DeviceId", name = "Controlled device", type = "ZWaveColorDevice" }
			}
		}
	end,

	getColorChannelNames = function (self, lul_device)
		return {"red", "green", "blue", "warmWhite", "coolWhite"}
	end,

	getAnimationProgramNames = function(self)
		-- TODO ?
		return {}
	end,

	_isWatching = {},

	init = function (self, lul_device)
		local rgbDeviceId = tonumber(_getVariableOrInit(lul_device, SID.RGB_CONTROLLER, "DeviceId", "0")) or 0
		_params[lul_device].rgbDeviceId = rgbDeviceId
		if (not self._isWatching[lul_device]) then
			luup.variable_watch("RGBController.initPluginInstance", SID.RGB_CONTROLLER, "DeviceId", lul_device)
			self._isWatching[lul_device] = true
		end
		if (rgbDeviceId == 0) then
			_showErrorOnUI(self, "init", lul_device, "RGBW device id is not set")
			return false
		elseif (luup.devices[rgbDeviceId] == nil) then
			_showErrorOnUI(self, "init", lul_device, "RGBW device does not exist")
			return false
		end
		_params[lul_device].rgbZwaveNode = luup.devices[rgbDeviceId].id

		initStatusFromRGBDevice(lul_device)
		if (_indexWatchedDevices[rgbDeviceId] == nil) then
			_indexWatchedDevices[rgbDeviceId] = {}
		end
		if (not _indexWatchedDevices[rgbDeviceId][lul_device]) then
			luup.variable_watch("RGBController.onRGBDeviceStatusChange", SID.SWITCH, "Status", rgbDeviceId)
			_indexWatchedDevices[rgbDeviceId][lul_device] = true
		end
		debug(lul_device, self, "init", "Controlled RGBW device is device #" .. tostring(rgbDeviceId) .. "(" .. tostring(luup.devices[rgbDeviceId].description) .. ") with Z-Wave node id #" .. tostring(_params[lul_device].rgbZwaveNode))
		return true
	end,

	setStatus = function (self, lul_device, newTargetValue)
		debug(lul_device, self, "setStatus", "Set status '" .. tostring(newTargetValue) .. "'")
		luup.call_action(SID.SWITCH, "SetTarget", {newTargetValue = newTargetValue}, _params[lul_device].rgbDeviceId)
		return true
	end,

	setColor = function (self, lul_device, color)
		debug(lul_device, self, "setColor", "Set RGBW color #" .. tostring(color))
		local data = ""
		local nb, partialData = 0, ""
		for _, primaryColorName in ipairs(_primaryColors) do
			partialData = getZWaveDataToSendFromHexColor(lul_device, primaryColorName, _getComponentColor(color, primaryColorName))
			if (partialData ~= "") then
				data = data .. " " .. partialData
				nb = nb + 1
			end
		end
		data = "0x33 0x05 0x" .. toHex(nb) .. data
		debug(lul_device, self, "setColor", "Send Z-Wave command " .. data)
		luup.call_action(SID.ZWAVE_NETWORK, "SendData", { Node = _params[lul_device].rgbZwaveNode, Data = data }, 1)
		return true
	end,

	startAnimationProgram = function (self, lul_device, programId, programName)
		debug(lul_device, self, "startAnimationProgram", "Not implemented")
		return false
	end,

	stopAnimationProgram = function (self, lul_device)
		debug(lul_device, self, "stopAnimationProgram", "Not implemented")
		return false
	end,

	getAnimationProgramNames = function(self, lul_device)
		debug(lul_device, self, "getAnimationProgramList", "Not implemented")
		return {}
	end,

	getColorChannelNames = function (self, lul_device)
		return {"red", "green", "blue", "warmWhite", "coolWhite"}
	end
}

-- Fibaro RGBW device
RGBDeviceTypes["FGRGBWM-441"] = {

	_name = "FGRGBWM-441",

	getParameters = function (self, lul_device)
		return {
			name = "Fibaro RGBW Controller",
			settings = {
				{ variable = "DeviceId", name = "Controlled device", type = "ZWaveColorDevice" }
			}
		}
	end,

	getColorChannelNames = function (self, lul_device)
		return {"red", "green", "blue", "warmWhite"}
	end,

	_animationPrograms = {
		["Fireplace"] = 6,
		["Storm"]     = 7,
		["Rainbow"]   = 8,
		["Aurora"]    = 9,
		["LAPD"]      = 10
	},

	getAnimationProgramNames = function(self, lul_device)
		local programNames = {}
		for programName, programId in pairs(self._animationPrograms) do
			table.insert(programNames, programName)
		end
		return programNames
	end,

	_isWatching = {},

	init = function (self, lul_device)
		debug(lul_device, self, "init", "Init")
		if (not RGBDeviceTypes["ZWaveColorDevice"]:init(lul_device)) then
			return false
		end
		_params[lul_device].initFromSlave = (_getVariableOrInit(lul_device, SID.RGB_CONTROLLER, "InitFromSlave", "1") == "1")
		-- Get color aliases
		_params[lul_device].colorAliases = {
			red   = _getVariableOrInit(lul_device, SID.RGB_CONTROLLER, "AliasRed",   "e2"),
			green = _getVariableOrInit(lul_device, SID.RGB_CONTROLLER, "AliasGreen", "e3"),
			blue  = _getVariableOrInit(lul_device, SID.RGB_CONTROLLER, "AliasBlue",  "e4"),
			warmWhite = _getVariableOrInit(lul_device, SID.RGB_CONTROLLER, "AliasWhite", "e5")
		}
		if (not self._isWatching[lul_device]) then
			luup.variable_watch("RGBController.initPluginInstance", SID.RGB_CONTROLLER, "AliasRed", lul_device)
			luup.variable_watch("RGBController.initPluginInstance", SID.RGB_CONTROLLER, "AliasGreen", lul_device)
			luup.variable_watch("RGBController.initPluginInstance", SID.RGB_CONTROLLER, "AliasBlue", lul_device)
			luup.variable_watch("RGBController.initPluginInstance", SID.RGB_CONTROLLER, "AliasWhite", lul_device)
			self._isWatching[lul_device] = true
		end
		-- Find dimmer child devices of the Fibaro device
		_params[lul_device].rgbChildDeviceIds = {}
		for deviceId, device in pairs(luup.devices) do
			if (device.device_num_parent == _params[lul_device].rgbDeviceId) then
				local colorAlias = device.id
				local colorName = nil
				for name, alias in pairs(_params[lul_device].colorAliases) do
					if (alias == colorAlias) then
						colorName = name
						break
					end
				end
				--= aliasToColor[ _params[lul_device].colorAliases[colorName] ]
				if (colorName ~= nil) then
					debug(lul_device, self, "init", "Find child device #" .. tostring(deviceId) .. "(" .. tostring(device.description) .. ") for color " .. tostring(colorName) .. " (alias " .. tostring(colorAlias) .. ")")
					_params[lul_device].rgbChildDeviceIds[colorName] = deviceId
				end
			end
		end
		-- Get color levels and status from the Fibaro device
		if (_params[lul_device].initFromSlave) then
			initColorFromDimmerDevices(lul_device)
		end
		return true
	end,

	setStatus = function (self, lul_device, newTargetValue)
		debug(lul_device, self, "setStatus", "Set status '" .. tostring(newTargetValue) .. "'")
		return RGBDeviceTypes["ZWaveColorDevice"]:setStatus(lul_device, newTargetValue)
	end,

	setColor = function (self, lul_device, color)
		debug(lul_device, self, "setColor", "Set RGBW color #" .. tostring(color))
		return RGBDeviceTypes["ZWaveColorDevice"]:setColor(lul_device, color)
	end,

	startAnimationProgram = function (self, lul_device, programId, programName)
		if (programName ~= "") then
			programId = self._animationPrograms[programName] or 0
			if (programId > 0) then
				debug(lul_device, self, "startAnimationProgram", "Retrieve program id '" .. tostring(programId).. "' from name '" .. tostring(programName) .. "'")
			else
				debug(lul_device, self, "startAnimationProgram", "Animation program '" .. programName .. "' is unknown")
				return false
			end
		end
		if ((programId > 0) and (programId < 11)) then
			debug(lul_device, self, "startAnimationProgram", "Start animation program #" .. tostring(programId))
			-- Z-Wave command class configuration parameters
			luup.call_action(SID.ZWAVE_NETWORK, "SendData", {Node = _params[lul_device].rgbZwaveNode, Data = "0x70 0x04 0x48 0x01 0x" .. toHex(programId)}, 1)
		else
			debug(lul_device, self, "startAnimationProgram", "Animation program #'" .. tostring(programId) .. "' is not between 1 and 10")
			return false
		end
		return true
	end,

	stopAnimationProgram = function (self, lul_device)
		debug(lul_device, self, "startAnimationProgram", "Stop animation program")
		setColorTarget(lul_device, "")
		return true
	end
}

-- Zipato RGBW bulb
RGBDeviceTypes["ZIP-RGBW"] = {

	_name = "ZIP-RGBW",

	getParameters = function (self, lul_device)
		return {
			name = "Zipato RGBW Bulb",
			settings = {
				{ variable = "DeviceId", name = "Controlled device", type = "ZWaveColorDevice" }
			}
		}
	end,

	getColorChannelNames = function (self, lul_device)
		return {"red", "green", "blue", "warmWhite", "coolWhite"}
	end,

	getAnimationProgramNames = function(self)
		return {
			"Strobe slow",
			"Strobe medium",
			"Strobe fast",
			"Strobe slow random colors",
			"Strobe medium random colors",
			"Strobe fast random colors"
		}
	end,

	init = function (self, lul_device)
		debug(lul_device, self, "init", "Init for device #" .. tostring(lul_device))
		if (not RGBDeviceTypes["ZWaveColorDevice"]:init(lul_device)) then
			return false
		end
		return true
	end,

	setStatus = function (self, lul_device, newTargetValue)
		debug(lul_device, self, "setStatus", "Set status '" .. tostring(newTargetValue) .. "'")
		return RGBDeviceTypes["ZWaveColorDevice"]:setStatus(lul_device, newTargetValue)
	end,

	setColor = function (self, lul_device, color)
		debug(lul_device, self, "setColor", "Set RGBW color #" .. tostring(color))
		-- RGB colors and cold white can not work together
		return RGBDeviceTypes["ZWaveColorDevice"]:setColor(lul_device, color)
	end,

	startAnimationProgram = function (self, lul_device, programId, programName)
		debug(lul_device, self, "startAnimationProgram", "Start animation program '" .. programName .. "'")
		--[[
		Z-Wave command class configuration parameters
		
		Configuration option 3 is used to adjust strobe light interval.
		  Values range from 0 to 25 in intervals of 100 milliseconds.
		
		Configuration option 4 is used to adjust strobe light pulse count.
		  Values range from 0 to 250 and a special value 255 which sets infinite flashing.
		
		Configuration option 5 is used to enable random strobe pulse colors.
		  Values range are 0 (turn on) or 1 (turn off).
		--]]
		if string.match(programName, "random") then
			luup.call_action(SID.ZWAVE_NETWORK, "SendData", {Node = _params[lul_device].rgbZwaveNode, Data = "0x70 0x04 0x05 0x01 0x01"}, 1)
		else
			luup.call_action(SID.ZWAVE_NETWORK, "SendData", {Node = _params[lul_device].rgbZwaveNode, Data = "0x70 0x04 0x05 0x01 0x00"}, 1)
		end

		if string.match(programName, "slow") then
			-- 2.5s
			luup.call_action(SID.ZWAVE_NETWORK, "SendData", {Node = _params[lul_device].rgbZwaveNode, Data = "0x70 0x04 0x03 0x01 0x19"}, 1)
		end

		if string.match(programName, "medium") then
			-- 700ms
			luup.call_action(SID.ZWAVE_NETWORK, "SendData", {Node = _params[lul_device].rgbZwaveNode, Data = "0x70 0x04 0x03 0x01 0x07"}, 1)
		end

		if string.match(programName, "fast") then
			-- 100ms
			luup.call_action(SID.ZWAVE_NETWORK, "SendData", {Node = _params[lul_device].rgbZwaveNode, Data = "0x70 0x04 0x03 0x01 0x01"}, 1)
		end

		luup.call_action(SID.ZWAVE_NETWORK, "SendData", {Node = _params[lul_device].rgbZwaveNode, Data = "0x70 0x04 0x04 0x01 0xFF"}, 1)

		return true
	end,

	stopAnimationProgram = function (self, lul_device)
		debug(lul_device, self, "startAnimationProgram", "Stop animation program")
		luup.call_action(SID.ZWAVE_NETWORK, "SendData", {Node = _params[lul_device].rgbZwaveNode, Data = "0x70 0x04 0x04 0x01 0x00"}, 1)
		return true
	end
}

-- Aeotec RGBW bulb
RGBDeviceTypes["AEO_ZW098-C55"] = {

	_name = "AEO_ZW098-C55",

	getParameters = function (self, lul_device)
		return {
			name = "Aeotec RGBW Bulb",
			settings = {
				{ variable = "DeviceId", name = "Controlled device", type = "ZWaveColorDevice" }
			}
		}
	end,

	getColorChannelNames = function (self, lul_device)
		return {"red", "green", "blue", "warmWhite", "coolWhite"}
	end,

	_defaultInternalAnimations = '{' ..
		'"Rainbow slow": {"transitionStyle":0, "displayMode":1, "changeSpeed":127, "residenceTime":127},' ..
		'"Rainbow fast": {"transitionStyle":0, "displayMode":1, "changeSpeed":5, "residenceTime":5},' ..
		'"Strobe red": {"transitionStyle":2, "displayMode":2, "changeSpeed":0, "residenceTime":0, "colorTransition":[0, 1]},' ..
		'"Strobe blue": {"transitionStyle":2, "displayMode":2, "changeSpeed":0, "residenceTime":0, "colorTransition":[0, 6]},' ..
		'"LAPD": {"transitionStyle":1 , "displayMode":2, "changeSpeed":0, "residenceTime":0, "colorTransition":[0, 1, 6]}' ..
	'}',

	getAnimationProgramNames = function(self)
		local animationNames = {}
		for programName, animation in pairs(_params[lul_device].internalAnimations) do
			table.insert(animationNames, programName)
		end
		return animationNames
	end,

	_isWatching = {},

	init = function (self, lul_device)
		debug(lul_device, self, "init", "Init for device #" .. tostring(lul_device))
		if (not RGBDeviceTypes["ZWaveColorDevice"]:init(lul_device)) then
			return false
		end
		if (not self._isWatching[lul_device]) then
			luup.variable_watch("RGBController.initPluginInstance", SID.RGB_CONTROLLER, "InternalAnimations", lul_device)
			self._isWatching[lul_device] = true
		end
		local jsonInternalAnimations = _getVariableOrInit(lul_device, SID.RGB_CONTROLLER, "InternalAnimations", self._defaultInternalAnimations)
		jsonInternalAnimations = string.gsub(jsonInternalAnimations, "\n", "")
		local decodeSuccess, internalAnimations, strError = pcall(json.decode, jsonInternalAnimations)
		if ((not decodeSuccess) or (type(internalAnimations) ~= "table")) then
			_params[lul_device].internalAnimations = {}
			_showErrorOnUI(self, "init", lul_device, "Internal animations decode error: " .. tostring(strError))
			return false
		else
			_params[lul_device].internalAnimations = internalAnimations
		end
		return true
	end,

	setStatus = function (self, lul_device, newTargetValue)
		debug(lul_device, self, "setStatus", "Set status '" .. tostring(newTargetValue) .. "'")
		return RGBDeviceTypes["ZWaveColorDevice"]:setStatus(lul_device, newTargetValue)
	end,

	setColor = function (self, lul_device, color)
		debug(lul_device, self, "setColor", "Set RGBW color #" .. tostring(color))
		-- RGB colors and warm white can not work together
		return RGBDeviceTypes["ZWaveColorDevice"]:setColor(lul_device, color)
	end,

	startAnimationProgram = function (self, lul_device, programId, programName)
		debug(lul_device, self, "startAnimationProgram", "Start animation program '" .. programName .. "'")
		local animation = _params[lul_device].internalAnimations[programName]
		if (animation == nil) then
			debug(lul_device, self, "startAnimationProgram", "Animation program '" .. programName .. "' is unknown")
			return false
		end
		--[[
		http://aeotec.com/z-wave-led-lightbulb/1511-led-bulb-manual.html
		
		Parameter 37 [4 bytes] will cycle the colour displayed by LED Bulb into different modes
		(MSB)
		 Value 1 - Colour Transition Style (2 bits)
					0 - Smooth Colour Transition
					1 - Fast/Direct Colour Transition
					2 - Fade Out Fale In Transition
		 Value 1 - Reserved (2 bits)
		 Value 1 - Colour Display Mode (4 bits)
					0 - Single Colour Mode
					1 - Rainbow Mode (red, orange, yellow, green, cyan, blue, violet, pinkish)
					2 - Multi Colour Mode(colours cycle between selected colours)
					3 - Random Mode
		 Value 2 - Cycle Count (8 bits)
					0 - Unlimited
		 Value 3 - Colour Change Speed (8 bits) - 0 is the fastest and 254 is the slowest
		 Value 4 - Colour Residence Time (4 bits) - 0 to 25.4 seconds
		(LSB)
		
		Parameter 38 [4 bytes] can be used to set up to 8 colours to cycle between when LED Bulb is in Multi Colour Mode.
		 Colours transition from Colour Index 1-8.
		 1-Red 2-Orange 3-Yellow 4-Green 5-Cyan 6-Blue 7-Violet 8-Pinkish
		--]]
		
		local command
		if (type(animation.colorTransition) == "table") then
			command = "0x70 0x04 0x26 0x04"
			for i = 3, 0, -1 do
				command = command .. " 0x" .. tostring(animation.colorTransition[2*i+2] or 0) .. tostring(animation.colorTransition[2*i+1] or 0)
			end
			debug(lul_device, self, "startAnimationProgram", "colorTransition " .. command)
			luup.call_action(SID.ZWAVE_NETWORK, "SendData", {Node = _params[lul_device].rgbZwaveNode, Data = command}, 1)
		end
		command = "0x70 0x04 0x25 0x04" ..
				 " 0x" .. toHex(((animation.transitionStyle or 0) * 64) + (animation.displayMode or 0)) ..
				 " 0x" .. toHex(animation.cycleCount or 0) ..
				 " 0x" .. toHex(animation.changeSpeed or 255) ..
				 " 0x" .. toHex(animation.residenceTime or 255)
		debug(lul_device, self, "startAnimationProgram", "colorAnimation " .. command)
		luup.call_action(SID.ZWAVE_NETWORK, "SendData", {Node = _params[lul_device].rgbZwaveNode, Data = command}, 1)

		return true
	end,

	stopAnimationProgram = function (self, lul_device)
		debug(lul_device, self, "startAnimationProgram", "Stop animation program")
		setColorTarget(lul_device, "")
		return true
	end
}

-- Hyperion Remote
-- See : https://github.com/tvdzwan/hyperion/wiki
RGBDeviceTypes["HYPERION"] = {

	_name = "HYPERION",

	getParameters = function (self, lul_device)
		return {
			name = "Hyperion Remote",
			settings = {
				{ variable = "DeviceIp", name = "Server IP", type = "string" },
				{ variable = "DevicePort", name = "Server port", type = "string" }
			}
		}
	end,

	getColorChannelNames = function (self, lul_device)
		return {"red", "green", "blue"}
	end,

	getAnimationProgramNames = function(self)
		return {
			"Knight rider",
			"Red mood blobs", "Green mood blobs", "Blue mood blobs", "Warm mood blobs", "Cold mood blobs", "Full color mood blobs",
			"Rainbow mood", "Rainbow swirl", "Rainbow swirl fast",
			"Snake",
			"Strobe blue", "Strobe Raspbmc", "Strobe white"
		}
	end,

	-- Send command to Hyperion JSON server by TCP
	_sendCommand = function (self, lul_device, command)
		if (_params[lul_device].rgbDeviceIp == "") then
			return false
		end

		local socket = require("socket")

		debug(lul_device, self, "sendCommand", "Connect to " .. tostring(_params[lul_device].rgbDeviceIp) .. ":" .. tostring(_params[lul_device].rgbDevicePort))
		local client, errorMsg = socket.connect(_params[lul_device].rgbDeviceIp, _params[lul_device].rgbDevicePort)
		if (client == nil) then
			_showErrorOnUI(self, "sendCommand", lul_device, "Connect error : " .. tostring(errorMsg))
			return false
		end

		local commandToSend = json.encode(command)
		debug(lul_device, self, "sendCommand", "Send : " .. tostring(commandToSend))
		client:send(commandToSend .. "\n")
		local response, status = client:receive("*l")
		debug(lul_device, self, "sendCommand", "Receive : " .. tostring(response))
		client:close()

		if (response ~= nil) then
			local decodeSuccess, jsonResponse = pcall(json.decode, response)
			if (not decodeSuccess) then
				_showErrorOnUI(self, "sendCommand", lul_device, "Response decode error: " .. tostring(jsonResponse))
			elseif (not jsonResponse.success) then
				_showErrorOnUI(self, "sendCommand", lul_device, "Response error: " .. tostring(jsonResponse.error))
			else
				return true
			end
		end
		
		return false
	end,

	_isWatching = {},

	init = function (self, lul_device)
		debug(lul_device, self, "init", "Init")
		_params[lul_device].rgbDeviceIp = _getVariableOrInit(lul_device, SID.RGB_CONTROLLER, "DeviceIp", "")
		_params[lul_device].rgbDevicePort = tonumber(_getVariableOrInit(lul_device, SID.RGB_CONTROLLER, "DevicePort", "19444")) or 19444
		if (not self._isWatching[lul_device]) then
			luup.variable_watch("RGBController.initPluginInstance", SID.RGB_CONTROLLER, "DeviceIp", lul_device)
			luup.variable_watch("RGBController.initPluginInstance", SID.RGB_CONTROLLER, "DevicePort", lul_device)
			self._isWatching[lul_device] = true
		end
		-- Check settings
		if (_params[lul_device].rgbDeviceIp == "") then
			_showErrorOnUI(self, "init", lul_device, "Hyperion server IP is not configured")
		else
			return true
		end
		return false
	end,

	setStatus = function (self, lul_device, newTargetValue)
		debug(lul_device, self, "setStatus", "Set status '" .. tostring(newTargetValue) .. "'")
		if (tostring(newTargetValue) == "1") then
			return self:setColor(lul_device, getColor(lul_device))
		else
			return self:_sendCommand(lul_device, {
				command = "clearall"
			})
		end
	end,

	setColor = function (self, lul_device, color)
		debug(lul_device, self, "setColor", "Set RGB color #" .. tostring(color))
		return self:_sendCommand(lul_device, {
			command = "color",
			color = {
				_getComponentColorLevel(color, "red"),
				_getComponentColorLevel(color, "green"),
				_getComponentColorLevel(color, "blue")
			},
			--duration = 5000,
			priority = 1002
		})
	end,

	startAnimationProgram = function (self, lul_device, programId, programName)
		debug(lul_device, self, "startAnimationProgram", "Start animation program '" .. programName .. "'")
		return self:_sendCommand(lul_device, {
			command = "effect",
			effect = {
				name = programName
			},
			priority = 1001
		})
	end,

	stopAnimationProgram = function (self, lul_device)
		debug(lul_device, self, "startAnimationProgram", "Stop animation program")
		return self:_sendCommand(lul_device, {
			command = "clear",
			priority = 1001
		})
	end
}

-- Group of dimmers
RGBDeviceTypes["RGBWdimmers"] = {

	_name = "RGBWdimmers",

	getParameters = function (self, lul_device)
		return {
			name = "RGBW Dimmers",
			settings = {
				{ variable = "DeviceIdRed", name = "Red", deviceType = "urn:schemas-upnp-org:device:DimmableLight:1" },
				{ variable = "DeviceIdGreen", name = "Green", deviceType = "urn:schemas-upnp-org:device:DimmableLight:1" },
				{ variable = "DeviceIdBlue", name = "Blue", deviceType = "urn:schemas-upnp-org:device:DimmableLight:1" },
				{ variable = "DeviceIdWarmWhite", name = "Warm white", deviceType = "urn:schemas-upnp-org:device:DimmableLight:1" },
				{ variable = "DeviceIdCoolWhite", name = "Cool white", deviceType = "urn:schemas-upnp-org:device:DimmableLight:1" }
			}
		}
	end,

	getColorChannelNames = function (self, lul_device)
		local channels = {}
		for colorName, rgbChildDeviceId in pairs(_params[lul_device].rgbChildDeviceIds) do
			if (rgbChildDeviceId ~= 0) then
				table.insert(channels, colorName)
			end
		end
		return channels
	end,

	_isWatching = {},

	init = function (self, lul_device)
		debug(lul_device, self, "init", "Init")
		-- Find dimmer devices for each color channel
		_params[lul_device].rgbChildDeviceIds = {
			red       = tonumber(_getVariableOrInit(lul_device, SID.RGB_CONTROLLER, "DeviceIdRed", "")) or 0,
			green     = tonumber(_getVariableOrInit(lul_device, SID.RGB_CONTROLLER, "DeviceIdGreen", "")) or 0,
			blue      = tonumber(_getVariableOrInit(lul_device, SID.RGB_CONTROLLER, "DeviceIdBlue",  "")) or 0,
			warmWhite = tonumber(_getVariableOrInit(lul_device, SID.RGB_CONTROLLER, "DeviceIdWarmWhite", "")) or 0,
			coolWhite = tonumber(_getVariableOrInit(lul_device, SID.RGB_CONTROLLER, "DeviceIdCoolWhite", "")) or 0
		}
		if (not self._isWatching[lul_device]) then
			luup.variable_watch("RGBController.initPluginInstance", SID.RGB_CONTROLLER, "DeviceIdRed", lul_device)
			luup.variable_watch("RGBController.initPluginInstance", SID.RGB_CONTROLLER, "DeviceIdGreen", lul_device)
			luup.variable_watch("RGBController.initPluginInstance", SID.RGB_CONTROLLER, "DeviceIdBlue", lul_device)
			luup.variable_watch("RGBController.initPluginInstance", SID.RGB_CONTROLLER, "DeviceIdWarmWhite", lul_device)
			luup.variable_watch("RGBController.initPluginInstance", SID.RGB_CONTROLLER, "DeviceIdCoolWhite", lul_device)
			self._isWatching[lul_device] = true
		end
		-- Check settings
		if (
			(_params[lul_device].rgbChildDeviceIds.red == 0)
			and (_params[lul_device].rgbChildDeviceIds.green == 0)
			and (_params[lul_device].rgbChildDeviceIds.blue == 0)
			and (_params[lul_device].rgbChildDeviceIds.warmWhite == 0)
			and (_params[lul_device].rgbChildDeviceIds.coolWhite == 0)
		) then
			_showErrorOnUI(self, "init", lul_device, "At least one dimmer must be configured")
			return false
		end
		-- Get color levels and status from the color dimmers
		_params[lul_device].initFromSlave = (_getVariableOrInit(lul_device, SID.RGB_CONTROLLER, "InitFromSlave", "1") == "1")
		if (_params[lul_device].initFromSlave) then
			initColorFromDimmerDevices(lul_device)
		end
		return true
	end,

	setStatus = function (self, lul_device, newTargetValue)
		debug(lul_device, self, "setStatus", "Set status '" .. tostring(newTargetValue) .. "'")
		if (newTargetValue == "1") then
			self:setColor(lul_device, getColor(lul_device))
		else
			self:setColor(lul_device, "0000000000")
		end
		return true
	end,

	setColor = function (self, lul_device, color)
		debug(lul_device, self, "setColor", "Set RGBW color #" .. tostring(color))
		for _, primaryColorName in ipairs(_primaryColors) do
			setLoadLevelFromHexColor(lul_device, primaryColorName, _getComponentColor(color, primaryColorName))
		end
		return true
	end
}

-- MySensor RGB(W)
RGBDeviceTypes["MYS-RGBW"] = {

	_name = "MYS-RGBW",

	getParameters = function (self, lul_device)
		return {
			name = "MySensors RGBW",
			settings = {
				{ variable = "ArduinoId", name = "Arduino plugin Id", type = "string" },
				{ variable = "RadioId",   name = "RGB Node altid",    type = "string" }
			}
		}
	end,

	getColorChannelNames = function (self, lul_device)
		return {"red", "green", "blue", "warmWhite"}
	end,

	getAnimationProgramNames = function(self)
		return {
			"Rainbow slow",
			"Rainbow medium",
			"Rainbow fast",
			"Random slow colors",
			"Random medium colors",
			"Random fast colors",
			"RGB fade slow colors",
			"RGB fade medium colors",
			"RGB fade fast colors",
			"Multicolor fade slow colors",
			"Multicolor fade medium colors",
			"Multicolor fade fast colors",
			"Current color flash slow colors",
			"Current color flash medium colors",
			"Current color flash fast colors",
		}
	end,

	_isWatching = {},

	init = function (self, lul_device, params)
		debug(lul_device, self, "init", "Init for device #" .. tostring(lul_device))
		_params[lul_device].rgbArduinoId = (tonumber(params.rgbArduinoId or _getVariableOrInit(lul_device, SID.RGB_CONTROLLER, "ArduinoId", params.rgbArduinoId)) or 0)
		_params[lul_device].rgbRadioId = (params.rgbRadioId or _getVariableOrInit(lul_device, SID.RGB_CONTROLLER, "RadioId", params.rgbRadioId) or "")
		if (not self._isWatching[lul_device]) then
			luup.variable_watch("RGBController.initPluginInstance", SID.RGB_CONTROLLER, "ArduinoId", lul_device)
			luup.variable_watch("RGBController.initPluginInstance", SID.RGB_CONTROLLER, "RadioId", lul_device)
			self._isWatching[lul_device] = true
		end
		-- Check settings
		if (
			(_params[lul_device].rgbArduinoId == 0)
			or (_params[lul_device].rgbRadioId == "")
		) then
			_showErrorOnUI(self, "init", lul_device, "Arduino plugin Id or RGB Node altid is not configured")
			return false
		end
		return true
	end,

	setStatus = function (self, lul_device, newTargetValue)
		debug(lul_device, self, "setStatus", "Set status '" .. tostring(newTargetValue) .. "'")
		if (tostring(newTargetValue) == "1") then
			luup.call_action("urn:upnp-arduino-cc:serviceId:arduino1", "SendCommand", {variableId = "LIGHT", value = "1", radioId = _params[lul_device].rgbRadioId}, _params[lul_device].rgbArduinoId)
		else
			luup.call_action("urn:upnp-arduino-cc:serviceId:arduino1", "SendCommand", {variableId = "LIGHT", value = "0", radioId = _params[lul_device].rgbRadioId}, _params[lul_device].rgbArduinoId)
		end
		return true
	end,

	setColor = function (self, lul_device, color)
		colorString = tostring(color)
		debug(lul_device, self, "setColor", "Set RGBW color #" .. colorString)
		luup.call_action("urn:upnp-arduino-cc:serviceId:arduino1", "SendCommand", {variableId = "RGBW", value = colorString, radioId = _params[lul_device].rgbRadioId}, _params[lul_device].rgbArduinoId)
		return true
	end,

	startAnimationProgram = function (self, lul_device, programId, programName)
		debug(lul_device, self, "startAnimationProgram", "Start animation program '" .. programName .. "'")
		mode = 0
		if string.match(programName, "Random") then
			mode = 0x01
		end
		if string.match(programName, "RGB fade") then
			mode = 0x02
		end
		if string.match(programName, "Multicolor fade") then
			mode = 0x03
		end
		if string.match(programName, "Current color flash") then
			mode = 0x04
		end
		if string.match(programName, "slow") then
			mode = 0x10 + mode
		end
		if string.match(programName, "medium") then
			mode = 0x20 + mode
		end
		if string.match(programName, "fast") then
			mode = 0x30 + mode
		end
		debug(lul_device, self, "startAnimationProgram", "Start animation program '" .. programName .. "' " .. tostring(mode))
		luup.call_action("urn:upnp-arduino-cc:serviceId:arduino1", "SendCommand", {variableId = "VAR_1", value = tostring(mode), radioId = _params[lul_device].rgbRadioId}, _params[lul_device].rgbArduinoId)
		return true
	end,

	stopAnimationProgram = function (self, lul_device)
		debug(lul_device, self, "stopAnimationProgram", "Stop animation program")
		luup.call_action("urn:upnp-arduino-cc:serviceId:arduino1", "SendCommand", {variableId = "VAR_1", value = "00", radioId = _params[lul_device].rgbRadioId}, _params[lul_device].rgbArduinoId)
		return true
	end
}

-------------------------------------------
-- Color transition management
-------------------------------------------

local _isTransitionInProgress = {}

local function _doColorTransition(lul_device)
	lul_device = tonumber(lul_device)
	debug(lul_device, "doColorTransition", "Color transition #" .. tostring(_params[lul_device].transition.index) .. "/" .. tostring(_params[lul_device].transition.nbSteps))
	if (luup.variable_get(SID.SWITCH, "Status", lul_device) == "0") then
		debug(lul_device, "doColorTransition", "Stop transition because device has been switched off")
		_isTransitionInProgress[lul_device] = false
		return
	end
	local ratio = _params[lul_device].transition.index / _params[lul_device].transition.nbSteps
	local newH = (1 - ratio) * _params[lul_device].transition.fromHslColor[1] + ratio * _params[lul_device].transition.toHslColor[1]
	local newS = (1 - ratio) * _params[lul_device].transition.fromHslColor[2] + ratio * _params[lul_device].transition.toHslColor[2]
	local newL = (1 - ratio) * _params[lul_device].transition.fromHslColor[3] + ratio * _params[lul_device].transition.toHslColor[3]
	local newHslColor = {newH, newS, newL}
	local newRgbColor = hslToRgb(newHslColor)
	local newColor = toHex(newRgbColor[1]) .. toHex(newRgbColor[2]) .. toHex(newRgbColor[3])
	setColorTarget(lul_device, newColor)
	--luup.variable_set(SID.RGB_CONTROLLER, "Color", "#" .. newColor, lul_device)
	--RGBDeviceTypes[_params[lul_device].rgbDeviceType].setColor(lul_device, newColor)

	_params[lul_device].transition.index = _params[lul_device].transition.index + 1
	if (_params[lul_device].transition.index <= _params[lul_device].transition.nbSteps) then
		debug(lul_device, "doColorTransition", "Next call in " .. _params[lul_device].transition.interval .. " second(s)")
		luup.call_delay("RGBController.doColorTransition", _params[lul_device].transition.interval, lul_device)
	else
		_isTransitionInProgress[lul_device] = false
		debug(lul_device, "doColorTransition", "Color transition is ended")
	end
end

-------------------------------------------
-- Custom animations
-------------------------------------------

-- name = { { "color", transition, wait}  ,...}
local _defaultCustomAnimations = '{' ..
	'"Red mood blobs":[["#FF005F0000", 0, 0], ["FFD8000000", 30, 0], ["#FF005F0000", 30, 0]],' ..
	'"Strobe red":[["#FF00000000", 0, 1], ["#0000000000", 0, 1]],' ..
	'"Strobe blue":[["#0000FF0000", 0, 1], ["#0000000000", 0, 1]],' ..
	'"Strobe warm white":[["#000000FF00", 0, 1], ["#0000000000", 0, 1]],' ..
	'"Strobe cold white":[["#00000000FF", 0, 1], ["#0000000000", 0, 1]]' ..
'}'

local function _loadCustomAnimationPrograms (lul_device, jsonCustomAnimations)
	if (type(jsonCustomAnimations) ~= "string") then
		_params[lul_device].customAnimations = {}
		return
	end
	jsonCustomAnimations = string.gsub((jsonCustomAnimations or ""), "\n", "")
	local decodeSuccess, customAnimations = pcall(json.decode, jsonCustomAnimations)
	if ((not decodeSuccess) or (type(customAnimations) ~= "table")) then
		_params[lul_device].customAnimations = {}
		_showErrorOnUI("loadCustomAnimationPrograms", lul_device, "Custom animations decode error: " .. tostring(customAnimations))
		return false
	else
		_params[lul_device].customAnimations = customAnimations
	end
end

-- Reload custom animations (mios call)
local function _onCustomAnimationProgramsAreUpdated (lul_device, lul_service, lul_variable, lul_value_old, lul_value_new)
	_loadCustomAnimationPrograms(lul_device, lul_value_new)
end

local function _doCustomAnimationProgram(lul_device, programName)
	
end

-------------------------------------------
-- Main functions
-------------------------------------------

-- Set status
function setTarget (lul_device, newTargetValue)
	debug(lul_device, "setTarget", "Set device status : " .. tostring(newTargetValue))
	if (not _params[lul_device].isConfigured) then
		debug(lul_device, "setTarget", "Device not initialized")
		return
	end
	-- todo
	if (tostring(newTargetValue) == "1") then
		newTargetValue = "1"
	else
		newTargetValue = "0"
	end
	if (RGBDeviceTypes[_params[lul_device].rgbDeviceType]:setStatus(lul_device, newTargetValue)) then
		luup.variable_set(SID.SWITCH, "Status", newTargetValue, lul_device)
	end
end

-- Set color
function setColorTarget (lul_device, newColor, transitionDuration, transitionNbSteps)
	if (not _params[lul_device].isConfigured) then
		debug(lul_device, "setColorTarget", "Device not initialized")
		return
	end
	local formerColor = luup.variable_get(SID.RGB_CONTROLLER, "Color", lul_device):gsub("#","")

	-- Compute color
	if ((newColor == nil) or (newColor == "")) then
		-- Wanted color has not been sent, keep former
		newColor = formerColor
	else
		newColor = newColor:gsub("#","")
		if ((newColor:len() ~= 6) and (newColor:len() ~= 8) and (newColor:len() ~= 10)) then
			error("Color '" .. tostring(newColor) .. "' has bad format. Should be '#[a-fA-F0-9]{6}', '#[a-fA-F0-9]{8}' or '#[a-fA-F0-9]{10}'")
			return false
		end
		if (newColor:len() == 6) then
			-- White components not sent, keep former value
			newColor = newColor .. formerColor:sub(7, 10)
		end
		if (newColor:len() == 8) then
			-- Cool white component not sent, keep former value
			newColor = newColor .. formerColor:sub(9, 10)
		end
	end

	-- Compute device status
	local status = luup.variable_get(SID.SWITCH, "Status", lul_device)
	if (newColor == "0000000000") then
		if (status == "1") then
			setTarget(lul_device, "0")
		end
	elseif (status == "0") then
		setTarget(lul_device, "1")
	end

	-- Set new color
	transitionDuration = tonumber(transitionDuration) or 0
	if (transitionDuration < 1) then
		transitionDuration = 0
	end
	transitionNbSteps  = tonumber(transitionNbSteps) or 10
	if (transitionNbSteps < 1) then
		transitionNbSteps = 1
	end
	if ((transitionDuration == 0) or (newColor == formerColor)) then
		debug(lul_device, "setColorTarget", "Set color RGBW #" .. newColor)
		luup.variable_set(SID.RGB_CONTROLLER, "Color", "#" .. newColor, lul_device)
		RGBDeviceTypes[_params[lul_device].rgbDeviceType]:setColor(lul_device, newColor)
	else
		debug(lul_device, "setColorTarget", "Set color from RGBW #" .. formerColor .. " to RGBW #" .. newColor .. " in " .. tostring(transitionDuration) .. " seconds and " .. tostring(transitionNbSteps) .. " steps")
		_params[lul_device].transition = {
			deviceId = lul_device,
			fromHslColor = rgbToHsl(_getComponentColorLevels(formerColor, {"red", "green", "blue"})),
			toHslColor   = rgbToHsl(_getComponentColorLevels(newColor, {"red", "green", "blue"})),
			index = 1,
			nbSteps = transitionNbSteps
		}
		_params[lul_device].transition.interval = math.max(math.floor(transitionDuration / _params[lul_device].transition.nbSteps), 1)
		_params[lul_device].transition.nbSteps = math.floor(transitionDuration / _params[lul_device].transition.interval)
		debug(lul_device, "setColorTarget", "isInProgress " .. tostring(_isTransitionInProgress[lul_device]))
		if (not _isTransitionInProgress[lul_device]) then
			debug(lul_device, "setColorTarget", "call doColorTransition")
			_isTransitionInProgress[lul_device] = true
			_doColorTransition(lul_device)
		end
	end
end

-- Get current RGBW color
function getColor (lul_device)
	local color = luup.variable_get(SID.RGB_CONTROLLER, "Color", lul_device)
	return color:gsub("#","")
end

-- Start animation program
function startAnimationProgram (lul_device, programId, programName)
	local programId = tonumber(programId) or 0
	local programName = programName or ""
	debug(lul_device, "startAnimationProgram", "Start animation program id: " .. tostring(programId) .. ", name: " .. tostring(programName))
	if (not _params[lul_device].isConfigured) then
		debug(lul_device, "startAnimationProgram", "Device not initialized")
		return
	end
	if ((programId == 0) and (programName == "")) then
		stopAnimationProgram(lul_device)
	elseif (type(RGBDeviceTypes[_params[lul_device].rgbDeviceType].startAnimationProgram) == "function") then
		if (RGBDeviceTypes[_params[lul_device].rgbDeviceType]:startAnimationProgram(lul_device, programId, programName)) then
			_params[lul_device].statusBeforeAnimation = luup.variable_get(SID.SWITCH, "Status", lul_device)
			luup.variable_set(SID.SWITCH, "Status", "1", lul_device)
		end
	else
		debug(_params[lul_device].rgbDeviceType .. "::startAnimationProgram", "Not implemented")
	end
end

-- Stop animation program
function stopAnimationProgram (lul_device)
	debug(lul_device, "stopAnimationProgram", "Stop animation program")
	if (not _params[lul_device].isConfigured) then
		debug(lul_device, "stopAnimationProgram", "Device not initialized")
		return
	end
	if (type(RGBDeviceTypes[_params[lul_device].rgbDeviceType].stopAnimationProgram) == "function") then
		if (RGBDeviceTypes[_params[lul_device].rgbDeviceType]:stopAnimationProgram(lul_device)) then
			if (_params[lul_device].statusBeforeAnimation == "0") then
				debug(lul_device, "startAnimationProgram", "Restore former device state before animation : switch it off")
				setTarget(lul_device, "0")
			end
		end
	else
		debug(_params[lul_device].rgbDeviceType .. "::stopAnimationProgram", "Not implemented")
	end
end

-- Start custom animation program
function startCustomAnimationProgram (lul_device, programName)
end

-- Start custom animation program
function stopCustomAnimationProgram (lul_device)
end

-- Get animation program names
function getAnimationProgramNames (lul_device)
	debug(lul_device, "getAnimationProgramList", "Get animation program names")
	local programNames = {}
	if (not _params[lul_device].isConfigured) then
		debug(lul_device, "getAnimationProgramNames", "Device not initialized")
	else
		-- RGB device animations
		if (type(RGBDeviceTypes[_params[lul_device].rgbDeviceType].getAnimationProgramNames) == "function") then
			programNames = RGBDeviceTypes[_params[lul_device].rgbDeviceType]:getAnimationProgramNames(lul_device)
		else
			debug(_params[lul_device].rgbDeviceType .. ".getAnimationProgramList", "Not implemented")
		end
		-- Custom animations
		if (type(_params[lul_device].customAnimations) == "table") then
			for programName, _ in pairs(_params[lul_device].customAnimations) do
				table.insert(programNames, "*" .. programName)
			end
		end
	end
	luup.variable_set(SID.RGB_CONTROLLER, "LastResult", json.encode(programNames), lul_device)
end

-- Get supported color channel names
function getColorChannelNames (lul_device)
	debug(lul_device, "getColorChannelNames", "Get color channel names")
	local channelNames = {}
	if (not _params[lul_device].isConfigured) then
		debug(lul_device, "getColorChannelNames", "Device not initialized")
	else
		channelNames = RGBDeviceTypes[_params[lul_device].rgbDeviceType]:getColorChannelNames(lul_device)
	end
	luup.variable_set(SID.RGB_CONTROLLER, "LastResult", json.encode(channelNames), lul_device)
end

-- Get RGB device types
function getRGBDeviceTypes (lul_device)
	debug(lul_device, "getRGBDeviceTypes", "Get RGB device types")
	local RGBDeviceTypesParameters = {}
	for typeName, RGBDeviceType in pairs(RGBDeviceTypes) do
		RGBDeviceTypesParameters[typeName] = RGBDeviceType:getParameters(lul_device)
	end
	luup.variable_set(SID.RGB_CONTROLLER, "LastResult", json.encode(RGBDeviceTypesParameters), lul_device)
end

-------------------------------------------
-- Startup
-------------------------------------------

-- Init plugin instance
local function _initPluginInstance (lul_device, params)
	log("initPluginInstance", "Init device #" .. tostring(lul_device))

	_getVariableOrInit(lul_device, SID.SWITCH, "Status", "0")
	_getVariableOrInit(lul_device, SID.RGB_CONTROLLER, "Configured", "0")
	_getVariableOrInit(lul_device, SID.RGB_CONTROLLER, "Message", "")

	-- Get plugin _params for this device
	_params[lul_device] = {
		deviceId = lul_device,
		isConfigured = false,
		rgbDeviceType = (params.deviceType or _getVariableOrInit(lul_device, SID.RGB_CONTROLLER, "DeviceType", (params.deviceType or ""))),
		color = _getVariableOrInit(lul_device, SID.RGB_CONTROLLER, "Color", "#0000000000"),
		debugMode = (_getVariableOrInit(lul_device, SID.RGB_CONTROLLER, "Debug", "0") == "1")
	}

	if (type(json) == "string") then
		_showErrorOnUI("initPluginInstance", lul_device, "No JSON decoder")
	elseif (_params[lul_device].rgbDeviceType == "") then
		_showErrorOnUI("initPluginInstance", lul_device, "RGB device type is not set")
	elseif (RGBDeviceTypes[_params[lul_device].rgbDeviceType] == nil) then
		_showErrorOnUI("initPluginInstance", lul_device, "RGB device type is not known")
	elseif (not RGBDeviceTypes[_params[lul_device].rgbDeviceType]:init(lul_device, params)) then
		error("initPluginInstance", "Device #" .. tostring(lul_device) .. " of type " .. _params[lul_device].rgbDeviceType .. " is KO")
		luup.variable_set(SID.RGB_CONTROLLER, "Configured", "0", lul_device)
	else
		_params[lul_device].isConfigured = true
		luup.variable_set(SID.RGB_CONTROLLER, "Configured", "1", lul_device)
		log("initPluginInstance", "Device #" .. tostring(lul_device) .. " of type " .. _params[lul_device].rgbDeviceType .. " is correctly configured")
		if (_params[lul_device].debugMode) then
			_showMessageOnUI(lul_device, '<div style="color:gray;font-size:.7em;text-align:left;">Debug enabled</div>')
		else
			_showMessageOnUI(lul_device, "")
		end
	end
end

local function _startupDevice (lul_device, initial_params)
	-- Update static JSON file
	if _updateStaticJSONFile(lul_device, _NAME .. "1") then
		warning("startup", "'device_json' has been updated : reload LUUP engine")
		--luup.reload()
		return false, "Reload LUUP engine"
	end

	-- Init
	_initPluginInstance(lul_device, initial_params)
	_loadCustomAnimationPrograms(lul_device, _getVariableOrInit(lul_device, SID.RGB_CONTROLLER, "CustomAnimations", _defaultCustomAnimations))

	-- ... and now my watch begins (setting changes)
	luup.variable_watch("RGBController.initPluginInstance", SID.RGB_CONTROLLER, "DeviceType", lul_device)
	luup.variable_watch("RGBController.onCustomAnimationProgramsAreUpdated", SID.RGB_CONTROLLER, "CustomAnimations", lul_device)
	luup.variable_watch("RGBController.onDebugValueIsUpdated", SID.RGB_CONTROLLER, "Debug", lul_device)
end

function startup (lul_device)
	log("startup", "Start plugin '" .. _NAME .. "' (v" .. _VERSION .. ")")

	local deviceType = luup.devices[lul_device].device_type
	local params = {}
	if (deviceType == DID.RGB_CONTROLLER) then
		-- Main device
		_startupDevice(lul_device, params)
	else
		-- Parent device
		if (deviceType == DID.ARDUINO) then
			params = {
				deviceType = "MYS-RGBW",
				rgbArduinoId = lul_device
			}
		end
		-- Look for a child RGB device, which need to start up
		for deviceId, device in pairs(luup.devices) do
			-- If I am the parent device of a child RGBController start it up
			if ((device.device_num_parent == lul_device) and (device.device_type == DID.RGB_CONTROLLER)) then
				log("startup", "Found RGB Controller child #" .. tostring(deviceId))
				if (deviceType == DID.ARDUINO) then
					params.rgbRadioId = device.id
				end
				_startupDevice(deviceId, params)
			end
		end
	end

	if (luup.version_major >= 7) then
		luup.set_failure(0, lul_device)
	end

	return true
end

-- Promote the functions used by Vera's luup.xxx functions to the Global Name Space
_G["RGBController.initPluginInstance"] = _initPluginInstance
_G["RGBController.onDebugValueIsUpdated"] = _onDebugValueIsUpdated
_G["RGBController.onRGBDeviceStatusChange"] = _onRGBDeviceStatusChange
_G["RGBController.onCustomAnimationProgramsAreUpdated"] = _onCustomAnimationProgramsAreUpdated

_G["RGBController.doColorTransition"] = _doColorTransition
_G["RGBController.doCustomAnimationProgram"] = _doCustomAnimationProgram
