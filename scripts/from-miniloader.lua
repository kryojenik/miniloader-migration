local flib_gui = require("__flib__.gui")
local table = require("__flib__.table")

local warning_notice =
[[*** BACKUP ***  BACKUP *** BACKUP ***

Migrating Miniloaders from the miniloader mod is experimental, but I think I have it mostly working well enough to serve your purposes.

Please make sure you have a backup of your game save before you save this migrated save.  There is no path back or undo!

If you notice loaders from a belt set that did not migrate, please let me know and I will try to incorporate them.

After your migration is complete, please remove the Miniloader migration mod.

*Note: All Miniloader and Filter Miniloader items in inventories and containers are gone.  This is a one time loss - sorry.  Assemblers creating miniloaders will now be idle and need to manually be configured with a new recipe.

-Kryojenik

*** BACKUP *** BACKUP *** BACKUP ***]]

local not_migrated_notice =
[[The following loaders were not migrated.  If you save now and KEEP the Miniloader migration mod enabled this list will be maintained.

The only way to remove these dummy / non-functional loader is via this window or by disabling the Miniloader migration mod.

You can reopen this list with the command /mdrn-migrations.

Please report any belt packs that result in miniloaders not migrating and I may be able to add support.

-Kryojenik]]

local filter_notice =
[[The following lodaers had complex, split lane configuraitons that will not be supported in this implementation.  Only one filter per lane is allowed.
Engineer intervention is required to set the desired filters.

You can return to this list with the command /mdrn-migration.  If you disable the Miniloader migration mod these dummy loaders will be removed.]]

-- Forward declaration
local create_filter_list

