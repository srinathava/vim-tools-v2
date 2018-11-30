'''
Minimal clang-rename integration with Vim.

Before installing make sure one of the following is satisfied:

* clang-rename is in your PATH
* `g:clang_rename_path` in ~/.vimrc points to valid clang-rename executable
* `binary` in clang-rename.py points to valid to clang-rename executable

To install, simply put this into your ~/.vimrc

    noremap <leader>cr :pyf <path-to>/clang-rename.py<cr>

IMPORTANT NOTE: Before running the tool, make sure you saved the file.

All you have to do now is to place a cursor on a variable/function/class which
you would like to rename and press '<leader>cr'. You will be prompted for a new
name if the cursor points to a valid symbol.
'''

from __future__ import print_function
import vim
import subprocess
import sys
import tempfile

def main():
    if vim.current.buffer.options['modified']:
        print('Current buffer needs to be saved to run refactoring')
        return

    binary = '/mathworks/hub/share/sbtools/external-apps/llvm/llvm-7.0.0/install/deb9-64/bin/clang-rename'

    # Get arguments for clang-rename binary.
    offset = int(vim.eval('line2byte(line("."))+col(".")')) - 2
    if offset < 0:
        print('Couldn\'t determine cursor position. Is your file empty?', file=sys.stderr)
        return

    origname = vim.eval('expand("<cword>")')
    new_name_request_message = 'type new name:'
    new_name = vim.eval("input('Enter new name: ', '%s')" % origname)

    filename = vim.current.buffer.name
    compile_commands_str = subprocess.check_output(['getCompilationDatabase.py', filename])

    tempdir = tempfile.mkdtemp()
    jsonfile = path.join(tempdir, 'compile_commands.json')
    open(jsonfile, 'w+b').write(compile_commands_str)

    # Call clang-rename.
    command = [binary,
               filename,
               '-i',
               '-p', tempdir,
               '-offset', str(offset),
               '-new-name', str(new_name)]

    print("Patience! This might take a little while...")

    # FIXME: make it possible to run the tool on unsaved file.
    p = subprocess.Popen(command,
                         stdout=subprocess.PIPE,
                         stderr=subprocess.PIPE)
    stdout, stderr = p.communicate()

    if stderr:
        print(stderr, file=sys.stderr)

    # Reload all buffers in Vim.
    vim.command("checktime")

if __name__ == '__main__':
    main()
