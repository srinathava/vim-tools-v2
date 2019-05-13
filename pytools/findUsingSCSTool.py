#!/usr/bin/env python3

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

sourceDir = '''config
matlab/makerules
matlab/platform
matlab/resources
matlab/rtw
matlab/simulink
matlab/src
matlab/standalone
matlab/test
matlab/toolbox
matlab/tools/memcheck
'''.split()

searchTerm = sys.argv[1]

params = urllib.parse.urlencode({'searchTerm': searchTerm, 
                           'searchField': 'TEXT',
                           'sort': 'FILETYPE',
                           'fileType': fileType, 
                           'sourceDir': sourceDir,
                           'indexName': 'Bmain', 
                           'indexDir': ''
                           }, True)
fullurl = 'http://codesearch.mathworks.com:8080/srcsearch/SearchResults.do?%s' % params
f = urllib.request.urlopen(fullurl)
url_output = f.read()

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
p.feed(url_output.decode('utf-8'))

fullfiles = p.filenames

if len(fullfiles) > NUM_FILES_LIMIT:
    print("Too many file matches (%d)!" % len(fullfiles))
else:
    print('%s' % subprocess.check_output(['grep', '-nH', '-i', searchTerm] + list(fullfiles)).decode('utf-8'))
