local _M = {}
local lfs = require("lfs")
local PATH = require("path")
_M.apply = function (rules)
    rules = rules or {}
    local succeed = plist.write("/var/mobile/Library/Preferences/ch.xxtou.webkitnetworkingdumper.plist", rules)
    notify_post("ch.xxtou.webkitnetworkingdumper/ReloadRules")
    return succeed
end
_M.path = app("com.apple.mobilesafari"):data_path() .. "/Library/Caches/com.apple.WebKit.Networking/ch.xxtou.webkitnetworkingdumper"
local clean_dir = function (path)
    if file.exists(path) == "directory" then
        PATH.each(path .. "/*", function(P, mode)
            if mode == 'directory' then
                PATH.rmdir(P)
            else
                PATH.remove(P)
            end
        end, {
            param = "fm";   -- request full path and mode
            delay = true;   -- use snapshot of directory
            recurse = true; -- include subdirs
            reverse = true; -- subdirs at first
        })
    end
end
_M.clear = function ()
    return clean_dir(_M.path)
end
_M.host_path = function (host)
    return _M.path .. "/" .. host
end
_M.host_clear = function (host)
    local host_path = _M.host_path(host)
    return clean_dir(host_path)
end
local localized_sort = function (arr)
    table.sort(arr, function (a, b)
        return a:localized_compare(b) > 0
    end)
    return arr
end
local _item_names = function (host, item, extension)
    item = item or ""
    local host_path = _M.host_path(host)
    if file.exists(host_path) ~= "directory" then
        return {}, false
    end
    local _, dir = lfs.dir(host_path)
    local first = false
    local tab = {}
    while true do
        local entry = dir:next()
        if not entry then
            break
        end
        if entry ~= "." and entry ~= ".." then
            local f_name, f_ext = PATH.splitext(entry)
            if not extension or f_ext == extension then
                if f_name:find(item .. "_", 1, true) == 1 then
                    table.insert(tab, entry)
                end
            end
        end
    end
    tab = localized_sort(tab)
    dir:close()
    return tab, first
end
_M.hosts = function ()
    local _, dir = lfs.dir(_M.path)
    local tab = {}
    while true do
        local entry = dir:next()
        if not entry then
            break
        end
        if entry ~= "." and entry ~= ".." then
            table.insert(tab, entry)
        end
    end
    tab = localized_sort(tab)
    dir:close()
    return tab
end
_M.item_paths = function (host, item, ext)
    local host_path = _M.host_path(host)
    local tab, first = _item_names(host, item, ext)
    if first then
        table.insert(tab, item)
    end
    local tabp = {}
    for _, v in ipairs(tab) do
        table.insert(tabp, host_path .. "/" .. v)
    end
    return tabp
end
_M.req_header_paths = function (host, item)
    return _M.item_paths(host, item, ".req-header")
end
_M.req_body_paths = function (host, item)
    return _M.item_paths(host, item, ".req-body")
end
_M.resp_header_paths = function (host, item)
    return _M.item_paths(host, item, ".resp-header")
end
_M.resp_body_paths = function (host, item)
    return _M.item_paths(host, item, ".resp-body")
end
_M.latest_item_path = function (host, item, ext)
    local host_path = _M.host_path(host)
    local tab, first = _item_names(host, item, ext)
    if #tab == 0 and first then
        return host_path .. "/" .. item
    end
    if #tab == 0 then
        return nil
    end
    return host_path .. "/" .. tab[1]
end
_M.latest_req_header_path = function (host, item)
    return _M.latest_item_path(host, item, ".req-header")
end
_M.latest_req_body_path = function (host, item)
    return _M.latest_item_path(host, item, ".req-body")
end
_M.latest_resp_header_path = function (host, item)
    return _M.latest_item_path(host, item, ".resp-header")
end
_M.latest_resp_body_path = function (host, item)
    return _M.latest_item_path(host, item, ".resp-body")
end
return _M