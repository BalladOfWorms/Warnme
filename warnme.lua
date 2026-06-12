--[[ BSD 3-Clause License

Copyright (c) 2022, Marian Arlt
All rights reserved.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met:

1. Redistributions of source code must retain the above copyright notice, this
   list of conditions and the following disclaimer.

2. Redistributions in binary form must reproduce the above copyright notice,
   this list of conditions and the following disclaimer in the documentation
   and/or other materials provided with the distribution.

3. Neither the name of the copyright holder nor the names of its
   contributors may be used to endorse or promote products derived from
   this software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE
FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE. ]]

-- Modified version; changes distributed under the same BSD 3-Clause
-- License above. Original addon by Deridjian. This fork adds:
-- ability-details database (ability_info.xml + ability_info_custom.xml
-- overrides), unified body box, red headline, watch-all scope,
-- //wm test display, live-resolution centering.

_addon.name = 'WarnMe'
_addon.author = 'Deridjian'
_addon.version = '1.2'
_addon.command = 'wm'

config = require('config')
texts = require('texts')
res = require('resources')

local defaults = {}
defaults.screen = windower.get_windower_settings().ui_x_res
defaults.timeout = 4
defaults.fontem = 0.9

defaults.ability = {}
defaults.ability.pos = {}
defaults.ability.pos.x = defaults.screen / 2
defaults.ability.pos.y = windower.get_windower_settings().ui_y_res / 2
defaults.ability.flags = {}
defaults.ability.flags.bold = true
defaults.ability.text = {}
defaults.ability.text.size = 38
defaults.ability.text.font = 'Lucida Console'
-- Bright warning red for the ability headline; the black stroke
-- below keeps it readable over any scene.
defaults.ability.text.red = 255
defaults.ability.text.green = 30
defaults.ability.text.blue = 30
defaults.ability.text.stroke = {}
defaults.ability.text.stroke.width = 2
defaults.ability.text.stroke.alpha = 210
defaults.ability.bg = {}
defaults.ability.bg.visible = false
defaults.ability.show = {}
defaults.ability.show.spells = true
defaults.ability.show.others = false
defaults.ability.show.watchall = false

defaults.details = {}
defaults.details.pos = {}
defaults.details.pos.x = defaults.ability.pos.x
defaults.details.pos.y = defaults.ability.pos.y + defaults.ability.text.size * 1.75
defaults.details.flags = {}
defaults.details.flags.bold = true
defaults.details.text = {}
defaults.details.text.size = defaults.ability.text.size / 2.5
defaults.details.text.font = defaults.ability.text.font
defaults.details.text.stroke = {}
defaults.details.text.stroke.width = 1
defaults.details.bg = {}
defaults.details.bg.visible = false
defaults.details.show = {}
defaults.details.show.actor = true
defaults.details.show.target = true

defaults.info = {}
defaults.info.pos = {}
defaults.info.pos.x = defaults.ability.pos.x
defaults.info.pos.y = defaults.details.pos.y + defaults.details.text.size * 2
defaults.info.flags = {}
defaults.info.flags.bold = true
defaults.info.text = {}
defaults.info.text.size = defaults.ability.text.size / 2.5
defaults.info.text.font = defaults.ability.text.font
defaults.info.text.red = 255
defaults.info.text.green = 128
defaults.info.text.blue = 255
defaults.info.text.stroke = {}
defaults.info.text.stroke.width = 1
defaults.info.bg = {}
defaults.info.bg.visible = false
defaults.info.show = {}
defaults.info.show.enabled = true

settings = config.load(defaults)

-- The saved <screen> value goes stale whenever the game resolution
-- changes (a leftover 2560 here pushes the visual center 320px to the
-- right on a 1920-wide screen). Always trust the live Windower
-- resolution; the stored value is refreshed to match.
settings.screen = windower.get_windower_settings().ui_x_res

local ability = texts.new('', settings.ability, settings)
local details = texts.new('', settings.details, settings)
local info = texts.new('', settings.info, settings)
local forced

