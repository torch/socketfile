local argcheck = require 'argcheck'
local transfer = require 'socketfile.transfer'
local unpack = unpack or table.unpack

local SocketFile = require "socketfile.socketfile"
local SocketFileServer = torch.class('torch.SocketFileServer')

-- a fake class to serialize "self"
torch.class('torch.__SocketFileSelf__')
local SocketFileSelf = torch.__SocketFileSelf__()

SocketFileServer.__init = argcheck{
   doc = [[
<a name="SocketFileServer">
#### torch.SocketFileServer(@ARGP)
@ARGT

Creates a file server.

If `port` is not provided, a free port will be taken.  To avoid networking
errors, it is important to put `ipv6` at true if your network supports
ipv6.  With `verbose` at `true`, the server will print commands which are
currently running, or additional debug messages.

]],
   noordered=true,
   {name="self", type="torch.SocketFileServer"},
   {name="port", type="number", opt=true},
   {name="backlog", type="number", default=32},
   {name="ipv6", type="boolean", default=false},
   {name="verbose", type="boolean", default=false},
   call =
      function(self, port, backlog, ipv6, verbose)
         self.__backlog = backlog
         self.__ipv6 = ipv6
         self.__verbose = verbose
         self.__nid = 0
         if port and port > 0 then
            self.__server = transfer.bind(port, backlog, ipv6)
            self.__port = port
         else
            self.__server = transfer.bind(0, backlog, ipv6)
            local _, port = self.__server:getsockname()
            self.__port = port
         end
         self.__hostname = transfer.hostname()
      end
}

function SocketFileServer:hostname()
   return self.__hostname
end

function SocketFileServer:port()
   return self.__port
end

-- queue a command on the server
-- note that the first argument in ... is id (or nil)
function SocketFileServer.command(cmd, hostname, port, ipv6, ...)
   local c = transfer.connect(hostname, port, ipv6)
   transfer.send(c, cmd)
   transfer.send(c, {...})
   local ret = transfer.receive(c)
   c:close()
   if not ret.status then
      error(ret.res)
   else
      return unpack(ret.res)
   end
end

function SocketFileServer:__xcall(client, func, files, ...)
   local status, res = pcall(
      function(...)
         return {func(self, files, ...)}
      end,
      ...
   )
   if not status and self.__verbose then
      print(string.format("$ command error: <%s>", res))
   end
   transfer.send(client, {status=status, res=res})
end

local commands = {}

function commands.require(self, _files, pkg)
   require(pkg)
end

SocketFileServer.require = argcheck{
   {name="hostname", type="string"},
   {name="port", type="number"},
   {name="ipv6", type="boolean", default=false},
   {name="package", type="string"},
   call =
      function(hostname, port, ipv6, pkg)
         SocketFileServer.command("require", hostname, port, ipv6, pkg)
      end
}

function commands.mkdir(self, _files, dir)
   os.execute(string.format('mkdir -p "%s"', dir))
end

SocketFileServer.mkdir = argcheck{
   {name="hostname", type="string"},
   {name="port", type="number"},
   {name="ipv6", type="boolean", default=false},
   {name="dir", type="string"},
   call =
      function(hostname, port, ipv6, dir)
         SocketFileServer.command("mkdir", hostname, port, ipv6, dir)
      end
}

function commands.files(self, files)
   local tbl = {}
   for id, file in pairs(files) do
      tbl[id] = file.name
   end
   return tbl
end

SocketFileServer.files = argcheck{
   {name="hostname", type="string"},
   {name="port", type="number"},
   {name="ipv6", type="boolean", default=false},
   call =
      function(hostname, port, ipv6)
         return SocketFileServer.command("files", hostname, port, ipv6)
      end
}

function commands.open(self, files, _, name, mode, quiet)
   self.__nid = self.__nid + 1 -- make sure we never overlap
   local id = self.__nid
   files[id] = {
      name = name,
      handle = torch.DiskFile(name, mode, quiet)
   }
   return id
end

-- handle self serialization in DiskFile
local function __self2placeholder(self, ...)
   local args = {...}
   for i=1,#args do
      if args[i] == self then
         args[i] = SocketFileSelf
      end
   end
   return unpack(args)
