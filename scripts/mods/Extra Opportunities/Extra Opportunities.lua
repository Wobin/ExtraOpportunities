--[[
Title: Extra Opportunities
Author: Wobin
Date: 25/06/2026
Repository: https://github.com/Wobin/ExtraOpportunities
--]]
local mod = get_mod("Extra Opportunities")
mod.version = mod.get_metadata and mod:get_metadata("version") or "unknown"

local traversal_polling = {}
local completed_traversals = {}
local Managers = Managers
local Unit = Unit
local Vector3 = Vector3
local Level  = Level
local math_ceil = math.ceil

local function _lerp(a, b, t)
    return a + (b - a) * t
end

local function _ilerp(a, b, v)
    if a == b then return 0 end
    return (v - a) / (b - a)
end

local function _radians_to_degrees(radians)
    return radians * 180 / math.pi
end

local function _deep_copy_color(color)
    return { color[1], color[2], color[3], color[4] }
end

local function _resolve_position(position_data)
    if not position_data then return nil end
    if pcall(Vector3.length, position_data) then return position_data end
    local ok, unboxed = pcall(function() return position_data:unbox() end)
    if ok and unboxed and pcall(Vector3.length, unboxed) then return unboxed end
    return nil
end

local color_lib = rawget(_G, "Color")
local DEFAULT_OPPORTUNITY_COLOR = { 255, 114, 247, 119 }

local function _get_player_slot()
    local local_player = mod._local_player
    return local_player and local_player.slot and local_player:slot() or nil
end

local function _get_player_slot_color(slot)
    if not slot or not color_lib then return _deep_copy_color(DEFAULT_OPPORTUNITY_COLOR) end
    local ok, color_func = pcall(function() return color_lib["player_slot_" .. slot] end)
    return ok and color_func and color_func(255, true) or _deep_copy_color(DEFAULT_OPPORTUNITY_COLOR)
end

local function _cache_player()
    mod._player_manager = Managers and Managers.player
    mod._local_player = mod._player_manager and mod._player_manager.local_player and mod._player_manager:local_player(1)
    mod._player_unit = mod._local_player and mod._local_player.player_unit
end

function mod.on_all_mods_loaded()
    mod:info(mod.version)
end


local function _get_expedition_objectives_handler()
    local game_mode_manager = Managers.state and Managers.state.game_mode
    local game_mode = game_mode_manager and game_mode_manager.game_mode and game_mode_manager:game_mode()
    if game_mode and game_mode.get_objectives_handler then
        return game_mode:get_objectives_handler()
    end
    return nil
end

local function _size_label_from_level_data(level_data)
    if not level_data then return nil end
    local tags = level_data.tags
    if tags then
        for i = 1, #tags do 
            if tags[i] == "level_size_16" then return "16m" end
        end
    end
    local level_name = level_data.level_name
    local level_size = level_name and string.match(level_name, "op_(%d+)m_")
    if level_size then return string.format("%sm", level_size) end
    return nil
end

local function _add_traversal_level_to_registry(level_index, level_data, merged)
    if not level_data or level_data.template_type ~= "traversal_level" or not level_data.spawned then
        return
    end
    if _size_label_from_level_data(level_data) ~= "16m" then
        return
    end
    local position_data = level_data.position
    if not position_data then
        return
    end
    local level = level_data.level
    local server_level_id = level and Level.get_data(level, "server_level_id")
    local id_key = server_level_id or (1000 + level_index)
    if not merged[id_key] then
        merged[id_key] = position_data
    end
end

local function _collect_traversal_16m_from_expedition(expedition, merged)
    if type(expedition) ~= "table" then return end
    for _, section in ipairs(expedition) do
        local levels_data = section and section.levels_data
        if type(levels_data) == "table" then
            for level_index, level_data in ipairs(levels_data) do
                _add_traversal_level_to_registry(level_index, level_data, merged)
            end
        end
    end
