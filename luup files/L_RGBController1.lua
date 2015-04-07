-- Plugin constants
local SID_RGBController = "urn:upnp-org:serviceId:RGBController1"
local SID_SwitchPower = "urn:upnp-org:serviceId:SwitchPower1"
local SID_Dimming = "urn:upnp-org:serviceId:Dimming1"
local SID_ZWaveNetwork = "urn:micasaverde-com:serviceId:ZWaveNetwork1"

-------------------------------------------
-- Plugin variables
-------------------------------------------

local PLUGIN_NAME = "RGBController"
local PLUGIN_VERSION = "1.1"
local DEBUG_MODE = false
local pluginParams = {}

-------------------------------------------
-- UI compatibility
-------------------------------------------

-- Update static JSON file
local function updateStaticJSONFile (pluginName)
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

-- Get child device for given color name
local function getRGBChildDeviceId(lul_device, colorName)
	local rgbChildDeviceId = nil
	local colorAlias = pluginParams.colorAliases[colorName]
	if (colorAlias ~= nil) then
		rgbChildDeviceId = pluginParams.rgbChildDeviceIds[colorAlias]
	end
	if (rgbChildDeviceId == nil) then
		warning("getRGBChildDeviceId", "Child not found for device " .. tostring(lul_device) .. " - color " .. tostring(colorName) .. " - colorAlias " .. tostring(colorAlias))
	end
	return rgbChildDeviceId
end

-- Get level for a specified color
local function getColorLevel(lul_device, colorName)
	local colorLevel = nil
	local rgbChildDeviceId = getRGBChildDeviceId(lul_device, colorName)
	if (rgbChildDeviceId ~= nil) then
		local colorLoadLevel = luup.variable_get(SID_Dimming, "LoadLevelStatus", rgbChildDeviceId) or 0
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
		luup.call_action(SID_Dimming, "SetLoadLevelTarget", {newLoadlevelTarget = loadLevel}, rgbChildDeviceId)
	else
		return false
	end
	return true
end

-- Set load level for a specified color and a hex value
local function getZWaveDataToSendFromHexColor(lul_device, colorName, hexColor)
	local colorAlias = pluginParams.colorAliases[colorName]
	local data = "0x00"
	if (colorAlias == "e2") then
		-- Red
		data = "0x02"
	elseif (colorAlias == "e3") then
		-- Green
		data = "0x03"
	elseif (colorAlias == "e4") then
		-- Blue
		data = "0x04"
	elseif (colorAlias == "e5") then
		-- Warm white
		data = "0x00"
	elseif (colorAlias == "e6") then
		-- Cool white (just work with Zipato)
		data = "0x01"
	end
	return data .. " 0x" .. hexColor
end

-- Set load level for a specified color and a hex value
local primaryColorPos = {
	["red"]   = { 1, 2 },
	["green"] = { 3, 4 },
	["blue"]  = { 5, 6 },
	["white"] = { 7, 8 }
}
local function getComponentColor(color, colorName)
	return color:sub(primaryColorPos[colorName][1], primaryColorPos[colorName][2])
end

-- Retrieves colors from controlled RGB device
-- Works just for Fibaro RGBW (must have child devices)
local function initFromRGBDevice (lul_device)
	-- Set color from color levels of the slave device
	local formerColor = luup.variable_get(SID_RGBController, "Color", lul_device)
	formerColor = formerColor:gsub("#","")
	local r = toHex(getColorLevel(lul_device, "red"))   or getComponentColor(formerColor, "red")
	local g = toHex(getColorLevel(lul_device, "green")) or getComponentColor(formerColor, "green")
	local b = toHex(getColorLevel(lul_device, "blue"))  or getComponentColor(formerColor, "blue")
	local w = toHex(getColorLevel(lul_device, "white")) or getComponentColor(formerColor, "white")
	local color = r .. g .. b .. w
	debug("initFromRGBDevice", "Get current color : #" .. color)
	if (formerColor ~= color) then
		luup.variable_set(SID_RGBController, "Color", "#" .. color, lul_device)
	end

	-- Set the status of the controller from slave status
	--local loadLevelStatus = tonumber((luup.variable_get(SID_Dimming, "LoadLevelStatus", pluginParams.rgbDeviceId)))
	if (luup.variable_get(SID_SwitchPower, "Status", pluginParams.rgbDeviceId) == "1") then
		luup.variable_set(SID_SwitchPower, "Status", "1", lul_device)
	else
		luup.variable_set(SID_SwitchPower, "Status", "0", lul_device)
	end
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
-- Main functions
-------------------------------------------

-- Set status
function setTarget (lul_device, newTargetValue)
	debug("setTarget", "Set device status : " .. tostring(newTargetValue))
	if (tostring(newTargetValue) == "1") then
		luup.call_action(SID_SwitchPower, "SetTarget", {newTargetValue = "1"}, pluginParams.rgbDeviceId)
		luup.variable_set(SID_SwitchPower, "Status", "1", lul_device)
	else
		luup.call_action(SID_SwitchPower, "SetTarget", {newTargetValue = "0"}, pluginParams.rgbDeviceId)
		luup.variable_set(SID_SwitchPower, "Status", "0", lul_device)
	end
end

