#!/usr/bin/env python3

import sys
from ListSearch import listOrSearchFiles, Finder

if __name__ == "__main__":
    print("\n".join(listOrSearchFiles(0, Finder)))
