local net = require("@lune/net");

-- This is the "http.createServer" of Lune
net.serve(8080, function(request)
    print("Got request:", request.method, request.path)
    
    return {
        status = 200,
        
        body = "Hello from Lune Express",
    }
end)