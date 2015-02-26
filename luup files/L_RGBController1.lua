-- Plugin constants
local SID_RGBController = "urn:upnp-org:serviceId:RGBController1"
local SID_SwitchPower = "urn:upnp-org:serviceId:SwitchPower1"
local SID_Dimming = "urn:upnp-org:serviceId:Dimming1"
local SID_ZWaveNetwork = "urn:micasaverde-com:serviceId:ZWaveNetwork1"

-------------------------------------------
-- Plugin variables
-------------------------------------------

local PLUGIN_NAME = "RGBController"
local PLUGIN_VERSION = "0.9"
local DEBUG_MODE = false
local pluginsParams = {}

-------------------------------------------
-- UI7 compatibility
-------------------------------------------

-- Check static JSON file
local function checkStaticJSONFile (pluginName)
	if (luup.version_branch ~= 1) then
		luup.log("ERROR - Plugin '" .. pluginName .. "' - checkStaticJSONFile : don't know how to do with this version branch " .. tostring(luup.version_branch), 1)
		return
	end
	local currentStaticJsonFile = luup.attr_get("device_json", lul_device)
	local expectedStaticJsonFile = "D_" .. pluginName .. "_UI" .. tostring(luup.version_major) .. ".json"
	if (currentStaticJsonFile ~= expectedStaticJsonFile) then
		luup.attr_set("device_json", expectedStaticJsonFile, lul_device)
		luup.log("Plugin '" .. pluginName .. "' - 'device_json' has been updated : reload LUUP engine")
		luup.reload()
	end
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
	luup.log("(" .. PLUGIN_NAME .. "::" .. tostring(methodName) .. ") " .. text, (level or 50))
end

local function error(methodName, text)
	log(methodName, "ERROR: " .. text, 1)
end

local function warning(methodName, text)
	log(methodName, "WARNING: " .. text, 2)
end

local function debug(methodName, text)
	if (DEBUG_MODE) then
		log(methodName, "DEBUG: " .. text)
	end
end

-- Convert num to hex
local function toHex(num)
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

-- Get child device for given color name
local function getChildDeviceId(lul_device, colorName)
	local pluginParams = pluginsParams[lul_device]
	local rgbChildDeviceId = nil
	local colorAlias = pluginParams.colorAliases[colorName]
	if (colorAlias ~= nil) then
		rgbChildDeviceId = pluginParams.rgbChildDeviceIds[colorAlias]
	end
	if (rgbChildDeviceId == nil) then
		warning("getChildDeviceId", "Child not found for device " .. tostring(lul_device) .. " - color " .. tostring(colorName) .. " - colorAlias " .. tostring(colorAlias))
	end
	return rgbChildDeviceId
end

-- Get level for a specified color
local function getColorLevel(lul_device, colorName)
	local colorLevel = 0
	local rgbChildDeviceId = getChildDeviceId(lul_device, colorName)
	if (rgbChildDeviceId ~= nil) then
		local colorLoadLevel = luup.variable_get(SID_Dimming, "LoadLevelStatus", rgbChildDeviceId) or 0
		colorLevel = math.ceil(tonumber(colorLoadLevel) * 2.55)
	end
	return colorLevel
end

-- Set load level for a specified color and a hex value
local function setLoadLevelFromHexColor(lul_device, colorName, hexColor)
	debug("setLoadLevelFromHexColor", "Device: " .. tostring(lul_device) .. ", colorName: " .. tostring(colorName) .. ", hexColor: " .. tostring(hexColor))
	local rgbChildDeviceId = getChildDeviceId(lul_device, colorName)
	if (rgbChildDeviceId ~= nil) then
		local loadLevel = math.floor(tonumber("0x" .. hexColor) * 100/255)
		luup.call_action(SID_Dimming, "SetLoadLevelTarget", {newLoadlevelTarget = loadLevel}, rgbChildDeviceId)
	else
		return false
	end
	return true
end

-- Set load level for a specified color and a hex value
local function getDataToSendFromHexColor(lul_device, colorName, hexColor)
	local pluginParams = pluginsParams[lul_device]
	local colorAlias = pluginParams.colorAliases[colorName]
	local data = "0x00"
	if (colorAlias == "e2") then
		-- red
		data = "0x02"
	elseif (colorAlias == "e3") then
		-- green
		data = "0x03"
	elseif (colorAlias == "e4") then
		-- blue
		data = "0x04"
	end
	return data .. " 0x" .. hexColor
end

