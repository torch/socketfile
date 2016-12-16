local argcheck = require 'argcheck'
local transfer = require 'socketfile.transfer'

local SocketFile = torch.class('torch.SocketFile', 'torch.File')

SocketFile.__init = argcheck{
   {name="self", type="torch.SocketFile"},
   {name="hostname", type="string"},
   {name="port", type="number"},
   {name="filename", type="string"},
   {name="mode", type="string", default="r"},
   {name="quiet", type="boolean", default=false},
   {name="ipv6", type="boolean", default=false},
   call =
      function(self, hostname, port, filename, mode, quiet, ipv6)
         local SocketFileServer = require "socketfile.socketfileserver"
         self.__hostname = hostname
         self.__port = port
         self.__ipv6 = ipv6
         self.__id = SocketFileServer.command(
            "open", hostname, port, ipv6, nil, filename, mode, quiet
         )
         if rawget(_G, 'newproxy') then -- lua 5.1?
            self.__gc = newproxy(true)
            getmetatable(self.__gc).__gc =
               function()
                  if self.__id then
                     self:close()
                  end
               end
         end
      end
}

-- lua 5.2
function SocketFile:__gc()
   if self.__id then
      self:close()
   end
end

-- methods are filled up by socketfileserver.lua

return SocketFile
