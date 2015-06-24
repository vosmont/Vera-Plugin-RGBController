-- Imports
local json = require("dkjson")
if (type(json) == "string") then
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

-- Hyperion
-- See : https://github.com/tvdzwan/hyperion/wiki

-------------------------------------------
-- Plugin constants
-------------------------------------------

local PLUGIN_NAME = "RGBController"
local PLUGIN_VERSION = "1.3"
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

local function log(methodName, text, level)
	luup.log("(" .. PLUGIN_NAME .. "::" .. tostring(methodName) .. ") " .. tostring(text), (level or 50))
end

local function error(methodName, text)
	log(methodName, "ERROR: " .. tostring(text), 1)
end

local function warning(methodName, text)
	log(methodName, "WARNING: " .. tostring(text), 2)
end

local function debug(methodName, text)
	if (DEBUG_MODE) then
		log(methodName, "DEBUG: " .. tostring(text))
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
-- Plugin functions
-------------------------------------------

-- Show message on UI
local function showMessageOnUI (lul_device, message)
	luup.variable_set(SID.RGB_CONTROLLER, "Message", tostring(message), lul_device)
end
-- Show error on UI
local function showErrorOnUI (methodName, lul_device, message)
	error(methodName, message)
	showMessageOnUI(lul_device, "<font color=\"red\">" .. tostring(message) .. "</font>")
end

local primaryColors = { "red", "green", "blue", "warmWhite", "coolWhite" }

