-- 新規タブでターミナルモードを起動
vim.api.nvim_set_keymap("n", "tt", "<cmd>terminal<CR>", { silent = true })

-- 下分割でターミナルモードを起動
vim.api.nvim_set_keymap("n", "tx", "<cmd>belowright new<CR><cmd>terminal<CR>", { silent = true })

-- ターミナルを開いたら常にinsertモードに入る
vim.api.nvim_create_autocmd("TermOpen", {
  pattern = "*",
  command = "startinsert",
})

vim.api.nvim_create_autocmd("TermOpen", {
  pattern = "*",
  callback = function()
    vim.opt_local.relativenumber = false
    vim.opt_local.number = false
  end,
})

-- ターミナルモードを終了するためのキーマッピング
vim.api.nvim_set_keymap("t", "<C-q>", "<C-\\><C-n><cmd>q<CR>", { noremap = true })