-- Retrieve colors from controlled RGB device
local function initFromSlave (lul_device)
	local pluginParams = pluginsParams[lul_device]

	-- Set color from color levels of the slave device
	local r = getColorLevel(lul_device, "red")
	local g = getColorLevel(lul_device, "green")
	local b = getColorLevel(lul_device, "blue")
	local w = getColorLevel(lul_device, "white")
	local color = "#" .. toHex(r) .. toHex(g) .. toHex(b) .. toHex(w)
	debug("initFromSlave", "Get current color : rgbw(" .. tostring(r) .. "," .. tostring(g) .. "," .. tostring(b) .. "," .. tostring(w) .. ") " .. color)
	luup.variable_set(SID_RGBController, "Color", color, lul_device)

	-- Set the status of the controller from slave status
	local loadLevelStatus = tonumber((luup.variable_get(SID_Dimming, "LoadLevelStatus", pluginParams.rgbDeviceId)))
	if (loadLevelStatus > 0) then
		--luup.variable_set(SID_RGBController, "Status", "1", lul_device)
		luup.variable_set(SID_SwitchPower, "Status", "1", lul_device)
	else
		--luup.variable_set(SID_RGBController, "Status", "0", lul_device)
		luup.variable_set(SID_SwitchPower, "Status", "0", lul_device)
	end
end

-------------------------------------------
-- Main functions
-------------------------------------------

-- Set color
function setColorTarget (lul_device, newColor)
	local pluginParams = pluginsParams[lul_device]
	local oldColor = luup.variable_get(SID_RGBController, "Color", lul_device)
	oldColor = oldColor:gsub("#","")

	-- Compute color
	if (newColor == "") then
		newColor = oldColor
	else
		newColor = newColor:gsub("#","")
		if ((newColor:len() ~= 6) and (newColor:len() ~= 8)) then
			error("Color '" .. tostring(newColor) .. "' has bad format. Should be '#dddddd' or '#dddddddd'")
			return false
		end
		if (newColor:len() == 6) then
			-- White not send, keep old value
			newColor = newColor .. oldColor:sub(7, 8)
		end
		luup.variable_set(SID_RGBController, "Color", newColor, lul_device)
	end

	-- Compute device status
	--local status = luup.variable_get(SID_RGBController, "Status", lul_device)
	local status = luup.variable_get(SID_SwitchPower, "Status", lul_device)
	if ((newColor == "00000000") and (status == "1")) then
		--luup.variable_set(SID_RGBController, "Status", "0", lul_device)
		luup.variable_set(SID_SwitchPower, "Status", "0", lul_device)
	elseif (status == "0") then
		--luup.variable_set(SID_RGBController, "Status", "1", lul_device)
		luup.variable_set(SID_SwitchPower, "Status", "1", lul_device)
	end

	-- Set new color
	debug("setColorTarget", "Set color RGBW #" .. newColor)
	-- DEPRECATED : Vera FGRGB implementation is buggy. Lags on color change.
	--setLoadLevelFromHexColor(lul_device, "red",   newColor:sub(1, 2))
	--setLoadLevelFromHexColor(lul_device, "green", newColor:sub(3, 4))
	--setLoadLevelFromHexColor(lul_device, "blue",  newColor:sub(5, 6))
	--setLoadLevelFromHexColor(lul_device, "white", newColor:sub(7, 8))
	local data = "0x33 0x05 0x06"
	data = data .. " " .. getDataToSendFromHexColor(lul_device, "red",   newColor:sub(1, 2))
	data = data .. " " .. getDataToSendFromHexColor(lul_device, "green", newColor:sub(3, 4))
	data = data .. " " .. getDataToSendFromHexColor(lul_device, "blue",  newColor:sub(5, 6))
	luup.call_action(SID_ZWaveNetwork, "SendData", {Node = pluginParams.rgbZwaveNode, Data = data}, 1)
	-- ARRRRR !!! the white color is not set with the multi Zwave command !
	data = "0x33 0x05 0x02 " .. getDataToSendFromHexColor(lul_device, "white", newColor:sub(7, 8))
	luup.call_action(SID_ZWaveNetwork, "SendData", {Node = pluginParams.rgbZwaveNode, Data = data}, 1)
	
	local newWhiteColor = newColor:sub(7, 8)
	if (newWhiteColor ~= oldColor:sub(7, 8)) then
		setLoadLevelFromHexColor(lul_device, "white", newWhiteColor)
	end

	return true
end

-- Set status
function setTarget (lul_device, newTargetValue)
	local pluginParams = pluginsParams[lul_device]

	debug("setTarget", "Set device status : " .. tostring(newTargetValue))
	if (tostring(newTargetValue) == "1") then
		luup.call_action(SID_Dimming, "SetLoadLevelTarget", {newLoadlevelTarget = "100"}, pluginParams.rgbDeviceId)
		--luup.variable_set(SID_RGBController, "Status", "1", lul_device)
		luup.variable_set(SID_SwitchPower, "Status", "1", lul_device)
	else
		luup.call_action(SID_Dimming, "SetLoadLevelTarget", {newLoadlevelTarget = "0"}, pluginParams.rgbDeviceId)
		--luup.variable_set(SID_RGBController, "Status", "0", lul_device)
		luup.variable_set(SID_SwitchPower, "Status", "0", lul_device)
	end

	return true
