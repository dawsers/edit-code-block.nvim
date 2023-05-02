local M = {}

local create_commands = function()
  vim.api.nvim_create_user_command('EditCodeBlock', function() require('ecb').edit_code_block() end, { desc = 'edit embedded code block in new window' })
  vim.api.nvim_create_user_command('EditOrgCodeBlock', function() require('ecb').edit_org_code_block() end, { desc = 'edit embedded org mode code block in new window' })
end

M.setup = function()
  create_commands()
end

local function create_edit_buffer(mdbufnr, row, col, srow, scol, erow, filetype)
  local mwin = vim.api.nvim_get_current_win()
  local lines = vim.api.nvim_buf_get_lines(mdbufnr, srow, erow, false)
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
  vim.api.nvim_win_set_cursor(win, { row - srow, col })

  -- Auto commands to update main buffer
  vim.api.nvim_create_autocmd({'BufWrite', 'BufWriteCmd'}, {
    buffer = bufnr,
    callback = function()
      local crow, ccol = unpack(vim.api.nvim_win_get_cursor(0))
      local nlines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, true)
      vim.api.nvim_buf_set_lines(mdbufnr, srow, erow, true, nlines)
      vim.api.nvim_win_set_cursor(mwin, { crow + srow, ccol })
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

M.edit_code_block = function ()
  local file_parser = vim.treesitter.get_parser()
  if not file_parser then
    return
  end
  -- Ensure the file gets parsed. Neovim doesn't re-parse the file on changes
  -- unless the tree-sitter highlighter is enabled
  file_parser:parse()
  
  local row, col = unpack(vim.api.nvim_win_get_cursor(0))
  local range = { row - 1, col, row - 1, col }
  local ltree = file_parser:language_for_range(range)
  if not ltree then
    return
  end

  local trees = ltree:trees()
  for _, tree in ipairs(trees) do
    local node = tree:root()
    if vim.treesitter.node_contains(node, range) then
      local mdbufnr = vim.fn.bufnr()
      local srow, scol, erow, _ = node:range(false)
      create_edit_buffer(mdbufnr, row, col, srow, scol, erow, ltree:lang())
    end
  end
end

M.edit_org_code_block = function ()
  local file_parser = vim.treesitter.get_parser()
  if not file_parser then
    return
  end
  -- Ensure the file gets parsed. Neovim doesn't re-parse the file on changes
  -- unless the tree-sitter highlighter is enabled
  file_parser:parse()
  
  local node = vim.treesitter.get_node()
  if not node then
    return
  end
  while node and node:type() ~= 'block' do
    node = node:parent()
  end

  if not node then
    return
  end

  -- Print code block
  local name, parameter, contents
  for child, field in node:iter_children() do
    if child:named() then
      if field == 'name' then
        name = child
      -- Only want the first parameter, which is the language name
      elseif field == 'parameter' and not parameter then
        parameter = child
      elseif field == 'contents' then
        contents = child
      end
    end
  end

  local mdbufnr = vim.fn.bufnr()
  if name then
    local srow, scol, erow, ecol = name:range(false)
    local btype = string.upper(table.concat(vim.api.nvim_buf_get_text(mdbufnr, srow, scol, erow, ecol, {})))
    if btype == 'SRC' and parameter then
      srow, scol, erow, ecol = parameter:range(false)
      local language = string.match(table.concat(vim.api.nvim_buf_get_text(mdbufnr, srow, scol, erow, ecol, {})), '%S*')
      if contents then
        srow, scol, erow, ecol = contents:range(false)
        local row, col = unpack(vim.api.nvim_win_get_cursor(0))
        create_edit_buffer(mdbufnr, row, col, srow, scol, erow, language)
      end
    end
  end
end

return M
