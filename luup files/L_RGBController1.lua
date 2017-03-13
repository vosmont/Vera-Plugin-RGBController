--[[
  This file is part of the plugin RGB Controller.
  https://github.com/vosmont/Vera-Plugin-RgbController
  Copyright (c) 2017 Vincent OSMONT
  This code is released under the MIT License, see LICENSE.
--]]

-- Imports
local status, json = pcall(require, "dkjson")
if (type(json) ~= "table") then
	-- UI5
	json = require("json")
end

-------------------------------------------
-- Constants
-------------------------------------------

local SID = {
	SWITCH = "urn:upnp-org:serviceId:SwitchPower1",
	DIMMER = "urn:upnp-org:serviceId:Dimming1",
	ZWAVE_NETWORK = "urn:micasaverde-com:serviceId:ZWaveNetwork1",
	RGB_CONTROLLER = "urn:upnp-org:serviceId:RGBController1"
}

-------------------------------------------
-- Plugin constants
-------------------------------------------

local PLUGIN_NAME = "RGBController"
local PLUGIN_VERSION = "1.43"
local DEBUG_MODE = false

-------------------------------------------
-- Plugin variables
-------------------------------------------

local pluginParams = {}

-------------------------------------------
-- UI compatibility
-------------------------------------------

-- Update static JSON file
local function updateStaticJSONFile (lul_device, pluginName)
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
function getVariableOrInit (lul_device, serviceId, variableName, defaultValue)
	local value = luup.variable_get(serviceId, variableName, lul_device)
	if (value == nil) then
		luup.variable_set(serviceId, variableName, defaultValue, lul_device)
		value = defaultValue
	end
	return value
end

function log(methodName, text, level)
	luup.log("(" .. PLUGIN_NAME .. "::" .. tostring(methodName) .. ") " .. tostring(text), (level or 50))
end

function error(methodName, text)
	log(methodName, "ERROR: " .. tostring(text), 1)
end

function warning(methodName, text)
	log(methodName, "WARNING: " .. tostring(text), 2)
end

function debug(methodName, text)
	if (DEBUG_MODE) then
		log(methodName, "DEBUG: " .. tostring(text))
	end
end

-- Convert num to hex
function toHex(num)
	num = tonumber(num)
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

function formatToHex(dataBuf)
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
function rgbToHsl(rgb)
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
function hslToRgb(hsl)
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
function showMessageOnUI (lul_device, message)
	luup.variable_set(SID.RGB_CONTROLLER, "Message", tostring(message), lul_device)
end
-- Show error on UI
function showErrorOnUI (methodName, lul_device, message)
	error(methodName, message)
	showMessageOnUI(lul_device, "<font color=\"red\">" .. tostring(message) .. "</font>")
end

primaryColors = { "red", "green", "blue", "warmWhite", "coolWhite" }

-------------------------------------------
-- Component color management
-------------------------------------------

primaryColorPos = {
	["red"]   = { 1, 2 },
	["green"] = { 3, 4 },
	["blue"]  = { 5, 6 },
	["warmWhite"] = { 7, 8 },
	["coolWhite"] = { 9, 10 }
}
function getComponentColor(color, colorName)
	local componentColor = color:sub(primaryColorPos[colorName][1], primaryColorPos[colorName][2])
	if (componentColor == "") then
		componentColor = "00"
	end
	return componentColor
end
function getComponentColorLevel(color, colorName)
	local hexLevel = getComponentColor(color, colorName)
	return math.floor(tonumber("0x" .. hexLevel))
end
function getComponentColorLevels(color, colorNames)
	local componentColorLevels = {}
	for _, colorName in ipairs(colorNames) do
		table.insert(componentColorLevels, getComponentColorLevel(color, colorName))
	end
	return componentColorLevels
end

-------------------------------------------
-- External event management
-------------------------------------------

-- Changes debug level log
function onDebugValueIsUpdated (lul_device, lul_service, lul_variable, lul_value_old, lul_value_new)
	if (lul_value_new == "1") then
		log("onDebugValueIsUpdated", "Enable debug mode")
		DEBUG_MODE = true
	else
		log("onDebugValueIsUpdated", "Disable debug mode")
		DEBUG_MODE = false
	end
end

-- Sets RGB Controller status according to RGB device status
function onRGBDeviceStatusChange (lul_device, lul_service, lul_variable, lul_value_old, lul_value_new)
	local formerStatus = luup.variable_get(SID.SWITCH, "Status", pluginParams.deviceId)
	if ((lul_value_new == "1") and (formerStatus == "0")) then
		log("onRGBDeviceStatusChange", "RGB device has just switch on")
		luup.variable_set(SID.SWITCH, "Status", "1", pluginParams.deviceId)
	elseif ((lul_value_new == "0") and (formerStatus == "1")) then
		log("onRGBDeviceStatusChange", "RGB device has just switch off")
		luup.variable_set(SID.SWITCH, "Status", "0", pluginParams.deviceId)
	end
end

-------------------------------------------
-- Dimmers management
-------------------------------------------

-- Get child device for given color name
function getRGBChildDeviceId(lul_device, colorName)
	local rgbChildDeviceId = pluginParams.rgbChildDeviceIds[colorName]
	if (rgbChildDeviceId == nil) then
		warning("getRGBChildDeviceId", "Child not found for device " .. tostring(lul_device) .. " - color " .. tostring(colorName))
	end
	return rgbChildDeviceId
end

-- Get level for a specified color
function getColorDimmerLevel(lul_device, colorName)
	local colorLevel = nil
	local rgbChildDeviceId = getRGBChildDeviceId(lul_device, colorName)
	if (rgbChildDeviceId ~= nil) then
		local colorLoadLevel = luup.variable_get(SID.DIMMER, "LoadLevelStatus", rgbChildDeviceId) or 0
		colorLevel = math.ceil(tonumber(colorLoadLevel) * 2.55)
	end
	return colorLevel
end

-- Set load level for a specified color and a hex value
function setLoadLevelFromHexColor(lul_device, colorName, hexColor)
	debug("setLoadLevelFromHexColor", "Device: " .. tostring(lul_device) .. ", colorName: " .. tostring(colorName) .. ", hexColor: " .. tostring(hexColor))
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
function initStatusFromRGBDevice (lul_device)
	local status = "0"
	if (pluginParams.rgbDeviceId ~= nil) then
		status = luup.variable_get(SID.SWITCH, "Status", pluginParams.rgbDeviceId)
		debug("initStatusFromRGBDevice", "Get current status of the controlled RGBW device : " .. tostring(status))
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
function initColorFromDimmerDevices (lul_device)
	-- Set color from color levels of the slave device
	local formerColor = luup.variable_get(SID.RGB_CONTROLLER, "Color", lul_device)
	formerColor = formerColor:gsub("#","")
	local red       = toHex(getColorDimmerLevel(lul_device, "red"))       or getComponentColor(formerColor, "red")
	local green     = toHex(getColorDimmerLevel(lul_device, "green"))     or getComponentColor(formerColor, "green")
	local blue      = toHex(getColorDimmerLevel(lul_device, "blue"))      or getComponentColor(formerColor, "blue")
	local warmWhite = toHex(getColorDimmerLevel(lul_device, "warmWhite")) or getComponentColor(formerColor, "warmWhite")
	local coolWhite = toHex(getColorDimmerLevel(lul_device, "coolWhite")) or getComponentColor(formerColor, "coolWhite")
	local color = red .. green .. blue .. warmWhite .. coolWhite
	debug("initColorFromDimmerDevices", "Get current color of the controlled dimmers : #" .. color)
	if (formerColor ~= color) then
		luup.variable_set(SID.RGB_CONTROLLER, "Color", "#" .. color, lul_device)
	end