end

local function _get_traversal_16m_registry()
    local merged = {}
    local objectives_handler = _get_expedition_objectives_handler()
    _collect_traversal_16m_from_expedition(objectives_handler and objectives_handler._expedition, merged)
    return merged
end

local function _poll_traversal_proximity(compass_element, opportunity_id, position, player_pos, t)
    if not opportunity_id or not position or not player_pos then return end
    
    local dist = Vector3.distance(position, player_pos)
    if dist > 10 then
        traversal_polling[opportunity_id] = nil
        return
    end
    
    local poll = traversal_polling[opportunity_id] or { enter_time = nil }
    if not poll.enter_time then
        poll.enter_time = t
    elseif t - poll.enter_time >= 3 then
        completed_traversals[opportunity_id] = true
        traversal_polling[opportunity_id] = nil
        return
    end
    traversal_polling[opportunity_id] = poll
end

local function _has_opportunity_marker(icon_data, opportunity_id)
    for i = 1, #icon_data do
        local existing = icon_data[i]
        if existing and existing.opportunity_id and existing.opportunity_id == opportunity_id then
            return true
        end
    end
    return false
end

local function _is_eligible_16m(registry, opportunity_id)
    return registry[opportunity_id] and not completed_traversals[opportunity_id]
end

local function _find_closest_16m(self, navigation_handler, registry)
    local closest_opportunity_id
    local closest_position
    local closest_distance = math.huge
    local rank = 1

    for opportunity_id, position_box in pairs(registry or {}) do
        if _is_eligible_16m(registry, opportunity_id) and not navigation_handler:is_level_completed(opportunity_id) then
            local position = _resolve_position(position_box)
            local ok, distance = pcall(self._get_distance_to_objective, self, position)
            if ok and type(distance) == "number" and distance == distance then
                if distance < closest_distance then
                    closest_distance = distance
                    closest_opportunity_id = opportunity_id
                    closest_position = position
                end
            end
        end

        if opportunity_id < (closest_opportunity_id or math.huge) and _is_eligible_16m(registry, opportunity_id) then
            rank = rank + 1
        end
    end

    if not closest_opportunity_id then return nil, nil, nil, nil end
    return closest_opportunity_id, closest_position, closest_distance, rank
end


function mod.get_closest_traversal_target(compass_element)
	if not compass_element then return nil end
	local navigation_handler = compass_element._navigation_handler
	if not navigation_handler or (navigation_handler.is_active and not navigation_handler:is_active()) then return nil end
	local registry = _get_traversal_16m_registry()
	local closest_opportunity_id, closest_position, closest_distance, closest_rank = _find_closest_16m(compass_element, navigation_handler, registry)
	if not closest_opportunity_id or not closest_position or type(closest_distance) ~= "number" then return nil end
	return {
		id = closest_opportunity_id,
		position = closest_position,
		distance = closest_distance,
		rank = closest_rank,
		slot = _get_player_slot(),
	}
end

