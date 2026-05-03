return {
  "folke/snacks.nvim",
  priority = 1000,
  lazy = false,
  opts = {
    bigfile = { enabled = true },
    dashboard = {
      enabled = true,
      sections = {
        { section = "header" },
        { section = "keys", gap = 1, padding = 1 },
        { section = "startup" },
      },
    },
    notifier = { enabled = true },
    quickfile = { enabled = true },
    statuscolumn = { enabled = false },
    words = { enabled = true },
    lazygit = { enabled = true },
  },
  keys = {
    { "<leader>gg", function() Snacks.lazygit() end, desc = "Lazygit" },
    { "<leader>gf", function() Snacks.lazygit.log_file() end, desc = "Lazygit File History" },
    { "<leader>gl", function() Snacks.lazygit.log() end, desc = "Lazygit Log" },
    { "<leader>n", function() Snacks.notifier.show_history() end, desc = "Notification History" },
    { "<leader>un", function() Snacks.notifier.hide() end, desc = "Dismiss Notifications" },
  },
}