-- Set load level for a specified color and a hex value
local primaryColorPos = {
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
	return math.floor(tonumber("0x" .. hexLevel) * 100/255)
end

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

-------------------------------------------
-- Dimmers management
-------------------------------------------

-- Get child device for given color name
local function getRGBChildDeviceId(lul_device, colorName)
	--local rgbChildDeviceId = nil
	--local colorAlias = pluginParams.colorAliases[colorName]
	--if (colorAlias ~= nil) then
	--	rgbChildDeviceId = pluginParams.rgbChildDeviceIds[colorAlias]
	--end
	local rgbChildDeviceId = pluginParams.rgbChildDeviceIds[colorName]
	if (rgbChildDeviceId == nil) then
		--warning("getRGBChildDeviceId", "Child not found for device " .. tostring(lul_device) .. " - color " .. tostring(colorName) .. " - colorAlias " .. tostring(colorAlias))
		warning("getRGBChildDeviceId", "Child not found for device " .. tostring(lul_device) .. " - color " .. tostring(colorName))
	end
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

-- Retrieves colors from controlled dimmers
local function initFromDimmerDevices (lul_device)
	-- Set color from color levels of the slave device
	local formerColor = luup.variable_get(SID.RGB_CONTROLLER, "Color", lul_device)
	formerColor = formerColor:gsub("#","")
	local red       = toHex(getColorDimmerLevel(lul_device, "red"))       or getComponentColor(formerColor, "red")
	local green     = toHex(getColorDimmerLevel(lul_device, "green"))     or getComponentColor(formerColor, "green")
	local blue      = toHex(getColorDimmerLevel(lul_device, "blue"))      or getComponentColor(formerColor, "blue")
	local warmWhite = toHex(getColorDimmerLevel(lul_device, "warmWhite")) or getComponentColor(formerColor, "warmWhite")
	local coolWhite = toHex(getColorDimmerLevel(lul_device, "coolWhite")) or getComponentColor(formerColor, "coolWhite")
	local color = red .. green .. blue .. warmWhite .. coolWhite
	debug("initFromDimmerDevices", "Get current color of the controlled dimmers : #" .. color)
	if (formerColor ~= color) then
		luup.variable_set(SID.RGB_CONTROLLER, "Color", "#" .. color, lul_device)
	end

	-- Set the status of the controller from slave status
	local status = "0"
	if (pluginParams.rgbDeviceId ~= nil) then
		status = luup.variable_get(SID.SWITCH, "Status", pluginParams.rgbDeviceId)
		debug("initFromDimmerDevices", "Get current status of the controlled RGBW device : " .. tostring(status))
	elseif (color ~= "0000000000") then
		status = "1"
	end
	if (status == "1") then
		luup.variable_set(SID.SWITCH, "Status", "1", lul_device)
	else
		luup.variable_set(SID.SWITCH, "Status", "0", lul_device)
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

local RGBDeviceTypes = { }
setmetatable(RGBDeviceTypes,{
	__index = function(t, deviceTypeName)
		return RGBDeviceTypes["ZWaveColorDevice"]
	end
})

-- Device that implements Z-Wave Color Command Class
RGBDeviceTypes["ZWaveColorDevice"] = {
	getParameters = function (lul_device)
		return {
			name = "Generic Z-Wave color device",
			settings = {
				{ variable = "DeviceId", name = "Controlled device", type = "ZWaveColorDevice" }
			}
		}
	end,

	isWatching = false,

	init = function (lul_device)
		pluginParams.rgbDeviceId = tonumber(getVariableOrInit(lul_device, SID.RGB_CONTROLLER, "DeviceId", "0"))
		if (not RGBDeviceTypes.ZWaveColorDevice.isWatching) then
			luup.variable_watch("initPluginInstance", SID.RGB_CONTROLLER, "DeviceId", lul_device)
			RGBDeviceTypes.ZWaveColorDevice.isWatching = true
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
		debug("ZWaveColorDevice.init", "Controlled RGBW device is device #" .. tostring(pluginParams.rgbDeviceId) .. "(" .. tostring(luup.devices[pluginParams.rgbDeviceId].description) .. ") with Z-Wave node id #" .. tostring(pluginParams.rgbZwaveNode))
		return true
	end,
	
	setStatus = function (lul_device, newTargetValue)
		debug("ZWaveColorDevice.setStatus", "Not implemented")
	end,

	setColor = function (lul_device, color)
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

	isWatching = false,

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
		if (not RGBDeviceTypes["FGRGBWM-441"].isWatching) then
			luup.variable_watch("initPluginInstance", SID.RGB_CONTROLLER, "AliasRed", lul_device)
			luup.variable_watch("initPluginInstance", SID.RGB_CONTROLLER, "AliasGreen", lul_device)
			luup.variable_watch("initPluginInstance", SID.RGB_CONTROLLER, "AliasBlue", lul_device)
			luup.variable_watch("initPluginInstance", SID.RGB_CONTROLLER, "AliasWhite", lul_device)
			RGBDeviceTypes["FGRGBWM-441"].isWatching = true
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
			initFromDimmerDevices(lul_device)
		end
		return true
	end,

	setStatus = function (lul_device, newTargetValue)
		if (tostring(newTargetValue) == "1") then
			debug("FGRGBWM-441.setStatus", "Switches on")
			luup.call_action(SID.SWITCH, "SetTarget", {newTargetValue = "1"}, pluginParams.rgbDeviceId)
			luup.variable_set(SID.SWITCH, "Status", "1", lul_device)
		else
			debug("FGRGBWM-441.setStatus", "Switches off")
			luup.call_action(SID.SWITCH, "SetTarget", {newTargetValue = "0"}, pluginParams.rgbDeviceId)
			luup.variable_set(SID.SWITCH, "Status", "0", lul_device)
		end
	end,

	setColor = function (lul_device, color)
		debug("FGRGBWM-441.setColor", "Set RGBW color #" .. tostring(color))
		RGBDeviceTypes.ZWaveColorDevice.setColor(lul_device, color)
	end,

	animationPrograms = {
		["Fireplace"] = 6,
		["Storm"]     = 7,
		["Rainbow"]   = 8,
		["Aurora"]    = 9,
		["LPD"]       = 10
	},

	startAnimationProgram = function (lul_device, programId, programName)
		local programId = tonumber(programId) or 0
		if (programName ~= nil) then
			programId = RGBDeviceTypes["FGRGBWM-441"].animationPrograms[programName] or 0
			if (programId > 0) then
				debug("FGRGBWM-441.startAnimationProgram", "Retrieve program id '" .. tostring(programId).. "' from name '" .. tostring(programName) .. "'")
			end
		end
		if (programId > 0) then
			debug("FGRGBWM-441.startAnimationProgram", "Start animation program #" .. tostring(programId))
			luup.call_action(SID.ZWAVE_NETWORK, "SendData", {Node = pluginParams.rgbZwaveNode, Data = "0x70 0x04 0x48 0x01 0x" .. toHex(programId)}, 1)
			if (luup.variable_get(SID.SWITCH, "Status", lul_device) == "0") then
				luup.variable_set(SID.SWITCH, "Status", "1", lul_device)
			end
		else
			debug("FGRGBWM-441.startAnimationProgram", "Stop animation program")
			setColorTarget(lul_device, "")
		end
	end,

	getAnimationProgramNames = function(lul_device)
		local programNames = {}
		for programName, programId in pairs(RGBDeviceTypes["FGRGBWM-441"].animationPrograms) do
			table.insert(programNames, programName)
		end
		return programNames
	end,

	getColorChannelNames = function (lul_device)
		return {"red", "green", "blue", "warmWhite"}
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

	init = function (lul_device)
		debug("ZIP-RGBW.init", "Init")
		if (not RGBDeviceTypes["ZWaveColorDevice"].init(lul_device)) then
			return false
		end
		pluginParams.rgbChildDeviceIds = {
			coolWhite = lul_device
		}
		return true
	end,

	setStatus = function (lul_device, newTargetValue)
		if (tostring(newTargetValue) == "1") then
			debug("ZIP-RGBW.setStatus", "Switches RGBW on")
			RGBDeviceTypes["ZIP-RGBW"].setColor(lul_device, getColor(lul_device))
			luup.variable_set(SID.SWITCH, "Status", "1", lul_device)
		else
			local whiteLoadLevel = luup.variable_get(SID.DIMMER, "LoadLevelStatus", pluginParams.rgbDeviceId) or 0
			local formerCoolWhite = toHex(math.ceil(tonumber(whiteLoadLevel) * 2.55))
			debug("ZIP-RGBW.setStatus", "Switches RGBW off and restores cold white to #" .. formerCoolWhite)
			RGBDeviceTypes["ZWaveColorDevice"].setColor(lul_device, "00000000" .. formerCoolWhite)
			luup.variable_set(SID.SWITCH, "Status", "0", lul_device)
		end
	end,

	setColor = function (lul_device, color)
		debug("ZIP-RGBW.setColor", "Set RGBW color #" .. tostring(color))
		-- RGB colors and cold white can not work together
		local rgbColor = color:sub(1, 6)
		local warmWhiteColor = getComponentColor(color, "warmWhite")
		local coolWhiteColor = getComponentColor(color, "coolWhite")
		--if ((rgbwColor ~= "00000000") and (luup.variable_get(SID.SWITCH, "Status", pluginParams.rgbDeviceId) == "1")) then
		--	luup.call_action(SID.SWITCH, "SetTarget", {newTargetValue = "0"}, pluginParams.rgbDeviceId)
		--end
		if (coolWhiteColor == "00") then
			RGBDeviceTypes["ZWaveColorDevice"].setColor(lul_device, rgbColor .. warmWhiteColor .. "00")
		else
			setLoadLevelFromHexColor(lul_device, "coolWhite", coolWhiteColor)
		end
	end,

	startAnimationProgram = function (lul_device, programId, programName)
		debug("ZIP-RGBW.startAnimationProgram", "Not implemented")
	end,

	getAnimationProgramNames = function(lul_device)
		debug("ZIP-RGBW.getAnimationProgramList", "Not implemented")
		return {}
	end,

	getColorChannelNames = function (lul_device)
		return {"red", "green", "blue", "warmWhite", "coolWhite"}
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

	init = function (lul_device)
		debug("AEO_ZW098-C55.init", "Init")
		if (not RGBDeviceTypes["ZWaveColorDevice"].init(lul_device)) then
			return false
		end
		pluginParams.rgbChildDeviceIds = {
			warmWhite = lul_device
		}
		return true
	end,

	setStatus = function (lul_device, newTargetValue)
		if (tostring(newTargetValue) == "1") then
			debug("AEO_ZW098-C55.setStatus", "Switches RGBW on")
			RGBDeviceTypes["AEO_ZW098-C55"].setColor(lul_device, getColor(lul_device))
			luup.variable_set(SID.SWITCH, "Status", "1", lul_device)
		else
			local whiteLoadLevel = luup.variable_get(SID.DIMMER, "LoadLevelStatus", pluginParams.rgbDeviceId) or 0
			local formerWarmWhite = toHex(math.ceil(tonumber(whiteLoadLevel) * 2.55))
			debug("AEO_ZW098-C55.setStatus", "Switches RGBW off and restores warm white to #" .. formerWarmWhite)
			RGBDeviceTypes["ZWaveColorDevice"].setColor(lul_device, "000000" .. formerWarmWhite .. "00")
			luup.variable_set(SID.SWITCH, "Status", "0", lul_device)
		end
	end,

	setColor = function (lul_device, color)
		debug("AEO_ZW098-C55.setColor", "Set RGBW color #" .. tostring(color))
		-- RGB colors and warm white can not work together
		local rgbColor = color:sub(1, 6)
		local warmWhiteColor = getComponentColor(color, "warmWhite")
		local coolWhiteColor = getComponentColor(color, "coolWhite")
		--if ((rgbwColor ~= "00000000") and (luup.variable_get(SID.SWITCH, "Status", pluginParams.rgbDeviceId) == "1")) then
		--	luup.call_action(SID.SWITCH, "SetTarget", {newTargetValue = "0"}, pluginParams.rgbDeviceId)
		--end
		if (warmWhiteColor == "00") then
			RGBDeviceTypes["ZWaveColorDevice"].setColor(lul_device, rgbColor .. "00" .. coolWhiteColor)
		else
			setLoadLevelFromHexColor(lul_device, "warmWhite", warmWhiteColor)
		end
	end,

	startAnimationProgram = function (lul_device, programId, programName)
		debug("AEO_ZW098-C55.startAnimationProgram", "Not implemented")
	end,

	getAnimationProgramNames = function(lul_device)
		debug("AEO_ZW098-C55.getAnimationProgramList", "Not implemented")
		return {}
	end,

	getColorChannelNames = function (lul_device)
		return {"red", "green", "blue", "warmWhite", "coolWhite"}
	end
}

-- Hyperion Remote
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

	-- Send command to Hyperion JSON server by TCP
	sendCommand = function (lul_device, command)
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

	isWatching = false,

	init = function (lul_device)
		debug("HYPERION.init", "Init")
		pluginParams.rgbDeviceIp = getVariableOrInit(lul_device, SID.RGB_CONTROLLER, "DeviceIp", "")
		pluginParams.rgbDevicePort = tonumber(getVariableOrInit(lul_device, SID.RGB_CONTROLLER, "DevicePort", "19444")) or 19444
		if (not RGBDeviceTypes["HYPERION"].isWatching) then
			luup.variable_watch("initPluginInstance", SID.RGB_CONTROLLER, "DeviceIp", lul_device)
			luup.variable_watch("initPluginInstance", SID.RGB_CONTROLLER, "DevicePort", lul_device)
			RGBDeviceTypes["HYPERION"].isWatching = true
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
			RGBDeviceTypes["HYPERION"].sendCommand(lul_device, {
				command = "clearall"
			})
			luup.variable_set(SID.SWITCH, "Status", "0", lul_device)
		end
	end,

	setColor = function (lul_device, color)
		debug("HYPERION.setColor", "Set RGB color #" .. tostring(color))
		RGBDeviceTypes["HYPERION"].sendCommand(lul_device, {
			command = "color",
			color = {
				getComponentColorLevel(color, "red"),
				getComponentColorLevel(color, "green"),
				getComponentColorLevel(color, "blue")
			},
			--duration = 5000,
			priority = 1001
		})
	end,

	startAnimationProgram = function (lul_device, programId, programName)
		if ((programName ~= nil) and (programName ~= "")) then
			debug("startAnimationProgram", "Start animation program '" .. programName .. "'")
			RGBDeviceTypes["HYPERION"].sendCommand(lul_device, {
				command = "effect",
				effect = {
					name = programName--,
					--args = {}
				},
				priority = 1002
			})
			if (luup.variable_get(SID.SWITCH, "Status", lul_device) == "0") then
				luup.variable_set(SID.SWITCH, "Status", "1", lul_device)
			end
		else
			debug("startAnimationProgram", "Stop animation program")
			RGBDeviceTypes["HYPERION"].sendCommand(lul_device, {
				command = "clear",
				priority = 1002
			})
		end
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

	getColorChannelNames = function (lul_device)
		return {"red", "green", "blue"}
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

	isWatching = false,

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
		if (not RGBDeviceTypes["RGBWdimmers"].isWatching) then
			luup.variable_watch("initPluginInstance", SID.RGB_CONTROLLER, "DeviceIdRed", lul_device)
			luup.variable_watch("initPluginInstance", SID.RGB_CONTROLLER, "DeviceIdGreen", lul_device)
			luup.variable_watch("initPluginInstance", SID.RGB_CONTROLLER, "DeviceIdBlue", lul_device)
			luup.variable_watch("initPluginInstance", SID.RGB_CONTROLLER, "DeviceIdWarmWhite", lul_device)
			luup.variable_watch("initPluginInstance", SID.RGB_CONTROLLER, "DeviceIdCoolWhite", lul_device)
			RGBDeviceTypes["RGBWdimmers"].isWatching = true
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
			initFromDimmerDevices(lul_device)
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
	end,

	startAnimationProgram = function (lul_device, programId, programName)
		debug("RGBWdimmers.startAnimationProgram", "Not implemented")
	end,

	getAnimationProgramNames = function(lul_device)
		debug("RGBWdimmers.getAnimationProgramList", "Not implemented")
		return {}
	end,

	getColorChannelNames = function (lul_device)
		local channels = {}
		for colorName, rgbChildDeviceId in pairs(pluginParams.rgbChildDeviceIds) do
			if (rgbChildDeviceId ~= 0) then
				table.insert(channels, colorName)
			end
		end
		return channels
	end
}

