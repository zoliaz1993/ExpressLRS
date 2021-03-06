--[[
        ChgId

      DanielGeA

  License https://www.gnu.org/licenses/gpl-3.0.en.html

  Ported from erskyTx. Thanks to MikeB

  Lua script for radios X7, X9, X-lite and Horus with openTx 2.2 or higher

  Change Frsky sensor Id

]] --
local commitSha = 'xxxxxx'
local version = 'v0.1'
local refresh = 0
local lcdChange = true
local updateValues = false
local readIdState = 0
local sendIdState = 0
local timestamp = 0
local bindmode = 0
local WebupdateReq = 0
local WebupdateReqWaitResp = false

local gotFirstResp = false

local binding = false

local AirRate = {
    selected = 1,
    list = {'------', 'AUTO', '500 Hz', '250 Hz', '200 Hz', '150 Hz', '100 Hz', '50 Hz', '25 Hz', '4 Hz'},
    dataId = {0xFF, 0xFE, 0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07},
    elements = 10
}
local TLMinterval = {
    selected = 9,
    list = {
        'Off', '1:128', '1:64', '1:32', '1:16', '1:8', '1:4', '1:2', '------'
    },
    dataId = {0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0xFF},
    elements = 9
}
local MaxPower = {
    selected = 1,
    list = {
        '------', '10 mW', '25 mW', '50 mW', '100 mW', '250 mW', '500 mW', '1000 mW', '2000 mW',
    },
    dataId = {0xFF, 0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07},
    elements = 9
}
local RFfreq = {
    selected = 7,
    list = {'915 AU', '915 FCC', '868 EU', '433 AU', '433 EU', '2.4G ISM', '------'},
    dataId = {0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0xFF},
    elements = 7
}

local selection = {
    selected = 1,
    state = false,
    list = {'AirRate', 'TLMinterval', 'MaxPower', 'RFfreq', "Bind", "WebUpdate"},
    elements = 6
}

local shaLUT = {'0', '1', '2', '3', '4', '5', '6', '7', '8', '9', 'a', 'b', 'c', 'd', 'e', 'f'}

-- returns flags to pass to lcd.drawText for inverted and flashing text
local function getFlags(element)
    if selection.selected ~= element then return 0 end
    if selection.selected == element and selection.state == false then
        return 0 + INVERS
    end
    -- this element is currently selected
    return 0 + INVERS + BLINK
end

local function increase(data)
    if data.selected > 1 then
        data.selected = data.selected - 1
        if data.selected == 4 then -- skip RF Mode which is defined at compilation
            data.selected = 3
        end
        --playTone(2000, 50, 0)
    end
    -- if data.selected > data.elements then data.selected = 1 end
end

local function decrease(data)
    if data.selected < data.elements then
        data.selected = data.selected + 1
        if data.selected == 4 then -- skip RF Mode which is defined at compilation
            data.selected = 5
        end
        --playTone(2000, 50, 0)
    end
    -- if data.selected < 1 then data.selected = data.elements end
end

--[[

It's unclear how the telemetry push/pop system works. We don't always seem to get
a response to a single push event. Can multiple responses be stacked up? Do they timeout?

If there are multiple repsonses we typically want the newest one, so this method
will keep reading until it gets a nil response, discarding the older data. A maximum number
of reads is used to defend against the possibility of this function running for an extended
period.

]]--

local function processResp()
    local tries=0
    local MAX_TRIES=5

    while tries<MAX_TRIES
    do
        local command, data = crossfireTelemetryPop()
	if (data == nil) then
	    return
	else
            if (command == 0x2D) and (data[1] == 0xEA) and (data[2] == 0xEE) then
				if(data[3] == 0xFF) then
					if(data[4] ==  0x01) then -- bind mode active
						bindmode = 1
					else
						bindmode = 0
					end
				elseif(data[3] == 0xFE) then
						WebupdateReq = data[4]
						WebupdateReqWaitResp = false
						if (WebupdateReq == 0) and (selection.selected == 6) then
							selection.state = false
							selection.selected = 1; 
						end
						
                elseif(data[3] == 0xF0) then -- First half of commit sha
                    commitSha = shaLUT[data[4]+1] .. shaLUT[data[5]+1] .. shaLUT[data[6]+1] .. string.sub(commitSha, 4, 6)
                elseif(data[3] == 0xF1) then -- Second half of commit sha
                    commitSha = string.sub(commitSha, 1, 3) .. shaLUT[data[4]+1] .. shaLUT[data[5]+1] .. shaLUT[data[6]+1]
                else	
					AirRate.selected = data[3]
					TLMinterval.selected = data[4]
					MaxPower.selected = data[5]
					RFfreq.selected = data[6]
				end
				if (gotFirstResp == false) then
					gotFirstResp = true -- detect when first contact is made with TX module 
				end
            end
        end
	tries = tries+1
    end
