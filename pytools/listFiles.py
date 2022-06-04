#!/usr/bin/env python3

import sys
from optparse import OptionParser
from ListSearch import listOrSearchFiles, Lister

parser = OptionParser()
parser.add_option("-p", "--only-in-proj", dest="onlyInProj", help="search in project only", action="store_true", default=False)

(options, args) = parser.parse_args()

print("\n".join(listOrSearchFiles(options.onlyInProj, Lister)))

