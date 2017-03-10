//@ sourceURL=J_RGBController1.js
// Debug in UI7 :
//config.logLevel = UI_LOG_LEVEL_DEBUG;

var RGBController = (function (api, $) {

	var uuid = "e76e1855-ea23-46c0-8dda-4b1a9d852bc6";
	var RGB_CONTROLLER_SID = "urn:upnp-org:serviceId:RGBController1";
	var myModule = {};
	var _deviceId = null;
	var _rgbDeviceType = null;
	var _color = "#0000000000";
	var _status = "0";

	// UI5 and ALTUI compatibility
	if (api === null) {
		api = {
			version: "UI5",
			getListOfDevices: function () {
				return jsonp.ud.devices;
			},
			setCpanelContent: function (html) {
				set_panel_html(html);
			},
			getDeviceStateVariable: function (deviceId, service, variable, options) {
				return get_device_state(deviceId, service, variable, (options.dynamic === true ? 1: 0));
			},
			setDeviceStateVariable: function (deviceId, service, variable, value, options) {
				set_device_state(deviceId, service, variable, value, (options.dynamic === true ? 1: 0));
			},
			setDeviceStateVariablePersistent: function (deviceId, service, variable, value, options) {
				set_device_state(deviceId, service, variable, value, 0);
			},
			performActionOnDevice: function (deviceId, service, action, options) {
				var query = "id=lu_action&DeviceNum=" + deviceId + "&serviceId=" + service + "&action=" + action;
				$.each(options.actionArguments, function (key, value) {
					query += "&" + key + "=" + value;
				});
				$.ajax({
					url: data_request_url + query,
					success: function (data, textStatus, jqXHR) {
						if (typeof(options.onSuccess) == 'function') {
							options.onSuccess({
								responseText: jqXHR.responseText,
								status: jqXHR.status
							});
						}
					},
					error: function (jqXHR, textStatus, errorThrown) {
						if (typeof(options.onFailure) != 'undefined') {
							options.onFailure({
								responseText: jqXHR.responseText,
								status: jqXHR.status
							});
						}
					}
				});
			},
			registerEventHandler: function (eventName, object, functionName) {
				// Not implemented
			}
		};
	}
	var myInterface = window.myInterface;
	if (typeof myInterface === 'undefined') {
		myInterface = {
			showModalLoading: function () {
				if ($.isFunction(show_loading)) {
					show_loading();
				}
			},
			hideModalLoading: function () {
				if ($.isFunction(hide_loading)) {
					hide_loading();
				}
			}
		};
	}
	var Utils = window.Utils;
	if (typeof Utils === 'undefined') {
		Utils = {
			logError: function (message) {
				console.error(message);
			},
			logDebug: function (message) {
				if ($.isPlainObject(window.AltuiDebug)) {
					AltuiDebug.debug(message);
				} else {
					//console.info(message);
				}
			}
		};
	}

	// Inject plugin specific CSS rules
	if ($("style[title=\"RGBController custom CSS\"]").size() == 0) {
		Utils.logDebug("[RGBController.init] Injects custom CSS");
		var pluginStyle = $("<style>");
		if ($.fn.jquery == "1.5") {
			pluginStyle.attr("type", "text/css")
				.attr("title", "RGBController custom CSS");
		} else {
			pluginStyle.prop("type", "text/css")
				.prop("title", "RGBController custom CSS");
		}
		pluginStyle
			.html("\
				#RGBController_controls { width: 400px; margin: 20px auto; }\
				#RGBController_colorpicker { display: inline-block; margin-right: 10px; }\
				#RGBController_sliders { display: inline-block; margin-left: 50px; } \
				#RGBController_sliders .ui-slider { display: inline-block; height: 180px; width: 19px; margin-left: 10px; }\
				#RGBController_sliders .ui-slider-range, #RGBController_sliders .ui-slider-handle { background-image: url('');  }\
				#RGBController_sliders .ui-slider-vertical { border-radius: 25px; }\
				#RGBController_sliders .ui-slider-handle { width: 25px; }\
				#RGBController_red .ui-slider-range, #RGBController_red .ui-slider-handle { background-color: #ef2929 !important; }\
				#RGBController_green .ui-slider-range, #RGBController_green .ui-slider-handle { background-color: #8ae234 !important; }\
				#RGBController_blue .ui-slider-range, #RGBController_blue .ui-slider-handle { background-color: #729fcf !important; }\
				#RGBController_warmWhite .ui-slider-range, #RGBController_warmWhite .ui-slider-handle { background-color: #FBE616 !important; }\
				#RGBController_coolWhite .ui-slider-range, #RGBController_coolWhite .ui-slider-handle { background-color: #FFFF88 !important; }\
				#RGBController_swatch {\
					height: 25px; margin-top: 30px; border-radius: 25px; padding: 1px 25px; text-align: center; \
					background-image: none;  border: none; background-color: black;\
				}\
				#RGBController_innerswatch {\
					line-height: 25px; width: 180px; font:bold 19px arial; text-align: center;\
					color: white; width 150px; display: inline-block; vertical-align: middle;\
				}\
				#RGBController_swatch button { height:23px; width:40px; }\
				#RGBController_swatch input { width:40px; height:23px; text-align:center; }\
				#RGBController_program { height: 25px; margin-top: 10px; border-radius: 25px; padding: 0px 25px; text-align: center; }\
				#RGBController_programs { width:60%; height:23px; }\
				#RGBController_settings { width:80%; margin: 20px auto; }\
				#RGBController_settings .RGBController_setting { margin-top: 10px; border-radius: 25px; padding: 1px 25px; text-align: left; }\
				#RGBController_settings .RGBController_setting span { display: inline-block; width: 30%; }\
				#RGBController_settings .RGBController_setting select { width: 70%; }\
				#RGBController_settings .RGBController_setting input { width: 69%; }\
				#RGBController_specificSettings .RGBController_setting { background: #FBA01C !important; }\
				#RGBController_saveSettings { text-align: center !important; }\
			")
			.appendTo("head");
	} else {
		Utils.logDebug("[RGBController.init] Injection of custom CSS has already been done");
	}

	/**
	 *
	 */
	function showError (response) {
		api.setCpanelContent(
				"<p>There has been a communication problem.</p>"
			+	"<p>Please try to reopen this tab.</p>"
			+	(typeof response.responseText !== 'undefined' ?  "<p>" + response.responseText + "</p>" : "" )
		);
	}

	/**
	 * Update color wheel according to external event
	 */
	function onDeviceStatusChanged (deviceObjectFromLuStatus) {
		if (deviceObjectFromLuStatus.id == _deviceId) {
			for (i = 0; i < deviceObjectFromLuStatus.states.length; i++) { 
				if (deviceObjectFromLuStatus.states[i].variable == "Color") {
					var newColor = deviceObjectFromLuStatus.states[i].value;
					if (newColor !== _color) {
						Utils.logDebug("[RGBController.onDeviceStatusChanged] Device #" + _deviceId + " color has been set to " + newColor);
						updateColorWheel(newColor);
					} else {
						Utils.logDebug("[RGBController.onDeviceStatusChanged] Device #" + _deviceId + " color is the current color " + _color);
					}
				} else if (deviceObjectFromLuStatus.states[i].variable == "Status") {
					_status = deviceObjectFromLuStatus.states[i].value;
					if (_status === "1") {
						$("#RGBController_off").removeClass("ui-state-highlight");
						$("#RGBController_on").addClass("ui-state-highlight");
					} else {
						$("#RGBController_off").addClass("ui-state-highlight");
						$("#RGBController_on").removeClass("ui-state-highlight");
					}
				}
			}
		}
	}

	/**
	 * Show color wheel panel
	 */
	function showColorWheel (deviceId) {
		try {
			_deviceId = deviceId;
			Utils.logDebug("[RGBController.showColorWheel] Show color wheel for device " + _deviceId);
			api.setCpanelContent(
					'<div id="RGBController_controls">'
				+		"<p>The plugin is not configured. Please go to the 'Settings' tab.</p>"
				+	'</div>'
			);

			var isConfigured = (api.getDeviceStateVariable(_deviceId, RGB_CONTROLLER_SID, "Configured", {dynamic: false}) === "1");
			if (isConfigured) {
				_rgbDeviceType = api.getDeviceStateVariable(_deviceId, RGB_CONTROLLER_SID, "DeviceType", {dynamic: false});
				_color = "#0000000000";
				var colorFromStateVariable = api.getDeviceStateVariable(_deviceId, RGB_CONTROLLER_SID, "Color", {dynamic: true});
				if (typeof colorFromStateVariable === "string") {
					var checkedColor = colorFromStateVariable.match(/[a-fA-F0-9]{10}/);
					if (checkedColor != null) {
						_color = "#" + checkedColor[0];
					}
				}
				_status = api.getDeviceStateVariable(_deviceId, SWP_SID, "Status", {dynamic: true});
				Utils.logDebug("[RGBController.showColorWheel] RGB device type:" + _rgbDeviceType + " - Color:" + _color);
				$("#RGBController_controls").empty();
				myInterface.showModalLoading();
				$.when(
					getColorChannelNames(_deviceId),
					getAnimationPrograms(_deviceId)
				).then(
					function (channelNames, programs) {
						drawAndManageColorWheel(_deviceId, _rgbDeviceType, _color, channelNames, programs);
						myInterface.hideModalLoading();
					},
					function (response) {
						showError(response);
						myInterface.hideModalLoading();
					}
				);
			}

			// Register
			api.registerEventHandler("on_ui_deviceStatusChanged", myModule, "onDeviceStatusChanged");
		} catch (err) {
			Utils.logError('Error in RGBController.showColorWheel: ' + err);
		}
	}

	/**
	 * Update the color wheel
	 */
	function updateColorWheel (color) {
		if ($("#RGBController_controls").size() > 0) {
			updateColorPicker(color);
			updateSliders(color);
			updateSwatch(color);
		}
	}
	function updateSliders (color) {
		Utils.logDebug("[RGBController.updateSliders] Update sliders with color " + color);
		var red = parseInt(color.substring(1, 3), 16);
		var green = parseInt(color.substring(3, 5), 16);
		var blue = parseInt(color.substring(5, 7), 16);
		$("#RGBController_red").slider("value", red);
		$("#RGBController_green").slider("value", green);
		$("#RGBController_blue").slider("value", blue);
		if (color.length > 7) {
			var warmWhite = parseInt(color.substring(7, 9), 16);
			var coolWhite = parseInt(color.substring(9, 11), 16);
			$("#RGBController_warmWhite").slider("value", warmWhite);
			$("#RGBController_coolWhite").slider("value", coolWhite);
		}
	}
	function updateColorPicker (color) {
		var rgbColor = color.substring(0, 7);
		Utils.logDebug("[RGBController.updateColorPicker] Update color picker with RGB color " + rgbColor);
		var colorPicker = $.farbtastic("#RGBController_colorpicker");
		if (colorPicker != null) {
			colorPicker.setColor(rgbColor, false);
		}
	}
	function updateSwatch (color) {
		color = color.toUpperCase();
		$("#RGBController_swatch").attr('style', 'background-color: ' + color.substring(0, 7) + ' !important');
		var colorPicker = $.farbtastic("#RGBController_colorpicker");
		if ((colorPicker != null) && $.isArray(colorPicker.hsl) && (colorPicker.hsl[2] > 0.5)) {
			$("#RGBController_innerswatch").css("color", "#000000");    
		} else {
			$("#RGBController_innerswatch").css("color", "#ffffff");  
		}
		$("#RGBController_innerswatch").html(color);
	}

	/**
	 * Draw and manage the color wheel
	 */
	function drawAndManageColorWheel (deviceId, rgbDeviceType, color, channelNames, programs) {
		var lastSendDate = +new Date();
		var sendTimer = 0;
		_color = color;
		var rgbColor = color.substring(0, 7);
		var warmWhiteColor = color.substring(7, 9);
		var coolWhiteColor = color.substring(9, 11);

		Utils.logDebug("[RGBController.drawAndManageColorWheel] Draw for device " + deviceId + " with initial color " + color);

		// Color picker and sliders (according to channels managed by the rgb device)
		var html = '<div id="RGBController_colorpicker"></div>'
			+	'<div id="RGBController_sliders">';
		var colorNames = ["red", "green", "blue", "warmWhite", "coolWhite"];
		for (i = 0; i < colorNames.length; i++) {
			if (channelNames.indexOf(colorNames[i]) > -1) {
				html +=	'<div id="RGBController_' + colorNames[i] + '"></div>';
			}
		}
		html +=	'</div>'
			+	'<div id="RGBController_swatch" class="ui-widget-content ui-corner-all">'
			+		'<button id="RGBController_off" class="ui-widget-content' + (_status === '0' ? ' ui-state-highlight' : '' ) + '">OFF</button>'
			+		'<button id="RGBController_on" class="ui-widget-content' + (_status === '1' ? ' ui-state-highlight' : '' ) + '">ON</button>'
			+		'<div id="RGBController_innerswatch"></div>'
			+		'<input type="text" value="0" id="RGBController_duration" class="ui-widget-content" title="Duration of the transition (seconds)">'
			+		'<input type="text" value="10" id="RGBController_steps" class="ui-widget-content" title="Number of steps for the transition">'
			+	'</div>';

		// Animations
		if (programs.names.length > 0) {
			html += '<div id="RGBController_program" class="ui-widget-content ui-corner-all">'
			+		'<select id="RGBController_programs" class="ui-widget-content">'
			+			'<option value="" selected="selected">&lt;Animation&gt;</option>';
			for (i = 0; i < programs.names.length; i++) {
				html += '<option value="' + programs.names[i] + '">' + programs.names[i] + '</option>';
			}
			html += '</select>'
			+		'<button id="RGBController_program_start" class="ui-widget-content">Start</button>'
			+		'<button id="RGBController_program_stop" class="ui-widget-content">Stop</button>'
			+	'</div>';
		}
		$("#RGBController_controls").html(html);

		// Color wheel
		$("#RGBController_colorpicker")
			.farbtastic({
				width: 180,
				callback: function (pickerRgbColor) {
					pickerRgbColor = pickerRgbColor.toUpperCase();
					Utils.logDebug("[RGBController.onPickerUpdate] RGB is changing: " + pickerRgbColor);
					updateSliders(pickerRgbColor);
					updateSwatch(pickerRgbColor + warmWhiteColor + coolWhiteColor);
					//setColor(pickerRgbColor);
				} 
			})
			.bind('farbtastic.stop', function (event, pickerRgbColor) {
				pickerRgbColor = pickerRgbColor.toUpperCase();
				Utils.logDebug("[RGBController.onPickerUpdate] RGB has changed: " + pickerRgbColor);
				setColor(pickerRgbColor);
			});

		// Color sliders
		$("#RGBController_sliders div").slider({
			orientation: "vertical",
			min: 0,
			max: 255,
			range: "min",
			stop: function () {
				var red = $("#RGBController_red").slider("value");
				var green = $("#RGBController_green").slider("value");
				var blue = $("#RGBController_blue").slider("value");
				var warmWhite = $("#RGBController_warmWhite").slider("value");
				var coolWhite = $("#RGBController_coolWhite").slider("value");
				var color = "#" + hexFromRGBW([red, green, blue, warmWhite, coolWhite]);
				var newRgbColor = color.substring(0, 7);
				warmWhiteColor = color.substring(7, 9);
				coolWhiteColor = color.substring(9, 11);
				Utils.logDebug("[RGBController.onSliderUpdate] RGB: " + newRgbColor  + " - Warm white: " + warmWhiteColor + " - Cool white: " + coolWhiteColor);
				if (newRgbColor != rgbColor) {
					rgbColor = newRgbColor;
					updateColorPicker(rgbColor);
				}
				updateSwatch(color);
				setColor(color);
			}
		});

		// Status buttons
		$("#RGBController_off")
			.click(function (event) {
				setStatus(deviceId, "0");
			});
		$("#RGBController_on")
			.click(function (event) {
				setStatus(deviceId, "1");
			});

		// Animation programs
		$("#RGBController_program_start")
			.click(function (event) {
				var programName = $("#RGBController_programs").val();
				startAnimationProgram(deviceId, programName);
			});
		$("#RGBController_program_stop")
			.click(function (event) {
				startAnimationProgram(deviceId, "");
			});

		// Init
		updateColorPicker(rgbColor);
		updateSliders(color);
		updateSwatch(color);

		function hexFromRGBW (channelColors) {
			var result = "";
			for (i = 0; i < channelColors.length; i++) {
				if (typeof channelColors[i] == "number") {
					var value = channelColors[i].toString(16).toUpperCase();
					if (value.length === 1) {
						value = "0" + value;
					}
					result += value;
				} else {
					result += "00";
				}
			}
			return result;
		}
		function setColor (color) {
			if (color.length == 7) {
				color += warmWhiteColor + coolWhiteColor;
			}
			_color = color;
			var currentDate = +new Date();
			if (currentDate - lastSendDate < 500) {
				Utils.logDebug("[RGBController.setColor] Last send is too close, we have to wait");
				if (sendTimer == 0) {
					// No timer set yet
					sendTimer = setTimeout(sendColor, 500);
				}
			} else {
				sendColor();
			}
		}
		function sendColor() {
			sendTimer = 0;
			lastSendDate = +new Date();
			var duration = parseInt($("#RGBController_duration").val(), 10);
			var nbSteps  = $("#RGBController_steps").val();
			if (duration > 0) {
				Utils.logDebug("[RGBController.sendColor] Set color to " + _color + " for device " + deviceId + " in " + duration + " seconds and " + nbSteps + " steps");
			} else {
				Utils.logDebug("[RGBController.sendColor] Set color to " + _color + " for device " + deviceId);
			}
			api.performActionOnDevice(deviceId, RGB_CONTROLLER_SID, "SetColorTarget", {
				actionArguments: {
					output_format: "json",
					newColorTargetValue: _color.replace("#", ""),
					transitionDuration : duration,
					transitionNbSteps  : nbSteps
				},
				onSuccess: function () {
					Utils.logDebug("[RGBController.sendColor] OK");
				},
				onFailure: function (response) {
					Utils.logDebug("[RGBController.sendColor] KO - response: " + response);
				}
			});
		}
	}

	/**
	 * Search Z-Wave RGB devices
	 */
	function getZWaveRgbDevices () {
		var rgbDevices = [];
		var devices = api.getListOfDevices();
		var i, j;
		for (i = 0; i < devices.length; i++) {
			var device = devices[i];
			if (
				((device.device_type === DEVICETYPE_DIMMABLE_LIGHT) || (device.device_type.indexOf("urn:schemas-upnp-org:device:DimmableRGBLight") > -1))
				&& (device.disabled == 0) && (device.id_parent == 1)
			) {
				// Check if device responds to Z-Wave Color Command Class
				for (j = 0; j < device.states.length; j++) {
					if (device.states[j].variable == "Capabilities") {
						var supportedCommandClasses = device.states[j].value.split("|")[1].split(",");
						//if (device.states[j].value.indexOf(",51,") > -1) {
						//if (device.states[j].value.match(/[,]?51[S]?[,]?/) != null) {
						if ((supportedCommandClasses.indexOf("51") > -1) || (supportedCommandClasses.indexOf("51S") > -1)) {
							rgbDevices.push(device);
							break;
						}
					}
				}
				
			}
		}
		return rgbDevices;
	}

	/**
	 * Search dimmer devices
	 */
	function getDimmerDevices () {
		var dimmerDevices = [];
		var devices = api.getListOfDevices();
		var i, j;
		for (i = 0; i < devices.length; i++) {
			var device = devices[i];
			//if ((device.device_type == DEVICETYPE_DIMMABLE_LIGHT) && (device.disabled == 0) && (device.id_parent == 1)) {
			if ((device.device_type == DEVICETYPE_DIMMABLE_LIGHT) && (device.disabled == 0)) {
				dimmerDevices.push(device);
			}
		}
		return dimmerDevices;
	}

	/**
	 * Set RGB controller settings
	 */
	function setSettings (deviceId, settings) {
		Utils.logDebug("[RGBController.setSettings] Save settings for device " + deviceId + ": " + $.param(settings));
		$.each(settings, function (variableName, value) {
			api.setDeviceStateVariablePersistent(deviceId, RGB_CONTROLLER_SID, variableName, value);
		});
		if (api.version == "UI5") {
			$("#RGBController_message").html("Settings have been modified. Please save your changes.");
		} else {
			$("#RGBController_message").html("Settings have been modified. Please wait a few secondes that the changes appear.");
		}
	}

	/**
	 * Show setting panel
	 */
	function showSettings (deviceId) {
		try {
			Utils.logDebug("[RGBController.showSettings] Show settings for device " + deviceId);
			var rgbDeviceType = api.getDeviceStateVariable(deviceId, RGB_CONTROLLER_SID, "DeviceType", {dynamic: true});

			myInterface.showModalLoading();
			$.when(
				getRgbDeviceTypes(deviceId)
			).then(
				function (rgbDeviceTypes) {
					var html =	'<div id="RGBController_settings">'
							+		'<p>To use this RGB controller, you must first choose the type of the device that you want to control, then its specific settings.</p>'
							+		'<div class="RGBController_setting ui-widget-content ui-corner-all">'
							+			'<span>Device type</span>'
							+			'<select id="RGBController_deviceTypeSelect" class="RGBController_settingValue" data-variable="DeviceType">'
							+				'<option value="">-- Select a type --</option>';
					var indexTypes = {};
					$.each(rgbDeviceTypes, function (i, data) {
						indexTypes[data.type] = data;
						html +=				'<option value="' + data.type + '"' + (data.type === rgbDeviceType ? ' selected' : '') + '>' + data.name + '</option>';
					});
					html +=				'</select>'
							+		'</div>'
							+		'<div id="RGBController_specificSettings"></div>'
							+		'<div id="RGBController_saveSettings" class="RGBController_setting ui-widget-content ui-corner-all">'
							+			'<button>Save</button>'
							+		'</div>'
							+		'<div id="RGBController_message"></div>'
							+	'</div>';
					api.setCpanelContent(html);

					$("#RGBController_saveSettings button")
						.click(function () {
							var settings = {};
							$("#RGBController_settings .RGBController_settingValue").each(function () {
								settings[ $(this).data("variable") ] = $(this).val();
							});
							setSettings(deviceId, settings);
						});

					$("#RGBController_deviceTypeSelect").change(function () {
						var selectedRgbDeviceType = $(this).val();
						if (typeof indexTypes[selectedRgbDeviceType] != "undefined") {
							drawSpecificSettings(deviceId, selectedRgbDeviceType, indexTypes[selectedRgbDeviceType].settings);
						}
					});

					if (typeof indexTypes[rgbDeviceType] != "undefined") {
						drawSpecificSettings(deviceId, rgbDeviceType, indexTypes[rgbDeviceType].settings);
					}

					myInterface.hideModalLoading();
				},
				function (response) {
					showError(response);
					myInterface.hideModalLoading();
				}
			);
		} catch (err) {
			Utils.logError('Error in RGBController.showSettings(): ' + err);
		}
	}

	/**
	 * Draw and manage the settings
	 */
	function drawSpecificSettings (deviceId, rgbDeviceType, settings) {
		var html = '';
		$.each(settings, function (idx, setting) {
			html +=	'<div class="RGBController_setting ui-widget-content ui-corner-all">';
			var value = api.getDeviceStateVariable(deviceId, RGB_CONTROLLER_SID, setting.variable, {dynamic: true});
			if (setting.type == "ZWaveColorDevice") {
				var rgbDevices  = getZWaveRgbDevices();
				html +=	'<span>' + setting.name + '</span>'
					+	'<select class="RGBController_settingValue" data-variable="' + setting.variable  + '">'
					+		'<option value="0">-- Select a device --</option>';
				var i;
				for (i = 0; i < rgbDevices.length; ++i) {
					var rgbDevice = rgbDevices[i];
					html +=	'<option value="' + rgbDevice.id + '"' + (rgbDevice.id.toString() == value ? ' selected' : '') + '>' + rgbDevice.name + ' (#' + rgbDevice.id + ')</option>';
				}
				html +=	'</select>';
			} else if (setting.type == "dimmer") {
				var dimmerDevices  = getDimmerDevices();
				html +=	'<span>' + setting.name + '</span>'
					+	'<select class="RGBController_settingValue" data-variable="' + setting.variable  + '">'
					+		'<option value="0">-- Select a device --</option>';
				var i;
				for (i = 0; i < dimmerDevices.length; ++i) {
					var dimmerDevice = dimmerDevices[i];
					html +=	'<option value="' + dimmerDevice.id + '"' + (dimmerDevice.id.toString() == value ? ' selected' : '') + '>' + dimmerDevice.name + ' (#' + dimmerDevice.id + ')</option>';
				}
				html +=	'</select>';
			} else if (setting.type == "string") {
				html +=	'<span>' + setting.name + '</span>'
					+	'<input type="text" value="' + (typeof value === "string" ? value : '') + '" class="RGBController_settingValue" data-variable="' + setting.variable  + '">';
			}
			html +=	'</div>';
		});
		$("#RGBController_specificSettings").html(html);
	}

	/**
	 * Get RGB device types
	 */
	function getRgbDeviceTypes (deviceId) {
		var dfd = $.Deferred();
		api.performActionOnDevice(deviceId, RGB_CONTROLLER_SID, "GetRGBDeviceTypes", {
			actionArguments: {
				output_format: "json"
			},
			onSuccess: function (response) {
				var jsonResponse = null;
				try {
					jsonResponse = $.parseJSON(response.responseText);
				} catch (err) {
					Utils.logError('[RGBController.getRgbDeviceTypes] Parse JSON error: ' + err);
				}
				if ($.isPlainObject(jsonResponse) && $.isPlainObject(jsonResponse["u:GetRGBDeviceTypesResponse"])) {
					var rgbDeviceTypes = $.parseJSON(jsonResponse["u:GetRGBDeviceTypesResponse"].retRGBDeviceTypes);
					if ($.isArray(rgbDeviceTypes)) {
						Utils.logDebug("[RGBController.getRgbDeviceTypes] OK - rgbDeviceTypes: " + jsonResponse["u:GetRGBDeviceTypesResponse"].retRGBDeviceTypes);
						dfd.resolve(rgbDeviceTypes);
						return;
					}
				}
				Utils.logDebug("[RGBController.getRgbDeviceTypes] KO - response: " + response.responseText);
				dfd.reject(response);
			},
			onFailure: function (response) {
				Utils.logDebug("[RGBController.getRgbDeviceTypes] performActionOnDevice failure");
				dfd.reject(response);
			}
		});
		return dfd.promise();
	}

	/**
	 * Get color channel names
	 */
	function getColorChannelNames (deviceId, options) {
		var dfd = $.Deferred();
		api.performActionOnDevice(deviceId, RGB_CONTROLLER_SID, "GetColorChannelNames", {
			actionArguments: {
				output_format: "json"
			},
			onSuccess: function (response) {
				var jsonResponse = null;
				try {
					jsonResponse = $.parseJSON(response.responseText);
				} catch (err) {
					Utils.logError('[RGBController.getColorChannelNames] Parse JSON error: ' + err);
				}
				if ($.isPlainObject(jsonResponse) && $.isPlainObject(jsonResponse["u:GetColorChannelNamesResponse"])) {
					var channelNames = $.parseJSON(jsonResponse["u:GetColorChannelNamesResponse"].retColorChannelNames);
					if ($.isArray(channelNames)) {
						Utils.logDebug("[RGBController.getColorChannelNames] OK - channelNames: " + channelNames);
						dfd.resolve(channelNames);
						return;
					}
				}
				Utils.logError("[RGBController.getColorChannelNames] KO - response: " + response.responseText);
				dfd.reject(response);
			},
			onFailure: function (response) {
				Utils.logError("[RGBController.getColorChannelNames] performActionOnDevice failure");
				dfd.reject(response);
			}
		});
		return dfd.promise();
	}

	/**
	 * Set RGB Controller status
	 */
	function setStatus (deviceId, status) {
		try {
			Utils.logDebug("[RGBController.setStatus] Set status '" + status + "' for device " + deviceId);
			api.performActionOnDevice(deviceId, RGB_CONTROLLER_SID, "SetTarget", {
				actionArguments: {
					output_format: "json",
					newTargetValue: status
				},
				onSuccess: function (response) {
					Utils.logDebug("[RGBController.setStatus] OK");
				},
				onFailure: function (response) {
					Utils.logDebug("[RGBController.setStatus] KO");
				}
			});
		} catch (err) {
			Utils.logError('Error in RGBController.setStatus: ' + err);
		}
	}

	/**
	 * Get animation program names
	 */
	function getAnimationPrograms (deviceId, options) {
		var dfd = $.Deferred();
		api.performActionOnDevice(deviceId, RGB_CONTROLLER_SID, "GetAnimationPrograms", {
			actionArguments: {
				output_format: "json"
			},
			onSuccess: function (response) {
				var jsonResponse = null;
				try {
					jsonResponse = $.parseJSON(response.responseText);
				} catch (err) {
					Utils.logError('[RGBController.getAnimationPrograms] Parse JSON error: ' + err);
				}
				if ($.isPlainObject(jsonResponse) && $.isPlainObject(jsonResponse["u:GetAnimationProgramsResponse"])) {
					var programs = $.parseJSON(jsonResponse["u:GetAnimationProgramsResponse"].retAnimationPrograms);
					if ($.isPlainObject(programs)) {
						Utils.logDebug("[RGBController.getAnimationPrograms] OK - programs: " + programs);
						dfd.resolve(programs);
						return;
					}
				}
				Utils.logError("[RGBController.getAnimationPrograms] KO - response: " + response.responseText);
				dfd.reject(response);
			},
			onFailure: function (response) {
				Utils.logError("[RGBController.getAnimationPrograms] performActionOnDevice failure");
				dfd.reject(response);
			}
		});
		return dfd.promise();
	}

	/**
	 * Start animation program
	 */
	function startAnimationProgram (deviceId, programName) {
		try {
			Utils.logDebug("[RGBController.startAnimationProgram] Start program '" + programName + "' for device " + deviceId);
			api.performActionOnDevice(deviceId, RGB_CONTROLLER_SID, "StartAnimationProgram", {
				actionArguments: {
					output_format: "json",
					programName: programName
				},
				onSuccess: function (response) {
					Utils.logDebug("[RGBController.startAnimationProgram] OK");
				},
				onFailure: function (response) {
					Utils.logDebug("[RGBController.startAnimationProgram] KO");
				}
			});
		} catch (err) {
			Utils.logError('Error in RGBController.startAnimationProgram: ' + err);
		}
	}

	myModule = {
		uuid: uuid,
		onDeviceStatusChanged: onDeviceStatusChanged,
		showColorWheel: showColorWheel,
		showSettings: showSettings
	};

	// UI5 compatibility
	if (api.version == "UI5") {
		window["RGBController.showColorWheel"] = showColorWheel;
		window["RGBController.showSettings"]   = showSettings;
	}

	return myModule;

})((typeof api !== 'undefined' ? api : null), jQuery);


