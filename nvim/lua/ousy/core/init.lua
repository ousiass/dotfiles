-- nvmのNodeをPATHに追加
local node_path = vim.fn.expand("~/.nvm/versions/node/v22.19.0/bin")
if vim.fn.isdirectory(node_path) == 1 then
  vim.env.PATH = node_path .. ":" .. vim.env.PATH
end

require("ousy.core.options")
require("ousy.core.keymaps")
require("ousy.core.autocmds")