end

-------------------------------------------
-- Z-Wave
-------------------------------------------

-- Set load level for a specified color and a hex value
aliasToColor = {
	["e2"] = "red",
	["e3"] = "green",
	["e4"] = "blue",
	["e5"] = "warmWhite",
	["e6"] = "coolWhite"
}
colorToCommand = {
	["warmWhite"] = "0x00",
	["coolWhite"] = "0x01",
	["red"]   = "0x02",
	["green"] = "0x03",
	["blue"]  = "0x04"
}
function getZWaveDataToSendFromHexColor(lul_device, colorName, hexColor)
	if (pluginParams.colorAliases ~= nil) then
		if (pluginParams.colorAliases[colorName] ~= nil) then
			-- translation
			colorName = aliasToColor[ pluginParams.colorAliases[colorName] ]
		else
			return ""
		end
	end
	return (colorToCommand[colorName] or "0x00") .. " 0x" .. hexColor
end

-------------------------------------------
-- RGB device types
-------------------------------------------

function getKeysSortedByValue(tbl, sortFunction)
	local keys = {}
	for key in pairs(tbl) do
		table.insert(keys, key)
	end
	if (type(sortFunction) ~= "function") then
		sortFunction = function(a, b) return a < b end
	end
	table.sort(keys, function(a, b)
		return sortFunction(tbl[a], tbl[b])
	end)
	return keys
end


RGBDeviceTypes = { }
setmetatable(RGBDeviceTypes,{
	__index = function(t, deviceTypeName)
		return RGBDeviceTypes["ZWaveColorDevice"]
	end
})

-- Device that implements Z-Wave Color Command Class
RGBDeviceTypes["ZWaveColorDevice"] = {
	getParameters = function (lul_device)
		return {
			name = "* Generic Z-Wave color device",
			settings = {
				{ variable = "DeviceId", name = "Controlled device", type = "ZWaveColorDevice" }
			}
		}
	end,

	getColorChannelNames = function (lul_device)
		return {"red", "green", "blue", "warmWhite", "coolWhite"}
	end,

	getAnimationProgramNames = function()
		-- TODO ?
		return {}
	end,

	_isWatching = false,

	init = function (lul_device)
		pluginParams.rgbDeviceId = tonumber(getVariableOrInit(lul_device, SID.RGB_CONTROLLER, "DeviceId", "0"))
		if (not RGBDeviceTypes.ZWaveColorDevice._isWatching) then
			luup.variable_watch("initPluginInstance", SID.RGB_CONTROLLER, "DeviceId", lul_device)
			RGBDeviceTypes.ZWaveColorDevice._isWatching = true
		end
		if (pluginParams.rgbDeviceId == 0) then
			showErrorOnUI("ZWaveColorDevice.init",lul_device,  "RGBW device id is not set")
			--luup.variable_set(SID.SWITCH, "Status", "0", lul_device)
			--luup.variable_set(SID.RGB_CONTROLLER, "Color", "#0000000000", lul_device)
			return false
		elseif (luup.devices[pluginParams.rgbDeviceId] == nil) then
			showErrorOnUI("ZWaveColorDevice.init",lul_device,  "RGBW device does not exist")
			return false
		end
		pluginParams.rgbZwaveNode = luup.devices[pluginParams.rgbDeviceId].id
		
		initStatusFromRGBDevice(lul_device)
		-- the watch should be done differently (risk of being done more than one time)
		luup.variable_watch("onRGBDeviceStatusChange", SID.SWITCH, "Status", pluginParams.rgbDeviceId)
		debug("ZWaveColorDevice.init", "Controlled RGBW device is device #" .. tostring(pluginParams.rgbDeviceId) .. "(" .. tostring(luup.devices[pluginParams.rgbDeviceId].description) .. ") with Z-Wave node id #" .. tostring(pluginParams.rgbZwaveNode))
		return true
	end,

	setStatus = function (lul_device, newTargetValue)
		debug("ZWaveColorDevice.setStatus", "Set status '" .. tostring(newTargetValue) .. "' for device #" .. tostring(lul_device))
		if (tostring(newTargetValue) == "1") then
			-- Restore the former load level
			local loadLevel = luup.variable_get( SID.RGB_CONTROLLER, "LoadLevelStatus", lul_device )
			if loadLevel then
				debug( lul_device, self, "setStatus", "Set former loal level '" .. tostring( loadLevel ) .. "'" )
				luup.call_action( SID.DIMMER, "SetLoadLevelTarget", { newLoadlevelTarget = loadLevel }, pluginParams.rgbDeviceId )
			else
				debug("ZWaveColorDevice.setStatus", "Switches on")
				luup.call_action(SID.SWITCH, "SetTarget", {newTargetValue = "1"}, pluginParams.rgbDeviceId)
				luup.variable_set(SID.SWITCH, "Status", "1", lul_device)
			end
		else
			-- Store the current load level
			local loadLevel = luup.variable_get( SID.DIMMER, "LoadLevelStatus", pluginParams.rgbDeviceId )
			luup.variable_set( SID.RGB_CONTROLLER, "LoadLevelStatus", loadLevel, lul_device )
			debug("ZWaveColorDevice.setStatus", "Switches off")
			luup.call_action(SID.SWITCH, "SetTarget", {newTargetValue = "0"}, pluginParams.rgbDeviceId)
			luup.variable_set(SID.SWITCH, "Status", "0", lul_device)
		end
	end,

	setColor = function (lul_device, color)
		debug("ZWaveColorDevice.setColor", "Set RGBW color #" .. tostring(color) .. " for device #" .. tostring(lul_device))
		local data = ""
		local nb, partialData = 0, ""
		for _, primaryColorName in ipairs(primaryColors) do
			partialData = getZWaveDataToSendFromHexColor(lul_device, primaryColorName, getComponentColor(color, primaryColorName))
			if (partialData ~= "") then
				data = data .. " " .. partialData
				nb = nb + 1
			end
		end
		data = "0x33 0x05 0x" .. toHex(nb) .. data
		debug("ZWaveColorDevice.setColor", "Send Z-Wave command " .. data)
		luup.call_action(SID.ZWAVE_NETWORK, "SendData", { Node = pluginParams.rgbZwaveNode, Data = data }, 1)
	end,

	startAnimationProgram = function (lul_device, programId, programName)
		debug("ZWaveColorDevice.startAnimationProgram", "Not implemented")
	end,

	getAnimationProgramNames = function(lul_device)
		debug("ZWaveColorDevice.getAnimationProgramList", "Not implemented")
		return {}
	end,

	getColorChannelNames = function (lul_device)
		return {"red", "green", "blue", "warmWhite", "coolWhite"}
	end
}