---Replace the Miniloader with a Loader modernized
---@param old_ldr LuaEntity
---@return boolean
local function replace_miniloader(old_ldr)
  -- TODO: Improve name change / mapping for other belt addition mods (ultimate belts / 5dim / etc...)
  local name = string.gsub(old_ldr.name, "miniloader", "mdrn")
  ---@type boolean | integer
  local was_filter = 0
  name, was_filter = string.gsub(name, "filter%-", "")
  was_filter = (was_filter > 0)
  if not prototypes.entity[name] then
    return false
  end

  ---@type LuaEntity[]
  local inserters = old_ldr.surface.find_entities_filtered{type = "inserter", position = old_ldr.position}
  local filter_mode = inserters[1].inserter_filter_mode
  local filters = {}
  local split_lanes = false
  local complex_split = false

  if was_filter then
    local filters_left = {}
    local filters_right = {}
    for i=1,inserters[1].prototype.filter_count do
      ---@type InventoryFilter?
      local left = inserters[1].get_filter(i) --[[@as InventoryFilter]] or nil
      if left then
        left.index = i
      end

      ---@type InventoryFilter?
      local right = inserters[2].get_filter(i) --[[@as InventoryFilter]] or nil
      if right then
        right.index = i
      end

      if left and right and (left.name ~= right.name)
      or ((left or right) and not left and right) then
        split_lanes = true
        filters_right[#filters_right+1] = right
      end
      filters_left[#filters_left+1] = left
    end

    if split_lanes then
      if #filters_left > 1 or #filters_right > 1 then
        -- Complex split lanes not supported
        complex_split = true
        filters = {
          left = filters_left,
          right = filters_right
        }
      else
        filters_right[1].index = 2
        filters = {
          filters_left[1],
          filters_right[1],
        }
      end

    else
      filters = filters_left
    end
  end

  local new_ldr_proto = {
    name = split_lanes and name .. "-split" or name,
    position = old_ldr.position,
    direction = old_ldr.direction,
    force = old_ldr.force,
    player = inserters[1].last_user,
    type = old_ldr.loader_type,
    create_build_effect_smoke = false,
    filters = not complex_split and filters or nil
  }

  -- Save the control behavior details
  local old_cb = inserters[1].get_control_behavior() --[[@as LuaInserterControlBehavior]]
  local circuit_set_filters
  local circuit_read_transfers
  local circuit_enable_disable
  local circuit_condition
  if old_cb then
    circuit_set_filters = old_cb.circuit_set_filters
    circuit_read_transfers = old_cb.circuit_read_hand_contents and (old_cb.circuit_hand_read_mode == defines.control_behavior.inserter.hand_read_mode.pulse)
    circuit_enable_disable = old_cb.circuit_enable_disable
    circuit_condition = old_cb.circuit_condition
  end

  -- Save details about connected wires
  local wires = {}
  for _, w in pairs(inserters[1].get_wire_connectors(false)) do
    if w.connection_count > 0 then
      wires[w.wire_connector_id] = (function()
        return w.connections
      end)()
    end
  end

  -- Destroy / remove old combo-entities
  local surface = old_ldr.surface
  old_ldr.destroy()
  for _,i in pairs(inserters) do
    i.destroy()
  end

  local new_ldr = surface.create_entity(new_ldr_proto)
  if not new_ldr then
    return false
  end

  if complex_split then
    storage.complex_split[new_ldr.unit_number] = {
      ldr = new_ldr,
      filters = filters,
      filter_mode = filter_mode
    }
  end

  if was_filter then
    new_ldr.loader_filter_mode = complex_split and "whitelist" or filter_mode
  end

  if old_cb then
    local new_cb = new_ldr.get_or_create_control_behavior() --[[@as LuaLoaderControlBehavior]]
    new_cb.circuit_set_filters = circuit_set_filters
    new_cb.circuit_read_transfers = circuit_read_transfers
    new_cb.circuit_enable_disable = circuit_enable_disable
    new_cb.circuit_condition = circuit_condition
    if wires then
      for wire_id, connections in pairs(wires) do
        local wire = new_ldr.get_wire_connector(wire_id, true)
        for _, c in pairs(connections) do
          if c.target.valid and c.target.owner.valid then
            wire.connect_to(c.target, true, c.origin)
          end
        end
      end
    end
  end
  return true
end

---Handle on_next_clicked
---@param e EventData.on_gui_click
local function on_next_clicked(e)
  local player = game.get_player(e.player_index)
  if not player then
    return
  end

  local window = player.gui.screen.mdrn_loader_list_window
  if not window then
    return
  end

  window.destroy()
  create_filter_list(e)
end

---Handle on_closed_clicked
---@param e EventData.on_gui_click
local function on_closed_clicked(e)
  local player = game.get_player(e.player_index)
  if not player then
    return
  end

  local window = player.gui.screen.mdrn_loader_filter_window
  if not window then
    return
  end

  window.destroy()
end

---Print a ping to the loader in the players chat
---@param e EventData.on_gui_click
local function on_ping_miniloader_clicked(e)
  local player = game.get_player(e.player_index)
  if not player then
    return
  end

  player.print(e.element.name)
end

---Remove an un-migrated miniloader from the game.
---@param i_ml integer
local function remove_miniloader(i_ml)
  local ml = storage.miniloaders_to_migrate[i_ml]
  if not ml then
    return
  end

  local entities = ml.surface.find_entities_filtered{position = ml.position}
  for _, ldr in pairs(entities) do
    ldr.destroy()
  end

  storage.miniloaders_to_migrate[i_ml] = nil
end

---Remove loader from the blacklist filter list
---@param i_ml integer
local function clear_complex_split(i_ml)
  storage.complex_split[i_ml] = nil
end

---Handle on_clear_blacklist_clicked
---@param e EventData.on_gui_click
local function on_clear_complex_split_clicked(e)
  local i_ml = tonumber(e.element.name)
  if not i_ml then
    return
  end

  clear_complex_split(i_ml)
  e.element.enabled = false
end

---Handle on_clear_all_clicked
---@param e EventData.on_gui_click
local function on_clear_all_clicked(e)
  if storage.complex_split and next(storage.complex_split) then
    for k,_ in pairs(storage.complex_split) do
      clear_complex_split(k)
    end
  end

  on_closed_clicked(e)
end

---Handle on_remove_clicked
---@param e EventData.on_gui_click
local function on_remove_clicked(e)
  local i_ml = tonumber(e.element.name)
  if not i_ml then
    return
  end

  remove_miniloader(i_ml)
  e.element.enabled = false
end

---Handle on_remove_all_clicked
---@param e EventData.on_gui_click
local function on_remove_all_clicked(e)
  if storage.miniloaders_to_migrate and next(storage.miniloaders_to_migrate) then
    for k,_ in pairs(storage.miniloaders_to_migrate) do
      remove_miniloader(k)
    end

    local player = game.get_player(e.player_index)
    if not player then
      return
    end

    storage.miniloaders_to_migrate = nil
  end
  on_next_clicked(e)
end

local function item_list(filters)
  local items
  for _, f in ipairs(filters) do
    item = "[item=" .. f.name .. ",quality=" .. f.quality .. "]"
    items = items and items .. " " .. item or item
  end
  return items
end

---Generate the content list of loaders with complex split-lane filters
local function complex_split_loaders()
  if not storage.complex_split or not next(storage.complex_split) then
    return {{type = "label", caption = "No complex split-lane loaders found. "}}
  end

  local elems = {}
  for k, v in pairs(storage.complex_split) do
    local loader = v.ldr
    local filters = v.filters
    elems = table.array_merge{elems, {
      { type = "label", caption = loader.name },
      { type = "label", caption = "Location: " .. loader.position.x .. ", " .. loader.position.y .. ", " .. loader.surface.name },
      {
        type = "button",
        name = k,
        caption = "Clear",
        tooltip = "Clear from tracking list.",
        style = "red_button",
        style_mods = { height = 24 },
        handler = { [defines.events.on_gui_click] = on_clear_complex_split_clicked },
      },
      {
        type = "button",
        name = loader.gps_tag,
        caption = "Ping",
        tooltip = "Print a gps link in chat.",
        style_mods = { height = 24 },
        handler = { [defines.events.on_gui_click] = on_ping_miniloader_clicked },
      },
      {
        type = "label",
        caption = "Filter mode: " .. v.filter_mode
      },
      {
        type = "label",
        caption = "Left: ".. item_list(filters.left)
      },
      {
        type = "label",
        caption = "Right: " .. item_list(filters.right)
      },
    }}
  end
  return elems
end

---Generate the content for the list of loaders that were not migrated
local function non_migrated_loaders()
  if not storage.miniloaders_to_migrate or not next(storage.miniloaders_to_migrate) then
    return {{ type = "label", caption = "No more Miniloaders left to migrate!" }}
  end

  local elems = {}
  for k, v in pairs(storage.miniloaders_to_migrate) do
    elems = table.array_merge{elems, {
      { type = "label", caption = v.name },
      { type = "label", caption = "Location: " .. v.position.x .. ", " .. v.position.y .. ", " .. v.surface.name },
      {
        type = "button",
        name = k,
        caption = "Remove",
        tooltip = "Remove entity from surface.",
        style = "red_button",
        style_mods = { height = 24 },
        handler = { [defines.events.on_gui_click] = on_remove_clicked },
      },
      {
        type = "button",
        name = v.gps_tag,
        caption = "Ping",
        tooltip = "Print a gps link in chat.",
        style_mods = { height = 24 },
        handler = { [defines.events.on_gui_click] = on_ping_miniloader_clicked },
      },
    }}
  end
  return elems
end

---Display the list of Miniloaders that had filters that could not be processed
---Filters configured as blacklist filters
---Filters that were configured on loaders of type input
---@param e EventData.on_gui_click
create_filter_list = function(e)
  local player = game.get_player(e.player_index)
  if not player then
    return
  end

  if player.gui.screen.mdrn_loader_filter_window then
    return
  end

  flib_gui.add(player.gui.screen, {
    type = "frame",
    name = "mdrn_loader_filter_window",
    direction = "vertical",
    caption = "Loaders Modernized - Filters altered",
    elem_mods = { auto_center = true },
    {
      type = "frame",
      style = "inside_shallow_frame_with_padding",
      { type = "label", style_mods = { single_line = false }, caption = filter_notice },
    },
    {
      type = "scroll-pane",
      {
        type = "frame",
        style = "inside_shallow_frame_with_padding",
        {
          type = "table",
          name = "mdrn_loader_table",
          column_count = 7,
          children = complex_split_loaders()
        },
      },
      {
        type = "flow",
        style = "dialog_buttons_horizontal_flow",
        drag_target = "mdrn_loader_filter_window",
        {
          type = "button",
          style = "red_button",
          caption = "Clear all!",
          tooltip = "Clear all loaders from tracking lists.",
          handler = {
            [defines.events.on_gui_click] = on_clear_all_clicked
          },
        },
        { type = "empty-widget", style = "flib_dialog_footer_drag_handle", ignored_by_interaction = true },
        {
          type = "button",
          style = "confirm_button",
          caption = "Close",
          handler = {
            [defines.events.on_gui_click] = on_closed_clicked
          },
        }
      }
    }
  })
end

---Display a list of Miniloaders that were not migrated
---@param pi integer
local function create_not_migrated_list(pi)
  local player = game.get_player(pi)
  if not player then
    return
  end

  if player.gui.screen.mdrn_loader_list_window then
    return
  end

  flib_gui.add(player.gui.screen, {
    type = "frame",
    name = "mdrn_loader_list_window",
    direction = "vertical",
    caption = "Loaders Modernized - Miniloaders not migrated",
    elem_mods = { auto_center = true },
    {
      type = "frame",
      style = "inside_shallow_frame_with_padding",
      { type = "label", style_mods = { single_line = false }, caption = not_migrated_notice },
    },
    {
      type = "scroll-pane",
      {
        type = "frame",
        style = "inside_shallow_frame_with_padding",
        {
          type = "table",
          name = "mdrn_loader_table",
          column_count = 4,
          children = non_migrated_loaders()
        },
      },
      {
        type = "flow",
        style = "dialog_buttons_horizontal_flow",
        drag_target = "mdrn_loader_list_window",
        {
          type = "button",
          style = "red_button",
          caption = "Remove all!",
          handler = {
            [defines.events.on_gui_click] = on_remove_all_clicked
          },
        },
        { type = "empty-widget", style = "flib_dialog_footer_drag_handle", ignored_by_interaction = true },
        {
          type = "button",
          style = "confirm_button",
          caption = "Next",
          handler = {
            [defines.events.on_gui_click] = on_next_clicked
          },
        }
      }
    }
  })
end

---Replace found Miniloaders
---@param e EventData.on_gui_click
local function replace_miniloaders(e)
  storage.complex_split = storage.complex_split or {}
  for i_ml, ml in pairs(storage.miniloaders_to_migrate) do
    if replace_miniloader(ml) then
      storage.miniloaders_to_migrate[i_ml] = nil
    end
  end

  if not next(storage.miniloaders_to_migrate) then
    storage.miniloaders_to_migrate = nil
  end

  local player = game.get_player(e.player_index)
  if not player then
    return
  end

  for _, p in pairs(game.players) do
    local window = p.gui.screen.mdrn_loader_warning_window
    if window then
      window.destroy()
    end
  end

  create_not_migrated_list(e.player_index)
end

---Display migration notification
---@param player LuaPlayer
local function create_notification(player)
  if player.gui.screen.mdrn_loader_warning_window then
    return
  end

  flib_gui.add(player.gui.screen, {
    type = "frame",
    name = "mdrn_loader_warning_window",
    style_mods = { width = 500 },
    direction = "vertical",
    caption = "Loaders Modernized",
    elem_mods = { auto_center = true },
    {
      type = "frame",
      style = "inside_shallow_frame_with_padding",
      { type = "label", style_mods = { single_line = false }, caption = warning_notice },
    },
    {
      type = "flow",
      style = "dialog_buttons_horizontal_flow",
      drag_target = "mdrn_loader_warning_window",
      { type = "empty-widget", style = "flib_dialog_footer_drag_handle", ignored_by_interaction = true },
      {
        type = "button",
        style = "confirm_button",
        caption = "Migrate!",
        tooltip = "Migrate Miniloaders that we can migrate, GO! GO! GO!",
        handler = {
          [defines.events.on_gui_click] = replace_miniloaders
        },
      }
    }
  })
end

---Gui handlers
flib_gui.add_handlers{
  replace_miniloaders = replace_miniloaders,
  on_ping_miniloaders_clicked = on_ping_miniloader_clicked,
  on_remove_clicked = on_remove_clicked,
  on_next_clicked = on_next_clicked,
  on_remove_all_clicked = on_remove_all_clicked,
  on_clear_all_clicked = on_clear_all_clicked,
  on_clear_complex_split_clicked = on_clear_complex_split_clicked,
  on_closed_clicked = on_closed_clicked,
}

---Find all miniloaders and disable their operation
local function find_and_disable_all_miniloaders()
  if storage.miniloaders_to_migrate then
    return
  end

  ---@type table<integer, string>
  local miniloader_parts = {}
  for _,v in pairs(prototypes.get_entity_filtered{{filter = "type", type = {"loader-1x1", "inserter"}}}) do
    if string.find(v.name, "miniloader") then
      miniloader_parts[#miniloader_parts+1] = v.name
    end
  end


  ---@type table<integer, LuaEntity>
  local to_migrate = {}
  for _, surface in pairs(game.surfaces) do
    local miniloaders = surface.find_entities_filtered{type = {"loader-1x1", "inserter"}, name = miniloader_parts}
    for _, m in pairs(miniloaders) do
      m.active = false
      m.operable = false
      if m.type == "loader-1x1" then
        to_migrate[m.unit_number] = m
      end
    end
  end

  storage.miniloaders_to_migrate = to_migrate
end

---Entry point to start the migration process
local function migrate()
  find_and_disable_all_miniloaders()
  for _, player in pairs(game.players) do
    create_notification(player)
  end
end

local from_miniloader = {}
---Process on_configuration_changed events
from_miniloader.on_configuration_changed = function()
  migrate()
end

---Console command to reopen migration window
---@param cd CustomCommandData
commands.add_command("mdrn-migrations", nil, function(cd)
  create_not_migrated_list(cd.player_index)
end)

return from_miniloader