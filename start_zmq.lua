-- start_zmq.lua
function sysCall_init()
    print("[START_ZMQ] Initializing ZMQ Remote API server...")
    
    -- Start the ZMQ remote API server
    simZMQ.startServer(23000)
    
    print("[START_ZMQ] ZMQ Remote API server started on port 23000")
end
