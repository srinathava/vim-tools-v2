local pickers = require "telescope.pickers"
local finders = require "telescope.finders"
local conf = require("telescope.config").values
local actions = require "telescope.actions"
local action_state = require "telescope.actions.state"
local entry_display = require "telescope.pickers.entry_display"

local function gen_from_commands(_)
  local displayer = entry_display.create {
    separator = "▏",
    items = {
      { width = 5 },
      { width = 30 },
      { remaining = true },
    },
  }

  local make_display = function(entry)
    entry = entry.entry
    return displayer {
      entry.shortcut,
      entry.cmd,
      entry.description,
    }
  end

  return function(entry)
    return {
      entry = entry,
      value = entry,
      valid = true,
      -- ordinal is used to filter the entry w.r.t user typed text
      ordinal = entry.shortcut .. entry.cmd .. entry.description,
      display = make_display,
    }
  end
end

local function command_picker(opts, results)
  opts = opts or require("telescope.themes").get_dropdown{
    layout_config = {
      height=math.min(40, #results + 4)
    }
  }
  pickers.new(opts, {
    prompt_title = "colors",
    finder = finders.new_table {
          results = results,
          entry_maker = gen_from_commands(),
        },
    sorter = conf.generic_sorter(opts),
    attach_mappings = function(prompt_bufnr, _)
          actions.select_default:replace(function()
            actions.close(prompt_bufnr)
            local selection = action_state.get_selected_entry()
            vim.cmd(selection.entry.cmd)
          end)
          return true
        end,
  }):find()
end

pickers.commands = function(opts)
  command_picker(opts, {
    {shortcut="fp", cmd="MWFindInProject", description="Find in project"},
    {shortcut="fs", cmd="MWFindInSolution", description="Find in solution"},
    {shortcut="cp", cmd="MWCompileProject", description="sbmake module"},
    {shortcut="cf", cmd="MWCompileFile", description="sbcc file"},
    {shortcut="op", cmd="MWOpenFile", description="Open file in solution"},
    {shortcut="sp", cmd="MWSetProjectCompileLevel", description="Set sbmake flags"},
    {shortcut="sf", cmd="MWSetFileCompileLevel", description="Set sbcc flags"},
    {shortcut="dc", cmd="MWDebugUnitTest current", description="Current unit/pkg test"},
    {shortcut="dt", cmd="MWDebugCurrentTestPoint", description="Current test point"},
    {shortcut="is", cmd="MWDiffWithOther", description="Diff with another sandbox"},
    {shortcut="ir", cmd="MWDiffWithArchive", description="Diff with backing job"},
    {shortcut="il", cmd="MWDiffWithLKG", description="Diff with latest_pass"},
    {shortcut="",   cmd="MWSplitWithOther", description="Open same file from other sandbox"},
    {shortcut="",   cmd="MWSplitWithOther archive", description="Open same file from backing job"},
    {shortcut="",   cmd="MWSplitWithOther lkg", description="Open same file from latest_pass"},
    {shortcut="ti", cmd="MWInitVimTags", description="Initialize Vim tags"},
    {shortcut="ta", cmd="MWAddIncludeForSymbol", description="Add include for current symbol"},
    {shortcut="rm", cmd="MWRunMATLABLoadSL", description="Run MATLAB (with Simulink load at startup)"},
    {shortcut="cv", cmd="MWOpenCoverageReport", description="Open coverage report for current file"},
  })
end

pickers.gdb = function(opts)
  command_picker(opts, {
    {shortcut="",  cmd="Termdebug", description="Start Gdb"},
    {shortcut="",  cmd="ShowGdb", description="Show Command Window"},
    {shortcut="s", cmd="Step", description="Step Into <F11>"},
    {shortcut="n", cmd="Next", description="Step Over <F10>"},
    {shortcut="o", cmd="Finish", description="Step Out  <Shift-F11>"},
    {shortcut="u", cmd="Until", description="Run until cursor"},
    {shortcut="r", cmd="Run", description="Run program"},
    {shortcut="c", cmd="Continue", description="Continue <F5>"},
    {shortcut="",  cmd="Stop", description="Interrupt <Ctrl-C>"},
    {shortcut="",  cmd="GDB kill", description="Kill <Shift-F5>"},
    {shortcut="u", cmd="GDB up", description="Up Stack (caller)  U"},
    {shortcut="d", cmd="GDB down", description="Down Stack (callee) D"},
    {shortcut="f", cmd="GDB frame ", description="Goto Frame"},
    {shortcut="w", cmd="Stack", description="Show Stack"},
    {shortcut="a", cmd="Attach", description="Attach"},
    {shortcut="q", cmd="QuickAttach", description="Quick Attach"},
    {shortcut="",  cmd="GDB handle SIGSEGV stop print", description="Handle SIGSEGV"},
    {shortcut="",  cmd="GDB handle SIGSEGV nostop noprint", description="Ignore SIGSEGV"},
  })
end

pickers.files = function()
  local projdir = vim.fn['mw#utils#GetRootDir']()
  local opts = {}

  if string.len(projdir) > 0 then
    opts = {cwd=projdir}
    local insideSb = vim.fn.filereadable(projdir .. '/mw_anchor')
    if insideSb then
      opts = vim.fn.extend(opts, {find_command={'listFiles.py'}})
    end
  end
  return require('telescope.builtin').find_files(opts)
end

return pickers
