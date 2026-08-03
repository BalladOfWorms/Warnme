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
-- //wm test display, live-resolution centering, category-scoped ID
-- lookups, gaze/radius/damage-type detail lines, //wm audit and
-- //wm dump for checking the database against Windower's resources.

_addon.name = 'WarnMe'
_addon.author = 'Deridjian'
_addon.version = '1.2.3'
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
-- Damage type + element on their own line ('Magical | Fire'). Off by
-- default: the targeting and effects lines are the ones that change how
-- you react, this one is reference. //wm toggle kind turns it on.
defaults.info.show.kind = false

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

-- Ability info storage.
--
-- Action IDs are only unique WITHIN an action category: monster ability
-- 322 is 1,000 Needles while spell 322 is something else entirely, so a
-- single id->entry table hands the wrong details to any spell or job
-- ability that happens to share a number with a mob skill. Entries that
-- declare <cat> are therefore keyed '<category>:<id>'; the flat id table
-- is only kept for hand-written entries that predate <cat>, and is only
-- consulted for monster abilities (category 7), where those legacy IDs
-- came from.
local ability_info_by_name = {}
local ability_info_by_cat_id = {}
local ability_info_by_id = {}

-- Shared parser for ability_info.xml and ability_info_custom.xml. Returns
-- the number of <ability> blocks read and how many carried an ID, or nil
-- plus an error string when the file cannot be opened.
local function parse_ability_file(filepath)
    local file = io.open(filepath, 'r')
    if not file then
        return nil, 'not found'
    end

    local content = file:read('*all')
    file:close()

    local blocks, with_id = 0, 0

    for block in content:gmatch('<ability>%s*(.-)%s*</ability>') do
        local name = block:match('<n>%s*(.-)%s*</n>')
        local id = tonumber(block:match('<id>%s*(%d+)%s*</id>'))
        local cat = tonumber(block:match('<cat>%s*(%d+)%s*</cat>'))

        local entry = {
            self_target = block:match('<self_target>%s*(%a+)%s*</self_target>') == 'true',
            aoe = block:match('<aoe>%s*(%a+)%s*</aoe>') == 'true',
            fan = block:match('<fan>%s*(%a+)%s*</fan>') == 'true',
            cone = block:match('<cone>%s*(%a+)%s*</cone>') == 'true',
            gaze = block:match('<gaze>%s*(%a+)%s*</gaze>') == 'true',
            shape = block:match('<shape>%s*(.-)%s*</shape>'),
            dmgtype = block:match('<type>%s*(.-)%s*</type>'),
            element = block:match('<element>%s*(.-)%s*</element>'),
            effects = block:match('<effects>%s*(.-)%s*</effects>') or '',
        }

        blocks = blocks + 1
        if name then
            ability_info_by_name[name:lower()] = entry
        end
        if id then
            with_id = with_id + 1
            if cat then
                ability_info_by_cat_id[cat .. ':' .. id] = entry
            else
                ability_info_by_id[id] = entry
            end
        end
    end

    return blocks, with_id
end

function load_ability_info()
    ability_info_by_name = {}
    ability_info_by_cat_id = {}
    ability_info_by_id = {}

    local filepath = windower.addon_path .. 'ability_info.xml'
    local blocks, with_id = parse_ability_file(filepath)
    if not blocks then
        windower.add_to_chat(123, "[WarnMe] ability_info.xml not found at: " .. filepath)
        return
    end

    windower.add_to_chat(200, string.format(
        "[WarnMe] Loaded %d ability entries (%d with an action ID)",
        blocks, with_id))
end

-- Optional hand-curated overrides: ability_info_custom.xml uses the
-- same format and is loaded AFTER the generated file, so its entries
-- win on name/id collisions. Keep manual corrections there -- they
-- survive regenerating ability_info.xml from the bestiary.
function load_ability_info_custom()
    local blocks, with_id =
        parse_ability_file(windower.addon_path .. 'ability_info_custom.xml')
    if not blocks then
        return
    end
    windower.add_to_chat(200, string.format(
        "[WarnMe] Loaded %d custom override entries (%d with an action ID)",
        blocks, with_id))
end

-- Load on startup
load_ability_info()
load_ability_info_custom()

