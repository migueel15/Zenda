-- PinStack: columna de ventanas fijadas en el borde izquierdo del monitor.
-- Lua reserva el hueco en el monitor (solo afecta a las ventanas en mosaico, no a
-- las capas de Quickshell) y coloca las ventanas; Quickshell pinta el asa de
-- redimensionado y manda el ancho con `zenda pinstack width`.
-- `zenda_cmd` lo antepone Zenda al generar el módulo.

-- El estado sobrevive a las recargas: Hyprland conserva el estado de Lua.
local M = zenda_pinstack or {}
zenda_pinstack = M

M._state = M._state or {
	active = false,
	monitor = nil,
	width = 900,
	-- Lo que ocupan otras zonas exclusivas antes de la columna (marco de Zenda).
	offset = 0,
	gap = 8,
	clients = {},
	live = false,
}

-- Ancho minimo que cada ventana del stack ha aceptado, por direccion. Hyprland no
-- expone el minimo del cliente: se descubre al pedirle menos y ver que no cede.
M._min = M._min or {}

--- Avisa a Quickshell del estado, el monitor y el ancho minimo de la columna.
M._notify = function()
	local s = M._state
	local monitor = s.monitor and s.monitor.name or ""
	hl.dispatch(hl.dsp.exec_cmd(zenda_cmd .. " pinstack state " .. tostring(s.active) .. " '" .. monitor .. "' " .. M._required_width() .. " " .. math.floor(s.width)))
end

--- Ancho de columna que necesita la ventana mas exigente del stack (0 sin minimos).
M._required_width = function()
	local widest = 0
	for _, client in ipairs(M._state.clients) do
		widest = math.max(widest, M._min[client.address] or 0)
	end
	if widest == 0 then return 0 end
	return math.ceil(widest + M._state.gap * 2)
end

--- Tras recolocar, compara el tamano real con el pedido: si una ventana no ha
--- bajado, ese es su minimo y la columna no puede ser mas estrecha.
M._check_min = function()
	M._check_pending = false
	if not M._state.active then return end
	-- Mientras el usuario redimensiona, el ancho de la ventana no es su minimo.
	if M._vresize ~= nil then return end
	-- Una entrada al stack se coloca sin animacion para medirla al instante.
	if M._entering then
		M._entering = false
		M._state.live = false
		for _, client in ipairs(M._state.clients) do M._set_anim(client, true) end
	end
	local expected = M._state.width - M._state.gap * 2
	local previous = M._required_width()
	local layout = M._layout()
	local taller = false
	local current = {}
	for _, window in ipairs(hl.get_windows()) do current[window.address] = window end
	for index, client in ipairs(M._state.clients) do
		local window = current[client.address]
		if window ~= nil and window.size.x > expected + 1 then
			M._min[client.address] = math.max(M._min[client.address] or 0, window.size.x)
		end
		-- Lo mismo en alto: si no ha bajado a su hueco, esa es su altura minima.
		if window ~= nil and layout[index] ~= nil and window.size.y > layout[index].height + 1 then
			M._min_h[client.address] = math.max(M._min_h[client.address] or 0, window.size.y)
			taller = true
		end
	end
	local required = M._required_width()
	if taller and required <= M._state.width then M.recalculate_stack() end
	if required == previous then return end
	if required > M._state.width then
		M._state.width = required
		M._reserve(required)
		M.recalculate_stack()
	end
	M._notify()
end

M._schedule_check = function()
	local fast = M._state.live
	-- Una comprobacion lenta pendiente no debe retrasar una rapida.
	if M._check_pending and not fast then return end
	M._check_pending = true
	-- Con animaciones hay que esperar a que terminen para no medir un tamano a medias.
	hl.timer(M._check_min, { timeout = fast and 50 or 400, type = "oneshot" })
end