-- Fibaro RGBW device
RGBDeviceTypes["FGRGBWM-441"] = {
	getParameters = function (lul_device)
		return {
			name = "Fibaro RGBW Controller",
			settings = {
				{ variable = "DeviceId", name = "Controlled device", type = "ZWaveColorDevice" }
			}
		}
	end,

	getColorChannelNames = function (lul_device)
		return {"red", "green", "blue", "warmWhite"}
	end,

	_animationPrograms = {
		["Fireplace"] = 6,
		["Storm"]     = 7,
		["Rainbow"]   = 8,
		["Aurora"]    = 9,
		["LAPD"]      = 10
	},

	getAnimationProgramNames = function(lul_device)
		return getKeysSortedByValue(RGBDeviceTypes["FGRGBWM-441"]._animationPrograms)
	end,

	_isWatching = false,

	init = function (lul_device)
		debug("FGRGBWM-441.init", "Init")
		if (not RGBDeviceTypes["ZWaveColorDevice"].init(lul_device)) then
			return false
		end
		pluginParams.initFromSlave = (getVariableOrInit(lul_device, SID.RGB_CONTROLLER, "InitFromSlave", "1") == "1")
		-- Get color aliases
		pluginParams.colorAliases = {
			red   = getVariableOrInit(lul_device, SID.RGB_CONTROLLER, "AliasRed",   "e2"),
			green = getVariableOrInit(lul_device, SID.RGB_CONTROLLER, "AliasGreen", "e3"),
			blue  = getVariableOrInit(lul_device, SID.RGB_CONTROLLER, "AliasBlue",  "e4"),
			warmWhite = getVariableOrInit(lul_device, SID.RGB_CONTROLLER, "AliasWhite", "e5")
		}
		if (not RGBDeviceTypes["FGRGBWM-441"]._isWatching) then
			luup.variable_watch("initPluginInstance", SID.RGB_CONTROLLER, "AliasRed", lul_device)
			luup.variable_watch("initPluginInstance", SID.RGB_CONTROLLER, "AliasGreen", lul_device)
			luup.variable_watch("initPluginInstance", SID.RGB_CONTROLLER, "AliasBlue", lul_device)
			luup.variable_watch("initPluginInstance", SID.RGB_CONTROLLER, "AliasWhite", lul_device)
			RGBDeviceTypes["FGRGBWM-441"]._isWatching = true
		end
		-- Find dimmer child devices of the Fibaro device
		pluginParams.rgbChildDeviceIds = {}
		for deviceId, device in pairs(luup.devices) do
			if (device.device_num_parent == pluginParams.rgbDeviceId) then
				local colorAlias = device.id
				local colorName = nil
				for name, alias in pairs(pluginParams.colorAliases) do
					if (alias == colorAlias) then
						colorName = name
						break
					end
				end
				--= aliasToColor[ pluginParams.colorAliases[colorName] ]
				if (colorName ~= nil) then
					debug("FGRGBWM-441.init", "Find child device #" .. tostring(deviceId) .. "(" .. tostring(device.description) .. ") for color " .. tostring(colorName) .. " (alias " .. tostring(colorAlias) .. ")")
					pluginParams.rgbChildDeviceIds[colorName] = deviceId
				end
			end
		end
		-- Get color levels and status from the Fibaro device
		if (pluginParams.initFromSlave) then
			initColorFromDimmerDevices(lul_device)
		end
		return true
	end,

	setStatus = function (lul_device, newTargetValue)
		debug("FGRGBWM-441.setStatus", "Set status '" .. tostring(newTargetValue) .. "' for device #" .. tostring(lul_device))
		RGBDeviceTypes["ZWaveColorDevice"].setStatus(lul_device, newTargetValue)
	end,

	setColor = function (lul_device, color)
		debug("FGRGBWM-441.setColor", "Set RGBW color #" .. tostring(color) .. " for device #" .. tostring(lul_device))
		RGBDeviceTypes.ZWaveColorDevice.setColor(lul_device, color)
	end,

	startAnimationProgram = function (lul_device, programId, programName)
		local programId = tonumber(programId) or 0
		if (programName ~= nil) then
			programId = RGBDeviceTypes["FGRGBWM-441"]._animationPrograms[programName] or 0
			if (programId > 0) then
				debug("FGRGBWM-441.startAnimationProgram", "Retrieve program id '" .. tostring(programId).. "' from name '" .. tostring(programName) .. "'")
			end
		end
		if ( ( programId > 0) and ( programId < 11 ) ) then
			debug("FGRGBWM-441.startAnimationProgram", "Start animation program #" .. tostring(programId))
			-- Z-Wave command class configuration parameters
			luup.call_action(SID.ZWAVE_NETWORK, "SendData", {Node = pluginParams.rgbZwaveNode, Data = "0x70 0x04 0x48 0x01 0x" .. toHex(programId)}, 1)
			if (luup.variable_get(SID.SWITCH, "Status", lul_device) == "0") then
				luup.variable_set(SID.SWITCH, "Status", "1", lul_device)
			end
		else
			debug("FGRGBWM-441.startAnimationProgram", "Stop animation program")
			setColorTarget(lul_device, "")
		end
	end
}

-- Zipato RGBW bulb
RGBDeviceTypes["ZIP-RGBW"] = {
	getParameters = function (lul_device)
		return {
			name = "Zipato RGBW Bulb",
			settings = {
				{ variable = "DeviceId", name = "Controlled device", type = "ZWaveColorDevice" }
			}
		}
	end,

	getColorChannelNames = function (lul_device)
		return {"red", "green", "blue", "warmWhite", "coolWhite"}
	end,

	getAnimationProgramNames = function()
		return {
			"Strobe slow",
			"Strobe medium",
			"Strobe fast",
			"Strobe slow random colors",
			"Strobe medium random colors",
			"Strobe fast random colors"
		}
	end,

	init = function (lul_device)
		debug("ZIP-RGBW.init", "Init for device #" .. tostring(lul_device))
		if (not RGBDeviceTypes["ZWaveColorDevice"].init(lul_device)) then
			return false
		end
		return true
	end,

	setStatus = function (lul_device, newTargetValue)
		debug("ZIP-RGBW.setStatus", "Set status '" .. tostring(newTargetValue) .. "' for device #" .. tostring(lul_device))
		RGBDeviceTypes["ZWaveColorDevice"].setStatus(lul_device, newTargetValue)
	end,

	setColor = function (lul_device, color)
		debug("ZIP-RGBW.setColor", "Set RGBW color #" .. tostring(color) .. " for device #" .. tostring(lul_device))
		-- RGB colors and cold white can not work together
		RGBDeviceTypes["ZWaveColorDevice"].setColor(lul_device, color)
	end,

	startAnimationProgram = function (lul_device, programId, programName)
		if ((programName ~= nil) and (programName ~= "")) then
			debug("ZIP-RGBW.startAnimationProgram", "Start animation program '" .. programName .. "'")
			-- ***
			--
			-- Z-Wave command class configuration parameters
			--
			-- Configuration option 3 is used to adjust strobe light interval.
			--  Values range from 0 to 25 in intervals of 100 milliseconds.
			--
			-- Configuration option 4 is used to adjust strobe light pulse count.
			--  Values range from 0 to 250 and a special value 255 which sets infinite flashing.
			--
			-- Configuration option 5 is used to enable random strobe pulse colors.
			--  Values range are 0 (turn on) or 1 (turn off).
			--
			-- ***
			--]]

			if string.match(programName, "random") then
				luup.call_action(SID.ZWAVE_NETWORK, "SendData", {Node = pluginParams.rgbZwaveNode, Data = "0x70 0x04 0x05 0x01 0x01"}, 1)
			else
				luup.call_action(SID.ZWAVE_NETWORK, "SendData", {Node = pluginParams.rgbZwaveNode, Data = "0x70 0x04 0x05 0x01 0x00"}, 1)
			end

			if string.match(programName, "slow") then
				-- 2.5s
				luup.call_action(SID.ZWAVE_NETWORK, "SendData", {Node = pluginParams.rgbZwaveNode, Data = "0x70 0x04 0x03 0x01 0x19"}, 1)
			end

			if string.match(programName, "medium") then
				-- 700ms
				luup.call_action(SID.ZWAVE_NETWORK, "SendData", {Node = pluginParams.rgbZwaveNode, Data = "0x70 0x04 0x03 0x01 0x07"}, 1)
			end

			if string.match(programName, "fast") then
				-- 100ms
				luup.call_action(SID.ZWAVE_NETWORK, "SendData", {Node = pluginParams.rgbZwaveNode, Data = "0x70 0x04 0x03 0x01 0x01"}, 1)
			end

			luup.call_action(SID.ZWAVE_NETWORK, "SendData", {Node = pluginParams.rgbZwaveNode, Data = "0x70 0x04 0x04 0x01 0xFF"}, 1)
			--if (luup.variable_get(SID.SWITCH, "Status", lul_device) == "0") then
			--	luup.variable_set(SID.SWITCH, "Status", "1", lul_device)
			--end
		else
			debug("ZIP-RGBW.startAnimationProgram", "Stop animation program")
			luup.call_action(SID.ZWAVE_NETWORK, "SendData", {Node = pluginParams.rgbZwaveNode, Data = "0x70 0x04 0x04 0x01 0x00"}, 1)
			setColorTarget(lul_device, "")
		end
	end
}

