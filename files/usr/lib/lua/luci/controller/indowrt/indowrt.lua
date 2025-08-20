module("luci.controller.indowrt.indowrt", package.seeall)

function index()
    entry({"admin", "network", "indowrt"}, call("render_page"), _("Fix TTL"), 100).leaf = true
end

function get_current_ttl()
    local output = luci.sys.exec("nft list chain inet fw4 mangle_postrouting_ttl65 2>/dev/null")
    if output and output:match("ip ttl set (%d+)") then
        return tonumber(output:match("ip ttl set (%d+)"))
    end
    return nil
end

function set_ttl(new_ttl)
    local ttl_file = "/etc/nftables.d/ttl65.nft"
    local ttl_rule = string.format([[
## Fix TTL
chain mangle_postrouting_ttl65 {
    type filter hook postrouting priority 300; policy accept;
    counter ip ttl set %d
}
chain mangle_prerouting_ttl65 {
    type filter hook prerouting priority 300; policy accept;
    counter ip ttl set %d
}
]], new_ttl, new_ttl)

    -- Menyimpan aturan baru ke file
    local f = io.open(ttl_file, "w")
    if f then
        f:write(ttl_rule)
        f:close()
    end

    -- Menerapkan aturan baru
    luci.sys.call("nft -f " .. ttl_file)
    luci.sys.call("/etc/init.d/firewall restart")
end

function render_page()
    local http = require "luci.http"
    local sys = require "luci.sys"
    local tpl = require "luci.template"
    local dispatcher = require "luci.dispatcher"

    -- Mengambil pengaturan TTL saat ini
    local current_ttl = get_current_ttl()

    -- Jika nilai TTL sudah dimasukkan, terapkan nilai TTL baru
    local ttl_value = http.formvalue("ttl_value")
    if ttl_value then
        ttl_value = tonumber(ttl_value)
        if ttl_value and ttl_value >= 1 and ttl_value <= 255 then
            set_ttl(ttl_value)
        end
    end

    tpl.render("indowrt/page", {
        current_ttl = current_ttl or "N/A",  -- Menampilkan TTL saat ini, atau N/A jika tidak ada
        ttl_value = ttl_value or current_ttl
    })
end
