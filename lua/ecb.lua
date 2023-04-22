local M = {}

local create_commands = function()
  vim.api.nvim_create_user_command('EditCodeBlock', function() require('ecb').edit_code_block() end, { desc = 'edit embedded code block in new window' })
end

M.setup = function(opts)
  create_commands()
end

M.edit_code_block = function ()
  local file_parser = vim.treesitter.get_parser()
  if not file_parser then
    return
  end
  local row, col = unpack(vim.api.nvim_win_get_cursor(0))
  local range = { row, col, row, col }
  local ltree = file_parser:language_for_range(range)
  if not ltree then
    return
  end

  local trees = ltree:trees()
  for _, tree in ipairs(trees) do
    local node = tree:root()
    if vim.treesitter.node_contains(node, range) then
      local mdbufnr = vim.fn.bufnr()
      local srow, scol, erow, ecol = node:range(false)
      local lines = vim.api.nvim_buf_get_lines(mdbufnr, srow, erow, false)

      local filetype = ltree:lang()
      vim.cmd('split')
      local win = vim.api.nvim_get_current_win()
      local bufnr = vim.api.nvim_create_buf(true, false)
      -- Set buffer options
      -- We want to keep the temporaty buffers and their link to the parent,
      -- even when they are hidden. To delete them, use `bd` or `:q!`
      vim.api.nvim_buf_set_option(bufnr, 'bufhidden', 'hide')
      vim.api.nvim_buf_set_option(bufnr, 'buftype', 'acwrite')
      vim.api.nvim_buf_set_option(bufnr, 'swapfile', false)
      vim.api.nvim_buf_set_option(bufnr, 'filetype', filetype)
      local bufname = bufnr .. ':' .. vim.api.nvim_buf_get_name(mdbufnr) .. ':' .. srow .. '-' .. erow
      vim.api.nvim_buf_set_name(bufnr, bufname)
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, true, lines)
      -- Set as not modified
      vim.api.nvim_buf_set_option(bufnr, 'modified', false)
      vim.api.nvim_win_set_buf(win, bufnr)
      -- Calculate cursor position in new window
      vim.api.nvim_win_set_cursor(win, { row - srow, col - scol })

      -- Auto commands to update main buffer
      vim.api.nvim_create_autocmd({'BufWrite', 'BufWriteCmd'}, {
        buffer = bufnr,
        callback = function()
          local nlines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, true)
          vim.api.nvim_buf_set_lines(mdbufnr, srow, erow, true, nlines)
          -- Set as not modified
          vim.api.nvim_buf_set_option(bufnr, 'modified', false)
        end,
      })
      vim.api.nvim_create_autocmd({'BufUnload'}, {
        buffer = bufnr,
        callback = function()
          -- Unlist the buffer and make sure it is wiped out next time if
          -- someone loads it by mistake
          vim.api.nvim_buf_set_option(bufnr, 'bufhidden', 'wipe')
          vim.api.nvim_buf_set_option(bufnr, 'buflisted', false)
        end,
      })
    end
  end
end

return M