-- Aeotec RGBW bulb
RGBDeviceTypes["AEO_ZW098-C55"] = {
	getParameters = function (lul_device)
		return {
			name = "Aeotec RGBW Bulb",
			settings = {
				{ variable = "DeviceId", name = "Controlled device", type = "ZWaveColorDevice" }
			}
		}
	end,

	getColorChannelNames = function (lul_device)
		return {"red", "green", "blue", "warmWhite", "coolWhite"}
	end,

	_defaultAnimations = '{' .. 
		'"Rainbow slow": {"transitionStyle":0 ,"displayMode":1, "changeSpeed":127, "residenceTime":127},' ..
		'"Rainbow fast": {"transitionStyle":0 ,"displayMode":1, "changeSpeed":5, "residenceTime":5},' ..
		'"Strobe red": {"transitionStyle":2 , "displayMode":2, "changeSpeed":0, "residenceTime":0, "colorTransition":[0, 1]},' ..
		'"Strobe blue": {"transitionStyle":2 , "displayMode":2, "changeSpeed":0, "residenceTime":0, "colorTransition":[0, 6]},' ..
		'"LAPD": {"transitionStyle":1 , "displayMode":2, "changeSpeed":0, "residenceTime":0, "colorTransition":[0, 1, 6]}' ..
	'}',

	getAnimationProgramNames = function()
		local animationNames = {}
		for programName, animation in pairs(pluginParams.internalAnimations) do
			table.insert(animationNames, programName)
		end
		return animationNames
	end,

	_isWatching = false,

	init = function (lul_device)
		debug("AEO_ZW098-C55.init", "Init for device #" .. tostring(lul_device))
		if (not RGBDeviceTypes["ZWaveColorDevice"].init(lul_device)) then
			return false
		end
		if (not RGBDeviceTypes["AEO_ZW098-C55"]._isWatching) then
			luup.variable_watch("initPluginInstance", SID.RGB_CONTROLLER, "InternalAnimations", lul_device)
			RGBDeviceTypes["AEO_ZW098-C55"]._isWatching = true
		end
		local jsonInternalAnimations = getVariableOrInit(lul_device, SID.RGB_CONTROLLER, "InternalAnimations", RGBDeviceTypes["AEO_ZW098-C55"]._defaultAnimations)
		jsonInternalAnimations = string.gsub (jsonInternalAnimations, "\n", "")
		local decodeSuccess, internalAnimations = pcall(json.decode, jsonInternalAnimations)
		if ((not decodeSuccess) or (type(internalAnimations) ~= "table")) then
			pluginParams.internalAnimations = {}
			showErrorOnUI("AEO_ZW098-C55.init", lul_device, "Internal animations decode error: " .. tostring(internalAnimations))
			return false
		else
			pluginParams.internalAnimations = internalAnimations
		end
		return true
	end,

	setStatus = function (lul_device, newTargetValue)
		debug("AEO_ZW098-C55.setStatus", "Set status '" .. tostring(newTargetValue) .. "' for device #" .. tostring(lul_device))
		RGBDeviceTypes["ZWaveColorDevice"].setStatus(lul_device, newTargetValue)
	end,

	setColor = function (lul_device, color)
		debug("AEO_ZW098-C55.setColor", "Set RGBW color #" .. tostring(color) .. " for device #" .. tostring(lul_device))
		-- RGB colors and warm white can not work together
		RGBDeviceTypes["ZWaveColorDevice"].setColor(lul_device, color)
	end,

	startAnimationProgram = function (lul_device, programId, programName)
		if ((programName ~= nil) and (programName ~= "")) then
			debug("AEO_ZW098-C55.startAnimationProgram", "Start animation program '" .. programName .. "'")
			local animation = pluginParams.internalAnimations[programName or ""]
			if (animation == nil) then
				debug("AEO_ZW098-C55.startAnimationProgram", "Animation program '" .. programName .. "' in unknown")
				return
			end
			--[[
			-- http://aeotec.com/z-wave-led-lightbulb/1511-led-bulb-manual.html
			--
			-- Parameter 37 [4 bytes] will cycle the colour displayed by LED Bulb into different modes
			-- (MSB)
			-- Value 1 - Colour Transition Style (2 bits)
			--            0 - Smooth Colour Transition
			--            1 - Fast/Direct Colour Transition
			--            2 - Fade Out Fale In Transition
			-- Value 1 - Reserved (2 bits)
			-- Value 1 - Colour Display Mode (4 bits)
			--            0 - Single Colour Mode
			--            1 - Rainbow Mode (red, orange, yellow, green, cyan, blue, violet, pinkish)
			--            2 - Multi Colour Mode(colours cycle between selected colours)
			--            3 - Random Mode
			-- Value 2 - Cycle Count (8 bits)
			--            0 - Unlimited
			-- Value 3 - Colour Change Speed (8 bits) - 0 is the fastest and 254 is the slowest
			-- Value 4 - Colour Residence Time (4 bits) - 0 to 25.4 seconds
			-- (LSB)
			--
			-- Parameter 38 [4 bytes] can be used to set up to 8 colours to cycle between when LED Bulb is in Multi Colour Mode.
			-- Colours transition from Colour Index 1-8.
			-- 1-Red 2-Orange 3-Yellow 4-Green 5-Cyan 6-Blue 7-Violet 8-Pinkish
			--]]
			
			local command
			if (type(animation.colorTransition) == "table") then
				command = "0x70 0x04 0x26 0x04"
				for i = 3, 0, -1 do
					command = command .. " 0x" .. tostring(animation.colorTransition[2*i+2] or 0) .. tostring(animation.colorTransition[2*i+1] or 0)
				end
				debug("AEO_ZW098-C55.startAnimationProgram", "colorTransition " .. command)
				luup.call_action(SID.ZWAVE_NETWORK, "SendData", {Node = pluginParams.rgbZwaveNode, Data = command}, 1)
			end
			command = "0x70 0x04 0x25 0x04" ..
					 " 0x" .. toHex(((animation.transitionStyle or 0) * 64) + (animation.displayMode or 0)) ..
					 " 0x" .. toHex(animation.cycleCount or 0) ..
					 " 0x" .. toHex(animation.changeSpeed or 255) ..
					 " 0x" .. toHex(animation.residenceTime or 255)
			debug("AEO_ZW098-C55.startAnimationProgram", "colorAnimation " .. command)
			luup.call_action(SID.ZWAVE_NETWORK, "SendData", {Node = pluginParams.rgbZwaveNode, Data = command}, 1)

			
			if (luup.variable_get(SID.SWITCH, "Status", lul_device) == "0") then
				luup.variable_set(SID.SWITCH, "Status", "1", lul_device)
			end
		else
			debug("AEO_ZW098-C55.startAnimationProgram", "Stop animation program")
			setColorTarget(lul_device, "")
		end
	end
}

