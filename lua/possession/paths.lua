local M = {}

local config = require('possession.config')
local utils = require('possession.utils')

--- Get session path
---@param name string
function M.session(name)
    -- Not technically need but should guard against potential errors
    assert(not vim.endswith(name, '.json'), 'Name should not end with .json')
    local filename = utils.percent_encode(name) .. '.json'
    return vim.fs.joinpath(config.session_dir, filename)
end

--- Get short session path for printing
---@param name string
function M.session_short(name)
    local path = M.session(name)
    return utils.relative_path(path, config.session_dir)
end

---@deprecated
function M.session_name(path)
    vim.deprecate('paths.session_name()', 'session.list() and get name from data', '?', 'possession')
    local data = M.read_file(path)
    return vim.json.decode(data).name
end

--- Get global cwd for use as session name
---@return string
function M.cwd_session_name()
    local global_cwd = vim.fn.getcwd(-1, -1)
    return vim.fn.fnamemodify(global_cwd, ':~')
end

--- Vim expands the given dir, then converts it to an absolute path
-- function M.absolute_dir(dir)
--     local p = Path:new(vim.fn.expand(dir)):absolute()
--     if vim.endswith(p, Path.path.sep) then
--         p = p:sub(1, #p - 1)
--     end
--     return p
-- end

function M.read_file(file)
    local fd = assert(io.open(file, 'r'))
    local contents = fd:read('*a')
    fd:close()
    return contents
end

return M
