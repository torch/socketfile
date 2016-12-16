# Files over sockets for Torch

This package adds support for `torch.SocketFile` and
`torch.SocketFileServer` classes in Torch. It is shipped separately from
Torch, as it adds an extra dependency to the `socket` package. However, a
`torch.SocketFile` is a sub-class of `torch.File` and could be used at any
place where a `torch.File` is used.

## Typical usage

First, you must create a file server with `torch.SocketFileServer`:
```lua
server = torch.SocketFileServer{
   port = 8000, -- arbirary port number
   verbose = true   
}

print('running on', server:hostname(), 'at port', server:port())

server:loop()
```

Specify the flag `ipv6 = true` if you are running on a `ipv6` network.

Then, you can have processes opening some `torch.SocketFile`, using the
hostname and port specified above.

```lua
file = torch.SocketFile{
   hostname = <hostname>, -- specify correct hostname here
   port = <port>, -- specify correct port here
   filename = "foobar.txt",
   mode = "w" -- same modes than torch.DiskFile are supported
}
```

Specify the flag `ipv6 = true` if you are running on a `ipv6` network.

The opened file should then support the same methods than `torch.DiskFile`.
```lua
print("> sending string")
file:writeString("hello world\n")

print("> sending 10 numbers")
for i=1,10 do
   file:writeObject(i)
end
```

See example in `test/` directory for more.