--- Lo llama `zenda pinstack width`. Con `live` (arrastre en curso) las ventanas
--- se mueven sin animacion para no quedarse atras del borde.
---@param width integer
---@param live boolean?
---@param offset integer?
M.set_width = function(width, live, offset)
	local required = M._required_width()
	M._state.width = math.max(width, required)
	M._state.offset = offset or M._state.offset
	M._state.live = live == true
	if M._state.active then M._reserve(M._state.width) end
	M.recalculate_stack()
	-- Quickshell pidio menos de lo que cabe: se le devuelve el minimo para que el
	-- asa no se quede en un ancho que la columna no tiene.
	if width < required and not M._state.live then M._notify() end
end

M.setup = function()
	-- Las ventanas del stack van fijadas (pin) y Hyprland ignora su fullscreen
	-- salvo con esta opcion; _sync_stack_fullscreen lo deja dentro del hueco.
	hl.config({ binds = { allow_pin_fullscreen = true } })
	M.apply_mappings()
	if not M._listening then
		M.apply_listeners()
		M._listening = true
	end
end

--- Este bind corre antes que el fin del arrastre, que soltaria la ventana donde esta.
M._after_drag = function(fn)
	return function()
		hl.timer(fn, { timeout = 30, type = "oneshot" })
	end
end

M.apply_mappings = function()
	hl.bind("SUPER + SHIFT + L", function()
		M.toggle_pinstack()
	end, { description = "Zenda pinstack" })

	hl.bind("SUPER + mouse:272", function()
		if M.is_cursor_inside_pinstack() then
			local client = hl.get_active_window()
			M.detach_client(client)
		end
	end, { non_consuming = true, transparent = true })

	hl.bind("SUPER + mouse:272", M._after_drag(function()
		local client = hl.get_active_window()
		if M.is_cursor_inside_pinstack() then
			M.attach_client(client, true)
			return
		end

		if M._has_tag(client) then
			M.detach_client(client)
			hl.dispatch(hl.dsp.window.float({ action = "off", window = client }))
			hl.dispatch(hl.dsp.window.tag({ tag = "-pinstack", window = client }))
			hl.dispatch(hl.dsp.window.pin({ action = "off", window = client }))
		end
	-- En 0.57 el bind consumidor del arrastre "ensombrece" a este al pulsar y no
	-- se ejecuta al soltar. `transparent` lo excluye de esa sombra; `non_consuming`
	-- deja que el arrastre del usuario siga funcionando.
	end), { drag = true, non_consuming = true, transparent = true })

	-- El redimensionado del usuario sigue activo; dentro del stack solo cuenta el eje vertical.
	hl.bind("SUPER + mouse:273", function()
		if M.is_cursor_inside_pinstack() then M._start_vresize() end
	-- Zenda carga despues de los atajos del usuario: sin `transparent` su
	-- redimensionado ensombrece este bind y nunca se ejecuta.
	end, { non_consuming = true, transparent = true })

	hl.bind("SUPER + mouse:273", M._stop_vresize, { release = true, non_consuming = true, transparent = true })
end

M.apply_listeners = function()
	hl.on("window.open", function(client)
		if M.is_cursor_inside_pinstack() then
			M.attach_client(client)
		end
	end)

	hl.on("window.close", function(client)
		if M.client_inside_stack(client) then
			M.close_client(client)
		end
	end)

	-- Con el pinstack activo, la pantalla completa real taparia la franja reservada:
	-- se convierte en maximizado interno con fullscreen de cliente (respeta reservas).
	hl.on("window.fullscreen", function(client)
		if client == nil then return end
		if M.client_inside_stack(client) then
			M._sync_stack_fullscreen(client)
			return
		end
		M._sync_fullscreen(client)
	end)

	-- Una recarga puede cambiar modo, escala o posicion del monitor.
	hl.on("config.reloaded", function()
		if not M._state.active then return end
		M._refresh_monitor()
		M._reserve(M._state.width)
		M.recalculate_stack()
		M._notify()
	end)
end

--- Zenda u otro cliente pueden cambiar modo, escala o posicion: se relee por nombre.
M._refresh_monitor = function()
	local current = M._state.monitor
	if current == nil then return end
	for _, monitor in ipairs(hl.get_monitors()) do
		if monitor.name == current.name then
			M._state.monitor = monitor
			return
		end
	end
end