// *************************************************************************************************************
// Modified version of Farbtastic for Vera UI5 - UI7
// https://github.com/mattfarina/farbtastic
// *************************************************************************************************************

// Farbtastic 2.0.0-alpha.1
(function ($) {

var __debug = false;

$.support.canvas = !! document.createElement("canvas").getContext;
$.support.excanvas = ! $.support.canvas && "G_vmlCanvasManager" in window;
$.support.farbtastic = $.support.canvas || $.support.excanvas;

$.fn.farbtastic = function (options) {
  options = options || {};
  this.each(function(){
    this.farbtastic = this.farbtastic || new $._farbtastic(this, options);
  });
  return this;
};

$.farbtastic = function (container, options) {
  container = $(container).get(0);
  return container.farbtastic || (container.farbtastic = new $._farbtastic(container, options));
};

$._farbtastic = function (container, options) {
  var fb = this;

  /////////////////////////////////////////////////////

  /**
   * Defaults for options
   */
  fb.defaults = {
    width: 300,
    wheelWidth: (options.width || 300) / 10,
    callback: null,
    color: "#808080"
  };

  fb._initialized = false;
  fb.$container = $(container);
  fb.EVENT_CHANGE = "farbtastic.change";
  fb.EVENT_STOP   = "farbtastic.stop";

  /**
   * Event Features
   */
  fb.emitter = $(fb);
  $.each(["on", "off", "trigger"], function(i, name){
    fb[name] = function(){
      this.emitter[name].apply(this.emitter, arguments);
      return this;
    };
  });

  /**
   * Link to the given element(s) or callback.
   */
  fb.linkTo = function (callback) {
    // Unbind previous nodes
    if (typeof fb.callback == 'object') {
      $(fb.callback).unbind('keyup', fb.updateValue);
      //$(fb.callback).off('keyup', fb.updateValue);
    }

    // Reset color
    fb.color = null;

    // Bind callback or elements
    if (typeof callback == 'function') {
      fb.callback = callback;
    }
    else if (typeof callback == 'object' || typeof callback == 'string') {
      fb.callback = $(callback);
      fb.callback.bind('keyup', fb.updateValue);
      //fb.callback.on('keyup', fb.updateValue);
      if (fb.callback[0].value) {
        fb.setColor(fb.callback[0].value);
      }
    }
    return this;
  }
  fb.updateValue = function (event) {
    if (this.value && this.value != fb.color) {
      fb.setColor(this.value);
    }
  }

  /**
   * Change color with HTML syntax #123456
   */
  fb.setColor = function (color, useCallback) {
    useCallback = useCallback !== false;
    var unpack = fb.unpack(color);
    if (fb.color != color && unpack) {
      fb.color = color;
      fb.rgb = unpack;
      fb.hsl = fb.RGBToHSL(fb.rgb);
      fb.updateDisplay(useCallback);
    }
    return this;
  }

  /**
   * Change color with HSL triplet [0..1, 0..1, 0..1]
   */
  fb.setHSL = function (hsl, useCallback) {
    useCallback = useCallback !== false;
    fb.hsl = hsl;
    fb.rgb = fb.HSLToRGB(hsl);
    fb.color = fb.pack(fb.rgb);
    fb.updateDisplay(useCallback);
    return this;
  }

  /////////////////////////////////////////////////////

  /**
   * Initialize the color picker widget.
   */
  fb.initWidget = function () {

    // Insert markup and size accordingly.
    var dim = {
      width: options.width,
      height: options.width
    };
    $(container)
      .html(
        '<div class="farbtastic" style="position: relative">' +
          '<div class="farbtastic-solid"></div>' +
          '<canvas class="farbtastic-mask"></canvas>' +
          '<canvas class="farbtastic-overlay"></canvas>' +
        '</div>'
      )
      .find('*').attr(dim).css(dim).end()
      .find('div>*').css('position', 'absolute');

    // IE Fix: Recreate canvas elements with doc.createElement and excanvas.
    if(! document.createElement("canvas").getContext && !! G_vmlCanvasManager){
      $('canvas', container).each(function () {
        // Fetch info.
        var attr = { 'class': $(this).attr('class'), style: this.getAttribute('style') },
            e = document.createElement('canvas');
        // Replace element.
        $(this).before($(e).attr(attr)).remove();
        // Init with explorerCanvas.
        G_vmlCanvasManager && G_vmlCanvasManager.initElement(e);
        // Set explorerCanvas elements dimensions and absolute positioning.
        $(e).attr(dim).css(dim).css('position', 'absolute')
          .find('*').attr(dim).css(dim);
      });
    }

    // Determine layout
    fb.radius = (options.width - options.wheelWidth) / 2 - 1;
    fb.square = Math.floor((fb.radius - options.wheelWidth / 2) * 0.7) - 1;
    fb.mid = Math.floor(options.width / 2);
    fb.markerSize = options.wheelWidth * 0.3;
    fb.solidFill = $('.farbtastic-solid', container).css({
      width: fb.square * 2 - 1,
      height: fb.square * 2 - 1,
      left: fb.mid - fb.square,
      top: fb.mid - fb.square
    });

    // Set up drawing context.
    fb.cnvMask = $('.farbtastic-mask', container);
    fb.ctxMask = fb.cnvMask[0].getContext('2d');
    fb.cnvOverlay = $('.farbtastic-overlay', container);
    fb.ctxOverlay = fb.cnvOverlay[0].getContext('2d');
    fb.ctxMask.translate(fb.mid, fb.mid);
    fb.ctxOverlay.translate(fb.mid, fb.mid);

    // Draw widget base layers.
    fb.drawCircle();
    fb.drawMask();
  }

  /**
   * Draw the color wheel.
   */
  fb.drawCircle = function () {
    var tm = +(new Date());
    // Draw a hue circle with a bunch of gradient-stroked beziers.
    // Have to use beziers, as gradient-stroked arcs don't work.
    var n = 24,
        r = fb.radius,
        w = options.wheelWidth,
        nudge = 8 / r / n * Math.PI, // Fudge factor for seams.
        m = fb.ctxMask,
        angle1 = 0, color1, d1;
    m.save();
    m.lineWidth = w / r;
    m.scale(r, r);
    // Each segment goes from angle1 to angle2.
    for (var i = 0; i <= n; ++i) {
      var d2 = i / n,
          angle2 = d2 * Math.PI * 2,
          // Endpoints
          x1 = Math.sin(angle1), y1 = -Math.cos(angle1);
          x2 = Math.sin(angle2), y2 = -Math.cos(angle2),
          // Midpoint chosen so that the endpoints are tangent to the circle.
          am = (angle1 + angle2) / 2,
          tan = 1 / Math.cos((angle2 - angle1) / 2),
          xm = Math.sin(am) * tan, ym = -Math.cos(am) * tan,
          // New color
          color2 = fb.pack(fb.HSLToRGB([d2, 1, 0.5]));
      if (i > 0) {
        if ($.support.excanvas){
          // IE's gradient calculations mess up the colors. Correct along the diagonals.
          var corr = (1 + Math.min(Math.abs(Math.tan(angle1)), Math.abs(Math.tan(Math.PI / 2 - angle1)))) / n;
          color1 = fb.pack(fb.HSLToRGB([d1 - 0.15 * corr, 1, 0.5]));
          color2 = fb.pack(fb.HSLToRGB([d2 + 0.15 * corr, 1, 0.5]));
          // Create gradient fill between the endpoints.
          var grad = m.createLinearGradient(x1, y1, x2, y2);
          grad.addColorStop(0, color1);
          grad.addColorStop(1, color2);
          m.fillStyle = grad;
          // Draw quadratic curve segment as a fill.
          var r1 = (r + w / 2) / r, r2 = (r - w / 2) / r; // inner/outer radius.
          m.beginPath();
          m.moveTo(x1 * r1, y1 * r1);
          m.quadraticCurveTo(xm * r1, ym * r1, x2 * r1, y2 * r1);
          m.lineTo(x2 * r2, y2 * r2);
          m.quadraticCurveTo(xm * r2, ym * r2, x1 * r2, y1 * r2);
          m.fill();
        }
        else {
          // Create gradient fill between the endpoints.
          var grad = m.createLinearGradient(x1, y1, x2, y2);
          grad.addColorStop(0, color1);
          grad.addColorStop(1, color2);
          m.strokeStyle = grad;
          // Draw quadratic curve segment.
          m.beginPath();
          m.moveTo(x1, y1);
          m.quadraticCurveTo(xm, ym, x2, y2);
          m.stroke();
        }
      }
      // Prevent seams where curves join.
      angle1 = angle2 - nudge; color1 = color2; d1 = d2;
    }
    m.restore();
    __debug && $('body').append('<div>drawCircle '+ (+(new Date()) - tm) +'ms');
  };

  /**
   * Draw the saturation/luminance mask.
   */
  fb.drawMask = function () {
    var tm = +(new Date());

    // Iterate over sat/lum space and calculate appropriate mask pixel values.
    var size = fb.square * 2, sq = fb.square;
    function calculateMask(sizex, sizey, outputPixel) {
      var isx = 1 / sizex, isy = 1 / sizey;
      for (var y = 0; y <= sizey; ++y) {
        var l = 1 - y * isy;
        for (var x = 0; x <= sizex; ++x) {
          var s = 1 - x * isx;
          // From sat/lum to alpha and color (grayscale)
          var a = 1 - 2 * Math.min(l * s, (1 - l) * s);
          var c = (a > 0) ? ((2 * l - 1 + a) * .5 / a) : 0;
          outputPixel(x, y, c, a);
        }
      }
    }

    // Method #1: direct pixel access (new Canvas).
    if (fb.ctxMask.getImageData) {
      // Create half-resolution buffer.
      var sz = Math.floor(size / 2);
      var buffer = document.createElement('canvas');
      buffer.width = buffer.height = sz + 1;
      var ctx = buffer.getContext('2d');
      var frame = ctx.getImageData(0, 0, sz + 1, sz + 1);

      var i = 0;
      calculateMask(sz, sz, function (x, y, c, a) {
        frame.data[i++] = frame.data[i++] = frame.data[i++] = c * 255;
        frame.data[i++] = a * 255;
      });

      ctx.putImageData(frame, 0, 0);
      fb.ctxMask.drawImage(buffer, 0, 0, sz + 1, sz + 1, -sq, -sq, sq * 2, sq * 2);
    }
    // Method #2: drawing commands (old Canvas).
    else if (! $.support.excanvas) {
      // Render directly at half-resolution
      var sz = Math.floor(size / 2);
      calculateMask(sz, sz, function (x, y, c, a) {
        c = Math.round(c * 255);
        fb.ctxMask.fillStyle = 'rgba(' + c + ', ' + c + ', ' + c + ', ' + a +')';
        fb.ctxMask.fillRect(x * 2 - sq - 1, y * 2 - sq - 1, 2, 2);
      });
    }
    // Method #3: vertical DXImageTransform gradient strips (IE).
    else {
      var cache_last, cache, w = 6; // Each strip is 6 pixels wide.
      var sizex = Math.floor(size / w);
      // 6 vertical pieces of gradient per strip.
      calculateMask(sizex, 6, function (x, y, c, a) {
        if (x == 0) {
          cache_last = cache;
          cache = [];
        }
        c = Math.round(c * 255);
        a = Math.round(a * 255);
        // We can only start outputting gradients once we have two rows of pixels.
        if (y > 0) {
          var c_last = cache_last[x][0],
              a_last = cache_last[x][1],
              color1 = fb.packDX(c_last, a_last),
              color2 = fb.packDX(c, a),
              y1 = Math.round(fb.mid + ((y - 1) * .333 - 1) * sq),
              y2 = Math.round(fb.mid + (y * .333 - 1) * sq);
          $('<div>').css({
            position: 'absolute',
            filter: "progid:DXImageTransform.Microsoft.Gradient(StartColorStr="+ color1 +", EndColorStr="+ color2 +", GradientType=0)",
            top: y1,
            height: y2 - y1,
            // Avoid right-edge sticking out.
            left: fb.mid + (x * w - sq - 1),
            width: w - (x == sizex ? Math.round(w / 2) : 0)
          }).appendTo(fb.cnvMask);
        }
        cache.push([c, a]);
      });
    }
    __debug && $('body').append('<div>drawMask '+ (+(new Date()) - tm) +'ms');
  }

  /**
   * Draw the selection markers.
   */
  fb.drawMarkers = function () {
    // Determine marker dimensions
    var sz = options.width, lw = Math.ceil(fb.markerSize / 4), r = fb.markerSize - lw + 1;
    var angle = fb.hsl[0] * 6.28,
        x1 =  Math.sin(angle) * fb.radius,
        y1 = -Math.cos(angle) * fb.radius,
        x2 = 2 * fb.square * (.5 - fb.hsl[1]),
        y2 = 2 * fb.square * (.5 - fb.hsl[2]),
        c1 = fb.invert ? '#fff' : '#000',
        c2 = fb.invert ? '#000' : '#fff';
    var circles = [
      { x: x1, y: y1, r: r,             c: '#000', lw: lw + 1 },
      { x: x1, y: y1, r: fb.markerSize, c: '#fff', lw: lw },
      { x: x2, y: y2, r: r,             c: c2,     lw: lw + 1 },
      { x: x2, y: y2, r: fb.markerSize, c: c1,     lw: lw },
    ];

    // Update the overlay canvas.
    fb.ctxOverlay.clearRect(-fb.mid, -fb.mid, sz, sz);
    for (var i = 0; i < circles.length; i++) {
      var c = circles[i];
      fb.ctxOverlay.lineWidth = c.lw;
      fb.ctxOverlay.strokeStyle = c.c;
      fb.ctxOverlay.beginPath();
      fb.ctxOverlay.arc(c.x, c.y, c.r, 0, Math.PI * 2, true);
      fb.ctxOverlay.stroke();
    }
  }

  /**
   * Update the markers and styles
   */
  fb.updateDisplay = function (useCallback) {
    useCallback = useCallback !== false;
    // Determine whether labels/markers should invert.
    fb.invert = (fb.rgb[0] * 0.3 + fb.rgb[1] * .59 + fb.rgb[2] * .11) <= 0.6;

    // Update the solid background fill.
    fb.solidFill.css('backgroundColor', fb.pack(fb.HSLToRGB([fb.hsl[0], 1, 0.5])));

    // Draw markers
    fb.drawMarkers();

    // Linked elements or callback
    if (typeof fb.callback == 'object') {
      // Set background/foreground color
      $(fb.callback).css({
        backgroundColor: fb.color,
        color: fb.invert ? '#fff' : '#000'
      });

      // Change linked value
      $(fb.callback).each(function() {
        if ((typeof this.value == 'string') && this.value != fb.color) {
          this.value = fb.color;
        }
      }).change();
    }
    else if (typeof fb.callback == 'function' && useCallback) {
      fb.callback.call(fb, fb.color);
    }
    if(fb._initialized){
      fb.$container.trigger(fb.EVENT_CHANGE, fb.color);
      fb.trigger(fb.EVENT_CHANGE, fb.color);
    }
  }

  /**
   * Helper for returning coordinates relative to the center.
   */
  fb.widgetCoords = function (event) {
	if (typeof api === 'undefined') {
		// UI5
		return {
			x: event.pageX - fb.offset.left - fb.mid,
			y: event.pageY - fb.offset.top - fb.mid + $("body").scrollTop() // Firefox bug
		};
	} else {
		// UI7 and ALTUI
		return {
			x: event.pageX - fb.offset.left - fb.mid,
			y: event.pageY - fb.offset.top - fb.mid
		};
	}
  }

  /**
   * Mousedown handler
   */
  fb.mousedown = function (event) {
    // Capture mouse
    if (!$._farbtastic.dragging) {
      $(document).bind('mousemove', fb.mousemove).bind('mouseup', fb.mouseup);
      //$(document).on('mousemove', fb.mousemove).on('mouseup', fb.mouseup);
      $._farbtastic.dragging = true;
    }

    // Update the stored offset for the widget.
    fb.offset = $(container).offset();

    // Check which area is being dragged
    var pos = fb.widgetCoords(event);
    fb.circleDrag = Math.max(Math.abs(pos.x), Math.abs(pos.y)) > (fb.square + 2);

    // Process
    fb.mousemove(event);
    return false;
  }

  /**
   * Mousemove handler
   */
  fb.mousemove = function (event) {
    // Get coordinates relative to color picker center
    var pos = fb.widgetCoords(event);

    // Set new HSL parameters
    if (fb.circleDrag) {
      var hue = Math.atan2(pos.x, -pos.y) / 6.28;
      fb.setHSL([(hue + 1) % 1, fb.hsl[1], fb.hsl[2]]);
    }
    else {
      var sat = Math.max(0, Math.min(1, -(pos.x / fb.square / 2) + .5));
      var lum = Math.max(0, Math.min(1, -(pos.y / fb.square / 2) + .5));
      fb.setHSL([fb.hsl[0], sat, lum]);
    }
    return false;
  }

  /**
   * Mouseup handler
   */
  fb.mouseup = function () {
    // Uncapture mouse
    $(document).unbind('mousemove', fb.mousemove);
    $(document).unbind('mouseup', fb.mouseup);
    //$(document).off('mousemove', fb.mousemove);
    //$(document).off('mouseup', fb.mouseup);
    $._farbtastic.dragging = false;
    // vosmont : event 'stop'
    if(fb._initialized){
      fb.$container.trigger(fb.EVENT_STOP, [ fb.color ]);
      fb.trigger(fb.EVENT_STOP, [ fb.color ]);
    }
  }

  /* Various color utility functions */
  fb.dec2hex = function (x) {
    return (x < 16 ? '0' : '') + x.toString(16);
  }

  fb.packDX = function (c, a) {
    return '#' + fb.dec2hex(a) + fb.dec2hex(c) + fb.dec2hex(c) + fb.dec2hex(c);
  };

  fb.pack = function (rgb) {
    var r = Math.round(rgb[0] * 255);
    var g = Math.round(rgb[1] * 255);
    var b = Math.round(rgb[2] * 255);
    return '#' + fb.dec2hex(r) + fb.dec2hex(g) + fb.dec2hex(b);
  };

  fb.unpack = function (color) {
    if (color.length == 7) {
      function x(i) {
        return parseInt(color.substring(i, i + 2), 16) / 255;
      }
      return [ x(1), x(3), x(5) ];
    }
    else if (color.length == 4) {
      function x(i) {
        return parseInt(color.substring(i, i + 1), 16) / 15;
      }
      return [ x(1), x(2), x(3) ];
    }
  };

  fb.HSLToRGB = function (hsl) {
    var m1, m2, r, g, b;
    var h = hsl[0], s = hsl[1], l = hsl[2];
    m2 = (l <= 0.5) ? l * (s + 1) : l + s - l * s;
    m1 = l * 2 - m2;
    return [
      this.hueToRGB(m1, m2, h + 0.33333),
      this.hueToRGB(m1, m2, h),
      this.hueToRGB(m1, m2, h - 0.33333)
    ];
  };

  fb.hueToRGB = function (m1, m2, h) {
    h = (h + 1) % 1;
    if (h * 6 < 1) return m1 + (m2 - m1) * h * 6;
    if (h * 2 < 1) return m2;
    if (h * 3 < 2) return m1 + (m2 - m1) * (0.66666 - h) * 6;
    return m1;
  };

  fb.RGBToHSL = function (rgb) {
    var r = rgb[0], g = rgb[1], b = rgb[2],
        min = Math.min(r, g, b),
        max = Math.max(r, g, b),
        delta = max - min,
        h = 0,
        s = 0,
        l = (min + max) / 2;
    if (l > 0 && l < 1) {
      s = delta / (l < 0.5 ? (2 * l) : (2 - 2 * l));
    }
    if (delta > 0) {
      if (max == r && max != g) h += (g - b) / delta;
      if (max == g && max != b) h += (2 + (b - r) / delta);
      if (max == b && max != r) h += (4 + (r - g) / delta);
      h /= 6;
    }
    return [h, s, l];
  };

  // Parse options.
  if(["string", "function"].indexOf($.type(options)) >= 0){
    options = {callback: options};
  }
  options = $.extend(fb.defaults, options);

  // Initialize.
  fb.initWidget();

  // Install mousedown handler (the others are set on the document on-demand)
  $('canvas.farbtastic-overlay', container).mousedown(fb.mousedown);

  // Set linked elements/callback
  if (options.callback) {
    fb.linkTo(options.callback);
  }
  // Set to gray.
  if (!fb.color){
    fb.setColor(options.color, false);
  }

  fb._initialized = true;
}

})(jQuery);