-- Qubino RGBW dimmer
RGBDeviceTypes["ZMNHWD1"] = {
	getParameters = function (lul_device)
		return {
			name = "Qubino RGBW dimmer",
			settings = {
				{ variable = "DeviceId", name = "Controlled device", type = "ZWaveColorDevice" }
			}
		}
	end,

	getColorChannelNames = function (lul_device)
		return {"red", "green", "blue", "warmWhite"}
	end,

	_animationPrograms = {
		["Ocean"]     = 1,
		["Lightning"] = 2,
		["Rainbow"]   = 3,
		["Snow"]      = 4,
		["Sun"]       = 5
	},

	getAnimationProgramNames = function(lul_device)
		local programNames = {}
		for programName, programId in pairs(RGBDeviceTypes["ZMNHWD1"]._animationPrograms) do
			table.insert(programNames, programName)
		end
		return programNames
	end,

	getAnimationParameters = function(lul_device)
		return { { variable = "programDuration", type = "number", placeholder = "duration (in s)", title = "Animation duration" } }
	end,

	_isWatching = false,

	init = function (lul_device)
		debug("ZMNHWD1.init", "Init")
		if (not RGBDeviceTypes["ZWaveColorDevice"].init(lul_device)) then
			return false
		end
		pluginParams.initFromSlave = (getVariableOrInit(lul_device, SID.RGB_CONTROLLER, "InitFromSlave", "1") == "1")
		-- Get color aliases
		pluginParams.colorAliases = {
			red   = getVariableOrInit(lul_device, SID.RGB_CONTROLLER, "AliasRed",   "e2"),
			green = getVariableOrInit(lul_device, SID.RGB_CONTROLLER, "AliasGreen", "e3"),
			blue  = getVariableOrInit(lul_device, SID.RGB_CONTROLLER, "AliasBlue",  "e4"),
			warmWhite = getVariableOrInit(lul_device, SID.RGB_CONTROLLER, "AliasWhite", "e5")
		}
		if (not RGBDeviceTypes["ZMNHWD1"]._isWatching) then
			luup.variable_watch("initPluginInstance", SID.RGB_CONTROLLER, "AliasRed", lul_device)
			luup.variable_watch("initPluginInstance", SID.RGB_CONTROLLER, "AliasGreen", lul_device)
			luup.variable_watch("initPluginInstance", SID.RGB_CONTROLLER, "AliasBlue", lul_device)
			luup.variable_watch("initPluginInstance", SID.RGB_CONTROLLER, "AliasWhite", lul_device)
			RGBDeviceTypes["ZMNHWD1"]._isWatching = true
		end
		-- Find dimmer child devices of the Fibaro device
		pluginParams.rgbChildDeviceIds = {}
		for deviceId, device in pairs(luup.devices) do
			if (device.device_num_parent == pluginParams.rgbDeviceId) then
				local colorAlias = device.id
				local colorName = nil
				for name, alias in pairs(pluginParams.colorAliases) do
					if (alias == colorAlias) then
						colorName = name
						break
					end
				end
				--= aliasToColor[ pluginParams.colorAliases[colorName] ]
				if (colorName ~= nil) then
					debug("ZMNHWD1.init", "Find child device #" .. tostring(deviceId) .. "(" .. tostring(device.description) .. ") for color " .. tostring(colorName) .. " (alias " .. tostring(colorAlias) .. ")")
					pluginParams.rgbChildDeviceIds[colorName] = deviceId
				end
			end
		end
		-- Get color levels and status from the Fibaro device
		if (pluginParams.initFromSlave) then
			initColorFromDimmerDevices(lul_device)
		end
		return true
	end,

	setStatus = function (lul_device, newTargetValue)
		debug("ZMNHWD1.setStatus", "Set status '" .. tostring(newTargetValue) .. "' for device #" .. tostring(lul_device))
		RGBDeviceTypes["ZWaveColorDevice"].setStatus(lul_device, newTargetValue)
	end,

	setColor = function (lul_device, color)
		debug("ZMNHWD1.setColor", "Set RGBW color #" .. tostring(color) .. " for device #" .. tostring(lul_device))
		RGBDeviceTypes.ZWaveColorDevice.setColor(lul_device, color)
	end,

	startAnimationProgram = function (lul_device, programId, programName, programDuration)
		local programId = tonumber(programId) or 0
		if (programName ~= nil) then
			programId = RGBDeviceTypes["ZMNHWD1"]._animationPrograms[programName] or 0
			if (programId > 0) then
				debug("ZMNHWD1.startAnimationProgram", "Retrieve program id '" .. tostring(programId).. "' from name '" .. tostring(programName) .. "'")
			end
		end
		if ( ( programId > 0) and ( programId < 6 ) ) then
			local programDuration = tonumber(programDuration) or 0
			if ( programDuration > 127 ) then
				-- Convert seconds into minutes
				programDuration = math.min( math.ceil( programDuration / 60 ), 128 )
				debug( "ZMNHWD1.startAnimationProgram", "Start animation program #" .. tostring( programId ) .. ", duration: " .. tostring(programDuration) .. "min" )
				programDuration = programDuration + 127
			else
				debug( "ZMNHWD1.startAnimationProgram", "Start animation program #" .. tostring( programId ) .. ", duration: " .. tostring(programDuration) .. "s" )
			end
			debug("ZMNHWD1.startAnimationProgram", "Start animation program #" .. tostring(programId))
			-- Z-Wave command class configuration parameters
			if ( programDuration > 0 ) then
				luup.call_action(SID.ZWAVE_NETWORK, "SendData", {Node = pluginParams.rgbZwaveNode, Data = "0x70 0x04 0x04 0x01 0x" .. toHex( programDuration )}, 1)
			end
			luup.call_action(SID.ZWAVE_NETWORK, "SendData", {Node = pluginParams.rgbZwaveNode, Data = "0x70 0x04 0x03 0x01 0x" .. toHex( programId )}, 1)
			if (luup.variable_get(SID.SWITCH, "Status", lul_device) == "0") then
				luup.variable_set(SID.SWITCH, "Status", "1", lul_device)
			end
		else
			debug("ZMNHWD1.startAnimationProgram", "Stop animation program")
			setColorTarget(lul_device, "")
		end
	end
}

