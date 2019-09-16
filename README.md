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
" In vimrc -- note the `!`
packadd! vim-tools
```

Even better -- if you do not _always_ need `vim-tools`, `sbvim` supports lazy
loading by interactively using `:packadd vim-tools`!
