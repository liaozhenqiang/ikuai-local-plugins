--[[
  discover.lua —— miIO 广播发现（udp/54321，发现阶段不需要 token）

  用法:
    luajit discover.lua

  输出（一行 JSON）:
    {"devices":[{"did":"...","model":"...","ip":"192.168.9.23","mac":"AA:BB:...","hw_ver":"...","fw_ver":"..."}],"broadcasts":[...]}

  设备事实（references/device-testing.md）:
    * LuaJIT 2.1 自带 cjson；没有 luasocket，用 FFI 调 libc 的 UDP socket
    * 设备没有 timeout/nohup，脚本自己限时约 2 秒
    * 失败一律输出 {"devices":[],"error":"..."}，调用方继续走 ARP 主流程
]]

local ok_cjson, cjson = pcall(require, "cjson")
local function emit(obj)
    if ok_cjson then
        local ok, s = pcall(cjson.encode, obj)
        if ok then
            print(s)
            return
        end
    end
    print('{"devices":[],"error":"cjson encode failed"}')
end

if not ok_cjson then
    print('{"devices":[],"error":"cjson missing"}')
    return
end

local ok_ffi, ffi = pcall(require, "ffi")
if not ok_ffi then
    emit({ devices = {}, error = "ffi unavailable" })
    return
end

local ok_bit, bit = pcall(require, "bit")
if not ok_bit then
    emit({ devices = {}, error = "bit unavailable" })
    return
end

local ok_cdef = pcall(ffi.cdef, [[
typedef unsigned char  uint8_t;
typedef unsigned short uint16_t;
typedef unsigned int   uint32_t;

struct sockaddr_in {
    uint16_t sin_family;
    uint16_t sin_port;
    uint32_t sin_addr;
    uint8_t  sin_zero[8];
};

struct pollfd {
    int   fd;
    short events;
    short revents;
};

int socket(int domain, int type, int protocol);
int setsockopt(int fd, int level, int optname, const void *optval, unsigned int optlen);
int sendto(int fd, const void *buf, unsigned long len, int flags, const void *addr, unsigned int addrlen);
int recvfrom(int fd, void *buf, unsigned long len, int flags, void *addr, unsigned int *addrlen);
int poll(struct pollfd *fds, unsigned long nfds, int timeout);
int close(int fd);
int usleep(unsigned int usec);
]])
if not ok_cdef then
    emit({ devices = {}, error = "ffi cdef failed" })
    return
end

local AF_INET      = 2
local SOCK_DGRAM   = 2
local SOL_SOCKET   = 1
local SO_REUSEADDR = 2
local SO_BROADCAST = 6
local POLLIN       = 1
local MI_PORT      = 54321

local function u32_to_ip(n)
    n = n % 4294967296
    local a = math.floor(n / 16777216) % 256
    local b = math.floor(n / 65536) % 256
    local c = math.floor(n / 256) % 256
    local d = n % 256
    return string.format("%d.%d.%d.%d", a, b, c, d)
end

local function ip_to_u32(s)
    local a, b, c, d = s:match("^(%d+)%.(%d+)%.(%d+)%.(%d+)$")
    if not a then return nil end
    a, b, c, d = tonumber(a), tonumber(b), tonumber(c), tonumber(d)
    if not a or a > 255 or b > 255 or c > 255 or d > 255 then return nil end
    return a * 16777216 + b * 65536 + c * 256 + d
end

local function htons(n)
    return bit.bor(bit.lshift(bit.band(n, 0xff), 8), bit.rshift(n, 8))
end

-- /proc/net/route 里的地址是小端十六进制；直接按主机序算广播地址再转字符串
local function is_private_ip(ip)
    local a, b = ip:match("^(%d+)%.(%d+)%.")
    a, b = tonumber(a), tonumber(b)
    if not a then return false end
    if a == 10 then return true end
    if a == 172 and b >= 16 and b <= 31 then return true end
    if a == 192 and b == 168 then return true end
    return false
end

