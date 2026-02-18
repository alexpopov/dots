local M = {}

function M.load_latest_session()
  require("persistence").load()
end

function M.save_session()
  require("persistence").save()
end

function M.create_scratch_buffer()
  local dir = "/tmp/nvim." .. os.getenv("USER")
  vim.fn.mkdir(dir, "p")
  local filename = dir .. "/scratch_" .. os.date("%Y%m%d_%H%M%S") .. ".txt"
  vim.cmd.edit(filename)
end

function M.safe_require(module_name)
  local status_ok, module = pcall(require, module_name)
  if not status_ok then
    vim.notify("Couldn't load module '" .. module_name .. "'", vim.log.levels.INFO)
    return nil
  end
  return module
end

function M.show_notify_history()
  local ok, notify = pcall(require, "notify")
  if ok then
    require("telescope").extensions.notify.notify()
  else
    vim.cmd("messages")
  end
end

-- Delete all buffers not visible in any window/tab
function M.delete_hidden_buffers()
  local visible_bufs = {}
  for _, tabpage in ipairs(vim.api.nvim_list_tabpages()) do
    for _, win in ipairs(vim.api.nvim_tabpage_list_wins(tabpage)) do
      visible_bufs[vim.api.nvim_win_get_buf(win)] = true
    end
  end

  local deleted = 0
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_valid(buf) and not visible_bufs[buf] then
      pcall(vim.api.nvim_buf_delete, buf, { force = false })
      deleted = deleted + 1
    end
  end
  vim.notify("Deleted " .. deleted .. " hidden buffers", vim.log.levels.INFO)
end

function M.add_to_para_inbox()
  local inbox = vim.fn.expand("~/gdrive/00_inbox/")
  local template_dir = vim.fn.stdpath("config") .. "/templates/"
  local options = { "Meeting", "Note" }

  vim.ui.select(options, {
    prompt = "Add to PARA Inbox:",
    format_item = function(item)
      return "New " .. item
    end,
  }, function(choice)
    if not choice then return end

    vim.ui.input({ prompt = "Description (spaces ok): " }, function(desc)
      if not desc or desc == "" then return end

      local date_prefix = os.date("%Y_%m_%d")
      local slug = desc:lower():gsub("%s+", "_"):gsub("[^%w_]", "")
      local filename = date_prefix .. "_" .. slug .. ".md"

      local subdir = (choice == "Meeting") and "meetings/" or "notes/"
      local path = inbox .. subdir .. filename
      local template = template_dir .. choice:lower() .. ".md"

      vim.cmd("edit " .. vim.fn.fnameescape(path))

      -- Pre-fill from template if the file is empty (new)
      if vim.api.nvim_buf_line_count(0) <= 1 and vim.api.nvim_buf_get_lines(0, 0, 1, false)[1] == "" then
        local lines = vim.fn.readfile(template)
        if #lines > 0 then
          vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
        end
      end
    end)
  end)
end

return M