-- Sunricher RGBW Controller
RGBDeviceTypes["SR-ZV9103FA-RGBW"] = {
	getParameters = function (lul_device)
		return {
			name = "Sunricher RGBW Controller",
			settings = {
				{ variable = "DeviceId", name = "Controlled device", type = "ZWaveColorDevice" }
			}
		}
	end,

	getColorChannelNames = function (lul_device)
		return {"red", "green", "blue", "warmWhite" }
	end,

	_animationPrograms = {
		["Fading rotation R-G-B"] = 1,
		["Fading up/down R"] = 2,
		["Fading up/down G"] = 3,
		["Fading up/down B"] = 4,
		["Fading up/down R+G"] = 5,
		["Fading up/down G+B"] = 6,
		["Fading up/down B+R"] = 7,
		["Fading up/down R+B+G"] = 8,
		["Fading up/down swap R-G"] = 9,
		["Fading up/down swap B-R"] = 10,
		["Fading up/down swap G-B"] = 11,
		["Quick flash rotating R-G-B"] = 12,
		["Quick flash R"] = 13,
		["Quick flash G"] = 14,
		["Quick flash B"] = 15,
		["Quick flash R+G"] = 16,
		["Quick flash G+B"] = 17,
		["Quick flash B+R"] = 18,
		["Quick flash R+G+B"] = 19,
		["Stepped rotation R-G-B"] = 20
	},

	getAnimationProgramNames = function(lul_device)
		return getKeysSortedByValue(RGBDeviceTypes["SR-ZV9103FA-RGBW"]._animationPrograms)
	end,

	getAnimationParameters = function(lul_device)
		return { { variable = "programSpeed", type = "number", placeholder = "speed [1-23]", title = "Animation speed" } }
	end,

	init = function (lul_device)
		debug("SR-ZV9103FA-RGBW.init", "Init for device #" .. tostring(lul_device))
		if (not RGBDeviceTypes["ZWaveColorDevice"].init(lul_device)) then
			return false
		end
		return true
	end,

	setStatus = function (lul_device, newTargetValue)
		debug("SR-ZV9103FA-RGBW.setStatus", "Set status '" .. tostring(newTargetValue) .. "' for device #" .. tostring(lul_device))
		RGBDeviceTypes["ZWaveColorDevice"].setStatus(lul_device, newTargetValue)
	end,

	setColor = function (lul_device, color)
		debug("SR-ZV9103FA-RGBW.setColor", "Set RGBW color #" .. tostring(color) .. " for device #" .. tostring(lul_device))
		-- RGB colors and cold white can not work together
		RGBDeviceTypes["ZWaveColorDevice"].setColor(lul_device, color)
	end,

	startAnimationProgram = function (lul_device, programId, programName, programDuration, programSpeed)
		local programId = tonumber(programId) or 0
		if (programName ~= nil) then
			programId = RGBDeviceTypes["SR-ZV9103FA-RGBW"]._animationPrograms[programName] or 0
			if (programId > 0) then
				debug("SR-ZV9103FA-RGBW.startAnimationProgram", "Retrieve program id '" .. tostring(programId).. "' from name '" .. tostring(programName) .. "'")
			end
		end
		if ( ( programId > 0) and ( programId < 21 ) ) then
			debug("SR-ZV9103FA-RGBW.startAnimationProgram", "Start animation program #" .. tostring(programId))
			-- Z-Wave command class configuration parameters
			luup.call_action(SID.ZWAVE_NETWORK, "SendData", {Node = pluginParams.rgbZwaveNode, Data = "0x33 0x05 0x01 0x08 0x" .. toHex(programId)}, 1)
			local programSpeed = tonumber(programSpeed) or 0
			if ( ( programSpeed > 0) and ( programSpeed < 33 ) ) then
				debug("SR-ZV9103FA-RGBW.startAnimationProgram", "Set speed to " .. tostring(programSpeed))
				luup.call_action(SID.ZWAVE_NETWORK, "SendData", {Node = pluginParams.rgbZwaveNode, Data = "0x33 0x05 0x01 0x08 0x" .. toHex(programSpeed + 199)}, 1)
			end
			if (luup.variable_get(SID.SWITCH, "Status", lul_device) == "0") then
				luup.variable_set(SID.SWITCH, "Status", "1", lul_device)
			end
		else
			debug("SR-ZV9103FA-RGBW.startAnimationProgram", "Stop animation program")
			setColorTarget(lul_device, "")
		end
	end
}

-- Hyperion Remote
-- See : https://github.com/tvdzwan/hyperion/wiki
RGBDeviceTypes["HYPERION"] = {
	getParameters = function (lul_device)
		return {
			name = "Hyperion Remote",
			settings = {
				{ variable = "DeviceIp", name = "Server IP", type = "string" },
				{ variable = "DevicePort", name = "Server port", type = "string" }
			}
		}
	end,

	getColorChannelNames = function (lul_device)
		return {"red", "green", "blue"}
	end,

	getAnimationProgramNames = function()
		return {
			"Knight rider",
			"Red mood blobs", "Green mood blobs", "Blue mood blobs", "Warm mood blobs", "Cold mood blobs", "Full color mood blobs",
			"Rainbow mood", "Rainbow swirl", "Rainbow swirl fast",
			"Snake",
			"Strobe blue", "Strobe Raspbmc", "Strobe white"
		}
	end,

	-- Send command to Hyperion JSON server by TCP
	_sendCommand = function (lul_device, command)
		if (pluginParams.rgbDeviceIp == "") then
			return false
		end

		local socket = require("socket")

		debug("HYPERION.sendCommand", "Connect to " .. tostring(pluginParams.rgbDeviceIp) .. ":" .. tostring(pluginParams.rgbDevicePort))
		local client, errorMsg = socket.connect(pluginParams.rgbDeviceIp, pluginParams.rgbDevicePort)
		if (client == nil) then
			showErrorOnUI("HYPERION.sendCommand", lul_device, "Connect error : " .. tostring(errorMsg))
			return false
		end

		local commandToSend = json.encode(command)
		debug("HYPERION.sendCommand", "Send : " .. tostring(commandToSend))
		client:send(commandToSend .. "\n")
		local response, status = client:receive("*l")
		debug("HYPERION.sendCommand", "Receive : " .. tostring(response))
		client:close()

		if (response ~= nil) then
			local decodeSuccess, jsonResponse = pcall(json.decode, response)
			if (not decodeSuccess) then
				showErrorOnUI("HYPERION.sendCommand", lul_device, "Response decode error: " .. tostring(jsonResponse))
			elseif (not jsonResponse.success) then
				showErrorOnUI("HYPERION.sendCommand", lul_device, "Response error: " .. tostring(jsonResponse.error))
			else
				return true
			end
		end
		
		return false
	end,

	_isWatching = false,

	init = function (lul_device)
		debug("HYPERION.init", "Init")
		pluginParams.rgbDeviceIp = getVariableOrInit(lul_device, SID.RGB_CONTROLLER, "DeviceIp", "")
		pluginParams.rgbDevicePort = tonumber(getVariableOrInit(lul_device, SID.RGB_CONTROLLER, "DevicePort", "19444")) or 19444
		if (not RGBDeviceTypes["HYPERION"]._isWatching) then
			luup.variable_watch("initPluginInstance", SID.RGB_CONTROLLER, "DeviceIp", lul_device)
			luup.variable_watch("initPluginInstance", SID.RGB_CONTROLLER, "DevicePort", lul_device)
			RGBDeviceTypes["HYPERION"]._isWatching = true
		end
		-- Check settings
		if (pluginParams.rgbDeviceIp == "") then
			showErrorOnUI("HYPERION.init", lul_device, "Hyperion server IP is not configured")
		else
			return true
		end
		return false
	end,

	setStatus = function (lul_device, newTargetValue)
		if (tostring(newTargetValue) == "1") then
			debug("HYPERION.setStatus", "Switches on")
			RGBDeviceTypes["HYPERION"].setColor(lul_device, getColor(lul_device))
			luup.variable_set(SID.SWITCH, "Status", "1", lul_device)
		else
			debug("HYPERION.setStatus", "Switches off")
			RGBDeviceTypes["HYPERION"]._sendCommand(lul_device, {
				command = "clearall"
			})
			luup.variable_set(SID.SWITCH, "Status", "0", lul_device)
		end
	end,

	setColor = function (lul_device, color)
		debug("HYPERION.setColor", "Set RGB color #" .. tostring(color))
		RGBDeviceTypes["HYPERION"]._sendCommand(lul_device, {
			command = "color",
			color = {
				getComponentColorLevel(color, "red"),
				getComponentColorLevel(color, "green"),
				getComponentColorLevel(color, "blue")
			},
			--duration = 5000,
			priority = 1002
		})
	end,

	startAnimationProgram = function (lul_device, programId, programName)
		if ((programName ~= nil) and (programName ~= "")) then
			debug("HYPERION.startAnimationProgram", "Start animation program '" .. programName .. "'")
			RGBDeviceTypes["HYPERION"]._sendCommand(lul_device, {
				command = "effect",
				effect = {
					name = programName
				},
				priority = 1001
			})
			if (luup.variable_get(SID.SWITCH, "Status", lul_device) == "0") then
				luup.variable_set(SID.SWITCH, "Status", "1", lul_device)
			end
		else
			debug("HYPERION.startAnimationProgram", "Stop animation program")
			RGBDeviceTypes["HYPERION"]._sendCommand(lul_device, {
				command = "clear",
				priority = 1001
			})
		end
	end
}

