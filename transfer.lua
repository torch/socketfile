local transfer = {}
local socket = require 'socket'

function transfer.hostname()
   return socket.dns.gethostname()
end

function transfer.bind(port, backlog, ipv6)
   local master
   if ipv6 then
      master = assert(socket.tcp6())
   else
      master = assert(socket.tcp())
   end
   assert(master:bind("*", port))
   assert(master:listen(backlog))
   return master
end

function transfer.connect(hostname, port, ipv6, retry)
   retry = retry or math.huge
   local function connect()
      local master
      if ipv6 then
         master = assert(socket.tcp6())
      else
         master = assert(socket.tcp())
      end
      assert(master:connect(hostname, port))
      return master
   end

   local status, client
   repeat
      status, client = pcall(connect)
      retry = retry - 1
      if not status then
         print(
            string.format("Failed to connect <%s:%s> (%s). [Retrying]",
                          hostname, port, client)
         )
         socket.sleep(10)
      end
   until status or retry == 0
   if not status then
      error(
         string.format("Failed to connect <%s:%s> (%s)", hostname, port, client)
      )
   end
   return client
end

-- split transfer into several blocks to circumvent luajit issues
local BLOCKSZ = 2^24 -- 16MB
function transfer.send(c, data)
   data = torch.CharTensor(torch.serializeToStorage(data))
   local size = data:size(1)
   c:send(string.format("0x%0.16x", size))
   local n = 0
   local buffer
   while n < math.floor(size/BLOCKSZ) do
      buffer = buffer or torch.CharTensor(BLOCKSZ)
      buffer:copy(data:narrow(1, n*BLOCKSZ+1, BLOCKSZ))
      local subdata = buffer:storage():string()
      assert(c:send(subdata) == BLOCKSZ, 'send error')
      n = n + 1
   end
   local subdata =
      data:narrow(1, n*BLOCKSZ+1, size % BLOCKSZ):clone():storage():string()
   assert(c:send(subdata) == size % BLOCKSZ, 'send error')
end

function transfer.receive(c)
   local size = assert(c:receive(18), 'receive error')
   size = tonumber(size)
   local data = torch.CharTensor(size)
   local n = 0
   local buffer
   while n < math.floor(size/BLOCKSZ) do
      buffer = buffer or torch.CharTensor(BLOCKSZ)
      local subdata = assert(c:receive(BLOCKSZ), 'receive error')
      assert(#subdata == BLOCKSZ, 'receive error')
      buffer:storage():string(subdata)
      data:narrow(1, n*BLOCKSZ+1, BLOCKSZ):copy(buffer)
      n = n + 1
   end
   local subdata = assert(c:receive(size % BLOCKSZ), 'receive error')
   assert(#subdata == size % BLOCKSZ, 'receive error')
   subdata = torch.CharTensor(torch.CharStorage():string(subdata))
   data:narrow(1, n*BLOCKSZ+1, size % BLOCKSZ):copy(subdata)
   return torch.deserializeFromStorage(data:storage())
end

return transfer