local function add_target(list, seen, ip)
    if ip and ip ~= "0.0.0.0" and not seen[ip] and is_private_ip(ip) then
        seen[ip] = true
        list[#list + 1] = ip
    end
end

local function broadcast_targets()
    local list, seen = {}, { ["255.255.255.255"] = true }
    list[#list + 1] = "255.255.255.255"

    local f = io.open("/proc/net/route", "r")
    if f then
        f:read("*l")
        for line in f:lines() do
            local iface, dest, gw, _flags, _ref, _use, _metric, mask =
                line:match("^(%S+)%s+(%S+)%s+(%S+)%s+(%S+)%s+(%S+)%s+(%S+)%s+(%S+)%s+(%S+)")
            if iface and iface ~= "lo" and dest ~= "00000000"
               and gw == "00000000" and mask ~= "00000000" then
                -- /proc/net/route 打印的是小端十六进制（192.168.9.0 => 0009A8C0），
                -- 先 bswap 成网络序整数再算广播，否则会得到 255.9.168.192 这种怪地址。
                local net = tonumber(dest, 16)
                local m = tonumber(mask, 16)
                if net and m then
                    local net_be = bit.bswap(net)
                    local mask_be = bit.bswap(m)
                    local brd = bit.bor(bit.band(net_be, mask_be), bit.bnot(mask_be))
                    add_target(list, seen, u32_to_ip(brd))
                end
            end
        end
        f:close()
    end

    -- 路由表看不到 LAN（策略路由 / 多表）时，用 ARP 里的地址反推 /24 广播
    local af = io.open("/proc/net/arp", "r")
    if af then
        af:read("*l")
        for line in af:lines() do
            local ip = line:match("^(%d+%.%d+%.%d+%.%d+)%s+")
            local a, b, c
            if ip then
                -- 注意：不能写 local a,b,c = ip and ip:match(...)，and 会截断多返回值
                a, b, c = ip:match("^(%d+)%.(%d+)%.(%d+)%.")
            end
            if a then
                add_target(list, seen, a .. "." .. b .. "." .. c .. ".255")
            end
        end
        af:close()
    end
    return list
end

-- 广播可能被 AP 隔离/多播抑制；再对 ARP 里每个私网地址发一次单播
local function arp_unicast_targets()
    local list = {}
    local f = io.open("/proc/net/arp", "r")
    if not f then return list end
    f:read("*l")
    for line in f:lines() do
        local ip = line:match("^(%d+%.%d+%.%d+%.%d+)%s+")
        if ip and is_private_ip(ip) then
            list[#list + 1] = ip
        end
    end
    f:close()
    return list
end

local function hello_packet()
    local p = ffi.new("uint8_t[32]")
    p[0], p[1] = 0x21, 0x31
    p[2], p[3] = 0x00, 0x20
    -- 标准 miIO discovery hello: 后 28 字节全 0xFF（python-miio 同款）。
    -- 设备会回 32 字节 header（部分带明文 JSON）；header 里的 did 就够认设备。
    for i = 4, 31 do
        p[i] = 0xFF
    end
    return p
end

local function send_packet(fd, ip, pkt)
    local u = ip_to_u32(ip)
    if not u then return false end
    local sa = ffi.new("struct sockaddr_in")
    sa.sin_family = AF_INET
    sa.sin_port = htons(MI_PORT)
    sa.sin_addr = bit.bswap(u % 4294967296)
    local n = ffi.C.sendto(fd, pkt, 32, 0, sa, ffi.sizeof("struct sockaddr_in"))
    return n == 32
end

local function decode_payload(payload)
    local ok, data = pcall(cjson.decode, payload)
    if not ok or type(data) ~= "table" then return nil end
    return data
end

local function handle_packet(buf, n, sa, devices, seen)
    if n < 32 or buf[0] * 256 + buf[1] ~= 0x2131 then return end
    local total = buf[2] * 256 + buf[3]
    if total < 32 then total = n end
    if total > n then total = n end
    local plen = total - 32

    local data
    if plen > 0 then
        data = decode_payload(ffi.string(ffi.cast("uint8_t*", buf) + 32, plen))
    end

    local params = {}
    if data then
        params = data.params
        if type(params) ~= "table" then params = data.result end
        if type(params) ~= "table" then params = {} end
    end

    local did = buf[8] * 16777216 + buf[9] * 65536 + buf[10] * 256 + buf[11]
    if did == 0 and params.did ~= nil then
        did = tonumber(params.did) or 0
    end

    local srcp = ffi.cast("uint8_t*", sa)
    local src = string.format("%d.%d.%d.%d", srcp[4], srcp[5], srcp[6], srcp[7])

    local mac = data and (params.mac or data.mac) or nil
    local model = data and (params.model or data.model) or nil
    local hw = data and (params.hw_ver or data.hw_ver) or nil
    local fw = data and (params.fw_ver or data.fw_ver) or nil

    -- 很多设备只回 32 字节 header（没有 JSON）；header 里的 did 仍然有效，
    -- 用它认设备，MAC 由 shell 侧按 IP 从 ARP 补。
    if did == 0 and not (type(mac) == "string" and mac ~= "") then return end

    local key
    if did ~= 0 then
        key = tostring(did)
    elseif type(mac) == "string" and mac ~= "" then
        key = mac
    else
        key = src
    end
    if seen[key] then return end
    seen[key] = true

    devices[#devices + 1] = {
        did = did ~= 0 and tostring(did) or "",
        model = type(model) == "string" and model or "",
        ip = src,
        mac = type(mac) == "string" and mac or "",
        hw_ver = type(hw) == "string" and hw or "",
        fw_ver = type(fw) == "string" and fw or "",
    }
end

local function main()
    local fd = ffi.C.socket(AF_INET, SOCK_DGRAM, 0)
    if fd < 0 then
        emit({ devices = {}, error = "socket failed" })
        return
    end

    local one = ffi.new("int[1]", 1)
    pcall(function() ffi.C.setsockopt(fd, SOL_SOCKET, SO_BROADCAST, one, 4) end)
    pcall(function() ffi.C.setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, one, 4) end)

    local targets = broadcast_targets()
    local target_seen = {}
    for _, ip in ipairs(targets) do target_seen[ip] = true end
    for _, ip in ipairs(arp_unicast_targets()) do
        if not target_seen[ip] then
            target_seen[ip] = true
            targets[#targets + 1] = ip
        end
    end

    local pkt = hello_packet()
    local sent = 0
    for _ = 1, 2 do
        for _, ip in ipairs(targets) do
            local ok, r = pcall(send_packet, fd, ip, pkt)
            if ok and r then sent = sent + 1 end
        end
        ffi.C.usleep(50000)
    end

    local devices, seen = {}, {}
    local buf = ffi.new("uint8_t[2048]")
    local sa = ffi.new("struct sockaddr_in")
    local slen = ffi.new("unsigned int[1]")
    local pfd = ffi.new("struct pollfd[1]")
    pfd[0].fd = fd
    pfd[0].events = POLLIN

    -- 100 次 * 20ms 上限 = 2s；有数据时 poll 立刻返回，实际通常 < 0.2s
    local received = 0
    for _ = 1, 100 do
        pfd[0].revents = 0
        local r = ffi.C.poll(pfd, 1, 20)
        if r and r > 0 and bit.band(pfd[0].revents, POLLIN) ~= 0 then
            slen[0] = ffi.sizeof("struct sockaddr_in")
            local n = ffi.C.recvfrom(fd, buf, 2048, 0, sa, slen)
            if n and n > 0 then
                received = received + 1
                handle_packet(buf, n, sa, devices, seen)
            end
        end
    end

    ffi.C.close(fd)

    if #devices == 0 then
        devices = setmetatable({}, { __jsontype = "array" })
    end

    -- 设备端 jq 1.4 不擅长复杂过滤器；这里直接给出 shell 可读的 tsv
    -- 字段顺序: did \x1f model \x1f ip \x1f mac
    local function field(v)
        if type(v) ~= "string" then return "" end
        return (v:gsub("[%z\1-\31\127]", " "))
    end
    local lines = {}
    for _, d in ipairs(devices) do
        lines[#lines + 1] = table.concat({
            field(d.did), field(d.model), field(d.ip), field(d.mac)
        }, "\31")
    end
    emit({
        devices = devices,
        targets = targets,
        sent = sent,
        received = received,
        tsv = table.concat(lines, "\n"),
    })
end

local ok, err = pcall(main)
if not ok then
    emit({ devices = {}, error = tostring(err) })
end
