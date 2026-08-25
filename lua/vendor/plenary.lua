-- Local, trimmed copy of the `Path` module from plenary.nvim (https://github.com/nvim-lua/plenary.nvim),
-- MIT License, Copyright (c) 2020 TJ DeVries. Vendored here so possession.nvim does not depend on
-- plenary.nvim being installed. Only keeps the pieces actually used by this plugin.

local uv = vim.loop

local function if_nil(val, was_nil, was_not_nil)
    if val == nil then
        return was_nil
    else
        return was_not_nil
    end
end

local path = {}
path.home = uv.os_homedir()

path.sep = (function()
    if jit then
        local os = string.lower(jit.os)
        if os ~= 'windows' then
            return '/'
        else
            return '\\'
        end
    else
        return package.config:sub(1, 1)
    end
end)()

path.root = (function()
    if path.sep == '/' then
        return function()
            return '/'
        end
    else
        return function(base)
            base = base or uv.cwd()
            return base:sub(1, 1) .. ':\\'
        end
    end
end)()

local function is_root(pathname)
    if path.sep == '\\' then
        return string.match(pathname, '^[A-Z]:\\?$')
    end
    return pathname == '/'
end

local _split_by_separator = (function()
    local formatted = string.format('([^%s]+)', path.sep)
    return function(filepath)
        local t = {}
        for str in string.gmatch(filepath, formatted) do
            table.insert(t, str)
        end
        return t
    end
end)()

local function is_uri(filename)
    return string.match(filename, '^%a[%w+-.]*://') ~= nil
end

local function is_absolute(filename, sep)
    if sep == '\\' then
        return string.match(filename, '^[%a]:[\\/].*$') ~= nil
    end
    return string.sub(filename, 1, 1) == sep
end

local function _normalize_path(filename, cwd)
    if is_uri(filename) then
        return filename
    end

    -- handles redundant `./` in the middle
    local redundant = path.sep .. '%.' .. path.sep
    if filename:match(redundant) then
        filename = filename:gsub(redundant, path.sep)
    end

    local out_file = filename

    local has = string.find(filename, path.sep .. '..', 1, true) or string.find(filename, '..' .. path.sep, 1, true)

    if has then
        local is_abs = is_absolute(filename, path.sep)
        local split_without_disk_name = function(filename_local)
            local parts = _split_by_separator(filename_local)
            -- Remove disk name part on Windows
            if path.sep == '\\' and is_abs then
                table.remove(parts, 1)
            end
            return parts
        end

        local parts = split_without_disk_name(filename)
        local idx = 1
        local initial_up_count = 0

        repeat
            if parts[idx] == '..' then
                if idx == 1 then
                    initial_up_count = initial_up_count + 1
                end
                table.remove(parts, idx)
                table.remove(parts, idx - 1)
                if idx > 1 then
                    idx = idx - 2
                else
                    idx = idx - 1
                end
            end
            idx = idx + 1
        until idx > #parts

        local prefix = ''
        if is_abs or #split_without_disk_name(cwd) == initial_up_count then
            prefix = path.root(filename)
        end

        out_file = prefix .. table.concat(parts, path.sep)
    end

    return out_file
end

local function clean(pathname)
    if is_uri(pathname) then
        return pathname
    end

    -- Remove double path seps, it's annoying
    pathname = pathname:gsub(path.sep .. path.sep, path.sep)

    -- Remove trailing path sep if not root
    if not is_root(pathname) and pathname:sub(-1) == path.sep then
        return pathname:sub(1, -2)
    end
    return pathname
end

---@class vendor.plenary.Path
local Path = {
    path = path,
}

Path.__index = function(t, k)
    local raw = rawget(Path, k)
    if raw then
        return raw
    end

    if k == '_cwd' then
        local cwd = uv.fs_realpath('.')
        t._cwd = cwd
        return cwd
    end

    if k == '_absolute' then
        local absolute = uv.fs_realpath(t.filename)
        t._absolute = absolute
        return absolute
    end
end

Path.__div = function(self, other)
    assert(Path.is_path(self))
    assert(Path.is_path(other) or type(other) == 'string')

    return self:joinpath(other)
end

Path.is_path = function(a)
    return getmetatable(a) == Path
end

function Path:new(...)
    local args = { ... }

    if type(self) == 'string' then
        table.insert(args, 1, self)
        self = Path -- luacheck: ignore
    end

    local path_input
    if #args == 1 then
        path_input = args[1]
    else
        path_input = args
    end

    -- If we already have a Path, it's fine.
    --   Just return it
    if Path.is_path(path_input) then
        return path_input
    end

    local sep = path.sep
    if type(path_input) == 'table' then
        sep = path_input.sep or path.sep
        path_input.sep = nil
    end

    local path_string
    if type(path_input) == 'table' then
        local path_objs = {}
        for _, v in ipairs(path_input) do
            if Path.is_path(v) then
                table.insert(path_objs, v.filename)
            else
                assert(type(v) == 'string')
                table.insert(path_objs, v)
            end
        end

        path_string = table.concat(path_objs, sep)
    else
        assert(type(path_input) == 'string', vim.inspect(path_input))
        path_string = path_input
    end

    local obj = {
        filename = path_string,

        _sep = sep,
    }

    setmetatable(obj, Path)

    return obj
end

function Path:_fs_filename()
    return self:absolute() or self.filename
end

function Path:_stat()
    return uv.fs_stat(self:_fs_filename()) or {}
end

function Path:joinpath(...)
    return Path:new(self.filename, ...)
end

function Path:absolute()
    if self:is_absolute() then
        return _normalize_path(self.filename, self._cwd)
    else
        return _normalize_path(self._absolute or table.concat({ self._cwd, self.filename }, self._sep), self._cwd)
    end
end

function Path:exists()
    return not vim.tbl_isempty(self:_stat())
end

function Path:is_absolute()
    return is_absolute(self.filename, self._sep)
end

function Path:make_relative(cwd)
    if is_uri(self.filename) then
        return self.filename
    end

    self.filename = clean(self.filename)
    cwd = clean(if_nil(cwd, self._cwd, cwd))
    if self.filename == cwd then
        self.filename = '.'
    else
        if cwd:sub(#cwd, #cwd) ~= path.sep then
            cwd = cwd .. path.sep
        end

        if self.filename:sub(1, #cwd) == cwd then
            self.filename = self.filename:sub(#cwd + 1, -1)
        end
    end

    return self.filename
end

function Path:normalize(cwd)
    if is_uri(self.filename) then
        return self.filename
    end

    self:make_relative(cwd)

    -- Substitute home directory w/ "~"
    -- string.gsub is not useful here because usernames with dashes at the end
    -- will be seen as a regexp pattern rather than a raw string
    local home = path.home
    if string.sub(path.home, -1) ~= path.sep then
        home = home .. path.sep
    end
    local start, finish = string.find(self.filename, home, 1, true)
    if start == 1 then
        self.filename = '~' .. path.sep .. string.sub(self.filename, (finish + 1), -1)
    end

    return _normalize_path(clean(self.filename), self._cwd)
end

local function check_self(self)
    if type(self) == 'string' then
        return Path:new(self)
    end

    return self
end

function Path:_read()
    self = check_self(self)

    local fd = assert(uv.fs_open(self:_fs_filename(), 'r', 438)) -- for some reason test won't pass with absolute
    local stat = assert(uv.fs_fstat(fd))
    local data = assert(uv.fs_read(fd, stat.size, 0))
    assert(uv.fs_close(fd))

    return data
end

function Path:read()
    return self:_read()
end

function Path:write(txt, flag, mode)
    assert(flag, [[Path:write requires a flag! For example: 'w' or 'a']])

    mode = mode or 438

    local fd = assert(uv.fs_open(self:_fs_filename(), flag, mode))
    assert(uv.fs_write(fd, txt, -1))
    assert(uv.fs_close(fd))
end

return Path