-- Set color
function setColorTarget (lul_device, newColor)
	local formerColor = luup.variable_get(SID_RGBController, "Color", lul_device)
	formerColor = formerColor:gsub("#","")

	-- Compute color
	if (newColor == "") then
		-- Wanted color has not been sent, keep former
		newColor = formerColor
	else
		newColor = newColor:gsub("#","")
		if ((newColor:len() ~= 6) and (newColor:len() ~= 8)) then
			error("Color '" .. tostring(newColor) .. "' has bad format. Should be '#[a-fA-F0-9]{6}' or '#[a-fA-F0-9]{8}'")
			return false
		end
		if (newColor:len() == 6) then
			-- White component not sent, keep former value
			newColor = newColor .. formerColor:sub(7, 8)
		end
		luup.variable_set(SID_RGBController, "Color", "#" .. newColor, lul_device)
	end

	-- Compute device status
	local status = luup.variable_get(SID_SwitchPower, "Status", lul_device)
	if (newColor == "00000000") then
		if (status == "1") then
			luup.variable_set(SID_SwitchPower, "Status", "0", lul_device)
		end
	elseif (status == "0") then
		luup.variable_set(SID_SwitchPower, "Status", "1", lul_device)
	end

	-- Set new color
	debug("setColorTarget", "Set color RGBW #" .. newColor)

	-- Send the RGB color by ZWave
	local data
	--if (newColor ~= formerColor) then
		data = "0x33 0x05 0x04"
		data = data .. " " .. getZWaveDataToSendFromHexColor(lul_device, "red",   getComponentColor(newColor, "red"))
		data = data .. " " .. getZWaveDataToSendFromHexColor(lul_device, "green", getComponentColor(newColor, "green"))
		data = data .. " " .. getZWaveDataToSendFromHexColor(lul_device, "blue",  getComponentColor(newColor, "blue"))
		data = data .. " " .. getZWaveDataToSendFromHexColor(lul_device, "white", getComponentColor(newColor, "white"))
		debug("setColorTarget", "Send Zwave command " .. data)
		luup.call_action(SID_ZWaveNetwork, "SendData", {Node = pluginParams.rgbZwaveNode, Data = data}, 1)
	--end
end

-- Get current RGBW color
-- Doesn't work !
function getColor (lul_device)
	local color = luup.variable_get(SID_RGBController, "Color", lul_device)
	return color:gsub("#","")
end

-- Start animation program
local animationPrograms = {
	["Fireplace"] = 6,
	["Storm"] = 7,
	["Rainbow"] = 8,
	["Aurora"] = 9,
	["LPD"] = 10
}
function startAnimationProgram (lul_device, programId, programName)
	local programId = tonumber(programId) or 0
	debug("startAnimationProgram", "programId " .. tostring(programId).. " programName " .. tostring(programName))
	if (programName ~= nil) then
		programId = animationPrograms[programName] or 0 
	end
	if (programId > 0) then
		debug("startAnimationProgram", "Start animation program #" .. tostring(programId))
		luup.call_action(SID_ZWaveNetwork, "SendData", {Node = pluginParams.rgbZwaveNode, Data = "0x70 0x04 0x48 0x01 0x" .. toHex(programId)}, 1)
	else
		debug("startAnimationProgram", "Stop animation program")
		setColorTarget(lul_device, "")
	end
end

-------------------------------------------
-- Startup
-------------------------------------------

-- Init plugin instance
function initPluginInstance (lul_device)
	log("initPluginInstance", "Init")

	-- Get plugin params for this device
	getVariableOrInit(lul_device, SID_SwitchPower, "Status", "0")
	pluginParams = {
		rgbDeviceId = tonumber(getVariableOrInit(lul_device, SID_RGBController, "DeviceId", "0")),
		rgbDeviceType = getVariableOrInit(lul_device, SID_RGBController, "DeviceType", ""),
		rgbChildDeviceIds = {},
		color = getVariableOrInit(lul_device, SID_RGBController, "Color", "#00000000"),
		colorAliases = {
			red   = getVariableOrInit(lul_device, SID_RGBController, "RedAlias",   "e2"),
			green = getVariableOrInit(lul_device, SID_RGBController, "GreenAlias", "e3"),
			blue  = getVariableOrInit(lul_device, SID_RGBController, "BlueAlias",  "e4"),
			white = getVariableOrInit(lul_device, SID_RGBController, "WhiteAlias", "e5")
		}
	}

	-- Get debug mode
	DEBUG_MODE = (getVariableOrInit(lul_device, SID_RGBController, "Debug", "0") == "1")

	if (pluginParams.rgbDeviceId == 0) then
		error("Device #" .. tostring(lul_device) .. " is not configured")
		luup.variable_set(SID_SwitchPower, "Status", "0", lul_device)
		luup.variable_set(SID_RGBController, "Color", "#00000000", lul_device)
		luup.set_failure(1, lul_device)
		--message = "Not configured"
	else
		pluginParams.rgbZwaveNode = luup.devices[pluginParams.rgbDeviceId].id
		-- Find child devices (if exist) of the main controller
		for deviceId, device in pairs(luup.devices) do
			if (device.device_num_parent == pluginParams.rgbDeviceId) then
				debug("initPluginInstance", "Device #" .. tostring(lul_device) .. " - Slave device #" .. tostring(pluginParams.rgbDeviceId) .. " - Find child device '" .. tostring(device.id) .. "' #" .. tostring(deviceId) .. " '" .. device.description .. "'")
				pluginParams.rgbChildDeviceIds[device.id] = deviceId
			end
		end
		-- Get color levels and status from slave
		initFromRGBDevice(lul_device)

		if (luup.version_major >= 7) then
			luup.set_failure(0, lul_device)
		end
	end
end

function startup (lul_device)
	log("startup", "Start plugin '" .. PLUGIN_NAME .. "' (v" .. PLUGIN_VERSION .. ")")

	-- Update static JSON file
	if updateStaticJSONFile(PLUGIN_NAME .. "1") then
		warning("startup", "'device_json' has been updated : reload LUUP engine")
		luup.reload()
		return false, "Reload LUUP engine"
	end

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