-- Ability info storage
local ability_info_by_name = {}
local ability_info_by_id = {}

function load_ability_info()
    ability_info_by_name = {}
    ability_info_by_id = {}
    
    local filepath = windower.addon_path..'ability_info.xml'
    local file, err = io.open(filepath, 'r')
    if not file then
        windower.add_to_chat(123, "[WarnMe] ability_info.xml not found at: "..filepath)
        return
    end
    
    local content = file:read('*all')
    file:close()
    
    local count = 0
    
    for ability_block in content:gmatch('<ability>%s*(.-)%s*</ability>') do
        local name = ability_block:match('<n>%s*(.-)%s*</n>')
        local id = ability_block:match('<id>%s*(%d+)%s*</id>')
        local self_target = ability_block:match('<self_target>%s*(%a+)%s*</self_target>') == 'true'
        local aoe = ability_block:match('<aoe>%s*(%a+)%s*</aoe>') == 'true'
        local fan = ability_block:match('<fan>%s*(%a+)%s*</fan>') == 'true'
        local cone = ability_block:match('<cone>%s*(%a+)%s*</cone>') == 'true'
        local effects = ability_block:match('<effects>%s*(.-)%s*</effects>') or ''
        
        local entry = {
            self_target = self_target,
            aoe = aoe,
            fan = fan,
            cone = cone,
            effects = effects
        }
        
        if name then
            ability_info_by_name[name:lower()] = entry
            count = count + 1
        end
        if id then
            ability_info_by_id[tonumber(id)] = entry
            count = count + 1
        end
    end
    
    windower.add_to_chat(200, "[WarnMe] Loaded "..count.." ability info entries")
end

-- Optional hand-curated overrides: ability_info_custom.xml uses the
-- same format and is loaded AFTER the generated file, so its entries
-- win on name/id collisions. Keep manual corrections there — they
-- survive regenerating ability_info.xml from server data.
function load_ability_info_custom()
    local filepath = windower.addon_path..'ability_info_custom.xml'
    local file = io.open(filepath, 'r')
    if not file then
        return
    end
    local content = file:read('*all')
    file:close()

    local count = 0
    for ability_block in content:gmatch('<ability>%s*(.-)%s*</ability>') do
        local name = ability_block:match('<n>%s*(.-)%s*</n>')
        local id = ability_block:match('<id>%s*(%d+)%s*</id>')
        local self_target = ability_block:match('<self_target>%s*(%a+)%s*</self_target>') == 'true'
        local aoe = ability_block:match('<aoe>%s*(%a+)%s*</aoe>') == 'true'
        local fan = ability_block:match('<fan>%s*(%a+)%s*</fan>') == 'true'
        local cone = ability_block:match('<cone>%s*(%a+)%s*</cone>') == 'true'
        local effects = ability_block:match('<effects>%s*(.-)%s*</effects>') or ''

        local entry = {
            self_target = self_target,
            aoe = aoe,
            fan = fan,
            cone = cone,
            effects = effects
        }

        if name then
            ability_info_by_name[name:lower()] = entry
            count = count + 1
        end
        if id then
            ability_info_by_id[tonumber(id)] = entry
            count = count + 1
        end
    end

    windower.add_to_chat(200, "[WarnMe] Loaded "..count.." custom override entries")
end

-- Load on startup
load_ability_info()
load_ability_info_custom()

function display_action(action, category)
    local language = windower.ffxi.get_info().language == "English" and 'en' or 'ja'
    local ability_id = action.targets[1].actions[1].param
    local categories = {[6]="job_abilities", [7]="monster_abilities", [8]="spells"}
    local action_name = res[categories[category]][ability_id][language]

    ability:text(action_name)
    align_center(ability, 'ability', action_name)
    ability:show()
    
    return ability_id, action_name
end

function details_line_for(action)
    local actor = windower.ffxi.get_mob_by_id(action.actor_id)
    local actor_target = windower.ffxi.get_mob_by_id(action.targets[1].id)

    if settings.details.show.actor and settings.details.show.target then
        return actor.name.." > "..actor_target.name
    elseif settings.details.show.actor and not settings.details.show.target then
        return actor.name
    else
        return "on "..actor_target.name
    end
