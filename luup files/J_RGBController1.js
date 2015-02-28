//@ sourceURL=J_RGBController1.js

var RGBController = (function (api, $) {

	var uuid = 'ToBeDefined';
	var RGBCONTROLLER_SID = 'urn:upnp-org:serviceId:RGBController1';
	var myModule = {};

	// Inject plugin specific CSS rules
	var pluginStyle = $("<style>");
	if ($.fn.jquery == "1.5") {
		pluginStyle.attr("type", "text/css");
	} else {
		pluginStyle.prop("type", "text/css");
	}
	pluginStyle.html("\
			#RGBController_colorWheel { width: 400px; height: 400px; margin: 20px auto; }\
			#RGBController_colorpicker { display: inline-block; margin-right: 10px; }\
			#RGBController_sliders { display: inline-block; margin-left: 50px; } \
			#RGBController_sliders .ui-slider { display: inline-block; height: 180px; width: 19px; margin-left: 10px; }\
			#RGBController_sliders .ui-slider-vertical { border-radius: 25px; }\
			#RGBController_sliders .ui-slider-handle { width: 25px; }\
			#RGBController_red .ui-slider-range, #RGBController_red .ui-slider-handle { background-color: #ef2929 !important; }\
			#RGBController_green .ui-slider-range, #RGBController_green .ui-slider-handle { background-color: #8ae234 !important; }\
			#RGBController_blue .ui-slider-range, #RGBController_blue .ui-slider-handle { background-color: #729fcf !important; }\
			#RGBController_white .ui-slider-range, #RGBController_white .ui-slider-handle { background-color: #FBE616 !important; }\
			#RGBController_swatch { height: 26px; border-radius: 25px; background-image: none; margin-top: 30px; border: none; background-color: black; }\
			#RGBController_innerswatch { font:bold 24px arial; text-align:center; color:white; }\
			#RGBController_program { margin-top: 10px; border-radius: 25px; padding: 0px 25px; text-align:center; }\
			#RGBController_programs { width: 60%; }\
		")
		.appendTo("head");

	// UI5 compatibility with UI7 JavaScript API
	if (api === null) {
		api = {
			getListOfDevices : function () {
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
				var query = "id=lu_action&output_format=json&DeviceNum=" + deviceId + "&serviceId=" + service + "&action=" + action;
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
			}
		};
	}
	if (typeof window.Utils === 'undefined') {
		window.Utils = {
			logError: function (message) {
				console.error(message);
			},
			logDebug: function (message) {
				//console.info(message);
			}
		};
	}

	/**
	 * Show color wheel panel
	 */
	function showColorWheel (deviceId) {
		try {
			Utils.logDebug("[RGBController.showColorWheel] Show color wheel for device " + deviceId);
			api.setCpanelContent(
						'<div id="RGBController_colorWheel">'
					+		"The plugin is not configured. Please go in tab 'Settings'"
					+	'</div>'
			);

			var RGBDeviceId = parseInt(api.getDeviceStateVariable(deviceId, RGBCONTROLLER_SID, "DeviceId", {dynamic: false}), 10);
			if (RGBDeviceId !== 0) {
				var color = api.getDeviceStateVariable(deviceId, RGBCONTROLLER_SID, "Color", {dynamic: true});
				color = "#" + color.replace("#", "");
				Utils.logDebug("[RGBController.showColorWheel] RGBDeviceId:" + RGBDeviceId + " Color:" + color);
				drawAndManageColorWheel(deviceId, color);
			}
		} catch (err) {
			Utils.logError('Error in RGBController.showColorWheel: ' + err);
		}
	}

	/**
	 * Draw and manage the color wheel
	 */
	function drawAndManageColorWheel (deviceId, color) {
		var lastSendDate = +new Date();
		var sendTimer = 0;
		var currentColor = color;
		var rgbColor = color.substring(0, 7);
		var whiteColor = color.substring(7, 9);

		Utils.logDebug("[RGBController.drawAndManageColorWheel] Draw for device " + deviceId + " with initial color " + color);

		$("#RGBController_colorWheel").html(
				'<div id="RGBController_colorpicker"></div>'
			+	'<div id="RGBController_sliders">'
			+		'<div id="RGBController_red"></div>'
			+		'<div id="RGBController_green"></div>'
			+		'<div id="RGBController_blue"></div>'
			+		'<div id="RGBController_white"></div>'
			+	'</div>'
			+	'<div id="RGBController_swatch" class="ui-widget-content ui-corner-all">'
			+		'<div id="RGBController_innerswatch"></div>'
			+	'</div>'
			+	'<div id="RGBController_program" class="ui-widget-content ui-corner-all">'
			+		'<select id="RGBController_programs" class="ui-widget-content">'
			+			'<option value="0" selected="selected">&lt;Animation&gt;</option>'
			+			'<option value="6">Fireplace</option>'
			+			'<option value="7">Storm</option>'
			+			'<option value="8">Rainbow</option>'
			+			'<option value="9">Aurora</option>'
			+			'<option value="10">LPD</option>'
			+		'</select>'
			+		'<button id="RGBController_program_start" class="ui-widget-content">Start</button>'
			+		'<button id="RGBController_program_stop" class="ui-widget-content">Stop</button>'
			+	'</div>'
		);

		var colorPicker = $.farbtastic("#RGBController_colorpicker", { callback:function() { }, width: 180 });

		// Color sliders
		$("#RGBController_sliders div").slider({
			orientation: "vertical",
			min: 0,
			max: 255,
			range: "min",
			slide: onSliderUpdate
		});

		// Fibaro animation programs
		$("#RGBController_program_start")
			.click(function (event) {
				var programId = $("#RGBController_programs").val();
				if (programId > 0) {
					startAnimationProgram(deviceId, programId);
				}
			});
		$("#RGBController_program_stop")
			.click(function (event) {
				startAnimationProgram(deviceId, 0);
			});

		// Init
		updateSwatch(color);
		updateSliders(color);
		colorPicker.setColor(rgbColor);
		colorPicker.linkTo(pickerUpdate);

		function onSliderUpdate () {
			var red = $("#RGBController_red").slider("value");
			var green = $("#RGBController_green").slider("value");
			var blue = $("#RGBController_blue").slider("value");
			var white = $("#RGBController_white").slider("value");
			var color = "#" + hexFromRGBW(red, green, blue, white);
			var newRgbColor = color.substring(0, 7);
			whiteColor = color.substring(7, 9);
			Utils.logDebug("[RGBController.onSliderUpdate] RGB: " + newRgbColor + " - White: " + whiteColor);
			if (newRgbColor != rgbColor) {
				rgbColor = newRgbColor;
				colorPicker.setColor(rgbColor);
			} else {
				updateSwatch(color);
				setColor(color);
			}
		}
		function updateSliders (color) {
		Utils.logDebug("[RGBController.updateSliders]");
			var red = parseInt(color.substring(1, 3), 16);
			var green = parseInt(color.substring(3, 5), 16);
			var blue = parseInt(color.substring(5, 7), 16);
			$("#RGBController_red").slider("value", red);
			$("#RGBController_green").slider("value", green);
			$("#RGBController_blue").slider("value", blue);
			if (color.length == 9) {
				var white = parseInt(color.substring(7, 9), 16);
				$("#RGBController_white").slider("value", white);
			}
		}
		function updateSwatch (color) {
			if (color.length == 7) {
				color += whiteColor;
			}
			color = color.toUpperCase();
			//$("#RGBController_swatch").css("background-color", color.substring(0, 7) + " !important");
			$("#RGBController_swatch").attr('style', 'background-color: ' + color.substring(0, 7) + ' !important');
			if (colorPicker.hsl[2] > 0.5) {
				$("#RGBController_innerswatch").css("color", "#000000");    
			} else {
				$("#RGBController_innerswatch").css("color", "#ffffff");  
			}
			$("#RGBController_innerswatch").html(color);
		}
		function hexFromRGBW (r, g, b, w) {
			var hex = [r.toString(16), g.toString(16), b.toString(16), w.toString(16)];
			$.each(hex, function (nr, val) {
				if (val.length === 1) {
					hex[nr] = "0" + val;
				}
			});
			return hex.join("").toUpperCase();
		}
		function pickerUpdate (pickerRgbColor) {
			updateSwatch(pickerRgbColor);
			updateSliders(pickerRgbColor);
			setColor(pickerRgbColor);
		}
		function setColor (color) {
			if (color.length == 7) {
				color += whiteColor;
			}
			currentColor = color;
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
			Utils.logDebug("[RGBController.sendColor] Set color to " + currentColor + " for device " + deviceId);
			api.performActionOnDevice(deviceId, RGBCONTROLLER_SID, "SetColorTarget", {
				actionArguments: {
					newColorTargetValue: currentColor.replace("#", "")
				},
				onSuccess: function () {
					Utils.logDebug("[RGBController.sendColor] OK");
				},
				onFailure: function () {
				Utils.logDebug("[RGBController.sendColor] KO");
				}
			});
		}
	}

	/**
	 * Search Fibaro FGRGB-101 devices
	 */
	function getRGBDevices () {
		var RGBDevices = [];
		var devices = api.getListOfDevices();
		var i, j;
		for (i = 0; i < devices.length; i++) {
			var device = devices[i];
			if ((device.device_type == DEVICETYPE_DIMMABLE_LIGHT) && (device.altid  == "e1")) {
				for (j = 0; j < devices.length; j++) {
					var parentDevice = devices[j];
					if ((parentDevice.id == device.id_parent) && (parentDevice.device_type == DEVICETYPE_DIMMABLE_LIGHT) && (parentDevice.manufacturer == "Fibar")) {
						RGBDevices.push(parentDevice);
					}
				}
			}
		}
		return RGBDevices;
	}

	/**
	 * Set RGB controller settings
	 */
	function setSettings (deviceId, RGBDeviceId) {
		Utils.logDebug("[RGBController.setSettings] Save RGBDeviceId " + RGBDeviceId + " for device " + deviceId);
		api.setDeviceStateVariablePersistent(deviceId, RGBCONTROLLER_SID, "DeviceId", RGBDeviceId);
		$("#RGBController_message").html("Settings have been modified. Please save your changes (UI5).");
	}

	/**
	 * Show setting panel
	 */
	function showSettings (deviceId) {
		try {
			Utils.logDebug("[RGBController.showSettings] Show settings for device " + deviceId);
			//var RGBDeviceId = parseInt(get_device_state (deviceId, RGBCONTROLLER_SID, "DeviceId", 0));
			var RGBDeviceId = parseInt(api.getDeviceStateVariable(deviceId, RGBCONTROLLER_SID, "DeviceId", {dynamic: false}), 10);

			var html =	'<div id="RGBController_settings">'
					+		'<p>To use this RGB controller, you must add the main Fibaro Controller.</p>'
					+		'<select id="RGBController_deviceSelect">'
					+			'<option value="0">-- Select a device --</option>';
			var RGBDevices = getRGBDevices();
			var i;
			for (i = 0; i < RGBDevices.length; ++i) {
				var RGBDevice = RGBDevices[i];
				html +=			'<option value="' + RGBDevice.id + '"' + (RGBDevice.id == RGBDeviceId ? ' selected' : '') + '>' + RGBDevice.name + ' (#' + RGBDevice.id + ')</option>';
			}
			html +=			'</select>'
					+		'<button>Select</button>'
					+		'<div id="RGBController_message"></div>'
					+	'</div>';
			api.setCpanelContent(html);

			$("#RGBController_settings button")
				.click(function () {
					var RGBDeviceId = $("#RGBController_deviceSelect").val();
					setSettings(deviceId, RGBDeviceId);
				});
		} catch (err) {
			Utils.logError('Error in RGBController.showSettings(): ' + err);
		}
	}

	/**
	 * Start Fibaro animation program
	 */
	function startAnimationProgram (deviceId, programId) {
		try {
			Utils.logDebug("[RGBController.startAnimationProgram] Start program " + programId + " for device " + deviceId);
			api.performActionOnDevice(deviceId, RGBCONTROLLER_SID, "StartAnimationProgram", {
				actionArguments: {
					programId: programId
				},
				onSuccess: function () {
					Utils.logDebug("[RGBController.startAnimationProgram] OK");
				},
				onFailure: function () {
					Utils.logDebug("[RGBController.startAnimationProgram] KO");
				}
			});
		} catch (err) {
			Utils.logError('Error in RGBController.startAnimationProgram: ' + err);
		}
	}

	myModule = {
		uuid: uuid,
		showColorWheel: showColorWheel,
		showSettings: showSettings
	};
	return myModule;

})((typeof api !== 'undefined' ? api : null), jQuery);

// UI5 compatibility
var RGBController_showColorWheel = RGBController.showColorWheel;
var RGBController_showSettings   = RGBController.showSettings;


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

  /**
   * Event Fetures
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
  fb.setColor = function (color) {
    var unpack = fb.unpack(color);
    if (fb.color != color && unpack) {
      fb.color = color;
      fb.rgb = unpack;
      fb.hsl = fb.RGBToHSL(fb.rgb);
      fb.updateDisplay();
    }
    return this;
  }

  /**
   * Change color with HSL triplet [0..1, 0..1, 0..1]
   */
  fb.setHSL = function (hsl) {
    fb.hsl = hsl;
    fb.rgb = fb.HSLToRGB(hsl);
    fb.color = fb.pack(fb.rgb);
    fb.updateDisplay();
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
  fb.updateDisplay = function () {
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
    else if (typeof fb.callback == 'function') {
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
    return {
      x: event.pageX - fb.offset.left - fb.mid,
      y: event.pageY - fb.offset.top - fb.mid - $(window).scrollTop()
      //y: event.pageY - fb.offset.top - fb.mid + $("#RGBController_colorWheel").position().top
    };
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
    fb.setColor(options.color);
  }

  fb._initialized = true;
}

})(jQuery);
