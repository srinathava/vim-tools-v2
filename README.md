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
## Contributing

This only applies to people who are interested in contributing to sbvim-tools.

```bash
mkdir -p ~/.vim/pack/mw/opt
cd ~/.vim/pack/mw/opt
# Notice that we are cloning into vim-tools-dev locally to distinguish from vim-tools
git clone git@insidelabs-git.mathworks.com:sbtools/sbvim/vim-tools.git vim-tools-dev
```

Now change your `~/.vimrc` to do something like:

```vim
let $SBVIM_CFG = 'base'  " your choice here, see `:h sbvim-cfgs`
source //mathworks/hub/share/sbtools/vimrc
packadd! vim-tools-dev
```

Notice `vim-tools-dev` instead of `vim-tools`. This lets you use the version of `vim-tools-dev` in your `~/.vim/pack`. Make modifications etc. When you are happy, 

```bash
cd ~/.vim/pack/mw/opt/vim-tools-dev
# git commit etc.
git push
```
This only pushes to this repo, but does not yet publish to the `sbvim-runtime` mirror. To do that:

```bash
cd $d # or wherever you wish to keep this
git clone git@insidelabs-git.mathworks.com:sbtools/sbvim/sbvim-runtime.git
cd sbvim-runtime
./ci/bumpdeps.sh
git commit # Make sure to add some text like "updating sbvim-tools"
git push
```

After some time (a few hours typically), the changes will appear in the sbvim-runtime mirror.
