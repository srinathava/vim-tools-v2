# vim-tools

Project management and GDB integration specific to MathWorks environments.
See:

https://confluence.mathworks.com/display/STAT/Vim+Setup+for+Sandbox+Development

## Installation

Assuming you are using `sbvim` (by sourcing the `sbvim/vimrc`), installing all
of the tools in this package should be as simple as:

```vim
let $SBVIM_CFG = 'base'  " your choice here, see `:h sbvim-cfgs`
source //mathworks/hub/share/sbtools/vimrc
packadd! vim-tools
```
