local env__ = setmetatable({}, { __index = function(_, key)
	return rawget(_G, key) or error("__index on env: " .. tostring(key), 2)
end, __newindex = function(_, key)
	error("__newindex on env: " .. tostring(key), 2)
end })
local _ENV = env__
if rawget(_G, "setfenv") then
	setfenv(1, env__)
end

math.randomseed(os.time())

local require_preload__ = {}
local require_loaded__ = {}
local function require(modname)
	local mod = require_loaded__[modname]
	if not mod then
		mod = assert(assert(require_preload__[modname], "missing module " .. modname)())
		require_loaded__[modname] = mod
	end
	return mod
end
rawset(env__, "require", require)

require_preload__["tptmp.client"] = function()

	local common_util = require("tptmp.common.util")
	
	local loadtime_error
	local http = rawget(_G, "http")
	local socket = rawget(_G, "socket")
	if sim.CELL ~= 4 then -- * Required by cursor snapping functions.
		loadtime_error = "CELL size is not 4"
	elseif sim.PMAPBITS >= 13 then -- * Required by how non-element tools are encoded (extended tool IDs, XIDs).
		loadtime_error = "PMAPBITS is too large"
	elseif not tpt.version or common_util.version_less({ tpt.version.major, tpt.version.minor }, { 97, 0 }) then
		loadtime_error = "version not supported"
	elseif not rawget(_G, "bit") then
		loadtime_error = "no bit API"
	elseif not http then
		loadtime_error = "no http API"
	elseif not socket then
		loadtime_error = "no socket API"
	elseif socket.bind then
		loadtime_error = "outdated socket API"
	elseif tpt.version.jacob1s_mod and not tpt.tab_menu then
		loadtime_error = "mod version not supported"
	elseif tpt.version.mobilemajor then
		loadtime_error = "platform not supported"
	end
	
	local config      =                        require("tptmp.client.config")
	local colours     = not loadtime_error and require("tptmp.client.colours")
	local window      = not loadtime_error and require("tptmp.client.window")
	local side_button = not loadtime_error and require("tptmp.client.side_button")
	local localcmd    = not loadtime_error and require("tptmp.client.localcmd")
	local client      = not loadtime_error and require("tptmp.client.client")
	local util        = not loadtime_error and require("tptmp.client.util")
	local profile     = not loadtime_error and require("tptmp.client.profile")
	local format      = not loadtime_error and require("tptmp.client.format")
	local manager     = not loadtime_error and require("tptmp.client.manager")
	
	local function run()
		if rawget(_G, "TPTMP") then
			if TPTMP.version <= config.version then
				TPTMP.disableMultiplayer()
			else
				loadtime_error = "newer version already running"
			end
		end
		if loadtime_error then
			print("TPTMP " .. config.versionstr .. ": Cannot load: " .. loadtime_error)
			return
		end
	
		local hooks_enabled = false
		local window_status = "hidden"
		local window_hide_mode = "hidden"
		local function set_floating(floating)
			window_hide_mode = floating and "floating" or "hidden"
		end
		local function get_window_status()
			return window_status
		end
		local TPTMP = {
			version = config.version,
			versionStr = config.versionstr,
		}
		local hide_window, show_window, begin_chat
		setmetatable(TPTMP, { __newindex = function(tbl, key, value)
			if key == "chatHidden" then
				if value then
					hide_window()
				else
					show_window()
				end
				return
			end
			rawset(tbl, key, value)
		end, __index = function(tbl, key)
			if key == "chatHidden" then
				return window_status ~= "shown"
			end
			return rawget(tbl, key)
		end })
		rawset(_G, "TPTMP", TPTMP)
	
		local current_id, current_hist = util.get_save_id()
		local function set_id(id, hist)
			current_id, current_hist = id, hist
		end
		local function get_id()
			return current_id, current_hist
		end
	
		local quickauth = manager.get("quickauthToken", "")
		local function set_qa(qa)
			quickauth = qa
			manager.set("quickauthToken", quickauth)
		end
		local function get_qa()
			return quickauth
		end
	
		local function log_event(text)
			print(text)
		end
	
		local should_reconnect_at
		local cli
		local prof = profile.new({
			set_id_func = set_id,
			get_id_func = get_id,
			log_event_func = log_event,
			registered_func = function()
				return cli and cli:registered()
			end
		})
		local win
		local should_reconnect = false
		local function kill_client()
			win:set_subtitle("status", "Not connected")
			cli:fps_sync(false)
			cli:stop()
			if should_reconnect then
				should_reconnect = false
				should_reconnect_at = socket.gettime() + config.reconnect_later_timeout
				win:backlog_push_neutral("* Will attempt to reconnect in " .. config.reconnect_later_timeout .. " seconds")
			end
			cli = nil
		end
		function begin_chat()
			show_window()
			win.hide_when_chat_done = true
		end
		function hide_window()
			window_status = window_hide_mode
			win.in_focus = false
		end
		function show_window()
			if not hooks_enabled then
				TPTMP.enableMultiplayer()
			end
			window_status = "shown"
			win:backlog_bump_marker()
			win.in_focus = true
		end
		win = window.new({
			hide_window_func = hide_window,
			window_status_func = get_window_status,
			log_event_func = log_event,
			client_func = function()
				return cli and cli:registered() and cli
			end,
			localcmd_parse_func = function(str)
				return cmd:parse(str)
			end,
			should_ignore_mouse_func = function(str)
				return prof:should_ignore_mouse()
			end,
		})
		local cmd = localcmd.new({
			window_status_func = get_window_status,
			window_set_floating_func = set_floating,
			client_func = function()
				return cli and cli:registered() and cli
			end,
			new_client_func = function(params)
				should_reconnect_at = nil
				params.window = win
				params.profile = prof
				params.set_id_func = set_id
				params.get_id_func = get_id
				params.set_qa_func = set_qa
				params.get_qa_func = get_qa
				params.log_event_func = log_event
				params.should_reconnect_func = function()
					should_reconnect = true
				end
				params.should_not_reconnect_func = function()
					should_reconnect = false
				end
				cli = client.new(params)
				return cli
			end,
			kill_client_func = function()
				should_reconnect = false
				kill_client()
			end,
			window = win,
		})
		win.localcmd = cmd
		local sbtn = side_button.new({
			notif_count_func = function()
				return win:backlog_notif_count()
			end,
			notif_important_func = function()
				return win:backlog_notif_important()
			end,
			show_window_func = show_window,
			hide_window_func = hide_window,
			begin_chat_func = begin_chat,
			window_status_func = get_window_status,
			sync_func = function()
				cmd:parse("/sync")
			end,
		})
	
		local grab_drop_text_input
		do
			if rawget(_G, "ui") and ui.grabTextInput then
				local text_input_grabbed = false
				function grab_drop_text_input(should_grab)
					if text_input_grabbed and not should_grab then
						ui.dropTextInput()
					elseif not text_input_grabbed and should_grab then
						ui.grabTextInput()
					end
					text_input_grabbed = should_grab
				end
			end
		end
	
		local pcur_r, pcur_g, pcur_b, pcur_a = unpack(colours.common.player_cursor)
		local bmode_to_repr = {
			[ 0 ] = "",
			[ 1 ] = " REPL",
			[ 2 ] = " SDEL",
		}
		local function decode_rulestring(tool)
			if tool.type == "cgol" then
				return tool.repr
			end
		end
		local function handle_tick()
			local now = socket.gettime()
			if should_reconnect_at and now >= should_reconnect_at then
				should_reconnect_at = nil
				win:backlog_push_neutral("* Attempting to reconnect")
				cmd:parse("/reconnect")
			end
			if grab_drop_text_input then
				grab_drop_text_input(window_status == "shown")
			end
			if cli then
				cli:tick()
				if cli:status() ~= "running" then
					kill_client()
				end
			end
			if cli then
				for _, member in pairs(cli.id_to_member) do
					if member:can_render() then
						local px, py = member.pos_x, member.pos_y
						local sx, sy = member.size_x, member.size_y
						local rx, ry = member.rect_x, member.rect_y
						local lx, ly = member.line_x, member.line_y
						local zx, zy, zs = member.zoom_x, member.zoom_y, member.zoom_s
						if rx then
							sx, sy = 0, 0
						end
						local tool = member.last_tool or member.tool_l
						local tool_name = util.to_tool[tool] or decode_rulestring(tool) or "UNKNOWN"
						local tool_class = util.xid_class[tool]
						if elem[tool_name] and tool ~= 0 and tool_name ~= "UNKNOWN" then
							local real_name = elem.property(elem[tool_name], "Name")
							if real_name ~= "" then
								tool_name = real_name
							end
						end
						local add_argb = false
						if tool_name:find("^DEFAULT_DECOR_") then
							add_argb = true
						end
						tool_name = tool_name:match("[^_]+$") or tool_name
						if add_argb then
							tool_name = ("%s %02X%02X%02X%02X"):format(tool_name, member.deco_a, member.deco_r, member.deco_g, member.deco_b)
						end
						local repl_tool_name
						if member.bmode ~= 0 then
							local repl_tool = member.tool_x
							repl_tool_name = util.to_tool[repl_tool] or "UNKNOWN"
							local repl_tool_class = util.xid_class[repl_tool]
							if elem[repl_tool_name] and repl_tool ~= 0 and repl_tool_name ~= "UNKNOWN" then
								local real_name = elem.property(elem[repl_tool_name], "Name")
								if real_name ~= "" then
									repl_tool_name = real_name
								end
							end
							repl_tool_name = repl_tool_name:match("[^_]+$") or repl_tool_name
						end
						if zx and util.inside_rect(zx, zy, zs, zs, px, py) then
							gfx.drawRect(zx - 1, zy - 1, zs + 2, zs + 2, pcur_r, pcur_g, pcur_b, pcur_a)
							if zs > 8 then
								gfx.drawText(zx, zy, "\238\129\165", pcur_r, pcur_g, pcur_b, pcur_a)
							end
						end
						local offx, offy = 6, -9
						local player_info = member.formatted_nick
						if cli.fps_sync_ and member.fps_sync then
							player_info = ("%s %s%+i"):format(player_info, colours.commonstr.brush, member.fps_sync_count_diff)
						end
						local brush_info
						if member.select or member.place then
							local xlo, ylo, xhi, yhi, action
							if member.select then
								xlo = math.min(px, member.select_x)
								ylo = math.min(py, member.select_y)
								xhi = math.max(px, member.select_x)
								yhi = math.max(py, member.select_y)
								action = member.select
							else
								xlo = math.min(sim.XRES - member.place_w, math.max(0, px - math.floor(member.place_w / 2)))
								ylo = math.min(sim.YRES - member.place_h, math.max(0, py - math.floor(member.place_h / 2)))
								xhi = xlo + member.place_w
								yhi = ylo + member.place_h
								action = member.place
							end
							gfx.drawRect(xlo, ylo, xhi - xlo + 1, yhi - ylo + 1, pcur_r, pcur_g, pcur_b, pcur_a)
							brush_info = action
						else
							local dsx, dsy = sx * 2 + 1, sy * 2 + 1
							if tool_class == "WL" then
								px, py = util.wall_snap_coords(px, py)
								sx, sy = util.wall_snap_coords(sx, sy)
								offx, offy = offx + 3, offy + 1
								dsx, dsy = 2 * sx + 4, 2 * sy + 4
							end
							if sx < 50 then
								offx = offx + sx
							end
							brush_info = ("%s %ix%i%s %s"):format(tool_name, dsx, dsy, bmode_to_repr[member.bmode], repl_tool_name or "")
							if not rx then
								if not lx and member.kmod_s and member.kmod_c then
									gfx.drawLine(px - 5, py, px + 5, py, pcur_r, pcur_g, pcur_b, pcur_a)
									gfx.drawLine(px, py - 5, px, py + 5, pcur_r, pcur_g, pcur_b, pcur_a)
								elseif tool_class == "WL" then
									gfx.drawRect(px - sx, py - sy, dsx, dsy, pcur_r, pcur_g, pcur_b, pcur_a)
								elseif member.shape == 0 then
									gfx.drawCircle(px, py, sx, sy, pcur_r, pcur_g, pcur_b, pcur_a)
								elseif member.shape == 1 then
									gfx.drawRect(px - sx, py - sy, sx * 2 + 1, sy * 2 + 1, pcur_r, pcur_g, pcur_b, pcur_a)
								elseif member.shape == 2 then
									gfx.drawLine(px - sx, py + sy, px     , py - sy, pcur_r, pcur_g, pcur_b, pcur_a)
									gfx.drawLine(px - sx, py + sy, px + sx, py + sy, pcur_r, pcur_g, pcur_b, pcur_a)
									gfx.drawLine(px     , py - sy, px + sx, py + sy, pcur_r, pcur_g, pcur_b, pcur_a)
								end
							end
							if lx then
								if member.kmod_a then
									px, py = util.line_snap_coords(lx, ly, px, py)
								end
								gfx.drawLine(lx, ly, px, py, pcur_r, pcur_g, pcur_b, pcur_a)
							end
							if rx then
								if member.kmod_a then
									px, py = util.rect_snap_coords(rx, ry, px, py)
								end
								local x, y, w, h = util.corners_to_rect(px, py, rx, ry)
								gfx.drawRect(x, y, w, h, pcur_r, pcur_g, pcur_b, pcur_a)
							end
						end
						gfx.drawText(px + offx, py + offy, player_info, pcur_r, pcur_g, pcur_b, pcur_a)
						gfx.drawText(px + offx, py + offy + 12, brush_info, pcur_r, pcur_g, pcur_b, pcur_a)
					end
				end
			end
			if window_status ~= "hidden" and win:handle_tick() then
				return false
			end
			if sbtn:handle_tick() then
				return false
			end
			prof:handle_tick()
		end
	
		local function handle_mousemove(px, py, dx, dy)
			if prof:handle_mousemove(px, py, dx, dy) then
				return false
			end
		end
	
		local function handle_mousedown(px, py, button)
			if window_status == "shown" and win:handle_mousedown(px, py, button) then
				return false
			end
			if sbtn:handle_mousedown(px, py, button) then
				return false
			end
			if prof:handle_mousedown(px, py, button) then
				return false
			end
		end
	
		local function handle_mouseup(px, py, button, reason)
			if window_status == "shown" and win:handle_mouseup(px, py, button, reason) then
				return false
			end
			if sbtn:handle_mouseup(px, py, button, reason) then
				return false
			end
			if prof:handle_mouseup(px, py, button, reason) then
				return false
			end
		end
	
		local function handle_mousewheel(px, py, dir)
			if window_status == "shown" and win:handle_mousewheel(px, py, dir) then
				return false
			end
			if sbtn:handle_mousewheel(px, py, dir) then
				return false
			end
			if prof:handle_mousewheel(px, py, dir) then
				return false
			end
		end
	
		local function handle_keypress(key, scan, rep, shift, ctrl, alt)
			if window_status == "shown" and win:handle_keypress(key, scan, rep, shift, ctrl, alt) then
				return false
			end
			if sbtn:handle_keypress(key, scan, rep, shift, ctrl, alt) then
				return false
			end
			if prof:handle_keypress(key, scan, rep, shift, ctrl, alt) then
				return false
			end
		end
	
		local function handle_keyrelease(key, scan, rep, shift, ctrl, alt)
			if window_status == "shown" and win:handle_keyrelease(key, scan, rep, shift, ctrl, alt) then
				return false
			end
			if sbtn:handle_keyrelease(key, scan, rep, shift, ctrl, alt) then
				return false
			end
			if prof:handle_keyrelease(key, scan, rep, shift, ctrl, alt) then
				return false
			end
		end
	
		local function handle_textinput(text)
			if window_status == "shown" and win:handle_textinput(text) then
				return false
			end
			if sbtn:handle_textinput(text) then
				return false
			end
			if prof:handle_textinput(text) then
				return false
			end
		end
	
		local function handle_textediting(text)
			if window_status == "shown" and win:handle_textediting(text) then
				return false
			end
			if sbtn:handle_textediting(text) then
				return false
			end
			if prof:handle_textediting(text) then
				return false
			end
		end
	
		local function handle_blur()
			if window_status == "shown" and win:handle_blur() then
				return false
			end
			if sbtn:handle_blur() then
				return false
			end
			if prof:handle_blur() then
				return false
			end
		end
	
		evt.register(evt.tick      , handle_tick      )
		evt.register(evt.mousemove , handle_mousemove )
		evt.register(evt.mousedown , handle_mousedown )
		evt.register(evt.mouseup   , handle_mouseup   )
		evt.register(evt.mousewheel, handle_mousewheel)
		evt.register(evt.keypress  , handle_keypress  )
		evt.register(evt.textinput , handle_textinput )
		evt.register(evt.keyrelease, handle_keyrelease)
		evt.register(evt.blur      , handle_blur      )
		if evt.textediting then
			evt.register(evt.textediting, handle_textediting)
		end
	
		function TPTMP.disableMultiplayer()
			if cli then
				cmd:parse("/fpssync off")
				cmd:parse("/disconnect")
			end
			evt.unregister(evt.tick      , handle_tick      )
			evt.unregister(evt.mousemove , handle_mousemove )
			evt.unregister(evt.mousedown , handle_mousedown )
			evt.unregister(evt.mouseup   , handle_mouseup   )
			evt.unregister(evt.mousewheel, handle_mousewheel)
			evt.unregister(evt.keypress  , handle_keypress  )
			evt.unregister(evt.textinput , handle_textinput )
			evt.unregister(evt.keyrelease, handle_keyrelease)
			evt.unregister(evt.blur      , handle_blur      )
			if evt.textediting then
				evt.unregister(evt.textediting, handle_textediting)
			end
			_G.TPTMP = nil
		end
	
		function TPTMP.enableMultiplayer()
			hooks_enabled = true
			TPTMP.enableMultiplayer = nil
		end
	
		win:set_subtitle("status", "Not connected")
		win:backlog_push_neutral("* Type " .. colours.commonstr.error .. "/connect" .. colours.commonstr.neutral .. " to join a server, " .. colours.commonstr.error .. "/list" .. colours.commonstr.neutral .. " for a list of commands, or " .. colours.commonstr.error .. "/help" .. colours.commonstr.neutral .. " for command help")
		win:backlog_notif_reset()
	end
	
	return {
		run = run,
	}
	
end

