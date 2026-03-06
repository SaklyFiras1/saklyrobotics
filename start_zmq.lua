-- start_zmq.lua
function sysCall_init()
    print("[START_ZMQ] Starting ZeroMQ remote API server...")
    
    local addonHandle = sim.getScript(sim.scripttype_addonscript, -1, "ZeroMQ remote API server")
    if addonHandle ~= -1 then
        sim.callScriptFunction("sysCall_init", addonHandle)
        print("[START_ZMQ] ZeroMQ remote API server initialized successfully")
    else
        print("[START_ZMQ] ERROR: 'ZeroMQ remote API server' add-on not found")
    end
end
