# vim-tools

The original SBTools Vim experience, by Srinath Avadhanula.

## History

This distribution of plugins previously resided under SBTOOLS/apps/vim as an
optional improvement over the minimal settings set by the SBTOOLS/vimrc intended
for use with C++ development.

With the creation of `sbvim`, the work done by Srinath has been converted to a
package within the larger `sbvim` optional package system.

This enables developers to easily opt-in to these plugins.

## Installation

Assuming you are using `sbvim` (by sourcing the `sbvim/vimrc`), installing all
of the tools in this package should be as simple as:

```vim
" In vimrc
packadd vim-tools
```

If you are not using `sbvim`, you can install this by manually sourcing the
following file:

```vim
" In vimrc
source /path/to/vim-tools/plugin/setup.vim
```
