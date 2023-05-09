local M = {}
local wincmd = 'split'

local create_commands = function()
  vim.api.nvim_create_user_command('EditCodeBlock',
    function(opts) require('ecb').edit_code_block(opts) end,
    {
      nargs = '*',
      complete = function(_, _, _)
        return { "split", "vsplit", "tabnew", "rightbelow", "leftabove" }
      end,
      desc = 'edit embedded code block in new window'
    })
  vim.api.nvim_create_user_command('EditCodeBlockOrg',
    function(opts) require('ecb').edit_code_block_org(opts) end,
    {
      nargs = '*',
      complete = function(_, _, _)
        return { "split", "vsplit", "tabnew", "rightbelow", "leftabove" }
      end,
      desc = 'edit embedded org mode code block in new window'
    })
  vim.api.nvim_create_user_command('EditCodeBlockSelection',
    function(opts) require('ecb').edit_code_block_selection(opts) end,
    {
      nargs = '+',
      complete = function(_, _, _)
        return { "split", "vsplit", "tabnew", "rightbelow", "leftabove" }
      end,
      desc = 'edit selected code in new window',
      range = true
    })
end

M.setup = function(opts)
  create_commands()
  if opts.wincmd then
    wincmd = opts.wincmd
  end
end

local function create_edit_buffer(win_cmd, mdbufnr, row, col, srow, scol, erow, ecol, filetype)
  local mwin = vim.api.nvim_get_current_win()
  local lines
  if ecol ~= 0 then
    lines = vim.api.nvim_buf_get_lines(mdbufnr, srow, erow + 1, false)
  else
    lines = vim.api.nvim_buf_get_lines(mdbufnr, srow, erow, false)
  end
  local pre, post
  if erow - srow + 1 <= #lines then
    post = string.sub(lines[erow - srow + 1], ecol + 1)
    lines[erow - srow + 1] = string.sub(lines[erow - srow + 1], 1, ecol)
  end
  if scol > 0 then
    pre = string.sub(lines[1], 1, scol)
    lines[1] = string.sub(lines[1], scol + 1)
  end
  vim.cmd(win_cmd)
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
  local crow = row - srow
  local ccol
  if crow > 1 then
    ccol = col
  else
    ccol = col - scol
  end
  vim.api.nvim_win_set_cursor(win, { crow, ccol })

  -- Auto commands to update main buffer
  vim.api.nvim_create_autocmd({'BufWrite', 'BufWriteCmd'}, {
    buffer = bufnr,
    callback = function()
      local crow, ccol = unpack(vim.api.nvim_win_get_cursor(win))
      local nlines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, true)
      if #nlines > 0 and pre then
        nlines[1] = pre .. nlines[1]
      end
      if #nlines > 0 and post then
        nlines[#nlines] = nlines[#nlines] .. post
      end
      if ecol ~= 0 then
        vim.api.nvim_buf_set_lines(mdbufnr, srow, erow + 1, true, nlines)
      else
        vim.api.nvim_buf_set_lines(mdbufnr, srow, erow, true, nlines)
      end
      local mcol
      if crow > 1 then
        mcol = ccol
      else
        mcol = ccol + scol
      end
      vim.api.nvim_win_set_cursor(mwin, { crow + srow, mcol })
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

M.edit_code_block = function (opts)
  local win_cmd
  if opts and opts.args and opts.args ~= '' then
    win_cmd = opts.args
  else
    win_cmd = wincmd
  end
  local file_parser = vim.treesitter.get_parser()
  if not file_parser then
    return
  end
  -- Ensure the file gets parsed. Neovim doesn't re-parse the file on changes
  -- unless the tree-sitter highlighter is enabled
  file_parser:parse()
  local row, col = unpack(vim.api.nvim_win_get_cursor(0))
  local range = { row - 1, col, row - 1, col + 1 }
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
      create_edit_buffer(win_cmd, mdbufnr, row, col, srow, scol, erow, ecol, ltree:lang())
    end
  end
end

M.edit_code_block_org = function (opts)
  local win_cmd
  if opts and opts.args and opts.args ~= '' then
    win_cmd = opts.args
  else
    win_cmd = wincmd
  end
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
        -- The cursor may belong to the block but not the contents, adjust
        if erow < row then
          row = erow
        end
        create_edit_buffer(win_cmd, mdbufnr, row, col, srow, scol, erow, ecol, language)
      end
    end
  end
end

M.edit_code_block_selection = function (opts)
  if not opts or not opts.args or opts.args == '' then
    error("You need to specify the file type of the selection")
  end
  local filetype = opts.fargs[1]
  local win_cmd
  if #opts.fargs > 1 then
    win_cmd = table.concat(opts.fargs, ' ', 2)
  else
    win_cmd = wincmd
  end

  local _, srow, scol, _ = unpack(vim.fn.getcharpos("'<"))
  local _, erow, ecol, _ = unpack(vim.fn.getcharpos("'>"))

  local mdbufnr = vim.fn.bufnr()
  local row, col = unpack(vim.api.nvim_win_get_cursor(0))
  create_edit_buffer(win_cmd, mdbufnr, row, col, srow - 1, scol - 1, erow - 1, ecol, filetype)
end

return M
