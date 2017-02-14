var http = require("http");
var url = require("url");

var server = http.createServer((req, res) => {
    var query = url.parse(req.url, true).query;
    var user = query.user || req.headers.user;
    if (!user) {
        res.statusCode = 401;
        res.end();
        return;
    }
    res.setHeader("User", user);
    var index = user.indexOf("@");
    if (index > 0 && user.substring(index) === "@microsoft.com") {
        var dtab = "";
        if ("l5d-label" in query) {
            var label = query["l5d-label"];
            if (label) {
                dtab = "/host=>/label/" + label;
            }
        } else {
            dtab = req.headers["l5d-dtab"];
        }
        if (dtab) {
            res.setHeader("l5d-dtab", dtab);
        }
    }
    res.statusCode = 200;
    res.end();
}).listen(32081);

process.on("SIGINT", () => {
    process.exit(130 /* 128 + SIGINT */);
});

process.on("SIGTERM", () => {
    console.log("Terminating...");
    server.close();
});
