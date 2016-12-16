require "socketfile"
require "nn"

local cmd = torch.CmdLine()
cmd:argument("-hostname", "server hostname")
cmd:argument("-port", "server port")
cmd:option("-ipv6", false, "use ipv6")
cmd:option("-workdir", "workdir", "where to put temporary files")

local opt = cmd:parse(arg)

local hostname = opt.hostname
local port = tonumber(opt.port)
local ipv6 = opt.ipv6
assert(port, 'number expected for port')
local workdir = opt.workdir
local name = os.tmpname():match("[^/]+$")

print("> filename:", name)

local mlp = nn.Sequential()
mlp:add( nn.Linear(784, 5000) )
mlp:add( nn.Tanh() )
mlp:add( nn.Linear(5000, 5000) )
mlp:add( nn.Tanh() )
mlp:add( nn.Linear(5000, 10) )

local params = mlp:getParameters()
print('> mlp size (mb):', params:size(1)*8/2^20)

print("> mkdir")
torch.SocketFileServer.mkdir{
   hostname = hostname,
   port = port,
   ipv6 = ipv6,
   dir = workdir
}

print("> require")
torch.SocketFileServer.require{
   hostname = hostname,
   port = port,
   ipv6 = ipv6,
   package = "nn"
}

local file = torch.SocketFile{
   hostname = hostname,
   port = port,
   filename = workdir .. "/" .. name,
   ipv6 = ipv6,
   mode = "w"
}

-- check that self is well handled
assert(file:binary() == file)
file:autoSpacing()
print("> sending string")
file:writeString("hello world\n")

print("> sending 10 numbers")
for i=1,10 do
   file:writeObject(i)
end

print("> sending empty torch tensor")
file:writeObject(torch.Tensor())

print("> sending large mlp")
file:writeObject(mlp)

print("> closing file")
file:close()

print("> checking files on server:")
for k, v in pairs(torch.SocketFileServer.files{hostname=hostname, port=port, ipv6=ipv6}) do
   print(k, v)
end

print("> opening file for read")
local file = torch.SocketFile{
   hostname = hostname,
   port = port,
   filename = workdir .. "/" .. name,
   ipv6 = ipv6,
}
file:binary()

print("> reading string")
print(file:readString("*line"))

print("> reading numbers and tensor")
for i=1,11 do
   print(file:readObject())
end
print("> reading (large) mlp")
print(file:readObject())

print("> checking garbage collection")
file = nil
collectgarbage()
collectgarbage()

print("> passed")
