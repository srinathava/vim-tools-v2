#!/usr/bin/env python3

from __future__ import print_function
import re, time
import subprocess
import sys
import os
from subprocess import getoutput

def startMatlab(extraArgs):
    if ('-nojvm' in extraArgs) or ('-nodesktop' in extraArgs):
        useXterm = True
    else:
        useXterm = False

    runonserver = ''
    if os.environ.get('RUNONSERVER') == '1':
        runonserver = 'xterm -e runonserver '
        useXterm = False  # no need for separate Xterm. runonserver already runs in xterm

    if useXterm:
        pid = subprocess.Popen(runonserver + 'xterm -e sb -skip-sb-startup-checks ' + extraArgs, shell=True).pid
    else:
        pid = subprocess.Popen(runonserver + 'sb -skip-sb-startup-checks ' + extraArgs, shell=True).pid

    if runonserver:
        return 0
        
    # wait for the correct MATLAB process to be loaded.
    n = 0
    while 1:
        pst = getoutput('pstree -p %d' % pid)
        m = re.search(r'MATLAB\((\d+)\)', pst)
        if m:
            return int(m.group(1))

        time.sleep(0.5)
        n += 1
        if n == 10:
            return 0

if __name__ == "__main__":
    pid = startMatlab(' '.join(sys.argv[1:]))
    print(pid)