M.toggle_pinstack = function()
	if M._state.active then
		M.disable_pinstack()
	else
		M.enable_pinstack()
	end
end

M.enable_pinstack = function()
	M._state.monitor = hl.get_active_monitor()
	M._state.active = true
	M._reserve(M._state.width)
	M._notify()
	M.recalculate_stack()
end

M.disable_pinstack = function()
	M._state.active = false
	M._state.live = false
	M.recalculate_stack()
	M._refresh_monitor()
	M._reserve(0)
	M._notify()
	M._restore_fullscreen()
	M._state.monitor = nil
end

--- Hyprland no tiene dispatcher para el reserved_area: se reconstruye el monitor
--- con sus valores actuales. `monitor.reserved` incluye las zonas exclusivas de las
--- capas, asi que se fija el valor absoluto.
---@param left integer
M._reserve = function(left)
	local monitor = M._state.monitor
	if monitor == nil then return end
	-- zenda: runtime
	hl.monitor({
		output = monitor.name,
		mode = string.format("%dx%d@%f", monitor.width, monitor.height, monitor.refresh_rate),
		position = string.format("%dx%d", monitor.position.x, monitor.position.y),
		scale = monitor.scale,
		transform = monitor.transform,
		reserved_area = { left = left },
	})
end

M._limited = M._limited or {}

---@param client HL.Window
---@param internal integer
---@param fs_client integer
M._set_fullscreen_state = function(client, internal, fs_client)
	hl.dispatch(hl.dsp.window.fullscreen_state({
		internal = internal, client = fs_client, action = "set", window = client
	}))
end

--- Con estados distintos Hyprland deja de sincronizar la ventana con lo que pide
--- la aplicacion; al salir se fija 0/0 para que vuelva a sincronizar.
---@param client HL.Window
M._sync_fullscreen = function(client)
	local wants = client.fullscreen == 2 or client.fullscreen_client == 2
	local limited = M._limited[client.address]

	if wants and M._state.active then
		if client.fullscreen ~= 1 or client.fullscreen_client ~= 2 then
			M._limited[client.address] = true
			M._set_fullscreen_state(client, 1, 2)
		end
	elseif wants then
		M._limited[client.address] = nil
		if client.fullscreen ~= 2 then M._set_fullscreen_state(client, 2, 2) end
	elseif limited then
		M._limited[client.address] = nil
		M._set_fullscreen_state(client, 0, 0)
	end
end

--- Dentro del pinstack la pantalla completa se queda en su hueco: solo el
--- cliente cree estar en fullscreen (interno 0, cliente 2).
---@param client HL.Window
M._sync_stack_fullscreen = function(client)
	local wants = client.fullscreen == 2 or client.fullscreen_client == 2
	if wants then
		if client.fullscreen == 0 and client.fullscreen_client == 2 then return end
		M._set_fullscreen_state(client, 0, 2)
	elseif client.fullscreen ~= 0 or client.fullscreen_client ~= 0 then
		M._set_fullscreen_state(client, 0, 0)
	else
		return
	end
	M.recalculate_stack()
end

--- Al cerrar el pinstack, los fullscreen limitados vuelven a ser fullscreen reales.
M._restore_fullscreen = function()
	for _, client in ipairs(hl.get_windows()) do
		if M._limited[client.address] then M._sync_fullscreen(client) end
	end
end