end

-- One body box under the headline: the actor/target line and the info
-- lines (targeting + effects) live in a single texts element, padded
-- line-by-line to a common center (monospace font makes the padding
-- exact). One element means one position, one drag handle, and no
-- per-element centering drift between the rows.
function show_body(details_string, targeting_line, effects_line)
    local lines = {}
    if details_string and details_string ~= '' then
        lines[#lines + 1] = details_string
    end
    if targeting_line and targeting_line ~= '' then
        lines[#lines + 1] = targeting_line
    end
    if effects_line and effects_line ~= '' then
        lines[#lines + 1] = effects_line
    end
    if #lines == 0 then
        return
    end

    local longest = ''
    for _, l in ipairs(lines) do
        if #l > #longest then longest = l end
    end
    for i, l in ipairs(lines) do
        if #l < #longest then
            lines[i] = string.rep(' ', math.floor((#longest - #l) / 2)) .. l
        end
    end

    details:text(table.concat(lines, "\n"))
    align_center(details, 'details', longest)
    details:show()
end

function info_lines_for(ability_id, ability_name)
    if not settings.info.show.enabled then
        return nil, nil
    end

    local info_data = ability_info_by_id[ability_id]
    if not info_data and ability_name then
        info_data = ability_info_by_name[ability_name:lower()]
    end
    if not info_data then
        return nil, nil
    end

    local info_parts = {}
    if info_data.self_target then table.insert(info_parts, "Self") end
    if info_data.aoe then table.insert(info_parts, "AOE") end
    if info_data.fan then table.insert(info_parts, "Fan") end
    if info_data.cone then table.insert(info_parts, "Conal") end

    local targeting_line = nil
    if #info_parts > 0 then
        targeting_line = table.concat(info_parts, " | ")
    end
    return targeting_line, info_data.effects
end

function align_center(element, key, string)
    local pos_x = settings.screen / 2 - (#string * settings[key].text.size * settings.fontem / 2)
    element:pos(pos_x, settings[key].pos.y)
end

function hide_and_clear()
    ability:hide(); details:hide(); info:hide()
    ability:clear(); details:clear(); info:clear()
end

windower.register_event('action', function(action)
    -- The acting mob: with watchall on, ANY monster's action qualifies
    -- (claim gate below still applies), so a mob your alt is fighting
    -- warns you even while you target something else. With watchall
    -- off (default), only your current target's actions show — the
    -- original behavior.
    local actor = windower.ffxi.get_mob_by_id(action.actor_id)
    if actor and actor.spawn_type == 16 then
        if not settings.ability.show.watchall then
            local t = windower.ffxi.get_mob_by_target('t')
            if not (t and t.id == action.actor_id) then
                return
            end
        end

        -- Safety check for claim_id
        local claimer = windower.ffxi.get_mob_by_id(actor.claim_id)
        local is_claimed_by_alliance = claimer and claimer.in_alliance or false

        if
            (settings.ability.show.others or is_claimed_by_alliance) and
            (action.category == 6 or action.category == 7 or (action.category == 8 and settings.ability.show.spells))
        then
            local ability_id, ability_name = display_action(action, action.category)
            local details_string = nil
            if settings.details.show.actor or settings.details.show.target then
                details_string = details_line_for(action)
            end
            local targeting_line, effects_line =
                info_lines_for(ability_id, ability_name)
            show_body(details_string, targeting_line, effects_line)

            if not forced then
                coroutine.schedule(hide_and_clear, settings.timeout)
            end
        end
    end
end)

windower.register_event('addon command', function(command, ...)
    cmd = command and command:lower()
    local arg = {...}

    if cmd == 'toggle' then
        if arg[1] == 'actor' then
            settings.details.show.actor = not settings.details.show.actor
            windower.add_to_chat(200, "[WarnMe] Actor: "..tostring(settings.details.show.actor))
            settings:save()
        elseif arg[1] == 'target' then
            settings.details.show.target = not settings.details.show.target
            windower.add_to_chat(200, "[WarnMe] Target: "..tostring(settings.details.show.target))
            settings:save()
        elseif arg[1] == 'spells' then
            settings.ability.show.spells = not settings.ability.show.spells
            windower.add_to_chat(200, "[WarnMe] Spells: "..tostring(settings.ability.show.spells))
            settings:save()
        elseif arg[1] == 'info' then
            settings.info.show.enabled = not settings.info.show.enabled
            windower.add_to_chat(200, "[WarnMe] Info: "..tostring(settings.info.show.enabled))
            settings:save()
        else
            windower.add_to_chat(167, "[WarnMe] Usage: //wm toggle [actor/target/spells/info]")
        end

    elseif cmd == 'reload' then
        load_ability_info()
        load_ability_info_custom()

    elseif cmd == 'test' then
        -- Render the real display on demand, then auto-hide after the
        -- configured timeout — for checking placement, sizes, and
        -- centering without waiting for a mob to act.
        --   //wm test                -> generic preview
        --   //wm test <ability name> -> preview using that ability's
        --                               info lines (if known)
        local player = windower.ffxi.get_player()
        local pname = player and player.name or 'You'
        local test_name = arg[1] and table.concat(arg, " ")
                          or "Display Test"

        if arg[1] then
            -- Resolve the canonical capitalization from Windower's
            -- resources so '//wm test sound blast' displays exactly
            -- as the game would: 'Sound Blast'. Unknown names typed
            -- in all-lowercase get a simple title-case instead.
            local want = test_name:lower()
            local resolved = false
            for _, entry in pairs(res.monster_abilities) do
                if entry.en and entry.en:lower() == want then
                    test_name = entry.en
                    resolved = true
                    break
                end
            end
            if not resolved and test_name == test_name:lower() then
                test_name = test_name:gsub("(%a)([%w']*)", function(a, b)
                    return a:upper() .. b
                end)
            end
        end

        ability:text(test_name)
        align_center(ability, 'ability', test_name)
        ability:show()

        local details_string = nil
        if settings.details.show.actor or settings.details.show.target then
            if settings.details.show.actor and settings.details.show.target then
                details_string = "Testlix > "..pname
            elseif settings.details.show.actor then
                details_string = "Testlix"
            else
                details_string = "on "..pname
            end
        end

        local targeting_line, effects_line = nil, nil
        if arg[1] then
            local result = ability_info_by_name[test_name:lower()]
            if result then
                windower.add_to_chat(200, "[WarnMe] FOUND! Effects: "..result.effects)
            else
                windower.add_to_chat(200, "[WarnMe] NOT FOUND (display shown without info)")
            end
            targeting_line, effects_line = info_lines_for(nil, test_name)
        elseif settings.info.show.enabled then
            targeting_line = "AOE | Conal"
            effects_line = "Paralysis, Silence"
        end
        show_body(details_string, targeting_line, effects_line)

        if not forced then
            coroutine.schedule(hide_and_clear, settings.timeout)
        end
        windower.add_to_chat(200, "[WarnMe] Display test — hides in "
            ..settings.timeout.."s (//wm sticky for a persistent one)")

    elseif cmd == 'timeout' then
        if not tonumber(arg[1]) then
            windower.add_to_chat(167, "[WarnMe] Usage: //wm timeout [seconds]")
        else
            settings.timeout = tonumber(arg[1])
            settings:save()
            windower.add_to_chat(200, "[WarnMe] Timeout: "..arg[1].." seconds")
        end

    elseif cmd == 'size' then
        if not tonumber(arg[2]) then
            windower.add_to_chat(167, "[WarnMe] Usage: //wm size [ability/details/info] [size]")
        elseif arg[1] == 'ability' or arg[1] == 'details' or arg[1] == 'info' then
            if arg[1] == 'ability' then
                settings.ability.text.size = tonumber(arg[2])
                settings.details.pos.y = settings.ability.pos.y + tonumber(arg[2]) * 1.75
            elseif arg[1] == 'details' then
                settings.details.text.size = tonumber(arg[2])
            elseif arg[1] == 'info' then
                settings.info.text.size = tonumber(arg[2])
            end
            settings:save()
            config.reload(settings)
            windower.add_to_chat(200, "[WarnMe] Size updated")
        else
            windower.add_to_chat(167, "[WarnMe] First arg must be: ability/details/info")
        end

    elseif cmd == 'watch' then
        settings.ability.show.watchall = not settings.ability.show.watchall
        settings:save()
        if settings.ability.show.watchall then
            windower.add_to_chat(200, "[WarnMe] Watching ALL alliance-claimed mobs (not just your target)")
        else
            windower.add_to_chat(200, "[WarnMe] Watching your current target only")
        end

    elseif cmd == 'mode' then
        settings.ability.show.others = not settings.ability.show.others
        windower.add_to_chat(200, "[WarnMe] Show others: "..tostring(settings.ability.show.others))
        settings:save()

    elseif cmd == 'tune' then
        if tonumber(arg[1]) and tonumber(arg[1]) >= 0.5 and tonumber(arg[1]) <= 1.5 then
            settings.fontem = tonumber(arg[1])
            settings:save()
            config.reload(settings)
            windower.add_to_chat(200, "[WarnMe] Alignment: "..arg[1].."em")
        else
            windower.add_to_chat(167, "[WarnMe] Value must be 0.5-1.5")
        end

    elseif cmd == 'sticky' then
        if forced then
            forced = nil
            hide_and_clear()
        else
            forced = true
            ability:text("Infinite Trouble")
            align_center(ability, 'ability', "Infinite Trouble")
            ability:show()
            local details_string = nil
            if settings.details.show.actor or settings.details.show.target then
                if settings.details.show.actor and settings.details.show.target then
                    details_string = "Debuglix > "..windower.ffxi.get_player().name
                elseif settings.details.show.actor and not settings.details.show.target then
                    details_string = "Debuglix"
                else
                    details_string = "on "..windower.ffxi.get_player().name
                end
            end
            local targeting_line, effects_line = nil, nil
            if settings.info.show.enabled then
                targeting_line = "AOE | Conal"
                effects_line = "Paralysis, Silence"
            end
            show_body(details_string, targeting_line, effects_line)
        end

    else
        local function onoff(v) return v and "ON" or "OFF" end
        windower.add_to_chat(200, "WarnMe - Enemy ability notification")
        windower.add_to_chat(207, "//wm toggle actor   -- show acting mob's name ["..onoff(settings.details.show.actor).."]")
        windower.add_to_chat(207, "//wm toggle target  -- show ability's victim ["..onoff(settings.details.show.target).."]")
        windower.add_to_chat(207, "//wm toggle spells  -- warn on spells too, not just TP moves ["..onoff(settings.ability.show.spells).."]")
        windower.add_to_chat(207, "//wm toggle info    -- show AOE/Conal + debuff lines ["..onoff(settings.info.show.enabled).."]")
        windower.add_to_chat(207, "//wm watch  -- warn for ALL alliance-claimed mobs vs current target only ["..(settings.ability.show.watchall and "ALL" or "TARGET").."]")
        windower.add_to_chat(207, "//wm mode   -- also warn for unclaimed/others' mobs ["..onoff(settings.ability.show.others).."]")
        windower.add_to_chat(207, "//wm timeout [seconds] -- how long warnings stay up ["..settings.timeout.."s]")
        windower.add_to_chat(207, "//wm size [ability/details/info] [size]")
        windower.add_to_chat(207, "//wm tune [0.5-1.5] -- centering em adjustment")
        windower.add_to_chat(207, "//wm test [ability name] -- show the display now")
        windower.add_to_chat(207, "//wm sticky -- persistent test display (toggle)")
        windower.add_to_chat(207, "//wm reload -- reload ability info files")
    end
end)