require_preload__["tptmp.client.client"] = function()

	local buffer_list = require("tptmp.common.buffer_list")
	local colours     = require("tptmp.client.colours")
	local config      = require("tptmp.client.config")
	local util        = require("tptmp.client.util")
	local format      = require("tptmp.client.format")
	
	local can_yield_xpcall = coroutine.resume(coroutine.create(function()
		assert(pcall(coroutine.yield))
	end))
	
	local client_i = {}
	local client_m = { __index = client_i }
	
	local packet_handlers = {}
	
	local function get_msec()
		return math.floor(socket.gettime() * 1000)
	end
	
	local index_to_lrax = {
		[ 0 ] = "tool_l",
		[ 1 ] = "tool_r",
		[ 2 ] = "tool_a",
		[ 3 ] = "tool_x",
	}
	
	local function get_auth_token(audience)
		local req = http.getAuthToken(audience)
		local started_at = socket.gettime()
		while req:status() == "running" do
			if socket.gettime() > started_at + config.auth_backend_timeout then
				return nil, "timeout", "failed to contact authentication backend"
			end
			coroutine.yield()
		end
		local body, code = req:finish()
		if code == 403 then
			return nil, "refused", body
		end
		if code ~= 200 then
			return nil, "non200", code
		end
		return body
	end
	
	function client_i:proto_error_(...)
		self:stop("protocol error: " .. string.format(...))
		coroutine.yield()
	end
	
	function client_i:proto_close_(message)
		self:stop(message)
		coroutine.yield()
	end
	
	function client_i:read_(count)
		while self.rx_:pending() < count do
			coroutine.yield()
		end
		return self.rx_:get(count)
	end
	
	function client_i:read_bytes_(count)
		while self.rx_:pending() < count do
			coroutine.yield()
		end
		local data, first, last = self.rx_:next()
		if last >= first + count - 1 then
			-- * Less memory-intensive path.
			self.rx_:pop(count)
			return data:byte(first, first + count - 1)
		end
		return self.rx_:get(count):byte(1, count)
	end
	
	function client_i:read_str24_()
		return self:read_(self:read_24be_())
	end
	
	function client_i:read_str8_()
		return self:read_(self:read_bytes_(1))
	end
	
	function client_i:read_nullstr_(max)
		local collect = {}
		while true do
			local byte = self:read_bytes_(1)
			if byte == 0 then
				break
			end
			if #collect == max then
				self:proto_error_("overlong nullstr")
			end
			table.insert(collect, string.char(byte))
		end
		return table.concat(collect)
	end
	
	function client_i:read_24be_()
		local hi, mi, lo = self:read_bytes_(3)
		return bit.bor(lo, bit.lshift(mi, 8), bit.lshift(hi, 16))
	end
	
	function client_i:read_xy_12_()
		local d24 = self:read_24be_()
		return bit.rshift(d24, 12), bit.band(d24, 0xFFF)
	end
	
	function client_i:handle_disconnect_reason_2_()
		local reason = self:read_str8_()
		self.should_not_reconnect_func_()
		self:stop(reason)
	end
	
	function client_i:handle_ping_3_()
		self.last_ping_received_at_ = socket.gettime()
	end
	
	local member_i = {}
	local member_m = { __index = member_i }
	
	function member_i:can_render()
		return self.can_render_
	end
	
	function member_i:update_can_render()
		if not self.can_render_ then
			if self.deco_a ~= nil and
			   self.kmod_c ~= nil and
			   self.shape  ~= nil and
			   self.size_x ~= nil and
			   self.pos_x  ~= nil then
				self.can_render_ = true
			end
		end
	end
	
	function client_i:add_member_(id, nick)
		if self.id_to_member[id] or id == self.self_id_ then
			self:proto_close_("member already exists")
		end
		self.id_to_member[id] = setmetatable({
			nick = nick,
			fps_sync = false,
		}, member_m)
	end
	
	function client_i:push_names(prefix)
		self.window_:backlog_push_room(self.room_name_, self.id_to_member, prefix)
	end
	
	function client_i:push_fpssync()
		local members = {}
		for _, member in pairs(self.id_to_member) do
			if member.fps_sync then
				table.insert(members, member)
			end
		end
		self.window_:backlog_push_fpssync(members)
	end
	
	function client_i:handle_room_16_()
		sim.clearSim()
		self.room_name_ = self:read_str8_()
		local item_count
		self.self_id_, item_count = self:read_bytes_(2)
		self.id_to_member = {}
		for i = 1, item_count do
			local id = self:read_bytes_(1)
			local nick = self:read_str8_()
			self:add_member_(id, nick)
		end
		self:reformat_nicks_()
		self:push_names("Joined ")
		self.window_:set_subtitle("room", self.room_name_)
		self.localcmd_:reconnect_commit({
			room = self.room_name_,
			host = self.host_,
			port = self.port_,
			secure = self.secure_,
		})
		self.profile_:user_sync()
	end
	
	function client_i:handle_join_17_()
		local id = self:read_bytes_(1)
		local nick = self:read_str8_()
		self:add_member_(id, nick)
		self:reformat_nicks_()
		self.window_:backlog_push_join(self.id_to_member[id].formatted_nick)
		self.profile_:user_sync()
	end
	
	function client_i:member_prefix_()
		local id = self:read_bytes_(1)
		local member = self.id_to_member[id]
		if not member then
			self:proto_close_("no such member")
		end
		return member, id
	end
	
	function client_i:handle_leave_18_()
		local member, id = self:member_prefix_()
		local nick = member.nick
		self.window_:backlog_push_leave(self.id_to_member[id].formatted_nick)
		self.id_to_member[id] = nil
	end
	
	function client_i:handle_say_19_()
		local member = self:member_prefix_()
		local msg = self:read_str8_()
		self.window_:backlog_push_say_other(member.formatted_nick, msg)
	end
	
	function client_i:handle_say3rd_20_()
		local member = self:member_prefix_()
		local msg = self:read_str8_()
		self.window_:backlog_push_say3rd_other(member.formatted_nick, msg)
	end
	
	function client_i:handle_server_22_()
		local msg = self:read_str8_()
		self.window_:backlog_push_server(msg)
	end
	
	function client_i:handle_sync_30_()
		local member = self:member_prefix_()
		self:read_(3)
		local data = self:read_str24_()
		local ok, err = util.stamp_load(0, 0, data, true)
		if ok then
			self.log_event_func_(colours.commonstr.event .. "Sync from " .. member.formatted_nick)
		else
			self.log_event_func_(colours.commonstr.error .. "Failed to sync from " .. member.formatted_nick .. colours.commonstr.error .. ": " .. err)
		end
	end
	
	function client_i:handle_pastestamp_31_()
		local member = self:member_prefix_()
		local x, y = self:read_xy_12_()
		local data = self:read_str24_()
		local ok, err = util.stamp_load(x, y, data, false)
		if ok then
			self.log_event_func_(colours.commonstr.event .. "Stamp from " .. member.formatted_nick) -- * Not really needed thanks to the stamp intent displays in init.lua.
		else
			self.log_event_func_(colours.commonstr.error .. "Failed to paste stamp from " .. member.formatted_nick .. colours.commonstr.error .. ": " .. err)
		end
	end
	
	function client_i:handle_mousepos_32_()
		local member = self:member_prefix_()
		member.pos_x, member.pos_y = self:read_xy_12_()
		member:update_can_render()
	end
	
	function client_i:handle_brushmode_33_()
		local member = self:member_prefix_()
		local bmode = self:read_bytes_(1)
		member.bmode = bmode < 3 and bmode or 0
		member:update_can_render()
	end
	
	function client_i:handle_brushsize_34_()
		local member = self:member_prefix_()
		local x, y = self:read_bytes_(2)
		member.size_x = x
		member.size_y = y
		member:update_can_render()
	end
	
	function client_i:handle_brushshape_35_()
		local member = self:member_prefix_()
		member.shape = self:read_bytes_(1)
		member:update_can_render()
	end
	
	function client_i:handle_keybdmod_36_()
		local member = self:member_prefix_()
		local kmod = self:read_bytes_(1)
		member.kmod_c = bit.band(kmod, 1) ~= 0
		member.kmod_s = bit.band(kmod, 2) ~= 0
		member.kmod_a = bit.band(kmod, 4) ~= 0
		member:update_can_render()
	end
	
	function client_i:handle_selecttool_37_()
		local member = self:member_prefix_()
		local hi, lo = self:read_bytes_(2)
		local tool = bit.bor(lo, bit.lshift(hi, 8))
		local index = bit.rshift(tool, 14)
		local xtype = bit.band(tool, 0x3FFF)
		member[index_to_lrax[index]] = util.to_tool[xtype] and xtype or util.unknown_xid
		member.last_toolslot = index
	end
	
	local simstates = {
		{
			format = "Simulation %s by %s",
			states = { "unpaused", "paused" },
			func = tpt.set_pause,
			shift = 0,
			size = 1,
		},
		{
			format = "Heat simulation %s by %s",
			states = { "disabled", "enabled" },
			func = tpt.heat,
			shift = 1,
			size = 1,
		},
		{
			format = "Ambient heat simulation %s by %s",
			states = { "disabled", "enabled" },
			func = tpt.ambient_heat,
			shift = 2,
			size = 1,
		},
		{
			format = "Newtonian gravity %s by %s",
			states = { "disabled", "enabled" },
			func = tpt.newtonian_gravity,
			shift = 3,
			size = 1,
		},
		{
			format = "Sand effect %s by %s",
			states = { "disabled", "enabled" },
			func = sim.prettyPowders,
			shift = 5,
			size = 1,
		},
		{
			format = "Water equalisation %s by %s",
			states = { "disabled", "enabled" },
			func = sim.waterEqualisation,
			shift = 4,
			size = 1,
		},
		{
			format = "Gravity mode set to %s by %s",
			states = { "vertical", "off", "radial", "custom" },
			func = sim.gravityMode,
			shift = 8,
			size = 2,
		},
		{
			format = "Air mode set to %s by %s",
			states = { "on", "pressure off", "velocity off", "off", "no update" },
			func = sim.airMode,
			shift = 10,
			size = 3,
		},
		{
			format = "Edge mode set to %s by %s",
			states = { "void", "solid", "loop" },
			func = sim.edgeMode,
			shift = 13,
			size = 2,
		},
	}
	function client_i:handle_simstate_38_()
		local member = self:member_prefix_()
		local lo, hi = self:read_bytes_(2)
		local temp = self:read_24be_()
		local gravx = self:read_24be_()
		local gravy = self:read_24be_()
		local bits = bit.bor(lo, bit.lshift(hi, 8))
		for i = 1, #simstates do
			local desc = simstates[i]
			local value = bit.band(bit.rshift(bits, desc.shift), bit.lshift(1, desc.size) - 1)
			if value + 1 > #desc.states then
				value = 0
			end
			if desc.func() ~= value then
				desc.func(value)
				self.log_event_func_(colours.commonstr.event .. desc.format:format(desc.states[value + 1], member.formatted_nick))
			end
		end
		if util.ambient_air_temp() ~= temp then
			local set = util.ambient_air_temp(temp)
			self.log_event_func_(colours.commonstr.event .. ("Ambient air temperature set to %.2f by %s"):format(set, member.formatted_nick))
		end
		do
			local cgx, cgy = util.custom_gravity()
			if cgx ~= gravx or cgy ~= gravy then
				local setx, sety = util.custom_gravity(gravx, gravy)
				if sim.gravityMode() == 3 then
					self.log_event_func_(colours.commonstr.event .. ("Custom gravity set to (%+.2f, %+.2f) by %s"):format(setx, sety, member.formatted_nick))
				end
			end
		end
		self.profile_:sample_simstate()
	end
	
	function client_i:handle_flood_39_()
		local member = self:member_prefix_()
		local index = self:read_bytes_(1)
		if index > 3 then
			index = 0
		end
		member.last_tool = member[index_to_lrax[index]]
		local x, y = self:read_xy_12_()
		util.flood_any(x, y, member.last_tool, -1, -1, member)
	end
	
	function client_i:handle_lineend_40_()
		local member = self:member_prefix_()
		local x1, y1 = member.line_x, member.line_y
		local x2, y2 = self:read_xy_12_()
		if member.kmod_a then
			x2, y2 = util.line_snap_coords(x1, y1, x2, y2)
		end
		util.create_line_any(x1, y1, x2, y2, member.size_x, member.size_y, member.last_tool, member.shape, member, false)
		member.line_x, member.line_y = nil, nil
	end
	
	function client_i:handle_rectend_41_()
		local member = self:member_prefix_()
		local x1, y1 = member.rect_x, member.rect_y
		local x2, y2 = self:read_xy_12_()
		if member.kmod_a then
			x2, y2 = util.rect_snap_coords(x1, y1, x2, y2)
		end
		util.create_box_any(x1, y1, x2, y2, member.last_tool, member)
		member.rect_x, member.rect_y = nil, nil
	end
	
	function client_i:handle_pointsstart_42_()
		local member = self:member_prefix_()
		local index = self:read_bytes_(1)
		if index > 3 then
			index = 0
		end
		member.last_tool = member[index_to_lrax[index]]
		local x, y = self:read_xy_12_()
		util.create_parts_any(x, y, member.size_x, member.size_y, member.last_tool, member.shape, member)
		member.last_x = x
		member.last_y = y
	end
	
	function client_i:handle_pointscont_43_()
		local member = self:member_prefix_()
		local x, y = self:read_xy_12_()
		util.create_line_any(member.last_x, member.last_y, x, y, member.size_x, member.size_y, member.last_tool, member.shape, member, true)
		member.last_x = x
		member.last_y = y
	end
	
	function client_i:handle_linestart_44_()
		local member = self:member_prefix_()
		local index = self:read_bytes_(1)
		if index > 3 then
			index = 0
		end
		member.last_tool = member[index_to_lrax[index]]
		member.line_x, member.line_y = self:read_xy_12_()
	end
	
	function client_i:handle_rectstart_45_()
		local member = self:member_prefix_()
		local index = self:read_bytes_(1)
		if index > 3 then
			index = 0
		end
		member.last_tool = member[index_to_lrax[index]]
		member.rect_x, member.rect_y = self:read_xy_12_()
	end
	
	function client_i:handle_custgolinfo_46_()
		local member = self:member_prefix_()
		local ruleset = bit.band(self:read_24be_(), 0x1FFFFF)
		local primary = self:read_24be_()
		local secondary = self:read_24be_()
		local begin = bit.band(bit.rshift(ruleset, 8), 0x1FE)
		local stay = bit.band(ruleset, 0x1FF)
		local states = bit.band(bit.rshift(ruleset, 17), 0xF) + 2
		local repr = {}
		table.insert(repr, "B")
		for i = 0, 8 do
			if bit.band(bit.lshift(1, i), begin) ~= 0 then
				table.insert(repr, i)
			end
		end
		table.insert(repr, "/")
		table.insert(repr, "S")
		for i = 0, 8 do
			if bit.band(bit.lshift(1, i), stay) ~= 0 then
				table.insert(repr, i)
			end
		end
		if states ~= 2 then
			table.insert(repr, "/")
			table.insert(repr, states)
		end
		member[index_to_lrax[member.last_toolslot]] = {
			type = "cgol",
			repr = table.concat(repr),
			ruleset = ruleset,
			primary = primary,
			secondary = secondary,
			elem = bit.bor(elem.DEFAULT_PT_LIFE, bit.lshift(ruleset, sim.PMAPBITS)),
		}
	end
	
	function client_i:handle_stepsim_50_()
		local member = self:member_prefix_()
		tpt.set_pause(1)
		sim.framerender(1)
		self.log_event_func_(colours.commonstr.event .. "Single-frame step from " .. member.formatted_nick)
	end
	
	function client_i:handle_sparkclear_60_()
		local member = self:member_prefix_()
		tpt.reset_spark()
		self.log_event_func_(colours.commonstr.event .. "Sparks cleared by " .. member.formatted_nick)
	end
	
	function client_i:handle_airclear_61_()
		local member = self:member_prefix_()
		tpt.reset_velocity()
		tpt.set_pressure()
		self.log_event_func_(colours.commonstr.event .. "Pressure cleared by " .. member.formatted_nick)
	end
	
	function client_i:handle_airinv_62_()
		-- * TODO[api]: add an api for this to tpt
		local member = self:member_prefix_()
		for x = 0, sim.XRES / sim.CELL - 1 do
			for y = 0, sim.YRES / sim.CELL - 1 do
				sim.pressure(x, y, -sim.pressure(x, y))
			end
		end
		self.log_event_func_(colours.commonstr.event .. "Pressure inverted by " .. member.formatted_nick)
	end
	
	function client_i:handle_clearsim_63_()
		local member = self:member_prefix_()
		sim.clearSim()
		self.set_id_func_(nil, nil)
		self.log_event_func_(colours.commonstr.event .. "Simulation cleared by " .. member.formatted_nick)
	end
	
	function client_i:handle_heatclear_64_()
		-- * TODO[api]: add an api for this to tpt
		local member = self:member_prefix_()
		util.heat_clear()
		self.log_event_func_(colours.commonstr.event .. "Ambient heat reset by " .. member.formatted_nick)
	end
	
	function client_i:handle_brushdeco_65_()
		local member = self:member_prefix_()
		member.deco_a, member.deco_r, member.deco_g, member.deco_b = self:read_bytes_(4)
		member:update_can_render()
	end
	
	function client_i:handle_clearrect_67_()
		self:member_prefix_()
		local x, y = self:read_xy_12_()
		local w, h = self:read_xy_12_()
		sim.clearRect(x, y, w, h)
	end
	
	function client_i:handle_canceldraw_68_()
		local member = self:member_prefix_()
		member.rect_x, member.rect_y = nil, nil
		member.line_x, member.line_y = nil, nil
		member.last_tool = nil
	end
	
	function client_i:handle_loadonline_69_()
		local member = self:member_prefix_()
		local id = self:read_24be_()
		local histhi = self:read_24be_()
		local histlo = self:read_24be_()
		local hist = histhi * 0x1000000 + histlo
		if id > 0 then
			sim.loadSave(id, 1, hist)
			coroutine.yield() -- * sim.loadSave seems to take effect one frame late.
			self.set_id_func_(id, hist)
			self.log_event_func_(colours.commonstr.event .. "Online save " .. (hist == 0 and "id" or "history") .. ":" .. id .. " loaded by " .. member.formatted_nick)
		end
	end
	
	function client_i:handle_reloadsim_70_()
		local member = self:member_prefix_()
		if self.get_id_func_() then
			sim.reloadSave()
		end
		self.log_event_func_(colours.commonstr.event .. "Simulation reloaded by " .. member.formatted_nick)
	end
	
	function client_i:handle_placestatus_71_()
		local member = self:member_prefix_()
		local k = self:read_bytes_(1)
		local w, h = self:read_xy_12_()
		if k == 0 then
			member.place = nil
		elseif k == 1 then
			member.place = "Pasting"
		end
		member.place_w = w
		member.place_h = h
	end
	
	function client_i:handle_selectstatus_72_()
		local member = self:member_prefix_()
		local k = self:read_bytes_(1)
		local x, y = self:read_xy_12_()
		if k == 0 then
			member.select = nil
		elseif k == 1 then
			member.select = "Copying"
		elseif k == 2 then
			member.select = "Cutting"
		elseif k == 3 then
			member.select = "Stamping"
		end
		member.select_x = x
		member.select_y = y
	end
	
	function client_i:handle_zoomstart_73_()
		local member = self:member_prefix_()
		local x, y = self:read_xy_12_()
		local s = self:read_bytes_(1)
		member.zoom_x = x
		member.zoom_y = y
		member.zoom_s = s
	end
	
	function client_i:handle_zoomend_74_()
		local member = self:member_prefix_()
		member.zoom_x = nil
		member.zoom_y = nil
		member.zoom_s = nil
	end
	
	function client_i:handle_sparksign_75_()
		local member = self:member_prefix_()
		local x, y = self:read_xy_12_()
		sim.partCreate(-1, x, y, elem.DEFAULT_PT_SPRK)
	end
	
	function client_i:handle_fpssync_76_()
		local member = self:member_prefix_()
		local hi = self:read_24be_()
		local mi = self:read_24be_()
		local lo = self:read_24be_()
		local elapsed = hi * 0x1000 + math.floor(mi / 0x1000)
		local count = mi % 0x1000 * 0x1000000 + lo
		if member.fps_sync and elapsed <= member.fps_sync_elapsed then
			self:fps_sync_end_(member)
		end
		local now_msec = get_msec()
		if not member.fps_sync then
			member.fps_sync = true
			member.fps_sync_count_diff = 0
			member.fps_sync_first = now_msec
			member.fps_sync_history = {}
			if self.fps_sync_count_ then
				member.fps_sync_count_offset = count - self.fps_sync_count_
			end
			if self.fps_sync_ then
				self.window_:backlog_push_fpssync_enable(member.formatted_nick)
			end
		end
		member.fps_sync_last = now_msec
		member.fps_sync_elapsed = elapsed
		member.fps_sync_count = count
		local history_item = { elapsed = elapsed, count = count, now_msec = now_msec }
		local history_size = #member.fps_sync_history
		if history_size < 5 then
			table.insert(member.fps_sync_history, 1, history_item)
		else
			for i = 1, history_size - 1 do
				member.fps_sync_history[i + 1] = member.fps_sync_history[i]
			end
			member.fps_sync_history[1] = history_item
		end
	end
	
	function client_i:handle_sync_request_128_()
		self:send_sync_done()
	end
	
	function client_i:connect_()
		self.server_probably_secure_ = nil
		self.window_:set_subtitle("status", "Connecting")
		self.socket_ = socket.tcp()
		self.socket_:settimeout(0)
		self.socket_:setoption("tcp-nodelay", true)
		while true do
			local ok, err = self.socket_:connect(self.host_, self.port_, self.secure_)
			if ok then
				break
			elseif err == "timeout" then
				coroutine.yield()
			else
				local errl = err:lower()
				if errl:find("schannel") or errl:find("ssl") then
					self.server_probably_secure_ = true
				end
				self:proto_close_(err)
			end
		end
		self.connected_ = true
	end
	
	function client_i:handshake_()
		self.window_:set_subtitle("status", "Registering")
		local name = util.get_name()
		self:write_bytes_(tpt.version.major, tpt.version.minor, config.version)
		self:write_nullstr_((name or tpt.get_name() or ""):sub(1, 255))
		self:write_bytes_(0) -- * Flags, currently unused.
		local qa_host, qa_port, qa_name, qa_token = self.get_qa_func_():match("^([^:]+):([^:]+):([^:]+):([^:]+)$")
		self:write_str8_(qa_token and qa_name == name and qa_host == self.host_ and tonumber(qa_port) == self.port_ and qa_token or "")
		self:write_str8_(self.initial_room_ or "")
		self:write_flush_()
		local conn_status = self:read_bytes_(1)
		local auth_err
		if conn_status == 4 then -- * Quickauth failed.
			self.window_:set_subtitle("status", "Authenticating")
			local token = ""
			if name then
				local fresh_token, err, info = get_auth_token(self.host_ .. ":" .. self.port_)
				if fresh_token then
					token = fresh_token
				else
					if err == "non200" then
						auth_err = "authentication failed (status code " .. info .. "); try again later or try restarting TPT"
					elseif err == "timeout" then
						auth_err = "authentication failed (timeout: " .. info .. "); try again later or try restarting TPT"
					else
						auth_err = "authentication failed (" .. err .. ": " .. info .. "); try logging out and back in and restarting TPT"
					end
				end
			end
			self:write_str8_(token)
			self:write_flush_()
			conn_status = self:read_bytes_(1)
			if name then
				self.set_qa_func_((conn_status == 1) and (self.host_ .. ":" .. self.port_ .. ":" .. name .. ":" .. token) or "")
			end
		end
		local downgrade_reason
		if conn_status == 5 then -- * Downgraded to guest.
			downgrade_reason = self:read_str8_()
			conn_status = self:read_bytes_(1)
		end
		if conn_status == 1 then
			self.should_reconnect_func_()
			self.registered_ = true
			self.nick_ = self:read_str8_()
			self:reformat_nicks_()
			self.flags_ = self:read_bytes_(1)
			self.guest_ = bit.band(self.flags_, 1) ~= 0
			self.last_ping_sent_at_ = socket.gettime()
			self.connecting_since_ = nil
			if tpt.get_name() and auth_err then
				self.window_:backlog_push_error("Warning: " .. auth_err)
			end
			if downgrade_reason then
				self.window_:backlog_push_error("Warning: " .. downgrade_reason)
			end
			self.window_:backlog_push_registered(self.formatted_nick_)
			self.profile_:set_client(self)
		elseif conn_status == 0 then
			local reason = self:read_nullstr_(255)
			self:proto_close_(auth_err or reason)
		else
			self:proto_error_("invalid connection status (%i)", conn_status)
		end
	end
	
	function client_i:send_ping()
		self:write_flush_("\3")
	end
	
	function client_i:send_say(str)
		self:write_("\19")
		self:write_str8_(str)
		self:write_flush_()
	end
	
	function client_i:send_say3rd(str)
		self:write_("\20")
		self:write_str8_(str)
		self:write_flush_()
	end
	
	function client_i:send_mousepos(px, py)
		self:write_("\32")
		self:write_xy_12_(px, py)
		self:write_flush_()
	end
	
	function client_i:send_brushmode(bmode)
		self:write_("\33")
		self:write_bytes_(bmode)
		self:write_flush_()
	end
	
	function client_i:send_brushsize(sx, sy)
		self:write_("\34")
		self:write_bytes_(sx, sy)
		self:write_flush_()
	end
	
	function client_i:send_brushshape(shape)
		self:write_("\35")
		self:write_bytes_(shape)
		self:write_flush_()
	end
	
	function client_i:send_keybdmod(c, s, a)
		self:write_("\36")
		self:write_bytes_(bit.bor(c and 1 or 0, s and 2 or 0, a and 4 or 0))
		self:write_flush_()
	end
	
	function client_i:send_selecttool(idx, xtype)
		self:write_("\37")
		local tool = bit.bor(xtype, bit.lshift(idx, 14))
		local hi = bit.band(bit.rshift(tool, 8), 0xFF)
		local lo = bit.band(           tool    , 0xFF)
		self:write_bytes_(hi, lo)
		self:write_flush_()
	end
	
	function client_i:send_simstate(ss_p, ss_h, ss_u, ss_n, ss_w, ss_g, ss_a, ss_e, ss_y, ss_t, ss_r, ss_s)
		self:write_("\38")
		local toggles = bit.bor(
			           ss_p    ,
			bit.lshift(ss_h, 1),
			bit.lshift(ss_u, 2),
			bit.lshift(ss_n, 3),
			bit.lshift(ss_w, 4),
			bit.lshift(ss_y, 5)
		)
		local multis = bit.bor(
			           ss_g    ,
			bit.lshift(ss_a, 2),
			bit.lshift(ss_e, 5)
		)
		self:write_bytes_(toggles, multis)
		self:write_24be_(ss_t)
		self:write_24be_(ss_r)
		self:write_24be_(ss_s)
		self:write_flush_()
	end
	
	function client_i:send_flood(index, x, y)
		self:write_("\39")
		self:write_bytes_(index)
		self:write_xy_12_(x, y)
		self:write_flush_()
	end
	
	function client_i:send_lineend(x, y)
		self:write_("\40")
		self:write_xy_12_(x, y)
		self:write_flush_()
	end
	
	function client_i:send_rectend(x, y)
		self:write_("\41")
		self:write_xy_12_(x, y)
		self:write_flush_()
	end
	
	function client_i:send_pointsstart(index, x, y)
		self:write_("\42")
		self:write_bytes_(index)
		self:write_xy_12_(x, y)
		self:write_flush_()
	end
	
	function client_i:send_pointscont(x, y)
		self:write_("\43")
		self:write_xy_12_(x, y)
		self:write_flush_()
	end
	
	function client_i:send_linestart(index, x, y)
		self:write_("\44")
		self:write_bytes_(index)
		self:write_xy_12_(x, y)
		self:write_flush_()
	end
	
	function client_i:send_rectstart(index, x, y)
		self:write_("\45")
		self:write_bytes_(index)
		self:write_xy_12_(x, y)
		self:write_flush_()
	end
	
	function client_i:send_custgolinfo(ruleset, primary, secondary)
		self:write_("\46")
		self:write_24be_(ruleset)
		self:write_24be_(primary)
		self:write_24be_(secondary)
		self:write_flush_()
	end
	
	function client_i:send_stepsim()
		self:write_flush_("\50")
	end
	
	function client_i:send_sparkclear()
		self:write_flush_("\60")
	end
	
	function client_i:send_airclear()
		self:write_flush_("\61")
	end
	
	function client_i:send_airinv()
		self:write_flush_("\62")
	end
	
	function client_i:send_clearsim()
		self:write_flush_("\63")
	end
	
	function client_i:send_heatclear()
		self:write_flush_("\64")
	end
	
	function client_i:send_brushdeco(deco)
		self:write_("\65")
		self:write_bytes_(
			bit.band(bit.rshift(deco, 24), 0xFF),
			bit.band(bit.rshift(deco, 16), 0xFF),
			bit.band(bit.rshift(deco,  8), 0xFF),
			bit.band(           deco     , 0xFF)
		)
		self:write_flush_()
	end
	
	function client_i:send_clearrect(x, y, w, h)
		self:write_("\67")
		self:write_xy_12_(x, y)
		self:write_xy_12_(w, h)
		self:write_flush_()
	end
	
	function client_i:send_canceldraw()
		self:write_flush_("\68")
	end
	
	function client_i:send_loadonline(id, hist)
		self:write_("\69")
		self:write_24be_(id)
		self:write_24be_(math.floor(hist / 0x1000000))
		self:write_24be_(           hist % 0x1000000 )
		self:write_flush_()
	end
	
	function client_i:send_pastestamp_data_(pid, x, y, w, h)
		local data, err = util.stamp_save(x, y, w, h)
		if not data then
			return nil, err
		end
		self:write_(pid)
		self:write_xy_12_(x, y)
		self:write_str24_(data)
		self:write_flush_()
		return true
	end
	
	function client_i:send_pastestamp(x, y, w, h)
		local ok, err = self:send_pastestamp_data_("\31", x, y, w, h)
		if not ok then
			self.log_event_func_(colours.commonstr.error .. "Failed to send stamp: " .. err)
		end
	end
	
	function client_i:send_sync()
		local ok, err = self:send_pastestamp_data_("\30", 0, 0, sim.XRES, sim.YRES)
		if not ok then
			self.log_event_func_(colours.commonstr.error .. "Failed to send screen: " .. err)
		end
	end
	
	function client_i:send_reloadsim()
		self:write_flush_("\70")
	end
	
	function client_i:send_placestatus(k, w, h)
		self:write_("\71")
		self:write_bytes_(k)
		self:write_xy_12_(w, h)
		self:write_flush_()
	end
	
	function client_i:send_selectstatus(k, x, y)
		self:write_("\72")
		self:write_bytes_(k)
		self:write_xy_12_(x, y)
		self:write_flush_()
	end
	
	function client_i:send_zoomstart(x, y, s)
		self:write_("\73")
		self:write_xy_12_(x, y)
		self:write_bytes_(s)
		self:write_flush_()
	end
	
	function client_i:send_zoomend()
		self:write_flush_("\74")
	end
	
	function client_i:send_sparksign(x, y)
		self:write_("\75")
		self:write_xy_12_(x, y)
		self:write_flush_()
	end
	
	function client_i:send_fpssync(elapsed, count)
		self:write_("\76")
		self:write_24be_(math.floor(elapsed / 0x1000))
		self:write_24be_(elapsed % 0x1000 * 0x1000 + math.floor(count / 0x1000000))
		self:write_24be_(count % 0x1000000)
		self:write_flush_()
	end
	
	function client_i:send_sync_done()
		self:write_flush_("\128")
		local id, hist = self.get_id_func_()
		self:send_loadonline(id or 0, hist or 0)
		self:send_sync()
		self.profile_:simstate_sync()
	end
	
	function client_i:start()
		assert(self.status_ == "ready")
		self.status_ = "running"
		self.proto_coro_ = coroutine.create(function()
			local wrap_traceback = can_yield_xpcall and xpcall or function(func)
				-- * It doesn't matter if wrap_traceback is not a real xpcall
				--   as the error would be re-thrown later anyway, but a real
				--   xpcall is preferable because it lets us print a stack trace
				--   from within the coroutine.
				func()
				return true
			end
			local ok, err = wrap_traceback(function()
				self:connect_()
				self:handshake_()
				while true do
					local packet_id = self:read_bytes_(1)
					local handler = packet_handlers[packet_id]
					if not handler then
						self:proto_error_("invalid packet ID (%i)", packet_id)
					end
					handler(self)
				end
			end, function(err)
				print(debug.traceback(err, 2))
			end)
			if not ok then
				error(err)
			end
		end)
	end
	
	function client_i:tick_read_()
		if self.connected_ and not self.read_closed_ then
			while true do
				local closed = false
				local data, err, partial = self.socket_:receive(config.read_size)
				if not data then
					if err == "closed" then
						data = partial
						closed = true
					elseif err == "timeout" then
						data = partial
					else
						self:stop(err)
						break
					end
				end
				local pushed, count = self.rx_:push(data)
				if pushed < count then
					self:stop("recv queue limit exceeded")
					break
				end
				if closed then
					self:tick_resume_()
					self:stop("connection closed: receive failed: " .. tostring(self.socket_lasterror_))
					break
				end
				if #data < config.read_size then
					break
				end
			end
		end
	end
	
	function client_i:tick_resume_()
		if self.proto_coro_ then
			local ok, err = coroutine.resume(self.proto_coro_)
			if not ok then
				self.proto_coro_ = nil
				error(err)
			end
			if self.proto_coro_ and coroutine.status(self.proto_coro_) == "dead" then
				error("proto coroutine terminated")
			end
		end
	end
	
	function client_i:tick_write_()
		if self.connected_ then
			while true do
				local data, first, last = self.tx_:next()
				if not data then
					break
				end
				local closed = false
				local count = last - first + 1
				if self.socket_:status() ~= "connected" then
					break
				end
				local written_up_to, err, partial_up_to = self.socket_:send(data, first, last)
				if not written_up_to then
					if err == "closed" then
						written_up_to = partial_up_to
						closed = true
					elseif err == "timeout" then
						written_up_to = partial_up_to
					else
						self:stop(err)
						break
					end
				end
				local written = written_up_to - first + 1
				self.tx_:pop(written)
				if closed then
					self.socket_lasterror_ = self.socket_:lasterror()
					self:stop("connection closed: send failed: " .. tostring(self.socket_lasterror_))
					break
				end
				if written < count then
					break
				end
			end
		end
	end
	
	function client_i:tick_connect_()
		if self.socket_ then
			if self.connecting_since_ and self.connecting_since_ + config.connect_timeout < socket.gettime() then
				self:stop("connect timeout")
			end
		end
	end
	
	function client_i:tick_ping_()
		if self.registered_ then
			local now = socket.gettime()
			if self.last_ping_sent_at_ + config.ping_interval < now then
				self:send_ping()
				self.last_ping_sent_at_ = now
			end
			if self.last_ping_received_at_ + config.ping_timeout < now then
				self:stop("ping timeout")
			end
		end
	end
	
	function client_i:tick_sim_()
		for _, member in pairs(self.id_to_member) do
			if member:can_render() then
				local lx, ly = member.line_x, member.line_y
				if member.last_tool == util.from_tool.DEFAULT_UI_WIND and not (member.select or member.place) and lx then
					local px, py = member.pos_x, member.pos_y
					if member.kmod_a then
						px, py = util.line_snap_coords(lx, ly, px, py)
					end
					util.create_line_any(lx, ly, px, py, member.size_x, member.size_y, member.last_tool, member.shape, member, false)
				end
			end
		end
	end
	
	function client_i:fps_sync_end_(member)
		if self.fps_sync_ then
			self.window_:backlog_push_fpssync_disable(member.formatted_nick)
		end
		member.fps_sync = false
	end
	
	function client_i:tick_fpssync_invalidate_()
		if self.registered_ then
			local now_msec = get_msec()
			for _, member in pairs(self.id_to_member) do
				if member.fps_sync then
					if member.fps_sync_last + config.fps_sync_timeout < now_msec then
						self:fps_sync_end_(member)
					end
				end
			end
		end
	end
	
	function client_i:tick_fpssync_()
		if self.registered_ then
			if self.fps_sync_ then
				local now_msec = get_msec()
				if not self.fps_sync_first_ then
					self.fps_sync_first_ = now_msec
					self.fps_sync_last_ = 0
					self.fps_sync_count_ = 0
					for _, member in pairs(self.id_to_member) do
						if member.fps_sync then
							member.fps_sync_count_offset = member.fps_sync_count
						end
					end
				end
				self.fps_sync_count_ = self.fps_sync_count_ + 1
				if now_msec >= self.fps_sync_last_ + 1000 then
					self:send_fpssync(now_msec - self.fps_sync_first_, self.fps_sync_count_)
					self.fps_sync_last_ = now_msec
				end
				local target_fps = self.fps_sync_target_			
				local smallest_target = self.fps_sync_count_ + math.floor(target_fps * config.fps_sync_plan_ahead_by / 1000)
				if self.fps_sync_target_ == 2 then
					smallest_target = math.huge
				end
				for _, member in pairs(self.id_to_member) do
					if member.fps_sync and #member.fps_sync_history >= 2 then
						local diff_count = member.fps_sync_history[1].count - member.fps_sync_history[2].count
						local diff_elapsed = member.fps_sync_history[1].elapsed - member.fps_sync_history[2].elapsed
						local slope = diff_count / (diff_elapsed / 1000)
						if slope <     5 then slope =     5 end
						if slope > 10000 then slope = 10000 end
						local current_msec = now_msec - member.fps_sync_history[1].now_msec
						local current_frames_remote = math.floor(member.fps_sync_history[1].count + slope * (current_msec / 1000))
						local current_frames_local = current_frames_remote - member.fps_sync_count_offset
						local target_msec = now_msec - member.fps_sync_history[1].now_msec + config.fps_sync_plan_ahead_by
						local target_frames_remote = math.floor(member.fps_sync_history[1].count + slope * (target_msec / 1000))
						local target_frames_local = target_frames_remote - member.fps_sync_count_offset
						member.fps_sync_count_diff = current_frames_local - self.fps_sync_count_
						if smallest_target > target_frames_local then
							smallest_target = target_frames_local
						end
					end
				end
				if smallest_target == math.huge then
					tpt.setfpscap(2)
				else
					local smallest_fps = (smallest_target - self.fps_sync_count_) / (config.fps_sync_plan_ahead_by / 1000)
					local fps = math.floor((target_fps + (smallest_fps - target_fps) * config.fps_sync_homing_factor) + 0.5)
					if fps < 10 then fps = 10 end
					tpt.setfpscap(fps)
				end
			end
		end
	end
	
	function client_i:tick()
		if self.status_ ~= "running" then
			return
		end
		self:tick_fpssync_invalidate_()
		self:tick_read_()
		self:tick_resume_()
		self:tick_write_()
		self:tick_connect_()
		self:tick_ping_()
		self:tick_sim_()
		self:tick_fpssync_()
	end
	
	function client_i:stop(message)
		if self.status_ == "dead" then
			return
		end
		self.profile_:clear_client()
		if self.socket_ then
			if self.connected_ then
				self.socket_:shutdown()
			end
			self.socket_:close()
			self.socket_lasterror_ = self.socket_:lasterror()
			self.socket_ = nil
			self.connected_ = nil
			self.registered_ = nil
		end
		self.proto_coro_ = nil
		self.status_ = "dead"
		local disconnected = "Disconnected"
		if message then
			disconnected = disconnected .. ": " .. message
		end
		self.window_:backlog_push_error(disconnected)
		if self.server_probably_secure_ then
			self.window_:backlog_push_error(("The server probably does not support secure connections, try /connect %s:%i"):format(self.host_, self.port_))
		end
	end
	
	function client_i:write_(data)
		if not self.write_buf_ then
			self.write_buf_ = data
		elseif type(self.write_buf_) == "string" then
			self.write_buf_ = { self.write_buf_, data }
		else
			table.insert(self.write_buf_, data)
		end
	end
	
	function client_i:write_flush_(data)
		if data then
			self:write_(data)
		end
		local buf = self.write_buf_
		self.write_buf_ = nil
		local pushed, count = self.tx_:push(type(buf) == "string" and buf or table.concat(buf))
		if pushed < count then
			self:stop("send queue limit exceeded")
		end
	end
	
	function client_i:write_bytes_(...)
		self:write_(string.char(...))
	end
	
	function client_i:write_str24_(str)
		local length = math.min(#str, 0xFFFFFF)
		self:write_24be_(length)
		self:write_(str:sub(1, length))
	end
	
	function client_i:write_str8_(str)
		local length = math.min(#str, 0xFF)
		self:write_bytes_(length)
		self:write_(str:sub(1, length))
	end
	
	function client_i:write_nullstr_(str)
		self:write_(str:gsub("[^\1-\255]", ""))
		self:write_("\0")
	end
	
	function client_i:write_24be_(d24)
		local hi = bit.band(bit.rshift(d24, 16), 0xFF)
		local mi = bit.band(bit.rshift(d24,  8), 0xFF)
		local lo = bit.band(           d24     , 0xFF)
		self:write_bytes_(hi, mi, lo)
	end
	
	function client_i:write_xy_12_(x, y)
		self:write_24be_(bit.bor(bit.lshift(x, 12), y))
	end
	
	function client_i:nick()
		return self.nick_
	end
	
	function client_i:formatted_nick()
		return self.formatted_nick_
	end
	
	function client_i:status()
		return self.status_
	end
	
	function client_i:connected()
		return self.connected_
	end
	
	function client_i:registered()
		return self.registered_
	end
	
	function client_i:nick_colour_seed(seed)
		self.nick_colour_seed_ = seed
		self:reformat_nicks_()
	end
	
	function client_i:fps_sync(fps_sync)
		if self.fps_sync_ and not fps_sync then
			tpt.setfpscap(self.fps_sync_target_)
		end
		if not self.fps_sync_ and fps_sync then
			self.fps_sync_first_ = nil
		end
		self.fps_sync_ = fps_sync and true or false
		self.fps_sync_target_ = fps_sync or false
	end
	
	function client_i:reformat_nicks_()
		if self.nick_ then
			self.formatted_nick_ = format.nick(self.nick_, self.nick_colour_seed_)
		end
		for _, member in pairs(self.id_to_member) do
			member.formatted_nick = format.nick(member.nick, self.nick_colour_seed_)
		end
	end
	
	for key, value in pairs(client_i) do
		local packet_id_str = key:match("^handle_.+_(%d+)_$")
		if packet_id_str then
			local packet_id = tonumber(packet_id_str)
			assert(not packet_handlers[packet_id])
			packet_handlers[packet_id] = value
		end
	end
	
	local function new(params)
		local now = socket.gettime()
		return setmetatable({
			host_ = params.host,
			port_ = params.port,
			secure_ = params.secure,
			event_log_ = params.event_log,
			backlog_ = params.backlog,
			rx_ = buffer_list.new({ limit = config.recvq_limit }),
			tx_ = buffer_list.new({ limit = config.sendq_limit }),
			connecting_since_ = now,
			last_ping_sent_at_ = now,
			last_ping_received_at_ = now,
			status_ = "ready",
			window_ = params.window,
			profile_ = params.profile,
			localcmd_ = params.localcmd,
			initial_room_ = params.initial_room,
			set_id_func_ = params.set_id_func,
			get_id_func_ = params.get_id_func,
			set_qa_func_ = params.set_qa_func,
			get_qa_func_ = params.get_qa_func,
			log_event_func_ = params.log_event_func,
			should_reconnect_func_ = params.should_reconnect_func,
			should_not_reconnect_func_ = params.should_not_reconnect_func,
			id_to_member = {},
			nick_colour_seed_ = 0,
			fps_sync_ = false,
		}, client_m)
	end
	
	return {
		new = new,
	}
	
end

require_preload__["tptmp.client.colours"] = function()

	local utf8 = require("tptmp.client.utf8")
	
	local function hsv_to_rgb(hue, saturation, value) -- * [0, 1), [0, 1), [0, 1)
		local sector = math.floor(hue * 6)
		local offset = hue * 6 - sector
		local red, green, blue
		if sector == 0 then
			red, green, blue = 1, offset, 0
		elseif sector == 1 then
			red, green, blue = 1 - offset, 1, 0
		elseif sector == 2 then
			red, green, blue = 0, 1, offset
		elseif sector == 3 then
			red, green, blue = 0, 1 - offset, 1
		elseif sector == 4 then
			red, green, blue = offset, 0, 1
		else
			red, green, blue = 1, 0, 1 - offset
		end
		return {
			math.floor((saturation * (red   - 1) + 1) * 0xFF * value),
			math.floor((saturation * (green - 1) + 1) * 0xFF * value),
			math.floor((saturation * (blue  - 1) + 1) * 0xFF * value),
		}
	end
	
	local function escape(rgb)
		-- * TODO[api]: Fix this TPT bug: most strings are still passed to/from Lua as zero-terminated, hence the math.max.
		return utf8.encode_multiple(15, math.max(rgb[1], 1), math.max(rgb[2], 1), math.max(rgb[3], 1))
	end
	
	local common = {}
	local commonstr = {}
	for key, value in pairs({
		brush           = {   0, 255,   0 },
		chat            = { 255, 255, 255 },
		error           = { 255,  50,  50 },
		event           = { 255, 255, 255 },
		join            = { 100, 255, 100 },
		leave           = { 255, 255, 100 },
		fpssyncenable   = { 255, 100, 255 },
		fpssyncdisable  = { 130, 130, 255 },
		lobby           = {   0, 200, 200 },
		neutral         = { 200, 200, 200 },
		room            = { 200, 200,   0 },
		status          = { 150, 150, 150 },
		notif_normal    = { 100, 100, 100 },
		notif_important = { 255,  50,  50 },
		player_cursor   = {   0, 255,   0, 128 },
	}) do
		common[key] = value
		commonstr[key] = escape(value)
	end
	
	local appearance = {
		hover = {
			background = {  20,  20,  20 },
			text       = { 255, 255, 255 },
			border     = { 255, 255, 255 },
		},
		inactive = {
			background = {   0,   0,   0 },
			text       = { 255, 255, 255 },
			border     = { 200, 200, 200 },
		},
		active = {
			background = { 255, 255, 255 },
			text       = {   0,   0,   0 },
			border     = { 235, 235, 235 },
		},
	}
	
	return {
		escape = escape,
		common = common,
		commonstr = commonstr,
		hsv_to_rgb = hsv_to_rgb,
		appearance = appearance,
	}
	
end

require_preload__["tptmp.client.config"] = function()

	local common_config = require("tptmp.common.config")
	
	local versionstr = "v2.0.28"
	
	local config = {
		-- ***********************************************************************
		-- *** The following options are purely cosmetic and should be         ***
		-- *** customised in accordance with your taste.                       ***
		-- ***********************************************************************
	
		-- * Version string to display in the window title.
		versionstr = versionstr,
	
		-- * Amount of incoming messages to remember, counted from the
		--   last one received.
		backlog_size = 1000,
	
		-- * Amount of outgoing messages to remember, counted from the
		--   last one sent.
		history_size = 1000,
	
		-- * Default window width. Overridden by the value loaded from the manager
		--   backend, if any.
		default_width = 230,
	
		-- * Default window height. Similar to default_width.
		default_height = 155,
	
		-- * Default window background alpha. Similar to default_width.
		default_alpha = 150,
	
		-- * Minimum window width.
		min_width = 160,
	
		-- * Minimum window height.
		min_height = 107,
	
		-- * Amount of time in seconds that elapses between a notification bubble
		--   appearing and settling in its final position.
		notif_fly_time = 0.1,
	
		-- * Distance in pixels between the position where a notification appears
		--   and the position where it settles.
		notif_fly_distance = 3,
	
		-- * Amount of time in seconds that elapses between a message arriving and
		--   it beginning to fade out if the window is floating.
		floating_linger_time = 3,
	
		-- * Amount of time in seconds that elapses between a message beginning to
		--   fade out and disappearing completely if the window is floating.
		floating_fade_time = 1,
	
		-- * Path to tptmp.client.manager.null configuration file relative to
		--   current directory. Only relevant if the null manager is active.
		null_manager_path = "tptmpsettings.txt",
	
	
		-- ***********************************************************************
		-- *** The following options should only be changed if you know what   ***
		-- *** you are doing. This usually involves consulting with the        ***
		-- *** developers. Otherwise, these are sane values you should trust.  ***
		-- ***********************************************************************
	
		-- * Specifies whether connections made without specifying the port number
		--   should be encrypted. Default should match the common setting.
		default_secure = common_config.secure,
	
		-- * Size of the buffer passed to the recv system call. Bigger values
		--   consume more memory, smaller ones incur larger system call overhead.
		read_size = 0x1000000,
	
		-- * Receive queue limit. Specifies the maximum amount of data the server
		--   is allowed to have sent but which the client has not yet had time to
		--   process. The connection is closed if the size of the receive queue
		--   exceeds this limit.
		recvq_limit = 0x200000,
	
		-- * Send queue limit. Specifies the maximum amount of data the server
		--   is allowed to have not yet processed but which the client has already
		--   queued. The connection is closed if the size of the send queue exceeds
		--   this limit.
		sendq_limit = 0x2000000,
	
		-- * Maximum amount of time in seconds after which the connection attempt
		--   should be deemed a failure, unless it succeeds.
		connect_timeout = 15,
	
		-- * Amount of time in seconds between pings being sent to the server.
		--   Should be half of the ping_timeout option on the server side or less.
		ping_interval = 60,
	
		-- * Amount of time in seconds the connection is allowed to be maintained
		--   without the server sending a ping. Should be twice the ping_interval
		--   option on the server side or more.
		ping_timeout = 120,
	
		-- * Amount of time in seconds that elapses between a non-graceful
		--   connection closure (anything that isn't the client willingly
		--   disconnecting or the server explicitly dropping the client) and an
		--   attempt to establish a new connection.
		reconnect_later_timeout = 2,
	
		-- * Path to the temporary stamp created when syncing.
		stamp_temp = ".tptmp.stm",
	
		-- * Pattern used to match word characters by the textbox. Used by cursor
		--   control, mostly Ctrl+Left and Ctrl+Right and related shortcuts.
		word_pattern = "^[A-Za-z0-9-_\128-\255]+$",
	
		-- * Pattern used to match whitespace characters by the textbox. Similar to
		--   word_pattern.
		whitespace_pattern = "^ $",
	
		-- * Namespace for settings stored in the manager backend.
		manager_namespace = "tptmp",
	
		-- * Grace period in milliseconds after which another client is deemed to
		--   not have FPS synchronization enabled.
		fps_sync_timeout = 10000,
	
		-- * Interval to plan ahead in milliseconds, after which local number of
		--   frames simulated should more or less match the number of frames
		--   everyone else with FPS synchronization enabled has simulated.
		fps_sync_plan_ahead_by = 3000,
	
		-- * Coefficient of linear interpolation between the current target FPS and
		--   that of the slowest client in the room with FPS synchronization
		--   enabled used when slowing down to match the number of frames simulated
		--   by this client. 0 means no slowing down at all, 1 means slowing down
		--   to the framerate the other client seems to be running at.
		fps_sync_homing_factor = 0.5,
	
	
		-- ***********************************************************************
		-- *** The following options should be changed in                      ***
		-- *** tptmp/common/config.lua instead. Since these options should     ***
		-- *** align with the equivalent options on the server side, you       ***
		-- *** will most likely have to run your own version of the server     ***
		-- *** if you intend to change these.                                  ***
		-- ***********************************************************************
	
		-- * Host to connect to by default.
		default_host = common_config.host,
	
		-- * Port to connect to by default.
		default_port = common_config.port,
	
		-- * Protocol version.
		version = common_config.version,
	
		-- * Client-to-server message size limit.
		message_size = common_config.message_size,
	
		-- * Client-to-server message rate limit.
		message_interval = common_config.message_interval,
	
		-- * Authentication backend URL. Only relevant if auth = true on the
		--   server side.
		auth_backend = common_config.auth_backend,
	
		-- * Authentication backend timeout in seconds. Only relevant if
		---  auth = true on the server side.
		auth_backend_timeout = common_config.auth_backend_timeout,
	}
	config.default_x = math.floor((sim.XRES - config.default_width) / 2)
	config.default_y = math.floor((sim.YRES - config.default_height) / 2)
	
	return config
	
end

require_preload__["tptmp.client.format"] = function()

	local colours = require("tptmp.client.colours")
	local util    = require("tptmp.client.util")
	
	local function nick(unformatted, seed)
		return colours.escape(colours.hsv_to_rgb(util.fnv1a32(seed .. unformatted .. "bagels") / 0x100000000, 0.5, 1)) .. unformatted
	end
	
	local names = {
		[   "null" ] = "lobby",
		[  "guest" ] = "guest lobby",
		[ "kicked" ] = "a dark alley",
	}
	
	local function room(unformatted)
		local name = names[unformatted]
		return name and (colours.commonstr.lobby .. name) or (colours.commonstr.room .. unformatted)
	end
	
	local function troom(unformatted)
		local name = names[unformatted]
		return name and (colours.commonstr.lobby .. name) or ("room " .. colours.commonstr.room .. unformatted)
	end
	
	return {
		nick = nick,
		room = room,
		troom = troom,
	}
	
end

require_preload__["tptmp.client.localcmd"] = function()

	local config         = require("tptmp.client.config")
	local format         = require("tptmp.client.format")
	local manager        = require("tptmp.client.manager")
	local command_parser = require("tptmp.common.command_parser")
	local colours        = require("tptmp.client.colours")
	
	local localcmd_i = {}
	local localcmd_m = { __index = localcmd_i }
	
	local function parse_fps_sync(fps_sync)
		fps_sync = fps_sync and tonumber(fps_sync) or false
		fps_sync = fps_sync and math.floor(fps_sync) or false
		fps_sync = fps_sync and fps_sync >= 2 and fps_sync or false
		return fps_sync
	end
	
	local cmdp = command_parser.new({
		commands = {
			help = {
				role = "help",
				help = "/help <command>: displays command usage and notes (try /help list)",
			},
			list = {
				role = "list",
				help = "/list, no arguments: lists available commands",
			},
			size = {
				func = function(localcmd, message, words, offsets)
					local width = tonumber(words[2] and #words[2] > 0 and #words[2] <= 7 and not words[2]:find("[^0-9]") and words[2] or "")
					local height = tonumber(words[3] and #words[3] > 0 and #words[3] <= 7 and not words[3]:find("[^0-9]") and words[3] or "")
					if not width or not height then
						return false
					else
						localcmd.window_:set_size(width, height)
					end
					return true
				end,
				help = "/size <width> <height>: sets the size of the chat window",
			},
			sync = {
				func = function(localcmd, message, words, offsets)
					local cli = localcmd.client_func_()
					if cli then
						cli:send_sync()
						if localcmd.window_status_func_() ~= "hidden" then
							localcmd.window_:backlog_push_neutral("* Simulation synchronized")
						end
					else
						if localcmd.window_status_func_() ~= "hidden" then
							localcmd.window_:backlog_push_error("Not connected, cannot sync")
						end
					end
					return true
				end,
				help = "/sync, no arguments: synchronizes your simulation with everyone else's in the room; shortcut is Alt+S",
			},
			S = {
				alias = "sync",
			},
			fpssync = {
				func = function(localcmd, message, words, offsets)
					local cli = localcmd.client_func_()
					if words[2] == "on" then
						if not localcmd.fps_sync_ then
							localcmd.fps_sync_ = tpt.setfpscap()
						end
						if words[3] then
							local fps_sync = parse_fps_sync(words[3])
							if not fps_sync then
								return false
							end
							localcmd.fps_sync_ = fps_sync
						end
						manager.set("fpsSync", tostring(localcmd.fps_sync_))
						if cli then
							cli:fps_sync(localcmd.fps_sync_)
						end
						localcmd.window_:backlog_push_neutral("* FPS synchronization enabled")
						return true
					elseif words[2] == "check" or not words[2] then
						if localcmd.fps_sync_ then
							local cli = localcmd.client_func_()
							if cli then
								cli:push_fpssync()
							else
								localcmd.window_:backlog_push_fpssync(true)
							end
						else
							localcmd.window_:backlog_push_fpssync(false)
						end
						return true
					elseif words[2] == "off" then
						localcmd.fps_sync_ = false
						manager.set("fpsSync", tostring(localcmd.fps_sync_))
						if cli then
							cli:fps_sync(localcmd.fps_sync_)
						end
						localcmd.window_:backlog_push_neutral("* FPS synchronization disabled")
						return true
					end
					return false
				end,
				help = "/fpssync on [targetfps]\\check\\off: enables or disables FPS synchronization with those in the room who also have it enabled; targetfps defaults to the current FPS cap",
			},
			floating = {
				func = function(localcmd, message, words, offsets)
					local cli = localcmd.client_func_()
					if words[2] == "on" then
						localcmd.floating_ = true
						localcmd.window_set_floating_func_(true)
						manager.set("floating", "on")
						localcmd.window_:backlog_push_neutral("* Floating mode enabled")
						return true
					elseif words[2] == "check" or not words[2] then
						if localcmd.floating_ then
							localcmd.window_:backlog_push_neutral("* Floating mode currenly enabled")
						else
							localcmd.window_:backlog_push_neutral("* Floating mode currenly disabled")
						end
						return true
					elseif words[2] == "off" then
						localcmd.floating_ = false
						localcmd.window_set_floating_func_(false)
						manager.set("floating", "false")
						localcmd.window_:backlog_push_neutral("* Floating mode disabled")
						return true
					end
					return false
				end,
				help = "/floating on\\check\\off: enables or disables floating mode: messages are drawn even when the window is hidden; chat shortcut is T",
			},
			connect = {
				macro = function(localcmd, message, words, offsets)
					return { "connectroom", "", unpack(words, 2) }
				end,
				help = "/connect [host[:[+]port]]: connects the default TPTMP server or the specified one, add + to connect securely",
			},
			C = {
				alias = "connect",
			},
			reconnect = {
				macro = function(localcmd, message, words, offsets)
					if not localcmd.reconnect_ then
						localcmd.window_:backlog_push_error("No successful connection on record, cannot reconnect")
						return {}
					end
					return { "connectroom", localcmd.reconnect_.room, localcmd.reconnect_.host .. ":" .. localcmd.reconnect_.secr .. localcmd.reconnect_.port }
				end,
				help = "/reconnect, no arguments: connects back to the most recently visited server",
			},
			connectroom = {
				func = function(localcmd, message, words, offsets)
					local cli = localcmd.client_func_()
					if not words[2] then
						return false
					elseif cli then
						localcmd.window_:backlog_push_error("Already connected")
					else
						local host = words[3] or config.default_host
						local host_without_port, port = host:match("^(.+):(%+?[^:]+)$")
						host = host_without_port or host
						local secure
						if port then
							secure = port:find("%+") and true
						else
							secure = config.default_secure
						end
						local new_cli = localcmd.new_client_func_({
							host = host,
							port = port and tonumber(port:gsub("[^0-9]", ""):sub(1, 5)) or config.default_port,
							secure = secure,
							initial_room = words[2],
							localcmd = localcmd,
						})
						new_cli:nick_colour_seed(localcmd.nick_colour_seed_)
						new_cli:fps_sync(localcmd.fps_sync_)
						new_cli:start()
					end
					return true
				end,
				help = "/connectroom <room> [host[:[+]port]]: same as /connect, but skips the lobby and joins the specified room",
			},
			CR = {
				alias = "connectroom",
			},
			disconnect = {
				func = function(localcmd, message, words, offsets)
					local cli = localcmd.client_func_()
					if cli then
						localcmd.kill_client_func_()
					else
						localcmd.window_:backlog_push_error("Not connected, cannot disconnect")
					end
					return true
				end,
				help = "/disconnect, no arguments: disconnects from the current server",
			},
			D = {
				alias = "disconnect",
			},
			quit = {
				alias = "disconnect",
			},
			Q = {
				alias = "disconnect",
			},
			names = {
				func = function(localcmd, message, words, offsets)
					local cli = localcmd.client_func_()
					if cli then
						cli:push_names("Currently in ")
					else
						localcmd.window_:backlog_push_error("Not connected, cannot list users")
					end
					return true
				end,
				help = "/names, no arguments: tells you which room you are in and lists users present",
			},
			clear = {
				func = function(localcmd, message, words, offsets)
					localcmd.window_:backlog_reset()
					localcmd.window_:backlog_push_neutral("* Backlog cleared")
					return true
				end,
				help = "/clear, no arguments: clears the chat window",
			},
			hide = {
				func = function(localcmd, message, words, offsets)
					localcmd.window_.hide_window_func_()
					return true
				end,
				help = "/hide, no arguments: hides the chat window; shortcut is Shift+Escape, this toggles window visibility (different from Escape without Shift, which defocuses the input box, and its counterpart Enter, which focuses it)",
			},
			me = {
				func = function(localcmd, message, words, offsets)
					local cli = localcmd.client_func_()
					if not words[2] then
						return false
					elseif cli then
						local msg = message:sub(offsets[2])
						localcmd.window_:backlog_push_say3rd(cli:formatted_nick(), msg)
						cli:send_say3rd(msg)
					else
						localcmd.window_:backlog_push_error("Not connected, message not sent")
					end
					return true
				end,
				help = "/me <message>: says something in third person",
			},
			ncseed = {
				func = function(localcmd, message, words, offsets)
					localcmd.nick_colour_seed_ = words[2] or tostring(math.random())
					manager.set("nickColourSeed", tostring(localcmd.nick_colour_seed_))
					local cli = localcmd.client_func_()
					localcmd.window_:nick_colour_seed(localcmd.nick_colour_seed_)
					if cli then
						cli:nick_colour_seed(localcmd.nick_colour_seed_)
					end
					return true
				end,
				help = "/ncseed [seed]: set nick colour seed, randomize it if not specified, default is 0",
			},
		},
		respond = function(localcmd, message)
			localcmd.window_:backlog_push_neutral(message)
		end,
		cmd_fallback = function(localcmd, message)
			local cli = localcmd.client_func_()
			if cli then
				cli:send_say("/" .. message)
				return true
			end
			return false
		end,
		help_fallback = function(localcmd, cmdstr)
			local cli = localcmd.client_func_()
			if cli then
				cli:send_say("/shelp " .. cmdstr)
				return true
			end
			return false
		end,
		list_extra = function(localcmd, cmdstr)
			local cli = localcmd.client_func_()
			if cli then
				cli:send_say("/slist")
			else
				localcmd.window_:backlog_push_neutral("* Server commands are not currently available (connect to a server first)")
			end
		end,
		help_format = colours.commonstr.neutral .. "* %s",
		alias_format = colours.commonstr.neutral .. "* /%s is an alias for /%s",
		list_format = colours.commonstr.neutral .. "* Client commands: %s",
		unknown_format = colours.commonstr.error .. "* No such command, try /list (maybe it is server-only, connect and try again)",
	})
	
	function localcmd_i:parse(str)
		if str:find("^/") and not str:find("^//") then
			cmdp:parse(self, str:sub(2))
			return true
		end
	end
	
	function localcmd_i:reconnect_commit(reconnect)
		self.reconnect_ = {
			room = reconnect.room,
			host = reconnect.host,
			port = tostring(reconnect.port),
			secr = reconnect.secure and "+" or "",
		}
		manager.set("reconnectRoom", self.reconnect_.room)
		manager.set("reconnectHost", self.reconnect_.host)
		manager.set("reconnectPort", self.reconnect_.port)
		manager.set("reconnectSecure", self.reconnect_.secr)
	end
	
	local function new(params)
		local reconnect = {
			room = manager.get("reconnectRoom", ""),
			host = manager.get("reconnectHost", ""),
			port = manager.get("reconnectPort", ""),
			secr = manager.get("reconnectSecure", ""),
		}
		if #reconnect.room == 0 or #reconnect.host == 0 or #reconnect.port == 0 then
			reconnect = nil
		end
		local fps_sync = parse_fps_sync(manager.get("fpsSync", "0"))
		local floating = manager.get("floating", "on") == "on"
		local cmd = setmetatable({
			fps_sync_ = fps_sync,
			floating_ = floating,
			reconnect_ = reconnect,
			window_status_func_ = params.window_status_func,
			window_set_floating_func_ = params.window_set_floating_func,
			client_func_ = params.client_func,
			new_client_func_ = params.new_client_func,
			kill_client_func_ = params.kill_client_func,
			nick_colour_seed_ = manager.get("nickColourSeed", "0"),
			window_ = params.window,
		}, localcmd_m)
		cmd.window_:nick_colour_seed(cmd.nick_colour_seed_)
		cmd.window_set_floating_func_(floating)
		return cmd
	end
	
	return {
		new = new,
	}
	
end

require_preload__["tptmp.client.manager"] = function()

	local jacobs = require("tptmp.client.manager.jacobs")
	local null   = require("tptmp.client.manager.null")
	
	if rawget(_G, "MANAGER") then
		return jacobs
	else
		return null
	end
	
end

require_preload__["tptmp.client.manager.jacobs"] = function()

	local config = require("tptmp.client.config")
	
	local MANAGER = rawget(_G, "MANAGER")
	
	local function get(key, default)
		local value = MANAGER.getsetting(config.manager_namespace, key)
		return type(value) == "string" and value or default
	end
	
	local function set(key, value)
		MANAGER.savesetting(config.manager_namespace, key, value)
	end
	
	local function hidden()
		return MANAGER.hidden
	end
	
	local function print(msg)
		return MANAGER.print(msg)
	end
	
	return {
		hidden = hidden,
		get = get,
		set = set,
		print = print,
		brand = "jacobs",
		minimize_conflict = true,
		side_button_conflict = true,
	}
	
end

require_preload__["tptmp.client.manager.null"] = function()

	local config = require("tptmp.client.config")
	
	local data
	
	local function load_data()
		if data then
			return
		end
		data = {}
		local handle = io.open(config.null_manager_path, "r")
		if not handle then
			return
		end
		for line in handle:read("*a"):gmatch("[^\r\n]+") do
			local key, value = line:match("^([^=]+)=(.*)$")
			if key then
				data[key] = value
			end
		end
		handle:close()
	end
	
	local function save_data()
		local handle = io.open(config.null_manager_path, "w")
		if not handle then
			return
		end
		local collect = {}
		for key, value in pairs(data) do
			table.insert(collect, tostring(key))
			table.insert(collect, "=")
			table.insert(collect, tostring(value))
			table.insert(collect, "\n")
		end
		handle:write(table.concat(collect))
		handle:close()
	end
	
	local function get(key, default)
		load_data()
		return data[key] or default
	end
	
	local function set(key, value)
		data[key] = value
		save_data()
	end
	
	local function print(msg)
		print(msg)
	end
	
	return {
		get = get,
		set = set,
		print = print,
		brand = "null",
	}
	
end

require_preload__["tptmp.client.profile"] = function()

	local vanilla = require("tptmp.client.profile.vanilla")
	local jacobs  = require("tptmp.client.profile.jacobs")
	
	if tpt.version.jacob1s_mod then
		return jacobs
	else
		return vanilla
	end
	
end

require_preload__["tptmp.client.profile.jacobs"] = function()

	local vanilla = require("tptmp.client.profile.vanilla")
	local config  = require("tptmp.client.config")
	
	local profile_i = {}
	local profile_m = { __index = profile_i }
	
	for key, value in pairs(vanilla.profile_i) do
		profile_i[key] = value
	end
	
	function profile_i:handle_mousedown(px, py, button)
		if self.client and (tpt.tab_menu() == 1 or self.kmod_c_) and px >= sim.XRES and py < 116 and not self.kmod_a_ then
			self.log_event_func_(config.print_prefix .. "The tab menu is disabled because it does not sync (press the Alt key to override)")
			return true
		end
		return vanilla.profile_i.handle_mousedown(self, px, py, button)
	end
	
	local function new(params)
		local prof = vanilla.new(params)
		prof.buttons_.clear = { x = gfx.WIDTH - 148, y = gfx.HEIGHT - 16, w = 17, h = 15 }
		setmetatable(prof, profile_m)
		return prof
	end
	
	return {
		new = new,
		brand = "jacobs",
	}
	
end

require_preload__["tptmp.client.profile.vanilla"] = function()

	local util   = require("tptmp.client.util")
	local config = require("tptmp.client.config")
	local sdl    = require("tptmp.client.sdl")
	
	local profile_i = {}
	local profile_m = { __index = profile_i }
	
	local index_to_lrax = {
		[ 0 ] = "tool_l_",
		[ 1 ] = "tool_r_",
		[ 2 ] = "tool_a_",
		[ 3 ] = "tool_x_",
	}
	local index_to_lraxid = {
		[ 0 ] = "tool_lid_",
		[ 1 ] = "tool_rid_",
		[ 2 ] = "tool_aid_",
		[ 3 ] = "tool_xid_",
	}
	local toolwarn_tools = {
		[ "DEFAULT_UI_PROPERTY" ] = "prop",
		[ "DEFAULT_TOOL_MIX"    ] = "mix",
		[ "DEFAULT_PT_LIGH"     ] = "ligh",
		[ "DEFAULT_PT_STKM"     ] = "stkm",
		[ "DEFAULT_PT_STKM2"    ] = "stkm",
		[ "DEFAULT_PT_SPAWN"    ] = "stkm",
		[ "DEFAULT_PT_SPAWN2"   ] = "stkm",
		[ "DEFAULT_PT_FIGH"     ] = "stkm",
		[ "UNKNOWN"             ] = "unknown",
	}
	local toolwarn_messages = {
		prop      =                      "The PROP tool does not sync, you will have to use /sync",
		mix       =                       "The MIX tool does not sync, you will have to use /sync",
		ligh      =                               "LIGH does not sync, you will have to use /sync",
		stkm      =                             "Stickmen do not sync, you will have to use /sync",
		cbrush    =                       "Custom brushes do not sync, you will have to use /sync",
		ipcirc    =               "The old circle brush does not sync, you will have to use /sync",
		unknown   =  "This custom element is not supported, please avoid using it while connected",
		cgol      = "This custom GOL type is not supported, please avoid using it while connected",
		cgolcolor =  "Custom GOL currently syncs without colours, use /sync to get colours across",
	}
	
	local BRUSH_COUNT = 3
	local MOUSEUP_REASON_MOUSEUP = 0
	local MOUSEUP_REASON_BLUR    = 1
	local MAX_SIGNS = 0
	while sim.signs[MAX_SIGNS + 1] do
		MAX_SIGNS = MAX_SIGNS + 1
	end
	
	local function rulestring_bits(str)
		local bits = 0
		for i = 1, #str do
			bits = bit.bor(bits, bit.lshift(1, str:byte(i) - 48))
		end
		return bits
	end
	
	local function get_custgolinfo(identifier)
		-- * TODO[api]: add an api for this to tpt
		local pref = io.open("powder.pref")
		if not pref then
			return
		end
		local pref_data = pref:read("*a")
		pref:close()
		local types = pref_data:match([=["Types"%s*:%s*%[([^%]]+)%]]=])
		if not types then
			return
		end
		for name, ruleset, primary, secondary in types:gmatch([["(%S+)%s+(%S+)%s+(%S+)%s+(%S+)"]]) do
			if "DEFAULT_PT_LIFECUST_" .. name == identifier then
				local begin, stay, states = ruleset:match("^B([1-8]+)/S([0-8]+)/([0-9]+)$")
				if not begin then
					begin, stay = ruleset:match("^B([1-8]+)/S([0-8]+)$")
					states = "2"
				end
				states = tonumber(states)
				states = states >= 2 and states <= 17 and states
				ruleset = begin and stay and states and bit.bor(bit.lshift(rulestring_bits(begin), 8), rulestring_bits(stay), bit.lshift(states - 2, 17))
				primary = tonumber(primary)
				secondary = tonumber(secondary)
				if ruleset and primary and secondary then
					return ruleset, primary, secondary
				end
				break
			end
		end
	end
	
	local function get_sign_data()
		local sign_data = {}
		for i = 1, MAX_SIGNS do
			local text = sim.signs[i].text
			if text then
				sign_data[i] = {
					tx = text,
					ju = sim.signs[i].justification,
					px = sim.signs[i].x,
					py = sim.signs[i].y,
				}
			end
		end
		return sign_data
	end
	
	local function perfect_circle()
		return sim.brush(1, 1, 1, 1, 0)() == 0
	end
	
	local props = {}
	for key, value in pairs(sim) do
		if key:find("^FIELD_") and key ~= "FIELD_TYPE" then
			table.insert(props, value)
		end
	end
	
	local function in_zoom_window(x, y)
		local ax, ay = sim.adjustCoords(x, y)
		return ren.zoomEnabled() and (ax ~= x or ay ~= y)
	end
	
	function profile_i:report_loadonline_(id, hist)
		if self.client_ then
			self.client_:send_loadonline(id, hist)
		end
	end
	
	function profile_i:report_pos_()
		if self.client_ then
			self.client_:send_mousepos(self.pos_x_, self.pos_y_)
		end
	end
	
	function profile_i:report_size_()
		if self.client_ then
			self.client_:send_brushsize(self.size_x_, self.size_y_)
		end
	end
	
	function profile_i:report_zoom_()
		if self.client_ then
			if self.zenabled_ then
				self.client_:send_zoomstart(self.zcx_, self.zcy_, self.zsize_)
			else
				self.client_:send_zoomend()
			end
		end
	end
	
	function profile_i:report_bmode_()
		if self.client_ then
			self.client_:send_brushmode(self.bmode_)
		end
	end
	
	function profile_i:report_shape_()
		if self.client_ then
			self.client_:send_brushshape(self.shape_ < BRUSH_COUNT and self.shape_ or 0)
		end
	end
	
	function profile_i:report_sparksign_(x, y)
		if self.client_ then
			self.client_:send_sparksign(x, y)
		end
	end
	
	function profile_i:report_flood_(i, x, y)
		if self.client_ then
			self.client_:send_flood(i, x, y)
		end
	end
	
	function profile_i:report_lineend_(x, y)
		self.lss_i_ = nil
		if self.client_ then
			self.client_:send_lineend(x, y)
		end
	end
	
	function profile_i:report_rectend_(x, y)
		self.rss_i_ = nil
		if self.client_ then
			self.client_:send_rectend(x, y)
		end
	end
	
	function profile_i:sync_linestart_(i, x, y)
		if self.client_ and self.lss_i_ then
			self.client_:send_linestart(self.lss_i_, self.lss_x_, self.lss_y_)
		end
	end
	
	function profile_i:report_linestart_(i, x, y)
		self.lss_i_ = i
		self.lss_x_ = x
		self.lss_y_ = y
		if self.client_ then
			self.client_:send_linestart(i, x, y)
		end
	end
	
	function profile_i:sync_rectstart_(i, x, y)
		if self.client_ and self.rss_i_ then
			self.client_:send_rectstart(self.rss_i_, self.rss_x_, self.rss_y_)
		end
	end
	
	function profile_i:report_rectstart_(i, x, y)
		self.rss_i_ = i
		self.rss_x_ = x
		self.rss_y_ = y
		if self.client_ then
			self.client_:send_rectstart(i, x, y)
		end
	end
	
	function profile_i:sync_pointsstart_()
		if self.client_ and self.pts_i_ then
			self.client_:send_pointsstart(self.pts_i_, self.pts_x_, self.pts_y_)
		end
	end
	
	function profile_i:report_pointsstart_(i, x, y)
		self.pts_i_ = i
		self.pts_x_ = x
		self.pts_y_ = y
		if self.client_ then
			self.client_:send_pointsstart(i, x, y)
		end
	end
	
	function profile_i:report_pointscont_(x, y, done)
		if self.client_ then
			self.client_:send_pointscont(x, y)
		end
		self.pts_x_ = x
		self.pts_y_ = y
		if done then
			self.pts_i_ = nil
		end
	end
	
	function profile_i:report_kmod_()
		if self.client_ then
			self.client_:send_keybdmod(self.kmod_c_, self.kmod_s_, self.kmod_a_)
		end
	end
	
	function profile_i:report_framestep_()
		if self.client_ then
			self.client_:send_stepsim()
		end
	end
	
	function profile_i:report_airinvert_()
		if self.client_ then
			self.client_:send_airinv()
		end
	end
	
	function profile_i:report_reset_spark_()
		if self.client_ then
			self.client_:send_sparkclear()
		end
	end
	
	function profile_i:report_reset_air_()
		if self.client_ then
			self.client_:send_airclear()
		end
	end
	
	function profile_i:report_reset_airtemp_()
		if self.client_ then
			self.client_:send_heatclear()
		end
	end
	
	function profile_i:report_clearrect_(x, y, w, h)
		if self.client_ then
			self.client_:send_clearrect(x, y, w, h)
		end
	end
	
	function profile_i:report_clearsim_()
		if self.client_ then
			self.client_:send_clearsim()
		end
	end
	
	function profile_i:report_reloadsim_()
		if self.client_ then
			self.client_:send_reloadsim()
		end
	end
	
	function profile_i:simstate_sync()
		if self.client_ then
			self.client_:send_simstate(self.ss_p_, self.ss_h_, self.ss_u_, self.ss_n_, self.ss_w_, self.ss_g_, self.ss_a_, self.ss_e_, self.ss_y_, self.ss_t_, self.ss_r_, self.ss_s_)
		end
	end
	
	function profile_i:report_tool_(index)
		if self.client_ then
			self.client_:send_selecttool(index, self[index_to_lrax[index]])
			local identifier = self[index_to_lraxid[index]]
			if identifier:find("^DEFAULT_PT_LIFECUST_") then
				local ruleset, primary, secondary = get_custgolinfo(identifier)
				if ruleset then
					self.client_:send_custgolinfo(ruleset, primary, secondary)
					-- * TODO[api]: add an api for setting gol colour
					self.display_toolwarn_["cgolcolor"] = true
				else
					self.display_toolwarn_["cgol"] = true
				end
			end
		end
	end
	
	function profile_i:report_deco_()
		if self.client_ then
			self.client_:send_brushdeco(self.deco_)
		end
	end
	
	function profile_i:sync_placestatus_()
		if self.client_ and self.pes_k_ ~= 0 then
			self.client_:send_placestatus(self.pes_k_, self.pes_w_, self.pes_h_)
		end
	end
	
	function profile_i:report_placestatus_(k, w, h)
		self.pes_k_ = k
		self.pes_w_ = w
		self.pes_h_ = h
		if self.client_ then
			self.client_:send_placestatus(k, w, h)
		end
	end
	
	function profile_i:sync_selectstatus_()
		if self.client_ and self.sts_k_ ~= 0 then
			self.client_:send_selectstatus(self.sts_k_, self.sts_x_, self.sts_y_)
		end
	end
	
	function profile_i:report_selectstatus_(k, x, y)
		self.sts_k_ = k
		self.sts_x_ = x
		self.sts_y_ = y
		if self.client_ then
			self.client_:send_selectstatus(k, x, y)
		end
	end
	
	function profile_i:report_pastestamp_(x, y, w, h)
		if self.client_ then
			self.client_:send_pastestamp(x, y, w, h)
		end
	end
	
	function profile_i:report_canceldraw_()
		if self.client_ then
			self.client_:send_canceldraw()
		end
	end
	
	function profile_i:get_stamp_size_()
		local stampsdef = io.open("stamps/stamps.def", "rb")
		if not stampsdef then
			return
		end
		local name = stampsdef:read(10)
		stampsdef:close()
		if type(name) ~= "string" or #name ~= 10 then
			return
		end
		local stamp = io.open("stamps/" .. name .. ".stm", "rb")
		if not stamp then
			return
		end
		local header = stamp:read(12)
		stamp:close()
		if type(header) ~= "string" or #header ~= 12 then
			return
		end
		local bw, bh = header:byte(7, 8) -- * Works for OPS and PSv too.
		return bw * 4, bh * 4
	end
	
	function profile_i:user_sync()
		self:report_size_()
		self:report_tool_(0)
		self:report_tool_(1)
		self:report_tool_(2)
		self:report_tool_(3)
		self:report_deco_()
		self:report_bmode_()
		self:report_shape_()
		self:report_kmod_()
		self:report_pos_()
		self:sync_pointsstart_()
		self:sync_placestatus_()
		self:sync_selectstatus_()
		self:sync_linestart_()
		self:sync_rectstart_()
		self:report_zoom_()
	end
	
	function profile_i:post_event_check_()
		if self.placesave_postmsg_ then
			local partcount = self.placesave_postmsg_.partcount
			if self.debug_ then
				self.debug_("fallback placesave detection", sim.NUM_PARTS, partcount)
			end
			if partcount and (partcount ~= sim.NUM_PARTS or sim.NUM_PARTS == sim.XRES * sim.YRES) and self.registered_func_() then
				-- * TODO[api]: get rid of all of this nonsense once redo-ui lands
				if self.client_ then
					self.client_:send_sync()
				end
				if self.debug_ then
					self.debug_("failed to determine paste area while connected, syncing everything")
				end
			end
			self.placesave_postmsg_ = nil
		end
		if self.placesave_size_ then
			local x1, y1, x2, y2 = self:end_placesave_size_()
			if x1 then
				if self.debug_ then
					self.debug_("placesave size determined to be", x1, y1, x2, y2)
				end
				local x, y, w, h = util.corners_to_rect(x1, y1, x2, y2)
				self.simstate_invalid_ = true
				if self.placesave_open_ then
					local id, hist = util.get_save_id()
					self.set_id_func_(id, hist)
					if id then
						self:report_loadonline_(id, hist)
					else
						self:report_pastestamp_(x, y, w, h)
					end
				elseif self.placesave_reload_ then
					if not self.get_id_func_() then
						self:report_pastestamp_(x, y, w, h)
					end
					self:report_reloadsim_()
				elseif self.placesave_clear_ then
					self.set_id_func_(nil, nil)
					self:report_clearsim_()
				else
					self:report_pastestamp_(x, y, w, h)
				end
			else
				if self.debug_ then
					self.debug_("placesave size not determined")
				end
			end
			self.placesave_open_ = nil
			self.placesave_reload_ = nil
			self.placesave_clear_ = nil
		end
		if self.zoom_invalid_ then
			self.zoom_invalid_ = nil
			self:update_zoom_()
		end
		if self.simstate_invalid_ then
			self.simstate_invalid_ = nil
			self:check_simstate()
		end
		if self.bmode_invalid_ then
			self.bmode_invalid_ = nil
			self:update_bmode_()
		end
		self:update_size_()
		self:update_shape_()
		self:update_tools_()
		self:update_deco_()
	end
	
	function profile_i:sample_simstate()
		local ss_p = tpt.set_pause()
		local ss_h = tpt.heat()
		local ss_u = tpt.ambient_heat()
		local ss_n = tpt.newtonian_gravity()
		local ss_w = sim.waterEqualisation()
		local ss_g = sim.gravityMode()
		local ss_a = sim.airMode()
		local ss_e = sim.edgeMode()
		local ss_y = sim.prettyPowders()
		local ss_t = util.ambient_air_temp()
		local ss_r, ss_s = util.custom_gravity()
		if self.ss_p_ ~= ss_p or
		   self.ss_h_ ~= ss_h or
		   self.ss_u_ ~= ss_u or
		   self.ss_n_ ~= ss_n or
		   self.ss_w_ ~= ss_w or
		   self.ss_g_ ~= ss_g or
		   self.ss_a_ ~= ss_a or
		   self.ss_e_ ~= ss_e or
		   self.ss_y_ ~= ss_y or
		   self.ss_t_ ~= ss_t or
		   self.ss_r_ ~= ss_r or
		   self.ss_s_ ~= ss_s then
			self.ss_p_ = ss_p
			self.ss_h_ = ss_h
			self.ss_u_ = ss_u
			self.ss_n_ = ss_n
			self.ss_w_ = ss_w
			self.ss_g_ = ss_g
			self.ss_a_ = ss_a
			self.ss_e_ = ss_e
			self.ss_y_ = ss_y
			self.ss_t_ = ss_t
			self.ss_r_ = ss_r
			self.ss_s_ = ss_s
			return true
		end
		return false
	end
	
	function profile_i:check_signs(old_data)
		local new_data = get_sign_data()
		local bw = sim.XRES / 4
		local to_send = {}
		local function key(x, y)
			return math.floor(x / 4) + math.floor(y / 4) * bw
		end
		for i = 1, MAX_SIGNS do
			if old_data[i] and new_data[i] then
				if old_data[i].ju ~= new_data[i].ju or
				   old_data[i].tx ~= new_data[i].tx or
				   old_data[i].px ~= new_data[i].px or
				   old_data[i].py ~= new_data[i].py then
					to_send[key(old_data[i].px, old_data[i].py)] = true
					to_send[key(new_data[i].px, new_data[i].py)] = true
				end
			elseif old_data[i] then
				to_send[key(old_data[i].px, old_data[i].py)] = true
			elseif new_data[i] then
				to_send[key(new_data[i].px, new_data[i].py)] = true
			end
		end
		for k in pairs(to_send) do
			local x, y, w, h = k % bw * 4, math.floor(k / bw) * 4, 4, 4
			self:report_clearrect_(x, y, w, h)
			self:report_pastestamp_(x, y, w, h)
		end
	end
	
	function profile_i:check_simstate()
		if self:sample_simstate() then
			self:simstate_sync()
		end
	end
	
	function profile_i:update_draw_mode_()
		if self.kmod_c_ and self.kmod_s_ then
			if util.xid_class[self[index_to_lrax[self.last_toolslot_]]] == "TOOL" then
				self.draw_mode_ = "points"
			else
				self.draw_mode_ = "flood"
			end
		elseif self.kmod_c_ then
			self.draw_mode_ = "rect"
		elseif self.kmod_s_ then
			self.draw_mode_ = "line"
		else
			self.draw_mode_ = "points"
		end
	end
	
	function profile_i:enable_shift_()
		self.kmod_changed_ = true
		self.kmod_s_ = true
		if not self.dragging_mouse_ or self.select_mode_ ~= "none" then
			self:update_draw_mode_()
		end
	end
	
	function profile_i:enable_ctrl_()
		self.kmod_changed_ = true
		self.kmod_c_ = true
		if not self.dragging_mouse_ or self.select_mode_ ~= "none" then
			self:update_draw_mode_()
		end
	end
	
	function profile_i:enable_alt_()
		self.kmod_changed_ = true
		self.kmod_a_ = true
	end
	
	function profile_i:disable_shift_()
		self.kmod_changed_ = true
		self.kmod_s_ = false
		if not self.dragging_mouse_ or self.select_mode_ ~= "none" then
			self:update_draw_mode_()
		end
	end
	
	function profile_i:disable_ctrl_()
		self.kmod_changed_ = true
		self.kmod_c_ = false
		if not self.dragging_mouse_ or self.select_mode_ ~= "none" then
			self:update_draw_mode_()
		end
	end
	
	function profile_i:disable_alt_()
		self.kmod_changed_ = true
		self.kmod_a_ = false
	end
	
	function profile_i:update_pos_(x, y)
		x, y = sim.adjustCoords(x, y)
		if x < 0         then x = 0            end
		if x >= sim.XRES then x = sim.XRES - 1 end
		if y < 0         then y = 0            end
		if y >= sim.YRES then y = sim.YRES - 1 end
		if self.pos_x_ ~= x or self.pos_y_ ~= y then
			self.pos_x_ = x
			self.pos_y_ = y
			self:report_pos_(self.pos_x_, self.pos_y_)
		end
	end
	
	function profile_i:update_size_()
		local x, y = tpt.brushx, tpt.brushy
		if x < 0   then x = 0   end
		if x > 255 then x = 255 end
		if y < 0   then y = 0   end
		if y > 255 then y = 255 end
		if self.size_x_ ~= x or self.size_y_ ~= y then
			self.size_x_ = x
			self.size_y_ = y
			self:report_size_(self.size_x_, self.size_y_)
		end
	end
	
	function profile_i:update_zoom_()
		local zenabled = ren.zoomEnabled()
		local zcx, zcy, zsize = ren.zoomScope()
		if self.zenabled_ ~= zenabled or self.zcx_ ~= zcx or self.zcy_ ~= zcy or self.zsize_ ~= zsize then
			self.zenabled_ = zenabled
			self.zcx_ = zcx
			self.zcy_ = zcy
			self.zsize_ = zsize
			self:report_zoom_()
		end
	end
	
	function profile_i:update_bmode_()
		local bmode = sim.replaceModeFlags()
		if self.bmode_ ~= bmode then
			self.bmode_ = bmode
			self:report_bmode_()
		end
	end
	
	function profile_i:update_shape_()
		local pcirc = self.perfect_circle_
		if self.perfect_circle_invalid_ then
			pcirc = perfect_circle()
		end
		local shape = tpt.brushID
		if self.shape_ ~= shape or self.perfect_circle_ ~= pcirc then
			local old_cbrush = self.cbrush_
			self.cbrush_ = shape >= BRUSH_COUNT or nil
			if not old_cbrush and self.cbrush_ then
				self.display_toolwarn_["cbrush"] = true
			end
			local old_ipcirc = self.ipcirc_
			self.ipcirc_ = shape == 0 and not pcirc
			if not old_ipcirc and self.ipcirc_ then
				self.display_toolwarn_["ipcirc"] = true
			end
			self.shape_ = shape
			self.perfect_circle_ = pcirc
			self:report_shape_()
		end
	end
	
	function profile_i:update_tools_()
		local tlid = tpt.selectedl
		local trid = tpt.selectedr
		local taid = tpt.selecteda
		local txid = tpt.selectedreplace
		if self.tool_lid_ ~= tlid then
			self.tool_l_ = util.from_tool[tlid] or util.unknown_xid
			self.tool_lid_ = tlid
			self:report_tool_(0)
		end
		if self.tool_rid_ ~= trid then
			self.tool_r_ = util.from_tool[trid] or util.unknown_xid
			self.tool_rid_ = trid
			self:report_tool_(1)
		end
		if self.tool_aid_ ~= taid then
			self.tool_a_ = util.from_tool[taid] or util.unknown_xid
			self.tool_aid_ = taid
			self:report_tool_(2)
		end
		if self.tool_xid_ ~= txid then
			self.tool_x_ = util.from_tool[txid] or util.unknown_xid
			self.tool_xid_ = txid
			self:report_tool_(3)
		end
		local new_tool = util.to_tool[self[index_to_lrax[self.last_toolslot_]]]
		local new_tool_id = self[index_to_lraxid[self.last_toolslot_]]
		if self.last_tool_ ~= new_tool then
			if not new_tool_id:find("^DEFAULT_PT_LIFECUST_") then
				if toolwarn_tools[new_tool] then
					self.display_toolwarn_[toolwarn_tools[new_tool]] = true
				end
			end
			self.last_tool_ = new_tool
		end
	end
	
	function profile_i:update_kmod_()
		if self.kmod_changed_ then
			self.kmod_changed_ = nil
			self:report_kmod_()
		end
	end
	
	function profile_i:update_deco_()
		local deco = sim.decoColour()
		if self.deco_ ~= deco then
			self.deco_ = deco
			self:report_deco_()
		end
	end
	
	function profile_i:begin_placesave_size_(x, y, aux_button)
		local bx, by = math.floor(x / 4), math.floor(y / 4)
		local p = 0
		local pres = {}
		local function push(x, y)
			p = p + 2
			local pr = sim.pressure(x, y)
			if pr >  256 then pr =  256 end
			if pr < -256 then pr = -256 end
			local st = (math.floor(pr * 0x10) * 0x1000 + math.random(0x000, 0xFFF)) / 0x10000
			pres[p - 1] = pr
			pres[p] = st
			sim.pressure(x, y, st)
		end
		for x = 0, sim.XRES / 4 - 1 do
			push(x, by)
		end
		for y = 0, sim.YRES / 4 - 1 do
			if y ~= by then
				push(bx, y)
			end
		end
		local pss = {
			pres = pres,
			bx = bx,
			by = by,
			aux_button = aux_button,
			airmode = sim.airMode(),
			partcount = sim.NUM_PARTS,
		}
		if aux_button then
			-- * This means that begin_placesave_size_ was called from a button
			--   callback, i.e. not really in response to pasting, but reloading /
			--   clearing / opening a save. In this case, the air mode should
			--   not be reset to the original air mode, but left to be whatever
			--   value these actions set it to.
			self.placesave_size_next_ = pss
		else
			self.placesave_size_ = pss
		end
		sim.airMode(4)
	end
	
	function profile_i:end_placesave_size_()
		local bx, by = self.placesave_size_.bx, self.placesave_size_.by
		local pres = self.placesave_size_.pres
		local p = 0
		local lx, ly, hx, hy = math.huge, math.huge, -math.huge, -math.huge
		local function pop(x, y)
			p = p + 2
			if sim.pressure(x, y) == pres[p] then
				sim.pressure(x, y, pres[p - 1])
			else
				lx = math.min(lx, x)
				ly = math.min(ly, y)
				hx = math.max(hx, x)
				hy = math.max(hy, y)
			end
		end
		for x = 0, sim.XRES / 4 - 1 do
			pop(x, by)
		end
		for y = 0, sim.YRES / 4 - 1 do
			if y ~= by then
				pop(bx, y)
			end
		end
		-- * Unlike normal stamp pastes, auxiliary button events (open, save, clear)
		--   are guaranteed to have been cancelled if no air change is detected.
		--   The following block roughly translates to resetting the air mode to
		--   the sampled value if the change in the simulation occurred due to
		--   a paste event, otherwise only if we actually detected a change in air.
		if not self.placesave_size_.aux_button or lx == math.huge then
			sim.airMode(self.placesave_size_.airmode)
		end
		local partcount = self.placesave_size_.partcount
		self.placesave_size_ = nil
		if lx == math.huge then
			self.placesave_postmsg_ = {
				partcount = partcount,
			}
		else
			return math.max((lx - 2) * 4, 0),
			       math.max((ly - 2) * 4, 0),
			       math.min((hx + 2) * 4, sim.XRES) - 1,
			       math.min((hy + 2) * 4, sim.YRES) - 1
		end
	end
	
	function profile_i:handle_tick()
		self:post_event_check_()
		if self.want_stamp_size_ then
			self.want_stamp_size_ = nil
			local w, h = self:get_stamp_size_()
			if w then
				self.place_x_, self.place_y_ = w, h
			end
		end
		if self.signs_invalid_ then
			local sign_data = self.signs_invalid_
			self.signs_invalid_ = nil
			self:check_signs(sign_data)
		end
		self:update_pos_(tpt.mousex, tpt.mousey)
		-- * Here the assumption is made that no Lua hook cancels the tick event.
		if self.placing_zoom_ then
			self.zoom_invalid_ = true
		end
		if self.skip_draw_ then
			self.skip_draw_ = nil
		else
			if self.select_mode_ == "none" and self.dragging_mouse_ then
				if self.draw_mode_ == "flood" then
					self:report_flood_(self.last_toolslot_, self.pos_x_, self.pos_y_)
				end
				if self.draw_mode_ == "points" then
					self:report_pointscont_(self.pos_x_, self.pos_y_)
				end
			end
		end
		if self.simstate_invalid_next_ then
			self.simstate_invalid_next_ = nil
			self.simstate_invalid_ = true
		end
		if self.placesave_size_next_ then
			self.placesave_size_ = self.placesave_size_next_
			self.placesave_size_next_ = nil
		end
		local complete_select_mode = self.select_x_ and self.select_mode_
		if self.prev_select_mode_ ~= complete_select_mode then
			self.prev_select_mode_ = complete_select_mode
			if self.select_mode_ == "copy"
			or self.select_mode_ == "cut"
			or self.select_mode_ == "stamp" then
				if self.select_mode_ == "copy" then
					self:report_selectstatus_(1, self.select_x_, self.select_y_)
				elseif self.select_mode_ == "cut" then
					self:report_selectstatus_(2, self.select_x_, self.select_y_)
				elseif self.select_mode_ == "stamp" then
					self:report_selectstatus_(3, self.select_x_, self.select_y_)
				end
			else
				self.select_x_, self.select_y_ = nil, nil
				self:report_selectstatus_(0, 0, 0)
			end
		end
		local complete_place_mode = self.place_x_ and self.select_mode_
		if self.prev_place_mode_ ~= complete_place_mode then
			self.prev_place_mode_ = complete_place_mode
			if self.select_mode_ == "place" then
				self:report_placestatus_(1, self.place_x_, self.place_y_)
			else
				self.place_x_, self.place_y_ = nil, nil
				self:report_placestatus_(0, 0, 0)
			end
		end
	end
	
	function profile_i:handle_mousedown(px, py, button)
		self:post_event_check_()
		self:update_pos_(px, py)
		self.last_in_zoom_window_ = in_zoom_window(px, py)
		-- * Here the assumption is made that no Lua hook cancels the mousedown event.
		if not self.kmod_c_ and not self.kmod_s_ and self.kmod_a_ and button == sdl.SDL_BUTTON_LEFT then
			button = 2
		end
		for _, btn in pairs(self.buttons_) do
			if util.inside_rect(btn.x, btn.y, btn.w, btn.h, tpt.mousex, tpt.mousey) then
				btn.active = true
			end
		end
		if not self.placing_zoom_ then
			if self.select_mode_ ~= "none" then
				self.sel_x1_ = self.pos_x_
				self.sel_y1_ = self.pos_y_
				self.sel_x2_ = self.pos_x_
				self.sel_y2_ = self.pos_y_
				self.dragging_mouse_ = true
				self.select_x_, self.select_y_ = self.pos_x_, self.pos_y_
				return
			end
			if px < sim.XRES and py < sim.YRES then
				if button == sdl.SDL_BUTTON_LEFT then
					self.last_toolslot_ = 0
				elseif button == sdl.SDL_BUTTON_MIDDLE then
					self.last_toolslot_ = 2
				elseif button == sdl.SDL_BUTTON_RIGHT then
					self.last_toolslot_ = 1
				else
					return
				end
				self:update_tools_()
				if next(self.display_toolwarn_) then
					if self.registered_func_() then
						for key in pairs(self.display_toolwarn_) do
							self.log_event_func_(toolwarn_messages[key])
						end
					end
					self.display_toolwarn_ = {}
				end
				self:update_draw_mode_()
				self.dragging_mouse_ = true
				if self.draw_mode_ == "rect" then
					self:report_rectstart_(self.last_toolslot_, self.pos_x_, self.pos_y_)
				end
				if self.draw_mode_ == "line" then
					self:report_linestart_(self.last_toolslot_, self.pos_x_, self.pos_y_)
				end
				if self.draw_mode_ == "flood" then
					if util.xid_class[self[index_to_lrax[self.last_toolslot_]]] == "DECOR" and self.registered_func_() then
						self.log_event_func_("Decoration flooding does not sync, you will have to use /sync")
					end
					self:report_flood_(self.last_toolslot_, self.pos_x_, self.pos_y_)
				end
				if self.draw_mode_ == "points" then
					self:report_pointsstart_(self.last_toolslot_, self.pos_x_, self.pos_y_)
				end
			end
		end
	end
	
	function profile_i:cancel_drawing_()
		if self.dragging_mouse_ then
			self:report_canceldraw_()
			self.dragging_mouse_ = false
		end
	end
	
	function profile_i:handle_mousemove(px, py, delta_x, delta_y)
		self:post_event_check_()
		self:update_pos_(px, py)
		for _, btn in pairs(self.buttons_) do
			if not util.inside_rect(btn.x, btn.y, btn.w, btn.h, tpt.mousex, tpt.mousey) then
				btn.active = false
			end
		end
		-- * Here the assumption is made that no Lua hook cancels the mousemove event.
		if self.select_mode_ ~= "none" then
			if self.select_mode_ == "place" then
				self.sel_x1_ = self.pos_x_
				self.sel_y1_ = self.pos_y_
			end
			if self.sel_x1_ then
				self.sel_x2_ = self.pos_x_
				self.sel_y2_ = self.pos_y_
			end
		elseif self.dragging_mouse_ then
			local last = self.last_in_zoom_window_
			self.last_in_zoom_window_ = in_zoom_window(px, py)
			if last ~= self.last_in_zoom_window_ and (self.draw_mode_ == "flood" or self.draw_mode_ == "points") then
				self:cancel_drawing_()
				return
			end
			if self.draw_mode_ == "flood" then
				self:report_flood_(self.last_toolslot_, self.pos_x_, self.pos_y_)
				self.skip_draw_ = true
			end
			if self.draw_mode_ == "points" then
				self:report_pointscont_(self.pos_x_, self.pos_y_)
				self.skip_draw_ = true
			end
		end
	end
	
	function profile_i:handle_mouseup(px, py, button, reason)
		self:post_event_check_()
		self:update_pos_(px, py)
		for name, btn in pairs(self.buttons_) do
			if btn.active then
				self["button_" .. name .. "_"](self)
			end
			btn.active = false
		end
		-- * Here the assumption is made that no Lua hook cancels the mouseup event.
		if px >= sim.XRES or py >= sim.YRES then
			self.perfect_circle_invalid_ = true
			self.simstate_invalid_next_ = true
		end
		if reason == MOUSEUP_REASON_MOUSEUP and self[index_to_lrax[self.last_toolslot_]] ~= util.from_tool.DEFAULT_UI_SIGN or button ~= 1 then
			for i = 1, MAX_SIGNS do
				local x = sim.signs[i].screenX
				if x then
					local t = sim.signs[i].text
					local y = sim.signs[i].screenY
					local w = sim.signs[i].width + 1
					local h = sim.signs[i].height
					if util.inside_rect(x, y, w, h, self.pos_x_, self.pos_y_) then
						if t:match("^{b|.*}$") then
							self:report_sparksign_(sim.signs[i].x, sim.signs[i].y)
						end
						if t:match("^{c:[0-9]+|.*}$") then
							if self.client_ then
								self.placesave_open_ = true
								self:begin_placesave_size_(100, 100, true)
							end
						end
					end
				end
			end
		end
		if self.placing_zoom_ then
			self.placing_zoom_ = false
			self.draw_mode_ = "points"
			self:cancel_drawing_()
		elseif self.dragging_mouse_ then
			if self.select_mode_ ~= "none" then
				if reason == MOUSEUP_REASON_MOUSEUP then
					local x, y, w, h = util.corners_to_rect(self.sel_x1_, self.sel_y1_, self.sel_x2_, self.sel_y2_)
					if self.select_mode_ == "place" then
						if self.client_ then
							self:begin_placesave_size_(x, y)
						end
					elseif self.select_mode_ == "copy" then
						self.clipsize_x_ = w
						self.clipsize_y_ = h
					elseif self.select_mode_ == "cut" then
						self.clipsize_x_ = w
						self.clipsize_y_ = h
						self:report_clearrect_(x, y, w, h)
					elseif self.select_mode_ == "stamp" then
						-- * Nothing.
					end
				end
				self.select_mode_ = "none"
				self:cancel_drawing_()
				return
			end
			if reason == MOUSEUP_REASON_MOUSEUP then
				if self.draw_mode_ == "rect" then
					self:report_rectend_(self.pos_x_, self.pos_y_)
				end
				if self.draw_mode_ == "line" then
					self:report_lineend_(self.pos_x_, self.pos_y_)
				end
				if self.draw_mode_ == "flood" then
					self:report_flood_(self.last_toolslot_, self.pos_x_, self.pos_y_)
				end
				if self.draw_mode_ == "points" then
					self:report_pointscont_(self.pos_x_, self.pos_y_, true)
				end
			end
			self:cancel_drawing_()
		elseif self.select_mode_ ~= "none" and button ~= 1 then
			if reason == MOUSEUP_REASON_MOUSEUP then
				self.select_mode_ = "none"
			end
		end
		self:update_draw_mode_()
	end
	
	function profile_i:handle_mousewheel(px, py, dir)
		self:post_event_check_()
		self:update_pos_(px, py)
		-- * Here the assumption is made that no Lua hook cancels the mousewheel event.
		if self.placing_zoom_ then
			self.zoom_invalid_ = true
		end
	end
	
	function profile_i:handle_keypress(key, scan, rep, shift, ctrl, alt)
		self:post_event_check_()
		if shift and not self.kmod_s_ then
			self:enable_shift_()
		end
		if ctrl and not self.kmod_c_ then
			self:enable_ctrl_()
		end
		if alt and not self.kmod_a_ then
			self:enable_alt_()
		end
		self:update_kmod_()
		-- * Here the assumption is made that no Lua hook cancels the keypress event.
		if not rep then
			if not self.stk2_out_ or ctrl then
				if scan == sdl.SDL_SCANCODE_W then
					self.simstate_invalid_ = true
				elseif scan == sdl.SDL_SCANCODE_S then
					self.select_mode_ = "stamp"
					self:cancel_drawing_()
				end
			end
		end
		-- * Here the assumption is made that no debug hook cancels the keypress event.
		if self.select_mode_ == "place" then
			-- * Note: Sadly, there's absolutely no way to know how these operations
			--         affect the save being placed, as it only grows if particles
			--         in it would go beyond its border.
			if key == sdl.SDLK_RIGHT then
				-- * Move. See note above.
				return
			elseif key == sdl.SDLK_LEFT then
				-- * Move. See note above.
				return
			elseif key == sdl.SDLK_DOWN then
				-- * Move. See note above.
				return
			elseif key == sdl.SDLK_UP then
				-- * Move. See note above.
				return
			elseif scan == sdl.SDL_SCANCODE_R and not rep then
				if ctrl and shift then
					-- * Rotate. See note above.
				elseif not ctrl and shift then
					-- * Rotate. See note above.
				else
					-- * Rotate. See note above.
				end
				return
			end
		end
		if rep then
			return
		end
		local did_shortcut = true
		if scan == sdl.SDL_SCANCODE_SPACE then
			self.simstate_invalid_ = true
		elseif scan == sdl.SDL_SCANCODE_GRAVE then
			if self.registered_func_() and not alt then
				self.log_event_func_("The console is disabled because it does not sync (press the Alt key to override)")
				return true
			end
		elseif scan == sdl.SDL_SCANCODE_Z then
			if self.select_mode_ == "none" or not self.dragging_mouse_ then
				if ctrl and not self.dragging_mouse_ then
					if self.registered_func_() and not alt then
						self.log_event_func_("Undo is disabled because it does not sync (press the Alt key to override)")
						return true
					end
				else
					self:cancel_drawing_()
					self.placing_zoom_ = true
					self.zoom_invalid_ = true
				end
			end
		elseif scan == sdl.SDL_SCANCODE_F5 or (ctrl and scan == sdl.SDL_SCANCODE_R) then
			self:button_reload_()
		elseif scan == sdl.SDL_SCANCODE_F and not ctrl then
			if ren.debugHUD() == 1 and (shift or alt) then
				if self.registered_func_() and not alt then
					self.log_event_func_("Partial framesteps do not sync, you will have to use /sync")
				end
			end
			self:report_framestep_()
			self.simstate_invalid_ = true
		elseif scan == sdl.SDL_SCANCODE_B and not ctrl then
			self.simstate_invalid_ = true
		elseif scan == sdl.SDL_SCANCODE_Y then
			if ctrl then
				if self.registered_func_() and not alt then
					self.log_event_func_("Redo is disabled because it does not sync (press the Alt key to override)")
					return true
				end
			else
				self.simstate_invalid_ = true
			end
		elseif scan == sdl.SDL_SCANCODE_U then
			if ctrl then
				self:report_reset_airtemp_()
			else
				self.simstate_invalid_ = true
			end
		elseif scan == sdl.SDL_SCANCODE_N then
			self.simstate_invalid_ = true
		elseif scan == sdl.SDL_SCANCODE_EQUALS then
			if ctrl then
				self:report_reset_spark_()
			else
				self:report_reset_air_()
			end
		elseif scan == sdl.SDL_SCANCODE_C and ctrl then
			self.select_mode_ = "copy"
			self:cancel_drawing_()
		elseif scan == sdl.SDL_SCANCODE_X and ctrl then
			self.select_mode_ = "cut"
			self:cancel_drawing_()
		elseif scan == sdl.SDL_SCANCODE_V and ctrl then
			if self.clipsize_x_ then
				self.select_mode_ = "place"
				self:cancel_drawing_()
				self.place_x_, self.place_y_ = self.clipsize_x_, self.clipsize_y_
			end
		elseif scan == sdl.SDL_SCANCODE_L then
			self.select_mode_ = "place"
			self:cancel_drawing_()
			self.want_stamp_size_ = true
		elseif scan == sdl.SDL_SCANCODE_K then
			self.select_mode_ = "place"
			self:cancel_drawing_()
			self.want_stamp_size_ = true
		elseif scan == sdl.SDL_SCANCODE_RIGHTBRACKET then
			if self.placing_zoom_ then
				self.zoom_invalid_ = true
			end
		elseif scan == sdl.SDL_SCANCODE_LEFTBRACKET then
			if self.placing_zoom_ then
				self.zoom_invalid_ = true
			end
		elseif scan == sdl.SDL_SCANCODE_I and not ctrl then
			self:report_airinvert_()
		elseif scan == sdl.SDL_SCANCODE_SEMICOLON then
			if self.client_ then
				self.bmode_invalid_ = true
			end
		end
		if key == sdl.SDLK_INSERT or key == sdl.SDLK_DELETE then
			if self.client_ then
				self.bmode_invalid_ = true
			end
		end
	end
	
	function profile_i:handle_keyrelease(key, scan, rep, shift, ctrl, alt)
		self:post_event_check_()
		if not shift and self.kmod_s_ then
			self:disable_shift_()
		end
		if not ctrl and self.kmod_c_ then
			self:disable_ctrl_()
		end
		if not alt and self.kmod_a_ then
			self:disable_alt_()
		end
		self:update_kmod_()
		-- * Here the assumption is made that no Lua hook cancels the keyrelease event.
		-- * Here the assumption is made that no debug hook cancels the keyrelease event.
		if rep then
			return
		end
		if scan == sdl.SDL_SCANCODE_Z then
			if self.placing_zoom_ and not alt then
				self.placing_zoom_ = false
				self.zoom_invalid_ = true
			end
		end
	end
	
	function profile_i:handle_textinput(text)
		self:post_event_check_()
	end
	
	function profile_i:handle_textediting(text)
		self:post_event_check_()
	end
	
	function profile_i:handle_blur()
		self:post_event_check_()
		for _, btn in pairs(self.buttons_) do
			btn.active = false
		end
		if self[index_to_lrax[self.last_toolslot_]] == util.from_tool.DEFAULT_UI_SIGN then
			self.signs_invalid_ = get_sign_data()
		end
		self:disable_shift_()
		self:disable_ctrl_()
		self:disable_alt_()
		self:update_kmod_()
		self:cancel_drawing_()
		self.draw_mode_ = "points"
	end
	
	function profile_i:should_ignore_mouse()
		return self.placing_zoom_ or self.select_mode_ ~= "none"
	end
	
	function profile_i:button_open_()
		if self.client_ then
			self.placesave_open_ = true
			self:begin_placesave_size_(100, 100, true)
		end
	end
	
	function profile_i:button_reload_()
		if self.client_ then
			self.placesave_reload_ = true
			self:begin_placesave_size_(100, 100, true)
		end
	end
	
	function profile_i:button_clear_()
		if self.client_ then
			self.placesave_clear_ = true
			self:begin_placesave_size_(100, 100, true)
		end
	end
	
	function profile_i:set_client(client)
		self.client_ = client
		self.bmode_invalid_ = true
		self.set_id_func_(util.get_save_id())
	end
	
	function profile_i:clear_client()
		self.client_ = nil
	end
	
	local function new(params)
		local prof = setmetatable({
			placing_zoom_ = false,
			kmod_c_ = false,
			kmod_s_ = false,
			kmod_a_ = false,
			bmode_ = 0,
			dragging_mouse_ = false,
			select_mode_ = "none",
			prev_select_mode_ = false,
			prev_place_mode_ = false,
			draw_mode_ = "points",
			last_toolslot_ = 0,
			shape_ = 0,
			stk2_out_ = false,
			perfect_circle_invalid_ = true,
			registered_func_ = params.registered_func,
			log_event_func_ = params.log_event_func,
			set_id_func_ = params.set_id_func,
			get_id_func_ = params.get_id_func,
			display_toolwarn_ = {},
			buttons_ = {
				open   = { x =               1, y = gfx.HEIGHT - 16, w = 17, h = 15 },
				reload = { x =              19, y = gfx.HEIGHT - 16, w = 17, h = 15 },
				clear  = { x = gfx.WIDTH - 159, y = gfx.HEIGHT - 16, w = 17, h = 15 },
			},
		}, profile_m)
		prof.tool_l_ = util.from_tool.UNKNOWN
		prof.tool_r_ = util.from_tool.UNKNOWN
		prof.tool_a_ = util.from_tool.UNKNOWN
		prof.tool_x_ = util.from_tool.UNKNOWN
		prof.last_tool_ = prof.tool_l_
		prof.deco_ = sim.decoColour()
		prof:update_pos_(tpt.mousex, tpt.mousey)
		prof:update_size_()
		prof:update_tools_()
		prof:update_deco_()
		prof:check_simstate()
		prof:update_kmod_()
		prof:update_bmode_()
		prof:update_shape_()
		prof:update_zoom_()
		prof:check_signs({})
		if false then
			prof.debug_ = function(...)
				print("[prof debug]", ...)
			end
		end
		return prof
	end
	
	return {
		new = new,
		brand = "vanilla",
		profile_i = profile_i,
	}
	
end

require_preload__["tptmp.client.sdl"] = function()

	-- * TODO[api]: get these from tpt
	return {
	    SDL_SCANCODE_A            =   4,
	    SDL_SCANCODE_B            =   5,
	    SDL_SCANCODE_C            =   6,
	    SDL_SCANCODE_F            =   9,
	    SDL_SCANCODE_I            =  12,
	    SDL_SCANCODE_K            =  14,
	    SDL_SCANCODE_L            =  15,
	    SDL_SCANCODE_N            =  17,
	    SDL_SCANCODE_R            =  21,
	    SDL_SCANCODE_S            =  22,
	    SDL_SCANCODE_T            =  23,
	    SDL_SCANCODE_U            =  24,
	    SDL_SCANCODE_V            =  25,
	    SDL_SCANCODE_W            =  26,
	    SDL_SCANCODE_X            =  27,
	    SDL_SCANCODE_Y            =  28,
	    SDL_SCANCODE_Z            =  29,
	    SDL_SCANCODE_RETURN       =  40,
	    SDL_SCANCODE_ESCAPE       =  41,
	    SDL_SCANCODE_BACKSPACE    =  42,
	    SDL_SCANCODE_TAB          =  43,
	    SDL_SCANCODE_SPACE        =  44,
	    SDL_SCANCODE_EQUALS       =  46,
	    SDL_SCANCODE_LEFTBRACKET  =  47,
	    SDL_SCANCODE_RIGHTBRACKET =  48,
	    SDL_SCANCODE_SEMICOLON    =  51,
	    SDL_SCANCODE_GRAVE        =  53,
	    SDL_SCANCODE_F5           =  62,
	    SDL_SCANCODE_HOME         =  74,
	    SDL_SCANCODE_DELETE       =  76,
	    SDL_SCANCODE_END          =  77,
	    SDL_SCANCODE_RIGHT        =  79,
	    SDL_SCANCODE_LEFT         =  80,
	    SDL_SCANCODE_DOWN         =  81,
	    SDL_SCANCODE_UP           =  82,
	    SDL_SCANCODE_LCTRL        = 224,
	    SDL_SCANCODE_LSHIFT       = 225,
	    SDL_SCANCODE_LALT         = 226,
	    SDL_SCANCODE_RCTRL        = 228,
	    SDL_SCANCODE_RSHIFT       = 229,
	    SDL_SCANCODE_RALT         = 230,
	    SDLK_DELETE               = 127,
	    SDLK_INSERT               = 0x40000000 + 73,
	    SDLK_RIGHT                = 0x40000000 + 79,
	    SDLK_LEFT                 = 0x40000000 + 80,
	    SDLK_DOWN                 = 0x40000000 + 81,
	    SDLK_UP                   = 0x40000000 + 82,
	    SDL_BUTTON_LEFT           = 1,
	    SDL_BUTTON_MIDDLE         = 2,
	    SDL_BUTTON_RIGHT          = 3,
	}
	
end

require_preload__["tptmp.client.side_button"] = function()

	local colours = require("tptmp.client.colours")
	local util    = require("tptmp.client.util")
	local utf8    = require("tptmp.client.utf8")
	local config  = require("tptmp.client.config")
	local manager = require("tptmp.client.manager")
	local sdl     = require("tptmp.client.sdl")
	
	local side_button_i = {}
	local side_button_m = { __index = side_button_i }
	
	function side_button_i:draw_button_()
		local inside = util.inside_rect(self.pos_x_, self.pos_y_, self.width_, self.height_, util.mouse_pos())
		if self.active_ and not inside then
			self.active_ = false
		end
		local state
		if self.active_ or self.window_status_func_() == "shown" then
			state = "active"
		elseif inside then
			state = "hover"
		else
			state = "inactive"
		end
		local text_colour = colours.appearance[state].text
		local border_colour = colours.appearance[state].border
		local background_colour = colours.appearance[state].background
		gfx.fillRect(self.pos_x_ + 1, self.pos_y_ + 1, self.width_ - 2, self.height_ - 2, unpack(background_colour))
		gfx.drawRect(self.pos_x_, self.pos_y_, self.width_, self.height_, unpack(border_colour))
		gfx.drawText(self.tx_, self.ty_, self.text_, unpack(text_colour))
	end
	
	function side_button_i:update_notif_count_()
		local notif_count = self.notif_count_func_()
		local notif_important = self.notif_important_func_()
		if self.window_status_func_() == "floating" and not notif_important then
			notif_count = 0
		end
		if self.notif_count_ ~= notif_count or self.notif_important_ ~= notif_important then
			self.notif_count_ = notif_count
			self.notif_important_ = notif_important
			local notif_count_str = tostring(self.notif_count_)
			self.notif_background_ = utf8.encode_multiple(0xE03B, 0xE039) .. utf8.encode_multiple(0xE03C):rep(#notif_count_str - 1) .. utf8.encode_multiple(0xE03A)
			self.notif_border_ = utf8.encode_multiple(0xE02D, 0xE02B) .. utf8.encode_multiple(0xE02E):rep(#notif_count_str - 1) .. utf8.encode_multiple(0xE02C)
			self.notif_text_ = notif_count_str:gsub(".", function(ch)
				return utf8.encode_multiple(ch:byte() + 0xDFFF)
			end)
			self.notif_width_ = gfx.textSize(self.notif_background_)
			self.notif_last_change_ = socket.gettime()
		end
	end
	
	function side_button_i:draw_notif_count_()
		if self.notif_count_ > 0 then
			local since_last_change = socket.gettime() - self.notif_last_change_
			local fly = since_last_change > config.notif_fly_time and 0 or ((1 - since_last_change / config.notif_fly_time) * config.notif_fly_distance)
			gfx.drawText(self.pos_x_ - self.notif_width_ + 4, self.pos_y_ - 4 - fly, self.notif_background_, unpack(self.notif_important_ and colours.common.notif_important or colours.common.notif_normal))
			gfx.drawText(self.pos_x_ - self.notif_width_ + 4, self.pos_y_ - 4 - fly, self.notif_border_)
			gfx.drawText(self.pos_x_ - self.notif_width_ + 7, self.pos_y_ - 4 - fly, self.notif_text_)
		end
	end
	
	function side_button_i:handle_tick()
		self:draw_button_()
		self:update_notif_count_()
		self:draw_notif_count_()
	end
	
	function side_button_i:handle_mousedown(mx, my, button)
		if button == sdl.SDL_BUTTON_LEFT then
			if util.inside_rect(self.pos_x_, self.pos_y_, self.width_, self.height_, util.mouse_pos()) then
				self.active_ = true
			end
		end
	end
	
	function side_button_i:handle_mouseup(mx, my, button)
		if button == sdl.SDL_BUTTON_LEFT then
			if self.active_ then
				if manager.minimize_conflict and not manager.hidden() then
					manager.print("minimize the manager before opening TPTMP")
				else
					if self.window_status_func_() == "shown" then
						self.hide_window_func_()
					else
						self.show_window_func_()
					end
				end
				self.active_ = false
			end
		end
	end
	
	function side_button_i:handle_mousewheel(pos_x, pos_y, dir)
	end
	
	function side_button_i:handle_keypress(key, scan, rep, shift, ctrl, alt)
		if shift and not ctrl and not alt and scan == sdl.SDL_SCANCODE_ESCAPE then
			self.show_window_func_()
			return true
		elseif alt and not ctrl and not shift and scan == sdl.SDL_SCANCODE_S then
			self.sync_func_()
			return true
		elseif not alt and not ctrl and not shift and scan == sdl.SDL_SCANCODE_T and self.window_status_func_() == "floating" then
			self.begin_chat_func_()
			return true
		end
	end
	
	function side_button_i:handle_keyrelease(key, scan, rep, shift, ctrl, alt)
	end
	
	function side_button_i:handle_textinput(text)
	end
	
	function side_button_i:handle_textediting(text)
	end
	
	function side_button_i:handle_blur()
		self.active_ = false
	end
	
	local function new(params)
		local pos_x, pos_y, width, height = 613, 136, 15, 15
		if tpt.version.jacob1s_mod and tpt.oldmenu and tpt.oldmenu() == 1 then
			pos_y = 392
		elseif tpt.num_menus then
			pos_y = 392 - 16 * tpt.num_menus() - (not tpt.version.jacob1s_mod and 16 or 0)
		end
		if manager.side_button_conflict then
			pos_y = pos_y - 17
		end
		local text = "<<"
		local tw, th = gfx.textSize(text)
		local tx = pos_x + math.ceil((width - tw) / 2)
		local ty = pos_y + math.floor((height - th) / 2)
		return setmetatable({
			text_ = text,
			tx_ = tx,
			pos_x_ = pos_x,
			ty_ = ty,
			pos_y_ = pos_y,
			width_ = width,
			height_ = height,
			active_ = false,
			notif_last_change_ = 0,
			notif_count_ = 0,
			notif_important_ = false,
			notif_count_func_ = params.notif_count_func,
			notif_important_func_ = params.notif_important_func,
			show_window_func_ = params.show_window_func,
			hide_window_func_ = params.hide_window_func,
			begin_chat_func_ = params.begin_chat_func,
			window_status_func_ = params.window_status_func,
			sync_func_ = params.sync_func,
		}, side_button_m)
	end
	
	return {
		new = new,
	}
	
end

require_preload__["tptmp.client.utf8"] = function()

	local function code_points(str)
		local cps = {}
		local cursor = 0
		while true do
			local old_cursor = cursor
			cursor = cursor + 1
			local head = str:byte(cursor)
			if not head then
				break
			end
			local size = 1
			if head >= 0x80 then
				if head < 0xC0 then
					return nil, cursor
				end
				size = 2
				if head >= 0xE0 then
					size = 3
				end
				if head >= 0xF0 then
					size = 4
				end
				if head >= 0xF8 then
					return nil, cursor
				end
				head = bit.band(head, bit.lshift(1, 7 - size) - 1)
				for ix = 2, size do
					local by = str:byte(cursor + ix - 1)
					if not by then
						return nil, cursor
					end
					if by < 0x80 or by >= 0xC0 then
						return nil, cursor + ix
					end
					head = bit.bor(bit.lshift(head, 6), bit.band(by, 0x3F))
				end
				cursor = cursor - 1 + size
			end
			local pos = old_cursor + 1
			if (head < 0x80 and size > 1)
			or (head < 0x800 and size > 2)
			or (head < 0x10000 and size > 3) then
				return nil, pos
			end
			table.insert(cps, { cp = head, pos = pos, size = size })
		end
		return cps
	end
	
	local function encode(code_point)
		if code_point < 0x80 then
			return string.char(code_point)
		elseif code_point < 0x800 then
			return string.char(
				bit.bor(0xC0,          bit.rshift(code_point,  6)       ),
				bit.bor(0x80, bit.band(           code_point     , 0x3F))
			)
		elseif code_point < 0x10000 then
			return string.char(
				bit.bor(0xE0,          bit.rshift(code_point, 12)       ),
				bit.bor(0x80, bit.band(bit.rshift(code_point,  6), 0x3F)),
				bit.bor(0x80, bit.band(           code_point     , 0x3F))
			)
		elseif code_point < 0x200000 then
			return string.char(
				bit.bor(0xF0,          bit.rshift(code_point, 18)       ),
				bit.bor(0x80, bit.band(bit.rshift(code_point, 12), 0x3F)),
				bit.bor(0x80, bit.band(bit.rshift(code_point,  6), 0x3F)),
				bit.bor(0x80, bit.band(           code_point     , 0x3F))
			)
		else
			error("invalid code point")
		end
	end
	
	local function encode_multiple(cp, ...)
		if not ... then
			return encode(cp)
		end
		local cps = { cp, ... }
		local collect = {}
		for i = 1, #cps do
			table.insert(collect, encode(cps[i]))
		end
		return table.concat(collect)
	end
	
	if tpt.version.jacob1s_mod then
		function code_points(str)
			local cps = {}
			for pos in str:gmatch("().") do
				table.insert(cps, { cp = str:byte(pos), pos = pos, size = 1 })
			end
			return cps
		end
	
		function encode(cp)
			if cp >= 0xE000 then
				cp = cp - 0xDF80
			end
			return string.char(cp)
		end
	end
	
	return {
		code_points = code_points,
		encode = encode,
		encode_multiple = encode_multiple,
	}
	
end

require_preload__["tptmp.client.util"] = function()

	local config      = require("tptmp.client.config")
	local common_util = require("tptmp.common.util")
	
	local jacobsmod = rawget(_G, "jacobsmod")
	local from_tool = {}
	local to_tool = {}
	local xid_first = {}
	local PMAPBITS = sim.PMAPBITS
	
	local tpt_version = { tpt.version.major, tpt.version.minor }
	local has_ambient_heat_tools
	do
		local old_selectedl = tpt.selectedl
		if old_selectedl == "DEFAULT_UI_PROPERTY" or old_selectedl == "DEFAULT_UI_ADDLIFE" then
			old_selectedl = "DEFAULT_PT_DUST"
		end
		has_ambient_heat_tools = pcall(function() tpt.selectedl = "DEFAULT_TOOL_AMBM" end)
		tpt.selectedl = old_selectedl
	end
	
	local function array_concat(...)
		local tbl = {}
		local arrays = { ... }
		for i = 1, #arrays do
			for j = 1, #arrays[i] do
				table.insert(tbl, arrays[i][j])
			end
		end
		return tbl
	end
	
	local function array_keyify(arr)
		local tbl = {}
		for i = 1, #arr do
			tbl[arr[i]] = true
		end
		return tbl
	end
	
	local tools = array_concat({
		"DEFAULT_PT_LIFE_GOL",
		"DEFAULT_PT_LIFE_HLIF",
		"DEFAULT_PT_LIFE_ASIM",
		"DEFAULT_PT_LIFE_2X2",
		"DEFAULT_PT_LIFE_DANI",
		"DEFAULT_PT_LIFE_AMOE",
		"DEFAULT_PT_LIFE_MOVE",
		"DEFAULT_PT_LIFE_PGOL",
		"DEFAULT_PT_LIFE_DMOE",
		"DEFAULT_PT_LIFE_3-4",
		"DEFAULT_PT_LIFE_LLIF",
		"DEFAULT_PT_LIFE_STAN",
		"DEFAULT_PT_LIFE_SEED",
		"DEFAULT_PT_LIFE_MAZE",
		"DEFAULT_PT_LIFE_COAG",
		"DEFAULT_PT_LIFE_WALL",
		"DEFAULT_PT_LIFE_GNAR",
		"DEFAULT_PT_LIFE_REPL",
		"DEFAULT_PT_LIFE_MYST",
		"DEFAULT_PT_LIFE_LOTE",
		"DEFAULT_PT_LIFE_FRG2",
		"DEFAULT_PT_LIFE_STAR",
		"DEFAULT_PT_LIFE_FROG",
		"DEFAULT_PT_LIFE_BRAN",
	}, {
		"DEFAULT_WL_ERASE",
		"DEFAULT_WL_CNDTW",
		"DEFAULT_WL_EWALL",
		"DEFAULT_WL_DTECT",
		"DEFAULT_WL_STRM",
		"DEFAULT_WL_FAN",
		"DEFAULT_WL_LIQD",
		"DEFAULT_WL_ABSRB",
		"DEFAULT_WL_WALL",
		"DEFAULT_WL_AIR",
		"DEFAULT_WL_POWDR",
		"DEFAULT_WL_CNDTR",
		"DEFAULT_WL_EHOLE",
		"DEFAULT_WL_GAS",
		"DEFAULT_WL_GRVTY",
		"DEFAULT_WL_ENRGY",
		"DEFAULT_WL_NOAIR",
		"DEFAULT_WL_ERASEA",
		"DEFAULT_WL_STASIS",
	}, {
		"DEFAULT_UI_SAMPLE",
		"DEFAULT_UI_SIGN",
		"DEFAULT_UI_PROPERTY",
		"DEFAULT_UI_WIND",
		"DEFAULT_UI_ADDLIFE",
	}, {
		"DEFAULT_TOOL_HEAT",
		"DEFAULT_TOOL_COOL",
		"DEFAULT_TOOL_AIR",
		"DEFAULT_TOOL_VAC",
		"DEFAULT_TOOL_PGRV",
		"DEFAULT_TOOL_NGRV",
		"DEFAULT_TOOL_MIX",
		"DEFAULT_TOOL_CYCL",
		has_ambient_heat_tools and "DEFAULT_TOOL_AMBM" or nil,
		has_ambient_heat_tools and "DEFAULT_TOOL_AMBP" or nil,
	}, {
		"DEFAULT_DECOR_SET",
		"DEFAULT_DECOR_CLR",
		"DEFAULT_DECOR_ADD",
		"DEFAULT_DECOR_SUB",
		"DEFAULT_DECOR_MUL",
		"DEFAULT_DECOR_DIV",
		"DEFAULT_DECOR_SMDG",
	})
	local xid_class = {}
	for i = 1, #tools do
		local xtype = 0x2000 + i
		local tool = tools[i]
		from_tool[tool] = xtype
		to_tool[xtype] = tool
		local class = tool:match("^[^_]+_(.-)_[^_]+$")
		xid_class[xtype] = class
		xid_first[class] = math.min(xid_first[class] or math.huge, xtype)
	end
	-- * TODO[opt]: support custom elements
	local known_elements = array_keyify({
		"DEFAULT_PT_NONE",
		"DEFAULT_PT_DUST",
		"DEFAULT_PT_WATR",
		"DEFAULT_PT_OIL",
		"DEFAULT_PT_FIRE",
		"DEFAULT_PT_STNE",
		"DEFAULT_PT_LAVA",
		"DEFAULT_PT_GUN",
		"DEFAULT_PT_GUNP",
		"DEFAULT_PT_NITR",
		"DEFAULT_PT_CLNE",
		"DEFAULT_PT_GAS",
		"DEFAULT_PT_C-4",
		"DEFAULT_PT_PLEX",
		"DEFAULT_PT_GOO",
		"DEFAULT_PT_ICE",
		"DEFAULT_PT_ICEI",
		"DEFAULT_PT_METL",
		"DEFAULT_PT_SPRK",
		"DEFAULT_PT_SNOW",
		"DEFAULT_PT_WOOD",
		"DEFAULT_PT_NEUT",
		"DEFAULT_PT_PLUT",
		"DEFAULT_PT_PLNT",
		"DEFAULT_PT_ACID",
		"DEFAULT_PT_VOID",
		"DEFAULT_PT_WTRV",
		"DEFAULT_PT_CNCT",
		"DEFAULT_PT_DSTW",
		"DEFAULT_PT_SALT",
		"DEFAULT_PT_SLTW",
		"DEFAULT_PT_DMND",
		"DEFAULT_PT_BMTL",
		"DEFAULT_PT_BRMT",
		"DEFAULT_PT_PHOT",
		"DEFAULT_PT_URAN",
		"DEFAULT_PT_WAX",
		"DEFAULT_PT_MWAX",
		"DEFAULT_PT_PSCN",
		"DEFAULT_PT_NSCN",
		"DEFAULT_PT_LNTG",
		"DEFAULT_PT_LN2",
		"DEFAULT_PT_INSL",
		"DEFAULT_PT_BHOL",
		"DEFAULT_PT_VACU",
		"DEFAULT_PT_WHOL",
		"DEFAULT_PT_VENT",
		"DEFAULT_PT_RBDM",
		"DEFAULT_PT_LRBD",
		"DEFAULT_PT_NTCT",
		"DEFAULT_PT_SAND",
		"DEFAULT_PT_GLAS",
		"DEFAULT_PT_PTCT",
		"DEFAULT_PT_BGLA",
		"DEFAULT_PT_THDR",
		"DEFAULT_PT_PLSM",
		"DEFAULT_PT_ETRD",
		"DEFAULT_PT_NICE",
		"DEFAULT_PT_NBLE",
		"DEFAULT_PT_BTRY",
		"DEFAULT_PT_LCRY",
		"DEFAULT_PT_STKM",
		"DEFAULT_PT_SWCH",
		"DEFAULT_PT_SMKE",
		"DEFAULT_PT_DESL",
		"DEFAULT_PT_COAL",
		"DEFAULT_PT_LO2",
		"DEFAULT_PT_LOXY",
		"DEFAULT_PT_O2",
		"DEFAULT_PT_OXYG",
		"DEFAULT_PT_INWR",
		"DEFAULT_PT_YEST",
		"DEFAULT_PT_DYST",
		"DEFAULT_PT_THRM",
		"DEFAULT_PT_GLOW",
		"DEFAULT_PT_BRCK",
		"DEFAULT_PT_HFLM",
		"DEFAULT_PT_CFLM",
		"DEFAULT_PT_FIRW",
		"DEFAULT_PT_FUSE",
		"DEFAULT_PT_FSEP",
		"DEFAULT_PT_AMTR",
		"DEFAULT_PT_BCOL",
		"DEFAULT_PT_PCLN",
		"DEFAULT_PT_HSWC",
		"DEFAULT_PT_IRON",
		"DEFAULT_PT_MORT",
		"DEFAULT_PT_LIFE",
		"DEFAULT_PT_DLAY",
		"DEFAULT_PT_CO2",
		"DEFAULT_PT_DRIC",
		"DEFAULT_PT_BUBW",
		"DEFAULT_PT_CBNW",
		"DEFAULT_PT_STOR",
		"DEFAULT_PT_PVOD",
		"DEFAULT_PT_CONV",
		"DEFAULT_PT_CAUS",
		"DEFAULT_PT_LIGH",
		"DEFAULT_PT_TESC",
		"DEFAULT_PT_DEST",
		"DEFAULT_PT_SPNG",
		"DEFAULT_PT_RIME",
		"DEFAULT_PT_FOG",
		"DEFAULT_PT_BCLN",
		"DEFAULT_PT_LOVE",
		"DEFAULT_PT_DEUT",
		"DEFAULT_PT_WARP",
		"DEFAULT_PT_PUMP",
		"DEFAULT_PT_FWRK",
		"DEFAULT_PT_PIPE",
		"DEFAULT_PT_FRZZ",
		"DEFAULT_PT_FRZW",
		"DEFAULT_PT_GRAV",
		"DEFAULT_PT_BIZR",
		"DEFAULT_PT_BIZG",
		"DEFAULT_PT_BIZRG",
		"DEFAULT_PT_BIZRS",
		"DEFAULT_PT_BIZS",
		"DEFAULT_PT_INST",
		"DEFAULT_PT_ISOZ",
		"DEFAULT_PT_ISZS",
		"DEFAULT_PT_PRTI",
		"DEFAULT_PT_PRTO",
		"DEFAULT_PT_PSTE",
		"DEFAULT_PT_PSTS",
		"DEFAULT_PT_ANAR",
		"DEFAULT_PT_VINE",
		"DEFAULT_PT_INVIS",
		"DEFAULT_PT_INVS",
		"DEFAULT_PT_116",
		"DEFAULT_PT_EQVE",
		"DEFAULT_PT_SPAWN2",
		"DEFAULT_PT_SPWN2",
		"DEFAULT_PT_SPWN",
		"DEFAULT_PT_SPAWN",
		"DEFAULT_PT_SHLD",
		"DEFAULT_PT_SHLD1",
		"DEFAULT_PT_SHLD2",
		"DEFAULT_PT_SHD2",
		"DEFAULT_PT_SHD3",
		"DEFAULT_PT_SHLD3",
		"DEFAULT_PT_SHLD4",
		"DEFAULT_PT_SHD4",
		"DEFAULT_PT_LOLZ",
		"DEFAULT_PT_WIFI",
		"DEFAULT_PT_FILT",
		"DEFAULT_PT_ARAY",
		"DEFAULT_PT_BRAY",
		"DEFAULT_PT_STKM2",
		"DEFAULT_PT_STK2",
		"DEFAULT_PT_BOMB",
		"DEFAULT_PT_C5",
		"DEFAULT_PT_C-5",
		"DEFAULT_PT_SING",
		"DEFAULT_PT_QRTZ",
		"DEFAULT_PT_PQRT",
		"DEFAULT_PT_EMP",
		"DEFAULT_PT_BREC",
		"DEFAULT_PT_BREL",
		"DEFAULT_PT_ELEC",
		"DEFAULT_PT_ACEL",
		"DEFAULT_PT_DCEL",
		"DEFAULT_PT_TNT",
		"DEFAULT_PT_BANG",
		"DEFAULT_PT_IGNT",
		"DEFAULT_PT_IGNC",
		"DEFAULT_PT_BOYL",
		"DEFAULT_PT_GEL",
		"DEFAULT_PT_TRON",
		"DEFAULT_PT_TTAN",
		"DEFAULT_PT_EXOT",
		"DEFAULT_PT_EMBR",
		"DEFAULT_PT_HYGN",
		"DEFAULT_PT_H2",
		"DEFAULT_PT_SOAP",
		"DEFAULT_PT_NBHL",
		"DEFAULT_PT_NWHL",
		"DEFAULT_PT_MERC",
		"DEFAULT_PT_PBCN",
		"DEFAULT_PT_GPMP",
		"DEFAULT_PT_CLST",
		"DEFAULT_PT_WWLD",
		"DEFAULT_PT_WIRE",
		"DEFAULT_PT_GBMB",
		"DEFAULT_PT_FIGH",
		"DEFAULT_PT_FRAY",
		"DEFAULT_PT_RPEL",
		"DEFAULT_PT_PPIP",
		"DEFAULT_PT_DTEC",
		"DEFAULT_PT_DMG",
		"DEFAULT_PT_TSNS",
		"DEFAULT_PT_VIBR",
		"DEFAULT_PT_BVBR",
		"DEFAULT_PT_CRAY",
		"DEFAULT_PT_PSTN",
		"DEFAULT_PT_FRME",
		"DEFAULT_PT_GOLD",
		"DEFAULT_PT_TUNG",
		"DEFAULT_PT_PSNS",
		"DEFAULT_PT_PROT",
		"DEFAULT_PT_VIRS",
		"DEFAULT_PT_VRSS",
		"DEFAULT_PT_VRSG",
		"DEFAULT_PT_GRVT",
		"DEFAULT_PT_DRAY",
		"DEFAULT_PT_CRMC",
		"DEFAULT_PT_HEAC",
		"DEFAULT_PT_SAWD",
		"DEFAULT_PT_POLO",
		"DEFAULT_PT_RFRG",
		"DEFAULT_PT_RFGL",
		"DEFAULT_PT_LSNS",
		"DEFAULT_PT_LDTC",
		"DEFAULT_PT_SLCN",
		"DEFAULT_PT_PTNM",
		"DEFAULT_PT_VSNS",
		"DEFAULT_PT_ROCK",
		"DEFAULT_PT_LITH",
	})
	for key, value in pairs(elem) do
		if known_elements[key] then
			from_tool[key] = value
			to_tool[value] = key
		end
	end
	local unknown_xid = 0x3FFF
	assert(not to_tool[unknown_xid])
	from_tool["UNKNOWN"] = unknown_xid
	to_tool[unknown_xid] = "UNKNOWN"
	
	local WL_FAN = from_tool.DEFAULT_WL_FAN - xid_first.WL
	
	local create_override = {
		[ from_tool.DEFAULT_PT_STKM ] = function(rx, ry, c)
			return 0, 0, c
		end,
		[ from_tool.DEFAULT_PT_LIGH ] = function(rx, ry, c)
			local tmp = rx + ry
			if tmp > 55 then
				tmp = 55
			end
			return 0, 0, c + bit.lshift(tmp, PMAPBITS)
		end,
		[ from_tool.DEFAULT_PT_TESC ] = function(rx, ry, c)
			local tmp = rx * 4 + ry * 4 + 7
			if tmp > 300 then
				tmp = 300
			end
			return rx, ry, c + bit.lshift(tmp, PMAPBITS)
		end,
		[ from_tool.DEFAULT_PT_STKM2 ] = function(rx, ry, c)
			return 0, 0, c
		end,
		[ from_tool.DEFAULT_PT_FIGH ] = function(rx, ry, c)
			return 0, 0, c
		end,
	}
	local no_flood = {
		[ from_tool.DEFAULT_PT_SPRK  ] = true,
		[ from_tool.DEFAULT_PT_STKM  ] = true,
		[ from_tool.DEFAULT_PT_LIGH  ] = true,
		[ from_tool.DEFAULT_PT_STKM2 ] = true,
		[ from_tool.DEFAULT_PT_FIGH  ] = true,
	}
	local no_shape = {
		[ from_tool.DEFAULT_PT_STKM  ] = true,
		[ from_tool.DEFAULT_PT_LIGH  ] = true,
		[ from_tool.DEFAULT_PT_STKM2 ] = true,
		[ from_tool.DEFAULT_PT_FIGH  ] = true,
	}
	local no_create = {
		[ from_tool.DEFAULT_UI_PROPERTY ] = true,
		[ from_tool.DEFAULT_UI_SAMPLE   ] = true,
		[ from_tool.DEFAULT_UI_SIGN     ] = true,
		[ from_tool.UNKNOWN             ] = true,
	}
	local line_only = {
		[ from_tool.DEFAULT_UI_WIND ] = true,
	}
	
	local function heat_clear()
		local temp = sim.ambientAirTemp()
		for x = 0, sim.XRES / sim.CELL - 1 do
			for y = 0, sim.YRES / sim.CELL - 1 do
				sim.ambientHeat(x, y, temp)
			end
		end
	end
	
	local function stamp_load(x, y, data, reset)
		if data == "" then -- * Is this check needed at all?
			return nil, "no stamp data"
		end
		local handle = io.open(config.stamp_temp, "wb")
		if not handle then
			return nil, "cannot write stamp data"
		end
		handle:write(data)
		handle:close()
		if reset then
			sim.clearRect(0, 0, sim.XRES, sim.YRES)
			heat_clear()
			tpt.reset_velocity()
			tpt.set_pressure()
		end
		local ok, err = sim.loadStamp(config.stamp_temp, x, y)
		if not ok then
			os.remove(config.stamp_temp)
			if err then
				return nil, "cannot load stamp data: " .. err
			else
				return nil, "cannot load stamp data"
			end
		end
		os.remove(config.stamp_temp)
		return true
	end
	
	local function stamp_save(x, y, w, h)
		local name = sim.saveStamp(x, y, w - 1, h - 1)
		if not name then
			return nil, "error saving stamp"
		end
		local handle = io.open("stamps/" .. name .. ".stm", "rb")
		if not handle then
			sim.deleteStamp(name)
			return nil, "cannot read stamp data"
		end
		local data = handle:read("*a")
		handle:close()
		sim.deleteStamp(name)
		return data
	end
	
	-- * Finds bynd, the smallest idx in [first, last] for which beyond(idx)
	--   is true. Assumes that for all idx in [first, bynd-1] beyond(idx) is
	--   false and for all idx in [bynd, last] beyond(idx) is true. beyond(first-1)
	--   is implicitly false and beyond(last+1) is implicitly true, thus an
	--   all-false field yields last+1 and an all-true field yields first.
	local function binary_search_implicit(first, last, beyond)
		local function beyond_wrap(idx)
			if idx < first then
				return false
			end
			if idx > last then
				return true
			end
			return beyond(idx)
		end
		while first <= last do
			local mid = math.floor((first + last) / 2)
			if beyond_wrap(mid) then
				if beyond_wrap(mid - 1) then
					last = mid - 1
				else
					return mid
				end
			else
				first = mid + 1
			end
		end
		return first
	end
	
	local function inside_rect(pos_x, pos_y, width, height, check_x, check_y)
		return pos_x <= check_x and pos_y <= check_y and pos_x + width > check_x and pos_y + height > check_y
	end
	
	local function mouse_pos()
		return tpt.mousex, tpt.mousey
	end
	
	local function brush_size()
		return tpt.brushx, tpt.brushy
	end
	
	local function selected_tools()
		return tpt.selectedl, tpt.selecteda, tpt.selectedr, tpt.selectedreplace
	end
	
	local function wall_snap_coords(x, y)
		return math.floor(x / 4) * 4, math.floor(y / 4) * 4
	end
	
	local function line_snap_coords(x1, y1, x2, y2)
		local dx, dy = x2 - x1, y2 - y1
		if math.abs(math.floor(dx / 2)) > math.abs(dy) then
			return x2, y1
		elseif math.abs(dx) < math.abs(math.floor(dy / 2)) then
			return x1, y2
		elseif dx * dy > 0 then
			return x1 + math.floor((dx + dy) / 2), y1 + math.floor((dy + dx) / 2)
		else
			return x1 + math.floor((dx - dy) / 2), y1 + math.floor((dy - dx) / 2)
		end
	end
	
	local function rect_snap_coords(x1, y1, x2, y2)
		local dx, dy = x2 - x1, y2 - y1
		if dx * dy > 0 then
			return x1 + math.floor((dx + dy) / 2), y1 + math.floor((dy + dx) / 2)
		else
			return x1 + math.floor((dx - dy) / 2), y1 + math.floor((dy - dx) / 2)
		end
	end
	
	local function create_parts_any(x, y, rx, ry, xtype, brush, member)
		if line_only[xtype] or no_create[xtype] then
			return
		end
		local class = xid_class[xtype]
		if class == "WL" then
			if xtype == from_tool.DEFAULT_WL_STRM then
				rx, ry = 0, 0
			end
			sim.createWalls(x, y, rx, ry, xtype - xid_first.WL, brush)
			return
		elseif class == "TOOL" then
			local str = 1
			if member.kmod_s then
				str = 10
			elseif member.kmod_c then
				str = 0.1
			end
			sim.toolBrush(x, y, rx, ry, xtype - xid_first.TOOL, brush, str)
			return
		elseif class == "DECOR" then
			sim.decoBrush(x, y, rx, ry, member.deco_r, member.deco_g, member.deco_b, member.deco_a, xtype - xid_first.DECOR, brush)
			return
		elseif class == "PT_LIFE" then
			xtype = bit.bor(elem.DEFAULT_PT_LIFE, bit.lshift(xtype - xid_first.PT_LIFE, PMAPBITS))
		elseif type(xtype) == "table" and xtype.type == "cgol" then
			-- * TODO[api]: add an api for setting gol colour
			xtype = xtype.elem
		end
		local ov = create_override[xtype]
		if ov then
			rx, ry, xtype = ov(rx, ry, xtype)
		end
		local selectedreplace
		if member.bmode ~= 0 then
			selectedreplace = tpt.selectedreplace
			tpt.selectedreplace = to_tool[member.tool_x] or "DEFAULT_PT_NONE"
		end
		sim.createParts(x, y, rx, ry, xtype, brush, member.bmode)
		if member.bmode ~= 0 then
			tpt.selectedreplace = selectedreplace
		end
	end
	
	local function create_line_any(x1, y1, x2, y2, rx, ry, xtype, brush, member, cont)
		if no_create[xtype] or no_shape[xtype] or (jacobsmod and xtype == tpt.element("ball") and not member.kmod_s) then
			return
		end
		local class = xid_class[xtype]
		if class == "WL" then
			local str = 1
			if cont then
				if member.kmod_s then
					str = 10
				elseif member.kmod_c then
					str = 0.1
				end
				str = str * 5
			end
			if not cont and xtype == from_tool.DEFAULT_WL_FAN and tpt.get_wallmap(math.floor(x1 / 4), math.floor(y1 / 4)) == WL_FAN then
				local fvx = (x2 - x1) * 0.005
				local fvy = (y2 - y1) * 0.005
				local bw = sim.XRES / 4
				local bh = sim.YRES / 4
				local visit = {}
				local mark = {}
				local last = 0
				local function enqueue(x, y)
					if x >= 0 and y >= 0 and x < bw and y < bh and tpt.get_wallmap(x, y) == WL_FAN then
						local k = x + y * bw
						if not mark[k] then
							last = last + 1
							visit[last] = k
							mark[k] = true
						end
					end
				end
				enqueue(math.floor(x1 / 4), math.floor(y1 / 4))
				local curr = 1
				while visit[curr] do
					local k = visit[curr]
					local x, y = k % bw, math.floor(k / bw)
					tpt.set_wallmap(x, y, 1, 1, fvx, fvy, WL_FAN)
					enqueue(x - 1, y)
					enqueue(x, y - 1)
					enqueue(x + 1, y)
					enqueue(x, y + 1)
					curr = curr + 1
				end
				return
			end
			if xtype == from_tool.DEFAULT_WL_STRM then
				rx, ry = 0, 0
			end
			sim.createWallLine(x1, y1, x2, y2, rx, ry, xtype - xid_first.WL, brush)
			return
		elseif xtype == from_tool.DEFAULT_UI_WIND then
			local str = 1
			if cont then
				if member.kmod_s then
					str = 10
				elseif member.kmod_c then
					str = 0.1
				end
				str = str * 5
			end
			sim.toolLine(x1, y1, x2, y2, rx, ry, sim.TOOL_WIND, brush, str)
			return
		elseif class == "TOOL" then
			local str = 1
			if cont then
				if member.kmod_s then
					str = 10
				elseif member.kmod_c then
					str = 0.1
				end
			end
			sim.toolLine(x1, y1, x2, y2, rx, ry, xtype - xid_first.TOOL, brush, str)
			return
		elseif class == "DECOR" then
			sim.decoLine(x1, y1, x2, y2, rx, ry, member.deco_r, member.deco_g, member.deco_b, member.deco_a, xtype - xid_first.DECOR, brush)
			return
		elseif class == "PT_LIFE" then
			xtype = bit.bor(elem.DEFAULT_PT_LIFE, bit.lshift(xtype - xid_first.PT_LIFE, PMAPBITS))
		elseif type(xtype) == "table" and xtype.type == "cgol" then
			-- * TODO[api]: add an api for setting gol colour
			xtype = xtype.elem
		end
		local ov = create_override[xtype]
		if ov then
			rx, ry, xtype = ov(rx, ry, xtype)
		end
		local selectedreplace
		if member.bmode ~= 0 then
			selectedreplace = tpt.selectedreplace
			tpt.selectedreplace = to_tool[member.tool_x] or "DEFAULT_PT_NONE"
		end
		sim.createLine(x1, y1, x2, y2, rx, ry, xtype, brush, member.bmode)
		if member.bmode ~= 0 then
			tpt.selectedreplace = selectedreplace
		end
	end
	
	local function create_box_any(x1, y1, x2, y2, xtype, member)
		if line_only[xtype] or no_create[xtype] or no_shape[xtype] then
			return
		end
		local class = xid_class[xtype]
		if class == "WL" then
			sim.createWallBox(x1, y1, x2, y2, xtype - xid_first.WL)
			return
		elseif class == "TOOL" then
			sim.toolBox(x1, y1, x2, y2, xtype - xid_first.TOOL)
			return
		elseif class == "DECOR" then
			sim.decoBox(x1, y1, x2, y2, member.deco_r, member.deco_g, member.deco_b, member.deco_a, xtype - xid_first.DECOR)
			return
		elseif class == "PT_LIFE" then
			xtype = bit.bor(elem.DEFAULT_PT_LIFE, bit.lshift(xtype - xid_first.PT_LIFE, PMAPBITS))
		elseif type(xtype) == "table" and xtype.type == "cgol" then
			-- * TODO[api]: add an api for setting gol colour
			xtype = xtype.elem
		end
		local _
		local ov = create_override[xtype]
		if ov then
			_, _, xtype = ov(member.size_x, member.size_y, xtype)
		end
		local selectedreplace
		if member.bmode ~= 0 then
			selectedreplace = tpt.selectedreplace
			tpt.selectedreplace = to_tool[member.tool_x] or "DEFAULT_PT_NONE"
		end
		sim.createBox(x1, y1, x2, y2, xtype, member and member.bmode)
		if member.bmode ~= 0 then
			tpt.selectedreplace = selectedreplace
		end
	end
	
	local function flood_any(x, y, xtype, part_flood_hint, wall_flood_hint, member)
		if line_only[xtype] or no_create[xtype] or no_flood[xtype] then
			return
		end
		local class = xid_class[xtype]
		if class == "WL" then
			sim.floodWalls(x, y, xtype - xid_first.WL, wall_flood_hint)
			return
		elseif class == "DECOR" or class == "TOOL" then
			return
		elseif class == "PT_LIFE" then
			xtype = bit.bor(elem.DEFAULT_PT_LIFE, bit.lshift(xtype - xid_first.PT_LIFE, PMAPBITS))
		elseif type(xtype) == "table" and xtype.type == "cgol" then
			-- * TODO[api]: add an api for setting gol colour
			xtype = xtype.elem
		end
		local _
		local ov = create_override[xtype]
		if ov then
			_, _, xtype = ov(member.size_x, member.size_y, xtype)
		end
		local selectedreplace
		if member.bmode ~= 0 then
			selectedreplace = tpt.selectedreplace
			tpt.selectedreplace = to_tool[member.tool_x] or "DEFAULT_PT_NONE"
		end
		sim.floodParts(x, y, xtype, part_flood_hint, member.bmode)
		if member.bmode ~= 0 then
			tpt.selectedreplace = selectedreplace
		end
	end
	
	local function corners_to_rect(x1, y1, x2, y2)
		local xl = math.min(x1, x2)
		local yl = math.min(y1, y2)
		local xh = math.max(x1, x2)
		local yh = math.max(y1, y2)
		return xl, yl, xh - xl + 1, yh - yl + 1
	end
	
	local function escape_regex(str)
		return (str:gsub("[%$%%%(%)%*%+%-%.%?%[%^%]]", "%%%1"))
	end
	
	local function fnv1a32(data)
		local hash = 2166136261
		for i = 1, #data do
			hash = bit.bxor(hash, data:byte(i))
			hash = bit.band(bit.lshift(hash, 24), 0xFFFFFFFF) + bit.band(bit.lshift(hash, 8), 0xFFFFFFFF) + hash * 147
		end
		hash = bit.band(hash, 0xFFFFFFFF)
		return hash < 0 and (hash + 0x100000000) or hash
	end
	
	local function ambient_air_temp(temp)
		if temp then
			local set = temp / 0x400
			sim.ambientAirTemp(set)
			return set
		else
			return math.max(0x000000, math.min(0xFFFFFF, math.floor(sim.ambientAirTemp() * 0x400)))
		end
	end
	
	local function custom_gravity(x, y)
		if x then
			if x >= 0x800000 then x = x - 0x1000000 end
			if y >= 0x800000 then y = y - 0x1000000 end
			local setx, sety = x / 0x400, y / 0x400
			sim.customGravity(setx, sety)
			return setx, sety
		else
			local getx, gety = sim.customGravity()
			getx = math.max(-0x800000, math.min(0x7FFFFF, math.floor(getx * 0x400)))
			gety = math.max(-0x800000, math.min(0x7FFFFF, math.floor(gety * 0x400)))
			if getx < 0 then getx = getx + 0x1000000 end
			if gety < 0 then gety = gety + 0x1000000 end
			return getx, gety
		end
	end
	
	local function get_save_id()
		local id, hist = sim.getSaveID()
		if id and not hist then
			hist = 0
		end
		return id, hist
	end
	
	local function urlencode(str)
		return (str:gsub("[^ !'()*%-%.0-9A-Z_a-z]", function(cap)
			return ("%%%02x"):format(cap:byte())
		end))
	end
	
	local function get_name()
		local name = tpt.get_name()
		return name ~= "" and name or nil
	end
	
	return {
		get_name = get_name,
		stamp_load = stamp_load,
		stamp_save = stamp_save,
		binary_search_implicit = binary_search_implicit,
		inside_rect = inside_rect,
		mouse_pos = mouse_pos,
		brush_size = brush_size,
		selected_tools = selected_tools,
		wall_snap_coords = wall_snap_coords,
		line_snap_coords = line_snap_coords,
		rect_snap_coords = rect_snap_coords,
		create_parts_any = create_parts_any,
		create_line_any = create_line_any,
		create_box_any = create_box_any,
		flood_any = flood_any,
		from_tool = from_tool,
		to_tool = to_tool,
		create_override = create_override,
		no_flood = no_flood,
		no_shape = no_shape,
		xid_class = xid_class,
		corners_to_rect = corners_to_rect,
		escape_regex = escape_regex,
		fnv1a32 = fnv1a32,
		ambient_air_temp = ambient_air_temp,
		custom_gravity = custom_gravity,
		get_save_id = get_save_id,
		version_less = common_util.version_less,
		version_equal = common_util.version_equal,
		tpt_version = tpt_version,
		urlencode = urlencode,
		heat_clear = heat_clear,
		unknown_xid = unknown_xid,
	}
	
end

require_preload__["tptmp.client.window"] = function()

	local config  = require("tptmp.client.config")
	local colours = require("tptmp.client.colours")
	local format  = require("tptmp.client.format")
	local utf8    = require("tptmp.client.utf8")
	local util    = require("tptmp.client.util")
	local manager = require("tptmp.client.manager")
	local sdl     = require("tptmp.client.sdl")
	
	local notif_important = colours.common.notif_important
	local text_bg_high = { notif_important[1] / 2, notif_important[2] / 2, notif_important[3] / 2 }
	local text_bg_high_floating = { notif_important[1] / 3, notif_important[2] / 3, notif_important[3] / 3 }
	local text_bg = { 0, 0, 0 }
	
	local window_i = {}
	local window_m = { __index = window_i }
	
	local wrap_padding = 11 -- * Width of "* "
	
	function window_i:backlog_push_join(formatted_nick)
		self:backlog_push_str(colours.commonstr.join .. "* " .. formatted_nick .. colours.commonstr.join .. " has joined", true)
	end
	
	function window_i:backlog_push_leave(formatted_nick)
		self:backlog_push_str(colours.commonstr.leave .. "* " .. formatted_nick .. colours.commonstr.leave .. " has left", true)
	end
	
	function window_i:backlog_push_fpssync_enable(formatted_nick)
		self:backlog_push_str(colours.commonstr.fpssyncenable .. "* " .. formatted_nick .. colours.commonstr.fpssyncenable .. " has enabled FPS synchronization", true)
	end
	
	function window_i:backlog_push_fpssync_disable(formatted_nick)
		self:backlog_push_str(colours.commonstr.fpssyncdisable .. "* " .. formatted_nick .. colours.commonstr.fpssyncdisable .. " has disabled FPS synchronization", true)
	end
	
	function window_i:backlog_push_error(str)
		self:backlog_push_str(colours.commonstr.error .. "* " .. str, true)
	end
	
	function window_i:get_important_(str)
		local cli = self.client_func_()
		if cli then
			if (" " .. str .. " "):lower():find("[^a-z0-9-_]" .. cli:nick():lower() .. "[^a-z0-9-_]") then
				return "highlight"
			end
		end
	end
	
	function window_i:backlog_push_say_other(formatted_nick, str)
		self:backlog_push_say(formatted_nick, str, self:get_important_(str))
	end
	
	function window_i:backlog_push_say3rd_other(formatted_nick, str)
		self:backlog_push_say3rd(formatted_nick, str, self:get_important_(str))
	end
	
	function window_i:backlog_push_say(formatted_nick, str, important)
		self:backlog_push_str(colours.commonstr.chat .. "<" .. formatted_nick .. colours.commonstr.chat .. "> " .. str, important)
	end
	
	function window_i:backlog_push_say3rd(formatted_nick, str, important)
		self:backlog_push_str(colours.commonstr.chat .. "* " .. formatted_nick .. colours.commonstr.chat .. " " .. str, important)
	end
	
	function window_i:backlog_push_room(room, members, prefix)
		local sep = colours.commonstr.neutral .. ", "
		local collect = { colours.commonstr.neutral, "* ", prefix, format.troom(room), sep }
		if next(members) then
			table.insert(collect, "present: ")
			local first = true
			for id, member in pairs(members) do
				if first then
					first = false
				else
					table.insert(collect, sep)
				end
				table.insert(collect, member.formatted_nick)
			end
		else
			table.insert(collect, "nobody else present")
		end
		self:backlog_push_str(table.concat(collect), true)
	end
	
	function window_i:backlog_push_fpssync(members)
		local sep = colours.commonstr.neutral .. ", "
		local collect = { colours.commonstr.neutral, "* " }
		if members == true then
			table.insert(collect, "FPS synchronization is enabled")
		elseif members then
			if next(members) then
				table.insert(collect, "FPS synchronization is enabled, in sync with: ")
				local first = true
				for id, member in pairs(members) do
					if first then
						first = false
					else
						table.insert(collect, sep)
					end
					table.insert(collect, member.formatted_nick)
				end
			else
				table.insert(collect, "FPS synchronization is enabled, not in sync with anyone")
			end
		else
			table.insert(collect, "FPS synchronization is disabled")
		end
		self:backlog_push_str(table.concat(collect), true)
	end
	
	function window_i:backlog_push_registered(formatted_nick)
		self:backlog_push_str(colours.commonstr.neutral .. "* Connected as " .. formatted_nick, true)
	end
	
	local server_colours = {
		n = colours.commonstr.neutral,
		e = colours.commonstr.error,
		j = colours.commonstr.join,
		l = colours.commonstr.leave,
	}
	function window_i:backlog_push_server(str)
		local formatted = str
			:gsub("\au([A-Za-z0-9-_#]+)", function(cap) return format.nick(cap, self.nick_colour_seed_) end)
			:gsub("\ar([A-Za-z0-9-_#]+)", function(cap) return format.room(cap)                         end)
			:gsub("\a([nejl])"          , function(cap) return server_colours[cap]                      end)
		self:backlog_push_str(formatted, true)
	end
	
	function window_i:nick_colour_seed(seed)
		self.nick_colour_seed_ = seed
	end
	
	function window_i:backlog_push_neutral(str)
		self:backlog_push_str(colours.commonstr.neutral .. str, true)
	end
	
	function window_i:backlog_wrap_(msg)
		if msg == self.backlog_first_ then
			return
		end
		if msg.wrapped_to ~= self.width_ then
			local line = {}
			local wrapped = {}
			local collect = msg.collect
			local i = 0
			local word = {}
			local word_width = 0
			local line_width = 0
			local max_width = self.width_ - 8
			local line_empty = true
			local red, green, blue = 255, 255, 255
			local initial_block
			local function insert_block(block)
				if initial_block then
					table.insert(line, initial_block)
					initial_block = nil
				end
				table.insert(line, block)
			end
			local function flush_line()
				if not line_empty then
					table.insert(wrapped, table.concat(line))
					line = {}
					initial_block = colours.escape({ red, green, blue })
					line_width = wrap_padding
					line_empty = true
				end
			end
			local function flush_word()
				if #word > 0 then
					for i = 1, #word do
						insert_block(word[i])
					end
					line_empty = false
					line_width = line_width + word_width
					word = {}
					word_width = 0
				end
			end
			while i < #collect do
				i = i + 1
				if collect[i] == "\15" and i + 3 <= #collect then
					local rgb = utf8.code_points(table.concat(collect, nil, i + 1, i + 3))
					if rgb then
						for j = i, i + 3 do
							table.insert(word, collect[j])
						end
						red, green, blue = rgb[1].cp, rgb[2].cp, rgb[3].cp
					end
					i = i + 3
				else
					local i_width = gfx.textSize(collect[i])
					if collect[i]:find(config.whitespace_pattern) then
						flush_word()
						if line_width + i_width > max_width then
							flush_line()
						end
						if not line_empty then
							insert_block(collect[i])
							line_width = line_width + i_width
						end
						line_empty = false
					else
						if line_width + word_width + i_width > max_width then
							flush_line()
							if line_width + word_width + i_width > max_width then
								flush_word()
								if line_width + word_width + i_width > max_width then
									flush_line()
								end
							end
						end
						table.insert(word, collect[i])
						word_width = word_width + i_width
					end
				end
			end
			flush_word()
			flush_line()
			if #wrapped > 1 and wrapped[#wrapped] == "" then
				wrapped[#wrapped] = nil
			end
			msg.wrapped_to = self.width_
			msg.wrapped = wrapped
			self.backlog_last_wrapped_ = math.max(self.backlog_last_wrapped_, msg.unique)
		end
	end
	
	function window_i:backlog_update_()
		local max_lines = math.floor((self.height_ - 35) / 12)
		local lines_reverse = {}
		self:backlog_wrap_(self.backlog_last_visible_msg_)
		if self.backlog_auto_scroll_ then
			while self.backlog_last_visible_msg_.next ~= self.backlog_last_ do
				self.backlog_last_visible_msg_ = self.backlog_last_visible_msg_.next
			end
			self:backlog_wrap_(self.backlog_last_visible_msg_)
			self.backlog_last_visible_line_ = #self.backlog_last_visible_msg_.wrapped
		end
		self:backlog_wrap_(self.backlog_last_visible_msg_)
		self.backlog_last_visible_line_ = math.min(#self.backlog_last_visible_msg_.wrapped, self.backlog_last_visible_line_)
		local source_msg = self.backlog_last_visible_msg_
		local source_line = self.backlog_last_visible_line_
		while #lines_reverse < max_lines do
			if source_msg == self.backlog_first_ then
				break
			end
			self:insert_wrapped_line_(lines_reverse, source_msg, source_line)
			source_line = source_line - 1
			if source_line == 0 then
				source_msg = source_msg.prev
				self:backlog_wrap_(source_msg)
				source_line = #source_msg.wrapped
			end
		end
		if source_msg ~= self.backlog_first_ and source_msg.unique - 1 <= self.backlog_unique_ - config.backlog_size then
			source_msg.prev = self.backlog_first_
			self.backlog_first_.next = source_msg
		end
		local lines = {}
		for i = #lines_reverse, 1, -1 do
			table.insert(lines, lines_reverse[i])
		end
		while #lines < max_lines do
			if self.backlog_last_visible_line_ == #self.backlog_last_visible_msg_.wrapped then
				if self.backlog_last_visible_msg_.next == self.backlog_last_ then
					break
				end
				self.backlog_last_visible_msg_ = self.backlog_last_visible_msg_.next
				self:backlog_wrap_(self.backlog_last_visible_msg_)
				self.backlog_last_visible_line_ = 1
			else
				self.backlog_last_visible_line_ = self.backlog_last_visible_line_ + 1
			end
			self:insert_wrapped_line_(lines, self.backlog_last_visible_msg_, self.backlog_last_visible_line_)
		end
		self.backlog_text_ = {}
		local marker_after
		for i = 1, #lines do
			local text_width = gfx.textSize(lines[i].wrapped)
			local padding = lines[i].needs_padding and wrap_padding or 0
			local box_width = lines[i].extend_box and self.width_ or (padding + text_width + 10)
			table.insert(self.backlog_text_, {
				padding = padding,
				pushed_at = lines[i].msg.pushed_at,
				highlight = lines[i].msg.important == "highlight",
				text = lines[i].wrapped,
				box_width = box_width,
			})
			if lines[i].marker then
				marker_after = i
			end
		end
		self.backlog_lines_ = lines
		self.backlog_text_y_ = self.height_ - #lines * 12 - 15
		self.backlog_marker_y_ = self.backlog_enable_marker_ and marker_after and marker_after ~= #lines and (self.backlog_text_y_ + marker_after * 12 - 2)
	end
	
	function window_i:backlog_push_(collect, important)
		self.backlog_unique_ = self.backlog_unique_ + 1
		local msg = {
			unique = self.backlog_unique_,
			collect = collect,
			prev = self.backlog_last_.prev,
			next = self.backlog_last_,
			important = important,
			pushed_at = socket.gettime(),
		}
		self.backlog_last_.prev.next = msg
		self.backlog_last_.prev = msg
		if important then
			self.backlog_unique_important_ = self.backlog_unique_
		end
		self:backlog_update_()
	end
	
	function window_i:backlog_push_str(str, important)
		local collect = {}
		local cps = utf8.code_points(str)
		if cps then
			for i = 1, #cps do
				table.insert(collect, str:sub(cps[i].pos, cps[i].pos + cps[i].size - 1))
			end
			self:backlog_push_(collect, important)
		end
	end
	
	function window_i:backlog_bump_marker()
		self.backlog_enable_marker_ = false
		if self.backlog_last_seen_ < self.backlog_unique_ then
			self.backlog_enable_marker_ = true
			self.backlog_marker_at_ = self.backlog_last_seen_
		end
		self:backlog_update_()
	end
	
	function window_i:backlog_notif_reset()
		self.backlog_last_seen_ = self.backlog_unique_
		self:backlog_bump_marker()
	end
	
	function window_i:backlog_notif_count()
		return self.backlog_unique_ - self.backlog_last_seen_
	end
	
	function window_i:backlog_notif_important()
		return self.backlog_unique_important_ - self.backlog_last_seen_ > 0
	end
	
	function window_i:backlog_reset()
		self.backlog_unique_ = 0
		self.backlog_unique_important_ = 0
		self.backlog_last_wrapped_ = 0
		self.backlog_last_seen_ = 0
		self.backlog_marker_at_ = 0
		self.backlog_last_ = { wrapped = {}, unique = 0 }
		self.backlog_first_ = { wrapped = {} }
		self.backlog_last_.prev = self.backlog_first_
		self.backlog_first_.next = self.backlog_last_
		self.backlog_last_visible_msg_ = self.backlog_first_
		self.backlog_last_visible_line_ = 0
		self.backlog_auto_scroll_ = true
		self.backlog_enable_marker_ = false
		self:backlog_update_()
	end
	
	local close_button_off_x = -12
	local close_button_off_y = 3
	if tpt.version.jacob1s_mod then
		close_button_off_x = -11
		close_button_off_y = 4
	end
	function window_i:tick_close_()
		local border_colour = colours.appearance.inactive.border
		local close_fg = colours.appearance.inactive.text
		local close_bg
		local inside_close = util.inside_rect(self.pos_x_ + self.width_ - 15, self.pos_y_, 15, 15, util.mouse_pos())
		if self.close_active_ then
			close_fg = colours.appearance.active.text
			close_bg = colours.appearance.active.background
		elseif inside_close then
			close_fg = colours.appearance.hover.text
			close_bg = colours.appearance.hover.background
		end
		if close_bg then
			gfx.fillRect(self.pos_x_ + self.width_ - 14, self.pos_y_ + 1, 13, 13, unpack(close_bg))
		end
		gfx.drawLine(self.pos_x_ + self.width_ - 15, self.pos_y_ + 1, self.pos_x_ + self.width_ - 15, self.pos_y_ + 13, unpack(border_colour))
		gfx.drawText(self.pos_x_ + self.width_ + close_button_off_x, self.pos_y_ + close_button_off_y, utf8.encode_multiple(0xE02A), unpack(close_fg))
		if self.close_active_ and not inside_close then
			self.close_active_ = false
		end
	end
	
	function window_i:handle_tick()
		local floating = self.window_status_func_() == "floating"
		local now = socket.gettime()
	
		if self.backlog_auto_scroll_ and not floating then
			self.backlog_last_seen_ = self.backlog_last_wrapped_
		else
			if self.backlog_last_seen_ < self.backlog_unique_ and not self.backlog_enable_marker_ then
				self:backlog_bump_marker()
			end
		end
	
		if self.resizer_active_ then
			local resizer_x, resizer_y = util.mouse_pos()
			local prev_x, prev_y = self.pos_x_, self.pos_y_
			self.pos_x_ = math.min(math.max(1, self.pos_x_ + resizer_x - self.resizer_last_x_), self.pos_x_ + self.width_ - config.min_width)
			self.pos_y_ = math.min(math.max(1, self.pos_y_ + resizer_y - self.resizer_last_y_), self.pos_y_ + self.height_ - config.min_height)
			local diff_x, diff_y = self.pos_x_ - prev_x, self.pos_y_ - prev_y
			self.resizer_last_x_ = self.resizer_last_x_ + diff_x
			self.resizer_last_y_ = self.resizer_last_y_ + diff_y
			self.width_ = self.width_ - diff_x
			self.height_ = self.height_ - diff_y
			self:input_update_()
			self:backlog_update_()
			self:subtitle_update_()
			self:save_window_rect_()
		end
		if self.dragger_active_ then
			local dragger_x, dragger_y = util.mouse_pos()
			local prev_x, prev_y = self.pos_x_, self.pos_y_
			self.pos_x_ = math.min(math.max(1, self.pos_x_ + dragger_x - self.dragger_last_x_), sim.XRES - self.width_)
			self.pos_y_ = math.min(math.max(1, self.pos_y_ + dragger_y - self.dragger_last_y_), sim.YRES - self.height_)
			local diff_x, diff_y = self.pos_x_ - prev_x, self.pos_y_ - prev_y
			self.dragger_last_x_ = self.dragger_last_x_ + diff_x
			self.dragger_last_y_ = self.dragger_last_y_ + diff_y
			self:save_window_rect_()
		end
	
		local border_colour = colours.appearance[self.in_focus and "active" or "inactive"].border
		local background_colour = colours.appearance.inactive.background
		if not floating then
			gfx.fillRect(self.pos_x_ + 1, self.pos_y_ + 1, self.width_ - 2, self.height_ - 2, background_colour[1], background_colour[2], background_colour[3], self.alpha_)
			gfx.drawRect(self.pos_x_, self.pos_y_, self.width_, self.height_, unpack(border_colour))
	
			self:tick_close_()
	
			local subtitle_blue = 255
			if #self.input_collect_ > 0 and self.input_last_say_ + config.message_interval >= now then
				subtitle_blue = 0
			end
			gfx.drawText(self.pos_x_ + 18, self.pos_y_ + 4, self.subtitle_text_, 255, 255, subtitle_blue)
	
			gfx.drawText(self.pos_x_ + self.width_ - self.title_width_ - 17, self.pos_y_ + 4, self.title_)
			for i = 1, 3 do
				gfx.drawLine(self.pos_x_ + i * 3 + 1, self.pos_y_ + 3, self.pos_x_ + 3, self.pos_y_ + i * 3 + 1, unpack(border_colour))
			end
			gfx.drawLine(self.pos_x_ + 1, self.pos_y_ + 14, self.pos_x_ + self.width_ - 2, self.pos_y_ + 14, unpack(border_colour))
			gfx.drawLine(self.pos_x_ + 14, self.pos_y_ + 1, self.pos_x_ + 14, self.pos_y_ + 13, unpack(border_colour))
		end
	
		local prev_text, prev_fades_at, prev_alpha, prev_box_width, prev_highlight
		for i = 1, #self.backlog_text_ + 1 do
			local fades_at, alpha, box_width, highlight
			if self.backlog_text_[i] then
				fades_at = self.backlog_text_[i].pushed_at + config.floating_linger_time + config.floating_fade_time
				alpha = math.max(0, math.min(1, (fades_at - now) / config.floating_fade_time))
				box_width = self.backlog_text_[i].box_width
				highlight = self.backlog_text_[i].highlight
			end
			if not prev_fades_at then
				prev_fades_at, prev_alpha, prev_box_width, prev_highlight = fades_at, alpha, box_width, highlight
			elseif not fades_at then
				fades_at, alpha, box_width, highlight = prev_fades_at, prev_alpha, prev_box_width, prev_highlight
			end
	
			local comm_box_width = math.max(box_width, prev_box_width)
			local min_box_width = math.min(box_width, prev_box_width)
			local comm_fades_at = math.max(fades_at, prev_fades_at)
			local comm_alpha = math.max(alpha, prev_alpha)
			local comm_highlight = highlight or prev_highlight
			local diff_fades_at = prev_fades_at
			local diff_alpha = prev_alpha
			local diff_highlight = prev_highlight
			if box_width > prev_box_width then
				diff_fades_at = fades_at
				diff_alpha = alpha
				diff_highlight = highlight
			end
			if floating and diff_fades_at > now then
				local rgb = diff_highlight and text_bg_high_floating or text_bg
				gfx.fillRect(self.pos_x_ - 1 + min_box_width, self.pos_y_ + self.backlog_text_y_ + i * 12 - 15, comm_box_width - min_box_width, 2, rgb[1], rgb[2], rgb[3], diff_alpha * self.alpha_)
			end
			if floating and comm_fades_at > now then
				local rgb = comm_highlight and text_bg_high_floating or text_bg
				local alpha = 1
				if not highlight and prev_alpha < comm_alpha then
					alpha = prev_alpha
				end
				gfx.fillRect(self.pos_x_ - 1, self.pos_y_ + self.backlog_text_y_ + i * 12 - 15, min_box_width, 2, alpha * rgb[1], alpha * rgb[2], alpha * rgb[3], comm_alpha * self.alpha_)
			end
	
			if prev_text then
				local alpha = 1
				if floating then
					alpha = math.min(1, (prev_fades_at - now) / config.floating_fade_time)
				end
				if floating and prev_fades_at > now then
					local rgb = prev_highlight and text_bg_high_floating or text_bg
					gfx.fillRect(self.pos_x_ - 1, self.pos_y_ + self.backlog_text_y_ + i * 12 - 25, prev_box_width, 10, rgb[1], rgb[2], rgb[3], alpha * self.alpha_)
				end
				if not floating and prev_highlight then
					gfx.fillRect(self.pos_x_ + 1, self.pos_y_ + self.backlog_text_y_ + i * 12 - 26, self.width_ - 2, 12, text_bg_high[1], text_bg_high[2], text_bg_high[3], alpha * self.alpha_)
				end
				if not floating or prev_fades_at > now then
					gfx.drawText(self.pos_x_ + 4 + prev_text.padding, self.pos_y_ + self.backlog_text_y_ + i * 12 - 24, prev_text.text, 255, 255, 255, alpha * 255)
				end
			end
			prev_text, prev_alpha, prev_fades_at, prev_box_width, prev_highlight = self.backlog_text_[i], alpha, fades_at, box_width, highlight
		end
	
		if not floating then
			if self.backlog_marker_y_ then
				gfx.drawLine(self.pos_x_ + 1, self.pos_y_ + self.backlog_marker_y_, self.pos_x_ + self.width_ - 2, self.pos_y_ + self.backlog_marker_y_, unpack(notif_important))
			end
	
			gfx.drawLine(self.pos_x_ + 1, self.pos_y_ + self.height_ - 15, self.pos_x_ + self.width_ - 2, self.pos_y_ + self.height_ - 15, unpack(border_colour))
			if self.input_has_selection_ then
				gfx.fillRect(self.pos_x_ + self.input_sel_low_x_ + self.input_scroll_x_, self.pos_y_ + self.height_ - 13, self.input_sel_high_x_ - self.input_sel_low_x_, 11)
			end
			gfx.drawText(self.pos_x_ + 4 + self.input_text_1x_, self.pos_y_ + self.height_ - 11, self.input_text_1_)
			gfx.drawText(self.pos_x_ + 4 + self.input_text_2x_, self.pos_y_ + self.height_ - 11, self.input_text_2_, 0, 0, 0)
			gfx.drawText(self.pos_x_ + 4 + self.input_text_3x_, self.pos_y_ + self.height_ - 11, self.input_text_3_)
			if self.in_focus and now % 1 < 0.5 then
				gfx.drawLine(self.pos_x_ + self.input_cursor_x_ + self.input_scroll_x_, self.pos_y_ + self.height_ - 13, self.pos_x_ + self.input_cursor_x_ + self.input_scroll_x_, self.pos_y_ + self.height_ - 3)
			end
		end
	end
	
	function window_i:handle_mousedown(px, py, button)
		if self.should_ignore_mouse_func_() then
			return
		end
		-- * TODO[opt]: mouse selection
		if button == sdl.SDL_BUTTON_LEFT then
			if util.inside_rect(self.pos_x_, self.pos_y_, self.width_, self.height_, util.mouse_pos()) then
				self.in_focus = true
			end
			if util.inside_rect(self.pos_x_, self.pos_y_, 15, 15, util.mouse_pos()) then
				self.resizer_active_ = true
				self.resizer_last_x_, self.resizer_last_y_ = util.mouse_pos()
				return true
			end
			if util.inside_rect(self.pos_x_ + 15, self.pos_y_, self.width_ - 30, 15, util.mouse_pos()) then
				self.dragger_active_ = true
				self.dragger_last_x_, self.dragger_last_y_ = util.mouse_pos()
				return true
			end
			if util.inside_rect(self.pos_x_ + self.width_ - 15, self.pos_y_, 15, 15, util.mouse_pos()) then
				self.close_active_ = true
				return true
			end
		elseif button == sdl.SDL_BUTTON_RIGHT then
			if util.inside_rect(self.pos_x_ + 1, self.pos_y_ + 15, self.width_ - 2, self.height_ - 30, util.mouse_pos()) then
				local _, y = util.mouse_pos()
				local line = 1 + math.floor((y - self.backlog_text_y_ - self.pos_y_) / 12)
				if self.backlog_lines_[line] then
					local collect = self.backlog_lines_[line].msg.collect
					local collect_sane = {}
					local i = 0
					while i < #collect do
						i = i + 1
						if collect[i] == "\15" then
							i = i + 3
						elseif collect[i]:byte() >= 32 then
							table.insert(collect_sane, collect[i])
						end
					end
					plat.clipboardPaste(table.concat(collect_sane))
					self.log_event_func_("Message copied to clipboard")
				end
				return true
			end
		end
		if util.inside_rect(self.pos_x_, self.pos_y_, self.width_, self.height_, util.mouse_pos()) then
			return true
		elseif self.in_focus then
			self.in_focus = false
		end
	end
	
	function window_i:handle_mouseup(px, py, button)
		if button == sdl.SDL_BUTTON_LEFT then
			if self.close_active_ then
				self.hide_window_func_()
			end
			self.resizer_active_ = false
			self.dragger_active_ = false
			self.close_active_ = false
		end
	end
	
	function window_i:handle_mousewheel(px, py, dir)
		if util.inside_rect(self.pos_x_, self.pos_y_ + 15, self.width_, self.height_ - 30, util.mouse_pos()) then
			self:backlog_wrap_(self.backlog_last_visible_msg_)
			while dir > 0 do
				if self.backlog_last_visible_line_ > 1 then
					self.backlog_last_visible_line_ = self.backlog_last_visible_line_ - 1
					self.backlog_auto_scroll_ = false
				elseif self.backlog_last_visible_msg_ ~= self.backlog_first_ then
					self.backlog_last_visible_msg_ = self.backlog_last_visible_msg_.prev
					self:backlog_wrap_(self.backlog_last_visible_msg_)
					self.backlog_last_visible_line_ = #self.backlog_last_visible_msg_.wrapped
					self.backlog_auto_scroll_ = false
				end
				dir = dir - 1
			end
			while dir < 0 do
				if self.backlog_last_visible_line_ < #self.backlog_last_visible_msg_.wrapped then
					self.backlog_last_visible_line_ = self.backlog_last_visible_line_ + 1
				elseif self.backlog_last_visible_msg_.next ~= self.backlog_last_ then
					self.backlog_last_visible_msg_ = self.backlog_last_visible_msg_.next
					self.backlog_last_visible_line_ = 1
				end
				self:backlog_wrap_(self.backlog_last_visible_msg_)
				if self.backlog_last_visible_msg_.next == self.backlog_last_ and self.backlog_last_visible_line_ == #self.backlog_last_visible_msg_.wrapped then
					self.backlog_auto_scroll_ = true
				end
				dir = dir + 1
			end
			self:backlog_update_()
			return true
		end
		if util.inside_rect(self.pos_x_, self.pos_y_, self.width_, self.height_, util.mouse_pos()) then
			return true
		end
	end
	
	local modkey_scan = {
		[ sdl.SDL_SCANCODE_LCTRL  ] = true,
		[ sdl.SDL_SCANCODE_LSHIFT ] = true,
		[ sdl.SDL_SCANCODE_LALT   ] = true,
		[ sdl.SDL_SCANCODE_RCTRL  ] = true,
		[ sdl.SDL_SCANCODE_RSHIFT ] = true,
		[ sdl.SDL_SCANCODE_RALT   ] = true,
	}
	function window_i:handle_keypress(key, scan, rep, shift, ctrl, alt)
		if not self.in_focus and self.window_status_func_() == "shown" and scan == sdl.SDL_SCANCODE_RETURN then
			self.in_focus = true
			return true
		end
		if self.in_focus then
			if not ctrl and not alt and scan == sdl.SDL_SCANCODE_ESCAPE then
				if self.in_focus then
					self.in_focus = false
					self.input_autocomplete_ = nil
					local force_hide = false
					if self.hide_when_chat_done then
						self.hide_when_chat_done = false
						force_hide = true
						self:input_reset_()
					end
					if shift or force_hide then
						self.hide_window_func_()
					end
				else
					self.in_focus = true
				end
			elseif not ctrl and not shift and not alt and scan == sdl.SDL_SCANCODE_TAB then
				local left_word_first, left_word
				local cursor = self.input_cursor_
				local check_offset = 0
				while self.input_collect_[cursor + check_offset] and not self.input_collect_[cursor + check_offset]:find(config.whitespace_pattern) do
					check_offset = check_offset - 1
				end
				if check_offset < 0 then
					left_word_first = cursor + check_offset + 1
					left_word = table.concat(self.input_collect_, "", left_word_first, cursor)
				end
				local cli = self.client_func_()
				if left_word and cli then
					left_word = left_word:lower()
					if self.input_autocomplete_ and not left_word:find("^" .. util.escape_regex(self.input_autocomplete_)) then
						self.input_autocomplete_ = nil
					end
					if not self.input_autocomplete_ then
						self.input_autocomplete_ = left_word
					end
					local nicks = {}
					local function try_complete(nick)
						if nick:lower():find("^" .. util.escape_regex(self.input_autocomplete_)) then
							table.insert(nicks, nick)
						end
					end
					try_complete(cli:nick())
					for _, member in pairs(cli.id_to_member) do
						try_complete(member.nick)
					end
					if next(nicks) then
						table.sort(nicks)
						local index = 1
						for i = 1, #nicks do
							if nicks[i]:lower() == left_word and nicks[i + 1] then
								index = i + 1
							end
						end
						self.input_sel_first_ = left_word_first - 1
						self.input_sel_second_ = cursor
						self:input_update_()
						self:input_insert_(nicks[index])
					end
				else
					self.input_autocomplete_ = nil
				end
			elseif not shift and not alt and (scan == sdl.SDL_SCANCODE_BACKSPACE or scan == sdl.SDL_SCANCODE_DELETE) then
				local start, length
				if self.input_has_selection_ then
					start = self.input_sel_low_
					length = self.input_sel_high_ - self.input_sel_low_
					self.input_cursor_ = self.input_sel_low_
				elseif (scan == sdl.SDL_SCANCODE_BACKSPACE and self.input_cursor_ > 0) or (scan == sdl.SDL_SCANCODE_DELETE and self.input_cursor_ < #self.input_collect_) then
					if ctrl then
						local cursor_step = scan == sdl.SDL_SCANCODE_DELETE and 1 or -1
						local check_offset = scan == sdl.SDL_SCANCODE_DELETE and 1 or  0
						local cursor = self.input_cursor_
						while self.input_collect_[cursor + check_offset] and self.input_collect_[cursor + check_offset]:find(config.whitespace_pattern) do
							cursor = cursor + cursor_step
						end
						while self.input_collect_[cursor + check_offset] and self.input_collect_[cursor + check_offset]:find(config.word_pattern) do
							cursor = cursor + cursor_step
						end
						if cursor == self.input_cursor_ then
							cursor = cursor + cursor_step
						end
						start = self.input_cursor_
						length = cursor - self.input_cursor_
						if length < 0 then
							start = start + length
							length = -length
						end
						self.input_cursor_ = start
					else
						if scan == sdl.SDL_SCANCODE_BACKSPACE then
							self.input_cursor_ = self.input_cursor_ - 1
						end
						start = self.input_cursor_
						length = 1
					end
				end
				if start then
					self:input_remove_(start, length)
					self:input_update_()
				end
				self.input_autocomplete_ = nil
			elseif not ctrl and not shift and not alt and scan == sdl.SDL_SCANCODE_RETURN then
				if #self.input_collect_ > 0 then
					local str = self:input_text_to_send_()
					local sent = str ~= "" and not self.message_overlong_
					if sent then
						local cli = self.client_func_()
						if self.localcmd and self.localcmd:parse(str) then
							-- * Nothing.
						elseif cli then
							local cps = utf8.code_points(str)
							local last = 0
							for i = 1, #cps do
								local new_last = cps[i].pos + cps[i].size - 1
								if new_last > config.message_size then
									break
								end
								last = new_last
							end
							local now = socket.gettime()
							if self.input_last_say_ + config.message_interval >= now then
								sent = false
							else
								self.input_last_say_  = now
								local limited_str = str:sub(1, last)
								self:backlog_push_say(cli:formatted_nick(), limited_str:gsub("^//", "/"))
								cli:send_say(limited_str)
							end
						else
							self:backlog_push_error("Not connected, message not sent")
						end
					end
					if sent then
						self.input_history_[self.input_history_next_] = self.input_editing_[self.input_history_select_]
						self.input_history_next_ = self.input_history_next_ + 1
						self.input_history_[self.input_history_next_] = {}
						self.input_history_[self.input_history_next_ - config.history_size] = nil
						self:input_reset_()
						if self.hide_when_chat_done then
							self.hide_when_chat_done = false
							self.in_focus = false
							self.hide_window_func_()
						end
					end
				else
					self.in_focus = false
				end
				self.input_autocomplete_ = nil
			elseif not ctrl and not shift and not alt and scan == sdl.SDL_SCANCODE_UP then
				local to_select = self.input_history_select_ - 1
				if self.input_history_[to_select] then
					self:input_select_(to_select)
				end
				self.input_autocomplete_ = nil
			elseif not ctrl and not shift and not alt and scan == sdl.SDL_SCANCODE_DOWN then
				local to_select = self.input_history_select_ + 1
				if self.input_history_[to_select] then
					self:input_select_(to_select)
				end
				self.input_autocomplete_ = nil
			elseif not alt and (scan == sdl.SDL_SCANCODE_HOME or scan == sdl.SDL_SCANCODE_END or scan == sdl.SDL_SCANCODE_RIGHT or scan == sdl.SDL_SCANCODE_LEFT) then
				self.input_cursor_prev_ = self.input_cursor_
				if scan == sdl.SDL_SCANCODE_HOME then
					self.input_cursor_ = 0
				elseif scan == sdl.SDL_SCANCODE_END then
					self.input_cursor_ = #self.input_collect_
				else
					if (scan == sdl.SDL_SCANCODE_RIGHT and self.input_cursor_ < #self.input_collect_) or (scan == sdl.SDL_SCANCODE_LEFT and self.input_cursor_ > 0) then
						local cursor_step = scan == sdl.SDL_SCANCODE_RIGHT and 1 or -1
						local check_offset = scan == sdl.SDL_SCANCODE_RIGHT and 1 or  0
						if ctrl then
							local cursor = self.input_cursor_
							while self.input_collect_[cursor + check_offset] and self.input_collect_[cursor + check_offset]:find(config.whitespace_pattern) do
								cursor = cursor + cursor_step
							end
							while self.input_collect_[cursor + check_offset] and self.input_collect_[cursor + check_offset]:find(config.word_pattern) do
								cursor = cursor + cursor_step
							end
							if cursor == self.input_cursor_ then
								cursor = cursor + cursor_step
							end
							self.input_cursor_ = cursor
						else
							self.input_cursor_ = self.input_cursor_ + cursor_step
						end
					end
				end
				if shift then
					if self.input_sel_first_ == self.input_sel_second_ then
						self.input_sel_first_ = self.input_cursor_prev_
					end
				else
					self.input_sel_first_ = self.input_cursor_
				end
				self.input_sel_second_ = self.input_cursor_
				self:input_update_()
				self.input_autocomplete_ = nil
			elseif ctrl and not shift and not alt and scan == sdl.SDL_SCANCODE_A then
				self.input_cursor_ = #self.input_collect_
				self.input_sel_first_ = 0
				self.input_sel_second_ = self.input_cursor_
				self:input_update_()
				self.input_autocomplete_ = nil
			elseif ctrl and not shift and not alt and scan == sdl.SDL_SCANCODE_C then
				if self.input_has_selection_ then
					plat.clipboardPaste(self:input_collect_range_(self.input_sel_low_ + 1, self.input_sel_high_))
				end
				self.input_autocomplete_ = nil
			elseif ctrl and not shift and not alt and scan == sdl.SDL_SCANCODE_V then
				local text = plat.clipboardCopy()
				if text then
					self:input_insert_(text)
				end
				self.input_autocomplete_ = nil
			elseif ctrl and not shift and not alt and scan == sdl.SDL_SCANCODE_X then
				if self.input_has_selection_ then
					local start = self.input_sel_low_
					local length = self.input_sel_high_ - self.input_sel_low_
					self.input_cursor_ = self.input_sel_low_
					plat.clipboardPaste(self:input_collect_range_(self.input_sel_low_ + 1, self.input_sel_high_))
					self:input_remove_(start, length)
					self:input_update_()
				end
				self.input_autocomplete_ = nil
			end
			return not modkey_scan[scan]
		else
			if not ctrl and not alt and scan == sdl.SDL_SCANCODE_ESCAPE then
				self.hide_window_func_()
				return true
			end
		end
	end
	
	function window_i:handle_keyrelease(key, scan, rep, shift, ctrl, alt)
		if self.in_focus then
			return not modkey_scan[scan]
		end
	end
	
	function window_i:handle_textinput(text)
		if self.in_focus then
			self:input_insert_(text)
			self.input_autocomplete_ = nil
			return true
		end
	end
	
	function window_i:handle_textediting(text)
		if self.in_focus then
			return true
		end
	end
	
	function window_i:handle_blur()
	end
	
	function window_i:save_window_rect_()
		manager.set("windowLeft", tostring(self.pos_x_))
		manager.set("windowTop", tostring(self.pos_y_))
		manager.set("windowWidth", tostring(self.width_))
		manager.set("windowHeight", tostring(self.height_))
		manager.set("windowAlpha", tostring(self.alpha_))
	end
	
	function window_i:insert_wrapped_line_(tbl, msg, line)
		table.insert(tbl, {
			wrapped = msg.wrapped[line],
			needs_padding = line > 1,
			extend_box = line < #msg.wrapped,
			msg = msg,
			marker = self.backlog_marker_at_ == msg.unique and #msg.wrapped == line,
		})
	end
	
	local function set_size_clamp(new_width, new_height, new_pos_x, new_pos_y)
		local width = math.min(math.max(new_width, config.min_width), sim.XRES - 1)
		local height = math.min(math.max(new_height, config.min_height), sim.YRES - 1)
		local pos_x = math.min(math.max(1, new_pos_x), sim.XRES - width)
		local pos_y = math.min(math.max(1, new_pos_y), sim.YRES - height)
		return width, height, pos_x, pos_y
	end
	
	function window_i:set_size(new_width, new_height)
		self.width_, self.height_, self.pos_x_, self.pos_y_ = set_size_clamp(new_width, new_height, self.pos_x_, self.pos_y_)
		self:input_update_()
		self:backlog_update_()
		self:subtitle_update_()
		self:save_window_rect_()
	end
	
	function window_i:subtitle_update_()
		self.subtitle_text_ = self.subtitle_secondary_ or self.subtitle_ or ""
		local max_width = self.width_ - self.title_width_ - 43
		if gfx.textSize(self.subtitle_text_) > max_width then
			self.subtitle_text_ = self.subtitle_text_:sub(1, util.binary_search_implicit(1, #self.subtitle_text_, function(idx)
				local str = self.subtitle_text_:sub(1, idx)
				str = str:gsub("\15[\194\195].", "\15"):gsub("\15[^\128-\255]", "\15")
				str = str:gsub("\15[\194\195].", "\15"):gsub("\15[^\128-\255]", "\15")
				str = str:gsub("\15[\194\195].", "\15"):gsub("\15[^\128-\255]", "\15")
				str = str:gsub("\15", "")
				return gfx.textSize(str .. "...") > max_width
			end) - 1) .. "..."
		end
	end
	
	function window_i:input_select_(history_index)
		self.input_history_select_ = history_index
		local editing = self.input_editing_[history_index]
		if not editing then
			editing = {}
			local original = self.input_history_[history_index]
			for i = 1, #original do
				editing[i] = original[i]
			end
			self.input_editing_[history_index] = editing
		end
		self.input_collect_ = editing
		self.input_cursor_ = #self.input_collect_
		self.input_sel_first_ = self.input_cursor_
		self.input_sel_second_ = self.input_cursor_
		self:input_update_()
	end
	
	function window_i:input_reset_()
		self.input_editing_ = {}
		self:input_select_(self.input_history_next_)
	end
	
	function window_i:input_remove_(start, length)
		for i = start + 1, #self.input_collect_ - length do
			self.input_collect_[i] = self.input_collect_[i + length]
		end
		for i = #self.input_collect_, #self.input_collect_ - length + 1, -1 do
			self.input_collect_[i] = nil
		end
		self.input_sel_first_ = self.input_cursor_
		self.input_sel_second_ = self.input_cursor_
	end
	
	function window_i:input_insert_(text)
		local cps = {}
		local unfiltered_cps = utf8.code_points(text)
		if unfiltered_cps then
			for i = 1, #unfiltered_cps do
				if unfiltered_cps[i].cp >= 32 then
					table.insert(cps, unfiltered_cps[i])
				end
			end
		end
		if #cps > 0 then
			if self.input_has_selection_ then
				local start = self.input_sel_low_
				local length = self.input_sel_high_ - self.input_sel_low_
				self.input_cursor_ = self.input_sel_low_
				self:input_remove_(start, length)
			end
			for i = #self.input_collect_, self.input_cursor_ + 1, -1 do
				self.input_collect_[i + #cps] = self.input_collect_[i]
			end
			for i = 1, #cps do
				self.input_collect_[self.input_cursor_ + i] = text:sub(cps[i].pos, cps[i].pos + cps[i].size - 1)
			end
			self.input_cursor_ = self.input_cursor_ + #cps
			self:input_update_()
		end
	end
	
	function window_i:input_clamp_text_(start, first, last)
		local shave_off_left = -start
		local shave_off_right = gfx.textSize(self:input_collect_range_(first, last)) + start - self.width_ + 10
		local new_first = util.binary_search_implicit(first, last, function(pos)
			return gfx.textSize(self:input_collect_range_(first, pos - 1)) >= shave_off_left
		end)
		local new_last = util.binary_search_implicit(first, last, function(pos)
			return gfx.textSize(self:input_collect_range_(pos, last)) < shave_off_right
		end) - 1
		local new_start = start + gfx.textSize(self:input_collect_range_(first, new_first - 1))
		return new_start, self:input_collect_range_(new_first, new_last)
	end
	
	function window_i:input_update_()
		self.input_sel_low_ = math.min(self.input_sel_first_, self.input_sel_second_)
		self.input_sel_high_ = math.max(self.input_sel_first_, self.input_sel_second_)
		self.input_text_1_ = self:input_collect_range_(1, self.input_sel_low_)
		self.input_text_1w_ = gfx.textSize(self.input_text_1_)
		self.input_text_2_ = self:input_collect_range_(self.input_sel_low_ + 1, self.input_sel_high_)
		self.input_text_2w_ = gfx.textSize(self.input_text_2_)
		self.input_text_3_ = self:input_collect_range_(self.input_sel_high_ + 1, #self.input_collect_)
		self.input_text_3w_ = gfx.textSize(self.input_text_3_)
		self.input_cursor_x_ = 4 + gfx.textSize(self:input_collect_range_(1, self.input_cursor_))
		self.input_sel_low_x_ = 3 + self.input_text_1w_
		self.input_sel_high_x_ = self.input_sel_low_x_ + 1 + self.input_text_2w_
		self.input_has_selection_ = self.input_sel_first_ ~= self.input_sel_second_
		local min_cursor_x = 4
		local max_cursor_x = self.width_ - 5
		if self.input_cursor_x_ + self.input_scroll_x_ < min_cursor_x then
			self.input_scroll_x_ = min_cursor_x - self.input_cursor_x_
		end
		if self.input_cursor_x_ + self.input_scroll_x_ > max_cursor_x then
			self.input_scroll_x_ = max_cursor_x - self.input_cursor_x_
		end
		local min_if_active = self.width_ - self.input_text_1w_ - self.input_text_2w_ - self.input_text_3w_ - 9
		if self.input_scroll_x_ < 0 and self.input_scroll_x_ < min_if_active then
			self.input_scroll_x_ = min_if_active
		end
		if min_if_active > 0 then
			self.input_scroll_x_ = 0
		end
		if self.input_sel_low_x_ < 1 - self.input_scroll_x_ then
			self.input_sel_low_x_ = 1 - self.input_scroll_x_
		end
		if self.input_sel_high_x_ > self.width_ - self.input_scroll_x_ - 1 then
			self.input_sel_high_x_ = self.width_ - self.input_scroll_x_ - 1
		end
		self.input_text_1x_ = self.input_scroll_x_
		self.input_text_2x_ = self.input_text_1x_ + self.input_text_1w_
		self.input_text_3x_ = self.input_text_2x_ + self.input_text_2w_
		self.input_text_1x_, self.input_text_1_ = self:input_clamp_text_(self.input_text_1x_, 1, self.input_sel_low_)
		self.input_text_2x_, self.input_text_2_ = self:input_clamp_text_(self.input_text_2x_, self.input_sel_low_ + 1, self.input_sel_high_)
		self.input_text_3x_, self.input_text_3_ = self:input_clamp_text_(self.input_text_3x_, self.input_sel_high_ + 1, #self.input_collect_)
		self:set_subtitle_secondary(self:input_status_())
	end
	
	function window_i:input_text_to_send_()
		return self:input_collect_range_():gsub("[\1-\31]", ""):gsub("^ *(.-) *$", "%1")
	end
	
	function window_i:input_status_()
		if #self.input_collect_ == 0 then
			return
		end
		local str = self:input_text_to_send_()
		local max_size = config.message_size
		if str:find("^/") and not str:find("^//") then
			max_size = 255
		end
		local byte_length = #str
		local bytes_left = max_size - byte_length
		if bytes_left < 0 then
			self.message_overlong_ = true
			return colours.commonstr.error .. tostring(bytes_left)
		else
			self.message_overlong_ = nil
			return tostring(bytes_left)
		end
	end
	
	function window_i:input_collect_range_(first, last)
		return table.concat(self.input_collect_, nil, first, last)
	end
	
	function window_i:set_subtitle(template, text)
		if template == "status" then
			self.subtitle_ = colours.commonstr.status .. text
		elseif template == "room" then
			self.subtitle_ = "In " .. format.troom(text)
		end
		self:subtitle_update_()
	end
	
	function window_i:set_subtitle_secondary(formatted_text)
		self.subtitle_secondary_ = formatted_text
		self:subtitle_update_()
	end
	
	local function new(params)
		local width, height, pos_x, pos_y = set_size_clamp(
			tonumber(manager.get("windowWidth", "")) or config.default_width,
			tonumber(manager.get("windowHeight", "")) or config.default_height,
			tonumber(manager.get("windowLeft", "")) or config.default_x,
			tonumber(manager.get("windowTop", "")) or config.default_y
		)
		local alpha = tonumber(manager.get("windowAlpha", "")) or config.default_alpha
		local title = "TPT Multiplayer " .. config.versionstr
		local title_width = gfx.textSize(title)
		local win = setmetatable({
			in_focus = false,
			pos_x_ = pos_x,
			pos_y_ = pos_y,
			width_ = width,
			height_ = height,
			alpha_ = alpha,
			title_ = title,
			title_width_ = title_width,
			input_scroll_x_ = 0,
			resizer_active_ = false,
			dragger_active_ = false,
			close_active_ = false,
			window_status_func_ = params.window_status_func,
			log_event_func_ = params.log_event_func,
			client_func_ = params.client_func,
			hide_window_func_ = params.hide_window_func,
			should_ignore_mouse_func_ = params.should_ignore_mouse_func,
			input_history_ = { {} },
			input_history_next_ = 1,
			input_editing_ = {},
			input_last_say_ = 0,
			nick_colour_seed_ = 0,
			hide_when_chat_done = false,
		}, window_m)
		win:input_reset_()
		win:backlog_reset()
		return win
	end
	
	return {
		new = new,
	}
	
end

require_preload__["tptmp.common.buffer_list"] = function()

	local buffer_list_i = {}
	local buffer_list_m = { __index = buffer_list_i }
	
	function buffer_list_i:push(data)
		local count = #data
		local want = count
		if self.limit then
			want = math.min(want, self.limit - self:pending())
		end
		if want > 0 then
			local buf = {
				data = data,
				curr = 0,
				last = want,
				prev = self.last_.prev,
				next = self.last_,
			}
			self.last_.prev.next = buf
			self.last_.prev = buf
			self.pushed_ = self.pushed_ + want
		end
		return want, count
	end
	
	function buffer_list_i:next()
		local buf = self.first_.next
		if buf == self.last_ then
			return
		end
		return buf.data, buf.curr + 1, buf.last
	end
	
	function buffer_list_i:pop(count)
		local buf = self.first_.next
		assert(buf ~= self.last_)
		assert(buf.last - buf.curr >= count)
		buf.curr = buf.curr + count
		if buf.curr == buf.last then
			buf.prev.next = buf.next
			buf.next.prev = buf.prev
		end
		self.popped_ = self.popped_ + count
	end
	
	function buffer_list_i:pushed()
		return self.pushed_
	end
	
	function buffer_list_i:popped()
		return self.popped_
	end
	
	function buffer_list_i:pending()
		return self.pushed_ - self.popped_
	end
	
	function buffer_list_i:get(count)
		assert(count <= self.pushed_ - self.popped_)
		local collect = {}
		while count > 0 do
			local data, first, last = self:next()
			local want = math.min(count, last - first + 1)
			local want_last = first - 1 + want
			table.insert(collect, first == 1 and want_last == #data and data or data:sub(first, want_last))
			self:pop(want)
			count = count - want
		end
		return table.concat(collect)
	end
	
	local function new(params)
		local bl = setmetatable({
			first_ = {},
			last_ = {},
			limit = params.limit,
			pushed_ = 0,
			popped_ = 0,
		}, buffer_list_m)
		bl.first_.next = bl.last_
		bl.last_.prev = bl.first_
		return bl
	end
	
	return {
		new = new,
	}
	
end

require_preload__["tptmp.common.command_parser"] = function()

	local command_parser_i = {}
	local command_parser_m = { __index = command_parser_i }
	
	function command_parser_i:parse(ctx, message)
		local words = {}
		local offsets = {}
		for offset, word in message:gmatch("()(%S+)") do
			table.insert(offsets, offset)
			table.insert(words, word)
		end
		if not words[1] then
			self:list_(ctx)
			return
		end
		local initial_cmd = words[1]
		words[1] = words[1]:lower()
		while true do
			local cmd = self.commands_[self.aliases_[words[1]] or words[1]]
			if not cmd then
				if self.cmd_fallback_ then
					if self.cmd_fallback_(ctx, message) then
						return
					end
				end
				self.respond_(ctx, self.unknown_format_)
				return
			end
			if cmd.macro then
				words = cmd.macro(ctx, message, words, offsets)
				if not words then
					self:help_(ctx, initial_cmd)
					return
				end
				if #words == 0 then
					return
				end
				words[1] = words[1]:lower()
				offsets = {}
				local offset = 0
				for i = 1, #words do
					offsets[i] = offset + 1
					offset = offset + #words[i] + 1
				end
				message = table.concat(words, " ")
			else
				local ok = cmd.func(ctx, message, words, offsets)
				if not ok then
					self:help_(ctx, initial_cmd)
				end
				return
			end
		end
	end
	
	function command_parser_i:list_(ctx)
		self.respond_(ctx, self.list_format_:format(self.list_str_))
		if self.list_extra_ then
			self.list_extra_(ctx)
		end
		return true
	end
	
	function command_parser_i:help_(ctx, from)
		from = from or self.help_name_
		local initial_from = from
		from = from:lower()
		local to = self.aliases_[from]
		if to then
			self.respond_(ctx, self.alias_format_:format(from, to))
			from = to
		end
		local cmd = self.commands_[from]
		if cmd then
			self.respond_(ctx, self.help_format_:format(cmd.help))
			return true
		end
		if self.help_fallback_ then
			if self.help_fallback_(ctx, initial_from) then
				return true
			end
		end
		self.respond_(ctx, self.unknown_format_)
		return true
	end
	
	local function new(params)
		local cmd = setmetatable({
			respond_ = params.respond,
			help_fallback_ = params.help_fallback,
			list_extra_ = params.list_extra,
			help_format_ = params.help_format,
			alias_format_ = params.alias_format,
			list_format_ = params.list_format,
			unknown_format_ = params.unknown_format,
			cmd_fallback_ = params.cmd_fallback,
			commands_ = {},
			aliases_ = {},
		}, command_parser_m)
		local collect = {}
		for name, info in pairs(params.commands) do
			if not info.hidden then
				table.insert(collect, "/" .. name)
			end
			name = name:lower()
			if info.role == "help" then
				cmd.help_name_ = name
				cmd.commands_[name] = {
					func = function(ctx, _, words)
						cmd:help_(ctx, words[2])
						return true
					end,
					help = info.help,
				}
			elseif info.role == "list" then
				cmd.commands_[name] = {
					func = function(ctx)
						cmd:list_(ctx)
						return true
					end,
					help = info.help,
				}
			elseif info.alias then
				cmd.aliases_[name] = info.alias
			elseif info.macro then
				cmd.commands_[name] = {
					macro = info.macro,
					help = info.help,
				}
			else
				cmd.commands_[name] = {
					func = info.func,
					help = info.help,
				}
			end
		end
		table.sort(collect)
		cmd.list_str_ = table.concat(collect, " ")
		return cmd
	end
	
	return {
		new = new,
	}
	
end

require_preload__["tptmp.common.config"] = function()

	return {
		-- ***********************************************************************
		-- *** The following options apply to both the server and the clients. ***
		-- *** Handle with care; changing options here means having to update  ***
		-- *** the client you ship.                                            ***
		-- ***********************************************************************
	
		-- * Protocol version, between 0 and 254. 255 is reserved for future use.
		version = 28,
	
		-- * Client-to-server message size limit, between 0 and 255, the latter
		--   limit being imposted by the protocol.
		message_size = 200, -- * Upper limit is 255.
	
		-- * Client-to-server message rate limit. Specifies the amount of time in
		--   seconds that must have elapsed since the previous message in order
		--   for the current message to be processed.
		message_interval = 1,
	
		-- * Authentication backend URL.
		auth_backend = "https://powdertoy.co.uk/ExternalAuth.api",
	
		-- * Authentication backend timeout in seconds.
		auth_backend_timeout = 3,
	
		-- * Username to UID backend URL.
		uid_backend = "https://powdertoy.co.uk/User.json",
	
		-- * Username to UID backend timeout in seconds.
		uid_backend_timeout = 3,
	
		-- * Host to connect to by default.
		host = "tptmp.starcatcher.us",
	
		-- * Port to connect to by default.
		port = 34403,
	
		-- * Encrypt traffic between player clients and the server.
		secure = true,
	}
	
end

require_preload__["tptmp.common.util"] = function()

	local function version_less(lhs, rhs)
		for i = 1, math.max(#lhs, #rhs) do
			local left = lhs[i] or 0
			local right = rhs[i] or 0
			if left < right then
				return true
			end
			if left > right then
				return false
			end
		end
		return false
	end
	
	local function version_equal(lhs, rhs)
		for i = 1, math.max(#lhs, #rhs) do
			local left = lhs[i] or 0
			local right = rhs[i] or 0
			if left ~= right then
				return false
			end
		end
		return true
	end
	
	return {
		version_less = version_less,
		version_equal = version_equal,
	}
	
end

require("tptmp.client").run()