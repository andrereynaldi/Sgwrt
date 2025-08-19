module("luci.controller.contribute", package.seeall)

function index()
    entry({"admin", "contribute"}, template("contribute"), _("Contribute"), 90).dependent = false
end