-- Group of dimmers
RGBDeviceTypes["RGBWdimmers"] = {
	getParameters = function (lul_device)
		return {
			name = "RGBW Dimmers",
			settings = {
				{ variable = "DeviceIdRed", name = "Red", type = "dimmer" },
				{ variable = "DeviceIdGreen", name = "Green", type = "dimmer" },
				{ variable = "DeviceIdBlue", name = "Blue", type = "dimmer" },
				{ variable = "DeviceIdWarmWhite", name = "Warm white", type = "dimmer" },
				{ variable = "DeviceIdCoolWhite", name = "Cool white", type = "dimmer" }
			}
		}
	end,

	getColorChannelNames = function (lul_device)
		local channels = {}
		for colorName, rgbChildDeviceId in pairs(pluginParams.rgbChildDeviceIds) do
			if (rgbChildDeviceId ~= 0) then
				table.insert(channels, colorName)
			end
		end
		return channels
	end,

	_isWatching = false,

	init = function (lul_device)
		debug("RGBWdimmers.init", "Init")
		-- Find dimmer devices for each color channel
		pluginParams.rgbChildDeviceIds = {
			red       = tonumber(getVariableOrInit(lul_device, SID.RGB_CONTROLLER, "DeviceIdRed", "")) or 0,
			green     = tonumber(getVariableOrInit(lul_device, SID.RGB_CONTROLLER, "DeviceIdGreen", "")) or 0,
			blue      = tonumber(getVariableOrInit(lul_device, SID.RGB_CONTROLLER, "DeviceIdBlue",  "")) or 0,
			warmWhite = tonumber(getVariableOrInit(lul_device, SID.RGB_CONTROLLER, "DeviceIdWarmWhite", "")) or 0,
			coolWhite = tonumber(getVariableOrInit(lul_device, SID.RGB_CONTROLLER, "DeviceIdCoolWhite", "")) or 0
		}
		if (not RGBDeviceTypes["RGBWdimmers"]._isWatching) then
			luup.variable_watch("initPluginInstance", SID.RGB_CONTROLLER, "DeviceIdRed", lul_device)
			luup.variable_watch("initPluginInstance", SID.RGB_CONTROLLER, "DeviceIdGreen", lul_device)
			luup.variable_watch("initPluginInstance", SID.RGB_CONTROLLER, "DeviceIdBlue", lul_device)
			luup.variable_watch("initPluginInstance", SID.RGB_CONTROLLER, "DeviceIdWarmWhite", lul_device)
			luup.variable_watch("initPluginInstance", SID.RGB_CONTROLLER, "DeviceIdCoolWhite", lul_device)
			RGBDeviceTypes["RGBWdimmers"]._isWatching = true
		end
		-- Check settings
		if (
			(pluginParams.rgbChildDeviceIds.red == 0)
			and (pluginParams.rgbChildDeviceIds.green == 0)
			and (pluginParams.rgbChildDeviceIds.blue == 0)
			and (pluginParams.rgbChildDeviceIds.warmWhite == 0)
			and (pluginParams.rgbChildDeviceIds.coolWhite == 0)
		) then
			showErrorOnUI("RGBWdimmers.init", lul_device, "At least one dimmer must be configured")
			return false
		end
		-- Get color levels and status from the color dimmers
		pluginParams.initFromSlave = (getVariableOrInit(lul_device, SID.RGB_CONTROLLER, "InitFromSlave", "1") == "1")
		if (pluginParams.initFromSlave) then
			initColorFromDimmerDevices(lul_device)
		end
		return true
	end,

	setStatus = function (lul_device, newTargetValue)
		if (tostring(newTargetValue) == "1") then
			debug("RGBWdimmers.setStatus", "Switches RGBW on")
			RGBDeviceTypes["RGBWdimmers"].setColor(lul_device, getColor(lul_device))
			luup.variable_set(SID.SWITCH, "Status", "1", lul_device)
		else
			debug("RGBWdimmers.setStatus", "Switches RGBW off")
			RGBDeviceTypes["RGBWdimmers"].setColor(lul_device, "0000000000")
			luup.variable_set(SID.SWITCH, "Status", "0", lul_device)
		end
	end,

	setColor = function (lul_device, color)
		debug("RGBWdimmers.setColor", "Set RGBW color #" .. tostring(color))
		for _, primaryColorName in ipairs(primaryColors) do
			setLoadLevelFromHexColor(lul_device, primaryColorName, getComponentColor(color, primaryColorName))
		end
	end
}

-------------------------------------------
-- Color transition management
-------------------------------------------

isTransitionInProgress = false

function doColorTransition(lul_device)
	lul_device = tonumber(lul_device)
	debug("doColorTransition", "Color transition #" .. tostring(pluginParams.transition.index) .. "/" .. tostring(pluginParams.transition.nbSteps))
	if (luup.variable_get(SID.SWITCH, "Status", lul_device) == "0") then
		debug("doColorTransition", "Stop transition because device has been switched off")
		isTransitionInProgress = false
		return
	end
	local ratio = pluginParams.transition.index / pluginParams.transition.nbSteps
	local newH = (1 - ratio) * pluginParams.transition.fromHslColor[1] + ratio * pluginParams.transition.toHslColor[1]
	local newS = (1 - ratio) * pluginParams.transition.fromHslColor[2] + ratio * pluginParams.transition.toHslColor[2]
	local newL = (1 - ratio) * pluginParams.transition.fromHslColor[3] + ratio * pluginParams.transition.toHslColor[3]
	local newHslColor = {newH, newS, newL}
	local newRgbColor = hslToRgb(newHslColor)
	local newColor = toHex(newRgbColor[1]) .. toHex(newRgbColor[2]) .. toHex(newRgbColor[3])
	setColorTarget(lul_device, newColor)
	--luup.variable_set(SID.RGB_CONTROLLER, "Color", "#" .. newColor, lul_device)
	--RGBDeviceTypes[pluginParams.rgbDeviceType].setColor(lul_device, newColor)

	pluginParams.transition.index = pluginParams.transition.index + 1
	if (pluginParams.transition.index <= pluginParams.transition.nbSteps) then
		debug("doColorTransition", "Next call in " .. pluginParams.transition.interval .. " second(s)")
		luup.call_delay("doColorTransition", pluginParams.transition.interval, lul_device)
	else
		isTransitionInProgress = false
		debug("doColorTransition", "Color transition is ended")
	end
end

-------------------------------------------
-- Z-Wave animations
-------------------------------------------

local ZwaveAnimations = {
	-- name = { { "color", transition, wait}  ,...}
	["Red mood blobs"] = {{"#FF005F0000", 0, 0}, {"FFD8000000", 30, 0}, {"#FF005F0000", 30, 0}},
	["Strobe red"] = {{"#FF00000000", 0, 1}, {"#0000000000", 0, 1}},
	["Strobe blue"] = {{"#0000FF0000", 0, 1}, {"#0000000000", 0, 1}},
	["Strobe warm white"] = {{"#000000FF00", 0, 1}, {"#0000000000", 0, 1}},
	["Strobe cold white"] = {{"#00000000FF", 0, 1}, {"#0000000000", 0, 1}}
}

-------------------------------------------
-- Main functions
-------------------------------------------

-- Set status
function setTarget (lul_device, newTargetValue)
	debug("setTarget", "Set device status : " .. tostring(newTargetValue))
	if (not pluginParams.isConfigured) then
		debug("setTarget", "Device not initialized")
		return
	end
	local formerStatus = luup.variable_get(SID.SWITCH, "Status", lul_device)
	RGBDeviceTypes[ pluginParams.rgbDeviceType ].setStatus(lul_device, newTargetValue)