mod:hook_require("scripts/ui/hud/elements/player_compass/hud_element_player_compass", function(HudElementPlayerCompass)
	if mod._compass_hooked then return end
	mod._compass_hooked = true

	local UIRenderer = require("scripts/managers/ui/ui_renderer")
	local UIFonts = require("scripts/managers/ui/ui_fonts")
	local UIFontSettings = require("scripts/managers/ui/ui_font_settings")
	local star_font_type = UIFontSettings.hud_body.font_type
	local star_text_options = UIFonts.get_font_options_by_style({
		text_horizontal_alignment = "center",
		text_vertical_alignment = "center",
		drop_shadow = true,
	}, {})

	mod:hook(HudElementPlayerCompass, "_get_expedition_navigation_icons", function(func, self, dt, t, ui_renderer)
		local icon_data = func(self, dt, t, ui_renderer)

		local navigation_handler = self._navigation_handler
		if (not navigation_handler or not navigation_handler.get_registered_opportunities) or (navigation_handler.is_active and not navigation_handler:is_active()) then return icon_data end
		
        if not mod._local_player then 
            _cache_player()
            return icon_data
        end

		local closest_opportunity_id, closest_position, closest_distance = _find_closest_16m(self, navigation_handler, _get_traversal_16m_registry())
		if not closest_opportunity_id or not closest_position then return icon_data end

		local player_unit = mod._player_unit
		if player_unit and Unit.alive(player_unit) then
			local player_pos = Unit.world_position(player_unit, 1)
			if player_pos then
				_poll_traversal_proximity(self, closest_opportunity_id, closest_position, player_pos, t)
			end
		end

		if _has_opportunity_marker(icon_data, closest_opportunity_id) then return icon_data end

		local at_opportunity = self._hud_objectives_by_id[closest_opportunity_id]

		local angle = self:_get_position_direction_angle(closest_position)
		local angle_degrees = _radians_to_degrees(angle)
		local text = "★"

		local size = { 20, 20 }
		if closest_distance <= 100 then
			local size_lerp = _ilerp(100, 25, closest_distance)
			size[1] = _lerp(size[1], size[1] * 1.5, size_lerp)
			size[2] = _lerp(size[2], size[2] * 1.5, size_lerp)
		end

		local color = _get_player_slot_color(_get_player_slot())

		icon_data[#icon_data + 1] = {
			angle = angle_degrees,
			widget = self._default_compass_icon_widget,
			text = text,
			text_color = color,
			text_size = { 80, 40 },
			icon_color = color,
			size = size,
			at_opportunity = at_opportunity,
			marked = closest_distance > 10,
			opportunity_id = closest_opportunity_id,
			extra_opportunities_marker = true,
		}

		table.sort(icon_data, function(a, b)
			return not a.marked and b.marked
		end)

		return icon_data
	end)

	mod:hook(HudElementPlayerCompass, "_draw_compass_icon", function(func, self, dt, t, ui_renderer, icon_data, x, y, alpha, draw_layer)
		if not (icon_data and icon_data.extra_opportunities_marker) then
			return func(self, dt, t, ui_renderer, icon_data, x, y, alpha, draw_layer)
		end

		local text = icon_data.text
		if text and text ~= "" then
			local size = icon_data.size or { 20, 20 }
			local box = icon_data.text_size or size
			local scale = ui_renderer.scale or 1
			local font_size = math_ceil((size[1] or 20) * scale)
			local slot_color = icon_data.text_color or { 255, 255, 255, 255 }
			local a = alpha or 255
			local brighten = 0.5
			local fill_color = {
				a,
				(slot_color[2] or 255) + (255 - (slot_color[2] or 255)) * brighten,
				(slot_color[3] or 255) + (255 - (slot_color[3] or 255)) * brighten,
				(slot_color[4] or 255) + (255 - (slot_color[4] or 255)) * brighten,
			}
			local outline_color = { a, 0, 0, 0 }
			local center_x = x + (size[1] or 20) * 0.5
			local center_y = y + (size[2] or 20) * 0.5
			local base_x = center_x - box[1] * 0.5
			local base_y = center_y - box[2] * 0.5
			local o = font_size * 0.09 / scale
			local offsets = { -o, -o, o, -o, -o, o, o, o, -o, 0, o, 0, 0, -o, 0, o }
			for i = 1, #offsets, 2 do
				local outline_position = { base_x + offsets[i], base_y + offsets[i + 1], draw_layer }
				UIRenderer.draw_text(ui_renderer, text, font_size, star_font_type, outline_position, box, outline_color, star_text_options)
			end
			local text_position = { base_x, base_y, draw_layer + 1 }
			UIRenderer.draw_text(ui_renderer, text, font_size, star_font_type, text_position, box, fill_color, star_text_options)
		end

		return draw_layer + 1
	end)
end)


