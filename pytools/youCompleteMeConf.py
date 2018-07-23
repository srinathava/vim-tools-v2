#!/usr/bin/env python3
import sys
sys.path += [r'/local/savadhan/sbtools/apps/vim/pytools']

from getCompilationDatabase import getFlags

def FlagsForFile(filename, **kwargs):
    (flags, moduleRoot) = getFlags(filename)
    return {
        'flags': flags,
    }