end

-- Set color
function setColorTarget (lul_device, newColor, transitionDuration, transitionNbSteps)
	if (not pluginParams.isConfigured) then
		debug("setTarget", "Device not initialized")
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
		debug("setColorTarget", "Set color RGBW #" .. newColor)
		luup.variable_set(SID.RGB_CONTROLLER, "Color", "#" .. newColor, lul_device)
		RGBDeviceTypes[pluginParams.rgbDeviceType].setColor(lul_device, newColor)
	else
		debug("setColorTarget", "Set color from RGBW #" .. formerColor .. " to RGBW #" .. newColor .. " in " .. tostring(transitionDuration) .. " seconds and " .. tostring(transitionNbSteps) .. " steps")
		pluginParams.transition = {
			deviceId = lul_device,
			fromHslColor = rgbToHsl(getComponentColorLevels(formerColor, {"red", "green", "blue"})),
			toHslColor   = rgbToHsl(getComponentColorLevels(newColor, {"red", "green", "blue"})),
			index = 1,
			nbSteps = transitionNbSteps
		}
		pluginParams.transition.interval = math.max(math.floor(transitionDuration / pluginParams.transition.nbSteps), 1)
		pluginParams.transition.nbSteps = math.floor(transitionDuration / pluginParams.transition.interval)
		debug("setColorTarget", "isInProgress " .. tostring(isTransitionInProgress))
		if (not isTransitionInProgress) then
			debug("setColorTarget", "call doColorTransition")
			isTransitionInProgress = true
			doColorTransition(lul_device)
		end
	end
end

-- Get current RGBW color
function getColor (lul_device)
	local color = luup.variable_get(SID.RGB_CONTROLLER, "Color", lul_device)
	return color:gsub("#","")
end

-- Start animation program
function startAnimationProgram (lul_device, programId, programName, programDuration, programSpeed)
	debug("startAnimationProgram", "Start animation program id: " .. tostring(programId) .. ", name: " .. tostring(programName) .. ", duration: " .. tostring(programDuration) .. ", speed: " .. tostring(programSpeed))
	if (not pluginParams.isConfigured) then
		debug("setTarget", "Device not initialized")
	elseif (type(RGBDeviceTypes[pluginParams.rgbDeviceType].startAnimationProgram) == "function") then
		RGBDeviceTypes[pluginParams.rgbDeviceType].startAnimationProgram(lul_device, programId, programName, programDuration, programSpeed)
	else
		debug(pluginParams.rgbDeviceType .. ".startAnimationProgram", "Not implemented")
	end
end

-- Get animation programs
function getAnimationPrograms (lul_device)
	debug("getAnimationProgramList", "Get animation program names")
	local programs = { names = {} }
	if (not pluginParams.isConfigured) then
		debug("getAnimationProgramNames", "Device not initialized")
	elseif (type(RGBDeviceTypes[pluginParams.rgbDeviceType].getAnimationProgramNames) == "function") then
		programs.names = RGBDeviceTypes[pluginParams.rgbDeviceType].getAnimationProgramNames(lul_device)
		if (type(RGBDeviceTypes[pluginParams.rgbDeviceType].getAnimationParameters) == "function") then
			programs.parameters = RGBDeviceTypes[pluginParams.rgbDeviceType].getAnimationParameters(lul_device)
		end
	else
		debug(pluginParams.rgbDeviceType .. ".getAnimationProgramList", "Not implemented")
	end
	luup.variable_set(SID.RGB_CONTROLLER, "LastResult", json.encode(programs), lul_device)
end

-- Get supported color channel names
function getColorChannelNames (lul_device)
	debug("getColorChannelList", "Get color channel names")
	local channelNames = {}
	if (not pluginParams.isConfigured) then
		debug("getColorChannelNames", "Device not initialized")
	else
		channelNames = RGBDeviceTypes[ pluginParams.rgbDeviceType ].getColorChannelNames(lul_device)
	end
	luup.variable_set(SID.RGB_CONTROLLER, "LastResult", json.encode(channelNames), lul_device)
end

-- Get RGB device types
function getRGBDeviceTypes (lul_device)
	debug("getRGBDeviceTypes", "Get RGB device types")
	local RGBDeviceTypesParameters = {}
	for typeName, RGBDeviceType in pairs(RGBDeviceTypes) do
		local params = RGBDeviceType.getParameters(lul_device)
		params.type = typeName
		table.insert(RGBDeviceTypesParameters, params)
	end
	table.sort(RGBDeviceTypesParameters, function(a, b) return a.type < b.type end)
	luup.variable_set(SID.RGB_CONTROLLER, "LastResult", json.encode(RGBDeviceTypesParameters), lul_device)
end

-------------------------------------------
-- Startup
-------------------------------------------

-- Init plugin instance
function initPluginInstance (lul_device)
	log("initPluginInstance", "Init")

	-- Get plugin params for this device
	getVariableOrInit(lul_device, SID.SWITCH, "Status", "0")
	getVariableOrInit(lul_device, SID.RGB_CONTROLLER, "Configured", "0")
	getVariableOrInit(lul_device, SID.RGB_CONTROLLER, "Message", "")
	pluginParams = {
		deviceId = lul_device,
		isConfigured = false,
		rgbDeviceType = getVariableOrInit(lul_device, SID.RGB_CONTROLLER, "DeviceType", ""),
		color = getVariableOrInit(lul_device, SID.RGB_CONTROLLER, "Color", "#0000000000")
	}

	-- Get debug mode
	DEBUG_MODE = (getVariableOrInit(lul_device, SID.RGB_CONTROLLER, "Debug", "0") == "1")

	if (type(json) == "string") then
		showErrorOnUI("initPluginInstance", lul_device, "No JSON decoder")
	elseif ((pluginParams.rgbDeviceType == "") or (RGBDeviceTypes[pluginParams.rgbDeviceType] == nil)) then
		showErrorOnUI("initPluginInstance", lul_device, "RGB device type is not set")
	elseif (RGBDeviceTypes[pluginParams.rgbDeviceType].init(lul_device)) then
		pluginParams.isConfigured = true
		luup.variable_set(SID.RGB_CONTROLLER, "Configured", "1", lul_device)
		log("initPluginInstance", "Device #" .. tostring(lul_device) .. " of type " .. pluginParams.rgbDeviceType .. " is correctly configured")
		if (DEBUG_MODE) then
			showMessageOnUI(lul_device, '<div style="color:gray;font-size:.7em;text-align:left;">Debug enabled</div>')
		else
			showMessageOnUI(lul_device, "")
		end
	else
		error("initPluginInstance", "Device #" .. tostring(lul_device) .. " of type " .. pluginParams.rgbDeviceType .. " is KO")
		luup.variable_set(SID.RGB_CONTROLLER, "Configured", "0", lul_device)
	end
end

function startup (lul_device)
	log("startup", "Start plugin '" .. PLUGIN_NAME .. "' (v" .. PLUGIN_VERSION .. ")")

	-- Update static JSON file
	if updateStaticJSONFile(lul_device, PLUGIN_NAME .. "1") then
		warning("startup", "'device_json' has been updated : reload LUUP engine")
		luup.reload()
		return false, "Reload LUUP engine"
	end

	-- Init
	initPluginInstance(lul_device)

	-- ... and now my watch begins (setting changes)
	luup.variable_watch("initPluginInstance", SID.RGB_CONTROLLER, "DeviceType", lul_device)
	luup.variable_watch("onDebugValueIsUpdated", SID.RGB_CONTROLLER, "Debug", lul_device)

	if (luup.version_major >= 7) then
		luup.set_failure(0, lul_device)
	end

	return true
end