end

local function __placeholder2self(self, ...)
   local args = {...}
   for i=1,#args do
      if torch.typename(args[i]) == "torch.__SocketFileSelf__" then
         args[i] = self
      end
   end
   return unpack(args)
end

SocketFileServer.registermethod = argcheck{
   {name="name", type="string"},
   {name="client", type="function", opt=true},
   {name="server", type="function", opt=true},
   call =
      function(name, clientf, serverf)
         clientf = clientf or
            function(self, ...)
               assert(self.__id, 'trying to operate on a closed file')
               return __placeholder2self(
                  self,
                  SocketFileServer.command(
                     name, self.__hostname, self.__port, self.__ipv6,
                     self.__id, ...
                  )
               )
            end
         serverf = serverf or
            function(self, files, id, ...)
               assert(id and files[id], string.format("invalid id <%s>", id))
               return __self2placeholder(
                  files[id].handle,
                  files[id].handle[name](files[id].handle, ...)
               )
            end
         SocketFile[name] = clientf
         commands[name] = serverf
      end
}

SocketFileServer.registermethod{
   name = "close",
   client =
      function(self)
         assert(self.__id, 'trying to operate on a closed file')
         local id = self.__id
         self.__id = nil
         SocketFileServer.command(
            "close", self.__hostname, self.__port, self.__ipv6, id
         )
      end,
   server =
      function(self, files, id)
         assert(id and files[id], string.format("invalid id <%s>", id))
         files[id].handle:close()
         files[id] = nil
      end
}

local methods = {
   'readByte',
   'readChar',
   'readShort',
   'readInt',
   'readLong',
   'readFloat',
   'readDouble',
   'readObject',
   'writeByte',
   'writeChar',
   'writeShort',
   'writeInt',
   'writeLong',
   'writeFloat',
   'writeDouble',
   'writeObject',
   'readString',
   'writeString',
   'ascii',
   'autoSpacing',
   'binary',
   'clearError',
   'noAutoSpacing',
   'synchronize',
   'pedantic',
   'position',
   'quiet',
   'seek',
   'seekEnd',
   'hasError',
   'isQuiet',
   'isReadable',
   'isWritable',
   'isAutoSpacing',
   'bigEndianEncoding',
   'isBigEndianCPU',
   'isLittleEndianCPU',
   'littleEndianEncoding',
   'nativeEndianEncoding',
   'longSize',
   'noBuffer',
}

for _, method in ipairs(methods) do
   SocketFileServer.registermethod(method)
end

SocketFileServer.loop = argcheck{
   doc = [[
<a name="SocketFileServer">
#### torch.SocketFileServer(@ARGP)
@ARGT

Starts the event loop of a master server. The loop will exit only when an
`exit` command is issued by a slave version of the master server.
]],
   {name="self", type="torch.SocketFileServer"},
   call =
      function(self)
         assert(self.__server, 'server is not running')
         local files = {}
         -- loop forever waiting for clients
         while true do
            -- wait for a connection from any client
            local client = self.__server:accept()
            -- make sure we don't block waiting for this client's line
            client:settimeout(nil)--10)
            -- receive the line
            local cmd = transfer.receive(client)
            local args = transfer.receive(client)
            if type(cmd) == 'string' then
               if self.__verbose then
                  if args[1] and files[args[1]] then
                     print(string.format(
                              "CMD: <%s> on <%s>",
                              cmd,
                              files[args[1]].name)
                     )
                  else
                     print(string.format("CMD: <%s>", cmd))
                  end
               end
               if cmd == 'exit' then
                  self:__xcall( -- ACK
                     client,
                     function()
                     end
                  )
                  break
               elseif commands[cmd] then
                  self:__xcall(
                     client,
                     commands[cmd],
                     files,
                     unpack(args)
                  )
               else
                  self:__xcall(
                     client,
                     function()
                        error(string.format("unknown command <%s>", cmd))
                     end
                  )
               end
            end
            client:close()
         end
         self.__server:close()
         self.__server = nil
      end
}

return SocketFileServer