-------------------------------------------
-- Main functions
-------------------------------------------

-- Set status
function setTarget (lul_device, newTargetValue)
	if (not pluginParams.isConfigured) then
		debug("setTarget", "Device not initialized")
		return
	end
	local formerStatus = luup.variable_get(SID.SWITCH, "Status", lul_device)
	debug("setTarget", "Set device status : " .. tostring(newTargetValue))
	RGBDeviceTypes[ pluginParams.rgbDeviceType ].setStatus(lul_device, newTargetValue)
end

-- Set color
function setColorTarget (lul_device, newColor)
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
			newColor = newColor .. formerColor:sub(7, 11)
		end
		luup.variable_set(SID.RGB_CONTROLLER, "Color", "#" .. newColor, lul_device)
	end

	-- Compute device status
	local status = luup.variable_get(SID.SWITCH, "Status", lul_device)
	if (newColor == "0000000000") then
		if (status == "1") then
			luup.variable_set(SID.SWITCH, "Status", "0", lul_device)
		end
	elseif (status == "0") then
		luup.variable_set(SID.SWITCH, "Status", "1", lul_device)
	end

	-- Set new color
	debug("setColorTarget", "Set color RGBW #" .. newColor)
	RGBDeviceTypes[pluginParams.rgbDeviceType].setColor(lul_device, newColor)