---@param client HL.Window | nil
---@param dropped boolean? True if window trying to attach is being droped
M.attach_client = function(client, dropped)
	if not M._state.active then return end
	if client == nil then return end

	for i, value in ipairs(M._state.clients) do
		if client.address == value.address then
			table.remove(M._state.clients, i)
			M.recalculate_stack()
		end
	end

	hl.dispatch(hl.dsp.window.tag({ tag = "+pinstack", window = client }))

	local ref_position
	if dropped then
		local current_window = hl.get_active_window()
		if current_window == nil then return end
		ref_position = current_window.at.y + (current_window.size.y / 2)
	else
		ref_position = hl.get_cursor_pos().y
	end

	-- La ventana sobre la que cae se parte en dos: la nueva ocupa la mitad del
	-- lado donde esta el cursor y el resto del stack conserva su altura.
	local insert_at = #M._state.clients + 1
	local count = #M._state.clients
	if count > 0 and M._state.monitor ~= nil then
		local layout = M._layout()
		local target = count
		for i, slot in ipairs(layout) do
			if ref_position < slot.top + slot.height + M._state.gap / 2 then
				target = i
				break
			end
		end
		local slot = layout[target]
		insert_at = ref_position < slot.top + slot.height / 2 and target or target + 1
		for i, c in ipairs(M._state.clients) do M._weights[c.address] = layout[i].height end
		local half = slot.height / 2
		M._weights[M._state.clients[target].address] = half
		M._weights[client.address] = half
	else
		M._weights[client.address] = nil
	end

	table.insert(M._state.clients, insert_at, client)
	-- Sin animacion: el minimo de la ventana se mide enseguida y la columna se
	-- ensancha al momento si no cabe.
	M._entering = true
	M._state.live = true
	M.recalculate_stack()
end

---@param client HL.Window | nil
M._remove_client = function(client)
	if client == nil then return end
	for index, value in ipairs(M._state.clients) do
		if value.address == client.address then
			table.remove(M._state.clients, index)
			M._min[client.address] = nil
			M._weights[client.address] = nil
			M._min_h[client.address] = nil
			M.recalculate_stack()
			if #M._state.clients > 0 then M._notify() end
			if #M._state.clients == 0 then M.disable_pinstack() end
			return
		end
	end
end

M.detach_client = M._remove_client
M.close_client = M._remove_client

M.recalculate_stack = function()
	if not M._state.active then
		for _, client in ipairs(M._state.clients) do
			M._hide_client(client)
		end
		return
	end

	M._refresh_monitor()
	local monitor = M._state.monitor
	if monitor == nil then return end

	local count = #M._state.clients
	if count == 0 then return end

	local layout = M._layout()
	local client_width = M._state.width - M._state.gap * 2
	local x = monitor.position.x + M._state.offset + M._state.gap

	for index, client in ipairs(M._state.clients) do
		M._set_anim(client, not M._state.live)
		hl.dispatch(hl.dsp.window.float({ action = "on", window = client }))
		hl.dispatch(hl.dsp.window.resize({ x = client_width, y = layout[index].height, window = client }))
		M._show_client(client, x, layout[index].top)
	end
	M._schedule_check()
end

-- Peso de la altura de cada ventana, por direccion; sin peso cuenta como 1.
M._weights = M._weights or {}

