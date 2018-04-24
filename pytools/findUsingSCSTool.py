#!/usr/bin/env python

import urllib.request, urllib.parse, urllib.error
from os import path
import subprocess
import sys

from html.parser import HTMLParser
import re
import urllib.request, urllib.parse, urllib.error

FILE_PATTERN = re.compile('file=([^&]+)')
NUM_FILES_LIMIT = 5000

fileType = '''M
Model
Java
C++
Fortran
Header
C
XML
Resource
TLC
Makefile
MTF
Requirements'''.split()

sourceDir = '''src
simulink/src
toolbox
standalone
makerules
rtw
stateflow
simulink'''.split()

searchTerm = sys.argv[1]

params = urllib.parse.urlencode({'searchTerm': searchTerm, 
                           'searchField': 'TEXT',
                           'sort': 'PATH',
                           'fileType': fileType, 
                           'sourceDir': sourceDir,
                           'indexId': 17, 
                           'indexDir': ''
                           }, True)
fullurl = 'http://codesearch.mathworks.com:8080/srcsearch/SearchResults.do?%s' % params
# print fullurl
f = urllib.request.urlopen(fullurl)
url_output = f.read()
# print url_output
fullfiles = []

class MyParser(HTMLParser):
    def __init__(self):
        HTMLParser.__init__(self)
        self.filenames = set()

    def handle_starttag(self, tag, attrs):
        if tag == 'span':

            filename = None
            for (n, v) in attrs:
                if n == 'onmouseover':
                    filename = v
                    break

            if filename:
                m = FILE_PATTERN.search(filename)
                if m:
                    filename = urllib.parse.unquote(m.group(1))
                    self.filenames.add(filename)

                    if len(self.filenames) > NUM_FILES_LIMIT:
                        raise ValueError("TooManyFiles")

p = MyParser();
try:
    p.feed(url_output)
except:
    pass

fullfiles = set()

p.feed(url_output)
for filename in p.filenames:
    fullpath = path.join('matlab', filename)
    fullfiles.add(fullpath)

if len(fullfiles) > NUM_FILES_LIMIT:
    print("Too many file matches (%d)!" % len(fullfiles))
else:
    print(subprocess.Popen(['grep', '-nH', '-i', searchTerm] + list(fullfiles), stdout=subprocess.PIPE).communicate()[0])