end

-- Get current RGBW color
function getColor (lul_device)
	local color = luup.variable_get(SID.RGB_CONTROLLER, "Color", lul_device)
	return color:gsub("#","")
end

-- Start animation program
function startAnimationProgram (lul_device, programId, programName)
	if (not pluginParams.isConfigured) then
		debug("setTarget", "Device not initialized")
		return
	end
	debug("startAnimationProgram", "Start animation program id: " .. tostring(programId) .. ", name: " .. tostring(programName))
	RGBDeviceTypes[pluginParams.rgbDeviceType].startAnimationProgram(lul_device, programId, programName)
end

-- Get animation program names
function getAnimationProgramNames (lul_device)
	debug("getAnimationProgramList", "Get animation program names")
	if (pluginParams.isConfigured) then
		local programNames = RGBDeviceTypes[pluginParams.rgbDeviceType].getAnimationProgramNames(lul_device)
		luup.variable_set(SID.RGB_CONTROLLER, "LastResult", json.encode(programNames), lul_device)
	else
		debug("getAnimationProgramNames", "Device not initialized")
		luup.variable_set(SID.RGB_CONTROLLER, "LastResult", "", lul_device)
	end
end

-- Get supported color channel names
function getColorChannelNames (lul_device)
	debug("getColorChannelList", "Get color channel names")
	if (pluginParams.isConfigured) then
		local channelNames = RGBDeviceTypes[ pluginParams.rgbDeviceType ].getColorChannelNames(lul_device)
		luup.variable_set(SID.RGB_CONTROLLER, "LastResult", json.encode(channelNames), lul_device)
	else
		debug("getColorChannelNames", "Device not initialized")
		luup.variable_set(SID.RGB_CONTROLLER, "LastResult", "", lul_device)
	end
end

-- Get RGB device types
function getRGBDeviceTypes (lul_device)
	debug("getRGBDeviceTypes", "Get RGB device types")
	local RGBDeviceTypesParameters = {}
	for typeName, RGBDeviceType in pairs(RGBDeviceTypes) do
		RGBDeviceTypesParameters[typeName] = RGBDeviceType.getParameters(lul_device)
	end
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