--- Reparte la altura del monitor entre las ventanas segun su peso.
---@return {top: number, height: number}[]
M._layout = function()
	local monitor = M._state.monitor
	local gap = M._state.gap
	local clients = M._state.clients
	local available = (monitor.height / monitor.scale) - gap * (#clients + 1)
	-- Las ventanas que no llegan a su minimo se fijan en el y el resto se
	-- reparte entre las demas por peso, hasta que todas caben.
	local heights, fixed = {}, {}
	for _ = 1, #clients do
		local free, total = available, 0
		for i, client in ipairs(clients) do
			if fixed[i] then free = free - heights[i] else total = total + (M._weights[client.address] or 1) end
		end
		local changed = false
		for i, client in ipairs(clients) do
			if not fixed[i] then
				heights[i] = total > 0 and free * (M._weights[client.address] or 1) / total or 0
				local min = M._min_height_of(client)
				if heights[i] < min then
					heights[i], fixed[i], changed = min, true, true
				end
			end
		end
		if not changed then break end
	end
	local layout = {}
	local top = monitor.position.y + gap
	for index = 1, #clients do
		layout[index] = { top = top, height = heights[index] }
		top = top + heights[index] + gap
	end
	return layout
end

-- Altura minima que cada ventana ha aceptado, por direccion.
M._min_h = M._min_h or {}

---@param client HL.Window
---@return number
M._min_height_of = function(client)
	return math.max(M._min_height, M._min_h[client.address] or 0)
end

-- Altura minima de una ventana del stack al redimensionarla.
M._min_height = 80

--- Redimensionado vertical: Hyprland redimensiona la ventana en libertad y en cada
--- vuelta se toma solo el borde vertical que ha movido; la vecina cede o gana esa
--- altura y la ventana vuelve a su columna.
M._resize_tick = function()
	local drag = M._vresize
	if drag == nil or not M._state.active then return end
	if drag.horizontal then return M._hresize_tick(drag) end
	local window
	for _, candidate in ipairs(hl.get_windows()) do
		if candidate.address == drag.address then window = candidate end
	end
	if window == nil then return end
	local index
	for i, client in ipairs(M._state.clients) do
		if client.address == drag.address then index = i end
	end
	if index == nil then return end

	local layout = M._layout()
	local gap = M._state.gap
	local current = layout[index]
	local bottom = current.top + current.height
	local heights = {}
	for i, slot in ipairs(layout) do heights[i] = slot.height end

	local new_top = window.at.y
	local new_bottom = window.at.y + window.size.y
	if index > 1 and math.abs(new_top - current.top) > 0.5 then
		local prev = layout[index - 1]
		local limit_low = prev.top + M._min_height_of(M._state.clients[index - 1]) + gap
		local limit_high = bottom - M._min_height_of(M._state.clients[index])
		new_top = math.max(limit_low, math.min(limit_high, new_top))
		heights[index - 1] = new_top - gap - prev.top
		heights[index] = bottom - new_top
	elseif index < #layout and math.abs(new_bottom - bottom) > 0.5 then
		local next_slot = layout[index + 1]
		local next_bottom = next_slot.top + next_slot.height
		local limit_low = current.top + M._min_height_of(M._state.clients[index])
		local limit_high = next_bottom - M._min_height_of(M._state.clients[index + 1]) - gap
		new_bottom = math.max(limit_low, math.min(limit_high, new_bottom))
		heights[index] = new_bottom - current.top
		heights[index + 1] = next_bottom - (new_bottom + gap)
	end

	for i, client in ipairs(M._state.clients) do
		M._weights[client.address] = heights[i]
	end
	M.recalculate_stack()
end

--- Con una sola ventana no hay vecina que ceda altura: redimensionarla cambia
--- el ancho de la columna, como el asa, y su altura queda fija.
---@param drag {address: string}
M._hresize_tick = function(drag)
	local window
	for _, candidate in ipairs(hl.get_windows()) do
		if candidate.address == drag.address then window = candidate end
	end
	local monitor = M._state.monitor
	if window == nil or monitor == nil then return end
	local max = math.floor(monitor.width / monitor.scale * M._max_ratio)
	local low = math.max(M._min_width, M._required_width())
	local width = math.floor(math.max(low, math.min(max, window.size.x + M._state.gap * 2)))
	if width == M._state.width then return end
	M._state.width = width
	M._reserve(width)
	M.recalculate_stack()
end

-- Limites del ancho de la columna; los mismos que el asa de Quickshell.
M._min_width = 200
M._max_ratio = 0.8

M._start_vresize = function()
	local client = hl.get_active_window()
	if not M.client_inside_stack(client) then return end
	local single = #M._state.clients == 1
	M._vresize = { address = client.address, horizontal = single }
	M._state.live = true
	-- Los limites van en la propia ventana: Hyprland no la deja pasar de ellos y no
	-- hay que corregirla despues (eso parpadeaba).
	local gap = M._state.gap
	local layout = M._layout()
	if single then
		local monitor = M._state.monitor
		local height = math.floor(layout[1].height)
		local min_w = math.ceil(math.max(M._min_width, M._required_width()) - gap * 2)
		local max_w = math.floor(monitor.width / monitor.scale * M._max_ratio - gap * 2)
		M._set_limits(client, min_w, height, max_w, height)
	else
		local index
		for i, c in ipairs(M._state.clients) do
			if c.address == client.address then index = i end
		end
		local clients = M._state.clients
		local spare = 0
		for _, i in ipairs({ index - 1, index + 1 }) do
			if clients[i] ~= nil then
				spare = math.max(spare, layout[i].height - M._min_height_of(clients[i]))
			end
		end
		local width = math.floor(M._state.width - gap * 2)
		M._set_limits(client, width, math.ceil(M._min_height_of(client)), width, math.floor(layout[index].height + spare))
	end
	if M._vresize_timer == nil then
		M._vresize_timer = hl.timer(M._resize_tick, { timeout = 16, type = "repeat" })
	else
		M._vresize_timer:set_enabled(true)
	end
end

--- Limites de la ventana durante el arrastre. Solo duran lo que el arrastre:
--- fuera de el, el tamano real sirve para descubrir sus minimos.
---@param client HL.Window
M._set_limits = function(client, min_w, min_h, max_w, max_h)
	hl.dispatch(hl.dsp.window.set_prop({ window = client, prop = "min_size", value = min_w .. " " .. min_h }))
	hl.dispatch(hl.dsp.window.set_prop({ window = client, prop = "max_size", value = max_w .. " " .. max_h }))
end

--- Devuelve limites amplios. No se usa "unset": quitar asi el limite cerro Hyprland 0.57.
---@param address string
M._unlock_width = function(address)
	for _, client in ipairs(hl.get_windows()) do
		if client.address == address then
			hl.dispatch(hl.dsp.window.set_prop({ window = client, prop = "min_size", value = "1 1" }))
			hl.dispatch(hl.dsp.window.set_prop({ window = client, prop = "max_size", value = "99999 99999" }))
			return
		end
	end
end

M._stop_vresize = function()
	if M._vresize == nil then return end
	if M._vresize_timer ~= nil then M._vresize_timer:set_enabled(false) end
	M._resize_tick()
	local horizontal = M._vresize.horizontal
	M._unlock_width(M._vresize.address)
	M._vresize = nil
	M._state.live = false
	M.recalculate_stack()
	-- El ancho de la columna ha cambiado sin el asa: Quickshell lo recoloca.
	if horizontal then M._notify() end
end

---@param client HL.Window
---@param enabled boolean
M._set_anim = function(client, enabled)
	hl.dispatch(hl.dsp.window.set_prop({
		window = client, prop = "no_anim", value = enabled and "false" or "true"
	}))
end

---@param client HL.Window | nil
M._hide_client = function(client)
	if client == nil then return end
	M._set_anim(client, false)
	hl.dispatch(hl.dsp.window.pin({ action = "off", window = client }))
	hl.dispatch(hl.dsp.window.move({
		workspace = "special:pinstack-hidden",
		window = client,
		follow = false
	}))
end

---@param client HL.Window | nil
---@param x number
---@param y number
M._show_client = function(client, x, y)
	if client == nil then return end
	hl.dispatch(hl.dsp.window.move({ workspace = hl.get_active_workspace(), window = client }))
	hl.dispatch(hl.dsp.window.move({ x = x, y = y, window = client }))
	hl.dispatch(hl.dsp.window.pin({ action = "on", window = client }))
	M._set_anim(client, not M._state.live)
end

---@param client HL.Window | nil
---@param tag string | nil
---@return boolean
M._has_tag = function(client, tag)
	tag = tag or "pinstack"
	if client == nil then return false end
	local tags = client.tags
	if type(tags) == "string" then
		return tags == tag
	end
	if type(tags) == "table" then
		for _, t in ipairs(tags) do
			if t == tag then return true end
		end
	end
	return false
end

M.is_cursor_inside_pinstack = function()
	local cur_pos = hl.get_cursor_pos()
	if cur_pos == nil then return false end
	local monitor = M._state.monitor
	if not M._state.active or monitor == nil then return false end

	local left = monitor.position.x + M._state.offset
	local top = monitor.position.y
	return cur_pos.x >= left
		and cur_pos.x <= left + M._state.width
		and cur_pos.y >= top
		and cur_pos.y <= top + monitor.height / monitor.scale
end

---@param client HL.Window | nil
M.client_inside_stack = function(client)
	if client == nil then return false end
	for _, c in ipairs(M._state.clients) do
		if client.address == c.address then return true end
	end
	return false
end

M.setup()