end

local function refreshHorus()
    lcd.clear()
    lcd.drawText(1, 1, 'ExpressLRS ' .. commitSha, INVERS)
    lcd.drawText(1, 25, 'Pkt. Rate', 0)
    lcd.drawText(1, 45, 'TLM Ratio', 0)
    lcd.drawText(1, 65, 'Set Power', 0)
    lcd.drawText(1, 85, 'RF Freq', 0)

    lcd.drawText(100, 25, AirRate.list[AirRate.selected], getFlags(1))
    lcd.drawText(100, 45, TLMinterval.list[TLMinterval.selected], getFlags(2))
    lcd.drawText(100, 65, MaxPower.list[MaxPower.selected], getFlags(3))
    lcd.drawText(100, 85, RFfreq.list[RFfreq.selected], getFlags(4))

    lcd.drawText(20, 110, '[Bind]', getFlags(5) + SMLSIZE)
    lcd.drawText(60, 110, '[Wifi Update]', getFlags(6) + SMLSIZE)

    if selection.selected == 5 then
        if selection.state == true then
            lcd.drawText(30, 110, 'Press [ENTER] to stop', MEDSIZE)
			if (bindmode == 0) then
				crossfireTelemetryPush(0x2D, {0xEE, 0xEA, 0xFF, 0x01})
			end
        end
		if (selection.state == false) and (bindmode == 1) then
			crossfireTelemetryPush(0x2D, {0xEE, 0xEA, 0xFF, 0x00})
			bindmode = 0
		end
    end
	
	if selection.selected == 6 then
        if (selection.state == true) and (WebupdateReq == 0) and (WebupdateReqWaitResp == false) then
			crossfireTelemetryPush(0x2D, {0xEE, 0xEA, 0xFE, 0x01})
			WebupdateReqWaitResp = true
        end
		if (selection.state == false) and (WebupdateReq == 1) and (WebupdateReqWaitResp == false) then
			crossfireTelemetryPush(0x2D, {0xEE, 0xEA, 0xFE, 0x00})
			WebupdateReqWaitResp = true
		end
    end
	if (WebupdateReq == 1) then
		lcd.drawText(3, 110, 'Wifi Update, Upload File', MEDSIZE)
	end

    lcdChange = false

end

local function refreshTaranis()
    lcd.clear()
    lcd.drawScreenTitle('ExpressLRS ' .. commitSha, 1, 1)
    lcd.drawText(1, 11, 'Pkt. Rate', 0)
    lcd.drawText(1, 21, 'TLM Ratio', 0)
    lcd.drawText(1, 31, 'Set Power', 0)
    lcd.drawText(1, 41, 'RF Freq', 0)

    lcd.drawText(60, 11, AirRate.list[AirRate.selected], getFlags(1))
    lcd.drawText(60, 21, TLMinterval.list[TLMinterval.selected], getFlags(2))
    lcd.drawText(60, 31, MaxPower.list[MaxPower.selected], getFlags(3))
    lcd.drawText(60, 41, RFfreq.list[RFfreq.selected], getFlags(4))

    lcd.drawText(18, 54, '[Bind]', getFlags(5) + SMLSIZE)
    lcd.drawText(55, 54, '[Wifi Update]', getFlags(6) + SMLSIZE)

    if selection.selected == 5 then
        if selection.state == true then
            lcd.drawText(7, 53, 'Press [ENTER] to stop', MEDSIZE)
			if (bindmode == 0) then
				crossfireTelemetryPush(0x2D, {0xEE, 0xEA, 0xFF, 0x01})
			end
        end
		if (selection.state == false) and (bindmode == 1) then
			crossfireTelemetryPush(0x2D, {0xEE, 0xEA, 0xFF, 0x00})
			bindmode = 0
		end
    end
	
	if selection.selected == 6 then
        if (selection.state == true) and (WebupdateReq == 0) and (WebupdateReqWaitResp == false) then
			crossfireTelemetryPush(0x2D, {0xEE, 0xEA, 0xFE, 0x01})
			WebupdateReqWaitResp = true

        end
		if (selection.state == false) and (WebupdateReq == 1) and (WebupdateReqWaitResp == false) then
			crossfireTelemetryPush(0x2D, {0xEE, 0xEA, 0xFE, 0x00})
			WebupdateReqWaitResp = true
		end
    end
	if (WebupdateReq == 1) then
		lcd.drawText(3, 53, 'Wifi Update, Upload File', MEDSIZE)
	end

    lcdChange = false