-- WHICH FIELD CARRIES THE ID DEPENDS ON THE CATEGORY, and the packet
-- offers two that both look plausible.
--
--   6 (job ability): the id is the packet's own Param. The ACTION param
--       is the VALUE -- damage, HP restored, or 0 -- so reading that as
--       an id turned a mob merely using a JA into an on-screen warning
--       reading 'Unknown ability (<some number>)' with no move behind
--       it. (Debuffed keys Corsair's Light Shot off `act.category == 6
--       and act.param == 131`, which is that job ability's id: the same
--       field, arrived at independently.)
--   7 (weapon skill / TP move start) and 8 (casting start): the move
--       being readied is in the ACTION's param, which is where the rest
--       of this addon has always read it from.
function action_id_for(action, category)
    if category == 6 then
        return action.param
    end
    local a1 = action.targets[1] and action.targets[1].actions
               and action.targets[1].actions[1]
    return a1 and a1.param
end

-- Anything that reaches the display with an id no resource file knows
-- gets written down once, with BOTH param fields and the message id,
-- because those three are what tell a real unnamed move apart from a row
-- that was never an ability. Capped: this must never become a file that
-- grows while you play.
local unknown_logged, UNKNOWN_LOG_MAX = 0, 50

function log_unknown_action(action, category, ability_id)
    if unknown_logged >= UNKNOWN_LOG_MAX then return end
    unknown_logged = unknown_logged + 1
    local a1 = action.targets[1] and action.targets[1].actions
               and action.targets[1].actions[1]
    local actor = windower.ffxi.get_mob_by_id(action.actor_id)
    local f = io.open(windower.addon_path .. 'warnme_unknown.txt', 'a')
    if not f then return end
    f:write(string.format(
        '%s  category %d  id %s  packet param %s  action param %s  '
        .. 'message %s  actor %s\n',
        os.date('%Y-%m-%d %H:%M:%S'), category, tostring(ability_id),
        tostring(action.param), tostring(a1 and a1.param),
        tostring(a1 and a1.message),
        actor and actor.name or '?'))
    f:close()
end

-- Returns nil when this row is not worth a warning at all -- and draws
-- nothing in that case, so the caller must check before building a body.
function display_action(action, category)
    local language = windower.ffxi.get_info().language == "English" and 'en' or 'ja'
    local ability_id = action_id_for(action, category)
    local categories = {[6]="job_abilities", [7]="monster_abilities", [8]="spells"}
    local pool = res[categories[category]]
    local entry = ability_id and pool and pool[ability_id]
    local action_name = entry and entry[language]

    if not action_name then
        log_unknown_action(action, category, ability_id)
        -- A readied TP move or a cast is a real event even when the name
        -- will not resolve: something IS coming, which is the whole job
        -- of this addon, and new content does run ahead of the resource
        -- files. A job ability is not the same thing -- there is nothing
        -- to step out of, and an unresolved one is far likelier to be a
        -- row that was never an ability than to be new content.
        if category == 6 then
            return nil
        end
        action_name = string.format('Unknown ability (%s)',
                                    tostring(ability_id))
    end

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
function show_body(details_string, targeting_line, kind_line, effects_line)
    local lines = {}
    for _, l in ipairs({details_string, targeting_line, kind_line,
                        effects_line}) do
        if l and l ~= '' then
            lines[#lines + 1] = l
        end
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

-- Category first (exact), then the name the game reported, then the
-- legacy category-less IDs -- and those only for monster abilities,
-- since that is the one category they were ever built from.
function ability_entry_for(category, ability_id, ability_name)
    local entry
    if category and ability_id then
        entry = ability_info_by_cat_id[category .. ':' .. ability_id]
    end
    if not entry and ability_name then
        entry = ability_info_by_name[ability_name:lower()]
    end
    if not entry and ability_id and (category == nil or category == 7) then
        entry = ability_info_by_id[ability_id]
    end
    return entry
end

function info_lines_for(category, ability_id, ability_name)
    if not settings.info.show.enabled then
        return nil, nil, nil
    end

    local info_data = ability_entry_for(category, ability_id, ability_name)
    if not info_data then
        return nil, nil, nil
    end

    local info_parts = {}
    if info_data.self_target then table.insert(info_parts, "Self") end
    if info_data.aoe then table.insert(info_parts, "AOE") end
    if info_data.fan then table.insert(info_parts, "Fan") end
    if info_data.cone then table.insert(info_parts, "Conal") end
    -- Gaze moves only land on players facing the mob, which is the one
    -- targeting fact you can still act on after the name goes up.
    if info_data.gaze then table.insert(info_parts, "Gaze") end
    -- Radius/reach, when the bestiary measured it ("15' radial").
    if info_data.shape and info_data.shape ~= '' then
        table.insert(info_parts, info_data.shape)
    end

    local targeting_line = nil
    if #info_parts > 0 then
        targeting_line = table.concat(info_parts, " | ")
    end

    local kind_line = nil
    if settings.info.show.kind then
        local kind_parts = {}
        if info_data.dmgtype and info_data.dmgtype ~= '' then
            table.insert(kind_parts, info_data.dmgtype)
        end
        if info_data.element and info_data.element ~= '' then
            table.insert(kind_parts, info_data.element)
        end
        if #kind_parts > 0 then
            kind_line = table.concat(kind_parts, " | ")
        end
    end

    return targeting_line, kind_line, info_data.effects
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
            -- display_action drew nothing and said so: not a warning.
            if ability_name then
                local details_string = nil
                if settings.details.show.actor or settings.details.show.target then
                    details_string = details_line_for(action)
                end
                local targeting_line, kind_line, effects_line =
                    info_lines_for(action.category, ability_id, ability_name)
                show_body(details_string, targeting_line, kind_line, effects_line)

                if not forced then
                    coroutine.schedule(hide_and_clear, settings.timeout)
                end
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
        elseif arg[1] == 'kind' then
            settings.info.show.kind = not settings.info.show.kind
            windower.add_to_chat(200, "[WarnMe] Damage type line: "..tostring(settings.info.show.kind))
            settings:save()
        else
            windower.add_to_chat(167, "[WarnMe] Usage: //wm toggle [actor/target/spells/info/kind]")
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

        local targeting_line, kind_line, effects_line = nil, nil, nil
        if arg[1] then
            local result = ability_info_by_name[test_name:lower()]
            if result then
                windower.add_to_chat(200, "[WarnMe] FOUND! Effects: "..result.effects)
            else
                windower.add_to_chat(200, "[WarnMe] NOT FOUND (display shown without info)")
            end
            targeting_line, kind_line, effects_line =
                info_lines_for(nil, nil, test_name)
        elseif settings.info.show.enabled then
            targeting_line = "AOE | Conal | 15' radial"
            kind_line = settings.info.show.kind and "Magical | Fire" or nil
            effects_line = "Paralysis, Silence"
        end
        show_body(details_string, targeting_line, kind_line, effects_line)

        if not forced then
            coroutine.schedule(hide_and_clear, settings.timeout)
        end
        windower.add_to_chat(200, "[WarnMe] Display test — hides in "
            ..settings.timeout.."s (//wm sticky for a persistent one)")

    elseif cmd == 'audit' then
        -- Check the database against Windower's own resource files: which
        -- mob skills the game knows about have no entry here, and which
        -- entries here match no name the game uses (usually a misspelling
        -- that would never fire in-game). Writes the full lists to
        -- warnme_audit.txt next to the addon.
        local missing, name_only, unknown = {}, {}, {}
        local known = {}
        for _, pool in ipairs({'monster_abilities', 'job_abilities',
                               'weapon_skills', 'spells'}) do
            for _, entry in pairs(res[pool]) do
                if entry.en and entry.en ~= '' then
                    known[entry.en:lower()] = true
                end
            end
        end
        for id, entry in pairs(res.monster_abilities) do
            if entry.en and entry.en ~= '' then
                if not ability_info_by_cat_id['7:' .. id] then
                    if ability_info_by_name[entry.en:lower()] then
                        table.insert(name_only,
                            string.format('%5d  %s', id, entry.en))
                    else
                        table.insert(missing,
                            string.format('%5d  %s', id, entry.en))
                    end
                end
            end
        end
        for name in pairs(ability_info_by_name) do
            if not known[name] then
                table.insert(unknown, name)
            end
        end
        table.sort(missing); table.sort(name_only); table.sort(unknown)

        windower.add_to_chat(200, string.format(
            "[WarnMe] Audit: %d mob skills with no entry, %d matched by name "
            .. "but missing their ID, %d entries the game never names",
            #missing, #name_only, #unknown))

        local path = windower.addon_path .. 'warnme_audit.txt'
        local f = io.open(path, 'w')
        if not f then
            windower.add_to_chat(123, "[WarnMe] Could not write " .. path)
        else
            f:write('WarnMe database audit\n\n')
            f:write(string.format(
                '%d monster abilities in res have no <ability> entry:\n',
                #missing))
            f:write(table.concat(missing, '\n'))
            f:write(string.format(
                '\n\n%d match an entry by name but that entry has no <id>:\n',
                #name_only))
            f:write(table.concat(name_only, '\n'))
            f:write(string.format(
                '\n\n%d entry names appear in no resource file:\n', #unknown))
            f:write(table.concat(unknown, '\n'))
            f:write('\n')
            f:close()
            windower.add_to_chat(200, "[WarnMe] Wrote " .. path)
        end

    elseif cmd == 'dump' then
        -- Dump every action name the resource files know, as
        -- 'category|id|name'. That file is what a database rebuild needs
        -- to attach real IDs to name-only entries and to cover spells and
        -- job abilities, which have no IDs here at all yet.
        local path = windower.addon_path .. 'warnme_res_dump.txt'
        local f = io.open(path, 'w')
        if not f then
            windower.add_to_chat(123, "[WarnMe] Could not write " .. path)
        else
            f:write('# WarnMe resource dump: category|id|english name\n')
            f:write('# 3 = weapon skill, 6 = job ability, 7 = monster '
                .. 'ability, 8 = spell\n')
            local total = 0
            for _, pair in ipairs({{7, 'monster_abilities'},
                                   {6, 'job_abilities'},
                                   {3, 'weapon_skills'},
                                   {8, 'spells'}}) do
                local ids = {}
                for id, entry in pairs(res[pair[2]]) do
                    if entry.en and entry.en ~= '' then
                        table.insert(ids, id)
                    end
                end
                table.sort(ids)
                for _, id in ipairs(ids) do
                    f:write(string.format('%d|%d|%s\n', pair[1], id,
                        res[pair[2]][id].en))
                    total = total + 1
                end
            end
            f:close()
            windower.add_to_chat(200, string.format(
                "[WarnMe] Wrote %d rows to %s", total, path))
        end

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
            local targeting_line, kind_line, effects_line = nil, nil, nil
            if settings.info.show.enabled then
                targeting_line = "AOE | Conal | 15' radial"
                kind_line = settings.info.show.kind and "Magical | Fire" or nil
                effects_line = "Paralysis, Silence"
            end
            show_body(details_string, targeting_line, kind_line, effects_line)
        end

    else
        local function onoff(v) return v and "ON" or "OFF" end
        windower.add_to_chat(200, "WarnMe - Enemy ability notification")
        windower.add_to_chat(207, "//wm toggle actor   -- show acting mob's name ["..onoff(settings.details.show.actor).."]")
        windower.add_to_chat(207, "//wm toggle target  -- show ability's victim ["..onoff(settings.details.show.target).."]")
        windower.add_to_chat(207, "//wm toggle spells  -- warn on spells too, not just TP moves ["..onoff(settings.ability.show.spells).."]")
        windower.add_to_chat(207, "//wm toggle info    -- show targeting + debuff lines ["..onoff(settings.info.show.enabled).."]")
        windower.add_to_chat(207, "//wm toggle kind    -- add a damage type/element line ["..onoff(settings.info.show.kind).."]")
        windower.add_to_chat(207, "//wm watch  -- warn for ALL alliance-claimed mobs vs current target only ["..(settings.ability.show.watchall and "ALL" or "TARGET").."]")
        windower.add_to_chat(207, "//wm mode   -- also warn for unclaimed/others' mobs ["..onoff(settings.ability.show.others).."]")
        windower.add_to_chat(207, "//wm timeout [seconds] -- how long warnings stay up ["..settings.timeout.."s]")
        windower.add_to_chat(207, "//wm size [ability/details/info] [size]")
        windower.add_to_chat(207, "//wm tune [0.5-1.5] -- centering em adjustment")
        windower.add_to_chat(207, "//wm test [ability name] -- show the display now")
        windower.add_to_chat(207, "//wm sticky -- persistent test display (toggle)")
        windower.add_to_chat(207, "//wm reload -- reload ability info files")
        windower.add_to_chat(207, "//wm audit  -- check the database against Windower's resources")
        windower.add_to_chat(207, "//wm dump   -- write every resource action name to a file")
    end
end)