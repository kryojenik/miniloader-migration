-- Using game provided event_handler.
local handler = require("__core__.lualib.event_handler")

handler.add_libraries({
  require("__flib__.gui"),

  --require("__loaders-modernized__.scripts.migrations"),
  --require("__loaders-modernized__.scripts.loaders-modernized"),
  --require("__loaders-modernized__.scripts.loader-gui")
})

handler.add_lib(require("scripts.from-miniloader"))