end

-- redraw the screen
local function refreshLCD()

    if LCD_W == 480 then
        refreshHorus()
    else
        refreshTaranis()
    end

end

local function init_func()
    -- first push so that we get the current values. Didn't seem to work.
    crossfireTelemetryPush(0x2D, {0xEE, 0xEA, 0x00, 0x00})
	--crossfireTelemetryPush(0x2D, {0xEE, 0xEA, 0x00, 0x00})
	--crossfireTelemetryPush(0x2D, {0xEE, 0xEA, 0x00, 0x00})
    processResp()
	--if LCD_W == 480 then
    --    refreshHorus()
   -- else
   --     refreshTaranis()
  --  end
end

local function bg_func(event)
    --if refresh < 25 then 
        --refresh = refresh + 1 
    --end
end
--[[
  Called at (unspecified) intervals when the script is running and the screen is visible

  Handles key presses and sends state changes to the tx module.

  Basic strategy:
    read any outstanding telemetry data
    process the event, sending a telemetryPush if necessary
    if there was no push due to events, send the void push to ensure current values are sent for next iteration
    redraw the display

]]--
local function run_func(event)

    local pushed = false
	
	processResp() -- first check if we have data from the module
	
	if gotFirstResp == false then
		crossfireTelemetryPush(0x2D, {0xEE, 0xEA, 0x00, 0x00}) -- ping until we get a resp
	end

    -- now process key events
    if event == EVT_ROT_LEFT or 
       event == EVT_PLUS_BREAK or 
       event == EVT_DOWN_BREAK then
        if selection.state == false then
            decrease(selection)
			crossfireTelemetryPush(0x2D, {0xEE, 0xEA, 0x00, 0x00})
        else
            if selection.selected == 1 then
	        -- AirRate
		crossfireTelemetryPush(0x2D, {0xEE, 0xEA, 0x01, 0x00})
		pushed = true
	    elseif selection.selected == 2 then
	        -- TLMinterval
	        crossfireTelemetryPush(0x2D, {0xEE, 0xEA, 0x02, 0x00})
		pushed = true
	    elseif selection.selected == 3 then
	        -- MaxPower
	        crossfireTelemetryPush(0x2D, {0xEE, 0xEA, 0x03, 0x00})
		pushed = true
	    elseif selection.selected == 4 then
	        -- RFFreq
	        crossfireTelemetryPush(0x2D, {0xEE, 0xEA, 0x04, 0x00})
		pushed = true
            end
	end
    elseif event == EVT_ROT_RIGHT or 
           event == EVT_MINUS_BREAK or 
	   event == EVT_UP_BREAK then
        if selection.state == false then
            increase(selection)
			crossfireTelemetryPush(0x2D, {0xEE, 0xEA, 0x00, 0x00})
        else
            if selection.selected == 1 then
	        -- AirRate
		crossfireTelemetryPush(0x2D, {0xEE, 0xEA, 0x01, 0x01})
		pushed = true
	    elseif selection.selected == 2 then
	        -- TLMinterval
	        crossfireTelemetryPush(0x2D, {0xEE, 0xEA, 0x02, 0x01})
		pushed = true
	    elseif selection.selected == 3 then
	        -- MaxPower
	        crossfireTelemetryPush(0x2D, {0xEE, 0xEA, 0x03, 0x01})
		pushed = true
	    elseif selection.selected == 4 then
	        -- RFFreq
	        crossfireTelemetryPush(0x2D, {0xEE, 0xEA, 0x04, 0x01})
		pushed = true
            end
	end
    elseif event == EVT_ENTER_BREAK then
        selection.state = not selection.state

    elseif event == EVT_EXIT_BREAK and selection.state then
        -- I was hoping to find the T16 RTN button as an alternate way of deselecting
	-- a field, but no luck so far
        selection.state = false
    end

    if not pushed then
        -- ensure we get up to date values from the module for next time
        --crossfireTelemetryPush(0x2D, {0xEE, 0xEA, 0x00, 0x00})
    end

    refreshLCD()

    return 0
end

return {run = run_func, background = bg_func, init = init_func}
