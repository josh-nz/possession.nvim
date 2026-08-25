local M = {}

local config = require('possession.config')
local utils = require('possession.utils')

--- Get session path
---@param name string
---@return string
function M.session(name)
    -- Not technically need but should guard against potential errors
    assert(not vim.endswith(name, '.json'), 'Name should not end with .json')
    return vim.fs.joinpath(config.session_dir, utils.percent_encode(name) .. '.json')
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
    return vim.json.decode(vim.fn.readblob(path)).name
end

--- Get global cwd for use as session name
---@return string
function M.cwd_session_name()
    local global_cwd = vim.fn.getcwd(-1, -1)
    return vim.fn.fnamemodify(global_cwd, ':~')
end

--- Resolve a user-facing directory spec (e.g. from config or a command argument) to an absolute
--- path with no trailing separator, suitable for use as a session `cwd` value. Runs `dir` through
--- vim.fn.expand() first, so '~', env vars, and Vim tokens like '%'/'#' are resolved - do not pass
--- a glob pattern here, as expand() would perform wildcard expansion instead of returning it as-is
--- (see utils.abspath() for a pure, non-expanding alternative).
---@param dir string
---@return string
function M.absolute_dir(dir)
    local p = utils.abspath(vim.fn.expand(dir))
    if vim.endswith(p, '/') then
        p = p:sub(1, #p - 1)
    end
    return p
end

return M
