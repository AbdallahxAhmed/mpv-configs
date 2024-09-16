local utils = require('mp.utils')
local msg = require('mp.msg')
local options = require('mp.options')

local script_options = {
    properties = "volume,sub-scale,audio-delay,sub-delay,audio,sub",
    config_file = "persistent_properties.json"
}

options.read_options(script_options, "persist_properties")

local properties_to_persist = {}
for prop in string.gmatch(script_options.properties, "([^,]+)") do
    properties_to_persist[prop] = true
end

local config_path = mp.find_config_file(script_options.config_file)
if not config_path then
    config_path = utils.join_path(mp.find_config_file('.'), script_options.config_file)
end

local persisted_properties = {}
local has_ass_subtitle = false

local function log(level, message)
    msg[level](message)
end

local function load_config()
    local file = io.open(config_path, "r")
    if file then
        local content = file:read("*all")
        file:close()
        local success, data = pcall(utils.parse_json, content)
        if success then
            return data
        else
            log("warn", "Failed to parse config file: " .. data)
        end
    else
        log("info", "No existing config file found. Will create a new one.")
    end
    return {}
end

local function save_config()
    for name in pairs(properties_to_persist) do
        if name ~= "sub" or not has_ass_subtitle then
            local value = mp.get_property_native(name)
            persisted_properties[name] = value
            log("info", string.format("Captured property %s = %s", name, utils.to_string(value)))
        end
    end

    local file = io.open(config_path, "w")
    if file then
        local success, content = pcall(utils.format_json, persisted_properties)
        if success then
            file:write(content)
            file:close()
            log("info", "Config saved successfully")
            mp.osd_message("Persistent properties saved", 2)
        else
            log("error", "Failed to format config data: " .. content)
            file:close()
        end
    else
        log("error", "Failed to open config file for writing: " .. config_path)
    end
end

local function apply_properties()
    for name, value in pairs(persisted_properties) do
        if properties_to_persist[name] and (name ~= "sub" or not has_ass_subtitle) then
            local success, err = pcall(mp.set_property_native, name, value)
            if success then
                log("info", string.format("Applied property %s = %s", name, utils.to_string(value)))
            else
                log("warn", string.format("Failed to apply property %s: %s", name, err))
            end
        end
    end
    mp.osd_message("Persistent properties applied", 2)
end

local function check_for_ass_subtitle()
    local video_path = mp.get_property("path")
    if video_path then
        local video_dir, video_name = utils.split_path(video_path)
        local ass_name = string.gsub(video_name, "%.[^%.]+$", ".ass")
        local ass_path = utils.join_path(video_dir, ass_name)
        
        local file = io.open(ass_path, "r")
        if file then
            file:close()
            has_ass_subtitle = true
            log("info", "Found matching .ass subtitle file: " .. ass_path)
            mp.commandv("sub-add", ass_path)
            mp.set_property("sub-visibility", "yes")
        else
            has_ass_subtitle = false
        end
    end
end

mp.register_event("file-loaded", function()
    check_for_ass_subtitle()
    persisted_properties = load_config()
    apply_properties()
    log("info", "Properties loaded and applied on file load")
end)

mp.register_event("end-file", function()
    save_config()
    log("info", "Properties saved on end-file event")
end)

mp.register_event("shutdown", function()
    save_config()
    log("info", "Properties saved on shutdown")
end)

-- Provide a way to manually save config
mp.add_key_binding("Ctrl+Alt+S", "save-persistent-properties", function()
    save_config()
end)

log("info", "Property persistence script loaded")