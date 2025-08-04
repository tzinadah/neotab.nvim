local api = vim.api
local config = require("neotab.config")
local log = require("neotab.logger")

---@class ntab.utils
local utils = {}

---@param x integer
---@param pos? integer[]
---@return string|nil
function utils.adj_char(x, pos)
    pos = pos or api.nvim_win_get_cursor(0)
    local col = pos[2] + x + 1

    local line = api.nvim_get_current_line()
    return line:sub(col, col)
end

function utils.tab()
    if config.user.act_as_tab then
        api.nvim_feedkeys(utils.replace("<Tab>"), "n", false)
    end
end

function utils.get_pair(char)
    if not char then
        return
    end

    local res = vim.tbl_filter(function(o)
        return o.close == char or o.open == char
    end, config.pairs)

    return not vim.tbl_isempty(res) and res[1] or nil
end

function utils.find_opening(info, line, col)
    if info.open == info.close then
        local idx = line:sub(1, col):reverse():find(info.open, 1, true)
        return idx and (#line - idx)
    end

    local c = 1
    for i = col, 1, -1 do
        local char = line:sub(i, i)

        if info.open == char then
            c = c - 1
        elseif info.close == char then
            c = c + 1
        end

        if c == 0 then
            return i
        end
    end
end

function utils.find_closing(info, line, col)
    if info.open == info.close then
        return line:find(info.close, col + 1, true)
    end

    local c = 1
    for i = col + 1, #line do
        local char = line:sub(i, i)

        if info.open == char then
            c = c + 1
        elseif info.close == char then
            c = c - 1
        end

        if c == 0 then
            return i
        end
    end
end

function utils.valid_pair(info, line, l, r)
    if info.open == info.close and line:sub(l, r):find(info.open, 1, true) then
        return true
    end

    local c = 1
    for i = l, r do
        local char = line:sub(i, i)

        if info.open == char then
            c = c + 1
        elseif info.close == char then
            c = c - 1
        end

        if c == 0 then
            return true
        end
    end

    return false
end

function utils.valid_pair_rev(info, line, l, r)
    if info.open == info.close and line:sub(l, r):find(info.open, 1, true) then
        return true
    end

    local c = 1
    for i = l, r do
        local char = line:sub(i, i)

        if info.open == char then
            c = c - 1
        elseif info.close == char then
            c = c + 1
        end

        if c == 0 then
            return true
        end
    end

    return false
end

---@alias ntab.pos { cursor: integer, char: integer }

---@param info ntab.pair
---@param line string
---@param col integer
---
---@return integer | nil
function utils.find_next_nested(info, line, col) --
    local char = line:sub(col - 1, col - 1)

    if info.open == info.close or info.close == char then
        for i = col, #line do
            char = line:sub(i, i)
            local char_info = utils.get_pair(char)

            if char_info then
                return i
            end
        end
    else
        local closing_idx = utils.find_closing(info, line, col - 1)
        local l, r = col, (closing_idx or #line)
        local first

        for i = l, r do
            char = line:sub(i, i)
            local char_info = utils.get_pair(char)

            if char_info and char == char_info.open then
                first = first or i
                if utils.valid_pair(char_info, line, i + 1, r) then
                    return i
                end
            end
        end

        return closing_idx or first
    end
end

---@param pair ntab.pair
---@param line string
---@param col integer
function utils.find_next_closing(pair, line, col) --
    local open_char = line:sub(col - 1, col - 1)

    local i
    if pair.open == pair.close then
        i = line:find(pair.close, col, true) --
    elseif open_char ~= pair.close then
        i = utils.find_closing(pair, line, col) --
            or line:find(pair.close, col, true)
    end

    return i or utils.find_next_nested(pair, line, col)
end

---@param pair ntab.pair
---@param line string
---@param col integer
---@param behavior ntab.behavior
---
---@return ntab.md | nil
function utils.find_next(pair, line, col, behavior) --
    local i

    if behavior == "closing" then
        i = utils.find_next_closing(pair, line, col)
    else
        i = utils.find_next_nested(pair, line, col)
    end

    if i then
        local prev = {
            pos = col - 1,
            char = line:sub(col - 1, col - 1),
        }

        local next = {
            pos = i,
            char = line:sub(i, i),
        }

        return {
            prev = prev,
            next = next,
            pos = math.max(col + 1, i),
        }
    end
end

---@param info ntab.pair
---@param line string
---@param col integer
---
---@return integer | nil
function utils.find_prev_nested(info, line, col)
    local char = line:sub(col, col)

    if info.open == info.close or info.open == char then
        for i = col - 1, 1, -1 do
            char = line:sub(i, i)
            local char_info = utils.get_pair(char)
            if char_info then
                return i + 1
            end
        end
    else
        local opening_idx = utils.find_opening(info, line, col - 1)
        if opening_idx then
            local l, r = opening_idx, col - 1
            local last

            for i = r, l, -1 do
                char = line:sub(i, i)
                local char_info = utils.get_pair(char)

                if char_info and char == char_info.close then
                    last = last or i
                    if utils.valid_pair_rev(char_info, line, l, i - 1) then
                        return i + 1
                    end
                end
            end

            return opening_idx + 1 or last
        end
    end
end

---@param pair ntab.pair
---@param line string
---@param col integer
function utils.find_prev_closing(pair, line, col)
    local char = line:sub(col, col)

    local i
    local before_cursor = line:sub(1, col - 1)
    local idx = before_cursor:reverse():find(pair.open, 1, true)

    if pair.open == pair.close then
        i = idx and (col - idx)
    elseif char ~= pair.open then
        i = utils.find_opening(pair, line, col - 1) or idx and (col - idx)
    end

    return i + 1 or utils.find_prev_nested(pair, line, col)
end

---@param pair ntab.pair
---@param line string
---@param col integer
---@param behavior ntab.behavior
---
---@return ntab.md | nil
function utils.find_prev(pair, line, col, behavior)
    local i

    if behavior == "closing" then
        i = utils.find_prev_closing(pair, line, col)
    else
        i = utils.find_prev_nested(pair, line, col)
    end

    if i then
        local prev = {
            pos = i,
            char = line:sub(i, i),
        }

        local next = {
            pos = col + 1,
            char = line:sub(col, col),
        }

        return {
            prev = prev,
            next = next,
            pos = math.min(col - 1, i),
        }
    end
end

---@param x? integer
---@param y? integer
function utils.set_cursor(x, y) --
    if not y or not x then
        local pos = api.nvim_win_get_cursor(0)
        x = x or (pos[2] + 1)
        y = y or (pos[1] + 1)
    end

    api.nvim_win_set_cursor(0, { y - 1, x - 1 })
end

---@param x integer
---@param y? integer
---@param pos? integer[]
function utils.move_cursor(x, y, pos)
    pos = pos or api.nvim_win_get_cursor(0)

    local line = pos[1] + (y or 0)
    local col = pos[2] + (x or 0)

    api.nvim_win_set_cursor(0, { line, col })

    return x
end

---@param str string
function utils.replace(str)
    return api.nvim_replace_termcodes(str, true, true, true)
end

function utils.map(mode, lhs, rhs, opts)
    local options = { noremap = true }

    if opts then
        options = vim.tbl_extend("force", options, opts)
    end

    api.nvim_set_keymap(mode, lhs, rhs, options)
end

return utils