end

-- Start animation program
function startAnimationProgram (lul_device, programId)
	local pluginParams = pluginsParams[lul_device]

	local programId = tonumber(programId) or 0
	if (programId > 0) then
		debug("startAnimationProgram", "Start animation program #" .. tostring(programId))
		luup.call_action(SID_ZWaveNetwork, "SendData", {Node = pluginParams.rgbZwaveNode, Data = "0x70 0x04 0x48 0x01 0x" .. toHex(programId)}, 1)
	else
		debug("startAnimationProgram", "Stop animation program")
		setColorTarget(lul_device, "")
	end

	return true
end

-------------------------------------------
-- Startup
-------------------------------------------

-- Change debug level log
function onDebugValueIsUpdated (lul_device, lul_service, lul_variable, lul_value_old, lul_value_new)
	if (lul_value_new == "1") then
		log("onDebugValueIsUpdated", "Enable debug mode")
		DEBUG_MODE = true
	else
		log("onDebugValueIsUpdated", "Disable debug mode")
		DEBUG_MODE = false
	end
end

-- Init plugin instance
function initPluginInstance (lul_device)
	log("initPluginInstance", "Init")

	-- Get plugin params for this device
	--getVariableOrInit(lul_device, SID_RGBController, "Status", "0")
	getVariableOrInit(lul_device, SID_SwitchPower, "Status", "0")
	local pluginParams = {
		deviceName = "RGBController[" .. tostring(lul_device) .. "]",
		rgbDeviceId = tonumber(getVariableOrInit(lul_device, SID_RGBController, "DeviceId", "0")),
		rgbChildDeviceIds = {},
		color = getVariableOrInit(lul_device, SID_RGBController, "Color", "#00000000"),
		colorAliases = {
			red   = getVariableOrInit(lul_device, SID_RGBController, "RedAlias",   "e2"),
			green = getVariableOrInit(lul_device, SID_RGBController, "GreenAlias", "e3"),
			blue  = getVariableOrInit(lul_device, SID_RGBController, "BlueAlias",  "e4"),
			white = getVariableOrInit(lul_device, SID_RGBController, "WhiteAlias", "e5")
		}
	}
	pluginsParams[lul_device] = pluginParams

	-- Get debug mode
	DEBUG_MODE = (getVariableOrInit(lul_device, SID_RGBController, "Debug", "0") == "1")

	if (pluginParams.rgbDeviceId == 0) then
		error("Device #" .. tostring(lul_device) .. " is not configured")
		--luup.variable_set(SID_RGBController, "Status", "0", lul_device)
		luup.variable_set(SID_SwitchPower, "Status", "0", lul_device)
		luup.variable_set(SID_RGBController, "Color", "#00000000", lul_device)
		luup.set_failure(1, lul_device)
		--message = "Not configured"
	else
		pluginParams.rgbZwaveNode = luup.devices[pluginParams.rgbDeviceId].id
		-- Find child devices of the main controller
		for deviceId, device in pairs(luup.devices) do
			if (device.device_num_parent == pluginParams.rgbDeviceId) then
				debug("initPluginInstance", "Device #" .. tostring(lul_device) .. " - Slave device #" .. tostring(pluginParams.rgbDeviceId) .. " - Find child device '" .. tostring(device.id) .. "' #" .. tostring(deviceId) .. " '" .. device.description .. "'")
				pluginParams.rgbChildDeviceIds[device.id] = deviceId
			end
		end
		-- Get color levels and status from slave
		initFromSlave(lul_device)
	end
end

function startup (lul_device)
	log("startup", "Start plugin '" .. PLUGIN_NAME .. "' (v" .. PLUGIN_VERSION .. ")")

	if (luup.version_major >= 7) then
		luup.set_failure(0, lul_device)
	end

	-- Check static JSON file
	checkStaticJSONFile(PLUGIN_NAME .. "1")

	-- Init
	initPluginInstance(lul_device)

	-- Register
	luup.variable_watch("initPluginInstance", SID_RGBController, "DeviceId", lul_device)
	luup.variable_watch("initPluginInstance", SID_RGBController, "RedAlias", lul_device)
	luup.variable_watch("initPluginInstance", SID_RGBController, "GreenAlias", lul_device)
	luup.variable_watch("initPluginInstance", SID_RGBController, "BlueAlias", lul_device)
	luup.variable_watch("initPluginInstance", SID_RGBController, "WhiteAlias", lul_device)
	luup.variable_watch("onDebugValueIsUpdated", SID_RGBController, "Debug", lul_device)

	return true
end
