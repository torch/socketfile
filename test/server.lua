require 'socketfile'

local cmd = torch.CmdLine()
cmd:option("-port", 0, "port at which server should run (will find a free port if 0)")
cmd:option("-verbose", false, "print debug messages")
cmd:option("-ipv6", false, "use ipv6")

local opt = cmd:parse(arg)

local server = torch.SocketFileServer{
   port = opt.port,
   ipv6 = opt.ipv6,
   verbose = opt.verbose   
}

print('running on', server:hostname(), 'at port', server:port())

server:loop()
