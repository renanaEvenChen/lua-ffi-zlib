local bit = require 'bit'
local ffi_zlib = require("ffi-zlib")

local ngx_log = ngx.log
local ngx_ERR = ngx.ERR

local band = bit.band
local lshift = bit.lshift
local table_concat = table.concat
local table_insert = table.insert
local string_sub = string.sub
local string_byte = string.byte


local function bget(gzf , i)
  local byte = string_byte(gzf, i)
  if not byte then
    return nil
  end
  return byte
end

-- get the gzip header size from file gzf
--https://www.ietf.org/rfc/rfc1952.txt
local function gzhead(gzf)
    local flags
    local size = 10

     --verify gzip magic header and compression method
    if (bget(gzf, 1) ~= 31 or bget(gzf, 2) ~= 139 or bget(gzf, 3) ~= 8) then
        ngx_log(ngx_ERR, " is not a valid gzip file")
        return 1
      end

    -- get and verify flags
    flags = bget(gzf, 4)

    if (band(flags , 0xe0) ~= 0) then --224
        ngx_log(ngx_ERR,"unknown reserved bits set gzf ", flags)
      end
    -- add modification time, extra flags, and os

    -- add extra field if present
    if band(flags , 4) ~= 0 then
        local len
        len = bget(gzf, 12)
        --len = len + lshift(bget(gzf, 12) , 8) --<<
        size = size + len + 2
    end

    -- add file name if present
    if band(flags , 8) ~= 0 then
        size = size + 1
        while (bget(gzf, size) ~= 0) do
          size = size + 1
        end
      end

    -- add comment if present
    if band(flags , 16) ~= 0 then
      size = size + 1
        while (bget(gzf, size) ~= 0) do
          size = size + 1
      end
    end

    -- add header crc if present
    if band(flags , 2) ~= 0 then
       size = size + 2
      end

      return size
end

-- str - uncompressed string
-- gz - compressed gzip string
-- Returns compressed concatenation of str and gz
function gz_concat(str, gz)

  local count = 0
    local input = function(bufsize)
      local start = count > 0 and bufsize*count or 1
      local finish = (bufsize*(count+1)-1)
      count = count + 1
      if bufsize == 1 then
        start = count
        finish = count
      end
      local data = str:sub(start, finish)
      if #data == 0 then
        return nil
      end
      return data
    end

    local output_table = {}
    local output = function(data)
      table_insert(output_table, data)
    end

    local Z_SYNC_FLUSH = 2
    local ok, err = ffi_zlib.deflateGzip(input, output, Z_SYNC_FLUSH)
    if not ok then
      ngx_log(ngx_ERR, err)
    end

    local gz_str = table_concat(output_table,'')
    local head_size = gzhead(gz)
    return gz_str..string.sub(gz, head_size+1, -1)

end


local M = {
  _VERSION = '0.1.0',
}

M.gz_concat = gz_concat

return M
